# JADD STUDIO の DB が Supabase の外で動くか（関数・権限・PostgREST の使い方）

- 調べた日: 2026-11-12
- 対象: jadd_studio3 の `origin/main`（`3cdfb6fe`、2026-11-12）。`prisma/patch/` の SQL 63 本（DB のパッチ。人が適用する）と、`lib/` の supabase-js の使い方
- 対象の DB: STUDIO 自身の DB（Supabase の jadd-studio）。backend・drivers-app の DB はほかのチームのもので、ここでは見ていない
- 目的: 「Postgres のストアドプロシージャ（JADD STUDIO で使っているものが動くこと）」と「PostgREST」という必須の条件を、AWS の上の Postgres（RDS / Aurora）と自前の PostgREST で満たせるかを確かめる

## 結論

- **関数は、ほぼそのまま RDS / Aurora の Postgres で動く見込み**。Supabase 固有の関数（`auth.uid()`・`auth.jwt()`・`request.jwt.claims`）は 1 つも使っていない。Supabase 固有の拡張（pg_net・vault・pgsodium・pg_cron）も使っていない。
- **要るのは、Supabase が最初から用意しているものを自分で作ることだけ**:
  - ロール `anon`・`authenticated`・`service_role`（権限の付け外しと RLS のポリシーが名前で指している）。PostgREST がつなぐ `authenticator` も要る。
  - スキーマ `extensions` と、その中の拡張 `pgcrypto`（`hmac()`）・`btree_gist`（排他制約）。
- **PostgREST は「サーバーが service_role の固定の鍵で呼ぶ」使い方だけ**。ログインした人の JWT で PostgREST を呼んでいない。そのため、自前の PostgREST に要る JWT は、service_role の鍵 1 つ（HS256 の共有の秘密で署名した長期の JWT）で足りる。利用者ごとの JWT の発行と検証は、STUDIO の今の作りでは要らない。
- 手当てが要るのは、DB の外の 2 点:
  - **Databricks の Lakehouse Federation が、この DB を `supabase_jadd_studio`（dev は `supabase_jadd_studio_dev`）として読んでいる**（パッチのコメントに 14 か所）。AWS に移すなら、Databricks から RDS / Aurora に届く経路が要る。
  - **`NOTIFY pgrst, 'reload schema'` を 33 か所で使う**（PostgREST にスキーマを読み直させる）。自前の PostgREST でも同じ仕組みで動くが、PostgREST と DB の間に RDS Proxy などのプーラーを挟むと `LISTEN` が使えない。

## 関数（ストアドプロシージャ）

- パッチの中で定義する関数は **45 種類**（`CREATE OR REPLACE` で版を重ねたものを 1 つと数える）。言語は plpgsql 58 か所、sql 6 か所。トリガーは 15 本。
- **コードから `.rpc()` で呼ぶ関数 27 本は、すべてパッチの中に定義がある**（コードとパッチを突き合わせた）。Supabase の管理画面で手で作って、パッチに残っていない関数は見つからなかった。
- 主な群:
  - STUDIO 独自のログイン: `studio_session_*`（セッションの作成・検証・更新・取り消し・backend-api のトークンの取得）、`studio_email_mfa_*`（メールの MFA）、`studio_user_set_status`。表はスキーマ `studio_auth` にある。
  - 注釈とレビューの保存: `save_*`（10 本ほど）、`lane_semantic_gt_*`（レーンの GT。版の固定・スナップショット）。
  - 履歴と集計: `record_*_history`、`curation_history_*`、`feature_usage_stats`、`navitime_api_usage_stats`。
- SECURITY DEFINER は 29 か所。`search_path` を `''` か `public` などに固定している（67 か所）。どちらもふつうの Postgres の書き方で、Supabase に依存しない。

## Supabase への依存の一覧（`grep` の件数）

| 項目 | 件数 | AWS で動かすときの扱い |
|---|---|---|
| `auth.uid()` / `auth.jwt()` / `auth.role()` / `request.jwt` | 0 | 不要 |
| ロール `service_role` | 126 | 自分で作る。`GRANT EXECUTE ... TO service_role` 30 か所、表への権限の付与もこのロール |
| ロール `authenticated` / `anon` | 119 / 102 | 自分で作る。ほとんどは `REVOKE ALL ... FROM public, anon, authenticated`（閉じる側）。RLS のポリシー 12 本が `TO authenticated USING (true)` |
| RLS の有効化 | 58 | そのまま動く。STUDIO は service_role（RLS を素通りする）で読み書きするので、ポリシーは実質使われていない |
| `CREATE EXTENSION` | 2 | `pgcrypto`・`btree_gist` を `WITH SCHEMA extensions` で入れる。スキーマ `extensions` を先に作る |
| `NOTIFY pgrst` | 33 | 自前の PostgREST が `LISTEN pgrst` していれば同じく動く |
| pg_net・vault・pgsodium・pg_cron・Storage・Realtime | 0 | 不要（`storage` の 4 件は表の名前の一部） |

注意: `service_role` は Supabase では `BYPASSRLS` を持つ。自分で作るときも同じ属性にしないと、RLS を有効にした表が読めなくなる。

## PostgREST（supabase-js）の使い方

- サーバー（Route Handler など）から、`SUPABASE_JADD_STUDIO_SERVICE_ROLE_KEY` で作ったクライアントを使う（`lib/database/jadd-studio/postgrest/client.ts`）。
- ブラウザ用のクライアント（anon の鍵）は `app/login/LoginCard.tsx` の 1 か所だけで、Google のログイン（Supabase Auth）に使う。DB の読み書きには使っていない。
- 使っている PostgREST の機能は標準のもの: `.from()`・`.rpc()`・`.single()` / `.maybeSingle()`・`count: 'exact'`・`onConflict`（upsert）など。
- supabase-js は `<URL>/rest/v1/` に向けて呼ぶ。自前の PostgREST の前に、このパスを PostgREST に渡す層（ALB のパスの振り分けなど）を置けば、クライアントのコードは URL と鍵を変えるだけで済む見込み。

## 表の定義の正本

- `prisma/models/` に 42 個のモデル（型の生成だけに使う）。パッチの中の `CREATE TABLE` は 56 個。
- パッチは日付順に人が適用する（マイグレーションの道具は使っていない）。新しい DB に一から作るなら、パッチを順に流すか、Supabase から `pg_dump --schema-only` で取るかを選ぶ。パッチだけで今の DB が再現できるかは確かめていない（パッチより前に管理画面で作った表があるかもしれない）。

## 新しいアプリの型に持ち込むこと

- DB を作るときに、Supabase と同じロール（`anon`・`authenticated`・`service_role`・`authenticator`）とスキーマ `extensions` を用意する初期化の SQL を型に入れる。STUDIO の関数をそのまま持ってこられ、Supabase の作法で書いた SQL も動く。
- PostgREST は、サーバーからだけ呼ぶ前提（service_role の鍵）を標準にする。利用者ごとの JWT を PostgREST に渡す作り（RLS を本当に効かせる）は、要るアプリが出たら考える。
