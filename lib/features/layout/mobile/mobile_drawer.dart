import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_list_tile.dart';
import 'package:aetheria/core/widgets/aether_menu.dart';
import 'package:aetheria/features/library/playlist_actions.dart';
import 'package:aetheria/src/rust/models/playlist.dart';

/// Mobile navigation drawer: the whole library and the playlists.
class MobilePlaylistDrawer extends StatelessWidget {
  const MobilePlaylistDrawer({super.key, required this.library});

  final LibraryProvider library;

  void _select(BuildContext context, String? playlistId) {
    library.setActivePlaylist(playlistId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final activeId = library.activePlaylistId;

    return Drawer(
      backgroundColor: cfg.bgElevated,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AetherSpace.xxl,
                AetherSpace.xl,
                AetherSpace.md,
                AetherSpace.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '音乐库',
                      style: AetherType.titleLgStyle(cfg.textPrimary),
                    ),
                  ),
                  AetherIconButton(
                    icon: Icons.add_rounded,
                    tooltip: '新建歌单',
                    onPressed: () => createPlaylistWithDialog(context, library),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AetherSpace.lg,
                  vertical: AetherSpace.xs,
                ),
                children: [
                  AetherListTile(
                    icon: Icons.library_music_outlined,
                    title: '全部歌曲',
                    trailing: Text(
                      '${library.songs.length}',
                      style: AetherType.bodySmStyle(cfg.textTertiary),
                    ),
                    selected: activeId == null,
                    onTap: () => _select(context, null),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AetherSpace.lg,
                      AetherSpace.xl,
                      AetherSpace.lg,
                      AetherSpace.sm,
                    ),
                    child: Text(
                      '歌单',
                      style: AetherType.labelStyle(cfg.textTertiary),
                    ),
                  ),
                  if (library.playlists.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AetherSpace.lg,
                      ),
                      child: Text(
                        '点击右上角的 + 新建第一个歌单',
                        style: AetherType.bodySmStyle(cfg.textTertiary),
                      ),
                    ),
                  for (final playlist in library.playlists)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AetherSpace.xs),
                      child: AetherListTile(
                        icon: Icons.queue_music_rounded,
                        title: playlist.name,
                        selected: activeId == playlist.id,
                        onTap: () => _select(context, playlist.id),
                        trailing: _PlaylistMenuButton(
                          playlist: playlist,
                          library: library,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistMenuButton extends StatelessWidget {
  const _PlaylistMenuButton({required this.playlist, required this.library});

  final Playlist playlist;
  final LibraryProvider library;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final choice = await showAetherMenu<String>(
      context: context,
      globalPosition: box.localToGlobal(Offset(0, box.size.height)),
      items: const [
        AetherMenuItem(
          value: 'rename',
          label: '重命名',
          icon: Icons.edit_outlined,
        ),
        AetherMenuItem(
          value: 'delete',
          label: '删除歌单',
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ],
    );
    if (!context.mounted) return;
    if (choice == 'rename') {
      await renamePlaylistWithDialog(context, library, playlist);
    } else if (choice == 'delete') {
      await deletePlaylistWithConfirm(context, library, playlist);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AetherIconButton(
      icon: Icons.more_horiz_rounded,
      size: 40,
      iconSize: AetherIconSize.lg,
      tooltip: '歌单操作',
      onPressed: () => _open(context),
    );
  }
}
