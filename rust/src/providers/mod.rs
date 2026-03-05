pub mod claude;
pub mod claude_cli;
pub mod ollama;
pub mod openai;

use crate::config::Config;
use async_trait::async_trait;

/// Result from a provider completion call — the raw text content from the LLM.
pub struct ProviderResult {
    pub content: String,
    pub provider_hint: String,
}

/// Message for chat-style requests.
#[derive(Debug, Clone, serde::Deserialize)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

/// Provider trait — all LLM providers implement this.
#[async_trait]
pub trait Provider: Send + Sync {
    /// Complete a single instruction with context.
    async fn complete(
        &self,
        system_prompt: &str,
        user_prompt: &str,
        config: &Config,
    ) -> Result<ProviderResult, String>;

    /// Chat with message history.
    async fn chat(
        &self,
        system_prompt: &str,
        messages: &[ChatMessage],
        config: &Config,
    ) -> Result<ProviderResult, String>;
}

/// Get a provider by name.
pub fn get_provider(name: &str) -> Result<Box<dyn Provider>, String> {
    match name {
        "claude" => Ok(Box::new(claude::ClaudeProvider)),
        "claude-cli" => Ok(Box::new(claude_cli::ClaudeCliProvider)),
        "openai" => Ok(Box::new(openai::OpenAiProvider)),
        "ollama" => Ok(Box::new(ollama::OllamaProvider)),
        _ => Err(format!("Unknown provider: {name}")),
    }
}
