use crate::protocol::{ParseResult, ValidationResult};

/// Validate response against expected schema
pub fn validate_response(response: &ParseResult) -> ValidationResult {
    let mut errors = Vec::new();

    // Check for mode field at root level
    match &response.mode {
        None => {
            errors.push("MISSING 'mode' field at root level - LLM must include \"mode\": \"changes\" or \"mode\": \"chat\"".to_string());
        }
        Some(mode) if mode != "changes" && mode != "chat" => {
            errors.push(format!("INVALID mode '{}' - must be either 'changes' or 'chat'", mode));
        }
        _ => {}
    }

    // If mode is changes, validate required fields
    if response.mode.as_deref() == Some("changes") {
        match &response.filename {
            None => {
                errors.push("MISSING 'filename' field - LLM must specify which file to create/modify".to_string());
            }
            Some(f) if f.is_empty() => {
                errors.push("INVALID 'filename' - must be a non-empty string with the target filename".to_string());
            }
            _ => {}
        }

        match &response.changes {
            None => {
                errors.push("MISSING 'changes' array - LLM must provide array of search/replace operations".to_string());
            }
            Some(changes) if changes.is_empty() => {
                errors.push("EMPTY 'changes' array - must contain at least one search/replace operation".to_string());
            }
            Some(changes) => {
                for (i, change) in changes.iter().enumerate() {
                    // search can be empty string for new files, but replace must exist
                    if change.replace.is_empty() && change.search.is_empty() {
                        errors.push(format!(
                            "Change #{} missing both 'search' and 'replace' fields",
                            i + 1
                        ));
                    }
                }
            }
        }

        if response.explanation.is_none() {
            errors.push("MISSING 'explanation' field - should explain what changes were made".to_string());
        }
    } else if response.mode.as_deref() == Some("chat") {
        if response.explanation.is_none() {
            errors.push("MISSING 'explanation' field - chat responses must include explanation text".to_string());
        }
    }

    if errors.is_empty() {
        ValidationResult {
            valid: true,
            errors: None,
            formatted_error: None,
        }
    } else {
        let formatted = format_validation_errors(&errors);
        ValidationResult {
            valid: false,
            errors: Some(errors),
            formatted_error: Some(formatted),
        }
    }
}

fn format_validation_errors(errors: &[String]) -> String {
    let mut lines = vec![
        "## LLM Response Schema Validation Failed".to_string(),
        String::new(),
        "The LLM's response doesn't match the required schema. This usually means:".to_string(),
        "1. The LLM didn't follow instructions properly".to_string(),
        "2. The response JSON is malformed".to_string(),
        "3. Required fields are missing or in wrong locations".to_string(),
        String::new(),
        "### Validation Errors:".to_string(),
        String::new(),
    ];

    for error in errors {
        lines.push(format!("- {}", error));
    }

    lines.push(String::new());
    lines.push("### Expected Schema for Code Changes:".to_string());
    lines.push("```json".to_string());
    lines.push("{".to_string());
    lines.push("  \"mode\": \"changes\",".to_string());
    lines.push("  \"filename\": \"exact_file.py\",".to_string());
    lines.push("  \"changes\": [".to_string());
    lines.push("    {".to_string());
    lines.push("      \"search\": \"\",  // empty for new files".to_string());
    lines.push("      \"replace\": \"file content\",".to_string());
    lines.push("      \"description\": \"what this does\"".to_string());
    lines.push("    }".to_string());
    lines.push("  ],".to_string());
    lines.push("  \"explanation\": \"Summary of changes\"".to_string());
    lines.push("}".to_string());
    lines.push("```".to_string());
    lines.push(String::new());
    lines.push("**Try rephrasing your request or report this issue if it persists.**".to_string());

    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::Change;

    fn make_changes_response() -> ParseResult {
        ParseResult {
            raw_response: String::new(),
            format_detected: "json_response".to_string(),
            mode: Some("changes".to_string()),
            filename: Some("test.py".to_string()),
            changes: Some(vec![Change {
                search: "old".to_string(),
                replace: "new".to_string(),
                description: Some("test".to_string()),
            }]),
            language: None,
            explanation: Some("Updated code".to_string()),
            code: None,
            thinking: None,
            thinking_formatted: None,
            parse_error: None,
            warning: None,
        }
    }

    #[test]
    fn test_valid_changes_response() {
        let response = make_changes_response();
        let result = validate_response(&response);
        assert!(result.valid);
        assert!(result.errors.is_none());
    }

    #[test]
    fn test_missing_mode() {
        let mut response = make_changes_response();
        response.mode = None;
        let result = validate_response(&response);
        assert!(!result.valid);
    }

    #[test]
    fn test_missing_filename() {
        let mut response = make_changes_response();
        response.filename = None;
        let result = validate_response(&response);
        assert!(!result.valid);
    }

    #[test]
    fn test_valid_chat_response() {
        let response = ParseResult {
            raw_response: String::new(),
            format_detected: "json_response".to_string(),
            mode: Some("chat".to_string()),
            filename: None,
            changes: None,
            language: None,
            explanation: Some("Here is an answer".to_string()),
            code: None,
            thinking: None,
            thinking_formatted: None,
            parse_error: None,
            warning: None,
        };
        let result = validate_response(&response);
        assert!(result.valid);
    }

    #[test]
    fn test_chat_missing_explanation() {
        let response = ParseResult {
            raw_response: String::new(),
            format_detected: "json_response".to_string(),
            mode: Some("chat".to_string()),
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
        let result = validate_response(&response);
        assert!(!result.valid);
    }
}
