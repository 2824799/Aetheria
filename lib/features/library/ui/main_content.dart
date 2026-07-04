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

class MainContent extends StatefulWidget {
  const MainContent({super.key});

  @override
  State<MainContent> createState() => _MainContentState();
}

class _MainContentState extends State<MainContent> {
  final TextEditingController _searchController = TextEditingController();

  Future<void> _importFiles(LibraryProvider provider) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'flac', 'm4a', 'ogg', 'aac'],
        allowMultiple: true,
      );

      if (result == null || result.paths.isEmpty) return;

      int successCount = 0;
      int failCount = 0;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      for (final path in result.paths) {
        if (path == null) continue;
        try {
          await provider.importSong(path);
          successCount++;
        } catch (e) {
          failCount++;
        }
      }

      Navigator.of(context).pop(); // pop progress indicator

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入完成: 成功 $successCount 首, 失败 $failCount 首')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入文件错误: $e')));
    }
  }

  Future<void> _importFolder(LibraryProvider provider) async {
    bool progressDialogOpen = false;
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory == null) return;

      String progressTitle = '正在扫描文件夹...';
      String progressSubtitle = '扫描完成后会继续读取音频元数据。';
      double? progressValue;
      void Function(void Function())? updateProgressDialog;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            updateProgressDialog = setDialogState;
            progressDialogOpen = true;
            final cfg = context.read<UIThemeProvider>().currentTheme;
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
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final filepaths = await music.scanDirectoryForPreview(
        dirPath: selectedDirectory,
      );
      if (filepaths.isEmpty) {
        if (context.mounted && progressDialogOpen) {
          Navigator.of(context).pop();
          progressDialogOpen = false;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('所选文件夹中未找到支持的音频文件')));
        return;
      }

      final previews = <dynamic>[];
      const batchSize = 24;
      for (int start = 0; start < filepaths.length; start += batchSize) {
        final end = math.min(start + batchSize, filepaths.length);
        updateProgressDialog?.call(() {
          progressTitle = '正在读取音频元数据...';
          progressSubtitle = '已处理 $end / ${filepaths.length} 首候选歌曲';
          progressValue = end / filepaths.length;
        });
        final batch = await music.previewAudioMetadata(
          filepaths: filepaths.sublist(start, end),
        );
        previews.addAll(batch);
      }

      if (context.mounted && progressDialogOpen) {
        Navigator.of(context).pop();
        progressDialogOpen = false;
      }

      _showImportPreviewModal(previews, provider);
    } catch (e) {
      if (context.mounted && progressDialogOpen) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('扫描文件夹错误: $e')));
    }
  }

  void _showImportPreviewModal(
    List<dynamic> previews,
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
                child: Container(
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
                              separatorBuilder: (_, __) => Divider(
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
                                Navigator.of(ctx).pop(); // pop preview dialog

                                // show progress hud
                                showDialog(
                                  context: this.context,
                                  barrierDismissible: false,
                                  builder: (c) => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );

                                int imported = 0;
                                for (int i = 0; i < previews.length; i++) {
                                  if (checkedItems[i]) {
                                    final item = previews[i];
                                    try {
                                      await provider.importSongWithMetadata(
                                        item.filepath,
                                        item.title,
                                        item.artist,
                                      );
                                      imported++;
                                    } catch (_) {}
                                  }
                                }

                                Navigator.of(
                                  this.context,
                                ).pop(); // pop progress hud

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
                          fontFamily: 'Outfit',
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
          const TagFilter(),
          const SizedBox(height: 16),

          // Custom Songs Grid List Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cfg.bgPanel.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cfg.border),
              ),
              child: const SongTable(),
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
