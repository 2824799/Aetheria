import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_progress.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';
import 'package:aetheria/features/player/ui/lyrics/lyrics_manual_dialog.dart';
import 'package:aetheria/features/player/ui/lyrics/lyrics_panel_widgets.dart';
import 'package:aetheria/features/player/ui/lyrics/lyrics_preview_dialog.dart';
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
  bool _cleared = false;
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
      _cleared = false;
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
        if (lyric != null) {
          _cleared = false;
        }
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
      _cleared = false;
      _error = null;
    });
    context.read<LibraryProvider>().markSongHasLyrics(widget.song.id);
    context.read<FloatingLyricsProvider>().notifyLyricUpdated();
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
      _cleared = false;
      _error = null;
    });
    context.read<LibraryProvider>().markSongHasLyrics(widget.song.id);
    context.read<FloatingLyricsProvider>().notifyLyricUpdated();
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
      context.read<FloatingLyricsProvider>().notifyLyricUpdated();
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
              Navigator.of(
                dialogContext,
              ).pop(int.tryParse(controller.text.trim()));
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
                Navigator.of(
                  dialogContext,
                ).pop(int.tryParse(controller.text.trim()));
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

  Future<void> _clearLyrics() async {
    final confirmed = await showAetherConfirmDialog(
      context: context,
      title: '清除歌词？',
      message: '当前音源保存的歌词会被删除。',
      confirmLabel: '清除',
      dangerous: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _loadingSaved = true;
      _error = null;
    });

    try {
      final songStillHasLyrics = await music.clearLyrics(
        songId: widget.song.id,
        audioVersionId: widget.audioVersion?.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _savedLyric = null;
        _candidates = const <LyricSearchCandidate>[];
        _cleared = true;
        _loadingSaved = false;
      });
      if (!songStillHasLyrics) {
        context.read<LibraryProvider>().markSongHasNoLyrics(widget.song.id);
      }
      context.read<FloatingLyricsProvider>().notifyLyricUpdated();
      showAetherToast(
        context,
        message: '歌词已清除',
        kind: AetherToastKind.success,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingSaved = false;
        _error = e.toString();
      });
      showAetherToast(
        context,
        message: '清除歌词失败: $e',
        kind: AetherToastKind.error,
      );
    }
  }

  String? get _displayContent {
    if (_cleared) {
      return null;
    }
    final content = _savedLyric?.content.trim();
    if (content != null && content.isNotEmpty) {
      return content;
    }
    final legacy = widget.song.lyrics?.trim();
    return legacy == null || legacy.isEmpty ? null : legacy;
  }

  Future<void> _copyLyrics(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    showAetherToast(
      context,
      message: '歌词已复制',
      kind: AetherToastKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    final content = _displayContent;
    final error = _error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LyricPanelHeader(
          audioVersion: widget.audioVersion,
          savedLyric: _savedLyric,
          actions: [
            if (_searching)
              const SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: AetherProgress.circular(size: 16, strokeWidth: 2),
                ),
              )
            else
              AetherIconButton(
                icon: Icons.travel_explore_rounded,
                iconSize: AetherIconSize.lg,
                color: cfg.textSecondary,
                tooltip: '联网查找歌词',
                onPressed: _searchLyrics,
              ),
            AetherIconButton(
              icon: Icons.edit_outlined,
              iconSize: AetherIconSize.lg,
              color: cfg.textSecondary,
              tooltip: '手动粘贴或编辑歌词',
              onPressed: _openManualEditor,
            ),
            if (content != null) ...[
              AetherIconButton(
                icon: Icons.copy_rounded,
                iconSize: AetherIconSize.lg,
                color: cfg.textSecondary,
                tooltip: '复制歌词',
                onPressed: () => _copyLyrics(content),
              ),
              AetherIconButton(
                icon: Icons.delete_outline_rounded,
                iconSize: AetherIconSize.lg,
                color: cfg.danger,
                tooltip: '清除歌词',
                onPressed: _clearLyrics,
              ),
            ],
          ],
        ),
        if (error != null) LyricPanelError(error),
        if (_candidates.isNotEmpty)
          LyricCandidateList(
            candidates: _candidates,
            height: widget.compact ? 174 : 220,
            onSelected: _openCandidatePreview,
          ),
        Expanded(
          child: _loadingSaved
              ? const LyricPanelLoading()
              : content == null
              ? LyricPanelEmptyState(
                  actionLabel: '联网查找歌词',
                  actionIcon: Icons.travel_explore_rounded,
                  loading: _searching,
                  onAction: _searchLyrics,
                )
              : SavedLyricText(content: content),
        ),
        LyricOffsetBar(
          offsetMs: _savedLyric?.offsetMs ?? 0,
          enabled: _savedLyric != null,
          onChanged: _setOffset,
          onEdit: _editOffset,
        ),
      ],
    );
  }
}
