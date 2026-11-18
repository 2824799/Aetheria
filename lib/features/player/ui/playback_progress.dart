import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/theme/theme.dart';
import 'package:aetheria/core/widgets/aether_slider.dart';

/// Rebuilds [builder] from `audio.positionListenable` at most once per
/// [minIntervalMs] while playing (or once per whole second when
/// [onlyWholeSeconds] is true), while updating immediately when paused, reset,
/// completed, or when track duration changes.
class ThrottledPositionBuilder extends StatefulWidget {
  const ThrottledPositionBuilder({
    super.key,
    required this.audio,
    this.minIntervalMs = 250,
    this.onlyWholeSeconds = false,
    required this.builder,
  });

  final AudioPlayerProvider audio;
  final int minIntervalMs;
  final bool onlyWholeSeconds;
  final Widget Function(BuildContext context, Duration position) builder;

  @override
  State<ThrottledPositionBuilder> createState() =>
      _ThrottledPositionBuilderState();
}

class _ThrottledPositionBuilderState extends State<ThrottledPositionBuilder> {
  late Duration _renderedPosition;
  late Duration _renderedTotalDuration;

  @override
  void initState() {
    super.initState();
    _renderedPosition = widget.audio.currentPosition;
    _renderedTotalDuration = widget.audio.totalDuration;
    widget.audio.positionListenable.addListener(_handlePositionChanged);
  }

  @override
  void didUpdateWidget(covariant ThrottledPositionBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.audio, widget.audio)) {
      oldWidget.audio.positionListenable.removeListener(_handlePositionChanged);
      _renderedPosition = widget.audio.currentPosition;
      _renderedTotalDuration = widget.audio.totalDuration;
      widget.audio.positionListenable.addListener(_handlePositionChanged);
    } else if (widget.audio.totalDuration != _renderedTotalDuration ||
        !widget.audio.isPlaying) {
      _renderedPosition = widget.audio.currentPosition;
      _renderedTotalDuration = widget.audio.totalDuration;
    }
  }

  @override
  void dispose() {
    widget.audio.positionListenable.removeListener(_handlePositionChanged);
    super.dispose();
  }

  void _handlePositionChanged() {
    final next = widget.audio.positionListenable.value;
    final total = widget.audio.totalDuration;
    final totalChanged = total != _renderedTotalDuration;
    final secondChanged = next.inSeconds != _renderedPosition.inSeconds;
    final shouldUpdate = widget.onlyWholeSeconds
        ? (totalChanged || secondChanged)
        : (totalChanged ||
              !widget.audio.isPlaying ||
              next == Duration.zero ||
              (total > Duration.zero && next >= total) ||
              (next.inMilliseconds - _renderedPosition.inMilliseconds).abs() >=
                  widget.minIntervalMs);
    if (!shouldUpdate) {
      return;
    }
    setState(() {
      _renderedPosition = next;
      _renderedTotalDuration = total;
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _renderedPosition);
}

/// The playback clock only rebuilds this control. Scrubbing previews locally
/// and performs one engine seek when the gesture finishes.
class PlaybackProgress extends StatefulWidget {
  const PlaybackProgress({
    super.key,
    required this.audio,
    this.showTime = false,
  });

  final AudioPlayerProvider audio;
  final bool showTime;

  @override
  State<PlaybackProgress> createState() => _PlaybackProgressState();
}

class _PlaybackProgressState extends State<PlaybackProgress> {
  double? _preview;
  int _seekRequest = 0;
  String? _songId;

  String _format(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final songId = widget.audio.playingSong?.id;
    if (_songId != songId) {
      _songId = songId;
      _preview = null;
      _seekRequest++;
    }
    return RepaintBoundary(
      child: ThrottledPositionBuilder(
        audio: widget.audio,
        minIntervalMs: 250,
        builder: (context, position) {
          final total = widget.audio.totalDuration.inMilliseconds;
          final progress =
              _preview ?? (total > 0 ? position.inMilliseconds / total : 0.0);
          final slider = AetherSlider(
            value: progress.clamp(0.0, 1.0),
            thumbRadius: 5,
            onChanged: total <= 0
                ? null
                : (value) {
                    _seekRequest++;
                    setState(() => _preview = value);
                  },
            onChangeEnd: total <= 0
                ? null
                : (value) async {
                    final request = ++_seekRequest;
                    try {
                      await widget.audio.seek(
                        Duration(milliseconds: (total * value).round()),
                      );
                    } finally {
                      if (mounted && request == _seekRequest) {
                        setState(() => _preview = null);
                      }
                    }
                  },
          );
          if (!widget.showTime) return SizedBox(height: 22, child: slider);
          final style = AetherType.captionStyle(context.tokens.textSecondary);
          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _format(Duration(milliseconds: (total * progress).round())),
                    style: style,
                  ),
                  Text(_format(widget.audio.totalDuration), style: style),
                ],
              ),
              slider,
            ],
          );
        },
      ),
    );
  }
}
