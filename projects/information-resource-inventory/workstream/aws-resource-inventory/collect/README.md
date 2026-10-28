# 一次情報を取る道具

AWS の読み取りの API を呼び、応答を伏せ字にして `~/aws/tuscenes-prod/<取得日>/` に保存する。

- `cap.sh <region|global> <service> <name> <aws の引数...>`: 1 回呼んで `<region>/<service>/<name>.json` に保存する。既にあれば呼ばない（一次情報は書き換えない）。失敗したら `.err` を残す。呼び出しはすべて `_log.tsv` に記録する。`global` は us-east-1 で呼ぶ。
- `redact.py`: 機微な値を伏せる。キー名（環境変数・ジョブの引数・UserData・パスワードなど）は残し、値を `<REDACTED>` にする。値の形（アクセスキーの ID（末尾 4 文字だけ残す）・Slack のトークン・JWT・秘密鍵・接続文字列の資格情報など）でも伏せる。

環境変数: `AWS_INV_PROFILE`（既定 `readonly`）、`AWS_INV_DIR`（既定 `~/aws/tuscenes-prod`）、`AWS_INV_DATE`（既定 今日の UTC の日付）。レート制限に備えて `AWS_RETRY_MODE=adaptive`・`AWS_MAX_ATTEMPTS=10` で呼ぶ。

段階 1 の取得のスクリプト（中で `cap.sh` を呼ぶ。取得済みのものは飛ばすので、途中から再実行できる）:

- `stage1-cfn.sh <region>...`: スタック・リソース・テンプレート
- `stage1-events-s3-lambda.sh <region>...`: EventBridge・Lambda・呼び出し回数（90 日）
- `stage1-s3.sh`: バケット一覧・リージョン・通知（global に置く）
- `stage1-a.sh <region>...`: 優先度 A（EC2・EBS・スナップショット・AMI・EIP・NAT・ELB と ターゲットの状態・RDS・SageMaker・EKS・ECS・CloudWatch Logs・ECR のイメージ）と VPC
- `stage1-misc.sh <region>...`: Secrets Manager（メタデータだけ）・KMS・セキュリティグループ・ENI・EC2・ACM・SQS の送信数、CloudFront・Route 53

IAM は `cap.sh` を直接呼んだ（`get-account-authorization-details`・`generate-credential-report`・`get-credential-report` など）。クレデンシャルレポートの CSV は `jq -r .Content | base64 -d` で取り出す。

利用状況のメトリクス（ALB・NLB・Aurora・NAT・S3 の容量。直近 90 日の日次）は、`cap.sh <region> cloudwatch usage-90d cloudwatch get-metric-data --metric-data-queries file://…` で一括して取った（`<region>/cloudwatch/usage-90d.json`）。CloudFront のリクエスト数は `global/cloudwatch/cloudfront-requests-90d.json`。
