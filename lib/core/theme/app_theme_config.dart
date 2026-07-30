import 'package:flutter/material.dart';

enum AppThemeType { dark, light, pink }

/// Full visual config for one theme.
///
/// Legacy getters (`textMain`, `bgPanel`, …) stay stable so existing screens
/// keep compiling while new code migrates to semantic names.
class AppThemeConfig {
  final Gradient bgApp;
  final Color bgPanel;
  final Color bgHover;
  final Color border;
  final Color sliderTrack;
  final Color textMain;
  final Color textSub;
  final Color accent;
  final Color accentHover;
  final Color accentGlow;
  final double glassBlur;
  final double ambientOpacity;
  final Brightness brightness;

  // Expanded surface / content tokens
  final Color bgSolid;
  final Color bgElevated;
  final Color bgPopover;
  final Color textTertiary;
  final Color textInverse;
  final Color borderStrong;
  final Color borderFocus;
  final Color accentMuted;
  final Color onAccent;
  final Color danger;
  final Color dangerHover;
  final Color dangerMuted;
  final Color warning;
  final Color success;
  final Color info;
  final Color scrim;
  final Color selection;
  final Color pressed;
  final Color overlayStroke;
  final double glassBlurDefault;

  const AppThemeConfig({
    required this.bgApp,
    required this.bgPanel,
    required this.bgHover,
    required this.border,
    required this.sliderTrack,
    required this.textMain,
    required this.textSub,
    required this.accent,
    required this.accentHover,
    required this.accentGlow,
    required this.glassBlur,
    required this.ambientOpacity,
    required this.brightness,
    required this.bgSolid,
    required this.bgElevated,
    required this.bgPopover,
    required this.textTertiary,
    required this.textInverse,
    required this.borderStrong,
    required this.borderFocus,
    required this.accentMuted,
    required this.onAccent,
    required this.danger,
    required this.dangerHover,
    required this.dangerMuted,
    required this.warning,
    required this.success,
    required this.info,
    required this.scrim,
    required this.selection,
    required this.pressed,
    required this.overlayStroke,
    required this.glassBlurDefault,
  });

  // ---- Semantic aliases (preferred for new code) ----
  Color get bg0 => bgSolid;
  Color get bg1 => bgPanel;
  Color get bg2 => bgElevated;
  Color get bg3 => bgPopover;
  Color get textPrimary => textMain;
  Color get textSecondary => textSub;
  Color get borderSubtle => border;
  Color get hover => bgHover;

  static AppThemeConfig forType(AppThemeType type) {
    switch (type) {
      case AppThemeType.light:
        return light;
      case AppThemeType.pink:
        return pink;
      case AppThemeType.dark:
        return dark;
    }
  }

  static const AppThemeConfig dark = AppThemeConfig(
    bgApp: RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: [Color(0xFF0F172A), Color(0xFF020617)],
    ),
    bgPanel: Color(0xA60F172A),
    bgHover: Color(0x0FFFFFFF),
    border: Color(0x14FFFFFF),
    sliderTrack: Color(0x26FFFFFF),
    textMain: Color(0xFFF8FAFC),
    textSub: Color(0xFF94A3B8),
    accent: Color(0xFF3B82F6),
    accentHover: Color(0xFF2563EB),
    accentGlow: Color(0x403B82F6),
    glassBlur: 24.0,
    ambientOpacity: 0.12,
    brightness: Brightness.dark,
    bgSolid: Color(0xFF020617),
    bgElevated: Color(0xCC1E293B),
    bgPopover: Color(0xF01E293B),
    textTertiary: Color(0xFF64748B),
    textInverse: Color(0xFF0F172A),
    borderStrong: Color(0x24FFFFFF),
    borderFocus: Color(0x993B82F6),
    accentMuted: Color(0x333B82F6),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFF87171),
    dangerHover: Color(0xFFEF4444),
    dangerMuted: Color(0x33F87171),
    warning: Color(0xFFFBBF24),
    success: Color(0xFF34D399),
    info: Color(0xFF38BDF8),
    scrim: Color(0x99020817),
    selection: Color(0x333B82F6),
    pressed: Color(0x14FFFFFF),
    overlayStroke: Color(0x1AFFFFFF),
    glassBlurDefault: 18.0,
  );

  static const AppThemeConfig light = AppThemeConfig(
    bgApp: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
    ),
    bgPanel: Color(0xC0FFFFFF),
    bgHover: Color(0x0F0F172A),
    border: Color(0x140F172A),
    sliderTrack: Color(0x1E0F172A),
    textMain: Color(0xFF0F172A),
    textSub: Color(0xFF64748B),
    accent: Color(0xFF2563EB),
    accentHover: Color(0xFF1D4ED8),
    accentGlow: Color(0x262563EB),
    glassBlur: 24.0,
    ambientOpacity: 0.05,
    brightness: Brightness.light,
    bgSolid: Color(0xFFF1F5F9),
    bgElevated: Color(0xF2FFFFFF),
    bgPopover: Color(0xFFFFFFFF),
    textTertiary: Color(0xFF94A3B8),
    textInverse: Color(0xFFFFFFFF),
    borderStrong: Color(0x240F172A),
    borderFocus: Color(0x992563EB),
    accentMuted: Color(0x1F2563EB),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFDC2626),
    dangerHover: Color(0xFFB91C1C),
    dangerMuted: Color(0x1FDC2626),
    warning: Color(0xFFD97706),
    success: Color(0xFF059669),
    info: Color(0xFF0284C7),
    scrim: Color(0x660F172A),
    selection: Color(0x292563EB),
    pressed: Color(0x140F172A),
    overlayStroke: Color(0x140F172A),
    glassBlurDefault: 16.0,
  );

  static const AppThemeConfig pink = AppThemeConfig(
    bgApp: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFF5F5), Color(0xFFFFE4E6)],
    ),
    bgPanel: Color(0xC0FFFFFF),
    bgHover: Color(0x14F43F5E),
    border: Color(0x26F43F5E),
    sliderTrack: Color(0x26F43F5E),
    textMain: Color(0xFF881337),
    textSub: Color(0xFFDB2777),
    accent: Color(0xFFF43F5E),
    accentHover: Color(0xFFE11D48),
    accentGlow: Color(0x33F43F5E),
    glassBlur: 24.0,
    ambientOpacity: 0.08,
    brightness: Brightness.light,
    bgSolid: Color(0xFFFFF1F2),
    bgElevated: Color(0xF2FFFFFF),
    bgPopover: Color(0xFFFFFFFF),
    textTertiary: Color(0xFFF9A8D4),
    textInverse: Color(0xFFFFFFFF),
    borderStrong: Color(0x33F43F5E),
    borderFocus: Color(0x99F43F5E),
    accentMuted: Color(0x1FF43F5E),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFE11D48),
    dangerHover: Color(0xFFBE123C),
    dangerMuted: Color(0x1FE11D48),
    warning: Color(0xFFEA580C),
    success: Color(0xFF059669),
    info: Color(0xFFDB2777),
    scrim: Color(0x66881337),
    selection: Color(0x29F43F5E),
    pressed: Color(0x1AF43F5E),
    overlayStroke: Color(0x1AF43F5E),
    glassBlurDefault: 16.0,
  );
}
