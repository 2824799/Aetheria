import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_chip.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_list_tile.dart';
import 'package:aetheria/core/widgets/aether_sheet.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/layout/mobile/mobile_dialogs.dart';
import 'package:aetheria/features/layout/mobile/mobile_song_detail_sheet.dart';
import 'package:aetheria/src/rust/models/song.dart';

void showMobileSongContextMenu(
  BuildContext context,
  Song song,
  LibraryProvider libraryProvider,
  AudioPlayerProvider audioProvider,
) {
  final cfg = context.tokens;

  showAetherSheet(
    context: context,
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AetherSpace.xl,
          AetherSpace.sm,
          AetherSpace.xl,
          AetherSpace.xxl,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                song.title,
                style: AetherType.titleStyle(cfg.textPrimary),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AetherSpace.xs),
              Text(
                song.artist ?? '未知歌手',
                style: AetherType.bodySmStyle(cfg.textSecondary),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AetherSpace.xl),
              AetherListTile(
                icon: Icons.play_arrow,
                title: '播放歌曲',
                onTap: () async {
                  Navigator.of(ctx).pop();
                  try {
                    await audioProvider.playSong(
                      song,
                      libraryProvider.displaySongs,
                      libraryProvider.libraryPath,
                      audioServerPort: libraryProvider.audioServerPort,
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    showAetherDialog<void>(
                      context: context,
                      builder: (dialogCtx) => AetherDialog(
                        title: '播放失败 - 诊断报告',
                        content: SelectableText(
                          e.toString(),
                          style: AetherType.captionStyle(
                            dialogCtx.tokens.textSecondary,
                          ).copyWith(fontFamily: 'monospace'),
                        ),
                        actions: [
                          AetherButton.primary(
                            label: '关闭',
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                          ),
                        ],
                      ),
                    );
                  }
                },
              ),
              AetherListTile(
                icon: Icons.info_outline,
                title: '打开详细信息',
                onTap: () {
                  Navigator.of(ctx).pop();
                  audioProvider.setActiveSong(song);
                  showAetherSheet(
                    context: context,
                    isScrollControlled: true,
                    decorate: false,
                    maxHeightFactor: 0.95,
                    builder: (_) => MobileSongDetailSheet(initialSong: song),
                  );
                },
              ),
              if (libraryProvider.playlists.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AetherSpace.md,
                    vertical: AetherSpace.md,
                  ),
                  child: Text(
                    '添加到歌单',
                    style: AetherType.labelStyle(cfg.textSecondary),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AetherSpace.md,
                    ),
                    itemCount: libraryProvider.playlists.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: AetherSpace.sm),
                    itemBuilder: (context, index) {
                      final pl = libraryProvider.playlists[index];
                      return AetherChip(
                        label: pl.name,
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          try {
                            await libraryProvider.addSongsToPlaylist(
                              pl.id,
                              [song.id],
                            );
                            if (!context.mounted) return;
                            showAetherToast(
                              context,
                              message: '已添加至歌单《${pl.name}》',
                              kind: AetherToastKind.success,
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            showAetherToast(
                              context,
                              message: '添加失败: $e',
                              kind: AetherToastKind.error,
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: AetherSpace.md),
              ],
              if (libraryProvider.activePlaylistId != null)
                AetherListTile(
                  icon: Icons.remove_circle_outline,
                  title: '从当前歌单移除',
                  warning: true,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    try {
                      await libraryProvider.removeSongsFromPlaylist(
                        libraryProvider.activePlaylistId!,
                        [song.id],
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      showAetherToast(
                        context,
                        message: '移除失败: $e',
                        kind: AetherToastKind.error,
                      );
                    }
                  },
                ),
              AetherListTile(
                icon: Icons.delete_forever,
                title: '彻底删除歌曲',
                destructive: true,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final confirm = await mobileConfirmDeleteSong(context, song);
                  if (confirm == true) {
                    try {
                      await libraryProvider.deleteSong(song.id);
                    } catch (e) {
                      if (!context.mounted) return;
                      showAetherToast(
                        context,
                        message: '删除失败: $e',
                        kind: AetherToastKind.error,
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}
