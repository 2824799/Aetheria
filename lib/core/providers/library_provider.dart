import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/src/rust/models/song.dart';
import 'package:aetheria/src/rust/models/playlist.dart';

class LibraryProvider extends ChangeNotifier {
  List<Song> songs = [];
  List<Tag> tags = [];
  List<Playlist> playlists = [];

  String? activePlaylistId;
  List<String> playlistSongIds = [];

  String searchQuery = '';
  List<PlatformInt64> selectedTags = [];
  List<PlatformInt64> excludedTags = [];
  String filterMode = 'AND'; // 'AND' or 'OR'

  String libraryPath = '';
  int? audioServerPort;

  bool isLoading = true;
  String? error;
  Map<String, dynamic>?
  clipboard; // { 'type': 'copy'/'cut', 'songIds': [...], 'sourcePlaylistId': '...' }

  LibraryProvider() {
    // Loaded externally in main or layout
  }

  Future<void> loadLibrary() async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final isInit = await music.isLibraryInitialized();
      if (!isInit) {
        isLoading = false;
        notifyListeners();
        return;
      }

      songs = await music.getSongs();
      tags = await music.getTags();
      playlists = await music.getPlaylists();
      libraryPath = await music.getLibraryPath();

      if (activePlaylistId != null) {
        try {
          playlistSongIds = await music.getPlaylistSongs(
            playlistId: activePlaylistId!,
          );
        } catch (e) {
          playlistSongIds = [];
        }
      } else {
        playlistSongIds = [];
      }

      isLoading = false;
      notifyListeners();
    } catch (e) {
      error = e.toString();
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> initializeLibrary(String path) async {
    isLoading = true;
    notifyListeners();
    try {
      await music.initializeLibraryPath(path: path);
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      isLoading = false;
      notifyListeners();
    }
  }

  bool isRefreshingDatabase = false;

  Future<void> refreshDatabase() async {
    isRefreshingDatabase = true;
    notifyListeners();
    try {
      await music.refreshSongDatabase();
      await loadLibrary();
    } catch (e) {
      error = e.toString();
    } finally {
      isRefreshingDatabase = false;
      notifyListeners();
    }
  }

  Future<void> importSong(String filepath) async {
    try {
      await music.importSong(filepath: filepath);
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> importSongWithMetadata(
    String filepath,
    String title,
    String artist,
  ) async {
    try {
      await music.importSongWithMetadata(
        filepath: filepath,
        title: title,
        artist: artist,
      );
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> importAudioVersionForSong(String songId, String filepath) async {
    try {
      await music.importAudioVersionForSong(songId: songId, filepath: filepath);
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateVersionStatus(
    String versionId,
    bool isEnabled,
    bool isPrimary,
  ) async {
    try {
      await music.updateVersionStatus(
        versionId: versionId,
        isEnabled: isEnabled,
        isPrimary: isPrimary,
      );
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateSongMetadata(
    String songId,
    String title,
    String artist,
  ) async {
    try {
      await music.updateSongMetadata(
        songId: songId,
        title: title,
        artist: artist,
      );
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteSong(String songId) async {
    try {
      await music.deleteSong(songId: songId);
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteAudioVersion(String versionId) async {
    try {
      await music.deleteAudioVersion(versionId: versionId);
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addTag(String name, String? color, String? category) async {
    try {
      await music.addTag(name: name, color: color, category: category);
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateTag(
    PlatformInt64 tagId,
    String name,
    String? color,
    String? category,
  ) async {
    try {
      await music.updateTag(
        tagId: tagId,
        name: name,
        color: color,
        category: category,
      );
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteTag(PlatformInt64 tagId) async {
    try {
      await music.deleteTag(tagId: tagId);
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> tagSong(String songId, PlatformInt64 tagId, bool bind) async {
    try {
      await music.tagSong(songId: songId, tagId: tagId, bind: bind);
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> createPlaylist(String name) async {
    try {
      await music.createPlaylist(name: name);
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deletePlaylist(String id) async {
    try {
      await music.deletePlaylist(id: id);
      if (activePlaylistId == id) {
        activePlaylistId = null;
      }
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> renamePlaylist(String id, String name) async {
    try {
      await music.renamePlaylist(id: id, name: name);
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addSongsToPlaylist(
    String playlistId,
    List<String> songIds,
  ) async {
    try {
      await music.addSongsToPlaylist(playlistId: playlistId, songIds: songIds);
      if (activePlaylistId == playlistId) {
        playlistSongIds = await music.getPlaylistSongs(playlistId: playlistId);
      }
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removeSongsFromPlaylist(
    String playlistId,
    List<String> songIds,
  ) async {
    try {
      await music.removeSongsFromPlaylist(
        playlistId: playlistId,
        songIds: songIds,
      );
      if (activePlaylistId == playlistId) {
        playlistSongIds = await music.getPlaylistSongs(playlistId: playlistId);
      }
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> resetLibrary() async {
    try {
      await music.resetLibrary();
      activePlaylistId = null;
      selectedTags.clear();
      excludedTags.clear();
      searchQuery = '';
      await loadLibrary();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    notifyListeners();
  }

  void toggleTag(PlatformInt64 tagId) {
    if (selectedTags.contains(tagId)) {
      selectedTags.remove(tagId);
      excludedTags.add(tagId);
    } else if (excludedTags.contains(tagId)) {
      excludedTags.remove(tagId);
    } else {
      selectedTags.add(tagId);
    }
    notifyListeners();
  }

  void setFilterMode(String mode) {
    filterMode = mode;
    notifyListeners();
  }

  void setActivePlaylist(String? playlistId) async {
    activePlaylistId = playlistId;
    if (playlistId != null) {
      try {
        playlistSongIds = await music.getPlaylistSongs(playlistId: playlistId);
      } catch (e) {
        playlistSongIds = [];
      }
    } else {
      playlistSongIds = [];
    }
    notifyListeners();
  }

  List<Song> get displaySongs {
    List<Song> list = songs;

    // Filter by playlist
    if (activePlaylistId != null) {
      list = list.where((song) => playlistSongIds.contains(song.id)).toList();
      // Sort list according to playlistSongIds ordering
      list.sort((a, b) {
        final idxA = playlistSongIds.indexOf(a.id);
        final idxB = playlistSongIds.indexOf(b.id);
        return idxA.compareTo(idxB);
      });
    }

    // Filter by search
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      list = list
          .where(
            (song) =>
                song.title.toLowerCase().contains(q) ||
                (song.artist?.toLowerCase().contains(q) ?? false) ||
                (song.album?.toLowerCase().contains(q) ?? false),
          )
          .toList();
    }

    // Filter by tags
    if (selectedTags.isNotEmpty || excludedTags.isNotEmpty) {
      list = list.where((song) {
        final songTagIds = song.tags.map((t) => t.id).toSet();

        if (excludedTags.isNotEmpty) {
          final hasExcluded = excludedTags.any((id) => songTagIds.contains(id));
          if (hasExcluded) return false;
        }

        if (selectedTags.isNotEmpty) {
          if (filterMode == 'AND') {
            return selectedTags.every((id) => songTagIds.contains(id));
          } else {
            return selectedTags.any((id) => songTagIds.contains(id));
          }
        }

        return true;
      }).toList();
    }

    return list;
  }

  void setClipboard(
    String type,
    List<String> songIds,
    String? sourcePlaylistId,
  ) {
    clipboard = {
      'type': type,
      'songIds': songIds,
      'sourcePlaylistId': sourcePlaylistId,
    };
    notifyListeners();
  }

  void clearClipboard() {
    clipboard = null;
    notifyListeners();
  }

  Future<void> pasteSongs(String targetPlaylistId) async {
    if (clipboard == null) return;
    final type = clipboard!['type'] as String;
    final songIds = List<String>.from(clipboard!['songIds'] as List);
    final sourcePlaylistId = clipboard!['sourcePlaylistId'] as String?;

    try {
      await addSongsToPlaylist(targetPlaylistId, songIds);
      if (type == 'cut' &&
          sourcePlaylistId != null &&
          sourcePlaylistId != targetPlaylistId) {
        await removeSongsFromPlaylist(sourcePlaylistId, songIds);
      }
      clearClipboard();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }
}
