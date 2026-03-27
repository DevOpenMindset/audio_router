// ignore_for_file: non_constant_identifier_names, constant_identifier_names
//
// Native audio bridge — thin Dart FFI wrapper around audio_backend.dll (C++).
// All COM/WASAPI work happens in C++; this file only marshals data across FFI.

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import '../models/audio_models.dart';

// ─── C struct mirrors for FFI ────────────────────────────────

// Must match AudioDeviceInfo in audio_backend.h
final class AudioDeviceInfoNative extends Struct {
  @Array(256)
  external Array<Uint16> id;
  @Array(256)
  external Array<Uint16> name;
  @Array(128)
  external Array<Uint16> short_name;
  @Int32()
  external int is_default;
  @Int32()
  external int is_active;
  @Float()
  external double volume;
}

// Must match AudioSessionInfo in audio_backend.h
final class AudioSessionInfoNative extends Struct {
  @Uint32()
  external int process_id;
  @Array(256)
  external Array<Uint16> process_name;
  @Array(256)
  external Array<Uint16> display_name;
  @Int32()
  external int is_active;
  @Float()
  external double peak_level;
  @Float()
  external double volume;
  @Int32()
  external int is_muted;
}

// Must match PeakLevelInfo in audio_backend.h
final class PeakLevelInfoNative extends Struct {
  @Uint32()
  external int process_id;
  @Float()
  external double peak_level;
}

// ─── FFI function typedefs ───────────────────────────────────

typedef _AudioInitC = Int32 Function();
typedef _AudioInitDart = int Function();

typedef _AudioCleanupC = Void Function();
typedef _AudioCleanupDart = void Function();

typedef _AudioGetDeviceCountC = Int32 Function();
typedef _AudioGetDeviceCountDart = int Function();

typedef _AudioGetDevicesC = Int32 Function(
    Pointer<AudioDeviceInfoNative>, Int32);
typedef _AudioGetDevicesDart = int Function(
    Pointer<AudioDeviceInfoNative>, int);

typedef _AudioGetSessionCountC = Int32 Function();
typedef _AudioGetSessionCountDart = int Function();

typedef _AudioGetSessionsC = Int32 Function(
    Pointer<AudioSessionInfoNative>, Int32);
typedef _AudioGetSessionsDart = int Function(
    Pointer<AudioSessionInfoNative>, int);

typedef _AudioRouteProcessC = Int32 Function(Uint32, Pointer<Utf16>);
typedef _AudioRouteProcessDart = int Function(int, Pointer<Utf16>);

typedef _AudioSetVolumeC = Int32 Function(Uint32, Float);
typedef _AudioSetVolumeDart = int Function(int, double);

typedef _AudioSetMuteC = Int32 Function(Uint32, Int32);
typedef _AudioSetMuteDart = int Function(int, int);

typedef _AudioSetAutostartC = Int32 Function(Int32);
typedef _AudioSetAutostartDart = int Function(int);

typedef _AudioGetAutostartC = Int32 Function();
typedef _AudioGetAutostartDart = int Function();

typedef _AudioRegisterHotkeyC = Int32 Function(Int32, Uint32, Uint32);
typedef _AudioRegisterHotkeyDart = int Function(int, int, int);

typedef _AudioUnregisterHotkeyC = Int32 Function(Int32);
typedef _AudioUnregisterHotkeyDart = int Function(int);

typedef _AudioPollHotkeyC = Int32 Function();
typedef _AudioPollHotkeyDart = int Function();

typedef _AudioGetVtableSlotC = Int32 Function();
typedef _AudioGetVtableSlotDart = int Function();

typedef _AudioGetDeviceVolumeC = Float Function(Pointer<Utf16>);
typedef _AudioGetDeviceVolumeDart = double Function(Pointer<Utf16>);

typedef _AudioSetDeviceVolumeC = Int32 Function(Pointer<Utf16>, Float);
typedef _AudioSetDeviceVolumeDart = int Function(Pointer<Utf16>, double);

typedef _AudioGetAppIconC = Int32 Function(
    Uint32, Pointer<Uint8>, Int32, Pointer<Int32>, Pointer<Int32>);
typedef _AudioGetAppIconDart = int Function(
    int, Pointer<Uint8>, int, Pointer<Int32>, Pointer<Int32>);

typedef _AudioPollPeaksC = Int32 Function(Pointer<PeakLevelInfoNative>, Int32);
typedef _AudioPollPeaksDart = int Function(Pointer<PeakLevelInfoNative>, int);

typedef _AudioStartMirrorC = Int32 Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _AudioStartMirrorDart = int Function(Pointer<Utf16>, Pointer<Utf16>);

typedef _AudioStopMirrorC = Int32 Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _AudioStopMirrorDart = int Function(Pointer<Utf16>, Pointer<Utf16>);

typedef _AudioStopAllMirrorsC = Void Function();
typedef _AudioStopAllMirrorsDart = void Function();

// ─── Helper: read wchar_t[] from FFI Array ───────────────────

String _readWCharArray(Array<Uint16> arr, int maxLen) {
  final codes = <int>[];
  for (int i = 0; i < maxLen; i++) {
    final c = arr[i];
    if (c == 0) break;
    codes.add(c);
  }
  return String.fromCharCodes(codes);
}

// ─── NativeAudioBridge ───────────────────────────────────────

/// Native audio backend that delegates to audio_backend.dll (Windows)
/// or libaudio_backend.dylib (macOS). This class only marshals data.
class NativeAudioBridge {
  late final DynamicLibrary _lib;
  bool _initialized = false;

  late final _AudioInitDart _audioInit;
  late final _AudioCleanupDart _audioCleanup;
  late final _AudioGetDeviceCountDart _getDeviceCount;
  late final _AudioGetDevicesDart _getDevices;
  late final _AudioGetSessionCountDart _getSessionCount;
  late final _AudioGetSessionsDart _getSessions;
  late final _AudioRouteProcessDart _routeProcess;
  late final _AudioSetVolumeDart _setVolume;
  late final _AudioSetMuteDart _setMute;
  late final _AudioSetAutostartDart _setAutostart;
  late final _AudioGetAutostartDart _getAutostart;
  late final _AudioRegisterHotkeyDart _registerHotkey;
  late final _AudioUnregisterHotkeyDart _unregisterHotkey;
  late final _AudioPollHotkeyDart _pollHotkey;
  late final _AudioGetVtableSlotDart _getVtableSlot;
  late final _AudioGetDeviceVolumeDart _getDeviceVolume;
  late final _AudioSetDeviceVolumeDart _setDeviceVolume;
  late final _AudioGetAppIconDart _getAppIcon;
  late final _AudioPollPeaksDart _pollPeaks;
  late final _AudioStartMirrorDart _startMirror;
  late final _AudioStopMirrorDart _stopMirror;
  late final _AudioStopAllMirrorsDart _stopAllMirrors;

  /// Load the native audio library and resolve all function symbols.
  /// Windows: audio_backend.dll  |  macOS: libaudio_backend.dylib
  Future<void> initialize() async {
    if (_initialized) return;

    final String libPath;

    if (Platform.isWindows) {
      // DLL sits next to the executable
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      libPath = '$exeDir\\audio_backend.dll';
    } else if (Platform.isMacOS) {
      // dylib is embedded in the app bundle's Frameworks directory
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final inFrameworks = '$exeDir/../Frameworks/libaudio_backend.dylib';
      // Fallback: next to the executable (useful during development)
      final nextToExe = '$exeDir/libaudio_backend.dylib';
      libPath = File(inFrameworks).existsSync() ? inFrameworks : nextToExe;
    } else {
      throw StateError('Unsupported platform: ${Platform.operatingSystem}');
    }

    if (!File(libPath).existsSync()) {
      throw StateError(
        'Native audio library not found at $libPath\n'
        'Windows: build audio_backend.dll from windows/audio_backend/\n'
        'macOS:   run macos/audio_backend/build.sh, then embed in app bundle.',
      );
    }

    _lib = DynamicLibrary.open(libPath);

    _audioInit = _lib
        .lookupFunction<_AudioInitC, _AudioInitDart>('audio_init');
    _audioCleanup = _lib
        .lookupFunction<_AudioCleanupC, _AudioCleanupDart>('audio_cleanup');
    _getDeviceCount = _lib
        .lookupFunction<_AudioGetDeviceCountC, _AudioGetDeviceCountDart>(
            'audio_get_device_count');
    _getDevices = _lib
        .lookupFunction<_AudioGetDevicesC, _AudioGetDevicesDart>(
            'audio_get_devices');
    _getSessionCount = _lib
        .lookupFunction<_AudioGetSessionCountC, _AudioGetSessionCountDart>(
            'audio_get_session_count');
    _getSessions = _lib
        .lookupFunction<_AudioGetSessionsC, _AudioGetSessionsDart>(
            'audio_get_sessions');
    _routeProcess = _lib
        .lookupFunction<_AudioRouteProcessC, _AudioRouteProcessDart>(
            'audio_route_process');
    _setVolume = _lib
        .lookupFunction<_AudioSetVolumeC, _AudioSetVolumeDart>(
            'audio_set_volume');
    _setMute = _lib
        .lookupFunction<_AudioSetMuteC, _AudioSetMuteDart>(
            'audio_set_mute');
    _setAutostart = _lib
        .lookupFunction<_AudioSetAutostartC, _AudioSetAutostartDart>(
            'audio_set_autostart');
    _getAutostart = _lib
        .lookupFunction<_AudioGetAutostartC, _AudioGetAutostartDart>(
            'audio_get_autostart');
    _registerHotkey = _lib
        .lookupFunction<_AudioRegisterHotkeyC, _AudioRegisterHotkeyDart>(
            'audio_register_hotkey');
    _unregisterHotkey = _lib
        .lookupFunction<_AudioUnregisterHotkeyC, _AudioUnregisterHotkeyDart>(
            'audio_unregister_hotkey');
    _pollHotkey = _lib
        .lookupFunction<_AudioPollHotkeyC, _AudioPollHotkeyDart>(
            'audio_poll_hotkey');
    _getVtableSlot = _lib
        .lookupFunction<_AudioGetVtableSlotC, _AudioGetVtableSlotDart>(
            'audio_get_vtable_slot');
    _getDeviceVolume = _lib
        .lookupFunction<_AudioGetDeviceVolumeC, _AudioGetDeviceVolumeDart>(
            'audio_get_device_volume');
    _setDeviceVolume = _lib
        .lookupFunction<_AudioSetDeviceVolumeC, _AudioSetDeviceVolumeDart>(
            'audio_set_device_volume');
    _getAppIcon = _lib
        .lookupFunction<_AudioGetAppIconC, _AudioGetAppIconDart>(
            'audio_get_app_icon');
    _pollPeaks = _lib
        .lookupFunction<_AudioPollPeaksC, _AudioPollPeaksDart>(
            'audio_poll_peaks');
    _startMirror = _lib
        .lookupFunction<_AudioStartMirrorC, _AudioStartMirrorDart>(
            'audio_start_mirror');
    _stopMirror = _lib
        .lookupFunction<_AudioStopMirrorC, _AudioStopMirrorDart>(
            'audio_stop_mirror');
    _stopAllMirrors = _lib
        .lookupFunction<_AudioStopAllMirrorsC, _AudioStopAllMirrorsDart>(
            'audio_stop_all_mirrors');

    // Initialize COM inside the DLL
    final hr = _audioInit();
    if (hr != 0) {
      throw StateError('audio_init failed with HRESULT 0x${hr.toRadixString(16)}');
    }

    _initialized = true;
    debugPrint('NativeAudioBridge: initialized via audio_backend.dll');
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'NativeAudioBridge not initialized. Call initialize() first.',
      );
    }
  }

  /// Enumerate all active audio output (render) devices.
  List<AudioDevice> enumerateDevices() {
    _ensureInitialized();

    const maxDevices = 32;
    final pDevices = calloc<AudioDeviceInfoNative>(maxDevices);

    try {
      final count = _getDevices(pDevices, maxDevices);
      final devices = <AudioDevice>[];

      for (int i = 0; i < count; i++) {
        final d = pDevices[i];
        devices.add(AudioDevice(
          id: _readWCharArray(d.id, 256),
          name: _readWCharArray(d.name, 256),
          shortName: _readWCharArray(d.short_name, 128),
          isDefault: d.is_default != 0,
          isActive: d.is_active != 0,
          volume: d.volume.clamp(0.0, 1.0),
        ));
      }

      return devices;
    } finally {
      calloc.free(pDevices);
    }
  }

  /// Enumerate all active audio sessions (apps producing audio).
  List<AudioSession> enumerateAudioSessions() {
    _ensureInitialized();

    const maxSessions = 64;
    final pSessions = calloc<AudioSessionInfoNative>(maxSessions);

    try {
      final count = _getSessions(pSessions, maxSessions);
      final sessions = <AudioSession>[];

      for (int i = 0; i < count; i++) {
        final s = pSessions[i];
        sessions.add(AudioSession(
          processId: s.process_id.toString(),
          processName: _readWCharArray(s.process_name, 256),
          displayName: _readWCharArray(s.display_name, 256),
          peakLevel: s.peak_level.clamp(0.0, 1.0),
          volume: s.volume.clamp(0.0, 1.0),
          isMuted: s.is_muted != 0,
          isActive: s.is_active != 0,
        ));
      }

      return sessions;
    } finally {
      calloc.free(pSessions);
    }
  }

  /// Get peak levels for all current sessions via the dedicated fast-poll function.
  /// Does NOT re-enumerate WASAPI sessions — reads cached device meters only.
  Map<String, double> getPeakLevels() {
    _ensureInitialized();

    const maxSessions = 64;
    final pPeaks = calloc<PeakLevelInfoNative>(maxSessions);

    try {
      final count = _pollPeaks(pPeaks, maxSessions);
      final levels = <String, double>{};

      for (int i = 0; i < count; i++) {
        final p = pPeaks[i];
        levels[p.process_id.toString()] = p.peak_level.clamp(0.0, 1.0);
      }

      return levels;
    } finally {
      calloc.free(pPeaks);
    }
  }

  /// Route a process's audio to a specific device.
  /// Returns the HRESULT: 0=COM success, 1=registry fallback, negative=error.
  int routeAppToDevice(String processId, String deviceId) {
    _ensureInitialized();

    final pDeviceId = deviceId.toNativeUtf16();
    try {
      final pid = int.tryParse(processId) ?? 0;
      final hr = _routeProcess(pid, pDeviceId);
      final slot = _getVtableSlot();
      final path = hr == 0
          ? 'COM vtable slot $slot'
          : hr == 1
              ? 'registry fallback'
              : 'error 0x${hr.toUnsigned(32).toRadixString(16).toUpperCase()}';
      debugPrint('routeAppToDevice: pid=$pid path=$path');
      return hr;
    } finally {
      calloc.free(pDeviceId);
    }
  }

  /// Set volume for a specific process (0.0 - 1.0).
  void setVolume(String processId, double volume) {
    _ensureInitialized();
    final pid = int.tryParse(processId) ?? 0;
    _setVolume(pid, volume.clamp(0.0, 1.0));
  }

  /// Set mute state for a specific process.
  void setMute(String processId, bool muted) {
    _ensureInitialized();
    final pid = int.tryParse(processId) ?? 0;
    _setMute(pid, muted ? 1 : 0);
  }

  /// Get master volume for a device (0.0 - 1.0). Returns -1 on error.
  double getDeviceVolume(String deviceId) {
    _ensureInitialized();
    final pId = deviceId.toNativeUtf16();
    try {
      return _getDeviceVolume(pId);
    } finally {
      calloc.free(pId);
    }
  }

  /// Set master volume for a device (0.0 - 1.0).
  void setDeviceVolume(String deviceId, double volume) {
    _ensureInitialized();
    final pId = deviceId.toNativeUtf16();
    try {
      _setDeviceVolume(pId, volume.clamp(0.0, 1.0));
    } finally {
      calloc.free(pId);
    }
  }

  /// Enable or disable auto-start at Windows login.
  void setAutostart(bool enabled) {
    _ensureInitialized();
    _setAutostart(enabled ? 1 : 0);
  }

  /// Check if auto-start is enabled.
  bool getAutostart() {
    _ensureInitialized();
    return _getAutostart() != 0;
  }

  /// Register a global hotkey. Returns true on success.
  /// modifiers: MOD_ALT=1, MOD_CONTROL=2, MOD_SHIFT=4, MOD_WIN=8
  bool registerHotkey(int id, int modifiers, int virtualKey) {
    _ensureInitialized();
    return _registerHotkey(id, modifiers, virtualKey) == 0;
  }

  /// Unregister a global hotkey.
  void unregisterHotkey(int id) {
    _ensureInitialized();
    _unregisterHotkey(id);
  }

  /// Poll for hotkey press. Returns hotkey id or 0 if none.
  int pollHotkey() {
    _ensureInitialized();
    return _pollHotkey();
  }

  /// Get app icon as 32×32 RGBA bytes. Returns null on error.
  Uint8List? getAppIcon(String processId) {
    _ensureInitialized();
    const w = 32, h = 32;
    const bufSize = w * h * 4;
    final buf = calloc<Uint8>(bufSize);
    final pW = calloc<Int32>();
    final pH = calloc<Int32>();
    try {
      final pid = int.tryParse(processId) ?? 0;
      final result = _getAppIcon(pid, buf, bufSize, pW, pH);
      if (result != 0) return null;
      return Uint8List.fromList(buf.asTypedList(bufSize));
    } finally {
      calloc.free(buf);
      calloc.free(pW);
      calloc.free(pH);
    }
  }

  /// Start mirroring audio from sourceDeviceId to targetDeviceId.
  void startMirror(String sourceDeviceId, String targetDeviceId) {
    _ensureInitialized();
    final pSrc = sourceDeviceId.toNativeUtf16();
    final pTgt = targetDeviceId.toNativeUtf16();
    try {
      _startMirror(pSrc, pTgt);
    } finally {
      calloc.free(pSrc);
      calloc.free(pTgt);
    }
  }

  /// Stop mirroring from sourceDeviceId to targetDeviceId.
  void stopMirror(String sourceDeviceId, String targetDeviceId) {
    _ensureInitialized();
    final pSrc = sourceDeviceId.toNativeUtf16();
    final pTgt = targetDeviceId.toNativeUtf16();
    try {
      _stopMirror(pSrc, pTgt);
    } finally {
      calloc.free(pSrc);
      calloc.free(pTgt);
    }
  }

  /// Stop all active mirror threads.
  void stopAllMirrors() {
    if (!_initialized) return;
    _stopAllMirrors();
  }

  /// Clean up COM resources.
  void dispose() {
    if (_initialized) {
      _audioCleanup();
      _initialized = false;
    }
  }
}
