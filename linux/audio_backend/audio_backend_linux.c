// audio_backend_linux.c — Main dispatcher for AudioRouter Linux backend
//
// Detects PipeWire vs PulseAudio at runtime and delegates all calls
// to the appropriate backend. Also handles XDG autostart, app icons,
// and global hotkeys.

#define AUDIO_BACKEND_EXPORTS
#include "audio_backend_linux.h"

#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>
#include <dirent.h>
#include <sys/stat.h>
#include <pthread.h>

#ifdef HAVE_GDK_PIXBUF
#include <gdk-pixbuf/gdk-pixbuf.h>
#endif

#ifdef HAVE_X11
#include <X11/Xlib.h>
#include <X11/keysym.h>
#endif

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
    if (!out_width || !out_height) return -1;
    *out_width = 0; *out_height = 0;

#ifndef HAVE_GDK_PIXBUF
    (void)pid; (void)rgba_buf; (void)buf_size;
    return -1;
#else
    // Step 1: get icon name from .desktop file
    char icon_name[256] = {0};
    if (find_desktop_icon(pid, icon_name, sizeof(icon_name)) != 0) {
        // Fallback: use binary name as icon name
        char link[64];
        char exe[PATH_MAX];
        snprintf(link, sizeof(link), "/proc/%u/exe", pid);
        ssize_t n = readlink(link, exe, sizeof(exe) - 1);
        if (n <= 0) return -1;
        exe[n] = '\0';
        const char *bn = strrchr(exe, '/');
        snprintf(icon_name, sizeof(icon_name), "%s", bn ? bn + 1 : exe);
    }

    // Step 2: resolve icon path — full path, or search XDG hierarchy
    char icon_path[PATH_MAX] = {0};
    if (icon_name[0] == '/') {
        strncpy(icon_path, icon_name, sizeof(icon_path) - 1);
    } else {
        // sizes and themes to try, in preference order
        const char *sizes[] = {"32x32","48x48","64x64","128x128","256x256", NULL};
        const char *bases[] = {
            "/usr/share/icons/hicolor",
            "/usr/share/icons/Adwaita",
            "/usr/share/icons",
            NULL
        };
        for (int b = 0; bases[b] && !icon_path[0]; b++) {
            for (int s = 0; sizes[s] && !icon_path[0]; s++) {
                char tmp[PATH_MAX];
                snprintf(tmp, sizeof(tmp), "%s/%s/apps/%s.png",
                         bases[b], sizes[s], icon_name);
                if (access(tmp, R_OK) == 0) strncpy(icon_path, tmp, sizeof(icon_path)-1);
            }
        }
        // pixmaps fallback
        if (!icon_path[0]) {
            char tmp[PATH_MAX];
            snprintf(tmp, sizeof(tmp), "/usr/share/pixmaps/%s.png", icon_name);
            if (access(tmp, R_OK) == 0) strncpy(icon_path, tmp, sizeof(icon_path)-1);
        }
    }
    if (!icon_path[0]) return -1;

    // Step 3: load + scale to 32×32 with GdkPixbuf
    GError *err = NULL;
    GdkPixbuf *pb = gdk_pixbuf_new_from_file_at_scale(icon_path, 32, 32, FALSE, &err);
    if (!pb) { if (err) g_error_free(err); return -1; }

    int W = gdk_pixbuf_get_width(pb);
    int H = gdk_pixbuf_get_height(pb);
    *out_width  = W;
    *out_height = H;

    int needed = W * H * 4;
    if (!rgba_buf || buf_size < needed) { g_object_unref(pb); return needed; }

    // Ensure RGBA (add alpha channel if the source is RGB-only)
    GdkPixbuf *rgba = gdk_pixbuf_add_alpha(pb, FALSE, 0, 0, 0);
    g_object_unref(pb);
    if (!rgba) return -1;

    const guchar *pixels = gdk_pixbuf_get_pixels(rgba);
    int rowstride = gdk_pixbuf_get_rowstride(rgba);
    for (int y = 0; y < H; y++)
        memcpy(rgba_buf + y * W * 4, pixels + y * rowstride, (size_t)(W * 4));

    g_object_unref(rgba);
    return 0;
#endif
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

// ─── Global Hotkeys (X11 XGrabKey) ───────────────────────────

#ifdef HAVE_X11

// Suppress X11 grab errors (e.g. key already grabbed by another app)
static int hk_x11_error(Display *d, XErrorEvent *e) {
    (void)d; (void)e; return 0;
}

typedef struct { int32_t id; KeyCode kc; unsigned int mods; } HKEntry;

static Display       *g_hk_display = NULL;
static Window         g_hk_root    = None;
static HKEntry        g_hk_entries[16];
static int            g_hk_count   = 0;
static pthread_t      g_hk_thread;
static volatile int   g_hk_running = 0;

// Circular queue for triggered hotkeys
static int32_t        g_hk_queue[8];
static int            g_hk_qhead = 0, g_hk_qtail = 0;
static pthread_mutex_t g_hk_mutex = PTHREAD_MUTEX_INITIALIZER;

// Windows VK → X11 KeySym
static KeySym vk_to_keysym(uint32_t vk) {
    if (vk >= 0x30 && vk <= 0x39) return (KeySym)(XK_0 + (vk - 0x30));  // 0-9
    if (vk >= 0x41 && vk <= 0x5A) return (KeySym)(XK_a + (vk - 0x41));  // a-z
    if (vk >= 0x70 && vk <= 0x7B) return (KeySym)(XK_F1 + (vk - 0x70)); // F1-F12
    switch (vk) {
        case 0x20: return XK_space;
        case 0x08: return XK_BackSpace;
        case 0x0D: return XK_Return;
        case 0x1B: return XK_Escape;
        default:   return (KeySym)vk;
    }
}

// Windows modifier flags → X11 masks
static unsigned int win_to_x11_mods(uint32_t m) {
    unsigned int x = 0;
    if (m & 1) x |= Mod1Mask;    // Alt
    if (m & 2) x |= ControlMask; // Ctrl
    if (m & 4) x |= ShiftMask;   // Shift
    if (m & 8) x |= Mod4Mask;    // Super/Win
    return x;
}

static void *hk_thread_fn(void *arg) {
    (void)arg;
    XEvent ev;
    while (g_hk_running) {
        while (XPending(g_hk_display) > 0) {
            XNextEvent(g_hk_display, &ev);
            if (ev.type == KeyPress) {
                unsigned int state = ev.xkey.state &
                    (ControlMask | Mod1Mask | ShiftMask | Mod4Mask);
                pthread_mutex_lock(&g_hk_mutex);
                for (int i = 0; i < g_hk_count; i++) {
                    if (g_hk_entries[i].kc   == ev.xkey.keycode &&
                        g_hk_entries[i].mods == state) {
                        int next = (g_hk_qtail + 1) % 8;
                        if (next != g_hk_qhead) {
                            g_hk_queue[g_hk_qtail] = g_hk_entries[i].id;
                            g_hk_qtail = next;
                        }
                        break;
                    }
                }
                pthread_mutex_unlock(&g_hk_mutex);
            }
        }
        usleep(10000); // 10 ms poll
    }
    return NULL;
}

static int hk_init_x11(void) {
    if (g_hk_display) return 0;
    g_hk_display = XOpenDisplay(NULL);
    if (!g_hk_display) return -1;
    g_hk_root = DefaultRootWindow(g_hk_display);
    XSetErrorHandler(hk_x11_error);
    g_hk_running = 1;
    return pthread_create(&g_hk_thread, NULL, hk_thread_fn, NULL);
}

#endif // HAVE_X11

AUDIO_API int32_t audio_register_hotkey(int32_t id, uint32_t modifiers, uint32_t vk) {
#ifdef HAVE_X11
    if (hk_init_x11() != 0) return -1;
    if (g_hk_count >= 16) return -1;

    KeySym sym = vk_to_keysym(vk);
    KeyCode kc  = XKeysymToKeycode(g_hk_display, sym);
    if (!kc) return -1;

    unsigned int xmods = win_to_x11_mods(modifiers);

    // Grab with and without CapsLock / NumLock so those don't block the hotkey
    unsigned int extra[] = {0, LockMask, Mod2Mask, LockMask | Mod2Mask};
    for (int i = 0; i < 4; i++)
        XGrabKey(g_hk_display, kc, xmods | extra[i],
                 g_hk_root, True, GrabModeAsync, GrabModeAsync);
    XFlush(g_hk_display);

    pthread_mutex_lock(&g_hk_mutex);
    g_hk_entries[g_hk_count++] = (HKEntry){id, kc, xmods};
    pthread_mutex_unlock(&g_hk_mutex);
    return 0;
#else
    (void)id; (void)modifiers; (void)vk;
    return -1;
#endif
}

AUDIO_API int32_t audio_unregister_hotkey(int32_t id) {
#ifdef HAVE_X11
    if (!g_hk_display) return -1;
    pthread_mutex_lock(&g_hk_mutex);
    for (int i = 0; i < g_hk_count; i++) {
        if (g_hk_entries[i].id == id) {
            unsigned int extra[] = {0, LockMask, Mod2Mask, LockMask | Mod2Mask};
            for (int j = 0; j < 4; j++)
                XUngrabKey(g_hk_display, g_hk_entries[i].kc,
                            g_hk_entries[i].mods | extra[j], g_hk_root);
            g_hk_entries[i] = g_hk_entries[--g_hk_count];
            XFlush(g_hk_display);
            break;
        }
    }
    pthread_mutex_unlock(&g_hk_mutex);
    return 0;
#else
    (void)id;
    return -1;
#endif
}

AUDIO_API int32_t audio_poll_hotkey(void) {
#ifdef HAVE_X11
    pthread_mutex_lock(&g_hk_mutex);
    if (g_hk_qhead == g_hk_qtail) {
        pthread_mutex_unlock(&g_hk_mutex);
        return 0;
    }
    int32_t hid = g_hk_queue[g_hk_qhead];
    g_hk_qhead = (g_hk_qhead + 1) % 8;
    pthread_mutex_unlock(&g_hk_mutex);
    return hid;
#else
    return 0;
#endif
}
