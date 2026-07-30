import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/motion.dart';
import 'package:aetheria/core/theme/tokens/radius.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';

enum AetherChipState { idle, selected, include, exclude }

class AetherChip extends StatelessWidget {
  final String label;
  final AetherChipState state;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Widget? leading;
  final bool compact;

  const AetherChip({
    super.key,
    required this.label,
    this.state = AetherChipState.idle,
    this.onTap,
    this.onLongPress,
    this.color,
    this.leading,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final accent = color ?? cfg.accent;

    late final Color bg;
    late final Color fg;
    late final Color border;

    switch (state) {
      case AetherChipState.idle:
        bg = cfg.bgHover;
        fg = cfg.textSecondary;
        border = cfg.borderSubtle;
      case AetherChipState.selected:
      case AetherChipState.include:
        bg = accent.withValues(alpha: 0.18);
        fg = accent;
        border = accent.withValues(alpha: 0.45);
      case AetherChipState.exclude:
        bg = cfg.dangerMuted;
        fg = cfg.danger;
        border = cfg.danger.withValues(alpha: 0.45);
    }

    final radius = BorderRadius.circular(AetherRadius.full);
    return AetherPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: radius,
      pressScale: AetherMotion.pressScaleSubtle,
      child: AnimatedContainer(
        duration: AetherMotion.duration(context, AetherMotion.fast),
        curve: AetherMotion.curve(context),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AetherSpace.md : AetherSpace.lg,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state == AetherChipState.exclude) ...[
              Icon(Icons.remove, size: 12, color: fg),
              const SizedBox(width: 4),
            ] else if (leading != null) ...[
              leading!,
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: AetherType.captionStyle(fg).copyWith(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w600,
                decoration: state == AetherChipState.exclude
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AetherBadge extends StatelessWidget {
  final String label;
  final Color? color;
  final bool soft;

  const AetherBadge({
    super.key,
    required this.label,
    this.color,
    this.soft = true,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final c = color ?? cfg.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: soft ? c.withValues(alpha: 0.14) : c,
        borderRadius: BorderRadius.circular(AetherRadius.sm),
        border: Border.all(color: c.withValues(alpha: soft ? 0.35 : 0.0)),
      ),
      child: Text(
        label,
        style: AetherType.captionStyle(soft ? c : cfg.onAccent).copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
