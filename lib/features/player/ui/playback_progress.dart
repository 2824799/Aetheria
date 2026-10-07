import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/theme/theme.dart';
import 'package:aetheria/core/widgets/aether_slider.dart';

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
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.audio.positionListenable,
      builder: (context, position, _) {
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
    );
  }
}
