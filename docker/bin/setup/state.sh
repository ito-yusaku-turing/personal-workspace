#!/usr/bin/env bash
# ====================================================================================
# セットアップ項目の「使わない」宣言を編集する（ホストから実行する）
#   docker/bin/setup/state.sh list                 項目と実効状態を一覧する
#   docker/bin/setup/state.sh skip <項目> [理由]   その項目を使わないと宣言する
#   docker/bin/setup/state.sh unskip <項目>        宣言を取り消す
#
#   引数はそのまま docker/container-bin/setup/state.sh に渡る（実体はそちら）。
#   宣言はコンテナ HOME 配下の setup-state.conf に残る（git 管理外）。
# ====================================================================================
set -euo pipefail
# 自身の実体パスを解決してから読み込む（シンボリックリンク経由の実行に対応する）
# shellcheck source=../lib/common.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")/../lib/common.sh"

require_docker
load_env
require_setup
require_devbox_image

dc run --rm --no-deps devbox docker/container-bin/setup/state.sh "$@"
