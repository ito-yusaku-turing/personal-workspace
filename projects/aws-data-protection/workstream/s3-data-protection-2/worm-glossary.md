# 原本バケットの WORM 化: 用語集

- 作成: 2026-11-04
- 使いどころ: WORM の資料を**共有用に仕上げるとき**に、言い換えをこの表で正式名に直す・補う。作業中の資料（workstream）は、いまの言い方のままでよい。
- 対象の資料: [worm-quickwin-plan.md](worm-quickwin-plan.md)・[worm-quickwin-design.md](worm-quickwin-design.md)・[worm-probe-runbook.md](worm-probe-runbook.md)、10-30 の [worm-design.md](worm-design.md)・[worm-reference.md](worm-reference.md)・[option-reassessment.md](option-reassessment.md)、Notion に上げた [S3 Object Lock（WORM）の整理](../../documents/notion-s3-object-lock.md)

## 1. 書き方の決まり

1. **抽象的・比喩的な言い方を使ったら、括弧で AWS の正式名（操作名・API・設定の項目）を補う。** 例: 「既存のバージョンにイベントホールドをかける（S3 Batch Operations の `PutObjectRetention`）」。
2. **同じ言葉に複数の意味を持たせない。** 「鍵」はとくに 5 つの意味で使っていたので、2 章の表で書き分ける。
3. **自分たちで作った呼び名（6 章）は、共有資料で使うかどうかを都度確認する。** 共有資料では「第一段階」のような、初めて読む人にも分かる語を選ぶ。
4. 補うのは、その段落で初めて出てくるところだけでよい。同じ段落で何度も括弧を付けない。

## 2. 「鍵」の書き分け

| いまの言い方 | 指しているもの | 書き方（正式名） |
|---|---|---|
| 「12 本に鍵をかける」「波ごとに鍵をかける」 | 下の 3 つをまとめた導入の作業 | Object Lock の導入（有効化＋既定の保持設定＋既存のバージョンへのイベントホールド） |
| 「バケットの鍵の設定」「Object Lock を有効にする」 | バケットで Object Lock を使えるようにする | Object Lock の有効化（`PutObjectLockConfiguration` の `ObjectLockEnabled: Enabled`。新しいバケットなら `CreateBucket` の `ObjectLockEnabledForBucket`）。バージョニングが前提で、有効にしたら戻せない |
| 「鍵の既定」 | 新しく書かれたバージョンに自動でかかる保持 | 既定の保持設定（`PutObjectLockConfiguration` の `Rule.DefaultRetention`。今回は `Mode: GOVERNANCE` と `DefaultEventHold.Days`）。外すときは `Rule` の無い設定を入れる |
| 「版に鍵がかかる」「鍵のかかった版」 | バージョンごとの保持の状態 | 保持（retention）。モード（`Mode`）・保持期限（`RetainUntilDate`）・イベントホールド（`EventHold`）の組。「保持されているバージョン」と書く |
| 「鍵の操作」「鍵の操作の Deny」 | バージョンごとの保持を変える操作 | 保持の変更（`s3:PutObjectRetention`・`s3:PutObjectLegalHold`） |
| 「Slack の鍵」 | Slack に送るための秘密の値 | Slack の認証情報（Webhook の URL・トークン）。Object Lock とは無関係 |

## 3. Object Lock の操作と状態

| いまの言い方 | 書き方（正式名） | メモ |
|---|---|---|
| 版 | バージョン（オブジェクトのバージョン、`VersionId`） | |
| ホールド | イベントホールド（`EventHold`） | リーガルホールド（`LegalHold`、`PutObjectLegalHold`）とは別物。共有資料では省略しない |
| ホールドをかける | イベントホールドの設定（`PutObjectRetention` の `EventHold: ON`） | 書き込み時は既定の保持設定で自動にかかる |
| 解除 | イベントホールドの解除（`PutObjectRetention` の `EventHold: OFF`。日数は書かない） | EventBridge では `Object Retention Updated` の `event-hold: OFF` |
| かけ直し | イベントホールドの再設定（`PutObjectRetention` の `EventHold: ON`） | 解除後、保持期限のうちならできる（Q8） |
| 期限・期限の欄 | 保持期限（`RetainUntilDate`） | イベントホールド中は「読んだ時刻＋日数」で先へ動く（Q12） |
| 解除の後 30 日 | 解除後の保持期間（既定の保持設定の `DefaultEventHold.Days`、バージョンごとなら `EventHoldDuration.Days`） | 解除した時刻＋日数で保持期限が固まる |
| 可変の保持期間 | イベントホールドを使った保持（AWS の説明では variable retention period） | |
| 既存の版にかける | 既存のバージョンへのイベントホールドの設定（S3 Batch Operations の Object Lock retention の操作＝`PutObjectRetention`） | 迂回の権限は要らない（Q6） |
| ガバナンス / コンプライアンス | ガバナンスモード（`GOVERNANCE`）/ コンプライアンスモード（`COMPLIANCE`） | |
| 迂回 | ガバナンスモードの迂回（`s3:BypassGovernanceRetention` の権限と、`x-amz-bypass-governance-retention` ヘッダー。CLI は `--bypass-governance-retention`） | |
| 迂回の Deny | バケットポリシーでの `s3:BypassGovernanceRetention` の Deny | 設計案の `DenyGovernanceBypass` |
| 鍵の操作の Deny | バケットポリシーでの `s3:PutObjectRetention`・`s3:PutObjectLegalHold` の Deny | 設計案の `DenyLockChange` |
| 消す（版を） | バージョンを指定した削除（`DeleteObject` に `VersionId`） | 版を指定しない削除は削除マーカーを付けるだけ |
| 削除マーカー | 削除マーカー（delete marker） | Object Lock では守られない |
| ライフサイクルで消える | ライフサイクルの失効（`NoncurrentVersionExpiration`・`Expiration`） | 保持されているバージョンは消せない（Q9 で確かめる） |

## 4. 書き込みとチェックサム

| いまの言い方 | 書き方（正式名） | メモ |
|---|---|---|
| チェックサムのヘッダー | `Content-MD5` または `x-amz-checksum-*`（`x-amz-sdk-checksum-algorithm`） | Object Lock の保持がかかる書き込みでは必須 |
| trailer で付ける | チェックサムをトレーラーで送る（`x-amz-trailer`、`x-amz-content-sha256: STREAMING-UNSIGNED-PAYLOAD-TRAILER`） | boto3 1.36 以降の既定 |
| `when_required` | boto3 / botocore の設定 `request_checksum_calculation="when_required"` | Object Lock のバケットでは拒まれる（Cosmos） |
| presigned URL | 署名付き URL（`generate_presigned_url`） | boto3 の既定は SigV2。Object Lock には SigV4（`signature_version="s3v4"`）が要る |
| マルチパート | マルチパートアップロード（`CreateMultipartUpload`・`UploadPart`・`CompleteMultipartUpload`） | チェックサムはパートごとに要る |
| コピー | `CopyObject`・`UploadPartCopy` | チェックサムなしでも通った（Q13） |

## 5. 通知と見張り

| いまの言い方 | 書き方（正式名） | メモ |
|---|---|---|
| すぐの通知 | EventBridge のルールから SNS へのメール通知（後で AWS Chatbot で Slack） | |
| 入口 1・ルール A | イベントホールドの解除の通知（EventBridge のルールで `Object Retention Updated` のうち `event-hold` が `ON` 以外を CloudWatch Logs に送り、CloudWatch のアラームで SNS へ） | |
| 入口 2・ルール B | バケット設定の変更の通知（EventBridge の `AWS API Call via CloudTrail` のうち、12 本への `PutBucketPolicy` など） | 拒まれた試みも届く（Q11） |
| ルール C | 通知の設定そのものの変更の通知（EventBridge のルール・CloudWatch のアラーム・ロググループ・SNS のトピックへの変更） | |
| 部品・通知の部品 | 通知の設定（EventBridge のルール・CloudWatch のアラーム・CloudWatch Logs のロググループ・SNS のトピックとサブスクリプション） | |
| 警報でまとめる | CloudWatch のアラーム（ルールの `MatchedEvents` が 1 分に 1 件以上）で 1 通にまとめる | |
| 管理イベント | CloudTrail の管理イベント（EventBridge では `AWS API Call via CloudTrail`） | |

## 6. 自分たちで作った呼び名（共有資料では都度確認）

作業資料ではこのまま使ってよい。共有資料に移すときは右の案に置き換え、使う語を確認する。

| 作業資料での語 | 共有資料での案 | 中身 |
|---|---|---|
| Quick Win | 第一段階 | 権限の設計を待たず、ガバナンスモードで 12 本に入れる |
| フルスペック | 第二段階、または完成形 | 権限の設計のあとで、コンプライアンスモードや tuscenes-prod の外の見張りまで入れる |
| 外せない層 | 使わない。「管理者権限でも消せない保護」のように中身を書く | |
| 書き手 | 書き込み元のシステム | バケットに書き込むプログラム・ジョブ・人の操作 |
| 波 1〜4 | 導入の段階 1〜4（または第 1 陣〜第 4 陣） | 12 本を分けて入れる順番 |
| カナリア | 予行用のバケット（`original-bucket-canary-767397804933`） | |
| 12 本 | 原本バケット 12 本 | 一覧は [worm-design.md](worm-design.md) の 2.5 |
| 穴 A〜D | 第一段階で残るリスク A〜D | [worm-quickwin-plan.md](worm-quickwin-plan.md) の 3.2 |
| PR-1・PR-2・PR-3 | 中身で呼ぶ（迂回の Deny と通知の PR、書き込み元の直しの PR、保持の変更の Deny の PR） | |
| 試し・Q1〜Q13 | 検証・検証項目 Q1〜Q13 | |
