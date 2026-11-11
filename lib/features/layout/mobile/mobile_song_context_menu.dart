import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_chip.dart';
import 'package:aetheria/core/widgets/aether_list_tile.dart';
import 'package:aetheria/core/widgets/aether_sheet.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/layout/mobile/mobile_actions.dart';
import 'package:aetheria/features/library/song_actions.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// Long-press sheet for a song in the mobile list.
///
/// Every action closes the sheet first and then runs against [context], the
/// list's context, which outlives the sheet.
void showMobileSongContextMenu(
  BuildContext context,
  Song song,
  LibraryProvider library,
  AudioPlayerProvider audio,
) {
  Future<void> run(BuildContext sheet, Future<void> Function() action) async {
    Navigator.of(sheet).pop();
    try {
      await action();
    } catch (e) {
      if (!context.mounted) return;
      showAetherToast(
        context,
        message: '操作失败: $e',
        kind: AetherToastKind.error,
      );
    }
  }

  showAetherSheet<void>(
    context: context,
    builder: (sheet) {
      final cfg = sheet.tokens;
      final playlistId = library.activePlaylistId;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AetherSpace.lg,
            AetherSpace.xs,
            AetherSpace.lg,
            AetherSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AetherSpace.lg,
                  0,
                  AetherSpace.lg,
                  AetherSpace.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AetherType.titleStyle(cfg.textPrimary),
                    ),
                    const SizedBox(height: AetherSpace.xxs),
                    Text(
                      song.artist ?? '未知歌手',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AetherType.bodySmStyle(cfg.textSecondary),
                    ),
                  ],
                ),
              ),
              AetherListTile(
                icon: Icons.play_arrow_rounded,
                title: '播放',
                onTap: () => run(
                  sheet,
                  () => mobilePlaySong(context, song, library, audio),
                ),
              ),
              AetherListTile(
                icon: Icons.info_outline_rounded,
                title: '歌曲详情',
                onTap: () {
                  Navigator.of(sheet).pop();
                  mobileOpenSongDetail(context, song, audio);
                },
              ),
              if (library.playlists.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AetherSpace.lg,
                    AetherSpace.lg,
                    AetherSpace.lg,
                    AetherSpace.md,
                  ),
                  child: Text(
                    '添加到歌单',
                    style: AetherType.labelStyle(cfg.textTertiary),
                  ),
                ),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AetherSpace.lg,
                    ),
                    itemCount: library.playlists.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AetherSpace.sm),
                    itemBuilder: (_, index) {
                      final playlist = library.playlists[index];
                      return AetherChip(
                        label: playlist.name,
                        onTap: () => run(
                          sheet,
                          () => addSongsToPlaylistWithToast(
                            context,
                            library,
                            playlist,
                            [song.id],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AetherSpace.md),
              ],
              if (playlistId != null)
                AetherListTile(
                  icon: Icons.playlist_remove_rounded,
                  title: '从当前歌单移除',
                  warning: true,
                  onTap: () => run(
                    sheet,
                    () => library.removeSongsFromPlaylist(playlistId, [
                      song.id,
                    ]),
                  ),
                ),
              AetherListTile(
                icon: Icons.delete_outline_rounded,
                title: '彻底删除歌曲',
                destructive: true,
                onTap: () => run(
                  sheet,
                  () => deleteSongsWithConfirm(context, library, [song.id]),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
