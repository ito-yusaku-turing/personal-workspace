#!/bin/bash
DIR=$(realpath "$(dirname "$(readlink -f "$0" || echo "$0")")/../")
cd "$DIR" || exit
export SHOW_CONFIG=1
. "$DIR"/lib/common.sh
cd ../

# DB は既定でバックグラウンド起動（前景で見たい場合は引数 -c を渡す）
up_service "backend-db" "${1:--d}"
