# tuscenes-prod の掃除の候補（2026-10-28 時点）

AWS アカウント tuscenes-prod（767397804933）の棚卸しの結果。伊藤の判断用のリストで、チーム向けには書いていない。セキュリティの観点（優先度 B）・グローバルなサービス・優先度 A を見終えた時点のもの。優先度 C は VPC だけ見た（末尾の「まだ見ていないもの」）。

- 一次情報: `~/aws/tuscenes-prod/2026-10-28/`（機微な値は伏せ字）。集計の表は同じ場所の `derived/`。
- 集計のスクリプト: [analyze/](analyze/README.md)。取得の道具: [collect/](collect/README.md)。
- 基準: 「使われていない」は 90 日、IAM は 180 日。日付は UTC。
- 持ち主: CloudFormation のスタックのリソースと突き合わせた。「コードあり」は、マウント済みのリポジトリ（HEAD）にスタック名が引用符つきで現れること。手がかりであって確証ではない。

## 1. 先に手を打ちたいもの（安全上のリスクが高い）

広い権限や広い信頼条件を持ったまま、長く使われていない主体。

| # | 対象 | 何が危ないか | 最終利用 | 持ち主 | 案 |
| --- | --- | --- | --- | --- | --- |
| S1 | ロール `github-actions-file-publishing-role-11JuEiVbjOnX` | **turingmotors の全リポジトリ・全 ref**（`repo:turingmotors/*:ref:*`）から引き受けられる | 2024-04-09 | スタック `github-actions-file-publishing`（コードなし） | スタックごと消す。**`github-oidc-provider` のスタックは消さない**（下の C3-1） |
| S2 | ロール `github-actions-image-publishing-role-dpzyqzl6r1zt` | turingmotors の**全リポジトリの main** から引き受けられる | 2024-07-08 | スタック `github-actions-image-publishing`（コードなし） | 同上 |
| S3 | ロール `CodeCatalystWorkflowDevelopmentRole-tuscenes-prod` | **AdministratorAccess** | 2024-03-14 | なし（手で作った） | 消す。`AWSRoleForCodeCatalystSupport`（2024-03-13）も |
| S4 | Lambda `alphard_route_gen` | 環境変数に **Slack の OAuth トークンと署名の秘密を平文**で持つ | 呼び出し 90 日 0 回、最終更新 2024-08-22 | なし | Slack 側でトークンを失効させてから、関数とロール `alphard_route_gen-role-6jn8wddo` を消す |
| S5 | IAM ユーザー `jadd-datasync`・`jadd-remote-sync-kohei.watanabe` | **AmazonS3FullAccess・AmazonS3ExpressFullAccess**。キーは無効 | 2025-10-11・2025-10-20 | なし | 消す |
| S6 | IAM ユーザー `shio-secretsmanager_GetSecretValue`・`sasaki` | シークレットの読み取り＋S3（shio は FullAccess）。キーは無効 | 2025-08-07・2026-05-28 | なし | 消す |
| S7 | ロール `tuscenes-sampler-test-role-n1huu9jg`・`tuscenes-processing`・`AmazonEMRStudio_RuntimeRole`・`ecsTaskExecutionRole`・`CoderWorkspaceRole` | S3FullAccess や SecretsManagerReadWrite | 2024-07〜2025-10 | なし | 消す。`ecsTaskExecutionRole` は既定の名前なので、参照するタスク定義が無いことを確かめてから |
| S8 | 外部のアカウントを信頼するロール `MiroReadOnlyAccess-vui2`（Miro）・`tiledb-cloud-role`（TileDB）・`NewRelicInfrastructure-Integrations-02198610953f`（New Relic） | 社外の主体が引き受けられる | 2025-01-14・2024-05-22・未使用 | なし | 連携をやめていれば消す |
| S9 | ロール `Flyte-ClusterCreationRole360249B6-H9KZJoLii5eR` | 信頼ポリシーの主体が `AROA…` の ID のまま（**元のロールが消えている**）。IAM・PassRole を持つ | 2025-02-28 | なし（スタック `Flyte` は消えた） | Flyte の残りのロール 4 本と一緒に消す |
| S10 | ロール `tuscenes-cicd-GithubActionsRoleF5CC769F-TsH727j5snzo` | `alphaspp-*`・`tuscenes-*` の全ブランチと PR から引き受けられる。PassRole と、ECS の更新・ECR への push を持つ | 2026-03-27。使ったのは [turingmotors/tuscenes-processor](https://github.com/turingmotors/tuscenes-processor) の CI（main への push で、ECR への push とシークレットの読み取り）。このリポジトリはその後アーカイブされた | スタック `tuscenes-cicd`（コードなし） | スタックごと消す。同系統でアーカイブされていないのは `tuscenes-calibration-check`（最終 push 2025-10-27）だけ。念のため、そのワークフローがこのロールを使っていないことを確かめる |
| S11 | セキュリティグループ `launch-wizard-1`・`launch-wizard-2`・`ssh-public`・`sky-sg-ubuntu-7523`・`sky-sg-yasumoto-3278`（us-west-2） | **SSH（22）を全世界に開放**。どこにも付いていない | — | なし | 消す |

ほかに気づいたこと（掃除ではなく、設定の見直しの候補）:

- GitHub Actions のロールの多くは、`pull_request` や全ブランチ（`ref:refs/heads/*`）からも引き受けられる。deploy を行うロール（`DatabricksTerraformDeployRole`・`CloudflareTerraformDeployRole`・`ModelcoreDeployRole`・`cdk-apps-diff-role` など）も含む。`ScenarioTestImagePublishingRole`・`ds-openpilot-ci-read-asset`・`vad-e2e-ci` は `repo:…:*`（何でも可）。
- ap-northeast-1 の `eks-cluster-sg-Coder-Cluster-753063954` が、ポート 30618 を全世界に開けている（Coder の EKS。使用中）。
- ReadOnlyAccess の IAM ユーザー `devin-readonly` は、キーが有効で毎日使われている（掃除の対象ではない）。

## 2. 競合しかねないもの

変更を加えようとしたときにぶつかりうるもの。型は [aws-resource-inventory.md](../aws-resource-inventory.md) の「設計判断と理由」を参照。

### 型 1: 眠っている（または待ち構えている）仕掛け

| # | 対象 | 状態 | 何が起きるか |
| --- | --- | --- | --- |
| C1-1 | **`tuscenes-tmp` の S3 通知 → `tuscenes-CleaningJob-Function`**（新しく分かった） | 通知が 2 本（`2.1/` の下の `.json`・`.csv` の作成）。どのスタックも持っていない。Lambda の呼び出しは 90 日 0 回 | `tuscenes-tmp` の `2.1/` に `.json`・`.csv` を置くと、**cleaning の job（SageMaker）が起動する**。tuscenes-tmp は Databricks から今も読まれている（ロールの最終利用 2026-10-27）。[tuscenes-stack-cleanup.md](../../../aws-data-protection/workstream/tuscenes-stack-cleanup.md) には未記載 |
| C1-2 | ルール `tuscenes-NewSceneEventRule…`（tuscenes-cleaned） | ENABLED。tuscenes-cleaned の EventBridge は有効だが、バケットは空 | 調査済み（tuscenes-stack-cleanup） |
| C1-3 | ルール `tuscenes-CleaningJobStateChangeRule…` | ENABLED | cleaning の job が動けば発火する。C1-1 とつながっている |

ほかの S3 を出どころにするルールは、`Datalake-RlogDecoderUploadRule…`（td1-raw、使用中）と `original-bucket-audit-s3-events`（カナリア）だけで、眠っているものは無かった。

### 型 2: 丸ごと上書きする持ち主

| # | 対象 | 状態 |
| --- | --- | --- |
| C2-1 | td1-raw の通知 | 調査済み（第二弾の TODO 23）。Datalake が `Managed: true` で持ち、Databricks の SNS 2 本は次の deploy で消えうる |
| C2-2 | tuscenes-cleaned の通知 | スタック `tuscenes` が `Managed: true` で持つ（EventBridge だけ）。スタックを消すと EventBridge が外れる |
| C2-3 | **Databricks の通知（SNS）が付いたバケット 15 本** | `csms-topic-by-path-*`・`databricks-auto-ingest-query-*` の SNS を、どのスタックも持っていない。closed-loop-scenario-test-result・cluster-storage-usage-reports・denso-nx-processed・denso-nx-raw・denso-taxi-processed・driving-behavior-data・embedding-ingest-to-databricks・gaming-data-collection・garuda-dataset・garuda-scene-list・scenario-test-result・tuscenes-annotation・tuscenes-calibration-test・tuscenes-raw（と td1-raw）。CDK でこれらに通知を足すときに `Managed: true`（`new s3.Bucket` で `addEventNotification`・`eventBridgeEnabled`）にすると、Databricks の取り込みが止まる |

### 型 3: 持ち主の不在・二重の持ち主

| # | 対象 | 状態 | 注意 |
| --- | --- | --- | --- |
| C3-1 | **スタック `github-oidc-provider`** | コードなし（2024-02-09 作成）。**GitHub の OIDC プロバイダーを持っていて、44 本のロールがこれに頼る** | S1・S2 の片付けで、隣のスタックと一緒に消してはいけない。消すと全リポジトリの GitHub Actions が AWS に入れなくなる。削除の保護を付けるか、cdk-apps に取り込む（import）のが望ましい |
| C3-2 | **スタック `databricks-s3-ingest-*` 31 本** | Databricks の画面（S3 の取り込みのクイックスタート）が作ったもの。コードなし。29 本は Unity Catalog の外部ロケーションとして使用中 | 消すとき、カスタムリソースが**スタックに保存された Databricks の個人アクセストークン**（NoEcho）で Databricks の API を呼ぶ。トークンが失効していれば削除は失敗する。Databricks 側の外部ロケーション・ストレージ資格情報を先に片付けるのが安全 |
| C3-3 | Lambda `vm-alarm-dev-periodic_task` とルール `vm-alarm-dev-periodic_task-event` | スタックなし（Serverless Framework 製とみられる）。**毎日 10:00 UTC に動いている**（90 日で 270 回）。最終更新 2024-02-29。環境変数 `GOOGLE_APPLICATION_CREDENTIALS` | 持ち主と用途が不明のまま動いている。持ち主を探す |
| C3-4 | CloudFront `E1K5TKF3VZ5EWE`（turing-video-frames、ap-northeast-1 のバケット） | スタックなし。90 日で 34 万リクエスト。バケットはスタック `VideoFrameExtractorOutputStack` が持つ | 手で作った配信。バケット側の変更（ポリシー・削除）で壊れうる。シークレット `video-frame-extractor/cloudfront-private-key`（ap-northeast-1）は一度も読まれていない |
| C3-5 | `tuscenes-tmp` の通知（C1-1） | バケットは Datalake が持つが、通知はどのスタックも持たない | 二重の持ち主の形 |
| C3-6 | コードの見当たらない CDK のスタック | `sfn-auto-labeling`（2024-10）・`DatabricksAutoLoader`（2024-11）・`LDAP`（2025-01）・`tuscenes-cicd`（2025-02）・`SharedBackend`（2025-02）・`YoutubeCollectorStack`（2026-02）、Amplify の 2 本 | 誰も deploy しないので drift しても気づかない |

### 型 4: 宛先の消えた配線

- ルールのターゲット・S3 の通知の宛先で、消えたものを指すものは無かった（AWS が管理するルール 7 本を除く）。
- 信頼ポリシーが消えた主体を指すものは S9（Flyte）。

## 3. 使われていないもの

### IAM ユーザー（37 人。コンソールのログインは 0 人）

有効なキーが無いユーザーが 19 人。消しても認証が止まるものは無い。

| ユーザー | 最終利用 | 持ち主 | 権限 |
| --- | --- | --- | --- |
| map4-user | 2024-06-18 | なし | trip-data-read-only |
| tuscenes-basicai-user | 2024-09-22 | tuscenes | BasicAI のバケットの読み書き・削除（tuscenes-stack-cleanup で扱う） |
| DatabricksAutoLoader-User00B015A1-… | 2024-12-26 | DatabricksAutoLoader | — |
| abemi | 2025-01-28 | なし | read-dataset |
| AzureDatabricks-AutoLoaderUser… | 2025-03-25 | AzureDatabricks | S3ReadOnly |
| jadd-dataset-read | 2025-04-05 | なし | jadd-dataset-read |
| tsukamoto | 2025-07-01 | なし | read-dataset |
| shio-secretsmanager_GetSecretValue | 2025-08-07 | なし | S1 表の S6 |
| appen-read-write | 2025-08-14 | なし | put・read（Appen 向けとみられる） |
| jadd-datasync・jadd-remote-sync-kohei.watanabe | 2025-10 | なし | S1 表の S5 |
| Databricks-EvalMapConverter… | 2026-03-17 | Databricks | — |
| qinertia-runner-gaggle | 2026-05-21 | QinertiaRunner | — |
| sasaki | 2026-05-28 | なし | S1 表の S6 |
| cluster-toolkit-user | 2026-06-01 | ClusterToolkit | — |
| ClosedLoopScenarioTestEks-…MetricsUser | 2026-06-24 | ClosedLoopScenarioTestEks | — |
| gaggle-shared-user | 2026-09-24 | なし | put-models・read-dataset（キーを止めたのは最近） |
| TuringDataExplorerStack-EmbeddingIngestGaggleUser… | 一度も使われていない | TuringDataExplorerStack | — |
| gaming-data-collection-uploader | 一度も使われていない | GamingDataCollectionStack | project:gaming-data-collection に関係 |

有効なキーがあるのに使われていないもの:

- `Databricks-NaviGeneratorDatabricksNaviGeneratorUser-…`: 最終利用 2026-05-02（178 日）。
- `Databricks-QinertiaRunnerDatabricksQinertiaRunnerUs-…`: キーが 2 本とも有効。1 本目は 2026-05-26 が最後で、2 本目は毎日使われている。1 本目は入れ替えの残り。

### IAM ロール（694 本）

- 内訳: サービスリンク 33・SSO 20・CDK の bootstrap 20・Control Tower 7・その他 614。
- その他のうち、180 日以上使われていないものが 229 本。151 本はスタックに属し（スタックごと片付ける）、78 本はスタックに属さない（手で消す）。一覧は `derived/iam-roles.tsv`。
- スタックに属さないものの主な群: SageMaker の Service Catalog 用（10 本、未使用）・Canvas・Studio 系、Amplify の SSR のログ用（11 本）、RlogVisualizer（5 本）、tuscenes-dataset のレプリケーション・取り込み・DataSync（10 本、2025 年まで）、Flyte（S9）、EMR Studio・Glue（2024-08）、ジャカルタの `ec2-s3-download-role-ap-southeast-3`、`vad-e2e-ci`（2026-04-16）、`rerun-data-api-GithubActionsRole`（2025-01-08）。
- スタックに属するものの主な群: `databricks-s3-ingest-*` の作成時だけ使う Lambda のロール（59 本）、`tuscenes`（11 本）、`Coder`・`CoderWorkspace`（17 本）、`ClosedLoopScenarioTest*`（12 本）。

### CloudFormation のスタック（ルート 128 本）

| 対象 | 状態 | 案 |
| --- | --- | --- |
| `amplify-d3u7ftafn08oup-main-branch-3a3f2d1bf5`・`databricks-s3-ingest-55042`・`databricks-s3-ingest-764d8` | ROLLBACK_COMPLETE（作成に失敗した殻） | 消す |
| `databricks-s3-ingest-e2441`（databricks-auto-ingest、2025-02-25）・`-10067`（mlflow-sandbox、2026-02-25）・`-f0b4a`（tuscenes-cleaned、2026-03-26）・`-e3370`（turing-video-frames、作成した日だけ） | 外部ロケーションのロールが 180 日以上使われていない | Databricks 側の外部ロケーションを確かめてから。C3-2 の注意 |
| `databricks-s3-ingest-9109d`（tuscenes-map、2026-04-06）・`-f4a68`（tuscenes-dataset、2026-07-01） | 90〜180 日 | 様子見 |
| `github-actions-file-publishing`・`github-actions-image-publishing` | S1・S2 | 消す（`github-oidc-provider` は残す） |
| `tuscenes` | 調査済み | tuscenes-stack-cleanup で扱う |
| C3-6 のスタック | コードなし | 中身を見て判断 |

`databricks-s3-ingest-*` の 31 本は、作成時だけ使う Lambda 2 本・ロール・バケット（`…-lambdazipsbucket-…`）を 1 組ずつ残している。

### Lambda（224 本）

- 90 日の呼び出しが 0 回のものが 125 本。多くは CDK・Databricks のカスタムリソース用（作成・更新のときだけ動く）なので、それだけでは消す理由にならない。
- 持ち主のいない未使用のもの: `alphard_route_gen`（S4）、`ModelConverter-BucketNotificationsHandler…`（スタック ModelConverter の古い世代の残り）、`Flyte-CustomVpcRestrictDefaultSG…`（Flyte の残り）。
- tuscenes の 7 本は tuscenes-stack-cleanup で扱う。
- 一覧は `derived/lambda.tsv`。秘密らしい名前の環境変数を持つ関数は `derived/lambda-env-secret-keys.tsv`（平文の値を持つのは `alphard_route_gen` だけ。ほかは SSM のパラメータ名など）。

### Secrets Manager（us-west-2 68 個、ap-northeast-1 6 個）

90 日以上読まれていないもの（**消しても、発行元で失効させない限り鍵は生きている**。消す前に発行元で失効させる）:

| リージョン | シークレット | 最終アクセス | 持ち主 |
| --- | --- | --- | --- |
| us-west-2 | tuscenes/notion | 2024-07-03 | なし |
| us-west-2 | oidc/google・oidc/github | 2025-01-06 | なし |
| us-west-2 | DatabaseSecret…・SlurmDBSecret… | 2025-01 | Coder |
| us-west-2 | databricks/video-slice-service・databricks/rerun-data-api | 2025-03 | なし |
| us-west-2 | openai | 2025-03-25 | なし |
| us-west-2 | video-streaming-service/supabase/jwt-secrets | 2025-04-16 | なし |
| us-west-2 | intdash | 2025-05-16 | なし |
| us-west-2 | ecr-pullthroughcache/docker-hub | 2025-05-23 | なし |
| us-west-2 | databricks/video-frame-generator・databricks/data-hub | 2026-01-16 | なし |
| us-west-2 | databricks/jadd-studio | 2026-03-25 | なし |
| us-west-2 | supabase/jadd-studio-dev・supabase/backend-dev | 2026-04-23 | なし |
| us-west-2 | e2e-sandbox-414801/service-account（GCP のサービスアカウントとみられる） | 2026-05-28 | なし |
| us-west-2 | nr-license-key-… | 2026-05-28 | NewRelic-AWS-Integration |
| ap-northeast-1 | video-frame-extractor/cloudfront-private-key | 一度も読まれていない | なし（C3-4） |
| ap-northeast-1 | ecr-pullthroughcache/docker-hub・ecr-pullthroughcache/ghcr | 2025-02〜03 | なし |

### そのほか

- SQS（us-west-2 99 本）: 90 日の送信が 0 件のものが 39 本。うち 34 本は Databricks の取り込み（file events）が作ったキュー。
- セキュリティグループ: us-west-2 の 100 個のうち、どの ENI にも付いていないもの（default を除く）が 42 個。全世界への SSH は S11。ap-northeast-1 は 0 個。
- KMS: カスタマー管理のキーは 3 本（us-west-2 の `alias/turing/ssm`・`alias/ssm`、ap-northeast-1 の `alias/ssm`）。使われているかは CloudTrail でしか分からないので、まだ判定していない。
- CloudFront: 5 本とも使われている。Route 53 は `apps.turing-ai.dev` の 1 ゾーン。ACM の証明書は全部使用中。
- IAM の OIDC プロバイダー 4 つは、どれも信頼するロールがある。

## 4. 優先度 A（費用のかかるもの）

us-west-2・ap-northeast-1 を見た。一次情報は同じく `~/aws/tuscenes-prod/2026-10-28/`。利用の判定は CloudWatch の直近 90 日の値。

### 片付けの候補

| # | 対象 | 根拠 | 持ち主 | 案 |
| --- | --- | --- | --- | --- |
| A1 | NAT Gateway `nat-0b516a81ce3a4585b`（VPC `ml-ops-vpc`、2024-02-06 作成） | 90 日の転送量 0。VPC の中には NAT しか無い | なし | VPC ごと消す |
| A2 | NAT Gateway `nat-05e298c48aaacd9a0`・`nat-07ca4f856cea2eb54`（Databricks のワーカーの VPC） | 90 日の転送量 0。VPC の中には NAT しか無い。作成日がスタック `databricks-workspace-stack-d3570`（2025-10-14）・`-d0cfc`（2025-08-27）と一致 | Databricks のワークスペースのスタック | Databricks のワークスペースの側で、クラシックの計算資源を使っていないか確かめる。`nat-0e70ef49932572130`（2026-07 作成、最後の転送は 2026-08-28）も同じ形 |
| A3 | NAT Gateway `nat-0b99844221c18fd5d`（`Coder/Vpc`） | 90 日の転送量 0 | Coder（us-west-2） | A6 と合わせて判断 |
| A4 | Elastic IP `34.208.220.170`（`auto-labeling-eip-us-west-2a`）・`54.244.115.207`（`Flyte/Vpc/PublicSubnet1`） | どこにも割り当てられていない | なし（Flyte のスタックは消えた） | 解放する |
| A5 | RDS の手動のスナップショット: us-west-2 の `flyte-snapshot-*`（クラスター 2・インスタンス 2、2024-11〜2025-05）・`tuscenes-pipeline-snapshot-*`・`tuscenes-snapshot-studiodatabase*`（2024-03〜05）、ap-northeast-1 の `coder*-snapshot-*`（2025-02・2025-06 の 5 個） | 元の DB はもう無い（Flyte・tuscenes studio）か、移行の際の残り | なし | 中身が要らなければ消す |
| A6 | **us-west-2 の Coder 一式**（スタック `Coder`、106 リソース。ALB・Aurora 2 台（db.t4g.medium）・NAT・EFS） | スタックの最終更新は 2025-01-14。今使われている Coder は ap-northeast-1（`coder-v2.turing-ai.dev`）とみられる。ただし ALB は 90 日で 34 万リクエスト、Aurora の最大接続数は 8 で、何かが動いている | Coder（cdk-apps） | **要確認**。旧環境が残っているだけなら大きい。持ち主に確かめる |
| A7 | EKS `CoderWorkspaceCluster`（us-west-2、2025-02 作成） | ノードグループ 0。スタック `CoderWorkspace`（us-west-2）のロール 8 本は一度も使われていない | CoderWorkspace | 要確認（クラスター 1 本で月 $73 前後） |
| A8 | EBS の未アタッチ 3 本（78 GiB）: `vol-0bac9cc937635e469`（CoderWorkspace の PVC、2025-02）・`vol-008879c07bd29b519`（Skypilot の PVC、2026-07）・`vol-00d62035721cd73d5`（2024-10） | どこにも付いていない | — | 消す |
| A9 | 停止中の EC2（Coder のワークスペース）: us-west-2 7 台・ap-northeast-1 7 台 | 停止が 90 日を超えるもの 10 台（停止した日）: ap-northeast-1 の `coder-debug`（t4g.micro、2025-02-18。キーペア `mats`）・`coder-toshiyukikato-replay-005`（07-06）・`coder-tatsuyasuzuki-test3-suzuki`（07-10）・`coder-tatsuyasuzuki-test2-tensorrt`（07-11）・`coder-keishiishihara-openpilot-2`（07-22）、us-west-2 の `coder-hayataebisawa-a`（2026-02-05）・`coder-ryuozaki-vins`（06-19）・`coder-yutaide-GPU`（06-22）・`coder-yutonakamura-scarlet-lizard-2`（07-19）・`coder-takumaseno-openpilot`（07-27） | Coder | Coder の側でワークスペースを消す（EBS が残り続ける） |
| A10 | **ECR（us-west-2）22.5 TB**（月 $2,200 前後） | push から 180 日を超えたイメージが 1,907 個・10.5 TB。大きいのは `closed-loop-scenario-test`（5.1 TB）・`3dgs-train`（2.9 TB）・`openpilot-replay`（1.4 TB、最終 push 2025-09-18）。最終 push が 180 日を超えたリポジトリは 17 本（`alphaspp-ui`・`alphaspp-devkit`・`tsuk-test`・`rerun-data-api`・`tuscenes-validator`・`jupyter`・`sagemaker-studio` など） | 各チーム | ライフサイクルポリシーを入れる。古い系統のリポジトリは消す |
| A11 | **CloudWatch Logs（us-west-2）9.0 TB**。保持期間が無期限のロググループが 368 個・9.0 TB | 最大は `/aws/batch/job`（8.1 TB）。ほかに VideoFrameGenerator の Lambda（390 GB）、ClosedLoopScenarioTestEks の Container Insights（計 410 GB） | 各スタック | 保持期間を決める（費用に加え、ログに機微な情報が残り続ける） |

### 気づいたこと

- **ECR のイメージは、ほぼ全部（5,248 個）の最終 pull が 2026-10-27 だった。** 何かが毎日すべてのイメージを pull している（脆弱性のスキャナーなどとみられる。主体は未確認）。そのため、ECR の「最終 pull」は使われているかの根拠にならない。上の A10 は push の日付で見た。
- EBS のボリュームの 127 本（149 本中、us-west-2）が暗号化されていない。
- EKS のクラスター 5 本は、すべて API のエンドポイントを全世界（`0.0.0.0/0`）に公開している。
- 動いている EC2（us-west-2 125 台・ap-northeast-1 4 台）は、すべて IMDSv2 を必須にしていた。停止中の Coder のワークスペースの多くは IMDSv1 を許している。
- SageMaker はドメイン `e2e`（us-west-2）が 1 つあるだけで、エンドポイント・ノートブック・アプリは無い。
- 動いていない ECS のクラスター（us-west-2 31 本）は、ほとんどが AWS Batch の計算環境が持つもの。片付けの対象ではない。

### S3（バケット単位）

価値の判定は project:aws-data-protection の分類（[raw-data-security.md](../../../aws-data-protection/workstream/done/raw-data-security.md) の S1〜S10）に任せ、ここでは使われていない形跡だけを挙げる。

- 空のバケット（14 本）: `sagemaker-automated-execution-*`・`sagemaker-studio-j6521u4939j`・`sharedbackend-rerundataapicachebucket…`（SharedBackend）・`tensorrt-engine-store`・`tsukamoto-test-*`・`tuscenes-basicai-export-*`・`tuscenes-basicai-import-*`・`tuscenes-basicai-results-*`・`tuscenes-cleaned-*`・`tuscenes-img-*`・`videoframegenerator-tmpbucket…`・`videosliceservice-tmpbucket…`。ほかに SSM の Quick Setup のもの 2 本（`do-not-delete-ssm-diagnosis-*`。消さない）。
- 90 日間オブジェクトの数が変わっていないもの: 81 本。`databricks-s3-ingest-*-lambdazipsbucket-*`（33 本。作成時だけ使うもの、C3-2）のほか、大きいのは `miwa-gmo-2026-0424-archive`（24.3 TB）・`td1-video-h265-gcp-*`（9.1 TB）・`dataset-for-appen`（707 GB）・`tuscenes-sampled-*`（558 GB）・`nuscenes-all`（518 GB）・`alphaspp-data-*`（372 GB）・`semantic-kitti`（189 GB）・`denso-data-*`（172 GB）。数が変わらないことは、読まれていないことを意味しない（読むだけのデータセット）。
- `nuscenes-all`・`argoverse2-all`・`semantic-kitti` は公開データセットの写しとみられる（取り直せる）。
- Flyte の残り: `flyte-bucket83908e77-*`・`flyte-userdatabucket58c9ae06-*`（スタックなし）。

## 5. 報告だけのリージョン

[stage0-overview.md](stage0-overview.md) を参照。要点:

- us-east-1: 今も月 $47 前後（S3・Secrets Manager・KMS）。スタック 3 本（`CDKToolkit`・`CoderWorkspace`・`DatadogCCMIntegration`）。
- us-east-2: S3 は 2026-02 で止まった。Secrets Manager・KMS が月 $7.81 程度残る。
- ap-southeast-3（ジャカルタ）: EC2 は 2026-01 で止まった。VPC・サブネット 6 などのネットワークと、ロール `ec2-s3-download-role-ap-southeast-3` が残る。
- ap-northeast-3（大阪）: 形跡なし。

## 6. まだ見ていないもの

- 優先度 C: VPC エンドポイント（取得済み・未集計）・Glue・Step Functions・DynamoDB・Kinesis Firehose・API Gateway など。VPC は us-west-2 の 30 個のうち、ENI が 0 のものが 13 個（多くは AWS Batch 用の CDK の VPC で、ジョブが無いときは空になる）。持ち主のいない `tuscenes/Vpc`（ENI 0）がある。
- KMS のキーの利用状況（CloudTrail が要る。管理イベントはログ用のアカウント 617808723336 に送られていて、このアカウントの ReadOnly では 90 日より前を見られない）。
- ECR のイメージを毎日 pull している主体。
