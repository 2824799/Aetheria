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
  int _stallTicks = 0;

  AudioPlayerProvider() {
    loadSettings();
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _lastPositionMs = -1;
    _stallTicks = 0;
    _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) async {
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
      final path = '$_cachedLibraryPath/${playingVersion!.filepath}'.replaceAll('\\', '/');
      
      double normGain = 1.0;
      if (volumeBalanceEnabled) {
        final lMin = getLMin();
        final lSong = playingVersion!.loudness ?? -15.0;
        if (lSong > lMin) {
          final deltaDb = volumeBalanceStrength * (lMin - lSong);
          normGain = math.pow(10, deltaDb / 20).toDouble();
        }
      }
      
      await music.startRustPlayback(
        path: path,
        volume: volume,
        pitch: pitchSemitones,
        algo: pitchAlgorithm,
        normalizationGain: normGain,
      );
      await music.seekRustPlayback(secs: pos.inMilliseconds / 1000.0);
    }
  }

  void setVolume(double vol) {
    volume = vol;
    music.setRustVolume(vol: vol);
    notifyListeners();
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
        await music.resumeRustPlayback();
        isPlaying = true;
        _startPositionTimer();
      }
    }
    notifyListeners();
    _updateNotification();
  }

  Future<void> resume() async {
    if (!isPlaying && playingSong != null && playingVersion != null) {
      await music.resumeRustPlayback();
      isPlaying = true;
      _startPositionTimer();
      notifyListeners();
      _updateNotification();
    }
  }

  Future<void> seek(Duration position) async {
    await music.seekRustPlayback(secs: position.inMilliseconds / 1000.0);
    currentPosition = position;
    notifyListeners();
  }

  Future<void> playSong(Song song, List<Song> queue, String libraryPath, {int? audioServerPort}) async {
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
    
    await playSongVersion(song, targetVersion, libraryPath, audioServerPort: audioServerPort);
  }

  Future<void> playSongVersion(Song song, AudioVersion version, String libraryPath, {int? audioServerPort}) async {
    activeSong = song;
    playingSong = song;
    playingVersion = version;
    _cachedLibraryPath = libraryPath;
    _cachedAudioServerPort = audioServerPort;
    currentPosition = Duration.zero;
    totalDuration = Duration.zero;
    
    final path = '$libraryPath/${version.filepath}'.replaceAll('\\', '/');
    
    // Check local file exists
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('音频文件不存在: $path');
    }
    
    // Calculate volume normalization gain
    double normGain = 1.0;
    if (volumeBalanceEnabled) {
      final lMin = getLMin();
      final lSong = version.loudness ?? -15.0;
      if (lSong > lMin) {
        final deltaDb = volumeBalanceStrength * (lMin - lSong);
        normGain = math.pow(10, deltaDb / 20).toDouble();
      }
    }
    
    // Start streaming playback in Rust via CPAL
    await music.startRustPlayback(
      path: path,
      volume: volume,
      pitch: pitchSemitones,
      algo: pitchAlgorithm,
      normalizationGain: normGain,
    );
    
    isPlaying = true;
    totalDuration = Duration(milliseconds: (version.duration * 1000).round());
    _startPositionTimer();
    
    notifyListeners();
    _updateNotification();
  }

  void playNext() {
    if (currentQueue.isEmpty || playingSong == null) return;
    
    int index = currentQueue.indexWhere((s) => s.id == playingSong!.id);
    if (index == -1) return;
    
    if (playMode == PlayMode.shuffle) {
      final randomIdx = DateTime.now().millisecond % currentQueue.length;
      final nextSong = currentQueue[randomIdx];
      playSong(nextSong, currentQueue, _cachedLibraryPath, audioServerPort: _cachedAudioServerPort).catchError((_){});
    } else {
      int nextIdx = index + 1;
      if (nextIdx >= currentQueue.length) {
        nextIdx = 0;
      }
      final nextSong = currentQueue[nextIdx];
      playSong(nextSong, currentQueue, _cachedLibraryPath, audioServerPort: _cachedAudioServerPort).catchError((_){});
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
    playSong(prevSong, currentQueue, _cachedLibraryPath, audioServerPort: _cachedAudioServerPort).catchError((_){});
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
    if (Platform.isAndroid) {
      NativeAudioHelper.hideNotification();
    }
    music.stopRustPlayback();
    super.dispose();
  }
}
