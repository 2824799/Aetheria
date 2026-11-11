//! Music library domain logic: importing, querying and maintaining the
//! managed library (SQLite metadata plus the `files/` and `covers/` folders).
//!
//! `crate::api` is a thin FRB surface over this module. Everything here
//! returns [`Result`]; the API layer turns errors into strings for Dart.

mod error;
pub mod import;
pub mod lyrics;
pub mod maintenance;
pub mod paths;
pub mod playlists;
mod probe;
pub mod songs;
pub mod tags;

#[cfg(test)]
pub(crate) mod test_support;
#[cfg(test)]
mod tests;

pub use error::{LibraryError, Result};

use crate::database::{connection, schema};
use std::path::PathBuf;

/// File extensions (lowercase) the importer accepts.
pub const AUDIO_EXTENSIONS: [&str; 6] = ["mp3", "wav", "flac", "m4a", "ogg", "aac"];

pub fn is_initialized() -> bool {
    connection::database_path().is_file()
}

/// Points the library at `path`, creating the folder layout and database
/// schema when they are missing.
pub fn initialize(path: PathBuf) -> Result<()> {
    connection::set_library_dir(path);
    paths::ensure_dirs()?;
    let mut conn = connection::open()?;
    schema::migrate(&mut conn)?;
    lyrics::scrub_legacy_tags(&conn)?;
    Ok(())
}

/// Flushes committed WAL pages so `database.db` can be copied on its own.
pub fn checkpoint() -> Result<()> {
    let conn = connection::open()?;
    conn.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);")?;
    Ok(())
}
