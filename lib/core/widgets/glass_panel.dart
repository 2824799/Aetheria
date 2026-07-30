import 'package:flutter/material.dart';
import 'package:aetheria/core/widgets/aether_surface.dart';

/// Backward-compatible glass panel. New code should prefer [AetherSurface].
class GlassPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final double? blur;
  final Color? customBackgroundColor;

  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius,
    this.border,
    this.padding,
    this.blur,
    this.customBackgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return AetherSurface(
      level: AetherSurfaceLevel.glass,
      borderRadius: borderRadius,
      border: border,
      padding: padding,
      blur: blur,
      color: customBackgroundColor,
      child: child,
    );
  }
}
