@echo off
rem DeepSeek Harness launcher shim (ASCII only: cmd.exe reads this file as OEM codepage).
rem Runs the PowerShell launcher next to this file and forwards every argument.
setlocal
set "SCRIPT=%~dp0Start-DeepSeekHarness.ps1"
if not exist "%SCRIPT%" (
  echo [error] launcher script not found: "%SCRIPT%"
  pause
  exit /b 1
)
set "PSEXE=pwsh.exe"
where pwsh.exe >nul 2>nul || set "PSEXE=powershell.exe"
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
exit /b %errorlevel%
