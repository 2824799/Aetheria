import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/src/rust/models/playlist.dart';

// Playlist dialogs shared by the desktop sidebar and the mobile drawer.

/// Asks for a name and creates a playlist.
Future<void> createPlaylistWithDialog(
  BuildContext context,
  LibraryProvider library,
) async {
  final name = await _askPlaylistName(
    context,
    title: '新建歌单',
    confirmLabel: '创建',
  );
  if (name == null || !context.mounted) return;
  await _run(context, '创建失败', () => library.createPlaylist(name));
}

/// Asks for a new name and renames [playlist].
Future<void> renamePlaylistWithDialog(
  BuildContext context,
  LibraryProvider library,
  Playlist playlist,
) async {
  final name = await _askPlaylistName(
    context,
    title: '重命名歌单',
    confirmLabel: '保存',
    initialName: playlist.name,
  );
  if (name == null || name == playlist.name || !context.mounted) return;
  await _run(
    context,
    '重命名失败',
    () => library.renamePlaylist(playlist.id, name),
  );
}

/// Deletes [playlist] after a confirmation. Its songs stay in the library.
Future<void> deletePlaylistWithConfirm(
  BuildContext context,
  LibraryProvider library,
  Playlist playlist,
) async {
  final confirmed = await showAetherConfirmDialog(
    context: context,
    title: '删除歌单？',
    message: '确定删除歌单“${playlist.name}”吗？这不会删除音乐库中的歌曲。',
    confirmLabel: '删除',
    dangerous: true,
  );
  if (!confirmed || !context.mounted) return;
  await _run(context, '删除失败', () => library.deletePlaylist(playlist.id));
}

/// Returns the trimmed name, or null when cancelled or left empty.
Future<String?> _askPlaylistName(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialName = '',
}) async {
  final controller = TextEditingController(text: initialName);
  final confirmed = await showAetherDialog<bool>(
    context: context,
    builder: (ctx) => AetherDialog(
      title: title,
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
          label: confirmLabel,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  final name = controller.text.trim();
  controller.dispose();
  return confirmed == true && name.isNotEmpty ? name : null;
}

Future<void> _run(
  BuildContext context,
  String failureLabel,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (!context.mounted) return;
    showAetherToast(
      context,
      message: '$failureLabel: $e',
      kind: AetherToastKind.error,
    );
  }
}
