# project:aws-app-platform 目録

これから作る社内の Web アプリを AWS に置くための標準の型（CDK のテンプレート・社の IdP の SSO・CI/CD）を整える案件。Vercel と Supabase を置き換え、全部の部品を AWS に入れてセキュリティを固める。使えなくなる機能の代わりも検討する。いまあるアプリ（jadd_studio3・fleet-ops など）の移設は後回しにする。対応するリポジトリはまだ無い（型の置き場所の候補は `/usr/app/cdk-apps`）。

2026-11-12 に作った。似た案件の [project:databricks-app-hosting](../databricks-app-hosting/README.md)（アプリを Databricks に移せるかの検討）を参考にする。ファイルを追加・移動・削除したら、この目録も同じコミットで更新する（ルールは personal-workspace の `AGENTS.md`「projects/（案件ごとの資料）」）。

## workstream/ — 進行中の作業記録

- [workstream/aws-app-platform.md](./workstream/aws-app-platform.md): **社内の Web アプリを AWS に置く標準の型を整える**。背景と目的、型に求める機能（必須・できれば欲しい）、使えなくなる機能と代わりの候補、検討の観点、社内の前例

## documents/ — 調べたこと・決めたこと

- [documents/aws-building-blocks.md](./documents/aws-building-blocks.md): **型の部品の下調べと構成の第一案**（2026-11-12）。Next.js のホスティング、ALB の OIDC 認証、自前の PostgREST、Aurora のバックアップと時点への復元、clone でのブランチ、PR ごとのプレビュー
- [documents/jadd-studio3-db-dependencies.md](./documents/jadd-studio3-db-dependencies.md): **JADD STUDIO の DB が Supabase の外で動くか**（2026-11-12）。関数 45 種類・RPC 27 本の Supabase への依存、PostgREST の使い方
