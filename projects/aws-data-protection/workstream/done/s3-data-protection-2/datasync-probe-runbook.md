# DataSync を Object Lock のバケットに向けて試す手順書

- 作成: 2026-11-11 ／ 伊藤（エージェントが起草）
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)。アクションの 4-6（[worm-action-list.md](worm-action-list.md)）。段階 2（denso の 3 本）の前提
- 状態: **行わないことにした**（2026-11-13、伊藤。S3 に記録されたチェックサムから、DataSync が SHA256 を付けて書いていると分かったため。[denso-nx-raw-writer-review.md](denso-nx-raw-writer-review.md)）。手順は、必要になったときのために残す
- 実行する人: 伊藤（`full` プロファイル＝tuscenes-prod の SSO の FullAccess）。エージェントは、ログと ReadOnly の確認で結果を読む
- スクリプト: `~/runbook/datasync-probe/datasync-probe.sh`（git の管理外）。ログは `~/runbook/datasync-probe/log/` に手順ごとに残る

denso の 3 本（denso-nx-raw・denso-taxi-processed・denso-taxi-video）には、Azure Blob から DataSync で書き込まれる。Object Lock と既定の保持設定を入れたあとも書き込めるかを、カナリア（`original-bucket-canary-767397804933`。予行で Object Lock と既定の保持設定（30 日）を入れたもの）で試す。

## なぜ試すか

- **DataSync のドキュメントに、Object Lock のことが書かれていない**（2026-11-11 に確かめた）。対応しているとも、していないとも書かれていない。
- Object Lock のバケットへの書き込みには、チェックサムのヘッダーが要る（予行の R2）。DataSync が付けるかは、書かれていない。
- 今の DataSync の設定（cdk-apps の `packages/azure-data-sync`）は、宛先のファイルを消さない（`PreserveDeletedFiles=PRESERVE`）。上書きは新しい版を足すだけなので、Object Lock とぶつかる操作は無い見込み。残る疑問はチェックサムだけ。

## 確かめること

| # | 問い | 手順 |
|---|---|---|
| D1 | 本番と同じ設定のタスクで、Object Lock のバケットに書き込めるか。書かれた版に、既定の保持設定から保持が付くか | run |
| D2 | 大きいファイル（約 127 MB。マルチパートになる見込み）も書けるか | run |
| D3 | 上書き（同じキーに新しい版）も書けるか | rerun |
| D4 | DataSync の書き込みが、トレイルでどう記録されるか（userAgent のチェックサムの印） | エージェントが ReadOnly で見る |

## 0. 前提と注意

- **転送元は、本番のタスク `azure-mlops1-dcorp-inbound-daily` と同じ Azure の場所**（`loc-04d6900bf0253b776`、dcorp-inbound コンテナ）を共用する。読み取りだけで、本番のタスクには触らない。cleanup でも消さない。
- 転送するのは、フィルタで選んだ 2 つのファイルだけ。どちらも denso-nx-raw にすでにあるもの。
  - `/control/deriveddata/nx_02/20260707/calib_param_path.txt`（37 バイト）
  - `/control/rawdata/nx_06/20260818/record/20260817_233840/filtered_20260818-030544.mcap`（約 127 MB）
- タスクの設定は、本番と同じにする（Enhanced モード、`TransferMode=CHANGED`、`PreserveDeletedFiles=PRESERVE`、`OverwriteMode=ALWAYS`、Intelligent-Tiering、ほか）。宛先のロールの権限も本番と同じで、カナリアの `datasync-probe/` だけに絞る。
- **書かれた版には 30 日のホールドが付き、外すまで消せない**（迂回は全員に拒否）。カナリアに DENSO のデータの写しが 2 つ（約 127 MB）残る。費用はほぼ 0。消したくなったら、予行と同じくジョブで解除し、30 日後に消す。
- **本番のタスク（毎日 03:00 JST = 18:00 UTC）の前後 30 分は避ける。** Azure の SAS を共用しているため。
- 費用: DataSync の Enhanced モードの転送料（数百 MB で数セント）と、Azure からの転送料。

```bash
aws sso login --profile full         # 切れていれば
cd ~/runbook/datasync-probe
```

## 1. 手順

| 手順 | コマンド | すること | 終わったら |
|---|---|---|---|
| 1 | `bash datasync-probe.sh setup` | 一時的なロール `original-bucket-canary-datasync-probe`、宛先（カナリアの `datasync-probe/`）、タスク `datasync-probe-canary` を作る | — |
| 2 | `bash datasync-probe.sh run` | D1・D2。本番と同じ設定で転送し、書かれた版の保持を出す | **エージェントに知らせる** |
| 3 | `bash datasync-probe.sh rerun` | D3。`TransferMode=ALL` で同じファイルを上書きする | **エージェントに知らせる** |
| 4 | `bash datasync-probe.sh cleanup` | タスク・宛先・ロールを消す（書かれた版は残る） | — |

**期待する結果**

- run: `SUCCESS`。2 ファイルが転送され、どちらも `GOVERNANCE ON 30`。
- rerun: `SUCCESS`。同じキーに新しい版ができ、新しい版も古い版も `GOVERNANCE ON 30`。
- `ERROR` で、理由が `Content-MD5 OR x-amz-checksum- HTTP header is required` なら、DataSync はチェックサムを付けていない。**denso の 3 本には既定の保持設定を入れられない**（ジョブで既存の版に付けるだけにする、などの代わりの案を考える）。

## 結果

| # | 結果 | 日時・メモ |
|---|---|---|
| D1 | | |
| D2 | | |
| D3 | | |
| D4 | | |
