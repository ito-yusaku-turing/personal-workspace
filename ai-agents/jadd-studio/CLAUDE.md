# プロジェクト一覧

このワークスペースは複数のプロジェクトを管理しています。
プロジェクトごとに`CLAUDE.md`が存在しています。

- `JADD_STUDIO3`: JADD STUDIO
    - `/usr/app/jadd_studio3/CLAUDE.md`
- `DRIVERS_APP`: ドライバーズアプリ
    - `/usr/app/drivers-app3/CLAUDE.md`
- `DIGITAL_SIGNAGE`: デジタルサイネージ
    - `/usr/app/digital-signage/CLAUDE.md`

# Git運用ルール

この環境にはpush用の認証情報が設定されていないため、エージェントから`git push`はできません。

- エージェントが行う書き込み系のgit操作は **`git commit` まで** とする。
- `git push` は実行しない。commit後はユーザーにpushを行うよう案内すること。

## ブランチ運用

各プロジェクトは Vercel 等に**デプロイ済み**のため、`main` への直接コミットは禁止する。
必ず作業ブランチを切ってコミットし、PR 経由で `main` に取り込む。

- **`main` に直接コミットしない**。作業開始時に `main` から作業ブランチを作成する。
- **ブランチ命名は「種別プレフィックス + 内容（kebab-case）」**とする。
    - `feature/` 新機能（例: `feature/slack-daily-summary`）
    - `fix/` バグ修正（例: `fix/cron-auth`）
    - `docs/` ドキュメントのみ（例: `docs/deployment-notes`）
    - `chore/` 設定・依存・雑務
- 取り込みは **PR 経由**とする。エージェントは作業ブランチへ commit までを行い、
  commit 後にユーザーへ「ブランチを push → GitHub で PR 作成 → レビュー後 `main` へマージ」を案内する。
- エージェントは push も PR 作成もできないため、PR の作成・マージはユーザーが行う。
