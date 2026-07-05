import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/library_provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/features/library/ui/tag_manager_modal.dart';

class TagFilter extends StatefulWidget {
  const TagFilter({super.key});

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
    final themeProvider = context.watch<UIThemeProvider>();
    final cfg = themeProvider.currentTheme;

    return Container(
      decoration: BoxDecoration(
        color: cfg.bgHover,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cfg.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // AND / OR toggles
              Container(
                decoration: BoxDecoration(
                  color: cfg.border,
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildToggleBtn(
                      '全部包含',
                      libraryProvider.filterMode == 'AND',
                      () {
                        libraryProvider.setFilterMode('AND');
                      },
                      cfg,
                    ),
                    _buildToggleBtn(
                      '任意包含',
                      libraryProvider.filterMode == 'OR',
                      () {
                        libraryProvider.setFilterMode('OR');
                      },
                      cfg,
                    ),
                  ],
                ),
              ),

              // Title Expand/Collapse
              InkWell(
                onTap: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sell, size: 14, color: cfg.textSub),
                      const SizedBox(width: 8),
                      Text(
                        '标签过滤器',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cfg.textSub,
                          fontFamily: 'Outfit',
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _isExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: 16,
                        color: cfg.textSub,
                      ),
                    ],
                  ),
                ),
              ),

              // Tag Manager Button
              if (MediaQuery.of(context).size.width >= 768)
                _buildTagManagerButton(context, cfg),
            ],
          ),

          // Collapsible Tag Chips Pool
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                libraryProvider.tags.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '暂无预设标签，可点击右侧标签管理新建',
                          style: TextStyle(color: cfg.textSub, fontSize: 12),
                        ),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: libraryProvider.tags.map((tag) {
                          final isSelected = libraryProvider.selectedTags
                              .contains(tag.id);
                          final isExcluded = libraryProvider.excludedTags
                              .contains(tag.id);

                          Color tagColor = tag.color != null
                              ? _parseHexColor(tag.color!, cfg.textSub)
                              : cfg.textSub;

                          if (isExcluded) {
                            tagColor = Colors.redAccent;
                          }

                          return InkWell(
                            onTap: () => libraryProvider.toggleTag(tag.id),
                            borderRadius: BorderRadius.circular(14),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: (isSelected || isExcluded)
                                    ? cfg.bgHover
                                    : cfg.bgPanel,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: (isSelected || isExcluded)
                                      ? tagColor
                                      : cfg.border,
                                  width: 1.0,
                                ),
                                boxShadow: (isSelected || isExcluded)
                                    ? [
                                        BoxShadow(
                                          color: tagColor.withOpacity(0.25),
                                          blurRadius: 8,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: tagColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    tag.name,
                                    style: TextStyle(
                                      color: (isSelected || isExcluded)
                                          ? cfg.textMain
                                          : tagColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'Outfit',
                                      decoration: isExcluded
                                          ? TextDecoration.lineThrough
                                          : null,
                                      decorationColor: Colors.redAccent,
                                      decorationThickness: 2.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
              ],
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? cfg.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.white : cfg.textSub,
            fontFamily: 'Outfit',
          ),
        ),
      ),
    );
  }

  Widget _buildTagManagerButton(BuildContext context, AppThemeConfig cfg) {
    return Material(
      color: cfg.border,
      borderRadius: BorderRadius.circular(7),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => TagManagerModal.show(context),
        child: SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sell_outlined, size: 13, color: cfg.textMain),
                const SizedBox(width: 6),
                Text(
                  '标签管理',
                  style: TextStyle(
                    fontSize: 11,
                    color: cfg.textMain,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
