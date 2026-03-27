@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" > nul 2>&1
cd /d "c:\Users\ahmed\audio_router\windows\audio_backend"
cl.exe /nologo /O2 /EHa /MD /DAUDIO_BACKEND_EXPORTS /c audio_backend.cpp /Fo:audio_backend.obj
if errorlevel 1 goto fail
link.exe /nologo /DLL /OUT:audio_backend.dll audio_backend.obj ole32.lib propsys.lib runtimeobject.lib ^
  /EXPORT:audio_init /EXPORT:audio_cleanup ^
  /EXPORT:audio_get_device_count /EXPORT:audio_get_devices ^
  /EXPORT:audio_get_session_count /EXPORT:audio_get_sessions ^
  /EXPORT:audio_route_process /EXPORT:audio_get_vtable_slot ^
  /EXPORT:audio_set_volume /EXPORT:audio_set_mute ^
  /EXPORT:audio_set_autostart /EXPORT:audio_get_autostart ^
  /EXPORT:audio_register_hotkey /EXPORT:audio_unregister_hotkey /EXPORT:audio_poll_hotkey
if errorlevel 1 goto fail
echo BUILD OK
goto end
:fail
echo BUILD FAILED
exit /b 1
:end
