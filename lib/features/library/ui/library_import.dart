import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/utils/audio_formats.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_checkbox.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_progress_dialog.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/src/rust/models/song.dart' show PreviewInfo;

/// Lets the user pick audio files and imports them.
Future<void> importAudioFiles(
  BuildContext context,
  LibraryProvider library,
) async {
  final List<String> paths;
  try {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedAudioExtensions,
      allowMultiple: true,
    );
    paths = picked?.paths.whereType<String>().toList() ?? const [];
  } catch (e) {
    if (context.mounted) _toastError(context, '无法打开文件选择器: $e');
    return;
  }
  if (paths.isEmpty || !context.mounted) return;

  await _importWithProgress(context, library, [
    for (final path in paths) (filepath: path, title: null, artist: null),
  ]);
}

/// Lets the user pick a folder, review what was found in it, and import the
/// checked songs.
Future<void> importAudioFolder(
  BuildContext context,
  LibraryProvider library,
) async {
  final String? directory;
  try {
    directory = await FilePicker.platform.getDirectoryPath();
  } catch (e) {
    if (context.mounted) _toastError(context, '无法打开文件夹选择器: $e');
    return;
  }
  if (directory == null || directory.isEmpty || !context.mounted) return;

  final found = await showAetherProgressDialog<List<PreviewInfo>>(
    context: context,
    title: '正在扫描文件夹…',
    task: (report) => _scan(directory!, report),
  );
  // Null means the scan failed; the progress dialog already showed why.
  if (found == null || !context.mounted) return;
  if (found.isEmpty) {
    showAetherToast(
      context,
      message: '所选文件夹中没有支持的音频文件',
      kind: AetherToastKind.info,
    );
    return;
  }

  final chosen = await showAetherDialog<List<PreviewInfo>>(
    context: context,
    builder: (_) => _ImportPreviewDialog(previews: found),
  );
  if (chosen == null || chosen.isEmpty || !context.mounted) return;

  await _importWithProgress(context, library, [
    for (final item in chosen)
      (filepath: item.filepath, title: item.title, artist: item.artist),
  ]);
}

Future<List<PreviewInfo>> _scan(
  String directory,
  void Function(AetherProgressUpdate) report,
) async {
  final files = await music.scanDirectoryForPreview(dirPath: directory);
  final previews = <PreviewInfo>[];
  // Tags are read in batches so the dialog can show progress on big folders.
  const batchSize = 24;
  for (var start = 0; start < files.length; start += batchSize) {
    report(
      AetherProgressUpdate(
        title: '正在读取音频信息…',
        detail: '$start / ${files.length}',
        value: start / files.length,
      ),
    );
    final end = math.min(start + batchSize, files.length);
    previews.addAll(
      await music.previewAudioMetadata(filepaths: files.sublist(start, end)),
    );
  }
  return previews;
}

Future<void> _importWithProgress(
  BuildContext context,
  LibraryProvider library,
  List<SongImportRequest> requests,
) async {
  final total = requests.length;
  final failures = await showAetherProgressDialog<List<String>>(
    context: context,
    title: '正在导入…',
    task: (report) => library.importSongs(
      requests,
      onProgress: (done) => report(
        AetherProgressUpdate(
          title: '正在导入…',
          detail: '$done / $total',
          value: done / total,
        ),
      ),
    ),
  );
  if (failures == null || !context.mounted) return;

  final imported = total - failures.length;
  if (failures.isEmpty) {
    showAetherToast(
      context,
      message: '已导入 $imported 首歌曲',
      kind: AetherToastKind.success,
    );
    return;
  }
  // Show one reason: usually every failure in a batch shares it.
  showAetherToast(
    context,
    message: '导入 $imported 首，失败 ${failures.length} 首：${failures.first}',
    kind: imported == 0 ? AetherToastKind.error : AetherToastKind.warning,
  );
}

void _toastError(BuildContext context, String message) {
  showAetherToast(context, message: message, kind: AetherToastKind.error);
}

/// Lists the songs found in a folder; pops with the ones left checked.
class _ImportPreviewDialog extends StatefulWidget {
  const _ImportPreviewDialog({required this.previews});

  final List<PreviewInfo> previews;

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  late final List<bool> _checked = List<bool>.filled(
    widget.previews.length,
    true,
  );

  int get _checkedCount => _checked.where((checked) => checked).length;

  void _setAll(bool value) {
    setState(() => _checked.fillRange(0, _checked.length, value));
  }

  void _confirm() {
    Navigator.of(context).pop([
      for (var i = 0; i < _checked.length; i++)
        if (_checked[i]) widget.previews[i],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final count = _checkedCount;
    final allChecked = count == _checked.length;

    return AetherDialog(
      title: '导入文件夹',
      maxWidth: 580,
      showClose: true,
      content: SizedBox(
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '已选 $count / ${_checked.length} 首',
                  style: AetherType.bodySmStyle(cfg.textSecondary),
                ),
                const Spacer(),
                AetherButton.ghost(
                  label: allChecked ? '全不选' : '全选',
                  size: AetherButtonSize.sm,
                  onPressed: () => _setAll(!allChecked),
                ),
              ],
            ),
            const SizedBox(height: AetherSpace.md),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AetherRadius.md),
                  border: Border.all(color: cfg.borderSubtle),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AetherRadius.md),
                  child: ListView.builder(
                    itemCount: widget.previews.length,
                    itemExtent: 52,
                    itemBuilder: (context, index) => _PreviewRow(
                      item: widget.previews[index],
                      checked: _checked[index],
                      onChanged: (value) =>
                          setState(() => _checked[index] = value),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        AetherButton.ghost(
          label: '取消',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AetherButton.primary(
          label: count == 0 ? '导入' : '导入 $count 首',
          onPressed: count == 0 ? null : _confirm,
        ),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.item,
    required this.checked,
    required this.onChanged,
  });

  final PreviewInfo item;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return AetherPressable(
      onTap: () => onChanged(!checked),
      pressScale: 1.0,
      hoverColor: cfg.bgHover,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: cfg.divider)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AetherSpace.lg),
          child: Row(
            children: [
              AetherCheckbox(
                value: checked,
                onChanged: (value) => onChanged(value ?? false),
              ),
              const SizedBox(width: AetherSpace.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AetherType.bodyStyle(
                        cfg.textPrimary,
                      ).copyWith(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '${item.artist} · ${item.filename}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AetherType.captionStyle(cfg.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
