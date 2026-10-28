#!/usr/bin/env bash
# 段階 1: Secrets Manager・KMS・セキュリティグループ・ENI・SQS の利用状況と、グローバルなサービス（CloudFront・Route 53・ACM）を取る。
#   stage1-misc.sh <region>...
set -uo pipefail
C=$(dirname "$0")/cap.sh
base=${AWS_INV_DIR:-$HOME/aws/tuscenes-prod}/${AWS_INV_DATE:-$(date -u +%F)}
for r in "$@"; do
  "$C" "$r" secretsmanager list-secrets secretsmanager list-secrets          # 値は取らない（メタデータだけ）
  "$C" "$r" kms list-keys kms list-keys
  "$C" "$r" kms list-aliases kms list-aliases
  for k in $(jq -r '.Keys[].KeyId' "$base/$r/kms/list-keys.json"); do
    "$C" "$r" kms/describe-key "$k" kms describe-key --key-id "$k"
    sleep 0.1
  done
  "$C" "$r" ec2 describe-security-groups ec2 describe-security-groups
  "$C" "$r" ec2 describe-network-interfaces ec2 describe-network-interfaces
  "$C" "$r" ec2 describe-instances ec2 describe-instances --query 'Reservations[].Instances[].{InstanceId:InstanceId,State:State.Name,Type:InstanceType,LaunchTime:LaunchTime,Tags:Tags,IamInstanceProfile:IamInstanceProfile,SecurityGroups:SecurityGroups,VpcId:VpcId,ImageId:ImageId,KeyName:KeyName,MetadataOptions:MetadataOptions,PublicIpAddress:PublicIpAddress}'
  "$C" "$r" acm list-certificates acm list-certificates
  for a in $(jq -r '.CertificateSummaryList[].CertificateArn' "$base/$r/acm/list-certificates.json"); do
    "$C" "$r" acm/describe-certificate "${a##*/}" acm describe-certificate --certificate-arn "$a"
  done
  # SQS: 直近 90 日の送信数（日次の合計）
  python3 -I - "$base/$r/sqs/list-queues.json" "$base/$r/sqs" <<'PY'
import json, sys, os
p = sys.argv[1]
qs = [u.rsplit("/", 1)[1] for u in (json.load(open(p)).get("QueueUrls", []) if os.path.getsize(p) else [])]
q = [{"Id": f"q{i}", "Label": n, "MetricStat": {"Metric": {"Namespace": "AWS/SQS", "MetricName": "NumberOfMessagesSent",
      "Dimensions": [{"Name": "QueueName", "Value": n}]}, "Period": 86400, "Stat": "Sum"}} for i, n in enumerate(qs)]
json.dump(q, open(f"{sys.argv[2]}/.mdq.json", "w"))
PY
  if [ "$(jq length "$base/$r/sqs/.mdq.json")" -gt 0 ]; then
    "$C" "$r" cloudwatch sqs-sent-90d cloudwatch get-metric-data --metric-data-queries "file://$base/$r/sqs/.mdq.json" \
      --start-time "$(date -u -d '90 days ago' +%FT00:00:00Z)" --end-time "$(date -u +%FT00:00:00Z)"
  fi
  rm -f "$base/$r/sqs/.mdq.json"
done
"$C" global cloudfront list-distributions cloudfront list-distributions
"$C" global route53 list-hosted-zones route53 list-hosted-zones
"$C" global acm list-certificates.us-east-1 acm list-certificates --region us-east-1
