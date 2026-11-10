# gaming-data-collection は何のバケットか（調査, 2026-11-10）

WORM 化（Object Lock）の対象から外す候補に挙がったので、[denso-raw-survey.md](denso-raw-survey.md) と同じ観点で調べた。tuscenes-prod の ReadOnly と、マウント済みのリポジトリ（gaming-data-collection・cdk-apps・mono-e2e・product-map）で調べた。

## 結論

- **シミュレータ（BeamNG・Forza Horizon・CARLA）で集めた走行動画とメトリクスの原本**。2026-05-25〜07-31 に集めた 11,514 セッション、77,667 件、3.32 TB。gaming-data-collection の案件（自社）で、中継サーバー relay00 から上げていた。
- **収集は終わっている**。案件の終了で、relay00 は 2026-09-01 に撤去された。アップロード用の IAM ユーザー `gaming-data-collection-uploader` は、2026-11-04 に CDK から消された（[cdk-apps#2393](https://github.com/turingmotors/cdk-apps/pull/2393)。IAM にももう無い）。最後の書き込みは 2026-07-31。
- **読まれていない（休眠）**。128 KB 以上のオブジェクトは、すべて Intelligent-Tiering の Archive Instant Access 層にある。この層には 90 日読まれなかったものだけが入るので、動画は書かれてから一度も読まれていないとみられる。Databricks の使い手は、開発用の pipeline 1 本（手動実行。2026-07-01 に作られ、その日以降は更新されていない）だけ。
- **同じデータの写しは見つからない**。relay00 の手元のデータは撤去のときに捨てた。ゲーム PC（game-pc2・game-pc3）は電源が切れたままで、手元に残っているかは確かめられない。Databricks の managed volume `e2e.tuscenes.gaming-data-collection` は作られているが、中身は確かめていない。
- **作り直せるかが、外すかどうかの分かれ目になる**。実車のデータと違い、シミュレータと手順がそろえば、同じ種類のデータは集め直せる。集めるのに 2 か月余りと人手（手動運転）がかかったので、同じセッションをそのまま取り戻すことはできない。tuscenes-model・tuscenes-annotation を外した理由（費用をかければ作り直せる）に当てはまるかは、データの使い道しだい。

## バケットの中身

キーの形は `<prefix>/<sid>/<file>`。1 セッションが 1 プレフィクス（仕様: gaming-data-collection の `docs/schema/s3-conventions.md`）。

| プレフィクス | 中身 | セッション | 件数 | 大きさ | 書かれた時期 |
|---|---|---|---|---|---|
| `beam-ng/` | BeamNG.drive / tech の手動運転。`raw.mp4`・`resized.mp4`・`metrics.csv`・`metadata.json`、一部はマルチカメラ（`raw.cam_*.mp4`）と `events.jsonl` | 4,632 | 26,223 | 0.84 TB | 2026-05-25〜07-14 |
| `forza/` | Forza Horizon。動画と `telemetry.csv`（Data Out）・`input.csv` | 3,498 | 20,988 | 0.85 TB | 2026-06-15〜07-16 |
| `carla/` | CARLA。動画（`video.cam_front_narrow.raw30fps.mp4` ほか）と `boxes.jsonl`・`calibration.json`・`map.json` | 3,384 | 30,456 | 1.63 TB | 2026-07-15〜07-31 |

- 各セッションの最後に、送り終えたしるしの `_complete.json` がある（11,377 件）。
- CARLA を集める仕組みは gaming-data-collection のリポジトリの外にある。relay00 の共通のクライアント（`gdc_relayclient`）で `prefix=carla` として送っていた。
- 古い版・削除マーカーは 0 件（`list-object-versions`）。バージョニングを入れた 2026-10-19 から後に、上書きも削除も無い。
- 大きさ: Archive Instant Access 層が 3.32 TB、STANDARD が 0.2 GB（29,282 件。128 KB 未満の小さいファイルは Intelligent-Tiering に移らない）。
- 2026-06-15 より前の動画は、`video.mp4` という古い名前（195 件）。

## 設定

- us-west-2。CDK の `apps/gaming-data-collection`（`GamingDataCollectionStack`）が持つ。パブリックアクセスはすべてブロックし、HTTPS 以外は拒む。
- バージョニングは 2026-10-19 に有効化した（[cdk-apps#2211](https://github.com/turingmotors/cdk-apps/pull/2211)）。守りのバケットポリシーは 2026-10-26 に入れた（[cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253)）。
- ライフサイクルは、すぐに Intelligent-Tiering へ移すことと、未完了のマルチパートを 7 日で消すことだけ。CDK のコメントでは Archive 層を使わないことになっているが、Archive Instant Access は追加の設定なしに自動で使われる層なので、食い違いではない。
- イベント通知: すべてのキーの作成・削除・失効を SNS `csms-topic-by-path-…` に送る。購読しているのは SQS `csms-queue-…` の 1 本だけ。Databricks の Unity Catalog が、外部の置き場の変更を拾うために作るもの（gaming-data-collection の `_complete.json` をきっかけに下流を動かす、という設計に対応する）。
- インベントリ・レプリケーションは無い。タグは `cost-center: gaming-data-collection`。

## だれが使っていたか・使えるか

| 使い手 | 経路 | 時期 | 今 |
|---|---|---|---|
| relay00（中継サーバー）・ゲーム PC | IAM ユーザー `gaming-data-collection-uploader`（`PutObject`・`AbortMultipartUpload` だけ） | 2026-05-25〜07-31 | relay00 は 2026-09-01 に撤去。キーは同じ日に無効化、ユーザーは 2026-11-04 に削除 |
| Databricks の DLT pipeline `[dev shuhei_tsukamoto] gdc_metadata_loader`（bundle、手動実行） | `metadata.json` と `_complete.json` を読み、`e2e.sandbox` に 3 つのテーブル（`bronze_gdc_metadata`・`bronze_gdc_complete`・`silver_gdc_completed_metadata`）を作る。読むのはメタデータだけで、動画は読まない | テーブルの作成と最後の更新は、どちらも 2026-07-01（product-map の 2026-09-28 のスナップショット） | 起動元なし、休眠 |
| Databricks の Auto Loader のロール | cdk-apps の `apps/databricks/lib/auto-loader.ts` で `ListBucket`・`GetObject` を許している | — | 権限は残っている |
| SSO のグループ `GamingDataCollection`（植田さん 1 名） | 権限セット `GamingDataCollection`。`GetObject`・`PutObject`・`DeleteObject`・`AbortMultipartUpload`・`ListBucket`。wm-data へのアップロードも同じ権限セットに入っている | — | 残っている。ふつうの削除はできるが、古い版の削除はバケットポリシーで止まる |

- managed volume `e2e.tuscenes.gaming-data-collection` は、2026-07-01 に塚本さんが Terraform に足した（[mono-e2e#3195](https://github.com/turingmotors/mono-e2e/pull/3195)「add gaming data collection volume」）。目的は、手で volume を作る権限を配らずに済ませること。中身（このバケットからの写しがあるか）は確かめていない。
- wm-data（World Model のデータ）の最上位のプレフィクスに、ゲームのデータらしいものは無い（`0.x.x/`・`deliveries/` など）。

## WORM の対象から外す場合に考えること

- **費用への影響は小さい**。手順 C の見積もり（約 $4,500）のうち、このバケットの分は 7.8 万件で $1 未満。外す理由は費用ではなく、データの扱いになる。
- **外しても、今の守りは残る**（tuscenes-model・tuscenes-annotation と同じ）。バージョニングと、古い版の削除と守りを外す操作を拒むバケットポリシー（[cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253)）。ふつうの削除・上書きは戻せる。
- **書き込みの止まったバケットなので、WORM 化の手間も小さい**。手順 C の段階 2 に入っている理由（SDK の既定で書く書き手）は、書き手がもういないので当てはまらない。入れるなら段階 1（書き込みの止まったもの）に移せる。
- 外すなら、cdk-apps の `apps/original-bucket-audit/lib/config.ts` の `LOCK_TARGET_BUCKETS`（[cdk-apps#2500](https://github.com/turingmotors/cdk-apps/pull/2500) で足した 10 本）と、その一覧を固定したテストから外す。PR がまだマージ前なので、今なら同じ PR で直せる。

## まだ分かっていないこと

1. **集めたデータを何に使う予定だったか**（学習・評価・研究など）。案件の資料には、収集の仕組みと形式はあるが、使い道は書かれていない。外すかどうかを決める一番の材料。
2. 今後使う予定があるか。使わないなら、持ち続けるか（3.32 TB。Archive Instant Access 層の定価で月 $13 ほど）。
3. Databricks の managed volume `e2e.tuscenes.gaming-data-collection` に写しがあるか。
4. ゲーム PC（game-pc2・game-pc3）に元の録画が残っているか。
5. CARLA の収集の担当と、その手元に写しがあるか。

## 調べ方

- AWS（`--profile readonly`）: `list-object-versions`（全 77,667 件）、`list-objects-v2`（最上位と `carla/` の一部）、`get-bucket-notification-configuration`・`get-bucket-tagging`・`list-bucket-inventory-configurations`、SNS の `list-subscriptions-by-topic`・`get-topic-attributes`、CloudWatch の `BucketSizeBytes`（層ごと）・`NumberOfObjects`、IAM の `get-user`、wm-data の最上位の一覧。
- リポジトリ: gaming-data-collection の `docs/schema/s3-conventions.md`・`docs/workstream/relay00-decommission-2026-09-01.md`・`docs/ledger/machine-ledger.md`・`gdc-s3stats/`、cdk-apps の `apps/gaming-data-collection`・`apps/databricks/lib/auto-loader.ts`・`apps/organization-policy/lib/{permission-sets,groups-cdk}.ts`・`git log`、mono-e2e の `projects/databricks-terraform/workspace/volumes.tf` と PR #3195、product-map の Databricks のスナップショット（2026-09-28）。
