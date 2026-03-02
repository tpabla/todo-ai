use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::config::Config;
use crate::logger::{LogLevel, Logger};

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

    pub fn dispatch(&mut self, request: RpcRequest) -> RpcResponse {
        match request.method.as_str() {
            "initialize" => self.handle_initialize(request),
            "shutdown" => self.handle_shutdown(request),
            "get_config" => self.handle_get_config(request),
            "set_config" => self.handle_set_config(request),
            "log" => self.handle_log(request),
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
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_initialize_with_config() {
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
        let response = handler.dispatch(request);
        let result = response.result.unwrap();
        assert_eq!(result["ok"], true);
        assert_eq!(handler.config.provider, "claude-cli");
        assert_eq!(handler.config.model, "claude-opus-4-6");
        assert_eq!(handler.config.log_level, "DEBUG");
    }

    #[test]
    fn test_get_config() {
        let mut handler = Handler::new();
        handler.config.provider = "ollama".to_string();

        let request = RpcRequest {
            jsonrpc: "2.0".to_string(),
            id: Some(Value::Number(1.into())),
            method: "get_config".to_string(),
            params: serde_json::json!({"key": "provider"}),
        };
        let response = handler.dispatch(request);
        let result = response.result.unwrap();
        assert_eq!(result["value"], "ollama");
    }

    #[test]
    fn test_set_config() {
        let mut handler = Handler::new();
        let request = RpcRequest {
            jsonrpc: "2.0".to_string(),
            id: Some(Value::Number(1.into())),
            method: "set_config".to_string(),
            params: serde_json::json!({"key": "log_level", "value": "ERROR"}),
        };
        let response = handler.dispatch(request);
        assert!(response.result.is_some());
        assert_eq!(handler.config.log_level, "ERROR");
    }

    #[test]
    fn test_unknown_method() {
        let mut handler = Handler::new();
        let request = RpcRequest {
            jsonrpc: "2.0".to_string(),
            id: Some(Value::Number(1.into())),
            method: "nonexistent".to_string(),
            params: Value::Null,
        };
        let response = handler.dispatch(request);
        assert!(response.error.is_some());
        assert_eq!(response.error.unwrap().code, -32601);
    }

    #[test]
    fn test_shutdown() {
        let mut handler = Handler::new();
        let request = RpcRequest {
            jsonrpc: "2.0".to_string(),
            id: Some(Value::Number(2.into())),
            method: "shutdown".to_string(),
            params: Value::Null,
        };
        let response = handler.dispatch(request);
        let result = response.result.unwrap();
        assert_eq!(result["ok"], true);
    }
}
