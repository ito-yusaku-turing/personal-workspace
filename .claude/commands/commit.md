---
description: 変更を確認し、規約に沿ったコミットメッセージでコミットする
argument-hint: "[コミットに含めたい範囲や補足があれば]"
---

コミットを作成する。追加の指示: $ARGUMENTS

## 参照するもの

- **対象リポジトリ（作業中のリポジトリ）の AGENTS.md / CLAUDE.md** — personal-workspace 以外では、**毎回これを読み、そこに書かれた Git 規約に従う**（例: jadd_studio3 は `docs/guidelines/git-workflow.md`）。下の手順や `docs/git-workflow.md` のルールは持ち込まない。規約が見つからなければ、実行前に人間に確認する。git コマンドは対象リポジトリで実行する
- [`docs/git-workflow.md`](../../docs/git-workflow.md) — personal-workspace のコミット規約と禁止事項（**正本**）
- `$HOME/.personal-workspace/agent-preferences.md` — 個人プリファレンス。無ければ既定（personal-workspace は `git-workflow.md` の表、ほかのリポジトリはその規約）に従う

## 手順

1. **個人プリファレンスを読む**（このセッションでまだ読んでいなければ）。`git commit` が `禁止` なら実行せず、手順の提示にとどめて終了する。
2. **ブランチを確認する**: `git branch --show-current`。
   - **personal-workspace**: `main` のままコミットしてよい（作業ブランチは切らない）。
   - **ほかのリポジトリ**: そのリポジトリの規約に従う（ブランチの扱い、コミットメッセージの形式も含む）。
3. **変更全体を把握する**: `git status --short` と `git diff` / `git diff --staged`。
   - 目的の異なる変更が混ざっていれば、コミットの分割を提案する。
   - `docker/.env` / `docker/config/repos.conf` など **git 管理外のローカル設定を巻き込まない**。
4. **生成物の同期を確認する**（プロジェクトに該当するものがあれば）。生成コマンドを実行し、同一コミットに含める。
5. **メッセージを起草する**（規約は git-workflow.md）。
   - 要約行: `<type>(<scope>): <要約>`（句点なし・50字程度）
   - 本文: **なぜこの変更が必要か**。変更点は箇条書きでよい
   - トレーラー: `Co-Authored-By`
6. 対象を**明示的に** `git add` し（`git add -A` で巻き込まない）、`git commit -F <一時ファイル>` で作成する。
7. `git log -1 --stat` の要点を報告する。**push はしない**（commit の依頼に push は含まれない。`/push` で別途依頼する）。

## やらないこと

- 対象リポジトリの規約が許していないブランチへのコミット
- 依頼なしのコミット、`--amend` や履歴の書き換え
- ステージ済みの他人の変更を巻き込むこと（`git status` で確認する）
