use std::path::Path;
use flutter_rust_bridge::frb;
use crate::models::{Song, Tag, AudioVersion, Playlist, PreviewInfo};
use crate::database::connection::{establish_connection, init_storage, set_library_dir, get_library_dir, get_files_dir};
use crate::database::schema::init_db;
use std::fs;
use rusqlite::params;
use rusqlite::OptionalExtension;
use uuid::Uuid;
use lofty::probe::Probe;
use lofty::file::{AudioFile, TaggedFileExt};
use lofty::tag::Accessor;

#[frb(sync)]
pub fn is_library_initialized() -> bool {
    let lib_dir = get_library_dir();
    lib_dir.exists() && lib_dir.join("database.db").exists()
}

pub fn initialize_library_path(path: String) -> Result<(), String> {
    let p = std::path::PathBuf::from(path);
    set_library_dir(p);
    init_db().map_err(|e| e.to_string())?;
    Ok(())
}

pub fn get_songs() -> Result<Vec<Song>, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    
    let mut stmt = conn.prepare(
        "SELECT id, title, artist, album, lyrics, cover_path, rating, created_at FROM songs ORDER BY title ASC"
    ).map_err(|e| e.to_string())?;
    
    let song_rows = stmt.query_map([], |row| {
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
    }).map_err(|e| e.to_string())?;
    
    let mut songs = Vec::new();
    for song_res in song_rows {
        let mut song = song_res.map_err(|e| e.to_string())?;
        
        let mut v_stmt = conn.prepare(
            "SELECT id, song_id, filepath, original_name, format, bitrate, sample_rate, duration, file_size, is_enabled, is_primary, md5, bit_depth FROM audio_files WHERE song_id = ?1"
        ).map_err(|e| e.to_string())?;
        
        let v_rows = v_stmt.query_map(params![song.id], |row| {
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
                md5: row.get(11)?,
                bit_depth: row.get(12)?,
            })
        }).map_err(|e| e.to_string())?;
        
        for v in v_rows {
            song.versions.push(v.map_err(|e| e.to_string())?);
        }
        
        let mut t_stmt = conn.prepare(
            "SELECT t.id, t.name, t.color, t.category FROM tags t 
             JOIN song_tags st ON t.id = st.tag_id 
             WHERE st.song_id = ?1"
        ).map_err(|e| e.to_string())?;
        
        let t_rows = t_stmt.query_map(params![song.id], |row| {
            Ok(Tag {
                id: row.get(0)?,
                name: row.get(1)?,
                color: row.get(2)?,
                category: row.get(3)?,
            })
        }).map_err(|e| e.to_string())?;
        
        for t in t_rows {
            song.tags.push(t.map_err(|e| e.to_string())?);
        }
        
        songs.push(song);
    }
    
    Ok(songs)
}

pub fn get_tags() -> Result<Vec<Tag>, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let mut stmt = conn.prepare("SELECT id, name, color, category FROM tags ORDER BY category, name").map_err(|e| e.to_string())?;
    let rows = stmt.query_map([], |row| {
        Ok(Tag {
            id: row.get(0)?,
            name: row.get(1)?,
            color: row.get(2)?,
            category: row.get(3)?,
        })
    }).map_err(|e| e.to_string())?;
    
    let mut tags = Vec::new();
    for r in rows {
        tags.push(r.map_err(|e| e.to_string())?);
    }
    Ok(tags)
}

pub fn get_playlists() -> Result<Vec<Playlist>, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let mut stmt = conn.prepare(
        "SELECT id, name, description, created_at FROM playlists ORDER BY created_at ASC"
    ).map_err(|e| e.to_string())?;
    let rows = stmt.query_map([], |row| {
        Ok(Playlist {
            id: row.get(0)?,
            name: row.get(1)?,
            description: row.get(2)?,
            created_at: row.get(3)?,
        })
    }).map_err(|e| e.to_string())?;
    let mut playlists = Vec::new();
    for r in rows {
        playlists.push(r.map_err(|e| e.to_string())?);
    }
    Ok(playlists)
}

pub fn start_audio_server() -> u16 {
    crate::audio::server::start();
    std::thread::sleep(std::time::Duration::from_millis(50));
    crate::audio::server::get_port()
}

pub fn get_library_path() -> Result<String, String> {
    Ok(get_library_dir().to_string_lossy().to_string())
}

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

    let file_size = src_path.metadata().map_err(|e| e.to_string())?.len() as i64;
    
    let tagged_file = Probe::open(src_path)
        .map_err(|e| format!("Failed to open file probe: {}", e))?
        .read()
        .map_err(|e| format!("Failed to read metadata: {}", e))?;
        
    let properties = tagged_file.properties();
    let duration = properties.duration().as_secs_f64();
    let bitrate = properties.audio_bitrate().map(|b| (b * 1000) as i32);
    let sample_rate = properties.sample_rate().map(|s| s as i32);
    let bit_depth = properties.bit_depth().map(|d| d as i32);
    
    let mut title = src_path.file_stem()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let mut artist = None;
    let mut album = None;
    
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
    
    let file_data = fs::read(src_path).map_err(|e| e.to_string())?;
    let file_md5 = format!("{:x}", md5::compute(file_data));

    let conn = establish_connection().map_err(|e| e.to_string())?;

    let md5_exists: bool = conn.query_row(
        "SELECT COUNT(*) FROM audio_files WHERE md5 = ?1",
        params![file_md5],
        |row| row.get::<_, i64>(0).map(|count| count > 0)
    ).map_err(|e| e.to_string())?;

    if md5_exists {
        return Err(format!("音频文件 [{}] 已存在于音乐库中，请勿重复导入！", original_name));
    }
    
    let uuid = Uuid::new_v4().to_string();
    let dest_filename = format!("{}.{}", uuid, ext);
    let dest_relative_path = format!("files/{}", dest_filename);
    let dest_absolute_path = get_files_dir().join(&dest_filename);
    
    fs::copy(src_path, &dest_absolute_path).map_err(|e| e.to_string())?;
    
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
         let new_id = Uuid::new_v4().to_string();
         conn.execute(
             "INSERT INTO songs (id, title, artist, album) VALUES (?1, ?2, ?3, ?4)",
             params![new_id, title, artist, album]
         ).unwrap();
         new_id
     });
     
    let version_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM audio_files WHERE song_id = ?1",
        params![song_id],
        |row| row.get(0)
    ).map_err(|e| e.to_string())?;
    let is_primary = if version_count == 0 { 1 } else { 0 };
    
    let version_id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO audio_files (id, song_id, filepath, original_name, format, bitrate, sample_rate, duration, file_size, is_enabled, is_primary, md5, bit_depth) 
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 1, ?10, ?11, ?12)",
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
            is_primary,
            file_md5,
            bit_depth
        ]
    ).map_err(|e| e.to_string())?;
    
    let mut stmt = conn.prepare(
        "SELECT id, title, artist, album, lyrics, cover_path, rating, created_at FROM songs WHERE id = ?1"
    ).map_err(|e| e.to_string())?;
    
    let mut song = stmt.query_row(params![song_id], |row| {
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
    }).map_err(|e| e.to_string())?;
    
    let mut v_stmt = conn.prepare(
        "SELECT id, song_id, filepath, original_name, format, bitrate, sample_rate, duration, file_size, is_enabled, is_primary, md5, bit_depth FROM audio_files WHERE song_id = ?1"
    ).map_err(|e| e.to_string())?;
    let v_rows = v_stmt.query_map(params![song.id], |row| {
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
            md5: row.get(11)?,
            bit_depth: row.get(12)?,
        })
    }).map_err(|e| e.to_string())?;
    for v in v_rows {
        song.versions.push(v.map_err(|e| e.to_string())?);
    }
    
    let mut t_stmt = conn.prepare(
        "SELECT t.id, t.name, t.color, t.category FROM tags t 
         JOIN song_tags st ON t.id = st.tag_id 
         WHERE st.song_id = ?1"
    ).map_err(|e| e.to_string())?;
    let t_rows = t_stmt.query_map(params![song.id], |row| {
        Ok(Tag {
            id: row.get(0)?,
            name: row.get(1)?,
            color: row.get(2)?,
            category: row.get(3)?,
        })
    }).map_err(|e| e.to_string())?;
    for t in t_rows {
        song.tags.push(t.map_err(|e| e.to_string())?);
    }
    
    Ok(song)
}

pub fn import_song_with_metadata(filepath: String, title: String, artist: String) -> Result<(), String> {
    let src_path = Path::new(&filepath);
    if !src_path.exists() {
        return Err("File does not exist".to_string());
    }
    
    let original_name = src_path.file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
        
    let ext = src_path.extension()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    let file_size = src_path.metadata().map_err(|e| e.to_string())?.len() as i64;
    
    let tagged_file = Probe::open(src_path)
        .map_err(|e| format!("Failed to open file probe: {}", e))?
        .read()
        .map_err(|e| format!("Failed to read metadata: {}", e))?;
        
    let properties = tagged_file.properties();
    let duration = properties.duration().as_secs_f64();
    let bitrate = properties.audio_bitrate().map(|b| (b * 1000) as i32);
    let sample_rate = properties.sample_rate().map(|s| s as i32);
    let bit_depth = properties.bit_depth().map(|d| d as i32);
    
    let file_data = fs::read(src_path).map_err(|e| e.to_string())?;
    let file_md5 = format!("{:x}", md5::compute(file_data));

    let conn = establish_connection().map_err(|e| e.to_string())?;

    let md5_exists: bool = conn.query_row(
        "SELECT COUNT(*) FROM audio_files WHERE md5 = ?1",
        params![file_md5],
        |row| row.get::<_, i64>(0).map(|count| count > 0)
    ).map_err(|e| e.to_string())?;

    if md5_exists {
        return Err(format!("音频文件 [{}] 已存在于库中，请勿重复导入！", original_name));
    }
    
    let uuid = Uuid::new_v4().to_string();
    let dest_filename = format!("{}.{}", uuid, ext);
    let dest_relative_path = format!("files/{}", dest_filename);
    let dest_absolute_path = get_files_dir().join(&dest_filename);
    
    fs::copy(src_path, &dest_absolute_path).map_err(|e| e.to_string())?;
    
    let artist_opt = if artist.trim().is_empty() || artist == "未知歌手" { None } else { Some(artist.trim().to_string()) };
    let song_id: String = match &artist_opt {
        None => {
            let id_opt: Option<String> = conn.query_row(
                "SELECT id FROM songs WHERE title = ?1 AND artist IS NULL",
                params![title.trim()],
                |row| row.get(0)
            ).optional().map_err(|e| e.to_string())?;
            id_opt
        },
        Some(art) => {
            let id_opt: Option<String> = conn.query_row(
                "SELECT id FROM songs WHERE title = ?1 AND artist = ?2",
                params![title.trim(), art],
                |row| row.get(0)
            ).optional().map_err(|e| e.to_string())?;
            id_opt
        }
    }.unwrap_or_else(|| {
        let new_id = Uuid::new_v4().to_string();
        conn.execute(
            "INSERT INTO songs (id, title, artist) VALUES (?1, ?2, ?3)",
            params![new_id, title.trim(), artist_opt]
        ).unwrap();
        new_id
    });

    let version_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM audio_files WHERE song_id = ?1",
        params![song_id],
        |row| row.get(0)
    ).map_err(|e| e.to_string())?;
    let is_primary = if version_count == 0 { 1 } else { 0 };
    
    let version_id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO audio_files (id, song_id, filepath, original_name, format, bitrate, sample_rate, duration, file_size, is_enabled, is_primary, md5, bit_depth) 
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 1, ?10, ?11, ?12)",
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
            is_primary,
            file_md5,
            bit_depth
        ]
    ).map_err(|e| e.to_string())?;
    
    Ok(())
}

pub fn import_audio_version_for_song(song_id: String, filepath: String) -> Result<AudioVersion, String> {
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

    let file_size = src_path.metadata().map_err(|e| e.to_string())?.len() as i64;
    
    let tagged_file = Probe::open(src_path)
        .map_err(|e| format!("Failed to open file probe: {}", e))?
        .read()
        .map_err(|e| format!("Failed to read metadata: {}", e))?;
        
    let properties = tagged_file.properties();
    let duration = properties.duration().as_secs_f64();
    let bitrate = properties.audio_bitrate().map(|b| (b * 1000) as i32);
    let sample_rate = properties.sample_rate().map(|s| s as i32);
    let bit_depth = properties.bit_depth().map(|d| d as i32);
    
    let file_data = fs::read(src_path).map_err(|e| e.to_string())?;
    let file_md5 = format!("{:x}", md5::compute(file_data));

    let conn = establish_connection().map_err(|e| e.to_string())?;

    let md5_exists: bool = conn.query_row(
        "SELECT COUNT(*) FROM audio_files WHERE md5 = ?1",
        params![file_md5],
        |row| row.get::<_, i64>(0).map(|count| count > 0)
    ).map_err(|e| e.to_string())?;

    if md5_exists {
        return Err(format!("该音频文件已存在于库中，请勿重复导入！"));
    }
    
    let uuid = Uuid::new_v4().to_string();
    let dest_filename = format!("{}.{}", uuid, ext);
    let dest_relative_path = format!("files/{}", dest_filename);
    let dest_absolute_path = get_files_dir().join(&dest_filename);
    
    fs::copy(src_path, &dest_absolute_path).map_err(|e| e.to_string())?;
    
    let version_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM audio_files WHERE song_id = ?1",
        params![song_id],
        |row| row.get(0)
    ).map_err(|e| e.to_string())?;
    let is_primary = if version_count == 0 { 1 } else { 0 };
    
    let version_id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO audio_files (id, song_id, filepath, original_name, format, bitrate, sample_rate, duration, file_size, is_enabled, is_primary, md5, bit_depth) 
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 1, ?10, ?11, ?12)",
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
            is_primary,
            file_md5,
            bit_depth
        ]
    ).map_err(|e| e.to_string())?;
    
    Ok(AudioVersion {
        id: version_id,
        song_id,
        filepath: dest_relative_path,
        original_name,
        format: Some(ext),
        bitrate,
        sample_rate,
        duration,
        file_size,
        is_enabled: true,
        is_primary: is_primary != 0,
        md5: Some(file_md5),
        bit_depth,
    })
}

pub fn update_version_status(version_id: String, is_enabled: bool, is_primary: bool) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let is_enabled_int = if is_enabled { 1 } else { 0 };
    
    conn.execute(
        "UPDATE audio_files SET is_enabled = ?1 WHERE id = ?2",
        params![is_enabled_int, version_id]
    ).map_err(|e| e.to_string())?;
    
    if is_primary {
        let song_id: String = conn.query_row(
            "SELECT song_id FROM audio_files WHERE id = ?1",
            params![version_id],
            |row| row.get(0)
        ).map_err(|e| e.to_string())?;
        
        conn.execute(
            "UPDATE audio_files SET is_primary = 0 WHERE song_id = ?1",
            params![song_id]
        ).map_err(|e| e.to_string())?;
        
        conn.execute(
            "UPDATE audio_files SET is_primary = 1 WHERE id = ?1",
            params![version_id]
        ).map_err(|e| e.to_string())?;
    }
    
    Ok(())
}

pub fn update_song_metadata(song_id: String, title: String, artist: String) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let artist_val = if artist.trim().is_empty() || artist.trim() == "未知歌手" {
        None
    } else {
        Some(artist.trim().to_string())
    };
    conn.execute(
        "UPDATE songs SET title = ?1, artist = ?2 WHERE id = ?3",
        params![title.trim(), artist_val, song_id]
    ).map_err(|e| e.to_string())?;
    Ok(())
}

pub fn delete_song(song_id: String) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    
    let mut stmt = conn.prepare("SELECT filepath FROM audio_files WHERE song_id = ?1").map_err(|e| e.to_string())?;
    let rows = stmt.query_map(params![song_id], |row| row.get::<_, String>(0)).map_err(|e| e.to_string())?;
    let files_dir = get_library_dir();
    for filepath_res in rows {
        if let Ok(filepath) = filepath_res {
            let absolute_path = files_dir.join(filepath);
            if absolute_path.exists() {
                let _ = fs::remove_file(absolute_path);
            }
        }
    }
    
    conn.execute("DELETE FROM songs WHERE id = ?1", params![song_id]).map_err(|e| e.to_string())?;
    Ok(())
}

pub fn delete_audio_version(version_id: String) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    
    let (song_id, is_primary): (String, i32) = conn.query_row(
        "SELECT song_id, is_primary FROM audio_files WHERE id = ?1",
        params![version_id],
        |row| Ok((row.get(0)?, row.get(1)?))
    ).map_err(|e| e.to_string())?;

    let filepath: String = conn.query_row(
        "SELECT filepath FROM audio_files WHERE id = ?1",
        params![version_id],
        |row| row.get(0)
    ).map_err(|e| e.to_string())?;
    
    let absolute_path = get_library_dir().join(filepath);
    if absolute_path.exists() {
        let _ = fs::remove_file(absolute_path);
    }
    
    conn.execute("DELETE FROM audio_files WHERE id = ?1", params![version_id]).map_err(|e| e.to_string())?;

    if is_primary != 0 {
        let next_primary_id: Option<String> = conn.query_row(
            "SELECT id FROM audio_files WHERE song_id = ?1 AND is_enabled = 1 LIMIT 1",
            params![song_id],
            |row| row.get(0)
        ).optional().map_err(|e| e.to_string())?;
        
        let target_id = match next_primary_id {
            Some(id) => Some(id),
            None => conn.query_row(
                "SELECT id FROM audio_files WHERE song_id = ?1 LIMIT 1",
                params![song_id],
                |row| row.get(0)
            ).optional().map_err(|e| e.to_string())?
        };
        
        if let Some(tid) = target_id {
            conn.execute(
                "UPDATE audio_files SET is_primary = 1 WHERE id = ?1",
                params![tid]
            ).map_err(|e| e.to_string())?;
        }
    }
    
    Ok(())
}

pub fn verify_audio_file(filepath: String) -> bool {
    let lib_dir = get_library_dir();
    let file_path = lib_dir.join(&filepath);
    file_path.exists() && file_path.is_file()
}

pub fn add_tag(name: String, color: Option<String>, category: Option<String>) -> Result<Tag, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    conn.execute(
        "INSERT INTO tags (name, color, category) VALUES (?1, ?2, ?3)",
        params![name, color, category]
    ).map_err(|e| e.to_string())?;
    
    let last_id = conn.last_insert_rowid();
    Ok(Tag {
        id: last_id,
        name,
        color,
        category,
    })
}

pub fn delete_tag(tag_id: i64) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    conn.execute("DELETE FROM tags WHERE id = ?1", params![tag_id]).map_err(|e| e.to_string())?;
    Ok(())
}

pub fn tag_song(song_id: String, tag_id: i64, bind: bool) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    if bind {
        conn.execute(
            "INSERT OR IGNORE INTO song_tags (song_id, tag_id) VALUES (?1, ?2)",
            params![song_id, tag_id]
        ).map_err(|e| e.to_string())?;
    } else {
        conn.execute(
            "DELETE FROM song_tags WHERE song_id = ?1 AND tag_id = ?2",
            params![song_id, tag_id]
        ).map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub fn create_playlist(name: String) -> Result<Playlist, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO playlists (id, name, description) VALUES (?1, ?2, '')",
        params![id, name]
    ).map_err(|e| e.to_string())?;
    
    let mut stmt = conn.prepare(
        "SELECT id, name, description, created_at FROM playlists WHERE id = ?1"
    ).map_err(|e| e.to_string())?;
    let playlist = stmt.query_row(params![id], |row| {
        Ok(Playlist {
            id: row.get(0)?,
            name: row.get(1)?,
            description: row.get(2)?,
            created_at: row.get(3)?,
        })
    }).map_err(|e| e.to_string())?;
    Ok(playlist)
}

pub fn delete_playlist(id: String) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    conn.execute("DELETE FROM playlists WHERE id = ?1", params![id]).map_err(|e| e.to_string())?;
    Ok(())
}

pub fn rename_playlist(id: String, name: String) -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    conn.execute("UPDATE playlists SET name = ?1 WHERE id = ?2", params![name, id]).map_err(|e| e.to_string())?;
    Ok(())
}

pub fn add_songs_to_playlist(playlist_id: String, song_ids: Vec<String>) -> Result<(), String> {
    let mut conn = establish_connection().map_err(|e| e.to_string())?;
    let tx = conn.transaction().map_err(|e| e.to_string())?;
    
    let max_sort_order: i32 = tx.query_row(
        "SELECT COALESCE(MAX(sort_order), -1) FROM playlist_songs WHERE playlist_id = ?1",
        params![playlist_id],
        |row| row.get(0)
    ).map_err(|e| e.to_string())?;
    
    let mut current_order = max_sort_order + 1;
    for song_id in song_ids {
        let exists: i64 = tx.query_row(
            "SELECT COUNT(*) FROM playlist_songs WHERE playlist_id = ?1 AND song_id = ?2",
            params![playlist_id, song_id],
            |row| row.get(0)
        ).map_err(|e| e.to_string())?;
        if exists == 0 {
            tx.execute(
                "INSERT INTO playlist_songs (playlist_id, song_id, sort_order) VALUES (?1, ?2, ?3)",
                params![playlist_id, song_id, current_order]
            ).map_err(|e| e.to_string())?;
            current_order += 1;
        }
    }
    tx.commit().map_err(|e| e.to_string())?;
    Ok(())
}

pub fn remove_songs_from_playlist(playlist_id: String, song_ids: Vec<String>) -> Result<(), String> {
    let mut conn = establish_connection().map_err(|e| e.to_string())?;
    let tx = conn.transaction().map_err(|e| e.to_string())?;
    for song_id in song_ids {
        tx.execute(
            "DELETE FROM playlist_songs WHERE playlist_id = ?1 AND song_id = ?2",
            params![playlist_id, song_id]
        ).map_err(|e| e.to_string())?;
    }
    tx.commit().map_err(|e| e.to_string())?;
    Ok(())
}

pub fn get_playlist_songs(playlist_id: String) -> Result<Vec<String>, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    let mut stmt = conn.prepare(
        "SELECT song_id FROM playlist_songs WHERE playlist_id = ?1 ORDER BY sort_order ASC"
    ).map_err(|e| e.to_string())?;
    let rows = stmt.query_map(params![playlist_id], |row| row.get::<_, String>(0)).map_err(|e| e.to_string())?;
    let mut song_ids = Vec::new();
    for r in rows {
        song_ids.push(r.map_err(|e| e.to_string())?);
    }
    Ok(song_ids)
}

fn scan_directory(dir: &Path, files: &mut Vec<std::path::PathBuf>) {
    if dir.is_dir() {
        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    scan_directory(&path, files);
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
    }
}

pub fn scan_directory_for_preview(dir_path: String) -> Result<Vec<String>, String> {
    let path = Path::new(&dir_path);
    if !path.is_dir() {
        return Err("Not a directory".to_string());
    }
    let mut files = Vec::new();
    scan_directory(path, &mut files);
    let list = files.into_iter().map(|f| f.to_string_lossy().to_string()).collect();
    Ok(list)
}

pub fn preview_audio_metadata(filepaths: Vec<String>) -> Result<Vec<PreviewInfo>, String> {
    let mut list = Vec::new();
    for fp in filepaths {
        let path = Path::new(&fp);
        let filename = path.file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        
        let mut title = path.file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        let mut artist = "未知歌手".to_string();
        
        if let Ok(tagged_file) = Probe::open(path).and_then(|p| p.read()) {
            if let Some(primary_tag) = tagged_file.primary_tag() {
                if let Some(t) = primary_tag.title() {
                    title = t.to_string();
                }
                if let Some(a) = primary_tag.artist() {
                    artist = a.to_string();
                }
            }
        }
        
        list.push(PreviewInfo {
            filepath: fp,
            filename,
            title,
            artist,
        });
    }
    Ok(list)
}

pub fn reset_library() -> Result<(), String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    
    let files_dir = get_files_dir();
    if files_dir.exists() {
        let _ = fs::remove_dir_all(&files_dir);
        let _ = fs::create_dir_all(&files_dir);
    }
    
    let tables = ["songs", "audio_files", "tags", "song_tags", "playlists", "playlist_songs"];
    for table in tables {
        let _ = conn.execute(&format!("DELETE FROM {}", table), []);
    }
    
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
        let _ = conn.execute(
            "INSERT INTO tags (name, color, category) VALUES (?1, ?2, ?3)",
            params![name, color, category],
        );
    }
    
    Ok(())
}

pub fn export_audio_file(version_id: String, dest_path: String) -> Result<String, String> {
    let conn = establish_connection().map_err(|e| e.to_string())?;
    
    let (filepath, original_name): (String, String) = conn.query_row(
        "SELECT filepath, original_name FROM audio_files WHERE id = ?1",
        params![version_id],
        |row| Ok((row.get(0)?, row.get(1)?))
    ).map_err(|e| e.to_string())?;
    
    let src_absolute = get_library_dir().join(&filepath);
    if !src_absolute.exists() {
        return Err("Source file not found in library".to_string());
    }
    
    let dest_path_obj = Path::new(&dest_path);
    let dest_absolute = if dest_path_obj.is_dir() {
        dest_path_obj.join(&original_name)
    } else {
        dest_path_obj.to_path_buf()
    };
    
    fs::copy(src_absolute, &dest_absolute).map_err(|e| e.to_string())?;
    
    Ok(dest_absolute.to_string_lossy().to_string())
}
