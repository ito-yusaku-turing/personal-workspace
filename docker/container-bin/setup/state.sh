#!/usr/bin/env bash
# ====================================================================================
# セットアップ項目の「使わない」宣言を編集する（devbox コンテナの中で実行する）
#
#   使い方:
#     setup/state.sh list                    項目と実効状態を一覧する
#     setup/state.sh skip <項目> [理由]      その項目を使わないと宣言する
#     setup/state.sh unskip <項目>           宣言を取り消す
#
#   宣言はコンテナ HOME 配下の setup-state.conf に書かれる（git 管理外 / 開発者ごと）。
#   ここには「使わない」という宣言だけを書き、探知結果はキャッシュしない。
#   状態はエージェントも読む: docker/container-bin/doctor.sh --porcelain
# ====================================================================================
set -uo pipefail
_self=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")
_self_dir=$(dirname "$_self")
# shellcheck source=../lib/common.sh
. "$_self_dir/../lib/common.sh"
# shellcheck source=../lib/setup-state.sh
. "$_self_dir/../lib/setup-state.sh"
# lib/common.sh が set -e を立てるが、探知には失敗しうるものが含まれるので外す
set +e

usage() {
	sed -n '3,/^# =\{10,\}/p' "$_self" | sed -e '$d' -e 's/^# \{0,1\}//'
	exit 1
}

require_known_item() {
	local want="$1" k
	for k in "${SETUP_ITEMS[@]}"; do
		[[ $k == "$want" ]] && return 0
	done
	die "未知の項目: $want
       このプロジェクトで使える項目: ${SETUP_ITEMS[*]}
       （同梱していないツールの項目は最初から現れません。docker/config/project.conf の DEVBOX_WITH_*）"
}

require_declinable() {
	local want="$1"
	if [[ ${SETUP_DECLINABLE[$want]:-0} != 1 ]]; then
		die "$want は前提条件のため「使わない」を宣言できません。
       （docker/.env・イメージ・依存関係・アプリの環境変数ファイルは環境が動くための前提です）"
	fi
}

cmd_list() {
	local item st state detail decl
	# 見出しは %-Ns がバイト数で数えるため揃わない。表示幅で手で合わせてある
	printf '  項目           実効状態  宣言可  詳細\n'
	for item in "${SETUP_ITEMS[@]}"; do
		st=$(setup_state_of "$item")
		state="${st%%$'\t'*}"
		detail="${st#*$'\t'}"
		decl=$([[ ${SETUP_DECLINABLE[$item]} == 1 ]] && echo yes || echo no)
		printf '  %-14s %-9s %-7s %s\n' "$item" "$state" "$decl" "$detail"
	done
	info ""
	note "  宣言ファイル: $SETUP_STATE_FILE$([[ -f $SETUP_STATE_FILE ]] || printf ' (未作成)')"
}

cmd_skip() {
	local item="${1-}" reason
	[[ -n $item ]] || die "項目名が必要です（setup/state.sh skip <項目> [理由]）"
	shift
	reason="$*"
	require_known_item "$item"
	require_declinable "$item"

	mkdir -p "$(dirname "$SETUP_STATE_FILE")"
	if [[ ! -f $SETUP_STATE_FILE ]]; then
		{
			echo "# ====================================================================================="
			echo "# セットアップ項目の「使わない」宣言"
			echo "#   <項目>  skip  [理由]"
			echo "#   編集は setup/state.sh skip / unskip でも、直接でもよい。"
			echo "#   使える項目名: ${SETUP_ITEMS[*]}"
			echo "# ====================================================================================="
		} >"$SETUP_STATE_FILE"
	fi

	# 既存の同項目の行を落としてから追記する（重複させない）
	local tmp
	tmp=$(mktemp)
	awk -v it="$item" '
		{ line = $0; sub(/#.*/, "", line) }
		{ n = split(line, f, /[ \t]+/) }
		# 先頭の空白を除いた1語目が対象項目なら落とす
		{ key = (f[1] == "" ? f[2] : f[1]) }
		key == it { next }
		{ print }
	' "$SETUP_STATE_FILE" >"$tmp"
	printf '%-14s skip %s\n' "$item" "$reason" >>"$tmp"
	mv "$tmp" "$SETUP_STATE_FILE"

	ok "$item を「使わない」と宣言しました${reason:+（${reason}）}"
	if [[ -n ${SETUP_IMPACT[$item]-} ]]; then
		note "  影響: ${SETUP_IMPACT[$item]}"
	fi
	# 設定が既に存在する場合は conflict になることを伝える
	if [[ $(setup_state_of "$item" | cut -f1) == conflict ]]; then
		warn "この項目には設定が存在します。宣言と実態が食い違っています（doctor.sh が警告します）。"
	fi
}

cmd_unskip() {
	local item="${1-}" tmp
	[[ -n $item ]] || die "項目名が必要です（setup/state.sh unskip <項目>）"
	require_known_item "$item"
	[[ -f $SETUP_STATE_FILE ]] || { note "  宣言ファイルがありません（宣言なし）"; return 0; }

	tmp=$(mktemp)
	awk -v it="$item" '
		{ line = $0; sub(/#.*/, "", line) }
		{ n = split(line, f, /[ \t]+/) }
		{ key = (f[1] == "" ? f[2] : f[1]) }
		key == it { next }
		{ print }
	' "$SETUP_STATE_FILE" >"$tmp"
	mv "$tmp" "$SETUP_STATE_FILE"
	ok "$item の宣言を取り消しました"
}

cmd="${1-list}"
[[ $# -gt 0 ]] && shift
case "$cmd" in
	list) cmd_list "$@" ;;
	skip) cmd_skip "$@" ;;
	unskip) cmd_unskip "$@" ;;
	-h | --help | help) usage ;;
	*) die "不明なサブコマンド: ${cmd}（--help を参照）" ;;
esac
