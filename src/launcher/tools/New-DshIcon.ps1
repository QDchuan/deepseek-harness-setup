<#
.SYNOPSIS
  从 dsh 前端的 favicon.svg 生成 Windows 图标 dsh.ico。

.DESCRIPTION
  不依赖任何浏览器或外部库：只用 System.Drawing 把 SVG 里那唯一的 path
  （DeepSeek 鲸鱼，仅含 M/C/Z 绝对指令）解析成 GraphicsPath，画成
  「蓝底圆角方块 + 白色鲸鱼」的多尺寸 .ico（16/32/48/64/128/256，PNG 载荷）。

.EXAMPLE
  .\New-DshIcon.ps1 -SvgPath .\favicon.svg -OutPath .\dsh.ico
#>
[CmdletBinding()]
param(
  [string]$SvgPath = (Join-Path $PSScriptRoot 'favicon.svg'),
  [string]$OutPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dsh.ico'),
  [string]$Background = '#4D6BFE',
  [double]$LogoFraction = 0.62,
  [double]$CornerFraction = 0.225
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path -LiteralPath $SvgPath)) { throw "找不到 SVG：$SvgPath" }
$svg = Get-Content -LiteralPath $SvgPath -Raw
$match = [regex]::Match($svg, '(?<!i)d="([^"]+)"')
if (-not $match.Success) { throw "SVG 里没有找到 path 的 d 属性：$SvgPath" }
$data = $match.Groups[1].Value

# ── 解析 path（只支持 M / C / L / Z 的绝对形式，正是这个 logo 用到的子集）──────
$tokenRe = [regex]'[A-Za-z]|-?\d*\.?\d+(?:[eE][-+]?\d+)?'
$tokens = @($tokenRe.Matches($data) | ForEach-Object { $_.Value })

$shape = New-Object System.Drawing.Drawing2D.GraphicsPath
$shape.FillMode = [System.Drawing.Drawing2D.FillMode]::Winding
$i = 0
$cmd = ''
$curX = 0.0; $curY = 0.0
while ($i -lt $tokens.Count) {
  $tok = $tokens[$i]
  if ($tok -match '^[A-Za-z]$') {
    $cmd = $tok.ToUpperInvariant()
    $i++
    if ($tok -cmatch '[a-z]') { throw "这个 logo 里出现了相对指令 '$tok'，本脚本不支持。" }
    if ($cmd -eq 'Z') { $shape.CloseFigure(); $cmd = ''; continue }
  }
  switch ($cmd) {
    'M' {
      $curX = [double]$tokens[$i]; $curY = [double]$tokens[$i + 1]; $i += 2
      $shape.StartFigure()
      $cmd = 'L'   # SVG 语义：M 之后不带指令的坐标对按 L 处理
    }
    'L' {
      $x = [double]$tokens[$i]; $y = [double]$tokens[$i + 1]; $i += 2
      $shape.AddLine([float]$curX, [float]$curY, [float]$x, [float]$y)
      $curX = $x; $curY = $y
    }
    'C' {
      if ($i + 5 -ge $tokens.Count) { throw 'path 数据在 C 指令处提前结束。' }
      $x1 = [double]$tokens[$i]; $y1 = [double]$tokens[$i + 1]
      $x2 = [double]$tokens[$i + 2]; $y2 = [double]$tokens[$i + 3]
      $x = [double]$tokens[$i + 4]; $y = [double]$tokens[$i + 5]
      $i += 6
      $shape.AddBezier(
        [float]$curX, [float]$curY,
        [float]$x1, [float]$y1,
        [float]$x2, [float]$y2,
        [float]$x, [float]$y)
      $curX = $x; $curY = $y
    }
    default { throw "不支持的 path 指令：'$cmd'" }
  }
}

function New-RoundedRect {
  param([single]$Size, [single]$Radius)
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $Radius * 2
  $p.AddArc(0, 0, $d, $d, 180, 90)
  $p.AddArc($Size - $d, 0, $d, $d, 270, 90)
  $p.AddArc($Size - $d, $Size - $d, $d, $d, 0, 90)
  $p.AddArc(0, $Size - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

$bgColor = [System.Drawing.ColorTranslator]::FromHtml($Background)
$sizes = 16, 32, 48, 64, 128, 256
$images = @()

foreach ($size in $sizes) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    $tile = New-RoundedRect -Size ([single]$size) -Radius ([single]($size * $CornerFraction))
    $brush = New-Object System.Drawing.SolidBrush($bgColor)
    $g.FillPath($brush, $tile)

    # 50x50 的 viewBox 居中缩放到 size * LogoFraction
    $logo = $shape.Clone()
    $scale = ($size * $LogoFraction) / 50.0
    $m = New-Object System.Drawing.Drawing2D.Matrix
    $m.Scale([single]$scale, [single]$scale, [System.Drawing.Drawing2D.MatrixOrder]::Append)
    $m.Translate([single]($size / 2 - 25 * $scale), [single]($size / 2 - 25 * $scale), [System.Drawing.Drawing2D.MatrixOrder]::Append)
    $logo.Transform($m)
    $g.FillPath([System.Drawing.Brushes]::White, $logo)

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $images += [pscustomobject]@{ Size = $size; Data = $ms.ToArray() }

    $logo.Dispose(); $m.Dispose(); $brush.Dispose(); $tile.Dispose()
  } finally {
    $g.Dispose(); $bmp.Dispose()
  }
}

# ── 组装 ICO 容器（每张图一个 PNG 载荷）────────────────────────────────────
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([UInt16]0)                 # reserved
$bw.Write([UInt16]1)                 # type: icon
$bw.Write([UInt16]$images.Count)
$offset = 6 + 16 * $images.Count
foreach ($img in $images) {
  $dim = if ($img.Size -ge 256) { 0 } else { $img.Size }
  $bw.Write([byte]$dim); $bw.Write([byte]$dim)
  $bw.Write([byte]0); $bw.Write([byte]0)      # 调色板数、保留位
  $bw.Write([UInt16]1)                        # 色彩平面
  $bw.Write([UInt16]32)                       # 位深
  $bw.Write([UInt32]$img.Data.Length)
  $bw.Write([UInt32]$offset)
  $offset += $img.Data.Length
}
foreach ($img in $images) { $bw.Write($img.Data) }
$bw.Flush()

$outDir = Split-Path $OutPath -Parent
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
[System.IO.File]::WriteAllBytes($OutPath, $ms.ToArray())
$bw.Dispose(); $ms.Dispose(); $shape.Dispose()

Write-Host "已生成 $OutPath（$($images.Count) 个尺寸：$($sizes -join '/')，$((Get-Item -LiteralPath $OutPath).Length) 字节）"
