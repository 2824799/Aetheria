import 'dart:io';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/utils/audio_formats.dart';
import 'package:aetheria/core/utils/formatting.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_progress_dialog.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/services/native_audio_helper.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/src/rust/models/song.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

// Actions on the audio versions of a song, shared by the desktop detail pane
// and the mobile detail sheet.

/// The version whose details should be shown for [song]: the one that is
/// playing, otherwise the primary one.
AudioVersion? displayVersionForSong(Song song, AudioPlayerProvider audio) {
  final playingVersion = audio.playingVersion;
  if (audio.playingSong?.id == song.id && playingVersion != null) {
    return playingVersion;
  }
  for (final version in song.versions) {
    if (version.isPrimary) return version;
  }
  return song.versions.isNotEmpty ? song.versions.first : null;
}

/// `FLAC | 320kbps | 44.1kHz | 3:05 | 12.3 MB`
String formatVersionSpecs(AudioVersion version) {
  final sampleRate = version.sampleRate;
  return [
    version.format?.toUpperCase() ?? '未知',
    '${(version.bitrate ?? 0) ~/ 1000}kbps',
    '${sampleRate == null ? '未知' : (sampleRate / 1000).toStringAsFixed(1)}kHz',
    formatDurationSeconds(version.duration),
    formatFileSize(version.fileSize.toInt()),
  ].join(' | ');
}

/// Runs [task] behind a progress dialog. Returns whether it completed; a
/// failure is shown by the dialog itself.
Future<bool> _runWithProgress(
  BuildContext context,
  String title,
  Future<void> Function() task,
) async {
  final completed = await showAetherProgressDialog<bool>(
    context: context,
    title: title,
    task: (_) async {
      await task();
      return true;
    },
  );
  return completed == true;
}

/// Makes [version] the default version of [song]. When the song is playing
/// another version, playback moves to [version] at the current position.
Future<void> makeVersionPrimary(
  BuildContext context,
  Song song,
  AudioVersion version,
) async {
  if (version.isPrimary) return;

  final library = context.read<LibraryProvider>();
  final audio = context.read<AudioPlayerProvider>();
  final followPlayback =
      audio.playingSong?.id == song.id &&
      audio.playingVersion?.id != version.id;
  final position = audio.currentPosition;
  final startPaused = !audio.isPlaying;

  try {
    await library.setPrimaryVersion(version.id);
    if (!followPlayback) return;

    final updatedSong = library.songs.firstWhere(
      (entry) => entry.id == song.id,
      orElse: () => song,
    );
    final updatedVersion = updatedSong.versions.firstWhere(
      (entry) => entry.id == version.id,
      orElse: () => version,
    );
    await audio.switchToVersion(
      updatedSong,
      updatedVersion,
      library.libraryPath,
      startPosition: position,
      startPaused: startPaused,
    );
  } catch (error) {
    if (!context.mounted) return;
    showAetherToast(
      context,
      message: '设置默认版本失败: $error',
      kind: AetherToastKind.error,
    );
  }
}

/// Lets the user pick an audio file and attaches it to [song] as a version.
Future<void> linkNewVersion(BuildContext context, Song song) async {
  final library = context.read<LibraryProvider>();
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedAudioExtensions,
    );
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;

    final linked = await _runWithProgress(
      context,
      '正在关联音源…',
      () => library.importAudioVersionForSong(song.id, path),
    );
    if (!linked || !context.mounted) return;
    showAetherToast(
      context,
      message: '成功关联新音源版本',
      kind: AetherToastKind.success,
    );
  } catch (error) {
    if (!context.mounted) return;
    showAetherToast(
      context,
      message: '关联失败: $error',
      kind: AetherToastKind.error,
    );
  }
}

/// Copies the audio file of [version] out of the library: to the system
/// Downloads folder on Android, to a user-chosen location elsewhere.
Future<void> exportVersion(BuildContext context, AudioVersion version) async {
  try {
    final String successMessage;
    final Future<void> Function() export;
    if (Platform.isAndroid) {
      final libraryPath = context.read<LibraryProvider>().libraryPath;
      final sourcePath = '$libraryPath/${version.filepath}'.replaceAll(
        '\\',
        '/',
      );
      export = () =>
          NativeAudioHelper.saveToDownloads(sourcePath, version.originalName);
      successMessage = '已成功导出至系统 Downloads/Aetheria 文件夹！';
    } else {
      final destination = await FilePicker.platform.saveFile(
        fileName: version.originalName,
        dialogTitle: '选择保存音频的位置',
      );
      if (destination == null) return;
      export = () =>
          music.exportAudioFile(versionId: version.id, destPath: destination);
      successMessage = '音频文件导出还原成功！';
    }
    if (!context.mounted) return;

    final exported = await _runWithProgress(context, '正在导出…', export);
    if (!exported || !context.mounted) return;
    showAetherToast(
      context,
      message: successMessage,
      kind: AetherToastKind.success,
    );
  } catch (error) {
    if (!context.mounted) return;
    showAetherToast(
      context,
      message: '导出失败: $error',
      kind: AetherToastKind.error,
    );
  }
}

/// Asks for confirmation, then deletes [version] and its audio file.
Future<void> deleteVersion(BuildContext context, AudioVersion version) async {
  final library = context.read<LibraryProvider>();
  final confirmed = await showAetherConfirmDialog(
    context: context,
    title: '删除音源版本？',
    message: '确定要删除音源版本“${version.originalName}”吗？这会同时删除对应的本地音频文件。',
    confirmLabel: '删除版本',
    dangerous: true,
  );
  if (!confirmed) return;

  try {
    await library.deleteAudioVersion(version.id);
    if (!context.mounted) return;
    showAetherToast(context, message: '音源版本已删除', kind: AetherToastKind.success);
  } catch (error) {
    if (!context.mounted) return;
    showAetherToast(
      context,
      message: '删除失败: $error',
      kind: AetherToastKind.error,
    );
  }
}
