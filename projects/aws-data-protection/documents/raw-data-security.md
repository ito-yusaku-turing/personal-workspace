# 走行データ消失リスク調査（2026-10）

Created by: Masahiro Yasumoto
Created time: 2026年10月15日 10:05
Last edited by: ItoYusaku
Last updated time: 2026年10月15日 16:47
Date: 2026年10月15日
Tags: aws
ステータス: 未着手
担当者: Masahiro Yasumoto
📌: No

<aside>
🚨

**結論: 走行データが消えるリスクは、今ある。** 原本（一次データ）約 3,667 TB のうち 99.5% に版管理・Object Lock・レプリケーション・バックアップのいずれも無く、消えたら戻らない。「1 操作で復旧不能に消せる」経路が 12 本あり、オブジェクトの削除は記録も検知もされない。

止血は「原本バケットの版管理＋SCP」「静的キーの無効化」「CI の権限分離」「削除系の検知」の 4 本柱（7 章）。いずれも 1 週間以内に着手できる。

</aside>

**この文書について**

- 調査期間: 2026-10-09〜10。対象は AWS 10 アカウント（tuscenes-prod を中心に e2e-dev、amman-pipeline、biz-dev、management など）、Databricks、GitHub の IaC リポジトリ、車両・アップロード PC の設定。
- 方法: 8 観点の並列調査で所見 106 件を集め、根本原因ごとに 31 項目に統合。各項目を「再現」「反証」「重大度の再評価」の 3 つの独立した検証にかけ、前工程の主張 25 点を修正した（8 章・10 章）。
- すべて読み取り専用で、設定は何も変更していない。
- 詳細レポート（約 115 KB、証拠ファイル・再現コマンド付き）は安本の端末の ~/work/data-deletion-risk にある。必要な人には共有する。

## 1. 結論

- 原本約 3,667 TB のうち、版管理・Object Lock・レプリケーション・AWS Backup のいずれも無いものが約 3,650 TB（99.5%）。消えたら戻らない（G01）。
- 「1 操作で復旧不能に消せる」経路は 12 本（3 章）。主体は AWS SSO 37 名、Coder 利用者（約 11 名。設定次第で実質全従業員に広がり得るが未確認）、Databricks の all-employees 71 主体（td1-rlog のみ）と e2e-team 21 名（denso-raw）、GitHub の push 権限者 55 名（mono-e2e）・54 名（cdk-apps）、root メールの受信者 9 名、management の管理者 7 名、静的アクセスキー 30 本超（うち 1 本は社外 SaaS が保持、4 本は所在不明）。
- SSO 権限セットの Deny は td1-raw と tuscenes-raw の DeleteObject だけで、Expiration 1 日のライフサイクル投入・PutObject の上書き・IAM ロール作成・CloudFormation・Databricks の IAM ロール・root で迂回できる。SCP に走行データの保護は無い。
- 削除は記録されない（S3 データイベント無し）。検知もされない（GuardDuty 0、Security Hub 未加入、Config ルール 0、S3 アラーム 0、Control Tower 通知の購読 0）。気づくのは人が Slack の日次コスト投稿を見るか、ジョブが落ちたとき。
- 別クラウドの写しは学習用の劣化変換動画 344 TB だけ（原本の 9%、復元には不十分）。例外は denso-nx-raw 171 TB で、送信元の Azure に原本が残る。
- 一方で、IaC の削除設定（Retain）、backend-api の本番 Lambda に raw の削除権限が無いこと、Databricks に UC を迂回する instance profile が無いこと、90 日の CloudTrail に削除事故の痕跡が無いことは確認できた（6 章）。

## 2. 走行データの在庫

CloudWatch の容量（2026-10-08 時点、全ストレージクラス合算、十進 TB）。

### 2.1 一次データ（原本。再収集できないもの）

| バケット | アカウント | TB | 種類 | 写し | 版管理 |
| --- | --- | --- | --- | --- | --- |
| td1-raw-767397804933 | tuscenes-prod | 1,737.9 | 動画 HEVC＋rlog（collect / control / core / journal） | 無し。collect 由来の動画のみ劣化派生が GCS にある | 無し |
| tuscenes-raw-767397804933 | tuscenes-prod | 913.7 | 動画＋rlog（v1.0〜2.2、収集は 2025-04 で終了） | 無し。劣化派生のみ GCS | 無し |
| denso-taxi-video-767397804933 | tuscenes-prod | 452.0 | タクシー動画 | 無し。Azure 側の取り込み元は 1〜30 日で削除済み | 無し |
| amman-nbox-log-tmp | amman-pipeline | 178.4 | N-BOX の Garmin 前方 MP4（2023-01〜2024-01） | 無し | 無し |
| denso-nx-raw-767397804933 | tuscenes-prod | 170.9 | mcap | Azure に原本 175.5 TB が残る（DataSync 再実行で復旧可） | 無し |
| databricks-workspace-e2e-bucket | tuscenes-prod | 115.6 | Unity Catalog 管理テーブルの実体（camera_frames、raw_rlog、scenes、curation など 2,880 表） | 無し | 無し |
| td1-raw-471112873671 | e2e-dev | 27.3 | 開発車両・机上検証機の固有データ（prod の写しではない） | 無し | 無し |
| td1-rlog | tuscenes-prod | 21.1 | 2024-10〜2025-04 の走行一式（凍結アーカイブ） | 無し。この期間の派生テーブルも無い | 無し |
| denso-raw-767397804933 | tuscenes-prod | 15.2 | DENSO 納品 raw（7z） | 無し | 無し |
| amman-comma3-log | amman-pipeline | 14.2 | comma3 の rlog＋動画 | 無し | 有り |
| tuscenes-annotation-767397804933 | tuscenes-prod | 13.5 | 人手ラベル | 無し | 無し |
| denso-nx-sample-767397804933 | tuscenes-prod | 5.7 | mcap サンプル | 無し | 無し |
| tuscenes-calibration（旧）／ tuscenes-calibration-767397804933 | tuscenes-prod | 1.3 | キャリブレーション | 無し | 旧は無し、新は有り |
| amman-nbox-log | amman-pipeline | 0.05 | 初期 N-BOX | 無し | 有り |
| **合計** |  | **3,666.9** |  | 独立した写しは実質 denso-nx-raw のみ | 版管理あり 14.3 TB（0.4%） |

本書で「一次バケット」と呼ぶのはこの 15 バケット（calibration の新旧を分ける）。版管理の有効化が要るのは版管理なしの 12 本。

### 2.2 二次データ・派生データ

- 二次（原本から再生成できる動画）約 651 TB: turing-video-training-sync-gcp 335 TB（H.264 変換動画、GCS に写し）、turing-video-ap-northeast-1 304 TB（閲覧用 DASH。commentary-audio だけは再生成不能）、ほか 12 TB。
- 派生（再生成可能）約 1,653 TB: garuda-dataset 463 TB、derived-data（2 アカウント）603 TB、turing-video-lake 322 TB（YouTube 由来の収集動画）、ほか。
- 全体 約 5,971 TB。GCP は転送先の GCS 1 バケットのみ（未認証のため実体は未確認）。オンプレの gc1 / gmo2 は学習用の部分コピーだけで、復旧元にならない。

## 3. 1 操作で復旧不能に消える経路

検証で確認できた経路だけを載せる（成立しなかった仮説は 8 章）。「戻せるか」は現状の設定での復旧可能性。TB は対象バケットの合計。

| # | 主体（人数） | 使うもの | 対象（TB） | 操作 | 検知／戻せるか | 所見 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SSO FullAccess 14 名＋AWSAdministratorAccess 2 名 | SSO セッション（12 時間） | Deny 対象外の原本 約 795（denso-taxi-video 452、denso-nx-raw 171、UC 実体 116、td1-rlog 21、denso-raw 15 ほか）。加えて二次の turing-video-ap-northeast-1 304 | `aws s3 rm --recursive` | 記録されない／不可 | G02 |
| 2 | 同上＋TeamE2E 23 名（計 37 名） | 同上 | td1-raw 1,738＋tuscenes-raw 914（Deny 対象） | Expiration 1 日のライフサイクル投入。1〜2 日後に全消去 | 管理イベント 1 行のみ、通知無し／投入から日次評価までの 1〜2 日だけ取り消せる | G02 |
| 3 | FullAccess 14＋Admin 2＋TeamDrivingSoftware 16＋TeamE2E 23（Deny 対象外のみ）＋Coder ロール・JADDViewer | 同上 | 版管理なしの全バケット 約 5,865 | `aws s3 sync` で空ファイルを上書き（PutObject は Deny されていない） | 記録されない／不可 | G02, G24 |
| 4 | Coder ワークスペース利用者（約 11 名。設定次第で全従業員、未確認）＋JADDViewer 3 名 | instance profile／SSO（AWS 管理ポリシー DataScientist、Deny 無し） | tuscenes-prod 全量 約 4,995 | `aws s3 rm --recursive`。Lambda の差し替えで S3 全権に昇格も可 | 記録されない／不可 | G03 |
| 5 | 現場キオスク PC の静的キー tokyo30-dataupload-pc-01（複数台で共有の可能性） | 平文の資格情報ファイル（自動ログイン・NOPASSWD の PC） | td1-raw、tuscenes-raw、td1-rlog、ohkami-navi-data（約 2,670） | `aws s3 rm` または Expiration 1 日 | 記録されない／不可 | G04 |
| 6 | 所在不明の静的キー 5 本（AmazonS3FullAccess の IAM ユーザー 4） | 静的キー（MFA・IP 条件無し） | tuscenes-prod 全量 約 4,995。1 ユーザーはアカウント管理者に昇格可 | `aws s3 rm`、ライフサイクル、DeleteBucket | 記録されない／不可 | G05 |
| 7 | Databricks の mlops-team 10 主体（人 9＋SP mono-e2e-ci） | UC 外部ロケーション（read only でなく、IAM ロールに DeleteObject） | td1-raw、tuscenes-raw、denso-nx-raw、td1-rlog、denso-raw（約 2,860） | `dbutils.fs.rm`／Files API | UC 監査に残るが通知無し。S3 側は記録されない／不可 | G06 |
| 8 | mono-e2e に push できる 55 名＋Devin 等の agent | PR 1 本で SP mono-e2e-ci の OIDC トークン（レビュー・マージ不要） | 7 と同じ＋UC 実体 116 | workflow を書いた PR を開く | GitHub の run ログに残る。通知無し／不可 | G07 |
| 9 | cdk-apps に push できる 54 名 | 任意ブランチ → CdkDeployRole → CloudFormation → cfn-exec-role（AdministratorAccess） | td1-raw、tuscenes-raw、denso-taxi-video、denso-nx-raw（約 3,275） | ライフサイクルに Expiration を混ぜた deploy（前例 PR #1440） | CloudTrail には cfn-exec-role 名義。通知無し／1〜2 日の窓のみ | G08 |
| 10 | Google グループ aws@ の 9 名、または 9 名の Google アカウントを奪った外部者 | root パスワードの再設定（メールのみ。MFA 無し、root 制限 SCP 無し） | tuscenes-prod 全量 約 4,995 | root でライフサイクル／削除／CloseAccount | 組織の CloudTrail に残るが通知無し／不可 | G11 |
| 11 | management の静的キー kento-t（社外 SaaS が保持）と management 管理者 7 名 | AssumeRole AWSControlTowerExecution（全メンバー Admin、SCP の除外対象） | 全アカウント全量 約 5,971 | 同上＋全アカウント閉鎖 | 通知無し／不可（CloseAccount だけは 90 日以内なら可） | G12, G13 |
| 12 | Databricks の all-employees 71 主体／e2e-team 21 名 | UC 外部ボリューム `e2e.sandbox.td1`、denso.default.raw（クラスタ不要） | td1-rlog 21、denso-raw 15 | Catalog Explorer／Files API／サーバーレス SQL の REMOVE | UC 監査に残るが通知無し／不可 | G31 |

補足の経路（規模が小さい、条件付き、または派生データ）:

- amman-pipeline: 休眠の静的キー 23 本と SSO FullAccess 31 名が amman-nbox-log-tmp 178 TB を消せる（G17）。
- TeamE2E の条件付き昇格（未実証）: TeamE2E は ssm:SendCommand が allowed で、起動中の Coder ワークスペース（DataScientist 付きの instance profile）があれば、その権限で td1-raw / tuscenes-raw を Deny 抜きで消せる経路が理論上残る。検証時点は全台停止（G02, G03）。
- LidarDeleter ロール: FullAccess 14 名が条件なしで assume でき、td1-raw / tuscenes-raw の lidar プレフィックス（残り約 5 億オブジェクト）を Deny の外で消せる（G22）。
- td-uploader: rlog の sync 失敗を検査せず SSD を消すため、1 走行分の rlog が消え得る。翌朝に検知はされる（G18）。
- クロスアカウント: tuscenes-prod の削除権限保持者が derived-data-994354357515 336 TB（派生）を消せる（G25）。

## 4. 所見の一覧（31 項目）

所見 106 件を根本原因ごとに統合した 31 項目。重大度は検証後の値（変更したものは括弧内に元の値）。critical と high の詳細は 5 章。

| ID | 重大度 | 所見 | 推奨の要点 |
| --- | --- | --- | --- |
| G01 | critical | 原本バケット（版管理なし 12 本）に版管理・Object Lock・レプリケーション・AWS Backup が無い。全経路を復旧不能にしている土台 | 版管理＋SCP（7 章 柱 1）。別アカウントへのレプリケーション |
| G02 | critical | SSO FullAccess 14・TeamE2E 23・Admin 2 の計 37 名が 1 セッションで消せる。Deny は 2 バケットの DeleteObject だけで、ライフサイクル・上書き・IAM 作成で迂回できる | 権限セットの Deny を全一次バケット × 削除系 API に拡張し、同内容を SCP に |
| G03 | critical | AWS 管理ポリシー DataScientist（全バケットに DeleteObject）が Coder の全ワークスペースと SSO JADDViewer に付与 | DataScientist を外し、ReadOnly＋明示した書き込み先だけの自前ポリシーに |
| G04 | critical | 現場アップロード PC の静的キー tokyo30-dataupload-pc-01 が raw 4 バケットの削除・ライフサイクル・版管理変更を持つ | バケットポリシーで Deny → ポリシーを PutObject 系だけに縮小 → 鍵をローテーション |
| G05 | critical（high から引き上げ） | AmazonS3FullAccess の静的キーが 4 ユーザーに残り、3 本は 1 年近く未使用。1 ユーザーはアカウント管理者に昇格できる | 即日 Inactive、2 週間後に削除 |
| G06 | critical | Databricks UC の外部ロケーションの IAM ロールが一次バケットに DeleteObject を持ち、mlops-team が ALL PRIVILEGES | 外部ロケーションを READ ONLY、IAM ロールから Delete / Put を外す、ALL PRIVILEGES を READ FILES に |
| G07 | critical | mono-e2e の PR だけで SP mono-e2e-ci（Databricks 管理者相当）のトークンが取れ、push 権限者 55 名がレビュー無しで raw まで消せる | SP を admins から外す、PR 用に plan 専用 SP、federation policy を main に限定、承認 1 以上 |
| G08 | critical | cdk-apps の任意ブランチ／PR から本番 AdministratorAccess で deploy でき、ライフサイクルに Expiration を混ぜれば raw が翌日消える | PR #2024 をマージし job_workflow_ref 条件を追加、deploy workflow を main 限定、cfn-exec-role に Deny |
| G11 | critical | メンバーアカウントの root に MFA 無し、root 制限 SCP 無し。root メール配送先の Google グループ（9 名）を押さえれば丸ごと消せる | Control Tower の root 制限を Product / misc OU に有効化、集中 root 管理、aws@ の参加制限、代替連絡先 |
| G12 | critical | management の IAM ユーザー kento-t（AdministratorAccess）の静的キーを社外 SaaS が保持。キー 1 本で全アカウント閉鎖・全メンバー Admin に届く | 最小権限の専用ユーザーに差し替えてから、キーを Inactive → 削除 |
| G31 | high（critical から引き下げ） | UC 外部ボリューム経由で all-employees 71 主体が td1-rlog 21 TB、e2e-team 21 名が denso-raw 15 TB をクラスタ無しで消せる | DROP VOLUME `e2e.sandbox.td1`、`grants.tf` から WRITE_VOLUME を外す、外部ロケーションを READ ONLY |
| G13 | high | management の管理者 7 名が 1 セッションで CloseAccount・全メンバー Admin が可能。SCP に走行データ保護と CloseAccount の Deny が無く、代替連絡先も未設定 | 組織独自の SCP、taro.test と残骸割当の削除、Admin をジャストインタイムに |
| G15 | high | 削除を記録する仕組み（S3 データイベント）も検知する仕組み（GuardDuty・Config・アラーム・通知購読）も無い | 一次バケット限定のデータイベント trail、EventBridge → Slack、容量減少アラーム、GuardDuty、Databricks 監査の SQL アラート |
| G16 | high | 別クラウドの写しは劣化変換動画 1 系統だけ。復旧手順書・演習が無い | 別アカウントへ Object Lock 付きレプリケーション、復旧手順書と演習 |
| G09 | high | UC 管理テーブルの実体 databricks-workspace-e2e-bucket（116 TB、版管理なし）は SSO 約 40 名が AWS 側から直接消せる。CFN スタックに保護無し | 版管理（非現行版 30〜60 日）、バケットポリシーで UC ロール以外の Delete を Deny、TerminationProtection |
| G10 | high | e2e.v2 / v2control の一次テーブルは DLT 生成物で、CAN_MANAGE 保持者（mlops-team＋admins 継承）がパイプライン削除やフルリフレッシュで落とせる。dropInactiveTables が本番で true | 個人の CAN_MANAGE を外す、dropInactiveTables を false、行数の前日比アラーム |
| G17 | high | amman-pipeline（178 TB）と biz-dev の一次データは IaC 外で、休眠の静的キー 23 本と SSO FullAccess 31 名が削除権限を持つ | 23 本を Inactive → 削除、版管理と削除 Deny、stale な SSO 割当 7 件を削除 |
| G18 | medium（high から引き下げ） | td-uploader が rlog の sync 失敗を検査せず車両 SSD を消す。発生実績 0、翌朝に検知される | rm の前提に 2 回の sync 成功と件数突合、未マージ PR #33 / #13 の取り込み |
| G19 | medium | e2e-dev に MFA 無しの Admin IAM ユーザーと S3FullAccess の静的キーが残る。共通 IoT 証明書のロールが td1-raw-471112873671 に上書きできる | 2 ユーザーを削除、バケットポリシーを IaC 化して prefix 限定、版管理 |
| G20 | medium | backend-api の garuda purge に所有者チェックが無く、service key でも任意データセットの S3 実体を消せる（再ビルドは可能） | purge を作成者か admin に限定、service key は拒否 |
| G21 | medium | backend-api の認証なし DELETE 3 本は Supabase の行だけを消す（1 本は物理削除）。BFF 経由でも所有者チェック無し | 認証と作成者照合を追加、物理削除を論理削除に |
| G22 | medium | LiDAR 一括削除の常設ロール。S3 Batch Operations の経路は不成立だが、LidarDeleter が FullAccess 全員に開いている（削除は 8〜9 月に 6.4 億オブジェクト実行済み、中断中） | 不要ロールの削除。残作業の要否を決めて信頼先を限定 |
| G23 | medium | Databricks で e2e-team が denso カタログに MODIFY。所有者が個人・退職者・unknown のオブジェクトが多い | MODIFY を sandbox に絞る、所有者を mlops-team に統一 |
| G24 | medium | TeamDrivingSoftware 16 名の s3:PutObject（全リソース）は版管理なしでは上書き破壊と同義 | Resource を必要な bucket / prefix に限定、版管理 |
| G25 | medium | クロスアカウントのバケットポリシーで相手アカウントの root に DeleteObject を許す派生バケット（336 TB） | root 文をロール限定に |
| G26 | medium | CloudTrail ログバケットは 365 日で自動削除、Object Lock 無し。CloudWatch Logs は 14 日 | Object Lock 付きバケットへ移行、保持 2〜3 年 |
| G27 | low（medium から引き下げ） | Okta で退職済みの 4 名が Identity Center に残存（サインインは不可）。退職者の Coder ワークスペースも残存 | offboard 手順に identitystore と Coder の削除を追加 |
| G28 | low | Databricks シークレットスコープの静的キーと共有クラスタ常駐のキーは、派生・tmp にしか削除権限が無い | 旧キーの無効化、個人 MANAGE をグループへ |
| G29 | low | cdk-apps-denso に本番ロール ARN を持つ古い Datalake 定義が残る（現状は assume に失敗）。org 内の任意 repo から tuscenes-assets を消せるロールあり | アーカイブ、file-publishing-role の main 限定 |
| G30 | info | Permissions boundary がほぼ無い | SCP で boundary を必須に |

重大度の変更: G05 high → critical、G31 critical → high、G18 high → medium、G27 medium → low（Identity Center 部分）、G14（削除が記録されない）は G15 に統合。

## 5. 重要所見の詳細（critical と high）

各項目は「事実」「リスク」「検証で直した点」「推奨」の順。括弧内の G 番号は 4 章の ID。

### 5.1 critical

- **G01** 原本バケットに版管理・Object Lock・レプリケーション・AWS Backup が無い
    - **事実**: 主要 25 バケットのうち 21 で版管理が未設定、Object Lock・レプリケーションも無し。AWS Backup は 5 アカウント × 2 リージョンでプラン 0。バケットポリシーに削除系の Deny は 1 件も無い。版管理ありは tuscenes-dataset / map / model / calibration（新）/ amman-comma3-log / amman-nbox-log だけで、MFA Delete は無し。tuscenes-dataset のレプリケーション規則は Disabled で宛先バケットは存在しない。td1-rlog / denso-raw / td1-video-h265-gcp / maps は CloudFormation 外の手動バケット。
    - **リスク**: 他の全経路を復旧不能にしている土台。DeleteObject 1 回、Expiration 1 日のライフサイクル 1 回、上書き 1 回で戻らない。
    - **検証で直した点**: 3 レンズとも critical で確定。AWSAdministratorAccess の保持者は 1 名ではなく 2 名。「amman-nbox-log 161 TB」は誤りで本体は amman-nbox-log-tmp 178 TB。denso-nx-raw は Azure に原本が残る。新事実として、FullAccess の Deny は DeleteObject 系だけで、td1-raw への PutLifecycleConfiguration / PutBucketVersioning / PutObject は allowed。
    - **推奨**: 版管理（非現行版 90 日以上）＋SCP。rlog と再収集不能な動画から、別アカウントへ Object Lock 付きレプリケーション。手動バケットを cdk import。
- **G02** SSO の FullAccess・TeamE2E・AWSAdministratorAccess が 1 セッションで一次データを消せる
    - **事実**: FullAccess は AdministratorAccess にインライン Deny（td1-raw / tuscenes-raw の DeleteObject 系のみ）を付けたもの。TeamE2E は AmazonS3FullAccess 等に Deny（PutObject と DeleteObject。DeleteObjectVersion は含まない）。Admin は Deny 無し。tuscenes-prod の割り当ては FullAccess 14 名、TeamE2E 23 名、Admin 2 名、重複排除で 37 名。SCP は Control Tower のガードレールのみ、permissions boundary 無し。simulate では FullAccess は td1-raw への PutLifecycleConfiguration / DeleteBucket / PutBucketPolicy / PutBucketVersioning / PutObject、iam:CreateRole、cloudformation:CreateStack が allowed。端末 1 台の SSO キャッシュに refreshToken が平文で入り、4 アカウントに届く。
    - **リスク**: 誤操作でも内部不正でも端末盗難でも、1 セッションで原本全量に届く。
    - **検証で直した点**: 「DeleteBucket で迂回」は非空バケットでは不成立。「バケットポリシーで自分に Allow」は identity 側の明示 Deny を覆せず不成立。「TeamE2E も IAM / CloudFormation で迂回」は誤りで、TeamE2E の確実な迂回はライフサイクル 1 本。ライフサイクルは即時でなく 1〜2 日の取り消し窓がある。新事実: FullAccess は PutObject が allowed なので上書きは即時かつ Deny の外。TeamE2E の Deny は DeleteObjectVersion を含まないため、版管理を入れても揃えないと版ごと消せる。TeamE2E は ssm:SendCommand が allowed で、起動中の Coder ワークスペース経由の条件付き経路が未実証で残る。
    - **推奨**: 権限セットの Deny を DeleteObject 系・PutLifecycleConfiguration・PutBucketVersioning・DeleteBucket・PutBucketPolicy（書き込みが要る主体以外は PutObject も）に広げ、Resource を一次 15 バケットに拡張。同内容を Product OU の SCP に。SessionDuration を 4 時間以下に。Engineers 群の AWSAdministratorAccess を撤去。
- **G03** AWS 管理ポリシー DataScientist が Coder の全ワークスペースと SSO JADDViewer に付与
    - **事実**: DataScientist は s3:DeleteObject / PutObject / Get / List と Lambda の作成・更新・実行を全リソースに許可し、条件無し。付与先は Coder ワークスペース用ロール（EC2 16 台・約 11 名、当日も使用）、Pod Identity 2 ロール（休眠）、旧 CoderWorkspaceRole（休眠）、SSO JADDViewer（3 名）。5 ロールとも boundary 無し・Deny 無し。Coder のログインは Google OIDC のドメイン制限のみで、サインアップ設定は未確認。
    - **リスク**: ワークスペース内の任意プロセス（依存パッケージ、AI エージェントを含む）が SSO の Deny を経由せず原本を消せる。
    - **検証で直した点**: 3 レンズとも critical。DataScientist 単体では DeleteObjectVersion・ライフサイクル・DeleteBucket は無いので、版管理を入れればこの経路は復旧可能に落ちる。新事実: lambda:UpdateFunctionCode と InvokeFunction で AmazonS3FullAccess を持つ Lambda の実行ロールに乗り換え、S3 全権に昇格できる。退職者の Coder ワークスペースが停止状態で残存。
    - **推奨**: DataScientist を外し、ReadOnly＋明示した書き込み先（tuscenes-tmp 等）だけの自前ポリシーに。一次バケットのバケットポリシーで Coder ロールと JADDViewer からの Delete / Put を Deny（二重防御）。JADDViewer を cdk-apps 管理に。休眠ロール 3 本を削除。
- **G04** 現場アップロード PC の静的キー tokyo30-dataupload-pc-01 が raw 4 バケットの削除・ライフサイクル・版管理変更を持つ
    - **事実**: IAM ユーザー tokyo30-dataupload-pc-01 の Active キー 1 本（2024-05 作成、現在も稼働中、MFA 無し）。管理ポリシーは tuscenes-raw / td1-raw / td1-rlog / ohkami-navi-data（約 2,670 TB）に DeleteObject、DeleteObjectVersion、DeleteBucket、PutLifecycleConfiguration、PutBucketVersioning、PutBucketObjectLockConfiguration など約 100 アクションを条件無しで許可。実際に使うのは s3 sync / cp だけ。鍵は自動ログインと NOPASSWD のキオスク PC に平文で置かれ、IaC 外。複数台（data-uploader01〜06）で同一キーを共有している可能性が高い。
    - **リスク**: 物理アクセスか PC の侵害だけで原本 2,670 TB を復旧不能に消せる。
    - **検証で直した点**: 3 レンズとも critical。「S3 Batch Operations まで持つ」は過大（PassRole が無く、そもそも Batch Operations に削除操作は無い）。「DeleteBucket」は空バケットのときだけ。
    - **推奨**: 即日、4 バケットのバケットポリシーにこのユーザーからの Delete 系・PutLifecycleConfiguration・PutBucketVersioning・PutBucketObjectLockConfiguration の Deny を入れる（現場 PC を触らずに閉じられる）。次にポリシーを PutObject / AbortMultipartUpload / ListBucket（collect / control / core / journal 限定）だけに差し替え、鍵をローテーション。現行スクリプトは Delete 系 API を呼ばないので処理は止まらない。中期は IAM Roles Anywhere か IoT 資格情報プロバイダへ。
- **G05** AmazonS3FullAccess の静的キーが 4 ユーザーに残り、3 本は 1 年近く未使用（high から critical へ）
    - **事実**: jadd-datasync（最終使用 2025-10）、jadd-remote-sync-kohei.watanabe（2025-10）、shio-secretsmanager_GetSecretValue（2025-08）、jadd_studio_amplify（2 本、1 本は 2026-09 に使用）。全て MFA 無し・boundary 無し・IaC 外。simulate で td1-raw / tuscenes-raw の DeleteObject / DeleteBucket / PutLifecycleConfiguration が allowed（SSO の Deny は IAM ユーザーに効かない）。jadd_studio_amplify は iam:CreateRole / AttachRolePolicy / sts:AssumeRole を全リソースに持ち、自分で Admin ロールを作って assume できる。tuscenes-prod の Active キー 42 本のうち 22 本が 90 日超未使用。
    - **リスク**: 所在不明のキーが漏えいしていても気づけず、全バケットを消せる。
    - **検証で直した点**: high から critical に引き上げ。G04 と同じ機構で対象が全バケットに広がり、1 ユーザーはアカウント全権に昇格できる。「未使用だから危険度が低い」は逆で、所在不明は漏えいに気づけないことを意味する。
    - **推奨**: 未使用 4 本を即日 Inactive、2 週間後に削除。jadd_studio_amplify は後継の読み取り専用ユーザーへの切替え先を特定して廃止。IAM ユーザー一元管理の棚卸しに 22 本を含める。
- **G06** Databricks UC の外部ロケーションの IAM ロールが一次バケットに DeleteObject を持ち、mlops-team が ALL PRIVILEGES
    - **事実**: 外部ロケーション 44 本のうち read only は 2 本だけ。一次バケット向け 8 本（td1-raw、td1-raw-471112873671、tuscenes-raw、td1-rlog、denso-raw、denso-nx-raw、amman-nbox-log と -tmp）は全て書き込み可で、IAM ロールは Get / Put / DeleteObject と Get / PutLifecycleConfiguration を持つ（Databricks quickstart の既定）。mlops-team（人 9＋SP mono-e2e-ci）が ALL PRIVILEGES またはメタストア所有者。全て ISOLATION_MODE_OPEN。直近 1 年、一次バケットへの書き込み資格情報の払い出しは 0 件（読むだけの用途）。
    - **リスク**: ノートブックの dbutils.fs.rm 1 回、または誤った overwrite で td1-raw 1,738 TB が消える。SSO の Deny は Databricks の IAM ロールに及ばない。
    - **検証で直した点**: critical を維持。「Databricks 側からロールを assume してライフサイクル変更」は不成立（信頼先は UC のマスターロールのみ、払い出される資格情報はパス単位）。DeleteBucket は不可。mlops-team 9 名中 7 名は既に SSO FullAccess で同じバケットを消せるので、この経路で新たに消せるのは 3 主体。IAM ロールに DeleteObjectVersion は無いので、版管理を入れればこの経路は復旧可能に落ちる。新事実: 一次バケット上に外部ボリュームがあり、一般ユーザーにも開いているものがある（G31）。
    - **推奨**: 一次バケット向け外部ロケーションを READ ONLY に（直近 1 年書き込み 0 件なので影響無し）。IAM ロールから Delete / Put / PutLifecycleConfiguration を外す。mlops-team の ALL PRIVILEGES を READ FILES に落とし、書き込みが要る SP だけ WRITE FILES。ISOLATED に固定。
- **G07** mono-e2e の PR だけで SP mono-e2e-ci のトークンが取れ、push 権限者 55 名がレビュー無しで raw まで消せる
    - **事実**: pull_request で github-oidc と CLIENT_ID=mono-e2e-ci を使う workflow が 5 本あり、PR ブランチからの run で prod への認証成功を確認（Devin の PR でも成功）。GitHub environment mono-e2e-ci に保護ルール無し。main ルールセットは承認 0・code owner 不要。push 権限 55 名。SP は Databricks の mlops-team と admins の両方に所属。別に、main push で起動する deploy ワークフロー 39 本も同じ SP を使う。
    - **リスク**: 本質は「既存 5 本」ではなく、push できる者が id-token の書き込み権限を持つ workflow を足せる点。PR 1 本で経路 7（raw 2,860 TB＋UC 実体 116 TB）に到達する。
    - **検証で直した点**: 3 レンズとも critical。影響を「DROP CATALOG（UNDROP 7 日で戻せる）」としたのは過小で、外部ロケーション経由の raw 削除は UNDROP の外。federation policy の本文はアカウント API が読めず未確認（run の成功で実質確定）。
    - **推奨**: mono-e2e-ci を admins から外し、PR 用に USE / SELECT だけの plan 専用 SP。federation policy の subject を main に限定。environment に required reviewers と branch policy。ルールセットを承認 1 以上にし、workflows と databricks-terraform を CODEOWNERS で固定。
- **G08** cdk-apps の任意ブランチ／PR から本番 AdministratorAccess で deploy でき、ライフサイクルに Expiration を混ぜれば raw が翌日消える
    - **事実**: GithubActions-CdkDeployRole（prod）の信頼条件は cdk-apps の全ブランチと pull_request。deploy-role 経由で cfn-exec-role（AdministratorAccess、boundary 無し）。CloudTrail 14 日で pull_request からの assume が 60 件。push 54 名。diff 系 workflow 30 本は PR 側の定義で同ロールを assume。本番 deploy workflow のうち main ガード無しの workflow_dispatch が 12 本。CloudFormation 147 スタック全てに TerminationProtection 無し。PutBucketLifecycle は 90 日で 15 件、全て cfn-exec-role 名義。前例として PR #1440 で tuscenes-video-training に Expiration 1 日のライフサイクルが入り、CloudFormation が適用した。
    - **リスク**: 54 名の誰か 1 人が自分のブランチに workflow を push するだけで、レビュー無しに Admin の CloudFormation を流せる。
    - **検証で直した点**: 3 レンズとも critical。「cfn-exec-role で aws s3 rm 等の任意操作」は不正確で、到達できるのはテンプレートで表現できる操作（ライフサイクル改変、Lambda カスタムリソース、IAM 作成）に限られる。結果は同じ。「15 本に branch 無制限」は 12 本。新事実: cdk-apps-diff-role は既に稼働中で、残るのはレビュー（PR #2024）だけ。
    - **推奨**: PR #2024 を最優先でマージし、management の ci-cdk-deploy-role と同じ job_workflow_ref 条件を付ける。本番 deploy workflow 12 本に main ガードか Environment。cfn-exec-role に一次バケットの削除系を Deny する boundary か SCP。CDK のユニットテストで一次バケットに Expiration が無いことを assert。一次データを持つスタックに TerminationProtection。
- **G11** メンバーアカウントの root に MFA 無し、root 制限 SCP 無し。root メール配送先の Google グループを押さえれば丸ごと消せる
    - **事実**: root の MFA は management 以外の全アカウントで未設定。Product OU（tuscenes-prod、e2e-dev など）と misc OU（biz-dev）の SCP に root 制限が無い（Research / Security / Web OU にはある）。集中 root 管理は未有効。root メールは aws+アカウント名@ で、配送先の Google グループ aws@ は MEMBER 9 名、参加申請可、誰でも投稿可。代替連絡先は未設定。root の操作は CloudTrail に残るが通知無し。
    - **リスク**: 受信箱 1 つで root パスワードを再設定し、SCP・バケットポリシー・SSO の Deny のどれにも止められず、CloseAccount まで到達する。社外のフィッシング経由にも開いている。
    - **検証で直した点**: 3 レンズとも critical。「全メンバーで root パスワードが有効」は 4 アカウントで未設定だったが、回復フローで設定できるので危険度は同じ。「CloudTrail 停止まで可能」は過大（ベースライン trail は SCP で守られる）。aws@ の 9 名のうち 7 名は既に SSO で同等の削除能力を持ち、root 経路で新たに得るのは 2 名。
    - **推奨**: Control Tower で Product / misc OU に root 制限コントロールを有効化（management から即時）。集中 root 管理を有効化してメンバー root の資格情報を削除。aws@ を招待制・メンバー最小化に。全アカウントに代替連絡先。
- **G12** management の IAM ユーザー kento-t（AdministratorAccess）の静的キーを社外 SaaS が保持
    - **事実**: management 唯一の IAM ユーザーに AdministratorAccess と Active キー（2025-05 作成、タグ freeeBundle）。90 日の CloudTrail 2,770 件は全て identitystore の List 系（毎日 04:05 JST、aws-sdk-ruby3、東京リージョンの EC2 3 IP）。最終使用 2026-09-30 で以後停止。simulate で organizations:CloseAccount / sts:AssumeRole / sso:CreateAccountAssignment / iam:CreateUser が allowed。各メンバーの AWSControlTowerExecution は management を無条件に信頼し、Control Tower のガードレール SCP は全てこのロールを除外している。management に EventBridge・アラーム・GuardDuty は無い。
    - **リスク**: SaaS 側の漏えいがそのまま全アカウントの Admin と 18 アカウントの閉鎖につながる。
    - **検証で直した点**: 3 レンズとも critical。SaaS は Josys ではなく Bundle by freee（キーのタグから）。日次利用は 10/1 で止まっており、今なら無効化の業務影響が小さい。
    - **推奨**: freee 連携を identitystore の読み取りのみ・送信元 IP 条件付きの専用ユーザー（または IAM Roles Anywhere）に差し替え、kento-t の AdministratorAccess を外して切替後にキーを Inactive → 削除。management の Organizations / IAM / sso の書き込み API に EventBridge → Slack の通知。

### 5.2 high

- **G31** UC 外部ボリューム経由で all-employees が td1-rlog を、e2e-team が denso-raw をクラスタ無しで消せる（critical から high へ）
    - **事実**: e2e.sandbox スキーマに all-employees（71 主体 = 人 59＋SP 12）の WRITE VOLUME / MODIFY が直接付与され、外部ボリューム td1（s3://td1-rlog/、所有者 unknown、Terraform 外）に継承。e2e-team 21 名は ALL PRIVILEGES。denso.default.raw は Terraform の grants で e2e-team に WRITE_VOLUME。Files API はクラスタ無しで応答する。180 日の監査で両ボリュームへの書き込み・削除は 0 件。
    - **リスク**: AWS 権限の無い社員や SP のトークン漏えいから、Catalog Explorer / Files API / サーバーレス SQL で復旧不能に消せる。主体の広さは全項目で最大。
    - **検証で直した点**: critical から high に。対象が td1-rlog 21 TB（2024-10〜2025-04 の凍結アーカイブ）と denso-raw 15 TB の計 36 TB で、主要原本 td1-raw / tuscenes-raw のボリュームは一般ユーザーには READ のみ。ただし td1-rlog の期間は派生テーブルも無く、消えたら唯一のデータ。
    - **推奨**: 即日 DROP VOLUME `e2e.sandbox.td1`（180 日利用 0 件）。残すなら所有者を mlops-team にして all-employees の WRITE VOLUME を REVOKE。`grants.tf` から e2e-team の WRITE_VOLUME / MODIFY を外す。外部ロケーションを READ ONLY。版管理。filesDelete の日次通知。
- **G13** management の管理者 7 名が 1 セッションで CloseAccount・全メンバー Admin が可能。SCP に走行データ保護が無い
    - **事実**: SCP 7 本に CloseAccount / LeaveOrganization / KMS / S3 削除系の Deny は 0。management の AWSAdministratorAccess は手動グループ AWSControlTowerAdmins（7 名）、ローカルユーザー taro.test、削除済みグループの残骸 2 件に付与。simulate で tuscenes-prod の AWSControlTowerExecution は tuscenes-raw の DeleteObject / PutLifecycleConfiguration / DeleteBucket が allowed。organization-policy の CODEOWNERS は 2 名、承認 1。代替連絡先は全アカウント未設定。
    - **リスク**: 組織レベルの防波堤が無く、G01・G02・G11 が成立する共通原因。
    - **検証で直した点**: high を維持。taro.test は Okta 外のローカルユーザーで単独ではサインインできない。「承認 1 名で単独実行」は自己承認不可のため最低 2 名（ただし承認後の push で承認が失効しない）。kento-t（G12）が主体一覧から漏れていた。
    - **推奨**: Product / misc OU に組織独自の SCP（一次バケットの削除系 API と CloseAccount / LeaveOrganization を break-glass 以外に Deny）。taro.test と残骸割当を削除。AWSControlTowerAdmins を IaC 管理に移し、management の Admin をジャストインタイムに。代替連絡先の設定。
- **G15** 削除を記録する仕組みも検知する仕組みも無い
    - **事実**: CloudTrail は 10 アカウント全てが Control Tower のベースライン trail のみで S3 データイベント無し、組織トレイル無し。サーバーアクセスログは 266 バケット全て無し。td1-raw は 2026-08-29 に約 1,040 万オブジェクト減っている（LiDAR 削除）が、記録はどこにも無い。GuardDuty は 10 アカウント × 17 リージョンで 0、Security Hub 未加入、Config ルール 0、S3 のアラーム 0、削除系の EventBridge ルール 0、Control Tower の通知トピックの購読 0、Databricks の SQL アラート 0。Expiration 1 日の全削除ライフサイクルが tuscenes-cleaned / img / video-training（いずれも空）と tuscenes-dataset の 8 prefix に常設。PutBucketLifecycle は 90 日で 27 件が無警報で通った。
    - **リスク**: 消えたことに気づけず、誰が消したかも追えない。復旧可能な類型（UNDROP 7 日、ライフサイクルの 1〜2 日の窓）が無検知のまま復旧不能に転化する。
    - **検証で直した点**: high（G14 を統合）。「誰が行っても記録されない」は AWS 側に限り、Databricks 経由の削除は system.access.audit に主体付きで残る。「翌月の請求減まで気づかない」は過大で、Slack の日次コスト投稿があり PB 級なら 2〜4 日で人の目に入る（自動ではない）。
    - **推奨**: 一次バケット限定の CloudTrail データイベント trail（WriteOnly）を新設して log-archive に集約。EventBridge で PutBucketLifecycle / DeleteBucket / PutBucketVersioning / DeleteBucketPolicy / PutBucketPolicy → Slack。原本の NumberOfObjects / BucketSizeBytes の減少アラーム。GuardDuty を組織で有効化。system.access.audit の削除系を Slack 通知する SQL アラート。空バケットの全削除ルールを撤去。
- **G16** 別クラウドの写しは劣化変換動画 1 系統だけ。復旧手順書・演習が無い
    - **事実**: GCS への転送は turing-video-training-sync-gcp（335 TB、620px / 10fps / 音声除去の派生）と biz-dev の web 動画の 2 本。原本 3,667 TB に対し写し 344 TB（9.4%、しかも劣化派生）。GCS 側は版管理無しで objectAdmin が 5 グループ＋サービスアカウント。tuscenes-dataset のレプリケーションは Disabled で宛先は 404。復旧手順・RPO / RTO・演習記録は無い。
    - **リスク**: 原本が消えた時に戻す先が無い。
    - **検証で直した点**: high を維持。「日次同期は 9/11 に停止」は正確には「変換バッチ完了時のオンデマンド起動に切替え」で、現時点の GCS 写しに欠落は無い。GCS のバケットは階層型のため Object Versioning が使えず、soft delete か別バケットが要る。Azure は denso-nx-raw の原本が残るが、taxi 系は削除済み。
    - **推奨**: rlog と再収集不能な動画から、SSO FullAccess を割り当てない専用アカウントへ Object Lock 付きレプリケーション。GCS は学習用配置と位置付け、バックアップに数えない。原本バケットごとに「再取得可否・RPO・写しの場所・復旧手順」をまとめ、半年ごとに復元演習。
- **G09** UC 管理テーブルの実体 databricks-workspace-e2e-bucket（116 TB、版管理なし）は AWS 側から直接消せる
    - **事実**: 7 カタログの managed 表 2,880 本の実体が 1 バケットに集中。版管理・Object Lock・ログ・通知いずれも無く、1 日数 TB 増加中。SSO FullAccess / TeamE2E / Admin（約 40 名）は simulate で DeleteObject / DeleteBucket / PutLifecycleConfiguration が allowed（Deny の対象外）。CloudFormation スタック databricks-workspace-e2e は TerminationProtection・DeletionPolicy 無し。
    - **リスク**: aws s3 rm 1 回で UNDROP も Time Travel も効かずに全テーブルが消える。
    - **検証で直した点**: high（3 レンズとも一部成立）。前工程の主経路「外部ロケーション e2e 経由で mlops-team が直接消す」は誤りで、UC は managed 領域へのパスアクセスを拒否する。主体は mlops-team ではなく AWS SSO の約 40 名。DeleteStack は非空バケットを消せず、実害は IAM ロール消失による一時停止。
    - **推奨**: 版管理（非現行版 30〜60 日）、バケットポリシーで UC ロール以外の Delete / Put を Deny。TerminationProtection と DeletionPolicy Retain。再生成に時間のかかる curation 系は週次 DEEP CLONE を別バケットへ。
- **G10** e2e.v2 / v2control の一次テーブルは DLT 生成物で、パイプライン削除やフルリフレッシュで落とせる
    - **事実**: 本番パイプライン 7 本は所有者 mono-e2e-ci、CAN_MANAGE は mlops-team と admins の継承（実質 10 名＋SP）。e2e.v2 156 本・v2control 160 本（raw_rlog 22 TB＋12 TB）。CLI の pipelines delete は既定 cascade で、2026-10-01 に dev パイプライン 7 本の削除で 158 テーブルが同時に消えた実例がある。本番 5 本全てに dropInactiveTables=true で、定義を消す PR が main にマージされると次回更新で DROP（main は承認 0）。
    - **リスク**: 1 コマンドで UNDROP 不能（パイプラインごと消すと ST / MV の UNDROP 不可）。td1-raw から再取り込みできるが数日〜数週間の空白。
    - **検証で直した点**: high を維持（重大度レンズは「再生成可能な派生」として medium を主張）。UI / API の削除は 2026-09-25 以降テーブル保持が既定、CLI は cascade。パイプラインが残る限り ST / MV も UNDROP できる。
    - **推奨**: 個人の CAN_MANAGE を外し、mlops-team を admins から外す。dropInactiveTables を本番で false。naga-pipeline を CODEOWNERS 必須に。行数・最新 trip 日付の前日比アラーム。
- **G17** amman-pipeline と biz-dev の一次データは IaC 外で、休眠の静的キーが削除権限を持つ
    - **事実**: amman-pipeline は IAM ユーザー 23 名・Active キー 29 本・MFA 0。AmazonS3FullAccess 相当 16 ユーザー＋AdministratorAccess 1 のキー 23 本は全て 2023〜2024 年以来未使用（最新は 2026-03）。2 ユーザーは Identity Center に対応する名前が無く、退職者の鍵と推定。SSO FullAccess 31 名も同じバケットを消せる。存在しない主体への SSO 割当が 7 件。biz-dev の静的キーが turing-video-lake 322 TB を消せる。
    - **リスク**: 所在不明の鍵 1 本で 178 TB の N-BOX 原本が復旧不能に消える。
    - **検証で直した点**: high を維持。「amman-nbox-log 161 TB、版管理あり」は誤りで、本体は版管理の無い amman-nbox-log-tmp 178 TB。turing-video-lake は YouTube 由来の収集動画で走行データではない。amman-pipeline の root は Research OU の SCP で塞がれている。
    - **推奨**: 23 本を即日 Inactive → 30 日後に削除、ユーザーとグループを解体。amman-nbox-log-tmp に版管理と削除 Deny。stale な SSO 割当 7 件を削除。biz-dev の GitHub Actions は OIDC へ。

## 6. 問題なしと確認できたこと

- **IaC からの削除**: 一次データバケットの配備済み CloudFormation テンプレートは全て DeletionPolicy=Retain / UpdateReplacePolicy=Retain で、autoDeleteObjects は scenario-test-gpu-offload の一時バケットだけ。cdk destroy や DeleteStack ではオブジェクトは消えない。mono-turing-infra の S3 バケットは force_destroy=false と prevent_destroy。mono-e2e の Databricks Terraform で重要テーブル・ボリュームは prevent_destroy。
- **アプリ経路**: backend-api の本番 Lambda ロールは raw / rlog / video バケットに一切の権限を持たない。S3 実体を消すルートは garuda purge（G20）、models（作成者限定）、backup rm（自領域限定）、feature-cache（内部 SigV4 のみ）の 4 つ。jadd-cli に S3 を直接消すコードは無い。JADD Studio の SQL 実行 API は DELETE / DROP / TRUNCATE / VACUUM を字句で拒否。
- **Databricks**: instance profile 0 件、クラスタは全て SINGLE_USER、DBFS に走行データ無し、Delta Sharing 無し。databricks-jobs と mono-e2e に raw を消すコードは無く、ジョブ 393 本に VACUUM / purge 系は無い。主要原本（td1-raw / tuscenes-raw）のボリュームは一般ユーザーには READ のみ。PAT 11 本に無期限は無い。system.access.audit は稼働中で、UC 経由の削除は主体付きで残る。
- **車両**: tp-driveos は静的キーを持たず IoT 資格情報プロバイダの 1 時間クレデンシャル。本番 raw への Put / Delete は無い。edge-ansible の秘密は Ansible Vault で暗号化。
- **組織**: CloudTrail の管理イベントは 10 アカウント全てで稼働（ログファイル検証 ON）、Control Tower のベースライン trail と Config の停止は SCP で Deny され、90 日で StopLogging / DeleteTrail は 0 件。management の root は MFA 3 台、root のアクセスキーは全アカウント無し。ci-cdk-deploy-role は main かつ特定 workflow に限定（G07 / G08 の修正の手本）。Databricks SCIM と Supabase auth.users に退職者は居ない。アクセスできない組織アカウントから tuscenes-prod の削除権限に届くロールも無い。
- **S3**: KMS 暗号化は全て AWS 管理鍵で、鍵削除による消失経路は無い。一次バケットの本体 prefix に Expiration は無い。パブリックアクセスブロックは 259 / 265 で全 Block、ACL の外部 grantee は 0。90 日の DeleteBucket 9 件は全て廃止済みの空バケット。S3 Inventory（td1-raw 日次・tuscenes-raw 週次・denso-taxi-video 日次）で 70 日以内なら「何が消えたか」は特定できる。
- **写し方向の安全**: GCS 転送と Azure DataSync はいずれも片方向で、S3 側の削除は伝播しない。

## 7. 対策ロードマップ

優先順位は「経路を塞ぐ効果 ÷ 作業量」。実行はしていない。既存の進行中の取り組み（cdk-apps PR #2024、service key 廃止、IdP 移行、backend-api 監査ログ、IAM ユーザー一元管理）との関係を各項目に書いた。

### 7.1 今日〜1 週間（止血、4 本柱）

<aside>
1️⃣

**柱 1: 原本バケットの版管理有効化＋SCP の Deny**（塞ぐ経路: 1〜9、12。G01 の根本原因）

- **版管理**: 版管理なしの 12 本に有効化する。IaC 管理の td1-raw / tuscenes-raw / tuscenes-annotation / denso-taxi-video / denso-nx-raw は cdk-apps の s3.Bucket に versioned: true、td1-rlog / denso-raw / denso-nx-sample / amman-nbox-log-tmp / databricks-workspace-e2e-bucket / td1-raw-471112873671 は手動で put-bucket-versioning。有効化は即時で既存データも対象になる（既存オブジェクトは null 版として残り、削除は削除マーカーになる）。
- **版管理だけでは止まらない相手**: DeleteObjectVersion・PutLifecycleConfiguration・PutBucketVersioning を持つ主体（SSO 37 名、静的キー、cfn-exec-role、root、management）は版ごと消せる。止まるのは DeleteObject / PutObject しか持たない主体（Coder・JADDViewer、Databricks の UC 経由すべて）と誤操作・暴走（rm --recursive、sync --delete、Expiration だけのライフサイクル、上書き）。
- **だから同じ週に SCP**: Product / misc OU に、一次 15 バケットに対する s3:DeleteObjectVersion・PutLifecycleConfiguration・PutBucketVersioning・PutBucketObjectLockConfiguration・DeleteBucket・PutBucketPolicy・DeleteBucketPolicy を break-glass ロール以外に Deny する。SCP はメンバーアカウントの root・IAM ユーザー・cfn-exec-role・Databricks のロールにも効く。残るのは management の管理者 7 名と kento-t のキーだけになり、SCP を外す操作は management の CloudTrail に残る。cdk-apps の organization-policy に追加（承認は 2 名体制に）。
- **権限セットの Deny も揃える**: TeamE2E の Deny を DeleteObjectVersion を含む形に（今は DeleteObject だけ）。
- **費用**: 版管理自体は無料。原本バケットは追記だけなので、通常運用では非現行版がほぼ増えない。費用が出るのは何かが消されたときで、消された分の保管料が続く（100 TB なら月 6 万円程度）。NoncurrentVersionExpiration は原本で 90 日、databricks-workspace-e2e-bucket（Delta の書き換えで非現行版が増える唯一のバケット）は 14〜30 日とし、有効化から 1 週間後に Storage Lens で非現行版の容量を確認して調整。
- **順序の注意**: LiDAR 間引きの残り（約 1.3〜1.6 PiB）を版管理の後に実行すると非現行版として残り、月 100 万円前後が続く。先に間引きを完了させるか、lidar プレフィックスだけ非現行版の失効を 7 日にする。
- **運用の変化**: 本当に消したいとき（間引き・廃止）は版 ID を指定する手順になる。
- 作業量: 版管理は半日、SCP は数日。
</aside>

<aside>
2️⃣

**柱 2: 静的キーの無効化**（塞ぐ経路: 5、6、11、amman の 23 本）

- tuscenes-prod（G05）: jadd-datasync、jadd-remote-sync-kohei.watanabe、shio-secretsmanager_GetSecretValue、jadd_studio_amplify の未使用キーを Inactive に。2 週間影響が無ければ削除。
- tokyo30（G04）: 先に 4 バケットのバケットポリシーでこのユーザーからの Delete 系・ライフサイクル・版管理変更を Deny（現場 PC を触らずに閉じられる）。次にポリシーを PutObject / AbortMultipartUpload / ListBucket だけの版に差し替え（現行スクリプトは Delete 系 API を呼ばないので処理は止まらない）、鍵をローテーション。
- management（G12）: freee 連携を identitystore の読み取りだけの専用ユーザーに差し替えてから、kento-t のキーを Inactive（日次利用は 10/1 から止まっている）。
- amman-pipeline（G17）: 23 本を Inactive。e2e-dev の test_yasumoto / DataUpload02 も同様（G19）。
- IAM ユーザー一元管理の棚卸しに含める。作業量は 1 日。
</aside>

<aside>
3️⃣

**柱 3: CI の権限分離**（塞ぐ経路: 8、9）

- cdk-apps: PR #2024（prod の CdkDeployRole を main 限定）をマージし、job_workflow_ref 条件を追加。本番 deploy workflow 12 本に main ガード。
- mono-e2e: mono-e2e-ci を Databricks の admins から外す。PR 用に USE / SELECT だけの plan 専用 SP。federation policy の subject を main に限定。environment に required reviewers。ルールセットを承認 1 以上に。
- Coder / JADDViewer（G03）: DataScientist を ReadOnly＋明示した書き込み先だけの自前ポリシーに置換。
- 作業量は 2〜3 日。
</aside>

<aside>
4️⃣

**柱 4: 削除系の検知**（全経路の「気づけない」を解消。G15）

- EventBridge: PutBucketLifecycle / DeleteBucket / PutBucketVersioning / DeleteBucketPolicy / PutBucketPolicy / PutBucketReplication、management は CloseAccount / LeaveOrganization / CreateAccessKey / CreateAccountAssignment を、既存の AWS Chatbot 経由で Slack へ。
- CloudWatch: 一次 15 バケットの NumberOfObjects / BucketSizeBytes の前日比 5% 減アラーム。
- CloudTrail: 一次バケット限定の WriteOnly データイベント trail を新設（ベースライン trail への追加は SCP が拒む）、log-archive へ配信。
- Databricks: system.access.audit の削除系アクション（deleteCatalog / deleteSchema / deleteExternalLocation / deletePipeline、一次スキーマ宛の deleteTable、一次ボリューム宛の filesDelete）を日次で Slack 通知する SQL アラート。
- Control Tower: Product / misc OU に root 制限コントロールを有効化（G11）。全アカウントに代替連絡先。
- 作業量は 2〜3 日。
</aside>

### 7.2 1 か月

- Databricks: 一次バケット向け外部ロケーション 8 本を READ ONLY、IAM ロール 7 本から Delete / Put / Lifecycle を外す、mlops-team の ALL PRIVILEGES を READ FILES に（G06）。DROP VOLUME `e2e.sandbox.td1`、`grants.tf` から e2e-team の WRITE_VOLUME を外す（G31）。所有者を mlops-team へ統一（G23）。
- 権限セットの Deny を一次 15 バケット × 削除系 API に拡張。SessionDuration を 4 時間へ。Engineers 群の AWSAdministratorAccess を撤去（G02）。
- GuardDuty を組織で有効化（委任管理者 audit、S3 Protection）。Security Hub の基本スタンダード。
- root: 集中 root 管理でメンバー root の資格情報を削除。aws@ の参加・投稿を制限（G11）。
- LidarDeleter / S3BatchDeleteLidar の整理（G22）。cdk-apps-denso のアーカイブ（G29）。stale な SSO 割当 7 件と taro.test の削除（G13, G17）。
- backend-api: garuda purge の所有者照合（G20）、認証なし DELETE 3 本の修正（G21）。service key 廃止と監査ログの取り組みに乗せる。
- td-uploader の rm 条件の修正と PR #33 / #13 の取り込み（G18）。

### 7.3 3 か月

- バックアップ専用アカウント（SSO FullAccess を割り当てない、Object Lock Compliance）へ、rlog → 再収集不能な動画 → UC 実体の順に S3 レプリケーション。同一リージョンなら転送料は掛からず、Deep Archive 直行で保管料は概算で月 60 万円前後（初回コピーの要求料は別、要見積り）。GCS は学習用配置と位置付け直す（G16）。
- 復旧 runbook（版管理の削除マーカー除去、UNDROP、レプリカからの戻し、DLT 再取り込み）と年 1 回の演習。RPO / RTO を決める。
- CloudTrail ログの Object Lock 付きバケットへの移行、保持 2〜3 年（G26）。Control Tower の 3.x 化（組織トレイル）。
- IdP 移行と合わせて、セッション期間の短縮・削除系 API への再認証・offboard 時の identitystore 削除を設計に入れる（G02, G27）。
- IAM ユーザーの全廃（IAM Roles Anywhere / OIDC へ）と permissions boundary の必須化を SCP で強制（G05, G17, G30）。

### 7.4 版管理についての補足

- 版管理で止まるのは「DeleteObject と PutObject しか持たない主体」と誤操作で、版削除やライフサイクル変更の権限を持つ主体は 1 手増えるだけで消せる。だから版管理は単独の対策ではなく、SCP とセットで初めて「権限があっても消せない」になる。
- 「権限があっても消せない」にする手段は 4 つ。SCP の Deny（費用ゼロ、management の管理者だけが外せる。本命）、Object Lock の Compliance モード（root でも期間内は消せないが不可逆で、DENSO データの返却・削除義務や LiDAR 間引きと衝突するので保持期間の設計が先）、別アカウントへのレプリケーション（独立した写し、費用は上記）、MFA Delete（ライフサイクル設定と両立せず td1-raw の Intelligent-Tiering 遷移が使えなくなるので勧めない）。

## 8. 検証で修正した主な点

前工程の所見のうち、検証で成り立たなかった、または過大だった主張。結論は変わらないが、正確さのため列挙する（詳細レポートには 25 点すべて）。

| 前工程の主張 | 検証結果 | 項目 |
| --- | --- | --- |
| DeleteBucket で Deny を迂回できる | 非空バケットは DeleteBucket できない。ライフサイクルで空にした後の仕上げにすぎない | G02, G04 |
| TeamE2E 23 名も IAM ロール作成や CloudFormation で迂回できる | TeamE2E は IAM と CloudFormation が implicitDeny。確実な迂回はライフサイクル 1 本。SSM 経由で起動中の Coder ワークスペースの権限を借りる条件付き経路は未実証 | G02, G03 |
| CDK スタックの削除で原本が消える | 一次バケットは RETAIN 既定で消えない | G02, G08, G09 |
| 外部ロケーション e2e 経由で UC managed テーブルの実体を直接消して UNDROP を迂回できる | UC が managed 領域へのパスアクセスを拒否する。Databricks 内からは DROP（UNDROP 可）か監査される DML のみ。AWS 側からの直接削除は成立する | G09 |
| Databricks 側から IAM ロールを assume してライフサイクルを変更できる | 信頼ポリシーは UC のマスターロールと自己 assume のみ。払い出される資格情報はパス単位 | G06 |
| S3 Batch Operations（S3BatchDeleteLidar、tokyo30 の CreateJob）で削除できる | Batch Operations にオブジェクト削除の操作は無い。この経路は不成立 | G22, G04 |
| lidar-cleaner は未実行 | 別ロール LidarDeleter で 2026-08-28〜09-03 に約 6.4 億オブジェクトを削除済み。途中で中断している | G22 |
| DLT パイプライン削除で公開テーブルが即 DROP され、ST / MV は UNDROP できない | UI / API は保持が既定、CLI は cascade が既定。パイプラインが残れば ST / MV も UNDROP できる | G10 |
| amman-nbox-log は 161 TB で版管理あり | 本体は版管理の無い amman-nbox-log-tmp 178 TB。amman-nbox-log は 0.05 TB | G17, G01 |
| kento-t のキーは Josys が使用 | キーのタグは freeeBundle。日次利用は 10/1 で停止 | G12 |
| オブジェクト削除は誰が行っても記録されない | AWS 側（CloudTrail・アクセスログ）に限る。Databricks 経由の削除は system.access.audit に主体付きで残る | G15 |
| 消えても翌月の請求減まで気づかない | 日次コストの Slack 投稿があり、PB 級なら 2〜4 日で人の目に入る（自動アラートではない） | G15 |
| 退職者が FullAccess を持つグループに残っていて使える | Okta の SCIM で無効化済み。同名で再作成しただけでは復活しない | G27 |
| GCS の日次同期は 9/11 に停止し、写しが止まっている | 変換バッチ完了時のオンデマンド起動に切替えたもの。現時点の欠落は無い | G16 |
| td1-raw-471112873671 は本番の写し | prod に無い車両・route を含む固有データ | G19 |
| td-uploader の欠陥は検知されない | 翌朝に「システム検証犬CLOUD」が rlog の存在を検証して Slack に投稿する。復旧はできない | G18 |

## 9. 未確認事項

人が認証や権限を用意して再確認すべきもの。

- **GCP**（gcloud の再認証が必要）: 転送先 GCS バケットの存在・容量・最終更新・versioning / soft delete / retention と、objectAdmin の実メンバー。G16 の「写しが実在する」は IaC と S3 側の転送記録からの推定。
- **Databricks アカウント API**（databricks auth login が必要）: SP mono-e2e-ci の federation policy の subject（pull_request を許可しているか）、アカウント管理者の一覧、他ワークスペースの有無。
- **Google Workspace / Okta**: aws@ の実メンバーとオーナー（identity リポの Terraform 定義 9 名で代替）。Okta 管理者の人数、MFA / サインオンポリシー。
- **アクセスできない組織アカウント**: canberra、gaggle-management、ota（車両ロールの実ポリシー）、corp-it、brain-research、nedo-4th、domain-central、external-project-1 の IAM・root・バケット・CloudTrail。
- **Azure**: denso-nx-raw の原本が残ることは確認したが、復旧（DataSync 再実行）の所要時間は未確認。
- **Coder**: 実際にログインできる人数とサインアップ設定（本文の「実質全従業員」は推測）。ワークスペース EC2 が SSM 管理ノードとして登録されているか（TeamE2E の条件付き経路の成立条件）。退職者の Coder ユーザーが無効化されているか。
- **Databricks**: workspace admin が自分を mlops-team に追加できるか（検証レンズ間で結論が割れ、実操作は未検証）。誰が SP mono-e2e-ci として実行できるか。UC メタストアのバックアップ機能の有無。all-employees がサーバーレス計算で任意コードを実行できるか。
- **IAM**: tuscenes-prod で使用中かつ削除権限を持つ IaC 管理の IAM ユーザー 5 本（Databricks-User、dataset-ops-gaggle、qinertia-runner-gaggle、ScenarioTestGpuOffload-ClusterJobUser、tuscenes-basicai-user）が、どのバケットの何を消せるか。
- **Databricks の実挙動**（書き込み禁止のため未実証）: Files API の削除が外部ボリュームで S3 の DeleteObject まで通ること、パイプラインの cascade 削除後の復旧可否、MODIFY だけで VACUUM RETAIN 0 HOURS が通るか。
- **Supabase backend-prod** の PITR の有無はダッシュボードで要確認（CLI では日次 PHYSICAL バックアップ 8 日分のみ）。
- **容量**: turing-video-lake / turing-video-ap-northeast-1 / amman-nbox-log-tmp / derived-data-994354357515 の一部レンズで再計測が未完了（他レンズの値で補完）。CloudFormation 外 54 バケットの突合、小バケット約 180 の版管理取得も未完。
- **2026-08-29 の td1-raw 約 1,040 万オブジェクト減少**は LiDAR 削除と時期が一致するが、記録が無いため断定できない。

## 10. 調査の方法と成果物

- **発見工程**: 8 観点（在庫、S3 設定、削除できる主体、Databricks、アプリ経路、IaC と CI、検知と復旧、組織とアカウント）をサブエージェントで並列に調査。所見 106 件を根本原因ごとに 31 項目に統合。
- **検証工程**: 各項目を「再現（鍵になる事実を自分でコマンドを打ち直す）」「反証（成り立たない条件を探す）」「重大度（基準に照らして再評価）」の 3 つで独立に検証。critical / high は 3 レンズ、medium は 2、low / info は 1。前工程の証拠ファイルを読むだけでは再現と認めなかった。最後に完全性の批評と改訂。
- **制約**: aws CLI は get / list / describe / head / lookup-events / simulate のみ、Databricks は SHOW / DESCRIBE / SELECT と REST の GET のみ、GitHub と git は読み取りのみ。何も作成・変更・削除していない。
- **重大度の基準**: critical = 単一主体・単一操作で主要な一次データが復旧不能に消える経路が今ある。high = 復旧不能だが複数条件が要る、または数十 TB 規模。medium = 復旧可能だが検知が無い、または派生データ。low = 衛生面。
- **主な限界**: GCP・Databricks アカウント API・Google Workspace・Okta・一部の組織アカウントは認証や権限が無く未確認（9 章）。Databricks の削除の実挙動は書き込み禁止のため推論。人数は Identity Center のグループ人数（ネスト・無効化は未考慮）。
- **日時**: 発見 2026-10-09 19:49〜20:50 JST、検証 2026-10-09 20:50〜10-10 00:41 JST、執筆 10-10、本ページ作成 10-15。
- **成果物**（安本の端末の ~/work/data-deletion-risk）: `report.md`（詳細 9 章、約 115 KB）、workflow/findings-all.json（所見 106 件）、workflow/items/（31 項目）、workflow/verify-run2.json（検証結果）、evidence/（生データと再現コマンド、約 800 MB）。
- **作成**: 安本が Claude Code で実施。問い合わせは安本まで。