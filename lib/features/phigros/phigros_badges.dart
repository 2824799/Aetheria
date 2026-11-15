import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/src/rust/models/song.dart';

Color phigrosDifficultyColor(String difficulty, AppThemeConfig cfg) {
  final base = difficulty.replaceAll('_Error', '');
  switch (base) {
    case 'EZ':
      return cfg.success;
    case 'HD':
      return cfg.info;
    case 'IN':
      return cfg.danger;
    case 'AT':
      return cfg.textPrimary;
    default:
      return cfg.warning;
  }
}

String formatPhigrosRating(double rating) {
  if (rating <= 0) return '—';
  final rounded = rating.toStringAsFixed(1);
  return rounded.endsWith('.0') ? rounded.substring(0, rounded.length - 2) : rounded;
}

String formatPhigrosBpm(double minBpm, double maxBpm) {
  String fmt(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
  if ((maxBpm - minBpm).abs() < 0.05) {
    return fmt(minBpm);
  }
  return '${fmt(minBpm)}–${fmt(maxBpm)}';
}

String formatPhigrosDiffBadgeLabel(PhigrosChartMeta chart) {
  final diffLabel = chart.difficulty.replaceAll('_Error', '·Err');
  return chart.rating > 0
      ? '$diffLabel ${formatPhigrosRating(chart.rating)}'
      : diffLabel;
}

/// Compact pill showing the selected Phigros difficulty & rating on song rows.
class PhigrosDifficultyBadge extends StatelessWidget {
  const PhigrosDifficultyBadge({
    super.key,
    required this.phigros,
    this.onTap,
    this.tooltip,
  });

  final PhigrosSongMeta phigros;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final chart = AudioPlayerProvider.activePhigrosChartFor(phigros);
    if (chart == null) return const SizedBox.shrink();

    final cfg = context.tokens;
    final color = phigrosDifficultyColor(chart.difficulty, cfg);
    final label = formatPhigrosDiffBadgeLabel(chart);
    final radius = BorderRadius.circular(AetherRadius.sm);

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: radius,
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Text(
        label,
        style: AetherType.captionStyle(color).copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          height: 1.15,
        ),
      ),
    );

    if (onTap == null) return badge;
    return AetherPressable(
      onTap: onTap,
      borderRadius: radius,
      pressScale: AetherMotion.pressScaleSubtle,
      tooltip: tooltip ?? '查看或切换谱面难度',
      child: badge,
    );
  }
}

/// Updates selected difficulty in SQLite + updates playing engine live if needed.
Future<void> changePhigrosDifficultyAndSync(
  BuildContext context,
  LibraryProvider library,
  Song song,
  String difficulty,
) async {
  final audio = context.read<AudioPlayerProvider>();
  final updated = await library.setPhigrosDifficulty(song.id, difficulty);
  if (updated != null) {
    audio.syncSongSnapshot(updated);
  }
}

/// Updates per-song hitsound overrides in SQLite + pushes live to playing engine.
Future<void> updatePhigrosSongHitsoundAndSync(
  BuildContext context,
  LibraryProvider library,
  Song song, {
  required String mode,
  double? volume,
  int? offsetMs,
}) async {
  final audio = context.read<AudioPlayerProvider>();
  final updated = await library.setPhigrosSongHitsound(
    song.id,
    mode: mode,
    volume: volume,
    offsetMs: offsetMs,
  );
  if (updated != null) {
    audio.syncSongSnapshot(updated);
  }
}

/// Dialog for importing or refreshing an extracted Phigros asset package.
Future<void> showPhigrosImportDialog(
  BuildContext context,
  LibraryProvider library,
) async {
  await showAetherDialog<void>(
    context: context,
    builder: (_) => _PhigrosImportDialog(library: library),
  );
}

class _PhigrosImportDialog extends StatefulWidget {
  const _PhigrosImportDialog({required this.library});

  final LibraryProvider library;

  @override
  State<_PhigrosImportDialog> createState() => _PhigrosImportDialogState();
}

class _PhigrosImportDialogState extends State<_PhigrosImportDialog> {
  static const String _defaultStagingPath = '/tmp/phigros_extracted';

  late final TextEditingController _dirController;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final hasDefault = File('$_defaultStagingPath/phigros_manifest.json').existsSync();
    _dirController = TextEditingController(
      text: hasDefault ? _defaultStagingPath : '',
    );
  }

  @override
  void dispose() {
    _dirController.dispose();
    super.dispose();
  }

  Future<void> _browseDir() async {
    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择 Phigros 解包资源目录（含 phigros_manifest.json）',
    );
    if (picked != null && picked.isNotEmpty) {
      setState(() {
        _dirController.text = picked;
        _error = null;
      });
    }
  }

  Future<void> _runImport() async {
    final dir = _dirController.text.trim();
    if (dir.isEmpty) {
      setState(() => _error = '请选择或填写 Phigros 资源目录路径。');
      return;
    }
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final res = await widget.library.importPhigrosPackage(dir);
      if (!mounted) return;
      Navigator.of(context).pop();
      showAetherToast(
        context,
        message:
            'Phigros 专区已就绪：新增 ${res.importedCount} 首、更新 ${res.updatedCount} 首（共 ${res.chartCount} 份谱面）',
        kind: AetherToastKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = '导入失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return AetherDialog(
      title: '导入 / 更新 Phigros 专区',
      maxWidth: 480,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '选择包含 phigros_manifest.json、曲目音频、曲绘与全难度谱面文件的目录（可通过 scripts/extract_phigros.py 从已连接平板或 APK/OBB 生成）。',
            style: AetherType.bodySmStyle(cfg.textSecondary).copyWith(height: 1.5),
          ),
          const SizedBox(height: AetherSpace.lg),
          Row(
            children: [
              Expanded(
                child: AetherTextField(
                  controller: _dirController,
                  enabled: !_importing,
                  hintText: '/path/to/phigros_extracted',
                ),
              ),
              const SizedBox(width: AetherSpace.sm),
              AetherButton.secondary(
                label: '浏览…',
                onPressed: _importing ? null : _browseDir,
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AetherSpace.md),
            Text(
              _error!,
              style: AetherType.captionStyle(cfg.danger),
            ),
          ],
          if (_importing) ...[
            const SizedBox(height: AetherSpace.lg),
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cfg.accent,
                  ),
                ),
                const SizedBox(width: AetherSpace.md),
                Expanded(
                  child: Text(
                    '正在校验并导入歌曲、全难度谱面与打击音效…',
                    style: AetherType.bodySmStyle(cfg.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        AetherButton.ghost(
          label: '取消',
          onPressed: _importing ? null : () => Navigator.of(context).pop(),
        ),
        AetherButton.primary(
          label: _importing ? '导入中…' : '开始导入',
          loading: _importing,
          onPressed: _importing ? null : _runImport,
        ),
      ],
    );
  }
}
