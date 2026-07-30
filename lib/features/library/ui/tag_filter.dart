import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_button.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/features/library/ui/tag_manager_modal.dart';

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

  Color _parseHexColor(String hex, Color defaultColor) {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return defaultColor;
  }

  @override
  Widget build(BuildContext context) {
    final libraryProvider = context.watch<LibraryProvider>();
    context.watch<UIThemeProvider>();
    final cfg = context.tokens;
    final contentHeightFactor = _isExpanded
        ? (1 - widget.scrollCollapseFactor.clamp(0.0, 1.0))
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: cfg.bgHover,
        borderRadius: BorderRadius.circular(AetherRadius.lg),
        border: Border.all(color: cfg.borderSubtle),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AetherSpace.xl,
        vertical: AetherSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: cfg.borderSubtle,
                  borderRadius: BorderRadius.circular(AetherRadius.sm),
                ),
                padding: const EdgeInsets.all(AetherSpace.xxs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildToggleBtn(
                      '全部包含',
                      libraryProvider.filterMode == 'AND',
                      () => libraryProvider.setFilterMode('AND'),
                      cfg,
                    ),
                    _buildToggleBtn(
                      '任意包含',
                      libraryProvider.filterMode == 'OR',
                      () => libraryProvider.setFilterMode('OR'),
                      cfg,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              AetherPressable(
                onTap: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                  if (_isExpanded) {
                    widget.onExpandRequested?.call();
                  }
                },
                borderRadius: BorderRadius.circular(AetherRadius.sm),
                pressScale: AetherMotion.pressScaleSubtle,
                hoverColor: cfg.pressed,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AetherSpace.md,
                    vertical: AetherSpace.xs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sell_rounded,
                        size: AetherIconSize.sm,
                        color: cfg.textSecondary,
                      ),
                      const SizedBox(width: AetherSpace.md),
                      Text(
                        '标签过滤器',
                        style: AetherType.bodyStyle(cfg.textSecondary).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: AetherSpace.xs),
                      AnimatedRotation(
                        turns: _isExpanded ? 0.25 : 0,
                        duration: AetherMotion.duration(context, AetherMotion.fast),
                        curve: AetherMotion.out,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: AetherIconSize.md,
                          color: cfg.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (MediaQuery.sizeOf(context).width >= 768) ...[
                const SizedBox(width: AetherSpace.md),
                AetherButton.secondary(
                  label: '标签管理',
                  icon: Icons.sell_outlined,
                  size: AetherButtonSize.sm,
                  onPressed: () => TagManagerModal.show(context),
                ),
              ],
            ],
          ),
          AnimatedSize(
            duration: AetherMotion.duration(context, AetherMotion.fast),
            curve: AetherMotion.out,
            alignment: Alignment.topCenter,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: contentHeightFactor,
                child: _buildTagPool(libraryProvider, cfg),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleBtn(
    String text,
    bool isActive,
    VoidCallback onTap,
    AppThemeConfig cfg,
  ) {
    return AetherPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AetherRadius.xs),
      pressScale: AetherMotion.pressScaleSubtle,
      child: AnimatedContainer(
        duration: AetherMotion.duration(context, AetherMotion.fast),
        curve: AetherMotion.out,
        padding: const EdgeInsets.symmetric(horizontal: AetherSpace.md, vertical: AetherSpace.xs),
        decoration: BoxDecoration(
          color: isActive ? cfg.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(AetherRadius.xs),
        ),
        child: Text(
          text,
          style: AetherType.captionStyle(
            isActive ? cfg.onAccent : cfg.textSecondary,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildTagPool(LibraryProvider libraryProvider, AppThemeConfig cfg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AetherSpace.lg),
        if (libraryProvider.tags.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AetherSpace.md),
            child: Text(
              '暂无预设标签，可点击右侧标签管理新建',
              style: AetherType.bodySmStyle(cfg.textSecondary),
            ),
          )
        else
          Wrap(
            spacing: AetherSpace.md,
            runSpacing: AetherSpace.md,
            children: libraryProvider.tags.map((tag) {
              final isSelected =
                  libraryProvider.selectedTags.contains(tag.id);
              final isExcluded =
                  libraryProvider.excludedTags.contains(tag.id);

              Color tagColor = tag.color != null
                  ? _parseHexColor(tag.color!, cfg.textSecondary)
                  : cfg.textSecondary;
              if (isExcluded) {
                tagColor = cfg.danger;
              }

              final active = isSelected || isExcluded;

              return AetherPressable(
                onTap: () => libraryProvider.toggleTag(tag.id),
                borderRadius: BorderRadius.circular(AetherRadius.full),
                pressScale: AetherMotion.pressScaleSubtle,
                child: AnimatedContainer(
                  duration: AetherMotion.duration(context, AetherMotion.fast),
                  curve: AetherMotion.out,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AetherSpace.lg,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? tagColor.withValues(alpha: 0.14)
                        : cfg.bg1,
                    borderRadius: BorderRadius.circular(AetherRadius.full),
                    border: Border.all(
                      color: active ? tagColor : cfg.borderSubtle,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isExcluded) ...[
                        Icon(
                          Icons.remove_rounded,
                          size: 12,
                          color: tagColor,
                        ),
                        const SizedBox(width: AetherSpace.xs),
                      ] else ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: tagColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AetherSpace.sm),
                      ],
                      Text(
                        tag.name,
                        style: AetherType.bodySmStyle(
                          active ? cfg.textPrimary : tagColor,
                        ).copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: isExcluded
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: cfg.danger,
                          decorationThickness: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
