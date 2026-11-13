# 第 2 段階の段階 1・2（td1-rlog、tuscenes-calibration の旧・新）に Object Lock を入れる手順書

- 作成: 2026-11-11 ／ 伊藤（エージェントが起草）
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)。段階の正本 [worm-rollout-stages.md](worm-rollout-stages.md) の「手順 C」の段階 1（td1-rlog）と段階 2（tuscenes-calibration の旧・新）。2026-11-12 に段階を並べ直し、もとの段階 1 の 3 本が段階 1・2 になった。td1-rlog を最後まで通してから、旧・新を続けて行う。アクションの 4-7
- 状態: **段階 1（td1-rlog）・段階 2（tuscenes-calibration の旧・新）とも、ホールドを付け終えた**（td1-rlog の verify は 2026-11-13）。**2026-11-13 に 3 本とも 15 日へ付け直した**（D34）。残りは層の比べ（11-13 の値が出るのを待っている）
- 実行する人: 伊藤（`full` プロファイル＝tuscenes-prod の SSO の FullAccess）。ジョブは確認待ちで止め、エージェントがログと ReadOnly で件数と中身を確かめてから流す（2 人目の確認はやめた。D33）。エージェントは、ログと ReadOnly の確認で結果を読み、書き込みのエラーをトレイルで見る
- スクリプト: `~/runbook/worm-stage/worm-stage.sh`（git の管理外）。段階 2・3 でも同じものを使う。ログは `~/runbook/worm-stage/log/` に、バケットと手順ごとに残る

予行（[canary-rehearsal-runbook.md](canary-rehearsal-runbook.md)）と同じ操作を、原本バケットに 1 本ずつ行う。段階 1 の 3 本は、書き込みがほとんど無く、件数も少ない。

## 0. 始める前の条件

| # | 条件 | 状態 |
|---|---|---|
| 0-1 | 解除後の保持期間を決める（アクションの 4-3） | **済み**（2026-11-12。30 日で固定。cdk-apps の `EVENT_HOLD_DAYS` とスクリプトの `HOLD_DAYS` は 30 のままでよい） |
| 0-2 | ~~ジョブの設定を確かめる 2 人目を決める（4-4）~~ | **不要とした**（2026-11-12。D33。日数・モード・バケットはロールとスクリプトが縛る。手順 4 の確かめはエージェントが行う） |
| 0-3 | 3 本の書き込み元が、チェックサムを付けて書いていること（1 章） | **済み**（2026-11-11。[writer-survey-1111.md](writer-survey-1111.md)。td1-rlog と旧は 12 日間書き込みなし、新は backend-api だけで付けている） |
| 0-4 | tuscenes-calibration（新）の書き手（backend-api）の設定 | **済み**（2026-11-11。下の 1 章） |
| 0-5 | 3 本のバケットポリシーに、守りの 5 文がそろっていること | **済み**（2026-11-11 の deploy のあと） |

## 1. 3 本の状態と書き込み元

| バケット | 暗号化 | ライフサイクル | 書き込み元 |
|---|---|---|---|
| `tuscenes-calibration`（旧） | SSE-S3 | Intelligent-Tiering への移動だけ（失効なし） | 10-30〜11-11 の 12 日間、書き込みなし |
| `tuscenes-calibration-767397804933`（新） | **SSE-KMS**（AWS 管理のキー `aws/s3`） | なし | backend-api の Lambda（JADD STUDIO の確定版のリリース）。boto3 1.42.11 の既定のクライアントで、チェックサムの設定を変えていない（mono-e2e の `routers/wheel_calibration.py`、cdk-apps の Lambda の環境変数にも無い）。CRC32 が付く。12 日間の 13 件の書き込みも、userAgent の記号でチェックサムを付けていた（実際の boto3 は 1.43 系）。予行の R2 で、条件付き書き込みも通った |
| `td1-rlog` | SSE-S3 | Intelligent-Tiering への移動だけ（失効なし） | 10-30〜11-11 の 12 日間、書き込みなし |

## 2. 手順（1 本ずつ）

順番は **td1-rlog → tuscenes-calibration（旧）→ tuscenes-calibration（新）**。最後の 1 本だけ SSE-KMS なので、ほかの 2 本で手順に慣れてから行う。

```bash
aws sso login --profile full         # 切れていれば
cd ~/runbook/worm-stage
B=td1-rlog                           # 段階 1
CAL_OLD=tuscenes-calibration         # 段階 2（旧）。下の表の $B をこの変数に読み替える
CAL_NEW=tuscenes-calibration-767397804933   # 段階 2（新）
```

| 手順 | コマンド | すること | 終わったら |
|---|---|---|---|
| 1 | `bash worm-stage.sh check $B` | 今の状態を出す（守りの 5 文がそろっているか） | — |
| 2 | `bash worm-stage.sh enable $B` | Object Lock を有効にする。**戻せない**。バケット名の打ち込みを求める | — |
| 3 | `bash worm-stage.sh default $B` | 既定の保持設定を入れる。これ以降の書き込みにチェックサムが要る | **エージェントに知らせる**。エージェントが 1 日ほど、書き込みのエラーをトレイルで見る |
| 4 | `bash worm-stage.sh hold $B` | 最新の版にホールドを付けるジョブを作り、確認待ちで止める。件数と先頭の 5 件を出す | **エージェントに知らせる**。エージェントがログと ReadOnly で、(1) 一覧の件数がバケットの最新の版の数（`list-objects-v2` で数える。プレフィクスで絞ったときはその範囲）と合うか、(2) プレフィクスの指定が意図どおりか、(3) 操作がガバナンス・30 日のイベントホールドか、を確かめる。合っていれば手順 5 |
| 5 | `bash worm-stage.sh run $B` | 確認待ちのジョブを流す。バケット名の打ち込みを求める | — |
| 6 | `bash worm-stage.sh verify $B` | 失敗の内訳と、一覧から選んだ 20 件の保持を出す | **エージェントに知らせる** |
| 4〜6 をまとめて | `EXPECT=最小:最大 bash worm-stage.sh apply $B` | 2026-11-13 に足した。起動のときにバケット名を 1 回打ち込むと、hold → 確かめ（ジョブの設定と一覧の中身。手順 4 の確かめをスクリプトが行う）→ run → verify を人を待たずに行う。確かめが外れたら流さずに止まる。PC が要るのは確かめから流し始めるまでと verify だけで、途中で止まっても同じコマンドで続きから。`DETACH=1` で待たずに抜ける。使い方はスクリプトの冒頭 | 出力を**エージェントに知らせる** |

- **書き込みが止まったら:** `bash worm-stage.sh rollback $B`。既定の保持設定を外すと、すぐ書けるようになる（予行の R3）。外していたあいだの版には、入れ直したあと hold からやり直して付ける。
- **td1-rlog では、手順 4〜6 を 2 回に分ける（層が上がらないかの確かめ。2026-11-12 に決めた）:** ホールドを付けると Intelligent-Tiering の層が Frequent Access に戻るか（＝「アクセス」と数えられるか）が、AWS のドキュメントに書かれていない（`PutObjectRetention` は、層が上がる操作の一覧にも、上がらない操作の例にも無い）。もし上がると、9 本で約 $7.5 万の追加の費用になる（Archive Instant Access 約 2,000 TB が 90 日、Infrequent Access 約 260 TB が 30 日、高い層に居る。ほとんどが td1-raw と tuscenes-raw）。td1-rlog は 21 TB がすべて Archive Instant Access で書き込みも無いので、ここで確かめる。
  1. 1 回目: `bash worm-stage.sh hold td1-rlog calibration/` → 確かめ → `run` → `verify`。`calibration/` は 26,778 件・89.7 GB（最終の書き込みは 2025-03-19）。最悪でも追加の費用は約 $3。
  2. ~~1〜2 日待ってから 2 回目~~ → **2026-11-12 に変えた: 待たずに、プレフィクスなしで 2 回目を流す**（伊藤）。層が上がっても td1-rlog の追加は最大で約 $750（Archive Instant Access 21 TB）で、許せる額とした。確かめは続けられる: 上がるなら td1-rlog の Frequent Access が約 21 TB 増える（読まれた分の 11.6 GB と取り違えない）。tuscenes-calibration（旧）の 1.26 TB も、確かめの 2 本目として残る。
  3. 11-13〜14 に、エージェントが CloudWatch の `BucketSizeBytes`（`IntelligentTieringAIAStorage`・`IntelligentTieringFAStorage`）を、下の元の値と比べる。**Frequent Access が大きく増え、Archive Instant Access が同じだけ減っていれば、層が上がった**。そのときは、段階 4 の td1-raw・tuscenes-raw の進め方を考え直す（AWS サポートの人の担当者に文書での回答を頼む、など）。
  - 元の値（11-11 の値、バイト）: Frequent Access 11,579,536,878、Archive Instant Access 21,041,754,089,562、Standard 2,181,507,551、Infrequent Access なし。
  - **注意:** 11-06 → 11-07 に、Archive Instant Access から 11,579,536,878 バイト（約 11.6 GB）が Frequent Access に上がっている（誰かが読んだとみられる。読み取りはトレイルに記録していないので、誰かは分からない）。ときどき読まれるので、増えた量が 89.7 GB と合うかで判断する。この 11.6 GB は、30 日たつ 12-06 ごろに Infrequent Access に下りるはず。
  - 1 回目の一覧の件数は、`calibration/` の 26,778 件と合うかで確かめる（2026-11-12 に ReadOnly で数えた）。
- **SSE-KMS の tuscenes-calibration（新）:** 手順 4 で、まず小さいプレフィクスに絞る（例: `bash worm-stage.sh hold $B calibration_results/`）。通ったら、プレフィクスなしで全体を流す（すでに付いた版にもう一度付けても、日数が同じなので何も変わらない）。カナリアは SSE-S3 なので、KMS の振る舞いは予行で確かめていない。
- **一覧は作った時点の写し:** 手順 3 のあとに手順 4 を行う（既定の保持設定を入れたあとに書かれた版は、既定から保持が付く）。
- **2026-11-13 に、3 本の既定の保持設定を 15 日に変えた**（D34。02:23:30Z td1-rlog、02:23:44Z 旧、02:23:57Z 新。ReadOnly で 15 日を確かめた）。これ以降に書かれる版は解除から 15 日、ジョブで付けた版は 30 日のまま。
- ジョブの結果のレポートは、失敗した件だけを書く（件数が多いバケットで、レポートが大きくならないように）。

## 3. 終わった条件

- 3 本とも、既定の保持設定を入れてから数日、書き込みのエラーが無い（エージェントがトレイルで見る）。
- 3 本とも、ジョブが `Complete` で、失敗が 0 件。verify の 20 件が `GOVERNANCE ON 30`。

## 結果

| バケット | enable | default | hold・run | verify | メモ |
|---|---|---|---|---|---|
| td1-rlog | 2026-11-12 03:04:15Z | 03:06:01Z | 1 回目（`calibration/`）: ジョブ `3f248203-adb1-4225-814f-f0c61047025a`、26,778 件 `Complete`・失敗 0。2 回目（全体、プレフィクスなし）: ジョブ `d50af3e2-c6ef-4009-a53f-1adefcbdba24`、4,555,379 件（数えた最新の版の数と一致）`Complete`・失敗 0。一覧づくり 06:59:59 →、`run` 08:28Z、終了 09:54:52Z | 1 回目: 04:17Z、失敗 0、20 件とも `GOVERNANCE ON 30`。2 回目: 2026-11-13 00:40Z、失敗 0、20 件とも `GOVERNANCE ON 30`（すべて `null` の版） | **1 回目の時間（見積もり用）:** 一覧づくり約 30 秒（03:06:38 作成 → 03:07:12 ごろ確認待ち）、`Active` 34 秒（約 790 件/秒。立ち上がり込みなので遅めに出る）、流し始め → 終了 約 1 分（03:10 → 03:11:16）。版の ID が `null`（版管理の前に書かれた版）にも付いた。`head-object` の `ObjectLockRetainUntilDate` はホールド中は「今＋30 日」と出るだけ（予行の R7）。**2 回目の時間（3 点目）:** `Active` 5,140 秒、約 886 件/秒。ジョブ 1 本の速さ約 890 件/秒は、455 万件でも変わらない。トレイルの `PutObjectLockRetention` は 4,557,667 件で、差の 2,288 件はすべて eventID が同じ記録の重複（CloudTrail が 2 回届けたもの）。層の比べは 11-13〜14。手順 4 の突き合わせ用: 最新の版の数 **4,555,379**（2026-11-12 01:06〜01:40 UTC、ReadOnly の `s3 ls --recursive` で数えた。34 分かかった）。CloudWatch の `NumberOfObjects` は 4,557,929 で、差の 2,550 は古い版・削除マーカーとみる |
| tuscenes-calibration（旧） | 2026-11-12 04:59:06Z | 05:25:20Z | ジョブ `5895f860-b745-455f-89bc-201c95cb03bd`、271,399 件（`s3 ls` の数と一致、プレフィクスなし）`Complete`・失敗 0 | 06:09Z、失敗 0、20 件とも `GOVERNANCE ON 30`（すべて `null` の版） | **時間（見積もり用）:** 一覧づくり約 32 秒（05:26:22 作成 → 05:26:55 確認待ち。td1-rlog とほぼ同じで、件数によらない）、`Active` 310 秒（約 875 件/秒）。進み方は、最初の約 1 分は 0 件、そのあと 1 分あたり 4〜7 万件。td1-rlog の 1 回目と合わせて「決まってかかる時間 + 件数 ÷ 速さ」に当てはめると、決まってかかる時間は約 4 秒、速さは約 890 件/秒（ジョブ 1 本あたり）。層の比べの 2 本目。元の値（11-11、バイト）: Archive Instant Access 1,256,075,511,079、Standard 4,909,212,180、Frequent Access・Infrequent Access なし。上がれば Frequent Access に約 1.26 TB が出る。最新の版の数 271,399（CloudWatch は 271,914） |
| tuscenes-calibration（新） | 2026-11-12 06:13:11Z | 06:15:19Z | まず `backup/` の 13 件（ジョブ `ca8e13d6-d62e-4773-a01b-60e7a6dff913`、失敗 0）、続けて全体の 309 件（ジョブ `5d7f4732-cfa2-41ba-8542-c3634ee23efc`、`s3 ls` の数と一致、`Complete`・失敗 0、`Active` 8 秒） | 06:33Z、失敗 0、20 件とも `GOVERNANCE ON 30`（`null` の版と、ふつうの版の ID の両方） | **SSE-KMS（`aws:kms`）の版にも付いた。KMS の権限の追加は要らない**（`PutObjectRetention` は中身を読み書きしないため、とみる）。ポリシーの先頭に `Sid` の無い文（471112873671・586794486929 に `Get*`・`List*` を許す）があるが、もとからのもの（current-state.md）。いちばん新しい書き込みは 11-09 11:02Z。既定の保持設定を入れた 06:15Z 以降の backend-api の書き込みが通るかを、トレイルで見る |

### 15 日への付け直し（2026-11-13、D34）

すでに 30 日で付いた版に、ジョブで 15 日のホールドを付け直した（伊藤が実行）。付け直した版の保持期限は「付け直した時刻＋30 日」で固まり、付け直してから 15 日たつと再び「読んだ時刻＋15 日」で動き出す、と見ている（推測。11-28 ごろにカナリアで確かめる。学習用の資料の 3.1）。

| バケット | ジョブ | 件数・結果 | verify | メモ |
|---|---|---|---|---|
| tuscenes-calibration（新） | `99cf84b1-ce4c-4965-bc9c-50a9bc88fc8f`（hold 03:16Z、run 04:09Z ごろ） | 309 件（`s3 ls` の数と一致）、`Complete`・失敗 0、`Active` 6 秒 | 04:15Z、20 件とも `GOVERNANCE ON 15` | エージェントが ReadOnly で一覧（309 行、すべて最新の版、削除マーカーなし）を確かめてから流した |
| tuscenes-calibration（旧） | `14366a2d-8c8c-4951-8764-ab83cd7a1ff2`（hold 04:18:55Z、run 04:25Z ごろ → 04:31Z） | 271,399 件（`s3 ls` の数と一致）、`Complete`・失敗 0、`Active` 306 秒（約 887 件/秒） | 04:32Z、20 件とも `GOVERNANCE ON 15` | トレイルの `PutObjectLockRetention` は 271,405 件。差の 6 件は eventID が同じ記録の重複。ジョブのロール以外の操作・拒否は無し |
| td1-rlog | `d527eadb-5592-4102-aef2-e5a3a28c3fd4`（`apply`。作成 06:35:58Z、流し始め 06:45:45Z） | 4,555,379 件（11-12 の数と一致）、`Complete`・失敗 0 | `apply` の verify で 20 件とも `GOVERNANCE ON 15` | **`apply` の初めての実地。** 15 項目の確かめがすべて OK で、人を待たずに verify まで通った |
