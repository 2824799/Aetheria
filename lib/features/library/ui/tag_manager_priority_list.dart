import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/utils/formatting.dart';
import 'package:aetheria/core/utils/tag_ordering.dart';
import 'package:aetheria/core/widgets/aether_icon_button.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/src/rust/models/song.dart';

typedef TagCategoryGroup = ({String category, List<Tag> tags});

/// Groups already-ordered tags into contiguous category sections.
List<TagCategoryGroup> groupOrderedTags(List<Tag> orderedTags) {
  final groups = <String, List<Tag>>{};
  for (final tag in orderedTags) {
    groups.putIfAbsent(effectiveTagCategory(tag), () => []).add(tag);
  }
  return [
    for (final entry in groups.entries) (category: entry.key, tags: entry.value),
  ];
}

Widget _dragProxyDecorator(
  Widget child,
  AppThemeConfig cfg,
) {
  return Material(
    color: Colors.transparent,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: cfg.bgElevated,
        borderRadius: BorderRadius.circular(AetherRadius.md),
        border: Border.all(color: cfg.borderStrong),
      ),
      child: child,
    ),
  );
}

/// Reorderable list of category groups for the desktop side pane.
class TagPriorityList extends StatelessWidget {
  const TagPriorityList({
    super.key,
    required this.groups,
    required this.editingTagId,
    required this.onMoveCategory,
    required this.onMoveTag,
    required this.onEditTag,
    required this.onDeleteTag,
  });

  final List<TagCategoryGroup> groups;
  final PlatformInt64? editingTagId;
  final void Function(int fromIndex, int toIndex) onMoveCategory;
  final void Function(String category, int fromIndex, int toIndex) onMoveTag;
  final ValueChanged<Tag> onEditTag;
  final ValueChanged<Tag> onDeleteTag;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AetherSpace.xl,
        0,
        AetherSpace.xl,
        AetherSpace.xl,
      ),
      buildDefaultDragHandles: false,
      proxyDecorator: (child, _, _) => _dragProxyDecorator(child, cfg),
      itemCount: groups.length,
      onReorderItem: onMoveCategory,
      itemBuilder: (context, index) => _CategoryGroupCard(
        key: ValueKey('tag-cat-${groups[index].category}'),
        group: groups[index],
        categoryIndex: index,
        categoryCount: groups.length,
        editingTagId: editingTagId,
        onMoveCategory: onMoveCategory,
        onMoveTag: onMoveTag,
        onEditTag: onEditTag,
        onDeleteTag: onDeleteTag,
      ),
    );
  }
}

/// Sliver variant for narrow layouts that scroll editor + priority groups
/// inside a single vertical container.
class SliverTagPriorityList extends StatelessWidget {
  const SliverTagPriorityList({
    super.key,
    required this.groups,
    required this.editingTagId,
    required this.onMoveCategory,
    required this.onMoveTag,
    required this.onEditTag,
    required this.onDeleteTag,
  });

  final List<TagCategoryGroup> groups;
  final PlatformInt64? editingTagId;
  final void Function(int fromIndex, int toIndex) onMoveCategory;
  final void Function(String category, int fromIndex, int toIndex) onMoveTag;
  final ValueChanged<Tag> onEditTag;
  final ValueChanged<Tag> onDeleteTag;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AetherSpace.xl,
        AetherSpace.lg,
        AetherSpace.xl,
        AetherSpace.xl,
      ),
      sliver: SliverReorderableList(
        itemCount: groups.length,
        proxyDecorator: (child, _, _) => _dragProxyDecorator(child, cfg),
        onReorderItem: onMoveCategory,
        itemBuilder: (context, index) => _CategoryGroupCard(
          key: ValueKey('tag-cat-${groups[index].category}'),
          group: groups[index],
          categoryIndex: index,
          categoryCount: groups.length,
          editingTagId: editingTagId,
          onMoveCategory: onMoveCategory,
          onMoveTag: onMoveTag,
          onEditTag: onEditTag,
          onDeleteTag: onDeleteTag,
        ),
      ),
    );
  }
}

class _CategoryGroupCard extends StatelessWidget {
  const _CategoryGroupCard({
    super.key,
    required this.group,
    required this.categoryIndex,
    required this.categoryCount,
    required this.editingTagId,
    required this.onMoveCategory,
    required this.onMoveTag,
    required this.onEditTag,
    required this.onDeleteTag,
  });

  final TagCategoryGroup group;
  final int categoryIndex;
  final int categoryCount;
  final PlatformInt64? editingTagId;
  final void Function(int fromIndex, int toIndex) onMoveCategory;
  final void Function(String category, int fromIndex, int toIndex) onMoveTag;
  final ValueChanged<Tag> onEditTag;
  final ValueChanged<Tag> onDeleteTag;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final canMoveUp = categoryIndex > 0;
    final canMoveDown = categoryIndex + 1 < categoryCount;

    return Container(
      margin: const EdgeInsets.only(bottom: AetherSpace.md),
      padding: const EdgeInsets.fromLTRB(
        AetherSpace.sm,
        AetherSpace.xs,
        AetherSpace.sm,
        AetherSpace.xs,
      ),
      decoration: BoxDecoration(
        color: cfg.bg1,
        borderRadius: BorderRadius.circular(AetherRadius.md),
        border: Border.all(color: cfg.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AetherSpace.xs,
              vertical: AetherSpace.xs,
            ),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: categoryIndex,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Tooltip(
                      message: '拖拽调整种类优先度',
                      child: Padding(
                        padding: const EdgeInsets.all(AetherSpace.xs),
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: AetherIconSize.md,
                          color: cfg.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AetherSpace.xs),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          group.category,
                          style: AetherType.labelStyle(cfg.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AetherSpace.sm),
                      Text(
                        '${group.tags.length}',
                        style: AetherType.captionStyle(cfg.textTertiary),
                      ),
                    ],
                  ),
                ),
                AetherIconButton.dense(
                  icon: Icons.keyboard_arrow_up_rounded,
                  tooltip: '上移种类 ${group.category}',
                  color: canMoveUp ? cfg.textSecondary : cfg.textTertiary,
                  onPressed: canMoveUp
                      ? () => onMoveCategory(categoryIndex, categoryIndex - 1)
                      : null,
                ),
                AetherIconButton.dense(
                  icon: Icons.keyboard_arrow_down_rounded,
                  tooltip: '下移种类 ${group.category}',
                  color: canMoveDown ? cfg.textSecondary : cfg.textTertiary,
                  onPressed: canMoveDown
                      ? () => onMoveCategory(categoryIndex, categoryIndex + 1)
                      : null,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cfg.divider),
          const SizedBox(height: AetherSpace.xxs),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator: (child, _, _) => _dragProxyDecorator(child, cfg),
            itemCount: group.tags.length,
            onReorderItem: (oldIndex, newIndex) =>
                onMoveTag(group.category, oldIndex, newIndex),
            itemBuilder: (context, tagIndex) {
              final tag = group.tags[tagIndex];
              return _TagPriorityRow(
                key: ValueKey('tag-item-${tag.id}'),
                tag: tag,
                index: tagIndex,
                siblingCount: group.tags.length,
                editing: tag.id == editingTagId,
                onMoveUp: tagIndex > 0
                    ? () => onMoveTag(group.category, tagIndex, tagIndex - 1)
                    : null,
                onMoveDown: tagIndex + 1 < group.tags.length
                    ? () => onMoveTag(group.category, tagIndex, tagIndex + 1)
                    : null,
                onEdit: () => onEditTag(tag),
                onDelete: () => onDeleteTag(tag),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TagPriorityRow extends StatelessWidget {
  const _TagPriorityRow({
    super.key,
    required this.tag,
    required this.index,
    required this.siblingCount,
    required this.editing,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onEdit,
    required this.onDelete,
  });

  final Tag tag;
  final int index;
  final int siblingCount;
  final bool editing;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final radius = BorderRadius.circular(AetherRadius.md);
    return AetherPressable(
      onTap: onEdit,
      borderRadius: radius,
      pressScale: 1,
      semanticLabel: '编辑标签 ${tag.name}',
      child: Container(
        height: 40,
        padding: const EdgeInsets.only(
          left: AetherSpace.xs,
          right: AetherSpace.xxs,
        ),
        decoration: BoxDecoration(
          color: editing ? cfg.accentMuted : null,
          borderRadius: radius,
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: MouseRegion(
                cursor: siblingCount > 1
                    ? SystemMouseCursors.grab
                    : MouseCursor.defer,
                child: Tooltip(
                  message: '拖拽调整标签优先度',
                  child: Padding(
                    padding: const EdgeInsets.all(AetherSpace.xs),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: AetherIconSize.sm,
                      color: cfg.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AetherSpace.sm),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: parseTagColor(tag.color, cfg.textTertiary),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AetherSpace.md),
            Expanded(
              child: Text(
                tag.name,
                style: AetherType.bodyStyle(
                  editing ? cfg.accent : cfg.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AetherIconButton.dense(
              icon: Icons.keyboard_arrow_up_rounded,
              tooltip: '上移标签 ${tag.name}',
              color: onMoveUp != null ? cfg.textSecondary : cfg.textTertiary,
              onPressed: onMoveUp,
            ),
            AetherIconButton.dense(
              icon: Icons.keyboard_arrow_down_rounded,
              tooltip: '下移标签 ${tag.name}',
              color: onMoveDown != null ? cfg.textSecondary : cfg.textTertiary,
              onPressed: onMoveDown,
            ),
            AetherIconButton.dense(
              icon: Icons.delete_outline_rounded,
              color: cfg.textTertiary,
              tooltip: '删除标签',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
