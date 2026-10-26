# GitHub 認証のセットアップ（初回のみ）

Personal Workspace で GitHub を使えるようにするための初回セットアップ。**開発者ごとに一度だけ**行う。以降の commit / push / PR 作成はコーディングエージェントが代行する（運用ルールは [`git-workflow.md`](git-workflow.md)）。

手順は `docker/bin/setup/github.sh` が持っている。**このドキュメントは「何を・なぜそう決めたか」と、スクリプトが担えない部分だけを書く**。実行するコマンドの正本はスクリプト側にあり、ここに写しは置かない（同じ手順が2箇所にあると必ず食い違う）。

```bash
docker/bin/setup/github.sh          # いまの状態と次の一手を表示する
docker/bin/setup/github.sh all      # 未了の項目を順に案内する
docker/bin/setup/github.sh --help   # サブコマンドの一覧
```

何度実行しても安全で、既にあるものは壊さない。認証情報はすべてホストの `$USER_HOME_DIR` 配下に残るため、**コンテナを作り直しても再ビルドしても消えない**。

> devbox の中から直接使う場合は `docker/container-bin/setup/github.sh`（同じ引数）。ホスト用とコンテナ用でディレクトリが分かれており、取り違えると警告して止まる。

## セットアップする3点

用途が異なる3つを設定する。**どれか1つでは足りない**。

| 項目名 | 設定するもの | 何に使うか | 保存先（コンテナ内 / = ホストの `$USER_HOME_DIR/`） |
|---|---|---|---|
| `git-identity` | git の名前・メール | コミットの著者情報 | `~/.gitconfig` |
| `ssh-key` | SSH 鍵 | `git push` / `git fetch`（remote が `git@github.com:...` のため） | `~/.ssh/` |
| `gh-auth` | gh のトークン | `gh pr create` 等の GitHub API 操作 | `~/.config/gh/hosts.yml` |

**3点すべて「使わない」を選べる**。コードを読むだけ・レビュー専用の使い方があるため。宣言すると催促されなくなり、エージェントもその操作を試みずに迂回する。

```bash
docker/bin/setup/state.sh skip gh-auth ブラウザで PR を作るので不要
docker/bin/setup/state.sh list        # 項目と実効状態の一覧
```

使えなくなるものは次のとおり。

| 宣言した項目 | 使えなくなるもの |
|---|---|
| `git-identity` | commit |
| `ssh-key` | push / fetch |
| `gh-auth` | PR の作成・一覧 |

## 決めてあること（規約）と、その理由

### git の名前・メール

GitHub アカウントのメールアドレスを使い、**グローバル（`~/.gitconfig`）に入れる**。マウントした他リポジトリでも同じ著者情報を効かせるため。

リポジトリ側の `.git/config` に `user.*` があるとそちらが優先される。意図せず別人名義になる事故を防ぐため、スクリプトはグローバルと食い違っていたら警告する。

### SSH 鍵

**devbox 専用の鍵を1本持つ**方針にした。ホストの鍵を共用すると、ホストの主鍵をエージェントが読める場所に置くことになり、revoke したときホスト側も止まる。環境ごとに分けておけば devbox の鍵だけを失効できる。

| 項目 | 規約 | 理由 |
|---|---|---|
| 鍵種別 | `ed25519` | GitHub の推奨。RSA は非推奨方向 |
| ファイル名 | 既定名 `id_ed25519` | `~/.ssh/config` の `IdentityFile` 指定が不要になる。`$USER_HOME_DIR` はこの環境専用の HOME なので用途は自明 |
| コメント | `<メール> <プロジェクト名> devbox` | 既定のコンテナホスト名（`node@<コンテナ ID>`）は再ビルドで変わり、識別の役に立たない |
| GitHub 上の title | `<プロジェクト名> devbox (<マシン識別子>)` | 複数のマシンで setup したときに鍵一覧で区別するため。**コンテナからホストのマシン名は取得できない**ので、ここは人間が入れる |
| パスフレーズ | **なし** | エージェントが許可を得たあとそのまま push できるようにする。パスフレーズ付きはコンテナに入るたび `ssh-add` が必要で、この運用と相反する。緩和策は「devbox 専用鍵にして単独で revoke できる状態を保つ」こと |

既に別の鍵がある場合、スクリプトは**勝手に動かさない**（動いている鍵を壊しうる）。使っていない鍵は `~/.ssh/retired/` へ移せば無効化できる（`ssh` はサブディレクトリを走査しない）。`--retire-existing` を付けると退避まで行う。削除はしない。

### gh のトークン

**`admin:public_key` を持たせない。** 付与されるスコープは `repo` / `read:org` / `gist` の3つだけにする。

SSH 鍵を追加できるトークンは、そのトークンを revoke しても、攻撃者や暴走したエージェントが自分の鍵を登録して居座る余地を残す。「鍵を1本読める」と「新しい鍵を無限に生やせる」は重さが違う。devbox はエージェントが動く場所なので、この権限は置かない。

その帰結として、**公開鍵の登録に `gh ssh-key add` は使わない**（このコマンドは `admin:public_key` を要求する）。登録はブラウザで人間が行う。

- 副作用として **SSH 鍵と gh トークンの設定順序が自由**になる（`gh ssh-key add` を使うなら「gh 認証 → 鍵登録」の順しかない）
- 検証は `ssh -T git@github.com` で行う。スコープを一切必要とせず、しかも「実際に認証が通るか」を直接試せる

> さらに絞りたい場合は Personal Access Token を使う。デバイスコード方式では `gist` を含む最小スコープが下限で、それ以下にはできない（`gh auth login --scopes` は *追加* しかできない）。classic PAT なら `repo` のみ、fine-grained PAT ならリポジトリ単位＋有効期限まで絞れるが、発行・失効・更新を自分で管理することになる。

## 人間しかできない工程が2つある

スクリプトで包んでも自動化できない。エージェントに任せることもできない。

| 工程 | なぜ人間か |
|---|---|
| **公開鍵を GitHub に登録** | ブラウザでの操作。`gh ssh-key add` を使わない方針のため（上記） |
| **`gh auth login`** | デバイスコードの入力に TTY が必要 |

`docker/bin/setup/github.sh ssh-key` は、貼るべき **title と公開鍵、登録ページの URL** を出力して終わる。あとはブラウザで貼るだけ。

`gh auth login` は、あなたが手で実行したときだけスクリプトが実際に起動する（エージェント経由など TTY が無いときは手順を表示する）。進行はこうなる。

1. 8桁のワンタイムコードが表示される
2. Enter を押す。**コンテナにブラウザは無いので起動失敗のメッセージが出るが正常**。URL は表示される
3. **ホスト側のブラウザ**で <https://github.com/login/device> を開き、コードを入力して認可する
4. `✓ Logged in as <username>` が出れば成功

> 途中でスコープの追加を促されても応じないこと。鍵の登録はブラウザで行う方針のため不要。

## 検証

```bash
docker/bin/setup/github.sh verify
```

次の5点を確認する。すべて `✔` になれば完了。

- `ssh` が `Hi <username>! You've successfully authenticated` を返す
- `git ls-remote origin` が通る（remote は SSH なので実際に同じ経路を使う）
- `gh` が認証済み
- **トークンが `admin:public_key` を持っていない**（方針どおりであることの実測）
- `gh` の API 疎通（PR 一覧が引ける）

環境全体の状態は `docker/bin/doctor.sh`。エージェント向けの機械可読出力は `docker/bin/doctor.sh --porcelain`。

## 実測メモ

- **トークンの保存先**: gh は OS のクレデンシャルストアに保存しようとするが、コンテナにはそれが無い。gh はこれを自動で検出して `~/.config/gh/hosts.yml` に平文で書く。**`--insecure-storage` を明示する必要はない。** `$USER_HOME_DIR` はホスト側の個人ディレクトリであり、リポジトリにも他人にも共有されないため、この挙動でよい
- **組織の SAML SSO**: 追加のトークン認可を求められずに組織リポジトリの API が通る場合が多い。求められる場合はブラウザの指示に従う
- **SSH コミット署名**を将来採用する場合、`admin:ssh_signing_key` という**別のスコープ**が必要になる。これも「持たせない」方針の対象として別途判断すること

## トラブルシュート

| 症状 | 原因と対処 |
|---|---|
| `git push` が `Permission denied (publickey)` | 公開鍵が GitHub に未登録、または鍵のパーミッションが緩い。`setup/github.sh verify` で切り分け、`setup/github.sh ssh-key` で貼るべき鍵を再表示できる |
| `ssh` が鍵を見つけない | `doctor.sh` の「HOME / pw_dir」が不一致。イメージが古い可能性があるので `docker/bin/setup/image.sh`（[経緯](development-environment.md#実行ユーザーとホームディレクトリ)） |
| `gh` が毎回未認証になる | `docker compose exec` で入って root（`$HOME=/root`）になっている。`docker/bin/shell.sh` を使う |
| コミットの著者が別人になる | リポジトリ側の `.git/config` の `user.*` が優先されている。`setup/github.sh git-identity` が警告する |
| キーリング関連で `gh auth login` が失敗する | `--insecure-storage` を付けて明示的に平文保存にする |
| 設定が消えた | `docker/.env` の `USER_HOME_DIR` を変更していないか確認する。認証情報はすべてこのディレクトリ配下にある |
| 未設定の項目を毎回催促される | 使わないなら宣言する: `docker/bin/setup/state.sh skip <項目>` |

## エージェントに任せる準備（任意）

commit / push / PR 作成は、既定では**依頼したときにエージェントが実行する**（「PR 作って」なら commit と push も含む）。「push は毎回確認してほしい」といった個人の方針は、git 管理外のプリファレンスファイルに書いておくとエージェントが読んで従う。

- 設定ファイル: `$USER_HOME_DIR/.personal-workspace/agent-preferences.md`（`docker/bin/setup.sh` が雛形を配置する）
- 書き方: [`agent-preferences.md`](agent-preferences.md)

## 関連

- [開発環境（Docker）](development-environment.md) — 環境の構築・運用の正本
- [Git 運用ガイドライン](git-workflow.md) — ブランチ・コミット・PR の運用ルール
- [エージェントの自律範囲と個人プリファレンス](agent-preferences.md)
