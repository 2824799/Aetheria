import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum FloatingLyricAlign { left, center, right }

class FloatingLyricsProvider extends ChangeNotifier {
  static const _prefix = 'aetheria-floating-lyrics';

  bool enabled = false;
  bool locked = false;
  bool alwaysOnTop = true;
  bool pauseFade = true;
  bool showTranslation = true;
  bool showNextLine = true;
  bool boldCurrentLine = true;
  bool zoomCurrentLine = true;
  bool compactMultiline = false;
  bool textShadowEnabled = true;
  FloatingLyricAlign align = FloatingLyricAlign.center;
  double fontSize = 30;
  double lineGap = 8;
  double opacity = 0.95;
  int refreshFps = 30;
  Color unplayedColor = const Color(0xFFFFFFFF);
  Color playedColor = const Color(0xFF22C55E);
  Color shadowColor = const Color(0x99000000);
  double windowX = -1;
  double windowY = -1;
  double windowWidth = 760;
  double windowHeight = 150;

  FloatingLyricsProvider() {
    load();
  }

  bool get hasSavedWindowPosition => windowX >= 0 && windowY >= 0;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool('$_prefix-enabled') ?? enabled;
    locked = prefs.getBool('$_prefix-locked') ?? locked;
    alwaysOnTop = prefs.getBool('$_prefix-always-on-top') ?? alwaysOnTop;
    pauseFade = prefs.getBool('$_prefix-pause-fade') ?? pauseFade;
    showTranslation =
        prefs.getBool('$_prefix-show-translation') ?? showTranslation;
    showNextLine = prefs.getBool('$_prefix-show-next-line') ?? showNextLine;
    boldCurrentLine = prefs.getBool('$_prefix-bold-current') ?? boldCurrentLine;
    zoomCurrentLine = prefs.getBool('$_prefix-zoom-current') ?? zoomCurrentLine;
    compactMultiline =
        prefs.getBool('$_prefix-compact-multiline') ?? compactMultiline;
    textShadowEnabled =
        prefs.getBool('$_prefix-text-shadow-enabled') ?? textShadowEnabled;
    align = _alignFromName(prefs.getString('$_prefix-align')) ?? align;
    fontSize = prefs.getDouble('$_prefix-font-size') ?? fontSize;
    lineGap = prefs.getDouble('$_prefix-line-gap') ?? lineGap;
    opacity = prefs.getDouble('$_prefix-opacity') ?? opacity;
    refreshFps = prefs.getInt('$_prefix-refresh-fps') ?? refreshFps;
    unplayedColor =
        _colorFromPrefs(prefs, '$_prefix-unplayed-color') ?? unplayedColor;
    playedColor =
        _colorFromPrefs(prefs, '$_prefix-played-color') ?? playedColor;
    shadowColor =
        _colorFromPrefs(prefs, '$_prefix-shadow-color') ?? shadowColor;
    windowX = prefs.getDouble('$_prefix-window-x') ?? windowX;
    windowY = prefs.getDouble('$_prefix-window-y') ?? windowY;
    windowWidth = prefs.getDouble('$_prefix-window-width') ?? windowWidth;
    windowHeight = prefs.getDouble('$_prefix-window-height') ?? windowHeight;
    notifyListeners();
  }

  Map<String, dynamic> stylePayload() {
    return <String, dynamic>{
      'locked': locked,
      'alwaysOnTop': alwaysOnTop,
      'pauseFade': pauseFade,
      'showTranslation': showTranslation,
      'showNextLine': showNextLine,
      'boldCurrentLine': boldCurrentLine,
      'zoomCurrentLine': zoomCurrentLine,
      'compactMultiline': compactMultiline,
      'textShadowEnabled': textShadowEnabled,
      'align': align.name,
      'fontSize': fontSize,
      'lineGap': lineGap,
      'opacity': opacity,
      'refreshFps': refreshFps,
      'unplayedColor': _argb(unplayedColor),
      'playedColor': _argb(playedColor),
      'shadowColor': _argb(shadowColor),
      'windowX': windowX,
      'windowY': windowY,
      'windowWidth': windowWidth,
      'windowHeight': windowHeight,
    };
  }

  String get styleSignature => stylePayload().entries
      .map((entry) => '${entry.key}:${entry.value}')
      .join('|');

  Future<void> setEnabled(bool value) async {
    enabled = value;
    notifyListeners();
    await _setBool('enabled', value);
  }

  Future<void> setLocked(bool value) async {
    locked = value;
    notifyListeners();
    await _setBool('locked', value);
  }

  Future<void> setAlwaysOnTop(bool value) async {
    alwaysOnTop = value;
    notifyListeners();
    await _setBool('always-on-top', value);
  }

  Future<void> setPauseFade(bool value) async {
    pauseFade = value;
    notifyListeners();
    await _setBool('pause-fade', value);
  }

  Future<void> setShowTranslation(bool value) async {
    showTranslation = value;
    notifyListeners();
    await _setBool('show-translation', value);
  }

  Future<void> setShowNextLine(bool value) async {
    showNextLine = value;
    notifyListeners();
    await _setBool('show-next-line', value);
  }

  Future<void> setBoldCurrentLine(bool value) async {
    boldCurrentLine = value;
    notifyListeners();
    await _setBool('bold-current', value);
  }

  Future<void> setZoomCurrentLine(bool value) async {
    zoomCurrentLine = value;
    notifyListeners();
    await _setBool('zoom-current', value);
  }

  Future<void> setCompactMultiline(bool value) async {
    compactMultiline = value;
    notifyListeners();
    await _setBool('compact-multiline', value);
  }

  Future<void> setTextShadowEnabled(bool value) async {
    textShadowEnabled = value;
    notifyListeners();
    await _setBool('text-shadow-enabled', value);
  }

  Future<void> setAlign(FloatingLyricAlign value) async {
    align = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix-align', value.name);
  }

  Future<void> setFontSize(double value) async {
    fontSize = value.clamp(8, 72).toDouble();
    notifyListeners();
    await _setDouble('font-size', fontSize);
  }

  Future<void> setLineGap(double value) async {
    lineGap = value.clamp(0, 32).toDouble();
    notifyListeners();
    await _setDouble('line-gap', lineGap);
  }

  Future<void> setOpacity(double value) async {
    opacity = value.clamp(0.2, 1.0).toDouble();
    notifyListeners();
    await _setDouble('opacity', opacity);
  }

  Future<void> setRefreshFps(double value) async {
    refreshFps = value.round().clamp(10, 60);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefix-refresh-fps', refreshFps);
  }

  Future<void> setWindowWidth(double value) async {
    await updateWindowBounds(
      x: windowX,
      y: windowY,
      width: value,
      height: windowHeight,
    );
  }

  Future<void> setWindowHeight(double value) async {
    await updateWindowBounds(
      x: windowX,
      y: windowY,
      width: windowWidth,
      height: value,
    );
  }

  Future<void> setUnplayedColor(Color value) async {
    unplayedColor = value;
    notifyListeners();
    await _setColor('unplayed-color', value);
  }

  Future<void> setPlayedColor(Color value) async {
    playedColor = value;
    notifyListeners();
    await _setColor('played-color', value);
  }

  Future<void> setShadowColor(Color value) async {
    shadowColor = value;
    notifyListeners();
    await _setColor('shadow-color', value);
  }

  Future<void> updateWindowBounds({
    required double x,
    required double y,
    required double width,
    required double height,
  }) async {
    windowX = x;
    windowY = y;
    windowWidth = width.clamp(120, 1800).toDouble();
    windowHeight = height.clamp(36, 420).toDouble();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$_prefix-window-x', windowX);
    await prefs.setDouble('$_prefix-window-y', windowY);
    await prefs.setDouble('$_prefix-window-width', windowWidth);
    await prefs.setDouble('$_prefix-window-height', windowHeight);
  }

  Future<void> resetWindowBounds() async {
    windowX = -1;
    windowY = -1;
    windowWidth = 760;
    windowHeight = 150;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix-window-x');
    await prefs.remove('$_prefix-window-y');
    await prefs.setDouble('$_prefix-window-width', windowWidth);
    await prefs.setDouble('$_prefix-window-height', windowHeight);
  }

  Future<void> resetStyle() async {
    align = FloatingLyricAlign.center;
    fontSize = 30;
    lineGap = 8;
    opacity = 0.95;
    unplayedColor = const Color(0xFFFFFFFF);
    playedColor = const Color(0xFF22C55E);
    shadowColor = const Color(0x99000000);
    showTranslation = true;
    showNextLine = true;
    boldCurrentLine = true;
    zoomCurrentLine = true;
    compactMultiline = false;
    textShadowEnabled = true;
    refreshFps = 30;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix-align', align.name);
    await prefs.setDouble('$_prefix-font-size', fontSize);
    await prefs.setDouble('$_prefix-line-gap', lineGap);
    await prefs.setDouble('$_prefix-opacity', opacity);
    await _setColor('unplayed-color', unplayedColor);
    await _setColor('played-color', playedColor);
    await _setColor('shadow-color', shadowColor);
    await prefs.setBool('$_prefix-show-translation', showTranslation);
    await prefs.setBool('$_prefix-show-next-line', showNextLine);
    await prefs.setBool('$_prefix-bold-current', boldCurrentLine);
    await prefs.setBool('$_prefix-zoom-current', zoomCurrentLine);
    await prefs.setBool('$_prefix-compact-multiline', compactMultiline);
    await prefs.setBool('$_prefix-text-shadow-enabled', textShadowEnabled);
    await prefs.setInt('$_prefix-refresh-fps', refreshFps);
  }

  Future<void> _setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix-$key', value);
  }

  Future<void> _setDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$_prefix-$key', value);
  }

  Future<void> _setColor(String key, Color value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefix-$key', _argb(value));
  }

  static Color? _colorFromPrefs(SharedPreferences prefs, String key) {
    final value = prefs.getInt(key);
    if (value == null) {
      return null;
    }
    return Color(value);
  }

  static int _argb(Color color) {
    return ((color.a * 255).round() << 24) |
        ((color.r * 255).round() << 16) |
        ((color.g * 255).round() << 8) |
        (color.b * 255).round();
  }

  static FloatingLyricAlign? _alignFromName(String? name) {
    return switch (name) {
      'left' => FloatingLyricAlign.left,
      'right' => FloatingLyricAlign.right,
      'center' => FloatingLyricAlign.center,
      _ => null,
    };
  }
}
