# 原本バケットの現状: できていることと、誰が何をできるか

- 作成: 2026-10-30 ／ 伊藤（調べと下書きはエージェント）
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)。[requirements.md](requirements.md) の「2. 全体の状態」を、権限の面から掘り下げたもの
- 範囲: tuscenes-prod（767397804933）の原本バケット 12 本。他のアカウントは調べていない
- 根拠: 2026-10-20 の主体の一覧（[principals-2026-10-20.md](../done/s3-bucket-access-control/principals-2026-10-20.md)）に、その後の変更（ステージ 1 のバケットポリシー、IAM ユーザーの削除）を重ね、2026-10-30 に ReadOnly で確かめた（下の「確かめたこと」）

全体設計の議論の出発点として、今の守りと、今だれが何をできるかを並べ、弱点を整理する（6 章）。手段の良し悪しは扱わない。

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
| 気づく | 監査のアプリ `original-bucket-audit`（[cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267)、2026-10-26 deploy） | カナリアのバケットの書き込み系のデータイベントを記録している | 12 本は対象外。**12 本の書き込みの記録は 2026-10-30 に始まった**（[cdk-apps#2387](https://github.com/turingmotors/cdk-apps/pull/2387)、07:18 UTC に deploy）。毎時の報告（PR-A）と、12 本の S3 のイベント・Inventory（PR-B）は保留 |
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
| `databricks-uc-3913775780464502-db_s3_external_cluster-st152026da` | Databricks の Unity Catalog（アカウント 414351767826 の `UCMasterRole`、ExternalId つき）。2026-07-29 に Databricks 側の仕組みが作った（タグ `DatabricksExternalBucket=cluster-storage-usage-reports-…`）。IaC には無い | deploy のロールの引き受け。インラインのポリシーが、自分を引き受けるための `sts:AssumeRole` を `Resource: *` で許している（条件は「主体が自分か UCMasterRole」なので、常に満たされる）。Databricks の権限の境界を付けても、シミュレーターは allowed | 2026-10-30 |
| `AmplifySSRLoggingRole-*`（6 本） | Amplify のサービスだけ。Amplify のアプリは 4 リージョンとも残っていない | deploy のロールの引き受け。AWS 管理のポリシー `AmplifyBackendDeployFullAccess` が、同じアカウントの `cdk-*-deploy-role-*` の引き受けを許している | 2024-12 以前か未使用 |
| tuscenes-prod の root | パスワード有効・MFA なし | バケットポリシーを消せる（AWS の仕様） | CorpIT に削除を依頼中（[aws-root-credentials.md](../aws-root-credentials.md)） |
| 管理アカウントの管理者 | root の一元管理 | `S3UnlockBucketPolicy` でポリシーを消せる。Control Tower のロールにも入れる | — |

FullAccess・AWSAdministratorAccess も deploy のロールを引き受けられるが、もともと 3.1 なので数えていない。

Databricks のロールと Amplify のロールは、2026-10-30 に全 740 主体を判定して見つかった（4 章）。

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
- ポリシーシミュレーターで、10-20 の一覧の 66 主体と、名前に GitHub・Deploy・Admin・SSO を含むロール（計 119）に、deploy のロールの引き受け、cfn-exec-role の `PassRole`・信頼の変更・ポリシーの付与、ロールの作成、スタックの作成・更新を当てた。
- **全主体（ロール 703・ユーザー 37）を手元で判定した**（2026-10-30。`get-account-authorization-details` を 1 回取り、[iam-scan/escalation.py](iam-scan/escalation.py) で判定。結果は [iam-scan/escalation-2026-10-30.json](iam-scan/escalation-2026-10-30.json)）。判定した操作は、deploy のロールの引き受け、cfn-exec という名前のロールの作成、cfn-exec・deploy のロールの信頼の変更、cfn-exec を渡してスタックを作ること、ロール・ユーザーへのポリシーの付与、アクセスキー・ログインの作成、ポリシーの版の作成。引き受けられるロールを辿る乗り継ぎも見た。
  - 条件の無い許可で当たったのは 15 主体で、上のシミュレーターの結果と同じ。ユーザーは 0。乗り継ぎで新しく届く主体は無かった。
  - 条件付きの許可で当たった 16 主体は、条件を読み、シミュレーターでも確かめ直した。**Databricks のロール 1 本と Amplify のログ用のロール 6 本は allowed（3.2 に足した）。** Coder のロール（タグ `coder:provisioned` の付いたロールだけを触れる。該当するロールは無い）、JADDViewer と Coder のワークスペース（SageMaker にだけロールを渡せる）、SSM の Quick Setup（決まったポリシーだけを付けられる）は、届かない。
- **SCP の効き方（2026-10-30、cdk-apps の main の `apps/organization-policy/lib/iam-guardrails.ts` を読んだ）:**
  - リポジトリで管理している SCP のうち、tuscenes-prod に付くのは `iam-guardrails` の 1 本だけ。RCP は無い。中身は、IAM ユーザーの作成、SSO の SAML provider の変更、SSO のロールのパス（`/aws-reserved/`）でのロールの作成・削除と信頼の変更、中央管理のロール（`/central/`）とその OIDC provider・EKS の access entry の変更の Deny。どれも `AWSControlTowerExecution`（一部は StackSets の実行ロールも）を例外にしている。
  - **S3 と、`cdk-hnb659fds-*` のロールには何も効かない。** 3.2 の経路は、どれも SCP では止まらない。効いているのは、SSO の例外のロールを偽装させないこと（3.1 の前提）と、IAM ユーザーの裏口を新しく作らせないこと。
  - Control Tower のロールと StackSets の実行ロールの名前を偽装できないのは、OU に付いた Control Tower のガードレール（GRIAMROLEPOLICY）に頼っている（コードのコメントによる。このガードレールはリポジトリの外で、確かめていない）。
  - SCP は、外から引き受けられたロール（Databricks のロールなど）にも効く。管理アカウントの主体と service-linked role には効かない。2 枚目の守り（TODO 24）で 3.2 の経路を止めるなら、Databricks と Amplify のロールも対象に含められる。
  - SCP が実際に付いているかは、管理アカウントの権限が要るので確かめていない。
- 証跡: Control Tower の証跡（全リージョン、管理イベントすべて）と、監査のアプリの証跡（カナリアのデータイベントだけ）。

## 5. 見えていないこと

- Control Tower のガードレール（GRIAMROLEPOLICY）の中身と、SCP が実際に付いているか（管理アカウントの権限が要る）。
- SSO の割り当てのうち、管理画面で直接したもの（`JADDViewer` など）。確かめるには管理アカウントの権限が要る。
- cdk-apps の `main` にマージできる人（GitHub のブランチの保護とレビューの必須の設定）。
- 他のアカウント（amman-pipeline・e2e-dev・biz-dev）の同じ集計。

## 6. 今の構成の弱点（2026-10-30）

2〜5 章から、データが消えうる・消えても気づけない・戻せない点を挙げる。「脅威」の列は、どの想定で効くか（誤操作・乗っ取られた主体・内部の悪意）。

### 6.1 止める

| # | 弱点 | 脅威 |
|---|---|---|
| W1 | **例外の 14 名は、ふだんの権限のまま、確認も通知も無しに、古い版を消せる・守りを外せる。** 誤操作が 1 回で通る。MFA は Okta の設定次第で、今の設定は確かめていない | 誤操作・乗っ取り・悪意 |
| W2 | **cdk-apps の `main` へのマージで、12 本の守りを外せる。** deploy のロールはアカウントに 1 組で、どのアプリの PR からでも 12 本のライフサイクル・ポリシーを変えられる。ライフサイクルに「古い版を失効させる」規則を書けば、レビューを通ったふつうの PR で大量に消える。承認は 1 名（CODEOWNERS。既定は MLOps 1・3、アプリによっては企画 1 も） | 誤操作・悪意 |
| W3 | **承認なしでマージできる GitHub App がある。** ルールセット `main-image-digest-auto-merge` が、App `cdk-apps-auto-merge` に PR での迂回を許している。2026-10-30 に確かめた: 権限はマージだけ、認証情報は `main` からしか使えない environment に置かれ、イメージの digest の更新の workflow だけが使う。おそれは小さいが、鍵が漏れれば開いている PR を承認なしでマージできる。**あわせて、`main` のルールは承認のあとの push に承認し直しを求めない**（作者が承認後に変更を足してマージできる） | 乗っ取り・誤操作 |
| W4 | **deploy のロールの信頼がアカウント全体（`767397804933:root`）。** 引き受ける権限を持つ主体はだれでも入れる。Control Tower の 2 本・StackSets・使われていない CodeCatalyst のロールに加え、**Databricks の Unity Catalog のロール（外の Databricks のアカウントから入る）と、残りものの Amplify のログ用のロール 6 本**が該当する（2026-10-30 に全主体を判定）。`cdk-hnb659fds-*` を守る SCP は無い（TODO 24） | 乗っ取り |
| W5 | **アカウントの外から外せる。** root（パスワード有効・MFA なし。CorpIT に削除を依頼中）と、管理アカウントの管理者 | 乗っ取り・悪意 |
| W6 | **守りは同じアカウントの中の 1 枚だけ。** 例外の主体が外せば、その後は何でもできる。組織の層（SCP・RCP）の 2 枚目は無い | 乗っ取り・悪意 |
| W7 | **ふつうの削除・上書きができる主体が多い（55）。** 戻せるが、量が多いと W12 になる。使われていない強いロールと、長期キーの IAM ユーザー（4 本）が残っていて、乗っ取りの入口になる | 誤操作・乗っ取り |

### 6.2 気づく

| # | 弱点 | 脅威 |
|---|---|---|
| W8 | **だれにも通知されない。** 12 本の書き込みの記録は 2026-10-30 に始まった（[cdk-apps#2387](https://github.com/turingmotors/cdk-apps/pull/2387)）が、後から調べられるようになっただけ | すべて |
| W9 | **守りの変更（ポリシー・ライフサイクル・バージョニング）を、だれも見ていない。** 管理イベントは Control Tower の証跡に残るが、置き場所はログのアカウント（617808723336）で、読めるかも確かめていない。tuscenes-prod の中で引けるのは 90 日分のイベント履歴だけ | すべて |
| W10 | **ライフサイクルで消えたものは、どこにも記録されない。** CloudTrail に出ず、S3 のイベントはカナリアだけ。W2 の経路で消されると、後から調べても「何が消えたか」が分からない | 誤操作・悪意 |
| W11 | **記録そのものを消せる。** ログのバケットは古い版を 1 日で消す設定で、例外の主体なら中身も消せる（監査ログの問題として分けて扱う） | 悪意 |

### 6.3 戻す

| # | 弱点 | 脅威 |
|---|---|---|
| W12 | **大量のふつうの削除から戻す手順と道具が無い。** 削除マーカーを消して戻すには古い版の削除の権限が要り、できるのは例外の主体だけ。td1-raw・tuscenes-raw では FullAccess もできず、AWSAdministratorAccess の 1 名だけ（古い版を上にコピーし直す方法なら、例外でなくても戻せる）。何百万件を戻す Batch Operations の手順も無い | 誤操作 |
| W13 | **写しが無い。** 頼りは同じアカウント・同じリージョンの、同じバケットの古い版だけ。古い版が消されたら戻せない。アカウントの閉鎖・乗っ取り・リージョンの障害には無力 | すべて |

### 6.4 遅らせる・判断・対象

| # | 弱点 | 脅威 |
|---|---|---|
| W14 | **猶予が無い。** 古い版の削除はその場で効く。ライフサイクルは実行まで 1〜2 日かかるが、気づく仕組みが無いので猶予にならない | すべて |
| W15 | **消す判断の手続きと記録が無い**（要件 2）。だれが判断し、何を残すかが決まっていない | 誤操作 |
| W16 | **対象の台帳が無い。** 12 本の一覧が 5 か所（datalake・denso-taxi・denso-nx・gaming-data-collection と監査のアプリ）に散らばる。新しいバケットは自動では守られない | 誤操作 |

### 6.5 とくに効くもの

- **W2＋W10＋W8:** レビューを通った cdk-apps の PR 1 本で、ライフサイクルから 12 本の古い版を大量に消せ、何が消えたかも残らず、だれも気づかない。誤操作でも起こりうる。今の構成で一番大きい穴。
- **W1＋W8:** 例外の 14 名の誤操作が、その場で取り返しのつかない形で通り、気づかれない。
- **W13:** ほかの守りがすべて外れたときの最後の網が無い。

### 6.6 脅威の範囲（問い b）との関係

| 想定 | 効く弱点 | 今の層で足りるか |
|---|---|---|
| 誤操作だけ | W1・W2・W7・W8・W10・W12・W14〜16 | 足りない。とくに W2（ふつうの PR で消える）と W8（気づかない）。ただし、どれも同じアカウントの中で手当てできる |
| 乗っ取られた主体も含む | 上に加えて W3〜W6・W13 | 足りない。アカウントの中の守りは、強い主体を乗っ取られると外される。組織の層か、外せない鍵（WORM）か、別の場所への写しが要る |
| 内部の悪意も含む | すべて（W11 を含む） | 足りない。例外の主体自身が相手なので、判断の手続き・記録の守り・外せない層が要る |

