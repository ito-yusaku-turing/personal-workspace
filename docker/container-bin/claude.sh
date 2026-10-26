#!/usr/bin/env bash
# ====================================================================================
# devbox コンテナ内で Claude Code を起動する
#
#   ホストからは docker/bin/claude.sh を使う（このスクリプトを呼び出す）。
#
#   **ネイティブ版のみを使う**（npm 版 @anthropic-ai/claude-code は使わない）。
#   導入先は $HOME/.local（= コンテナ HOME にマウントされたホスト側ディレクトリ）なので、
#   コンテナを作り直しても消えず、ログイン状態（$HOME/.claude）も保持される。
#
#   更新:
#     $HOME/.claude-last-updated に最後に更新確認した時刻（epoch 秒）を記録し、
#     そこから 04:00（コンテナのタイムゾーン）を跨いでいたら `claude update` を実行する。
#     1日1回に抑えることで、起動のたびにネットワークを叩かないようにしている。
#
#   権限:
#     既定で --dangerously-skip-permissions を付けて起動する。devbox はホストから
#     隔離されたコンテナで、書き込める範囲がマウントしたリポジトリとコンテナ HOME に
#     限られていることが前提。引数で権限系のオプションを渡した場合、または
#     DEVBOX_CLAUDE_SKIP_PERMISSIONS=0 の場合は付けない。
# ====================================================================================
set -euo pipefail
# 自身の実体パスを解決してから読み込む（シンボリックリンク経由の実行に対応する）
# shellcheck source=lib/common.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")/lib/common.sh"

UPDATE_STAMP="$HOME/.claude-last-updated"
INSTALLER_URL="https://claude.ai/install.sh"
UPDATE_TZ="${DEVBOX_TZ:-UTC}"

# 直近に過ぎた 04:00（UPDATE_TZ）を epoch 秒で返す
last_update_boundary() {
	local now today_0400
	now=$(date +%s)
	today_0400=$(TZ="$UPDATE_TZ" date -d "today 04:00" +%s)
	if (( now >= today_0400 )); then
		printf '%s' "$today_0400"
	else
		TZ="$UPDATE_TZ" date -d "yesterday 04:00" +%s
	fi
}

read_stamp() {
	local v=""
	if [[ -f $UPDATE_STAMP ]]; then
		v=$(head -n1 "$UPDATE_STAMP" 2>/dev/null || true)
	fi
	if [[ ! $v =~ ^[0-9]+$ ]]; then
		v=0
	fi
	printf '%s' "$v"
}

write_stamp() { date +%s >"$UPDATE_STAMP"; }

# ------------------------------------------------------------------------------------
# 導入 / 更新
# ------------------------------------------------------------------------------------
if ! command -v claude >/dev/null 2>&1; then
	info "Claude Code（ネイティブ版）を導入します…"
	curl -fsSL "$INSTALLER_URL" | bash
	hash -r
	command -v claude >/dev/null 2>&1 ||
		die "claude の導入に失敗しました。手動で 'curl -fsSL $INSTALLER_URL | bash' を実行してください。"
	write_stamp
else
	boundary=$(last_update_boundary)
	if (( $(read_stamp) < boundary )); then
		info "Claude Code の更新を確認します（前回確認から 04:00 を跨ぎました）…"
		if claude update; then
			write_stamp
		else
			warn "更新に失敗しました。現在のバージョンのまま起動します。"
		fi
	fi
fi

# ------------------------------------------------------------------------------------
# 起動
# ------------------------------------------------------------------------------------
add_skip=1
if [[ ${DEVBOX_CLAUDE_SKIP_PERMISSIONS:-1} == "0" ]]; then
	add_skip=0
fi
for arg in "$@"; do
	case "$arg" in
		--dangerously-skip-permissions | --allow-dangerously-skip-permissions | --permission-mode | --safe-mode)
			# 権限系を明示的に指定されたときは既定を被せない
			add_skip=0
			;;
	esac
done

if (( add_skip )); then
	exec claude --dangerously-skip-permissions "$@"
else
	exec claude "$@"
fi
