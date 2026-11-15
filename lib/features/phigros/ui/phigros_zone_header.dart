import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_chip.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_slider.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';
import 'package:aetheria/core/widgets/aether_switch.dart';
import 'package:aetheria/features/phigros/phigros_badges.dart';

/// Top control bar for the Phigros zone playlist: global hit-sound controls,
/// quick resource import, and Phigros chapter filter chips.
class PhigrosZoneHeader extends StatelessWidget {
  const PhigrosZoneHeader({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    if (!library.isPhigrosPlaylistActive) {
      return const SizedBox.shrink();
    }
    final audio = context.watch<AudioPlayerProvider>();
    final cfg = context.tokens;
    final chapters = library.phigrosChapters;
    final offsetMs = audio.phigrosHitsoundOffsetMs;

    return AetherSurface(
      level: AetherSurfaceLevel.panel,
      borderRadius: BorderRadius.circular(AetherRadius.md),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AetherSpace.lg : AetherSpace.xl,
        vertical: AetherSpace.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AetherSpace.xl,
            runSpacing: AetherSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AetherSwitch(
                    value: audio.phigrosHitsoundEnabled,
                    onChanged: audio.setPhigrosHitsoundEnabled,
                  ),
                  const SizedBox(width: AetherSpace.sm),
                  Text(
                    '全局打击音效',
                    style: AetherType.labelStyle(cfg.textPrimary),
                  ),
                ],
              ),
              SizedBox(
                width: compact ? 220 : 240,
                child: Row(
                  children: [
                    Text(
                      '音量 ${(audio.phigrosHitsoundVolume * 100).round()}%',
                      style: AetherType.captionStyle(cfg.textSecondary),
                    ),
                    const SizedBox(width: AetherSpace.sm),
                    Expanded(
                      child: AetherSlider(
                        value: audio.phigrosHitsoundVolume,
                        min: 0.0,
                        max: 1.5,
                        divisions: 30,
                        onChanged: audio.phigrosHitsoundEnabled
                            ? audio.setPhigrosHitsoundVolume
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '全局偏移 ${offsetMs >= 0 ? '+' : ''}$offsetMs ms',
                    style: AetherType.captionStyle(cfg.textSecondary),
                  ),
                  const SizedBox(width: AetherSpace.xs),
                  AetherIconButton.dense(
                    icon: Icons.remove_rounded,
                    tooltip: '提前 5 ms',
                    onPressed: () => audio.setPhigrosHitsoundOffsetMs(offsetMs - 5),
                  ),
                  AetherIconButton.dense(
                    icon: Icons.add_rounded,
                    tooltip: '延后 5 ms',
                    onPressed: () => audio.setPhigrosHitsoundOffsetMs(offsetMs + 5),
                  ),
                  if (offsetMs != 0)
                    AetherButton.ghost(
                      label: '归零',
                      size: AetherButtonSize.sm,
                      onPressed: () => audio.setPhigrosHitsoundOffsetMs(0),
                    ),
                ],
              ),
              if (!compact)
                AetherButton.secondary(
                  label: '导入 / 更新 Phigros',
                  icon: Icons.sync_rounded,
                  size: AetherButtonSize.sm,
                  onPressed: () => showPhigrosImportDialog(context, library),
                ),
            ],
          ),
          if (chapters.isNotEmpty) ...[
            const SizedBox(height: AetherSpace.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  AetherChip(
                    label: '全部章节',
                    compact: true,
                    state: library.activePhigrosChapter == null
                        ? AetherChipState.selected
                        : AetherChipState.idle,
                    onTap: () => library.setActivePhigrosChapter(null),
                  ),
                  for (final chapter in chapters) ...[
                    const SizedBox(width: AetherSpace.xs),
                    AetherChip(
                      label: chapter,
                      compact: true,
                      state: library.activePhigrosChapter == chapter
                          ? AetherChipState.selected
                          : AetherChipState.idle,
                      onTap: () => library.setActivePhigrosChapter(chapter),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
