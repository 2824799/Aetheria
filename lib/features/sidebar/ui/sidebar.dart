import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/library/ui/settings_modal.dart';

class Sidebar extends StatelessWidget {
  final double width;

  const Sidebar({super.key, required this.width});

  @override
  Widget build(BuildContext context) {
    final libraryProvider = context.watch<LibraryProvider>();
    final themeProvider = context.watch<UIThemeProvider>();
    final cfg = themeProvider.currentTheme;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: cfg.bgPanel,
        border: Border(right: BorderSide(color: cfg.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo Section
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cfg.accent, cfg.accentHover],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: cfg.accentGlow,
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.music_note,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Aetheria',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: cfg.textMain,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
          ),

          // Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildMenuTitle('音乐库', cfg),
                _buildMenuItem(
                  icon: Icons.library_music,
                  title: '全部歌曲',
                  count: libraryProvider.songs.length,
                  isActive: libraryProvider.activePlaylistId == null,
                  onTap: () => libraryProvider.setActivePlaylist(null),
                  cfg: cfg,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMenuTitle('歌单', cfg),
                    IconButton(
                      icon: Icon(Icons.add, size: 16, color: cfg.textSub),
                      onPressed: () =>
                          _showCreatePlaylistDialog(context, libraryProvider),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...libraryProvider.playlists.map(
                  (p) => _buildPlaylistItem(
                    context,
                    playlistId: p.id,
                    title: p.name,
                    isActive: libraryProvider.activePlaylistId == p.id,
                    onTap: () => libraryProvider.setActivePlaylist(p.id),
                    provider: libraryProvider,
                    cfg: cfg,
                  ),
                ),
              ],
            ),
          ),

          // Bottom Actions
          Divider(height: 1, color: cfg.border),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: _buildMenuItem(
              icon: Icons.settings,
              title: '设置',
              isActive: false,
              onTap: () => SettingsModal.show(context),
              cfg: cfg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTitle(String title, AppThemeConfig cfg) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: cfg.textSub,
          fontFamily: 'Outfit',
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    int? count,
    required bool isActive,
    required VoidCallback onTap,
    required AppThemeConfig cfg,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isActive ? cfg.bgHover : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? Border(left: BorderSide(color: cfg.accent, width: 3))
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isActive ? cfg.accent : cfg.textSub),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive ? cfg.textMain : cfg.textSub,
                  fontFamily: 'Outfit',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (count != null)
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 11,
                  color: cfg.textSub,
                  fontFamily: 'Outfit',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistItem(
    BuildContext context, {
    required String playlistId,
    required String title,
    required bool isActive,
    required VoidCallback onTap,
    required LibraryProvider provider,
    required AppThemeConfig cfg,
  }) {
    return GestureDetector(
      onSecondaryTapUp: (details) {
        _showPlaylistContextMenu(
          context,
          details.globalPosition,
          playlistId,
          title,
          provider,
        );
      },
      child: _buildMenuItem(
        icon: Icons.queue_music,
        title: title,
        isActive: isActive,
        onTap: onTap,
        cfg: cfg,
      ),
    );
  }

  void _showCreatePlaylistDialog(
    BuildContext context,
    LibraryProvider provider,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '歌单名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(ctx).pop();
                try {
                  await provider.createPlaylist(name);
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('创建失败: $e')));
                }
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showPlaylistContextMenu(
    BuildContext context,
    Offset position,
    String playlistId,
    String currentName,
    LibraryProvider provider,
  ) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit, size: 16),
              SizedBox(width: 8),
              Text('重命名歌单'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.redAccent, size: 16),
              SizedBox(width: 8),
              Text('删除歌单', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
    ).then((val) {
      if (val == 'rename') {
        _showRenamePlaylistDialog(context, playlistId, currentName, provider);
      } else if (val == 'delete') {
        _confirmDeletePlaylist(context, playlistId, currentName, provider);
      }
    });
  }

  void _showRenamePlaylistDialog(
    BuildContext context,
    String id,
    String currentName,
    LibraryProvider provider,
  ) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名歌单'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '新歌单名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(ctx).pop();
                try {
                  await provider.renamePlaylist(id, name);
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('命名失败: $e')));
                }
              }
            },
            child: const Text('重命名'),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePlaylist(
    BuildContext context,
    String id,
    String name,
    LibraryProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除歌单？'),
        content: Text('您确定要删除歌单“$name”吗？这不会删除音乐库中的歌曲。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await provider.deletePlaylist(id);
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
