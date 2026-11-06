# 原本バケットの権限の整理（WORM の導入後の姿と、SCP・RCP で守る範囲）

- 作成: 2026-11-06 ／ 伊藤（エージェントが起草）
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)
- 状態: **たたき台**。Notion に上げる前に、伊藤と整理するための作業資料。決めてほしいことは 7 章
- 前提: [worm-decisions.md](worm-decisions.md) の D13（削除の運用は先送り）・D14（FullAccess を例外から外す）、G1（完全削除用の権限）・G2（SCP の範囲）。現状は [current-state.md](current-state.md) の 3 章

**要点**

- 原本バケットの守りは、**5 つの層**（IAM のポリシー・バケットポリシー・Object Lock・SCP・RCP）でできている。層ごとに「誰に効くか」と「誰が書き換えられるか」が違う。強さは「書き換えられる人がどこにいるか」で決まる（1 章）。
- 今の設計（手順 D まで）の守りは、ほぼ**バケットポリシー 1 枚**に乗っている。バケットポリシーは tuscenes-prod の中から書き換えられるので、書き換えられる主体が実質の上限になる。
- **FullAccess を例外から外しても、FullAccess は間接にバケットポリシーを書き換えられる。** FullAccess の中身は AWS 管理ポリシーの `AdministratorAccess` で、IAM を自由に操作できる。deploy のロールを引き受ける（信頼が `767397804933:root`）か、`cdk-hnb659fds-cfn-exec-role-*` という名前のロールを作れば、バケットポリシーの例外を名乗れる（3 章の R2・R3）。**D14 を効かせるには、この 2 つの経路を SCP で塞ぐ必要がある。**
- 組織のポリシーで有効なのは SCP だけで、**RCP は有効になっていない**（`describe-organization`、2026-11-06）。RCP は、主な禁止を tuscenes-prod の中から外せない層へ移せる。ただし、管理アカウントでポリシーの種類を有効にするところから始める（5 章）。

## 1. 守りの層

| 層 | どこにあるか | 誰に効くか | 効かない相手 | 誰が書き換えられるか |
|---|---|---|---|---|
| ① IAM のポリシー（権限セット・ロールのポリシー） | 権限セットは管理アカウント（cdk-apps の `apps/organization-policy`）。ロールは tuscenes-prod | その主体だけ | ほかの主体 | 権限セット: 管理アカウントの deploy（CODEOWNERS の 2 名の承認）。**SSO のロールのポリシー**: tuscenes-prod で IAM を操作できる主体（FullAccess を含む。`DenyReservedPathRoles` は信頼の変更だけを止め、ポリシーの変更は止めない） |
| ② バケットポリシー | tuscenes-prod の各バケット（cdk-apps の `packages/original-bucket-guard`） | tuscenes-prod の中の全員と、ほかのアカウント | 例外にした主体。root と管理アカウントの `S3UnlockBucketPolicy` には、ポリシーの削除を止められない（AWS の仕様） | 例外の主体（`DenyProtectionRemoval` の例外）、deploy のロール（CloudFormation）、root、管理アカウント |
| ③ Object Lock（バージョンの保持） | 各バージョン | 全員（root も） | ガバナンスモードでは、迂回の権限を持つ主体 | 保持の変更の権限（`s3:PutObjectRetention`）と迂回の権限を持つ主体。②で絞る |
| ④ SCP | 管理アカウント（`apps/organization-policy` の `iam-guardrails` など） | tuscenes-prod の主体（root を含む） | 管理アカウントの主体、サービスにリンクされたロール、ほかのアカウントの主体 | 管理アカウントの管理者、organization-policy の deploy |
| ⑤ RCP（未導入） | 管理アカウント | tuscenes-prod のリソース（S3 など）へのリクエスト。ほかのアカウントの主体からのものも含む（ドキュメントによる） | サービスにリンクされたロール（ドキュメントによる・要確認） | ④と同じ |

- ①②は tuscenes-prod の中から書き換えられる。④⑤は管理アカウントからしか書き換えられない。**守りを④⑤に移すほど、tuscenes-prod の中の強い主体（FullAccess・deploy のロール・root）が乗っ取られても外せなくなる。** 代わりに、書き換えの力が管理アカウントに集まる（project:privileged-access の頂点の群）。
- 管理アカウントの organization-policy の deploy は、CODEOWNERS（2 名のどちらか）の承認が要り、deploy のロールは `main` の専用の workflow からしか引き受けられない（`apps/organization-policy/README.md`）。今ある経路のうち、2 人目の確認がいちばん強くかかっている。

## 2. 主体

| 主体 | 中身 | 人・入り方 |
|---|---|---|
| 書き込み元のシステム・一般の利用者 | 各アプリのロール、`TeamE2E` などの権限セット | 多数（current-state.md の 3.3・3.4） |
| FullAccess | 権限セット。AWS 管理ポリシー `AdministratorAccess`＋td1-raw・tuscenes-raw の `s3:DeleteObject*` の Deny（インライン） | 14 名（Group 3・Group 4 の正社員） |
| **完全削除用の権限** | 保護されたバージョンを最終的に消すために、保護を外せる権限。今は SSO の `AWSAdministratorAccess`（Control Tower の既定の権限セット） | 山本 修平（`Engineers`）。ほかに 1〜2 名の見込み |
| ジョブのロール `central/original-bucket-lock-batch`（予定） | S3 Batch Operations だけが引き受ける。保持の変更ができる | 人は入れない。ロールを渡せるのは完全削除用の権限だけ（予定） |
| deploy のロール | `cdk-hnb659fds-deploy-role-*`（信頼は `767397804933:root`。アカウントの中のだれでも引き受けを試せる）→ CloudFormation → `cdk-hnb659fds-cfn-exec-role-*`（`AdministratorAccess`） | 正規の経路は GitHub Actions（cdk-apps の `main` へのマージ）。ほかに FullAccess・AWSAdministratorAccess・Databricks のロール 1 本・Amplify のロール 6 本などが引き受けられる（current-state.md の 3.2） |
| tuscenes-prod の root | パスワードあり・MFA なし | CorpIT に削除を依頼中（[aws-root-credentials.md](../aws-root-credentials.md)） |
| 管理アカウントの管理者 | SCP・RCP・権限セットを変えられる。`AWSControlTowerExecution` で tuscenes-prod に入れる。root の一元管理の `S3UnlockBucketPolicy` | project:privileged-access の頂点の群 |

## 3. 原本バケットを壊す経路と、今の設計での塞がり方

「今の設計」は、共有用の資料の手順 D まで終えた姿（バケットポリシーの 4 文・ジョブのロール・SCP `DenyPassLockBatchRole`）。

| # | 経路 | だれが | 今の設計で | 塞ぐ層の候補 |
|---|---|---|---|---|
| R1 | 自分の権限で、古いバージョンを消す・保持を外す・バケットの設定を変える | FullAccess ほか | **塞がる**（② の 4 文） | — |
| R2 | deploy のロールを引き受け、CloudFormation でバケットポリシーを書き換える（迂回の禁止を外す → 迂回して消す） | FullAccess、Databricks・Amplify のロールなど、deploy のロールを引き受けられる主体 | **開いている**。変更は通知される | ④ deploy のロールの引き受けを、GitHub Actions のロール以外に禁じる（S1） |
| R3 | `cdk-hnb659fds-cfn-exec-role-*` という名前のロールを作る、または今のロールの信頼を書き換えて、自分で引き受ける。② の例外を名乗れる | IAM を操作できる主体（FullAccess など） | **開いている** | ④ `cdk-hnb659fds-*` のロールの作成・削除・信頼の変更を禁じる（S2。TODO 24） |
| R4 | `cdk-apps` の `main` に、バケットポリシーを書き換える変更をマージする | マージできる人 | **開いている**。PR のレビューと通知で気づく | 運用（レビュー）。⑤に移せば、②を書き換えても守りは外れない（S4〜S6） |
| R5 | 自分でロールを作り、Batch Operations で保持を外す | FullAccess ほか | **塞がる**（② の `DenyLockChange` は主体の ARN で照合） | — |
| R6 | ジョブのロールを渡して、保持を外すジョブを作る | FullAccess ほか | **塞がる**（④ `DenyPassLockBatchRole`。予定） | — |
| R7 | ジョブのロールの中身を書き換える | FullAccess ほか | **塞がる**（④ 既存の `DenyCentralRoleChanges`） | — |
| R8 | 完全削除用の権限で、バケットポリシーから迂回の禁止を外し、迂回して消す（30 日を待たずに） | 完全削除用の権限 | **開いている**。変更は通知される | ⑤ 迂回を RCP で全員に禁じる（S4） |
| R9 | 完全削除用の権限で、ジョブで保持を外し、30 日待って消す | 完全削除用の権限 | **想定どおりの経路**。解除は通知される | — |
| R10 | 通知の部品（EventBridge のルール・アラーム・SNS）を外してから、R2〜R4 を行う | FullAccess、deploy のロール | **開いている**。部品の変更も通知するが、最後に残った部品を外す操作は通知されない | ④ 通知の部品の変更を、deploy のロール以外に禁じる（S7）。ただし R2・R3 が開いていると効かない |
| R11 | root で、バケットポリシーを消す | tuscenes-prod の root | **開いている**。root の認証情報の削除を依頼中 | root の認証情報を消す（別の案件）。④ で root の S3 の操作を禁じる（S8） |
| R12 | 管理アカウントから、SCP・RCP を外す、`S3UnlockBucketPolicy` でポリシーを消す、`AWSControlTowerExecution` で入る | 管理アカウントの管理者 | **開いている**（tuscenes-prod の中の層では止められない） | 範囲の外。project:privileged-access で扱う |
| R13 | 自分の SSO のロール（`AWSReservedSSO_FullAccess_*`）のポリシーから、td1-raw・tuscenes-raw の Deny を外す | FullAccess | **開いている**。ただし ② が残るので、古いバージョンは消せない（通常の削除ができるようになるだけ） | ④ SSO のロールのポリシーの変更を禁じる（S9） |

- **D14（FullAccess を例外から外す）で塞がるのは R1 だけ。** FullAccess は R2・R3 で、間接にバケットポリシーを書き換えられる。FullAccess を外す効果を出すには、少なくとも S1・S2 が要る。
- R2・R3 は、FullAccess のほか、乗っ取られた Databricks のロールや Amplify のロールにも開いている（current-state.md の 3.2）。

## 4. 目標の姿: だれが何をできるか

手順 D に S1・S2 を足した姿を案とする（S4 以降は 7 章で決める）。

| 操作 | 書き込み元・一般の利用者 | FullAccess | 完全削除用の権限 | ジョブのロール | deploy のロール（GitHub Actions） | 守る層 |
|---|---|---|---|---|---|---|
| 読み取り・書き込み・上書き・通常の削除 | 今の権限のまま | できる（td1-raw・tuscenes-raw の通常の削除を除く） | できる | — | — | ① |
| イベントホールドの解除・付け直し | できない | できない | ジョブを作れば、ジョブのロールが行う | **できる** | できない | ②（`DenyLockChange`）・④（`DenyPassLockBatchRole`） |
| 迂回して消す | できない | できない | できない（※） | できない | できない（※） | ②（`DenyGovernanceBypass`）。S4 で ⑤ |
| 保護されていないバージョンを指定した削除 | できない | できない | **できる** | — | できない | ②（`DenyIrreversibleDelete`） |
| 既定の保持設定の変更 | できない | できない | できる | — | できない | ② |
| バケットの設定の変更（ポリシー・ライフサイクル・バージョニング） | できない | できない（S1・S2 で間接の経路も塞ぐ） | できる | — | できる | ②・④（S1・S2） |
| deploy のロールの引き受け | — | できない（S1） | できない（S1）※要検討 | — | できる | ④（S1） |

- ※ バケットポリシーを書き換えられる主体（完全削除用の権限と deploy のロール）は、迂回の禁止を外せば迂回できる（R4・R8）。S4（RCP）を入れれば、tuscenes-prod の中からはだれもできなくなる。
- 完全削除用の権限が「保護されたバージョンを消す」には、ジョブで解除 → 30 日待つ → バージョンを指定して消す（またはライフサイクル）、の順になる（R9）。
- S1 で、手元からの `cdk diff` に影響が出るおそれがある。`cdk diff` は deploy 済みのテンプレートを deploy のロールで読む。新しい版の CDK は、引き受けられないと lookup のロールに切り替えるとされるが、確かめていない（8 章）。止まるなら、diff は GitHub Actions で取る運用にする。

## 5. SCP・RCP の候補

| # | 層 | 中身 | 塞ぐ経路 | 止まるもの・注意 | 例外 |
|---|---|---|---|---|---|
| S1 | ④ SCP | deploy のロール（`cdk-hnb659fds-deploy-role-*`）の引き受け（`sts:AssumeRole`）を禁じる | R2 | 手元での `cdk diff`・`cdk deploy`（deploy は Actions だけの運用なので影響は diff だけ）。Databricks・Amplify のロールの抜け道もまとめて塞がる。CDK の lookup のロール・file-publishing のロールは別に考える | GitHub Actions の deploy のロール、`AWSControlTowerExecution` |
| S2 | ④ SCP | `cdk-hnb659fds-*` のロールの作成・削除・信頼の変更・ポリシーの変更を禁じる（`DenyReservedPathRoles` と同じ形） | R3 | `cdk bootstrap` のやり直し（bootstrap のスタックの更新）。だれがどう行うかを決める | `AWSControlTowerExecution`。bootstrap を行う主体 |
| S3 | ④ SCP | ジョブのロールを渡す操作（`iam:PassRole`）を禁じる（**設計済み**の `DenyPassLockBatchRole`） | R6 | — | 完全削除用の権限 |
| S4 | ⑤ RCP | 原本バケットでの迂回（`s3:BypassGovernanceRetention`）を全員に禁じる | R4・R8 | 日数を誤ったときに直すには、管理アカウントで RCP を外す必要がある（共有用の資料の 4.4） | なし |
| S5 | ⑤ RCP | 原本バケットでの保持の変更（`s3:PutObjectRetention`・`s3:PutObjectLegalHold`）を、ジョブのロール以外に禁じる | R4・R5（② の `DenyLockChange` を外しても効く） | ② と二重になる。ジョブのロールの ARN の照合を RCP でも確かめる | ジョブのロール |
| S6 | ⑤ RCP | 原本バケットでの、バージョンを指定した削除・バケットの削除・既定の保持設定の変更を、完全削除用の権限以外に禁じる | R4（② の `DenyIrreversibleDelete` を外しても効く） | ② と二重になる | 完全削除用の権限 |
| S7 | ④ SCP | 通知の部品（ルール・アラーム・SNS のトピック・ロググループ）の変更・削除を禁じる | R10 | 部品を変える deploy。S1・S2 が無いと、deploy のロールを通して外せる | deploy のロール |
| S8 | ④ SCP | tuscenes-prod の root の、S3 のバケットの設定の変更を禁じる | R11 | root の一元管理と、root の認証情報の削除（別の案件）と重なる。Control Tower の root の制限で代えられるかを見る | — |
| S9 | ④ SCP | SSO のロール（`/aws-reserved/`）のポリシーの変更を禁じる（今の `DenyReservedPathRoles` に足す） | R13 | Identity Center は service-linked role で変えるので止まらない（README の記述） | `AWSControlTowerExecution` |

**RCP について（ドキュメントによる。3-3 で確かめる）**

- 組織で RCP のポリシーの種類を有効にする必要がある（今は SCP だけ。2026-11-06 に `describe-organization` で確かめた）。
- RCP は、メンバーアカウントのリソース（S3 を含む）へのリクエストに効き、ほかのアカウントの主体や root からのリクエストも制限できる。サービスにリンクされたロールには効かない。管理アカウントのリソースには効かない。
- RCP は「上限」なので、許可は与えない。Deny の書き方は SCP と同じで、`aws:PrincipalArn` の条件で例外を書ける。
- AWS のサービスの主体（CloudTrail・Inventory の書き込み先など）からのリクエストにも効くので、原本バケットに限った Deny にし、`aws:PrincipalIsAWSService` などで巻き込みを避ける。

**組み合わせの案**

| 案 | 中身 | 残る経路 | 手間 |
|---|---|---|---|
| A. 最小 | 今の設計（S3）＋ S1・S2 | R4・R8・R10〜R12 | SCP の文を 2 つ足すだけ。S1 の diff の運用の変更 |
| B. 中 | A ＋ S4（迂回だけ RCP） | R4（ポリシーの書き換えで保持の変更・削除の禁止は外せるが、迂回はできない）・R10〜R12 | RCP の有効化。日数の誤りを直す手順が管理アカウントの作業になる |
| C. 大 | B ＋ S5・S6・S7・S9 | R11・R12 | 二重の管理。例外の主体（ジョブのロール・完全削除用の権限）の ARN を、② と ⑤ の 2 か所で揃える |

- **エージェントの案は B。** A は D14 を効かせるための最低限で、B で「バケットポリシーを書き換えても 30 日を待たずに消す道」が tuscenes-prod の中から無くなる。C は、完全削除用の権限を専用に新しく作るか（6 章）が決まってから考えるのがよい（例外の ARN が変わるため）。

## 6. 完全削除用の権限

| 案 | 中身 | よい点 | 気になる点 |
|---|---|---|---|
| a. `AWSAdministratorAccess` のまま | Control Tower の既定の権限セット。今の 1〜3 名 | 新しく作るものが無い | 持つ人が、ほかの用途でも日常的に使う（山本さんは 10-30・11-02 に読み取りで使った）。持つ人が頂点の群の人（GitHub の owner・GCP）と重なる。管理画面で直接した割り当てが見えていない |
| b. 専用の権限セットを新しく作る | 例: 完全削除に要る権限（ジョブのロールを渡す・Batch Operations のジョブの作成・バージョンを指定した削除）だけを持つ。ふだんから割り当てる | 権限が狭い。② ④ の例外を、これ 1 つに向けられる。使われたら必ず完全削除の作業とわかるので、サインインを通知にできる | 新しい権限セットと名簿の管理が要る（organization-policy の承認） |
| c. b を、使うときだけ割り当てる | ふだんはだれにも割り当てず、要るときに organization-policy の PR で割り当てる | PR が判断の記録と 2 人目の確認になる（要件 12） | 割り当ての PR の承認者（CODEOWNERS の 2 名）が、実質の承認者になる |

- 10-30 に撤回の方向にした BreakGlass（D1）は「許可を待たずに使える昇格」で、要件 12（2 人目の確認）とぶつかった。完全削除は急がない（30 日かかる）ので、c はこのぶつかりが無い。
- **エージェントの案は c（少なくとも b）。** 案 c なら、完全削除用の権限を「名簿」ではなく「PR」で管理できる。

## 7. 決めてほしいこと

1. 3 章の経路の見立て（とくに R2・R3 で、FullAccess を例外から外しても間接に書き換えられること）が合っているか。
2. SCP・RCP の組み合わせ（5 章の A〜C）。手順 D に入れるもの。
3. S1 を入れるなら、手元での `cdk diff` をやめ、GitHub Actions の diff にしてよいか。
4. 完全削除用の権限の案（6 章の a〜c）。
5. RCP を有効にするか（管理アカウントの作業。CorpIT・organization-policy の CODEOWNERS と相談）。

## 8. 確かめること

- [ ] S1: CDK の deploy の経路で、GitHub Actions 以外に deploy のロールを使うもの（lookup のロール・file-publishing のロール・image-publishing のロールの扱い、ほかのリポジトリからの deploy）。CloudTrail の `AssumeRole` を、deploy のロールについて 90 日分引く。
- [ ] S2: `cdk bootstrap` を最後にだれがいつ行ったか（`CDKToolkit` のスタックのイベント）。
- [ ] RCP の仕様（root・サービスにリンクされたロール・AWS のサービスの主体への効き方、大きさの上限、`aws:PrincipalArn` での例外の書き方）。
- [ ] tuscenes-prod に付いている SCP の全体（管理アカウントの権限が要る。Control Tower のガードレールを含む）。
- [ ] 完全削除用の権限の案 b・c で、Batch Operations のジョブの作成に要る権限の最小の組。

## 出典

- cdk-apps（2026-11-06 の `main`）: `apps/organization-policy/lib/iam-guardrails.ts`（SCP `iam-guardrails` の 8 文）、`lib/permission-sets.ts`（FullAccess の中身）、`README.md`（deploy の承認と、SCP の効かない範囲）
- tuscenes-prod の ReadOnly（2026-11-06）: deploy のロールと cfn-exec-role の信頼と付いているポリシー、`organizations describe-organization`（有効なポリシーの種類は SCP だけ）
- [current-state.md](current-state.md) の 3 章（例外を名乗れる主体）、[worm-quickwin-design.md](worm-quickwin-design.md) の 2 章・2.1
