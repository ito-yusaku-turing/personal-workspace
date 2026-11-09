# 原本バケットの保護の層と抜け穴（WORM の導入後の姿）

- 作成: 2026-11-06 ／ 伊藤（エージェントが起草）。2026-11-09 に、伊藤と合意した捉え方（1 章）で組み直した
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)
- 状態: **たたき台**。Notion に上げる前に、伊藤と整理するための作業資料。決めてほしいことは 6 章
- 前提: [worm-decisions.md](worm-decisions.md) の D7（古い版には保持をかけない）・D13（削除の運用は先送り）・D14（FullAccess を例外から外す）、G1（完全削除用の権限）・G2（SCP の範囲）。導入後の姿は共有用の資料 [notion-worm-governance-rollout.md](../../documents/notion-worm-governance-rollout.md) の 3 章。現状は [current-state.md](current-state.md) の 3 章

**要点**

- 原本バケットの保護を、**データ → バージョニング → バケットポリシー → Object Lock** の層で捉える。各層の抜け穴は、上の層が塞ぐ（2 章）。
- **どの層の抜け穴も、最後はバケットポリシー（層 2）に集まる。** 層 2 には上の層が無いので、層 2 の抜け穴（例外の主体・ポリシーを書き換えられる主体・例外を名乗る道）が、管理の対象になる（3 章）。Object Lock（層 3）の抜け穴も、層 2 の文で縛るので、層 2 に戻る（4 章）。
- 層 2 の抜け穴の多くは、意図して残す**緊急ハッチ**（deploy の経路・完全削除用の権限・root）。塞ぐのではなく、だれが使えて、使ったら気づけるかを管理する。
- 想定外の**抜け穴**は、**正規でない主体が、ハッチの cfn-exec-role を名乗る道**（X1〜X3）だけ。乗っ取られた主体（要件 7）が、PR もレビューも無しに、deploy の経路と同じ力を得る。これを塞ぐかが、いちばん大きな論点（6 章の 1）。

## 1. 捉え方（2026-11-09、伊藤と合意）

1. **保護の抜け穴は、緊急ハッチでもある。** 締め出されたときの戻し道や、意図して消すときの経路は、抜け穴と同じ形をしている。ハッチ（意図して残す）と抜け穴（想定外）を分けて扱う。
2. **大事なのは、抜け穴が無いことではなく、抜け穴を把握・管理できていること。** 要件（[requirements.md](requirements.md) の 3 章）も、検知（要件 3・9・10・13）と判断の記録（要件 12）を軸にしている。
3. **抜け穴の抜け穴を辿ると、範囲が際限なく広がる。** S3 バケットの保護を中心に層で捉え、どこまでを範囲にするかを先に決める（5 章）。組織全体の権限の階層は、ここでは扱わない（project:privileged-access）。

ハッチは、次の 4 点で管理する。

| 物差し | 根拠 |
|---|---|
| だれが使えるか（名簿があるか） | — |
| 使ったら即時に通知されるか | 要件 9・10・13 |
| 判断の記録と、2 人目の確認があるか | 要件 12 |
| 使うと**すぐ消せる**のか、**30 日の猶予が始まるだけ**か | すぐ消せるハッチほど、強い管理が要る |

## 2. 層と抜け穴

| 層 | 状態 | 守るもの | この層の抜け穴 | 塞ぐ層 |
|---|---|---|---|---|
| 0. データ | — | — | 通常の削除・上書き | 層 1（古い版が残るので戻せる） |
| 1. バージョニング | 導入済み（2026-10-20） | 上書き・削除されても、古い版が残る | ① 古い版の削除（`s3:DeleteObjectVersion`）、② ライフサイクルで古い版を失効させる、③ バージョニングの停止、④ バケットの削除 | 層 2（①④ は `DenyIrreversibleDelete`、②③ は `DenyProtectionRemoval`） |
| 2. バケットポリシー | 導入済み（2026-10-26） | 層 1 の抜け穴を、例外の主体以外に禁じる | ⑤ 例外の主体、⑥ ポリシーを書き換えられる主体、⑦ 例外を名乗る道 | **無い（最上位）**。3 章で管理する |
| 3. Object Lock | これから（手順 A〜D） | 最新の版を、イベントホールドを解除して 30 日たつまで消せなくする | ⑧ 迂回、⑨ イベントホールドの解除、⑩ 既定の保持設定の変更 | 層 2（⑧ は `DenyGovernanceBypass`、⑨ は `DenyLockChange`、⑩ は `DenyIrreversibleDelete`）。4 章 |

- Object Lock は、層 2 が保たれている間は「解除してから 30 日」の猶予を足す。層 2 を書き換えられる主体に対しては、独立した守りにならない（迂回の禁止を外せば迂回できる）。
- 古い版（最新でない版）には保持をかけない（D7）。古い版は層 2 だけで守る。

## 3. 層 2 の抜け穴の台帳

### 3.1 緊急ハッチ（意図して残す）

手順 D まで終えた姿。⑤（例外の主体）と ⑥（ポリシーを書き換えられる主体）は、ここではまとめて扱う。

| # | ハッチ | できること | だれが | 通知 | 判断の記録・2 人目 | 使うと |
|---|---|---|---|---|---|---|
| H1 | **deploy の経路**（cfn-exec-role。`DenyProtectionRemoval` の例外） | バケットの設定の変更（ポリシー・ライフサイクル・バージョニング） | cdk-apps の `main` にマージできる人（GitHub Actions の deploy） | される（バケットの設定の変更。拒まれた試みも） | PR とレビュー | 迂回の禁止を外せば、**すぐ消せる** |
| H2 | **完全削除用の権限**（今は AWSAdministratorAccess。`DenyIrreversibleDelete`・`DenyProtectionRemoval` の例外、ジョブのロールを渡せる） | 保護されていない版の削除、既定の保持設定の変更、バケットの設定の変更、ジョブでのイベントホールドの解除（H5） | 山本 修平さんほか 1〜2 名の見込み（アクション 2-1） | される | **無い**（削除の運用は先送り。D13） | 解除なら 30 日の猶予。迂回の禁止を外せば、**すぐ消せる**（共有用の資料の 4.4 の急ぎの戻し方も、この道） |
| H3 | **FullAccess**（暫定の例外） | H2 と同じ（td1-raw・tuscenes-raw の古い版の削除を除く） | 14 名 | される | 無い | **手順 D（D14）で例外から外す**。外すまでは H2 と同じ |
| H4 | **root・管理アカウント**（AWS の仕様で、バケットポリシーで止められない） | バケットポリシーの削除（root の `DeleteBucketPolicy`、管理アカウントの `S3UnlockBucketPolicy`） | tuscenes-prod の root の鍵を持つ人、管理アカウントの管理者 | される（バケットの設定の変更） | 無い | 締め出されたときの戻し道。ポリシーを消せば、**すぐ消せる**。tuscenes-prod の root は認証情報の削除を依頼中（[aws-root-credentials.md](../aws-root-credentials.md)） |

### 3.2 想定外の抜け穴: ⑦ 例外を名乗る道

バケットポリシーの例外は、主体の ARN で照合している。deploy の経路の例外は `arn:aws:iam::767397804933:role/cdk-hnb659fds-cfn-exec-role-767397804933-*`（[bucket-policy/statements.json](bucket-policy/statements.json)）。この ARN を、正規の経路（GitHub Actions）以外から名乗れる道が 3 つある。

| # | 道 | だれが | 通知 | 塞ぐ手段の案（SCP） | 止まるもの |
|---|---|---|---|---|---|
| X1 | deploy のロール（`cdk-hnb659fds-deploy-role-*`）を引き受け、CloudFormation でバケットポリシーを書き換える。信頼が `767397804933:root` なので、アカウントの中でだれでも引き受けを試せる | FullAccess・AWSAdministratorAccess・Databricks のロール 1 本・Amplify のロール 6 本など（current-state.md の 3.2） | 引き受けは通知されない。最後のバケットポリシーの変更は通知される | deploy のロールの引き受け（`sts:AssumeRole`）を、GitHub Actions の deploy のロールと `AWSControlTowerExecution` 以外に禁じる | 手元からの `cdk diff`（止まるかは未確認。7 章） |
| X2 | cfn-exec-role を自分で CloudFormation に渡し（`iam:PassRole`）、スタックでバケットポリシーを書き換える。deploy のロールを通らない | `iam:PassRole` とスタックの作成を持つ主体（FullAccess・AWSAdministratorAccess など。全主体の判定は [iam-scan/escalation.py](iam-scan/escalation.py)） | 同上 | cfn-exec-role を渡す操作を、deploy のロールと `AWSControlTowerExecution` 以外に禁じる | 無い見込み（正規の deploy では deploy のロールが渡す。7 章で確かめる） |
| X3 | `cdk-hnb659fds-cfn-exec-role-767397804933-*` という名前のロールを作る、または今の cfn-exec-role の信頼を書き換えて、自分で引き受ける。今の SCP `iam-guardrails` が守るのは `/aws-reserved/` のパスのロールだけで、パスが `/` のこのロールは守られていない | IAM を操作できる主体（FullAccess・AWSAdministratorAccess など） | 同上（ロールの作成・信頼の変更は、要件 9 では通知の対象。今の設計では拾っていない） | `cdk-hnb659fds-*` のロールの作成・削除・信頼の変更・ポリシーの変更を禁じる（TODO 24。`DenyReservedPathRoles` と同じ形） | `cdk bootstrap` のやり直し。だれがどう行うかを決める |

- X1〜X3 は、H1 と同じ力（バケットの設定の変更 → 迂回の禁止を外してすぐ消す）を、**PR もレビューも無しに**得る道。脅威の範囲（要件 7）の「乗っ取られた主体」が、ここを使える。
- D14（FullAccess を例外から外す）で塞がるのは、FullAccess が H3 として直接書き換える道だけ。X1〜X3 が開いている間は、FullAccess は間接に書き換えられる。**D14 の効果を出すには、X1〜X3 を同時か先に塞ぐ必要がある。**

## 4. 層 3 の抜け穴の台帳

| 抜け穴 | 層 2 の文 | ハッチ | そのほかの道と塞がり方 |
|---|---|---|---|
| ⑧ 迂回（`s3:BypassGovernanceRetention`） | `DenyGovernanceBypass`（例外なし） | 無い | 層 2 を書き換えられる主体（H1・H2・H4、X1〜X3）は、文を外して迂回できる。層 2 に戻る |
| ⑨ イベントホールドの解除（`s3:PutObjectRetention`・`s3:PutObjectLegalHold`） | `DenyLockChange`（例外はジョブのロールだけ） | **H5: ジョブのロール**（`/central/original-bucket-lock-batch`）。ロールを渡せるのは H2 だけ（SCP `DenyPassLockBatchRole`、予定）。解除の後 30 日の猶予。解除は通知される | 自分で作ったロールでジョブを流す → 例外の ARN でないので拒まれる。ジョブのロールの中身を変える → SCP `DenyCentralRoleChanges`（既存）で拒まれる。**導入の途中（手順 B〜D）は、FullAccess なども解除できる**（共有用の資料の 5.1） |
| ⑩ 既定の保持設定の変更（`s3:PutBucketObjectLockConfiguration`） | `DenyIrreversibleDelete`（例外は H2） | H2 | 層 2 に戻る |

- H5 の鍵（ジョブのロールを渡せること）は、SCP で H2 に絞る。SCP を書き換えられる主体は範囲の外（5 章）。

## 5. 範囲

| 区分 | 中身 |
|---|---|
| **範囲内** | 層 1〜3 の抜け穴。層 2 のハッチ（H1〜H4）と、ハッチの鍵をだれが持つか（H5 を含む）。⑦ 例外を名乗る道（X1〜X3） |
| **書き留めて打ち切る** | 通知の仕組み（ルール・アラーム・SNS）を外してから層 2 を書き換える道。通知の仕組みの変更も通知するが、最後の 1 つを外す操作は通知されない（共有用の資料の 3.6）。これ以上は追わない |
| **範囲外** | X1〜X3 を塞ぐ手段（SCP など）を、さらにだれが書き換えられるか。管理アカウント・IdP・GitHub の権限（project:privileged-access）。FullAccess が自分の SSO のロールから td1-raw・tuscenes-raw の Deny を外す道（層 0 の話で、層 1 が守る） |

## 6. 決めてほしいこと

1. **X1〜X3 を塞ぐか、受け入れて通知で管理するか。** エージェントの案は**塞ぐ**（3 つとも SCP）。乗っ取られた主体が、レビュー無しに H1 と同じ力を得る道で、D14 の前提でもあるため。塞ぐなら、D14 と同じ手順 D に入れる。
2. **H1・H2 の「すぐ消せる」を受け入れるか。** 迂回の禁止を RCP にも重ねる（バケットポリシーを書き換えても迂回できなくする）と、H1・H2 は「30 日の猶予」だけのハッチになる。代わりに、急ぎの戻し方（共有用の資料の 4.4）が、管理アカウントで RCP を外す作業になり、ハッチが範囲の外へ移る。RCP は組織で有効になっていない（2026-11-06 に `describe-organization` で確認）ので、有効にするところから始まる（CorpIT・organization-policy の CODEOWNERS と相談）。エージェントの案は、**手順 D では受け入れて通知で管理し、RCP は別の手順 E として後で決める**。
3. **H2（完全削除用の権限）の形**（G1）。
   - a. AWSAdministratorAccess のまま: 新しく作るものが無い。持つ人がほかの用途でも日常的に使い、名簿も見えていない。
   - b. 専用の権限セットを作り、ふだんから割り当てる: 権限が狭く、層 2 の例外をこれ 1 つに向けられる。使われたら完全削除の作業と分かる。
   - c. b を、使うときだけ organization-policy の PR で割り当てる: PR が判断の記録と 2 人目の確認になる（要件 12）。H2 の「記録・2 人目が無い」が埋まる。
   - エージェントの案は **c**（少なくとも b）。完全削除は急がない（30 日かかる）ので、割り当てを待っても困らない。
4. **H3（FullAccess）を外すまでの扱い。** 手順 B・C の作業は FullAccess で行うので、外すのは手順 D（D14）。それまでは、FullAccess（14 名）が H2 と同じハッチで、イベントホールドも解除できる。この期間は通知が主な守りになることを、共有用の資料に書く。

## 7. 確かめること

- [ ] X1: deploy のロールを、GitHub Actions 以外から引き受けているもの（ほかのリポジトリからの deploy、lookup のロール・file-publishing のロール・image-publishing のロールの扱い）。CloudTrail の `AssumeRole` を 90 日分引く。手元の `cdk diff` が止まるか。
- [ ] X2: 正規の deploy で、cfn-exec-role を渡しているのが deploy のロールだけか（CloudTrail の `CreateChangeSet`・`PassRole`）。
- [ ] X3: `cdk bootstrap` を最後にだれがいつ行ったか（`CDKToolkit` のスタックのイベント）。
- [ ] X3: ロールの作成・信頼の変更を、通知で拾えているか（要件 9）。
- [ ] H2: AWSAdministratorAccess を持つほかの 1〜2 名（アクション 2-1）。案 b・c なら、Batch Operations のジョブの作成に要る権限の最小の組。
- [ ] tuscenes-prod に付いている SCP の全体（管理アカウントの権限が要る。Control Tower のガードレールを含む）。
- [ ] RCP の仕様（6 章の 2 を検討するとき。root・サービスにリンクされたロール・AWS のサービスの主体への効き方、`aws:PrincipalArn` での例外の書き方）。

## 付録: 2026-11-06 版の番号との対応

11-06 版は、経路を R1〜R13、塞ぐ手段を S1〜S9 で呼んでいた。workstream の 11-06 の記録はこの番号を使っている。

| 11-06 版 | この版 |
|---|---|
| R1（自分の権限で古い版を消す・設定を変える） | H3（D14 で外す） |
| R2（deploy のロールを引き受ける） | X1 |
| —（11-09 に見つけた。cfn-exec-role を自分で渡す） | X2 |
| R3（cfn-exec-role の名前のロールを作る・信頼を変える） | X3 |
| R4（cdk-apps の `main` にマージする） | H1 |
| R5〜R7（自分のロール・ジョブのロールを渡す・ジョブのロールを変える） | 4 章の ⑨（塞がる） |
| R8（完全削除用の権限で迂回の禁止を外す） | H2 の「すぐ消せる」 |
| R9（完全削除用の権限で解除して 30 日待つ） | H2・H5（正規の経路） |
| R10（通知の部品を外す） | 5 章の「書き留めて打ち切る」 |
| R11（root） | H4 |
| R12（管理アカウント） | H4（`S3UnlockBucketPolicy`）と、範囲外 |
| R13（SSO のロールのポリシーを変える） | 範囲外（層 1 が守る） |
| S1・S2 | X1・X3 を塞ぐ手段 |
| S3（`DenyPassLockBatchRole`） | H5 の鍵 |
| S4（迂回の禁止を RCP にも） | 6 章の 2 |
| S5・S6（層 2 の文を RCP にも重ねる）、S7（通知の部品）、S8（root）、S9（SSO のロール） | 外した。S5・S6 は層 2 の二重化、S7〜S9 は範囲の外か、打ち切ったもの |

## 出典

- cdk-apps（2026-11-06 の `main`、`bf609590`）: `apps/organization-policy/lib/iam-guardrails.ts`（SCP `iam-guardrails`。`/aws-reserved/` のロールを守る文）、`lib/permission-sets.ts`（FullAccess の中身は `AdministratorAccess`）、`README.md`（deploy の承認と、SCP の効かない範囲）
- [bucket-policy/statements.json](bucket-policy/statements.json)（層 2 の 2 文と例外の ARN）
- tuscenes-prod の ReadOnly（2026-11-06）: deploy のロールと cfn-exec-role の信頼と付いているポリシー、`organizations describe-organization`（有効なポリシーの種類は SCP だけ）
- [current-state.md](current-state.md) の 3 章（例外を名乗れる主体）、共有用の資料の 3 章・5.1
