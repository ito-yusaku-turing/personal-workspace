#!/usr/bin/env bash
# 段階 1: EventBridge（ルール・ターゲット・バス・スケジュール）、Lambda（関数・イベントソース・呼び出し回数）、S3（バケット・場所・通知）を取る。
#   stage1-events-s3-lambda.sh <region>...   （S3 のバケット一覧と通知は global として 1 回だけ取る）
set -uo pipefail
C=$(dirname "$0")/cap.sh
base=${AWS_INV_DIR:-$HOME/aws/tuscenes-prod}/${AWS_INV_DATE:-$(date -u +%F)}
for r in "$@"; do
  "$C" "$r" events list-event-buses events list-event-buses
  for bus in $(jq -r '.EventBuses[].Name' "$base/$r/events/list-event-buses.json"); do
    "$C" "$r" events "list-rules.$bus" events list-rules --event-bus-name "$bus"
    for rule in $(jq -r '.Rules[].Name' "$base/$r/events/list-rules.$bus.json"); do
      "$C" "$r" events/targets "$bus.$rule" events list-targets-by-rule --event-bus-name "$bus" --rule "$rule"
      sleep 0.1
    done
  done
  "$C" "$r" scheduler list-schedules scheduler list-schedules
  "$C" "$r" lambda list-functions lambda list-functions
  "$C" "$r" lambda list-event-source-mappings lambda list-event-source-mappings
  # 呼び出し回数（直近 90 日の日次の合計）。GetMetricData は 1 回 500 本まで
  python3 -I - "$base/$r/lambda/list-functions.json" "$base/$r/lambda" <<'PY'
import json, sys
fns = [f["FunctionName"] for f in json.load(open(sys.argv[1]))["Functions"]]
for i in range(0, len(fns), 400):
    q = [{"Id": f"f{i+j}", "Label": n, "MetricStat": {"Metric": {"Namespace": "AWS/Lambda", "MetricName": "Invocations",
          "Dimensions": [{"Name": "FunctionName", "Value": n}]}, "Period": 86400, "Stat": "Sum"}} for j, n in enumerate(fns[i:i+400])]
    json.dump(q, open(f"{sys.argv[2]}/.mdq{i//400}.json", "w"))
PY
  for q in "$base/$r/lambda"/.mdq*.json; do
    n=$(basename "$q" .json); n=${n#.mdq}
    "$C" "$r" cloudwatch "lambda-invocations-90d.$n" cloudwatch get-metric-data --metric-data-queries "file://$q" \
      --start-time "$(date -u -d '90 days ago' +%FT00:00:00Z)" --end-time "$(date -u +%FT00:00:00Z)"
    rm -f "$q"
  done
done
