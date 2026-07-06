import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/services/lyric_search_service.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/src/rust/models/song.dart';

String _sourceLabel(String source) {
  return switch (source) {
    'local_embedded' => '音频内嵌',
    'local_lrc' => '本地 LRC',
    'legacy_song' => '旧版歌曲歌词',
    'lrclib' => 'LRCLIB',
    'netease' => '网易云音乐',
    'qq' => 'QQ音乐',
    'kugou' => '酷狗音乐',
    'manual' => '手动保存',
    _ => source,
  };
}

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

class LyricsDisplayPanel extends StatefulWidget {
  const LyricsDisplayPanel({
    super.key,
    required this.song,
    required this.audioVersion,
    required this.cfg,
    this.compact = false,
    this.onOpenManager,
  });

  final Song song;
  final AudioVersion? audioVersion;
  final AppThemeConfig cfg;
  final bool compact;
  final VoidCallback? onOpenManager;

  @override
  State<LyricsDisplayPanel> createState() => _LyricsDisplayPanelState();
}

class _LyricsDisplayPanelState extends State<LyricsDisplayPanel> {
  SavedLyric? _savedLyric;
  bool _loading = false;
  String? _error;
  String? _lastLoadKey;

  String get _loadKey => '${widget.song.id}|${widget.audioVersion?.id ?? ''}';

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedLyric());
  }

  @override
  void didUpdateWidget(covariant LyricsDisplayPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.audioVersion?.id != widget.audioVersion?.id) {
      unawaited(_loadSavedLyric());
    }
  }

  Future<void> _loadSavedLyric() async {
    final key = _loadKey;
    if (widget.song.id.isEmpty || key == _lastLoadKey && _loading) {
      return;
    }
    _lastLoadKey = key;
    setState(() {
      _loading = true;
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
        _loading = false;
      });
    } catch (e) {
      if (!mounted || key != _loadKey) {
        return;
      }
      setState(() {
        _loading = false;
        _error = e.toString();
      });
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

  String? get _displayTranslation {
    final translation = _savedLyric?.translation?.trim();
    return translation == null || translation.isEmpty ? null : translation;
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    final content = _displayContent;
    final sourceText = _savedLyric == null
        ? '未保存到当前音源'
        : '${_sourceLabel(_savedLyric!.source)} · ${_savedLyric!.offsetMs}ms';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, widget.compact ? 8 : 12, 8, 4),
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
                        color: cfg.textMain,
                        fontSize: widget.compact ? 11 : 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sourceText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cfg.textSub, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: '歌词管理',
                child: IconButton(
                  onPressed: () => _openManager(context),
                  icon: Icon(Icons.manage_search, size: 19, color: cfg.textSub),
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 10),
            ),
          ),
        Expanded(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cfg.accent,
                  ),
                )
              : content == null
              ? _buildDisplayEmptyState(context, cfg)
              : SyncedLyricsView(
                  content: content,
                  translation: _displayTranslation,
                  offsetMs: _savedLyric?.offsetMs ?? 0,
                  cfg: cfg,
                  compact: widget.compact,
                ),
        ),
      ],
    );
  }

  Widget _buildDisplayEmptyState(BuildContext context, AppThemeConfig cfg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lyrics_outlined, color: cfg.textSub, size: 30),
            const SizedBox(height: 10),
            Text(
              '暂无歌词',
              style: TextStyle(
                color: cfg.textMain,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _openManager(context),
              icon: const Icon(Icons.manage_search, size: 16),
              label: const Text('打开歌词管理'),
              style: ElevatedButton.styleFrom(
                backgroundColor: cfg.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openManager(BuildContext context) {
    final callback = widget.onOpenManager;
    if (callback != null) {
      callback();
      return;
    }
    context.read<AudioPlayerProvider>().setActiveTab('lyric_manager');
  }
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
    final saved = await showDialog<SavedLyric>(
      context: context,
      builder: (context) => _LyricPreviewDialog(
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
  }

  Future<void> _openManualEditor() async {
    final saved = await showDialog<SavedLyric>(
      context: context,
      builder: (context) => _ManualLyricDialog(
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
  }

  Future<void> _setOffset(int offsetMs) async {
    final lyric = _savedLyric;
    if (lyric == null) {
      return;
    }
    try {
      final updated = await music.updateLyricOffset(
        lyricId: lyric.id,
        offsetMs: offsetMs.clamp(-30000, 30000),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('偏移保存失败: $e')));
    }
  }

  Future<void> _editOffset() async {
    final lyric = _savedLyric;
    if (lyric == null) {
      return;
    }
    final controller = TextEditingController(text: lyric.offsetMs.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('歌词偏移'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(suffixText: 'ms'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(int.tryParse(controller.text.trim()));
            },
            child: const Text('保存'),
          ),
        ],
      ),
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
        : '${_sourceLabel(_savedLyric!.source)} · ${_savedLyric!.offsetMs}ms';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, widget.compact ? 10 : 14, 16, 8),
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
                        color: cfg.textMain,
                        fontSize: widget.compact ? 11 : 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sourceText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cfg.textSub, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: '自动查找歌词',
                child: IconButton(
                  onPressed: _searching ? null : _searchLyrics,
                  icon: _searching
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cfg.accent,
                          ),
                        )
                      : Icon(Icons.travel_explore, size: 18, color: cfg.accent),
                ),
              ),
              Tooltip(
                message: '手动粘贴歌词',
                child: IconButton(
                  onPressed: _openManualEditor,
                  icon: Icon(Icons.edit_note, size: 20, color: cfg.textSub),
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 10),
            ),
          ),
        if (_candidates.isNotEmpty) _buildCandidateStrip(cfg),
        Expanded(
          child: _loadingSaved
              ? Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cfg.accent,
                  ),
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
    final previewLines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(18)
        .join('\n');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: cfg.bgHover.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cfg.border.withValues(alpha: 0.65)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      lyric == null
                          ? '当前歌词预览'
                          : '${_sourceLabel(lyric.source)} · ${lyric.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cfg.textMain,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${_displayOffset}ms',
                    style: TextStyle(
                      color: cfg.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cfg.border.withValues(alpha: 0.55)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  previewLines.isEmpty ? '暂无可预览内容' : previewLines,
                  style: TextStyle(
                    color: cfg.textSub,
                    fontSize: widget.compact ? 11 : 12,
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
      height: widget.compact ? 118 : 132,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      decoration: BoxDecoration(
        color: cfg.bgHover.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cfg.border.withValues(alpha: 0.65)),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _candidates.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: cfg.border.withValues(alpha: 0.45)),
        itemBuilder: (context, index) {
          final candidate = _candidates[index];
          return InkWell(
            onTap: () => _openCandidatePreview(candidate),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Container(
                    width: 72,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: cfg.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      candidate.sourceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cfg.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
                            color: cfg.textMain,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            candidate.artist,
                            candidate.album,
                            candidate.durationSec == null
                                ? null
                                : _formatDuration(candidate.durationSec!),
                          ].whereType<String>().join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cfg.textSub, fontSize: 9.5),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: cfg.textSub),
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
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lyrics_outlined, color: cfg.textSub, size: 30),
            const SizedBox(height: 10),
            Text(
              '暂无歌词',
              style: TextStyle(
                color: cfg.textMain,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _searching ? null : _searchLyrics,
              icon: const Icon(Icons.travel_explore, size: 16),
              label: const Text('网络中自动查找'),
              style: ElevatedButton.styleFrom(
                backgroundColor: cfg.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffsetControls(AppThemeConfig cfg) {
    final enabled = _savedLyric != null;
    return Container(
      padding: EdgeInsets.fromLTRB(14, 8, 14, widget.compact ? 10 : 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cfg.border.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        children: [
          Text(
            '偏移',
            style: TextStyle(
              color: enabled ? cfg.textMain : cfg.textSub,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: '-500ms',
            child: IconButton(
              onPressed: enabled
                  ? () => _setOffset(_displayOffset - 500)
                  : null,
              icon: const Icon(Icons.remove, size: 15),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            ),
          ),
          InkWell(
            onTap: enabled ? _editOffset : null,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 76,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cfg.bgHover.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: cfg.border.withValues(alpha: 0.7)),
              ),
              child: Text(
                '${_displayOffset}ms',
                style: TextStyle(
                  color: enabled ? cfg.textMain : cfg.textSub,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Tooltip(
            message: '+500ms',
            child: IconButton(
              onPressed: enabled
                  ? () => _setOffset(_displayOffset + 500)
                  : null,
              icon: const Icon(Icons.add, size: 15),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: enabled ? () => _setOffset(0) : null,
            child: const Text('重置'),
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

class _LyricPreviewDialog extends StatefulWidget {
  const _LyricPreviewDialog({
    required this.candidate,
    required this.song,
    required this.audioVersion,
    required this.cfg,
  });

  final LyricSearchCandidate candidate;
  final Song song;
  final AudioVersion? audioVersion;
  final AppThemeConfig cfg;

  @override
  State<_LyricPreviewDialog> createState() => _LyricPreviewDialogState();
}

class _LyricPreviewDialogState extends State<_LyricPreviewDialog> {
  LoadedLyricContent? _loaded;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final loaded = await LyricSearchService.loadCandidate(widget.candidate);
      if (!mounted) {
        return;
      }
      setState(() {
        _loaded = loaded;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    final loaded = _loaded;
    if (loaded == null || _saving) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      final saved = await music.saveLyric(
        songId: widget.song.id,
        audioVersionId: widget.audioVersion?.id,
        source: widget.candidate.source,
        sourceId: widget.candidate.sourceId,
        title: widget.candidate.title,
        artist: widget.candidate.artist,
        content: loaded.content,
        translation: loaded.translation,
        romanized: loaded.romanized,
        offsetMs: 0,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    final loaded = _loaded;
    return AlertDialog(
      title: Text(
        '${widget.candidate.sourceLabel} · ${widget.candidate.title}',
      ),
      content: SizedBox(
        width: 520,
        height: 520,
        child: _loading
            ? Center(child: CircularProgressIndicator(color: cfg.accent))
            : _error != null
            ? SelectableText(_error!)
            : SyncedLyricsView(
                content: loaded!.content,
                translation: loaded.translation,
                offsetMs: 0,
                cfg: cfg,
                compact: true,
                allowSeekGuide: false,
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: loaded == null || _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存到当前音源'),
        ),
      ],
    );
  }
}

class _ManualLyricDialog extends StatefulWidget {
  const _ManualLyricDialog({
    required this.song,
    required this.audioVersion,
    required this.cfg,
  });

  final Song song;
  final AudioVersion? audioVersion;
  final AppThemeConfig cfg;

  @override
  State<_ManualLyricDialog> createState() => _ManualLyricDialogState();
}

class _ManualLyricDialogState extends State<_ManualLyricDialog> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.song.lyrics ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _saving) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await music.saveLyric(
        songId: widget.song.id,
        audioVersionId: widget.audioVersion?.id,
        source: 'manual',
        sourceId: null,
        title: widget.song.title,
        artist: widget.song.artist,
        content: content,
        translation: null,
        romanized: null,
        offsetMs: 0,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('手动粘贴歌词'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '[00:12.34] 歌词文本',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存到当前音源'),
        ),
      ],
    );
  }
}

class SyncedLyricsView extends StatefulWidget {
  const SyncedLyricsView({
    super.key,
    required this.content,
    required this.offsetMs,
    required this.cfg,
    this.translation,
    this.compact = false,
    this.allowSeekGuide = true,
  });

  final String content;
  final String? translation;
  final int offsetMs;
  final AppThemeConfig cfg;
  final bool compact;
  final bool allowSeekGuide;

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  final ScrollController _controller = ScrollController();
  Timer? _guideTimer;
  int _lastActiveIndex = -1;
  bool _guideVisible = false;
  bool _autoScrolling = false;

  double get _lineExtent => widget.compact ? 44 : 52;

  @override
  void dispose() {
    _guideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioPlayerProvider>();
    final lines = _parseLyrics(widget.content);
    final translation = _translationByTime(widget.translation);
    final timed = lines.any((line) => line.timeMs != null);
    if (lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(color: widget.cfg.textSub, fontSize: 12),
        ),
      );
    }

    final activeIndex = timed
        ? _activeLineIndex(
            lines,
            audio.currentPosition.inMilliseconds + widget.offsetMs,
          )
        : -1;
    if (activeIndex != _lastActiveIndex && !_guideVisible) {
      _lastActiveIndex = activeIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients || activeIndex < 0) {
          return;
        }
        _autoScrollToIndex(activeIndex);
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (!widget.allowSeekGuide || _autoScrolling) {
                  return false;
                }
                if (notification is ScrollStartNotification ||
                    notification is ScrollUpdateNotification) {
                  _showSeekGuide();
                }
                return false;
              },
              child: ListView.builder(
                controller: _controller,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.compact ? 18 : 24,
                  vertical: math.max(
                    18,
                    constraints.maxHeight / 2 - _lineExtent / 2,
                  ),
                ),
                itemExtent: _lineExtent,
                itemCount: lines.length,
                itemBuilder: (context, index) {
                  final line = lines[index];
                  final active = index == activeIndex;
                  final lineTranslation = line.timeMs == null
                      ? null
                      : translation[line.timeMs]?.trim();
                  return _LyricLineTile(
                    line: line,
                    translation: lineTranslation,
                    active: active,
                    cfg: widget.cfg,
                    compact: widget.compact,
                  );
                },
              ),
            ),
            if (widget.allowSeekGuide && _guideVisible)
              _SeekGuideOverlay(
                cfg: widget.cfg,
                onSeek: timed ? () => _seekToGuideLine(lines) : null,
              ),
          ],
        );
      },
    );
  }

  void _autoScrollToIndex(int index) {
    if (!_controller.hasClients) {
      return;
    }
    final target = math.max(0.0, index * _lineExtent);
    _autoScrolling = true;
    _controller
        .animateTo(
          math.min(target, _controller.position.maxScrollExtent),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        )
        .whenComplete(() {
          _autoScrolling = false;
        });
  }

  void _showSeekGuide() {
    _guideTimer?.cancel();
    if (!_guideVisible) {
      setState(() {
        _guideVisible = true;
      });
    }
    _guideTimer = Timer(const Duration(milliseconds: 2400), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _guideVisible = false;
      });
    });
  }

  int _centerLineIndex(int count) {
    if (!_controller.hasClients || count == 0) {
      return 0;
    }
    final raw = (_controller.offset / _lineExtent).round();
    return raw.clamp(0, count - 1);
  }

  Future<void> _seekToGuideLine(List<_LyricLine> lines) async {
    final index = _centerLineIndex(lines.length);
    final target = lines[index].timeMs;
    if (target == null) {
      return;
    }
    final seekMs = math.max(0, target - widget.offsetMs);
    await context.read<AudioPlayerProvider>().seek(
      Duration(milliseconds: seekMs),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _guideVisible = false;
    });
  }

  static List<_LyricLine> _parseLyrics(String content) {
    final timedLines = <_LyricLine>[];
    final plainLines = <_LyricLine>[];
    final timeReg = RegExp(
      r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?(?:,\d{1,8})?\]',
    );
    final qrcLineReg = RegExp(r'^\[(\d{1,8}),(\d{1,8})\]');
    final metadataReg = RegExp(r'^\[[a-zA-Z]+:.*\]$');
    for (final rawLine
        in content
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n')
            .split('\n')) {
      if (metadataReg.hasMatch(rawLine.trim())) {
        continue;
      }
      final matches = timeReg.allMatches(rawLine).toList(growable: false);
      final qrcMatch = qrcLineReg.firstMatch(rawLine.trimLeft());
      final lineTimes = <_LineTime>[];
      for (final match in matches) {
        lineTimes.add(
          _LineTime(
            _parseTimestamp(match.group(1), match.group(2), match.group(3)),
            null,
          ),
        );
      }
      if (qrcMatch != null) {
        final start = int.tryParse(qrcMatch.group(1) ?? '') ?? 0;
        final duration = int.tryParse(qrcMatch.group(2) ?? '') ?? 0;
        lineTimes.add(_LineTime(start, duration > 0 ? start + duration : null));
      }

      var lyricPart = rawLine
          .replaceAll(timeReg, '')
          .replaceAll(qrcLineReg, '')
          .trim();
      if (lineTimes.isEmpty) {
        if (rawLine.trim().isNotEmpty) {
          plainLines.add(
            _LyricLine(null, null, _cleanLyricText(rawLine), const []),
          );
        }
        continue;
      }
      for (final lineTime in lineTimes) {
        final parsed = _parseTimedLineContent(
          lyricPart,
          lineTime.startMs,
          lineTime.endMs,
        );
        timedLines.add(
          _LyricLine(
            lineTime.startMs,
            lineTime.endMs,
            parsed.text,
            parsed.segments,
          ),
        );
      }
    }
    if (timedLines.isEmpty) {
      return plainLines.isEmpty ? const <_LyricLine>[] : plainLines;
    }
    timedLines.sort((a, b) => (a.timeMs ?? 0).compareTo(b.timeMs ?? 0));
    for (var i = 0; i < timedLines.length; i++) {
      final line = timedLines[i];
      final start = line.timeMs;
      if (start == null) {
        continue;
      }
      final nextStart = i + 1 < timedLines.length
          ? timedLines[i + 1].timeMs
          : null;
      line.endMs ??= nextStart ?? start + _estimatedLineDuration(line.text);
      if (line.endMs! <= start) {
        line.endMs = start + _estimatedLineDuration(line.text);
      }
      for (var j = 0; j < line.segments.length; j++) {
        final segment = line.segments[j];
        if (segment.endMs <= segment.startMs) {
          segment.endMs = j + 1 < line.segments.length
              ? line.segments[j + 1].startMs
              : line.endMs!;
        }
      }
    }
    return timedLines;
  }

  static Map<int, String> _translationByTime(String? content) {
    if (content == null || content.trim().isEmpty) {
      return const <int, String>{};
    }
    final result = <int, String>{};
    for (final line in _parseLyrics(content)) {
      final time = line.timeMs;
      if (time != null && line.text.trim().isNotEmpty) {
        result[time] = line.text;
      }
    }
    return result;
  }

  static int _activeLineIndex(List<_LyricLine> lines, int positionMs) {
    var active = -1;
    for (var i = 0; i < lines.length; i++) {
      final time = lines[i].timeMs;
      if (time == null) {
        continue;
      }
      if (time <= positionMs) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  static int _parseTimestamp(
    String? minuteText,
    String? secondText,
    String? fracText,
  ) {
    final minute = int.tryParse(minuteText ?? '') ?? 0;
    final second = int.tryParse(secondText ?? '') ?? 0;
    final frac = fracText ?? '0';
    final millis = frac.length == 1
        ? int.parse(frac) * 100
        : frac.length == 2
        ? int.parse(frac) * 10
        : int.parse(frac.substring(0, math.min(3, frac.length)));
    return (minute * 60 + second) * 1000 + millis;
  }

  static int _estimatedLineDuration(String text) {
    return math.max(1800, math.min(6200, text.runes.length * 180));
  }

  static _ParsedLineContent _parseTimedLineContent(
    String rawText,
    int lineStartMs,
    int? lineEndMs,
  ) {
    final relativeReg = RegExp(r'[\(<](\d{1,8}),(\d{1,8})[\)>]');
    final absoluteReg = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>');

    final relativeMatches = relativeReg
        .allMatches(rawText)
        .toList(growable: false);
    if (relativeMatches.isNotEmpty) {
      final segments = <_LyricSegment>[];
      for (var i = 0; i < relativeMatches.length; i++) {
        final match = relativeMatches[i];
        final nextStart = i + 1 < relativeMatches.length
            ? relativeMatches[i + 1].start
            : rawText.length;
        final text = _cleanLyricText(rawText.substring(match.end, nextStart));
        if (text.isEmpty) {
          continue;
        }
        final offset = int.tryParse(match.group(1) ?? '') ?? 0;
        final duration = int.tryParse(match.group(2) ?? '') ?? 0;
        final start = lineStartMs + offset;
        segments.add(_LyricSegment(start, start + duration, text));
      }
      final text = segments.map((segment) => segment.text).join();
      if (text.trim().isNotEmpty) {
        return _ParsedLineContent(text.trim(), segments);
      }
    }

    final absoluteMatches = absoluteReg
        .allMatches(rawText)
        .toList(growable: false);
    if (absoluteMatches.isNotEmpty) {
      final segments = <_LyricSegment>[];
      for (var i = 0; i < absoluteMatches.length; i++) {
        final match = absoluteMatches[i];
        final nextStart = i + 1 < absoluteMatches.length
            ? absoluteMatches[i + 1].start
            : rawText.length;
        final text = _cleanLyricText(rawText.substring(match.end, nextStart));
        if (text.isEmpty) {
          continue;
        }
        final start = _parseTimestamp(
          match.group(1),
          match.group(2),
          match.group(3),
        );
        segments.add(_LyricSegment(start, start, text));
      }
      final text = segments.map((segment) => segment.text).join();
      if (text.trim().isNotEmpty) {
        return _ParsedLineContent(text.trim(), segments);
      }
    }

    return _ParsedLineContent(_cleanLyricText(rawText), const []);
  }

  static String _cleanLyricText(String text) {
    return text
        .replaceAll(RegExp(r'\[[a-zA-Z]+:[^\]]*\]'), '')
        .replaceAll(RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>'), '')
        .replaceAll(RegExp(r'[\(<](\d{1,8}),(\d{1,8})[\)>]'), '')
        .trim();
  }
}

class _LyricLine {
  _LyricLine(this.timeMs, this.endMs, this.text, this.segments);

  final int? timeMs;
  int? endMs;
  final String text;
  final List<_LyricSegment> segments;
}

class _LyricSegment {
  _LyricSegment(this.startMs, this.endMs, this.text);

  final int startMs;
  int endMs;
  final String text;
}

class _LineTime {
  const _LineTime(this.startMs, this.endMs);

  final int startMs;
  final int? endMs;
}

class _ParsedLineContent {
  const _ParsedLineContent(this.text, this.segments);

  final String text;
  final List<_LyricSegment> segments;
}

class _LyricLineTile extends StatelessWidget {
  const _LyricLineTile({
    required this.line,
    required this.translation,
    required this.active,
    required this.cfg,
    required this.compact,
  });

  final _LyricLine line;
  final String? translation;
  final bool active;
  final AppThemeConfig cfg;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      color: active ? cfg.textMain : cfg.textSub,
      fontSize: active ? (compact ? 14 : 15) : (compact ? 12 : 12.5),
      fontWeight: active ? FontWeight.w900 : FontWeight.w500,
      height: 1.24,
    );
    return AnimatedScale(
      scale: active ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 160),
              style: baseStyle,
              child: Text(
                line.text.isEmpty ? ' ' : line.text,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (translation != null && translation!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  translation!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active
                        ? cfg.accent
                        : cfg.textSub.withValues(alpha: 0.65),
                    fontSize: compact ? 10.5 : 11.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SeekGuideOverlay extends StatelessWidget {
  const _SeekGuideOverlay({required this.cfg, required this.onSeek});

  final AppThemeConfig cfg;
  final VoidCallback? onSeek;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Center(
          child: Row(
            children: [
              const SizedBox(width: 18),
              Expanded(
                child: CustomPaint(
                  painter: _DashedLinePainter(
                    cfg.accent.withValues(alpha: 0.55),
                  ),
                  child: const SizedBox(height: 1),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: cfg.accent.withValues(alpha: 0.14),
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: onSeek,
                  icon: Icon(Icons.play_arrow, color: cfg.accent, size: 18),
                  tooltip: '从这里播放',
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashWidth = 6.0;
    const dashGap = 5.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(math.min(x + dashWidth, size.width), 0),
        paint,
      );
      x += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
