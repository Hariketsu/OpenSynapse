@echo off
setlocal
title OpenSynapse 2.4.6 Installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0OpenSynapse.ps1" -Mode Install
set "EXITCODE=%ERRORLEVEL%"
echo.
if "%EXITCODE%"=="0" (
echo OpenSynapse 2.4.6 installation completed.
) else (
  echo Installation failed with exit code %EXITCODE%.
)
pause
exit /b %EXITCODE%
