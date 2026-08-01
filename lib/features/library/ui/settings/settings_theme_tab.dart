import 'package:flutter/material.dart';
import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_section.dart';
import 'package:aetheria/features/library/ui/settings/settings_shared_widgets.dart';

class SettingsThemeTab extends StatelessWidget {
  const SettingsThemeTab({
    super.key,
    required this.cfg,
    required this.themeProvider,
  });

  final AppThemeConfig cfg;
  final UIThemeProvider themeProvider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AetherSectionHeader(title: '界面主题风格'),
        const SizedBox(height: AetherSpace.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth >= 680
                ? (constraints.maxWidth - (AetherSpace.md * 3)) / 4
                : (constraints.maxWidth - AetherSpace.md) / 2;
            return Wrap(
              spacing: AetherSpace.md,
              runSpacing: AetherSpace.md,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: SettingsThemeCard(
                    title: '深邃暗色',
                    type: AppThemeType.dark,
                    previewGradient: AppThemeConfig.dark.bgApp,
                    themeProvider: themeProvider,
                    cfg: cfg,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: SettingsThemeCard(
                    title: '纯净亮色',
                    type: AppThemeType.light,
                    previewGradient: AppThemeConfig.light.bgApp,
                    themeProvider: themeProvider,
                    cfg: cfg,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: SettingsThemeCard(
                    title: '温润粉樱',
                    type: AppThemeType.pink,
                    previewGradient: AppThemeConfig.pink.bgApp,
                    themeProvider: themeProvider,
                    cfg: cfg,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: SettingsThemeCard(
                    title: '暮樱暗粉',
                    type: AppThemeType.pinkDark,
                    previewGradient: AppThemeConfig.pinkDark.bgApp,
                    themeProvider: themeProvider,
                    cfg: cfg,
                  ),
                ),
              ],
            );
          },
        ),
        const AetherDivider(),
        Text(
          '数据引擎: SQLite 3 & Symphonia/Lofty (Rust)\n界面渲染: Flutter 3 & Rust (FRB v2)',
          style: AetherType.captionStyle(
            cfg.textSecondary,
          ).copyWith(height: 1.5),
        ),
      ],
    );
  }
}
