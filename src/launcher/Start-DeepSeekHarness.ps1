<#
.SYNOPSIS
  启动 DeepSeek Harness 浏览器 GUI（dsh web）。

.DESCRIPTION
  桌面 / 开始菜单快捷方式指向本脚本。它只做这几件事：

    1. 读取安装清单（安装器写在 <安装根目录>\dsh-setup.json），据此找到
       Node 和 dsh；清单不在时退回到自动探测（PATH、便携运行时、npx 缓存、
       全局 npm、PATH 上的 dsh）。
    2. 如果目标端口上已经有 DSH 在跑，就直接打开浏览器，不再起第二个实例
       （避免两个进程抢同一个会话库）。
    3. 否则在默认工作目录里执行 `dsh web --port <端口>`。浏览器由 dsh 自己打开：
       启动 URL 里带着本次进程的 token，浏览器用它换签名 cookie 后再跳到干净
       的根地址，所以这里不代劳开浏览器，免得丢掉 token 那一步。
    4. 出错时把窗口留住并打印排查提示，双击启动时也能看到原因。

  关闭这个控制台窗口 = 停止 DSH（会话都已落盘，下次启动还在）。
#>
[CmdletBinding()]
param(
  # >>> 默认工作区（安装器会改写这一行，请保留这两个标记）>>>
  [string]$Workspace = "$env:USERPROFILE\Documents\DeepSeekHarness",
  # <<< 默认工作区 <<<

  # GUI 端口。
  [int]$Port = 3080,

  # 本次不自动打开浏览器（对应 dsh 的 --no-open）。
  [switch]$NoBrowser,

  # 只检查环境、打印将要执行的命令，不启动。
  [switch]$Diagnose
)

$ErrorActionPreference = 'Stop'

function Write-Title([string]$Text) { Write-Host $Text -ForegroundColor Cyan }
function Write-Note([string]$Text)  { Write-Host $Text -ForegroundColor DarkGray }
function Write-Ok([string]$Text)    { Write-Host $Text -ForegroundColor Green }
function Write-Warn2([string]$Text) { Write-Host $Text -ForegroundColor Yellow }
function Write-Fail([string]$Text)  { Write-Host $Text -ForegroundColor Red }

# 端口上是否已经有人在监听（用 TCP 连接判断，不依赖 netstat 权限）。
function Test-TcpPort {
  param([int]$Port, [int]$TimeoutMs = 700)
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
    $client.EndConnect($iar)
    return $true
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

# ── 安装清单：由 setup 写入，记录 Node 与 dsh 的相对位置 ─────────────────────
$manifest = $null
foreach ($candidate in @(
    (Join-Path (Split-Path $PSScriptRoot -Parent) 'dsh-setup.json'),
    (Join-Path $PSScriptRoot 'dsh-setup.json'))) {
  if (Test-Path -LiteralPath $candidate) {
    try {
      $manifest = Get-Content -LiteralPath $candidate -Raw | ConvertFrom-Json
      if ($manifest.workspace -and -not $PSBoundParameters.ContainsKey('Workspace')) {
        $Workspace = $manifest.workspace
      }
      break
    } catch {
      Write-Warn2 "安装清单读不出来（$candidate）：$($_.Exception.Message)"
    }
  }
}
$installRoot = if ($manifest -and $manifest.installRoot) { $manifest.installRoot } else { Split-Path $PSScriptRoot -Parent }

function Resolve-RelativePath {
  param([string]$Base, [string]$Relative)
  if (-not $Relative) { return $null }
  $full = Join-Path $Base $Relative
  if (Test-Path -LiteralPath $full) { return $full }
  return $null
}

function Get-NodeExe {
  # 1) 安装清单里的便携版 Node
  if ($manifest -and $manifest.nodeRelativePath) {
    $p = Resolve-RelativePath -Base $installRoot -Relative $manifest.nodeRelativePath
    if ($p) { return $p }
  }
  # 2) 便携运行时（没写清单时按约定找）
  foreach ($p in @(
      (Join-Path $installRoot 'runtime\node\node.exe'),
      (Join-Path $PSScriptRoot 'runtime\node\node.exe'))) {
    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
  }
  # 3) PATH 与常见安装位置
  foreach ($name in 'node.exe', 'node') {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) { return $cmd.Source }
  }
  foreach ($p in @(
      (Join-Path $env:ProgramFiles 'nodejs\node.exe'),
      (Join-Path $env:LOCALAPPDATA 'Programs\nodejs\node.exe'))) {
    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
  }
  return $null
}

# 读 dsh 包的版本号（bin.js 的上两级就是包目录）。
function Get-DshVersion {
  param([string]$BinPath)
  try {
    $pkg = Join-Path (Split-Path (Split-Path $BinPath -Parent) -Parent) 'package.json'
    if (Test-Path -LiteralPath $pkg) {
      return (Get-Content -LiteralPath $pkg -Raw | ConvertFrom-Json).version
    }
  } catch { }
  return $null
}

function New-DshScriptEntry {
  param([string]$BinPath, [string]$NodeExe, [string]$Source)
  $version = Get-DshVersion -BinPath $BinPath
  [pscustomobject]@{
    Kind       = 'script'
    Command    = $NodeExe
    PrefixArgs = @($BinPath)
    Display    = if ($version) { "dsh $version（$Source）" } else { "dsh（$Source）" }
    BinPath    = $BinPath
  }
}

# 按优先级挑一个 dsh 入口：
#   1. 安装清单记录的 app 目录（安装器装的那份）
#   2. 安装根目录 / 启动器目录下的 app\node_modules\@deepseek-ai\dsh
#   3. npx 缓存里最新的一份（_npx\<hash>\node_modules\@deepseek-ai\dsh）
#   4. 全局 npm 安装目录
#   5. PATH 上的 dsh.cmd / dsh.exe（官方 shim）
function Get-DshEntry {
  param([string]$NodeExe)

  if ($manifest -and $manifest.appRelativePath) {
    $bin = Resolve-RelativePath -Base $installRoot -Relative $manifest.appRelativePath
    if ($bin -and $NodeExe) { return New-DshScriptEntry -BinPath $bin -NodeExe $NodeExe -Source '安装目录' }
  }

  if ($NodeExe) {
    foreach ($root in @($installRoot, $PSScriptRoot)) {
      $bin = Join-Path $root 'app\node_modules\@deepseek-ai\dsh\lib\bin.js'
      if (Test-Path -LiteralPath $bin) {
        return New-DshScriptEntry -BinPath $bin -NodeExe $NodeExe -Source '安装目录'
      }
    }

    $npxRoot = Join-Path $env:LOCALAPPDATA 'npm-cache\_npx'
    if (Test-Path -LiteralPath $npxRoot) {
      $cached = Get-ChildItem -LiteralPath $npxRoot -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
          $bin = Join-Path $_.FullName 'node_modules\@deepseek-ai\dsh\lib\bin.js'
          if (Test-Path -LiteralPath $bin) {
            [pscustomobject]@{ Bin = $bin; Stamp = (Get-Item -LiteralPath $bin).LastWriteTime }
          }
        } | Sort-Object Stamp -Descending
      if ($cached) {
        return New-DshScriptEntry -BinPath @($cached)[0].Bin -NodeExe $NodeExe -Source 'npx 缓存'
      }
    }

    foreach ($root in @((Join-Path $env:APPDATA 'npm\node_modules'), (Join-Path $env:ProgramFiles 'nodejs\node_modules'))) {
      $bin = Join-Path $root '@deepseek-ai\dsh\lib\bin.js'
      if (Test-Path -LiteralPath $bin) {
        return New-DshScriptEntry -BinPath $bin -NodeExe $NodeExe -Source '全局安装'
      }
    }
  }

  foreach ($name in 'dsh.cmd', 'dsh.exe', 'dsh') {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
      return [pscustomobject]@{
        Kind       = 'shim'
        Command    = $cmd.Source
        PrefixArgs = @()
        Display    = "dsh（PATH: $($cmd.Source)）"
        BinPath    = $null
      }
    }
  }
  return $null
}

# 兜底：连缓存都找不到时用 npx 拉取，版本沿用 npx 缓存里记录的那条依赖声明。
function Get-NpxEntry {
  $spec = '@deepseek-ai/dsh@latest'
  $npxRoot = Join-Path $env:LOCALAPPDATA 'npm-cache\_npx'
  if (Test-Path -LiteralPath $npxRoot) {
    foreach ($pkg in Get-ChildItem -LiteralPath $npxRoot -Filter 'package.json' -Recurse -Depth 1 -ErrorAction SilentlyContinue) {
      try {
        $json = Get-Content -LiteralPath $pkg.FullName -Raw | ConvertFrom-Json
        $dep = $json.dependencies.'@deepseek-ai/dsh'
        if ($dep) { $spec = "@deepseek-ai/dsh@$dep"; break }
      } catch { }
    }
  }
  $npx = Get-Command npx.cmd -ErrorAction SilentlyContinue
  if (-not $npx) { $npx = Get-Command npx -ErrorAction SilentlyContinue }
  if (-not $npx) { return $null }
  [pscustomobject]@{
    Kind       = 'shim'
    Command    = $npx.Source
    PrefixArgs = @('-y', $spec)
    Display    = "npx $spec（需要联网下载）"
    BinPath    = $null
  }
}

# ── 环境检查 ────────────────────────────────────────────────────────────────
$node  = Get-NodeExe
$entry = Get-DshEntry -NodeExe $node

Write-Title 'DeepSeek Harness'
Write-Host  '  浏览器 GUI 启动器'
Write-Host  ''

if (-not $node -and -not $entry) {
  Write-Fail '没有找到 Node，也没有找到 dsh。'
  Write-Host ''
  Write-Host '看起来还没安装（或安装目录被移动了）。重新运行安装程序即可：'
  Write-Host "  `"$installRoot\setup.cmd`""
  Write-Host ''
  Write-Host '也可以直接安装到本目录：'
  Write-Host "  npm install --prefix `"$installRoot\app`" @deepseek-ai/dsh"
  if (-not $Diagnose -and [Environment]::UserInteractive) {
    Write-Host ''
    Read-Host '按回车键关闭窗口' | Out-Null
  }
  exit 1
}

if (-not $entry) {
  $entry = Get-NpxEntry
  if ($entry) { Write-Warn2 '没有找到本地 dsh，将用 npx 下载一份（首次会比较慢）。' }
}

if (-not $entry) {
  Write-Fail '找到了 Node，但没有找到 dsh。'
  Write-Host ''
  Write-Host '重新运行安装程序，或手动装一份：'
  Write-Host "  npm install --prefix `"$installRoot\app`" @deepseek-ai/dsh"
  if (-not $Diagnose -and [Environment]::UserInteractive) {
    Write-Host ''
    Read-Host '按回车键关闭窗口' | Out-Null
  }
  exit 1
}

# ── 工作目录 ────────────────────────────────────────────────────────────────
if (-not $Workspace) { $Workspace = $env:USERPROFILE }
if (-not (Test-Path -LiteralPath $Workspace)) {
  if ($Diagnose) {
    Write-Warn2 "工作目录不存在（诊断模式不创建）：$Workspace"
  } else {
    try {
      New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
      Write-Note "已创建默认工作区：$Workspace"
    } catch {
      Write-Warn2 "工作目录不存在且创建失败：$Workspace"
      $Workspace = $env:USERPROFILE
      Write-Warn2 "改用：$Workspace"
    }
  }
}

# ── 组装命令 ────────────────────────────────────────────────────────────────
$dshArgs = @('web', '--port', "$Port")
if ($NoBrowser) { $dshArgs += '--no-open' }

$allArgs = @($entry.PrefixArgs) + $dshArgs
$pretty  = ($allArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '

$portBusy = Test-TcpPort -Port $Port

Write-Host "  dsh    ：$($entry.Display)"
Write-Host "  Node   ：$(if ($node) { $node } else { '（由 shim 自带）' })"
Write-Host "  工作区 ：$Workspace"
Write-Host "  地址   ：http://127.0.0.1:$Port/"
Write-Host "  端口   ：$(if ($portBusy) { '已有进程在监听（不会重复启动）' } else { '空闲' })"
Write-Host "  命令   ：$($entry.Command) $pretty"
Write-Host ''

if ($Diagnose) {
  Write-Note '浏览器会自动打开（带 token 的启动 URL，由 dsh 自己打印和交接）。'
  Write-Note '关闭启动后的控制台窗口即停止 DSH。'
  Write-Host ''
  Write-Ok '[诊断模式] 检查通过，未启动任何进程。'
  exit 0
}

# ── 端口检查：已经在跑就只开浏览器 ──────────────────────────────────────────
if ($portBusy) {
  Write-Warn2 "端口 $Port 上已经有一个 DeepSeek Harness 在运行。"
  Write-Host  '不再启动第二个实例，直接打开浏览器。'
  Write-Note  '如果浏览器显示未授权，说明当前浏览器没有那份 cookie，'
  Write-Note  '请回到原来那个已经打开的 DSH 标签页继续用。'
  Write-Host  ''
  Write-Host "  地址：http://127.0.0.1:$Port/"
  Start-Process "http://127.0.0.1:$Port/"
  exit 0
}

Write-Note '浏览器会自动打开（带 token 的启动 URL，由 dsh 自己打印和交接）。'
Write-Note '没打开的话，手动访问上面打印出来的 dsh web: 那一行地址。'
Write-Note '关闭本窗口即停止 DSH。'

# ── 启动 ────────────────────────────────────────────────────────────────────
Write-Host ''
Push-Location -LiteralPath $Workspace
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
  & $entry.Command @allArgs
  $code = $LASTEXITCODE
} catch {
  Write-Fail "启动失败：$($_.Exception.Message)"
  $code = 1
} finally {
  Pop-Location
  $sw.Stop()
}

Write-Host ''
if ($code -ne 0) {
  Write-Fail "DeepSeek Harness 退出，退出码 $code（运行了 $([int]$sw.Elapsed.TotalSeconds) 秒）。"
  if ($sw.Elapsed.TotalSeconds -lt 30) {
    Write-Host ''
    Write-Host '常见原因：'
    Write-Host "  - profile 目录有问题或插件报错：$env:USERPROFILE\.dsh\profiles\web"
    Write-Host "  - 端口 $Port 被别的程序占用（请看上面报错里的 EADDRINUSE）"
    Write-Host '  - ~\.dsh 没有写权限，或磁盘空间不足'
    Write-Host '先用诊断模式确认入口没问题：'
    Write-Host "  `"$PSCommandPath`" -Diagnose"
  }
  if ([Environment]::UserInteractive) {
    Write-Host ''
    Read-Host '按回车键关闭窗口' | Out-Null
  }
} else {
  Write-Ok 'DeepSeek Harness 已停止。'
}

exit $code
