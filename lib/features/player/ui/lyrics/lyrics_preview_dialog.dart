import 'package:flutter/material.dart';
import 'package:aetheria/core/widgets/aether_empty_state.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;
import 'dart:async';

import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/features/player/ui/lyrics/lyrics_synced_view.dart';
import 'package:aetheria/services/lyric_search_service.dart';
import 'package:aetheria/src/rust/models/song.dart';

class LyricPreviewDialog extends StatefulWidget {
  const LyricPreviewDialog({
    super.key,
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
  State<LyricPreviewDialog> createState() => LyricPreviewDialogState();
}

class LyricPreviewDialogState extends State<LyricPreviewDialog> {
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
      context.read<FloatingLyricsProvider>().notifyLyricUpdated();
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
    return AetherDialog(
      maxWidth: 560,
      title: '${widget.candidate.sourceLabel} · ${widget.candidate.title}',
      content: SizedBox(
        height: 420,
        child: _loading
            ? const AetherLoading(message: '加载歌词预览…')
            : _error != null
            ? SelectableText(_error!, style: AetherType.bodyStyle(cfg.danger))
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
        AetherButton.ghost(
          label: '取消',
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        AetherButton.primary(
          label: '保存到当前音源',
          loading: _saving,
          onPressed: loaded == null || _saving ? null : _save,
        ),
      ],
    );
  }
}
