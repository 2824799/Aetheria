import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/glass_panel.dart';
import 'package:aetheria/features/library/ui/tag_filter.dart';
import 'package:aetheria/features/library/ui/song_table.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/src/rust/models/song.dart' show PreviewInfo;

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
    if (!mounted) {
      return null;
    }

    var progressDialogOpen = false;
    var progressTitle = initialTitle;
    var progressSubtitle = initialSubtitle;
    var progressCurrent = 0;
    var progressTotal = 0;
    var progressIndeterminate = true;
    void Function(void Function())? setDialogState;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, updateDialogState) {
          setDialogState = updateDialogState;
          progressDialogOpen = true;
          final cfg = dialogContext.read<UIThemeProvider>().currentTheme;
          final progressValue = progressIndeterminate || progressTotal <= 0
              ? null
              : (progressCurrent / progressTotal).clamp(0.0, 1.0);

          return Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 360,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cfg.bgPanel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cfg.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progressTitle,
                      style: TextStyle(
                        color: cfg.textMain,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      progressSubtitle,
                      style: TextStyle(
                        color: cfg.textSub,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: progressValue,
                        color: cfg.accent,
                        backgroundColor: cfg.border.withOpacity(0.45),
                      ),
                    ),
                    if (progressTotal > 0) ...[
                      const SizedBox(height: 10),
                      Text(
                        '已完成 $progressCurrent / $progressTotal 项',
                        style: TextStyle(
                          color: cfg.textMain,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
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
        if (title != null) {
          progressTitle = title;
        }
        if (subtitle != null) {
          progressSubtitle = subtitle;
        }
        if (current != null) {
          progressCurrent = current;
        }
        if (total != null) {
          progressTotal = total;
        }
        if (indeterminate != null) {
          progressIndeterminate = indeterminate;
        }
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

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入完成: 成功 $successCount 首, 失败 $failCount 首')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入文件错误: $e')));
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

      if (!mounted) {
        return;
      }
      if (previews == null || previews.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('所选文件夹中未找到支持的音频文件')));
        return;
      }

      _showImportPreviewModal(previews, provider);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('扫描文件夹错误: $e')));
    }
  }

  void _showImportPreviewModal(
    List<PreviewInfo> previews,
    LibraryProvider provider,
  ) {
    final checkedItems = List<bool>.filled(previews.length, true);

    showDialog(
      context: context,
      builder: (ctx) {
        final cfg = context.read<UIThemeProvider>().currentTheme;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Center(
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: 580,
                  height: 480,
                  child: GlassPanel(
                    borderRadius: BorderRadius.circular(16),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '导入预览 (共 ${previews.length} 首)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: cfg.textMain,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                color: cfg.textSub,
                                size: 20,
                              ),
                              onPressed: () => Navigator.of(ctx).pop(),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () {
                                setModalState(() {
                                  checkedItems.fillRange(
                                    0,
                                    checkedItems.length,
                                    true,
                                  );
                                });
                              },
                              child: const Text('全选'),
                            ),
                            TextButton(
                              onPressed: () {
                                setModalState(() {
                                  checkedItems.fillRange(
                                    0,
                                    checkedItems.length,
                                    false,
                                  );
                                });
                              },
                              child: const Text('全不选'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: cfg.border),
                            ),
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: previews.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                color: cfg.border.withOpacity(0.5),
                              ),
                              itemBuilder: (context, index) {
                                final item = previews[index];
                                return CheckboxListTile(
                                  value: checkedItems[index],
                                  title: Text(
                                    item.title,
                                    style: TextStyle(
                                      color: cfg.textMain,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${item.artist} - ${item.filename}',
                                    style: TextStyle(
                                      color: cfg.textSub,
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onChanged: (val) {
                                    setModalState(() {
                                      checkedItems[index] = val ?? false;
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('取消'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () async {
                                final selectedPreviews = <PreviewInfo>[];
                                for (
                                  int index = 0;
                                  index < previews.length;
                                  index++
                                ) {
                                  if (checkedItems[index]) {
                                    selectedPreviews.add(previews[index]);
                                  }
                                }

                                Navigator.of(ctx).pop();

                                if (selectedPreviews.isEmpty) {
                                  if (!mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text('请至少选择一首歌曲再导入'),
                                    ),
                                  );
                                  return;
                                }

                                int imported = 0;
                                await _runProgressDialog<void>(
                                  initialTitle: '正在导入已选歌曲...',
                                  initialSubtitle:
                                      '已完成 0 / ${selectedPreviews.length} 首歌曲',
                                  task: (updateProgress) async {
                                    updateProgress(
                                      current: 0,
                                      total: selectedPreviews.length,
                                      indeterminate: false,
                                    );
                                    for (
                                      int index = 0;
                                      index < selectedPreviews.length;
                                      index++
                                    ) {
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

                                if (!mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(content: Text('成功导入 $imported 首歌曲')),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: cfg.accent,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('开始导入'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final libraryProvider = context.watch<LibraryProvider>();
    final themeProvider = context.watch<UIThemeProvider>();
    final cfg = themeProvider.currentTheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cfg.bgPanel,
        border: Border.all(color: cfg.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Search & Import Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Search Input Box
              SizedBox(
                width: 300,
                height: 38,
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => libraryProvider.setSearchQuery(val),
                  style: TextStyle(color: cfg.textMain, fontSize: 13),
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: cfg.textSub,
                    ),
                    hintText: '搜索歌曲、歌手、专辑...',
                    hintStyle: TextStyle(color: cfg.textSub.withOpacity(0.5)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: cfg.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: cfg.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: cfg.accent, width: 2.0),
                    ),
                  ),
                ),
              ),

              // Import Dropdown Options
              PopupMenuButton<String>(
                onSelected: (val) {
                  if (val == 'files') {
                    _importFiles(libraryProvider);
                  } else if (val == 'folder') {
                    _importFolder(libraryProvider);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'files',
                    child: Row(
                      children: [
                        Icon(Icons.audio_file, size: 16),
                        SizedBox(width: 8),
                        Text('导入单首/多首音频文件'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'folder',
                    child: Row(
                      children: [
                        Icon(Icons.folder, size: 16),
                        SizedBox(width: 8),
                        Text('导入整个文件夹'),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: cfg.accent,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: cfg.accentGlow,
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.folder_open,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '导入歌曲',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Custom Multi-dimensional Tag Filter Panel
          TagFilter(
            scrollCollapseFactor: _tagCollapseFactor,
            onExpandRequested: () {
              setState(() {
                _tagCollapseFactor = 0;
              });
            },
          ),
          const SizedBox(height: 16),

          // Custom Songs Grid List Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cfg.bgPanel.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cfg.border),
              ),
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
