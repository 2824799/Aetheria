use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Song {
    pub id: String,
    pub title: String,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub lyrics: Option<String>,
    pub cover_path: Option<String>,
    pub rating: i32,
    pub created_at: String,
    pub versions: Vec<AudioVersion>,
    pub tags: Vec<Tag>,
    pub phigros: Option<PhigrosSongMeta>,
}

/// Chart metadata for one Phigros difficulty level attached to a song.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct PhigrosChartMeta {
    pub difficulty: String,
    pub sort_rank: i32,
    pub rating: f64,
    pub charter: String,
    pub bpm_min: f64,
    pub bpm_max: f64,
    pub chart_offset_ms: i32,
    pub note_count: i32,
    pub tap_count: i32,
    pub drag_count: i32,
    pub hold_count: i32,
    pub flick_count: i32,
    pub audio_rel_path: Option<String>,
    pub cover_rel_path: Option<String>,
    pub chart_rel_path: String,
}

/// Per-song Phigros metadata, selected chart difficulty, and per-song hitsound overrides.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct PhigrosSongMeta {
    pub phigros_id: String,
    pub chapter: String,
    pub composer: String,
    pub illustrator: String,
    pub selected_difficulty: String,
    /// `"global"`, `"on"`, or `"off"`.
    pub hitsound_mode: String,
    pub hitsound_volume: Option<f64>,
    pub hitsound_offset_ms: Option<i32>,
    pub charts: Vec<PhigrosChartMeta>,
}

/// Summary returned after importing or refreshing a Phigros asset package.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct PhigrosImportResult {
    pub playlist_id: String,
    pub imported_count: i32,
    pub updated_count: i32,
    pub chart_count: i32,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct AudioVersion {
    pub id: String,
    pub song_id: String,
    pub filepath: String,      // Relative path, e.g. "files/uuid.mp3"
    pub original_name: String, // e.g. "周杰伦 - 晴天.mp3"
    pub format: Option<String>,
    pub bitrate: Option<i32>,
    pub sample_rate: Option<i32>,
    pub duration: f64,
    pub file_size: i64,
    pub is_enabled: bool,
    pub is_primary: bool,
    pub md5: Option<String>,
    pub bit_depth: Option<i32>,
    pub loudness: Option<f64>,
    pub metadata_scanned: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct SavedLyric {
    pub id: String,
    pub song_id: String,
    pub audio_version_id: Option<String>,
    pub source: String,
    pub source_id: Option<String>,
    pub title: String,
    pub artist: Option<String>,
    pub content: String,
    pub translation: Option<String>,
    pub romanized: Option<String>,
    pub offset_ms: i32,
    pub is_selected: bool,
    pub updated_at: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct LocalLyricCandidate {
    pub source: String,
    pub source_id: Option<String>,
    pub title: String,
    pub artist: Option<String>,
    pub content: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Tag {
    pub id: i64,
    pub name: String,
    pub color: Option<String>,
    pub category: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct PreviewInfo {
    pub filepath: String,
    pub filename: String,
    pub title: String,
    pub artist: String,
}
