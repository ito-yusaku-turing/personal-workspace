# docker/ — devbox（エージェント用の作業環境）

Personal Workspace の作業環境（開発シェルとコーディングエージェント）を Docker Compose で提供する。説明の正本は [`docs/development-environment.md`](../docs/development-environment.md)。ここには最短の手順だけを置く。

```bash
docker/bin/setup.sh            # 初期セットアップ（対話式。何度実行しても安全）
docker/bin/claude.sh           # Claude Code を起動する（1日1回 自動更新 / skip-permissions が既定）
docker/bin/remote-claude.sh    # Remote Control モードで起動する（セッション名 pw-MMDD）
docker/bin/shell.sh            # 開発シェルに入る
docker/bin/doctor.sh           # 状態を診断する（--porcelain を付けると機械可読）
docker/bin/setup.sh --refresh  # config/repos.conf の変更を反映する
docker/bin/setup/image.sh      # イメージを再ビルドする（「古い形式です」と言われたとき）
```

| ディレクトリ | どこから実行するか |
| --- | --- |
| `docker/bin/`、`docker/bin/setup/` | **ホスト**から |
| `docker/container-bin/` | **devbox コンテナの中**から（`docker/bin/` の同名スクリプトが内部で呼ぶ） |
