#!/usr/bin/env bash
# ====================================================================================
# devbox で Claude Code を起動する（ホストから実行する）
#   docker/bin/claude.sh              対話セッションを開始
#   docker/bin/claude.sh --help       引数はそのまま claude に渡る
#
#   コーディングエージェントは devbox コンテナの中でのみ動作させる。
#   実体は docker/container-bin/claude.sh（コンテナ内で実行される）。
# ====================================================================================
set -euo pipefail
# 自身の実体パスを解決してから読み込む（シンボリックリンク経由の実行に対応する）
# shellcheck source=lib/common.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")/lib/common.sh"

require_docker
load_env
require_setup
require_devbox_image

dc run --rm devbox docker/container-bin/claude.sh "$@"
