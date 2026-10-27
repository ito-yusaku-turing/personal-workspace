# Tern iOS アプリの認証と、フィードバックの送信

- 開始: 2026-10-23
- 状態: **方針と分担が決まり、説明用の資料でレビューを受ける段階（2026-10-27）**。こちらは「Google ログインと、ログインした利用者が backend-api を呼ぶ経路」を用意し、iOS への組み込み方を示すまで。iOS への組み込みとフィードバックの機能は三輪さんが作る。説明用の資料（[`notion-tern-ios-google-login.md`](tern-backend-api/notion-tern-ios-google-login.md)）を Notion に上げた（2026-10-26、[Notion のページ](https://app.notion.com/p/405a93b3e6f281208011c7ccdb174536)。Status は下書き。2026-10-27 に TL;DR を足して同期）。三輪さんと MLOps チームにレビューしてもらう
- 所属: project:tern-ios-auth（作業先は navi-ios-app・mono-e2e・cdk-apps にまたがる。2026-10-26 に `~/docs/workstream/` から移した）
- 関連: [backend-api・JADD STUDIO・CLI の認証（補足資料）](../../idp-broker/documents/backend-api-auth-supplement.md)、[M2M 認証](../../m2m-auth/workstream/m2m-auth.md)

## 元の要件

> **Task**: Tern の iOS アプリで Google ログインをしたい
>
> 内製ナビ（Tern）の β テストのため、iOS アプリを作って TestFlight しています。
> この利用のために現状 Tern API の API キーを指定していますが、将来的に API キーから脱却したいという話題があります。
> また、今後 backend API 経由でフィードバックを送信するなどの機能も入れていきたいのですが、現状の仕組みでやろうとすると JADD_SERVICE_KEY を使うことになり、これも脱却したい運用です。
>
> そこで、JADD STUDIO3 のように Google アカウントでログインして認証できるようになると、色々楽になるのですが、ご検討いただけないでしょうか？

追加の要件（2026-10-23）: **ナビデータについてのフィードバックを送信し、Databricks から参照したい。**

要件をほどくと、次の 3 つになる。

| # | 欲しいこと | いまの形 |
|---|---|---|
| R1 | 利用者が Google でログインし、アプリが「誰か」を知る | 無い。アプリは匿名 |
| R2 | Tern API（経路の計算）を API キー無しで呼ぶ | 共有の API キー 1 本を、利用者が設定画面に手で入れる |
| R3 | ナビデータへのフィードバックを送り、Databricks から読む | 機能が無い。作るなら JADD_SERVICE_KEY を使うことになる |

## 分担（2026-10-23）

| 担当 | 範囲 |
|---|---|
| **こちら** | R1 の経路を用意する。backend-prod の Supabase の設定（MLOps との調整）と、iOS への組み込み方を示すこと。backend-api に届くことの確認まで |
| 三輪さん | iOS への組み込み（ログイン・backend-api の呼び出し）と R3（フィードバックの中身・テーブルの定義・backend-api の受付・送信の画面） |
| 未定 | R2（Tern API の API キーをやめる）。今回の範囲外 |

## 調べた事実（2026-10-23）

### iOS アプリ（turingmotors/navi-ios-app、`87cade2`）

| 事実 | 根拠 |
|---|---|
| **backend-api はいま一切呼んでいない** | リポ全体に backend-api・Supabase・Bearer の記述が無い |
| 外への通信は Tern API（経路の計算）だけ。`GET /mapbox/directions/v5/...` に `x-api-key` を付ける | `TuringNavi/Services/Routing/ValhallaClient.swift:4,47`、`docs/ARCHITECTURE.md:43-46` |
| API キーは実機では設定画面から手で入れ、Keychain に置く。ビルドには埋め込まない | `TuringNavi/Features/Settings/Settings.swift:80-91`、`docs/DEVELOPMENT.md:108-117` |
| ほかの通信先は、車内 LAN の車載機（TuringPilot、`https://172.16.250.1`）と地図タイル（CARTO）。どちらも認証の話には絡まない | `TuringPilotClient.swift:106`、`CartoStyle.swift:14` |
| オフライン（端末内の Valhalla）での経路の計算もでき、既定はオフライン | `Settings.swift:53` |

### Tern API（cdk-apps `apps/tern-api`、origin/main `c8698ee2`）

| 事実 | 根拠 |
|---|---|
| API Gateway（REST）。**API キー必須で、キーは 1 本を共有**。車両も同じキーを使っているので、`apiKeyId` では呼び出し元を区別できない | `lib/tern-api-stack.ts:432-488`、`README.md:80,101-103` |
| 同じ API の IAM（SigV4）版もある | `lib/tern-api-stack.ts:500-517`、`README.md:83` |
| BFF と同じアカウント・リージョン（767397804933 / us-west-2） | `bin/tern-api.ts:10-11`、`apps/bff/bin/bff.ts:8-9` |

### backend-api と既存の認証（mono-e2e `ef544ba56`、cdk-apps `c8698ee2`）

| 事実 | 根拠 |
|---|---|
| BFF の authorizer は、Supabase の JWT（HS256）・サービスキー（`sk_*`）・利用者の自己発行キー（`jadd_*`）を受ける | `apps/bff/lib/functions/supabase-authorizer-v3.ts:1-30` |
| **既存の Supabase プロジェクト（backend-prod と JADD Studio）の JWT は、もう通る** | 補足資料の 3 章 |
| jadd-cli は、**backend-prod の Supabase に Google でログイン**している（Supabase の `/auth/v1/authorize?provider=google` → ローカルへのリダイレクト） | jadd-cli `src/jadd/supabase_oauth.py:12-13,79` |
| **backend-api には既に Tern 用の API がある**（`/tern-dev-agent/map-errors/*`）。社内の JWT か `jadd_*` キーで呼べ、`@turing-motors.com` の検証済みの利用者だけに許す。保存先は **Databricks の `e2e.tern_agent`** | mono-e2e `projects/api/backend-api/docs/tern-agent.md:5-26,173`、cdk-apps `apps/backend-api/TERN_AGENT.md` |
| JADD_SERVICE_KEY（`sk_*`）は CI 用。有効期限が無く、利用者を表さない | mono-e2e `.github/workflows/*`、authorizer `:13-19` |
| （2026-10-26 確認）`api.turing-ai.dev` はまだ BFF の `$default` に割り当てられている。backend-api の API Gateway は API Gateway の IP からの呼び出ししか受けないので、**実機から直接は届かない** | cdk-apps `aef8ad08`: `apps/bff/lib/bff-stack.ts:199`、`apps/backend-api/lib/api.ts:1321-1350` |
| （同）backend-api は公開経路のトークンを自分で検証する（`TOKEN_VERIFICATION_MODE=enforce`）。検証は BFF のスタックの `supabase-authorizer-v3` を invoke して行うので、**BFF のスタックを消すと検証役も消える** | mono-e2e `53264c67f`: `deps/token_verifier.py:1-40`、cdk-apps `apps/backend-api/lib/api.ts:23-29,160-166,298-320` |

## 視点を引いた整理

- **R1 に新しい Supabase プロジェクトは要らない見込み。** jadd-cli と同じく、backend-prod の Supabase に Google でログインすればよい。そのトークンは backend-api の検証（`token_verifier`。今は BFF のスタックの authorizer を invoke する）をもう通るので、**鍵の登録も検証の改修も要らない**。iOS では `ASWebAuthenticationSession` で Supabase の認可の画面を開き、アプリの URL スキームへ戻す（supabase-swift の OAuth のログインがこれを包んでいる）。設定の手作業は、backend-prod の Supabase の Redirect URLs にアプリの戻り先を足すことだけ。ただし backend-prod の anon キーがアプリのビルドに入るので、`public` スキーマの RLS を確かめる（説明用の資料の「新しく生じること」）。
- **R3 は、既存の Tern 用の API と同じ作りで足せる。** backend-api にフィードバックの受付を足し、backend-prod の Postgres に書く（Databricks からは federation で読む。下の「フィードバックの保存先」）。認可も同じく「検証済みの `@turing-motors.com` の利用者」にでき、送った人を JWT の `sub`・email で記録できる。JADD_SERVICE_KEY は使わない。
- **R2 は別の作業になる。** Tern API は backend-api の後ろにいないので、ログインしても API キーは消えない。共有のキーを外すには、Tern API にトークンを検証する入口を足すか、backend-api に中継を足す必要がある（下の案）。β テストの間は、キーを残したまま R1・R3 を先に進めてもよい。

## R2（Tern API の API キーをやめる）の案

2026-10-26: a と b の両方を残して比べる（どちらに決めるかは未定）。

| 案 | 中身 |
|---|---|
| a. Tern API に authorizer を付ける | Tern API の同じ REST API に `/auth/{proxy+}` を足し、Supabase の JWT で受ける。既に PR がある（[cdk-apps#2220](https://github.com/turingmotors/cdk-apps/pull/2220)） |
| b. backend-api を経由する | backend-api に Tern API への中継を足す。アプリは `https://api.turing-ai.dev/v1/...`（BFF 経由）を R1 と同じトークンで呼ぶ。先例は `/valhalla/lane-semantic-map/*` |
| c. キーを残す | β の間は今のまま。作業はゼロだが、要件の「API キーから脱却」は満たさない |

### a と b の比較

| 観点 | a. Tern API に authorizer | b. backend-api を経由 |
|---|---|---|
| 今の進み具合 | PR がある。Approve 済みだが Draft、main と conflict。10/19 から止まっている（三輪さんが Devin に作らせたもの） | 手を付けていない。ただし同じ作りの先例が backend-api で動いている |
| 残りの作業 | `ALLOWED_ISSUERS` に backend-prod（`lvngtemehmcxemnurgwb`）を足す、conflict を解く、deploy 後に `AWS_LWA_REMOVE_BASE_PATH` が効くか実機で確かめる | backend-api に Tern API 用の中継を足す。先例は POST の `/route` などと `GET /status`・`/map-info` だけで、アプリが呼ぶ `GET /mapbox/directions/v5/...` は無い。Tern API の キーを取る IAM 権限も要る |
| どのリポジトリか | cdk-apps（`apps/tern-api`）だけ | mono-e2e（backend-api）。必要なら cdk-apps（キーの権限） |
| アプリから見た入口 | 2 つ（backend-api と Tern API の `/auth/*`）。どちらも同じトークン | backend-api の 1 つだけ |
| BFF への依存 | 検証を BFF のスタックの `supabase-authorizer-v3` に任せる。BFF の道（`/v1`）は通らない | 検証も `/v1` の道も BFF に頼る。BFF の撤廃が経路の計算にも及ぶ |
| 遅延 | 今の道と同じ。authorizer の結果は 5 分キャッシュ | BFF → backend-api の Lambda → Tern API と 2 段増える。どこまで許せるかは未確認 |
| 上限 | `/auth/*` は 20 rps / burst 50（API キー版は 100 / 1000）。authorizer の同時実行は 10 | backend-api の Lambda の上限と、上流との通信の期限（先例は 26 秒）。応答の大きさも先例は 4 MiB まで |
| 費用 | authorizer の Lambda（キャッシュで少ない） | 経路の計算 1 回ごとに backend-api の Lambda が 1 回動く |
| 認可の判定 | authorizer の中で、`iss`・`role`・匿名でないこと・`@turing-motors.com`・`app_metadata.provider == google` を見る | backend-api の既存の判定（`get_verified_user`、`tern_agent.py` の `writer`）を使える |
| 失効の反映 | 最大 5 分（authorizer のキャッシュ） | 最大およそ 10 分（BFF と backend-api の 2 段のキャッシュ） |
| R1 との関係 | R1a（ログイン）だけがあればよい | R1a と R1b（backend-api の呼び出し）の上に乗る |

### 判断の材料

- a は「動きかけの PR を進める」話で、決めるべきは issuer に backend-prod を足すかどうかだけ。止まっている理由は PR の本文にある「iOS がどの Supabase project でログインするか」で、R1 で backend-prod に決めたので、それを伝えれば動き出せる見込み。
- b は入口が 1 つにまとまるのが利点だが、経路の計算まで BFF の撤廃の影響を受け、遅延と費用も増える。経路の計算は走行中の再計算もあるので、呼ぶ回数と許せる遅延を三輪さんに確かめてから選ぶ。
- どちらも BFF のスタックの `supabase-authorizer-v3` に頼る点は同じ。BFF の撤廃では、どちらの案でも検証役の引き継ぎが要る。

## こちらの作業（R1）

1. **backend-prod の Supabase の設定**（手動）: Redirect URLs にアプリの戻り先（URL スキーム。例: `turingnavi://auth-callback`）を足す
2. **iOS への組み込み方を示す**（実装は三輪さん。説明用の資料の「iOS アプリへの組み込み」）
   - ログイン: supabase-swift で、Google の OAuth（PKCE）のログインを `ASWebAuthenticationSession` で行う。セッションは Keychain に置き、トークンの更新とログアウトも用意する。設定画面にログインの状態を出す
   - backend-api のクライアント: ベースの URL は `https://api.turing-ai.dev/v1`（BFF 経由）。BFF の撤廃に備え、ビルドの設定で差し替えられるようにする。BFF の authorizer は無効なトークンにも 403 を返すので、401・403 のどちらでも 1 回だけ更新して送り直す。`Authorization: Bearer <access_token>` を付け、期限切れのときは更新してから送る。この上に受付の呼び出しを足せる形にする
3. **疎通の確認**: ログインした実機から、既存の backend-api のエンドポイントを呼び、BFF の authorizer と backend-api の `token_verifier` を通ることを確かめる（`/v1/tern-dev-agent/map-errors/capabilities`）
4. **引き渡し**: 三輪さんに、組み込み方と、受付の API 側で `@turing-motors.com` に絞る方法（既存の tern-agent と同じ）を伝える

三輪さんの側（参考）: iOS にログインと backend-api の呼び出しを組み込む。フィードバックの中身を決め、db-models にテーブルを足し、backend-api に受付を足し、iOS に送信の画面を足す。R2 は今回の範囲外。

当初の案（新しい Supabase プロジェクト + 鍵の登録）は、**backend-prod を使えなくなった場合だけ**の予備に回す（下の「決めたこと」で backend-prod を使うと決めた）。その場合の注意: authorizer は HS256 の共有の秘密しか受けない（`supabase-authorizer-v3.ts:578`）ので、新しいプロジェクトが非対称鍵なら authorizer の改修が要る。また `iss` を確かめていないので、新しいプロジェクトに誰でも Google で入れると backend-api まで届く。

## 決めたこと（2026-10-23）

- [x] **β テスターは社員だけ。** Google ログイン（`@turing-motors.com`）で足りる。当初の案（新しい Supabase プロジェクト）は使わない
- [x] **ログインには backend-prod の Supabase を使う。** jadd-cli で Supabase Auth の実績がある
  - jadd-cli と共存できる。Redirect URLs は複数登録でき、アプリは `redirect_to` で戻り先を指定するので、Site URL も jadd-cli の戻り先も変えない。Google の Client ID もカンマ区切りで足せる（ネイティブの Sign-In にする場合）。同じ社員は jadd-cli と iOS で同じ `sub` になる
- [x] **iOS への組み込みは三輪さんが行う**（分担の表）。navi-ios-app は三輪さんのリポなので、PR も三輪さんが出す
- [x] **BFF の撤廃までは BFF（`https://api.turing-ai.dev/v1`）を通して backend-api を呼ぶ**（2026-10-26。同日に一度「BFF を使わない」としたのを改めた）。BFF は撤廃が決まっているが今も動いていて、backend-api に届く道は BFF だけ。撤廃の作業には同じ URL とパスを引き継いでもらうよう頼む（jadd-cli も同じ URL）。資料の前提条件の先頭に【重要】として書いた
- [x] **フィードバックの保存先・テーブル・受付の API は今回の範囲外（三輪さんの裁量）**（2026-10-26 に改めた）。今回は backend-prod の DB のスキーマに手を入れない。下の「フィードバックの保存先」は、三輪さんへの参考として残す（当初は A に決めたと書いていた）

## 決めること

- [ ] **ログインは必須か任意か**（三輪さんと決める）。オフラインの経路の計算は今もキー無しで使えるので、「フィードバックを送るときだけログイン」もありうる
- [ ] 【未決】idp-broker の方針「Supabase のトークンはどの段でも扱わない」（2026-10-16、[補足資料](../../idp-broker/documents/backend-api-auth-supplement.md)）との関係。Tern は backend-prod の Supabase のトークンに頼る利用者を足す。一時的な例外とするか、ブローカーへの移行で置き換える対象に入れるかが決まっていない
- [ ] BFF の撤廃（安本さん）で、`https://api.turing-ai.dev/v1` の URL とパスを引き継いでもらえるか。引き継げないなら、撤廃より前にアプリの版を出し直す必要がある。検証役（`supabase-authorizer-v3`）の行き先も同じ作業で決まる（[M2M 認証](../../m2m-auth/workstream/m2m-auth.md)の「1. BFF」）

三輪さんの側で決めること（参考）: フィードバックの中身（経路・地点・自由記述・スクリーンショット？）と読み方。**座標を含むので、ログには出さない**（既存の tern-agent の方針と同じ）。R2 は担当・時期とも未定。

### フィードバックの保存先

どちらも backend-api が書き、Databricks から読める。backend-prod の Postgres は Databricks の federation のカタログ `supabase_backend_prod` で読める（mono-e2e で 21 か所の参照がある）。

| | A. backend-prod の Postgres | B. Databricks のテーブル |
|---|---|---|
| 先例 | Tern の回帰テスト（`packages/db-models/backend_models/tern_regression_test.py`、alembic） | Tern の地図エラー（`e2e.tern_agent`、Terraform） |
| 定義の場所 | mono-e2e の db-models（alembic のマイグレーション） | mono-e2e の databricks-terraform |
| 書き込み | 1 件ずつの INSERT が速く安い。アプリへの応答も速い | SQL Warehouse を通す。止まっていると起動待ちが出る |
| Databricks からの読み | `supabase_backend_prod.public.<table>`（federation。重い集計には向かない。必要ならマテリアライズする） | そのまま読める。ほかの Databricks のデータと JOIN しやすい |
| 向き | アプリからの少量の書き込みが主なとき | Databricks での集計・突き合わせが主なとき |

当初（2026-10-23）は A に決めたと書いたが、2026-10-26 に保存先は三輪さんの裁量に改めた。A を選ぶ場合の理由は、アプリから 1 件ずつ送るものなので、Postgres に書いて federation で読むのが素直なこと。

## 調べること

- [ ] backend-prod の Supabase の Redirect URLs に、アプリの URL スキームを足せるか（ワイルドカードの制限。JADD STUDIO の `docs/general/authentication.md:444`）
- [ ] supabase-swift の OAuth のログイン（PKCE）が、backend-prod の設定のままで使えるか
- [ ] backend-prod の Supabase の Google のログインが、社外の Google アカウントを弾くか（OAuth の同意画面が「内部」か）。弾かないなら、受付の API 側で `@turing-motors.com` に絞る（jadd-cli の経路でも同じ事情）
- [ ] backend-prod の Supabase で、退職者がどう止まるか（JADD Studio のプロジェクトは STUDIO の cron が ban する）
  - 分かったこと: backend-prod にもオフボーディングの同期（[mono-e2e#6139](https://github.com/turingmotors/mono-e2e/pull/6139)）があり、10/9 に本番で有効になった。15 分ごとに、Google で停止・削除された人を ban し、API キーの再発行を止める（[IdP の役割分担の検討](../../idp-broker/workstream/idp-auth0-role-division.md)の「backend-api の課題と、今の動き」）
  - 残り: ban のあと、発行済みのトークンがいつまで使えるか
- [ ] backend-prod の `public` スキーマの RLS が「認証済みなら何でも読める」になっていないか（anon キーをアプリのビルドに入れるため。説明用の資料の「新しく生じること」）
- [ ] 疎通の確認に使う、既存の backend-api の読み取りのエンドポイント（副作用が無く、利用者の身元が返るもの）
- [ ] backend-prod の Supabase の設定を変えられる人（Redirect URLs の追加）
- 三輪さんの側（参考）: backend-prod の Postgres に足したテーブルが、`supabase_backend_prod` の federation で自動的に見えるか（権限の付与が要るか）

## 進捗と引き継ぎ

- 2026-10-23: 資料を作成。当初は「新しい Supabase プロジェクトの鍵を backend-api に登録する」案で書いた。
- 2026-10-23: 元の要件と追加の要件（フィードバックを Databricks から読む）から見直した。iOS アプリは backend-api を呼んでおらず、Tern API の共有キーだけを使っている。既存の backend-prod の Supabase と、backend-api の Tern 用の API の作りを使えば、新しいプロジェクトも鍵の登録も要らない見込み。次は「決めること」の先頭 2 つ（テスターの範囲・backend-prod でよいか）を依頼者に確かめる。
- 2026-10-23: β テスターは社員だけ、ログインは backend-prod の Supabase と決まった。フィードバックの中身は三輪さんに確認する。保存先は backend-prod の Postgres（federation で Databricks から読む）を推奨として整理した。次は三輪さんへの確認。
- 2026-10-23: 保存先を backend-prod の Postgres に決めた（既存の Tern の回帰テストのテーブルと並べる）。残りは三輪さんへのフィードバックの中身の確認。
- 2026-10-23: 分担が決まった。こちらは R1（Google ログインと backend-api を呼ぶ経路の用意）まで、フィードバックの機能（テーブル・受付・画面）は三輪さん、R2 は範囲外。次は「調べること」の Supabase の設定（Redirect URLs・社外アカウント）を確かめ、iOS のログインに着手する。
- 2026-10-23: 「backend-prod の認証を使うと iOS 専用になるか」を確認し、Redirect URLs を足すだけで jadd-cli と共存できると整理した。backend-prod の Redirect URLs にアプリの戻り先を足す方向で進める。
- 2026-10-23: 三輪さんと MLOps チームに共有する説明用の資料を [`tern-backend-api/notion-tern-ios-google-login.md`](tern-backend-api/notion-tern-ios-google-login.md) に作った（Notion に取り込んでレビューしてもらう）。iOS への組み込みは三輪さんが行う。
- 2026-10-26: 説明用の資料を MLOps 1チームの「ドキュメント置き場」に Notion のページとして作った（[Notion のページ](https://app.notion.com/p/405a93b3e6f281208011c7ccdb174536)、Status は `下書き(Draft)`）。原本はローカルの資料のままで、冒頭に URL を書いた。上げる前に PR 番号をフル URL にし、Notion で崩れた太字（`**…）**を` の形）を原本ごと直した。
- 2026-10-26: BFF の撤廃が決まっているので、アプリは BFF を使わず backend-api だけを呼ぶ形に説明用の資料を直した。main を見ると、まだ `api.turing-ai.dev` は BFF にあり、backend-api は API Gateway の IP からしか受けず、検証も BFF のスタックの authorizer に頼っている。入口の用意と検証役の移設は BFF の撤廃の作業の前提として、資料の「作業の順番」の 3' と「合意したいこと」の 7 に書いた。R2 の既存の PR（[cdk-apps#2220](https://github.com/turingmotors/cdk-apps/pull/2220)）が STUDIO の Supabase と BFF の authorizer に頼っていることも見つけた。
- 2026-10-26: 説明用の資料を手元で組み直した（Notion には未反映）。提案の形をやめ、要件（今のアプリの整理を含む）・前提条件・仕様・今回の範囲・注意点の順にした。図とコードは外し、人の情報は最小限にした。今回の範囲は R1 まで（Redirect URLs の追加・anon キーの受け渡し・iOS への組み込み・疎通の確認）で、DB のスキーマ・API の追加・Databricks は範囲外（R1 の後は三輪さんの裁量）とした。Google Cloud の OAuth クライアントは作らない（Supabase の画面でのログインにするため）。
- 2026-10-26: BFF は撤廃まで動くので、撤廃までは BFF を通す前提に資料を組み替えた。廃止予定の BFF に頼ることは前提条件の先頭に【重要】として書いた。BFF の authorizer は期限切れのトークンにも 403 を返す（`supabase-authorizer-v3.ts:112`、HTTP API の simple response）ので、応答の扱いを「401・403 なら 1 回更新して送り直す」に改めた。R2・R3 は「範囲外」にそろえた。
- 2026-10-26: R2 の案 a（[cdk-apps#2220](https://github.com/turingmotors/cdk-apps/pull/2220)）と案 b（backend-api を経由）を両方残して比べることにした。b には backend-api の `/valhalla/lane-semantic-map/*` という先例がある。#2220 は 10/19 から止まっていて、Draft のまま main と conflict している。比較は「R2 の案」の節に書いた。
- 2026-10-26: 組み直した説明用の資料で Notion のページを同期した（本文をまるごと置き換え。表の列の幅は既定に戻った）。Notion の側でタイトルの末尾に「(ドラフト)」が足されていたので、プロパティには触らずに残した。コメントは無かった。R2 の a・b の比較は workstream にだけ書き、説明用の資料には入れていない。
- 2026-10-27: 説明用の資料の冒頭の概要の段落を、TL;DR（6 項目）に置き換えた。Notion のページも同じ箇所だけ書き換えて同期した（同期の前に確かめたところ、人の編集もコメントも無かった）。
- 次: Notion は 2026-10-27 の版で同期済み。人の情報（担当）を最後に必要な分だけ足し、R2 の a・b を資料に載せるかを決める。そのあと Status を `提案中(Proposed)` にして共有する。直すときは原本を直してから Notion を更新する（その前に Notion の人の編集とコメントを確かめる）
