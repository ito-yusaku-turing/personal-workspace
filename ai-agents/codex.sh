#!/bin/bash
DIR=$(realpath "$(dirname "$(readlink -f "$0" || echo "$0")")")
CODEX=$DIR/node_modules/.bin/codex

export CODEX_LANG=ja

if [[ ! -f "$CODEX" ]]; then
    npm install --save-dev @openai/codex@latest
fi

if [[ "$1" == "update" ]]; then
	npm install --save-dev @openai/codex@latest
	shift
fi

if [[ "$HOME" == "/usr/home" ]]; then
	echo -e "\033[31;1;5m -------- BRAVE MODE -------- \033[0m"
	$CODEX --dangerously-bypass-approvals-and-sandbox "$@"
else
	echo "Codex safety mode"
	$CODEX "$@"
fi
