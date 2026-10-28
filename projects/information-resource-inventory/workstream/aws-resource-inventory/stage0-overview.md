# 段階 0: リージョンと種別の概観（2026-10-28）

tuscenes-prod（767397804933）の、どのリージョンに何があるかの概観。一次情報は `~/aws/tuscenes-prod/2026-10-28/`（`global/ce/`・`global/ec2/`・`*/config/`・`*/tagging/`）。

## 調べ方

- 費用: Cost Explorer のリージョン別・サービス別の月次（2025-10-01〜2026-10-27）。
- 種別の件数: AWS Config の高度なクエリ（us-west-2・ap-northeast-1）。Control Tower が入れたレコーダーが、両リージョンで 2024-02-01 から記録している（日次）。
  - ap-northeast-1 は全種別とグローバルな種別（IAM）を記録する。
  - us-west-2 は EC2 のインスタンス・ボリューム・ENI と SSM の 2 種を記録から外している。段階 1 では、これらを直接の API で取る。
  - 件数は Config の記録であり、正確な数は段階 1 の直接の API で確かめる（たとえば EC2Fleet の 65,073 件は、終わった Batch・Spot のフリートの記録とみられる）。
- ほかのリージョンの形跡: タグ付け API（`get-resources`）。タグを付けたことがあるリソースしか出ないので、費用と合わせて見る。
- Resource Explorer はリージョンごとのローカルの索引（5 リージョン）だけで、集約の索引もビューも無い。今回は使わない。

## リージョンごとの形跡

| リージョン | 12 か月の費用 | 形跡 | 扱い |
| --- | --- | --- | --- |
| us-west-2 | 約 $2,556,000 | 主（下の件数） | 深掘りする |
| ap-northeast-1 | 約 $117,000 | あり（下の件数） | 深掘りする |
| us-east-1 | 約 $29,900 | Databricks（$18,952、2025-12 が最後）、S3（$10,039、今も月 $40 前後）、Secrets Manager・KMS（今も）、EC2（2026-05 が最後）。タグ付きでは CloudFormation スタック 2・CloudFront ディストリビューション 5・関数 2・EFS 1・IAM の OIDC プロバイダー 2・CDK のアセットのバケット・`datadog-account-level-cost-report` のバケットなど | 報告だけ（CloudFront・ACM・IAM などグローバルなサービスの置き場でもある） |
| us-east-2 | 約 $7,060 | S3（$6,841、2026-02 が最後）、Secrets Manager・KMS（今も月 $7.81 程度）。タグ付きではスタック 1・EFS 1・Chatbot・CDK のアセットのバケットなど | 報告だけ |
| ap-southeast-3（ジャカルタ） | 約 $1,860 | EC2（2025-11〜2026-01 だけ月 $500〜750）。オプトイン済み。VPC 1・サブネット 6 などのネットワークが残る | 報告だけ |
| us-west-1・eu-west-1・ca-central-1 | 各 $1 未満 | eu-west-1 に Chatbot の設定 1 | 報告だけ |
| ap-southeast-1 | $0 | Chatbot の設定 1 | 報告だけ |
| ap-northeast-3（大阪） | $0 | タグ付きのリソースなし | 使われていない |
| そのほか（オプトイン不要の国） | $0 | タグ付きのリソースなし | 使われていない |

ほかに、`NoRegion` が約 $288,500、`global` が約 $205,000 ある（サポート・Marketplace・データ転送など）。

## 種別ごとの件数（Config、2026-10-28）

IAM（グローバル）: ロール 694・ポリシー（カスタマー管理）55・ユーザー 37。

| 種別 | us-west-2 | ap-northeast-1 |
| --- | ---: | ---: |
| Lambda::Function | 215 | 9 |
| S3::Bucket | 145 | 7 |
| CloudFormation::Stack | 126 | 15 |
| EC2::SecurityGroup | 100 | 11 |
| SQS::Queue | 99 | 0 |
| SecretsManager::Secret | 72 | 6 |
| Events::Rule | 56 | 3 |
| ECR::Repository | 51 | 5 |
| ECS::Cluster | 39 | 1 |
| AutoScaling::AutoScalingGroup | 32 | 1 |
| SNS::Topic | 30 | 2 |
| EC2::VPC | 30 | 3 |
| Batch::JobQueue / ComputeEnvironment | 30 / 28 | 0 |
| StepFunctions::StateMachine | 26 | 0 |
| EC2::VPCEndpoint | 20 | 2 |
| KMS::Key | 16 | 9 |
| RDS::DBClusterSnapshot | 16 | 7 |
| DynamoDB::Table | 15 | 0 |
| EC2::EIP | 12 | 4 |
| EC2::NatGateway | 8 | 1 |
| ACM::Certificate | 8 | 1 |
| EKS::Cluster | 3 | 2 |
| RDS::DBCluster / DBInstance | 2 / 3 | 1 / 1 |
| EC2::Instance | （記録外） | 11 |
