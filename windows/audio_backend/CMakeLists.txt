cmake_minimum_required(VERSION 3.14)
project(audio_backend LANGUAGES CXX)

add_library(audio_backend SHARED
  "audio_backend.cpp"
  "audio_backend.h"
)

target_compile_features(audio_backend PUBLIC cxx_std_17)
target_compile_definitions(audio_backend PRIVATE AUDIO_BACKEND_EXPORTS)
target_compile_definitions(audio_backend PRIVATE NOMINMAX)
target_compile_definitions(audio_backend PRIVATE UNICODE _UNICODE)
target_compile_options(audio_backend PRIVATE /EHsc /W3)

# Link Windows audio and COM libraries
target_link_libraries(audio_backend PRIVATE
  ole32.lib
  propsys.lib
  uuid.lib
  runtimeobject.lib
  Shell32.lib
  Gdi32.lib
  User32.lib
  Advapi32.lib
)

# Set output name
set_target_properties(audio_backend PROPERTIES
  OUTPUT_NAME "audio_backend"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner/$<CONFIG>"
)
