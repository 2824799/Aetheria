import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_progress.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// Floating mini play bar pinned above the system gesture area.
class MobileMiniPlayer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final curMs = audioProvider.currentPosition.inMilliseconds.toDouble();
    final totMs = audioProvider.totalDuration.inMilliseconds.toDouble();
    final progress = totMs > 0 ? (curMs / totMs).clamp(0.0, 1.0) : 0.0;

    return AetherPressable(
      onTap: onOpenDetail,
      borderRadius: BorderRadius.circular(AetherRadius.xl),
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
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cfg.accentMuted,
                    borderRadius: BorderRadius.circular(AetherRadius.md),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.music_note,
                    color: cfg.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AetherSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playingSong.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AetherType.titleSmStyle(cfg.textPrimary),
                      ),
                      Text(
                        playingSong.artist ?? '未知歌手',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AetherType.captionStyle(cfg.textSecondary),
                      ),
                    ],
                  ),
                ),
                AetherIconButton(
                  icon: audioProvider.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  tooltip: audioProvider.isPlaying ? '暂停' : '播放',
                  onPressed: () => audioProvider.playPause(),
                ),
                AetherIconButton(
                  icon: Icons.skip_next_rounded,
                  tooltip: '下一首',
                  onPressed: () => audioProvider.playNext(),
                ),
              ],
            ),
            const SizedBox(height: AetherSpace.sm),
            AetherProgress.linear(
              value: progress,
              size: 3,
            ),
          ],
        ),
      ),
    );
  }
}
