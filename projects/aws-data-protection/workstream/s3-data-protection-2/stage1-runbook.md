# 第 2 段階の段階 1（tuscenes-calibration の新・旧、td1-rlog）に Object Lock を入れる手順書

- 作成: 2026-11-11 ／ 伊藤（エージェントが起草）
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)。段階の正本 [worm-rollout-stages.md](worm-rollout-stages.md) の「手順 C」の段階 1。アクションの 4-7
- 状態: **未実施**。始める前の条件（0 章）がそろっていない
- 実行する人: 伊藤（`full` プロファイル＝tuscenes-prod の SSO の FullAccess）。ジョブの設定は伊藤ともう 1 人で確かめる。エージェントは、ログと ReadOnly の確認で結果を読み、書き込みのエラーをトレイルで見る
- スクリプト: `~/runbook/worm-stage/worm-stage.sh`（git の管理外）。段階 2・3 でも同じものを使う。ログは `~/runbook/worm-stage/log/` に、バケットと手順ごとに残る

予行（[canary-rehearsal-runbook.md](canary-rehearsal-runbook.md)）と同じ操作を、原本バケットに 1 本ずつ行う。段階 1 の 3 本は、書き込みがほとんど無く、件数も少ない。

## 0. 始める前の条件

| # | 条件 | 状態 |
|---|---|---|
| 0-1 | 解除後の保持期間を決める（アクションの 4-3）。30 日以外にするなら、先に cdk-apps の `EVENT_HOLD_DAYS` を変える PR を deploy し、スクリプトの `HOLD_DAYS` も合わせる | **未**（仮の 30 日） |
| 0-2 | ジョブの設定を確かめる 2 人目を決める（4-4） | **未** |
| 0-3 | 3 本の書き込み元が、チェックサムを付けて書いていること（1 章） | **済み**（2026-11-11。[writer-survey-1111.md](writer-survey-1111.md)。td1-rlog と旧は 12 日間書き込みなし、新は backend-api だけで付けている） |
| 0-4 | tuscenes-calibration（新）の書き手（backend-api）の設定 | **済み**（2026-11-11。下の 1 章） |
| 0-5 | 3 本のバケットポリシーに、守りの 5 文がそろっていること | **済み**（2026-11-11 の deploy のあと） |

## 1. 3 本の状態と書き込み元

| バケット | 暗号化 | ライフサイクル | 書き込み元 |
|---|---|---|---|
| `tuscenes-calibration`（旧） | SSE-S3 | Intelligent-Tiering への移動だけ（失効なし） | 10-30〜11-11 の 12 日間、書き込みなし |
| `tuscenes-calibration-767397804933`（新） | **SSE-KMS**（AWS 管理のキー `aws/s3`） | なし | backend-api の Lambda（JADD STUDIO の確定版のリリース）。boto3 1.42.11 の既定のクライアントで、チェックサムの設定を変えていない（mono-e2e の `routers/wheel_calibration.py`、cdk-apps の Lambda の環境変数にも無い）。CRC32 が付く。12 日間の 13 件の書き込みも、userAgent の記号でチェックサムを付けていた（実際の boto3 は 1.43 系）。予行の R2 で、条件付き書き込みも通った |
| `td1-rlog` | SSE-S3 | Intelligent-Tiering への移動だけ（失効なし） | 10-30〜11-11 の 12 日間、書き込みなし |

## 2. 手順（1 本ずつ）

順番は **td1-rlog → tuscenes-calibration（旧）→ tuscenes-calibration（新）**。最後の 1 本だけ SSE-KMS なので、ほかの 2 本で手順に慣れてから行う。

```bash
aws sso login --profile full         # 切れていれば
cd ~/runbook/worm-stage
B=td1-rlog                           # 1 本ずつ変える
```

| 手順 | コマンド | すること | 終わったら |
|---|---|---|---|
| 1 | `bash worm-stage.sh check $B` | 今の状態を出す（守りの 5 文がそろっているか） | — |
| 2 | `bash worm-stage.sh enable $B` | Object Lock を有効にする。**戻せない**。バケット名の打ち込みを求める | — |
| 3 | `bash worm-stage.sh default $B` | 既定の保持設定を入れる。これ以降の書き込みにチェックサムが要る | **エージェントに知らせる**。エージェントが 1 日ほど、書き込みのエラーをトレイルで見る |
| 4 | `bash worm-stage.sh hold $B` | 最新の版にホールドを付けるジョブを作り、確認待ちで止める。件数と先頭の 5 件を出す | **2 人で件数と中身を確かめる**。エージェントにも知らせる |
| 5 | `bash worm-stage.sh run $B` | 確認待ちのジョブを流す。バケット名の打ち込みを求める | — |
| 6 | `bash worm-stage.sh verify $B` | 失敗の内訳と、一覧から選んだ 20 件の保持を出す | **エージェントに知らせる** |

- **書き込みが止まったら:** `bash worm-stage.sh rollback $B`。既定の保持設定を外すと、すぐ書けるようになる（予行の R3）。外していたあいだの版には、入れ直したあと hold からやり直して付ける。
- **SSE-KMS の tuscenes-calibration（新）:** 手順 4 で、まず小さいプレフィクスに絞る（例: `bash worm-stage.sh hold $B calibration_results/`）。通ったら、プレフィクスなしで全体を流す（すでに付いた版にもう一度付けても、日数が同じなので何も変わらない）。カナリアは SSE-S3 なので、KMS の振る舞いは予行で確かめていない。
- **一覧は作った時点の写し:** 手順 3 のあとに手順 4 を行う（既定の保持設定を入れたあとに書かれた版は、既定から保持が付く）。
- ジョブの結果のレポートは、失敗した件だけを書く（件数が多いバケットで、レポートが大きくならないように）。

## 3. 終わった条件

- 3 本とも、既定の保持設定を入れてから数日、書き込みのエラーが無い（エージェントがトレイルで見る）。
- 3 本とも、ジョブが `Complete` で、失敗が 0 件。verify の 20 件が `GOVERNANCE ON 30`。

## 結果

| バケット | enable | default | hold・run | verify | メモ |
|---|---|---|---|---|---|
| td1-rlog | | | | | |
| tuscenes-calibration（旧） | | | | | |
| tuscenes-calibration（新） | | | | | |
