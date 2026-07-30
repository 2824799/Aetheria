import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/utils/audio_quality.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/features/layout/mobile/mobile_utils.dart';
import 'package:aetheria/src/rust/models/song.dart';

class MobileSongTile extends StatelessWidget {
  final Song song;
  final AppThemeConfig cfg;
  final LibraryProvider libraryProvider;
  final bool isActive;
  final bool isCurrentlyPlaying;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const MobileSongTile({
    super.key,
    required this.song,
    required this.cfg,
    required this.libraryProvider,
    required this.isActive,
    required this.isCurrentlyPlaying,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    AudioVersion? primary;
    for (final version in song.versions) {
      if (version.isPrimary) {
        primary = version;
        break;
      }
    }
    if (primary == null && song.versions.isNotEmpty) {
      primary = song.versions.first;
    }

    final specsText = audioQualityText(primary);
    final qualityColor = audioQualityColor(primary, cfg.textSecondary);

    return Padding(
      padding: const EdgeInsets.only(bottom: AetherSpace.sm),
      child: AetherPressable(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AetherRadius.md),
        hoverColor: cfg.bgHover,
        pressedColor: cfg.pressed,
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? cfg.bgHover : cfg.bg1,
            borderRadius: BorderRadius.circular(AetherRadius.md),
            border: Border(
              left: BorderSide(
                color: isCurrentlyPlaying ? cfg.accent : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AetherSpace.lg,
            vertical: AetherSpace.lg - 2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            song.title,
                            style: AetherType.titleSmStyle(
                              isCurrentlyPlaying ? cfg.accent : cfg.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (libraryProvider.songHasLyrics(song)) ...[
                          const SizedBox(width: AetherSpace.sm),
                          MobileLrcBadge(cfg: cfg),
                        ],
                      ],
                    ),
                    const SizedBox(height: AetherSpace.xs),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            song.artist ?? '未知歌手',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AetherType.bodySmStyle(cfg.textSecondary),
                          ),
                        ),
                        const SizedBox(width: AetherSpace.md),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AetherSpace.xs,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: qualityColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AetherRadius.xs),
                          ),
                          child: Text(
                            specsText,
                            style: AetherType.captionStyle(qualityColor).copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (song.tags.isNotEmpty) ...[
                      const SizedBox(height: AetherSpace.xs),
                      Wrap(
                        spacing: AetherSpace.sm,
                        runSpacing: AetherSpace.xs,
                        children: song.tags.map((t) {
                          final c = t.color != null
                              ? mobileParseHexColor(t.color!, cfg.textSecondary)
                              : cfg.textSecondary;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AetherSpace.sm,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: c.withValues(alpha: 0.10),
                              borderRadius:
                                  BorderRadius.circular(AetherRadius.xs),
                              border: Border.all(color: c.withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              t.name,
                              style: AetherType.captionStyle(c).copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
