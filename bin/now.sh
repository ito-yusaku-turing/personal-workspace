#!/usr/bin/env bash
# いま取り組んでいる workstream を、projects/README.md の「取り組み中」「待ち・保留」の順に出す。
# どちらにも載っていない進行中の workstream は「未分類」として出す。
#
#   bin/now.sh [-f] [絞り込みの文字列]
#     -f  状態の行を切り詰めない
#     文字列を渡すと、パス（project-id/workstream/名前）にそれを含むものだけに絞る
set -euo pipefail
source "$(dirname "$0")/lib/workstream.sh"

while getopts 'fh' opt; do
  case "$opt" in
    f) WS_WIDTH=0 ;;
    *) sed -n '2,8s/^# \{0,1\}//p' "$0"; exit 0 ;;
  esac
done
shift $((OPTIND - 1))
filter="${1:-}"

index="$PROJECTS_DIR/README.md"
[[ -f "$index" ]] || { echo "projects/README.md がありません" >&2; exit 1; }

# 見出し（## <名前>）の下にある「- [パス](./パス): メモ」を「パス<TAB>メモ」で出す
section() {
  awk -v want="## $1" '
    /^## / { on = ($0 == want); next }
    on && /^- \[/ {
      path = $0; sub(/^- \[[^]]*\]\(\.\//, "", path); sub(/\).*/, "", path)
      memo = $0; sub(/^- \[[^]]*\]\([^)]*\):? */, "", memo)
      print path "\t" memo
    }' "$index"
}

listed=""
print_section() {
  local title="$1" rows path memo
  rows="$(section "$title")"
  [[ -z "$rows" ]] && return 0
  local out=""
  while IFS=$'\t' read -r path memo; do
    listed+="$path"$'\n'
    [[ -n "$filter" && "$path" != *"$filter"* ]] && continue
    if [[ ! -f "$PROJECTS_DIR/$path" ]]; then
      out+="  ! $path が見つかりません（done/ に移した？）"$'\n'
      continue
    fi
    out+="$(ws_print_long "$path" "$memo")"$'\n'
  done <<<"$rows"
  [[ -n "$out" ]] && printf '== %s ==\n%s\n' "$title" "$out"
  return 0
}

print_section "取り組み中"
print_section "待ち・保留"

unlisted=""
while read -r rel; do
  [[ -z "$rel" ]] && continue
  grep -qxF "$rel" <<<"$listed" && continue
  [[ -n "$filter" && "$rel" != *"$filter"* ]] && continue
  unlisted+="$(ws_print_long "$rel")"$'\n'
done <<<"$(ws_active)"
[[ -n "$unlisted" ]] && printf '== 未分類（projects/README.md に載っていない）==\n%s' "$unlisted"
exit 0
