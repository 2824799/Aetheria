import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/theme/theme.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_progress.dart';
import 'package:aetheria/core/widgets/aether_section.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';

class SettingsLibraryTab extends StatelessWidget {
  const SettingsLibraryTab({
    super.key,
    required this.cfg,
    required this.libraryProvider,
    required this.isDesktop,
    required this.settingsImporting,
    required this.onChangeLibraryPath,
    required this.onImportFiles,
    required this.onImportFolder,
  });

  final AppThemeConfig cfg;
  final LibraryProvider libraryProvider;
  final bool isDesktop;
  final bool settingsImporting;
  final VoidCallback onChangeLibraryPath;
  final VoidCallback onImportFiles;
  final VoidCallback onImportFolder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AetherSectionHeader(title: '本地音乐数据库'),
        Text('当前托管路径：', style: AetherType.bodySmStyle(cfg.textSecondary)),
        const SizedBox(height: AetherSpace.sm),
        AetherSurface(
          level: AetherSurfaceLevel.flat,
          color: cfg.bgHover,
          borderRadius: BorderRadius.circular(AetherRadius.sm + 2),
          padding: const EdgeInsets.all(AetherSpace.lg),
          child: SelectableText(
            libraryProvider.libraryPath,
            style: AetherType.bodySmStyle(cfg.textPrimary).copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(height: AetherSpace.xl),
        if (isDesktop) ...[
          AetherButton.secondary(
            label: '选择新托管路径',
            icon: Icons.drive_file_rename_outline,
            size: AetherButtonSize.sm,
            onPressed: onChangeLibraryPath,
          ),
          const SizedBox(height: AetherSpace.lg - 2),
          Text(
            '* 更改路径后，请确保新路径下已有或准备导入 music.db 与 files 目录。',
            style: AetherType.captionStyle(cfg.textSecondary).copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ] else ...[
          Text(
            '* 移动端系统路径由应用安全托管，无需且不支持自定义修改。',
            style: AetherType.bodySmStyle(cfg.textSecondary).copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: AetherSpace.lg),
          Wrap(
            spacing: AetherSpace.lg - 2,
            runSpacing: AetherSpace.lg - 2,
            children: [
              AetherButton.primary(
                label: '导入音频',
                icon: Icons.audio_file,
                size: AetherButtonSize.sm,
                loading: settingsImporting,
                onPressed: settingsImporting ? null : onImportFiles,
              ),
              AetherButton.secondary(
                label: '导入目录',
                icon: Icons.folder_open,
                size: AetherButtonSize.sm,
                onPressed: settingsImporting ? null : onImportFolder,
              ),
            ],
          ),
        ],
        const AetherDivider(),
        const AetherSectionHeader(title: '数据维护与重构'),
        Wrap(
          spacing: AetherSpace.lg - 2,
          runSpacing: AetherSpace.lg - 2,
          children: [
            AetherButton.primary(
              label: libraryProvider.isRefreshingDatabase
                  ? '正在刷新中...'
                  : '刷新扫描全部歌曲',
              icon: Icons.refresh,
              size: AetherButtonSize.sm,
              loading: libraryProvider.isRefreshingDatabase,
              onPressed: libraryProvider.isRefreshingDatabase
                  ? null
                  : () async {
                      await libraryProvider.refreshDatabase();
                      if (!context.mounted) {
                        return;
                      }
                      showAetherToast(
                        context,
                        message: '歌曲数据已全部刷新完成！',
                        kind: AetherToastKind.success,
                      );
                    },
            ),
            AetherButton.secondary(
              label: libraryProvider.isRefreshingDatabase
                  ? '正在扫描...'
                  : '仅扫描新增文件',
              icon: Icons.library_add_check_outlined,
              size: AetherButtonSize.sm,
              onPressed: libraryProvider.isRefreshingDatabase
                  ? null
                  : () async {
                      await libraryProvider.refreshDatabase(
                        onlyUnscanned: true,
                      );
                      if (!context.mounted) {
                        return;
                      }
                      showAetherToast(
                        context,
                        message: '新增歌曲扫描已完成！',
                        kind: AetherToastKind.success,
                      );
                    },
            ),
          ],
        ),
        if (libraryProvider.isRefreshingDatabase) ...[
          const SizedBox(height: AetherSpace.lg),
          AetherProgress.linear(
            size: 6,
            value: libraryProvider.refreshProgressTotal > 0
                ? libraryProvider.refreshProgressCurrent /
                    libraryProvider.refreshProgressTotal
                : null,
            trackColor: cfg.borderSubtle.withValues(alpha: 0.45),
          ),
          const SizedBox(height: AetherSpace.md),
          Text(
            libraryProvider.refreshProgressTotal > 0
                ? '已完成 ${libraryProvider.refreshProgressCurrent} / ${libraryProvider.refreshProgressTotal} 首歌曲'
                : '正在准备刷新任务...',
            style: AetherType.captionStyle(cfg.textPrimary).copyWith(
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AetherSpace.xs),
          Text(
            libraryProvider.refreshProgressLabel.isNotEmpty
                ? libraryProvider.refreshProgressLabel
                : '正在深度重扫音频属性与响度信息，旧库里解析失败的 M4A 时长也会在这一轮里重新校正。',
            style: AetherType.captionStyle(cfg.textSecondary).copyWith(height: 1.5),
          ),
        ],
        const SizedBox(height: AetherSpace.md),
        Text(
          '* 全量扫描会重新处理所有音频；新增扫描只处理尚未完整扫描的版本。完整扫描会写入标记，后续新增扫描会自动跳过它们。',
          style: AetherType.captionStyle(cfg.textSecondary).copyWith(height: 1.5),
        ),
      ],
    );
  }
}
