#!/usr/bin/env bash
# ====================================================================================
# 個人設定ファイルの雛形を配置する（ホストから実行する）
#   docker/bin/setup/config.sh          未配置のものだけ雛形をコピーする
#   docker/bin/setup/config.sh status   配置状況だけを表示する
#
#   配置先はコンテナ HOME 配下の個人設定ディレクトリ（git 管理外）。
#   既存ファイルは上書きしない。
#   引数はそのまま docker/container-bin/setup/config.sh に渡る（実体はそちら）。
#
#   docker/bin/setup.sh も初回セットアップの一部として同じ配置を行う。こちらは
#   「あとから雛形だけ置きたい」「devbox の中から置きたい」ときの入口。
# ====================================================================================
set -euo pipefail
# 自身の実体パスを解決してから読み込む（シンボリックリンク経由の実行に対応する）
# shellcheck source=../lib/common.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")/../lib/common.sh"

require_docker
load_env
require_setup
require_devbox_image

dc run --rm --no-deps -T devbox docker/container-bin/setup/config.sh "$@"
