@echo off
rem ============================================================
rem  DeepSeek Harness - single-file bootstrap.
rem
rem  Download this ONE file, double-click it, done. It fetches the
rem  setup package from GitHub, extracts it to a temp folder and runs
rem  src\setup.ps1 (which installs Node + DeepSeek Harness + launcher).
rem
rem  No admin rights needed. ASCII only (cmd.exe reads .cmd as OEM).
rem
rem  Overridable environment variables:
rem    DSH_SETUP_REPO     owner/repo to download
rem    DSH_SETUP_BRANCH   branch name (default: main)
rem    DSH_SETUP_ZIP      use a local zip instead of downloading
rem ============================================================
setlocal enabledelayedexpansion
title DeepSeek Harness Setup

set "REPO=%DSH_SETUP_REPO%"
if not defined REPO set "REPO=QDchuan/deepseek-harness-setup"
set "BRANCH=%DSH_SETUP_BRANCH%"
if not defined BRANCH set "BRANCH=main"
for /f "tokens=2 delims=/" %%A in ("%REPO%") do set "REPONAME=%%A"

set "WORK=%TEMP%\dsh-setup-%RANDOM%%RANDOM%"
set "ZIP=%WORK%\repo.zip"
mkdir "%WORK%" 2>nul
if not exist "%WORK%" (
  echo [error] cannot create temp folder: "%WORK%"
  pause
  exit /b 1
)

echo.
echo  ==============================================
echo   DeepSeek Harness - one-click setup
echo  ==============================================
echo.
echo   Installs into your own user folder. No administrator
echo   rights needed. Takes a few minutes on first run.
echo.

if defined DSH_SETUP_ZIP (
  echo  [1/3] Using local package: %DSH_SETUP_ZIP%
  copy /y "%DSH_SETUP_ZIP%" "%ZIP%" >nul 2>nul
  if not exist "%ZIP%" (
    echo  [error] cannot read "%DSH_SETUP_ZIP%"
    rmdir /s /q "%WORK%" 2>nul
    pause
    exit /b 1
  )
  goto :extract
)

set "URL1=https://codeload.github.com/%REPO%/zip/refs/heads/%BRANCH%"
set "URL2=https://ghfast.top/https://github.com/%REPO%/archive/refs/heads/%BRANCH%.zip"
set "URL3=https://gh-proxy.com/https://github.com/%REPO%/archive/refs/heads/%BRANCH%.zip"

echo  [1/3] Downloading setup package...
where curl.exe >nul 2>nul
if not errorlevel 1 (
  call :try_curl "%URL1%"
  if exist "%ZIP%" goto :extract
  call :try_curl "%URL2%"
  if exist "%ZIP%" goto :extract
  call :try_curl "%URL3%"
  if exist "%ZIP%" goto :extract
)

echo        curl did not work, trying PowerShell...
call :try_ps "%URL1%"
if exist "%ZIP%" goto :extract
call :try_ps "%URL2%"
if exist "%ZIP%" goto :extract
call :try_ps "%URL3%"
if exist "%ZIP%" goto :extract

echo.
echo  [error] Could not download the setup package.
echo.
echo    Download it manually in your browser:
echo      https://github.com/%REPO%/archive/refs/heads/%BRANCH%.zip
echo    then extract the zip and double-click setup.cmd inside.
echo.
echo    (If you are behind a proxy, set HTTPS_PROXY first.)
rmdir /s /q "%WORK%" 2>nul
pause
exit /b 1

:extract
echo  [2/3] Extracting...
set "SRC=%WORK%\%REPONAME%-%BRANCH%"
where tar.exe >nul 2>nul
if not errorlevel 1 (
  tar.exe -xf "%ZIP%" -C "%WORK%" >nul 2>nul
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%ZIP%' -DestinationPath '%WORK%' -Force"
)
if not exist "%SRC%\src\setup.ps1" (
  for /d %%D in ("%WORK%\*") do (
    if exist "%%D\src\setup.ps1" set "SRC=%%D"
  )
)
if not exist "%SRC%\src\setup.ps1" (
  echo  [error] unexpected package layout after extracting.
  echo          Extracted to: %WORK%
  pause
  exit /b 1
)

echo  [3/3] Running the installer...
echo.
set "PSEXE=pwsh.exe"
where pwsh.exe >nul 2>nul || set "PSEXE=powershell.exe"
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%SRC%\src\setup.ps1" %*
set "CODE=%errorlevel%"

rmdir /s /q "%WORK%" 2>nul
exit /b %CODE%

:try_curl
if exist "%ZIP%" exit /b 0
curl.exe -L --fail --silent --show-error --retry 2 --output "%ZIP%" %1
if exist "%ZIP%" exit /b 0
del "%ZIP%" 2>nul
exit /b 1

:try_ps
if exist "%ZIP%" exit /b 0
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -Uri '%1' -OutFile '%ZIP%' -UseBasicParsing } catch { exit 1 }"
if exist "%ZIP%" exit /b 0
del "%ZIP%" 2>nul
exit /b 1
