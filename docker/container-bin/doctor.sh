#!/usr/bin/env bash
# ====================================================================================
# devbox コンテナ内のツールとクレデンシャルを診断する
#
#   ホストからは docker/bin/doctor.sh を使う（このスクリプトを呼び出す）。
#   セットアップ項目はすべて任意。未設定でも開発環境は動く（該当機能だけが使えない）。
#
#   使い方:
#     docker/container-bin/doctor.sh              人間向けの一覧
#     docker/container-bin/doctor.sh --porcelain  機械可読（TSV / エージェント向け）
#
#   「未着手」と「使わないと決めた」の区別は lib/setup-state.sh が担う。
# ====================================================================================
set -uo pipefail
# 自身の実体パスを解決してから読み込む（シンボリックリンク経由の実行に対応する）
_self=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")
_self_dir=$(dirname "$_self")
# shellcheck source=lib/common.sh
. "$_self_dir/lib/common.sh"
# shellcheck source=lib/setup-state.sh
. "$_self_dir/lib/setup-state.sh"
# lib/common.sh が set -e を立てるが、診断は失敗しうる検査を並べるものなので外す
set +e

PORCELAIN=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--porcelain) PORCELAIN=1; shift ;;
		-h | --help)
			sed -n '3,/^# =\{10,\}/p' "$_self" | sed -e '$d' -e 's/^# \{0,1\}//'
			exit 1 ;;
		*) die "不明な引数: $1（--help を参照）" ;;
	esac
done

if (( PORCELAIN )); then
	setup_state_porcelain
	exit 0
fi

# ラベル列を表示幅で揃える（printf の %-Ns はバイト数で数えるため日本語がずれる）
row() {
	local label="$1" value="$2" chars bytes width pad
	chars=$(printf '%s' "$label" | wc -m)
	bytes=$(printf '%s' "$label" | LC_ALL=C wc -c)
	width=$(( chars + (bytes - chars) / 2 ))
	pad=$(( 20 - width ))
	if (( pad < 1 )); then pad=1; fi
	printf '  %s%*s%s\n' "$label" "$pad" "" "$value"
}
have() { command -v "$1" >/dev/null 2>&1; }

# セットアップ項目1件を人間向けに1行で表示する
row_item() {
	local item="$1" st state detail label
	st=$(setup_state_of "$item")
	state="${st%%$'\t'*}"
	detail="${st#*$'\t'}"
	label="${SETUP_LABEL[$item]}"
	case "$state" in
		ok)
			row "$label" "$detail" ;;
		missing)
			row "$label" "${SETUP_MISSING_LABEL[$item]:-未設定}   ${C_DIM}→ ${SETUP_HINT[$item]}${C_OFF}" ;;
		declined)
			# 使わないと宣言済み。催促せず、影響だけを添えて隠さずに見せる
			row "$label" "${C_DIM}使わない${detail:+ ($detail)}  ※${SETUP_IMPACT[$item]:-}${C_OFF}" ;;
		conflict)
			row "$label" "${C_YELLOW}宣言と不一致${C_OFF} ${C_DIM}${detail}${C_OFF}" ;;
		error)
			row "$label" "${C_YELLOW}エラー${C_OFF}   ${detail}" ;;
		*)
			row "$label" "?（${state}）" ;;
	esac
}

row "実行ユーザー" "$(id -un) ($(id -u):$(id -g))"

# ssh / ssh-keygen は $HOME ではなく getpwuid() の pw_dir を見る。両者がずれると
# 鍵も ~/.ssh/config も見つからなくなるため、ここで一致を確認する。
pw_dir=$(getent passwd "$(id -u)" | cut -d: -f6)
if [[ $pw_dir == "$HOME" ]]; then
	row "HOME / pw_dir" "一致     $HOME"
else
	row "HOME / pw_dir" "不一致!  HOME=$HOME pw_dir=$pw_dir → ssh が鍵を見つけられません"
fi

row "node / npm" "$(node --version 2>/dev/null || echo '?') / $(npm --version 2>/dev/null || echo '?')"
if have psql; then
	row "psql" "$(psql --version 2>/dev/null | head -1)"
fi

# セットアップ項目（宣言 × 探知）
for _item in "${SETUP_ITEMS_HUMAN[@]}"; do
	row_item "$_item"
done

# Claude Code はセットアップ項目ではなく、claude.sh が必要に応じて導入する
if have claude; then
	claude_ver=$(claude --version 2>/dev/null || echo 'あり')
	stamp_file="$HOME/.claude-last-updated"
	if [[ -f $stamp_file ]] && stamp=$(head -n1 "$stamp_file" 2>/dev/null) && [[ $stamp =~ ^[0-9]+$ ]]; then
		row "claude" "${claude_ver}（ネイティブ版 / 最終更新 $(date -d "@$stamp" '+%Y-%m-%d %H:%M')）"
	else
		row "claude" "${claude_ver}（ネイティブ版 / 更新記録なし）"
	fi
else
	row "claude" "未導入   → docker/bin/claude.sh が導入します"
fi

# gh のトークンに admin:public_key が付いていたら知らせる。
# 鍵の登録はブラウザで人間が行う方針なので、このスコープは不要。
_gh=$(setup_state_of gh-auth)
if [[ ${_gh#*$'\t'} == *admin:public_key* ]]; then
	warn "gh のトークンが admin:public_key を保持しています。方針では不要です。
       トークンを作り直す場合は docker/container-bin/setup/github.sh gh-login を参照。"
fi

# 宣言ファイルの綴り間違いは黙って無視すると気づけないため警告する
_unknown=$(setup_state_unknown_items)
if [[ -n $_unknown ]]; then
	warn "$SETUP_STATE_FILE に未知の項目名があります（無視されます）: $(printf '%s' "$_unknown" | tr '\n' ' ')
       このプロジェクトで使える項目名: ${SETUP_ITEMS[*]}"
fi
