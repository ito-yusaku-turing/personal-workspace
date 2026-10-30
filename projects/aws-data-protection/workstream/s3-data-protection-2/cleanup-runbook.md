# 原本バケットに届く主体の掃除（手順書）

- 作成: 2026-10-30 ／ 伊藤（下書きはエージェント）
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md) のステージ 4（TODO 13・14）
- 根拠: [current-state.md](current-state.md) の 3 章・4 章（2026-10-30 に全 740 主体を判定）
- 棚卸しとの関係: [project:information-resource-inventory の掃除の候補](../../../information-resource-inventory/workstream/aws-resource-inventory/cleanup-candidates.md) と重なるものは、その番号（S3・S5〜S7・C3-6）を併記した。重なるものは、この手順書で片付ける
- 対象: tuscenes-prod（767397804933）

## 進め方

- **伊藤が `full` プロファイルで、番号ごとに実施する。** 終わったら「N 番を実施した」とエージェントに伝える。
- **エージェントが ReadOnly（`readonly` プロファイル）で、実施の前と後の確認をする。** 実施の前の確認は、伝えてもらえれば直前にやり直す（2026-10-30 の確認から日がたつため）。
- スクリプト（`cleanup/`）は、**既定で空実行**（何を消すかを表示するだけ）。表示を見てから、`--apply` を付けて実行する。
- 1〜11 は、すぐに消してよいもの。12・13 は、持ち主や扱いを決めてから。

```bash
cd projects/aws-data-protection/workstream/s3-data-protection-2/cleanup
./delete-iam-role.sh full <ロール名>                 # 空実行
./delete-iam-role.sh full <ロール名> --apply         # 実行
```

## 一覧

| # | 対象 | なぜ消すか | 最終利用 | 棚卸し | 状態 |
|---|---|---|---|---|---|
| 1 | Amplify の SSR のログ用のロール 12 本と、専用のポリシー 12 本 | うち 6 本は、AWS 管理のポリシー `AmplifyBackendDeployFullAccess` で **deploy のロールを引き受けられ、原本バケットの守りを外せる**。Amplify のアプリは 4 リージョンとも無い | 2024-12 以前か未使用 | （3 章の「Amplify の SSR のログ用」） | 未 |
| 2 | `CodeCatalystWorkflowDevelopmentRole-tuscenes-prod`・`AWSRoleForCodeCatalystSupport` | 前者は **AdministratorAccess**。deploy のロールの引き受け・ロールの作成ができる | 2024-03-14・2024-03-13 | S3 | 未 |
| 3 | `tuscenes-sampler-test-role-n1huu9jg` と専用のポリシー 2 本 | AmazonS3FullAccess・SecretsManagerReadWrite。使う Lambda は無い | 2024-07-10 | S7 | 未 |
| 4 | `tuscenes-processing` とインスタンスプロファイル | AmazonS3FullAccess。どの EC2 にも付いていない | 2024-07-16 | S7 | 未 |
| 5 | `AmazonEMRStudio_RuntimeRole` | AmazonS3FullAccess。EMR Serverless のアプリ 2 本は止まっていて、ジョブの実行の履歴も無い | 2024-08-28 | S7 | 未 |
| 6 | `ecsTaskExecutionRole` | AmazonS3FullAccess・SecretsManagerReadWrite。us-west-2 の有効なタスク定義からは参照されていない | 2025-03-25 | S7 | 未 |
| 7 | `GlueRole` | S3 の読み取りと、プレフィックス限定の削除・上書き。Glue のジョブは無い | 2024-08-28 | — | 未 |
| 8 | `AmazonSageMaker-ExecutionRole-20240315T103566` と専用のポリシー | AmazonSageMakerFullAccess と 12 本の削除・上書き。ドメインの既定ではない | 2024-04-01 | — | 未 |
| 9 | IAM ユーザー `jadd-datasync` | AmazonS3FullAccess。キーは無効 | 2025-10-11 | S5 | 未 |
| 10 | IAM ユーザー `jadd-remote-sync-kohei.watanabe` と、9・10 だけが使うポリシー `AmazonS3ExpressFullAccess`（カスタマー管理） | AmazonS3FullAccess。キーは無効 | 2025-10-20 | S5 | 未 |
| 11 | IAM ユーザー `shio-secretsmanager_GetSecretValue` | AmazonS3FullAccess とシークレットの読み取り。キーは無効 | 2025-08-07 | S6 | 未 |
| 12 | スタック `sfn-auto-labeling`（Lambda 3 本・Step Functions・ロール 4 本） | Lambda のロールが AmazonS3FullAccess。コードが見当たらない（どのリポジトリにも無い） | 2024-10-11 | C3-6 | **要確認** |
| 13 | SageMaker のドメイン `e2e` と、既定のロール `SageMaker-ExecutionRole-20240206T192166`（専用のポリシー 5 本） | ロールが原本バケット 5 本の削除・上書きと SageMaker の全権を持つ。ドメインに 4 名のユーザープロファイルが残る | 2024-05-07 | — | **要確認** |

## 共通: 戻し方

消す前の定義を [cleanup/backup/](cleanup/backup/) に控えた（2026-10-30、`get-account-authorization-details` から。信頼・付いていたポリシー・インラインのポリシー・専用のポリシーの中身・タグ）。

- **ロール:** `create-role`（`Path`・`AssumeRolePolicyDocument`・`Tags` を控えから）→ 専用のポリシーを消していれば `create-policy` → `attach-role-policy` → インラインは `put-role-policy`。インスタンスプロファイルは `create-instance-profile` と `add-role-to-instance-profile`。ARN は同じになるが、ロール ID（`AROA…`）は変わる。ロール ID で信頼している相手は、作り直しても戻らない。
- **IAM ユーザー:** 作り直せるが、アクセスキーは戻せない（新しいキーになる）。
- **スタック:** 消すとリソースは戻らない。12 番は、消す前に template と Lambda のコードを控える。

---

## 1. Amplify の SSR のログ用のロール（12 本）

**実施の前の確認（エージェント）:** 4 リージョン（us-west-2・ap-northeast-1・us-east-1・us-east-2）で `aws amplify list-apps` が空。12 本の最終利用が 2026-10-30 の控えから変わっていない。専用のポリシー（`AmplifySSRLoggingPolicy-*`）が、それぞれのロールにしか付いていない（付き先 1）。

**実施（伊藤）:**

```bash
for r in $(aws --profile readonly iam list-roles --path-prefix /service-role/ \
    --query "Roles[?starts_with(RoleName,'AmplifySSRLoggingRole-')].RoleName" --output text); do
  ./delete-iam-role.sh full "$r" --delete-own-policies          # 空実行。12 本分の表示を見る
done
# 表示が想定どおりなら、--apply を付けて同じループを回す
```

**実施の後の確認（エージェント）:** `AmplifySSRLoggingRole-*` と `AmplifySSRLoggingPolicy-*` が 0 本。

## 2. CodeCatalyst のロール（2 本）

**実施の前の確認:** 2 本とも最終利用が 2024-03 のまま。

**実施:**

```bash
./delete-iam-role.sh full CodeCatalystWorkflowDevelopmentRole-tuscenes-prod
./delete-iam-role.sh full AWSRoleForCodeCatalystSupport
# 表示を見てから --apply
```

**実施の後の確認:** 2 本とも `NoSuchEntity`。全主体の判定（`iam-scan/escalation.py`）から消える。

## 3. `tuscenes-sampler-test-role-n1huu9jg`

**実施の前の確認:** 2 リージョンの Lambda で、このロールを使う関数が無い。

**実施:**

```bash
./delete-iam-role.sh full tuscenes-sampler-test-role-n1huu9jg --delete-own-policies
```

専用のポリシー `AWSLambdaBasicExecutionRole-e45aa1fe-…`・`-09ad65ef-…`（付き先 1）も消える。

**実施の後の確認:** ロールとポリシー 2 本が無い。

## 4. `tuscenes-processing`

**実施の前の確認:** 2 リージョンで、インスタンスプロファイル `tuscenes-processing` が EC2 に付いていない。

**実施:**

```bash
./delete-iam-role.sh full tuscenes-processing
```

同じ名前のインスタンスプロファイルも消える。

**実施の後の確認:** ロールとインスタンスプロファイルが無い。

## 5. `AmazonEMRStudio_RuntimeRole`

**実施の前の確認:** EMR Serverless のアプリ（`x86`・`Serverless_Interactive_App`、us-west-2）が止まったままで、ジョブの実行の履歴が無い。

**実施:**

```bash
./delete-iam-role.sh full AmazonEMRStudio_RuntimeRole
```

EMR Serverless のアプリ 2 本は、このロールが無くても残る（実行のときにロールを渡す仕組み）。アプリの片付けは、棚卸しの側で扱う。

**実施の後の確認:** ロールが無い。

## 6. `ecsTaskExecutionRole`

**実施の前の確認:** 2 リージョンの有効なタスク定義で、`executionRoleArn`・`taskRoleArn` にこのロールを使うものが無い（2026-10-30 は us-west-2 で 0 件。ap-northeast-1 は直前に確かめる）。

**実施:**

```bash
./delete-iam-role.sh full ecsTaskExecutionRole
```

注: ECS のコンソールの既定の名前なので、コンソールでタスク定義を作ると、同じ名前で作り直されることがある。作り直されたら、権限は `AmazonECSTaskExecutionRolePolicy` だけになる（S3 の権限は付かない）。

**実施の後の確認:** ロールが無い。

## 7. `GlueRole`

**実施の前の確認:** 2 リージョンで Glue のジョブ・クローラー・開発エンドポイントが無い。

**実施:**

```bash
./delete-iam-role.sh full GlueRole
```

**実施の後の確認:** ロールが無い。

## 8. `AmazonSageMaker-ExecutionRole-20240315T103566`

**実施の前の確認:** SageMaker のドメイン `e2e` の既定のロールでも、ユーザープロファイルのロールでもない。ノートブック・ジョブ・エンドポイントから使われていない。

**実施:**

```bash
./delete-iam-role.sh full AmazonSageMaker-ExecutionRole-20240315T103566 --delete-own-policies
```

専用のポリシー `AmazonSageMaker-ExecutionPolicy-20240315T103566`（付き先 1）も消える。

**実施の後の確認:** ロールとポリシーが無い。

## 9・10・11. IAM ユーザー（3 人）

キーはすでに無効。有効なキーが残っていたら、スクリプトは止まる。

**実施の前の確認:** 3 人とも有効なキーが 0 本、ログインのパスワードが無い。

**実施:**

```bash
./delete-iam-user.sh full jadd-datasync                       # 9
./delete-iam-user.sh full jadd-remote-sync-kohei.watanabe     # 10
./delete-iam-user.sh full shio-secretsmanager_GetSecretValue  # 11
# それぞれ表示を見てから --apply
```

10 番の後に、9・10 だけが使っていたカスタマー管理のポリシーを消す（付き先が 0 になっていることを確かめてから）:

```bash
aws --profile full iam get-policy --policy-arn arn:aws:iam::767397804933:policy/AmazonS3ExpressFullAccess --query Policy.AttachmentCount
aws --profile full iam list-policy-versions --policy-arn arn:aws:iam::767397804933:policy/AmazonS3ExpressFullAccess
# 既定でない版があれば delete-policy-version で消してから
aws --profile full iam delete-policy --policy-arn arn:aws:iam::767397804933:policy/AmazonS3ExpressFullAccess
```

11 番のポリシー `secretsmanager_GetSecretValue` は、ほかにも付き先があるので残す。

**実施の後の確認:** 3 人とも `NoSuchEntity`。`AmazonS3ExpressFullAccess` が無い。IAM ユーザーは 34 人になる。

## 12. スタック `sfn-auto-labeling`（要確認）

**決めること:** 持ち主（auto-labeling を作った人）に確かめるか、確かめずに消すか。コードはマウント済みのリポジトリのどこにも無い。棚卸しでは、AWS Batch の計算環境 `auto-labeling-compute-env` の持ち主も、アーカイブ済みの `map-auto-labeling` 系のリポジトリとされている。

**実施の前の確認（エージェント）:** Step Functions の `AutoLabelingStateMachine…` の実行の履歴、Lambda 3 本の呼び出しの回数（CloudWatch の 90 日）、Lambda のロールの最終利用。

**消す前の控え（伊藤か、エージェントが ReadOnly で）:** `aws cloudformation get-template --stack-name sfn-auto-labeling`、Lambda 3 本の `get-function`（コードの zip をダウンロードする）。

**実施（決めたあと、伊藤）:**

```bash
aws --profile full cloudformation delete-stack --region us-west-2 --stack-name sfn-auto-labeling
aws --profile full cloudformation wait stack-delete-complete --region us-west-2 --stack-name sfn-auto-labeling
```

**実施の後の確認:** スタックが `DELETE_COMPLETE`。ロール 4 本・Lambda 3 本・ステートマシンが無い。

## 13. SageMaker のドメイン `e2e` と、そのロール（要確認）

**決めること:** ドメインを使っている人がいるか。ユーザープロファイルは 4 名（kohei-watanabe・koki-igari・kohei-iwamasa・kazuki-matsuda）。動いているアプリは無く、ドメインの最終更新は 2024-04-01、ロールの最終利用は 2024-05-07。

**ロールだけを消すと、ドメインが壊れた状態で残る。** 消すならドメインごと消す。ドメインを消すには、アプリ・スペース・ユーザープロファイルを先に消す必要があり、ホームの EFS を残すか消すか（`RetentionPolicy`）も決める。手順は、扱いが決まってから書く。

---

## 削除しないもの（参考）

| 対象 | 理由と扱い |
|---|---|
| Databricks の Unity Catalog のロール `databricks-uc-3913775780464502-db_s3_external_cluster-st152026da` | 使用中（2026-10-30）。deploy のロールを引き受けられるのは、インラインのポリシーの `sts:AssumeRole` が `Resource: *` のため。自分自身に絞れば塞がるが、Databricks 側が作ったロールなので、直しても戻されるおそれがある。Databricks の担当と直し方を相談する。SCP で止める案もある（TODO 24） |
| `S3BatchDeleteLidar` | 一度も使われていないが、mono-e2e の `projects/lidar-cleaner` の設定から参照されている。TODO 16 で扱う |
| `LidarDeleter` | 2026-08〜09 の LiDAR の間引きで使った。TODO 16 で扱う |
| IAM ユーザー `tokyo30-dataupload-pc-01` | キーが有効で、今日も使われている（2026-10-30）。持ち主に確かめる（TODO 13） |
| CDK の bootstrap（us-east-1・us-east-2） | cfn-exec-role が守りを外せるが、Coder の旧版のスタック `CoderWorkspace` がまだ載っている。棚卸しの Coder の片付け（5 章）のあとで消す |
| Control Tower・StackSets のロール | AWS と管理アカウントが使う。消さない |
| `tuscenes-cicd-GithubActionsRole…` | 守りは外せない（スタックの作成の権限が無い）。棚卸しの S10 で、スタックごと片付ける |
