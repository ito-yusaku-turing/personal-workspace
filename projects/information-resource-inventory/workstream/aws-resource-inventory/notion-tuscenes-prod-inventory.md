# tuscenes-prod の AWS リソースの棚卸し（2026-10）

作成: 2026-10-28 ／ 伊藤

<!-- Notion: https://app.notion.com/p/407a93b3e6f281ebb9e1f041231cce43 （MLOps 1チーム / ドキュメント置き場。このファイルが原本） -->

AWS アカウント tuscenes-prod（767397804933）にあるリソースを総ざらいし、**使われていないもの**と、**変更するときに思わぬ事故を起こしかねないもの**を洗い出しました。片付けの候補を共有し、持ち主の確認と片付けの順番を相談するための資料です。

**要点**

- **安全上、先に手を打ちたいものがあります（2 章）。** インターネットに公開されたまま放置された LDAP サーバー、認証なしで公開された Lambda の URL、全リポジトリから引き受けられる GitHub Actions のロールなどです。
- **消すと全体が止まるものがあります。** スタック `github-oidc-provider` を消すと、全リポジトリの GitHub Actions が AWS に入れなくなります。ほかの片付けで巻き添えにしないよう注意してください。
- **費用の大きいもの**: ECR が 22.5 TB（月 $2,200 前後）、保持期間が無期限のログが 9 TB です。Coder の旧版は月 $400 かかっていますが、人には使われていません。Coder の新版の EKS は延長サポート料金で月 $1,296 かかっています。
- **片付けの候補のほとんどは cdk-apps で管理されていません。** コードを消しても片付かないので、手で消すことになります（6 章）。

## 1. 調べ方

- 対象: tuscenes-prod。us-west-2 と ap-northeast-1 を詳しく見ました。CloudFront・IAM・Route 53 などのグローバルなサービスも含みます。ほかのリージョンは、使った形跡があるかだけを見ました。
- 「使われていない」の基準: 90 日（IAM は 180 日）。CloudTrail・CloudWatch のメトリクス・IAM の最終アクセスで判定しました。
- 持ち主: CloudFormation のスタックと、cdk-apps・mono-e2e・GitHub のリポジトリを突き合わせました。
- 調査は読み取りの権限だけで行い、何も変更していません。費用は $1 未満です。
- 秘密の値（トークンなど）は記録していません。

## 2. 安全上、先に手を打ちたいもの

| 対象 | 何が危ないか | 最終利用 | 案 |
|---|---|---|---|
| スタック `LDAP`（OpenLDAP、インターネット向けの NLB） | ディレクトリのサーバーがインターネットに公開されたまま。90 日分のログでは、来ているのはスキャナーだけ（匿名の照会と、パスワード違いの認証の試行）。認証に成功したものは無い。コードの [turingmotors/ldap](https://github.com/turingmotors/ldap) はアーカイブ済み。今の LDAP（turing-infra-ldap）とは別物 | 2025-01（スタックの最終更新） | スタックごと消す。ECR `ldap` とロググループも |
| Lambda `alphard_route_gen` | Slack のトークンを環境変数に平文で持つ。**認証なしの Function URL がインターネットに公開されている** | 2024-08（最終更新）。90 日の呼び出しは 0 回 | Slack 側でトークンを失効させてから、関数とロールを消す |
| Lambda `vm-alarm-dev-periodic_task` | 毎日 GCP から 403 で失敗していて、何もしていない。Slack のワークフローを起動する URL がコードに平文で書かれている。[turingmotors/vm-alarm](https://github.com/turingmotors/vm-alarm) はアーカイブ済み | 毎日（失敗） | 関数・ルール・ロールを消し、Slack のワークフローの URL を無効にする |
| ロール `github-actions-file-publishing-role-…`・`github-actions-image-publishing-role-…` | turingmotors の**全リポジトリ**から引き受けられる | 2024-04・2024-07 | スタックごと消す（`github-oidc-provider` は残す。3 章） |
| ロール `tuscenes-cicd-GithubActionsRole…` | 多くのブランチと PR から引き受けられ、PassRole・ECR への push を持つ。最後に使った CI のリポジトリ（tuscenes-processor）はアーカイブ済み | 2026-03 | スタックごと消す |
| ロール `CodeCatalystWorkflowDevelopmentRole-tuscenes-prod` | AdministratorAccess | 2024-03 | 消す |
| 強い権限を持つ未使用の IAM ユーザー・ロール | S3 やシークレットの広い権限を持つ IAM ユーザー 4 人（キーは無効）、S3FullAccess・SecretsManagerReadWrite を持つロール 4 本、外部の会社（Miro・TileDB・New Relic）を信頼するロール 3 本、元のロールが消えた Flyte のロール | 2024〜2026-05 | 消す（外部連携をやめていれば） |
| セキュリティグループ 5 個（`launch-wizard-*`・`ssh-public` など） | SSH を全世界に開放。どこにも付いていない | — | 消す |

そのほか、片付けではなく設定の見直しの候補:

- GitHub Actions のロールの多くが、`pull_request` や全ブランチからも引き受けられます（deploy を行うロールを含む）。
- EKS のクラスター 5 本は、API のエンドポイントを全世界に公開しています。
- us-west-2 の EBS 149 本のうち 127 本が暗号化されていません。

## 3. 変更するときにぶつかりかねないもの

片付けや CDK の変更のときに、思わぬところが止まりうるものです。

| 対象 | 何が起きるか |
|---|---|
| **スタック `github-oidc-provider`** | GitHub の OIDC プロバイダーを持ち、**44 本のロールがこれに頼っている**。消すと全リポジトリの GitHub Actions が AWS に入れなくなる。cdk-apps は ARN で参照しているだけで、管理していない。削除の保護を付けるか、cdk-apps に取り込むのが望ましい |
| `tuscenes-tmp` の S3 通知 | `2.1/` の下に `.json`・`.csv` を置くと、cleaning の job（SageMaker）が起動する仕掛けが残っている。どのスタックも持っていない。今はそのプレフィックスが無いので眠っている |
| Databricks の通知（SNS）が付いたバケット 15 本 | CDK でこれらのバケットに通知を足すとき、`Managed: true` になる書き方をすると、Databricks の取り込みの通知が消えて取り込みが止まる |
| スタック `databricks-s3-ingest-*`（31 本） | Databricks の画面が作ったもの。消すときに、スタックに保存された Databricks のトークンで API を呼ぶので、トークンが失効していると削除に失敗する。Databricks 側の外部ロケーションを先に片付ける |
| CloudFront `E1K5TKF3VZ5EWE`（turing-video-frames） | 手で作った配信で、どのスタックにも無い。バケットは cdk-apps の `VideoFrameExtractorOutputStack` が持つので、バケット側の変更で壊れうる |
| コードの無いスタック（`sfn-auto-labeling`・`DatabricksAutoLoader`・`SharedBackend`・`YoutubeCollectorStack` など） | 誰も deploy しないので、手で変えられても気づかない |

## 4. 費用の大きいもの

| 対象 | 規模 | 案 |
|---|---|---|
| ECR（us-west-2） | 22.5 TB、月 $2,200 前後。push から 180 日を超えたイメージが 10.5 TB（大きいのは `closed-loop-scenario-test`・`3dgs-train`・`openpilot-replay`）。最終 push が 180 日を超えたリポジトリが 17 本 | ライフサイクルポリシーを入れる。古いリポジトリは消す |
| CloudWatch Logs（us-west-2） | 保持期間が無期限のロググループ 368 個・9.0 TB（最大は `/aws/batch/job` の 8.1 TB） | 保持期間を決める |
| **Coder の旧版**（us-west-2 のスタック `Coder`） | 月 $400 前後。直近 30 日のサーバーログに、ログインやワークスペースの操作は無く、来ているのはスキャナーだけ。`coder.turing-ai.dev` がまだ旧版を指している。EFS 28.8 TB（ほぼ Archive）が残る | DNS を外し、スタックを消す。EFS の中身は確認してから決める |
| Coder の新版の EKS 3 本 | バージョン 1.32 のままで、延長サポートの料金が月 $1,296 | 標準サポートのバージョンに上げれば月 $219 |
| Coder の新版の停止中のワークスペース | 14 台・EBS 7.9 TB（月 $630 前後）。90 日を超えて止まっているものが 10 台 | Coder の側で消す |
| NAT Gateway | 止められるものが 4 本・月 $130 前後: `ml-ops-vpc`（何もいない）、Coder の旧版、Databricks のワークスペース `workshop`・`secondee`（どちらも Terraform の管理外で、使われていない） | VPC・ワークスペースと一緒に片付ける |

Coder は 2 つの版があります。**片付けの対象は旧版（us-west-2）だけ**で、新版（ap-northeast-1、`coder-v2.turing-ai.dev`）は使われています。同じ名前のスタック `Coder` が両方のリージョンにあるので、取り違えに注意してください。

## 5. 使われていないもの（そのほか）

| 種別 | 件数 | 備考 |
|---|---|---|
| IAM ロール | 180 日以上未使用 229 本（スタック外 78 本） | スタック内のものはスタックごと片付ける |
| IAM ユーザー | 37 人中、有効なキーが無いもの 19 人。コンソールのログインは 0 人 | 消しても止まるものは無い |
| CloudFormation | 作成に失敗した殻 3 本。使われていない `databricks-s3-ingest-*` 4 本（mono-e2e のコードからも参照なし） | Databricks 側を先に片付ける |
| Secrets Manager | 90 日以上読まれていないもの 20 個前後 | 消す前に、発行元で鍵を失効させる |
| KMS | us-west-2 の `alias/turing/ssm`・`alias/ssm` は 90 日間使われていない | まず無効化して様子を見る |
| セキュリティグループ | どこからも参照されていないもの 18 個 | |
| EIP・EBS・RDS のスナップショット | EIP 2 個（Flyte・auto-labeling の残り）、未アタッチの EBS 3 本、元の DB が無いスナップショット | |
| DynamoDB・Cognito・Batch | 持ち主のいないテーブル 5 本、ユーザープール 3 個、auto-labeling の一式（2024 年） | Cognito は利用者の情報を持ちうる |
| Step Functions | 一度も実行されていないもの 2 本（cdk-apps の DensoNx・closed-loop-scenario-test） | 持ち主に確認 |

ほかのリージョン: us-east-1 は月 $47 前後（S3・Secrets Manager・KMS）、us-east-2 は月 $8 前後、ジャカルタはネットワークだけが残っています。大阪は使われていません。

## 6. cdk-apps で管理されているか

2026-10-28 の cdk-apps（`c081e538`）と、その履歴で確かめました。

| 区分 | スタック・リソース |
|---|---|
| 管理している（今もコードにある） | Coder の新版（ap-northeast-1 の `Coder`・`CoderWorkspace-*`）・`Datalake`・`VideoFrameExtractorStack`・`VideoFrameExtractorOutputStack`・`SkypilotApiServer`・`ModelConverter`・`QinertiaRunner`・`ClusterToolkit`・`ClosedLoopScenarioTestEks`・`TuringDataExplorerStack`・`GamingDataCollectionStack`・`Databricks`・`AzureDatabricks`・`DensoNx`、GitHub Actions のロールの多く |
| かつてあり、今はコードから外れた（AWS に残る） | **Coder の旧版**（2025-02 にコードが東京向けに書き換えられた）・`YoutubeCollectorStack`・RlogVisualizer のロール・Flyte の残り |
| 一度も無い | `LDAP`・`tuscenes`・`tuscenes-cicd`・**`github-oidc-provider`**・`github-actions-file-publishing`・`github-actions-image-publishing`・`sfn-auto-labeling`・`DatabricksAutoLoader`・`SharedBackend`・`NewRelic-AWS-Integration`・`databricks-s3-ingest-*`・`databricks-workspace-*`（Databricks の画面が作成）・`vm-alarm`（Chalice）・手で作った Lambda や IAM ユーザー |

## 7. 確定できていないこと

- Coder の旧版の EFS 28.8 TB の中身（確かめるには、マウントしてファイルの一覧を取る必要があります）。
- 中身が変わらない S3 バケット（`miwa-gmo-2026-0424-archive` 24.3 TB など）が読まれているか。アクセスの記録を取っていないため分かりません。
- 90 日より前に誰が作った・変えたか。

## 8. 相談したいこと

- **片付けの順番**: 2 章（安全上のもの）を先に、次に Coder の旧版と NAT Gateway、その後に ECR・ログの保持期間、の順を考えています。
- **持ち主の確認**: 持ち主の分からないもの（Databricks のワークスペース `secondee`、`SharedBackend`、外部の会社を信頼するロールなど）に心当たりがあれば教えてください。
- **今後の防止**: 手で作ったリソースやコードから外れたスタックが、こうして残り続けます。新しいリソースは cdk-apps などのコードで作る、という方針を確認したいです。
