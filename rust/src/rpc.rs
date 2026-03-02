use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Deserialize)]
pub struct RpcRequest {
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

pub struct Handler;

impl Handler {
    pub fn new() -> Self {
        Self
    }

    pub fn dispatch(&self, request: RpcRequest) -> RpcResponse {
        match request.method.as_str() {
            "initialize" => self.handle_initialize(request),
            "shutdown" => self.handle_shutdown(request),
            _ => RpcResponse::error(
                request.id,
                -32601,
                format!("Method not found: {}", request.method),
            ),
        }
    }

    fn handle_initialize(&self, request: RpcRequest) -> RpcResponse {
        RpcResponse::success(
            request.id,
            serde_json::json!({
                "ok": true,
                "version": "0.1.0"
            }),
        )
    }

    fn handle_shutdown(&self, request: RpcRequest) -> RpcResponse {
        RpcResponse::success(request.id, serde_json::json!({"ok": true}))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_initialize() {
        let handler = Handler::new();
        let request = RpcRequest {
            jsonrpc: "2.0".to_string(),
            id: Some(Value::Number(1.into())),
            method: "initialize".to_string(),
            params: Value::Null,
        };
        let response = handler.dispatch(request);
        let result = response.result.unwrap();
        assert_eq!(result["ok"], true);
        assert_eq!(result["version"], "0.1.0");
    }

    #[test]
    fn test_unknown_method() {
        let handler = Handler::new();
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
        let handler = Handler::new();
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
