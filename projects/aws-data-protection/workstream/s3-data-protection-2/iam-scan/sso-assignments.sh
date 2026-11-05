#!/usr/bin/env bash
# IAM Identity Center の権限セットの割り当てを、人の単位まで展開して TSV で出す（読み取りだけ）。
#
# 使い方（管理アカウントを読めるプロファイルで。ホストの default など）:
#   PROFILE=default bash sso-assignments.sh [アカウント ID ...] > out.tsv
#   アカウント ID を省くと tuscenes-prod（767397804933）だけ。
#
# 出力の列: アカウント 権限セット 主体の種類 グループ名 ユーザー名 表示名
#   グループ経由の割り当ては、グループのメンバーごとに 1 行。直接の割り当ては グループ名が「-」。
# 呼ぶ API は sso-admin と identitystore の List/Describe だけ。書き込みはしない。
set -euo pipefail

PROFILE=${PROFILE:-default}
REGION=${REGION:-us-west-2}
ACCOUNTS=("$@")
[ ${#ACCOUNTS[@]} -eq 0 ] && ACCOUNTS=(767397804933)
AWS=(aws --profile "$PROFILE" --region "$REGION" --output text)

read -r INSTANCE STORE < <("${AWS[@]}" sso-admin list-instances --query 'Instances[0].[InstanceArn,IdentityStoreId]')
echo "# $(date -u +%FT%TZ) instance=$INSTANCE store=$STORE profile=$PROFILE" >&2

declare -A GROUP_NAME USER_LINE
group_name() {
  [ -n "${GROUP_NAME[$1]:-}" ] || GROUP_NAME[$1]=$("${AWS[@]}" identitystore describe-group --identity-store-id "$STORE" --group-id "$1" --query DisplayName)
  echo "${GROUP_NAME[$1]}"
}
user_line() {
  [ -n "${USER_LINE[$1]:-}" ] || USER_LINE[$1]=$("${AWS[@]}" identitystore describe-user --identity-store-id "$STORE" --user-id "$1" --query '[UserName,DisplayName]')
  echo "${USER_LINE[$1]}"
}

printf 'account\tpermission_set\tprincipal_type\tgroup\tuser\tdisplay_name\n'
for acc in "${ACCOUNTS[@]}"; do
  for ps in $("${AWS[@]}" sso-admin list-permission-sets-provisioned-to-account --instance-arn "$INSTANCE" --account-id "$acc" --query 'PermissionSets[]'); do
    name=$("${AWS[@]}" sso-admin describe-permission-set --instance-arn "$INSTANCE" --permission-set-arn "$ps" --query PermissionSet.Name)
    "${AWS[@]}" sso-admin list-account-assignments --instance-arn "$INSTANCE" --account-id "$acc" --permission-set-arn "$ps" \
      --query 'AccountAssignments[].[PrincipalType,PrincipalId]' |
    while read -r type pid; do
      [ -z "$type" ] && continue
      if [ "$type" = GROUP ]; then
        g=$(group_name "$pid")
        members=$("${AWS[@]}" identitystore list-group-memberships --identity-store-id "$STORE" --group-id "$pid" --query 'GroupMemberships[].MemberId.UserId')
        [ -z "$members" ] && printf '%s\t%s\tGROUP\t%s\t(メンバーなし)\t-\n' "$acc" "$name" "$g"
        for uid in $members; do
          printf '%s\t%s\tGROUP\t%s\t%s\n' "$acc" "$name" "$g" "$(user_line "$uid")"
        done
      else
        printf '%s\t%s\tUSER\t-\t%s\n' "$acc" "$name" "$(user_line "$pid")"
      fi
    done
  done
done
