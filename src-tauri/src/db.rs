use std::path::PathBuf;
use rusqlite::{params, Connection, Result};
use serde::{Deserialize, Serialize};
use tauri::Manager;

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Tag {
    pub id: i64,
    pub name: String,
    pub color: Option<String>,
    pub category: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct AudioVersion {
    pub id: String,
    pub song_id: String,
    pub filepath: String, // Relative path, e.g. "files/uuid.mp3"
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
}

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
pub struct Playlist {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub created_at: String,
}

use std::sync::RwLock;

static LIBRARY_DIR: RwLock<Option<PathBuf>> = RwLock::new(None);

pub fn set_library_dir(path: PathBuf) {
    if let Ok(mut dir) = LIBRARY_DIR.write() {
        *dir = Some(path);
    }
}

pub fn get_config_path(app_handle: &tauri::AppHandle) -> PathBuf {
    app_handle.path().app_data_dir().expect("Failed to get app data dir").join("config.json")
}

#[derive(Serialize, Deserialize, Clone, Debug)]
struct AppConfig {
    library_path: String,
}

pub fn load_library_path(app_handle: &tauri::AppHandle) -> Option<PathBuf> {
    let config_path = get_config_path(app_handle);
    if config_path.exists() {
        if let Ok(content) = std::fs::read_to_string(&config_path) {
            if let Ok(config) = serde_json::from_str::<AppConfig>(&content) {
                return Some(PathBuf::from(config.library_path));
            }
        }
    }
    None
}

pub fn save_library_path(app_handle: &tauri::AppHandle, path: PathBuf) -> Result<(), String> {
    let config_path = get_config_path(app_handle);
    if let Some(parent) = config_path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let config = AppConfig {
        library_path: path.to_string_lossy().to_string(),
    };
    let content = serde_json::to_string(&config).map_err(|e| e.to_string())?;
    std::fs::write(&config_path, content).map_err(|e| e.to_string())?;
    Ok(())
}

// 获取库的根路径
pub fn get_library_dir() -> PathBuf {
    let mut custom_path = None;
    if let Ok(dir) = LIBRARY_DIR.read() {
        if let Some(path) = &*dir {
            custom_path = Some(path.clone());
        }
    }
    
    if let Some(path) = custom_path {
        path
    } else {
        #[cfg(debug_assertions)]
        {
            PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .parent()
                .expect("Failed to get parent directory")
                .join("library")
        }
        #[cfg(not(debug_assertions))]
        {
            #[cfg(any(target_os = "android", target_os = "ios"))]
            {
                std::env::temp_dir().join("library")
            }
            #[cfg(not(any(target_os = "android", target_os = "ios")))]
            {
                let mut path = std::env::current_exe().expect("Failed to get current exe path");
                path.pop();
                path.join("library")
            }
        }
    }
}

// 获取托管音频文件夹路径
pub fn get_files_dir() -> PathBuf {
    get_library_dir().join("files")
}

// 初始化本地文件夹结构
pub fn init_storage() -> std::io::Result<()> {
    let files_dir = get_files_dir();
    std::fs::create_dir_all(files_dir)?;
    Ok(())
}

// 建立 SQLite 连接
pub fn establish_connection() -> Result<Connection> {
    let db_path = get_library_dir().join("database.db");
    
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let conn = {
        let db_url = format!("file://{}?nolock=1", db_path.display());
        Connection::open_with_flags(
            db_url,
            rusqlite::OpenFlags::SQLITE_OPEN_READ_WRITE
                | rusqlite::OpenFlags::SQLITE_OPEN_CREATE
                | rusqlite::OpenFlags::SQLITE_OPEN_URI,
        )?
    };

    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let conn = Connection::open(db_path)?;

    conn.execute("PRAGMA foreign_keys = ON;", [])?;
    Ok(conn)
}

// 初始化数据库表
pub fn init_db() -> Result<()> {
    init_storage().map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?;
    let conn = establish_connection()?;

    // 1. 歌曲表
    conn.execute(
        "CREATE TABLE IF NOT EXISTS songs (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            artist TEXT,
            album TEXT,
            lyrics TEXT,
            cover_path TEXT,
            rating INTEGER DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );",
        [],
    )?;

    // 2. 音频文件（版本）表
    conn.execute(
        "CREATE TABLE IF NOT EXISTS audio_files (
            id TEXT PRIMARY KEY,
            song_id TEXT NOT NULL,
            filepath TEXT NOT NULL UNIQUE,
            original_name TEXT NOT NULL,
            format TEXT,
            bitrate INTEGER,
            sample_rate INTEGER,
            duration REAL NOT NULL,
            file_size INTEGER NOT NULL,
            is_enabled INTEGER DEFAULT 1,
            is_primary INTEGER DEFAULT 0,
            md5 TEXT,
            bit_depth INTEGER,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
        );",
        [],
    )?;

    // 3. 标签定义表
    conn.execute(
        "CREATE TABLE IF NOT EXISTS tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            color TEXT,
            category TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );",
        [],
    )?;

    // 4. 歌曲与标签关联表（多对多）
    conn.execute(
        "CREATE TABLE IF NOT EXISTS song_tags (
            song_id TEXT NOT NULL,
            tag_id INTEGER NOT NULL,
            PRIMARY KEY (song_id, tag_id),
            FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE,
            FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
        );",
        [],
    )?;

    // 5. 传统歌单表
    conn.execute(
        "CREATE TABLE IF NOT EXISTS playlists (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            description TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );",
        [],
    )?;

    // 6. 歌单与歌曲关联表
    conn.execute(
        "CREATE TABLE IF NOT EXISTS playlist_songs (
            playlist_id TEXT NOT NULL,
            song_id TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            PRIMARY KEY (playlist_id, song_id),
            FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
            FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
        );",
        [],
    )?;

    // 创建索引以优化高频查询
    conn.execute("CREATE INDEX IF NOT EXISTS idx_audio_files_song ON audio_files(song_id);", [])?;
    conn.execute("CREATE INDEX IF NOT EXISTS idx_song_tags_song ON song_tags(song_id);", [])?;
    conn.execute("CREATE INDEX IF NOT EXISTS idx_song_tags_tag ON song_tags(tag_id);", [])?;

    // 数据库迁移：自动检查并补全 md5 列（针对已有旧数据库文件）
    let has_md5: bool = conn.query_row(
        "SELECT COUNT(*) FROM pragma_table_info('audio_files') WHERE name='md5'",
        [],
        |row| row.get::<_, i64>(0).map(|count| count > 0)
    ).unwrap_or(false);
    
    if !has_md5 {
        let _ = conn.execute("ALTER TABLE audio_files ADD COLUMN md5 TEXT;", []);
    }

    // 数据库迁移：自动检查并补全 bit_depth 列（针对已有旧数据库文件）
    let has_bit_depth: bool = conn.query_row(
        "SELECT COUNT(*) FROM pragma_table_info('audio_files') WHERE name='bit_depth'",
        [],
        |row| row.get::<_, i64>(0).map(|count| count > 0)
    ).unwrap_or(false);
    
    if !has_bit_depth {
        let _ = conn.execute("ALTER TABLE audio_files ADD COLUMN bit_depth INTEGER;", []);
    }

    // 插入默认种子标签（若库为空）
    let count: i64 = conn.query_row("SELECT COUNT(*) FROM tags", [], |row| row.get(0))?;
    if count == 0 {
        let default_tags = vec![
            ("中文", "#ef4444", "语言"),
            ("英文", "#3b82f6", "语言"),
            ("日韩", "#f43f5e", "语言"),
            ("纯音乐", "#10b981", "流派"),
            ("摇滚", "#f59e0b", "流派"),
            ("流行", "#ec4899", "流派"),
            ("民谣", "#84cc16", "流派"),
            ("古典", "#64748b", "流派"),
            ("伤感", "#8b5cf6", "情绪"),
            ("治愈", "#06b6d4", "情绪"),
            ("欢快", "#eab308", "情绪"),
        ];

        for (name, color, category) in default_tags {
            conn.execute(
                "INSERT INTO tags (name, color, category) VALUES (?1, ?2, ?3)",
                params![name, color, category],
            )?;
        }
    }

    Ok(())
}
