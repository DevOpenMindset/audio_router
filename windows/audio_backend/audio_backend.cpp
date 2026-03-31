// audio_backend.cpp — Native C++ audio backend for AudioRouter
//
// Uses COM/WASAPI to enumerate devices, sessions, peak levels,
// and route per-app audio. Compiled as a DLL loaded by Dart via FFI.

#include "audio_backend.h"

#include <windows.h>
#include <mmdeviceapi.h>
#include <audiopolicy.h>
#include <endpointvolume.h>
#include <functiondiscoverykeys_devpkey.h>
#include <psapi.h>
#include <tlhelp32.h>
#include <shellapi.h>

#pragma comment(lib, "Shell32.lib")
#include <propvarutil.h>
#include <inspectable.h>
#include <eventtoken.h>
#include <winstring.h>
#include <roapi.h>

#include <string>
#include <map>
#include <vector>
#include <set>
#include <mutex>
#include <thread>
#include <atomic>

#ifndef AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM
#define AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM 0x80000000
#endif
#ifndef AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY
#define AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY 0x08000000
#endif

#pragma comment(lib, "runtimeobject.lib")

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "propsys.lib")

// ─── Internal State ──────────────────────────────────────────

static bool g_initialized = false;
static IMMDeviceEnumerator* g_enumerator = nullptr;
static std::mutex g_mutex;

// Per-app routed device: pid → raw device ID (same format as IMMDevice::GetId).
// Empty string means "default device" (no explicit route).
static std::map<DWORD, std::wstring> g_pidToDeviceId;

// Cached device-level peak meter handles: device ID string → IAudioMeterInformation*.
// Obtained via IMMDevice::Activate(IAudioMeterInformation) — the only reliable WASAPI
// path to peak data. Created during session enumeration, read by audio_poll_peaks.
static std::map<std::wstring, IAudioMeterInformation*> g_deviceMeterCache;

// Maps Windows PID → device ID string for fast peak lookup in audio_poll_peaks.
// Rebuilt every time audio_get_sessions enumerates sessions.
static std::map<DWORD, std::wstring> g_sessionDeviceMap;

// ─── Helpers ─────────────────────────────────────────────────

static std::wstring GetProcessNameFromPid(DWORD pid) {
    if (pid == 0) return L"System";

    HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!hProcess) return L"Unknown";

    wchar_t path[MAX_PATH] = {};
    DWORD size = MAX_PATH;
    std::wstring name = L"Unknown";

    if (QueryFullProcessImageNameW(hProcess, 0, path, &size)) {
        std::wstring fullPath(path);
        auto lastSlash = fullPath.find_last_of(L'\\');
        auto lastDot = fullPath.find_last_of(L'.');
        if (lastSlash != std::wstring::npos && lastDot != std::wstring::npos && lastDot > lastSlash) {
            name = fullPath.substr(lastSlash + 1, lastDot - lastSlash - 1);
        } else if (lastSlash != std::wstring::npos) {
            name = fullPath.substr(lastSlash + 1);
        }
    }

    CloseHandle(hProcess);
    return name;
}

static std::wstring FormatDisplayName(const std::wstring& processName) {
    std::wstring lower = processName;
    for (auto& c : lower) c = towlower(c);

    struct { const wchar_t* key; const wchar_t* display; } known[] = {
        {L"spotify", L"Spotify"}, {L"discord", L"Discord"},
        {L"chrome", L"Chrome"}, {L"firefox", L"Firefox"},
        {L"msedge", L"Microsoft Edge"}, {L"brave", L"Brave"},
        {L"teams", L"Microsoft Teams"}, {L"slack", L"Slack"},
        {L"vlc", L"VLC media player"}, {L"foobar2000", L"foobar2000"},
        {L"obs64", L"OBS Studio"}, {L"obs32", L"OBS Studio"},
    };

    for (const auto& entry : known) {
        if (lower.find(entry.key) != std::wstring::npos)
            return entry.display;
    }

    // Capitalize first letter
    std::wstring result = processName;
    if (!result.empty()) result[0] = towupper(result[0]);
    return result;
}

static void SafeCopyWString(wchar_t* dest, size_t destSize, const std::wstring& src) {
    wcsncpy_s(dest, destSize, src.c_str(), _TRUNCATE);
}

// ─── Lifecycle ───────────────────────────────────────────────

AUDIO_API int32_t audio_init(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_initialized) return 0;

    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) return hr;

    hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator), nullptr,
        CLSCTX_ALL, IID_PPV_ARGS(&g_enumerator)
    );
    if (FAILED(hr)) return hr;

    g_initialized = true;
    return 0;
}

AUDIO_API void audio_cleanup(void) {
    audio_stop_all_mirrors(); // stop mirror threads before acquiring g_mutex
    std::lock_guard<std::mutex> lock(g_mutex);
    // Release cached device peak meters
    for (auto& pair : g_deviceMeterCache) {
        if (pair.second) pair.second->Release();
    }
    g_deviceMeterCache.clear();
    g_sessionDeviceMap.clear();
    if (g_enumerator) {
        g_enumerator->Release();
        g_enumerator = nullptr;
    }
    CoUninitialize();
    g_initialized = false;
}

// ─── Device Enumeration ──────────────────────────────────────

static std::vector<AudioDeviceInfo> EnumerateDevices() {
    std::vector<AudioDeviceInfo> result;
    if (!g_enumerator) return result;

    // Get default device ID
    std::wstring defaultId;
    {
        IMMDevice* pDefault = nullptr;
        HRESULT hr = g_enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &pDefault);
        if (SUCCEEDED(hr) && pDefault) {
            LPWSTR id = nullptr;
            pDefault->GetId(&id);
            if (id) {
                defaultId = id;
                CoTaskMemFree(id);
            }
            pDefault->Release();
        }
    }

    // Enumerate render endpoints
    IMMDeviceCollection* pCollection = nullptr;
    HRESULT hr = g_enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &pCollection);
    if (FAILED(hr) || !pCollection) return result;

    UINT count = 0;
    pCollection->GetCount(&count);

    for (UINT i = 0; i < count; i++) {
        IMMDevice* pDevice = nullptr;
        if (FAILED(pCollection->Item(i, &pDevice))) continue;

        AudioDeviceInfo info = {};
        info.is_active = 1;

        // Get device ID
        LPWSTR id = nullptr;
        pDevice->GetId(&id);
        if (id) {
            SafeCopyWString(info.id, 256, id);
            info.is_default = (defaultId == id) ? 1 : 0;
            CoTaskMemFree(id);
        }

        // Get friendly name from property store
        IPropertyStore* pProps = nullptr;
        if (SUCCEEDED(pDevice->OpenPropertyStore(STGM_READ, &pProps))) {
            PROPVARIANT varName;
            PropVariantInit(&varName);
            if (SUCCEEDED(pProps->GetValue(PKEY_Device_FriendlyName, &varName))) {
                if (varName.vt == VT_LPWSTR && varName.pwszVal) {
                    std::wstring fullName(varName.pwszVal);
                    SafeCopyWString(info.name, 256, fullName);

                    // Extract short name (before parentheses)
                    auto paren = fullName.find(L'(');
                    if (paren != std::wstring::npos && paren > 0) {
                        std::wstring shortName = fullName.substr(0, paren);
                        // Trim trailing spaces
                        while (!shortName.empty() && shortName.back() == L' ')
                            shortName.pop_back();
                        SafeCopyWString(info.short_name, 128, shortName);
                    } else {
                        SafeCopyWString(info.short_name, 128, fullName);
                    }
                }
                PropVariantClear(&varName);
            }
            pProps->Release();
        }

        // Get master volume via IAudioEndpointVolume
        info.volume = 1.0f;
        IAudioEndpointVolume* pEndpointVol = nullptr;
        if (SUCCEEDED(pDevice->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL,
                                        nullptr, reinterpret_cast<void**>(&pEndpointVol))) && pEndpointVol) {
            pEndpointVol->GetMasterVolumeLevelScalar(&info.volume);
            pEndpointVol->Release();
        }

        pDevice->Release();
        result.push_back(info);
    }

    pCollection->Release();
    return result;
}

AUDIO_API int32_t audio_get_device_count(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto devices = EnumerateDevices();
    return static_cast<int32_t>(devices.size());
}

AUDIO_API int32_t audio_get_devices(AudioDeviceInfo* devices, int32_t max_count) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto devs = EnumerateDevices();
    int32_t count = static_cast<int32_t>(devs.size());
    if (count > max_count) count = max_count;
    for (int32_t i = 0; i < count; i++) {
        devices[i] = devs[i];
    }
    return count;
}

// ─── Session Enumeration ─────────────────────────────────────

static void CollectSessionsFromDevice(IMMDevice* pDevice, std::set<DWORD>& seenPids,
                                      std::vector<AudioSessionInfo>& result) {
    IAudioSessionManager2* pManager = nullptr;
    HRESULT hr = pDevice->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL, nullptr,
                                   reinterpret_cast<void**>(&pManager));
    if (FAILED(hr) || !pManager) return;

    IAudioSessionEnumerator* pEnum = nullptr;
    hr = pManager->GetSessionEnumerator(&pEnum);
    if (FAILED(hr) || !pEnum) {
        pManager->Release();
        return;
    }

    int sessionCount = 0;
    pEnum->GetCount(&sessionCount);

    // Ensure a cached device-level peak meter exists for this device.
    // We do NOT call GetPeakValue here — that is done exclusively by audio_poll_peaks
    // every 33ms so that the peak accumulation window is never split between callers.
    std::wstring deviceId;
    {
        LPWSTR pwszId = nullptr;
        if (SUCCEEDED(pDevice->GetId(&pwszId)) && pwszId) {
            deviceId = pwszId;
            CoTaskMemFree(pwszId);
        }
    }
    if (!deviceId.empty() && g_deviceMeterCache.find(deviceId) == g_deviceMeterCache.end()) {
        IAudioMeterInformation* pMeter = nullptr;
        if (SUCCEEDED(pDevice->Activate(__uuidof(IAudioMeterInformation), CLSCTX_ALL,
                                        nullptr, reinterpret_cast<void**>(&pMeter))) && pMeter) {
            g_deviceMeterCache[deviceId] = pMeter;
        }
    }

    for (int i = 0; i < sessionCount; i++) {
        IAudioSessionControl* pControl = nullptr;
        if (FAILED(pEnum->GetSession(i, &pControl))) continue;

        IAudioSessionControl2* pControl2 = nullptr;
        hr = pControl->QueryInterface(__uuidof(IAudioSessionControl2),
                                      reinterpret_cast<void**>(&pControl2));
        if (FAILED(hr) || !pControl2) {
            pControl->Release();
            continue;
        }

        DWORD pid = 0;
        pControl2->GetProcessId(&pid);

        if (pid == 0 || seenPids.count(pid)) {
            // System sounds or already collected from another device
            pControl2->Release();
            pControl->Release();
            continue;
        }
        seenPids.insert(pid);

        AudioSessionInfo info = {};
        info.process_id = pid;

        std::wstring procName = GetProcessNameFromPid(pid);

        // Skip protected / system processes — routing or muting them could
        // break system audio or OS stability.
        {
            std::wstring lower = procName;
            for (auto& c : lower) c = towlower(c);
            static const wchar_t* kSysBlocklist[] = {
                L"unknown", L"system", L"svchost", L"audiodg", L"dwm",
                L"csrss", L"winlogon", L"services", L"lsass", L"smss",
                L"wininit", L"fontdrvhost", L"sihost", L"ctfmon",
                L"rundll32", L"taskhostw", L"backgroundtaskhost",
                L"searchhost", L"searchindexer",
                // Hide ourselves — mirror render threads register audio_router
                // as an audio session on the target device.
                L"audio_router", nullptr
            };
            bool blocked = false;
            for (int bi = 0; kSysBlocklist[bi]; bi++) {
                if (lower == kSysBlocklist[bi]) { blocked = true; break; }
            }
            if (blocked) {
                pControl2->Release();
                pControl->Release();
                continue;
            }
        }

        SafeCopyWString(info.process_name, 256, procName);
        SafeCopyWString(info.display_name, 256, FormatDisplayName(procName));

        AudioSessionState state;
        pControl->GetState(&state);
        // Show Active and Inactive sessions (app open but silent is still routable).
        // Only exclude Expired sessions (stream fully closed).
        if (state == AudioSessionStateExpired) {
            pControl2->Release();
            pControl->Release();
            continue;
        }
        info.is_active = (state == AudioSessionStateActive) ? 1 : 0;

        info.peak_level = 0.0f;          // Peaks are provided by audio_poll_peaks, not here
        g_sessionDeviceMap[pid] = deviceId; // Track which device this session lives on

        info.volume = 1.0f;
        info.is_muted = 0;
        ISimpleAudioVolume* pVolume = nullptr;
        if (SUCCEEDED(pControl->QueryInterface(__uuidof(ISimpleAudioVolume),
                                               reinterpret_cast<void**>(&pVolume))) && pVolume) {
            pVolume->GetMasterVolume(&info.volume);
            BOOL muted = FALSE;
            pVolume->GetMute(&muted);
            info.is_muted = muted ? 1 : 0;
            pVolume->Release();
        }

        pControl2->Release();
        pControl->Release();
        result.push_back(info);
    }

    pEnum->Release();
    pManager->Release();
}

static std::vector<AudioSessionInfo> EnumerateSessions() {
    std::vector<AudioSessionInfo> result;
    if (!g_enumerator) return result;

    // Rebuild pid→device map from scratch on every enumeration.
    g_sessionDeviceMap.clear();

    // Scan ALL active render devices, not just the default.
    // Apps routed to non-default devices would be invisible otherwise.
    IMMDeviceCollection* pCollection = nullptr;
    HRESULT hr = g_enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &pCollection);
    if (FAILED(hr) || !pCollection) return result;

    UINT deviceCount = 0;
    pCollection->GetCount(&deviceCount);

    std::set<DWORD> seenPids; // deduplicate across devices

    for (UINT d = 0; d < deviceCount; d++) {
        IMMDevice* pDevice = nullptr;
        if (FAILED(pCollection->Item(d, &pDevice))) continue;
        CollectSessionsFromDevice(pDevice, seenPids, result);
        pDevice->Release();
    }

    pCollection->Release();
    return result;
}

AUDIO_API int32_t audio_get_session_count(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto sessions = EnumerateSessions();
    return static_cast<int32_t>(sessions.size());
}

AUDIO_API int32_t audio_get_sessions(AudioSessionInfo* sessions, int32_t max_count) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto sess = EnumerateSessions();
    int32_t count = static_cast<int32_t>(sess.size());
    if (count > max_count) count = max_count;
    for (int32_t i = 0; i < count; i++) {
        sessions[i] = sess[i];
    }

    return count;
}

// ─── Peak Level Poll ─────────────────────────────────────────
//
// Reads the current device-level peak for every known session WITHOUT
// re-enumerating WASAPI sessions.  Called every 33 ms from Dart; calling
// audio_get_sessions at that rate would (a) be expensive and (b) reset the
// IAudioMeterInformation accumulator before audio_poll_peaks could read it.

AUDIO_API int32_t audio_poll_peaks(PeakLevelInfo* peaks, int32_t max_count) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_initialized || !peaks || max_count <= 0) return 0;

    // Read the fresh peak for every cached device meter.
    std::map<std::wstring, float> devicePeaks;
    for (auto it = g_deviceMeterCache.begin(); it != g_deviceMeterCache.end(); ) {
        float peak = 0.0f;
        if (it->second && SUCCEEDED(it->second->GetPeakValue(&peak))) {
            devicePeaks[it->first] = peak;
            ++it;
        } else {
            // Stale handle — release and remove.
            if (it->second) it->second->Release();
            it = g_deviceMeterCache.erase(it);
        }
    }

    // Map device peaks → session PIDs.
    int32_t count = 0;
    for (const auto& kv : g_sessionDeviceMap) {
        if (count >= max_count) break;
        auto devIt = devicePeaks.find(kv.second);
        peaks[count].process_id = kv.first;
        peaks[count].peak_level = (devIt != devicePeaks.end()) ? devIt->second : 0.0f;
        ++count;
    }
    return count;
}

// ─── Per-App Routing ─────────────────────────────────────────
//
// Based on EarTrumpet's open-source implementation:
// https://github.com/File-New-Project/EarTrumpet
//
// On Windows 11 21H2+ the correct approach is:
//   RoGetActivationFactory("Windows.Media.Internal.AudioPolicyConfig",
//                          IID={ab3d4648-e242-459f-b02f-541c70306324})
// The interface (IAudioPolicyConfigFactoryVariantFor21H2) inherits IInspectable and
// has 19 placeholder methods before SetPersistedDefaultAudioEndpoint:
//   IUnknown[0-2] + IInspectable[3-5] + 19 placeholders[6-24]
//   → SetPersistedDefaultAudioEndpoint at vtable slot 25
//   → GetPersistedDefaultAudioEndpoint at vtable slot 26
//
// On older Windows (pre-21H2) the IID is {2A59116D-...} (same slot layout).
//
// The device ID passed to SetPersisted must be formatted as:
//   "\\?\SWD#MMDEVAPI#{raw_device_id}#{e6327cad-dcec-4949-ae8a-991e976a79d2}"

// IID for Windows 11 21H2+ AudioPolicyConfig (IAudioPolicyConfigFactoryVariantFor21H2)
// Source: EarTrumpet open source, IAudioPolicyConfigFactoryVariantFor21H2.cs
static const IID IID_AudioPolicyConfig21H2 = {
    0xab3d4648, 0xe242, 0x459f,
    {0xb0, 0x2f, 0x54, 0x1c, 0x70, 0x30, 0x63, 0x24}
};

// IID for older Windows AudioPolicyConfig (IAudioPolicyConfigFactoryVariantForDownlevel)
static const IID IID_AudioPolicyConfigDownlevel = {
    0x2A59116D, 0x6C4F, 0x45E0,
    {0xA7, 0x4F, 0x70, 0x7E, 0x3F, 0xEF, 0x92, 0x58}
};

// CLSID for CPolicyConfigClient — always registered in AudioSes.dll
static const CLSID CLSID_PolicyConfigClient = {
    0x870AF99C, 0x171D, 0x4F9E,
    {0xAF, 0x0D, 0xE6, 0x3D, 0xF4, 0x0C, 0x2B, 0xC9}
};

// Both interface variants (21H2 and downlevel) share the same vtable layout:
//   IUnknown[0-2] + IInspectable[3-5] + 19 placeholder methods[6-24]
//   → SetPersistedDefaultAudioEndpoint at slot 25
//   → GetPersistedDefaultAudioEndpoint at slot 26
// No runtime detection needed — these offsets are fixed by the interface definition.
static const int kSetPersistedSlot = 25;

typedef HRESULT(STDMETHODCALLTYPE* FnSetPersisted)(
    void* pThis, UINT processId, int flow, int role, HSTRING deviceId);

static HRESULT SafeSetPersisted(void* pObj, UINT pid, int flow, int role, HSTRING hDevId) {
    void** vtable = *reinterpret_cast<void***>(pObj);
    FnSetPersisted fn = reinterpret_cast<FnSetPersisted>(vtable[kSetPersistedSlot]);
    __try {
        return fn(pObj, pid, flow, role, hDevId);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return E_FAIL;
    }
}

// Format raw IMMDevice ID for SetPersistedDefaultAudioEndpoint.
// EarTrumpet wraps it as: \\?\SWD#MMDEVAPI#{raw_id}#{e6327cad-dcec-4949-ae8a-991e976a79d2}
static std::wstring FormatDeviceIdForRouting(const wchar_t* rawId) {
    return std::wstring(L"\\\\?\\SWD#MMDEVAPI#")
         + rawId
         + L"#{e6327cad-dcec-4949-ae8a-991e976a79d2}";
}

AUDIO_API int32_t audio_route_process(uint32_t pid, const wchar_t* device_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_initialized || !device_id) return E_FAIL;

    wchar_t dbg[768];

    // Track which device this PID is routed to (used by FindVolumeForPid).
    if (device_id[0] != L'\0') {
        g_pidToDeviceId[pid] = device_id; // raw device ID
    } else {
        g_pidToDeviceId.erase(pid); // reset to default
    }

    // Build the correctly formatted device ID string.
    // Empty device_id means "reset to default" — pass null HSTRING (EarTrumpet behaviour).
    HSTRING hDeviceId = nullptr;
    std::wstring formattedId;
    if (device_id[0] != L'\0') {
        formattedId = FormatDeviceIdForRouting(device_id);
        WindowsCreateString(formattedId.c_str(), static_cast<UINT32>(formattedId.size()), &hDeviceId);
    }

    void* pFactory = nullptr;
    HRESULT hr = E_FAIL;

    // ── Strategy 1: RoGetActivationFactory (Windows 11 21H2+) ───────────────
    // EarTrumpet: AudioPolicyConfigFactoryImplFor21H2 uses this activation class.
    {
        HSTRING hClass = nullptr;
        static const wchar_t* kClass = L"Windows.Media.Internal.AudioPolicyConfig";
        WindowsCreateString(kClass, static_cast<UINT32>(wcslen(kClass)), &hClass);
        hr = RoGetActivationFactory(hClass, IID_AudioPolicyConfig21H2, &pFactory);
        WindowsDeleteString(hClass);
        swprintf_s(dbg, 768, L"AudioRouter: RoActivate hr=0x%08X factory=%p\n",
                   (unsigned)hr, pFactory);
        OutputDebugStringW(dbg);
    }

    // ── Strategy 2: CoCreateInstance(CPolicyConfigClient, downlevel IID) ────
    if (FAILED(hr) || !pFactory) {
        hr = CoCreateInstance(CLSID_PolicyConfigClient, nullptr, CLSCTX_ALL,
                              IID_AudioPolicyConfigDownlevel, &pFactory);
        swprintf_s(dbg, 768, L"AudioRouter: CoCreate(downlevel) hr=0x%08X factory=%p\n",
                   (unsigned)hr, pFactory);
        OutputDebugStringW(dbg);
    }

    // ── Strategy 3: CoCreateInstance(CPolicyConfigClient, 21H2 IID) ─────────
    if (FAILED(hr) || !pFactory) {
        hr = CoCreateInstance(CLSID_PolicyConfigClient, nullptr, CLSCTX_ALL,
                              IID_AudioPolicyConfig21H2, &pFactory);
        swprintf_s(dbg, 768, L"AudioRouter: CoCreate(21H2 IID) hr=0x%08X factory=%p\n",
                   (unsigned)hr, pFactory);
        OutputDebugStringW(dbg);
    }

    if (SUCCEEDED(hr) && pFactory) {
        // SetPersistedDefaultAudioEndpoint for eConsole and eMultimedia roles
        // (matching EarTrumpet's AudioPolicyConfig.SetDefaultEndPoint)
        HRESULT hr1 = SafeSetPersisted(pFactory, pid, eRender, eConsole,    hDeviceId);
        HRESULT hr2 = SafeSetPersisted(pFactory, pid, eRender, eMultimedia,  hDeviceId);

        swprintf_s(dbg, 768,
            L"AudioRouter: SetPersisted(slot=%d) pid=%u hr1=0x%08X hr2=0x%08X dev=%s\n",
            kSetPersistedSlot, pid, (unsigned)hr1, (unsigned)hr2, formattedId.c_str());
        OutputDebugStringW(dbg);

        ((IUnknown*)pFactory)->Release();
        WindowsDeleteString(hDeviceId);
        return (SUCCEEDED(hr1) && SUCCEEDED(hr2)) ? S_OK : (FAILED(hr1) ? hr1 : hr2);
    }

    WindowsDeleteString(hDeviceId);
    OutputDebugStringW(L"AudioRouter: all COM strategies failed, registry fallback\n");

    // ── Registry fallback (only affects new sessions, not live ones) ─────────
    wchar_t processName[MAX_PATH] = {};
    wchar_t* fileName = nullptr;
    HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (hProcess) {
        DWORD size = MAX_PATH;
        if (QueryFullProcessImageNameW(hProcess, 0, processName, &size)) {
            fileName = wcsrchr(processName, L'\\');
            if (fileName) fileName++;
            else fileName = processName;
        }
        CloseHandle(hProcess);
    }
    if (!fileName) return E_FAIL;

    HKEY hKey = nullptr;
    wchar_t keyPath[512];
    swprintf_s(keyPath, 512,
               L"Software\\Microsoft\\Multimedia\\Audio\\DeviceProperties\\%ws", fileName);
    if (RegOpenKeyExW(HKEY_CURRENT_USER, keyPath, 0, KEY_WRITE, &hKey) != ERROR_SUCCESS) {
        RegCreateKeyExW(HKEY_CURRENT_USER, keyPath, 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hKey, nullptr);
    }
    HRESULT regHr = E_FAIL;
    if (hKey) {
        DWORD sz = (DWORD)(wcslen(device_id) + 1) * sizeof(wchar_t);
        if (RegSetValueExW(hKey, L"{1.0.0.0}", 0, REG_SZ,
                           (const BYTE*)device_id, sz) == ERROR_SUCCESS) {
            SendMessageW(HWND_BROADCAST, WM_SETTINGCHANGE, 0, (LPARAM)L"Audio");
            regHr = 0x00000001;
        }
        RegCloseKey(hKey);
    }
    return regHr;
}

// Returns 25 (hardcoded vtable slot for SetPersistedDefaultAudioEndpoint).
// Kept for Dart-side logging compatibility.
AUDIO_API int32_t audio_get_vtable_slot(void) {
    return kSetPersistedSlot;
}

// ─── Per-App Volume ─────────────────────────────────────────

// Helper: find ISimpleAudioVolume for a given PID on a specific IMMDevice.
static ISimpleAudioVolume* FindVolumeOnDevice(DWORD targetPid, IMMDevice* pDevice) {
    if (!pDevice) return nullptr;
    IAudioSessionManager2* pManager = nullptr;
    HRESULT hr = pDevice->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL, nullptr,
                                   reinterpret_cast<void**>(&pManager));
    if (FAILED(hr) || !pManager) return nullptr;

    ISimpleAudioVolume* result = nullptr;
    IAudioSessionEnumerator* pEnum = nullptr;
    hr = pManager->GetSessionEnumerator(&pEnum);
    if (SUCCEEDED(hr) && pEnum) {
        int count = 0;
        pEnum->GetCount(&count);
        for (int i = 0; i < count && !result; i++) {
            IAudioSessionControl* pControl = nullptr;
            if (FAILED(pEnum->GetSession(i, &pControl))) continue;
            IAudioSessionControl2* pControl2 = nullptr;
            if (SUCCEEDED(pControl->QueryInterface(__uuidof(IAudioSessionControl2),
                                                   reinterpret_cast<void**>(&pControl2)))) {
                DWORD pid = 0;
                pControl2->GetProcessId(&pid);
                if (pid == targetPid) {
                    pControl->QueryInterface(__uuidof(ISimpleAudioVolume),
                                             reinterpret_cast<void**>(&result));
                }
                pControl2->Release();
            }
            pControl->Release();
        }
        pEnum->Release();
    }
    pManager->Release();
    return result;
}

// Helper: find ISimpleAudioVolume for a given PID.
// Prefers the device the PID has been explicitly routed to (g_pidToDeviceId),
// then falls back to scanning all active render devices.
static ISimpleAudioVolume* FindVolumeForPid(DWORD targetPid) {
    if (!g_enumerator) return nullptr;

    // Try the routed device first
    auto it = g_pidToDeviceId.find(targetPid);
    if (it != g_pidToDeviceId.end() && !it->second.empty()) {
        IMMDevice* pRoutedDevice = nullptr;
        HRESULT hr = g_enumerator->GetDevice(it->second.c_str(), &pRoutedDevice);
        if (SUCCEEDED(hr) && pRoutedDevice) {
            ISimpleAudioVolume* vol = FindVolumeOnDevice(targetPid, pRoutedDevice);
            pRoutedDevice->Release();
            if (vol) return vol;
        }
    }

    // Fallback: scan all active render devices
    IMMDeviceCollection* pCollection = nullptr;
    HRESULT hr = g_enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &pCollection);
    if (FAILED(hr) || !pCollection) return nullptr;

    UINT deviceCount = 0;
    pCollection->GetCount(&deviceCount);
    ISimpleAudioVolume* result = nullptr;

    for (UINT d = 0; d < deviceCount && !result; d++) {
        IMMDevice* pDevice = nullptr;
        if (FAILED(pCollection->Item(d, &pDevice))) continue;
        result = FindVolumeOnDevice(targetPid, pDevice);
        pDevice->Release();
    }

    pCollection->Release();
    return result;
}

AUDIO_API int32_t audio_set_volume(uint32_t process_id, float volume) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_initialized) return E_FAIL;

    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;

    ISimpleAudioVolume* pVol = FindVolumeForPid(process_id);
    if (!pVol) return E_FAIL;

    HRESULT hr = pVol->SetMasterVolume(volume, nullptr);
    pVol->Release();
    return hr;
}

AUDIO_API int32_t audio_set_mute(uint32_t process_id, int32_t muted) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_initialized) return E_FAIL;

    ISimpleAudioVolume* pVol = FindVolumeForPid(process_id);
    if (!pVol) return E_FAIL;

    HRESULT hr = pVol->SetMute(muted ? TRUE : FALSE, nullptr);
    pVol->Release();
    return hr;
}

// ─── Device Master Volume ────────────────────────────────────

static IAudioEndpointVolume* GetEndpointVolumeForDevice(const wchar_t* device_id) {
    if (!g_enumerator || !device_id || device_id[0] == L'\0') return nullptr;
    IMMDevice* pDevice = nullptr;
    if (FAILED(g_enumerator->GetDevice(device_id, &pDevice)) || !pDevice) return nullptr;
    IAudioEndpointVolume* pVol = nullptr;
    pDevice->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL, nullptr,
                      reinterpret_cast<void**>(&pVol));
    pDevice->Release();
    return pVol;
}

AUDIO_API float audio_get_device_volume(const wchar_t* device_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    IAudioEndpointVolume* pVol = GetEndpointVolumeForDevice(device_id);
    if (!pVol) return -1.0f;
    float vol = 1.0f;
    pVol->GetMasterVolumeLevelScalar(&vol);
    pVol->Release();
    return vol;
}

AUDIO_API int32_t audio_set_device_volume(const wchar_t* device_id, float volume) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    IAudioEndpointVolume* pVol = GetEndpointVolumeForDevice(device_id);
    if (!pVol) return E_FAIL;
    HRESULT hr = pVol->SetMasterVolumeLevelScalar(volume, nullptr);
    pVol->Release();
    return hr;
}

// ─── Auto-Start ─────────────────────────────────────────────

static const wchar_t* AUTOSTART_KEY = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
static const wchar_t* AUTOSTART_VALUE = L"AudioRouter";

AUDIO_API int32_t audio_set_autostart(int32_t enabled) {
    HKEY hKey;
    if (enabled) {
        LONG result = RegOpenKeyExW(HKEY_CURRENT_USER, AUTOSTART_KEY, 0, KEY_SET_VALUE, &hKey);
        if (result != ERROR_SUCCESS) return E_FAIL;

        wchar_t exePath[MAX_PATH];
        GetModuleFileNameW(nullptr, exePath, MAX_PATH);

        result = RegSetValueExW(hKey, AUTOSTART_VALUE, 0, REG_SZ,
                                reinterpret_cast<const BYTE*>(exePath),
                                static_cast<DWORD>((wcslen(exePath) + 1) * sizeof(wchar_t)));
        RegCloseKey(hKey);
        return (result == ERROR_SUCCESS) ? 0 : E_FAIL;
    } else {
        LONG result = RegOpenKeyExW(HKEY_CURRENT_USER, AUTOSTART_KEY, 0, KEY_SET_VALUE, &hKey);
        if (result != ERROR_SUCCESS) return 0; // Key doesn't exist, nothing to remove
        RegDeleteValueW(hKey, AUTOSTART_VALUE);
        RegCloseKey(hKey);
        return 0;
    }
}

AUDIO_API int32_t audio_get_autostart(void) {
    HKEY hKey;
    LONG result = RegOpenKeyExW(HKEY_CURRENT_USER, AUTOSTART_KEY, 0, KEY_QUERY_VALUE, &hKey);
    if (result != ERROR_SUCCESS) return 0;

    result = RegQueryValueExW(hKey, AUTOSTART_VALUE, nullptr, nullptr, nullptr, nullptr);
    RegCloseKey(hKey);
    return (result == ERROR_SUCCESS) ? 1 : 0;
}

// ─── Global Hotkeys ─────────────────────────────────────────

// Hidden message-only window for receiving hotkey messages
static HWND g_hotkeyHwnd = nullptr;

static LRESULT CALLBACK HotkeyWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

static void EnsureHotkeyWindow() {
    if (g_hotkeyHwnd) return;

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = HotkeyWndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"AudioRouterHotkeyClass";
    RegisterClassExW(&wc);

    g_hotkeyHwnd = CreateWindowExW(
        0, L"AudioRouterHotkeyClass", L"", 0,
        0, 0, 0, 0, HWND_MESSAGE, nullptr, wc.hInstance, nullptr
    );
}

AUDIO_API int32_t audio_register_hotkey(int32_t id, uint32_t modifiers, uint32_t vk) {
    EnsureHotkeyWindow();
    if (!g_hotkeyHwnd) return E_FAIL;
    BOOL ok = RegisterHotKey(g_hotkeyHwnd, id, modifiers, vk);
    return ok ? 0 : E_FAIL;
}

AUDIO_API int32_t audio_unregister_hotkey(int32_t id) {
    if (!g_hotkeyHwnd) return 0;
    UnregisterHotKey(g_hotkeyHwnd, id);
    return 0;
}

AUDIO_API int32_t audio_poll_hotkey(void) {
    if (!g_hotkeyHwnd) return 0;
    MSG msg;
    while (PeekMessageW(&msg, g_hotkeyHwnd, WM_HOTKEY, WM_HOTKEY, PM_REMOVE)) {
        return static_cast<int32_t>(msg.wParam); // hotkey id
    }
    return 0;
}

// ─── App Icon Extraction ─────────────────────────────────────

AUDIO_API int32_t audio_get_app_icon(uint32_t pid, uint8_t* rgba_buf, int32_t buf_size,
                                     int32_t* out_width, int32_t* out_height) {
    if (!out_width || !out_height) return -1;

    const int W = 32, H = 32;
    *out_width = W;
    *out_height = H;

    const int needed = W * H * 4;
    if (!rgba_buf || buf_size < needed) return needed;

    // Get executable path from PID
    HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!hProcess) return -2;

    wchar_t exePath[MAX_PATH] = {};
    DWORD size = MAX_PATH;
    bool gotPath = QueryFullProcessImageNameW(hProcess, 0, exePath, &size) != 0;
    CloseHandle(hProcess);
    if (!gotPath) return -3;

    // Try large icon (32x32) first, then small icon
    HICON hIcon = nullptr;
    if (ExtractIconExW(exePath, 0, &hIcon, nullptr, 1) == 0 || !hIcon) {
        HICON hSmall = nullptr;
        ExtractIconExW(exePath, 0, nullptr, &hSmall, 1);
        hIcon = hSmall;
    }
    if (!hIcon) return -4;

    // Render icon into a 32-bit top-down DIB
    HDC hdcScreen = GetDC(nullptr);
    HDC hdcMem = CreateCompatibleDC(hdcScreen);

    BITMAPINFOHEADER bi = {};
    bi.biSize        = sizeof(bi);
    bi.biWidth       = W;
    bi.biHeight      = -H;  // top-down
    bi.biPlanes      = 1;
    bi.biBitCount    = 32;
    bi.biCompression = BI_RGB;

    void* pBits = nullptr;
    HBITMAP hBmp = CreateDIBSection(hdcMem, reinterpret_cast<BITMAPINFO*>(&bi),
                                    DIB_RGB_COLORS, &pBits, nullptr, 0);
    if (!hBmp) {
        DeleteDC(hdcMem);
        ReleaseDC(nullptr, hdcScreen);
        DestroyIcon(hIcon);
        return -5;
    }

    HGDIOBJ oldBmp = SelectObject(hdcMem, hBmp);
    memset(pBits, 0, W * H * 4);
    DrawIconEx(hdcMem, 0, 0, hIcon, W, H, 0, nullptr, DI_NORMAL);

    // Convert BGRA → RGBA; if no alpha channel found, force fully opaque
    const uint8_t* src = reinterpret_cast<const uint8_t*>(pBits);
    bool hasAlpha = false;
    for (int i = 0; i < W * H && !hasAlpha; i++) {
        if (src[i * 4 + 3] != 0) hasAlpha = true;
    }
    for (int i = 0; i < W * H; i++) {
        rgba_buf[i * 4 + 0] = src[i * 4 + 2];              // R
        rgba_buf[i * 4 + 1] = src[i * 4 + 1];              // G
        rgba_buf[i * 4 + 2] = src[i * 4 + 0];              // B
        rgba_buf[i * 4 + 3] = hasAlpha ? src[i * 4 + 3] : 255; // A
    }

    SelectObject(hdcMem, oldBmp);
    DeleteObject(hBmp);
    DeleteDC(hdcMem);
    ReleaseDC(nullptr, hdcScreen);
    DestroyIcon(hIcon);

    return 0;
}

// ─── Loopback Mirror ─────────────────────────────────────────

struct MirrorEntry {
    std::wstring sourceId;
    std::wstring targetId;
    std::atomic<bool> shouldStop{false};
    std::thread worker;
};

// key = {sourceDeviceId, targetDeviceId}
static std::map<std::pair<std::wstring, std::wstring>, MirrorEntry*> g_mirrors;
static std::mutex g_mirrorMutex;

static void MirrorThreadFunc(MirrorEntry* entry) {
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);

    IMMDeviceEnumerator* pEnum = nullptr;
    CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                     __uuidof(IMMDeviceEnumerator), (void**)&pEnum);
    if (!pEnum) { CoUninitialize(); return; }

    IMMDevice* pSrc = nullptr;
    IMMDevice* pTgt = nullptr;
    pEnum->GetDevice(entry->sourceId.c_str(), &pSrc);
    pEnum->GetDevice(entry->targetId.c_str(), &pTgt);

    if (!pSrc || !pTgt) {
        if (pSrc) pSrc->Release();
        if (pTgt) pTgt->Release();
        pEnum->Release();
        CoUninitialize();
        return;
    }

    // ── Capture client (loopback from source) ──
    IAudioClient* pCapClient = nullptr;
    pSrc->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void**)&pCapClient);
    if (!pCapClient) {
        pSrc->Release(); pTgt->Release(); pEnum->Release();
        CoUninitialize(); return;
    }

    WAVEFORMATEX* pWfx = nullptr;
    pCapClient->GetMixFormat(&pWfx);

    // 2-second buffer; loopback mode
    HRESULT hr = pCapClient->Initialize(
        AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_LOOPBACK,
        20000000LL, 0, pWfx, nullptr);

    if (FAILED(hr)) {
        CoTaskMemFree(pWfx);
        pCapClient->Release();
        pSrc->Release(); pTgt->Release(); pEnum->Release();
        CoUninitialize(); return;
    }

    IAudioCaptureClient* pCapture = nullptr;
    pCapClient->GetService(__uuidof(IAudioCaptureClient), (void**)&pCapture);
    if (!pCapture) {
        CoTaskMemFree(pWfx); pCapClient->Release();
        pSrc->Release(); pTgt->Release(); pEnum->Release();
        CoUninitialize(); return;
    }

    // ── Render client (to target) ──
    IAudioClient* pRndClient = nullptr;
    pTgt->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void**)&pRndClient);
    if (!pRndClient) {
        CoTaskMemFree(pWfx); pCapture->Release(); pCapClient->Release();
        pSrc->Release(); pTgt->Release(); pEnum->Release();
        CoUninitialize(); return;
    }

    // AUTOCONVERTPCM lets WASAPI handle sample-rate/format conversion automatically
    hr = pRndClient->Initialize(
        AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
        20000000LL, 0, pWfx, nullptr);

    IAudioRenderClient* pRender = nullptr;
    UINT32 renderBufSize = 0;

    if (SUCCEEDED(hr)) {
        pRndClient->GetService(__uuidof(IAudioRenderClient), (void**)&pRender);
        pRndClient->GetBufferSize(&renderBufSize);
    }

    if (!pRender) {
        CoTaskMemFree(pWfx); pCapture->Release(); pCapClient->Release();
        pRndClient->Release();
        pSrc->Release(); pTgt->Release(); pEnum->Release();
        CoUninitialize(); return;
    }

    pCapClient->Start();
    pRndClient->Start();

    while (!entry->shouldStop) {
        Sleep(10); // 10 ms polling

        UINT32 packetSize = 0;
        while (!entry->shouldStop &&
               SUCCEEDED(pCapture->GetNextPacketSize(&packetSize)) &&
               packetSize > 0) {
            BYTE* pData = nullptr;
            UINT32 numFrames = 0;
            DWORD flags = 0;
            if (FAILED(pCapture->GetBuffer(&pData, &numFrames, &flags, nullptr, nullptr)))
                break;

            UINT32 padding = 0;
            pRndClient->GetCurrentPadding(&padding);
            UINT32 available = renderBufSize - padding;

            if (available >= numFrames) {
                BYTE* pRenderData = nullptr;
                if (SUCCEEDED(pRender->GetBuffer(numFrames, &pRenderData))) {
                    if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
                        memset(pRenderData, 0, numFrames * pWfx->nBlockAlign);
                    } else {
                        memcpy(pRenderData, pData, numFrames * pWfx->nBlockAlign);
                    }
                    pRender->ReleaseBuffer(numFrames, 0);
                }
            }

            pCapture->ReleaseBuffer(numFrames);
        }
    }

    pCapClient->Stop();
    pRndClient->Stop();

    CoTaskMemFree(pWfx);
    pRender->Release();
    pCapture->Release();
    pRndClient->Release();
    pCapClient->Release();
    pSrc->Release();
    pTgt->Release();
    pEnum->Release();
    CoUninitialize();
}

AUDIO_API int32_t audio_start_mirror(const wchar_t* source_device_id,
                                      const wchar_t* target_device_id) {
    if (!source_device_id || !target_device_id) return -1;

    std::wstring srcId(source_device_id);
    std::wstring tgtId(target_device_id);

    // Guard 1: reject self-mirror (source == target → instant echo loop)
    if (srcId.empty() || tgtId.empty() || srcId == tgtId) return -2;

    auto key = std::make_pair(srcId, tgtId);
    // Guard 2: reject circular mirror (B→A already exists when adding A→B → feedback)
    auto reverseKey = std::make_pair(tgtId, srcId);

    std::lock_guard<std::mutex> lock(g_mirrorMutex);
    if (g_mirrors.find(key) != g_mirrors.end()) return 0;      // already running
    if (g_mirrors.find(reverseKey) != g_mirrors.end()) return -3; // circular mirror blocked

    MirrorEntry* entry = new MirrorEntry();
    entry->sourceId = srcId;
    entry->targetId = tgtId;
    entry->worker = std::thread(MirrorThreadFunc, entry);
    g_mirrors[key] = entry;
    return 0;
}

AUDIO_API int32_t audio_stop_mirror(const wchar_t* source_device_id,
                                     const wchar_t* target_device_id) {
    if (!source_device_id || !target_device_id) return -1;
    auto key = std::make_pair(std::wstring(source_device_id), std::wstring(target_device_id));

    std::lock_guard<std::mutex> lock(g_mirrorMutex);
    auto it = g_mirrors.find(key);
    if (it == g_mirrors.end()) return 0;

    it->second->shouldStop = true;
    if (it->second->worker.joinable()) it->second->worker.join();
    delete it->second;
    g_mirrors.erase(it);
    return 0;
}

AUDIO_API void audio_stop_all_mirrors(void) {
    std::lock_guard<std::mutex> lock(g_mirrorMutex);
    for (auto& kv : g_mirrors) {
        kv.second->shouldStop = true;
        if (kv.second->worker.joinable()) kv.second->worker.join();
        delete kv.second;
    }
    g_mirrors.clear();
}

// ─── Set Default Device (IPolicyConfig) ─────────────────────

// IPolicyConfig COM interface — undocumented but stable since Windows 7.
// Used by EarTrumpet, SoundSwitch, and many other audio tools.
MIDL_INTERFACE("f8679f50-850a-41cf-9c72-430f290290c8")
IPolicyConfig : public IUnknown {
public:
    virtual HRESULT STDMETHODCALLTYPE GetMixFormat(PCWSTR, WAVEFORMATEX**) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetDeviceFormat(PCWSTR, INT, WAVEFORMATEX**) = 0;
    virtual HRESULT STDMETHODCALLTYPE ResetDeviceFormat(PCWSTR) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetDeviceFormat(PCWSTR, WAVEFORMATEX*, WAVEFORMATEX*) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetProcessingPeriod(PCWSTR, INT, PINT64, PINT64) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetProcessingPeriod(PCWSTR, PINT64) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetShareMode(PCWSTR, struct DeviceShareMode*) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetShareMode(PCWSTR, struct DeviceShareMode*) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetPropertyValue(PCWSTR, const PROPERTYKEY&, PROPVARIANT*) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetPropertyValue(PCWSTR, const PROPERTYKEY&, PROPVARIANT*) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetDefaultEndpoint(PCWSTR deviceId, ERole role) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetEndpointVisibility(PCWSTR, INT) = 0;
};

AUDIO_API int32_t audio_set_default_device(const wchar_t* device_id) {
    if (!device_id || device_id[0] == L'\0') return E_INVALIDARG;

    IPolicyConfig* pPolicyConfig = nullptr;
    HRESULT hr = CoCreateInstance(
        CLSID_PolicyConfigClient, nullptr, CLSCTX_ALL,
        __uuidof(IPolicyConfig), reinterpret_cast<void**>(&pPolicyConfig));
    if (FAILED(hr) || !pPolicyConfig) return hr;

    // Set as default for all roles (console, multimedia, communications)
    hr = pPolicyConfig->SetDefaultEndpoint(device_id, eConsole);
    pPolicyConfig->SetDefaultEndpoint(device_id, eMultimedia);
    pPolicyConfig->SetDefaultEndpoint(device_id, eCommunications);
    pPolicyConfig->Release();
    return hr;
}

// ─── Device Balance (Stereo L/R) ────────────────────────────

AUDIO_API float audio_get_device_balance(const wchar_t* device_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    IAudioEndpointVolume* pVol = GetEndpointVolumeForDevice(device_id);
    if (!pVol) return 0.0f;

    UINT channelCount = 0;
    pVol->GetChannelCount(&channelCount);
    if (channelCount < 2) {
        pVol->Release();
        return 0.0f; // mono — no balance
    }

    float left = 1.0f, right = 1.0f;
    pVol->GetChannelVolumeLevelScalar(0, &left);
    pVol->GetChannelVolumeLevelScalar(1, &right);
    pVol->Release();

    // Convert L/R volumes to -1..+1 balance
    // If left==right → 0, if left==0 → +1, if right==0 → -1
    float sum = left + right;
    if (sum < 0.001f) return 0.0f;
    return (right - left) / sum;
}

AUDIO_API int32_t audio_set_device_balance(const wchar_t* device_id, float balance) {
    std::lock_guard<std::mutex> lock(g_mutex);
    IAudioEndpointVolume* pVol = GetEndpointVolumeForDevice(device_id);
    if (!pVol) return E_FAIL;

    UINT channelCount = 0;
    pVol->GetChannelCount(&channelCount);
    if (channelCount < 2) {
        pVol->Release();
        return 0; // mono — no-op
    }

    if (balance < -1.0f) balance = -1.0f;
    if (balance > 1.0f) balance = 1.0f;

    // Get current master volume to preserve overall loudness
    float master = 1.0f;
    pVol->GetMasterVolumeLevelScalar(&master);

    float left, right;
    if (balance <= 0.0f) {
        // Pan left: right is reduced
        left = master;
        right = master * (1.0f + balance);
    } else {
        // Pan right: left is reduced
        left = master * (1.0f - balance);
        right = master;
    }

    pVol->SetChannelVolumeLevelScalar(0, left, nullptr);
    pVol->SetChannelVolumeLevelScalar(1, right, nullptr);
    pVol->Release();
    return 0;
}

// ─── OS Sound Settings ──────────────────────────────────────

AUDIO_API int32_t audio_open_sound_settings(void) {
    // Open Windows 11/10 Sound Settings
    HINSTANCE result = ShellExecuteW(nullptr, L"open",
        L"ms-settings:sound", nullptr, nullptr, SW_SHOWNORMAL);
    return (reinterpret_cast<intptr_t>(result) > 32) ? 0 : E_FAIL;
}

// ─── OS Accent Color ────────────────────────────────────────

AUDIO_API uint32_t audio_get_accent_color(void) {
    HKEY hKey;
    LONG result = RegOpenKeyExW(HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\DWM", 0, KEY_QUERY_VALUE, &hKey);
    if (result != ERROR_SUCCESS) return 0;

    DWORD color = 0;
    DWORD size = sizeof(color);
    // DWM AccentColor might be missing or have 0 alpha. ColorizationColor is always present
    // and is in AARRGGBB format.
    result = RegQueryValueExW(hKey, L"ColorizationColor", nullptr, nullptr,
                               reinterpret_cast<BYTE*>(&color), &size);
    RegCloseKey(hKey);
    if (result != ERROR_SUCCESS || color == 0) return 0;

    // Force alpha to 0xFF (solid) to ensure Flutter renders it properly
    return 0xFF000000 | (color & 0x00FFFFFF);
}

// ─── DLL Entry Point ─────────────────────────────────────────

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID lpReserved) {
    switch (reason) {
    case DLL_PROCESS_ATTACH:
        DisableThreadLibraryCalls(hModule);
        break;
    case DLL_PROCESS_DETACH:
        break;
    }
    return TRUE;
}
