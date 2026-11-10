# project:databricks-app-hosting 目録

社内の Web アプリ（jadd_studio3・fleet-ops など。いまは Vercel と Supabase の上にある）を、Databricks（Databricks Apps・Lakebase・Databricks の認証）に移せるかを検討する案件。対応するリポジトリはない（対象は `/usr/app/jadd_studio3`・`/usr/app/fleet-ops` など）。

2026-11-10 に作った。Vercel の MFA とデプロイの経路の作業（[information-resource-inventory/workstream/vercel-accounts.md](../information-resource-inventory/workstream/vercel-accounts.md)）から派生した。ファイルを追加・移動・削除したら、この目録も同じコミットで更新する（ルールは personal-workspace の `AGENTS.md`「projects/（案件ごとの資料）」）。

## workstream/ — 進行中の作業記録

- [workstream/databricks-app-hosting.md](./workstream/databricks-app-hosting.md): **アプリを Databricks に移せるかの検討**。公式ドキュメントで分かったこと（2026-11-10）、壁になりそうな点、確かめること

## documents/ — 調べたこと・決めたこと

- [documents/pricing-estimate.md](./documents/pricing-estimate.md): **Databricks の料金体系と見積もり**（2026-11-10、定価、オレゴン）。いまの負荷から jadd_studio3・fleet-ops の月額を出し、Vercel に残す場合と比べた。社のプランと契約の単価の調べ方も
