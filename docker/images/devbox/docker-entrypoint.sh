#!/bin/sh
# ====================================================================================
# devbox / app コンテナのエントリポイント
#
#   root で起動し、ホストの UID/GID に対応する passwd/group エントリを
#   **home = /usr/home** で用意してから、その UID/GID に降格して本来のコマンドを実行する。
#
#   なぜ必要か:
#     ssh / ssh-keygen 等は $HOME ではなく getpwuid() の pw_dir（/etc/passwd の 6 列目）を
#     見る。ホストの /etc/passwd をマウントする方式では pw_dir がホスト側のパス
#     （/home/xxx や /Users/xxx）になり、コンテナ内に存在しないため鍵も ~/.ssh/config も
#     見つからない。加えて macOS の通常ユーザーは OpenDirectory 管理で /etc/passwd に
#     載らないため、その方式は macOS では成立しない。
#
#   ホストと同じ UID/GID で実行することで、bind mount に書き込んだファイルの所有者が
#   ホスト側と一致する。マウント先を chown しないこと。
# ====================================================================================
set -eu

HOME_DIR=/usr/home
HOST_UID="${HOST_UID:-0}"
HOST_GID="${HOST_GID:-0}"
CONTAINER_USER="${CONTAINER_USER:-dev}"

# ユーザー名として使えない文字が来たら既定名に落とす（macOS のユーザー名対策）
case "$CONTAINER_USER" in
	[a-z_][a-z0-9_-]*) ;;
	*) CONTAINER_USER=dev ;;
esac

# root 実行の指定ならそのまま実行する
if [ "$HOST_UID" = "0" ]; then
	export HOME=/root
	exec "$@"
fi

# グループ: 同じ GID が既にあればそれを使う（macOS の GID 20 = Debian の dialout 等）
if ! getent group "$HOST_GID" >/dev/null 2>&1; then
	groupadd -g "$HOST_GID" "$CONTAINER_USER"
fi

# ユーザー: 同じ UID が既にあれば home を矯正する
#   node 公式イメージは UID 1000 を node（home=/home/node）が使っているため、
#   Linux の一般的な UID 1000 と衝突する。ここで /usr/home に付け替える。
if entry=$(getent passwd "$HOST_UID" 2>/dev/null); then
	existing_name=${entry%%:*}
	existing_home=$(echo "$entry" | cut -d: -f6)
	if [ "$existing_home" != "$HOME_DIR" ]; then
		usermod -d "$HOME_DIR" "$existing_name"
	fi
else
	# -M: home は bind mount 済みなので作らせない（chown もしない）
	useradd -u "$HOST_UID" -g "$HOST_GID" -d "$HOME_DIR" -s /bin/bash -M "$CONTAINER_USER"
fi

export HOME="$HOME_DIR"

# setpriv は util-linux 同梱（追加パッケージ不要）
exec setpriv --reuid "$HOST_UID" --regid "$HOST_GID" --init-groups "$@"
