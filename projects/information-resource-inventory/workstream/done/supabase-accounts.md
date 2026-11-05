# Supabase のアカウントの棚卸しと SSO 化の検討

- 開始: 2026-11-05
- 状態: **完了**（2026-11-05）。SSO は見送り、MFA を必須にし、使っていない人を外した（20 → 16 名）
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

リポジトリに出てくるプロジェクト（2026-11-05 に `/usr/app/` 配下を grep。組織との突き合わせは下の「API で取った組織の現状」）:

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

## API で取った組織の現状（2026-11-05）

scoped PAT（Organization Members・Organization Projects の Read）で取った。一次情報は `~/supabase/dhazyhuzuwitqasezcvr/2026-11-05/`（git 管理外）。範囲外の `GET /v1/projects` は 403 になり、権限が絞れていることも確かめた。

メンバー（20 名。全員 turing-motors.com のメール）:

| ロール | 人数 | MFA 有効 | 該当者 |
|---|---|---|---|
| Owner | 3 | 1 | 安本さん（MFA 無効）・山本修平さん（**MFA 有効**）・渡辺孝文さん（MFA 無効） |
| Administrator | 4 | 0 | 伊藤・犬塚さん・塚本さん・徳地さん |
| Developer | 13 | 0 | （一覧は一次情報を参照） |

- MFA が有効なのは 20 名中 1 名だけ。SSO のユーザー（`is_sso_user`）は 0 名。プロジェクト単位のロールの人はいない（全員が組織全体のロール）。
- `username` がメールでない人が 6 名いる（伊藤を含む）。GitHub でログインしている人と思われるが、API からログインの方式は分からない（推測）。
- 退職者が残っているかは、下の「名簿との突き合わせ」で確かめた（残っていない）。
- MFA の強制を有効にできるのは、Owner のうち MFA を設定済みの山本さんだけ（いまの状態では）。

プロジェクト（11 件。すべて ACTIVE_HEALTHY）:

| ref | 名前 | リージョン | compute | 作成日 |
|---|---|---|---|---|
| `fdgjfmuvmiwipxsfyecw` | jadd-studio-prod | us-west-1 | medium | 2025-01-08 |
| `zlsxpcotdkwjrktfovqd` | drivers-app-dev | ap-northeast-1 | micro | 2025-04-03 |
| `kuqqkzwvpmhkajpukgkm` | drivers-app-prod | ap-northeast-1 | medium | 2025-04-17 |
| `ebdfwtvfpemzevdpxmek` | jadd-studio-dev | ap-northeast-1 | small | 2025-04-30 |
| `mmlgcgropqvvkyhnaspq` | fleet-management-dev | ap-northeast-1 | micro | 2025-08-28 |
| `tlhayuhveurzpbdiqrso` | fleet-management-prod | ap-northeast-1 | micro | 2025-09-16 |
| `lvngtemehmcxemnurgwb` | backend-prod | us-west-1 | xlarge | 2025-10-21 |
| `dxnqnvmqkckpcgbrjdkx` | backend-dev | ap-southeast-1 | micro | 2025-11-21 |
| `qgnfaidhxcuqivmgubuy` | biz-fleet-ops | ap-northeast-1 | micro | 2026-03-24 |
| `lzafrhdmhmvhqgclggbc` | corp-turing-seat-map | ap-northeast-1 | nano | 2026-03-27 |
| `getreuxrgoowoenjghil` | web-ivi-storybook | ap-northeast-1 | micro | 2026-08-06 |

リポジトリとの突き合わせ:

- リポジトリで見つけた 6 件のうち 5 件はこの組織にある。`seacktbfnjusvroguhwc`（旧 tuscenes）はこの組織に無い。消したのか、ほかの組織にあるのかは未確認。
- 組織にあってリポジトリで見つからなかったもの: drivers-app-prod・fleet-management-dev/prod・backend-dev・corp-turing-seat-map・web-ivi-storybook（マウントしていないリポジトリで使っている可能性がある）。

### 名簿との突き合わせ（2026-11-05）

在籍の正本は identity リポの `platform/okta/users.tf`（SmartHR から同期。origin/main の `da61de2` を読んだ）。開発者の名簿は jadd_studio3 の `docs/workstream/feature-contributors.md` の「貢献者名簿」（git にコミットした 23 名。在籍しているかは書かれていない）。個人ごとの表は `~/supabase/dhazyhuzuwitqasezcvr/2026-11-05/roster-check.md`（git 管理外）。

- **退職者は残っていない**。20 名とも Okta で ACTIVE で、DEPROVISIONED（8 名）との重なりは無い。Google Workspace とメールの台帳にも全員いる。
- 雇用形態は、正社員 18 名・執行役員 1 名・業務委託 1 名（Developer）。
- Supabase にいて、STUDIO の開発者名簿にいない人が 8 名いる（Owner 1・Administrator 1・Developer 6）。総務チームや事業開発部の人も含まれる。STUDIO 以外のプロジェクト（drivers-app・fleet-management・corp-turing-seat-map など）を使っている可能性があるので、要らないとは言えない。本人か所属のチームに使い道を確かめる。
- 逆に、STUDIO の開発者名簿にいて Supabase にいない人が 11 名いる（全員在籍）。Supabase を直接触らずに開発できている、ということ。
- 判断の材料: Administrator の徳地さん（執行役員・事業開発部）と、Developer の業務委託 1 名は、ロールが要るかを確かめる候補。

## 完了時の確認（2026-11-05）

伊藤から: MFA の必須化を有効にし、A・B の全員に一斉にアナウンスした。あとは、不要と連絡があった人を外すだけ。MFA の設定はログインのときに求められるので、こちらからのフォローは要らない。これで完了とする。

API で取り直した結果（一次情報は `~/supabase/dhazyhuzuwitqasezcvr/2026-11-05-after/`）:

- メンバーは 20 名 → 16 名。外れたのは C の 1 名、B の 1 名、A の 2 名（区分の後に外すと決めたと思われる。個人ごとは見直しリスト）。
- B のうち 3 名はメンバーに残っている。
- MFA を設定済みなのは 16 名中 2 名（山本さん・伊藤）。残りの 14 名は、次のログインで MFA の設定を求められる。
- MFA の必須化がオンになっていることは、API では確かめていない（調査用の PAT に組織の設定を読む権限を付けていないため）。

## 設計判断と理由

- 一次情報（メンバー一覧など。メールアドレスを含む）は git で管理せず、`~/supabase/dhazyhuzuwitqasezcvr/` に置く。aws-resource-inventory と同じ扱い。
- **SSO は導入しない**（2026-11-05 決定）。Team プランへの格上げ（+$574/月）が要るため。
- **組織で MFA を必須にする**（2026-11-05 決定）。Pro のままできる。設定できるのは MFA を設定済みの Owner だけなので、山本さんに頼む。
- **もうアクセスの要らない人を組織から外す**（2026-11-05 決定）。全員の在籍は確かめたので、一人ずつ聞いて決める。Administrator と Developer は伊藤が外す。Owner の変更は Owner に頼む。

## アクションプラン

`<...>` の日付は伊藤が決める。依頼文の下書きは [supabase-accounts/requests.md](supabase-accounts/requests.md)。

| # | やること | 誰が | いつまで |
|---|---|---|---|
| 1 | 日程を決める（ヒアリングの回答期限・MFA 必須化の日。間は 2 週間ほど） | 伊藤 | |
| 2 | 山本さんに依頼する（MFA の必須化、Owner 2 名への声かけ） | 伊藤 → 山本さん | |
| 3 | メンバーを A（要る・MFA を頼む）15 名・B（要らなそう・聞く）4 名・C（要らないと確認済み）1 名に分ける | 伊藤 | 済（2026-11-05） |
| 4 | C の 1 名を外す | 伊藤 | すぐ |
| 5 | A に MFA の予告（1-A）、B にヒアリング（1-B）を送る | 伊藤 | |
| 6 | B の回答をもとに外す。返事が無い人は、もう一度声をかけてから外す | 伊藤 | 回答期限の後 |
| 7 | Owner の変更が要れば、山本さんに頼む | 伊藤 → 山本さん | |
| 8 | 必須化の前日に API で `mfa_enabled` を取り、未設定の人に声をかけ、一覧を山本さんに送る | エージェント・伊藤 | 必須化の前日 |
| 9 | MFA を必須にする | 山本さん | 必須化の日 |
| 10 | API で確かめる（全員が MFA 有効か、外した人がいないか）。結果をここに書く | エージェント | 必須化の後 |
| 11 | 調査用の PAT を失効させる | 伊藤 | 10 の後 |

注意:

- 必須化しても、Personal Access Token（PAT）は止まらない。他人の PAT は API で一覧できないので、各自に使っていないものを消してもらう（依頼文に入れた）。
- 外した人は、組織のプロジェクトのダッシュボードに入れなくなるだけで、アプリへのログイン（Supabase Auth）には影響しない。
- SSO を入れないので、退職したときに自動では外れない。再発防止として、退職の手順（identity リポの退職の PR）に Supabase を足すか、定期的に名簿と突き合わせるかを、後で決める（未決）。

## 進捗チェックリスト

- [x] 現状を聞き取る（Owner 3 名・Pro・MFA ほぼ無効）
- [x] リポジトリから参照されているプロジェクトを洗い出す（6 件）
- [x] SSO・MFA 強制・ロール・監査ログの提供条件を調べる
- [x] scoped PAT を作り、メンバー一覧（ロール・MFA）とプロジェクト一覧を API で取る（20 名・11 件）
- [x] リポジトリのプロジェクトと組織のプロジェクトを突き合わせる（旧 tuscenes がこの組織に無い）
- [x] 在籍者の名簿（Okta）と STUDIO の開発者名簿と突き合わせる（退職者なし。名簿外 8 名）
- [x] 20 名の見直しリストを作る（`~/supabase/dhazyhuzuwitqasezcvr/2026-11-05/review-list.md`。所属・MFA・Supabase を使うリポジトリでの最終コミット日）
- [x] 方針を決める（SSO は見送り、MFA を必須化、使っていない人を外す）
- [x] アクションプランと依頼文の下書きを作る
- [x] メンバーを A/B/C に分ける（A 15・B 4・C 1）
- [x] C を外し、MFA を必須にして、アナウンスする（2026-11-05）
- [x] API で結果を確かめる（16 名、MFA 設定済み 2 名）
- [ ] ロールの見直しの案（Administrator 4 名・Developer 13 名が妥当か）
- [ ] 退職者・不明なアカウント・強すぎる権限を掃除の候補にする
- [x] SSO のためのプラン（Team）の料金を調べる（差額 $574/月。未確認の点は営業に問い合わせ）
- [ ] 再発防止（退職したときに外す仕組み）を決める

## 次セッションへの引き継ぎ

完了した（2026-11-05）。方針は [documents/supabase-org-account-policy.md](../../documents/supabase-org-account-policy.md) に書き出した。残っているもの（この案件では扱わない）:

- B のうち、メンバーに残っている 3 名: 不要と連絡があり次第、伊藤が外す
- 再発防止（退職したときに組織から外す仕組み）
- 旧 tuscenes（`seacktbfnjusvroguhwc`）の所在
- 後日、全員が MFA を設定したかを確かめる（伊藤が依頼する）。調査用の PAT（`~/.config/supabase/pat`）は 7 日間有効（2026-11-05 作成なので 2026-11-12 ごろまで）。`GET /v2/organizations/dhazyhuzuwitqasezcvr/members` をページ送りで取り、`mfa_enabled` が false の人と、B の 3 名が外れたかを見る。期限が切れていたら、同じ権限（Organization Members と Organization Projects の Read）で作り直す
- 確かめたら、PAT を失効させ、ファイルを消す（伊藤）

## 関連リンク

- [project:privileged-access](../../../privileged-access/README.md): 組織の Owner は権限の頂点の地図（privilege-map.md）に反映する
- [project:idp-broker](../../../idp-broker/README.md): 社内アプリを使う人の認証の入口の選定（この案件は社員が Supabase そのものに入るためのアカウントで、別物）
