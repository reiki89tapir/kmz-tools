<# ---------------------------------------------------------------------------
calcKML-selectKMZ.ps1

Usage: .\calcKML-selectKMZ.ps1 OUTPUT.kmz INPUT1.kmz [INPUT2.kmz …]

機能:
  1. 複数 KMZ を走査し、含まれる各 KML のサイズ(byte)とファイル名を一覧表示
  2. 「インデックス番号, サイズ（3桁カンマ区切り・右寄せ整列）, KMZ名:KMLパス」で表示
  3. 範囲指定(例: 1-3 7 10-12)、all、list、q を受け付ける
  4. 選択した KML に対応する KMZ（重複除去・順序維持）を merge_kmz.ps1 に渡す
  5. 合計容量を表示し、y で結合実行。N/Enter なら再選択（一覧は再表示しない）

備考:
  - KMZ は ZIP 互換のため、ZipArchive で直接読み取り（展開用の一時ディレクトリは使いません）
  - PowerShell 5.1 / 7 いずれでも動作を想定
--------------------------------------------------------------------------- #>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$OutputKmz,

    [Parameter(Mandatory = $true, Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$InputKmz
)

$ErrorActionPreference = 'Stop'

# ---- 依存: merge_kmz.ps1（同一ディレクトリ想定） ----
$ScriptDir = Split-Path -Parent $PSCommandPath
$Merger = Join-Path $ScriptDir 'merge_kmz.ps1'
if (-not (Test-Path $Merger)) {
    Write-Error "merge_kmz.ps1 が見つかりません: $Merger"
    exit 1
}

# ---- 数値フォーマット（3桁区切り） ----
function Format-Bytes([long]$n) {
    return $n.ToString('N0', [System.Globalization.CultureInfo]::InvariantCulture)
}

# ---- 範囲・単体指定の展開（重複除去・順序維持）----
function Expand-Selection {
    param(
        [string]$InputText,
        [int]$Max
    )
    $tokens = ($InputText -split '\s+') | Where-Object { $_ -ne '' }
    $out = New-Object System.Collections.Generic.List[int]
    $seen = New-Object System.Collections.Generic.HashSet[int]

    foreach ($t in $tokens) {
        if ($t -match '^(?<s>\d+)-(?<e>\d+)$') {
            $s = [int]$Matches['s']
            $e = [int]$Matches['e']
            if ($s -gt $e) { $tmp = $s; $s = $e; $e = $tmp }
            for ($i = $s; $i -le $e; $i++) {
                if ($i -ge 1 -and $i -le $Max) {
                    if ($seen.Add($i)) { [void]$out.Add($i) }
                }
            }
        }
        elseif ($t -match '^\d+$') {
            $i = [int]$t
            if ($i -ge 1 -and $i -le $Max) {
                if ($seen.Add($i)) { [void]$out.Add($i) }
            }
        }
        # 無効トークンは無視
    }
    return ,$out.ToArray()
}

# ---- KMZ -> KML 情報を収集 ----
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

$items = New-Object System.Collections.Generic.List[pscustomobject]

foreach ($kmz in $InputKmz) {
    if (-not (Test-Path $kmz)) {
        Write-Error "KMZ が見つかりません: $kmz"
        exit 1
    }
    $abs = (Resolve-Path $kmz).Path
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($abs)
    } catch {
        Write-Error "KMZ を開けませんでした: $abs"
        exit 1
    }

    foreach ($entry in $zip.Entries) {
        if ($entry.FullName -match '\.kml$') {
            $display = "{0}:{1}" -f ([System.IO.Path]::GetFileName($abs)), $entry.FullName
            $size = [long]$entry.Length  # uncompressed size
            $items.Add([pscustomobject]@{
                KmzPath   = $abs
                KmlPath   = $entry.FullName
                Size      = $size
                Display   = $display
            })
        }
    }
    $zip.Dispose()
}

if ($items.Count -eq 0) {
    Write-Error "KML が 1 つも見つかりませんでした。"
    exit 1
}

# ---- 一覧表示関数 ----
function Show-List {
    param([System.Collections.Generic.List[pscustomobject]]$Items)

    $formattedSizes = $Items | ForEach-Object { (Format-Bytes $_.Size) }
    $width = ($formattedSizes | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum

    $template = "{0,3}, {1," + $width + "}, {2}"
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $idx = $i + 1
        $sizeStr = $formattedSizes[$i]
        $disp = $Items[$i].Display
        Write-Host ($template -f $idx, $sizeStr, $disp)
    }
}

$showListNext = $true

while ($true) {
    if ($showListNext) {
        Show-List -Items $items
    }

    Write-Host
    $sel = Read-Host "選択（例: 1-3 7 10-12 / all / list / q）"

    switch -Regex ($sel) {
        '^q$' {
            Write-Host "終了します。"
            exit 0
        }
        '^list$' {
            $showListNext = $true
            continue
        }
        '^all$' {
            $selIndices = 1..$items.Count
        }
        default {
            $selIndices = Expand-Selection -InputText $sel -Max $items.Count
            if (-not $selIndices -or $selIndices.Count -eq 0) {
                Write-Host "有効なインデックスがありません。再入力してください。"
                $showListNext = $true
                continue
            }
        }
    }

    # 合計容量
    $sum = [long]0
    foreach ($i in $selIndices) {
        $sum += $items[$i - 1].Size
    }
    $sumFmt = Format-Bytes $sum
    Write-Host "選択された KML の合計容量: $sumFmt bytes"

    $ans = Read-Host "結合しますか？ [y/N]"
    if ($ans -match '^[yY]$') {
        # 対応 KMZ を重複除去（入力順維持）
        $uniqueKmz = New-Object System.Collections.Generic.List[string]
        $seen = New-Object System.Collections.Generic.HashSet[string]
        foreach ($i in $selIndices) {
            $kmzPath = $items[$i - 1].KmzPath
            if ($seen.Add($kmzPath)) {
                [void]$uniqueKmz.Add($kmzPath)
            }
        }

        # 表示（安全のため引用符で囲って見せる）
        $argsShown = @($Merger, $OutputKmz) + $uniqueKmz
        Write-Host "merge_kmz.ps1 を実行します:"
        Write-Host "  $($argsShown | ForEach-Object { '"' + $_ + '"' } | Join-String ' ')"

        # 実行
        & $Merger $OutputKmz @uniqueKmz
        Write-Host "完了しました。出力: $OutputKmz"
        exit 0
    }
    else {
        # 一覧は再表示しない
        $showListNext = $false
    }
}
