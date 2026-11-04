# IAM Roles Anywhere の調査（M2M 認証の候補として）

- 調べた日: 2026-11-04（AWS の公式ドキュメントで裏取り。出典は末尾）
- 関連: [M2M 認証の手法の確立](../workstream/m2m-auth.md)

**IAM Roles Anywhere は、AWS の外にあるマシンが自分の X.509 証明書を使って、IAM ロールの一時的な資格情報を受け取る仕組み。** 認証だけを担うサービスで、マシンの上で何を動かすかには関わらない。m2m-auth の「資格情報の強さの段階」でいうと段階 3（1 台ごとの証明書）にあたり、鍵を TPM に入れれば段階 4 に届く。

## 仕組み

```
[自前の CA または AWS Private CA] ──証明書を発行──▶ [マシン] 秘密鍵＋証明書（鍵は TPM・PKCS#11 にも置ける）
                                                      │ ① 証明書の連鎖を添え、秘密鍵で署名して CreateSession を呼ぶ
                                                      ▼
                                           [IAM Roles Anywhere]
                                             ・トラストアンカーで証明書の連鎖を検証する
                                             ・取り込んだ CRL で失効を確かめる
                                             ・プロファイルとロールの信頼ポリシーで、引き受けてよいか判定する
                                                      │ ② 一時的な資格情報を返す（15 分〜12 時間）
                                                      ▼
                                           [マシン] SigV4 で呼ぶ（AWS の API、IAM 認証で受ける API Gateway など）
```

- 秘密鍵はネットワークに出ない。送るのは証明書と署名だけ。
- 呼び先は、IAM（SigV4）で受けられる必要がある。backend-api なら API Gateway の IAM 認証と resource policy で受ける形になる。tern-api と同じ受け方。

### AWS 側の設定

| 設定 | 中身 |
|---|---|
| トラストアンカー | 信頼する CA。AWS Private CA か、外部の CA の証明書（バンドル）を登録する。1 つのトラストアンカーに登録できる CA 証明書は 2 枚まで（切り替え用） |
| プロファイル | 引き受けてよいロールの一覧、セッションポリシー（1 つ）とマネージドポリシー（権限の上限）、資格情報の有効期間、証明書の属性の写し方（attribute mapping）、呼び手がセッション名を決めてよいか（`acceptRoleSessionName`） |
| ロールの信頼ポリシー | `rolesanywhere.amazonaws.com` を信頼する。条件（`aws:SourceArn` でトラストアンカーを限る、`aws:PrincipalTag/x509Subject/CN` など）を付ける |
| CRL | 失効した証明書の一覧。API か CLI で取り込む（後述） |

**信頼の境界はアカウント全体。** 条件を付けなければ、アカウント内のどのトラストアンカーの証明書でも、`rolesanywhere` を信頼するどのロールでも引き受けられてしまう。ロールごとに、トラストアンカーと証明書の属性で絞る条件を必ず付ける（公式の推奨）。

### 証明書の要件

- 末端の証明書: X.509v3。basicConstraints に CA があるなら `false`。Key Usage に `Digital Signature`。署名は SHA-256 以上（MD5・SHA-1 は不可）。
- CA の証明書: basicConstraints が `CA: true`、Key Usage に `Certificate Sign`。
- 鍵の種類: RSA・EC（ECDSA）・ML-DSA。
- リクエストに添える連鎖は 5 枚まで。

## 機体の見分け方

| 手がかり | 中身 |
|---|---|
| ロールのセッション名 | **既定は証明書のシリアル番号（16 進）**。CloudTrail の `userIdentity` にもこれが載り、どの証明書のセッションか追える。プロファイルで `acceptRoleSessionName` を有効にすると、呼び手が `roleSessionName` で決められる（有効にしていないプロファイルに送ると `Access Denied`） |
| セッションタグ | 証明書の Subject・Issuer・SAN が `aws:PrincipalTag/x509Subject/CN`、`x509Issuer/O`、`x509SAN/DNS` などの形で載る。複数の値は `/` でつなぐ。SAN は DNS・URI・DN の最初の 1 つだけ。どの属性を載せるかはプロファイルの attribute mapping で変えられる |
| sourceIdentity | Subject の CN が 61 文字以下なら `CN=<CN>`、CN が無ければ `ID=<シリアル番号>` |
| Subject | Roles Anywhere は証明書の Subject ごとに「最初と最後に認証した時刻」を記録する（コンソールの Subject activity） |

**証明書の CN に機体 ID（号車名や Thing 名）を入れておけば、呼び先は sourceIdentity やセッションタグで機体を特定できる。** シリアル番号から機体を引くなら、発行記録の台帳が要る。

- 要確認: タグの章に「これらの値はポリシーの条件に使えない」という一文がある一方、信頼ポリシーの例では `aws:PrincipalTag/x509Subject/CN` を条件に使っている。実際に試してから頼る。
- 要確認: 呼び先（API Gateway の IAM 認証）で、`userArn`（セッション名入り）以外に sourceIdentity やタグを受け取れるか。

## 失効（1 台だけ止める）

- **CRL を取り込む**（`ImportCrl` API か `aws rolesanywhere import-crl`。コンソールではできない）。形式は PEM。1 つのトラストアンカーに取り込める CRL は 2 つまで（引き上げ不可）。資格情報を出す前に CRL と照合する。
- **OCSP と CRL 配布点（CDP）は見に行かない。** CA の側で失効させただけでは効かない。失効したら CRL を作り直して取り込む手順を、運用に組み込む必要がある。
- 取り込んでから効くまでの時間は書かれていない。
- すでに出た資格情報は期限まで有効。止めたいときに早く効くよう、有効期間は短めにしておく。
- 全体を止めるときは、トラストアンカー・プロファイル・CRL の有効・無効を切り替える API がある。

## 資格情報の有効期間とポリシー

- 15 分〜12 時間。実際の期限は、プロファイルの `durationSeconds` と CreateSession で求めた値の短い方。ロールの `MaxSessionDuration` を超えるとエラーになる。プロファイルの既定値はドキュメントに書かれていない（1 時間と思われるが未確認）。
- プロファイルには複数のロールを載せられるが、セッションポリシーは 1 つだけ。マネージドポリシーも付けられ、ロールの権限をさらに絞れる。

## マシン側の道具（aws_signing_helper）

AWS が出しているクライアント。2026-08 時点で 1.8.5。

| モード | 動き | 注意 |
|---|---|---|
| `credential-process` | AWS CLI・SDK の `credential_process` から呼ばれ、資格情報を JSON で返す | **基本はこれ**。資格情報がファイルに残らない |
| `update` | `~/.aws/credentials` に書き、期限の 5 分前に取り直す | 資格情報がファイルに残る |
| `serve` | `127.0.0.1:9911` に IMDSv2 互換の口を開く | 同じマシンのどのプロセスからでも取れる |

鍵の置き場所:
- **TPM 2.0**: Linux は 1.3.0（2024-11）、Windows は 1.4.0（2024-12）から使える。注意点が 3 つある。TPM の永続・一時オブジェクトは自分で片付ける。保護のない鍵を読み込むと、そのマシンの誰でも使える。RSA の鍵には sign の属性が要る。
- PKCS#11（HSM・セキュアエレメント・スマートカード）。
- Windows の証明書ストア、macOS のキーチェーン。
- ファイル（PKCS#8。パスワード付きにも対応）。

## 上限と費用

| 項目 | 既定 | 引き上げ |
|---|---|---|
| CreateSession | 毎秒 10 回 | できる |
| トラストアンカー | 50 | できる |
| プロファイル | 250 | できる |
| トラストアンカーあたりの CRL・CA 証明書 | 各 2 | できない |

100 台規模なら上限は問題にならない。

費用:
- Roles Anywhere 自体: 料金のページが見つからず、今回は確かめられなかった（追加料金なしと理解しているが未確認）。
- AWS Private CA を使う場合（2026-11 時点の料金表）:

  | モード | CA の月額 | 証明書ごとの料金 | 証明書の有効期間 |
  |---|---|---|---|
  | 汎用 | $400 | 1,000 枚まで $0.75/枚 | 制限なし |
  | 短命証明書 | $50 | $0.058/枚 | 7 日まで |

  OCSP の料金は Roles Anywhere では使わないのでかからない。
- 自前の CA なら、AWS 側の CA の費用はかからない。代わりに、CA の鍵の保管・発行・CRL の運用は自分で持つ。

## AWS IoT credential provider（いまの実機の基盤）との比較

どちらも「証明書 → 一時的な IAM 資格情報 → SigV4」で、呼び先から見た形は同じ。違うのは台帳と失効の持ち方。

| 観点 | IAM Roles Anywhere | IoT credential provider |
|---|---|---|
| 信頼の単位 | CA（証明書を 1 枚ずつ登録しない） | 証明書を 1 枚ずつ IoT Core に登録し、Thing と紐付ける |
| 台帳 | CA の発行記録（自分で持つ） | Thing（属性・グループ）がそのまま台帳になる |
| 1 台だけ止める | CRL を作り直して取り込む | 証明書を INACTIVE にする |
| 機体の見分け | シリアル番号のセッション名、CN の sourceIdentity・タグ | 要確認（Thing 名や証明書 ID が `userArn` に載るか。workstream の「調べること」） |
| 権限の絞り方 | プロファイルと信頼ポリシーの条件 | role alias と IoT ポリシー |
| 鍵の保管 | TPM・PKCS#11 に対応したクライアントがある | 作り次第（mTLS のクライアントを自分で用意する） |
| 他の機能 | 認証だけ | MQTT・Device Shadow・Jobs など機体管理の機能が揃う |
| 向くもの | 台数が少なく、CA を持てる常設のマシン（サーバー・CI） | 機体管理と一体で運用する IoT 機器 |

## m2m-auth での位置づけ（2026-11-04 時点の伊藤の考え）

- **CI 用マシン（GitHub Actions のジョブとして動かないもの）は、Roles Anywhere を第一候補にする。** 1 台 1 証明書、秘密を送らない、鍵は TPM に入れられる、短命の資格情報、の原則を AWS の標準の部品だけで満たせる。台数が少ないので、Private CA の短命証明書モードか、自前の小さな CA で回せる。
  - GitHub Actions のジョブ（self-hosted runner を含む）なら、ジョブごとの OIDC で IAM role を引き受ける形が先。配る秘密が無い分、こちらが強い。
- **車載装置は、いまの IoT の基盤（安部さんの 1 台 1 証明書の計画）を進める。** Thing を台帳にでき、Mender と連携し、失効が即時に効くので、Roles Anywhere に乗り換える理由は弱い。比べる価値があるのは「1 台 1 証明書を自前の CA で発行し、IoT と Roles Anywhere の両方で同じ証明書を使う」形まで。
- **どちらでも backend-api の受け方は同じ（IAM role → SigV4）。** backend-api の入口に IAM で受ける余地を残せば、車載装置は IoT、CI は Roles Anywhere か OIDC、と入口をそろえられる。

## 次に確かめること

- [ ] 社内設置の CI 用マシンの実体（GitHub Actions の self-hosted runner か、TPM があるか）
- [ ] 信頼ポリシーで `aws:PrincipalTag/x509Subject/CN` を条件に使えるか（ドキュメントの記述が食い違っている）
- [ ] API Gateway の IAM 認証で受けたとき、backend-api に機体の手がかり（セッション名・sourceIdentity）がどう届くか
- [ ] CRL の取り込みが効くまでの時間
- [ ] Roles Anywhere 自体の料金と、プロファイルの有効期間の既定値

## 出典（2026-11-04 に読んだ）

- [Introduction](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/introduction.html)
- [Trust model](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/trust-model.html)（セッション名、sourceIdentity、CRL、証明書の要件）
- [Authentication](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/authentication.html)、[CreateSession](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/authentication-create-session.html)（有効期間、`acceptRoleSessionName`）
- [Attribute mapping](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/attribute-mapping.html)
- [Credential helper](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/credential-helper.html)（モード、TPM・PKCS#11、変更履歴）
- [Monitoring subjects](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/monitoring-subjects.html)、[CloudTrail](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/logging-using-cloudtrail.html)
- [ImportCrl API](https://docs.aws.amazon.com/rolesanywhere/latest/APIReference/API_ImportCrl.html)
- [Quotas](https://docs.aws.amazon.com/general/latest/gr/rolesanywhere.html)
- [AWS Private CA pricing](https://aws.amazon.com/private-ca/pricing/)
