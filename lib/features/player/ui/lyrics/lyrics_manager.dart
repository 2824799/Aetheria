import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_progress.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/player/ui/lyrics/lyrics_manual_dialog.dart';
import 'package:aetheria/features/player/ui/lyrics/lyrics_preview_dialog.dart';
import 'package:aetheria/features/player/ui/lyrics/lyrics_shared.dart';
import 'package:aetheria/services/lyric_search_service.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/src/rust/models/song.dart';

class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.song,
    required this.audioVersion,
    required this.cfg,
    this.compact = false,
  });

  final Song song;
  final AudioVersion? audioVersion;
  final AppThemeConfig cfg;
  final bool compact;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}


class _LyricsPanelState extends State<LyricsPanel> {
  SavedLyric? _savedLyric;
  List<LyricSearchCandidate> _candidates = const <LyricSearchCandidate>[];
  bool _loadingSaved = false;
  bool _searching = false;
  String? _error;
  String? _lastLoadKey;

  String get _loadKey => '${widget.song.id}|${widget.audioVersion?.id ?? ''}';

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedLyric());
  }

  @override
  void didUpdateWidget(covariant LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.audioVersion?.id != widget.audioVersion?.id) {
      _candidates = const <LyricSearchCandidate>[];
      _error = null;
      unawaited(_loadSavedLyric());
    }
  }

  Future<void> _loadSavedLyric() async {
    final key = _loadKey;
    if (widget.song.id.isEmpty || key == _lastLoadKey && _loadingSaved) {
      return;
    }
    _lastLoadKey = key;
    setState(() {
      _loadingSaved = true;
      _error = null;
    });

    try {
      final lyric = await music.getSelectedLyric(
        songId: widget.song.id,
        audioVersionId: widget.audioVersion?.id,
      );
      if (!mounted || key != _loadKey) {
        return;
      }
      setState(() {
        _savedLyric = lyric;
        _loadingSaved = false;
      });
      if (lyric != null) {
        context.read<LibraryProvider>().markSongHasLyrics(widget.song.id);
      }
    } catch (e) {
      if (!mounted || key != _loadKey) {
        return;
      }
      setState(() {
        _loadingSaved = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _searchLyrics() async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await LyricSearchService.search(
        widget.song,
        widget.audioVersion,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _candidates = results;
        _searching = false;
        if (results.isEmpty) {
          _error = '没有找到可用歌词。';
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _searching = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openCandidatePreview(LyricSearchCandidate candidate) async {
    final saved = await showAetherDialog<SavedLyric>(
      context: context,
      builder: (context) => LyricPreviewDialog(
        candidate: candidate,
        song: widget.song,
        audioVersion: widget.audioVersion,
        cfg: widget.cfg,
      ),
    );
    if (saved == null || !mounted) {
      return;
    }
    setState(() {
      _savedLyric = saved;
      _candidates = const <LyricSearchCandidate>[];
      _error = null;
    });
    context.read<LibraryProvider>().markSongHasLyrics(widget.song.id);
  }

  Future<void> _openManualEditor() async {
    final saved = await showAetherDialog<SavedLyric>(
      context: context,
      builder: (context) => ManualLyricDialog(
        song: widget.song,
        audioVersion: widget.audioVersion,
        cfg: widget.cfg,
      ),
    );
    if (saved == null || !mounted) {
      return;
    }
    setState(() {
      _savedLyric = saved;
      _candidates = const <LyricSearchCandidate>[];
      _error = null;
    });
    context.read<LibraryProvider>().markSongHasLyrics(widget.song.id);
  }

  Future<void> _setOffset(int offsetMs) async {
    final lyric = _savedLyric;
    if (lyric == null) {
      return;
    }
    try {
      final updated = await music.updateLyricOffset(
        lyricId: lyric.id,
        offsetMs: offsetMs.clamp(-1000000, 1000000),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _savedLyric = updated;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      showAetherToast(
        context,
        message: '偏移保存失败: $e',
        kind: AetherToastKind.error,
      );
    }
  }

  Future<void> _editOffset() async {
    final lyric = _savedLyric;
    if (lyric == null) {
      return;
    }
    final controller = TextEditingController(text: lyric.offsetMs.toString());
    final result = await showAetherDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AetherDialog(
          title: '歌词偏移',
          content: AetherTextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            hintText: '偏移毫秒，可为负',
            onSubmitted: (_) {
              Navigator.of(dialogContext)
                  .pop(int.tryParse(controller.text.trim()));
            },
          ),
          actions: [
            AetherButton.ghost(
              label: '取消',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            AetherButton.primary(
              label: '保存',
              onPressed: () {
                Navigator.of(dialogContext)
                    .pop(int.tryParse(controller.text.trim()));
              },
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result != null) {
      await _setOffset(result);
    }
  }

  String? get _displayContent {
    final content = _savedLyric?.content.trim();
    if (content != null && content.isNotEmpty) {
      return content;
    }
    final legacy = widget.song.lyrics?.trim();
    return legacy == null || legacy.isEmpty ? null : legacy;
  }

  int get _displayOffset => _savedLyric?.offsetMs ?? 0;

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    final content = _displayContent;
    final sourceText = _savedLyric == null
        ? '未保存到当前音源'
        : '${lyricSourceLabel(_savedLyric!.source)} · ${_savedLyric!.offsetMs}ms';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(AetherSpace.xl, widget.compact ? AetherSpace.lg - 2 : AetherSpace.lg + 2, AetherSpace.xl, AetherSpace.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.audioVersion?.originalName ?? '歌曲通用歌词',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cfg.textPrimary,
                        fontSize: widget.compact ? AetherType.bodySm : AetherType.body,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AetherSpace.xxs),
                    Text(
                      sourceText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AetherType.captionStyle(cfg.textSecondary),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: '自动查找歌词',
                child: _searching
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: Center(
                        child: AetherProgress.circular(size: 16, strokeWidth: 2),
                      ),
                    )
                  : AetherIconButton(
                      icon: Icons.travel_explore,
                      iconSize: AetherIconSize.lg,
                      color: cfg.accent,
                      tooltip: '搜索歌词',
                      onPressed: _searchLyrics,
                    ),
              ),
              Tooltip(
                message: '手动粘贴歌词',
                child: AetherIconButton(
                  icon: Icons.edit_note,
                  iconSize: AetherIconSize.xl,
                  color: cfg.textSecondary,
                  tooltip: '手动编辑歌词',
                  onPressed: _openManualEditor,
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AetherSpace.xl),
            child: Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AetherType.captionStyle(cfg.warning),
            ),
          ),
        if (_candidates.isNotEmpty) _buildCandidateStrip(cfg),
        Expanded(
          child: _loadingSaved
              ? Center(
                  child: AetherProgress.circular(size: 16, strokeWidth: 2),
                )
              : content == null
              ? _buildEmptyState(cfg)
              : _buildCurrentLyricPreview(cfg, content),
        ),
        _buildOffsetControls(cfg),
      ],
    );
  }

  Widget _buildCurrentLyricPreview(AppThemeConfig cfg, String content) {
    final lyric = _savedLyric;
    final previewText = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .join('\n');

    return Padding(
      padding: const EdgeInsets.fromLTRB(AetherSpace.xl, AetherSpace.md, AetherSpace.xl, AetherSpace.md),
      child: Container(
        decoration: BoxDecoration(
          color: cfg.bgHover.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AetherRadius.sm + 2),
          border: Border.all(color: cfg.borderSubtle.withValues(alpha: 0.65)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AetherSpace.lg, AetherSpace.lg - 2, AetherSpace.lg, AetherSpace.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      lyric == null
                          ? '当前歌词预览'
                          : '${lyricSourceLabel(lyric.source)} · ${lyric.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cfg.textPrimary,
                        fontSize: AetherType.body,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${_displayOffset}ms',
                    style: TextStyle(
                      color: cfg.accent,
                      fontSize: AetherType.bodySm,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AetherSpace.xs),
                  Tooltip(
                    message: '复制歌词',
                    child: AetherIconButton(
                      icon: Icons.copy_all_outlined,
                      iconSize: AetherIconSize.md,
                      color: cfg.textSecondary,
                      tooltip: '复制歌词',
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: content));
                        if (!mounted) {
                          return;
                        }
                        showAetherToast(
                          context,
                          message: '歌词已复制到剪切板',
                          kind: AetherToastKind.success,
                        );
                      },
                    )
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cfg.borderSubtle.withValues(alpha: 0.55)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AetherSpace.lg),
                child: SelectableText(
                  previewText.isEmpty ? '暂无可预览内容' : previewText,
                  style: TextStyle(
                    color: cfg.textSecondary,
                    fontSize: widget.compact ? AetherType.bodySm : AetherType.body,
                    height: 1.65,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCandidateStrip(AppThemeConfig cfg) {
    return Container(
      height: widget.compact ? 174 : 220,
      margin: const EdgeInsets.fromLTRB(AetherSpace.xl, AetherSpace.sm, AetherSpace.xl, AetherSpace.md),
      decoration: BoxDecoration(
        color: cfg.bgHover.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AetherRadius.sm + 2),
        border: Border.all(color: cfg.borderSubtle.withValues(alpha: 0.65)),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: AetherSpace.sm),
        itemCount: _candidates.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: cfg.borderSubtle.withValues(alpha: 0.45)),
        itemBuilder: (context, index) {
          final candidate = _candidates[index];
          return AetherPressable(
            onTap: () => _openCandidatePreview(candidate),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AetherSpace.lg - 2, vertical: AetherSpace.sm + 1),
              child: Row(
                children: [
                  Container(
                    width: 72,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: AetherSpace.xs - 1),
                    decoration: BoxDecoration(
                      color: cfg.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AetherRadius.xs + 1),
                    ),
                    child: Text(
                      candidate.sourceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cfg.accent,
                        fontSize: AetherType.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AetherSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          candidate.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cfg.textPrimary,
                            fontSize: AetherType.bodySm,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            candidate.durationSec == null
                                ? null
                                : _formatDuration(candidate.durationSec!),
                            candidate.artist,
                            candidate.album,
                          ].whereType<String>().join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AetherType.captionStyle(cfg.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: cfg.textSecondary),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(AppThemeConfig cfg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AetherSpace.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lyrics_outlined, color: cfg.textSecondary, size: 30),
            const SizedBox(height: AetherSpace.lg - 2),
            Text(
              '暂无歌词',
              style: TextStyle(
                color: cfg.textPrimary,
                fontSize: AetherType.titleSm,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AetherSpace.lg),
            AetherButton.primary(
              label: '网络中自动查找',
              icon: Icons.travel_explore,
              onPressed: _searching ? null : _searchLyrics,
              loading: _searching,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffsetControls(AppThemeConfig cfg) {
    final enabled = _savedLyric != null;
    return Container(
      padding: EdgeInsets.fromLTRB(AetherSpace.lg + 2, AetherSpace.md, AetherSpace.lg + 2, widget.compact ? AetherSpace.lg - 2 : AetherSpace.lg + 2),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cfg.borderSubtle.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        children: [
          Text(
            '偏移',
            style: TextStyle(
              color: enabled ? cfg.textPrimary : cfg.textSecondary,
              fontSize: AetherType.bodySm,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: AetherSpace.sm),
          Tooltip(
            message: '-500ms',
            child: AetherIconButton(
              icon: Icons.remove,
              size: 30,
              iconSize: AetherIconSize.sm,
              tooltip: '-500ms',
              onPressed: enabled ? () => _setOffset(_displayOffset - 500) : null,
            ),
          ),
          AetherPressable(
            onTap: enabled ? _editOffset : null,
            borderRadius: BorderRadius.circular(AetherRadius.sm),
            child: Container(
              width: 76,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cfg.bgHover.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AetherRadius.sm),
                border: Border.all(color: cfg.borderSubtle.withValues(alpha: 0.7)),
              ),
              child: Text(
                '${_displayOffset}ms',
                style: TextStyle(
                  color: enabled ? cfg.textPrimary : cfg.textSecondary,
                  fontSize: AetherType.bodySm,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Tooltip(
            message: '+500ms',
            child: AetherIconButton(
              icon: Icons.add,
              size: 30,
              iconSize: AetherIconSize.sm,
              tooltip: '+500ms',
              onPressed: enabled ? () => _setOffset(_displayOffset + 500) : null,
            ),
          ),
          const Spacer(),
          AetherButton.ghost(
            label: '重置',
            size: AetherButtonSize.sm,
            onPressed: enabled ? () => _setOffset(0) : null,
          ),
        ],
      ),
    );
  }

  static String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = (seconds % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }
}


