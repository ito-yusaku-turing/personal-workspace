# 開発環境（Docker）

Personal Workspace は、**コーディングエージェントを動かすための汎用の作業場**を Docker Compose で提供する。定義一式はリポジトリ直下の `docker/` にある。特定のプロジェクトのアプリは起動しない。各プロジェクトの開発サーバーは、それぞれのリポジトリ側の docker で起動する（例: jadd_studio3 の `docker/bin/up.sh`）。

この環境は jadd_studio3 の `docker/` から、プロジェクトに依存しない部分を抜き出して作った（共有 HOME の `~/agent-devbox/` テンプレートが元）。jadd_studio3 側を直したら、こちらにも取り込むか検討すること。

## 前提

- **Docker（Compose v2.20 以上）**。`include:` を使うため、2.20 未満では動かない。
- ホストに入れるものはほかにない。Node.js も gh もクラウド CLI も、すべてコンテナに同梱している。

## クイックスタート

```bash
docker/bin/setup.sh     # 初期セットアップ（対話式。何度実行しても安全）
docker/bin/claude.sh    # Claude Code を devbox 内で起動する
```

`setup.sh` は次の処理を行う。既にあるものは壊さない。

1. `docker/.env` を生成する（コンテナ HOME を対話で確認する）
2. コンテナ HOME を作成する
3. 個人設定（エージェント個人プリファレンス・セットアップ宣言）の雛形を置く
4. `docker/config/repos.conf` から、追加リポジトリのマウント定義を生成する
5. devbox イメージをビルドする
6. `doctor.sh` で状態を表示する

GitHub の認証（git 署名 / SSH 鍵 / gh）はコンテナの中で行うため、別のスクリプトに分けてある。コンテナ HOME を jadd_studio3 と共有している場合は、すでに済んでいる。

```bash
docker/bin/setup/github.sh      # 状態と次の一手を表示する（all を付けると順に案内する）
```

規約とその理由は [`github-setup.md`](github-setup.md) にある。

## jadd_studio3 の devbox との関係

**併用する**前提で設計している。どちらから入っても同じ道具・同じログイン状態・同じパスで作業できるように、次の3点を揃えている。

| 揃えるもの | 内容 |
| --- | --- |
| コンテナ HOME | 既定で `~/.jadd-studio/home` を共有する。claude のログイン・memory・ssh 鍵・gh の認証を作り直さずに済む。memory は作業ディレクトリごとに分かれるので混ざらない |
| マウント先 | どちらも `/usr/app/<名前>` に固定している。personal-workspace は、jadd_studio3 側の repos.conf からマウントしても `/usr/app/personal-workspace` になる |
| 同梱ツール | psql / aws / gcloud / databricks / uv。jadd_studio3 の devbox と同じ構成 |

イメージは別にしている（`personal-workspace-devbox` と `jadd-studio3-devbox`）。作業ディレクトリと、エージェントが最初に読む指示（`AGENTS.md`）が違う。

個人設定（エージェント個人プリファレンス・セットアップ宣言）も分けている。STUDIO 用は `~/.jadd-studio/`、こちらは `~/.personal-workspace/` にある。STUDIO のチーム共有ルールとは前提が違うため。

## サービス構成

| サービス | 役割 | 起動条件 |
| --- | --- | --- |
| `devbox` | 開発シェル / コーディングエージェント | `run` 専用（profile `cli`）。使い捨てのコンテナとして起動する |

常駐するサービスは持たない。増やすときは、`docker/services/` にファイルを1つ追加し、`docker/compose.yml` の `include:` に足す。

Node.js のバージョンは、リポジトリ直下の `.nvmrc` だけで決まる。`docker/bin/lib/common.sh` がこれを読み、ビルド引数として渡す。`docker/.env` に書いても無視され、`doctor.sh` が警告する。jadd_studio3 の `.nvmrc` に合わせておくとよい。

## 設定ファイル

| ファイル | 内容 | git |
| --- | --- | --- |
| `docker/config/project.conf` | ワークスペースの設定（名前・マウント先・個人設定の置き場・同梱ツール） | 管理下 |
| `docker/.env` | このマシン固有の設定（コンテナ HOME 等） | 管理外（雛形は `config/env.example`） |
| `docker/config/repos.conf` | devbox にマウントする他リポジトリの一覧 | 管理外（雛形は `config/repos.example.conf`） |
| `docker/compose.repos.yml` | `repos.conf` から生成されるマウント定義 | 管理外（生成物） |

`project.conf` の `CONTAINER_REPO_DIR` と `DEVBOX_WITH_*` はイメージに焼き込まれる。**変更したら `docker/bin/setup/image.sh` で再ビルドする。**

### 環境変数の優先順位

`load_env()` は、`project.conf` → `docker/.env` の順にシェルへ読み込んでから compose に渡す。そのため、**素の `docker compose` とは優先順位が逆になる**。強い順に並べると次のとおり。

1. スクリプトが計算する値（`HOST_UID` / `HOST_GID` / `CONTAINER_USER` / `NODE_VERSION`）
2. `docker/.env`
3. `docker/config/project.conf`
4. シェルの環境変数（両ファイルのどちらにも書かれていないキーだけが通る。例: `AWS_PROFILE`）

ファイルに書いたキーは、シェルから一時的に上書きできない。

### `docker/config/repos.conf`（参照する他リポジトリ）

```
# <名前>  <ホスト側の絶対パス>
jadd_studio3   /home/you/projects/jadd-studio/jadd_studio3
```

- **コンテナ側のマウント先は `/usr/app/<名前>` に固定**で、指定はできない。エージェントが常に同じパスで参照できるようにするため。
- ホストにないパスは、警告を出して無視する。
- 編集したら `docker/bin/setup.sh --refresh` で反映する。

## 実行ユーザーとホームディレクトリ

コンテナは root で起動する。entrypoint（`docker/images/devbox/docker-entrypoint.sh`）が**ホストと同じ UID/GID に降格**してから、本来のコマンドを実行する。こうすると、bind mount に書いたファイルの所有者がホスト側と一致する。

降格の前に、passwd エントリのホームを `/usr/home` に揃えている。`ssh` は `$HOME` ではなく `getpwuid()` の `pw_dir` を見るため、揃えないと鍵が見つからない。`doctor.sh` は、この2つが一致しているかを確認する。

> ホストの `/etc/passwd` はマウントしない（旧 personal-workspace の方式）。macOS では成立せず、`pw_dir` がコンテナ内に存在しないパスになるため。
>
> `docker compose exec` で入ると root になる。`docker/bin/` のスクリプトはすべて `run` を使うので、通常の使い方では起きない。

## クレデンシャル

**すべて任意**。置き場所は `USER_HOME_DIR` の配下にまとめてあり、コンテナからは `$HOME`（= `/usr/home`）に見える。**イメージには焼き込まない。**

| 用途 | 置き場（`$USER_HOME_DIR/`） |
| --- | --- |
| GitHub | `.config/gh`、`.gitconfig`、`.ssh` |
| AWS / Databricks / Google Cloud | `.aws`、`.databrickscfg`、`.config/gcloud` |
| Claude Code / Codex | `.claude` / `.codex`（バイナリは `.local`） |

### 「使わない」の宣言

「まだ設定していない」と「使わないと決めた」を区別するために、**「使わない」という宣言だけ**を別ファイルに書く。

- パス: `$USER_HOME_DIR/.personal-workspace/setup-state.conf`
- 編集: `docker/bin/setup/state.sh skip <項目> [理由]` / `unskip <項目>` / `list`

設定済みかどうかは、このファイルに書かない。毎回その場で調べる。エージェントは次のコマンドで状態を取得する。

```bash
docker/bin/doctor.sh --porcelain              # ホストから
docker/container-bin/doctor.sh --porcelain    # コンテナ内から
```

状態は `ok` / `missing` / `declined` / `conflict` / `error` のいずれか。`declined` は「使わないと決めた」なので、催促せずに迂回する。

### エージェント個人プリファレンス

- パス: `$USER_HOME_DIR/.personal-workspace/agent-preferences.md`
- 書き方: [`agent-preferences.md`](agent-preferences.md)

## スクリプトの置き場所

実行する場所でディレクトリを分けている。取り違えると、警告を出して終了する。判定には、イメージに焼き込んだ目印 `/etc/devbox.conf` を使う。

| ディレクトリ | 実行場所 | 中身 |
| --- | --- | --- |
| `docker/bin/` | ホスト | 日常的に使う操作と、入口の `setup.sh` |
| `docker/bin/setup/` | ホスト | 初回セットアップと保守のときだけ使う操作 |
| `docker/container-bin/` | devbox 内 | 実体。`docker/bin/` の同名スクリプトが `docker compose run` 経由で呼ぶ |

> jadd_studio3 の devbox の目印は `/etc/jadd-devbox` で、こちらとは別のもの。jadd_studio3 の devbox の中から `docker/container-bin/` を実行すると、「コンテナ外です」として止まる。jadd_studio3 の devbox から使うのは、ファイルの閲覧と編集だけにする。

## よく使う操作

| コマンド | 用途 |
| --- | --- |
| `docker/bin/claude.sh` | Claude Code を起動する（未導入なら導入する） |
| `docker/bin/remote-claude.sh` | Claude Code を Remote Control モードで起動する（セッション名は `pw-MMDD`） |
| `docker/bin/codex.sh` | Codex CLI を起動する |
| `docker/bin/shell.sh [cmd...]` | 開発シェルに入る。コマンドを直接実行することもできる |
| `docker/bin/doctor.sh` | 状態を診断する（`--porcelain` を付けると機械可読） |

| コマンド（初回・保守） | 用途 |
| --- | --- |
| `docker/bin/setup.sh [--refresh]` | 初期セットアップ（`--refresh` を付けると repos.conf の変更だけを反映する） |
| `docker/bin/setup/github.sh` | GitHub 認証を設定・検証する |
| `docker/bin/setup/config.sh` | 個人設定ファイルの雛形を置く（既存のものは上書きしない） |
| `docker/bin/setup/state.sh` | 使わない項目を宣言する |
| `docker/bin/setup/image.sh [--no-cache]` | イメージを再ビルドする |

## コーディングエージェント

Claude Code / Codex は **devbox コンテナの中でだけ動かす**。

- **Claude Code はネイティブ版だけを使う**。未導入なら、`claude.sh` の初回実行時に `https://claude.ai/install.sh` から導入する。導入先は `$HOME/.local` なので、コンテナを作り直しても消えない。
- **更新**: 起動するたびに、前回の確認（`$HOME/.claude-last-updated`）から **04:00（`project.conf` の `TZ`）を跨いだか**を見る。跨いでいれば `claude update` を実行してから起動する。記録ファイルは jadd_studio3 と共有なので、どちらかで1日1回更新すれば済む。
- **権限**: `--dangerously-skip-permissions` を既定で付ける。マウントしているのは、このリポジトリ・`USER_HOME_DIR`・repos.conf に登録したリポジトリだけなので、この既定で運用している。外すときは、権限系のオプションを明示するか、`DEVBOX_CLAUDE_SKIP_PERMISSIONS=0` を設定する。
- **Remote Control**: セッション名を変えたいときは `DEVBOX_RC_SESSION=pw-hotfix docker/bin/remote-claude.sh` のように指定する。
- **Notion（MCP）**: personal-workspace で起動したセッションからだけ操作する。Notion 公式の MCP サーバーを Claude Code の **local スコープ**で登録している（設定は `$HOME/.claude.json` の `/usr/app/personal-workspace` の欄。git 管理外）。
  - 登録: `cd /usr/app/personal-workspace && claude mcp add --scope local --transport http notion https://mcp.notion.com/mcp`。認証は personal-workspace のセッションの `/mcp` から OAuth で行う。
  - claude.ai のコネクタには Notion を足さない。コネクタはアカウント全体に効き、ほかのリポジトリや claude.ai の会話からも操作できてしまう。
  - 効く範囲は「起動した場所」で決まる。personal-workspace で起動したセッションなら、ほかのリポジトリの作業中でも使える。jadd_studio3 の devbox でも、`/usr/app/personal-workspace` で起動すれば効く（HOME を共有しているため）。
  - 認証のトークンは HOME に保存される。Notion 公式の MCP は本人の権限で動き、触れるページを Notion 側で絞れない（本人が見られるページはすべて読める）。
  - そのため、使えるツールを Claude Code 側で絞っている（`.claude/settings.json`）。`--dangerously-skip-permissions` で起動しても効く。
    - PreToolUse フック `.claude/hooks/notion-guard.py` が、許可リスト（`notion-fetch`・`notion-create-pages`・`notion-update-page`・`notion-get-comments`）以外の Notion のツールを止める。Notion が後から足したツールも止まる。フックが失敗したときも止める（`onFailure: block`）。
    - 許可したツールでも、範囲外の使い方は止める。Notion のメモリの読み書き、スキル化、テンプレートの適用、検証済みの設定、子ページを消す更新（`allow_deleting_content`）が対象。
    - 書き込み（`notion-create-pages`・`notion-update-page`）は、フックが毎回確認（`permissionDecision: ask`）を返す。`--dangerously-skip-permissions` で起動していても確認のダイアログが出ることを、2026-10-26 に確かめた。
    - フックが読み込まれなかったときの備えとして、`permissions.deny` にも削除と移動のツールを並べている。
    - 許可する操作を変えるときは、`notion-guard.py` の `ALLOWED` を直す。運用のルールは `AGENTS.md` の「Notion」。
  - 外すとき: `cd /usr/app/personal-workspace && claude mcp remove notion -s local`

## 注意点・トラブルシュート

- **「devbox イメージが古い形式です」と言われたら、`docker/bin/setup/image.sh` を実行する。** entrypoint・`/etc/devbox.conf`・Node.js のバージョンを変えたときは、Dockerfile の `LABEL devbox.schema` と `common.sh` の `DEVBOX_IMAGE_SCHEMA` を一緒に +1 する。
- **`docker compose` を直接実行しない。** UID/GID・`project.conf` の値・`compose.repos.yml` は、`docker/bin/` のスクリプトが渡している。
- **`repos.conf` を編集したら**、`docker/bin/setup.sh --refresh` を実行する。
