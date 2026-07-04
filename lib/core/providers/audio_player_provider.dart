import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/services/native_audio_helper.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

enum PlayMode { list, single, shuffle }

class AudioPlayerProvider extends ChangeNotifier {
  static const String _playbackSongIdKey = 'aetheria-playback-song-id';
  static const String _playbackVersionIdKey = 'aetheria-playback-version-id';
  static const String _playbackPositionMsKey = 'aetheria-playback-position-ms';
  static const String _playbackQueueIdsKey = 'aetheria-playback-queue-ids';

  Song? activeSong;
  Song? playingSong;
  AudioVersion? playingVersion;

  List<Song> currentQueue = [];

  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;

  double volume = 0.8;
  PlayMode playMode = PlayMode.list;
  bool playAlongside = false;

  bool volumeBalanceEnabled = false;
  double volumeBalanceStrength = 0.5;
  double pitchSemitones = 0.0;
  String pitchAlgorithm = 'wsola';

  bool isDetailOpen = false;
  String activeTab = 'versions';

  String _cachedLibraryPath = '';
  int? _cachedAudioServerPort;
  Timer? _positionTimer;
  int _lastPositionMs = -1;
  int _lastPersistedSecond = -1;
  int _stallTicks = 0;
  bool _hasPreparedPlayback = false;
  Duration? _pendingRestorePosition;

  AudioPlayerProvider() {
    loadSettings();
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _lastPositionMs = -1;
    _lastPersistedSecond = -1;
    _stallTicks = 0;
    _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (
      timer,
    ) async {
      if (!isPlaying) return;
      final posSec = await music.getRustPlaybackPosition();
      currentPosition = Duration(milliseconds: (posSec * 1000).round());

      final reachedEnd =
          currentPosition >= totalDuration && totalDuration > Duration.zero;

      // Fallback for EOF: the Rust position is derived from samples the hardware
      // actually consumed, so if the stored duration is slightly overestimated the
      // position will plateau just below totalDuration once the stream ends. Detect
      // that stall and advance as well.
      final posMs = currentPosition.inMilliseconds;
      if (posMs == _lastPositionMs) {
        _stallTicks += 1;
      } else {
        _stallTicks = 0;
        _lastPositionMs = posMs;
      }
      final stalledAtEnd = _stallTicks >= 6 && currentPosition > Duration.zero;

      if (reachedEnd || stalledAtEnd) {
        _positionTimer?.cancel();
        if (playMode == PlayMode.single) {
          await seek(Duration.zero);
          await resume();
        } else {
          playNext();
        }
      }
      if (currentPosition.inSeconds != _lastPersistedSecond) {
        _lastPersistedSecond = currentPosition.inSeconds;
        unawaited(_persistPlaybackState());
      }
      notifyListeners();
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
  }

  Future<void> loadSettings() async {
    try {
      if (Platform.isAndroid) {
        await NativeAudioHelper.requestNotificationPermission();
      }
      final prefs = await SharedPreferences.getInstance();
      playAlongside = prefs.getBool('play-alongside') ?? false;
      volumeBalanceEnabled = prefs.getBool('volume-balance-enabled') ?? false;
      volumeBalanceStrength = prefs.getDouble('volume-balance-strength') ?? 0.5;
      pitchSemitones = prefs.getDouble('pitch-semitones') ?? 0.0;
      pitchAlgorithm = prefs.getString('pitch-algorithm') ?? 'wsola';
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setPlayAlongside(bool value) async {
    playAlongside = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('play-alongside', value);
    } catch (_) {}
  }

  Future<void> setVolumeBalanceEnabled(bool value) async {
    volumeBalanceEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('volume-balance-enabled', value);
      await _hotReloadDSP();
    } catch (_) {}
  }

  Future<void> setVolumeBalanceStrength(double value) async {
    volumeBalanceStrength = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('volume-balance-strength', value);
      await _hotReloadDSP();
    } catch (_) {}
  }

  Future<void> setPitchSemitones(double value) async {
    pitchSemitones = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('pitch-semitones', value);
      await music.setRustPitch(pitch: value, algo: pitchAlgorithm);
    } catch (_) {}
  }

  Future<void> setPitchAlgorithm(String value) async {
    pitchAlgorithm = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pitch-algorithm', value);
      await music.setRustPitch(pitch: pitchSemitones, algo: value);
    } catch (_) {}
  }

  double _computeNormalizationGain(AudioVersion version) {
    if (!volumeBalanceEnabled) {
      return 1.0;
    }
    final lMin = getLMin();
    final lSong = version.loudness ?? -15.0;
    if (lSong <= lMin) {
      return 1.0;
    }
    final deltaDb = volumeBalanceStrength * (lMin - lSong);
    return math.pow(10, deltaDb / 20).toDouble();
  }

  Future<void> _clearPersistedPlaybackState(SharedPreferences prefs) async {
    await prefs.remove(_playbackSongIdKey);
    await prefs.remove(_playbackVersionIdKey);
    await prefs.remove(_playbackPositionMsKey);
    await prefs.remove(_playbackQueueIdsKey);
  }

  Future<void> _persistPlaybackState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final song = playingSong;
      final version = playingVersion;
      if (song == null || version == null) {
        await _clearPersistedPlaybackState(prefs);
        return;
      }

      await prefs.setString(_playbackSongIdKey, song.id);
      await prefs.setString(_playbackVersionIdKey, version.id);
      await prefs.setInt(
        _playbackPositionMsKey,
        currentPosition.inMilliseconds,
      );
      await prefs.setStringList(
        _playbackQueueIdsKey,
        currentQueue.map((entry) => entry.id).toList(growable: false),
      );
    } catch (_) {}
  }

  Future<void> restorePlaybackState(
    List<Song> librarySongs,
    String libraryPath, {
    int? audioServerPort,
  }) async {
    if (librarySongs.isEmpty || libraryPath.isEmpty) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final songId = prefs.getString(_playbackSongIdKey);
      final versionId = prefs.getString(_playbackVersionIdKey);
      if (songId == null || versionId == null) {
        return;
      }

      Song? restoredSong;
      for (final song in librarySongs) {
        if (song.id == songId) {
          restoredSong = song;
          break;
        }
      }
      if (restoredSong == null) {
        await _clearPersistedPlaybackState(prefs);
        return;
      }

      AudioVersion? restoredVersion;
      for (final version in restoredSong.versions) {
        if (version.id == versionId) {
          restoredVersion = version;
          break;
        }
      }
      if (restoredVersion == null) {
        await _clearPersistedPlaybackState(prefs);
        return;
      }
      final restoredSongValue = restoredSong;
      final restoredVersionValue = restoredVersion;

      final savedQueueIds =
          prefs.getStringList(_playbackQueueIdsKey) ?? const <String>[];
      final songsById = {for (final song in librarySongs) song.id: song};
      final restoredQueue = <Song>[];
      for (final id in savedQueueIds) {
        final queueSong = songsById[id];
        if (queueSong != null &&
            !restoredQueue.any((entry) => entry.id == id)) {
          restoredQueue.add(queueSong);
        }
      }
      if (!restoredQueue.any((entry) => entry.id == restoredSongValue.id)) {
        restoredQueue.insert(0, restoredSongValue);
      }

      activeSong = restoredSongValue;
      playingSong = restoredSongValue;
      playingVersion = restoredVersionValue;
      currentQueue = restoredQueue;
      _cachedLibraryPath = libraryPath;
      _cachedAudioServerPort = audioServerPort;

      final savedPositionMs = prefs.getInt(_playbackPositionMsKey) ?? 0;
      totalDuration = Duration(
        milliseconds: (restoredVersionValue.duration * 1000).round(),
      );
      currentPosition = Duration(milliseconds: savedPositionMs);
      if (totalDuration > Duration.zero && currentPosition > totalDuration) {
        currentPosition = totalDuration;
      }

      isPlaying = false;
      _hasPreparedPlayback = false;
      _pendingRestorePosition = currentPosition;
      notifyListeners();
      _updateNotification();
    } catch (_) {}
  }

  Future<void> _startCurrentVersionPlayback({
    required Duration startPosition,
    required bool startPaused,
  }) async {
    final version = playingVersion;
    if (version == null) {
      throw Exception('当前没有可播放的音频版本。');
    }

    final path = '$_cachedLibraryPath/${version.filepath}'.replaceAll('\\', '/');
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('音频文件不存在: $path');
    }

    final clampedPosition =
        totalDuration > Duration.zero && startPosition > totalDuration
            ? totalDuration
            : startPosition;

    await music.startRustPlayback(
      path: path,
      volume: volume,
      pitch: pitchSemitones,
      algo: pitchAlgorithm,
      normalizationGain: _computeNormalizationGain(version),
    );
    if (clampedPosition > Duration.zero) {
      await music.seekRustPlayback(
        secs: clampedPosition.inMilliseconds / 1000.0,
      );
    }

    if (startPaused) {
      await music.pauseRustPlayback();
      isPlaying = false;
      _stopPositionTimer();
    } else {
      isPlaying = true;
      _startPositionTimer();
    }

    currentPosition = clampedPosition;
    totalDuration = Duration(milliseconds: (version.duration * 1000).round());
    _hasPreparedPlayback = true;
    _pendingRestorePosition = null;
    notifyListeners();
    _updateNotification();
    unawaited(_persistPlaybackState());
  }

  double getLMin() {
    double lMin = -15.0; // Moderate default loudness
    bool found = false;
    for (final song in currentQueue) {
      for (final v in song.versions) {
        if (v.isPrimary && v.loudness != null) {
          if (!found || v.loudness! < lMin) {
            lMin = v.loudness!;
            found = true;
          }
        }
      }
    }
    return lMin;
  }

  Future<void> _hotReloadDSP() async {
    if (playingSong != null && playingVersion != null && isPlaying) {
      final pos = currentPosition;
      final path = '$_cachedLibraryPath/${playingVersion!.filepath}'.replaceAll(
        '\\',
        '/',
      );

      await music.startRustPlayback(
        path: path,
        volume: volume,
        pitch: pitchSemitones,
        algo: pitchAlgorithm,
        normalizationGain: _computeNormalizationGain(playingVersion!),
      );
      await music.seekRustPlayback(secs: pos.inMilliseconds / 1000.0);
    }
  }

  void setVolume(double vol) {
    volume = vol;
    music.setRustVolume(vol: vol);
    notifyListeners();
    unawaited(_persistPlaybackState());
  }

  void togglePlayMode() {
    if (playMode == PlayMode.list) {
      playMode = PlayMode.shuffle;
    } else if (playMode == PlayMode.shuffle) {
      playMode = PlayMode.single;
    } else {
      playMode = PlayMode.list;
    }
    notifyListeners();
  }

  Future<void> playPause() async {
    if (isPlaying) {
      await music.pauseRustPlayback();
      isPlaying = false;
      _stopPositionTimer();
    } else {
      if (playingSong != null && playingVersion != null) {
        if (!_hasPreparedPlayback) {
          await _startCurrentVersionPlayback(
            startPosition: _pendingRestorePosition ?? currentPosition,
            startPaused: false,
          );
          return;
        }
        await music.resumeRustPlayback();
        isPlaying = true;
        _startPositionTimer();
      }
    }
    notifyListeners();
    _updateNotification();
    unawaited(_persistPlaybackState());
  }

  Future<void> resume() async {
    if (!isPlaying && playingSong != null && playingVersion != null) {
      if (!_hasPreparedPlayback) {
        await _startCurrentVersionPlayback(
          startPosition: _pendingRestorePosition ?? currentPosition,
          startPaused: false,
        );
        return;
      }
      await music.resumeRustPlayback();
      isPlaying = true;
      _startPositionTimer();
      notifyListeners();
      _updateNotification();
      unawaited(_persistPlaybackState());
    }
  }

  Future<void> seek(Duration position) async {
    final targetPosition =
        totalDuration > Duration.zero && position > totalDuration
            ? totalDuration
            : position;
    if (!_hasPreparedPlayback && playingSong != null && playingVersion != null) {
      currentPosition = targetPosition;
      _pendingRestorePosition = targetPosition;
      notifyListeners();
      unawaited(_persistPlaybackState());
      return;
    }
    await music.seekRustPlayback(secs: targetPosition.inMilliseconds / 1000.0);
    currentPosition = targetPosition;
    notifyListeners();
    _updateNotification();
    unawaited(_persistPlaybackState());
  }

  Future<void> playSong(
    Song song,
    List<Song> queue,
    String libraryPath, {
    int? audioServerPort,
  }) async {
    currentQueue = queue;
    activeSong = song;

    // Find target version
    AudioVersion? targetVersion;
    for (var v in song.versions) {
      if (v.isPrimary && v.isEnabled) {
        targetVersion = v;
        break;
      }
    }

    if (targetVersion == null) {
      for (var v in song.versions) {
        if (v.isEnabled) {
          targetVersion = v;
          break;
        }
      }
    }

    if (targetVersion == null) {
      throw Exception('该歌曲暂无可用的启用音频版本！请先启用至少一个版本。');
    }

    await playSongVersion(
      song,
      targetVersion,
      libraryPath,
      audioServerPort: audioServerPort,
    );
  }

  Future<void> playSongVersion(
    Song song,
    AudioVersion version,
    String libraryPath, {
    int? audioServerPort,
  }) async {
    activeSong = song;
    playingSong = song;
    playingVersion = version;
    _cachedLibraryPath = libraryPath;
    _cachedAudioServerPort = audioServerPort;
    currentPosition = Duration.zero;
    totalDuration = Duration(milliseconds: (version.duration * 1000).round());
    _hasPreparedPlayback = false;
    _pendingRestorePosition = null;
    await _startCurrentVersionPlayback(
      startPosition: Duration.zero,
      startPaused: false,
    );
  }

  void playNext() {
    if (currentQueue.isEmpty || playingSong == null) return;

    int index = currentQueue.indexWhere((s) => s.id == playingSong!.id);
    if (index == -1) return;

    if (playMode == PlayMode.shuffle) {
      final randomIdx = DateTime.now().millisecond % currentQueue.length;
      final nextSong = currentQueue[randomIdx];
      playSong(
        nextSong,
        currentQueue,
        _cachedLibraryPath,
        audioServerPort: _cachedAudioServerPort,
      ).catchError((_) {});
    } else {
      int nextIdx = index + 1;
      if (nextIdx >= currentQueue.length) {
        nextIdx = 0;
      }
      final nextSong = currentQueue[nextIdx];
      playSong(
        nextSong,
        currentQueue,
        _cachedLibraryPath,
        audioServerPort: _cachedAudioServerPort,
      ).catchError((_) {});
    }
  }

  void playPrevious() {
    if (currentQueue.isEmpty || playingSong == null) return;

    int index = currentQueue.indexWhere((s) => s.id == playingSong!.id);
    if (index == -1) return;

    int prevIdx = index - 1;
    if (prevIdx < 0) {
      prevIdx = currentQueue.length - 1;
    }
    final prevSong = currentQueue[prevIdx];
    playSong(
      prevSong,
      currentQueue,
      _cachedLibraryPath,
      audioServerPort: _cachedAudioServerPort,
    ).catchError((_) {});
  }

  void setActiveSong(Song? song) {
    activeSong = song;
    notifyListeners();
  }

  void setDetailOpen(bool open) {
    isDetailOpen = open;
    notifyListeners();
  }

  void setActiveTab(String tab) {
    activeTab = tab;
    notifyListeners();
  }

  void _updateNotification() {
    if (Platform.isAndroid && playingSong != null) {
      NativeAudioHelper.showNotification(
        playingSong!.title,
        playingSong!.artist ?? '未知歌手',
        isPlaying,
      );
    }
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    unawaited(_persistPlaybackState());
    if (Platform.isAndroid) {
      NativeAudioHelper.hideNotification();
    }
    music.stopRustPlayback();
    super.dispose();
  }
}
