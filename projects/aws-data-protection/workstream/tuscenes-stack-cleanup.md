# 古いスタック tuscenes を片付ける

- 開始: 2026-10-27
- 状態: **起票した。まだ着手しない（積んでいる）**。着手するときは「着手の前に確かめること」から
- 所属: project:aws-data-protection
- 経緯: [S3 バケットのデータ保護 第二弾](s3-data-protection-2.md) の TODO 23 の調査で見つかった。tuscenes-raw の EventBridge を有効にすると、このスタックのルールが目を覚ますため。第二弾では、そのルール 1 本だけを伊藤が手で止める（2026-10-27 決定）。スタック全体の片付けは、この資料で別に進める（2026-10-27 伊藤が決定）

tuscenes-prod（767397804933、us-west-2）に、CloudFormation のスタック `tuscenes` が残っている。作ったのは、アーカイブ済みの [turingmotors/tuscenes-pipeline](https://github.com/turingmotors/tuscenes-pipeline)（CDK、Python）。収集は 2025-04 に終わり、主なバケットは cdk-apps に移った。それでも、ルール・Lambda・IAM ユーザー・バケット 5 本などが残っている。これを片付ける。

## 背景・目的

- 動いていない仕組みが、条件がそろえば動き出す形で残っている。tuscenes-raw の `metadata.json` の作成・削除で、cleaning の job・Supabase の書き換え・Slack への投稿が起きる。
- 使われていない IAM ユーザーとロールが、削除の権限を持ったまま残っている（第二弾の原則 1「最大権限は人だけ」、ステージ 4「主体の掃除」に当たる）。
- コードのリポジトリはアーカイブ済みで、誰も deploy しない。第一弾では「コードの見当たらない古いスタック」と書いていた（[raw-data-security.md](done/raw-data-security.md) の tuscenes-basicai-datasets の項）。出所は 2026-10-27 に分かった。

## 沿革（2026-10-27 に調べた）

- 2024-02-02: 前身の [turingmotors/tuscenes-infra](https://github.com/turingmotors/tuscenes-infra)（CDK、TypeScript）が、`alphaspp-raw`・`alphaspp-data` などと Glue の cleaning の job を作った。スタック `alphaspp-pipeline` はもう無いが、バケットは残っている（`alphaspp-raw` 約 0.9 TB・`alphaspp-data` 約 0.4 TB。第一弾の分類では S10）。
- 2024-02-15: tuscenes-pipeline のリポジトリを作った。
- 2024-03-11: スタック `tuscenes` を作った。2024-03-12 に `RawDataBucket`（`{STACK_NAME}-raw-{account}` = `tuscenes-raw-767397804933`）が入った。
- 2024-05-17: tuscenes-raw のいちばん古いデータ（`1.0/2024/05/17/`）。
- 2024-06-26: `NewTripEvent` の Lambda の最後の変更。
- 2025-04-08: [tuscenes-pipeline#27](https://github.com/turingmotors/tuscenes-pipeline/pull/27)（「cdk-apps にリソース移管します」）で、tuscenes-raw と tuscenes-dataset を cdk-apps の datalake に移した（[cdk-apps#169](https://github.com/turingmotors/cdk-apps/pull/169)）。datalake では tuscenes-raw の EventBridge を無効にした（コミットの箇条書きに「cleaning 処理を停止」）。スタックには `from_bucket_name` の参照とルールが残った。
- 2025-04-09: スタックの Lambda の多くが、この日の deploy を最後に更新されていない。
- 2025-05-23: [tuscenes-pipeline#30](https://github.com/turingmotors/tuscenes-pipeline/pull/30)（「tuscenes studio を削除」）。スタックの最後の更新（2025-05-23 06:56 UTC）。その後、リポジトリはアーカイブされた。

## スタックの中身（2026-10-27、ReadOnly）

スタックの状態は `UPDATE_COMPLETE`。削除の保護は無い。出力（Outputs・Export）は無いので、ほかのスタックからの参照（ImportValue）は無い。リソースは 45 個。

### ルール（3 本、すべて ENABLED）

| ルール | 条件 | ターゲット | いまの状態 |
| --- | --- | --- | --- |
| `tuscenes-NewTripEventRule9F52899F-dXQQ5emHVD08` | `tuscenes-raw-*` の `*/*/*/*/*/metadata.json` の `Object Created`・`Object Deleted` | `tuscenes-NewTripEvent-Handler` | **2026-10-27 に伊藤が止めた（DISABLED）**（第二弾の TODO 25）。スタックから見て設定がずれた状態（drift）になっている。止める前も、tuscenes-raw の EventBridge が無効だったので発火していなかった |
| `tuscenes-NewSceneEventRuleF06A1069-KN9bHdkkEJfn` | `tuscenes-cleaned-*` の `*/*/*/*/*/metadata.json` の `Object Created` | `tuscenes-NewSceneEvent-Handler` | tuscenes-cleaned の EventBridge は有効だが、バケットが空（0 件）なので発火しない |
| `tuscenes-CleaningJobStateChangeRule33E79DCB-oqMoaQSfHQKB` | SageMaker の Processing Job の状態の変化で、タグ `type=tuscenes-cleaning` のもの | `tuscenes-CleaningJob-EventHandler` | cleaning の job が起動されない限り発火しない |

### Lambda（7 本。直近 90 日の呼び出しはすべて 0 件）

| 関数 | 役割 | 最終更新 | ロールの最終利用 |
| --- | --- | --- | --- |
| `tuscenes-NewTripEvent-Handler` | trip の作成で、Slack（SNS → Chatbot）に投稿、Supabase の `vehicle`・`trip` に upsert、cleaning の job と検証を起動する。削除で、Slack に投稿、Supabase の `trip` から消す（削除の側は未定義の変数を使っていて、途中で失敗するとみられる） | 2025-04-09 | 2025-04-08 |
| `tuscenes-CleaningJob-Function` | cleaning の job（SageMaker Processing。出力は tuscenes-cleaned）を作る | 2025-04-09 | 2025-04-08 |
| `tuscenes-CleaningJob-EventHandler` | cleaning の job の状態の変化を受ける | 2025-04-09 | 2025-04-08 |
| `tuscenes-TripValidation-Function` | trip の検証（コンテナイメージ。ECR の `tuscenes-validator`、スタックの外） | 2025-03-18 | 2025-04-08 |
| `tuscenes-NewSceneEvent-Handler` | tuscenes-cleaned の scene の作成を受ける | 2025-04-09 | 2025-04-08 |
| `tuscenes-IssueRegister-Function` | 不明（中身は読んでいない）。リソースポリシーで、**td1-raw の S3 からの起動を許している**。いまの td1-raw の通知には、この Lambda への設定は無い | 2025-04-09 | 2024-07-03 |
| `tuscenes-BucketNotificationsHandler…` | CDK の通知の設定のハンドラー（下の「注意」） | 2025-04-09 | 2025-04-09 |

ロールは 8 本（上の 7 本の実行ロールと、cleaning の job の `tuscenes-CleaningJobRole…`）。最終利用はどれも 2025-04-09 以前。

### IAM ユーザー

- `tuscenes-basicai-user`（2024-03-11 作成）。アクセスキーは 1 本で **Inactive**（2024-03-11 作成、最終利用 2024-09-22、s3）。コンソールのログインは無く、MFA も無い。
- インラインポリシーで、tuscenes-basicai-datasets・tuscenes-basicai-results に、読み書きと `s3:DeleteObject*` を許している。外部の BasicAI（アノテーションの委託先）向けとみられる。

### SNS

- `tuscenes-TopicBFC7AF6E-zRkyCVGXCdFs`。購読は AWS Chatbot（https）だけ。Chatbot がどの Slack のチャンネルにつながっているかは確かめていない。

### S3 バケット（5 本。どれも `DeletionPolicy: Retain`）

| バケット | オブジェクト | 大きさ | バージョニング | 通知 | 備考 |
| --- | --- | --- | --- | --- | --- |
| tuscenes-basicai-datasets | 約 116 万 | 約 2.1 TB | なし | なし | 第一弾の分類は S4（外注の成果物）。中身と経緯が分からないため、第一弾・第二弾の手当てから外した。唯一の読み手（cdk-apps の DataFormatter）は 2025-11-19 に消えた |
| tuscenes-basicai-results | 0 | 0 | なし | なし | |
| tuscenes-cleaned | 0 | 0 | なし | EventBridge だけ（このスタックが `Managed: true` で持つ） | cdk-apps の `apps/databricks/lib/auto-loader.ts` が、Databricks の Auto Loader の通知の設定の対象に入れている |
| tuscenes-ingest | 2 | 約 6 GB | なし | なし | |
| tuscenes-testdata | 39 | 約 6 GB | 有効 | なし | **今も使われている**。cdk-apps の `apps/github-actions/lib/github-actions-stack.ts` と `apps/organization-policy/lib/permission-sets.ts`（`qinertia-runner/*`）が参照している |

### スタックの外にあって、関係するもの（消さない・別に判断する）

- tuscenes-raw・tuscenes-dataset: datalake（cdk-apps）に移った。スタックからは `from_bucket_name` で参照しているだけ。
- Secrets Manager の `supabase`: Lambda が `SUPABASE_SECRET_ARN` で参照しているが、スタックの外。最終アクセスは 2026-05-28、最終変更は 2026-09-30 なので、ほかの誰かが使っているとみられる。**消さない。**
- ECR の `tuscenes-validator`（検証の Lambda のイメージ）。
- **tuscenes-tmp の S3 の通知（2026-10-28 に棚卸しで分かった）**: `2.1/` の下の `.json`・`.csv` の作成（`s3:ObjectCreated:*`、Id `1`・`2`）で、このスタックの `tuscenes-CleaningJob-Function` を起動する。どのスタックも持っていない（バケットは cdk-apps の Datalake が持つが、通知は持たない）。手で付けたか、昔のスタックの名残とみられる。Lambda の呼び出しは直近 90 日で 0 回なので、今は誰もそこに書いていない。ただし tuscenes-tmp は Databricks から今も読まれている（外部ロケーションのロールの最終利用 2026-10-27）ので、**`2.1/` に書けば cleaning の job（SageMaker）が動く状態**にある。出典: [AWS リソースの棚卸し](../../information-resource-inventory/workstream/aws-resource-inventory/cleanup-candidates.md) の C1-1。
- スタック `tuscenes-cicd`（ロール `tuscenes-cicd-GithubActionsRole…`）: `tuscenes-*`・`alphaspp-*` の GitHub Actions 用。最後の利用は 2026-03-27 の [turingmotors/tuscenes-processor](https://github.com/turingmotors/tuscenes-processor) の CI（main への push。ECR への push とシークレットの読み取り）で、このリポジトリもアーカイブ済み。このスタックとは別に片付けられる。出典は同じく棚卸しの S10。
- 前身のバケット `alphaspp-raw`・`alphaspp-data`（スタック `alphaspp-pipeline` は削除済み）。
- AWS Chatbot の設定（SNS の購読先）。

## 注意（片付け方に効くこと）

- **スタックを消すと、tuscenes-cleaned の通知の設定が空になる。** `CleanedDataBucketNotifications3738AD3D`（`Custom::S3BucketNotifications`、`Managed: true`）の Delete で、CDK のハンドラーが通知の設定を `{}` に置き換える（[s3-data-protection-2.md](s3-data-protection-2.md) の TODO 23 の調査を参照）。いまは EventBridge だけで、バケットも空なので実害は小さい。ただし、消す前に Databricks の Auto Loader の通知（`databricks-auto-ingest-*`）が付いていないことを確かめる。
- **バケット 5 本は、スタックを消しても残る**（`Retain`）。スタックの外に出るだけで、中身もポリシーも残る。tuscenes-testdata は今も使われているので、残すのが前提。ほかの 4 本は、中身を見てから別に決める。
- **tuscenes-basicai-datasets は原本の候補（S4）。** 第一弾で「中身と経緯が分からない」として外したもの。片付けの中で、持ち主・中身・残すかを決める。
- **スタックの削除で消えるのは、ルール 3 本・Lambda 7 本・ロール 8 本・IAM ユーザー 1 本・SNS のトピック**など（バケット以外）。IAM ユーザーとロールが消えると、第一弾の洗い出し（[principals-2026-10-20.md](done/s3-bucket-access-control/principals-2026-10-20.md)）の主体も減る。
- **tuscenes-tmp の通知を先に外す。** スタックを消すと `tuscenes-CleaningJob-Function` が消え、tuscenes-tmp の通知は消えた関数を指したまま残る（宛先の消えた配線）。そうなると、あとで誰かがこのバケットの通知の設定を書き換えるとき、宛先の検証で失敗しうる。Id `1`・`2` の 2 本だけを外す（`put-bucket-notification-configuration` は丸ごと置き換えなので、ほかの設定が無いことを確かめてから）。
- ルール `NewTripEventRule` は、第二弾で手で止めた後、スタックから見て設定がずれた状態（drift）になっている。スタックを消すときは問題にならない。

## 設計判断と理由

- 片付けは第二弾から切り離す（2026-10-27 伊藤が決定）。第二弾に必要なのは、ルール 1 本を止めることだけで、それは第二弾の中で伊藤が手で行う。

## 進捗チェックリスト

- [ ] 着手の前に確かめること
  - [ ] 持ち主への確認（tuscenes-pipeline を移した松田さん、cleaning の job を触っていた安本さんが候補）。止める・消すことに異論がないか
  - [ ] tuscenes-basicai-datasets の中身と持ち主。残すか（原本として守るか）
  - [ ] tuscenes-ingest・tuscenes-basicai-results・tuscenes-cleaned を残すか
  - [ ] `tuscenes-IssueRegister-Function` の中身と、td1-raw からの起動の許可の経緯
  - [ ] AWS Chatbot のつなぎ先（Slack のチャンネル）
  - [ ] tuscenes-cleaned に Databricks の通知が付いていないこと
  - [ ] tuscenes-tmp の通知（`2.1/` → `tuscenes-CleaningJob-Function`）の出どころ。外してよいか
- [ ] 片付けの手順書を書く（スタックの削除。バケットは残る。削除の前後の確認と、戻せないことの明記）
- [ ] 伊藤が実行する（Full 権限）
- [ ] 残ったバケットの扱い（cdk-apps で持つか、消すか）を決める

## 次セッションへの引き継ぎ

- 2026-10-28: AWS リソースの棚卸しで、tuscenes-tmp の通知が `tuscenes-CleaningJob-Function` を起動する形で残っていると分かった（「スタックの外にあって、関係するもの」と「注意」に追記）。
- 起票しただけで、何も変えていない。調べた数字は 2026-10-27 時点。着手するときは、数字（呼び出し数・最終利用・オブジェクト数）を取り直す。
- 調べるのは ReadOnly（`--profile readonly`）で。書き込みは伊藤が Full 権限で行う。

## 関連リンク

- [S3 バケットのデータ保護 第二弾](s3-data-protection-2.md)（TODO 23・tuscenes-raw の沿革・(b) の決定）
- [turingmotors/tuscenes-pipeline](https://github.com/turingmotors/tuscenes-pipeline)（アーカイブ済み。`tuscenes_pipeline/main.py`・`new_trip_event.py`・`functions/new_trip_event_handler/index.py`）
- [turingmotors/tuscenes-infra](https://github.com/turingmotors/tuscenes-infra)（アーカイブ済み。前身）
- [走行データ消失リスクへの対応](done/raw-data-security.md)（バケットの種別。tuscenes-basicai-datasets・alphaspp-*）
