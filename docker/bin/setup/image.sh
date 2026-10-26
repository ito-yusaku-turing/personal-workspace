#!/usr/bin/env bash
# ====================================================================================
# devbox イメージをビルドする
#   docker/bin/setup/image.sh              devbox / app が使うイメージをビルド
#   docker/bin/setup/image.sh --no-cache   キャッシュを使わずビルド
#   docker/bin/setup/image.sh db           サービスを指定してビルド
#
#   devbox と app は同一イメージを共有するため、1回ビルドすれば両方に反映される。
#
#   docker/config/project.conf の DEVBOX_WITH_*（同梱ツール）や
#   CONTAINER_REPO_DIR を変更したら、ここで再ビルドすること。
# ====================================================================================
set -euo pipefail
# 自身の実体パスを解決してから読み込む（シンボリックリンク経由の実行に対応する）
# shellcheck source=../lib/common.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")/../lib/common.sh"

require_docker
load_env
require_setup

declare -a args=("$@")
# サービス名が指定されていなければ devbox（= 共有イメージ）をビルドする
has_service=0
for a in "${args[@]-}"; do
	case "$a" in
		-*) ;;
		"") ;;
		*) has_service=1 ;;
	esac
done
if (( ! has_service )); then
	args+=("devbox")
fi

# devbox は profile: cli のため、明示的にプロファイルを有効にしてから叩く
dc --profile cli build "${args[@]}"
