# Changelog

## [1.2.19] - 2026-03-28
### Fixed
- Per-app sessions now visible even when the app is open but temporarily silent (paused Spotify, idle Discord, etc.)

## [1.2.17] - 2026-03-28
### Fixed
- App version now correctly reflects the release tag — update dialog no longer appears after installing the latest version
- App relaunches reliably after silent auto-update on Windows
- Search bar removed from session list

## [1.2.14] - unreleased

## [1.2.13] - 2026-03-28
### Added
- Multi-output mirror: route one source to multiple audio devices simultaneously
- Safety guards against echo/feedback loops (source = target, A→B+B→A circular mirrors)
- macOS CoreAudio backend (CATapDescription, macOS 14.2+)
- Dock / menu-bar visibility toggle in settings
- Buy Me a Coffee link replaces PayPal in settings

### Fixed
- Mirror devices disappearing after the 2-second session refresh
- `soundshift` process no longer shows up as an app card when mirrors are active
- Apps producing no audio are filtered from the session list
- Auto-update now relaunches the app automatically after silent install

## [1.2.12] - 2026-03-28
### Added
- Separate public releases repository (`audio_router_releases`) — source stays private
- macOS DMG built and published via Codemagic CI

### Fixed
- `libaudio_backend.dylib` now compiled and embedded in app bundle by CI
- `MAC_GH_TOKEN` scope fixed so Codemagic can upload to GitHub releases

## [1.2.9] - 2026-03-27
### Added
- WASAPI loopback mirror engine (Windows) for multi-output routing
- `soundshift` added to system blocklist in C++ and Dart session filters

## [1.2.8] - 2026-03-26
### Added
- Initial public release
- Per-app audio output routing (Windows WASAPI, macOS CoreAudio)
- Per-app volume control with peak-level meter
- System tray with quick-access menu
- Auto-start with Windows / macOS login
- Auto-update service (checks GitHub releases, downloads and installs silently)
