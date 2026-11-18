import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/features/lyrics/lyric_timeline.dart';
import 'package:aetheria/features/lyrics/playing_lyric.dart';
import 'package:aetheria/services/native_audio_helper.dart';

class FloatingLyricsBridge extends StatefulWidget {
  const FloatingLyricsBridge({super.key, required this.child});

  final Widget child;

  @override
  State<FloatingLyricsBridge> createState() => _FloatingLyricsBridgeState();
}

class _FloatingLyricsBridgeState extends State<FloatingLyricsBridge> {
  Timer? _timer;
  FloatingLyricsProvider? _settings;
  AudioPlayerProvider? _audio;
  final PlayingLyricTracker _lyrics = PlayingLyricTracker();
  final PlaybackPositionEstimator _clock = PlaybackPositionEstimator();
  bool _ticking = false;
  bool _pendingImmediateTick = false;
  bool _visible = false;
  bool _requestedOverlayPermission = false;
  String _lastStyleSignature = '';
  int _lastOverlayCheckAtMs = 0;
  bool _overlayAllowed = true;
  int _lastLyricRevision = 0;
  _SentFloatingLyricPayload? _lastSentPayload;

  @override
  void initState() {
    super.initState();
    NativeAudioHelper.setFloatingLyricEventHandler(_handleNativeEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.read<FloatingLyricsProvider>();
    final audio = context.read<AudioPlayerProvider>();
    if (identical(settings, _settings) && identical(audio, _audio)) return;
    _settings?.removeListener(_requestTick);
    _audio?.positionListenable.removeListener(_handlePositionChanged);
    _audio?.removeListener(_requestTick);
    _settings = settings..addListener(_requestTick);
    _audio = audio..addListener(_requestTick);
    _audio?.positionListenable.addListener(_handlePositionChanged);
    _requestTick();
  }

  void _handlePositionChanged() {
    if (_audio?.isPlaying ?? false) {
      return;
    }
    _requestTick();
  }

  void _requestTick() {
    if (!mounted) return;
    _timer?.cancel();
    _timer = null;
    if (_ticking) {
      _pendingImmediateTick = true;
      return;
    }
    unawaited(_tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _settings?.removeListener(_requestTick);
    _audio?.positionListenable.removeListener(_handlePositionChanged);
    _audio?.removeListener(_requestTick);
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
    if (!mounted || _ticking) return;
    _ticking = true;
    try {
      await _sendFrame();
    } finally {
      _ticking = false;
      if (mounted) {
        if (_pendingImmediateTick) {
          _pendingImmediateTick = false;
          unawaited(_tick());
        } else {
          final settings = _settings;
          final shouldScheduleTimer =
              settings != null &&
              settings.enabled &&
              (_audio?.isPlaying ?? false) &&
              (_lyrics.lyric.timeline?.hasTimedLines ?? false);
          if (shouldScheduleTimer) {
            final interval = (1000 / settings.refreshFps.clamp(10, 60)).ceil();
            _timer = Timer(Duration(milliseconds: interval), _requestTick);
          }
        }
      }
    }
  }

  Future<void> _sendFrame() async {
    if (!mounted) {
      return;
    }

    final settings = context.read<FloatingLyricsProvider>();
    final audio = context.read<AudioPlayerProvider>();

    if (settings.lyricRevision != _lastLyricRevision) {
      _lastLyricRevision = settings.lyricRevision;
      _lyrics.invalidate();
    }

    if (!settings.enabled) {
      _lastSentPayload = null;
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
      _lastSentPayload = null;
      return;
    }

    await _lyrics.sync(audio);
    if (!mounted || !settings.enabled) return;

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
      _lastSentPayload = null;
    }

    final lyric = _lyrics.lyric;
    final positionMs = _clock.positionMs(audio, now) + lyric.offsetMs;
    final frame =
        lyric.timeline?.frameAt(positionMs) ?? const LyricFrame.empty();
    final songTitle = audio.playingSong?.title.trim() ?? '';
    final artist = audio.playingSong?.artist?.trim() ?? '';
    final previews = settings.showNextLine
        ? (lyric.timeline?.previewLinesAfter(
                frame.activeIndex,
                count: settings.compactMultiline ? 4 : 1,
                showTranslation: settings.showTranslation,
              ) ??
              const <LyricPreviewLine>[])
        : const <LyricPreviewLine>[];
    final activeText = frame.line.trim().isEmpty
        ? (previews.isNotEmpty ? '···' : '')
        : frame.line;
    final translation = settings.showTranslation ? frame.translation : '';
    final nextLine = previews.isNotEmpty ? previews.first.text : '';
    final nextTranslation =
        previews.isNotEmpty ? previews.first.translation : '';
    final contextLines = previews.skip(1).map((line) => line.text).toList();
    final contextTranslations = previews
        .skip(1)
        .map((line) => line.translation)
        .toList();
    final progress = frame.progress.clamp(0.0, 1.0);
    final payload = _SentFloatingLyricPayload(
      line: activeText,
      translation: translation,
      nextLine: nextLine,
      nextTranslation: nextTranslation,
      contextLines: contextLines,
      contextTranslations: contextTranslations,
      progressPermille: (progress * 1000).round(),
      activeIndex: frame.activeIndex,
      isPlaying: audio.isPlaying,
      songTitle: songTitle,
      artist: artist,
    );
    if (payload == _lastSentPayload) {
      return;
    }
    _lastSentPayload = payload;

    await NativeAudioHelper.updateFloatingLyrics(<String, dynamic>{
      'line': activeText,
      'translation': translation,
      'nextLine': nextLine,
      'nextTranslation': nextTranslation,
      'contextLines': contextLines,
      'contextTranslations': contextTranslations,
      'progress': progress,
      'activeIndex': frame.activeIndex,
      'isPlaying': audio.isPlaying,
      'songTitle': songTitle,
      'artist': artist,
    });
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

class _SentFloatingLyricPayload {
  const _SentFloatingLyricPayload({
    required this.line,
    required this.translation,
    required this.nextLine,
    required this.nextTranslation,
    required this.contextLines,
    required this.contextTranslations,
    required this.progressPermille,
    required this.activeIndex,
    required this.isPlaying,
    required this.songTitle,
    required this.artist,
  });

  final String line;
  final String translation;
  final String nextLine;
  final String nextTranslation;
  final List<String> contextLines;
  final List<String> contextTranslations;
  final int progressPermille;
  final int activeIndex;
  final bool isPlaying;
  final String songTitle;
  final String artist;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SentFloatingLyricPayload &&
          line == other.line &&
          translation == other.translation &&
          nextLine == other.nextLine &&
          nextTranslation == other.nextTranslation &&
          progressPermille == other.progressPermille &&
          activeIndex == other.activeIndex &&
          isPlaying == other.isPlaying &&
          songTitle == other.songTitle &&
          artist == other.artist &&
          listEquals(contextLines, other.contextLines) &&
          listEquals(contextTranslations, other.contextTranslations);

  @override
  int get hashCode => Object.hash(
    line,
    translation,
    nextLine,
    nextTranslation,
    progressPermille,
    activeIndex,
    isPlaying,
    songTitle,
    artist,
    Object.hashAll(contextLines),
    Object.hashAll(contextTranslations),
  );
}
