---
description: 変更を確認し、規約に沿ったコミットメッセージでコミットする
argument-hint: "[コミットに含めたい範囲や補足があれば]"
---

コミットを作成する。追加の指示: $ARGUMENTS

## 参照するもの

- **対象リポジトリ（作業中のリポジトリ）の AGENTS.md / CLAUDE.md** — 独自の Git 規約があれば**そちらを優先**する（例: jadd_studio3 は `docs/guidelines/git-workflow.md`）。git コマンドは対象リポジトリで実行する
- [`docs/git-workflow.md`](../../docs/git-workflow.md) — コミット規約と禁止事項（**正本**）
- `$HOME/.personal-workspace/agent-preferences.md` — 個人プリファレンス。無ければ `git-workflow.md` の既定表に従う

## 手順

1. **個人プリファレンスを読む**（このセッションでまだ読んでいなければ）。`git commit` が `禁止` なら実行せず、手順の提示にとどめて終了する。
2. **ブランチを確認する**: `git branch --show-current`。`main` にいる場合は**コミットしない**。作業ブランチ名を提案し、切ってよいか確認する。
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

- `main` への直接コミット
- 依頼なしのコミット、`--amend` や履歴の書き換え
- ステージ済みの他人の変更を巻き込むこと（`git status` で確認する）
