use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
use serde_json::Value;
use std::collections::HashMap;
use std::time::Duration;

/// HTTP response wrapper.
#[derive(Debug)]
pub struct HttpResponse {
    pub status: u16,
    pub body: Value,
}

/// Make an async HTTP request.
pub async fn request(
    url: &str,
    method: &str,
    headers: &HashMap<String, String>,
    body: Option<&Value>,
    timeout_ms: u64,
) -> Result<HttpResponse, String> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_millis(timeout_ms))
        .redirect(reqwest::redirect::Policy::limited(5))
        .build()
        .map_err(|e| format!("Failed to create HTTP client: {e}"))?;

    let mut header_map = HeaderMap::new();
    for (k, v) in headers {
        let name = HeaderName::from_bytes(k.as_bytes())
            .map_err(|e| format!("Invalid header name '{k}': {e}"))?;
        let value = HeaderValue::from_str(v)
            .map_err(|e| format!("Invalid header value for '{k}': {e}"))?;
        header_map.insert(name, value);
    }

    let builder = match method.to_uppercase().as_str() {
        "GET" => client.get(url),
        "POST" => client.post(url),
        "PUT" => client.put(url),
        "DELETE" => client.delete(url),
        _ => return Err(format!("Unsupported HTTP method: {method}")),
    };

    let mut builder = builder.headers(header_map);
    if let Some(b) = body {
        builder = builder.json(b);
    }

    let response = builder
        .send()
        .await
        .map_err(|e| {
            if e.is_timeout() {
                "timeout".to_string()
            } else if e.is_connect() {
                format!("network: {e}")
            } else {
                format!("HTTP request failed: {e}")
            }
        })?;

    let status = response.status().as_u16();
    let body_text = response
        .text()
        .await
        .map_err(|e| format!("Failed to read response body: {e}"))?;

    let body: Value = serde_json::from_str(&body_text).unwrap_or(Value::String(body_text));

    if status >= 200 && status < 300 {
        Ok(HttpResponse { status, body })
    } else {
        Err(format!("HTTP {status}: {body}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_invalid_url() {
        let result = request(
            "http://localhost:1/nonexistent",
            "GET",
            &HashMap::new(),
            None,
            1000,
        )
        .await;
        assert!(result.is_err());
    }
}
