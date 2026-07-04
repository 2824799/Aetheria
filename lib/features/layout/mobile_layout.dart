import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/glass_panel.dart';
import 'package:aetheria/features/library/ui/tag_filter.dart';
import 'package:aetheria/features/library/ui/tag_manager_modal.dart';
import 'package:aetheria/features/library/ui/settings_modal.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:aetheria/src/rust/models/playlist.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'dart:io';
import 'package:aetheria/services/native_audio_helper.dart';

class MobileLayout extends StatefulWidget {
  const MobileLayout({super.key});

  @override
  State<MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<MobileLayout> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  bool _isImporting = false;
  String _importProgressTitle = '正在处理...';
  String _importProgressSubtitle = '';
  int _importProgressCurrent = 0;
  int _importProgressTotal = 0;
  bool _importProgressIndeterminate = true;

  @override
  void initState() {
    super.initState();
    final lib = context.read<LibraryProvider>();
    _searchController.text = lib.searchQuery;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _parseHexColor(String hex, Color defaultColor) {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return defaultColor;
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(1)} ${suffixes[i]}';
  }

  void _updateImportProgress({
    required String title,
    required String subtitle,
    int current = 0,
    int total = 0,
    bool indeterminate = true,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isImporting = true;
      _importProgressTitle = title;
      _importProgressSubtitle = subtitle;
      _importProgressCurrent = current;
      _importProgressTotal = total;
      _importProgressIndeterminate = indeterminate;
    });
  }

  void _clearImportProgress() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isImporting = false;
      _importProgressTitle = '正在处理...';
      _importProgressSubtitle = '';
      _importProgressCurrent = 0;
      _importProgressTotal = 0;
      _importProgressIndeterminate = true;
    });
  }

  // Import audio files
  Future<void> _importFiles(LibraryProvider provider) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'flac', 'm4a', 'ogg', 'aac'],
        allowMultiple: true,
      );

      final selectedPaths = result?.paths.whereType<String>().toList() ?? const [];
      if (selectedPaths.isEmpty) return;

      _updateImportProgress(
        title: '正在导入音频文件...',
        subtitle: '已完成 0 / ${selectedPaths.length} 首歌曲',
        current: 0,
        total: selectedPaths.length,
        indeterminate: false,
      );

      int successCount = 0;
      int failCount = 0;

      for (int index = 0; index < selectedPaths.length; index++) {
        _updateImportProgress(
          title: '正在导入音频文件...',
          subtitle: '正在导入 ${index + 1} / ${selectedPaths.length} 首歌曲',
          current: index,
          total: selectedPaths.length,
          indeterminate: false,
        );
        try {
          await provider.importSong(selectedPaths[index]);
          successCount++;
        } catch (_) {
          failCount++;
        }
        _updateImportProgress(
          title: '正在导入音频文件...',
          subtitle: '已完成 ${index + 1} / ${selectedPaths.length} 首歌曲',
          current: index + 1,
          total: selectedPaths.length,
          indeterminate: false,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入完成: 成功 $successCount 首, 失败 $failCount 首')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入文件错误: $e')));
    } finally {
      _clearImportProgress();
    }
  }

  // Import folder
  Future<void> _importFolder(LibraryProvider provider) async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory == null) return;

      _updateImportProgress(
        title: '正在扫描文件夹...',
        subtitle: '正在搜索支持的音频文件...',
      );

      // Scan directory for preview
      final filepaths = await music.scanDirectoryForPreview(
        dirPath: selectedDirectory,
      );
      if (filepaths.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('所选文件夹中未找到支持的音频文件')));
        return;
      }

      _updateImportProgress(
        title: '正在读取音频元数据...',
        subtitle: '已处理 0 / ${filepaths.length} 首候选歌曲',
        current: 0,
        total: filepaths.length,
        indeterminate: false,
      );

      final previews = <PreviewInfo>[];
      const batchSize = 24;
      for (int start = 0; start < filepaths.length; start += batchSize) {
        final end = start + batchSize > filepaths.length
            ? filepaths.length
            : start + batchSize;
        final batch = await music.previewAudioMetadata(
          filepaths: filepaths.sublist(start, end),
        );
        previews.addAll(batch);
        _updateImportProgress(
          title: '正在读取音频元数据...',
          subtitle: '已处理 $end / ${filepaths.length} 首候选歌曲',
          current: end,
          total: filepaths.length,
          indeterminate: false,
        );
      }

      if (!mounted) return;
      // Present import preview modal
      _showImportPreviewModal(previews, provider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('扫描文件夹错误: $e')));
    } finally {
      _clearImportProgress();
    }
  }

  // Import Preview Modal
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
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  height: MediaQuery.of(context).size.height * 0.65,
                  child: GlassPanel(
                    borderRadius: BorderRadius.circular(16),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '导入预览 (共 ${previews.length} 首)',
                              style: TextStyle(
                                fontSize: 15,
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
                        const SizedBox(height: 10),
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
                              child: const Text(
                                '全选',
                                style: TextStyle(fontSize: 12),
                              ),
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
                              child: const Text(
                                '全不选',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
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
                                  dense: true,
                                  value: checkedItems[index],
                                  title: Text(
                                    item.title.isNotEmpty
                                        ? item.title
                                        : item.filename,
                                    style: TextStyle(
                                      color: cfg.textMain,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    item.artist.isNotEmpty
                                        ? item.artist
                                        : '未知歌手',
                                    style: TextStyle(
                                      color: cfg.textSub,
                                      fontSize: 10,
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
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('取消'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () async {
                                final selectedPreviews = <PreviewInfo>[];
                                for (int index = 0; index < previews.length; index++) {
                                  if (checkedItems[index]) {
                                    selectedPreviews.add(previews[index]);
                                  }
                                }

                                Navigator.of(ctx).pop();

                                if (selectedPreviews.isEmpty) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(this.context).showSnackBar(
                                    const SnackBar(content: Text('请至少选择一首歌曲再导入')),
                                  );
                                  return;
                                }

                                _updateImportProgress(
                                  title: '正在导入已选歌曲...',
                                  subtitle: '已完成 0 / ${selectedPreviews.length} 首歌曲',
                                  current: 0,
                                  total: selectedPreviews.length,
                                  indeterminate: false,
                                );

                                int imported = 0;
                                for (int i = 0; i < selectedPreviews.length; i++) {
                                  final item = selectedPreviews[i];
                                  _updateImportProgress(
                                    title: '正在导入已选歌曲...',
                                    subtitle:
                                        '正在导入 ${i + 1} / ${selectedPreviews.length} 首歌曲',
                                    current: i,
                                    total: selectedPreviews.length,
                                    indeterminate: false,
                                  );
                                  try {
                                    await provider.importSongWithMetadata(
                                      item.filepath,
                                      item.title,
                                      item.artist,
                                    );
                                    imported++;
                                  } catch (_) {}
                                  _updateImportProgress(
                                    title: '正在导入已选歌曲...',
                                    subtitle:
                                        '已完成 ${i + 1} / ${selectedPreviews.length} 首歌曲',
                                    current: i + 1,
                                    total: selectedPreviews.length,
                                    indeterminate: false,
                                  );
                                }

                                if (mounted) {
                                  _clearImportProgress();
                                }

                                if (!mounted) return;
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

  // Playlist Create dialog
  void _showCreatePlaylistDialog(
    BuildContext context,
    LibraryProvider provider,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '歌单名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(ctx).pop();
                try {
                  await provider.createPlaylist(name);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('创建失败: $e')));
                }
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  // Playlist Rename dialog
  void _showRenamePlaylistDialog(
    BuildContext context,
    String id,
    String currentName,
    LibraryProvider provider,
  ) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名歌单'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '新歌单名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(ctx).pop();
                try {
                  await provider.renamePlaylist(id, name);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('命名失败: $e')));
                }
              }
            },
            child: const Text('重命名'),
          ),
        ],
      ),
    );
  }

  // Playlist Delete confirmation
  void _confirmDeletePlaylist(
    BuildContext context,
    String id,
    String name,
    LibraryProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除歌单？'),
        content: Text('您确定要删除歌单“$name”吗？这不会删除音乐库中的歌曲。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await provider.deletePlaylist(id);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // Song Context Menu Bottom Sheet
  void _showSongContextMenu(
    BuildContext context,
    Song song,
    LibraryProvider libraryProvider,
    AudioPlayerProvider audioProvider,
  ) {
    final themeProvider = context.read<UIThemeProvider>();
    final cfg = themeProvider.currentTheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: cfg.bgPanel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: cfg.border)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cfg.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                  ),
                ),
                Text(
                  song.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: cfg.textMain,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist ?? '未知歌手',
                  style: TextStyle(fontSize: 12, color: cfg.textSub),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),

                // Play Item
                ListTile(
                  leading: Icon(Icons.play_arrow, color: cfg.accent),
                  title: Text(
                    '播放歌曲',
                    style: TextStyle(
                      color: cfg.textMain,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    try {
                      await audioProvider.playSong(
                        song,
                        libraryProvider.displaySongs,
                        libraryProvider.libraryPath,
                        audioServerPort: libraryProvider.audioServerPort,
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('播放失败 - 诊断报告'),
                          content: SingleChildScrollView(
                            child: SelectableText(
                              e.toString(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),

                // Open Details Item
                ListTile(
                  leading: Icon(Icons.info_outline, color: cfg.textMain),
                  title: Text(
                    '打开详细信息',
                    style: TextStyle(
                      color: cfg.textMain,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    audioProvider.setActiveSong(song);
                    _showSongDetailSheet(context, song);
                  },
                ),

                // Add to Playlist Sub-menu
                if (libraryProvider.playlists.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      '添加到歌单',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: cfg.textSub,
                      ),
                    ),
                  ),
                  Container(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: libraryProvider.playlists.length,
                      itemBuilder: (context, index) {
                        final pl = libraryProvider.playlists[index];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () async {
                              Navigator.of(ctx).pop();
                              try {
                                await libraryProvider.addSongsToPlaylist(
                                  pl.id,
                                  [song.id],
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('已添加至歌单《${pl.name}》')),
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('添加失败: $e')),
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: cfg.bgHover,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: cfg.border),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                pl.name,
                                style: TextStyle(
                                  color: cfg.textMain,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Remove from Playlist (if activePlaylistId is not null)
                if (libraryProvider.activePlaylistId != null)
                  ListTile(
                    leading: const Icon(
                      Icons.remove_circle_outline,
                      color: Colors.orangeAccent,
                    ),
                    title: const Text(
                      '从当前歌单移除',
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      try {
                        await libraryProvider.removeSongsFromPlaylist(
                          libraryProvider.activePlaylistId!,
                          [song.id],
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('移除失败: $e')));
                      }
                    },
                  ),

                // Delete Item
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    '彻底删除歌曲',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('删除歌曲？'),
                        content: Text(
                          '确定要彻底删除歌曲《${song.title}》吗？这会同时删除本地音乐文件！',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(c).pop(false),
                            child: const Text('取消'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(c).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        await libraryProvider.deleteSong(song.id);
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Link New Version picker
  Future<void> _linkNewVersion(
    BuildContext context,
    Song song,
    LibraryProvider provider,
  ) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'flac', 'm4a', 'ogg', 'aac'],
      );

      if (result == null || result.files.single.path == null) return;
      final path = result.files.single.path!;

      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      await provider.importAudioVersionForSong(song.id, path);

      if (!context.mounted) return;
      Navigator.of(context).pop(); // pop progress indicator
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('成功关联新音源版本')));
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // pop loader if failed
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('关联失败: $e')));
    }
  }

  // Export audio file
  Future<void> _exportVersion(
    BuildContext context,
    AudioVersion version,
  ) async {
    try {
      if (Platform.isAndroid) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(child: CircularProgressIndicator()),
        );
        final libraryPath = context.read<LibraryProvider>().libraryPath;
        final srcPath = '$libraryPath/${version.filepath}'.replaceAll(
          '\\',
          '/',
        );

        await NativeAudioHelper.saveToDownloads(srcPath, version.originalName);

        if (!context.mounted) return;
        Navigator.of(context).pop(); // pop progress indicator
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已成功导出至系统 Downloads/Aetheria 文件夹！')),
        );
      } else {
        String? destPath = await FilePicker.platform.saveFile(
          fileName: version.originalName,
          dialogTitle: '选择保存音频的位置',
        );

        if (destPath == null) return;

        if (!context.mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(child: CircularProgressIndicator()),
        );

        await music.exportAudioFile(versionId: version.id, destPath: destPath);

        if (!context.mounted) return;
        Navigator.of(context).pop(); // pop progress indicator
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('音频文件导出还原成功！')));
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  // Full Screen Detail Sheet (Editable Metadata, Version settings, Tag binding, Lyrics, Seeker, Controls)
  void _showSongDetailSheet(BuildContext context, Song initialSong) {
    context.read<AudioPlayerProvider>().setActiveSong(initialSong);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _SongDetailSheetBody(state: this, initialSong: initialSong);
      },
    );
  }

  // Helper widget to render detail sheet tab contents
  Widget _buildTabContent(
    BuildContext context,
    Song song,
    String activeTab,
    LibraryProvider libraryProvider,
    AudioPlayerProvider audioProvider,
    AppThemeConfig cfg,
  ) {
    if (activeTab == 'versions') {
      return Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: song.versions.length,
              itemBuilder: (context, index) {
                final v = song.versions[index];
                final durationMin = (v.duration / 60).floor();
                final durationSec = (v.duration % 60)
                    .round()
                    .toString()
                    .padLeft(2, '0');

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  color: Colors.white.withOpacity(0.04),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: cfg.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          v.originalName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: cfg.textMain,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${v.format?.toUpperCase() ?? "未知"} | ${(v.bitrate ?? 0) ~/ 1000}kbps | ${v.sampleRate != null ? (v.sampleRate! / 1000).toStringAsFixed(1) : "未知"}kHz | $durationMin:$durationSec | ${_formatFileSize(v.fileSize.toInt())}',
                          style: TextStyle(fontSize: 9, color: cfg.textSub),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Enable check
                            InkWell(
                              onTap: () async {
                                await libraryProvider.updateVersionStatus(
                                  v.id,
                                  !v.isEnabled,
                                  v.isPrimary,
                                );
                              },
                              child: Row(
                                children: [
                                  Icon(
                                    v.isEnabled
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    size: 14,
                                    color: v.isEnabled
                                        ? cfg.accent
                                        : cfg.textSub,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '启用',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: cfg.textMain,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Primary radio
                            InkWell(
                              onTap: () async {
                                if (!v.isPrimary) {
                                  await libraryProvider.updateVersionStatus(
                                    v.id,
                                    true,
                                    true,
                                  );
                                }
                              },
                              child: Row(
                                children: [
                                  Icon(
                                    v.isPrimary
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 14,
                                    color: v.isPrimary
                                        ? cfg.accent
                                        : cfg.textSub,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '主音源',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: cfg.textMain,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            // Export and Delete
                            IconButton(
                              icon: Icon(
                                Icons.download,
                                size: 14,
                                color: cfg.textSub,
                              ),
                              onPressed: () => _exportVersion(context, v),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            if (song.versions.length > 1) ...[
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 14,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () async {
                                  try {
                                    await libraryProvider.deleteAudioVersion(
                                      v.id,
                                    );
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('删除失败: $e')),
                                    );
                                  }
                                },
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Bind another version track
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SizedBox(
              width: double.infinity,
              height: 32,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _linkNewVersion(context, song, libraryProvider),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('绑定其他音轨文件', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cfg.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (activeTab == 'tags') {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 3.2,
        ),
        itemCount: libraryProvider.tags.length,
        itemBuilder: (context, index) {
          final tag = libraryProvider.tags[index];
          final isBound = song.tags.any((t) => t.id == tag.id);
          final tagColor = tag.color != null
              ? _parseHexColor(tag.color!, cfg.textSub)
              : cfg.textSub;

          return InkWell(
            onTap: () async {
              await libraryProvider.tagSong(song.id, tag.id, !isBound);
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isBound
                    ? tagColor.withOpacity(0.08)
                    : Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isBound ? tagColor : cfg.border.withOpacity(0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isBound ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 14,
                    color: isBound ? tagColor : cfg.textSub,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tag.name,
                      style: TextStyle(
                        color: tagColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    if (activeTab == 'lyrics') {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Align(
          alignment: Alignment.topCenter,
          child: Text(
            song.lyrics != null && song.lyrics!.trim().isNotEmpty
                ? song.lyrics!
                : '暂无歌词',
            textAlign: TextAlign.center,
            style: TextStyle(color: cfg.textMain, height: 1.6, fontSize: 12),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final libraryProvider = context.watch<LibraryProvider>();
    final audioProvider = context.watch<AudioPlayerProvider>();
    final themeProvider = context.watch<UIThemeProvider>();
    final cfg = themeProvider.currentTheme;

    final songs = libraryProvider.displaySongs;
    final playlists = libraryProvider.playlists;
    final activePlaylistId = libraryProvider.activePlaylistId;
    final activePlaylistName = activePlaylistId == null
        ? '全部音乐'
        : playlists
              .firstWhere(
                (p) => p.id == activePlaylistId,
                orElse: () => Playlist(id: '', name: '未知歌单', createdAt: ''),
              )
              .name;

    final playingSong = audioProvider.playingSong;
    final curMs = audioProvider.currentPosition.inMilliseconds.toDouble();
    final totMs = audioProvider.totalDuration.inMilliseconds.toDouble();
    final progressPercent = totMs > 0
        ? (curMs / totMs).clamp(0.0, 1.0) * 100
        : 0.0;

    return Stack(
      children: [
        Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.transparent,
          drawer: Drawer(
            backgroundColor: Colors.transparent,
            child: GlassPanel(
              borderRadius: BorderRadius.zero,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Drawer Header
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '我的歌单',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: cfg.textMain,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.add,
                              color: cfg.textMain,
                              size: 22,
                            ),
                            onPressed: () => _showCreatePlaylistDialog(
                              context,
                              libraryProvider,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Playlist Items
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        children: [
                          ListTile(
                            leading: Icon(
                              Icons.library_music,
                              color: activePlaylistId == null
                                  ? cfg.accent
                                  : cfg.textSub,
                            ),
                            title: Text(
                              '全部音乐',
                              style: TextStyle(
                                color: cfg.textMain,
                                fontSize: 14,
                              ),
                            ),
                            trailing: Text(
                              '${libraryProvider.songs.length}',
                              style: TextStyle(
                                color: cfg.textSub,
                                fontSize: 12,
                              ),
                            ),
                            selected: activePlaylistId == null,
                            selectedTileColor: cfg.bgHover,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            onTap: () {
                              libraryProvider.setActivePlaylist(null);
                              Navigator.of(context).pop(); // Close drawer
                            },
                          ),
                          const SizedBox(height: 8),
                          ...playlists.map((pl) {
                            final isSelected = activePlaylistId == pl.id;
                            return ListTile(
                              leading: Icon(
                                Icons.queue_music,
                                color: isSelected ? cfg.accent : cfg.textSub,
                              ),
                              title: Text(
                                pl.name,
                                style: TextStyle(
                                  color: cfg.textMain,
                                  fontSize: 14,
                                ),
                              ),
                              selected: isSelected,
                              selectedTileColor: cfg.bgHover,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              onTap: () {
                                libraryProvider.setActivePlaylist(pl.id);
                                Navigator.of(context).pop();
                              },
                              trailing: PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_vert,
                                  color: cfg.textSub,
                                  size: 18,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onSelected: (val) {
                                  if (val == 'rename') {
                                    _showRenamePlaylistDialog(
                                      context,
                                      pl.id,
                                      pl.name,
                                      libraryProvider,
                                    );
                                  } else if (val == 'delete') {
                                    _confirmDeletePlaylist(
                                      context,
                                      pl.id,
                                      pl.name,
                                      libraryProvider,
                                    );
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'rename',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 16),
                                        SizedBox(width: 8),
                                        Text(
                                          '重命名歌单',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete,
                                          color: Colors.redAccent,
                                          size: 16,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          '删除歌单',
                                          style: TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.menu, color: cfg.textMain),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            title: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [cfg.accent, Colors.orangeAccent],
              ).createShader(bounds),
              child: Text(
                'Aetheria Mobile',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  fontFamily: 'Outfit',
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.sell_outlined, color: cfg.textMain, size: 20),
                onPressed: () => TagManagerModal.show(context),
                tooltip: '标签管理',
              ),
              IconButton(
                icon: Icon(
                  Icons.settings_outlined,
                  color: cfg.textMain,
                  size: 20,
                ),
                onPressed: () => SettingsModal.show(context),
                tooltip: '系统设置',
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search Input Box
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: SizedBox(
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
                      hintText: '搜索歌名、歌手或格式...',
                      hintStyle: TextStyle(color: cfg.textSub.withOpacity(0.5)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
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
              ),

              // Import buttons row
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 34,
                        child: ElevatedButton.icon(
                          onPressed: () => _importFiles(libraryProvider),
                          icon: const Icon(Icons.audio_file, size: 14),
                          label: const Text(
                            '导入单歌',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cfg.border,
                            foregroundColor: cfg.textMain,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 34,
                        child: ElevatedButton.icon(
                          onPressed: () => _importFolder(libraryProvider),
                          icon: const Icon(Icons.folder_open, size: 14),
                          label: const Text(
                            '导入目录',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cfg.border,
                            foregroundColor: cfg.textMain,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // TagFilter widget
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TagFilter(),
              ),

              // Active playlist / songs count indicator
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      activePlaylistName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: cfg.textSub,
                      ),
                    ),
                    Text(
                      '共 ${songs.length} 首歌曲',
                      style: TextStyle(fontSize: 11, color: cfg.textSub),
                    ),
                  ],
                ),
              ),

              // Songs List Area
              Expanded(
                child: songs.isEmpty
                    ? Center(
                        child: Text(
                          '暂无歌曲，请点击上方按钮导入音源',
                          style: TextStyle(color: cfg.textSub, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: songs.length,
                        itemBuilder: (context, index) {
                          final song = songs[index];
                          final isCurrentlyPlaying = playingSong?.id == song.id;
                          final isActive =
                              audioProvider.activeSong?.id == song.id;
                          AudioVersion? primary;
                          for (final v in song.versions) {
                            if (v.isPrimary) {
                              primary = v;
                              break;
                            }
                          }
                          if (primary == null && song.versions.isNotEmpty) {
                            primary = song.versions.first;
                          }

                          // Build the specs label text
                          String specsText = '无源';
                          if (primary != null) {
                            final specs = <String>[];
                            if (primary.format != null)
                              specs.add(primary.format!.toUpperCase());
                            if (primary.format?.toLowerCase() == 'flac' &&
                                primary.bitDepth != null) {
                              specs.add('${primary.bitDepth}b');
                            }
                            if (primary.sampleRate != null) {
                              final rateK = primary.sampleRate! / 1000;
                              specs.add(
                                '${rateK.toStringAsFixed(primary.sampleRate! % 1000 == 0 ? 0 : 1)}k',
                              );
                            }
                            if (primary.bitrate != null) {
                              specs.add(
                                '${(primary.bitrate! / 1000).round()}kbps',
                              );
                            }
                            if (primary.loudness != null) {
                              specs.add(
                                '${primary.loudness!.toStringAsFixed(1)}dB',
                              );
                            }
                            if (specs.isNotEmpty) {
                              specsText = specs.join('/');
                            }
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: InkWell(
                              onTap: () async {
                                audioProvider.setActiveSong(song);
                                try {
                                  await audioProvider.playSong(
                                    song,
                                    songs,
                                    libraryProvider.libraryPath,
                                    audioServerPort:
                                        libraryProvider.audioServerPort,
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('播放失败 - 诊断报告'),
                                      content: SingleChildScrollView(
                                        child: SelectableText(
                                          e.toString(),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(),
                                          child: const Text('关闭'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                              onLongPress: () => _showSongContextMenu(
                                context,
                                song,
                                libraryProvider,
                                audioProvider,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isActive ? cfg.bgHover : cfg.bgPanel,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border(
                                    left: BorderSide(
                                      color: isCurrentlyPlaying
                                          ? cfg.accent
                                          : Colors.transparent,
                                      width: 4,
                                    ),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          // Song Title
                                          Text(
                                            song.title,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13.5,
                                              color: isCurrentlyPlaying
                                                  ? cfg.accent
                                                  : cfg.textMain,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),

                                          // Row 1: Artist name and Tech specs badge
                                          Row(
                                            children: [
                                              Text(
                                                song.artist ?? '未知歌手',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: cfg.textSub,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 1,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: cfg.border,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  specsText,
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    color: cfg.textMain,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          // Row 2: All tags wrapped below it
                                          if (song.tags.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: song.tags.map((t) {
                                                final c = t.color != null
                                                    ? _parseHexColor(
                                                        t.color!,
                                                        cfg.textSub,
                                                      )
                                                    : cfg.textSub;
                                                return Text(
                                                  '#${t.name}',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: c,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.more_horiz,
                                        color: cfg.textSub,
                                        size: 20,
                                      ),
                                      onPressed: () => _showSongContextMenu(
                                        context,
                                        song,
                                        libraryProvider,
                                        audioProvider,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // Floating mini playbar (replicates Apple Music style floating bar)
              if (playingSong != null)
                Padding(
                  padding: const EdgeInsets.only(
                    left: 12,
                    right: 12,
                    bottom: 12,
                  ),
                  child: GestureDetector(
                    onTap: () {
                      audioProvider.setActiveSong(playingSong);
                      _showSongDetailSheet(context, playingSong);
                    },
                    child: GlassPanel(
                      borderRadius: BorderRadius.circular(12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Stack(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: cfg.accentGlow,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: cfg.border),
                                ),
                                child: Icon(
                                  Icons.music_note,
                                  color: cfg.accent,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      playingSong.title,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: cfg.textMain,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      playingSong.artist ?? '未知歌手',
                                      style: TextStyle(
                                        color: cfg.textSub,
                                        fontSize: 11,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  audioProvider.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  color: cfg.accent,
                                  size: 22,
                                ),
                                onPressed: () => audioProvider.playPause(),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: Icon(
                                  Icons.skip_next,
                                  color: cfg.textMain,
                                  size: 20,
                                ),
                                onPressed: () => audioProvider.playNext(),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          // Bottom tiny progress bar line
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom:
                                -10, // offsets to bottom edge inside padding
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                height: 2,
                                decoration: BoxDecoration(
                                  color: cfg.border,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                                child: FractionallySizedBox(
                                  widthFactor: (progressPercent / 100).clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: cfg.accent,
                                      borderRadius: BorderRadius.circular(1),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_isImporting)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: GlassPanel(
                  borderRadius: BorderRadius.circular(12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _importProgressTitle,
                        style: TextStyle(
                          color: cfg.textMain,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: 260,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            minHeight: 6,
                            value:
                                _importProgressIndeterminate ||
                                        _importProgressTotal <= 0
                                    ? null
                                    : (_importProgressCurrent /
                                            _importProgressTotal)
                                        .clamp(0.0, 1.0),
                            color: cfg.accent,
                            backgroundColor: cfg.border.withOpacity(0.45),
                          ),
                        ),
                      ),
                      if (_importProgressTotal > 0) ...[
                        const SizedBox(height: 10),
                        Text(
                          '已完成 $_importProgressCurrent / $_importProgressTotal 首',
                          style: TextStyle(
                            color: cfg.textMain,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (_importProgressSubtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 260,
                          child: Text(
                            _importProgressSubtitle,
                            style: TextStyle(
                              color: cfg.textSub,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SongDetailSheetBody extends StatefulWidget {
  final _MobileLayoutState state;
  final Song initialSong;

  const _SongDetailSheetBody({required this.state, required this.initialSong});

  @override
  State<_SongDetailSheetBody> createState() => _SongDetailSheetBodyState();
}

class _SongDetailSheetBodyState extends State<_SongDetailSheetBody> {
  String activeTab = 'versions';
  bool showVolumeSlider = false;
  late TextEditingController titleController;
  late TextEditingController artistController;
  late FocusNode focusNodeTitle;
  late FocusNode focusNodeArtist;
  String? lastSongId;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.initialSong.title);
    artistController = TextEditingController(
      text: widget.initialSong.artist ?? '未知歌手',
    );
    focusNodeTitle = FocusNode();
    focusNodeArtist = FocusNode();
    lastSongId = widget.initialSong.id;

    focusNodeTitle.addListener(_onTitleFocusChange);
    focusNodeArtist.addListener(_onArtistFocusChange);
  }

  @override
  void dispose() {
    titleController.dispose();
    artistController.dispose();
    focusNodeTitle.dispose();
    focusNodeArtist.dispose();
    super.dispose();
  }

  void _onTitleFocusChange() {
    if (!focusNodeTitle.hasFocus) {
      _saveMetadata();
    }
  }

  void _onArtistFocusChange() {
    if (!focusNodeArtist.hasFocus) {
      _saveMetadata();
    }
  }

  Future<void> _saveMetadata() async {
    if (lastSongId == null) return;
    final libraryProvider = context.read<LibraryProvider>();
    final song = libraryProvider.songs.firstWhere(
      (s) => s.id == lastSongId,
      orElse: () => widget.initialSong,
    );
    final newTitle = titleController.text.trim();
    final newArtistText = artistController.text.trim();
    final newArtist = newArtistText == '未知歌手' ? '' : newArtistText;

    if (newTitle.isNotEmpty &&
        (newTitle != song.title || newArtist != (song.artist ?? ''))) {
      try {
        await libraryProvider.updateSongMetadata(song.id, newTitle, newArtist);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存元数据失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryProvider = context.watch<LibraryProvider>();
    final audioProvider = context.watch<AudioPlayerProvider>();
    final cfg = context.read<UIThemeProvider>().currentTheme;

    // Follow the player's active song if detail view is open
    final currentActiveSong = audioProvider.activeSong ?? widget.initialSong;

    if (currentActiveSong.id != lastSongId) {
      lastSongId = currentActiveSong.id;
      final songData = libraryProvider.songs.firstWhere(
        (s) => s.id == currentActiveSong.id,
        orElse: () => currentActiveSong,
      );
      titleController.text = songData.title;
      artistController.text = songData.artist ?? '未知歌手';
    }

    final song = libraryProvider.songs.firstWhere(
      (s) => s.id == currentActiveSong.id,
      orElse: () => currentActiveSong,
    );

    final isPlayingThisSong = audioProvider.playingSong?.id == song.id;
    final durationMin = (audioProvider.totalDuration.inSeconds / 60).floor();
    final durationSec = (audioProvider.totalDuration.inSeconds % 60)
        .toString()
        .padLeft(2, '0');
    final curMin = (audioProvider.currentPosition.inSeconds / 60).floor();
    final curSec = (audioProvider.currentPosition.inSeconds % 60)
        .toString()
        .padLeft(2, '0');

    final curMs = audioProvider.currentPosition.inMilliseconds.toDouble();
    final totMs = audioProvider.totalDuration.inMilliseconds.toDouble();
    final progress = totMs > 0 ? (curMs / totMs).clamp(0.0, 1.0) : 0.0;

    return Container(
      height: MediaQuery.of(context).size.height * 0.95,
      decoration: BoxDecoration(
        gradient: cfg.bgApp,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Pull bar / Top close button row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      size: 28,
                      color: cfg.textMain,
                    ),
                    onPressed: () {
                      _saveMetadata();
                      Navigator.of(context).pop();
                    },
                  ),
                  Text(
                    isPlayingThisSong ? '正在播放' : '歌曲详情',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: cfg.textSub,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 48), // Spacer
                ],
              ),
            ),

            // Cover section with radial-glow
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: cfg.accentGlow,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: cfg.accent.withOpacity(0.12),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                      border: Border.all(color: cfg.border),
                    ),
                    child: Icon(Icons.music_note, size: 45, color: cfg.accent),
                  ),
                  const SizedBox(height: 8),

                  // Editable Title field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: TextField(
                      controller: titleController,
                      focusNode: focusNodeTitle,
                      textAlign: TextAlign.center,
                      onSubmitted: (_) => _saveMetadata(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: cfg.textMain,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 2),
                      ),
                    ),
                  ),

                  // Editable Artist field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: TextField(
                      controller: artistController,
                      focusNode: focusNodeArtist,
                      textAlign: TextAlign.center,
                      onSubmitted: (_) => _saveMetadata(),
                      style: TextStyle(fontSize: 12, color: cfg.textSub),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Three tab buttons, expanded to fill available height
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              activeTab = 'versions';
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: activeTab == 'versions'
                                      ? cfg.accent
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(
                              '音频源 (${song.versions.length})',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: activeTab == 'versions'
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: activeTab == 'versions'
                                    ? cfg.textMain
                                    : cfg.textSub,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              activeTab = 'tags';
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: activeTab == 'tags'
                                      ? cfg.accent
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(
                              '关联标签 (${song.tags.length})',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: activeTab == 'tags'
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: activeTab == 'tags'
                                    ? cfg.textMain
                                    : cfg.textSub,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              activeTab = 'lyrics';
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: activeTab == 'lyrics'
                                      ? cfg.accent
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(
                              '滚动歌词',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: activeTab == 'lyrics'
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: activeTab == 'lyrics'
                                    ? cfg.textMain
                                    : cfg.textSub,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 1, color: cfg.border),

                  // Scrollable list tab content is now Expanded
                  Expanded(
                    child: widget.state._buildTabContent(
                      context,
                      song,
                      activeTab,
                      libraryProvider,
                      audioProvider,
                      cfg,
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Seeker & Control Area
            if (isPlayingThisSong) ...[
              // Seeker
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$curMin:$curSec',
                          style: TextStyle(fontSize: 11, color: cfg.textSub),
                        ),
                        Text(
                          '$durationMin:$durationSec',
                          style: TextStyle(fontSize: 11, color: cfg.textSub),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                        activeTrackColor: cfg.accent,
                        inactiveTrackColor: cfg.sliderTrack,
                        thumbColor: cfg.accent,
                      ),
                      child: Slider(
                        value: progress,
                        onChanged: (val) {
                          final targetMs =
                              (audioProvider.totalDuration.inMilliseconds * val)
                                  .toInt();
                          audioProvider.seek(Duration(milliseconds: targetMs));
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Control Buttons Row / Volume Slider Row
              if (showVolumeSlider)
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: 24,
                    left: 16,
                    right: 16,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          audioProvider.volume == 0
                              ? Icons.volume_off
                              : Icons.volume_up,
                          size: 20,
                          color: audioProvider.volume == 0
                              ? cfg.textSub
                              : cfg.accent,
                        ),
                        onPressed: () {
                          audioProvider.setVolume(
                            audioProvider.volume == 0 ? 0.8 : 0,
                          );
                        },
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                            activeTrackColor: cfg.accent,
                            inactiveTrackColor: cfg.sliderTrack,
                            thumbColor: cfg.accent,
                          ),
                          child: Slider(
                            value: audioProvider.volume,
                            onChanged: (val) {
                              audioProvider.setVolume(val);
                            },
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 20, color: cfg.textSub),
                        onPressed: () {
                          setState(() {
                            showVolumeSlider = false;
                          });
                        },
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: 24,
                    left: 16,
                    right: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // Play Mode Button
                      IconButton(
                        icon: Icon(
                          audioProvider.playMode == PlayMode.shuffle
                              ? Icons.shuffle
                              : audioProvider.playMode == PlayMode.single
                              ? Icons.repeat_one
                              : Icons.repeat,
                          size: 20,
                          color: audioProvider.playMode != PlayMode.list
                              ? cfg.accent
                              : cfg.textSub,
                        ),
                        onPressed: () => audioProvider.togglePlayMode(),
                      ),

                      // Skip Back
                      IconButton(
                        icon: Icon(
                          Icons.skip_previous,
                          size: 28,
                          color: cfg.textMain,
                        ),
                        onPressed: () => audioProvider.playPrevious(),
                      ),

                      // Large center play/pause circle
                      GestureDetector(
                        onTap: () => audioProvider.playPause(),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cfg.accent,
                            boxShadow: [
                              BoxShadow(
                                color: cfg.accentGlow,
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            audioProvider.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),

                      // Skip Next
                      IconButton(
                        icon: Icon(
                          Icons.skip_next,
                          size: 28,
                          color: cfg.textMain,
                        ),
                        onPressed: () => audioProvider.playNext(),
                      ),

                      // Volume button
                      IconButton(
                        icon: Icon(
                          audioProvider.volume == 0
                              ? Icons.volume_off
                              : Icons.volume_up,
                          size: 20,
                          color: audioProvider.volume == 0
                              ? cfg.textSub
                              : cfg.accent,
                        ),
                        onPressed: () {
                          setState(() {
                            showVolumeSlider = true;
                          });
                        },
                      ),
                    ],
                  ),
                ),
            ] else ...[
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}
