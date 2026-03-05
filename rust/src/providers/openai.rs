use async_trait::async_trait;
use serde_json::json;
use std::collections::HashMap;

use crate::config::Config;
use crate::http;
use crate::retry::{self, RetryConfig};

use super::{ChatMessage, Provider, ProviderResult};

pub struct OpenAiProvider;

const API_URL: &str = "https://api.openai.com/v1/chat/completions";

fn get_api_key() -> Result<String, String> {
    std::env::var("OPENAI_API_KEY")
        .map_err(|_| "OPENAI_API_KEY not set".to_string())
}

fn build_headers(api_key: &str) -> HashMap<String, String> {
    let mut headers = HashMap::new();
    headers.insert("content-type".to_string(), "application/json".to_string());
    headers.insert("authorization".to_string(), format!("Bearer {api_key}"));
    headers
}

fn extract_content(body: &serde_json::Value) -> Result<String, String> {
    body.get("choices")
        .and_then(|c| c.as_array())
        .and_then(|arr| arr.first())
        .and_then(|choice| choice.get("message"))
        .and_then(|msg| msg.get("content"))
        .and_then(|c| c.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| format!("No content in OpenAI response: {body}"))
}

#[async_trait]
impl Provider for OpenAiProvider {
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
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            "temperature": config.temperature,
            "max_tokens": config.max_tokens
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
            provider_hint: "openai".to_string(),
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

        let mut openai_messages: Vec<serde_json::Value> = vec![
            json!({"role": "system", "content": system_prompt})
        ];

        for msg in messages {
            let role = if msg.role == "ai" { "assistant" } else { &msg.role };
            openai_messages.push(json!({"role": role, "content": msg.content}));
        }

        let body = json!({
            "model": config.model,
            "messages": openai_messages,
            "temperature": config.temperature,
            "max_tokens": config.max_tokens
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
            provider_hint: "openai".to_string(),
        })
    }
}
