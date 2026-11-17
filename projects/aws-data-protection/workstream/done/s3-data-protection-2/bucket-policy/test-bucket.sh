#!/bin/bash
# 第 1 段のバケットポリシーを、使い捨てのバケットで試す。人が Full 権限で実行する（エージェントは実行しない）。
# 使い方: bash test-bucket.sh setup|denied|exempt|cleanup
#   PROFILE を変えるときは PROFILE=xxx bash test-bucket.sh ...（既定は full）
set -u
cd "$(dirname "$0")"
PROFILE=${PROFILE:-full}
ACC=767397804933
B=s3-policy-test-$ACC
ROLE=s3-policy-test-denied
A=(--region us-west-2)

# 実行する人のロール（一時的なロールの信頼先にする）を、今のセッションから求める
CALLER=$(aws sts get-caller-identity --profile "$PROFILE" --query Arn --output text) || exit 1
[[ $CALLER == arn:aws:sts::$ACC:assumed-role/* ]] || { echo "tuscenes-prod の SSO のセッションではない: $CALLER"; exit 1; }
RUNNER_ROLE=$(cut -d/ -f2 <<<"$CALLER")
case $RUNNER_ROLE in
  AWSReservedSSO_FullAccess_*|AWSReservedSSO_AWSAdministratorAccess_*) ;;
  *) echo "例外の主体（FullAccess か AWSAdministratorAccess）で実行する: $RUNNER_ROLE"; exit 1;;
esac
FULL_ROLE_ARN=$(aws iam get-role --profile "$PROFILE" --role-name "$RUNNER_ROLE" --query Role.Arn --output text) || exit 1

# 期待どおりかを 1 行で出す。$1=期待（allow|deny） $2=操作名 以降=コマンド
expect() {
  local want=$1 name=$2; shift 2
  local err; err=$("$@" 2>&1 >/dev/null); local rc=$?
  local got
  if [ $rc -eq 0 ]; then got=allow
  elif grep -q "AccessDenied" <<<"$err"; then got=deny
  else got="error: $(tail -1 <<<"$err")"; fi
  if [ "$got" = "$want" ]; then echo "OK  $name: $got"; else echo "NG  $name: 期待 $want / 結果 $got"; fi
}

v1() { aws s3api list-object-versions "${A[@]}" --profile "$PROFILE" --bucket $B --prefix test.txt \
  --query 'Versions[?IsLatest==`false`]|[0].VersionId' --output text; }

case ${1:-} in
setup)
  set -e
  aws s3api create-bucket "${A[@]}" --profile "$PROFILE" --bucket $B --create-bucket-configuration LocationConstraint=us-west-2
  aws s3api put-bucket-versioning "${A[@]}" --profile "$PROFILE" --bucket $B --versioning-configuration Status=Enabled
  echo v1 | aws s3 cp - s3://$B/test.txt "${A[@]}" --profile "$PROFILE"
  echo v2 | aws s3 cp - s3://$B/test.txt "${A[@]}" --profile "$PROFILE"
  aws iam create-role --profile "$PROFILE" --role-name $ROLE --max-session-duration 3600 \
    --assume-role-policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"$FULL_ROLE_ARN\"},\"Action\":\"sts:AssumeRole\"}]}" >/dev/null
  aws iam put-role-policy --profile "$PROFILE" --role-name $ROLE --policy-name s3-all-on-test-bucket \
    --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"s3:*\",\"Resource\":[\"arn:aws:s3:::$B\",\"arn:aws:s3:::$B/*\"]}]}"
  aws s3api put-bucket-policy "${A[@]}" --profile "$PROFILE" --bucket $B --policy file://test-policy.json
  echo "setup 完了。IAM の反映を待つため、30 秒ほどおいてから denied を実行する"
  ;;
denied)
  # 例外に当たらない主体（s3:* を持つ一時的なロール）で、2 文が拒否することを確かめる
  V1=$(v1)
  C=$(aws sts assume-role --profile "$PROFILE" --role-arn arn:aws:iam::$ACC:role/$ROLE --role-session-name policy-test \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text) || exit 1
  read -r AK SK ST <<<"$C"
  T=(env -u AWS_PROFILE AWS_ACCESS_KEY_ID=$AK AWS_SECRET_ACCESS_KEY=$SK AWS_SESSION_TOKEN=$ST aws "${A[@]}")
  echo "--- 一時的なロール（例外に当たらない主体）"
  expect allow "PutObject（上書き）"           "${T[@]}" s3api put-object --bucket $B --key test2.txt
  expect allow "DeleteObject（削除マーカー）"   "${T[@]}" s3api delete-object --bucket $B --key test2.txt
  expect deny  "DeleteObjectVersion（古い版）"  "${T[@]}" s3api delete-object --bucket $B --key test.txt --version-id "$V1"
  expect deny  "DeleteBucket"                   "${T[@]}" s3api delete-bucket --bucket $B
  expect deny  "PutObjectLockConfiguration"     "${T[@]}" s3api put-object-lock-configuration --bucket $B --object-lock-configuration ObjectLockEnabled=Enabled
  expect deny  "PutBucketVersioning（停止）"    "${T[@]}" s3api put-bucket-versioning --bucket $B --versioning-configuration Status=Suspended
  expect deny  "PutBucketLifecycle"             "${T[@]}" s3api put-bucket-lifecycle-configuration --bucket $B --lifecycle-configuration '{"Rules":[{"ID":"t","Status":"Enabled","Filter":{},"NoncurrentVersionExpiration":{"NoncurrentDays":1}}]}'
  expect deny  "DeleteBucketLifecycle"          "${T[@]}" s3api delete-bucket-lifecycle --bucket $B
  expect deny  "PutBucketPolicy"                "${T[@]}" s3api put-bucket-policy --bucket $B --policy file://test-policy.json
  expect deny  "DeleteBucketPolicy"             "${T[@]}" s3api delete-bucket-policy --bucket $B
  expect deny  "PutBucketOwnershipControls"     "${T[@]}" s3api put-bucket-ownership-controls --bucket $B --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'
  expect deny  "PutBucketAcl"                   "${T[@]}" s3api put-bucket-acl --bucket $B --acl private
  ;;
exempt)
  # 例外の主体（FullAccess）が締め出されないことを確かめる
  V1=$(v1)
  P=(aws "${A[@]}" --profile "$PROFILE")
  echo "--- FullAccess（例外の主体）"
  expect allow "PutBucketPolicy（同じ文で上書き）" "${P[@]}" s3api put-bucket-policy --bucket $B --policy file://test-policy.json
  expect allow "PutBucketVersioning（有効のまま）" "${P[@]}" s3api put-bucket-versioning --bucket $B --versioning-configuration Status=Enabled
  expect allow "DeleteObjectVersion（古い版）"     "${P[@]}" s3api delete-object --bucket $B --key test.txt --version-id "$V1"
  ;;
cleanup)
  P=(aws "${A[@]}" --profile "$PROFILE")
  "${P[@]}" s3api list-object-versions --bucket $B --query '[Versions,DeleteMarkers][][].[Key,VersionId]' --output text |
    while read -r k v; do [ -n "$k" ] && [ "$k" != None ] && "${P[@]}" s3api delete-object --bucket $B --key "$k" --version-id "$v" >/dev/null; done
  "${P[@]}" s3api delete-bucket-policy --bucket $B
  "${P[@]}" s3api delete-bucket --bucket $B
  aws iam delete-role-policy --profile "$PROFILE" --role-name $ROLE --policy-name s3-all-on-test-bucket
  aws iam delete-role --profile "$PROFILE" --role-name $ROLE
  echo "cleanup 完了"
  ;;
*) echo "使い方: bash $0 setup|denied|exempt|cleanup"; exit 1;;
esac
