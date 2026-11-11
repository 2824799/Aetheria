use super::test_support::TestLibrary;
use super::{import, lyrics, maintenance, paths, playlists, songs, tags};
use crate::audio::test_support::TestWav;
use crate::database::connection;
use rusqlite::params;
use std::fs;
use std::path::{Path, PathBuf};

/// A short stereo WAV whose contents (and therefore MD5) depend on `seed`.
fn wav(seed: i32) -> TestWav {
    let samples: Vec<i32> = (0..4_410).map(|i| (i * seed) % 8_000).collect();
    TestWav::pcm(44_100, 2, 16, &samples)
}

fn managed_files() -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = fs::read_dir(paths::files_dir())
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .collect();
    files.sort();
    files
}

fn new_lyric(song_id: &str, version_id: Option<&str>, content: &str) -> lyrics::NewLyric {
    lyrics::NewLyric {
        song_id: song_id.to_string(),
        audio_version_id: version_id.map(str::to_string),
        source: "manual".to_string(),
        source_id: None,
        title: " Title ".to_string(),
        artist: Some("  ".to_string()),
        content: content.to_string(),
        translation: None,
        romanized: None,
        offset_ms: 0,
    }
}

#[test]
fn import_registers_a_song_with_one_primary_version() {
    let _library = TestLibrary::new();
    let source = wav(3);

    let song = import::import_song(source.path()).unwrap();

    let stem = Path::new(source.path()).file_stem().unwrap();
    assert_eq!(song.title, stem.to_string_lossy());
    assert_eq!(song.artist, None);
    assert_eq!(song.versions.len(), 1);
    let version = &song.versions[0];
    assert!(version.is_primary && version.is_enabled);
    assert_eq!(version.format.as_deref(), Some("wav"));
    assert_eq!(version.sample_rate, Some(44_100));
    assert!((version.duration - 0.05).abs() < 0.001);
    assert!(version.md5.is_some());
    assert!(version.loudness.is_some());
    assert!(paths::audio_file(&version.filepath).unwrap().is_file());

    let listed = songs::all().unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].versions[0].id, version.id);
}

#[test]
fn duplicate_import_is_rejected_without_leaving_a_copy() {
    let _library = TestLibrary::new();
    let source = wav(3);
    import::import_song(source.path()).unwrap();

    let error = import::import_song(source.path()).unwrap_err();

    assert!(error.to_string().contains("请勿重复导入"));
    assert_eq!(managed_files().len(), 1);
    assert_eq!(songs::all().unwrap().len(), 1);
}

#[test]
fn importing_into_a_missing_song_fails_cleanly() {
    let _library = TestLibrary::new();
    let source = wav(3);

    let error = import::import_version("no-such-song", source.path()).unwrap_err();

    assert_eq!(error.to_string(), "歌曲不存在。");
    assert!(managed_files().is_empty());
}

#[test]
fn files_with_the_same_title_and_artist_become_versions_of_one_song() {
    let _library = TestLibrary::new();
    let (first, second, third) = (wav(3), wav(5), wav(7));

    import::import_song_with_metadata(first.path(), " 晴天 ", "未知歌手").unwrap();
    import::import_song_with_metadata(second.path(), "晴天", "  ").unwrap();
    import::import_song_with_metadata(third.path(), "晴天", "周杰伦").unwrap();

    let all = songs::all().unwrap();
    assert_eq!(all.len(), 2);
    let unknown = all.iter().find(|song| song.artist.is_none()).unwrap();
    assert_eq!(unknown.title, "晴天");
    let primary: Vec<bool> = unknown.versions.iter().map(|v| v.is_primary).collect();
    assert_eq!(primary, [true, false]);
    let known = all.iter().find(|song| song.artist.is_some()).unwrap();
    assert_eq!(known.artist.as_deref(), Some("周杰伦"));
}

#[test]
fn sidecar_lyrics_follow_the_audio_file() {
    let _library = TestLibrary::new();
    let source = wav(3);
    let sidecar = Path::new(source.path()).with_extension("lrc");
    fs::write(&sidecar, "[00:01.00]hello\n").unwrap();

    let song = import::import_song(source.path()).unwrap();
    fs::remove_file(&sidecar).unwrap();

    let candidates = lyrics::local_candidates(&song.id, None).unwrap();
    assert_eq!(candidates.len(), 1);
    assert_eq!(candidates[0].source, "local_lrc");
    assert_eq!(candidates[0].content, "[00:01.00]hello");

    songs::delete(&song.id).unwrap();
    assert!(managed_files().is_empty());
}

#[test]
fn deleting_the_primary_version_promotes_the_oldest_remaining_one() {
    let _library = TestLibrary::new();
    let (first, second, third) = (wav(3), wav(5), wav(7));
    let song = import::import_song(first.path()).unwrap();
    let second = import::import_version(&song.id, second.path()).unwrap();
    let third = import::import_version(&song.id, third.path()).unwrap();
    assert!(!second.is_primary && !third.is_primary);

    songs::set_primary_version(&third.id).unwrap();
    let versions = songs::all().unwrap().remove(0).versions;
    let primary: Vec<&str> = versions
        .iter()
        .filter(|v| v.is_primary)
        .map(|v| v.id.as_str())
        .collect();
    assert_eq!(primary, [third.id.as_str()]);

    songs::delete_version(&third.id).unwrap();
    let versions = songs::all().unwrap().remove(0).versions;
    assert_eq!(versions.len(), 2);
    assert!(versions[0].is_primary && !versions[1].is_primary);
    assert!(!paths::audio_file(&third.filepath).unwrap().exists());
    assert_eq!(managed_files().len(), 2);
}

#[test]
fn deleting_a_song_removes_its_rows_and_files() {
    let _library = TestLibrary::new();
    let (first, second) = (wav(3), wav(5));
    let song = import::import_song(first.path()).unwrap();
    let keep = import::import_song_with_metadata(second.path(), "keep", "");
    keep.unwrap();
    let tag = tags::add("live", None, None).unwrap();
    tags::tag_song(&song.id, tag.id, true).unwrap();
    let playlist = playlists::create("mix").unwrap();
    playlists::add_songs(&playlist.id, &[song.id.clone()]).unwrap();
    lyrics::save(new_lyric(&song.id, None, "[00:01.00]la")).unwrap();

    songs::delete(&song.id).unwrap();

    let remaining = songs::all().unwrap();
    assert_eq!(remaining.len(), 1);
    assert_eq!(remaining[0].title, "keep");
    assert_eq!(managed_files().len(), 1);
    assert!(playlists::song_ids(&playlist.id).unwrap().is_empty());
    assert!(lyrics::song_ids_with_lyrics().unwrap().is_empty());
    assert_eq!(
        songs::delete_version("gone").unwrap_err().to_string(),
        "音源版本不存在。"
    );
}

#[test]
fn stored_paths_from_a_synced_database_cannot_reach_outside_the_library() {
    let library = TestLibrary::new();
    let source = wav(3);
    let song = import::import_song(source.path()).unwrap();
    let outside = library.scratch_dir().join("outside.wav");
    fs::write(&outside, b"precious").unwrap();
    let hostile = outside.to_string_lossy().into_owned();
    let conn = connection::open().unwrap();
    conn.execute(
        "UPDATE audio_files SET filepath = ?1 WHERE song_id = ?2",
        params![hostile, song.id],
    )
    .unwrap();
    conn.execute(
        "UPDATE songs SET cover_path = ?1 WHERE id = ?2",
        params![hostile, song.id],
    )
    .unwrap();

    let export_dir = library.scratch_dir().join("export");
    fs::create_dir_all(&export_dir).unwrap();
    let exported = maintenance::export_version(&song.versions[0].id, &export_dir.to_string_lossy());
    assert!(exported.is_err());
    songs::delete(&song.id).unwrap();

    assert_eq!(fs::read(&outside).unwrap(), b"precious");
}

#[test]
fn saving_a_lyric_replaces_the_previous_one_in_its_scope() {
    let _library = TestLibrary::new();
    let (first, second) = (wav(3), wav(5));
    let song = import::import_song(first.path()).unwrap();
    let primary = &song.versions[0];
    let other = import::import_version(&song.id, second.path()).unwrap();

    lyrics::save(new_lyric(&song.id, None, "[00:01.00]song wide")).unwrap();
    lyrics::save(new_lyric(&song.id, Some(&primary.id), "[00:01.00]old")).unwrap();
    let saved = lyrics::save(new_lyric(&song.id, Some(&primary.id), "[00:01.00]new")).unwrap();
    assert_eq!(saved.title, "Title");
    assert_eq!(saved.artist, None);
    assert!(saved.is_selected);

    let row_count: i64 = connection::open()
        .unwrap()
        .query_row("SELECT COUNT(*) FROM lyrics", [], |row| row.get(0))
        .unwrap();
    assert_eq!(row_count, 2);
    let for_primary = lyrics::selected(&song.id, Some(&primary.id))
        .unwrap()
        .unwrap();
    assert_eq!(for_primary.content, "[00:01.00]new");
    let for_other = lyrics::selected(&song.id, Some(&other.id))
        .unwrap()
        .unwrap();
    assert_eq!(for_other.content, "[00:01.00]song wide");

    let updated = lyrics::update_offset(&saved.id, -250).unwrap();
    assert_eq!(updated.offset_ms, -250);
    assert!(lyrics::update_offset("gone", 1).is_err());
    assert!(lyrics::save(new_lyric(&song.id, None, " \n[kana:1]\n")).is_err());
    assert!(lyrics::save(new_lyric(&song.id, Some("foreign"), "x")).is_err());
    assert!(lyrics::save(new_lyric("gone", None, "x")).is_err());
}

#[test]
fn clearing_lyrics_reports_whether_other_versions_still_have_some() {
    let _library = TestLibrary::new();
    let (first, second) = (wav(3), wav(5));
    let song = import::import_song(first.path()).unwrap();
    let primary = &song.versions[0];
    let other = import::import_version(&song.id, second.path()).unwrap();
    lyrics::save(new_lyric(&song.id, None, "[00:01.00]song wide")).unwrap();
    lyrics::save(new_lyric(&song.id, Some(&primary.id), "[00:01.00]primary")).unwrap();
    lyrics::save(new_lyric(&song.id, Some(&other.id), "[00:01.00]other")).unwrap();
    assert_eq!(lyrics::song_ids_with_lyrics().unwrap(), [song.id.clone()]);

    assert!(lyrics::clear(&song.id, Some(&primary.id)).unwrap());
    assert!(lyrics::selected(&song.id, Some(&primary.id))
        .unwrap()
        .is_none());
    assert!(lyrics::selected(&song.id, Some(&other.id))
        .unwrap()
        .is_some());

    assert!(!lyrics::clear(&song.id, None).unwrap());
    assert!(lyrics::song_ids_with_lyrics().unwrap().is_empty());
}

#[test]
fn playlists_keep_insertion_order_and_skip_duplicates() {
    let _library = TestLibrary::new();
    let (first, second, third) = (wav(3), wav(5), wav(7));
    let a = import::import_song(first.path()).unwrap().id;
    let b = import::import_song(second.path()).unwrap().id;
    let c = import::import_song(third.path()).unwrap().id;
    let playlist = playlists::create(" mix ").unwrap();
    assert_eq!(playlist.name, "mix");

    playlists::add_songs(&playlist.id, &[b.clone(), a.clone()]).unwrap();
    playlists::add_songs(&playlist.id, &[a.clone(), c.clone(), b.clone()]).unwrap();
    assert_eq!(
        playlists::song_ids(&playlist.id).unwrap(),
        [b.clone(), a.clone(), c.clone()]
    );

    playlists::remove_songs(&playlist.id, &[a]).unwrap();
    assert_eq!(playlists::song_ids(&playlist.id).unwrap(), [b, c]);

    assert_eq!(
        playlists::create("mix").unwrap_err().to_string(),
        "歌单名称已存在。"
    );
    assert!(playlists::create("  ").is_err());
    playlists::rename(&playlist.id, "renamed").unwrap();
    playlists::delete(&playlist.id).unwrap();
    assert!(playlists::all().unwrap().is_empty());
}

#[test]
fn tags_reject_duplicates_and_bind_to_songs() {
    let _library = TestLibrary::new();
    let source = wav(3);
    let song = import::import_song(source.path()).unwrap();
    let default_count = tags::all().unwrap().len();
    assert_eq!(default_count, 11);

    let tag = tags::add(" live ", Some("#ffffff".into()), None).unwrap();
    assert_eq!(tag.name, "live");
    assert_eq!(
        tags::add("live", None, None).unwrap_err().to_string(),
        "标签名称已存在。"
    );
    assert!(tags::add(" ", None, None).is_err());

    tags::tag_song(&song.id, tag.id, true).unwrap();
    tags::tag_song(&song.id, tag.id, true).unwrap();
    assert_eq!(songs::all().unwrap()[0].tags.len(), 1);
    tags::update(tag.id, "concert", None, Some("scene".into())).unwrap();
    assert_eq!(songs::all().unwrap()[0].tags[0].name, "concert");

    tags::delete(tag.id).unwrap();
    assert!(songs::all().unwrap()[0].tags.is_empty());
    assert_eq!(tags::all().unwrap().len(), default_count);
}

#[test]
fn reset_empties_the_library_and_restores_default_tags() {
    let _library = TestLibrary::new();
    let source = wav(3);
    import::import_song(source.path()).unwrap();
    fs::write(paths::covers_dir().join("stale.jpg"), b"x").unwrap();
    for tag in tags::all().unwrap() {
        tags::delete(tag.id).unwrap();
    }
    tags::add("custom", None, None).unwrap();
    playlists::create("mix").unwrap();

    maintenance::reset().unwrap();

    assert!(songs::all().unwrap().is_empty());
    assert!(playlists::all().unwrap().is_empty());
    assert!(managed_files().is_empty());
    assert!(!paths::covers_dir().join("stale.jpg").exists());
    let names: Vec<String> = tags::all().unwrap().into_iter().map(|t| t.name).collect();
    assert_eq!(names.len(), 11);
    assert!(!names.contains(&"custom".to_string()));
    // The same file can be imported again after a reset.
    import::import_song(source.path()).unwrap();
}

#[test]
fn refresh_and_export_work_on_managed_files() {
    let library = TestLibrary::new();
    let source = wav(3);
    let song = import::import_song(source.path()).unwrap();
    let version = &song.versions[0];
    assert!(!version.metadata_scanned);

    maintenance::refresh_metadata(&version.id).unwrap();
    let refreshed = songs::all().unwrap().remove(0).versions.remove(0);
    assert!(refreshed.metadata_scanned);
    assert!((refreshed.duration - version.duration).abs() < 1e-9);
    assert!(refreshed.loudness.is_some());

    let export_dir = library.scratch_dir();
    let exported = maintenance::export_version(&version.id, &export_dir.to_string_lossy()).unwrap();
    assert_eq!(
        Path::new(&exported),
        export_dir.join(&version.original_name)
    );
    assert_eq!(
        fs::read(&exported).unwrap(),
        fs::read(source.path()).unwrap()
    );

    assert!(maintenance::refresh_metadata("gone").is_err());
}

#[test]
fn metadata_edits_validate_and_normalize() {
    let _library = TestLibrary::new();
    let source = wav(3);
    let song = import::import_song(source.path()).unwrap();

    songs::update_metadata(&song.id, " New ", " Someone ").unwrap();
    let updated = songs::all().unwrap().remove(0);
    assert_eq!(updated.title, "New");
    assert_eq!(updated.artist.as_deref(), Some("Someone"));

    songs::update_metadata(&song.id, "New", "未知歌手").unwrap();
    assert_eq!(songs::all().unwrap()[0].artist, None);
    assert!(songs::update_metadata(&song.id, "  ", "x").is_err());
    assert!(songs::update_metadata("gone", "x", "x").is_err());
}

#[test]
fn directory_scan_finds_nested_audio_and_survives_symlink_cycles() {
    let library = TestLibrary::new();
    let root = library.scratch_dir().join("music");
    let nested = root.join("album");
    fs::create_dir_all(&nested).unwrap();
    fs::write(root.join("a.MP3"), b"").unwrap();
    fs::write(nested.join("b.flac"), b"").unwrap();
    fs::write(nested.join("cover.jpg"), b"").unwrap();
    fs::write(nested.join("noext"), b"").unwrap();
    #[cfg(unix)]
    std::os::unix::fs::symlink(&root, nested.join("loop")).unwrap();

    let found = import::scan_directory(&root.to_string_lossy()).unwrap();

    let names: Vec<String> = found
        .iter()
        .map(|path| {
            Path::new(path)
                .file_name()
                .unwrap()
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    assert_eq!(names, ["a.MP3", "b.flac"]);
    assert!(import::scan_directory(&root.join("a.MP3").to_string_lossy()).is_err());

    let preview = import::preview_metadata(vec![root.join("a.MP3").to_string_lossy().into_owned()]);
    assert_eq!(preview[0].title, "a");
    assert_eq!(preview[0].artist, "未知歌手");
    assert_eq!(preview[0].filename, "a.MP3");
}

#[test]
fn databases_from_older_builds_gain_the_missing_columns() {
    let library = TestLibrary::new();
    let old_library = library.scratch_dir().join("old-library");
    fs::create_dir_all(&old_library).unwrap();
    let old = rusqlite::Connection::open(old_library.join("database.db")).unwrap();
    old.execute_batch(
        "CREATE TABLE songs (id TEXT PRIMARY KEY, title TEXT NOT NULL, artist TEXT, album TEXT,
             lyrics TEXT, cover_path TEXT, rating INTEGER DEFAULT 0,
             created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
             updated_at DATETIME DEFAULT CURRENT_TIMESTAMP);
         CREATE TABLE audio_files (id TEXT PRIMARY KEY, song_id TEXT NOT NULL,
             filepath TEXT NOT NULL UNIQUE, original_name TEXT NOT NULL, format TEXT,
             bitrate INTEGER, sample_rate INTEGER, duration REAL NOT NULL,
             file_size INTEGER NOT NULL, is_enabled INTEGER DEFAULT 1,
             is_primary INTEGER DEFAULT 0, created_at DATETIME DEFAULT CURRENT_TIMESTAMP);
         INSERT INTO songs (id, title) VALUES ('s1', 'Old song');
         INSERT INTO audio_files (id, song_id, filepath, original_name, duration, file_size,
             is_primary) VALUES ('v1', 's1', 'files/x.mp3', 'x.mp3', 12.5, 10, 1);",
    )
    .unwrap();
    drop(old);

    super::initialize(old_library).unwrap();

    let all = songs::all().unwrap();
    assert_eq!(all.len(), 1);
    let version = &all[0].versions[0];
    assert_eq!(version.md5, None);
    assert_eq!(version.loudness, None);
    assert!(!version.metadata_scanned);
    assert_eq!(tags::all().unwrap().len(), 11);
}
