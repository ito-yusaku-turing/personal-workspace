#!/usr/bin/env bash
# ====================================================================================
# 環境診断
#   前提条件・設定・クレデンシャルの状態を一覧表示する。
#   セットアップ項目はすべて任意。未設定でも開発環境自体は起動できる（該当機能のみ使えない）。
#
#   使い方:
#     docker/bin/doctor.sh              人間向けの一覧
#     docker/bin/doctor.sh --porcelain  機械可読（TSV / エージェント向け）
#
#   porcelain はホスト側の項目を出したあと、コンテナ内の項目を連結する。
#   devbox イメージが無い／古い場合はコンテナ側を問い合わせられないため、
#   devbox-image の行までで出力が終わる（それが理由を示している）。
# ====================================================================================
set -euo pipefail
# 自身の実体パスを解決してから読み込む（シンボリックリンク経由の実行に対応する）
_self=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")
# shellcheck source=lib/common.sh
. "$(dirname "$_self")/lib/common.sh"

PORCELAIN=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--porcelain) PORCELAIN=1; shift ;;
		-h | --help)
			sed -n '3,/^# =\{10,\}/p' "$_self" | sed -e '$d' -e 's/^# \{0,1\}//'
			exit 1 ;;
		*) die "不明な引数: $1（--help を参照）" ;;
	esac
done

# ------------------------------------------------------------------------------------
# 機械可読出力
#   状態の語彙と項目名の契約は docker/container-bin/lib/setup-state.sh が正。
#   ホスト側でしか分からない項目（project.conf・docker/.env・イメージ）だけをここで足す。
# ------------------------------------------------------------------------------------
if (( PORCELAIN )); then
	# 契約バージョンの正は setup-state.sh。ここに数字を直書きすると、項目を足したときに
	# ホストとコンテナで違う版を名乗る（実際に片方だけ上げる事故が起きうる）。
	# コンテナを起こさずヘッダだけ出す必要があるため、source ではなく値を読み出す。
	printf '# devbox-setup-state %s\n' \
		"$(sed -n 's/^SETUP_STATE_SCHEMA=\([0-9][0-9]*\).*/\1/p' \
			"$DOCKER_DIR/container-bin/lib/setup-state.sh" | head -1)"
	if [[ ! -f $PROJECT_CONF ]]; then
		printf 'project-conf\tmissing\t%s\n' "$PROJECT_CONF"
		exit 0
	fi
	printf 'project-conf\tok\t%s\n' "$PROJECT_CONF"
	if [[ -f $ENV_FILE ]]; then
		printf 'docker-env\tok\t%s\n' "$ENV_FILE"
		load_env
	else
		printf 'docker-env\tmissing\t\n'
		exit 0
	fi
	if ! devbox_image_exists; then
		printf 'devbox-image\tmissing\t%s\n' "docker/bin/setup/image.sh"
		exit 0
	elif ! devbox_image_is_current; then
		printf 'devbox-image\terror\t古い形式（期待 schema=%s / イメージ側 %s）→ docker/bin/setup/image.sh\n' \
			"$DEVBOX_IMAGE_SCHEMA" "$(devbox_image_schema || true)"
		exit 0
	fi
	printf 'devbox-image\tok\t%s\n' "$(devbox_image_name)"
	# ヘッダは既に出したのでコンテナ側では抑制する
	dc run --rm --no-deps -T -e SETUP_STATE_NO_HEADER=1 devbox \
		docker/container-bin/doctor.sh --porcelain
	exit 0
fi

# ラベル列を表示幅で揃える（printf の %-Ns はバイト数で数えるため日本語がずれる）
row() {
	local label="$1" value="$2" chars bytes width pad
	chars=$(printf '%s' "$label" | wc -m)
	bytes=$(printf '%s' "$label" | LC_ALL=C wc -c)
	width=$(( chars + (bytes - chars) / 2 ))
	pad=$(( 20 - width ))
	if (( pad < 1 )); then pad=1; fi
	printf '  %s%*s%s\n' "$label" "$pad" "" "$value"
}

info "==== ホスト ===="
if command -v docker >/dev/null 2>&1; then
	row "docker" "$(docker --version 2>/dev/null || echo '?')"
	if docker compose version >/dev/null 2>&1; then
		row "docker compose" "$(docker compose version --short 2>/dev/null || echo '?')"
	else
		row "docker compose" "${C_RED}v2 が使えません${C_OFF}"
	fi
	if ! docker info >/dev/null 2>&1; then
		row "docker daemon" "${C_RED}接続できません${C_OFF}"
	fi
else
	row "docker" "${C_RED}未インストール${C_OFF}"
fi

info ""
info "==== 設定 ===="
if [[ ! -f $PROJECT_CONF ]]; then
	row "project.conf" "${C_RED}なし${C_OFF}  ${C_DIM}git 管理下のはず。リポジトリの状態を確認してください${C_OFF}"
	exit 0
fi
row "project.conf" "${C_GREEN}あり${C_OFF}"
if [[ -f $ENV_FILE ]]; then
	row "docker/.env" "${C_GREEN}あり${C_OFF}"
	load_env
else
	row "docker/.env" "${C_RED}なし${C_OFF}  ${C_DIM}docker/bin/setup.sh を実行してください${C_OFF}"
	exit 0
fi

row "プロジェクト" "${PROJECT_LABEL:-$PROJECT_NAME}  ${C_DIM}(compose: ${COMPOSE_PROJECT_NAME})${C_OFF}"
row "リポジトリ" "$REPO_DIR ${C_DIM}→ ${CONTAINER_REPO_DIR}${C_OFF}"
if [[ -n ${USER_HOME_DIR-} && -d ${USER_HOME_DIR-} ]]; then
	row "コンテナ HOME" "${C_GREEN}${USER_HOME_DIR}${C_OFF}"
else
	row "コンテナ HOME" "${C_RED}${USER_HOME_DIR:-未設定}（存在しません）${C_OFF}"
fi
row "Node.js" "${NODE_VERSION}  ${C_DIM}(.nvmrc / CI と共通)${C_OFF}"

# 同梱ツールの構成（project.conf で切り替えたら再ビルドが要る）
_tools=""
for _t in PSQL AWS GCLOUD DATABRICKS UV; do
	_v="DEVBOX_WITH_${_t}"
	[[ ${!_v:-0} == 1 ]] && _tools+="$(printf '%s' "$_t" | tr '[:upper:]' '[:lower:]') "
done
_tools="${_tools% }"
row "同梱ツール" "${_tools:-（基本セットのみ）}"

# .env に残った NODE_VERSION は .nvmrc に上書きされる。気づけるよう警告する
if grep -qE '^[[:space:]]*NODE_VERSION=' "$ENV_FILE"; then
	warn "docker/.env の NODE_VERSION は無視されます（.nvmrc が正）。その行は削除してください。"
fi

if [[ -f $REPOS_OVERRIDE ]]; then
	row "追加リポジトリ" "$(grep -c '^      - ' "$REPOS_OVERRIDE" || echo 0) 件  ${C_DIM}docker/config/repos.conf${C_OFF}"
else
	row "追加リポジトリ" "なし"
fi

if ! devbox_image_exists; then
	row "devbox イメージ" "${C_YELLOW}未ビルド${C_OFF}  ${C_DIM}docker/bin/setup/image.sh${C_OFF}"
elif devbox_image_is_current; then
	row "devbox イメージ" "${C_GREEN}ビルド済み${C_OFF}  ${C_DIM}$(devbox_image_name) (schema=${DEVBOX_IMAGE_SCHEMA})${C_OFF}"
else
	image_schema=$(devbox_image_schema)
	row "devbox イメージ" "${C_YELLOW}古い形式${C_OFF}  ${C_DIM}期待 schema=${DEVBOX_IMAGE_SCHEMA} / イメージ側 ${image_schema:-ラベルなし}。docker/bin/setup/image.sh で再ビルド${C_OFF}"
fi

# ------------------------------------------------------------------------------------
# コンテナ内のツールとクレデンシャル
# ------------------------------------------------------------------------------------
info ""
info "==== コンテナ内のツール / クレデンシャル（すべて任意） ===="
if ! devbox_image_exists; then
	note "  devbox イメージが未ビルドのため確認できません（docker/bin/setup/image.sh）"
	exit 0
fi
if ! devbox_image_is_current; then
	note "  devbox イメージが古いため確認できません。docker/bin/setup/image.sh で再ビルドしてください"
	exit 0
fi

dc run --rm --no-deps -T devbox docker/container-bin/doctor.sh || warn "コンテナ内の診断に失敗しました"
