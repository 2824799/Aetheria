import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/features/lyrics/lyric_timeline.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/src/rust/models/song.dart';
import 'package:flutter/foundation.dart';

/// The parsed lyric of the track that is currently playing.
///
/// Shared by the lyric bridges so they resolve the selected lyric, the legacy
/// fallback and the offset in exactly the same way.
class PlayingLyric {
  const PlayingLyric({
    this.timeline,
    this.romanizedByTime = const <int, String>{},
    this.offsetMs = 0,
  });

  static const PlayingLyric empty = PlayingLyric();

  final LyricTimeline? timeline;
  final Map<int, String> romanizedByTime;
  final int offsetMs;

  /// Loads the lyric selected for [song] and [versionId], falling back to the
  /// lyric text stored on the song itself when nothing is selected or the
  /// lookup fails.
  static Future<PlayingLyric> load(Song song, String? versionId) async {
    final legacy = song.lyrics?.trim() ?? '';
    try {
      final lyric = await music.getSelectedLyric(
        songId: song.id,
        audioVersionId: versionId,
      );
      final saved = lyric?.content.trim() ?? '';
      final content = saved.isNotEmpty ? saved : legacy;
      return PlayingLyric(
        timeline: content.isEmpty
            ? null
            : LyricTimeline.parse(
                content: content,
                translation: lyric?.translation?.trim(),
              ),
        romanizedByTime: LyricTimeline.parseTranslationByTime(
          lyric?.romanized?.trim(),
        ),
        offsetMs: lyric?.offsetMs ?? 0,
      );
    } catch (error) {
      debugPrint('Failed to load the lyric of ${song.id}: $error');
      return PlayingLyric(
        timeline: legacy.isEmpty ? null : LyricTimeline.parse(content: legacy),
      );
    }
  }
}

/// Keeps [lyric] in step with the track that [AudioPlayerProvider] is playing.
class PlayingLyricTracker {
  PlayingLyric lyric = PlayingLyric.empty;

  String? _songId;
  String? _versionId;
  bool _loading = false;
  bool _stale = false;

  /// Forces the next [sync] to load the lyric again, e.g. after it was edited.
  void invalidate() => _stale = true;

  /// Loads the lyric when the playing track changed. Returns whether [lyric]
  /// was replaced.
  Future<bool> sync(AudioPlayerProvider audio) async {
    final song = audio.playingSong;
    final songId = song?.id;
    final versionId = audio.playingVersion?.id;
    final upToDate = songId == _songId && versionId == _versionId && !_stale;
    if (_loading || upToDate) {
      return false;
    }

    _loading = true;
    _stale = false;
    _songId = songId;
    _versionId = versionId;
    lyric = PlayingLyric.empty;
    try {
      if (song != null) {
        final loaded = await PlayingLyric.load(song, versionId);
        if (audio.playingSong?.id == songId &&
            audio.playingVersion?.id == versionId) {
          lyric = loaded;
        } else {
          // The track changed while loading; pick up the new one next time.
          _stale = true;
        }
      }
    } finally {
      _loading = false;
    }
    return true;
  }
}

/// Interpolates the playback position between two provider updates, so lyric
/// output can advance smoothly at its own refresh rate.
class PlaybackPositionEstimator {
  int _anchorPositionMs = 0;
  int _anchorReadAtMs = 0;
  bool _anchorWasPlaying = false;

  /// Whether playback was running the last time a position was estimated.
  bool get wasPlaying => _anchorWasPlaying;

  /// Forgets the current anchor; the next estimate starts from the provider.
  void reset() => _anchorReadAtMs = 0;

  int positionMs(AudioPlayerProvider audio, int nowMs) {
    final currentMs = audio.currentPosition.inMilliseconds;
    final moved = (currentMs - _anchorPositionMs).abs() > 120;
    if (moved || audio.isPlaying != _anchorWasPlaying || _anchorReadAtMs == 0) {
      _anchorPositionMs = currentMs;
      _anchorReadAtMs = nowMs;
      _anchorWasPlaying = audio.isPlaying;
    }
    if (!audio.isPlaying) {
      return currentMs;
    }
    final estimated = _anchorPositionMs + (nowMs - _anchorReadAtMs);
    final totalMs = audio.totalDuration.inMilliseconds;
    return estimated.clamp(0, totalMs > 0 ? totalMs : 1 << 31);
  }
}
