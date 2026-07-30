import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetheria/core/theme/app_theme_config.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';

export 'package:aetheria/core/theme/app_theme_config.dart';
export 'package:aetheria/core/theme/aetheria_theme.dart';
export 'package:aetheria/core/theme/tokens/space.dart';
export 'package:aetheria/core/theme/tokens/radius.dart';
export 'package:aetheria/core/theme/tokens/motion.dart';
export 'package:aetheria/core/theme/tokens/typography.dart';
export 'package:aetheria/core/theme/tokens/icon_size.dart';
export 'package:aetheria/core/theme/tokens/palettes.dart';

class UIThemeProvider extends ChangeNotifier {
  AppThemeType _themeType = AppThemeType.dark;

  UIThemeProvider() {
    _loadTheme();
  }

  AppThemeType get themeType => _themeType;

  AppThemeConfig get currentTheme => AppThemeConfig.forType(_themeType);

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('aetheria-theme');
    if (savedTheme != null) {
      _themeType = AppThemeType.values.firstWhere(
        (e) => e.toString().split('.').last == savedTheme,
        orElse: () => AppThemeType.dark,
      );
      notifyListeners();
    }
  }

  Future<void> setTheme(AppThemeType type) async {
    if (_themeType == type) return;
    _themeType = type;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aetheria-theme', type.toString().split('.').last);
  }

  ThemeData get themeData => buildAetheriaThemeData(currentTheme);
}

