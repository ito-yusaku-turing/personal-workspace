# 原本バケットの通知の設計（第三弾の柱 1）

- 作成: 2026-11-17 ／ 伊藤（エージェントが起草）
- 親: [S3 バケットのデータ保護 第三弾](../s3-data-protection-3.md)
- 状態: **案**。届け方（4 章）は伊藤の案が固まった（2026-11-17。チームの合意はまだ。仕様が固まったらチームに共有して合意を取る）。8 章も伊藤の案が出た（11-17。ルール D・E は入れる、見張りは見送り、ログのバケットは通知のあとに設計、OK は送らない）
- 土台: [worm-quickwin-design.md](../done/s3-data-protection-2/worm-quickwin-design.md) の 3 章（2026-11-04 の通知の下書き）。仕組みの説明はそちらを正本にし、ここには 11-04 から変わったことと、台帳（[loophole-ledger.md](loophole-ledger.md)）への当てはめを書く

**要点**

- 台帳のうち、通知で区分 A・B にするのは L1・L2・L4・L5・L10・L12（と、塞がない場合の L13）。今はどれも区分 C。
- 形は 11-04 の下書きのまま。**ルール A**（ホールドの解除）・**ルール B**（バケットの設定の変更）・**ルール C**（通知の部品の変更）を EventBridge に置き、SNS からメールで届ける。置き場は cdk-apps の `apps/original-bucket-audit` の新しいスタック。
- 届け方（4 章、11-17 の伊藤の方針）: **メールは注意を要する通知だけ**（`mlops1@`）、**Slack は `#aws_security_alert` に注意と定期の両方**を流し、注意にはメンションを付ける。
- 11-04 から足すもの: ジョブの作成と状態の変更（I5、決定済み）、**ルール D**（古い版の削除と、拒まれた鍵の操作。案）、**ルール E**（ジョブのロールと deploy の経路の IAM の変更。us-east-1 に置く。案）、トレイルの止め方の通知。見張り（L12）は 11-17 に見送った（5 章）。
- 2026-11-17 に確かめた前提: 通知に要る EventBridge の有効化は、Object Lock の 9 本のうち 8 本で未。既存のルールとぶつかるものは無い（tuscenes-raw の古いルールは止めてある）。管理イベントの通知は、Control Tower の証跡 `aws-controltower-BaselineCloudTrail` に頼る。**この証跡は tuscenes-prod の中にある（組織の証跡ではない）**。止められないかは、管理アカウントの側で確かめる（3.3。11-17 に前提を直した）。

## 1. 何を通知するか（台帳への当てはめ）

| 台帳 | 抜け穴 | 通知 | 通知の後の区分 |
|---|---|---|---|
| L1 | deploy の経路（cfn-exec-role）でのバケットの設定の変更 | ルール B | A |
| L2 | AWSAdministratorAccess（完全削除用の権限） | ルール B（設定の変更）・ルール A（解除）・ジョブ（I5）・ルール D（古い版の削除） | A（名簿の確定が前提。アクション 2-1） |
| L3 | FullAccess（暫定の例外） | L2 と同じ通知が効く | 手順 D で塞ぐ。それまでは B |
| L4 | root・管理アカウントのバケットポリシーの削除 | ルール B（`DeleteBucketPolicy`） | A |
| L5 | ジョブのロールでのホールドの解除 | ルール A・ジョブ（I5）・ルール E（ロールの変更） | A |
| L6〜L9・L19 | 例外を名乗る道（X1〜X3・X5） | 最後のバケットの設定の変更はルール B で気づく。ロールの変更はルール E | 手順 D で塞ぐ。それまでは B |
| L10 | 既存の CDK のスタックの更新（X4） | ルール B | B |
| L11 | GitHub の側の素通り | L1 と同じ（最後の変更はルール B で気づく） | 実質 B（台帳の「決めること」3） |
| L12 | 通知の仕組みを外してから書き換える | ルール C（見張りは見送り。5 章） | 部品を外す操作は B。最後の 1 つを外す操作と、ルールの条件の書き換えは C に残る |
| L13 | 監査ログのバケットの中身を消す | 通知の PR のあとに設計する（6 章） | 未定（C のまま） |

L14（ふつうの削除・上書き）は検知（毎時の報告、柱 4）で扱い、通知の対象にしない。

## 2. 全体の形

```text
us-west-2（tuscenes-prod）
  S3 のイベント（9 本とカナリア。EventBridge を有効にする）
    ルール A: Object Retention Updated・ON でない ──▶ ロググループ ──▶ 警報（1 分に 1 件以上）──┐
  CloudTrail の管理イベント（Control Tower の証跡が届ける）                                                │
    ルール B: 12 本とカナリアの設定の変更、ジョブの作成と状態の変更 ─────────────────────────┤
    ルール C: 通知の部品の変更、original-bucket-audit の証跡の変更 ─────────────────────────┤
  CloudTrail のデータイベント（original-bucket-audit の証跡が届ける）                            ├─▶ SNS ─▶ メール
    ルール D: 古い版の削除、拒まれた鍵の操作 ──▶ ロググループ ──▶ 警報 ──────────────────────┤        （Slack は後で）
                                                                                              │
us-east-1（tuscenes-prod）                                                                    │
    ルール E: ジョブのロール・deploy の経路のロールの IAM の変更 ──▶ SNS（us-east-1）─▶ メール ┘
```

- ルール A と D は件数が跳ねうる（Batch Operations で億の単位）ので、11-04 の下書きのとおり、ロググループに記録して警報でまとめる。B・C・E は件数が少ないので、SNS に直接送る（入力の変換で 1 通にまとめる）。
- 12 本の対象の一覧は `config.ts` の `ORIGINAL_BUCKET_NAMES` を使う。ルール A の対象は `LOCK_TARGET_BUCKETS`（カナリアと 9 本）。新しい一覧（11-04 の下書きの `ALERT_TARGET_BUCKETS`）は作らない。

## 3. ルール（11-04 の下書きからの差分）

### 3.1 ルール A（ホールドの解除）

下書きの 3.2 のまま。対象は 9 本とカナリア。

- **EventBridge の有効化が要るのは 8 本**（2026-11-17、ReadOnly で `get-bucket-notification-configuration` を見た）。有効なのはカナリア・td1-raw・tuscenes-model だけ。下書きの 3.6 の 3 つ目の問いは、これで答えが出た。
- 有効にすると、8 本のすべての作成・削除のイベントが default のバスに流れる。それを受ける既存のルールは、止めてある `tuscenes-NewTripEventRule…`（tuscenes-raw の `metadata.json`）だけ（11-17 に S3 のイベントを受けるルールを全部見た）。datalake の `eventBridgeEnabled: false, // cleaning 処理に必要` のコメントは、この PR で経緯の分かる形に直す（第二弾の TODO 25 の残り）。
- 有効化は、監査のスタックと同じく、バケットを読み込んで `enableEventBridgeNotification()` で足す（Databricks の通知を消さない）。
- **件数が跳ねても、通知は増えない**（2026-11-18、伊藤と確かめた）。1 件ずつは送らず、ロググループに書いて警報にし、`ALARM` になったときだけ送る。`ALARM` のあいだは送り直さず、OK に戻っても送らない（8 章の 6）。Batch Operations で 1 億件を解除しても、届くのは 1 通。
- **警報を、ジョブのロールとそれ以外の主体の 2 本に分ける**（2 段目、11-18）。1 本だと、正当なジョブで鳴り続けているあいだに、別の主体の解除が隠れる。解除してよいのはジョブのロールだけなので、それ以外の主体の警報は 1 件でも鳴らす。S3 のイベントの要求した主体の欄（`detail.requester` の見込み）で分けられるかは、カナリアで確かめる。
- **通知の本文に、Logs Insights の検索へのリンクを入れる**（2 段目、11-18）。警報の通知には、誰が・どのオブジェクトに・何件かが出ないため。
- ロググループの費用: 1 億件の解除で約 100 GB、取り込みは 1 GB あたり約 $0.50 なので 1 回で約 $50。めったに起きないので許容し、保存期間は短くする。

### 3.2 ルール B（バケットの設定の変更・ジョブ）

下書きの 3.3 に、次を足す。

- **ジョブの作成と状態の変更**（I5、決定済み）: `CreateJob`・`UpdateJobStatus`・`UpdateJobPriority`。`requestParameters.bucketName` が無いので、バケットで絞らず、アカウントのすべてのジョブを拾う（ジョブは少ない）。伊藤が流すジョブも鳴るが、区分 A の「使ったら通知が届く」そのもの。
- **対象を 12 本とカナリアに、ジョブのレポートの置き場を足す**（ジョブの記録を消す道）。ログのバケットを足すかは、L13 の設計で決める（6 章）。
- `PutBucketObjectLockConfiguration`（既定の保持設定）は 11-04 から入っている。11-13 の 15 日への付け直しのような操作も鳴る。
- **拒まれた試みはメンションを付けずに送る**（8 章の 10、11-18）。1 段目のルールは成否を問わず 1 本で送っているので、2 段目で `errorCode` の有無（`{"exists": true}`・`{"exists": false}`）でルールを 2 本に分け、文面を変える。

### 3.3 ルール C（通知の部品の変更）

下書きの 3.4 に、次を足す。

- **original-bucket-audit の証跡の変更**: `StopLogging`・`DeleteTrail`・`PutEventSelectors`・`PutInsightSelectors`・`UpdateTrail`。ルール D はこの証跡のデータイベントに頼るため。
- **管理イベントの証跡は、tuscenes-prod の中にある**（2026-11-17 に直した。前は「管理アカウントの組織の証跡なので、tuscenes-prod の中からは止められない」と書いていたが、誤り）。tuscenes-prod で管理イベントを記録しているのは Control Tower の証跡 `aws-controltower-BaselineCloudTrail` だけで、`original-bucket-audit` はデータイベントだけを記録する（11-17、`get-event-selectors`）。この証跡は `IsOrganizationTrail: False`・ホームは us-west-2・全リージョン（11-17、`describe-trails`。[cdk-apps#2614](https://github.com/turingmotors/cdk-apps/pull/2614) のレビューで分かった）。
  - ルール B・C・E は、この証跡に頼る。止められると、まとめて黙る。
  - Control Tower の予防のガードレール（組織のポリシー）が `aws-controltower-*` の証跡の変更を禁じているのがふつうだが、メンバーのアカウントからは確かめられない。**管理アカウントの側で確かめる**（伊藤の判断、11-17）。禁じていなければ、この証跡の `StopLogging`・`DeleteTrail`・`UpdateTrail`・`PutEventSelectors` をルール C に足す。
  - [cdk-apps#2614](https://github.com/turingmotors/cdk-apps/pull/2614) では、説明だけして手当てしない。

### 3.4 ルール D（古い版の削除・拒まれた鍵の操作。新しい案）

11-04 の下書きに無い。L2・L3 の「保護されていない版の削除」と、乗っ取りの下調べに気づくため。

| 拾うもの | 条件 | ねらい |
|---|---|---|
| 版を指定した削除 | `DeleteObject` で `requestParameters.versionId` がある（成否を問わない） | 例外の主体が古い版を消した・消そうとした |
| 拒まれた鍵の操作 | `PutObjectRetention`・`PutObjectLegalHold` で `errorCode` がある | ジョブのロール以外が鍵を触ろうとした |
| 迂回の試み | `x-amz-bypass-governance-retention` を付けた要求（`requestParameters` の欄はカナリアで確かめる） | `DenyGovernanceBypass` に拒まれた試み |

- 元は `original-bucket-audit` の証跡（12 本とカナリアの書き込み系のデータイベント）。EventBridge に届くかは、カナリアで確かめる（Q11 で確かめたのは管理イベントだけ）。
- **ジョブの `PutObjectRetention`（成功）は拾わない**（億の単位で出る）。成功した解除はルール A で拾う。
- ルール A と同じく、ロググループと警報でまとめる。ジョブのロール／それ以外の主体で分けることと、Logs Insights へのリンクも同じ（3.1、11-18）。
- **メンション**（8 章の 10）: 版を指定した削除（成功）の警報には付ける。拒まれた鍵の操作と迂回の試みは、拒まれた操作なので付けない（警報を別にする）。
- `DeleteObjects`（まとめての削除）は、CloudTrail の記録に版の ID が出るかを確かめてから決める。
- ライフサイクルでの失効は CloudTrail に出ないので、ここでは拾えない（L17。ライフサイクルの変更はルール B で拾う）。

### 3.5 ルール E（IAM の変更。新しい案）

ジョブのロール（L5）と deploy の経路のロール（L8・L9）の変更を拾う。手順 D の SCP で塞ぐまでのあいだの気づきになり、塞いだ後も拒まれた試みを拾える。

- IAM のイベントは **us-east-1 の default のバスにしか届かない**ので、このルールと SNS のトピックだけは us-east-1 に置く（同じアプリの別のスタック）。
- 拾う操作: `UpdateAssumeRolePolicy`・`PutRolePolicy`・`AttachRolePolicy`・`DetachRolePolicy`・`DeleteRolePolicy`・`DeleteRole`・`CreateRole`（名前で絞る）。対象は `original-bucket-lock-batch`、`cdk-hnb659fds-*`、GitHub Actions の deploy のロール。

## 4. 届け方（2026-11-17、伊藤の方針）

### 4.1 方針

伊藤の方針（2026-11-17）:

- **メールには、注意を要する通知だけを流す。** 宛先は `mlops@turing-motors.com`（コストアノマリーに揃える。Google グループ `mlops1@` を通って配られる）。
- **Slack には、新しいチャンネル `#aws_security_alert` を作り、注意を要する通知と定期的なモニタリングの情報の両方を流す。** `#aws_cost_monitoring` に倣う。
- **Slack で注意を要する通知には、メンションを付ける。** 相手は Slack のユーザーグループ `@mlops1`（ID `S087DHX478B`。Slack での表示は `@mlops1_all`）。
- **メンションは重要な通知だけに限る**（2026-11-18、伊藤）。注意の通知のうち、どれにメンションを付けるかは 8 章の 10 で決める。
- **`#aws_security_alert` は公開のチャンネルにする。** エンジニアならだれでも見られるようにする。
- **どれも伊藤の個人の案で、チームの合意はまだ。** 仕様が固まったら、チームに共有して合意を取る。

これを、通知を 2 つの重さに分ける形にする。

| 重さ | 中身 | メール（`mlops1@`） | Slack（`#aws_security_alert`） |
|---|---|---|---|
| **注意** | ルール A〜E のすべて、警報が鳴ったこと | 送る | 送る。`@mlops1` をメンションする |
| **定期** | 通知の PR では無い。後で、毎時の報告（柱 4）・ジョブの進みなど | 送らない | 送る。メンションしない |

- ルール B のジョブの作成と状態の変更は、伊藤が流すジョブでも鳴る。件数が少ないので注意のまま送る（区分 A の「使ったら通知が届く」）。うるさければ、ジョブのロールで作ったものだけを定期に下げる。

### 4.2 形

```text
ルール A〜E・警報（EventBridge）
  ├─ 入力の変換（人が読む文）──────────────▶ SNS「注意・メール」──▶ mlops@（→ Google グループ mlops1@）
  └─ 入力の変換（カスタム通知の JSON）────▶ SNS「Slack」──▶ Amazon Q Developer ──▶ #aws_security_alert
```

- **トピックは、メール用と Slack 用に分ける。** Slack 用の SNS には、Amazon Q Developer のカスタム通知の JSON を送る（メンションはこの中に書く）。同じトピックにメールを付けると、メールにその JSON がそのまま届くため。EventBridge のルール 1 つに送り先を 2 つ付け、送り先ごとに入力の変換を変える。
- **警報（ルール A・D）も EventBridge を通す。** 警報の SNS への直接の通知は Slack で決まった形になり、メンションを入れられない。警報の状態の変化（`CloudWatch Alarm State Change`）を EventBridge のルールで受け、上と同じく 2 つの送り先に送る。OK に戻ったときは送らない（8 章の 6）ので、このルールは `ALARM` への変化だけを拾う。
- メールの 1 通の中身は「いつ・誰が（ARN）・何を（eventName）・どのバケットに・拒まれたか（errorCode）」。警報の通知には、Logs Insights のクエリの例を付ける。
- ルール E（us-east-1）も、us-east-1 に同じ 2 つのトピックを置く（SNS から Amazon Q Developer へは、同じリージョンでなくてよい）。

### 4.3 メール

- **宛先は `mlops@turing-motors.com`**（2026-11-17、伊藤の案。コストアノマリーに揃える）。
- **グループのアドレスなので、購読をやめる操作を守る。** SNS のメールには「購読をやめる」のリンクが付き、受け取った人のだれか 1 人が押すと、グループ全体への通知が止まる。購読の確認を `aws sns confirm-subscription --authenticate-on-unsubscribe true` で行い、やめるのに AWS の認証が要る形にする（下書きの 3.5 のまま）。CDK の `EmailSubscription` は確認のメールを送るだけなので、確認は伊藤が CLI で行う手順にする。
- 長くは頂点の群の外へ移す（requirements.md の 7.5.2 の 7）。`mlops1@` のグループのメンバーを、Workspace の管理者が変えられることは受け入れる（区分の上は L20 の範囲）。
- **既存の事例（コストアノマリー）**: tuscenes-prod の購読（`mlops-team`）の宛先は `#aws_cost_monitoring` のチャンネルのメールアドレスだった（2026-11-17、ReadOnly）。`mlops1@` に届いているのは、**管理アカウント `aws+management`（210332786925）の購読**（伊藤が受け取ったメールのヘッダで確かめた）。宛先（`To:`）は `mlops@turing-motors.com` で、Google グループ `mlops1@`（MLOps 1 Team）を通って配られている（`mlops@` はこのグループの別名か、このグループを含むグループとみる。推定）。
- **Google グループで受けるときの注意**:
  - 外の送り手（AWS）からの投稿を、グループが受け付けている（コストアノマリーが届いている）。SNS の送り手（`no-reply@sns.amazonaws.com`）も同じ設定で届く見込み。購読の確認のメールが届くかで確かめる。
  - **迷惑メールとして保留される**ことがある（ヘッダに `X-Spam-Checked-In-Group`）。保留されると、だれにも届かない。グループの設定で、保留せずに配る形になっているかを、グループの管理者（`mlops1+owners@`）に確かめる。
  - グループの記録（`List-Archive`）に、通知が残る。メンバーが後から見られる。

### 4.4 Slack

- **Amazon Q Developer を選んだ理由**（2026-11-17。チームへの説明の正本。PR とチームの資料には短くして入れる）:
  - **秘密を持たない。** Slack に投稿する token は Amazon Q Developer（AWS の側）が持ち、こちらは持たない（取り出せない）。ワークスペースを承認したとき（`#dev_system_info` の設定のとき）に作られ、tuscenes-prod とワークスペースの紐付けとして残っている。token の置き場所・権限・ローテーション・漏れたときの対応が要らない。社内の慣例（Lambda と bot token）では、token を読める人は AWS を通さずに Slack へ直接投稿でき、AWS の側では止められない。（11-17 に「認証情報を持たない」と書いたのは不正確だったので直した）
  - **投稿は必ず AWS の API と IAM を通る。** 入口は SNS のトピックと Slack の設定だけで、どちらも IAM で決まる。Slack の設定の作成・変更は管理イベントとして CloudTrail に残る。トピックへの発行（`sns:Publish`）は SNS のデータイベントで、記録するには設定が要り、1 段目では記録していない（監査の証跡が記録するのは S3 のオブジェクトのデータイベントだけ。Copilot の指摘で直した）。2 段目で、発行を絞るときに記録もあわせて考える。2 段目で、トピックへの発行をこのスタックのルールからだけに絞る。その変更も CloudTrail に残り、ルール C の対象になる。
  - **逆に、IAM で絞るまでは強い権限の人は投稿できる**（11-17、ReadOnly の IAM の試算）。FullAccess（`AdministratorAccess` と原本バケットの削除の拒否）は `sns:Publish` も `chatbot:CreateSlackChannelConfiguration`・`Update…` も持つ。トピックに発行すれば `#aws_security_alert` に任意の文を出せ、Slack の設定を作れば、AWS のアプリを招待したワークスペースのほかのチャンネルにも出せる。手当て: 発行の絞り込み（2 段目）、設定の変更の通知（ルール C）、設定を作れる主体の絞り込み（組織のポリシーで `chatbot:*` を deploy の経路だけにする案。手順 D で決める。新しい論点）。
  - **守る部品が少ない。** 部品はトピックと Slack の設定だけ（慣例の形では Lambda・token・そのロールも要る）。部品が少ないほど、黙らせる道も少ない。
  - 社内の慣例と違うのは、用途が違うため。既存の通知の多くはアプリの運用の知らせで、文面の自由さやメンションの柔軟さが大事。今回は見張りの通知で、偽れないこと・黙らされないことが大事。
  - 受け入れること: 文面は決まった形でフッターが付く。ユーザーグループのメンションは文書に記載が無く、1 段目で確かめる（効かなければ形を変えるか、Lambda と bot token に替える）。
- **Amazon Q Developer in chat applications（旧 AWS Chatbot）で送る。** tuscenes-prod では、Slack のワークスペース `Turing`（`T02B2T6EWNL`）がすでに承認済みで（`ENABLED`）、`tuscenes-notification` の設定が `#dev_system_info` に送っている（2026-11-17、ReadOnly）。11-04 の下書きで心配したワークスペースの承認は、もう要らない。新しく要るのは、`#aws_security_alert` のチャンネルの設定 1 つ（CDK の `SlackChannelConfiguration`。チャンネルの ID が要る）と、チャンネルへのアプリの招待。
- **チャンネルの設定には、通知だけを許す。** この設定のロールとガードレールのポリシーは、Slack からの AWS の操作（コマンド）に効く。通知に権限は要らないので、ロールに何も付けず、ガードレールも空の形（通知だけ）にする。
- **メンションは Slack のユーザーグループ `@mlops1`**（2026-11-17、伊藤の案）。Slack の書き方は `<!subteam^グループの ID>` で、グループの ID（`S` で始まる）が要る。カスタム通知が文書で対応を明記しているのは、ユーザー ID でのメンションだけ（[custom-notifs](https://docs.aws.amazon.com/chatbot/latest/adminguide/custom-notifs.html)）。ユーザーグループが効くかは、チャンネルを作ったらカナリアで試す（7 章）。
  - **Web で調べた結果**（2026-11-17）:
    - 公式の文書が書いているのは、ユーザー ID での `<@userID>` だけ。`title` と `description` で使えて、メンションされた人に通知が届くとある。ユーザーグループ・`@here`・`@channel` には触れていない。
    - 使えたと書いた記事は 1 件ある（[Zenn、GENDA、2025-12-26](https://zenn.dev/genda_jp/articles/20251225-custom-notification-slack-mention)）。`description` にユーザーグループとユーザーのメンションを入れて、成功したとしている。ただ、根拠はスクリーンショットだけで、検証の詳細はない。記事の記法 `<@!subteam^ID>` は Slack の正式な形 `<!subteam^ID>` と違う。グループ ID の取り方も、チャンネル ID と取り違えているように見える。`@here`・`@channel` は「そのまま使えるようです」で、確かめていない。
    - `@here` が `description` で効いたという記事もあるが（[Zenn](https://zenn.dev/yuta28/articles/eventbridge-slack)）、本文は読み込んでいない。
    - まとめると、**ユーザーグループは効く見込みが高いが、公式の保証はない**。カナリアでは `<!subteam^ID>` と `<@!subteam^ID>` の両方を試し、グループの人に通知が届くか（表示だけでなく）を見る。効かなければ、メンバーのユーザー ID を並べる形に替える（メンバーの入れ替えに追随しないのが欠点）。
- **チャンネルは公開**（2026-11-17、伊藤の案）。エンジニアならだれでも見られるようにする。通知には主体の ARN・バケット・キーが載るが、社内の公開のチャンネルに載せてよい範囲とみる（認証情報は載らない）。
- **Slack の経路を外す操作もルール C で拾う。** チャンネルの設定の削除・変更（`chatbot.amazonaws.com` の `DeleteSlackChannelConfiguration`・`UpdateSlackChannelConfiguration`）と、Slack 用のトピックの購読の削除。どのリージョンの EventBridge に届くかは確かめる（7 章）。メールは Slack とは別の経路なので、片方を外されても、もう片方で気づける。

### 4.5 社内の慣例（2026-11-17 に調べた）

メールと Slack に送る仕組みが、今どうなっているか。AWS は tuscenes-prod を ReadOnly で、コードは cdk-apps・mono-turing-infra・databricks-jobs・mono-e2e・identity を読んだ。

**メール**

| 仕組み | どこで | 宛先 |
|---|---|---|
| Cost Anomaly Detection の購読（AWS のサービスが自分で送る） | 管理アカウント（210332786925） | `mlops@`（Google グループ `mlops1@` を通る） |
| 同上 | tuscenes-prod（`mlops-team`） | `#aws_cost_monitoring` のチャンネルのメールアドレス |
| SNS のメールの購読 | tuscenes-prod（us-west-2・us-east-1・ap-northeast-1） | **0 件**。SNS の購読は SQS（Databricks の auto-ingest など）と Lambda だけ |

cdk-apps にも、SNS のメールの購読（`EmailSubscription`）を作るコードは無い。**SNS からグループのアドレスにメールを送るのは、社内では初めて**になる。

**Slack**

| 仕組み | 使っているところ | 認証情報 |
|---|---|---|
| **Lambda から `chat.postMessage`（Slack のアプリの bot token）** | cdk-apps の多く（cache-builder・feature-cache-builder・garuda の自動削除と警報・tesla-fleet-client・tern-api・skypilot・scenario-test・closed-loop・train3dgs・azure-data-sync など）。SNS（警報）か EventBridge から Lambda を起こす | Secrets Manager（`<アプリ>/slack-bot-token` など 12 件）か SSM の SecureString。アプリごとに専用の Slack のアプリを作る例が増えている（Garuda Auto Delete・Train3DGS Notifier）。azure-data-sync は model-converter の token を借りている |
| Incoming Webhook | databricks-jobs の `cost_monitoring`（`#aws_cost_monitoring` の毎日のコストの報告）、video-training-converter、mono-turing-infra の alertmanager（`#gc1-alerts`） | Secrets Manager・ExternalSecret。**databricks-jobs は webhook の URL をコードに直書きしている**（下の注） |
| Amazon Q Developer（旧 AWS Chatbot） | `tuscenes-notification` → `#dev_system_info` の 1 件だけ。CDK の外で作ったもの（ロールが `service-role/aws-chatbot-role`） | 認証情報なし。ガードレールは `ReadOnlyAccess` と `AWSLambdaInvocation` で、チャンネルから AWS の読み取りと Lambda の起動ができる。**使われていない**（2026-11-17）: `#dev_system_info` はアーカイブ済みで、最後の通知は 2025-04-09（伊藤）。購読するトピック 2 本のうち `tuScenesEvents-…` は消えていて、`tuscenes-…`（スタック `tuscenes`）は 90 日間発行 0。設定は `ENABLED` のまま残る（片付けの候補。持ち主は別） |
| メンション | tesla-fleet-client は、決めた警報が `ALARM` になったときだけ `@channel` を付ける。cache-builder は依頼した人を Slack のユーザーに引いてメンションする | — |

**この設計への示唆**

- **Slack の慣例は「Lambda ＋ bot token」**。メンション（`<!subteam^…>`）は `chat.postMessage` なら Slack の仕様どおりに効き、文面も自由に作れる。一方で、bot token を読める主体（Secrets Manager の読み取りを持つ FullAccess など）は、偽の通知を流せ、token を消せば Slack を黙らせられる。Lambda と秘密もルール C の対象に足す必要がある。11-04 の下書きは、外せる主体を減らすために「Lambda と Secrets Manager の鍵は使わない」とした。
- **Amazon Q Developer は、認証情報を持たず部品が少ない**が、社内の例は 1 件だけで、メンションのユーザーグループへの対応が分からない（4.4）。
- どちらにするかは 8 章の 9。

**注（別件）: databricks-jobs の `cost_monitoring/aws-cost-monitoring.py` に、Slack の Incoming Webhook の URL が直書きされ、git の履歴に残っている**（2025-05-07 から）。URL を知っていればだれでも、そのチャンネルに投稿できる。webhook の作り直しと、秘密の置き場（Databricks の secret scope など）への移し替えを、持ち主（安本さん）に伝える。

## 5. 見張り（L12）

**2026-11-17、伊藤の判断で見送った（今回は過剰なケア）。** ルール C で、通知の部品を外す操作の多くは拾える。残るのは、最後の 1 つ（SNS のトピックの削除など）を外す操作と、ルールの条件の書き換えで特定のイベントだけを落とされる場合で、L12 のこの部分は区分 C に残る。

検討した形は次のとおり（再開するときのために残す）。本物と同じ経路を通る事象をカナリアで毎日起こし（ホールドの付け外し・無害な設定の変更・拒まれる削除）、届かなければ鳴らす。判定は、(a) 同じアカウントの警報（26 時間 0 件で鳴らす）か、(b) Control Tower の監査用のアカウントなど別のアカウント。届いたことを毎日 Slack に流せば、来ないこと自体が人の目にも見える。

## 6. ログのバケット（L13）

**2026-11-17、伊藤の判断で決めるのを後にした。通知の PR が済んだら設計する。** 下は、そのときの材料。

監査ログのバケット（`original-bucket-audit-logs-*`）は、古い版を 1 日で消す設定（`noncurrentVersionExpiration: 1 日`）で、ふつうの削除の権限があれば中身を実質消せる（W11）。

- 案 1（塞ぐ）: 原本バケットと同じ守りのバケットポリシー（`packages/original-bucket-guard`）を当て、古い版の期限を延ばす（例 30 日）。通知の PR に入れられる。費用は古い版の保存の分（トレイルのファイルは 1 日に数十 GB。期限を延ばすと、上書き・削除の分だけ増える。実際は上書きしないので、ほぼ増えない見込み）。
- 案 2（B にする）: ルール B・D の対象にログのバケットを足すだけ。
- 起草時の推奨は、案 1 と案 2 の両方（塞いだうえで、設定の変更も通知する）。

## 7. 確かめること（PR の後、カナリアで）

- [ ] 8 本の EventBridge の有効化の後、ルール A が解除（`OFF`）だけを拾い、`ON` を拾わない（ジョブを流しても鳴らない）。
- [ ] ルール B の実際の eventName（`PutBucketLifecycle` か `PutBucketLifecycleConfiguration` か など）。カナリアで 1 回ずつ鳴らす。
- [ ] ジョブの作成と状態の変更が、`AWS API Call via CloudTrail` として届く（eventSource が `s3.amazonaws.com` か）。
- [ ] ルール D のデータイベントが EventBridge に届く。`DeleteObjects` の記録に版の ID が出るか。迂回の要求の欄。
- [ ] ルール E が us-east-1 で届く。
- [ ] 警報の `MatchedEvents` が、送り先がロググループのときに出る（下書きの 3.6 の 2 つ目）。
- [x] Slack のメンション: ユーザーグループ `@mlops1`（`<!subteam^…>`）が、カスタム通知で効くか。→ 効く（11-18、9.1）。
- [ ] Amazon Q Developer の設定の変更が、どのリージョンの EventBridge に届くか（ルール C）。CloudTrail では、作成（`CreateSlackChannelConfiguration`）は us-west-2 に記録された（11-18、9.1）。EventBridge に届くかは 2 段目で確かめる。
- [ ] `--authenticate-on-unsubscribe true` で確認したメールの購読が、メールのリンクから外せないこと。

## 8. 決めること

| # | 決めること | 推奨 |
|---|---|---|
| 1 | 通知の受け手（アクション 4-5） | **伊藤の案（11-17）**: メールは `mlops@turing-motors.com`、Slack は `#aws_security_alert`（新設・公開）、メンションは `@mlops1`。チームの合意はまだ |
| 2 | ~~ルール D（古い版の削除・拒まれた鍵の操作）を入れるか~~ | → **入れる**（11-17、伊藤） |
| 3 | ~~ルール E（IAM の変更、us-east-1）を入れるか~~ | → **入れる**（11-17、伊藤） |
| 4 | ~~見張りを入れるか~~ | → **見送る**（11-17、伊藤。今回は過剰なケア。5 章） |
| 5 | ログのバケットを塞ぐか（L13） | → **後にする**（11-17、伊藤。通知の PR のあとに設計する。6 章） |
| 6 | ~~警報が戻ったとき（OK）にも送るか（I5 の未決）~~ | → **送らない**（11-17、伊藤） |
| 7 | ~~`#aws_security_alert` を公開にするか、非公開にするか~~ | → **公開**（11-17、伊藤の案。エンジニアならだれでも見られる） |
| 8 | ~~Slack で注意の通知にメンションする相手~~ | → **`@mlops1`**（11-17、伊藤の案。効くかはカナリアで試す） |
| 9 | ~~Slack に送る仕組み: Amazon Q Developer か、Lambda ＋ bot token（社内の慣例）か~~ | → **Amazon Q Developer**（11-17、伊藤。1 段目の試しで、ユーザーグループのメンションも効いた。9.1） |
| 10 | ~~注意の通知のうち、どれに `@mlops1` のメンションを付けるか~~ | → **重要な通知だけに付ける**（11-18、伊藤）。**付ける**: 守りを外す・弱める操作で、成功したもの（ホールドの解除、バケットポリシー・Object Lock・バージョニング・レプリケーションの変更、バケットの削除、古い版の削除、通知の仕組みの変更）。ルール A・D の警報にも付ける（警報は鳴ったときに 1 通だけなので、件数が跳ねてもメンションは増えない。3.1・3.4）。**付けない**（Slack には流す）: 守りは外さない操作（Inventory・通知の設定）、伊藤が流すジョブの作成・状態の変更、**拒まれた操作**（`errorCode` があるもの。守りは効いているので、記録として流す） |

## 9. 次

8 章は 11-17 に伊藤の案が出た。次は、仕様をチームに共有して合意を取り、cdk-apps の PR を起草する（アクション 4-9。エージェントが起草、伊藤が PR を作る）。PR に一緒に入れるもの: レポートの置き場をトレイルの対象に足す（[cdk-apps#2500](https://github.com/turingmotors/cdk-apps/pull/2500) のレビュー）、original-bucket-audit のテストを CI で走らせる workflow、datalake の `eventBridgeEnabled: false` のコメントの直し。

### 9.1 1 段目: Slack への経路をカナリアで試す（2026-11-17、伊藤の決定）

- **2 段に分ける。** 1 段目は Slack 用の SNS・Amazon Q Developer の設定・カナリアだけのルール B。メンションと届き方を確かめ、結果を仕様に入れてチームの合意を取る。2 段目でルール A〜E を全バケットに広げる。**メールは今回のスコープから外す**。
- 起草: cdk-apps のブランチ `original-bucket-audit-slack`（commit `0cce70ea`、[cdk-apps#2614](https://github.com/turingmotors/cdk-apps/pull/2614)）。スタック `OriginalBucketNotify`（`lib/notify-stack.ts`）。
  - チャンネルの設定は、ガードレールを省くと `AdministratorAccess` が既定で付く（aws-cdk-lib の `SlackChannelConfiguration` の既定）。すべてを拒むガードレールを付け、ロールには何も付けない。
  - トピックは、ほかのアカウントからの発行を拒む（CDK がルールの送り先に付ける許可は条件なしのため）。
  - **直したこと**: Amazon Q Developer でも、トピックに `sns:Publish` できる主体は偽の通知を流せる。bot token と違い、トピックのポリシーで「このスタックのルールからだけ」に絞れる。1 段目は手でメンションを試すために絞らず、2 段目で絞る。
  - レビュー（11-17、安本さん。Approve）の提案 2 件を取り込んだ（11-18、`c69b5dc2`）。ルールの発行のロールの信頼ポリシーに `aws:SourceArn`（このルールの ARN）と `aws:SourceAccount` の条件を付けた（`iam:PassRole` と `events:PutRule`・`events:PutTargets` を持つ主体が、別のルールにこのロールを付けて発行できないように）。拾う操作に `PutBucketInventoryConfiguration`・`DeleteBucketInventoryConfiguration` を足した（監査の入力を止める操作）。
  - 2 段目への注意（安本さん）: EventBridge は入力の変換で値をエスケープしない。`userAgent`・`errorMessage` のように呼び出し側が決められる値を文面に足すと、JSON が壊れて通知が落ちるか、文面・メンションを差し込まれうる。
- **伊藤がすること（PR の前）**:
  1. `#aws_security_alert` を公開で作り、Amazon Q Developer（旧 AWS Chatbot）のアプリを招待する。
  2. チャンネルの ID（`C…`）と、ユーザーグループ `@mlops1` の ID（`S…`）を控える。`lib/config.ts` に入れる。→ 済み（11-17。チャンネル `C0CJ6HNC21K`、`@mlops1` は `S087DHX478B`）。
  3. PR（[cdk-apps#2614](https://github.com/turingmotors/cdk-apps/pull/2614)、11-17 にエージェントが作った）をマージする（main への push で `original-bucket-audit-deploy` が走る）。
- **deploy の後に試すこと**（FullAccess）:
  1. 入力の変換の `<!subteam^…>` を、EventBridge が受け付けたか（deploy が通れば受け付けた）。
  2. 手で 3 通を発行する。`<!subteam^ID>`・`<@!subteam^ID>`（Zenn の記法）・`<@自分のユーザー ID>`（文書にある形）。`@mlops1` のメンバーに通知が届くか（メンションの一覧に載るか）を見る。

     ```bash
     T=arn:aws:sns:us-west-2:767397804933:original-bucket-alert-slack
     for M in '<!subteam^SXXXX>' '<@!subteam^SXXXX>' '<@UXXXX>'; do
       aws --profile full --region us-west-2 sns publish --topic-arn "$T" --message "$(jq -cn --arg m "$M" \
         '{version:"1.0",source:"custom",content:{textType:"client-markdown",title:"メンションの試し",description:"\($m) 試しの通知（書き方: `\($m)`）"}}')"
     done
     ```

  3. カナリアで、ルール B を鳴らす。`aws s3api put-bucket-versioning --bucket original-bucket-canary-767397804933 --versioning-configuration Status=Enabled`（もう有効なので、何も変わらない）。通知が来るか、`errorCode` が無いときに「エラー」の欄がどう出るか、を見る。**メンションが入力の変換の後も残り、`@mlops1` のメンバーに通知が届くか**も見る（`<!subteam^…>` は入力のテンプレートの変数と同じ `<…>` の形で、EventBridge がそのまま残すかは文書に無い。2 の手での発行では確かめられない。安本さんの指摘）。
  4. チャンネルの設定の作成（`CreateSlackChannelConfiguration`）が、どのリージョンの CloudTrail に出たか（ルール C の置き場所。7 章）。
  5. 3 で通知が届かなかったら: ルールの `FailedInvocations` のメトリクスと、トピックのポリシーで拒まれていないかを見る。ルールは専用のロールでトピックに発行し、`events.amazonaws.com` からの直接の発行はトピックのポリシーで条件なしに拒む（Copilot の指摘で、`aws:SourceArn` の条件に頼る形から 11-17 に替えた。そのキーが EventBridge から SNS への発行に付くかは文書で確かめられなかった）。ロールでの発行が拒まれていないか（ロールのポリシー・トピックのポリシー）と、ロールの引き受けが信頼ポリシーの条件（ルールの ARN・アカウント）で失敗していないかを見る。DLQ はまだ無いので、落ちても黙って途切れる。
- 結果で決めること: メンションの書き方（効かなければ、メンバーのユーザー ID を並べる形か、Lambda と bot token か）。
- **結果（2026-11-18、deploy は 01:18Z。手での発行とカナリアは伊藤が FullAccess で実行）**:
  - deploy は成功し、入力の変換の `<!subteam^…>` も受け付けられた（1）。
  - 手での発行（2）: `<!subteam^S087DHX478B>`（Slack の正式な形）と `<@U07M27J3NK1>`（文書にある個人の形）は、メンションとして効いた。`<@!subteam^…>`（Zenn の記法）は効かず、文字のまま出た。**メンションの書き方は `<!subteam^…>` に決まり**（ルールの文面もこの形）。
  - カナリア（3）: 02:18:33Z の `PutBucketVersioning` が、すぐに届いた。ルールの `Invocations` は 1、`FailedInvocations` は 0。信頼ポリシーの条件の下で、ロールでの発行が通った。入力の変換の後もメンションが残り、`@mlops1_all` として効いた。「誰が」には SSO のロールの arn・type・principalId が出て、本人まで分かる。成功した操作では「エラー」の値は空で、「（無ければ成功した操作）」だけが出る。
  - CloudTrail（4）: Slack の設定の作成（`CreateSlackChannelConfiguration`、呼んだのは `AWSCloudFormation`）は us-west-2 に記録された。us-east-1・us-east-2・ap-northeast-1 には無い。
  - 2 段目で直すこと: `invokedBy` は人の操作では空で、文面に ` `` ` と出る。値が無いときの書き方を考える。「送り元」の行のすぐ後に「Next steps:」が続くのは、Amazon Q Developer の表示の形。
  - **メンションは重要な通知だけに限る**（伊藤）。どれに付けるかは 8 章の 10。

## 10. 通知の文面（2026-11-18）

文面の実装は cdk-apps の `apps/original-bucket-audit/lib/notify-stack.ts`（`addBucketConfigRule()` の `RuleTargetInput.fromObject`）。**ここを文面の正本にし、決めたら実装を合わせる。**

### 10.1 観点（2026-11-18、伊藤）

1. **用語**: この workstream の中でしか使っていない語（例: 原本バケット）は、社内のだれでも分かる語に置き換える。
2. **正式な名称**: 同じ系統の語は、正式な名称にそろえる（例: 「バケット」より「S3 バケット」）。
3. **危険度がすぐ分かる**: 通知を見た人が、事態の危険度をすぐに判別できるようにする。

あわせて、数年後に読む人（この workstream を知らない人）が、通知だけで「何が起きたか・なぜ通知が来たか・何をすればよいか」を分かるようにする。

### 10.2 制約

- **入力の変換には条件の分岐が無い。** 値が無い欄は空のまま出る。文面を変えたいとき（成功と拒否、危険度の違い）は、ルールを分ける。危険度ごとに文面を変えるには、**危険度ごとにルールを分ける**（ルールのイベントパターンで eventName・`errorCode` の有無を分ける）。
- **値はエスケープされない**（[cdk-apps#2614](https://github.com/turingmotors/cdk-apps/pull/2614) のレビュー）。呼び出し側が決められる値（`userAgent`・`errorMessage`）は入れない。
- 日時は UTC のまま（入力の変換で JST に直せない）。
- Amazon Q Developer の表示の形（`nextSteps` の前の「Next steps:」、フッター）は変えられない。

### 10.3 用語の置き換え（案）

| 今の語 | 置き換え（案） | 理由 |
|---|---|---|
| 原本バケット | **保護対象の S3 バケット**（11-18 に決定）。本文で「削除・上書きを防いでいる S3 バケット」と言い換える | 「原本」はこの workstream の語。何を守っているかは本文で説明する |
| バケット | S3 バケット | 観点 2 |
| 誰が | 実行した IAM プリンシパル | CloudTrail の `userIdentity`（API を呼んだ主体）に当たる正式な語 |
| 送り元 | 送信元 IP アドレス | CloudTrail の `sourceIPAddress` |
| 設定の操作 | （題名には操作の結果を書く。下の 10.4） | 「設定の操作」では危険度が分からない |
| エラー | エラーコード（拒否のときだけの文面に出す） | 成功の文面から欄ごと消す |
| eventName | 操作（API 名） | 値は CloudTrail の名前（`PutBucketPolicy` など）のまま |

口調と語の決まり（2026-11-18、伊藤と決めた）:

- **欄の名前と題名は、堅い語の体言止めにする。** 一覧で先頭の数語だけ見て中身が分かるように。題名は「〜を検知」で終える。
- **欄の中の説明文と、読み手に頼む文は、です・ます調のままにする。** 漢語を詰めると、数年後の読み手にかえって読みにくい。1 行目の「意図した操作かを確認してください。」も命令の形にしない。
- **時刻は、何の時刻かで名前を分ける。** 1 件ずつの通知（ルール B など）は操作そのものの時刻なので「発生時刻（UTC）」。警報の通知は警報が `ALARM` になった時刻で、操作はその前の集計の期間に起きているので「検知時刻（UTC）」。「発生時刻」と書くと、その時刻ちょうどでログを絞って最初の操作を取りこぼしうる。
- ルール B と A・D で、同じ欄は同じ名前にそろえる。

| 欄の名前（決定） | 前の案 |
|---|---|
| 発生事象 | 何が起きたか |
| 発生時刻（UTC）（1 件ずつの通知） | 日時（UTC） |
| 検知時刻（UTC）（警報） | いつから（UTC） |
| 判定内容（警報。中身は AWS が書く英語の判定の文） | 件数 |
| ログの格納先 | 記録の置き場 |
| 通知の理由 | なぜ通知が来たか |
| 実行した IAM プリンシパル | 操作した IAM プリンシパル |

### 10.4 危険度（2026-11-18、伊藤の方針）

- **重大**: 保護を外す・弱める操作、取り返しの付かない操作、**公開につながる操作**。公開は当社にとってより危険なので、重大に入れる（伊藤）。
- **通知だけ**: 保護を強める、より安全になる方向の操作。
- 向きが通知から分からない操作（例: `PutBucketPolicy` は強めることも弱めることもできる）は、**重大に倒す**。向きをイベントパターンで分けられるものだけ、安全な向きを通知だけに下げる。

題名の先頭に、色の絵文字と危険度の語を置く。メンションの有無（8 章の 10）と 1 対 1 にする。

| 危険度 | 題名の先頭 | メンション | 当てはまるもの | 読んだ人がすること |
|---|---|---|---|---|
| **重大** | `:red_circle: [重大]` | 付ける | 上の「重大」が成功した | すぐ、操作した人に意図を確かめる |
| **注意** | `:large_yellow_circle: [注意]` | 付けない | 上の「通知だけ」が成功した。ジョブの作成・状態の変更 | 心当たりがなければ確かめる |
| **記録** | `:white_circle: [記録]` | 付けない | 保護に関わる操作が拒否された（保護が効いた） | 対応は不要。繰り返す・心当たりのない主体なら確かめる |

ルール B の操作の分け方（案）:

| 危険度 | 操作 | 理由 |
|---|---|---|
| 重大 | `PutBucketPolicy`・`DeleteBucketPolicy` | 保護を外せる。公開もできる |
| 重大 | `PutBucketObjectLockConfiguration` | 既定の保持設定を短くも長くもできる（向きが分からない） |
| 重大 | `PutBucketLifecycle` | 古い版を失効させるルールを足せる |
| 重大 | `PutBucketVersioning` で `Status` が `Suspended` | バージョニングの停止 |
| 重大 | `DeleteBucket` | 取り返しが付かない |
| 重大（公開） | `PutBucketAcl`・`DeleteBucketOwnershipControls`、`PutBucketOwnershipControls` で `BucketOwnerEnforced` 以外 | ACL での公開につながる（所有権の設定で ACL が有効になる） |
| 重大（公開） | `DeleteBucketPublicAccessBlock`、`PutBucketPublicAccessBlock` で 4 つのどれかが `false` | 公開のブロックを外す |
| 重大 | `PutBucketReplication`・`PutBucketEncryption`・`DeleteBucketEncryption` | 写しを外のアカウントに送れる・暗号化の鍵を替えられる（向きが分からない） |
| 重大（監視） | `PutBucketNotification`・`PutBucketInventoryConfiguration`・`DeleteBucketInventoryConfiguration` | データの保護は外さないが、監視の入力を止められる（伊藤、11-18） |
| 注意 | `PutBucketVersioning` で `Status` が `Enabled` | 強める向き |
| 注意 | `PutBucketPublicAccessBlock` で 4 つとも `true` | 強める向き |
| 注意 | `PutBucketOwnershipControls` で `BucketOwnerEnforced` | 強める向き（ACL を効かなくする） |
| 注意 | `DeleteBucketLifecycle` | 古い版を消すルールも消えるので、保護は弱まらない |
| 注意 | `DeleteBucketReplication` | 写しが止まる。原本は弱まらない |
| 注意 | ジョブの `CreateJob`・`UpdateJobStatus`・`UpdateJobPriority` | 伊藤が流すジョブでも鳴る（区分 A の「使ったら届く」） |
| 記録 | 上のすべてで、`errorCode` があるもの | 保護が効いた |

- 向きを分ける欄の名前は、CloudTrail の記録で確かめた（10.8）。
- オブジェクトの ACL（`PutObjectAcl`）での公開は、ルール B（S3 バケットの設定）では拾わない。所有権の設定が `BucketOwnerEnforced` なら ACL は効かないので、所有権の設定の変更（重大）で気づける。**12 本とカナリアは、すべて `BucketOwnerEnforced`**（2026-11-18、ReadOnly で `get-bucket-ownership-controls`）。

### 10.5 載せる欄（2026-11-18、伊藤の方針）

**アラートを見て「まずい」と思った人が、すぐ調べ始められるように、ログを特定する鍵になる欄を載せる。** 値が無い欄は消さずに、空と分かる表記にする。

| 欄 | 値（CloudTrail の記録） | 何に使うか |
|---|---|---|
| S3 バケット | `requestParameters.bucketName` | |
| 操作（API 名） | `eventName` | |
| 実行した IAM プリンシパル | `userIdentity.arn` | 人・ロールの特定 |
| 種類 | `userIdentity.type` | `AWSService` なら arn が空になる |
| principalId | `userIdentity.principalId` | ロールのセッション名（SSO ではメールアドレス）まで含む |
| invokedBy | `userIdentity.invokedBy` | AWS のサービスが代わりに呼んだとき |
| アクセスキー ID | `userIdentity.accessKeyId` | 同じセッションの、ほかの操作を CloudTrail で引く鍵 |
| 発生時刻（UTC） | `eventTime` | |
| 送信元 IP アドレス | `sourceIPAddress` | |
| リージョン・アカウント | `awsRegion`・`recipientAccountId` | どの CloudTrail を見るか |
| eventID・requestID | `eventID`・`requestID` | その 1 件を CloudTrail・S3 のサーバーアクセスログで引く鍵 |
| エラーコード | `errorCode` | 記録（拒否）の文面だけ |

- `userAgent` は載せない。呼び出し側が自由に決められ、入力の変換でエスケープされないため（10.2）。eventID から引ける。
- **空のときの表記（`-` や `null`）は、入力の変換だけではできない**。文書には既定値の機能が無く、「If you specify a variable to match a JSON path that doesn't exist in the event, that variable isn't created and won't appear in the output.」とだけある（[eb-transform-target-input](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-transform-target-input.html)、2026-11-18 に読んだ）。1 段目では、文字列の中の `invokedBy` は空で出た。手は次のどれか（10.7 の 4）。
  - a. 欄の名前に「（空は値なし）」と添える。実装は今のまま。
  - **b. 値の有無でルールを分ける（`{"exists": false}`）。→ 採用（伊藤、11-18）。** 空になるのは実際には `arn`（AWS のサービスが操作したとき）と `invokedBy`（人が操作したとき）で、`userIdentity.type` が `AWSService` かどうかで 2 本に分ければほぼ足りる。値の無いほうの文面に `-` と書く。危険度の 3 本と掛けて、ルール B は 6 本になる。ほかの欄（`accessKeyId` など）が空になる場合は、カナリアや実際の記録で見つけたら足す。
  - c. ~~文字列の外に置いた変数が `null` になるか~~ → 文書に書かれていない。カスタム通知の欄はどれも文字列なので、文字列の外には置けない。使わない。

### 10.6 ルール B の文面（2026-11-18、口調をそろえた）

**重大（成功）**

```text
題名: :red_circle: [重大] 保護対象の S3 バケットで、保護を外す・弱める操作を検知: <操作>
本文:
<!subteam^…> 意図した操作かを確認してください。
*S3 バケット*: `<bucketName>`
*操作（API 名）*: `<eventName>`
*実行した IAM プリンシパル*: `<arn>`
*種類*: <type>　*principalId*: `<principalId>`　*invokedBy*: `<invokedBy>`
*アクセスキー ID*: `<accessKeyId>`
*発生時刻（UTC）*: <eventTime>
*送信元 IP アドレス*: <sourceIPAddress>
*リージョン・アカウント*: <awsRegion>・<recipientAccountId>
*通知の理由*: この S3 バケットには、消えると取り戻せないデータを置いています。S3 Object Lock・バケットポリシー・バージョニングで、削除と上書きを防いでいます。この操作は、その保護を外す・弱める、またはデータを公開することができます。
次にすること:
- 実行者に、意図した操作であるかを確認
- CloudTrail で eventID `<eventID>`（requestID `<requestID>`）を検索し、要求の内容（requestParameters）を確認
```

- **対応の手順は通知に書かない**。「意図した操作かを確認してください」に留め、手順書へのリンクは Slack のチャンネルのトピックなどに置く（伊藤、2026-11-18）。
- 値が無い欄（AWS のサービスが実行したときの `arn`、人が実行したときの `invokedBy`）は、ルールを分けて `-` と書く（10.5）。
- 「次にすること:」は説明のための書き方で、実際の見出しは Amazon Q Developer が付ける「Next steps:」になる（変えられない）。

**注意（成功）**: 題名を `:large_yellow_circle: [注意] 保護対象の S3 バケットで、保護に関わる設定の変更を検知: <操作>` にし、メンションを外す。「通知の理由」は「この操作は保護を外しませんが、保護や監視の仕組みに関わります。」。次にすることの 1 つ目は「心当たりがなければ、実行者に確認」。

**記録（拒否）**

```text
題名: :white_circle: [記録] 保護対象の S3 バケットへの操作の拒否を検知: <操作>
本文:
保護が効いて、操作は拒否されました。即時の対応は不要です。同じ操作が繰り返される場合や、心当たりのない IAM プリンシパルの場合は、確認してください。
*エラーコード*: `<errorCode>`
（ほかの欄は重大と同じ）
```

### 10.7 決めること（文面）

1. ~~10.3 の置き換え、とくに「保護対象の S3 バケット」でよいか~~ → **保護対象の S3 バケット**（伊藤、11-18）。
2. ~~監視の入力を止める操作を、注意のままにするか、重大に上げるか~~ → **重大**（伊藤、11-18）。
3. ~~「意図しない操作なら」の行き先~~ → 通知には書かない。手順書はチャンネルのトピックなどに置く（伊藤、11-18）。
4. ~~空の欄の表記を、10.5 の a・b のどちらにするか~~ → **b**（伊藤、11-18）。
5. ~~`principalId`・`invokedBy` を外してよいか~~ → 付ける。ログの特定に役立つ欄も足す（伊藤、11-18。10.5）。

### 10.8 向きを分ける欄（2026-11-18、CloudTrail の記録で確かめた）

us-west-2 の `lookup-events`（ReadOnly）で、実際の記録の `requestParameters` を見た。

| 操作 | 欄 | 記録の例 |
|---|---|---|
| `PutBucketVersioning` | `requestParameters.VersioningConfiguration.Status` | `"Enabled"`（11-18 02:18:33Z のカナリアの試し） |
| `PutBucketPublicAccessBlock` | `requestParameters.PublicAccessBlockConfiguration` の `BlockPublicAcls`・`IgnorePublicAcls`・`BlockPublicPolicy`・`RestrictPublicBuckets` | 4 つとも JSON の `true`（11-13・11-18、ほかのアプリのバケット） |
| `PutBucketOwnershipControls` | `requestParameters.OwnershipControls.Rule.ObjectOwnership` | `"BucketOwnerEnforced"`（10-21、`s3-policy-test-…`） |

- イベントパターン:
  - バージョニング: `Status` が `["Suspended"]` なら重大、`["Enabled"]` なら注意。
  - 所有権: `ObjectOwnership` が `["BucketOwnerEnforced"]` なら注意、`[{"anything-but": "BucketOwnerEnforced"}]` なら重大。
  - 公開のブロック: 4 つのどれかが `true` でない（`false`、または欄が無い。欄を省くと `false` 扱い）なら重大。`$or` で 4 つを並べ、それぞれ `[false]` と `[{"exists": false}]` を見る。4 つとも `[true]` なら注意。重大と注意のパターンが、すべての場合を漏れなく分けるかをテストで確かめる。
- `userIdentity` には `onBehalfOf`（Identity Center のユーザー ID）も入っていた（SSO の操作）。`principalId` にメールアドレスが入るので、文面には載せない。
- `invokedBy` は、SSO の操作の記録には欄が無かった（1 段目で空に出た理由）。

### 10.9 ルール A・D の警報の文面（2026-11-18）

#### 警報の分け方

| 警報 | 拾うもの | 元のログ | 危険度 |
|---|---|---|---|
| A-1 ジョブでの解除 | イベントホールドの解除（S3 のイベント `Object Retention Updated` の `event-hold` が `ON` 以外） | S3 のイベント | 重大 |
| A-2 ジョブのロール以外の保持の変更 | `PutObjectRetention`・`PutObjectLegalHold` が成功し、主体がジョブのロール（`original-bucket-lock-batch`）でない | CloudTrail のデータイベント | 重大 |
| D-1 版を指定した削除 | `DeleteObject` で `versionId` があり、成功した | CloudTrail のデータイベント | 重大 |
| D-2 拒否された操作 | 鍵の操作（`PutObjectRetention`・`PutObjectLegalHold`）・版を指定した削除・迂回の試みで、`errorCode` がある | CloudTrail のデータイベント | 記録 |

- **主体で分けるのは、S3 のイベントではできない。** S3 のイベントの `requester` はアカウント ID だけで、主体が分からない（第二弾の [stage2-hourly-report.md](../done/s3-data-protection-2/stage2-hourly-report.md)）。そこで、ジョブのロール以外の主体は、CloudTrail のデータイベントの `userIdentity` で拾う（A-2）。ジョブのロール以外は、バケットポリシーで保持の変更を拒まれるので、A-2 が鳴るのは守りに穴があったときだけ。
- A-2 は、ジョブのロールの成功（億の単位）を拾わない形にする（`userIdentity.sessionContext.sessionIssuer.arn` が `anything-but` ジョブのロール）。Batch Operations の操作がジョブのロールの主体で記録されるか、欄の名前は、カナリアのジョブで確かめる。
- A-1 はジョブでの解除の数を数える。解除してよいのはジョブだけで、使うのは意図して消すとき（D13・D35）だけなので、重大のまま鳴らす（「使ったら届く」）。

#### 警報の通知で取れるもの

警報の通知は、EventBridge の `CloudWatch Alarm State Change` を入力の変換で文面にする（4.2）。取れるのは、警報の名前（`detail.alarmName`）・状態になった時刻（`detail.state.timestamp`）・理由（`detail.state.reason`。AWS が書く文で、しきい値を超えたデータポイントの値＝件数が入る）。**誰が・どのオブジェクトかは、通知には出ない**ので、ロググループと Logs Insights のクエリを本文に書く。

#### 文面

**重大（A-1・A-2・D-1）**

```text
題名: :red_circle: [重大] 保護対象の S3 バケットで、<題名の一文>
本文:
<!subteam^…> 意図した操作かを確認してください。
*発生事象*: <発生事象の説明>
*検知時刻（UTC）*: <state.timestamp>
*判定内容*: <state.reason>
*警報*: `<alarmName>`
*ログの格納先*: CloudWatch Logs のロググループ `<ロググループ名>`（us-west-2・アカウント 767397804933）
*通知の理由*: この S3 バケットには、消えると取り戻せないデータを置いています。S3 Object Lock で、削除と上書きを防いでいます。<警報ごとの理由>
次にすること:
- 実行者に、意図した操作であるかを確認
- CloudWatch Logs Insights で、ロググループ `<ロググループ名>` に次のクエリを実行し、実行した IAM プリンシパルと対象のオブジェクトを確認: `<クエリ>`。操作は検知時刻より前から続いている場合があるので、検知時刻の数分前から検索する
- 警報の継続中は再通知しません。終息したかは、警報 `<alarmName>` の状態で確認
```

| 警報 | 題名の一文 | 発生事象の説明 | 理由 | クエリ（案） |
|---|---|---|---|---|
| A-1 | イベントホールドの解除を検知 | オブジェクトのイベントホールド（S3 Object Lock）が解除されました。 | 解除されたオブジェクトは、15 日後に削除できるようになります。 | `fields @timestamp, detail.bucket.name, detail.object.key, detail.object.version-id \| sort @timestamp desc \| limit 100` |
| A-2 | 想定外の IAM プリンシパルによる保持の変更を検知 | 保持の変更（`PutObjectRetention`・`PutObjectLegalHold`）は、決まったジョブのロールにしか許していません。それ以外の IAM プリンシパルによる変更が成功しました。 | 保護の設定に不備がある可能性があります。 | `fields @timestamp, detail.userIdentity.arn, detail.requestParameters.bucketName, detail.requestParameters.key \| sort @timestamp desc \| limit 100` |
| D-1 | オブジェクトの古い版の削除を検知 | 版を指定した削除（`DeleteObject` の `versionId`）が成功しました。この削除は取り消せません。 | 保護されていない古い版は、権限があれば削除できます。 | `fields @timestamp, detail.userIdentity.arn, detail.requestParameters.bucketName, detail.requestParameters.key, detail.requestParameters.versionId \| sort @timestamp desc \| limit 100` |

**記録（D-2）**: 題名は `:white_circle: [記録] 保護対象の S3 バケットで、オブジェクトの操作の拒否を検知`。メンションを外し、1 行目を「保護が効いて、操作は拒否されました。即時の対応は不要です。同じ操作が繰り返される場合や、心当たりのない IAM プリンシパルの場合は、確認してください。」にする。クエリに `detail.errorCode` を足す。

- 「判定内容」の欄は、AWS が書く判定の文をそのまま出す（例: `Threshold Crossed: 1 out of the last 1 datapoints [3.0 (18/11/26 02:18:00)] was greater than or equal to the threshold (1.0)`）。英語で読みにくいが、件数（`3.0`）と時刻が入る。入力の変換では数だけを取り出せない（伊藤、11-18 に了承）。`detail.state.reasonData` で読みやすくできるかは、カナリアで確かめる。
- Logs Insights のクエリは、コンソールの URL に埋めるとリンクにできるが、URL の書き方が文書化されておらず、壊れやすい。数年後も使えるよう、**クエリの文を本文に書く**。
- `|` は Slack の表示で崩れないかを確かめる（コードの中なので崩れない見込み）。

### 10.10 決めること（A・D）

1. ~~10.9 の警報の 4 本の分け方でよいか。A-1（ジョブでの解除）を重大のまま鳴らすか~~ → **4 本に分け、A-1 は重大のまま**（伊藤、11-18）。
2. ~~「件数」に AWS の英語の文を出すことでよいか~~ → **出す**。欄の名前は「判定内容」（伊藤、11-18）。
3. ~~警報ごとの題名の一文・説明・理由~~ → 口調と欄の名前を決め、10.6・10.9 に反映した（伊藤、11-18。10.3 の「口調と語の決まり」）。

### 10.11 ルール C・E の文面（案、2026-11-18）

どちらも 1 件ずつ送る通知なので、ルール B と同じ形にする（10.6）。違うのは「対象」の欄と、題名の一文・通知の理由だけ。

#### ルール C（通知の仕組みの変更）

3.3 と第二弾の下書き（[worm-quickwin-design.md](../done/s3-data-protection-2/worm-quickwin-design.md) の 3.4）の部品に、1 段目で増えた部品（Amazon Q Developer の設定）と、警報の作り（メトリクスフィルター）を足す。

| 部品 | 拾う操作 | 対象の欄 |
|---|---|---|
| EventBridge のルール | `DeleteRule`・`DisableRule`・`PutRule`・`RemoveTargets`・`PutTargets` | `requestParameters.name`・`rule` |
| CloudWatch の警報 | `DeleteAlarms`・`DisableAlarmActions`・`PutMetricAlarm`・`SetAlarmState` | `requestParameters.alarmName(s)` |
| CloudWatch Logs | `DeleteLogGroup`・`PutRetentionPolicy`・`DeleteMetricFilter`・`PutMetricFilter` | `requestParameters.logGroupName` |
| SNS のトピック | `DeleteTopic`・`SetTopicAttributes`・`AddPermission`・`RemovePermission`・`Unsubscribe`・`SetSubscriptionAttributes`（購読のフィルターで黙らせられる） | `requestParameters.topicArn` |
| Amazon Q Developer の設定 | `DeleteSlackChannelConfiguration`・`UpdateSlackChannelConfiguration` など（us-west-2 に記録される。9.1） | `requestParameters.chatConfigurationArn` |
| 証跡（original-bucket-audit） | `StopLogging`・`DeleteTrail`・`UpdateTrail`・`PutEventSelectors`・`PutInsightSelectors` | `requestParameters.name` |

- 欄の名前（とくに `alarmName` と `alarmNames`、Amazon Q Developer の欄）は、記録で確かめてから書く。
- 危険度: 成功はすべて**重大**（監視を止められる。向きの分かる操作が無いので、重大に倒す）。拒否は**記録**。
- 題名の一文: `通知の仕組みの変更を検知: <操作>`。通知の理由: 「この部品は、保護対象の S3 バケットへの操作を通知する仕組みの一部です。変更されると、以後の通知が届かなくなる場合があります。」
- **限界**（下書きのまま）: SNS のトピックそのものを消されると、その通知は届かない。ルール C を消す操作は、C 自身では拾えない場合がある。

#### ルール E（IAM の変更、us-east-1）

3.5 の対象に、1 段目で増えた IAM の部品（ルールの発行のロール、Amazon Q Developer の設定のロール、ガードレールの管理ポリシー）を足す。

| 対象 | 拾う操作 | 対象の欄 |
|---|---|---|
| ロール（ジョブのロール `original-bucket-lock-batch`、`cdk-hnb659fds-*`、GitHub Actions の deploy のロール、通知のロール） | `CreateRole`・`DeleteRole`・`UpdateAssumeRolePolicy`・`PutRolePolicy`・`DeleteRolePolicy`・`AttachRolePolicy`・`DetachRolePolicy`・`PutRolePermissionsBoundary`・`DeleteRolePermissionsBoundary` | `requestParameters.roleName` |
| 管理ポリシー（ガードレール） | `CreatePolicyVersion`・`SetDefaultPolicyVersion`・`DeletePolicy` | `requestParameters.policyArn` |

- 危険度: 成功はすべて**重大**（ロールの信頼関係や権限を広げられる。向きが分からない）。拒否は**記録**。
- 題名の一文: `保護に関わる IAM ロール・ポリシーの変更を検知: <操作>`。通知の理由: 「この IAM ロール・ポリシーは、保護対象の S3 バケットの保護の解除、または変更の通知に使います。変更されると、保護を外す権限を得られる、または通知が届かなくなる場合があります。」
- ロール名の欄は前方一致で絞る（`cdk-hnb659fds-` など。CDK が付けるロール名の後ろの乱数のため）。

#### deploy で鳴る通知の多さ（決めること）

ルール C・E の対象は、どれも CDK のスタックで作っている。**このスタックを deploy するたびに、`PutRule`・`PutTargets`・`PutMetricAlarm`・`PutRolePolicy` などが十数件まとめて鳴り、すべてメンション付きの重大になる。** ルール B も、保護対象の S3 バケットのバケットポリシーを持つスタックの deploy で鳴る。

- 案 1: そのまま重大で鳴らす（「使ったら届く」）。deploy は PR のマージの後だけで、頻度は低い。ただし、一度に十数件のメンションが飛ぶ。
- 案 2: deploy の経路（CloudFormation の実行のロール `cdk-hnb659fds-cfn-exec-role-*`、`invokedBy` が `cloudformation.amazonaws.com`）による成功は、**注意**（メンションなし）に下げる。deploy の経路は PR のレビューとマージを通る（L1）。ただし、GitHub の側の素通り（L11）や、手元からの `cdk deploy` も同じ経路に見えるので、その分はメンションが付かない。
- 案 3: deploy の経路による成功は、1 件ずつではなく、ルール A・D のように警報で 1 通にまとめる。

### 10.12 決めること（C・E）

1. ルール C・E の成功をすべて重大にすることでよいか。
2. deploy で鳴る通知の多さを、案 1〜3 のどれで扱うか。

