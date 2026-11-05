# tuscenes-prod の FullAccess・AWSAdministratorAccess を持つ人

作成: 2026-11-05 ／ 伊藤

<!-- Notion: （未作成。上げたら URL を書く。このファイルが原本） -->

tuscenes-prod（原本バケットのある AWS アカウント）で、SSO の権限セット FullAccess と AWSAdministratorAccess を持つ人の一覧です。共有用の資料「原本バケットの WORM 化: ガバナンスモードでの導入」で、誰が何をできるか（3.2）や、承認する人（7 章）を考えるための資料です。

**要点**

- **AWSAdministratorAccess** を持っていると分かっているのは、**山本 修平さん 1 名**です。ほかに 1〜2 名いる見込みで、確かめています。
- **FullAccess** を持つのは、自動運転第 3 グループと第 4 グループの正社員で、**14 名**です。
- どちらも 2026-11-05 時点で、Identity Center のグループのメンバーから数えました。グループを通さない割り当て（ユーザーへの直接の割り当て）は、まだ確かめていません。

## 1. 2 つの権限セット

| | FullAccess | AWSAdministratorAccess |
|---|---|---|
| 中身 | AWS 管理ポリシーの `AdministratorAccess`。ただし td1-raw と tuscenes-raw のオブジェクトの削除（`s3:DeleteObject*`）を Deny | AWS 管理ポリシーの `AdministratorAccess`（Deny なし） |
| 作ったもの | cdk-apps の `apps/organization-policy`（`permission-sets.ts`） | Control Tower（2022 年に導入したときに作られたもの） |
| セッションの長さ | 12 時間 | — |
| 割り当ての経路 | Okta のグループ（SCIM で Identity Center に同期）。割り当ては cdk-apps の `groups-synced.ts` | Identity Center のグループ `Engineers`。Okta にも cdk-apps にも定義が無い（2022 年の古い同期の残り） |
| 原本バケットのバケットポリシーでの扱い（今） | 例外（バージョンを指定した削除・バケットの設定の変更ができる） | 例外（同じ） |
| 原本バケットのバケットポリシーでの扱い（導入後） | 例外から外す | 例外として残す（承認する人） |

AWSAdministratorAccess には、td1-raw と tuscenes-raw の削除の Deny がありません。そのため今は、この 2 本の最新ではないバージョンを消したり、削除マーカーを消して戻したりできるのは、AWSAdministratorAccess だけです。

## 2. AWSAdministratorAccess を持つ人

| 人 | 経路 | 備考 |
|---|---|---|
| 山本 修平（CorpIT） | グループ `Engineers`（メンバーは 1 名） | 2026-10-30 と 11-02 に、この権限セットで tuscenes-prod にサインインしている（CloudTrail） |
| （ほかに 1〜2 名の見込み） | — | 確かめている |

- グループ `Engineers` は、tuscenes-prod のほか、e2e-dev・brain-research・canberra・amman-pipeline・gaggle-management の計 6 アカウントに AWSAdministratorAccess を付けています（identity の `docs/aws-manual-groups.md`、2026-08-04 時点）。
- 管理アカウントなど 4 アカウントの AWSAdministratorAccess は、別のグループ `AWSControlTowerAdmins` が持っています。tuscenes-prod には付いていません（同じ資料）。

## 3. FullAccess を持つ人

| 人 | 経路（Okta のグループ） |
|---|---|
| 神尾 皓 | 自動運転第 3 グループ 正社員 |
| 藤井 一喜 | 自動運転第 3 グループ 正社員 |
| 山口 祐 | 自動運転第 3 グループ 正社員 |
| 渡辺 晃平 | 自動運転第 3 グループ 正社員 |
| 深澤 開 | 自動運転第 3 グループ 正社員 |
| 大戸 一希 | 自動運転第 3 グループ 正社員、自動運転第 4 グループ 正社員 |
| 伊藤 祐策 | 自動運転第 4 グループ 正社員 |
| 岩政 公平 | 自動運転第 4 グループ 正社員 |
| 犬塚 眞太郎 | 自動運転第 4 グループ 正社員 |
| 安本 雅啓 | 自動運転第 4 グループ 正社員 |
| 渡邉 孝文 | 自動運転第 4 グループ 正社員 |
| 塚本 周平 | 自動運転第 4 グループ 正社員 |
| 加藤 祐二 | 自動運転第 4 グループ 正社員 |
| 寺西 裕紀 | 自動運転第 4 グループ 正社員 |

- Okta のグループの正式名は `ORG:Autonomous Driving Group 3 Regular Employees` と `ORG:Autonomous Driving Group 4 Regular Employees` です。
- 組織の異動でグループのメンバーが変わると、FullAccess を持つ人も自動で変わります。この一覧は 2026-11-05 時点のものです。

## 4. 調べ方と、分かっていないこと

| 調べたこと | 方法 |
|---|---|
| どのグループに、どの権限セットが付いているか | cdk-apps の `apps/organization-policy/lib/groups-synced.ts`（`main`）。`Engineers` は identity の `docs/aws-manual-groups.md` |
| グループのメンバー | Identity Store を tuscenes-prod の ReadOnly で読んだ（`identitystore list-group-memberships`・`describe-user`） |
| 実際に使っているか | tuscenes-prod の CloudTrail（AWSAdministratorAccess のみ。直近の記録） |

**分かっていないこと:**

- **グループを通さない割り当て**（Identity Center の管理画面で、ユーザーに直接付けたもの）。割り当ての一覧（`sso-admin list-account-assignments`）は、管理アカウントの権限が無いと読めません。AWSAdministratorAccess の「ほかに 1〜2 名」は、これで確かめます。
- tuscenes-prod の FullAccess では確かめられません。割り当ては、管理アカウント（210332786925）にある Identity Center のインスタンスが持っています。FullAccess が効くのは tuscenes-prod の中だけなので、拒まれます（2026-11-05 に試した）。
- 確かめる方法は 2 つです。
  - 管理アカウントを読める人に、スクリプトを実行してもらう。割り当てを漏れなく確かめられます。スクリプトは personal-workspace の `projects/aws-data-protection/workstream/s3-data-protection-2/iam-scan/sso-assignments.sh` です（読み取りだけ）。
  - tuscenes-prod の CloudTrail で、AWSAdministratorAccess へのサインイン（`AssumeRoleWithSAML`）を全件めくる。期間中に実際に使った人だけが分かります。

## 5. 関連する資料

- 原本バケットの WORM 化: ガバナンスモードでの導入（3.2 誰が何をできるか、7 章 チームで決めてほしいこと）
- S3 Object Lock（WORM）の仕組み
