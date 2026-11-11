import 'package:flutter/material.dart';
import 'package:aetheria/core/utils/formatting.dart';
import 'package:aetheria/features/player/version_actions.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/features/player/ui/lyrics_panel.dart';
import 'package:aetheria/src/rust/models/song.dart';

Widget buildMobileDetailTabContent(
  BuildContext context,
  Song song,
  String activeTab,
  LibraryProvider libraryProvider,
  AudioPlayerProvider audioProvider,
  AppThemeConfig cfg,
  VoidCallback? openLyricManager,
  Widget? versionHeader,
) {
  if (activeTab == 'versions') {
    return Column(
      children: [
        ?versionHeader,
        Expanded(
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(AetherSpace.lg),
            itemCount: song.versions.length,
            itemBuilder: (context, index) {
              final v = song.versions[index];

              return Container(
                margin: const EdgeInsets.only(bottom: AetherSpace.lg - 2),
                padding: const EdgeInsets.all(AetherSpace.lg - 2),
                decoration: BoxDecoration(
                  color: cfg.bgHover,
                  borderRadius: BorderRadius.circular(AetherRadius.md),
                  border: Border.all(color: cfg.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      v.originalName,
                      style: AetherType.bodySmStyle(cfg.textPrimary).copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AetherSpace.xs),
                    Text(
                      formatVersionSpecs(v),
                      style: AetherType.captionStyle(cfg.textSecondary),
                    ),
                    const SizedBox(height: AetherSpace.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AetherSpace.sm,
                          vertical: AetherSpace.xxs,
                        ),
                        decoration: BoxDecoration(
                          color: (v.metadataScanned ? cfg.success : cfg.textSecondary)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AetherRadius.sm),
                        ),
                        child: Text(
                          v.metadataScanned ? '已完整扫描' : '待完整扫描',
                          style: AetherType.captionStyle(
                            v.metadataScanned ? cfg.success : cfg.textSecondary,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: AetherSpace.md),
                    Row(
                      children: [
                        Tooltip(
                          message:
                              '播放这首歌时优先使用的版本；若正在播放，会按当前进度切到新版本。',
                          child: AetherPressable(
                            onTap: v.isPrimary
                                ? null
                                : () => makeVersionPrimary(context, song, v),
                            borderRadius:
                                BorderRadius.circular(AetherRadius.sm),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AetherSpace.xs,
                                vertical: AetherSpace.xs,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    v.isPrimary
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: AetherIconSize.sm,
                                    color: v.isPrimary
                                        ? cfg.accent
                                        : cfg.textSecondary,
                                  ),
                                  const SizedBox(width: AetherSpace.xs),
                                  Text(
                                    '默认播放版本',
                                    style: AetherType.captionStyle(
                                      cfg.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        AetherIconButton.dense(
                          icon: Icons.download,
                          color: cfg.textSecondary,
                          tooltip: '导出',
                          onPressed: () => exportVersion(context, v),
                        ),
                        if (song.versions.length > 1) ...[
                          const SizedBox(width: AetherSpace.sm),
                          AetherIconButton.dense(
                            icon: Icons.delete_outline,
                            color: cfg.danger,
                            tooltip: '删除版本',
                            onPressed: () => deleteVersion(context, v),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AetherSpace.lg,
            vertical: AetherSpace.sm,
          ),
          child: AetherButton.primary(
            label: '绑定其他音轨文件',
            icon: Icons.add,
            size: AetherButtonSize.sm,
            expanded: true,
            onPressed: () => linkNewVersion(context, song),
          ),
        ),
      ],
    );
  }

  if (activeTab == 'tags') {
    return GridView.builder(
      padding: const EdgeInsets.all(AetherSpace.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AetherSpace.md,
        crossAxisSpacing: AetherSpace.md,
        childAspectRatio: 3.2,
      ),
      itemCount: libraryProvider.tags.length,
      itemBuilder: (context, index) {
        final tag = libraryProvider.tags[index];
        final isBound = song.tags.any((t) => t.id == tag.id);
        final tagColor = parseTagColor(tag.color, cfg.textSecondary);

        return AetherPressable(
          onTap: () async {
            await libraryProvider.tagSong(song.id, tag.id, !isBound);
          },
          borderRadius: BorderRadius.circular(AetherRadius.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AetherSpace.md,
              vertical: AetherSpace.xs,
            ),
            decoration: BoxDecoration(
              color: isBound
                  ? tagColor.withValues(alpha: 0.08)
                  : cfg.pressed,
              borderRadius: BorderRadius.circular(AetherRadius.sm),
              border: Border.all(
                color: isBound
                    ? tagColor
                    : cfg.borderSubtle.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isBound ? Icons.check_box : Icons.check_box_outline_blank,
                  size: AetherIconSize.sm,
                  color: isBound ? tagColor : cfg.textSecondary,
                ),
                const SizedBox(width: AetherSpace.sm),
                Expanded(
                  child: Text(
                    tag.name,
                    style: AetherType.captionStyle(tagColor).copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: AetherType.bodySm - 1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  if (activeTab == 'lyrics') {
    return LyricsDisplayPanel(
      song: song,
      audioVersion: displayVersionForSong(song, audioProvider),
      cfg: cfg,
      compact: true,
      onOpenManager: openLyricManager,
    );
  }

  if (activeTab == 'lyric_manager') {
    return LyricsPanel(
      song: song,
      audioVersion: displayVersionForSong(song, audioProvider),
      cfg: cfg,
      compact: true,
    );
  }

  return const SizedBox.shrink();
}
