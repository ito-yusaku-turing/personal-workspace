# 社内の Web アプリを AWS に置く標準の型を整える

- 開始: 2026-11-12
- 状態: **型に求める機能を決めた（必須・できれば欲しい）**（2026-11-12）。次は、JADD STUDIO の関数（RPC）が Supabase の外で動くかを調べ、cdk-apps の前例（coder など）を読む
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

| 区分 | 機能 | 見立て（未検証） |
|---|---|---|
| **必須** | GitHub で main にマージしたら自動でデプロイされる | GitHub Actions + OIDC で IAM ロールを引き受け、CDK か ECS のデプロイを流す |
| **必須** | PostgREST | AWS には同じものが無い。PostgREST（OSS）を自前で動かす（ECS Fargate など）。利用者の JWT をどう作り、PostgREST にどう検証させるかが論点 |
| **必須** | Postgres のストアドプロシージャ（JADD STUDIO で使っているものが動くこと） | RDS / Aurora の Postgres で関数は動く。Supabase 固有のもの（`auth.uid()`・`anon` / `authenticated` / `service_role` のロール・拡張）に頼っているものは手当てが要る |
| 必須（標準で付いてくる） | DB の定期バックアップを 7 日分 | RDS / Aurora の自動バックアップ（保持の日数を 7 日にする）。CDK の既定は 1 日なので、型で 7 日を指定する |
| できれば欲しい | PR ごとのプレビュー | PR ごとに一時的な環境を立て、閉じたら消す。費用と後始末の作りが論点 |
| できれば欲しい | Supabase のブランチ機能 | Aurora の複製（clone。書き込むまでデータを共有する）で DB を分け、マイグレーションを流す形が候補。プレビューと組み合わせる |
| できれば欲しい | Point-in-time recovery（時点への復元） | RDS / Aurora では、自動バックアップの保持の期間の中なら、任意の時点に復元できる（新しい DB として作られる）。7 日のバックアップと一緒に付いてくる見込み |

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
| Supabase: PostgREST（supabase-js） | DB の読み書き | **自前で PostgREST を動かす（必須）** |
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
- **型に求める機能を、必須・できれば欲しいに分けた**（2026-11-12、伊藤。上の「型に求める機能」）。必須は main へのマージでの自動デプロイ・PostgREST・JADD STUDIO のストアドプロシージャが動くこと・7 日分のバックアップ。できれば欲しいのは PR ごとのプレビュー・ブランチ・時点への復元。

## 進捗チェックリスト

- [x] 起票する（2026-11-12）
- [x] 背景と目的を固める（Supabase も対象。CI で席の問題をなくす。2026-11-12）
- [x] 型に求める機能を、必須・できれば欲しいに分ける（2026-11-12）
- [ ] JADD STUDIO のストアドプロシージャ（RPC 25 本ほど）を洗い出し、Supabase 固有のものへの依存を調べる
- [ ] PostgREST を自前で動かす形（置き場所・利用者の JWT の作り方と検証）を決める
- [ ] RDS か Aurora か（ブランチを Aurora の複製で作るなら Aurora）を決める
- [ ] 使えなくなる機能ごとに、代わり（AWS のサービス・自前）を決める。新しいアプリに要らない機能は落とす
- [ ] 型に求めること（上の観点の優先順位、必須と任意）を決める
- [ ] cdk-apps の前例（coder・github-actions など）を調べる
- [ ] 最初に型を使うアプリ（お試しの題材）を決める
- [ ] 実行環境と認証の方式の候補を比べる
- [ ] 型を作り、お試しのアプリで出す

## 次セッションへの引き継ぎ

- 起票し、背景と目的を固めた（2026-11-12）。範囲は「新しいアプリの標準の型」で、Vercel と Supabase の両方を AWS に置き換える。
- 一番の論点は「Vercel・Supabase でできていた機能が使えなくなる」こと。上の表の機能ごとに、代わりを検討する。表の候補はまだ確かめていない。
- 型に求める機能を決めた（上の「型に求める機能」）。Realtime は入れていない。
- 次は 2 つ。
  1. JADD STUDIO のストアドプロシージャを洗い出し、Supabase 固有のもの（`auth.uid()`・Supabase のロール・拡張）への依存を調べる。jadd_studio3 の `origin/main` で見る（手元の作業ツリーは別のブランチのことがある）。
  2. PostgREST を自前で動かす形を考える。いちばんの論点は、利用者の JWT をだれが発行し、PostgREST がどう検証するか（ALB の OIDC 認証が付ける JWT をそのまま使えるか、アプリが署名し直すか）。
- cdk-apps の前例（coder など）も読む。
- cdk-apps で作業するときは、そのリポジトリの `AGENTS.md` / `CLAUDE.md` に従う。

## 関連リンク

- [databricks-app-hosting/workstream/databricks-app-hosting.md](../../databricks-app-hosting/workstream/databricks-app-hosting.md): 似た案件。とくに [documents/build-and-deploy.md](../../databricks-app-hosting/documents/build-and-deploy.md)（Vercel との比較、GitHub Actions + OIDC）
- [information-resource-inventory/workstream/vercel-accounts.md](../../information-resource-inventory/workstream/vercel-accounts.md): Vercel の席・トークンの問題
- [project:idp-broker](../../idp-broker/README.md): 社内アプリの認証の入口（IdP）の選定
- リポジトリ: `/usr/app/cdk-apps`
