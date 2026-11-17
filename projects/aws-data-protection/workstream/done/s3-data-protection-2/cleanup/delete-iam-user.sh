#!/usr/bin/env bash
# IAM ユーザーを消す。既定は空実行（何を消すかを表示するだけ）。--apply を付けたときだけ消す。
#
#   ./delete-iam-user.sh <プロファイル> <ユーザー名> [--apply]
#
# - アクセスキー・ログイン・MFA・署名の証明書・SSH の鍵・サービス用の認証情報を消し、
#   ポリシーとグループを外してから、ユーザーを消す。
# - 有効なアクセスキーが残っていたら止まる（使われている可能性があるため）。
# - 消す前の定義は backup/ に控えてある（キーの中身は控えていないので、キーは戻せない）。
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "使い方: $0 <プロファイル> <ユーザー名> [--apply]" >&2
  exit 2
fi
PROFILE=$1
USER_NAME=$2
APPLY=false
[ "${3:-}" = "--apply" ] && APPLY=true

aws_() { aws --profile "$PROFILE" "$@"; }
run() {
  if $APPLY; then
    echo "+ aws $*"
    aws_ "$@"
  else
    echo "（空実行）aws $*"
  fi
}

active=$(aws_ iam list-access-keys --user-name "$USER_NAME" --query 'length(AccessKeyMetadata[?Status==`Active`])' --output text)
if [ "$active" != "0" ]; then
  echo "有効なアクセスキーが $active 本あるので止める: $USER_NAME" >&2
  exit 1
fi

for k in $(aws_ iam list-access-keys --user-name "$USER_NAME" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
  echo "キー $k の最終利用: $(aws_ iam get-access-key-last-used --access-key-id "$k" --query 'AccessKeyLastUsed.LastUsedDate' --output text)"
  run iam delete-access-key --user-name "$USER_NAME" --access-key-id "$k"
done
if aws_ iam get-login-profile --user-name "$USER_NAME" >/dev/null 2>&1; then
  run iam delete-login-profile --user-name "$USER_NAME"
fi
for sn in $(aws_ iam list-mfa-devices --user-name "$USER_NAME" --query 'MFADevices[].SerialNumber' --output text); do
  run iam deactivate-mfa-device --user-name "$USER_NAME" --serial-number "$sn"
  case $sn in *:mfa/*) run iam delete-virtual-mfa-device --serial-number "$sn" ;; esac
done
for c in $(aws_ iam list-signing-certificates --user-name "$USER_NAME" --query 'Certificates[].CertificateId' --output text); do
  run iam delete-signing-certificate --user-name "$USER_NAME" --certificate-id "$c"
done
for k in $(aws_ iam list-ssh-public-keys --user-name "$USER_NAME" --query 'SSHPublicKeys[].SSHPublicKeyId' --output text); do
  run iam delete-ssh-public-key --user-name "$USER_NAME" --ssh-public-key-id "$k"
done
for c in $(aws_ iam list-service-specific-credentials --user-name "$USER_NAME" --query 'ServiceSpecificCredentials[].ServiceSpecificCredentialId' --output text); do
  run iam delete-service-specific-credential --user-name "$USER_NAME" --service-specific-credential-id "$c"
done
for arn in $(aws_ iam list-attached-user-policies --user-name "$USER_NAME" --query 'AttachedPolicies[].PolicyArn' --output text); do
  run iam detach-user-policy --user-name "$USER_NAME" --policy-arn "$arn"
done
for name in $(aws_ iam list-user-policies --user-name "$USER_NAME" --query 'PolicyNames' --output text); do
  run iam delete-user-policy --user-name "$USER_NAME" --policy-name "$name"
done
for g in $(aws_ iam list-groups-for-user --user-name "$USER_NAME" --query 'Groups[].GroupName' --output text); do
  run iam remove-user-from-group --user-name "$USER_NAME" --group-name "$g"
done
run iam delete-user --user-name "$USER_NAME"
