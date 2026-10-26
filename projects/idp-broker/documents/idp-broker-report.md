# 社内アプリの認証の入口となる IdP の選定

- 作成: 2026-10-16
- 範囲: 公開の文書・料金ページ・Terraform Registry による机上の調査。動作の確認は、6 章の検証テナントで行う
- 作業の記録: [`idp-auth0-role-division.md`](../workstream/idp-auth0-role-division.md)

## 用語

- **ブローカー**: 社内アプリの認証の入口となる IdP のこと。社内アプリの手前に立ち、外から来た人のログインを中継する。この報告書で選ぶ対象そのもの。最初に載せるのは JADD STUDIO で、まず協力会社の人のログインに使う。
  - 協力会社ごとの IdP（その会社の社員の本人確認をする仕組み。Entra ID など）を複数受け入れ、本人確認の結果を確かめたうえで、JADD STUDIO にログインの結果（トークン）を渡す。
  - JADD STUDIO が信頼するのはブローカー 1 つだけになる。協力会社が増えても、ブローカーの設定を足せば済む。
  - 相手先の IdP から離任（無効化）の知らせを受け、JADD STUDIO に伝える役も持つ。
  - 製品の分類では「アプリ用の IdP」「CIAM」「B2B 向けの認証基盤」などと呼ばれる。Auth0・Zitadel Cloud（ツィタデルクラウド）・WorkOS はいずれもこの役を担える。
- **IdP**（Identity Provider）: 利用者の本人確認をして、その結果をアプリに渡す仕組み。
- **SCIM**: IdP からアプリやブローカーへ、利用者の作成・変更・無効化を送るための標準の仕様。

## 1. 結論

- **本命は Auth0、2 番手は Zitadel Cloud、3 番手は WorkOS。** WorkOS は運用の条件 (7) を満たさず候補から外れるが、Auth0 と比べる基準として順位に残した（3 章）。
- 決め手は、**identity リポと同等の IaC（設定をコードで持ち、PR で変え、CI で適用し、読み取りと書き込みの credential を分ける）ができるか**。Auth0 と Zitadel Cloud は満たせるが、WorkOS は credential を分けられない。
- Zitadel Cloud が Auth0 に及ばないのは、**離任の確かさ**（SCIM がプレビュー、無効化のときにアプリへ通知されるかが不明）、**SCIM の人と SSO の人の結び付けがメール・ユーザー名頼み**、**日本のリージョンが無い**、の 3 点。
- 次の一手は、Auth0 と Zitadel Cloud の検証テナントで離任の流れを確かめることと、Auth0 の Enterprise の見積を取ること（6 章）。

## 2. 前提と要件

### 構想の要約

- 協力会社の人は、**相手先の IdP** で本人確認したうえで、ブローカーを経由して JADD STUDIO に入る。
- 社員がいま Google で JADD STUDIO にログインしているのは一時的な形で、ブローカーの導入が決まれば、社員も Okta からブローカーを経由して入る形に置き換える。
- 入場は相手先の IdP が決める（こちら向けのアプリに割り当てた人だけが入れる）。JADD STUDIO の中で何ができるかは JADD STUDIO のロールで決める。
- **離任は必須。** 相手先の IdP から SCIM で無効化を受け、JADD STUDIO の既存のセッションまで止める。取りこぼしは定期の突き合わせ（cron）で拾う。

### 選ぶ条件

3 段で見る。「構想が求める機能」と「運用の条件」は満たさなければ候補から外し、「比べる観点」は残った候補の比較に使う。番号は 3 章の星取表の項目と対応する。

**構想が求める機能**

| 番号 | 条件 |
|---|---|
| (1) | 大手が使う IdP（Entra ID・Okta・Ping Identity・ForgeRock・HENNGE One など）を、協力会社ごとに SAML / OIDC の企業接続として受けられる |
| (2) | 協力会社ごとの所属をトークンに載せて JADD STUDIO に渡せる |
| (3) | ログインの途中で、相手先が割り当てた証拠（クレーム）の無い人を拒否できる |
| (4) | 相手先の IdP から SCIM で無効化を受けられる |
| (5) | 無効化を受けたら、既存のセッションを止めて JADD STUDIO に知らせる |
| (6) | 利用者の状態を API で引ける（突き合わせの cron に使う） |

**運用の条件**

| 番号 | 条件 |
|---|---|
| — | SaaS であること |
| (7) | identity リポの IaC lane と同等の運用ができること（下の「IaC の 4 条件」） |
| (8) | 管理画面に Okta の SSO で入れる。大手の製品はおおむね備える機能なので、公開文書で確かめられなかった候補も満たす前提で扱い、問い合わせで確かめる |

(7) で満たすべきことを次の 4 つにまとめ、この報告書では「IaC の 4 条件」と呼ぶ。

| 条件 | 要点 | 何のためか |
|---|---|---|
| Config as Code | 設定を宣言的なコードで持つ | 正本を git に置く |
| Plan in PR | PR で差分（plan）を見せる | レビュー |
| Apply from CI | main への merge で CI が適用し、ローカルからは適用しない | 変更の経路を 1 本にする |
| Read-Write Split | 読み取り（plan）と書き込み（apply）の credential を、SP 側で分ける | PR から書き込みの鍵に届かないようにする |

**比べる観点**

| 番号 | 観点 |
|---|---|
| (9) | 日本のリージョン |
| (10) | SLA |
| (11) | 費用 |

### 協力会社の IdP

協力会社の第一候補の 2 社（以下 D社・T社）が使う IdP を、公開の情報（DNS の公開レコード、Microsoft のログイン画面が使う公開の realm discovery）で確かめた。

| 対象 | 会社 | Entra ID のテナント | 認証の形 |
|---|---|---|---|
| D社の日本の社員のメールのドメイン | D社 | あり | Managed（Entra ID が自分で認証する） |
| T社の社員のメールのドメイン | T社 | あり | Managed |

- 両社とも、社員が Microsoft 365 にサインインするときの IdP は Entra ID そのもの。こちら向けのアプリも Entra ID で作ってもらう形が最も自然と見ている。
- 次の点は外からは分からないので、相手先の IT に確かめる（6 章）。
  - 社外のアプリとのフェデレーションを Entra ID で出すか、別の IdP で出すか（T社の欧州法人は、取引先向けのポータルを Ping Identity / ForgeRock で運用している事例がある）
  - どの会社・どのテナントの人が使うか（グループ会社・地域法人はテナントが別になりうる）
  - SCIM のプロビジョニングと条件付きアクセスを、こちら向けのアプリに設定してもらえるか

## 3. 候補の比較

### 星取表

凡例: ○ = 公開文書で確認できた / △ = 条件付き、またはこちらで補う / × = 無い、または満たせない / （不明） = 公開文書で確かめきれない（理由は「不明とした理由」）

| 項目 | Auth0（Enterprise） | Zitadel Cloud | WorkOS |
|---|---|---|---|
| **構想が求める機能** | | | |
| (1) 大手の IdP の企業接続を社ごとに複数 | ○ | ○（Pro は IdP 3 つまで） | ○（1 本 $125/月） |
| (2) 協力会社ごとの所属 | ○ Organization | ○ 組織 | ○ Organization |
| (3) ログインの途中での拒否 | ○ Actions | △ Actions v2 | △ Actions |
| (4) 協力会社からの SCIM | ○ | △ プレビュー・利用者だけ | ○ Directory Sync（1 本 $125/月） |
| (5) 離任時のセッションの停止とアプリへの通知 | ○ | （不明） | △ |
| (6) 利用者の状態を引く API | ○ | ○ | ○ |
| **運用の条件** | | | |
| (7) identity リポと同等の IaC | ○ | ○ | △ |
| (8) 管理画面に Okta の SSO で入る | ○（Enterprise） | （不明。満たす前提） | ○（全プラン） |
| **比べる観点** | | | |
| (9) 日本のリージョン | ○ | × | （不明） |
| (10) SLA | 99.99% | 99.99%（Enterprise） | 99.99%（年契約） |
| (11) 費用 | 見積 | Pro $100/月。Enterprise は見積 | 協力会社 1 社につき $250/月 |
| **順位** | **本命** | **2 番手** | **3 番手** |

WorkOS は (7) の Read-Write Split を満たせず、運用の条件から外れる。当初の有力候補で、Auth0 と比べる基準になるため、星取表に残した。

### 項目の説明

**(1) 大手の IdP の企業接続を社ごとに複数**

協力会社ごとに、その会社の IdP を SAML か OIDC の「企業接続」として登録できるか。協力会社が増えたら接続を足すだけで済む。

- Auth0: Entra ID 専用の接続（`waad`）と汎用の SAML / OIDC の接続がある。
- Zitadel Cloud: 組織ごとに Entra ID・SAML・OIDC の IdP を登録できる。Pro プランは IdP 3 つまで。
- WorkOS: 接続 1 本ごとに課金（1〜15 本目は $125/月、16 本目から段階的に下がる）。

**(2) 協力会社ごとの所属**

ブローカーが「この人はどの協力会社の人か」をトークンに載せて JADD STUDIO に渡せるか。JADD STUDIO は所属を属性として記録するだけで、権限には使わない。3 者とも、会社ごとの単位（Organization / 組織）を持つ。

**(3) ログインの途中での拒否**

相手先の IdP が「こちら向けのアプリに割り当てた人」にだけ載せるクレーム（例: アプリロール `JADDStudio.User`）を、ブローカーがログインの途中で確かめ、無い人を拒否できるか。相手先の割り当ての設定ミスがあっても、拒否する側に倒すための仕組み。

- Auth0: Actions のコードがブローカーの中で動く。設定だけで閉じる。
- Zitadel Cloud・WorkOS: ブローカーが**こちらのエンドポイント**を呼び、許可か拒否かを返させる形。拒否の判断をこちらのサーバーに置き、その受け口を運用することになるので △ とした。WorkOS では、JIT（初回ログインでの自動作成）を切り、SCIM で作られた人だけが入れる形にすれば、この確認そのものを不要にできる。

**(4) 協力会社からの SCIM**

相手先の IdP が SCIM でブローカーへ利用者の作成・無効化を送り、ブローカーがそれを受けられるか。離任を速く伝えるための入口。

- Auth0: 接続ごとに SCIM の受け口がある。全プランに含まれる。
- Zitadel Cloud: 組織ごとに受け口がある（`/scim/v2/{組織 ID}`）が、**プレビュー**の機能で、利用者だけを扱う（グループは不可）。
- WorkOS: Directory Sync として、接続とは別に 1 本ごとに課金する。

**(5) 離任時のセッションの停止とアプリへの通知**

SCIM で無効化を受けたとき、ブローカーが既存のセッションを止め、JADD STUDIO にもすぐ知らせるか。JADD STUDIO は自分のセッションを持つので、知らせが来なければ離任した人が使い続けられてしまう。

- Auth0: 無効化を受けると利用者を blocked にし、セッションを終え、リフレッシュトークンを失効させ、**OIDC のバックチャネルログアウト**（標準の仕様）を JADD STUDIO に送る（バックチャネルログアウトは Enterprise プラン）。
- Zitadel Cloud: バックチャネルログアウトは実装されているが、SSO のセッションが終わったときに送るものとして書かれており、**SCIM の無効化で送られるかが文書に無い**。
- WorkOS: AuthKit の Directory Provisioning（WorkOS のサポートに頼んで有効にする機能）を使えば、WorkOS 側のセッションは失効する。JADD STUDIO への知らせは WorkOS 独自のイベント（Events API か Webhook）で、バックチャネルログアウトは無い。JADD STUDIO がイベントを読んで自分のセッションを止めるので △ とした。

**(6) 利用者の状態を引く API**

リアルタイムの知らせの取りこぼしを拾うため、JADD STUDIO が定期的に「この人は無効になっていないか」をブローカーに問い合わせられるか。3 者とも API がある。WorkOS は Events API を前回の続きから読めるので、知らせと突き合わせを 1 本の定期処理にまとめられる。

**(7) identity リポと同等の IaC**

2 章の IaC の 4 条件を満たせるか。詳しくは 5 章。

- Auth0: 公式の Terraform provider があり、構想で使う設定をすべて扱える。Management API の M2M アプリに scope を付けて、読み取りと書き込みの credential を分けられる。
- Zitadel Cloud: Zitadel 社の Terraform provider があり、構想で使う設定をほぼ扱える。**読み取りだけの管理者ロール**で credential を分けられる。
- WorkOS: Terraform provider はコミュニティ製だけで、扱えない設定がある。**API キーに読み取りだけの区分が無く**、credential を分けられないので △ とした（4 章）。

**(8) 管理画面に Okta の SSO で入る**

ブローカーの管理画面に、こちらの管理者が Okta の SSO で入れるか。入れなければ管理者のアカウントを Okta の外に持つことになり、退職したときの停止を別に管理しなければならない。

- Auth0: Enterprise プランの機能。
- WorkOS: 全プランで使える。管理者のアカウントの作成・削除を Directory Sync で連動させることもできる。

**(9) 日本のリージョン**

ブローカーに置かれる利用者のデータ（協力会社の人の氏名・メールアドレス等）を、日本のデータセンターに置けるか。

- Auth0: 公開クラウドに日本のリージョン（`*.jp.auth0.com`）がある。
- Zitadel Cloud: 選べるのは EU・US・スイス・豪州。

**(10) SLA**

稼働率の保証。3 者とも、上位のプランか年契約で 99.99%。

**(11) 費用**

- Auth0: Enterprise は見積制。契約の上限に対して計測されるのは、月に使った人数（MAU）と、使われた企業接続の本数（＝協力会社の数）。
- Zitadel Cloud: Pro が $100/月。SLA 99.99% が付く Enterprise は見積制。
- WorkOS: 企業接続と Directory Sync が 1 本 $125/月ずつで、協力会社 1 社につき $250/月。ログイン画面（AuthKit）は 100 万 MAU まで無料。

### 不明とした理由

| 候補 | 項目 | 理由 |
|---|---|---|
| Zitadel Cloud | (5) 離任時のセッションの停止とアプリへの通知 | SCIM の文書には「`active` を利用者の状態に対応させる」とだけあり、**無効化のときに既存のセッションを止めるか、バックチャネルログアウトを送るかが書かれていない**。バックチャネルログアウトの文書は、SSO のセッションが終わったときの動きとして書かれている。検証テナントで確かめる |
| Zitadel Cloud | (8) 管理画面に Okta の SSO で入る | Zitadel Cloud には、インスタンスの管理画面（ここには外部の IdP を設定できる）と、インスタンスを契約・管理するポータルの 2 つがある。**ポータルに Okta の SSO で入れるかを、公開文書で確かめられなかった**。大手の製品はおおむね備える機能なので、満たす前提で扱い、問い合わせで確かめる |
| WorkOS | (9) 日本のリージョン | サブプロセッサーの一覧に AWS（USA）とあるだけで、**リージョンを選べるかの記載が見当たらない** |

### 検討したが外した候補

- **Keycloak、および Zitadel・Ory・FusionAuth の自前ホスティング版**
  SaaS に限る方針のため外した。サーバーの運用と脆弱性への追従がこちらの仕事になる。
- **Clerk、Descope、Stytch、Frontegg**
  協力会社ごとの接続と SCIM を、コードで管理できないため外した。Clerk は Terraform provider が無く、Descope は確かめられなかった。Stytch と Frontegg は provider があるが、接続や SCIM の設定を扱えない。
- **Amazon Cognito、Google Identity Platform、PingOne**
  協力会社の IdP から SCIM を受けられないため外した。離任の仕組みを自前で作ることになる。PingOne の SCIM は送り出しだけ。
- **Ory Network、FusionAuth Cloud**
  離任の要件を満たしにくいため外した。Ory Network は無効化しても既存のセッションが止まらず、通知の配送も best-effort。FusionAuth Cloud は SCIM がテナント単位で、協力会社ごとに分けられない。
- **Okta Workforce（Inbound Federation）、Microsoft Entra ID（自社テナントを新設して B2B ゲストで受ける）、Google Workspace（協力会社にアカウントを発行）**
  協力会社の人を自社の台帳に取り込む形で、構想と合わないため外した。社員の台帳に社外の人が混ざる、入場をこちらが決めることになる、相手先での退職が効かない、のいずれかに当たる。
- **Supabase Auth の SAML SSO**
  協力会社に Supabase のトークンを持たせると JADD STUDIO の BFF を直接叩けてしまうため外した。

## 4. 上位 3 候補の比較

### 製品の作りの違い

- **Auth0** は認証の基盤。接続・Organization・Actions・セッション・ログを 1 つのテナントで持ち、JADD STUDIO は Auth0 を OIDC の IdP として信頼する。
- **Zitadel Cloud** も認証の基盤で、作りは Auth0 に近い。会社ごとの単位（組織）の中に IdP・利用者・SCIM の受け口を持つ。
- **WorkOS** は企業向け機能の部品の組み合わせ。企業接続（SSO）・Directory Sync（SCIM）・AuthKit（ログイン画面・利用者・セッション）・Admin Portal（相手先の IT 向けの設定画面）を別々の製品として組み合わせる。

### 論点ごとの比較

| 論点 | Auth0 | Zitadel Cloud | WorkOS |
|---|---|---|---|
| SCIM の人と SSO の人の結び付け | 接続の設定で、Entra ID の `oid`（利用者の不変の ID）に揃える。Entra ID のメールを「確かめ済み」と扱わない設定もある | 自動リンクはメールかユーザー名。ID に揃えるには、SCIM の `userName` と IdP 側のユーザー名を `oid` にする工夫が要る | 組織の中で IdP の一意の ID を先に照合し、次に確かめ済みのメールで照合する |
| 初回ログインの条件 | 接続を Organization に紐付けるだけ | 組織の IdP の設定で、自動作成を許すか決める | **メールのドメインが組織の「確かめ済みのドメイン」のときだけ自動作成が動く**。相手先の IT が DNS に TXT を足して確かめるか、こちらが手で追加する |
| 相手先の IT による設定 | Self-Service SSO（SCIM も） | （不明） | Admin Portal（SSO・SCIM・ドメインの確認を、相手先がリンクから設定できる） |
| 認証のログ | 30 日の保持と、ログのストリーミング | （不明） | （不明） |
| 会社 | Okta 社の製品。調達とサポートの窓口が Okta と揃う | Zitadel 社（スイス）。2025 年に、自動リンクの重大な脆弱性（CVE-2025-64717、CVSS 9.8）を修正している | 独立の企業。2025-12 に Trust Center（SOC レポート等）を公開 |

### JADD STUDIO 側で作るものの違い

| | Auth0 | Zitadel Cloud | WorkOS |
|---|---|---|---|
| ログイン | Auth0 との OIDC 1 本 | Zitadel との OIDC 1 本 | AuthKit との連携 1 本 |
| 入場の確かめ | 無し（Auth0 の Actions に閉じる） | Actions v2 から呼ばれる受け口 | Actions から呼ばれる受け口（JIT を切る形なら無し） |
| 離任の受け取り | バックチャネルログアウトの受け口 + 突き合わせの cron | バックチャネルログアウトの受け口 + 突き合わせの cron（無効化で届くかは要検証） | Events API を読む定期処理（外から叩かれる受け口を持たない形にできる） |

### WorkOS で identity リポと同等の IaC ができるか

**結論: できない。** WorkOS の設定は、identity リポの分け方で言えば IaC lane ではなく **Direct SP lane**（API のスクリプトと skill で手順を固める形）に近い運用になる。

WorkOS で使える手段は 3 つ。

| 手段 | 扱えるもの | Config as Code | Plan in PR | Apply from CI | 所見 |
|---|---|---|---|---|---|
| Terraform の `osodevops/workos`（コミュニティ製） | Organization・企業接続・Directory・Webhook・利用者・所属 | ○ | ○ | ○ | WorkOS 社製ではない。v1.0.0（2026-02）のみで、利用実績はほぼ無い。Actions・ドメイン・セッションの設定は対象外 |
| 公式 CLI の `workos seed`（YAML） | permission・role・Organization（ドメイン付き）・redirect URI・CORS・homepage | △ | × | △ | 企業接続・Directory・Webhook・Actions は対象外。差分の表示は文書に無く、消せるのは「seed で作ったものを全部」だけ。状態は手元の JSON に置く。開発環境の初期化の道具 |
| REST API + 自前のスクリプト | Organization・ドメイン・企業接続の作成（SAML / OIDC）・role・permission・redirect URI・CORS・Webhook | △ 宣言の形を自前で作る | △ 差分を自前で出す | ○ | Directory（SCIM の受け口）を API で作る方法は文書に無い。Actions とセッションの設定の API も見当たらない |

**Read-Write Split（credential の分離）は、どの手段でも満たせない。** WorkOS の API キーは、文書に「あらゆる API の要求を実行できる」とあり、読み取りだけのキーを作る方法が見当たらない（WorkOS にも「読み取りだけの API キー」の機能はあるが、WorkOS を使うアプリが自分の顧客に配るためのもの）。plan 用のキーでも書き込みができるので、identity リポの「PR からは書き込みの鍵に届かない」を WorkOS 側で強制できない。

## 5. identity リポと同等の IaC ができるか（Auth0 と Zitadel Cloud）

### Auth0

**結論: できる。** Okta と同じ形で、identity リポに `platform/auth0/` を足して管理できる見込み。

**手段**

| 手段 | 状態 | 所見 |
|---|---|---|
| Terraform の `auth0/auth0`（Auth0 社製） | v1.59.0（2026-10-07）。更新が続いている | 本命 |
| Auth0 CLI の `auth0 terraform generate` | 実験的 | 既存のテナントを読んで Terraform のコードを書き出す。管理画面で試した検証テナントを取り込むときに使える |
| Deploy CLI（YAML / JSON） | v9.1.0（2026-10-07） | テナントの書き出し・取り込みの道具。差分（plan）を出す作りではないので、identity リポには Terraform のほうが合う |

**構想で使う設定と Terraform の対応**

| 構想での設定 | resource | 所見 |
|---|---|---|
| 協力会社の IdP の企業接続 | `auth0_connection`（Entra ID は `waad`、ほかは `samlp` / `oidc`） | Entra ID の接続で `user_id_attribute = "oid"`（ID で照合する）と、メールを確かめ済みと扱わない設定をコードで宣言できる |
| 企業接続の秘密（OIDC のクライアントシークレット） | `auth0_connection` の write-only の引数 | state に残らない（Terraform 1.11 以上）。Secret Manager から渡せる |
| 受信側 SCIM の設定 | `auth0_connection_scim_configuration` | 属性の対応もコードで持てる |
| SCIM のトークン | `auth0_connection_scim_token` | 作れるが、**トークンの値が state に入る** |
| 協力会社ごとの Organization と接続の紐付け | `auth0_organization` / `auth0_organization_connection` | |
| 入場の Actions | `auth0_action` / `auth0_trigger_actions` | Actions のコードそのものが PR の差分になり、入場の規則の変更をレビューに載せられる |
| JADD STUDIO のクライアントとバックチャネルログアウトの送り先 | `auth0_client`（`oidc_logout`） | |
| セッションの寿命（絶対・無操作） | `auth0_tenant` | |
| ログの持ち出し・Event Streams | `auth0_log_stream` / `auth0_event_stream` | |
| 相手先の IT によるセルフ設定 | `auth0_self_service_profile` | |
| plan / apply 用の M2M アプリと scope | `auth0_client` / `auth0_client_grant` | 下の Read-Write Split |

構想の範囲の設定は、すべて Terraform で扱える。管理画面の管理者（テナントのメンバー）と Dashboard SSO だけは、管理画面か契約で設定する。

**IaC の 4 条件**

| | 満たし方 |
|---|---|
| Config as Code | `auth0/auth0` |
| Plan in PR | identity リポの Okta の plan の workflow と同じ形で、Auth0 の plan の workflow を足せる |
| Apply from CI | 同じく apply の workflow を足す。state は GCS、秘密は Secret Manager + WIF に揃えられる |
| Read-Write Split | Management API の M2M アプリごとに scope を付けられる。plan 用のアプリには読み取りの scope だけ、apply 用のアプリには書き込みの scope を付ける。分離が Auth0 側で強制される |

plan / apply 用の M2M アプリそのものは、最初の 1 回だけ管理画面で作る（Okta の Terraform 用の API Services app と同じ扱い）。

### Zitadel Cloud

**結論: できる見込み。** IaC の 4 条件を満たせる。

**手段**

Terraform の `zitadel/zitadel`（Zitadel 社製。Terraform Registry の partner 区分）。v3.8.7（2026-09-25）。110 の resource を持つ。

**構想で使う設定と Terraform の対応**

| 構想での設定 | resource | 所見 |
|---|---|---|
| 協力会社ごとの組織 | `zitadel_org` | |
| 協力会社の IdP の企業接続 | `zitadel_org_idp_azure_ad` / `zitadel_org_idp_saml` / `zitadel_org_idp_oidc` | メールを確かめ済みと扱うか（`email_verified`）と、自動リンクの条件（`auto_linking`）をコードで持てる。クライアントシークレットは write-only で state に残らない |
| 組織のログインの方針 | `zitadel_login_policy` | 使ってよい IdP、ローカルのパスワードを許すか、等 |
| SCIM の受け口の認証 | `zitadel_machine_user` / `zitadel_org_member` / `zitadel_personal_access_token` | SCIM は組織のマシンユーザーのトークンで認証する。マシンユーザー・権限・トークンを作れるが、**トークンの値が state に入る** |
| SCIM の受け口そのもの | — | 組織ごとに URL が決まる |
| 入場の Actions | `zitadel_action_target` / `zitadel_action_execution_*` | こちらのエンドポイントを呼ぶ形。署名の鍵が state に入る |
| JADD STUDIO のクライアントとバックチャネルログアウトの送り先 | `zitadel_application_oidc`（`back_channel_logout_uri`） | |
| トークンの寿命 | `zitadel_default_oidc_settings` | リフレッシュトークンの寿命・無操作の寿命 |

**IaC の 4 条件**

| | 満たし方 |
|---|---|
| Config as Code | `zitadel/zitadel` |
| Plan in PR / Apply from CI | Auth0 と同じく、identity リポに plan / apply の workflow を足せる |
| Read-Write Split | 読み取りだけの管理者ロール（インスタンス全体の `IAM_OWNER_VIEWER`、組織ごとの `ORG_OWNER_VIEWER`）がある。plan 用のマシンユーザーには読み取りのロールだけを付け、apply 用には書き込みのロールを付ける |

plan / apply 用のマシンユーザーそのものは、最初の 1 回だけ管理画面で作る。

### identity リポの lane での位置づけ（Auth0・Zitadel Cloud 共通）

| 対象 | lane | 動線 |
|---|---|---|
| ブローカー本体（企業接続・Organization・Actions・クライアント・セッション） | IaC | Okta と同じ plan / apply の workflow で管理する |
| 協力会社の人のアカウント | Provisioning（起点は相手先） | 相手先の IdP から SCIM で入り、外されれば止まる。利用者の出入りの起点は相手先の IdP で、Terraform が扱うのはブローカーの設定だけ |
| JADD STUDIO の中のロール | Direct SP | いまと同じ（JADD STUDIO のユーザー管理画面で付ける） |

identity リポの Provisioning lane は、いまは「Okta の Terraform で完結する」前提で書かれている。**「社外の IdP を起点にする Provisioning」を README に書き足す必要がある。**

### 注意すること（Auth0・Zitadel Cloud 共通）

- **SCIM のトークンの値が state に入る。** 相手先に渡す秘密なので、Terraform の外で発行するか、state の閲覧権限を絞る前提で使うかを、identity リポのオーナー（コーポレート IT）と決める。
- **入場の Actions は、クレームを見るだけの作りにする。** Actions の秘密や署名の鍵は state に入る。
- **設定の変更は PR で行い、管理画面は読むだけにする。** 管理画面で変えると、次の plan に差分として出る。Okta と同じ運用を README に書く。

## 6. 未確認のことと次の一手

### 検証テナントで確かめること

確かめるには、ブローカーの検証テナントと、検証用の Entra ID テナントがあればよい。

- Auth0
  - SCIM で作られた人と SSO で入った人が、`oid` で同じ 1 人になるか
  - SCIM の無効化で、バックチャネルログアウトが実際に JADD STUDIO に送られるか
  - Entra ID でアカウントを無効化しただけ（割り当て解除・削除ではない）でも、無効化が SCIM で届くか
  - 割り当ての無い人のトークンにアプリロールのクレームが載らず、Actions で拒否できるか
- Zitadel Cloud
  - SCIM の無効化で、既存のセッションが止まり、バックチャネルログアウトが送られるか
  - SCIM の `userName` と IdP 側のユーザー名を `oid` に揃え、同じ 1 人として結び付けられるか

### ベンダーに問い合わせること

- Auth0: Enterprise の見積（協力会社の利用人数と社数で）。Dashboard SSO の設定方法
- Zitadel Cloud: SCIM の正式提供の時期。日本のリージョンの予定。契約・管理のポータルに SSO で入れるか
- WorkOS: API キーに読み取りだけの scope を付ける予定。リージョンを選べるか

### 相手先（協力会社）の IT に確かめること

- 社外のアプリとのフェデレーションに使う IdP（Entra ID か、別の IdP か）
- 使う人が属する会社・テナント
- こちら向けのアプリに、割り当て・アプリロール・SCIM のプロビジョニング・条件付きアクセス（MFA）を設定してもらえるか

### 構想として決まっていないこと

- Auth0 なら、プラン（Enterprise か B2B Professional か。バックチャネルログアウトと Dashboard SSO は Enterprise だけ）
- 協力会社のセッションの絶対的な寿命（SCIM が止まったときの保険。例: 7 日）
- ブローカーの運用主体（コーポレート IT か、アプリ側か）。identity リポの IaC lane で管理する方針は 2026-10-16 に決めた（[`where-to-solve.md`](where-to-solve.md) 3 章）

## 7. 出典

2026-10-16 に参照した。第三者の記事から取った値は本文でそう書いている。

### Auth0

- Auth0 Pricing: https://auth0.com/pricing
- Monitor Subscription Usage: https://auth0.com/docs/troubleshoot/customer-support/manage-subscriptions/monitor-subscription-usage
- Configure Inbound SCIM: https://auth0.com/docs/authenticate/protocols/scim/configure-inbound-scim
- OIDC Back-Channel Logout Initiators: https://auth0.com/docs/authenticate/login/logout/back-channel-logout/oidc-back-channel-logout-initiators
- Public cloud service endpoints（リージョン）: https://auth0.com/docs/troubleshoot/customer-support/operational-policies/public-cloud-service-endpoints
- Terraform provider: https://github.com/auth0/terraform-provider-auth0
- Auth0 CLI（terraform generate）: https://github.com/auth0/auth0-cli/blob/main/docs/auth0_terraform_generate.md
- Deploy CLI: https://github.com/auth0/auth0-deploy-cli

### Zitadel

- Pricing: https://zitadel.com/pricing
- SCIM v2: https://zitadel.com/docs/guides/manage/user/scim2
- SCIM API: https://zitadel.com/docs/apis/scim2
- Back-channel logout: https://zitadel.com/docs/guides/integrate/back-channel-logout
- Administrators（管理者ロール）: https://zitadel.com/docs/guides/manage/console/administrators
- Account linking: https://zitadel.com/docs/concepts/features/account-linking
- Terraform provider: https://registry.terraform.io/providers/zitadel/zitadel
- CVE-2025-64717: https://nvd.nist.gov/vuln/detail/CVE-2025-64717

### WorkOS

- Pricing: https://workos.com/pricing
- AuthKit Actions: https://workos.com/docs/authkit/actions
- Directory Provisioning: https://workos.com/docs/user-management/directory-provisioning
- Identity linking: https://workos.com/docs/authkit/identity-linking
- JIT provisioning: https://workos.com/docs/authkit/jit-provisioning
- Domain verification: https://workos.com/docs/authkit/domain-verification
- Data syncing（Events API）: https://workos.com/docs/events/data-syncing
- Dashboard authentication: https://workos.com/docs/dashboard/authentication
- API authentication: https://workos.com/docs/reference/api-authentication
- CLI: https://workos.com/docs/cli
- Subprocessors: https://workos.com/legal/subprocessors
- Terraform provider（コミュニティ製）: https://pkg.go.dev/github.com/osodevops/terraform-provider-workos

### 外した候補

- Clerk Directory Sync: https://clerk.com/docs/guides/configure/auth-strategies/enterprise-connections/directory-sync
- Descope の料金: https://descope.com/pricing
- Stytch の Terraform provider: https://registry.terraform.io/providers/stytchauth/stytch
- Frontegg の Terraform provider: https://registry.terraform.io/providers/frontegg/frontegg
- Ory: SCIM https://www.ory.com/docs/kratos/manage-identities/scim / Event Streams https://www.ory.com/docs/actions/live-events / Pricing https://www.ory.com/pricing
- FusionAuth の Terraform provider: https://registry.terraform.io/providers/FusionAuth/fusionauth
- PingOne: Inbound and outbound provisioning https://docs.pingidentity.com/pingone/integrations/p1_inbound_outbound_provisioning.html
- Keycloak 26.7.0: https://www.keycloak.org/2026/07/keycloak-2670-released / 26.8.1: https://www.keycloak.org/2026/10/keycloak-2681-released
- Entra の cross-tenant synchronization: https://learn.microsoft.com/entra/identity/multi-tenant-organizations/cross-tenant-synchronization-overview
- Okta Pricing: https://www.okta.com/pricing/
- Google Identity Platform の料金: https://cloud.google.com/identity-platform/pricing

### 協力会社の IdP

- T社の欧州法人の取引先向けポータルの公開事例（Ping Identity / ForgeRock の導入事例）
- DNS の公開レコード（Google Public DNS）と Microsoft の realm discovery（`login.microsoftonline.com/getuserrealm.srf`）を 2026-10-16 に取得
