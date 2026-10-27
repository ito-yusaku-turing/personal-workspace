# ステージ 2: 原本バケットの削除の毎時の報告（設計）

- 状態: 1 本目の PR（[cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267)、カナリアと記録の仕組み）は 2026-10-26 にマージし、deploy した。カナリアでの確認の 4 点のうち 3 点が済み、失効の確認だけが残っている（下の「カナリアでの確認の結果」）。次は毎時の集計と報告の PR
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md) のステージ 2
- 置き場所: cdk-apps の新しいアプリ `apps/original-bucket-audit`（tuscenes-prod、us-west-2）
- 構想での位置づけ: 「今日なに消したかわかる君」（原本バケットの戻せない削除などを、規則で必ず知らせる部品）。集める部分は、構想全体の「事実の層」の最初でもある。構想は [project:what-did-i-do の構想](../../../what-did-i-do/documents/notion-what-did-i-do-concept.md)（2026-10-26）。段階 3（毎時の報告）は、構想に合わせて設計し直す

## 要件（2026-10-22 伊藤が決定）

- 原本バケット 12 本の削除を、1 時間ごとに「誰が・どのバケットで・何件・何バイト」で報告する。削除が無い時間は投稿しない。
- Slack では本人にメンションする。意図しない操作なら、まず本人が気づく。Slack のセットアップ（チャンネル・bot）は後で決める。
- 報告はログとしても残す。
- **取りこぼさないことが前提。** 正時で正確に区切る必要はない（届いた時刻で区切る）。
- 手段は問わない。費用もかけてよい（下の見積もりで合意）。
- スコープ外: 即時のアラート（大量削除・古い版の削除・失効のルールの追加などで強く鳴らす）。オプションとして後で考える。
- 後回し: 仕組み自体の見張り（作るが後でよい）。

## 報告の形

```
🗑 原本バケットの削除（10/22 14:00〜15:00 に届いた分）
@伊藤 (FullAccess)
  td1-raw  古い版の削除 120 件 / 3.4 GB  ← 戻せない
    主なプレフィックス: collection/2026-10-01/ (98)、collection/2026-10-02/ (22)
@鈴木 (FullAccess)
  tuscenes-raw  削除 2,300 件 / 18 GB  ← 古い版から戻せる
denso-nx-extractor（denso-nx のロール）
  td1-raw  削除 4 件 / 1.2 MB
```

- 集計の単位は「主体 × バケット × 種別」。種別は次の 3 つ。
  - **削除**: 削除マーカーが付く。古い版から戻せる。
  - **古い版の削除**: 戻せない。
  - **失効**: ライフサイクルで消えた。戻せない。
- 操作の時刻の範囲と、主なプレフィックスの上位を添える。
- 「誰が」は次のとおり表示する。
  - SSO の人: セッション名のメールアドレス。Slack では `users.lookupByEmail` でメンションする。
  - アプリのロール・IAM ユーザー: 対応表で担当者を引く。
  - Databricks のロール: 本人は AWS から見えない。担当チームにメンションする。
  - 失効: 「ライフサイクル」と表示する。

## データの流れ

| 知りたいこと | 情報源 | 届き方 |
| --- | --- | --- |
| どのオブジェクトが・種別 | S3 のイベント `Object Deleted`。`deletion-type` は削除マーカーか完全な削除か、`reason` は API かライフサイクルか | EventBridge → Firehose → S3 |
| サイズ（Inventory より後に作られた分） | S3 のイベント `Object Created`（`size`・`version-id`） | 同上 |
| 誰が | 新しいトレイルの削除系のデータイベント（`DeleteObject`・`DeleteObjects`）の **ログファイル** | CloudTrail → S3 |
| サイズ（それより前からある分） | S3 Inventory（毎日・全版・Parquet） | S3 |

- 「誰が」は、EventBridge 経由ではなくログファイルから取る。CloudTrail のイベントを EventBridge に届けるのはベストエフォートで、取りこぼしうるため。ログファイルの配送は確実で、遅れは通常 5〜15 分。
- 「誰が」とオブジェクトは、S3 のイベントの `request-id` と CloudTrail の `requestID` でつなぐ（要確認）。一括削除は 1 つの request-id に多くのオブジェクトが付く。
- サイズの引き方:
  - 古い版の削除・失効: 消えた版の ID で引く。
  - 削除マーカー: 削除の時点で最新だった版を引く。
  - 引く先は、直近の Inventory と、それより後の `Object Created`。

## 毎時の処理（取りこぼさない仕組み）

毎時 15 分に、EventBridge Scheduler が集計の Lambda を起動する。集計には Athena を使う。

1. **時刻ではなく、未処理のファイルを処理する。** Firehose が置いたファイルのうち、まだ処理していないものを全部拾う（処理済みの記録は DynamoDB に持つ）。前の回が失敗しても、次の回で追いつく。遅れて届いたファイルも拾う。
2. 削除が 0 件なら、ここで終わる。Inventory は読まない。
3. CloudTrail のログで「誰が」を付ける。まだログが届いていないものは「保留」にして、次の回に回す。24 時間たっても付かなければ「不明（request-id）」として報告する。
4. サイズを付ける。
5. 報告を JSON でログのバケットに保存し、Slack に投稿する。
6. 重複を除く。S3 のイベントは「少なくとも 1 回」届くので、`bucket`・`key`・`version-id`・`sequencer` で重複を除く。

経路ごとの取りこぼしの手当て:

| 経路 | 手当て |
| --- | --- |
| EventBridge → Firehose | ルールのターゲットに再試行（最大 24 時間）と DLQ（SQS）を付ける。DLQ も処理の対象にする |
| Firehose → S3 | 失敗した分を S3 のエラーの置き場に出す。それも処理の対象にする |
| S3 のイベント自体の欠落 | **日次の突き合わせ**。前日と当日の Inventory を比べて、消えた版・新しい削除マーカーを求める。報告済みの削除と合わない分を報告する。最後の網 |

## 新しいアプリの中身

| 部品 | 中身 |
| --- | --- |
| 12 本の一覧 | `packages/original-bucket-guard` に足して、ステージ 1 と共有する |
| EventBridge の有効化 | 12 本を `fromBucketName` で読み込み、`enableEventBridgeNotification()` を呼ぶ |
| Inventory | `AwsCustomResource` で `PutBucketInventoryConfiguration` を呼ぶ（ID は `original-bucket-audit`。ID ごとの設定なので、ほかに触れない）。全版、Parquet、毎日。送り先はこのアプリのバケット |
| トレイル | CfnTrail と advanced event selectors。12 本の `DeleteObject`・`DeleteObjects` だけ（`readOnly=false`）。手本は `apps/garuda/lib/constructs/index-access-trail.ts` |
| ルール | S3 の `Object Created`・`Object Deleted`（12 本）→ Firehose（GZIP、到着時刻で分ける）。再試行と DLQ を付ける |
| ログのバケット | 生のイベント・CloudTrail のログ・Inventory・報告 |
| Athena | テーブルは partition projection で定義する |
| 処理済みの記録 | DynamoDB |
| 集計の Lambda | 毎時 15 分（EventBridge Scheduler）。日次の突き合わせも同じ Lambda で行う |

### EventBridge の有効化を、新しいアプリから既存のバケットとして行う理由

CDK は、自分が作ったバケット（`s3.Bucket`）の通知の設定を **丸ごと上書き** する（`Managed: true` → `handle_managed`）。各アプリの側で `eventBridgeEnabled` を足すと、Databricks の auto-ingest と file events（`csms-*`）の通知が消える。

読み込んだバケット（`fromBucketName`）なら `Managed: false` → `handle_unmanaged` になる。外部の通知を残して足すだけで、EventBridge の設定は削除のときも外部の設定として残る（aws-cdk-lib 2.173 の `custom-resource-handlers/dist/aws-s3/notifications-resource-handler/index.py` で確認）。

ステージ 1 のバケットポリシーは、通知と Inventory の設定を拒否しないので、ぶつからない。

## 保存期間と費用の見積もり（月）

前提（2026-10-22 に ReadOnly で測った）:
- 12 本の合計は約 6.5 億オブジェクト。1 か月の増分は約 136 万。
- td1-raw の PUT は月約 335 万回、削除は 30 日で 4 回。
- 作成のイベントは、月 400 万件と見込む。

| 項目 | 保存期間 | 費用 |
| --- | --- | --- |
| S3 Inventory の作成（6.5 億 × 毎日、100 万件あたり $0.0025） | — | 約 $49 |
| S3 Inventory の保存（1 日分を 30 GB と見込む） | **7 日**（サイズを引くのと日次の突き合わせに要る分だけ） | 約 $5 |
| Firehose（400 万件。1 件 5 KB に切り上げで課金） | — | 約 $0.6 |
| 生のイベント（GZIP で月 1 GB 未満） | 1 年 | $1 未満 |
| CloudTrail のデータイベント（削除だけ）とログ | 1 年 | $1 未満 |
| 毎時の報告（JSON） | 3 年、Object Lock（governance） | $1 未満 |
| Athena（削除があった時間だけ Inventory を読む。1 回 $0.1 前後）・Lambda・DynamoDB・Scheduler | — | 数ドル |
| **合計** | | **約 $60** |

- 費用のほとんどは Inventory。Inventory を 1 年残すと月 $250 以上かかるので、7 日にする。
- 事故で 1 億件が消された場合は、データイベントで一度きり約 $100 かかる（検知したい事故そのものなので許容する）。
- Object Lock を compliance ではなく governance にする理由: compliance にすると、設定を誤ったときに root でも縮められない。governance なら、特別な権限で直せる。

## 先に確かめること（カナリアで。手順は cdk-apps の `apps/original-bucket-audit/README.md`）

1. S3 の `Object Deleted` の `request-id` が、CloudTrail の `requestID` と一致するか。この設計の前提。
2. 一括削除（`DeleteObjects`）が、S3 のイベント（オブジェクトごとか）と CloudTrail（キーが載るか）にどう出るか。
3. 読み込んだバケットで `enableEventBridgeNotification()` を呼んだとき、既存の通知が残るか。カナリアには Databricks の代わりに SNS の通知（`canary-external`）を付けてある。
4. 古い版の削除・削除マーカー・失効のそれぞれで、`deletion-type`・`reason`・`version-id` がどう出るか。

## カナリアでの確認の結果（2026-10-26）

[cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) を 06:37 UTC にマージした（deploy は 06:42 UTC に完了）。06:48:25 UTC に伊藤が exerciser を 1 回起動した（run `20261026T064825Z`）。07:04 UTC にログのバケットを ReadOnly で読んだ。分析に使ったスクリプトは、エージェントの一時ディレクトリの `analyze-canary.py`（残していない）。

起こした操作:

| 操作 | exerciser の結果 | S3 のイベント（`events/`） | CloudTrail（`trail/`） |
| --- | --- | --- | --- |
| 作成 7 件（a を 2 版・b・c・d・expire を 2 版） | 成功 | `Object Created` 7 件。`size` と `version-id` が載る | `PutObject` 7 件 |
| 削除マーカー（a） | 成功 | `Object Deleted` 1 件。`deletion-type=Delete Marker Created`、`reason=DeleteObject` | `DeleteObject` 1 件。`requestID` がイベントと同じ |
| 古い版の削除（a） | AccessDenied | 出ない | `DeleteObject` 1 件、`errorCode=AccessDenied` |
| 一括削除（b・c・d） | 成功 | `Object Deleted` 3 件。3 件とも同じ `request-id`（一括削除の要求の ID）。`reason` は `DeleteObjects` ではなく `DeleteObject` | 本体の `DeleteObjects` 1 件（キーは載らない。`resources` は `ARNPrefix` だけ）＋ オブジェクトごとの `DeleteObject` 3 件 |
| 一括での古い版の削除（b） | 一部エラー（b が AccessDenied） | 出ない | 本体の `DeleteObjects` は**エラーなし**（HTTP 200）。オブジェクトごとの `DeleteObject` に `errorCode=AccessDenied` |

確認の 4 点の答え:

1. **request-id はつながる。** S3 のイベントの `request-id` 9 種は、すべて CloudTrail の `requestID` にあった。
2. **一括削除は、オブジェクトごとに記録される。**
   - S3 のイベントは、オブジェクトごとに 1 件。`request-id` は一括削除の要求の ID。
   - CloudTrail は、本体の `DeleteObjects` 1 件と、オブジェクトごとの `DeleteObject` に分かれる。オブジェクトごとの記録には `requestID` が無く、`additionalEventData.parentRequestID` に本体の ID が入る。キーは `resources` の `AWS::S3::Object` の ARN にある。
   - 今のトレイルの条件（`resources.ARN` の前方一致）で、本体もオブジェクトごとの記録も残った（レビューの指摘 3 は解消）。
3. **既存の通知は残る。** カナリアの通知に、SNS（`canary-external`）と `EventBridgeConfiguration` の両方があった。
4. **`deletion-type`・`reason`:** 削除マーカーは `Delete Marker Created`、`reason=DeleteObject`（一括削除でも同じ）。古い版の削除は守りで拒否されたので、`Permanently Deleted` はまだ見ていない。**失効（`expire/`。1 日で失効、古い版は 3 日で掃除）は、2026-10-27〜28 に確かめる。**

設計に反映すること:

- **「誰が」は CloudTrail からしか取れない。** S3 のイベントの `requester` はアカウント ID（`767397804933`）で、主体が分からない。
- **つなぎ方を 2 通りにする。** 単発の削除は `request-id` = `requestID`。一括削除は、`request-id` = `parentRequestID` かつ `resources` のキーで、オブジェクトごとの記録とつなぐ。
- **削除のイベントには `size` が載らない。** 設計どおり、`Object Created` と Inventory から引く。
- **拒否された削除は、CloudTrail にしか出ない。** 一括のときは、本体がエラーなし（HTTP 200）で、オブジェクトごとの記録にだけ AccessDenied が出る。拒否の試みを報告に載せるなら、オブジェクトごとの記録の `errorCode` を見る（今の要件では報告の対象外。即時のアラートを考えるときの材料）。
- **トレイルを削除系に絞るとき**（12 本を足す前）は、`eventName` に `DeleteObject` と `DeleteObjects` の両方を入れる。オブジェクトごとの記録の `eventName` は `DeleteObject` なので、`DeleteObjects` だけでは「誰が・どのキー」が取れない。

## tuscenes-raw の EventBridge（2026-10-27 決定）

- tuscenes-raw には、古いスタック `tuscenes`（tuscenes-pipeline。アーカイブ済み）のルール `tuscenes-NewTripEventRule…` が残っている。`metadata.json` の作成・削除で、cleaning の job・Supabase・Slack への投稿を起こすもの。tuscenes-raw の EventBridge は、2025-04 に datalake へ移したときに、これを止めるために無効にしてある。
- S3 の EventBridge は、default のバスにすべてのイベントを流す。届け先を選べないので、監査のために有効にすると、このルールも動き出す。
- **決定: 伊藤がこのルールを止めてから（`disable-rule`）、12 本すべてに同じ形で EventBridge を入れる。** 手順は workstream の TODO 25。
- 採らなかった案: tuscenes-raw だけ CloudTrail で報告する。CloudTrail では次のものが見えないため。
  - ライフサイクルの削除（CloudTrail に出ない）。
  - 一括削除の種類。オブジェクトごとの記録には `resources` のキーしか載らない。単発の `DeleteObject` なら、応答の `x-amz-delete-marker` で分かる。
- スタック全体の片付けは、別の資料（[tuscenes-stack-cleanup.md](../tuscenes-stack-cleanup.md)）。

## 後で決めること

- Slack: 投稿するチャンネルと bot（`users:read.email`・`chat:write`）。
- 見張り: Lambda の失敗、DLQ に入った、作成のイベントが 24 時間 0 件のときの通知。
- 即時のアラート（オプション）。
- アプリのロールと担当者の対応表の持ち方。

## カナリアと実装の段階（2026-10-22 追記）

- tuscenes-prod に常設のカナリア `original-bucket-canary-767397804933` を置く。原本バケットと同じ条件にする。
  - バージョニング
  - ステージ 1 のバケットポリシー
  - 外部の通知（SNS）
  - 監査のスタックの外にあること
- 削除は、カナリアの Lambda（`original-bucket-canary-exerciser`）を手で起動して起こす。古い版の削除は守りのバケットポリシーで拒否されるはずなので、拒否されることも確かめる。
- 段階:
  1. カナリアと記録の仕組み（[cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267)）
  2. カナリアで確認の 4 点
  3. 毎時の集計と報告
  4. 原本バケット 12 本を足す（その前にトレイルを削除系に絞る）
- 実装での判断:
  - Firehose の出力は 1 行 1 件にならない（区切りなしに連なる）。集計の側で 1 件ずつに分ける。Firehose の改行の付け足し（AppendDelimiterToRecord）は、動的パーティションと組み合わせる前提か不確かなので使わなかった。
  - Firehose を EventBridge のターゲットにするとき、CDK の L2 は DLQ と再試行を持てないので、L1 の上書きで足した。
