/// Curated color palettes that are intentionally fixed (not theme-bound).
///
/// Feature UI must not invent ad-hoc `Color(0x…)` swatches — pull from here
/// or from [AppThemeConfig].
library;

import 'package:flutter/material.dart';

/// Floating / desktop lyric style presets used by settings.
class AetherLyricPalettes {
  AetherLyricPalettes._();

  /// Unplayed lyric text samples.
  static const List<Color> unplayed = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFFE0F2FE),
    Color(0xFFFFF7ED),
  ];

  /// Played / active lyric text samples.
  static const List<Color> played = <Color>[
    Color(0xFF22C55E),
    Color(0xFF38BDF8),
    Color(0xFFF97316),
    Color(0xFFEC4899),
  ];

  /// Text shadow / outline samples.
  static const List<Color> shadow = <Color>[
    Color(0x99000000),
    Color(0xAA111827),
    Color(0x770F172A),
  ];
}

/// Fallback tag / accent colors when a stored hex is invalid.
class AetherFallbackColors {
  AetherFallbackColors._();

  /// Matches dark-theme accent; safe default for parse failures.
  static const Color accent = Color(0xFF3B82F6);

  /// Neutral chip / tag fallback.
  static const Color neutral = Color(0xFF94A3B8);
}
