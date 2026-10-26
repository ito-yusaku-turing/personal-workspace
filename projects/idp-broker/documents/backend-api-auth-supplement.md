# ブローカー 3 候補と、backend-api・JADD STUDIO・CLI の認証（補足資料）

- 作成: 2026-10-16
- 範囲: 公開の文書と、mono-e2e・cdk-apps・jadd_studio3 の origin/main のコードによる机上の調査。動作の確認は、7 章の検証テナントで行う
- 関連: 報告書「社内アプリの認証の入口となる IdP の選定」（[`idp-broker-report.md`](idp-broker-report.md)）、安本さんの「service key 廃止の設計メモ」（2026-10-05）
- 読み手: 安本さん、MLOps1 のメンバー

## 用語

- **ブローカー**: 社内アプリの認証の入口となる IdP。社員は Okta から、ブローカーを経由してログインする。候補は Auth0（本命）・Zitadel Cloud（ツィタデルクラウド。2 番手）・WorkOS（3 番手）で、選定の経緯は報告書にある。
- **発行元（`iss`）**: トークンを出した主体。いまは Supabase の各プロジェクトで、この資料の形ではブローカーになる。
- **JWKS**: 発行元が公開する検証用の公開鍵の一覧。受け手は共有の秘密を持たずに署名（RS256 など）を検証できる。
- **`aud`**: トークンの宛先。backend-api 宛てのトークンには、backend-api を表す値が入る。

## 1. 目的と前提

**目的**: Supabase のトークンを、ブローカーが出すトークンに置き換えたとき、3 つのアクセスの経路が安全に成り立つかを、ブローカー 3 候補ごとに示す。

| 前提 | 内容 |
|---|---|
| Supabase のトークン | どの段でも扱わない。必須になっている箇所は撤去する |
| 社員のログイン | いま Google で JADD STUDIO にログインしているのは一時的な形。ブローカーの導入が決まれば、Okta からブローカーを経由する形に置き換える |
| 範囲外 | 協力会社のアクセス（報告書の範囲）と、M2M（車載装置・CI）。設計メモの号車・サービスのキーと IAM の経路は、そのまま残る。機械の身元は AWS（IoT・IAM）と backend-api の API キーで持つ方針で、ブローカーを M2M の発行役にはしない。どの候補を選んでも M2M の設計は変わらない |
| 扱う課題 | ブローカーの選び方で答えが変わる課題だけを扱う。backend-api・JADD STUDIO・jadd-cli の設計で解く課題は、6 章に一覧だけを置く |

**3 つの経路**

| 経路 | 中身 | いまの形 |
|---|---|---|
| A. backend-api | backend-api が、ブローカーの出すトークンを受けて検証する | BFF の authorizer が、Supabase の JWT を共有の秘密（HS256）で検証する |
| B. JADD STUDIO + backend-api | JADD STUDIO にログインし、そのサーバーが利用者の身元で backend-api を呼ぶ | JADD Studio の Supabase に Google でログインし、そのトークンを backend-api に送る |
| C. CLI | jadd-cli がログインし、backend-api を呼ぶ | backend-prod の Supabase に Google でログインし、anon キーを付けてトークンを更新する |

## 2. 結論

- **3 候補とも、3 つの経路をブローカーのトークンで組める。** 報告書の順位（Auth0 が本命）は変わらない。
- **差がいちばん出るのは、退職した社員を止めること（A・B）。** Okta での停止がブローカーに届いたとき、リフレッシュトークンまで止まることを文書で確かめられたのは Auth0 だけ。Zitadel Cloud と WorkOS は（不明）が残る。backend-api の側は、オフボーディングの同期をブローカーの状態に合わせれば補える。
- **B では、WorkOS の「1 回のログインで backend-api 宛てのトークンも得る」が確かめきれていない。** 得られなければ、JADD STUDIO のログインの作りが変わる。
- **C は、ローカルの転送（認可コード + PKCE）を既定にすれば、3 候補の差はほぼ消える。** デバイスコードだけで作るなら、Zitadel Cloud のリフレッシュトークンが弱点になる。
- **どの候補を選んでも、backend-api・JADD STUDIO・jadd-cli の設計で解く課題が残る。** CLI から起動した長時間タスクの資格情報もその 1 つ。この資料では扱わず、6 章に一覧を置く。

## 3. いまの姿（安全に関わる事実）

| 事実 | 根拠（origin/main、2026-10-16） |
|---|---|
| Supabase の JWT を、少なくとも 2 プロジェクト分（backend-prod と JADD Studio）受けている。何プロジェクト分を受けるかは `supabase/jwt-secrets` の中身で決まる | cdk-apps `apps/bff/lib/functions/supabase-authorizer-v3.ts:139-145,569-612`、mono-e2e `backend-api/docs/data-explorer.md:38` |
| `iss` を確かめていない。見ているのは `exp`・`aud === "authenticated"`・`email` の有無 | 同 `:224-227,235,238` |
| backend-api は利用者を `sub` だけで見分け、所有者や帰属の判定の多くを email で行う | mono-e2e `deps/auth.py:156-162`、`routers/garuda_datasets.py:136-152` ほか |
| 検証の結果のキャッシュが 2 段ある（BFF の authorizer と backend-api の各 300 秒）。失効が効くまで最大でおよそ 10 分 | `bff-stack.ts:100-107`、`deps/token_verifier.py:73,271-307` |
| 同じ人が、backend-prod と JADD Studio で別の `sub` を持つ | 設計メモの「ロール」の節 |

## 4. 経路ごとの適合性

凡例: ○ = 公開文書で確認できた / △ = 条件付き、またはこちらで補う / （不明） = 公開文書で確かめきれない（理由は 5 章）

### A. backend-api

| 論点 | Auth0 | Zitadel Cloud | WorkOS |
|---|---|---|---|
| backend-api 宛てのトークン（`aud`） | ○ API を登録して指定する | △ プロジェクトを `aud` に入れる scope で指定する。`aud` だけでは認可にならないと文書にあり、ロールか claim も確かめる | ○ resource indicator で指定する |
| 署名の検証（JWKS、RS256） | ○ | ○ | ○ |
| アクセストークンに email を載せる | △ 既定では入らない。Actions で独自の claim を足し、authorizer で `email` に読み替える | △ アクセストークンを JWT にし、claim を足す設定が要る | △ JWT テンプレートで足す |
| 退職した社員を止める（Okta での停止が届き、リフレッシュトークンが止まる） | ○ Okta からの SCIM の無効化で、block・セッション終了・リフレッシュトークンの失効まで行う | （不明） | △ Okta からの Directory Sync と Directory Provisioning で、セッションは失効する。リフレッシュトークンは（不明） |
| 人の API キーの発行と持ち主 | ○ ブローカーの JWT で発行し、持ち主を `(iss, sub)` で持つ | ○ 同左 | ○ 同左 |

- email は、社員なら Okta が管理しているので、所有者の判定に使い続けられる。
- 退職した社員のリフレッシュトークンがブローカーで止まらなくても、backend-api のオフボーディングの同期がブローカーの利用者の状態を見て API キーを失効させれば、backend-api の側では止まる。発行済みのアクセストークンは寿命（5〜15 分を目安に短くする）まで残る。

### B. JADD STUDIO + backend-api

| 論点 | Auth0 | Zitadel Cloud | WorkOS |
|---|---|---|---|
| 1 回のログインで、JADD STUDIO のセッションと backend-api 宛てのトークンを両方得る | ○ ログインの要求に `audience` を付ける | ○ プロジェクトの scope を付ける | （不明） |
| リフレッシュトークンの入れ替わり（JADD STUDIO はリースを取って更新している） | ○ 入れ替わりと、再使用の猶予を設定できる | ○ 寿命と無操作の寿命を設定できる | ○ 更新のたびに入れ替わる。今のリースの仕組みで受けられる |
| 退職した人の JADD STUDIO のセッションを止める | ○ バックチャネルログアウト（Enterprise） | △ バックチャネルログアウトはある。Okta からの無効化で送られるかは（不明） | △ バックチャネルログアウトは無い。イベントを読んで止める |
| 社員を Okta から入れる接続の費用 | ○ 企業接続の本数に数えない | ○ 組織の IdP として登録する | △ SSO の接続 1 本として $125/月 |


### C. CLI

| 論点 | Auth0 | Zitadel Cloud | WorkOS |
|---|---|---|---|
| ローカルの転送（認可コード + PKCE、`127.0.0.1` で受ける。`gh`・`gcloud` と同じ形） | ○ 見込み（Native アプリ） | ○ 見込み（Native アプリ） | （不明） |
| デバイスコード（ブラウザの無い環境向け。RFC 8628） | ○ | ○ | ○ CLI Auth |
| デバイスコードでのリフレッシュトークン | ○ `offline_access` と API の「Allow Offline Access」の両方が要る | △ 期限が切れるたびにログインし直す可能性がある（要検証） | ○ |
| デバイスコードでの backend-api 宛ての `aud` | ○ `audience` を指定する | △ プロジェクトの scope | （不明） |
| 秘密を持たない公開クライアント（anon キーの廃止） | ○ | ○ | ○ |

- 既定をローカルの転送にし、SSH 先などブラウザの無い環境だけデバイスコードを使えば、3 候補の差はほぼ消える。
- この経路は、人がその場にいる対話の CLI に限る。CLI から起動した長時間タスクの資格情報は、6 章で扱わないことに置く。

## 5. 不明とした理由

| 候補 | 経路・論点 | 理由 |
|---|---|---|
| Zitadel Cloud | A・退職した社員を止める | 2023 年に「無効化してもリフレッシュトークンが失効しない」脆弱性（CVE-2023-22492）を直している。直した後の振る舞いと、SCIM の無効化との関係が文書に無い |
| Zitadel Cloud | B・退職した人のセッション | バックチャネルログアウトの文書は SSO のセッションが終わったときの動きとして書かれていて、無効化で送られるかの記載が無い |
| Zitadel Cloud | C・デバイスコードでのリフレッシュトークン | 公式の scope の文書は「`offline_access` は認可コードの流れだけ」とし、別の解説は使えるとしていて食い違う |
| WorkOS | A・退職した社員を止める | Directory Provisioning の無効化でセッションを失効させるとあるが、リフレッシュトークンの記載が無い |
| WorkOS | B・1 回のログインで両方得る | resource indicator の記載は Connect（他社のアプリ向けの OAuth）の文書にあり、JADD STUDIO が使う AuthKit のセッションのトークンで使えるかを確かめきれない |
| WorkOS | C・ローカルの転送 | 本番の環境で `127.0.0.1` への転送を許すかの記載が見当たらない |
| WorkOS | C・デバイスコードでの `aud` | CLI Auth の文書に記載が無い |

## 6. この資料で扱わないこと（アプリケーションの設計の課題）

どの候補を選んでも答えが変わらず、backend-api・JADD STUDIO・jadd-cli の設計で解く課題。ここでは一覧だけを置き、議論は別に行う。

| 課題 | 経路 | 今の動き |
|---|---|---|
| authorizer を JWKS 対応にし、`iss` と `aud` の許可リストを入れる。移行の間は Supabase とブローカーを `iss` で見分ける | A | 設計メモの段階 3（`iss` の対応表）が土台。未着手 |
| 共有の署名鍵（`jwt_secret_*`）の撤去 | A | ブローカーに移れば、設計メモの「JWT 署名鍵の作り直し」は要らず、撤去で済む |
| `sub` が変わる。`requested_by_id`・API キーの持ち主など、`sub` を保存している列の対応表を作る | A・B・C | ブローカーの決定待ち |
| backend-prod のオフボーディングの同期を、Google のディレクトリからブローカーの利用者の状態に替える | A | 同期そのものは 10/9 に本番で有効（cdk-apps #2122・#2123）。置き換えはブローカーの決定待ち |
| 検証の結果のキャッシュ 2 段（各 300 秒） | A・B | BFF の撤廃（安本さん）で 1 段になる見込み。BFF に残るのは `/v1/{proxy+}` と authorizer だけ（10/16 の cdk-apps #2186 で旧ルートを撤去済み） |
| JADD STUDIO のログイン・セッションの更新・自動凍結を、ブローカー向けに作り直す | B | ブローカーの決定待ち |
| jadd-cli のログインを、ローカルの転送とデバイスコードに替える。手動ログイン用の Lambda（`apps/jadd-cli-auth-callback`）を撤去する | C | ブローカーの決定待ち。設計メモの段階 2（jadd-cli の版上げ）と同じ版で出せる |
| **CLI から起動した長時間タスクの資格情報。** 手元や Slurm で走るタスクが途中で backend-api を呼ぶと、アクセストークンが切れて失敗する。いまは `.env` のリフレッシュトークンをジョブの中で更新しているが、複数のジョブが同じトークンを持つと入れ替わりで失敗する。人の API キーで走らせる形が素直 | C | 設計メモの段階 5（Slurm・ローカル実行で投入者の人のキーを使う）と重なる。backend-api が起動して AWS の中で走るタスクは、ジョブの IAM の role で動くので対象外 |
| リフレッシュトークンの保存先（`~/.jadd/cli/` の 0600 のファイル）を、OS のキーチェーンに移すか | C | 未定 |
| `supabase/jwt-secrets` に入っている `jwt_secret_*` の数と、それぞれどのプロジェクトのものか | A | 安本さん・MLOps1 に確かめる |
| `iss` を見ていないので、JADD Studio の JWT からも `/v1/api-keys` で API キーを発行できるように見える。そのキーは backend-prod のオフボーディングの同期の対象から漏れる | A | 安本さん・MLOps1 に確かめる |

## 7. 検証テナントで確かめること

- Okta で停止した社員について、ブローカーがリフレッシュトークンを止めるか（Zitadel Cloud・WorkOS）
- Okta で停止した社員に、バックチャネルログアウトが送られるか（Zitadel Cloud）
- AuthKit のセッションで、backend-api 宛てのトークンを得られるか（WorkOS）
- `127.0.0.1` への転送を本番の設定で許すか（3 候補）
- デバイスコードでリフレッシュトークンが出るか（Zitadel Cloud）
- アクセストークンに email を載せ、authorizer の形で検証できるか（3 候補）

## 8. 参照

### コード（origin/main、2026-10-16）

- mono-e2e: `projects/api/backend-api/deps/auth.py`、`deps/token_verifier.py`、`routers/api_keys.py`、`services/offboarding_sync.py`、`docs/data-explorer.md`、`packages/jadd-cli/src/jadd/supabase_oauth.py`
- cdk-apps: `apps/bff/lib/functions/supabase-authorizer-v3.ts`、`apps/bff/lib/bff-stack.ts`、`apps/jadd-cli-auth-callback`
- jadd_studio3: `app/api/auth/supabase/route.ts`、`lib/utils/auth/SessionStore.ts`、`lib/utils/auth/SupabaseTokenRefresher.ts`

### ブローカーの文書

- Auth0: Configure Inbound SCIM https://auth0.com/docs/authenticate/protocols/scim/configure-inbound-scim
- Auth0: Device Authorization Flow https://auth0.com/docs/get-started/authentication-and-authorization-flow/device-authorization-flow
- Auth0: Call your API using the Device Authorization Flow https://auth0.com/docs/get-started/authentication-and-authorization-flow/device-authorization-flow/call-your-api-using-the-device-authorization-flow
- Zitadel: Claims https://zitadel.com/docs/apis/openidoauth/claims
- Zitadel: Scopes https://zitadel.com/docs/apis/openidoauth/scopes
- Zitadel: Device Authorization https://zitadel.com/docs/guides/integrate/login/oidc/device-authorization
- Zitadel: Back-channel logout https://zitadel.com/docs/guides/integrate/back-channel-logout
- Zitadel: aud の検証の注意 https://help.zitadel.com/security-best-practices-validating-audience-aud-claims-in-zitadel-access-tokens
- Zitadel: CVE-2023-22492 https://nvd.nist.gov/vuln/detail/CVE-2023-22492
- WorkOS: CLI Auth https://workos.com/docs/authkit/cli-auth
- WorkOS: JWT templates https://workos.com/docs/authkit/jwt-templates
- WorkOS: Connect token claims https://workos.com/docs/authkit/connect/token-claims
- WorkOS: Directory Provisioning https://workos.com/docs/user-management/directory-provisioning
