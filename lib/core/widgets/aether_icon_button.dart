import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/icon_size.dart';
import 'package:aetheria/core/theme/tokens/motion.dart';
import 'package:aetheria/core/theme/tokens/radius.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';

class AetherIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;
  final Color? backgroundColor;
  final String? tooltip;
  final bool selected;
  final bool primary;

  const AetherIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 36,
    this.iconSize = AetherIconSize.lg,
    this.color,
    this.backgroundColor,
    this.tooltip,
    this.selected = false,
    this.primary = false,
  });

  /// Dense control used in lists / version rows.
  const AetherIconButton.dense({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.backgroundColor,
    this.tooltip,
    this.selected = false,
  })  : size = 28,
        iconSize = AetherIconSize.sm,
        primary = false;

  /// Large transport control (skip / mode) on mobile player.
  const AetherIconButton.transport({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.backgroundColor,
    this.tooltip,
    this.selected = false,
  })  : size = 44,
        iconSize = AetherIconSize.xxl,
        primary = false;

  /// Filled circular primary play/pause control.
  const AetherIconButton.play({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  })  : size = 56,
        iconSize = 26,
        color = null,
        backgroundColor = null,
        selected = false,
        primary = true;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final radius = BorderRadius.circular(primary ? AetherRadius.full : AetherRadius.md);
    final fg = color ??
        (primary
            ? cfg.onAccent
            : (selected ? cfg.accent : cfg.textSecondary));
    final bg = backgroundColor ??
        (primary
            ? cfg.accent
            : (selected ? cfg.accentMuted : Colors.transparent));

    return AetherPressable(
      onTap: onPressed,
      enabled: onPressed != null,
      borderRadius: radius,
      pressScale: AetherMotion.pressScale,
      hoverColor: primary ? null : cfg.bgHover,
      pressedColor: primary ? null : cfg.pressed,
      tooltip: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: cfg.accentGlow,
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Icon(icon, size: iconSize, color: fg),
        ),
      ),
    );
  }
}
