import 'package:flutter/material.dart';

enum AppThemeType { dark, light, pink, pinkDark }

/// Full visual config for one theme.
///
/// Most line and state colours are already translucent. Use them as they are:
/// `color.withValues(alpha: x)` replaces the alpha instead of scaling it, so
/// `border.withValues(alpha: 0.45)` turns an 8% hairline into a 45% one.
class AppThemeConfig {
  final Gradient bgApp;
  final Color bgPanel;
  final Color bgHover;
  final Color border;

  /// Separator between rows of one list or table; quieter than [border].
  final Color divider;
  final Color sliderTrack;
  final Color textMain;
  final Color textSub;
  final Color accent;
  final Color accentHover;
  final Color accentGlow;
  final double ambientOpacity;
  final Brightness brightness;

  // Expanded surface / content tokens
  final Color bgSolid;
  final Color bgElevated;
  final Color bgPopover;
  final Color textTertiary;
  final Color borderStrong;
  final Color borderFocus;
  final Color accentMuted;
  final Color onAccent;
  final Color danger;
  final Color dangerMuted;
  final Color warning;
  final Color success;
  final Color info;
  final Color scrim;
  final Color selection;
  final Color pressed;
  final double glassBlurDefault;

  const AppThemeConfig({
    required this.bgApp,
    required this.bgPanel,
    required this.bgHover,
    required this.border,
    required this.divider,
    required this.sliderTrack,
    required this.textMain,
    required this.textSub,
    required this.accent,
    required this.accentHover,
    required this.accentGlow,
    required this.ambientOpacity,
    required this.brightness,
    required this.bgSolid,
    required this.bgElevated,
    required this.bgPopover,
    required this.textTertiary,
    required this.borderStrong,
    required this.borderFocus,
    required this.accentMuted,
    required this.onAccent,
    required this.danger,
    required this.dangerMuted,
    required this.warning,
    required this.success,
    required this.info,
    required this.scrim,
    required this.selection,
    required this.pressed,
    required this.glassBlurDefault,
  });

  // ---- Semantic aliases (preferred for new code) ----
  Color get bg1 => bgPanel;
  Color get textPrimary => textMain;
  Color get textSecondary => textSub;
  Color get borderSubtle => border;

  static AppThemeConfig forType(AppThemeType type) {
    switch (type) {
      case AppThemeType.light:
        return light;
      case AppThemeType.pink:
        return pink;
      case AppThemeType.pinkDark:
        return pinkDark;
      case AppThemeType.dark:
        return dark;
    }
  }

  /// Cool graphite. Panels are opaque steps above the background, so stacked
  /// surfaces never compound their transparency.
  static const AppThemeConfig dark = AppThemeConfig(
    bgApp: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0C1018), Color(0xFF080B11)],
    ),
    bgPanel: Color(0xFF10151E),
    bgHover: Color(0x0DFFFFFF),
    border: Color(0x14FFFFFF),
    divider: Color(0x0BFFFFFF),
    sliderTrack: Color(0x24FFFFFF),
    textMain: Color(0xFFE9EDF3),
    textSub: Color(0xFF9CA7B8),
    accent: Color(0xFF4C8DF6),
    accentHover: Color(0xFF3B7DEB),
    accentGlow: Color(0x384C8DF6),
    ambientOpacity: 0.08,
    brightness: Brightness.dark,
    bgSolid: Color(0xFF080B11),
    bgElevated: Color(0xFF171D28),
    bgPopover: Color(0xFF1A212D),
    textTertiary: Color(0xFF7A8597),
    borderStrong: Color(0x24FFFFFF),
    borderFocus: Color(0x994C8DF6),
    accentMuted: Color(0x294C8DF6),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFF87171),
    dangerMuted: Color(0x33F87171),
    warning: Color(0xFFFBBF24),
    success: Color(0xFF34D399),
    info: Color(0xFF38BDF8),
    scrim: Color(0x99040609),
    selection: Color(0x334C8DF6),
    pressed: Color(0x14FFFFFF),
    glassBlurDefault: 18.0,
  );

  static const AppThemeConfig light = AppThemeConfig(
    bgApp: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFF6F7F9), Color(0xFFEFF1F5)],
    ),
    bgPanel: Color(0xFFFFFFFF),
    bgHover: Color(0x0A0F172A),
    border: Color(0x140F172A),
    divider: Color(0x0D0F172A),
    sliderTrack: Color(0x1E0F172A),
    textMain: Color(0xFF0F172A),
    textSub: Color(0xFF55627A),
    accent: Color(0xFF2563EB),
    accentHover: Color(0xFF1D4ED8),
    accentGlow: Color(0x262563EB),
    ambientOpacity: 0.04,
    brightness: Brightness.light,
    bgSolid: Color(0xFFF1F3F6),
    bgElevated: Color(0xFFFFFFFF),
    bgPopover: Color(0xFFFFFFFF),
    textTertiary: Color(0xFF7B879B),
    borderStrong: Color(0x240F172A),
    borderFocus: Color(0x992563EB),
    accentMuted: Color(0x1A2563EB),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFDC2626),
    dangerMuted: Color(0x1FDC2626),
    warning: Color(0xFFB45309),
    success: Color(0xFF047857),
    info: Color(0xFF0369A1),
    scrim: Color(0x660F172A),
    selection: Color(0x242563EB),
    pressed: Color(0x140F172A),
    glassBlurDefault: 16.0,
  );

  /// Rose accent on warm white. Body text stays a muted plum: pink is for
  /// emphasis, not for every label.
  static const AppThemeConfig pink = AppThemeConfig(
    bgApp: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFFF7F8), Color(0xFFFDECEF)],
    ),
    bgPanel: Color(0xFFFFFFFF),
    bgHover: Color(0x0FE11D48),
    border: Color(0x1FE11D48),
    divider: Color(0x12E11D48),
    sliderTrack: Color(0x26E11D48),
    textMain: Color(0xFF4A1528),
    textSub: Color(0xFF8F5468),
    accent: Color(0xFFE8456B),
    accentHover: Color(0xFFD42E57),
    accentGlow: Color(0x2EE8456B),
    ambientOpacity: 0.06,
    brightness: Brightness.light,
    bgSolid: Color(0xFFFFF1F3),
    bgElevated: Color(0xFFFFFFFF),
    bgPopover: Color(0xFFFFFFFF),
    textTertiary: Color(0xFFAD7C8D),
    borderStrong: Color(0x33E11D48),
    borderFocus: Color(0x99E8456B),
    accentMuted: Color(0x1AE8456B),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFC81E3A),
    dangerMuted: Color(0x1FC81E3A),
    warning: Color(0xFFB45309),
    success: Color(0xFF047857),
    info: Color(0xFFA2367F),
    scrim: Color(0x660F0A0C),
    selection: Color(0x24E8456B),
    pressed: Color(0x1AE11D48),
    glassBlurDefault: 16.0,
  );

  /// A dark, warm-neutral surface palette with soft blush accents.
  static const AppThemeConfig pinkDark = AppThemeConfig(
    bgApp: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF171015), Color(0xFF100C10)],
    ),
    bgPanel: Color(0xFF1A1318),
    bgHover: Color(0x10F6B6CA),
    border: Color(0x1FF6B6CA),
    divider: Color(0x10F6B6CA),
    sliderTrack: Color(0x33F6B6CA),
    textMain: Color(0xFFFFF7FA),
    textSub: Color(0xFFD8B8C3),
    accent: Color(0xFFF3A6BE),
    accentHover: Color(0xFFEC88AA),
    accentGlow: Color(0x40F3A6BE),
    ambientOpacity: 0.1,
    brightness: Brightness.dark,
    bgSolid: Color(0xFF100C10),
    bgElevated: Color(0xFF241920),
    bgPopover: Color(0xFF2A1D24),
    textTertiary: Color(0xFFA98591),
    borderStrong: Color(0x3DF6B6CA),
    borderFocus: Color(0xB3F3A6BE),
    accentMuted: Color(0x2EF3A6BE),
    onAccent: Color(0xFF35121F),
    danger: Color(0xFFFF8FA3),
    dangerMuted: Color(0x33FF8FA3),
    warning: Color(0xFFF6C177),
    success: Color(0xFF8BD5CA),
    info: Color(0xFFC6A0F6),
    scrim: Color(0xB3000000),
    selection: Color(0x38F3A6BE),
    pressed: Color(0x1FF6B6CA),
    glassBlurDefault: 18.0,
  );
}
