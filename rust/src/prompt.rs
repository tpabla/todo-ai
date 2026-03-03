use serde::Deserialize;
use serde_json::Value;

// Load prompt templates from markdown files at compile time
const SYSTEM_PROMPT: &str = include_str!("../prompts/system.md");
const SEARCH_REPLACE_RULES: &str = include_str!("../prompts/search_replace_rules.md");
const EXAMPLES: &str = include_str!("../prompts/examples.md");
const TODO_INSTRUCTIONS: &str = include_str!("../prompts/todo_instructions.md");
const PROJECT_SCAN_INSTRUCTIONS: &str = include_str!("../prompts/project_scan_instructions.md");

/// Build the system prompt (schema description + rules + examples).
/// This is the direct port of prompt_config.get_schema_description().
pub fn get_system_prompt() -> String {
    format!(
        "{system}\n\nIMPORTANT RULES:\n{rules}\n\n{examples}",
        system = SYSTEM_PROMPT,
        rules = SEARCH_REPLACE_RULES,
        examples = EXAMPLES,
    )
}

/// Context passed from Lua for prompt building.
#[derive(Debug, Deserialize)]
pub struct PromptContext {
    pub instruction: Option<String>,
    pub file_content: Option<String>,
    pub file_path: Option<String>,
    pub filename: Option<String>,
    pub language: Option<String>,
    pub selected_text: Option<String>,
    pub line_number: Option<u32>,
    pub end_line: Option<u32>,
    pub surrounding_lines: Option<Value>,
    pub cached_context: Option<Value>,
    pub other_buffers: Option<Vec<BufferInfo>>,
    pub project_todos: Option<String>,
    pub mode: Option<String>,
    pub is_visual: Option<bool>,
    pub is_todo: Option<bool>,
    pub is_chat: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct BufferInfo {
    pub filename: Option<String>,
    pub name: Option<String>,
    pub filetype: Option<String>,
    #[serde(rename = "type")]
    pub type_: Option<String>,
}

impl BufferInfo {
    fn display_name(&self) -> &str {
        self.filename
            .as_deref()
            .or(self.name.as_deref())
            .unwrap_or("unknown")
    }

    fn display_type(&self) -> &str {
        self.filetype
            .as_deref()
            .or(self.type_.as_deref())
            .unwrap_or("text")
    }
}

/// Build the user prompt based on context.
/// Port of prompt_builder.build_user_prompt().
pub fn build_user_prompt(context: &PromptContext) -> String {
    let instruction = context.instruction.as_deref().unwrap_or("");

    // Visual selection mode
    if context.is_visual.unwrap_or(false) || context.selected_text.as_ref().is_some_and(|s| !s.is_empty()) {
        return build_visual_prompt(context, instruction);
    }

    // TODO mode
    if context.is_todo.unwrap_or(false) || (context.line_number.is_some() && !context.is_chat.unwrap_or(false)) {
        return build_todo_prompt(context, instruction);
    }

    // Project scan mode
    if context.mode.as_deref() == Some("project_scan") {
        return build_project_scan_prompt(context, instruction);
    }

    // Chat / general mode
    build_chat_prompt(context, instruction)
}

fn build_context_info(context: &PromptContext) -> String {
    let mut info = String::new();

    if let Some(ref cached) = context.cached_context {
        if let Ok(json) = serde_json::to_string(cached) {
            info.push_str("\n\nProject Context:\n");
            info.push_str(&json);
        }
    }

    if let Some(ref buffers) = context.other_buffers {
        if !buffers.is_empty() {
            info.push_str("\n\nOther Open Files:\n");
            for buf in buffers {
                info.push_str(&format!("- {} ({})\n", buf.display_name(), buf.display_type()));
            }
        }
    }

    info
}

fn build_visual_prompt(context: &PromptContext, instruction: &str) -> String {
    let context_info = build_context_info(context);

    format!(
        r#"File: {file_path}
Language: {language}
{context_info}

Full file content:
{file_content}

Selected text (lines {start}-{end}):
{selected_text}

Task: {instruction}

Use SEARCH/REPLACE format where "search" is the selected text and "replace" is the improved version."#,
        file_path = context.file_path.as_deref().unwrap_or("unknown"),
        language = context.language.as_deref().unwrap_or("unknown"),
        context_info = context_info,
        file_content = context.file_content.as_deref().unwrap_or(""),
        start = context.line_number.unwrap_or(0),
        end = context.end_line.or(context.line_number).unwrap_or(0),
        selected_text = context.selected_text.as_deref().unwrap_or(""),
        instruction = instruction,
    )
}

fn build_todo_prompt(context: &PromptContext, instruction: &str) -> String {
    let context_info = build_context_info(context);

    // Extract TODO line and indentation from surrounding_lines
    let (todo_line, indentation) = extract_todo_info(context);
    let indent_display = indentation.replace('\t', "\\t");
    let indent_len = indentation.len();
    let indent_type = if indentation.contains('\t') { "tabs" } else { "spaces" };

    let surrounding_json = context
        .surrounding_lines
        .as_ref()
        .and_then(|v| serde_json::to_string(v).ok())
        .unwrap_or_else(|| "[]".to_string());

    format!(
        r#"File: {file_path}
Language: {language}
{context_info}

Full file content:
{file_content}

TODO at line {line}: {instruction}
Current line indentation: "{indent_display}" ({indent_len} {indent_type})
Exact TODO line content: {todo_line_json}

Context around TODO:
{surrounding}

{todo_instructions}

INDENTATION: Copy EXACTLY from the search text - "{indent_display}" ({indent_len} {indent_type})

Example for your response - use logical blocks when appropriate:"#,
        file_path = context.file_path.as_deref().unwrap_or("unknown"),
        language = context.language.as_deref().unwrap_or("unknown"),
        context_info = context_info,
        file_content = context.file_content.as_deref().unwrap_or(""),
        line = context.line_number.unwrap_or(0),
        instruction = instruction,
        indent_display = indent_display,
        indent_len = indent_len,
        indent_type = indent_type,
        todo_line_json = serde_json::to_string(&todo_line).unwrap_or_else(|_| "\"\"".to_string()),
        surrounding = surrounding_json,
        todo_instructions = TODO_INSTRUCTIONS,
    )
}

fn extract_todo_info(context: &PromptContext) -> (String, String) {
    if let Some(Value::Array(lines)) = &context.surrounding_lines {
        for line in lines {
            if line.get("is_target").and_then(|v| v.as_bool()).unwrap_or(false) {
                let content = line
                    .get("content")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                let indentation = content
                    .chars()
                    .take_while(|c| c.is_whitespace())
                    .collect::<String>();
                return (content.to_string(), indentation);
            }
        }
    }
    (String::new(), String::new())
}

fn build_project_scan_prompt(context: &PromptContext, instruction: &str) -> String {
    format!(
        "Task: {instruction}\n\nProject TODOs to process:\n{todos}\n\n{instructions}",
        instruction = instruction,
        todos = context.project_todos.as_deref().unwrap_or(""),
        instructions = PROJECT_SCAN_INSTRUCTIONS,
    )
}

fn build_chat_prompt(context: &PromptContext, instruction: &str) -> String {
    let context_str = context
        .file_content
        .as_deref()
        .or(context.file_path.as_deref())
        .unwrap_or("");

    format!(
        r#"Task: {instruction}

Context:
{context}

Provide appropriate response using the JSON schema. Use "code_snippet" for examples, "changes" for file modifications."#,
        instruction = instruction,
        context = context_str,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_system_prompt_contains_key_elements() {
        let prompt = get_system_prompt();
        assert!(prompt.contains("mode"));
        assert!(prompt.contains("changes"));
        assert!(prompt.contains("chat"));
        assert!(prompt.contains("search"));
        assert!(prompt.contains("replace"));
        assert!(prompt.contains("filename"));
        assert!(prompt.contains("explanation"));
    }

    #[test]
    fn test_system_prompt_includes_rules() {
        let prompt = get_system_prompt();
        assert!(prompt.contains("IMPORTANT RULES:"));
        assert!(prompt.contains("Maximum 1-3 changes per response"));
    }

    #[test]
    fn test_system_prompt_includes_examples() {
        let prompt = get_system_prompt();
        assert!(prompt.contains("GOOD EXAMPLE"));
        assert!(prompt.contains("BAD EXAMPLE"));
    }

    #[test]
    fn test_build_chat_prompt() {
        let ctx = PromptContext {
            instruction: Some("hello".to_string()),
            file_content: Some("some code".to_string()),
            file_path: None,
            filename: None,
            language: None,
            selected_text: None,
            line_number: None,
            end_line: None,
            surrounding_lines: None,
            cached_context: None,
            other_buffers: None,
            project_todos: None,
            mode: None,
            is_visual: None,
            is_todo: None,
            is_chat: Some(true),
        };
        let prompt = build_user_prompt(&ctx);
        assert!(prompt.contains("Task: hello"));
        assert!(prompt.contains("some code"));
    }

    #[test]
    fn test_build_visual_prompt() {
        let ctx = PromptContext {
            instruction: Some("refactor this".to_string()),
            file_content: Some("full file".to_string()),
            file_path: Some("test.py".to_string()),
            filename: Some("test.py".to_string()),
            language: Some("python".to_string()),
            selected_text: Some("selected code".to_string()),
            line_number: Some(10),
            end_line: Some(15),
            surrounding_lines: None,
            cached_context: None,
            other_buffers: None,
            project_todos: None,
            mode: None,
            is_visual: Some(true),
            is_todo: None,
            is_chat: None,
        };
        let prompt = build_user_prompt(&ctx);
        assert!(prompt.contains("Selected text (lines 10-15)"));
        assert!(prompt.contains("selected code"));
        assert!(prompt.contains("refactor this"));
    }

    #[test]
    fn test_build_todo_prompt() {
        let ctx = PromptContext {
            instruction: Some("fix the bug".to_string()),
            file_content: Some("code here".to_string()),
            file_path: Some("main.rs".to_string()),
            filename: Some("main.rs".to_string()),
            language: Some("rust".to_string()),
            selected_text: None,
            line_number: Some(42),
            end_line: None,
            surrounding_lines: Some(serde_json::json!([
                {"content": "    // TODO: fix the bug", "is_target": true}
            ])),
            cached_context: None,
            other_buffers: None,
            project_todos: None,
            mode: None,
            is_visual: None,
            is_todo: Some(true),
            is_chat: None,
        };
        let prompt = build_user_prompt(&ctx);
        assert!(prompt.contains("TODO at line 42"));
        assert!(prompt.contains("fix the bug"));
        assert!(prompt.contains("4 spaces"));
        // Verify it includes content from the md file
        assert!(prompt.contains("OPTIMIZE FOR LOGICAL BLOCKS"));
    }

    #[test]
    fn test_build_project_scan_prompt() {
        let ctx = PromptContext {
            instruction: Some("process all".to_string()),
            file_content: None,
            file_path: None,
            filename: None,
            language: None,
            selected_text: None,
            line_number: None,
            end_line: None,
            surrounding_lines: None,
            cached_context: None,
            other_buffers: None,
            project_todos: Some("TODO: fix thing\nTODO: add stuff".to_string()),
            mode: Some("project_scan".to_string()),
            is_visual: None,
            is_todo: None,
            is_chat: None,
        };
        let prompt = build_user_prompt(&ctx);
        assert!(prompt.contains("Project TODOs"));
        assert!(prompt.contains("TODO: fix thing"));
        // Verify it includes content from the md file
        assert!(prompt.contains("LOGICAL ORDER for developer review"));
    }

    #[test]
    fn test_context_info_with_buffers() {
        let ctx = PromptContext {
            instruction: Some("test".to_string()),
            file_content: Some("code".to_string()),
            file_path: Some("test.py".to_string()),
            filename: None,
            language: Some("python".to_string()),
            selected_text: Some("selected".to_string()),
            line_number: Some(1),
            end_line: Some(5),
            surrounding_lines: None,
            cached_context: None,
            other_buffers: Some(vec![
                BufferInfo {
                    filename: Some("utils.py".to_string()),
                    name: None,
                    filetype: Some("python".to_string()),
                    type_: None,
                },
            ]),
            project_todos: None,
            mode: None,
            is_visual: Some(true),
            is_todo: None,
            is_chat: None,
        };
        let prompt = build_user_prompt(&ctx);
        assert!(prompt.contains("utils.py (python)"));
    }
}
