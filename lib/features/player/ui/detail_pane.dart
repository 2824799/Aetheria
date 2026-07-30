import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_empty_state.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_tabs.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/player/ui/lyrics_panel.dart';
import 'package:aetheria/features/player/ui/song_cover_art.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/services/native_audio_helper.dart';
import 'dart:io';
import 'package:aetheria/core/widgets/aether_surface.dart';

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

  String _formatLoudness(double? loudness) {
    if (loudness == null) {
      return '响度: 待扫描';
    }
    return '响度: ${loudness.toStringAsFixed(1)} LUFS';
  }

  Future<bool> _confirmDeleteVersion(
    BuildContext context,
    AudioVersion version,
  ) async {
    return showAetherConfirmDialog(
      context: context,
      title: '删除音源版本？',
      message: '确定要删除音源版本“${version.originalName}”吗？这会同时删除对应的本地音频文件。',
      confirmLabel: '删除版本',
      dangerous: true,
    );
  }

  Future<T?> _withBlockingLoader<T>(
    BuildContext context,
    Future<T> Function() task,
  ) async {
    var opened = false;
    try {
      showAetherDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AetherDialog(
          content: SizedBox(
            height: 96,
            child: AetherLoading(message: '处理中…'),
          ),
        ),
      );
      opened = true;
      return await task();
    } finally {
      if (opened && context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  AudioVersion? _displayVersionForSong(
    Song song,
    AudioPlayerProvider audioProvider,
  ) {
    final playingVersion = audioProvider.playingVersion;
    if (audioProvider.playingSong?.id == song.id && playingVersion != null) {
      return playingVersion;
    }
    for (final version in song.versions) {
      if (version.isPrimary) {
        return version;
      }
    }
    return song.versions.isNotEmpty ? song.versions.first : null;
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

    await libraryProvider.setPrimaryVersion(version.id);

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

      await _withBlockingLoader<void>(context, () async {
        await provider.importAudioVersionForSong(song.id, path);
      });
      if (!context.mounted) {
        return;
      }
      showAetherToast(
        context,
        message: '成功关联新音源版本',
        kind: AetherToastKind.success,
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      showAetherToast(
        context,
        message: '关联失败: $e',
        kind: AetherToastKind.error,
      );
    }
  }

  Future<void> _exportVersion(
    BuildContext context,
    AudioVersion version,
  ) async {
    try {
      if (Platform.isAndroid) {
        final libraryPath = context.read<LibraryProvider>().libraryPath;
        final srcPath = '$libraryPath/${version.filepath}'.replaceAll(
          '\\',
          '/',
        );
        await _withBlockingLoader<void>(context, () async {
          await NativeAudioHelper.saveToDownloads(
            srcPath,
            version.originalName,
          );
        });
        if (!context.mounted) return;
        showAetherToast(
          context,
          message: '已成功导出至系统 Downloads/Aetheria 文件夹！',
          kind: AetherToastKind.success,
        );
      } else {
        final destPath = await FilePicker.platform.saveFile(
          fileName: version.originalName,
          dialogTitle: '选择保存音频的位置',
        );
        if (destPath == null) return;
        if (!context.mounted) return;
        await _withBlockingLoader<void>(context, () async {
          await music.exportAudioFile(
            versionId: version.id,
            destPath: destPath,
          );
        });
        if (!context.mounted) return;
        showAetherToast(
          context,
          message: '音频文件导出还原成功！',
          kind: AetherToastKind.success,
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      showAetherToast(
        context,
        message: '导出失败: $e',
        kind: AetherToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioPlayerProvider>();
    final libraryProvider = context.watch<LibraryProvider>();
    context.watch<UIThemeProvider>();
    final cfg = context.tokens;

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
      borderRadius: const BorderRadius.horizontal(
        left: Radius.circular(AetherRadius.xxl),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: cfg.glassBlurDefault,
          sigmaY: cfg.glassBlurDefault,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: cfg.bg1.withValues(alpha: 0.92),
            border: Border(
              left: BorderSide(color: cfg.borderSubtle),
            ),
            boxShadow: [
              BoxShadow(
                color: cfg.scrim.withValues(alpha: 0.26),
                blurRadius: 42,
                offset: const Offset(-14, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: AetherSpace.sm,
                    right: AetherSpace.sm,
                  ),
                  child: AetherIconButton(
                    icon: Icons.close_rounded,
                    tooltip: '关闭详情',
                    onPressed: () => audioProvider.setDetailOpen(false),
                    color: cfg.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: _buildContent(
                  context,
                  song,
                  audioProvider,
                  libraryProvider,
                  cfg,
                ),
              ),
              Divider(height: 1, color: cfg.borderSubtle),
              AetherTabBar(
                value: audioProvider.activeTab,
                onChanged: audioProvider.setActiveTab,
                tabs: const [
                  AetherTabItem(id: 'lyrics', label: '滚动歌词'),
                  AetherTabItem(id: 'lyric_manager', label: '歌词管理'),
                  AetherTabItem(id: 'tags', label: '标签管理'),
                  AetherTabItem(id: 'versions', label: '音源版本'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVersionHeader(
    BuildContext context,
    Song song,
    AppThemeConfig cfg,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AetherSpace.xxl - 2, AetherSpace.xxs, AetherSpace.xxl - 2, AetherSpace.md),
      child: Column(
        children: [
          SongCoverArt(song: song, cfg: cfg, size: 124, borderRadius: AetherRadius.xl),
          const SizedBox(height: AetherSpace.lg + 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AetherSpace.sm),
            child: _EditableMetadataText(
              value: song.title,
              emptyText: '未命名歌曲',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AetherType.title,
                fontWeight: FontWeight.bold,
                color: cfg.textPrimary,
              ),
              cfg: cfg,
              onSave: (value) => _saveSongMetadata(context, song, title: value),
            ),
          ),
          const SizedBox(height: AetherSpace.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AetherSpace.lg + 2),
            child: _EditableMetadataText(
              value: song.artist ?? '',
              emptyText: '未知歌手',
              textAlign: TextAlign.center,
              style: AetherType.bodySmStyle(cfg.textSecondary),
              cfg: cfg,
              onSave: (value) =>
                  _saveSongMetadata(context, song, artist: value),
            ),
          ),
        ],
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
    if (audioProvider.activeTab == 'lyrics') {
      return LyricsDisplayPanel(
        song: song,
        audioVersion: _displayVersionForSong(song, audioProvider),
        cfg: cfg,
      );
    }

    if (audioProvider.activeTab == 'lyric_manager') {
      return LyricsPanel(
        song: song,
        audioVersion: _displayVersionForSong(song, audioProvider),
        cfg: cfg,
      );
    }

    if (audioProvider.activeTab == 'versions') {
      return Column(
        children: [
          _buildVersionHeader(context, song, cfg),
          Padding(
            padding: const EdgeInsets.fromLTRB(AetherSpace.xl, AetherSpace.lg, AetherSpace.xl, 0),
            child: Text(
              '“默认播放版本”是在播放这首歌时优先使用的音源；若正在播放，会按当前进度切到新版本。',
              style: AetherType.captionStyle(cfg.textSecondary).copyWith(height: 1.5),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(AetherSpace.xl, AetherSpace.lg - 2, AetherSpace.xl, AetherSpace.xl),
              itemCount: song.versions.length,
              itemBuilder: (context, index) {
                final v = song.versions[index];

                final durationMin = (v.duration / 60).floor();
                final durationSec = (v.duration % 60)
                    .round()
                    .toString()
                    .padLeft(2, '0');

                return AetherSurface(
                  margin: const EdgeInsets.only(bottom: AetherSpace.lg),
                  level: AetherSurfaceLevel.panel,
                  color: cfg.bgHover,
                  borderRadius: BorderRadius.circular(AetherRadius.md),
                  padding: const EdgeInsets.all(AetherSpace.lg),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Filename
                        Text(
                          v.originalName,
                          style: AetherType.titleSmStyle(cfg.textPrimary).copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AetherSpace.sm),

                        // Technical specs
                        Text(
                          '${v.format?.toUpperCase() ?? "未知"} | ${(v.bitrate ?? 0) ~/ 1000}kbps | ${v.sampleRate != null ? (v.sampleRate! / 1000).toStringAsFixed(1) : "未知"}kHz | $durationMin:$durationSec | ${_formatFileSize(v.fileSize.toInt())} | ${_formatLoudness(v.loudness)}',
                          style: AetherType.captionStyle(cfg.textSecondary),
                        ),
                        const SizedBox(height: AetherSpace.sm),
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
                                          ? cfg.success
                                          : cfg.textSecondary)
                                      .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AetherRadius.sm),
                            ),
                            child: Text(
                              v.metadataScanned ? '已完整扫描' : '待完整扫描',
                              style: TextStyle(
                                color: v.metadataScanned
                                    ? cfg.success
                                    : cfg.textSecondary,
                                fontSize: AetherType.caption,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AetherSpace.lg - 2),

                        Align(
                          alignment: Alignment.centerLeft,
                          child: Tooltip(
                            message: '播放这首歌时优先使用的版本；若正在播放，会按当前进度切到新版本。',
                            child: AetherPressable(
                              onTap: () => _setPrimaryVersion(
                                context,
                                song,
                                v,
                                libraryProvider,
                                audioProvider,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    v.isPrimary
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: AetherIconSize.md,
                                    color: v.isPrimary
                                        ? cfg.accent
                                        : cfg.textSecondary,
                                  ),
                                  const SizedBox(width: AetherSpace.xs),
                                  Text(
                                    '默认播放版本',
                                    style: AetherType.bodySmStyle(cfg.textPrimary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AetherSpace.md),
                        const Divider(height: 1),
                        const SizedBox(height: AetherSpace.sm),

                        // Export and Delete buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            AetherButton.ghost(
                              label: '导出物理文件',
                              icon: Icons.download,
                              size: AetherButtonSize.sm,
                              onPressed: () => _exportVersion(context, v),
                            ),
                            if (song.versions.length > 1)
                              AetherButton.danger(
                                label: '删除版本',
                                icon: Icons.delete_outline_rounded,
                                size: AetherButtonSize.sm,
                                onPressed: () async {
                                  final confirmed = await _confirmDeleteVersion(
                                    context,
                                    v,
                                  );
                                  if (!confirmed) {
                                    return;
                                  }
                                  if (!context.mounted) {
                                    return;
                                  }
                                  try {
                                    await libraryProvider.deleteAudioVersion(
                                      v.id,
                                    );
                                    if (!context.mounted) {
                                      return;
                                    }
                                    showAetherToast(
                                      context,
                                      message: '音频版本已删除',
                                      kind: AetherToastKind.success,
                                    );
                                  } catch (e) {
                                    if (!context.mounted) {
                                      return;
                                    }
                                    showAetherToast(
                                      context,
                                      message: '删除失败: $e',
                                      kind: AetherToastKind.error,
                                    );
                                  }
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                );
              },
            ),
          ),

          // Link New Version button
          Padding(
            padding: const EdgeInsets.all(AetherSpace.xl),
            child: AetherButton.primary(
              label: '关联新的音源版本',
              icon: Icons.add_rounded,
              expanded: true,
              onPressed: () =>
                  _linkNewVersion(context, song, libraryProvider),
            ),
          ),
        ],
      );
    }

    if (audioProvider.activeTab == 'tags') {
      return ListView.builder(
        padding: const EdgeInsets.all(AetherSpace.xl),
        itemCount: libraryProvider.tags.length,
        itemBuilder: (context, index) {
          final tag = libraryProvider.tags[index];
          final isBound = song.tags.any((t) => t.id == tag.id);
          final tagColor = tag.color != null
              ? _parseHexColor(tag.color!, cfg.textSecondary)
              : cfg.textSecondary;

          return Padding(
            padding: const EdgeInsets.only(bottom: AetherSpace.md),
            child: AetherPressable(
              onTap: () async {
                await libraryProvider.tagSong(song.id, tag.id, !isBound);
              },
              borderRadius: BorderRadius.circular(AetherRadius.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AetherSpace.lg,
                  vertical: AetherSpace.md,
                ),
                decoration: BoxDecoration(
                  color: cfg.bgHover,
                  borderRadius: BorderRadius.circular(AetherRadius.sm),
                  border: Border.all(color: cfg.borderSubtle.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isBound ? Icons.check_box : Icons.check_box_outline_blank,
                      size: AetherIconSize.md,
                      color: isBound ? cfg.accent : cfg.textSecondary,
                    ),
                    const SizedBox(width: AetherSpace.md),
                    Container(
                      width: AetherSpace.md,
                      height: AetherSpace.md,
                      decoration: BoxDecoration(
                        color: tagColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AetherSpace.md),
                    Text(
                      '[${tag.category ?? "自定义"}] ${tag.name}',
                      style: AetherType.titleSmStyle(tagColor).copyWith(
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
      showAetherToast(context, message: '保存失败: $e', kind: AetherToastKind.error);
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
          duration: AetherMotion.duration(context, AetherMotion.press),
          padding: const EdgeInsets.symmetric(horizontal: AetherSpace.md, vertical: AetherSpace.xs),
          decoration: BoxDecoration(
            color: showEditFrame
                ? cfg.bgHover.withValues(alpha: 0.18)
                : cfg.bgHover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(AetherRadius.sm),
            border: Border.all(
              color: showEditFrame
                  ? cfg.accent.withValues(alpha: 0.34)
                  : cfg.bgHover.withValues(alpha: 0),
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
                  child: AetherTextField.plain(
                    controller: _controller,
                    focusNode: _focusNode,
                    textAlign: widget.textAlign,
                    enabled: !_isSaving,
                    onSubmitted: (_) => _commit(),
                    style: widget.style,
                    contentPadding: EdgeInsets.zero,
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
                      const SizedBox(width: AetherSpace.sm),
                      Icon(
                        Icons.edit,
                        size: AetherIconSize.xs,
                        color: cfg.textSecondary.withValues(alpha: 0.8),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
