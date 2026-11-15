//! Folder layout of the managed library.
//!
//! ```text
//! <library>/database.db
//! <library>/files/<uuid>.<ext>     managed audio (+ optional <uuid>.lrc)
//! <library>/covers/<song-id>.<ext> extracted cover art
//! ```

use std::path::PathBuf;

pub use crate::database::connection::library_dir;

const FILES_DIR: &str = "files";
const COVERS_DIR: &str = "covers";
const PHIGROS_DIR: &str = "phigros";
const PHIGROS_SE_SUBDIR: &str = "se";
const PHIGROS_CHARTS_SUBDIR: &str = "charts";

pub fn files_dir() -> PathBuf {
    library_dir().join(FILES_DIR)
}

pub fn covers_dir() -> PathBuf {
    library_dir().join(COVERS_DIR)
}

pub fn phigros_dir() -> PathBuf {
    library_dir().join(PHIGROS_DIR)
}

pub fn phigros_se_dir() -> PathBuf {
    phigros_dir().join(PHIGROS_SE_SUBDIR)
}

pub fn phigros_charts_dir() -> PathBuf {
    phigros_dir().join(PHIGROS_CHARTS_SUBDIR)
}

pub fn ensure_dirs() -> std::io::Result<()> {
    std::fs::create_dir_all(files_dir())?;
    std::fs::create_dir_all(covers_dir())?;
    std::fs::create_dir_all(phigros_se_dir())?;
    std::fs::create_dir_all(phigros_charts_dir())
}

/// Database value for a managed audio file, e.g. `files/<uuid>.flac`.
pub fn audio_relative_path(file_name: &str) -> String {
    format!("{FILES_DIR}/{file_name}")
}

/// Database value for an extracted cover, e.g. `covers/<song-id>.jpg`.
pub fn cover_relative_path(file_name: &str) -> String {
    format!("{COVERS_DIR}/{file_name}")
}

/// Database value for a Phigros chart timeline, e.g. `phigros/charts/<id>_IN.json`.
pub fn phigros_chart_relative_path(file_name: &str) -> String {
    format!("{PHIGROS_DIR}/{PHIGROS_CHARTS_SUBDIR}/{file_name}")
}

/// Absolute location of a stored `audio_files.filepath`.
///
/// The database can arrive from another device through LAN sync, so stored
/// paths are untrusted: only the final component is honoured, which keeps
/// every read, export and delete inside `files/`.
pub fn audio_file(stored: &str) -> Option<PathBuf> {
    file_name(stored).map(|name| files_dir().join(name))
}

/// Absolute location of a stored `songs.cover_path`; see [`audio_file`].
pub fn cover_file(stored: &str) -> Option<PathBuf> {
    file_name(stored).map(|name| covers_dir().join(name))
}

/// Absolute location of a stored `phigros_charts.chart_rel_path`.
pub fn phigros_chart_file(stored: &str) -> Option<PathBuf> {
    file_name(stored).map(|name| phigros_charts_dir().join(name))
}

pub(super) fn file_name(stored: &str) -> Option<&str> {
    let name = stored.rsplit(['/', '\\']).next()?;
    // A drive-relative path such as C:track.wav replaces the base when joined
    // on Windows. Colons can also address NTFS alternate data streams.
    (!name.is_empty() && name != "." && name != ".." && !name.contains([':', '\0'])).then_some(name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stored_paths_cannot_escape_the_library() {
        assert_eq!(file_name("files/a.mp3"), Some("a.mp3"));
        assert_eq!(file_name("a.mp3"), Some("a.mp3"));
        assert_eq!(file_name("files\\a.mp3"), Some("a.mp3"));
        assert_eq!(file_name("../../etc/passwd"), Some("passwd"));
        assert_eq!(file_name("files/.."), None);
        assert_eq!(file_name("files/"), None);
        assert_eq!(file_name(""), None);
        assert_eq!(file_name("C:outside.wav"), None);
        assert_eq!(file_name("files/C:outside.wav"), None);
        assert_eq!(file_name("files/track.wav:stream"), None);
        assert_eq!(file_name("files/bad\0.wav"), None);
        assert!(audio_file("/etc/passwd").unwrap().starts_with(files_dir()));
        assert!(cover_file("../x.jpg").unwrap().starts_with(covers_dir()));
    }
}
