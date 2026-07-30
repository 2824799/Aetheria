import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_list_tile.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';
import 'package:aetheria/features/layout/mobile/mobile_dialogs.dart';
import 'package:aetheria/src/rust/models/playlist.dart';

class MobilePlaylistDrawer extends StatelessWidget {
  final LibraryProvider libraryProvider;
  final AppThemeConfig cfg;

  const MobilePlaylistDrawer({
    super.key,
    required this.libraryProvider,
    required this.cfg,
  });

  @override
  Widget build(BuildContext context) {
    final playlists = libraryProvider.playlists;
    final activePlaylistId = libraryProvider.activePlaylistId;

    return Drawer(
      backgroundColor: Colors.transparent,
      child: AetherSurface(
        level: AetherSurfaceLevel.glass,
        borderRadius: BorderRadius.zero,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(AetherSpace.xxl),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '我的歌单',
                      style: AetherType.titleLgStyle(cfg.textPrimary),
                    ),
                    AetherIconButton(
                      icon: Icons.add,
                      tooltip: '新建歌单',
                      onPressed: () => mobileShowCreatePlaylistDialog(
                        context,
                        libraryProvider,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: cfg.borderSubtle),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AetherSpace.lg,
                    vertical: AetherSpace.md,
                  ),
                  children: [
                    AetherListTile(
                      leading: Icon(
                        Icons.library_music,
                        color: activePlaylistId == null
                            ? cfg.accent
                            : cfg.textSecondary,
                      ),
                      title: '全部音乐',
                      trailing: Text(
                        '${libraryProvider.songs.length}',
                        style: AetherType.bodySmStyle(cfg.textSecondary),
                      ),
                      selected: activePlaylistId == null,
                      onTap: () {
                        libraryProvider.setActivePlaylist(null);
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(height: AetherSpace.md),
                    ...playlists.map((Playlist pl) {
                      final selected = activePlaylistId == pl.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AetherSpace.xs),
                        child: AetherListTile(
                          leading: Icon(
                            Icons.queue_music,
                            color: selected ? cfg.accent : cfg.textSecondary,
                          ),
                          title: pl.name,
                          selected: selected,
                          onTap: () {
                            libraryProvider.setActivePlaylist(pl.id);
                            Navigator.of(context).pop();
                          },
                          trailing: PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              color: cfg.textSecondary,
                              size: 18,
                            ),
                            color: cfg.bgPopover,
                            onSelected: (value) {
                              if (value == 'rename') {
                                mobileShowRenamePlaylistDialog(
                                  context,
                                  id: pl.id,
                                  currentName: pl.name,
                                  provider: libraryProvider,
                                );
                              } else if (value == 'delete') {
                                mobileConfirmDeletePlaylist(
                                  context,
                                  id: pl.id,
                                  name: pl.name,
                                  provider: libraryProvider,
                                );
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text(
                                  '重命名歌单',
                                  style: AetherType.bodySmStyle(cfg.textPrimary),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete,
                                      color: cfg.danger,
                                      size: 16,
                                    ),
                                    const SizedBox(width: AetherSpace.md),
                                    Text(
                                      '删除歌单',
                                      style: AetherType.bodySmStyle(cfg.danger)
                                          .copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
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
