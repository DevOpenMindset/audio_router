/// Windows Audio Backend — Native FFI Interface
///
/// This file documents the Win32/COM API calls needed for real audio routing.
/// In production, these would be called via dart:ffi + the win32 package.
///
/// ## Architecture
///
/// ```
/// Flutter UI (Dart)
///     │
///     ├── AudioService (lib/services/audio_service.dart)
///     │   └── Currently: simulation layer
///     │   └── Production: calls NativeAudioBridge
///     │
///     └── NativeAudioBridge (this file)
///         └── dart:ffi → win32 COM APIs
///             ├── IMMDeviceEnumerator    → List output devices
///             ├── IAudioSessionManager2  → List active audio sessions
///             ├── IAudioMeterInformation → Get peak levels
///             └── IPolicyConfig          → Route app audio to device
/// ```
///
/// ## Required COM Interfaces
///
/// ### 1. Device Enumeration (IMMDeviceEnumerator)
/// ```cpp
/// CoCreateInstance(CLSID_MMDeviceEnumerator, ...)
/// enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &collection)
/// collection->GetCount(&count)
/// collection->Item(i, &device)
/// device->OpenPropertyStore(STGM_READ, &props)
/// props->GetValue(PKEY_Device_FriendlyName, &name)
/// ```
///
/// ### 2. Audio Session Enumeration (IAudioSessionManager2)
/// ```cpp
/// device->Activate(IID_IAudioSessionManager2, ...)
/// manager->GetSessionEnumerator(&enumerator)
/// enumerator->GetCount(&count)
/// enumerator->GetSession(i, &control)
/// control->QueryInterface(IID_IAudioSessionControl2, &control2)
/// control2->GetProcessId(&pid)
/// control2->GetState(&state) // Active, Inactive, Expired
/// ```
///
/// ### 3. Peak Meter (IAudioMeterInformation)
/// ```cpp
/// control->QueryInterface(IID_IAudioMeterInformation, &meter)
/// meter->GetPeakValue(&peak) // 0.0 - 1.0
/// ```
///
/// ### 4. Per-App Audio Routing (IPolicyConfig)
/// This is an undocumented COM interface but widely used by tools
/// like SoundSwitch, EarTrumpet, and Audio Router.
/// ```cpp
/// CoCreateInstance(CLSID_PolicyConfig, ...)
/// // GUID: {F8679F50-850A-41CF-9C72-430F290290C8}
/// policyConfig->SetDefaultEndpoint(deviceId, eConsole)
/// ```
///
/// ## Dart FFI Implementation Notes
///
/// Use the `win32` package which provides Dart bindings for most COM interfaces.
/// For IPolicyConfig (undocumented), you'll need to define the vtable manually:
///
/// ```dart
/// import 'dart:ffi';
/// import 'package:win32/win32.dart';
///
/// // Define IPolicyConfig GUID
/// final CLSID_PolicyConfig =
///     GUIDFromString('{870AF99C-171D-4F9E-AF0D-E63DF40C2BC9}');
/// final IID_IPolicyConfig =
///     GUIDFromString('{F8679F50-850A-41CF-9C72-430F290290C8}');
///
/// // Initialize COM
/// CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
///
/// // Create device enumerator
/// final enumerator = MMDeviceEnumerator.createInstance();
/// final collection = enumerator.enumAudioEndpoints(
///     EDataFlow.eRender, DEVICE_STATE_ACTIVE);
///
/// // Iterate devices
/// for (var i = 0; i < collection.count; i++) {
///   final device = collection.item(i);
///   final props = device.openPropertyStore(STGM_READ);
///   final name = props.getValue(PKEY_Device_FriendlyName);
///   // ... build AudioDevice model
/// }
/// ```
///
/// ## Build Requirements
///
/// - Windows 10/11 SDK
/// - Flutter Windows desktop support enabled
/// - win32 package >= 5.5.0
/// - Run: `flutter config --enable-windows-desktop`
/// - Build: `flutter build windows --release`
///
/// ## System Tray Integration
///
/// Use `system_tray` package:
/// ```dart
/// final systemTray = SystemTray();
/// await systemTray.initSystemTray(
///   title: 'SoundShift',
///   iconPath: 'assets/icon.ico',
/// );
/// systemTray.registerSystemTrayEventHandler((eventName) {
///   if (eventName == kSystemTrayEventClick) {
///     windowManager.show(); // Show popup at tray position
///   }
/// });
/// ```

library native_audio;

// This file serves as architecture documentation.
// The actual FFI bindings would be implemented here in production.
// See AudioService for the simulation layer used during development.
