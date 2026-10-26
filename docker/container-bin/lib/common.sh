#!/usr/bin/env bash
# ====================================================================================
# docker/container-bin/ 配下のスクリプト共通処理
#
#   docker/container-bin/ は **devbox コンテナの中から実行する**スクリプト群。
#   ホスト（コンテナ外）から実行するスクリプトは docker/bin/ に置く。
#
#   このファイルを source した時点で実行場所を判定し、コンテナ外なら警告して終了する。
#
#   プロジェクト固有の値（リポジトリのマウント先・個人設定の置き場・同梱ツール）は
#   イメージビルド時に焼かれた /etc/devbox.conf から読む。ここにハードコードしないこと
#   （テンプレートを別プロジェクトへそのまま持ち込めなくなる）。
# ====================================================================================
set -euo pipefail

DEVBOX_MARKER=/etc/devbox.conf

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
# 実行場所のガード
# ------------------------------------------------------------------------------------
if [[ ! -f $DEVBOX_MARKER ]]; then
	printf '%sエラー:%s ここは devbox コンテナの外です。このスクリプトはコンテナ内で実行します。\n' "${C_RED}" "${C_OFF}" >&2
	printf '       （コーディングエージェントは devbox の中でのみ動作させる方針です）\n' >&2
	printf '       ホストからは docker/bin/ 配下のスクリプトを使ってください。\n' >&2
	printf '         例: docker/bin/claude.sh / docker/bin/codex.sh / docker/bin/doctor.sh\n' >&2
	printf '       devbox コンテナの中で実行しているのにこれが出る場合はイメージが古い。\n' >&2
	printf '         docker/bin/setup/image.sh で再ビルドしてください。\n' >&2
	exit 1
fi

# ビルド時に焼かれたコンテナ設定（KEY=VALUE のみ。コマンド置換は含まない）
# shellcheck disable=SC1090
. "$DEVBOX_MARKER"

REPO_DIR="${DEVBOX_REPO_DIR:?/etc/devbox.conf に DEVBOX_REPO_DIR がありません（イメージが古い: docker/bin/setup/image.sh）}"
PROJECT_NAME="${DEVBOX_PROJECT_NAME:-project}"
# 表示名は compose から環境変数で渡る（イメージに焼かないので変更に再ビルドが要らない）
PROJECT_LABEL="${PROJECT_LABEL:-$PROJECT_NAME}"

# 個人設定（コンテナ HOME 配下 = ホストの $USER_HOME_DIR 配下 = git 管理外）。
# 雛形の配置は docker/bin/setup.sh（ホスト）と setup/config.sh（両方）が行う。
PERSONAL_CONFIG_DIR="$HOME/${DEVBOX_PERSONAL_CONFIG_DIR_NAME:-.devbox}"
AGENT_PREFS_EXAMPLE="$REPO_DIR/docker/config/agent-preferences.example.md"
AGENT_PREFS_DEST="$PERSONAL_CONFIG_DIR/agent-preferences.md"
SETUP_STATE_EXAMPLE="$REPO_DIR/docker/config/setup-state.example.conf"
SETUP_STATE_DEST="$PERSONAL_CONFIG_DIR/setup-state.conf"

cd "$REPO_DIR"
