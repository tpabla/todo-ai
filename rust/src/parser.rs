use regex::Regex;
use serde_json::Value;
use std::collections::HashMap;

/// Result of parsing an LLM response.
#[derive(Debug, Default)]
pub struct ParseResult {
    pub raw_response: String,
    pub format_detected: String,
    pub thinking: Option<HashMap<String, String>>,
    pub thinking_formatted: Option<String>,

    // JSON-parsed fields (direct assignment from response)
    pub mode: Option<String>,
    pub filename: Option<String>,
    pub changes: Option<Value>,
    pub language: Option<String>,
    pub explanation: Option<String>,

    // Code extraction fields
    pub code: Option<String>,
    pub code_language: Option<String>,

    // Error/warning fields
    pub parse_error: Option<String>,
    pub warning: Option<String>,

    // Raw JSON data for debugging
    pub raw_json: Option<Value>,

    // XML parsed sections
    pub parsed_sections: HashMap<String, String>,
}

/// Thinking tag definitions — matched as `<tag>...</tag>`.
const THINKING_TAGS: &[&str] = &[
    "think", "thinking", "thought", "reasoning", "analysis",
    "planning", "approach", "strategy", "scratch", "work", "internal",
];

/// Parse a response from the LLM.
pub fn parse(response: &str, hint: Option<&str>) -> ParseResult {
    let mut result = ParseResult {
        raw_response: response.to_string(),
        format_detected: "unknown".to_string(),
        ..Default::default()
    };

    // Extract and preserve thinking tags
    let thinking = extract_thinking_tags(response);
    let cleaned_response;
    if !thinking.is_empty() {
        result.thinking_formatted = Some(format_thinking(&thinking));
        result.thinking = Some(thinking);
        cleaned_response = remove_thinking_tags(response);
    } else {
        cleaned_response = response.to_string();
    }

    // Extract assistant tags if present
    let working_response = extract_assistant_content(&cleaned_response);

    // Detect format
    let mut format = detect_format(&working_response);

    // Special handling for Claude responses
    if let Some(h) = hint {
        if h.to_lowercase().contains("claude") {
            let trimmed = working_response.trim();
            if trimmed.starts_with('{') && trimmed.ends_with('}') {
                if serde_json::from_str::<Value>(trimmed).is_ok() {
                    format = "json_response".to_string();
                }
            } else if format == "mixed_format" && looks_like_code(&working_response) {
                format = "plain_code".to_string();
            }
        }
    }

    result.format_detected = format.clone();

    match format.as_str() {
        "xml_structured" => parse_xml_structured(&working_response, &mut result),
        "json_response" => parse_json_response(&working_response, &mut result),
        "markdown_formatted" => parse_markdown_formatted(&working_response, &mut result),
        "plain_code" => {
            result.code = Some(working_response.trim().to_string());
            result.explanation = Some("Generated code".to_string());
        }
        _ => parse_generic(&working_response, &mut result),
    }

    result
}

/// Detect the format of a response string.
pub fn detect_format(response: &str) -> String {
    let trimmed = response.trim();

    // Check for XML-like structure
    let xml_re = Regex::new(r"<\w+>.*?</\w+>").unwrap();
    if xml_re.is_match(trimmed) {
        return "xml_structured".to_string();
    }

    // Check for JSON
    if trimmed.starts_with('{') && trimmed.ends_with('}') {
        if serde_json::from_str::<Value>(trimmed).is_ok() {
            return "json_response".to_string();
        }
    }

    // Check for markdown code blocks
    if trimmed.contains("```") {
        return "markdown_formatted".to_string();
    }

    // Check if it looks like code
    if looks_like_code(trimmed) {
        return "plain_code".to_string();
    }

    "mixed_format".to_string()
}

/// Heuristic: does this text look like source code?
pub fn looks_like_code(text: &str) -> bool {
    let code_patterns = [
        r"^\s*def\s+",
        r"^\s*class\s+",
        r"^\s*function\s+",
        r"^\s*const\s+",
        r"^\s*let\s+",
        r"^\s*var\s+",
        r"^\s*import\s+",
        r"^\s*from\s+",
        r"^\s*export\s+",
        r"^\s*if\s*[(\:]",
        r"^\s*for\s+",
        r"^\s*while\s+",
        r"^\s*return\s+",
        r"^\s*print\(",
        r"^\s*try:",
        r"^\s*except",
        r"[{};]",
        r"=>",
        r"->",
        r"::",
        r#"=\s*["']"#,
        r"\.\w+\(",
    ];

    let compiled: Vec<Regex> = code_patterns
        .iter()
        .filter_map(|p| Regex::new(p).ok())
        .collect();

    let lines: Vec<&str> = text.lines().collect();

    // Quick check: first line starts with import/def/class/from
    if let Some(first) = lines.first() {
        let f = first.trim_start();
        if f.starts_with("import ") || f.starts_with("from ")
            || f.starts_with("def ") || f.starts_with("class ")
        {
            return true;
        }
    }

    let mut code_lines = 0;
    let mut non_empty_lines = 0;

    for line in &lines {
        if line.chars().any(|c| !c.is_whitespace()) {
            non_empty_lines += 1;
            for re in &compiled {
                if re.is_match(line) {
                    code_lines += 1;
                    break;
                }
            }
        }
    }

    if non_empty_lines > 0 {
        (code_lines as f64 / non_empty_lines as f64) > 0.4
    } else {
        false
    }
}

/// Extract thinking sections from various tag types.
pub fn extract_thinking_tags(response: &str) -> HashMap<String, String> {
    let mut sections: HashMap<String, String> = HashMap::new();

    for tag in THINKING_TAGS {
        let pattern = format!(r"(?s)<{tag}>(.*?)</{tag}>");
        if let Ok(re) = Regex::new(&pattern) {
            for cap in re.captures_iter(response) {
                let content = cap[1].trim().to_string();
                sections
                    .entry(tag.to_string())
                    .and_modify(|existing| {
                        existing.push_str("\n\n");
                        existing.push_str(&content);
                    })
                    .or_insert(content);
            }
        }
    }

    sections
}

/// Remove all thinking-like tags from a response.
pub fn remove_thinking_tags(response: &str) -> String {
    let mut result = response.to_string();
    for tag in THINKING_TAGS {
        let pattern = format!(r"(?s)<{tag}>.*?</{tag}>");
        if let Ok(re) = Regex::new(&pattern) {
            result = re.replace_all(&result, "").to_string();
        }
    }
    result.trim().to_string()
}

/// Format thinking sections into readable markdown.
pub fn format_thinking(thinking: &HashMap<String, String>) -> String {
    let tag_display = [
        ("thinking", "Thinking"),
        ("think", "Thinking"),
        ("thought", "Thoughts"),
        ("reasoning", "Reasoning"),
        ("analysis", "Analysis"),
        ("planning", "Planning"),
        ("approach", "Approach"),
        ("strategy", "Strategy"),
        ("scratch", "Scratch Work"),
        ("work", "Work"),
        ("internal", "Internal Process"),
    ];

    let mut formatted = String::from("## AI Thinking Process\n\n");

    for (key, header) in &tag_display {
        if let Some(content) = thinking.get(*key) {
            formatted.push_str(&format!("### {header}\n"));
            for line in content.lines() {
                let trimmed = line.trim();
                formatted.push_str(trimmed);
                formatted.push('\n');
            }
            formatted.push('\n');
        }
    }

    formatted.push_str("---\n");
    formatted
}

/// Extract content from `<assistant>...</assistant>` wrapper if present.
fn extract_assistant_content(response: &str) -> String {
    let re = Regex::new(r"(?s)<assistant>(.*?)</assistant>").unwrap();
    if let Some(cap) = re.captures(response) {
        cap[1].to_string()
    } else {
        response.to_string()
    }
}

/// Parse XML-structured responses.
fn parse_xml_structured(response: &str, result: &mut ParseResult) {
    // Extract code from XML tags
    let code_tags = ["code", "implementation", "solution", "answer"];
    for tag in &code_tags {
        let pattern = format!(r"(?s)<{tag}>(.*?)</{tag}>");
        if let Ok(re) = Regex::new(&pattern) {
            if let Some(cap) = re.captures(response) {
                result.code = Some(cap[1].trim().to_string());
                break;
            }
        }
    }

    // Extract explanation
    let explanation_tags = ["explanation", "description", "reasoning", "context"];
    for tag in &explanation_tags {
        let pattern = format!(r"(?s)<{tag}>(.*?)</{tag}>");
        if let Ok(re) = Regex::new(&pattern) {
            if let Some(cap) = re.captures(response) {
                result.explanation = Some(cap[1].trim().to_string());
                break;
            }
        }
    }

    // Parse all XML tags into sections (no backreferences in regex crate)
    let all_tags_re = Regex::new(r"(?s)<(\w+)>(.*?)</(\w+)>").unwrap();
    for cap in all_tags_re.captures_iter(response) {
        if cap[1] == cap[3] {
            result
                .parsed_sections
                .insert(cap[1].to_string(), cap[2].trim().to_string());
        }
    }
}

/// Parse JSON responses — direct field assignment, no guessing.
fn parse_json_response(response: &str, result: &mut ParseResult) {
    let trimmed = response.trim();

    // Check if JSON looks complete
    if !trimmed.ends_with('}') {
        result.parse_error = Some(
            "JSON response appears incomplete (no closing }). Response may have been cut off due to length or timeout.".to_string()
        );
        return;
    }

    let data: Value = match serde_json::from_str(trimmed) {
        Ok(v) => v,
        Err(e) => {
            result.parse_error = Some(format!("JSON parsing failed: {e}"));
            return;
        }
    };

    // Direct assignment — the schema validator checks required fields later
    result.mode = data.get("mode").and_then(|v| v.as_str()).map(|s| s.to_string());
    result.filename = data.get("filename").and_then(|v| v.as_str()).map(|s| s.to_string());
    result.changes = data.get("changes").cloned();
    result.language = data.get("language").and_then(|v| v.as_str()).map(|s| s.to_string());
    result.explanation = data.get("explanation").and_then(|v| v.as_str()).map(|s| s.to_string());

    result.raw_json = Some(data);
}

/// Parse markdown-formatted responses (code blocks, etc).
fn parse_markdown_formatted(response: &str, result: &mut ParseResult) {
    let code_block_re = Regex::new(r"(?s)```(\w*)\s*\n(.*?)\n```").unwrap();

    let mut code_blocks: Vec<(String, String)> = Vec::new();

    for cap in code_block_re.captures_iter(response) {
        let lang = cap[1].to_string();
        let code = cap[2].to_string();

        // If it's a JSON code block with our expected schema, parse as JSON
        if lang == "json" || (lang.is_empty() && code.contains("\"changes\"")) {
            if let Ok(data) = serde_json::from_str::<Value>(&code) {
                if data.get("changes").is_some() {
                    result.changes = data.get("changes").cloned();
                    result.language = data.get("language").and_then(|v| v.as_str()).map(|s| s.to_string());
                    result.explanation = data
                        .get("explanation")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string())
                        .or_else(|| Some("Generated changes".to_string()));
                    result.format_detected = "json_response".to_string();
                    result.warning = Some("JSON was wrapped in ```json``` - AI should return raw JSON only".to_string());
                    return;
                }
            }
        }

        code_blocks.push((lang, code));
    }

    // Extract explanation (text outside code blocks)
    let explanation_text = code_block_re.replace_all(response, "").trim().to_string();

    if let Some((lang, first_code)) = code_blocks.first() {
        result.code = Some(first_code.trim().to_string());
        result.code_language = Some(if lang.is_empty() {
            "text".to_string()
        } else {
            lang.clone()
        });

        // Only use explanation if it doesn't look like code
        if !explanation_text.is_empty() && !looks_like_code(&explanation_text) {
            result.explanation = Some(explanation_text);
        }
    } else if looks_like_code(&explanation_text) {
        result.code = Some(explanation_text);
        result.explanation = Some("Generated code".to_string());
    } else {
        result.explanation = Some(explanation_text);
    }
}

/// Fallback parser for mixed/unknown formats.
fn parse_generic(response: &str, result: &mut ParseResult) {
    // Try to extract code blocks first
    let code_block_re = Regex::new(r"(?s)```\w*\s*\n(.*?)\n```").unwrap();
    if let Some(cap) = code_block_re.captures(response) {
        result.code = Some(cap[1].trim().to_string());
        return;
    }

    // If it looks like code, treat as plain code
    if looks_like_code(response) {
        result.code = Some(response.trim().to_string());
        result.explanation = Some("Generated code".to_string());
        return;
    }

    // Try to separate code from explanation
    let mut code_lines: Vec<&str> = Vec::new();
    let mut explanation_lines: Vec<&str> = Vec::new();
    let mut in_code = false;

    for line in response.lines() {
        if looks_like_code(line) {
            in_code = true;
            code_lines.push(line);
        } else if in_code && line.trim().is_empty() {
            code_lines.push(line);
        } else {
            in_code = false;
            explanation_lines.push(line);
        }
    }

    if !code_lines.is_empty() {
        result.code = Some(code_lines.join("\n").trim().to_string());
    }
    if !explanation_lines.is_empty() {
        result.explanation = Some(explanation_lines.join("\n").trim().to_string());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- Format detection ---

    #[test]
    fn test_detect_json() {
        let input = r#"{"mode": "chat", "explanation": "hello"}"#;
        assert_eq!(detect_format(input), "json_response");
    }

    #[test]
    fn test_detect_xml() {
        let input = "<code>fn main() {}</code>";
        assert_eq!(detect_format(input), "xml_structured");
    }

    #[test]
    fn test_detect_markdown() {
        let input = "Here's the code:\n```python\nprint('hi')\n```";
        assert_eq!(detect_format(input), "markdown_formatted");
    }

    #[test]
    fn test_detect_plain_code() {
        let input = "import os\nimport sys\ndef main():\n    print('hello')\n";
        assert_eq!(detect_format(input), "plain_code");
    }

    #[test]
    fn test_detect_mixed() {
        let input = "Here is some explanation about the code.";
        assert_eq!(detect_format(input), "mixed_format");
    }

    // --- Thinking tags ---

    #[test]
    fn test_extract_thinking_tags() {
        let input = "<thinking>Step 1: analyze\nStep 2: implement</thinking>\nActual response here";
        let tags = extract_thinking_tags(input);
        assert!(tags.contains_key("thinking"));
        assert!(tags["thinking"].contains("Step 1"));
    }

    #[test]
    fn test_extract_multiple_thinking_types() {
        let input = "<thinking>thought process</thinking><reasoning>logical steps</reasoning>";
        let tags = extract_thinking_tags(input);
        assert_eq!(tags.len(), 2);
        assert!(tags.contains_key("thinking"));
        assert!(tags.contains_key("reasoning"));
    }

    #[test]
    fn test_remove_thinking_tags() {
        let input = "<thinking>internal</thinking>\nThe answer is 42.";
        let cleaned = remove_thinking_tags(input);
        assert_eq!(cleaned, "The answer is 42.");
        assert!(!cleaned.contains("internal"));
    }

    #[test]
    fn test_format_thinking() {
        let mut tags = HashMap::new();
        tags.insert("thinking".to_string(), "I need to analyze this".to_string());
        let formatted = format_thinking(&tags);
        assert!(formatted.contains("### Thinking"));
        assert!(formatted.contains("I need to analyze this"));
        assert!(formatted.contains("---"));
    }

    // --- JSON parsing ---

    #[test]
    fn test_parse_json_response() {
        let input = r#"{"mode": "changes", "filename": "test.py", "changes": [{"search": "old", "replace": "new"}], "explanation": "Updated code"}"#;
        let result = parse(input, None);
        assert_eq!(result.format_detected, "json_response");
        assert_eq!(result.mode.as_deref(), Some("changes"));
        assert_eq!(result.filename.as_deref(), Some("test.py"));
        assert_eq!(result.explanation.as_deref(), Some("Updated code"));
        assert!(result.changes.is_some());
        assert!(result.parse_error.is_none());
    }

    #[test]
    fn test_parse_json_chat() {
        let input = r#"{"mode": "chat", "explanation": "Here's what the code does..."}"#;
        let result = parse(input, None);
        assert_eq!(result.format_detected, "json_response");
        assert_eq!(result.mode.as_deref(), Some("chat"));
        assert_eq!(result.explanation.as_deref(), Some("Here's what the code does..."));
    }

    #[test]
    fn test_parse_incomplete_json() {
        // Ends with } but is actually invalid JSON — tests the parse_json_response error path
        let input = r#"{"mode": "changes", "filename": "test.py"}"#;
        // This is actually valid JSON (just missing changes array), so test that it parses
        let result = parse(input, None);
        assert_eq!(result.format_detected, "json_response");
        assert_eq!(result.mode.as_deref(), Some("changes"));
    }

    #[test]
    fn test_parse_incomplete_json_no_closing_brace() {
        // Input that starts with { but doesn't end with } won't be detected as JSON
        let input = r#"{"mode": "changes", "filename": "test.py""#;
        let result = parse(input, None);
        // Not detected as JSON since it doesn't end with }
        assert_ne!(result.format_detected, "json_response");
    }

    #[test]
    fn test_parse_invalid_json() {
        // Malformed JSON that starts/ends with braces but can't parse
        let input = r#"{"mode": changes, "bad":}"#;
        let result = parse(input, None);
        // detect_format tries json_decode, fails, falls through to another format
        assert_ne!(result.format_detected, "json_response");
    }

    // --- XML parsing ---

    #[test]
    fn test_parse_xml_code() {
        let input = "<code>def hello():\n    print('hi')</code><explanation>A greeting function</explanation>";
        let result = parse(input, None);
        assert_eq!(result.format_detected, "xml_structured");
        assert_eq!(result.code.as_deref(), Some("def hello():\n    print('hi')"));
        assert_eq!(result.explanation.as_deref(), Some("A greeting function"));
    }

    #[test]
    fn test_parse_xml_sections() {
        let input = "<code>x = 1</code><description>Sets x</description>";
        let result = parse(input, None);
        assert!(result.parsed_sections.contains_key("code"));
        assert!(result.parsed_sections.contains_key("description"));
    }

    // --- Markdown parsing ---

    #[test]
    fn test_parse_markdown_code_block() {
        let input = "Here's the fix:\n```python\ndef hello():\n    print('hi')\n```\nThis adds a greeting.";
        let result = parse(input, None);
        assert_eq!(result.format_detected, "markdown_formatted");
        assert_eq!(result.code.as_deref(), Some("def hello():\n    print('hi')"));
        assert_eq!(result.code_language.as_deref(), Some("python"));
    }

    #[test]
    fn test_parse_markdown_json_wrapped() {
        let input = "```json\n{\"mode\": \"changes\", \"filename\": \"test.py\", \"changes\": [{\"search\": \"a\", \"replace\": \"b\"}], \"explanation\": \"fix\"}\n```";
        let result = parse(input, None);
        assert_eq!(result.format_detected, "json_response");
        assert!(result.changes.is_some());
        assert!(result.warning.is_some());
    }

    // --- Thinking + content combined ---

    #[test]
    fn test_parse_with_thinking_and_json() {
        let input = "<thinking>Let me analyze this</thinking>\n{\"mode\": \"chat\", \"explanation\": \"The answer\"}";
        let result = parse(input, None);
        assert!(result.thinking.is_some());
        assert_eq!(result.mode.as_deref(), Some("chat"));
        assert_eq!(result.explanation.as_deref(), Some("The answer"));
    }

    // --- Claude hint ---

    #[test]
    fn test_claude_hint_json() {
        let input = r#"{"mode": "chat", "explanation": "hello"}"#;
        let result = parse(input, Some("claude-3"));
        assert_eq!(result.format_detected, "json_response");
        assert_eq!(result.mode.as_deref(), Some("chat"));
    }

    // --- looks_like_code ---

    #[test]
    fn test_looks_like_code_python() {
        assert!(looks_like_code("import os\ndef main():\n    pass"));
    }

    #[test]
    fn test_looks_like_code_plain_text() {
        assert!(!looks_like_code("This is just a regular sentence about programming."));
    }

    // --- Generic parsing ---

    #[test]
    fn test_parse_generic_with_code_block() {
        let input = "Some text\n```\ncode here\n```\nMore text";
        // This hits markdown_formatted, not generic
        let result = parse(input, None);
        assert_eq!(result.format_detected, "markdown_formatted");
        assert!(result.code.is_some());
    }

    #[test]
    fn test_parse_plain_code() {
        let input = "import os\nimport sys\ndef main():\n    os.path.join('a', 'b')\n";
        let result = parse(input, None);
        assert_eq!(result.format_detected, "plain_code");
        assert!(result.code.is_some());
    }
}
