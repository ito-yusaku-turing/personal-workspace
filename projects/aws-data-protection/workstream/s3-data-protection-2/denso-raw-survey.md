# denso-raw は何のバケットか（調査, 2026-11-06）

2026-11-06 の共有ミーティングで出た質問「denso-raw は何のバケットか？」への回答。tuscenes-prod の ReadOnly とマウント済みのリポジトリ（cdk-apps・databricks-jobs・mono-e2e・product-map）で調べた。

## 結論

- **2026-11-10 に、WORM（Object Lock）の対象から外した**（D27）。持ち主が退職して不在で、使われた形跡も無いため。バージョニングと守りのバケットポリシーは残る。
- **2024-12 の 5 日間（12/11・12・13・17・18）に、車両 `dn01` で集めた走行データの原本**。カメラ 7 台（cam0〜2・cam4〜7）、LiDAR、GNSS（Fixposition）、CAN（操舵角・車輪速・ウインカー）が入っている。走行は 63 本で、展開済みのものは 62 本。
- 2024-12-18 に安本さんが Databricks（Unity Catalog の `denso` カタログ）に取り込んだ。2025-01〜02 には JADD Creator の sampling からも読まれた。**2025-05 を最後に、どちらももう使われていない（休眠）**。JADD Creator は 2026-09-30 に削除された。
- **同じ走行の写しはほかに見つからない**。tuscenes-raw の同じ日付には `ad*` の車両しか無い。消えたら取り戻せない、と見てよい（S2 の扱い・WORM の対象に入れたことと合う）。
- これまで資料では「DENSO 納品の raw（7z）」と書いていたが、**DENSO から受け取ったデータかは確かめられていない**。アーカイブの名前は `turing_2024-12-11_15-51-36.7z` で、自社の名前が付いている。DENSO の車両か、DENSO 向けの案件で自社が集めたデータかもしれない。誰が集めて誰に権利があるかは、安本さん（取り込んだ人）か当時の案件の担当に聞く必要がある。

## バケットの中身

| プレフィクス | 中身 | 大きさ | 書かれた時期 |
|---|---|---|---|
| `tmp/<YYMMDD>/jpg/turing_<日時>.7z` | 走行ごとのカメラ画像のアーカイブ（63 本） | 約 2.8 TB | 2024-12-26〜27 |
| `tmp/<YYMMDD>/pcap/turing_<日時>/pcap/lidar.pcap` | 走行ごとの LiDAR の生データ（63 本） | 約 3.5 TB | 同上 |
| `tmp/<YYMMDD>/converted_fixed.7z` | 日ごとに 1 つ（中身は未確認。名前から変換後の補正済みデータか） | 合わせて 0.5 GB | 同上 |
| `v0/dn01-<日時>/{camera,lidar,gnss,can}/` | 上のアーカイブを展開したもの。JPEG（10 Hz）、PCD、CSV。62 走行 | 残りのほぼ全部（約 8.8 TB） | 2025-01-06 前後 |
| `20241217/` | 12/17 の 1 日分の初期の形（`cam*.7z`、`lidar.pcap.gz`、CSV、`.DS_Store`） | 約 72 GB | 2024-12-18 |
| `_policy-check/` | 2026-10-23 のバケットポリシーの確認で使った空のオブジェクト | 0 | 2026-10-23 |

- `.DS_Store` があるので、`20241217/` は Mac から手で上げたものと見られる。
- `tmp/241211/` の 2 つ（`converted_fixed.7z` と `turing_2024-12-11_19-07-32.7z`）だけ、更新日時が 2025-12-23 になっている。上げ直したかコピーしたものと見られるが、CloudTrail が 90 日しか残らないので、誰が何をしたかは分からない。
- 合計 15.2 TB、921 万件（CloudWatch、2026-11-05）。ほぼ全部（15.0 TB）が Intelligent-Tiering の Archive Instant Access 層にある。読まれていないことと合う。

## 設定

- us-west-2。暗号化は SSE-S3（Bucket Key あり）。パブリックアクセスはすべてブロック。タグ・通知・レプリケーション・インベントリは無い。
- ライフサイクルは `tmp/` を Intelligent-Tiering に移す規則 1 本だけ（`v0/` は別の経路で Intelligent-Tiering に入っている）。
- バージョニングは 2026-10-20 に有効化した（第一弾）。バケットポリシーは 2026-10-23 に入れた（ステージ 1 の 1 本目、[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252)）。
- `ListBuckets` の作成日は 2026-10-23 になっているが、これはポリシーを入れた日で、作成日ではない。最も古いオブジェクトは 2024-12-18。Databricks 用のロールも 2024-12-18 07:02 UTC に作られている。バケットはその日に手で作られたと見られる。

## だれが使っていたか

| 使い手 | 経路 | 時期 | 今 |
|---|---|---|---|
| Databricks の DLT pipeline 5 本（`denso-camera-log`・`denso-can-adas`・`denso-gnss-log`・`denso-lidar-pcd`・`denso-scenes`） | Auto Loader で `v0/*/...` を読み、`denso.default` のテーブル（`camera_frames`・`odometry`・`scenes` など 17 個）を作る。コードは databricks-jobs の `denso/`（mats16。2024-12-18〜2025-01-17） | 2024-12-18〜2025-05-13（テーブルの最終更新） | 起動元なし、休眠（product-map の `docs/mlops/databricks-jobs/README.md`） |
| JADD Creator の sampling（auto-labeling） | cdk-apps で読み取りを許可（2025-01-22 の `87e532cc`、2025-02-06 の `c70a44be`「[E2E-902] add denso permission to sampling」） | 2025-01〜 | 2026-09-30 に JADD Creator ごと削除（[cdk-apps#2014](https://github.com/turingmotors/cdk-apps/pull/2014)） |
| Unity Catalog の外部ロケーション | IAM ロール `databricks-s3-ingest-9bf18-db_s3_iam`（2024-12-18 作成。このバケットだけを対象にする） | 最終利用は 2026-10-23（ポリシーを入れた後の確認） | 残っている |

- `denso` カタログの権限（mono-e2e の `projects/databricks-terraform/workspace/grants.tf`）: e2e-team に `WRITE_VOLUME`・`MODIFY` などを付けている。all-employees は `BROWSE` だけ。外部ボリューム `denso.default.raw` を通して、e2e-team 21 名がクラスタ無しで消せる（調査資料の G31）。
- `denso.default` は、`e2e.default` の合流 VIEW には入っていない。今の DENSO のデータ（`denso_nx`・`denso_taxi`）とは別の、古い系統。
- 車両 ID `dn01` は、mono-e2e の trip-viewer-cache のテストに `denso-nx` の例として出てくる。denso-nx の車両と同じ車両かは確かめていない。

## まだ分かっていないこと

1. 集めたのはだれか、データの権利はどこにあるか（DENSO との契約上の扱い）。
2. 2024-12 の 5 日間は何のための走行だったか（PoC・評価など）。
3. `converted_fixed.7z` の中身。2025-12-23 に書き直した 2 つは、だれが何のために書いたか。
4. 今後も持ち続けるか。持つなら、`tmp/` のアーカイブと `v0/` の展開済みのデータの両方が要るか。片方だけにすれば約 6〜9 TB 減らせるが、版の削除は今のポリシーで止めている。

## 調べ方

- AWS（`--profile readonly`）: `list-objects-v2`（最上位と各プレフィクスの一部、`tmp/` は全 132 件）、バケットの設定の読み取り、CloudWatch の `BucketSizeBytes`・`NumberOfObjects`、CloudTrail の `lookup-events`（us-west-2、90 日。管理イベントは 2 件だけ）、IAM の `get-role`・`get-role-policy`、tuscenes-raw の `2.1/2024/12/<日>/` の一覧。
- リポジトリ: cdk-apps の `git log -S denso-raw`、databricks-jobs の `denso/`、mono-e2e の `grants.tf`、product-map の Databricks のスナップショット（2026-09-28）。
