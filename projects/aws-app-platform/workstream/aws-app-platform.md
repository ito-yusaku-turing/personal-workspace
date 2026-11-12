# 社内の Web アプリを AWS に置く標準の型を整える

- 開始: 2026-11-12
- 状態: **起票し、背景と範囲を固めた**（2026-11-12）。次は、Vercel・Supabase の機能ごとに AWS での代わりを洗い出し、cdk-apps の前例（coder など）を調べる
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
| Supabase: Postgres | DB | RDS / Aurora Serverless v2 |
| Supabase: Auth（Google OAuth など） | 利用者のログイン | ALB の OIDC 認証で社の IdP に直接つなぐ / Cognito |
| Supabase: PostgREST（supabase-js） | DB の読み書き | ORM（Prisma など）でサーバーから直接 / 自前で PostgREST を動かす |
| Supabase: RLS とログインした人の JWT | 行ごとの権限 | アプリの層で権限を確かめる / 自前の JWT で RLS を続ける |
| Supabase: Storage | ファイル | S3 + 署名付き URL |
| Supabase: Realtime | 変更の通知 | 要るアプリだけ（AppSync・API Gateway の WebSocket など） |
| Supabase: 管理画面（Studio）・バックアップ | 運用 | RDS の自動バックアップ・スナップショット。DB の閲覧の道具は別に決める |

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

## 進捗チェックリスト

- [x] 起票する（2026-11-12）
- [x] 背景と目的を固める（Supabase も対象。CI で席の問題をなくす。2026-11-12）
- [ ] 使えなくなる機能ごとに、代わり（AWS のサービス・自前）を決める。新しいアプリに要らない機能は落とす
- [ ] 型に求めること（上の観点の優先順位、必須と任意）を決める
- [ ] cdk-apps の前例（coder・github-actions など）を調べる
- [ ] 最初に型を使うアプリ（お試しの題材）を決める
- [ ] 実行環境と認証の方式の候補を比べる
- [ ] 型を作り、お試しのアプリで出す

## 次セッションへの引き継ぎ

- 起票し、背景と目的を固めた（2026-11-12）。範囲は「新しいアプリの標準の型」で、Vercel と Supabase の両方を AWS に置き換える。
- 一番の論点は「Vercel・Supabase でできていた機能が使えなくなる」こと。上の表の機能ごとに、代わりを検討する。表の候補はまだ確かめていない。
- 次は、表の機能のうち新しいアプリに要るものを伊藤と絞り、cdk-apps の前例を読むところから。
- cdk-apps で作業するときは、そのリポジトリの `AGENTS.md` / `CLAUDE.md` に従う。

## 関連リンク

- [databricks-app-hosting/workstream/databricks-app-hosting.md](../../databricks-app-hosting/workstream/databricks-app-hosting.md): 似た案件。とくに [documents/build-and-deploy.md](../../databricks-app-hosting/documents/build-and-deploy.md)（Vercel との比較、GitHub Actions + OIDC）
- [information-resource-inventory/workstream/vercel-accounts.md](../../information-resource-inventory/workstream/vercel-accounts.md): Vercel の席・トークンの問題
- [project:idp-broker](../../idp-broker/README.md): 社内アプリの認証の入口（IdP）の選定
- リポジトリ: `/usr/app/cdk-apps`
