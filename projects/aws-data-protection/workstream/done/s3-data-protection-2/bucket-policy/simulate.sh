#!/bin/bash
# 2 文を足したポリシーで、主体ごとの許可・拒否をポリシーシミュレーターで確かめる（読み取りだけ）。
# 使い方: ./simulate.sh <バケット>   （rendered/<バケット>.json を使う）
B=$1; P="--profile readonly"
ACC=767397804933
declare -A PR=(
  [FullAccess]="arn:aws:iam::$ACC:role/aws-reserved/sso.amazonaws.com/us-west-2/AWSReservedSSO_FullAccess_ed608317ee39a850"
  [AWSAdministratorAccess]="arn:aws:iam::$ACC:role/aws-reserved/sso.amazonaws.com/us-west-2/AWSReservedSSO_AWSAdministratorAccess_619c2f8a913e315a"
  [cfn-exec-role]="arn:aws:iam::$ACC:role/cdk-hnb659fds-cfn-exec-role-$ACC-us-west-2"
  [tokyo30-upload-pc]="arn:aws:iam::$ACC:user/tokyo30-dataupload-pc-01"
  [databricks]="arn:aws:iam::$ACC:role/${DBX_ROLE:-databricks-s3-ingest-3090e-db_s3_iam}"
)
ACTS="s3:DeleteObject s3:PutObject s3:DeleteObjectVersion s3:DeleteBucket s3:PutBucketVersioning s3:PutLifecycleConfiguration s3:PutBucketPolicy"
printf "%-24s" ""; for a in $ACTS; do printf "%-14s" "${a#s3:}" | cut -c1-14 | tr -d '\n'; done; echo
for n in FullAccess AWSAdministratorAccess cfn-exec-role tokyo30-upload-pc databricks; do
  printf "%-24s" "$n"
  for a in $ACTS; do
    case $a in s3:DeleteObject|s3:PutObject|s3:DeleteObjectVersion) R="arn:aws:s3:::$B/x";; *) R="arn:aws:s3:::$B";; esac
    d=$(aws iam simulate-principal-policy $P --policy-source-arn "${PR[$n]}" --action-names $a \
      --resource-arns "$R" --resource-policy "file://rendered/$B.json" --resource-owner "arn:aws:iam::$ACC:root" \
      --context-entries "ContextKeyName=aws:PrincipalArn,ContextKeyValues=${PR[$n]},ContextKeyType=string" \
        "ContextKeyName=s3:ResourceAccount,ContextKeyValues=$ACC,ContextKeyType=string" \
        "ContextKeyName=aws:ResourceAccount,ContextKeyValues=$ACC,ContextKeyType=string" \
        "ContextKeyName=aws:PrincipalAccount,ContextKeyValues=$ACC,ContextKeyType=string" \
        "ContextKeyName=aws:SecureTransport,ContextKeyValues=true,ContextKeyType=boolean" \
      --query 'EvaluationResults[0].EvalDecision' --output text 2>&1 | tail -1)
    printf "%-14s" "$d"
  done; echo
done
