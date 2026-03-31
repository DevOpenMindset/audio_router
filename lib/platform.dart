import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Override for UI style.
/// null    = follow the real OS
/// 'win'   = force Windows 11 UI (Fluent, Segoe UI, Win11 colours)
/// 'mac'   = force macOS UI (macos_ui, SF Pro, macOS colours)
/// 'linux' = force GNOME/Adwaita UI (Material+Adwaita, Cantarell)
String? uiStyleOverride;

bool get isWindows => !kIsWeb &&
    (uiStyleOverride == 'win' ||
        (uiStyleOverride == null && Platform.isWindows));

bool get isMacOS => !kIsWeb &&
    (uiStyleOverride == 'mac' ||
        (uiStyleOverride == null && Platform.isMacOS));

bool get isLinux => !kIsWeb &&
    (uiStyleOverride == 'linux' ||
        (uiStyleOverride == null && Platform.isLinux));

// ── Platform-specific hotkey labels ──────────────────────────
String get hotkeyModifier       => isMacOS ? 'Cmd+Option' : 'Ctrl+Alt';
String get hotkeyModifierSymbol => isMacOS ? '⌘⌥'        : 'Ctrl+Alt';

// ── Routing capability ───────────────────────────────────────
/// Per-app routing is natively supported on:
///   • Windows  (WASAPI / IPolicyConfig — always)
///   • Linux    (PipeWire / PulseAudio — always)
///   • macOS 14.2+ (CATapDescription API)
bool get routingNativelySupported {
  if (Platform.isWindows) return true;
  if (Platform.isLinux) return true;
  if (!Platform.isMacOS) return false;
  try {
    final match = RegExp(r'Version (\d+)\.(\d+)')
        .firstMatch(Platform.operatingSystemVersion);
    if (match == null) return false;
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    return major > 14 || (major == 14 && minor >= 2);
  } catch (_) {
    return false;
  }
}

/// Human-readable macOS version string, e.g. "14.1.2". Null on non-macOS.
String? get macOsVersionString {
  if (!Platform.isMacOS) return null;
  try {
    final match =
        RegExp(r'Version ([\d.]+)').firstMatch(Platform.operatingSystemVersion);
    return match?.group(1);
  } catch (_) {
    return null;
  }
}
