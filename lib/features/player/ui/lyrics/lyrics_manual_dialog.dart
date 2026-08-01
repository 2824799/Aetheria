import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/floating_lyrics_provider.dart';
import 'package:aetheria/src/rust/api/music.dart' as music;

import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_dialog.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/src/rust/models/song.dart';

class ManualLyricDialog extends StatefulWidget {
  const ManualLyricDialog({
    super.key,
    required this.song,
    required this.audioVersion,
    required this.cfg,
  });

  final Song song;
  final AudioVersion? audioVersion;
  final AppThemeConfig cfg;

  @override
  State<ManualLyricDialog> createState() => ManualLyricDialogState();
}

class ManualLyricDialogState extends State<ManualLyricDialog> {
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
    return AetherDialog(
      maxWidth: 560,
      title: '手动粘贴歌词',
      content: SizedBox(
        height: 360,
        child: Column(
          children: [
            Expanded(
              child: AetherTextField(
                controller: _controller,
                maxLines: 20,
                minLines: 12,
                hintText: '[00:12.34] 歌词文本',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AetherSpace.md),
              Text(_error!, style: AetherType.bodySmStyle(widget.cfg.danger)),
            ],
          ],
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
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
