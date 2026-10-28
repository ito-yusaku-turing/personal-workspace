# project:information-resource-inventory 目録

情報資源の棚卸し。持っている情報資源（クラウドのリソースなど）を洗い出し、使われていないもの・安全上のリスクがあるもの・変更しようとしたときに競合しかねないものを見つけて、掃除の候補にする案件。最初の対象は AWS アカウント tuscenes-prod（767397804933）。

2026-10-28 に作った。ファイルを追加・移動・削除したら、この目録も同じコミットで更新する（ルールは personal-workspace の `AGENTS.md`「projects/（案件ごとの資料）」）。

AWS から取った一次情報は、その時点の写しなので git では管理せず、`~/aws/tuscenes-prod/` に置く。この project には、分析の結果と決めたことを置く。

## workstream/ — 進行中の作業記録

- [workstream/aws-resource-inventory.md](./workstream/aws-resource-inventory.md): **AWS リソースの棚卸し**。tuscenes-prod の us-west-2・ap-northeast-1 を対象に、セキュリティを重視して掃除の候補を作る
  - [workstream/aws-resource-inventory/cleanup-candidates.md](./workstream/aws-resource-inventory/cleanup-candidates.md): **掃除の候補のリスト**（伊藤の判断用）。安全上のリスク・競合しかねないもの・使われていないもの（2026-10-28、優先度 B とグローバルなサービスまで）
  - [workstream/aws-resource-inventory/notion-tuscenes-prod-inventory.md](./workstream/aws-resource-inventory/notion-tuscenes-prod-inventory.md): チーム共有用の記事「tuscenes-prod の AWS リソースの棚卸し（2026-10）」（[Notion のページ](https://app.notion.com/p/407a93b3e6f281ebb9e1f041231cce43)の原本）
  - [workstream/aws-resource-inventory/stage0-overview.md](./workstream/aws-resource-inventory/stage0-overview.md): 段階 0 の結果。リージョンごとの費用と形跡、種別ごとの件数（2026-10-28）
  - [workstream/aws-resource-inventory/collect/](./workstream/aws-resource-inventory/collect/README.md): 一次情報を取る道具（保存・ログ・伏せ字）と、段階 1 の取得のスクリプト
  - [workstream/aws-resource-inventory/analyze/](./workstream/aws-resource-inventory/analyze/README.md): 一次情報を集計するスクリプト（IAM・スタック・競合の判定）

## 関連する資料（ほかの project）

- [../aws-data-protection/workstream/tuscenes-stack-cleanup.md](../aws-data-protection/workstream/tuscenes-stack-cleanup.md): 古いスタック tuscenes の片付け。調べた結果を棚卸しで再利用する
- [../aws-data-protection/workstream/s3-data-protection-2.md](../aws-data-protection/workstream/s3-data-protection-2.md): 原本バケットの守りの第二弾。競合の手本（眠っていた EventBridge のルール、通知の丸ごと上書き）は、この資料の TODO 23・25
