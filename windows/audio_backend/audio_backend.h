#pragma once

// audio_backend.h — C API exported from audio_backend.dll
// Called by Dart via dart:ffi

#ifdef AUDIO_BACKEND_EXPORTS
#define AUDIO_API __declspec(dllexport)
#else
#define AUDIO_API __declspec(dllimport)
#endif

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ─── Structures ──────────────────────────────────────────────

typedef struct {
    wchar_t id[256];
    wchar_t name[256];
    wchar_t short_name[128];
    int32_t is_default;
    int32_t is_active;
    float volume;   // master volume 0.0 - 1.0 (IAudioEndpointVolume)
} AudioDeviceInfo;

typedef struct {
    uint32_t process_id;
    wchar_t process_name[256];
    wchar_t display_name[256];
    int32_t is_active;       // 1 = AudioSessionStateActive
    float peak_level;        // 0.0 - 1.0
    float volume;            // 0.0 - 1.0 (ISimpleAudioVolume)
    int32_t is_muted;        // 1 = muted
} AudioSessionInfo;

// Lightweight peak level entry — returned by audio_poll_peaks.
typedef struct {
    uint32_t process_id;
    float peak_level;        // 0.0 - 1.0, device-level peak for this session
} PeakLevelInfo;

// ─── Lifecycle ───────────────────────────────────────────────

/// Initialize COM and internal state. Call once at startup.
/// Returns 0 on success, HRESULT on failure.
AUDIO_API int32_t audio_init(void);

/// Clean up COM resources. Call once at shutdown.
AUDIO_API void audio_cleanup(void);

// ─── Device Enumeration ──────────────────────────────────────

/// Get the number of active render (output) devices.
AUDIO_API int32_t audio_get_device_count(void);

/// Fill the provided array with device info. Returns actual count written.
/// `max_count` is the size of the `devices` array.
AUDIO_API int32_t audio_get_devices(AudioDeviceInfo* devices, int32_t max_count);

// ─── Session Enumeration ─────────────────────────────────────

/// Get the number of active audio sessions.
AUDIO_API int32_t audio_get_session_count(void);

/// Fill the provided array with session info. peak_level is always 0 here —
/// use audio_poll_peaks for live peak data.
/// Returns actual count written.
AUDIO_API int32_t audio_get_sessions(AudioSessionInfo* sessions, int32_t max_count);

/// Fast peak-level poll — reads cached device meters without re-enumerating sessions.
/// Call every 33ms from the UI thread. Returns number of entries written.
AUDIO_API int32_t audio_poll_peaks(PeakLevelInfo* peaks, int32_t max_count);

// ─── Per-App Routing ─────────────────────────────────────────

/// Route a process's audio to a specific device.
/// `device_id` is the MMDevice endpoint ID string.
/// Returns 0 = COM success, 1 = registry fallback used, negative = error.
AUDIO_API int32_t audio_route_process(uint32_t process_id, const wchar_t* device_id);

/// Returns the vtable slot used for SetPersistedDefaultAudioEndpoint.
/// -1 = not yet detected / detection failed (registry fallback is used).
///  7 = Windows 10 1803-22H2 layout.
///  9 = Windows 11 23H2+ layout.
AUDIO_API int32_t audio_get_vtable_slot(void);

// ─── Per-App Volume ─────────────────────────────────────────

/// Set volume for a specific process (0.0 - 1.0). Returns 0 on success.
AUDIO_API int32_t audio_set_volume(uint32_t process_id, float volume);

/// Set mute state for a specific process. Returns 0 on success.
AUDIO_API int32_t audio_set_mute(uint32_t process_id, int32_t muted);

// ─── Device Master Volume ────────────────────────────────────

/// Get master volume for a device (0.0 - 1.0). Returns -1.0 on error.
AUDIO_API float audio_get_device_volume(const wchar_t* device_id);

/// Set master volume for a device (0.0 - 1.0). Returns 0 on success.
AUDIO_API int32_t audio_set_device_volume(const wchar_t* device_id, float volume);

// ─── App Icon ───────────────────────────────────────────────

/// Extract the process's icon as 32×32 RGBA pixels.
/// Pass rgba_buf=NULL / buf_size=0 to query required size (returns W*H*4).
/// Returns 0 on success, negative on error, positive = required buffer size.
/// out_width and out_height are always set to 32 on success.
AUDIO_API int32_t audio_get_app_icon(uint32_t pid, uint8_t* rgba_buf, int32_t buf_size,
                                     int32_t* out_width, int32_t* out_height);

// ─── Loopback Mirror ─────────────────────────────────────────

/// Start mirroring audio from source device to target device via WASAPI loopback.
/// Creates a background thread that captures all audio from sourceDeviceId and
/// re-renders it on targetDeviceId. Idempotent (no-op if already mirroring).
/// Returns 0 on success.
AUDIO_API int32_t audio_start_mirror(const wchar_t* source_device_id,
                                      const wchar_t* target_device_id);

/// Stop a specific mirror. Returns 0 on success.
AUDIO_API int32_t audio_stop_mirror(const wchar_t* source_device_id,
                                     const wchar_t* target_device_id);

/// Stop all active mirrors. Called during cleanup.
AUDIO_API void audio_stop_all_mirrors(void);

// ─── Auto-Start ─────────────────────────────────────────────

/// Enable or disable auto-start at Windows login.
AUDIO_API int32_t audio_set_autostart(int32_t enabled);

/// Returns 1 if auto-start is enabled, 0 otherwise.
AUDIO_API int32_t audio_get_autostart(void);

// ─── Default Device ─────────────────────────────────────────

/// Set the default audio playback device.
/// `device_id` is the MMDevice endpoint ID string.
/// Returns 0 on success, negative on error.
AUDIO_API int32_t audio_set_default_device(const wchar_t* device_id);

// ─── Device Balance (Stereo L/R) ────────────────────────────

/// Get stereo balance for a device. Returns a value from -1.0 (full left)
/// through 0.0 (center) to 1.0 (full right). Returns 0.0 on error.
AUDIO_API float audio_get_device_balance(const wchar_t* device_id);

/// Set stereo balance for a device. balance: -1.0 (left) to 1.0 (right).
/// Returns 0 on success.
AUDIO_API int32_t audio_set_device_balance(const wchar_t* device_id, float balance);

// ─── OS Sound Settings ──────────────────────────────────────

/// Open the native OS sound settings dialog.
/// Returns 0 on success.
AUDIO_API int32_t audio_open_sound_settings(void);

// ─── OS Accent Color ────────────────────────────────────────

/// Get the OS accent color as ARGB. Returns 0 on failure.
AUDIO_API uint32_t audio_get_accent_color(void);

// ─── Global Hotkeys ─────────────────────────────────────────

/// Register a global hotkey. id = unique ID (1-based), modifiers = MOD_* flags, vk = virtual key.
/// Returns 0 on success.
AUDIO_API int32_t audio_register_hotkey(int32_t id, uint32_t modifiers, uint32_t vk);

/// Unregister a global hotkey by id.
AUDIO_API int32_t audio_unregister_hotkey(int32_t id);

/// Poll for hotkey events. Returns the hotkey id that was pressed, or 0 if none.
AUDIO_API int32_t audio_poll_hotkey(void);

#ifdef __cplusplus
}
#endif
