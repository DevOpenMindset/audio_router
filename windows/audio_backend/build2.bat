@echo off
setlocal

set MSVC=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64
set WINSDK_INC=C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0
set WINSDK_LIB=C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0
set MSVC_INC=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include
set MSVC_LIB=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\lib\x64

cd /d "c:\Users\ahmed\audio_router\windows\audio_backend"

"%MSVC%\cl.exe" /nologo /O2 /EHa /MD /DAUDIO_BACKEND_EXPORTS ^
  /I"%MSVC_INC%" ^
  /I"%WINSDK_INC%\um" ^
  /I"%WINSDK_INC%\shared" ^
  /I"%WINSDK_INC%\ucrt" ^
  /c audio_backend.cpp /Fo:audio_backend.obj

if errorlevel 1 (echo COMPILE FAILED & exit /b 1)

"%MSVC%\link.exe" /nologo /DLL /OUT:audio_backend.dll audio_backend.obj ^
  /LIBPATH:"%MSVC_LIB%" ^
  /LIBPATH:"%WINSDK_LIB%\um\x64" ^
  /LIBPATH:"%WINSDK_LIB%\ucrt\x64" ^
  ole32.lib propsys.lib runtimeobject.lib ^
  /EXPORT:audio_init /EXPORT:audio_cleanup ^
  /EXPORT:audio_get_device_count /EXPORT:audio_get_devices ^
  /EXPORT:audio_get_session_count /EXPORT:audio_get_sessions ^
  /EXPORT:audio_route_process /EXPORT:audio_get_vtable_slot ^
  /EXPORT:audio_set_volume /EXPORT:audio_set_mute ^
  /EXPORT:audio_set_autostart /EXPORT:audio_get_autostart ^
  /EXPORT:audio_register_hotkey /EXPORT:audio_unregister_hotkey /EXPORT:audio_poll_hotkey

if errorlevel 1 (echo LINK FAILED & exit /b 1)
echo BUILD OK
