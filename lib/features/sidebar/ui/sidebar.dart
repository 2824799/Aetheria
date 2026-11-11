import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_menu.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/features/library/playlist_actions.dart';
import 'package:aetheria/features/library/ui/settings_modal.dart';
import 'package:aetheria/src/rust/models/playlist.dart';

/// Desktop navigation: the whole library, the playlists, and settings.
class Sidebar extends StatelessWidget {
  final double width;

  const Sidebar({super.key, required this.width});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final cfg = context.tokens;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: cfg.bg1,
        border: Border(right: BorderSide(color: cfg.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Brand(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AetherSpace.lg),
              children: [
                _NavItem(
                  icon: Icons.library_music_outlined,
                  title: '全部歌曲',
                  count: library.songs.length,
                  isActive: library.activePlaylistId == null,
                  onTap: () => library.setActivePlaylist(null),
                ),
                const SizedBox(height: AetherSpace.xxl),
                Padding(
                  padding: const EdgeInsets.only(
                    left: AetherSpace.lg,
                    bottom: AetherSpace.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '歌单',
                          style: AetherType.labelStyle(cfg.textTertiary),
                        ),
                      ),
                      AetherIconButton(
                        icon: Icons.add_rounded,
                        onPressed: () =>
                            createPlaylistWithDialog(context, library),
                        size: 28,
                        iconSize: AetherIconSize.md,
                        tooltip: '新建歌单',
                      ),
                    ],
                  ),
                ),
                if (library.playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AetherSpace.lg,
                      vertical: AetherSpace.sm,
                    ),
                    child: Text(
                      '点击 + 新建第一个歌单',
                      style: AetherType.bodySmStyle(cfg.textTertiary),
                    ),
                  ),
                for (final playlist in library.playlists)
                  _NavItem(
                    icon: Icons.queue_music_rounded,
                    title: playlist.name,
                    isActive: library.activePlaylistId == playlist.id,
                    onTap: () => library.setActivePlaylist(playlist.id),
                    onContextMenu: (position) =>
                        _showPlaylistMenu(context, position, playlist, library),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AetherSpace.lg),
            child: _NavItem(
              icon: Icons.settings_outlined,
              title: '设置',
              isActive: false,
              onTap: () => SettingsModal.show(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPlaylistMenu(
    BuildContext context,
    Offset position,
    Playlist playlist,
    LibraryProvider library,
  ) async {
    final choice = await showAetherMenu<String>(
      context: context,
      globalPosition: position,
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
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AetherSpace.xxl,
        AetherSpace.xxl,
        AetherSpace.xxl,
        AetherSpace.xxl,
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: cfg.accent,
              borderRadius: BorderRadius.circular(AetherRadius.md - 2),
            ),
            child: Icon(
              Icons.graphic_eq_rounded,
              color: cfg.onAccent,
              size: AetherIconSize.lg,
            ),
          ),
          const SizedBox(width: AetherSpace.lg),
          Expanded(
            child: Text(
              'Aetheria',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AetherType.titleStyle(
                cfg.textPrimary,
              ).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.title,
    required this.isActive,
    required this.onTap,
    this.count,
    this.onContextMenu,
  });

  final IconData icon;
  final String title;
  final int? count;
  final bool isActive;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final radius = BorderRadius.circular(AetherRadius.md);
    final count = this.count;
    final onContextMenu = this.onContextMenu;

    final item = AetherPressable(
      onTap: onTap,
      borderRadius: radius,
      pressScale: AetherMotion.pressScaleSubtle,
      hoverColor: isActive ? null : cfg.bgHover,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AetherSpace.lg),
        decoration: BoxDecoration(
          color: isActive ? cfg.accentMuted : null,
          borderRadius: radius,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: AetherIconSize.lg,
              color: isActive ? cfg.accent : cfg.textSecondary,
            ),
            const SizedBox(width: AetherSpace.lg),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AetherType.bodyStyle(
                  isActive ? cfg.textPrimary : cfg.textSecondary,
                ).copyWith(
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (count != null)
              Text(
                '$count',
                style: AetherType.bodySmStyle(cfg.textTertiary),
              ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AetherSpace.xxs),
      child: onContextMenu == null
          ? item
          : GestureDetector(
              onSecondaryTapUp: (details) =>
                  onContextMenu(details.globalPosition),
              child: item,
            ),
    );
  }
}
