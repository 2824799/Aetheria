//! Music library API exposed to Dart.
//!
//! Thin wrappers over [`crate::library`]; errors cross the bridge as
//! user-presentable strings.

use crate::library::{self, import, lyrics, maintenance, paths, playlists, songs, tags};
use crate::models::{
    AudioVersion, LocalLyricCandidate, Playlist, PreviewInfo, SavedLyric, Song, Tag,
};
use flutter_rust_bridge::frb;
use std::path::PathBuf;

// ---- Library ----

#[frb(sync)]
pub fn is_library_initialized() -> bool {
    library::is_initialized()
}

pub fn initialize_library_path(path: String) -> Result<(), String> {
    Ok(library::initialize(PathBuf::from(path))?)
}

pub fn get_library_path() -> String {
    paths::library_dir().to_string_lossy().into_owned()
}

/// Flushes the WAL so sync can transfer `database.db` by itself.
pub fn checkpoint_library_database() -> Result<(), String> {
    Ok(library::checkpoint()?)
}

pub fn reset_library() -> Result<(), String> {
    Ok(maintenance::reset()?)
}

// ---- Songs and audio versions ----

pub fn get_songs() -> Result<Vec<Song>, String> {
    Ok(songs::all()?)
}

pub fn update_song_metadata(song_id: String, title: String, artist: String) -> Result<(), String> {
    Ok(songs::update_metadata(&song_id, &title, &artist)?)
}

pub fn delete_song(song_id: String) -> Result<(), String> {
    Ok(songs::delete(&song_id)?)
}

pub fn delete_audio_version(version_id: String) -> Result<(), String> {
    Ok(songs::delete_version(&version_id)?)
}

pub fn set_primary_version(version_id: String) -> Result<(), String> {
    Ok(songs::set_primary_version(&version_id)?)
}

pub fn ensure_song_cover(song_id: String) -> Result<Option<String>, String> {
    Ok(songs::ensure_cover(&song_id)?)
}

pub fn refresh_audio_file_metadata(version_id: String) -> Result<(), String> {
    Ok(maintenance::refresh_metadata(&version_id)?)
}

/// Copies a version's audio file to `dest_path` (a directory or a file path)
/// and returns the path written.
pub fn export_audio_file(version_id: String, dest_path: String) -> Result<String, String> {
    Ok(maintenance::export_version(&version_id, &dest_path)?)
}

// ---- Import ----

pub fn import_song(filepath: String) -> Result<Song, String> {
    Ok(import::import_song(&filepath)?)
}

pub fn import_song_with_metadata(
    filepath: String,
    title: String,
    artist: String,
) -> Result<(), String> {
    Ok(import::import_song_with_metadata(
        &filepath, &title, &artist,
    )?)
}

pub fn import_audio_version_for_song(
    song_id: String,
    filepath: String,
) -> Result<AudioVersion, String> {
    Ok(import::import_version(&song_id, &filepath)?)
}

pub fn scan_directory_for_preview(dir_path: String) -> Result<Vec<String>, String> {
    Ok(import::scan_directory(&dir_path)?)
}

pub fn preview_audio_metadata(filepaths: Vec<String>) -> Vec<PreviewInfo> {
    import::preview_metadata(filepaths)
}

// ---- Lyrics ----

pub fn get_selected_lyric(
    song_id: String,
    audio_version_id: Option<String>,
) -> Result<Option<SavedLyric>, String> {
    Ok(lyrics::selected(&song_id, audio_version_id.as_deref())?)
}

pub fn get_song_ids_with_lyrics() -> Result<Vec<String>, String> {
    Ok(lyrics::song_ids_with_lyrics()?)
}

pub fn get_local_lyric_candidates(
    song_id: String,
    audio_version_id: Option<String>,
) -> Result<Vec<LocalLyricCandidate>, String> {
    Ok(lyrics::local_candidates(
        &song_id,
        audio_version_id.as_deref(),
    )?)
}

/// Saves a lyric for the song (or one of its audio versions), replacing the
/// lyric previously saved for that scope.
pub fn save_lyric(
    song_id: String,
    audio_version_id: Option<String>,
    source: String,
    source_id: Option<String>,
    title: String,
    artist: Option<String>,
    content: String,
    translation: Option<String>,
    romanized: Option<String>,
    offset_ms: i32,
) -> Result<SavedLyric, String> {
    Ok(lyrics::save(lyrics::NewLyric {
        song_id,
        audio_version_id,
        source,
        source_id,
        title,
        artist,
        content,
        translation,
        romanized,
        offset_ms,
    })?)
}

pub fn update_lyric_offset(lyric_id: String, offset_ms: i32) -> Result<SavedLyric, String> {
    Ok(lyrics::update_offset(&lyric_id, offset_ms)?)
}

/// Clears the lyrics shown for a version (or every lyric of the song when
/// `audio_version_id` is `None`). Returns whether the song still has lyrics.
pub fn clear_lyrics(song_id: String, audio_version_id: Option<String>) -> Result<bool, String> {
    Ok(lyrics::clear(&song_id, audio_version_id.as_deref())?)
}

// ---- Tags ----

pub fn get_tags() -> Result<Vec<Tag>, String> {
    Ok(tags::all()?)
}

pub fn add_tag(
    name: String,
    color: Option<String>,
    category: Option<String>,
) -> Result<Tag, String> {
    Ok(tags::add(&name, color, category)?)
}

pub fn update_tag(
    tag_id: i64,
    name: String,
    color: Option<String>,
    category: Option<String>,
) -> Result<(), String> {
    Ok(tags::update(tag_id, &name, color, category)?)
}

pub fn delete_tag(tag_id: i64) -> Result<(), String> {
    Ok(tags::delete(tag_id)?)
}

pub fn tag_song(song_id: String, tag_id: i64, bind: bool) -> Result<(), String> {
    Ok(tags::tag_song(&song_id, tag_id, bind)?)
}

// ---- Playlists ----

pub fn get_playlists() -> Result<Vec<Playlist>, String> {
    Ok(playlists::all()?)
}

pub fn create_playlist(name: String) -> Result<Playlist, String> {
    Ok(playlists::create(&name)?)
}

pub fn rename_playlist(id: String, name: String) -> Result<(), String> {
    Ok(playlists::rename(&id, &name)?)
}

pub fn delete_playlist(id: String) -> Result<(), String> {
    Ok(playlists::delete(&id)?)
}

pub fn get_playlist_songs(playlist_id: String) -> Result<Vec<String>, String> {
    Ok(playlists::song_ids(&playlist_id)?)
}

pub fn add_songs_to_playlist(playlist_id: String, song_ids: Vec<String>) -> Result<(), String> {
    Ok(playlists::add_songs(&playlist_id, &song_ids)?)
}

pub fn remove_songs_from_playlist(
    playlist_id: String,
    song_ids: Vec<String>,
) -> Result<(), String> {
    Ok(playlists::remove_songs(&playlist_id, &song_ids)?)
}
