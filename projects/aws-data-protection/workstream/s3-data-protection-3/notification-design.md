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

### 3.2 ルール B（バケットの設定の変更・ジョブ）

下書きの 3.3 に、次を足す。

- **ジョブの作成と状態の変更**（I5、決定済み）: `CreateJob`・`UpdateJobStatus`・`UpdateJobPriority`。`requestParameters.bucketName` が無いので、バケットで絞らず、アカウントのすべてのジョブを拾う（ジョブは少ない）。伊藤が流すジョブも鳴るが、区分 A の「使ったら通知が届く」そのもの。
- **対象を 12 本とカナリアに、ジョブのレポートの置き場を足す**（ジョブの記録を消す道）。ログのバケットを足すかは、L13 の設計で決める（6 章）。
- `PutBucketObjectLockConfiguration`（既定の保持設定）は 11-04 から入っている。11-13 の 15 日への付け直しのような操作も鳴る。

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
- **Slack で注意を要する通知には、メンションを付ける。** 相手は Slack のユーザーグループ `@mlops1`。
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
- [ ] Slack のメンション: ユーザーグループ `@mlops1`（`<!subteam^…>`）が、カスタム通知で効くか。
- [ ] Amazon Q Developer の設定の変更が、どのリージョンの EventBridge に届くか（ルール C）。
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
| 9 | Slack に送る仕組み: Amazon Q Developer か、Lambda ＋ bot token（社内の慣例）か | 4.5 を見て決める |

## 9. 次

8 章は 11-17 に伊藤の案が出た。次は、仕様をチームに共有して合意を取り、cdk-apps の PR を起草する（アクション 4-9。エージェントが起草、伊藤が PR を作る）。PR に一緒に入れるもの: レポートの置き場をトレイルの対象に足す（[cdk-apps#2500](https://github.com/turingmotors/cdk-apps/pull/2500) のレビュー）、original-bucket-audit のテストを CI で走らせる workflow、datalake の `eventBridgeEnabled: false` のコメントの直し。

### 9.1 1 段目: Slack への経路をカナリアで試す（2026-11-17、伊藤の決定）

- **2 段に分ける。** 1 段目は Slack 用の SNS・Amazon Q Developer の設定・カナリアだけのルール B。メンションと届き方を確かめ、結果を仕様に入れてチームの合意を取る。2 段目でルール A〜E を全バケットに広げる。**メールは今回のスコープから外す**。
- 起草: cdk-apps のブランチ `original-bucket-audit-slack`（commit `0cce70ea`、[cdk-apps#2614](https://github.com/turingmotors/cdk-apps/pull/2614)）。スタック `OriginalBucketNotify`（`lib/notify-stack.ts`）。
  - チャンネルの設定は、ガードレールを省くと `AdministratorAccess` が既定で付く（aws-cdk-lib の `SlackChannelConfiguration` の既定）。すべてを拒むガードレールを付け、ロールには何も付けない。
  - トピックは、ほかのアカウントからの発行を拒む（CDK がルールの送り先に付ける許可は条件なしのため）。
  - **直したこと**: Amazon Q Developer でも、トピックに `sns:Publish` できる主体は偽の通知を流せる。bot token と違い、トピックのポリシーで「このスタックのルールからだけ」に絞れる。1 段目は手でメンションを試すために絞らず、2 段目で絞る。
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

  3. カナリアで、ルール B を鳴らす。`aws s3api put-bucket-versioning --bucket original-bucket-canary-767397804933 --versioning-configuration Status=Enabled`（もう有効なので、何も変わらない）。通知が来るか、`errorCode` が無いときに「拒否」の欄がどう出るか、を見る。
  4. チャンネルの設定の作成（`CreateSlackChannelConfiguration`）が、どのリージョンの CloudTrail に出たか（ルール C の置き場所。7 章）。
  5. 3 で通知が届かなかったら: ルールの `FailedInvocations` のメトリクスと、トピックのポリシーで拒まれていないかを見る。ルールは専用のロールでトピックに発行し、`events.amazonaws.com` からの直接の発行はトピックのポリシーで条件なしに拒む（Copilot の指摘で、`aws:SourceArn` の条件に頼る形から 11-17 に替えた。そのキーが EventBridge から SNS への発行に付くかは文書で確かめられなかった）。ロールでの発行が拒まれていないか（ロールのポリシー・トピックのポリシー）を見る。DLQ はまだ無いので、落ちても黙って途切れる。
- 結果で決めること: メンションの書き方（効かなければ、メンバーのユーザー ID を並べる形か、Lambda と bot token か）。
