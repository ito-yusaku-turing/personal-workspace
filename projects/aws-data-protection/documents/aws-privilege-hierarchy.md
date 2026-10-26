# AWS の権限の階層（参考資料）

2026-10-20 作成 / 伊藤

複数の AWS アカウントを持つ組織で、権限の強さをどう階層にするかの整理。前半の一般論は古くならない内容、後半はうちの組織への当てはめと、日付つきの調査記録。

関連:
- [S3 バケットのデータ保護 第二弾](../workstream/s3-data-protection-2.md)（層 3〜5 を直す案件）
- [メンバーアカウントの root の認証情報を消す](../workstream/aws-root-credentials.md)（層 0 の root の案件）
- `~/security-review/issues.md` の H7〜H10（CI の経路の問題）

## 1. 一般論

### 頂点は「管理アカウントの root」だけではない

技術的に最も強いのは、管理アカウントの root。どのポリシーでも制限できない。ただし、実際の頂点はもっと広い。

| 頂点に並ぶもの | なぜ頂点か |
|---|---|
| 管理アカウントの root | どのポリシーでも制限できない |
| 管理アカウントの管理者全員 | SCP は管理アカウントには効かない。組織・SCP・IAM Identity Center の割り当てを変えられるので、自分に全アカウントの管理者を付けられる |
| IdP（Okta）の管理者 | AWS の外にいるが、自分を AWS の管理者グループに入れられる |
| root のメールの受信箱を読める人（メールドメインの管理者を含む） | パスワードを再設定して root に入れる |
| 管理アカウントに deploy する CI の経路を変えられる人 | CI のロールが管理者相当なら、その経路を通せる人は管理者と同じ |

つまり、頂点は次の 2 種類の人の集合になる。
- **権限を割り当てる仕組みを変えられる人**
- **root の認証情報に辿り着ける人**

設計の目標は、この集合を小さく保ち、その中で行われる操作を必ず記録し、通知することにある。

### 一般的な階層

AWS の Security Reference Architecture などで推奨されている形。

```
層 0  管理アカウント（＋IdP の管理者・root のメール・管理アカウントへの CI の経路）
       │ 組織・SCP・権限の割り当て・請求だけ。ワークロードは置かない
       │ 使う人は最小限。普段は使わない
       ▼
層 1  セキュリティ・ログのアカウント（委任管理者）
       │ CloudTrail の組織トレイル・GuardDuty・Security Hub など
       │ ログは消せない形で保管（Object Lock など）。ワークロードの管理者は触れない
       ▼
層 2  ガードレール（SCP / RCP、OU ごと）
       │ 「誰であっても」できないことを決める
       │ 例：root の操作を拒否、組織からの離脱を拒否、CloudTrail の停止を拒否、リージョンの制限
       ▼
層 3  メンバーアカウントの最大権限（break-glass・昇格用の権限セット）
       │ 普段は持たず、必要なときに短時間だけ昇格する
       ▼
層 4  日常の権限
       ├ 人：開発者・閲覧者の権限セット
       ├ CI/CD：アカウントごとの deploy ロール（main へのレビュー必須で守る）
       └ アプリ：必要なリソースとプレフィックスだけの最小権限
       ▼
層 5  リソース側の最後の守り
          バケットポリシーの Deny・Object Lock・KMS のキーポリシー
          （アカウント内の誰に対しても効く）
```

### 設計の原則

1. **「権限を変える権限」が最も強い。** `iam:*`、`sso:*`、`organizations:*`、`s3:PutBucketPolicy` などは、それ自体では何も壊さない。それでも、自分に何でも付けられる。データを消せる権限より上に置く。
2. **上の層は、予防できない分を検知で補う。** root や管理アカウントの管理者は、ポリシーで止めきれない。使われたら必ず誰かに通知が届くようにする。
3. **職務を分ける。** ガードレールやログを変えられる人と、ワークロードを動かす人を分ける。ワークロードを乗っ取られても、ログを消して痕跡を隠せないようにする。
4. **管理アカウントは空にする。** ワークロードを置くと、そこで動くアプリや CI まで頂点に加わる。Identity Center なども、できれば委任管理者のアカウントに出す。
5. **メンバーアカウントの root は無くす。** 一元管理（Centralized root access management）で認証情報を消す。root でしかできない作業は、管理アカウントから `sts:AssumeRoot` で行う。
   - 一元管理を有効にした**後**に作ったアカウントは、root の認証情報なしで作られる。
   - 有効にする**前から**あるアカウントには、認証情報が残る。1 アカウントずつ明示的に消す必要がある。
6. **CI は「その経路を変えられる人」の権限と同じ。** CI のロールの強さだけを見ても足りない。workflow・依存（lockfile）・Action・ブランチ保護を変えられる人まで数える。

## 2. うちの組織への当てはめ（2026-10-20 時点）

| 層 | うちの組織では | 状態 |
|---|---|---|
| 0 | 管理アカウント（210332786925）、Okta（identity リポジトリ）、root のメール。いずれも CorpIT の管理 | 管理アカウントの中は tuscenes-prod から見えない |
| 0 | cdk-apps の `apps/organization-policy`。管理アカウントに deploy され、Identity Center の権限セット・ユーザー・グループ・割り当てを管理する | 3 節。守りは丁寧だが穴がある |
| 0 | メンバーアカウントの root | tuscenes-prod はパスワードが有効で、MFA 無し。削除を CorpIT に依頼する（root の案件） |
| 1〜2 | Control Tower | ある。どのコントロールが付いているかは未確認 |
| 3〜5 | tuscenes-prod の SSO の権限セット、CI、アプリ、バケットポリシー | S3 の第二弾で直す |

## 3. 調査記録: organization-policy の経路（2026-10-20）

cdk-apps の main（`c9ee0565`）、GitHub の ruleset と Environment の設定を確認した。変更は何もしていない。

### 何を管理しているか

- `apps/organization-policy/bin/organization-policy.ts` の deploy 先は `env: { account: "210332786925", region: "us-west-2" }`、つまり管理アカウント。
- スタックは次の 4 つを持つ（`lib/organization-policy-stack.ts`）。このスタックを deploy できる人は、**自分に任意のアカウントの FullAccess を付けられる**。
  - IAM Identity Center の権限セット。FullAccess は `AdministratorAccess`
  - Identity Store のユーザー
  - Identity Store のグループ
  - グループの、各アカウントへの割り当て

### 今ある守り

- **CODEOWNERS**：次の 4 つは yamashush・MasahiroYasumoto のどちらかの承認が必須。
  - `apps/organization-policy/`
  - `.github/workflows/organization-policy-*.yml`
  - `.github/CODEOWNERS`
  - `.npmrc`
- **ruleset `main-image-digest-auto-merge`**（main に効く）：`require_code_owner_review: true`、承認 1。迂回できるのは自動マージ用の GitHub App（Integration 4444115）だけで、PR のマージに限る。
- **自動マージの App の鍵**：Environment `auto-merge` の secret にある。deployment branch policy は main のみ。任意の branch に足した workflow からは使えない。
- **管理アカウントの `ci-cdk-deploy-role`**：信頼の条件で、`sub` を main に、`job_workflow_ref` を `organization-policy-deploy.yml@refs/heads/main` に固定している。ほかの workflow からは assume できない。
- **deploy の job**：
  - 依存は `npm ci --ignore-scripts` で入れる。
  - Slack 通知は、id-token を持たない別の job で行う。
- **`ci-cdk-deploy-role` 自体**：CDK ではなく CloudFormation のテンプレートで、人が手で deploy する。CI が自分のロールを書き換えられないようにするため。

### 見つかった穴

| # | 穴 | 起こりうること | issues |
|---|---|---|---|
| 1 | ruleset が `dismiss_stale_reviews_on_push: false`、`require_last_push_approval: false` | まともな変更で Code Owner の承認をもらった後に、自分に FullAccess を付けるコミットを足し、そのままマージできる | H8 |
| 2 | 依存を入れるルートの `package-lock.json` は、mlops-1・mlops-3・planning-1 のだれか 1 人の承認で変えられる。README は「mlops の管理下」と書くが、CODEOWNERS で planning-1 が足されて広がっている | `aws-cdk-lib` などの取得先を差し替えると、管理アカウントの権限を持った deploy の job の中でそのコードが動く。README も「残っている穴」として認めている | H9 |
| 3 | workflow の Action（`actions/checkout@v6`、`actions/setup-node@v6`、`aws-actions/configure-aws-credentials@v6`）を、SHA ではなくタグで指定している | 外部の Action のタグが書き換えられると、管理アカウントの権限が渡る | H10 |

### 層 0 に入る人（この経路から見て）

- Code Owner の 2 人（承認する人）
- リポジトリの admin 9 人（kotarotanahashi・sangotaro・takuseno・rescircuit・graph226・khwatanabe・ymgaq・MasahiroYasumoto・yamashush）と、GitHub org の owner。ruleset を無効にすればマージできる
- 穴 1・2 を通して、cdk-apps に書き込める人のほぼ全員。承認する人 1 人が見落とすか、だれか 1 人と組めば足りる
- 管理アカウントの FullAccess を持つ人。`ci-cdk-deploy-role` の更新は、この権限で手で行う。誰が持つかは tuscenes-prod からは見えない

### 確かめていないこと

- 管理アカウントの `cfn-exec-role` の権限。CDK の初期設定なら `AdministratorAccess`。
- ruleset の `require_extra_approval_for_unattributed_changes: true` の意味。穴 1 の一部を塞いでいる可能性がある。
- ~~Identity Center が管理アカウントにあるのか、委任管理者のアカウント（CorpIT の 259604217662 など）にあるのか。~~ → インスタンスは管理アカウント 210332786925 にある（2026-10-20、[原本バケットへのアクセスの洗い出し](../workstream/done/s3-bucket-access-control.md) の進捗）。委任管理者のアカウントを置いているかは未確認。

### 塞ぎ方の案

どれを採るかは、cdk-apps の管理者と Code Owner が判断する。

- 穴 1：ruleset で「新しい push で承認を外す」「最後の push は別の人が承認する」を有効にする。全リポジトリのフローに影響する。
- 穴 2：README の案どおり、organization-policy の依存を専用の lockfile に分け、CODEOWNERS で 2 人の管理にする。
- 穴 3：Action を SHA で固定する。自動マージの workflow は、すでに SHA で固定している。
