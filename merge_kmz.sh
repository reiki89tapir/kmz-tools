#!/usr/bin/env bash
# merge_kmz.sh
# — 複数の KMZ を結合し、Google マイマップ用に最適化
# ----------------------------------------------------------------------------
# 主な変更点 (2025‑07‑23 c)
#   * ルート色が反映されず黒一色になる問題を修正。
#       1) <styleUrl> の既存行を削除してから新しいものを挿入。
#       2) <Style> 定義を <Placemark> より前に配置（My Maps の前方参照非対応対策）。
# ----------------------------------------------------------------------------
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 OUTPUT.kmz INPUT1.kmz [INPUT2.kmz …]" >&2
  echo "Usage: $0 merged.kmz dir/25*.kmz" >&2
  exit 1
fi

OUT_KMZ="$1"; shift
INPUT_KMZ=("$@")

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
MERGED_KML="$WORK_DIR/doc.kml"

LAYER_NAME="$(basename "$OUT_KMZ")"

# ------- 交互要素パレット（[色, 名称, 色, 名称, …] ; ABGR 8桁） -------
PALETTE=(
  "ff0000ff" "赤"
  "ff00ff00" "緑"
  "ffff0000" "青"
  "ff00ffff" "黄"
  "ffff00ff" "マゼンタ"
  "ffffff00" "シアン"
  "ff7f7f7f" "グレー"
  "ff7f0000" "暗赤"
  "ff007f00" "暗緑"
  "ff00007f" "暗青"
  "ff4e1c80" "葡萄色"
  "ff1c349b" "煉瓦色"
  "ff1c5ed9" "橙色"
  "ff3caef0" "玉蜀黍色"
  "ff39dbf9" "菜の花色"
  "ff25797f" "鶯色"
  "ff388b5d" "若竹色"
  "ff3c702a" "常磐色"
  "ff635e22" "青緑"
  "ff985222" "群青色"
  "ff7b1b1f" "紺青"
  "ffb33364" "菫色"
  "ff2f354b" "焦茶"
  "ff5b2db6" "紅紫"
  "ff5661f1" "珊瑚朱色"
  "ff2585e9" "橙色"
  "ff45c5f3" "山吹色"
  "ff3eeefb" "檸檬色"
  "ff3eb6af" "抹茶色"
  "ff4db384" "若葉色"
  "ff5c9c3d" "緑青色"
  "ffa5943a" "浅葱色"
  "ffcd8238" "縹色"
  "ffa7433e" "花色"
  "ffac2794" "京紫"
  "ff495775" "灰茶"
  "ffb193ea" "桃色"
  "ff9da6e5" "珊瑚色"
  "ff87d0f8" "杏色"
  "ff88ddf5" "卵色"
  "ff97fffe" "若菜色"
  "ffa2f0e6" "若芽色"
  "ffa9e1c8" "柳色"
  "ffadcd93" "白緑"
  "fff1e9bb" "水色"
  "fff7bfa7" "勿忘草色"
  "ffd8a6a1" "藤色"
  "ffd593c8" "紅藤色"
  "ffa4abba" "鳩羽鼠"
  "ffffffff" "白"
  "ffbdbdbd" "銀鼠"
  "ff757575" "鼠色"
  "ff424242" "濃鼠"
  "ff000000" "黒"
)

# ユーティリティ
palette_count() { echo $(( ${#PALETTE[@]} / 2 )); }          # ペア数（=色数）
color_at()      { local i=$1; echo "${PALETTE[$((i*2))]}"; } # i番目(0始まり)の色
name_at()       { local i=$1; echo "${PALETTE[$((i*2+1))]}"; } # i番目の名前

# UTF-8 の見かけ幅を概算（ASCII=1、非ASCII=2）で計算（Bash 3 互換、mapfile 不要）
utf8_display_width() {
  local s="$1"
  local -a arr=()
  # 各バイトを 16 進の 2 桁で 1 行ずつ読み込み、配列 arr に格納
  while IFS= read -r hex; do
    arr+=("$hex")
  done < <(printf '%s' "$s" | hexdump -v -e '1/1 "%02x\n"')

  local n=${#arr[@]}
  local i=0 w=0 b=0
  while (( i < n )); do
    b=$((16#${arr[i]}))
    if   (( b < 0x80 )); then ((w+=1)); ((i+=1))      # ASCII
    elif (( b >= 0xC0 && b <= 0xDF )); then ((w+=2)); ((i+=2))  # 2byte
    elif (( b >= 0xE0 && b <= 0xEF )); then ((w+=2)); ((i+=3))  # 3byte
    elif (( b >= 0xF0 && b <= 0xF7 )); then ((w+=2)); ((i+=4))  # 4byte
    else ((i+=1))
    fi
  done
  echo "$w"
}

# 見本表示（ABGR→RGB に変換し 24bit Truecolor で出力、列を揃える）
show_color_samples() {
  local total
  total=$(palette_count)

  # セル幅（見かけ幅）の最大値を算出
  local maxw=0 label w
  local i
  for ((i=0; i<total; i++)); do
    label="$(printf "[%d: %s]" $((i+1)) "$(name_at "$i")")"
    w=$(utf8_display_width "$label")
    (( w > maxw )) && maxw=$w
  done
  local gap=2               # 列間スペース
  local per_row=10          # 1行あたりの列数（例と同じ 10）
  echo "[INFO] 色の見本（${total}色。表示は 24bit Truecolor、背景は黒を想定）" >&2

  local col=0
  for ((i=0; i<total; i++)); do
    local hex name r g b idx pad
    hex="$(color_at "$i")"
    name="$(name_at "$i")"
    r=$((16#${hex:6:2}))
    g=$((16#${hex:4:2}))
    b=$((16#${hex:2:2}))
    idx=$((i+1))
    # [最後=黒] の見本は白文字で
    if (( idx == total )); then r=255; g=255; b=255; fi

    label="$(printf "[%d: %s]" "$idx" "$name")"
    w=$(utf8_display_width "$label")
    pad=$(( maxw - w + ( (col==per_row-1) ? 0 : gap ) ))
    (( pad < 0 )) && pad=0

    # 色を適用して表示（ラベルのみ着色、パディングは無色）
    printf "\033[38;2;%d;%d;%dm%s\033[0m%*s" "$r" "$g" "$b" "$label" "$pad" "" >&2

    ((col++))
    if (( col == per_row )); then
      echo >&2
      col=0
    fi
  done
  # 端数で改行
  (( col != 0 )) && echo >&2
  echo >&2
}
# ---------------------------------------------------------------------------

cat >"$MERGED_KML" <<KMLHDR
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>${LAYER_NAME}</name>
KMLHDR

color_idx=0

# ------- 見本表示と開始色の確認（1番目の KMZ に適用する色を選択） -------
if [[ -t 0 ]]; then
  show_color_samples
  total_colors=$(palette_count)
  # ここで 1番目入力ファイルの「ファイル名のみ」を取得して表示に使う
  first_basename="$(basename "${INPUT_KMZ[0]}")"
  while :; do
    read -r -p "1番目のKMZ（${first_basename}）に使う開始色インデックスを入力してください (1-${total_colors}、Enterで1): " ans
    if [[ -z "${ans:-}" ]]; then
      start_idx=1
      break
    elif [[ "$ans" =~ ^[0-9]+$ ]] && (( ans>=1 && ans<=total_colors )); then
      start_idx=$ans
      break
    else
      echo "1〜${total_colors} の数値を入力してください。" >&2
    fi
  done
  color_idx=$((start_idx-1))
  echo "[INFO] 開始色: [$start_idx: $(name_at $((start_idx-1)))] ($(color_at $((start_idx-1)))))" >&2
else
  echo "[INFO] 非対話モードのため開始色は既定値 [1: $(name_at 0)] を使用します。" >&2
  total_colors=$(palette_count)
  color_idx=0
fi
# ---------------------------------------------------------------------------

for kmz in "${INPUT_KMZ[@]}"; do
  if [[ ! -f "$kmz" ]]; then
    echo "[WARN] not found: $kmz" >&2
    continue
  fi

  # KMZ のフルパスから拡張子 .kmz を除いた「ファイル名のみ」を取得する
  RAW="$(basename "$kmz" .kmz)"
  
  # 先頭から最初の「_」(アンダースコア) までを取り除く
  # 例: 2205060502_partFileName.kmz -> partFileName.kmz
  # ※ ${VAR#PATTERN} は「先頭側で最短一致を削除」する Bash のパラメータ展開
  ROUTE_NAME="${RAW#*_}"

  TMP=$(mktemp -d)
  unzip -qq "$kmz" -d "$TMP"
  SRC_KML="$TMP/doc.kml"
  if [[ ! -f "$SRC_KML" ]]; then
    echo "[WARN] doc.kml missing in $kmz" >&2
    rm -rf "$TMP"
    continue
  fi

  idx_mod=$(( color_idx % total_colors ))
  COLOR="$(color_at "$idx_mod")"
  STYLE_ID="routeStyle${color_idx}"

  # 1) スタイル定義を先に出力
  cat >>"$MERGED_KML" <<STYLE
    <Style id="${STYLE_ID}">
      <LineStyle>
        <color>${COLOR}</color>
        <width>4</width>
      </LineStyle>
    </Style>
STYLE

  # 2) Placemark 部分を処理
  awk '
    /<Document[ >]/{insideDoc=1; next}
    /<\/Document>/{insideDoc=0}
    insideDoc' "$SRC_KML" | \
  sed -e '/<Style/,/<\/Style>/d' \
      -e '/^[[:space:]]*<name>.*<\/name>[[:space:]]*$/d' \
      -e '/^[[:space:]]*<styleUrl>.*<\/styleUrl>[[:space:]]*$/d' | \
  awk -v n="$ROUTE_NAME" -v sid="$STYLE_ID" '
    /<Placemark[ >]/{
      print;
      printf "        <name>%s</name>\n", n;
      printf "        <styleUrl>#%s</styleUrl>\n", sid;
      next;
    }
    {print}
  ' >>"$MERGED_KML"

  rm -rf "$TMP"
  echo "[OK] merged $(basename "$kmz") with color $COLOR" >&2
  ((color_idx++))
done

cat >>"$MERGED_KML" <<KMLFTR
  </Document>
</kml>
KMLFTR

(
  cd "$WORK_DIR"
  zip -q -9 merged.zip doc.kml
)

mv "$WORK_DIR/merged.zip" "$OUT_KMZ"

echo "[DONE] created $OUT_KMZ"
