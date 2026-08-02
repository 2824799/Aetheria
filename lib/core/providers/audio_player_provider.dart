import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetheria/src/rust/audio/player.dart' show AudioOutputInfo;
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
  static const String _volumeKey = 'aetheria-playback-volume';
  static const String _pitchEnabledKey = 'pitch-enabled';
  static const String _pitchBufferMsKey = 'pitch-buffer-ms';
  static const String _peakProtectionKey = 'peak-protection-enabled';
  static const String _ditherEnabledKey = 'dither-enabled';
  static const String _rubberbandWindowKey = 'rubberband-window';
  static const String _rubberbandFormantKey = 'rubberband-formant-preserved';
  static const String _resamplerQualityKey = 'resampler-quality';
  static const String _outputLatencyModeKey = 'output-latency-mode';
  static const String _developerModeKey = 'developer-mode-enabled';

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
  bool pitchEnabled = false;
  double pitchSemitones = 0.0;
  String pitchAlgorithm = 'rubberband';
  int pitchBufferMs = 240;
  bool peakProtectionEnabled = true;
  bool ditherEnabled = true;
  String rubberbandWindow = 'latency';
  bool rubberbandFormantPreserved = false;
  String resamplerQuality = 'standard';
  String outputLatencyMode = 'shared-default';
  AudioOutputInfo? audioOutputInfo;
  bool developerModeEnabled = false;

  bool isDetailOpen = false;
  String activeTab = 'lyrics';

  String _cachedLibraryPath = '';
  int? _cachedAudioServerPort;
  Timer? _positionTimer;
  Timer? _outputInfoTimer;
  Timer? _audioRouteChangeDebounce;
  int _lastPositionMs = -1;
  int _lastPersistedSecond = -1;
  int _stallTicks = 0;
  bool _isHandlingPlaybackEnd = false;
  bool _hasPreparedPlayback = false;
  Duration? _pendingRestorePosition;
  String? _lastDefaultOutputDeviceName;
  bool _isCheckingOutputDeviceChange = false;

  AudioPlayerProvider() {
    NativeAudioHelper.setNotificationActionHandler(_handleNotificationAction);
    NativeAudioHelper.setAudioRouteChangedHandler(_handleAudioRouteChanged);
    loadSettings();
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _lastPositionMs = -1;
    _lastPersistedSecond = -1;
    _stallTicks = 0;
    _isHandlingPlaybackEnd = false;
    _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (
      timer,
    ) async {
      if (!isPlaying || _isHandlingPlaybackEnd) return;
      final posSec = await music.getRustPlaybackPosition();
      final streamFinished = await music.isRustPlaybackFinished();
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
      final nearEnd =
          totalDuration > Duration.zero &&
          currentPosition >= totalDuration - const Duration(seconds: 2);
      final stalledAtEnd =
          _stallTicks >= 6 && currentPosition > Duration.zero && nearEnd;

      if (streamFinished || reachedEnd || stalledAtEnd) {
        await _handlePlaybackEnded();
        return;
      }
      if (currentPosition.inSeconds != _lastPersistedSecond) {
        _lastPersistedSecond = currentPosition.inSeconds;
        unawaited(_persistPlaybackState());
        _updateNotification();
      }
      notifyListeners();
    });
  }

  Future<void> _handlePlaybackEnded() async {
    if (_isHandlingPlaybackEnd) return;
    _isHandlingPlaybackEnd = true;
    _positionTimer?.cancel();

    try {
      if (playMode == PlayMode.single &&
          playingSong != null &&
          playingVersion != null) {
        currentPosition = Duration.zero;
        _hasPreparedPlayback = false;
        await _startCurrentVersionPlayback(
          startPosition: Duration.zero,
          startPaused: false,
        );
        return;
      }

      playNext();
    } finally {
      _isHandlingPlaybackEnd = false;
    }
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
  }

  void _startOutputInfoTimer() {
    _outputInfoTimer?.cancel();
    unawaited(_refreshOutputInfoAndDeviceChange());
    _outputInfoTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshOutputInfoAndDeviceChange());
    });
  }

  void _stopOutputInfoTimer() {
    _outputInfoTimer?.cancel();
  }

  Future<void> loadSettings() async {
    try {
      if (Platform.isAndroid) {
        await NativeAudioHelper.requestNotificationPermission();
      }
      final prefs = await SharedPreferences.getInstance();
      playAlongside = prefs.getBool('play-alongside') ?? false;
      volume = (prefs.getDouble(_volumeKey) ?? volume)
          .clamp(0.0, 1.0)
          .toDouble();
      volumeBalanceEnabled = prefs.getBool('volume-balance-enabled') ?? false;
      volumeBalanceStrength = prefs.getDouble('volume-balance-strength') ?? 0.5;
      pitchEnabled = prefs.getBool(_pitchEnabledKey) ?? false;
      pitchSemitones = prefs.getDouble('pitch-semitones') ?? 0.0;
      pitchAlgorithm = _normalizePitchAlgorithm(
        prefs.getString('pitch-algorithm'),
      );
      if (prefs.getString('pitch-algorithm') != pitchAlgorithm) {
        await prefs.setString('pitch-algorithm', pitchAlgorithm);
      }
      pitchBufferMs = prefs.getInt(_pitchBufferMsKey) ?? 240;
      peakProtectionEnabled = prefs.getBool(_peakProtectionKey) ?? true;
      ditherEnabled = prefs.getBool(_ditherEnabledKey) ?? true;
      rubberbandWindow = _normalizeRubberbandWindow(
        prefs.getString(_rubberbandWindowKey),
      );
      rubberbandFormantPreserved =
          prefs.getBool(_rubberbandFormantKey) ?? false;
      resamplerQuality = _normalizeResamplerQuality(
        prefs.getString(_resamplerQualityKey),
      );
      outputLatencyMode = _normalizeOutputLatencyMode(
        prefs.getString(_outputLatencyModeKey),
      );
      developerModeEnabled = prefs.getBool(_developerModeKey) ?? false;
      music.setAudioPerformanceProfilingEnabled(enabled: developerModeEnabled);
      await music.setRustOutputBufferMs(ms: pitchBufferMs);
      await music.setRustOutputLatencyMode(mode: outputLatencyMode);
      await music.setRustVolume(vol: volume);
      await _syncAudioQualitySettings();
      await music.setRustPitch(
        pitch: _effectivePitchSemitones,
        algo: pitchAlgorithm,
      );
      await refreshAudioOutputInfo();
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
      await music.setRustPitch(
        pitch: _effectivePitchSemitones,
        algo: pitchAlgorithm,
      );
    } catch (_) {}
  }

  Future<void> setPitchAlgorithm(String value) async {
    final normalized = _normalizePitchAlgorithm(value);
    pitchAlgorithm = normalized;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pitch-algorithm', normalized);
      await music.setRustPitch(
        pitch: _effectivePitchSemitones,
        algo: normalized,
      );
    } catch (_) {}
  }

  Future<void> setPitchEnabled(bool value) async {
    pitchEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_pitchEnabledKey, value);
      await music.setRustPitch(
        pitch: _effectivePitchSemitones,
        algo: pitchAlgorithm,
      );
      await _hotReloadDSP();
    } catch (_) {}
  }

  Future<void> setPitchBufferMs(int value) async {
    pitchBufferMs = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_pitchBufferMsKey, value);
      await music.setRustOutputBufferMs(ms: value);
      await _hotReloadDSP();
    } catch (_) {}
  }

  Future<void> setPeakProtectionEnabled(bool value) async {
    peakProtectionEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_peakProtectionKey, value);
      await _syncAudioQualitySettings();
    } catch (_) {}
  }

  Future<void> setDitherEnabled(bool value) async {
    ditherEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_ditherEnabledKey, value);
      await _syncAudioQualitySettings();
    } catch (_) {}
  }

  Future<void> setRubberbandWindow(String value) async {
    final normalized = _normalizeRubberbandWindow(value);
    rubberbandWindow = normalized;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_rubberbandWindowKey, normalized);
      await _syncAudioQualitySettings();
      await _hotReloadDSP();
    } catch (_) {}
  }

  Future<void> setRubberbandFormantPreserved(bool value) async {
    rubberbandFormantPreserved = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rubberbandFormantKey, value);
      await _syncAudioQualitySettings();
    } catch (_) {}
  }

  Future<void> setResamplerQuality(String value) async {
    final normalized = _normalizeResamplerQuality(value);
    resamplerQuality = normalized;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_resamplerQualityKey, normalized);
      await _syncAudioQualitySettings();
      await _hotReloadDSP();
    } catch (_) {}
  }

  Future<void> setOutputLatencyMode(String value) async {
    final normalized = _normalizeOutputLatencyMode(value);
    outputLatencyMode = normalized;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_outputLatencyModeKey, normalized);
      await music.setRustOutputLatencyMode(mode: normalized);
      await _hotReloadDSP();
      await refreshAudioOutputInfo();
    } catch (_) {}
  }

  Future<void> refreshAudioOutputInfo() async {
    try {
      final next = await music.getRustAudioOutputInfo();
      if (audioOutputInfo != next) {
        audioOutputInfo = next;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _refreshOutputInfoAndDeviceChange() async {
    await refreshAudioOutputInfo();
    await _handleDefaultOutputDeviceChange();
  }

  Future<void> _handleDefaultOutputDeviceChange() async {
    if (Platform.isAndroid || Platform.isIOS || _isCheckingOutputDeviceChange) {
      return;
    }

    _isCheckingOutputDeviceChange = true;
    try {
      final defaultDeviceName = await music.getRustDefaultOutputDeviceName();
      if (defaultDeviceName.isEmpty) {
        return;
      }

      if (_lastDefaultOutputDeviceName == null) {
        _lastDefaultOutputDeviceName = defaultDeviceName;
        return;
      }

      if (_lastDefaultOutputDeviceName == defaultDeviceName) {
        return;
      }

      _lastDefaultOutputDeviceName = defaultDeviceName;
      await _restartPlaybackOnDefaultOutputDevice();
    } catch (_) {
      // Device probing can fail transiently while Windows is switching endpoints.
    } finally {
      _isCheckingOutputDeviceChange = false;
    }
  }

  Future<void> setDeveloperModeEnabled(bool value) async {
    if (developerModeEnabled == value) {
      return;
    }
    developerModeEnabled = value;
    music.setAudioPerformanceProfilingEnabled(enabled: value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_developerModeKey, value);
  }

  Future<void> _handleAudioRouteChanged() async {
    if (!Platform.isAndroid) {
      return;
    }
    _audioRouteChangeDebounce?.cancel();
    _audioRouteChangeDebounce = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(_restartAfterAudioRouteChange()),
    );
  }

  Future<void> _restartAfterAudioRouteChange() async {
    if (_isCheckingOutputDeviceChange) {
      return;
    }
    _isCheckingOutputDeviceChange = true;
    try {
      await _restartPlaybackOnDefaultOutputDevice();
      await refreshAudioOutputInfo();
    } catch (_) {
      // Android can emit several transient route events while switching.
    } finally {
      _isCheckingOutputDeviceChange = false;
    }
  }

  Future<void> _restartPlaybackOnDefaultOutputDevice() async {
    if (playingSong == null ||
        playingVersion == null ||
        !_hasPreparedPlayback ||
        _cachedLibraryPath.isEmpty) {
      return;
    }

    final wasPlaying = isPlaying;
    final position = currentPosition;
    _hasPreparedPlayback = false;
    await _startCurrentVersionPlayback(
      startPosition: position,
      startPaused: !wasPlaying,
    );
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

  double get _effectivePitchSemitones => pitchEnabled ? pitchSemitones : 0.0;

  String _normalizePitchAlgorithm(String? value) {
    return value == 'resample' ? 'resample' : 'rubberband';
  }

  String _normalizeRubberbandWindow(String? value) {
    return value == 'quality' ? 'quality' : 'latency';
  }

  String _normalizeResamplerQuality(String? value) {
    return value == 'high' ? 'high' : 'standard';
  }

  String _normalizeOutputLatencyMode(String? value) {
    return value == 'shared-low-latency' || value == 'shared-stable'
        ? value!
        : 'shared-default';
  }

  Future<void> _syncAudioQualitySettings() {
    return music.setRustAudioQualitySettings(
      peakProtectionEnabled: peakProtectionEnabled,
      ditherEnabled: ditherEnabled,
      rubberbandWindow: rubberbandWindow,
      rubberbandFormantPreserved: rubberbandFormantPreserved,
      resamplerQuality: resamplerQuality,
    );
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

    final path = '$_cachedLibraryPath/${version.filepath}'.replaceAll(
      '\\',
      '/',
    );
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
      pitch: _effectivePitchSemitones,
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
      _startOutputInfoTimer();
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
    if (playingSong == null ||
        playingVersion == null ||
        !_hasPreparedPlayback) {
      return;
    }

    final wasPlaying = isPlaying;
    final pos = currentPosition;
    final path = '$_cachedLibraryPath/${playingVersion!.filepath}'.replaceAll(
      '\\',
      '/',
    );

    await music.startRustPlayback(
      path: path,
      volume: volume,
      pitch: _effectivePitchSemitones,
      algo: pitchAlgorithm,
      normalizationGain: _computeNormalizationGain(playingVersion!),
    );
    await music.seekRustPlayback(secs: pos.inMilliseconds / 1000.0);
    if (wasPlaying) {
      _startOutputInfoTimer();
    } else {
      await music.pauseRustPlayback();
      await refreshAudioOutputInfo();
    }
  }

  void setVolume(double vol) {
    final normalized = vol.clamp(0.0, 1.0).toDouble();
    volume = normalized;
    unawaited(music.setRustVolume(vol: normalized));
    notifyListeners();
    unawaited(_persistVolume());
    _updateNotification();
  }

  Future<void> _persistVolume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_volumeKey, volume);
    } catch (_) {}
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
      _stopOutputInfoTimer();
    } else {
      if (playingSong != null && playingVersion != null) {
        if (!_hasPreparedPlayback) {
          await _startCurrentVersionPlayback(
            startPosition: _pendingRestorePosition ?? currentPosition,
            startPaused: false,
          );
          return;
        }
        await _handleDefaultOutputDeviceChange();
        await music.resumeRustPlayback();
        isPlaying = true;
        _startPositionTimer();
        _startOutputInfoTimer();
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
      await _handleDefaultOutputDeviceChange();
      await music.resumeRustPlayback();
      isPlaying = true;
      _startPositionTimer();
      _startOutputInfoTimer();
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
    if (!_hasPreparedPlayback &&
        playingSong != null &&
        playingVersion != null) {
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

  Future<void> stopForLibrarySync() async {
    _stopPositionTimer();
    _stopOutputInfoTimer();
    await music.stopRustPlayback();
    isPlaying = false;
    _hasPreparedPlayback = false;
    playingSong = null;
    playingVersion = null;
    activeSong = null;
    currentQueue = [];
    currentPosition = Duration.zero;
    totalDuration = Duration.zero;
    _pendingRestorePosition = null;
    notifyListeners();
    _updateNotification();
    try {
      final prefs = await SharedPreferences.getInstance();
      await _clearPersistedPlaybackState(prefs);
    } catch (_) {}
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
      if (v.isPrimary) {
        targetVersion = v;
        break;
      }
    }

    targetVersion ??= song.versions.isNotEmpty ? song.versions.first : null;

    if (targetVersion == null) {
      throw Exception('该歌曲暂无可播放的音源版本。');
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

  Future<void> switchToVersion(
    Song song,
    AudioVersion version,
    String libraryPath, {
    int? audioServerPort,
    Duration? startPosition,
    bool startPaused = false,
  }) async {
    activeSong = song;
    playingSong = song;
    playingVersion = version;
    currentQueue = currentQueue
        .map((entry) => entry.id == song.id ? song : entry)
        .toList(growable: false);
    if (!currentQueue.any((entry) => entry.id == song.id)) {
      currentQueue = <Song>[song];
    }
    _cachedLibraryPath = libraryPath;
    _cachedAudioServerPort = audioServerPort;
    totalDuration = Duration(milliseconds: (version.duration * 1000).round());
    _hasPreparedPlayback = false;
    _pendingRestorePosition = null;
    await _startCurrentVersionPlayback(
      startPosition: startPosition ?? currentPosition,
      startPaused: startPaused,
    );
  }

  void syncSongSnapshot(Song song) {
    var changed = false;
    if (activeSong?.id == song.id) {
      activeSong = song;
      changed = true;
    }
    if (playingSong?.id == song.id) {
      playingSong = song;
      changed = true;
    }
    final nextQueue = currentQueue
        .map((entry) => entry.id == song.id ? song : entry)
        .toList(growable: false);
    if (nextQueue.length == currentQueue.length) {
      currentQueue = nextQueue;
    }
    if (changed) {
      notifyListeners();
      _updateNotification();
      unawaited(_persistPlaybackState());
    }
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

  bool _hasPreviousInQueue() {
    if (currentQueue.isEmpty || playingSong == null) {
      return false;
    }
    return currentQueue.length > 1;
  }

  bool _hasNextInQueue() {
    if (currentQueue.isEmpty || playingSong == null) {
      return false;
    }
    return currentQueue.length > 1;
  }

  Future<void> _handleNotificationAction(String action) async {
    if (action.startsWith('seek:')) {
      final positionMs = int.tryParse(action.substring('seek:'.length));
      if (positionMs != null) {
        await seek(Duration(milliseconds: positionMs));
      }
      return;
    }

    switch (action) {
      case 'previous':
        playPrevious();
        break;
      case 'toggle':
        await playPause();
        break;
      case 'next':
        playNext();
        break;
      default:
        break;
    }
  }

  String? _currentPlayingAudioPath() {
    final version = playingVersion;
    if (version == null || _cachedLibraryPath.isEmpty) {
      return null;
    }
    return '$_cachedLibraryPath/${version.filepath}'.replaceAll('\\', '/');
  }

  void _updateNotification() {
    if (Platform.isAndroid && playingSong != null) {
      final audioPath = _currentPlayingAudioPath();
      final payload = <String, dynamic>{
        'title': playingSong!.title,
        'artist': playingSong!.artist ?? '未知歌手',
        'isPlaying': isPlaying,
        'positionMs': currentPosition.inMilliseconds,
        'durationMs': totalDuration.inMilliseconds,
        'hasPrevious': _hasPreviousInQueue(),
        'hasNext': _hasNextInQueue(),
      };
      if (audioPath != null) {
        payload['audioPath'] = audioPath;
      }
      unawaited(NativeAudioHelper.showNotification(payload));
    }
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _outputInfoTimer?.cancel();
    _audioRouteChangeDebounce?.cancel();
    unawaited(_persistPlaybackState());
    if (Platform.isAndroid) {
      NativeAudioHelper.hideNotification();
    }
    music.stopRustPlayback();
    super.dispose();
  }
}
