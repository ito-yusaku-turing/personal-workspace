# 通知の 3 本目の PR の設計（警報でまとめる通知）

- 書いた日: 2026-11-19（案）。同日に Fable の意見をもらい、伊藤が 8 章を決めた
- 前提の PR: [cdk-apps#2643](https://github.com/turingmotors/cdk-apps/pull/2643)（1 件ずつ送る通知の形。レビュー中）。3 本目は #2643 のマージの後に、新しいブランチで起こす
- 仕様の正本は cdk-apps の `apps/original-bucket-audit/docs/notifications.md` と `lib/alert-catalog.ts`。この資料は 3 本目の起草までの設計と、決めることを置く
- 元の設計: [notification-design.md](notification-design.md) の 3.1・3.4・10.9〜10.10。ここで変えたところは、各節に書く

## 1. 範囲

| # | 中身 | 形 |
|---|---|---|
| 1 | オブジェクトの操作を、警報でまとめて送る（A-1・A-2・D-1・D-2） | 新しい形（警報） |
| 2 | CloudWatch の警報・Logs の変更の通知。#2643 で外した 8 操作を、`notify-critical-input` の行に戻す（新しい部品の分も足す） | 今の形（1 件ずつ） |
| 3 | S3 Batch Operations のジョブの作成・状態の変更の通知（重大。伊藤、11-19） | 今の形（1 件ずつ）。新しい行 |

範囲の外（決まったこと）:

- deploy の経路を警報でまとめることは、しない（11-19、案 2。#2643 で決定にした）。
- 対象はカナリアだけ。データ保護対象の 9 本への展開は 4 本目。

## 2. カナリアで確かめたこと（2026-11-19）

`~/runbook/alert-event-probe/alert-event-probe.sh`（伊藤が FullAccess で実行、エージェントが ReadOnly で読んだ）。

| 確かめたこと | 結果 |
|---|---|
| 監査の証跡 `original-bucket-audit` のデータイベントが EventBridge に届くか | 届く（`AWS API Call via CloudTrail`、数秒） |
| 保持の変更・リーガルホールドの記録の名前 | `PutObjectLockRetention`・`PutObjectLockLegalHold`（API 名と違う） |
| ジョブの操作の主体 | `sessionIssuer.userName` = `original-bucket-lock-batch`、`invokedBy` = `batchoperations.s3.amazonaws.com` |
| ホールドの解除の記録 | CloudTrail: `additionalEventData.objectRetentionInfo.retentionInfo.eventHold` が `OFF`。S3 のイベント: `Object Retention Updated` で `object-retention-event-data.event-hold` が `OFF`（主体はアカウント ID だけ） |
| ジョブでのホールドの付与 | `PutObjectLockRetention` の成功に `objectRetentionInfo.retentionInfo.eventHold: "ON"`（`eventHoldDuration` も）が付く（2026-11-19、`alert-event-probe.sh hold`。監査の証跡のログで確かめた） |
| 人の書き込み（`PutObject`） | `objectRetentionInfo`（`eventHold: ON`）が付く。操作の名前で絞る必要がある |
| 版を指定した削除の成功 | `DeleteObject` で `requestParameters.versionId` があり、`errorCode` が無い。削除マーカーの版を消した操作は `responseElements.x-amz-delete-marker` が `"true"`・`additionalEventData.objectSize` が 0 で見分けられる（Fable の指摘。実の版の削除の記録は未採取。今日の版は 12-04 に消せるようになる） |
| ホールド中の版の削除 | `AccessDenied`。`errorMessage` は「object protected by object lock」 |
| 迂回（`--bypass-governance-retention`）の試み | 欄に出ない。`errorMessage` の文（`s3:BypassGovernanceRetention` … explicit deny）だけが違う |
| 人による保持の変更・リーガルホールド | 守りのバケットポリシーで `AccessDenied` |
| まとめての削除（`DeleteObjects`） | **CloudTrail では中身が見えない**。`requestParameters.delete` は空、版もキーも出ない。1 件ずつの拒否も `errorCode` に出ない（応答は 200） |
| `DeleteObjects` の成功を S3 のイベントで | `Object Deleted` が 1 件ずつ届く（`deletion-type` = `Permanently Deleted`、`reason` = `DeleteObject`、版の ID あり。主体はアカウント ID だけ） |
| 削除マーカーの作成・版の削除の区別（S3 のイベント） | `Delete Marker Created` と `Permanently Deleted` で分かれる。削除マーカーの版の削除は `etag` が無い形（実の版の削除に `etag` が付くかは確かめていない） |

## 3. 警報の作り

```text
EventBridge のルール original-bucket-alert-<警報>（CloudTrail のデータイベント・S3 のイベント。カナリアだけ）
  ├─▶ 指標 AWS/Events の MatchedEvents（RuleName ごと。EventBridge が出す）
  │     └─▶ CloudWatch の警報 original-bucket-alert-<警報>（1 分に 1 件以上で ALARM）
  │           └─▶ EventBridge のルール（CloudWatch Alarm State Change、ALARM になったときだけ）
  │                 └─▶ 入力の変換 → SNS のトピック original-bucket-alert-slack → Slack
  └─▶ CloudWatch Logs のロググループ original-bucket-alert-<警報>（調べるための置き場。保存は短く）
```

- **警報は、EventBridge が出すルールごとの一致の件数（`AWS/Events` の `MatchedEvents`）に掛ける**（Fable の M1、伊藤が了承）。1 分の粒度で数えられることを、カナリアの受け口のルールで確かめた（11-19。08:36 の 8 件・08:37 の 1 件・08:41 の 2 件が、操作の数と合った）。遅れは測っていない。メトリクスフィルターは使わない。ロググループやそのリソースポリシーを壊されても、警報は鳴る（失うのは調べるための記録だけ）。D-1 のように元が 2 つあるときは、ルール 2 本の指標を metric math で足す。1 分の粒度と遅れは、起草の前に確かめる。
- **件数が跳ねても、通知は 1 通**（11-18 に決めた）。ALARM のあいだは送り直さず、OK に戻っても送らない。期間は 1 分、評価は 1 回、データが無いときは「超えていない」とみなす。静かな 1 分の後に OK に戻るので、次の操作はまた届く。
- 警報の状態の変化を拾うルール: `source` が `aws.cloudwatch`、`detail-type` が `CloudWatch Alarm State Change`、`detail.alarmName` が警報の名前の完全一致、`detail.state.value` が `ALARM`。
- 警報の通知は、Amazon Q Developer の既定の警報の表示ではなく、EventBridge の入力の変換でカスタム通知にする（メンションを入れるため）。
- 部品の名前は、すべて `original-bucket-alert-` で始める。発行のロールの信頼ポリシー（前方一致）と、通知の仕組みの変更の見張り（5 章）にそのまま入る。
- ロググループへ書くには、CloudWatch Logs のリソースポリシーで `events.amazonaws.com` に書き込みを許す。**CDK の `targets.CloudWatchLogGroup` は使わない。** 今の aws-cdk-lib（2.260.0）では、ルールごとにカスタムリソース（`LogGroupResourcePolicy`。Lambda で `PutResourcePolicy` を呼ぶ）を作るため（ソースで確かめた、11-19）。Lambda を使わない方針に外れ、ポリシーの名前もこちらで決められない。代わりに、`logs.ResourcePolicy`（名前は `original-bucket-alert-events`）を 1 つ置き、ルールの送り先はロググループの ARN を返すだけの小さな送り先で付ける。
- 費用: ロググループの取り込みは、正当なジョブで 1 億件を解除すると約 100 GB（約 $50）。めったに起きないので許容する（11-18）。保存期間は短くする。

## 4. 警報の分け方（案）

| 警報 | 拾うもの | 元 | 危険度 | 元の設計からの変更 |
|---|---|---|---|---|
| A-1 ジョブでのホールドの解除 | `PutObjectLockRetention` の成功で、`objectRetentionInfo.retentionInfo.eventHold` が `OFF`（条件の書き方は下）、主体がジョブのロール | CloudTrail | 重大 | **S3 のイベントから CloudTrail に移す**（決めた） |
| A-2 ジョブのロール以外による保持の変更 | `PutObjectLockRetention`・`PutObjectLockLegalHold` の成功で、主体がジョブのロールでない（`sessionIssuer.userName` が無い記録も含める） | CloudTrail | 重大 | 記録の名前を直した。解除かどうかを問わない（ジョブのロール以外の変更は、守りのバケットポリシーで拒まれるはずなので、成功したら守りに穴がある） |
| D-1 版の削除 | `DeleteObject` の成功で `versionId` がある（CloudTrail）と、S3 のイベントの `Object Deleted`（`deletion-type` が `Permanently Deleted`） | CloudTrail＋S3 のイベント | 重大 | `DeleteObjects` が CloudTrail で見えないので、S3 のイベントも元にする（決めた） |
| D-2 拒否されたオブジェクトの操作 | `PutObjectLockRetention`・`PutObjectLockLegalHold`、`versionId` のある `DeleteObject` で、`errorCode` がある。迂回の試みも入る | CloudTrail | 記録 | 拒否されたまとめての削除は拾えない（限界） |

- **A-1 と A-2 は重ならない**（主体がジョブのロールか、そうでないかで分ける）。ジョブのロールのホールドの付与（`eventHold` が `ON`）は拾わない（億の単位で出る）。
- **A-2 の「ジョブのロールでない」は、`anything-but` に `{ "exists": false }` を並べる。** `sessionIssuer` の無い IAM ユーザー・root の記録を落とさないため（#2643 の再レビューの教訓）。`sessionIssuer.userName` は IAM に登録された名前がそのまま残るので、大文字・小文字の心配は無い。
- **A-1 の `eventHold` の条件**: `["OFF"]` だと、欄の無い成功した変更が A-1 にも A-2 にも当たらず黙る。「`ON` 以外＋欄なし」だと、ジョブでの付与の記録に欄が無かった場合に億の単位で鳴る。→ **「`ON` 以外＋欄なし」にする。** ジョブでの付与の記録に `eventHold: "ON"` が付くことを確かめた（11-19）ので、付与で鳴ることはない。成功した保持の変更には、解除・付与とも欄が付いていた。
- **D-1 の対象**: 削除マーカーの版の削除も入る（データは消えない）。CloudTrail では `x-amz-delete-marker` で見分けられる見込みだが、**今は分けずに重大で流す**（伊藤。データ保護対象は、ふだん削除の操作が行われないバケットを選んでいる）。12-04 以降に実の版の削除の記録を採ってから見直す。
- D-1 の件数は、同じ削除が 2 つの元から数えられるので「おおよそ」になる。
- **D-2 で迂回かどうかを分けるか**: `errorMessage` で分けられるが、`errorMessage` は通知に載せない。分けないで、Logs Insights のクエリで `errorMessage` を見る形にする（案）。
- 警報の名前は、警報の通知に載せてよい。警報の状態の変化のイベントは、名前の完全一致で拾い、名前はこちらで決めたものだけになるため（#2643 で「警報の名前を載せない」としたのは、呼び出し側が警報を作る操作の通知のこと）。

## 5. 1 件ずつの通知に足すもの

**通知の仕組みの変更（`notify-critical-input`）**

- 戻す: `PutMetricAlarm`・`DeleteAlarms`・`SetAlarmState`（CloudWatch の警報）、`DeleteLogGroup`・`PutRetentionPolicy`（CloudWatch Logs）。メトリクスフィルターは使わないので、`PutMetricFilter`・`DeleteMetricFilter` は要らない。source に `aws.cloudwatch`・`aws.logs`。
- 足す: CloudWatch Logs のリソースポリシーの `PutResourcePolicy`・`DeleteResourcePolicy`。`requestParameters` は `policyName` の形と `resourceArn`（ロググループ単位）の形があるので、両方を `$or` で拾う（Fable の M3）。消されると調べるための記録が止まる（警報は 3 章の形なので止まらない）。
- 戻さない: `DisableAlarmActions`（通知は警報のアクションでなく状態の変化のイベントで送るので、止めても通知は止まらない。Fable の M4）。`DeleteAlarms` の対象の欄は配列の `alarmNames` なので、`$or` に枝を足す。
- 警報の名前は、対象の欄に載せない（#2643 の決まりのまま）。
- イベントパターンの大きさ: graph226 さんの計算では、入力と出口を 1 行にしても約 1,466 文字。入力の行だけなら上限（2048）に収まる見込み。`checkPatternSize` が確かめる。

**ジョブの作成・状態の変更（新しい行）**

- `CreateJob`・`UpdateJobStatus`・`UpdateJobPriority`。管理イベント、source は `aws.s3`、us-west-2。
- バケットで絞らない（記録に `bucketName` が無い）。アカウントのすべてのジョブを拾う（90 日で `CreateJob` 27 件・`UpdateJobStatus` 17 件）。
- 危険度は重大（伊藤、11-19）。すべてのジョブを拾う（ジョブのロールの `RoleArn` で絞る案・サービスのイベント `JobCreated`・`JobStatusChanged` を使う案は採らない。ほかのロールのジョブにも気づけるように。伊藤、11-19）。deploy で作るものではないので、`deploySeverity` は書かない（ルールは成功・失敗の 2 本）。
- **対象の欄は載せない**: 記録にジョブの ID が無い（`UpdateJobStatus` の `requestParameters` は `requestedJobStatus` と `Host` だけ）。`CreateJob` の中身（説明・ロールの ARN など）は呼び出し側が決める値。→ #2643 で外した `target.omitted`（載せない理由を書く欄）を戻し、「-（ジョブの ID は記録に無い。eventID から確認）」と書く。
- ほかのリージョンで作ったジョブは拾わない。ジョブは対象のバケットと同じリージョンで作る必要がある見込み（確かめていない）。

## 6. 警報の通知の文面

元の設計の 10.9 の形を引き継ぎ、語を直す（「保護対象」→「データ保護対象」）。

```text
題名: :red_circle: [重大] データ保護対象の S3 バケットで、<題名の一文>
本文:
<!subteam^…> 意図した操作かを確認してください。
*発生事象*: <発生事象の説明>
*検知時刻（UTC）*: <state.timestamp>
*警報*: `<alarmName>`
*ログの格納先*: CloudWatch Logs のロググループ `<ロググループ名>`（us-west-2・アカウント 767397804933）
*通知の理由*: <警報ごとの理由>
次にすること:
- 実行者に、意図した操作であるかを確認
- CloudWatch Logs Insights で、ロググループ `<ロググループ名>` に次のクエリを実行し、実行した IAM プリンシパルと対象のオブジェクトを確認: `<クエリ>`。操作は検知時刻より前から続いている場合があるので、検知時刻の数分前から検索する
- 警報の継続中は再通知しません。終息したかは、警報 `<alarmName>` の状態で確認
```

- **判定内容（`state.reason`）は載せない**（Fable の H2、伊藤が了承）。`SetAlarmState` で呼び出し側が理由の文を決められ、入力の変換はエスケープしないため。件数は Logs Insights で見る。
- クエリの欄の名前は、確かめた記録に合わせる（`detail.userIdentity.sessionContext.sessionIssuer.userName`・`detail.requestParameters.key`・`detail.requestParameters.versionId`・`detail.errorMessage` など）。`userIdentity.arn` は使ってよい（クエリはこちらが書く文で、値は Logs Insights の画面に出るだけ。入力の変換を通らない）。
- 記録（D-2）は、メンションを外し、1 行目を「保護が効いて、操作は拒否されました。…」にする（10.9 のまま）。

## 7. 限界（3 本目の時点）

- **まとめての削除（`DeleteObjects`）は、CloudTrail では見えない。** 決めること 2 の (b) なら、版の削除も拒否も届かない。(a) でも、拒否は届かず、成功の主体は分からない。
- 削除マーカーの版の削除も、D-1 の重大で届く（今は分けない）。
- 何度も繰り返される拒否（D-2）では、警報が ALARM と OK を往復し、そのたびに届く。逆に、OK に戻るまでの間に起きた操作は届かない。
- ジョブのロールによる `PutObjectLockLegalHold` の成功は、どの警報にも入らない（ロールに権限が無いので、拒否なら D-2 に入る）。
- ライフサイクルでの失効は CloudTrail に出ない（ライフサイクルの変更は 1 件ずつの通知で拾う）。
- 警報の ALARM のあいだに起きた別の操作は、通知されない（同じ警報の中では 1 通）。
- データイベントの EventBridge への配送は、CloudTrail の配送に頼る（遅れ・取りこぼしの保証は無い）。
- 警報・ロググループ・メトリクスフィルターを消す・止める操作は、1 件ずつの通知で届く。ただし、その操作で止まった警報の分は以後届かない（#2643 の「自分を止める操作」と同じ種類）。

## 8. 決めたこと（2026-11-19、伊藤）

1. **A-1 を CloudTrail に移す。** 利点は、主体でジョブのロールとそれ以外に分けられること（A-2 と重ならない）。8 本の EventBridge の有効化は、2 で S3 のイベントを使うので、4 本目で結局要る（Fable の指摘で理由を直した）。
2. **D-1 は (a)**: 3 本目で、カナリアの S3 のイベント（`Object Deleted`・`Permanently Deleted`）も元にする。S3 コンソールの削除は `DeleteObjects` を使う見込みで、CloudTrail だけでは漏れるため。
3. **削除マーカーの版の削除も、今は重大で流す。** 12-04 以降に実の版の削除の記録を採って、見分けられるかを確かめる。
4. **D-2 で迂回の試みを分けない。** クエリで見る。
5. **CloudWatch Logs のリソースポリシーの変更を見張る**（2 つの形）。
6. **警報はメトリクスフィルターでなく `AWS/Events` の `MatchedEvents` に掛ける。判定内容は載せない。ジョブはすべて重大。`DisableAlarmActions` は戻さない。**

起草の前に確かめること: 済んだ（11-19）。ジョブでの付与の記録・`MatchedEvents` の 1 分の粒度・CDK の送り先の作り（3・4 章）。`MatchedEvents` の遅れは測っていない。
