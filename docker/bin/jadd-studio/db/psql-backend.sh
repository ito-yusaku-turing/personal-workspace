#!/bin/bash
# ローカル backend-db(postgres) に psql で接続する。
#   引数なし: 対話 psql シェル / 引数あり: そのまま psql に渡す(例: -c "select ...")
#   事前に up-backend-db.sh で backend-db を起動しておくこと。
DIR=$(realpath "$(dirname "$(readlink -f "$0" || echo "$0")")/../../")
cd "$DIR" || exit
. "$DIR"/lib/common.sh
cd ../

# HOME はコンテナ側で /usr/home(user-home マウント)に設定済みのため、
# psql 履歴(~/.psql_history)はそこに永続化される。
docker_compose exec -e PGPASSWORD=postgres backend-db \
	psql -U postgres -d backend_local "$@"
