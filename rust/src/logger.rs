use std::fs::OpenOptions;
use std::io::Write;

const LOG_FILE: &str = "/tmp/todo-ai.log";

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum LogLevel {
    Debug = 1,
    Info = 2,
    Warn = 3,
    Error = 4,
}

impl LogLevel {
    pub fn from_str(s: &str) -> Self {
        match s.to_uppercase().as_str() {
            "DEBUG" => Self::Debug,
            "INFO" => Self::Info,
            "WARN" => Self::Warn,
            "ERROR" => Self::Error,
            _ => Self::Info,
        }
    }

    fn label(&self) -> &'static str {
        match self {
            Self::Debug => "DEBUG",
            Self::Info => "INFO",
            Self::Warn => "WARN",
            Self::Error => "ERROR",
        }
    }
}

pub struct Logger {
    level: LogLevel,
}

impl Logger {
    pub fn new(level: LogLevel) -> Self {
        Self { level }
    }

    pub fn set_level(&mut self, level: LogLevel) {
        self.level = level;
    }

    fn write(&self, level: LogLevel, context: &str, message: &str) {
        if level < self.level {
            return;
        }

        let now = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");
        let entry = format!("{now} [{level}] {context}: {message}\n", level = level.label());

        if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(LOG_FILE) {
            let _ = file.write_all(entry.as_bytes());
        }
    }

    pub fn debug(&self, context: &str, message: &str) {
        self.write(LogLevel::Debug, context, message);
    }

    pub fn info(&self, context: &str, message: &str) {
        self.write(LogLevel::Info, context, message);
    }

    pub fn warn(&self, context: &str, message: &str) {
        self.write(LogLevel::Warn, context, message);
    }

    pub fn error(&self, context: &str, message: &str) {
        self.write(LogLevel::Error, context, message);
    }

    /// Handle a log notification from Lua (forwarded via RPC)
    pub fn handle_log_notification(&self, level: &str, context: &str, data: &str) {
        let log_level = LogLevel::from_str(level);
        self.write(log_level, &format!("lua/{context}"), data);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_log_level_from_str() {
        assert_eq!(LogLevel::from_str("DEBUG"), LogLevel::Debug);
        assert_eq!(LogLevel::from_str("info"), LogLevel::Info);
        assert_eq!(LogLevel::from_str("WARN"), LogLevel::Warn);
        assert_eq!(LogLevel::from_str("error"), LogLevel::Error);
        assert_eq!(LogLevel::from_str("garbage"), LogLevel::Info);
    }

    #[test]
    fn test_level_ordering() {
        assert!(LogLevel::Debug < LogLevel::Info);
        assert!(LogLevel::Info < LogLevel::Warn);
        assert!(LogLevel::Warn < LogLevel::Error);
    }
}
