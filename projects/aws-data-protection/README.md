# project:aws-data-protection 目録

tuscenes-prod（767397804933）の S3 原本バケットを、消失や破壊から守る案件。第一弾（バージョニング、2026-10-20 完了）と第二弾（権限設計のアップグレード、進行中）、そこから切り出した AWS アカウントの手当てを扱う。作業先は主に cdk-apps（`/usr/app/cdk-apps`）。

2026-10-26 に `~/docs`（`workstream/` の一部と `security/`）から移した。ファイルを追加・移動・削除したら、この目録も同じコミットで更新する（ルールは personal-workspace の `AGENTS.md`「projects/（案件ごとの資料）」）。

## workstream/ — 進行中の作業記録

- [workstream/s3-data-protection-2.md](./workstream/s3-data-protection-2.md): **S3 バケットのデータ保護 第二弾（権限設計のアップグレード）**。古い版ごと消す・守りを外す操作ができる 37 主体を権限設計から直す。ステージ 1〜4 と通し番号の TODO で進める
  - [workstream/s3-data-protection-2/permission-upgrade-plan.md](./workstream/s3-data-protection-2/permission-upgrade-plan.md): チーム共有用のアップグレードプラン（4 原則と進め方。Notion に上げる）
  - [workstream/s3-data-protection-2/stage2-hourly-report.md](./workstream/s3-data-protection-2/stage2-hourly-report.md): ステージ 2「原本バケットの削除の毎時の報告」の設計（cdk-apps `apps/original-bucket-audit`、カナリア）
  - [workstream/s3-data-protection-2/bucket-policy/](./workstream/s3-data-protection-2/bucket-policy/test-runbook.md): ステージ 1 のバケットポリシー一式。生成・比較・シミュレーションのスクリプト、12 本分の生成結果（`rendered/`）、使い捨てバケットで試す手順書（`test-runbook.md`）
  - `workstream/s3-data-protection-2/stage2-verify/cdk/cdk.out/`: ステージ 2 の検証用スタック（`S2vProbeStack`）の合成結果。CDK のソースは移す前から残っていない
- [workstream/aws-root-credentials.md](./workstream/aws-root-credentials.md): **メンバーアカウントの root の認証情報を消す**。tuscenes-prod の root（パスワード有効・MFA なし）の削除を CorpIT に依頼する
- [workstream/jadd-studio-amplify-removal.md](./workstream/jadd-studio-amplify-removal.md): **IAM ユーザー jadd_studio_amplify を削除する**。キーが jadd_studio3 の git 履歴に平文で残っていたユーザー。キーは無効化済み、削除は未着手

## workstream/done/ — 完了した作業記録（第一弾）

- [workstream/done/raw-data-security.md](./workstream/done/raw-data-security.md): **走行データ消失リスクへの対応（バケットの価値の見積もり）**。第一弾の親。PUT/GET からバケットの価値を見積もり、種別 S1〜S10 と処遇を裁定した
  - [workstream/done/raw-data-security/cli-versioning-runbook.md](./workstream/done/raw-data-security/cli-versioning-runbook.md): 手で作った原本バケット 3 本のバージョニングを AWS CLI で入れる手順書（2026-10-20 実施済み）
  - [workstream/done/raw-data-security/notion-bucket-classification.md](./workstream/done/raw-data-security/notion-bucket-classification.md): チーム共有用の記事「S3 バケットの種別とバージョニングの処遇」
  - [workstream/done/raw-data-security/notion-s3-versioning-proposal.md](./workstream/done/raw-data-security/notion-s3-versioning-proposal.md): チームの合意を取るための記事「S3 バケットに版管理を入れる提案」（2026-10-16）
  - `workstream/done/raw-data-security/`（`*.py` `*.sh` `*.tsv` `cw.json.gz`）: 価値の見積もりに使ったスクリプトと集計データ（2026-10-15 取得）。中身の一覧は親資料の「成果物」
- [workstream/done/s3-versioning-cdk.md](./workstream/done/s3-versioning-cdk.md): **原本バケットのバージョニング（cdk-apps の準備）**。CDK 管理のバケットに cdk-apps の PR 4 本でバージョニングを入れた
- [workstream/done/s3-bucket-access-control.md](./workstream/done/s3-bucket-access-control.md): **原本バケットへのアクセスの洗い出しと手当て**。原本バケットを壊せる主体を洗い出した。第二弾の根拠
  - [workstream/done/s3-bucket-access-control/principals-2026-10-20.md](./workstream/done/s3-bucket-access-control/principals-2026-10-20.md): 原本バケットを壊せる主体の一覧（2026-10-20 時点。`data/final.py` で生成）
  - `workstream/done/s3-bucket-access-control/data/`: 洗い出しのスクリプト、バケット一覧、主体の生データ、当時のバケットポリシー

## documents/ — 参考資料

- [documents/raw-data-security.md](./documents/raw-data-security.md): **走行データ消失リスク調査（2026-10）**。安本さんの調査（Notion から取り込み）。workstream の G 番号はこの資料の所見 ID
- [documents/aws-privilege-hierarchy.md](./documents/aws-privilege-hierarchy.md): **AWS の権限の階層**。複数アカウントの組織での権限の階層の一般論と、うちの組織への当てはめ（管理アカウントへの CI の経路の調査を含む）
