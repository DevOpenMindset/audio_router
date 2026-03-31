#pragma once

// pipewire_backend.h — PipeWire backend for AudioRouter
// Primary backend for modern Linux (Ubuntu 22.04+, Fedora 34+)

#include "audio_backend_linux.h"

int pw_backend_init(void);
void pw_backend_cleanup(void);

int32_t pw_backend_get_device_count(void);
int32_t pw_backend_get_devices(AudioDeviceInfo* devices, int32_t max_count);

int32_t pw_backend_get_session_count(void);
int32_t pw_backend_get_sessions(AudioSessionInfo* sessions, int32_t max_count);
int32_t pw_backend_poll_peaks(PeakLevelInfo* peaks, int32_t max_count);

int32_t pw_backend_route_process(uint32_t pid, const char* device_id);
int32_t pw_backend_set_volume(uint32_t pid, float volume);
int32_t pw_backend_set_mute(uint32_t pid, int32_t muted);

float   pw_backend_get_device_volume(const char* device_id);
int32_t pw_backend_set_device_volume(const char* device_id, float volume);

int32_t pw_backend_start_mirror(const char* source_id, const char* target_id);
int32_t pw_backend_stop_mirror(const char* source_id, const char* target_id);
void    pw_backend_stop_all_mirrors(void);
