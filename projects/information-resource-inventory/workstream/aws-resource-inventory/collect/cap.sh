#!/usr/bin/env bash
# AWS の読み取りの API を 1 回呼び、応答を伏せ字にして一次情報として保存する。
#   cap.sh <region|global> <service> <name> <aws の引数...>
# 保存先: $AWS_INV_DIR/$AWS_INV_DATE/<region>/<service>/<name>.json（既にあれば呼ばずに飛ばす）
# ログ:   $AWS_INV_DIR/$AWS_INV_DATE/_log.tsv（時刻・リージョン・サービス・名前・終了コード・伏せた件数・コマンド）
set -uo pipefail
[ $# -ge 4 ] || { echo "usage: cap.sh <region|global> <service> <name> <aws args...>" >&2; exit 2; }
region=$1 service=$2 name=$3; shift 3
base=${AWS_INV_DIR:-$HOME/aws/tuscenes-prod}/${AWS_INV_DATE:-$(date -u +%F)}
out=$base/$region/$service/$name.json
[ -s "$out" ] && { echo "skip $out" >&2; exit 0; }
mkdir -p "$(dirname "$out")"
api_region=$region; [ "$region" = global ] && api_region=us-east-1
export AWS_RETRY_MODE=adaptive AWS_MAX_ATTEMPTS=10 AWS_PAGER=""
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp); err=$(mktemp)
aws --profile "${AWS_INV_PROFILE:-readonly}" --region "$api_region" --output json "$@" >"$tmp" 2>"$err"
rc=$?
n=-
if [ $rc -eq 0 ]; then
  n=$(python3 -I "$here/redact.py" <"$tmp" 2>&1 >"$out.part") && mv "$out.part" "$out" || { rc=97; rm -f "$out.part"; }
else
  # 失敗は .err に残す（権限なし・未対応リージョンも一次情報）
  python3 -I -c 'import sys,re;print(re.sub(r"(AKIA|ASIA)[A-Z0-9]{16}","<REDACTED>",sys.stdin.read()),end="")' <"$err" >"${out%.json}.err"
fi
rm -f "$tmp" "$err"
printf '%s\t%s\t%s\t%s\t%s\t%s\taws %s\n' "$(date -u +%FT%TZ)" "$region" "$service" "$name" "$rc" "$n" "$*" >>"$base/_log.tsv"
exit $rc
