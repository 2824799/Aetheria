import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/services/native_audio_helper.dart';
import 'dart:io';

class DetailPane extends StatelessWidget {
  const DetailPane({super.key});

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

  Future<void> _saveSongMetadata(
    BuildContext context,
    Song song, {
    String? title,
    String? artist,
  }) async {
    final nextTitle = (title ?? song.title).trim();
    final nextArtist = (artist ?? song.artist ?? '').trim();
    if (nextTitle.isEmpty) {
      throw Exception('歌曲名称不能为空');
    }
    if (nextTitle == song.title && nextArtist == (song.artist ?? '')) {
      return;
    }

    final libraryProvider = context.read<LibraryProvider>();
    final audioProvider = context.read<AudioPlayerProvider>();
    await libraryProvider.updateSongMetadata(song.id, nextTitle, nextArtist);
    final updatedSong = libraryProvider.songs.firstWhere(
      (entry) => entry.id == song.id,
      orElse: () => song,
    );
    audioProvider.syncSongSnapshot(updatedSong);
  }

  Future<void> _setPrimaryVersion(
    BuildContext context,
    Song song,
    AudioVersion version,
    LibraryProvider libraryProvider,
    AudioPlayerProvider audioProvider,
  ) async {
    if (version.isPrimary) {
      return;
    }

    final shouldSwitchCurrentPlayback =
        audioProvider.playingSong?.id == song.id &&
        audioProvider.playingVersion?.id != version.id;
    final position = audioProvider.currentPosition;
    final startPaused = !audioProvider.isPlaying;

    await libraryProvider.updateVersionStatus(version.id, true, true);

    if (!shouldSwitchCurrentPlayback) {
      return;
    }

    final updatedSong = libraryProvider.songs.firstWhere(
      (entry) => entry.id == song.id,
      orElse: () => song,
    );
    final updatedVersion = updatedSong.versions.firstWhere(
      (entry) => entry.id == version.id,
      orElse: () => version,
    );

    await audioProvider.switchToVersion(
      updatedSong,
      updatedVersion,
      libraryProvider.libraryPath,
      audioServerPort: libraryProvider.audioServerPort,
      startPosition: position,
      startPaused: startPaused,
    );
  }

  Future<void> _linkNewVersion(
    BuildContext context,
    Song song,
    LibraryProvider provider,
  ) async {
    var loaderShown = false;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'flac', 'm4a', 'ogg', 'aac'],
      );

      if (result == null || result.files.single.path == null) return;
      final path = result.files.single.path!;
      if (!context.mounted) {
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );
      loaderShown = true;

      await provider.importAudioVersionForSong(song.id, path);
      if (!context.mounted) {
        return;
      }

      if (loaderShown) {
        Navigator.of(context).pop(); // pop progress indicator
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('成功关联新音源版本')));
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      if (loaderShown) {
        Navigator.of(context).pop(); // pop loader if failed
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('关联失败: $e')));
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioPlayerProvider>();
    final libraryProvider = context.watch<LibraryProvider>();
    final themeProvider = context.watch<UIThemeProvider>();
    final cfg = themeProvider.currentTheme;

    final song = libraryProvider.songs.firstWhere(
      (s) => s.id == audioProvider.activeSong?.id,
      orElse: () =>
          audioProvider.activeSong ??
          Song(
            id: '',
            title: '',
            rating: 0,
            createdAt: '',
            versions: [],
            tags: [],
          ),
    );

    if (song.id.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            color: cfg.bgPanel.withOpacity(0.88),
            border: Border(
              left: BorderSide(color: cfg.border.withOpacity(0.9)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.26),
                blurRadius: 42,
                offset: const Offset(-14, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              // Close button
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: Icon(Icons.close, color: cfg.textSub),
                  onPressed: () => audioProvider.setDetailOpen(false),
                ),
              ),

              // Header (Artwork Cover placeholder, Title, Artist)
              Container(
                width: 130,
                height: 130,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [Colors.white.withOpacity(0.06), cfg.border],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: cfg.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(Icons.music_note, size: 48, color: cfg.accent),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _EditableMetadataText(
                  value: song.title,
                  emptyText: '未命名歌曲',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: cfg.textMain,
                    fontFamily: 'Outfit',
                  ),
                  cfg: cfg,
                  onSave: (value) =>
                      _saveSongMetadata(context, song, title: value),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: _EditableMetadataText(
                  value: song.artist ?? '',
                  emptyText: '未知歌手',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: cfg.textSub,
                    fontFamily: 'Outfit',
                  ),
                  cfg: cfg,
                  onSave: (value) =>
                      _saveSongMetadata(context, song, artist: value),
                ),
              ),
              const SizedBox(height: 16),

              // Tabs (Versions, Tags, Lyrics)
              Row(
                children: [
                  _buildTab(context, '音源版本', 'versions', audioProvider, cfg),
                  _buildTab(context, '标签管理', 'tags', audioProvider, cfg),
                  _buildTab(context, '歌词', 'lyrics', audioProvider, cfg),
                ],
              ),
              Divider(height: 1, color: cfg.border),

              // Content Area
              Expanded(
                child: _buildContent(
                  context,
                  song,
                  audioProvider,
                  libraryProvider,
                  cfg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(
    BuildContext context,
    String title,
    String tabId,
    AudioPlayerProvider provider,
    AppThemeConfig cfg,
  ) {
    final isActive = provider.activeTab == tabId;
    return Expanded(
      child: InkWell(
        onTap: () => provider.setActiveTab(tabId),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? cfg.accent : Colors.transparent,
                width: 2.0,
              ),
            ),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? cfg.textMain : cfg.textSub,
              fontFamily: 'Outfit',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    Song song,
    AudioPlayerProvider audioProvider,
    LibraryProvider libraryProvider,
    AppThemeConfig cfg,
  ) {
    if (audioProvider.activeTab == 'versions') {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              '“可用于播放”决定这个文件是否参与播放选择；“默认播放版本”是在播放这首歌时优先使用的音源。',
              style: TextStyle(color: cfg.textSub, fontSize: 10, height: 1.5),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              itemCount: song.versions.length,
              itemBuilder: (context, index) {
                final v = song.versions[index];

                final durationMin = (v.duration / 60).floor();
                final durationSec = (v.duration % 60)
                    .round()
                    .toString()
                    .padLeft(2, '0');

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: Colors.white.withOpacity(0.04),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: cfg.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Filename
                        Text(
                          v.originalName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: cfg.textMain,
                            fontFamily: 'Outfit',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),

                        // Technical specs
                        Text(
                          '${v.format?.toUpperCase() ?? "未知"} | ${(v.bitrate ?? 0) ~/ 1000}kbps | ${v.sampleRate != null ? (v.sampleRate! / 1000).toStringAsFixed(1) : "未知"}kHz | $durationMin:$durationSec | ${_formatFileSize(v.fileSize.toInt())}',
                          style: TextStyle(
                            fontSize: 10,
                            color: cfg.textSub,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (v.metadataScanned
                                          ? const Color(0xFF10B981)
                                          : cfg.textSub)
                                      .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              v.metadataScanned ? '已完整扫描' : '待完整扫描',
                              style: TextStyle(
                                color: v.metadataScanned
                                    ? const Color(0xFF10B981)
                                    : cfg.textSub,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Tooltip(
                              message: '关闭后，这个版本不会被自动选来播放；已在播放时不会立刻中断。',
                              child: InkWell(
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
                                      size: 16,
                                      color: v.isEnabled
                                          ? cfg.accent
                                          : cfg.textSub,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '可用于播放',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: cfg.textMain,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Tooltip(
                              message: '播放这首歌时优先使用的版本；若正在播放，会按当前进度切到新版本。',
                              child: InkWell(
                                onTap: () => _setPrimaryVersion(
                                  context,
                                  song,
                                  v,
                                  libraryProvider,
                                  audioProvider,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      v.isPrimary
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      size: 16,
                                      color: v.isPrimary
                                          ? cfg.accent
                                          : cfg.textSub,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '默认播放版本',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: cfg.textMain,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 6),

                        // Export and Delete buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              onPressed: () => _exportVersion(context, v),
                              icon: Icon(
                                Icons.download,
                                size: 13,
                                color: cfg.textSub,
                              ),
                              label: Text(
                                '导出物理文件',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cfg.textSub,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            if (song.versions.length > 1)
                              TextButton.icon(
                                onPressed: () async {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  try {
                                    await libraryProvider.deleteAudioVersion(
                                      v.id,
                                    );
                                    if (!context.mounted) {
                                      return;
                                    }
                                    messenger.showSnackBar(
                                      const SnackBar(content: Text('音频版本已删除')),
                                    );
                                  } catch (e) {
                                    if (!context.mounted) {
                                      return;
                                    }
                                    messenger.showSnackBar(
                                      SnackBar(content: Text('删除失败: $e')),
                                    );
                                  }
                                },
                                icon: const Icon(
                                  Icons.delete,
                                  size: 13,
                                  color: Colors.redAccent,
                                ),
                                label: const Text(
                                  '删除版本',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.redAccent,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Link New Version button
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 38,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _linkNewVersion(context, song, libraryProvider),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('关联新的音源版本', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cfg.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (audioProvider.activeTab == 'tags') {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: libraryProvider.tags.length,
        itemBuilder: (context, index) {
          final tag = libraryProvider.tags[index];
          final isBound = song.tags.any((t) => t.id == tag.id);
          final tagColor = tag.color != null
              ? _parseHexColor(tag.color!, cfg.textSub)
              : cfg.textSub;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () async {
                await libraryProvider.tagSong(song.id, tag.id, !isBound);
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cfg.border.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isBound ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 16,
                      color: isBound ? cfg.accent : cfg.textSub,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: tagColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '[${tag.category ?? "自定义"}] ${tag.name}',
                      style: TextStyle(
                        color: tagColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    if (audioProvider.activeTab == 'lyrics') {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Text(
          song.lyrics ?? '暂无歌词',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cfg.textMain,
            height: 1.8,
            fontSize: 13,
            fontFamily: 'Outfit',
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _EditableMetadataText extends StatefulWidget {
  const _EditableMetadataText({
    required this.value,
    required this.emptyText,
    required this.style,
    required this.cfg,
    required this.onSave,
    this.textAlign = TextAlign.left,
  });

  final String value;
  final String emptyText;
  final TextStyle style;
  final AppThemeConfig cfg;
  final TextAlign textAlign;
  final Future<void> Function(String value) onSave;

  @override
  State<_EditableMetadataText> createState() => _EditableMetadataTextState();
}

class _EditableMetadataTextState extends State<_EditableMetadataText> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isHovered = false;
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _EditableMetadataText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (_isEditing && !_focusNode.hasFocus && !_isSaving) {
      _commit();
    }
  }

  void _startEditing() {
    if (_isEditing) {
      return;
    }
    setState(() {
      _isEditing = true;
      _controller.text = widget.value;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _cancel() {
    _controller.text = widget.value;
    setState(() {
      _isEditing = false;
    });
    _focusNode.unfocus();
  }

  Future<void> _commit() async {
    if (_isSaving) {
      return;
    }
    final nextValue = _controller.text.trim();
    setState(() {
      _isSaving = true;
    });
    try {
      await widget.onSave(nextValue);
      if (!mounted) {
        return;
      }
      setState(() {
        _isEditing = false;
      });
      _focusNode.unfocus();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      _controller.text = widget.value;
      setState(() {
        _isEditing = false;
      });
      _focusNode.unfocus();
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    final showEditFrame = _isHovered || _isEditing;
    final displayValue = widget.value.trim().isEmpty
        ? widget.emptyText
        : widget.value.trim();

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() {
        _isHovered = true;
      }),
      onExit: (_) => setState(() {
        _isHovered = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _startEditing,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: showEditFrame
                ? cfg.bgHover.withOpacity(0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: showEditFrame
                  ? cfg.accent.withOpacity(0.34)
                  : Colors.transparent,
            ),
          ),
          child: _isEditing
              ? Focus(
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) {
                      return KeyEventResult.ignored;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.escape) {
                      _cancel();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textAlign: widget.textAlign,
                    maxLines: 1,
                    enabled: !_isSaving,
                    onSubmitted: (_) => _commit(),
                    style: widget.style,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: widget.textAlign == TextAlign.center
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        displayValue,
                        textAlign: widget.textAlign,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: widget.style,
                      ),
                    ),
                    if (showEditFrame) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.edit,
                        size: 12,
                        color: cfg.textSub.withOpacity(0.8),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
