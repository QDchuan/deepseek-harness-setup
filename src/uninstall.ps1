<#
.SYNOPSIS
  卸载 DeepSeek Harness 安装器装下的所有东西。

.DESCRIPTION
  删除的内容：
    · 桌面与开始菜单里的「DeepSeek Harness」快捷方式
    · 开始菜单里的「卸载 DeepSeek Harness」
    · 「设置 → 应用」里的注册项（HKCU）
    · 安装目录本身（Node 便携版、dsh 依赖、启动器、缓存、日志都在一起）

  默认**不删** %USERPROFILE%\.dsh（你的会话记录、设置与 API 密钥都在那里）。
  要一起清掉请加 -PurgeData。

.EXAMPLE
  .\uninstall.ps1                 # 交互确认后卸载，保留会话数据
  .\uninstall.ps1 -PurgeData      # 连会话记录与密钥一起删
  .\uninstall.ps1 -Yes            # 不确认，直接卸
#>
[CmdletBinding()]
param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'DeepSeekHarness'),
  [switch]$PurgeData,
  [switch]$Yes,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }

function Write-Ok([string]$Text)   { Write-Host "    $Text" -ForegroundColor Green }
function Write-Info([string]$Text) { Write-Host "    $Text" -ForegroundColor DarkGray }
function Write-Warn2([string]$Text) { Write-Host "    $Text" -ForegroundColor Yellow }

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ' 卸载 DeepSeek Harness' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "  将删除安装目录：$InstallDir"
Write-Host '  将删除桌面 / 开始菜单快捷方式和应用列表注册项'
if ($PurgeData) {
  Write-Host "  将同时删除会话数据与密钥：$DshHome" -ForegroundColor Yellow
} else {
  Write-Host "  会保留会话数据与密钥：$DshHome" -ForegroundColor Green
}
Write-Host ''

if ($DryRun) {
  Write-Info '[dry-run] 什么都没删。'
  exit 0
}

if (-not $Yes) {
  $answer = Read-Host '确认卸载？输入 y 回车'
  if ($answer -notmatch '^(y|Y|yes|YES|是)$') {
    Write-Host '已取消。' -ForegroundColor Yellow
    exit 0
  }
}

# 端口占着说明 DSH 还在跑：先提醒，避免删到一半失败
$client = New-Object System.Net.Sockets.TcpClient
try {
  $iar = $client.BeginConnect('127.0.0.1', 3080, $null, $null)
  if ($iar.AsyncWaitHandle.WaitOne(600)) {
    $client.EndConnect($iar)
    Write-Warn2 '检测到 DSH 还在运行：请先关掉那个控制台窗口（或那个终端），再继续。'
    if (-not $Yes) {
      Read-Host '关掉之后按回车继续' | Out-Null
    }
  }
} catch { } finally { $client.Close() }

# ── 快捷方式 ────────────────────────────────────────────────────────────────
$shortcuts = @(
  (Join-Path ([Environment]::GetFolderPath('Desktop')) 'DeepSeek Harness.lnk'),
  (Join-Path ([Environment]::GetFolderPath('Programs')) 'DeepSeek Harness.lnk'),
  (Join-Path ([Environment]::GetFolderPath('Programs')) '卸载 DeepSeek Harness.lnk')
)
foreach ($s in $shortcuts) {
  if (Test-Path -LiteralPath $s) {
    Remove-Item -LiteralPath $s -Force -ErrorAction SilentlyContinue
    # 删完要回读确认：被安全软件/权限拦住时不能谎报成功
    if (Test-Path -LiteralPath $s) { Write-Warn2 "没删掉（可能被拦截，可手动删除）：$s" }
    else { Write-Ok "已删除 $s" }
  }
}

# ── 应用列表注册项 ──────────────────────────────────────────────────────────
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeekHarness'
if (Test-Path $key) {
  Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
  if (Test-Path $key) { Write-Warn2 '没能从「设置 → 应用」移除（可手动删除注册项 HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeekHarness）' }
  else { Write-Ok '已从「设置 → 应用」移除' }
}

# ── 会话数据 ────────────────────────────────────────────────────────────────
if ($PurgeData) {
  if (Test-Path -LiteralPath $DshHome) {
    try {
      Remove-Item -LiteralPath $DshHome -Recurse -Force -ErrorAction Stop
      Write-Ok "已删除 $DshHome"
    } catch {
      Write-Warn2 "删除 $DshHome 失败：$($_.Exception.Message)"
    }
  }
} else {
  Write-Info "保留 $DshHome（要一起删就再跑一次并加 -PurgeData）"
}

# ── 安装目录 ────────────────────────────────────────────────────────────────
if (Test-Path -LiteralPath $InstallDir) {
  try {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction Stop
    Write-Ok "已删除 $InstallDir"
  } catch {
    # 自己就住在这个目录里，脚本文件可能正被占用：交给一个隐藏的 cmd 退出后再删
    $cmdPath = Join-Path $env:TEMP 'dsh-setup-cleanup.cmd'
    $lines = @(
      '@echo off',
      'ping 127.0.0.1 -n 3 >nul',
      "rmdir /s /q `"$InstallDir`"",
      'del "%~f0"'
    )
    Set-Content -LiteralPath $cmdPath -Value ($lines -join "`r`n") -Encoding ASCII
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList "/c `"$cmdPath`"" -WindowStyle Hidden
    Write-Warn2 '安装目录里有文件正被占用，已安排后台删除：几秒后那个文件夹会自己消失。'
  }
} else {
  Write-Info "安装目录不存在，跳过：$InstallDir"
}

Write-Host ''
Write-Host ' 卸载完成。' -ForegroundColor Green
Write-Host ''
if ([Environment]::UserInteractive) { try { Read-Host '按回车键关闭窗口' | Out-Null } catch { } }
