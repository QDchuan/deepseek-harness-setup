@echo off
rem ============================================================
rem  DeepSeek Harness one-click setup entry (double-click me).
rem  This file is ASCII only: cmd.exe reads .cmd as OEM codepage.
rem  All user-facing Chinese output lives in src\setup.ps1 (UTF-8 BOM).
rem ============================================================
setlocal
title DeepSeek Harness Setup
set "PS1=%~dp0src\setup.ps1"
if not exist "%PS1%" (
  echo [error] setup script not found: "%PS1%"
  echo         Extract the whole repository, then run setup.cmd again.
  pause
  exit /b 1
)
set "PSEXE=pwsh.exe"
where pwsh.exe >nul 2>nul || set "PSEXE=powershell.exe"
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %errorlevel%
