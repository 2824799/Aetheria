import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/app_theme_config.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/radius.dart';

enum AetherSurfaceLevel { flat, panel, elevated, overlay, glass }

/// Unified surface primitive. Prefer this over ad-hoc Container + blur.
class AetherSurface extends StatelessWidget {
  final Widget child;
  final AetherSurfaceLevel level;
  final BorderRadius? borderRadius;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final Color? color;
  final double? blur;
  final List<BoxShadow>? boxShadow;
  final Clip clipBehavior;

  const AetherSurface({
    super.key,
    required this.child,
    this.level = AetherSurfaceLevel.panel,
    this.borderRadius,
    this.border,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.color,
    this.blur,
    this.boxShadow,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final radius = borderRadius ?? BorderRadius.circular(AetherRadius.lg);
    final resolved = _resolve(cfg);
    final effectiveBorder = border ??
        Border.all(color: resolved.borderColor, width: resolved.borderWidth);

    Widget content = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? resolved.color,
        borderRadius: radius,
        border: effectiveBorder,
        boxShadow: boxShadow ?? resolved.shadows,
      ),
      child: child,
    );

    if (resolved.useBlur) {
      final sigma = blur ?? cfg.glassBlurDefault;
      content = ClipRRect(
        borderRadius: radius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: content,
        ),
      );
    } else if (borderRadius != null || level != AetherSurfaceLevel.flat) {
      content = ClipRRect(
        borderRadius: radius,
        clipBehavior: clipBehavior,
        child: content,
      );
    }

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }
    return content;
  }

  _SurfaceStyle _resolve(AppThemeConfig cfg) {
    switch (level) {
      case AetherSurfaceLevel.flat:
        return _SurfaceStyle(
          color: cfg.bgSolid.withValues(alpha: 0.0),
          borderColor: Colors.transparent,
          borderWidth: 0,
          useBlur: false,
        );
      case AetherSurfaceLevel.panel:
        return _SurfaceStyle(
          color: cfg.bgPanel,
          borderColor: cfg.borderSubtle,
          borderWidth: 1,
          useBlur: false,
        );
      case AetherSurfaceLevel.elevated:
        return _SurfaceStyle(
          color: cfg.bgElevated,
          borderColor: cfg.borderSubtle,
          borderWidth: 1,
          useBlur: false,
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: cfg.brightness == Brightness.dark ? 0.28 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        );
      case AetherSurfaceLevel.overlay:
        return _SurfaceStyle(
          color: cfg.bgPopover,
          borderColor: cfg.borderStrong,
          borderWidth: 1,
          useBlur: false,
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: cfg.brightness == Brightness.dark ? 0.4 : 0.12),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        );
      case AetherSurfaceLevel.glass:
        return _SurfaceStyle(
          color: cfg.bgPanel.withValues(alpha: 0.86),
          borderColor: cfg.borderSubtle,
          borderWidth: 1,
          useBlur: true,
        );
    }
  }
}

class _SurfaceStyle {
  final Color color;
  final Color borderColor;
  final double borderWidth;
  final bool useBlur;
  final List<BoxShadow>? shadows;

  const _SurfaceStyle({
    required this.color,
    required this.borderColor,
    required this.borderWidth,
    required this.useBlur,
    this.shadows,
  });
}
