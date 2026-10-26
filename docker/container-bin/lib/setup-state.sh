#!/usr/bin/env bash
# ====================================================================================
# セットアップ項目の状態モデル
#
#   「まだ着手していない」と「使わないと決めた」を区別する。この2つを混ぜると、
#   使わない開発者に永久に催促が出続け、エージェントは催促すべきか迂回すべきかを
#   判断できない。
#
#   実効状態は次の2つの積で決まる。
#     宣言 : setup-state.conf に書かれた skip（人間が書く）
#     探知 : いま実際に使える状態かどうか（毎回ライブに調べる）
#
#   ★ 探知結果はキャッシュしない。陳腐化した状態が嘘をつくのが典型的な失敗のため、
#     状態ファイルには「使わない」という宣言だけを書く。
#
#   実効状態:
#     ok        使える
#     missing   未着手（案内する）
#     declined  使わないと宣言済み（黙って迂回する）
#     conflict  使わないと宣言したが設定が存在する（宣言の見直しを促す）
#     error     設定はあるが検証に失敗した（原因を提示する）
#
#   ★ 項目の集合はプロジェクトの構成で変わる。docker/config/project.conf で
#     同梱していないツール（DEVBOX_WITH_* = 0）の項目は最初から現れない。
#     使わないツールの催促が出ないことと、宣言の手間が要らないことを両立させるため。
#
#   このファイルは container-bin/lib/common.sh を source した後に読み込むこと。
# ====================================================================================

# 機械可読出力の契約バージョン。項目名や状態の語彙を変えたら +1 する。
SETUP_STATE_SCHEMA=1

# 宣言ファイル（コンテナ HOME 配下 = ホストの $USER_HOME_DIR 配下 = git 管理外）。
# 検証時に別のファイルを読ませられるよう、既に設定されていればそれを尊重する。
SETUP_STATE_FILE="${SETUP_STATE_FILE:-$PERSONAL_CONFIG_DIR/setup-state.conf}"

# ------------------------------------------------------------------------------------
# 項目の定義
#   SETUP_ITEMS       : 機械可読出力に出す全項目（順序を保つため配列）
#   SETUP_ITEMS_HUMAN : doctor.sh の人間向け表示に出す項目。
#                       node-modules / app-env はホスト側の doctor.sh が既に
#                       表示しているため人間向けからは省くが、porcelain には含める
#                       （エージェントはコンテナ内から1コマンドで全部を得たいため）。
#   SETUP_DECLINABLE  : 「使わない」を宣言できるか。
#                       前提条件（node_modules 等）はメニュー項目ではないので対象外。
#
#   項目を増やすときは、_probe_<項目名のハイフンをアンダースコアに> 関数と
#   下の4つの連想配列に1行ずつ足す。
# ------------------------------------------------------------------------------------
SETUP_ITEMS=(git-identity ssh-key gh-auth agent-prefs)
SETUP_ITEMS_HUMAN=(git-identity gh-auth agent-prefs ssh-key)

# 同梱しているツールの項目だけを足す（project.conf の DEVBOX_WITH_*）。
# set -e が有効な文脈で source されうるので、条件は if で書く
# （`[[ ]] && ...` は偽のとき行全体が非ゼロを返し、読み込み中のスクリプトを落とす）。
if [[ ${DEVBOX_WITH_AWS:-0} == 1 ]]; then
	SETUP_ITEMS+=(aws); SETUP_ITEMS_HUMAN+=(aws)
fi
if [[ ${DEVBOX_WITH_DATABRICKS:-0} == 1 ]]; then
	SETUP_ITEMS+=(databricks); SETUP_ITEMS_HUMAN+=(databricks)
fi
if [[ ${DEVBOX_WITH_GCLOUD:-0} == 1 ]]; then
	SETUP_ITEMS+=(gcloud); SETUP_ITEMS_HUMAN+=(gcloud)
fi
SETUP_ITEMS+=(codex)
SETUP_ITEMS_HUMAN+=(codex)
# アプリの環境変数ファイルを持つプロジェクトだけ
if [[ -n ${APP_ENV_FILE:-} ]]; then
	SETUP_ITEMS+=(app-env)
fi
# 依存関係を持つプロジェクトだけ
if [[ -f "$REPO_DIR/package.json" ]]; then
	SETUP_ITEMS+=(node-modules)
fi

declare -A SETUP_LABEL=(
	[git-identity]="git 署名"
	[ssh-key]="ssh 鍵"
	[gh-auth]="gh (GitHub CLI)"
	[agent-prefs]="エージェント設定"
	[aws]="aws"
	[databricks]="databricks"
	[gcloud]="gcloud"
	[codex]="codex"
	[app-env]="${APP_ENV_FILE:-アプリ環境変数}"
	[node-modules]="node_modules"
)

declare -A SETUP_DECLINABLE=(
	[git-identity]=1
	[ssh-key]=1
	[gh-auth]=1
	[agent-prefs]=1
	[aws]=1
	[databricks]=1
	[gcloud]=1
	[codex]=1
	[app-env]=0
	[node-modules]=0
)

# missing のときに案内する文言
declare -A SETUP_HINT=(
	[git-identity]="docker/container-bin/setup/github.sh git-identity"
	[ssh-key]="docker/container-bin/setup/github.sh ssh-key"
	[gh-auth]="docker/container-bin/setup/github.sh gh-login"
	[agent-prefs]="setup/config.sh で雛形を配置（既定はすべて都度確認）"
	[aws]="\$USER_HOME_DIR/.aws に配置、または環境変数の AWS_*"
	[databricks]="\$USER_HOME_DIR/.databrickscfg、または環境変数の DATABRICKS_*"
	[gcloud]="gcloud auth application-default login"
	[codex]="docker/bin/codex.sh が導入します"
	[app-env]="プロジェクトの README を参照"
	[node-modules]="docker/bin/shell.sh のうえ npm ci"
)

# missing のときのラベル（既定は「未設定」。ツールの導入は「未導入」が実態に合う）
declare -A SETUP_MISSING_LABEL=(
	[codex]="未導入"
	[node-modules]="なし"
	[app-env]="なし"
)

# declined を選んだとき何が使えなくなるか（doctor.sh が表示し、doc からも参照する）
declare -A SETUP_IMPACT=(
	[git-identity]="commit ができません"
	[ssh-key]="push / fetch ができません"
	[gh-auth]="PR の作成・一覧ができません"
	[agent-prefs]="エージェントは全操作を都度確認します"
	[aws]="AWS を使う機能が動きません"
	[databricks]="Databricks を使う機能が動きません"
	[gcloud]="Google Cloud を使う機能が動きません"
	[codex]="Codex CLI を使いません"
)

_have() { command -v "$1" >/dev/null 2>&1; }

# アプリの環境変数ファイルに指定のキーがすべて定義されているか（値は読まない / ログにも出さない）。
# クレデンシャルはコンテナ HOME 配下だけでなくこのファイル経由でも渡せるため、
# 探知がそちらを見落とすと「資格情報はあるのに missing」という嘘の状態になる。
_app_env_has() {
	local f="$REPO_DIR/${APP_ENV_FILE:-}" k
	[[ -n ${APP_ENV_FILE:-} && -f $f ]] || return 1
	for k in "$@"; do
		grep -qE "^[[:space:]]*${k}=." "$f" 2>/dev/null || return 1
	done
	return 0
}

# ------------------------------------------------------------------------------------
# 探知（probe）
#   いずれも "状態<TAB>詳細" を1行で返す。状態は ok / missing / error のみ。
#   declined / conflict は宣言と突き合わせて上位で決まる。
#   -e が有効な文脈で source されても止まらないよう、失敗しうる箇所は必ず受け止める。
# ------------------------------------------------------------------------------------

# git の著者情報。$REPO_DIR にいるためリポジトリ側の設定も含めた実効値を見る。
# グローバルに無くリポジトリ側だけで効いている場合は、マウントした他リポジトリでは
# 著者情報が無いことになるため、詳細でそれを伝える。
_probe_git_identity() {
	local name email global_name
	name=$(git config --get user.name 2>/dev/null || true)
	email=$(git config --get user.email 2>/dev/null || true)
	if [[ -z $name || -z $email ]]; then
		printf 'missing\t\n'
		return
	fi
	global_name=$(git config --global --get user.name 2>/dev/null || true)
	if [[ -z $global_name ]]; then
		printf 'ok\t%s <%s> (リポジトリ設定のみ / 他リポジトリでは未設定)\n' "$name" "$email"
	else
		printf 'ok\t%s <%s>\n' "$name" "$email"
	fi
}

# 鍵ファイルの存在だけを見る（ローカルで完結するため速い）。
# GitHub に登録済みで実際に認証が通るかは setup/github.sh verify が確かめる。
# ここで毎回 ssh -T を叩くと、状態の問い合わせがネットワーク障害で失敗しうる。
_probe_ssh_key() {
	local -a keys=()
	local k
	for k in "$HOME"/.ssh/id_*; do
		[[ -f $k && $k != *.pub ]] && keys+=("$(basename "$k")")
	done
	if (( ${#keys[@]} == 0 )); then
		printf 'missing\t\n'
	else
		printf 'ok\t%s (%s) — 疎通は setup/github.sh verify で確認\n' "$HOME/.ssh" "${keys[*]}"
	fi
}

# gh の認証。トークンのスコープも返す。
# admin:public_key を持たせない方針（鍵登録はブラウザで人間が行う）なので、
# 付いていたら詳細に印を付けて doctor.sh が警告できるようにする。
_probe_gh_auth() {
	local out account scopes
	if ! _have gh; then
		printf 'error\tgh コマンドがありません（イメージが古い可能性: docker/bin/setup/image.sh）\n'
		return
	fi
	if ! out=$(gh auth status 2>&1); then
		printf 'missing\t\n'
		return
	fi
	account=$(printf '%s' "$out" | sed -n 's/.*Logged in to [^ ]* account \([^ ]*\).*/\1/p' | head -1)
	scopes=$(printf '%s' "$out" | sed -n "s/.*Token scopes: *//p" | head -1 | tr -d "'" | tr -s ' ')
	if [[ $scopes == *admin:public_key* ]]; then
		printf 'ok\t%s / scopes: %s / ★admin:public_key を保持（方針では不要）\n' "${account:-?}" "${scopes:-?}"
	else
		printf 'ok\t%s / scopes: %s\n' "${account:-?}" "${scopes:-?}"
	fi
}

_probe_agent_prefs() {
	if [[ -f $AGENT_PREFS_DEST ]]; then
		printf 'ok\t%s\n' "$AGENT_PREFS_DEST"
	else
		printf 'missing\t\n'
	fi
}

# 設定の存在と、実際に認証が通るかを分けて報告する。
# 「設定はあるが sts が失敗する」という中間状態が実在するため error が必要。
# ~/.aws が無くても環境変数の AWS_* で使えるので、そちらも見る。
_probe_aws() {
	local ident
	if ! _have aws; then
		printf 'error\taws CLI がありません（イメージが古い可能性）\n'
		return
	fi
	if [[ ! -d "$HOME/.aws" ]]; then
		if _app_env_has AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; then
			printf 'ok\t%s の AWS_*（環境変数として渡せば使える / 未検証）\n' "$APP_ENV_FILE"
		else
			printf 'missing\t\n'
		fi
		return
	fi
	if ident=$(timeout 15 aws sts get-caller-identity --query Arn --output text 2>/dev/null); then
		printf 'ok\t%s\n' "$ident"
	else
		printf 'error\t設定はあるが認証確認に失敗（AWS_PROFILE 未指定 / 期限切れの可能性）\n'
	fi
}

# 資格情報の在処が2通りある。人が入れる ADC（application_default_credentials.json）と、
# サービスアカウントの鍵（GOOGLE_APPLICATION_CREDENTIALS）。前者はプローブや手作業、
# 後者は自動実行で使うため、どちらでも ok とする。
#
# ★ トークンは絶対に出力しない。`gcloud auth print-access-token` は検証には使えるが、
#   標準出力がそのままアクセストークンなので、詳細に混ぜると doctor の出力とログに
#   資格情報が載る。**通ったかどうかだけを見て、表示するのはアカウント名に留める。**
_probe_gcloud() {
	local adc="${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}/application_default_credentials.json"
	local account
	if ! _have gcloud; then
		printf 'error\tgcloud CLI がありません（イメージが古い可能性: docker/bin/setup/image.sh）\n'
		return
	fi
	if [[ ! -f $adc ]] && ! _app_env_has GOOGLE_APPLICATION_CREDENTIALS; then
		printf 'missing\t\n'
		return
	fi
	if [[ ! -f $adc ]]; then
		printf 'ok\t%s の GOOGLE_APPLICATION_CREDENTIALS（未検証）\n' "$APP_ENV_FILE"
		return
	fi
	# 実際にトークンが取れるかまで見る。ADC のファイルはあるが期限切れ・失効という
	# 中間状態が実在し、そこを missing と混ぜると「未着手」に見えてしまう。
	if timeout 20 gcloud auth application-default print-access-token >/dev/null 2>&1; then
		account=$(gcloud config get-value account 2>/dev/null | grep -v '^(unset)$' || true)
		printf 'ok\tADC%s\n' "${account:+ / $account}"
	else
		printf 'error\tADC はあるが取得に失敗（期限切れ / 失効の可能性: gcloud auth application-default login）\n'
	fi
}

# ~/.databrickscfg が無くても環境変数の DATABRICKS_* で CLI は動くため、
# 設定ファイルの有無だけで missing と断じない。
_probe_databricks() {
	if ! _have databricks; then
		printf 'error\tdatabricks CLI がありません（イメージが古い可能性）\n'
		return
	fi
	if [[ -f "$HOME/.databrickscfg" ]]; then
		printf 'ok\t%s\n' "$HOME/.databrickscfg"
	elif _app_env_has DATABRICKS_HOST DATABRICKS_TOKEN; then
		printf 'ok\t%s の DATABRICKS_*（環境変数として渡せば使える / 未検証）\n' "$APP_ENV_FILE"
	elif _app_env_has DATABRICKS_HOST DATABRICKS_CLIENT_ID DATABRICKS_CLIENT_SECRET; then
		printf 'ok\t%s の DATABRICKS_*（OAuth / 未検証）\n' "$APP_ENV_FILE"
	else
		printf 'missing\t\n'
	fi
}

_probe_codex() {
	if _have codex; then
		printf 'ok\t%s\n' "$(codex --version 2>/dev/null || echo あり)"
	else
		printf 'missing\t\n'
	fi
}

_probe_app_env() {
	if [[ -n ${APP_ENV_FILE:-} && -f "$REPO_DIR/$APP_ENV_FILE" ]]; then
		printf 'ok\t\n'
	else
		printf 'missing\t\n'
	fi
}

_probe_node_modules() {
	if [[ -d "$REPO_DIR/node_modules" ]]; then printf 'ok\t\n'; else printf 'missing\t\n'; fi
}

# ------------------------------------------------------------------------------------
# 宣言（declaration）
#   書式は repos.conf と同じ空白区切り。YAML パーサを前提にしない。
#     <項目>  skip  [理由]
#   シェルで source はしない（任意コード実行になるため）。
# ------------------------------------------------------------------------------------

# 指定項目が skip 宣言されていれば理由（無ければ空文字）を返し、成功で抜ける。
setup_state_declared_skip() {
	local want="$1" line item verb rest
	[[ -f $SETUP_STATE_FILE ]] || return 1
	while IFS= read -r line || [[ -n $line ]]; do
		line="${line%%#*}"
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ -z $line ]] && continue
		# shellcheck disable=SC2086
		set -- $line
		item="${1-}"; verb="${2-}"; shift 2 2>/dev/null || true
		rest="$*"
		[[ $item == "$want" && $verb == "skip" ]] || continue
		printf '%s' "$rest"
		return 0
	done <"$SETUP_STATE_FILE"
	return 1
}

# 宣言ファイルに書かれているが定義に無い項目名を列挙する（綴り間違いの検出）
setup_state_unknown_items() {
	local line item known k
	[[ -f $SETUP_STATE_FILE ]] || return 0
	while IFS= read -r line || [[ -n $line ]]; do
		line="${line%%#*}"
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ -z $line ]] && continue
		# shellcheck disable=SC2086
		set -- $line
		item="${1-}"
		known=0
		for k in "${SETUP_ITEMS[@]}"; do [[ $k == "$item" ]] && known=1 && break; done
		(( known )) || printf '%s\n' "$item"
	done <"$SETUP_STATE_FILE"
}

# ------------------------------------------------------------------------------------
# 実効状態 = 宣言 × 探知
#   "状態<TAB>詳細" を返す。
# ------------------------------------------------------------------------------------
setup_state_of() {
	local item="$1" probe_fn probed state detail reason
	probe_fn="_probe_${item//-/_}"
	if ! declare -F "$probe_fn" >/dev/null 2>&1; then
		printf 'error\t探知の実装がありません: %s\n' "$item"
		return
	fi
	probed=$("$probe_fn")
	state="${probed%%$'\t'*}"
	detail="${probed#*$'\t'}"

	if reason=$(setup_state_declared_skip "$item"); then
		if [[ $state == ok ]]; then
			# 使わないと宣言したのに設定が存在する。壊さず警告だけに留める。
			printf 'conflict\t宣言は skip だが設定が存在する: %s\n' "$detail"
		else
			printf 'declined\t%s\n' "$reason"
		fi
		return
	fi
	printf '%s\t%s\n' "$state" "$detail"
}

# ------------------------------------------------------------------------------------
# 機械可読出力
#   TSV を主にする。コンテナには jq / python3 があるが、ホスト側の前提を
#   Docker + bash だけに保つため（repos.conf を YAML にしなかったのと同じ理由）。
#   SETUP_STATE_NO_HEADER=1 でヘッダを抑制できる（ホスト側の doctor.sh が
#   自分の項目に続けてコンテナ側の出力を連結するため）。
# ------------------------------------------------------------------------------------
setup_state_porcelain() {
	local item st
	if [[ ${SETUP_STATE_NO_HEADER-} != 1 ]]; then
		printf '# devbox-setup-state %s\n' "$SETUP_STATE_SCHEMA"
	fi
	for item in "${SETUP_ITEMS[@]}"; do
		st=$(setup_state_of "$item")
		printf '%s\t%s\n' "$item" "$st"
	done
}
