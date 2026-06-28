use tauri::Manager;

mod db;
mod commands;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            // 1. 初始化数据库及存储文件夹
            db::init_db()?;

            // 2. 动态允许前端通过 asset:// 协议读取托管音乐文件
            let files_dir = db::get_files_dir();
            app.asset_protocol_scope().allow_directory(&files_dir, true)?;

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_songs,
            commands::import_song,
            commands::export_song,
            commands::update_version_status,
            commands::get_tags,
            commands::add_tag,
            commands::delete_tag,
            commands::tag_song,
            commands::get_library_path,
            commands::select_audio_files,
            commands::select_export_directory,
            commands::select_directory,
            commands::select_save_file,
            commands::get_playlists,
            commands::create_playlist,
            commands::delete_playlist,
            commands::rename_playlist,
            commands::add_songs_to_playlist,
            commands::remove_songs_from_playlist,
            commands::get_playlist_songs
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

