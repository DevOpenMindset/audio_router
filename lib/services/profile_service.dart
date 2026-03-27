import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audio_models.dart';

class ProfileService extends ChangeNotifier {
  List<RoutingProfile> _profiles = [];
  String? _activeProfileId;
  bool _loaded = false;

  List<RoutingProfile> get profiles => List.unmodifiable(_profiles);
  String? get activeProfileId => _activeProfileId;
  bool get isLoaded => _loaded;

  ProfileService() {
    _load();
  }

  // ─── CRUD ──────────────────────────────────────────────────

  void addProfile(RoutingProfile profile) {
    _profiles.add(profile);
    _save();
    notifyListeners();
  }

  void updateProfile(RoutingProfile updated) {
    _profiles = _profiles.map((p) => p.id == updated.id ? updated : p).toList();
    _save();
    notifyListeners();
  }

  void removeProfile(String profileId) {
    _profiles.removeWhere((p) => p.id == profileId);
    if (_activeProfileId == profileId) _activeProfileId = null;
    _save();
    notifyListeners();
  }

  // ─── Activation ────────────────────────────────────────────

  void activateProfile(String profileId) {
    _activeProfileId = profileId;
    _save();
    notifyListeners();
  }

  void deactivateProfile() {
    _activeProfileId = null;
    _save();
    notifyListeners();
  }

  RoutingProfile? get activeProfile {
    if (_activeProfileId == null) return null;
    try {
      return _profiles.firstWhere((p) => p.id == _activeProfileId);
    } catch (_) {
      return null;
    }
  }

  /// Capture the current state (routes, volumes, duck rules, custom names)
  /// into a new profile.
  RoutingProfile snapshotProfile({
    required String name,
    required String icon,
    required List<AudioSession> sessions,
    required List<DuckRule> duckRules,
    Map<String, String> customNames = const {},
  }) {
    final routes  = <String, String>{};
    final volumes = <String, double>{};

    for (final s in sessions) {
      if (s.assignedDeviceId != null) {
        routes[s.processName] = s.assignedDeviceId!;
      }
      if (s.volume < 0.99) {
        volumes[s.processName] = s.volume;
      }
    }

    return RoutingProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      icon: icon,
      routes: routes,
      volumes: volumes,
      duckRules: List.from(duckRules),
      customNames: Map.from(customNames),
    );
  }

  // ─── Persistence ───────────────────────────────────────────

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('profiles');
      if (json != null) {
        final list = jsonDecode(json) as List;
        _profiles = list
            .map((e) => RoutingProfile.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      _activeProfileId = prefs.getString('active_profile_id');
    } catch (e) {
      debugPrint('Failed to load profiles: $e');
    }

    // Add defaults if no profiles exist
    if (_profiles.isEmpty) {
      _profiles = [
        const RoutingProfile(
          id: 'gaming',
          name: 'Gaming',
          icon: '🎮',
          routes: {},
        ),
        const RoutingProfile(
          id: 'work',
          name: 'Travail',
          icon: '💼',
          routes: {},
        ),
        const RoutingProfile(
          id: 'music',
          name: 'Musique',
          icon: '🎵',
          routes: {},
        ),
      ];
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_profiles.map((p) => p.toJson()).toList());
      await prefs.setString('profiles', json);
      if (_activeProfileId != null) {
        await prefs.setString('active_profile_id', _activeProfileId!);
      } else {
        await prefs.remove('active_profile_id');
      }
    } catch (e) {
      debugPrint('Failed to save profiles: $e');
    }
  }
}
