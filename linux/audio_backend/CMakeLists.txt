cmake_minimum_required(VERSION 3.14)
project(audio_backend C)

# Find PipeWire and PulseAudio via pkg-config
find_package(PkgConfig REQUIRED)

pkg_check_modules(PIPEWIRE libpipewire-0.3)
pkg_check_modules(PULSE libpulse)
pkg_check_modules(GDK_PIXBUF gdk-pixbuf-2.0)
pkg_check_modules(X11 x11)

if(NOT PIPEWIRE_FOUND AND NOT PULSE_FOUND)
    message(FATAL_ERROR "Neither PipeWire nor PulseAudio development libraries found. "
                        "Install libpipewire-0.3-dev or libpulse-dev.")
endif()

# Shared library: libaudio_backend.so
set(SOURCES audio_backend_linux.c)

if(PIPEWIRE_FOUND)
    list(APPEND SOURCES pipewire_backend.c)
endif()

if(PULSE_FOUND)
    list(APPEND SOURCES pulse_backend.c)
endif()

add_library(audio_backend SHARED ${SOURCES})

target_compile_definitions(audio_backend PRIVATE AUDIO_BACKEND_EXPORTS)

if(PIPEWIRE_FOUND)
    target_compile_definitions(audio_backend PRIVATE HAVE_PIPEWIRE)
    target_include_directories(audio_backend PRIVATE ${PIPEWIRE_INCLUDE_DIRS})
    target_link_libraries(audio_backend ${PIPEWIRE_LIBRARIES})
    message(STATUS "AudioRouter: PipeWire backend ENABLED (${PIPEWIRE_VERSION})")
else()
    message(STATUS "AudioRouter: PipeWire backend DISABLED (libpipewire-0.3 not found)")
endif()

if(PULSE_FOUND)
    target_compile_definitions(audio_backend PRIVATE HAVE_PULSE)
    target_include_directories(audio_backend PRIVATE ${PULSE_INCLUDE_DIRS})
    target_link_libraries(audio_backend ${PULSE_LIBRARIES})
    message(STATUS "AudioRouter: PulseAudio backend ENABLED (${PULSE_VERSION})")
else()
    message(STATUS "AudioRouter: PulseAudio backend DISABLED (libpulse not found)")
endif()

# Common dependencies
target_link_libraries(audio_backend dl pthread)

# GdkPixbuf for app icon loading (optional — graceful no-op if missing)
if(GDK_PIXBUF_FOUND)
    target_compile_definitions(audio_backend PRIVATE HAVE_GDK_PIXBUF)
    target_include_directories(audio_backend PRIVATE ${GDK_PIXBUF_INCLUDE_DIRS})
    target_link_libraries(audio_backend ${GDK_PIXBUF_LIBRARIES})
    message(STATUS "AudioRouter: GdkPixbuf ENABLED — app icons will work")
else()
    message(STATUS "AudioRouter: GdkPixbuf NOT FOUND — app icons disabled")
endif()

# X11 for global hotkeys (optional — graceful no-op on pure Wayland)
if(X11_FOUND)
    target_compile_definitions(audio_backend PRIVATE HAVE_X11)
    target_include_directories(audio_backend PRIVATE ${X11_INCLUDE_DIRS})
    target_link_libraries(audio_backend ${X11_LIBRARIES})
    message(STATUS "AudioRouter: X11 ENABLED — global hotkeys will work")
else()
    message(STATUS "AudioRouter: X11 NOT FOUND — hotkeys disabled")
endif()

# C11 standard
set_target_properties(audio_backend PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON
    # Hide all symbols except AUDIO_API exports
    C_VISIBILITY_PRESET hidden
)
