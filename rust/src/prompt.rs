use crate::protocol::PromptResult;

/// SEARCH/REPLACE rules shared between schema and prompt
const SEARCH_REPLACE_RULES: &[&str] = &[
    "CRITICAL: Maximum 1-3 changes per response - NEVER exceed this limit!",
    "If task requires more than 3 changes, do a SUBSET and explain what's next",
    "When user says 'continue', pick up from where you left off",
    "Break large tasks into logical chunks (e.g. first 3 methods, then next 3)",
    "Bias towards combining continuous/adjacent changes into one diff",
    "Group related changes logically - each diff should be one cohesive unit",
    "Include complete context - if changing a function, include the whole function",
    "The 'search' must match EXACTLY what's in the file (indentation, whitespace)",
    "The 'replace' should be the complete replacement for that logical section",
    "Continuous changes should usually be combined unless they're unrelated concerns",
    "'description' MUST reference the specific TODO - e.g. 'Convert to martini per TODO request'",
    "NEVER use generic descriptions like 'Change 1', 'Update function 2' - be specific!",
    "Changes are applied sequentially in the order provided",
    "Related functions (get_X, make_X, display_X) should be ONE change, not three",
    "ORDER changes in logical progression - dependencies first, then dependent code",
    "When changing multiple files, order by: 1) core/library files, 2) implementation files, 3) tests",
    "Each change block should be self-contained and reviewable as a logical unit",
];

/// Build the system prompt (schema description)
pub fn get_schema_description() -> String {
    let rules: Vec<String> = SEARCH_REPLACE_RULES
        .iter()
        .enumerate()
        .map(|(i, rule)| format!("{}. {}", i + 1, rule))
        .collect();

    format!(
        r#"CRITICAL: Respond with ONLY pure JSON - no markdown wrapping around the JSON itself!

MANDATORY: Your response MUST start with {{ and end with }}

REQUIRED: Every response MUST include "mode" field at the root level

FIRST, DETERMINE THE RESPONSE MODE BY UNDERSTANDING USER INTENT:

Ask yourself: "Does the user want me to CHANGE their code or just UNDERSTAND it?"

Use mode="changes" when the user wants code to be different:
- They use words like "create", "make", "build", "generate", "write", "add", "implement"
- They say "create the missing files" or "generate the functions"
- They describe a problem that needs fixing
- They want new functionality added
- They're asking for improvements or optimizations
- They want something to work differently
- They're describing desired behavior that doesn't exist yet
- They reference missing imports or undefined functions that need to be created

Use mode="chat" when the user wants understanding:
- They use words like "what", "why", "how", "explain", "tell me about"
- They're asking what their code does
- They want to know how something works
- They're asking why something happens
- They want concepts explained
- They're debugging and need to understand current behavior
- They're asking about their code without implying changes

CRITICAL: When in doubt about file creation, if the user mentions "create", "make", or "generate" in relation to files or code, ALWAYS use mode="changes". Users expect action when they request creation.

RESPONSE FORMAT: Raw JSON object with ONE of these two structures:

FOR CODE CHANGES (mode="changes"):
{{
  "mode": "changes",
  "filename": "string (REQUIRED)",
  "changes": [
    {{
      "search": "string (REQUIRED)",
      "replace": "string (REQUIRED)",
      "description": "string"
    }}
  ],
  "language": "string (auto-detected)",
  "explanation": "string (REQUIRED)"
}}

CRITICAL FILE HANDLING RULES:
- The "filename" field is ABSOLUTELY REQUIRED for mode="changes"
- The "mode" field MUST be included at the root level of your JSON
- Always specify the EXACT filename when making code changes
- For NEW FILE creation: use empty string "" for search, full content for replace
- ONLY ONE FILE PER RESPONSE - This is MANDATORY
- NEVER combine multiple files in one response

SCOPED CHANGES - CRITICAL LIMITS:
- MAXIMUM 1-3 changes per response - this prevents token limits
- If task needs more changes, do a logical subset and explain what's next
- When user says "continue", pick up exactly where you left off

FOR CONVERSATIONAL RESPONSES (mode="chat"):
{{
  "mode": "chat",
  "explanation": "string (REQUIRED)"
}}

DO NOT wrap the JSON in ```json``` or any other markdown formatting!
Return ONLY the raw JSON object.

CONTEXT PROVIDED:
You will receive comprehensive context including:
- File content and surrounding code
- LSP diagnostics (errors, warnings) for current file AND all open buffers
- Code symbols and structure from language servers
- Type information and documentation on hover
- Project structure and other open files

IMPORTANT RULES:
{}"#,
        rules.join("\n")
    )
}

/// Build user prompt for visual selection mode
fn build_visual_prompt(
    instruction: &str,
    file_path: &str,
    language: &str,
    file_content: &str,
    line_number: usize,
    end_line: usize,
    selected_text: &str,
    context_info: &str,
) -> String {
    format!(
        r#"File: {}
Language: {}
{}

Full file content:
{}

Selected text (lines {}-{}):
{}

Task: {}

Use SEARCH/REPLACE format where "search" is the selected text and "replace" is the improved version."#,
        file_path, language, context_info, file_content, line_number, end_line, selected_text,
        instruction
    )
}

/// Build user prompt for TODO mode
fn build_todo_prompt(
    instruction: &str,
    file_path: &str,
    language: &str,
    file_content: &str,
    line_number: usize,
    indentation: &str,
    todo_line: &str,
    surrounding_lines: &str,
    context_info: &str,
) -> String {
    let indent_count = indentation.len();
    let indent_type = if indentation.contains('\t') {
        "tabs"
    } else {
        "spaces"
    };
    let indent_display = indentation.replace('\t', "\\t");

    format!(
        r#"File: {}
Language: {}
{}

Full file content:
{}

TODO at line {}: {}
Current line indentation: "{}" ({} {})
Exact TODO line content: {}

Context around TODO:
{}

CRITICAL INSTRUCTIONS FOR SEARCH/REPLACE:
1. OPTIMIZE FOR LOGICAL BLOCKS: Combine related changes into larger, cohesive replacements
2. When multiple functions/sections work together, replace them as ONE logical unit
3. "search": Include ALL related code that forms a logical block (entire functions, classes, or sections)
4. "replace": The complete new implementation for the entire logical block
5. REDUCE DEVELOPER BURDEN: Use fewer, larger changes instead of many small ones
6. INDENTATION: Copy EXACTLY from the search text - "{}" ({} {})
7. "description": Describe the logical transformation, not just mechanical changes

DIFF OPTIMIZATION GUIDELINES:
- Group related changes logically - what makes sense to review together?
- Include complete context - whole functions, not just individual lines
- Minimize review burden - aim for 2-3 cohesive diffs instead of 5-7 tiny ones
- Think like a reviewer - what would you want to approve as one unit?"#,
        file_path,
        language,
        context_info,
        file_content,
        line_number,
        instruction,
        indent_display,
        indent_count,
        indent_type,
        todo_line,
        surrounding_lines,
        indent_display,
        indent_count,
        indent_type
    )
}

/// Build user prompt for chat mode
fn build_chat_prompt(instruction: &str, context: &str) -> String {
    format!(
        r#"Task: {}

Context:
{}

Provide appropriate response using the JSON schema. Use "code_snippet" for examples, "changes" for file modifications."#,
        instruction, context
    )
}

/// Build user prompt based on context
pub fn build_user_prompt(instruction: &str, context: &serde_json::Value) -> String {
    // Check for visual selection mode
    if let Some(selected_text) = context.get("selected_text").and_then(|v| v.as_str()) {
        if !selected_text.is_empty() {
            let file_path = context
                .get("file_path")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");
            let language = context
                .get("language")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");
            let file_content = context
                .get("file_content")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let line_number = context
                .get("line_number")
                .and_then(|v| v.as_u64())
                .unwrap_or(0) as usize;
            let end_line = context
                .get("end_line")
                .and_then(|v| v.as_u64())
                .unwrap_or(line_number as u64) as usize;

            let context_info = build_context_info(context);

            return build_visual_prompt(
                instruction,
                file_path,
                language,
                file_content,
                line_number,
                end_line,
                selected_text,
                &context_info,
            );
        }
    }

    // Check for TODO mode
    if let Some(line_number) = context.get("line_number").and_then(|v| v.as_u64()) {
        let file_path = context
            .get("file_path")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown");
        let language = context
            .get("language")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown");
        let file_content = context
            .get("file_content")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        // Extract TODO line and indentation from surrounding lines
        let (todo_line, indentation) = extract_todo_info(context, line_number as usize);
        let surrounding = context
            .get("surrounding_lines")
            .map(|v| serde_json::to_string(v).unwrap_or_default())
            .unwrap_or_default();

        let context_info = build_context_info(context);

        return build_todo_prompt(
            instruction,
            file_path,
            language,
            file_content,
            line_number as usize,
            &indentation,
            &todo_line,
            &surrounding,
            &context_info,
        );
    }

    // Chat mode
    let context_str = serde_json::to_string(context).unwrap_or_default();
    build_chat_prompt(instruction, &context_str)
}

fn build_context_info(context: &serde_json::Value) -> String {
    let mut info = String::new();

    if let Some(cached) = context.get("cached_context") {
        info.push_str("\n\nProject Context:\n");
        info.push_str(&serde_json::to_string(cached).unwrap_or_default());
    }

    if let Some(buffers) = context.get("other_buffers").and_then(|v| v.as_array()) {
        if !buffers.is_empty() {
            info.push_str("\n\nOther Open Files:\n");
            for buf in buffers {
                let name = buf
                    .get("filename")
                    .or_else(|| buf.get("name"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("unknown");
                let ftype = buf
                    .get("filetype")
                    .or_else(|| buf.get("type"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("text");
                info.push_str(&format!("- {} ({})\n", name, ftype));
            }
        }
    }

    info
}

fn extract_todo_info(context: &serde_json::Value, _line_number: usize) -> (String, String) {
    let mut todo_line = String::new();
    let mut indentation = String::new();

    if let Some(surrounding) = context.get("surrounding_lines").and_then(|v| v.as_array()) {
        for line_info in surrounding {
            if line_info
                .get("is_target")
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
            {
                todo_line = line_info
                    .get("content")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();

                // Extract leading whitespace
                indentation = todo_line
                    .chars()
                    .take_while(|c| c.is_whitespace())
                    .collect();
                break;
            }
        }
    }

    (todo_line, indentation)
}

/// Build complete prompt (system + user)
pub fn build_complete_prompt(instruction: &str, context: &serde_json::Value) -> PromptResult {
    let system = get_schema_description();
    let user = build_user_prompt(instruction, context);

    PromptResult { system, user }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_schema_description_contains_key_elements() {
        let schema = get_schema_description();
        assert!(schema.contains("mode"));
        assert!(schema.contains("changes"));
        assert!(schema.contains("chat"));
        assert!(schema.contains("search") && schema.contains("replace"));
    }

    #[test]
    fn test_build_chat_prompt() {
        let result = build_chat_prompt("explain this code", "{}");
        assert!(result.contains("explain this code"));
    }

    #[test]
    fn test_build_complete_prompt() {
        let context = serde_json::json!({});
        let result = build_complete_prompt("hello", &context);
        assert!(!result.system.is_empty());
        assert!(!result.user.is_empty());
    }
}
