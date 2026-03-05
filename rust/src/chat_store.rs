use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

/// A single chat message for persistence.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
    pub timestamp: String,
    #[serde(default)]
    pub is_thinking: bool,
}

/// Metadata about a saved chat session.
#[derive(Debug, Clone, Serialize)]
pub struct SessionInfo {
    pub id: String,
    pub file: String,
    pub mtime: String,
    pub size: u64,
}

/// Save chat messages to a markdown file.
pub fn save_chat(
    project_root: &str,
    session_id: &str,
    session_start: &str,
    messages: &[ChatMessage],
) -> Result<String, String> {
    let chat_dir = format!("{project_root}/.todoai/chats");

    // Create directory
    fs::create_dir_all(&chat_dir)
        .map_err(|e| format!("Failed to create chat dir: {e}"))?;

    let chat_file = format!("{chat_dir}/{session_id}.md");

    // Build markdown content
    let mut lines = Vec::new();
    lines.push(format!("# Todo-AI Chat Session: {session_id}"));
    lines.push(format!("Started: {session_start}"));
    lines.push(format!("Last Updated: {}", chrono::Local::now().format("%Y-%m-%d %H:%M:%S")));
    lines.push(String::new());
    lines.push("## Messages".to_string());
    lines.push(String::new());

    for msg in messages {
        if msg.is_thinking {
            continue;
        }

        let role_label = if msg.role == "user" {
            "👤 User"
        } else {
            "🤖 AI"
        };

        lines.push(format!("### {role_label} _[{}]_", msg.timestamp));
        lines.push(String::new());

        for line in msg.content.lines() {
            lines.push(line.to_string());
        }

        lines.push(String::new());
        lines.push("---".to_string());
        lines.push(String::new());
    }

    let content = lines.join("\n");
    fs::write(&chat_file, &content)
        .map_err(|e| format!("Failed to write chat file: {e}"))?;

    Ok(chat_file)
}

/// Load a chat session from a markdown file.
pub fn load_chat(
    project_root: &str,
    session_id: &str,
) -> Result<Vec<ChatMessage>, String> {
    let chat_file = format!("{project_root}/.todoai/chats/{session_id}.md");

    let content = fs::read_to_string(&chat_file)
        .map_err(|e| format!("Failed to read chat file: {e}"))?;

    let mut messages = Vec::new();
    let mut current_role: Option<String> = None;
    let mut current_content: Vec<String> = Vec::new();
    let mut current_time = String::new();

    for line in content.lines() {
        if let Some(time) = parse_user_header(line) {
            // Save previous message
            if let Some(role) = current_role.take() {
                if !current_content.is_empty() {
                    let content = current_content.join("\n").trim().to_string();
                    messages.push(ChatMessage {
                        role,
                        content,
                        timestamp: current_time.clone(),
                        is_thinking: false,
                    });
                }
            }
            current_role = Some("user".to_string());
            current_time = time;
            current_content.clear();
        } else if let Some(time) = parse_ai_header(line) {
            if let Some(role) = current_role.take() {
                if !current_content.is_empty() {
                    let content = current_content.join("\n").trim().to_string();
                    messages.push(ChatMessage {
                        role,
                        content,
                        timestamp: current_time.clone(),
                        is_thinking: false,
                    });
                }
            }
            current_role = Some("ai".to_string());
            current_time = time;
            current_content.clear();
        } else if line == "---" {
            if let Some(role) = current_role.take() {
                if !current_content.is_empty() {
                    let content = current_content.join("\n").trim().to_string();
                    messages.push(ChatMessage {
                        role,
                        content,
                        timestamp: current_time.clone(),
                        is_thinking: false,
                    });
                }
            }
            current_content.clear();
        } else if current_role.is_some() && !line.starts_with('#') {
            current_content.push(line.to_string());
        }
    }

    // Don't forget last message
    if let Some(role) = current_role {
        if !current_content.is_empty() {
            let content = current_content.join("\n").trim().to_string();
            messages.push(ChatMessage {
                role,
                content,
                timestamp: current_time,
                is_thinking: false,
            });
        }
    }

    Ok(messages)
}

/// List available chat sessions, sorted newest first.
pub fn list_chats(project_root: &str) -> Vec<SessionInfo> {
    let chat_dir = format!("{project_root}/.todoai/chats");
    let dir_path = Path::new(&chat_dir);

    if !dir_path.exists() {
        return Vec::new();
    }

    let mut sessions: Vec<SessionInfo> = Vec::new();

    if let Ok(entries) = fs::read_dir(dir_path) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map_or(false, |e| e == "md") {
                let id = path
                    .file_stem()
                    .map(|s| s.to_string_lossy().to_string())
                    .unwrap_or_default();

                if let Ok(meta) = fs::metadata(&path) {
                    let mtime = meta
                        .modified()
                        .ok()
                        .and_then(|t| {
                            let datetime: chrono::DateTime<chrono::Local> = t.into();
                            Some(datetime.format("%Y-%m-%d %H:%M:%S").to_string())
                        })
                        .unwrap_or_default();

                    sessions.push(SessionInfo {
                        id,
                        file: path.to_string_lossy().to_string(),
                        mtime,
                        size: meta.len(),
                    });
                }
            }
        }
    }

    // Sort newest first
    sessions.sort_by(|a, b| b.mtime.cmp(&a.mtime));
    sessions
}

/// Remove old sessions beyond max_sessions count.
pub fn cleanup_old_sessions(project_root: &str, max_sessions: usize) -> usize {
    let mut sessions = list_chats(project_root);

    if sessions.len() <= max_sessions {
        return 0;
    }

    // Sessions are sorted newest first, so remove from the end
    let to_remove = sessions.len() - max_sessions;
    let mut removed = 0;

    for session in sessions.iter().rev().take(to_remove) {
        if fs::remove_file(&session.file).is_ok() {
            removed += 1;
        }
    }

    removed
}

// --- Helpers ---

fn parse_user_header(line: &str) -> Option<String> {
    // ### 👤 User _[HH:MM]_
    if line.starts_with("### 👤 User") {
        extract_timestamp(line)
    } else {
        None
    }
}

fn parse_ai_header(line: &str) -> Option<String> {
    // ### 🤖 AI _[HH:MM]_
    if line.starts_with("### 🤖 AI") {
        extract_timestamp(line)
    } else {
        None
    }
}

fn extract_timestamp(line: &str) -> Option<String> {
    let start = line.find('[')?;
    let end = line.find(']')?;
    if end > start {
        Some(line[start + 1..end].to_string())
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_save_and_load_chat() {
        let dir = std::env::temp_dir().join("todo-ai-chat-test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let messages = vec![
            ChatMessage {
                role: "user".to_string(),
                content: "Hello AI".to_string(),
                timestamp: "10:30".to_string(),
                is_thinking: false,
            },
            ChatMessage {
                role: "ai".to_string(),
                content: "Hello! How can I help?".to_string(),
                timestamp: "10:30".to_string(),
                is_thinking: false,
            },
            ChatMessage {
                role: "user".to_string(),
                content: "Fix this bug".to_string(),
                timestamp: "10:31".to_string(),
                is_thinking: false,
            },
        ];

        // Save
        let result = save_chat(
            dir.to_str().unwrap(),
            "test_session",
            "2026-03-05 10:30:00",
            &messages,
        );
        assert!(result.is_ok());

        // Load
        let loaded = load_chat(dir.to_str().unwrap(), "test_session");
        assert!(loaded.is_ok());
        let loaded = loaded.unwrap();
        assert_eq!(loaded.len(), 3);
        assert_eq!(loaded[0].role, "user");
        assert_eq!(loaded[0].content, "Hello AI");
        assert_eq!(loaded[1].role, "ai");
        assert_eq!(loaded[1].content, "Hello! How can I help?");
        assert_eq!(loaded[2].role, "user");
        assert_eq!(loaded[2].content, "Fix this bug");

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_save_skips_thinking_messages() {
        let dir = std::env::temp_dir().join("todo-ai-chat-thinking-test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let messages = vec![
            ChatMessage {
                role: "user".to_string(),
                content: "Hello".to_string(),
                timestamp: "10:30".to_string(),
                is_thinking: false,
            },
            ChatMessage {
                role: "ai".to_string(),
                content: "Thinking...".to_string(),
                timestamp: "10:30".to_string(),
                is_thinking: true,
            },
            ChatMessage {
                role: "ai".to_string(),
                content: "Here is my answer".to_string(),
                timestamp: "10:31".to_string(),
                is_thinking: false,
            },
        ];

        save_chat(dir.to_str().unwrap(), "thinking_test", "2026-03-05", &messages).unwrap();
        let loaded = load_chat(dir.to_str().unwrap(), "thinking_test").unwrap();
        assert_eq!(loaded.len(), 2); // thinking message excluded
        assert_eq!(loaded[1].content, "Here is my answer");

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_list_chats() {
        let dir = std::env::temp_dir().join("todo-ai-chat-list-test");
        let _ = fs::remove_dir_all(&dir);
        let chat_dir = dir.join(".todoai/chats");
        fs::create_dir_all(&chat_dir).unwrap();

        fs::write(chat_dir.join("session1.md"), "# Session 1").unwrap();
        fs::write(chat_dir.join("session2.md"), "# Session 2").unwrap();
        fs::write(chat_dir.join("not_a_session.txt"), "nope").unwrap();

        let sessions = list_chats(dir.to_str().unwrap());
        assert_eq!(sessions.len(), 2);
        assert!(sessions.iter().any(|s| s.id == "session1"));
        assert!(sessions.iter().any(|s| s.id == "session2"));

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_cleanup_old_sessions() {
        let dir = std::env::temp_dir().join("todo-ai-chat-cleanup-test");
        let _ = fs::remove_dir_all(&dir);
        let chat_dir = dir.join(".todoai/chats");
        fs::create_dir_all(&chat_dir).unwrap();

        // Create 5 sessions
        for i in 1..=5 {
            fs::write(
                chat_dir.join(format!("session{i}.md")),
                format!("# Session {i}"),
            )
            .unwrap();
        }

        // Cleanup to keep only 3
        let removed = cleanup_old_sessions(dir.to_str().unwrap(), 3);
        assert_eq!(removed, 2);

        let remaining = list_chats(dir.to_str().unwrap());
        assert_eq!(remaining.len(), 3);

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_load_nonexistent_session() {
        let result = load_chat("/tmp/nonexistent", "no_such_session");
        assert!(result.is_err());
    }

    #[test]
    fn test_extract_timestamp() {
        assert_eq!(
            extract_timestamp("### 👤 User _[10:30]_"),
            Some("10:30".to_string())
        );
        assert_eq!(
            extract_timestamp("### 🤖 AI _[14:22]_"),
            Some("14:22".to_string())
        );
        assert_eq!(extract_timestamp("no timestamp here"), None);
    }

    #[test]
    fn test_multiline_message() {
        let dir = std::env::temp_dir().join("todo-ai-chat-multiline-test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let messages = vec![ChatMessage {
            role: "ai".to_string(),
            content: "Line 1\nLine 2\n```rust\nfn main() {}\n```".to_string(),
            timestamp: "10:30".to_string(),
            is_thinking: false,
        }];

        save_chat(dir.to_str().unwrap(), "multiline", "2026-03-05", &messages).unwrap();
        let loaded = load_chat(dir.to_str().unwrap(), "multiline").unwrap();
        assert_eq!(loaded.len(), 1);
        assert!(loaded[0].content.contains("Line 1"));
        assert!(loaded[0].content.contains("fn main()"));

        let _ = fs::remove_dir_all(&dir);
    }
}
