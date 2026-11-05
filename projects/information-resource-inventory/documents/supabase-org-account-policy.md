# Supabase の組織のアカウントの方針

- 決めた日: 2026-11-05（伊藤）
- 経緯: [workstream/done/supabase-accounts.md](../workstream/done/supabase-accounts.md)

Supabase の組織 `dhazyhuzuwitqasezcvr`（会社契約の Pro）の、ダッシュボードに入る人のアカウントの扱い。アプリの利用者のログイン（Supabase Auth）は対象外。

## 決めたこと

- **SSO は入れない**。ダッシュボードへの SSO は Team プラン以上で、Pro からの差額は $574/月かかるため。
- **組織で MFA を必須にする**（Require MFA to access organization）。2026-11-05 に山本さん（Owner）が有効にした。
- **アクセスの要らない人は組織から外す**。外してもアプリへのログインには影響しない。必要になったら、また招待する。

## 運用で知っておくこと

- MFA の必須化を変えられるのは、MFA を設定している Owner だけ。Administrator は Administrator と Developer の追加・削除ができるが、Owner は変えられない。
- MFA を設定していないメンバーは、組織のプロジェクトを開けない（メンバーからは外れない。設定すれば戻る）。設定はログインのときに求められるので、個別にフォローしなくてよい。
- 不要になった人は、本人から連絡があったときに外す（Administrator・Developer は Administrator でも外せる）。
- Supabase の MFA にはリカバリーコードが無い。認証アプリを 2 つの端末に登録しておく。
- Personal Access Token は MFA の必須化の対象外。他人の PAT は API で一覧できない。
- SSO が無いので、退職しても組織から自動では外れない。
- 棚卸しは、scoped PAT（Organization Members と Organization Projects の Read だけ）で `GET /v2/organizations/{slug}/members`（`mfa_enabled` が返る）と `GET /v2/organizations/{slug}/projects` を呼べばできる。メンバーの在籍は identity リポの `platform/okta/users.tf` と突き合わせる。
