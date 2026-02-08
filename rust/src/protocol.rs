use serde::{Deserialize, Serialize};

/// Incoming request from the Neovim Lua bridge
#[derive(Debug, Deserialize)]
pub struct Request {
    pub id: u64,
    pub method: String,
    #[serde(default)]
    pub params: serde_json::Value,
}

/// Outgoing response to the Neovim Lua bridge
#[derive(Debug, Serialize)]
pub struct Response {
    pub id: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl Response {
    pub fn ok(id: u64, result: serde_json::Value) -> Self {
        Self {
            id,
            result: Some(result),
            error: None,
        }
    }

    pub fn err(id: u64, error: String) -> Self {
        Self {
            id,
            result: None,
            error: Some(error),
        }
    }
}

// --- Search/Replace types ---

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct Change {
    pub search: String,
    pub replace: String,
    #[serde(default)]
    pub description: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ApplyChangesParams {
    pub lines: Vec<String>,
    pub changes: Vec<Change>,
}

#[derive(Debug, Serialize)]
pub struct ApplyChangesResult {
    pub lines: Vec<String>,
    pub applied_count: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub errors: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct CalculatePositionParams {
    pub content: String,
    pub search_text: String,
}

#[derive(Debug, Serialize)]
pub struct PositionInfo {
    pub start_pos: usize,
    pub end_pos: usize,
    pub start_line: usize,
    pub end_line: usize,
    pub line_count: usize,
}

#[derive(Debug, Deserialize)]
pub struct ValidateChangesParams {
    pub changes: Vec<Change>,
}

#[derive(Debug, Deserialize)]
pub struct TrackRegionsParams {
    pub lines: Vec<String>,
    pub changes: Vec<Change>,
    #[serde(default)]
    pub rejected_indices: Vec<usize>,
}

#[derive(Debug, Serialize)]
pub struct ChangeRegion {
    pub change_index: usize,
    pub original_start: usize,
    pub original_end: usize,
    pub new_line_count: usize,
    pub search_text: String,
    pub replace_text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
}

// --- Parser types ---

#[derive(Debug, Deserialize)]
pub struct ParseParams {
    pub response: String,
    #[serde(default)]
    pub hint: Option<String>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct ParseResult {
    pub raw_response: String,
    pub format_detected: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub filename: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub changes: Option<Vec<Change>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub explanation: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub thinking: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub thinking_formatted: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parse_error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub warning: Option<String>,
}

// --- Validator types ---

#[derive(Debug, Deserialize)]
pub struct ValidateResponseParams {
    pub response: ParseResult,
}

#[derive(Debug, Serialize)]
pub struct ValidationResult {
    pub valid: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub errors: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub formatted_error: Option<String>,
}

// --- Scanner types ---

#[derive(Debug, Deserialize)]
pub struct ScanParams {
    pub lines: Vec<String>,
    #[serde(default)]
    pub comment_string: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct TodoItem {
    pub line: usize,
    pub instruction: String,
    pub full_line: String,
    pub pattern: String,
}

#[derive(Debug, Deserialize)]
pub struct ScanProjectParams {
    pub files: Vec<FileEntry>,
}

#[derive(Debug, Deserialize)]
pub struct FileEntry {
    pub path: String,
    pub content: String,
}

#[derive(Debug, Serialize)]
pub struct ProjectTodos {
    pub todos_by_file: std::collections::HashMap<String, Vec<TodoItem>>,
    pub total_count: usize,
}

// --- Prompt types ---

#[derive(Debug, Deserialize)]
pub struct BuildPromptParams {
    pub instruction: String,
    #[serde(default)]
    pub context: Option<serde_json::Value>,
}

#[derive(Debug, Serialize)]
pub struct PromptResult {
    pub system: String,
    pub user: String,
}

// --- Provider types ---

#[derive(Debug, Deserialize)]
pub struct ProviderRequestParams {
    pub provider: String,
    pub instruction: String,
    pub context: serde_json::Value,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub temperature: Option<f64>,
    #[serde(default)]
    pub max_tokens: Option<u32>,
    #[serde(default)]
    pub api_key: Option<String>,
    #[serde(default)]
    pub messages: Option<Vec<ChatMessage>>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}
