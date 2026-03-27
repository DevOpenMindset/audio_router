# AudioRouter

Route audio per-app to different output devices. Simple. Clean. No bullshit.

Spotify → Enceintes. Discord → Casque. YouTube → Écouteurs. One click.

## Screenshot

The app runs as a tray popup — click the icon, pick your routing, done.

## Architecture

```
lib/
├── main.dart                          # Entry point, window config
├── core/
│   └── native_audio_bridge.dart       # Win32 FFI docs & interface
├── models/
│   └── audio_models.dart              # AudioDevice, AudioSession, RoutingProfile
├── services/
│   ├── audio_service.dart             # WASAPI interface (sim layer for dev)
│   └── profile_service.dart           # Saved routing presets
├── screens/
│   └── home_screen.dart               # Main UI assembly
├── theme/
│   └── app_theme.dart                 # Colors, typography
└── widgets/
    ├── app_icon.dart                  # Custom painted app icons
    ├── device_footer.dart             # Detected devices bar
    ├── device_selector.dart           # Custom dropdown (no Material)
    ├── peak_level_bar.dart            # Audio level indicator
    ├── profile_bar.dart               # Profile selector chips
    ├── session_card.dart              # Per-app routing card
    └── title_bar.dart                 # Frameless window title bar
```

## Design Principles

- **Zero Material widgets** in the UI layer — everything is custom painted
- Dark theme only, tray-app aesthetic
- Feels native to Windows, not like a Flutter app
- 380x540px popup, frameless, always-on-top

## Setup

### Prerequisites

- Flutter 3.16+ with Windows desktop enabled
- Windows 10/11
- Internet connection on first run (Google Fonts downloads Inter automatically)

### Run

```bash
flutter config --enable-windows-desktop
flutter pub get
flutter run -d windows
```

### Build

```bash
flutter build windows --release
```

Output: `build/windows/x64/runner/Release/audio_router.exe`

## Backend Implementation

The `AudioService` currently uses a simulation layer for UI development.
To connect to real Windows audio:

1. Implement the FFI bindings documented in `lib/core/native_audio_bridge.dart`
2. Replace simulation methods in `AudioService` with native calls
3. Key Win32 APIs needed:
   - `IMMDeviceEnumerator` — enumerate output devices
   - `IAudioSessionManager2` — list apps producing audio
   - `IAudioMeterInformation` — peak level meters
   - `IPolicyConfig` — per-app audio routing (undocumented but stable)

## Roadmap

- [x] UI with custom widgets
- [x] Simulated audio backend
- [x] Profile system (Gaming/Work/Music presets)
- [ ] Native Win32 audio backend via FFI
- [ ] System tray integration
- [ ] Auto-start with Windows
- [ ] Per-app volume control
- [ ] Hotkey support for profile switching
- [ ] Auto-detect new audio sessions
- [ ] Remember routing across reboots

## Tech Stack

- **UI**: Flutter Desktop (Windows)
- **Backend**: Dart + dart:ffi + win32 package
- **Audio API**: Windows WASAPI / COM
- **State**: Provider + ChangeNotifier

## License

MIT
