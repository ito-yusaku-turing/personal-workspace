# AWS リソースの棚卸し

- 開始: 2026-10-28
- 状態: **優先度 A〜C の調査と、Coder・NAT Gateway の掘り下げを終え、[掃除の候補のリスト](aws-resource-inventory/cleanup-candidates.md)を作った**（2026-10-28）。次は伊藤がリストを見て、片付けるもの・持ち主に確かめるものを決める。片付けの手順書はまだ
- 所属: project:information-resource-inventory

AWS アカウント tuscenes-prod（767397804933）のリソースを総ざらいし、掃除の候補のリストを作る。

## 背景・目的

- 使われていないリソースを特定し、掃除の候補にする。
- 今回は費用よりもセキュリティを重く見る。使われていない主体・権限・仕組みが残っていること自体をリスクとみなす。
- もう一つの軸として、**変更を加えようとしたときに競合しかねないもの**を見つける。手本は、原本バケットの守りの第二弾で見つかった次の 2 件（[s3-data-protection-2.md](../../aws-data-protection/workstream/s3-data-protection-2.md) の TODO 23・25、2026-10-27）。
  - **眠っている仕掛け**: スタック `tuscenes` の EventBridge のルール `tuscenes-NewTripEventRule…` は ENABLED のまま、tuscenes-raw の EventBridge が無効なので発火していなかった。監査のために EventBridge を有効にすると、cleaning の job・Supabase の書き換え・Slack への投稿が動き出すところだった。2026-10-27 に伊藤がルールを止めた。
  - **丸ごと上書きする持ち主**: td1-raw の通知は、datalake の CDK が `Managed: true` で丸ごと持っている。ほかの経路で足した通知は、datalake の deploy で消えるおそれがある。

## 設計判断と理由

- **対象**: tuscenes-prod だけ。認証は SSO の ReadOnly（`--profile readonly`）。
- **リージョン**: 深掘りするのは us-west-2 と ap-northeast-1 だけ（2026-10-28 伊藤が決定）。ほかの米国のリージョン・大阪・ほかの国は、使った形跡があれば報告するだけ。IAM などのグローバルなサービスは `global` として扱う。
- **「使われていない」の閾値**: 既定は 90 日。IAM の最終利用は 180 日で区切る（2026-10-28 伊藤が承認）。
- **グローバルなサービス（IAM・CloudFront・Route 53・ACM など）も深掘りの対象で、掃除の対象**（2026-10-28 伊藤が決定）。
- **IAM のレポートの生成**: `generate-credential-report`・`generate-service-last-accessed-details` を呼んでよい（2026-10-28 伊藤が許可）。AWS 側にレポートの作成ジョブができるだけで、リソースは変わらない。
- **掃除の候補のリストは、まず伊藤の判断用**（2026-10-28 決定）。チーム向けの書き方にはしない。
- **Coder は 2 つの版があり、片付けの対象は旧版（us-west-2 のスタック `Coder`）だけ**。新版（ap-northeast-1 のスタック `Coder` と `CoderWorkspace` 3 本）は今も使われている（2026-10-28 伊藤。最初に「全面停止」と聞いたのを訂正）。新版の利用の実態が AWS から分からないこと（ALB のアクセスログが無効）への手当ては、別に検討する（伊藤）。
- **費用**: 調査で $100 未満なら進めてよい（2026-10-28 伊藤）。見積もりは $5 未満（Cost Explorer 1 回 $0.01、GetMetricData 1,000 メトリクスあたり $0.01）。
- **優先度**: セキュリティを重視する（2026-10-28 伊藤が決定）。
  - B（上位）: IAM ユーザー・アクセスキー・ロール、CloudFormation スタック、Lambda、EventBridge のルール、SNS・SQS、Secrets Manager、KMS、セキュリティグループ
  - A: EC2・EBS・スナップショット・AMI・EIP・NAT Gateway・ELB・RDS・SageMaker・EKS/ECS・OpenSearch・ElastiCache・S3（バケット単位）・ECR・CloudWatch Logs
  - C: VPC・VPC エンドポイント・Route 53・ACM・Glue・Step Functions
- **一次情報と分析の置き場を分ける**（2026-10-28 伊藤が決定）。
  - 一次情報: `~/aws/tuscenes-prod/<取得日>/<リージョン>/<サービス>/<操作>.json`。API の応答を 1 回 1 ファイルで保存し、書き換えない。git では管理しない。
  - 分析の結果と決めたこと: この project の資料にする。
- **機微な情報は伏せる**（2026-10-28 伊藤が決定）。保存する前に、キー名は残して値を `<REDACTED>` にする（[collect/redact.py](aws-resource-inventory/collect/redact.py)）。元の値は手元にも残さない。Secrets Manager・SSM パラメータは値を取らない。EC2 の UserData は取らない。アクセスキーの ID は末尾 4 文字だけ残す（突き合わせのため。2026-10-28）。
- **競合しかねないものの型**（案。2026-10-28）: (1) 眠っている仕掛け（ENABLED なのに出どころが止まっているルールなど）、(2) 丸ごと上書きする持ち主（`Managed: true` の通知など）、(3) 二重の持ち主・持ち主の不在（アーカイブ済みのリポジトリのスタック、`from_bucket_name` だけの参照、手で作ったもの、drift）、(4) 宛先の消えた配線（消えたターゲットを指すルール・通知・購読）。
- **レート制限**: `AWS_RETRY_MODE=adaptive`・`AWS_MAX_ATTEMPTS=10`。同じサービスへの呼び出しは並列にしない。CloudTrail の `lookup-events` は全体には使わない。

## 進捗チェックリスト

- [x] 進め方の議論（対象・優先度・置き場・機微な情報・閾値・リージョン）
- [x] 一次情報を取る道具（[collect/](aws-resource-inventory/collect/README.md)）
- [x] 段階 0: リージョンごとの費用と形跡、種別ごとの件数（[stage0-overview.md](aws-resource-inventory/stage0-overview.md)）
- [x] 段階 1・2（優先度 B とグローバルなサービス）: IAM・CloudFormation・EventBridge・S3 の通知・Lambda・Secrets Manager・KMS・セキュリティグループ・SQS・CloudFront・Route 53・ACM → [cleanup-candidates.md](aws-resource-inventory/cleanup-candidates.md)
- [ ] 伊藤がリストを見て、片付けるもの・持ち主に確かめるものを決める
- [x] 段階 1・2（優先度 A）: EC2・EBS・スナップショット・AMI・EIP・NAT Gateway・ELB・RDS・SageMaker・EKS・ECS・ECR・CloudWatch Logs・S3 の使用状況（[collect/stage1-a.sh](aws-resource-inventory/collect/stage1-a.sh)）
- [x] `tuscenes-cicd` のロールの 2026-03-27 の利用者 → tuscenes-processor の CI（IAM のサービスの最終アクセスと GitHub の実行履歴で特定）
- [x] tuscenes-stack-cleanup に tuscenes-tmp の通知の件を追記（2026-10-28 伊藤が許可）
- [x] 段階 1・2（優先度 C）: Route 53・Step Functions・DynamoDB・Cognito・Batch・EFS・VPC エンドポイント・アラーム・Scheduler・SSM など（[collect/stage1-c.sh](aws-resource-inventory/collect/stage1-c.sh)）
- [x] Coder の掘り下げ（旧版の状態・費用・洗い出し・削除の注意と順番、新版について気づいたこと）→ リストの 5 章
- [x] NAT Gateway の掘り下げ（経路・接続数・Databricks のワークスペースとの対応）→ リストの 6 章
- [ ] 伊藤の判断を受けて、片付けの手順書を書く（Coder の旧版から）
- [ ] （別に検討）Coder の新版の利用の実態を把握する手当て
- [ ] KMS のキーの利用（管理イベントはログ用のアカウントにあり、このアカウントからは 90 日より前を見られない）
- [ ] ECR のイメージを毎日 pull している主体

## 次セッションへの引き継ぎ

- 一次情報は `~/aws/tuscenes-prod/2026-10-28/` にある。取るときは [collect/cap.sh](aws-resource-inventory/collect/cap.sh) を使う（伏せ字とログを自動で行う）。
- 段階 0 で分かったこと: AWS Config が両リージョンで記録中（us-west-2 は EC2 のインスタンス・ボリューム・ENI を記録から外している）。IAM はロール 694・ユーザー 37。us-west-2 は Lambda 215・スタック 126・シークレット 72・ルール 56。
- 報告だけのリージョン: us-east-1（Databricks・S3・CloudFront など。今も月 $47 前後）、us-east-2（S3 は 2026-02 まで。今も月 $7.81 程度）、ジャカルタ（EC2 は 2026-01 まで。ネットワークが残る）。大阪は形跡なし。
- 段階 1（優先度 B）の取得は API 約 900 回、費用は $1 未満。取得のスクリプトは [collect/](aws-resource-inventory/collect/README.md)、集計は [analyze/](aws-resource-inventory/analyze/README.md)。集計の表は `~/aws/tuscenes-prod/2026-10-28/derived/`。
- 注意: Config の件数は削除済みの記録を含むことがある（IAM ロールは Config・実数とも 694 本で一致、EC2Fleet は 65,073 件と過大）。数は直接の API で数える。
- 主な発見（詳細はリスト）:
  - スタック `github-oidc-provider`（コードなし）が、44 本のロールが頼る GitHub の OIDC プロバイダーを持つ。隣の使われていないスタックと一緒に消すと全 CI が止まる。
  - `tuscenes-tmp` の `2.1/` への `.json`・`.csv` の作成で、`tuscenes-CleaningJob-Function` が今も起動する（通知はどのスタックも持たない）。tuscenes-stack-cleanup に書き足す必要がある。
  - turingmotors の全リポジトリから引き受けられるロールが 2 本（2024 年から未使用）、AdministratorAccess の未使用ロールが 1 本、Slack のトークンを平文で持つ未使用の Lambda が 1 本。
  - 持ち主のいないまま毎日動く Lambda `vm-alarm-dev-periodic_task`。
  - 優先度 A: 使われていない NAT Gateway 4 本、割り当ての無い EIP 2 個、元の DB の無い RDS のスナップショット、ECR 22.5 TB（半分は 180 日より前の push）、保持期間が無期限のログ 9 TB。Coder の旧版（us-west-2）。
- Coder: 同じ名前のスタック `Coder` が us-west-2（旧版）と ap-northeast-1（新版）にある。集計の `derived/iam-owner.json` はスタック名だけでリージョンを区別しないので、取り違えに注意する（一度取り違えた）。旧版は月 $400 前後で、EFS 3 本が `Retain`（28.8 TB が残る）、実体の無いリソース 2 つ（EKS `Coder-AutoCluster`・Aurora `coder-slurmdb*`）がスタックに載っている。シークレット `coder/oidc/*` は 2026-10-27 に読まれていて、新版が使うとみられる（消さない）。新版は EKS 3 本が 1.32 の延長サポートで計 $1,296/月。`CoderWorkspace` の共有 EFS は `DeletionPolicy: Delete`。
- Cost Explorer はスタックのタグ（`aws:cloudformation:stack-name`）で費用を分けられる（コスト配分タグが有効）。`global/ce/cost-by-stack-2026-09.json`。
- CloudTrail: 管理イベントは Control Tower のトレイルで、ログ用のアカウント（617808723336）のバケットに送られている。このアカウントでは、イベント履歴の直近 90 日しか見られない。90 日より前の利用者は、IAM のサービスの最終アクセス（`generate-service-last-accessed-details`）と、GitHub の実行履歴で絞り込んだ。
- ECR の最終 pull は、何かが毎日全イメージを pull しているため、使われているかの根拠にならない。push の日付を使う。
- スタック `tuscenes` は [tuscenes-stack-cleanup.md](../../aws-data-protection/workstream/tuscenes-stack-cleanup.md) で調べ済み。結果を再利用し、二重に調べない。

## 関連リンク

- [s3-data-protection-2.md](../../aws-data-protection/workstream/s3-data-protection-2.md): 競合の手本（TODO 23・25）
- [tuscenes-stack-cleanup.md](../../aws-data-protection/workstream/tuscenes-stack-cleanup.md): スタック tuscenes の中身
- `/usr/app/cdk-apps`: 持ち主（IaC）を突き合わせる先
