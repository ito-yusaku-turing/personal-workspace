# Tern iOS アプリに Google ログインを入れ、backend-api を呼べるようにする

Notion: <https://app.notion.com/p/405a93b3e6f281208011c7ccdb174536>（この資料が原本。直すときはここを直してから Notion を更新する）

作成: 2026-10-23 ／ 更新: 2026-10-26

Tern の iOS アプリで、社員が Google アカウントでログインできるようにする。そのトークンで backend-api を呼べるようにし、API キーや JADD_SERVICE_KEY を使わずに機能を足せる土台を作る。ログインには jadd-cli と同じ backend-prod の Supabase Auth を使う。

## 要件

### 今の iOS アプリ（navi-ios-app）

- 利用者を区別していない。アプリは匿名で動く。
- 外への通信は Tern API（経路の計算）だけ。共有の API キー 1 本を、各自が設定画面で入れて `x-api-key` に付ける。
- backend-api は呼んでいない。
- 経路の計算は端末の中（オフライン）でもでき、既定はオフライン。

### 要件

| # | 要件 | 今回 |
|---|---|---|
| R1 | 社員が Google でログインし、アプリが利用者を知る。そのトークンで backend-api を呼べる | **やる** |
| R2 | Tern API を API キー無しで呼ぶ | やらない |
| R3 | ナビデータへのフィードバックを送り、Databricks から読む | やらない（R1 の上に別に作る） |

## 前提条件

- β テスターは社員だけ。社外の人のログインは考えない。
- backend-prod の Supabase Auth は jadd-cli と共用。jadd-cli のログインを変えずに足せること。
- backend-api の検証は、backend-prod の Supabase の JWT をすでに受け付けている（jadd-cli が使っている）。
- BFF（`api.turing-ai.dev`）は撤廃が決まっている。アプリは BFF を使わず、撤廃した後の backend-api の入口を呼ぶ。

## 仕様

### ログイン

- supabase-swift の Auth で、Google の OAuth（PKCE）のログインをする。Supabase のログイン画面を `ASWebAuthenticationSession` で開き、Google でログインしてアプリに戻る。
- Google のネイティブのログイン（Google Sign-In SDK）は使わない。そのため、Google Cloud に iOS 用の OAuth クライアントは作らない。
- 社員のアカウントを先に出すため、`hd=turing-motors.com` を付ける。これは表示の指定で、制限ではない。
- セッションは supabase-swift が Keychain に置き、期限が近づくと自動で更新する。
- 設定画面に、ログインの状態（メールアドレス）と、ログイン・ログアウトの操作を置く。

### backend-api の呼び出し

- `Authorization: Bearer <access_token>` を付けて送る。送る前にセッションを取り出し、期限切れなら更新してから使う。
- 応答の扱い:
  - 401（トークンが無効）: 1 回だけセッションを更新して送り直す。だめならログインし直してもらう。
  - 403（社員のアカウントでない）: 社員のアカウントでログインするよう案内する。
  - 503（認証の基盤に一時的に届かない）: 少し待って送り直す。
- Tern API の呼び出し（`x-api-key`）は今のまま変えない。

### 設定の値

| 項目 | 値 |
|---|---|
| Supabase の URL | `https://lvngtemehmcxemnurgwb.supabase.co`（backend-prod） |
| anon キー | backend-prod の anon キー。ビルドの設定で渡し、リポジトリに直接書かない |
| URL スキーム | `turingnavi`（案）。`Config/AppInfo.plist` の `CFBundleURLTypes` に登録する |
| 戻り先 | `turingnavi://auth-callback`（案）。backend-prod の Redirect URLs と一字一句同じにする |
| backend-api の URL | BFF を撤廃した後の backend-api の入口（未定）。ビルドの設定で渡し、差し替えられるようにする |

## 今回の範囲

### 今回やること

- backend-prod の Supabase Auth の **Redirect URLs に戻り先を 1 行足す**（URL Configuration）。Site URL、Google のプロバイダ、jadd-cli の戻り先は変えない。
- anon キーを iOS アプリの担当に渡す。
- 上の「仕様」のとおり、ログインと backend-api の呼び出しを iOS に組み込む。
- 疎通を確かめる。ログインした実機から、backend-api の既存の Tern 用 API（`GET /tern-dev-agent/map-errors/capabilities`）を呼んで 200 が返ること。これで、ログイン・backend-api でのトークンの検証・`@turing-motors.com` の判定までが通ったと分かる。

### 今回やらないこと

- backend-prod の DB のスキーマ（テーブルの追加）、backend-api への API の追加、Databricks の設定。
- Tern API の API キーの廃止（R2）。
- Google Cloud の OAuth クライアントの追加・変更。
- BFF の撤廃の後の入口づくり（BFF の撤廃の作業で行う）。

### この先は三輪さんの裁量

R1 ができた後の機能（R3 のフィードバックなど）は、中身・保存先・API・画面を三輪さんが決めて作ってよい。backend-api に API を足すなら、認可は既存の Tern 用 API と同じ判定（`deps/tern_agent.py` の `writer`。検証済みで `@turing-motors.com` の利用者だけ）が使える。送った人は JWT の `sub` と email で記録できる。

## 注意点・留意点

- **backend-api の入口がまだ無い。** `api.turing-ai.dev` は BFF に割り当てられたままで、backend-api の API Gateway は API Gateway の IP からしか受けない。実機から直接は届かないので、疎通の確認は入口ができるまでできない。ログインの組み込みは先に進められる。
- **検証役も BFF にある。** backend-api はトークンの検証を、BFF のスタックにある `supabase-authorizer-v3` に任せている。BFF を撤廃した後も、この検証役が残る必要がある。
- **anon キーがアプリのビルドに入る。** anon キーは公開を前提にした値なので入れてよいと考える。ただしログインした社員は backend-prod の PostgREST を直接呼べるので、`public` スキーマの RLS が「認証済みなら何でも読める」になっていないかを確かめる。
- **社外の Google アカウントを弾くかは未確認。** OAuth の同意画面が「内部」でなければ、社外の人もログインはできる。backend-api の側で `@turing-motors.com` に絞れば、API は使えない。
- **退職者のトークン。** アクセストークンの寿命は約 1 時間。backend-prod では、オフボーディングの同期（[mono-e2e#6139](https://github.com/turingmotors/mono-e2e/pull/6139)）が 15 分ごとに、Google で停止・削除された人を ban している。ban した後、発行済みのトークンがいつまで使えるかは未確認。
- **jadd-cli と同じ利用者になる。** 同じ社員は、jadd-cli とアプリで同じ `sub` になる。backend-api からは区別できない。
- **ログに出さない。** アクセストークン、座標、フィードバックの本文は、アプリのログにも backend-api のログにも出さない。
- **URL スキームは確定してから足す。** Redirect URLs とアプリの登録が一字一句同じでないとログインから戻れない。名前を決めてから Supabase に足す。
- **R2 の既存の PR とは前提が違う。** Tern API に Supabase の JWT を受ける入口を足す PR（[cdk-apps#2220](https://github.com/turingmotors/cdk-apps/pull/2220)、未マージ）は、JADD STUDIO3 の Supabase の JWT だけを受け、検証を BFF の authorizer に任せている。この資料の前提（backend-prod・BFF を使わない）とは合わない。

## 参考

- backend-api のトークンの検証: mono-e2e `projects/api/backend-api/deps/token_verifier.py`
- backend-api の入口: cdk-apps `apps/backend-api/lib/api.ts`（`RestApi` の resource policy）
- 既存の Tern 用 API の認可: mono-e2e `projects/api/backend-api/deps/tern_agent.py`、`projects/api/backend-api/docs/tern-agent.md`
- jadd-cli のログイン: mono-e2e `packages/jadd-cli/src/jadd/supabase_oauth.py`
- iOS アプリの今の通信: navi-ios-app `TuringNavi/Services/Routing/ValhallaClient.swift`、`docs/ARCHITECTURE.md`
