use async_trait::async_trait;
use serde_json::json;
use std::collections::HashMap;

use crate::config::Config;
use crate::http;
use crate::retry::{self, RetryConfig};

use super::{ChatMessage, Provider, ProviderResult};

pub struct ClaudeProvider;

const API_URL: &str = "https://api.anthropic.com/v1/messages";

fn get_api_key() -> Result<String, String> {
    std::env::var("ANTHROPIC_API_KEY")
        .map_err(|_| "ANTHROPIC_API_KEY not set".to_string())
}

fn build_headers(api_key: &str) -> HashMap<String, String> {
    let mut headers = HashMap::new();
    headers.insert("content-type".to_string(), "application/json".to_string());
    headers.insert("x-api-key".to_string(), api_key.to_string());
    headers.insert("anthropic-version".to_string(), "2023-06-01".to_string());
    headers
}

fn extract_content(body: &serde_json::Value) -> Result<String, String> {
    // Check for API errors
    if let Some(error) = body.get("error") {
        let msg = error
            .get("message")
            .and_then(|m| m.as_str())
            .unwrap_or("unknown error");
        return Err(format!("Claude API error: {msg}"));
    }

    // Extract content from response
    body.get("content")
        .and_then(|c| c.as_array())
        .and_then(|arr| arr.first())
        .and_then(|item| item.get("text"))
        .and_then(|t| t.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| format!("No content in Claude response: {body}"))
}

#[async_trait]
impl Provider for ClaudeProvider {
    async fn complete(
        &self,
        system_prompt: &str,
        user_prompt: &str,
        config: &Config,
    ) -> Result<ProviderResult, String> {
        let api_key = get_api_key()?;
        let headers = build_headers(&api_key);

        let body = json!({
            "model": config.model,
            "max_tokens": config.max_tokens,
            "temperature": config.temperature,
            "system": system_prompt,
            "messages": [{"role": "user", "content": user_prompt}]
        });

        let timeout = config.timeouts.llm_request;
        let retry_config = RetryConfig::default();

        let response = retry::with_retry(&retry_config, || {
            let headers = headers.clone();
            let body = body.clone();
            async move {
                http::request(API_URL, "POST", &headers, Some(&body), timeout).await
            }
        })
        .await?;

        let content = extract_content(&response.body)?;
        Ok(ProviderResult {
            content,
            provider_hint: "claude".to_string(),
        })
    }

    async fn chat(
        &self,
        system_prompt: &str,
        messages: &[ChatMessage],
        config: &Config,
    ) -> Result<ProviderResult, String> {
        let api_key = get_api_key()?;
        let headers = build_headers(&api_key);

        // Convert messages to Claude format
        let claude_messages: Vec<serde_json::Value> = messages
            .iter()
            .map(|msg| {
                let role = match msg.role.as_str() {
                    "system" => "user",
                    "ai" => "assistant",
                    other => other,
                };
                let content = if msg.role == "system" {
                    format!("Context: {}", msg.content)
                } else {
                    msg.content.clone()
                };
                json!({"role": role, "content": content})
            })
            .collect();

        let body = json!({
            "model": config.model,
            "max_tokens": config.max_tokens,
            "temperature": config.temperature,
            "system": system_prompt,
            "messages": claude_messages
        });

        let timeout = config.timeouts.llm_request;
        let retry_config = RetryConfig::default();

        let response = retry::with_retry(&retry_config, || {
            let headers = headers.clone();
            let body = body.clone();
            async move {
                http::request(API_URL, "POST", &headers, Some(&body), timeout).await
            }
        })
        .await?;

        let content = extract_content(&response.body)?;
        Ok(ProviderResult {
            content,
            provider_hint: "claude".to_string(),
        })
    }
}
