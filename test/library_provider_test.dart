import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/src/rust/frb_generated.dart';
import 'package:aetheria/src/rust/models/playlist.dart';
import 'package:aetheria/src/rust/models/song.dart';

Song _song(
  String id,
  String title, {
  String? artist,
  List<AudioVersion> versions = const [],
}) {
  return Song(
    id: id,
    title: title,
    artist: artist,
    rating: 0,
    createdAt: '',
    versions: versions,
    tags: const [],
  );
}

AudioVersion _version(String id, String songId, String originalName) {
  return AudioVersion(
    id: id,
    songId: songId,
    filepath: 'files/$id.mp3',
    originalName: originalName,
    duration: 180,
    fileSize: 1024,
    isEnabled: true,
    isPrimary: true,
    metadataScanned: true,
  );
}

class _FakeLibraryApi extends Fake implements RustLibApi {
  final List<Song> dbSongs = [];
  final List<Playlist> dbPlaylists = [];
  final Map<String, List<String>> dbPlaylistSongs = {};
  final List<({String playlistId, List<String> songIds})> addPlaylistCalls = [];
  final Set<String> failingFilepaths = {};
  var _nextSongNumber = 1;
  var _nextVersionNumber = 1;

  void reset() {
    dbSongs.clear();
    dbPlaylists.clear();
    dbPlaylistSongs.clear();
    addPlaylistCalls.clear();
    failingFilepaths.clear();
    _nextSongNumber = 1;
    _nextVersionNumber = 1;
  }

  @override
  bool crateApiMusicIsLibraryInitialized() => true;

  @override
  Future<List<Song>> crateApiMusicGetSongs() async {
    final sorted = List<Song>.of(dbSongs)
      ..sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    return sorted;
  }

  @override
  Future<List<Tag>> crateApiMusicGetTags() async => const [];

  @override
  Future<List<Playlist>> crateApiMusicGetPlaylists() async =>
      List<Playlist>.of(dbPlaylists);

  @override
  Future<String> crateApiMusicGetLibraryPath() async => '/tmp/aetheria';

  @override
  Future<List<String>> crateApiMusicGetSongIdsWithLyrics() async => const [];

  @override
  Future<List<String>> crateApiMusicGetPlaylistSongs({
    required String playlistId,
  }) async {
    return List<String>.of(dbPlaylistSongs[playlistId] ?? const []);
  }

  @override
  Future<Song> crateApiMusicImportSong({required String filepath}) async {
    if (failingFilepaths.contains(filepath)) {
      throw StateError('导入失败: $filepath');
    }
    final name = filepath.replaceAll('\\', '/').split('/').last;
    final stem = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    final songId = 'song-${_nextSongNumber++}';
    final version = _version('ver-${_nextVersionNumber++}', songId, name);
    final song = _song(songId, stem, versions: [version]);
    dbSongs.add(song);
    return song;
  }

  @override
  Future<void> crateApiMusicImportSongWithMetadata({
    required String filepath,
    required String title,
    required String artist,
  }) async {
    if (failingFilepaths.contains(filepath)) {
      throw StateError('导入失败: $filepath');
    }
    final name = filepath.replaceAll('\\', '/').split('/').last;
    final normalizedArtist =
        artist.trim().isEmpty || artist.trim() == '未知歌手'
        ? null
        : artist.trim();
    final effectiveTitle = title.trim().isEmpty
        ? (name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name)
        : title;
    final existingIndex = dbSongs.indexWhere(
      (s) => s.title == effectiveTitle && s.artist == normalizedArtist,
    );
    if (existingIndex >= 0) {
      final existing = dbSongs[existingIndex];
      final version = _version('ver-${_nextVersionNumber++}', existing.id, name);
      dbSongs[existingIndex] = _song(
        existing.id,
        existing.title,
        artist: existing.artist,
        versions: [...existing.versions, version],
      );
      return;
    }
    final songId = 'song-${_nextSongNumber++}';
    final version = _version('ver-${_nextVersionNumber++}', songId, name);
    dbSongs.add(
      _song(
        songId,
        effectiveTitle,
        artist: normalizedArtist,
        versions: [version],
      ),
    );
  }

  @override
  Future<void> crateApiMusicAddSongsToPlaylist({
    required String playlistId,
    required List<String> songIds,
  }) async {
    if (!dbPlaylists.any((p) => p.id == playlistId)) {
      throw StateError('FOREIGN KEY constraint failed');
    }
    addPlaylistCalls.add((playlistId: playlistId, songIds: List.of(songIds)));
    final list = dbPlaylistSongs.putIfAbsent(playlistId, () => []);
    for (final id in songIds) {
      if (!list.contains(id)) {
        list.add(id);
      }
    }
  }

  @override
  Future<void> crateApiMusicDeletePlaylist({required String id}) async {
    dbPlaylists.removeWhere((p) => p.id == id);
    dbPlaylistSongs.remove(id);
  }
}

void main() {
  test('uses Explorer-style natural ordering for non-playlist song lists', () {
    final provider = LibraryProvider()
      ..songs = [
        _song('4', 'Track 10'),
        _song('1', 'Track 2'),
        _song('3', 'Track 02'),
        _song('2', 'track 1'),
        _song('6', 'Same title', artist: 'Artist 10'),
        _song('5', 'Same Title', artist: 'Artist 2'),
      ];

    expect(provider.displaySongs.map((song) => song.id), [
      '5',
      '6',
      '2',
      '1',
      '3',
      '4',
    ]);
  });

  test('reuses filtered results and invalidates them when filters change', () {
    final provider = LibraryProvider()
      ..songs = [_song('1', 'Track 1'), _song('2', 'Track 2')];
    final first = provider.displaySongs;
    expect(identical(provider.displaySongs, first), isTrue);
    expect(() => first.clear(), throwsUnsupportedError);
    provider.setSearchQuery('2');
    expect(provider.displaySongs.map((song) => song.id), ['2']);
    final filtered = provider.displaySongs;
    provider.setSearchQuery('2');
    expect(identical(filtered, provider.displaySongs), isTrue);
    provider.setSearchQuery('');
    expect(provider.displaySongs.map((song) => song.id), ['1', '2']);
    provider.dispose();
  });

  test('playlist filtering skips stale ids while preserving order', () {
    final provider = LibraryProvider()
      ..songs = [_song('1', 'Track 1'), _song('2', 'Track 2')]
      ..activePlaylistId = 'playlist'
      ..playlistSongIds = ['2', 'missing', '1'];
    expect(provider.displaySongs.map((song) => song.id), ['2', '1']);
    provider.setSearchQuery('1');
    expect(provider.displaySongs.map((song) => song.id), ['1']);
    provider.dispose();
  });

  test('preserves manually arranged playlist order', () {
    final provider = LibraryProvider()
      ..songs = [_song('1', 'Track 10'), _song('2', 'Track 2')]
      ..activePlaylistId = 'playlist'
      ..playlistSongIds = ['1', '2'];

    expect(provider.displaySongs.map((song) => song.id), ['1', '2']);
  });

  group('LibraryProvider persistence & import', () {
    final api = _FakeLibraryApi();

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      RustLib.initMock(api: api);
    });
    tearDownAll(RustLib.dispose);
    setUp(() {
      api.reset();
      SharedPreferences.setMockInitialValues({});
    });

    group('importSongs playlist targeting', () {

    test('adds imported files to active playlist by default', () async {
      const favorite = Playlist(id: 'pl-fav', name: '我的最爱', createdAt: '');
      api.dbPlaylists.add(favorite);
      final provider = LibraryProvider();
      addTearDown(provider.dispose);

      await provider.loadLibrary();
      await provider.setActivePlaylist(favorite.id);

      final report = await provider.importSongsWithReport([
        (filepath: '/music/zeta.mp3', title: null, artist: null),
        (filepath: '/music/alpha.flac', title: null, artist: null),
      ]);

      expect(report.failures, isEmpty);
      expect(report.importedCount, 2);
      expect(report.targetPlaylist?.id, favorite.id);
      expect(report.playlistError, isNull);
      expect(api.addPlaylistCalls, hasLength(1));
      expect(api.addPlaylistCalls.single.playlistId, favorite.id);
      // Preserves exact import order in the playlist.
      expect(api.addPlaylistCalls.single.songIds, ['song-1', 'song-2']);
      expect(provider.playlistSongIds, ['song-1', 'song-2']);
      expect(provider.displaySongs.map((s) => s.title), ['zeta', 'alpha']);
    });

    test('does not add to any playlist when All Songs is selected', () async {
      const favorite = Playlist(id: 'pl-fav', name: '我的最爱', createdAt: '');
      api.dbPlaylists.add(favorite);
      final provider = LibraryProvider();
      addTearDown(provider.dispose);

      await provider.loadLibrary();
      expect(provider.activePlaylistId, isNull);

      final report = await provider.importSongsWithReport([
        (filepath: '/music/alone.mp3', title: null, artist: null),
      ]);

      expect(report.failures, isEmpty);
      expect(report.importedCount, 1);
      expect(report.targetPlaylist, isNull);
      expect(report.playlistError, isNull);
      expect(api.addPlaylistCalls, isEmpty);
      expect(provider.displaySongs.map((s) => s.title), ['alone']);
    });

    test(
      'matches folder metadata imports including new versions of existing songs in order',
      () async {
        const playlist = Playlist(id: 'pl-acg', name: 'ACG', createdAt: '');
        api.dbPlaylists.add(playlist);
        api.dbSongs.add(
          _song(
            'existing-song',
            'Existing Song',
            artist: 'Artist',
            versions: [_version('v0', 'existing-song', 'existing.mp3')],
          ),
        );
        api.failingFilepaths.add('/folder/broken.mp3');

        final provider = LibraryProvider();
        addTearDown(provider.dispose);

        await provider.loadLibrary();
        await provider.setActivePlaylist(playlist.id);

        final report = await provider.importSongsWithReport([
          (filepath: '/folder/01_zebra.flac', title: 'Zebra', artist: 'A'),
          (filepath: '/folder/broken.mp3', title: 'Broken', artist: 'B'),
          (
            filepath: '/folder/existing.flac',
            title: 'Existing Song',
            artist: 'Artist',
          ),
          (filepath: '/folder/02_alpha.flac', title: 'Alpha', artist: 'C'),
        ]);

        expect(report.importedCount, 3);
        expect(report.failures, hasLength(1));
        expect(report.targetPlaylist?.id, playlist.id);
        expect(report.playlistError, isNull);
        expect(api.addPlaylistCalls, hasLength(1));
        expect(api.addPlaylistCalls.single.songIds, [
          'song-1',
          'existing-song',
          'song-2',
        ]);
        expect(provider.displaySongs.map((s) => s.title), [
          'Zebra',
          'Existing Song',
          'Alpha',
        ]);
      },
    );

    test('supports overriding or disabling target playlist', () async {
      const pl1 = Playlist(id: 'pl-1', name: '歌单1', createdAt: '');
      const pl2 = Playlist(id: 'pl-2', name: '歌单2', createdAt: '');
      api.dbPlaylists.addAll([pl1, pl2]);

      final provider = LibraryProvider();
      addTearDown(provider.dispose);
      await provider.loadLibrary();
      await provider.setActivePlaylist(pl1.id);

      final overridden = await provider.importSongsWithReport(
        [(filepath: '/music/a.mp3', title: 'A', artist: '')],
        targetPlaylistId: pl2.id,
        addToActivePlaylist: false,
      );
      expect(overridden.targetPlaylist?.id, pl2.id);
      expect(api.dbPlaylistSongs[pl2.id], ['song-1']);
      expect(api.dbPlaylistSongs[pl1.id], isNull);

      final libraryOnly = await provider.importSongsWithReport(
        [(filepath: '/music/b.mp3', title: 'B', artist: '')],
        addToActivePlaylist: false,
      );
      expect(libraryOnly.targetPlaylist, isNull);
      expect(api.dbPlaylistSongs[pl1.id], isNull);
      expect(api.dbPlaylistSongs[pl2.id], ['song-1']);
    });

    test(
      'reports playlistError without corrupting importedCount if target playlist vanished',
      () async {
        const pl1 = Playlist(id: 'pl-gone', name: '消失歌单', createdAt: '');
        api.dbPlaylists.add(pl1);

        final provider = LibraryProvider();
        addTearDown(provider.dispose);
        await provider.loadLibrary();
        await provider.setActivePlaylist(pl1.id);

        // Simulate the playlist being removed externally before import finishes.
        api.dbPlaylists.clear();

        final report = await provider.importSongsWithReport([
          (filepath: '/music/kept.mp3', title: null, artist: null),
        ]);

        expect(report.failures, isEmpty);
        expect(report.importedCount, 1);
        expect(report.targetPlaylist, isNull);
        expect(report.playlistError, isNotNull);
        expect(provider.songs, hasLength(1));
      },
    );
  });

    group('active playlist persistence', () {

    test('restores selected playlist across restarts and clears on All Songs or deletion', () async {
      const pl1 = Playlist(id: 'pl-1', name: '1', createdAt: '');
      const pl2 = Playlist(id: 'pl-2', name: '2', createdAt: '');
      api.dbPlaylists.addAll([pl1, pl2]);
      api.dbSongs.addAll([
        _song('s1', 'Song One'),
        _song('s2', 'Song Two'),
      ]);
      api.dbPlaylistSongs[pl1.id] = ['s2'];

      final firstSession = LibraryProvider();
      addTearDown(firstSession.dispose);
      await firstSession.loadLibrary();
      expect(firstSession.activePlaylistId, isNull);

      await firstSession.setActivePlaylist(pl1.id);
      expect(firstSession.activePlaylistId, pl1.id);
      expect(firstSession.displaySongs.map((s) => s.id), ['s2']);

      // Simulates closing and reopening the app cleanly.
      final restoredSession = LibraryProvider();
      addTearDown(restoredSession.dispose);
      await restoredSession.loadLibrary();
      expect(restoredSession.activePlaylistId, pl1.id);
      expect(restoredSession.activePlaylist?.id, pl1.id);
      expect(restoredSession.playlistSongIds, ['s2']);
      expect(restoredSession.displaySongs.map((s) => s.id), ['s2']);

      // Selecting All Songs persists null across future launches.
      await restoredSession.setActivePlaylist(null);
      final allSongsSession = LibraryProvider();
      addTearDown(allSongsSession.dispose);
      await allSongsSession.loadLibrary();
      expect(allSongsSession.activePlaylistId, isNull);
      expect(allSongsSession.displaySongs.map((s) => s.id), ['s1', 's2']);

      // Deleting the active playlist clears the persisted selection too.
      await allSongsSession.setActivePlaylist(pl2.id);
      await allSongsSession.deletePlaylist(pl2.id);
      expect(allSongsSession.activePlaylistId, isNull);
      final afterDeleteSession = LibraryProvider();
      addTearDown(afterDeleteSession.dispose);
      await afterDeleteSession.loadLibrary();
      expect(afterDeleteSession.activePlaylistId, isNull);
    });

    test('falls back to All Songs when persisted playlist no longer exists', () async {
      const pl1 = Playlist(id: 'pl-1', name: '1', createdAt: '');
      api.dbPlaylists.add(pl1);
      api.dbSongs.add(_song('s1', 'Song One'));

      final firstSession = LibraryProvider();
      addTearDown(firstSession.dispose);
      await firstSession.loadLibrary();
      await firstSession.setActivePlaylist(pl1.id);

      // Playlist vanished externally (e.g., library reset or LAN sync).
      api.dbPlaylists.clear();

      final reopened = LibraryProvider();
      addTearDown(reopened.dispose);
      await reopened.loadLibrary();
      expect(reopened.activePlaylistId, isNull);
      expect(reopened.playlistSongIds, isEmpty);
      expect(reopened.displaySongs.map((s) => s.id), ['s1']);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('aetheria-active-playlist-v1'), isNull);
    });
    });

    group('song list scroll offset persistence', () {
      test('persists offsets per viewport and scope across restarts', () async {
        const pl1 = Playlist(id: 'pl-1', name: '1', createdAt: '');
        const phi = Playlist(
          id: 'pl-phi',
          name: 'Phigros',
          createdAt: '',
          kind: 'phigros',
        );
        api.dbPlaylists.addAll([pl1, phi]);
        api.dbSongs.addAll([
          _song('s1', 'Song One'),
          _song('s2', 'Song Two'),
        ]);

        final session1 = LibraryProvider();
        addTearDown(session1.dispose);
        await session1.loadLibrary();

        expect(session1.songListScrollScope, 'all');
        expect(
          session1.recordSongListScrollOffset(
            SongListViewport.desktop,
            'all',
            624.0,
          ),
          isTrue,
        );
        expect(
          session1.recordSongListScrollOffset(
            SongListViewport.desktop,
            'playlist:pl-1',
            1248.0,
          ),
          isTrue,
        );
        expect(
          session1.recordSongListScrollOffset(
            SongListViewport.mobile,
            'all',
            310.0,
          ),
          isTrue,
        );
        await session1.persistSongListScrollOffsets();

        await session1.setActivePlaylist(phi.id);
        expect(session1.songListScrollScope, 'playlist:pl-phi');
        session1.setActivePhigrosChapter('Legacy');
        expect(session1.songListScrollScope, 'playlist:pl-phi:Legacy');
        session1.recordSongListScrollOffset(
          SongListViewport.desktop,
          'playlist:pl-phi:Legacy',
          416.0,
        );
        await session1.persistSongListScrollOffsets();

        // Active search or tag filters temporarily hide the persisted scope.
        session1.setSearchQuery('Song');
        expect(session1.songListScrollScope, isNull);
        session1.setSearchQuery('');
        expect(session1.songListScrollScope, 'playlist:pl-phi:Legacy');
        session1.toggleTag(1);
        expect(session1.songListScrollScope, isNull);
        session1.clearTagFilters();

        final session2 = LibraryProvider();
        addTearDown(session2.dispose);
        await session2.loadLibrary();

        expect(
          session2.savedSongListScrollOffset(SongListViewport.desktop, 'all'),
          624.0,
        );
        expect(
          session2.savedSongListScrollOffset(
            SongListViewport.desktop,
            'playlist:pl-1',
          ),
          1248.0,
        );
        expect(
          session2.savedSongListScrollOffset(
            SongListViewport.desktop,
            'playlist:pl-phi:Legacy',
          ),
          416.0,
        );
        expect(
          session2.savedSongListScrollOffset(SongListViewport.mobile, 'all'),
          310.0,
        );

        // Returning to the very top clears the stored offset across restarts.
        expect(
          session2.recordSongListScrollOffset(
            SongListViewport.desktop,
            'all',
            0.0,
          ),
          isTrue,
        );
        await session2.persistSongListScrollOffsets();

        final session3 = LibraryProvider();
        addTearDown(session3.dispose);
        await session3.loadLibrary();
        expect(
          session3.savedSongListScrollOffset(SongListViewport.desktop, 'all'),
          0.0,
        );
      });

      test('prunes offsets for deleted or vanished playlists', () async {
        const pl1 = Playlist(id: 'pl-1', name: '1', createdAt: '');
        const pl2 = Playlist(id: 'pl-2', name: '2', createdAt: '');
        api.dbPlaylists.addAll([pl1, pl2]);
        api.dbSongs.add(_song('s1', 'Song One'));

        final session1 = LibraryProvider();
        addTearDown(session1.dispose);
        await session1.loadLibrary();
        session1.recordSongListScrollOffset(
          SongListViewport.desktop,
          'all',
          200.0,
        );
        session1.recordSongListScrollOffset(
          SongListViewport.desktop,
          'playlist:pl-1',
          500.0,
        );
        session1.recordSongListScrollOffset(
          SongListViewport.desktop,
          'playlist:pl-2',
          700.0,
        );
        await session1.persistSongListScrollOffsets();

        await session1.deletePlaylist(pl1.id);
        expect(
          session1.savedSongListScrollOffset(
            SongListViewport.desktop,
            'playlist:pl-1',
          ),
          0.0,
        );
        expect(
          session1.savedSongListScrollOffset(
            SongListViewport.desktop,
            'playlist:pl-2',
          ),
          700.0,
        );

        // Simulate external removal of pl-2 before next startup.
        api.dbPlaylists.removeWhere((p) => p.id == pl2.id);

        final session2 = LibraryProvider();
        addTearDown(session2.dispose);
        await session2.loadLibrary();
        expect(
          session2.savedSongListScrollOffset(SongListViewport.desktop, 'all'),
          200.0,
        );
        expect(
          session2.savedSongListScrollOffset(
            SongListViewport.desktop,
            'playlist:pl-2',
          ),
          0.0,
        );
      });
    });
  });
}
