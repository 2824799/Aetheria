import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/motion.dart';
import 'package:aetheria/core/theme/tokens/radius.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';

/// Compact themed switch. Color-only transition; no slide bounce.
class AetherSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final String? semanticLabel;

  const AetherSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final canInteract = enabled && onChanged != null;
    final duration = AetherMotion.duration(context, AetherMotion.fast);
    final curve = AetherMotion.curve(context);

    final trackColor = !canInteract
        ? cfg.sliderTrack
        : (value ? cfg.accent : cfg.sliderTrack);
    final thumbColor = !canInteract
        ? cfg.textTertiary
        : (value ? cfg.onAccent : cfg.textSecondary);

    return Semantics(
      label: semanticLabel,
      toggled: value,
      enabled: canInteract,
      button: true,
      child: AetherPressable(
        onTap: canInteract ? () => onChanged!(!value) : null,
        enabled: canInteract,
        pressScale: AetherMotion.pressScaleSubtle,
        borderRadius: BorderRadius.circular(AetherRadius.full),
        child: AnimatedContainer(
          duration: duration,
          curve: curve,
          width: 42,
          height: 24,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(AetherRadius.full),
            border: Border.all(
              color: value && canInteract
                  ? cfg.accent.withValues(alpha: 0.35)
                  : cfg.borderSubtle,
            ),
          ),
          child: AnimatedAlign(
            duration: duration,
            curve: curve,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: thumbColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: cfg.scrim.withValues(alpha: 0.25),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings-style row: title + optional subtitle + switch.
class AetherSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final bool dense;
  final Widget? leading;

  const AetherSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.dense = false,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final canInteract = enabled && onChanged != null;
    final vPad = dense ? AetherSpace.sm : AetherSpace.md;

    return AetherPressable(
      onTap: canInteract ? () => onChanged!(!value) : null,
      enabled: canInteract,
      pressScale: 1.0,
      hoverColor: cfg.bgHover,
      pressedColor: cfg.pressed,
      borderRadius: BorderRadius.circular(AetherRadius.md),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AetherSpace.sm,
          vertical: vPad,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AetherSpace.lg),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AetherType.titleSmStyle(
                      canInteract ? cfg.textPrimary : cfg.textTertiary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AetherSpace.xxs),
                    Text(
                      subtitle!,
                      style: AetherType.bodySmStyle(cfg.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AetherSpace.lg),
            AetherSwitch(
              value: value,
              onChanged: onChanged,
              enabled: enabled,
              semanticLabel: title,
            ),
          ],
        ),
      ),
    );
  }
}
