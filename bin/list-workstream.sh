#!/usr/bin/env bash
# workstream を project ごとに一覧する。
#
#   bin/list-workstream.sh [-a] [-f] [project-id ...]
#     -a  完了したもの（workstream/done/）も出す
#     -f  状態の行を切り詰めない
#     project-id を渡すと、その project だけに絞る（前方一致）
set -euo pipefail
source "$(dirname "$0")/lib/workstream.sh"

show_done=0
while getopts 'afh' opt; do
  case "$opt" in
    a) show_done=1 ;;
    f) WS_WIDTH=0 ;;
    *) sed -n '2,8s/^# \{0,1\}//p' "$0"; exit 0 ;;
  esac
done
shift $((OPTIND - 1))

# 第 1 引数の project が、残りの引数（絞り込み）のどれかに前方一致するか。絞り込みが無ければ常に真
matches() {
  local p="$1"; shift
  [[ $# -eq 0 ]] && return 0
  for f in "$@"; do [[ "$p" == "$f"* ]] && return 0; done
  return 1
}

found=0
for dir in "$PROJECTS_DIR"/*/; do
  project="$(basename "$dir")"
  matches "$project" "$@" || continue
  active="$(ws_active | grep "^$project/" || true)"
  done_list=""
  [[ $show_done -eq 1 ]] && done_list="$(ws_done | grep "^$project/" || true)"
  [[ -z "$active" && -z "$done_list" ]] && continue
  found=1
  echo "[$project]"
  [[ -n "$active" ]] && while read -r rel; do ws_print "$rel"; done <<<"$active"
  if [[ -n "$done_list" ]]; then
    echo "  -- 完了 --"
    while read -r rel; do ws_print "$rel"; done <<<"$done_list"
  fi
done

[[ $found -eq 0 ]] && echo "該当する workstream はありません"
exit 0
