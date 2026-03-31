// ignore_for_file: non_constant_identifier_names, constant_identifier_names
//
// Native audio bridge for Linux — thin Dart FFI wrapper around libaudio_backend.so.
// Uses char[] (UTF-8) instead of wchar_t[] (UTF-16) for string fields.
// All PipeWire/PulseAudio work happens in C; this file only marshals data across FFI.

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import '../models/audio_models.dart';
import 'audio_bridge.dart';

// ─── C struct mirrors for Linux FFI (UTF-8 char[]) ──────────

// Must match AudioDeviceInfo in audio_backend_linux.h
final class AudioDeviceInfoLinux extends Struct {
  @Array(256)
  external Array<Uint8> id;
  @Array(256)
  external Array<Uint8> name;
  @Array(128)
  external Array<Uint8> short_name;
  @Int32()
  external int is_default;
  @Int32()
  external int is_active;
  @Float()
  external double volume;
}

// Must match AudioSessionInfo in audio_backend_linux.h
final class AudioSessionInfoLinux extends Struct {
  @Uint32()
  external int process_id;
  @Array(256)
  external Array<Uint8> process_name;
  @Array(256)
  external Array<Uint8> display_name;
  @Int32()
  external int is_active;
  @Float()
  external double peak_level;
  @Float()
  external double volume;
  @Int32()
  external int is_muted;
}

// Must match PeakLevelInfo in audio_backend_linux.h
final class PeakLevelInfoLinux extends Struct {
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
    Pointer<AudioDeviceInfoLinux>, Int32);
typedef _AudioGetDevicesDart = int Function(
    Pointer<AudioDeviceInfoLinux>, int);

typedef _AudioGetSessionCountC = Int32 Function();
typedef _AudioGetSessionCountDart = int Function();

typedef _AudioGetSessionsC = Int32 Function(
    Pointer<AudioSessionInfoLinux>, Int32);
typedef _AudioGetSessionsDart = int Function(
    Pointer<AudioSessionInfoLinux>, int);

// Linux uses char* (Pointer<Utf8>) instead of wchar_t* (Pointer<Utf16>)
typedef _AudioRouteProcessC = Int32 Function(Uint32, Pointer<Utf8>);
typedef _AudioRouteProcessDart = int Function(int, Pointer<Utf8>);

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

typedef _AudioGetDeviceVolumeC = Float Function(Pointer<Utf8>);
typedef _AudioGetDeviceVolumeDart = double Function(Pointer<Utf8>);

typedef _AudioSetDeviceVolumeC = Int32 Function(Pointer<Utf8>, Float);
typedef _AudioSetDeviceVolumeDart = int Function(Pointer<Utf8>, double);

typedef _AudioGetAppIconC = Int32 Function(
    Uint32, Pointer<Uint8>, Int32, Pointer<Int32>, Pointer<Int32>);
typedef _AudioGetAppIconDart = int Function(
    int, Pointer<Uint8>, int, Pointer<Int32>, Pointer<Int32>);

typedef _AudioPollPeaksC = Int32 Function(Pointer<PeakLevelInfoLinux>, Int32);
typedef _AudioPollPeaksDart = int Function(Pointer<PeakLevelInfoLinux>, int);

typedef _AudioStartMirrorC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _AudioStartMirrorDart = int Function(Pointer<Utf8>, Pointer<Utf8>);

typedef _AudioStopMirrorC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _AudioStopMirrorDart = int Function(Pointer<Utf8>, Pointer<Utf8>);

typedef _AudioStopAllMirrorsC = Void Function();
typedef _AudioStopAllMirrorsDart = void Function();

typedef _AudioSetDefaultDeviceC = Int32 Function(Pointer<Utf8>);
typedef _AudioSetDefaultDeviceDart = int Function(Pointer<Utf8>);

typedef _AudioGetDeviceBalanceC = Float Function(Pointer<Utf8>);
typedef _AudioGetDeviceBalanceDart = double Function(Pointer<Utf8>);

typedef _AudioSetDeviceBalanceC = Int32 Function(Pointer<Utf8>, Float);
typedef _AudioSetDeviceBalanceDart = int Function(Pointer<Utf8>, double);

typedef _AudioOpenSoundSettingsC = Int32 Function();
typedef _AudioOpenSoundSettingsDart = int Function();

typedef _AudioGetAccentColorC = Uint32 Function();
typedef _AudioGetAccentColorDart = int Function();

// ─── Helper: read char[] (UTF-8) from FFI Array ─────────────

String _readUtf8Array(Array<Uint8> arr, int maxLen) {
  final codes = <int>[];
  for (int i = 0; i < maxLen; i++) {
    final c = arr[i];
    if (c == 0) break;
    codes.add(c);
  }
  return String.fromCharCodes(codes);
}

// ─── NativeAudioBridgeLinux ─────────────────────────────────

/// Native audio backend for Linux — delegates to libaudio_backend.so
/// which uses PipeWire or PulseAudio under the hood.
class NativeAudioBridgeLinux implements AudioBridge {
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
  late final _AudioSetDefaultDeviceDart _setDefaultDevice;
  late final _AudioGetDeviceBalanceDart _getDeviceBalance;
  late final _AudioSetDeviceBalanceDart _setDeviceBalance;
  late final _AudioOpenSoundSettingsDart _openSoundSettings;
  late final _AudioGetAccentColorDart _getAccentColor;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    // libaudio_backend.so sits in the lib/ subdirectory of the bundle
    final inLib = '$exeDir/lib/libaudio_backend.so';
    final nextToExe = '$exeDir/libaudio_backend.so';
    final libPath = File(inLib).existsSync() ? inLib : nextToExe;

    if (!File(libPath).existsSync()) {
      throw StateError(
        'Native audio library not found at $libPath\n'
        'Linux: build libaudio_backend.so from linux/audio_backend/',
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
    _setDefaultDevice = _lib
        .lookupFunction<_AudioSetDefaultDeviceC, _AudioSetDefaultDeviceDart>(
            'audio_set_default_device');
    _getDeviceBalance = _lib
        .lookupFunction<_AudioGetDeviceBalanceC, _AudioGetDeviceBalanceDart>(
            'audio_get_device_balance');
    _setDeviceBalance = _lib
        .lookupFunction<_AudioSetDeviceBalanceC, _AudioSetDeviceBalanceDart>(
            'audio_set_device_balance');
    _openSoundSettings = _lib
        .lookupFunction<_AudioOpenSoundSettingsC, _AudioOpenSoundSettingsDart>(
            'audio_open_sound_settings');
    _getAccentColor = _lib
        .lookupFunction<_AudioGetAccentColorC, _AudioGetAccentColorDart>(
            'audio_get_accent_color');

    final hr = _audioInit();
    if (hr != 0) {
      throw StateError('audio_init failed with code $hr');
    }

    _initialized = true;
    final backend = _getVtableSlot();
    final backendName = backend == 0 ? 'PipeWire' : backend == 1 ? 'PulseAudio' : 'unknown';
    debugPrint('NativeAudioBridgeLinux: initialized via $backendName backend');
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'NativeAudioBridgeLinux not initialized. Call initialize() first.',
      );
    }
  }

  @override
  List<AudioDevice> enumerateDevices() {
    _ensureInitialized();
    const maxDevices = 32;
    final pDevices = calloc<AudioDeviceInfoLinux>(maxDevices);
    try {
      final count = _getDevices(pDevices, maxDevices);
      final devices = <AudioDevice>[];
      for (int i = 0; i < count; i++) {
        final d = pDevices[i];
        devices.add(AudioDevice(
          id: _readUtf8Array(d.id, 256),
          name: _readUtf8Array(d.name, 256),
          shortName: _readUtf8Array(d.short_name, 128),
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

  @override
  List<AudioSession> enumerateAudioSessions() {
    _ensureInitialized();
    const maxSessions = 64;
    final pSessions = calloc<AudioSessionInfoLinux>(maxSessions);
    try {
      final count = _getSessions(pSessions, maxSessions);
      final sessions = <AudioSession>[];
      for (int i = 0; i < count; i++) {
        final s = pSessions[i];
        sessions.add(AudioSession(
          processId: s.process_id.toString(),
          processName: _readUtf8Array(s.process_name, 256),
          displayName: _readUtf8Array(s.display_name, 256),
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

  @override
  Map<String, double> getPeakLevels() {
    _ensureInitialized();
    const maxSessions = 64;
    final pPeaks = calloc<PeakLevelInfoLinux>(maxSessions);
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

  @override
  int routeAppToDevice(String processId, String deviceId) {
    _ensureInitialized();
    final pDeviceId = deviceId.toNativeUtf8();
    try {
      final pid = int.tryParse(processId) ?? 0;
      final hr = _routeProcess(pid, pDeviceId);
      final backend = _getVtableSlot();
      final backendName = backend == 0 ? 'PipeWire' : 'PulseAudio';
      debugPrint('routeAppToDevice: pid=$pid via $backendName result=$hr');
      return hr;
    } finally {
      calloc.free(pDeviceId);
    }
  }

  @override
  void setVolume(String processId, double volume) {
    _ensureInitialized();
    final pid = int.tryParse(processId) ?? 0;
    _setVolume(pid, volume.clamp(0.0, 1.0));
  }

  @override
  void setMute(String processId, bool muted) {
    _ensureInitialized();
    final pid = int.tryParse(processId) ?? 0;
    _setMute(pid, muted ? 1 : 0);
  }

  @override
  double getDeviceVolume(String deviceId) {
    _ensureInitialized();
    final pId = deviceId.toNativeUtf8();
    try {
      return _getDeviceVolume(pId);
    } finally {
      calloc.free(pId);
    }
  }

  @override
  void setDeviceVolume(String deviceId, double volume) {
    _ensureInitialized();
    final pId = deviceId.toNativeUtf8();
    try {
      _setDeviceVolume(pId, volume.clamp(0.0, 1.0));
    } finally {
      calloc.free(pId);
    }
  }

  @override
  void setAutostart(bool enabled) {
    _ensureInitialized();
    _setAutostart(enabled ? 1 : 0);
  }

  @override
  bool getAutostart() {
    _ensureInitialized();
    return _getAutostart() != 0;
  }

  @override
  bool registerHotkey(int id, int modifiers, int virtualKey) {
    _ensureInitialized();
    return _registerHotkey(id, modifiers, virtualKey) == 0;
  }

  @override
  void unregisterHotkey(int id) {
    _ensureInitialized();
    _unregisterHotkey(id);
  }

  @override
  int pollHotkey() {
    _ensureInitialized();
    return _pollHotkey();
  }

  @override
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

  @override
  void startMirror(String sourceDeviceId, String targetDeviceId) {
    _ensureInitialized();
    final pSrc = sourceDeviceId.toNativeUtf8();
    final pTgt = targetDeviceId.toNativeUtf8();
    try {
      _startMirror(pSrc, pTgt);
    } finally {
      calloc.free(pSrc);
      calloc.free(pTgt);
    }
  }

  @override
  void stopMirror(String sourceDeviceId, String targetDeviceId) {
    _ensureInitialized();
    final pSrc = sourceDeviceId.toNativeUtf8();
    final pTgt = targetDeviceId.toNativeUtf8();
    try {
      _stopMirror(pSrc, pTgt);
    } finally {
      calloc.free(pSrc);
      calloc.free(pTgt);
    }
  }

  @override
  void stopAllMirrors() {
    if (!_initialized) return;
    _stopAllMirrors();
  }

  @override
  int setDefaultDevice(String deviceId) {
    _ensureInitialized();
    final pId = deviceId.toNativeUtf8();
    try {
      return _setDefaultDevice(pId);
    } finally {
      calloc.free(pId);
    }
  }

  @override
  double getDeviceBalance(String deviceId) {
    _ensureInitialized();
    final pId = deviceId.toNativeUtf8();
    try {
      return _getDeviceBalance(pId);
    } finally {
      calloc.free(pId);
    }
  }

  @override
  void setDeviceBalance(String deviceId, double balance) {
    _ensureInitialized();
    final pId = deviceId.toNativeUtf8();
    try {
      _setDeviceBalance(pId, balance.clamp(-1.0, 1.0));
    } finally {
      calloc.free(pId);
    }
  }

  @override
  void openSoundSettings() {
    _ensureInitialized();
    _openSoundSettings();
  }

  @override
  int getAccentColor() {
    _ensureInitialized();
    return _getAccentColor();
  }

  @override
  void dispose() {
    if (_initialized) {
      _audioCleanup();
      _initialized = false;
    }
  }
}
