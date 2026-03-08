use rand::Rng;
use std::future::Future;
use std::time::Duration;
use tokio::time::sleep;

/// Retry configuration.
#[derive(Debug, Clone)]
pub struct RetryConfig {
    pub max_attempts: u32,
    pub base_delay_ms: u64,
    pub exponential_base: f64,
    pub max_delay_ms: u64,
}

impl Default for RetryConfig {
    fn default() -> Self {
        Self {
            max_attempts: 3,
            base_delay_ms: 1000,
            exponential_base: 2.0,
            max_delay_ms: 30000,
        }
    }
}

/// Check if an error message indicates a retryable condition.
pub fn is_retryable(error: &str) -> bool {
    let lower = error.to_lowercase();
    lower.contains("timeout")
        || lower.contains("network")
        || lower.contains("rate limit")
        || lower.contains("429")
        || lower.contains("502")
        || lower.contains("503")
        || lower.contains("504")
}

/// Calculate delay with exponential backoff + jitter.
fn calculate_delay(attempt: u32, config: &RetryConfig) -> Duration {
    let base = config.base_delay_ms as f64 * config.exponential_base.powi(attempt as i32);
    let capped = base.min(config.max_delay_ms as f64);
    // Add jitter: 0.5x to 1.5x
    let jitter = rand::thread_rng().gen_range(0.5..1.5);
    Duration::from_millis((capped * jitter) as u64)
}

/// Execute an async function with retry logic.
pub async fn with_retry<F, Fut, T>(
    config: &RetryConfig,
    mut f: F,
) -> Result<T, String>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, String>>,
{
    let mut last_error = String::new();

    for attempt in 0..config.max_attempts {
        match f().await {
            Ok(result) => return Ok(result),
            Err(e) => {
                last_error = e;

                if !is_retryable(&last_error) || attempt + 1 >= config.max_attempts {
                    break;
                }

                let delay = calculate_delay(attempt, config);
                sleep(delay).await;
            }
        }
    }

    Err(last_error)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_retryable() {
        assert!(is_retryable("timeout occurred"));
        assert!(is_retryable("HTTP 429: rate limited"));
        assert!(is_retryable("HTTP 503: service unavailable"));
        assert!(is_retryable("network error"));
        assert!(!is_retryable("invalid API key"));
        assert!(!is_retryable("HTTP 401: unauthorized"));
    }

    #[test]
    fn test_retry_config_default() {
        let config = RetryConfig::default();
        assert_eq!(config.max_attempts, 3);
        assert_eq!(config.base_delay_ms, 1000);
    }

    #[tokio::test]
    async fn test_with_retry_success_first_try() {
        let config = RetryConfig::default();
        let result = with_retry(&config, || async { Ok::<_, String>("success".to_string()) }).await;
        assert_eq!(result.unwrap(), "success");
    }

    #[tokio::test]
    async fn test_with_retry_non_retryable_fails_immediately() {
        let config = RetryConfig { max_attempts: 3, ..Default::default() };
        let attempt_count = std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0));
        let count = attempt_count.clone();

        let result = with_retry(&config, || {
            count.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            async { Err::<String, _>("invalid API key".to_string()) }
        }).await;

        assert!(result.is_err());
        assert_eq!(attempt_count.load(std::sync::atomic::Ordering::SeqCst), 1);
    }
}
