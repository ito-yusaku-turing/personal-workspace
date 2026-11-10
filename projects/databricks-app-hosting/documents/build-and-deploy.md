# Databricks Apps での構築とデプロイ

- 調べた日: 2026-11-10（Databricks の公式ドキュメントと、社内のリポジトリ）
- 前提: お試しでは、jadd_studio3 をまるごと移さない。**土台を新しく作り、backend-api を使わない機能だけを移す**（2026-11-10、伊藤）。オレゴンのいまの Workspace（`dbc-24f125d6-4420`）に置く。

## 結論

- **Vercel の「main に push したら本番に出る」は、Databricks でも作れる**。やり方は 2 つある。
  1. **Git から直接デプロイ**（2026-04-07 に GA）し、「push で自動デプロイ」をオンにする。いちばん Vercel に近い。ただし、CI のチェックを待たずに出る。
  2. **GitHub Actions から、トークン無し（GitHub の OIDC）でデプロイ**する。**社内ではすでに mono-e2e がこのやり方で、48 本のワークフローを回している**。CI が通ったものだけを出せる。
- **PR ごとのプレビューは無い**。作ることはできるが、アプリが動いている時間だけ課金され（Medium で 1 時間 $0.375〜0.475）、Workspace に 100 個までという上限もある。共有の dev のアプリを 1 つ置くのが現実的。
- **ワンクリックの切り戻しは無い**。前のコミットかタグをデプロイし直す。
- **ログは、計算機が止まると消える**。残すなら、Unity Catalog の表に送る機能（App telemetry、Beta）を使う。
- 勧め: **2（GitHub Actions + OIDC）**。社内の前例と同じ作りなので、仕組みと権限の管理を流用できる。

## Vercel との比較

| | Vercel（いま） | Databricks Apps |
|---|---|---|
| main への push で本番に出る | 標準で付いてくる | Git の自動デプロイ（GitHub のみ）か、GitHub Actions で作る |
| デプロイの前に CI を通す | GitHub Actions を別に組む | Actions で作れば自然にそうなる。Git の自動デプロイは CI を待たない |
| PR ごとのプレビュー（専用の URL） | 標準 | **無い**。共有の dev のアプリで代える |
| デプロイする主体 | コミットの作者（有料の席が要る）か、人に紐づくトークン | **サービスプリンシパル**。席は無い。GitHub の OIDC でトークンを持たない |
| ビルド | Vercel のビルド機（jadd_studio3 は Turbo） | **アプリの計算機の上**（Medium なら 2 vCPU・6 GB）。ビルドの時間とメモリの上限は書かれていない |
| ビルドのログ | UI | UI の Logs タブ（Build）、`databricks apps logs` |
| 動いているときのログ | UI（保持の期間あり） | Logs タブ、アプリの URL の後ろに `/logz`、CLI。**計算機が止まると消える**。App telemetry（Beta）で UC の表（`otel_logs` など）に送れる |
| 切り戻し | 前のデプロイを選ぶだけ | 単独の操作は無い。前のコミットかタグを出し直す。履歴は Deployments タブ・`databricks apps list-deployments` |
| 環境ごとの環境変数 | Production / Preview / Development | bundle の target（dev / prod）ごとに上書きする。秘密は secret scope から `valueFrom` で渡す |
| 出し直しの間の停止 | 無し | 1 台のときは書かれていない。2 台以上なら、古い台が応答し続ける |
| URL | 独自のドメイン | `https://<アプリ>-<workspace-id>.<リージョン>.databricksapps.com` 固定 |

## やり方 1: Git から直接デプロイ（push で自動）

[Deploy](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/deploy) に書かれている。

- ブランチ・タグ・コミットを選んでデプロイする。GitHub・GitLab・Bitbucket などに対応する。Workspace 全体で「Git からしかデプロイさせない」こともできる。
- 「Auto deploy on push events」をオンにすると、push で出る。条件:
  - **GitHub**（Databricks の GitHub App を入れる）か Azure DevOps であること。
  - **private** のリポジトリで、**ブランチ**であること（タグは使えない）。
  - アプリのサービスプリンシパルが、Git の資格情報を持っていること。
- 良い点: CI のワークフローも、Databricks 側の資格情報も要らない。
- 問題:
  - **lint・型チェック・テストが落ちていても出る**。
  - 組織 `turingmotors` に Databricks の GitHub App を入れる必要がある（組織の管理者の判断）。
  - プレビューは無い。

## やり方 2: GitHub Actions + bundle + OIDC（勧め）

公式の手順は [CI/CD with GitHub Actions](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/cicd-github-actions)。アプリは bundle（いまの名前は Declarative Automation Bundles。旧 Databricks Asset Bundles）の `resources.apps` に書く。

```yaml
# .github/workflows/deploy.yml（形を示すための例）
on:
  push:
    branches: [main]
permissions:
  id-token: write
  contents: read
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    env:
      DATABRICKS_AUTH_TYPE: github-oidc
      DATABRICKS_HOST: https://dbc-24f125d6-4420.cloud.databricks.com
      DATABRICKS_CLIENT_ID: <このアプリのデプロイ用のサービスプリンシパル>
    steps:
      - uses: actions/checkout@v4
      - uses: databricks/setup-cli@<版を固定する>
      - run: databricks bundle deploy -t prod --auto-approve
      - run: databricks bundle run <アプリのキー> -t prod   # deploy だけでは再起動しない
```

- `bundle deploy` はコードを上げて設定を変えるだけで、アプリは再起動しない。`bundle run` で起動し直す。公式の例は、最後に `app_status.state` が `RUNNING` になるまで確かめる。
- デプロイする主体には、アプリへの `CAN MANAGE` が要る（新しく作るなら、アプリを作る権限）。
- lint・型チェック・テストのジョブを前に置けば、通ったものだけが出る。

### 社内の前例（mono-e2e）

- 48 本のワークフローが `DATABRICKS_AUTH_TYPE: github-oidc` を使っている。主体は `mono-e2e-ci`（`dbc-24f125d6-4420`）。PR では `-t dev`、main への push では `-t prod` に出すものがある。例: `.github/workflows/cost-monitoring_deploy.yaml`。
- サービスプリンシパルと信頼の設定（federation policy）は、`projects/databricks-terraform/account/service_principals.tf` で Terraform にしてある（INFR-331）。`mono-e2e-ci` だけは手で作った。
- そこに書かれている設計の注意:
  - 信頼の条件（subject）は `repo:turingmotors/<リポジトリ>:environment:production` にする。main に限るのは、GitHub の environment の「デプロイしてよいブランチ」の設定で守る。
  - **PR 用の信頼の設定を同じサービスプリンシパルに足さない**。信頼の設定は「誰がそのサービスプリンシパルになれるか」しか決めない。足すと、PR のブランチのジョブが本番の権限をそのまま使える。PR で dev に出すなら、権限の狭い別のサービスプリンシパルを作る。
  - audiences は既定の account ID ではなく、`https://<workspace>/oidc/v1/token` を明示する。
- 2026-07-15 以降に作った（移した）リポジトリは、subject に数値の ID が入る（`repo:org@123/repo@456:…`）。新しいリポジトリを作るなら、この形になる。

### 用意するもの

1. 新しいリポジトリ（private）。
2. デプロイ用のサービスプリンシパルと、信頼の設定（`environment:production`）。mono-e2e の Terraform に足すのが筋だが、持ち主は infra 側。**アカウントの管理者が要る**。
3. GitHub の environment `production`（main だけがデプロイできる設定）。
4. 本番のアプリへの `CAN MANAGE` を、デプロイ用のサービスプリンシパルに付ける。
5. アプリが使うもの（SQL ウェアハウス・secret・Lakebase）を bundle の `resources` に書く。アプリ自身のサービスプリンシパルに、Unity Catalog の表の権限を付ける。

## プレビューと dev の環境

- PR ごとのプレビューの機能は無い。
- PR ごとに一時的なアプリを作り、閉じたら消すことは、コマンドを組めばできる（`bundle deploy` / `bundle run` / `bundle destroy`）。ただ:
  - 動いている間は 1 時間 $0.375〜0.475（Medium、定価）かかる。
  - Workspace に 100 個までの上限がある。
  - アプリ名は小文字・数字・ハイフンだけ。URL は毎回変わる。
- 現実的なのは次の 2 つ。
  - **共有の dev のアプリを 1 つ置く**。PR のラベルか手動で、そこに出す。権限の狭い別のサービスプリンシパルを使う。
  - **手元で動かす**。`next dev` などを、自分の Databricks の資格情報で Workspace に向ける。`databricks apps run-local` もある。

## 土台をどう作るか

| | Next.js（`next build` / `next start`） | AppKit（Databricks の TypeScript の SDK） |
|---|---|---|
| 中身 | いまの STUDIO と同じ | React + Express 4 + Vite。`databricks apps init` でひな形を作る |
| 成熟度 | Next.js 自体は成熟。**Databricks のドキュメントに Next.js の記述は無い** | `@databricks/appkit` 0.91.2、ドキュメントは「v0」。GA などの表示は無い |
| Databricks との相性 | `@databricks/sql` を自分で使う | SQL のファイルを置くとキャッシュ付きの API になる。ログインした人の権限で走らせる（`.obo.sql`）。Lakebase・Genie のプラグイン |
| STUDIO からの移しやすさ | ページ・Route Handler・MUI をほぼそのまま持ってこられる | ページは React に、API は Express に書き直す |
| デプロイ | どちらも同じ（`npm run build` → `npm run start`） | `databricks apps deploy` が、ビルド・bundle のデプロイ・起動までまとめて行う |

- 勧め: STUDIO の機能を移すのが目的なので、**まず Next.js の最小のアプリで動くかを確かめる**。だめなら AppKit に切り替える。
- どちらでも、ビルドに要るものは `dependencies` に入れる（`devDependencies` は入らない）。1 ファイル 10 MB まで。Node 22。

## 確かめていないこと

- Next.js が Apps で動くか（H2C、ビルドの時間とメモリ）。
- 1 台のとき、出し直しの間にアプリが止まるか。デプロイにかかる時間。
- `--mode SNAPSHOT` と `AUTO_SYNC` の違い（ドキュメントに値はあるが説明が無い）。
- ログの保持の期間（止まると消えるとだけある）。
- 組織 `turingmotors` に Databricks の GitHub App を入れられるか（やり方 1 の場合だけ要る）。
- デプロイ用のサービスプリンシパルを、だれが作れるか（アカウントの管理者）。

## 一次情報

- Databricks: [Deploy](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/deploy)・[CI/CD with GitHub Actions](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/cicd-github-actions)・[apps コマンド](https://docs.databricks.com/aws/en/dev-tools/cli/reference/apps-commands)・[bundle の resources](https://docs.databricks.com/aws/en/dev-tools/bundles/resources)・[デプロイのモード](https://docs.databricks.com/aws/en/dev-tools/bundles/deployment-modes)・[federation policy](https://docs.databricks.com/aws/en/dev-tools/auth/oauth-federation-policy)・[GitHub の OIDC](https://docs.databricks.com/aws/en/dev-tools/auth/provider-github)・[監視とログ](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/monitor)・[App telemetry](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/observability)・[環境変数](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/environment-variables)・[権限](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/permissions)・[依存](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/dependencies)・[2026-04 のリリースノート（Git からのデプロイの GA）](https://docs.databricks.com/aws/en/release-notes/product/2026/april)・[AppKit](https://developers.databricks.com/docs/appkit/v0)
- 社内: mono-e2e の `.github/workflows/cost-monitoring_deploy.yaml`・`projects/databricks-terraform/account/service_principals.tf`
