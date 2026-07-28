# Changelog

## [Unreleased]
### Fixed
- macOS: native backend loads again — three exported functions had C++-mangled names and two were missing, which silently dropped the app into simulation mode with fake devices and apps
- macOS: session enumeration used wrong CoreAudio four-char codes ('plst'/'poro' instead of the SDK's 'prs#'/'piro'), so no real apps ever appeared
- macOS: per-app routing rebuilt on the documented process-tap architecture (tap wrapped in a private aggregate device, separate capture and playback engines); the previous code pointed an AudioUnit at the tap object, which CoreAudio rejects
- macOS: tapped processes are now silenced via the real CATapDescription muteBehavior API (the previously used `mutedProcesses` property does not exist)
- macOS: per-app volume works for unrouted apps (lazy tap to the current device), carries over when switching devices, and no longer leaks a burst of audio to the default device mid-switch
- macOS: internal tap aggregates no longer appear in the device picker (routing into one created a feedback loop)
- macOS: app icons no longer show the wrong app after the session list reorders; helper-process sessions fall back to sibling pids for their icon
- macOS: closing the window hides to the menu bar instead of quitting (applicationShouldTerminateAfterLastWindowClosed); Quit lives in the tray menu
- macOS: removed duplicate fake traffic lights; native window controls work
- macOS: toolbar tab bar no longer clipped by the ToolBar's 150px default title width
- macOS: Settings tab rendered a grey void — fluent_ui Tooltip crashed without a FluentApp ancestor; the inline Settings "Done" button popped the root route into a black window
- Previewing the Windows/Linux interface style on macOS (and vice versa on Linux) grey-boxed every widget — theme/localization ancestors are now injected per style
- Release DMG reported as damaged on Apple Silicon: the dylib was embedded after signing; CI now re-signs the app after embedding
- UI language defaulted to French; it now follows the OS language (English fallback)

### Added
- macOS: menu-bar panel mode — no Dock icon by default, 🔊 status item, window opens as a popover aligned with the tray icon and hides when it loses focus
- Collapsible per-device system volume section on the Apps tab

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
- Separate public releases repository (`audio_router_releases`) — source code now open source (MIT)
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
