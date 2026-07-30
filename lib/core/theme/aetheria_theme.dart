import 'package:flutter/material.dart';
import 'package:aetheria/core/theme/app_theme_config.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';
import 'package:aetheria/core/theme/tokens/motion.dart';
import 'package:aetheria/core/theme/tokens/radius.dart';

/// ThemeExtension bridge so widgets can read tokens via [Theme.of].
@immutable
class AetheriaTheme extends ThemeExtension<AetheriaTheme> {
  final AppThemeConfig colors;

  const AetheriaTheme({required this.colors});

  static AetheriaTheme of(BuildContext context) {
    final ext = Theme.of(context).extension<AetheriaTheme>();
    assert(
      ext != null,
      'AetheriaTheme not found. Ensure UIThemeProvider.themeData is applied.',
    );
    return ext ?? const AetheriaTheme(colors: AppThemeConfig.dark);
  }

  @override
  AetheriaTheme copyWith({AppThemeConfig? colors}) {
    return AetheriaTheme(colors: colors ?? this.colors);
  }

  @override
  AetheriaTheme lerp(ThemeExtension<AetheriaTheme>? other, double t) {
    if (other is! AetheriaTheme) return this;
    // Theme switches crossfade at the MaterialApp level; keep discrete configs.
    return t < 0.5 ? this : other;
  }
}

extension AetheriaBuildContextX on BuildContext {
  /// Full theme extension.
  AetheriaTheme get aether => AetheriaTheme.of(this);

  /// Color/surface tokens (preferred name for new code).
  AppThemeConfig get tokens => AetheriaTheme.of(this).colors;

  /// Backward-friendly alias used across existing UI.
  AppThemeConfig get cfg => tokens;
}

/// Builds a complete [ThemeData] from [AppThemeConfig].
ThemeData buildAetheriaThemeData(AppThemeConfig cfg) {
  final textMain = cfg.textPrimary;
  final textSub = cfg.textSecondary;

  return ThemeData(
    useMaterial3: true,
    brightness: cfg.brightness,
    scaffoldBackgroundColor: Colors.transparent,
    visualDensity: VisualDensity.standard,
    colorScheme: ColorScheme(
      brightness: cfg.brightness,
      primary: cfg.accent,
      onPrimary: cfg.onAccent,
      secondary: cfg.accentHover,
      onSecondary: cfg.onAccent,
      error: cfg.danger,
      onError: cfg.onAccent,
      surface: cfg.bgElevated,
      onSurface: textMain,
    ),
    textTheme: TextTheme(
      bodyLarge: AetherType.bodyStyle(textMain),
      bodyMedium: AetherType.bodyStyle(textMain),
      bodySmall: AetherType.bodySmStyle(textSub),
      labelLarge: AetherType.labelStyle(textMain),
      labelMedium: AetherType.labelStyle(textSub),
      labelSmall: AetherType.captionStyle(textSub),
      titleLarge: AetherType.titleLgStyle(textMain),
      titleMedium: AetherType.titleStyle(textMain),
      titleSmall: AetherType.titleSmStyle(textMain),
      headlineSmall: AetherType.displayStyle(textMain),
    ),
    dividerColor: cfg.borderSubtle,
    splashFactory: NoSplash.splashFactory,
    extensions: <ThemeExtension<dynamic>>[
      AetheriaTheme(colors: cfg),
    ],
    dialogTheme: DialogThemeData(
      backgroundColor: cfg.bgPopover,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AetherRadius.lg),
        side: BorderSide(color: cfg.borderSubtle),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: AetherMotion.tooltipDelay,
      decoration: BoxDecoration(
        color: cfg.bgPopover,
        borderRadius: BorderRadius.circular(AetherRadius.md),
        border: Border.all(color: cfg.borderSubtle),
      ),
      textStyle: AetherType.bodySmStyle(textMain),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: cfg.bgPopover,
      contentTextStyle: AetherType.bodyStyle(textMain),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AetherRadius.md),
        side: BorderSide(color: cfg.borderSubtle),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cfg.bgPopover,
      surfaceTintColor: Colors.transparent,
      textStyle: AetherType.bodyStyle(textMain),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AetherRadius.md),
        side: BorderSide(color: cfg.borderSubtle),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: cfg.borderSubtle,
      thickness: 1,
      space: 1,
    ),
  );
}


