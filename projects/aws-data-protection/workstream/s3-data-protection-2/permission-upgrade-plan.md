# 原本バケットを守る権限設計のアップグレードプラン

2026-10-20 / tuscenes-prod（767397804933）の原本バケット 12 本

## この資料について

走行データの原本バケット 12 本には、2026-10-20 までにバージョニングを入れました。これで、ふつうの削除や上書きは古い版から戻せます。

ただし、**古い版ごと消す**操作や、**守りそのものを外す**操作（バージョニングの停止、ライフサイクルの書き換え、バケットポリシーの削除、バケットの削除）は、今も多くの主体ができます。この資料では、権限の現状と目指す形を並べ、どの順で近づけるかを示します。

次の 3 点について、賛否をお願いします。

1. **目指す形**（下の「目指す形」の 4 原則）
2. **進め方の順序**（「ステージ」の表。とくにステージ 1 で全 12 本にバケットポリシーの Deny を入れること）
3. **ステージ 1 のバケットポリシーの方針**（「ステージ 1 の設計」。例外を break-glass と CDK の deploy だけにすること）

## 前提: これまでにやったこと

- 12 本すべてでバージョニングを有効にした（[cdk-apps#2211](https://github.com/turingmotors/cdk-apps/pull/2211)・[cdk-apps#2215](https://github.com/turingmotors/cdk-apps/pull/2215)・[cdk-apps#2216](https://github.com/turingmotors/cdk-apps/pull/2216)・[cdk-apps#2217](https://github.com/turingmotors/cdk-apps/pull/2217) と、手で作った 3 本は CLI）。古い版は失効させない。
- 「誰が何をできるか」を、IAM ポリシーシミュレーターで全主体（ロール 686・ユーザー 38）について洗い出した。

## 現状: 何が問題か

洗い出しの結果、12 本のどれかに書き込める主体は 66 ありました。そのうち、**戻せない形で壊せる主体が 37** あります。

| 分類 | できること | 主体の数 | 例 |
|---|---|---|---|
| A | 全 12 本で守りを外せる（バージョニングの停止・ライフサイクル・ポリシー・バケットの削除・古い版の削除） | 21 | SSO の AWSAdministratorAccess・FullAccess・TeamE2E、CDK の deploy、使われていない古いロール、`AmazonS3FullAccess` を持つ IAM ユーザー 4 本 |
| B | 一部のバケットで守りを外せる | 1 | アップロード用 PC の IAM ユーザー（td1-raw・td1-rlog・tuscenes-raw。バケットの削除まで） |
| C | 古い版ごと消せる | 5 | backend-api、モデルのビルド・変換のジョブ、denso-nx の抽出ジョブ（td1-raw） |
| D | ライフサイクルを書き換えられる | 10 | Databricks の Unity Catalog 用のロール |

このほかに、ふつうの削除や上書きだけができる主体が 29 あります。これらはバージョニングによって戻せるので、今回の対象から外します。

背景にある原因は、次の 4 つです。

- **CDK の `grantReadWrite` が、古い版の削除まで許す。** `grantReadWrite` は `s3:DeleteObject*` を付けるので、`s3:DeleteObjectVersion` も含まれます。C の 5 本はすべてこれが原因です。CDK のよくある書き方なので、ロールを 1 本ずつ直しても、次の PR でまた生まれます。
- **既存の Deny は部分的。** SSO の FullAccess と TeamE2E には、td1-raw と tuscenes-raw の削除を拒否する文があります。ただし、TeamE2E は古い版の削除を拒否していません。また、どちらもライフサイクルの書き換えやバケットの削除は拒否していません。ほかの 10 本には Deny がありません。
- **最大権限の持ち主が多い。** SSO で AdministratorAccess 相当を持つ人が多くいます（FullAccess だけで 14 名）。人以外にも、使われていない古いロールや長期のアクセスキーを持つ IAM ユーザーが、`AmazonS3FullAccess` を持っています。
- **root に MFA が無い。** tuscenes-prod の root はパスワードが有効で、MFA がありません。パスワードは作成時から使われた記録が無いものの、root のメールを受け取れる人なら再設定して入れます。root を制限する SCP があるかは、メンバーアカウントからは確かめられません。root はバケットポリシーでも止められない唯一の経路です（調査書の G11、critical）。アカウント全体の問題なので、root の認証情報を消す件は別の案件として進めています（CorpIT に依頼）。

アカウントの外からは壊せません。バケットポリシーは他アカウントへの読み取りの許可だけで、ACL は無効、アクセスポイントもありません。

## 目指す形

1. **最大権限を持つのは人間だけにし、人数を必要最小限に絞る。** 例外は、IaC の deploy の経路（CDK の cfn-exec-role）と、AWS が管理するロール（Control Tower・StackSets）だけ。deploy の経路は、main へのマージにレビューを必須にし、workflow からしか deploy しないことで守る。
2. **重要なバケットで古い版を消す権限は、最大権限を持つ人間（break-glass）だけに限る。** 守りを外す操作も同じ扱いにする。意図して大量に消すときは、昇格した人がライフサイクルの規則を書き、S3 に消させる。削除権限を持つ常設のロールは置かない。
3. **最大権限を持つ人は MFA を必須にし、できる限り強化する。** SSO は Okta 経由なので、MFA は Okta 側で強制する（フィッシングに強い要素）。root は認証情報そのものを無くす（別の案件）。
4. **普段は最大権限を使わず、必要なときに昇格する。** 昇格用の権限セットを分け、セッションを短くし、使ったら必ず通知する。承認フローは置かない（少人数の運用には重いため、検知で代える）。

## 現状と目標の対比

| 観点 | 現状 | 目標 | ステージ |
|---|---|---|---|
| 古い版の削除 | 27 主体（人・アプリ・CI・使われていないロール） | break-glass の人だけ | 1 |
| 守りを外す操作（バージョニングの停止・ライフサイクル・ポリシー・バケットの削除） | 32 主体 | break-glass の人と、CDK の deploy（設定の書き込みだけ） | 1 |
| 意図した大量削除 | 常設のロール（LidarDeleter・S3BatchDeleteLidar）が `DeleteObject` で消す | 昇格した人がライフサイクルの規則を書き、S3 が消す | 1 |
| 削除の記録 | 無い（データイベントもアクセスログも無効） | 12 本の削除系のデータイベントを記録し、1 時間ごとに Slack に報告する（即時のアラートは後で考える） | 2 |
| root | パスワード有効・MFA 無し（アクセスキーは無い）。制限する SCP の有無は未確認 | 組織で root を一元管理し、認証情報を消す。root の使用は通知する | 別の案件 |
| 最大権限を持つ人 | FullAccess 14 名ほか（AdministratorAccess 相当） | 必要最小限の少人数 | 3 |
| 最大権限の使い方 | 普段から使う | 普段は通常の権限、必要なときだけ昇格する（短いセッション＋通知） | 3 |
| MFA | Okta のポリシーに依存（強さは未確認） | 昇格用のアプリはフィッシングに強い要素を必須にする | 3 |
| アプリの権限 | `grantReadWrite` でバケット全体に古い版の削除を許す | 必要なプレフィックスへの書き込みだけ。古い版の削除はバケットポリシーで常に拒否 | 4 |
| 機械の長期キー | IAM ユーザー 7 本（`AmazonS3FullAccess` 4 本、アップロード用 PC は今日も使用） | 使われていないものは消す。残すものは最小の権限か、一時的な認証情報に置き換える | 4 |
| 使われていない強いロール | 1 年以上使われていない `AmazonS3FullAccess`・AdministratorAccess のロールが 7 本 | 持ち主と予定を確かめて消す | 4 |

## ステージ

| ステージ | やること | 効果 | 手間 | 影響を受ける人 |
|---|---|---|---|---|
| **1** | 12 本にバケットポリシーの Deny を入れる（古い版の削除と守りを外す操作。例外は break-glass と CDK の deploy） | 大。A〜D の 37 主体の大半がまとめて止まる | 中（設計・テスト・CDK） | 古い版を消している人・アプリ（今は無いはず） |
| **2** | 削除のデータイベントを記録し、1 時間ごとに報告する | 中（壊されたら 1 時間ほどで気づける） | 小（費用の見積もりと通知の設定） | なし |
| **3** | 最大権限の持ち主を必要最小限に絞り、昇格用の権限セットと通知を作る。Okta で MFA を強化する | 中 | 中（権限セットの再設計と、チームへの周知） | FullAccess を使っている全員 |
| **4** | 主体の掃除（`grantReadWrite` の見直し、使われていない IAM ユーザー・ロール・長期キー、LidarDeleter） | 小〜中（ステージ 1 の後は多重の守り） | 中（持ち主の確認が要る） | 各アプリの持ち主 |

ステージ 1 が入れば、残りのステージは急ぎません。ステージ 2 はステージ 1 と並行して進められます。ステージ 1 で止められない root は、別の案件で認証情報を消します。

## ステージ 1 の設計（方針）

12 本それぞれのバケットポリシーに、次の 2 文を足します。

| 文 | 拒否する操作 | 拒否しない主体 |
|---|---|---|
| 1. 消す操作 | `s3:DeleteObjectVersion`、`s3:DeleteBucket`、`s3:PutBucketObjectLockConfiguration` | break-glass の権限セットだけ（当面は暫定の例外。下の注） |
| 2. 守りを外す操作 | `s3:PutBucketVersioning`、`s3:PutLifecycleConfiguration`（ライフサイクルの削除も含む）、`s3:PutBucketPolicy`、`s3:DeleteBucketPolicy`、`s3:PutBucketOwnershipControls`、`s3:PutBucketAcl` | break-glass の権限セット（当面は暫定の例外）と、CDK の cfn-exec-role（12 本とも） |

- **当面の例外（2026-10-21 に決定）**: break-glass の権限セットと名簿を待たずに入れるため、例外は暫定で SSO の FullAccess と AWSAdministratorAccess にします。break-glass の権限セットができたら、例外を差し替えます。
- 例外は `aws:PrincipalArn` で指定します（SSO のロールは名前に乱数が付くので、ワイルドカードで指定）。
- ふつうの削除（`s3:DeleteObject`）と上書き（`s3:PutObject`）は止めません。バージョニングで戻せるうえ、止めるとアプリが動かなくなるためです。
- ライフサイクルによる削除は S3 自身が行うので、この Deny に掛かりません。意図して消すときは、break-glass の人が規則を書きます。
- 12 本とも cdk-apps で書きます。CDK 管理の 9 本（tuscenes-model は `cdk import` で取り込み済み）は、手で書くと次の deploy で上書きされるためです。手で作った 3 本（td1-rlog・tuscenes-calibration（旧）・denso-raw）も、datalake の `CfnBucketPolicy` として書きます（バケット自体は CDK の管理外のまま）。例外の主体を 1 か所で変えられるようにするためです（2026-10-22 に決定。当初は CLI で書く予定でした）。
- **締め出しに注意します。** ポリシーの変更を拒否するので、break-glass の指定を誤ると、ポリシーを直せるのは root だけになります。そのため、先に使い捨てのテスト用のバケットで試し、IAM Access Analyzer で構文を検証してから入れます（2026-10-21 に済み）。今後の検証（例外の差し替えなど）には、常設のカナリア（原本バケットと同じ条件の検証用のバケット）を使います。root の一元管理（別の案件）が入れば、管理アカウントから `S3UnlockBucketPolicy` でポリシーを消して戻すこともできます。
- **Databricks で試すこと**があります。Unity Catalog 用のロールは、標準のポリシーでライフサイクルの権限を持っています。拒否したときに Unity Catalog が壊れないかを、1 本で確かめます（2026-10-23 に denso-raw で確かめ、入れた後も書き込みと削除ができました）。

## 決めてほしいこと

1. 目指す形の 4 原則に、賛成か反対か。
2. ステージの順序（ステージ 1＝バケットポリシー、ステージ 2＝削除の検知を並行）に、賛成か反対か。
3. ステージ 1 で、ふつうの削除と上書きは止めず、例外を break-glass と CDK の deploy だけにすることに、賛成か反対か。
4. break-glass の人を誰にするか（必要最小限の人数で）。

## 2026-10-21 追記: いただいた質問への回答

### 「12 本」はどれか（ステージの節）

tuscenes-prod（767397804933）の次の 12 本です。どれもバージョニングを入れ終えています。

| 種別 | バケット | 管理元 |
|---|---|---|
| 自社収集 | td1-raw、tuscenes-raw、gaming-data-collection、tuscenes-calibration（新） | CDK |
| 自社収集 | td1-rlog、tuscenes-calibration（旧） | 手で作成 |
| 他社から受領 | denso-taxi-video、denso-taxi-processed、denso-nx-raw | CDK |
| 他社から受領 | denso-raw | 手で作成 |
| AI モデル | tuscenes-model | CDK |
| 外注の成果物 | tuscenes-annotation | CDK |

tuscenes-basicai-datasets（中身と経緯が分からないため）と denso-nx-sample（チームでバージョニングを見送ったため）は含めていません。

### 削除の記録は CloudTrail か。意図して大量に消すと費用が膨らまないか（ステージの節）

CloudTrail のデータイベントを使う想定です。料金は 10 万件あたり $0.10 です。

- **ライフサイクルで消せば、費用はかかりません。** ライフサイクルによる失効は S3 自身が行い、CloudTrail のデータイベントには記録されません。目指す形の原則 2 で、意図した大量削除（LiDAR の削除など）はライフサイクルで行うことにしています。
- **API で 1 件ずつ消した場合の目安**: 2026-08〜09 の LiDAR の間引きでは、tuscenes-raw のオブジェクトが 8.3 億件から 2.1 億件に減りました。約 6.2 億件の削除をすべて記録すると、約 $620 です。
- **ふだんの費用**: 記録するのは削除系の操作に絞ります。上書き（`PutObject`）は古い版から戻せるので記録しません。12 本はふだんほとんど削除が無いので、小さい見込みです。件数を見積もってから決めます。（2026-10-22 に決定: 記録は 12 本の `DeleteObject`・`DeleteObjects` だけにし、1 時間ごとに報告します。データイベントの費用は月 $1 未満の見込みです）
- **別案**: S3 の削除通知を EventBridge に流す方法もあります。ほぼ無料ですが、誰が消したかは分かりません。

### 最大権限の持ち主を絞り、昇格用の権限セットと通知を作る（ステージ 3）の詳細

今は `FullAccess`（中身は AdministratorAccess、セッション 12 時間、14 名）を、普段の作業にそのまま使っています。これを 2 つに分けます。

| | 普段用 | 昇格用（break-glass） |
|---|---|---|
| 権限 | 普段の作業に足りるもの。原本の古い版の削除や、守りを外す操作はできない | AdministratorAccess。ステージ 1 のバケットポリシーの例外になる |
| 持つ人 | 今 FullAccess を使っている人 | 必要最小限の数名（決めてほしいことの 4） |
| セッション | 今と同じ | 1 時間程度 |
| MFA | 今と同じ | Okta でフィッシングに強い要素を必須にする |
| 使ったとき | — | Slack に通知する |

進め方は次のとおりです。

1. **棚卸し**: FullAccess の 14 名と、Control Tower の AWSAdministratorAccess の持ち主が直近 90 日に何をしたかを、CloudTrail で見る。普段用に要る権限を決める。
2. **普段用の権限セットを作り、割り当てを移す**: 移す前にチームに周知する。
3. **FullAccess を外す**: 昇格用を持つ人だけを残す。
4. **通知**: 昇格用のロールでログインしたことを、CloudTrail の管理イベント（無料）から EventBridge 経由で Slack に送る。
5. **Okta**: AWS のアプリの認証ポリシーで、break-glass のグループの人にフィッシングに強い要素を必須にする（identity の担当と相談）。

承認フローは置きません。少人数の運用には重いため、通知で代えます。

### break-glass の権限セットはどれか（ステージ 1 の設計）

**まだありません。新しく作ります。**

- 作る場所は cdk-apps の `apps/organization-policy` です（今の FullAccess などと同じ）。
- 名前は仮に `BreakGlass`、中身は AdministratorAccess、セッションは 1 時間程度にします。
- バケットポリシーの例外は、`AWSReservedSSO_BreakGlass_*` というロール名で指定します。
- 誰に割り当てるかは、決めてほしいことの 4 です。

上の節の「昇格用」と同じものです。ステージ 1 で先に作り、普段用との切り分けはステージ 3 で進めます。

### Unity Catalog 用のロールに、なぜライフサイクルの権限があるのか（ステージ 1 の設計）

Databricks が理由を説明した資料は見つかりませんでした。分かったことは次のとおりです。

- **出所**: 該当の 10 本は、Databricks の「S3 からデータを取り込む」設定画面が作る CloudFormation の雛形（スタック `databricks-s3-ingest-*`。tuscenes-prod には 2024-08 から 31 個）で作られています。雛形のポリシーに `s3:GetLifecycleConfiguration` と `s3:PutLifecycleConfiguration` がありますが、理由のコメントはありません。
- **今の公式ドキュメント**: 手で設定する手順のポリシーにも、自動で設定する手順の説明にも、ライフサイクルの権限は出てきません。追加で載っているのは、ファイルの到着を検知する機能（file events）のための通知の権限だけです。今の自動設定は CloudFormation ではなく、IAM の一時的な委任を使っています。
- **使われた記録**: 直近 90 日の CloudTrail で、12 本のライフサイクルを変えたのは CDK の deploy の経路だけでした。Databricks のロールからの変更はありません。

古い雛形にだけ残っている権限で、使われていない可能性が高いと考えています。ただ裏付けは無いので、予定どおり 1 本で拒否して Unity Catalog が動くかを確かめます。必要なら Databricks のサポートにも理由を聞きます。

出典:

- [CloudTrail pricing](https://aws.amazon.com/cloudtrail/pricing/)
- [Logging options for Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/logging-with-S3.html)（ライフサイクルの失効は CloudTrail に記録されない）
- [Databricks: S3 の external location を手で設定する](https://docs.databricks.com/aws/en/connect/unity-catalog/cloud-storage/s3/s3-external-location-manual)
- [Databricks: S3 の external location を自動で設定する](https://docs.databricks.com/aws/en/connect/unity-catalog/cloud-storage/s3/s3-external-location-cfn)
