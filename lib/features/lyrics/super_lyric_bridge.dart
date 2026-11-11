import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/features/lyrics/lyric_timeline.dart';
import 'package:aetheria/features/lyrics/playing_lyric.dart';
import 'package:aetheria/services/native_audio_helper.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

class SuperLyricBridge extends StatefulWidget {
  const SuperLyricBridge({super.key, required this.child});

  final Widget child;

  @override
  State<SuperLyricBridge> createState() => _SuperLyricBridgeState();
}

class _SuperLyricBridgeState extends State<SuperLyricBridge> {
  Timer? _timer;
  bool _available = false;
  bool _initializing = false;
  bool _ticking = false;
  bool _stopped = true;
  bool _wasEnabled = false;
  int _nextInitializeAtMs = 0;
  int _lastLyricRevision = 0;
  String _lastPublishedSignature = '';
  final PlayingLyricTracker _lyrics = PlayingLyricTracker();
  final PlaybackPositionEstimator _clock = PlaybackPositionEstimator();

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        unawaited(_tick());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (Platform.isAndroid) {
      unawaited(NativeAudioHelper.disposeSuperLyric());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  Future<void> _tick() async {
    if (!mounted || _ticking) {
      return;
    }
    _ticking = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final settings = context.read<FloatingLyricsProvider>();
      final audio = context.read<AudioPlayerProvider>();
      if (!settings.superLyricEnabled) {
        if (_wasEnabled) {
          await _disable(audio);
        }
        _wasEnabled = false;
        return;
      }
      _wasEnabled = true;

      if (!_available) {
        await _initialize(now);
        if (!_available) {
          return;
        }
      }

      if (settings.lyricRevision != _lastLyricRevision) {
        _lastLyricRevision = settings.lyricRevision;
        _lyrics.invalidate();
      }

      if (await _lyrics.sync(audio)) {
        _lastPublishedSignature = '';
        _clock.reset();
      }
      final song = audio.playingSong;
      final lyric = _lyrics.lyric;
      final timeline = lyric.timeline;
      final offsetMs = lyric.offsetMs;
      if (song == null ||
          timeline == null ||
          timeline.lines.isEmpty ||
          !audio.isPlaying) {
        await _sendStopIfNeeded(audio);
        return;
      }

      final positionMs = _clock.positionMs(audio, now) + offsetMs;
      final activeIndex = timeline.hasTimedLines
          ? LyricTimeline.activeLineIndex(timeline.lines, positionMs)
          : 0;
      if (activeIndex < 0 || activeIndex >= timeline.lines.length) {
        await _sendStopIfNeeded(audio);
        return;
      }

      final line = timeline.lines[activeIndex];
      if (shouldHoldSuperLyricLine(line)) {
        return;
      }

      final translation = line.timeMs == null
          ? ''
          : timeline.translationFor(line);
      final secondary = line.timeMs == null
          ? ''
          : lyric.romanizedByTime[line.timeMs]?.trim() ?? '';
      final signature = <Object?>[
        song.id,
        audio.playingVersion?.id,
        activeIndex,
        line.text,
        line.timeMs,
        line.endMs,
        translation,
        secondary,
        offsetMs,
      ].join('|');
      if (!_stopped && signature == _lastPublishedSignature) {
        return;
      }

      final published = await NativeAudioHelper.publishSuperLyric(
        buildSuperLyricPayload(
          title: song.title,
          artist: song.artist,
          album: song.album,
          line: line,
          translation: translation,
          secondary: secondary,
          offsetMs: offsetMs,
        ),
      );
      if (published) {
        _stopped = false;
        _lastPublishedSignature = signature;
      } else {
        _markUnavailable(now);
      }
    } finally {
      _ticking = false;
    }
  }

  Future<void> _disable(AudioPlayerProvider audio) async {
    if (_available && !_stopped) {
      await _sendStopIfNeeded(audio);
    }
    await NativeAudioHelper.disposeSuperLyric();
    _available = false;
    _stopped = true;
    _lastPublishedSignature = '';
    _nextInitializeAtMs = 0;
  }

  Future<void> _initialize(int now) async {
    if (_available || _initializing || now < _nextInitializeAtMs) {
      return;
    }
    _initializing = true;
    try {
      _available = await NativeAudioHelper.initializeSuperLyric();
      if (!_available) {
        _nextInitializeAtMs = now + 5000;
      }
    } finally {
      _initializing = false;
    }
  }

  void _markUnavailable(int now) {
    _available = false;
    _stopped = true;
    _lastPublishedSignature = '';
    _nextInitializeAtMs = now + 5000;
  }

  Future<void> _sendStopIfNeeded(AudioPlayerProvider audio) async {
    if (_stopped) {
      return;
    }
    final stopped = await NativeAudioHelper.stopSuperLyric(
      buildSuperLyricMetadata(
        title: audio.playingSong?.title,
        artist: audio.playingSong?.artist,
        album: audio.playingSong?.album,
      ),
    );
    _stopped = true;
    _lastPublishedSignature = '';
    if (!stopped) {
      _markUnavailable(DateTime.now().millisecondsSinceEpoch);
    }
  }
}

bool shouldHoldSuperLyricLine(LyricLine line) => line.text.trim().isEmpty;

Map<String, dynamic> buildSuperLyricMetadata({
  String? title,
  String? artist,
  String? album,
}) {
  final payload = <String, dynamic>{};
  if (title?.trim().isNotEmpty == true) {
    payload['title'] = title!.trim();
  }
  if (artist?.trim().isNotEmpty == true) {
    payload['artist'] = artist!.trim();
  }
  if (album?.trim().isNotEmpty == true) {
    payload['album'] = album!.trim();
  }
  return payload;
}

Map<String, dynamic> buildSuperLyricPayload({
  required String title,
  String? artist,
  String? album,
  required LyricLine line,
  String translation = '',
  String secondary = '',
  int offsetMs = 0,
}) {
  final payload = buildSuperLyricMetadata(
    title: title,
    artist: artist,
    album: album,
  )..['line'] = line.text;

  final rawStart = line.timeMs;
  final rawEnd = line.endMs;
  if (rawStart != null && rawEnd != null) {
    final startTime = math.max(0, rawStart - offsetMs);
    final endTime = math.max(startTime + 1, rawEnd - offsetMs);
    payload['startTimeMs'] = startTime;
    payload['endTimeMs'] = endTime;

    final words = line.segments
        .where((segment) => segment.text.isNotEmpty)
        .map((segment) {
          final wordStart = math.max(0, segment.startMs - offsetMs);
          return <String, dynamic>{
            'text': segment.text,
            'startTimeMs': wordStart,
            'endTimeMs': math.max(wordStart + 1, segment.endMs - offsetMs),
          };
        })
        .toList(growable: false);
    if (words.isNotEmpty) {
      payload['words'] = words;
    }
  }

  if (translation.trim().isNotEmpty) {
    payload['translation'] = translation.trim();
  }
  if (secondary.trim().isNotEmpty) {
    payload['secondary'] = secondary.trim();
  }
  return payload;
}
