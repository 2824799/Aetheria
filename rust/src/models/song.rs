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
