import 'package:flutter/widgets.dart';

/// Motion budget for a quiet daily-use music workstation.
///
/// Rules (from design skills):
/// - UI under ~300ms
/// - enter uses ease-out; exit is faster
/// - keyboard / ultra-high-frequency actions: no motion
/// - press feedback is short and interruptible
/// - respect [MediaQuery.disableAnimationsOf]
class AetherMotion {
  AetherMotion._();

  static const Duration press = Duration(milliseconds: 120);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration panel = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 280);

  /// First tooltip show delay. Subsequent tooltips should skip delay at call site.
  static const Duration tooltipDelay = Duration(milliseconds: 400);

  /// Multiply enter duration for exits.
  static const double exitFactor = 0.7;

  static Duration exit(Duration enter) {
    final ms = (enter.inMilliseconds * exitFactor).round();
    return Duration(milliseconds: ms.clamp(90, enter.inMilliseconds));
  }

  /// Whether the platform/user asked to minimize motion.
  static bool reduce(BuildContext context) {
    return MediaQuery.disableAnimationsOf(context);
  }

  /// Returns [Duration.zero] when reduced motion is on.
  static Duration duration(BuildContext context, Duration normal) {
    return reduce(context) ? Duration.zero : normal;
  }

  /// Exit duration with reduced-motion support.
  static Duration exitOf(BuildContext context, Duration enter) {
    if (reduce(context)) return Duration.zero;
    return exit(enter);
  }

  /// Snappy ease-out for most UI entrances / state changes.
  static const Curve out = Curves.easeOutCubic;

  /// Soft out for panels / sheets.
  static const Curve outQuart = Curves.easeOutQuart;

  /// Only for non-gesture symmetric transitions.
  static const Curve inOut = Curves.easeInOutCubic;

  /// Linear / instant when reduced; otherwise [out].
  static Curve curve(BuildContext context, [Curve normal = out]) {
    return reduce(context) ? Curves.linear : normal;
  }

  /// Press scale targets. Never animate from scale(0).
  static const double pressScale = 0.97;
  static const double pressScaleSubtle = 0.98;

  /// Modal/popover enter scale floor (with opacity).
  static const double popoverFromScale = 0.96;
  static const double modalFromScale = 0.96;

  /// Enter scale when reduced motion is preferred (no zoom).
  static double fromScale(BuildContext context, [double normal = modalFromScale]) {
    return reduce(context) ? 1.0 : normal;
  }
}
