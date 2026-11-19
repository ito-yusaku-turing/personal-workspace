# S3 バケットのデータ保護 第三弾（抜け穴の把握と塞ぎ・監視）

- 開始: 2026-11-16
- 状態: **通知の 2 本目（1 件ずつ送る通知の形）の PR は、Copilot の指摘（IAM のパスを含む ARN）を直し、イベントパターンを上限に収まるように分けた**（[cdk-apps#2643](https://github.com/turingmotors/cdk-apps/pull/2643)、head `2700c8b9`）。伊藤がチームのレビューに出す。指摘に対応し、マージ・deploy の後に PR のチェックリストで確かめる

第二弾で原本バケット 9 本に Object Lock を入れた。第三弾では、残った抜け穴を台帳にして区分 A（意図して残す）・B（監視する）・C（監視されていない）に分け、塞ぐ・監視を付ける・主体を減らすことで、C をできるだけ無くす。

- 所属: project:aws-data-protection
- 前段: [第二弾](done/s3-data-protection-2.md)（権限設計のアップグレードと WORM の導入）。第二弾の決定（D1〜D36）・アクション（[worm-action-list.md](done/s3-data-protection-2/worm-action-list.md)）・導入の段階（[worm-rollout-stages.md](done/s3-data-protection-2/worm-rollout-stages.md)）は、第二弾の資料を正本のまま参照する
- 第二弾の閉じ方（2026-11-16、伊藤）: **9 本すべてのホールドの verify が済んだら閉じる**（`done/` に移す）。共有用の資料の Notion への反映などの残りは、第三弾に引き継ぐ（下の「第二弾から引き継いだもの」）。導入の第 3 段階（通知・手順 D）も第三弾で行う

## 第二弾から引き継いだもの

第二弾を閉じた時点で残っているもの。片付いたら消す。

- [ ] 共有用の資料を Notion に反映する（書き込む前に許可を取る）。
  - MLOps 向け（[notion-worm-governance-rollout.md](../documents/notion-worm-governance-rollout.md)）。**ローカルの原本は 2026-11-17 に今の状態へ直した**（15 日、第 2 段階の結果、11-13〜17 の決定、通知の案）。Notion への反映はまだ（伊藤の指示待ち）
  - 会社全体向け（[notion-worm-company-guide.md](../documents/notion-worm-company-guide.md)）。新しく作る（親ページの指定が無ければ MLOps 1チームのドキュメント置き場）
- [x] ~~tuscenes-annotation の関係者（イバイさん・川村さん・塚本さん・安本さん）へのお知らせを送ったか確かめる。~~ → お知らせは要らない（2026-11-17、伊藤）。
- [ ] td1-raw の古い CLI（2.15・2.16）の書き込みが、既定の保持設定の下で拒まれていないかをトレイルで見る。tuscenes-annotation の夜の処理は 11-17 に見て、拒否 0（第二弾の 11-17 の記録）。
- [ ] e2e-dev の `td1-raw-471112873671` の既定の保持設定（1 日）を外すか決める。徳弘さんの試しの結果の詳細を受け取る。
- [ ] 2026-11-28 ごろ、カナリアの `default.txt` で、付け直しのあとの期限の動きを確かめる。
- [x] 第二弾を `done/` に移す前に、恒久的に残す内容（決定 D1〜D36・導入の結果・手順書）が第二弾のフォルダの資料にあることを確かめる。→ 確かめて、2026-11-17 に移した（フォルダごと `done/s3-data-protection-2/` にある）。

## 背景・目的

第二弾までで、原本バケットは次の層で守られている（[permission-model.md](done/s3-data-protection-2/permission-model.md)）。

- 層 1: バージョニング（12 本、2026-10-20）
- 層 2: 守りのバケットポリシー（12 本、2026-10-26。迂回の禁止・鍵の操作の禁止は 2026-11-10）
- 層 3: Object Lock（9 本、2026-11-16。ガバナンス・イベントホールド・解除の後 15 日）

一方で、層 2 を書き換えられる主体（例外の主体・例外を名乗る道）が残り、**起きても人に届く通知がまだ無い**。今の抜け穴は、ほぼすべてが区分 C（監視されていない）にあたる。

第三弾の目的は次の 2 つ。

1. **抜け穴を把握する。** 残る抜け穴をすべて台帳に載せ、区分 A・B・C に分ける（伊藤、2026-11-16）。
2. **区分 C を減らす。** 塞げるものは塞ぎ、残すものには通知を付けて A か B にする。どこまで減らせるかを確かめ、残る C は理由とともに台帳に残す。

## 範囲

作業の柱は 4 つ。台帳がすべての柱の起点になる。

| 柱 | 中身 | 台帳で効くもの | 出どころ（第二弾） |
|---|---|---|---|
| 0. 台帳 | 抜け穴を洗い出し、区分を決める。柱 1〜3 の結果で区分を更新する | すべて | permission-model.md・current-state.md の 6 章 |
| 1. 通知 | 解除・バケットの設定の変更・ジョブの作成・通知の仕組みの変更を、即時に届ける。見張り、ログのバケットの守り | L1・L2・L4・L5・L10・L12・L13 を A・B にする | 導入の第 3 段階の通知、アクション 4-5・4-9 |
| 2. 手順 D | FullAccess を例外から外す。ジョブのロールと deploy の経路を守る SCP | L3・L6〜L9・L19 を塞ぐ | 導入の第 3 段階の手順 D、アクション 2-1・2-3・3-5・4-8・4c-3〜4c-5 |
| 3. 掃除 | 原本バケットに届く主体を減らす | L14 の主体を減らす。L6 の対象を減らす | TODO 12〜16、[cleanup-runbook.md](done/s3-data-protection-2/cleanup-runbook.md) |
| 4. 検知（できれば） | 削除の毎時の報告。監査の対象（S3 のイベント・Inventory）に原本バケットを足す | L14 を B にする | ステージ 2 の PR-A・PR-B、[stage2-hourly-report.md](done/s3-data-protection-2/stage2-hourly-report.md) |

範囲の外:
- 意図して消すときの手順（D13・D35）。消す必要が出たときに再開する。
- 組織・IdP・GitHub の権限の頂点（project:privileged-access）。
- root の認証情報の削除（[aws-root-credentials.md](aws-root-credentials.md)）。

## 設計判断と理由

- **台帳を先に作る。** 柱ごとに手当てを進めると、何が残ったかが見えなくなる。手当ての結果は、台帳の区分の変化として記録する。
- **「監視」は、起きたら人に届くことに限る。** トレイルに記録が残るだけでは、気づくのが後になるので、区分 C に数える（案。台帳の「決めること」の 1）。
- **通知を手順 D より先に入れる**（導入の段階の決めごとを引き継ぐ）。手順 D の SCP で止まるものが出たときに、気づけるようにするため。
- **検知（毎時の報告）は最後にする。** 通知と手順 D で層 2・3 の抜け穴を先に片付ける。毎時の報告が扱うのは層 0・1（戻せる操作）なので、急ぎではない。

## 進め方（案）

| 順 | やること | 柱 | 前提・担当 |
|---|---|---|---|
| 1 | 台帳の区分と範囲を決める（台帳の「決めること」1〜6） | 0 | 伊藤 |
| 2 | 通知の受け手を決める（4-5） | 1 | チーム |
| 3 | 通知の PR（ルール A: ホールドの解除、ルール B: バケットの設定の変更・ジョブの作成と状態の変更、ルール C: 通知の仕組みの変更）。レポートの置き場をトレイルの対象に足す。original-bucket-audit のテストを CI で走らせる | 1 | エージェントが起草、伊藤が PR を作る。カナリアで全部の通知が届くことを確かめる |
| 4 | 見張り（カナリアで定期的に事象を起こし、届かなければ鳴らす）と、ログのバケットの守り | 1 | 台帳の 4・5 で入れると決めたら |
| 5 | 手順 D の前の確かめ（3-5: deploy のロールの引き受け・cfn-exec-role を渡す主体・`cdk bootstrap` の履歴を CloudTrail で 90 日分、手元の `cdk diff` が止まるか） | 2 | エージェント（ReadOnly。大量の読み取りは伊藤に断ってから） |
| 6 | AWSAdministratorAccess を持つ人の確定（2-1）と、山本さんへの相談（2-3） | 2 | 伊藤 |
| 7 | 4c-3（deploy の経路を 9 本のポリシーの変更から締め出すか）・4c-4（GitHub の側）・4c-5（ジョブのロールを渡す操作の禁止を前倒しするか）を決める | 2 | 伊藤（安本さんと） |
| 8 | 手順 D の PR（FullAccess を例外から外す・SCP の文） | 2 | エージェントが起草、伊藤が PR を作る |
| 9 | 掃除（cleanup-runbook.md の残り、`grantReadWrite` の見直し、IAM ユーザー、使われていない強いロール、JADDViewer、LidarDeleter） | 3 | 1〜8 と並行。持ち主への確認が要るものは伊藤 |
| 10 | 検知（毎時の報告。Slack の bot、PR-A、PR-B。tuscenes-raw の古いルールは止めてある） | 4 | 1〜8 のあと |
| 11 | 台帳を最終の区分に更新し、残る C を理由とともに書く。共有用の資料に反映する | 0 | 各柱のあと |

## 進捗チェックリスト

- [x] 計画と台帳の案を書いた（2026-11-16）
- [ ] 台帳の区分と範囲を決めた
- [x] 通知の届け方の方針を決めた（2026-11-17。メールは `mlops1@`、Slack は `#aws_security_alert`）
- [x] 通知の設計の決めること（2026-11-17、伊藤の案。チームの合意はまだ）
- [ ] 通知の仕様をチームに共有し、合意を取った
- [ ] 通知の PR を入れ、カナリアで全部届いた（1 段目の Slack への経路とルール B の一部は 2026-11-18 に届いた。2 段目が残る）
- [ ] ログのバケットの守り（通知の PR のあとに設計する）。見張りは 11-17 に見送った
- [ ] 手順 D の前の確かめ（3-5・2-1・2-3・4c-3〜4c-5）
- [ ] 手順 D の PR を入れた
- [ ] 掃除
- [ ] 検知（毎時の報告）
- [ ] 台帳を最終の区分に更新した

## 次セッションへの引き継ぎ

- 2026-11-16: 計画と台帳の案を書いた。台帳では今の抜け穴が 21 件（L1〜L21）。今はほぼすべてが区分 C で、通知・手順 D・掃除・検知を終えると、C に残る見込みは L11（GitHub の側）・L18（新しいバケット）・L21（写しが無い）だけ。
  - 次: 台帳の「決めること」1〜6 を伊藤と決める。通知の受け手（4-5）をチームで決める。
  - 第二弾は、9 本の verify が済んだら閉じる（伊藤）。残りは上の「第二弾から引き継いだもの」で進める。
  - 2026-11-16 のセッションの終わり。次のセッションで最初にやること:
    1. 第二弾の残りの 3 本（tuscenes-raw・td1-raw・tuscenes-annotation）の verify の出力を読み、第二弾の結果の表を埋める。3 本が済んだら第二弾を閉じる（`done/` に移し、目録と `projects/README.md` を直す）。
    2. 台帳の「決めること」1〜6 を伊藤と決める。
    3. 通知の受け手（4-5）を決め、通知の PR の起草に入る。手順 D の前の確かめ（3-5）は ReadOnly で並行して始められる。

- 2026-11-17: **通知の設計から始めた**（伊藤。塞ぐ前に通知）。[notification-design.md](s3-data-protection-3/notification-design.md) を書いた（11-04 の下書きを土台に、ルール D・E・見張り・ログのバケットを足し、台帳の L 番号を当てはめた）。届け方は伊藤の方針で 4 章を書いた: メールは注意を要する通知だけ（`mlops1@turing-motors.com`）、Slack は新設の `#aws_security_alert` に注意（メンション付き）と定期（見張りなど）。
  - ReadOnly で分かったこと: EventBridge の有効化が要るのは 9 本のうち 8 本。既存のルールとはぶつからない。管理イベントの証跡は組織の証跡だけ。Slack のワークスペースは Amazon Q Developer に承認済み（`#dev_system_info` への既存の設定あり）。**tuscenes-prod のコストアノマリーの宛先は `mlops1@` ではなく `#aws_cost_monitoring` のチャンネルのメールアドレス**（伊藤に確かめてもらう）。
  - 届け方の伊藤の案（11-17）: メールは `mlops@turing-motors.com`（コストアノマリーに揃える。管理アカウントの購読が Google グループ `mlops1@` を通って配られている）、Slack は `#aws_security_alert`（公開）、メンションは `@mlops1`。**個人の案で、仕様が固まったらチームに共有して合意を取る。**
  - 8 章の伊藤の案（11-17）: ルール D・E は入れる。見張り（L12）は見送る（今回は過剰なケア。L12 の一部は C に残る）。ログのバケット（L13）は通知の PR のあとに設計する。警報が OK に戻ったときは送らない。
  - 次: 仕様をチームに共有して合意を取る。並行して通知の PR（4-9）を起草する。伊藤の作業: `#aws_security_alert` を作り、チャンネルの ID と `@mlops1` のグループの ID を控える。`mlops1+owners@` に迷惑メールの保留の設定を確かめる。
- 2026-11-17（午後）: Slack は Amazon Q Developer で送ると決めた（伊藤。メンションが効かなければ替える）。メールは今回のスコープから外す。通知は 2 段に分け、1 段目（Slack への経路・カナリアだけのルール B）を cdk-apps のブランチ `original-bucket-audit-slack` に起草した（`0cce70ea`、[cdk-apps#2614](https://github.com/turingmotors/cdk-apps/pull/2614)）。
  - 次: 伊藤が `#aws_security_alert` を作り、チャンネルと `@mlops1` の ID を `lib/config.ts` に入れて PR にする。deploy の後に試すことは設計の 9.1。
- 2026-11-17 05:54Z: **第二弾の td1-raw の verify が済み、第二弾を閉じた**（9 本すべてのホールドが verify 済み）。`done/` に移し、リンクを直した。
- 2026-11-17（夕方）: [cdk-apps#2614](https://github.com/turingmotors/cdk-apps/pull/2614) の本文の冒頭を直した（WORM 化の続きで、監視の Slack への通知の最初の例。監視ごとにスタックを分ける想定）。「認証情報を持たない」を「秘密を持たない・投稿は AWS の API と IAM を通る」に直し、FullAccess も今は投稿できることを書いた（本文と、コードの説明の commit `1db934be`）。新しい論点: Slack の設定を作れる主体の絞り込み（手順 D）。
  - 次: 別のセッションで PR のレビューをかける（伊藤）。
- 2026-11-17（夜）: [cdk-apps#2614](https://github.com/turingmotors/cdk-apps/pull/2614) のレビュー（別のセッション）の指摘を直した（commit `60818efd`）。トピックへの EventBridge からの発行をこのルールの ARN で絞った、拾う操作に Delete の対とレプリケーション・公開のブロック・暗号化を足した、文面の「拒否」を「エラー」にして主体の type・invokedBy を足した、テストを bin と同じ一覧で作る形にした。DLQ と再試行は 2 本目。
  - **設計の誤りを直した**: 管理イベントの証跡 `aws-controltower-BaselineCloudTrail` は組織の証跡ではなく、tuscenes-prod の中にある。止められないかを管理アカウントの側で確かめる（伊藤）。PR では説明だけ。
  - 次: 伊藤が PR を読み直し、マージする。直しの後の `cdk diff` はまだ取っていない。
- 2026-11-17（夜）: [cdk-apps#2614](https://github.com/turingmotors/cdk-apps/pull/2614) の Copilot の指摘 2 件を直した（`66bdba72`）。トピックへの発行は、`aws:SourceArn` の条件をやめて、ルールの専用のロールで発行し `events.amazonaws.com` の直接の発行を条件なしで拒む形にした。ガードレールの IAM の説明を英語にした（日本語が通る例がアカウントに無い）。Copilot のコメントへの返信はしていない。
- 2026-11-17（夜）: Copilot の 2 回目のレビュー（`66bdba72`）は新しい指摘 0 件で、前の 2 件は解決済み（返信も済み）。見落としとして 1 件（Low）: 「投稿は必ず CloudTrail に残る」は言い過ぎ。`sns:Publish` は SNS のデータイベントで、記録していない（監査の証跡は S3 のオブジェクトのデータイベントだけ）。README・コードの説明・PR の本文・設計の 4.4 を直し（`f64769ac`）、PR にコメントで返した。
  - 2 段目への持ち越し: トピックへの発行を絞るときに、発行の記録（SNS のデータイベント）も考える。
  - 次: 人の承認を得てマージ・deploy し、9.1 の手順で試す。

- 2026-11-18: [cdk-apps#2614](https://github.com/turingmotors/cdk-apps/pull/2614) は安本さんが Approve（11-17）。提案 2 件（ルールのロールの信頼ポリシーに `aws:SourceArn`・`aws:SourceAccount` の条件、Inventory の設定の操作を拾う）は、伊藤の判断でこの PR に取り込んだ（`c69b5dc2`。jest 21 件・`tsc`・`cdk synth` は通過）。PR の本文も直した。安本さんのインラインのコメントへの返信はしていない。9.1 の 3 に、メンションが入力の変換の後も残るかの確認を足した。
  - 作業ツリーに、エージェントが触っていない `apps/original-bucket-audit/package.json`（`aws-cdk` を `^2.1148.1` に）と `package-lock.json` の変更が残っている（commit していない）。
  - 次: CI の cdk diff を確かめて、伊藤がマージする。deploy の後に 9.1 の手順で試す。
- 2026-11-18: 伊藤がマージし、deploy した（01:18Z）。9.1 の手順で試した（手での発行とカナリアは伊藤、確かめはエージェントが ReadOnly で）。**Slack に届き、ユーザーグループのメンション `<!subteam^…>` も、手での発行とルールの入力の変換の両方で効いた**。ロールでの発行は、信頼ポリシーの条件の下で通った（`FailedInvocations` 0）。Slack の設定の作成は us-west-2 の CloudTrail に残る。詳細は設計の 9.1 の「結果」。
  - 伊藤の方針: メンション（表示は `@mlops1_all`）は重要な通知だけに限る。線引きは設計の 8 章の 10（たたき台あり）。
  - メンションの線引きを決めた（設計の 8 章の 10）。守りを外す・弱める操作で成功したものにだけ付ける。拒まれた操作は、メンションを付けずに流す（伊藤）。オブジェクトに対する操作（ルール A・D）は、警報で 1 通にまとめるので件数が跳ねても通知は増えない。2 段目で、警報をジョブのロール／それ以外の主体の 2 本に分け、本文に Logs Insights へのリンクを入れる（3.1・3.4）。
  - 次: 仕様（1 段目の結果を含む）をチームに共有して合意を取る。2 段目を起草する。中身は、ルール A〜E を原本バケットに広げる・トピックへの発行をルールのロールだけに絞る・DLQ と再試行・`invokedBy` が空のときの文面・ルール B を成否で 2 本に分ける・A・D の警報を主体で分ける。

- 2026-11-18（午後）: 伊藤の方針で、チームへの共有より先に仕様を固めて動作確認をする。**通知の文面を設計の 10 章にまとめた**（文面の正本。実装は cdk-apps の `notify-stack.ts`）。
  - 観点（伊藤）: workstream の中の語を使わない（「原本バケット」→「保護対象の S3 バケット」）、正式な名称（「S3 バケット」）、危険度がすぐ分かる。
  - 危険度は 3 段（重大＝メンションあり／注意／記録＝拒否）。重大は、保護を外す・弱める操作、取り返しの付かない操作、公開につながる操作、監視の入力を止める操作。向きが分からない操作は重大に倒す。向きの欄は CloudTrail の記録で確かめた（10.8）。
  - 調べる鍵の欄（principalId・invokedBy・accessKeyId・requestID など）を載せる。空の欄は、`userIdentity.type` でルールを分けて `-` と書く。ルール B は 6 本になる。
  - ルール A・D は、警報 4 本（A-1 ジョブでの解除、A-2 ジョブのロール以外の保持の変更、D-1 古い版の削除、D-2 拒否）。S3 のイベントでは主体が分からないので、A-2 は CloudTrail のデータイベントで拾う。
  - 口調: 欄の名前と題名は堅い体言止め（「〜を検知」）。説明文と頼む文は、です・ます調。警報の時刻は「検知時刻」（操作はその前から起きうる）。
  - 所有権の設定は、12 本とカナリアがすべて `BucketOwnerEnforced`（ReadOnly で確かめた）。
  - 次: ルール C・E の文面を同じ形で起こす。固まったら、2 段目の PR を作る（伊藤）。カナリアで確かめること: Batch Operations の操作がジョブのロールの主体で CloudTrail に記録されるか、警報の `reasonData`。

- 2026-11-18（夕方）: PR の分け方を決めた（伊藤）。固まった領域から順に、PR ごとに品評する。**1. 1 件ずつ送る通知**（S3 バケットの設定・通知の仕組み・IAM）→ **2. 警報でまとめる通知**（ホールドの解除・古い版の削除・ジョブのロール以外の保持の変更・拒否・deploy の経路のまとめ）→ **3. 12 本への横展開と仕上げ**。
  - 足りない欄の名前を、試し用の資源（`~/runbook/alert-field-probe/alert-field-probe.sh`）で確かめた（設計の 10.13・10.14）。Amazon Q Developer の更新・削除だけは同じチャンネルで試せず、文書の名前のまま。
  - deploy の経路は案 3（警報で 1 通）。PR 1 では暫定で注意（メンションなし）。
  - **[cdk-apps#2643](https://github.com/turingmotors/cdk-apps/pull/2643) を出した**（ブランチ `original-bucket-alert-catalog`、`5c619b23`）。仕様の正本を cdk-apps の `apps/original-bucket-audit/docs/notifications.md` に置いた。通知の表（`lib/alert-catalog.ts`）からルール 28 本（us-west-2 に 21、us-east-1 に 7）を組み立てる。イベントパターンは、実際の記録 12 件と書き換えた例 19 件で `TestEventPattern` を当て、31 件すべて期待どおり（`scripts/check-alert-patterns.py`）。
  - 起草は git worktree（scratchpad の `cdk-apps-alert`）で行った。`/usr/app/cdk-apps` の作業ツリーには、エージェントが触っていない `package.json`・`package-lock.json` の変更が残っていて、ブランチを切り替えられなかったため。
  - セルフレビュー（別セッション）の指摘 10 件のうち 9 件を直した（`6c75c871`）。主なもの: us-east-1 の通知の部品も見張る、失敗の通知に前方一致で拾った名前を載せない（エスケープされないため）、S3 バケットの重大は deploy の経路でも重大、記録の文面を「失敗しました」にする、信頼ポリシーからカスタムのバスのルールを除く、`PutDataProtectionPolicy` を見張る（us-west-2 では使えなかった）。パターンの確かめは 36/36。PR の本文も直した。
  - 分かった限界: トピックを消す・購読をやめる操作の通知は、そのトピック自身を通るので、操作の後には届かないことがある（cdk-apps の docs 10 章）。
  - 再レビュー（`6c75c871`）は前回の指摘がすべて対応済み。新しい nit 1 件（警報の操作の通知で、対象の欄が空で出る。警報の名前を載せないため）は、**警報を足す次の PR で直す**（伊藤、11-18）。警報の行を分けて「-（警報の名前は載せない。eventID から確認）」と書く。
  - **イベントパターンの大きさの上限は、このアカウントでは 2048 文字**（Service Quotas の Event pattern size。引き上げは申請できる）で、テストが見ていた 4096 ではなかった（Fable の確かめで分かった）。今の最大は 1,865 文字。12 本に広げると S3 バケットのルールが約 2,300 文字で超えるので、3 本目の PR で引き上げの申請かパターンの分割をする（`0301d649` でテストに固めた）。
  - PR の本文を清書した（実装と突き合わせ、Fable にも確かめてもらった）。deploy の後の確かめに「重大」（カナリアの暗号化の設定を同じ値で入れ直す）を足した。最初の deploy では us-east-1 のスタックの deploy 中の通知は Slack に届かない（Slack の設定が us-east-1 のトピックを受けるのは、そのあとの us-west-2 の更新から）ので、deploy の後に us-east-1 のトピックへ手で発行して確かめる。
  - 次: チームの品評を受けて直す。マージ・deploy の後に PR のチェックリスト（deploy の通知が注意で来る・`UpdateSlackChannelConfiguration` の欄・注意と記録の見え方・us-east-1 から届く）を確かめる。マージしたら、設計の 10 章を「経緯と理由」だけに縮め、仕様は cdk-apps を指す。

- 2026-11-18（セッションの終わり）: PR の本文を清書した（伊藤と推敲）。
  - 本文の方針: 「チームで品評する」ことは書かない。docs を参照させない（docs を置いたこと・何のために何を書いたかは「仕様の文書」の節に書く）。「通知の形」の節は、設計とその意図を書く。冒頭は「MLOps チームに今日配属された人でも、通知だけを見て判断し、動き出せることを目標に決めました」。公開を重大にする理由は「成功していれば、データ流出インシデントの疑いがあるため」。
  - 最初の commit（`5c619b23`）のメッセージに「チームで品評するための PR」と残っている。push 済みなので直さない。squash でマージするときに消す（伊藤）。
  - 次のセッションで最初にやること:
    1. チームのレビューの指摘に対応する。直すときは、cdk-apps のブランチ `original-bucket-alert-catalog` を使う。起草に使った worktree は scratchpad（`cdk-apps-alert`）にあり、消えていたら `git -C /usr/app/cdk-apps worktree prune` の後に作り直す（`/usr/app/cdk-apps` の作業ツリーには、エージェントが触っていない `package.json`・`package-lock.json` の変更が残っていて、ブランチを切り替えられない）。パターンを変えたら `scripts/check-alert-patterns.py` を流す（ReadOnly で約 1 分）。
    2. マージ・deploy の後に、PR の「deploy の後に確かめること」を伊藤と確かめる（重大はカナリアの暗号化の設定の入れ直し、us-east-1 はトピックへの手での発行）。`UpdateSlackChannelConfiguration` の欄（`ChatConfigurationArn`）も、その記録で確かめる。
    3. 2 本目（警報でまとめる通知）の前に、CloudTrail のデータイベントが EventBridge に届くかと、Batch Operations の操作の主体を、カナリアで確かめる。2 本目では、警報の操作の通知で対象の欄が空になる nit も直す。
    4. ~~3 本目（12 本に広げる）の前に、イベントパターンの上限（2048 文字）の手当てを決める。~~ → 11-19 に #2643 で分けた。
  - 設計の 10 章（`notification-design.md`）は、マージしたら「経緯と理由」だけに縮め、仕様は cdk-apps の `docs/notifications.md` を指す。
  - 試しのスクリプトは `~/runbook/alert-field-probe/alert-field-probe.sh`（git 管理外）。

- 2026-11-19: [cdk-apps#2643](https://github.com/turingmotors/cdk-apps/pull/2643) の Copilot のレビュー（`0301d649`）の指摘 1 件（High）を直した（`3b1d1ecd`）。
  - 指摘: 管理ポリシーの ARN（`policyArn`）を、成功した操作の通知にそのまま載せていた。IAM のパスには引用符やバックスラッシュも使え、入力の変換はエスケープしないので、パスに `"` を含むポリシーをジョブのロールに付けると、重大の通知が落ちる。
  - 同じ種類の穴をもう 1 つ見つけた: 実行者の欄の `userIdentity.arn`。IAM ユーザーの ARN にはユーザーのパスが入る。
  - 直し方: IAM の行をロールの操作（`iam-role-critical`、ロール名だけを載せる）と管理ポリシーの操作（`iam-policy-critical`、対象の欄は「-（eventID から確認）」）に分けた。実行者は、ロール名（`sessionIssuer.userName`）か IAM ユーザー名（`userName`）と、実行者のアカウント（`accountId`）で載せる。IAM ユーザー用にルールを分ける案は、パターンが大きくなり 2048 文字の上限に近づくのでやめた。ルールは us-east-1 が 14 本から 21 本になった。
  - jest 32 件・`tsc`・`cdk synth`・prettier は通過。パターンの確かめは 40/40（足した例: ガードレールをほかのロールに付ける・パスに引用符を含むポリシー・IAM ユーザーの操作・対象外の管理ポリシー）。パターンの最大は 1,865 文字のまま。PR の本文も直した。
  - worktree は今回のセッションの scratchpad に作り直した（`cdk-apps-alert`。`node_modules` は `/usr/app/cdk-apps` からのシンボリックリンク）。
  - Copilot のコメントに返信した（伊藤の了承の後）。
  - 設計の 10 章（`notification-design.md`）の実行者の欄の記述は古いまま。マージの後に 10 章を縮めるときに合わせて消す。
  - 次: チームのレビューを受けて直す。マージ・deploy の後に PR のチェックリストを確かめる（実行者の欄がロール名で出ることも見る）。

- 2026-11-19（続き）: **イベントパターンの上限（2048 文字）は、引き上げを申請せず、ルールを分けて収めると決めた**（伊藤。展開先はこの後も広がりうる）。PR がまだレビューに出す前だったので、3 本目ではなく [cdk-apps#2643](https://github.com/turingmotors/cdk-apps/pull/2643) に入れた（`2700c8b9`）。
  - 前提: 1 件の操作で通知はちょうど 1 通。`$or` の条件は機械的に分けない（公開のブロックの 2 つを同時に外すと、2 つの条件に一致する）。
  - 1 段目（手で書く）: 定義の行を、操作の名前が重ならない行に分けた。`s3-critical` → `s3-critical-ops`（操作の名前だけで拾う）と `s3-critical-dir`（向きの条件）。`notify-critical` → `notify-critical-input`（証跡・ルール・警報・Logs）と `notify-critical-output`（SNS・Amazon Q Developer）。危険度・題名・理由は同じ。
  - 2 段目（自動）: 定義の行に `partition`（区切ってよい一覧。1 件の操作が値を 1 つだけ持つもの＝S3 バケットの名前）を宣言でき、組み立てで予算（上限 − 100 = 1,948 文字）に収まるように宣言の順に詰めて区切る。名前には区切りが 1 つでも `-p1` を付ける。区切れない行・値 1 つで超える・名前が 64 文字を超える、のどれでも `cdk synth` が止まる。
  - 測った値: 分ける前は `s3-critical` が 1 本で 1,841（12 本＋カナリアで 2,186）、`notify-critical` が 1,865。分けた後の最大は `s3-critical-dir` の 1,471。区切りが 2 つになるのは、`s3-critical-dir` が合わせて約 18 本、`s3-warning` が約 29 本、`s3-critical-ops` が約 34 本。
  - ルールは us-west-2 が 35 本、us-east-1 が 28 本。jest 39 件、パターンの確かめ 42/42。PR の本文と docs の 5.1 も直した。
  - 次: 伊藤がチームのレビューに出す。マージ・deploy の後に PR のチェックリストを確かめる。

## 関連リンク

- [抜け穴の台帳](s3-data-protection-3/loophole-ledger.md)
- 第二弾: [s3-data-protection-2.md](done/s3-data-protection-2.md)、[permission-model.md](done/s3-data-protection-2/permission-model.md)、[current-state.md](done/s3-data-protection-2/current-state.md)、[worm-rollout-stages.md](done/s3-data-protection-2/worm-rollout-stages.md)、[worm-action-list.md](done/s3-data-protection-2/worm-action-list.md)、[worm-decisions.md](done/s3-data-protection-2/worm-decisions.md)、[stage2-hourly-report.md](done/s3-data-protection-2/stage2-hourly-report.md)、[cleanup-runbook.md](done/s3-data-protection-2/cleanup-runbook.md)
- cdk-apps: `apps/original-bucket-audit`（通知・検知の置き場）、`packages/original-bucket-guard`（守りのバケットポリシー）、`apps/organization-policy`（SCP）
