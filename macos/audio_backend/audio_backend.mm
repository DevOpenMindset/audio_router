// audio_backend.mm — macOS Core Audio backend for AudioRouter
//
// Routing strategy by macOS version:
//   macOS 14.2+  → CATapDescription + AVAudioEngine  (capture & redirect)
//   macOS 12–14  → kAudioProcessPropertyDevice        (system routing, best-effort)
//   macOS < 12   → no-op (process API unavailable)
//
// Volume / mute on macOS 14.2+ work via the AVAudioMixerNode in the tap engine.
// Build: see build.sh

#include "audio_backend.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <AVFAudio/AVFAudio.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreGraphics/CoreGraphics.h>
#include <AudioUnit/AudioUnit.h>
#include <Carbon/Carbon.h>
#include <libproc.h>
#ifndef PROC_NAME_LEN
#define PROC_NAME_LEN 256
#endif

#include <chrono>
#include <string>
#include <vector>
#include <map>
#include <queue>
#include <mutex>
#include <cstring>
#include <algorithm>

// Process audio object properties come from the SDK's AudioHardware.h
// (kAudioHardwarePropertyProcessObjectList = 'prs#', kAudioProcessPropertyPID
// = 'ppid', kAudioProcessPropertyIsRunningOutput = 'piro'). Do NOT re-define
// them behind #ifndef: they are C enums, not macros, so the guard always
// fires and a wrong four-char code here silently breaks session enumeration
// (GetPropertyDataSize returns kAudioHardwareUnknownPropertyError → the app
// falls back to an empty session list). Requires the macOS 14.4+ SDK.

// Per-process device routing — macOS 14+
#ifndef kAudioProcessPropertyDevice
#define kAudioProcessPropertyDevice 'pdev'
#endif

// ─── Forward declarations for CATapDescription (macOS 14.2+) ─
// Declared here so the file compiles against older SDKs.
// Guarded by @available at runtime.

#if __MAC_OS_X_VERSION_MAX_ALLOWED < 140200
typedef NS_ENUM(NSInteger, CATapMuteBehavior) {
    CATapUnmuted = 0,
    CATapMuted = 1,
    CATapMutedWhenTapped = 2,
};
@interface CATapDescription : NSObject
- (instancetype)initStereoMixdownOfProcesses:(NSArray<NSNumber *> *)processObjectIDs;
@property (atomic, readwrite, getter=isMuted) CATapMuteBehavior muteBehavior;
@property (nonatomic, copy) NSString *name;
@end
extern "C" OSStatus AudioHardwareCreateProcessTap(CATapDescription *inDesc, AudioObjectID *outTapID);
extern "C" OSStatus AudioHardwareDestroyProcessTap(AudioObjectID inTapID);
#else
#include <CoreAudio/CATapDescription.h>
// These symbols may be absent from CATapDescription.h in newer SDKs — declare explicitly.
extern "C" OSStatus AudioHardwareCreateProcessTap(CATapDescription *inDesc, AudioObjectID *outTapID);
extern "C" OSStatus AudioHardwareDestroyProcessTap(AudioObjectID inTapID);
#endif

// ─── Internal State ──────────────────────────────────────────

static bool g_initialized = false;
static std::mutex g_mutex;

// PID → routed device (for peak level lookups)
static std::map<pid_t, AudioObjectID> g_pidToDevice;

// Tap routing state (macOS 14.2+): one engine per routed PID
static NSMutableDictionary<NSNumber *, AVAudioEngine *>    *g_tapEngines; // playback engines
static NSMutableDictionary<NSNumber *, AVAudioEngine *>    *g_capEngines; // capture engines
static NSMutableDictionary<NSNumber *, AVAudioMixerNode *> *g_tapMixers;
static NSMutableDictionary<NSNumber *, NSNumber *>         *g_tapIDs;   // tapObjectID
static NSMutableDictionary<NSNumber *, NSNumber *>         *g_tapAggs;  // aggregate deviceID
// Failed StartTapRoute attempts per pid: back off so the Dart layer's 2 s
// refresh (which re-applies persisted volumes) can't hammer tap creation.
static std::map<pid_t, std::chrono::steady_clock::time_point> g_tapFailedAt;

// ─── UTF-16 Helpers ──────────────────────────────────────────

static void CFStringToUTF16(CFStringRef str, uint16_t *dest, size_t maxChars) {
    if (!str || !dest || maxChars == 0) return;
    memset(dest, 0, maxChars * sizeof(uint16_t));
    CFIndex len = CFStringGetLength(str);
    if (len >= (CFIndex)(maxChars - 1)) len = (CFIndex)(maxChars - 1);
    CFStringGetCharacters(str, CFRangeMake(0, len), (UniChar *)dest);
}

static void CStrToUTF16(const char *str, uint16_t *dest, size_t maxChars) {
    if (!str || !dest || maxChars == 0) return;
    @autoreleasepool {
        NSString *ns = [NSString stringWithUTF8String:str];
        if (!ns) { dest[0] = 0; return; }
        CFStringToUTF16((__bridge CFStringRef)ns, dest, maxChars);
    }
}

static std::string UTF16ToStr(const uint16_t *src, size_t maxChars) {
    if (!src) return "";
    size_t len = 0;
    while (len < maxChars && src[len]) len++;
    if (!len) return "";
    @autoreleasepool {
        NSString *ns = [NSString stringWithCharacters:(const unichar *)src length:len];
        return ns ? std::string([ns UTF8String]) : "";
    }
}

// ─── Lifecycle ───────────────────────────────────────────────

static void StopAllTapRoutes();  // forward

AUDIO_API int32_t audio_init(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_initialized) return 0;
    g_tapEngines = [NSMutableDictionary new];
    g_capEngines = [NSMutableDictionary new];
    g_tapMixers  = [NSMutableDictionary new];
    g_tapIDs     = [NSMutableDictionary new];
    g_tapAggs    = [NSMutableDictionary new];
    g_initialized = true;
    return 0;
}

AUDIO_API void audio_cleanup(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    StopAllTapRoutes();
    g_pidToDevice.clear();
    g_initialized = false;
}

// ─── Device Enumeration ──────────────────────────────────────

static bool IsOutputDevice(AudioObjectID devId) {
    AudioObjectPropertyAddress addr = {
        kAudioDevicePropertyStreamConfiguration,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(devId, &addr, 0, nullptr, &size) != kAudioHardwareNoError) return false;
    if (!size) return false;
    AudioBufferList *list = (AudioBufferList *)malloc(size);
    if (!list) return false;
    OSStatus st = AudioObjectGetPropertyData(devId, &addr, 0, nullptr, &size, list);
    bool has = (st == kAudioHardwareNoError && list->mNumberBuffers > 0);
    free(list);
    return has;
}

static AudioObjectID GetDefaultOutputDevice() {
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectID id = kAudioObjectUnknown;
    UInt32 size = sizeof(id);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, nullptr, &size, &id);
    return id;
}

static float GetDevicePeakLevel(AudioObjectID devId) {
#if __MAC_OS_X_VERSION_MAX_ALLOWED < 260000
    for (UInt32 ch = 0; ch <= 2; ch++) {
        AudioObjectPropertyAddress addr = {
            kAudioDevicePropertyDevicePeakVolume,
            kAudioDevicePropertyScopeOutput, ch
        };
        Float32 peak = 0.0f;
        UInt32 size = sizeof(peak);
        if (AudioObjectGetPropertyData(devId, &addr, 0, nullptr, &size, &peak) == kAudioHardwareNoError)
            return peak;
    }
#else
    (void)devId;
#endif
    return 0.0f;
}

static float GetDeviceVolumeForId(AudioObjectID devId) {
    for (UInt32 ch = 0; ch <= 1; ch++) {
        AudioObjectPropertyAddress addr = {
            kAudioDevicePropertyVolumeScalar,
            kAudioDevicePropertyScopeOutput, ch
        };
        Float32 vol = 1.0f;
        UInt32 size = sizeof(vol);
        if (AudioObjectGetPropertyData(devId, &addr, 0, nullptr, &size, &vol) == kAudioHardwareNoError)
            return vol;
    }
    return 1.0f;
}

static std::vector<AudioDeviceInfo> EnumerateDevices() {
    std::vector<AudioDeviceInfo> result;

    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0, nullptr, &size)) return result;

    size_t count = size / sizeof(AudioObjectID);
    std::vector<AudioObjectID> ids(count);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, nullptr, &size, ids.data());

    AudioObjectID defId = GetDefaultOutputDevice();

    for (AudioObjectID devId : ids) {
        if (!IsOutputDevice(devId)) continue;

        // Skip our own tap aggregates — kAudioAggregateDeviceIsPrivateKey
        // hides them from other processes but NOT from the creating process,
        // so without this they appear (and can be routed into, creating a
        // feedback loop) in our own device picker.
        {
            bool ours = false;
            for (NSNumber *aggNum in [g_tapAggs allValues]) {
                if ((AudioObjectID)[aggNum unsignedIntValue] == devId) { ours = true; break; }
            }
            if (ours) continue;
        }

        AudioDeviceInfo info = {};
        char idStr[32];
        snprintf(idStr, sizeof(idStr), "%u", (unsigned)devId);
        CStrToUTF16(idStr, info.id, 256);
        info.is_default = (devId == defId) ? 1 : 0;
        info.is_active  = 1;
        info.volume     = GetDeviceVolumeForId(devId);

        AudioObjectPropertyAddress nameAddr = {
            kAudioObjectPropertyName,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        CFStringRef nameRef = nullptr;
        UInt32 nsize = sizeof(nameRef);
        if (AudioObjectGetPropertyData(devId, &nameAddr, 0, nullptr, &nsize, &nameRef) == kAudioHardwareNoError && nameRef) {
            CFStringToUTF16(nameRef, info.name, 256);
            CFStringToUTF16(nameRef, info.short_name, 128);
            CFRelease(nameRef);
        }
        result.push_back(info);
    }
    return result;
}

AUDIO_API int32_t audio_get_device_count(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    return (int32_t)EnumerateDevices().size();
}

AUDIO_API int32_t audio_get_devices(AudioDeviceInfo *devices, int32_t max_count) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto devs = EnumerateDevices();
    int32_t n = (int32_t)std::min(devs.size(), (size_t)max_count);
    for (int32_t i = 0; i < n; i++) devices[i] = devs[i];
    return n;
}

// ─── Process Object Helpers ──────────────────────────────────

static AudioObjectID FindProcessObject(pid_t targetPid) {
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyProcessObjectList,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0, nullptr, &size)) return kAudioObjectUnknown;
    if (!size) return kAudioObjectUnknown;

    size_t count = size / sizeof(AudioObjectID);
    std::vector<AudioObjectID> objs(count);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, nullptr, &size, objs.data());

    AudioObjectPropertyAddress pidAddr = {
        kAudioProcessPropertyPID,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    for (AudioObjectID obj : objs) {
        pid_t pid = 0;
        UInt32 ps = sizeof(pid);
        if (AudioObjectGetPropertyData(obj, &pidAddr, 0, nullptr, &ps, &pid) == kAudioHardwareNoError && pid == targetPid)
            return obj;
    }
    return kAudioObjectUnknown;
}

// ─── Session Enumeration (macOS 12+) ─────────────────────────

static std::string GetProcessDisplayName(pid_t pid) {
    @autoreleasepool {
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if (app) {
            NSString *name = app.localizedName ?: [app.executableURL lastPathComponent];
            if (name) return std::string([name UTF8String]);
        }
        char buf[PROC_NAME_LEN] = {};
        if (proc_name((int)pid, buf, sizeof(buf)) > 0 && buf[0])
            return std::string(buf);
    }
    return "Unknown";
}

static std::string FormatDisplayName(const std::string &name) {
    static const struct { const char *key; const char *display; } known[] = {
        {"spotify",         "Spotify"},
        {"discord",         "Discord"},
        {"google chrome",   "Chrome"},
        {"firefox",         "Firefox"},
        {"safari",          "Safari"},
        {"microsoft edge",  "Microsoft Edge"},
        {"vlc",             "VLC media player"},
        {"slack",           "Slack"},
        {"zoom",            "Zoom"},
        {"microsoft teams", "Microsoft Teams"},
        {"obs",             "OBS Studio"},
        {"music",           "Apple Music"},
        {"podcasts",        "Podcasts"},
        {"quicktime",       "QuickTime Player"},
        {"iina",            "IINA"},
        {nullptr, nullptr}
    };
    std::string lower = name;
    for (auto &c : lower) c = (char)tolower((unsigned char)c);
    for (int i = 0; known[i].key; i++)
        if (lower.find(known[i].key) != std::string::npos) return known[i].display;
    std::string result = name;
    if (!result.empty()) result[0] = (char)toupper((unsigned char)result[0]);
    return result;
}

static std::vector<AudioSessionInfo> EnumerateSessions() {
    std::vector<AudioSessionInfo> result;

    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyProcessObjectList,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0, nullptr, &size)) return result;
    if (!size) return result;

    size_t count = size / sizeof(AudioObjectID);
    std::vector<AudioObjectID> objs(count);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, nullptr, &size, objs.data());

    AudioObjectPropertyAddress pidAddr = {kAudioProcessPropertyPID, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioObjectPropertyAddress runAddr = {kAudioProcessPropertyIsRunningOutput, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioObjectID defDev = GetDefaultOutputDevice();

    for (AudioObjectID obj : objs) {
        pid_t pid = 0;
        UInt32 ps = sizeof(pid);
        if (AudioObjectGetPropertyData(obj, &pidAddr, 0, nullptr, &ps, &pid) != kAudioHardwareNoError) continue;
        if (pid <= 0 || pid == getpid()) continue;

        UInt32 running = 0, rs = sizeof(running);
        AudioObjectGetPropertyData(obj, &runAddr, 0, nullptr, &rs, &running);

        AudioSessionInfo info = {};
        info.process_id = (uint32_t)pid;
        info.is_active  = running ? 1 : 0;
        info.volume     = 1.0f;
        info.is_muted   = 0;

        // Volume/mute from tap mixer if we have an active route
        @autoreleasepool {
            AVAudioMixerNode *mx = g_tapMixers[@(pid)];
            if (mx) {
                info.volume   = mx.outputVolume;
                info.is_muted = (mx.outputVolume < 0.001f) ? 1 : 0;
            }
        }

        // Peak from routed device (or default)
        AudioObjectID peakDev = defDev;
        auto it = g_pidToDevice.find(pid);
        if (it != g_pidToDevice.end() && it->second != kAudioObjectUnknown)
            peakDev = it->second;
        info.peak_level = running ? GetDevicePeakLevel(peakDev) : 0.0f;

        std::string name = GetProcessDisplayName(pid);
        CStrToUTF16(name.c_str(),                    info.process_name, 256);
        CStrToUTF16(FormatDisplayName(name).c_str(), info.display_name, 256);
        result.push_back(info);
    }
    return result;
}

AUDIO_API int32_t audio_get_session_count(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    return (int32_t)EnumerateSessions().size();
}

AUDIO_API int32_t audio_get_sessions(AudioSessionInfo *sessions, int32_t max_count) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto sess = EnumerateSessions();
    int32_t n = (int32_t)std::min(sess.size(), (size_t)max_count);
    for (int32_t i = 0; i < n; i++) sessions[i] = sess[i];
    return n;
}

// ─── Tap Routing (macOS 14.2+) ───────────────────────────────

static void StopTapForPid_nolock(pid_t pid) {
    @autoreleasepool {
        NSNumber *key = @(pid);
        AVAudioEngine *cap = g_capEngines[key];
        if (cap) {
            @try { [cap.inputNode removeTapOnBus:0]; } @catch (NSException *e) {}
            [cap stop];
            [g_capEngines removeObjectForKey:key];
        }
        AVAudioEngine *eng = g_tapEngines[key];
        if (eng) { [eng stop]; [g_tapEngines removeObjectForKey:key]; }
        [g_tapMixers removeObjectForKey:key];

        NSNumber *aggNum = g_tapAggs[key];
        if (aggNum) {
            AudioHardwareDestroyAggregateDevice((AudioObjectID)[aggNum unsignedIntValue]);
            [g_tapAggs removeObjectForKey:key];
        }

        NSNumber *tapNum = g_tapIDs[key];
        if (tapNum) {
            if (@available(macOS 14.2, *)) {
                AudioHardwareDestroyProcessTap((AudioObjectID)[tapNum unsignedIntValue]);
            }
            [g_tapIDs removeObjectForKey:key];
        }
    }
}

static void StopAllTapRoutes() {
    @autoreleasepool {
        for (NSNumber *key in [g_capEngines allKeys]) {
            AVAudioEngine *cap = g_capEngines[key];
            @try { [cap.inputNode removeTapOnBus:0]; } @catch (NSException *e) {}
            [cap stop];
        }
        [g_capEngines removeAllObjects];
        for (NSNumber *key in [g_tapEngines allKeys]) {
            AVAudioEngine *eng = g_tapEngines[key];
            if (eng) [eng stop];
        }
        for (NSNumber *aggNum in [g_tapAggs allValues])
            AudioHardwareDestroyAggregateDevice((AudioObjectID)[aggNum unsignedIntValue]);
        if (@available(macOS 14.2, *)) {
            for (NSNumber *tapNum in [g_tapIDs allValues])
                AudioHardwareDestroyProcessTap((AudioObjectID)[tapNum unsignedIntValue]);
        }
        [g_tapEngines removeAllObjects];
        [g_tapMixers  removeAllObjects];
        [g_tapIDs     removeAllObjects];
        [g_tapAggs    removeAllObjects];
    }
}

// Start a CATapDescription-based route: captures processObj audio → targetDev.
// Returns 0 on success, negative on error.
static int32_t StartTapRoute(pid_t pid, AudioObjectID processObj, AudioObjectID targetDev) {
    if (@available(macOS 14.2, *)) {
        // Snapshot the existing route (if any) but do NOT stop it yet: tearing
        // the old tap down before the new one exists unmutes the process for a
        // moment, leaking a burst of audio to the default device mid-switch.
        // The old route is destroyed after the new one is running (below).
        NSNumber *pidKey = @(pid);
        AVAudioEngine *oldCap   = g_capEngines[pidKey];
        AVAudioEngine *oldPlay  = g_tapEngines[pidKey];
        NSNumber      *oldTap   = g_tapIDs[pidKey];
        NSNumber      *oldAgg   = g_tapAggs[pidKey];
        AVAudioMixerNode *oldMixer = g_tapMixers[pidKey];
        // Preserve the per-app volume across the switch — a fresh engine's
        // mixer is at 1.0, which caused an audible jump until the Dart layer
        // re-applied the persisted volume seconds later.
        float carriedVolume = oldMixer ? oldMixer.outputVolume : 1.0f;

        // Create the tap — captures this process and silences its original output.
        CATapDescription *desc = [[CATapDescription alloc]
            initStereoMixdownOfProcesses:@[@(processObj)]];
        // Silence the process's direct output while our engine reads the tap;
        // without this the app keeps playing on its original device and
        // routing appears to do nothing. (A `mutedProcesses` property was
        // used here before — it does not exist in any SDK.)
        desc.muteBehavior = CATapMutedWhenTapped;
        desc.name = [NSString stringWithFormat:@"AudioRouter-%d", (int)pid];

        AudioObjectID tapDev = 0;
        OSStatus st = AudioHardwareCreateProcessTap(desc, &tapDev);
        if (st != noErr) {
            fprintf(stderr, "[audio_backend] CreateProcessTap failed st=%d\n", (int)st);
            return (int32_t)st;
        }

        // A tap object is not a device, so no AudioUnit can read it directly.
        // Wrap it in a private TAP-ONLY aggregate: its input channels are then
        // exactly the tap's stereo mixdown. (Adding the target device as a
        // sub-device does NOT work — the sub-device's own input channels, e.g.
        // a headset microphone, take priority over the tap on the input bus.)
        NSDictionary *aggDict = @{
            @kAudioAggregateDeviceNameKey: [NSString stringWithFormat:@"SoundShift-%d", (int)pid],
            @kAudioAggregateDeviceUIDKey: [[NSUUID UUID] UUIDString],
            @kAudioAggregateDeviceIsPrivateKey: @YES,
            @kAudioAggregateDeviceTapListKey: @[
                @{ @kAudioSubTapUIDKey: [desc.UUID UUIDString],
                   @kAudioSubTapDriftCompensationKey: @YES },
            ],
            @kAudioAggregateDeviceTapAutoStartKey: @YES,
        };
        AudioObjectID aggDev = 0;
        st = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)aggDict, &aggDev);
        if (st != noErr) {
            fprintf(stderr, "[audio_backend] CreateAggregateDevice failed st=%d\n", (int)st);
            AudioHardwareDestroyProcessTap(tapDev);
            return (int32_t)st;
        }

        // Two engines: AVAudioEngine cannot span two devices in one graph, so
        // a capture engine reads the tap aggregate and hands buffers to a
        // playback engine rendering on the target device via a player node.
        Float64 sr = 0;
        UInt32 ss = sizeof(sr);
        AudioObjectPropertyAddress srAddr = {
            kAudioDevicePropertyNominalSampleRate,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        AudioObjectGetPropertyData(aggDev, &srAddr, 0, nullptr, &ss, &sr);
        if (sr < 8000) sr = 48000;
        AVAudioFormat *fmt = [[AVAudioFormat alloc]
            initStandardFormatWithSampleRate:sr channels:2];

        AVAudioEngine *capEngine  = [[AVAudioEngine alloc] init];
        AVAudioEngine *playEngine = [[AVAudioEngine alloc] init];
        AVAudioPlayerNode *player = [[AVAudioPlayerNode alloc] init];

        int32_t rc = -5;
        @try {
            AudioUnit inputUnit = capEngine.inputNode.audioUnit;
            st = AudioUnitSetProperty(inputUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0,
                &aggDev, sizeof(AudioObjectID));
            if (st != noErr) @throw [NSException exceptionWithName:@"au" reason:@"input device" userInfo:nil];

            AudioUnit outputUnit = playEngine.outputNode.audioUnit;
            st = AudioUnitSetProperty(outputUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0,
                &targetDev, sizeof(AudioObjectID));
            if (st != noErr) @throw [NSException exceptionWithName:@"au" reason:@"output device" userInfo:nil];

            [playEngine attachNode:player];
            [playEngine connect:player to:playEngine.mainMixerNode format:fmt];

            NSError *err = nil;
            [playEngine startAndReturnError:&err];
            if (err) @throw [NSException exceptionWithName:@"au" reason:@"play start" userInfo:nil];
            [player play];

            [capEngine.inputNode installTapOnBus:0 bufferSize:2048 format:fmt
                block:^(AVAudioPCMBuffer *buf, AVAudioTime *when) {
                    [player scheduleBuffer:buf completionHandler:nil];
                }];
            err = nil;
            [capEngine startAndReturnError:&err];
            if (err) {
                [capEngine.inputNode removeTapOnBus:0];
                @throw [NSException exceptionWithName:@"au" reason:@"capture start" userInfo:nil];
            }
            rc = 0;
        } @catch (NSException *ex) {
            fprintf(stderr, "[audio_backend] tap route failed: %s\n", ex.reason.UTF8String);
            [playEngine stop];
            AudioHardwareDestroyAggregateDevice(aggDev);
            AudioHardwareDestroyProcessTap(tapDev);
            return rc;
        }

        playEngine.mainMixerNode.outputVolume = carriedVolume;

        // Store — playback engine under g_tapEngines, its main mixer carries
        // per-app volume; capture engine tracked separately.
        g_capEngines[pidKey] = capEngine;
        g_tapEngines[pidKey] = playEngine;
        g_tapMixers [pidKey] = playEngine.mainMixerNode;
        g_tapIDs    [pidKey] = @(tapDev);
        g_tapAggs   [pidKey] = @(aggDev);

        // New route is live — now retire the old one. Both taps mute the
        // process during the overlap, so there is no leak to the default
        // device and at worst a few ms of doubled output on the old target.
        if (oldCap) {
            @try { [oldCap.inputNode removeTapOnBus:0]; } @catch (NSException *e) {}
            [oldCap stop];
        }
        if (oldPlay) [oldPlay stop];
        if (oldAgg) AudioHardwareDestroyAggregateDevice((AudioObjectID)[oldAgg unsignedIntValue]);
        if (oldTap) AudioHardwareDestroyProcessTap((AudioObjectID)[oldTap unsignedIntValue]);
        return 0;
    }
    return -100; // macOS < 14.2
}

// ─── Per-App Routing ─────────────────────────────────────────

AUDIO_API int32_t audio_route_process(uint32_t process_id, const uint16_t *device_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_initialized || !device_id) return -1;

    std::string idStr = UTF16ToStr(device_id, 256);
    pid_t pid = (pid_t)process_id;

    if (idStr.empty()) {
        // Reset: stop tap, restore normal audio
        StopTapForPid_nolock(pid);
        g_pidToDevice.erase(pid);
        // Best-effort: try to clear kAudioProcessPropertyDevice if available
        AudioObjectID processObj = FindProcessObject(pid);
        if (processObj != kAudioObjectUnknown) {
            AudioObjectPropertyAddress addr = {
                (AudioObjectPropertySelector)kAudioProcessPropertyDevice,
                kAudioObjectPropertyScopeGlobal,
                kAudioObjectPropertyElementMain
            };
            AudioObjectID unknown = kAudioObjectUnknown;
            AudioObjectSetPropertyData(processObj, &addr, 0, nullptr, sizeof(AudioObjectID), &unknown);
        }
        return 0;
    }

    AudioObjectID targetDev;
    try { targetDev = (AudioObjectID)std::stoul(idStr); }
    catch (...) { return -2; }

    g_pidToDevice[pid] = targetDev;

    AudioObjectID processObj = FindProcessObject(pid);

    // ── Strategy 1: CATapDescription (macOS 14.2+, real capture + redirect) ──
    if (@available(macOS 14.2, *)) {
        if (processObj != kAudioObjectUnknown) {
            int32_t r = StartTapRoute(pid, processObj, targetDev);
            if (r == 0) return 0;
            // Fall through to strategy 2 on error
        }
    }

    // ── Strategy 2: kAudioProcessPropertyDevice (macOS 14, best-effort) ──────
    if (processObj != kAudioObjectUnknown) {
        AudioObjectPropertyAddress addr = {
            (AudioObjectPropertySelector)kAudioProcessPropertyDevice,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        OSStatus st = AudioObjectSetPropertyData(processObj, &addr, 0, nullptr, sizeof(AudioObjectID), &targetDev);
        if (st == noErr) return 0;
    }

    // ── macOS 12–13: no routing possible, UI-only ─────────────────────────────
    return -3;
}

AUDIO_API int32_t audio_get_vtable_slot(void) { return -1; }

// ─── Per-App Volume (works via tap mixer on macOS 14.2+) ─────

// macOS has no per-process volume API, so volume/mute go through the tap
// engine's mixer node. If the app isn't routed yet, lazily create a tap to
// its current device (routed target or system default) so the mixer exists.
static AVAudioMixerNode *MixerForPid_nolock(pid_t pid, bool createIfMissing) {
    AVAudioMixerNode *mx = g_tapMixers[@(pid)];
    if (mx || !createIfMissing) return mx;
    if (@available(macOS 14.2, *)) {
        // Back off after a failure — the Dart refresh re-applies persisted
        // volumes every 2 s, which would otherwise retry tap creation forever.
        auto failed = g_tapFailedAt.find(pid);
        if (failed != g_tapFailedAt.end() &&
            std::chrono::steady_clock::now() - failed->second < std::chrono::seconds(30)) {
            return nil;
        }
        AudioObjectID processObj = FindProcessObject(pid);
        if (processObj == kAudioObjectUnknown) return nil;
        auto it = g_pidToDevice.find(pid);
        AudioObjectID dev = (it != g_pidToDevice.end())
            ? it->second : GetDefaultOutputDevice();
        if (dev == kAudioObjectUnknown) return nil;
        if (StartTapRoute(pid, processObj, dev) != 0) {
            g_tapFailedAt[pid] = std::chrono::steady_clock::now();
            return nil;
        }
        g_tapFailedAt.erase(pid);
        return g_tapMixers[@(pid)];
    }
    return nil;
}

AUDIO_API int32_t audio_set_volume(uint32_t process_id, float volume) {
    std::lock_guard<std::mutex> lock(g_mutex);
    float v = std::max(0.0f, std::min(1.0f, volume));
    @autoreleasepool {
        // Only spin up a tap when the volume actually deviates from unity;
        // setting 100% on an untapped app is a no-op anyway.
        AVAudioMixerNode *mx = MixerForPid_nolock((pid_t)process_id, v < 0.999f);
        if (mx) mx.outputVolume = v;
    }
    return 0;
}

AUDIO_API int32_t audio_set_mute(uint32_t process_id, int32_t muted) {
    std::lock_guard<std::mutex> lock(g_mutex);
    @autoreleasepool {
        AVAudioMixerNode *mx = MixerForPid_nolock((pid_t)process_id, muted != 0);
        if (mx) mx.outputVolume = muted ? 0.0f : 1.0f;
    }
    return 0;
}

// ─── Device Master Volume ────────────────────────────────────

static AudioObjectID DeviceFromUTF16(const uint16_t *s) {
    if (!s) return kAudioObjectUnknown;
    std::string str = UTF16ToStr(s, 256);
    if (str.empty()) return kAudioObjectUnknown;
    try { return (AudioObjectID)std::stoul(str); } catch (...) { return kAudioObjectUnknown; }
}

AUDIO_API float audio_get_device_volume(const uint16_t *device_id) {
    AudioObjectID id = DeviceFromUTF16(device_id);
    return (id == kAudioObjectUnknown) ? -1.0f : GetDeviceVolumeForId(id);
}

AUDIO_API int32_t audio_set_device_volume(const uint16_t *device_id, float volume) {
    AudioObjectID id = DeviceFromUTF16(device_id);
    if (id == kAudioObjectUnknown) return -1;
    volume = std::max(0.0f, std::min(1.0f, volume));
    for (UInt32 ch = 0; ch <= 2; ch++) {
        AudioObjectPropertyAddress addr = {kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, ch};
        Boolean settable = false;
        if (AudioObjectIsPropertySettable(id, &addr, &settable) == kAudioHardwareNoError && settable) {
            Float32 v = volume;
            if (AudioObjectSetPropertyData(id, &addr, 0, nullptr, sizeof(v), &v) == kAudioHardwareNoError)
                return 0;
        }
    }
    return -1;
}

// ─── Device Balance ──────────────────────────────────────────

AUDIO_API float audio_get_device_balance(const uint16_t *device_id) {
    AudioObjectID id = DeviceFromUTF16(device_id);
    if (id == kAudioObjectUnknown) return 0.0f;

    // Try stereo pan scalar first (single knob, -1..1 remapped from 0..1)
    AudioObjectPropertyAddress panAddr = {
        kAudioDevicePropertyStereoPanChannels,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    UInt32 panChans[2] = {0, 0};
    UInt32 sz = sizeof(panChans);
    if (AudioObjectGetPropertyData(id, &panAddr, 0, nullptr, &sz, panChans) == kAudioHardwareNoError) {
        AudioObjectPropertyAddress sp = {
            kAudioDevicePropertyStereoPan,
            kAudioDevicePropertyScopeOutput,
            kAudioObjectPropertyElementMain
        };
        Float32 pan = 0.5f;
        sz = sizeof(pan);
        AudioObjectGetPropertyData(id, &sp, 0, nullptr, &sz, &pan);
        return pan * 2.0f - 1.0f; // 0..1 → -1..1
    }

    // Fallback: per-channel volumes (ch 1 = left, ch 2 = right)
    Float32 left = 1.0f, right = 1.0f;
    AudioObjectPropertyAddress addrL = {kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, 1};
    AudioObjectPropertyAddress addrR = {kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, 2};
    sz = sizeof(Float32);
    AudioObjectGetPropertyData(id, &addrL, 0, nullptr, &sz, &left);
    AudioObjectGetPropertyData(id, &addrR, 0, nullptr, &sz, &right);
    float sum = left + right;
    if (sum < 0.001f) return 0.0f;
    return (right - left) / sum;
}

AUDIO_API int32_t audio_set_device_balance(const uint16_t *device_id, float balance) {
    AudioObjectID id = DeviceFromUTF16(device_id);
    if (id == kAudioObjectUnknown) return -1;
    balance = std::max(-1.0f, std::min(1.0f, balance));

    // Try stereo pan scalar (0..1)
    AudioObjectPropertyAddress panAddr = {
        kAudioDevicePropertyStereoPan,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    Boolean settable = false;
    if (AudioObjectIsPropertySettable(id, &panAddr, &settable) == kAudioHardwareNoError && settable) {
        Float32 pan = (balance + 1.0f) / 2.0f;
        if (AudioObjectSetPropertyData(id, &panAddr, 0, nullptr, sizeof(pan), &pan) == kAudioHardwareNoError)
            return 0;
    }

    // Fallback: per-channel volume scaling
    Float32 master = GetDeviceVolumeForId(id);
    if (master < 0.0f) master = 1.0f;
    Float32 left  = (balance <= 0.0f) ? master : master * (1.0f - balance);
    Float32 right = (balance >= 0.0f) ? master : master * (1.0f + balance);

    AudioObjectPropertyAddress addrL = {kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, 1};
    AudioObjectPropertyAddress addrR = {kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, 2};
    Boolean setL = false, setR = false;
    AudioObjectIsPropertySettable(id, &addrL, &setL);
    AudioObjectIsPropertySettable(id, &addrR, &setR);
    if (setL && setR) {
        AudioObjectSetPropertyData(id, &addrL, 0, nullptr, sizeof(Float32), &left);
        AudioObjectSetPropertyData(id, &addrR, 0, nullptr, sizeof(Float32), &right);
        return 0;
    }
    return -1;
}

// ─── Set Default Output Device ───────────────────────────────

AUDIO_API int32_t audio_set_default_device(const uint16_t *device_id) {
    AudioObjectID id = DeviceFromUTF16(device_id);
    if (id == kAudioObjectUnknown) return -1;
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    OSStatus st = AudioObjectSetPropertyData(
        kAudioObjectSystemObject, &addr, 0, nullptr, sizeof(AudioObjectID), &id);
    return (st == kAudioHardwareNoError) ? 0 : (int32_t)st;
}

// ─── App Icon ───────────────────────────────────────────────

AUDIO_API int32_t audio_get_app_icon(uint32_t pid, uint8_t *rgba_buf, int32_t buf_size,
                                     int32_t *out_width, int32_t *out_height) {
    if (!out_width || !out_height) return -1;
    const int W = 32, H = 32;
    *out_width = W; *out_height = H;
    const int needed = W * H * 4;
    if (!rgba_buf || buf_size < needed) return needed;

    @autoreleasepool {
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:(pid_t)pid];
        if (!app) return -2;
        NSImage *icon = app.icon;
        if (!icon) return -3;

        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        if (!cs) return -4;
        CGContextRef cg = CGBitmapContextCreate(rgba_buf, W, H, 8, W * 4, cs,
            kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(cs);
        if (!cg) return -5;

        CGContextClearRect(cg, CGRectMake(0, 0, W, H));
        CGContextTranslateCTM(cg, 0, H);
        CGContextScaleCTM(cg, 1.0, -1.0);

        NSGraphicsContext *nsCtx = [NSGraphicsContext graphicsContextWithCGContext:cg flipped:NO];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:nsCtx];
        [icon drawInRect:NSMakeRect(0, 0, W, H) fromRect:NSZeroRect
               operation:NSCompositingOperationSourceOver fraction:1.0];
        [NSGraphicsContext restoreGraphicsState];
        CGContextRelease(cg);
        return 0;
    }
}

// ─── Auto-Start (LaunchAgent) ─────────────────────────────────

static NSString *LaunchAgentPath() {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/LaunchAgents/com.audiotouter.AudioRouter.plist"];
}

AUDIO_API int32_t audio_set_autostart(int32_t enabled) {
    NSString *path = LaunchAgentPath();
    if (!enabled) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return 0;
    }
    NSString *exe = NSBundle.mainBundle.executablePath;
    if (!exe) return -1;
    NSDictionary *plist = @{
        @"Label":            @"com.audiotouter.AudioRouter",
        @"ProgramArguments": @[exe],
        @"RunAtLoad":        @YES,
        @"KeepAlive":        @NO,
    };
    NSString *dir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSError *err = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
        format:NSPropertyListXMLFormat_v1_0 options:0 error:&err];
    if (!data || err) return -2;
    return [data writeToFile:path atomically:YES] ? 0 : -3;
}

AUDIO_API int32_t audio_get_autostart(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:LaunchAgentPath()] ? 1 : 0;
}

// ─── Global Hotkeys (Carbon) ──────────────────────────────────

struct HotkeyEntry { int32_t id; EventHotKeyRef ref; };
static std::vector<HotkeyEntry> g_hotkeys;
static std::queue<int32_t>      g_hotkeyQueue;
static std::mutex               g_hotkeyMutex;
static EventHandlerRef          g_hotkeyHandler = nullptr;

static const uint16_t kMacKeyCodes[10] = {29,18,19,20,21,23,22,26,28,25};

static uint16_t VKToMac(uint32_t vk) {
    return (vk >= 0x30 && vk <= 0x39) ? kMacKeyCodes[vk - 0x30] : (uint16_t)(vk & 0xFF);
}
static UInt32 WinToMacMods(uint32_t m) {
    return ((m & 1) ? (UInt32)optionKey : 0) | ((m & 2) ? (UInt32)controlKey : 0) |
           ((m & 4) ? (UInt32)shiftKey  : 0) | ((m & 8) ? (UInt32)cmdKey     : 0);
}

static OSStatus HotkeyHandler(EventHandlerCallRef, EventRef event, void *) {
    EventHotKeyID hkid = {};
    GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, nullptr, sizeof(hkid), nullptr, &hkid);
    std::lock_guard<std::mutex> lock(g_hotkeyMutex);
    g_hotkeyQueue.push((int32_t)hkid.id);
    return noErr;
}

static void EnsureHotkeyHandler() {
    if (g_hotkeyHandler) return;
    EventTypeSpec spec = {kEventClassKeyboard, kEventHotKeyPressed};
    InstallApplicationEventHandler(HotkeyHandler, 1, &spec, nullptr, &g_hotkeyHandler);
}

AUDIO_API int32_t audio_register_hotkey(int32_t id, uint32_t modifiers, uint32_t vk) {
    EnsureHotkeyHandler();
    EventHotKeyID hkid = {'AuRo', (UInt32)id};
    EventHotKeyRef ref = nullptr;
    OSStatus st = RegisterEventHotKey(VKToMac(vk), WinToMacMods(modifiers), hkid,
                                      GetApplicationEventTarget(), 0, &ref);
    if (st == noErr) { std::lock_guard<std::mutex> lock(g_hotkeyMutex); g_hotkeys.push_back({id, ref}); }
    return (int32_t)st;
}

AUDIO_API int32_t audio_unregister_hotkey(int32_t id) {
    std::lock_guard<std::mutex> lock(g_hotkeyMutex);
    for (auto it = g_hotkeys.begin(); it != g_hotkeys.end(); ++it)
        if (it->id == id) { UnregisterEventHotKey(it->ref); g_hotkeys.erase(it); return 0; }
    return 0;
}

AUDIO_API int32_t audio_poll_hotkey(void) {
    std::lock_guard<std::mutex> lock(g_hotkeyMutex);
    if (g_hotkeyQueue.empty()) return 0;
    int32_t id = g_hotkeyQueue.front(); g_hotkeyQueue.pop();
    return id;
}

// ─── Peak Levels ─────────────────────────────────────────────
// On macOS, CoreAudio's kAudioDevicePropertyCurrentDevicePeakHold does not
// reset on read (unlike WASAPI GetPeakValue), so calling it from both
// audio_get_sessions and audio_poll_peaks is safe — no double-consumption bug.

AUDIO_API int32_t audio_poll_peaks(PeakLevelInfo* peaks, int32_t max_count) {
    if (!peaks || max_count <= 0) return 0;
    std::lock_guard<std::mutex> lock(g_mutex);

    auto sessions = EnumerateSessions();
    int32_t count = 0;
    for (const auto& s : sessions) {
        if (count >= max_count) break;
        peaks[count].process_id = s.process_id;
        peaks[count].peak_level = s.peak_level;
        ++count;
    }
    return count;
}

// ─── Loopback Mirror (stubs — macOS routes per-process via CATap) ────────────
// On macOS 14.2+, CATapDescription already captures a single process and
// redirects it to any output device. True device-level mirroring via loopback
// is a Windows/WASAPI concept and has no direct CoreAudio equivalent.
// These stubs let the Dart layer call the same API on both platforms without
// conditional compilation.

AUDIO_API int32_t audio_start_mirror(const uint16_t* source_device_id,
                                     const uint16_t* target_device_id) {
    (void)source_device_id; (void)target_device_id;
    return 0; // no-op on macOS
}

AUDIO_API int32_t audio_stop_mirror(const uint16_t* source_device_id,
                                    const uint16_t* target_device_id) {
    (void)source_device_id; (void)target_device_id;
    return 0; // no-op on macOS
}

AUDIO_API void audio_stop_all_mirrors(void) {
    // no-op on macOS
}

// ─── OS Integration ──────────────────────────────────────────

AUDIO_API int32_t audio_open_sound_settings(void) {
    NSURL *url = [NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.sound"];
    return [[NSWorkspace sharedWorkspace] openURL:url] ? 0 : -1;
}

AUDIO_API uint32_t audio_get_accent_color(void) {
    if (@available(macOS 10.14, *)) {
        __block uint32_t argb = 0;
        void (^read)(void) = ^{
            NSColor *accent = [[NSColor controlAccentColor]
                colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
            if (accent) {
                uint32_t r = (uint32_t)lround(accent.redComponent   * 255.0);
                uint32_t g = (uint32_t)lround(accent.greenComponent * 255.0);
                uint32_t b = (uint32_t)lround(accent.blueComponent  * 255.0);
                argb = 0xFF000000u | (r << 16) | (g << 8) | b;
            }
        };
        if ([NSThread isMainThread]) read();
        else dispatch_sync(dispatch_get_main_queue(), read);
        return argb;
    }
    return 0;
}
