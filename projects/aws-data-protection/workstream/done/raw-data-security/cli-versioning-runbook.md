# 手で作った原本バケットのバージョニングの手順書（AWS CLI）

- 作成: 2026-10-19（同日に、古い版を失効させない形に改めた）
- **実施: 2026-10-20 15:07 JST**（伊藤、SSO FullAccess）。3 本とも `Enabled`、ライフサイクルは変わらないことを ReadOnly で確かめた（CloudTrail の `PutBucketVersioning` も 3 件、エラー無し）
- 対象: tuscenes-prod（767397804933）、us-west-2 の 3 本
- やること: バージョニングを有効にする。**ライフサイクルは変えない**（古い版は失効させない）
- 実行する人: 書き込みの権限を持つ人（SSO の FullAccess など）。ReadOnly ではできない

## 対象

| バケット | 種別 | 容量 | 今のバージョニング | 今のライフサイクル（変えない） |
|---|---|---|---|---|
| `td1-rlog` | S1 自社収集 | 21.1 TB | 無し | `td1-rlog`: バケット全体を Intelligent-Tiering へ |
| `tuscenes-calibration`（旧、接尾辞なし） | S1 自社収集 | 1.3 TB | 無し | `MoveToIntelligentTiering`: バケット全体を Intelligent-Tiering へ |
| `denso-raw-767397804933` | S2 他社から受領 | 15.2 TB | 無し | `MoveToIntelligentTiering`: `tmp/` だけを Intelligent-Tiering へ |

- 3 本とも手で作ったもので、CloudFormation の管理下に無い（タグも無い）。2026-10-19 に ReadOnly で確かめた。
- tuscenes-basicai-datasets は、今回の手当てから外した（中身と経緯がよく分からないため）。

## なぜ CLI か

手で作ったバケットで、書き込みもほとんど無い。運用の実態に合わせて、cdk import で IaC に取り込むのではなく CLI で入れる（2026-10-19 に決定）。

## なぜ失効させないか

今回の手当ては操作ミスへの備え。失効を付けると、ミスに気づけないまま期限を過ぎたときに、そこで本当に消える。原本はふだん消しも上書きもしないので、失効が無くても古い版はほとんど溜まらない。意図して消すときは、ライフサイクルなどで古い版ごと消す（cdk-apps #2211 のレビューの指摘で、CDK の 4 本と揃えた）。

## 手順

```sh
export AWS_PROFILE=<書き込みの権限のあるプロファイル>
export AWS_REGION=us-west-2

# 0. 正しいアカウントか確かめる（767397804933 であること）
aws sts get-caller-identity --query Account --output text

# 1. 実行前の状態を確かめる（3 本とも何も出ない＝一度も有効にしていない、であること）
aws s3api get-bucket-versioning --bucket td1-rlog --expected-bucket-owner 767397804933
aws s3api get-bucket-versioning --bucket tuscenes-calibration --expected-bucket-owner 767397804933
aws s3api get-bucket-versioning --bucket denso-raw-767397804933 --expected-bucket-owner 767397804933

# 2. バージョニングを有効にする（成功しても何も出ない）
aws s3api put-bucket-versioning --bucket td1-rlog --expected-bucket-owner 767397804933 --versioning-configuration Status=Enabled
aws s3api put-bucket-versioning --bucket tuscenes-calibration --expected-bucket-owner 767397804933 --versioning-configuration Status=Enabled
aws s3api put-bucket-versioning --bucket denso-raw-767397804933 --expected-bucket-owner 767397804933 --versioning-configuration Status=Enabled

# 3. 結果を確かめる（3 本とも "Status": "Enabled"）
aws s3api get-bucket-versioning --bucket td1-rlog --expected-bucket-owner 767397804933
aws s3api get-bucket-versioning --bucket tuscenes-calibration --expected-bucket-owner 767397804933
aws s3api get-bucket-versioning --bucket denso-raw-767397804933 --expected-bucket-owner 767397804933
```

- `--expected-bucket-owner` は、別のアカウントの同名バケットを誤って操作しないための保険。`td1-rlog` と `tuscenes-calibration` は名前にアカウント番号が付いていないので、特に効く。
- 1 行に 1 つのコマンドで、ループも変数も使わない（1 行ずつ貼って結果を見ながら進められるように。2026-10-20 に改めた）。
- 3 の確認は ReadOnly の権限でもできる（実行後にエージェントに頼んでもよい）。

## 戻し方

- **バージョニングは無効に戻せない。** 戻すなら `Status=Suspended`（一時停止）にする。一時停止しても、それまでにできた古い版は残る。

## 費用

- 有効にする前からあるオブジェクトは null 版として残り、費用は変わらない。
- 3 本とも書き込みも削除もほとんど無いので、古い版はほぼ増えない。
