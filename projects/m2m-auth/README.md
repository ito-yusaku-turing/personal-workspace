# project:m2m-auth 目録

車載装置や CI 用マシンが backend-api などを呼ぶときの認証（M2M）の手法を確立する案件。無期限のサービスキーを複数の機体で使い回している状態をやめ、1 台 1 身元・短命のトークンの形を目指す。関連するリポジトリは mono-e2e（backend-api）・cdk-apps・openpilot。

2026-10-26 に `~/docs/workstream/` から移した。ファイルを追加・移動・削除したら、この目録も同じコミットで更新する（ルールは personal-workspace の `AGENTS.md`「projects/（案件ごとの資料）」）。

関連する project: [project:idp-broker](../idp-broker/README.md)（人の認証。退職の同期・ロールの持ち場・BFF 撤廃後の入口が共通の論点）

## workstream/ — 進行中の作業記録

- [workstream/m2m-auth.md](./workstream/m2m-auth.md): **M2M 認証の手法の確立（車載装置・CI 用マシン）**。一般的なやり方の整理と、関係者（岩政さん・安本さんほか）の動きの把握。改善案は歩調を合わせてから詰める
