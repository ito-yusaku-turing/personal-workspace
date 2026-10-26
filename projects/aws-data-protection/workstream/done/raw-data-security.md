# 走行データ消失リスクへの対応（バケットの価値の見積もり）

- 開始: 2026-10-15
- **完了（2026-10-20）**: 第一弾として完結。残りの TODO は [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md) に引き継いだ
- 状態: **原本のバージョニングは入れ終えた（2026-10-20）**。対象の 12 本すべてで有効（CDK の分は [s3-versioning-cdk.md](s3-versioning-cdk.md)）。次の段のアクセスの洗い出しは [s3-bucket-access-control.md](s3-bucket-access-control.md) で済ませ、バケットポリシーと残りの TODO は第二弾に移した
- 用語: S3 の Versioning は「バージョニング」と書く（2026-10-19 に「版管理」から統一）。旧版を指すときは「古い版」
- 所属: project:aws-data-protection（2026-10-26 に `~/docs/workstream/` から移した）
- 関連: [走行データ消失リスク調査（2026-10）](../../documents/raw-data-security.md)（安本さんの調査。本資料の G 番号はそちらの所見 ID）

## 背景

- 安本さんの調査によると、原本約 3,667 TB の 99.5% にバージョニング・Object Lock・レプリケーション・バックアップのどれも無い。1 操作で戻せない形で消せる経路が 12 本あり、削除は記録も検知もされない。
- 調査書の対策（4 本柱と 1〜3 か月の項目）は数が多すぎて、一度には着手できない。
- そこで、**どのバケットから守るか**を裁定するために、まずバケットごとの価値を見積もる。

## 決まったこと

- 価値は **PUT と GET の両方**で見積もる。外部から買ったデータは PUT が古くても使われていることがあるため、PUT だけでは取りこぼす。
- 見る期間は**半年〜1 年**。
- **1 年以上アクセスの無いバケットは、対応を後回しにしてよい。**
- 裁定の前に、得られた情報をバケットごとに取りまとめる（下の「バケットごとの情報」）。
- 進め方は、**やると決めたことを順番に**。古い版を何日残すかなどの細部は、その段になってから改めて決める。

## 裁定（2026-10-15）

| 段階 | やること | 対象 | 時期 |
|---|---|---|---|
| いますぐやる | **バージョニングを始める** | リストアップしたバケット全部 | すぐ |
| 次にやる | **バケットポリシーを設計して設定する**。レビューと現状調査をしっかりやってから | 対象のバケット全部 | 今週〜来週中 |
| 焦らずじっくりやる | **削除権限を持つ主体の洗い出しと掃除** | — | 期限なし |

- **LiDAR の間引きはまだやらない。** 具体的な間引きの方法は別に検討する。
- 調査書の SCP の案は、この裁定ではバケットポリシーに置き換えた。

### 裁定案のレビュー（指摘はすべて妥当として採用）

**いますぐやる（バージョニング）について**

1. **古い版を何日残すか（`NoncurrentVersionExpiration`）を決める。** 決めないと、消された・上書きされたデータの課金が無期限に続く。とくに次の 3 か所に注意する。
   - **databricks-workspace-e2e-bucket**: Delta Lake の書き換えや VACUUM で、古い版が毎日 TB 単位で増える。失効を短く（14〜30 日）するのが前提。Databricks がワークスペースのストレージのバージョニングについて何を推奨しているかも確認する。
   - **既存のライフサイクルで Expiration しているプレフィックス**: バージョニングを入れると Expiration は削除マーカーを付けるだけになり、容量が減らなくなる。ON にする前に、各バケットのライフサイクルを確認する。
   - **DataSync を受けるバケット（denso-nx-raw、denso-taxi-video）**: 転送先にバージョニングがあると、余分な版ができうる。タスクの設定（上書き・削除の扱い）を確認する。
   - 初期値の案は、原本 90 日、databricks-workspace-e2e-bucket 14〜30 日。1 週間後に Storage Lens で古い版の容量を見て調整する。**日数はその段で決める。**（2026-10-19 に改めた: 古い版は失効させない。下の「進捗と引き継ぎ」）
2. **LiDAR の間引きが勝手に再開されないようにする。** 間引きは中断中だが、LidarDeleter ロールは FullAccess の 14 名が今も使える（G22）。バージョニングの後に残り（約 1.3〜1.6 PiB）が消されると、月 100 万円前後の課金が続く。最低限、関係者に周知する。ロールの信頼ポリシーを外せば確実に止まる。

**次にやる（バケットポリシー）について**

3. **バケットポリシーで塞げない穴を明記する。**
   - root（経路 10）: アカウントの root は、Deny があってもバケットポリシーを消せる（S3 の仕様）。
   - CloseAccount（経路 11）: アカウントを閉鎖すると、90 日後にデータごと消える。
   - この 2 つは主体の掃除の側で扱う。ただし Control Tower の root 制限（手間は小）は、バケットポリシーと同じ時期に入れる価値がある。
4. **設計の段階で確かめること。**
   - CDK が `AWS::S3::BucketPolicy` を管理しているバケットに手でポリシーを書くと、次の deploy で上書きされる。IaC 管理の 5 本（td1-raw、tuscenes-raw、tuscenes-annotation、denso-taxi-video、denso-nx-raw）は、cdk-apps に書く前提にする。手で ON にしたバージョニングも、後で `versioned: true` として cdk-apps に書き戻す。
   - break-glass の主体を決め、`aws:PrincipalArn` で Deny から外す。外さないと、正当なライフサイクル変更や、版を指定した削除（間引き・復旧）までできなくなる。
   - 直近 90 日に PutBucketLifecycle・PutBucketPolicy・PutBucketVersioning を呼んだ主体を、CloudTrail の管理イベントで洗い出す（Databricks の IAM ロールにもライフサイクルの権限がある）。
   - 適用前に IAM Access Analyzer で構文を検証し、テスト用のバケットで試す。

**範囲について**

5. **「リストアップしたバケット」の範囲を確定する。**
   - 調査書の「バージョニングなし 12 本」のうち、amman-nbox-log-tmp（amman-pipeline）と td1-raw-471112873671（e2e-dev）は tuscenes-prod の外にある。ReadOnly の SSO では作業できないので、作業する人の権限を確かめる。
   - 二次データの turing-video-ap-northeast-1 には、作り直せない commentary-audio が含まれる。対象に含めるかを決める。

**補足**

- 裁定には検知が入っていない。一次バケットの容量が前日比で減ったら鳴るアラームは手間が小さく、バージョニングと組み合わせると「戻せるうちに気づける」。
- 主体の掃除を後回しにしても、バージョニングとバケットポリシーが入れば S3 の削除経路はほぼ塞がる。残るのは root と kento-t（CloseAccount）だけ。

### 裁定の前提にした仕様

**バージョニングの課金**

- バージョニングを有効にすること自体は無料。有効にする前からあるオブジェクトは null 版として残り、費用は変わらない。
- 古い版は、差分ではなく丸ごと 1 オブジェクトとして、そのストレージクラスの単価で課金される。
- **普通に削除する（バージョン ID なし）と削除マーカーが付くだけで、元のデータは古い版として課金され続ける。** 課金が止まるのは、古い版が失効したとき、または版を指定して削除したときだけ。
  - 費用は「消した量 × 失効までの日数」で頭打ちになる。たとえば 100 TB が AIA 層（0.004 ドル/GB・月）にあれば、月 400 ドルを 90 日で約 1,200 ドル。
  - 失効までの日数は、そのまま「気づいて戻すまでの猶予」になる。
- Intelligent-Tiering のバケットでは、古い版も読まれなければ IA、AIA へと下がっていく。監視料は古い版にもかかる。最低保管期間は無い。
- バージョニングは無効化できない。「一時停止」はできるが、すでにある古い版は残る。

**IAM で「削除はできるが版は消せない」にする方法**

- `s3:DeleteObject`（バージョン ID なしの削除。削除マーカーが付くだけ）と `s3:DeleteObjectVersion`（版を指定した削除）は別のアクションなので、分けて許可・拒否できる。Databricks の UC 用ロールは、すでにこの形になっている。
- ただし、次の権限が残っていると同じことができてしまうので、一緒に Deny する。
  - `s3:PutLifecycleConfiguration`: 古い版を 1 日で失効させるルールを入れられる
  - `s3:PutBucketVersioning`: バージョニングを一時停止できる
  - `s3:PutBucketPolicy` / `s3:DeleteBucketPolicy`: バケットポリシー側の Deny を外せる
  - `s3:PutBucketObjectLockConfiguration`、`s3:DeleteBucket`
- 今の権限の多くは AdministratorAccess や AmazonS3FullAccess のように全部を Allow したものなので、Allow を絞るだけでは足りず、明示的な Deny が要る。
- 削除マーカーを消して戻す操作にも `s3:DeleteObjectVersion` が要る。復旧と間引きは、break-glass の主体が行う運用になる。

## バージョニングの下調べ（2026-10-16）

ReadOnly の SSO で、AWS CLI から読み取り専用で調べた。設定は何も変えていない。対象は調査書 2.1 のバージョニングなしのうち tuscenes-prod にある 10 本と、候補の turing-video-ap-northeast-1。比較のため、バージョニングが有効な tuscenes-calibration（新）も見た。

### バケットごとの現状

| バケット | 管理元 | バージョニング | ライフサイクル | ポリシー | Inventory |
|---|---|---|---|---|---|
| td1-raw | CDK `Datalake` | 未設定 | IT への移行だけ | 有り（cfn） | 日次・現行版のみ |
| tuscenes-raw | CDK `Datalake` | 未設定 | IT への移行だけ | 有り（cfn） | 週次・現行版のみ |
| tuscenes-annotation | CDK `Datalake` | 未設定 | IT への移行だけ | 無し | 無し |
| denso-taxi-video | CDK `DensoTaxiStack` | 未設定 | IT への移行だけ | 有り（cfn） | 日次・現行版のみ |
| denso-nx-raw | CDK `DensoNx` | 未設定 | IT への移行だけ | 無し | 無し |
| denso-nx-sample | CDK `DensoNx` | 未設定 | IT への移行だけ | 無し | 無し |
| turing-video-ap-northeast-1 | CDK `VideoOrigin`（東京） | 未設定 | `tmp/` を 14 日で Expiration | CloudFront の OAC | 無し |
| databricks-workspace-e2e-bucket | Databricks quickstart の CFn（2024-08-29 に作ってから更新なし） | 未設定 | 無し | 有り（Databricks 用） | 無し |
| td1-rlog | 手動 | 未設定 | IT への移行だけ | 無し | 無し |
| denso-raw | 手動 | 未設定 | `tmp/` の IT 移行だけ | 無し | 無し |
| tuscenes-calibration（旧） | 手動 | 未設定 | IT への移行だけ | 無し | 無し |
| （参考）tuscenes-calibration（新） | CDK `Datalake` | **有効** | 無し（古い版が失効しない） | 有り | 無し |

- 全バケットで Object Lock とレプリケーションは無く、`AbortIncompleteMultipartUpload` の規則も無い。暗号化は SSE-S3（calibration（新）だけ KMS）、所有者は全部 BucketOwnerEnforced。
- 「未設定」は、バージョニングを一度も ON にしたことがない状態（一時停止ではない）。

### レビュー 1 の懸念を確かめた結果

- **既存の Expiration**: 持っているのは turing-video-ap-northeast-1 の `tmp/`（14 日）だけで、今の最上位は `commentary-audio/` と `media/` だけ。`tmp/` は空なので、バージョニングを入れても容量が減らなくなるものは実質ない。他のバケットのライフサイクルは IT への移行だけ。
- **DataSync**:
  - denso-nx-raw 宛ての `azure-mlops1-dcorp-inbound-daily`（毎日 03:00 JST）は、`OverwriteMode=ALWAYS`・`TransferMode=CHANGED`・`PreserveDeletedFiles=PRESERVE`。変わったファイルだけを上書きし、削除はしない。直近 10 回は転送も削除も 0 件なので、**バージョニングを入れても余分な版はほぼできない**。
  - denso-taxi-video 宛ての 2 本（taxi-processed-video は無効、geniac4 はスケジュールなし）は、最後の実行が 2026-09-19 で転送 0 件。
  - **別に気になる事実**: daily タスクがスキップした件数（＝転送元の Azure にあるファイル数）が、10-14 までの 187,810 から、10-15・16 は 5,946 に減り、**10-17 以降は 0 件**（2026-10-20 に確認。`FilesListed.AtSource`）。調査書の「Azure に原本 175.5 TB が残る（G01）」が崩れている可能性がある。
- **Databricks の推奨**: Delta Lake（UC の managed テーブルを含む）を置くバケットでは、バージョニングを**推奨しない**。Delta 自身にバージョニング（time travel）があり、VACUUM で消すファイルが残ってしまうため。入れるなら「古い版は 3 つまで・7 日以内」のライフサイクルにすることを勧めている。バージョニングによる S3 API の遅延も KB にある。
  - 出典: [Delta Lake limitations on S3](https://docs.databricks.com/aws/delta/s3-limitations)、[KB: Slow S3 API responses](https://kb.databricks.com/delta/slow-s3-api-responses-when-using-delta-lake-with-versioning-enabled-s3-buckets)
  - **裁定案の初期値 14〜30 日とは食い違う。**
- **古い版の増え方の見積もり**（CloudWatch の日次の容量から、前日比の減少を足した。上書きや、同じ日の削除と追加の相殺は見えないので下限）:
  - databricks-workspace-e2e-bucket: 直近 30 日で約 21 TB、90 日で約 45 TB（減った日は 90 日中 37 日）。7 日で失効させても、古い版は常に数 TB ある。
  - 原本の 9 本: 直近 30 日の減少は 0。90 日では tuscenes-raw の約 1,826 TB（08-31〜09-02 の LiDAR 間引き）と td1-raw の約 19 TB（08-28）だけ。**今の運用のままなら、原本の古い版はほぼ増えない。** 費用が増えるのは databricks-workspace-e2e-bucket と、間引きを再開した場合。

### 管理元ごとの入れ方

- **CDK 管理の 7 本は、cdk-apps の PR で入れる**（`versioned: true` とライフサイクルに `noncurrentVersionExpiration`）。
  - これらのライフサイクルはテンプレートで管理しているので、**古い版の失効を手で足すと、次の deploy で消える**。
  - バージョニングそのものはテンプレートに無いので、手で ON にしても、CloudFormation は差分の無いプロパティを触らず、戻らないと考えられる。ただ、失効と一緒に入れるなら PR 1 本の方が素直。
  - 前例は tuscenes-model（`datalake-stack.ts` の Model Bucket のコメント。import 済みのバケットに `versioned: true` を足して deploy した）。
- **databricks-workspace-e2e-bucket は CLI で入れる**。2024-08 から更新の無い quickstart の CFn で、ライフサイクルも持っていない。
- **手動の 3 本（td1-rlog、denso-raw、tuscenes-calibration（旧））は CLI で入れる**。`put-bucket-lifecycle-configuration` は全体を置き換えるので、既存の IT 移行の規則も含めて書く。
- **CloudTrail（直近 90 日）**: 対象バケットへの PutBucketLifecycle・PutBucketPolicy・PutBucketVersioning は、すべて cdk の cfn-exec-role から（td1-raw のポリシーが 09-17、denso-taxi-video のポリシーが 10-13）。Databricks のロールや個人による変更は無い。

### LiDAR の間引き（レビュー 2）

- `LidarDeleter`: 信頼先は SSO の FullAccess 権限セット（14 名）。権限は td1-raw・tuscenes-raw の `*/lidar/*` に対する `s3:DeleteObject` だけ。最後に使われたのは 2026-09-03。
- `S3BatchDeleteLidar`（S3 Batch Operations 用）も `s3:DeleteObject` だけ。
- **どちらにも `DeleteObjectVersion` が無い。** バージョニングの後に間引きが再開されると、データは消えずに古い版として課金が続く（月 100 万円前後）。止めるには、LidarDeleter の信頼ポリシーを外す。

### 裁定（2026-10-19）

- **データ収集や他社からの買い取りで得たデータ（原本）は、バージョニングをすぐに入れる。確定。** 対象は td1-raw、tuscenes-raw、denso-taxi-video、denso-nx-raw、denso-nx-sample（2026-10-19 にチームで却下）、tuscenes-annotation、td1-rlog、denso-raw、tuscenes-calibration（旧）。
- **databricks-workspace-e2e-bucket にはバージョニングを入れない（A 案）。** Databricks の公式が、Delta Lake（UC の managed テーブルを含む）を置くバケットでのバージョニングを推奨していないため、それに従う。Databricks 経由の誤操作は、Delta の time travel と `UNDROP`（既定 7 日）で戻す。S3 を直接消されることへの手当ては、バケットポリシー（Databricks のロール以外に削除を禁止する）などで別に考える。この案をチームで議論する。
  - 公式の推奨: バージョニングは ON にしない。ON にするなら古い版は 3 つまで・7 日以内（[Delta Lake limitations on S3](https://docs.databricks.com/aws/delta/s3-limitations)）。managed テーブルのバックアップは Deep Clone（[Disaster recovery](https://docs.databricks.com/aws/en/admin/disaster-recovery)）。
  - 退けた案: バージョニング＋古い版 7 日・3 版（推奨の条件どおり。S3 を直接消されても 7 日は戻せる）。作り直せないテーブルだけを Deep Clone で写す案は、テーブルの洗い出しの後に改めて検討する余地がある。

### 内容の種別と処遇（2026-10-19）

0.1 TB 以上の 47 本を、中身の出どころで 10 種別に分けた。番号は以後この資料で正式に使う。「推定」は名前やコードから推し量ったもの。古い版を何日残すかは、引き続きその段で決める。

| 種別 | 定義 | 処遇 | 理由 |
|---|---|---|---|
| **S1** 自社収集 | 自社の車両・機材で集めた原本 | **バージョニングを行う** | 失えば集め直せない |
| **S2** 他社から受領 | 他社から納品・転送された原本（買い取り・共同研究を問わない） | **バージョニングを行う** | 失えば受け取り直せる保証がない |
| **S3** AI モデル | 学習済みモデルの置き場 | **バージョニングを行う（既に導入済み）** | 作り直すには多大な学習費用がかかる |
| **S4** 外注の成果物 | 費用を払って外部に作らせたもの | **バージョニングを行う** | 失えばもう一度費用がかかる |
| **S5** 公開・外部取得 | 公開データセットや、公開の場から取ったもの | 行わない | 取り直せる |
| **S6** 派生 | S1・S2・S4 から作ったもの | 行わない | 作り直せる |
| **S7** Databricks | Unity Catalog の managed テーブルの実体 | 行わない（A 案。チームで議論する） | 公式の推奨に従う。S3 を直接消されることへの手当ては別に考える |
| **S8** 自社の成果物 | 評価結果・生成物など（AI モデルを除く） | 行わない | 作り直せる |
| **S9** 運用・退避・一時 | バックアップ・一時置き・運用データ | 行わない | 原本ではない |
| **S10** 出所不明 | 手動で作られ、cdk-apps に履歴が無いもの | 行わない | 2026-10-19 の裁定 |

| 種別 | バケット（TB） |
|---|---|
| S1 | td1-raw（1,754）、tuscenes-raw（914）、td1-rlog（21）、gaming-data-collection（3.3、推定: ゲームやシミュレータの操作記録）、tuscenes-calibration（旧 1.3 / 新 ほぼ 0） |
| S2 | denso-taxi-video（452）、denso-nx-raw（171）、denso-raw（15）、denso-nx-sample（5.7）、denso-taxi-processed（1.1、2026-10-19 に S6 から移した） |
| S3 | tuscenes-model（62） |
| S4 | tuscenes-annotation（13.5）、tuscenes-basicai-datasets（2.1） |
| S5 | external-driving-videos（4.2、YouTube）、argoverse2-all（1.1）、nuscenes-all（0.5）、semantic-kitti（0.2）、openmaptiles（0.3） |
| S6 | garuda-dataset（540）、turing-video-training-sync-gcp（335）、turing-video-ap-northeast-1（306）、derived-data（267）、tuscenes-dataset（30）、td1-video-h265-gcp（9.1）、tuscenes-map（1.7）、turing-video-frames（1.3）、train-3dgs-video（0.9）、dataset-for-appen（0.7）、tuscenes-sampled（0.6）、trajectory-visualizer-data（0.3） |
| S7 | databricks-workspace-e2e-bucket（118） |
| S8 | scenario-test-result（15.6）、closed-loop-scenario-test-result（8.4）、wm-data（1.3）、driving-behavior-data（0.7） |
| S9 | cluster-backup（2.4）、datadog-account-level-cost-report（1.3）、tuscenes-tmp（0.7）、s3-inventory-results（0.7）、hyperpod-user-data（0.5）、tuscenes-assets（0.1） |
| S10 | miwa-gmo-2026-0424-archive（24.3）、abemi-gmo-2026-0424-archive（3.7）、alphaspp-raw（0.9）、alphaspp-data（0.4）、dataset-for-third-dimension（0.3）、denso-data（0.2） |

- **S3 の tuscenes-model は、バージョニングを既に導入済み**（cdk-apps `apps/datalake/lib/datalake-stack.ts` の Model Bucket。CDK 外で作られたバケットを `cdk import` で取り込み、`versioned: true` にしてある）。今回の作業は要らない。ライフサイクルは Intelligent-Tiering への移行だけで、**古い版の失効は無い**（古い版は無期限に残る）。次の「バケットポリシー」の段では、S1・S2・S4 と同じく対象に含めるかを改めて決める。
- 2026-10-19 に確定した原本 9 本に対し、**仮決めで足したのは gaming-data-collection（S1）と tuscenes-basicai-datasets（S4）**。
- **tuscenes-basicai-datasets（S4）は、今回の手当てから外した（2026-10-19）。** 中身と経緯がよく分からないため。手で作ったものではなく、コードの見当たらない古いスタック `tuscenes` の管理下にあることも分かった（[s3-versioning-cdk.md](s3-versioning-cdk.md) の「範囲外」）。
- **turing-video-ap-northeast-1 は S6（行わない）とした。** commentary-audio は作り直せる（下記）。
- 次の 3 本は、取り直せない・唯一の写しの可能性があるが、**バージョニングは行わない**と決めた（2026-10-19）: external-driving-videos（S5。YouTube 側で動画が消えると取り直せない）、cluster-backup・hyperpod-user-data（S9。退避先が唯一の写しの可能性がある）。
- S10 はバージョニングを行わないが、持ち主と出所の確認（「調べること」）は残す。
- **denso-nx-sample（S2）は、チームで却下された（2026-10-19）。** バージョニングを行わない。これを除いたものを、手当ての対象として仮決めした。cdk-apps で入れる分の準備は [原本バケットのバージョニング（cdk-apps の準備）](s3-versioning-cdk.md) で進める。

#### commentary-audio の元データ（2026-10-19 に確かめた）

データの流れは次のとおりで、**元データは td1-raw の rlog にある**。

1. 車両の openpilot（`system/micd/`）が、マイクの音声を rlog に記録する。
2. rlog-decoder（cdk-apps `datalake`）が、td1-raw の rlog から `rlog.parquet` を作る。
3. naga-pipeline の Auto Loader が `s3://td1-raw-767397804933` の `rlog.parquet` を `e2e.v2.raw_rlog` に取り込む（mono-e2e `projects/databricks-jobs/naga-pipeline/bundles/turingpilot-collect/databricks.yml` の `rlog_s3_root` の既定値）。音声は `topic IN ('microphoneAudio', 'microphone')` の `data` 列に hex で入っている。
4. `commentary_audio_convert`（mono-e2e `projects/databricks-jobs/commentary-audio`）が `raw_rlog` から WAV・エンベロープ・`audio_index` を作り、turing-video-ap-northeast-1 の `commentary-audio/` に書く。
5. `commentary_audio_transcribe` が WAV を Amazon Transcribe で文字起こしし、`transcript.json` と `transcript_index` を書く。

- jadd_studio3 の ADR（`docs/features/commentary-driving/adr/0001-audio-source-and-conversion.md`）も「`raw_rlog` に原本が残り続けるため、形式もチャンネル数も後から再変換でやり直せる」としている。
- 作り直すときは、文字起こしに Amazon Transcribe の従量課金がかかる。
- 調査書 2.2 の「commentary-audio は作り直せない」は、この流れと食い違う。

### 裁定が要ること

1. ~~**範囲**: tuscenes-prod の 10 本に、turing-video-ap-northeast-1 を足すか。~~ → 種別で決める（上の「内容の種別と処遇」）。turing-video-ap-northeast-1 は S6 で行わない。
2. ~~**databricks-workspace-e2e-bucket**: バージョニングを入れるか。~~ → 入れない（A 案、2026-10-19）。
3. ~~**原本の古い版の日数**: 90 日でよいか。今は増えないので、日数を延ばしても費用はほぼ変わらない。~~ → 失効させない（2026-10-19。下の「進捗と引き継ぎ」）。
4. **LidarDeleter の信頼ポリシーを外すか**、周知だけにするか。
5. **denso-nx-raw の Azure 側の件数の減少**を、誰に確かめるか。

## 調べ方

いずれも読み取り専用で、設定は何も変えていない。対象は tuscenes-prod（767397804933）の 158 バケット。権限は SSO の ReadOnly。

### CloudWatch（2026-10-15 取得、過去 455 日分の日次値）

| 見たもの | 何が分かるか | 使えた範囲 |
|---|---|---|
| `NumberOfObjects`（AllStorageTypes） | オブジェクト数が最後に増えた日を、**最終 PUT** とみなす | 全バケット |
| `BucketSizeBytes`（ストレージクラス別） | 容量と、Intelligent-Tiering の層ごとの内訳 | 全バケット |
| リクエストメトリクス（`GetRequests` ほか） | **GET の回数そのもの** | 設定のある 7 バケットだけ（td1-raw、garuda-dataset、derived-data、tuscenes-dataset、tuscenes-tmp、tuscenes-img、tuscenes-calibration-test） |

GET の回数が取れない残りのバケットは、**Intelligent-Tiering の層の動き**から GET の有無を推定した。

- Intelligent-Tiering では、30 日読まれないデータは高頻度層（FA）から低頻度層（IA）へ、90 日読まれないと AIA 層へ移る。**読まれると FA に戻る。**
- そこで、「オブジェクト数が増えていない日に、IA・AIA が 10 GB 以上減り、FA がその半分以上増えた日」を**再アクセス**（GET があった日）とみなした。
- 例として tuscenes-raw では、2026-03 に約 380 TB、2026-06 に約 316 TB が FA に戻っていた（GCS 向けの変換バッチと思われる）。

### cdk-apps の履歴（main の HEAD は 2026-10-15 の `78c01206`、全 2,927 コミット）

- `git log --all -S<バケット名>` で、そのバケット名を足した・消したコミットのうち最初と最後を取った。
- HEAD のコード（README・テストを除く）で、そのバケットを参照しているアプリの数を数えた。

## 結果の概要

最終アクセス日は、最終 PUT・最後の再アクセス・最後の GET のうち最も新しい日とした。

| 区分 | 数 | 容量 |
|---|---|---|
| A: 6 か月以内にアクセスあり | 63 | 約 5,036 TB |
| B: 最終アクセスが 6〜12 か月前 | 6 | 約 30 TB |
| C: 1 年以上アクセスなし | 89 | 約 28 TB（うち 80 本は 1 本 0.1 TB 未満） |

## バケットごとの情報（0.1 TB 以上の 47 本）

列の意味:
- **区分**: 上の A / B / C。
- **再アクセス**: Intelligent-Tiering の層の動きから推定した、最後に GET があった日。
- **GET**: リクエストメトリクスがあるバケットだけ。最後に GET があった日と、直近 12 か月の回数。ただし日次値があるのは td1-raw が 2026-03-31 から、garuda-dataset が 04-27 から、derived-data が 08-24 からなので（`cw.json.gz`）、この 3 本は実質で半年分以下の回数（下の補足の「半年で」も同じ数）。
- **層 FA/低頻度**: Intelligent-Tiering の高頻度層と低頻度層（IA と AIA の合計）の容量（TB）。`Std` は Standard クラスなので、層から GET は推定できない。
- **cdk-apps 初出 / 最終**: そのバケット名を足した・消したコミットの最初と最後。
- **参照アプリ**: HEAD で参照しているアプリの数。
- バケット名の `-*` は `-767397804933` を省略したもの。

| バケット | TB | 区分 | 最終 PUT | 再アクセス | GET | 層 FA/低頻度 | cdk-apps 初出 | cdk-apps 最終 | 参照アプリ |
|---|---|---|---|---|---|---|---|---|---|
| td1-raw-* | 1,753.6 | A | 2026-10-13 | 2026-07-11 | 2026-10-15（2,143 百万回） | IT 648/1101 | 2025-01-09 #4 | 2026-10-08 #2092 | 20 |
| tuscenes-raw-* | 913.7 | A | なし | 2026-09-26（一括は 06-24） | — | IT 0/913 | 2024-12-26 `74d0f37b` | 2026-10-08 #2092 | 6 |
| garuda-dataset-* | 540.2 | A | 2026-10-11 | 2026-10-12 | 2026-10-15（9,569 百万回） | IT 312/221 | 2026-03-04 #814 | 2026-10-06 #2047 | 8 |
| denso-taxi-video-* | 452.0 | A | 2026-09-12 | 2026-10-13 | — | IT 433/19 | 2026-07-13 #1486 | 2026-10-13 #2141 | 6 |
| turing-video-training-sync-gcp | 335.3 | A | 2026-09-09 | なし | — | IT 0/335 | 2026-05-26 #1177 | 2026-09-09 `e35fd628` | 1 |
| turing-video-ap-northeast-1-* | 305.9 | A | 2026-10-13 | なし | — | IT 121/185 | 2025-02-19 #88 | 2026-09-16 #1927 | 2 |
| derived-data-* | 266.6 | A | 2026-10-13 | なし | 2026-10-15（40,374 百万回） | IT 261/5 | 2026-07-24 #1548 | 2026-10-06 #2061 | 6 |
| denso-nx-raw-* | 170.9 | A | 2026-10-02 | なし | — | IT 46/125 | 2026-04-10 #948 | 2026-07-24 #1521 | 1 |
| databricks-workspace-e2e-bucket | 118.2 | A | 2026-10-13 | 測れない | — | Std | 2024-12-26 `0018f09b` | 2026-07-13 #1470 | 1 |
| tuscenes-model-* | 62.2 | A | 2026-10-13 | なし | — | IT 4/57 | 2025-01-17 #7 | 2026-10-09 `bef3c6ed` | 15 |
| tuscenes-dataset-* | 29.7 | A | 2026-10-13 | 2026-07-17 | 2026-08-17（361 百万回） | IT 0/30 | 2025-01-17 #7 | 2026-09-30 #2014 | 4 |
| miwa-gmo-2026-0424-archive | 24.3 | A | 2026-04-29 | 測れない | — | Std | 履歴なし | — | 0 |
| td1-rlog | 21.1 | C | 2025-09-08 | なし | — | IT 0/21 | 2024-12-26 `74d0f37b` | 2025-03-27 `c6a41494` | 1 |
| scenario-test-result-* | 15.6 | A | 2026-10-13 | なし | — | IT 1/15 | 2025-05-01 `4e7cb9c6` | 2026-08-24 #1735 | 8 |
| denso-raw-* | 15.2 | B | 2025-12-23 | 2026-04-15（少量） | — | IT 0/15 | 2025-01-22 `87e532cc` | 2026-09-30 #2014 | 0 |
| tuscenes-annotation-* | 13.5 | A | 2026-10-13 | 2026-03-05 | — | IT 1/12 | 2025-01-17 #7 | 2026-09-30 #2014 | 3 |
| td1-video-h265-gcp-* | 9.1 | B | 2026-04-08 | 測れない | — | Std | 2026-04-07 `f5842a54`（main 外） | 同左 | 0 |
| closed-loop-scenario-test-result-* | 8.4 | A | 2026-09-28 | なし | — | IT 0/8 | 2025-12-02 #512 | 2026-07-16 #1513 | 5 |
| denso-nx-sample-* | 5.7 | A | 2026-05-20 | なし | — | IT 0/6 | 2026-05-01 #1033 | 2026-10-13 #2024 | 2 |
| external-driving-videos-* | 4.2 | B | 2026-02-18 | なし | — | IT 0.0/4.2 | 2026-02-04 `4c565bff` | 2026-02-09 `2ad562e8` | 1 |
| abemi-gmo-2026-0424-archive-*-us-west-2-an | 3.7 | A | 2026-10-10 | 測れない | — | Std | 履歴なし | — | 0 |
| gaming-data-collection-* | 3.3 | A | 2026-07-31 | なし | — | IT 0.0/3.3 | 2026-05-25 #1169 | 2026-07-29 `c3d84472` | 3 |
| cluster-backup-* | 2.4 | A | 2026-08-27 | なし | — | IT 0.0/2.4 | 2026-08-03 #1641 | 2026-10-02 #2050 | 2 |
| tuscenes-basicai-datasets-* | 2.1 | C | なし | なし | — | IT 0.0/2.1 | 2025-01-17 #7 | 2025-11-19 `20a04397` | 0 |
| tuscenes-map-* | 1.7 | A | 2026-10-13 | 2026-07-14 | — | IT 0.1/1.5 | 2025-01-17 #7 | 2026-10-15 `26689e00` | 5 |
| wm-data-* | 1.3 | A | 2026-10-12 | なし | — | IT 1.3/0.0 | 2026-09-02 #1840 | 2026-09-09 #1899 | 3 |
| turing-video-frames-* | 1.3 | A | 2026-10-13 | なし | — | IT 0.1/1.0 | 2026-01-15 `ff922a7f` | 2026-01-21 `e04c7dfb` | 1 |
| datadog-account-level-cost-report | 1.3 | A | 2026-10-13 | 測れない | — | Std | 履歴なし | — | 0 |
| tuscenes-calibration（旧、接尾辞なし） | 1.3 | B | 2026-03-24 | なし | — | IT 0.0/1.3 | 2025-01-17 #7 | 2026-04-01 `44019c07` | 0 |
| denso-taxi-processed-* | 1.1 | A | 2026-09-11 | なし | — | IT 0.9/0.3 | 2026-07-01 #1406 | 2026-07-14 #1491 | 1 |
| argoverse2-all | 1.1 | C | なし | なし | — | IT 0.0/1.1 | 履歴なし | — | 0 |
| alphaspp-raw-* | 0.9 | C | なし | なし | — | IT 0.0/0.9 | 履歴なし | — | 0 |
| train-3dgs-video-* | 0.9 | A | 2026-09-27 | なし | — | IT 0.0/0.9 | 2025-09-05 #350 | 2025-09-05 #350 | 1 |
| dataset-for-appen | 0.7 | C | なし | 測れない | — | Std | 履歴なし | — | 0 |
| driving-behavior-data-* | 0.7 | A | 2026-10-10 | なし | — | IT 0.1/0.6 | 2026-06-11 #990 | 2026-07-31 #1629 | 1 |
| tuscenes-tmp-* | 0.7 | A | 2026-10-13 | なし | 2026-10-14（47 百万回） | IT 0.0/0.0 | 2024-12-27 `86b82624` | 2026-10-09 `bef3c6ed` | 10 |
| s3-inventory-results-* | 0.7 | A | 2026-10-12 | なし | — | IT 0.3/0.3 | 2025-10-28 `d63affea` | 2026-08-04 #1655 | 2 |
| tuscenes-sampled-* | 0.6 | C | なし | 測れない | — | Std | 履歴なし | — | 0 |
| nuscenes-all | 0.5 | C | なし | 測れない | — | Std | 履歴なし | — | 0 |
| hyperpod-user-data-* | 0.5 | A | 2026-10-08 | 測れない | — | Std | 2026-08-20 #1729 | 2026-08-20 #1729 | 2 |
| alphaspp-data-* | 0.4 | C | なし | 測れない | — | Std | 履歴なし | — | 0 |
| dataset-for-third-dimension | 0.3 | B | 2026-01-09 | 測れない | — | Std | 履歴なし | — | 0 |
| openmaptiles-* | 0.3 | A | 2026-07-27 | 測れない | — | Std | 2026-06-19 #1329 | 2026-09-30 #2031 | 7 |
| trajectory-visualizer-data-* | 0.3 | A | 2026-10-13 | なし | — | IT 0.0/0.2 | 2025-11-06 `796f7de7` | 2025-11-06 `796f7de7` | 1 |
| semantic-kitti | 0.2 | C | なし | 測れない | — | Std | 履歴なし | — | 0 |
| denso-data-* | 0.2 | C | なし | 測れない | — | Std | 履歴なし | — | 0 |
| tuscenes-assets-* | 0.1 | A | 2026-10-13 | 測れない | — | Std | 2025-01-24 `d8f7579f` | 2026-07-16 #1513 | 6 |

0.1 TB 未満の 111 本は [`raw-data-security/classified.tsv`](raw-data-security/classified.tsv) にある。

### バケットごとの補足（分かった事実）

**一次データ（調査書 2.1 の原本）**

- **td1-raw**: 依存が最も広い（参照アプリ 20）。高頻度層に 648 TB があり、GET は半年で約 21 億回。
- **tuscenes-raw**: 15 か月の間、PUT は 1 度も無い（2025-04 に収集を終えている）。2026-03 に約 380 TB、2026-06 に約 316 TB が一括で読まれた（GCS 向けの変換バッチと思われる）。それ以降の読み出しは 0.1 TB 程度だけ。2026-08〜09 に LiDAR の間引きでオブジェクトが 8.3 億から 2.1 億に減っている。
- **denso-taxi-video**: 2026-07 にできたバケット（#1486）。容量のほぼ全部（433 TB）が高頻度層にあり、2026-09-19 に 21 TB の再アクセスがあった。2026-10-13 に Feature Cache ジョブへの読み取り権限が付いた（#2141）。
- **denso-nx-raw**: 2026-04 にできた（#948）。参照しているのは denso-nx アプリだけ。Azure に原本 175.5 TB が残っている（調査書 G01）。
- **databricks-workspace-e2e-bucket**: Standard クラスなので GET は測れない。UC 管理テーブル 2,880 本の実体（調査書 G09）。
- **td1-rlog**: td1-raw ができる前の rlog の置き場。2025-03-27 の `c6a41494` で、rlog の読み先が `td1-rlog` から `td1-raw` に変わった。今も参照しているのは Databricks の auto-loader の IAM 権限だけ。**15 か月の間、全量が AIA 層にあり、FA に戻った日が 1 日も無い。** 調査書によると、2024-10〜2025-04 の走行一式の唯一の原本で、派生テーブルも無い。
- **denso-raw**: 読み手だった JADD Creator が 2026-09-30 に削除され（#2014）、**IaC 上の読み手は 0**。残る経路は mono-e2e 側の Databricks ボリューム `denso.default.raw`（調査書 G31）。2025-12-22 に 4.7 GB、2026-03〜04 にごく少量の再アクセスがあった。
- **tuscenes-annotation**: 人手のラベル。2026-02〜03 に計 0.7 TB の再アクセスがあった。
- **denso-nx-sample**: 2026-05 にできた（#1033）。denso-nx の抽出テストで使われている。
- **tuscenes-calibration（旧、接尾辞なし）**: 2026-05-19 の #1142（train3dgs: per-account calibration bucket）で、IaC の参照先が `tuscenes-calibration-<account>` に移った。HEAD で旧バケットを名指ししているコードは無い（最後に名指ししたのは 2026-04-01 の `44019c07`）。**ところが新バケットはほぼ 0 TB で、旧バケットの 1.26 TB は移っていない。**

**二次・派生データ**

- **turing-video-training-sync-gcp**: 2026-05-26 の #1177 でできた GCS 同期用のバケット。全量が IA 層にある（S3 側では読まれていない）。前身の tuscenes-video-training は、#1440 のライフサイクルで全削除された。
- **turing-video-ap-northeast-1**: 閲覧用の DASH 動画。2025-02 にできた（#88）。commentary-audio だけは作り直せない（調査書 2.2）。
- **td1-video-h265-gcp**: 作ったコミット `f5842a54`（2026-04-07、H.265 の GCP 転送パイプライン）は、**main に一度もマージされていない**ブランチ `origin/td1-raw-gcp-converter` にしか無い。PUT は翌日 04-08 に止まっている。中身は td1-raw の cam_front 動画を H.265・960x620・30fps に変換したもの。
- **garuda-dataset / derived-data**: どちらも 2026 年にできた。GET はそれぞれ半年で約 96 億回、約 404 億回。

**外部由来・出所不明のもの**

- **external-driving-videos**: 前身は youtube-collector（改名して external-video-collector）。yt-dlp で YouTube から取得した動画。コードの更新は 2026-02 が最後。
- **tuscenes-basicai-datasets**: 唯一の読み手だった BasicAI のアノテーション整形 Lambda（DataFormatter）が、2025-11-19 の `20a04397` で削除された。15 か月の間、PUT も再アクセスも無い。
- **cdk-apps に履歴が一切無い**（手動で作ったもの）: miwa-gmo-2026-0424-archive（24.3 TB）、abemi-gmo-2026-0424-archive（3.7 TB）、datadog-account-level-cost-report、argoverse2-all、nuscenes-all、semantic-kitti、alphaspp-raw / alphaspp-data、dataset-for-appen、dataset-for-third-dimension、tuscenes-sampled、denso-data。
  - argoverse2・nuscenes・semantic-kitti は名前から公開データセットと思われる。
  - 購入データがどれかは、cdk-apps からは分からない。

**退避用**

- **cluster-backup**（#1641、クラスタからの退避）と **hyperpod-user-data**（#1729、HyperPod Lustre の縮小に伴うユーザーデータの退避）。

## 測れないこと・限界

- **Standard クラスのバケットは GET を推定できない。** 表の「測れない」がこれにあたり、判定は PUT だけによる。
- Intelligent-Tiering は 128 KB 未満のオブジェクトの層を動かさない。小さなファイルだけを読んだ場合は検知できない。
- 再アクセスは「オブジェクト数が増えていない日」だけで判定した。PUT と GET が同じ日にあると見落とす。ただし、そうしたバケットは PUT で A 区分に入るので、区分には影響しない。
- 最終 PUT はオブジェクト数の増加で見ている。同じキーへの上書きと、同じ日の削除と追加の相殺は見えない（LiDAR を間引いた td1-raw / tuscenes-raw が該当）。
- **対象は tuscenes-prod だけ。** amman-pipeline（amman-nbox-log-tmp 178 TB ほか）、e2e-dev（td1-raw-471112873671 27 TB）、biz-dev は ReadOnly の SSO が無く、調べていない。

## 調べること（未確認）

- 手動で作ったバケットの持ち主と出所（購入データかどうか、再取得できるか）。mono-e2e や Slack の履歴から、作った人を絞り込めるかもしれない。
- Standard クラスのバケットの GET。CloudTrail の KMS Decrypt イベントから推定できる可能性がある（バケットが SSE-KMS かどうかの確認が先）。
- tuscenes-calibration（旧）の 1.26 TB が、新バケットか別の場所に写されているか。
- amman-pipeline・e2e-dev・biz-dev の同じ集計（権限を持つ人に依頼が要る）。

## 成果物

[`raw-data-security/`](raw-data-security/) に置いた。再実行すると、その日の値で作り直せる。

| ファイル | 中身 |
|---|---|
| `cw_s3.py` | CloudWatch から全バケットの日次メトリクスを取る。引数: `regions.tsv metricscfg.tsv cw.json` |
| `analyze.py` / `classify.py` | `cw.json` から最終 PUT・再アクセス・区分を出す（`classify.py` は作業ディレクトリの `cw.json` を読み、`classified.json` / `classified.tsv` を書く） |
| `hist.sh` | 1 バケット分の cdk-apps 履歴（初出・最終・参照ファイル） |
| `regions.tsv` / `metricscfg.tsv` | バケットのリージョンと、リクエストメトリクスの設定 |
| `cw.json.gz` | 取得した生データ（2026-10-15） |
| `classified.tsv` | 全 158 バケットの集計結果 |
| `hist.tsv` / `apps.tsv` | cdk-apps の履歴と、参照アプリの数 |
| [`cli-versioning-runbook.md`](raw-data-security/cli-versioning-runbook.md) | 手で作った原本バケット 3 本（td1-rlog、tuscenes-calibration（旧）、denso-raw）のバージョニングを AWS CLI で入れる手順書（2026-10-19） |
| [`notion-bucket-classification.md`](raw-data-security/notion-bucket-classification.md) | チーム共有用の Notion 記事（種別と処遇の表、バケットごとの詳細の表。2026-10-19） |
| [`notion-s3-versioning-proposal.md`](raw-data-security/notion-s3-versioning-proposal.md) | チームに合意を取るための Notion 記事（バージョニングの対象と処遇の提案、2026-10-16） |

## 進捗と引き継ぎ

- 2026-10-15: 調査書を読み、TODO を 3 段階に整理した（数が多すぎたため裁定に切り替え）。CloudWatch と cdk-apps から、バケットごとの PUT・GET・経緯を取りまとめた。TODO を効き目で Tier に分け、手間もランク付けしたうえで、最初の裁定をした（上の「裁定」）。レビューの指摘はすべて採用した。
- **次にやること（2026-10-16 以降）**: 裁定の「いますぐやる」= バージョニングの開始から、順番に進める。
  1. 対象バケットの範囲を確定する（レビュー 5）。
  2. バージョニングを ON にする前の現状調査（読み取り専用でできる）: 各バケットの既存のライフサイクル、DataSync タスクの設定、Databricks の推奨（レビュー 1）。
  3. 古い版を何日残すかを決める（その時点で裁定する）。
  4. LiDAR の間引きを止めておく手当て（周知、またはロールの信頼ポリシーを外す。レビュー 2）。
  5. バージョニングを ON にする（作業は人が行う。他アカウントの 2 本は権限のある人に依頼）。
  6. その後、「次にやる」のバケットポリシーの設計に移る（レビュー 3・4）。
- 2026-10-16: 上の 1・2・4 の下調べを、AWS CLI（読み取り専用）で済ませた（「バージョニングの下調べ」）。既存の Expiration と DataSync の懸念は実質なし。databricks-workspace-e2e-bucket は、Databricks の推奨（7 日以内）と裁定案が食い違う。CDK 管理の 7 本は、cdk-apps の PR で入れる必要がある。denso-nx-raw の Azure 側のファイル数が、10-15 に急に減っていた。
- **次にやること**: 「裁定が要ること」の 5 点を決める → cdk-apps の PR（7 本）と、CLI の手順書（4 本）を書く。
- 2026-10-19: 種別 S1〜S10 と処遇を決め、チーム共有用の記事（[`notion-bucket-classification.md`](raw-data-security/notion-bucket-classification.md)）を作った。denso-nx-sample はチームで却下された。cdk-apps の準備を [s3-versioning-cdk.md](s3-versioning-cdk.md) に起票した。
- 2026-10-19: **古い版は失効させないことにした**（当初の 90 日を取り消し）。cdk-apps #2211 のレビューで「消すときはライフサイクルで古い版ごと消すので、失効は要らないのでは」と指摘があり、妥当と判断した。
  - 理由: 今回の手当ては操作ミスへの備え。失効を付けると、ミスに気づけないまま期限を過ぎたときにそこで消える。削除を検知する仕組みが無く、期限内に気づける保証がない。原本はふだん消しも上書きもしない（直近 30 日に容量が減った日が無い）ので、失効が無くても古い版はほとんど溜まらない。tuscenes-model（S3）の前例とも揃う。
  - 一緒に決めること: (1) 意図して大量に消すときは、版を指定して消すかライフサイクルで古い版ごと消す。今の LidarDeleter は `s3:DeleteObject` だけなので、このまま間引きを再開すると約 1.3〜1.6 PiB が古い版として**無期限に**残る。(2) 古い版の容量を Storage Lens などで見ておく。
  - 親のレビュー 1（「古い版を何日残すかを決める」）は、この判断で置き換えた。
  - CDK の 4 本の PR から失効を外し、CLI の手順書をバージョニングだけにした（[`cli-versioning-runbook.md`](raw-data-security/cli-versioning-runbook.md)、3 本分にまとめた）。
- 2026-10-19: **denso-taxi-processed を S6（派生）から S2（他社から受領）に移し、バージョニングを行うことにした。** cdk-apps #2216 のレビューで、作り直す元だった Azure 側の原本（bag）と加工後のデータが削除済みで、ほかに写しが無いと分かった（geniac4 は原本を 9/19、加工後を 9/30 に purge、mlops-1 も削除済み）。中身は bag ごとの calibration / can / frame_timestamps / gnss の parquet（1.0 TiB・1,126 万件）。frame_timestamps は mp4 から作り直せず、失うと video の動画も時刻を合わせられない。#2216 に含めた。
- 2026-10-19: tuscenes-basicai-datasets を今回の手当てから外した。CLI で入れるのは td1-rlog・tuscenes-calibration（旧）・denso-raw の 3 本になった。
- 2026-10-19: td1-rlog は、cdk import で IaC に取り込まず AWS CLI で入れると決めた（2025-09 から書き込みが無い運用の実態に合わせた）。手順書を書いた（その後 [`raw-data-security/cli-versioning-runbook.md`](raw-data-security/cli-versioning-runbook.md) に改めた）。
- 2026-10-19: 裁定の「次にやる」（バケットポリシー）の準備として、[原本バケットへのアクセスの洗い出しと手当て](s3-bucket-access-control.md) を起票した。
- ~~次にやること: cdk-apps の準備は子の workstream で進める。こちらでは、CLI で入れる 4 本の手順書と、LidarDeleter の扱いを決める。~~（2026-10-19 の終わりに下へ置き換えた）
- 2026-10-19 の終わりの状態:
  - バージョニングが有効: gaming-data-collection、td1-raw、tuscenes-raw、tuscenes-annotation、tuscenes-calibration（新）、denso-taxi-video、denso-taxi-processed、denso-nx-raw（cdk-apps #2211・#2215・#2216・#2217、deploy 後に ReadOnly で確認）、tuscenes-model（以前から）。古い版はどれも失効させない。
  - 未実施: td1-rlog、tuscenes-calibration（旧）、denso-raw（CLI。[`raw-data-security/cli-versioning-runbook.md`](raw-data-security/cli-versioning-runbook.md)）。
  - チーム共有用の記事（[`notion-bucket-classification.md`](raw-data-security/notion-bucket-classification.md)）は、今日の変更（失効なし・basicai の除外・denso-taxi-processed の S2 への移動）を反映済み。**Notion へは上げ直しが要る。**
- **次にやること**（優先順）:
  1. **CLI の 3 本を実行する**（書き込みの権限の人が手順書を流す → エージェントが ReadOnly で確認）。 → **2026-10-20 15:07 JST に実施済み**（伊藤が SSO FullAccess で実行）。エージェントが ReadOnly で、3 本とも `Enabled`、ライフサイクルは変わらず古い版の失効も無いことを確かめた。
  2. **LidarDeleter の扱いを決める**（周知か、信頼ポリシーを外すか）。**2026-10-20: 作った人に聞く。後回し。**td1-raw・tuscenes-raw はもうバージョニングが有効で、今のロール（`s3:DeleteObject` だけ）で間引きを再開すると、古い版が無期限に残って課金が続く。
  3. ~~2026-10-20 03:00 JST の `azure-mlops1-dcorp-inbound-daily` の結果を確かめる~~ → 2026-10-20 に確認。成功し、新しい SAS で認証は通っている。ただし送り元は 10-17 から 0 件で、中身が流れることは確かめられていない（[s3-versioning-cdk.md](s3-versioning-cdk.md)）。
  4. deploy の workflow の `paths` に `packages/azure-data-sync/**` を足す PR（denso-nx・denso-taxi。#2216 のレビューで約束した）。 → 2026-10-20 に cdk-apps #2231 を出した。**TODO: 作った人に確認してから進める（それまでレビュー依頼・マージはしない）。**
  5. 次の段: [s3-bucket-access-control.md](s3-bucket-access-control.md) の洗い出し。
  6. 「裁定が要ること」の残り: denso-nx-raw の Azure 側のファイル数の減少（10-17 以降は 0 件）を誰に確かめるか。 **2026-10-20: 作った人に聞く。後回し。**Notion の記事の上げ直し。
