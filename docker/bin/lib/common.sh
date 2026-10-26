#!/usr/bin/env bash
# ====================================================================================
# docker/bin/ 配下のスクリプト共通処理
#
#   docker/bin/ は **ホスト（コンテナ外）から実行する**スクリプト群。
#   コンテナの中から実行するスクリプトは docker/container-bin/ に置く。
#
#   - docker/config/project.conf（プロジェクト共通 / git 管理下）の読み込み
#   - docker/.env（開発者ごと / git 管理外）の読み込みとパス展開
#   - ホストの UID/GID と Node.js バージョンを compose へ渡す
#   - docker compose のラッパ dc()
# ====================================================================================
set -euo pipefail

DEVBOX_MARKER=/etc/devbox.conf

# このファイルは docker/bin/lib/common.sh にある。
# 実行経路にシンボリックリンクが含まれていても実体の位置を基準にできるよう、
# 自身のパスのリンクを辿ってから解決する（`readlink -f` は環境差があるため純 bash で行う）。
# これを怠ると、例えば docker/ 自体をリンクした先から実行したときに REPO_DIR が
# リポジトリ外を指し、「.nvmrc がありません」等の誤ったエラーになる。
_common_self=${BASH_SOURCE[0]}
while [[ -L $_common_self ]]; do
	_common_link=$(readlink "$_common_self")
	case $_common_link in
		/*) _common_self=$_common_link ;;
		*)  _common_self=$(cd -P "$(dirname "$_common_self")" && pwd)/$_common_link ;;
	esac
done
DOCKER_DIR=$(cd -P "$(dirname "$_common_self")/../.." && pwd)
REPO_DIR=$(cd -P "$DOCKER_DIR/.." && pwd)
unset _common_self _common_link

PROJECT_CONF="$DOCKER_DIR/config/project.conf"
ENV_FILE="$DOCKER_DIR/.env"
ENV_EXAMPLE="$DOCKER_DIR/config/env.example"
REPOS_CONF="$DOCKER_DIR/config/repos.conf"
REPOS_EXAMPLE="$DOCKER_DIR/config/repos.example.conf"
REPOS_OVERRIDE="$DOCKER_DIR/compose.repos.yml"
# エージェント個人プリファレンスとセットアップ宣言（コンテナ HOME 配下 = git 管理外）。
# 配置先のディレクトリ名は project.conf の PERSONAL_CONFIG_DIR_NAME。
AGENT_PREFS_EXAMPLE="$DOCKER_DIR/config/agent-preferences.example.md"
SETUP_STATE_EXAMPLE="$DOCKER_DIR/config/setup-state.example.conf"
export DOCKER_DIR REPO_DIR PROJECT_CONF ENV_FILE ENV_EXAMPLE
export REPOS_CONF REPOS_EXAMPLE REPOS_OVERRIDE AGENT_PREFS_EXAMPLE SETUP_STATE_EXAMPLE

# ------------------------------------------------------------------------------------
# 出力
# ------------------------------------------------------------------------------------
if [[ -t 1 ]]; then
	C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_GREEN=$'\033[32m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
	C_RED=""; C_YELLOW=""; C_GREEN=""; C_DIM=""; C_OFF=""
fi

info() { printf '%s\n' "$*" >&2; }
note() { printf '%s%s%s\n' "$C_DIM" "$*" "$C_OFF" >&2; }
ok()   { printf '%s✔%s %s\n' "$C_GREEN" "$C_OFF" "$*" >&2; }
warn() { printf '%s警告:%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()  { printf '%sエラー:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

# ------------------------------------------------------------------------------------
# パス展開: 先頭の ~ をホームに展開する（compose は ~ を展開しないため）
# ------------------------------------------------------------------------------------
expand_path() {
	local p="${1-}"
	case "$p" in
		"~") printf '%s' "$HOME" ;;
		"~/"*) printf '%s' "$HOME/${p#\~/}" ;;
		*) printf '%s' "$p" ;;
	esac
}

# 名前 → 環境変数名（some-lib → SOME_LIB）
env_key_of() {
	printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_' | tr -cd 'A-Z0-9_'
}

# ------------------------------------------------------------------------------------
# docker / docker compose の存在確認
# ------------------------------------------------------------------------------------
require_docker() {
	command -v docker >/dev/null 2>&1 || die "docker が見つかりません。Docker をインストールしてください。"
	docker compose version >/dev/null 2>&1 ||
		die "docker compose (v2) が使えません。Docker Compose v2.20 以上が必要です。"
}

# compose ファイルの include: を使うため v2.20 以上が必要
require_compose_version() {
	local raw major minor
	raw=$(docker compose version --short 2>/dev/null || echo "0.0.0")
	raw="${raw#v}"
	major="${raw%%.*}"
	minor="${raw#*.}"; minor="${minor%%.*}"
	if [[ ! $major =~ ^[0-9]+$ || ! $minor =~ ^[0-9]+$ ]]; then
		warn "docker compose のバージョンを判定できませんでした（${raw}）。2.20 以上が必要です。"
		return 0
	fi
	if (( major < 2 || (major == 2 && minor < 20) )); then
		die "docker compose $raw は非対応です。include: を使うため 2.20 以上へ更新してください。"
	fi
}

# ------------------------------------------------------------------------------------
# 設定の読み込み
#   project.conf（プロジェクト共通）→ .env（開発者ごと）の順に読む。
#   compose 自身も docker/.env を読むが、~ の展開やスクリプト内での参照のために
#   ここでも読む。シェル環境の値は .env より優先されるため、展開済みの値が compose に渡る。
# ------------------------------------------------------------------------------------
load_env() {
	[[ -f $PROJECT_CONF ]] || die "docker/config/project.conf がありません（git 管理下のはず）。リポジトリの状態を確認してください。"

	set -a
	# shellcheck disable=SC1090
	. "$PROJECT_CONF"
	if [[ -f $ENV_FILE ]]; then
		# shellcheck disable=SC1090
		. "$ENV_FILE"
	fi
	set +a

	# project.conf の必須項目
	local k
	for k in PROJECT_NAME CONTAINER_REPO_DIR PERSONAL_CONFIG_DIR_NAME; do
		[[ -n ${!k-} ]] || die "docker/config/project.conf に $k がありません。"
	done
	[[ $CONTAINER_REPO_DIR == /* ]] ||
		die "CONTAINER_REPO_DIR は絶対パスにしてください（現在: ${CONTAINER_REPO_DIR}）"

	# compose のプロジェクト名。compose.yml の name: は変数展開できないため環境変数で渡す
	COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$PROJECT_NAME}"
	# イメージ名。.env で上書きできる
	DEVBOX_IMAGE="${DEVBOX_IMAGE:-${PROJECT_NAME}-devbox:latest}"
	# 追加リポジトリのマウント先の親（CONTAINER_REPO_DIR と同階層に並べる）
	CONTAINER_REPOS_PARENT=$(dirname "$CONTAINER_REPO_DIR")
	# 個人設定の置き場（ホスト側の絶対パスは USER_HOME_DIR 確定後に組み立てる）
	PERSONAL_CONFIG_DIR_NAME="${PERSONAL_CONFIG_DIR_NAME#/}"
	TZ="${TZ:-Asia/Tokyo}"
	export COMPOSE_PROJECT_NAME DEVBOX_IMAGE CONTAINER_REPOS_PARENT
	export PERSONAL_CONFIG_DIR_NAME TZ

	# コンテナはホストと同じ UID/GID で動く（entrypoint が root から降格する）。
	# macOS では bind mount の所有権がファイル共有層で変換されるため一致は不要だが、
	# Linux / WSL2 では必須。同じ値を渡しておけば両方で正しく動く。
	HOST_UID=$(id -u)
	HOST_GID=$(id -g)
	CONTAINER_USER=$(id -un 2>/dev/null || echo dev)
	export HOST_UID HOST_GID CONTAINER_USER

	# Node.js のバージョンは .nvmrc が唯一の正。CI（actions/setup-node の
	# node-version-file）も同じファイルを読む。docker/.env に NODE_VERSION が
	# 残っていても、ここで上書きして無視する（開発者ごとの乖離を作らせない）。
	if [[ -f "$REPO_DIR/.nvmrc" ]]; then
		NODE_VERSION=$(tr -d ' \t\r\nv' <"$REPO_DIR/.nvmrc")
		export NODE_VERSION
	else
		die ".nvmrc がありません（Node.js バージョンの正）。
       リポジトリ直下に .nvmrc を置いてください（例: echo 24.22.1 > .nvmrc）。"
	fi

	if [[ -n ${USER_HOME_DIR-} ]]; then
		USER_HOME_DIR=$(expand_path "$USER_HOME_DIR")
		export USER_HOME_DIR
		PERSONAL_CONFIG_DIR="$USER_HOME_DIR/$PERSONAL_CONFIG_DIR_NAME"
		export PERSONAL_CONFIG_DIR
	fi
	# REPO_* は setup.sh が絶対パスで書くが、手で ~ を書かれても動くようにする
	local var
	for var in $(compgen -v | grep '^REPO_' || true); do
		[[ ${!var} == "~"* ]] || continue
		printf -v "$var" '%s' "$(expand_path "${!var}")"
		export "${var?}"
	done
}

# setup 済みであることを要求する（操作系スクリプト用）
require_setup() {
	[[ -f $ENV_FILE ]] || die "docker/.env がありません。先に docker/bin/setup.sh を実行してください。"
	[[ -n ${USER_HOME_DIR-} ]] || die "docker/.env に USER_HOME_DIR が設定されていません。"
	if [[ ! -d $USER_HOME_DIR ]]; then
		die "USER_HOME_DIR が存在しません: ${USER_HOME_DIR}（docker/bin/setup.sh を実行してください）"
	fi
}

# ------------------------------------------------------------------------------------
# docker compose ラッパ
#   追加リポジトリのマウント定義（生成物）があれば重ねる
# ------------------------------------------------------------------------------------
dc() {
	local -a files=(-f "$DOCKER_DIR/compose.yml")
	if [[ -f $REPOS_OVERRIDE ]]; then
		files+=(-f "$REPOS_OVERRIDE")
	fi
	(cd "$DOCKER_DIR" && docker compose "${files[@]}" "$@")
}

# ------------------------------------------------------------------------------------
# devbox イメージ
#   イメージには契約バージョンのラベル（devbox.schema）を焼いてある。
#   スクリプトが期待する版と食い違う＝イメージが古いので、再ビルドを促す。
#   Dockerfile の LABEL を上げたらこの値も一緒に上げること。
# ------------------------------------------------------------------------------------
DEVBOX_IMAGE_SCHEMA=1

devbox_image_name() { printf '%s' "${DEVBOX_IMAGE:-devbox:latest}"; }

devbox_image_exists() {
	docker image inspect "$(devbox_image_name)" >/dev/null 2>&1
}

# ビルド済みイメージのラベル値（無ければ空文字）
devbox_image_schema() {
	docker image inspect \
		-f '{{ with .Config.Labels }}{{ index . "devbox.schema" }}{{ end }}' \
		"$(devbox_image_name)" 2>/dev/null || true
}

devbox_image_is_current() {
	[[ $(devbox_image_schema) == "$DEVBOX_IMAGE_SCHEMA" ]]
}

require_devbox_image() {
	if ! devbox_image_exists; then
		die "devbox イメージが未ビルドです。docker/bin/setup.sh または docker/bin/setup/image.sh を実行してください。"
	fi
	if ! devbox_image_is_current; then
		local found
		found=$(devbox_image_schema)
		die "devbox イメージが古い形式です（期待: schema=${DEVBOX_IMAGE_SCHEMA} / イメージ側: ${found:-ラベルなし}）。
       docker/bin/setup/image.sh で再ビルドしてください。"
	fi
}

# ------------------------------------------------------------------------------------
# 実行場所のガード（このファイルを source した時点で判定する）
#   docker/bin/ 配下はホストから実行するもの。devbox の中では docker を使えないため、
#   誤って実行したら早期に止める。
# ------------------------------------------------------------------------------------
if [[ -f $DEVBOX_MARKER ]]; then
	die "docker/bin/ 配下はホスト（コンテナ外）から実行するスクリプトです。
       devbox コンテナの中では docker/container-bin/ 配下を使ってください。"
fi
