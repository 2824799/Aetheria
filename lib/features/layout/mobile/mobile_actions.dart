import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/widgets/aether_progress_dialog.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';
import 'package:aetheria/services/native_audio_helper.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/src/rust/models/song.dart';

Future<void> mobileLinkNewVersion(
  BuildContext context,
  Song song,
  LibraryProvider provider,
) async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'flac', 'm4a', 'ogg', 'aac'],
    );

    if (result == null || result.files.single.path == null) return;
    final filePath = result.files.single.path!;
    if (!context.mounted) return;

    await showAetherProgressDialog<void>(
      context: context,
      title: '正在关联音源…',
      task: (_) async {
        await provider.importAudioVersionForSong(song.id, filePath);
      },
    );

    if (!context.mounted) return;
    showAetherToast(
      context,
      message: '成功关联新音源版本',
      kind: AetherToastKind.success,
    );
  } catch (e) {
    if (!context.mounted) return;
    showAetherToast(
      context,
      message: '关联失败: $e',
      kind: AetherToastKind.error,
    );
  }
}

Future<void> mobileExportVersion(
  BuildContext context,
  AudioVersion version,
) async {
  try {
    if (Platform.isAndroid) {
      final libraryPath = context.read<LibraryProvider>().libraryPath;
      final srcPath = '$libraryPath/${version.filepath}'.replaceAll('\\', '/');

      await showAetherProgressDialog<void>(
        context: context,
        title: '正在导出…',
        task: (_) async {
          await NativeAudioHelper.saveToDownloads(
            srcPath,
            version.originalName,
          );
        },
      );

      if (!context.mounted) return;
      showAetherToast(
        context,
        message: '已成功导出至系统 Downloads/Aetheria 文件夹！',
        kind: AetherToastKind.success,
      );
    } else {
      final destPath = await FilePicker.platform.saveFile(
        fileName: version.originalName,
        dialogTitle: '选择保存音频的位置',
      );

      if (destPath == null) return;
      if (!context.mounted) return;

      await showAetherProgressDialog<void>(
        context: context,
        title: '正在导出…',
        task: (_) async {
          await music.exportAudioFile(
            versionId: version.id,
            destPath: destPath,
          );
        },
      );

      if (!context.mounted) return;
      showAetherToast(
        context,
        message: '音频文件导出还原成功！',
        kind: AetherToastKind.success,
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    showAetherToast(
      context,
      message: '导出失败: $e',
      kind: AetherToastKind.error,
    );
  }
}

Future<void> mobileShowPlayErrorDialog(BuildContext context, Object error) {
  return showAetherDialog<void>(
    context: context,
    builder: (ctx) => AetherDialog(
      title: '播放失败 - 诊断报告',
      content: SelectableText(
        error.toString(),
        style: AetherType.captionStyle(ctx.tokens.textSecondary).copyWith(
          fontFamily: 'monospace',
        ),
      ),
      actions: [
        AetherButton.primary(
          label: '关闭',
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    ),
  );
}
