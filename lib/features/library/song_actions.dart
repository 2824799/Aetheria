import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/src/rust/models/playlist.dart';

// Song actions shared by the desktop table menu and the mobile song sheet.
// They throw on failure; the caller decides how to report it.

/// Adds [songIds] to [playlist] and confirms with a toast.
Future<void> addSongsToPlaylistWithToast(
  BuildContext context,
  LibraryProvider library,
  Playlist playlist,
  List<String> songIds,
) async {
  await library.addSongsToPlaylist(playlist.id, songIds);
  if (!context.mounted) return;
  showAetherToast(
    context,
    message: '已添加到歌单「${playlist.name}」',
    kind: AetherToastKind.success,
  );
}

/// Deletes [songIds] and their audio files after a double confirmation.
/// Returns true when the songs were deleted.
Future<bool> deleteSongsWithConfirm(
  BuildContext context,
  LibraryProvider library,
  List<String> songIds,
) async {
  final summary = _describeSongs(songIds, library);
  final confirmed = await showAetherConfirmDialog(
    context: context,
    title: '删除歌曲？',
    message: '即将从音乐库中删除 $summary，并同时删除本地物理音频文件。',
    confirmLabel: '继续删除',
    dangerous: true,
    doubleConfirm: true,
    doubleConfirmTitle: '再次确认彻底删除',
    doubleConfirmMessage: '最后确认：$summary 的数据库记录和本地音频文件都会被删除，此操作不可撤销。',
    doubleConfirmLabel: '彻底删除',
  );
  if (!confirmed) return false;

  for (final id in songIds) {
    await library.deleteSong(id);
  }
  if (context.mounted) {
    showAetherToast(
      context,
      message: songIds.length == 1 ? '歌曲已删除' : '已删除 ${songIds.length} 首歌曲',
      kind: AetherToastKind.success,
    );
  }
  return true;
}

String _describeSongs(List<String> songIds, LibraryProvider library) {
  final titleById = {for (final song in library.songs) song.id: song.title};
  final titles = [for (final id in songIds) ?titleById[id]];
  if (titles.isEmpty) {
    return songIds.length == 1 ? '这首歌曲' : '这 ${songIds.length} 首歌曲';
  }
  final preview = titles.take(3).map((title) => '《$title》').join('、');
  return songIds.length > 3 ? '$preview 等 ${songIds.length} 首歌曲' : preview;
}
