#!/usr/bin/env bash
# ====================================================================================
# devbox コンテナ内で Codex CLI を起動する
#
#   ホストからは docker/bin/codex.sh を使う（このスクリプトを呼び出す）。
#
#   導入先は $HOME/.local（NPM_CONFIG_PREFIX。コンテナ HOME にマウントされたホスト側
#   ディレクトリ）なので、コンテナを作り直しても消えず、ログイン状態も保持される。
# ====================================================================================
set -euo pipefail
# 自身の実体パスを解決してから読み込む（シンボリックリンク経由の実行に対応する）
# shellcheck source=lib/common.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")/lib/common.sh"

if ! command -v codex >/dev/null 2>&1; then
	info "Codex CLI を導入します…"
	npm install -g @openai/codex
	hash -r
fi

command -v codex >/dev/null 2>&1 ||
	die "codex の導入に失敗しました。手動で 'npm install -g @openai/codex' を実行してください。"

exec codex "$@"
