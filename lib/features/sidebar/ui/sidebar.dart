import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/library/ui/settings_modal.dart';

class Sidebar extends StatelessWidget {
  final double width;

  const Sidebar({super.key, required this.width});

  @override
  Widget build(BuildContext context) {
    final libraryProvider = context.watch<LibraryProvider>();
    final cfg = context.watch<UIThemeProvider>().currentTheme;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: cfg.bgPanel,
        border: Border(right: BorderSide(color: cfg.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AetherSpace.xxl,
              AetherSpace.xxl,
              AetherSpace.xxl,
              AetherSpace.lg,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AetherSpace.md),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cfg.accent, cfg.accentHover],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AetherRadius.md),
                    boxShadow: [
                      BoxShadow(
                        color: cfg.accentGlow,
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.music_note_rounded,
                    color: cfg.onAccent,
                    size: AetherIconSize.xxl,
                  ),
                ),
                const SizedBox(width: AetherSpace.lg),
                Expanded(
                  child: Text(
                    'Aetheria',
                    style: AetherType.titleLgStyle(cfg.textPrimary).copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AetherSpace.lg),
              children: [
                _SidebarSectionLabel(label: '音乐库', cfgColor: cfg.textTertiary),
                _SidebarNavItem(
                  icon: Icons.library_music_rounded,
                  title: '全部歌曲',
                  count: libraryProvider.songs.length,
                  isActive: libraryProvider.activePlaylistId == null,
                  onTap: () => libraryProvider.setActivePlaylist(null),
                ),
                const SizedBox(height: AetherSpace.xxl),
                Row(
                  children: [
                    Expanded(
                      child: _SidebarSectionLabel(
                        label: '歌单',
                        cfgColor: cfg.textTertiary,
                      ),
                    ),
                    AetherIconButton(
                      icon: Icons.add_rounded,
                      onPressed: () =>
                          _showCreatePlaylistDialog(context, libraryProvider),
                      size: 28,
                      iconSize: AetherIconSize.md,
                      tooltip: '新建歌单',
                    ),
                  ],
                ),
                const SizedBox(height: AetherSpace.sm),
                if (libraryProvider.playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AetherSpace.md,
                      vertical: AetherSpace.sm,
                    ),
                    child: Text(
                      '还没有歌单',
                      style: AetherType.captionStyle(cfg.textTertiary),
                    ),
                  )
                else
                  ...libraryProvider.playlists.map(
                    (p) => _SidebarNavItem(
                      icon: Icons.queue_music_rounded,
                      title: p.name,
                      isActive: libraryProvider.activePlaylistId == p.id,
                      onTap: () => libraryProvider.setActivePlaylist(p.id),
                      onSecondaryTapUp: (details) {
                        _showPlaylistContextMenu(
                          context,
                          details.globalPosition,
                          p.id,
                          p.name,
                          libraryProvider,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: cfg.borderSubtle),
          Padding(
            padding: const EdgeInsets.all(AetherSpace.lg),
            child: _SidebarNavItem(
              icon: Icons.settings_rounded,
              title: '设置',
              isActive: false,
              onTap: () => SettingsModal.show(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreatePlaylistDialog(
    BuildContext context,
    LibraryProvider provider,
  ) async {
    final controller = TextEditingController();
    final created = await showAetherDialog<bool>(
      context: context,
      builder: (ctx) {
        return AetherDialog(
          title: '新建歌单',
          content: AetherTextField(
            controller: controller,
            hintText: '歌单名称',
            autofocus: true,
            onSubmitted: (_) => Navigator.of(ctx).pop(true),
          ),
          actions: [
            AetherButton.ghost(
              label: '取消',
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            AetherButton.primary(
              label: '创建',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        );
      },
    );

    final name = controller.text.trim();
    controller.dispose();
    if (created != true || name.isEmpty) return;

    try {
      await provider.createPlaylist(name);
    } catch (e) {
      if (context.mounted) {
        showAetherToast(
          context,
          message: '创建失败: $e',
          kind: AetherToastKind.error,
        );
      }
    }
  }

  Future<void> _showPlaylistContextMenu(
    BuildContext context,
    Offset position,
    String playlistId,
    String currentName,
    LibraryProvider provider,
  ) async {
    final cfg = context.tokens;
    final val = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 16, color: cfg.textSecondary),
              const SizedBox(width: AetherSpace.md),
              Text('重命名歌单', style: AetherType.bodyStyle(cfg.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 16, color: cfg.danger),
              const SizedBox(width: AetherSpace.md),
              Text('删除歌单', style: AetherType.bodyStyle(cfg.danger)),
            ],
          ),
        ),
      ],
    );

    if (!context.mounted) return;
    if (val == 'rename') {
      await _showRenamePlaylistDialog(
        context,
        playlistId,
        currentName,
        provider,
      );
    } else if (val == 'delete') {
      await _confirmDeletePlaylist(context, playlistId, currentName, provider);
    }
  }

  Future<void> _showRenamePlaylistDialog(
    BuildContext context,
    String id,
    String currentName,
    LibraryProvider provider,
  ) async {
    final controller = TextEditingController(text: currentName);
    final renamed = await showAetherDialog<bool>(
      context: context,
      builder: (ctx) {
        return AetherDialog(
          title: '重命名歌单',
          content: AetherTextField(
            controller: controller,
            hintText: '新歌单名称',
            autofocus: true,
            onSubmitted: (_) => Navigator.of(ctx).pop(true),
          ),
          actions: [
            AetherButton.ghost(
              label: '取消',
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            AetherButton.primary(
              label: '重命名',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        );
      },
    );

    final name = controller.text.trim();
    controller.dispose();
    if (renamed != true || name.isEmpty) return;

    try {
      await provider.renamePlaylist(id, name);
    } catch (e) {
      if (context.mounted) {
        showAetherToast(
          context,
          message: '命名失败: $e',
          kind: AetherToastKind.error,
        );
      }
    }
  }

  Future<void> _confirmDeletePlaylist(
    BuildContext context,
    String id,
    String name,
    LibraryProvider provider,
  ) async {
    final confirmed = await showAetherConfirmDialog(
      context: context,
      title: '删除歌单？',
      message: '确定删除歌单“$name”吗？这不会删除音乐库中的歌曲。',
      confirmLabel: '删除',
      dangerous: true,
    );
    if (!confirmed) return;

    try {
      await provider.deletePlaylist(id);
    } catch (e) {
      if (context.mounted) {
        showAetherToast(
          context,
          message: '删除失败: $e',
          kind: AetherToastKind.error,
        );
      }
    }
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  final String label;
  final Color cfgColor;

  const _SidebarSectionLabel({
    required this.label,
    required this.cfgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AetherSpace.md,
        bottom: AetherSpace.sm,
        top: 2,
      ),
      child: Text(
        label,
        style: AetherType.captionStyle(cfgColor).copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final int? count;
  final bool isActive;
  final VoidCallback onTap;
  final GestureTapUpCallback? onSecondaryTapUp;

  const _SidebarNavItem({
    required this.icon,
    required this.title,
    this.count,
    required this.isActive,
    required this.onTap,
    this.onSecondaryTapUp,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final radius = BorderRadius.circular(AetherRadius.md);

    final item = AetherPressable(
      onTap: onTap,
      borderRadius: radius,
      pressScale: AetherMotion.pressScaleSubtle,
      hoverColor: isActive ? null : cfg.bgHover,
      child: AnimatedContainer(
        duration: AetherMotion.fast,
        curve: AetherMotion.out,
        padding: const EdgeInsets.symmetric(
          horizontal: AetherSpace.lg,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: isActive ? cfg.accentMuted : Colors.transparent,
          borderRadius: radius,
          border: isActive
              ? Border(left: BorderSide(color: cfg.accent, width: 3))
              : Border(left: BorderSide(color: Colors.transparent, width: 3)),
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
                style: AetherType.bodyStyle(
                  isActive ? cfg.textPrimary : cfg.textSecondary,
                ).copyWith(
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (count != null)
              Text(
                count.toString(),
                style: AetherType.captionStyle(cfg.textTertiary),
              ),
          ],
        ),
      ),
    );

    if (onSecondaryTapUp == null) return item;

    return GestureDetector(
      onSecondaryTapUp: onSecondaryTapUp,
      child: item,
    );
  }
}
