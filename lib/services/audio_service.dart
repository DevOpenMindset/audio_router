import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audio_models.dart';
// Conditionally import native bridge only on Windows
// ignore: unused_import
import '../core/native_audio_bridge_impl.dart';

/// Audio service that bridges Flutter UI with Windows audio system.
///
/// On Windows: uses NativeAudioBridge (COM/WASAPI via FFI)
/// On other platforms: uses simulation data for UI development
class AudioService extends ChangeNotifier {
  List<AudioDevice> _devices = [];
  List<AudioSession> _sessions = [];
  Timer? _pollTimer;
  Timer? _refreshTimer;
  Timer? _duckTimer;
  Timer? _hotkeyTimer;
  final Random _rng = Random();

  // Native bridge (null on non-Windows)
  NativeAudioBridge? _native;
  bool _useNative = false;

  // Persisted per-app routes: processId → deviceId.
  // Survives session reconnections (WASAPI sessions briefly disappear when
  // SetPersistedDefaultAudioEndpoint moves them to a new device).
  final Map<String, String> _persistedRoutes = {};

  // Persisted per-app volumes: processId → volume.
  // When a routed session reappears on its new device, we reapply the volume
  // because the fresh WASAPI session starts at 1.0.
  final Map<String, double> _persistedVolumes = {};

  // ── Route Memory (cross-restart persistence by process name) ──
  // Maps processName (lowercase) → deviceId.
  // Saved to SharedPreferences so routes survive app restarts.
  Map<String, String> _routeMemory = {};

  // ── Mirror Memory (cross-restart persistence) ──
  // Maps processName (lowercase) → set of extra mirror device IDs.
  Map<String, Set<String>> _mirrorMemory = {};

  // Called when devices are physically connected or disconnected.
  // Added/removed device lists passed as arguments.
  void Function(List<AudioDevice> added, List<AudioDevice> removed)? onDevicesChanged;

  // Auto-duck state
  List<DuckRule> _duckRules = [];
  final Map<String, double> _originalVolumes = {}; // processName -> volume before duck
  final Set<String> _currentlyDucked = {};          // processNames currently ducked
  final Map<String, Timer> _activeFades = {};       // processName -> fade timer
  final Set<String> _fadingPids = {};               // pids mid-fade (block _refreshSessions)

  List<AudioDevice> get devices => List.unmodifiable(_devices);
  List<AudioSession> get sessions => List.unmodifiable(_sessions);
  // A routed session stays in activeSessions even when WASAPI marks it inactive
  // during the brief device-transition period.
  List<AudioSession> get activeSessions => _sessions
      .where((s) => s.isActive || _persistedRoutes.containsKey(s.processId))
      .toList();
  List<AudioSession> get inactiveSessions => _sessions
      .where((s) => !s.isActive && !_persistedRoutes.containsKey(s.processId))
      .toList();
  List<DuckRule> get duckRules => List.unmodifiable(_duckRules);

  AudioService() {
    _init();
  }

  Future<void> _init() async {
    await _loadDuckRules();
    await _loadRouteMemory();
    await _loadMirrorMemory();
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS)) {
      await _initNative();
    } else {
      _initSimulation();
    }
  }

  // ─── NATIVE WINDOWS BACKEND ──────────────────────────────────

  Future<void> _initNative() async {
    try {
      _native = NativeAudioBridge();
      await _native!.initialize();
      _useNative = true;

      // Initial enumeration
      _refreshDevices();
      _refreshSessions();

      // Peak levels at ~30fps
      _pollTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        _refreshPeakLevels();
      });

      // Device/session list refresh every 2s
      _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _refreshDevices();
        _refreshSessions();
      });

      // Auto-duck evaluation every 500ms
      _duckTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _evaluateDuckRules();
      });

      // Hotkey polling at ~30fps
      _hotkeyTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        _pollHotkeys();
      });
    } catch (e) {
      debugPrint('Failed to initialize native audio: $e');
      debugPrint('Falling back to simulation mode');
      _useNative = false;
      _initSimulation();
    }
  }

  void _refreshDevices() {
    if (!_useNative || _native == null) return;
    try {
      final newDevices = _native!.enumerateDevices();
      if (!_listEquals(newDevices, _devices)) {
        // Detect physical device connect/disconnect events
        if (_devices.isNotEmpty && onDevicesChanged != null) {
          final oldIds = _devices.map((d) => d.id).toSet();
          final newIds = newDevices.map((d) => d.id).toSet();
          final added   = newDevices.where((d) => !oldIds.contains(d.id)).toList();
          final removed = _devices.where((d) => !newIds.contains(d.id)).toList();
          if (added.isNotEmpty || removed.isNotEmpty) {
            onDevicesChanged!(added, removed);
          }
        }
        _devices = newDevices;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Device enumeration error: $e');
    }
  }

  // Windows system processes that must never appear in the session list.
  // Routing or muting these could break system audio / OS stability.
  static const Set<String> _systemBlocklist = {
    'unknown', 'system', 'svchost', 'audiodg', 'dwm',
    'csrss', 'winlogon', 'services', 'lsass', 'smss',
    'wininit', 'fontdrvhost', 'sihost', 'ctfmon', 'rundll32',
    'taskhostw', 'backgroundtaskhost', 'searchhost', 'searchindexer',
    // Hide ourselves — mirror render threads register audio_router as a
    // WASAPI session on the target device; we must not show it in the UI.
    'audio_router',
  };

  void _refreshSessions() {
    if (!_useNative || _native == null) return;
    try {
      final newSessions = _native!.enumerateAudioSessions()
          .where((s) => !_systemBlocklist.contains(s.processName.toLowerCase()))
          .toList();
      final newPids = newSessions.map((s) => s.processId).toSet();

      // Restore device/volume/mirror assignments from persistent maps
      final rebuilt = newSessions.map((newSession) {
        final pid = newSession.processId;
        AudioSession s = newSession;
        final deviceId = _persistedRoutes[pid];
        if (deviceId != null) s = s.copyWith(assignedDeviceId: deviceId);
        final vol = _persistedVolumes[pid];
        if (vol != null && (s.volume - vol).abs() > 0.01 && !_fadingPids.contains(pid)) {
          // New WASAPI session on new device has wrong volume — reapply
          _native?.setVolume(pid, vol);
          s = s.copyWith(volume: vol);
        }
        // Restore mirrorDeviceIds from current in-memory state so that the
        // periodic 2-second WASAPI refresh doesn't wipe the mirror list.
        final existing = _sessions.where((e) => e.processId == pid).firstOrNull;
        if (existing != null && existing.mirrorDeviceIds.isNotEmpty) {
          s = s.copyWith(mirrorDeviceIds: existing.mirrorDeviceIds);
        }
        return s;
      }).toList();

      // Keep routed sessions that temporarily vanished during device transition
      for (final s in _sessions) {
        if (!newPids.contains(s.processId) &&
            _persistedRoutes.containsKey(s.processId)) {
          rebuilt.add(s.copyWith(isActive: false, peakLevel: 0));
        }
      }

      // Auto-apply route memory for newly appeared sessions
      final existingPids = _sessions.map((s) => s.processId).toSet();
      for (var i = 0; i < rebuilt.length; i++) {
        final s = rebuilt[i];
        final isNew = !existingPids.contains(s.processId);
        if (isNew && s.assignedDeviceId == null) {
          final savedDevice = _routeMemory[s.processName.toLowerCase()];
          if (savedDevice != null && savedDevice.isNotEmpty) {
            _persistedRoutes[s.processId] = savedDevice;
            if (_useNative && _native != null) {
              try { _native!.routeAppToDevice(s.processId, savedDevice); } catch (_) {}
            }
          }
        }
        // Restore mirrors for newly appeared sessions
        if (isNew) {
          final savedMirrors = _mirrorMemory[s.processName.toLowerCase()];
          if (savedMirrors != null && savedMirrors.isNotEmpty) {
            final primaryDeviceId = _persistedRoutes[s.processId] ??
                _routeMemory[s.processName.toLowerCase()];
            if (primaryDeviceId != null && _useNative && _native != null) {
              for (final mirrorId in savedMirrors) {
                // Skip self-mirror: if saved mirror == primary device, skip to avoid echo
                if (mirrorId == primaryDeviceId) continue;
                try { _native!.startMirror(primaryDeviceId, mirrorId); } catch (_) {}
              }
            }
            rebuilt[i] = s.copyWith(mirrorDeviceIds: savedMirrors.toList());
          }
        }
      }

      _sessions = rebuilt;
      notifyListeners();
    } catch (e) {
      debugPrint('Session enumeration error: $e');
    }
  }

  void _refreshPeakLevels() {
    if (!_useNative || _native == null) return;
    try {
      final levels = _native!.getPeakLevels();
      // Do NOT return early on empty — we still need to decay existing levels.

      bool changed = false;
      _sessions = _sessions.map((session) {
        final rawLevel = levels[session.processId] ?? 0.0;

        double newLevel;
        if (rawLevel >= session.peakLevel) {
          // New peak is higher — jump up immediately.
          newLevel = rawLevel;
        } else {
          // Decay: smooth falloff so the bar doesn't snap to 0.
          // 0.88 per tick (33ms) → bar reaches ~1 % after ~35 ticks (~1.1 s).
          newLevel = session.peakLevel * 0.88;
          if (newLevel < 0.005) newLevel = 0.0;
          // Never decay below the actual current level.
          if (newLevel < rawLevel) newLevel = rawLevel;
        }

        if ((newLevel - session.peakLevel).abs() > 0.002) {
          changed = true;
          return session.copyWith(peakLevel: newLevel);
        }
        return session;
      }).toList();

      if (changed) notifyListeners();
    } catch (e) {
      // Silently ignore peak level errors
    }
  }

  // ─── SIMULATION BACKEND ──────────────────────────────────────

  void _initSimulation() {
    _devices = const [
      AudioDevice(
        id: 'speakers_main',
        name: 'Enceintes salon (Realtek High Definition Audio)',
        shortName: 'Enceintes salon',
        isDefault: true,
      ),
      AudioDevice(
        id: 'headset_hyperx',
        name: 'HyperX Cloud II (USB Audio Device)',
        shortName: 'Casque HyperX',
      ),
      AudioDevice(
        id: 'bt_earbuds',
        name: 'Galaxy Buds Pro (Bluetooth)',
        shortName: 'Écouteurs BT',
        isActive: false,
      ),
      AudioDevice(
        id: 'monitor_hdmi',
        name: 'DELL U2723QE (NVIDIA High Definition Audio)',
        shortName: 'Moniteur HDMI',
      ),
    ];

    _sessions = [
      const AudioSession(
        processId: '1',
        processName: 'Spotify',
        displayName: 'Spotify',
        subtitle: 'Kendrick Lamar — Not Like Us',
        isActive: true,
        assignedDeviceId: 'speakers_main',
        peakLevel: 0.65,
      ),
      const AudioSession(
        processId: '2',
        processName: 'Discord',
        displayName: 'Discord',
        subtitle: 'Voice — #general',
        isActive: true,
        assignedDeviceId: 'headset_hyperx',
        peakLevel: 0.3,
      ),
      const AudioSession(
        processId: '3',
        processName: 'Chrome',
        displayName: 'Chrome',
        subtitle: 'YouTube — Tuto Ableton',
        isActive: true,
        assignedDeviceId: 'speakers_main',
        peakLevel: 0.45,
      ),
      const AudioSession(
        processId: '4',
        processName: 'Teams',
        displayName: 'Microsoft Teams',
        subtitle: null,
        isActive: false,
        assignedDeviceId: null,
        peakLevel: 0.0,
      ),
      const AudioSession(
        processId: '5',
        processName: 'VLC',
        displayName: 'VLC media player',
        subtitle: null,
        isActive: false,
        assignedDeviceId: null,
        peakLevel: 0.0,
      ),
    ];

    _pollTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _updateSimulatedPeaks();
    });
  }

  void _updateSimulatedPeaks() {
    bool changed = false;
    _sessions = _sessions.map((session) {
      if (!session.isActive) return session;
      final target = 0.15 + _rng.nextDouble() * 0.7;
      final current = session.peakLevel;
      final newLevel = current + (target - current) * 0.12;
      if ((newLevel - current).abs() > 0.001) {
        changed = true;
        return session.copyWith(peakLevel: newLevel.clamp(0.0, 1.0));
      }
      return session;
    }).toList();
    if (changed) notifyListeners();
  }

  // ─── PUBLIC API ──────────────────────────────────────────────

  void setSessionVolume(String processId, double volume) {
    final clamped = volume.clamp(0.0, 1.0);
    _persistedVolumes[processId] = clamped;
    if (_useNative && _native != null) {
      try {
        _native!.setVolume(processId, clamped);
      } catch (e) {
        debugPrint('Volume set error: $e');
      }
    }
    _sessions = _sessions.map((s) {
      if (s.processId == processId) {
        return s.copyWith(volume: clamped);
      }
      return s;
    }).toList();
    notifyListeners();
  }

  void toggleMute(String processId) {
    final session = _sessions.firstWhere(
      (s) => s.processId == processId,
      orElse: () => throw StateError('Session not found'),
    );
    final newMuted = !session.isMuted;
    if (_useNative && _native != null) {
      try {
        _native!.setMute(processId, newMuted);
      } catch (e) {
        debugPrint('Mute toggle error: $e');
      }
    }
    _sessions = _sessions.map((s) {
      if (s.processId == processId) {
        return s.copyWith(isMuted: newMuted);
      }
      return s;
    }).toList();
    notifyListeners();
  }

  void routeSession(String processId, String deviceId) {
    debugPrint('routeSession called: pid=$processId -> device=$deviceId (native=$_useNative)');

    // Update persistent map so assignedDeviceId survives session reconnections
    if (deviceId.isEmpty) {
      _persistedRoutes.remove(processId);
    } else {
      _persistedRoutes[processId] = deviceId;
    }

    // Persist by process name so the route is restored when the app restarts
    final session = _sessions.where((s) => s.processId == processId).firstOrNull;
    if (session != null) {
      final nameKey = session.processName.toLowerCase();
      if (deviceId.isEmpty) {
        _routeMemory.remove(nameKey);
      } else {
        _routeMemory[nameKey] = deviceId;
      }
      _saveRouteMemory();
    }

    if (_useNative && _native != null) {
      try {
        final hr = _native!.routeAppToDevice(processId, deviceId);
        debugPrint('routeAppToDevice returned: 0x${hr.toUnsigned(32).toRadixString(16).toUpperCase()}');
      } catch (e) {
        debugPrint('Warning: Native routing failed for $processId -> $deviceId: $e');
      }
    }

    _sessions = _sessions.map((s) {
      if (s.processId == processId) {
        return s.copyWith(assignedDeviceId: deviceId.isEmpty ? null : deviceId);
      }
      return s;
    }).toList();
    notifyListeners();
  }

  /// Add a mirror output device for a session (WASAPI loopback).
  void addMirrorDevice(String processId, String primaryDeviceId, String mirrorDeviceId) {
    // Guard: never mirror a device to itself (echo loop)
    if (mirrorDeviceId.isEmpty || primaryDeviceId.isEmpty) return;
    if (mirrorDeviceId == primaryDeviceId) {
      debugPrint('addMirrorDevice: blocked self-mirror ($mirrorDeviceId == primary)');
      return;
    }

    // Check if already mirroring
    final session = _sessions.firstWhere(
      (s) => s.processId == processId,
      orElse: () => throw StateError('Session not found'),
    );
    if (session.mirrorDeviceIds.contains(mirrorDeviceId)) return;
    // Guard: mirror == current assigned device (would create A→A mirror)
    if (session.assignedDeviceId != null && mirrorDeviceId == session.assignedDeviceId) {
      debugPrint('addMirrorDevice: blocked mirror == assignedDevice ($mirrorDeviceId)');
      return;
    }

    if (_useNative && _native != null) {
      try { _native!.startMirror(primaryDeviceId, mirrorDeviceId); } catch (e) {
        debugPrint('startMirror error: $e');
      }
    }

    _sessions = _sessions.map((s) {
      if (s.processId == processId) {
        return s.copyWith(mirrorDeviceIds: [...s.mirrorDeviceIds, mirrorDeviceId]);
      }
      return s;
    }).toList();

    // Persist by process name
    final nameKey = session.processName.toLowerCase();
    _mirrorMemory.putIfAbsent(nameKey, () => {}).add(mirrorDeviceId);
    _saveMirrorMemory();
    notifyListeners();
  }

  /// Remove a mirror output device for a session.
  void removeMirrorDevice(String processId, String primaryDeviceId, String mirrorDeviceId) {
    if (_useNative && _native != null) {
      try { _native!.stopMirror(primaryDeviceId, mirrorDeviceId); } catch (e) {
        debugPrint('stopMirror error: $e');
      }
    }

    final session = _sessions.firstWhere(
      (s) => s.processId == processId,
      orElse: () => throw StateError('Session not found'),
    );

    _sessions = _sessions.map((s) {
      if (s.processId == processId) {
        return s.copyWith(
          mirrorDeviceIds: s.mirrorDeviceIds.where((id) => id != mirrorDeviceId).toList(),
        );
      }
      return s;
    }).toList();

    // Persist
    final nameKey = session.processName.toLowerCase();
    _mirrorMemory[nameKey]?.remove(mirrorDeviceId);
    if (_mirrorMemory[nameKey]?.isEmpty == true) _mirrorMemory.remove(nameKey);
    _saveMirrorMemory();
    notifyListeners();
  }

  /// Returns mirror devices for a session.
  List<AudioDevice> getMirrorDevicesForSession(AudioSession session) {
    return session.mirrorDeviceIds
        .map((id) {
          try { return _devices.firstWhere((d) => d.id == id); } catch (_) { return null; }
        })
        .whereType<AudioDevice>()
        .toList();
  }

  /// Reset all apps to the system default audio device and stop all mirrors.
  void resetAllRoutes() {
    for (final t in _activeFades.values) { t.cancel(); }
    _activeFades.clear();
    _fadingPids.clear();
    _persistedRoutes.clear();
    _persistedVolumes.clear();
    if (_useNative && _native != null) {
      try { _native!.stopAllMirrors(); } catch (_) {}
    }
    _sessions = _sessions.map((s) => s.copyWith(mirrorDeviceIds: [])).toList();
    for (final session in _sessions) {
      routeSession(session.processId, '');
    }
  }

  void setDeviceVolume(String deviceId, double volume) {
    if (_useNative && _native != null) {
      try {
        _native!.setDeviceVolume(deviceId, volume);
      } catch (e) {
        debugPrint('Device volume set error: $e');
      }
    }
    _devices = _devices.map((d) {
      if (d.id == deviceId) return d.copyWith(volume: volume.clamp(0.0, 1.0));
      return d;
    }).toList();
    notifyListeners();
  }

  /// Returns raw 32×32 RGBA bytes for the process icon, or null on failure.
  Uint8List? getAppIconBytes(String processId) {
    if (!_useNative || _native == null) return null;
    try {
      return _native!.getAppIcon(processId);
    } catch (_) {
      return null;
    }
  }

  AudioDevice? getDeviceForSession(AudioSession session) {
    if (session.assignedDeviceId == null) return null;
    try {
      return _devices.firstWhere((d) => d.id == session.assignedDeviceId);
    } catch (_) {
      return null;
    }
  }

  // ─── PROFILE APPLICATION ─────────────────────────────────

  /// Apply a saved profile to the current sessions.
  /// Matches sessions by processName (case-insensitive).
  void applyProfile(RoutingProfile profile) {
    // Reset existing routes first (native + in-memory)
    for (final s in _sessions) {
      _persistedRoutes.remove(s.processId);
      if (_useNative && _native != null) {
        try { _native!.routeAppToDevice(s.processId, ''); } catch (_) {}
      }
    }
    _persistedRoutes.clear();

    // Apply profile routes
    for (final s in _sessions) {
      final deviceId = profile.routes[s.processName] ??
          profile.routes[s.processName.toLowerCase()];
      if (deviceId != null && deviceId.isNotEmpty) {
        routeSession(s.processId, deviceId);
      }
    }

    // Apply profile volumes
    for (final s in _sessions) {
      final vol = profile.volumes[s.processName] ??
          profile.volumes[s.processName.toLowerCase()];
      if (vol != null) {
        setSessionVolume(s.processId, vol);
      }
    }

    notifyListeners();
  }

  // ─── ROUTE MEMORY ────────────────────────────────────────

  Future<void> _loadRouteMemory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('route_memory');
      if (json != null) {
        final map = jsonDecode(json) as Map;
        _routeMemory = Map<String, String>.from(map);
      }
    } catch (e) {
      debugPrint('Route memory load error: $e');
    }
  }

  Future<void> _saveRouteMemory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('route_memory', jsonEncode(_routeMemory));
    } catch (e) {
      debugPrint('Route memory save error: $e');
    }
  }

  /// Clear all remembered routes (called from UI reset button).
  Future<void> clearRouteMemory() async {
    _routeMemory.clear();
    _mirrorMemory.clear();
    await _saveRouteMemory();
    await _saveMirrorMemory();
  }

  Future<void> _loadMirrorMemory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('mirror_memory');
      if (json != null) {
        final map = jsonDecode(json) as Map;
        _mirrorMemory = map.map((k, v) =>
          MapEntry(k as String, Set<String>.from(v as List)));
      }
    } catch (e) {
      debugPrint('Mirror memory load error: $e');
    }
  }

  Future<void> _saveMirrorMemory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = _mirrorMemory.map((k, v) => MapEntry(k, v.toList()));
      await prefs.setString('mirror_memory', jsonEncode(encoded));
    } catch (e) {
      debugPrint('Mirror memory save error: $e');
    }
  }

  // ─── AUTO-DUCK ────────────────────────────────────────────

  void addDuckRule(DuckRule rule) {
    _duckRules.add(rule);
    _saveDuckRules();
    notifyListeners();
  }

  void updateDuckRule(DuckRule updated) {
    _duckRules = _duckRules.map((r) => r.id == updated.id ? updated : r).toList();
    _saveDuckRules();
    notifyListeners();
  }

  void removeDuckRule(String ruleId) {
    _duckRules.removeWhere((r) => r.id == ruleId);
    _saveDuckRules();
    notifyListeners();
  }

  /// Smoothly fade a session's volume from [fromVol] to [toVol] over ~800ms.
  /// Immediately locks [_persistedVolumes] to the target so _refreshSessions
  /// converges there once the fade completes.
  void _fadeToVolume(String processId, String processName, double fromVol, double toVol) {
    _activeFades[processName]?.cancel();
    _fadingPids.add(processId);
    _persistedVolumes[processId] = toVol.clamp(0.0, 1.0);

    const steps = 16;
    const stepMs = 50; // 800ms total
    int step = 0;

    _activeFades[processName] = Timer.periodic(
      const Duration(milliseconds: stepMs),
      (timer) {
        step++;
        final t = step / steps;
        final vol = (fromVol + (toVol - fromVol) * t).clamp(0.0, 1.0);
        if (_useNative && _native != null) {
          _native!.setVolume(processId, vol);
        }
        _sessions = _sessions.map((s) {
          if (s.processId == processId) return s.copyWith(volume: vol);
          return s;
        }).toList();
        notifyListeners();
        if (step >= steps) {
          timer.cancel();
          _activeFades.remove(processName);
          _fadingPids.remove(processId);
        }
      },
    );
  }

  void _evaluateDuckRules() {
    if (_sessions.isEmpty || _duckRules.isEmpty) return;

    final activeNames = _sessions
        .where((s) => s.isActive)
        .map((s) => s.processName.toLowerCase())
        .toSet();

    // Determine which targets should be ducked right now
    final shouldBeDucked = <String, double>{}; // targetName -> duckedVolume
    for (final rule in _duckRules) {
      if (!rule.enabled) continue;
      if (activeNames.contains(rule.triggerProcessName.toLowerCase())) {
        final key = rule.targetProcessName.toLowerCase();
        // If multiple rules duck the same target, use the lowest volume
        if (!shouldBeDucked.containsKey(key) || rule.duckedVolume < shouldBeDucked[key]!) {
          shouldBeDucked[key] = rule.duckedVolume;
        }
      }
    }

    // Apply ducks
    for (final entry in shouldBeDucked.entries) {
      final targetName = entry.key;
      final duckedVol = entry.value;
      if (!_currentlyDucked.contains(targetName)) {
        // Save original volume and duck
        final target = _sessions.where(
          (s) => s.processName.toLowerCase() == targetName,
        ).firstOrNull;
        if (target != null) {
          _originalVolumes[targetName] = _persistedVolumes[target.processId] ?? target.volume;
          _currentlyDucked.add(targetName);
          _fadeToVolume(target.processId, targetName, target.volume, duckedVol);
        }
      }
    }

    // Restore volumes for targets that should no longer be ducked
    final toRestore = _currentlyDucked.difference(shouldBeDucked.keys.toSet());
    for (final targetName in toRestore) {
      final target = _sessions.where(
        (s) => s.processName.toLowerCase() == targetName,
      ).firstOrNull;
      if (target != null) {
        final origVol = _originalVolumes[targetName] ?? 1.0;
        _fadeToVolume(target.processId, targetName, target.volume, origVol);
      }
      _originalVolumes.remove(targetName);
      _currentlyDucked.remove(targetName);
    }
  }

  Future<void> _loadDuckRules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('duck_rules');
      if (json != null) {
        final list = jsonDecode(json) as List;
        _duckRules = list.map((e) => DuckRule.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('Failed to load duck rules: $e');
    }
  }

  Future<void> _saveDuckRules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_duckRules.map((r) => r.toJson()).toList());
      await prefs.setString('duck_rules', json);
    } catch (e) {
      debugPrint('Failed to save duck rules: $e');
    }
  }

  bool isSessionDucked(String processName) =>
      _currentlyDucked.contains(processName.toLowerCase());

  // ─── AUTO-START ───────────────────────────────────────────

  bool get autostart => _useNative && _native != null && _native!.getAutostart();

  void setAutostart(bool enabled) {
    if (_useNative && _native != null) {
      _native!.setAutostart(enabled);
      notifyListeners();
    }
  }

  // ─── GLOBAL HOTKEYS ────────────────────────────────────────

  // MOD_CONTROL = 2, MOD_ALT = 1
  static const int _modCtrlAlt = 3; // MOD_CONTROL | MOD_ALT
  // VK_1..VK_4 = 0x31..0x34
  final Map<int, String> _hotkeyProfileMap = {};
  VoidCallback? onHotkeyProfileSwitch;

  /// Register Ctrl+Alt+1..N for profile switching.
  void registerProfileHotkeys(List<String> profileIds) {
    if (!_useNative || _native == null) return;

    // Unregister old hotkeys
    for (final id in _hotkeyProfileMap.keys) {
      _native!.unregisterHotkey(id);
    }
    _hotkeyProfileMap.clear();

    // Register new ones (Ctrl+Alt+1 through Ctrl+Alt+N, max 9)
    for (int i = 0; i < profileIds.length && i < 9; i++) {
      final hotkeyId = i + 1;
      final vk = 0x31 + i; // VK_1 = 0x31
      if (_native!.registerHotkey(hotkeyId, _modCtrlAlt, vk)) {
        _hotkeyProfileMap[hotkeyId] = profileIds[i];
      }
    }
  }

  void _pollHotkeys() {
    if (!_useNative || _native == null) return;
    final id = _native!.pollHotkey();
    if (id > 0 && _hotkeyProfileMap.containsKey(id)) {
      _lastHotkeyProfileId = _hotkeyProfileMap[id];
      onHotkeyProfileSwitch?.call();
    }
  }

  String? _lastHotkeyProfileId;
  String? consumeHotkeyProfile() {
    final id = _lastHotkeyProfileId;
    _lastHotkeyProfileId = null;
    return id;
  }

  AudioDevice get defaultDevice =>
      _devices.firstWhere((d) => d.isDefault, orElse: () => _devices.first);

  bool get isNativeMode => _useNative;

  bool _listEquals(List<AudioDevice> a, List<AudioDevice> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _refreshTimer?.cancel();
    _duckTimer?.cancel();
    _hotkeyTimer?.cancel();
    for (final t in _activeFades.values) { t.cancel(); }
    _activeFades.clear();
    // Unregister hotkeys
    if (_useNative && _native != null) {
      for (final id in _hotkeyProfileMap.keys) {
        _native!.unregisterHotkey(id);
      }
    }
    _native?.dispose();
    super.dispose();
  }
}
