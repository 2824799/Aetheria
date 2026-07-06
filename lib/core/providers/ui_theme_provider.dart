import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeType { dark, light, pink }

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
  });
}

class UIThemeProvider extends ChangeNotifier {
  AppThemeType _themeType = AppThemeType.dark;

  UIThemeProvider() {
    _loadTheme();
  }

  AppThemeType get themeType => _themeType;

  AppThemeConfig get currentTheme => _getThemeConfig();

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
    _themeType = type;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aetheria-theme', type.toString().split('.').last);
  }

  AppThemeConfig _getThemeConfig() {
    switch (_themeType) {
      case AppThemeType.light:
        return const AppThemeConfig(
          bgApp: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
          ),
          bgPanel: Color(0xC0FFFFFF), // rgba(255, 255, 255, 0.75)
          bgHover: Color(0x0F0F172A), // rgba(15, 23, 42, 0.06)
          border: Color(0x140F172A), // rgba(15, 23, 42, 0.08)
          sliderTrack: Color(0x1E0F172A), // rgba(15, 23, 42, 0.12)
          textMain: Color(0xFF0F172A),
          textSub: Color(0xFF64748B),
          accent: Color(0xFF2563EB),
          accentHover: Color(0xFF1D4ED8),
          accentGlow: Color(0x262563EB), // rgba(37, 99, 235, 0.15)
          glassBlur: 30.0,
          ambientOpacity: 0.05,
          brightness: Brightness.light,
        );
      case AppThemeType.pink:
        return const AppThemeConfig(
          bgApp: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF5F5), Color(0xFFFFE4E6)],
          ),
          bgPanel: Color(0xC0FFFFFF), // rgba(255, 255, 255, 0.75)
          bgHover: Color(0x14F43F5E), // rgba(244, 63, 94, 0.08)
          border: Color(0x26F43F5E), // rgba(244, 63, 94, 0.15)
          sliderTrack: Color(0x26F43F5E), // rgba(244, 63, 94, 0.15)
          textMain: Color(0xFF881337),
          textSub: Color(0xFFDB2777),
          accent: Color(0xFFF43F5E),
          accentHover: Color(0xFFE11D48),
          accentGlow: Color(0x33F43F5E), // rgba(244, 63, 94, 0.2)
          glassBlur: 30.0,
          ambientOpacity: 0.08,
          brightness: Brightness.light,
        );
      case AppThemeType.dark:
        return const AppThemeConfig(
          bgApp: RadialGradient(
            center: Alignment.center,
            radius: 1.0,
            colors: [Color(0xFF0F172A), Color(0xFF020617)],
          ),
          bgPanel: Color(0xA60F172A), // rgba(15, 23, 42, 0.65)
          bgHover: Color(0x0FFFFFFF), // rgba(255, 255, 255, 0.06)
          border: Color(0x14FFFFFF), // rgba(255, 255, 255, 0.08)
          sliderTrack: Color(0x26FFFFFF), // rgba(255, 255, 255, 0.15)
          textMain: Color(0xFFF8FAFC),
          textSub: Color(0xFF94A3B8),
          accent: Color(0xFF3B82F6),
          accentHover: Color(0xFF2563EB),
          accentGlow: Color(0x403B82F6), // rgba(59, 130, 246, 0.25)
          glassBlur: 30.0,
          ambientOpacity: 0.12,
          brightness: Brightness.dark,
        );
    }
  }

  ThemeData get themeData {
    final cfg = currentTheme;
    return ThemeData(
      brightness: cfg.brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: ColorScheme(
        brightness: cfg.brightness,
        primary: cfg.accent,
        onPrimary: Colors.white,
        secondary: cfg.accentHover,
        onSecondary: Colors.white,
        error: Colors.redAccent,
        onError: Colors.white,
        background: Colors.transparent,
        onBackground: cfg.textMain,
        surface: cfg.bgPanel,
        onSurface: cfg.textMain,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: cfg.textMain),
        bodyMedium: TextStyle(color: cfg.textMain),
        bodySmall: TextStyle(color: cfg.textSub),
        titleLarge: TextStyle(color: cfg.textMain, fontWeight: FontWeight.bold),
      ),
      dividerColor: cfg.border,
    );
  }
}
