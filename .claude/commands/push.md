---
description: 未コミット差分の commit と自動チェックの通過を済ませて作業ブランチを push する
argument-hint: "[補足があれば]"
---

作業ブランチを push する。追加の指示: $ARGUMENTS

## 参照するもの

- **対象リポジトリ（作業中のリポジトリ）の AGENTS.md / CLAUDE.md** — 独自の Git 規約があれば**そちらを優先**する（例: jadd_studio3 は `docs/guidelines/git-workflow.md`）。git コマンドは対象リポジトリで実行する
- [`docs/git-workflow.md`](../../docs/git-workflow.md) — push の前提と禁止事項（**正本**）
- `$HOME/.personal-workspace/agent-preferences.md` — 個人プリファレンス。無ければ `git-workflow.md` の既定表に従う
- `docker/container-bin/doctor.sh --porcelain` — セットアップ状態（`ssh-key` が使えるか）

## 手順

1. **個人プリファレンスを読む**（未読なら）。`git push` が `禁止` なら実行せず終了する。
2. **セットアップ状態を確認する**（未取得なら）: `docker/container-bin/doctor.sh --porcelain`。
   - `ssh-key` が `declined` → **push を試さない**。「SSH 鍵を使わない設定になっている」ことと、鍵を用意する場合の入口（`docker/bin/setup/github.sh ssh-key`）を伝えて終了する。
   - `ssh-key` が `missing` → 未着手なので `docker/bin/setup/github.sh ssh-key` を案内して終了する。
3. **ブランチを確認する**: `git branch --show-current`。`main` なら**中止**する（push 禁止）。
4. **未コミットの変更を確認する**: `git status --short`。今回の作業の差分が残っていれば `/commit` の手順でコミットする（push の依頼に含まれる）。作業と無関係の差分は含めず、残したことを報告する。
5. **push 対象を確認する**: `git log @{u}.. --oneline`（上流が無い場合は `git log main..HEAD --oneline`）。
6. **自動チェックを通す**（このセッションで未実施、または以降にコードを変更している場合）。
   ```bash
   # personal-workspace: シェルスクリプトの構文チェック
   git ls-files -z '*.sh' | xargs -0 -n1 bash -n
   # ほかのリポジトリ: そのリポジトリの AGENTS.md / CLAUDE.md が定めるチェック（build / lint / test 等）
   ```
   **失敗したら push しない**。結果を報告し、修正するかを確認する。
7. push する。
   ```bash
   git push -u origin "$(git branch --show-current)"
   ```
8. 結果（ブランチ名・コミット数・リモートの URL）を報告する。**PR は作らない**（push の依頼に PR 作成は含まれない。`/pr` で別途依頼する）。

## やらないこと

- `main` への push
- `--force` / `--force-with-lease`（履歴の書き換えは人間の明示指示があるときだけ）
- 他人のブランチへの push、ブランチ・タグの削除
