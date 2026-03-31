// audio_bridge.dart — Abstract interface for the native audio backend.
//
// Platform-specific implementations:
//   Windows/macOS: NativeAudioBridge (UTF-16 wchar_t FFI)
//   Linux:         NativeAudioBridgeLinux (UTF-8 char FFI)

import 'dart:io';
import 'dart:typed_data';
import '../models/audio_models.dart';
import 'native_audio_bridge_impl.dart';
import 'native_audio_bridge_linux.dart';

/// Abstract audio bridge interface that all platform backends must implement.
abstract class AudioBridge {
  Future<void> initialize();
  void dispose();

  List<AudioDevice> enumerateDevices();
  List<AudioSession> enumerateAudioSessions();
  Map<String, double> getPeakLevels();

  int routeAppToDevice(String processId, String deviceId);
  void setVolume(String processId, double volume);
  void setMute(String processId, bool muted);

  double getDeviceVolume(String deviceId);
  void setDeviceVolume(String deviceId, double volume);

  void setAutostart(bool enabled);
  bool getAutostart();

  bool registerHotkey(int id, int modifiers, int virtualKey);
  void unregisterHotkey(int id);
  int pollHotkey();

  Uint8List? getAppIcon(String processId);

  void startMirror(String sourceDeviceId, String targetDeviceId);
  void stopMirror(String sourceDeviceId, String targetDeviceId);
  void stopAllMirrors();

  int setDefaultDevice(String deviceId);
  double getDeviceBalance(String deviceId);
  void setDeviceBalance(String deviceId, double balance);
  void openSoundSettings();
  int getAccentColor();

  /// Factory: returns the correct bridge for the current platform.
  static AudioBridge create() {
    if (Platform.isLinux) {
      return NativeAudioBridgeLinux();
    }
    // Windows and macOS use the original bridge (UTF-16 / wchar_t)
    return NativeAudioBridge();
  }
}
