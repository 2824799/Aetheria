import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/utils/audio_quality.dart';
import 'package:aetheria/features/library/ui/song_badges.dart';
import 'package:aetheria/features/library/ui/song_table/song_columns.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_column_layout.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_tags.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_text.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// Builds the body cells of one song row.
class SongTableCells {
  const SongTableCells({required this.textCache, required this.layout});

  final SongTableTextCache textCache;
  final SongTableColumnLayout layout;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: AetherSpace.lg,
  );

  Widget build(
    SongColumnKey column,
    Song song,
    AppThemeConfig cfg, {
    required bool isPlaying,
    required bool hasLyrics,
  }) {
    final width = layout.widthOf(column);
    return SizedBox(
      width: width,
      child: switch (column) {
        SongColumnKey.title => _title(song, cfg, isPlaying, hasLyrics),
        SongColumnKey.artist => _artist(song, cfg),
        SongColumnKey.tags => _tags(song, cfg, width),
        SongColumnKey.versions => _versions(song, cfg),
        SongColumnKey.spec => _quality(song),
      },
    );
  }

  Widget _title(Song song, AppThemeConfig cfg, bool isPlaying, bool hasLyrics) {
    return Padding(
      padding: _padding,
      child: Row(
        children: [
          Expanded(
            child: SongTableText(
              song.title,
              cache: textCache,
              prefetchGroup: isPlaying
                  ? null
                  : hasLyrics
                  ? SongTableTextGroup.title
                  : SongTableTextGroup.titleWithoutLyrics,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AetherType.titleSmStyle(
                isPlaying ? cfg.accent : cfg.textPrimary,
              ).copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          if (hasLyrics) ...[
            const SizedBox(width: AetherSpace.sm),
            const LrcBadge(),
          ],
        ],
      ),
    );
  }

  Widget _artist(Song song, AppThemeConfig cfg) {
    final artist = song.artist;
    return Padding(
      padding: _padding,
      child: SongTableText(
        artist ?? '未知歌手',
        cache: textCache,
        prefetchGroup: SongTableTextGroup.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AetherType.bodyStyle(
          artist == null ? cfg.textTertiary : cfg.textSecondary,
        ),
      ),
    );
  }

  Widget _tags(Song song, AppThemeConfig cfg, double width) {
    return Padding(
      padding: _padding,
      child: song.tags.isEmpty
          ? SongTableText(
              '—',
              cache: textCache,
              style: AetherType.bodySmStyle(cfg.textTertiary),
            )
          : SongTableTags(
              tags: song.tags,
              textCache: textCache,
              cfg: cfg,
              availableWidth: width - _padding.horizontal,
            ),
    );
  }

  Widget _versions(Song song, AppThemeConfig cfg) {
    final count = song.versions.length;
    return Center(
      child: SongTableText(
        count.toString(),
        cache: textCache,
        textAlign: TextAlign.center,
        // One version is the norm; only extra versions deserve attention.
        style: AetherType.bodyStyle(
          count > 1 ? cfg.textPrimary : cfg.textTertiary,
        ).copyWith(fontWeight: count > 1 ? FontWeight.w600 : FontWeight.w400),
      ),
    );
  }

  Widget _quality(Song song) {
    return Center(
      child: AudioQualityBadge(
        version: primaryVersionOf(song),
        textCache: textCache,
      ),
    );
  }
}
