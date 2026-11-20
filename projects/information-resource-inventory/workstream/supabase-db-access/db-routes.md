# Supabase の DB に直接つないでいる経路（リポジトリからの洗い出し）

- 調べた日: 2026-11-20（エージェントが `/usr/app/` 配下を `git grep`・`git log -p` で調べた。DB には接続していない）
- 所属: [../supabase-db-access.md](../supabase-db-access.md)

Postgres のプロトコルで直接つなぐ経路（アプリの実行時・バッチ・CI・マイグレーション・人の手順）を、リポジトリから拾ったもの。HTTPS の API（PostgREST・supabase-js）は対象外。秘密の値は載せない。リポジトリの外（Vercel の環境変数・Databricks の Connection・GitHub secrets の中身）は見ていないので、**本番の接続先とロールの多くは推測**。

## 重要な発見

- **追跡済みのファイルに、drivers-app-dev の DB のパスワードが入っている**。[drivers-app3 の `.env.example`](https://github.com/turingmotors/drivers-app3/blob/main/.env.example) の 9 行目（コメント行）。接続先は `postgres.zlsxpcotdkwjrktfovqd`（drivers-app-dev、`postgres` ロール）、`aws-0-ap-northeast-1.pooler.supabase.com:5432`。
  - 2025-09 から履歴にある。リポジトリは private。
  - 手元の `drivers-app3/.env` と `drivers-app-mono/packages/db/.env` のパスワードと同じ（ハッシュで比べた）。つまり、まだ変えられていない。
  - drivers-app-mono の ADR 0047（`docs/adr/0047-share-dev-database-and-distribute-env-from-aws-secrets.md`）で既知の課題になっていて、未決（u-75）。
  - dev の DB だが、全開発者と drivers-app3 が共有している。リポジトリを読める人（過去に読めた人を含む）は誰でも入れる。
- **backend-prod の DB の資格情報が、少なくとも 3 か所にある**。GitHub secrets（mono-e2e の `BACKEND_PROD_USER` / `BACKEND_PROD_PASSWORD`）、AWS Secrets Manager の `supabase/backend-prod`（Lambda・Batch・EKS・ECS が共有）、開発者の手元の git 管理外のファイル（mono-e2e の `packages/db-models/scripts/db-password.sh` の `DB_PASSWORD_PROD`）。
- **ほとんどの経路が `postgres`（相当）でつないでいる**。専用のロールが確かめられたのは、digital-signage の `assignments_bot` と、Databricks から fleet-ops の DB を読むロールだけ。
- **接続元の IP はほとんど固定でない**（GitHub のホストランナー・Vercel・VPC に入っていない Lambda・NAT の無いパブリックサブネット・Databricks）。

## プロジェクトごとの経路

場所の行番号は 2026-11-20 時点。「推測」と書いたもの以外は、コードか文書に書かれていた。

### backend-prod（`lvngtemehmcxemnurgwb`）

接続先がコードに無く、`supabase/backend-prod` の `DATABASE_URL` や GitHub secrets で渡しているものが多い。backend-prod と推測する根拠は、mono-e2e の `services/offboarding_sync.py:12` が ref を `lvngtemehmcxemnurgwb` と検証していること（dev のアカウントにも同じ名前の secret があり、中身は見ていない）。

| 何が | 場所 | 秘密の置き場所 | 接続元 |
|---|---|---|---|
| CI のマイグレーション（Alembic。main への push と手動） | mono-e2e `.github/workflows/db-models-migration.yaml:29`。`aws-1-us-west-1.pooler.supabase.com:5432`（session） | GitHub secrets `BACKEND_PROD_USER` / `BACKEND_PROD_PASSWORD` | GitHub のホストランナー（IP は固定でない） |
| backend-api の実行時（SQLAlchemy） | mono-e2e `projects/api/backend-api/db.py`、cdk-apps `apps/backend-api/lib/api.ts` | Secrets Manager `supabase/backend-prod` | Lambda（VPC なし） |
| offboarding の定期バッチ | cdk-apps `apps/backend-api/lib/offboarding.ts`、mono-e2e `projects/api/backend-api/jobs/offboarding_sync.py` | 同上 | Lambda（VPC なし） |
| scenario-test の前後処理・aggregator | cdk-apps `apps/scenario-test/lib/scenario-run.ts`、mono-e2e `projects/api/scenario-test/*/db.py` | 同上 | Lambda（VPC なし）、AWS Batch（NAT の有無は未確認） |
| scenario-test の GPU offload | cdk-apps `apps/scenario-test/lib/scenario-test-gpu-offload-stack.ts` | 同上 | Lambda（一部は skypilot の VPC の `PRIVATE_WITH_EGRESS`） |
| closed-loop-scenario-test（prod のアカウントだけ） | cdk-apps `apps/closed-loop-scenario-test/lib/*-stack.ts`、mono-e2e `projects/closed-loop-scenario-test/lambda/aggregate_results/index.py` | 同上 | EKS（パブリックサブネット、`natGateways: 0`）、Lambda |
| modelcore-build | cdk-apps `apps/modelcore-build/lib/modelcore-build-stack.ts`、mono-e2e `projects/modelcore-build/infrastructure/db.py` | 同上 | ECS（パブリックサブネット、NAT なし） |
| train3dgs | cdk-apps `apps/train3dgs/`、mono-e2e `projects/3dgs-metrics-ingest/db.py` | 同上 | Lambda（VPC なし） |
| 手元のマイグレーション | mono-e2e `packages/db-models/alembic/env.py`（`DATABASE_URL` が無ければ Secrets Manager の値を使う） | 環境変数か Secrets Manager | 開発者の手元 |
| 手元の手順（prod のパスワードも持つ） | mono-e2e `packages/db-models/scripts/db-password.sh`（git 管理外） | 開発者の手元のファイル | 開発者の手元 |
| Databricks の Lakehouse Federation | カタログ `supabase_backend_prod`。定義はリポジトリに無い | Databricks の Connection | Databricks |

### backend-dev（`dxnqnvmqkckpcgbrjdkx`）

- 人の手順（開発サーバー・alembic・`backup.sh` の pg_dump）。mono-e2e `packages/db-models/scripts/activate-as-development.sh`、`projects/api/backend-api/README.md`。`aws-1-ap-southeast-1.pooler.supabase.com:5432`（session）、`postgres` ロール。パスワードは手元の `db-password.sh`。

### jadd-studio-dev（`ebdfwtvfpemzevdpxmek`）・jadd-studio-prod（`fdgjfmuvmiwipxsfyecw`、推測）

- アプリの実行時は PostgREST で、直接はつながない（jadd_studio3 `docs/guidelines/database.md:19`）。
- **人の手順**: `prisma/patch/` の DDL を psql か使い捨てのスクリプトで流す（jadd_studio3 `docs/guidelines/database.md` §6・§7。各 `table-spec.md` も同じ）。`docs/workstream/driving-report.md:49` に、本番に流した記録がある。`postgres` ロール。手元の値は Secrets Manager（us-west-2）から `.env.local` を作る（キー `SUPABASE_JADD_STUDIO_DIRECT_URL` / `SUPABASE_JADD_STUDIO_DATABASE_URL`）。
- Databricks の Federation: カタログ `supabase_jadd_studio`・`supabase_jadd_studio_dev`。

### drivers-app-dev（`zlsxpcotdkwjrktfovqd`）・drivers-app-prod（`kuqqkzwvpmhkajpukgkm`、推測）

- drivers-app3 の実行時（Prisma 6）。`prisma/schema.prisma:7`。手元は dev の 5432（session）で、実行時にも session pooler を使っている。本番は Vercel の環境変数と推測（`drivers-app3.vercel.app`）。`postgres` ロール。
- drivers-app3 の人の手順: `db push` / `migrate dev`（`AGENTS.md`）、**本番への psql**（`documents/diary/2026-07-06-suganuma-driver-backfill.md:68`、`documents/diary/2026-07-15-training-project-dcol113-backfill.md:58`）。
- drivers-app-mono の実行時（api / manager / driver、`@prisma/adapter-pg`）。いまは dev だけ。6543（transaction）。`postgres` ロール。Secrets Manager（us-west-2、`developer-local/`）から `.env` を作る。本番は Vercel の予定で、配り方は未決（f-1）。
- drivers-app-mono のマイグレーション・開発の道具（`packages/db/prisma.config.ts`、`docs/architecture/app4-implementation-foundation.md:95-115`、`apps/*/scripts/dev-session.mjs`）。5432。
- Databricks の Federation: カタログ `supabase_drivers_app`。

### biz-fleet-ops（`qgnfaidhxcuqivmgubuy`）

- fleet-ops の実行時（Route Handler で `pg`。トランザクションの中で `authenticated` に切り替える）。`lib/server/database.ts:10`、`docs/runbooks/deployment.md`。transaction pooler（6543）。ロールは「DB の所有者権限」とあるので `postgres` と推測。Vercel の `DATABASE_URL`（Preview / Production）。GitHub Actions には置かない方針。
- fleet-ops のマイグレーション: 本番への適用は Supabase の GitHub 連携（Supabase の側で動く。GitHub に secret は無い）。本番に `db push` しないと明記（`docs/guides/database-changes.md:43`）。
- digital-signage の実行時（`pg`）。`src/lib/db/client.ts`。6543。**専用のロール `assignments_bot`**（`assignments` だけ SELECT、BYPASSRLS）。Vercel の `DB_BIZ_FLEET_OPS`。対話で調べるときは 5432（`docs/supabase.md`）。
- Databricks の Federation: カタログ `supabase_fleet_ops_prod`・`supabase_collect_ops`（推測でこのプロジェクト）。専用の JDBC ログインロールに、NOLOGIN の `data_collection_reader` / `vehicle_registry_reader` を付けている（fleet-ops `docs/runbooks/driving-projects-operations.md:117-119`）。

### 経路が見つからなかったプロジェクト

fleet-management-dev / prod（cdk-apps の `apps/ota` が Edge Function を API で呼ぶだけ）、corp-turing-seat-map、web-ivi-storybook。リポジトリが `/usr/app/` に無いだけの可能性がある。

### 参考: API 経由（対象外）

jadd_studio3・jadd-studio-signage（service_role キーで PostgREST）、cdk-apps の trajectory-visualizer（jadd-studio-prod の REST）、jadd-cli（`SUPABASE_API_KEY`）、mono-e2e の `modelcore_build_upload_turing-default.yaml`（self-hosted のランナー）。

ローカルの DB（`supabase start`、docker の postgres、CI の service container）は対象外。mono-turing-infra には Supabase は出てこない。

## TLS の扱い

- digital-signage: `rejectUnauthorized: false`（証明書を検証しない）
- fleet-ops: `sslmode=require` と `uselibpqcompat`（検証しないと推測）
- drivers-app-mono: Supabase の CA を同梱して検証する

## リポジトリからは分からないこと

- 本番の接続先とロール（Vercel の環境変数、`BACKEND_PROD_USER`、Secrets Manager の中身）。
- Databricks の Connection の host・ポート・ロール（Databricks で `SHOW CONNECTIONS`）。
- `/usr/app/` に無いリポジトリや、手元だけで動かしているスクリプト。
- 実際に接続している経路の全体。各プロジェクトの接続ログ（`log_connections`）で確かめるのが確実。ただし共有の pooler 経由は接続元の IP が残らない。
