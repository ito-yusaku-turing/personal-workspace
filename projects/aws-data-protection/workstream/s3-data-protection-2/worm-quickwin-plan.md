# 原本バケットの WORM 化: Quick Win プラン

- 作成: 2026-11-02 ／ 伊藤
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)・[全体の状態と要件](requirements.md) の 8 章（課題 K6）
- 状態: **作戦を決めた段**（2026-11-02）。次は 4 章の作業の順番を決めて、試しの準備から

権限の設計（2 人目の確認・専用の経路）が固まるのを待たず、最小限の設計で WORM を先に入れる。穴があることは承知のうえで、誤操作と、いちばん大きい穴（ふつうの PR でライフサイクルから大量に消える）を先に塞ぐ。権限の設計が固まったら、フルスペックに差し替える。

## 1. 位置づけ

| 段 | 中身 | いつ |
|---|---|---|
| **Quick Win**（この資料の本体） | ガバナンスモードで 12 本に鍵をかける。解除はすぐに通知する。解除できる人は今の例外の主体のまま。穴は認識して受け入れる | 権限の設計を待たずに始める |
| フルスペック | 解除できるのをシステム保全責任者だけにする。解除の権限を取り戻せる経路をすべて塞ぐ（6 章） | 権限の設計（課題 K1・K2）が固まり次第 |

これまでの資料との関係:

- [worm-design.md](worm-design.md) の決定（12 本・可変の保持期間・解除の後 30 日・既存の最新版にもかける）は引き継ぐ。**モードは、Quick Win ではガバナンスで始める**（決定 2 のコンプライアンスは、フルスペックで改めて決める）。
- [option-reassessment.md](option-reassessment.md) の 4.4 と 7 章は「解除の経路の設計が WORM の前に要る」としていた。2026-11-02 の許容（2 章）で、この前提を外した。7 章の調査は、フルスペックの解除の経路でそのまま使う。

## 2. 決めたこと（2026-11-02、伊藤）

1. **ガバナンスモードで始める。**
2. **かける対象は、原本バケット 12 本すべて。** 大量に消す予定は無いので、鍵をかけない例外は置かない。
3. **解除できるのは、FullAccess を持つ人をはじめ、ほかに何人かいる状態でよい。** ほかにいる主体は、存在を把握できていればよい（3.2 の穴 B）。
4. **解除の後 30 日たてば、版を含めて完全に消せる状態にする。** 解除しても 30 日は絶対に消せないことと、そのあいだの保存の費用は許容する。
5. **解除するとすぐに通知が飛ぶようにする。**
6. **通知の仕組みを外せるのは FullAccess を持つ人とし、これを認識された穴とする。**

## 3. 評価

### 3.1 得られるもの

| 防げるもの | 理由 | 弱点 |
|---|---|---|
| **ライフサイクルによる大量の削除**（今いちばん大きい穴） | ライフサイクルは鍵のかかった版を消せない。消すには先に解除が要り、解除はすぐに通知される | W2・W10 |
| **誰の誤操作も、ほぼ通らない** | 鍵のかかった版を消すには、解除と 30 日の待ちが要る。迂回は全員に Deny する（4 章の作業 1）ので、FullAccess でも、先にポリシーを外さない限り消せない | W1・W14 |
| **FullAccess 以外の主体の乗っ取り** | 例外でない主体は、解除も迂回もできない | W7 |
| **cdk-apps の PR 経由の乗っ取り** | deploy の経路でポリシーを外しても、消すには別の主体による解除か迂回が要り、どちらも通知と足跡が残る | W2・W4 |
| 戻す道具の必要が下がる | 消えないので、大量に戻す手順（K9）を急がなくてよい | W12 |
| 設計の時間が買える | 取り返しのつかない被害が先に止まるので、権限の設計を急がずに詰められる | — |

### 3.2 認識された穴（Quick Win で受け入れる）

| # | 穴 | 中身 |
|---|---|---|
| A | FullAccess の乗っ取り | 通知を外し、ポリシーを外し、迂回して消すことが、1 人でできる |
| B | 解除できる「ほかの何人か」 | deploy の経路（cfn-exec-role。cdk-apps の `main` へのマージ）と、それを引き受けられる 22 主体（2026-10-30 の全主体の判定）、root、管理アカウント、頂点の群（[privilege-map.md](../../../privileged-access/workstream/apex-privileges/privilege-map.md) の台帳）。一覧にして把握する（作業 7） |
| C | 今ある古い版 | 鍵はかからない（worm-design.md の決定 5）。守りは今のバケットポリシーの層だけ |
| D | 通知を外せる主体の範囲 | 「FullAccess だけ」が成り立つかは確かめていない（作業 4）。FullAccess 以外にもいれば、A に載せて範囲を広げるか、見張りを tuscenes-prod の外に置く |

### 3.3 運用上のリスク

| リスク | 中身 | 手当て |
|---|---|---|
| **書き込みが止まる**（いちばん大きい） | Object Lock の既定がかかったバケットへの書き込みには、チェックサムのヘッダーが要る。古いクライアントが書けなくなるおそれがある | 試しの Q5 と、本番の書き手を 1 つずつ確かめる（作業 5） |
| Object Lock は外せない | バケットの Object Lock は、一度有効にすると無効にできない | ガバナンスで始めるので、鍵そのものは迂回で外せる（ポリシーを外せば）。設定を誤っても戻しやすい |
| 入れているあいだ | 既存の版に Batch Operations でかけ終わるまで、既存の版は守られない | worm-design.md の 2.4 の順番（既定 → 既存の最新版） |

### 3.4 まとめ

- 手間に対して価値が高い。主な脅威の誤操作と、いちばん大きい穴を、権限の設計を固める前に塞げる。
- 条件は 2 つ。**迂回を全員に Deny すること**（作業 1）と、**通知を外せる主体を確かめること**（作業 4）。これが無いと、「30 日」と「通知を外せるのは FullAccess だけ」が名前だけになる。ガバナンスでは、迂回の権限（`s3:BypassGovernanceRetention`、AdministratorAccess に含まれる）があれば、解除も待ちも無しに消せるため。

## 4. Quick Win の作業

| # | 作業 | 中身 | 状態 |
|---|---|---|---|
| 1 | **迂回を全員に Deny する** | バケットポリシーで `s3:BypassGovernanceRetention` を、例外の主体も含めて全員に Deny する。FullAccess が迂回するには、先にポリシーを外す必要があり、その変更は通知に乗る（作業 3） | 未 |
| 2 | 鍵の操作を例外の主体に閉じる | バケットポリシーで `s3:PutObjectRetention`・`s3:PutObjectLegalHold`・`s3:PutBucketObjectLockConfiguration` を、ステージ 1 の例外の主体以外に Deny する | 未 |
| 3 | **すぐの通知** | 対象: ホールドの解除と保持の変更（S3 のイベント `Object Retention Updated`、CloudTrail の `PutObjectLockRetention`）、バケットの鍵の設定の変更、バケットポリシーの変更、バケットの通知の設定の変更、通知のルールそのものの変更・削除。受け手は暫定でよい（フルスペックで頂点の群の外へ移す） | 未。Slack の bot の準備（保留中の 0-2・0-3）が関わる |
| 4 | **通知を外せる主体を確かめる** | 通知のルール・通知先・バケットの通知の設定を変えられる主体を、全主体の判定と同じ方法で洗い出す。FullAccess だけでなければ、穴 A の範囲を広げるか、見張りを外に置く（5 章） | 済み（2026-11-02、8 章）。入口を 2 つ・送り先を SNS にすれば、解除できる主体とほぼ同じ集まりにできる |
| 5 | **書き込みの経路を確かめる** | 12 本の書き手（アップロード用の PC・DataSync・Databricks・各アプリ）が、チェックサムのヘッダーを付けて書くか。試しの Q5 の結果と、書き手ごとのクライアントの版で判断する | ログに出た分は済み（2026-11-02、9 章）。**tuscenes-model の Cosmos と jadd-cli は直さないと止まる。** DataSync・Databricks・gaming の PC は不明 |
| 6 | **試し** | 使い捨てのバケットで、[worm-probe-runbook.md](worm-probe-runbook.md) の Q1〜Q6 に、下の Q7〜Q11 を足して確かめる。スクリプトは `~/runbook/worm-probe/worm-probe.sh`（git の管理外。伊藤が Full 権限で実行し、ログは同じフォルダの `log/`） | 実行中。2026-11-02 に setup〜events。Q2・Q5 で迂回の Deny と書き手の確かめが必須、Q7 で迂回の Deny が効くこと、Q10・Q11 で解除と管理イベント（拒まれた試みを含む）が EventBridge に届くことが分かった。Q9・Q12 は翌日以降 |
| 7 | 解除できる主体の一覧（穴 B） | ステージ 1 の例外と、全主体の判定（[iam-scan/](iam-scan/escalation.py)）から作る。構造上の上位権限者は privilege-map.md の台帳を指す | 済み（2026-11-02、7 章） |
| 8 | 入れる | バケットの既定（ガバナンス、イベントホールド、解除の後 30 日）→ 既存の最新版に Batch Operations でホールドをかける（worm-design.md の 2.4）→ バケットポリシーの変更（作業 1・2）を cdk-apps の PR で。**Batch Operations のジョブのロールは例外の主体ではないので、作業 2 のポリシーの後では鍵の操作を拒まれる。** ホールドをかけ終えてからポリシーを当てるか、ジョブのロールを例外に足す | 未 |
| 9 | 入れたあとの確かめ | 12 本の鍵の設定、ホールドのかかった件数、書き込みのエラー、通知が届くこと（カナリアで解除して確かめる） | 未 |

試しに足す項目:

| # | 確かめること |
|---|---|
| Q7 | バケットポリシーで `s3:BypassGovernanceRetention` を Deny すると、迂回の権限を持つ主体でも、ホールド中・保持期限前の版を消せないか |
| Q8 | **解除のあと、保持期限のうちにホールドをかけ直せるか。** かけ直せれば、30 日のあいだに誰かが止められる（フルスペックの拒否の仕組みの土台） |
| Q9 | ライフサイクルの失効が、ホールド中の版を消さないか（今の版の失効は削除マーカーを付けるだけか） |
| Q10 | 解除で `Object Retention Updated` のイベントが EventBridge に届くか。届くまでの時間 |
| Q11 | バケットポリシー・鍵の既定・ライフサイクルの変更が、管理イベント（`AWS API Call via CloudTrail`）として tuscenes-prod の default のバスに届くか（10-29 からの未確認） |
| Q12 | ホールドが ON のまま、期限の欄（書いた時刻＋保持の日数）が過ぎた版を消せないか。消せてしまうなら「解除するまで消えない」が崩れる |
| Q13 | boto3 の書き込み（`put_object`・`upload_file` のマルチパート。CRC32 を trailer で付ける）、Content-MD5 を入れた presigned URL、CopyObject が、Object Lock の既定のあるバケットで通るか（9 章） |

順番の見込み: 試し（作業 6）と、書き込みの経路の確かめ（作業 5）を先に行う。どちらかで問題が出たら、Quick Win の形を見直す。通知（作業 3・4）は、試しと並行して作れる。

## 5. 通知の見張りを tuscenes-prod の外に置く手（穴 A・D を狭める）

Quick Win でやるか、フルスペックでやるかは決めていない。

- **組織の証跡で見張る。** バケットポリシーの変更や通知のルールの削除は、管理イベントとして Control Tower の組織の証跡にも残る。tuscenes-prod の FullAccess からは、それを止められない。見張りを別のアカウントに置けば、「通知が外された」ことに気づける。
- **カナリアで生存を確かめる。** カナリアで毎日、ホールドをかけて解除し、通知が届くことを確かめる。届かなければ、通知が外されたと分かる（届かないことを見張る側は、外に置く必要がある）。

## 6. フルスペックで足りない部分

「解除できるのはシステム保全責任者だけ」にするには、解除の権限を差し替えるだけでは足りない。**解除の権限を取り戻せる経路を、すべて塞ぐ**必要がある。

| # | 補足 | 中身 | 課題 |
|---|---|---|---|
| 1 | 解除の経路 | 専用の workflow と OIDC のロール（option-reassessment.md の 7 章）か、別の形。鍵の操作の例外を、その経路だけにする | K1・K2・K6 |
| 2 | 2 人目の確認の強制 | 解除の依頼の Code Owner をシステム保全責任者にする。最後の push の承認を有効にする | K1 |
| 3 | **バケットポリシーの変更も、専用の経路だけにする** | ポリシーを書き換えられる限り、FullAccess も deploy の経路も、解除の権限を取り戻せる | K2 |
| 4 | FullAccess を例外から外す | 迂回・鍵・ポリシーのすべてから外す | K3 |
| 5 | 組織の層で守る（SCP） | 解除用のロールの作成・信頼の変更・受け渡しと、deploy のロールの引き受けを絞る | K4 |
| 6 | 通知の受け手を頂点の群の外へ | 通知を外す操作の見張りも含める（5 章） | K7・K8 |
| 7 | **かけ直しの扱い** | 守りを強める操作（ホールドのかけ直し）は 1 人で、弱める操作（解除）は 2 人で。Q8 が通れば、30 日のあいだに誰か 1 人が止められる、対等な拒否の仕組みになる | K1 |
| 8 | モードをコンプライアンスにするか | 既存の版のモードを変えられるか。変えるなら全件に Batch Operations をかけ直す（費用も同じだけかかる）。試しの 5-1 で確かめる | K6 |
| 9 | 名簿の変更の決まり | 足す・外す・入れ替える。行き詰まったときの最後の手段 | K1 |
| 10 | 台帳 | 新しいバケットが自動で守られる形にする | K11 |
| 11 | 手順書 | 解除、かけ直し、30 日後の削除（タグで絞ったライフサイクル）、判断の記録の書式 | K1・K9 |
| 12 | 残る穴の明記 | root（管理アカウントからの root の操作で、バケットポリシーは外せる）、管理アカウント、頂点の群。[project:privileged-access](../../../privileged-access/workstream/apex-privileges.md) と、残るリスクの扱いに回す | 頂点の案件 |

## 7. 解除できる主体の一覧（作業 7、2026-11-02）

Quick Win のバケットポリシー（試しの `policy` と同じ形: ステージ 1 の 2 文＋迂回を全員に Deny＋鍵の操作を例外の主体に閉じる）を入れたときに、ホールドを解除できる主体。2026-10-30 の全主体の判定（[current-state.md](current-state.md) の 3.1・3.2）による。穴 B の把握の正本にする。

| 段 | 主体 | 解除までの手順 | 通知に乗るもの |
|---|---|---|---|
| 直接 | SSO `FullAccess`（13 名）・`AWSAdministratorAccess`（1 名） | そのまま解除できる | 解除（Q10） |
| ポリシーを書き換えてから | `cdk-hnb659fds-cfn-exec-role-*`（deploy の経路。cdk-apps の `main` へのマージ） | バケットポリシーから鍵の操作の Deny を外し、そのあと解除する（スタックの中で Lambda などを作って解除させる） | ポリシーの変更（Q11）と解除（Q10） |
| 同上（deploy のロールに届く） | `GithubActions-CdkDeployRole…`、Control Tower の 2 本、StackSets、CodeCatalyst、Databricks の Unity Catalog のロール、Amplify のログ用のロール 6 本 | 同上 | 同上 |
| 構造の上から | tuscenes-prod の root、管理アカウントの管理者、頂点の群（[privilege-map.md](../../../privileged-access/workstream/apex-privileges/privilege-map.md) の台帳。`organization-policy` の経路や Okta から FullAccess を付けられる） | ポリシーを消す、FullAccess を手に入れるなどしてから解除する | ポリシーの変更と解除（管理アカウントからの操作も tuscenes-prod の CloudTrail に出るかは確かめていない） |

- 「直接」以外は、どれも**ポリシーの変更か FullAccess の取得が先に要り、その足跡が通知に乗る**。
- 掃除の手順書（[cleanup-runbook.md](cleanup-runbook.md)）の 1・2 で、Amplify と CodeCatalyst の分は消える見込み。Databricks の Unity Catalog のロールは、担当と直し方を相談する（課題 K4）。
- Batch Operations のジョブのロールは、例外に入れない（ホールドはポリシーの前にかける。作業 8）。

## 8. 通知を外せる主体（作業 4、2026-11-02）

全主体の IAM の設定を取り直して判定した（726 主体。ロール 702・ユーザー 24。スクリプトは [iam-scan/notification-tamper.py](iam-scan/notification-tamper.py)、結果は [iam-scan/notification-tamper-2026-11-02.json](iam-scan/notification-tamper-2026-11-02.json)）。通知の部品はまだ無いので、仮の名前で、外す・黙らせる操作の権限を見た。SCP とリソースのポリシーは見ていない。

### 8.1 部品ごとの結果

例外の主体（FullAccess・AWSAdministratorAccess）と、deploy の経路・Control Tower・StackSets・CodeCatalyst を除いた数。

| 部品 | 外す操作 | 外せる主体 | 見立て |
|---|---|---|---|
| **バケットの通知の設定**（S3 → EventBridge） | `s3:PutBucketNotification` | **18**。`AmazonS3FullAccess` や `s3:*` を持つ主体（Databricks の Auto Loader のロール 2 本、Coder のロール 4 本、TeamE2E・JADDViewer、skypilot、アップロード用の PC、CDK の通知用の Lambda 3 本、使われていない強いロール） | 多い。ただし、この設定の変更は管理イベントなので、CloudTrail 経由の通知（Q11）で気づける（8.2） |
| EventBridge のルール | 削除・無効化・書き換え・送り先の差し替え | 2（ModelConverter の Step Functions のロール 2 本。`events:PutRule`・`PutTargets` を `Resource: *` で持つ）＋AWS のサービスのロール（条件付き） | Step Functions のサービスのロールなので、使うにはステートマシンを書き換える権限が要る（二段目の経路。確かめていない）。cdk-apps でルールの名前に絞れる |
| 送り先: Lambda | 削除・コードの差し替え | 5（Coder のロール 4 本、JADDViewer） | Lambda を送り先にすると穴が広がる |
| 送り先: Slack の鍵（Secrets Manager） | 書き換え・削除 | 3（CoderWorkspaceRole、ecsTaskExecutionRole、sampler-test） | 同上。後の 2 本は掃除の手順書の 6・3 で消える |
| **送り先: SNS** | トピックの削除・設定の変更 | **0** | いちばん狭い |
| 監査の証跡（拒まれた試みのデータイベント） | 停止・削除・対象の変更 | 0 | 狭い |
| 権限の昇格 | ポリシーを付ける・信頼を変える | 条件付きだけ（Coder の 2 本、SSM の Quick Setup の 2 本） | 10-30 の判定と同じ |

### 8.2 見立て

- **「通知を外せるのは FullAccess だけ」は、部品の選び方しだいで「解除できる主体（7 章）とほぼ同じ集まり」にできる。** そのための形:
  1. **入口を 2 つにする。** S3 のイベント（解除の `Object Retention Updated`）と、CloudTrail 経由の管理イベント（ポリシー・鍵の既定・ライフサイクル・**バケットの通知の設定**の変更。拒まれた試みも含む）。バケットの通知の設定を外されても、その変更自体が 2 つ目の入口で通知される。
  2. **送り先は SNS にする**（Lambda と Secrets Manager の鍵を使わない）。Slack へは AWS Chatbot か、SNS のメールで受ける。
  3. ModelConverter の Step Functions のロールの `events:PutRule`・`PutTargets` を、使っているルールの名前に絞る（cdk-apps）。
- **バケットポリシーで `s3:PutBucketNotification` を Deny するのは、今は勧めない。** Databricks が 6 本に通知の設定を作っている（Auto Loader の `databricks-auto-ingest-*` が td1-raw・tuscenes-raw・tuscenes-annotation に、Unity Catalog のファイルイベントの `csms-topic-by-path-*` が denso-nx-raw・denso-taxi-processed・gaming-data-collection に）。Deny すると、Databricks の新しい取り込みの設定が失敗する。入れるなら Databricks の担当と相談する。
- **入れるときの注意（作業 3・8）:** バケットの通知の設定は、1 回の書き込みで全体が置き換わる。EventBridge を有効にするときは、今の設定（Databricks のトピック）を残したまま足す。td1-raw と tuscenes-model は、すでに EventBridge が有効。逆に、Databricks が設定を書き直したときに EventBridge の指定が落ちるおそれがあるので、2 つ目の入口とカナリアの生存の確かめ（5 章）で見張る。
- 掃除の手順書の 9〜11（キーが無効な IAM ユーザー 3 人）は、2026-11-02 の時点で消えていた。Amplify のログ用のロールは 11 本（10-30 は 12 本）。

## 9. 書き手の確かめ（作業 5、2026-11-02）

監査の証跡（`original-bucket-audit`）の全期間（2026-10-30 07:19〜11-02 08:00 UTC、139 万件）を読み、書き手ごとに集計した（サブエージェントの調べ。作業用のファイルは scratchpad の `writer-survey/`）。CloudTrail はヘッダーを記録しないので、userAgent の `m/` の欄（SDK が実際に使った機能の記号。`U`〜`Y` はチェックサムを計算した、`a` は `when_required` の設定）、SDK のソース、手元での再現（S3 に送る前に横取り）で判定した。

### 9.1 入れる前に直さないと止まる書き手

| 書き手 | バケット | 件数（PutObject＋UploadPart） | 理由 | 直し方 |
|---|---|---|---|---|
| **TeamE2E の Cosmos の checkpoint**（`cosmos3/.../*.distcp`） | tuscenes-model | **1,146,088**（書き込みの約 82%） | mono-e2e `projects/wm_generation/src/omnidreams/_src/imaginaire/utils/easy_io/backends/boto3_client.py:282` と `utils/object_store.py:29` が `request_checksum_calculation="when_required"` を指定している（コードで確かめた） | 指定を消すか `when_supported` にする。aioboto3 と multi-storage-client の経路も確かめる。持ち主への連絡が要る |
| **jadd-cli（backend-api の presigned URL）** | tuscenes-model | 1,227（0.1.7・0.1.8 と、0.1.6 以前とみられる python-requests） | presigned URL にはチェックサムが入らない。jadd-cli は `requests.put` で User-Agent しか送らない（`packages/jadd-cli/src/jadd/model/api.py:151,156,191`。コードで確かめた） | URL に Content-MD5 を入れて発行し、クライアントが同じ値を送る、など。古い版の jadd-cli は書けなくなる |

### 9.2 付けると判定したもの

アップロード用の PC（aws-cli 2.38.5・2.25.8・2.23.7 は CRC、2.15.58・2.16.9 は Content-MD5）、Datalake の rlog のデコーダー（boto3 1.36.14、CRC32）、LocalizationNightly、ModelConverter、PerceptionDetection（CLI と JS）、ModelcoreBuild、TeamE2E の人の手の操作。

- アップロード用の PC の 2.23.7・2.25.8 は、設定で `when_required` にしていなければ付ける。PC の `~/.aws/config` と環境変数を確かめる。
- **boto3 の「CRC32 を trailer で付ける」送り方が Object Lock で通るかは、試していない**（11-02 の試しは CLI と Content-MD5 だけ）。Datalake など boto3 の書き手が多いので、試しに足す（Q13）。

### 9.3 不明なもの（ログに書き込みが無かった）

| 書き手 | バケット | 分かっていること | 確かめ方 |
|---|---|---|---|
| DataSync（Azure から） | denso の 3 本 | 公式の資料に記述が無い | 使い捨ての Object Lock のバケットを宛先にしたタスクで試す |
| Databricks | （書く経路はコードに見当たらない） | external location は READ_FILES だけ。ただし catalog `denso` に WRITE_VOLUME があり、volume の場所は Terraform から分からない。Databricks の KB では、S3A の UploadPart は Content-MD5 を付けず、Delta Lake は Object Lock のバケットに対応しない | volume の場所を UI で確かめる。12 本を指していれば Databricks の担当と相談 |
| gaming-data-collection の各 PC | gaming-data-collection | boto3 の指定は `>=1.34` だけ。1.36 未満なら付けない | 各 PC の `pip show boto3` か、次の書き込みの userAgent |
| SkyPilot の API サーバー | tuscenes-* の 5 本 | SDK の版がリポジトリから分からない | 書き込みがあれば userAgent で |

この 3 日余り書き込みが無かったバケット: tuscenes-raw、tuscenes-calibration（新・旧）、td1-rlog、denso の 4 本、gaming-data-collection。

### 9.4 Quick Win への影響

- **tuscenes-model は、Cosmos と jadd-cli を直すまで入れられない。** 入れる順番（作業 8）では、tuscenes-model を後に回すか、直してから入れる。
- 書き込みの止まっているバケット（tuscenes-raw・td1-rlog・tuscenes-calibration（旧）・denso-raw）は、書き手の問題が小さいので先に入れやすい。
- 試しに足すもの（Q13）: boto3 の `put_object` と `upload_file`（マルチパート）、Content-MD5 を入れた presigned URL、CopyObject。DataSync は別に試す。
