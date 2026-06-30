use tauri::Manager;

mod db;
mod commands;
mod audio_server;

#[tauri::command]
fn get_audio_server_port() -> u16 {
    audio_server::get_port()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            #[cfg(any(target_os = "android", target_os = "ios"))]
            {
                let path = db::load_library_path(app.handle()).unwrap_or_else(|| {
                    let default_path = app.handle().path().app_local_data_dir()
                        .expect("Failed to get local data dir")
                        .join("library");
                    std::fs::create_dir_all(&default_path).ok();
                    db::save_library_path(app.handle(), default_path.clone()).ok();
                    default_path
                });
                db::set_library_dir(path.clone());
                if let Err(e) = db::init_db() {
                    eprintln!("Failed to init DB during setup: {}", e);
                } else {
                    let files_dir = db::get_files_dir();
                    let _ = app.asset_protocol_scope().allow_directory(&files_dir, true);
                }
                // Start local HTTP audio streaming server for Android
                audio_server::start();
            }

            #[cfg(not(any(target_os = "android", target_os = "ios")))]
            {
                if let Some(path) = db::load_library_path(app.handle()) {
                    db::set_library_dir(path.clone());
                    if let Err(e) = db::init_db() {
                        eprintln!("Failed to init DB during setup: {}", e);
                    } else {
                        let files_dir = db::get_files_dir();
                        if let Err(e) = app.asset_protocol_scope().allow_directory(&files_dir, true) {
                            eprintln!("Failed to allow asset directory: {}", e);
                        }
                    }
                }
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::list_directories,
            commands::list_contents,
            commands::is_library_initialized,
            commands::initialize_library_path,
            commands::get_songs,
            commands::import_song,
            commands::import_audio_files,
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
            commands::get_playlist_songs,
            commands::verify_audio_file,
            commands::delete_song,
            commands::delete_audio_version,
            commands::reset_library,
            commands::import_audio_version_for_song,
            commands::preview_audio_metadata,
            commands::import_song_with_metadata,
            commands::update_song_metadata,
            commands::scan_directory_for_preview,
            commands::read_audio_file_base64,
            get_audio_server_port
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

