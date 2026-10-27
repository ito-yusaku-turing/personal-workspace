# bin/now.sh と bin/list-workstream.sh の共通部。source して使う。

# 文字数で切り詰めるため、UTF-8 のロケールにする
export LC_ALL=C.UTF-8

PW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECTS_DIR="$PW_ROOT/projects"

# 状態の 1 行の表示幅（文字数）。0 なら切り詰めない
WS_WIDTH="${WS_WIDTH:-70}"

# workstream の冒頭から「- 開始:」の日付を取り出す
ws_started() {
  sed -n 's/^- 開始: *\([0-9-]*\).*/\1/p' "$1" | head -n1
}

# workstream の冒頭から状態の 1 行を取り出す。
# 「- 状態:」か「- **完了**」のうち、先に出てくる行を使う
ws_status() {
  local line
  line="$(grep -m1 -E '^- (状態:|\*\*完了)' "$1" || true)"
  line="${line#- }"
  line="${line#状態: }"
  line="${line//\*\*/}"
  if [[ "$WS_WIDTH" -gt 0 && "${#line}" -gt "$WS_WIDTH" ]]; then
    line="${line:0:WS_WIDTH}…"
  fi
  printf '%s' "$line"
}

# 1 件を表示する。引数は projects/ からの相対パス
ws_print() {
  local rel="$1" file="$PROJECTS_DIR/$1" name
  name="$(basename "$rel" .md)"
  printf '  %-28s (%s〜) %s\n' "$name" "$(ws_started "$file")" "$(ws_status "$file")"
}

# 1 件を複数行で表示する（project も出す）。引数は projects/ からの相対パスと、任意のメモ
ws_print_long() {
  local rel="$1" memo="${2:-}" file="$PROJECTS_DIR/$1"
  printf '  %s/%s  (%s〜)\n' "${rel%%/*}" "$(basename "$rel" .md)" "$(ws_started "$file")"
  printf '    状態: %s\n' "$(ws_status "$file")"
  [[ -n "$memo" ]] && printf '    メモ: %s\n' "$memo"
  return 0
}

# 進行中の workstream（done/ にないもの）を、projects/ からの相対パスで列挙する
ws_active() {
  (cd "$PROJECTS_DIR" && find . -path './*/workstream/*.md' -not -path '*/done/*' \
    | sed 's|^\./||' | awk -F/ 'NF == 3' | sort)
}

# 完了した workstream（workstream/done/ の直下）を列挙する
ws_done() {
  (cd "$PROJECTS_DIR" && find . -path './*/workstream/done/*.md' \
    | sed 's|^\./||' | awk -F/ 'NF == 4' | sort)
}
