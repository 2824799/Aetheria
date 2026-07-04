use rusqlite::{params, Connection, Result};
use std::path::PathBuf;
use std::sync::RwLock;

static LIBRARY_DIR: RwLock<Option<PathBuf>> = RwLock::new(None);

pub fn set_library_dir(path: PathBuf) {
    if let Ok(mut dir) = LIBRARY_DIR.write() {
        *dir = Some(path);
    }
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
            // Fallback for development
            std::env::temp_dir().join("aetheria_library")
        }
        #[cfg(not(debug_assertions))]
        {
            std::env::temp_dir().join("aetheria_library")
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
