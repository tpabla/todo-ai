use async_trait::async_trait;
use serde_json::json;
use std::collections::HashMap;

use crate::config::Config;
use crate::http;
use crate::retry::{self, RetryConfig};

use super::{ChatMessage, Provider, ProviderResult};

pub struct OllamaProvider;

fn get_base_url() -> String {
    std::env::var("OLLAMA_URL").unwrap_or_else(|_| "http://localhost:11434".to_string())
}

fn build_headers() -> HashMap<String, String> {
    let mut headers = HashMap::new();
    headers.insert("content-type".to_string(), "application/json".to_string());
    headers
}

fn extract_generate_content(body: &serde_json::Value) -> Result<String, String> {
    body.get("response")
        .and_then(|r| r.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| "No response from Ollama".to_string())
}

fn extract_chat_content(body: &serde_json::Value) -> Result<String, String> {
    body.get("message")
        .and_then(|m| m.get("content"))
        .and_then(|c| c.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| "No content in Ollama chat response".to_string())
}

#[async_trait]
impl Provider for OllamaProvider {
    async fn complete(
        &self,
        system_prompt: &str,
        user_prompt: &str,
        config: &Config,
    ) -> Result<ProviderResult, String> {
        let base_url = get_base_url();
        let url = format!("{base_url}/api/generate");
        let headers = build_headers();

        // Ollama generate uses a combined prompt
        let combined = format!("{system_prompt}\n\n{user_prompt}");

        let body = json!({
            "model": config.model,
            "prompt": combined,
            "temperature": config.temperature,
            "stream": false
        });

        let timeout = config.timeouts.llm_request;
        let retry_config = RetryConfig::default();

        let response = retry::with_retry(&retry_config, || {
            let url = url.clone();
            let headers = headers.clone();
            let body = body.clone();
            async move {
                http::request(&url, "POST", &headers, Some(&body), timeout).await
            }
        })
        .await?;

        let content = extract_generate_content(&response.body)?;
        Ok(ProviderResult {
            content,
            provider_hint: "ollama".to_string(),
        })
    }

    async fn chat(
        &self,
        system_prompt: &str,
        messages: &[ChatMessage],
        config: &Config,
    ) -> Result<ProviderResult, String> {
        let base_url = get_base_url();
        let url = format!("{base_url}/api/chat");
        let headers = build_headers();

        let mut ollama_messages: Vec<serde_json::Value> = vec![
            json!({"role": "system", "content": system_prompt})
        ];

        for msg in messages {
            let role = if msg.role == "ai" { "assistant" } else { &msg.role };
            ollama_messages.push(json!({"role": role, "content": msg.content}));
        }

        let body = json!({
            "model": config.model,
            "messages": ollama_messages,
            "temperature": config.temperature,
            "stream": false
        });

        let timeout = config.timeouts.llm_request;
        let retry_config = RetryConfig::default();

        let response = retry::with_retry(&retry_config, || {
            let url = url.clone();
            let headers = headers.clone();
            let body = body.clone();
            async move {
                http::request(&url, "POST", &headers, Some(&body), timeout).await
            }
        })
        .await?;

        let content = extract_chat_content(&response.body)?;
        Ok(ProviderResult {
            content,
            provider_hint: "ollama".to_string(),
        })
    }
}
