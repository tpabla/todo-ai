use crate::protocol::{ProjectTodos, TodoItem};
use regex::Regex;
use std::collections::HashMap;

/// Patterns to match TODO: @ai comments across different languages
const PATTERNS: &[&str] = &[
    r"--+\s*TODO:\s*@ai\s+(.+)",          // Lua: -- TODO: @ai
    r"//\s*TODO:\s*@ai\s+(.+)",            // C-style: // TODO: @ai
    r"#\s*TODO:\s*@ai\s+(.+)",             // Python/Shell: # TODO: @ai
    r#""\s*TODO:\s*@ai\s+(.+)"#,           // Vim: " TODO: @ai
    r";\s*TODO:\s*@ai\s+(.+)",             // Lisp: ; TODO: @ai
    r"/\*\s*TODO:\s*@ai\s+(.+)",           // C-style: /* TODO: @ai
    r"<!--\s*TODO:\s*@ai\s+(.+)",          // HTML: <!-- TODO: @ai
    r"\{-\s*TODO:\s*@ai\s+(.+)",           // Jinja: {- TODO: @ai
    r"%\s*TODO:\s*@ai\s+(.+)",             // LaTeX: % TODO: @ai
    r"\.\.\.\s*TODO:\s*@ai\s+(.+)",        // Haskell: ... TODO: @ai
];

/// Find TODO: @ai items in lines of text
pub fn find_todos(lines: &[String], comment_string: Option<&str>) -> Vec<TodoItem> {
    let compiled: Vec<Regex> = PATTERNS
        .iter()
        .filter_map(|p| Regex::new(p).ok())
        .collect();

    let mut todos = Vec::new();

    for (line_num, line) in lines.iter().enumerate() {
        if let Some(todo) = parse_line(line, line_num + 1, &compiled, lines, comment_string) {
            todos.push(todo);
        }
    }

    todos
}

fn parse_line(
    line: &str,
    line_num: usize,
    patterns: &[Regex],
    all_lines: &[String],
    comment_string: Option<&str>,
) -> Option<TodoItem> {
    for (idx, pattern) in patterns.iter().enumerate() {
        if let Some(caps) = pattern.captures(line) {
            if let Some(instruction_match) = caps.get(1) {
                let instruction = instruction_match.as_str().trim().to_string();

                // Check for multi-line continuation
                let full_instruction =
                    extract_multiline_todo(all_lines, line_num, &instruction, comment_string);

                return Some(TodoItem {
                    line: line_num,
                    instruction: full_instruction,
                    full_line: line.to_string(),
                    pattern: PATTERNS[idx].to_string(),
                });
            }
        }
    }
    None
}

fn extract_multiline_todo(
    lines: &[String],
    start_line: usize,
    initial_instruction: &str,
    comment_string: Option<&str>,
) -> String {
    let mut full_instruction = initial_instruction.to_string();

    if start_line == 0 || start_line > lines.len() {
        return full_instruction;
    }

    let start_idx = start_line - 1; // Convert to 0-based
    let indent = extract_indent(&lines[start_idx]);

    // Determine comment marker
    let comment_start = comment_string
        .map(|cs| {
            // Extract comment start from format like "// %s" or "-- %s"
            cs.split("%s").next().unwrap_or("//").trim().to_string()
        })
        .unwrap_or_else(|| "//".to_string());

    let mut i = start_idx + 1;
    while i < lines.len() {
        let line = &lines[i];
        let line_indent = extract_indent(line);

        if line_indent == indent && line.trim_start().starts_with(&comment_start) {
            if !line.contains("TODO") && !line.contains("@ai") {
                let content = line
                    .trim_start()
                    .strip_prefix(&comment_start)
                    .unwrap_or("")
                    .trim();
                if !content.is_empty() {
                    full_instruction.push(' ');
                    full_instruction.push_str(content);
                }
                i += 1;
            } else {
                break;
            }
        } else {
            break;
        }
    }

    // Normalize whitespace
    full_instruction
        .split_whitespace()
        .collect::<Vec<&str>>()
        .join(" ")
}

fn extract_indent(line: &str) -> String {
    let trimmed = line.trim_start();
    line[..line.len() - trimmed.len()].to_string()
}

/// Scan multiple files for TODO items
pub fn scan_project(files: &[(String, String)]) -> ProjectTodos {
    let compiled: Vec<Regex> = PATTERNS
        .iter()
        .filter_map(|p| Regex::new(p).ok())
        .collect();

    let mut todos_by_file: HashMap<String, Vec<TodoItem>> = HashMap::new();
    let mut total_count = 0;

    for (file_path, content) in files {
        let lines: Vec<String> = content.lines().map(|s| s.to_string()).collect();
        let mut file_todos = Vec::new();

        for (line_num, line) in lines.iter().enumerate() {
            if let Some(mut todo) = parse_line(line, line_num + 1, &compiled, &lines, None) {
                todo.pattern = file_path.clone(); // Reuse pattern field to store file path
                file_todos.push(todo);
                total_count += 1;
            }
        }

        if !file_todos.is_empty() {
            todos_by_file.insert(file_path.clone(), file_todos);
        }
    }

    ProjectTodos {
        todos_by_file,
        total_count,
    }
}

/// Format project TODOs for context
pub fn format_project_todos(todos: &ProjectTodos) -> String {
    let mut formatted = Vec::new();
    formatted.push("=== Project-wide TODOs ===\n".to_string());

    for (file_path, file_todos) in &todos.todos_by_file {
        formatted.push(format!("\n{file_path}:"));
        for todo in file_todos {
            formatted.push(format!("  Line {}: {}", todo.line, todo.instruction));
        }
    }

    formatted.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_find_lua_todo() {
        let lines = vec![
            "-- some code".to_string(),
            "-- TODO: @ai add error handling".to_string(),
            "local x = 1".to_string(),
        ];
        let todos = find_todos(&lines, Some("-- %s"));
        assert_eq!(todos.len(), 1);
        assert_eq!(todos[0].line, 2);
        assert_eq!(todos[0].instruction, "add error handling");
    }

    #[test]
    fn test_find_python_todo() {
        let lines = vec![
            "# TODO: @ai implement sorting".to_string(),
        ];
        let todos = find_todos(&lines, Some("# %s"));
        assert_eq!(todos.len(), 1);
        assert_eq!(todos[0].instruction, "implement sorting");
    }

    #[test]
    fn test_find_js_todo() {
        let lines = vec![
            "// TODO: @ai fix this function".to_string(),
        ];
        let todos = find_todos(&lines, Some("// %s"));
        assert_eq!(todos.len(), 1);
        assert_eq!(todos[0].instruction, "fix this function");
    }

    #[test]
    fn test_multiline_todo() {
        let lines = vec![
            "// TODO: @ai create a function".to_string(),
            "// that handles user input".to_string(),
            "// and validates it properly".to_string(),
            "function foo() {}".to_string(),
        ];
        let todos = find_todos(&lines, Some("// %s"));
        assert_eq!(todos.len(), 1);
        assert!(todos[0].instruction.contains("handles user input"));
        assert!(todos[0].instruction.contains("validates it properly"));
    }

    #[test]
    fn test_no_todos() {
        let lines = vec![
            "local x = 1".to_string(),
            "-- just a comment".to_string(),
        ];
        let todos = find_todos(&lines, None);
        assert!(todos.is_empty());
    }
}
