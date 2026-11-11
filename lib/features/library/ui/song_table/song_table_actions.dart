import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/widgets/aether_menu.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/library/song_actions.dart';

const String _playlistPrefix = 'playlist:';

/// Opens the row context menu for [songIds] and runs the chosen command.
///
/// [onDeleted] runs after the songs were removed from the library.
Future<void> showSongTableContextMenu({
  required BuildContext context,
  required Offset position,
  required List<String> songIds,
  required LibraryProvider library,
  required VoidCallback onDeleted,
}) async {
  final command = await showAetherMenu<String>(
    context: context,
    globalPosition: position,
    items: _menuItems(library),
  );
  if (command == null || !context.mounted) return;

  final playlistId = library.activePlaylistId;
  try {
    if (command.startsWith(_playlistPrefix)) {
      final id = command.substring(_playlistPrefix.length);
      for (final playlist in library.playlists) {
        if (playlist.id == id) {
          await addSongsToPlaylistWithToast(context, library, playlist, songIds);
          break;
        }
      }
      return;
    }
    switch (command) {
      case 'copy':
        library.setClipboard(SongClipboardMode.copy, songIds, playlistId);
      case 'cut':
        library.setClipboard(SongClipboardMode.cut, songIds, playlistId);
      case 'delete':
        if (await deleteSongsWithConfirm(context, library, songIds)) {
          onDeleted();
        }
      case 'remove_playlist':
        if (playlistId != null) {
          await library.removeSongsFromPlaylist(playlistId, songIds);
        }
      case 'paste':
        if (playlistId != null) {
          await library.pasteSongs(playlistId);
        }
    }
  } catch (e) {
    if (!context.mounted) return;
    showAetherToast(
      context,
      message: '操作失败: $e',
      kind: AetherToastKind.error,
    );
  }
}

List<AetherMenuItem<String>> _menuItems(LibraryProvider library) {
  final inPlaylist = library.activePlaylistId != null;
  final clipboardCount = library.clipboard?.songIds.length;
  return [
    const AetherMenuItem(
      value: 'copy',
      label: '复制所选歌曲',
      icon: Icons.copy_rounded,
    ),
    const AetherMenuItem(
      value: 'cut',
      label: '剪切所选歌曲',
      icon: Icons.content_cut_rounded,
    ),
    if (inPlaylist && clipboardCount != null)
      AetherMenuItem(
        value: 'paste',
        label: '粘贴歌曲 ($clipboardCount 首)',
        icon: Icons.content_paste_rounded,
      ),
    if (library.playlists.isNotEmpty) ...[
      const AetherMenuItem.divider(),
      for (final playlist in library.playlists)
        AetherMenuItem(
          value: '$_playlistPrefix${playlist.id}',
          label: '添加到歌单 · ${playlist.name}',
          icon: Icons.playlist_add_rounded,
        ),
    ],
    const AetherMenuItem.divider(),
    if (inPlaylist)
      const AetherMenuItem(
        value: 'remove_playlist',
        label: '从当前歌单移除',
        icon: Icons.playlist_remove_rounded,
        warning: true,
      ),
    const AetherMenuItem(
      value: 'delete',
      label: '彻底删除歌曲',
      icon: Icons.delete_outline_rounded,
      destructive: true,
    ),
  ];
}
