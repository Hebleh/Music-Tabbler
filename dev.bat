@echo off
setlocal

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev.ps1" %*
set "DEV_EXIT_CODE=%ERRORLEVEL%"

endlocal & exit /b %DEV_EXIT_CODE%
