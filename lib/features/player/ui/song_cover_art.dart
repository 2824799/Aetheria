import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/src/rust/models/song.dart';

class SongCoverArt extends StatefulWidget {
  const SongCoverArt({
    super.key,
    required this.song,
    required this.cfg,
    required this.size,
    this.borderRadius = 14,
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
  bool _loading = false;

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
      _coverPath = widget.song.coverPath;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCover());
    }
  }

  Future<void> _ensureCover() async {
    if (!mounted || _loading || widget.song.id.isEmpty) {
      return;
    }
    final currentPath = _absoluteCoverPath(_coverPath);
    if (currentPath != null && File(currentPath).existsSync()) {
      return;
    }

    _loading = true;
    try {
      final path = await context.read<LibraryProvider>().ensureSongCover(
        widget.song,
      );
      if (!mounted || path == null || path.trim().isEmpty) {
        return;
      }
      setState(() {
        _coverPath = path;
      });
    } finally {
      _loading = false;
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
    final hasCover = absolutePath != null && File(absolutePath).existsSync();

    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      gradient: hasCover
          ? null
          : LinearGradient(
              colors: [Colors.white.withValues(alpha: 0.06), cfg.border],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
      border: Border.all(color: cfg.border),
      boxShadow: widget.shadow
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
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
