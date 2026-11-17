# S3 バケットのデータ保護 第三弾（抜け穴の把握と塞ぎ・監視）

- 開始: 2026-11-16
- 状態: **通知の 1 段目（Slack への経路をカナリアで試す）を cdk-apps で起草し、チャンネルとグループの ID も入れた**（ブランチ `original-bucket-audit-slack`、未 push）。伊藤がローカルで差分を見てから push・PR。deploy の後の試しは [notification-design.md](s3-data-protection-3/notification-design.md) の 9.1

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
- [ ] 通知の PR を入れ、カナリアで全部届いた
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
- 2026-11-17（午後）: Slack は Amazon Q Developer で送ると決めた（伊藤。メンションが効かなければ替える）。メールは今回のスコープから外す。通知は 2 段に分け、1 段目（Slack への経路・カナリアだけのルール B）を cdk-apps のブランチ `original-bucket-audit-slack` に起草した（`0cce70ea`、`/usr/app/cdk-apps` でチェックアウトしている、未 push）。
  - 次: 伊藤が `#aws_security_alert` を作り、チャンネルと `@mlops1` の ID を `lib/config.ts` に入れて PR にする。deploy の後に試すことは設計の 9.1。
- 2026-11-17 05:54Z: **第二弾の td1-raw の verify が済み、第二弾を閉じた**（9 本すべてのホールドが verify 済み）。`done/` に移し、リンクを直した。

## 関連リンク

- [抜け穴の台帳](s3-data-protection-3/loophole-ledger.md)
- 第二弾: [s3-data-protection-2.md](done/s3-data-protection-2.md)、[permission-model.md](done/s3-data-protection-2/permission-model.md)、[current-state.md](done/s3-data-protection-2/current-state.md)、[worm-rollout-stages.md](done/s3-data-protection-2/worm-rollout-stages.md)、[worm-action-list.md](done/s3-data-protection-2/worm-action-list.md)、[worm-decisions.md](done/s3-data-protection-2/worm-decisions.md)、[stage2-hourly-report.md](done/s3-data-protection-2/stage2-hourly-report.md)、[cleanup-runbook.md](done/s3-data-protection-2/cleanup-runbook.md)
- cdk-apps: `apps/original-bucket-audit`（通知・検知の置き場）、`packages/original-bucket-guard`（守りのバケットポリシー）、`apps/organization-policy`（SCP）
