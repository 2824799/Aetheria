import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_section.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';
import 'package:aetheria/core/widgets/aether_switch.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/library/ui/settings/settings_shared_widgets.dart';
import 'package:aetheria/services/native_audio_helper.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class SettingsDeveloperTab extends StatefulWidget {
  const SettingsDeveloperTab({
    super.key,
    required this.cfg,
    required this.audioProvider,
  });

  final AppThemeConfig cfg;
  final AudioPlayerProvider audioProvider;

  @override
  State<SettingsDeveloperTab> createState() => _SettingsDeveloperTabState();
}

class _SettingsDeveloperTabState extends State<SettingsDeveloperTab> {
  Timer? _refreshTimer;
  Map<String, dynamic> _report = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _refreshReport();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshReport(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refreshReport() {
    if (!widget.audioProvider.developerModeEnabled || !mounted) {
      return;
    }
    try {
      final decoded = jsonDecode(music.getAudioPerformanceReportJson());
      if (decoded is Map) {
        setState(() {
          _report = Map<String, dynamic>.from(decoded);
        });
      }
    } catch (_) {}
  }

  Future<void> _setEnabled(bool value) async {
    await widget.audioProvider.setDeveloperModeEnabled(value);
    if (!mounted) {
      return;
    }
    if (value) {
      _refreshReport();
    } else {
      setState(() {
        _report = const <String, dynamic>{};
      });
    }
  }

  void _resetStats() {
    music.resetAudioPerformanceStats();
    _refreshReport();
    showAetherToast(context, message: '性能统计已清零', kind: AetherToastKind.success);
  }

  Future<void> _copyJson() async {
    final report = music.getAudioPerformanceReportJson();
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) {
      return;
    }
    showAetherToast(
      context,
      message: '详细 JSON 报告已复制',
      kind: AetherToastKind.success,
    );
  }

  Future<void> _exportReport() async {
    final report = music.exportAudioPerformanceReportMarkdown();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '-');
    final fileName = 'aetheria-performance-$stamp.md';
    try {
      if (Platform.isAndroid) {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(
          '${tempDir.path}${Platform.pathSeparator}$fileName',
        );
        await tempFile.writeAsString(report, flush: true);
        await NativeAudioHelper.saveToDownloads(tempFile.path, fileName);
      } else {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: '导出 Aetheria 性能报告',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const <String>['md'],
        );
        if (path == null) {
          return;
        }
        await File(path).writeAsString(report, flush: true);
      }
      if (!mounted) {
        return;
      }
      showAetherToast(
        context,
        message: Platform.isAndroid ? '性能报告已保存到下载目录' : '性能报告已导出',
        kind: AetherToastKind.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAetherToast(
        context,
        message: '导出失败: $error',
        kind: AetherToastKind.error,
      );
    }
  }

  List<Map<String, dynamic>> get _metrics {
    final raw = _report['metrics'];
    if (raw is! List) {
      return const <Map<String, dynamic>>[];
    }
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  String _fixed(Object? value, [int digits = 3]) {
    return value is num ? value.toDouble().toStringAsFixed(digits) : '0.000';
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    final enabled = widget.audioProvider.developerModeEnabled;
    final metrics = _metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AetherSectionHeader(title: '开发者模式'),
        AetherSwitchTile(
          title: enabled ? '性能统计已启用' : '启用性能统计',
          subtitle: '按音频块记录热点函数调用次数、总耗时、平均耗时和单次最大耗时。统计本身只在开启时产生开销。',
          value: enabled,
          onChanged: _setEnabled,
        ),
        const AetherDivider(),
        if (!enabled)
          AetherSurface(
            level: AetherSurfaceLevel.flat,
            color: cfg.bgHover,
            padding: const EdgeInsets.all(AetherSpace.lg),
            child: Text(
              '开启后开始新的统计会话。建议先清零，再复现 CPU 占用偏高的歌曲和播放设置，然后导出报告。',
              style: AetherType.bodySmStyle(
                cfg.textSecondary,
              ).copyWith(height: 1.5),
            ),
          )
        else ...[
          Wrap(
            spacing: AetherSpace.md,
            runSpacing: AetherSpace.md,
            children: [
              AetherButton.secondary(
                label: '清零统计',
                icon: Icons.restart_alt_rounded,
                size: AetherButtonSize.sm,
                onPressed: _resetStats,
              ),
              AetherButton.secondary(
                label: '复制 JSON',
                icon: Icons.copy_all_rounded,
                size: AetherButtonSize.sm,
                onPressed: _copyJson,
              ),
              AetherButton.primary(
                label: '导出详细报告',
                icon: Icons.download_rounded,
                size: AetherButtonSize.sm,
                onPressed: _exportReport,
              ),
            ],
          ),
          const SizedBox(height: AetherSpace.lg),
          Text(
            _report['note']?.toString() ?? '正在收集性能数据…',
            style: AetherType.captionStyle(
              cfg.textSecondary,
            ).copyWith(height: 1.5),
          ),
          const SizedBox(height: AetherSpace.md),
          if (metrics.isEmpty)
            AetherSurface(
              level: AetherSurfaceLevel.flat,
              color: cfg.bgHover,
              padding: const EdgeInsets.all(AetherSpace.xl),
              child: Text(
                '尚无热点数据。开始播放歌曲后会自动更新。',
                style: AetherType.bodySmStyle(cfg.textSecondary),
              ),
            )
          else
            for (final metric in metrics) ...[
              AetherSurface(
                level: AetherSurfaceLevel.flat,
                color: cfg.bgHover,
                borderRadius: BorderRadius.circular(AetherRadius.sm + 2),
                padding: const EdgeInsets.all(AetherSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric['label']?.toString() ?? '未知热点',
                      style: AetherType.labelStyle(cfg.textPrimary),
                    ),
                    const SizedBox(height: AetherSpace.sm),
                    Wrap(
                      spacing: AetherSpace.md,
                      runSpacing: AetherSpace.sm,
                      children: [
                        SettingsInfoPill(
                          cfg: cfg,
                          label: '调用',
                          value: '${metric['calls'] ?? 0} 次',
                        ),
                        SettingsInfoPill(
                          cfg: cfg,
                          label: '总耗时',
                          value: '${_fixed(metric['totalMs'])} ms',
                        ),
                        SettingsInfoPill(
                          cfg: cfg,
                          label: '平均',
                          value: '${_fixed(metric['averageUs'])} μs',
                        ),
                        SettingsInfoPill(
                          cfg: cfg,
                          label: '最大',
                          value: '${_fixed(metric['maxUs'])} μs',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AetherSpace.md),
            ],
        ],
      ],
    );
  }
}
