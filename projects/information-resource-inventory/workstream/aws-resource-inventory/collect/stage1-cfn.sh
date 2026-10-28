#!/usr/bin/env bash
# 段階 1: CloudFormation のスタック・リソース・テンプレートを取る。
#   stage1-cfn.sh <region>...
set -uo pipefail
C=$(dirname "$0")/cap.sh
base=${AWS_INV_DIR:-$HOME/aws/tuscenes-prod}/${AWS_INV_DATE:-$(date -u +%F)}
for r in "$@"; do
  "$C" "$r" cloudformation describe-stacks cloudformation describe-stacks
  "$C" "$r" cloudformation list-stacks-deleted cloudformation list-stacks --stack-status-filter DELETE_COMPLETE
  for s in $(jq -r '.Stacks[].StackName' "$base/$r/cloudformation/describe-stacks.json"); do
    "$C" "$r" cloudformation/resources "$s" cloudformation list-stack-resources --stack-name "$s"
    "$C" "$r" cloudformation/templates "$s" cloudformation get-template --stack-name "$s" --template-stage Original
    sleep 0.2
  done
done
