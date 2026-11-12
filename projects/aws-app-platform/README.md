# project:aws-app-platform 目録

これから作る社内の Web アプリを AWS に置くための標準の型（CDK のテンプレート・社の IdP の SSO・CI/CD）を整える案件。いまあるアプリ（jadd_studio3・fleet-ops など）の移設は後回しにする。対応するリポジトリはまだ無い（型の置き場所の候補は `/usr/app/cdk-apps`）。

2026-11-12 に作った。似た案件の [project:databricks-app-hosting](../databricks-app-hosting/README.md)（アプリを Databricks に移せるかの検討）を参考にする。ファイルを追加・移動・削除したら、この目録も同じコミットで更新する（ルールは personal-workspace の `AGENTS.md`「projects/（案件ごとの資料）」）。

## workstream/ — 進行中の作業記録

- [workstream/aws-app-platform.md](./workstream/aws-app-platform.md): **社内の Web アプリを AWS に置く標準の型を整える**。範囲・検討の観点・社内の前例
