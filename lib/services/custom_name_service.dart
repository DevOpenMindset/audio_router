import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists user-defined display names for audio apps.
/// e.g. "chrome" → "YouTube", "msedge" → "Teams perso"
class CustomNameService extends ChangeNotifier {
  static const _key = 'custom_app_names';

  /// processName (lowercase) → custom display name
  Map<String, String> _names = {};

  CustomNameService() {
    _load();
  }

  /// Returns the custom name for [processName], or [defaultName] if none set.
  String nameFor(String processName, String defaultName) =>
      _names[processName.toLowerCase()] ?? defaultName;

  /// True if a custom name has been set for this process.
  bool hasCustomName(String processName) =>
      _names.containsKey(processName.toLowerCase());

  /// Set a custom name. Pass empty string to remove.
  void setName(String processName, String customName) {
    final key = processName.toLowerCase();
    if (customName.trim().isEmpty) {
      _names.remove(key);
    } else {
      _names[key] = customName.trim();
    }
    _save();
    notifyListeners();
  }

  /// Remove the custom name and revert to default.
  void resetName(String processName) {
    _names.remove(processName.toLowerCase());
    _save();
    notifyListeners();
  }

  /// Apply all custom names from a profile (merge, not replace).
  void applyFromProfile(Map<String, String> profileCustomNames) {
    for (final e in profileCustomNames.entries) {
      _names[e.key.toLowerCase()] = e.value;
    }
    _save();
    notifyListeners();
  }

  /// Export current custom names (for profile snapshot).
  Map<String, String> export() => Map.unmodifiable(_names);

  // ─── Persistence ──────────────────────────────────────────

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_key);
      if (json != null) {
        _names = Map<String, String>.from(jsonDecode(json) as Map);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('CustomNameService load error: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_names));
    } catch (e) {
      debugPrint('CustomNameService save error: $e');
    }
  }
}
