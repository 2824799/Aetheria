import 'package:flutter/material.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'dart:async';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_progress.dart';
import 'package:aetheria/features/player/ui/lyrics/lyrics_shared.dart';
import 'package:aetheria/features/player/ui/lyrics/lyrics_synced_view.dart';
import 'package:aetheria/src/rust/models/song.dart';

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
        : '${lyricSourceLabel(_savedLyric!.source)} · ${_savedLyric!.offsetMs}ms';

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
                        color: cfg.textPrimary,
                        fontSize: widget.compact ? AetherType.bodySm : AetherType.body,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sourceText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cfg.textSecondary, fontSize: AetherType.caption),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: '歌词管理',
                child: AetherIconButton(
                  icon: Icons.manage_search,
                  iconSize: AetherIconSize.xl,
                  color: cfg.textSecondary,
                  tooltip: '管理歌词',
                  onPressed: () => _openManager(context),
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
              style: AetherType.captionStyle(cfg.warning),
            ),
          ),
        Expanded(
          child: _loading
              ? Center(
                  child: AetherProgress.circular(size: 16, strokeWidth: 2),
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
            Icon(Icons.lyrics_outlined, color: cfg.textSecondary, size: 30),
            const SizedBox(height: 10),
            Text(
              '暂无歌词',
              style: TextStyle(
                color: cfg.textPrimary,
                fontSize: AetherType.titleSm,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            AetherButton.primary(
              onPressed: () => _openManager(context),
              icon: Icons.manage_search,
              label: '打开歌词管理',
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


