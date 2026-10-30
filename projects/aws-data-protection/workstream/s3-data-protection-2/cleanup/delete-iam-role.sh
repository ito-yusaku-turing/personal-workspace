#!/usr/bin/env bash
# IAM ロールを消す。既定は空実行（何を消すかを表示するだけ）。--apply を付けたときだけ消す。
#
#   ./delete-iam-role.sh <プロファイル> <ロール名> [--apply] [--delete-own-policies]
#
# - 付いている管理ポリシーを外し、インラインのポリシーを消し、インスタンスプロファイルから外してから、ロールを消す。
# - ロールと同じ名前のインスタンスプロファイルは、ほかのロールが入っていなければ一緒に消す。
# - --delete-own-policies: 外したカスタマー管理ポリシーのうち、どこにも付いていなくなったものを消す（古い版も消す）。
# - 消す前の定義は backup/ に控えてある（戻し方は cleanup-runbook.md の「戻し方」）。
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "使い方: $0 <プロファイル> <ロール名> [--apply] [--delete-own-policies]" >&2
  exit 2
fi
PROFILE=$1
ROLE=$2
shift 2
APPLY=false
OWN=false
for a in "$@"; do
  case $a in
    --apply) APPLY=true ;;
    --delete-own-policies) OWN=true ;;
    *) echo "知らない引数: $a" >&2; exit 2 ;;
  esac
done

aws_() { aws --profile "$PROFILE" "$@"; }
run() {
  if $APPLY; then
    echo "+ aws $*"
    aws_ "$@"
  else
    echo "（空実行）aws $*"
  fi
}

aws_ iam get-role --role-name "$ROLE" --query 'Role.[Arn,RoleLastUsed.LastUsedDate]' --output text

OWN_POLICIES=()
for arn in $(aws_ iam list-attached-role-policies --role-name "$ROLE" --query 'AttachedPolicies[].PolicyArn' --output text); do
  run iam detach-role-policy --role-name "$ROLE" --policy-arn "$arn"
  case $arn in arn:aws:iam::aws:*) ;; *) OWN_POLICIES+=("$arn") ;; esac
done
for name in $(aws_ iam list-role-policies --role-name "$ROLE" --query 'PolicyNames' --output text); do
  run iam delete-role-policy --role-name "$ROLE" --policy-name "$name"
done
for ip in $(aws_ iam list-instance-profiles-for-role --role-name "$ROLE" --query 'InstanceProfiles[].InstanceProfileName' --output text); do
  run iam remove-role-from-instance-profile --instance-profile-name "$ip" --role-name "$ROLE"
  if [ "$ip" = "$ROLE" ]; then
    others=$(aws_ iam get-instance-profile --instance-profile-name "$ip" --query "length(InstanceProfile.Roles[?RoleName!='$ROLE'])" --output text)
    [ "$others" = "0" ] && run iam delete-instance-profile --instance-profile-name "$ip"
  fi
done
run iam delete-role --role-name "$ROLE"

if $OWN; then
  for arn in "${OWN_POLICIES[@]}"; do
    count=$(aws_ iam get-policy --policy-arn "$arn" --query 'Policy.AttachmentCount' --output text)
    # 空実行では外していないので、まだ 1 つ付いている
    if { $APPLY && [ "$count" = "0" ]; } || { ! $APPLY && [ "$count" = "1" ]; }; then
      for v in $(aws_ iam list-policy-versions --policy-arn "$arn" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text); do
        run iam delete-policy-version --policy-arn "$arn" --version-id "$v"
      done
      run iam delete-policy --policy-arn "$arn"
    else
      echo "残す（ほかにも付いている）: $arn"
    fi
  done
fi
