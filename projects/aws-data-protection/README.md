# project:aws-data-protection 目録

tuscenes-prod（767397804933）の S3 原本バケットを、消失や破壊から守る案件。第一弾（バージョニング、2026-10-20 完了）と第二弾（権限設計のアップグレード、進行中）、そこから切り出した AWS アカウントの手当てを扱う。作業先は主に cdk-apps（`/usr/app/cdk-apps`）。

2026-10-26 に `~/docs`（`workstream/` の一部と `security/`）から移した。ファイルを追加・移動・削除したら、この目録も同じコミットで更新する（ルールは personal-workspace の `AGENTS.md`「projects/（案件ごとの資料）」）。

## workstream/ — 進行中の作業記録

- [workstream/s3-data-protection-2.md](./workstream/s3-data-protection-2.md): **S3 バケットのデータ保護 第二弾（権限設計のアップグレード）**。古い版ごと消す・守りを外す操作ができる 37 主体を権限設計から直す。ステージ 1〜4 と通し番号の TODO で進める
  - [workstream/s3-data-protection-2/requirements.md](./workstream/s3-data-protection-2/requirements.md): **全体の状態と要件**（2026-10-30）。議論を要件の明確化まで戻したときの出発点。入っている守り・止まっている作業・選択肢・誰も扱っていないもの、要件（1〜14）、問い a〜h とその回答と設計への影響（2026-10-30）、設計の骨格の案
  - [workstream/s3-data-protection-2/current-state.md](./workstream/s3-data-protection-2/current-state.md): **原本バケットの現状**（2026-10-30）。できていること（止める・遅らせる・気づく・戻す・判断の経路ごと）と、だれが何をできるか（強い順に 5 段。例外を名乗れる経路を含む）、ReadOnly で確かめたことと見えていないこと、今の構成の弱点（W1〜W16 と、脅威の範囲との関係）
  - [workstream/s3-data-protection-2/option-reassessment.md](./workstream/s3-data-protection-2/option-reassessment.md): **BreakGlass と WORM の再評価**（2026-10-30）。固まった要件に照らし、BreakGlass は必要性が下がり（cdk-apps の PR を経路にする案）、WORM は有用性が上がった（外せない層・遅らせる）とした見立てと、組み合わせの案、決めてほしいことと回答（BreakGlass は撤回の方向、WORM は本命の候補）、ホールドの解除の経路の調査（GitHub Actions の専用の workflow、調べた場所つき）
  - [workstream/s3-data-protection-2/permission-upgrade-plan.md](./workstream/s3-data-protection-2/permission-upgrade-plan.md): チーム共有用のアップグレードプラン（4 原則と進め方。Notion に上げる）
  - [workstream/s3-data-protection-2/breakglass-proposal.md](./workstream/s3-data-protection-2/breakglass-proposal.md): **BreakGlass 権限の導入の提案**。MLOps チームと CorpIT チーム向け。BreakGlass 権限の考え方・今の FullAccess・ギャップ・移行の手順・残るリスク・お願いしたいこと（2026-10-29、第一版。2026-10-30 にチームの議論で選択肢の 1 つに戻した。Notion: https://app.notion.com/p/408a93b3e6f281b38292d14cbbed304c ）
  - [workstream/s3-data-protection-2/worm-design.md](./workstream/s3-data-protection-2/worm-design.md): **原本バケットの WORM 化の設計**（TODO 26。2026-10-30 に全体設計の選択肢の 1 つに戻した）。決めたこと（12 本・コンプライアンス・時間がたっても外れない鍵＝可変の保持期間・解除の後 30 日・解除は BreakGlass だけ・既存の最新版にもかける〈仮〉）、費用（一度きり約 $3,900） と理由、誰が鍵を外せるか、ガバナンスの強さ、ライフサイクルとの衝突、消す必要が出る想定ケース（2026-10-30）
  - [workstream/s3-data-protection-2/worm-reference.md](./workstream/s3-data-protection-2/worm-reference.md): WORM 化の設計の添付。比べたこと（鍵の表し方・モード・解除後の日数）と調べたこと（可変の保持期間の仕様と出典、CloudFormation・CLI・Batch Operations の対応、12 本の今の設定と件数・費用）（2026-10-30）
  - [workstream/s3-data-protection-2/worm-probe-runbook.md](./workstream/s3-data-protection-2/worm-probe-runbook.md): 可変の保持期間（イベントホールド）を使い捨てのバケットで試す手順書（未実行・保留。既定の意味・迂回・解除・コンプライアンスでの解除・チェックサム・Batch Operations）（2026-10-30）
  - [workstream/s3-data-protection-2/breakglass-design-draft.md](./workstream/s3-data-protection-2/breakglass-design-draft.md): BreakGlass の設計の叩き台（内部の検討の記録。チーム向けは上の提案）（2026-10-29）
  - [workstream/s3-data-protection-2/stage2-hourly-report.md](./workstream/s3-data-protection-2/stage2-hourly-report.md): ステージ 2「原本バケットの削除の毎時の報告」の設計（cdk-apps `apps/original-bucket-audit`、カナリア）
  - [workstream/s3-data-protection-2/bucket-policy/](./workstream/s3-data-protection-2/bucket-policy/test-runbook.md): ステージ 1 のバケットポリシー一式。生成・比較・シミュレーションのスクリプト、12 本分の生成結果（`rendered/`）、使い捨てバケットで試す手順書（`test-runbook.md`）
  - `workstream/s3-data-protection-2/stage2-verify/cdk/cdk.out/`: ステージ 2 の検証用スタック（`S2vProbeStack`）の合成結果。CDK のソースは移す前から残っていない
- [workstream/tuscenes-stack-cleanup.md](./workstream/tuscenes-stack-cleanup.md): **古いスタック tuscenes を片付ける**。アーカイブ済みの tuscenes-pipeline が残したスタック（ルール・Lambda・IAM ユーザー・バケット 5 本）。第二弾の TODO 23 の調査で見つかった。積んでいる
- [workstream/aws-root-credentials.md](./workstream/aws-root-credentials.md): **メンバーアカウントの root の認証情報を消す**。tuscenes-prod の root（パスワード有効・MFA なし）の削除を CorpIT に依頼する

## workstream/done/ — 完了した作業記録

- [workstream/done/jadd-studio-amplify-removal.md](./workstream/done/jadd-studio-amplify-removal.md): **IAM ユーザー jadd_studio_amplify を削除する**。キーが jadd_studio3 の git 履歴に平文で残っていたユーザー。2026-10-26 にユーザーと Amplify の一式を削除して完了
  - [workstream/done/jadd-studio-amplify-removal/delete-runbook.md](./workstream/done/jadd-studio-amplify-removal/delete-runbook.md): 削除の手順書（AWS CLI。実行前後の確認と戻し方）
  - [workstream/done/jadd-studio-amplify-removal/amplify-cleanup-runbook.md](./workstream/done/jadd-studio-amplify-removal/amplify-cleanup-runbook.md): Amplify の一式（スタック・アプリ・Cognito・バケットなど）の削除の手順書（AWS CLI）
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
- [documents/notion-s3-object-lock.md](./documents/notion-s3-object-lock.md): **S3 Object Lock（WORM）の整理**。チーム共有用（Notion に上げる）。仕組み・モード・今の守りへの重なり方・費用・決めること（2026-10-26）
- [documents/privileged-access-and-break-glass.md](./documents/privileged-access-and-break-glass.md): **特権アクセスと break-glass の一般論**。学習用。組織と人のレイヤーの設計、緊急用のアクセス、特権を持つ人の要件を、NIST・ISO・Microsoft・AWS・政府統一基準・IPA を根拠にまとめた（2026-10-29）
- [documents/aws-privilege-hierarchy.md](./documents/aws-privilege-hierarchy.md): **AWS の権限の階層**。複数アカウントの組織での権限の階層の一般論と、うちの組織への当てはめ（管理アカウントへの CI の経路の調査を含む）
