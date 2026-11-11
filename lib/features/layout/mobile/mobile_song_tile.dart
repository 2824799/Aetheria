import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/utils/audio_quality.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/features/library/ui/song_badges.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// One song in the mobile list: title, artist, audio quality and tags.
class MobileSongTile extends StatelessWidget {
  const MobileSongTile({
    super.key,
    required this.song,
    required this.hasLyrics,
    required this.isActive,
    required this.isPlaying,
    required this.onTap,
    required this.onLongPress,
  });

  final Song song;
  final bool hasLyrics;

  /// The song whose details were opened last.
  final bool isActive;

  /// The song loaded in the player.
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final radius = BorderRadius.circular(AetherRadius.md);
    final artist = song.artist;

    return Padding(
      padding: const EdgeInsets.only(bottom: AetherSpace.sm),
      child: AetherPressable(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: radius,
        pressScale: AetherMotion.pressScaleSubtle,
        hoverColor: cfg.bgHover,
        pressedColor: cfg.pressed,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AetherSpace.xl,
            vertical: AetherSpace.lg,
          ),
          decoration: BoxDecoration(
            color: isPlaying ? cfg.accentMuted : cfg.bg1,
            borderRadius: radius,
            border: Border.all(
              color: isActive && !isPlaying
                  ? cfg.borderStrong
                  : cfg.borderSubtle,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AetherType.titleSmStyle(
                        isPlaying ? cfg.accent : cfg.textPrimary,
                      ).copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (hasLyrics) ...[
                    const SizedBox(width: AetherSpace.sm),
                    const LrcBadge(),
                  ],
                ],
              ),
              const SizedBox(height: AetherSpace.xs),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      artist ?? '未知歌手',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AetherType.bodySmStyle(
                        artist == null ? cfg.textTertiary : cfg.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AetherSpace.md),
                  AudioQualityBadge(version: primaryVersionOf(song)),
                ],
              ),
              if (song.tags.isNotEmpty) ...[
                const SizedBox(height: AetherSpace.md),
                Wrap(
                  spacing: AetherSpace.sm,
                  runSpacing: AetherSpace.xs,
                  children: [
                    for (final tag in song.tags) SongTagChip(tag: tag),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
