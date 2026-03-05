use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::config::Config;
use crate::logger::{LogLevel, Logger};
use crate::parser;
use crate::prompt::{self, PromptContext};
use crate::providers::{self, ChatMessage};
use crate::schema;

#[derive(Debug, Deserialize)]
pub struct RpcRequest {
    #[allow(dead_code)]
    pub jsonrpc: String,
    pub id: Option<Value>,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

#[derive(Debug, Serialize)]
pub struct RpcResponse {
    pub jsonrpc: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<RpcError>,
}

#[derive(Debug, Serialize)]
pub struct RpcError {
    pub code: i64,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

#[derive(Debug, Serialize)]
#[allow(dead_code)]
pub struct RpcNotification {
    pub jsonrpc: String,
    pub method: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<Value>,
}

impl RpcResponse {
    pub fn success(id: Option<Value>, result: Value) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            id,
            result: Some(result),
            error: None,
        }
    }

    pub fn error(id: Option<Value>, code: i64, message: String) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            id,
            result: None,
            error: Some(RpcError {
                code,
                message,
                data: None,
            }),
        }
    }
}

pub struct Handler {
    pub config: Config,
    pub logger: Logger,
}

impl Handler {
    pub fn new() -> Self {
        Self {
            config: Config::default(),
            logger: Logger::new(LogLevel::Info),
        }
    }

    pub async fn dispatch(&mut self, request: RpcRequest) -> RpcResponse {
        match request.method.as_str() {
            "initialize" => self.handle_initialize(request),
            "shutdown" => self.handle_shutdown(request),
            "get_config" => self.handle_get_config(request),
            "set_config" => self.handle_set_config(request),
            "log" => self.handle_log(request),
            "complete" => self.handle_complete(request).await,
            _ => RpcResponse::error(
                request.id,
                -32601,
                format!("Method not found: {}", request.method),
            ),
        }
    }

    fn handle_initialize(&mut self, request: RpcRequest) -> RpcResponse {
        // Parse config from params
        let config_value = if let Some(obj) = request.params.as_object() {
            obj.get("config").cloned().unwrap_or(request.params.clone())
        } else {
            request.params.clone()
        };

        self.config = Config::from_params(&config_value);
        self.logger.set_level(LogLevel::from_str(&self.config.log_level));

        self.logger.info("backend", &format!(
            "Initialized: provider={}, model={}, log_level={}",
            self.config.provider, self.config.model, self.config.log_level
        ));

        RpcResponse::success(
            request.id,
            serde_json::json!({
                "ok": true,
                "version": "0.1.0"
            }),
        )
    }

    fn handle_shutdown(&self, request: RpcRequest) -> RpcResponse {
        self.logger.info("backend", "Shutting down");
        RpcResponse::success(request.id, serde_json::json!({"ok": true}))
    }

    fn handle_get_config(&self, request: RpcRequest) -> RpcResponse {
        let key = request.params.get("key").and_then(|v| v.as_str());

        match key {
            Some(k) => {
                let value = self.config.get(k).unwrap_or(Value::Null);
                RpcResponse::success(request.id, serde_json::json!({"value": value}))
            }
            None => {
                // Return full config
                let value = serde_json::to_value(&self.config).unwrap_or(Value::Null);
                RpcResponse::success(request.id, value)
            }
        }
    }

    fn handle_set_config(&mut self, request: RpcRequest) -> RpcResponse {
        let key = request.params.get("key").and_then(|v| v.as_str());
        let value = request.params.get("value");

        match (key, value) {
            (Some(k), Some(v)) => {
                self.config.set(k, v.clone());

                // Update logger level if log_level changed
                if k == "log_level" {
                    if let Some(level_str) = v.as_str() {
                        self.logger.set_level(LogLevel::from_str(level_str));
                    }
                }

                self.logger.debug("backend", &format!("Config set: {k} = {v}"));
                RpcResponse::success(request.id, serde_json::json!({"ok": true}))
            }
            _ => RpcResponse::error(
                request.id,
                -32602,
                "set_config requires 'key' and 'value' params".to_string(),
            ),
        }
    }

    fn handle_log(&self, request: RpcRequest) -> RpcResponse {
        let level = request.params.get("level").and_then(|v| v.as_str()).unwrap_or("INFO");
        let context = request.params.get("context").and_then(|v| v.as_str()).unwrap_or("unknown");
        let data = request.params.get("data").and_then(|v| v.as_str()).unwrap_or("");

        self.logger.handle_log_notification(level, context, data);

        // Log is a notification, but return success if it has an id
        RpcResponse::success(request.id, serde_json::json!({"ok": true}))
    }

    /// Handle the `complete` RPC: build prompt → call provider → parse → validate → return.
    async fn handle_complete(&self, request: RpcRequest) -> RpcResponse {
        self.logger.info("complete", "=== COMPLETE REQUEST START ===");

        // Parse context from params
        let context: PromptContext = match serde_json::from_value(request.params.clone()) {
            Ok(ctx) => ctx,
            Err(e) => {
                self.logger.error("complete", &format!("Failed to parse context: {e}"));
                return RpcResponse::error(request.id, -32602, format!("Invalid context: {e}"));
            }
        };

        // Build prompts
        let system_prompt = prompt::get_system_prompt();
        let user_prompt = prompt::build_user_prompt(&context);

        self.logger.info("complete", &format!(
            "System prompt: {} chars, User prompt: {} chars",
            system_prompt.len(), user_prompt.len()
        ));

        // Get provider
        let provider = match providers::get_provider(&self.config.provider) {
            Ok(p) => p,
            Err(e) => {
                self.logger.error("complete", &format!("Provider error: {e}"));
                return RpcResponse::error(request.id, -32603, e);
            }
        };

        // Determine if this is a chat request with history
        let conversation_history: Option<Vec<ChatMessage>> = request.params
            .get("conversation_history")
            .and_then(|v| serde_json::from_value(v.clone()).ok());

        // Call provider
        let provider_result = if let Some(messages) = conversation_history {
            // Chat mode with history — append current user prompt
            let mut all_messages = messages;
            all_messages.push(ChatMessage {
                role: "user".to_string(),
                content: user_prompt.clone(),
            });
            provider.chat(&system_prompt, &all_messages, &self.config).await
        } else {
            // Single completion
            provider.complete(&system_prompt, &user_prompt, &self.config).await
        };

        let provider_result = match provider_result {
            Ok(r) => r,
            Err(e) => {
                self.logger.error("complete", &format!("Provider call failed: {e}"));
                return RpcResponse::error(request.id, -32603, e);
            }
        };

        self.logger.info("complete", &format!(
            "Provider returned {} chars (hint: {})",
            provider_result.content.len(), provider_result.provider_hint
        ));

        // Parse the response
        let parsed = parser::parse(&provider_result.content, Some(&provider_result.provider_hint));

        // Check for parse errors
        if let Some(ref parse_error) = parsed.parse_error {
            self.logger.error("complete", &format!("Parse error: {parse_error}"));
            return RpcResponse::error(request.id, -32603, format!("Parse error: {parse_error}"));
        }

        // Build result JSON from parsed fields
        let mut result = serde_json::Map::new();

        if let Some(ref mode) = parsed.mode {
            result.insert("mode".to_string(), Value::String(mode.clone()));
        }
        if let Some(ref filename) = parsed.filename {
            result.insert("filename".to_string(), Value::String(filename.clone()));
        }
        if let Some(ref changes) = parsed.changes {
            result.insert("changes".to_string(), changes.clone());
        }
        if let Some(ref language) = parsed.language {
            result.insert("language".to_string(), Value::String(language.clone()));
        }
        if let Some(ref explanation) = parsed.explanation {
            result.insert("explanation".to_string(), Value::String(explanation.clone()));
        }
        if let Some(ref code) = parsed.code {
            result.insert("code".to_string(), Value::String(code.clone()));
        }
        if let Some(ref warning) = parsed.warning {
            result.insert("warning".to_string(), Value::String(warning.clone()));
        }
        if let Some(ref thinking) = parsed.thinking_formatted {
            result.insert("thinking_formatted".to_string(), Value::String(thinking.clone()));
        }
        result.insert("format_detected".to_string(), Value::String(parsed.format_detected.clone()));

        let result_value = Value::Object(result);

        // Validate if it has mode field (skip validation for raw code responses)
        if parsed.mode.is_some() {
            if let Err(errors) = schema::validate_response(&result_value) {
                let error_msg = schema::format_validation_errors(&errors);
                self.logger.error("complete", &format!("Schema validation failed: {error_msg}"));
                // Return the result anyway but with validation errors attached
                let mut result_map = result_value.as_object().unwrap().clone();
                result_map.insert("validation_errors".to_string(),
                    Value::Array(errors.into_iter().map(Value::String).collect()));
                return RpcResponse::success(request.id, Value::Object(result_map));
            }
        }

        self.logger.info("complete", "=== COMPLETE REQUEST END ===");
        RpcResponse::success(request.id, result_value)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_initialize_with_config() {
        let mut handler = Handler::new();
        let request = RpcRequest {
            jsonrpc: "2.0".to_string(),
            id: Some(Value::Number(1.into())),
            method: "initialize".to_string(),
            params: serde_json::json!({
                "config": {
                    "provider": "claude-cli",
                    "model": "claude-opus-4-6",
                    "log_level": "DEBUG"
                }
            }),
        };
        let response = handler.dispatch(request).await;
        let result = response.result.unwrap();
        assert_eq!(result["ok"], true);
        assert_eq!(handler.config.provider, "claude-cli");
        assert_eq!(handler.config.model, "claude-opus-4-6");
        assert_eq!(handler.config.log_level, "DEBUG");
    }

    #[tokio::test]
    async fn test_get_config() {
        let mut handler = Handler::new();
        handler.config.provider = "ollama".to_string();

        let request = RpcRequest {
            jsonrpc: "2.0".to_string(),
            id: Some(Value::Number(1.into())),
            method: "get_config".to_string(),
            params: serde_json::json!({"key": "provider"}),
        };
        let response = handler.dispatch(request).await;
        let result = response.result.unwrap();
        assert_eq!(result["value"], "ollama");
    }

    #[tokio::test]
    async fn test_set_config() {
        let mut handler = Handler::new();
        let request = RpcRequest {
            jsonrpc: "2.0".to_string(),
            id: Some(Value::Number(1.into())),
            method: "set_config".to_string(),
            params: serde_json::json!({"key": "log_level", "value": "ERROR"}),
        };
        let response = handler.dispatch(request).await;
        assert!(response.result.is_some());
        assert_eq!(handler.config.log_level, "ERROR");
    }

    #[tokio::test]
    async fn test_unknown_method() {
        let mut handler = Handler::new();
        let request = RpcRequest {
            jsonrpc: "2.0".to_string(),
            id: Some(Value::Number(1.into())),
            method: "nonexistent".to_string(),
            params: Value::Null,
        };
        let response = handler.dispatch(request).await;
        assert!(response.error.is_some());
        assert_eq!(response.error.unwrap().code, -32601);
    }

    #[tokio::test]
    async fn test_shutdown() {
        let mut handler = Handler::new();
        let request = RpcRequest {
            jsonrpc: "2.0".to_string(),
            id: Some(Value::Number(2.into())),
            method: "shutdown".to_string(),
            params: Value::Null,
        };
        let response = handler.dispatch(request).await;
        let result = response.result.unwrap();
        assert_eq!(result["ok"], true);
    }

    #[tokio::test]
    async fn test_complete_invalid_context() {
        let mut handler = Handler::new();
        handler.config.provider = "claude".to_string();

        let request = RpcRequest {
            jsonrpc: "2.0".to_string(),
            id: Some(Value::Number(3.into())),
            method: "complete".to_string(),
            params: Value::String("not an object".to_string()),
        };
        let response = handler.dispatch(request).await;
        assert!(response.error.is_some());
        assert!(response.error.unwrap().message.contains("Invalid context"));
    }
}
