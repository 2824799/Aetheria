import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_menu.dart';
import 'package:aetheria/core/widgets/aether_checkbox.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/library/ui/tag_filter.dart';
import 'package:aetheria/features/library/ui/song_table.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/src/rust/models/song.dart' show PreviewInfo;
import 'package:aetheria/core/widgets/aether_progress.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';

typedef ProgressDialogUpdate =
    void Function({
      String? title,
      String? subtitle,
      int? current,
      int? total,
      bool? indeterminate,
    });

class MainContent extends StatefulWidget {
  const MainContent({super.key});

  @override
  State<MainContent> createState() => _MainContentState();
}

class _MainContentState extends State<MainContent> {
  final TextEditingController _searchController = TextEditingController();
  double _tagCollapseFactor = 0;

  Future<T?> _runProgressDialog<T>({
    required String initialTitle,
    required String initialSubtitle,
    required Future<T> Function(ProgressDialogUpdate updateProgress) task,
  }) async {
    if (!mounted) return null;

    var progressDialogOpen = false;
    var progressTitle = initialTitle;
    var progressSubtitle = initialSubtitle;
    var progressCurrent = 0;
    var progressTotal = 0;
    var progressIndeterminate = true;
    void Function(void Function())? setDialogState;

    showAetherDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, updateDialogState) {
            setDialogState = updateDialogState;
            progressDialogOpen = true;
            final cfg = dialogContext.tokens;
            final progressValue = progressIndeterminate || progressTotal <= 0
                ? null
                : (progressCurrent / progressTotal).clamp(0.0, 1.0);

            return AetherDialog(
              title: progressTitle,
              maxWidth: 380,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    progressSubtitle,
                    style: AetherType.bodySmStyle(cfg.textSecondary),
                  ),
                  const SizedBox(height: AetherSpace.xl),
                  AetherProgress.linear(
                    size: 6,
                    value: progressValue,
                    trackColor: cfg.sliderTrack,
                  ),
                  if (progressTotal > 0) ...[
                    const SizedBox(height: AetherSpace.md),
                    Text(
                      '已完成 $progressCurrent / $progressTotal 项',
                      style: AetherType.captionStyle(cfg.textPrimary).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
    await Future<void>.delayed(Duration.zero);

    void updateProgress({
      String? title,
      String? subtitle,
      int? current,
      int? total,
      bool? indeterminate,
    }) {
      setDialogState?.call(() {
        if (title != null) progressTitle = title;
        if (subtitle != null) progressSubtitle = subtitle;
        if (current != null) progressCurrent = current;
        if (total != null) progressTotal = total;
        if (indeterminate != null) progressIndeterminate = indeterminate;
      });
    }

    try {
      return await task(updateProgress);
    } finally {
      if (mounted && progressDialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _importFiles(LibraryProvider provider) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'flac', 'm4a', 'ogg', 'aac'],
        allowMultiple: true,
      );

      final selectedPaths =
          result?.paths.whereType<String>().toList() ?? const [];
      if (selectedPaths.isEmpty) return;

      int successCount = 0;
      int failCount = 0;

      await _runProgressDialog<void>(
        initialTitle: '正在导入音频文件...',
        initialSubtitle: '已完成 0 / ${selectedPaths.length} 首歌曲',
        task: (updateProgress) async {
          updateProgress(
            current: 0,
            total: selectedPaths.length,
            indeterminate: false,
          );
          for (int index = 0; index < selectedPaths.length; index++) {
            updateProgress(
              subtitle: '正在导入 ${index + 1} / ${selectedPaths.length} 首歌曲',
              current: index,
            );
            try {
              await provider.importSong(selectedPaths[index]);
              successCount++;
            } catch (_) {
              failCount++;
            }
            updateProgress(
              subtitle: '已完成 ${index + 1} / ${selectedPaths.length} 首歌曲',
              current: index + 1,
            );
          }
        },
      );

      if (!mounted) return;
      showAetherToast(
        context,
        message: '导入完成: 成功 $successCount 首, 失败 $failCount 首',
        kind: failCount > 0 ? AetherToastKind.warning : AetherToastKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAetherToast(
        context,
        message: '导入文件错误: $e',
        kind: AetherToastKind.error,
      );
    }
  }

  Future<void> _importFolder(LibraryProvider provider) async {
    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory == null) return;

      final previews = await _runProgressDialog<List<PreviewInfo>>(
        initialTitle: '正在扫描文件夹...',
        initialSubtitle: '扫描完成后会继续读取音频元数据。',
        task: (updateProgress) async {
          final filepaths = await music.scanDirectoryForPreview(
            dirPath: selectedDirectory,
          );
          if (filepaths.isEmpty) {
            return const <PreviewInfo>[];
          }

          updateProgress(
            title: '正在读取音频元数据...',
            subtitle: '已处理 0 / ${filepaths.length} 首候选歌曲',
            current: 0,
            total: filepaths.length,
            indeterminate: false,
          );

          final previews = <PreviewInfo>[];
          const batchSize = 24;
          for (int start = 0; start < filepaths.length; start += batchSize) {
            final end = math.min(start + batchSize, filepaths.length);
            final batch = await music.previewAudioMetadata(
              filepaths: filepaths.sublist(start, end),
            );
            previews.addAll(batch);
            updateProgress(
              subtitle: '已处理 $end / ${filepaths.length} 首候选歌曲',
              current: end,
            );
          }

          return previews;
        },
      );

      if (!mounted) return;
      if (previews == null || previews.isEmpty) {
        showAetherToast(
          context,
          message: '所选文件夹中未找到支持的音频文件',
          kind: AetherToastKind.info,
        );
        return;
      }

      await _showImportPreviewModal(previews, provider);
    } catch (e) {
      if (!mounted) return;
      showAetherToast(
        context,
        message: '扫描文件夹错误: $e',
        kind: AetherToastKind.error,
      );
    }
  }

  Future<void> _showImportPreviewModal(
    List<PreviewInfo> previews,
    LibraryProvider provider,
  ) async {
    final checkedItems = List<bool>.filled(previews.length, true);

    final shouldImport = await showAetherDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final cfg = context.tokens;
            final selectedCount =
                checkedItems.where((checked) => checked).length;

            return AetherDialog(
              title: '导入预览 (共 ${previews.length} 首)',
              maxWidth: 580,
              showClose: true,
              contentPadding: const EdgeInsets.fromLTRB(AetherSpace.xxl, AetherSpace.xs, AetherSpace.xxl, AetherSpace.lg),
              content: SizedBox(
                height: 360,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        AetherButton.ghost(
                          label: '全选',
                          size: AetherButtonSize.sm,
                          onPressed: () {
                            setModalState(() {
                              checkedItems.fillRange(
                                0,
                                checkedItems.length,
                                true,
                              );
                            });
                          },
                        ),
                        const SizedBox(width: AetherSpace.sm),
                        AetherButton.ghost(
                          label: '全不选',
                          size: AetherButtonSize.sm,
                          onPressed: () {
                            setModalState(() {
                              checkedItems.fillRange(
                                0,
                                checkedItems.length,
                                false,
                              );
                            });
                          },
                        ),
                        const Spacer(),
                        Text(
                          '已选 $selectedCount 首',
                          style: AetherType.captionStyle(cfg.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AetherSpace.md),
                    Expanded(
                      child: AetherSurface(
                        level: AetherSurfaceLevel.panel,
                        borderRadius: BorderRadius.circular(AetherRadius.md),
                        color: cfg.bgHover,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: AetherSpace.xs),
                          itemCount: previews.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: cfg.borderSubtle,
                          ),
                          itemBuilder: (context, index) {
                            final item = previews[index];
                            return AetherPressable(
                              onTap: () {
                                setModalState(() {
                                  checkedItems[index] = !checkedItems[index];
                                });
                              },
                              pressScale: 1.0,
                              hoverColor: cfg.bgHover,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AetherSpace.md,
                                  vertical: AetherSpace.sm,
                                ),
                                child: Row(
                                  children: [
                                    AetherCheckbox(
                                      value: checkedItems[index],
                                      onChanged: (val) {
                                        setModalState(() {
                                          checkedItems[index] = val ?? false;
                                        });
                                      },
                                    ),
                                    const SizedBox(width: AetherSpace.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.title,
                                            style: AetherType.bodyStyle(
                                              cfg.textPrimary,
                                            ).copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '${item.artist} - ${item.filename}',
                                            style: AetherType.captionStyle(
                                              cfg.textSecondary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                AetherButton.ghost(
                  label: '取消',
                  onPressed: () => Navigator.of(ctx).pop(false),
                ),
                AetherButton.primary(
                  label: '开始导入',
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldImport != true) return;

    final selectedPreviews = <PreviewInfo>[];
    for (int index = 0; index < previews.length; index++) {
      if (checkedItems[index]) {
        selectedPreviews.add(previews[index]);
      }
    }

    if (selectedPreviews.isEmpty) {
      if (!mounted) return;
      showAetherToast(
        context,
        message: '请至少选择一首歌曲再导入',
        kind: AetherToastKind.warning,
      );
      return;
    }

    int imported = 0;
    await _runProgressDialog<void>(
      initialTitle: '正在导入已选歌曲...',
      initialSubtitle: '已完成 0 / ${selectedPreviews.length} 首歌曲',
      task: (updateProgress) async {
        updateProgress(
          current: 0,
          total: selectedPreviews.length,
          indeterminate: false,
        );
        for (int index = 0; index < selectedPreviews.length; index++) {
          final item = selectedPreviews[index];
          updateProgress(
            subtitle:
                '正在导入 ${index + 1} / ${selectedPreviews.length} 首歌曲',
            current: index,
          );
          try {
            await provider.importSongWithMetadata(
              item.filepath,
              item.title,
              item.artist,
            );
            imported++;
          } catch (_) {}
          updateProgress(
            subtitle:
                '已完成 ${index + 1} / ${selectedPreviews.length} 首歌曲',
            current: index + 1,
          );
        }
      },
    );

    if (!mounted) return;
    showAetherToast(
      context,
      message: '成功导入 $imported 首歌曲',
      kind: AetherToastKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final libraryProvider = context.watch<LibraryProvider>();
    context.watch<UIThemeProvider>();
    final cfg = context.tokens;

    return Container(
      padding: const EdgeInsets.all(AetherSpace.xxxl),
      decoration: BoxDecoration(
        color: cfg.bg1,
        border: Border.all(color: cfg.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AetherSearchField(
                    controller: _searchController,
                    hintText: '搜索歌曲、歌手、专辑…',
                    onChanged: libraryProvider.setSearchQuery,
                    onClear: () => libraryProvider.setSearchQuery(''),
                  ),
                ),
              ),
              const SizedBox(width: AetherSpace.lg),
              Builder(
                builder: (buttonContext) {
                  return AetherButton.primary(
                    label: '导入歌曲',
                    icon: Icons.folder_open_rounded,
                    onPressed: () async {
                      final box =
                          buttonContext.findRenderObject() as RenderBox?;
                      final overlay = Overlay.of(buttonContext)
                          .context
                          .findRenderObject() as RenderBox?;
                      if (box == null || overlay == null) return;
                      final topLeft =
                          box.localToGlobal(Offset.zero, ancestor: overlay);
                      final size = box.size;
                      final selected = await showAetherMenu<String>(
                        context: buttonContext,
                        globalPosition: Offset(topLeft.dx, topLeft.dy + size.height + 6),
                        items: const [
                          AetherMenuItem(
                            value: 'files',
                            label: '导入单首/多首音频文件',
                            icon: Icons.audio_file_rounded,
                          ),
                          AetherMenuItem(
                            value: 'folder',
                            label: '导入整个文件夹',
                            icon: Icons.folder_rounded,
                          ),
                        ],
                      );
                      if (selected == 'files') {
                        await _importFiles(libraryProvider);
                      } else if (selected == 'folder') {
                        await _importFolder(libraryProvider);
                      }
                    },
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: AetherSpace.xl),
          TagFilter(
            scrollCollapseFactor: _tagCollapseFactor,
            onExpandRequested: () {
              setState(() {
                _tagCollapseFactor = 0;
              });
            },
          ),
          const SizedBox(height: AetherSpace.xl),
          Expanded(
            child: AetherSurface(
              level: AetherSurfaceLevel.panel,
              borderRadius: BorderRadius.circular(AetherRadius.lg),
              color: cfg.bg1.withValues(alpha: 0.4),
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (notification) {
                  final delta = notification.scrollDelta ?? 0;
                  if (notification.metrics.axis == Axis.vertical &&
                      delta > 0 &&
                      _tagCollapseFactor < 1) {
                    setState(() {
                      _tagCollapseFactor = math.min(
                        1,
                        _tagCollapseFactor + delta / 140,
                      );
                    });
                  }
                  return false;
                },
                child: const SongTable(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
