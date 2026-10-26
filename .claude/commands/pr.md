---
description: 未コミット差分の commit と push を済ませ、セルフレビュー結果をもとに本文を起草して gh pr create する
argument-hint: "[PR の目的や強調したい点があれば]"
---

Pull Request を作成する。追加の指示: $ARGUMENTS

## 参照するもの

- **対象リポジトリ（作業中のリポジトリ）の AGENTS.md / CLAUDE.md** — 独自の Git 規約があれば**そちらを優先**する（例: jadd_studio3 は `docs/guidelines/git-workflow.md`）。git コマンドは対象リポジトリで実行する
- [`docs/git-workflow.md`](../../docs/git-workflow.md) — PR の書式と禁止事項（**正本**）
- `$HOME/.personal-workspace/agent-preferences.md` — 個人プリファレンス。無ければ `git-workflow.md` の既定表に従う
- `docker/container-bin/doctor.sh --porcelain` — セットアップ状態（`gh-auth` が使えるか）

## 手順

0. **対象が personal-workspace なら PR を作らない**。personal-workspace は `main` だけで運用し、PR を使わない（[`docs/git-workflow.md`](../../docs/git-workflow.md) の「personal-workspace の運用」）。その旨を伝え、必要なら `/push` の手順で `main` に push するかを確認して終了する。

1. **個人プリファレンスを読む**（未読なら）。`gh pr create` が `禁止` なら実行せず終了する。
2. **セットアップ状態を確認する**（未取得なら）: `docker/container-bin/doctor.sh --porcelain`。
   `gh-auth` が `ok` でない場合も**作業を打ち切らない**。差分の把握・セルフレビュー・本文の起草（手順 3〜5）は最後まで行い、最後に**人間が自分で叩けるコマンド**（`gh pr create` の全文、または PR 作成 URL）を渡して終わる。
   - `declined` → gh を使わない設定なので、`gh` を試さず本文とブラウザ用の情報だけを渡す。
   - `missing` → 上記に加えて `docker/bin/setup/github.sh gh-login` を案内する。
3. **前提を確認する**。
   - ブランチが `main` でないこと
   - 未コミット差分や未 push のコミットがあれば `/commit` `/push` の手順をそのまま実行する（PR 作成の依頼に含まれる）
   - 同じブランチの PR が既に無いこと（`gh-auth` が `ok` の場合のみ: `gh pr list --head "$(git branch --show-current)"`）
4. **差分を把握する**: `git log main..HEAD --oneline` と `git diff main...HEAD --stat`。
5. **セルフレビューを行う**。自動チェックは step 3 の `/push` で通っている。step 3 が no-op だった（既に commit / push 済みだった）場合はここで通す。
6. **タイトルと本文を起草する**。
   - タイトル: コミットの要約行と同じ形式 `<type>(<scope>): <要約>`
   - 本文は次の構成。バッククォート等を含むため、**一時ファイルに書いて `--body-file` で渡す**。
     ```markdown
     ## 目的
     ## 変更内容
     ## 確認したこと
     ## 残課題・確認してほしい点
     ```
   - 「確認したこと」には**確認していない範囲**も明記する。「残課題」にはやり残し・既知の制約・レビューで見てほしい観点を書く。
7. 作成する。
   ```bash
   gh pr create --base main --title "<タイトル>" --body-file <一時ファイル>
   ```
   レビュー前の共有が目的なら `--draft` を付ける（人間の指示がある場合のみ）。
8. **PR の URL と、本文の「残課題・確認してほしい点」の要点を報告する**。一時ファイルは削除する。

## やらないこと

- **マージ（`gh pr merge`）** — 禁止。個人設定でも解禁されない。レビュー後に人間が行う
- 依頼なしの PR 作成、レビュアーの勝手な指定
- 目的の異なる変更を1つの PR に混ぜること（分割を提案する）
