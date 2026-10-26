# project:tern-ios-auth 目録

内製ナビ Tern の iOS アプリに Google ログインを入れ、API キーや JADD_SERVICE_KEY を使わずに backend-api を呼べるようにする案件。こちらの担当はログインと backend-api を呼ぶ経路の用意まで。フィードバックの機能は三輪さんが作る。関連するリポジトリは navi-ios-app・mono-e2e・cdk-apps。

2026-10-26 に `~/docs/workstream/` から移した。ファイルを追加・移動・削除したら、この目録も同じコミットで更新する（ルールは personal-workspace の `AGENTS.md`「projects/（案件ごとの資料）」）。

関連する project: [project:idp-broker](../idp-broker/README.md)（backend-api・JADD STUDIO・CLI の認証）、[project:m2m-auth](../m2m-auth/README.md)

## workstream/ — 進行中の作業記録

- [workstream/tern-backend-api.md](./workstream/tern-backend-api.md): **Tern iOS アプリの認証と、フィードバックの送信**。要件 R1〜R3、分担、調べた事実、決めたこと・決めること
  - [workstream/tern-backend-api/notion-tern-ios-google-login.md](./workstream/tern-backend-api/notion-tern-ios-google-login.md): 三輪さんと MLOps チーム向けの説明用の資料（Notion に取り込んでレビューしてもらう）
