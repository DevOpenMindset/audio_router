$cl   = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe'
$link = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe'
$mi   = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include'
$ml   = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\lib\x64'
$si   = 'C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0'
$sl   = 'C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0'

Set-Location 'c:\Users\ahmed\audio_router\windows\audio_backend'

& $cl /nologo /O2 /EHa /MD /DAUDIO_BACKEND_EXPORTS `
  "/I$mi" "/I$si\um" "/I$si\shared" "/I$si\ucrt" "/I$si\winrt" `
  /c audio_backend.cpp /Fo:audio_backend.obj
if ($LASTEXITCODE -ne 0) { Write-Host 'COMPILE FAILED'; exit 1 }

& $link /nologo /DLL /OUT:audio_backend.dll audio_backend.obj `
  "/LIBPATH:$ml" "/LIBPATH:$sl\um\x64" "/LIBPATH:$sl\ucrt\x64" `
  ole32.lib propsys.lib runtimeobject.lib user32.lib advapi32.lib `
  /EXPORT:audio_init /EXPORT:audio_cleanup `
  /EXPORT:audio_get_device_count /EXPORT:audio_get_devices `
  /EXPORT:audio_get_session_count /EXPORT:audio_get_sessions `
  /EXPORT:audio_route_process /EXPORT:audio_get_vtable_slot `
  /EXPORT:audio_set_volume /EXPORT:audio_set_mute `
  /EXPORT:audio_set_autostart /EXPORT:audio_get_autostart `
  /EXPORT:audio_register_hotkey /EXPORT:audio_unregister_hotkey /EXPORT:audio_poll_hotkey
if ($LASTEXITCODE -ne 0) { Write-Host 'LINK FAILED'; exit 1 }

Write-Host 'BUILD OK'
Stop-Process -Name audio_router -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Copy-Item audio_backend.dll 'c:\Users\ahmed\audio_router\build\windows\x64\runner\Debug\audio_backend.dll' -Force
Write-Host 'DEPLOYED'
