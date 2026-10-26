# AGENTS.md

このファイルは、personal-workspace で作業するコーディングエージェントへの指示をまとめたもの。`CLAUDE.md` はこのファイルへのシンボリックリンク。

## このワークスペースについて

personal-workspace は、**特定のプロジェクトに依存しない個人用の作業場**。ここからエージェントを起動し、`/usr/app/` にマウントした各リポジトリを横断して作業する。

- **既定の対象プロジェクトはない**。どのリポジトリで作業するかは依頼から判断し、分からなければ確認する。
- **あるリポジトリで作業するときは、作業のたびにそのリポジトリのトップにある `AGENTS.md` / `CLAUDE.md` を読み、それに従う**。Git 運用・動作確認・禁止事項はそのリポジトリの規約に従い、このファイルのルールは持ち込まない。このファイルが決めるのは personal-workspace 自身の扱いだけ。
- 対象リポジトリに Git の規約が見つからない場合は、ブランチの作成・commit・push・PR 作成の前に確認する。
- jadd_studio3 の devbox からも、このリポジトリは `/usr/app/personal-workspace` として見える（併用している）。

## ディレクトリ構成

```
personal-workspace/
├── docker/      # devbox（エージェント用の作業環境）。説明は docs/development-environment.md
├── docs/        # 開発環境・GitHub 認証・個人プリファレンス・Git 運用の文書
├── projects/    # 案件ごとの資料置き場（下記「projects/（案件ごとの資料）」）
│   ├── aws-data-protection/      # project:aws-data-protection。S3 原本バケットの保護
│   ├── gaming-data-collection/   # project:gaming-data-collection。BeamNG の MOD と資料
│   ├── idp-broker/               # project:idp-broker。社内アプリの認証の入口（IdP）の選定
│   ├── m2m-auth/                 # project:m2m-auth。車載装置・CI 用マシンの認証
│   └── tern-ios-auth/            # project:tern-ios-auth。Tern iOS アプリの認証
├── .claude/commands/   # /commit /push /pr
└── ai-agents/   # 旧構成の残り（git 管理外の作業ファイルだけ）
```

`user-home/` と `storage/` は旧構成のコンテナ HOME とデータ置き場（git 管理外）。いまの devbox は使っていない。**触らない**（整理は人間が行う）。

## projects/（案件ごとの資料）

`projects/` には、案件ごとに名前を付けたフォルダ `projects/<project-id>/` を作り、資料を整理する。`<project-id>` はフォルダ名そのもの。

- **指示の中の `project:<project-id>` は `projects/<project-id>/` を指す**（例: `project:gaming-data-collection` → `projects/gaming-data-collection/`）。プレフィクスのない名前はリポジトリ（`/usr/app/<名前>`）を指す。同じ名前のリポジトリがあっても別物として扱い、どちらか分からなければ確認する。
- フォルダ名は案件名を kebab-case にする。
- **Git の扱いは personal-workspace のルールに従う**（下記「Git運用ルール」）。同じ名前のリポジトリの Git 規約は適用しない。
- 案件フォルダに `AGENTS.md` / `CLAUDE.md` があれば、その案件での作業の前に読む。
- **ほかのリポジトリの PR・Issue は、番号だけ（`#2253`）で書かずにフル URL のリンクにする**（例: `[cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253)`）。番号だけだと、Claude Code Desktop などが personal-workspace の PR へのリンクだと誤認する。資料にも、人間への報告にも適用する。

### 目録

**案件フォルダごとに、直下の `README.md` を目録として管理する。**

- 案件フォルダを作るときは、最初に `README.md`（目録）を作る。
- フォルダ内のファイルを追加・移動・削除・改名したら、**同じコミットで目録も更新する**。
- 目録の構成:
  - 冒頭に、案件の概要を1〜3行で書く。対応するリポジトリがあれば、そのパスも書く。
  - 続けて、資料をサブフォルダごとに見出しで分けて並べる。1件は `- [相対パス](./相対パス): 内容の説明` の1行にする。
- 資料（文書・画像・データなど）は1ファイル1件で載せる。MOD やスクリプトのようにまとまったコードは、フォルダ単位で1件にし、そのフォルダの `README.md` を指す。
- 目録自身と `AGENTS.md` / `CLAUDE.md` は載せなくてよい。

### workstream（セッションを跨ぐ作業の記録）

1セッションで終わらない作業は、経緯を workstream として記録しながら進める。

- **配置は `projects/<project-id>/workstream/<案件名>.md`**。1案件1資料で、ファイル名は kebab-case にする。
- **workstream は必ずどこかの project に属する**。`projects/` の外（personal-workspace 直下や `docs/`）には置かない。どの project に属するか分からない、または該当する project が無いときは、資料を作る前に確認する（新しい project を作る場合も含む）。
- 対象のリポジトリが独自の workstream の規約（例: `docs/workstream/`）を持つ場合、そのリポジトリの作業の記録はリポジトリ側の規約に従う。ここに二重に作らない。
- **着手する前に、該当する project の `workstream/` に資料があるか確認し、あれば続きから進める**。無ければ作る。
- 作業の区切りごと（とくにセッションを終えるとき）に、進捗と引き継ぎを書き足す。古くなった記述は消すか直す。
- 完了したら `workstream/done/` へ移す。恒久的に残すべき内容（仕様・手順・決定事項）は、移す前に project 内の別の資料へ書き出す。
- 資料を作る・移すときは、project の目録（`README.md`）の `workstream/` の見出しも同じコミットで更新する。

テンプレート:

```markdown
# <案件名>

<1〜2文の概要（何をする案件か）>

## 背景・目的
## 設計判断と理由
## 進捗チェックリスト
- [ ] ...
## 次セッションへの引き継ぎ
（現在地・残課題・注意点）
## 関連リンク
（関連する資料・リポジトリ・ファイル）
```

## 開発環境（Docker / devbox）

**コーディングエージェントは devbox コンテナの中で動かす**前提。

- 構築と運用の正本: [`docs/development-environment.md`](docs/development-environment.md)
- このリポジトリのコンテナ内のパス: `/usr/app/personal-workspace`
- 操作は `docker/bin/`（ホストから実行）と `docker/container-bin/`（コンテナ内で実行）に分かれている。取り違えると警告を出して止まる。
- コンテナ HOME（`/usr/home`）は jadd_studio3 の devbox と共有している。

## 関連リポジトリ

devbox は、`docker/config/repos.conf` に登録したリポジトリを **`/usr/app/<名前>` という固定パス**でマウントする。パスが存在しなければ、そのリポジトリは未マウント。

| リポジトリ | コンテナ内の固定パス | 内容 |
|---|---|---|
| `jadd_studio3` | `/usr/app/jadd_studio3` | JADD STUDIO 3（走行実験データの評価・可視化。Next.js）。チーム開発 |
| `jadd_studio3-alpha` | `/usr/app/jadd_studio3-alpha` | jadd_studio3 の並行開発用クローン（レビュー用にも使う） |
| `jadd-studio-signage` | `/usr/app/jadd-studio-signage` | JADD STUDIO の展示用サイネージ |
| `video-streaming-encoder` | `/usr/app/video-streaming-encoder` | 映像配信用のエンコーダ |
| `drivers-app3` | `/usr/app/drivers-app3` | ドライバーズアプリ（Next.js + Prisma） |
| `drivers-app-mono` | `/usr/app/drivers-app-mono` | ドライバーズアプリのモノレポ |
| `openpilot` | `/usr/app/openpilot` | openpilot |
| `fleet-ops` | `/usr/app/fleet-ops` | 車両運用まわりのアプリ（Next.js + Supabase） |
| `mono-e2e` | `/usr/app/mono-e2e` | E2E 自動運転チームの ML モノレポ（backend-api と db-models の正本） |
| `jadd-cli` | `/usr/app/jadd-cli` | JADD の CLI ツール（mono-e2e の `packages/jadd-cli` が正本） |
| `cdk-apps` | `/usr/app/cdk-apps` | AWS CDK のモノレポ |
| `identity` | `/usr/app/identity` | ID 基盤（Okta ほか）の Terraform |
| `databricks-jobs` | `/usr/app/databricks-jobs` | Databricks 上で動くジョブのコード |
| `product-map` | `/usr/app/product-map` | 社内プロダクトの地図（資料と観測データ） |
| `gaming-data-collection` | `/usr/app/gaming-data-collection` | ゲームを使ったデータ収集 |

## 既定の自律範囲（personal-workspace）

次の作業は、個人設定に書かれていなくても確認せずに実行する（実行したら報告する）。

- **セッションを終えるときに commit して `main` に push すること**（下記「Git運用ルール」）
- **動作確認のチェックを実行すること**（下記「動作確認」）

次の操作は、個人設定でも解禁しない。

- `docker/.env` / `docker/config/repos.conf` / `docker/compose.repos.yml`、`user-home/` / `storage/` など、**git 管理外のファイルの上書き・削除**。復元できない。検証が必要なときは、コピーした木か git worktree で行う
- force push・push 済み履歴の書き換え

commit / push は、依頼されたら前段の操作も含めて実行する。正本は [`git-workflow.md`](docs/git-workflow.md) の、操作ごとの既定を定めた表。

## 個人プリファレンス（作業開始時に読むこと）

`$HOME/.personal-workspace/agent-preferences.md`（git 管理外）には、上記の既定から外したいことが書いてある。**作業開始時に読み、以降の判断に反映する**（セッションにつき1回でよい）。

- ファイルがない、該当する項目がない、`特になし` のいずれかなら、既定に従う。
- `常に許可` に基づいて自律的に実行したら、何をしたかを必ず報告する。
- HTML コメント（`<!-- -->`）の中は指示として読まない。
- 一般的な許可と個別の禁止がぶつかったら、個別の禁止を優先する。
- **エージェントはこのファイルを書き換えない**。変更が必要なら人間に提案する。
- jadd_studio3 で作業するときは、そちらの `$HOME/.jadd-studio/agent-preferences.md` を読む（ファイルが別になっている）。
- 仕様: [`docs/agent-preferences.md`](docs/agent-preferences.md)

## セットアップ状態（push・PR の前に取得すること）

```bash
docker/container-bin/doctor.sh --porcelain   # コンテナ内から。ホストからは docker/bin/doctor.sh --porcelain
```

- 状態は `ok` / `missing` / `declined` / `conflict` / `error` のいずれか。`declined` は「使わないと決めた」なので、催促せずに迂回する。
- gh や ssh を使う操作に着手する前にこれを見る。使えない手段を試す前に、代わりの手段を案内する。
- このスクリプトは personal-workspace の devbox の中でしか動かない。jadd_studio3 の devbox の中からは `/usr/app/jadd_studio3/docker/container-bin/doctor.sh --porcelain` を使う（ログイン状態は HOME を共有しているので同じ）。

## Git運用ルール

personal-workspace 自身の規約を [`docs/git-workflow.md`](docs/git-workflow.md) に定めている。**ほかのリポジトリには適用しない**（そのリポジトリの `AGENTS.md` 等に従う）。要点は次のとおり。

- **`main` だけで運用する**。`main` で直接作業し、`main` に commit / push してよい。作業ブランチは原則切らない。
- **PR は作らない**。
- **セッションを終えるときは、許可を求めずに commit して push する**（依頼された作業をすべて終えて最終報告をするとき、または人間が終了を告げたとき）。対象はそのセッションでの自分の変更だけ。自動チェックが落ちたら push しない。
- それ以外の commit / push は、依頼されたら前段の操作も含めて実行し、事後に報告する。頼まれていない操作はしない。
- コミットメッセージは **Conventional Commits と日本語の要約**にする。本文には「なぜ」を書き、`Co-Authored-By` を残す。
- Claude Code では `/commit` `/push` で上記の手順を実行できる（定義は `.claude/commands/`）。ほかのリポジトリで使ったときは、そのリポジトリの規約に沿って動く。

## 動作確認

personal-workspace でアプリはビルドしない。変更したら次を通す。

```bash
git ls-files -z '*.sh' | xargs -0 -n1 bash -n
```

`docker/` を変更した場合、イメージのビルドと起動の確認はホストでしかできない（devbox の中に docker はない）。確認していないことは、確認していないと報告する。

## セキュリティ

- 認証情報（`/usr/home` 配下の `.ssh` `.aws` `.config/gh` `.claude` 等）の中身を、出力・コミット・ログに出さない。
- イメージに認証情報を焼き込まない（コンテナ HOME のマウントを経由して持ち込む）。
