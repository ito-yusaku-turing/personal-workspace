# 第 2 段階の予行（カナリアに後から Object Lock を入れる）の手順書

- 作成: 2026-11-11 ／ 伊藤（エージェントが起草）
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)。段階の正本 [worm-rollout-stages.md](worm-rollout-stages.md) の「手順 B」。アクションの 4-2 と 4c-6（[worm-action-list.md](worm-action-list.md)）
- 状態: **R5 で止めた**（2026-11-11 06:07 UTC〜。pre〜run まで実施）。run のジョブが、ジョブのロールの `DenyFixedRetention` で拒まれた。原因は特定した（下の「R5 の切り分け」）。ロールのポリシーを直す PR [cdk-apps#2537](https://github.com/turingmotors/cdk-apps/pull/2537) を作った。deploy してから、hold からやり直す（`tmp/hold-job` を消してから）。第 1 段階（[cdk-apps#2500](https://github.com/turingmotors/cdk-apps/pull/2500)）は 2026-11-11 05:16 UTC に deploy 済み。シミュレーターで見る項目（S1）は、エージェントが 11-11 に済ませた
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
| R1 | **OK。** 後から有効にできた（FullAccess。設定は `ObjectLockEnabled` だけ）。バージョニングは Enabled のまま。既存の 3 版に保持は付かなかった。**既定の保持設定が無いあいだは、チェックサムなしの書き込みも通った**（CLI の既定の書き込みも通り、保持なし）。手順 C では、有効化と既定の保持設定を分けられる（有効化だけでは書き込みは止まらない） | 2026-11-11 06:08 UTC。ログ `20261111-150828-enable.log` |
| R2 | **OK（8 行とも）。** 既定の保持設定（GOVERNANCE・`DefaultEventHold.Days: 30`）を入れられた。新しい版は GOVERNANCE・ON・30 日（CLI の既定・Content-MD5 だけ・条件付き書き込み・マルチパート 20 MiB）。チェックサムなしは `InvalidRequest: Content-MD5 OR x-amz-checksum- HTTP header is required for Put Object requests with Object Lock parameters`（既定の保持設定から付く場合も、この文言）。条件付き書き込み（`If-None-Match: *`）は、新しいキーで通り、同じキーで `PreconditionFailed`（ふつうのバケットと同じ）。pre/ の既存の 3 版は保持なしのまま。**残る点:** 条件付き書き込みは CLI で試した。backend-api（boto3 1.42）は、S3 のクライアントを `when_required` にしていなければ CRC32 が付いて通る（Q13）。段階 1 の前に設定を確かめる | 2026-11-11 06:12 UTC。ログ `20261111-151231-default.log` |
| R3 | **OK。** 既定の保持設定を外すと（`ObjectLockEnabled` だけに戻す。FullAccess で通った）、チェックサムなしの書き込みがすぐに通り、その版は保持なし。外す前に付いた保持（`r2/default.txt`）は残った。入れ直しも通った。**書き込みが止まったときの戻し方は、この 1 回の操作で足りる。** 外しているあいだに書かれた版には保持が付かないので、入れ直したあと、その間の版にジョブでホールドを付ける | 2026-11-11 06:14 UTC。ログ `20261111-151424-rollback.log` |
| R4 | **OK（6 つとも拒否）。** FullAccess の、ホールドの解除・リーガルホールド・迂回つきの削除・書き込みでの期限の指定（ガバナンス・コンプライアンス）は `is not authorized to perform`（IAM の評価での拒否。FullAccess は IAM で許されているので、バケットポリシーの文による）。迂回なしの削除だけは `Access Denied because object protected by object lock`（Object Lock そのもの）。`r2/default.txt` はホールドのまま。文言が 200 字で切れたので、書き込みでの指定がどのアクションで拒まれたかは、トレイルで見る | 2026-11-11 06:21 UTC。ログ `20261111-152131-direct.log` |
| R5 | **一覧までは OK、ホールドは NG（2 件とも失敗）。** 一覧（ManifestGenerator）は、対象を読む権限なしで作れた。中身は a・b の最新版の 2 件（b の古い版は入らない）。レポートの置き場に書けた。約 20 秒で `Suspended`（確認待ち）。流すと 2 件とも `AccessDenied`: `original-bucket-lock-batch … is not authorized to perform: s3:PutObjectRetention … with an explicit deny in an identity-based policy`。**ジョブのロール自身の Deny に当たった**（バケットポリシーではない）。シミュレーターでは同じ指定（GOVERNANCE・ON・30 日）が許可だったので、ジョブの実際の要求は、シミュレーターに与えた条件キーと違う形をしている。どの Deny か（`DenyUnexpectedEventHoldDuration` か `DenyFixedRetention`）は、トレイルの記録で調べる。pre/ の 3 版は保持なしのまま | 2026-11-11 06:36〜06:38 UTC。ジョブ `4d794f32-621b-4381-85c1-55b1f97cd67b`。ログ `20261111-153613-hold.log`・`20261111-153803-run.log` |
| R6 | | |
| R7 | | |
| R8 | | |
| S1 | **OK。** ジョブのロール（`simulate-principal-policy`）: 30 日のホールドと解除は許可。31 日・年での指定（日数のキーなし）・`COMPLIANCE`（小文字も）・固定の期限は拒否（ロールのポリシー）。対象外のバケット（tuscenes-model）は暗黙の拒否。バケットポリシー（`simulate-custom-policy`、カナリアの実物のポリシー）: `DenyLockChange` を除いたポリシーでも、FullAccess の `COMPLIANCE` の指定（保持の変更・書き込みのヘッダー）は拒否、`GOVERNANCE` は許可（`DenyComplianceMode` だけが効いている）。実物のポリシーでは、FullAccess の保持の変更・リーガルホールド・迂回は拒否。ジョブのロールは `GOVERNANCE` の保持の変更だけ許可、`COMPLIANCE` と迂回は拒否 | 2026-11-11、エージェント（ReadOnly） |

## R5 の切り分け（2026-11-11）

**原因: 保持を延ばす要求では、ホールドの要求でも、S3 が条件キー `s3:object-lock-retain-until-date`（と `s3:object-lock-remaining-retention-days`）を埋める。** ジョブのロールの `DenyFixedRetention` は「`retain-until-date` があれば拒む」なので、保持の無い版に 30 日のホールドを付ける要求（R5）を拒んだ。シミュレーターは与えたキーしか評価しないので、見抜けなかった。

- トレイルの記録: 2 件とも `PutObjectLockRetention`（CloudTrail での名前。`PutObjectRetention` ではない）、`AccessDenied`、`invokedBy: batchoperations.s3.amazonaws.com`。本文（`retention`）は記録されない。受け取った大きさ 211 バイトは、XML の宣言つきの「モード・ON・30 日」の本文と一致し、期限は付いていなかった（ジョブは指定どおりに送っている）。
- 切り分け: `~/runbook/canary-rehearsal/condprobe.sh`（git の管理外）。worm-probe のバケット（バケットポリシーを外した）で、一時的なロール `worm-probe-condprobe` に Deny を 1 文ずつ入れ、4 種類の要求が拒まれるかを見た（07:07〜07:09 UTC、ログ `20261111-160718-condprobe-run.log`）。拒まれた＝そのキーが要求に載っている。

| 条件キー | ホールド ON（今と同じ 1 日） | ホールド ON（2 日に延ばす） | 解除（OFF） | 固定の期限（+3 日） |
|---|---|---|---|---|
| `s3:object-lock-retain-until-date` | 無し | **有り** | 無し | 有り |
| `s3:object-lock-remaining-retention-days` | 無し | **有り**（`> 1` に当たる。1 日のときは当たらない） | 無し | 有り |
| `s3:object-lock-event-hold-duration-days` | 有り | 有り | 無し | 無し |
| `s3:object-lock-event-hold` | 有り | 有り | 有り | **無し** |
| `s3:object-lock-mode` | 有り | 有り | 有り | 有り |

- 「今と同じ日数」のホールドの要求で期限のキーが無いのは、保持が延びないから、とみる（R5 は保持の無い版なので延びる側）。
- ほかの文は効いている: 解除は期限のキーを持たないので止まらない。日数のキー（`DenyUnexpectedEventHoldDuration`）とモードのキー（`DenyComplianceRetention`・バケットポリシーの `DenyComplianceMode`）は、必要な要求に載る。
- **直し方:** `DenyFixedRetention` の条件を「`s3:object-lock-event-hold` が無い」（`Null: true`）に変える（固定の期限だけの要求を止める）。ホールドに最低の期限を混ぜる要求は、これでは止まらないので、「`s3:object-lock-remaining-retention-days` が `EVENT_HOLD_DAYS` を超える」（`NumericGreaterThan`）を拒む文を足す。
- 境目（T7、07:13 UTC）: 「`remaining-retention-days` が 2 を超えたら拒む」文で、1 日から 2 日に延ばす要求は当たらなかった（日数ちょうどの値が入る）。固定の期限（+3 日）は当たった。新しい文の境目は `EVENT_HOLD_DAYS` のままでよい。
- worm-probe に残ったもの: バケットポリシーは外したまま（片付け待ち）。試しの版のうち t2・t3 は固定の期限が 2026-11-14 07:08 UTC まで残る。試験用のロールは cleanup で消す。

