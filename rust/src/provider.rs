use crate::prompt;
use serde_json::Value;

/// Send a request to an LLM provider and return the raw response text
pub fn send_request(
    provider: &str,
    instruction: &str,
    context: &Value,
    model: Option<&str>,
    temperature: Option<f64>,
    max_tokens: Option<u32>,
    api_key: Option<&str>,
    messages: Option<&[crate::protocol::ChatMessage]>,
) -> Result<String, String> {
    match provider {
        "claude" => send_claude(instruction, context, model, temperature, max_tokens, api_key, messages),
        "openai" => send_openai(instruction, context, model, temperature, max_tokens, api_key, messages),
        "ollama" => send_ollama(instruction, context, model, temperature, max_tokens, messages),
        _ => Err(format!("Unknown provider: {}", provider)),
    }
}

fn send_claude(
    instruction: &str,
    context: &Value,
    model: Option<&str>,
    temperature: Option<f64>,
    max_tokens: Option<u32>,
    api_key: Option<&str>,
    messages: Option<&[crate::protocol::ChatMessage]>,
) -> Result<String, String> {
    let api_key = api_key.ok_or("ANTHROPIC_API_KEY not set")?;
    let model = model.unwrap_or("claude-3-5-sonnet-20241022");
    let temperature = temperature.unwrap_or(0.7);
    let max_tokens = max_tokens.unwrap_or(4096);

    let system_prompt = prompt::get_schema_description();

    let claude_messages = if let Some(msgs) = messages {
        // Convert chat messages to Claude format
        msgs.iter()
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
                serde_json::json!({ "role": role, "content": content })
            })
            .collect::<Vec<_>>()
    } else {
        let user_prompt = prompt::build_user_prompt(instruction, context);
        vec![serde_json::json!({ "role": "user", "content": user_prompt })]
    };

    let body = serde_json::json!({
        "model": model,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "system": system_prompt,
        "messages": claude_messages,
    });

    let mut response = ureq::post("https://api.anthropic.com/v1/messages")
        .header("content-type", "application/json")
        .header("x-api-key", api_key)
        .header("anthropic-version", "2023-06-01")
        .send_json(&body)
        .map_err(|e| format!("Claude API request failed: {}", e))?;

    let data: Value = response
        .body_mut()
        .read_json()
        .map_err(|e| format!("Failed to parse Claude response: {}", e))?;

    // Check for API errors
    if let Some(error) = data.get("error") {
        let msg = error
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Unknown error");
        return Err(format!("Claude API error: {}", msg));
    }

    // Extract content
    data.get("content")
        .and_then(|c| c.as_array())
        .and_then(|arr| arr.first())
        .and_then(|item| item.get("text"))
        .and_then(|t| t.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| "No content in Claude response".to_string())
}

fn send_openai(
    instruction: &str,
    context: &Value,
    model: Option<&str>,
    temperature: Option<f64>,
    max_tokens: Option<u32>,
    api_key: Option<&str>,
    messages: Option<&[crate::protocol::ChatMessage]>,
) -> Result<String, String> {
    let api_key = api_key.ok_or("OPENAI_API_KEY not set")?;
    let model = model.unwrap_or("gpt-4");
    let temperature = temperature.unwrap_or(0.7);
    let max_tokens = max_tokens.unwrap_or(4096);

    let system_prompt = prompt::get_schema_description();

    let mut openai_messages = vec![serde_json::json!({
        "role": "system",
        "content": system_prompt,
    })];

    if let Some(msgs) = messages {
        for msg in msgs {
            let role = match msg.role.as_str() {
                "ai" => "assistant",
                other => other,
            };
            openai_messages.push(serde_json::json!({
                "role": role,
                "content": msg.content,
            }));
        }
    } else {
        let user_prompt = prompt::build_user_prompt(instruction, context);
        openai_messages.push(serde_json::json!({
            "role": "user",
            "content": user_prompt,
        }));
    }

    let body = serde_json::json!({
        "model": model,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "messages": openai_messages,
    });

    let mut response = ureq::post("https://api.openai.com/v1/chat/completions")
        .header("content-type", "application/json")
        .header("Authorization", &format!("Bearer {}", api_key))
        .send_json(&body)
        .map_err(|e| format!("OpenAI API request failed: {}", e))?;

    let data: Value = response
        .body_mut()
        .read_json()
        .map_err(|e| format!("Failed to parse OpenAI response: {}", e))?;

    // Check for API errors
    if let Some(error) = data.get("error") {
        let msg = error
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Unknown error");
        return Err(format!("OpenAI API error: {}", msg));
    }

    // Extract content
    data.get("choices")
        .and_then(|c| c.as_array())
        .and_then(|arr| arr.first())
        .and_then(|choice| choice.get("message"))
        .and_then(|msg| msg.get("content"))
        .and_then(|c| c.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| "No content in OpenAI response".to_string())
}

fn send_ollama(
    instruction: &str,
    context: &Value,
    model: Option<&str>,
    temperature: Option<f64>,
    _max_tokens: Option<u32>,
    messages: Option<&[crate::protocol::ChatMessage]>,
) -> Result<String, String> {
    let model = model.unwrap_or("llama3");
    let temperature = temperature.unwrap_or(0.7);

    let system_prompt = prompt::get_schema_description();

    let mut ollama_messages = vec![serde_json::json!({
        "role": "system",
        "content": system_prompt,
    })];

    if let Some(msgs) = messages {
        for msg in msgs {
            let role = match msg.role.as_str() {
                "ai" => "assistant",
                other => other,
            };
            ollama_messages.push(serde_json::json!({
                "role": role,
                "content": msg.content,
            }));
        }
    } else {
        let user_prompt = prompt::build_user_prompt(instruction, context);
        ollama_messages.push(serde_json::json!({
            "role": "user",
            "content": user_prompt,
        }));
    }

    let body = serde_json::json!({
        "model": model,
        "messages": ollama_messages,
        "stream": false,
        "options": {
            "temperature": temperature,
        },
    });

    let mut response = ureq::post("http://localhost:11434/api/chat")
        .header("content-type", "application/json")
        .send_json(&body)
        .map_err(|e| format!("Ollama API request failed: {}", e))?;

    let data: Value = response
        .body_mut()
        .read_json()
        .map_err(|e| format!("Failed to parse Ollama response: {}", e))?;

    data.get("message")
        .and_then(|msg| msg.get("content"))
        .and_then(|c| c.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| "No content in Ollama response".to_string())
}
