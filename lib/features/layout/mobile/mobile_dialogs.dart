import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/src/rust/models/song.dart';

Future<bool> mobileConfirmDeleteSong(BuildContext context, Song song) {
  return showAetherConfirmDialog(
    context: context,
    title: '删除歌曲？',
    message: '即将从音乐库中删除《${song.title}》，并同时删除本地物理音频文件。',
    confirmLabel: '继续删除',
    cancelLabel: '取消',
    dangerous: true,
    doubleConfirm: true,
    doubleConfirmTitle: '再次确认彻底删除',
    doubleConfirmMessage:
        '最后确认：《${song.title}》的数据库记录和本地音频文件都会被删除，此操作不可撤销。',
    doubleConfirmLabel: '彻底删除',
  );
}

Future<bool> mobileConfirmDeleteVersion(
  BuildContext context,
  AudioVersion version,
) {
  return showAetherConfirmDialog(
    context: context,
    title: '删除音源版本？',
    message: '确定要删除音源版本“${version.originalName}”吗？这会同时删除对应的本地音频文件。',
    confirmLabel: '删除版本',
    cancelLabel: '取消',
    dangerous: true,
  );
}

Future<void> mobileConfirmDeletePlaylist(
  BuildContext context, {
  required String id,
  required String name,
  required LibraryProvider provider,
}) async {
  final confirmed = await showAetherConfirmDialog(
    context: context,
    title: '删除歌单？',
    message: '您确定要删除歌单“$name”吗？这不会删除音乐库中的歌曲。',
    confirmLabel: '删除',
    cancelLabel: '取消',
    dangerous: true,
  );
  if (!confirmed || !context.mounted) return;
  try {
    await provider.deletePlaylist(id);
  } catch (e) {
    if (!context.mounted) return;
    showAetherToast(
      context,
      message: '删除失败: $e',
      kind: AetherToastKind.error,
    );
  }
}

void mobileShowCreatePlaylistDialog(
  BuildContext context,
  LibraryProvider provider,
) {
  final controller = TextEditingController();
  showAetherDialog<void>(
    context: context,
    builder: (ctx) => AetherDialog(
      title: '新建歌单',
      content: AetherTextField(
        controller: controller,
        hintText: '歌单名称',
        autofocus: true,
      ),
      actions: [
        AetherButton.ghost(
          label: '取消',
          onPressed: () => Navigator.of(ctx).pop(),
        ),
        AetherButton.primary(
          label: '创建',
          onPressed: () async {
            final name = controller.text.trim();
            if (name.isEmpty) return;
            Navigator.of(ctx).pop();
            try {
              await provider.createPlaylist(name);
            } catch (e) {
              if (!context.mounted) return;
              showAetherToast(
                context,
                message: '创建失败: $e',
                kind: AetherToastKind.error,
              );
            }
          },
        ),
      ],
    ),
  );
}

void mobileShowRenamePlaylistDialog(
  BuildContext context, {
  required String id,
  required String currentName,
  required LibraryProvider provider,
}) {
  final controller = TextEditingController(text: currentName);
  showAetherDialog<void>(
    context: context,
    builder: (ctx) => AetherDialog(
      title: '重命名歌单',
      content: AetherTextField(
        controller: controller,
        hintText: '新歌单名称',
        autofocus: true,
      ),
      actions: [
        AetherButton.ghost(
          label: '取消',
          onPressed: () => Navigator.of(ctx).pop(),
        ),
        AetherButton.primary(
          label: '重命名',
          onPressed: () async {
            final name = controller.text.trim();
            if (name.isEmpty) return;
            Navigator.of(ctx).pop();
            try {
              await provider.renamePlaylist(id, name);
            } catch (e) {
              if (!context.mounted) return;
              showAetherToast(
                context,
                message: '命名失败: $e',
                kind: AetherToastKind.error,
              );
            }
          },
        ),
      ],
    ),
  );
}
