#pragma once

// audio_backend_linux.h — C API exported from libaudio_backend.so
// Called by Dart via dart:ffi
// Mirrors the Windows audio_backend.h API but uses char[] (UTF-8) instead of wchar_t[] (UTF-16)

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

#ifdef AUDIO_BACKEND_EXPORTS
#define AUDIO_API __attribute__((visibility("default")))
#else
#define AUDIO_API
#endif

// ─── Structures ──────────────────────────────────────────────

typedef struct {
    char id[256];           // Sink name (PulseAudio) or node serial (PipeWire)
    char name[256];         // Full human-readable name
    char short_name[128];   // Short display name
    int32_t is_default;
    int32_t is_active;
    float volume;           // Master volume 0.0 - 1.0
} AudioDeviceInfo;

typedef struct {
    uint32_t process_id;
    char process_name[256];
    char display_name[256];
    int32_t is_active;       // 1 = currently producing audio
    float peak_level;        // 0.0 - 1.0
    float volume;            // 0.0 - 1.0
    int32_t is_muted;        // 1 = muted
} AudioSessionInfo;

typedef struct {
    uint32_t process_id;
    float peak_level;        // 0.0 - 1.0
} PeakLevelInfo;

// ─── Lifecycle ───────────────────────────────────────────────

/// Initialize audio backend (PipeWire or PulseAudio).
/// Returns 0 on success, negative on failure.
AUDIO_API int32_t audio_init(void);

/// Clean up resources.
AUDIO_API void audio_cleanup(void);

// ─── Device Enumeration ──────────────────────────────────────

/// Get number of active output (sink) devices.
AUDIO_API int32_t audio_get_device_count(void);

/// Fill array with device info. Returns actual count written.
AUDIO_API int32_t audio_get_devices(AudioDeviceInfo* devices, int32_t max_count);

// ─── Session Enumeration ─────────────────────────────────────

/// Get number of active audio sessions (sink-inputs).
AUDIO_API int32_t audio_get_session_count(void);

/// Fill array with session info. Returns actual count written.
AUDIO_API int32_t audio_get_sessions(AudioSessionInfo* sessions, int32_t max_count);

/// Fast peak-level poll. Returns number of entries written.
AUDIO_API int32_t audio_poll_peaks(PeakLevelInfo* peaks, int32_t max_count);

// ─── Per-App Routing ─────────────────────────────────────────

/// Route a process's audio to a specific sink.
/// device_id is the sink name (PA) or node serial string (PW).
/// Returns 0 on success.
AUDIO_API int32_t audio_route_process(uint32_t process_id, const char* device_id);

/// Returns the backend type: 0 = PipeWire, 1 = PulseAudio, -1 = none.
AUDIO_API int32_t audio_get_vtable_slot(void);

// ─── Per-App Volume ──────────────────────────────────────────

/// Set volume for a specific process (0.0 - 1.0). Returns 0 on success.
AUDIO_API int32_t audio_set_volume(uint32_t process_id, float volume);

/// Set mute state for a specific process. Returns 0 on success.
AUDIO_API int32_t audio_set_mute(uint32_t process_id, int32_t muted);

// ─── Device Master Volume ────────────────────────────────────

/// Get master volume for a sink (0.0 - 1.0). Returns -1.0 on error.
AUDIO_API float audio_get_device_volume(const char* device_id);

/// Set master volume for a sink (0.0 - 1.0). Returns 0 on success.
AUDIO_API int32_t audio_set_device_volume(const char* device_id, float volume);

// ─── App Icon ────────────────────────────────────────────────

/// Extract the process's icon as 32x32 RGBA pixels.
/// Returns 0 on success, negative on error.
AUDIO_API int32_t audio_get_app_icon(uint32_t pid, uint8_t* rgba_buf, int32_t buf_size,
                                     int32_t* out_width, int32_t* out_height);

// ─── Loopback Mirror ─────────────────────────────────────────

/// Start mirroring audio from source sink to target sink.
AUDIO_API int32_t audio_start_mirror(const char* source_device_id,
                                      const char* target_device_id);

/// Stop a specific mirror.
AUDIO_API int32_t audio_stop_mirror(const char* source_device_id,
                                     const char* target_device_id);

/// Stop all active mirrors.
AUDIO_API void audio_stop_all_mirrors(void);

// ─── Auto-Start ──────────────────────────────────────────────

/// Enable or disable auto-start via XDG autostart.
AUDIO_API int32_t audio_set_autostart(int32_t enabled);

/// Returns 1 if auto-start is enabled, 0 otherwise.
AUDIO_API int32_t audio_get_autostart(void);

// ─── Default Device ─────────────────────────────────────────

/// Set the default audio output sink.
/// Returns 0 on success, negative on error.
AUDIO_API int32_t audio_set_default_device(const char* device_id);

// ─── Device Balance (Stereo L/R) ────────────────────────────

/// Get stereo balance: -1.0 (left) to +1.0 (right), 0.0 = center.
AUDIO_API float audio_get_device_balance(const char* device_id);

/// Set stereo balance: -1.0 (left) to +1.0 (right).
AUDIO_API int32_t audio_set_device_balance(const char* device_id, float balance);

// ─── OS Sound Settings ──────────────────────────────────────

/// Open the native OS sound settings.
AUDIO_API int32_t audio_open_sound_settings(void);

// ─── OS Accent Color ────────────────────────────────────────

/// Get the OS accent color as ARGB. Returns 0 on failure.
AUDIO_API uint32_t audio_get_accent_color(void);

// ─── Global Hotkeys ──────────────────────────────────────────

/// Register a global hotkey.
AUDIO_API int32_t audio_register_hotkey(int32_t id, uint32_t modifiers, uint32_t vk);

/// Unregister a global hotkey.
AUDIO_API int32_t audio_unregister_hotkey(int32_t id);

/// Poll for hotkey events. Returns hotkey id or 0 if none.
AUDIO_API int32_t audio_poll_hotkey(void);

#ifdef __cplusplus
}
#endif
