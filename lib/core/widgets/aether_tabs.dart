import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/motion.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';

class AetherTabItem {
  final String id;
  final String label;

  const AetherTabItem({required this.id, required this.label});
}

/// Underline tab bar for detail sheets and dense tool surfaces.
///
/// The indicator sits on the edge that touches the content: the bottom edge
/// by default, the top edge ([indicatorAtTop]) for bars placed under their
/// content. It changes colour only — no layout width animation.
class AetherTabBar extends StatelessWidget {
  final List<AetherTabItem> tabs;
  final String value;
  final ValueChanged<String> onChanged;
  final bool expanded;
  final double fontSize;
  final bool indicatorAtTop;

  const AetherTabBar({
    super.key,
    required this.tabs,
    required this.value,
    required this.onChanged,
    this.expanded = true,
    this.fontSize = AetherType.bodySm,
    this.indicatorAtTop = false,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final children = <Widget>[];
    for (final tab in tabs) {
      final active = tab.id == value;
      final indicator = BorderSide(
        color: active ? cfg.accent : Colors.transparent,
        width: 2,
      );
      final child = AetherPressable(
        onTap: () {
          if (tab.id != value) onChanged(tab.id);
        },
        pressScale: AetherMotion.pressScaleSubtle,
        child: AnimatedContainer(
          duration: AetherMotion.duration(context, AetherMotion.fast),
          curve: AetherMotion.curve(context),
          padding: const EdgeInsets.symmetric(
            horizontal: AetherSpace.sm,
            vertical: AetherSpace.lg - 1,
          ),
          decoration: BoxDecoration(
            border: indicatorAtTop
                ? Border(top: indicator)
                : Border(bottom: indicator),
          ),
          alignment: Alignment.center,
          child: Text(
            tab.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.2,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? cfg.textPrimary : cfg.textSecondary,
            ),
          ),
        ),
      );
      children.add(expanded ? Expanded(child: child) : child);
    }

    return Row(children: children);
  }
}
