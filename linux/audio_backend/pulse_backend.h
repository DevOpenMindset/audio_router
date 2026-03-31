#pragma once

// pulse_backend.h — PulseAudio backend for AudioRouter
// Fallback when PipeWire is not available

#include "audio_backend_linux.h"

int pulse_init(void);
void pulse_cleanup(void);

int32_t pulse_get_device_count(void);
int32_t pulse_get_devices(AudioDeviceInfo* devices, int32_t max_count);

int32_t pulse_get_session_count(void);
int32_t pulse_get_sessions(AudioSessionInfo* sessions, int32_t max_count);
int32_t pulse_poll_peaks(PeakLevelInfo* peaks, int32_t max_count);

int32_t pulse_route_process(uint32_t pid, const char* device_id);
int32_t pulse_set_volume(uint32_t pid, float volume);
int32_t pulse_set_mute(uint32_t pid, int32_t muted);

float   pulse_get_device_volume(const char* device_id);
int32_t pulse_set_device_volume(const char* device_id, float volume);

int32_t pulse_start_mirror(const char* source_id, const char* target_id);
int32_t pulse_stop_mirror(const char* source_id, const char* target_id);
void    pulse_stop_all_mirrors(void);
