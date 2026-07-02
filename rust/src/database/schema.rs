use rusqlite::{params, Result};
use super::connection::{establish_connection, init_storage};

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
            loudness REAL,
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

    // 数据库迁移：自动检查并补全 loudness 列（针对已有旧数据库文件）
    let has_loudness: bool = conn.query_row(
        "SELECT COUNT(*) FROM pragma_table_info('audio_files') WHERE name='loudness'",
        [],
        |row| row.get::<_, i64>(0).map(|count| count > 0)
    ).unwrap_or(false);
    
    if !has_loudness {
        let _ = conn.execute("ALTER TABLE audio_files ADD COLUMN loudness REAL;", []);
    }

    // 自动为已有但 loudness 为空的音频计算听感指标
    if let Ok(mut stmt) = conn.prepare("SELECT id, filepath FROM audio_files WHERE loudness IS NULL") {
        let files_dir = super::connection::get_files_dir();
        if let Ok(rows) = stmt.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        }) {
            let mut pending_updates = Vec::new();
            for r in rows {
                if let Ok((id, filepath)) = r {
                    let filename = filepath.split('/').last().unwrap_or(&filepath);
                    let abs_path = files_dir.join(filename);
                    if abs_path.exists() {
                        if let Ok(ld) = crate::audio::dsp::calculate_loudness(&abs_path.to_string_lossy()) {
                            pending_updates.push((id, ld));
                        }
                    }
                }
            }
            for (id, ld) in pending_updates {
                let _ = conn.execute("UPDATE audio_files SET loudness = ?1 WHERE id = ?2", params![ld, id]);
            }
        }
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
