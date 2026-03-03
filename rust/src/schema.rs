use serde_json::Value;

/// Validate an LLM response against the expected schema.
/// Returns Ok(()) on success, Err(Vec<String>) with validation errors.
pub fn validate_response(response: &Value) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();

    let obj = match response.as_object() {
        Some(o) => o,
        None => {
            errors.push("Response is not a JSON object".to_string());
            return Err(errors);
        }
    };

    // Check for mode field at root level
    let mode = match obj.get("mode").and_then(|v| v.as_str()) {
        Some(m) => m,
        None => {
            errors.push(
                "MISSING 'mode' field at root level - must include \"mode\": \"changes\" or \"mode\": \"chat\""
                    .to_string(),
            );
            // Can't validate further without mode
            return Err(errors);
        }
    };

    if mode != "changes" && mode != "chat" {
        errors.push(format!(
            "INVALID mode '{mode}' - must be either 'changes' or 'chat'"
        ));
        return Err(errors);
    }

    if mode == "changes" {
        validate_changes_mode(obj, &mut errors);
    } else if mode == "chat" {
        validate_chat_mode(obj, &mut errors);
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

fn validate_changes_mode(obj: &serde_json::Map<String, Value>, errors: &mut Vec<String>) {
    // filename
    match obj.get("filename") {
        None => errors.push(
            "MISSING 'filename' field - must specify which file to create/modify".to_string(),
        ),
        Some(v) => {
            if !v.is_string() || v.as_str().map_or(true, |s| s.is_empty()) {
                errors.push(
                    "INVALID 'filename' - must be a non-empty string with the target filename"
                        .to_string(),
                );
            }
        }
    }

    // changes array
    match obj.get("changes") {
        None => errors
            .push("MISSING 'changes' array - must provide array of search/replace operations".to_string()),
        Some(v) => {
            if let Some(arr) = v.as_array() {
                if arr.is_empty() {
                    errors.push(
                        "EMPTY 'changes' array - must contain at least one search/replace operation"
                            .to_string(),
                    );
                } else {
                    for (i, change) in arr.iter().enumerate() {
                        let idx = i + 1;
                        if let Some(change_obj) = change.as_object() {
                            // search field: must exist (can be empty string for new files)
                            if !change_obj.contains_key("search") {
                                errors.push(format!(
                                    "Change #{idx} missing 'search' field - use empty string \"\" for new files"
                                ));
                            }
                            if !change_obj.contains_key("replace") {
                                errors.push(format!(
                                    "Change #{idx} missing 'replace' field - must include replacement content"
                                ));
                            }
                        } else {
                            errors.push(format!("Change #{idx} is not a JSON object"));
                        }
                    }
                }
            } else {
                errors.push("INVALID 'changes' - must be an array of change objects".to_string());
            }
        }
    }

    // explanation
    if !obj.contains_key("explanation") {
        errors.push("MISSING 'explanation' field - should explain what changes were made".to_string());
    }
}

fn validate_chat_mode(obj: &serde_json::Map<String, Value>, errors: &mut Vec<String>) {
    if !obj.contains_key("explanation") {
        errors.push(
            "MISSING 'explanation' field - chat responses must include explanation text".to_string(),
        );
    }
}

/// Format validation errors into a human-readable markdown string.
pub fn format_validation_errors(errors: &[String]) -> String {
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
        lines.push(format!("- {error}"));
    }

    lines.push(String::new());
    lines.push("### Expected Schema for Code Changes:".to_string());
    lines.push("```json".to_string());
    lines.push(r#"{
  "mode": "changes",
  "filename": "exact_file.py",
  "changes": [
    {
      "search": "",
      "replace": "file content",
      "description": "what this does"
    }
  ],
  "explanation": "Summary of changes"
}"#.to_string());
    lines.push("```".to_string());
    lines.push(String::new());
    lines.push("**Try rephrasing your request or report this issue if it persists.**".to_string());

    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_valid_changes_response() {
        let response = json!({
            "mode": "changes",
            "filename": "test.py",
            "changes": [
                {"search": "old", "replace": "new", "description": "update"}
            ],
            "explanation": "Updated code"
        });
        assert!(validate_response(&response).is_ok());
    }

    #[test]
    fn test_valid_chat_response() {
        let response = json!({
            "mode": "chat",
            "explanation": "Here's how it works..."
        });
        assert!(validate_response(&response).is_ok());
    }

    #[test]
    fn test_missing_mode() {
        let response = json!({"filename": "test.py"});
        let err = validate_response(&response).unwrap_err();
        assert!(err[0].contains("MISSING 'mode'"));
    }

    #[test]
    fn test_invalid_mode() {
        let response = json!({"mode": "invalid"});
        let err = validate_response(&response).unwrap_err();
        assert!(err[0].contains("INVALID mode"));
    }

    #[test]
    fn test_changes_missing_filename() {
        let response = json!({
            "mode": "changes",
            "changes": [{"search": "", "replace": "content"}],
            "explanation": "New file"
        });
        let err = validate_response(&response).unwrap_err();
        assert!(err.iter().any(|e| e.contains("MISSING 'filename'")));
    }

    #[test]
    fn test_changes_empty_array() {
        let response = json!({
            "mode": "changes",
            "filename": "test.py",
            "changes": [],
            "explanation": "Nothing"
        });
        let err = validate_response(&response).unwrap_err();
        assert!(err.iter().any(|e| e.contains("EMPTY 'changes'")));
    }

    #[test]
    fn test_changes_missing_search_replace() {
        let response = json!({
            "mode": "changes",
            "filename": "test.py",
            "changes": [{"description": "missing fields"}],
            "explanation": "Bad"
        });
        let err = validate_response(&response).unwrap_err();
        assert!(err.iter().any(|e| e.contains("missing 'search'")));
        assert!(err.iter().any(|e| e.contains("missing 'replace'")));
    }

    #[test]
    fn test_chat_missing_explanation() {
        let response = json!({"mode": "chat"});
        let err = validate_response(&response).unwrap_err();
        assert!(err.iter().any(|e| e.contains("MISSING 'explanation'")));
    }

    #[test]
    fn test_new_file_empty_search() {
        let response = json!({
            "mode": "changes",
            "filename": "new_file.py",
            "changes": [{"search": "", "replace": "content"}],
            "explanation": "New file"
        });
        assert!(validate_response(&response).is_ok());
    }

    #[test]
    fn test_not_an_object() {
        let response = json!("just a string");
        let err = validate_response(&response).unwrap_err();
        assert!(err[0].contains("not a JSON object"));
    }

    #[test]
    fn test_format_errors() {
        let errors = vec!["Missing mode".to_string(), "Missing filename".to_string()];
        let formatted = format_validation_errors(&errors);
        assert!(formatted.contains("Missing mode"));
        assert!(formatted.contains("Missing filename"));
        assert!(formatted.contains("Schema Validation Failed"));
    }
}
