use std::fs;
use std::path::Path;
use rusqlite::{params, OptionalExtension};
use uuid::Uuid;
use lofty::probe::Probe;
use lofty::file::{AudioFile, TaggedFileExt};
use lofty::tag::Accessor;

use crate::db::{self, Song, AudioVersion, Tag};

// 错误处理辅助宏
macro_rules! err_str {
    ($e:expr) => {
        $e.map_err(|err| err.to_string())
    };
}

#[tauri::command]
pub fn get_songs() -> Result<Vec<Song>, String> {
    let conn = err_str!(db::establish_connection())?;
    
    // 1. 查询所有歌曲
    let mut stmt = err_str!(conn.prepare(
        "SELECT id, title, artist, album, lyrics, cover_path, rating, created_at FROM songs ORDER BY title ASC"
    ))?;
    
    let song_rows = err_str!(stmt.query_map([], |row| {
        Ok(Song {
            id: row.get(0)?,
            title: row.get(1)?,
            artist: row.get(2)?,
            album: row.get(3)?,
            lyrics: row.get(4)?,
            cover_path: row.get(5)?,
            rating: row.get(6)?,
            created_at: row.get(7)?,
            versions: Vec::new(),
            tags: Vec::new(),
        })
    }))?;
    
    let mut songs = Vec::new();
    for song_res in song_rows {
        let mut song = err_str!(song_res)?;
        
        // 2. 查询该歌曲关联的所有音频版本
        let mut v_stmt = err_str!(conn.prepare(
            "SELECT id, song_id, filepath, original_name, format, bitrate, sample_rate, duration, file_size, is_enabled, is_primary FROM audio_files WHERE song_id = ?1"
        ))?;
        
        let v_rows = err_str!(v_stmt.query_map(params![song.id], |row| {
            let is_enabled_int: i32 = row.get(9)?;
            let is_primary_int: i32 = row.get(10)?;
            Ok(AudioVersion {
                id: row.get(0)?,
                song_id: row.get(1)?,
                filepath: row.get(2)?,
                original_name: row.get(3)?,
                format: row.get(4)?,
                bitrate: row.get(5)?,
                sample_rate: row.get(6)?,
                duration: row.get(7)?,
                file_size: row.get(8)?,
                is_enabled: is_enabled_int != 0,
                is_primary: is_primary_int != 0,
            })
        }))?;
        
        for v in v_rows {
            song.versions.push(err_str!(v)?);
        }
        
        // 3. 查询该歌曲绑定的标签
        let mut t_stmt = err_str!(conn.prepare(
            "SELECT t.id, t.name, t.color, t.category FROM tags t 
             JOIN song_tags st ON t.id = st.tag_id 
             WHERE st.song_id = ?1"
        ))?;
        
        let t_rows = err_str!(t_stmt.query_map(params![song.id], |row| {
            Ok(Tag {
                id: row.get(0)?,
                name: row.get(1)?,
                color: row.get(2)?,
                category: row.get(3)?,
            })
        }))?;
        
        for t in t_rows {
            song.tags.push(err_str!(t)?);
        }
        
        songs.push(song);
    }
    
    Ok(songs)
}

#[tauri::command]
pub fn import_song(filepath: String) -> Result<Song, String> {
    let src_path = Path::new(&filepath);
    if !src_path.exists() {
        return Err("File does not exist".to_string());
    }
    
    let original_name = src_path.file_name()
        .ok_or_else(|| "Invalid file name".to_string())?
        .to_string_lossy()
        .to_string();
        
    let ext = src_path.extension()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    let file_size = err_str!(src_path.metadata())?.len() as i64;
    
    // 1. 使用 lofty 读取元数据
    let tagged_file = Probe::open(src_path)
        .map_err(|e| format!("Failed to open file probe: {}", e))?
        .read()
        .map_err(|e| format!("Failed to read metadata: {}", e))?;
        
    let properties = tagged_file.properties();
    let duration = properties.duration().as_secs_f64();
    let bitrate = properties.audio_bitrate().map(|b| b as i32);
    let sample_rate = properties.sample_rate().map(|s| s as i32);
    
    let mut title = src_path.file_stem()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let mut artist = None;
    let mut album = None;
    
    // 优先读取主要标签
    if let Some(primary_tag) = tagged_file.primary_tag() {
        if let Some(t) = primary_tag.title() {
            title = t.to_string();
        }
        if let Some(a) = primary_tag.artist() {
            artist = Some(a.to_string());
        }
        if let Some(al) = primary_tag.album() {
            album = Some(al.to_string());
        }
    } else if let Some(first_tag) = tagged_file.first_tag() {
        if let Some(t) = first_tag.title() {
            title = t.to_string();
        }
        if let Some(a) = first_tag.artist() {
            artist = Some(a.to_string());
        }
        if let Some(al) = first_tag.album() {
            album = Some(al.to_string());
        }
    }
    
    // 2. 复制物理文件到托管文件夹
    let uuid = Uuid::new_v4().to_string();
    let dest_filename = format!("{}.{}", uuid, ext);
    let dest_relative_path = format!("files/{}", dest_filename);
    let dest_absolute_path = db::get_files_dir().join(&dest_filename);
    
    err_str!(fs::copy(src_path, &dest_absolute_path))?;
    
    let conn = err_str!(db::establish_connection())?;
    
    // 3. 匹配歌曲实体，防重复
    // 查找是否已存在相同 Title 且相同 Artist 的歌曲
    let song_id: String = match artist {
        Some(ref art_name) => {
            conn.query_row(
                "SELECT id FROM songs WHERE title = ?1 AND artist = ?2",
                params![title, art_name],
                |row| row.get(0)
            ).optional()
        },
        None => {
            conn.query_row(
                "SELECT id FROM songs WHERE title = ?1 AND artist IS NULL",
                params![title],
                |row| row.get(0)
            ).optional()
        }
    }.map_err(|e| e.to_string())?
     .unwrap_or_else(|| {
         // 不存在则创建新歌曲对象
         let new_id = Uuid::new_v4().to_string();
         conn.execute(
             "INSERT INTO songs (id, title, artist, album) VALUES (?1, ?2, ?3, ?4)",
             params![new_id, title, artist, album]
         ).unwrap();
         new_id
     });
     
    // 4. 插入音频版本记录
    // 检查这是不是该歌曲的第一个音频文件（如果是，默认设为 Primary）
    let version_count: i64 = err_str!(conn.query_row(
        "SELECT COUNT(*) FROM audio_files WHERE song_id = ?1",
        params![song_id],
        |row| row.get(0)
    ))?;
    let is_primary = if version_count == 0 { 1 } else { 0 };
    
    let version_id = Uuid::new_v4().to_string();
    err_str!(conn.execute(
        "INSERT INTO audio_files (id, song_id, filepath, original_name, format, bitrate, sample_rate, duration, file_size, is_enabled, is_primary) 
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 1, ?10)",
        params![
            version_id,
            song_id,
            dest_relative_path,
            original_name,
            ext,
            bitrate,
            sample_rate,
            duration,
            file_size,
            is_primary
        ]
    ))?;
    
    // 5. 组装插入后的歌曲对象返回
    let mut stmt = err_str!(conn.prepare(
        "SELECT id, title, artist, album, lyrics, cover_path, rating, created_at FROM songs WHERE id = ?1"
    ))?;
    
    let mut song = err_str!(stmt.query_row(params![song_id], |row| {
        Ok(Song {
            id: row.get(0)?,
            title: row.get(1)?,
            artist: row.get(2)?,
            album: row.get(3)?,
            lyrics: row.get(4)?,
            cover_path: row.get(5)?,
            rating: row.get(6)?,
            created_at: row.get(7)?,
            versions: Vec::new(),
            tags: Vec::new(),
        })
    }))?;
    
    // 再次加载该歌曲的全部版本和标签
    let mut v_stmt = err_str!(conn.prepare(
        "SELECT id, song_id, filepath, original_name, format, bitrate, sample_rate, duration, file_size, is_enabled, is_primary FROM audio_files WHERE song_id = ?1"
    ))?;
    let v_rows = err_str!(v_stmt.query_map(params![song.id], |row| {
        let is_enabled_int: i32 = row.get(9)?;
        let is_primary_int: i32 = row.get(10)?;
        Ok(AudioVersion {
            id: row.get(0)?,
            song_id: row.get(1)?,
            filepath: row.get(2)?,
            original_name: row.get(3)?,
            format: row.get(4)?,
            bitrate: row.get(5)?,
            sample_rate: row.get(6)?,
            duration: row.get(7)?,
            file_size: row.get(8)?,
            is_enabled: is_enabled_int != 0,
            is_primary: is_primary_int != 0,
        })
    }))?;
    for v in v_rows {
        song.versions.push(err_str!(v)?);
    }
    
    let mut t_stmt = err_str!(conn.prepare(
        "SELECT t.id, t.name, t.color, t.category FROM tags t 
         JOIN song_tags st ON t.id = st.tag_id 
         WHERE st.song_id = ?1"
    ))?;
    let t_rows = err_str!(t_stmt.query_map(params![song.id], |row| {
        Ok(Tag {
            id: row.get(0)?,
            name: row.get(1)?,
            color: row.get(2)?,
            category: row.get(3)?,
        })
    }))?;
    for t in t_rows {
        song.tags.push(err_str!(t)?);
    }
    
    Ok(song)
}

#[tauri::command]
pub fn export_song(version_id: String, export_dir: String) -> Result<String, String> {
    let conn = err_str!(db::establish_connection())?;
    
    let (filepath, original_name): (String, String) = err_str!(conn.query_row(
        "SELECT filepath, original_name FROM audio_files WHERE id = ?1",
        params![version_id],
        |row| Ok((row.get(0)?, row.get(1)?))
    ))?;
    
    let src_absolute = db::get_library_dir().join(&filepath);
    if !src_absolute.exists() {
        return Err("Source file not found in library".to_string());
    }
    
    let export_dir_path = Path::new(&export_dir);
    if !export_dir_path.exists() {
        return Err("Export directory does not exist".to_string());
    }
    
    let dest_absolute = export_dir_path.join(&original_name);
    err_str!(fs::copy(src_absolute, &dest_absolute))?;
    
    Ok(dest_absolute.to_string_lossy().to_string())
}

#[tauri::command]
pub fn update_version_status(version_id: String, is_enabled: bool, is_primary: bool) -> Result<(), String> {
    let conn = err_str!(db::establish_connection())?;
    
    let is_enabled_int = if is_enabled { 1 } else { 0 };
    
    // 更新启用状态
    err_str!(conn.execute(
        "UPDATE audio_files SET is_enabled = ?1 WHERE id = ?2",
        params![is_enabled_int, version_id]
    ))?;
    
    // 如果被设为主版本，重置同歌曲其他版本的主版本状态
    if is_primary {
        let song_id: String = err_str!(conn.query_row(
            "SELECT song_id FROM audio_files WHERE id = ?1",
            params![version_id],
            |row| row.get(0)
        ))?;
        
        err_str!(conn.execute(
            "UPDATE audio_files SET is_primary = 0 WHERE song_id = ?1",
            params![song_id]
        ))?;
        
        err_str!(conn.execute(
            "UPDATE audio_files SET is_primary = 1 WHERE id = ?1",
            params![version_id]
        ))?;
    }
    
    Ok(())
}

#[tauri::command]
pub fn get_tags() -> Result<Vec<Tag>, String> {
    let conn = err_str!(db::establish_connection())?;
    let mut stmt = err_str!(conn.prepare("SELECT id, name, color, category FROM tags ORDER BY category, name"))?;
    let rows = err_str!(stmt.query_map([], |row| {
        Ok(Tag {
            id: row.get(0)?,
            name: row.get(1)?,
            color: row.get(2)?,
            category: row.get(3)?,
        })
    }))?;
    
    let mut tags = Vec::new();
    for r in rows {
        tags.push(err_str!(r)?);
    }
    Ok(tags)
}

#[tauri::command]
pub fn add_tag(name: String, color: Option<String>, category: Option<String>) -> Result<Tag, String> {
    let conn = err_str!(db::establish_connection())?;
    err_str!(conn.execute(
        "INSERT INTO tags (name, color, category) VALUES (?1, ?2, ?3)",
        params![name, color, category]
    ))?;
    
    let last_id = conn.last_insert_rowid();
    Ok(Tag {
        id: last_id,
        name,
        color,
        category,
    })
}

#[tauri::command]
pub fn delete_tag(tag_id: i64) -> Result<(), String> {
    let conn = err_str!(db::establish_connection())?;
    err_str!(conn.execute("DELETE FROM tags WHERE id = ?1", params![tag_id]))?;
    Ok(())
}

#[tauri::command]
pub fn tag_song(song_id: String, tag_id: i64, bind: bool) -> Result<(), String> {
    let conn = err_str!(db::establish_connection())?;
    if bind {
        err_str!(conn.execute(
            "INSERT OR IGNORE INTO song_tags (song_id, tag_id) VALUES (?1, ?2)",
            params![song_id, tag_id]
        ))?;
    } else {
        err_str!(conn.execute(
            "DELETE FROM song_tags WHERE song_id = ?1 AND tag_id = ?2",
            params![song_id, tag_id]
        ))?;
    }
    Ok(())
}

#[tauri::command]
pub fn get_library_path() -> Result<String, String> {
    Ok(db::get_library_dir().to_string_lossy().to_string())
}

#[tauri::command]
pub fn select_audio_files() -> Result<Vec<String>, String> {
    let files = rfd::FileDialog::new()
        .add_filter("Audio Files", &["mp3", "wav", "flac", "m4a", "ogg", "aac"])
        .pick_files();
        
    match files {
        Some(paths) => {
            let path_strs = paths.iter()
                .map(|p| p.to_string_lossy().to_string())
                .collect();
            Ok(path_strs)
        },
        None => Ok(Vec::new())
    }
}

#[tauri::command]
pub fn select_export_directory() -> Result<Option<String>, String> {
    let dir = rfd::FileDialog::new()
        .pick_folder();
        
    match dir {
        Some(path) => Ok(Some(path.to_string_lossy().to_string())),
        None => Ok(None)
    }
}

#[tauri::command]
pub fn select_directory() -> Result<Option<String>, String> {
    let dir = rfd::FileDialog::new()
        .pick_folder();
        
    match dir {
        Some(path) => Ok(Some(path.to_string_lossy().to_string())),
        None => Ok(None)
    }
}

#[tauri::command]
pub fn select_save_file() -> Result<Option<String>, String> {
    let file = rfd::FileDialog::new()
        .save_file();
        
    match file {
        Some(path) => Ok(Some(path.to_string_lossy().to_string())),
        None => Ok(None)
    }
}

#[tauri::command]
pub fn get_playlists() -> Result<Vec<db::Playlist>, String> {
    let conn = err_str!(db::establish_connection())?;
    let mut stmt = err_str!(conn.prepare(
        "SELECT id, name, description, created_at FROM playlists ORDER BY created_at ASC"
    ))?;
    let rows = err_str!(stmt.query_map([], |row| {
        Ok(db::Playlist {
            id: row.get(0)?,
            name: row.get(1)?,
            description: row.get(2)?,
            created_at: row.get(3)?,
        })
    }))?;
    let mut playlists = Vec::new();
    for r in rows {
        playlists.push(err_str!(r)?);
    }
    Ok(playlists)
}

#[tauri::command]
pub fn create_playlist(name: String) -> Result<db::Playlist, String> {
    let conn = err_str!(db::establish_connection())?;
    let id = uuid::Uuid::new_v4().to_string();
    err_str!(conn.execute(
        "INSERT INTO playlists (id, name, description) VALUES (?1, ?2, '')",
        params![id, name]
    ))?;
    
    let mut stmt = err_str!(conn.prepare(
        "SELECT id, name, description, created_at FROM playlists WHERE id = ?1"
    ))?;
    let playlist = err_str!(stmt.query_row(params![id], |row| {
        Ok(db::Playlist {
            id: row.get(0)?,
            name: row.get(1)?,
            description: row.get(2)?,
            created_at: row.get(3)?,
        })
    }))?;
    Ok(playlist)
}

#[tauri::command]
pub fn delete_playlist(id: String) -> Result<(), String> {
    let conn = err_str!(db::establish_connection())?;
    err_str!(conn.execute("DELETE FROM playlists WHERE id = ?1", params![id]))?;
    Ok(())
}

#[tauri::command]
pub fn rename_playlist(id: String, name: String) -> Result<(), String> {
    let conn = err_str!(db::establish_connection())?;
    err_str!(conn.execute("UPDATE playlists SET name = ?1 WHERE id = ?2", params![name, id]))?;
    Ok(())
}

#[tauri::command]
pub fn add_songs_to_playlist(playlist_id: String, song_ids: Vec<String>) -> Result<(), String> {
    let mut conn = err_str!(db::establish_connection())?;
    let tx = err_str!(conn.transaction())?;
    
    // Get current max sort_order
    let max_sort_order: i32 = err_str!(tx.query_row(
        "SELECT COALESCE(MAX(sort_order), -1) FROM playlist_songs WHERE playlist_id = ?1",
        params![playlist_id],
        |row| row.get(0)
    ))?;
    
    let mut current_order = max_sort_order + 1;
    for song_id in song_ids {
        let exists: i64 = err_str!(tx.query_row(
            "SELECT COUNT(*) FROM playlist_songs WHERE playlist_id = ?1 AND song_id = ?2",
            params![playlist_id, song_id],
            |row| row.get(0)
        ))?;
        if exists == 0 {
            err_str!(tx.execute(
                "INSERT INTO playlist_songs (playlist_id, song_id, sort_order) VALUES (?1, ?2, ?3)",
                params![playlist_id, song_id, current_order]
            ))?;
            current_order += 1;
        }
    }
    err_str!(tx.commit())?;
    Ok(())
}

#[tauri::command]
pub fn remove_songs_from_playlist(playlist_id: String, song_ids: Vec<String>) -> Result<(), String> {
    let mut conn = err_str!(db::establish_connection())?;
    let tx = err_str!(conn.transaction())?;
    for song_id in song_ids {
        err_str!(tx.execute(
            "DELETE FROM playlist_songs WHERE playlist_id = ?1 AND song_id = ?2",
            params![playlist_id, song_id]
        ))?;
    }
    err_str!(tx.commit())?;
    Ok(())
}

#[tauri::command]
pub fn get_playlist_songs(playlist_id: String) -> Result<Vec<String>, String> {
    let conn = err_str!(db::establish_connection())?;
    let mut stmt = err_str!(conn.prepare(
        "SELECT song_id FROM playlist_songs WHERE playlist_id = ?1 ORDER BY sort_order ASC"
    ))?;
    let rows = err_str!(stmt.query_map(params![playlist_id], |row| row.get::<_, String>(0)))?;
    let mut song_ids = Vec::new();
    for r in rows {
        song_ids.push(err_str!(r)?);
    }
    Ok(song_ids)
}

fn scan_directory(dir: &Path, files: &mut Vec<std::path::PathBuf>) -> std::io::Result<()> {
    if dir.is_dir() {
        for entry in fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() {
                scan_directory(&path, files)?;
            } else if path.is_file() {
                if let Some(ext) = path.extension() {
                    let ext_str = ext.to_string_lossy().to_lowercase();
                    if ["mp3", "wav", "flac", "m4a", "ogg", "aac"].contains(&ext_str.as_str()) {
                        files.push(path);
                    }
                }
            }
        }
    }
    Ok(())
}

#[tauri::command]
pub fn import_audio_files(dir_path: String) -> Result<i32, String> {
    let path = Path::new(&dir_path);
    if !path.is_dir() {
        return Err("Not a directory".to_string());
    }

    let mut files = Vec::new();
    scan_directory(path, &mut files).map_err(|e| e.to_string())?;

    let mut import_count = 0;
    for file in files {
        let path_str = file.to_string_lossy().to_string();
        match import_song(path_str) {
            Ok(_) => import_count += 1,
            Err(e) => println!("Failed to import {}: {}", file.display(), e),
        }
    }
    Ok(import_count)
}


