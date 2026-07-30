import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';

Color songTableParseHexColor(String hex, Color defaultColor) {
  final clean = hex.replaceAll('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  }
  return defaultColor;
}

class SongTableLrcBadge extends StatelessWidget {
  const SongTableLrcBadge({super.key, required this.cfg});

  final AppThemeConfig cfg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AetherSpace.sm - 1,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: cfg.accentMuted,
        borderRadius: BorderRadius.circular(AetherRadius.xs),
        border: Border.all(color: cfg.accent.withValues(alpha: 0.55)),
      ),
      child: Text(
        'LRC',
        style: AetherType.captionStyle(cfg.accent).copyWith(
          fontWeight: FontWeight.w800,
          fontSize: AetherType.caption - 1,
          letterSpacing: 0,
          height: 1.1,
        ),
      ),
    );
  }
}
