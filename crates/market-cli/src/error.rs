use crate::model::ValidationError;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorKind {
    User,
    Runtime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppError {
    pub kind: ErrorKind,
    pub message: String,
}

impl AppError {
    pub fn user(message: impl Into<String>) -> Self {
        Self {
            kind: ErrorKind::User,
            message: message.into(),
        }
    }

    pub fn runtime(message: impl Into<String>) -> Self {
        Self {
            kind: ErrorKind::Runtime,
            message: message.into(),
        }
    }

    pub fn runtime_with_trace(prefix: &str, trace: &[String]) -> Self {
        if trace.is_empty() {
            return Self::runtime(prefix);
        }

        let mut message = String::from(prefix);
        message.push_str(" (provider trace: ");
        message.push_str(&trace.join(" | "));
        message.push(')');
        Self::runtime(message)
    }

    pub fn exit_code(&self) -> i32 {
        match self.kind {
            ErrorKind::User => 2,
            ErrorKind::Runtime => 1,
        }
    }
}

impl From<ValidationError> for AppError {
    fn from(value: ValidationError) -> Self {
        Self::user(value.to_string())
    }
}
