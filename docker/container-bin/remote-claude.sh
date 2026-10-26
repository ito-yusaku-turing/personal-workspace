#!/usr/bin/env bash
# ====================================================================================
# devbox コンテナ内で Claude Code を Remote Control モードで起動する
#
#   ホストからは docker/bin/remote-claude.sh を使う（このスクリプトを呼び出す）。
#
#   セッション名は <接頭辞>-<今日の月日4桁>。例: 接頭辞 myapp / 7月29日 → myapp-0729
#   接頭辞は docker/config/project.conf の AGENT_SESSION_PREFIX。
#   DEVBOX_RC_SESSION を設定すればその名前をそのまま使う。
#
#   導入・更新・既定の権限オプションは claude.sh と共通（このスクリプトが呼び出す）。
# ====================================================================================
set -euo pipefail
# 自身の実体パスを解決してから読み込む（シンボリックリンク経由の実行に対応する）
SCRIPT_DIR=$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")" && pwd)
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

prefix="${AGENT_SESSION_PREFIX:-$PROJECT_NAME}"
session="${DEVBOX_RC_SESSION:-${prefix}-$(TZ="${DEVBOX_TZ:-UTC}" date +%m%d)}"

info "Remote Control セッション: ${C_GREEN}${session}${C_OFF}"

exec "$SCRIPT_DIR/claude.sh" --remote-control "$session" "$@"
