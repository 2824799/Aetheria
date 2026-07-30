import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/icon_size.dart';
import 'package:aetheria/core/theme/tokens/motion.dart';
import 'package:aetheria/core/theme/tokens/radius.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';

/// Unified list row for menus, settings, and context actions.
class AetherListTile extends StatelessWidget {
  final Widget? leading;
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final bool selected;
  final bool enabled;
  final bool dense;
  final bool destructive;
  final bool warning;
  final EdgeInsetsGeometry? padding;
  final String? tooltip;

  const AetherListTile({
    super.key,
    this.leading,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.selected = false,
    this.enabled = true,
    this.dense = false,
    this.destructive = false,
    this.warning = false,
    this.padding,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final canInteract = enabled && (onTap != null || onLongPress != null);
    final radius = BorderRadius.circular(AetherRadius.md);
    final titleColor = destructive
        ? cfg.danger
        : warning
            ? cfg.warning
            : (selected ? cfg.accent : (canInteract ? cfg.textPrimary : cfg.textTertiary));
    final iconColor = destructive
        ? cfg.danger
        : warning
            ? cfg.warning
            : (selected ? cfg.accent : cfg.textSecondary);
    final vPad = dense ? AetherSpace.sm : AetherSpace.md;
    final hPad = dense ? AetherSpace.md : AetherSpace.lg;

    final leadingWidget = leading ??
        (icon != null
            ? Icon(icon, size: AetherIconSize.lg, color: iconColor)
            : null);

    return AetherPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onSecondaryTap,
      enabled: canInteract,
      borderRadius: radius,
      pressScale: AetherMotion.pressScaleSubtle,
      hoverColor: cfg.bgHover,
      pressedColor: cfg.pressed,
      tooltip: tooltip,
      child: AnimatedContainer(
        duration: AetherMotion.duration(context, AetherMotion.fast),
        curve: AetherMotion.curve(context),
        padding: padding ??
            EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          color: selected ? cfg.selection : Colors.transparent,
          borderRadius: radius,
        ),
        child: Row(
          children: [
            if (leadingWidget != null) ...[
              leadingWidget,
              SizedBox(width: dense ? AetherSpace.md : AetherSpace.lg),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dense
                        ? AetherType.bodyStyle(titleColor).copyWith(
                              fontWeight: FontWeight.w600,
                            )
                        : AetherType.titleSmStyle(titleColor),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AetherSpace.xxs),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AetherType.bodySmStyle(cfg.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AetherSpace.md),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
