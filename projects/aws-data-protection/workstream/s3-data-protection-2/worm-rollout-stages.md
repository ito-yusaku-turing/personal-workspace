# 原本バケットの WORM 化: 導入の段階

- 作成: 2026-11-09 ／ 伊藤（エージェントが起草）
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)
- 状態: **第 1 段階の PR をレビュー中**（[cdk-apps#2500](https://github.com/turingmotors/cdk-apps/pull/2500)。2026-11-10 に gaming-data-collection と denso-raw を外し、tuscenes-annotation を戻した）
- 使い道: 導入の段階の正本。ここから、共有用の資料（[notion-worm-governance-rollout.md](../../documents/notion-worm-governance-rollout.md)）の 1 章・4 章と、cdk-apps の各 PR の本文（[pr-step-a.md](pr-step-a.md) など）を作る。段階を変えたら、先にここを直す
- 前提: [worm-decisions.md](worm-decisions.md)（D1〜D24）、[permission-model.md](permission-model.md)（層と抜け穴）

**要点**

- 導入は 3 つの段階で進める。**部品を置く → Object Lock を入れる → 抜け穴を塞ぐ。**
- 第 1 段階と第 3 段階は cdk-apps の PR、第 2 段階は CLI と S3 Batch Operations の作業。
- どの段階も、日々の読み取り・書き込み・上書き・通常の削除は止めない。止まりうるのは、チェックサムを付けない書き込みだけで、第 2 段階で、書き込みの少ないバケットから順に確かめる。

## 対象のバケット

| 区分 | バケット |
|---|---|
| **Object Lock を入れる 9 本** | `td1-raw-767397804933`、`tuscenes-raw-767397804933`、`td1-rlog`、`tuscenes-calibration`、`tuscenes-calibration-767397804933`、`tuscenes-annotation-767397804933`、`denso-nx-raw-767397804933`、`denso-taxi-processed-767397804933`、`denso-taxi-video-767397804933` |
| 入れない 3 本 | `tuscenes-model-767397804933`、`gaming-data-collection-767397804933`、`denso-raw-767397804933`（tuscenes-model は費用をかければ作り直せ、入れ替わりが激しいため。gaming-data-collection はシミュレータで集めたデータで、収集を終えている。2026-11-10 に持ち主が除外を了承。denso-raw は持ち主が退職して不在で、使われた形跡も無いため。2026-11-10 に除外を決めた。tuscenes-annotation は 2026-11-10 に対象に戻した（人手のラベルで、付け直すのが難しい）。バージョニングと守りのバケットポリシーは残る） |
| カナリア | `original-bucket-canary-767397804933`。原本バケットと同じ守り（バージョニング・守りのバケットポリシー）を入れた検証用のバケットで、原本のデータは置かない。`apps/original-bucket-audit` の `OriginalBucketCanary` スタックが持つ。手順を原本バケットに入れる前に、ここで試す |

原本バケットは、上の 9 本と 3 本の計 12 本。どれも tuscenes-prod（767397804933）の us-west-2 にある。

## 全体

| 段階 | 目的 | 手順 | 形 | 終わった時点の姿 |
|---|---|---|---|---|
| 第 1 段階 | 部品を置く | A | cdk-apps の PR 1 本 | 迂回の禁止がバケットポリシーに入り、ジョブのロールとレポートの置き場ができている。止まる操作は無い |
| 第 2 段階 | Object Lock を入れる | B（カナリアで予行）→ C（段階 1〜3 の順に各バケットへ） | CLI と S3 Batch Operations の作業 | 対象の 9 本で、新しく書かれる版と、今ある最新の版が保護されている |
| 第 3 段階 | 抜け穴を塞ぐ | 通知 → D | cdk-apps の PR 2 本（通知、手順 D）と、組織のポリシー | 保護を外せるのは完全削除用の権限（AWSAdministratorAccess）がジョブを作ったときだけ。解除と設定の変更は通知される |

## 第 1 段階: 部品を置く（手順 A）

第 2 段階の作業に要る部品を、先に置く。

| 部品 | 中身 | 置き場 |
|---|---|---|
| 迂回の禁止 `DenyGovernanceBypass` | Object Lock の保持の迂回（`s3:BypassGovernanceRetention`）を、全員に禁じる文。原本バケット 12 本とカナリアのバケットポリシーに入る | `packages/original-bucket-guard` |
| 保持の変更の禁止 `DenyLockChange` | 保持の変更（`s3:PutObjectRetention`）とリーガルホールドを、ジョブのロール以外の全員に禁じる文。似た権限のロールを新しく作っても拒否される。2026-11-10 に第 3 段階から前倒しした（D31） | `packages/original-bucket-guard` |
| コンプライアンスモードの禁止 `DenyComplianceMode` | コンプライアンスモードの保持を付ける書き込み・保持の変更を、全員に禁じる文（2026-11-10 のレビューで足した） | `packages/original-bucket-guard` |
| ジョブのロール `original-bucket-lock-batch` | S3 Batch Operations だけが使えるロール。原本バケット 9 本とカナリアの版の保持を付ける・外す・読むことと、ジョブに対象の一覧を作らせることだけができる。版の削除・迂回・タグ付けはできない | `apps/original-bucket-audit` |
| レポートの置き場 `original-bucket-lock-batch-reports-767397804933` | ジョブが作った対象の一覧と、1 件ずつの結果を残す。何に保護を付けたかの記録なので、消さない。原本バケットと同じ守りのバケットポリシーを入れる | `apps/original-bucket-audit` |

- **変わらないこと:** 今は Object Lock が無いので、迂回・保持の変更・コンプライアンスモードの禁止が止める操作は無い。ジョブのロールも、ジョブを作るまで何もしない。
- **これらの禁止を先に入れる理由:** 第 2 段階で Object Lock を入れたその時から、保護された版を迂回して消せず、ジョブのロール以外は保持を外せない状態にするため。第 2 段階で FullAccess が行うのは Object Lock の設定とジョブの作成で、保持の変更はジョブのロールが行うので、先に入れても作業は止まらない。
- **第 3 段階まで残る穴:** ジョブのロールを渡す操作とロールの変更の禁止（組織のポリシー）は第 3 段階で入る。それまでは、ジョブを作れて、このロールを渡せる主体（FullAccess など）なら、このロールで解除のジョブを作れる。
- **誰が:** 伊藤が PR を作り、チームがレビューする。deploy は GitHub Actions（`main` へのマージ）。
- **終わった条件:** deploy が済み、3 つの部品ができている。

## 第 2 段階: Object Lock を入れる（手順 B・C）

### 手順 B: カナリアで予行する

手順書: [canary-rehearsal-runbook.md](canary-rehearsal-runbook.md)（2026-11-11）。

カナリア（上の「対象のバケット」）に、後から Object Lock を入れて試す。カナリアは、そのあとも Object Lock を入れたまま、手順の訓練に使う。

確かめること:

- 既存のバケットに、後から Object Lock を有効にしたときの振る舞い。
- 既定の保持設定を外すと、チェックサムなしで書けるようになるか（書き込みが止まったときの戻し方）。
- ジョブのロールで、対象の一覧を作らせてイベントホールドを付けるジョブが通るか（このロールの形では初めて流す）。外すジョブが通るか。
- ジョブのロールと、バケットポリシーの `DenyComplianceMode` で、コンプライアンスモードの保持を指定すると拒まれるか。**確かめ方**（2026-11-10 のレビューの提案を採用）:
  1. 先に IAM ポリシーシミュレーター（`aws iam simulate-principal-policy`、`--context-entries` で `s3:object-lock-mode=COMPLIANCE` を与える）で、ロールの判定を見る。何も変えずに、ポリシーの書き方を確かめられる。
  2. 実際の要求は **1 件だけ、イベントホールドではなく固定の期限（翌日）** で試す。ジョブのロールは固定の期限そのものを拒む（`DenyFixedRetention`）ので、ロールの `DenyComplianceRetention` を切り分けて見るのはシミュレーターで行う。バケットポリシーの `DenyComplianceMode` も、シミュレーター（`simulate-custom-policy` の `--resource-policy`）で見る。FullAccess からの実際の要求は、先に `DenyLockChange` で拒まれるので、`DenyComplianceMode` の切り分けには使えない。拒否が効かなかったときの被害を、1 件・1 日に抑えるため。イベントホールドで試して効かなかった場合、解除の要求にもモード `COMPLIANCE` が載るので、同じ Deny でジョブのロールからは外せなくなる。
  3. 保持の変更の要求が、モードや期限の条件キーをどう持つかも、このとき見る（固定の期限も止めるかを、これで決める）。
- DataSync が、Object Lock のバケットに書き込めるか。
- （解除後の保持期間をロールで固定する場合）30 日以外の日数・年での指定・固定の期限が拒まれ、30 日のホールドと解除が通るか。あわせて、ホールド中の版の日数を延ばす・縮めるとどうなるか（縮めるのに迂回が要るか。AWS のドキュメントに書かれていない）。あとから日数を変えるときの手順の確かめになる。

ジョブに対象の一覧を作らせる方法（ManifestGenerator）は、2026-11-09 にカナリアで確かめた。一覧には最新版だけが版の ID つきで入り、古い版と、最新が削除マーカーのキーは入らない。確認待ちの設定で止めて、流す前に一覧を確かめられる（[manifest-generator-probe-runbook.md](manifest-generator-probe-runbook.md)）。

### 手順 C: 各バケットに入れる

書き込みが少なく、書き込み元の問題が無いものから入れる。

| 段階 | バケット | 理由 |
|---|---|---|
| 1 | td1-rlog | 12 日間の書き込みが 0 件。最初の 1 本として、手順を最後まで通す（2026-11-12、伊藤） |
| 2 | tuscenes-calibration（旧）→（新） | 旧は書き込み 0 件。新は backend-api だけ（12 日間で 13 件、チェックサムあり）で、SSE-KMS。段階 1 に続けて入れる |
| 3 | denso-nx-raw | 書き込みは 0 件だが、DataSync のタスクが毎日動いている。書き込みのジョブを精査し、作った人（Inuzuka さん）に確かめてから入れる |
| 4 | 残りの 5 本（denso-taxi-processed、denso-taxi-video、tuscenes-raw、tuscenes-annotation、td1-raw） | 段階 3 までが済んだら、まとめて進める。それぞれの前に要るものは下の「段ごとの前に」 |

2026-11-12 に並べ直した（伊藤）。それまでは 3 段階（1: calibration の新・旧と td1-rlog、2: denso の 3 本と tuscenes-annotation、3: td1-raw と tuscenes-raw）だった。並べ直した理由: 書き込みの見直し（[writer-survey-1111.md](writer-survey-1111.md)）で、tuscenes-annotation は td1-raw に次いで書き込みが多く（12 日間で約 49 万件）、tuscenes-raw は書き込みが 0 件と分かり、旧の段階 2・3 の分け方が実際の重さと合わなかった。重さには、既定の保持設定で書き込みを止めるおそれ（書き込みの多さ）と、ジョブの費用と時間（版の数）の 2 つの軸がある。

各バケットでの作業:

1. Object Lock を有効にし、既定の保持設定（ガバナンスモード、イベントホールド、解除後の保持期間 15 日。2026-11-13 に 30 日から変えた。D34）を CLI で入れる。**有効にする操作は戻せない。**
2. 1 日ほど、書き込み元のエラーを見る。
3. S3 Batch Operations のジョブで、最新の版にイベントホールドを付ける。対象の一覧はジョブに作らせ、確認待ちで止めて、件数と中身（プレフィクス・操作）を確かめてから流す（2026-11-12 に 2 人目の確認をやめた。D33）。2026-11-13 から、この確かめはスクリプト（`worm-stage.sh apply`）が行い、通れば人を待たずに流す。件数の範囲（`EXPECT`）は、エージェントが ReadOnly で見積もって渡す。バケットごとに 1 本で、バケットどうしは並列に流す。
4. 付いた件数を確かめる（`apply` が最後に verify まで行う。エージェントが出力とトレイルを読む）。

**段階 3・4 の結果（2026-11-13、伊藤が実行）:** 段階 4 は、Intelligent-Tiering の層が上がらない前提で、書き込みの無い 3 本を段階 3 と同じ日に入れた（`default` のあとの 1 日の様子見は、書き込みが無いので省いた）。バケット名の打ち込みは、承認済みの一覧（`worm-stage.sh` の `APPROVED`）で省いた。

| バケット | enable・default（15 日） | すでにある版のホールド |
|---|---|---|
| denso-nx-raw | 07:54:39Z・07:54:47Z | `apply`（ジョブ `b159f91a-cd0f-47bb-b46c-913fae555ee5`）。187,833 件、失敗 0、08:05Z に済み。見本 20 件とも `GOVERNANCE ON 15` |
| denso-taxi-processed | 07:54:54Z・07:55:03Z | `DETACH=1` の `apply`（ジョブ `71c8149c-0b12-4a90-b03f-446347658f22`、08:17Z）。一覧づくりの途中。`EXPECT=10137617:11376659` |
| denso-taxi-video | 07:55:11Z・07:55:20Z | 同（ジョブ `cf1c9692-f0ed-48ff-b4aa-2939c1c58829`）。`EXPECT=17725105:19891507` |
| tuscenes-raw | 07:55:26Z・07:55:35Z | 同（ジョブ `186e879f-1391-420e-ae3f-676d18bd57c1`）。`EXPECT=184972196:207579909` |

`EXPECT` は、CloudWatch の `NumberOfObjects`（11-12、全版）を上限に、その 90% を下限にした（バージョニングは 10-20 からで古い版は少ない。denso-taxi は 6% を数えて推した値も CloudWatch に近かった）。denso-taxi-video・tuscenes-raw のポリシーの `Sid` の無い文は、ほかのアカウントに読むことだけを許す文（ReadOnly で確かめた）。

**td1-raw は、e2e-dev で先に試す（2026-11-13、アップロード用の PC を管理する徳弘さんと合意）。** e2e-dev の `td1-raw-471112873671` に、バージョニング（それまで入っていなかった）・Object Lock・既定の保持設定（ガバナンス・イベントホールド・**1 日**）を入れた（伊藤、e2e-dev の Full。e2e-dev には守りの 5 文も ReadOnly のプロファイルも無い）。ここに本番の 6 つの CLI の版（2.15.58・2.16.9・2.23.7・2.25.8・2.38.5・2.40.1。11-11〜13 のトレイルで数えた）で書いてもらい、チェックサムが必須の状態で書けるかを確かめる。本命は 2.15・2.16（2 日で約 8,300 件。チェックサムが既定になる前の版）。e2e-dev のこのバケットには、別アカウント（582491218614）の `jetson-aws-access-role` も `PutObject` できる（ポリシーの `AllowOtaJetsonRead`）ので、既定の保持設定を入れているあいだは、その書き込みが拒まれうる。本番の td1-raw は、この結果と 4c-2（LiDAR にもホールドを付けるか）を見てから入れる。

段ごとの前に決める・確かめること（2026-11-10 に分かったもの）:

- 段階 2: tuscenes-calibration（新）は、JADD STUDIO の確定版のリリース（backend-api の Lambda、boto3 1.42、条件付き書き込み `IfNoneMatch`）が書く。予行で、Object Lock のバケットでもこの書き方が通るか確かめる（予行の R2 で確かめた）。
- 段階 3: denso-nx-raw の DataSync のタスク（`azure-mlops1-dcorp-inbound-daily`）の設定と、ほかの書き手の有無を精査し、作った人に確かめる。→ **済み（2026-11-13）**。DataSync は書き込みにチェックサム（SHA256）を付けていると S3 の記録から分かったので、**DataSync の試し（[datasync-probe-runbook.md](datasync-probe-runbook.md)）は行わない**（伊藤の判断）。denso-taxi の 2 本も同じ（[denso-nx-raw-writer-review.md](denso-nx-raw-writer-review.md)）。
- 段階 4: denso-taxi の 2 本は、DataSync のスケジュールが止まっている（再開する前に、段階 3 の結果を当てはめる）。tuscenes-annotation には、人手のラベルのほかに自動の処理の出力が毎日書かれる。既定の保持設定はバケット全体に効くので、自動の出力にも保持を付けるかを先に決める（アクション 4c-1）。
- 段階 4: tuscenes-annotation には TeamE2E の人が手で書くので、チェックサムを付けない道具（s5cmd など）を使わないよう、先にチームに知らせる。
- 段階 4: td1-raw の LiDAR の間引きの残りと `LidarDeleter` の扱いを先に決める（アクション 4c-2）。アップロード用の PC の古い CLI の設定（`when_required` にしていないか）も確かめる。
- 段階 4: td1-raw・tuscenes-raw は版の数が多い（計約 5.9 億、費用の 9 割）。ジョブはプレフィクスで小さく流してから全体を流す（I6）。
  - **時間（2026-11-12 に測った）:** ジョブ 1 本は件数によらず約 890 件/秒（2.7 万・27 万・455 万件で同じ）。一覧づくりは 455 万件で約 5 分 20 秒（約 1.4 万件/秒）。1 本で流すと tuscenes-raw 約 2.9 日、td1-raw 約 5.3 日。
  - **並列にする:** 同時に動かせるジョブはアカウントあたり 6 本（[batch-ops](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops.html)）。優先度は速さを変えない。AWS のブログでは 1 本で 10 億件を Active 約 24 時間（約 11,600 件/秒）で流した例があり、890 件/秒は 1 本の上限ではないかもしれない。re:Post では「速さはプレフィクスの分け方による」との答え。td1-rlog の 890 件/秒はプレフィクスあたりの PUT 3,500 件/秒より低く、失敗も 0 件なので、S3 の側の上限ではなく、ジョブ 1 本が送る量で決まっているとみる（推論）。
  - **段階 4 の最初に測る:** 重ならないプレフィクス（td1-raw は `collect/`・`control/`・`core/`・`journal/`・`swaglog/`・`troubleshooting/`、その下は車両。tuscenes-raw は `1.0/`・`2.0/`・`2.1/`・`2.2/`・`unit_test/`）で 2〜3 本を同時に流し、合計の速さを見る。伸びるなら 6 本まで増やす（6 本で約 5,300 件/秒なら、2 本の計約 6 億件が約 1.3 日）。分けるには、プレフィクスごとの件数が要る（S3 Inventory を伊藤が設定するか、`s3 ls` で数える。td1-raw は数時間かかる）。`worm-stage.sh hold` はプレフィクスを 1 つしか取らないので、複数を取るように直すか、1 本ずつ作る。AWS サポートの人の担当者に、速さの差の理由も聞く。
  - **2026-11-13 の判断（伊藤）: 1 つのバケットの中では分けず、バケットごとに 1 本で並列に流す。** 過去のデータなので急がない（td1-raw の約 5.3 日を受け入れる）。分けて手順を複雑にする価値は無い。上の「段階 4 の最初に測る」（プレフィクスで分けて速さを見る）は行わない。流し方は `worm-stage.sh apply`（起動 1 回で hold → 確かめ → run → verify。11-13 に足した）。
  - **同時に 6 本を超えたときの扱い（2026-11-13 に AWS サポートの AI bot に聞いた）:** 上限は「Active の 6 本」で、`Preparing`・`Suspended`・`Ready` は数えない。7 本目は `Ready` で待ち、空きができると自動で `Active` に移る。`Suspended`・`Ready` に期限は無い。終わったジョブ（`Complete` など）は 90 日後に消える。**ただし、どれも文書の同じ文（[batch-ops](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops.html)・[job status](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops-job-status.html)）からの推論で、7 本目の `UpdateJobStatus` がエラーにならないかは文書に無い、と bot 自身が書いている**。リージョンごとか否かも推論（すべて us-west-2 なので関係しない）。今回の対象は残り 6 本で、バケットごとに 1 本なら上限ちょうどに収まる。もし 7 本目の流す要求が拒まれても、`apply` は 5 回やり直して止まるだけで、ジョブは確認待ちのまま残る（あとで同じコマンドで続きから）。2 回目（速さ・層）の答え: 同時に動くジョブが速さを分け合うかは文書に無い。1 本の速さを上げる設定も無く、上げるならジョブを分けるしかない（どちらも文書に無いことの言い換え）。層は「上がらない」。理由は、Intelligent-Tiering の文書の「アクセスに当たる操作」の一覧（[intelligent-tiering-overview](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering-overview.html)。GetObject・PutObject・CopyObject など）に `PutObjectRetention` が無いこと。当たらない操作の一覧は「a sample, not a definitive list」なので、文書に名前は出ない（エージェントが原文で確かめた）。実測（CloudWatch の層ごとの容量）で確かめるのは変わらない。
- 段階 1 で、ホールドを付けると Intelligent-Tiering の層が上がるかを確かめる（ドキュメントに記述が無い。上がると 9 本で約 $7.5 万の追加の費用）。2026-11-12 に、td1-rlog（21 TB）と tuscenes-calibration（旧、1.26 TB）の全体に付けた（どちらも Archive Instant Access。上がっても 2 本で最大 約 $800 で、許せる額とした）。11-13〜14 に CloudWatch の層ごとの容量を元の値と比べる（[stage1-runbook.md](stage1-runbook.md) の手順 2 の下の注）。**段階 3・4 は、この結果を見てから進める**。上がったら、段階 4 の td1-raw・tuscenes-raw の前に進め方を考え直す。

`tuscenes-calibration-767397804933` だけは SSE-KMS（AWS 管理のキー `aws/s3`）で暗号化されている。カナリアでは確かめられないので、段階 2 で、このバケットは少ない件数で先に流す。

- **誰が:** 伊藤（FullAccess）。ジョブの件数と中身は、確認待ちのあいだにエージェントが確かめる。
- **終わった条件:** 段階ごとに数日、書き込みのエラーが無い。9 本の最新の版に、イベントホールドが付いている。

## 第 3 段階: 抜け穴を塞ぐ（通知・手順 D）

第 2 段階までで付けた保護を、外せる主体を絞り、外されたら気づけるようにする。

### 通知（cdk-apps の PR）

第 2 段階の作業には使わないので、別の PR にする。手順 A〜C と並行して進め、手順 D の前に入れる。

| 何を | どう拾うか |
|---|---|
| イベントホールドの解除 | EventBridge の `Object Retention Updated` のうち、`ON` 以外。CloudWatch のアラームでまとめて、SNS からメール |
| バケットの設定の変更（バケットポリシー・既定の保持設定・ライフサイクル・バージョニング・通知の設定・削除など）と、S3 Batch Operations のジョブの作成と状態の変更 | CloudTrail の管理イベント。拒まれた試みも拾う |
| 通知の仕組みそのものの変更 | 同上 |

- **前に決めること:** 通知の受け手。
- **終わった条件:** カナリアで、すべての通知が届く。

### 手順 D（cdk-apps の PR と、組織のポリシー）

| 何を | 中身 |
|---|---|
| FullAccess を例外から外す | 既存の 2 文（`DenyIrreversibleDelete`・`DenyProtectionRemoval`）の例外から FullAccess を外す。古い版の削除・バケットの設定の変更は、AWSAdministratorAccess と deploy の経路だけになる |
| ジョブのロールを守る組織のポリシー | ロールを渡す操作（`iam:PassRole`）を AWSAdministratorAccess だけにする。ロールの作成・削除・信頼の変更・ポリシーの変更を、deploy の経路以外に禁じる |
| deploy の経路を守る組織のポリシー | deploy のロールの引き受けを GitHub Actions の deploy のロールだけにする。cfn-exec-role を渡す操作を deploy のロールだけにする。`cdk-hnb659fds-*` のロールと GitHub Actions の deploy のロールの、作成・削除・信頼の変更・ポリシーの変更を禁じる |

- **前に済ませること:** AWSAdministratorAccess を持つ人の確認と、役を引き受けてもらえるかの相談。deploy のロールを引き受けている主体と、cfn-exec-role を渡している主体の確認（CloudTrail）。
- **止まるもの:** 手元の PC からの `cdk diff`（差分は GitHub Actions で取る）。`cdk bootstrap` のやり直し（組織のポリシーの例外を一時的に足す PR で行う）。
- **終わった時点の姿:** 保護を外せるのは、AWSAdministratorAccess の人がジョブのロールを渡してジョブを作ったときだけ。外しても、解除してから 30 日は消せない。解除と設定の変更は通知される。

## この計画のあとに残すもの

| もの | 中身 | 扱い |
|---|---|---|
| 既存のスタックの更新 | cdk-apps のスタックには deploy の経路のロールが付いたままなので、スタックを更新できる主体は、そのロールでバケットポリシーを書き換えられる | 把握した抜け道として残す。バケットポリシーの変更の通知で気づく。手当ては次の検討（D20） |
| バケットポリシーを書き換えられる主体 | AWSAdministratorAccess・deploy の経路・root・管理アカウントは、迂回の禁止を外せば、すぐ消せる | 受け入れる。変更の通知で気づく（D16） |
| 意図して消すときの手順 | 対象の決め方・承認・消す方法 | 消す必要が出たときに決める（D13） |
