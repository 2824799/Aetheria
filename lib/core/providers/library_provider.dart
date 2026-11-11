import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/src/rust/models/song.dart';
import 'package:aetheria/src/rust/models/playlist.dart';

bool _isAsciiDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

/// Compares text using Windows Explorer-style natural ordering.
///
/// Numeric runs are compared by value, so "Track 2" precedes "Track 10".
/// The implementation lives in Dart so every supported platform presents the
/// same order instead of relying on platform-specific native comparators.
int explorerStyleCompare(String left, String right) {
  var leftIndex = 0;
  var rightIndex = 0;
  var numericFormattingOrder = 0;

  while (leftIndex < left.length && rightIndex < right.length) {
    final leftIsDigit = _isAsciiDigit(left.codeUnitAt(leftIndex));
    final rightIsDigit = _isAsciiDigit(right.codeUnitAt(rightIndex));

    if (leftIsDigit && rightIsDigit) {
      final leftStart = leftIndex;
      final rightStart = rightIndex;
      while (leftIndex < left.length &&
          _isAsciiDigit(left.codeUnitAt(leftIndex))) {
        leftIndex += 1;
      }
      while (rightIndex < right.length &&
          _isAsciiDigit(right.codeUnitAt(rightIndex))) {
        rightIndex += 1;
      }

      var leftSignificantStart = leftStart;
      var rightSignificantStart = rightStart;
      while (leftSignificantStart < leftIndex - 1 &&
          left.codeUnitAt(leftSignificantStart) == 0x30) {
        leftSignificantStart += 1;
      }
      while (rightSignificantStart < rightIndex - 1 &&
          right.codeUnitAt(rightSignificantStart) == 0x30) {
        rightSignificantStart += 1;
      }

      final leftSignificantLength = leftIndex - leftSignificantStart;
      final rightSignificantLength = rightIndex - rightSignificantStart;
      final lengthOrder = leftSignificantLength.compareTo(
        rightSignificantLength,
      );
      if (lengthOrder != 0) {
        return lengthOrder;
      }
      for (var index = 0; index < leftSignificantLength; index++) {
        final digitOrder = left
            .codeUnitAt(leftSignificantStart + index)
            .compareTo(right.codeUnitAt(rightSignificantStart + index));
        if (digitOrder != 0) {
          return digitOrder;
        }
      }

      if (numericFormattingOrder == 0) {
        numericFormattingOrder = (leftIndex - leftStart).compareTo(
          rightIndex - rightStart,
        );
      }
      continue;
    }

    if (leftIsDigit != rightIsDigit) {
      return leftIsDigit ? -1 : 1;
    }

    final leftStart = leftIndex;
    final rightStart = rightIndex;
    while (leftIndex < left.length &&
        !_isAsciiDigit(left.codeUnitAt(leftIndex))) {
      leftIndex += 1;
    }
    while (rightIndex < right.length &&
        !_isAsciiDigit(right.codeUnitAt(rightIndex))) {
      rightIndex += 1;
    }
    final textOrder = left
        .substring(leftStart, leftIndex)
        .toLowerCase()
        .compareTo(right.substring(rightStart, rightIndex).toLowerCase());
    if (textOrder != 0) {
      return textOrder;
    }
  }

  final remainingOrder = (left.length - leftIndex).compareTo(
    right.length - rightIndex,
  );
  if (remainingOrder != 0) {
    return remainingOrder;
  }
  if (numericFormattingOrder != 0) {
    return numericFormattingOrder;
  }
  return left.compareTo(right);
}

int _compareSongsLikeExplorer(Song left, Song right) {
  final titleOrder = explorerStyleCompare(left.title, right.title);
  if (titleOrder != 0) {
    return titleOrder;
  }
  final artistOrder = explorerStyleCompare(
    left.artist ?? '',
    right.artist ?? '',
  );
  if (artistOrder != 0) {
    return artistOrder;
  }
  return left.id.compareTo(right.id);
}

/// One file to import. A non-null [title] overrides what the file's tags say.
typedef SongImportRequest = ({String filepath, String? title, String? artist});

enum SongClipboardMode { copy, cut }

/// Songs picked up with copy/cut, waiting to be pasted into a playlist.
class SongClipboard {
  const SongClipboard({
    required this.mode,
    required this.songIds,
    this.sourcePlaylistId,
  });

  final SongClipboardMode mode;
  final List<String> songIds;
  final String? sourcePlaylistId;
}

Song _copySong(
  Song song, {
  required String? lyrics,
  required String? coverPath,
}) {
  return Song(
    id: song.id,
    title: song.title,
    artist: song.artist,
    album: song.album,
    lyrics: lyrics,
    coverPath: coverPath,
    rating: song.rating,
    createdAt: song.createdAt,
    versions: song.versions,
    tags: song.tags,
  );
}

class LibraryProvider extends ChangeNotifier {
  List<Song> songs = [];
  List<Tag> tags = [];
  List<Playlist> playlists = [];
  Set<String> songIdsWithLyrics = {};

  String? activePlaylistId;
  List<String> playlistSongIds = [];

  String searchQuery = '';
  List<PlatformInt64> selectedTags = [];
  List<PlatformInt64> excludedTags = [];
  String filterMode = 'AND'; // 'AND' or 'OR'

  String libraryPath = '';

  /// True only while the very first load is running; later reloads keep the
  /// current list on screen instead of flashing a loading state.
  bool isLoading = true;
  String? error;
  SongClipboard? clipboard;

  bool isRefreshingDatabase = false;
  int refreshProgressCurrent = 0;
  int refreshProgressTotal = 0;
  String refreshProgressLabel = '';

  bool _hasLoaded = false;
  int _loadRequest = 0;
  int _playlistRequest = 0;
  List<Song>? _displaySongsCache;

  @override
  void notifyListeners() {
    _displaySongsCache = null;
    super.notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> loadLibrary() async {
    final request = ++_loadRequest;
    final firstLoad = !_hasLoaded;
    if (isLoading != firstLoad || error != null) {
      isLoading = firstLoad;
      error = null;
      notifyListeners();
    }

    try {
      if (!music.isLibraryInitialized()) {
        return;
      }

      final playlistId = activePlaylistId;
      final (
        loadedSongs,
        loadedTags,
        loadedPlaylists,
        loadedPath,
        lyricSongIds,
        loadedPlaylistSongIds,
      ) = await (
        music.getSongs(),
        music.getTags(),
        music.getPlaylists(),
        music.getLibraryPath(),
        music.getSongIdsWithLyrics(),
        _playlistSongIdsOrEmpty(playlistId),
      ).wait;

      // A newer load started while this one was in flight; its result wins.
      if (request != _loadRequest) {
        return;
      }

      songs = loadedSongs;
      tags = loadedTags;
      playlists = loadedPlaylists;
      libraryPath = loadedPath;
      songIdsWithLyrics = lyricSongIds.toSet();
      if (activePlaylistId == playlistId) {
        playlistSongIds = loadedPlaylistSongIds;
      }
    } catch (e) {
      if (request == _loadRequest) {
        error = e.toString();
      }
    } finally {
      if (request == _loadRequest) {
        _hasLoaded = true;
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<List<String>> _playlistSongIdsOrEmpty(String? playlistId) async {
    if (playlistId == null) {
      return const [];
    }
    try {
      return await music.getPlaylistSongs(playlistId: playlistId);
    } catch (_) {
      // The playlist may have been deleted (locally or by a sync).
      return const [];
    }
  }

  Future<void> initializeLibrary(String path) {
    return _mutate(() => music.initializeLibraryPath(path: path));
  }

  /// Runs a library mutation, then reloads so every listener sees the result.
  /// Failures are recorded in [error] and rethrown for the caller to present.
  Future<void> _mutate(
    Future<void> Function() action, {
    bool reload = true,
  }) async {
    try {
      await action();
      if (reload) {
        await loadLibrary();
      } else {
        notifyListeners();
      }
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Lyrics flags and covers
  // ---------------------------------------------------------------------------

  bool songHasLyrics(Song song) {
    final legacy = song.lyrics?.trim();
    return legacy?.isNotEmpty == true || songIdsWithLyrics.contains(song.id);
  }

  void markSongHasLyrics(String songId) {
    if (songId.isEmpty || songIdsWithLyrics.contains(songId)) {
      return;
    }
    songIdsWithLyrics = {...songIdsWithLyrics, songId};
    notifyListeners();
  }

  void markSongHasNoLyrics(String songId) {
    if (songId.isEmpty) {
      return;
    }
    songIdsWithLyrics = {
      for (final id in songIdsWithLyrics)
        if (id != songId) id,
    };
    songs = [
      for (final song in songs)
        if (song.id == songId)
          _copySong(song, lyrics: null, coverPath: song.coverPath)
        else
          song,
    ];
    notifyListeners();
  }

  Future<String?> ensureSongCover(Song song) async {
    if (song.id.isEmpty) {
      return null;
    }
    try {
      final coverPath = await music.ensureSongCover(songId: song.id);
      if (coverPath == null || coverPath.trim().isEmpty) {
        return null;
      }
      if (song.coverPath != coverPath) {
        songs = [
          for (final entry in songs)
            if (entry.id == song.id)
              _copySong(entry, lyrics: entry.lyrics, coverPath: coverPath)
            else
              entry,
        ];
        notifyListeners();
      }
      return coverPath;
    } catch (e) {
      debugPrint('ensureSongCover(${song.id}) failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Metadata refresh
  // ---------------------------------------------------------------------------

  Future<void> refreshDatabase({bool onlyUnscanned = false}) async {
    if (isRefreshingDatabase) {
      return;
    }
    isRefreshingDatabase = true;
    refreshProgressCurrent = 0;
    refreshProgressTotal = 0;
    refreshProgressLabel = onlyUnscanned ? '正在查找新增歌曲...' : '正在准备刷新任务...';
    notifyListeners();
    try {
      final snapshotSongs = songs.isNotEmpty
          ? List<Song>.of(songs)
          : await music.getSongs();
      final targetSongs = onlyUnscanned
          ? snapshotSongs
                .where(
                  (song) =>
                      song.versions.any((version) => !version.metadataScanned),
                )
                .toList()
          : snapshotSongs;

      refreshProgressTotal = targetSongs.length;
      if (targetSongs.isEmpty) {
        refreshProgressLabel = onlyUnscanned
            ? '没有找到新增或未完整扫描的歌曲。'
            : '音乐库为空，无需刷新。';
      }
      notifyListeners();

      String? firstFailure;
      for (var songIndex = 0; songIndex < targetSongs.length; songIndex++) {
        final song = targetSongs[songIndex];
        refreshProgressCurrent = songIndex;
        refreshProgressLabel =
            '正在刷新 ${songIndex + 1} / ${targetSongs.length} 首歌曲: ${song.title}';
        notifyListeners();

        for (final version in song.versions) {
          if (onlyUnscanned && version.metadataScanned) {
            continue;
          }
          try {
            await music.refreshAudioFileMetadata(versionId: version.id);
          } catch (e) {
            // One unreadable file must not abort the rest of the scan.
            firstFailure ??= '${song.title}: $e';
          }
        }
      }

      await loadLibrary();
      if (firstFailure != null) {
        error = firstFailure;
      }
    } catch (e) {
      error = e.toString();
    } finally {
      isRefreshingDatabase = false;
      refreshProgressCurrent = 0;
      refreshProgressTotal = 0;
      refreshProgressLabel = '';
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Songs and versions
  // ---------------------------------------------------------------------------

  /// Imports [requests] in order and reloads the library once at the end.
  ///
  /// One bad file does not stop the rest: the reasons of the files that could
  /// not be imported are returned. [onProgress] receives the number handled.
  Future<List<String>> importSongs(
    List<SongImportRequest> requests, {
    void Function(int done)? onProgress,
  }) async {
    final failures = <String>[];
    try {
      for (var index = 0; index < requests.length; index++) {
        final request = requests[index];
        final title = request.title;
        try {
          if (title == null) {
            await music.importSong(filepath: request.filepath);
          } else {
            await music.importSongWithMetadata(
              filepath: request.filepath,
              title: title,
              artist: request.artist ?? '',
            );
          }
        } catch (e) {
          failures.add(e.toString());
        }
        onProgress?.call(index + 1);
      }
    } finally {
      await loadLibrary();
    }
    return failures;
  }

  Future<void> importAudioVersionForSong(String songId, String filepath) {
    return _mutate(
      () => music.importAudioVersionForSong(songId: songId, filepath: filepath),
    );
  }

  Future<void> setPrimaryVersion(String versionId) {
    return _mutate(() => music.setPrimaryVersion(versionId: versionId));
  }

  Future<void> updateSongMetadata(String songId, String title, String artist) {
    return _mutate(
      () => music.updateSongMetadata(
        songId: songId,
        title: title,
        artist: artist,
      ),
    );
  }

  Future<void> deleteSong(String songId) {
    return _mutate(() => music.deleteSong(songId: songId));
  }

  Future<void> deleteAudioVersion(String versionId) {
    return _mutate(() => music.deleteAudioVersion(versionId: versionId));
  }

  // ---------------------------------------------------------------------------
  // Tags
  // ---------------------------------------------------------------------------

  Future<void> addTag(String name, String? color, String? category) {
    return _mutate(
      () => music.addTag(name: name, color: color, category: category),
    );
  }

  Future<void> updateTag(
    PlatformInt64 tagId,
    String name,
    String? color,
    String? category,
  ) {
    return _mutate(
      () => music.updateTag(
        tagId: tagId,
        name: name,
        color: color,
        category: category,
      ),
    );
  }

  Future<void> deleteTag(PlatformInt64 tagId) {
    return _mutate(() async {
      await music.deleteTag(tagId: tagId);
      // A deleted tag must not keep filtering the list invisibly.
      selectedTags.remove(tagId);
      excludedTags.remove(tagId);
    });
  }

  Future<void> tagSong(String songId, PlatformInt64 tagId, bool bind) {
    return _mutate(
      () => music.tagSong(songId: songId, tagId: tagId, bind: bind),
    );
  }

  // ---------------------------------------------------------------------------
  // Playlists
  // ---------------------------------------------------------------------------

  Future<void> createPlaylist(String name) {
    return _mutate(() => music.createPlaylist(name: name));
  }

  Future<void> deletePlaylist(String id) {
    return _mutate(() async {
      await music.deletePlaylist(id: id);
      if (activePlaylistId == id) {
        activePlaylistId = null;
        playlistSongIds = [];
      }
      if (clipboard?.sourcePlaylistId == id) {
        clipboard = null;
      }
    });
  }

  Future<void> renamePlaylist(String id, String name) {
    return _mutate(() => music.renamePlaylist(id: id, name: name));
  }

  Future<void> addSongsToPlaylist(String playlistId, List<String> songIds) {
    return _mutate(() async {
      await music.addSongsToPlaylist(playlistId: playlistId, songIds: songIds);
      await _reloadActivePlaylistSongs(playlistId);
    }, reload: false);
  }

  Future<void> removeSongsFromPlaylist(
    String playlistId,
    List<String> songIds,
  ) {
    return _mutate(() async {
      await music.removeSongsFromPlaylist(
        playlistId: playlistId,
        songIds: songIds,
      );
      await _reloadActivePlaylistSongs(playlistId);
    }, reload: false);
  }

  Future<void> _reloadActivePlaylistSongs(String playlistId) async {
    if (activePlaylistId != playlistId) {
      return;
    }
    final ids = await music.getPlaylistSongs(playlistId: playlistId);
    if (activePlaylistId == playlistId) {
      playlistSongIds = ids;
    }
  }

  Future<void> setActivePlaylist(String? playlistId) async {
    final request = ++_playlistRequest;
    activePlaylistId = playlistId;
    playlistSongIds = [];
    notifyListeners();
    if (playlistId == null) {
      return;
    }
    final ids = await _playlistSongIdsOrEmpty(playlistId);
    if (request != _playlistRequest) {
      return;
    }
    playlistSongIds = ids;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Clipboard
  // ---------------------------------------------------------------------------

  void setClipboard(
    SongClipboardMode mode,
    List<String> songIds,
    String? sourcePlaylistId,
  ) {
    clipboard = SongClipboard(
      mode: mode,
      songIds: List<String>.unmodifiable(songIds),
      sourcePlaylistId: sourcePlaylistId,
    );
    notifyListeners();
  }

  Future<void> pasteSongs(String targetPlaylistId) async {
    final pending = clipboard;
    if (pending == null) {
      return;
    }
    await addSongsToPlaylist(targetPlaylistId, pending.songIds);
    final source = pending.sourcePlaylistId;
    if (pending.mode == SongClipboardMode.cut &&
        source != null &&
        source != targetPlaylistId) {
      await removeSongsFromPlaylist(source, pending.songIds);
    }
    clipboard = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Filtering
  // ---------------------------------------------------------------------------

  void setSearchQuery(String query) {
    if (searchQuery == query) {
      return;
    }
    searchQuery = query;
    notifyListeners();
  }

  /// Cycles a tag through: unselected → required → excluded → unselected.
  void toggleTag(PlatformInt64 tagId) {
    if (selectedTags.remove(tagId)) {
      excludedTags.add(tagId);
    } else if (!excludedTags.remove(tagId)) {
      selectedTags.add(tagId);
    }
    notifyListeners();
  }

  void clearTagFilters() {
    if (selectedTags.isEmpty && excludedTags.isEmpty) {
      return;
    }
    selectedTags = [];
    excludedTags = [];
    notifyListeners();
  }

  void setFilterMode(String mode) {
    if (filterMode == mode) {
      return;
    }
    filterMode = mode;
    notifyListeners();
  }

  List<Song> get displaySongs {
    final cached = _displaySongsCache;
    if (cached != null) {
      return cached;
    }

    Iterable<Song> list = songs;
    final inPlaylist = activePlaylistId != null;
    if (inPlaylist) {
      final byId = {for (final song in songs) song.id: song};
      list = [for (final id in playlistSongIds) ?byId[id]];
    }

    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      list = list.where(
        (song) =>
            song.title.toLowerCase().contains(query) ||
            (song.artist?.toLowerCase().contains(query) ?? false) ||
            (song.album?.toLowerCase().contains(query) ?? false),
      );
    }

    if (selectedTags.isNotEmpty || excludedTags.isNotEmpty) {
      final matchAll = filterMode == 'AND';
      list = list.where((song) {
        final songTagIds = {for (final tag in song.tags) tag.id};
        if (excludedTags.any(songTagIds.contains)) {
          return false;
        }
        if (selectedTags.isEmpty) {
          return true;
        }
        return matchAll
            ? selectedTags.every(songTagIds.contains)
            : selectedTags.any(songTagIds.contains);
      });
    }

    final result = list.toList();
    // Playlist order is user-defined. Every other list uses one shared natural
    // ordering so desktop and mobile never depend on their native platform.
    if (!inPlaylist) {
      result.sort(_compareSongsLikeExplorer);
    }
    return _displaySongsCache = List<Song>.unmodifiable(result);
  }
}
