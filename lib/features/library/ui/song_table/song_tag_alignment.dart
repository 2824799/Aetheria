import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/utils/tag_ordering.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// One vertical tag column slot reserved for a tag category in aligned mode.
class AlignedTagSlot {
  const AlignedTagSlot({
    required this.category,
    required this.slotInCategory,
    required this.width,
    required this.trailingGap,
  });

  final String category;
  final int slotInCategory;
  final double width;
  final double trailingGap;
}

/// One aligned slot assigned to a specific song row (`tag` is null when absent).
typedef AlignedRowSlot = ({AlignedTagSlot slot, Tag? tag});

/// Precomputed column-slot geometry across the currently visible song list.
///
/// For each tag category present in the list (ordered by category priority),
/// reserves `maxCount(category)` slots. Each slot's width equals the widest tag
/// appearing at that `(category, slotIndex)` position across the list so tags of
/// the same category and slot align vertically across all rows.
class SongTagAlignmentPlan {
  const SongTagAlignmentPlan(this.slots);

  final List<AlignedTagSlot> slots;

  bool get hasSlots => slots.isNotEmpty;

  factory SongTagAlignmentPlan.fromSongs(
    List<Song> songs, {
    required TagOrderConfig orderConfig,
    required double Function(Tag tag) measureChipWidth,
  }) {
    final maxWidthsByCategory = <String, List<double>>{};

    for (final song in songs) {
      if (song.tags.isEmpty) continue;
      final sorted = orderConfig.sortTags(song.tags);
      final counts = <String, int>{};
      for (final tag in sorted) {
        final category = effectiveTagCategory(tag);
        final slotIndex = counts[category] ?? 0;
        counts[category] = slotIndex + 1;

        // Round up slightly so fractional glyph metrics never clip inside a slot.
        final width = (measureChipWidth(tag) + 0.5).ceilToDouble();
        final slotWidths = maxWidthsByCategory.putIfAbsent(category, () => []);
        if (slotIndex >= slotWidths.length) {
          slotWidths.add(width);
        } else if (width > slotWidths[slotIndex]) {
          slotWidths[slotIndex] = width;
        }
      }
    }

    if (maxWidthsByCategory.isEmpty) {
      return const SongTagAlignmentPlan([]);
    }

    final orderedCategories = maxWidthsByCategory.keys.toList()
      ..sort(orderConfig.compareCategories);

    final slots = <AlignedTagSlot>[];
    for (var catIndex = 0; catIndex < orderedCategories.length; catIndex++) {
      final category = orderedCategories[catIndex];
      final widths = maxWidthsByCategory[category]!;
      final hasNextCategory = catIndex + 1 < orderedCategories.length;
      for (var slotIndex = 0; slotIndex < widths.length; slotIndex++) {
        final isLastInCategory = slotIndex + 1 == widths.length;
        slots.add(
          AlignedTagSlot(
            category: category,
            slotInCategory: slotIndex,
            width: widths[slotIndex],
            trailingGap: (isLastInCategory && hasNextCategory)
                ? AetherSpace.lg
                : AetherSpace.sm,
          ),
        );
      }
    }

    return SongTagAlignmentPlan(List<AlignedTagSlot>.unmodifiable(slots));
  }

  /// Resolves [sortedTags] into aligned slots up through this row's last tag,
  /// preserving blank spacers before or between tags while omitting trailing
  /// empty slots so rows without overflow do not create extra scrollables.
  List<AlignedRowSlot> resolveRow(List<Tag> sortedTags) {
    if (sortedTags.isEmpty || slots.isEmpty) {
      return const [];
    }
    final resolved = <AlignedRowSlot>[];
    var tagIndex = 0;
    var lastNonEmpty = -1;

    for (final slot in slots) {
      Tag? matched;
      if (tagIndex < sortedTags.length &&
          effectiveTagCategory(sortedTags[tagIndex]) == slot.category) {
        matched = sortedTags[tagIndex++];
        lastNonEmpty = resolved.length;
      }
      resolved.add((slot: slot, tag: matched));
    }

    if (lastNonEmpty < 0) return const [];
    return resolved.sublist(0, lastNonEmpty + 1);
  }
}
