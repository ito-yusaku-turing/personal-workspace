# Postgres に直接つなぐ経路を守る施策の調査

- 調べた日: 2026-11-20（エージェントが Web で調べた。主な点は公式の文書の原文で確かめた）
- 所属: [../supabase-db-access.md](../supabase-db-access.md)

マネージド Postgres への直接の接続（psql・アプリ・CI）を守る一般的な施策と、それが Supabase（Pro）で使えるかの調べ。方針はまだ決めていない。考察は末尾の「考察」。

## 要点

- **Supabase に Temporary access（JIT アクセス）が加わっている**（2026-05-25 に機能プレビューとして発表）。人は DB のパスワードの代わりに本人の PAT で Postgres に入る。メンバーごとに使えるロール・期限・接続元の CIDR を割り当て、メンバーから外せば入れなくなる。
- **ただし JIT を入れても、ロールのパスワードでの接続は残る**。公式の文書の原文: "The role's own password keeps working … A team member who knows the role's password can connect with it after you remove their mapping. To end that access, change the role's password."（[team-database-access](https://supabase.com/docs/guides/platform/team-database-access)、2026-11-20 に原文で確認）
- そのため、いま空いている穴（外した人・MFA の無い人がパスワードで入れる）を塞ぐのは、**`postgres` のパスワードを変えて、人に配らないこと**だけ。ほかの施策は、それを続けられるようにするための支え。
- **共有の pooler（Supavisor）経由の接続は、Postgres のログに pooler の IP しか残らない**。接続ログ（`log_connections`）は新しいプロジェクトでは既定で無効。

## 1. 業界の定石（ベンダーに依らない）

| 施策 | 何を守るか | 手間 | 費用感 | 小さなチームへの向き |
|---|---|---|---|---|
| ネットワークで隔離する（IP 許可リスト・踏み台・VPN） | パスワードが漏れても、決めた経路の外からは入れない | 低〜中 | 踏み台・VPN の維持費 | ◎ 最初の一手 |
| IdP 連携の一時トークン | 長く使えるパスワードを無くす | 中 | 無料（クラウドの機能） | ◎ ただし DB が対応している場合だけ |
| 動的クレデンシャル（Vault / OpenBao） | 要求のたびに期限付きのユーザーを作る | 高 | Vault の運用費 | △ 運用の担い手がいれば |
| アクセスプロキシ・ZTNA（Teleport・StrongDM・Cloudflare Access・Tailscale・Boundary） | IdP と MFA を経た人だけが経路に乗れる | 中 | 無料〜1人あたり月 $50 前後 | ○ |
| JIT とブレークグラス | 常に持っている権限を減らし、緊急の経路を別に持つ | 中 | 製品による | ○ |
| 最小権限のロール設計 | 読み取りと書き込みを分け、本番に書ける人を絞る | 低〜中 | 無料 | ◎ 必須 |
| 監査ログ（pgaudit・接続ログ） | 誰がいつどこから入り、何をしたかの証跡 | 低〜中 | ログの保管費 | ◎ |
| パスワードのローテーションと退職者処理 | 人が知っているパスワードを無効にする | 低（影響の範囲の把握が要る） | 無料 | ◎ 必須 |

他社のマネージド Postgres の IdP 連携（比べるための参考）:

- AWS RDS の IAM 認証: トークンは 15 分で切れる。`rds_iam` を付けたユーザーはパスワードで入れなくなる（[AWS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)）。
- GCP Cloud SQL の IAM 認証: OAuth のトークン（1 時間）。グループで管理できる（[Google](https://docs.cloud.google.com/sql/docs/postgres/iam-authentication)）。
- Azure の Entra 認証: パスワード認証を無効にできる。消したユーザーも、発行済みのトークンが切れるまで（最大 60 分）は入れる（[Microsoft](https://learn.microsoft.com/en-us/azure/postgresql/security/security-entra-concepts)）。
- **3 社とも「パスワード認証を止められる」のが要**。Supabase の JIT は、いまはパスワード認証を止められない。

製品の補足:

- Vault: `CREATE ROLE "{{name}}" WITH LOGIN PASSWORD … VALID UNTIL …` で期限付きのユーザーを作る。管理用のユーザーに `CREATEROLE` が要る（[HashiCorp](https://developer.hashicorp.com/vault/docs/secrets/databases/postgresql)）。
- Teleport: DB 側の証明書認証（pg_hba）を前提にする（[Teleport](https://goteleport.com/docs/enroll-resources/database-access/enroll-self-hosted-databases/postgres-self-hosted)）。Supabase の利用者は pg_hba を変えられないので、そのままは使えない（推測）。
- Cloudflare Access: DB の手前に cloudflared を置き、利用者は `cloudflared access tcp` でブラウザの IdP ログインを経てつなぐ（[Cloudflare](https://developers.cloudflare.com/access/other-protocols/tcp-guide)）。Free は 50 人未満向け。
- Tailscale: 2026-04-08 に料金体系が変わった（[ブログ](https://tailscale.com/blog/pricing-v4)）。Personal は 6 人まで無料。
- StrongDM: 1 人あたり月 $50・最低 20 人という情報がある（第三者のサイト。公式の価格表は非公開）。

## 2. Supabase で使えるもの

### Temporary access（JIT）

- 出典: [Temporary access](https://supabase.com/docs/guides/platform/temporary-access)、[Map team members to Postgres roles](https://supabase.com/docs/guides/platform/team-database-access)、[Changelog 2026-05-25](https://supabase.com/changelog/46346-feature-preview-temporary-token-based-database-access)
- 条件: SSL Enforcement が有効、Postgres 17.6.1.081 以上（原文で確認）。既定で無効。ダッシュボードか `PUT /v1/projects/{ref}/jit-access` で有効にする。
- 割り当て: `PUT /v1/projects/{ref}/database/jit` で、メンバーごとにロール・`expires_at`・`allowed_cidrs`（IPv4 / IPv6）を付ける。DB に新しいロールは作らない。
- つなぎ方: 接続文字列のパスワードを PAT（`sbp_…`）に置き換える。直接接続と共有の pooler で使える（pooler では `options=-c jit=true`）。専用の pooler（PgBouncer）では使えない。
- 期限は数分〜90 日。
- **注意**: PAT は MFA の必須化の対象外（[MFA enforcement](https://supabase.com/docs/guides/platform/mfa/org-mfa-enforcement)）。MFA を設定したアカウントでは PAT の発行に MFA を経たセッションが要るが、必須化の前に MFA 無しで発行した PAT は生きている可能性がある（推測）。
- 未確認: Pro で使えるか（文書にプランの制限の記述が無い）、プレビューのいまの状態、外したメンバーの PAT そのものが失効するか。

### ロール

- `postgres` はスーパーユーザーではない。`supabase_admin` は Supabase の内部用（[roles-superuser](https://supabase.com/docs/guides/database/postgres/roles-superuser)、[roles](https://supabase.com/docs/guides/database/postgres/roles)）。
- ログインできるロールは作れる。公式はサービスごとに分けることを勧めている。共有の pooler では、ユーザー名を `<role>.<project-ref>` にする（[connecting-to-postgres](https://supabase.com/docs/guides/database/connecting-to-postgres)）。
- `postgres` に `CREATEROLE` があるかは文書に無い。`select rolcreaterole from pg_roles where rolname='postgres'` で確かめる。
- CLI の一時ロール: `POST /v1/projects/{ref}/cli/login-role` で、`read_only` と TTL 付きのロールを作れる（ベータ）（[API](https://supabase.com/docs/reference/api/v1-create-login-role)）。

### 監査ログ

- pgaudit は使える。設定はロール単位だけ（`alter role … set pgaudit.log`）（[pgaudit](https://supabase.com/docs/guides/database/extensions/pgaudit)）。
- 接続ログ（`log_connections`）は新しいプロジェクトでは既定で無効。Database Settings か `PUT …/config/database/postgres` で有効にする（[connection logging](https://supabase.com/docs/guides/platform/postgres-connection-logging)）。
- ログには `user_name`（ロール）と `connection_from`（IP）が出る。**共有の pooler 経由だと pooler の IP になる**（[KB](https://supabase.com/docs/guides/troubleshooting/how-to-interpret-and-explore-the-postgres-logs-OuCIOj.md)）。
- 保持は Pro で 7 日（Team 28 日）。Log Drain は 1 本あたり月 $60 から。Platform Audit Logs は Team 以上（[pricing](https://supabase.com/pricing)、2026-11-20 に見た）。

### パスワードの変更

- ダッシュボードで変えても止まらない。Supabase 内部のサービス（PostgREST・専用の pooler など）は自動で追従する。**外部のアプリや CI に書いたパスワードは手で直す**（[roles](https://supabase.com/docs/guides/database/postgres/roles)）。
- 共有の pooler はパスワードをしばらくキャッシュする。変えた直後は `28P01` で失敗することがある（多くは約 15 秒で直る）。古いパスワードで繰り返しつなぐと Circuit breaker が開く。
- 公式が勧める無停止の手順: 新しいロールを並べて作り、クライアントを順に移してから古いロールを消す（[KB](https://supabase.com/docs/guides/troubleshooting/supavisor-error-password-authentication-failed-after-password-rotation)）。

### Network Restrictions の補足

- 直接接続が IPv6 に解決される場合は、IPv4 と IPv6 の両方を登録する（IPv4 アドオンを使うなら IPv4 だけでよい）（[network-restrictions](https://supabase.com/docs/guides/platform/network-restrictions)）。
- Supavisor は 2024-01-24 から Network Restrictions を守る（[changelog](https://supabase.com/changelog/20522-supavisor-starts-enforcing-network-restrictions)）。
- 登録できる件数の上限、Read replica に効くかは未確認。
- IPv4 アドオンは 1 時間 $0.0055（月 約 $4）（[ipv4](https://supabase.com/docs/guides/platform/manage-your-usage/ipv4)）。

## 3. アプリ・CI からの接続

- GitHub Actions: 標準のランナーは IP が固定でない。larger runner の静的な IP は **GitHub Enterprise Cloud が要る**（[GitHub](https://docs.github.com/en/actions/reference/runners/larger-runners)）。代わりは固定 IP の self-hosted runner。
- Vercel: Static IPs は Pro 以上で **1 プロジェクトあたり月 $100** と転送量（[Vercel](https://vercel.com/docs/networking/static-ips)）。IP は共有のプールから。
- Vercel と GitHub Actions は IPv4 だけ。直接接続には Supabase の IPv4 アドオンが要り、そうでなければ共有の pooler を使う（[ipv4-address](https://supabase.com/docs/guides/platform/ipv4-address)）。
- AWS: NAT Gateway の EIP で出口を固定できる（us-east-1 で 1 時間 $0.045 + 1GB $0.045）（[AWS](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html)）。
- OIDC: Supabase が GitHub の OIDC のトークンを受け取れる、という文書は見つからなかった（未確認、おそらく未対応）。代わりに、AWS の OIDC で Secrets Manager から DB のパスワードを取る形はとれる。
- ロールを接続ごとに分けると、`pg_stat_statements` やログの `user_name` でどのサービスか見分けられる。

## 4. Supabase Pro で取れる選択肢の比べ

| 選択肢 | 効果 | 手間 | 副作用・注意 |
|---|---|---|---|
| A. `postgres` のパスワードを変え、人に配らない | いまの穴を直接塞ぐ | 低〜中（使っている箇所の洗い出しが要る） | パスワードを書いたアプリ・CI が止まる。新しいロールへ順に移すと安全 |
| B. 人は JIT で入る | 入るのに本人の PAT が要る。期限・CIDR・メンバーからの削除で止まる | 中（PG のアップグレード、SSL の強制） | プレビュー。PAT は MFA の必須化の対象外。Pro で使えるか未確認。A が無いと効かない |
| C. 用途ごとのロール（アプリ用・マイグレーション用・読み取り専用） | 漏れたときの被害を絞る。ログで追える | 中 | 権限の設計。`supabase_admin` が付けたデフォルト権限は変えられない |
| D. Network Restrictions で出口の IP を絞る | パスワードが漏れても決めた場所からしか入れない | 低（出口の固定が難しい） | Vercel は月 $100、GitHub は Enterprise Cloud。Edge Functions から直接つなげなくなる |
| E. 固定 IP の踏み台・ZTNA を通し、その IP だけ許可 | IdP と MFA を経た人だけが届く | 中（ホストの運用） | ホストが落ちると入れない。DB からは全員が同じ IP に見える |
| F. 接続ログと pgaudit、Log Drain | 事後の検知・調査 | 低 | Pro の保持は 7 日。Log Drain は月 $60 から。pooler 経由は IP が分からない |
| G. Vault / OpenBao の動的クレデンシャル | 期限付きのユーザーの自動の作成と削除 | 高 | Supabase での事例が見つからない。運用が重い |
| H. Team プランへ上げる | PrivateLink・Platform Audit Logs・ログ 28 日・SSO | 低（契約） | 月 $599 から |

## 考察

エージェントの考察（2026-11-20）。[db-routes.md](./db-routes.md)（リポジトリからの洗い出し）とあわせて考えた。まだ決めていない。

### 守りを 4 つの層に分けて考える

| 層 | 問い | いまの状態 |
|---|---|---|
| 資格（誰が） | パスワードを知っているのは誰か | `postgres` のパスワードを人も CI もアプリも共有している。外した人も知っているかもしれない。drivers-app-dev はリポジトリに入っている |
| 経路（どこから） | どこからなら入れるか | どこからでも入れる。接続元の IP はほとんど固定でない |
| 権限（何を） | 入ったら何ができるか | ほとんどが `postgres` なので、何でもできる |
| 記録（何をしたか） | 後で追えるか | 接続ログは既定で無効（各プロジェクトの設定は未確認）。保持は 7 日 |

**いま空いている穴を塞げるのは「資格」の層だけ**。つまり、パスワードを変えること。経路を絞っても、許可した場所（社内・CI）にいる元メンバーは入れる。権限を分けても、`postgres` のパスワードを知っている人には効かない。

### 考えたこと

1. **パスワードを変えるだけでは続かない**。いまは `postgres` のパスワードを人・CI・Lambda・Vercel・Databricks が共有している。変えると全部を直す必要があり、直した先でまた人が知ることになる。先に**用途ごとのロールに分けて**（選択肢 C）、`postgres` を「誰も普段は使わない」状態にしてから変える（選択肢 A）と、次からは人が外れたときに変えるロールが絞れる。公式が勧める無停止の手順（新しいロールを並べて作り、順に移してから古いものを消す）とも合う。
2. **人のアクセスは、パスワードを持たせない方向**にする。手段の候補は 3 つ。
   - ダッシュボードの SQL Editor（MFA を経る）。jadd_studio3 の DDL のパッチや、drivers-app3 の本番への psql は、まずこれに寄せられるか確かめる。
   - CI でのマイグレーション（mono-e2e の Alembic、fleet-ops の Supabase の GitHub 連携）。人が本番に流す経路を減らせる。
   - Temporary access（JIT）。向きは正しいが、プレビューで、PAT には MFA の必須化が効かない。Pro で使えるかも未確認。まず dev のプロジェクトで試すのがよい。
3. **Network Restrictions は、いまは全体には入れにくい**。backend-prod は GitHub のホストランナー・VPC の無い Lambda・Databricks からつながっていて、出口を固定するには構成の変更（VPC と NAT）か費用（Vercel の Static IPs は 1 プロジェクトあたり月 $100、GitHub は Enterprise Cloud が要る）がかかる。直接の経路が無いか少ないプロジェクト（fleet-management-*、corp-turing-seat-map、web-ivi-storybook）から入れるのが現実的。ただし Edge Functions から DB に直接つないでいないかを先に確かめる。
4. **まず見えるようにする**。接続ログを有効にすると、リポジトリからは分からない経路（Vercel・Databricks・手元のスクリプト・元メンバー）が見える。副作用が小さく、ロールを分けたあとの確かめにも使える。ただし共有の pooler 経由では接続元の IP が残らないので、ロールを分けるのとあわせて効く。設定の変更なので、担当の人の合意を取ってから入れる。
5. **Team プランへ上げる（PrivateLink など）のは、いまは要らない**。資格の層を直さないかぎり、閉じた経路にしても元メンバーの問題は残る。
6. **drivers-app-dev のパスワードは、ほかと切り離して先に手当てできる**。dev だがリポジトリに入っていて、全開発者が共有している。drivers-app-mono の ADR 0047 で未決（u-75）なので、drivers-app の担当の人と相談する。

### 進め方の案（まだ決めていない）

1. drivers-app-dev のパスワードの件を、drivers-app の担当の人に伝える。
2. 把握の残り: 各プロジェクトの設定（Network Restrictions・SSL Enforcement・`log_connections`・Postgres のバージョン）、LOGIN を持つロールの一覧、Databricks の Connection、Vercel の環境変数の接続先。
3. 接続ログを有効にして、実際の経路を 1〜2 週間見る（合意を取ってから）。
4. 経路ごとに専用のロールを作って移す（backend-prod の CI・Lambda・Databricks、fleet-ops、drivers-app など）。
5. `postgres` のパスワードを変え、ブレークグラス用として保管する（置き場所と、出せる人を決める）。
6. 人の手順を SQL Editor・CI・JIT に寄せる。
7. 出口を固定できるプロジェクトから Network Restrictions を入れる。
