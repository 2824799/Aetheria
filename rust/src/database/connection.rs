use rusqlite::{Connection, Result};
use std::path::PathBuf;
use std::sync::RwLock;
use std::time::Duration;

static LIBRARY_DIR: RwLock<Option<PathBuf>> = RwLock::new(None);

pub fn set_library_dir(path: PathBuf) {
    *LIBRARY_DIR.write().unwrap_or_else(|e| e.into_inner()) = Some(path);
}

/// Root of the managed library. Falls back to a temp directory until the app
/// has called `initialize_library_path`.
pub fn library_dir() -> PathBuf {
    LIBRARY_DIR
        .read()
        .unwrap_or_else(|e| e.into_inner())
        .clone()
        .unwrap_or_else(|| std::env::temp_dir().join("aetheria_library"))
}

pub fn database_path() -> PathBuf {
    library_dir().join("database.db")
}

/// Opens a connection to the library database.
///
/// Connections are short-lived on purpose: LAN sync replaces `database.db` on
/// disk, so nothing may keep the file open between calls.
pub fn open() -> Result<Connection> {
    let conn = Connection::open(database_path())?;
    conn.busy_timeout(Duration::from_secs(8))?;
    conn.execute_batch(
        "PRAGMA foreign_keys = ON;
         PRAGMA journal_mode = WAL;
         PRAGMA synchronous = NORMAL;",
    )?;
    Ok(conn)
}
