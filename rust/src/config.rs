use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RetryConfig {
    pub max_attempts: u32,
    pub base_delay: u64,
    pub exponential_base: u32,
    pub max_delay: u64,
    pub jitter: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeoutConfig {
    pub llm_request: u64,
    pub health_check: u64,
    pub default: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationConfig {
    pub max_messages: usize,
    pub max_total_chars: usize,
    pub max_message_length: usize,
    pub auto_clear_on_error: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub provider: String,
    pub model: String,
    pub api_key: Option<String>,
    pub endpoint: Option<String>,
    pub temperature: f64,
    pub max_tokens: u64,
    pub cache_enabled: bool,
    pub cache_dir: String,
    pub retry: RetryConfig,
    pub timeouts: TimeoutConfig,
    pub conversation: ConversationConfig,
    pub log_level: String,

    /// Extra fields from Lua we don't parse but preserve
    #[serde(flatten)]
    pub extra: HashMap<String, Value>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            provider: "claude".to_string(),
            model: String::new(),
            api_key: None,
            endpoint: None,
            temperature: 0.7,
            max_tokens: 8192,
            cache_enabled: true,
            cache_dir: ".todoai".to_string(),
            retry: RetryConfig {
                max_attempts: 3,
                base_delay: 1000,
                exponential_base: 2,
                max_delay: 30000,
                jitter: true,
            },
            timeouts: TimeoutConfig {
                llm_request: 300000,
                health_check: 5000,
                default: 30000,
            },
            conversation: ConversationConfig {
                max_messages: 50,
                max_total_chars: 50000,
                max_message_length: 4000,
                auto_clear_on_error: false,
            },
            log_level: "INFO".to_string(),
            extra: HashMap::new(),
        }
    }
}

impl Config {
    /// Create config from Lua params, merging with defaults
    pub fn from_params(params: &Value) -> Self {
        // Start with defaults as JSON, then overlay params on top
        let mut base = serde_json::to_value(Config::default()).unwrap();

        if let (Some(base_obj), Some(params_obj)) = (base.as_object_mut(), params.as_object()) {
            for (k, v) in params_obj {
                if !v.is_null() {
                    base_obj.insert(k.clone(), v.clone());
                }
            }
        }

        let mut config: Config = serde_json::from_value(base).unwrap_or_default();

        // Read API keys from environment if not provided
        if config.api_key.is_none() {
            config.api_key = match config.provider.as_str() {
                "claude" => std::env::var("ANTHROPIC_API_KEY").ok(),
                "openai" => std::env::var("OPENAI_API_KEY").ok(),
                _ => None,
            };
        }

        config
    }

    /// Load project-specific config from .todoai/config.json and merge
    pub fn load_project_config(&mut self, project_root: &str) {
        let path = Path::new(project_root).join(&self.cache_dir).join("config.json");
        if let Ok(content) = fs::read_to_string(&path) {
            if let Ok(project_config) = serde_json::from_str::<Value>(&content) {
                if let Some(obj) = project_config.as_object() {
                    // Merge project config over current config
                    let mut current = serde_json::to_value(&*self).unwrap_or(Value::Null);
                    if let Some(current_obj) = current.as_object_mut() {
                        for (k, v) in obj {
                            current_obj.insert(k.clone(), v.clone());
                        }
                        if let Ok(merged) = serde_json::from_value::<Config>(Value::Object(current_obj.clone())) {
                            *self = merged;
                        }
                    }
                }
            }
        }
    }

    pub fn get(&self, key: &str) -> Option<Value> {
        let as_value = serde_json::to_value(self).ok()?;
        as_value.get(key).cloned()
    }

    pub fn set(&mut self, key: &str, value: Value) {
        let mut as_value = serde_json::to_value(&*self).unwrap_or(Value::Null);
        if let Some(obj) = as_value.as_object_mut() {
            obj.insert(key.to_string(), value);
            if let Ok(updated) = serde_json::from_value::<Config>(Value::Object(obj.clone())) {
                *self = updated;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert_eq!(config.provider, "claude");
        assert_eq!(config.temperature, 0.7);
        assert_eq!(config.max_tokens, 8192);
        assert_eq!(config.retry.max_attempts, 3);
        assert_eq!(config.timeouts.llm_request, 300000);
    }

    #[test]
    fn test_from_params() {
        let params = serde_json::json!({
            "provider": "claude-cli",
            "model": "claude-opus-4-6",
            "log_level": "DEBUG",
            "temperature": 0.5
        });
        let config = Config::from_params(&params);
        assert_eq!(config.provider, "claude-cli");
        assert_eq!(config.model, "claude-opus-4-6");
        assert_eq!(config.log_level, "DEBUG");
        assert_eq!(config.temperature, 0.5);
        // Defaults preserved
        assert_eq!(config.max_tokens, 8192);
        assert_eq!(config.retry.max_attempts, 3);
    }

    #[test]
    fn test_get_set() {
        let mut config = Config::default();
        config.set("log_level", Value::String("ERROR".to_string()));
        assert_eq!(config.log_level, "ERROR");
        assert_eq!(config.get("log_level"), Some(Value::String("ERROR".to_string())));
    }

    #[test]
    fn test_extra_fields_preserved() {
        let params = serde_json::json!({
            "provider": "claude-cli",
            "model": "opus",
            "chat_window_width": 60,
            "highlight_todos": true
        });
        let config = Config::from_params(&params);
        assert_eq!(config.extra.get("chat_window_width"), Some(&serde_json::json!(60)));
        assert_eq!(config.extra.get("highlight_todos"), Some(&serde_json::json!(true)));
    }
}
