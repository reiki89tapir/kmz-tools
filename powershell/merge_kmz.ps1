#!/usr/bin/env pwsh
# merge_kmz.ps1 — 複数の KMZ を結合し、Google マイマップ用に最適化（PowerShell 版）
# ----------------------------------------------------------------------------
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$OUT_KMZ,

  [Parameter(Mandatory = $true, Position = 1, ValueFromRemainingArguments = $true)]
  [string[]]$INPUT_KMZ
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($INPUT_KMZ.Count -lt 1) {
  Write-Host "Usage: pwsh -File merge_kmz.ps1 OUTPUT.kmz INPUT1.kmz [INPUT2.kmz …]"
  Write-Host "Usage: pwsh -File merge_kmz.ps1 merged.kmz dir/25*.kmz"
  exit 1
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

$WORK_DIR  = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
$null = New-Item -ItemType Directory -Path $WORK_DIR | Out-Null
try {
  $MERGED_KML = Join-Path $WORK_DIR 'doc.kml'
  $LAYER_NAME = [IO.Path]::GetFileName($OUT_KMZ)

  # ------- 交互要素パレット（[色, 名称, 色, 名称, …] ; ABGR 8桁） -------
  $PALETTE = @(
    "ff0000ff","赤",
    "ff00ff00","緑",
    "ffff0000","青",
    "ff00ffff","黄",
    "ffff00ff","マゼンタ",
    "ffffff00","シアン",
    "ff7f7f7f","グレー",
    "ff7f0000","暗赤",
    "ff007f00","暗緑",
    "ff00007f","暗青",
    "ff4e1c80","葡萄色",
    "ff1c349b","煉瓦色",
    "ff1c5ed9","橙色",
    "ff3caef0","玉蜀黍色",
    "ff39dbf9","菜の花色",
    "ff25797f","鶯色",
    "ff388b5d","若竹色",
    "ff3c702a","常磐色",
    "ff635e22","青緑",
    "ff985222","群青色",
    "ff7b1b1f","紺青",
    "ffb33364","菫色",
    "ff2f354b","焦茶",
    "ff5b2db6","紅紫",
    "ff5661f1","珊瑚朱色",
    "ff2585e9","橙色",
    "ff45c5f3","山吹色",
    "ff3eeefb","檸檬色",
    "ff3eb6af","抹茶色",
    "ff4db384","若葉色",
    "ff5c9c3d","緑青色",
    "ffa5943a","浅葱色",
    "ffcd8238","縹色",
    "ffa7433e","花色",
    "ffac2794","京紫",
    "ff495775","灰茶",
    "ffb193ea","桃色",
    "ff9da6e5","珊瑚色",
    "ff87d0f8","杏色",
    "ff88ddf5","卵色",
    "ff97fffe","若菜色",
    "ffa2f0e6","若芽色",
    "ffa9e1c8","柳色",
    "ffadcd93","白緑",
    "fff1e9bb","水色",
    "fff7bfa7","勿忘草色",
    "ffd8a6a1","藤色",
    "ffd593c8","紅藤色",
    "ffa4abba","鳩羽鼠",
    "ffffffff","白",
    "ffbdbdbd","銀鼠",
    "ff757575","鼠色",
    "ff424242","濃鼠",
    "ff000000","黒"
  )

  function PaletteCount { return [int]($PALETTE.Count / 2) }
  function ColorAt([int]$i) { return $PALETTE[$i*2] }
  function NameAt([int]$i)  { return $PALETTE[$i*2+1] }

  # UTF-8 の見かけ幅（ASCII=1、非ASCII=2 の概算）
  function Get-DisplayWidth([string]$s) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($s)
    $i=0; $w=0
    while ($i -lt $bytes.Length) {
      $b = $bytes[$i]
      if     ($b -lt 0x80)                   { $w+=1; $i+=1 }
      elseif ($b -ge 0xC0 -and $b -le 0xDF) { $w+=2; $i+=2 }
      elseif ($b -ge 0xE0 -and $b -le 0xEF) { $w+=2; $i+=3 }
      elseif ($b -ge 0xF0 -and $b -le 0xF7) { $w+=2; $i+=4 }
      else { $i+=1 }
    }
    return $w
  }

  # 見本表示（ABGR→RGB に変換し 24bit Truecolor で出力、列を揃える）
  function Show-ColorSamples {
    $total  = PaletteCount
    $maxw   = 0
    for ($i=0; $i -lt $total; $i++) {
      $label = "[{0}: {1}]" -f ($i+1), (NameAt $i)
      $w = Get-DisplayWidth $label
      if ($w -gt $maxw) { $maxw = $w }
    }
    $gap = 2
    $perRow = 10
    Write-Host "[INFO] 色の見本（$total 色。表示は 24bit Truecolor、背景は黒を想定）"

    $col = 0
    $esc = [char]27
    for ($i=0; $i -lt $total; $i++) {
      $hex = ColorAt $i
      $name = NameAt $i
      $r = [Convert]::ToInt32($hex.Substring(6,2),16)
      $g = [Convert]::ToInt32($hex.Substring(4,2),16)
      $b = [Convert]::ToInt32($hex.Substring(2,2),16)
      $idx = $i + 1
      if ($idx -eq $total) { $r=255; $g=255; $b=255 } # 最後（黒）は白文字で
      $label = "[{0}: {1}]" -f $idx, $name
      $w = Get-DisplayWidth $label
      $pad = $maxw - $w + ($(if($col -eq ($perRow-1)) {0} else {$gap}))
      if ($pad -lt 0) { $pad = 0 }
      Write-Host "$esc[38;2;${r};${g};${b}m$label$esc[0m" -NoNewline
      Write-Host (" " * $pad) -NoNewline
      $col++
      if ($col -eq $perRow) { Write-Host ""; $col = 0 }
    }
    if ($col -ne 0) { Write-Host "" }
    Write-Host ""
  }

  @"
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>$LAYER_NAME</name>
"@ | Set-Content -LiteralPath $MERGED_KML -Encoding UTF8

  $color_idx = 0

  # ------- 見本表示と開始色の確認（1番目の KMZ に適用する色を選択） -------
  $total_colors = PaletteCount
  if (-not [Console]::IsInputRedirected) {
    Show-ColorSamples
    $first_basename = [IO.Path]::GetFileName($INPUT_KMZ[0])
    while ($true) {
      $ans = Read-Host ("1番目のKMZ（{0}）に使う開始色インデックスを入力してください (1-{1}、Enterで1)" -f $first_basename, $total_colors)
      if ([string]::IsNullOrWhiteSpace($ans)) { $start_idx = 1; break }
      elseif ($ans -match '^\d+$' -and [int]$ans -ge 1 -and [int]$ans -le $total_colors) { $start_idx = [int]$ans; break }
      else { Write-Host "1〜$total_colors の数値を入力してください。" }
    }
    $color_idx = $start_idx - 1
    Write-Host ("[INFO] 開始色: [{0}: {1}] ({2})" -f $start_idx, (NameAt ($start_idx-1)), (ColorAt ($start_idx-1)))
  } else {
    Write-Host "[INFO] 非対話モードのため開始色は既定値 [1: $(NameAt 0)] を使用します。"
    $color_idx = 0
  }
  # ---------------------------------------------------------------------------

  foreach ($kmz in $INPUT_KMZ) {
    if (-not (Test-Path -LiteralPath $kmz)) {
      Write-Host "[WARN] not found: $kmz"
      continue
    }

    # KMZ のフルパスから拡張子 .kmz を除いた「ファイル名のみ」を取得する
    $RAW = [IO.Path]::GetFileNameWithoutExtension($kmz)

    # 先頭から最初の「_」までを取り除く
    # 例: 2205060502_partFileName.kmz -> partFileName
    $ROUTE_NAME = ($RAW -replace '^[^_]*_', '')

    $TMP = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
    $null = New-Item -ItemType Directory -Path $TMP | Out-Null
    try {
      [IO.Compression.ZipFile]::ExtractToDirectory($kmz, $TMP)
      $SRC_KML = Join-Path $TMP 'doc.kml'
      if (-not (Test-Path -LiteralPath $SRC_KML)) {
        Write-Host "[WARN] doc.kml missing in $kmz"
        continue
      }

      $idx_mod = $color_idx % $total_colors
      $COLOR   = ColorAt $idx_mod
      $STYLE_ID = "routeStyle$color_idx"

      # 1) スタイル定義を先に出力
@"
    <Style id="$STYLE_ID">
      <LineStyle>
        <color>$COLOR</color>
        <width>4</width>
      </LineStyle>
    </Style>
"@ | Add-Content -LiteralPath $MERGED_KML -Encoding UTF8

      # 2) Placemark 部分を処理（<Document> 内だけ取り出し、Style/name/styleUrl を除去しつつ挿入）
      $insideDoc = $false
      $skipStyle = $false
      $lines = (Get-Content -LiteralPath $SRC_KML -Raw) -split "`n"
      foreach ($line in $lines) {
        $l = $line.TrimEnd("`r")

        if ($l -match '<Document[ >]') { $insideDoc = $true; continue }
        if ($l -match '</Document>')    { $insideDoc = $false }
        if (-not $insideDoc) { continue }

        if ($skipStyle) {
          if ($l -match '</Style>') { $skipStyle = $false }
          continue
        }
        if ($l -match '<Style') { $skipStyle = $true; continue }

        if ($l -match '^\s*<name>.*</name>\s*$')      { continue }
        if ($l -match '^\s*<styleUrl>.*</styleUrl>\s*$') { continue }

        if ($l -match '<Placemark[ >]') {
          Add-Content -LiteralPath $MERGED_KML -Value $l -Encoding UTF8
          Add-Content -LiteralPath $MERGED_KML -Value ("        <name>{0}</name>" -f $ROUTE_NAME) -Encoding UTF8
          Add-Content -LiteralPath $MERGED_KML -Value ("        <styleUrl>#{0}</styleUrl>" -f $STYLE_ID) -Encoding UTF8
          continue
        }

        Add-Content -LiteralPath $MERGED_KML -Value $l -Encoding UTF8
      }

      Write-Host ("[OK] merged {0} with color {1}" -f ([IO.Path]::GetFileName($kmz)), $COLOR)
      $color_idx++
    }
    finally {
      if (Test-Path -LiteralPath $TMP) { Remove-Item -LiteralPath $TMP -Recurse -Force }
    }
  }

@"
  </Document>
</kml>
"@ | Add-Content -LiteralPath $MERGED_KML -Encoding UTF8

  # doc.kml を zip 化（作成先は $WORK_DIR の外にする）
  $zipTemp = Join-Path ([IO.Path]::GetTempPath()) (([IO.Path]::GetRandomFileName()) + ".zip")
  if (Test-Path -LiteralPath $zipTemp) { Remove-Item -LiteralPath $zipTemp -Force }
  [IO.Compression.ZipFile]::CreateFromDirectory($WORK_DIR, $zipTemp)

  Move-Item -LiteralPath $zipTemp -Destination $OUT_KMZ -Force
  Write-Host "[DONE] created $OUT_KMZ"
}
finally {
  if (Test-Path -LiteralPath $WORK_DIR) { Remove-Item -LiteralPath $WORK_DIR -Recurse -Force }
}
