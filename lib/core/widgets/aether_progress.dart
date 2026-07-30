import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/radius.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';

/// Themed circular / linear progress indicators.
class AetherProgress extends StatelessWidget {
  final AetherProgressType type;
  final double? value;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? trackColor;
  final String? semanticsLabel;

  const AetherProgress.circular({
    super.key,
    this.value,
    this.size = 22,
    this.strokeWidth = 2.4,
    this.color,
    this.trackColor,
    this.semanticsLabel,
  }) : type = AetherProgressType.circular;

  const AetherProgress.linear({
    super.key,
    this.value,
    this.size = 4,
    this.strokeWidth = 4,
    this.color,
    this.trackColor,
    this.semanticsLabel,
  }) : type = AetherProgressType.linear;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final fg = color ?? cfg.accent;
    final bg = trackColor ?? cfg.sliderTrack;

    switch (type) {
      case AetherProgressType.circular:
        return SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: value,
            strokeWidth: strokeWidth,
            color: fg,
            backgroundColor: bg,
            strokeCap: StrokeCap.round,
            semanticsLabel: semanticsLabel,
          ),
        );
      case AetherProgressType.linear:
        return ClipRRect(
          borderRadius: BorderRadius.circular(AetherRadius.full),
          child: SizedBox(
            height: size,
            child: LinearProgressIndicator(
              value: value,
              minHeight: size,
              color: fg,
              backgroundColor: bg,
              borderRadius: BorderRadius.circular(AetherRadius.full),
              semanticsLabel: semanticsLabel,
            ),
          ),
        );
    }
  }
}

enum AetherProgressType { circular, linear }

/// Compact inline spinner + optional label (for buttons / toolbars).
class AetherInlineLoading extends StatelessWidget {
  final String? label;
  final double size;

  const AetherInlineLoading({
    super.key,
    this.label,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AetherProgress.circular(size: size, strokeWidth: 2),
        if (label != null) ...[
          const SizedBox(width: AetherSpace.sm),
          Text(label!, style: AetherType.bodySmStyle(cfg.textSecondary)),
        ],
      ],
    );
  }
}
