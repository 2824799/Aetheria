import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_widgets.dart';
import 'package:aetheria/features/library/ui/song_table/song_table_text.dart';
import 'package:aetheria/src/rust/models/song.dart';
import 'package:flutter/material.dart';

/// Ordinary tag rows need only a Row. Create a nested Scrollable only when
/// the labels actually overflow, keeping horizontal access to longer tag sets.
class SongTableTags extends StatelessWidget {
  const SongTableTags({
    super.key,
    required this.tags,
    this.textCache,
    required this.cfg,
    required this.availableWidth,
  });

  final List<Tag> tags;
  final SongTableTextCache? textCache;
  final AppThemeConfig cfg;
  final double availableWidth;

  static final _widths = <(String, double), double>{};

  double _labelWidth(BuildContext context, String label) {
    final scaler = MediaQuery.textScalerOf(context);
    final scale = scaler.scale(14) / 14;
    final key = (label, scale);
    final cached = _widths[key];
    if (cached != null) return cached;

    final style = DefaultTextStyle.of(context).style.merge(
      const TextStyle(
        fontSize: AetherType.caption,
        fontWeight: FontWeight.bold,
      ),
    );
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
    )..layout();
    final width = painter.width;
    painter.dispose();
    _widths[key] = width;
    return width;
  }

  @override
  Widget build(BuildContext context) {
    // Include chip padding, left border and trailing margin. The guard absorbs
    // fractional font metrics at desktop scales without risking Row overflow.
    final requiredWidth = tags.fold<double>(
      1,
      (sum, tag) => sum + _labelWidth(context, tag.name) + 14 + AetherSpace.sm,
    );
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final tag in tags) _chip(tag)],
    );
    return requiredWidth <= availableWidth
        ? row
        : SingleChildScrollView(scrollDirection: Axis.horizontal, child: row);
  }

  Widget _chip(Tag tag) {
    final color = tag.color == null
        ? cfg.accent
        : songTableParseHexColor(tag.color!, cfg.accent);
    return Container(
      margin: const EdgeInsets.only(right: AetherSpace.sm),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AetherRadius.xs),
        border: Border(left: BorderSide(color: color, width: 2)),
      ),
      child: textCache == null
          ? Text(tag.name, style: _style(color))
          : SongTableText(tag.name, cache: textCache!, style: _style(color)),
    );
  }

  TextStyle _style(Color color) => TextStyle(
    fontSize: AetherType.caption,
    color: color,
    fontWeight: FontWeight.bold,
  );
}
