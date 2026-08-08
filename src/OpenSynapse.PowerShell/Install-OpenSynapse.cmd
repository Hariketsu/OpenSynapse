@echo off
setlocal
title OpenSynapse 0.2.0-preview.1 Installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0OpenSynapse.ps1" -Mode Install
set "EXITCODE=%ERRORLEVEL%"
echo.
if "%EXITCODE%"=="0" (
echo OpenSynapse 0.2.0-preview.1 installation completed.
) else (
  echo Installation failed with exit code %EXITCODE%.
)
pause
exit /b %EXITCODE%
