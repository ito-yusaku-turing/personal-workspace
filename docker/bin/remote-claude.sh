#!/usr/bin/env bash
# ====================================================================================
# devbox を起動し、同時に Claude Code を Remote Control モードで立ち上げる
#   docker/bin/remote-claude.sh              セッション名は <接頭辞>-<月日4桁>
#   docker/bin/remote-claude.sh --model opus 引数はそのまま claude に渡る
#
#   接頭辞は docker/config/project.conf の AGENT_SESSION_PREFIX。
#   セッション名を直接変えたいときは DEVBOX_RC_SESSION を設定する。
#     DEVBOX_RC_SESSION=myapp-hotfix docker/bin/remote-claude.sh
#
#   実体は docker/container-bin/remote-claude.sh（コンテナ内で実行される）。
# ====================================================================================
set -euo pipefail
# 自身の実体パスを解決してから読み込む（シンボリックリンク経由の実行に対応する）
# shellcheck source=lib/common.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")/lib/common.sh"

require_docker
load_env
require_setup
require_devbox_image

declare -a env_args=()
if [[ -n ${DEVBOX_RC_SESSION:-} ]]; then
	env_args+=(-e "DEVBOX_RC_SESSION=$DEVBOX_RC_SESSION")
fi
if [[ -n ${AGENT_SESSION_PREFIX:-} ]]; then
	env_args+=(-e "AGENT_SESSION_PREFIX=$AGENT_SESSION_PREFIX")
fi

dc run --rm "${env_args[@]}" devbox docker/container-bin/remote-claude.sh "$@"
