# アプリを Databricks に移せるかの検討

- 開始: 2026-11-10
- 状態: **起票した**（2026-11-10。公式ドキュメントで一次調査済み）。次は、社の Databricks の Workspace のリージョン・プラン・単価を確かめ、社外の利用者を入れられるかを CorpIT と詰める
- 所属: project:databricks-app-hosting
- 派生元: [information-resource-inventory/workstream/vercel-accounts.md](../../information-resource-inventory/workstream/vercel-accounts.md)（Vercel の MFA の必須化と、共有アカウント・CI のトークンをなくす作業）

社内の Web アプリを、Vercel（ホスティング）と Supabase（DB・認証）から、Databricks の Databricks Apps（ホスティング）・Lakebase（Postgres）・Databricks の認証（社の IdP の SSO）に移せるかを検討する。

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
- 社外の人は「identity federation with SCIM and JIT provisioning」で入れる（Workspace の全体の権限は渡さずに、アプリだけを使わせられる）。
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

- 公式の料金のページ（[Apps](https://www.databricks.com/product/pricing/databricks-apps)・[Lakebase](https://www.databricks.com/product/pricing/lakebase)）は、取得しても単価が表示されなかった。
- 外部の記事では Apps は Premium で $0.75/DBU とある（[Flexera](https://www.flexera.com/blog/finops/databricks-pricing-guide/)。**未確認**）。この単価だと、Medium 1 台を常に動かして 0.5 × 730 時間 × $0.75 ≒ **月 $270**。Vercel のチーム全体は月 $360（vercel-accounts の試算）。
- 人ごとの課金は無いと思われる（ドキュメントでは確かめていない）。

## 対象のアプリ（2026-11-10 にリポジトリで確認）

| アプリ | いまの構成 | 利用者 | Databricks との関係 |
|---|---|---|---|
| jadd_studio3 | Next.js 16（Node 24.22.1 に固定）・Prisma・Supabase。Vercel の cron（offboarding-sync など） | 社内の人は Google（Supabase Auth）。**Google アカウントを使わない社外の人は、メールとパスワードと TOTP**（STUDIO 独自の認証。`docs/general` の認証の仕様・`docs/workstream/email-user-totp.md`） | `@databricks/sql` で Workspace `dbc-24f125d6-4420` を使っている |
| fleet-ops | Next.js 16.2.1・Supabase（`@supabase/ssr`）。Supabase Auth を 13 ファイル、Storage か Realtime を 4 ファイルで使う（grep の件数） | 未確認 | `@databricks/sql` を使っている |

## 見立て（2026-11-10。まだ決めていない）

良くなること:

- **デプロイのトークンと席の問題が無くなる**。作者ごとの有料の席が無い（推測）。デプロイはサービスプリンシパルで行える（GitHub Actions からの OIDC が使えるかは未確認）。
- **入口で社の IdP の SSO と MFA が必ず効く**。アプリが公開されない。
- 本番の環境変数にある Databricks の秘密を、アプリのサービスプリンシパルに置き換えられる。データの近くでアプリが動く。

壁になりそうなこと:

1. **使う人が全員 Databricks のアカウントユーザーである必要がある**。jadd_studio3 の社外の利用者を入れるには、IdP と ID 連携で Databricks に登録することになる。
2. **Next.js が動くか分からない**（対応の一覧に無い。H2C の要件。Node 22 と 24 の違い。ファイル 1 つ 10 MB まで）。
3. **Supabase の代わりは DB だけ**。Auth・Realtime・Storage は作り直しになる。
4. cron・独自のドメイン・自動の台数の増減にあたるものが無い。cron は Databricks の Jobs で代えられる（推測）。
5. 料金は未確定。Vercel より安くなるとは限らない。

第一候補は、社内の人だけが使うアプリにするのがよさそう（推測）。

## 設計判断と理由

（まだ無い）

## 進捗チェックリスト

- [x] Databricks Apps・Lakebase・認証を公式ドキュメントで調べる（2026-11-10）
- [ ] 社の Databricks の Workspace（`dbc-24f125d6-4420`）のリージョン・プラン（Premium / Enterprise）を確かめる
- [ ] Apps と Lakebase の単価を確かめる（料金のページかアカウントの担当者）
- [ ] 社外の利用者を ID 連携（SCIM と JIT）で入れられるか、CorpIT と詰める
- [ ] fleet-ops などの利用者が社内の人だけかを確かめる
- [ ] Next.js 16 の小さなアプリが Databricks Apps で動くかを試す（H2C・Node 22・ファイルの大きさ）
- [ ] GitHub Actions からのデプロイの認証（OIDC が使えるか）を確かめる
- [ ] Lakebase の拡張（PostGIS・pg_cron など）と、Supabase からの移行の手順を確かめる
- [ ] 進めるかを決める

## 次セッションへの引き継ぎ

**2026-11-10**: 起票した。公式ドキュメントで一次調査を済ませた（上の「公式ドキュメントで分かったこと」）。

- 次は、社の Workspace のリージョン・プラン・単価を確かめる。Lakebase は Workspace と同じリージョンに作られるので、リージョンが東京でなければ、DB の置き場の前提が変わる。
- 料金のページは取得しても単価が出なかった。ブラウザで見るか、アカウントの担当者に聞く。
- 読んでいないページ: Apps の deploy・environment-variables・cicd-github-actions・create-app-template・embed、AppKit（https://developers.databricks.com/docs/appkit/v0/）、Lakebase の料金・拡張・高可用性。

## 関連リンク

- [information-resource-inventory/workstream/vercel-accounts.md](../../information-resource-inventory/workstream/vercel-accounts.md): 派生元。Vercel の席の要件・トークンが漏れたときの影響・席の数と費用の試算
- [information-resource-inventory/workstream/supabase-db-access.md](../../information-resource-inventory/workstream/supabase-db-access.md): Supabase の DB への直接の接続経路
- [project:idp-broker](../../idp-broker/README.md): 社内アプリの認証の入口（IdP）の選定。Databricks の SSO を入口にする場合は関係する
- リポジトリ: `/usr/app/jadd_studio3`・`/usr/app/fleet-ops`
