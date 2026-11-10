# アプリを Databricks に移せるかの検討

- 開始: 2026-11-10
- 状態: **お試しの方針（土台を作り直し、backend-api を使わない機能だけ移す）と、構築・デプロイの方法まで調べた**（2026-11-10）。次は、最小版の STUDIO を Databricks Apps に置いたときの運用を精査する（観点は引き継ぎに）
- 所属: project:databricks-app-hosting
- 派生元: [information-resource-inventory/workstream/vercel-accounts.md](../../information-resource-inventory/workstream/vercel-accounts.md)（Vercel の MFA の必須化と、共有アカウント・CI のトークンをなくす作業）

社内の Web アプリを、Vercel（ホスティング）と Supabase（DB・認証）から、Databricks の Databricks Apps（ホスティング）・Lakebase（Postgres）・Databricks の認証（社の IdP の SSO）に移せるかを検討する。**移すアプリは完全に社内専用として作る**（社外の利用者は対象外。2026-11-10、伊藤）。

## 背景・目的

- vercel-accounts の作業で、Vercel には次の問題があると分かった。
  - 人に紐づかないデプロイのトークンが無い。GitHub Actions からの OIDC も無い。
  - Git 連携では、コミットの作者ごとに有料の席（$20/月）が要る。
  - jadd_studio3 の CI のトークンが漏れると、本番の環境変数を介して Supabase・AWS・Databricks の資格情報まで被害が及ぶ。
- そこで「アプリを Databricks に移せないか」という案が出た（2026-11-10）。Databricks はホスティング・DB・認証をまとめて提供している。
- 目的: 移せるか、移すと何が良くなり何が足りないかを確かめ、進めるかを決める。

## 公式ドキュメントで分かったこと（2026-11-10 に確認。ページの更新日は 2026-09〜11）

### Databricks Apps（ホスティング）

- 実行環境は Ubuntu 22.04、**Node.js 22**、Python 3.11。Node の既定の起動は `npm run start`（`app.yaml` の `command` で変えられる）。`DATABRICKS_APP_PORT` を `0.0.0.0` で待ち受ける（[System environment](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/system-env)・[Best practices](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/best-practices)）。
- 対応の一覧にある Node のフレームワークは React・Angular・Svelte・Express。**Next.js は名前が無い**（[概要](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/)）。Node と React の SDK「AppKit」がある（未読）。
- 守ること: HTTP/2 の平文（H2C）に対応する。SIGTERM から 15 秒以内に止まる。アプリのファイルは 1 つ 10 MB まで（[Best practices](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/best-practices)・[App development](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/app-development)）。
- 1 台の大きさ: Medium（2 vCPU・6 GB、既定）0.5 DBU/時、Large（4 vCPU・12 GB）1 DBU/時、XLarge（12 vCPU・48 GB、一部のリージョンだけ）3 DBU/時（[Compute size](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/compute-size)）。
- 台数は 1〜5 台を手で決める。**自動では増減しない**。台数を増やしたアプリは Workspace に 20 個まで（[Horizontal scaling](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/horizontal-scaling)）。アプリは Workspace に 100 個まで（[Resource limits](https://docs.databricks.com/aws/en/resources/limits)）。ディスクは一時的なもの。
- 課金は「動いている時間 × 用意した大きさ」（"billed per hour of compute time while running"）。
- URL は `https://<アプリ名>.aws.databricksapps.com`。**独自のドメインの機能は見当たらない**。リクエストの時間制限・WebSocket・cron の記述は見当たらない。
- 外向きの通信は、制限しなければインターネットに出られる（推測）。通信の制限（network policies）は Enterprise だけ（[Networking](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/networking)）。
- デプロイは GitHub Actions と Bundles で自動化できる（未読）。

### 利用者の認証

- **公開も、匿名でのアクセスもできない**。"You can't make Databricks apps public. Anonymous access and bypassing single sign-on (SSO) are not supported."（[Permissions](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/permissions)）
- 使う人は、社の IdP で認証された **Databricks のアカウントユーザー**であること。権限は `CAN USE` / `CAN MANAGE` で、人・グループ・サービスプリンシパルに付ける。`All account users` に開くこともできる。
- アプリが受け取るヘッダー: `X-Forwarded-Email`・`X-Forwarded-User`・`X-Forwarded-Preferred-Username` など（[HTTP headers](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/http-headers)）。
- アプリごとにサービスプリンシパルが作られる（`DATABRICKS_CLIENT_ID`・`DATABRICKS_CLIENT_SECRET`）。ログインした人の権限で Unity Catalog などを使わせることもできる（user authorization。[Authorization](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/auth)）。

### Lakebase（Postgres）

- 「Lakebase Postgres Autoscaling」。Postgres 16・17・18（既定は 17）。**ap-northeast-1（東京）で使える**。Workspace と同じリージョンに作られ、あとから変えられない（[Manage projects](https://docs.databricks.com/aws/en/oltp/projects/manage-projects)）。
- 1 CU は RAM 2 GB。0.5〜112 CU（自動の伸縮は 64 CU まで）。使っていないときは止められる（60 秒〜7 日。既定は 24 時間）。
- 分岐（ブランチ）、時点への復元（2〜30 日、既定 7 日）、読み取りの複製（ブランチごとに 6 つまで）、RLS。
- DB の認証: Databricks の ID の OAuth のトークン（1 時間で切れる。SSL 必須）か、Postgres のパスワード（新しいプロジェクトでは既定でオフ）（[Authentication](https://docs.databricks.com/aws/en/oltp/projects/authentication)）。
- 接続先はインターネットから届く（例: `ep-example.database.<region>.databricks.com:5432`）。Workspace が Private Link なら、Lakebase にも inbound の Private Link が要る（[Connect](https://docs.databricks.com/aws/en/oltp/projects/connect)）。
- PostgREST 互換の **Data API** がある。認証は JWT ではなく Databricks の OAuth のトークン（[Data API](https://docs.databricks.com/aws/en/oltp/projects/data-api)）。
- Unity Catalog の Delta のテーブルを Lakebase に同期できる（読み取りだけ）。逆向き（Postgres の変更を Delta に出す）は Public Preview。
- **Supabase Auth・Realtime・Storage にあたるものは見当たらない**。拡張（PostGIS・pg_cron など）は未確認。

### 料金

料金体系と見積もりは [documents/pricing-estimate.md](../documents/pricing-estimate.md) にまとめた（2026-11-10）。要点:

- **社の Workspace（`dbc-24f125d6-4420`）は us-west-2（オレゴン）**。データの本体もオレゴン。**オレゴンのいまの Workspace に置く**（2026-11-10、伊藤）。
- Apps は「Interactive Serverless」の単価で、動いている時間 × 大きさで課金される。Medium 1 台・1 時間は、オレゴンの Premium で $0.375、Enterprise で $0.475。
- Lakebase は CU 時間（オレゴンの Premium で $0.092）と、ストレージ（DSU）。2027-01-31 まで 50% 引き。
- いまの負荷（Vercel の請求の使用量と、Supabase の計算機の大きさ）から、Apps は Medium 1 台ずつ、Lakebase は jadd_studio3 が 1 CU・fleet-ops が 0.5 CU と置いた。jadd_studio3 と fleet-ops で、定価で **Premium 月 $655 / Enterprise 月 $822**。
- Vercel に残して全員分の席を払う場合は月 $750〜810。移すと Vercel は月 $375 ほどに下がるが、合計は **Premium 約 $1,030 / Enterprise 約 $1,200** で、**定価では Vercel に残すほうが月 $200〜450 安い**。Apps は使われていなくても 1 台ごとに課金されるため。
- 人ごとの課金は無いと思われる（ドキュメントでは確かめていない）。

## 対象のアプリ（2026-11-10 にリポジトリで確認）

| アプリ | いまの構成 | 利用者 | Databricks との関係 |
|---|---|---|---|
| jadd_studio3 | Next.js 16（Node 24.22.1 に固定）・Prisma・Supabase。Vercel の cron（offboarding-sync など） | 社内の人は Google（Supabase Auth）。ほかにメールとパスワードの経路がある（STUDIO 独自の認証。`docs/general` の認証の仕様）。社内専用にするなら使わなくなる | `@databricks/sql` で Workspace `dbc-24f125d6-4420` を使っている |
| fleet-ops | Next.js 16.2.1・Supabase（`@supabase/ssr`）。Supabase Auth を 13 ファイル、Storage か Realtime を 4 ファイルで使う（grep の件数） | 未確認（社内専用にする前提） | `@databricks/sql` を使っている |

## 見立て（2026-11-10。まだ決めていない）

良くなること:

- **デプロイのトークンと席の問題が無くなる**。作者ごとの有料の席が無い（推測）。デプロイはサービスプリンシパルで行える（GitHub Actions からの OIDC が使えるかは未確認）。
- **入口で社の IdP の SSO と MFA が必ず効く**。アプリが公開されない。
- 本番の環境変数にある Databricks の秘密を、アプリのサービスプリンシパルに置き換えられる。データの近くでアプリが動く。

壁になりそうなこと:

1. **使う人が全員 Databricks のアカウントユーザーである必要がある**。社内専用なので、社の IdP から Databricks に人を登録できていれば足りる（いまの登録の範囲は未確認）。
2. **Next.js が動くか分からない**（対応の一覧に無い。H2C の要件。Node 22 と 24 の違い。ファイル 1 つ 10 MB まで）。
3. **Supabase の代わりは DB だけ**。Auth・Realtime・Storage は作り直しになる。
4. cron・独自のドメイン・自動の台数の増減にあたるものが無い。cron は Databricks の Jobs で代えられる（推測）。
5. アプリごとに課金されるので、移すアプリが多いと Vercel より高くなりうる（[documents/pricing-estimate.md](../documents/pricing-estimate.md)）。
6. 東京のオフィスからオレゴンのアプリまでは遠い（往復で 100 ms 前後と言われる。測っていない）。いまの jadd_studio3 の関数は東京（`hnd1`）で動いているが、DB は東京、データ（Databricks）はオレゴン。

## 設計判断と理由

- **お試しでは jadd_studio3 をまるごと移さない。土台を新しく作り、backend-api を使わない機能だけを移す**（2026-11-10、伊藤）。まるごと移すのは大変で、backend-api を使わない機能を選べば、最大の懸念（backend-api への鍵。[documents/jadd-studio3-feasibility.md](../documents/jadd-studio3-feasibility.md)）が消えるため。

## 進捗チェックリスト

- [x] Databricks Apps・Lakebase・認証を公式ドキュメントで調べる（2026-11-10）
- [x] 社の Workspace のリージョンを確かめる（us-west-2。2026-11-10）
- [x] 料金体系を調べ、定価で試算する（2026-11-10。[documents/pricing-estimate.md](../documents/pricing-estimate.md)）
- [x] jadd_studio3・fleet-ops のいまの負荷と DB の大きさから見積もり直す（2026-11-10）
- [x] 置き場所を決める（オレゴンのいまの Workspace。2026-11-10、伊藤）
- [ ] 社のプラン（Premium / Enterprise）と契約の割引を確かめる（調べ方は [documents/pricing-estimate.md](../documents/pricing-estimate.md) の末尾）。**billing の閲覧権限が無いので後回し**（2026-11-10、伊藤）
- [x] jadd_studio3 を移したときに機能をどこまで保てるかを評価する（2026-11-10。[documents/jadd-studio3-feasibility.md](../documents/jadd-studio3-feasibility.md)）
- [x] お試しの形を決める（土台を作り直し、backend-api を使わない機能だけ移す。2026-11-10、伊藤）
- [x] 構築とデプロイの方法を調べる（2026-11-10。[documents/build-and-deploy.md](../documents/build-and-deploy.md)）
- [ ] 移す機能を選ぶ（backend-api を使わないもの）
- [ ] デプロイのやり方を決める（Git の自動デプロイか、GitHub Actions + OIDC か）。デプロイ用のサービスプリンシパルと信頼の設定を、だれに作ってもらうか決める
- [ ] backend-api の鍵の道（Supabase のログインを残す / STUDIO が JWT を署名 / BFF が Databricks のトークンを受け付ける / サービスキー）を、cdk-apps・backend-api のチームと決める
- [ ] jadd_studio3 の瞬間の山を確かめ、Apps の台数を決める
- [ ] 社の IdP から Databricks に、アプリを使う社内の人が登録されているかを確かめる
- [ ] Next.js 16 の小さなアプリが Databricks Apps で動くかを試す（H2C・Node 22・ファイルの大きさ・ビルドの時間とメモリ）
- [x] GitHub Actions からのデプロイの認証（OIDC が使えるか）を確かめる（2026-11-10。使える。mono-e2e が `github-oidc` で 48 本を回している）
- [x] Lakebase の拡張と、Supabase からの移行の手順を確かめる（2026-11-10。pgcrypto・btree_gist はある。pg_cron は無い。手順は pg_dump / pg_restore）
- [ ] Lakebase で SECURITY DEFINER の関数と、Data API の upsert・`return=representation` が使えるか試す
- [ ] 進めるかを決める

## 次セッションへの引き継ぎ

### 現在地（2026-11-10 のまとめ）

1 日で、起票・料金・機能の見立て・構築とデプロイまで調べた。資料は 3 つ。

- [documents/pricing-estimate.md](../documents/pricing-estimate.md): 料金。オレゴンの定価で jadd_studio3 と fleet-ops を移すと月 $655〜822。Vercel に残して全員分の席を払う（月 $750〜810）より、合計で月 $200〜450 高い。Apps は使われていなくても 1 台ごとに課金されるため。
- [documents/jadd-studio3-feasibility.md](../documents/jadd-studio3-feasibility.md): jadd_studio3 の機能をどこまで保てるか。
- [documents/build-and-deploy.md](../documents/build-and-deploy.md): 構築とデプロイの方法。Vercel との比較。

決めたこと（伊藤）:

- 社内専用で作る。社外の利用者・社外の ID は対象外。
- 置き場所はオレゴン（us-west-2）のいまの Workspace（`dbc-24f125d6-4420`）。データの本体もここにある。
- **お試しでは jadd_studio3 をまるごと移さない。土台を新しく作り、backend-api を使わない機能だけを移す**。
- 社のプラン（Premium / Enterprise）と契約の割引の確認は、billing の閲覧権限が無いので後回し。

分かったことの要点:

- **最大の懸念は backend-api への鍵だった**。STUDIO は、ログインした人の Supabase のトークンを backend-api（BFF）への Bearer にしている。Databricks の SSO にするとこれが手に入らない。backend-api を使わない機能を選べば、この懸念は消える。
- Supabase で使っているのは Auth と PostgREST（supabase-js）だけ。Storage・Realtime は使っていない。backend と drivers-app の DB はほかのチームのものなので、Supabase はまるごとは捨てられない。Lakebase の Data API が supabase-js で動くかは未確認。
- 画面と Databricks のデータを読む機能は、ほぼそのまま動く見込み。Databricks の資格情報は、Apps が注入するアプリのサービスプリンシパルに替えられる。
- main への push での自動デプロイは作れる。勧めは GitHub Actions + OIDC（トークン無し）。mono-e2e が `github-oidc` で 48 本を回していて、サービスプリンシパルと信頼の設定は `mono-e2e/projects/databricks-terraform/account/service_principals.tf` にある（PR 用の信頼の設定を本番のサービスプリンシパルに足さない、という注意つき）。
- Vercel に無かった手間: PR ごとのプレビューが無い。ワンクリックの切り戻しが無い。ビルドはアプリの計算機の上で走る。ログは止まると消える。URL は固定。cron が無い（Jobs で代える）。
- Next.js は Databricks のドキュメントに記述が無い。動かなければ AppKit（React + Express、v0）に切り替える。

### 次回: 最小版の STUDIO を Databricks に置いたときの運用を精査する

「jadd_studio3 の最小版を Databricks Apps にデプロイする」想定で、運用がどうなるかを精査・理解するところから始める（伊藤）。見る観点の案:

1. **最小版の中身**: 移す機能（backend-api を使わないもの）。DB が要るか（Databricks SQL だけで済む機能なら、Supabase も Lakebase も要らない）。ログインした人の扱い（`X-Forwarded-Email` から STUDIO のロールへの対応）。
2. **デプロイの流れ**: リポジトリの置き場所（新しい private のリポジトリか）。main → 本番、dev のアプリの置き方。デプロイ用のサービスプリンシパルと信頼の設定をだれが作り、だれが持つか（アカウントの管理者・infra 側の Terraform）。
3. **権限**: アプリを使える人（`CAN USE` を付けるグループ、社の IdP から Databricks への登録の範囲）。アプリを触れる人（`CAN MANAGE`）。アプリのサービスプリンシパルに付ける Unity Catalog の権限と、ログインした人の権限で読ませるか（user authorization）。
4. **設定と秘密**: secret scope をだれが管理するか。dev と本番の分け方（bundle の target）。
5. **監視と障害**: ログの残し方（App telemetry、Beta）、死活の見張りと通知、切り戻しの手順、出し直しの間に止まるか。
6. **費用の管理**: 常に動かす台数、dev のアプリを止める運用、`system.billing.usage` での見え方（閲覧権限が要る）。
7. **手元の開発**: devbox から Workspace に向けて動かす方法（`databricks apps run-local`、資格情報の持ち方）。
8. **定期実行**: Jobs からアプリの `/api/` を呼ぶ形。

まだ試していないこと: Next.js 16 の最小のアプリが Apps で動くか（H2C・Node 22・ビルドの時間とメモリ・1 ファイル 10 MB）。運用の精査のあとか途中で試す。

### 補足（一次情報と、調べ方）

- 料金の単価は、公式の料金の計算機のデータ（`https://www.databricks.com/en-pricing-assets/data/pricing/AWS.json`）と、料金のページのデータ（`https://www.databricks.com/en-pricing-assets/page-data/product/pricing/<databricks-apps|lakebase|storage>/page-data.json`）から取った。料金のページは JavaScript で描くので、ふつうに取得すると単価が出ない。
- 負荷の一次情報は `~/vercel/turing-inc/2026-11-10/`（Vercel の請求）と `~/supabase/dhazyhuzuwitqasezcvr/2026-11-10/`（Supabase のプロジェクト）。
- jadd_studio3 は `origin/main` の `b034efdd`（2026-11-10）で調べた。手元の作業ツリーは別のブランチにある。

## 関連リンク

- [information-resource-inventory/workstream/vercel-accounts.md](../../information-resource-inventory/workstream/vercel-accounts.md): 派生元。Vercel の席の要件・トークンが漏れたときの影響・席の数と費用の試算
- [information-resource-inventory/workstream/supabase-db-access.md](../../information-resource-inventory/workstream/supabase-db-access.md): Supabase の DB への直接の接続経路
- [project:idp-broker](../../idp-broker/README.md): 社内アプリの認証の入口（IdP）の選定。Databricks の SSO を入口にする場合は関係する
- リポジトリ: `/usr/app/jadd_studio3`・`/usr/app/fleet-ops`
