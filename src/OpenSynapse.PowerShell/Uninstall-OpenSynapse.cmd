@echo off
setlocal
title OpenSynapse 2.5.1 Uninstaller
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0OpenSynapse.ps1" -Mode Uninstall
set "EXITCODE=%ERRORLEVEL%"
echo.
if "%EXITCODE%"=="0" (
  echo OpenSynapse was removed and the original state was restored.
) else (
  echo Uninstallation failed with exit code %EXITCODE%.
)
pause
exit /b %EXITCODE%
