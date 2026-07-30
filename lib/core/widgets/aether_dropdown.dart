import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/motion.dart';
import 'package:aetheria/core/theme/tokens/radius.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';
import 'package:aetheria/core/widgets/aether_menu.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';

class AetherDropdownItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const AetherDropdownItem({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// Compact dropdown built on [showAetherMenu] for form rows.
class AetherDropdown<T> extends StatelessWidget {
  final T? value;
  final List<AetherDropdownItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hintText;
  final double? width;
  final double height;
  final bool enabled;

  const AetherDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hintText,
    this.width,
    this.height = AetherSpace.controlHeight,
    this.enabled = true,
  });

  AetherDropdownItem<T>? get _selected {
    for (final item in items) {
      if (item.value == value) return item;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    if (!enabled || onChanged == null || items.isEmpty) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final selected = await showAetherMenu<T>(
      context: context,
      globalPosition: Offset(origin.dx, origin.dy + box.size.height + 4),
      minWidth: box.size.width,
      maxWidth: (box.size.width * 1.4).clamp(180.0, 360.0),
      items: [
        for (final item in items)
          AetherMenuItem<T>(
            value: item.value,
            label: item.label,
            icon: item.icon,
          ),
      ],
    );
    if (selected != null) {
      onChanged?.call(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final selected = _selected;
    final label = selected?.label ?? hintText ?? '请选择';
    final labelColor = selected == null ? cfg.textTertiary : cfg.textPrimary;

    return SizedBox(
      width: width,
      height: height,
      child: AetherPressable(
        enabled: enabled && onChanged != null,
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(AetherRadius.md),
        pressScale: AetherMotion.pressScaleSubtle,
        hoverColor: cfg.bgHover,
        pressedColor: cfg.pressed,
        child: AetherSurface(
          level: AetherSurfaceLevel.flat,
          color: cfg.bgHover,
          borderRadius: BorderRadius.circular(AetherRadius.md),
          border: Border.all(color: cfg.borderSubtle),
          padding: const EdgeInsets.symmetric(horizontal: AetherSpace.lg),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AetherType.bodyStyle(labelColor),
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: cfg.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
