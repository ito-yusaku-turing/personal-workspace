#!/usr/bin/env bash
# ====================================================================================
# 初期セットアップ
#
#   docker/.env の生成 → コンテナ HOME の作成 → 個人設定の雛形配置
#   → 追加リポジトリのマウント定義生成 → イメージのビルド、までを一括で行う。
#
#   何度実行しても安全（既にあるものは壊さない）。
#
#   使い方:
#     docker/bin/setup.sh              対話つきでセットアップ
#     docker/bin/setup.sh --yes        既定値で非対話セットアップ
#     docker/bin/setup.sh --refresh    追加リポジトリの設定だけ再反映する
#     docker/bin/setup.sh --no-build   イメージのビルドを省略する
# ====================================================================================
set -euo pipefail
# 自身の実体パスを解決してから読み込む（シンボリックリンク経由の実行に対応する）
# shellcheck source=lib/common.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")/lib/common.sh"

ASSUME_YES=0
REFRESH_ONLY=0
DO_BUILD=1

usage() {
	# 冒頭のヘッダコメント（閉じの罫線まで）をそのまま説明として表示する
	sed -n '3,/^# =\{10,\}/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'
	exit 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-y | --yes) ASSUME_YES=1; shift ;;
		--refresh) REFRESH_ONLY=1; shift ;;
		--no-build) DO_BUILD=0; shift ;;
		-h | --help) usage ;;
		*) die "不明な引数: $1（--help を参照）" ;;
	esac
done

# ------------------------------------------------------------------------------------
# ヘルパ
# ------------------------------------------------------------------------------------
ask() {
	local prompt="$1" default="$2" ans
	if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
		printf '%s' "$default"
		return 0
	fi
	read -r -p "$prompt [$default]: " ans || ans=""
	printf '%s' "${ans:-$default}"
}

confirm() {
	local prompt="$1" default="${2:-N}" ans
	ans=$(ask "$prompt (y/N)" "$default")
	[[ $ans =~ ^[Yy] ]]
}

# docker/.env の KEY を書き換える（コメントアウトされていれば有効化する）
set_env_kv() {
	local key="$1" value="$2" tmp
	tmp=$(mktemp)
	if grep -qE "^[#[:space:]]*${key}=" "$ENV_FILE"; then
		awk -v k="$key" -v v="$value" '
			$0 ~ "^[#[:space:]]*" k "=" && !done { print k "=" v; done = 1; next }
			{ print }
		' "$ENV_FILE" >"$tmp"
	else
		cat "$ENV_FILE" >"$tmp"
		printf '%s=%s\n' "$key" "$value" >>"$tmp"
	fi
	mv "$tmp" "$ENV_FILE"
}

# ------------------------------------------------------------------------------------
# 1. docker/.env
# ------------------------------------------------------------------------------------
create_env_file() {
	if [[ -f $ENV_FILE ]]; then
		ok "docker/.env は既に存在します（設定は変更しません）"
		return 0
	fi

	info ""
	info "docker/.env を作成します。"
	info ""
	note "  コンテナの HOME にするホスト側ディレクトリを指定します。"
	note "  gh / ssh / クラウド CLI / claude の設定と認証情報はすべてここに置きます。"

	local user_home
	user_home=$(ask "コンテナ HOME のパス" "$DEFAULT_USER_HOME")
	user_home=$(expand_path "$user_home")

	cp "$ENV_EXAMPLE" "$ENV_FILE"
	set_env_kv USER_HOME_DIR "$user_home"
	ok "docker/.env を作成しました"
}

# ------------------------------------------------------------------------------------
# 2. ディレクトリ
# ------------------------------------------------------------------------------------
create_directories() {
	[[ -n ${USER_HOME_DIR-} ]] || die "docker/.env の USER_HOME_DIR が空です。"
	mkdir -p "$USER_HOME_DIR"
	ok "コンテナ HOME: $USER_HOME_DIR"
}

# ------------------------------------------------------------------------------------
# 3. 個人設定の雛形（コンテナ HOME 配下 = git 管理外）
#    既にあるものは上書きしない。
# ------------------------------------------------------------------------------------
place_personal_config() {
	local example="$1" dest="$2" label="$3" hint="$4"
	if [[ ! -f $example ]]; then
		warn "$label: 雛形が見つかりません（${example}）"
		return 0
	fi
	if [[ -f $dest ]]; then
		ok "$label: ${dest}（既存のため変更しません）"
		return 0
	fi
	mkdir -p "$(dirname "$dest")"
	cp "$example" "$dest"
	ok "$label の雛形を配置しました: $dest"
	note "  $hint"
}

setup_personal_configs() {
	place_personal_config "$AGENT_PREFS_EXAMPLE" "$PERSONAL_CONFIG_DIR/agent-preferences.md" \
		"エージェント設定" "「指示なしでやってよいこと」の個人設定です。既定はすべて都度確認。"
	place_personal_config "$SETUP_STATE_EXAMPLE" "$PERSONAL_CONFIG_DIR/setup-state.conf" \
		"セットアップ宣言" "使わない項目を宣言すると催促されなくなります（docker/bin/setup/state.sh）。"
}

# ------------------------------------------------------------------------------------
# 4. 追加リポジトリ（docker/config/repos.conf → docker/compose.repos.yml）
# ------------------------------------------------------------------------------------
generate_repos_override() {
	if [[ ! -f $REPOS_CONF ]]; then
		cp "$REPOS_EXAMPLE" "$REPOS_CONF"
		note "  docker/config/repos.conf を作成しました（追加リポジトリは未登録）"
	fi

	local tmp entries=0 line name path mount key
	tmp=$(mktemp)
	{
		echo "# ====================================================================================="
		echo "# 生成物 — 直接編集しないこと。"
		echo "# docker/config/repos.conf を編集し、docker/bin/setup.sh --refresh で再生成する。"
		echo "# ====================================================================================="
		echo "services:"
		echo "  devbox:"
		echo "    volumes:"
	} >"$tmp"

	while IFS= read -r line || [[ -n $line ]]; do
		line="${line%%#*}"
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		if [[ -z $line ]]; then
			continue
		fi

		# shellcheck disable=SC2086
		set -- $line
		name="${1-}"
		path="${2-}"
		if [[ -z $name || -z $path ]]; then
			warn "repos.conf の書式が不正な行を無視します: $line"
			continue
		fi
		if [[ -n ${3-} ]]; then
			warn "$name: マウント先は $CONTAINER_REPOS_PARENT/$name に固定のため、3列目以降は無視します"
		fi
		# マウント先は固定。エージェントが常に同じパスで参照できるようにするため
		mount="$CONTAINER_REPOS_PARENT/$name"
		path=$(expand_path "$path")
		if [[ ! -d $path ]]; then
			warn "$name のパスが存在しないため無視します: $path"
			continue
		fi

		printf '      - "%s:%s"\n' "$path" "$mount" >>"$tmp"
		entries=$((entries + 1))
		ok "追加リポジトリ: $name → $mount"

		# compose のサービス定義からビルド元として参照できるよう .env にも書く
		key="REPO_$(env_key_of "$name")"
		set_env_kv "$key" "$path"
		printf -v "$key" '%s' "$path"
		export "${key?}"
	done <"$REPOS_CONF"

	if (( entries > 0 )); then
		mv "$tmp" "$REPOS_OVERRIDE"
	else
		rm -f "$tmp" "$REPOS_OVERRIDE"
		note "  追加リポジトリの登録はありません（docker/config/repos.conf で追加できます）"
	fi
}

# ------------------------------------------------------------------------------------
# 5. イメージのビルド
# ------------------------------------------------------------------------------------
build_image() {
	if (( ! DO_BUILD )); then
		note "  --no-build のためビルドを省略しました"
		if ! devbox_image_exists; then
			warn "devbox イメージがまだありません。docker/bin/setup/image.sh を実行してください。"
		elif ! devbox_image_is_current; then
			local found
			found=$(devbox_image_schema)
			warn "devbox イメージが古い形式です（期待: schema=${DEVBOX_IMAGE_SCHEMA} / イメージ側: ${found:-ラベルなし}）。
       docker/bin/setup/image.sh で再ビルドしてください。"
		fi
		return 0
	fi
	info ""
	info "devbox イメージをビルドします（初回は数分かかります）…"
	"$DOCKER_DIR/bin/setup/image.sh"
	ok "イメージをビルドしました: $(devbox_image_name)"
}

# ====================================================================================
# 実行
# ====================================================================================
require_docker
require_compose_version

if (( REFRESH_ONLY )); then
	[[ -f $ENV_FILE ]] || die "docker/.env がありません。先に引数なしで setup.sh を実行してください。"
	load_env
	generate_repos_override
	ok "追加リポジトリの設定を反映しました"
	exit 0
fi

# project.conf を先に読む（.env の既定値の算出に使う）
load_env
DEFAULT_USER_HOME=$(expand_path "${DEFAULT_USER_HOME_DIR:-$HOME/.${PROJECT_NAME}/home}")

info "==== ${PROJECT_LABEL:-$PROJECT_NAME} 開発環境セットアップ ===="

create_env_file
load_env
# ディレクトリを作ってから設定の妥当性を検証する
create_directories
require_setup
setup_personal_configs
generate_repos_override
build_image

info ""
ok "セットアップが完了しました"
info ""
info "次の操作:"
info "  docker/bin/setup/github.sh   GitHub 認証（git 署名 / SSH 鍵 / gh）を設定"
info "  docker/bin/shell.sh          開発用シェルに入る"
info "  docker/bin/claude.sh         Claude Code を起動"
info "  docker/bin/doctor.sh         環境と認証情報の状態を確認"
info "  docker/bin/setup/state.sh    使わない項目を宣言する（催促されなくなる）"
info ""
"$DOCKER_DIR/bin/doctor.sh" || true
