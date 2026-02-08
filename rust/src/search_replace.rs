use crate::protocol::{
    ApplyChangesResult, Change, ChangeRegion, PositionInfo,
};

/// Apply a single SEARCH/REPLACE transformation
pub fn apply_single(content: &str, search_text: &str, replace_text: &str) -> Result<String, String> {
    match content.find(search_text) {
        Some(start_pos) => {
            let end_pos = start_pos + search_text.len();
            let mut result = String::with_capacity(content.len() - search_text.len() + replace_text.len());
            result.push_str(&content[..start_pos]);
            result.push_str(replace_text);
            result.push_str(&content[end_pos..]);
            Ok(result)
        }
        None => Err("Search text not found".to_string()),
    }
}

/// Apply multiple SEARCH/REPLACE changes to lines
pub fn apply_changes(lines: &[String], changes: &[Change]) -> ApplyChangesResult {
    let mut content = lines.join("\n");
    let mut applied_count = 0;
    let mut errors = Vec::new();

    for (i, change) in changes.iter().enumerate() {
        if change.search.is_empty() && change.replace.is_empty() {
            errors.push(format!("Change {}: missing search or replace field", i + 1));
            continue;
        }

        match apply_single(&content, &change.search, &change.replace) {
            Ok(result) => {
                content = result;
                applied_count += 1;
            }
            Err(err) => {
                errors.push(format!("Change {}: {}", i + 1, err));
            }
        }
    }

    let new_lines: Vec<String> = content.split('\n').map(|s| s.to_string()).collect();

    let error_str = if errors.is_empty() {
        None
    } else {
        Some(errors.join("; "))
    };

    ApplyChangesResult {
        lines: new_lines,
        applied_count,
        errors: error_str,
    }
}

/// Calculate position information for a change
pub fn calculate_position(content: &str, search_text: &str) -> Option<PositionInfo> {
    let start_pos = content.find(search_text)?;
    let end_pos = start_pos + search_text.len();

    let before = &content[..start_pos];
    let start_line = before.matches('\n').count() + 1;
    let search_lines = search_text.matches('\n').count() + 1;
    let end_line = start_line + search_lines - 1;

    Some(PositionInfo {
        start_pos,
        end_pos,
        start_line,
        end_line,
        line_count: search_lines,
    })
}

/// Track change regions for navigation
pub fn track_change_regions(
    lines: &[String],
    changes: &[Change],
    rejected_indices: &[usize],
) -> Vec<ChangeRegion> {
    let content = lines.join("\n");
    let mut regions = Vec::new();

    for (i, change) in changes.iter().enumerate() {
        if rejected_indices.contains(&i) {
            continue;
        }

        if let Some(pos_info) = calculate_position(&content, &change.search) {
            let replace_lines: Vec<&str> = change.replace.split('\n').collect();

            regions.push(ChangeRegion {
                change_index: i,
                original_start: pos_info.start_line,
                original_end: pos_info.end_line,
                new_line_count: replace_lines.len(),
                search_text: change.search.clone(),
                replace_text: change.replace.clone(),
                description: change.description.clone(),
            });
        }
    }

    regions
}

/// Validate a single change structure
pub fn validate_change(change: &Change) -> Result<(), String> {
    if change.search.is_empty() && change.replace.is_empty() {
        return Err("Both search and replace are empty".to_string());
    }
    Ok(())
}

/// Validate all changes
pub fn validate_changes(changes: &[Change]) -> Result<(), String> {
    for (i, change) in changes.iter().enumerate() {
        if let Err(err) = validate_change(change) {
            return Err(format!("Change {}: {}", i + 1, err));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_apply_single() {
        let content = "hello world";
        let result = apply_single(content, "world", "rust").unwrap();
        assert_eq!(result, "hello rust");
    }

    #[test]
    fn test_apply_single_not_found() {
        let content = "hello world";
        let result = apply_single(content, "missing", "rust");
        assert!(result.is_err());
    }

    #[test]
    fn test_apply_changes() {
        let lines = vec!["hello world".to_string(), "foo bar".to_string()];
        let changes = vec![Change {
            search: "world".to_string(),
            replace: "rust".to_string(),
            description: None,
        }];
        let result = apply_changes(&lines, &changes);
        assert_eq!(result.applied_count, 1);
        assert_eq!(result.lines, vec!["hello rust", "foo bar"]);
        assert!(result.errors.is_none());
    }

    #[test]
    fn test_calculate_position() {
        let content = "line 1\nline 2\nline 3";
        let pos = calculate_position(content, "line 2").unwrap();
        assert_eq!(pos.start_line, 2);
        assert_eq!(pos.end_line, 2);
        assert_eq!(pos.line_count, 1);
    }

    #[test]
    fn test_track_change_regions() {
        let lines = vec![
            "def foo():".to_string(),
            "    pass".to_string(),
        ];
        let changes = vec![Change {
            search: "    pass".to_string(),
            replace: "    return 42".to_string(),
            description: Some("Return value".to_string()),
        }];
        let regions = track_change_regions(&lines, &changes, &[]);
        assert_eq!(regions.len(), 1);
        assert_eq!(regions[0].original_start, 2);
    }
}
