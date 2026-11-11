use std::fmt;

/// A library failure carrying a message that is safe to show to the user.
#[derive(Debug)]
pub struct LibraryError(String);

pub type Result<T> = std::result::Result<T, LibraryError>;

impl LibraryError {
    pub fn new(message: impl Into<String>) -> Self {
        Self(message.into())
    }
}

impl fmt::Display for LibraryError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for LibraryError {}

impl From<LibraryError> for String {
    fn from(error: LibraryError) -> Self {
        error.0
    }
}

impl From<rusqlite::Error> for LibraryError {
    fn from(error: rusqlite::Error) -> Self {
        Self(error.to_string())
    }
}

impl From<std::io::Error> for LibraryError {
    fn from(error: std::io::Error) -> Self {
        Self(error.to_string())
    }
}
