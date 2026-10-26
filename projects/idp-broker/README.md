# project:idp-broker 目録

協力会社の人にも社内アプリ（まず JADD STUDIO）を使わせるため、社内アプリの認証の入口となる IdP（ブローカー）を選び、Okta・Google Workspace・ブローカーの役割分担と、backend-api・JADD STUDIO・jadd-cli の認証・認可の持ち場を検討する案件。関連するリポジトリは identity（`/usr/app/identity`）・jadd_studio3・mono-e2e・cdk-apps。

2026-10-26 に `~/docs/workstream/` から移した。ファイルを追加・移動・削除したら、この目録も同じコミットで更新する（ルールは personal-workspace の `AGENTS.md`「projects/（案件ごとの資料）」）。

関連する project: [project:m2m-auth](../m2m-auth/README.md)（機械の認証）、[project:tern-ios-auth](../tern-ios-auth/README.md)（Tern iOS アプリの認証）

## workstream/ — 進行中の作業記録

- [workstream/idp-auth0-role-division.md](./workstream/idp-auth0-role-division.md): **IdP の役割分担の検討（Okta / Google Workspace / Auth0）**。作業記録の本体。推奨案（ブローカーを社内アプリ共通の入口にする）、協力会社を入れる構想、ブローカー候補の比較、backend-api と jadd-cli の認証の検討メモ

## documents/ — 報告書・議論用の資料

- [documents/idp-broker-report.md](./documents/idp-broker-report.md): **社内アプリの認証の入口となる IdP の選定**（報告書、2026-10-16）。本命 Auth0、2 番手 Zitadel Cloud、3 番手 WorkOS。決め手は identity リポと同等の IaC ができるか
- [documents/backend-api-auth-supplement.md](./documents/backend-api-auth-supplement.md): **ブローカー 3 候補と、backend-api・JADD STUDIO・CLI の認証**（補足資料、2026-10-16）。Supabase のトークンをブローカーのトークンに置き換えたとき、3 つの経路が成り立つかを候補ごとに示す
- [documents/where-to-solve.md](./documents/where-to-solve.md): **どの問題を、どこで解くか**（チームの議論用、2026-10-16）。決まった置き場所と、置き場所を決めるときの問い
- [documents/authn-authz-issue-map.md](./documents/authn-authz-issue-map.md): **認証・認可の課題の地図**（2026-10-19）。上の資料に散っていた課題を「認証 / 認可 × エンドポイント」の 1 枚にまとめたもの
