#!/usr/bin/env bash
# calcKML-selectKMZ.sh
# - 入力された KMZ ファイルから ファイル総容量を考慮して KML ファイルを選別する
# - 選別された KML ファイルを merge_kmz.sh に渡して結合する
# - OUTPUT.kmz に指定した出力ファイルは merge_kmz.sh で生成される
# ----------------------------------------------------------------------------
# 主な変更点 (2025‑07‑23 c)
# - 計算対象の KMZ を選択するためのインタラクティブなスクリプトを追加。
# ----------------------------------------------------------------------------

set -euo pipefail

die() {
  echo "Error: $*" 1>&2
  exit 1
}

usage() {
  echo "Usage: $0 OUTPUT.kmz INPUT1.kmz [INPUT2.kmz …]" >&2
  echo "Usage: $0 merged.kmz dir/25*.kmz" >&2
  exit 1
}

# 3桁区切り
format_number() {
  echo "$1" | awk '{
    s=$1; neg="";
    if (s ~ /^-/) { neg="-"; s=substr(s,2) }
    out="";
    while (length(s) > 3) {
      out="," substr(s, length(s)-2, 3) out;
      s=substr(s, 1, length(s)-3);
    }
    print neg s out
  }'
}

is_number() {
  case "$1" in
    ''|*[!0-9]*)
      return 1 ;;
    *)
      return 0 ;;
  esac
}

# 範囲・単体指定の展開（重複除去・最初の入力順維持）
expand_selection() {
  local input="$1"
  local max="$2"
  local token
  local -a out=()
  local seen=""

  for token in $input; do
    if echo "$token" | grep -Eq '^[0-9]+-[0-9]+$'; then
      local start="${token%-*}"
      local end="${token#*-}"
      if ! is_number "$start" || ! is_number "$end"; then
        continue
      fi
      if [ "$start" -gt "$end" ]; then
        local tmp="$start"
        start="$end"
        end="$tmp"
      fi
      local i="$start"
      while [ "$i" -le "$end" ]; do
        if [ "$i" -ge 1 ] && [ "$i" -le "$max" ]; then
          case " $seen " in
            *" $i "*) : ;;
            *)
              out+=("$i")
              seen="$seen $i"
              ;;
          esac
        fi
        i=$((i+1))
      done
    else
      if is_number "$token"; then
        local i="$token"
        if [ "$i" -ge 1 ] && [ "$i" -le "$max" ]; then
          case " $seen " in
            *" $i "*) : ;;
            *)
              out+=("$i")
              seen="$seen $i"
              ;;
          esac
        fi
      fi
    fi
  done

  echo "${out[*]-}"
}

print_list() {
  local count="${#KML_NAMES[@]}"

  local width=0
  local i=0
  while [ "$i" -lt "$count" ]; do
    local formatted
    formatted="$(format_number "${KML_SIZES[$i]}")"
    local len=${#formatted}
    if [ "$len" -gt "$width" ]; then
      width="$len"
    fi
    i=$((i+1))
  done

  i=0
  while [ "$i" -lt "$count" ]; do
    local idx=$((i+1))
    local size_fmt
    size_fmt="$(format_number "${KML_SIZES[$i]}")"
    printf "%3d, %*s, %s\n" "$idx" "$width" "$size_fmt" "${KML_NAMES[$i]}"
    i=$((i+1))
  done
}

[ "$#" -lt 2 ] && usage

OUTPUT="$1"; shift
[ -z "${OUTPUT-}" ] && usage
[ "$#" -lt 1 ] && usage

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MERGER="${SCRIPT_DIR}/merge_kmz.sh"
[ -x "$MERGER" ] || die "merge_kmz.sh が見つからないか実行できません: $MERGER"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

KML_SIZES=()
KML_NAMES=()
KML2KMZ=()
KMZ_PATHS=()

kmz_index=0
for kmz in "$@"; do
  [ -f "$kmz" ] || die "KMZ が見つかりません: $kmz"
  abs_kmz="$(cd "$(dirname "$kmz")" && pwd)/$(basename "$kmz")"
  KMZ_PATHS+=("$abs_kmz")

  outdir="$WORKDIR/kmz_$kmz_index"
  mkdir -p "$outdir"
  unzip -qq "$abs_kmz" -d "$outdir" || die "unzip 失敗: $abs_kmz"

  while IFS= read -r -d '' kml; do
    rel="${kml#$outdir/}"
    bytes="$(wc -c < "$kml" | tr -d '[:space:]')"
    disp="$(basename "$abs_kmz"):$rel"
    KML_SIZES+=("$bytes")
    KML_NAMES+=("$disp")
    KML2KMZ+=("$abs_kmz")
  done < <(find "$outdir" -type f -name '*.kml' -print0)

  kmz_index=$((kmz_index+1))
done

TOTAL_COUNT="${#KML_NAMES[@]}"
[ "$TOTAL_COUNT" -eq 0 ] && die "KML が 1 つも見つかりませんでした。"

show_list_next=1

while :; do
  if [ "$show_list_next" -eq 1 ]; then
    print_list
  fi

  echo
  printf "選択（例: 1-3 7 10-12 / all / list / q）> "
  read -r sel || exit 1

  case "$sel" in
    q)
      echo "終了します。"
      exit 0
      ;;
    list)
      show_list_next=1
      continue
      ;;
    all)
      sel_indices=""
      i=1
      while [ "$i" -le "$TOTAL_COUNT" ]; do
        sel_indices="$sel_indices $i"
        i=$((i+1))
      done
      sel_indices="${sel_indices# }"
      ;;
    *)
      sel_indices="$(expand_selection "$sel" "$TOTAL_COUNT")"
      if [ -z "${sel_indices-}" ]; then
        echo "有効なインデックスがありません。再入力してください。"
        show_list_next=1
        continue
      fi
      ;;
  esac

  sum=0
  for idx in $sel_indices; do
    arr_idx=$((idx-1))
    size="${KML_SIZES[$arr_idx]}"
    sum=$((sum + size))
  done

  sum_fmt="$(format_number "$sum")"
  echo "選択された KML の合計容量: ${sum_fmt} bytes"

  printf "結合しますか？ [y/N] "
  read -r ans || exit 1
  case "$ans" in
    [yY])
      # ---------- 修正ポイント: 配列で保持して安全に引き渡す ----------
      UNIQUE_KMZ=()
      seen_kmz=""
      for idx in $sel_indices; do
        arr_idx=$((idx-1))
        kmz_path="${KML2KMZ[$arr_idx]}"
        case " $seen_kmz " in
          *" $kmz_path "*) : ;;
          *)
            UNIQUE_KMZ+=("$kmz_path")
            seen_kmz="$seen_kmz $kmz_path"
            ;;
        esac
      done

      echo "merge_kmz.sh を実行します:"
      # 表示は %q で可視化（bash 3 でも利用可）
      printf '  %q' "$MERGER" "$OUTPUT"
      for p in "${UNIQUE_KMZ[@]}"; do
        printf ' %q' "$p"
      done
      echo

      "$MERGER" "$OUTPUT" "${UNIQUE_KMZ[@]}"
      echo "完了しました。出力: $OUTPUT"
      exit 0
      ;;
    *)
      show_list_next=0
      ;;
  esac
done
