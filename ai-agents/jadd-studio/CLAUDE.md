# プロジェクト一覧

このワークスペースは複数のプロジェクトを管理しています。
プロジェクトごとに`CLAUDE.md`が存在しています。

- `JADD_STUDIO3`: JADD STUDIO
    - `/usr/app/jadd_studio3/CLAUDE.md`
- `DRIVERS_APP`: ドライバーズアプリ
    - `/usr/app/drivers-app3/CLAUDE.md`
- `DIGITAL_SIGNAGE`: デジタルサイネージ
    - `/usr/app/digital-signage/CLAUDE.md`

# Git運用ルール（個人方針）

このリポジトリ（personal-workspace）は完全に個人用であり、コーディングエージェントが従う**個人的な git 運用方針**をここに集約する。本方針は私が関わる全リポジトリ（`JADD_STUDIO3` / `DRIVERS_APP` / `DIGITAL_SIGNAGE`）での作業に適用する。

## コミット・プッシュ

- **作業完了後、commit と push はデフォルトで行わない。**
- **`git commit` はユーザーから明確な指示があった場合のみ**行う。指示が無ければ変更を作業ツリーに残し、確認を仰ぐ。
- この環境には push 用の認証情報が無いため、**`git push` は実行しない**。push・GitHub での PR 作成・マージはユーザーが行う。

## ブランチ運用

各プロジェクトは Vercel 等に**デプロイ済み**のため、`main` の安全性を守る。

- **`main` に直接コミットしない**。`main` から作業ブランチを切り、PR 経由で取り込む。
- **ファイル改変を伴う作業を始める前に、必ずブランチの状態を確認する**。`main`、または着手する案件に無関係そうなブランチ名の場合は、そのまま作業せず、作業ブランチを切ることを提案する。
- **ブランチ命名は「種別プレフィックス + 内容（kebab-case）」**とする（`feature/` `fix/` `docs/` `chore/`）。

## プロジェクト個別の共有ルール

- `JADD_STUDIO3` は複数開発者で共同メンテされるため、リポジトリ側のチーム共有ルール（`/usr/app/jadd_studio3/CLAUDE.md` および `docs/guidelines/git-workflow.md`）にも従う。本個人方針はそれに上乗せする。
- `DRIVERS_APP` / `DIGITAL_SIGNAGE` は現時点では単独開発のため、本個人方針に従う。
