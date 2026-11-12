# 社内の Web アプリを AWS に置く標準の型を整える

- 開始: 2026-11-12
- 状態: **下調べを終え、構成の第一案（ECS Fargate + ALB の OIDC 認証・自前の PostgREST・Aurora Serverless v2・GitHub Actions + OIDC）を出した**（2026-11-12）。次は、第一案を伊藤と確かめ、実測すること（Next.js と ALB の認証・Aurora の clone の時間）を試す
- 所属: project:aws-app-platform
- 似た案件: [databricks-app-hosting/workstream/databricks-app-hosting.md](../../databricks-app-hosting/workstream/databricks-app-hosting.md)（アプリを Databricks に移せるかの検討）

これから作る社内の Web アプリを AWS に置くときの標準の型（CDK のテンプレート・社の IdP の SSO・CI/CD）を作る。**Vercel（ホスティング）と Supabase（DB・認証など）の両方を置き換え、全部の部品を AWS に入れてセキュリティを固める**。対象は新しいアプリ。いまあるアプリ（jadd_studio3・fleet-ops）の移設は後回し（2026-11-12、伊藤）。

## 背景・目的

- Vercel には次の問題がある（[vercel-accounts](../../information-resource-inventory/workstream/vercel-accounts.md) と [databricks-app-hosting](../../databricks-app-hosting/workstream/databricks-app-hosting.md) で分かった）。
  - 人に紐づかないデプロイのトークンが無い。GitHub Actions からの OIDC も無い。
  - Git 連携では、コミットの作者ごとに有料の席（$20/月）が要る。
  - CI のトークンが漏れると、本番の環境変数を介してほかの資格情報まで被害が及ぶ。
- 置き場所の候補として Databricks Apps を調べた（2026-11-10）。入口で SSO が必ず効き、デプロイはサービスプリンシパルと OIDC で行える。ただし、PR ごとのプレビュー・切り戻しの操作・cron・独自のドメインが無い。アプリ 1 つごとに常に課金される。
- 社内のアプリが増えるたびに、置き場所・認証・デプロイを毎回考えずに済むよう、AWS の上に標準の型を用意する。

目的（2026-11-12、伊藤）:

1. **Vercel だけでなく Supabase も統合の対象にする**。ホスティング・DB・認証などの全部の部品を AWS に入れ、権限・秘密・ネットワークを AWS の仕組み（IAM・組織のポリシー・監査）でまとめて固める。
2. **CI を作り、デプロイ用の席の問題を根本からなくす**。デプロイは GitHub Actions から OIDC で IAM ロールを引き受けて行い、人に紐づく席も長期のトークンも要らない形にする。
3. **Vercel と Supabase でできていた機能が使えなくなるのが問題**。機能ごとに、AWS のサービスで代えるか、自前で作るかなどの代わりを検討する。

## 型に求める機能（2026-11-12、伊藤）

見立ては 2026-11-12 の下調べ（[documents/aws-building-blocks.md](../documents/aws-building-blocks.md)・[documents/jadd-studio3-db-dependencies.md](../documents/jadd-studio3-db-dependencies.md)）。

| 区分 | 機能 | 見立て |
|---|---|---|
| **必須** | GitHub で main にマージしたら自動でデプロイされる | GitHub Actions + OIDC。cdk-apps の `GithubActions-CdkDeployRole`（main からだけ）と `cdk-apps-diff-role`（PR）の作りをなぞる |
| **必須** | PostgREST | 自前の PostgREST（第一案は v14 系）を ECS Fargate で動かす。STUDIO はサーバーから service_role の固定の鍵で呼ぶだけなので、利用者ごとの JWT は要らない。RDS Proxy は挟まない（`set_config`・`LISTEN` で接続が固定される） |
| **必須** | Postgres のストアドプロシージャ（JADD STUDIO で使っているものが動くこと） | **ほぼそのまま動く見込み**。Supabase 固有の関数・拡張は使っていない。ロール `anon`・`authenticated`・`service_role`（`BYPASSRLS`）・`authenticator` とスキーマ `extensions` を自分で作れば足りる |
| 必須（標準で付いてくる） | DB の定期バックアップを 7 日分 | Aurora の自動バックアップ。**CDK の既定は 1 日なので、型で 7 日を明示する** |
| できれば欲しい | PR ごとのプレビュー | PR ごとに ECS のサービスと Aurora の clone を作り、閉じたら消す。Amplify は SSO を前段に置けないので使わない |
| できれば欲しい | Supabase のブランチ機能 | Aurora の clone（copy-on-write、15 個まで）。作るのにかかる時間は実測する。本番のデータを PR の環境に渡してよいかは別に決める |
| できれば欲しい | Point-in-time recovery（時点への復元） | **7 日のバックアップと一緒に付いてくる**（Aurora は 5 分以内の時点まで戻せる）。1 秒の精度が要るなら AWS Backup の継続バックアップ |

## 使えなくなる機能と代わりの候補（案。2026-11-12 に洗い出し始めた）

databricks-app-hosting で分かった「Vercel・Supabase で使っている機能」を元にした。候補は未検証。

| もとの機能 | 何に使っているか | 代わりの候補 |
|---|---|---|
| Vercel: main への push で本番に出る | デプロイ | GitHub Actions + OIDC + CDK / ECS のデプロイ |
| Vercel: PR ごとのプレビュー（専用の URL） | レビュー | PR ごとに一時的な環境を立てて閉じたら消す / 共有の dev 環境 |
| Vercel: ワンクリックの切り戻し | 障害対応 | 前のイメージのタグを出し直す（ECS のロールバック・CodeDeploy） |
| Vercel: 環境ごとの環境変数 | 設定 | SSM Parameter Store・Secrets Manager。CDK の環境ごとの設定 |
| Vercel: Cron | 定期実行 | EventBridge Scheduler |
| Vercel: ログ・関数の監視 | 調査 | CloudWatch Logs・アラーム |
| Vercel: CDN・独自のドメイン・証明書 | 配信 | CloudFront・Route 53・ACM |
| Vercel: OIDC で IAM ロールを引き受ける | AWS の呼び出し | タスクロール（そのまま IAM ロールを持てる） |
| Supabase: Postgres | DB | Aurora PostgreSQL Serverless v2（第一案。0 ACU で止まる・clone が作れる） |
| Supabase: Auth（Google OAuth など） | 利用者のログイン | ALB の OIDC 認証で社の IdP に直接つなぐ（第一案）。Cognito は挟まない |
| Supabase: PostgREST（supabase-js） | DB の読み書き | **自前で PostgREST を動かす（必須）**。supabase-js は `<URL>/rest/v1/` に向けて呼ぶので、そのパスを PostgREST に渡す |
| Supabase: RLS とログインした人の JWT | 行ごとの権限 | アプリの層で権限を確かめる / 自前の JWT で RLS を続ける |
| Supabase: Storage | ファイル | S3 + 署名付き URL |
| Supabase: Realtime | 変更の通知 | 求める機能に入れていない（2026-11-12）。要るアプリが出たら考える |
| Supabase: 管理画面（Studio）・バックアップ | 運用 | RDS / Aurora の自動バックアップ（7 日）と時点への復元。DB の閲覧の道具は別に決める |
| Supabase: ブランチ | 開発 | Aurora の複製（できれば欲しい） |

## 検討の観点（案）

databricks-app-hosting の「運用の精査」の観点を、AWS の型に置き換えたもの。

1. **実行環境**: 何の上で動かすか（ECS Fargate + ALB・App Runner・Lambda + CloudFront・Amplify Hosting など）。Next.js を前提にするか。
2. **利用者の認証**: 入口で社の IdP の SSO を必ず効かせる方法（ALB の OIDC 認証・Cognito・IAM Identity Center など）。アプリが受け取る利用者の ID。[project:idp-broker](../../idp-broker/README.md) の結論との関係。
3. **デプロイ**: GitHub Actions + OIDC で IAM ロールを引き受ける（cdk-apps の `apps/github-actions` に前例があるか確かめる）。main → 本番、dev の置き方、PR ごとのプレビューを持つか、切り戻し。
4. **アカウントとネットワーク**: どの AWS アカウントに置くか（アプリごとか共有か）。VPC・独自のドメイン・証明書。
5. **設定と秘密**: Secrets Manager / SSM Parameter Store。アプリに IAM ロールを渡し、長期の鍵を置かない。
6. **DB**: 要るアプリ向けの標準（RDS / Aurora Serverless・DynamoDB）。Supabase を使い続けるか。
7. **監視と障害**: ログ（CloudWatch Logs）、死活の見張りと通知。
8. **費用**: アプリ 1 つあたりの最低の月額。使われないときに止まるか。
9. **型の配り方**: cdk-apps の中の雛形か、Construct のライブラリか、別のリポジトリか。

## 社内の前例（2026-11-12 に cdk-apps の `apps/` をざっと見た。中身は未確認）

| アプリ | 見えたこと |
|---|---|
| `coder` | ECS（`aws-ecs-patterns`）と Lambda。Web の UI を持つ社内向けのサービス。認証のかけ方を確かめる |
| `trajectory-visualizer` | ECS と Lambda |
| `jadd-cli-auth-callback` | Lambda。認証のコールバック |
| `road-coverage-cdn` | S3 + CloudFront（jadd_studio3 の静的データの配信） |
| `github-actions` | GitHub Actions 用の設定と思われる（OIDC の IAM ロールか確かめる） |

## 設計判断と理由

- **対象は新しいアプリの標準の型。いまあるアプリの移設は後回し**（2026-11-12、伊藤）。
- **Vercel と Supabase の両方を置き換え、全部の部品を AWS に入れる**（2026-11-12、伊藤）。権限・秘密・監査を AWS の仕組みでまとめて固めるため。
- **デプロイは CI（GitHub Actions + OIDC）から行い、席とトークンを要らなくする**（2026-11-12、伊藤）。席の問題を、人数分払うのではなく、根本からなくすため。
- **構成の第一案**（2026-11-12、下調べから。伊藤の確認はまだ）: ECS Fargate + ALB の OIDC 認証、自前の PostgREST、Aurora PostgreSQL Serverless v2、GitHub Actions + OIDC。App Runner（2026-04-30 に新規の受付を終えた）と Amplify Hosting（SSO を前段に置けない・CI から OIDC で出せない）は採らない。理由は [documents/aws-building-blocks.md](../documents/aws-building-blocks.md)。
- **型に求める機能を、必須・できれば欲しいに分けた**（2026-11-12、伊藤。上の「型に求める機能」）。必須は main へのマージでの自動デプロイ・PostgREST・JADD STUDIO のストアドプロシージャが動くこと・7 日分のバックアップ。できれば欲しいのは PR ごとのプレビュー・ブランチ・時点への復元。

## 進捗チェックリスト

- [x] 起票する（2026-11-12）
- [x] 背景と目的を固める（Supabase も対象。CI で席の問題をなくす。2026-11-12）
- [x] 型に求める機能を、必須・できれば欲しいに分ける（2026-11-12）
- [x] JADD STUDIO のストアドプロシージャを洗い出し、Supabase 固有のものへの依存を調べる（2026-11-12。[documents/jadd-studio3-db-dependencies.md](../documents/jadd-studio3-db-dependencies.md)）
- [x] 部品（ホスティング・PostgREST・DB・バックアップ・ブランチ・プレビュー）を Web で下調べし、第一案を出す（2026-11-12。[documents/aws-building-blocks.md](../documents/aws-building-blocks.md)）
- [x] cdk-apps の前例を読む（2026-11-12。`coder` は ECS Fargate + ALB + Aurora で、認証は Coder 自身の OIDC。`github-actions` に main からだけの deploy ロールと PR 用の diff ロールがある）
- [ ] 第一案を伊藤と確かめる（PostgREST の版、Aurora にするか）
- [ ] 実測する: Next.js 16 の standalone を ECS Fargate + ALB の OIDC 認証の後ろで動かす / Aurora の clone にかかる時間 / ECS Express Mode と ALB の OIDC 認証を組めるか
- [ ] 型をどの AWS アカウントに置くか、ネットワーク（VPC・ドメイン・証明書）を決める
- [ ] 使えなくなる機能ごとに、代わり（AWS のサービス・自前）を決める。新しいアプリに要らない機能は落とす
- [ ] 型に求めること（上の観点の優先順位、必須と任意）を決める
- [ ] cdk-apps の前例（coder・github-actions など）を調べる
- [ ] 最初に型を使うアプリ（お試しの題材）を決める
- [ ] 実行環境と認証の方式の候補を比べる
- [ ] 型を作り、お試しのアプリで出す

## 次セッションへの引き継ぎ

### 現在地（2026-11-12）

- 範囲: 新しいアプリの標準の型。Vercel と Supabase の両方を AWS に置き換える（伊藤）。
- 型に求める機能を決め（上の表）、下調べを終えた。資料は 2 つ。
  - [documents/jadd-studio3-db-dependencies.md](../documents/jadd-studio3-db-dependencies.md): STUDIO の DB は Supabase の外でもほぼそのまま動く。要るのはロールと `extensions` スキーマを作ることだけ。PostgREST は service_role の固定の鍵でサーバーからだけ呼んでいる。
  - [documents/aws-building-blocks.md](../documents/aws-building-blocks.md): 部品ごとの公式の情報と、構成の第一案。
- 第一案: ECS Fargate + ALB の OIDC 認証、自前の PostgREST（v14 系）、Aurora PostgreSQL Serverless v2（保持 7 日）、GitHub Actions + OIDC。**伊藤の確認はまだ**。

### 次にやること

1. 第一案を伊藤と確かめる。
2. 実測する（[documents/aws-building-blocks.md](../documents/aws-building-blocks.md) の末尾の 4 つ）。どのアカウントで試すか（e2e-dev など）を先に決める。
3. 置き場所のアカウントとネットワークを決める。

### 注意

- STUDIO を移すときの話（後回し）: Databricks の Lakehouse Federation が STUDIO の DB を `supabase_jadd_studio` として読んでいる。AWS に移すなら Databricks から Aurora に届く経路が要る。
- 本番のデータを含む clone を PR の環境に渡してよいかは、別に決める。
- cdk-apps で作業するときは、そのリポジトリの規約に従う（cdk-apps の直下には `AGENTS.md` / `CLAUDE.md` が無い。README が入口）。
- jadd_studio3 は `origin/main` の `3cdfb6fe`（2026-11-12）で調べた。

## 関連リンク

- [databricks-app-hosting/workstream/databricks-app-hosting.md](../../databricks-app-hosting/workstream/databricks-app-hosting.md): 似た案件。とくに [documents/build-and-deploy.md](../../databricks-app-hosting/documents/build-and-deploy.md)（Vercel との比較、GitHub Actions + OIDC）
- [information-resource-inventory/workstream/vercel-accounts.md](../../information-resource-inventory/workstream/vercel-accounts.md): Vercel の席・トークンの問題
- [project:idp-broker](../../idp-broker/README.md): 社内アプリの認証の入口（IdP）の選定
- リポジトリ: `/usr/app/cdk-apps`
