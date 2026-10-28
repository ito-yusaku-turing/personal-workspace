#!/usr/bin/env bash
# 段階 1: S3 のバケット一覧・各バケットのリージョン・通知の設定を取る。バケットはグローバルな名前なので global に置く。
set -uo pipefail
C=$(dirname "$0")/cap.sh
base=${AWS_INV_DIR:-$HOME/aws/tuscenes-prod}/${AWS_INV_DATE:-$(date -u +%F)}
"$C" global s3 list-buckets s3api list-buckets
jq -r '.Buckets[].Name' "$base/global/s3/list-buckets.json" | while read -r b; do
  "$C" global s3/location "$b" s3api get-bucket-location --bucket "$b"
  "$C" global s3/notification "$b" s3api get-bucket-notification-configuration --bucket "$b"
  sleep 0.1
done
