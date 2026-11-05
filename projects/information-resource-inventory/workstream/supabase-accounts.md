# Supabase のアカウントの棚卸しと SSO 化の検討

- 開始: 2026-11-05
- 状態: **現状の聞き取り、参照されているプロジェクト 6 件の洗い出し、SSO・MFA の提供条件の調査を終えた**（2026-11-05）。次は伊藤の scoped PAT でメンバー一覧（ロール・MFA）とプロジェクト一覧を取る
- 所属: project:information-resource-inventory

Supabase のアカウント（組織・チームのメンバーと、その権限）を棚卸しし、社の IdP（Okta / Google Workspace）による SSO に寄せられるかを検討する。

## 背景・目的

- Supabase のアカウントの一覧と権限を把握する。
- 退職者・協力会社のアカウントが残っていないか、Owner など強い権限を誰が持っているかを確かめる。
- 入退社に合わせてアカウントを管理できるよう、SSO 化（あわせて可能ならプロビジョニング）を検討する。

## 現状（2026-11-05 時点）

伊藤から聞いた内容:

- 組織 ID: `dhazyhuzuwitqasezcvr`。会社名義で Pro プランを契約している
- Owner: 安本さん・山本さん・渡辺孝文さんの 3 名
- 伊藤: 会社の GitHub アカウントでログイン。ロールは Administrator
- メンバーのほとんどは MFA が無効

リポジトリに出てくるプロジェクト（2026-11-05 に `/usr/app/` 配下を grep。この組織に属するかは未確認）:

| プロジェクト ref | 使っているところ | 見立て |
|---|---|---|
| `lvngtemehmcxemnurgwb` | cdk-apps の backend-api、jadd-cli、mono-e2e（scenario-test・garuda-builder） | backend-api の認証（backend-prod） |
| `ebdfwtvfpemzevdpxmek` | jadd_studio3（`env/static.yaml`）、jadd-studio-signage、mono-e2e | JADD Studio の DB |
| `zlsxpcotdkwjrktfovqd` | jadd_studio3（`env/static.yaml`） | ドライバーズアプリ |
| `seacktbfnjusvroguhwc` | jadd_studio3 の完了した workstream（scene-set-migration）だけ | 旧 tuscenes。移行済みで不要かもしれない |
| `qgnfaidhxcuqivmgubuy` | fleet-ops | fleet-ops |
| `fdgjfmuvmiwipxsfyecw` | cdk-apps の trajectory-visualizer | trajectory-visualizer |

手元（devbox）には Supabase CLI も Personal Access Token も無い。メンバー一覧を API で取るには、伊藤のトークンが要る。

## 公式ドキュメントで分かったこと（2026-11-05 に確認）

ダッシュボードに入るアカウントの話。アプリ側の Supabase Auth とは別。

| 機能 | 使えるプラン | いまの Pro で | 出典 |
|---|---|---|---|
| ダッシュボードへの SSO（SAML） | Team（$599/月〜）・Enterprise | **使えない** | [SSO](https://supabase.com/docs/guides/platform/sso)・[料金](https://supabase.com/pricing) |
| 組織の MFA 強制（Require MFA to access organization） | Pro・Team・Enterprise | **使える** | [MFA enforcement](https://supabase.com/docs/guides/platform/mfa/org-mfa-enforcement) |
| Read-only ロール・プロジェクト単位のロール | Team・Enterprise | 使えない | [Access control](https://supabase.com/docs/guides/platform/access-control) |
| 組織の監査ログ（Platform Audit Logs） | Team・Enterprise | 使えない | [Platform Audit Logs](https://supabase.com/docs/guides/security/platform-audit-logs) |

SSO:

- 対応する IdP は SAML 2.0 全般。Okta と Google Workspace には手順書がある。
- GitHub ログインなどの既存のアカウントは、同じメールでも SSO のアカウントとは別物で、紐づけられない。一度外して、SSO 必須の招待で入れ直す。
- SSO を使わない Owner を最低 1 つ残す必要がある（SSO の設定を外すときにも要る）。
- 招待ごとに「SSO 必須」か「SSO 以外も可」かを選べる。auto-join（メールのドメインで自動参加）もある。
- SCIM による自動プロビジョニングは、ドキュメントで確認できなかった。

MFA 強制:

- 有効にできるのは Owner だけ。その Owner 自身が MFA を設定している必要がある。**伊藤（Administrator）は有効にできない**。
- 有効にすると、MFA を設定していないメンバーは即座に組織のリソースに触れなくなる。メンバーからは外れず、MFA を設定すれば戻る。
- **Personal Access Token（PAT）は強制の対象外**。PAT は別に棚卸しする必要がある。
- リカバリーコードは無い。要素をすべて失うとアカウントを戻せないので、予備の TOTP を別の端末に登録するよう周知する。

ロール（Pro で使えるのは Owner・Administrator・Developer の 3 つ）:

- Administrator は Owner の追加・削除、組織の設定の変更、プロジェクトの移管ができない。Administrator・Developer の追加・削除と、課金の変更はできる。
- Developer は service キーを読める。Pro には Read-only が無いので、見るだけの人も Developer 以上になる。

棚卸しに使う API:

- `GET /v2/organizations/{slug}/members`: メンバーごとに `mfa_enabled`・`is_sso_user`・ロールが返る（v1 にも `mfa_enabled`・`role_name` がある）。
- `GET /v1/projects`: `ref`・`organization_id`・`name`・`status` などが返る。
- トークンは、Organization Members と Organization Projects の Read を持つ scoped PAT にする。権限は本人のロールを超えない。メンバー一覧は全ロールで見られるので、Administrator で呼べるはず（未確認）。

### SSO のためのプランの料金（2026-11-05 に確認）

出典: [料金](https://supabase.com/pricing)・[Billing](https://supabase.com/docs/guides/platform/billing-on-supabase)・[Compute](https://supabase.com/docs/guides/platform/manage-your-usage/compute)・[SSO MAU](https://supabase.com/docs/guides/platform/manage-your-usage/monthly-active-users-sso)

- プランは組織単位で、組織の全プロジェクトにかかる。料金表では、メンバーの人数による課金は無い（Unlimited）。
- 基本料金は Pro が $25/月〜、Team が $599/月〜（差は **$574/月**）。Enterprise は個別見積もりで、料金は公開されていない。
- compute の credit（$10/月 = Micro 1 台分）と、含まれる使用量（egress 250 GB・MAU 10 万など）は Pro と Team で同じ。compute はプロジェクトごとの時間課金で、プランによらず同じ単価（Micro 約 $10/月、Small 約 $15/月、Medium 約 $60/月、Large 約 $110/月）。
- したがって、Team に上げて増えるのは基本料金の差だけ。例えば 6 件すべてが Micro なら、Pro 約 $75/月 → Team 約 $649/月になる。
- Team で増えるもの: SSO、Read-only とプロジェクト単位のロール、組織の監査ログ、ログの保持（7 → 28 日）、バックアップ（7 → 14 日）、SOC2・ISO 27001 のレポート、メールサポートの SLA。稼働率の SLA は Enterprise だけ。
- 未確認:
  - 料金表の SSO の行は Team も「Contact Us」になっている。追加の料金や手続きが要るかは書かれていない。
  - 「from $599」の条件、年払いの割引、プランを途中で変えたときの日割り。
  - SSO の従量課金（50 MAU まで無料、超えると $0.015/MAU）の説明はアプリ側の SSO（`signInWithSSO`）のもので、ダッシュボードのログインにもかかるかは書かれていない。
  - 各プロジェクトのいまの compute のサイズ（請求の実額は、Owner か Administrator が請求画面で確かめる）。

## 設計判断と理由

- 一次情報（メンバー一覧など。メールアドレスを含む）は git で管理せず、`~/supabase/dhazyhuzuwitqasezcvr/` に置く。aws-resource-inventory と同じ扱い。
- SSO は Team プランへの格上げ（$599/月〜）が前提になるので、先に Pro のままできる MFA の強制を案にする（案。まだ決めていない）。

## 進捗チェックリスト

- [x] 現状を聞き取る（Owner 3 名・Pro・MFA ほぼ無効）
- [x] リポジトリから参照されているプロジェクトを洗い出す（6 件）
- [x] SSO・MFA 強制・ロール・監査ログの提供条件を調べる
- [ ] scoped PAT を作り、メンバー一覧（ロール・MFA）とプロジェクト一覧を API で取る
- [ ] リポジトリのプロジェクトと組織のプロジェクトを突き合わせる（ほかの組織にあるものは無いか）
- [ ] 退職者・不明なアカウント・強すぎる権限を掃除の候補にする
- [x] SSO のためのプラン（Team）の料金を調べる（差額 $574/月。未確認の点は営業に問い合わせ）
- [ ] MFA の強制の案をまとめ、Owner に頼む（予備の TOTP の周知、PAT の扱いも含む）
- [ ] SSO 化の案（Team への格上げの要否・IdP・移行手順・影響）をまとめる

## 次セッションへの引き継ぎ

- 次は伊藤が scoped PAT を作る。権限は Organization Members（Read）と Organization Projects（Read）の 2 つだけにし、対象の組織は `dhazyhuzuwitqasezcvr` だけにする。使うのは `GET /v2/organizations/{slug}/members` と `GET /v2/organizations/{slug}/projects`（DB の `infra_compute_size` も返る）。Projects (account-wide) は組織で絞れないので付けない。Legacy（全権限）は使わない。調査が終わったら失効させる。エージェントはそのトークンで API からメンバー一覧とプロジェクト一覧を取る。トークンは画面に出さない形で渡してもらう（例: 権限 600 のファイルに置く）。
- MFA の強制と SSO の設定は Owner にしかできない。伊藤の役割は、案を作って Owner に頼むこと。

## 関連リンク

- [project:privileged-access](../../privileged-access/README.md): 組織の Owner は権限の頂点の地図（privilege-map.md）に反映する
- [project:idp-broker](../../idp-broker/README.md): 社内アプリを使う人の認証の入口の選定（この案件は社員が Supabase そのものに入るためのアカウントで、別物）
