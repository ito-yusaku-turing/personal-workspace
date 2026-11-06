# 原本バケットの WORM 化: Quick Win の設計案

- 作成: 2026-11-04 ／ 伊藤（エージェントが起草）
- 親: [worm-quickwin-plan.md](worm-quickwin-plan.md)（作業 1・2・3・8 の設計）
- 状態: **案**（2026-11-04、11-05 に 2 章・2.1・4 章を直した。11-06 にチームの共有ミーティングの意見で 2.1・4 章を直した）。決めてほしいことは 7 章

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

> **2026-11-05 に直した（E2〜E4 の決定）。** FullAccess を例外から外し、保持の変更の例外をジョブのロールだけにした。仕組みは 2.1。下の表が今の案。

| Sid | 中身 | 例外 | 入れる時期 |
|---|---|---|---|
| **`DenyGovernanceBypass`**（新） | `s3:BypassGovernanceRetention`（`bucket/*`） | **なし（全員）** | PR-1（鍵より前） |
| **`DenyLockChange`**（新） | `s3:PutObjectRetention`・`s3:PutObjectLegalHold`（`bucket/*`） | **ジョブのロール `central/original-bucket-lock-batch` だけ**（人は入れない） | PR-1（2.1 のロールと一緒に。順番の縛りは無くなった） |
| `DenyIrreversibleDelete`（既存を直す） | 古い版の削除・バケットの削除・鍵の既定の変更（`s3:PutBucketObjectLockConfiguration`） | **AWSAdministratorAccess だけ**（FullAccess を外す） | PR-1 |
| `DenyProtectionRemoval`（既存を直す） | バージョニング・ライフサイクル・ポリシー・所有者・ACL の変更 | **AWSAdministratorAccess と deploy のロール**（FullAccess を外す） | PR-1 |

- 共通部は 12 本で同じ。WORM から外した tuscenes-model・tuscenes-annotation でも、FullAccess は古い版を消せなくなる。2 本の古い版を消すときも、ライフサイクル（CDK）で消す（11-05、D2 の波及）。
- ふつうの削除（削除マーカー）は止めない。
- 11-04 の案（例外は SSO の FullAccess・AWSAdministratorAccess、`DenyLockChange` はホールドをかけ終えてから）は、11-05 にこの表に置き換えた。

試しの `policy`（`~/runbook/worm-probe/worm-probe.sh` の `policy`。git の管理外。当てたポリシーは `~/runbook/worm-probe/tmp/policy.json`）と同じ形。Q7 で効くことを確かめた。

決めたこととその理由:

- **迂回の Deny は、鍵より先に入れる。** 鍵が無いうちは何も変わらない（迂回するものが無い）ので、安全に先に入れられる。後から入れると、鍵があって迂回できる期間ができる。
- ~~**鍵の操作の Deny は、ホールドをかけ終えてから入れる。**~~ → 11-05: ジョブのロールを例外にしたので、ホールドをかけるジョブも同じロールで流せる。先に入れてよい。以下は 11-04 の理由（経緯）。Batch Operations のジョブのロールは例外ではないので、先に入れるとジョブが拒まれる（プランの作業 8）。そのあいだは、`s3:PutObjectRetention` を持つ例外でない主体（`AmazonS3FullAccess` などを持つもの）も解除できるが、解除は通知される（3 章）。
  - 対案: ジョブのロールを例外に足し、条件キー `s3:object-lock-event-hold` で `ON` だけ許す。順番の縛りは無くなるが、条件キーの効き方を試していないので、採らない。
- **鍵の既定は、deploy の経路では変えない。** `s3:PutBucketObjectLockConfiguration` はステージ 1 から SSO の 2 つにしか許していない。これを保ち、鍵の既定は CLI で入れる（4 章）。PR-3 までは FullAccess（伊藤）、PR-3 の後は AWSAdministratorAccess が入れる（FullAccess を例外から外すのは PR-3）。
  - CloudFormation の `ObjectLockEnabled` を既存のバケットで変えると、置き換え（作り直し）にならないかを確かめていない。原本バケットで試すのは危ないので、CDK では持たない。
  - 代わりに、CDK の側のバケットには「鍵の既定は CLI で入れた」とコメントを残す。ドリフトの検出には出る。

### 2.1 掃除と承認の仕組み（2026-11-05。11-06 に掃除の流れを先送り）

> **2026-11-06（チームの共有ミーティング、[worm-decisions.md](worm-decisions.md) の D13・D14）:** 削除の運用（下の「流れ」）は今は詰めず、消す必要が出たときに決める。導入で作るのは次の 3 つだけにする。
>
> - ジョブのロール `central/original-bucket-lock-batch`。最初に既存のバージョンへイベントホールドを付けるジョブと、対象を誤ったときの解除のジョブに使う。
> - SCP `DenyPassLockBatchRole`。ロールを渡せるのを AWSAdministratorAccess（完全削除用の権限）だけにする。FullAccess を外す（D14）には要る。
> - ジョブのレポートの置き場。FullAccess が書く `manifests/` は作らない。
>
> 承認する人（完全削除用の権限）を専用に新しく作るか（G1）と、SCP で守る範囲（G2）は検討中。以下の「流れ」は、消す必要が出たときの出発点として残す。

方針（伊藤、11-05。[worm-decisions.md](worm-decisions.md) の「検討中」）: 対象を決めるところまでは FullAccess でもできる。実行は AWSAdministratorAccess が承認し、執行はジョブに任せる。対象は prefix や正規表現。頻度は 3 か月に 1 度あるかないかで、MLOps チームが決める。緊急の削除はしない（「完全に消すには最低 30 日かかる」）。

承認の形は **(a) AWSAdministratorAccess がジョブを作る** にした（11-05、伊藤）。Batch Operations の確認待ちの機能（(b)）は、FullAccess が確認なしのジョブを作るのを止められるか分からないので採らない。

**流れ:**

| # | 手順 | 主体 | 使う権限 |
|---|---|---|---|
| 1 | 対象を決め、マニフェスト（`Bucket,Key,VersionId` の CSV）を作って、置き場の `manifests/` に置く。正規表現はインベントリか一覧から絞る（Batch Operations のマニフェストの生成は prefix・接尾辞・部分一致まで） | FullAccess | 読み取り、置き場への書き込み |
| 2 | MLOps チームで決めたことを確かめ、ジョブを 2 本作る。① タグ付け（例 `cleanup=<日付>`）、② 解除（`S3PutObjectRetention` で `EventHold: OFF`）。①が終わってから② | **AWSAdministratorAccess**（承認） | `s3:CreateJob`、ロールの `iam:PassRole` |
| 3 | 対象の版にタグを付け、ホールドを解除する | ジョブのロール | 下の「ロール」 |
| 4 | 30 日待つ。解除は通知される（3.2） | — | — |
| 5 | タグで絞ったライフサイクルのルールを PR で足す。消え終わったら外す | deploy のロール | 今のまま |

- ライフサイクルのルールは常設しない。既存の古い版にはホールドが無い（D7）ので、常設のルールがあると、タグを付けるだけで消える。PR を通すので、承認も二重になる。
- マニフェストはジョブを作るときに ETag で固定される。承認のあとに FullAccess がマニフェストを差し替えても、ジョブは失敗する（差し替えた中身では動かない）。
- 最初に既存の版へホールドをかけるジョブ（作業 8）も、同じロールで流す。PR-3（PassRole の SCP）までは、伊藤が FullAccess で流せる。

**部品:**

| 部品 | 置き場所 | 中身 |
|---|---|---|
| ジョブのロール `original-bucket-lock-batch`（パス `/central/`） | `apps/organization-policy` の中央管理のロール（central-iam-roles.ts） | 信頼: `batchoperations.s3.amazonaws.com`（`aws:SourceAccount` を tuscenes-prod に固定）。権限: 10 本の `bucket/*` への `s3:PutObjectRetention`・`s3:PutObjectTagging`・`s3:PutObjectVersionTagging`（と Get）、置き場の `manifests/*` の読み取り、`reports/*` への書き込み、`sts:AssumeRole` の Deny。`/central/` の下なので、FullAccess は変更できない（SCP `DenyCentralRoleChanges`） |
| SCP の文 `DenyPassLockBatchRole` | `apps/organization-policy` の iam-guardrails.ts | `iam:PassRole`（このロール）を、SSO の AWSAdministratorAccess 以外に Deny |
| マニフェストとレポートの置き場 `original-bucket-cleanup-<アカウント>` | `apps/original-bucket-audit` | `manifests/`（FullAccess が書く）、`reports/`（ジョブが書く）。バージョニング |
| バケットポリシーの直し | `packages/original-bucket-guard` | 2 章の表 |

- 中央管理のロールの型（`CentralIamRole`）は、今は OIDC の信頼しか書けない。サービスの信頼を書けるように型を広げる必要がある（organization-policy の CODEOWNERS の承認が要る）。
- 下書きのポリシー 4 つ（バケットポリシー・SCP・ロールの信頼・ロールの権限）は、IAM Access Analyzer の `validate-policy` で指摘なし（2026-11-05。作業用のファイルは scratchpad の `cleanup-approval/`）。

**これで塞がるもの・残るもの:**

- FullAccess は、解除・古い版の削除・設定の変更ができない。ジョブのロールも渡せない。自分でロールを作ってジョブを流しても、そのロールは `DenyLockChange` の例外ではないので拒まれる。`/central/` の下にロールを作ることも SCP で拒まれる。
- AWSAdministratorAccess も、自分では解除しない（`DenyLockChange` の例外ではない）。ただし、バケットポリシーを書き換えれば外せる（E3 の条件。変更は通知される）。
- 残る穴は 11-04 のまま: deploy のロール（PR でポリシーを書き換える）、root、管理アカウントの管理者。
- **FullAccess も、deploy のロールを引き受ければ、CloudFormation を通してバケットポリシーを書き換えられる**（deploy のロールの信頼は `767397804933:root`。current-state.md の 3.2。2026-11-05 の整合性チェックで指摘）。「FullAccess は設定の変更ができない」は「直接は」に限る。信頼を狭めるのは TODO 24（未着手）。
- 書き込み元が保持の値（`x-amz-object-lock-*`）を明示して書くと、`s3:PutObjectRetention` も要るので、PR-3 の後は `DenyLockChange` に拒まれる。各段階の前に確かめる。
- 承認できるのは AWSAdministratorAccess の 1 名だけ。`Engineers` グループ（2022 年の旧 SCIM の残り）の 山本 修平（CorpIT）。ほかに 1〜2 名いる見込みで、名前は後で確かめる（[current-state.md](current-state.md) の 3.1.1）。割り当てを消さないことを決めごとにし、2 名にするかは BreakGlass の議論に回す。

**確かめること:**

- [ ] `aws:PrincipalArn` で、Batch Operations のジョブのセッションがロールの ARN（パス込み）として照合されるか（カナリアで）。
- [ ] ライフサイクルのタグの条件が、古い版にどう効くか（版ごとのタグで判定されるか）（カナリアで）。
- [ ] 10 本の版に既存のタグがあるか（Batch Operations のタグ付けは丸ごと置き換える）。
- [ ] Batch Operations の `S3PutObjectRetention` で `EventHold: OFF` にできるか（Q6 は `ON` だけ試した）。
- [ ] 保持期限の切れたバージョンに、イベントホールドを付け直せるか（掃除の取りやめ方。2026-11-05）。
- 掃除の取りやめ方と、ライフサイクルを 2 段にする案は、共有用の資料（[notion-worm-governance-rollout.md](../../documents/notion-worm-governance-rollout.md) の 4.2）に書いた（2026-11-05）。

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
| **A. PR-1** | 迂回の Deny（2 章の `DenyGovernanceBypass`）と、通知（3 章）、ジョブのロールとレポートの置き場（2.1）を cdk-apps で入れる | PR（マージは伊藤、deploy は Actions） | 通知がカナリアで鳴ることを確かめる |
| **B. カナリアで予行** | カナリア `original-bucket-canary-767397804933` に、後から Object Lock を有効にする。既定はガバナンス・イベントホールド 1 日。カナリアの exerciser を回す | 伊藤（FullAccess・CLI。手順書を用意する） | 1 章の「まだ試していないこと」3 つ。戻し方（`Rule` を外すと書けるか） |
| **C. 波ごとに鍵をかける** | 各バケットで、(1) 鍵の既定を入れる（ガバナンス・イベントホールド 30 日）、(2) 1 日ほど書き手のエラーを見る、(3) Batch Operations で今の版にホールドをかける、(4) 件数を確かめる | 伊藤（FullAccess・CLI と Batch Operations。ジョブの設定は 2 人で確かめる） | 波ごとに数日 |
| **D. PR-3** | 鍵の操作の Deny（2 章の `DenyLockChange`）、FullAccess を例外から外す（2 章の既存の 2 文）、SCP `DenyPassLockBatchRole`（2.1） | PR | 全部の波のジョブが終わってから |

- ~~PR-2 は書き手の直し（mono-e2e の Cosmos・backend-api と jadd-cli）。手順 C の 4 波の前に要る。~~ → 11-05 に tuscenes-model を外したので要らない。
- **FullAccess を外すのを PR-3 まで待つ理由（11-05 の案）:** B・C は伊藤が FullAccess で行う。PR-1 で FullAccess を外すと、B・C（鍵の既定・ジョブ）を AWSAdministratorAccess の 1 名が行うことになる。そのあいだは 11-04 までの穴（FullAccess が解除・設定の変更をできる）が残るが、解除と設定の変更は通知される。
- カナリアは常設で、Object Lock は外せないが、カナリアは原本と同じ守りを持つべきものなので、外せなくてよい。

### 4.2 波（小さいもの・書き手の問題が無いものから）

| 波 | バケット | 理由 | 前に要るもの |
|---|---|---|---|
| 1 | tuscenes-calibration（新、354 件）、td1-rlog、tuscenes-calibration（旧）、denso-raw | 書き込みが止まっている。件数が少ない | 手順 B |
| 2 | gaming-data-collection、denso-taxi-processed、denso-taxi-video、denso-nx-raw（2026-11-05 に波 1 から移した。Azure から DataSync で毎日転送している） | 書き手が SDK の既定で書く見込み。DataSync（denso）と Databricks の volume は不明 | DataSync を Object Lock のバケットに向けて試す。Databricks の volume の場所の確認。gaming の PC の boto3 の設定（`when_required` にしていないか） |
| 3 | td1-raw、tuscenes-raw | 件数で 9 割（費用の大半）。いちばん大事な原本 | 波 1・2 で問題が無いこと |

2026-11-05 に、tuscenes-model（S3）と tuscenes-annotation（S4）を WORM の対象から外した（[worm-decisions.md](worm-decisions.md) の D2）。もとの波 4（tuscenes-model。PR-2 で書き手を直してから）は無くなった。

### 4.3 戻し方

| 起きたこと | 戻し方 | 確かめ |
|---|---|---|
| 書き手が止まった | そのバケットの鍵の既定（`Rule`）を外す（PR-3 までは FullAccess、その後は AWSAdministratorAccess・CLI）。Object Lock 自体は外せないが、既定が無ければ新しい版に鍵はかからない | 手順 B で「`Rule` を外すとチェックサムなしで書けるか」を確かめる |
| Batch Operations で対象を誤った | 解除のジョブを流せる（PR-3 の後は AWSAdministratorAccess がジョブのロールで。迂回の Deny は解除を止めない。Q3）。解除のあとは 30 日待つ | — |
| Batch Operations で日数を誤った | **解除のジョブでは直せない**（解除すると保持期限が「解除した時刻＋誤った日数」で固まる）。迂回の Deny をいったん外し、迂回の権限を持つロールで保持を付け直すジョブを流す。直したら迂回の Deny を戻す（2026-11-05 の整合性チェック） | 誤りやすいのは日数。ジョブの設定は 2 人で確かめる |
| 通知がうるさい | ルール B のイベント名を絞る（PR） | — |

### 4.4 費用

[worm-design.md](worm-design.md) の 5 章のまま（既存の版へのホールドで一度きり約 $3,900、その記録のデータイベントで約 $650）。通知の部品は月に数ドル以下。

## 5. 書き手の直し（PR-2 の中身）

> **2026-11-05: 要らなくなった。** 止まる書き手はどれも tuscenes-model の書き手で、tuscenes-model を WORM の対象から外した（D2）。下の表は、tuscenes-model に後から WORM をかけるときのために残す。

| 書き手 | 直し方 | 持ち主への連絡 |
|---|---|---|
| Cosmos の checkpoint（mono-e2e `projects/wm_generation/.../boto3_client.py:282`・`utils/object_store.py:29`） | `request_checksum_calculation="when_required"` を消すか `when_supported` にする。Q13 で、既定なら boto3 のどの版も通ることを確かめた | 要（TeamE2E） |
| backend-api の upload_url（`projects/api/backend-api/routers/models.py:1203`、マルチパートは `:420`。クライアントは `:1095`） | **クライアントを SigV4（`signature_version="s3v4"`）にする**。そのうえで、**クライアントから受け取った MD5（か CRC32）を `ContentMD5`（`ChecksumCRC32`）として署名に入れて発行する**。マルチパートはパートごと。11-05 の Q13 の 2 回目で、署名に入れない Content-MD5 は `AccessDenied` で拒まれると分かったので、API の形（リクエストにチェックサムを足す）が変わる | 要（backend-api と jadd-cli の持ち主） |
| jadd-cli（`packages/jadd-cli/src/jadd/model/api.py:151,156,191`） | アップロードの前に MD5（パートごと）を計算して API に渡し、PUT に同じ Content-MD5 を付ける。古い版は書けなくなるので、backend-api の側で最小の版を確かめるか、利用者に上げてもらう | 同上 |

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
6. （11-06）完全削除用の権限を専用に新しく作るか（[worm-decisions.md](worm-decisions.md) の G1）。作るなら、PR-3 の例外と SCP `DenyPassLockBatchRole` の例外を、AWSAdministratorAccess からそれに差し替える。
7. （11-06）SCP・RCP で守る範囲（G2）。PR-3 に何を足すかが変わる。
