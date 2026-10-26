# 原本バケットへのアクセスの洗い出しと手当て

- 開始: 2026-10-19
- **完了（2026-10-20）**: 第一弾として完結。残りの TODO は [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md) に引き継いだ
- 状態: **洗い出しの表ができた（2026-10-20）**。レビューと手当ての案づくり（バケットポリシー）は第二弾に移した
- 所属: project:aws-data-protection（2026-10-26 に `~/docs/workstream/` から移した）
- 親: [走行データ消失リスクへの対応](raw-data-security.md)（種別 S1〜S10 と処遇、裁定はそちらが正本）
- 兄弟: [原本バケットのバージョニング（cdk-apps の準備）](s3-versioning-cdk.md)
- 用語: S3 の Versioning は「バージョニング」と書く。旧版を指すときは「古い版」

## 位置づけ

親 workstream の裁定（2026-10-15）の 2 段目と 3 段目にあたる。

| 段階 | 裁定の内容 | この workstream での扱い |
|---|---|---|
| いますぐやる | バージョニングを始める | 兄弟の workstream で PR を出した（cdk-apps #2211・#2215・#2216・#2217、レビュー中。2026-10-19 にすべてマージ・deploy 済み） |
| **次にやる** | **バケットポリシーを設計して設定する。レビューと現状調査をしっかりやってから**（今週〜来週中） | **ここで行う。** 洗い出しは、この「現状調査」にあたる |
| 焦らずじっくりやる | 削除権限を持つ主体の洗い出しと掃除（期限なし） | 洗い出しの結果は共有する。掃除（権限を外すこと）は急がない |

- 裁定では、調査書の SCP の案をバケットポリシーに置き換えている。
- バージョニングとバケットポリシーが入れば、S3 の削除の経路はほぼ塞がる。残るのは root（経路 10）と CloseAccount（経路 11）だけで、これは主体の掃除の側で扱う（親のレビュー 3）。

## 対象のバケット

親の種別のうち、バージョニングを行うもの（S1・S2・S4）と、既に導入済みの S3。

| 種別 | バケット |
|---|---|
| S1 自社収集 | td1-raw、tuscenes-raw、td1-rlog、gaming-data-collection、tuscenes-calibration（旧・新） |
| S2 他社から受領 | denso-taxi-video、denso-taxi-processed、denso-nx-raw、denso-raw |
| S3 AI モデル | tuscenes-model |
| S4 外注の成果物 | tuscenes-annotation |

- tuscenes-basicai-datasets（S4）は、今回の手当てから外した（中身と経緯がよく分からないため）。
- denso-nx-sample（S2）は、チームでバージョニングを却下した。バケットポリシーの対象に含めるかは、改めて決める。
- 範囲は tuscenes-prod（767397804933）だけ。他のアカウント（amman-pipeline、e2e-dev、biz-dev）は ReadOnly の SSO が無く、親でも調べていない。

## 洗い出すこと

守りたいのは「戻せない形で消す・壊す」操作。バージョニングが入った後に効く操作を中心に見る。

| 操作の種類 | アクションの例 | なぜ見るか |
|---|---|---|
| 版を指定した削除 | `s3:DeleteObjectVersion` | バージョニングがあっても、古い版ごと消せる |
| 守りを外す | `s3:PutBucketVersioning`、`s3:PutLifecycleConfiguration`、`s3:PutBucketPolicy`、`s3:DeleteBucketPolicy`、`s3:PutBucketObjectLockConfiguration` | 一時停止・1 日で失効させる規則・Deny の削除で、守りを無効にできる（親「IAM で『削除はできるが版は消せない』にする方法」） |
| バケットの削除 | `s3:DeleteBucket` | |
| 普通の削除・上書き | `s3:DeleteObject`、`s3:PutObject` | バージョニングの後は削除マーカー・古い版になるだけで戻せる。ただし課金が続く（LidarDeleter の件） |

主体ごとに次を取りまとめる。

- 主体（IAM ロール・ユーザー、SSO の権限セット、他アカウントの主体、AWS のサービス）
- 上の操作のどれができるか、その根拠（どのポリシーのどの Allow か）
- 直近 90 日に実際に使ったか（CloudTrail）
- 正当な用途（break-glass の候補か、ライフサイクルを書き換える CI か、など）

## 調べ方（案。読み取り専用）

| 情報源 | 分かること | 注意 |
|---|---|---|
| 各バケットのバケットポリシー（`get-bucket-policy`） | 他アカウントの主体への Allow | 親の下調べで、ポリシーのあるバケットは分かっている |
| IAM のロール・ユーザーのポリシー（`get-account-authorization-details`） | アカウント内の主体の Allow。AdministratorAccess・AmazonS3FullAccess の持ち主 | 多くは全部を Allow したポリシーなので、Allow を絞るだけでは足りない（親） |
| SSO の権限セット（cdk-apps `apps/organization-policy`） | どの権限セットが何をできるか、誰に割り当てているか | 割り当ては IAM Identity Center 側。FullAccess は 14 名（調査書 G22） |
| IAM Access Analyzer | 外部からのアクセス。組織内の主体からのアクセス（内部アクセスの分析） | 内部アクセスの分析が tuscenes-prod で使えるか、権限と費用を確かめる |
| CloudTrail の管理イベント（直近 90 日） | PutBucketLifecycle・PutBucketPolicy・PutBucketVersioning を呼んだ主体 | 親の下調べでは、対象バケットへの呼び出しは cdk の cfn-exec-role だけだった |
| CloudTrail のデータイベント | DeleteObject などを実際に呼んだ主体 | データイベントが記録されているかを先に確かめる（調査書は「削除は記録も検知もされない」としている） |
| Databricks の Unity Catalog | storage credential・external location が使う IAM ロール | Databricks の IAM ロールにもライフサイクルの権限がある（親のレビュー 4） |

## 洗い出しの結果（2026-10-20）

全主体の表は [principals-2026-10-20.md](s3-bucket-access-control/principals-2026-10-20.md)（66 主体。生成の手順とデータは `s3-bucket-access-control/data/`）。

### 調べた方法と確かさ

- **アカウント内の IAM 主体**（ロール 686・ユーザー 38）を、IAM ポリシーシミュレーターで、「洗い出すこと」の 9 操作 × 12 本について判定した（ReadOnly で使える）。条件の値として `s3:ResourceAccount`・`aws:ResourceAccount`・`aws:PrincipalAccount`＝767397804933、`aws:SecureTransport`＝true を渡した。
  - 値を渡さないと、cdk の deploy-role 4 本が「全 12 本で版の削除ができる」と誤って出た（根拠の文は `StringNotEquals s3:ResourceAccount` で、自アカウント以外のバケット向け）。渡した後は 4 本とも拒否。
  - 対象の操作を条件付きで許す Allow は、ほかに `AdministratorAccess-Amplify`（`aws:CalledVia` が CloudFormation のとき）だけ。`jadd_studio_amplify` は別に `AmazonS3FullAccess` を持つので結果は変わらない。
- **プレフィックスで絞った許可**は、シミュレーターに `バケット/x` を渡しただけでは当たらない（LidarDeleter の `*/lidar/*` を一度取りこぼした）。全ポリシーの Allow を静的に走査して 28 件を拾い、実際のキーの形でシミュレーターでも確かめた（17 通り、すべて許可）。
- **アカウントの外の主体**: 6 本のバケットポリシーは、他アカウントへの読み取り（`Get*`・`List*`・`GetObject` 等）の許可だけ。ACL は 12 本とも無効（`BucketOwnerEnforced`）。アクセスポイントは無い。**外から壊せる経路は無い。**
- **反映していないもの**: SCP（シミュレーターは見ない。組織の SCP は親の調査書の範囲）、root、SSO の権限セットに誰が割り当てられているか。

### 分類

| 分類 | 主体 | 数 |
|---|---|---|
| **A. 全 12 本で守りを外せる**（バージョニングの停止・ライフサイクル・ポリシー・バケット削除・版の削除） | 管理系: Control Tower の 2 本、StackSets の exec、cdk の cfn-exec-role 4 本、CodeCatalyst、SSO の AWSAdministratorAccess・FullAccess<br>`AmazonS3FullAccess`: SSO の TeamE2E、ecsTaskExecutionRole、EMR Studio、tuscenes-sampler-test、sfn-auto-labeling、skypilot-v1、tuscenes-processing、IAM ユーザー 4（jadd-datasync・jadd-remote-sync-kohei.watanabe・jadd_studio_amplify・shio-secretsmanager_GetSecretValue） | 21 |
| **B. 一部のバケットで守りを外せる** | IAM ユーザー `tokyo30-dataupload-pc-01`（td1-raw・td1-rlog・tuscenes-raw で、ポリシー以外のすべて。バケット削除も） | 1 |
| **C. 版の削除ができる**（守りは外せない） | BackendApi（tuscenes-model）、ModelcoreBuild（tuscenes-model）、ModelConverter 2 本（tuscenes-model の `fullcombo/`・`wam/`）、**DensoNx-ExtractorJobRole（td1-raw）** | 5 |
| **D. ライフサイクルを書き換えられる** | Databricks の `databricks-s3-ingest-*-db_s3_iam` 10 本（各 1 本。削除・上書きも） | 10 |
| E. 削除（削除マーカー）・上書きだけ | Coder 4 本・SSO の JADDViewer・SageMaker 2 本（DataScientist 等で 12 本または 5 本）、SSO の GamingDataCollection・TeamDataPlanning・TeamFundamentalAI、DataSync 5 本、LidarDeleter・S3BatchDeleteLidar、GlueRole（`aws-glue-` を含むキーだけ）、PerceptionDetection 1 本 | 19 |
| F. 上書きだけ | SSO の TeamDrivingSoftware（12 本）、SkypilotApiServer、Train3dGs、RlogDecoder、PerceptionDetection 3 本、IAM ユーザー 3（gaggle-shared-user・gaming-data-collection-uploader・tsukamoto） | 10 |

- バージョニングが入った今、E・F は戻せる（削除マーカー・古い版になる）。課金が続くだけ。**戻せない形で壊せるのは A〜D の 37 主体**。

### 目立つこと（事実）

1. **既存の Deny は部分的。** SSO の FullAccess は td1-raw・tuscenes-raw の `s3:DeleteObject*` を拒否している（版の削除も含む）。TeamE2E は同じ 2 本の `PutObject`・`DeleteObject` だけで、**`DeleteObjectVersion` は拒否していない**。どちらもライフサイクル・バージョニング・ポリシー・バケット削除は拒否していない。ほかの 10 本には Deny が無い。
2. **`tokyo30-dataupload-pc-01`**: 長期のアクセスキー（2024-05-27 作成、**今日も使用**）を持つ IAM ユーザーが、td1-raw・td1-rlog・tuscenes-raw のバケット削除・バージョニングの停止・ライフサイクルの書き換えまでできる。名前からアップロード用の PC。キーが漏れると 3 本を壊せる。
3. **`AmazonS3FullAccess` の IAM ユーザー 4 本**: jadd-datasync（最終 2025-10-11）、jadd-remote-sync-kohei.watanabe（**2025-10-20、ちょうど 1 年前**が最後）、jadd_studio_amplify（2026-10-16。もう 1 本のキーは未使用）、shio-secretsmanager_GetSecretValue（2025-08-07。名前に反して S3 を全部操作できる）。
4. **`DensoNx-ExtractorJobRole` が td1-raw の版を削除できる。** denso-nx の抽出ジョブが自社の原本を消せる理由は不明。cdk-apps で確かめる。
5. **SSO の JADDViewer**（閲覧用に見える名前）が、`DataScientist` で 12 本すべての削除・上書きができる。最終利用は 2026-04-02。
6. **使われていない強い主体**: ecsTaskExecutionRole（2025-03）、EMR Studio（2024-08）、CodeCatalyst（2024-03）、tuscenes-sampler-test（2024-07）、sfn-auto-labeling（2024-10）、tuscenes-processing（2024-07）、cdk の cfn-exec-role の us-east-2（2025-07）。掃除の候補（3 段目、急がない）。
7. **Databricks の 10 本がライフサイクルを書き換えられる。** UC の external location 用の標準のポリシー。親のレビュー 4 の懸念のとおり。

### IAM ユーザーのアクセスキー

| ユーザー | キー | 最終利用 |
|---|---|---|
| tokyo30-dataupload-pc-01 | 1 本（2024-05-27） | 2026-10-20（S3） |
| jadd_studio_amplify | 2 本（2024-11-22・2026-04-06） | 2026-10-16（S3）・未使用 |
| gaggle-shared-user | 1 本（2024-10-21） | 2026-09-24（STS） |
| jadd-remote-sync-kohei.watanabe | 1 本（2025-10-08） | 2025-10-20（S3） |
| jadd-datasync | 1 本（2025-08-04） | 2025-10-11（S3） |
| shio-secretsmanager_GetSecretValue | 1 本（2024-09-11） | 2025-08-07（S3） |
| tsukamoto | 1 本（2025-07-01） | 2025-07-01（S3） |
| gaming-data-collection-uploader | 無し | — |

## 手当ての計画で決めること

洗い出しが済んでから決める。今わかっている論点だけ並べておく。

1. **Deny の範囲**: 上の表のどの操作を、どのバケットで Deny するか。
2. **break-glass の主体**: 誰を Deny から外すか。`aws:PrincipalArn` で外す。外さないと、正当なライフサイクルの変更や、版を指定した削除（間引き・復旧）までできなくなる（親のレビュー 4）。
3. **CI の扱い**: cdk の cfn-exec-role は、バケットポリシー・ライフサイクル・バージョニングを書き換える。Deny から外すか、外すならどう守るか。
4. **書き方**: IaC で管理しているバケットは cdk-apps に書く（手で書くと次の deploy で上書きされる）。手で作ったバケットの扱い（CLI か、import して CDK 管理にするか）。
5. **root の制限**: Control Tower の root 制限を同じ時期に入れるか（手間は小。親のレビュー 3）。
6. **検証**: 適用前に IAM Access Analyzer で構文を検証し、テスト用のバケットで試す（親のレビュー 4）。
7. **LidarDeleter**: 周知か、信頼ポリシーを外すか（兄弟の workstream の「先に済ませること」。#2215 のマージ前に決める）。（2026-10-20 に後回しにした。第二弾の TODO 16）

## 進捗と引き継ぎ

- 2026-10-19: 起票した。親の裁定とレビュー 3・4 から、位置づけ・対象・洗い出すこと・調べ方の案・決めることを書き出した。
- 2026-10-20: 対象のバージョニングがすべて入った（CDK の 8 本は 10-19、CLI の 3 本は 10-20、tuscenes-model は以前から）。
- 2026-10-20: 情報源ごとに、SSO ReadOnly（tuscenes-prod、us-west-2）で取れるかを確かめた。

  | 情報源 | 取れるか | 分かったこと |
  |---|---|---|
  | IAM（`get-account-authorization-details`） | ○ | 取れる |
  | バケットポリシー | ○ | 13 本中 6 本にある（denso-taxi-video・gaming-data-collection（Deny 1 文）・td1-raw・tuscenes-calibration（新）・tuscenes-model・tuscenes-raw）。中身は未読 |
  | CloudTrail の管理イベント（90 日、`lookup-events`） | ○ | 誰がバージョニング・ライフサイクル・ポリシーを変えたかは追える |
  | CloudTrail のデータイベント | **× 記録が無い** | trail は 2 本。`aws-controltower-BaselineCloudTrail` は管理イベントだけ（`DataResources` 空）、`garuda-index-access` は `*/index.json` の `GetObject` だけ |
  | S3 のサーバーアクセスログ | **× 記録が無い** | 13 本とも無効 |
  | IAM Access Analyzer | △ | アナライザーは us-west-2・ap-northeast-1・us-east-1 とも未作成。`validate-policy` は使える |
  | SSO の権限セット | △ | Identity Center のインスタンスは管理アカウント 210332786925 にある。割り当ての中身は cdk-apps `apps/organization-policy` から読む |

  - **「直近 90 日に削除を実際に使ったか」は、今の記録からは分からない。** 洗い出しは「何が許されているか」（IAM とバケットポリシー）で行う。実際の使用を知りたければ、データイベントかアクセスログを先に有効にする必要がある（費用が掛かる。手当ての計画で決める）。
- 2026-10-20: 洗い出しの表を作った（上の「洗い出しの結果」）。66 主体、戻せない形で壊せるのは A〜D の 37 主体。途中で 2 つの誤りを見つけて直した（プレフィックスの許可の取りこぼし、条件の値を渡さないことによる deploy-role の誤判定）。
- **次にやること**:
  1. 表を人がレビューする（とくに「目立つこと」の 2〜5 の扱い）。
  2. 「手当ての計画で決めること」の 1〜3（Deny の範囲・break-glass・CI の扱い）を、A〜D の主体を見ながら案にする。
  3. DensoNx-ExtractorJobRole が td1-raw を消せる理由を cdk-apps で確かめる。
