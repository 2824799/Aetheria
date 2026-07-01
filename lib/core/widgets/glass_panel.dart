import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';

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
    final themeProvider = context.watch<UIThemeProvider>();
    final cfg = themeProvider.currentTheme;
    
    final radius = borderRadius ?? BorderRadius.zero;
    final blurVal = blur ?? cfg.glassBlur;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurVal, sigmaY: blurVal),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: customBackgroundColor ?? cfg.bgPanel,
            borderRadius: radius,
            border: border ?? Border.all(color: cfg.border, width: 1.0),
          ),
          child: child,
        ),
      ),
    );
  }
}
