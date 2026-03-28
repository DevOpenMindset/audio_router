import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/app_theme.dart';
import '../platform.dart' as _plat;

class ThemeService extends ChangeNotifier {
  bool _isDarkMode = true;
  /// 'win' = Windows 11 UI, 'mac' = macOS UI
  String _uiStyle = Platform.isWindows ? 'win' : 'mac';
  String _locale = 'fr';
  bool _loaded = false;
  // macOS: show in Dock by default; Windows: hidden from taskbar by default (lives in tray)
  bool _showInTaskbar = Platform.isMacOS ? true : false;

  bool get isDarkMode => _isDarkMode;
  String get uiStyle => _uiStyle;
  String get locale => _locale;
  bool get isLoaded => _loaded;
  bool get showInTaskbar => _showInTaskbar;

  ThemeService() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool('dark_mode') ?? true;
      _uiStyle = prefs.getString('ui_style') ??
          (Platform.isWindows ? 'win' : 'mac');
      _locale = prefs.getString('locale') ?? 'fr';
      _showInTaskbar = prefs.getBool('show_in_taskbar') ??
          (Platform.isMacOS ? true : false);
    } catch (e) {
      debugPrint('Failed to load theme: $e');
    }
    isDarkTheme = _isDarkMode;
    _plat.uiStyleOverride = _uiStyle;
    _loaded = true;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    isDarkTheme = _isDarkMode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('dark_mode', _isDarkMode);
    } catch (e) {
      debugPrint('Failed to save theme: $e');
    }
  }

  Future<void> setDarkMode(bool value) async {
    if (_isDarkMode == value) return;
    _isDarkMode = value;
    isDarkTheme = _isDarkMode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('dark_mode', _isDarkMode);
    } catch (e) {
      debugPrint('Failed to save theme: $e');
    }
  }

  Future<void> setUIStyle(String style) async {
    if (_uiStyle == style) return;
    _uiStyle = style;
    _plat.uiStyleOverride = style;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ui_style', _uiStyle);
    } catch (e) {
      debugPrint('Failed to save ui_style: $e');
    }
  }

  Future<void> setLocale(String l) async {
    if (_locale == l) return;
    _locale = l;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('locale', _locale);
    } catch (e) {
      debugPrint('Failed to save locale: $e');
    }
  }

  Future<void> setShowInTaskbar(bool value) async {
    if (_showInTaskbar == value) return;
    _showInTaskbar = value;
    notifyListeners();
    await windowManager.setSkipTaskbar(!value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('show_in_taskbar', value);
    } catch (e) {
      debugPrint('Failed to save show_in_taskbar: $e');
    }
  }
}
