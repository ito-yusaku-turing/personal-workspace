# プロジェクト一覧

このワークスペースは複数のプロジェクトを管理しています。
プロジェクトごとに`CLAUDE.md`が存在しています。

- `JADD_STUDIO3`: JADD STUDIO
    - `/usr/app/jadd_studio3/CLAUDE.md`
- `DRIVERS_APP`: ドライバーズアプリ
    - `/usr/app/drivers-app3/CLAUDE.md`

# Git運用ルール

この環境にはpush用の認証情報が設定されていないため、エージェントから`git push`はできません。

- エージェントが行う書き込み系のgit操作は **`git commit` まで** とする。
- `git push` は実行しない。commit後はユーザーにpushを行うよう案内すること。
