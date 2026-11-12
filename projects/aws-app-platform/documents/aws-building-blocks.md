# 型の部品の下調べ（ホスティング・PostgREST・DB・バックアップ・ブランチ・プレビュー）

- 調べた日: 2026-11-12（AWS・PostgREST・Supabase・Next.js の公式ドキュメント、GitHub のソースとリリース）
- 【確】は公式のドキュメント・ソース・リリースで確かめたこと、【推】は推測や未検証のこと
- 型に求める機能は [workstream](../workstream/aws-app-platform.md) の「型に求める機能」。STUDIO の DB の依存は [jadd-studio3-db-dependencies.md](./jadd-studio3-db-dependencies.md)

## 結論（構成の第一案）

| 層 | 第一案 | 理由 |
|---|---|---|
| アプリ（Next.js） | **ECS Fargate + ALB**（Next.js の standalone 出力） | ALB の OIDC 認証で社の IdP の SSO を入口に必ず効かせられる。CI で作ったイメージを OIDC で出せる。cdk-apps の `coder` も ECS Fargate + ALB + Aurora |
| 利用者の認証 | **ALB の OIDC 認証**（社の IdP に直接つなぐ） | アプリに届く前に SSO が効く。アプリは `x-amzn-oidc-data` を検証して利用者を知る |
| PostgREST | **自前の PostgREST を ECS Fargate で動かす**。service_role の鍵でサーバーからだけ呼ぶ | AWS に同じものは無い。STUDIO はサーバーから service_role で呼ぶだけなので、利用者ごとの JWT は要らない |
| DB | **Aurora PostgreSQL Serverless v2** | 時点への復元が標準で付く。clone で PR ごとの DB（ブランチの代わり）を安く作れる。0 ACU で使っていない間は止まる |
| デプロイ | **GitHub Actions + OIDC**。cdk-apps の `GithubActions-CdkDeployRole`（main からだけ）と `cdk-apps-diff-role`（PR）の作りをなぞる | 席もトークンも要らない。社内に前例がある |
| PR ごとのプレビュー（できれば） | PR ごとに ECS のサービスと Aurora の clone を作り、PR を閉じたら消す | Amplify のプレビューは SSO を前段に置けず、使えない |

採らないもの:

- **App Runner**【確】: 2026-04-30 に新規の顧客の受付を終えた。新機能も足さない。AWS は移行先に ECS Express Mode を勧めている（[告知](https://docs.aws.amazon.com/apprunner/latest/dg/apprunner-availability-change.html)）。
- **Amplify Hosting**【確】: アクセス制限はブランチごとの Basic 認証だけで、社の IdP の SSO を前段に置けない。SSR のアプリは手動デプロイに対応しないので、CI から OIDC で出す形が取れない。ドキュメント上の対応は Next.js 15 まで（[SSR support](https://docs.aws.amazon.com/amplify/latest/userguide/ssr-amplify-support.html)・[Manual deploys](https://docs.aws.amazon.com/amplify/latest/userguide/manual-deploys.html)）。
- **RDS Proxy を PostgREST と DB の間に挟むこと**: 下の「PostgREST」。

## Next.js のホスティング

- **ECS Fargate + ALB**【確】: 複数台で動かすときは、共有の `cacheHandler`（Redis・S3 など）、揃えた `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY`、`deploymentId`、SIGTERM での待ちが要る（[Self-hosting](https://nextjs.org/docs/app/guides/self-hosting)）。1 台なら気にしなくてよい。
- **ECS Express Mode**【確】: 同じネットワークの設定の Express Mode のサービス同士で ALB を共有でき、追加の料金は無い。PR ごとのプレビューの土台の候補（[Express Mode](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-overview.html)）。ALB の OIDC 認証と組めるかは確かめていない。
- **OpenNext + Lambda**【確】: `@opennextjs/aws` 4.1.15（2026-11-03）。対応は Next.js `>=15.5.29 <16 || >=16.4.5`。AWS ではなく SST のコミュニティが保守する。SSO を入口に置くには CloudFront と Lambda@Edge などを自分で組む必要がある【推】。

## 利用者の認証（ALB の OIDC 認証）

- 【確】ALB は利用者の情報を `x-amzn-oidc-data` に入れて渡す。ES256 で署名した JWT だが、公開鍵は JWKS ではなく `https://public-keys.auth.elb.{region}.amazonaws.com/{kid}` から kid ごとに PEM で取る。base64url に詰め物（パディング）が付く。`signer`（ALB の ARN）を必ず確かめる（[ALB の認証](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-authenticate-users.html)）。AWS は検証に `aws-jwt-verify` を案内している。
- 【推】**この JWT を PostgREST にそのまま検証させることはできない**（`Authorization` で来ない・鍵が JWKS で渡せない・パディング・`role` が無い）。利用者の権限で PostgREST を呼びたくなったら、Next.js のサーバーが検証してから自前の鍵で短命の JWT に署名し直す。
- Cognito を挟む場合【確】: JWKS（RS256）を PostgREST に渡せる。ただし鍵が替わるので取り直しが要る。`role` を入れるには Pre token generation の Lambda（access token に入れるには Essentials / Plus の機能プラン）が要る。**新しいアプリの型では Cognito を挟まない**【推】（STUDIO の使い方では要らない）。

## PostgREST

- **版**【確】: 最新の安定版は v16.5（2026-10-18）。保守版の v14.18（2026-09-10）。v15 は無い（偶数の版だけ出す）。v16 は PG13 を切り、`jwt-role-claim-key` の書き方が変わった（[CHANGELOG](https://github.com/PostgREST/postgrest/blob/main/CHANGELOG.md)）。
- **supabase-js との相性**【確】: postgrest-js は PostgREST v12 以降に対応するが、型の機能の判定は `13`・`14` まで。Supabase のセルフホストの compose は v14.18、Supabase CLI のローカルは v16.5。→ **第一案は v14 系**（Supabase のセルフホストと揃う）【推】。
- **JWT の検証**【確】: `jwt-secret` に共有の秘密、JWK、JWKS を入れられる（v13 から kid を照合）。JWKS を URL から自動で取る機能は無い（[postgrest#1130](https://github.com/PostgREST/postgrest/issues/1130)、2018 年から未対応）。STUDIO の使い方（service_role の固定の鍵）なら HS256 の共有の秘密で足りる。秘密は Secrets Manager に置き、`@file` かコンテナの環境変数で渡す。
- **ロールと claims**【確】: `role` クレームでロールを切り替える（無ければ `db-anon-role`）。claims は `request.jwt.claims` に入る（リクエストごと）。
- **Supabase の `auth.uid()`**【確】: `request.jwt.claims` の `sub` を uuid に変換するだけ（[ソース](https://github.com/supabase/auth/blob/master/migrations/20220224000811_update_auth_functions.up.sql)）。STUDIO は使っていない。
- **RDS Proxy とは組まない**【確 + 推】: PostgREST はリクエストごとに `set_config` を呼び、スキーマの読み直しに `LISTEN` を使う。RDS Proxy は PostgreSQL で `SET`・`set_config`・`PREPARE`・`LISTEN` を使うと接続を固定する（[pinning](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy-pinning.html)）。PostgREST は自前の接続のプール（`db-pool`）を持つので、DB に直接つなぐ。RDS Proxy を付けると Aurora Serverless v2 は 0 ACU に止まらなくもなる。
- **AWS の上の事例**: 公式の事例は見つからなかった。公式の Docker のイメージ（GHCR にもある）を ECS Fargate で動かす【推】。

## DB（Aurora PostgreSQL）とバックアップ

- **自動バックアップと時点への復元**【確】
  - Aurora: 保持は 1〜35 日（止められない）。戻せる最新の時点はふつう 5 分以内。復元は新しいクラスターになる（[Aurora のバックアップ](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Managing.Backups.html)）。
  - RDS: 保持は 0〜35 日。既定は API / CLI で 1 日、コンソールで 7 日。ログは 5 分ごとに S3 に上がる（[RDS のバックアップ](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.BackupRetention.html)）。
  - **CDK の既定は 1 日**（aws-cdk-lib v2.276.0。`DatabaseInstance.backupRetention`・`DatabaseCluster.backup`）。**型で 7 日を明示する**。
  - → **「7 日分のバックアップ」と「時点への復元」は、保持を 7 日にするだけで両方満たせる**。
- **AWS Backup の継続バックアップ**【確】: 35 日まで、1 秒の精度で戻せる。ログは別のリージョンやアカウントへ写せない（写せるのはスナップショット）（[PITR](https://docs.aws.amazon.com/aws-backup/latest/devguide/point-in-time-recovery.html)）。型では任意にする。
- **Serverless v2 の 0 ACU**【確】: Aurora PostgreSQL 16.3 以降。使っていない間は止まり、再開に 15 秒ほど。止まっている間はインスタンスの料金が 0。
- **拡張**【確】: Supabase 固有の pg_net・pgsodium・supabase_vault・pg_graphql・pgjwt は RDS / Aurora に無い（[拡張の一覧](https://docs.aws.amazon.com/AmazonRDS/latest/PostgreSQLReleaseNotes/postgresql-extensions.html)）。STUDIO はどれも使っていない。pg_cron は使える（`shared_preload_libraries` に入れて再起動。メタデータは `postgres` の DB）。STUDIO が使う pgcrypto は一覧にある。btree_gist は一覧で確かめていない。

## ブランチ（Supabase のブランチの代わり）

- **Aurora の clone**【確】: copy-on-write で、元と違うページの分だけ課金される。copy-on-write は 15 個まで（16 個目からは丸ごとの写し）。同じリージョンの中だけ。別のアカウントには AWS RAM で共有して作れる。`restore-db-cluster-to-point-in-time --restore-type copy-on-write` でクラスターを作り、インスタンスを別に足す（[Clone](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Managing.Clone.html)）。**作るのにかかる時間は書かれていない**（実測する）。
- 本番のデータを含む clone を PR の環境に渡してよいかは、別に決める【推】（Supabase のブランチは、既定ではデータを写さず、マイグレーションと seed から作る）。
- RDS（Aurora でない）なら、1 台の中に PR ごとの DB を作り、パッチと seed を流すほうが安い【推】。
- Neon: ブランチがほぼ一瞬で作れて、使っていない間は止まる。ただし AWS の外に出る【推】。

## PR ごとのプレビュー

- 【推】一般的な作り方: GitHub Actions の `pull_request`（opened / synchronize）で、PR ごとの CDK のスタック（ECS のサービス、ALB のホスト名の振り分け、Route 53 のワイルドカード、Aurora の clone）を作る。`closed` で `cdk destroy`。取り残しに備えて、タグを付けて定期的に掃除する。
- 【確】Amplify のプレビューは、SSR のアプリでは公開のリポジトリで使えない。上のとおり SSO を前段に置けないので、型では使わない。
- 【推】注意: PR のコードはプレビューの環境の資格情報で動く。cdk-apps の `cdk-apps-diff-role` と同じく、PR から引き受けられるロールは本番に触れないようにする。

## 実測しないと決められないこと

1. RDS Proxy が PostgREST の `set_config`（`is_local=true`）で接続を固定するか。固定しなくても、`LISTEN` があるので直接つなぐ第一案は変えない見込み。
2. Aurora の clone にかかる時間（プレビューの作りやすさが決まる）。
3. ECS Express Mode と ALB の OIDC 認証を組めるか。
4. Next.js 16 の standalone を ECS Fargate で動かし、ALB の OIDC 認証の後ろで `x-amzn-oidc-data` を検証できるか。
