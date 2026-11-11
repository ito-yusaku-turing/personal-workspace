# 第 2 段階の予行（カナリアに後から Object Lock を入れる）の手順書

- 作成: 2026-11-11 ／ 伊藤（エージェントが起草）
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)。段階の正本 [worm-rollout-stages.md](worm-rollout-stages.md) の「手順 B」。アクションの 4-2 と 4c-6（[worm-action-list.md](worm-action-list.md)）
- 状態: **未実施**。第 1 段階（[cdk-apps#2500](https://github.com/turingmotors/cdk-apps/pull/2500)）は 2026-11-11 05:16 UTC に deploy 済み。シミュレーターで見る項目（S1）は、エージェントが 11-11 に済ませた
- 実行する人: 伊藤（`full` プロファイル＝tuscenes-prod の SSO の FullAccess）。エージェントは、ログと ReadOnly の確認で結果を読む
- スクリプト: `~/runbook/canary-rehearsal/rehearsal.sh`（git の管理外。前回の `~/runbook/manifest-probe/` と同じ形）。ログは `~/runbook/canary-rehearsal/log/` に手順ごとに残る

手順 C で原本バケットに入れるのと同じ操作を、先にカナリア `original-bucket-canary-767397804933` で行う。第 1 段階で入れた部品（守りの 3 文・ジョブのロール・レポートの置き場）を、実物で初めて通す。

## 確かめること

| # | 問い | なぜ要るか | 手順 |
|---|---|---|---|
| R1 | 既存のバケットに後から Object Lock を有効にすると、既存の版・バージョニング・書き込みはどうなるか | 手順 C の 1 番目の操作。**戻せない** | enable |
| R2 | 既定の保持設定を入れると、新しい版に GOVERNANCE・ON・30 日が付くか。チェックサムなしの書き込みが拒まれるか。条件付き書き込み（`If-None-Match`）とマルチパートが通るか | 書き込み元が止まらないか。tuscenes-calibration（新）の書き手（backend-api）は条件付き書き込みを使う（4c-6） | default |
| R3 | 既定の保持設定を外すと、チェックサムなしで書けるようになるか。付いた保持は残るか | 書き込みが止まったときの戻し方 | rollback |
| R4 | FullAccess の直接の操作（ホールドを外す・リーガルホールド・迂回の削除・書き込みでの期限の指定）が拒まれるか | `DenyLockChange`・`DenyGovernanceBypass` を実物で確かめる | direct |
| R5 | ジョブのロールで、対象の一覧をジョブに作らせ、確認待ちで止めてからホールドを付けられるか。対象を読む権限（`s3:GetObject`）なしで通るか。一覧と結果をレポートの置き場に書けるか | このロールの形で流すのは初めて（PR の未確認の点） | hold → run |
| R6 | ジョブのロールで、30 日以外の日数と、固定の期限が拒まれるか | `DenyUnexpectedEventHoldDuration`・`DenyFixedRetention` を実物で確かめる | negative |
| R7 | ジョブのロールで、ホールドを外せるか。外したあとの期限は「外した時刻＋30 日」で固まるか | 手順の訓練。解除が止まらないこと | release |
| R8 | ホールド中・解除後の版の日数を、延ばす・縮めるとどうなるか。縮めるのに迂回が要るか | あとから日数を変えるときの手順（AWS のドキュメントに書かれていない） | days（worm-probe のバケット） |
| S1 | コンプライアンスモードの指定が、ジョブのロールとバケットポリシーの両方で拒まれるか | 実物では試さない（効かなかったとき戻せない） | **済み**（下の「結果」） |

DataSync が Object Lock のバケットに書き込めるか（アクションの 4-6）は、この手順書には入れない。DataSync のタスクを予行用のバケットに向ける設定が要るので、別に行う。

## 0. 前提と注意

- **R1 の Object Lock の有効化は戻せない。** カナリアは、このあとも Object Lock を入れたまま訓練に使う（D23）。
- **カナリアの失効の試しは使えなくなる。** 既定の保持設定はバケット全体に効く。exerciser（`original-bucket-canary-exerciser`、手で起動するだけ）が書く `expire/` の版にも保持が付き、ライフサイクルでは消えなくなる（Q9）。失効を監査が拾うかを、カナリアでは試せなくなる。
- **保持が付いた版は、外してから 30 日たつまで誰も消せない**（迂回は全員に拒否）。試すキーはどれも数十バイト。費用はほぼ 0。
- 費用: ジョブ 4 本で約 $1（1 本 $0.25）。
- 実行は、イベントホールドを知っている AWS CLI（2.39.3 以降。ホストの WSL のもの）で行う。スクリプトが最初に確かめる。
- R8 は、前回の使い捨てのバケット `worm-probe-767397804933` を使う（片付けがまだで、Object Lock とポリシーが残っている）。R8 で書いた版は最長 3 日保持が付くので、**worm-probe の片付けは R8 から 3 日後より後になる**。
- 手順ごとに止まって、ログをエージェントに読ませてから次へ進む。`NG` が出たら、そこで止める。

```bash
aws sso login --profile full         # 切れていれば
cd ~/runbook/canary-rehearsal
```

## 1. 手順

| 手順 | コマンド | すること | 終わったら |
|---|---|---|---|
| 1 | `bash rehearsal.sh pre` | 試すキー（`rehearsal/pre/a.txt`、版が 2 つの `rehearsal/pre/b.txt`）を、Object Lock を入れる前に書く | — |
| 2 | `bash rehearsal.sh enable` | R1。**Object Lock を有効にする（戻せない）**。既定の保持設定はまだ入れない | **エージェントに知らせる** |
| 3 | `bash rehearsal.sh default` | R2。既定の保持設定を入れ、書き込みを 6 通り試す | **エージェントに知らせる** |
| 4 | `bash rehearsal.sh rollback` | R3。既定の保持設定を外して書き込みを試し、入れ直す | — |
| 5 | `bash rehearsal.sh direct` | R4。FullAccess の直接の操作 6 つが拒まれることを見る | `NG` が無いこと |
| 6 | `bash rehearsal.sh hold` | R5。ジョブを作る（確認待ち）。止まったら、作られた一覧を出す | **エージェントに知らせる**。一覧が 2 件（a と b の最新版）であること |
| 7 | `bash rehearsal.sh run` | R5。確認待ちのジョブを流し、各版の保持を出す | — |
| 8 | `bash rehearsal.sh negative` | R6。拒まれるはずのジョブを 2 本流す（各 2 件） | **エージェントに知らせる** |
| 9 | `bash rehearsal.sh release` | R7。pre/ の最新版のホールドを、ジョブで外す | — |
| 10 | `bash rehearsal.sh days` | R8。worm-probe のバケットで、日数を延ばす・縮める | **エージェントに知らせる** |

- `bash rehearsal.sh show` で、いつでも今の状態（既定の保持設定・各版の保持・ジョブ）を出せる。
- ジョブが `Failed` になったら、エージェントに知らせる。ロールの権限の不足なら、cdk-apps の PR で直す（手で権限を足さない）。
- 手順 2〜3 のあとは、カナリアの書き込みが CloudTrail（監査のトレイル）にどう残るかを、エージェントが ReadOnly で見る。

### 試すキー（カナリアの `rehearsal/` の下）

| キー | いつ書く | 期待する保持 |
|---|---|---|
| `pre/a.txt`・`pre/b.txt`（版 2 つ） | Object Lock の前 | 書いたときは無し。R5 で最新版にだけホールド、R7 で外す |
| `r1/default.txt`・`r1/no-checksum.txt` | Object Lock のあと、既定の保持設定の前 | 無し |
| `r2/*` | 既定の保持設定のあと | GOVERNANCE・ON・30 日（外さずに残す） |
| `r3/no-checksum.txt` | 既定の保持設定を外したあいだ | 無し |
| `r4/*` | — | 書けないはず |

ジョブの入力（一覧）・作られた一覧・結果は、レポートの置き場 `original-bucket-lock-batch-reports-767397804933` の `rehearsal/` の下に置く（`input/`・`manifest/`・`report/<ジョブ>/`）。

## 結果

| # | 結果 | 日時・メモ |
|---|---|---|
| R1 | | |
| R2 | | |
| R3 | | |
| R4 | | |
| R5 | | |
| R6 | | |
| R7 | | |
| R8 | | |
| S1 | **OK。** ジョブのロール（`simulate-principal-policy`）: 30 日のホールドと解除は許可。31 日・年での指定（日数のキーなし）・`COMPLIANCE`（小文字も）・固定の期限は拒否（ロールのポリシー）。対象外のバケット（tuscenes-model）は暗黙の拒否。バケットポリシー（`simulate-custom-policy`、カナリアの実物のポリシー）: `DenyLockChange` を除いたポリシーでも、FullAccess の `COMPLIANCE` の指定（保持の変更・書き込みのヘッダー）は拒否、`GOVERNANCE` は許可（`DenyComplianceMode` だけが効いている）。実物のポリシーでは、FullAccess の保持の変更・リーガルホールド・迂回は拒否。ジョブのロールは `GOVERNANCE` の保持の変更だけ許可、`COMPLIANCE` と迂回は拒否 | 2026-11-11、エージェント（ReadOnly） |
