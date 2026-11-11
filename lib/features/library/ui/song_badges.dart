import 'package:flutter/material.dart';

import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/utils/audio_quality.dart';
import 'package:aetheria/core/utils/formatting.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_text.dart';
import 'package:aetheria/src/rust/models/song.dart';

// Small song markers shared by the desktop table and the mobile list.
//
// [textCache] is the desktop table's layout cache; leave it null elsewhere.

/// Marks a song that has lyrics.
class LrcBadge extends StatelessWidget {
  const LrcBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AetherRadius.xs),
        border: Border.all(color: cfg.borderStrong),
      ),
      child: Text(
        'LRC',
        style: AetherType.captionStyle(cfg.textTertiary).copyWith(
          fontWeight: FontWeight.w700,
          fontSize: AetherType.caption - 1,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Sample rate / bit depth / bitrate / loudness of [version], tinted by its
/// quality tier.
class AudioQualityBadge extends StatelessWidget {
  const AudioQualityBadge({super.key, required this.version, this.textCache});

  final AudioVersion? version;
  final SongTableTextCache? textCache;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final color = audioQualityColor(version, cfg);
    final text = audioQualityText(version);
    final style = AetherType.captionStyle(color).copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final cache = textCache;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AetherSpace.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AetherRadius.xs),
      ),
      child: cache == null
          ? Text(text, maxLines: 1, style: style)
          : SongTableText(text, cache: cache, style: style),
    );
  }
}

/// A tag on a song row: tinted label with a colour bar on its left edge.
class SongTagChip extends StatelessWidget {
  const SongTagChip({super.key, required this.tag, this.textCache});

  /// Horizontal space the chip takes besides its label.
  static const double chromeWidth = 14;

  final Tag tag;
  final SongTableTextCache? textCache;

  static const TextStyle labelStyle = TextStyle(
    fontSize: AetherType.caption,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final color = parseTagColor(tag.color, cfg.accent);
    final style = labelStyle.copyWith(color: color);
    final cache = textCache;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AetherRadius.xs),
        border: Border(left: BorderSide(color: color, width: 2)),
      ),
      child: cache == null
          ? Text(tag.name, maxLines: 1, style: style)
          : SongTableText(tag.name, cache: cache, style: style),
    );
  }
}
