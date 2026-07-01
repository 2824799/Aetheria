import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'dart:io';

enum PlayMode { list, single, shuffle }

class AudioPlayerProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  Song? activeSong;
  Song? playingSong;
  AudioVersion? playingVersion;
  
  List<Song> currentQueue = [];
  
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;
  
  double volume = 0.8;
  PlayMode playMode = PlayMode.list;
  
  bool isDetailOpen = false;
  String activeTab = 'versions';

  String _cachedLibraryPath = '';
  int? _cachedAudioServerPort;

  AudioPlayerProvider() {
    _initListeners();
  }

  void _initListeners() {
    _audioPlayer.onPositionChanged.listen((pos) {
      currentPosition = pos;
      notifyListeners();
    });
    
    _audioPlayer.onDurationChanged.listen((dur) {
      totalDuration = dur;
      notifyListeners();

      if (playingVersion != null && playingVersion!.duration < 1.0 && dur.inSeconds > 0) {
        final secs = dur.inMilliseconds / 1000.0;
        playingVersion = AudioVersion(
          id: playingVersion!.id,
          songId: playingVersion!.songId,
          filepath: playingVersion!.filepath,
          originalName: playingVersion!.originalName,
          format: playingVersion!.format,
          bitrate: playingVersion!.bitrate,
          sampleRate: playingVersion!.sampleRate,
          duration: secs,
          fileSize: playingVersion!.fileSize,
          isEnabled: playingVersion!.isEnabled,
          isPrimary: playingVersion!.isPrimary,
          md5: playingVersion!.md5,
          bitDepth: playingVersion!.bitDepth,
        );
        music.updateVersionDuration(versionId: playingVersion!.id, duration: secs)
            .then((_) => notifyListeners())
            .catchError((_){});
      }
    });
    
    _audioPlayer.onPlayerStateChanged.listen((state) {
      isPlaying = state == PlayerState.playing;
      notifyListeners();
    });
    
    _audioPlayer.onPlayerComplete.listen((_) {
      if (playMode == PlayMode.single) {
        _audioPlayer.seek(Duration.zero);
        _audioPlayer.resume();
      } else {
        playNext();
      }
    });
  }

  void setVolume(double vol) {
    volume = vol;
    _audioPlayer.setVolume(vol);
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
      await _audioPlayer.pause();
    } else {
      if (playingSong != null && playingVersion != null) {
        await _audioPlayer.resume();
      }
    }
  }

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
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
    
    // Verify file existence on the local filesystem
    final file = File(path);
    final exists = await file.exists();
    if (!exists) {
      throw '音频物理文件不存在！\n期望路径: $path\n数据库内记录: ${version.filepath}';
    }
    
    // Verify file readability
    try {
      final access = await file.open(mode: FileMode.read);
      await access.close();
    } catch (e) {
      throw '音频文件无法读取，权限不足: $e\n文件路径: $path';
    }
    
    String url = path;
    if (Platform.isAndroid && audioServerPort != null && audioServerPort > 0) {
      url = 'http://127.0.0.1:$audioServerPort/audio?path=${Uri.encodeComponent(path)}';
      await _audioPlayer.play(UrlSource(url));
    } else {
      await _audioPlayer.play(DeviceFileSource(path));
    }
    
    notifyListeners();
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

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
