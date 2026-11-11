import 'package:flutter/material.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/providers/audio_player_provider.dart';
import 'dart:async';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/player/ui/lyrics/lyrics_panel_widgets.dart';
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
  int? _lastLyricRevision;

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
    final lyricRevision = context.select<FloatingLyricsProvider, int>(
      (p) => p.lyricRevision,
    );
    if (_lastLyricRevision != null && _lastLyricRevision != lyricRevision) {
      _lastLyricRevision = lyricRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadSavedLyric();
      });
    } else {
      _lastLyricRevision = lyricRevision;
    }

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
            AetherIconButton(
              icon: Icons.tune_rounded,
              iconSize: AetherIconSize.lg,
              color: cfg.textSecondary,
              tooltip: '歌词管理',
              onPressed: () => _openManager(context),
            ),
          ],
        ),
        if (error != null) LyricPanelError(error),
        Expanded(
          child: _loading
              ? const LyricPanelLoading()
              : content == null
              ? LyricPanelEmptyState(
                  actionLabel: '打开歌词管理',
                  actionIcon: Icons.tune_rounded,
                  onAction: () => _openManager(context),
                )
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

  void _openManager(BuildContext context) {
    final callback = widget.onOpenManager;
    if (callback != null) {
      callback();
      return;
    }
    context.read<AudioPlayerProvider>().setActiveTab('lyric_manager');
  }
}


