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
  static const String _themePrefsKey = 'aetheria-theme';
  static const String _tagAlignmentPrefsKey = 'aetheria-tag-alignment-enabled';

  AppThemeType _themeType = AppThemeType.dark;
  bool _tagAlignmentEnabled = false;

  UIThemeProvider() {
    _loadPreferences();
  }

  AppThemeType get themeType => _themeType;

  /// Whether desktop song table tags align vertically by category slots.
  bool get tagAlignmentEnabled => _tagAlignmentEnabled;

  AppThemeConfig get currentTheme => AppThemeConfig.forType(_themeType);

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    var changed = false;

    final savedTheme = prefs.getString(_themePrefsKey);
    if (savedTheme != null) {
      final parsed = AppThemeType.values.firstWhere(
        (e) => e.toString().split('.').last == savedTheme,
        orElse: () => AppThemeType.dark,
      );
      if (parsed != _themeType) {
        _themeType = parsed;
        changed = true;
      }
    }

    final savedAlign = prefs.getBool(_tagAlignmentPrefsKey);
    if (savedAlign != null && savedAlign != _tagAlignmentEnabled) {
      _tagAlignmentEnabled = savedAlign;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  Future<void> setTheme(AppThemeType type) async {
    if (_themeType == type) return;
    _themeType = type;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePrefsKey, type.toString().split('.').last);
  }

  /// Toggles tag column alignment mode in the desktop song table.
  Future<void> setTagAlignmentEnabled(bool enabled) async {
    if (_tagAlignmentEnabled == enabled) return;
    _tagAlignmentEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tagAlignmentPrefsKey, enabled);
  }

  ThemeData get themeData => buildAetheriaThemeData(currentTheme);
}

