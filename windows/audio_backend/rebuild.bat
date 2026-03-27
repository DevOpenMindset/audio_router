@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
cd /d "C:\Users\ahmed\audio_router\windows\audio_backend"
echo Compiling...
cl.exe /nologo /O2 /EHa /MD /DAUDIO_BACKEND_EXPORTS /c audio_backend.cpp /Fo:audio_backend.obj
if errorlevel 1 ( echo COMPILE FAILED & exit /b 1 )
echo Linking...
link.exe /nologo /DLL /OUT:audio_backend.dll audio_backend.obj ole32.lib propsys.lib runtimeobject.lib Shell32.lib Gdi32.lib User32.lib Advapi32.lib ^
  /EXPORT:audio_init /EXPORT:audio_cleanup ^
  /EXPORT:audio_get_device_count /EXPORT:audio_get_devices ^
  /EXPORT:audio_get_session_count /EXPORT:audio_get_sessions ^
  /EXPORT:audio_route_process /EXPORT:audio_get_vtable_slot ^
  /EXPORT:audio_set_volume /EXPORT:audio_set_mute ^
  /EXPORT:audio_get_device_volume /EXPORT:audio_set_device_volume ^
  /EXPORT:audio_get_app_icon ^
  /EXPORT:audio_set_autostart /EXPORT:audio_get_autostart ^
  /EXPORT:audio_register_hotkey /EXPORT:audio_unregister_hotkey /EXPORT:audio_poll_hotkey ^
  /EXPORT:audio_poll_peaks ^
  /EXPORT:audio_start_mirror /EXPORT:audio_stop_mirror /EXPORT:audio_stop_all_mirrors
if errorlevel 1 ( echo LINK FAILED & exit /b 1 )
echo BUILD OK
