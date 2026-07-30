import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/motion.dart';
import 'package:aetheria/core/theme/tokens/radius.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';

enum AetherButtonVariant { primary, secondary, ghost, danger }
enum AetherButtonSize { sm, md, lg }

class AetherButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AetherButtonVariant variant;
  final AetherButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool expanded;
  final String? tooltip;

  const AetherButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AetherButtonVariant.primary,
    this.size = AetherButtonSize.md,
    this.icon,
    this.loading = false,
    this.expanded = false,
    this.tooltip,
  });

  const AetherButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = AetherButtonSize.md,
    this.icon,
    this.loading = false,
    this.expanded = false,
    this.tooltip,
  }) : variant = AetherButtonVariant.primary;

  const AetherButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = AetherButtonSize.md,
    this.icon,
    this.loading = false,
    this.expanded = false,
    this.tooltip,
  }) : variant = AetherButtonVariant.secondary;

  const AetherButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = AetherButtonSize.md,
    this.icon,
    this.loading = false,
    this.expanded = false,
    this.tooltip,
  }) : variant = AetherButtonVariant.ghost;

  const AetherButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = AetherButtonSize.md,
    this.icon,
    this.loading = false,
    this.expanded = false,
    this.tooltip,
  }) : variant = AetherButtonVariant.danger;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final enabled = onPressed != null && !loading;

    final double height;
    final double fontSize;
    final double hPad;
    final double iconSize;
    switch (size) {
      case AetherButtonSize.sm:
        height = 30;
        fontSize = AetherType.bodySm;
        hPad = AetherSpace.md;
        iconSize = 14;
      case AetherButtonSize.md:
        height = AetherSpace.controlHeight;
        fontSize = AetherType.body;
        hPad = AetherSpace.xl;
        iconSize = 16;
      case AetherButtonSize.lg:
        height = 44;
        fontSize = AetherType.titleSm;
        hPad = AetherSpace.xxl;
        iconSize = 18;
    }

    late final Color bg;
    late final Color fg;
    late final Color borderColor;
    switch (variant) {
      case AetherButtonVariant.primary:
        bg = cfg.accent;
        fg = cfg.onAccent;
        borderColor = Colors.transparent;
      case AetherButtonVariant.secondary:
        bg = cfg.bgHover;
        fg = cfg.textPrimary;
        borderColor = cfg.borderSubtle;
      case AetherButtonVariant.ghost:
        bg = Colors.transparent;
        fg = cfg.textSecondary;
        borderColor = Colors.transparent;
      case AetherButtonVariant.danger:
        bg = cfg.danger;
        fg = cfg.onAccent;
        borderColor = Colors.transparent;
    }

    final radius = BorderRadius.circular(AetherRadius.xl);
    final child = Container(
      height: height,
      width: expanded ? double.infinity : null,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: Border.all(color: borderColor),
        boxShadow: variant == AetherButtonVariant.primary
            ? [
                BoxShadow(
                  color: cfg.accentGlow,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading) ...[
            SizedBox(
              width: iconSize,
              height: iconSize,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: fg,
              ),
            ),
            const SizedBox(width: AetherSpace.sm),
          ] else if (icon != null) ...[
            Icon(icon, size: iconSize, color: fg),
            const SizedBox(width: AetherSpace.sm),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );

    return AetherPressable(
      enabled: enabled,
      onTap: enabled ? onPressed : null,
      borderRadius: radius,
      pressScale: AetherMotion.pressScaleSubtle,
      hoverColor: variant == AetherButtonVariant.ghost ? cfg.bgHover : null,
      tooltip: tooltip,
      semanticLabel: tooltip,
      child: child,
    );
  }
}
