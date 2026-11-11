use rusqlite::{params, Connection, Result};

/// Tags seeded into a brand-new (or reset) library: `(name, color, category)`.
const DEFAULT_TAGS: [(&str, &str, &str); 11] = [
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

const CREATE_TABLES: &str = "
    CREATE TABLE IF NOT EXISTS songs (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT,
        album TEXT,
        lyrics TEXT,
        cover_path TEXT,
        rating INTEGER DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    -- One row per managed audio file; a song can own several versions.
    CREATE TABLE IF NOT EXISTS audio_files (
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
        metadata_scanned INTEGER DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        color TEXT,
        category TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS song_tags (
        song_id TEXT NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (song_id, tag_id),
        FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
    );

    -- Lyrics bind to a song and, preferably, to one specific audio version.
    CREATE TABLE IF NOT EXISTS lyrics (
        id TEXT PRIMARY KEY,
        song_id TEXT NOT NULL,
        audio_version_id TEXT,
        source TEXT NOT NULL,
        source_id TEXT,
        title TEXT NOT NULL,
        artist TEXT,
        content TEXT NOT NULL,
        translation TEXT,
        romanized TEXT,
        offset_ms INTEGER DEFAULT 0,
        is_selected INTEGER DEFAULT 1,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE,
        FOREIGN KEY (audio_version_id) REFERENCES audio_files(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS playlist_songs (
        playlist_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, song_id),
        FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
        FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
    );
";

/// Columns added after the first release: `(column, definition)`. Databases
/// created by older builds (or pulled from an older peer) gain them here.
const AUDIO_FILE_MIGRATIONS: [(&str, &str); 4] = [
    ("md5", "TEXT"),
    ("bit_depth", "INTEGER"),
    ("loudness", "REAL"),
    ("metadata_scanned", "INTEGER DEFAULT 0"),
];

// Created after the column migrations because `idx_audio_files_md5` needs `md5`.
const CREATE_INDEXES: &str = "
    CREATE INDEX IF NOT EXISTS idx_audio_files_song ON audio_files(song_id);
    CREATE INDEX IF NOT EXISTS idx_audio_files_md5 ON audio_files(md5);
    CREATE INDEX IF NOT EXISTS idx_song_tags_song ON song_tags(song_id);
    CREATE INDEX IF NOT EXISTS idx_song_tags_tag ON song_tags(tag_id);
    CREATE INDEX IF NOT EXISTS idx_lyrics_song_version
        ON lyrics(song_id, audio_version_id, is_selected);
";

/// Creates missing tables, applies column migrations and seeds default tags.
pub fn migrate(conn: &mut Connection) -> Result<()> {
    let tx = conn.transaction()?;
    tx.execute_batch(CREATE_TABLES)?;
    for (column, definition) in AUDIO_FILE_MIGRATIONS {
        if !has_column(&tx, "audio_files", column)? {
            tx.execute_batch(&format!(
                "ALTER TABLE audio_files ADD COLUMN {column} {definition};"
            ))?;
        }
    }
    tx.execute_batch(CREATE_INDEXES)?;

    let tag_count: i64 = tx.query_row("SELECT COUNT(*) FROM tags", [], |row| row.get(0))?;
    if tag_count == 0 {
        seed_default_tags(&tx)?;
    }
    tx.commit()
}

pub fn seed_default_tags(conn: &Connection) -> Result<()> {
    let mut stmt =
        conn.prepare("INSERT OR IGNORE INTO tags (name, color, category) VALUES (?1, ?2, ?3)")?;
    for (name, color, category) in DEFAULT_TAGS {
        stmt.execute(params![name, color, category])?;
    }
    Ok(())
}

fn has_column(conn: &Connection, table: &str, column: &str) -> Result<bool> {
    conn.query_row(
        "SELECT COUNT(*) FROM pragma_table_info(?1) WHERE name = ?2",
        params![table, column],
        |row| row.get::<_, i64>(0).map(|count| count > 0),
    )
}
