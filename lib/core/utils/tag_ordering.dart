import 'package:aetheria/src/rust/models/song.dart';

/// Fallback category name for tags with null/blank category.
const String kDefaultTagCategory = '自定义';

/// Built-in tag categories shown in pickers, ordered with [kDefaultTagCategory]
/// last.
const List<String> kPresetTagCategories = [
  '流派',
  '语言',
  '情绪',
  '场景',
  kDefaultTagCategory,
];

/// Returns the canonical category name for [tag].
String effectiveTagCategory(Tag tag) {
  final raw = tag.category?.trim();
  if (raw == null || raw.isEmpty) {
    return kDefaultTagCategory;
  }
  return raw;
}

/// Persisted display ordering for tag categories and tags within each category.
///
/// Earlier items in [categoryOrder] and [tagOrderByCategory] have higher display
/// priority. Unlisted categories/tags fall back deterministically after listed
/// ones so newly created items do not jump ahead of arranged priorities.
class TagOrderConfig {
  const TagOrderConfig({
    this.categoryOrder = const [],
    this.tagOrderByCategory = const {},
  });

  /// Ordered category names from highest priority (index 0) onward.
  final List<String> categoryOrder;

  /// Ordered tag IDs per category name from highest priority (index 0) onward.
  final Map<String, List<int>> tagOrderByCategory;

  static const _namedPresets = ['流派', '语言', '情绪', '场景'];

  factory TagOrderConfig.fromJson(dynamic json) {
    if (json is! Map) {
      return const TagOrderConfig();
    }
    final categories = <String>[];
    final seenCats = <String>{};
    final rawCategories = json['categories'];
    if (rawCategories is List) {
      for (final item in rawCategories) {
        final name = item?.toString().trim() ?? '';
        if (name.isNotEmpty && seenCats.add(name)) {
          categories.add(name);
        }
      }
    }

    final tagsByCategory = <String, List<int>>{};
    final rawTags = json['tagsByCategory'];
    if (rawTags is Map) {
      for (final entry in rawTags.entries) {
        final category = entry.key.toString().trim();
        if (category.isEmpty || entry.value is! List) continue;
        final ids = <int>[];
        final seenIds = <int>{};
        for (final rawId in entry.value as List) {
          final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
          if (id != null && seenIds.add(id)) {
            ids.add(id);
          }
        }
        tagsByCategory[category] = List<int>.unmodifiable(ids);
      }
    }

    return TagOrderConfig(
      categoryOrder: List<String>.unmodifiable(categories),
      tagOrderByCategory: Map<String, List<int>>.unmodifiable(tagsByCategory),
    );
  }

  Map<String, dynamic> toJson() => {
        'categories': categoryOrder,
        'tagsByCategory': tagOrderByCategory,
      };

  int compareCategories(String a, String b) {
    if (a == b) return 0;

    final idxA = categoryOrder.indexOf(a);
    final idxB = categoryOrder.indexOf(b);
    if (idxA >= 0 && idxB >= 0) return idxA.compareTo(idxB);
    if (idxA >= 0) return -1;
    if (idxB >= 0) return 1;

    // Default ranking before customization: named presets -> custom -> 自定义.
    final tierA = _defaultCategoryTier(a);
    final tierB = _defaultCategoryTier(b);
    if (tierA != tierB) return tierA.compareTo(tierB);

    final lower = a.toLowerCase().compareTo(b.toLowerCase());
    if (lower != 0) return lower;
    return a.compareTo(b);
  }

  static int _defaultCategoryTier(String category) {
    final presetIdx = _namedPresets.indexOf(category);
    if (presetIdx >= 0) return presetIdx;
    if (category == kDefaultTagCategory) return _namedPresets.length + 1;
    return _namedPresets.length;
  }

  int compareTags(Tag a, Tag b) {
    final catA = effectiveTagCategory(a);
    final catB = effectiveTagCategory(b);
    final catCmp = compareCategories(catA, catB);
    if (catCmp != 0) return catCmp;

    final list = tagOrderByCategory[catA];
    if (list != null && list.isNotEmpty) {
      final idxA = list.indexOf(a.id.toInt());
      final idxB = list.indexOf(b.id.toInt());
      if (idxA >= 0 && idxB >= 0) return idxA.compareTo(idxB);
      if (idxA >= 0) return -1;
      if (idxB >= 0) return 1;
    }

    final nameLower = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (nameLower != 0) return nameLower;
    final nameExact = a.name.compareTo(b.name);
    if (nameExact != 0) return nameExact;
    return a.id.compareTo(b.id);
  }

  /// Returns whether [tags] is already sorted according to this configuration.
  bool isSorted(List<Tag> tags) {
    for (var i = 0; i + 1 < tags.length; i++) {
      if (compareTags(tags[i], tags[i + 1]) > 0) {
        return false;
      }
    }
    return true;
  }

  /// Returns [tags] sorted by category priority first, then in-category priority.
  ///
  /// Reuses [tags] as-is when already sorted to avoid per-build allocations.
  List<Tag> sortTags(List<Tag> tags) {
    if (tags.length <= 1 || isSorted(tags)) {
      return tags;
    }
    final sorted = List<Tag>.of(tags)..sort(compareTags);
    return List<Tag>.unmodifiable(sorted);
  }

  /// Distinct categories present in [tags], ordered by category priority.
  List<String> orderedCategoriesFrom(Iterable<Tag> tags) {
    final seen = <String>{};
    final result = <String>[];
    for (final tag in tags) {
      final category = effectiveTagCategory(tag);
      if (seen.add(category)) {
        result.add(category);
      }
    }
    result.sort(compareCategories);
    return result;
  }

  /// Reorders the visible categories derived from [allTags] by moving the
  /// category at [fromIndex] to final index [toIndex].
  TagOrderConfig moveCategory(
    Iterable<Tag> allTags,
    int fromIndex,
    int toIndex,
  ) {
    final active = orderedCategoriesFrom(allTags);
    if (fromIndex < 0 ||
        fromIndex >= active.length ||
        toIndex < 0 ||
        toIndex >= active.length ||
        fromIndex == toIndex) {
      return this;
    }
    final moved = active.removeAt(fromIndex);
    active.insert(toIndex, moved);

    // Keep any previously known (currently empty) categories at the tail so
    // recreating a tag there later preserves its relative order.
    final activeSet = active.toSet();
    final nextCategories = <String>[
      ...active,
      for (final category in categoryOrder)
        if (!activeSet.contains(category)) category,
    ];

    return TagOrderConfig(
      categoryOrder: List<String>.unmodifiable(nextCategories),
      tagOrderByCategory: tagOrderByCategory,
    );
  }

  /// Reorders tags inside [category] (derived from [allTags]) by moving the
  /// tag at [fromIndex] to final index [toIndex].
  TagOrderConfig moveTagInCategory(
    Iterable<Tag> allTags,
    String category,
    int fromIndex,
    int toIndex,
  ) {
    final inCategory = [
      for (final tag in allTags)
        if (effectiveTagCategory(tag) == category) tag,
    ]..sort(compareTags);
    final ids = [for (final tag in inCategory) tag.id.toInt()];
    if (fromIndex < 0 ||
        fromIndex >= ids.length ||
        toIndex < 0 ||
        toIndex >= ids.length ||
        fromIndex == toIndex) {
      return this;
    }
    final moved = ids.removeAt(fromIndex);
    ids.insert(toIndex, moved);

    final nextMap = Map<String, List<int>>.of(tagOrderByCategory);
    nextMap[category] = List<int>.unmodifiable(ids);

    return TagOrderConfig(
      categoryOrder: categoryOrder,
      tagOrderByCategory: Map<String, List<int>>.unmodifiable(nextMap),
    );
  }

  /// Removes [tagId] from category lists (or every category except [keepCategory]).
  TagOrderConfig pruneTagId(int tagId, {String? keepCategory}) {
    var changed = false;
    final nextMap = <String, List<int>>{};
    for (final entry in tagOrderByCategory.entries) {
      if (entry.key == keepCategory || !entry.value.contains(tagId)) {
        nextMap[entry.key] = entry.value;
        continue;
      }
      changed = true;
      final remaining = [
        for (final id in entry.value)
          if (id != tagId) id,
      ];
      if (remaining.isNotEmpty) {
        nextMap[entry.key] = List<int>.unmodifiable(remaining);
      }
    }
    if (!changed) return this;
    return TagOrderConfig(
      categoryOrder: categoryOrder,
      tagOrderByCategory: Map<String, List<int>>.unmodifiable(nextMap),
    );
  }
}
