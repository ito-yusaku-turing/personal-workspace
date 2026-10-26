#!/usr/bin/env bash
# ====================================================================================
# 開発用シェル（devbox）に入る
#   docker/bin/shell.sh                 bash を起動する
#   docker/bin/shell.sh npm ci          コマンドを直接実行する
#
#   使い捨てコンテナ（run --rm）で起動する。作業結果はマウントされた
#   リポジトリとコンテナ HOME に残り、コンテナ自体は終了時に破棄される。
# ====================================================================================
set -euo pipefail
# 自身の実体パスを解決してから読み込む（シンボリックリンク経由の実行に対応する）
# shellcheck source=lib/common.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")/lib/common.sh"

require_docker
load_env
require_setup
require_devbox_image

if (( $# )); then
	dc run --rm devbox "$@"
else
	dc run --rm devbox bash
fi
