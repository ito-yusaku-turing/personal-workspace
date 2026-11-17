# denso-nx-raw の書き込み元の精査（2026-11-12）

- 作成: 2026-11-12 ／ エージェント（ReadOnly と cdk-apps の `main` のコード）
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)。段階の正本 [worm-rollout-stages.md](worm-rollout-stages.md) の手順 C の段階 3。アクションの 4c-7
- 状態: **精査は済み。2026-11-13 に、DataSync の心配はないと判断した**（S3 に記録されたチェックサムから。下の「犬塚さんの答えと、DataSync のチェックサム」）。DataSync の試しは行わない。次は段階 1・2 と同じ手順で入れる

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

## mono-turing-infra で分かったこと（2026-11-13）

転送元の Azure は mono-turing-infra の `platform/azure/` が管理している（犬塚さん・大戸さんが書いた。読んだのは `main` の `eeb30895`、2026-11-12）。根拠は次の 3 つ。

- [mono-turing-infra#772](https://github.com/turingmotors/mono-turing-infra/pull/772)（犬塚さん、2026-10-13 に merge）の本文
- `platform/azure/mlops-1/foundation/partner-data-bucket/terragrunt.hcl`
- `docs/rules/azure.md` の「原本 (partner inbound) の lifecycle 削除 / 破棄」と、`docs/azure/DESIGN.md`

| 問い | 分かったこと | 残ること |
|---|---|---|
| 1. `dcorp-inbound` が空になったのは意図したものか | **意図したもの**。#772 で、`dcorp-inbound` に lifecycle 削除（作成から 14 日を超えた blob を消す。`delete_after_days = 14`、旧 version は 1 日）を入れた。mlops-1 は merge で CI が apply するので、10-13 の merge が削除の発火点になった。理由は「DENSO NX の案件が終わる見込み」と費用（mlops-1 の RG の費用の 99.7%、月約 55 万円）。消す前に、Azure の現行 blob 187,810 件を S3 と名前・サイズで全件照合し、S3 に無いもの 0 件・サイズ不一致 0 件を確かめている。soft delete は SA 共通で 1 日 | 無し。**社内の写しは denso-nx-raw だけ**になった。原本は D 社の手元にある、という前提（DESIGN.md の「誤削除時の復旧方針」）は残る |
| 2. 新しいデータが届く予定はあるか | 案件は終わる見込み。ただし、**受け口は残してある**: D 社は今の credential のまま push でき、DataSync の日次（止めていない）が翌朝 S3 へ運び、Azure からは 14 日後に消える。14 日は「S3 へ渡るまでの猶予」 | 再開の見込み（届くとしたら、いつ・どのくらいか）は資料に無い。犬塚さんに聞く |
| 3. 同じファイルが置き直されることはあるか | **ある**。#772 によると、旧 version 5,564 件のうち 2,321 件は、D 社が同じファイルを同じサイズで送り直したもの。ほかに 636 件（0.2 TB）は、D 社が上げたあとに自分で消して置き換えたもの（`rawdata/nx_06/20260710` の mcap 299 件など） | 再開したときは、送り直しで S3 に新しい版ができ、古い版はホールドで残る（保存の費用が増える）。量は小さいとみる |
| 4. DataSync 以外に手で書く人はいるか | 資料に無い。Azure の blob を書けるのは D 社の SP と、`blob_data_contributor_principal_ids` の 3 人（大戸さん・安本さん・犬塚さん）と CI の SP。S3 側の手置き（2026-05-07）の主は分からない | 犬塚さんに聞く |
| 5. 抽出のジョブで、denso-nx-raw を消したり置き直したりするか | #772 に「NX の抽出・DLT・mdash はいずれも S3 を読んでいる」とあり、CDK も `grantRead` だけ（上の「書き込み元」）。denso-nx-raw に書き込む DataSync はこのタスクだけで、レプリケーションも無い、とも書いてある | 手での運用だけ、念のため聞く |

**Object Lock を入れるときに新しく効いてくること:**

- **DataSync の書き込みが Object Lock で止まると、届いたデータが消えるおそれがある。** 案件が再開して D 社が push したのに、既定の保持設定のせいで DataSync の転送が失敗すると（チェックサムを付けない書き方の場合）、そのデータは S3 に入らないまま、14 日後に Azure から消える。D 社の手元に原本はあるので取り戻せるが、気づくのが遅れると頼み直しになる。
- 防ぎ方は 2 つ。(a) DataSync の試し（[datasync-probe-runbook.md](datasync-probe-runbook.md)）で、`ENHANCED` のタスクが Object Lock のバケットに書けるかを先に確かめる。(b) 入れたあと、DataSync のタスクの実行の失敗に気づける仕組み（通知）があるかを確かめる。今の転送は 0 件が続いているので、試しの前に入れても、すぐに止まる書き込みは無い。
- **mono-turing-infra の側の約束:** 「DataSync の日次の schedule を止めるなら、先に `delete_after_days` を外す」（`docs/rules/azure.md`）。Object Lock の作業で DataSync を止めることは無いが、止めたくなったときはこの順番を守る。

## 犬塚さんの答えと、DataSync のチェックサム（2026-11-13）

**犬塚さんの答え:** 案件の予定は今のところ無いが、再開する可能性はある。

**DataSync がチェックサムを付けて書くかは、コードでは分からない**。DataSync のタスクは cdk-apps（`packages/azure-data-sync/src/datasync-task.ts`）にあり、mono-turing-infra にあるのは転送元の Azure の側だけ。タスクの設定にチェックサムの項目は無く（`verifyMode` は書いたあとの読み返しの設定）、DataSync のドキュメントにも書かれていない（2026-11-13 に再び確かめた）。

**代わりに、S3 に記録されたチェックサムから分かった**（ReadOnly の `list-objects-v2`、全 187,833 件）。S3 は、書き手がチェックサムを送らなければ CRC64NVME を自分で付け、送ればその方式（ここでは SHA256）を記録する。

| 書き手 | 件数 | 記録されたチェックサム | 読み方 |
|---|---|---|---|
| DataSync（`azure-mlops1/dcorp-inbound/` のファイル。2026-05-14〜10-02） | 187,821 | **すべて SHA256**（1 回で書いたもの 94,334 件は `FULL_OBJECT`、マルチパートの 93,487 件は `COMPOSITE`） | DataSync は、ふつうの書き込みでも、マルチパートのパートごとにも、`x-amz-checksum-sha256` を送っている（推論。SHA256 は書き手が送らないと付かない） |
| DataSync（0 バイトのフォルダの印、`…/` で終わるキー。2026-07-16） | 3 | CRC64NVME | **フォルダの印には、チェックサムを送っていない**とみる（S3 の既定の値） |
| 手で置いたもの（`rawdata/`・`deriveddata/`・`vehicle-config/`、2026-05-07） | 9 | CRC64NVME | 送っていない、または CLI が CRC64NVME を送った（区別できない） |

タスクは 1 本（`azure-mlops1-dcorp-inbound-daily`、`ENHANCED`、2026-05-14 09:50Z に作成）で、SHA256 の版はすべてこのタスクが書いたもの。denso-taxi-processed・denso-taxi-video（`ENHANCED` のタスクが書く）も、先頭の 2 万件ずつがすべて SHA256 だった。

**Object Lock との関係:** 保持が付く書き込みで要るのは「`Content-MD5` か `x-amz-checksum-*` のヘッダー」（予行の R2 で出たエラーの文。学習用の資料の 5 章）。SHA256 のヘッダーはこれに当たるので、**ファイルの書き込みは通る見込みが高い**。残る心配は次の 2 つで、どちらも小さい。

- **フォルダの印（0 バイト）は拒まれるおそれがある。** 転送元に空のフォルダがあるときだけ作られる（これまでに 3 件）。拒まれても失うのは空のフォルダの印だけだが、タスクの実行が `ERROR` で終わる見込みで、Slack に失敗の通知が出る。
- 推論であること（DataSync が送るヘッダーを直接見てはいない）。確かめるなら、DataSync の試し（[datasync-probe-runbook.md](datasync-probe-runbook.md)）か、入れたあとの最初の転送をトレイルで見る。

**判断の材料:** 再開の予定は無く、転送は 0 件が続いている。再開して書き込みが拒まれても、Slack に通知が出て、Azure には 14 日の猶予があるので、既定の保持設定を外せば（`rollback`）取り戻せる。**2026-11-13 に、DataSync の試しは行わずに入れると決めた（伊藤）。** 入れたあとの最初の転送をトレイルで見る。

## 入れるまでの段取り（案）

1. 犬塚さんに確かめる（伊藤）。2026-11-13 に、聞くことを「再開の見込み（2）」と「手で書く人（4）」と「手での削除・置き直し（5）」に絞った（上の「mono-turing-infra で分かったこと」）。
2. DataSync の試し（伊藤。[datasync-probe-runbook.md](datasync-probe-runbook.md)）。新しいデータの予定が無いなら、試しの結果を待たずに入れる手もある（転送は 0 件が続いているので、既定の保持設定で止まる書き込みが無い）。
3. 段階 1・2 と同じ手順（`worm-stage.sh`）で入れる。版の数は約 19 万で、ジョブは小さい。
