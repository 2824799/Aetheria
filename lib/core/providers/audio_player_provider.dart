import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:aetheria/core/utils/library_paths.dart';
import 'package:aetheria/services/native_audio_helper.dart';
import 'package:aetheria/src/rust/api/playback.dart' as playback;
import 'package:aetheria/src/rust/audio/player.dart' show AudioOutputInfo;
import 'package:aetheria/src/rust/models/song.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PlayMode { list, single, shuffle }

/// Owns playback state (queue, position, DSP settings) and drives the Rust
/// audio engine.
class AudioPlayerProvider extends ChangeNotifier {
  static const String _playbackSongIdKey = 'aetheria-playback-song-id';
  static const String _playbackVersionIdKey = 'aetheria-playback-version-id';
  static const String _playbackPositionMsKey = 'aetheria-playback-position-ms';
  static const String _playbackQueueIdsKey = 'aetheria-playback-queue-ids';
  static const String _volumeKey = 'aetheria-playback-volume';
  static const String _playAlongsideKey = 'play-alongside';
  static const String _volumeBalanceEnabledKey = 'volume-balance-enabled';
  static const String _volumeBalanceStrengthKey = 'volume-balance-strength';
  static const String _pitchEnabledKey = 'pitch-enabled';
  static const String _pitchSemitonesKey = 'pitch-semitones';
  static const String _pitchAlgorithmKey = 'pitch-algorithm';
  static const String _pitchBufferMsKey = 'pitch-buffer-ms';
  static const String _peakProtectionKey = 'peak-protection-enabled';
  static const String _ditherEnabledKey = 'dither-enabled';
  static const String _rubberbandWindowKey = 'rubberband-window';
  static const String _rubberbandFormantKey = 'rubberband-formant-preserved';
  static const String _rubberbandVocalOnlyKey = 'rubberband-vocal-only-pitch';
  static const String _resamplerQualityKey = 'resampler-quality';
  static const String _outputLatencyModeKey = 'output-latency-mode';
  static const String _developerModeKey = 'developer-mode-enabled';

  /// Loudness assumed for versions that have not been measured, in dBFS.
  static const double _defaultLoudnessDb = -15.0;

  static const Duration _positionPollInterval = Duration(milliseconds: 250);

  /// Consecutive unchanged position polls near the end that count as EOF.
  static const int _stallTicksAtEnd = 6;

  Song? activeSong;
  Song? playingSong;
  AudioVersion? playingVersion;

  List<Song> currentQueue = [];

  bool isPlaying = false;
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  ValueListenable<Duration> get positionListenable => _position;
  Duration get currentPosition => _position.value;
  set currentPosition(Duration value) => _position.value = value;
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
  bool rubberbandVocalOnlyPitch = false;
  String resamplerQuality = 'high';
  String outputLatencyMode = 'shared-default';
  AudioOutputInfo? audioOutputInfo;
  bool developerModeEnabled = false;

  bool isDetailOpen = false;
  String activeTab = 'lyrics';

  final math.Random _random = math.Random();
  String _libraryPath = '';
  Timer? _positionTimer;
  Timer? _outputInfoTimer;
  Timer? _audioRouteChangeDebounce;
  int _lastPositionMs = -1;
  int _lastPersistedSecond = -1;
  int _stallTicks = 0;
  bool _isHandlingPlaybackEnd = false;
  bool _pollingPosition = false;
  bool _disposed = false;

  /// Whether the engine holds a stream for [playingVersion]. False after a
  /// restore or a failed start, in which case "play" opens the stream first.
  bool _hasPreparedPlayback = false;
  Duration? _pendingRestorePosition;
  String? _lastDefaultOutputDeviceName;
  bool _isCheckingOutputDeviceChange = false;

  /// Identifies the newest stream start; older ones abandon their work.
  int _streamRequest = 0;
  Future<void> _streamStart = Future<void>.value();

  AudioPlayerProvider() {
    NativeAudioHelper.setNotificationActionHandler(_handleNotificationAction);
    NativeAudioHelper.setAudioRouteChangedHandler(_handleAudioRouteChanged);
    loadSettings();
  }

  @override
  void notifyListeners() {
    // Async work (settings load, engine calls) can finish after disposal.
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  // ---- Settings ----

  Future<void> loadSettings() async {
    try {
      if (Platform.isAndroid) {
        await NativeAudioHelper.requestNotificationPermission();
      }
      final prefs = await SharedPreferences.getInstance();
      await _readPreferences(prefs);
      notifyListeners();
      await _pushSettingsToEngine();
      await refreshAudioOutputInfo();
    } catch (error) {
      debugPrint('Failed to load audio settings: $error');
    }
  }

  Future<void> _readPreferences(SharedPreferences prefs) async {
    playAlongside = prefs.getBool(_playAlongsideKey) ?? false;
    volume = (prefs.getDouble(_volumeKey) ?? volume).clamp(0.0, 1.0).toDouble();
    volumeBalanceEnabled = prefs.getBool(_volumeBalanceEnabledKey) ?? false;
    volumeBalanceStrength = prefs.getDouble(_volumeBalanceStrengthKey) ?? 0.5;
    pitchEnabled = prefs.getBool(_pitchEnabledKey) ?? false;
    pitchSemitones = prefs.getDouble(_pitchSemitonesKey) ?? 0.0;
    final savedAlgorithm = prefs.getString(_pitchAlgorithmKey);
    pitchAlgorithm = _normalizePitchAlgorithm(savedAlgorithm);
    if (savedAlgorithm != pitchAlgorithm) {
      // Migrates algorithms removed from the engine to the default.
      await prefs.setString(_pitchAlgorithmKey, pitchAlgorithm);
    }
    pitchBufferMs = prefs.getInt(_pitchBufferMsKey) ?? 240;
    peakProtectionEnabled = prefs.getBool(_peakProtectionKey) ?? true;
    ditherEnabled = prefs.getBool(_ditherEnabledKey) ?? true;
    rubberbandWindow = _normalizeRubberbandWindow(
      prefs.getString(_rubberbandWindowKey),
    );
    rubberbandFormantPreserved = prefs.getBool(_rubberbandFormantKey) ?? false;
    rubberbandVocalOnlyPitch = prefs.getBool(_rubberbandVocalOnlyKey) ?? false;
    resamplerQuality = _normalizeResamplerQuality(
      prefs.getString(_resamplerQualityKey),
    );
    outputLatencyMode = _normalizeOutputLatencyMode(
      prefs.getString(_outputLatencyModeKey),
    );
    developerModeEnabled = prefs.getBool(_developerModeKey) ?? false;
  }

  Future<void> _pushSettingsToEngine() async {
    playback.setAudioPerformanceProfilingEnabled(enabled: developerModeEnabled);
    await playback.setOutputBufferMs(ms: pitchBufferMs);
    await playback.setOutputLatencyMode(mode: outputLatencyMode);
    await playback.setVolume(volume: volume);
    await _pushQualitySettings();
    await _pushPitch();
  }

  /// Announces a changed setting, persists it and forwards it to the engine.
  ///
  /// Settings are best-effort: a failure keeps the in-memory value so the UI
  /// stays responsive, and the next engine start picks it up.
  Future<void> _applySetting({
    required Future<Object?> Function(SharedPreferences prefs) persist,
    Future<void> Function()? push,
    bool restartStream = false,
  }) async {
    notifyListeners();
    try {
      await persist(await SharedPreferences.getInstance());
      await push?.call();
      if (restartStream) {
        await _restartStream();
      }
    } catch (error) {
      debugPrint('Failed to apply audio setting: $error');
    }
  }

  Future<void> setPlayAlongside(bool value) {
    playAlongside = value;
    return _applySetting(
      persist: (prefs) => prefs.setBool(_playAlongsideKey, value),
    );
  }

  Future<void> setVolumeBalanceEnabled(bool value) {
    volumeBalanceEnabled = value;
    return _applySetting(
      persist: (prefs) => prefs.setBool(_volumeBalanceEnabledKey, value),
      restartStream: true,
    );
  }

  Future<void> setVolumeBalanceStrength(double value) {
    volumeBalanceStrength = value;
    return _applySetting(
      persist: (prefs) => prefs.setDouble(_volumeBalanceStrengthKey, value),
      restartStream: true,
    );
  }

  Future<void> setPitchSemitones(double value) {
    pitchSemitones = value;
    return _applySetting(
      persist: (prefs) => prefs.setDouble(_pitchSemitonesKey, value),
      push: _pushPitch,
    );
  }

  Future<void> setPitchAlgorithm(String value) {
    pitchAlgorithm = _normalizePitchAlgorithm(value);
    return _applySetting(
      persist: (prefs) => prefs.setString(_pitchAlgorithmKey, pitchAlgorithm),
      push: _pushPitch,
    );
  }

  Future<void> setPitchEnabled(bool value) {
    pitchEnabled = value;
    return _applySetting(
      persist: (prefs) => prefs.setBool(_pitchEnabledKey, value),
      push: _pushPitch,
      restartStream: true,
    );
  }

  Future<void> setPitchBufferMs(int value) {
    pitchBufferMs = value;
    return _applySetting(
      persist: (prefs) => prefs.setInt(_pitchBufferMsKey, value),
      push: () => playback.setOutputBufferMs(ms: value),
      restartStream: true,
    );
  }

  Future<void> setPeakProtectionEnabled(bool value) {
    peakProtectionEnabled = value;
    return _applySetting(
      persist: (prefs) => prefs.setBool(_peakProtectionKey, value),
      push: _pushQualitySettings,
    );
  }

  Future<void> setDitherEnabled(bool value) {
    ditherEnabled = value;
    return _applySetting(
      persist: (prefs) => prefs.setBool(_ditherEnabledKey, value),
      push: _pushQualitySettings,
    );
  }

  Future<void> setRubberbandWindow(String value) {
    rubberbandWindow = _normalizeRubberbandWindow(value);
    return _applySetting(
      persist: (prefs) =>
          prefs.setString(_rubberbandWindowKey, rubberbandWindow),
      push: _pushQualitySettings,
      restartStream: true,
    );
  }

  Future<void> setRubberbandFormantPreserved(bool value) {
    rubberbandFormantPreserved = value;
    return _applySetting(
      persist: (prefs) => prefs.setBool(_rubberbandFormantKey, value),
      push: _pushQualitySettings,
    );
  }

  Future<void> setRubberbandVocalOnlyPitch(bool value) {
    rubberbandVocalOnlyPitch = value;
    return _applySetting(
      persist: (prefs) => prefs.setBool(_rubberbandVocalOnlyKey, value),
      push: _pushQualitySettings,
      restartStream: true,
    );
  }

  Future<void> setResamplerQuality(String value) {
    resamplerQuality = _normalizeResamplerQuality(value);
    return _applySetting(
      persist: (prefs) =>
          prefs.setString(_resamplerQualityKey, resamplerQuality),
      push: _pushQualitySettings,
      restartStream: true,
    );
  }

  Future<void> setOutputLatencyMode(String value) async {
    outputLatencyMode = _normalizeOutputLatencyMode(value);
    await _applySetting(
      persist: (prefs) =>
          prefs.setString(_outputLatencyModeKey, outputLatencyMode),
      push: () => playback.setOutputLatencyMode(mode: outputLatencyMode),
      restartStream: true,
    );
    await refreshAudioOutputInfo();
  }

  Future<void> setDeveloperModeEnabled(bool value) async {
    if (developerModeEnabled == value) {
      return;
    }
    developerModeEnabled = value;
    playback.setAudioPerformanceProfilingEnabled(enabled: value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_developerModeKey, value);
  }

  void setVolume(double value) {
    volume = value.clamp(0.0, 1.0).toDouble();
    notifyListeners();
    unawaited(_applyVolume());
    _updateNotification();
  }

  Future<void> _applyVolume() async {
    try {
      await playback.setVolume(volume: volume);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_volumeKey, volume);
    } catch (error) {
      debugPrint('Failed to apply volume: $error');
    }
  }

  double get _effectivePitchSemitones => pitchEnabled ? pitchSemitones : 0.0;

  Future<void> _pushPitch() {
    return playback.setPitch(
      pitch: _effectivePitchSemitones,
      algo: pitchAlgorithm,
    );
  }

  Future<void> _pushQualitySettings() {
    return playback.setAudioQualitySettings(
      peakProtectionEnabled: peakProtectionEnabled,
      ditherEnabled: ditherEnabled,
      rubberbandWindow: rubberbandWindow,
      rubberbandFormantPreserved: rubberbandFormantPreserved,
      rubberbandVocalOnlyPitch: rubberbandVocalOnlyPitch,
      resamplerQuality: resamplerQuality,
    );
  }

  static String _normalizePitchAlgorithm(String? value) {
    return value == 'resample' ? 'resample' : 'rubberband';
  }

  static String _normalizeRubberbandWindow(String? value) {
    return value == 'quality' ? 'quality' : 'latency';
  }

  static String _normalizeResamplerQuality(String? value) {
    return value == 'standard' ? 'standard' : 'high';
  }

  static String _normalizeOutputLatencyMode(String? value) {
    return value == 'shared-low-latency' || value == 'shared-stable'
        ? value!
        : 'shared-default';
  }

  // ---- Output device ----

  Future<void> refreshAudioOutputInfo() async {
    try {
      final next = await playback.getAudioOutputInfo();
      if (audioOutputInfo != next) {
        audioOutputInfo = next;
        notifyListeners();
      }
    } catch (_) {
      // The info panel simply keeps its last snapshot.
    }
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

  Future<void> _refreshOutputInfoAndDeviceChange() async {
    await refreshAudioOutputInfo();
    await _handleDefaultOutputDeviceChange();
  }

  /// Desktop: follows the system default device when the user switches it.
  Future<void> _handleDefaultOutputDeviceChange() async {
    if (Platform.isAndroid || Platform.isIOS || _isCheckingOutputDeviceChange) {
      return;
    }

    _isCheckingOutputDeviceChange = true;
    try {
      final deviceName = await playback.getDefaultOutputDeviceName();
      if (deviceName.isEmpty || deviceName == _lastDefaultOutputDeviceName) {
        return;
      }
      final isFirstProbe = _lastDefaultOutputDeviceName == null;
      _lastDefaultOutputDeviceName = deviceName;
      if (!isFirstProbe) {
        await _restartStream();
      }
    } catch (_) {
      // Device probing can fail transiently while Windows is switching endpoints.
    } finally {
      _isCheckingOutputDeviceChange = false;
    }
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
      await _restartStream();
      await refreshAudioOutputInfo();
    } catch (_) {
      // Android can emit several transient route events while switching.
    } finally {
      _isCheckingOutputDeviceChange = false;
    }
  }

  // ---- Engine stream ----

  String _audioPath(AudioVersion version) {
    return managedAudioPath(_libraryPath, version.filepath) ??
        (throw const FormatException('音乐库中的音频文件名无效。'));
  }

  /// Gain that pulls louder tracks down towards the quietest primary version
  /// in the queue, scaled by [volumeBalanceStrength].
  double _normalizationGain(AudioVersion version) {
    if (!volumeBalanceEnabled) {
      return 1.0;
    }
    final target = _quietestPrimaryLoudness();
    final loudness = version.loudness ?? _defaultLoudnessDb;
    if (loudness <= target) {
      return 1.0;
    }
    final deltaDb = volumeBalanceStrength * (target - loudness);
    return math.pow(10, deltaDb / 20).toDouble();
  }

  double _quietestPrimaryLoudness() {
    double? quietest;
    for (final song in currentQueue) {
      for (final version in song.versions) {
        final loudness = version.loudness;
        if (version.isPrimary &&
            loudness != null &&
            (quietest == null || loudness < quietest)) {
          quietest = loudness;
        }
      }
    }
    return quietest ?? _defaultLoudnessDb;
  }

  /// Reopens the current stream at the current position so settings that are
  /// fixed at stream start (device, buffer, gain, resampler) take effect.
  Future<void> _restartStream() async {
    if (playingSong == null ||
        playingVersion == null ||
        !_hasPreparedPlayback ||
        _libraryPath.isEmpty) {
      return;
    }
    await _startStream(startPosition: currentPosition, startPaused: !isPlaying);
  }

  /// Opens an engine stream for [playingVersion].
  ///
  /// Starts are serialized and only the newest one proceeds, so skipping
  /// quickly through songs can never leave an older song playing or seek the
  /// new song to a stale position.
  Future<void> _startStream({
    required Duration startPosition,
    required bool startPaused,
  }) async {
    final request = ++_streamRequest;
    final previous = _streamStart;
    final done = Completer<void>();
    _streamStart = done.future;
    try {
      await previous;
      if (request == _streamRequest && !_disposed) {
        await _openStream(request, startPosition, startPaused);
      }
    } finally {
      done.complete();
    }
  }

  Future<void> _openStream(
    int request,
    Duration startPosition,
    bool startPaused,
  ) async {
    bool superseded() => request != _streamRequest || _disposed;

    final version = playingVersion;
    if (version == null) {
      throw Exception('当前没有可播放的音频版本。');
    }
    final duration = Duration(milliseconds: (version.duration * 1000).round());
    final position = duration > Duration.zero && startPosition > duration
        ? duration
        : startPosition;
    _hasPreparedPlayback = false;
    try {
      final path = _audioPath(version);
      if (!await File(path).exists()) {
        throw Exception('音频文件不存在: $path');
      }
      if (superseded()) return;
      await playback.startPlayback(
        path: path,
        volume: volume,
        pitch: _effectivePitchSemitones,
        algo: pitchAlgorithm,
        normalizationGain: _normalizationGain(version),
      );
      if (superseded()) return;
      if (position > Duration.zero) {
        await playback.seekPlayback(secs: position.inMilliseconds / 1000.0);
      }
      if (startPaused) {
        await playback.pausePlayback();
      }
    } catch (_) {
      if (!superseded()) {
        await _haltAfterFailedStart();
      }
      rethrow;
    }
    if (superseded()) return;

    isPlaying = !startPaused;
    if (startPaused) {
      _stopPositionTimer();
      unawaited(refreshAudioOutputInfo());
    } else {
      _startPositionTimer();
      _startOutputInfoTimer();
    }
    currentPosition = position;
    totalDuration = duration;
    _hasPreparedPlayback = true;
    _pendingRestorePosition = null;
    _publishPlaybackState();
  }

  /// Leaves a consistent "selected but not playing" state when a stream could
  /// not be opened; pressing play retries.
  Future<void> _haltAfterFailedStart() async {
    try {
      await playback.stopPlayback();
    } catch (_) {
      // Nothing more can be done; the UI state below is still accurate.
    }
    isPlaying = false;
    _stopPositionTimer();
    _stopOutputInfoTimer();
    notifyListeners();
    _updateNotification();
  }

  // ---- Position tracking ----

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _lastPositionMs = -1;
    _lastPersistedSecond = -1;
    _stallTicks = 0;
    _isHandlingPlaybackEnd = false;
    _positionTimer = Timer.periodic(_positionPollInterval, _pollPosition);
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
  }

  Future<void> _pollPosition(Timer timer) async {
    if (!isPlaying || _isHandlingPlaybackEnd || _pollingPosition) return;
    _pollingPosition = true;
    try {
      final progress = await playback.getPlaybackProgress();
      if (!timer.isActive || !isPlaying) return;
      currentPosition = Duration(
        milliseconds: (progress.positionSecs * 1000).round(),
      );

      final hasDuration = totalDuration > Duration.zero;
      final reachedEnd = hasDuration && currentPosition >= totalDuration;

      // The engine position counts samples the hardware consumed, so when the
      // stored duration is slightly too long the position plateaus just short
      // of it once the stream ends. Treat that stall as the end as well.
      final positionMs = currentPosition.inMilliseconds;
      if (positionMs == _lastPositionMs) {
        _stallTicks += 1;
      } else {
        _stallTicks = 0;
        _lastPositionMs = positionMs;
      }
      final nearEnd =
          hasDuration &&
          currentPosition >= totalDuration - const Duration(seconds: 2);
      final stalledAtEnd =
          _stallTicks >= _stallTicksAtEnd &&
          currentPosition > Duration.zero &&
          nearEnd;

      if (progress.finished || reachedEnd || stalledAtEnd) {
        await _handlePlaybackEnded();
        return;
      }
      if (currentPosition.inSeconds != _lastPersistedSecond) {
        _lastPersistedSecond = currentPosition.inSeconds;
        unawaited(_persistPlaybackPosition());
        _updateNotification();
      }
    } catch (error) {
      debugPrint('Failed to poll playback position: $error');
    } finally {
      _pollingPosition = false;
    }
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
        await _startStream(startPosition: Duration.zero, startPaused: false);
      } else {
        playNext();
      }
    } catch (error) {
      debugPrint('Failed to continue playback: $error');
    } finally {
      _isHandlingPlaybackEnd = false;
    }
  }

  // ---- Persistence ----

  Future<void> _clearPersistedPlaybackState(SharedPreferences prefs) async {
    await prefs.remove(_playbackSongIdKey);
    await prefs.remove(_playbackVersionIdKey);
    await prefs.remove(_playbackPositionMsKey);
    await prefs.remove(_playbackQueueIdsKey);
  }

  Future<void> _persistPlaybackPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _playbackPositionMsKey,
        currentPosition.inMilliseconds,
      );
    } catch (_) {
      // Losing one position sample is harmless.
    }
  }

  Future<void> _persistPlaybackState() async {
    final song = playingSong;
    final version = playingVersion;
    final positionMs = currentPosition.inMilliseconds;
    final queueIds = currentQueue
        .map((entry) => entry.id)
        .toList(growable: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (song == null || version == null) {
        await _clearPersistedPlaybackState(prefs);
        return;
      }
      await prefs.setString(_playbackSongIdKey, song.id);
      await prefs.setString(_playbackVersionIdKey, version.id);
      await prefs.setInt(_playbackPositionMsKey, positionMs);
      await prefs.setStringList(_playbackQueueIdsKey, queueIds);
    } catch (_) {
      // Resume-after-restart is a convenience; never fail playback over it.
    }
  }

  /// Restores the song, version, queue and position saved by the last
  /// session. The stream itself is opened lazily on the first "play".
  Future<void> restorePlaybackState(
    List<Song> librarySongs,
    String libraryPath,
  ) async {
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

      final songsById = {for (final song in librarySongs) song.id: song};
      final song = songsById[songId];
      final version = song?.versions
          .where((version) => version.id == versionId)
          .firstOrNull;
      if (song == null || version == null) {
        await _clearPersistedPlaybackState(prefs);
        return;
      }

      final queueIds = <String>{...?prefs.getStringList(_playbackQueueIdsKey)};
      final queue = <Song>[
        if (!queueIds.contains(song.id)) song,
        for (final id in queueIds) ?songsById[id],
      ];

      activeSong = song;
      playingSong = song;
      playingVersion = version;
      currentQueue = queue;
      _libraryPath = libraryPath;

      totalDuration = Duration(milliseconds: (version.duration * 1000).round());
      final savedPosition = Duration(
        milliseconds: prefs.getInt(_playbackPositionMsKey) ?? 0,
      );
      currentPosition =
          totalDuration > Duration.zero && savedPosition > totalDuration
          ? totalDuration
          : savedPosition;

      isPlaying = false;
      _hasPreparedPlayback = false;
      _pendingRestorePosition = currentPosition;
      notifyListeners();
      _updateNotification();
    } catch (error) {
      debugPrint('Failed to restore playback state: $error');
    }
  }

  // ---- Transport ----

  Future<void> playPause() => isPlaying ? pause() : resume();

  Future<void> pause() async {
    if (!isPlaying) {
      return;
    }
    await playback.pausePlayback();
    isPlaying = false;
    _stopPositionTimer();
    _stopOutputInfoTimer();
    _publishPlaybackState();
  }

  Future<void> resume() async {
    if (isPlaying || playingSong == null || playingVersion == null) {
      return;
    }
    if (!_hasPreparedPlayback) {
      await _startStream(
        startPosition: _pendingRestorePosition ?? currentPosition,
        startPaused: false,
      );
      return;
    }
    await _handleDefaultOutputDeviceChange();
    await playback.resumePlayback();
    isPlaying = true;
    _startPositionTimer();
    _startOutputInfoTimer();
    _publishPlaybackState();
  }

  Future<void> seek(Duration position) async {
    final target = totalDuration > Duration.zero && position > totalDuration
        ? totalDuration
        : position;
    if (!_hasPreparedPlayback &&
        playingSong != null &&
        playingVersion != null) {
      // No stream yet (restored session): remember where to start instead.
      currentPosition = target;
      _pendingRestorePosition = target;
      notifyListeners();
      unawaited(_persistPlaybackState());
      return;
    }
    await playback.seekPlayback(secs: target.inMilliseconds / 1000.0);
    currentPosition = target;
    _publishPlaybackState();
  }

  /// Releases every audio file before LAN sync replaces the library on disk.
  Future<void> stopForLibrarySync() async {
    final stopping = _stopStream();
    _stopPositionTimer();
    _stopOutputInfoTimer();
    isPlaying = false;
    _hasPreparedPlayback = false;
    playingSong = null;
    playingVersion = null;
    activeSong = null;
    currentQueue = [];
    currentPosition = Duration.zero;
    totalDuration = Duration.zero;
    _pendingRestorePosition = null;
    await stopping;
    _publishPlaybackState();
  }

  /// Queue the stop behind any native open already in flight. A stop that
  /// overtakes an open would let that open recreate the stream afterwards.
  Future<void> _stopStream() async {
    _streamRequest++;
    final previous = _streamStart;
    final done = Completer<void>();
    _streamStart = done.future;
    try {
      await previous;
      await playback.stopPlayback();
    } finally {
      done.complete();
    }
  }

  /// Plays the primary version of [song] with [queue] as the play queue.
  Future<void> playSong(Song song, List<Song> queue, String libraryPath) async {
    currentQueue = queue;
    activeSong = song;
    final version =
        song.versions.where((version) => version.isPrimary).firstOrNull ??
        song.versions.firstOrNull;
    if (version == null) {
      throw Exception('该歌曲暂无可播放的音源版本。');
    }
    await playSongVersion(song, version, libraryPath);
  }

  Future<void> playSongVersion(
    Song song,
    AudioVersion version,
    String libraryPath,
  ) {
    _selectVersion(song, version, libraryPath);
    currentPosition = Duration.zero;
    return _startStream(startPosition: Duration.zero, startPaused: false);
  }

  /// Switches the playing song to another of its versions, keeping the
  /// position unless [startPosition] says otherwise.
  Future<void> switchToVersion(
    Song song,
    AudioVersion version,
    String libraryPath, {
    Duration? startPosition,
    bool startPaused = false,
  }) {
    currentQueue = currentQueue.any((entry) => entry.id == song.id)
        ? _queueWith(song)
        : <Song>[song];
    _selectVersion(song, version, libraryPath);
    return _startStream(
      startPosition: startPosition ?? currentPosition,
      startPaused: startPaused,
    );
  }

  void _selectVersion(Song song, AudioVersion version, String libraryPath) {
    activeSong = song;
    playingSong = song;
    playingVersion = version;
    _libraryPath = libraryPath;
    totalDuration = Duration(milliseconds: (version.duration * 1000).round());
    _hasPreparedPlayback = false;
    _pendingRestorePosition = null;
  }

  List<Song> _queueWith(Song song) {
    return currentQueue
        .map((entry) => entry.id == song.id ? song : entry)
        .toList(growable: false);
  }

  /// Replaces stale copies of [song] after the library edited it.
  void syncSongSnapshot(Song song) {
    currentQueue = _queueWith(song);
    final isActive = activeSong?.id == song.id;
    final isPlayingSong = playingSong?.id == song.id;
    if (isActive) {
      activeSong = song;
    }
    if (isPlayingSong) {
      playingSong = song;
    }
    if (isActive || isPlayingSong) {
      _publishPlaybackState();
    }
  }

  void playNext() => _skip(forward: true);

  void playPrevious() => _skip(forward: false);

  void _skip({required bool forward}) {
    final current = playingSong;
    if (current == null) return;
    final index = currentQueue.indexWhere((song) => song.id == current.id);
    if (index == -1) return;

    final length = currentQueue.length;
    final int target;
    if (forward && playMode == PlayMode.shuffle && length > 1) {
      // Draw from the other songs so shuffle never repeats the current one.
      final offset = 1 + _random.nextInt(length - 1);
      target = (index + offset) % length;
    } else {
      target = (index + (forward ? 1 : -1)) % length;
    }
    unawaited(_playFromQueue(currentQueue[target]));
  }

  Future<void> _playFromQueue(Song song) async {
    try {
      await playSong(song, currentQueue, _libraryPath);
    } catch (error) {
      debugPrint('Failed to play "${song.title}": $error');
    }
  }

  void togglePlayMode() {
    playMode = switch (playMode) {
      PlayMode.list => PlayMode.shuffle,
      PlayMode.shuffle => PlayMode.single,
      PlayMode.single => PlayMode.list,
    };
    notifyListeners();
  }

  // ---- Detail pane ----

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

  // ---- System notification (Android) ----

  void _publishPlaybackState() {
    notifyListeners();
    _updateNotification();
    unawaited(_persistPlaybackState());
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
      case 'toggle':
        await playPause();
      case 'next':
        playNext();
    }
  }

  void _updateNotification() {
    final song = playingSong;
    if (!Platform.isAndroid || song == null) {
      return;
    }
    final version = playingVersion;
    final canSkip = currentQueue.length > 1;
    final audioPath = version == null
        ? null
        : managedAudioPath(_libraryPath, version.filepath);
    unawaited(
      NativeAudioHelper.showNotification(<String, dynamic>{
        'title': song.title,
        'artist': song.artist ?? '未知歌手',
        'isPlaying': isPlaying,
        'positionMs': currentPosition.inMilliseconds,
        'durationMs': totalDuration.inMilliseconds,
        'hasPrevious': canSkip,
        'hasNext': canSkip,
        'audioPath': ?audioPath,
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _positionTimer?.cancel();
    _outputInfoTimer?.cancel();
    _audioRouteChangeDebounce?.cancel();
    unawaited(_persistPlaybackState());
    if (Platform.isAndroid) {
      NativeAudioHelper.hideNotification();
    }
    unawaited(_stopStream());
    _position.dispose();
    super.dispose();
  }
}
