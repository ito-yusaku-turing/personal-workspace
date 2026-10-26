#!/usr/bin/env bash
# ====================================================================================
# GitHub 認証のセットアップ（devbox コンテナの中で実行する）
#
#   ホストからは docker/bin/setup/github.sh を使う（このスクリプトを呼び出す）。
#   何度実行しても安全（既にあるものは壊さない）。
#
#   使い方:
#     setup/github.sh status          いまの状態と次の一手を表示する
#     setup/github.sh git-identity    コミットの著者情報を設定する
#     setup/github.sh ssh-key         規約どおりの鍵を用意し、登録用の情報を出す
#     setup/github.sh gh-login        gh の認証を行う（対話。人間が実行する）
#     setup/github.sh verify          疎通とスコープを検証する
#     setup/github.sh all             上を順に案内する
#
#   このスクリプトが「実行するコマンドの唯一の正本」である。
#   規約とその理由・トラブルシュートは docs/github-setup.md にある。
#   手順の写しをドキュメントやエージェント側に持たせないこと（三重管理になる）。
#
#   人間の操作が必要で自動化できない工程が2つある。
#     - 公開鍵の GitHub への登録: ブラウザで行う。gh ssh-key add は使わない。
#       admin:public_key スコープを devbox のトークンに持たせないため（鍵を追加
#       できるトークンは、revoke しても別の鍵で居座られる余地を残す）。
#     - gh auth login: デバイスコードの入力に TTY が必要。
# ====================================================================================
set -uo pipefail
_self=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")
_self_dir=$(dirname "$_self")
# shellcheck source=../lib/common.sh
. "$_self_dir/../lib/common.sh"
# shellcheck source=../lib/setup-state.sh
. "$_self_dir/../lib/setup-state.sh"
# lib/common.sh が set -e を立てるが、このスクリプトは「失敗しうる検査を続けて
# 結果をまとめて報告する」性質なので外す。GitHub の ssh -T は成功しても終了コード 1
# を返すため、-e のままでは検証の途中で無言のまま死ぬ。
# 中断すべき失敗は die または `|| die` で明示する。
set +e

# 鍵の生成規約（変更する場合は docs/github-setup.md の表も直すこと）
KEY_TYPE=ed25519
KEY_PATH="$HOME/.ssh/id_ed25519"
KEY_PURPOSE="${PROJECT_NAME} devbox"
GH_LOGIN_ARGS=(--hostname github.com --git-protocol ssh --skip-ssh-key --web)
SSH_KEY_URL="https://github.com/settings/ssh/new"

usage() {
	sed -n '3,/^# =\{10,\}/p' "$_self" | sed -e '$d' -e 's/^# \{0,1\}//'
	exit 1
}

interactive() { [[ -t 0 ]]; }

# 状態の1行取得
state_of() { setup_state_of "$1" | cut -f1; }

# ------------------------------------------------------------------------------------
# status
# ------------------------------------------------------------------------------------
cmd_status() {
	local item st
	info "==== GitHub 認証の状態 ===="
	for item in git-identity ssh-key gh-auth; do
		st=$(setup_state_of "$item")
		printf '  %-14s %-9s %s\n' "$item" "${st%%$'\t'*}" "${st#*$'\t'}"
	done
	info ""
	local next=""
	[[ $(state_of git-identity) == missing ]] && next="git-identity"
	[[ -z $next && $(state_of ssh-key) == missing ]] && next="ssh-key"
	[[ -z $next && $(state_of gh-auth) == missing ]] && next="gh-login"
	if [[ -n $next ]]; then
		info "次の一手: docker/container-bin/setup/github.sh $next"
	else
		info "次の一手: docker/container-bin/setup/github.sh verify"
	fi
	note "  使わないと決めた項目は setup/state.sh skip <項目> で宣言できます（催促されなくなります）"
}

# ------------------------------------------------------------------------------------
# git-identity — コミットの著者情報
#   グローバル（~/.gitconfig）に入れる。マウントした他リポジトリにも効かせるため。
#   既にある値は壊さない。
# ------------------------------------------------------------------------------------
cmd_git_identity() {
	local name="" email="" g_name g_email
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--name) name="${2-}"; shift 2 ;;
			--email) email="${2-}"; shift 2 ;;
			*) die "git-identity: 不明な引数: $1" ;;
		esac
	done

	g_name=$(git config --global --get user.name 2>/dev/null || true)
	g_email=$(git config --global --get user.email 2>/dev/null || true)
	if [[ -n $g_name && -n $g_email ]]; then
		ok "git 署名は既に設定されています: $g_name <$g_email>"
		note "  変更する場合: git config --global user.name / user.email"
		_warn_repo_override "$g_name" "$g_email"
		return 0
	fi

	if [[ -z $name || -z $email ]]; then
		# リポジトリ側に値があれば既定として提示する
		local d_name d_email
		d_name=$(git config --get user.name 2>/dev/null || true)
		d_email=$(git config --get user.email 2>/dev/null || true)
		if interactive; then
			read -r -p "氏名 [${d_name}]: " name || name=""
			name="${name:-$d_name}"
			read -r -p "メールアドレス [${d_email}]: " email || email=""
			email="${email:-$d_email}"
		else
			info "グローバルの git 署名が未設定です。次を実行してください（GitHub アカウントのメールを使う）。"
			info ""
			info "  git config --global user.name \"${d_name:-Your Name}\""
			info "  git config --global user.email \"${d_email:-you@example.com}\""
			info ""
			note "  引数でも渡せます: setup/github.sh git-identity --name ... --email ..."
			return 0
		fi
	fi
	[[ -n $name && -n $email ]] || die "氏名とメールアドレスの両方が必要です。"

	git config --global user.name "$name"
	git config --global user.email "$email"
	ok "git 署名を設定しました: $name <$email>（~/.gitconfig）"
	_warn_repo_override "$name" "$email"
}

# リポジトリ側の .git/config がグローバルを上書きしていたら知らせる。
# 意図せず別人名義でコミットする事故を防ぐため。
_warn_repo_override() {
	local g_name="$1" g_email="$2" r_name r_email
	r_name=$(git config --local --get user.name 2>/dev/null || true)
	r_email=$(git config --local --get user.email 2>/dev/null || true)
	if [[ -n $r_name || -n $r_email ]]; then
		if [[ $r_name != "$g_name" || $r_email != "$g_email" ]]; then
			warn "このリポジトリの .git/config が別の著者情報で上書きしています:
       ${r_name:-（未設定）} <${r_email:-（未設定）}>
       意図しない場合は git config --local --unset user.name / user.email"
		fi
	fi
}

# ------------------------------------------------------------------------------------
# ssh-key — 鍵を用意し、GitHub へ貼るための情報を出す
#   登録そのものはブラウザで人間が行う（gh ssh-key add は使わない。冒頭の理由参照）。
# ------------------------------------------------------------------------------------
cmd_ssh_key() {
	local title="" email="" retire=0
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--title) title="${2-}"; shift 2 ;;
			--email) email="${2-}"; shift 2 ;;
			--retire-existing) retire=1; shift ;;
			*) die "ssh-key: 不明な引数: $1" ;;
		esac
	done

	mkdir -p "$HOME/.ssh" || die "$HOME/.ssh を作成できません"
	chmod 700 "$HOME/.ssh" || die "$HOME/.ssh のパーミッションを設定できません"

	if [[ -f $KEY_PATH ]]; then
		ok "鍵は既にあります: ${KEY_PATH}（作り直しません）"
	else
		_retire_other_keys "$retire"
		[[ -n $email ]] || email=$(git config --get user.email 2>/dev/null || true)
		if [[ -z $email ]]; then
			die "コメントに入れるメールアドレスが分かりません。
       先に setup/github.sh git-identity を実行するか、--email で渡してください。"
		fi
		# 規約: ed25519 / 既定ファイル名 / パスフレーズなし / コメントにメール＋用途。
		# パスフレーズなしはエージェントが許可を得た後そのまま push できるようにするため。
		# 緩和策は devbox 専用鍵にして単独で revoke できる状態を保つこと。
		ssh-keygen -t "$KEY_TYPE" -C "$email $KEY_PURPOSE" -f "$KEY_PATH" -N "" -q ||
			die "鍵の生成に失敗しました。"
		chmod 600 "$KEY_PATH"
		chmod 644 "$KEY_PATH.pub"
		ok "鍵を生成しました: ${KEY_PATH}（$KEY_TYPE / パスフレーズなし）"
	fi

	if [[ -z $title ]]; then
		# ホストのマシン名はコンテナから取得できない（HOSTNAME はコンテナ ID）ため、
		# 識別子は人間が入れる。複数マシンで setup したときに鍵一覧で区別するのに使う。
		local d_id="${CONTAINER_USER:-$(id -un)}"
		if interactive; then
			read -r -p "GitHub 上の鍵の識別子（例 ${d_id}@macbook）[${d_id}]: " id_part || id_part=""
			title="$KEY_PURPOSE (${id_part:-$d_id})"
		else
			title="$KEY_PURPOSE (${d_id}@<マシン名を記入>)"
		fi
	fi

	info ""
	info "==== GitHub に公開鍵を登録してください（ブラウザ） ===="
	info "  1) $SSH_KEY_URL を開く"
	info "  2) Key type は Authentication key のまま"
	info "  3) Title に次を入れる"
	info ""
	printf '%s\n' "$title"
	info ""
	info "  4) Key に次の1行を貼る"
	info ""
	cat "$KEY_PATH.pub"
	info ""
	note "  gh ssh-key add は使いません（admin:public_key スコープを持たせない方針）"
	info "  登録したら: docker/container-bin/setup/github.sh verify"
}

# id_ed25519 以外の鍵があるときの扱い。
# 勝手に動かすと動いている鍵を壊しうるので、既定では警告だけに留める。
_retire_other_keys() {
	local retire="$1" k found=0
	for k in "$HOME"/.ssh/id_*; do
		[[ -f $k && $k != *.pub ]] || continue
		found=1
	done
	(( found )) || return 0

	if (( ! retire )); then
		if interactive; then
			local ans
			read -r -p "他の鍵が $HOME/.ssh にあります。~/.ssh/retired/ へ退避しますか? (y/N): " ans || ans=""
			[[ $ans =~ ^[Yy] ]] || { note "  既存の鍵はそのままにします"; return 0; }
		else
			warn "他の鍵が $HOME/.ssh にあります。使っていないなら ~/.ssh/retired/ へ移すと無効化できます
       （ssh はサブディレクトリを走査しません）。退避するには --retire-existing を付けてください。"
			return 0
		fi
	fi

	mkdir -p "$HOME/.ssh/retired"
	chmod 700 "$HOME/.ssh/retired"
	for k in "$HOME"/.ssh/id_*; do
		[[ -e $k ]] || continue
		mv "$k" "$HOME/.ssh/retired/"
	done
	ok "既存の鍵を $HOME/.ssh/retired/ へ退避しました（削除はしていません）"
}

# ------------------------------------------------------------------------------------
# gh-login — gh の認証
#   デバイスコードの入力に TTY が必要なため、エージェントからは実行できない。
#   人間が手で走らせたときだけ実際に gh を起動し、それ以外は手順を出す。
# ------------------------------------------------------------------------------------
cmd_gh_login() {
	command -v gh >/dev/null 2>&1 || die "gh コマンドがありません（イメージが古い可能性: docker/bin/setup/image.sh）"

	if gh auth status >/dev/null 2>&1; then
		ok "gh は既に認証済みです"
		gh auth status 2>&1 | sed 's/^/  /'
		return 0
	fi

	if ! interactive; then
		info "gh の認証は対話が必要です。devbox のシェルで次を実行してください。"
		info ""
		info "  gh auth login ${GH_LOGIN_ARGS[*]}"
		info ""
		info "進行の期待値:"
		info "  1) 8桁のワンタイムコードが表示される"
		info "  2) Enter を押す（コンテナにブラウザは無いので起動失敗のメッセージが出るが正常）"
		info "  3) ホストのブラウザで https://github.com/login/device を開きコードを入力して認可"
		info "  4) ✓ Logged in as <username> が出れば成功"
		info ""
		note "  --skip-ssh-key を付けているため、トークンに admin:public_key は付きません。"
		note "  スコープを足すよう促されても応じないこと（鍵の登録はブラウザで行う方針）。"
		return 0
	fi

	info "gh auth login を開始します（ワンタイムコードをホストのブラウザで入力してください）"
	gh auth login "${GH_LOGIN_ARGS[@]}" || die "gh auth login に失敗しました。
       キーリング関連で失敗する場合は --insecure-storage を付けて平文保存にしてください。"
	ok "gh の認証が完了しました"
}

# ------------------------------------------------------------------------------------
# verify — 疎通とスコープの検証
# ------------------------------------------------------------------------------------
cmd_verify() {
	local rc=0 out scopes

	# GitHub の ssh -T は成功しても終了コード 1 を返す（シェルを提供しないため）。
	# 終了コードでは判定できないので、応答メッセージで判定する。
	out=$(ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1)
	if [[ $out == *"successfully authenticated"* ]]; then
		ok "ssh: ${out%%$'\n'*}"
	else
		warn "ssh: 認証できていません
       $out
       公開鍵が GitHub に未登録か、鍵のパーミッションが緩い可能性があります。
       setup/github.sh ssh-key で貼るべき公開鍵を再表示できます。"
		rc=1
	fi

	# 実際の git 操作（remote が SSH のため上と同じ経路を通る）
	if ! git remote get-url origin >/dev/null 2>&1; then
		note "  git: origin が設定されていないため疎通確認を省略しました"
	elif git ls-remote origin HEAD >/dev/null 2>&1; then
		ok "git: origin へ到達できます"
	else
		warn "git: origin へ到達できません（remote: $(git remote get-url origin 2>/dev/null || echo '?')）"
		rc=1
	fi

	if ! command -v gh >/dev/null 2>&1; then
		warn "gh: コマンドがありません"
		rc=1
	elif out=$(gh auth status 2>&1); then
		ok "gh: $(printf '%s' "$out" | sed -n 's/.*Logged in to [^ ]* account \([^ ]*\).*/\1/p' | head -1) として認証済み"
		scopes=$(printf '%s' "$out" | sed -n 's/.*Token scopes: *//p' | head -1 | tr -d "'")
		info "     scopes: ${scopes:-?}"
		# 方針の実測確認。鍵登録をブラウザに寄せた理由がここで担保されている
		if [[ $scopes == *admin:public_key* ]]; then
			warn "gh: トークンが admin:public_key を保持しています。方針では不要です。"
			rc=1
		else
			ok "gh: admin:public_key を保持していません（方針どおり）"
		fi
		if ! git remote get-url origin >/dev/null 2>&1; then
			note "  gh: origin が無いため API 疎通の確認を省略しました"
		elif gh pr list --limit 1 >/dev/null 2>&1; then
			ok "gh: API 疎通 OK（PR 一覧を取得できました）"
		else
			warn "gh: API 疎通に失敗しました（組織の SSO 認可が必要な可能性）"
			rc=1
		fi
	else
		warn "gh: 未認証 → setup/github.sh gh-login"
		rc=1
	fi

	info ""
	if (( rc == 0 )); then
		ok "GitHub 認証はすべて期待どおりです"
	else
		info "未完了の項目があります。使わないと決めた項目は次で宣言できます:"
		info "  docker/container-bin/setup/state.sh skip <項目>"
	fi
	return "$rc"
}

# ------------------------------------------------------------------------------------
# all — 順に案内する
# ------------------------------------------------------------------------------------
cmd_all() {
	cmd_git_identity
	info ""
	cmd_ssh_key
	info ""
	cmd_gh_login
	info ""
	cmd_verify || true
}

# ====================================================================================
cmd="${1-status}"
[[ $# -gt 0 ]] && shift
case "$cmd" in
	status) cmd_status "$@" ;;
	git-identity) cmd_git_identity "$@" ;;
	ssh-key) cmd_ssh_key "$@" ;;
	gh-login) cmd_gh_login "$@" ;;
	verify) cmd_verify "$@" ;;
	all) cmd_all "$@" ;;
	-h | --help | help) usage ;;
	*) die "不明なサブコマンド: ${cmd}（--help を参照）" ;;
esac
