#pragma once

// audio_backend.h — C API for macOS audio backend dylib
// Called by Dart via dart:ffi
//
// Strings use uint16_t arrays (UTF-16, 2 bytes per char) to match
// Dart's Array<Uint16> / Pointer<Utf16> — identical to Windows.

#define AUDIO_API __attribute__((visibility("default")))

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ─── Structures ──────────────────────────────────────────────
// Layout must match audio_backend.h on Windows and the Dart FFI structs.

typedef struct {
    uint16_t id[256];         // AudioObjectID encoded as decimal UTF-16 string
    uint16_t name[256];       // Friendly device name (CFString → UTF-16)
    uint16_t short_name[128]; // Same as name on macOS (no parentheses convention)
    int32_t  is_default;      // 1 = system default output device
    int32_t  is_active;       // Always 1 for enumerated devices
    float    volume;          // Master output scalar 0.0–1.0
} AudioDeviceInfo;

typedef struct {
    uint32_t process_id;          // PID
    uint16_t process_name[256];   // Executable/bundle name (UTF-16)
    uint16_t display_name[256];   // Pretty-printed name (UTF-16)
    int32_t  is_active;           // 1 = kAudioProcessPropertyIsRunningOutput
    float    peak_level;          // 0.0–1.0 (device-level peak for active sessions)
    float    volume;              // 0.0–1.0 (state managed in Dart; no macOS per-app API)
    int32_t  is_muted;            // 0 always (state managed in Dart)
} AudioSessionInfo;

// ─── Lifecycle ───────────────────────────────────────────────

/// Initialize Core Audio state. Call once at startup.
AUDIO_API int32_t audio_init(void);

/// Clean up state. Call once at shutdown.
AUDIO_API void audio_cleanup(void);

// ─── Device Enumeration ──────────────────────────────────────

AUDIO_API int32_t audio_get_device_count(void);
AUDIO_API int32_t audio_get_devices(AudioDeviceInfo* devices, int32_t max_count);

// ─── Session Enumeration (macOS 12+) ─────────────────────────

AUDIO_API int32_t audio_get_session_count(void);
AUDIO_API int32_t audio_get_sessions(AudioSessionInfo* sessions, int32_t max_count);

// ─── Per-App Routing ─────────────────────────────────────────

/// Route a process to a specific device.
/// device_id: UTF-16 string of decimal AudioObjectID, or empty to reset.
/// Returns 0 on success (macOS 14+), negative on error or older macOS.
AUDIO_API int32_t audio_route_process(uint32_t process_id, const uint16_t* device_id);

/// Not applicable on macOS — always returns -1.
AUDIO_API int32_t audio_get_vtable_slot(void);

// ─── Per-App Volume ─────────────────────────────────────────
// macOS has no public per-process volume API.
// Volume state is tracked in Dart; these are no-ops that return 0.

AUDIO_API int32_t audio_set_volume(uint32_t process_id, float volume);
AUDIO_API int32_t audio_set_mute(uint32_t process_id, int32_t muted);

// ─── Device Master Volume ────────────────────────────────────

AUDIO_API float   audio_get_device_volume(const uint16_t* device_id);
AUDIO_API int32_t audio_set_device_volume(const uint16_t* device_id, float volume);

// ─── Device Balance / Default Device ─────────────────────────
// Declared here so the definitions in audio_backend.mm get C linkage;
// without these declarations the symbols are C++-mangled and Dart FFI
// lookups fail, dropping the app into simulation mode.

AUDIO_API float   audio_get_device_balance(const uint16_t* device_id);
AUDIO_API int32_t audio_set_device_balance(const uint16_t* device_id, float balance);
AUDIO_API int32_t audio_set_default_device(const uint16_t* device_id);

// ─── OS Integration ──────────────────────────────────────────

/// Open the macOS System Settings sound pane. Returns 0 on success.
AUDIO_API int32_t audio_open_sound_settings(void);

/// System accent colour as 0xAARRGGBB, or 0 if unavailable.
AUDIO_API uint32_t audio_get_accent_color(void);

// ─── App Icon ───────────────────────────────────────────────

/// Extract the process's icon as 32×32 RGBA pixels via NSWorkspace.
AUDIO_API int32_t audio_get_app_icon(uint32_t pid, uint8_t* rgba_buf, int32_t buf_size,
                                     int32_t* out_width, int32_t* out_height);

// ─── Auto-Start ─────────────────────────────────────────────
// Implemented via ~/Library/LaunchAgents/com.audiotouter.AudioRouter.plist

AUDIO_API int32_t audio_set_autostart(int32_t enabled);
AUDIO_API int32_t audio_get_autostart(void);

// ─── Global Hotkeys (Carbon) ─────────────────────────────────
// Modifier flags match Windows: MOD_ALT=1, MOD_CONTROL=2, MOD_SHIFT=4, MOD_WIN=8
// Virtual key codes match Windows: VK_1=0x31 .. VK_9=0x39

AUDIO_API int32_t audio_register_hotkey(int32_t id, uint32_t modifiers, uint32_t vk);
AUDIO_API int32_t audio_unregister_hotkey(int32_t id);
AUDIO_API int32_t audio_poll_hotkey(void);

// ─── Peak Levels (fast poll, separate from session enumeration) ──────────────

typedef struct {
    uint32_t process_id;
    float    peak_level;
} PeakLevelInfo;

/// Read peak levels for all known sessions without re-enumerating.
/// Returns the number of entries written to `peaks`.
AUDIO_API int32_t audio_poll_peaks(PeakLevelInfo* peaks, int32_t max_count);

// ─── Loopback Mirror (Windows-only, stubs on macOS) ─────────────────────────

/// Start mirroring audio from source_device_id to target_device_id.
/// On macOS, routing is per-process via CATapDescription — returns 0 (no-op).
AUDIO_API int32_t audio_start_mirror(const uint16_t* source_device_id,
                                     const uint16_t* target_device_id);

/// Stop mirroring from source_device_id to target_device_id. No-op on macOS.
AUDIO_API int32_t audio_stop_mirror(const uint16_t* source_device_id,
                                    const uint16_t* target_device_id);

/// Stop all active mirrors. No-op on macOS.
AUDIO_API void audio_stop_all_mirrors(void);

#ifdef __cplusplus
}
#endif
