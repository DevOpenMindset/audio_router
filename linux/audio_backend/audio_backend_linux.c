// audio_backend_linux.c — Main dispatcher for AudioRouter Linux backend
//
// Detects PipeWire vs PulseAudio at runtime and delegates all calls
// to the appropriate backend. Also handles XDG autostart, app icons,
// and global hotkeys.

#define AUDIO_BACKEND_EXPORTS
#include "audio_backend_linux.h"

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>
#include <dirent.h>
#include <sys/stat.h>
#include <pthread.h>

// ─── Backend selection ───────────────────────────────────────

typedef enum {
    BACKEND_NONE = -1,
    BACKEND_PIPEWIRE = 0,
    BACKEND_PULSEAUDIO = 1,
} BackendType;

static BackendType g_backend = BACKEND_NONE;

// Forward declarations — resolved at link time based on available libs
#ifdef HAVE_PIPEWIRE
#include "pipewire_backend.h"
#endif

#ifdef HAVE_PULSE
#include "pulse_backend.h"
#endif

// ─── Lifecycle ───────────────────────────────────────────────

AUDIO_API int32_t audio_init(void) {
#ifdef HAVE_PIPEWIRE
    // Try PipeWire first (it's the modern standard)
    if (pw_backend_init() == 0) {
        g_backend = BACKEND_PIPEWIRE;
        fprintf(stderr, "AudioRouter: using PipeWire backend\n");
        return 0;
    }
    fprintf(stderr, "AudioRouter: PipeWire init failed, trying PulseAudio\n");
#endif

#ifdef HAVE_PULSE
    if (pulse_init() == 0) {
        g_backend = BACKEND_PULSEAUDIO;
        fprintf(stderr, "AudioRouter: using PulseAudio backend\n");
        return 0;
    }
    fprintf(stderr, "AudioRouter: PulseAudio init failed\n");
#endif

    fprintf(stderr, "AudioRouter: no audio backend available!\n");
    g_backend = BACKEND_NONE;
    return -1;
}

AUDIO_API void audio_cleanup(void) {
    switch (g_backend) {
#ifdef HAVE_PIPEWIRE
        case BACKEND_PIPEWIRE: pw_backend_cleanup(); break;
#endif
#ifdef HAVE_PULSE
        case BACKEND_PULSEAUDIO: pulse_cleanup(); break;
#endif
        default: break;
    }
    g_backend = BACKEND_NONE;
}

// ─── Device Enumeration ──────────────────────────────────────

AUDIO_API int32_t audio_get_device_count(void) {
    switch (g_backend) {
#ifdef HAVE_PIPEWIRE
        case BACKEND_PIPEWIRE: return pw_backend_get_device_count();
#endif
#ifdef HAVE_PULSE
        case BACKEND_PULSEAUDIO: return pulse_get_device_count();
#endif
        default: return 0;
    }
}

AUDIO_API int32_t audio_get_devices(AudioDeviceInfo* devices, int32_t max_count) {
    switch (g_backend) {
#ifdef HAVE_PIPEWIRE
        case BACKEND_PIPEWIRE: return pw_backend_get_devices(devices, max_count);
#endif
#ifdef HAVE_PULSE
        case BACKEND_PULSEAUDIO: return pulse_get_devices(devices, max_count);
#endif
        default: return 0;
    }
}

// ─── Session Enumeration ─────────────────────────────────────

AUDIO_API int32_t audio_get_session_count(void) {
    switch (g_backend) {
#ifdef HAVE_PIPEWIRE
        case BACKEND_PIPEWIRE: return pw_backend_get_session_count();
#endif
#ifdef HAVE_PULSE
        case BACKEND_PULSEAUDIO: return pulse_get_session_count();
#endif
        default: return 0;
    }
}

AUDIO_API int32_t audio_get_sessions(AudioSessionInfo* sessions, int32_t max_count) {
    switch (g_backend) {
#ifdef HAVE_PIPEWIRE
        case BACKEND_PIPEWIRE: return pw_backend_get_sessions(sessions, max_count);
#endif
#ifdef HAVE_PULSE
        case BACKEND_PULSEAUDIO: return pulse_get_sessions(sessions, max_count);
#endif
        default: return 0;
    }
}

AUDIO_API int32_t audio_poll_peaks(PeakLevelInfo* peaks, int32_t max_count) {
    switch (g_backend) {
#ifdef HAVE_PIPEWIRE
        case BACKEND_PIPEWIRE: return pw_backend_poll_peaks(peaks, max_count);
#endif
#ifdef HAVE_PULSE
        case BACKEND_PULSEAUDIO: return pulse_poll_peaks(peaks, max_count);
#endif
        default: return 0;
    }
}

// ─── Per-App Routing ─────────────────────────────────────────

AUDIO_API int32_t audio_route_process(uint32_t process_id, const char* device_id) {
    switch (g_backend) {
#ifdef HAVE_PIPEWIRE
        case BACKEND_PIPEWIRE: return pw_backend_route_process(process_id, device_id);
#endif
#ifdef HAVE_PULSE
        case BACKEND_PULSEAUDIO: return pulse_route_process(process_id, device_id);
#endif
        default: return -1;
    }
}

AUDIO_API int32_t audio_get_vtable_slot(void) {
    return (int32_t)g_backend;
}

// ─── Per-App Volume ──────────────────────────────────────────

AUDIO_API int32_t audio_set_volume(uint32_t process_id, float volume) {
    switch (g_backend) {
#ifdef HAVE_PIPEWIRE
        case BACKEND_PIPEWIRE: return pw_backend_set_volume(process_id, volume);
#endif
#ifdef HAVE_PULSE
        case BACKEND_PULSEAUDIO: return pulse_set_volume(process_id, volume);
#endif
        default: return -1;
    }
}

AUDIO_API int32_t audio_set_mute(uint32_t process_id, int32_t muted) {
    switch (g_backend) {
#ifdef HAVE_PIPEWIRE
        case BACKEND_PIPEWIRE: return pw_backend_set_mute(process_id, muted);
#endif
#ifdef HAVE_PULSE
        case BACKEND_PULSEAUDIO: return pulse_set_mute(process_id, muted);
#endif
        default: return -1;
    }
}

// ─── Device Master Volume ────────────────────────────────────

AUDIO_API float audio_get_device_volume(const char* device_id) {
    switch (g_backend) {
#ifdef HAVE_PIPEWIRE
        case BACKEND_PIPEWIRE: return pw_backend_get_device_volume(device_id);
#endif
#ifdef HAVE_PULSE
        case BACKEND_PULSEAUDIO: return pulse_get_device_volume(device_id);
#endif
        default: return -1.0f;
    }
}

AUDIO_API int32_t audio_set_device_volume(const char* device_id, float volume) {
    switch (g_backend) {
#ifdef HAVE_PIPEWIRE
        case BACKEND_PIPEWIRE: return pw_backend_set_device_volume(device_id, volume);
#endif
#ifdef HAVE_PULSE
        case BACKEND_PULSEAUDIO: return pulse_set_device_volume(device_id, volume);
#endif
        default: return -1;
    }
}

// ─── App Icon (XDG icon theme resolution) ────────────────────

// Resolve an app icon from its PID by:
// 1. Reading /proc/{pid}/exe to get the binary path
// 2. Searching .desktop files for a matching Exec=
// 3. Reading the Icon= field
// 4. Resolving the icon in the XDG icon theme hierarchy

static int find_desktop_icon(uint32_t pid, char* icon_name, size_t icon_name_len) {
    // Get executable path
    char proc_link[64];
    char exe_path[PATH_MAX];
    snprintf(proc_link, sizeof(proc_link), "/proc/%u/exe", pid);

    ssize_t len = readlink(proc_link, exe_path, sizeof(exe_path) - 1);
    if (len < 0) return -1;
    exe_path[len] = '\0';

    // Get just the binary name
    const char *bin_name = strrchr(exe_path, '/');
    bin_name = bin_name ? bin_name + 1 : exe_path;

    // Search .desktop files
    const char *dirs[] = {
        "/usr/share/applications",
        "/usr/local/share/applications",
        NULL,
    };

    // Also check user .local
    char user_dir[PATH_MAX];
    const char *home = getenv("HOME");
    if (home) {
        snprintf(user_dir, sizeof(user_dir), "%s/.local/share/applications", home);
    }

    for (int d = 0; dirs[d] || d == 0; d++) {
        const char *search_dir = (d == 0 && home) ? user_dir : dirs[d];
        if (!search_dir) continue;

        DIR *dp = opendir(search_dir);
        if (!dp) continue;

        struct dirent *entry;
        while ((entry = readdir(dp)) != NULL) {
            if (!strstr(entry->d_name, ".desktop")) continue;

            char desktop_path[PATH_MAX];
            snprintf(desktop_path, sizeof(desktop_path), "%s/%s", search_dir, entry->d_name);

            FILE *f = fopen(desktop_path, "r");
            if (!f) continue;

            char line[1024];
            int found_exec = 0;
            char found_icon[256] = {0};

            while (fgets(line, sizeof(line), f)) {
                if (strncmp(line, "Exec=", 5) == 0) {
                    if (strstr(line + 5, bin_name)) {
                        found_exec = 1;
                    }
                }
                if (strncmp(line, "Icon=", 5) == 0) {
                    char *val = line + 5;
                    size_t vlen = strlen(val);
                    if (vlen > 0 && val[vlen-1] == '\n') val[vlen-1] = '\0';
                    snprintf(found_icon, sizeof(found_icon), "%s", val);
                }
            }
            fclose(f);

            if (found_exec && found_icon[0]) {
                snprintf(icon_name, icon_name_len, "%s", found_icon);
                closedir(dp);
                return 0;
            }
        }
        closedir(dp);
    }

    return -1;
}

AUDIO_API int32_t audio_get_app_icon(uint32_t pid, uint8_t* rgba_buf, int32_t buf_size,
                                     int32_t* out_width, int32_t* out_height) {
    // For now, return -1 (not implemented)
    // Full implementation would:
    // 1. find_desktop_icon() to get icon name
    // 2. Search /usr/share/icons/{theme}/32x32/apps/{name}.png
    // 3. Load PNG with stb_image and write to rgba_buf
    (void)pid; (void)rgba_buf; (void)buf_size;
    if (out_width) *out_width = 0;
    if (out_height) *out_height = 0;
    return -1;
}

// ─── Loopback Mirror ─────────────────────────────────────────

AUDIO_API int32_t audio_start_mirror(const char* source_device_id,
                                      const char* target_device_id) {
    switch (g_backend) {
#ifdef HAVE_PIPEWIRE
        case BACKEND_PIPEWIRE: return pw_backend_start_mirror(source_device_id, target_device_id);
#endif
#ifdef HAVE_PULSE
        case BACKEND_PULSEAUDIO: return pulse_start_mirror(source_device_id, target_device_id);
#endif
        default: return -1;
    }
}

AUDIO_API int32_t audio_stop_mirror(const char* source_device_id,
                                     const char* target_device_id) {
    switch (g_backend) {
#ifdef HAVE_PIPEWIRE
        case BACKEND_PIPEWIRE: return pw_backend_stop_mirror(source_device_id, target_device_id);
#endif
#ifdef HAVE_PULSE
        case BACKEND_PULSEAUDIO: return pulse_stop_mirror(source_device_id, target_device_id);
#endif
        default: return -1;
    }
}

AUDIO_API void audio_stop_all_mirrors(void) {
    switch (g_backend) {
#ifdef HAVE_PIPEWIRE
        case BACKEND_PIPEWIRE: pw_backend_stop_all_mirrors(); break;
#endif
#ifdef HAVE_PULSE
        case BACKEND_PULSEAUDIO: pulse_stop_all_mirrors(); break;
#endif
        default: break;
    }
}

// ─── Auto-Start (XDG) ───────────────────────────────────────

static void get_autostart_path(char* buf, size_t buflen) {
    const char *home = getenv("HOME");
    if (home) {
        snprintf(buf, buflen, "%s/.config/autostart/audio_router.desktop", home);
    } else {
        buf[0] = '\0';
    }
}

static void get_exe_path(char* buf, size_t buflen) {
    ssize_t len = readlink("/proc/self/exe", buf, buflen - 1);
    if (len > 0) {
        buf[len] = '\0';
    } else {
        snprintf(buf, buflen, "/usr/bin/audio_router");
    }
}

AUDIO_API int32_t audio_set_autostart(int32_t enabled) {
    char path[PATH_MAX];
    get_autostart_path(path, sizeof(path));
    if (!path[0]) return -1;

    if (enabled) {
        // Ensure directory exists
        char dir[PATH_MAX];
        snprintf(dir, sizeof(dir), "%s/.config/autostart", getenv("HOME"));
        mkdir(dir, 0755);

        char exe[PATH_MAX];
        get_exe_path(exe, sizeof(exe));

        FILE *f = fopen(path, "w");
        if (!f) return -1;

        fprintf(f,
            "[Desktop Entry]\n"
            "Type=Application\n"
            "Name=AudioRouter\n"
            "Comment=Per-app audio routing\n"
            "Exec=%s\n"
            "Icon=audio_router\n"
            "Terminal=false\n"
            "X-GNOME-Autostart-enabled=true\n"
            "StartupNotify=false\n"
            "Categories=AudioVideo;Audio;\n",
            exe);
        fclose(f);
        return 0;
    } else {
        return (unlink(path) == 0 || errno == ENOENT) ? 0 : -1;
    }
}

AUDIO_API int32_t audio_get_autostart(void) {
    char path[PATH_MAX];
    get_autostart_path(path, sizeof(path));
    if (!path[0]) return 0;
    return (access(path, F_OK) == 0) ? 1 : 0;
}

// ─── Set Default Device ──────────────────────────────────────

AUDIO_API int32_t audio_set_default_device(const char* device_id) {
    if (!device_id || device_id[0] == '\0') return -1;

    // Use pactl or wpctl depending on backend
    char cmd[512];
    if (g_backend == BACKEND_PIPEWIRE) {
        // wpctl set-default <node-id>
        snprintf(cmd, sizeof(cmd), "wpctl set-default %s", device_id);
    } else {
        // pactl set-default-sink <sink-name>
        snprintf(cmd, sizeof(cmd), "pactl set-default-sink %s", device_id);
    }
    int ret = system(cmd);
    return (ret == 0) ? 0 : -1;
}

// ─── Device Balance (Stereo L/R) ────────────────────────────

AUDIO_API float audio_get_device_balance(const char* device_id) {
    if (!device_id || device_id[0] == '\0') return 0.0f;

    // Use pactl to get sink channel volumes
    // pactl list sinks outputs volume info per channel
    char cmd[512];
    snprintf(cmd, sizeof(cmd),
        "pactl get-sink-volume %s 2>/dev/null", device_id);

    FILE *fp = popen(cmd, "r");
    if (!fp) return 0.0f;

    char line[512];
    float left_pct = -1.0f, right_pct = -1.0f;

    while (fgets(line, sizeof(line), fp)) {
        // Parse "Volume: front-left: 65536 / 100% / 0.00 dB,   front-right: 65536 / 100% / 0.00 dB"
        char *fl = strstr(line, "front-left:");
        char *fr = strstr(line, "front-right:");
        if (fl && fr) {
            char *pct_l = strchr(fl, '/');
            if (pct_l) {
                pct_l++; // skip '/'
                left_pct = (float)atoi(pct_l);
            }
            char *pct_r = strchr(fr, '/');
            if (pct_r) {
                pct_r++;
                right_pct = (float)atoi(pct_r);
            }
            break;
        }
    }
    pclose(fp);

    if (left_pct < 0 || right_pct < 0) return 0.0f;
    float sum = left_pct + right_pct;
    if (sum < 0.01f) return 0.0f;
    return (right_pct - left_pct) / sum;
}

AUDIO_API int32_t audio_set_device_balance(const char* device_id, float balance) {
    if (!device_id || device_id[0] == '\0') return -1;
    if (balance < -1.0f) balance = -1.0f;
    if (balance > 1.0f) balance = 1.0f;

    // First get current overall volume percentage
    char cmd[512];
    snprintf(cmd, sizeof(cmd),
        "pactl get-sink-volume %s 2>/dev/null | head -1", device_id);
    FILE *fp = popen(cmd, "r");
    if (!fp) return -1;

    char line[512];
    int master_pct = 100;
    if (fgets(line, sizeof(line), fp)) {
        char *pct = strchr(line, '/');
        if (pct) {
            pct++;
            master_pct = atoi(pct);
        }
    }
    pclose(fp);

    int left_pct, right_pct;
    if (balance <= 0.0f) {
        left_pct = master_pct;
        right_pct = (int)(master_pct * (1.0f + balance));
    } else {
        left_pct = (int)(master_pct * (1.0f - balance));
        right_pct = master_pct;
    }

    // pactl set-sink-volume <sink> <left>% <right>%
    snprintf(cmd, sizeof(cmd),
        "pactl set-sink-volume %s %d%% %d%%", device_id, left_pct, right_pct);
    int ret = system(cmd);
    return (ret == 0) ? 0 : -1;
}

// ─── OS Sound Settings ──────────────────────────────────────

AUDIO_API int32_t audio_open_sound_settings(void) {
    // Try GNOME Settings first, fall back to generic
    int ret = system("gnome-control-center sound &>/dev/null &");
    if (ret != 0) {
        ret = system("xdg-open x-settings://sound &>/dev/null &");
    }
    if (ret != 0) {
        ret = system("pavucontrol &>/dev/null &");
    }
    return (ret == 0) ? 0 : -1;
}

// ─── OS Accent Color ────────────────────────────────────────

AUDIO_API uint32_t audio_get_accent_color(void) {
    // Try GNOME gsettings accent-color (GNOME 47+)
    FILE *fp = popen(
        "gsettings get org.gnome.desktop.interface accent-color 2>/dev/null", "r");
    if (fp) {
        char line[128];
        if (fgets(line, sizeof(line), fp)) {
            // Returns something like "'blue'" or "'teal'"
            // Map common GNOME accent colors to ARGB
            pclose(fp);
            struct { const char* name; uint32_t argb; } colors[] = {
                {"blue",   0xFF3584E4},
                {"teal",   0xFF2190A4},
                {"green",  0xFF3A944A},
                {"yellow", 0xFFC88800},
                {"orange", 0xFFE66100},
                {"red",    0xFFE01B24},
                {"pink",   0xFFD56199},
                {"purple", 0xFF9141AC},
                {"slate",  0xFF6E8B9E},
                {NULL, 0}
            };
            for (int i = 0; colors[i].name; i++) {
                if (strstr(line, colors[i].name)) {
                    return colors[i].argb;
                }
            }
            return 0xFF3584E4; // default GNOME blue
        }
        pclose(fp);
    }

    // Fallback: try reading GTK theme color from gtk.css
    return 0xFF3584E4; // GNOME default blue
}

// ─── Global Hotkeys ──────────────────────────────────────────

// TODO: Implement X11 XGrabKey + Wayland D-Bus portal
// For now, stub implementations

AUDIO_API int32_t audio_register_hotkey(int32_t id, uint32_t modifiers, uint32_t vk) {
    (void)id; (void)modifiers; (void)vk;
    // TODO: X11 XGrabKey or Wayland portal
    return -1;
}

AUDIO_API int32_t audio_unregister_hotkey(int32_t id) {
    (void)id;
    return -1;
}

AUDIO_API int32_t audio_poll_hotkey(void) {
    return 0; // No hotkey pressed
}
