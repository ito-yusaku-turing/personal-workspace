#!/usr/bin/env bash
# ====================================================================================
# GitHub 認証のセットアップ（ホストから実行する）
#   docker/bin/setup/github.sh              いまの状態と次の一手を表示する
#   docker/bin/setup/github.sh all          順に案内する
#   docker/bin/setup/github.sh --help       サブコマンドの一覧
#
#   引数はそのまま docker/container-bin/setup/github.sh に渡る（実体はそちら）。
#   認証情報はコンテナ HOME（ホストの ${USER_HOME_DIR}）配下に残るため、
#   コンテナを作り直しても消えない。
# ====================================================================================
set -euo pipefail
# 自身の実体パスを解決してから読み込む（シンボリックリンク経由の実行に対応する）
# shellcheck source=../lib/common.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")/../lib/common.sh"

require_docker
load_env
require_setup
require_devbox_image

# 対話（gh auth login のワンタイムコード入力、氏名の入力）があるため TTY を渡す
dc run --rm --no-deps devbox docker/container-bin/setup/github.sh "$@"
