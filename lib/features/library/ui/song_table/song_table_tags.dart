import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/library/ui/song_badges.dart';
import 'package:aetheria/features/library/ui/song_table/song_tag_alignment.dart';
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
    this.alignmentPlan,
  });

  final List<Tag> tags;
  final SongTableTextCache? textCache;
  final AppThemeConfig cfg;
  final double availableWidth;
  final SongTagAlignmentPlan? alignmentPlan;

  static final _widths = <(String, double), double>{};

  static double _labelWidth(BuildContext context, String label) {
    final scaler = MediaQuery.textScalerOf(context);
    final scale = scaler.scale(14) / 14;
    final key = (label, scale);
    final cached = _widths[key];
    if (cached != null) return cached;

    final style = DefaultTextStyle.of(
      context,
    ).style.merge(SongTagChip.labelStyle);
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

  /// Measures total chip width for [tag] under the current text scale and style.
  static double measureChipWidth(BuildContext context, Tag tag) =>
      _labelWidth(context, tag.name) + SongTagChip.chromeWidth;

  @override
  Widget build(BuildContext context) {
    final plan = alignmentPlan;
    if (plan != null && plan.hasSlots) {
      return _buildAligned(plan);
    }

    // Include chip chrome and trailing gap. The guard absorbs fractional font
    // metrics at desktop scales without risking Row overflow.
    final requiredWidth = tags.fold<double>(
      1,
      (sum, tag) =>
          sum +
          _labelWidth(context, tag.name) +
          SongTagChip.chromeWidth +
          AetherSpace.sm,
    );
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tag in tags)
          Padding(
            padding: const EdgeInsets.only(right: AetherSpace.sm),
            child: SongTagChip(tag: tag, textCache: textCache),
          ),
      ],
    );
    return requiredWidth <= availableWidth
        ? row
        : SingleChildScrollView(scrollDirection: Axis.horizontal, child: row);
  }

  Widget _buildAligned(SongTagAlignmentPlan plan) {
    final rowSlots = plan.resolveRow(tags);
    if (rowSlots.isEmpty) {
      return const SizedBox.shrink();
    }

    var requiredWidth = 1.0;
    for (var i = 0; i < rowSlots.length; i++) {
      requiredWidth += rowSlots[i].slot.width;
      if (i + 1 < rowSlots.length) {
        requiredWidth += rowSlots[i].slot.trailingGap;
      }
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rowSlots.length; i++) ...[
          SizedBox(
            width: rowSlots[i].slot.width,
            child: rowSlots[i].tag == null
                ? null
                : Align(
                    alignment: Alignment.centerLeft,
                    child: SongTagChip(
                      tag: rowSlots[i].tag!,
                      textCache: textCache,
                    ),
                  ),
          ),
          if (i + 1 < rowSlots.length)
            SizedBox(width: rowSlots[i].slot.trailingGap),
        ],
      ],
    );

    return requiredWidth <= availableWidth
        ? row
        : SingleChildScrollView(scrollDirection: Axis.horizontal, child: row);
  }
}
