# 原本バケットの WORM 化: Quick Win の設計案

- 作成: 2026-11-04 ／ 伊藤（エージェントが起草）
- 親: [worm-quickwin-plan.md](worm-quickwin-plan.md)（作業 1・2・3・8 の設計）
- 状態: **案**（2026-11-04）。伊藤のレビュー待ち。決めてほしいことは 7 章

Quick Win の作業のうち、バケットポリシーの文（作業 1・2）、すぐの通知（作業 3）、入れる順番（作業 8）の設計案。2026-11-02〜04 の試し（[worm-probe-runbook.md](worm-probe-runbook.md) の結果の表）と、書き手の確かめ（プランの 9 章）を前提にする。

## 1. 前提（試しで分かったこと）

| 前提 | 根拠 |
|---|---|
| ガバナンスでは、迂回のヘッダーでホールド中の版も消せる。バケットポリシーで迂回を Deny すれば、FullAccess でも消せない | Q2・Q7 |
| ホールドが ON のあいだは、解除しない限り消えない（期限の欄は「読んだ時刻＋日数」で先へ動く） | Q12 |
| 解除のあと、保持期限のうちにかけ直せる | Q8 |
| 解除は `Object Retention Updated` として EventBridge に届く。キューまで 0〜2 秒。`object-retention-event-data.event-hold` に `ON`・`OFF` が入る | Q10 |
| ポリシー・鍵の既定・ライフサイクルの変更は、`AWS API Call via CloudTrail` として届く。拒まれた試みも届く | Q11 |
| Batch Operations で既存の版にホールドをかけられる。ジョブのロールに迂回の権限は要らない | Q6 |
| 書き込みには、Content-MD5 かチェックサムのヘッダーが要る。SDK の既定（boto3 1.35 は MD5、1.36 以降は CRC32 の trailer、CLI は CRC）なら通る。`when_required` と presigned URL（SigV2）は止まる。コピーは止まらない | Q5・Q13 |

**まだ試していないこと**（4 章の手順 B で確かめる）:

- 既存のバケット（バージョニング・ステージ 1 のポリシー・Databricks の通知・Intelligent-Tiering あり）に、後から Object Lock を有効にできるか。試しのバケットは作るときに有効にした。
- 鍵の既定（`Rule`）を外せば、チェックサムなしの書き込みがまた通るか（戻し方の前提）。
- EventBridge のルールの `MatchedEvents` の指標で、警報を鳴らせるか（3.2）。

## 2. バケットポリシー（作業 1・2）

cdk-apps の `packages/original-bucket-guard`（ステージ 1 の共通部）に、文を 2 つ足す。12 本はそれぞれのアプリ（datalake・denso-taxi・denso-nx・gaming-data-collection）がこの共通部を使っているので、共通部を直せば 12 本に入る。

| Sid | 中身 | 例外 | 入れる時期 |
|---|---|---|---|
| `DenyIrreversibleDelete`（既存） | 古い版の削除・バケットの削除・**鍵の既定の変更**（`s3:PutBucketObjectLockConfiguration`） | SSO の FullAccess・AWSAdministratorAccess | 入っている |
| `DenyProtectionRemoval`（既存） | バージョニング・ライフサイクル・ポリシー・所有者・ACL の変更 | SSO の 2 つ＋deploy のロール | 入っている |
| **`DenyGovernanceBypass`**（新） | `s3:BypassGovernanceRetention`（`bucket/*`） | **なし（全員）** | PR-1（鍵より前） |
| **`DenyLockChange`**（新） | `s3:PutObjectRetention`・`s3:PutObjectLegalHold`（`bucket/*`） | SSO の 2 つだけ（deploy のロールは入れない） | PR-3（ホールドをかけ終えてから） |

試しの `policy`（`~/runbook/worm-probe/worm-probe.sh` の `policy`。git の管理外。当てたポリシーは `~/runbook/worm-probe/tmp/policy.json`）と同じ形。Q7 で効くことを確かめた。

決めたこととその理由:

- **迂回の Deny は、鍵より先に入れる。** 鍵が無いうちは何も変わらない（迂回するものが無い）ので、安全に先に入れられる。後から入れると、鍵があって迂回できる期間ができる。
- **鍵の操作の Deny は、ホールドをかけ終えてから入れる。** Batch Operations のジョブのロールは例外ではないので、先に入れるとジョブが拒まれる（プランの作業 8）。そのあいだは、`s3:PutObjectRetention` を持つ例外でない主体（`AmazonS3FullAccess` などを持つもの）も解除できるが、解除は通知される（3 章）。
  - 対案: ジョブのロールを例外に足し、条件キー `s3:object-lock-event-hold` で `ON` だけ許す。順番の縛りは無くなるが、条件キーの効き方を試していないので、採らない。
- **鍵の既定は、deploy の経路では変えない。** `s3:PutBucketObjectLockConfiguration` はステージ 1 から SSO の 2 つにしか許していない。これを保ち、鍵の既定は FullAccess が CLI で入れる（4 章）。
  - CloudFormation の `ObjectLockEnabled` を既存のバケットで変えると、置き換え（作り直し）にならないかを確かめていない。原本バケットで試すのは危ないので、CDK では持たない。
  - 代わりに、CDK の側のバケットには「鍵の既定は CLI で入れた」とコメントを残す。ドリフトの検出には出る。

## 3. すぐの通知（作業 3）

### 3.1 全体の形

```text
入口 1: S3 のイベント（解除）
  12 本 ──EventBridge を有効化──▶ default のバス
    ルール A: Object Retention Updated・event-hold が ON でない ──▶ ロググループ（記録）
                                                     │
                                       警報: ルール A の MatchedEvents ≥ 1（1 分）
                                                     ▼
入口 2: CloudTrail 経由の管理イベント            SNS のトピック ──▶ メール（暫定）
    ルール B: 12 本のポリシー・鍵の既定など ──────────▶ │          ──▶ Slack（後で）
    ルール C: 通知の部品そのものの変更 ─────────────▶ │
```

- 送り先は **SNS** にする（プランの 8.2。通知の部品のうち、外せる主体がいちばん少ない）。Lambda と Secrets Manager の鍵は使わない。
- 置き場所は cdk-apps の `apps/original-bucket-audit` に、新しいスタック（仮に `RetentionAlertStack`）として足す。バケットは今の `AuditStack` と同じく、**読み込んだうえで EventBridge を足す**（`Managed: false`。Databricks の通知を消さない。プランの 8.2）。
  - 監査の対象（`AUDIT_TARGET_BUCKETS`。今はカナリアだけ）は広げない。広げると、12 本の作成・削除のイベントがすべて Firehose に流れる。通知の対象は別の一覧（仮に `ALERT_TARGET_BUCKETS`＝カナリア＋12 本）にする。

### 3.2 入口 1: 解除（ルール A と警報）

```json
{
  "source": ["aws.s3"],
  "detail-type": ["Object Retention Updated"],
  "detail": {
    "bucket": { "name": ["<12 本とカナリア>"] },
    "$or": [
      { "object-retention-event-data": { "event-hold": [{ "anything-but": "ON" }] } },
      { "object-retention-event-data": { "event-hold": [{ "exists": false }] } }
    ]
  }
}
```

- **`ON` を除く。** Batch Operations で既存の版にホールドをかけると、約 6.5 億件の `ON` のイベントが出る。これを通知すると洪水になる。`event-hold` の欄の無いイベント（固定の保持期限の変更など）は、念のため拾う。
- **1 件ずつ SNS に送らず、警報でまとめる。** 解除が Batch Operations でまとめて行われると、億の単位のイベントが出る。1 件ずつメールにすると、届かないうえに費用がかさむ（SNS のメールは 10 万通あたり $2）。そこで、
  - ルール A の送り先は CloudWatch Logs のロググループにする（何が解除されたかの記録。保持は 2 年）。
  - CloudWatch の警報で、ルール A の `MatchedEvents` が 1 分に 1 件以上なら鳴らす（欠けたデータは「超えていない」として扱う）。警報は状態が変わったときに 1 回だけ SNS に送る。
  - 届くまでは 1〜3 分の見込み（指標の集計の分）。要件の「すぐ」には足りるとみる。
  - 中身は、警報の説明に Logs Insights のクエリの例を書いておき、受け取った人が見る。
- 1 億件の解除のときの記録の費用は、ロググループの取り込みで数百ドルの見込み（1 件 1 KB として 100 GB × $0.50）。起きたら事件なので許容する。

### 3.3 入口 2: 12 本の管理の操作（ルール B）

```json
{
  "source": ["aws.s3"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventSource": ["s3.amazonaws.com"],
    "eventName": [
      "PutBucketPolicy", "DeleteBucketPolicy",
      "PutBucketObjectLockConfiguration",
      "PutBucketLifecycle", "DeleteBucketLifecycle",
      "PutBucketVersioning",
      "PutBucketNotification",
      "PutBucketOwnershipControls", "PutBucketAcl",
      "DeleteBucket"
    ],
    "requestParameters": { "bucketName": ["<12 本とカナリア>"] }
  }
}
```

- 送り先は SNS に直接（件数が少ないので、まとめなくてよい）。入力の変換で「誰が・何を・どのバケットに・拒まれたか（`errorCode`）」を 1 通にまとめる。
- **拒まれた試みも送る**（Q11 で届くことを確かめた）。乗っ取りの下調べに気づける。
- `PutBucketNotification` を入れるのは、入口 1 を外す操作（バケットの通知の設定の書き換え）に気づくため（プランの 8.2）。Databricks が通知の設定を作り直すと鳴るが、頻度は低い。
- 実際の名前（`PutBucketLifecycle` か `PutBucketLifecycleConfiguration` か、など）は、カナリアで 1 回ずつ鳴らして直す。Q11 で見えたのは `PutBucketPolicy`・`DeleteBucketPolicy`・`PutBucketObjectLockConfiguration`・`PutBucketLifecycle`。

### 3.4 通知の部品そのものの変更（ルール C）

ルール A・B、警報、ロググループ、SNS のトピックを外す・黙らせる操作を、ルール C で拾って SNS に送る。

| 部品 | 拾う操作（eventName） |
|---|---|
| EventBridge のルール | `DeleteRule`・`DisableRule`・`PutRule`・`RemoveTargets`・`PutTargets`（名前で絞る） |
| CloudWatch の警報 | `DeleteAlarms`・`DisableAlarmActions`・`PutMetricAlarm`・`SetAlarmState` |
| ロググループ | `DeleteLogGroup`・`PutRetentionPolicy` |
| SNS のトピック | `DeleteTopic`・`SetTopicAttributes`・`Unsubscribe`・`RemovePermission` |
| バケットの EventBridge の有効化 | ルール B の `PutBucketNotification` で拾う |

- **限界**: SNS のトピックそのものを消されると、その通知は届かない。ルール C を消す操作は、C 自身では拾えない（ルール B は S3 の操作しか拾わない）。ルール C の名前の条件には、A・B と C 自身を入れる（C の無効化や送り先の差し替えは、消される前のイベントとして拾える見込み。カナリアで確かめる）。それでも、FullAccess が順に外していけば黙らせられる。これはプランの穴 A（FullAccess の乗っ取り）そのもので、フルスペックで見張りを tuscenes-prod の外に置いて塞ぐ（プランの 5 章）。
- **CloudWatch の警報を外せる主体は、まだ調べていない。** プランの 8 章の判定（`notification-tamper.py`）に、`cloudwatch:DeleteAlarms`・`DisableAlarmActions`・`PutMetricAlarm` と `logs:DeleteLogGroup` を足して取り直す。

### 3.5 受け手

- **最初は SNS のメール**にする。宛先は伊藤と、MLOps のチームのメーリングリスト（暫定。フルスペックで頂点の群の外へ移す。requirements.md の 7.5）。
- 購読の確認は `confirm-subscription --authenticate-on-unsubscribe true` で行う。メールの「購読をやめる」のリンクで、受け取った人が認証なしに外せないようにする。
- Slack は、AWS Chatbot（Amazon Q Developer in chat applications）で SNS から送る。Slack のワークスペースの承認が要るので、保留中の 0-2・0-3（Slack の bot の準備）と一緒に進める。
- トピックのポリシーは、`events.amazonaws.com`（ルールの ARN で絞る）と `cloudwatch.amazonaws.com`（警報の ARN で絞る）からの Publish だけを許す。暗号化はしない（AWS 管理キーの `aws/sns` では EventBridge から送れない）。

### 3.6 要確認

- [ ] CloudTrail 経由の管理イベントが EventBridge に届くには、tuscenes-prod の中に管理イベントを記録する証跡が要るか。Q11 では届いたので今は満たしているが、どの証跡に頼っているか（Control Tower の組織の証跡か、`original-bucket-audit` か）を確かめる。証跡を止めると入口 2 が黙るなら、ルール C に `StopLogging`・`DeleteTrail`・`PutEventSelectors` を足す。
- [ ] ルール A の `MatchedEvents` が、送り先がロググループのときに出るか（カナリアで確かめる）。
- [ ] td1-raw と tuscenes-model の EventBridge を、今どのスタックが有効にしているか。CDK が通知を丸ごと持っているバケットがあれば、`Managed: false` の追加と食い違う（TODO 23 の注意）。

## 4. 入れる順番（作業 8）

### 4.1 全体

| 手順 | 中身 | 誰が・どう | 待ち |
|---|---|---|---|
| **A. PR-1** | 迂回の Deny（2 章の `DenyGovernanceBypass`）と、通知（3 章）を cdk-apps で入れる | PR（マージは伊藤、deploy は Actions） | 通知がカナリアで鳴ることを確かめる |
| **B. カナリアで予行** | カナリア `original-bucket-canary-767397804933` に、後から Object Lock を有効にする。既定はガバナンス・イベントホールド 1 日。カナリアの exerciser を回す | 伊藤（FullAccess・CLI。手順書を用意する） | 1 章の「まだ試していないこと」3 つ。戻し方（`Rule` を外すと書けるか） |
| **C. 波ごとに鍵をかける** | 各バケットで、(1) 鍵の既定を入れる（ガバナンス・イベントホールド 30 日）、(2) 1 日ほど書き手のエラーを見る、(3) Batch Operations で今の版にホールドをかける、(4) 件数を確かめる | 伊藤（FullAccess・CLI と Batch Operations。ジョブの設定は 2 人で確かめる） | 波ごとに数日 |
| **D. PR-3** | 鍵の操作の Deny（2 章の `DenyLockChange`） | PR | 全部の波のジョブが終わってから |

- PR-2 は書き手の直し（mono-e2e の Cosmos・backend-api と jadd-cli）。手順 C の 4 波の前に要る。
- カナリアは常設で、Object Lock は外せないが、カナリアは原本と同じ守りを持つべきものなので、外せなくてよい。

### 4.2 波（小さいもの・書き手の問題が無いものから）

| 波 | バケット | 理由 | 前に要るもの |
|---|---|---|---|
| 1 | tuscenes-calibration（新、354 件）、td1-rlog、tuscenes-calibration（旧）、denso-raw、denso-nx-raw | 書き込みがほぼ無い。件数が少ない | 手順 B |
| 2 | gaming-data-collection、denso-taxi-processed、denso-taxi-video、tuscenes-annotation | 書き手が SDK の既定で書く見込み。DataSync（denso）と Databricks の volume は不明 | DataSync を Object Lock のバケットに向けて試す。Databricks の volume の場所の確認。gaming の PC の boto3 の設定（`when_required` にしていないか） |
| 3 | td1-raw、tuscenes-raw | 件数で 9 割（費用の大半）。いちばん大事な原本 | 波 1・2 で問題が無いこと |
| 4 | tuscenes-model | Cosmos（書き込みの約 82%）と jadd-cli が止まる | PR-2（Cosmos の `when_required` を外す、backend-api の presigned URL を SigV4＋チェックサムにする、古い jadd-cli を止める） |

### 4.3 戻し方

| 起きたこと | 戻し方 | 確かめ |
|---|---|---|
| 書き手が止まった | そのバケットの鍵の既定（`Rule`）を外す（FullAccess・CLI）。Object Lock 自体は外せないが、既定が無ければ新しい版に鍵はかからない | 手順 B で「`Rule` を外すとチェックサムなしで書けるか」を確かめる |
| Batch Operations の設定を誤った | ガバナンスなので、FullAccess が解除のジョブを流せる（迂回の Deny は解除を止めない。Q3）。解除のあとは 30 日待つ | 誤りやすいのは日数。ジョブの設定は 2 人で確かめる |
| 通知がうるさい | ルール B のイベント名を絞る（PR） | — |

### 4.4 費用

[worm-design.md](worm-design.md) の 5 章のまま（既存の版へのホールドで一度きり約 $3,900、その記録のデータイベントで約 $650）。通知の部品は月に数ドル以下。

## 5. 書き手の直し（PR-2 の中身）

| 書き手 | 直し方 | 持ち主への連絡 |
|---|---|---|
| Cosmos の checkpoint（mono-e2e `projects/wm_generation/.../boto3_client.py:282`・`utils/object_store.py:29`） | `request_checksum_calculation="when_required"` を消すか `when_supported` にする。Q13 で、既定なら boto3 のどの版も通ることを確かめた | 要（TeamE2E） |
| backend-api の upload_url（`projects/api/backend-api/routers/models.py:1203`、マルチパートは `:420`。クライアントは `:1095`） | **クライアントを SigV4（`signature_version="s3v4"`）にする**。そのうえでチェックサムを付ける形は、11-04 の 2 回目の試し（`Q13_ONLY=presign-v4`）で決める。「署名に入れない Content-MD5 を jadd-cli が付ける」が通れば、API の形を変えずに済む | 要（backend-api と jadd-cli の持ち主） |
| jadd-cli（`packages/jadd-cli/src/jadd/model/api.py:151,156,191`） | PUT に Content-MD5（パートごと）を付ける。古い版は書けなくなるので、backend-api の側で最小の版を確かめるか、利用者に上げてもらう | 同上 |

## 6. フルスペックへの持ち越し

- 通知の見張りを tuscenes-prod の外に置く（3.4 の限界）。
- 受け手を頂点の群の外へ（3.5）。
- 鍵の操作の例外を、専用の経路（解除用の workflow）だけにする（プランの 6 章）。

## 7. 決めてほしいこと

1. 鍵の既定を CLI で入れ、CDK では持たない（2 章）でよいか。
2. 解除の通知を、1 件ずつではなく警報でまとめる（3.2）でよいか。届くまで 1〜3 分になる。
3. 最初の受け手（3.5）。メールの宛先を誰にするか。
4. 波の分け方と順番（4.2）。
5. 鍵の操作の Deny（`DenyLockChange`）を最後に回す（2 章）か、ジョブのロールを条件つきで例外に足して先に入れるか。
