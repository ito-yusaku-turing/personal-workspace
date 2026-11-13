# 外部資料の目録

personal-workspace の外にある資料（ほかのリポジトリ・Notion・公式の文書）の、**どこに何が書いてあるか**の目録。中身は写さず、場所と、何を調べるときに読むかだけを書く。

- 作成: 2026-11-13 ／ 伊藤（エージェントが起草）
- 足すとき: 調べもので外部の資料を読んで役に立ったら、1 行足す。読んだ版（コミットや日付）が効くものは添える。古くなった行は直すか消す。
- 案件の資料からの参照は、これまでどおりそれぞれの資料に書く。ここは「次に同じことを調べるとき、どこから読むか」の入口。

## リポジトリ（`/usr/app/` にマウントしているもの）

入口は、どのリポジトリもトップの `AGENTS.md`（無ければ `CLAUDE.md`・`README.md`）。作業するときはそれに従う（[AGENTS.md](../AGENTS.md) の「このワークスペースについて」）。

| リポジトリ | 内容 | 主な資料の場所 | このワークスペースで使った場面 |
|---|---|---|---|
| [cdk-apps](https://github.com/turingmotors/cdk-apps) | AWS CDK のモノレポ（tuscenes-prod などのアプリ・原本バケットの守り） | 各 `apps/<名前>/README.md`。原本バケットの監査と Object Lock は `apps/original-bucket-audit/`、共通部は `packages/original-bucket-guard/`、Azure からの同期は `packages/azure-data-sync/`・`apps/denso-nx/` | project:aws-data-protection のほぼすべて |
| [mono-turing-infra](https://github.com/turingmotors/mono-turing-infra) | GCP・AWS・Azure のインフラ（Terragrunt）。GPU クラスタ（HyperPod・gcluster）、management EKS、Datadog、Databricks、Cloudflare、オンプレ、**DENSO のデータの受け口（Azure）** | `AGENTS.md`（領域ごとの `AGENTS.md` の表）、`docs/<領域>/DESIGN.md`、`docs/rules/`、`docs/runbooks/`（約 150 本）。経緯は Jira に書く方針で、リポジトリには今の状態だけ | 下の「mono-turing-infra の読みどころ」 |
| [mono-e2e](https://github.com/turingmotors/mono-e2e) | E2E 自動運転チームの ML モノレポ。backend-api と db-models の正本 | `projects/<名前>/`（api・databricks-terraform・cloudflare-terraform など）、`packages/` | backend-api の書き込み元の精査（aws-data-protection）、mono-e2e-repo-size |
| [identity](https://github.com/turingmotors/identity) | ID 基盤（Okta ほか）の Terraform | `AGENTS.md`、`docs/aws-manual-groups.md` | privileged-access、idp-broker |
| [databricks-jobs](https://github.com/turingmotors/databricks-jobs) | Databricks 上で動くジョブのコード（`denso/`・`calibration-*` など） | `README.md` | 原本バケットを読むジョブの確かめ |
| [jadd_studio3](https://github.com/turingmotors/jadd_studio3) | JADD STUDIO 3（Next.js） | `docs/`（features・guidelines・workstream）。人の対応表は `.mailmap` | GitHub ID から人を引く（`.mailmap`） |
| [fleet-ops](https://github.com/turingmotors/fleet-ops) | 車両運用のアプリ（Next.js + Supabase） | `docs/`（adr・features・guides・plans・runbooks） | Vercel のアカウントの棚卸し（information-resource-inventory） |
| [drivers-app-mono](https://github.com/turingmotors/drivers-app-mono)・[drivers-app3](https://github.com/turingmotors/drivers-app3) | ドライバーズアプリ | `docs/`（mono）、`documents/`（3） | — |
| [gaming-data-collection](https://github.com/turingmotors/gaming-data-collection) | シミュレータを使ったデータ収集 | `docs/`（design・spec・runbook ほか） | project:gaming-data-collection |
| [product-map](https://github.com/ito-yusaku-turing/product-map) | 社内プロダクトの地図（資料と観測データ） | `README.md`、`docs/mlops/`、`snapshots/` | プロダクトの所在を引く |
| [openpilot](https://github.com/turingmotors/openpilot) | openpilot | `docs/` | — |
| [jadd-studio-signage](https://github.com/turingmotors/jadd-studio-signage)・[digital-signage](https://github.com/turingmotors/digital-signage) | 展示用のサイネージ | `docs/` | AWS リソースの棚卸し（digital-signage） |
| [video-streaming-encoder](https://github.com/turingmotors/video-streaming-encoder) | 映像配信用のエンコーダ | `README.md` | — |
| [jadd-cli](https://github.com/turingmotors/jadd-cli) | JADD の CLI（**mono-e2e の `packages/jadd-cli` へ移行済み**） | — | — |

### mono-turing-infra の読みどころ

2026-11-13 に `main` の `eeb30895`（2026-11-12）で読んだ。

| 知りたいこと | 読む先 |
|---|---|
| DENSO（D 社）が Azure に push するデータの受け口の構成（`mlops1data81abaf24`・`dcorp-inbound`・`dcorp-taxi-inbound`） | `platform/azure/README.md`、`docs/azure/DESIGN.md` の「Partner data 受信」 |
| AWS DataSync が Azure から S3 へ運ぶ仕組み（読み取り専用の SP、User Delegation SAS） | `docs/azure/DESIGN.md` の「Cross-cloud reader」。SAS を発行する Lambda は cdk-apps の `packages/azure-data-sync/src/functions/sas-rotator/`（DESIGN.md のリンク先 `apps/denso-nx/lib/azure-data-sync/` は古い。[cdk-apps#1442](https://github.com/turingmotors/cdk-apps/pull/1442) で移った） |
| Azure の原本を消す規則（lifecycle の `delete_after_days`、merge で削除が発火する、DataSync を止めるなら先に外す） | `docs/rules/azure.md` の「原本 (partner inbound) の lifecycle 削除 / 破棄」 |
| 各 container の削除の日数・soft delete の日数 | `platform/azure/mlops-1/foundation/partner-data-bucket/terragrunt.hcl` |
| NX 原本を消した判断と、S3 との全件の突合 | [mono-turing-infra#772](https://github.com/turingmotors/mono-turing-infra/pull/772)（2026-10-13） |
| D 社・DataSync の credential の渡し方と rotation | `docs/runbooks/azure-partner-credentials.md` |
| Azure の blob を誰が操作したか（Log Analytics） | `docs/runbooks/azure-storage-audit.md` |
| taxi データの変換（Azure Batch）と geniac4 | `docs/runbooks/azure-geniac4.md`、`docs/azure/DESIGN.md` の「taxi-batch」 |
| GitHub Actions の OIDC と、その既知のリスク（`repo:*`） | `AGENTS.md` の「CI/CD」 |
| AWS の長寿命のデータバケット（HyperPod 側） | `AGENTS.md` の「主要導線」の `aws-*-data-bucket`（中身はまだ読んでいない） |

## リポジトリ（マウントしていないが、資料から参照しているもの）

| リポジトリ | 参照している場面 |
|---|---|
| [tuscenes-pipeline](https://github.com/turingmotors/tuscenes-pipeline)・[tuscenes-processor](https://github.com/turingmotors/tuscenes-processor)・[tuscenes-infra](https://github.com/turingmotors/tuscenes-infra) | tuscenes の古いスタックの片付け（aws-data-protection の tuscenes-stack-cleanup）、書き込み元の精査、AWS リソースの棚卸し（information-resource-inventory） |
| [ldap](https://github.com/turingmotors/ldap)・[turing-infra-ldap](https://github.com/turingmotors/turing-infra-ldap)・[vm-alarm](https://github.com/turingmotors/vm-alarm) | AWS リソースの棚卸しの、片付けの候補（information-resource-inventory） |

## Notion

### ローカルに原本があるページ（このワークスペースから上げたもの）

直すときは原本を直してから Notion を更新する（[AGENTS.md](../AGENTS.md) の「Notion」）。

| ページ | 原本 |
|---|---|
| [原本バケットの WORM 化: 現在地と計画](https://app.notion.com/p/40fa93b3e6f2811bb51ffaef3cc970e9) | [projects/aws-data-protection/documents/notion-worm-governance-rollout.md](../projects/aws-data-protection/documents/notion-worm-governance-rollout.md) |
| [S3 Object Lock（WORM）の仕組み](https://app.notion.com/p/40fa93b3e6f281999534fcd62c4ad220) | [projects/aws-data-protection/documents/notion-s3-object-lock-spec.md](../projects/aws-data-protection/documents/notion-s3-object-lock-spec.md) |
| [S3 Object Lock（WORM）の整理](https://app.notion.com/p/405a93b3e6f2817084c9d8a90650c21e) | [projects/aws-data-protection/documents/notion-s3-object-lock.md](../projects/aws-data-protection/documents/notion-s3-object-lock.md) |
| [BreakGlass 権限の導入の提案](https://app.notion.com/p/408a93b3e6f281b38292d14cbbed304c) | [projects/aws-data-protection/workstream/s3-data-protection-2/breakglass-proposal.md](../projects/aws-data-protection/workstream/s3-data-protection-2/breakglass-proposal.md) |
| [システム操作の通知と見張りの構想](https://app.notion.com/p/405a93b3e6f28156a7c0fbc3db578957) | [projects/what-did-i-do/documents/notion-what-did-i-do-concept.md](../projects/what-did-i-do/documents/notion-what-did-i-do-concept.md) |
| [Tern iOS アプリに Google ログインを入れる](https://app.notion.com/p/405a93b3e6f281208011c7ccdb174536) | [projects/tern-ios-auth/workstream/tern-backend-api/notion-tern-ios-google-login.md](../projects/tern-ios-auth/workstream/tern-backend-api/notion-tern-ios-google-login.md) |
| [tuscenes-prod の AWS リソースの棚卸し（2026-10）](https://app.notion.com/p/407a93b3e6f281ebb9e1f041231cce43) | [projects/information-resource-inventory/workstream/aws-resource-inventory/notion-tuscenes-prod-inventory.md](../projects/information-resource-inventory/workstream/aws-resource-inventory/notion-tuscenes-prod-inventory.md) |

### ほかの人のページ

| ページ | 内容 | 参照している場面 |
|---|---|---|
| [MLOps 1チームのドキュメント置き場](https://app.notion.com/p/turing-motors/1eda93b3e6f2809183efc88c780883b3) | 資料を上げる既定の場所（データベース） | Notion に上げるとき |
| [各クラスターでデータ共有をするようにする](https://app.notion.com/p/turing-motors/413a93b3e6f2809088c5fcf78b388b53) | 岩政さんの設計 | mono-e2e-repo-size |

## 公式の文書（よく引くもの）

| 文書 | 何を見るとき |
|---|---|
| [S3 Batch Operations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops.html)・[ジョブの状態](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops-job-status.html)・[トラブルシューティング](https://docs.aws.amazon.com/AmazonS3/latest/userguide/troubleshooting-batch-operations.html) | 同時に動かせるジョブ（Active 6 本）、`Ready` の待ち、終わったジョブが 90 日で消えること |
| [S3 Intelligent-Tiering の仕組み](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering-overview.html) | 層が上がる操作の一覧（言い切り）と、上がらない操作の一覧（例示） |
| [Azure Blob の lifecycle](https://learn.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-overview)・[soft delete](https://learn.microsoft.com/en-us/azure/storage/blobs/soft-delete-blob-overview) | mono-turing-infra の Azure の削除の規則を読むとき |
