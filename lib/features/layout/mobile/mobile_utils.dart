import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';

class MobileLrcBadge extends StatelessWidget {
  final AppThemeConfig cfg;
  const MobileLrcBadge({super.key, required this.cfg});

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
