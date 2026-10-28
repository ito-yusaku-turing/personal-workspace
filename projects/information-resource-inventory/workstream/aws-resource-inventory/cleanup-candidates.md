# tuscenes-prod の掃除の候補（2026-10-28 時点）

AWS アカウント tuscenes-prod（767397804933）の棚卸しの結果。伊藤の判断用のリストで、チーム向けには書いていない。セキュリティの観点（優先度 B）・グローバルなサービス・優先度 A・優先度 C を見終えた時点のもの。Coder（旧版が片付けの対象）と NAT Gateway は掘り下げた（5 章・6 章）。

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
| S7 | ロール `tuscenes-sampler-test-role-n1huu9jg`・`tuscenes-processing`・`AmazonEMRStudio_RuntimeRole`・`ecsTaskExecutionRole` | S3FullAccess や SecretsManagerReadWrite | 2024-07〜2025-03 | なし | 消す。`ecsTaskExecutionRole` は既定の名前なので、参照するタスク定義が無いことを確かめてから。`CoderWorkspaceRole`（SecretsManagerReadWrite、2025-10-08）はスタック `Coder` が持つので、5 章で一緒に片付ける |
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
| A1〜A3 | NAT Gateway | 6 章に移した | | |
| A4 | Elastic IP `34.208.220.170`（`auto-labeling-eip-us-west-2a`）・`54.244.115.207`（`Flyte/Vpc/PublicSubnet1`） | どこにも割り当てられていない | なし（Flyte のスタックは消えた） | 解放する |
| A5 | RDS の手動のスナップショット: us-west-2 の `flyte-snapshot-*`（クラスター 2・インスタンス 2、2024-11〜2025-05）・`tuscenes-pipeline-snapshot-*`・`tuscenes-snapshot-studiodatabase*`（2024-03〜05）、ap-northeast-1 の `coder*-snapshot-*`（2025-02・2025-06 の 5 個。Coder の旧版から新版への移行のときのもの） | 元の DB はもう無い（Flyte・tuscenes studio）か、移行の際の残り | なし | 中身が要らなければ消す。Coder のものは新版の持ち主に確かめる |
| A6・A7 | Coder | 5 章に移した（旧版だけが片付けの対象。新版は利用中） | | |
| A8 | EBS の未アタッチ 3 本（78 GiB）: `vol-0bac9cc937635e469`（CoderWorkspace（新版）の PVC、2025-02）・`vol-008879c07bd29b519`（Skypilot の PVC、2026-07）・`vol-00d62035721cd73d5`（2024-10） | どこにも付いていない | — | 消す |
| A9 | 停止中の EC2（Coder の新版のワークスペース）: us-west-2 7 台・ap-northeast-1 7 台 | 停止が 90 日を超えるもの 10 台（停止した日）: ap-northeast-1 の `coder-debug`（t4g.micro、2025-02-18。キーペア `mats`）・`coder-toshiyukikato-replay-005`（07-06）・`coder-tatsuyasuzuki-test3-suzuki`（07-10）・`coder-tatsuyasuzuki-test2-tensorrt`（07-11）・`coder-keishiishihara-openpilot-2`（07-22）、us-west-2 の `coder-hayataebisawa-a`（2026-02-05）・`coder-ryuozaki-vins`（06-19）・`coder-yutaide-GPU`（06-22）・`coder-yutonakamura-scarlet-lizard-2`（07-19）・`coder-takumaseno-openpilot`（07-27） | Coder | Coder の側でワークスペースを消す（EBS が残り続ける） |
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

## 5. Coder（掘り下げ）

Coder は 2 つの版がある（2026-10-28 伊藤）。**片付けの対象は旧版だけ**。新版は今も使われている。新版の利用の実態が AWS から分からないこと（下の「新版の状態」）への手当ては、別に検討する（伊藤）。

| 版 | 構成 | 作成 | 扱い |
| --- | --- | --- | --- |
| 旧版 | us-west-2 のスタック `Coder`（ECS のサーバー・ALB・Aurora・EFS 3 本・VPC・NAT） | 2024-05-06（最終更新 2025-01-14） | **片付けの対象** |
| 新版 | ap-northeast-1 のスタック `Coder`（EKS `Coder-Cluster`・Aurora・VPC・NAT、`coder-v2.turing-ai.dev`）と、ワークスペース用のスタック `CoderWorkspace`（us-west-2・ap-northeast-1・us-east-1） | 2025-02-12・13 | 利用中。消さない |

同じ名前のスタック `Coder` が 2 つのリージョンにあるので、取り違えに注意する。ワークスペース（停止中 14 台）は、両リージョンとも新版のもの（新版のスタックのロール `Coder-WorkspaceRole…` を使う）。新版は us-west-2 にもワークスペースを作る（ロール `Coder-ClusterProvisionerRole…` の最終利用が us-west-2）。

### 旧版の状態（2026-10-28）

- サーバーの ECS のタスクが 1 つ動いている（今日 07:08 UTC にも入れ替わった）。ALB には毎日数百〜1 万件のリクエストがある（90 日で 34 万件）。Aurora の最大接続数は 8。アクセスログは無効なので、リクエストの出どころは分からない。
- NAT Gateway の 90 日の転送量は 0。EFS 3 本の 90 日間の読み書きは 0。
- **スタックに載っているのに実体が無いものがある**: EKS `Coder-AutoCluster` と Aurora `coder-slurmdb7993b14f-*`（どちらも describe で見つからない）。スタックの外で消したとみられる。スタックを消すときに、ここで止まらないか注意する。
- 新版への移行の跡: ap-northeast-1 の RDS のスナップショット `coder-snapshot-databaseb269d8bb-*`（2025-02-12）は、旧版の DB（`coder-databaseb269d8bb-*`）を写したもの。

### 旧版の費用（2026-09 の 1 か月。概算）

| 内訳 | 額 |
| --- | ---: |
| Aurora（db.t4g.medium 2 台） | $108 |
| EFS（`Coder/DataFileSystem` 28.8 TB、ほぼ Archive） | 約 $230 |
| NAT Gateway・ALB | 約 $55 |
| ECS のタスク | 未確認 |
| **合計** | **約 $400/月** |

### 旧版の洗い出し（片付けの対象）

| 区分 | 対象 | 消すときの注意 |
| --- | --- | --- |
| スタック | us-west-2 の `Coder`（106 リソース）と、入れ子の `Coder-CoderAutoCluster…KubectlProvider…` | EFS 3 本と S3 `coder-assets-767397804933` は `Retain`（残る）。Aurora は `Snapshot`（最終スナップショットができる）。実体の無い 2 つ（上）で止まりうる |
| EFS（`Retain` で残る） | `Coder/DataFileSystem`（**28.8 TB、ほぼ Archive**、90 日間の読み書き 0）・`Coder/HomeFileSystem`・`Coder/SharedFileSystem`（どちらも空） | 28.8 TB の中身が誰の何かを確かめてから決める。新版に移したか、ユーザーのデータが残っているか |
| S3（`Retain` で残る） | `coder-assets-767397804933`（4 オブジェクト） | 中身を見て消す |
| シークレット | `DatabaseSecret3B817195-*`・`SlurmDBSecret533AAEEA-*`（スタックの中。最終アクセス 2025-01） | スタックと一緒に消える |
| ロール | スタックの中の 7 本と `CoderWorkspaceRole`（SecretsManagerReadWrite、最終利用 2025-10-08） | スタックと一緒に消える |
| ロググループ | `/aws/lambda/Coder-CoderAutoCluster*`・`/aws/lambda/Coder-CustomVpcRestrictDefaultSG*`・`Coder-LogGroup*`・`Coder-ServiceTaskDefnginxLogGroup*`（us-west-2） | スタックの外のものは手で消す |
| RDS のスナップショット | ap-northeast-1 の `coder-snapshot-databaseb269d8bb-*`（移行のときの写し） | 新版の移行が済んでいれば消す |

**旧版と一緒に消してはいけないもの**:

- シークレット `coder/oidc/github`・`coder/oidc/google`（us-west-2、スタックの外）は、**2026-10-27 に読まれている**。新版が使っているとみられる。
- us-west-2 の `CoderWorkspace` のスタック・EKS `CoderWorkspaceCluster`・ワークスペースの EC2 は新版のもの。
- `Coder-*` で始まるロールのうち、`Coder-Cluster*`・`Coder-WorkspaceRole…` は新版（ap-northeast-1 のスタック）のもの。

順番の案: (1) 28.8 TB の EFS の中身を確かめる → (2) ECS のサービスを 0 にして、何か困る人が出ないか様子を見る → (3) スタックを消す（入れ子は親と一緒に消える）→ (4) 残ったもの（EFS・S3・最終スナップショット・ロググループ）を片付ける。

### 新版について気づいたこと（片付けではない）

- 費用（2026-09）: EKS 3 本（`Coder-Cluster`・`CoderWorkspaceCluster` 2 本）が **バージョン 1.32 のまま延長サポートの料金（1 本 $432/月、計 $1,296/月）**。標準サポートのバージョンに上げれば 1 本 $73/月になる。Aurora（ap-northeast-1）$257。
- 停止中のワークスペース 14 台の EBS が 7.9 TB（約 $630/月）。90 日を超えて止まっているものが 10 台（A9）。Coder の側で消すのが筋。
- **`CoderWorkspace` の共有 EFS は `DeletionPolicy: Delete`**。スタックを消すと中身ごと消える（us-west-2 1.5 TB・ap-northeast-1 3.2 TB）。
- ap-northeast-1 の ALB `k8s-coder-coder-a7d165dea7` とセキュリティグループ 2 個は k8s が作ったもので、スタックの外。将来スタックを消すときは、先に k8s の側で消す。
- ap-northeast-1 の EFS `Coder/CsiFileSystem`（5.7 GB、マウントターゲット 0、スタックなし）は使われていない。消してよい候補。
- 利用の実態（ALB のリクエストが人によるものか）は、アクセスログが無効なので AWS からは分からない。手当ては別に検討する（伊藤）。

## 6. NAT Gateway（掘り下げ）

NAT Gateway は、1 本で月 $33 ほど（時間料金。転送量は別）かかる。どのサブネットが経路に使っているか、そのサブネットに何がいるか、90 日間の接続数と転送量を見た。

| NAT | VPC | 作成 | 経路に使うサブネットの中身 | 90 日の最大接続数・転送量 | 判定 |
| --- | --- | --- | --- | --- | --- |
| `nat-0b516a81ce3a4585b` | `ml-ops-vpc`（持ち主なし） | 2024-02-06 | サブネット 3、ENI 0 | 0・0 | **消す**。VPC には NAT と S3 のゲートウェイエンドポイントしか無い。VPC・EIP ごと消す |
| `nat-0b99844221c18fd5d` | `Coder/Vpc`（us-west-2、Coder の旧版） | 2024-05-06 | EFS のマウントターゲット 9・RDS 2 | 0・0 | 5 章で旧版と一緒に消える |
| `nat-015fe2e1fa8d7964c` | `Coder/Vpc`（ap-northeast-1、Coder の新版） | 2025-02-12 | EKS・RDS | 435・8.5 GB | 使用中 |
| `nat-07ca4f856cea2eb54` | Databricks のワーカーの VPC（ワークスペース `workshop`、スタック `databricks-workspace-stack-d0cfc`） | 2025-08-27 | — | 0・0 | **Databricks のワークスペース `workshop` を消す**（VPC と NAT は Databricks が作ったもので、ワークスペースと一緒に片付ける） |
| `nat-05e298c48aaacd9a0` | Databricks のワーカーの VPC（ワークスペース `secondee`、スタック `databricks-workspace-stack-d3570`） | 2025-10-14 | — | 0・0 | 同上（`secondee`） |
| `nat-0e70ef49932572130` | Databricks のワーカーの VPC（`workerenv-747465534265`。どのワークスペースかは、CloudFormation からは分からない） | 2026-07-10 | — | 25・0.08 GB（最後は 2026-08-28） | Databricks のアカウントの画面で、どのワークスペースか確かめる |
| `nat-08633f1f1c3de9bc0` | Databricks のワーカーの VPC（`workerenv-391377578046`、主のワークスペース `e2e` とみられる） | 2024-08-29 | — | 4,096・454 GB | 使用中 |
| `nat-0b855302db270f550` | VideoFrameExtractorStack | 2026-01-15 | ECS | 154・372 GB | 使用中 |
| `nat-06819f9c66c51eb18` | SkypilotApiServer | 2026-08-17 | EKS・NLB・Lambda | 69・21 GB | 使用中 |

- Databricks のワークスペースのスタック（`databricks-workspace-*`）は、Databricks の画面のクイックスタートが作ったもの。消すときは、C3-2 と同じく、カスタムリソースが保存された Databricks のトークンで API を呼ぶ。ワークスペースは Databricks のアカウントの画面で消すのが筋。
- Databricks の VPC には、持ち主のいない S3 のゲートウェイエンドポイントが 1 つずつある（ワークスペースと一緒に消える）。

片付けで止まる NAT は 4 本（`ml-ops-vpc`・Coder の旧版・Databricks 2）、月 $130 前後。

## 7. 優先度 C

| 種別 | 結果 | 候補 |
| --- | --- | --- |
| Route 53（`apps.turing-ai.dev`） | API Gateway を指す A レコード 5 本は、どれもドメインが実在する | Vercel を指す CNAME 3 本（`digital-signage`・`jadd-studio-signage`・`jadd-studio`）は、Vercel の側にプロジェクトがあるかを AWS からは確かめられない。消えていればサブドメインの乗っ取りの余地になる |
| Step Functions（26） | 90 日間実行の無いものが 2 本 | `BulkPipelineStateMachine74302C4C-BcRAHN9RFO0Z`・`ScenarioTestClosedLoop-Run-StateMachine`（どちらも一度も実行されていない） |
| DynamoDB（15） | 持ち主のスタックが無いもの | `tuscenes-table`（0 件、2024-03）・`turing-video-status`（0 件、2025-02）・`test-007`（0 件、2024-12）・`alphaspp-scene-table`（101 件、2024-02）・`vad-e2e_test-data`（4 件、2025-01） |
| Cognito（3） | どれもスタックが無い | `FlyteUserPool`（2024-11。Flyte は消えた）・`DataHub-Auth`（2024-12）・`UserPool6BA7E5F2-qHTym8tzlxyc`（2024-11）。利用者の情報（メールアドレスなど）を持ちうるので、要らなければ消す |
| AWS Batch（計算環境 28） | 持ち主のいないもの 1 | `auto-labeling-compute-env`。スタック `sfn-auto-labeling`・`Infra-ECS-Cluster-auto-labeling-*`、EIP `auto-labeling-eip-us-west-2a`（A4）と合わせて、auto-labeling の一式（2024-09〜10）として片付ける |
| EFS | 5 章 | `Coder/CsiFileSystem`（新版の残り） |
| VPC エンドポイント（20、すべて S3 のゲートウェイ型） | 持ち主のいないもの 5 | `ml-ops-vpc` と Databricks の VPC 4 つ。VPC と一緒に消える |
| CloudWatch のアラーム（43） | すべて OK。消えたリソースを見張るもの（INSUFFICIENT_DATA）は無い | 通知先の無いアラームが 15 本（us-west-2） |
| EventBridge Scheduler（8） | どれも実在のターゲットを指す | — |
| SSM パラメータ（144） | SecureString 45。1 年以上更新されていないもの 18 | 値は見ていない |
| Glue・Amplify・Backup・VPC ピアリング・Transit Gateway | どれも無い（Glue は `default` データベースだけ） | — |
| IAM のインスタンスプロファイル（75） | 動いているインスタンスで使われていないもの 65 | 起動テンプレートや Batch が使うものもあるので、ロールと一緒に判断する |

## 8. 報告だけのリージョン

[stage0-overview.md](stage0-overview.md) を参照。要点:

- us-east-1: 今も月 $47 前後（S3・Secrets Manager・KMS）。スタック 3 本（`CDKToolkit`・`CoderWorkspace`・`DatadogCCMIntegration`）。
- us-east-2: S3 は 2026-02 で止まった。Secrets Manager・KMS が月 $7.81 程度残る。
- ap-southeast-3（ジャカルタ）: EC2 は 2026-01 で止まった。VPC・サブネット 6 などのネットワークと、ロール `ec2-s3-download-role-ap-southeast-3` が残る。
- ap-northeast-3（大阪）: 形跡なし。

## 9. まだ見ていないもの

- VPC は us-west-2 の 30 個のうち、ENI が 0 のものが 13 個（多くは AWS Batch 用の CDK の VPC で、ジョブが無いときは空になる）。持ち主のいない `tuscenes/Vpc`（ENI 0）がある。中身は細かく見ていない。
- Coder の ALB へのリクエストの出どころ（アクセスログが無効）。手当ては別に検討する（伊藤）。
- KMS のキーの利用状況（CloudTrail が要る。管理イベントはログ用のアカウント 617808723336 に送られていて、このアカウントの ReadOnly では 90 日より前を見られない）。
- ECR のイメージを毎日 pull している主体。
