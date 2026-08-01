import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_slider.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// Floating mini play bar pinned above the system gesture area.
class MobileMiniPlayer extends StatefulWidget {
  final Song playingSong;
  final AppThemeConfig cfg;
  final AudioPlayerProvider audioProvider;
  final VoidCallback onOpenDetail;

  const MobileMiniPlayer({
    super.key,
    required this.playingSong,
    required this.cfg,
    required this.audioProvider,
    required this.onOpenDetail,
  });

  @override
  State<MobileMiniPlayer> createState() => _MobileMiniPlayerState();
}

class _MobileMiniPlayerState extends State<MobileMiniPlayer> {
  double? _dragProgress;

  @override
  void didUpdateWidget(covariant MobileMiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playingSong.id != widget.playingSong.id) {
      _dragProgress = null;
    }
  }

  void _seekTo(double progress) {
    final durationMs = widget.audioProvider.totalDuration.inMilliseconds;
    if (durationMs <= 0) {
      return;
    }
    final targetMs = (durationMs * progress.clamp(0.0, 1.0)).round();
    unawaited(widget.audioProvider.seek(Duration(milliseconds: targetMs)));
  }

  @override
  Widget build(BuildContext context) {
    final curMs = widget.audioProvider.currentPosition.inMilliseconds
        .toDouble();
    final totMs = widget.audioProvider.totalDuration.inMilliseconds.toDouble();
    final actualProgress = totMs > 0 ? (curMs / totMs).clamp(0.0, 1.0) : 0.0;
    final progress = _dragProgress ?? actualProgress;

    return Material(
      type: MaterialType.transparency,
      child: AetherSurface(
        level: AetherSurfaceLevel.elevated,
        borderRadius: BorderRadius.circular(AetherRadius.xl),
        padding: const EdgeInsets.fromLTRB(
          AetherSpace.lg,
          AetherSpace.md,
          AetherSpace.sm,
          AetherSpace.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AetherPressable(
              onTap: widget.onOpenDetail,
              borderRadius: BorderRadius.circular(AetherRadius.lg),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.cfg.accentMuted,
                      borderRadius: BorderRadius.circular(AetherRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.music_note,
                      color: widget.cfg.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AetherSpace.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.playingSong.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AetherType.titleSmStyle(
                            widget.cfg.textPrimary,
                          ),
                        ),
                        Text(
                          widget.playingSong.artist ?? '未知歌手',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AetherType.captionStyle(
                            widget.cfg.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AetherIconButton(
                    icon: widget.audioProvider.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    tooltip: widget.audioProvider.isPlaying ? '暂停' : '播放',
                    onPressed: () => widget.audioProvider.playPause(),
                  ),
                  AetherIconButton(
                    icon: Icons.skip_next_rounded,
                    tooltip: '下一首',
                    onPressed: () => widget.audioProvider.playNext(),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 22,
              child: AetherSlider(
                value: progress,
                onChanged: totMs <= 0
                    ? null
                    : (value) {
                        setState(() {
                          _dragProgress = value;
                        });
                      },
                onChangeEnd: totMs <= 0
                    ? null
                    : (value) {
                        setState(() {
                          _dragProgress = null;
                        });
                        _seekTo(value);
                      },
                trackHeight: 3,
                thumbRadius: 5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
