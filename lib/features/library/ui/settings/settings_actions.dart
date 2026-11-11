import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/sync_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';

const int _minBufferMs = 60;
const int _maxBufferMs = 1500;

/// Replaces this device's library with [device]'s after two confirmations.
Future<void> confirmPullFromDevice(
  BuildContext context,
  SyncDevice device, {
  required LibraryProvider library,
  required AudioPlayerProvider audio,
  required SyncProvider sync,
}) async {
  final proceed = await showAetherConfirmDialog(
    context: context,
    title: '从远端同步到本机？',
    message:
        '${device.name} 的音乐库将同步到本机。本机曲库与 files 会以对方为准；'
        '主题、悬浮歌词、音频处理等本机设置不会被覆盖。',
    confirmLabel: '继续',
    doubleConfirm: true,
    doubleConfirmTitle: '再次确认覆盖本机',
    doubleConfirmMessage:
        '本机多余的歌曲、歌词、数据库记录和 files 文件会被删除。'
        '同步前会备份当前库，但这仍然是一次覆盖操作；本机设置会保留。',
    doubleConfirmLabel: '确认覆盖',
  );
  if (!proceed) return;

  try {
    await sync.pullFromDevice(
      device: device,
      libraryProvider: library,
      audioProvider: audio,
    );
    if (!context.mounted) return;
    showAetherToast(
      context,
      message: '已从 ${device.name} 同步到本机',
      kind: AetherToastKind.success,
    );
  } catch (e) {
    if (!context.mounted) return;
    showAetherToast(
      context,
      message: '同步失败: $e',
      kind: AetherToastKind.error,
    );
  }
}

/// Asks for a processing buffer length and applies it.
Future<void> showCustomBufferDialog(
  BuildContext context,
  AudioPlayerProvider audio,
) async {
  final controller = TextEditingController(text: audio.pitchBufferMs.toString());
  final result = await showAetherDialog<int>(
    context: context,
    builder: (ctx) {
      void submit() {
        final value = int.tryParse(controller.text.trim());
        if (value != null) {
          Navigator.of(ctx).pop(value);
        }
      }

      return AetherDialog(
        title: '自定义处理缓冲',
        content: AetherTextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          label: '缓冲长度 (ms)',
          hintText: '可输入 $_minBufferMs 到 $_maxBufferMs 毫秒',
          onSubmitted: (_) => submit(),
        ),
        actions: [
          AetherButton.ghost(
            label: '取消',
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          AetherButton.primary(label: '应用', onPressed: submit),
        ],
      );
    },
  );
  controller.dispose();
  if (result == null) return;
  await audio.setPitchBufferMs(result.clamp(_minBufferMs, _maxBufferMs));
}

/// Points the app at another managed library folder.
Future<void> changeLibraryPath(
  BuildContext context,
  LibraryProvider library,
) async {
  try {
    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择新的托管音乐库路径',
    );
    if (directory == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aetheria-library-path', directory);
    await library.initializeLibrary(directory);
    if (!context.mounted) return;
    showAetherToast(
      context,
      message: '托管路径已更新: $directory',
      kind: AetherToastKind.success,
    );
  } catch (e) {
    if (!context.mounted) return;
    showAetherToast(
      context,
      message: '更改路径失败: $e',
      kind: AetherToastKind.error,
    );
  }
}
