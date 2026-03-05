use regex::Regex;
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::process::Command;

/// A single TODO @ai match.
#[derive(Debug, Clone, serde::Serialize)]
pub struct TodoMatch {
    pub line: usize,
    pub instruction: String,
    pub full_line: String,
    pub file: Option<String>,
}

/// Patterns to match TODO: @ai comments across languages.
/// Each returns the capture group for the instruction text.
static TODO_PATTERNS: &[&str] = &[
    // Single-line comments
    r"--+\s*TODO:\s*@ai\s+(.+)",          // Lua
    r"//\s*TODO:\s*@ai\s+(.+)",            // C-style
    r"#\s*TODO:\s*@ai\s+(.+)",             // Python/Shell
    r#""\s*TODO:\s*@ai\s+(.+)"#,           // Vim
    r";\s*TODO:\s*@ai\s+(.+)",             // Lisp/Assembly
    // Multi-line comment start
    r"/\*\s*TODO:\s*@ai\s+(.+)",           // C-style block
    r"<!--\s*TODO:\s*@ai\s+(.+)",          // HTML
    r"\{-\s*TODO:\s*@ai\s+(.+)",           // Jinja
    // Language-specific
    r"%\s*TODO:\s*@ai\s+(.+)",             // LaTeX
];

/// Parse a single line for a TODO @ai match.
pub fn parse_line(line: &str) -> Option<String> {
    for pattern in TODO_PATTERNS {
        if let Ok(re) = Regex::new(pattern) {
            if let Some(caps) = re.captures(line) {
                if let Some(instruction) = caps.get(1) {
                    return Some(instruction.as_str().trim().to_string());
                }
            }
        }
    }
    None
}

/// Extract multi-line TODO instruction from consecutive comment lines.
pub fn extract_multiline_todo(lines: &[&str], start_line: usize) -> String {
    let initial = parse_line(lines[start_line]).unwrap_or_default();
    let mut full = initial;

    if start_line >= lines.len() {
        return full;
    }

    // Detect indent and comment style of the TODO line
    let indent = lines[start_line]
        .chars()
        .take_while(|c| c.is_whitespace())
        .collect::<String>();

    let comment_start = detect_comment_start(lines[start_line]);

    // Look for continuation lines
    let mut i = start_line + 1;
    while i < lines.len() {
        let line = lines[i];
        let line_indent: String = line.chars().take_while(|c| c.is_whitespace()).collect();

        if line_indent != indent {
            break;
        }

        let trimmed = line.trim_start();
        if !trimmed.starts_with(&comment_start) {
            break;
        }

        // Skip if it's another TODO or @ai
        if trimmed.contains("TODO") || trimmed.contains("@ai") {
            break;
        }

        // Extract content after comment marker
        let content = trimmed
            .strip_prefix(&comment_start)
            .unwrap_or("")
            .trim();

        if !content.is_empty() {
            full.push(' ');
            full.push_str(content);
        }

        i += 1;
    }

    // Normalize whitespace
    full.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Detect the comment start marker from a line.
fn detect_comment_start(line: &str) -> String {
    let trimmed = line.trim_start();
    if trimmed.starts_with("//") {
        "//".to_string()
    } else if trimmed.starts_with("--") {
        "--".to_string()
    } else if trimmed.starts_with('#') {
        "#".to_string()
    } else if trimmed.starts_with("/*") {
        "/*".to_string()
    } else if trimmed.starts_with(';') {
        ";".to_string()
    } else if trimmed.starts_with('%') {
        "%".to_string()
    } else {
        "//".to_string() // default
    }
}

/// Find all TODO @ai matches in the given lines.
pub fn find_todos(lines: &[&str]) -> Vec<TodoMatch> {
    let mut todos = Vec::new();

    for (i, line) in lines.iter().enumerate() {
        if parse_line(line).is_some() {
            let full_instruction = extract_multiline_todo(lines, i);
            todos.push(TodoMatch {
                line: i + 1, // 1-indexed
                instruction: full_instruction,
                full_line: line.to_string(),
                file: None,
            });
        }
    }

    todos
}

/// Scan a project directory for TODO @ai comments across all source files.
pub fn scan_project(project_root: &str) -> HashMap<String, Vec<TodoMatch>> {
    let root = Path::new(project_root);
    let mut todos_by_file: HashMap<String, Vec<TodoMatch>> = HashMap::new();

    // Get file list from git or find
    let files = get_project_files(root);

    for file_path in files {
        let full_path = root.join(&file_path);
        if let Ok(content) = fs::read_to_string(&full_path) {
            let lines: Vec<&str> = content.lines().collect();
            let mut file_todos = find_todos(&lines);

            if !file_todos.is_empty() {
                // Set file path on each match
                for todo in &mut file_todos {
                    todo.file = Some(file_path.clone());
                }
                todos_by_file.insert(file_path, file_todos);
            }
        }
    }

    todos_by_file
}

/// Format project TODOs for LLM context.
pub fn format_project_todos(todos_by_file: &HashMap<String, Vec<TodoMatch>>) -> String {
    let mut lines = vec!["=== Project-wide TODOs ===\n".to_string()];

    for (file_path, todos) in todos_by_file {
        lines.push(format!("\n📄 {file_path}:"));
        for todo in todos {
            lines.push(format!("  Line {}: {}", todo.line, todo.instruction));
        }
    }

    lines.join("\n")
}

fn get_project_files(root: &Path) -> Vec<String> {
    // Try git ls-files first
    let git_output = Command::new("git")
        .args(["ls-files"])
        .current_dir(root)
        .output();

    let raw_files = match git_output {
        Ok(o) if o.status.success() && !o.stdout.is_empty() => {
            String::from_utf8_lossy(&o.stdout).to_string()
        }
        _ => {
            // Fallback to find
            let find_output = Command::new("find")
                .args([
                    ".",
                    "-type",
                    "f",
                    "(",
                    "-name", "*.lua",
                    "-o", "-name", "*.js",
                    "-o", "-name", "*.ts",
                    "-o", "-name", "*.py",
                    "-o", "-name", "*.go",
                    "-o", "-name", "*.rs",
                    "-o", "-name", "*.c",
                    "-o", "-name", "*.cpp",
                    "-o", "-name", "*.h",
                    "-o", "-name", "*.hpp",
                    ")",
                ])
                .current_dir(root)
                .output();

            match find_output {
                Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).to_string(),
                _ => return Vec::new(),
            }
        }
    };

    raw_files
        .lines()
        .filter(|f| {
            !f.starts_with(".git/")
                && !f.contains("node_modules/")
                && !f.contains(".venv/")
                && !f.contains("vendor/")
                && !f.contains("target/")
                && !f.contains("dist/")
                && !f.contains("build/")
                && !f.contains(".min.")
        })
        .map(|f| f.trim_start_matches("./").to_string())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_line_lua() {
        assert_eq!(
            parse_line("-- TODO: @ai add error handling"),
            Some("add error handling".to_string())
        );
    }

    #[test]
    fn test_parse_line_c_style() {
        assert_eq!(
            parse_line("// TODO: @ai fix this bug"),
            Some("fix this bug".to_string())
        );
    }

    #[test]
    fn test_parse_line_python() {
        assert_eq!(
            parse_line("# TODO: @ai refactor this function"),
            Some("refactor this function".to_string())
        );
    }

    #[test]
    fn test_parse_line_html() {
        assert_eq!(
            parse_line("<!-- TODO: @ai add accessibility"),
            Some("add accessibility".to_string())
        );
    }

    #[test]
    fn test_parse_line_no_match() {
        assert_eq!(parse_line("// just a regular comment"), None);
        assert_eq!(parse_line("// TODO: but no @ai tag"), None);
        assert_eq!(parse_line("let x = 42;"), None);
    }

    #[test]
    fn test_find_todos_multiple() {
        let lines = vec![
            "fn main() {",
            "    // TODO: @ai add error handling",
            "    let x = 1;",
            "    // TODO: @ai refactor this",
            "}",
        ];
        let todos = find_todos(&lines);
        assert_eq!(todos.len(), 2);
        assert_eq!(todos[0].line, 2);
        assert_eq!(todos[0].instruction, "add error handling");
        assert_eq!(todos[1].line, 4);
        assert_eq!(todos[1].instruction, "refactor this");
    }

    #[test]
    fn test_extract_multiline_todo() {
        let lines = vec![
            "    // TODO: @ai add a new function",
            "    // that handles authentication",
            "    // and returns a token",
            "    let x = 1;",
        ];
        let instruction = extract_multiline_todo(&lines, 0);
        assert_eq!(
            instruction,
            "add a new function that handles authentication and returns a token"
        );
    }

    #[test]
    fn test_extract_multiline_stops_at_different_indent() {
        let lines = vec![
            "    // TODO: @ai fix this",
            "        // different indent",
            "    let x = 1;",
        ];
        let instruction = extract_multiline_todo(&lines, 0);
        assert_eq!(instruction, "fix this");
    }

    #[test]
    fn test_extract_multiline_stops_at_another_todo() {
        let lines = vec![
            "    // TODO: @ai first task",
            "    // TODO: @ai second task",
        ];
        let instruction = extract_multiline_todo(&lines, 0);
        assert_eq!(instruction, "first task");
    }

    #[test]
    fn test_detect_comment_start() {
        assert_eq!(detect_comment_start("  // comment"), "//");
        assert_eq!(detect_comment_start("  -- comment"), "--");
        assert_eq!(detect_comment_start("  # comment"), "#");
        assert_eq!(detect_comment_start("  /* comment"), "/*");
    }

    #[test]
    fn test_format_project_todos() {
        let mut todos_by_file = HashMap::new();
        todos_by_file.insert(
            "src/main.rs".to_string(),
            vec![TodoMatch {
                line: 10,
                instruction: "add error handling".to_string(),
                full_line: "// TODO: @ai add error handling".to_string(),
                file: Some("src/main.rs".to_string()),
            }],
        );

        let formatted = format_project_todos(&todos_by_file);
        assert!(formatted.contains("src/main.rs"));
        assert!(formatted.contains("Line 10"));
        assert!(formatted.contains("add error handling"));
    }

    #[test]
    fn test_scan_project_real() {
        // Scan our own project — should find the TODO in main.rs
        let project_root = env!("CARGO_MANIFEST_DIR");
        let todos = scan_project(project_root);

        // We know src/main.rs has a TODO: @ai comment
        let main_todos = todos.get("src/main.rs");
        assert!(
            main_todos.is_some(),
            "Expected to find TODOs in src/main.rs, found files: {:?}",
            todos.keys().collect::<Vec<_>>()
        );
        assert!(!main_todos.unwrap().is_empty());
    }
}
