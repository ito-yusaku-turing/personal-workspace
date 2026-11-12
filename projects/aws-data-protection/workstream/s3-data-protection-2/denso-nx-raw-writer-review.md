# denso-nx-raw の書き込み元の精査（2026-11-12）

- 作成: 2026-11-12 ／ エージェント（ReadOnly と cdk-apps の `main` のコード）
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)。段階の正本 [worm-rollout-stages.md](worm-rollout-stages.md) の手順 C の段階 3。アクションの 4c-7
- 状態: **精査は済み。持ち主（犬塚さん）への確認はこれから**（下の「持ち主に確かめること」）

denso-nx-raw（`denso-nx-raw-767397804933`）に Object Lock を入れる前に、誰が・何で書き込むかを確かめた。

## 持ち主

- **犬塚 慎太郎さん（Shintaro Inuzuka）**。cdk-apps の `apps/denso-nx` と `packages/azure-data-sync` のコミット 38 件のうち 29 件（抽出の Batch ジョブ・Step Functions・ListMcaps Lambda・BulkPipeline、2026-05-01〜）。共有パッケージ `packages/azure-data-sync` への切り出し（[cdk-apps#1442](https://github.com/turingmotors/cdk-apps/pull/1442)）も犬塚さん。2026-11-10 の D28 の聞き取りの相手も犬塚さん。
- スタックとバケットを最初に作ったのは安本さん（[cdk-apps#948](https://github.com/turingmotors/cdk-apps/pull/948)、2026-04-10）。
- denso-nx-raw への DataSync のタスクを最初に作ったのは大戸 一希さん（GitHub の `kazu0716`。jadd_studio3 の `.mailmap` で確かめた。[cdk-apps#1077](https://github.com/turingmotors/cdk-apps/pull/1077)・[cdk-apps#1094](https://github.com/turingmotors/cdk-apps/pull/1094)、2026-05-14〜15）。
- CODEOWNERS に denso-nx の行は無い。

## 書き込み元

| 書き手 | 書き込み先 | 根拠 | 状態 |
|---|---|---|---|
| DataSync のタスク `azure-mlops1-dcorp-inbound-daily`（スタック `DensoNx`、ロール `DensoNx-AzureDataSyncTaskS3AccessRole…`） | `azure-mlops1/dcorp-inbound/` だけ（ロールの権限がこのプレフィクスに絞られている） | CDK（`lib/denso-nx-stack.ts`）と、`describe-task`・ロールのポリシー | 毎日 03:00 JST に動く（スケジュールは有効）。**10-14 以降の 30 回は、すべて転送 0 件**。転送元の Azure（`mlops1data81abaf24` の `dcorp-inbound`）のファイル数が 10-14 の 187,810 → 10-15・16 の 5,946 → **10-17 以降は 0** |
| 手で置いたもの | 直下の `rawdata/`（1 件）・`deriveddata/`（3 件）・`vehicle-config/`（5 件） | `s3 ls` | どれも 2026-05-07（DataSync を作る前）。それ以降の書き込みは無い |
| 抽出の Batch ジョブ・ListMcaps Lambda・ListSessions Lambda | — | CDK はどれも denso-nx-raw に `grantRead` だけ。書き出し先は denso-nx-processed と td1-raw | 書かない |

監査のトレイル（10-30〜11-11）でも、denso-nx-raw への書き込みは 0 件（[writer-survey-1111.md](writer-survey-1111.md)）。

## DataSync のタスクの設定と、Object Lock との関係

| 設定 | 値 | Object Lock を入れたあと |
|---|---|---|
| `TaskMode` | `ENHANCED` | チェックサムを付けて書くか分からない。[datasync-probe-runbook.md](datasync-probe-runbook.md) の試しで確かめる |
| `TransferMode`・`OverwriteMode` | `CHANGED`・`ALWAYS` | Azure 側でファイルが変わると上書きする。新しい版ができ、古い版はホールドで残る（消えない。その分の保存の費用がかかる） |
| `PreserveDeletedFiles` | `PRESERVE` | Azure 側で消えても、S3 からは消さない。転送元が 0 件になっても、バケットの中身はそのまま（10-17 以降の実行で確かめられる） |
| `ObjectMetadata` | `PRESERVE` | — |
| `VerifyMode` | `ONLY_FILES_TRANSFERRED` | 書き込んだあとに読み返す。ロールに `GetObject`・`GetObjectVersion` がある |
| ロールの権限 | `PutObject`・`DeleteObject`・`AbortMultipartUpload` ほか | `DeleteObject` は版を指定しない削除（削除マーカー）だけなら Object Lock でも通る。`PRESERVE` なので使われない見込み |
| ストレージクラス | `INTELLIGENT_TIERING` | — |

## 持ち主に確かめること（犬塚さん）

1. **Azure の `dcorp-inbound` が 10-15〜17 に空になったのは、意図したものか。** DENSO 側が受け渡しのあとに消す運用か。Azure の側に原本はもう無い、という理解でよいか（D28 で「唯一の原本」として対象にした前提）。
2. **これから DENSO から新しいデータが届く予定はあるか。** 届くなら、いつごろ・どれくらいの量か。DataSync の試しの結果が出る前に届くと、既定の保持設定を入れたあとに転送が止まるおそれがある。
3. **Azure に同じファイルが置き直されることはあるか。** あると、`OverwriteMode: ALWAYS` で上書きされ、古い版がホールドで残る（保存の費用が倍になる）。
4. **DataSync 以外に、手で書き込む人はいるか。** 直下の `rawdata/` などは 2026-05-07 に手で置かれた。今後も手で置く人がいるなら、その人が使う道具（チェックサムを付けるか）を知りたい。
5. **抽出のジョブで、denso-nx-raw のファイルを消したり置き直したりすることはあるか。** コードは読むだけだが、手での運用を確かめたい。

## 入れるまでの段取り（案）

1. 犬塚さんに上の 1〜5 を確かめる（伊藤）。
2. DataSync の試し（伊藤。[datasync-probe-runbook.md](datasync-probe-runbook.md)）。新しいデータの予定が無いなら、試しの結果を待たずに入れる手もある（転送は 0 件が続いているので、既定の保持設定で止まる書き込みが無い）。
3. 段階 1・2 と同じ手順（`worm-stage.sh`）で入れる。版の数は約 19 万で、ジョブは小さい。
