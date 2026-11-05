# Vercel のアカウントの棚卸しと SSO 化の検討

- 開始: 2026-11-05
- 状態: **SSO・2FA・料金を調べた**（2026-11-05）。Pro なら SSO は +$300/月、2FA の必須化は追加の費用なし。Pro・Owner 4 名（伊藤を含む）・2FA は約半分と聞いた。次はメンバー一覧と 2FA の状況を取り、CI のトークンの持ち主を確かめる
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

- 海老澤さん（Owner）は **2FA 未設定**。塚本さんは設定済み。
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
- **2026-12-31 に、Vercel の全ユーザーに認証アプリの登録が必須になる**（Enterprise は同じ日に 2FA の必須化が強制でオンになる）。

ロール（Pro で使えるのは Owner・Member・Developer・Billing・Pro Viewer）:

- **メンバーの招待・削除・ロールの変更は Owner だけ**。Supabase と違い、Owner でない人は人を外せない。
- Member はプロジェクトとチームの設定のほとんどを扱える。Developer は Production の環境変数を変えられない。Pro Viewer は読み取りだけ。
- 見るだけの人を Pro Viewer に移すと、有料の席が減る（推測）。

棚卸しに使う API:

- `GET /v3/teams/{teamId}/members`: ロール・メール・Git のアカウント・`joinedFrom`（SSO で入ったか）・`createdAt` が返る。**2FA の有無と最後のログインは返らない**（2FA はダッシュボードの Members で見る。disabled で絞り込める）。
- `GET /v10/projects`: プロジェクトの一覧。
- トークンはチームや 1 つのプロジェクトに絞れ、有効期限も付けられる。**読み取りだけのスコープは無い**（チームに絞ったトークンでも読み書きできる）。

## 設計判断と理由

（まだ無い）

## 進捗チェックリスト

- [ ] 棚卸しの対象（組織・チーム・プロジェクト）を洗い出す
- [ ] メンバーと権限（Owner・管理者など）の一覧を作る
- [ ] 退職者・不明なアカウント・強すぎる権限を掃除の候補にする
- [x] SSO・2FA の必須化・ロール・料金・API を調べる（Pro なら SSO は +$300/月、2FA の必須化は追加の費用なし）
- [ ] SSO 化の案（IdP・移行手順・影響）をまとめる

## 次セッションへの引き継ぎ

- 公式ドキュメントの調べと、現状の聞き取り（Pro・Owner 4 名・2FA は約半分）は済んだ。次はメンバー一覧と 2FA の状況を取り、名簿と突き合わせる。
- **2FA を必須にする前に、CI の `VERCEL_TOKEN` を作った人が 2FA を設定しているか確かめる**。fleet-ops は塚本さん（2FA 設定済み）で問題ない。jadd_studio3 は `jaddstudio3-deployment-4700`（確定）で 2FA 未設定。必須にする前に、このアカウントに 2FA を設定する（ログインの情報と認証アプリを誰が持つかも決める。作ったのは海老澤さんと思われる）。海老澤さん（Owner）本人の 2FA も要る。
- メンバー一覧は API で取れるが、2FA の有無は API で取れない。ダッシュボードの Members の画面で見る。
- トークンに読み取りだけのスコープは無い。API を使うなら、チームに絞り、期限を短くし、使い終わったら失効させる。
- Supabase の結論（[documents/supabase-org-account-policy.md](../../documents/supabase-org-account-policy.md)）と比べると、Vercel の SSO は Pro の add-on（$300/月）で入れられる点が違う。

## 関連リンク

- [project:privileged-access](../../privileged-access/README.md): 組織の Owner は権限の頂点の地図（privilege-map.md）に反映する
- [project:idp-broker](../../idp-broker/README.md): 社内アプリを使う人の認証の入口の選定（この案件は社員が Vercel そのものに入るためのアカウントで、別物）
