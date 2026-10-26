# M2M 認証の手法の確立（車載装置・CI 用マシン）

- 開始: 2026-10-15
- 状態: **一般論の整理と、関係者の動きの把握の段階**。改善案は岩政さん・安本さんと歩調を合わせてから詰める
- 所属: project:m2m-auth（2026-10-26 に `~/docs/workstream/` から移した）
- 関連: [IdP の役割分担の検討](../../idp-broker/workstream/idp-auth0-role-division.md)（退職の同期・ロールの持ち場・BFF 撤廃後の入口が共通の論点）

## 背景

- 車載装置や社内設置の CI 用マシンが、backend-api などを機械として呼んでいる。車載装置はアメリカへも行く。
- いまは**無期限のサービスキー**を発行して使っている。**1 つのキーを複数の機体で使い回している**ので、これをなんとかしたい。

### 前提（2026-10-15 に確定）

- 認証先は**主に backend-api**。今後増えるかもしれないので、**手法を確立しておきたい**。
- **機体を識別し、さらに実行できる操作を制御する**必要がある。
- 機体に対するアクセス制御の**台帳の管理方法は未策定**。
- 機体の数はせいぜい **100 台程度**。1000 台規模に増えるころには、その費用も払える見込み。

## 一般的なやり方

一言でいうと、**機械ごとに別々の身元を持たせ、その身元を短命のトークン（資格情報）に交換してから API を呼ぶ**。

### 原則

| 原則 | 中身 | 無期限の共有キーだと |
|---|---|---|
| 1 台 1 身元 | 機体・マシンごとに別の資格情報を持たせる | 1 台が盗まれても全台を替えるしかない。ログから「どの機体か」も分からない |
| 秘密を送らない | 公開鍵の仕組みで「鍵を持っていること」だけを証明する | キーそのものが毎回ネットワークを流れ、漏れればそのまま使われる |
| 鍵を取り出せなくする | 秘密鍵は TPM やセキュアエレメントに置き、ファイルで持たない | ストレージを抜かれる、イメージを複製されると終わり |
| 短命のトークンで呼ぶ | 長期の身元は「トークンを取る」ことにだけ使い、API は数分〜1 時間のトークンで呼ぶ | 漏れたキーがいつまでも使える |
| 最小権限・失効できる | トークンに対象（audience）と権限（scope）を絞って入れる。1 台単位で止められる | 何でもできるキーを、止める手段なしに配っている |

### 資格情報の強さの段階

| 段階 | 方式 | 例 | 漏えいへの強さ |
|---|---|---|---|
| 0 | 静的な API キー（無期限・共有） | **いまの形** | ✗ |
| 1 | 1 台ごとの秘密（client secret や API キー）。OAuth2 Client Credentials なら短命トークンも | 安本さんの号車のキー（`jadv_`）、Auth0 の M2M | △ 秘密は送信され、ファイルにもある |
| 2 | 1 台ごとの非対称鍵で署名した JWT（`private_key_jwt`、RFC 7523） | Auth0 / Okta / Entra | ○ 秘密が送信されない |
| 3 | 1 台ごとの X.509 証明書（mTLS、RFC 8705。または IoT credential provider） | AWS IoT Core、Azure IoT DPS | ○ |
| 4 | 段階 2〜3 の鍵を TPM・セキュアエレメントに入れる | 車載・IoT の標準的な形 | ◎ |
| 別系統 | 秘密を持たない。基盤が出す身元トークンを交換する（Workload Identity Federation） | GitHub Actions の OIDC、Vercel OIDC、Databricks の UC service credential | ◎ 配る秘密が無い |

### 典型的な流れ

```
[機械] 長期の身元（証明書 / 署名鍵 / 基盤の OIDC トークン）
   │  ① 身元を証明する
   ▼
[発行役] 台帳を見る（有効か・失効していないか）
   │  ② 短命の資格情報を出す（機体 ID・権限入り）
   ▼
[機械] ── ③ 短命の資格情報で呼ぶ ──▶ [API] 署名・期限・対象・権限を検証する
```

- 止めるときは台帳で 1 台を無効にする。出ている資格情報も期限（数分〜1 時間）で切れる。
- 呼び先が増えても、各呼び先は手元で検証するだけでよい（JWT なら JWKS、IAM なら SigV4 と resource policy）。**「手法を確立したい」という要件にはここが効く。** 呼び先ごとに backend-api へ問い合わせる作り（API キーの照合）は、呼び先が増えるほど重くなる。

### 対象別の定石

- **CI**: GitHub Actions なら（self-hosted runner でも）ジョブごとの OIDC トークンで IAM role を引き受ける。それ以外ならマシンごとの非対称鍵。
- **車載装置**: 1 台 1 証明書。キッティングで機体の中で鍵を作り（できれば TPM の中）、自前の CA か IoT のサービスで証明書を入れる。
  - 持ち出しと盗難: 鍵を取り出せない作りの価値が大きい。盗まれた機体は台帳で 1 台だけ止める。
  - 回線が途切れる: 短命の資格情報が切れても、つながったときに取り直せる作りにする。長期の身元（証明書）は数か月〜年単位にし、失効は台帳（サーバー側の拒否リスト）で行う。
  - 時計のずれ: 期限の検証は時刻に依存する。時刻が取れない状態も想定する。
  - 国外: 発行役の拠点・遅延・つながらないときの振る舞いを考える。暗号の輸出規制（EAR）は一般的な TLS なら問題になりにくいが、機材の持ち出しの運用として一度確かめる。
- **AWS IoT の credential provider（証明書 → 一時的な IAM 資格情報）は、呼び先が IAM（SigV4）で受けるならそのまま使える。** 実機にはすでに全台共通の証明書が入っていて、S3・CodeArtifact の読み取りに使われている。API の呼び出しでは tern-api がこの形に移りつつある（下の「車載装置の IoT 証明書の基盤」）。

### 台帳の持ち方の選択肢

| 方式 | 長所 | 短所 |
|---|---|---|
| A. backend-api の DB ＋ admin の API・CLI（安本さんのメモの案） | 発行・失効がすぐ効く。キッティングの手順に組み込みやすい | 変更のレビューが残らない。DB の接続文字列を読める主体は行を直接足せる |
| B. git で宣言して適用する（identity リポ・cdk-apps の invoker と同じ流儀） | PR でレビューでき、履歴が残る。100 台なら十分回る | 適用がマージ待ちになる。盗難時の即時失効には別の手段が要る |
| C. 専用のレジストリ（AWS IoT の Thing 等） | 機体管理の機能が揃っている | 特定の基盤に寄る |

いまの考え: **定義（権限の束）はコード、機体と割り当ては git で宣言、緊急の失効だけは即時の操作**の組み合わせ。

## 関係者の動き（2026-10-15 時点）

コンポーネントごとに「方針」「やった（誰が）」「これからやる」でまとめる。名前は敬称略。

### 1. BFF（cdk-apps の apps/bff）

**方針**: **撤廃する。** ルートを 1 本ずつ backend-api に移し、旧ルートの利用が 0 件になったのを確かめてから撤去する（進め方は mono-e2e #6161 の本文）。

**やった（誰が）**

| 内容 | 誰が | PR |
|---|---|---|
| `/rlogvis`・`/lidar-matching`・`/jadd` を撤去 | 安本 | cdk-apps #2091・#2013 |
| 旧ルートの利用を数えるため、アクセスログを付けた | 安本 | cdk-apps #2111・#2114 |
| `/video`・`/trajectory-visualizer` を backend-api に移し、旧ルートと中継先を撤去 | 安本 | mono-e2e #6161・#6299、cdk-apps #2166〜#2168 |

**これからやる**
- 残りのルート（3dgs・data-explorer）を移す。STUDIO の資料ではキーワード検索も BFF 固有のエンドポイントとして残っている。
- 【未決】service key 廃止のメモで BFF の authorizer に持たせていた役割（API キーの検証、号車・サービスのキーの経路制限、`iss` の確認、`.internal` のメールの拒否）を、撤廃後どこに移すか。

### 2. backend-api（mono-e2e）

**方針**: **唯一の入口として、主体ごとに検証・認可・記録する。** 静的な共有キー（service key）をなくし、人・号車・サービスは主体ごとの API キー、AWS 内のジョブは IAM で受ける（安本さんの設計メモ）。

**やった（誰が）**

| 内容 | 誰が | PR |
|---|---|---|
| 全リクエストを監査の行（1 行の JSON）で残す | 伊藤 | #6022・#6080 |
| authorizer の invoke に上限。経路の判定を API Gateway が照合したリソースで行う | 安本 | #6132・#6134 |
| 公開経路以外からの依頼者の自己申告を拒否（`require_public_principal`） | 安本 | #6161 |
| backend-prod のオフボーディング同期（Google で停止・削除された人を ban し、個人の API キーを失効） | 安本 | #6139、cdk-apps #2108・#2116・#2122 |
| service key 廃止の設計メモ | 安本 | 設計メモ（10/5）。未実装 |
| イメージの依存を lock どおりに入れる | 伊藤 | #6076（未マージ） |

**これからやる**
- service key 廃止の実装（メモの 8 段階: 土台 → jadd-cli → authorizer → シナリオテスト → サービスのキー → 号車 → enforce → 削除）
- オフボーディング同期を本番で有効にする（専用の Google アカウントと委任の準備待ち）
- メモの「残るリスク」: JWT 署名鍵の作り直し（JWKS への移行）、`backend-prod` を読める 39 主体の整理
- 【未決】STUDIO のロールを backend-api でも効かせるか（メモでは範囲外）

### 3. JADD STUDIO

**方針**: API ルートは `defineRoute` で権限・入力・応答を宣言し、backend-api の呼び出しはロールごとのホワイトリストで絞る。外部サービスへは静的なキーでなく IAM（Vercel OIDC）で接続する。退職・停止した人は自動で止め、操作は監査ログに残す。

**やった（誰が）**

| 内容 | 誰が | PR |
|---|---|---|
| `defineRoute` の導入、旧い形を ESLint で止める、`server.md` | 伊藤 | #1042・#1044・#1106 |
| backend-api の呼び出し基盤とロールごとのホワイトリスト | 伊藤 | #1053・#923・#1101 |
| セッションをサーバー側に持ち、ロールを 10 分ごとに DB と突き合わせる | 伊藤 | #1015 |
| 利用者と cron の操作監査ログ（ガイドラインは伊藤） | 塚本 | #1054（#1075） |
| メールユーザーの TOTP 必須化 | 塚本 | #1040 |
| ログイン CSRF・再設定後のセッション残存・長大パスワードを塞ぐ | 伊藤 | #1132 |
| ユーザーの凍結、Google で削除・停止された人の自動凍結、本番での一斉点検 | 伊藤 | #1150・#1162・#1164 |
| Databricks SQL のエスケープの穴を塞ぐ | 山下・伊藤 | #1051・#1052・#1066 |
| `/jump` の未認証アクセスとオープンリダイレクトを塞ぐ | 山下 | #1062 |
| 廃止する Supabase tuscenes-prod への接続を削除 | 安本 | #1067 |
| 動画・きしめんを BFF から backend-api の `/v1` へ切り替え | 安本 | #1159・#1165 |
| tern を API キーから SigV4（Vercel OIDC の role）に替えた | Devin（岩政の依頼） | #1161、cdk-apps #2159 |

**これからやる**
- Vercel から `VALHALLA_TURING_API_KEY`・`TERN_API_KEY` を消す（#1161 のリリース後）
- BFF の残りのルートの移行に合わせて、呼び出し先を切り替える
- 【未決】協力会社（Entra ID）を Auth0 経由で入れる（[IdP の資料](../../idp-broker/workstream/idp-auth0-role-division.md)）
- 【課題】ホワイトリストは STUDIO の中だけで効く。自分でトークンを取れば backend-api を直接呼べる（`docs/guidelines/backend-api.md`）

### 4. 車載装置用 M2M

**方針**: 共有の秘密をやめ、機体ごとに身元を持たせる。**backend-api は、安部さんが進めている 1 台 1 証明書の体制が整ってから、実機の IoT 証明書の基盤に乗せる**のを第一候補にする。急ぎではないので、共通の証明書で先につなぐことはしない（2026-10-15 の伊藤の判断。関係者とはまだ合わせていない）。
- 乗り方: デバイス証明書 → IoT credential provider → backend-api 用の IAM role → backend-api は SigV4 で受ける。tern-api と同じ型（下の「車載装置の IoT 証明書の基盤」）
- 安本さんの号車ごとの API キー（`jadv_`。未実装）は、1 台 1 証明書を待つ間のつなぎとして要るかを、安本さんと決める

**いまの状態**

| 呼び先 | 何のためか | 認証 | 機体の区別 |
|---|---|---|---|
| backend-api（webd・op-ui） | 実機の画面・機能から backend-api を使う | 全車共通の service key（`service_key_openpilot`。edge-ansible が `/etc/opt/turing/jadd_service_key` に配る） | できない |
| S3（`tuscenes-model`・`maps`・`openmaptiles`） | モデルの wheel・地図の取得 | 全台共通の aws-access 証明書（2026-03 から。80 台に 1 枚、期限 2050 年）→ `jetson-assume-role-alias` → `jetson-aws-access-role` | できない |
| CodeArtifact（`e2e/internal`） | 社内パッケージの取得（Gemfury からの移行） | 上と同じ証明書・role（読み取りの権限を足しただけ） | できない |
| tern-api（navd） | 経路の取得（directions） | 全台共通の tern-api 証明書（新設）→ `jetson-tern-api-alias` → `jetson-tern-api-role`（`GET /mapbox/directions/*` だけ）。CDK への取り込み（#2154）は Draft | できない |
| IoT Core（MQTT・Device Shadow） | Mender と連携する常駐プロセス（`iot-core-agent`） | 全台共通の mender 証明書（IoT ポリシー `mender-dev`） | できない |

- 3 枚の証明書は、どれも OTA で全台に配る。Mender で機体を accept すると IoT Core に Thing ができ、その時点で Lambda が 3 枚を Thing に紐付ける（安部さん。`OtaCertificateAttachments`）。

**やった（誰が）**

| 内容 | 誰が | PR |
|---|---|---|
| credential provider（`jetson-assume-role-alias` → `jetson-aws-access-role`）と全台共通の証明書を、手作業で作った（S3 用） | 未確認（2026-03-05 作成） | ― |
| CodeArtifact を作り、Gemfury から同期した | 岩政 | cdk-apps #1939・#1955 |
| credential provider を CDK に取り込み、実機の role に CodeArtifact の読み取りを付けた（MLOP-2598 の一部） | 岩政 | cdk-apps #2003・#2026・#2027 |
| 実機の証明書・Mender 連携・証明書のポリシーと、Thing ができたときの証明書の紐付け（Lambda）を CDK に取り込んだ | 安部 | cdk-apps #2052・#2057・#2110・#2152 |
| 実機の uv が証明書から CodeArtifact のトークンを都度取る（keyring） | 鈴木 達也 | openpilot #5721（承認済み・未マージ）、edge-ansible #531 |
| tern-api の IAM 版 API・実機からの invoker、tern-api 専用の IoT ポリシー・role alias・role | 岩政 | cdk-apps #2081・#2089・#2090 |
| 1 台 1 証明書の最終形を描いた（下の「1 台 1 証明書への道筋」） | 安部 | ―（2026-10-15 のヒアリング） |
| 号車ごとの API キーとスコープの設計 | 安本 | 設計メモ（未実装） |

**これからやる**
- tern-api 証明書の CDK への取り込みと Thing への紐付け（安部。cdk-apps #2154、Draft）、OTA での配布（edge-ansible #552。状態は未確認）
- openpilot の navd を証明書 → SigV4 で呼ぶようにする（openpilot #5940、未マージ。API キーでの呼び直しを残し、その次の OTA で消す）
- 1 台 1 証明書の体制を作る（安部。**時期は未定**）
- 安本さんと、`jadv_` を実機に配るか（1 台 1 証明書までのつなぎにするか、号車は証明書を待つか）を決める（伊藤）
- BFF の撤廃後の backend-api の入口に、あとから実機を IAM で受ける余地を残してもらう（安本さんと調整。伊藤）
- 【未決】backend-api で、呼んだ機体をどう見分けるか（**未定**。role のセッション名・`userArn` に証明書 ID や Thing 名が載るか）
- 【未決】用途ごとの止め方。いまは貸出で tern-api 証明書を実機から消して tern-api だけ止めている。デバイス証明書が 1 枚になったら、Thing の属性やグループ、ポリシー変数などで止める形に変える必要がある。backend-api 用の role もこの仕組みに乗る
- 【未決】機体の台帳をどこに置くか（Thing・CDK・backend-api の DB）。キッティング・封印・貸出の手順を 1 本にする

### 車載装置の IoT 証明書の基盤（2026-10-15 に裏取り・ヒアリング）

GitHub の名前: 岩政さん = colum2131、安部 敦さん = piste-jp、鈴木 達也さん = tsuzuki16。

#### 成り立ちと用途

**この基盤は M2M の構想のために作られたものではない。** 実機が AWS のリソースを読むために、もともとあったものである。用途が後から足されてきた。

```
OTA で全台に配る 3 枚の証明書（どれも全台共通）。Mender で accept → Thing ができたら Lambda で Thing に紐付ける

aws-access 証明書（2026-03-05 に手作業で作成）
  └─ role alias jetson-assume-role-alias（ota / ap-northeast-1）
       └─ jetson-aws-access-role（1 時間の一時的な資格情報）
            ├─ S3: モデルの wheel・地図（当初からの用途）
            └─ CodeArtifact: 社内パッケージ（2026-10、岩政さんが追加）

tern-api 証明書（新設。CDK への取り込みは #2154）
  └─ role alias jetson-tern-api-alias
       └─ jetson-tern-api-role（GET /mapbox/directions/* だけ。岩政さん）

mender 証明書（iot-core-agent の MQTT・Device Shadow 用。IoT ポリシー mender-dev）
```

| 用途 | 目的 | 経緯 |
|---|---|---|
| S3 | 実機がモデルの wheel（実験で差し替えるもの。`exp_utl.py` が `s3://tuscenes-model-…/…whl` から取る）と地図を読む | 2026-03 から稼働。作った人は未確認 |
| CodeArtifact | **社内パッケージの置き場を Gemfury（共有トークン）から CodeArtifact（IAM）へ移す**（MLOP-2598）。実機も GitHub の資格情報を持たずに取れるようにする | 岩政さんが CodeArtifact を作り（9/17〜）、実機の role に読み取りを足した（10/1）。**証明書は増やしていない**。実機側は鈴木さんの openpilot #5721（未マージ）と edge-ansible #531 |
| tern-api | navd が directions を共有の API キーでなく SigV4 で呼ぶ | 岩政さん（10/8〜）。**実機から API を呼ぶ M2M として、この基盤を使った初めての例**。貸出で単独で止められるよう、証明書と role を分けた |

- CodeArtifact に置くのは、推論の枠組みと依存（`modelcore`、aarch64 向けの `tensorrt`・`onnxruntime-gpu`、`navi-processor` など）と、固定したモデルの wheel（`modelcore-fullcombo`）。実験で差し替えるモデルは S3 から取る。
- 実機が CodeArtifact から取るのは、コンテナの中で `uv sync` や `exp_utl.py` を実行したとき（必要な分をその場で落とす）。証明書を配る OTA（Mender）とは別の話。
- backend-api とは、いまのところ何もつながっていない（cdk-apps の backend-api・bff、mono-e2e の `projects/api` に言及は無い）。

#### 1 台 1 証明書への道筋（安部さん、2026-10-15 のヒアリング）

1 台 1 証明書の体制は**安部さんが進めている**（岩政さんではない）。コードや資料には「今後の改善点」とだけあり、最終形はヒアリングで分かった。

**最終形**
1. キッティングの初めに、全台共通の証明書を 1 枚だけ配る。
2. 共通の証明書には、**証明書を発行できる role だけ**を付けておく。
3. キッティングの途中で、機体が共通の証明書を使って固有のデバイス証明書を作り、証明書と秘密鍵を機体のローカルに保存する。
4. Mender で accept して IoT Core に Thing ができた時点で、Lambda がその Thing とデバイス証明書を紐付ける（いまの紐付けの仕組みと同じ）。

- AWS IoT の「claim 証明書による Fleet Provisioning」と同じ形。共通の証明書が漏れても AWS のリソースには直接届かず、デバイス証明書も Mender の accept（人の確認）を経て Thing に紐付くまでは使えない、という作りになる。
- **時期は未定。** 呼び先で機体を見分ける方法も**未定**。

**まだ確かめていないこと**
- 秘密鍵を機体の中で作るか（`CreateCertificateFromCsr`。鍵が外に出ず、将来 TPM に移せる）、AWS に作らせるか（`CreateKeysAndCertificate`）
- いまの 3 枚（mender・aws-access・tern-api）と用途ごとの role alias を、最終形でどう持つか（デバイス証明書 1 枚に寄せるか、用途ごとの止め方をどうするか）
- 共通の証明書が漏れたときの扱い（発行時の確認 pre-provisioning hook を入れるか）
- 廃車・貸出の終了でデバイス証明書をどう止めるか（Mender の decommission では Thing が消えない。#2154）

#### backend-api をこの基盤に乗せる案

「証明書がすでに全台に入っているので、その配布の基盤に乗って backend-api への経路を作るのがよいのでは」という話が上がっている（2026-10）。

**利点**
- 証明書の配布・Thing の作成・紐付けの仕組み（OTA・Mender・`OtaCertificateAttachments`）がすでに動いている。新しい秘密を配らずに済む。
- tern-api で「用途ごとに role を分け、呼び先の resource policy で経路を絞る」型ができている。backend-api 用の role を足せば同じ形になる。
- 秘密を送らない（SigV4）・短命（1 時間）・権限は CDK のコードで PR レビューされる、が最初から満たせる。

**構想との照合**

| 構想の原則・要件 | いまの共通の証明書に乗せた場合 | 安部さんの最終形に乗せた場合 |
|---|---|---|
| 秘密を送らない | ✅ SigV4 | ✅ |
| 短命の資格情報 | ✅ 1 時間 | ✅ |
| 最小権限 | ✅ 用途ごとに role を分ける | ✅（用途ごとの止め方は要設計） |
| 手法の再利用 | ✅ tern-api と同じ型 | ✅ |
| 1 台 1 身元 | ❌ 全台共通 | ✅ |
| 1 台単位の失効 | ❌ 証明書を無効にすると全台が止まる。期限は 2050 年 | ✅ その機体の証明書を INACTIVE にする |
| 機体の識別 | ❌ 分かるのは role まで | 未定（`userArn` に証明書 ID や Thing 名が載るか） |
| 機体ごとの操作の制御 | ❌ role 単位 | 機体の識別ができれば backend-api の側でできる |
| 鍵を取り出せなくする | ❌ 全台に同じ鍵のファイル | △ 機体ごとの鍵のファイル（機体の中で作るなら将来 TPM に移せる） |
| 台帳 | △ Thing は台数分ある（126 個）が、機体と権限の対応は持っていない | △ Thing と Mender の accept が台帳の芯になる。権限の対応は別途 |
| 受け口 | △ backend-api の公開経路は IAM を受けていない（`/internal` だけ）。BFF の撤廃で作り直す検証役と一緒に設計する | 同左 |
| 国外・回線断 | △ credential provider は ap-northeast-1 だけ、backend-api は us-west-2。SigV4 は時刻のずれに弱い | 同左 |

**評価**
- **安部さんの最終形に乗せれば、前提の「機体を識別し、操作を制御する」まで届く見込みがある。** 残る穴は「呼び先で機体を見分ける方法」で、ここは安部さんの側でも未定。backend-api の要件として伝える必要がある。
- 急ぎではないので、**最終形が整ってから乗る**のが最も手戻りが少ない。共通の証明書で先につなぐと、移行を 2 回することになる。
- ただし最終形の**時期が未定**なので、待つ間も全車共通の無期限の service key が残る。漏えいなどで急ぐ必要が出たら、共通の証明書で用途別の role を使う（機体の区別は無いが、キーは無くせる）か、`jadv_` をつなぎにする。
- 待つ間に固まってしまわないよう、押さえておくこと:
  1. 安部さんに、backend-api が乗りたいこと、機体の識別が要件であることを伝える
  2. 安本さんと、`jadv_` を実機に配るかを決める
  3. BFF の撤廃後の backend-api の入口に、IAM を受ける余地を残す

### 3 者を並べて見えること

| 流れ | STUDIO | 安本 | 岩政 |
|---|---|---|---|
| 静的な秘密 → 基盤の身元（IAM） | tern を Vercel OIDC に | シナリオテストを IAM に（メモ） | tern-api の全経路、Gemfury → CodeArtifact |
| 入口を 1 つにして中で守る | `defineRoute`・ホワイトリスト | BFF を撤廃して backend-api に集約 | API Gateway の resource policy |
| 退職したら止める | #1162（STUDIO の Supabase） | #6139（backend-prod の Supabase） | ― |
| 主体ごとに記録する | 監査ログ（#1054） | ―（監査の行 #6022 は伊藤） | アクセスログ（`userArn`） |

方向は「秘密を配らず、主体ごとに身元を持たせ、入口で絞り、記録を残す」でそろっている。

## 歩調を合わせる論点

安部さん・岩政さん・安本さんと話すときの論点。

1. **backend-api は、安部さんの 1 台 1 証明書の体制が整ってから IoT 証明書の基盤に乗せる、でよいか**（伊藤の第一候補）。安本さんの `jadv_` を、それまでのつなぎとして実機に配るか。backend-api 用の role を足すときの持ち場（ota は安部さん、role と resource policy は backend-api の側か）。
2. **安部さんの最終形に、backend-api の要件を入れてもらう**: 呼び先で機体を見分けられること（未定）、用途ごとに止められること、時期の目安（未定）。秘密鍵を機体の中で作るか。
3. **機体の台帳をどこに置くか**（Thing・CDK・backend-api の DB）。封印・貸出の手順も含める。
4. **BFF の撤廃後、backend-api の入口で何を受けるか**（JWT・API キー・IAM のどれを、どの authorizer で）。入口が backend-api の API Gateway になるなら、IAM の resource policy で絞れる。
5. **CI は GitHub OIDC に寄せるか**（岩政さんの role がすでにある）。
6. IdP の検討との接点: 退職の同期が 2 本ある（STUDIO と backend-prod）。ロールが STUDIO と backend-api（`user_role`）の 2 か所にできる。協力会社を backend-api まで通すなら揃える必要がある。

## 調べること（未確認）

- [ ] 号車のハードウェアに TPM・セキュアエレメントがあるか。OS とキッティングの担当
- [ ] 社内設置の CI 用マシンの実体（GitHub Actions の self-hosted runner か）
- [ ] edge-ansible #552（tern-api 用の証明書と秘密鍵の配布）・#531（CodeArtifact 用の `aws_credential_process.py`）の状態と、秘密鍵をどこに置いて配っているか
- [ ] 2026-03-05 に credential provider と全台共通の証明書を作ったのは誰か（基盤の持ち主）
- [ ] IoT credential provider で得た資格情報から、呼び先で機体（Thing 名・証明書 ID）を取り出せるか（role のセッション名・`userArn` に何が入るか）。安部さんの側でも未定
- [ ] Auth0 を発行役にする場合: `private_key_jwt` が使えるプラン、アプリ数の上限、M2M トークン数の数え方

## 参照

- 安本さんの設計メモ「service key 廃止の設計メモ」（2026-10-05）: `~/docs/backend-api/backend-api-sayonara-service-key.html`（ローカルの HTML）。中にあったリンク: https://claude.ai/code/artifact/d636aaec-438b-40bc-8612-e6309b07c0a5 （最新版かは未確認）。原本は Claude Docs とある
- openpilot #5940（navd を証明書 → SigV4 で呼ぶ）、cdk-apps #2154（tern-api 用の証明書）
- Gemfury → CodeArtifact 移行（MLOP-2598）: cdk-apps #1939・#2003・#2026・#2027、openpilot #5721（実機は証明書から CodeArtifact のトークンを取る）、`cdk-apps/apps/codeartifact/README.md` の「実機」
- cdk-apps: `apps/ota/README.md`（IoT credential provider、tern-api 用の証明書）、`apps/ota/docs/iot-credential-provider.md`、`apps/tern-api/README.md`（実機・JADD Studio から呼ぶ）
- mono-e2e: `projects/api/backend-api/docs/offboarding.md`
- JADD STUDIO: `docs/guidelines/backend-api.md`、`docs/workstream/external-viewer-auth.md`、`docs/workstream/offboarding-sync.md`
- RFC 7523（JWT によるクライアント認証）、RFC 8705（mTLS と証明書に紐づくトークン）

## 進捗と引き継ぎ

- 2026-10-15: 起票。M2M の一般的なやり方（原則・資格情報の段階・対象別の定石・台帳の持ち方）を整理した。前提（認証先は主に backend-api、機体の識別と操作の制御、台帳は未策定、100 台程度）を確定した。
- 2026-10-15: 既存の動きを調べた。安本さんの service key 廃止の設計メモ（未実装）、岩政さんの IoT 証明書 → IAM の経路（S3・CodeArtifact は稼働中、tern-api は受け口まで。証明書は全台共通）、安本さんの BFF 撤廃、STUDIO の守りの強化と接続先の変更（tern の Vercel OIDC 化 #1161 を含む）。コンポーネントごとの「方針・やった・これからやる」にまとめた。
- 2026-10-15: 岩政さんの車載装置向けの作業を詳しく調べ、「進捗と構想とのギャップ」を足した。型（秘密を送らない・短命・最小権限・コードで管理）は実現済みで、ギャップは 1 台ごとの身元・識別・失効・鍵の保護に集中している。openpilot #5940 と edge-ansible #552 で実機への切り替えが進行中。cdk-apps の piste-jp さんを別の人として書いていたが、安部 敦さんだったので直した。
- 2026-10-15: 伊藤さんから、岩政さんの IoT の作業は backend-api の M2M ではなく別の目的（CodeArtifact への経路）だったこと、その証明書の基盤に乗って backend-api への経路を作る案が上がっていることを聞き、コードと PR で裏取りした。直した点: (1) 証明書と credential provider は 2026-03 に S3 用として手作業で作られたもので、CodeArtifact のために増えてはいない。(2) CodeArtifact に置くのは推論の枠組み・依存と固定のモデルで、実験で差し替えるモデルは S3 から取る。(3) CodeArtifact からの取得はコンテナ内の `uv sync` で、OTA の仕組み（Mender）とは別物。(4) 岩政さんの tern-api の作業は、実機から API を呼ぶ M2M としてこの基盤を使った初めての例。「岩政さんの作業: 進捗と構想とのギャップ」をやめ、「車載装置の IoT 証明書の基盤」（成り立ちと用途、backend-api を乗せる案の照合）に組み直した。
- 2026-10-15: 安部さんにヒアリングした。1 台 1 証明書は安部さんが進めていて（岩政さんではない）、最終形は「共通の証明書には発行の role だけ → キッティングで機体ごとの証明書を作る → Mender の accept で Thing ができたら Lambda で紐付け」（claim 証明書による Fleet Provisioning と同じ形）。いまは mender・aws-access・tern-api の 3 枚を OTA で配り、それぞれ別の role alias に紐付く。時期と、呼び先で機体を見分ける方法はどちらも未定。「4. 車載装置用 M2M」の方針を「最終形が整ってから backend-api を乗せる」に改め、照合の表を「いまの共通の証明書」と「最終形」の 2 列にした。
- 次: 安部さんに backend-api の要件（機体の識別・用途ごとの停止）を伝え、安本さんと `jadv_` をつなぎにするかを決める。並行して「調べること」のうち TPM の有無と CI 用マシンの実体を確かめる。
