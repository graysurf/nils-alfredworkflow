use crate::{convert::ConvertError, parser::ParseError};

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

    pub fn exit_code(&self) -> i32 {
        match self.kind {
            ErrorKind::User => 2,
            ErrorKind::Runtime => 1,
        }
    }
}

impl From<ParseError> for AppError {
    fn from(error: ParseError) -> Self {
        Self::user(error.to_string())
    }
}

impl From<ConvertError> for AppError {
    fn from(error: ConvertError) -> Self {
        Self::user(error.to_string())
    }
}
