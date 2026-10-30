# 原本バケットの現状: できていることと、誰が何をできるか

- 作成: 2026-10-30 ／ 伊藤（調べと下書きはエージェント）
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)。[requirements.md](requirements.md) の「2. 全体の状態」を、権限の面から掘り下げたもの
- 範囲: tuscenes-prod（767397804933）の原本バケット 12 本。他のアカウントは調べていない
- 根拠: 2026-10-20 の主体の一覧（[principals-2026-10-20.md](../done/s3-bucket-access-control/principals-2026-10-20.md)）に、その後の変更（ステージ 1 のバケットポリシー、IAM ユーザーの削除）を重ね、2026-10-30 に ReadOnly で確かめた（下の「確かめたこと」）

全体設計の議論の出発点として、今の守りと、今だれが何をできるかを並べる。手段の良し悪しは扱わない。

## 1. 要点

- **戻す手段はある。** 12 本ともバージョニングが有効で、古い版を消すライフサイクルも無い。ふつうの削除・上書きは、何年たっても戻せる。
- **止める層は 1 枚。** バケットポリシーの Deny（ステージ 1）で、古い版を直接消せるのは SSO の FullAccess（13 名）と AWSAdministratorAccess（1 名）だけになった。2026-10-20 には 37 主体だった。
- **ただし、例外を名乗れる経路が残る。** CDK の deploy のロールは守りを外す例外で、アカウント内の強い主体はこれを引き受けられる。経路として、cdk-apps の `main` への マージ（GitHub Actions）、Control Tower・StackSets のロール（管理・監査アカウントから入る）、使われていない CodeCatalyst のロール、root、管理アカウントの管理者がある。
- **気づく仕組みは無い。** 削除のデータイベントを記録しているのはカナリアだけ。12 本の削除も、守りの変更も、だれにも通知されない。管理イベントは Control Tower の証跡に残るので、後から調べることはできる。
- **遅らせる手段は無い。** 消す操作はその場で効く（WORM は未導入）。
- **判断の手続きは無い。** 例外の 14 名は、だれの確認も通知も無しに、古い版を消せる。

## 2. できていること（役割ごと）

[requirements.md](requirements.md) の 5 章の役割の枠に当てはめた。

| 役割 | 入っているもの | 効いていること | 足りないこと |
|---|---|---|---|
| 止める | バケットポリシーの Deny（12 本。2026-10-23・26） | 例外以外は、古い版の削除・バケットの削除・Object Lock の設定・守りの変更（バージョニング・ライフサイクル・ポリシー・所有権・ACL）ができない | 例外が広い（3 章）。例外を名乗れる経路が残る（3.2） |
| 止める | SCP `DenyReservedPathRoles`（[cdk-apps#2150](https://github.com/turingmotors/cdk-apps/pull/2150)） | SSO のロール（`/aws-reserved/`）を作ったり信頼を変えたりできないので、SSO の例外を名乗れない | `cdk-hnb659fds-*` のロールは対象外（TODO 24） |
| 止める | 危ない主体の片付け | IAM ユーザー jadd_studio_amplify を削除（2026-10-26）。deploy のロールを名乗れた主体が 1 つ減った | 3.3 の主体は手つかず |
| 遅らせる | なし | — | 消す操作に猶予が無い |
| 気づく | 監査のアプリ `original-bucket-audit`（[cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267)、2026-10-26 deploy） | カナリアのバケットの書き込み系のデータイベントを記録している | 12 本は対象外。毎時の報告（PR-A）と 12 本への拡大（PR-B）は保留 |
| 気づく | Control Tower の証跡（`aws-controltower-BaselineCloudTrail`） | 管理イベント（ポリシー・バージョニング・ライフサイクルの変更、ロールの引き受け）が、ログのアカウント（617808723336）に残る | 通知は無い。データイベント（古い版の削除）は残らない |
| 戻す | バージョニング（12 本。2026-10-20） | ふつうの削除・上書きは戻せる。古い版の失効は設定していない | 古い版ごと消されると戻せない。別の場所への写しは無い |
| 判断と特権の経路 | 例外の主体（FullAccess・AWSAdministratorAccess・deploy の経路） | — | 判断の手続き・記録・通知が無い。BreakGlass は選択肢に戻した |

## 3. 誰が何をできるか（2026-10-30）

強い順に 5 段に分けた。「12」は 12 本すべて。

### 3.1 古い版を直接消せる・守りを直接外せる（バケットポリシーの例外）

| 主体 | 中の人・入り方 | できること | 注 |
|---|---|---|---|
| SSO `FullAccess` | 13 名。Okta のグループ `ORG:Autonomous Driving Group 3 Regular Employees`（Infrastructure Team と担当役員）と `Group 4`（MLOps 1・3 Team と担当役員） | 古い版の削除・守りの変更・バケットの削除（12）。ふつうの削除（10） | td1-raw・tuscenes-raw は、権限セットのインラインの Deny で、ふつうの削除も古い版の削除もできない。ただし守りは外せる |
| SSO `AWSAdministratorAccess` | 1 名（`Engineers`） | すべて（12） | |
| `cdk-hnb659fds-cfn-exec-role-*`（4 リージョン） | CloudFormation だけが引き受ける。中身は deploy の経路（3.2） | 守りの変更（12）。ポリシーから Deny を外した後は、古い版の削除も | ライフサイクルで古い版を失効させれば、CloudFormation から大量に消せる |

人数は cdk-apps・identity のリポジトリから数えた（2026-10-29）。管理画面で直接した割り当ては見えていない。

### 3.2 例外を名乗れる（間接に 3.1 と同じことができる）

deploy のロール（`cdk-hnb659fds-deploy-role-*`）は、アカウント内のだれでも引き受けられる信頼になっている（`767397804933:root`）。引き受ける権限を持つ主体と、cfn-exec-role という名前のロールを作れる・信頼を書き換えられる主体は、守りを外せる。

| 主体 | 入り方 | 経路 | 最終利用 |
|---|---|---|---|
| `GithubActions-CdkDeployRole…` | GitHub Actions。`turingmotors/cdk-apps` の `main` だけ | deploy のロール → cfn-exec-role。**cdk-apps の `main` にマージできる人は、だれでも守りを外す変更を入れられる** | 2026-10-30 |
| `AWSControlTowerExecution` | 管理アカウント（210332786925）の root | deploy のロールの引き受け、IAM のロールの作成・信頼の変更 | 2025-09-12 |
| `aws-controltower-AdministratorExecutionRole` | 監査アカウント（494249021538）のロール | 同上 | — |
| `stacksets-exec-ff6b…` | 管理アカウントの StackSets | 同上 | 2026-02-02 |
| `CodeCatalystWorkflowDevelopmentRole-tuscenes-prod` | CodeCatalyst の space | 同上 | 2024-03-14 |
| tuscenes-prod の root | パスワード有効・MFA なし | バケットポリシーを消せる（AWS の仕様） | CorpIT に削除を依頼中（[aws-root-credentials.md](../aws-root-credentials.md)） |
| 管理アカウントの管理者 | root の一元管理 | `S3UnlockBucketPolicy` でポリシーを消せる。Control Tower のロールにも入れる | — |

FullAccess・AWSAdministratorAccess も deploy のロールを引き受けられるが、もともと 3.1 なので数えていない。

`tuscenes-cicd-GithubActionsRole…`（tuscenes-* と alphaspp-* のリポジトリ、最終利用 2026-03-27）は、cfn-exec-role を渡す権限（`iam:PassRole`）だけを持つ。CloudFormation のスタックを作る権限は無いので、これだけでは守りを外せないとみている（確かめていない）。

### 3.3 ふつうの削除・上書きができる（バージョニングで戻せる）

45 主体。古い版は消せないので、消されても戻せる。ただし削除マーカーと古い版の分の課金が続く。

| 種類 | 主体 | 範囲 |
|---|---|---|
| SSO の権限セット | `TeamE2E`（Group 1 の正社員・企画 1 課）、`JADDViewer`（割り当てはリポジトリに無い） | 10〜12 |
| | `TeamFundamentalAI`（tuscenes-model）、`TeamDataPlanning`（calibration（新））、`GamingDataCollection` | 1 本ずつ |
| 使われていない強いロール（最終利用が 1 年以上前） | ecsTaskExecutionRole、AmazonEMRStudio_RuntimeRole、tuscenes-sampler-test、sfn-auto-labeling、tuscenes-processing、SageMaker の 2 本、GlueRole（プレフィックス限定） | 5〜12 |
| 使っている強いロール | skypilot-v1（2026-08）、Coder のロール 4 本 | 12 |
| IAM ユーザー（長期キー） | jadd-datasync、jadd-remote-sync-kohei.watanabe、shio-secretsmanager_GetSecretValue（3 本とも `AmazonS3FullAccess`）、tokyo30-dataupload-pc-01 | 3〜12 |
| アプリ | backend-api・modelcore-build・model-converter 2 本・denso-nx の抽出（`grantReadWrite`）、PerceptionDetection の batch | 1 本ずつ |
| データの取り込み | Databricks のロール 10 本（各 1 本）、Azure からの DataSync のロール 5 本（denso） | 1 本ずつ |
| 消すためのロール | LidarDeleter（FullAccess から引き受ける）、S3BatchDeleteLidar | td1-raw・tuscenes-raw の `*/lidar/*` |

2026-10-20 に「古い版の削除・守りの変更ができる」だった 37 主体のうち、例外の 6、3.2 の 4、削除した jadd_studio_amplify を除く 26 主体が、ステージ 1 でここまで下がった。

### 3.4 上書きだけ（戻せる）

10 主体。SSO の `TeamDrivingSoftware`（Group 2 の正社員、12 本）、SkypilotApiServer（5 本）、Datalake の RlogDecoder、PerceptionDetection の 3 本、Train3dGs、IAM ユーザー 3 本（gaggle-shared-user・gaming-data-collection-uploader・tsukamoto）。

### 3.5 ほかのアカウントからの読み取りだけ

6 本のバケットポリシーが、ほかのアカウントに読み取り（`Get*`・`List*` など）を許している。書き込み・削除を許す文は無い。ACL は 12 本とも無効。

| バケット | 読めるアカウント |
|---|---|
| td1-raw | 994354357515（feature-cache-job-role）、471112873671、505728817009 の devin-investigator ほか |
| tuscenes-raw・tuscenes-model・tuscenes-calibration（新） | 471112873671、586794486929。tuscenes-model は加えて 582491218614（Jetson の OTA）と 994354357515 |
| denso-taxi-video | 471112873671、994354357515 |

## 4. 確かめたこと（2026-10-30、ReadOnly）

- 12 本ともバージョニングは `Enabled`、Object Lock は未設定。
- 12 本とも `DenyIrreversibleDelete`・`DenyProtectionRemoval` が入っていて、操作と例外は [statements.json](bucket-policy/statements.json) と一致する。
- IAM ユーザーは 37（2026-10-20 は 38。jadd_studio_amplify の削除）。
- deploy のロール 4 本の信頼は `767397804933:root`。cfn-exec-role 4 本の信頼は CloudFormation だけ。
- `GithubActions-CdkDeployRole…` の信頼は `repo:turingmotors/cdk-apps:ref:refs/heads/main` だけ。
- ポリシーシミュレーターで、10-20 の一覧の 66 主体と、名前に GitHub・Deploy・Admin・SSO を含むロール（計 119）に、deploy のロールの引き受け、cfn-exec-role の `PassRole`・信頼の変更・ポリシーの付与、ロールの作成、スタックの作成・更新を当てた。結果が 3.2 の表。
- 証跡: Control Tower の証跡（全リージョン、管理イベントすべて）と、監査のアプリの証跡（カナリアのデータイベントだけ）。

## 5. 見えていないこと

- **残りのロール約 620 本は、シミュレーターにかけていない。** S3 を壊す権限は無い（10-20 に確認）が、deploy のロールを引き受けたり、ロールを作ったりできる主体が、3.2 に加わる可能性がある。全部にかけるのは、指示を受けてから行う。
- SCP の効き方（シミュレーターは SCP を見ない）。とくに Control Tower のロールに SCP が効くか。
- SSO の割り当てのうち、管理画面で直接したもの（`JADDViewer` など）。確かめるには管理アカウントの権限が要る。
- cdk-apps の `main` にマージできる人（GitHub のブランチの保護とレビューの必須の設定）。
- 他のアカウント（amman-pipeline・e2e-dev・biz-dev）の同じ集計。
