import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/layout/mobile/mobile_actions.dart';
import 'package:aetheria/features/layout/mobile/mobile_dialogs.dart';
import 'package:aetheria/features/layout/mobile/mobile_utils.dart';
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
              final durationMin = (v.duration / 60).floor();
              final durationSec = (v.duration % 60)
                  .round()
                  .toString()
                  .padLeft(2, '0');

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
                      '${v.format?.toUpperCase() ?? "未知"} | ${(v.bitrate ?? 0) ~/ 1000}kbps | ${v.sampleRate != null ? (v.sampleRate! / 1000).toStringAsFixed(1) : "未知"}kHz | $durationMin:$durationSec | ${mobileFormatFileSize(v.fileSize.toInt())}',
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
                                : () async {
                                    final shouldSwitch =
                                        audioProvider.playingSong?.id ==
                                            song.id &&
                                        audioProvider.playingVersion?.id !=
                                            v.id;
                                    final position =
                                        audioProvider.currentPosition;
                                    final startPaused =
                                        !audioProvider.isPlaying;
                                    await libraryProvider.setPrimaryVersion(
                                      v.id,
                                    );
                                    if (!shouldSwitch || !context.mounted) {
                                      return;
                                    }
                                    final updatedSong =
                                        libraryProvider.songs.firstWhere(
                                      (entry) => entry.id == song.id,
                                      orElse: () => song,
                                    );
                                    final updatedVersion =
                                        updatedSong.versions.firstWhere(
                                      (entry) => entry.id == v.id,
                                      orElse: () => v,
                                    );
                                    await audioProvider.switchToVersion(
                                      updatedSong,
                                      updatedVersion,
                                      libraryProvider.libraryPath,
                                      audioServerPort:
                                          libraryProvider.audioServerPort,
                                      startPosition: position,
                                      startPaused: startPaused,
                                    );
                                  },
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
                          onPressed: () => mobileExportVersion(context, v),
                        ),
                        if (song.versions.length > 1) ...[
                          const SizedBox(width: AetherSpace.sm),
                          AetherIconButton.dense(
                            icon: Icons.delete_outline,
                            color: cfg.danger,
                            tooltip: '删除版本',
                            onPressed: () async {
                              final confirm =
                                  await mobileConfirmDeleteVersion(context, v);
                              if (!confirm) return;
                              try {
                                await libraryProvider.deleteAudioVersion(v.id);
                                if (!context.mounted) return;
                                showAetherToast(
                                  context,
                                  message: '音源版本已删除',
                                  kind: AetherToastKind.success,
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                showAetherToast(
                                  context,
                                  message: '删除失败: $e',
                                  kind: AetherToastKind.error,
                                );
                              }
                            },
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
            onPressed: () =>
                mobileLinkNewVersion(context, song, libraryProvider),
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
        final tagColor = tag.color != null
            ? mobileParseHexColor(tag.color!, cfg.textSecondary)
            : cfg.textSecondary;

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
      audioVersion: mobileDisplayVersionForSong(song, audioProvider),
      cfg: cfg,
      compact: true,
      onOpenManager: openLyricManager,
    );
  }

  if (activeTab == 'lyric_manager') {
    return LyricsPanel(
      song: song,
      audioVersion: mobileDisplayVersionForSong(song, audioProvider),
      cfg: cfg,
      compact: true,
    );
  }

  return const SizedBox.shrink();
}
