# Vercel のアカウントの棚卸しと SSO 化の検討

- 開始: 2026-11-05
- 状態: **人のアカウントの 2FA は全員済んだ**（2026-11-09）。未設定は共有アカウントだけ。次は、小さなプロジェクトで作者の検査の挙動を試し、jadd_studio3・fleet-ops を Git 連携に移して共有アカウントを消す
- 所属: project:information-resource-inventory

Vercel のアカウント（組織・チームのメンバーと、その権限）を棚卸しし、社の IdP（Okta / Google Workspace）による SSO に寄せられるかを検討する。

## 背景・目的

- Vercel のアカウントの一覧と権限を把握する。
- 退職者・協力会社のアカウントが残っていないか、Owner など強い権限を誰が持っているかを確かめる。
- 入退社に合わせてアカウントを管理できるよう、SSO 化（あわせて可能ならプロビジョニング）を検討する。

## 現状（2026-11-05 時点）

リポジトリから分かったこと（`/usr/app/` 配下を grep）:

- チームは `turing-inc`（`vercel.com/turing-inc`。cdk-apps の jadd-studio・backend-api・tern-api の README とテストに出てくる）。
- プランは未確認。jadd_studio3 の資料には、cron の挙動から「Pro 以上と判断した」とある。
- `vercel.json` があるリポジトリ: jadd_studio3、jadd-studio-signage、fleet-ops、drivers-app-mono（`apps/drivers-app-manager`）。
- 参照されている `*.vercel.app`: jadd-studio2、studio2、drivers-app3、fleet-ops-sandy、fleet-management-blush、road-curvature-map、jadd-studio-ex。どれも `turing-inc` のチームにあるかは未確認。
- JADD Studio の本番の project ID は `prj_ywCO4lG6pJIo5tdrnGaMz4AxVbAS`（jadd_studio3 の監査ログの workstream）。

伊藤から聞いた内容（2026-11-05）:

- プランは **Pro**。
- Owner は山本さん・海老澤さん・安本さん・伊藤の 4 名。伊藤が Owner なので、2FA の必須化・メンバーの削除・ロールの変更は伊藤ができる。
- メンバーは 20 名弱で、2FA を設定しているのは約半分。

CI で使っている Vercel のトークン（2FA を必須にすると、作った人が 2FA 未設定なら止まる）:

| リポジトリ | ワークフロー | secrets | 用途 |
|---|---|---|---|
| jadd_studio3 | `.github/workflows/deploy.yml` | `VERCEL_TOKEN` | **本番のデプロイ**（main への push で `vercel pull` → `build` → `deploy --prod`） |
| fleet-ops | `.github/workflows/vercel-preview.yml` | `VERCEL_TOKEN`・`VERCEL_ORG_ID`・`VERCEL_PROJECT_ID` | Preview と本番のデプロイ |

誰のトークンかを、git の履歴と GitHub の secrets の作成・更新日時で推定した（2026-11-05。secrets を登録した人は API では分からないので、推定）:

- **jadd_studio3 → 海老澤さん（ほぼ確実）**。`VERCEL_TOKEN` の作成は 2026-04-20 13:16 JST、更新は 14:22 JST。`deploy.yml` を作ったのは海老澤さん（同じ日の 12:26〜14:57 JST に 10 コミット）。伊藤の記憶とも合う。
- **fleet-ops（Environment `vercel-production`）→ 塚本さん（有力）**。`VERCEL_TOKEN` の作成は 2026-09-30 20:21 JST、更新は 21:18 JST。PR [fleet-ops#246](https://github.com/turingmotors/fleet-ops/pull/246)（Devin が作成、依頼は maikosuzuki-5）を 20:23 に merge し、続く [fleet-ops#247](https://github.com/turingmotors/fleet-ops/pull/247)（21:03）・[fleet-ops#248](https://github.com/turingmotors/fleet-ops/pull/248)（21:36）を作ったのが塚本さん。
- fleet-ops の Environment `vercel-preview` にも `VERCEL_TOKEN` がある（2026-11-02 18:36 JST 作成）。同じ頃のコミットは無く、誰かは分からない。runbook には「CI から参照しない」とある。
- 確かめるには、本人に聞くか、GitHub の組織の監査ログ（`secret` の操作。組織の Owner が見られる）を見る。

伊藤がダッシュボードで確かめた（2026-11-05）:

- 海老澤さん（Owner）は **2FA 未設定**（2026-11-06 に設定済み）。塚本さんは設定済み。
- `jaddstudio3-deployment-4700` という **2FA 未設定のユーザー**がいる。名前から、jadd_studio3 のデプロイ用のアカウントと思われる。リポジトリと資料には出てこない。jadd_studio3 の `VERCEL_TOKEN` は作成の約 1 時間後（2026-04-20 14:22 JST）に更新されており、このとき海老澤さん個人のトークンから、このアカウントのトークンに差し替えた可能性がある（推測）。
- **確定（2026-11-05、伊藤が JADD Studio のデプロイログで確かめた）: jadd_studio3 の `VERCEL_TOKEN` は `jaddstudio3-deployment-4700` のトークン**。海老澤さん個人のトークンではない。
- **どちらであっても、いまのままでは 2FA を必須にした時点で JADD Studio の本番のデプロイが止まる**。デプロイ用のアカウントにも 2FA（TOTP）が要る。Integration のトークンは対象外。jadd-studio-signage は GitHub Actions からデプロイしない（Vercel の Git 連携）。

## 公式ドキュメントで分かったこと（2026-11-05 に確認）

ダッシュボードに入るアカウントの話。アプリの利用者の認証とは別。

| 機能 | Pro | Enterprise | 出典 |
|---|---|---|---|
| SAML SSO（Okta・Google に対応。強制もできる） | **add-on で $300/月**（定額。2025-08 から） | 含まれる | [SAML](https://vercel.com/docs/saml)・[Pro plan](https://vercel.com/docs/plans/pro-plan)・[changelog](https://vercel.com/changelog/saml-sso-is-now-available-to-pro-teams) |
| Directory Sync（SCIM。IdP で外すと自動で外れる） | 使えない | 含まれる | [Directory Sync](https://vercel.com/docs/directory-sync) |
| 2FA の必須化（Two-Factor Authentication Enforcement） | 使える（と思われる。プランの明記なし） | 使える | [2FA enforcement](https://vercel.com/docs/two-factor-enforcement) |
| 監査ログ（Audit Logs、90 日） | 使えない（Activity Log はある） | 含まれる | [Audit log](https://vercel.com/docs/audit-log)・[Activity log](https://vercel.com/docs/activity-log) |
| プロジェクト単位のロール・Security・Contributor | 使えない | 含まれる | [Access roles](https://vercel.com/docs/rbac/access-roles) |

料金（Pro）:

- 基本料金 $20/月（有料の席 1 つと、使用量のクレジット $20 を含む）。有料の席は 1 つ増えるごとに $20/月。
- **Viewer（Pro Viewer）の席は無料で、数の制限が無い**。Billing の席は 1 つまで無料。
- Enterprise は個別見積もりで、料金は公開されていない。
- SSO だけが目的なら、Pro に $300/月の add-on を足せば済む。

SSO:

- 設定と強制（Require Team Members to login with SAML）は Owner だけができる。強制すると、SAML でないセッションはチームの情報を見られない。
- SAML だけでは、外すのもロールを変えるのも手作業。IdP で外したら自動で外れるようにするには、Directory Sync（Enterprise）が要る。
- GitHub やメールでログインしている既存のアカウントが、SAML とどう紐づくかは書かれていない（未確認）。

2FA の必須化:

- Settings → Security & Privacy → Two-Factor Authentication Enforcement。設定できるのは、本人の 2FA を有効にしている Owner だけ。すぐに効く。
- 2FA を設定していない人は、チームのダッシュボード・API・トークン・CLI・CI からのデプロイ・PR のビルドが止まる。チームには残るので、席は消費し続ける。
- bot やサービス用のアカウントにも 2FA が要る。Integration のトークンは対象外。
- 認証アプリ（TOTP）と passkey が使える。復旧用のコードもある。
- **2027-01-20 に、Vercel の全ユーザーに認証アプリの登録が必須になる**（2026-11-06 に確かめたドキュメント（2026-08-28 更新）の日付。11-05 には 2026-12-31 と書いていたが、いまの記述は "All Vercel users must set up an authenticator app by January 20, 2027"）（Enterprise は同じ日に 2FA の必須化が強制でオンになる）。

ロール（Pro で使えるのは Owner・Member・Developer・Billing・Pro Viewer）:

- **メンバーの招待・削除・ロールの変更は Owner だけ**。Supabase と違い、Owner でない人は人を外せない。
- Member はプロジェクトとチームの設定のほとんどを扱える。Developer は Production の環境変数を変えられない。Pro Viewer は読み取りだけ。
- 見るだけの人を Pro Viewer に移すと、有料の席が減る（推測）。

棚卸しに使う API:

- `GET /v3/teams/{teamId}/members`: ロール・メール・Git のアカウント・`joinedFrom`（SSO で入ったか）・`createdAt` が返る。**`mfaEnabled`（2FA の有無）も返る**（2026-11-06 に確かめた。当初「返らない」と書いたのは誤り）。最後のログインは返らない。
- `GET /v10/projects`: プロジェクトの一覧。
- トークンはチームや 1 つのプロジェクトに絞れ、有効期限も付けられる。**読み取りだけのスコープは無い**（チームに絞ったトークンでも読み書きできる）。

## 共有アカウントを使わないデプロイの方法（2026-11-05 に調べた）

背景: jadd_studio3 は GitHub Actions + Vercel CLI でデプロイしている。伊藤の認識では、**Vercel のアカウントが無い人にも（main への merge で）デプロイの権利を開くため**。トークンは共有アカウント `jaddstudio3-deployment-4700` のもの。共有アカウントはやめたい。

分かったこと:

- **個人に紐づかないトークンは無い**。トークンは必ずユーザーのもの（範囲は Full Account / Team / Project）。チームが所有するトークンやサービスアカウントの機能は無い（[Access tokens](https://vercel.com/docs/accounts/access-tokens)）。
- **GitHub Actions から OIDC でデプロイする仕組みは、まだ無い**。公式の手順書に "Vercel doesn't currently support OIDC for authenticating the GitHub Actions deployment itself" とある（[kb](https://vercel.com/kb/guide/how-can-i-use-github-actions-with-vercel)）。2026-10-22 のブログで「API と CLI に OIDC を広げる」と予告している（[blog](https://vercel.com/blog/death-to-long-lived-static-credentials)。時期は書いていない）。
- **Pro の Git 連携では、非公開リポジトリのコミットの作者がチームのメンバー（有料の席）でないとデプロイされない**（[Git](https://vercel.com/docs/git#deploying-private-git-repositories)・[Collaboration](https://vercel.com/docs/accounts#collaboration-settings)）。Viewer（無料）ではデプロイできない。
- Vercel はこの席の要件を回避する抜け道を最近ふさいだと書いている（[kb、2026-10-16 更新](https://vercel.com/kb/guide/why-aren-t-commits-triggering-deployments-on-vercel)）。Vercel の社員はコミュニティで「Deploy Hook や CLI で席の要件を回避していた人に影響する」と書いた（[community、2026-05-07](https://community.vercel.com/t/deploy-hooks-now-blocked-if-commit-author-not-in-vercel-team/41348)。公式のドキュメントではない）。**いまの「アカウントの無い人も CLI でデプロイできる」形は、Vercel から見ると席の要件の回避にあたるおそれがある**（推測。CLI のデプロイが作者を検査するかは公式に書かれていない。いまは動いている）。
- Integration のトークンは 2FA の必須化の対象外だが、導入した人が抜けると無効になる。CLI の prebuilt で使えるかも未確認。
- **2027-01-20 から、Vercel の全ユーザーに認証アプリが必須になる**。共有アカウントを続けるなら、TOTP の秘密も共有することになる。

選択肢:

| 案 | アカウントの無い人も merge でデプロイできるか | 利点 | 欠点 |
|---|---|---|---|
| A. 担当者 1 名（Owner など）の個人のトークン（プロジェクトに絞り、期限付き）に替え、共有アカウントを消す | ○（いまと同じ） | 変更が最小。共有と TOTP の共有が無くなる。prebuilt とキャッシュはそのまま | 担当者の異動・退職で止まる。席の要件の回避にあたるおそれは残る |
| B. Git 連携に戻し、Deployment Checks で GitHub Actions のチェックを必須にする | ×（コミットの作者ごとに有料の席 $20/月が要る） | トークンが要らない。Vercel の推奨に最も近い | 席の費用。ビルドが Vercel 側になる（`installCommand` で `npm ci` などにする） |
| C. GitHub Actions から Deploy Hook を叩く | ×（作者の検査を受けるとされる） | Vercel のトークンが要らない | URL が秘密そのもの。prebuilt にできない。勧めない |
| D. 自作の Integration のトークン | △（未確認） | 2FA の必須化の対象外 | 用途外の使い方。導入者が抜けると無効。勧めない |
| E. CLI の OIDC を待つ | ○（Pro に開かれれば） | 静的な秘密が無くなる | いまは使えない。時期が分からない |

## デプロイの経路の精査（2026-11-06）

調査用に伊藤の PAT（チーム `turing-inc` に限り、期限は 7 日）を作り、GET だけを投げた。取った一次情報は git の外の `~/vercel/turing-inc/2026-11-06/` にある（`projects.jsonl`・`deployments.jsonl`（プロジェクトごとに直近 100 件）・`members.json`）。

プロジェクトは 12 件。デプロイの出どころ（API の `source`）で分けると次のとおり。

| 経路 | プロジェクト | デプロイを作った Vercel のユーザー | コミットの作者はチームにいるか |
|---|---|---|---|
| **CI（GitHub Actions）から CLI** | jadd-studio3 | 共有アカウント `jaddstudio3-deployment-4700` | **いない人が多い**（下記） |
| **CI（GitHub Actions）から CLI** | biz-fleet-ops（fleet-ops） | 塚本さん | **いない人が含まれる**（下記） |
| 手元から CLI（Claude Code・Codex 経由） | office-map・corp-seat-map（旧名 seat-map） | 岩崎さん | 本人（チームにいる）。`gitDirty=1`（コミットしていないコードを出している） |
| 手元から CLI（Claude Code・Codex 経由） | slack-driving-notify-test・turing-connect | 塚本さん | 本人（チームにいる） |
| Git 連携 | drivers-app3・jadd-studio-signage・digital-signage・fleet-management・genius-cad-review・road-curvature-map・turing-connect | コミットの作者 | 席の要件どおり |

GitHub の組織 `turingmotors` のコードを `VERCEL_TOKEN` で検索しても、CI から CLI でデプロイしているのはこの 2 つのリポジトリだけだった。

### jadd_studio3（jadd-studio3）

- Vercel のプロジェクトは Git 連携が無い（`link` が無い）。デプロイはすべて `.github/workflows/deploy.yml` から来ている（直近 100 件、2026-10-23〜11-05、すべて `source: cli`・production）。
- 流れ: main への push → `vercel pull --environment=production` → `vercel build --prod` → `vercel deploy --prebuilt --prod`。CLI は 51.7.0 に固定。GitHub の Environment は使っていない（secrets はリポジトリの secrets）。
- デプロイを作るのは共有アカウント `jaddstudio3-deployment-4700`（ロールは Member。2026-04-20 に参加。2FA は未設定）。
- **デプロイのメタデータに、コミットの作者の名前とメールが載る**（`githubCommitAuthorName`・`githubCommitAuthorEmail`。CLI が checkout の Git の情報から自動で付ける）。直近 100 件の作者は 16 人。名前でチームのメンバーと照合すると、**約半分（46 件）がチームにいない人**のコミットだった（Yuto Nakamura・Miwa・Ibai Gorordo・devin-ai-integration[bot] など。照合は名前だけなので推定）。
- つまり、**Vercel 側から「席の無い人のコミットが CLI で本番に出ている」ことが見える状態**にある。Vercel が CLI のデプロイにも作者の検査を広げれば、そのまま止まる。

#### GitHub でのトークンの置き方と、取り出せる人（2026-11-09 に GitHub の API で確かめた。GET だけ）

- `VERCEL_TOKEN`・`VERCEL_ORG_ID`・`VERCEL_PROJECT_ID` は、**リポジトリの Actions の secrets**（2026-04-20 に登録。`VERCEL_TOKEN` は同じ日に 1 回更新）。Environment（`copilot`・`Preview`・`Production`）はあるが、どれにも secrets は無く、保護の規則も無い。
- 値を**画面や API で見ることはできない**。secrets は書き込みだけで、リポジトリの admin でも名前と日時しか見えない。
- ただし、**リポジトリの secrets はブランチを問わず、どのワークフローからも使える**。書き込み権限のある人がブランチにワークフローを置いて push するか、そのブランチで PR を作れば、secrets を使うジョブが動く。ログでは値が伏せ字になるが、伏せ字は取り出しを止める仕組みではない。**つまり、書き込み権限のある人なら誰でも、値を取り出せる**。
  - 実際に、main に無いワークフローがブランチの PR から動いた例がある（`experiment-next-cache.yml`（graph226、2026-08-27）・`lint.yml`・`supply-chain.yml`（devin-ai-integration[bot]）。どれも `VERCEL_*` は参照していない）。直近 1,000 件の実行（2026-10-05 以降）には、`ci.yml`・`deploy.yml`・Copilot のレビュー以外の実行は無かった。それより前の実行は全部は見ていない。
- 書き込み権限（write 以上）を持つ人: **56 名**（admin 13・write 43）。チーム 12（`team-leaders`・`team-mlops-1-admin` は admin、ほかは push）と、外部のコラボレーター 2 名（sadnessOjisan・uedahotaka、write）を経由する。ほかに、ブランチに push できる bot（devin-ai-integration）がいる。
- main の ruleset（`protect main branch`）は、削除・force push の禁止、PR を必須にすること、ステータスチェック（`test`・`typecheck`・`build`）の 3 つ。**承認の数は 0**。そのため、書き込み権限のある人は、`deploy.yml` を書き換えた PR を自分で merge することもできる。ruleset は main にだけかかり、ほかのブランチは守らない。
- fork はできない（`allow_forking: false`、非公開）。外部の人が fork の PR から取り出す道は無い。
- `GITHUB_TOKEN` の既定は write で、PR の承認もできる（`can_approve_pull_request_reviews: true`）。
- 組織の secrets に `VERCEL_*` があるかは、伊藤の権限では見えない（403）。
- トークンの範囲（チーム全体かプロジェクトだけか）は分からない。共有アカウントで作ったトークンなので、伊藤の API からは見えない。

#### トークンが漏れたときの影響（2026-11-09。まだ漏れた事実は無い。想定）

トークンの持ち主は共有アカウント `jaddstudio3-deployment-4700`（ロールは Member、2FA 未設定）。範囲は不明なので、最小で jadd-studio3、最大でチームの全 12 プロジェクトが対象。

- Member はプロジェクトの管理者を兼ねるので、本番へのデプロイ・プロジェクトの設定の変更・本番の環境変数の管理ができる（[Access roles](https://vercel.com/docs/rbac/access-roles)）。
- 環境変数は、Config（`encrypted`）は読める。Secret（`sensitive`）は読み返せないが、本番の環境変数が渡るデプロイを作れるので、実質は守られない。
- jadd-studio3 の本番の環境変数には、外部の資格情報が集まっている（名前と種類だけ取得。値は取らない）。Secret 扱いは 30 件。重いものだけ: Supabase の `SUPABASE_*_SERVICE_ROLE_KEY`（RLS を迂回）・`SUPABASE_JADD_STUDIO_DATABASE_URL`（DB の接続文字列。[supabase-db-access.md](./supabase-db-access.md) の穴と直結）、`AWS_ACCESS_KEY_ID`/`SECRET`、`DATABRICKS_CLIENT_ID`/`SECRET`、`JWT_SECRET`、`MFA_ENCRYPTION_KEY`、各 CDN の秘密鍵、外部 API（Mapbox・Notion・Safie・NAVITIME・Teslemetry・Devin ほか）。
- **被害は Vercel に閉じない**。本番の環境変数を介して、Supabase の DB・AWS・Databricks などの外部の資格情報まで及ぶ。

対応（優先順）: ① トークンを失効（`DELETE /v3/user/tokens/{tokenId}` かアカウントの Tokens 画面）。② Git 連携に移してトークンを無くす（既定の方針）。つなぎなら、トークンを Environment `Production` に移して main 限定にし、PR に承認を必須化する。③ 漏れた前提での環境変数のローテーション（Supabase の service_role・AWS・Databricks・JWT/MFA の鍵。jadd_studio3 側の担当と相談）。

### fleet-ops（biz-fleet-ops）

- Vercel のプロジェクトは GitHub に連携しているが、`vercel.json` の `git.deploymentEnabled: false` で Git 連携からのデプロイを止めている。デプロイはすべて `.github/workflows/vercel-preview.yml` から来ている（直近 100 件、すべて `source: cli`・production）。
- 作った経緯: runbook（`docs/runbooks/deployment.md`）に「**Git 連携で作者の Vercel アカウント確認が通らない場合は**、承認付き Vercel Deploy で…手動実行できる」とある。2026-09-30 に PR [fleet-ops#246](https://github.com/turingmotors/fleet-ops/pull/246)〜[fleet-ops#248](https://github.com/turingmotors/fleet-ops/pull/248) で入った。**席の要件を避けることが目的として資料に書かれている**。
- 流れ: SHA が main と一致するかを確かめる → **`git archive` で Git の作業ツリーの外へ出し、作業ツリーでないことを確かめてから** pull・build・deploy する。このため **CLI がコミットの作者を付けられず、メタデータに作者が載らない**。代わりに独自の `--meta`（`sourceCommit`・`workflowRun`・`requestedBy`＝GitHub のユーザー名）を付けている。runbook は SHA の固定のためと書いているが、結果として Vercel からは作者が見えない。
- `requestedBy` には、チームにいない人（maikosuzuki-5・yamaz-aki・devin-ai-integration[bot]）が含まれる。
- トークンは塚本さん個人のもので、範囲は**チームの All Projects**（runbook。プロジェクトに絞ると CLI 59.10.0 の `vercel pull` が失敗するため）。GitHub の Environment `vercel-production`（main に限る）に置いてある。**fleet-ops の CI から、チームのほかのプロジェクト（jadd-studio3 を含む）も触れる**。
- `docs/runbooks/deployment.md` の表は「Web アプリは Vercel の GitHub 連携で push 時に自動」のままで、いまの実態と食い違っている。

### Git 連携の席の要件は実際に効いている

- fleet-management で、2026-10-27 にチームにいない作者（kanade-k-1228）のコミットが 2 件 **BLOCKED** になっていた（"The deployment was blocked because the commit author doesn't have permission to create deployments for this project."）。
- 同じプロジェクトでも renovate[bot] のコミット（95 件）は通っている。bot は対象外らしい（推測）。

### 見立て（まだ決めていない）

- 危うさは fleet-ops のほうが大きい。席の要件を避けるためと資料に書いてあり、作者が Vercel に見えない形にしてある。Vercel から見れば「検査を避ける作り」と読まれうる。
- jadd_studio3 は、作者が Vercel に見えるぶん素直だが、Vercel が CLI にも検査を広げれば止まる。共有アカウントの問題も重なる。
- 手元からの CLI（岩崎さん・塚本さん）は、デプロイした人がチームにいるので、席の要件の点では問題ない。

## 2FA の状況（2026-11-06 15:24 に取得、API の `mfaEnabled`）

**2026-11-09 に取り直した結果: 19 名中 18 名が設定済み。人のアカウントは全員設定済みで、未設定は共有アカウント `jaddstudio3-deployment-4700` だけ**（犬塚さん（shintaroinuzuka-9342）が設定した）。**これで人のアカウントの 2FA は完了とする**（伊藤、2026-11-09）。一次情報は `~/vercel/turing-inc/2026-11-09/members.json`。この取得では、11-06 の記録で Developer と書いた人のロールがすべて `MEMBER` で返った（API の表記の違いか、ロールが変わったかは確かめていない）。

**16:24 に取り直した結果: 19 名中 17 名が設定済み。未設定は shintaroinuzuka-9342 と共有アカウントだけ**（15:24 からの 1 時間で 5 名が設定した）。18:39 に取り直しても変わらず。下の表は 15:24 の時点のもの。

19 名中、未設定は 7 名。計画の 1 のアナウンスでは、共有アカウントを除く 6 名に設定してもらう。海老澤さん（Owner）は 2026-11-06 に設定した（09:50 の取得では未設定、15:24 の取得で設定済み）。人のアカウントは、本人が 2FA を設定してもデプロイの経路に影響しない（止まるのは必須化したときだけ。CI のトークンを持つ塚本さんは設定済み）。

| ロール | ユーザー | GitHub | 最後にデプロイを作った日 |
|---|---|---|---|
| Member | atsushiabe-7916 | piste-jp | 2026-10-29 |
| Member | bonaizawa | BonAizawa | 2026-11-06 |
| Member | shintaroinuzuka-9342 | graph226 | - |
| Member | takafumiwatanabe-6923 | ohnabe | - |
| Member | yusukeomae-9953 | rary21 | - |
| Member | yuyaiwasaki-8105 | - | 2026-08-28 |
| （共有アカウント。アナウンスの対象外） | jaddstudio3-deployment-4700 | - | 2026-11-05 |

設定済み（12 名）: ito-yusaku-turing・hayataebisawa-2001・masahiroyasumoto-3938・yamashu-turing（以上 Owner）、daikishiotsuka-5671・kento-1989・sangotaro・shokamekawa-7414・shuheitsukamoto-5730・shunsukeshibata-8695・takuyayamashita-5395・colum2131（Developer）。

- 「最後にデプロイを作った日」は、プロジェクトごとの直近 100 件の中での最新。`-` は使っていないという意味ではない。
- sangotaro と colum2131 は gmail のアドレスで入っている。外す人を決めるときに確かめる。

## ログインの方法と MFA の効き目（2026-11-06）

公式ドキュメントとログインの画面で確かめたこと:

- **Vercel**: ログインはメール（6 桁の使い捨てのコード）・GitHub・GitLab・Bitbucket・passkey・SAML（チーム）。**パスワードでのログインは無い。Google でのログインも無い**（[Accounts](https://vercel.com/docs/accounts)）。GitHub をつないでいないメンバー（kento-1989・takuyayamashita-5395・yuyaiwasaki-8105・共有アカウント）は、メールのコードで入っていると思われる。
- **Supabase**: ログインの画面は GitHub・ChatGPT・SSO と、**メールとパスワード**。Google は無い（[sign-in](https://supabase.com/dashboard/sign-in)）。
- どちらも、GitHub などでログインしたときにもサービスの 2FA を求めるかは、ドキュメントに書かれていない。伊藤（両方で設定済み）が GitHub でログインし直して確かめられる。
- Supabase の API（`GET /v2/organizations/{slug}/members`）は、ログインの方法を返さない。`username` が GitHub のユーザー名の人（5 名）と、メールアドレスの人（10 名）がいる。後者はメールとパスワードで登録した可能性がある（推測。確かめるには本人に聞く）。
- GitHub の組織 `turingmotors` が 2FA を必須にしているかは、伊藤の権限では見えない（`two_factor_requirement_enabled` が null。組織の Owner なら見える）。

## 移行の設計（2026-11-06）

方針（伊藤）: **main への merge で本番に出る便利さは残す。代わりに、席の無い人の merge でデプロイが失敗する（BLOCKED）ことは受け入れる。** つまり、両方とも Vercel の Git 連携に戻す。CI のトークンと共有アカウントは無くす。

全体の計画（伊藤の案に補足を入れたもの。2026-11-06）:

1. **今すぐ**: 要らない人を外す → 海老澤さんに 2FA を個別に依頼 → 全員に MFA の有効化をアナウンス（共有アカウントは対象外） → fleet-ops の `vercel-preview` のトークンを止める
2. **12 月中旬まで**: jadd_studio3・fleet-ops を Git 連携に移す（担当の人と合意を取ってから） → 共有アカウントを消す
3. **2027-01-20 の前後**: MFA を強制する

### Vercel が見る「作者」

- 両リポジトリとも **squash merge と rebase merge だけ**を許している（merge commit は不可）。squash の main のコミットは、**作者が PR を作った人**で、committer が GitHub になる。**merge ボタンを押した人ではない**。
- Git 連携が検査するのは「コミットの作者」（[Git](https://vercel.com/docs/git#deploying-private-git-repositories)）。したがって、**席のある人が merge しても、PR の作者が席の無い人なら BLOCKED になる**。
- ブロックされた変更は消えない。次に席のある人の PR が merge されると、その時点の main がまるごと出るので、一緒に本番に出る。ただし、本人の知らないうちに他人の変更が一緒に出ることになる。
- 作者の照合は、Vercel のアカウントにつないだ GitHub のアカウントで行う（推定）。チームのメンバーでも GitHub をつないでいない人（kento-1989・takuyayamashita・yuyaiwasaki-8105）は、作者として通らないおそれがある。
- fleet-management で 2026-10-27 にブロックされた 2 件は、チームにいない人（kanade-k-1228）が renovate のブランチに push したもの。renovate[bot] のコミットは通っている。

main の直近 100 コミットの作者を GitHub のユーザー名で照合した結果（2026-11-06。前回の名前での照合は、colum2131＝Kohei Iwamasa さんを誤ってチーム外に数えていた）:

| リポジトリ | チームにいる人 | チームにいない人 | devin-ai-integration[bot] |
|---|---|---|---|
| jadd_studio3 | 59 件 | 35 件（yutyan0119 17・ensan-hcl 8・ibaiGorordo 6・koukyo1994 3・Masakichi210 2・Rozk12 1） | 6 件 |
| fleet-ops | 77 件 | 4 件（yamaz-aki 2・maikosuzuki-5 2） | 19 件 |

devin のコミットが通るかは分からない（renovate[bot] は通る）。fleet-ops では 2 割近くを占めるので、試す必要がある。

### 席の数と費用の試算（2026-11-09）

jadd_studio3 で、直近 3 か月（2026-08-09〜11-09）に merge された PR を GitHub の API で集計した。合計 648 件で、作者は人が 20 名、ほかに devin-ai-integration[bot] が 97 件。Git 連携が見る作者は squash の main のコミットの作者で、PR の作者と同じなので、PR の作者で数えた。

- チームにいる 9 名: ebiebix 128・ito-yusaku-turing 58・shuhei-tsukamoto 34・graph226 34・rary21 19・colum2131 12・Daiki-Shiotsuka 11・MasahiroYasumoto 8・yamashush 5
- チームにいない 11 名（PR は合わせて 179 件）: ensan-hcl 50・yutyan0119 44・ibaiGorordo 23・Masakichi210 16・koukyo1994 10・inuex35 5・abemii2 2・keishihara 1・katsuster 1・hakubishin3 1・Rozk12 1

課金対象は Owner・Member・Developer の席（Viewer は無料）。基本料金 $20 に 1 席が含まれるので、月額は $20 × 席の数。

| 場合 | 席の数 | 月額 |
|---|---|---|
| いま（Owner 4・Member 14・共有アカウント 1。Viewer はいない） | 19 | $380 |
| 共有アカウントを消す | 18 | $360 |
| ＋ jadd_studio3 の PR が 5 件以上の 6 名を足す | 24 | $480 |
| ＋ jadd_studio3 のチームにいない 11 名を全員足す | 29 | $580 |
| ＋ fleet-ops のチームにいない 2 名（yamaz-aki・maikosuzuki-5）も足す | 31 | $620 |
| 11/6 の方針のまま（席を足さず、BLOCKED を受け入れる） | 18 | $360。直近 3 か月の PR の約 3 割（179 / 648 件）が BLOCKED になる |

- 確かめていないこと: devin-ai-integration[bot] が作者のコミットが通るか（「試して確かめること」）。チームにいる 18 名の中に、デプロイしない人（Viewer に移せる人）がいるか。調べるには、Git 連携でデプロイしているほかのプロジェクトの作者も見る必要がある。
- GitHub のアカウントの持ち主の推定（ensan-hcl＝三輪さん、koukyo1994＝荒井さん、inuex35＝井上さん、abemii2＝阿部さん、Masakichi210＝川村さんなど）は、コミットの名前とメールから推した。hakubishin3 が誰かは分からない。
- 席を足すか、BLOCKED を受け入れるかは、まだ決めていない。

### GitHub Actions でしかしていないこと（精査の結果）

jadd_studio3（`deploy.yml`）:

| していること | Git 連携に移したとき | 手当て |
|---|---|---|
| main の push で `node_modules` のキャッシュを保存し、**PR の CI（`ci.yml`）のキャッシュの供給元を兼ねている** | `deploy.yml` を消すと、PR の CI のキャッシュが当たらなくなる | `ci.yml` に、main の push でキャッシュだけを作るジョブを足す |
| Node を `.nvmrc` の 24.22.1 に固定してビルド | Vercel は 24.x の最新で組む（パッチまでは固定できない） | 受け入れる。ネイティブの依存（lz4・roaring・sharp）は、実行する環境と同じ所で組むぶん、むしろ素直になる |
| `SKIP_NPM_CI=1` で `npm ci` を飛ばす | 使わなくなる | `vercel.json` の `installCommand` を `npm ci` に戻す（`npm ci` のあと postinstall で `prisma generate` と `assets:place` が走る） |
| デプロイの前のテストは無い（テストは PR の `ci.yml`） | 変わらない | なし |
| GitHub の secrets は `VERCEL_*` だけ。ビルドの環境変数は Vercel の Production から `vercel pull` で取る | Vercel が直接使う | secrets を消す |

fleet-ops（`vercel-preview.yml`）:

| していること | Git 連携に移したとき | 手当て |
|---|---|---|
| **本番に出す前のテスト**（`test:scheduler`・`test:auth-callback`・`tsc --noEmit`） | 何もしないとテストを通らずに出る | Vercel の Build Command を `npm run test:scheduler && npm run test:auth-callback && npx tsc --noEmit && next build` にする（Vercel の上で走るので、落ちればデプロイされない） |
| main の先頭と SHA が一致するかを、ビルドの前後で確かめる（古いコミットを出さない） | Git 連携はコミットごとに組む | 古いデプロイが新しいものを上書きしないかは未確認。試す |
| CLI を 59.10.0 に固定し、`tar` を上書きする | CLI を使わなくなる | なし |
| GitHub の Environment `vercel-production`（main だけ）にトークンを置く | トークンが要らなくなる | Environment `vercel-production`・`vercel-preview` とトークンを消す。塚本さんのトークンは失効してもらう |
| 独自の `--meta`（`sourceCommit`・`requestedBy`）で追跡する | Git 連携が作者と SHA を付ける | なし |

ほかのワークフロー（`db-check`・`feature-boundaries`・`vehicle-registry`・`vehicle-registry-sync`）はデプロイと関係ない。`vehicle-registry-sync` は Vercel 上のアプリの API を呼ぶだけで、トークンは使わない。

### どこで何を操作するか

jadd_studio3:

1. **GitHub**（組織の管理者）: Vercel の GitHub App が `turingmotors/jadd_studio3` を読めるか確かめる。読めなければ、対象のリポジトリに足す。
2. **リポジトリ**（PR。作者は席のある人）: `vercel.json` の `installCommand` を戻し、本番以外を組まない設定（`git.deploymentEnabled` か `ignoreCommand`）を入れる。`deploy.yml` を消し、`ci.yml` にキャッシュを作るジョブを足す。`docs/general/deployment.md` を直す。
3. **Vercel**（Owner）: jadd-studio3 → Settings → Git で `turingmotors/jadd_studio3` をつなぐ。Production Branch は `main`。
4. 3 の直後に 2 の PR を merge する。push のときは、push したコミットにあるワークフローが動くので、`deploy.yml` を消したコミットでは Actions が動かず、Git 連携だけがデプロイする。3 と 4 の間にほかの merge が入ると二重にデプロイされるので、続けて行う。
5. デプロイと本番の画面を確かめる。
6. **GitHub**: secrets の `VERCEL_TOKEN`・`VERCEL_ORG_ID`・`VERCEL_PROJECT_ID` を消す。
7. **Vercel**（Owner）: 共有アカウント `jaddstudio3-deployment-4700` をチームから外し、アカウントも消す。

fleet-ops（Git 連携はつながっている）:

1. **リポジトリ**（PR。作者は席のある人。塚本さんと合意してから）: `vercel.json` の `git.deploymentEnabled: false` を外し、本番以外を組まない設定にする。Build Command にテストを入れる。`vercel-preview.yml` と `scripts/vercel-preview*` を消し、runbook（`deployment.md`・`vercel-preview.md`）を直す。
2. merge して、Git 連携でデプロイされたことを確かめる。
3. **GitHub**: Environment `vercel-production`・`vercel-preview` を消す。**Vercel**: 塚本さんにトークンを失効してもらう。

### 試して確かめること（小さなプロジェクトで）

- [ ] 席の無い人の PR を席のある人が squash merge したとき、BLOCKED になるか
- [ ] devin-ai-integration[bot] が作者のコミットが通るか
- [ ] BLOCKED になったあと、席のある人が出し直せるか（ダッシュボードの Redeploy、または Git の参照からのデプロイ）
- [ ] 本番以外を組まない設定の書き方（`git.deploymentEnabled` で main だけを有効にできるか。だめなら `ignoreCommand`）
- [ ] 古いコミットのデプロイが、あとから終わって新しいものを上書きしないか
- [ ] ダッシュボードのチームの設定で、チームにいない作者を自動でメンバーに足す、または承認を求める動きになっていないか（足されると有料の席が増える。API では見えなかった）

## 設計判断と理由

（まだ無い）

## 進捗チェックリスト

- [x] リポジトリから、チーム `turing-inc` と使われ方を洗い出す
- [x] SSO・2FA の必須化・ロール・料金・API を調べる（Pro なら SSO は +$300/月、2FA の必須化は追加の費用なし）
- [x] 現状を聞き取る（Pro・Owner 4 名・メンバー 20 名弱・2FA は約半分）
- [x] CI のトークンの持ち主を確かめる（fleet-ops は塚本さんで 2FA 済み。jadd_studio3 は共有アカウント `jaddstudio3-deployment-4700` で 2FA 未設定）
- [x] 共有アカウントを使わないデプロイの方法を調べる（案 A〜E）
- [ ] 共有アカウントをなくす案を選ぶ（**次回の議論**）
- [ ] 選んだ案に切り替え、共有アカウントを消す（2027-01-20 より前に）
- [x] 調査用の PAT を用意する（チームに絞り、期限は 7 日。GET だけ使う。終わったら無効にする）
- [x] JADD Studio のデプロイの仕組みを精査する
- [x] 同じ形（CI から CLI・トークンでデプロイ）のプロダクトがほかにないか調べる（fleet-ops だけ）
- [x] Vercel の動向から見て安全な運用方法を決める（Git 連携に戻し、席の無い人の merge は BLOCKED を受け入れる。2026-11-06）
- [ ] 小さなプロジェクトで作者の検査の挙動を試す（「移行の設計」の「試して確かめること」）
- [ ] jadd_studio3 を Git 連携に移す
- [ ] fleet-ops を Git 連携に移す（塚本さんと合意してから）
- [ ] メンバー一覧と 2FA の状況を取り、名簿（Okta）と突き合わせる
- [ ] 外す人を決めて外す（伊藤は Owner なので自分でできる）
- [ ] SSO を入れるか決める（Pro の add-on で +$300/月）
- [x] 人のアカウントの 2FA を全員に設定してもらう（2026-11-09 完了。未設定は共有アカウントだけ）
- [ ] 2FA を必須にする（共有アカウントを消してから。2027-01-20 の前後）

## 次セッションへの引き継ぎ

**2026-11-09**: 犬塚さんが 2FA を設定し、人のアカウントは全員済んだ（「2FA の状況」）。Vercel の再アナウンスは要らなくなった。Supabase も同じ日に取り直し、15 名全員が MFA を設定済みだった（記録は `done/supabase-accounts.md`）。

**2026-11-06 の締め（伊藤）**: 全体に MFA の有効化をアナウンスした。18:39 の時点で Vercel は 19 名中 17 名が設定済み（未設定は shintaroinuzuka-9342 と共有アカウント）。Supabase は 15 名中 13 名（未設定は安本さん（Owner）と shunsuke-1222。記録は `done/supabase-accounts.md`）。**残りは週明けに伊藤が再アナウンスする**。

週明けにやること:

1. 再アナウンスの後に、両方のメンバーを API で取り直す（Vercel は `GET /v3/teams/{teamId}/members` の `mfaEnabled`、Supabase は `GET /v2/organizations/dhazyhuzuwitqasezcvr/members` の `mfa_enabled`）。**毎回取り直す。前に取ったファイルを使い回さない**。
2. 計画の 1 の残り: 要らない人を外す（名簿と突き合わせる）。fleet-ops の Environment `vercel-preview` のトークンを止める。
3. 計画の 2: 小さなプロジェクトで「試して確かめること」を試す → 塚本さんたちと合意を取る → 移行する。

調査用のトークン:

- Vercel の PAT（`~/.config/vercel/token`。伊藤のもの、チーム `turing-inc` に限る）は 2026-11-13 ごろに切れる。GET だけを送るラッパーは、そのセッションの作業用ディレクトリに置いた使い捨てのもの。作り直すなら、`curl -X GET` に `teamId=team_pI0XxaMASApEgMjswpsMuOLJ` を付ける。
- Supabase の PAT（`~/.config/supabase/pat`）は 2026-11-12 ごろに切れる。
- 調査が終わったら、どちらも無効にしてファイルを消す。

**次にやること（2026-11-06）: 方針は「Git 連携に戻し、席の無い人の merge は BLOCKED を受け入れる」に決めた（「移行の設計」）。次は小さなプロジェクトで作者の検査の挙動を試すことと、計画の 1（要らない人を外す → MFA のアナウンス）。** 対象は jadd_studio3 と fleet-ops の 2 つ（「デプロイの経路の精査」）。調査用の PAT は 2026-11-13 ごろに切れる。終わったら無効にし、`~/.config/vercel/token` を消す。

**前回からの議論: 共有アカウント `jaddstudio3-deployment-4700` をどうなくすか。**

- 前提: jadd_studio3 は GitHub Actions + Vercel CLI でデプロイしている。目的は、Vercel のアカウントが無い人にも main への merge でデプロイを開くこと（伊藤の認識）。トークンは共有アカウントのもので、2FA 未設定。
- 制約: 人に紐づかないトークンも、GitHub Actions からの OIDC も、まだ無い。Pro の Git 連携はコミットの作者ごとに有料の席が要る。いまの形は席の要件の回避にあたるおそれがある。2027-01-20 から全ユーザーに認証アプリが必須になる。詳しくは「共有アカウントを使わないデプロイの方法」。
- エージェントの推奨（まだ決めていない）: 2027-01-20 までに **案 A**（Owner の伊藤か海老澤さんの、プロジェクトに絞った期限付きのトークンに替え、共有アカウントを消す）。**Vercel には問い合わせない**（2026-11-06、伊藤の判断。藪蛇になるため）。代わりに、Vercel の動向から見て安全な運用方法を先に考える。
- 決まったら、切り替えの手順（トークンの作成 → GitHub の secrets の入れ替え → デプロイの確認 → 共有アカウントの削除）を作る。A の場合、トークンを GitHub の Environment（main だけに限る）に置くかも決める。

そのほか:

- 2FA を必須にする前に、海老澤さん（Owner）本人と、CI のトークンの持ち主の 2FA を済ませる。fleet-ops のトークン（塚本さん）は 2FA 済みで問題ない。fleet-ops の Environment `vercel-preview` のトークン（2026-11-02 作成）は持ち主が分からない（CI からは使わないとされている）。
- メンバー一覧と 2FA の有無は API（`GET /v3/teams/{teamId}/members` の `mfaEnabled`）で取れる。2026-11-06 15:24 時点で 19 名中 7 名が未設定（「2FA の状況」）。
- Supabase の結論（[documents/supabase-org-account-policy.md](../../documents/supabase-org-account-policy.md)）と比べると、Vercel の SSO は Pro の add-on（$300/月）で入れられる点が違う。SSO を入れるかはまだ決めていない。

## 関連リンク

- [supabase-db-access.md](./supabase-db-access.md): 派生タスク。Supabase の DB に psql などで直接つなぐ経路は MFA が効かないので、経路の把握とセキュリティ強化を別に進める（2026-11-09 起票）
- [project:privileged-access](../../privileged-access/README.md): 組織の Owner は権限の頂点の地図（privilege-map.md）に反映する
- [project:idp-broker](../../idp-broker/README.md): 社内アプリを使う人の認証の入口の選定（この案件は社員が Vercel そのものに入るためのアカウントで、別物）
