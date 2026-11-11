import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/utils/formatting.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/features/library/ui/tag_manager_modal.dart';
import 'package:aetheria/src/rust/models/song.dart';

/// Tag filter bar above the song list.
///
/// Tapping a tag cycles it: off → required → excluded → off. The tag pool
/// folds away as the list scrolls ([scrollCollapseFactor] 0 → 1) and can be
/// folded by hand from the header.
class TagFilter extends StatefulWidget {
  const TagFilter({
    super.key,
    this.scrollCollapseFactor = 0,
    this.onExpandRequested,
  });

  final double scrollCollapseFactor;
  final VoidCallback? onExpandRequested;

  @override
  State<TagFilter> createState() => _TagFilterState();
}

class _TagFilterState extends State<TagFilter> {
  bool _isExpanded = true;

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) {
      widget.onExpandRequested?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final cfg = context.tokens;
    final poolFactor = _isExpanded
        ? 1 - widget.scrollCollapseFactor.clamp(0.0, 1.0)
        : 0.0;
    final activeCount =
        library.selectedTags.length + library.excludedTags.length;
    final isWide = MediaQuery.sizeOf(context).width >= 768;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _ExpandToggle(
              expanded: poolFactor > 0,
              activeCount: activeCount,
              onTap: _toggleExpanded,
            ),
            const SizedBox(width: AetherSpace.md),
            _MatchModeSwitch(
              matchAll: library.filterMode == 'AND',
              onChanged: (matchAll) =>
                  library.setFilterMode(matchAll ? 'AND' : 'OR'),
            ),
            const Spacer(),
            if (activeCount > 0)
              AetherButton.ghost(
                label: '清除筛选',
                size: AetherButtonSize.sm,
                onPressed: library.clearTagFilters,
              ),
            if (isWide) ...[
              const SizedBox(width: AetherSpace.xs),
              AetherButton.ghost(
                label: '管理标签',
                icon: Icons.sell_outlined,
                size: AetherButtonSize.sm,
                onPressed: () => TagManagerModal.show(context),
              ),
            ],
          ],
        ),
        // Scrolling supplies the height directly; a second layout animation
        // would trail the gesture and keep resizing the list viewport.
        ClipRect(
          child: Align(
            alignment: Alignment.topLeft,
            heightFactor: poolFactor,
            child: ExcludeFocus(
              excluding: poolFactor == 0,
              child: Padding(
                padding: const EdgeInsets.only(top: AetherSpace.md),
                child: _TagPool(library: library, cfg: cfg),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({
    required this.expanded,
    required this.activeCount,
    required this.onTap,
  });

  final bool expanded;
  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return AetherPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AetherRadius.sm),
      pressScale: AetherMotion.pressScaleSubtle,
      hoverColor: cfg.bgHover,
      tooltip: expanded ? '收起标签' : '展开标签',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AetherSpace.sm,
          vertical: AetherSpace.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: AetherMotion.duration(context, AetherMotion.fast),
              curve: AetherMotion.out,
              child: Icon(
                Icons.chevron_right_rounded,
                size: AetherIconSize.md,
                color: cfg.textTertiary,
              ),
            ),
            const SizedBox(width: AetherSpace.xs),
            Text('标签', style: AetherType.labelStyle(cfg.textSecondary)),
            if (activeCount > 0) ...[
              const SizedBox(width: AetherSpace.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: cfg.accentMuted,
                  borderRadius: BorderRadius.circular(AetherRadius.full),
                ),
                child: Text(
                  '$activeCount',
                  style: AetherType.captionStyle(
                    cfg.accent,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Whether a song must carry every required tag or just one of them.
class _MatchModeSwitch extends StatelessWidget {
  const _MatchModeSwitch({required this.matchAll, required this.onChanged});

  final bool matchAll;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AetherSpace.xxs),
      decoration: BoxDecoration(
        color: cfg.bgHover,
        borderRadius: BorderRadius.circular(AetherRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, '全部包含', matchAll, () => onChanged(true)),
          _segment(context, '任意包含', !matchAll, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    final cfg = context.tokens;
    return AetherPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AetherRadius.xs),
      pressScale: AetherMotion.pressScaleSubtle,
      child: AnimatedContainer(
        duration: AetherMotion.duration(context, AetherMotion.fast),
        curve: AetherMotion.out,
        padding: const EdgeInsets.symmetric(
          horizontal: AetherSpace.md,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: selected ? cfg.bgElevated : Colors.transparent,
          borderRadius: BorderRadius.circular(AetherRadius.xs),
          border: Border.all(
            color: selected ? cfg.borderSubtle : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: AetherType.captionStyle(
            selected ? cfg.textPrimary : cfg.textTertiary,
          ).copyWith(fontSize: AetherType.bodySm - 1),
        ),
      ),
    );
  }
}

class _TagPool extends StatelessWidget {
  const _TagPool({required this.library, required this.cfg});

  final LibraryProvider library;
  final AppThemeConfig cfg;

  @override
  Widget build(BuildContext context) {
    if (library.tags.isEmpty) {
      return Text(
        '还没有标签，可以在“管理标签”中新建',
        style: AetherType.bodySmStyle(cfg.textTertiary),
      );
    }
    return Wrap(
      spacing: AetherSpace.sm,
      runSpacing: AetherSpace.sm,
      children: [
        for (final tag in library.tags)
          _TagChip(
            tag: tag,
            isRequired: library.selectedTags.contains(tag.id),
            excluded: library.excludedTags.contains(tag.id),
            onTap: () => library.toggleTag(tag.id),
          ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.tag,
    required this.isRequired,
    required this.excluded,
    required this.onTap,
  });

  final Tag tag;
  final bool isRequired;
  final bool excluded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final active = isRequired || excluded;
    final color = excluded
        ? cfg.danger
        : parseTagColor(tag.color, cfg.textSecondary);

    return AetherPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AetherRadius.full),
      pressScale: AetherMotion.pressScaleSubtle,
      hoverColor: active ? null : cfg.bgHover,
      child: AnimatedContainer(
        duration: AetherMotion.duration(context, AetherMotion.fast),
        curve: AetherMotion.out,
        padding: const EdgeInsets.symmetric(
          horizontal: AetherSpace.lg,
          vertical: AetherSpace.xs,
        ),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(AetherRadius.full),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.7) : cfg.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (excluded)
              Icon(Icons.remove_rounded, size: AetherIconSize.xs, color: color)
            else
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            const SizedBox(width: AetherSpace.sm),
            Text(
              tag.name,
              style:
                  AetherType.bodySmStyle(
                    active ? cfg.textPrimary : cfg.textSecondary,
                  ).copyWith(
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    decoration: excluded ? TextDecoration.lineThrough : null,
                    decorationColor: cfg.danger,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
