#!/bin/bash
# backend-api(FastAPI)を起動する。backend-db に接続する。
#   既定はバックグラウンド(-d)。前景で起動したい場合は -c を渡す。
#   初回、または db-models のモデル変更後は --build (-b) でイメージを再ビルドする。
#   例: up-backend-api.sh            (背景)
#       up-backend-api.sh -c         (前景)
#       up-backend-api.sh -c --build (前景 + 再ビルド)
DIR=$(realpath "$(dirname "$(readlink -f "$0" || echo "$0")")/../")
cd "$DIR" || exit
export SHOW_CONFIG=1
. "$DIR"/lib/common.sh
cd ../

DETACH="-d"
BUILD=""
for arg in "$@"; do
	case "$arg" in
		-c) DETACH="" ;;
		-d) DETACH="-d" ;;
		--build | -b) BUILD="--build" ;;
		*)
			echo "unknown option: $arg (use -c / -d / --build)" >&2
			exit 1
			;;
	esac
done

# shellcheck disable=SC2086
docker_compose up $DETACH $BUILD backend-api
