//! Copies audio files into the managed library and registers them.

use super::{paths, probe, songs, LibraryError, Result, AUDIO_EXTENSIONS};
use crate::audio::dsp;
use crate::database::connection;
use crate::models::{AudioVersion, PreviewInfo, Song};
use rusqlite::{params, Connection, OptionalExtension};
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use uuid::Uuid;

/// Which song an imported file becomes a version of.
#[derive(Clone, Copy)]
enum Target<'a> {
    /// Find or create the song named by the file's own tags.
    FromTags,
    /// Find or create the song with this user-confirmed title and artist.
    Named { title: &'a str, artist: &'a str },
    /// Attach to an existing song.
    Song(&'a str),
}

/// Imports a file, deriving title/artist/album from its tags (falling back to
/// the file name for the title).
pub fn import_song(filepath: &str) -> Result<Song> {
    let (conn, version) = import(Path::new(filepath), Target::FromTags)?;
    songs::load(&conn, &version.song_id)
}

/// Imports a file under an explicit title and artist.
pub fn import_song_with_metadata(filepath: &str, title: &str, artist: &str) -> Result<()> {
    import(Path::new(filepath), Target::Named { title, artist }).map(drop)
}

/// Imports a file as an additional audio version of `song_id`.
pub fn import_version(song_id: &str, filepath: &str) -> Result<AudioVersion> {
    import(Path::new(filepath), Target::Song(song_id)).map(|(_, version)| version)
}

fn import(source: &Path, target: Target<'_>) -> Result<(Connection, AudioVersion)> {
    if !source.is_file() {
        return Err(LibraryError::new("文件不存在。"));
    }
    let original_name = source
        .file_name()
        .ok_or_else(|| LibraryError::new("文件名无效。"))?
        .to_string_lossy()
        .into_owned();
    let extension = source
        .extension()
        .unwrap_or_default()
        .to_string_lossy()
        .into_owned();
    let file_size = source.metadata()?.len() as i64;

    let tagged = probe::open(source)?;
    let properties = probe::properties(source, &tagged);
    let tags = probe::tags(&tagged);
    let md5 = probe::file_md5(source)?;

    let mut conn = connection::open()?;
    let duplicate: bool = conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM audio_files WHERE md5 = ?1)",
        params![md5],
        |row| row.get(0),
    )?;
    if duplicate {
        return Err(LibraryError::new(format!(
            "音频文件 [{original_name}] 已存在于音乐库中，请勿重复导入！"
        )));
    }
    if let Target::Song(song_id) = target {
        if !songs::exists(&conn, song_id)? {
            return Err(songs::song_not_found());
        }
    }
    // Measured only once the file is known to be importable: it decodes audio.
    let loudness =
        dsp::calculate_loudness(&source.to_string_lossy(), dsp::LoudnessScan::Quick).ok();

    let file_name = if extension.is_empty() {
        Uuid::new_v4().to_string()
    } else {
        format!("{}.{extension}", Uuid::new_v4())
    };
    let destination = paths::files_dir().join(&file_name);
    fs::create_dir_all(paths::files_dir())?;
    fs::copy(source, &destination)?;
    let sidecar = copy_sidecar_lyrics(source, &destination);

    let file_stem = || {
        source
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned()
    };
    let mut register = || -> Result<String> {
        let tx = conn.transaction()?;
        let song_id = match target {
            Target::Song(song_id) => song_id.to_string(),
            Target::Named { title, artist } => {
                let title = match title.trim() {
                    "" => file_stem(),
                    title => title.to_string(),
                };
                find_or_create_song(
                    &tx,
                    &title,
                    songs::normalize_artist(artist).as_deref(),
                    None,
                )?
            }
            Target::FromTags => {
                let title = tags.title.clone().unwrap_or_else(file_stem);
                find_or_create_song(&tx, &title, tags.artist.as_deref(), tags.album.as_deref())?
            }
        };
        let version_id = Uuid::new_v4().to_string();
        tx.execute(
            "INSERT INTO audio_files (id, song_id, filepath, original_name, format, bitrate,
                 sample_rate, duration, file_size, is_enabled, is_primary, md5, bit_depth, loudness)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 1,
                 NOT EXISTS(SELECT 1 FROM audio_files WHERE song_id = ?2), ?10, ?11, ?12)",
            params![
                version_id,
                song_id,
                paths::audio_relative_path(&file_name),
                original_name,
                extension,
                properties.bitrate,
                properties.sample_rate,
                properties.duration,
                file_size,
                md5,
                properties.bit_depth,
                loudness,
            ],
        )?;
        tx.commit()?;
        Ok(version_id)
    };

    let version_id = match register() {
        Ok(version_id) => version_id,
        Err(error) => {
            // Never leave an unregistered copy behind in `files/`.
            let _ = fs::remove_file(&destination);
            if let Some(sidecar) = sidecar {
                let _ = fs::remove_file(sidecar);
            }
            return Err(error);
        }
    };

    let version = songs::load_version(&conn, &version_id)?;
    // Cover extraction is cosmetic; the import itself has already succeeded.
    let _ = songs::ensure_cover_with(&conn, &version.song_id);
    Ok((conn, version))
}

fn find_or_create_song(
    conn: &Connection,
    title: &str,
    artist: Option<&str>,
    album: Option<&str>,
) -> Result<String> {
    let existing: Option<String> = conn
        .query_row(
            "SELECT id FROM songs WHERE title = ?1 AND artist IS ?2 ORDER BY rowid LIMIT 1",
            params![title, artist],
            |row| row.get(0),
        )
        .optional()?;
    if let Some(id) = existing {
        return Ok(id);
    }
    let id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO songs (id, title, artist, album) VALUES (?1, ?2, ?3, ?4)",
        params![id, title, artist, album],
    )?;
    Ok(id)
}

/// Copies `<source>.lrc` next to the imported audio so it can be offered as a
/// local lyric candidate later. Returns the copy's path when one was made.
fn copy_sidecar_lyrics(source: &Path, destination: &Path) -> Option<PathBuf> {
    let source_lrc = source.with_extension("lrc");
    if !source_lrc.is_file() {
        return None;
    }
    let destination_lrc = destination.with_extension("lrc");
    fs::copy(source_lrc, &destination_lrc).ok()?;
    Some(destination_lrc)
}

/// Recursively lists importable audio files under `dir`.
pub fn scan_directory(dir: &str) -> Result<Vec<String>> {
    let root = Path::new(dir);
    if !root.is_dir() {
        return Err(LibraryError::new("所选路径不是文件夹。"));
    }
    let mut files = Vec::new();
    let mut visited = HashSet::new();
    collect_audio_files(root, &mut visited, &mut files);
    files.sort();
    Ok(files
        .into_iter()
        .map(|path| path.to_string_lossy().into_owned())
        .collect())
}

fn collect_audio_files(dir: &Path, visited: &mut HashSet<PathBuf>, files: &mut Vec<PathBuf>) {
    // Canonical paths break symlink cycles, which would otherwise recurse forever.
    let Ok(canonical) = dir.canonicalize() else {
        return;
    };
    if !visited.insert(canonical) {
        return;
    }
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_audio_files(&path, visited, files);
        } else if path.is_file() && is_audio_file(&path) {
            files.push(path);
        }
    }
}

fn is_audio_file(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| {
            AUDIO_EXTENSIONS
                .iter()
                .any(|known| ext.eq_ignore_ascii_case(known))
        })
}

/// Title/artist guesses shown to the user before a batch import.
pub fn preview_metadata(filepaths: Vec<String>) -> Vec<PreviewInfo> {
    filepaths
        .into_iter()
        .map(|filepath| {
            let path = Path::new(&filepath);
            let lossy = |name: Option<&std::ffi::OsStr>| {
                name.unwrap_or_default().to_string_lossy().into_owned()
            };
            let tags = probe::open(path)
                .map(|file| probe::tags(&file))
                .unwrap_or_default();
            PreviewInfo {
                filename: lossy(path.file_name()),
                title: tags.title.unwrap_or_else(|| lossy(path.file_stem())),
                artist: tags.artist.unwrap_or_else(|| "未知歌手".to_string()),
                filepath,
            }
        })
        .collect()
}
