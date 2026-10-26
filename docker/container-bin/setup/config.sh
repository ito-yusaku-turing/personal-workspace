#!/usr/bin/env bash
# ====================================================================================
# 個人設定ファイルの雛形を配置する
#
#   配置先はコンテナ HOME 配下の個人設定ディレクトリ
#   （= ホストの $USER_HOME_DIR/<PERSONAL_CONFIG_DIR_NAME>/、git 管理外）。
#     agent-preferences.md   エージェントの自律範囲の個人設定
#     setup-state.conf       セットアップ項目の「使わない」宣言
#
#   使い方:
#     setup/config.sh            未配置のものだけ雛形をコピーし、状態を表示する
#     setup/config.sh status     配置状況だけを表示する
#
#   **既にあるファイルは絶対に上書きしない**（個人の設定を壊さないため）。
#   雛形の側が更新されても、既存ファイルには反映しない。差分を見たいときは
#   status が雛形へのパスを出すので、自分で比べて必要な行だけ取り込む。
#
#   docker/bin/setup.sh（ホスト側）も同じ配置を行うが、あちらはホスト専用のため
#   devbox の中からは実行できない。同じことをコンテナ内から行うのがこのスクリプト。
# ====================================================================================
set -uo pipefail
_self=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")
_self_dir=$(dirname "$_self")
# shellcheck source=../lib/common.sh
. "$_self_dir/../lib/common.sh"
# 失敗しうる検査を続けたいので -e は外す（中断すべき失敗は die で明示する）
set +e

usage() {
	sed -n '3,/^# =\{10,\}/p' "$_self" | sed -e '$d' -e 's/^# \{0,1\}//'
	exit 1
}

# 雛形 → 配置先。既存は触らない
place() {
	local example="$1" dest="$2" label="$3"
	if [[ ! -f $example ]]; then
		warn "$label: 雛形が見つかりません（${example}）"
		return 1
	fi
	if [[ -f $dest ]]; then
		ok "$label: 既にあります（変更しません）"
		note "  $dest"
		note "  雛形: $example"
		return 0
	fi
	mkdir -p "$(dirname "$dest")" || die "$(dirname "$dest") を作成できません"
	cp "$example" "$dest" || die "$dest へコピーできません"
	ok "$label: 雛形を配置しました"
	note "  $dest"
	return 0
}

show_status() {
	local f
	for f in "$AGENT_PREFS_DEST" "$SETUP_STATE_DEST"; do
		if [[ -f $f ]]; then
			printf '  %-24s %s\n' "$(basename "$f")" "あり     $f"
		else
			printf '  %-24s %s\n' "$(basename "$f")" "未配置   → docker/container-bin/setup/config.sh"
		fi
	done
}

case "${1-place}" in
	place)
		place "$AGENT_PREFS_EXAMPLE" "$AGENT_PREFS_DEST" "エージェント設定"
		place "$SETUP_STATE_EXAMPLE" "$SETUP_STATE_DEST" "セットアップ宣言"
		info ""
		note "  どちらも「既定から外れたいことだけ」を書くファイルです。初期値はすべて「特になし」。"
		note "  書き方: docs/agent-preferences.md / docker/config/setup-state.example.conf"
		;;
	status)
		show_status
		;;
	-h | --help | help) usage ;;
	*) die "不明なサブコマンド: ${1-}（--help を参照）" ;;
esac
