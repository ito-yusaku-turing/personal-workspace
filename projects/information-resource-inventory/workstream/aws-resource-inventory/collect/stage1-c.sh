#!/usr/bin/env bash
# 段階 1（優先度 C）: Glue・Step Functions の最終実行・DynamoDB・Firehose・API Gateway・Batch・CodeBuild・Cognito・EFS・
# DataSync・CloudWatch のアラーム・Scheduler・SSM パラメータ（メタデータだけ）・Amplify・Backup・インスタンスプロファイル、Route 53 のレコード。
#   stage1-c.sh <region>...
set -uo pipefail
C=$(dirname "$0")/cap.sh
base=${AWS_INV_DIR:-$HOME/aws/tuscenes-prod}/${AWS_INV_DATE:-$(date -u +%F)}
for r in "$@"; do
  "$C" "$r" glue get-jobs glue get-jobs
  "$C" "$r" glue get-crawlers glue get-crawlers
  "$C" "$r" glue get-databases glue get-databases
  for sm in $(jq -r '.stateMachines[].stateMachineArn' "$base/$r/stepfunctions/list-state-machines.json"); do
    "$C" "$r" stepfunctions/last-execution "${sm##*:}" stepfunctions list-executions --state-machine-arn "$sm" --max-items 1
    sleep 0.1
  done
  "$C" "$r" dynamodb list-tables dynamodb list-tables
  for t in $(jq -r '.TableNames[]' "$base/$r/dynamodb/list-tables.json"); do
    "$C" "$r" dynamodb/table "$t" dynamodb describe-table --table-name "$t"
  done
  for s in $(jq -r '.DeliveryStreamNames[]' "$base/$r/kinesis-firehose/list-delivery-streams.json"); do
    "$C" "$r" kinesis-firehose/stream "$s" firehose describe-delivery-stream --delivery-stream-name "$s"
  done
  "$C" "$r" apigateway get-rest-apis apigateway get-rest-apis
  "$C" "$r" apigateway get-domain-names apigateway get-domain-names
  "$C" "$r" apigatewayv2 get-apis apigatewayv2 get-apis
  "$C" "$r" batch describe-compute-environments batch describe-compute-environments
  "$C" "$r" codebuild list-projects codebuild list-projects
  for p in $(jq -r '.projects[]' "$base/$r/codebuild/list-projects.json"); do
    "$C" "$r" codebuild/builds "$p" codebuild list-builds-for-project --project-name "$p" --max-items 1
  done
  "$C" "$r" cognito-idp list-user-pools cognito-idp list-user-pools --max-results 60
  "$C" "$r" efs describe-file-systems efs describe-file-systems
  "$C" "$r" datasync list-tasks datasync list-tasks
  "$C" "$r" cloudwatch describe-alarms cloudwatch describe-alarms
  "$C" "$r" scheduler/schedules list scheduler list-schedules
  for g in $(jq -r '.Schedules[]|"\(.GroupName)/\(.Name)"' "$base/$r/scheduler/list-schedules.json"); do
    "$C" "$r" scheduler/schedules "${g//\//__}" scheduler get-schedule --group-name "${g%%/*}" --name "${g#*/}"
  done
  "$C" "$r" ssm describe-parameters ssm describe-parameters
  "$C" "$r" amplify list-apps amplify list-apps
  "$C" "$r" backup list-backup-plans backup list-backup-plans
  "$C" "$r" ec2 describe-vpc-peering-connections ec2 describe-vpc-peering-connections
  "$C" "$r" ec2 describe-transit-gateway-attachments ec2 describe-transit-gateway-attachments
done
"$C" global iam list-instance-profiles iam list-instance-profiles
for z in $(jq -r '.HostedZones[].Id|split("/")[-1]' "$base/global/route53/list-hosted-zones.json"); do
  "$C" global route53/records "$z" route53 list-resource-record-sets --hosted-zone-id "$z"
done
