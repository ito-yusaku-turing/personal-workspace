# CorpIT への聞き取り（2026-11-02）

- 作成: 2026-11-02 ／ 伊藤
- 親: [権限の地図](privilege-map.md) の 7 章（ヒアリング項目 I1〜I25）。この資料は、それを聞く順に並べ直した当日のシート
- 状態: **1 回目の聞き取りを済ませた（2026-11-02）**。止められている循環の詳細は、後日聞く。答えは privilege-map.md の 7 章・8 章・9.1・10.1 に反映した

## 聞き取りの結果（1 回目、2026-11-02）

CorpIT から聞いたこと（伊藤のメモから）:

1. **すでに GCP を、最上位の権限者を持つシステムにしてある。**
2. **GCP にしたのは、GCP だけは認証をバイパスできるから。** Okta を飛ばしてログインできる。identity の README の state の行（「GCP は管理者が SAML を bypass してログインできる」）と一致する。
3. **実質的な最高権限者は 4 名**: 渡辺 晃平（khwatanabe）・山口 祐（ymgaq）・山本 修平（yamashush）・大戸 一希（kazu0716）。
   - 大戸さんは infrastructure のチームにいて、GitHub の組織の owner ではない（identity の `people.tf`・`team_memberships.tf`、8b8e953）。ほかの 3 名は owner。
4. **指摘した循環のいくつかはブロックされていて、実際には止まっている。** どれが、どの仕組みで止まっているかは、後日詳しく聞く。

答えが付いた項目: I16（一部。最高権限者の 4 名）、I18（一部。Okta を迂回できるのは GCP だけ）。

### 次の聞き取りで聞くこと

| # | 聞くこと | なぜ | 答え |
|---|---|---|---|
| I27 | 止められている循環はどれか（9.1 の C1〜C4）、どの仕組みで止めているか。とくに C1（identity の admin が environment の制限を外す）と C2（`gcp-organization-admins@` のメンバーを IaC で書ける） | 循環の地図を、構造上の経路から実際の経路に直す | |
| I26 | 4 名が持っているのは、GCP の組織管理者か、Workspace の super admin か、両方か。Workspace の super admin は、この 4 名だけか | GCP の組織は Workspace（Cloud Identity）のドメインに属し、Okta を飛ばすログインも Workspace の設定で決まるとみられる。4 名の外に super admin がいれば、その人も頂点になる | |
| I28 | GitHub の組織の owner のうち、4 名に入らない 4 名（棚橋 耕太郎・安本 雅啓・渡邉 礁太郎・山下 卓也）の位置付け。C1 は止められているか | C1 が通るなら、この 4 名も実質の最高権限者に近い | |
| I19 | `gcp-organization-admins@`・`gcp-security-admins@` に付いている GCP のロール（1 回目では未確認）。`gcp-organization-admins@` のメンバーは 山崎 明美・棚橋 耕太郎・山口 祐 で、最上位の 4 名と食い違う | C2 の有無。組織管理者なら、最上位は 4 名より多い | |
| I29 | Workspace の apply のサービスアカウントの管理ロールの範囲（ドメイン全体か、OU に限っているか） | 通知の受け手を IaC の外に置いても、apply から書き換えられるか | |
| I30 | cdk-apps の `main` の保護を、組織のルールセットに移せるか（Team プランで使えるか、owner として設定してもらえるか）。今ある組織のルールセット（I4） | リポジトリの admin が `main` の保護を外せないようにする。システム保全責任者が cdk-apps の admin を兼ねる条件 | |


## 最初に伝えること（1 分）

- S3 の原本バケットの守りを設計する中で、承認の流れを迂回できる経路を調べた。その結果、GitHub の owner・identity・GCP・Okta・Google Workspace の管理者が互いに届き合う「輪」になっていて、1 人で、通知なしに組織のほぼすべてに届く人が 10 名を超えていた（[privilege-map.md](privilege-map.md) の 9 章）。
- 誰かのやり方を責める話ではない。identity は鍵を人に配らないなど丁寧に作られている。ID 基盤が自分をコードで管理すると、この輪はできやすい。
- 一体で取り組みたい。案として「頂点を Google Workspace の super admin の専用アカウントに据え、矢印を一方向にする」を考えている（10 章）。その前提が正しいかを確かめたい。
- 画面を見せてもらえるものは、口頭より画面で確かめたい。

## A. 輪が本当に閉じているか（最優先）

案の前提を決める項目。時間が足りなければ、ここだけは聞く。

| # | 聞くこと | なぜ | 答え |
|---|---|---|---|
| I19 | Workspace のグループ `gcp-organization-admins@`・`gcp-security-admins@` に、GCP の組織と `corp-it-485102` で何のロールが付いているか。組織管理者（`roles/resourcemanager.organizationAdmin`）か | 付いていれば、identity の PR を 1 つ通すだけで GCP の組織管理者になり、apply の鍵すべてに届く。**輪を閉じている最重要の辺**（E1） | |
| I7 | `corp-it-485102` で、Secret Manager の `github-apply-private-key` などを読める主体と、`tf-github-apply@` を名乗れる主体。プロジェクトの owner は誰か | apply の鍵に届く人 | |
| I20 | `aws@`（名前は「AWS Admins」）は何に使っているか。AWS の root や管理アカウントの登録のメールか。いま誰に届くか | root のメールなら、identity の PR でメンバーを足して回復のメールを受け取れる（E4） | |
| I21 | Okta の apply の App（CD 用）に付いている管理ロールは、独自の最小のロールか、Organization Administrator か | README は最小のロールを推奨。実際の設定で Okta への辺の太さが変わる | |
| I5 | identity の `main` のブランチの保護。`enforce_admins`（admin にも適用）、古い承認の取り消し、最後の push の承認は有効か。README（admins included）と CODEOWNERS の注記（無効）が食い違っている | admin が承認なしでマージできるか（P7） | |
| I15 | identity の environment `okta-prod`・`google-workspace-prod` も、`github-prod` と同じく「ブランチの制限だけ」か | admin が制限を外せば、Okta と Google の apply の鍵も取れる（P5 と同じ手口） | |

## B. 頂点にいる人

| # | 聞くこと | なぜ | 答え |
|---|---|---|---|
| I16 | Google Workspace の特権管理者（super admin）は誰か（人数と人）。GCP の組織の管理者は誰か | 頂点そのもの | |
| I23 | super admin のアカウントは普段使いと分けているか。ログインは Okta を通るか、Google 自身のログインか。セキュリティキーは必須か | 頂点の人の要件の今の状態。Okta を通るなら Okta の管理者が頂点に届く（E2） | |
| I17 | Okta の特権管理者（Super Admin）は誰か。管理者のアカウントの要件（MFA の種類、専用のアカウントか） | 頂点の群の人 | |
| I18 | GCP の権限を持つ人のログインは Okta の SAML 経由か。SAML を迂回できる（Google 自身のログインができる）管理者は誰か | README の「管理者は SAML を bypass できる」の範囲 | |
| I22 | ドメイン（turing-motors.com）のレジストラと DNS の管理者は誰か。そのログインの方法と MFA | MX を変えれば、全サービスの回復のメールを奪える。頂点の一部 | |
| I14 | AWS の管理アカウントの root は誰が持ち、どう保管しているか。MFA は | AWS の最上位 | |
| I10 | AWS の管理アカウントの管理者（人数と人）、Identity Center の管理者、委任管理者 | AWS の頂点（U8） | |
| I1 | GitHub の組織の owner が 7 名である理由。2〜3 名に減らせるか | 頂点の枝を絞る | |
| I6 | `team-leaders` が `all_repo_admin` を持つ理由。外せるか | 全リポジトリの admin が 5 名いる（P2） | |

## C. 迂回と漏れ

| # | 聞くこと | なぜ | 答え |
|---|---|---|---|
| I24 | break-glass の資格情報（AWS の root、super admin、GitHub の回復コードなど）の置き場。Keeper（Okta の App）に置いているか | 置き場が Okta の下なら、Okta の管理者が頂点に届く（E5） | |
| I25 | GitHub の owner のアカウントの登録のメールと回復の手段は、会社のドメインか個人か | 会社の管理の外の回復の経路 | |
| I2 | GitHub の組織に入っている App と、その権限の一覧（AI エージェントを含む） | Administration や Members の書き込みを持つ App は、頂点の枝 | |
| I3 | GitHub の外部の協力者の一覧と、その権限 | 届く人の漏れ | |
| I13 | Okta の管理者のうち、AWS の権限セットにつながるグループを変えられる人 | Okta から FullAccess を付けられる経路 | |
| I12 | AWS の管理画面で直接した SSO の割り当て（`organization-policy` の外のもの）はあるか | 例外の権限セットに届く人の漏れ | |

## D. いまある守りと通知

| # | 聞くこと | なぜ | 答え |
|---|---|---|---|
| I8 | GitHub の組織の監査ログか webhook で、チーム・メンバー・ルールセット・environment の変更を即時に通知できるか。いま見ている人はいるか | 頂点が使われたら気づく | |
| I9 | identity の Terraform に、差分の定期の検知（画面での直接の変更に気づく）を足せるか | 直接の変更が次の apply まで残る | |
| I4 | GitHub の組織のルールセットの有無と中身。2 要素認証の必須化 | 組織の層の守り | |
| I11 | tuscenes-prod に効く SCP・RCP と、Control Tower のガードレールの中身 | S3 の案件の残りの調べ | |
| — | Workspace の管理ログ・GCP の監査ログ・Okta のシステムログを、いまどこかに送って見ているか | 輪の外での見張り（10.3 の 4）の出発点 | |

## 終わりに確かめること

- 10 章の案（頂点を super admin の専用アカウントに据える、特権のグループを IaC の書き込みから外す）への CorpIT の意見。
- 次に誰が何を見るか（画面を見せてもらう日、設定の一覧を出してもらうなど）。
