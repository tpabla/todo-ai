use crate::protocol::{Change, ParseResult};
use regex::Regex;
use std::collections::HashMap;

/// Parse response from LLM
pub fn parse(response: &str, hint: Option<&str>) -> ParseResult {
    let mut result = ParseResult {
        raw_response: response.to_string(),
        format_detected: "unknown".to_string(),
        mode: None,
        filename: None,
        changes: None,
        language: None,
        explanation: None,
        code: None,
        thinking: None,
        thinking_formatted: None,
        parse_error: None,
        warning: None,
    };

    // Extract thinking tags
    let thinking = extract_thinking_tags(response);
    if !thinking.is_empty() {
        result.thinking = Some(serde_json::to_value(&thinking).unwrap_or_default());
        result.thinking_formatted = Some(format_thinking(&thinking));
    }

    // Remove thinking tags for parsing
    let cleaned = remove_thinking_tags(response);

    // Extract assistant tags if present
    let processed = extract_assistant_content(&cleaned);

    // Detect format
    let mut format = detect_format(&processed);

    // Special handling for Claude responses
    if let Some(h) = hint {
        if h.to_lowercase().contains("claude") {
            let trimmed = processed.trim();
            if trimmed.starts_with('{') && trimmed.ends_with('}') {
                if serde_json::from_str::<serde_json::Value>(trimmed).is_ok() {
                    format = "json_response".to_string();
                }
            } else if format == "mixed_format" && looks_like_code(&processed) {
                format = "plain_code".to_string();
            }
        }
    }

    result.format_detected = format.clone();

    match format.as_str() {
        "json_response" => parse_json_response(&processed, &mut result),
        "xml_structured" => parse_xml_structured(&processed, &mut result),
        "markdown_formatted" => parse_markdown_formatted(&processed, &mut result),
        "plain_code" => {
            result.code = Some(processed.trim().to_string());
            result.explanation = Some("Generated code".to_string());
        }
        _ => parse_generic(&processed, &mut result),
    }

    result
}

fn detect_format(response: &str) -> String {
    let trimmed = response.trim();

    // Check for XML-like structure
    let xml_re = Regex::new(r"<\w+>.*</\w+>").unwrap();
    if xml_re.is_match(trimmed) {
        return "xml_structured".to_string();
    }

    // Check for JSON
    if trimmed.starts_with('{') && trimmed.ends_with('}') {
        if serde_json::from_str::<serde_json::Value>(trimmed).is_ok() {
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

pub fn looks_like_code(text: &str) -> bool {
    let patterns = [
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

    let compiled: Vec<Regex> = patterns
        .iter()
        .filter_map(|p| Regex::new(p).ok())
        .collect();

    let lines: Vec<&str> = text.split('\n').collect();

    // Quick check first line
    if let Some(first) = lines.first() {
        let first = first.trim();
        if first.starts_with("import ") || first.starts_with("from ") ||
           first.starts_with("def ") || first.starts_with("class ") {
            return true;
        }
    }

    let mut code_lines = 0;
    let mut non_empty_lines = 0;

    for line in &lines {
        if !line.trim().is_empty() {
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

fn extract_thinking_tags(response: &str) -> HashMap<String, String> {
    let tag_names = [
        "think", "thinking", "thought", "reasoning", "analysis",
        "planning", "approach", "strategy", "scratch", "work", "internal",
    ];

    let mut sections = HashMap::new();

    for tag in &tag_names {
        let pattern = format!(r"(?s)<{}>(.*?)</{}>", tag, tag);
        if let Ok(re) = Regex::new(&pattern) {
            let mut combined = String::new();
            for cap in re.captures_iter(response) {
                let content = cap[1].trim();
                if !combined.is_empty() {
                    combined.push_str("\n\n");
                }
                combined.push_str(content);
            }
            if !combined.is_empty() {
                // Normalize tag name
                let key = match *tag {
                    "think" => "thinking",
                    _ => tag,
                };
                sections.insert(key.to_string(), combined);
            }
        }
    }

    sections
}

fn remove_thinking_tags(response: &str) -> String {
    let tag_names = [
        "think", "thinking", "thought", "reasoning", "analysis",
        "planning", "approach", "strategy", "scratch", "work", "internal",
    ];

    let mut result = response.to_string();
    for tag in &tag_names {
        let pattern = format!(r"(?s)<{}>.*?</{}>", tag, tag);
        if let Ok(re) = Regex::new(&pattern) {
            result = re.replace_all(&result, "").to_string();
        }
    }

    result.trim().to_string()
}

fn format_thinking(sections: &HashMap<String, String>) -> String {
    let mut formatted = Vec::new();
    formatted.push("## AI Thinking Process\n".to_string());

    let tag_display = [
        ("thinking", "Thinking"),
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

    for (key, header) in &tag_display {
        if let Some(content) = sections.get(*key) {
            formatted.push(format!("### {}\n", header));
            for line in content.lines() {
                formatted.push(line.to_string());
            }
            formatted.push(String::new());
        }
    }

    formatted.push("---\n".to_string());
    formatted.join("\n")
}

fn extract_assistant_content(response: &str) -> String {
    let re = Regex::new(r"(?s)<assistant>(.*?)</assistant>").unwrap();
    if let Some(cap) = re.captures(response) {
        cap[1].to_string()
    } else {
        response.to_string()
    }
}

fn parse_json_response(response: &str, result: &mut ParseResult) {
    let trimmed = response.trim();
    if !trimmed.ends_with('}') {
        result.parse_error = Some(
            "JSON response appears incomplete (no closing }). Response may have been cut off due to length or timeout.".to_string()
        );
        return;
    }

    match serde_json::from_str::<serde_json::Value>(trimmed) {
        Ok(data) => {
            result.mode = data.get("mode").and_then(|v| v.as_str()).map(|s| s.to_string());
            result.filename = data.get("filename").and_then(|v| v.as_str()).map(|s| s.to_string());
            result.language = data.get("language").and_then(|v| v.as_str()).map(|s| s.to_string());
            result.explanation = data.get("explanation").and_then(|v| v.as_str()).map(|s| s.to_string());

            if let Some(changes_val) = data.get("changes") {
                if let Ok(changes) = serde_json::from_value::<Vec<Change>>(changes_val.clone()) {
                    result.changes = Some(changes);
                }
            }
        }
        Err(e) => {
            result.parse_error = Some(format!("JSON parsing failed: {}", e));
        }
    }
}

fn parse_xml_structured(response: &str, result: &mut ParseResult) {
    let code_tags = ["code", "implementation", "solution", "answer"];
    for tag in &code_tags {
        let pattern = format!(r"(?s)<{}>(.*?)</{}>", tag, tag);
        if let Ok(re) = Regex::new(&pattern) {
            if let Some(cap) = re.captures(response) {
                result.code = Some(cap[1].trim().to_string());
                break;
            }
        }
    }

    let explanation_tags = ["explanation", "description", "reasoning", "context"];
    for tag in &explanation_tags {
        let pattern = format!(r"(?s)<{}>(.*?)</{}>", tag, tag);
        if let Ok(re) = Regex::new(&pattern) {
            if let Some(cap) = re.captures(response) {
                result.explanation = Some(cap[1].trim().to_string());
                break;
            }
        }
    }
}

fn parse_markdown_formatted(response: &str, result: &mut ParseResult) {
    let code_block_re = Regex::new(r"(?s)```(\w*)\s*\n(.*?)\n```").unwrap();
    let mut code_blocks: Vec<(String, String)> = Vec::new();

    for cap in code_block_re.captures_iter(response) {
        let lang = cap[1].to_string();
        let code = cap[2].to_string();

        // Check if it's a JSON code block with our schema
        if lang == "json" || code.trim().starts_with('{') {
            if let Ok(data) = serde_json::from_str::<serde_json::Value>(code.trim()) {
                if data.get("changes").is_some() {
                    if let Some(changes_val) = data.get("changes") {
                        if let Ok(changes) = serde_json::from_value::<Vec<Change>>(changes_val.clone()) {
                            result.changes = Some(changes);
                        }
                    }
                    result.language = data.get("language").and_then(|v| v.as_str()).map(|s| s.to_string());
                    result.explanation = data.get("explanation")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string())
                        .or(Some("Generated changes".to_string()));
                    result.format_detected = "json_response".to_string();
                    result.warning = Some("JSON was wrapped in ```json``` - AI should return raw JSON only".to_string());
                    return;
                }
            }
        }

        code_blocks.push((lang, code));
    }

    // Extract explanation text outside code blocks
    let explanation_text = code_block_re.replace_all(response, "").trim().to_string();

    if let Some((lang, code)) = code_blocks.first() {
        result.code = Some(code.trim().to_string());
        if !lang.is_empty() {
            result.language = Some(lang.clone());
        }

        if !looks_like_code(&explanation_text) && !explanation_text.is_empty() {
            result.explanation = Some(explanation_text);
        }
    } else if looks_like_code(&explanation_text) {
        result.code = Some(explanation_text);
        result.explanation = Some("Generated code".to_string());
    } else {
        result.explanation = Some(explanation_text);
    }
}

fn parse_generic(response: &str, result: &mut ParseResult) {
    // Try to extract code blocks
    let code_block_re = Regex::new(r"(?s)```\w*\s*\n(.*?)\n```").unwrap();
    if let Some(cap) = code_block_re.captures(response) {
        result.code = Some(cap[1].trim().to_string());
        return;
    }

    if looks_like_code(response) {
        result.code = Some(response.trim().to_string());
        result.explanation = Some("Generated code".to_string());
        return;
    }

    // Try to separate code from explanation
    let mut code_lines = Vec::new();
    let mut explanation_lines = Vec::new();
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

    #[test]
    fn test_parse_json_response() {
        let response = r#"{"mode":"changes","filename":"test.py","changes":[{"search":"old","replace":"new","description":"test"}],"explanation":"Updated code"}"#;
        let result = parse(response, None);
        assert_eq!(result.format_detected, "json_response");
        assert_eq!(result.mode, Some("changes".to_string()));
        assert_eq!(result.filename, Some("test.py".to_string()));
        assert!(result.changes.is_some());
    }

    #[test]
    fn test_parse_chat_response() {
        let response = r#"{"mode":"chat","explanation":"Here is the answer"}"#;
        let result = parse(response, None);
        assert_eq!(result.mode, Some("chat".to_string()));
        assert_eq!(result.explanation, Some("Here is the answer".to_string()));
    }

    #[test]
    fn test_detect_format_json() {
        assert_eq!(detect_format(r#"{"mode":"chat"}"#), "json_response");
    }

    #[test]
    fn test_detect_format_markdown() {
        assert_eq!(detect_format("```python\nprint('hello')\n```"), "markdown_formatted");
    }

    #[test]
    fn test_extract_thinking_tags() {
        let response = "<thinking>I need to analyze this</thinking>\nHere is my answer";
        let result = extract_thinking_tags(response);
        assert!(result.contains_key("thinking"));
    }

    #[test]
    fn test_looks_like_code() {
        assert!(looks_like_code("def foo():\n    return 42"));
        assert!(looks_like_code("import os\nfrom sys import path"));
        assert!(!looks_like_code("This is a plain text explanation."));
    }
}
