import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/theme/theme.dart';
import 'package:aetheria/src/rust/models/song.dart';

class SongCoverArt extends StatefulWidget {
  const SongCoverArt({
    super.key,
    required this.song,
    required this.cfg,
    required this.size,
    this.borderRadius = AetherRadius.lg,
    this.iconSize = 44,
    this.shadow = true,
  });

  final Song song;
  final AppThemeConfig cfg;
  final double size;
  final double borderRadius;
  final double iconSize;
  final bool shadow;

  @override
  State<SongCoverArt> createState() => _SongCoverArtState();
}

class _SongCoverArtState extends State<SongCoverArt> {
  String? _coverPath;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _coverPath = widget.song.coverPath;
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCover());
  }

  @override
  void didUpdateWidget(covariant SongCoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.song.coverPath != widget.song.coverPath) {
      _request++;
      _coverPath = widget.song.coverPath;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCover());
    }
  }

  Future<void> _ensureCover() async {
    if (!mounted || widget.song.id.isEmpty) {
      return;
    }
    final request = ++_request;
    final song = widget.song;
    final library = context.read<LibraryProvider>();
    final currentPath = _absoluteCoverPath(_coverPath);
    try {
      if (currentPath != null && await File(currentPath).exists()) return;
      if (!mounted || request != _request || song.id != widget.song.id) return;
      final path = await library.ensureSongCover(song);
      if (!mounted ||
          request != _request ||
          song.id != widget.song.id ||
          path == null ||
          path.trim().isEmpty) {
        return;
      }
      setState(() {
        _coverPath = path;
      });
    } catch (_) {
      // Missing or corrupt covers retain the placeholder.
    }
  }

  String? _absoluteCoverPath(String? relativePath) {
    final path = relativePath?.trim();
    if (path == null || path.isEmpty) {
      return null;
    }
    final libraryPath = context.read<LibraryProvider>().libraryPath;
    if (libraryPath.trim().isEmpty) {
      return null;
    }
    return '$libraryPath/$path'.replaceAll('\\', '/');
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    final absolutePath = _absoluteCoverPath(_coverPath);
    final hasCover = absolutePath != null;

    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      gradient: hasCover
          ? null
          : LinearGradient(
              colors: [
                cfg.textPrimary.withValues(alpha: 0.06),
                cfg.borderSubtle,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
      border: Border.all(color: cfg.borderSubtle),
      boxShadow: widget.shadow
          ? [
              BoxShadow(
                color: cfg.textPrimary.withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ]
          : null,
    );

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: decoration,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: hasCover
            ? Image.file(
                File(absolutePath),
                fit: BoxFit.cover,
                cacheWidth:
                    (widget.size * MediaQuery.devicePixelRatioOf(context))
                        .ceil(),
                errorBuilder: (context, error, stackTrace) =>
                    _PlaceholderCover(cfg: cfg, iconSize: widget.iconSize),
              )
            : _PlaceholderCover(cfg: cfg, iconSize: widget.iconSize),
      ),
    );
  }
}

class _PlaceholderCover extends StatelessWidget {
  const _PlaceholderCover({required this.cfg, required this.iconSize});

  final AppThemeConfig cfg;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(Icons.music_note, size: iconSize, color: cfg.accent),
    );
  }
}
