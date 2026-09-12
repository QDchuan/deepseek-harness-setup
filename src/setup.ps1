<#
.SYNOPSIS
  DeepSeek Harness 一键安装器（Windows，无需管理员权限）。

.DESCRIPTION
  给不熟悉命令行、机器上也没装 Node 的人用的安装程序。双击 setup.cmd 之后它会：

    [1/6] 检查环境（系统架构、磁盘空间、安装目录可写性）
    [2/6] 准备 Node.js：机器上已有 >= 22 的直接复用，否则下载官方便携版
          解压到 <安装目录>\runtime\node（只动用户目录，不需要管理员）
    [3/6] 用 npm 把 DeepSeek Harness 装到 <安装目录>\app
          （npm 缓存也放在安装目录里，不污染全局，卸载时一起删掉）
    [4/6] 安装启动器到 <安装目录>\launcher，并把默认工作区写进去
    [5/6] 创建桌面 / 开始菜单快捷方式，注册「应用和功能」里的卸载项
    [6/6] 直接启动 DSH（浏览器自动打开）

  重复运行是安全的：已装的部分会复用，dsh 会升级到最新版。

.PARAMETER InstallDir
  安装根目录，默认 %LOCALAPPDATA%\DeepSeekHarness。

.PARAMETER Workspace
  DSH 会话的默认工作目录（agent 的工作区根），会写进启动器。
  默认 %USERPROFILE%\Documents\DeepSeekHarness。

.PARAMETER NodeVersion
  没有可用 Node 时下载哪个版本，默认 v22.23.2（Node 22 LTS）。

.PARAMETER DshSpec
  装哪个 npm 包/版本，默认 @deepseek-ai/dsh@latest。

.PARAMETER Registry
  npm 源。默认用本机 npm 配置；安装失败时自动换 https://registry.npmmirror.com 重试一次。

.PARAMETER NodeZip
  离线安装：直接使用本机已有的 node-vXX-win-x64.zip，不联网下载。

.PARAMETER ForcePortableNode
  忽略系统里已有的 Node，强制使用安装目录里的便携版。

.EXAMPLE
  .\setup.ps1
  默认安装并启动。

.EXAMPLE
  .\setup.ps1 -InstallDir D:\DSH -Workspace D:\code -NoLaunch
  装到 D 盘、默认工作区 D:\code、装完不启动。

.EXAMPLE
  .\setup.ps1 -DryRun
  只报告将要做什么，不下载、不写入。

.NOTES
  卸载：运行 <安装目录>\卸载.cmd，或从「设置 → 应用 → 已安装的应用」里卸载。
#>
[CmdletBinding()]
param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'DeepSeekHarness'),
  [string]$Workspace = (Join-Path $env:USERPROFILE 'Documents\DeepSeekHarness'),
  [string]$NodeVersion = 'v22.23.2',
  [string]$DshSpec = '@deepseek-ai/dsh@latest',
  [string]$Registry = '',
  [string]$NodeZip = '',
  [switch]$ForcePortableNode,
  [switch]$NoShortcuts,
  [switch]$NoLaunch,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$SetupVersion = '1.0.0'
$MinNodeMajor = 22
$NpmMirror = 'https://registry.npmmirror.com'
$SourceRoot = $PSScriptRoot                      # 仓库里的 src\
$RepoSrcLauncher = Join-Path $SourceRoot 'launcher'

# ── 输出helper ──────────────────────────────────────────────────────────────
function Write-Banner([string]$Text) { Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Step([string]$Num, [string]$Text) { Write-Host ''; Write-Host "[$Num] $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "    $Text" -ForegroundColor Green }
function Write-Info([string]$Text) { Write-Host "    $Text" -ForegroundColor DarkGray }
function Write-Warn2([string]$Text) { Write-Host "    $Text" -ForegroundColor Yellow }
function Write-Err2([string]$Text)  { Write-Host "    $Text" -ForegroundColor Red }
function Write-Cmd([string]$Text)  { Write-Host "    > $Text" -ForegroundColor Magenta }

function Pause-IfInteractive {
  if (-not $DryRun -and [Environment]::UserInteractive) {
    Write-Host ''
    try { Read-Host '按回车键关闭窗口' | Out-Null } catch { }
  }
}

# 文本文件一律写成 UTF-8 with BOM：Windows PowerShell 5.1 与记事本都能正确显示中文。
function Write-Utf8BomFile {
  param([string]$Path, [string]$Content)
  $utf8Bom = New-Object System.Text.UTF8Encoding($true)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8Bom)
}

function Get-PowerShellExe {
  $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) { return $cmd.Source }
  $pf = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
  if (Test-Path -LiteralPath $pf) { return $pf }
  return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
}

function Get-NodeMajor {
  param([string]$Exe)
  try {
    $raw = & $Exe --version 2>$null
    if ($raw -match 'v(\d+)\.') { return [int]$Matches[1] }
  } catch { }
  return 0
}

# 找一个系统里已有的 node.exe（PATH + 常见安装位置）。
function Find-SystemNode {
  foreach ($name in 'node.exe', 'node') {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
      $major = Get-NodeMajor $cmd.Source
      if ($major -gt 0) { return [pscustomobject]@{ Exe = $cmd.Source; Major = $major } }
    }
  }
  foreach ($p in @(
      (Join-Path $env:ProgramFiles 'nodejs\node.exe'),
      (Join-Path $env:LOCALAPPDATA 'Programs\nodejs\node.exe'))) {
    if (Test-Path -LiteralPath $p) {
      $major = Get-NodeMajor $p
      if ($major -gt 0) { return [pscustomobject]@{ Exe = $p; Major = $major } }
    }
  }
  return $null
}

# ── 下载：按「已有 node → curl.exe → Invoke-WebRequest → BITS」依次尝试 ─────
$DownloadScript = @'
const fs = require('fs');
const [url, out] = process.argv.slice(2);
fetch(url)
  .then(async (r) => {
    if (!r.ok) { throw new Error('HTTP ' + r.status); }
    const buf = Buffer.from(await r.arrayBuffer());
    fs.writeFileSync(out, buf);
    console.log('OK ' + buf.length);
  })
  .catch((e) => { console.error('ERR ' + e.message); process.exit(1); });
'@

function Invoke-Download {
  param([string]$Url, [string]$OutFile, [string]$NodeExe, [string]$TempDir)

  if ($NodeExe) {
    # 注意：必须存成 .cjs —— 里面用了 require()，而 .mjs 会被当成 ES 模块拒绝。
    $script = Join-Path $TempDir 'download.cjs'
    if (-not (Test-Path -LiteralPath $script)) { Set-Content -LiteralPath $script -Value $DownloadScript -Encoding ASCII }
    Write-Cmd "node 下载 $Url"
    & $NodeExe $script $Url $OutFile
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $OutFile) -and (Get-Item -LiteralPath $OutFile).Length -gt 0) { return $true }
  }

  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if ($curl -and $curl.Source) {
    Write-Cmd "curl 下载 $Url"
    if ([Environment]::UserInteractive) {
      & $curl.Source -L --fail --progress-bar --retry 2 --output $OutFile $Url
    } else {
      & $curl.Source -L --fail --silent --show-error --retry 2 --output $OutFile $Url
    }
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $OutFile) -and (Get-Item -LiteralPath $OutFile).Length -gt 0) { return $true }
  }

  try {
    Write-Cmd "PowerShell 下载 $Url"
    $old = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
      Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 300
    } finally { $ProgressPreference = $old }
    if ((Test-Path -LiteralPath $OutFile) -and (Get-Item -LiteralPath $OutFile).Length -gt 0) { return $true }
  } catch {
    Write-Info "PowerShell 下载失败：$($_.Exception.Message)"
  }

  try {
    Write-Cmd "BITS 下载 $Url"
    Start-BitsTransfer -Source $Url -Destination $OutFile -ErrorAction Stop
    if ((Test-Path -LiteralPath $OutFile) -and (Get-Item -LiteralPath $OutFile).Length -gt 0) { return $true }
  } catch {
    Write-Info "BITS 下载失败：$($_.Exception.Message)"
  }

  return $false
}

function Get-NodeZipFromWeb {
  param([string]$Version, [string]$Arch, [string]$CachePath, [string]$NodeExe, [string]$TempDir)
  $file = "node-$Version-win-$Arch.zip"
  $urls = @(
    "https://registry.npmmirror.com/-/binary/node/$Version/$file",
    "https://npmmirror.com/mirrors/node/$Version/$file",
    "https://nodejs.org/dist/$Version/$file"
  )
  foreach ($url in $urls) {
    if (Test-Path -LiteralPath $CachePath) { Remove-Item -LiteralPath $CachePath -Force -ErrorAction SilentlyContinue }
    if (Invoke-Download -Url $url -OutFile $CachePath -NodeExe $NodeExe -TempDir $TempDir) {
      $size = (Get-Item -LiteralPath $CachePath).Length
      if ($size -gt 10MB) { return $true }
      Write-Warn2 "下载到的文件太小（$([int]($size/1KB)) KB），换个源重试。"
    }
  }
  return $false
}

# ── 主流程 ──────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ' DeepSeek Harness 一键安装' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "  安装位置：$InstallDir"
Write-Host "  默认工作区：$Workspace"
Write-Host '  不需要管理员权限，所有文件都在你的用户目录里。'
if ($DryRun) { Write-Host ''; Write-Host '  [dry-run] 只检查，不下载、不写入、不创建快捷方式。' -ForegroundColor Yellow }

$transcriptStarted = $false
try {
  # ── [1/6] 环境检查 ────────────────────────────────────────────────────────
  Write-Step '1/6' '检查环境'

  $arch = switch -Wildcard ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64'  { 'x64'; break }
    'ARM64'  { 'arm64'; break }
    'x86'    { throw '这是 32 位系统，DeepSeek Harness 需要 64 位 Windows。' }
    default  { 'x64' }
  }
  Write-Ok "系统架构：$arch"

  $psMajor = $PSVersionTable.PSVersion.Major
  Write-Ok "PowerShell：$($PSVersionTable.PSVersion)"

  $existingManifest = Join-Path $InstallDir 'dsh-setup.json'
  $isUpgrade = Test-Path -LiteralPath $existingManifest
  if ($isUpgrade) { Write-Ok '检测到已有安装，本次将复用并升级。' }

  if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $InstallDir, (Join-Path $InstallDir 'logs'), (Join-Path $InstallDir 'cache') | Out-Null
  }

  # 磁盘空间（需要 ~1.5GB：Node ~120MB + 依赖 ~400MB + 缓存）
  $qualifier = Split-Path $InstallDir -Qualifier
  try {
    $free = (Get-PSDrive -Name $qualifier.TrimEnd(':')).Free
    if ($free -and $free -lt 2GB) { Write-Warn2 "剩余空间只有 $([int]($free/1MB)) MB，建议先清理磁盘。" }
    else { Write-Ok "磁盘剩余空间：$([int]($free/1MB)) MB" }
  } catch { }

  $logPath = Join-Path $InstallDir ("logs\setup-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
  if (-not $DryRun) {
    try { Start-Transcript -Path $logPath -Append | Out-Null; $transcriptStarted = $true; Write-Info "安装日志：$logPath" } catch { }
  }

  # ── [2/6] Node.js ────────────────────────────────────────────────────────
  Write-Step '2/6' '准备 Node.js'
  $nodeExe = $null
  $nodeMode = 'system'
  $nodeVersionText = ''
  $runtimeDir = Join-Path $InstallDir 'runtime\node'
  $portableNode = Join-Path $runtimeDir 'node.exe'

  # $probeNode 只用于「借它联网下载」（node 的 TLS 比系统 curl/PS 更省事），
  # $systemNode 才是「决定要不要复用它」的那一个。
  $probeNode = Find-SystemNode
  $systemNode = $null
  if (-not $ForcePortableNode) { $systemNode = $probeNode }

  if ($systemNode -and $systemNode.Major -ge $MinNodeMajor) {
    $nodeExe = $systemNode.Exe
    $nodeVersionText = (& $nodeExe --version)
    Write-Ok "复用系统里已有的 Node：$nodeVersionText（$nodeExe）"
    Write-Info '（想强制用安装目录里的便携版 Node，加 -ForcePortableNode）'
  } elseif (Test-Path -LiteralPath $portableNode) {
    $nodeMode = 'portable'
    $nodeExe = $portableNode
    $nodeVersionText = (& $nodeExe --version)
    Write-Ok "使用安装目录里的 Node：$nodeVersionText"
  } else {
    if ($systemNode) {
      Write-Warn2 "系统里的 Node 是 $($systemNode.Major) 版，太旧（需要 $MinNodeMajor 以上），改装便携版。"
    } elseif ($probeNode) {
      Write-Info "按 -ForcePortableNode 要求忽略系统里的 Node $($probeNode.Major) 版，改用便携版。"
    } else {
      Write-Info '这台机器上没找到 Node.js，开始下载官方便携版（约 35MB，不用管理员权限）。'
    }

    $cacheZip = Join-Path $InstallDir "cache\node-$NodeVersion-win-$arch.zip"
    $tempDir = Join-Path $InstallDir 'cache\tmp'
    if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $tempDir | Out-Null }

    $haveZip = $false
    if ($NodeZip) {
      if (Test-Path -LiteralPath $NodeZip) {
        $cacheZip = $NodeZip
        $haveZip = $true
        Write-Ok "使用你指定的本地压缩包：$NodeZip"
      } else {
        throw "指定的 node 压缩包不存在：$NodeZip"
      }
    } elseif (Test-Path -LiteralPath $cacheZip) {
      $haveZip = $true
      Write-Ok "使用上次下载的缓存：$cacheZip"
    }

    if ($DryRun) {
      Write-Info "[dry-run] 将下载 $NodeVersion ($arch) 并解压到 $runtimeDir"
    } else {
      if (-not $haveZip) {
        if (-not (Get-NodeZipFromWeb -Version $NodeVersion -Arch $arch -CachePath $cacheZip -NodeExe $probeNode.Exe -TempDir $tempDir)) {
          throw "下载 Node.js 失败。请检查网络（或用手机热点重试），也可以自己下载 https://nodejs.org/dist/$NodeVersion/node-$NodeVersion-win-$arch.zip 后加参数 -NodeZip <文件路径> 重跑安装。"
        }
        Write-Ok "下载完成：$([int]((Get-Item -LiteralPath $cacheZip).Length/1MB)) MB"
      }

      Write-Info '解压中……'
      $extractDir = Join-Path $tempDir 'node-extract'
      if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force }
      New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

      $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
      if ($tar -and $tar.Source) {
        & $tar.Source -xf $cacheZip -C $extractDir
      } else {
        Expand-Archive -LiteralPath $cacheZip -DestinationPath $extractDir -Force
      }

      $inner = Get-ChildItem -LiteralPath $extractDir -Directory | Select-Object -First 1
      if (-not $inner) { throw "解压出来的内容不对：$extractDir" }
      if (Test-Path -LiteralPath $runtimeDir) { Remove-Item -LiteralPath $runtimeDir -Recurse -Force }
      New-Item -ItemType Directory -Force -Path (Split-Path $runtimeDir -Parent) | Out-Null
      Move-Item -LiteralPath $inner.FullName -Destination $runtimeDir

      $nodeExe = $portableNode
      $nodeMode = 'portable'
      if (-not (Test-Path -LiteralPath $nodeExe)) { throw "便携版 Node 解压后找不到 node.exe：$nodeExe" }
      $nodeVersionText = (& $nodeExe --version)
      Write-Ok "便携版 Node 就绪：$nodeVersionText"
    }
  }

  # ── [3/6] 安装 dsh ───────────────────────────────────────────────────────
  Write-Step '3/6' "安装 DeepSeek Harness（$DshSpec）"
  $appDir = Join-Path $InstallDir 'app'
  $dshBin = Join-Path $appDir 'node_modules\@deepseek-ai\dsh\lib\bin.js'
  $npmCache = Join-Path $InstallDir 'cache\npm'

  if ($DryRun) {
    Write-Info "[dry-run] 将执行：npm install --prefix `"$appDir`" $DshSpec"
  } else {
    $npm = $null
    if ($nodeMode -eq 'portable') {
      $npm = Join-Path $runtimeDir 'npm.cmd'
    } else {
      # 用 npm.cmd（不要用 npm.ps1：某些环境下它转参数会出问题）
      $npmDir = Split-Path $nodeExe -Parent
      $candidate = Join-Path $npmDir 'npm.cmd'
      if (Test-Path -LiteralPath $candidate) { $npm = $candidate }
      else { $npm = (Get-Command npm.cmd -ErrorAction SilentlyContinue).Source }
    }
    if (-not $npm -or -not (Test-Path -LiteralPath $npm)) { throw "找不到 npm.cmd（node 目录：$(Split-Path $nodeExe -Parent)）" }

    $npmArgs = @(
      'install', '--prefix', $appDir, $DshSpec,
      '--no-audit', '--no-fund', '--loglevel=notice',
      '--cache', $npmCache,
      '--logs-dir', (Join-Path $InstallDir 'logs')
    )
    if ($Registry) { $npmArgs += @('--registry', $Registry) }

    Write-Info '下载并安装依赖（第一次大约 200MB，视网速可能要几分钟）……'
    Write-Cmd "$npm install --prefix `"$appDir`" $DshSpec"
    Push-Location $InstallDir
    try { & $npm @npmArgs } finally { Pop-Location }
    $npmCode = $LASTEXITCODE

    if ($npmCode -ne 0 -and -not $Registry) {
      Write-Warn2 '默认 npm 源安装失败，改用国内镜像重试一次……'
      $npmArgs += @('--registry', $NpmMirror)
      Write-Cmd "npm install ... --registry $NpmMirror"
      Push-Location $InstallDir
      try { & $npm @npmArgs } finally { Pop-Location }
      $npmCode = $LASTEXITCODE
    }
    if ($npmCode -ne 0) {
      throw @"
npm 安装失败（退出码 $npmCode）。
    日志：$(Join-Path $InstallDir 'logs')
    常见原因：网络不通/被墙、安全软件拦截 npm 写文件、磁盘空间不足。
    手动重试：
      cd "$InstallDir"
      npm install --prefix "$appDir" $DshSpec --registry $NpmMirror
"@
    }
    if (-not (Test-Path -LiteralPath $dshBin)) { throw "安装完了但找不到 dsh 入口：$dshBin" }

    $dshVersion = (& $nodeExe $dshBin --version 2>$null | Select-Object -First 1)
    if (-not $dshVersion) { throw "dsh 装好了但运行不起来：$nodeExe $dshBin --version" }
    Write-Ok "DeepSeek Harness 就绪：$dshVersion"
  }

  # ── [4/6] 安装启动器 ─────────────────────────────────────────────────────
  Write-Step '4/6' '安装启动器'
  $launcherDir = Join-Path $InstallDir 'launcher'
  $launcherPs1 = Join-Path $launcherDir 'Start-DeepSeekHarness.ps1'

  if ($DryRun) {
    Write-Info "[dry-run] 将把启动器安装到 $launcherDir"
  } else {
    foreach ($f in 'Start-DeepSeekHarness.ps1', 'start-dsh.cmd', 'dsh.ico') {
      if (-not (Test-Path -LiteralPath (Join-Path $RepoSrcLauncher $f))) { throw "安装包不完整，缺少：$(Join-Path $RepoSrcLauncher $f)" }
    }
    New-Item -ItemType Directory -Force -Path $launcherDir | Out-Null

    # 启动器正文：UTF-8 BOM
    $launcherText = Get-Content -LiteralPath (Join-Path $RepoSrcLauncher 'Start-DeepSeekHarness.ps1') -Raw
    # 把默认工作区写进标记之间
    $escaped = $Workspace.Replace('`', '``').Replace('$', '`$')
    $pattern = '(?ms)(# >>> 默认工作区.*?>>>\r?\n).*?(\r?\n[ \t]*# <<< 默认工作区)'
    $replacement = "`$1  [string]`$Workspace = `"$escaped`",`$2"
    if ($launcherText -notmatch $pattern) { throw '启动器模板里找不到默认工作区的标记，安装包可能被改坏了。' }
    $launcherText = [regex]::Replace($launcherText, $pattern, $replacement)
    Write-Utf8BomFile -Path $launcherPs1 -Content $launcherText

    Copy-Item -LiteralPath (Join-Path $RepoSrcLauncher 'start-dsh.cmd') -Destination (Join-Path $launcherDir 'start-dsh.cmd') -Force

    # 图标：优先按当前安装的 dsh 前端 favicon 现场生成，失败就用安装包里带的
    $iconTarget = Join-Path $launcherDir 'dsh.ico'
    $iconOk = $false
    $iconMaker = Join-Path $RepoSrcLauncher 'tools\New-DshIcon.ps1'
    $favicon = Join-Path $appDir 'node_modules\@deepseek-ai\dsh-web-frontend\dist\favicon.svg'
    if ((Test-Path -LiteralPath $iconMaker) -and (Test-Path -LiteralPath $favicon)) {
      try {
        & (Get-PowerShellExe) -NoProfile -ExecutionPolicy Bypass -File $iconMaker -SvgPath $favicon -OutPath $iconTarget 2>$null | Out-Null
        $iconOk = Test-Path -LiteralPath $iconTarget
      } catch { $iconOk = $false }
    }
    if (-not $iconOk) {
      Copy-Item -LiteralPath (Join-Path $RepoSrcLauncher 'dsh.ico') -Destination $iconTarget -Force
      Write-Info '使用安装包里自带的图标。'
    } else {
      Write-Info '已按当前版本的前端图标生成 dsh.ico。'
    }
    if (Test-Path -LiteralPath (Join-Path $RepoSrcLauncher 'tools')) {
      New-Item -ItemType Directory -Force -Path (Join-Path $launcherDir 'tools') | Out-Null
      # 注意：这里必须用 -Path（-LiteralPath 不展开 * 通配符）
      Copy-Item -Path (Join-Path $RepoSrcLauncher 'tools\*') -Destination (Join-Path $launcherDir 'tools') -Force
    }
    Write-Ok "启动器：$launcherPs1"
    Write-Ok "默认工作区已写入：$Workspace"
  }

  # ── [5/6] 快捷方式与卸载项 ───────────────────────────────────────────────
  Write-Step '5/6' '创建快捷方式'
  $shortcutPaths = @()
  $uninstallCmd = Join-Path $InstallDir '卸载.cmd'
  $uninstallPs1 = Join-Path $SourceRoot 'uninstall.ps1'

  if ($DryRun) {
    Write-Info '[dry-run] 桌面 + 开始菜单快捷方式、卸载入口、应用列表注册项'
  } else {
    # 卸载器：装进安装目录，并且让 卸载.cmd 指向安装目录里的这一份
    # （不要把路径指到临时目录或用户解压的那个文件夹——那些随时可能被删掉）
    $pwshExe = Get-PowerShellExe
    $uninstallLocal = Join-Path $InstallDir 'uninstall.ps1'
    if (Test-Path -LiteralPath $uninstallPs1) {
      Write-Utf8BomFile -Path $uninstallLocal -Content (Get-Content -LiteralPath $uninstallPs1 -Raw)
    }
    if (-not (Test-Path -LiteralPath $uninstallLocal)) { throw "安装包不完整，缺少 uninstall.ps1：$uninstallPs1" }

    $uninstallText = @"
@echo off
rem DeepSeek Harness uninstaller shim (ASCII only).
setlocal
"$pwshExe" -NoProfile -ExecutionPolicy Bypass -File "$uninstallLocal" -InstallDir "$InstallDir" %*
exit /b %errorlevel%
"@
    Set-Content -LiteralPath $uninstallCmd -Value $uninstallText -Encoding ASCII

    if (-not $NoShortcuts) {
      $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcherPs1`""
      $shell = New-Object -ComObject WScript.Shell
      $iconLocation = if (Test-Path -LiteralPath (Join-Path $launcherDir 'dsh.ico')) { (Join-Path $launcherDir 'dsh.ico') + ',0' } else { '' }

      $shortcutPaths += (Join-Path ([Environment]::GetFolderPath('Desktop')) 'DeepSeek Harness.lnk')
      $shortcutPaths += (Join-Path ([Environment]::GetFolderPath('Programs')) 'DeepSeek Harness.lnk')
      if (Test-Path -LiteralPath $uninstallCmd) {
        $shortcutPaths += (Join-Path ([Environment]::GetFolderPath('Programs')) '卸载 DeepSeek Harness.lnk')
      }

      foreach ($path in $shortcutPaths) {
        $dir = Split-Path $path -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $lnk = $shell.CreateShortcut($path)
        if ([System.IO.Path]::GetFileName($path) -like '卸载*') {
          $lnk.TargetPath       = $uninstallCmd
          $lnk.Arguments        = ''
          $lnk.WorkingDirectory = $InstallDir
          $lnk.Description      = '卸载 DeepSeek Harness'
        } else {
          $lnk.TargetPath       = $pwshExe
          $lnk.Arguments        = $arguments
          $lnk.WorkingDirectory = $launcherDir
          $lnk.Description      = 'DeepSeek Harness —— 启动浏览器 GUI（dsh web）'
        }
        if ($iconLocation) { $lnk.IconLocation = $iconLocation }
        $lnk.WindowStyle = 1
        $lnk.Save()
        Write-Ok $path
      }
    } else {
      Write-Info '（按 -NoShortcuts 要求跳过快捷方式）'
    }

    # 「设置 → 应用 → 已安装的应用」里的卸载项（只写 HKCU，不需要管理员）
    try {
      $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeekHarness'
      New-Item -Path $key -Force | Out-Null
      $sizeKb = 0
      try { $sizeKb = [int](((Get-ChildItem -LiteralPath $InstallDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1KB) } catch { }
      Set-ItemProperty -Path $key -Name DisplayName     -Value 'DeepSeek Harness'
      Set-ItemProperty -Path $key -Name DisplayVersion  -Value $(if ($dshVersion) { "$dshVersion" } else { $SetupVersion })
      Set-ItemProperty -Path $key -Name Publisher       -Value 'deepseek-harness-setup'
      Set-ItemProperty -Path $key -Name InstallLocation -Value $InstallDir
      Set-ItemProperty -Path $key -Name UninstallString -Value "`"$uninstallCmd`""
      Set-ItemProperty -Path $key -Name DisplayIcon     -Value $(if ($iconLocation) { $iconLocation } else { $uninstallCmd })
      Set-ItemProperty -Path $key -Name NoModify        -Value 1 -Type DWord
      Set-ItemProperty -Path $key -Name NoRepair        -Value 1 -Type DWord
      if ($sizeKb -gt 0) { Set-ItemProperty -Path $key -Name EstimatedSize -Value $sizeKb -Type DWord }
      Write-Ok '已注册到「设置 → 应用」，可以直接在那里卸载。'
    } catch {
      Write-Warn2 "注册卸载信息失败（不影响使用）：$($_.Exception.Message)"
    }

    # 安装清单：启动器据此定位 Node 与 dsh（只写相对路径，整个目录可以整体搬走）
    $manifest = [ordered]@{
      schema           = 1
      setupVersion     = $SetupVersion
      installedAt      = (Get-Date).ToString('s')
      installRoot      = $InstallDir
      nodeMode         = $nodeMode
      nodeRelativePath = $(if ($nodeMode -eq 'portable') { 'runtime\node\node.exe' } else { '' })
      nodeVersion      = $nodeVersionText
      appRelativePath  = 'app\node_modules\@deepseek-ai\dsh\lib\bin.js'
      dshVersion       = "$dshVersion"
      workspace        = $Workspace
      port             = 3080
    }
    Write-Utf8BomFile -Path (Join-Path $InstallDir 'dsh-setup.json') -Content ($manifest | ConvertTo-Json -Depth 4)
    Write-Ok "安装清单：$(Join-Path $InstallDir 'dsh-setup.json')"
  }

  # ── [6/6] 启动 ───────────────────────────────────────────────────────────
  Write-Step '6/6' '启动 DeepSeek Harness'
  Write-Host ''
  Write-Host '  首次启动后，浏览器会自动打开 DSH 界面：' -ForegroundColor White
  Write-Host '   · 会先弹两个说明窗口，接着让你填 DeepSeek API 密钥' -ForegroundColor White
  Write-Host '     （在 https://platform.deepseek.com 申请，密钥只存本机凭据库）' -ForegroundColor White
  Write-Host '   · 关闭启动后的那个控制台窗口 = 停止 DSH' -ForegroundColor White
  Write-Host ''

  if ($DryRun) {
    Write-Ok '[dry-run] 检查通过，什么都没改。'
    exit 0
  }

  if ($transcriptStarted) { try { Stop-Transcript | Out-Null } catch { } }

  if ($NoLaunch) {
    Write-Ok '安装完成（按 -NoLaunch 要求没有启动）。'
    Write-Host "  双击桌面上的「DeepSeek Harness」即可启动。" -ForegroundColor Green
    Pause-IfInteractive
    exit 0
  }

  Write-Host '  正在启动……（这个窗口会一直开着，它就是 DSH 本体）' -ForegroundColor Green
  Write-Host ''
  $pwshExe = Get-PowerShellExe
  & $pwshExe -NoProfile -ExecutionPolicy Bypass -File $launcherPs1
  $launchCode = $LASTEXITCODE

  Write-Host ''
  if ($launchCode -eq 0) {
    Write-Ok 'DeepSeek Harness 已停止。桌面快捷方式随时可以再次启动。'
  } else {
    Write-Err2 "启动时出错（退出码 $launchCode）。"
    Write-Host "  诊断：`"$launcherPs1`" -Diagnose" -ForegroundColor White
    Write-Host "  日志：$InstallDir\logs" -ForegroundColor White
  }
  Pause-IfInteractive
  exit $launchCode
} catch {
  Write-Host ''
  Write-Err2 "安装失败：$($_.Exception.Message)"
  Write-Host ''
  Write-Host '可以这样排查：' -ForegroundColor White
  Write-Host '  · 确认能上网（浏览器能打开 https://registry.npmmirror.com）' -ForegroundColor White
  Write-Host "  · 看日志：$InstallDir\logs" -ForegroundColor White
  Write-Host '  · 重跑一次安装（已装的部分会复用，不会重复下载）' -ForegroundColor White
  Write-Host '  · 把日志内容发给作者' -ForegroundColor White
  if ($transcriptStarted) { try { Stop-Transcript | Out-Null } catch { } }
  Pause-IfInteractive
  exit 1
}
