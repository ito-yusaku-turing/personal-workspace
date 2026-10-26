# 原本バケットのバージョニング（cdk-apps の準備）

- 開始: 2026-10-19
- **完了（2026-10-20）**: 第一弾として完結。残りの TODO は [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md) に引き継いだ
- 状態: **cdk-apps の 4 本の PR はすべてマージ・deploy 済み（2026-10-19）**。DataSync は 2026-10-20 に確かめた（認証は通った。送り元が 0 件なので中身の転送は未確認）。deploy の workflow の `paths` の修正（[cdk-apps#2231](https://github.com/turingmotors/cdk-apps/pull/2231)）は第二弾の TODO 18 に移した
- 所属: project:aws-data-protection（作業先は cdk-apps だが、cdk-apps に workstream の置き場が無いためこちらに置く。2026-10-26 に `~/docs/workstream/` から移した）
- 親: [走行データ消失リスクへの対応](raw-data-security.md)（種別 S1〜S10 と処遇はそちらが正本）
- 用語: S3 の Versioning は「バージョニング」と書く。旧版を指すときは「古い版」

## 目的

親 workstream で「バージョニングを行う」とした原本のバケットのうち、**CDK で管理しているもの**に、cdk-apps の PR でバージョニングと古い版の失効を入れる（2026-10-19 に改めた: 古い版は失効させない。下の「決まったこと」）。手で ON にすると、ライフサイクルを次の deploy で上書きされるため、テンプレートに書く（親 workstream の「管理元ごとの入れ方」）。

手動で作ったバケット（AWS CLI で入れる分）は、この workstream の範囲外。

## 対象（仮決め、2026-10-19）

親 workstream の処遇から、チームで却下された **denso-nx-sample を除いた**もの。

### cdk-apps で入れる（この workstream）

cdk-apps の main（`3567cdea`、2026-10-19）で確かめた。

| バケット | 種別 | アプリ / スタック | 構成 ID（ファイル） | 今のテンプレート | 変えること |
|---|---|---|---|---|---|
| td1-raw | S1 | datalake | `RawBucket`（`apps/datalake/lib/datalake-stack.ts`） | `versioned` 無し。ライフサイクルは IT への移行だけ | `versioned: true` と古い版の失効を足す |
| tuscenes-raw | S1 | datalake | `TuscenesRawBucket`（同上） | 同上 | 同上 |
| tuscenes-calibration（新） | S1 | datalake | `TuscenesCalibrationBucket`（同上） | **`versioned` 無し。ただし実バケットは有効**（テンプレートと実物がずれている） | `versioned: true` を書いて実物に合わせ、古い版の失効を足す |
| gaming-data-collection | S1 | gaming-data-collection | `Bucket`（`apps/gaming-data-collection/lib/gaming-data-collection-stack.ts`） | `versioned` 無し。IT への移行と、未完了のマルチパートを 7 日で中止 | `versioned: true` と古い版の失効を足す |
| denso-taxi-video | S2 | denso-taxi | `DensoTaxiVideoBucket`（`apps/denso-taxi/lib/denso-taxi-stack.ts`） | `versioned` 無し。ライフサイクルは共有の定数 `intelligentTieringLifecycle` | 同上。**共有の定数は直さず**、このバケットだけの規則にする |
| denso-taxi-processed | S2 | denso-taxi | `DensoTaxiProcessedBucket`（同上） | `versioned` 無し | `versioned: true` を足す（2026-10-19、[cdk-apps#2216](https://github.com/turingmotors/cdk-apps/pull/2216) のレビューで作り直せないと分かり追加） |
| denso-nx-raw | S2 | denso-nx | `DensoNxBucket`（`apps/denso-nx/lib/denso-nx-stack.ts`） | 同上（定数を processed・sample と共有） | 同上 |
| tuscenes-annotation | S4 | datalake | `TuscenesAnnotationBucket`（`apps/datalake/lib/datalake-stack.ts`） | `versioned` 無し。ライフサイクルは IT への移行だけ | `versioned: true` と古い版の失効を足す |

- 共有の定数 `intelligentTieringLifecycle`（denso-nx・denso-taxi）は、対象外のバケット（denso-nx-processed、denso-nx-sample、denso-taxi-processed）も使っている。定数に失効を足すと、それらにも規則が入る（バージョニングが無いので実害は無いが、意図が読めなくなる）。
- **前例**: tuscenes-model（`TuscenesModelBucket`、同じファイル）が `versioned: true` を持つ。ただし古い版の失効は無い。tuscenes-dataset（`TuscenesDatasetBucket`）は、`noncurrentVersionExpiration` をプレフィックスごとに使っている。

### 範囲外（AWS CLI で入れる。手順書は別に書く）

| バケット | 種別 | 理由 |
|---|---|---|
| td1-rlog | S1 | 手動で作ったもの |
| tuscenes-calibration（旧、接尾辞なし） | S1 | 同上 |
| denso-raw | S2 | 同上 |
| ~~tuscenes-basicai-datasets~~ | S4 | **今回の手当てから外した（2026-10-19、中身と経緯がよく分からないため）。** cdk-apps に定義が無い。**ただし CloudFormation のスタック `tuscenes`（2024-03-11 作成、最終更新 2025-05-23、リソース 45 個・バケット 5 本）の管理下にある**（論理 ID `BasicaiDatasetsBucket684C0359`）。スタックのコードは cdk-apps にも mono-e2e にも見当たらない。CLI で変えるとこのスタックのドリフトになる |

### 対象外

- tuscenes-model（S3）: バージョニングは導入済み。
- denso-nx-sample（S2）: 2026-10-19 にチームで却下された。

## 変更の形（案）

```ts
versioned: true,
lifecycleRules: [
  {
    enabled: true,
    transitions: [
      {
        storageClass: s3.StorageClass.INTELLIGENT_TIERING,
        transitionAfter: cdk.Duration.days(0),
      },
    ],
    // 消された・上書きされたデータは古い版として残る。N 日で失効させ、課金を頭打ちにする。
    noncurrentVersionExpiration: cdk.Duration.days(90),
  },
],
```

- ~~失効は 90 日~~ → 失効させない（2026-10-19）。上の案から `noncurrentVersionExpiration` を除いた形になった。
- 変更は、CloudFormation の `VersioningConfiguration` と `LifecycleConfiguration` の更新だけになるはず。**バケットの置き換え（replacement）が起きないこと**を `cdk diff` で確かめる。
- 既存のオブジェクトは null 版として残り、費用は変わらない（親 workstream の「裁定の前提にした仕様」）。

## デプロイの経路

| アプリ | 経路 | 注意 |
|---|---|---|
| datalake | main への push で `datalake-deploy.yml`（本番）と `datalake-deploy-dev.yml`（e2e-dev、471112873671）が両方走る。PR では `datalake-diff.yml` | **dev アカウントの同名バケット（td1-raw-471112873671 など）にも同時に入る** |
| denso-nx | main への push で `denso-nx-deploy.yml`。PR では `denso-nx-diff.yml` | |
| denso-taxi | main への push で `denso-taxi-deploy.yml` | diff の workflow は無い |
| gaming-data-collection | **deploy の workflow が無い** | 手元からの deploy は原則禁止で、workflow に一本化する方針（2026-10-19）。deploy と diff の workflow を足す |

## 決まったこと（2026-10-19）

1. ~~古い版は 90 日で失効させる。~~ → **古い版は失効させない**（2026-10-19、[cdk-apps#2211](https://github.com/turingmotors/cdk-apps/pull/2211) のレビューの指摘。理由は親 workstream の進捗）。
2. **PR はアプリごとに分ける**（datalake / denso-nx / denso-taxi / gaming-data-collection）。
3. **dev アカウントには入れない方針**（下の「dev アカウントの扱い」で慣習を確かめた。書き方は PR で決める）。
4. **gaming-data-collection を最初に行う。** 当初は手動で作ったものとして `cdk import` で CDK 管理にする予定だったが、調べるとすでに CDK 管理だった（下の「gaming-data-collection」）。

### 進める順番

| 順 | アプリ | やること |
|---|---|---|
| 1 | gaming-data-collection | バージョニングを足して、手で deploy する（下の「gaming-data-collection」） |
| 2 | datalake | td1-raw・tuscenes-raw・tuscenes-calibration（新）・tuscenes-annotation |
| 3 | denso-taxi | denso-taxi-video |
| 4 | denso-nx | denso-nx-raw |

## dev アカウントの扱い（2026-10-19 に確かめた）

dev に deploy されるのは **datalake だけ**（`datalake-deploy-dev.yml`、e2e-dev 471112873671）。denso-nx・denso-taxi の deploy 先は本番（767397804933）だけ。

明文化された運用ルールは見当たらなかった。慣習として分かったのは次のとおり。

- **テンプレートは全アカウント共通で、本番だけの差は props で分ける。**
  - `bin/datalake.ts` で `isProd`（`account === "767397804933"`）を計算し、Feature Cache の読み取り権限などを本番だけに渡している。
  - [cdk-apps#2031](https://github.com/turingmotors/cdk-apps/pull/2031)（2026-09-30）では、本番にしか無いバケットのポリシー（`OpenmaptilesBucketPolicy`）を `prodAccountIds.includes(currentAccountId)` のときだけ作るようにした。dev / GENIAC で作られないことのテストも足している。
- **dev は main に追従させる。** [cdk-apps#2031](https://github.com/turingmotors/cdk-apps/pull/2031) で、main への push で dev にも自動 deploy するようにした。手動だと dev が main から遅れ、未反映の差分が溜まって壊れても気づけないため。
- **バージョニングは、前例では dev にも入れている。** tuscenes-model のバージョニングは [cdk-apps#2031](https://github.com/turingmotors/cdk-apps/pull/2031) で dev にも入った（「prod と同じ設定」）。
- **dev の td1-raw は検証用のバケット。** 車両チームが試験データを上げ、消すこともある（mono-e2e `naga-pipeline/PLAN.md`: 2026-06-30 に試験データ `nx99` が削除された）。バージョニングを入れると、消した試験データが古い版として 90 日残る。（2026-10-19 に改めた: 失効はやめた。dev にはバージョニング自体を入れていない（[cdk-apps#2215](https://github.com/turingmotors/cdk-apps/pull/2215)））

**書き方の案**: [cdk-apps#2031](https://github.com/turingmotors/cdk-apps/pull/2031) と同じく、`versioned` と失効を `prodAccountIds.includes(currentAccountId)` のときだけ有効にする。dev / GENIAC では何も変わらないことをテストで確かめる。tuscenes-model の前例（dev にも入れた）とは逆の判断になるので、PR 本文に理由（dev は検証用で原本ではない）を書く。

## gaming-data-collection（import は不要だった）

**2026-10-19 に読み取り専用で確かめたところ、すでに CloudFormation の管理下にあった。** `cdk import` は要らない。手で `cdk deploy` したもので、deploy の workflow が無いだけだった。

| 確かめたこと | 結果 |
|---|---|
| スタック | us-west-2 の `GamingDataCollectionStack` が `UPDATE_COMPLETE`（作成 2026-05-22、最終更新 2026-06-12） |
| スタックのリソース | `Bucket83908E77`（バケット）、`BucketPolicyE9A3008A`（SSL 以外を拒否）、`Uploader9E18DA9B`（IAM ユーザー）、`UploaderDefaultPolicy3E3749F0`（インラインポリシー）、`CDKMetadata`。コードのリソースが全部入っている |
| デプロイ済みのテンプレートと main | 一致する。[cdk-apps#1285](https://github.com/turingmotors/cdk-apps/pull/1285)（IP 制限の撤廃）も反映済み |
| 実バケットとテンプレート | 一致する。バージョニング無し、ライフサイクルは IT への移行と未完了のマルチパートの 7 日での中止、パブリックアクセスは全部ブロック、SSE-S3、BucketOwnerEnforced |
| テンプレートの外の設定 | S3 イベント通知が SNS トピック `csms-topic-by-path-…` に向いている（作成・削除・ライフサイクルの失効）。テンプレートは通知を持たないので、deploy では変わらない |
| IAM ユーザーのアクセスキー | 発行されていない |
| bootstrap（us-west-2） | `CDKToolkit` は version 29 |

### 手順

1. バージョニングと 90 日の失効を足す PR を出す（`versioned: true`、ライフサイクルの規則に `noncurrentVersionExpiration`）。（2026-10-19 に改めた: 失効は外した。下の「進捗と引き継ぎ」）
2. マージ後に、書き込みの権限で `apps/gaming-data-collection` から `npx cdk deploy` する（クリーンな checkout から）。`cdk diff` が `VersioningConfiguration` と `LifecycleConfiguration` の変更だけであることを先に確かめる。

## 先に済ませること

- **LidarDeleter の信頼ポリシーを外すか、周知する**（親 workstream のレビュー 2）。バージョニングの後に LiDAR の間引きを再開されると、データは消えずに古い版として課金が続く。失効が 90 日なら、約 1.3〜1.6 PiB が 90 日間残る。（2026-10-19 に失効はやめたので、無期限に残る。LidarDeleter の扱いは第二弾の TODO 16）

## 進捗と引き継ぎ

- 2026-10-19: 起票した。cdk-apps の main で、対象 7 本の定義・今のライフサイクル・deploy の経路を確かめた。tuscenes-calibration（新）は、テンプレートに `versioned` が無いのに実バケットは有効だった。
- 2026-10-19: 4 点が決まった（90 日・アプリごと・dev は入れない方針・gaming-data-collection は import して最初に）。dev の慣習と、gaming-data-collection の import できるリソースを調べた。
- 2026-10-19: gaming-data-collection は運用されておらず止まってもよいので、import の手順を 4 段に縮めた。
- 2026-10-19: 読み取り専用で確かめると、gaming-data-collection はすでに CDK 管理（`GamingDataCollectionStack`）で、テンプレートも実物も main と一致していた。import は不要になった。
- 2026-10-19: gaming-data-collection の PR を出した（[cdk-apps#2211](https://github.com/turingmotors/cdk-apps/pull/2211)）。`cdk diff` はバージョニングと古い版の失効の追加だけ。
- 2026-10-19: **手元からの deploy は原則禁止とし、workflow による deploy に一本化する方針**になった。cdk-apps の作法を調べた（下記）。
  - deploy: `.github/workflows/<app>-deploy.yml`（auto-merge の対象は `-deploy-prd.yml`）。main への push で `apps/<app>/**` と workflow 自身が変わったら起動、`workflow_dispatch` も付ける。ロールは `GithubActions-CdkDeployRole9C8BD064-IT9EkYWJ2rUK`（cdk-apps の main からだけ assume できる）。`concurrency` は `cancel-in-progress: false`（途中で止めると CloudFormation が UPDATE_IN_PROGRESS で残る）。失敗時は `./.github/actions/slack-notify`。根拠は cdk-apps の README「対象の app を追加するとき」と `apps/github-actions/README.md`。
  - diff: `.github/workflows/<app>-diff.yml`。PR で `npx cdk diff --no-change-set` を実行して結果をコメントする。ロールは `cdk-apps-diff-role`（PR から deploy ロールは assume できない）。
  - deploy の workflow が無いアプリは、gaming-data-collection を含めて 14 個ある（bff、cluster-toolkit、coder、gaming-data-collection、gcp-federation、ip-ranges、jadd-cli-auth-callback、jadd-studio、onnx-simplifier、openpilot-scenario-test、orin-cluster、skypilot、terraform-backend、valhalla-sandbox-api）。
- 2026-10-19: [cdk-apps#2211](https://github.com/turingmotors/cdk-apps/pull/2211) に deploy / diff の workflow（`gaming-data-collection-deploy.yml` / `-diff.yml`）を足した。diff の workflow は動き、差分はバージョニングと古い版の失効の追加だけだった。
- 2026-10-19: 残りの 3 本の PR を出した。どれも diff の workflow は通った。
  - [cdk-apps#2215](https://github.com/turingmotors/cdk-apps/pull/2215)（datalake）: td1-raw・tuscenes-raw・tuscenes-annotation・tuscenes-calibration（新）。`isProdAccount`（`currentAccountId` が `prodAccountIds` に含まれるか）で prod だけに入れ、dev / GENIAC では入らないことをテストした。diff は 4 本の `VersioningConfiguration` と `LifecycleConfiguration` だけ。
  - [cdk-apps#2216](https://github.com/turingmotors/cdk-apps/pull/2216)（denso-taxi）: denso-taxi-video。**denso-taxi に diff の workflow が無かったので `denso-taxi-diff.yml` を足した。** diff は video の 2 項目だけ。
  - [cdk-apps#2217](https://github.com/turingmotors/cdk-apps/pull/2217)（denso-nx）: denso-nx-raw。**`denso-nx-diff` のコメントは、Lambda のバンドルのログが 60,000 文字の上限を埋めて diff の本体が載らない**（既存の問題）。main とブランチを同じ方法で synth して比べ、raw の 2 項目だけが変わることを確かめた。
  - 共有のライフサイクルの定数は直さず、`originalDataLifecycle` を別に作って対象のバケットだけに使った（denso-taxi・denso-nx）。
  - 手元の denso-taxi / denso-nx のテストと synth は、Docker が無いので `CDK_CONTEXT_JSON='{"aws:cdk:bundling-stacks":[]}'` でバンドルを飛ばして動かした。
- 2026-10-19: [cdk-apps#2216](https://github.com/turingmotors/cdk-apps/pull/2216)・[cdk-apps#2217](https://github.com/turingmotors/cdk-apps/pull/2217) の diff の workflow に、先に `cdk synth --quiet` して `cdk diff --app cdk.out` で差分を取る段を入れた（バンドルのログでコメントが埋まる対策）。どちらの PR も本文にレビューの対象として書いた。
  - これで [cdk-apps#2217](https://github.com/turingmotors/cdk-apps/pull/2217) の diff の本体が見えるようになり、**この PR と関係の無い未 deploy の差分が見つかった**。`packages/azure-data-sync` の [cdk-apps#1791](https://github.com/turingmotors/cdk-apps/pull/1791)（2026-08-28、SAS のローテーションのメトリクスを送り元ごとに分ける）が、denso-nx の本番に入っていない。denso-nx の最後の deploy は 2026-08-18 で、`denso-nx-deploy.yml` は `apps/denso-nx/**` でしか起動しないため。[cdk-apps#2217](https://github.com/turingmotors/cdk-apps/pull/2217) をマージすると一緒に deploy され、その途中で SAS のローテーションが 1 回走る（[cdk-apps#1791](https://github.com/turingmotors/cdk-apps/pull/1791) が意図した動き）。[cdk-apps#2217](https://github.com/turingmotors/cdk-apps/pull/2217) の本文に書いた。
  - denso-taxi は 2026-10-19 に deploy されていて、[cdk-apps#2216](https://github.com/turingmotors/cdk-apps/pull/2216) の diff は video の 2 項目だけ。
- 2026-10-19: レビューの指摘を受け、4 本の PR から古い版の失効を外した（[cdk-apps#2211](https://github.com/turingmotors/cdk-apps/pull/2211) `1f6cfa3b`、[cdk-apps#2215](https://github.com/turingmotors/cdk-apps/pull/2215) `c5e5ecde`、[cdk-apps#2216](https://github.com/turingmotors/cdk-apps/pull/2216) `849955e5`、[cdk-apps#2217](https://github.com/turingmotors/cdk-apps/pull/2217) `1a255848`）。denso-taxi・denso-nx の専用のライフサイクルの定数もやめ、共有の定数に戻した。題と本文を書き直した。
- 2026-10-19: [cdk-apps#2211](https://github.com/turingmotors/cdk-apps/pull/2211)・[cdk-apps#2215](https://github.com/turingmotors/cdk-apps/pull/2215) がマージされ、workflow の deploy が成功した（datalake は dev も成功）。ReadOnly で、gaming-data-collection・td1-raw・tuscenes-raw・tuscenes-annotation・tuscenes-calibration（新）のバージョニングが Enabled で、古い版の失効が無いことを確かめた。tuscenes-calibration（新）は実物のライフサイクルが空（テンプレートには IT への移行がある。下調べのときからのずれ）。
- 2026-10-19: [cdk-apps#2216](https://github.com/turingmotors/cdk-apps/pull/2216) のレビュー（graph226）を反映した（`1b3a40d4`）。(1) denso-taxi-processed も作り直せないのでバージョニングを入れた。(2) `denso-taxi-diff` の `paths` に `packages/azure-data-sync/**` を足した。(3) `denso-taxi-diff` に jest の段を足した（バンドルを飛ばす）。diff は video と processed の `VersioningConfiguration` だけ。
- 2026-10-19: [cdk-apps#2217](https://github.com/turingmotors/cdk-apps/pull/2217) を先にマージした（[cdk-apps#1791](https://github.com/turingmotors/cdk-apps/pull/1791) の未 deploy の差分も含めて deploy）。`denso-nx-deploy`（run 39223093994）は成功し、DensoNx スタックは `UPDATE_COMPLETE`（08:33Z）。ReadOnly で確かめた結果:
  - denso-nx-raw のバージョニングは Enabled。
  - deploy の途中で SAS の rotator が `request_type='Update'` で 1 回走り、新しい SAS（2026-10-26 まで有効）を `azure-data-sync/mlops1/sas-token` に書いた。
  - `SasRotationSuccess` の新しい系列（`Source=mlops1data81abaf24/dcorp-inbound`）に 08:29Z の 1 件が入り、`SasRotationFailureAlarm` と `LongRunningAlarm` は OK のまま。
  - 新しい SAS で DataSync が動くかは、次の `azure-mlops1-dcorp-inbound-daily`（2026-10-20 03:00 JST）で確かめる。
- 2026-10-19: [cdk-apps#2216](https://github.com/turingmotors/cdk-apps/pull/2216) のレビューの 3 件に返信した。再レビュー待ち。
- 2026-10-19: [cdk-apps#2216](https://github.com/turingmotors/cdk-apps/pull/2216) が LGTM をもらってマージされた（09:19Z）。`denso-taxi-deploy`（run 39229145292）は成功し、DensoTaxiStack は `UPDATE_COMPLETE`（09:21Z）。denso-taxi-video・denso-taxi-processed のバージョニングは Enabled、古い版の失効は無し。DensoTaxiStack のアラーム 6 本は OK のまま。**これで cdk-apps の 4 本はすべてマージ・deploy 済み。**
- 2026-10-20: ReadOnly（us-west-2）で `azure-mlops1-dcorp-inbound-daily` の 2026-10-20 03:00 JST の実行（SAS のローテーション 10-19 08:29Z の後で最初の実行）を確かめた。`SUCCESS`（Prepare・Transfer・Verify とも成功、エラー無し）。`SasRotationFailureAlarm`・`LongRunningAlarm` は OK のまま。**新しい SAS での認証は通っている**（SAS が無効なら一覧の段で失敗する）。
  - ただし、送り元で一覧に出たファイルは **0 件**（`FilesListed.AtSource`）。10-14 まで 187,810 件 → 10-15・16 は 5,946 件 → **10-17 以降は 0 件**。転送するものが無いので、データの中身が流れることまでは確かめられていない。件数の減少は親の workstream の「裁定が要ること」の 5 で扱う。
- **次にやること**:
  1. ~~2026-10-20 03:00 JST の実行の確認~~ → 済み（上）。
  2. `denso-nx-deploy.yml`・`denso-taxi-deploy.yml` の `paths` に `packages/azure-data-sync/**` を足す PR を出す（`denso-nx-diff.yml` の `paths` も同じく足す）。
     → 2026-10-20 に [cdk-apps#2231](https://github.com/turingmotors/cdk-apps/pull/2231)（`ci/azure-data-sync-deploy-paths`、`29acf072`）を出した。3 本の `paths` に足しただけ。マージすると deploy が 2 本走るが、最後の deploy（[cdk-apps#2217](https://github.com/turingmotors/cdk-apps/pull/2217)・[cdk-apps#2216](https://github.com/turingmotors/cdk-apps/pull/2216)）以降に対象の変更は無く、差分は出ないはず（PR の `denso-nx-diff` も差分なし）。**TODO: 作った人に確認してから進める（それまでレビュー依頼・マージはしない）。**
  3. LidarDeleter の扱いは親の workstream で決める。
