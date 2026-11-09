# Supabase の DB への接続経路の把握とセキュリティ強化

- 開始: 2026-11-09
- 状態: **起票した**（2026-11-09）。次は、各プロジェクトの Network Restrictions・SSL Enforcement の設定と、DB に直接つないでいる経路を洗い出す
- 所属: project:information-resource-inventory
- 派生元: [vercel-accounts.md](./vercel-accounts.md)（Vercel・Supabase の MFA の必須化の作業）。Supabase のアカウントの棚卸しは [done/supabase-accounts.md](./done/supabase-accounts.md)

Supabase の組織（`dhazyhuzuwitqasezcvr`、Pro）の各プロジェクトについて、Postgres に直接つなぐ経路（psql・アプリ・CI など）を洗い出し、公式の手段で守りを固める。

## 背景・目的

- ダッシュボードには MFA を必須にした（2026-11-05）。しかし、**Postgres のプロトコル（psql など）で直接つなぐ経路は、DB のパスワードだけで入れる**。MFA も組織のメンバーであることも求められない。
- そのため、組織から外した人や MFA を設定していない人でも、DB のパスワードを知っていれば DB に入れる。
- 目的は 2 つ。
  - **把握**: どのプロジェクトに、誰が・何が・どこから・どのロールでつないでいるかを知る。
  - **強化**: 公式の手段で接続元とパスワードの扱いを固める。

## 公式の手段（2026-11-09 に公式ドキュメントで確認）

**psql での接続を人ごとの MFA や SSO に結びつける公式の仕組みは無い。** 認証は、どの経路でも Postgres のロールのパスワードで行う。

| 手段 | 内容 | 条件 |
|---|---|---|
| [Network Restrictions](https://supabase.com/docs/guides/platform/network-restrictions) | DB に接続できる IP を許可リストで絞る（IPv4・IPv6）。直接の接続にも pooler にも効き、パスワードを確かめる前に弾く。HTTPS の API（PostgREST・Storage・Auth）と supabase-js には効かない。制限をかけると、Edge Functions からは DB に直接つなげなくなる | Owner か Admin が設定する（**伊藤は Administrator なので設定できる**）。プランの制限はドキュメントに書かれていない |
| [PrivateLink](https://supabase.com/docs/guides/platform/privatelink) | AWS の VPC から VPC Lattice を通して閉じた経路で DB に接続する（5432・6543）。そのうえで「Restrict all access」をオンにすると、インターネットからの接続をすべて止められる | **Team / Enterprise プランだけ**。VPC は同じリージョンにあること |
| [SSL Enforcement](https://supabase.com/docs/guides/platform/ssl-enforcement) | SSL を使わない接続を拒む（Postgres・Supavisor・専用の pooler）。設定すると DB が短時間再起動する | Owner か Admin が設定する |
| [ロールを分ける](https://supabase.com/docs/guides/database/postgres/roles) | サービスごとに別の Postgres ロールを作るよう公式が勧めている（`pg_stat_statements` で区別できる） | パスワードの定期的な変更の手順は書かれていない |
| CLI の一時ロール | DB のパスワードを渡さずに CLI を使うと、数百秒で切れる一時ロール `cli_login_postgres`（`postgres` のメンバー）が作られる（[KB](https://supabase.com/kb/troubleshooting/permission-denied-when-deleting-the-cli_login_postgres-role-808bae)） | 認証は Supabase のアカウント側で行う。PAT でも作れるので、MFA を経たことの保証にはならない |

公式の [Production checklist](https://supabase.com/docs/guides/security/production-checklist) が DB について勧めているのは、RLS・SSL Enforcement・Network Restrictions の 3 つ。

## 設計判断と理由

（まだ無い）

案（エージェントの提案。まだ決めていない）:

1. Network Restrictions で、接続元を決まった IP（CI・踏み台・オフィスなど）に絞る。
2. 人は DB のパスワードを持たず、ダッシュボードの SQL Editor（MFA を経る）か CLI を使う。
3. `postgres` のパスワードは、メンバーを外すたびに変える。アプリには専用のロールを使う。
4. 閉じた経路が要るなら PrivateLink。ただし Team プランへの変更が要る。

## 進捗チェックリスト

- [x] 公式の手段を調べる（2026-11-09）
- [ ] 組織のプロジェクトを API で取り直す（前回の一覧は [done/supabase-accounts.md](./done/supabase-accounts.md)）
- [ ] 各プロジェクトの Network Restrictions・SSL Enforcement の設定を取る（Management API の `network-restrictions`・`ssl-enforcement`。手元の PAT で読めるかは未確認）
- [ ] DB に直接つないでいる経路をリポジトリから洗い出す（接続文字列・`DATABASE_URL`・`SUPABASE_DB_PASSWORD`・`5432` / `6543`・GitHub の secrets）
- [ ] 経路ごとに、接続元の IP（固定か）・ロール・パスワードの持ち主を表にする
- [ ] DB のパスワードを知っている人・置いてある所を把握する（外した人が知っていたか）
- [ ] 方針を決める（Network Restrictions の許可リスト、パスワードの変更、ロールの分け方）
- [ ] 担当の人と合意を取ってから設定する
- [ ] 設定の結果を API で確かめ、[documents/supabase-org-account-policy.md](../documents/supabase-org-account-policy.md) に運用として書き出す

## 次セッションへの引き継ぎ

- 起票しただけ。まず「把握」から始める。
- 調査用の Supabase の PAT（`~/.config/supabase/pat`）は 2026-11-12 ごろに切れる。組織の設定を読む権限を付けていないので、プロジェクトの設定が読めるかを最初に試す。GET だけを送る。
- Network Restrictions を入れると、許可していない所からの接続はすぐに切られる。Edge Functions や、IP が固定でない CI・開発者の手元が止まるおそれがある。経路を把握し終えるまで設定は変えない。
- Pro のままでは PrivateLink は使えない。

## 関連リンク

- [vercel-accounts.md](./vercel-accounts.md): 派生元。Vercel・Supabase の MFA の必須化
- [done/supabase-accounts.md](./done/supabase-accounts.md): Supabase のアカウントの棚卸し（プロジェクトの一覧、PAT は MFA の強制の対象外であること）
- [documents/supabase-org-account-policy.md](../documents/supabase-org-account-policy.md): Supabase の組織のアカウントの方針
