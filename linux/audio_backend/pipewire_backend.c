// pipewire_backend.c — PipeWire backend for AudioRouter
//
// Uses PipeWire's API to enumerate sinks, sink-inputs (clients),
// route per-app audio, control volumes, and create loopback mirrors.
// This is the primary backend for modern Linux distributions.
//
// PipeWire exposes audio objects as nodes in a graph:
//   - Sinks (output devices) are nodes with media.class = "Audio/Sink"
//   - Sink-inputs (app streams) are nodes with media.class = "Stream/Output/Audio"
//   - Routing = changing a stream's target.node metadata

#include "pipewire_backend.h"

#include <pipewire/pipewire.h>
#include <spa/param/props.h>
#include <spa/param/audio/format-utils.h>
#include <spa/pod/builder.h>
#include <spa/pod/parser.h>
#include <spa/utils/result.h>

#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <pthread.h>
#include <unistd.h>
#include <errno.h>

// ─── Internal State ──────────────────────────────────────────

static struct pw_thread_loop *g_loop = NULL;
static struct pw_context     *g_context = NULL;
static struct pw_core         *g_core = NULL;
static struct pw_registry     *g_registry = NULL;
static struct spa_hook         g_registry_listener;
static struct spa_hook         g_core_listener;
static int                     g_ready = 0;

#define MAX_SINKS       32
#define MAX_STREAMS     64
#define MAX_MIRRORS     16

// ─── Sink (output device) cache ──────────────────────────────

typedef struct {
    AudioDeviceInfo info;
    uint32_t        id;          // PipeWire global object ID
    int             valid;
    struct spa_hook listener;
    struct pw_proxy *proxy;
} PwSink;

static PwSink  g_sinks[MAX_SINKS];
static int     g_sink_count = 0;
static char    g_default_sink_name[256] = {0};

// ─── Stream (sink-input / app) cache ─────────────────────────

typedef struct {
    AudioSessionInfo info;
    uint32_t         id;         // PipeWire global object ID
    uint32_t         target_id;  // Target sink node ID
    int              valid;
    struct spa_hook  listener;
    struct pw_proxy *proxy;
} PwStream;

static PwStream g_streams[MAX_STREAMS];
static int      g_stream_count = 0;

// ─── Mirror state ────────────────────────────────────────────

typedef struct {
    char     source[256];
    char     target[256];
    uint32_t module_id;
} PwMirror;

static PwMirror g_mirrors[MAX_MIRRORS];
static int      g_mirror_count = 0;

static pthread_mutex_t g_data_mutex = PTHREAD_MUTEX_INITIALIZER;

// ─── Helpers ─────────────────────────────────────────────────

static void _lock(void)   { if (g_loop) pw_thread_loop_lock(g_loop); }
static void _unlock(void) { if (g_loop) pw_thread_loop_unlock(g_loop); }

static void get_process_name(uint32_t pid, char* buf, size_t buflen) {
    char path[64];
    snprintf(path, sizeof(path), "/proc/%u/comm", pid);
    FILE *f = fopen(path, "r");
    if (f) {
        if (fgets(buf, buflen, f)) {
            size_t len = strlen(buf);
            if (len > 0 && buf[len-1] == '\n') buf[len-1] = '\0';
        }
        fclose(f);
    } else {
        snprintf(buf, buflen, "pid-%u", pid);
    }
}

// Find a free slot or return NULL
static PwSink* find_sink_slot(void) {
    for (int i = 0; i < MAX_SINKS; i++) {
        if (!g_sinks[i].valid) return &g_sinks[i];
    }
    return NULL;
}

static PwStream* find_stream_slot(void) {
    for (int i = 0; i < MAX_STREAMS; i++) {
        if (!g_streams[i].valid) return &g_streams[i];
    }
    return NULL;
}

static PwSink* find_sink_by_id(uint32_t id) {
    for (int i = 0; i < MAX_SINKS; i++) {
        if (g_sinks[i].valid && g_sinks[i].id == id) return &g_sinks[i];
    }
    return NULL;
}

static PwStream* find_stream_by_pid(uint32_t pid) {
    for (int i = 0; i < MAX_STREAMS; i++) {
        if (g_streams[i].valid && g_streams[i].info.process_id == pid)
            return &g_streams[i];
    }
    return NULL;
}

static PwSink* find_sink_by_name(const char *name) {
    for (int i = 0; i < MAX_SINKS; i++) {
        if (g_sinks[i].valid && strcmp(g_sinks[i].info.id, name) == 0)
            return &g_sinks[i];
    }
    return NULL;
}

// ─── Node info callback (for sinks and streams) ─────────────

static void on_node_info(void *data, const struct pw_node_info *info) {
    // This callback fires when node properties change (volume, etc.)
    // We could update cached volumes here for real-time tracking
    (void)data;
    (void)info;
}

static const struct pw_node_events node_events = {
    PW_VERSION_NODE_EVENTS,
    .info = on_node_info,
};

// ─── Registry events ─────────────────────────────────────────

static void registry_global(void *data, uint32_t id, uint32_t permissions,
                            const char *type, uint32_t version,
                            const struct spa_dict *props) {
    (void)data;
    (void)permissions;
    (void)version;

    if (!props) return;

    // We only care about nodes
    if (strcmp(type, PW_TYPE_INTERFACE_Node) != 0) return;

    const char *media_class = spa_dict_lookup(props, PW_KEY_MEDIA_CLASS);
    if (!media_class) return;

    pthread_mutex_lock(&g_data_mutex);

    if (strcmp(media_class, "Audio/Sink") == 0) {
        // This is an output device (sink)
        PwSink *sink = find_sink_slot();
        if (!sink) { pthread_mutex_unlock(&g_data_mutex); return; }

        memset(sink, 0, sizeof(PwSink));
        sink->id = id;
        sink->valid = 1;

        const char *node_name = spa_dict_lookup(props, PW_KEY_NODE_NAME);
        const char *node_desc = spa_dict_lookup(props, PW_KEY_NODE_DESCRIPTION);
        const char *node_nick = spa_dict_lookup(props, PW_KEY_NODE_NICK);

        snprintf(sink->info.id, sizeof(sink->info.id), "%s",
                 node_name ? node_name : "unknown");
        snprintf(sink->info.name, sizeof(sink->info.name), "%s",
                 node_desc ? node_desc : (node_name ? node_name : "Unknown Sink"));
        snprintf(sink->info.short_name, sizeof(sink->info.short_name), "%s",
                 node_nick ? node_nick : (node_desc ? node_desc : "Sink"));

        sink->info.is_active = 1;
        sink->info.volume = 1.0f;

        // Check if this is the default sink
        if (g_default_sink_name[0] && node_name &&
            strcmp(node_name, g_default_sink_name) == 0) {
            sink->info.is_default = 1;
        }

        g_sink_count++;

    } else if (strcmp(media_class, "Stream/Output/Audio") == 0) {
        // This is an app audio stream (sink-input)
        PwStream *stream = find_stream_slot();
        if (!stream) { pthread_mutex_unlock(&g_data_mutex); return; }

        memset(stream, 0, sizeof(PwStream));
        stream->id = id;
        stream->valid = 1;

        const char *app_name = spa_dict_lookup(props, PW_KEY_APP_NAME);
        const char *pid_str  = spa_dict_lookup(props, PW_KEY_APP_PROCESS_ID);
        const char *media_name = spa_dict_lookup(props, PW_KEY_MEDIA_NAME);

        stream->info.process_id = pid_str ? (uint32_t)atoi(pid_str) : 0;

        // Skip our own streams
        if (app_name && strcmp(app_name, "AudioRouter") == 0) {
            stream->valid = 0;
            pthread_mutex_unlock(&g_data_mutex);
            return;
        }

        if (stream->info.process_id > 0) {
            get_process_name(stream->info.process_id,
                             stream->info.process_name,
                             sizeof(stream->info.process_name));
        } else if (app_name) {
            snprintf(stream->info.process_name,
                     sizeof(stream->info.process_name), "%s", app_name);
        }

        snprintf(stream->info.display_name, sizeof(stream->info.display_name),
                 "%s", app_name ? app_name : stream->info.process_name);

        stream->info.is_active = 1;
        stream->info.volume = 1.0f;
        stream->info.peak_level = 0.0f;

        // Get target node
        const char *target = spa_dict_lookup(props, PW_KEY_TARGET_OBJECT);
        if (!target) target = spa_dict_lookup(props, "target.node");
        stream->target_id = target ? (uint32_t)atoi(target) : 0;

        g_stream_count++;
    }

    pthread_mutex_unlock(&g_data_mutex);
}

static void registry_global_remove(void *data, uint32_t id) {
    (void)data;

    pthread_mutex_lock(&g_data_mutex);

    // Remove sink
    for (int i = 0; i < MAX_SINKS; i++) {
        if (g_sinks[i].valid && g_sinks[i].id == id) {
            g_sinks[i].valid = 0;
            g_sink_count--;
            break;
        }
    }

    // Remove stream
    for (int i = 0; i < MAX_STREAMS; i++) {
        if (g_streams[i].valid && g_streams[i].id == id) {
            g_streams[i].valid = 0;
            g_stream_count--;
            break;
        }
    }

    pthread_mutex_unlock(&g_data_mutex);
}

static const struct pw_registry_events registry_events = {
    PW_VERSION_REGISTRY_EVENTS,
    .global = registry_global,
    .global_remove = registry_global_remove,
};

// ─── Core events ─────────────────────────────────────────────

static void on_core_done(void *data, uint32_t id, int seq) {
    (void)data;
    (void)id;
    (void)seq;
    g_ready = 1;
    pw_thread_loop_signal(g_loop, false);
}

static void on_core_error(void *data, uint32_t id, int seq, int res, const char *message) {
    (void)data;
    (void)id;
    (void)seq;
    fprintf(stderr, "AudioRouter PipeWire error: %s (res=%d)\n", message, res);
}

static const struct pw_core_events core_events = {
    PW_VERSION_CORE_EVENTS,
    .done = on_core_done,
    .error = on_core_error,
};

// ─── Detect default sink via pw-cli or environment ───────────

static void detect_default_sink(void) {
    // Try to get default sink from pipewire-pulse or wpctl
    FILE *fp = popen("LANG=C wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep 'node.name' | head -1 | awk -F'\"' '{print $2}'", "r");
    if (fp) {
        if (fgets(g_default_sink_name, sizeof(g_default_sink_name), fp)) {
            size_t len = strlen(g_default_sink_name);
            if (len > 0 && g_default_sink_name[len-1] == '\n')
                g_default_sink_name[len-1] = '\0';
        }
        pclose(fp);
    }
}

// ─── Public API ──────────────────────────────────────────────

int pw_backend_init(void) {
    pw_init(NULL, NULL);

    detect_default_sink();

    g_loop = pw_thread_loop_new("audio-router", NULL);
    if (!g_loop) return -1;

    g_context = pw_context_new(pw_thread_loop_get_loop(g_loop), NULL, 0);
    if (!g_context) {
        pw_thread_loop_destroy(g_loop);
        g_loop = NULL;
        return -1;
    }

    pw_thread_loop_lock(g_loop);
    pw_thread_loop_start(g_loop);

    g_core = pw_context_connect(g_context, NULL, 0);
    if (!g_core) {
        pw_thread_loop_unlock(g_loop);
        pw_thread_loop_stop(g_loop);
        pw_context_destroy(g_context);
        pw_thread_loop_destroy(g_loop);
        g_context = NULL;
        g_loop = NULL;
        return -1;
    }

    pw_core_add_listener(g_core, &g_core_listener, &core_events, NULL);

    g_registry = pw_core_get_registry(g_core, PW_VERSION_REGISTRY, 0);
    pw_registry_add_listener(g_registry, &g_registry_listener, &registry_events, NULL);

    // Trigger a sync to get initial objects
    pw_core_sync(g_core, PW_ID_CORE, 0);

    // Wait for the initial roundtrip
    while (!g_ready) {
        pw_thread_loop_wait(g_loop);
    }

    pw_thread_loop_unlock(g_loop);

    return 0;
}

void pw_backend_cleanup(void) {
    pw_backend_stop_all_mirrors();

    if (g_loop) {
        pw_thread_loop_lock(g_loop);

        if (g_registry) {
            pw_proxy_destroy((struct pw_proxy*)g_registry);
            g_registry = NULL;
        }
        if (g_core) {
            pw_core_disconnect(g_core);
            g_core = NULL;
        }

        pw_thread_loop_unlock(g_loop);
        pw_thread_loop_stop(g_loop);

        if (g_context) {
            pw_context_destroy(g_context);
            g_context = NULL;
        }
        pw_thread_loop_destroy(g_loop);
        g_loop = NULL;
    }

    pw_deinit();
    g_ready = 0;
}

int32_t pw_backend_get_device_count(void) {
    pthread_mutex_lock(&g_data_mutex);
    int c = 0;
    for (int i = 0; i < MAX_SINKS; i++) {
        if (g_sinks[i].valid) c++;
    }
    pthread_mutex_unlock(&g_data_mutex);
    return c;
}

int32_t pw_backend_get_devices(AudioDeviceInfo* devices, int32_t max_count) {
    pthread_mutex_lock(&g_data_mutex);
    int count = 0;
    for (int i = 0; i < MAX_SINKS && count < max_count; i++) {
        if (g_sinks[i].valid) {
            devices[count++] = g_sinks[i].info;
        }
    }
    pthread_mutex_unlock(&g_data_mutex);
    return count;
}

int32_t pw_backend_get_session_count(void) {
    pthread_mutex_lock(&g_data_mutex);
    int c = 0;
    for (int i = 0; i < MAX_STREAMS; i++) {
        if (g_streams[i].valid) c++;
    }
    pthread_mutex_unlock(&g_data_mutex);
    return c;
}

int32_t pw_backend_get_sessions(AudioSessionInfo* sessions, int32_t max_count) {
    pthread_mutex_lock(&g_data_mutex);
    int count = 0;
    for (int i = 0; i < MAX_STREAMS && count < max_count; i++) {
        if (g_streams[i].valid) {
            sessions[count++] = g_streams[i].info;
        }
    }
    pthread_mutex_unlock(&g_data_mutex);
    return count;
}

int32_t pw_backend_poll_peaks(PeakLevelInfo* peaks, int32_t max_count) {
    // PipeWire peak metering requires subscribing to node params
    // For now, return basic activity indication
    pthread_mutex_lock(&g_data_mutex);
    int count = 0;
    for (int i = 0; i < MAX_STREAMS && count < max_count; i++) {
        if (g_streams[i].valid) {
            peaks[count].process_id = g_streams[i].info.process_id;
            peaks[count].peak_level = g_streams[i].info.is_active ? 0.1f : 0.0f;
            count++;
        }
    }
    pthread_mutex_unlock(&g_data_mutex);
    return count;
}

int32_t pw_backend_route_process(uint32_t pid, const char* device_id) {
    // Use WirePlumber's wpctl or pw-metadata to move a stream to a different sink
    // This is the most reliable cross-version approach

    pthread_mutex_lock(&g_data_mutex);

    // Find the stream node ID for this PID
    uint32_t stream_id = 0;
    for (int i = 0; i < MAX_STREAMS; i++) {
        if (g_streams[i].valid && g_streams[i].info.process_id == pid) {
            stream_id = g_streams[i].id;
            break;
        }
    }

    // Find the target sink node ID
    uint32_t sink_id = 0;
    if (device_id && device_id[0]) {
        for (int i = 0; i < MAX_SINKS; i++) {
            if (g_sinks[i].valid && strcmp(g_sinks[i].info.id, device_id) == 0) {
                sink_id = g_sinks[i].id;
                break;
            }
        }
    } else {
        // Empty = move to default
        for (int i = 0; i < MAX_SINKS; i++) {
            if (g_sinks[i].valid && g_sinks[i].info.is_default) {
                sink_id = g_sinks[i].id;
                break;
            }
        }
    }

    pthread_mutex_unlock(&g_data_mutex);

    if (!stream_id || !sink_id) return -1;

    // Use pw-metadata to set the target node for this stream
    // This is the WirePlumber-compatible way to route streams
    char cmd[512];
    snprintf(cmd, sizeof(cmd),
             "pw-metadata -n default 0 'target.node' '{ \"value\": %u }' 'Spa:Id' 2>/dev/null; "
             "wpctl set-default %u 2>/dev/null",
             sink_id, sink_id);

    // For per-stream routing, use pw-cli or the PipeWire API directly
    // The most reliable method is setting the target.node property on the stream
    snprintf(cmd, sizeof(cmd),
             "pw-cli s %u Props '{ target.node = %u }' 2>/dev/null",
             stream_id, sink_id);

    int ret = system(cmd);
    return (ret == 0) ? 0 : -1;
}

int32_t pw_backend_set_volume(uint32_t pid, float volume) {
    pthread_mutex_lock(&g_data_mutex);
    uint32_t stream_id = 0;
    for (int i = 0; i < MAX_STREAMS; i++) {
        if (g_streams[i].valid && g_streams[i].info.process_id == pid) {
            stream_id = g_streams[i].id;
            g_streams[i].info.volume = volume;
            break;
        }
    }
    pthread_mutex_unlock(&g_data_mutex);

    if (!stream_id) return -1;

    char cmd[256];
    snprintf(cmd, sizeof(cmd), "wpctl set-volume %u %.2f 2>/dev/null", stream_id, volume);
    return system(cmd) == 0 ? 0 : -1;
}

int32_t pw_backend_set_mute(uint32_t pid, int32_t muted) {
    pthread_mutex_lock(&g_data_mutex);
    uint32_t stream_id = 0;
    for (int i = 0; i < MAX_STREAMS; i++) {
        if (g_streams[i].valid && g_streams[i].info.process_id == pid) {
            stream_id = g_streams[i].id;
            g_streams[i].info.is_muted = muted;
            break;
        }
    }
    pthread_mutex_unlock(&g_data_mutex);

    if (!stream_id) return -1;

    char cmd[256];
    snprintf(cmd, sizeof(cmd), "wpctl set-mute %u %d 2>/dev/null", stream_id, muted ? 1 : 0);
    return system(cmd) == 0 ? 0 : -1;
}

float pw_backend_get_device_volume(const char* device_id) {
    pthread_mutex_lock(&g_data_mutex);
    float vol = -1.0f;
    for (int i = 0; i < MAX_SINKS; i++) {
        if (g_sinks[i].valid && strcmp(g_sinks[i].info.id, device_id) == 0) {
            vol = g_sinks[i].info.volume;
            break;
        }
    }
    pthread_mutex_unlock(&g_data_mutex);
    return vol;
}

int32_t pw_backend_set_device_volume(const char* device_id, float volume) {
    pthread_mutex_lock(&g_data_mutex);
    uint32_t sink_id = 0;
    for (int i = 0; i < MAX_SINKS; i++) {
        if (g_sinks[i].valid && strcmp(g_sinks[i].info.id, device_id) == 0) {
            sink_id = g_sinks[i].id;
            g_sinks[i].info.volume = volume;
            break;
        }
    }
    pthread_mutex_unlock(&g_data_mutex);

    if (!sink_id) return -1;

    char cmd[256];
    snprintf(cmd, sizeof(cmd), "wpctl set-volume %u %.2f 2>/dev/null", sink_id, volume);
    return system(cmd) == 0 ? 0 : -1;
}

int32_t pw_backend_start_mirror(const char* source_id, const char* target_id) {
    if (!source_id || !target_id) return -1;
    if (g_mirror_count >= MAX_MIRRORS) return -1;

    // Check if already mirroring
    for (int i = 0; i < g_mirror_count; i++) {
        if (strcmp(g_mirrors[i].source, source_id) == 0 &&
            strcmp(g_mirrors[i].target, target_id) == 0) {
            return 0;
        }
    }

    // Use pw-loopback to create a loopback from source to target
    char cmd[1024];
    snprintf(cmd, sizeof(cmd),
             "pw-loopback -C '%s' -P '%s' --capture-props='stream.dont-remix=true' &",
             source_id, target_id);

    int ret = system(cmd);
    if (ret != 0) return -1;

    PwMirror *m = &g_mirrors[g_mirror_count++];
    snprintf(m->source, sizeof(m->source), "%s", source_id);
    snprintf(m->target, sizeof(m->target), "%s", target_id);
    m->module_id = 0; // We'd need to track the PID of pw-loopback

    return 0;
}

int32_t pw_backend_stop_mirror(const char* source_id, const char* target_id) {
    for (int i = 0; i < g_mirror_count; i++) {
        if (strcmp(g_mirrors[i].source, source_id) == 0 &&
            strcmp(g_mirrors[i].target, target_id) == 0) {
            // Kill the pw-loopback process (simplified)
            // In production, we'd track the PID and kill it directly
            g_mirrors[i] = g_mirrors[--g_mirror_count];
            return 0;
        }
    }
    return -1;
}

void pw_backend_stop_all_mirrors(void) {
    // Kill all pw-loopback processes we started
    system("pkill -f 'pw-loopback.*AudioRouter' 2>/dev/null");
    g_mirror_count = 0;
}
