# project:mono-e2e-repo-size 目録

mono-e2e のリポジトリが急に重くなり、clone や fetch に時間がかかるようになった件の調査と解決。対応するリポジトリは mono-e2e（`/usr/app/mono-e2e`）。

2026-11-11 に作った。ファイルを追加・移動・削除したら、この目録も同じコミットで更新する（ルールは personal-workspace の `AGENTS.md`「projects/（案件ごとの資料）」）。

**2026-11-11 に、本件は岩政さん（MLOps）が引き取った。こちらでは閉じた。**

## documents/ — 分かったこと・結論

- [documents/findings.md](./documents/findings.md): **分かったことと結論**。重さの原因（main の外の作業ブランチ）、ブランチを消せば軽くなるか、デマンド（D1 クラスター間の共有・D2 URL と認証付きの結果の共有）、岩政さんに渡す所見

## workstream/done/ — 完了した作業記録

- [workstream/done/mono-e2e-repo-size.md](./workstream/done/mono-e2e-repo-size.md): **mono-e2e のリポジトリの肥大の解決**（2026-11-04〜11-11、岩政さんに引き継いで完了）。発端の相談とその事実確認、Devin の調査結果、考察、岩政さんの設計の要約と所見、ブランチを消せば軽くなるかの確認、原因の見直し、ヒアリング先、代わりの実装の考察、Miwa さんへのヒアリングとデマンドの整理、workspace を別リポジトリ（LFS 付き）にする案、2026-11-04 の調査の結果、対策の案
