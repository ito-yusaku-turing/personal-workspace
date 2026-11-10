# WORM の対象の残り 8 本の精査（2026-11-10）

denso-raw・gaming-data-collection を外したあと（D26・D27）、残りの 8 本も同じ観点で見直した。観点は、何のデータか・使われているか・写しがあるか・作り直せるか・入れる前に決めることがあるか。tuscenes-prod の ReadOnly と、手元の記録（第一弾の分類 [notion-bucket-classification.md](../done/raw-data-security/notion-bucket-classification.md)、[raw-data-security.md](../done/raw-data-security.md)、安本さんの調査書 [raw-data-security.md](../../documents/raw-data-security.md)）で調べた。

## 結論

**2026-11-10 の決定（D30）:** 外していた tuscenes-annotation（人手のラベル）を、安本さんの意見を受けて対象に戻した。対象は 9 本。自動の処理（物体検出・車線の自動ラベル、位置推定の毎晩の出力。開発用の試し出力を含む）も毎日書いているので、既定の保持設定でそれらにも保持が付く。扱いは未決。

**2026-11-10 の決定（D28）:** Inuzuka さんへの聞き取りを受けて、denso-taxi-video・denso-taxi-processed・denso-nx-raw を正式に対象とした。要確認は td1-rlog と tuscenes-calibration（旧）の 2 本になった。

**2026-11-10 の決定（D29）:** td1-rlog と tuscenes-calibration（旧）も対象とした。どちらも前の版の走行データで、単発で学習に使われた（2026-04 の読み出しと符号する）。重要性は低いが、唯一の原本で費用が安い（2 本で約 $34）。**これで対象の 8 本はすべて確定。** 残る決めごとは td1-raw の LiDAR の扱いだけ。

| 区分 | バケット | 理由 |
|---|---|---|
| **確定** | td1-raw | 今も毎日書かれている（直近 1 週間で 1 日 3〜10 万件）。高頻度層に 708 TB。依存が最も広い。2025-04 以降の TD1 の唯一の原本 |
| **確定**（11-10、D28） | denso-taxi-video | Azure 側の取り込み元は削除済みで、写しが無い。高頻度層に 404 TB（読まれている。Feature Cache） |
| **確定**（11-10、D28） | denso-taxi-processed | Azure 側の元データは削除済み。frame_timestamps は動画から作り直せない |
| **確定** | tuscenes-calibration（新） | 今も使われ、手で直したキャリブレーションの結果（`calibration_results/`・直した前の控えの `backup/`）がある。360 件で費用はほぼ 0 |
| **確定（入れる前に決めることあり）** | tuscenes-raw | Turing Pilot v1 の唯一の原本（2025-04 に収集を終えた）。全量が 90 日読まれていない層にあるが、2026-03・06 に数百 TB の一括の読み出しがあった。LiDAR は 2026-08〜09 に間引き済み（今の経路には `lidar/` が無い）。費用は約 $1,440 で 2 番目に大きい |
| **確定**（11-10、D29） | td1-rlog | 2024-10〜2025-04 の TD1 の走行一式。td1-raw とは期間が重ならず、**唯一の原本**（11-10 に確かめた）。ほぼ全量が 90 日読まれていない層にあり、残る読み手は Databricks の auto-loader の権限だけ。ただし、少量の読み出しは続いている（2025-10〜2026-04 に 9 回、1 回あたり 2〜12 GB。最後は 2026-04-07） |
| **確定**（11-10、D29） | tuscenes-calibration（旧） | 2024 のキャリブレーションの撮影データ（チェスボードの画像・内部パラメータの撮影・地図の URL 一覧）。新しいバケットには移っておらず、コードからの参照も 2026-04 で途絶えた。休眠。持ち主と、今も要るかが分からない |
| **確定**（11-10、D28） | denso-nx-raw | 2026-10-03 を最後に新しいファイルが来ていない（DataSync の日次の転送は 0 件）。第一弾の調べでは Azure に原本 175.5 TB が残っていたが、10-15〜17 に転送元のファイル数が 0 になった。**Azure にまだあるなら受け取り直せる**、無いなら唯一の原本 |

**td1-raw にも、入れる前に決めることがある。** LiDAR の間引き（意図した大量削除）が途中で止まっていて、残り約 1.3〜1.6 PiB のほとんどが td1-raw にある（2026-10 の見積もり。今も `*/lidar/*.pcd` がある）。消すロール `LidarDeleter` も残っている（最後に使われたのは 2026-09-03）。Object Lock を入れたあとは、消すのにジョブでの解除と 30 日の待ちが要り、その間の保存の費用もかかる。

## 確かめたこと（2026-11-10、ReadOnly）

| バケット | 件数（11-09） | 45 日の件数の増減 | 層ごとの容量（TB） |
|---|---|---|---|
| td1-raw | 386,495,174 | 41 日で増加（1 日 0.3〜10 万件） | FA 708 / IA 165 / AIA 947 / Standard 1.5 |
| tuscenes-raw | 205,524,662 | 変化なし | AIA 913 / ほか 0.8 |
| denso-taxi-video | 19,694,561 | 変化なし | FA 404 / IA 48 |
| denso-taxi-processed | 11,264,019 | 変化なし | FA 0.5 / IA 0.4 / AIA 0.3 |
| td1-rlog | 4,557,929 | 変化なし | AIA 21.0 |
| tuscenes-calibration（旧） | 271,914 | 変化なし | AIA 1.26 |
| denso-nx-raw | 188,139 | 10-02・10-03 だけ増加 | IA 72 / AIA 98 |
| tuscenes-calibration（新） | 360 | 時々数件ずつ増加 | ほぼ 0 |

- FA・IA・AIA は Intelligent-Tiering の高頻度・低頻度（30 日読まれない）・Archive Instant Access（90 日読まれない）の層。
- td1-rlog と td1-raw の期間: td1-rlog は `2024/…`・`control/ad00/2025/01`・`control/ad10/2025/02` など 2024-10〜2025-04。td1-raw は `control/ad00/2025/04` 以降。
- denso-nx-raw の DataSync（`azure-mlops1-dcorp-inbound-daily`、毎日 03:00 JST、有効）は、残っている実行の記録がすべて転送 0 件。
- `LidarDeleter` の信頼は SSO の FullAccess のまま。

## 外した場合の費用の減り方（手順 C）

1 件あたり約 $7/100 万件（Batch Operations・リクエスト・CloudTrail）で、td1-rlog が約 $32、tuscenes-calibration（旧）が約 $2、denso-nx-raw が約 $1。費用の大半は td1-raw（約 $2,700）と tuscenes-raw（約 $1,440）で、要確認の 3 本を外しても総額はほとんど変わらない。外すかは費用ではなく、データの扱いで決める。

## 確かめる相手と問い

| バケット | 問い |
|---|---|
| td1-raw の LiDAR | 間引きを再開するか。するなら、Object Lock を入れる前に終えるか、`lidar/` を保持の対象から外すか。外す場合、ジョブに作らせる一覧はキーの条件で「含む」側にしか絞れないので、一覧の作り方を別に考える。新しく書かれる LiDAR の版にも、既定の保持設定で保持が付く |

## 確定の 3 本の関係者（2026-11-10、コードから）

cdk-apps・mono-e2e・databricks-jobs・product-map の git の履歴（コミットの作者名。GitHub のログイン名のものはそのまま）から調べた。人の役割はコードから推したもので、本人には確かめていない。

### denso-taxi-video・denso-taxi-processed（同じ取り込みの 2 本）

Azure 側の加工ジョブ（taxi-extractor）の出力を、DataSync で、parquet は denso-taxi-processed へ、動画は denso-taxi-video へ振り分けて取り込む（cdk-apps の `apps/denso-taxi`、共通の `packages/azure-data-sync`）。

| 役割 | 人 | 根拠 |
|---|---|---|
| **作った人・取り込みの担当（窓口の第一候補）** | Shintaro Inuzuka さん | 2 本のバケット・DataSync・GENIAC4 の取り込みを作り、止めた（cdk-apps の `apps/denso-taxi` 9 件、2026-07-01〜09-24。[cdk-apps#1486](https://github.com/turingmotors/cdk-apps/pull/1486)・[cdk-apps#1491](https://github.com/turingmotors/cdk-apps/pull/1491)・[cdk-apps#1980](https://github.com/turingmotors/cdk-apps/pull/1980) など）。processed を読む DLT `denso-taxi-sdp`（mono-e2e、9 件）と、video を学習用に変換する `video-training-converter` の taxi 対応（[cdk-apps#1656](https://github.com/turingmotors/cdk-apps/pull/1656)）も書いた |
| 保有データカタログ・S3 Inventory | 安本さん（Masahiro Yasumoto） | 2 本の S3 Inventory を足した（[cdk-apps#1655](https://github.com/turingmotors/cdk-apps/pull/1655)・[cdk-apps#1714](https://github.com/turingmotors/cdk-apps/pull/1714)）。mono-e2e の `data-catalog` の作者。`denso-taxi-sdp` にも 2 件 |
| video の読み手（Feature Cache・dataset-ops） | Takafumi Watanabe さん | dataset-ops に video の読み取りを足した（2026-07-28）。dev の Feature Cache の読み取り（[cdk-apps#2195](https://github.com/turingmotors/cdk-apps/pull/2195)）。本番の Feature Cache の読み取りは Devin が作った（[cdk-apps#2141](https://github.com/turingmotors/cdk-apps/pull/2141)） |
| processed の読み手（taxi の curation） | Ibai Gorordo さん、安本さん | mono-e2e の `curation/` の taxi のジョブ（2026-09〜10） |

- 2 本とも、新しい書き込みは 9 月半ばで止まっている（DataSync の taxi の 4 タスクに、残っている実行の記録が無い。GENIAC4 側の日次の実行は 2026-09-24 に止めた）。受け取りが終わったのかは、Inuzuka さんに確かめる。

### tuscenes-calibration（新）

車両ごとのキャリブレーションの確定版（`calibration_results/<車両>/{camera_parameters,wheel_base_center_parameters,…}/<日付>.json`）を置く。

| 役割 | 人 | 根拠 |
|---|---|---|
| **書き込みの仕組みを作った人（窓口の第一候補）** | `tsuzuki16` | JADD STUDIO の「確定版のリリース」（`POST /wheel-calibration/release`）を作った（mono-e2e の `routers/wheel_calibration.py`、2026-07-27〜08-03。[mono-e2e#3807](https://github.com/turingmotors/mono-e2e/pull/3807)・[mono-e2e#3872](https://github.com/turingmotors/mono-e2e/pull/3872)）。cdk-apps で backend-api の Lambda にこのバケットへの書き込みを許した |
| バケットを CDK に置いた人 | Kazuki Matsuda さん（denso-raw の持ち主だった松田さん〈退職〉と同じ人かは確かめていない。今の書き手と読み手には関わらない） | Datalake のスタックに `tuscenes-calibration-<account>` を足した（2025-04-08、[cdk-apps#169](https://github.com/turingmotors/cdk-apps/pull/169)） |
| 読み手: Databricks への取り込み | `inuex35`・`graph226`・安本さん・`ohnabe` | databricks-jobs の `calibration-parameter-loader`（毎時、Auto Loader で取り込む） |
| 読み手: データセット | Ibai Gorordo さん | mono-e2e の `jaddless_dataset/calibration.py` |
| 読み手: シナリオテスト | — | mono-e2e の `jadd-cli`・`db-models`（既定のバケット）、cdk-apps の `closed-loop-scenario-test` |

- **書き込み元が 1 つ見つかった。** backend-api の Lambda が、JADD STUDIO からの確定版のリリースで書く（11-04〜09 にも書かれている）。11-02 の書き込み元の洗い出しには出ていなかった。boto3 は 1.42（uv.lock）で、`when_required` の設定は見当たらないので、チェックサムは付く見込み。条件付き書き込み（`IfNoneMatch="*"`）を使っている。Object Lock との組み合わせは予行で確かめる。
- `overwrite=true` のリリースは同じキーに上書きする。Object Lock の下では、上書きされた古い版にも保持が付いたまま残る。JSON なので量は問題にならない。
- `backup/`（2026-07-08 の手直しの前の控え）を書いた人は、コードからは分からない。

## 一覧: サイズ・費用・最終参照日（2026-11-10）

| バケット | 区分 | 容量（TB） | 件数 | 保持を付ける費用 | 最終参照日（読み取り） | 最終書き込み |
|---|---|---|---|---|---|---|
| td1-raw | 確定 | 1,821 | 3 億 8,650 万 | 約 $2,710 | 2026-11-10（毎日。GET 1 日 100〜700 万回） | 毎日 |
| tuscenes-raw | 確定 | 914 | 2 億 552 万 | 約 $1,440 | 2026-10-28（約 78 GB） | 2025-04（収集の終わり） |
| denso-taxi-video | 確定（D28） | 452 | 1,969 万 | 約 $140 | 2026-11-02（10-31〜11-02 に約 117 TB） | 2026-09-12 |
| denso-taxi-processed | 確定（D28） | 1.1 | 1,126 万 | 約 $80 | 測れない（※2） | 2026-09-11 |
| td1-rlog | 確定（D29） | 21.1 | 456 万 | 約 $32 | 2026-04-07（約 12 GB） | 2025-09-08 |
| tuscenes-calibration（旧） | 確定（D29） | 1.3 | 27 万 | 約 $2 | 2026-04-01（約 29 GB） | 2026-03-24 |
| denso-nx-raw | 確定（D28） | 171 | 19 万 | 約 $1 | 2026-08-19（約 2 GB） | 2026-10-02 |
| tuscenes-calibration（新） | 確定 | ほぼ 0 | 360 | ほぼ $0 | 測れない（※3） | 2026-11-08 |
| **計** | | **約 3,381** | **約 6.28 億** | **約 $4,410** | | |

- この表は 8 本のとき（D30 の前）のもの。tuscenes-annotation（13.5 TB・約 1,770 万件・約 $124）を足すと、9 本で約 3,394 TB・約 6.46 億件・約 $4,530 になる。

- 費用は、Batch Operations（$1/100 万件）・`PutObjectRetention` のリクエスト（$5/100 万件）・CloudTrail のデータイベント（$1/100 万件）・一覧の生成（$0.015/100 万件）の合計（約 $7/100 万件）。件数は CloudWatch の `NumberOfObjects`（11-09）で、古い版・削除マーカーを含む上限。
- 最終参照日: td1-raw は S3 のリクエストのメトリクス（`GetRequests`）。ほかはリクエストのメトリクスが無いので、Intelligent-Tiering の高頻度層の容量が、件数の増えない日に 1 GB 以上増えた最後の日（読まれたデータは高頻度層に戻る）。直近 15 か月の CloudWatch の日次の値。少ない読み出し（1 GB 未満）は見えない。
- ※2 denso-taxi-processed は小さいファイル（128 KB 未満は層を移らない）が多く、この方法では読み出しが見えない。DLT `denso-taxi-sdp` の読み先。
- ※3 tuscenes-calibration（新）は Intelligent-Tiering ではない（Standard）ので測れない。databricks-jobs の `calibration-parameter-loader` が毎時読む設計。
