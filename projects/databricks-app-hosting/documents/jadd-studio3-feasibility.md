# JADD STUDIO 3 を Databricks に移したとき、機能をどこまで保てるか

- 調べた日: 2026-11-10
- 対象: jadd_studio3 の `origin/main`（`b034efdd`、2026-11-10）。Databricks の公式ドキュメント（2026-11-10 時点）
- 前提: オレゴン（us-west-2）のいまの Workspace に置く。社内専用で作る（社外の利用者は対象外）

## 結論

- **画面と Databricks のデータを読む機能は、ほぼそのまま動く見込み**。いまでも重いデータは Databricks SQL から読んでいる（リポジトリ 158 個）。アプリのサービスプリンシパルに置き換えれば、むしろ素直になる。
- **一番の山は Supabase の DB ではなく、backend-api を呼ぶための鍵**。STUDIO は、ログインした人の Supabase のアクセストークンを、backend-api（BFF）への Bearer の資格情報にしている。Databricks の SSO に替えると、このトークンが手に入らない。backend-api を使う機能（ナビルート・ホイールベース校正・mc-calib・実験・3DGS・レーンの GT など、app 側で 32 ファイル）が止まる。手当てには cdk-apps（BFF）側の変更か、Supabase のログインを残すかが要る。
- **Supabase の DB は、まるごとは捨てられない**。backend と drivers-app の DB はほかのチームのもので、STUDIO は読みに行くだけ（移せない）。STUDIO 自身の DB（jadd-studio）を Lakebase に移すかは選べる。ただし、supabase-js をそのまま Lakebase に向けて動くかは確かめられていない。
- 小さな手直しで済むもの: cron（5 本）、Tern の AWS の資格情報（Vercel の OIDC）、Node 24→22、ビルドの依存、利用者の IP の取り方、URL の変更。
- 失うもの: メールとパスワードのログイン（社内専用なので使わない）と、独自のドメイン（Databricks Apps に機能が見当たらない）。
- **お試しの勧め**: 第一段階は「ホスティングだけ移す」。DB と Supabase Auth は Supabase に残し、Databricks の SSO の内側で、いまの Google ログインをもう一度通す。コードの変更が最も少なく、backend-api も動いたまま試せる。利用者は 2 回ログインすることになる。DB の移設と認証の作り直しは、その結果を見てから決める。

## いまの作り（2026-11-10 にコードで確認）

| 層 | いま | 件数・規模 |
|---|---|---|
| ホスティング | Vercel（関数は東京 `hnd1`）。Next.js 16、Node 24.22.1 に固定 | ページ 160、API ルート 442 |
| ログイン | Google: Supabase Auth（OAuth）→ STUDIO が独自のセッションを発行する。メール+パスワード+TOTP: STUDIO の中で完結 | セッションの正本は jadd-studio DB の `studio_auth.session` |
| STUDIO 自身の DB | Supabase jadd-studio（東京）。**supabase-js（PostgREST）を service role で使う**。Prisma は型の生成だけ | リポジトリ 48、表 40、`.from()` 509 箇所（3 つの DB の合計）、RPC 25 本、パッチ 61 本 |
| ほかのチームの DB | Supabase backend（mono-e2e が正本）・drivers-app（drivers-app3 が正本）を PostgREST で読む。backend は 3DGS の 2 か所だけ書く | リポジトリ 14 + 4 |
| backend-api | BFF（API Gateway + Lambda のオーソライザー）経由。**ログインした人の Supabase のトークンを Bearer で送る** | app/lib で 32 ファイル |
| Databricks | `@databricks/sql`（PAT か OAuth の M2M）、Vector Search | リポジトリ 158 |
| AWS | S3（既定の資格情報の連鎖＝環境変数の鍵）、CloudFront の署名付き URL、Tern の API と S3 は **Vercel の OIDC で IAM ロールを引き受ける** | |
| 定期実行 | Vercel Cron 5 本（文字起こし・予約の通知・セッションの掃除・退職者の同期・レーンの事前計算）。`CRON_SECRET` の Bearer で守る | |
| 外部 API | Slack・Notion・Devin・Mapbox・Google（Maps・Geocoding・Directory）・Valhalla・Teslemetry・Safie・R2 の署名・映像配信 | |

Supabase の機能のうち、使っているのは **Auth（Google OAuth、管理 API）と PostgREST だけ**。Storage と Realtime は使っていない（`.storage(` の 4 件は localStorage）。

## 機能ごとの見立て

### そのまま動く見込み（確かめは要る）

| 機能 | 理由 |
|---|---|
| 画面全般（MUI・地図・deck.gl・SignalScope など） | ブラウザで動く。サーバーは `next start` で返すだけ |
| Databricks のデータを読む機能（トリップ・評価・カバレッジなど） | `@databricks/sql` はそのまま。資格情報は、Apps が注入するサービスプリンシパル（`DATABRICKS_CLIENT_ID`/`SECRET`）に替えられる。データもアプリもオレゴンになり近くなる |
| STUDIO 自身の DB の読み書き（DB を Supabase に残す場合） | supabase-js のまま。外向きの通信で Supabase に届けばよい |
| backend と drivers-app の DB を読む機能 | 同上（service role のキーを Apps の secret に置く） |
| S3・CloudFront の署名 | 環境変数の鍵を Apps の secret から渡せば、既定の連鎖でそのまま動く |
| `next/image`・redirects・i18n・`unstable_cache`・`after()` | Node のサーバーで動く機能。キャッシュは台ごとのメモリとディスク（再起動で消える） |

### 小さな手直しが要る

| 項目 | 何が起きるか | 手当て |
|---|---|---|
| Node のバージョン | Apps は **Node 22**。STUDIO は 24.22.1 に固定 | 22 で動くか試す。24 の機能に頼っていなければ下げる |
| ビルドの依存 | Apps は `NODE_ENV=production` で入れるので、**devDependencies を入れない**。`next build` に要る `tailwindcss`・`@tailwindcss/postcss`・`typescript`、`postinstall` の `prisma generate` に要る `prisma` が devDependencies にある | dependencies に移す。ビルドは Apps の計算機（Medium なら 2 vCPU・6 GB）で走る。ビルドの時間とメモリの上限は書かれていない。いまの Vercel は Turbo のビルド機 |
| 1 ファイル 10 MB まで | git にある大きなファイルは無い。ffmpeg.wasm（32 MB）はインストールの後に `public/` に写すので、上げるファイルには入らない（見込み） | デプロイで確かめる |
| 定期実行（5 本） | Apps に cron は無い | Databricks の Jobs から `/api/` を呼ぶ（サービスプリンシパルの M2M のトークンで呼べる）。ただし、`Authorization` は Databricks のトークンに使われるので、`CRON_SECRET` の受け取り方を変える必要がありそう（未確認） |
| Tern（AWS の IAM ロール） | `@vercel/functions/oidc` で `JaddStudioTernApiRole` を引き受けている。Apps に IAM ロールを渡す仕組みは書かれていない | 期限の無い IAM ユーザーの鍵を secret に置く（後退）か、Unity Catalog の service credentials が Apps から使えるか確かめる |
| 利用者の IP | `@vercel/functions` の `ipAddress` | Apps が付ける `X-Real-Ip` に替える |
| 長く走る API（17 本、上限 120〜300 秒） | Apps の前段の時間制限は書かれていない。コミュニティでは 30〜120 秒で 504 になるという報告がある | 該当: レーンの GT の調査と事前計算、道路カバレッジの差分、ナビルートの dispatch・標高、Tern の trip-matching、シーンの指標 など。cron の 4 本は Jobs に移せば関係ない。画面から呼ぶものは、測ってから、非同期（ジョブを投げて待つ）にするか決める |
| URL が変わる | `https://<アプリ>-<workspace-id>.<リージョン>.databricksapps.com` 固定。独自のドメインは書かれていない | 共有した URL とブックマークが切れる。Vercel 側に転送を残すかを決める。`NEXT_PUBLIC_APP_URL`・OAuth の戻り先も替える |
| 外部 API の IP の許可リスト | 出口の IP が変わる。固定の IP は NCC で持てる | Safie・Teslemetry・Valhalla・映像配信などが IP で絞っているかを確かめる（未確認） |
| 距離 | 利用者は東京、アプリはオレゴン。DB を Supabase（東京）に残すと、アプリ→DB も太平洋をまたぐ（往復 100 ms 前後、測っていない） | 1 画面で DB を何度も順に呼ぶところが遅くなる。お試しで体感を測る |

### 設計の判断かほかのチームの協力が要る

#### 1. ログイン（Supabase Auth → Databricks の SSO）

- Apps は前段で社の IdP の SSO を通し、`X-Forwarded-Email`・`X-Forwarded-User` を付けて渡す。**STUDIO のロールと権限（`user` 表、10 分ごとの再検証、監査ログ）はそのまま使える**。「誰か」の決め方を、Supabase のトークンの検証からヘッダーに替えるだけで済む。
- 使う人は全員、Databricks のアカウントユーザーで、アプリに `CAN USE` が要る。
- **メールとパスワードの経路（TOTP を含む）は使わなくなる**。いまの利用者がいるかは確かめていない。
- **退職者の同期（offboarding-sync）** は、Supabase Auth に残る Google の `sub` で突き合わせている。SSO にすると `sub` が手に入らないので、作り直しが要る。Databricks の SCIM で外された人は前段で弾かれるので、要らなくなる可能性もある。
- `user.uid`（Supabase のユーザー ID）を鍵にしているところがある。backend-api に人を伝えるのにも使う（次の 2）。

#### 2. backend-api の鍵（最大の山）

BFF のオーソライザー（[cdk-apps の `supabase-authorizer-v3.ts`](https://github.com/turingmotors/cdk-apps/blob/main/apps/bff/lib/functions/supabase-authorizer-v3.ts)）が受け付けるのは、次の 3 つ。

- Supabase の JWT（HS256。Secrets Manager の `jwt_secret_{name}` のどれかで検証。複数の鍵を登録できる）
- サービスキー（`service_key_{name}`。人は分からず、サービスの名前になる）
- 人が自分で発行した API キー（`jadd_*`）

Databricks の SSO にすると、STUDIO は Supabase のトークンを持たない。選べる道:

| 道 | 中身 | 良い点 | 問題 |
|---|---|---|---|
| A. Supabase のログインを残す | SSO の内側で、いまの Google ログインをもう一度通す | **コードの変更がほぼ無い**。お試しに向く | 利用者が 2 回ログインする。Supabase の OAuth の戻り先が Apps の前段を通るかは未確認 |
| B. STUDIO が JWT を自分で署名する | BFF に `jwt_secret_studio` を足し、STUDIO が人の `sub`（Supabase のユーザー ID）と email で JWT を作る | 1 回のログインで済む | cdk-apps と backend-api のチームの合意が要る。STUDIO が「誰にでもなれる鍵」を持つことになるので、鍵の管理と監査を決める必要がある |
| C. BFF が Databricks のトークンを受け付ける | オーソライザーに Databricks の OAuth のトークンの検証を足す。STUDIO はユーザー認可（`x-forwarded-access-token`）を送る | 人の資格情報のまま渡せる | cdk-apps の改修が要る。backend-api の `sub`（いまは Supabase のユーザー ID）との対応を作る必要がある |
| D. サービスキーで呼ぶ | STUDIO 用のサービスキーで呼ぶ | 改修が少ない | backend-api から人が見えなくなる（作成者や監査が「STUDIO」になる）。STUDIO 側のロールだけが守りになる |

どれも取らなければ、backend-api を使う機能は止まる。

#### 3. STUDIO 自身の DB（Supabase に残すか、Lakebase に移すか）

| 案 | 中身 | 良い点 | 問題 |
|---|---|---|---|
| **残す**（お試しの勧め） | DB は Supabase（東京）のまま | コードは変わらない。Databricks からの読み取り（Lakehouse Federation）もそのまま | Supabase の契約は残る。東京とオレゴンの往復が増える |
| Lakebase + Data API | Lakebase の PostgREST 互換の Data API に、postgrest-js を向ける | リポジトリ層を書き直さずに済むかもしれない | 下の「Data API で確かめること」。**互換と書かれているが、supabase-js・postgrest-js の名は無い** |
| Lakebase + Postgres の直結 | node-postgres などで SQL を書く | 機能の制約が最も少ない | リポジトリ 48 個・数百のクエリと RPC の呼び方を書き直す。大きな作業 |

Lakebase で確かめたこと（[拡張](https://docs.databricks.com/aws/en/oltp/projects/extensions)・[互換性](https://docs.databricks.com/aws/en/oltp/projects/compatibility)・[Data API](https://docs.databricks.com/aws/en/oltp/projects/data-api)）:

- パッチで使っている拡張は `pgcrypto` と `btree_gist`。どちらも Lakebase にある。RLS・独自のスキーマ・GRANT も使える。
- **SECURITY DEFINER の関数（29 か所）は、ドキュメントに記述が無い**。セッションストアとアノテーションの保存はこれに頼っている。試す必要がある。
- 本当の superuser は無い（`databricks_superuser` が代わり）。
- 移行は `pg_dump` / `pg_restore`（パスワードのロールで行う）。Supabase からの手順は、Neon の [Migrate from Supabase](https://neon.com/docs/import/migrate-from-supabase) が近い（Lakebase の公式ではない）。

Data API で確かめること（STUDIO の使い方と突き合わせた）:

| STUDIO の使い方 | Data API |
|---|---|
| 絞り込み・並べ替え・`.range()`（48 か所）・`count: "exact"`（15 か所）・埋め込み（7 か所）・RPC（25 本） | 対応と書かれている |
| `upsert`（4 か所）・書いた行を返す（`.insert().select()`。`Prefer: return=representation`） | **記述が無い** |
| URL | `…/api/2.0/workspace/<ws-id>/rest/<database>/<schema>/<table>`。supabase-js の `…/rest/v1/<table>` と形が違う。postgrest-js に URL を直接渡す必要がある |
| 権限 | いまは service role のキー。パッチの GRANT は `service_role` 向けが 69 か所、`authenticated` 12・`anon` 1。Data API はトークンの持ち主の Postgres のロールに切り替わるので、**アプリのサービスプリンシパルのロールに付け直す** |
| スキーマの再読み込み（`NOTIFY pgrst, 'reload schema'`、31 か所） | Data API での扱いは書かれていない |
| トークン | 1 時間で切れる。サービスプリンシパルのトークンを取り直す仕組みが要る |

#### 4. Databricks から STUDIO の DB を読んでいるパイプライン

`supabase_jadd_studio.public.*`（Lakehouse Federation）を、databricks-jobs の 5 ファイル、mono-e2e の 39 ファイル（naga-pipeline など）が読んでいる。DB を Lakebase に移すなら、Lakebase を Unity Catalog に載せ直し、これらの参照を替える必要がある（同じカタログ名を付け直せるかは未確認）。DB を Supabase に残すなら関係ない。

## お試しの進め方（案）

**第一段階: ホスティングだけ移す**（DB と Supabase Auth は残す）

1. Databricks Apps に、STUDIO の main をそのまま上げる。手直しは、devDependencies の移動、Node 22、`app.yaml`（起動のコマンド・環境変数・secret）、`X-Real-Ip` だけ。
2. Supabase の OAuth の戻り先に Apps の URL を足す。SSO の内側で Google ログインが通るか、backend-api が動くかを見る。
3. 見ること:
   - ビルドが Apps の計算機で終わるか。
   - H2C の要件を `next start` が満たすか。
   - 長く走る API が前段で切られないか。
   - 東京から使ったときの体感（DB が東京、アプリがオレゴン）。
4. 定期実行は Vercel に残したまま、お試しでは止めない。本番の切り替えまでに Jobs に移す。

**第二段階以降**（結果を見て決める）

- ログインを SSO だけにする（backend-api の道 B か C を、cdk-apps と backend-api のチームと決める。offboarding-sync を作り直す）。
- STUDIO の DB を Lakebase に移すか決める（Data API の確かめ、SECURITY DEFINER の確かめ、パイプラインの参照の替え）。

## 確かめていないこと

- Next.js が Apps で動くか（公式の記述は無い。第三者の手順はある）。H2C、ビルドの上限、前段の時間制限、WebSocket。
- SSO の内側で、ほかのサイト（Supabase の OAuth）への往復が通るか。
- 社の IdP から Databricks に、STUDIO を使う人が全員登録されているか。メールとパスワードの利用者が今いるか。
- Lakebase の SECURITY DEFINER と、Data API の upsert・`return=representation`。
- 外部 API が IP で絞っているか。
- backend と drivers-app の Supabase がどのリージョンにあるか。

## 一次情報

- jadd_studio3: `docs/general/authentication.md`・`docs/general/adr/0004-session-management.md`・`docs/guidelines/database.md`・`lib/server/backend-api/`・`lib/utils/auth/`・`lib/server/tern/client.ts`・`vercel.json`・`package.json`・`prisma/patch/`
- cdk-apps: `apps/bff/lib/functions/supabase-authorizer-v3.ts`
- Databricks: [Apps のデプロイ](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/deploy)・[依存](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/dependencies)・[HTTP ヘッダー](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/http-headers)・[認可](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/auth)・[ローカルからの接続（M2M）](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/connect-local)・[ネットワーク](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/networking)・[Apps と Lakebase](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/lakebase)・[Lakebase の認証](https://docs.databricks.com/aws/en/oltp/projects/authentication)・[コネクションプール](https://docs.databricks.com/aws/en/oltp/projects/connection-pooling)・[pg_dump/pg_restore](https://docs.databricks.com/aws/en/oltp/projects/pg-dump-restore)
