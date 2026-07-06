import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/features/lyrics/lyric_timeline.dart';
import 'package:aetheria/services/native_audio_helper.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;

class FloatingLyricsBridge extends StatefulWidget {
  const FloatingLyricsBridge({super.key, required this.child});

  final Widget child;

  @override
  State<FloatingLyricsBridge> createState() => _FloatingLyricsBridgeState();
}

class _FloatingLyricsBridgeState extends State<FloatingLyricsBridge> {
  Timer? _timer;
  String? _loadedSongId;
  String? _loadedVersionId;
  String _content = '';
  String? _translation;
  int _offsetMs = 0;
  LyricTimeline? _timeline;
  bool _loading = false;
  bool _visible = false;
  bool _requestedOverlayPermission = false;
  String _lastStyleSignature = '';
  int _lastSentAtMs = 0;
  int _lastOverlayCheckAtMs = 0;
  bool _overlayAllowed = true;
  int _anchorPositionMs = 0;
  int _anchorReadAtMs = 0;
  bool _anchorWasPlaying = false;

  @override
  void initState() {
    super.initState();
    NativeAudioHelper.setFloatingLyricEventHandler(_handleNativeEvent);
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      unawaited(_tick());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(NativeAudioHelper.hideFloatingLyrics());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  Future<void> _handleNativeEvent(Map<String, dynamic> event) async {
    if (!mounted) {
      return;
    }
    if (event['type'] != 'boundsChanged') {
      return;
    }
    final x = _asDouble(event['x']);
    final y = _asDouble(event['y']);
    final width = _asDouble(event['width']);
    final height = _asDouble(event['height']);
    if (x == null || y == null || width == null || height == null) {
      return;
    }
    await context.read<FloatingLyricsProvider>().updateWindowBounds(
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }

  Future<void> _tick() async {
    if (!mounted) {
      return;
    }

    final settings = context.read<FloatingLyricsProvider>();
    final audio = context.read<AudioPlayerProvider>();

    if (!settings.enabled) {
      if (_visible) {
        await NativeAudioHelper.hideFloatingLyrics();
        _visible = false;
      }
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (Platform.isAndroid && now - _lastOverlayCheckAtMs > 1000) {
      _lastOverlayCheckAtMs = now;
      _overlayAllowed = await NativeAudioHelper.canDrawOverlays();
      if (!_overlayAllowed) {
        if (!_requestedOverlayPermission) {
          _requestedOverlayPermission = true;
          await NativeAudioHelper.requestOverlayPermission();
        }
      }
    }
    if (Platform.isAndroid && !_overlayAllowed) {
      return;
    }

    await _ensureLyricLoaded(audio);

    final styleSignature = settings.styleSignature;
    if (styleSignature != _lastStyleSignature) {
      _lastStyleSignature = styleSignature;
      await NativeAudioHelper.updateFloatingLyricsStyle(
        settings.stylePayload(),
      );
    }

    if (!_visible) {
      await NativeAudioHelper.showFloatingLyrics();
      _visible = true;
    }

    final frameIntervalMs = (1000 / settings.refreshFps.clamp(10, 60)).round();
    if (audio.isPlaying && now - _lastSentAtMs < frameIntervalMs) {
      return;
    }
    if (!audio.isPlaying && now - _lastSentAtMs < 500) {
      return;
    }
    _lastSentAtMs = now;

    final positionMs = _estimatedPlaybackPositionMs(audio, now) + _offsetMs;
    final frame = _timeline?.frameAt(positionMs) ?? const LyricFrame.empty();
    final songTitle = audio.playingSong?.title.trim();
    final artist = audio.playingSong?.artist?.trim();
    final contextLines = _contextLines(frame.activeIndex, settings);
    await NativeAudioHelper.updateFloatingLyrics(<String, dynamic>{
      'line': frame.line.isEmpty
          ? (songTitle?.isNotEmpty == true ? songTitle : '暂无歌词')
          : frame.line,
      'translation': settings.showTranslation ? frame.translation : '',
      'nextLine': settings.showNextLine ? frame.nextLine : '',
      'contextLines': contextLines,
      'progress': frame.progress,
      'activeIndex': frame.activeIndex,
      'isPlaying': audio.isPlaying,
      'songTitle': songTitle ?? '',
      'artist': artist ?? '',
      'fade': settings.pauseFade && !audio.isPlaying,
    });
  }

  int _estimatedPlaybackPositionMs(AudioPlayerProvider audio, int now) {
    final currentMs = audio.currentPosition.inMilliseconds;
    final moved = (currentMs - _anchorPositionMs).abs() > 120;
    if (moved || audio.isPlaying != _anchorWasPlaying || _anchorReadAtMs == 0) {
      _anchorPositionMs = currentMs;
      _anchorReadAtMs = now;
      _anchorWasPlaying = audio.isPlaying;
    }
    if (!audio.isPlaying) {
      return currentMs;
    }
    final estimated = _anchorPositionMs + (now - _anchorReadAtMs);
    final totalMs = audio.totalDuration.inMilliseconds;
    if (totalMs > 0) {
      return estimated.clamp(0, totalMs);
    }
    return estimated.clamp(0, 1 << 31);
  }

  List<String> _contextLines(int activeIndex, FloatingLyricsProvider settings) {
    if (!settings.compactMultiline || !settings.showNextLine) {
      return const <String>[];
    }
    final lines = _timeline?.lines;
    if (lines == null || activeIndex < 0) {
      return const <String>[];
    }
    return lines
        .skip(activeIndex + 1)
        .map((line) => line.text.trim())
        .where((text) => text.isNotEmpty)
        .take(3)
        .toList(growable: false);
  }

  Future<void> _ensureLyricLoaded(AudioPlayerProvider audio) async {
    final song = audio.playingSong;
    final version = audio.playingVersion;
    final songId = song?.id;
    final versionId = version?.id;
    if (songId == _loadedSongId && versionId == _loadedVersionId) {
      return;
    }
    if (_loading) {
      return;
    }

    _loading = true;
    try {
      _loadedSongId = songId;
      _loadedVersionId = versionId;
      if (song == null) {
        _content = '';
        _translation = null;
        _offsetMs = 0;
        _timeline = null;
        return;
      }

      final lyric = await music.getSelectedLyric(
        songId: song.id,
        audioVersionId: versionId,
      );
      _content = lyric?.content.trim().isNotEmpty == true
          ? lyric!.content.trim()
          : (song.lyrics?.trim() ?? '');
      _translation = lyric?.translation?.trim();
      _offsetMs = lyric?.offsetMs ?? 0;
      _timeline = _content.trim().isEmpty
          ? null
          : LyricTimeline.parse(content: _content, translation: _translation);
    } catch (_) {
      _content = song?.lyrics?.trim() ?? '';
      _translation = null;
      _offsetMs = 0;
      _timeline = _content.trim().isEmpty
          ? null
          : LyricTimeline.parse(content: _content);
    } finally {
      _loading = false;
    }
  }

  double? _asDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    return null;
  }
}
