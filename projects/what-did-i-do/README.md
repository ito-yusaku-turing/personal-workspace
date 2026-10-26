# project:what-did-i-do 目録

自分の主体でシステムに行った重要な操作を、定期的に Slack で知らせる仕組み（今日なにしたかわかる君）と、人でない主体の異常を LLM で見張る仕組み（大事なもの見張る君）の構想。原本バケットの削除の必ずの通知（今日なに消したかわかる君）は project:aws-data-protection で作っており、ここから参照する。作業先は主に cdk-apps（`/usr/app/cdk-apps`）。

2026-10-26 に作った。ファイルを追加・移動・削除したら、この目録も同じコミットで更新する（ルールは personal-workspace の `AGENTS.md`「projects/（案件ごとの資料）」）。

## documents/ — 資料

- [documents/notion-what-did-i-do-concept.md](./documents/notion-what-did-i-do-concept.md): **システム操作の通知と見張りの構想**。チーム共有用（Notion に上げる）。4 つの部品・主体の振り分け・LLM の使い方と安全・Bedrock の費用の見積もり（2026-10-26）

## 関連する資料（ほかの project）

- [../aws-data-protection/workstream/s3-data-protection-2/stage2-hourly-report.md](../aws-data-protection/workstream/s3-data-protection-2/stage2-hourly-report.md): 今日なに消したかわかる君（原本バケットの削除の記録と報告）の設計と、カナリアでの確認の結果
