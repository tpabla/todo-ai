use async_trait::async_trait;
use tokio::process::Command;

use crate::config::Config;

use super::{ChatMessage, Provider, ProviderResult};

pub struct ClaudeCliProvider;

fn parse_cli_output(raw: &str) -> Result<String, String> {
    let data: serde_json::Value = serde_json::from_str(raw)
        .map_err(|e| format!("Failed to parse claude CLI output: {e}"))?;

    if data.get("is_error").and_then(|v| v.as_bool()).unwrap_or(false) {
        let msg = data.get("result").and_then(|v| v.as_str()).unwrap_or("unknown error");
        return Err(format!("Claude CLI error: {msg}"));
    }

    data.get("result")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .ok_or_else(|| "No content in claude CLI response".to_string())
}

async fn run_claude_cli(system_prompt: &str, prompt: &str) -> Result<String, String> {
    let output = Command::new("claude")
        .args([
            "-p",
            "--output-format", "json",
            "--system-prompt", system_prompt,
            "--no-session-persistence",
        ])
        .env("CLAUDECODE", "")
        .env("ANTHROPIC_API_KEY", "")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .map_err(|e| format!("Failed to spawn claude CLI: {e}"))?;

    // Write prompt to stdin
    use tokio::io::AsyncWriteExt;
    let mut child = output;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(prompt.as_bytes()).await
            .map_err(|e| format!("Failed to write to claude stdin: {e}"))?;
        drop(stdin); // Close stdin
    }

    let output = child.wait_with_output().await
        .map_err(|e| format!("Failed to wait for claude CLI: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!(
            "claude CLI failed (code {}): {stderr}",
            output.status.code().unwrap_or(-1)
        ));
    }

    let raw = String::from_utf8_lossy(&output.stdout).to_string();
    parse_cli_output(&raw)
}

#[async_trait]
impl Provider for ClaudeCliProvider {
    async fn complete(
        &self,
        system_prompt: &str,
        user_prompt: &str,
        _config: &Config,
    ) -> Result<ProviderResult, String> {
        let content = run_claude_cli(system_prompt, user_prompt).await?;
        Ok(ProviderResult {
            content,
            provider_hint: "claude".to_string(),
        })
    }

    async fn chat(
        &self,
        system_prompt: &str,
        messages: &[ChatMessage],
        _config: &Config,
    ) -> Result<ProviderResult, String> {
        // Format messages into a single prompt
        let mut parts = Vec::new();
        for msg in messages {
            let role = if msg.role == "ai" { "assistant" } else { &msg.role };
            parts.push(format!("[{role}]: {}", msg.content));
        }
        let prompt = parts.join("\n\n");

        let content = run_claude_cli(system_prompt, &prompt).await?;
        Ok(ProviderResult {
            content,
            provider_hint: "claude".to_string(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_cli_output_success() {
        let raw = r#"{"result": "hello world", "is_error": false}"#;
        let result = parse_cli_output(raw);
        assert_eq!(result.unwrap(), "hello world");
    }

    #[test]
    fn test_parse_cli_output_error() {
        let raw = r#"{"result": "something went wrong", "is_error": true}"#;
        let result = parse_cli_output(raw);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Claude CLI error"));
    }

    #[test]
    fn test_parse_cli_output_empty() {
        let raw = r#"{"result": "", "is_error": false}"#;
        let result = parse_cli_output(raw);
        assert!(result.is_err());
    }

    #[test]
    fn test_parse_cli_output_invalid_json() {
        let result = parse_cli_output("not json");
        assert!(result.is_err());
    }
}
