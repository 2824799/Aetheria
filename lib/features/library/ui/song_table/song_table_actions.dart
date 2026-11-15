import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/widgets/aether_menu.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/library/song_actions.dart';
import 'package:aetheria/features/phigros/phigros_badges.dart';
import 'package:aetheria/src/rust/models/song.dart';

const String _playlistPrefix = 'playlist:';
const String _phigrosDiffPrefix = 'phi_diff:';

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
  Song? singlePhigrosSong;
  if (songIds.length == 1) {
    final targetId = songIds.first;
    for (final s in library.songs) {
      if (s.id == targetId && s.phigros != null) {
        singlePhigrosSong = s;
        break;
      }
    }
  }
  final command = await showAetherMenu<String>(
    context: context,
    globalPosition: position,
    items: _menuItems(library, singlePhigrosSong),
  );
  if (command == null || !context.mounted) return;

  final playlistId = library.activePlaylistId;
  try {
    if (command.startsWith(_phigrosDiffPrefix) && singlePhigrosSong != null) {
      final diff = command.substring(_phigrosDiffPrefix.length);
      await changePhigrosDifficultyAndSync(
        context,
        library,
        singlePhigrosSong,
        diff,
      );
      return;
    }
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

List<AetherMenuItem<String>> _menuItems(
  LibraryProvider library,
  Song? singlePhigrosSong,
) {
  final inPlaylist = library.activePlaylistId != null;
  final clipboardCount = library.clipboard?.songIds.length;
  final phigros = singlePhigrosSong?.phigros;
  return [
    if (phigros != null && phigros.charts.isNotEmpty) ...[
      for (final chart in phigros.charts)
        AetherMenuItem(
          value: '$_phigrosDiffPrefix${chart.difficulty}',
          label:
              '切换难度 · ${formatPhigrosDiffBadgeLabel(chart)}${chart.difficulty == phigros.selectedDifficulty ? ' ✓' : ''}',
          icon: Icons.sports_esports_rounded,
        ),
      const AetherMenuItem.divider(),
    ],
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
