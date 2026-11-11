# 原本バケットの書き込み元の見直し（2026-11-11）

- 作成: 2026-11-11 ／ エージェント（ReadOnly。伊藤の了承を得て、監査のトレイルの全期間を読んだ）
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)。アクションの E（2026-11-11 に決めた）。前回は 2026-11-02 の 3 日分（共有用の資料の 8.3）
- 道具: `~/runbook/trail-scan/writer-survey.py`（git の管理外）。トレイルは scratchpad に落として読んだ（約 2.2 万ファイル、1.2 GB）

Object Lock を入れる 9 本について、誰が・何で書いているか、チェックサムを付けているかを、監査のトレイル（`original-bucket-audit-logs-767397804933` の `trail/`。書き込み系のデータイベント）で集計した。**期間は 2026-10-30〜11-11 の約 12 日**（トレイルが原本バケットを記録し始めたのが 10-30）。

## 判定の仕方

- userAgent の `m/` の欄（SDK が使った機能の記号）に `U`〜`Y` があれば「付ける」（チェックサムを計算した）。`a` があれば `when_required`（付けない）。
- 古い SDK（AWS CLI 2.25 以前、boto3 1.36.14 など）は、付けていても `m/` に記号を出さない。これらは版から推定した（「付ける見込み（版）」）。根拠は Q13 の検証（boto3 1.35 は Content-MD5、1.36 以降は CRC32、AWS CLI v2 はどの版も付ける）。**設定で `when_required` にしていると、古い版では見分けられない**。
- `CopyObject`・`UploadPartCopy`・`CreateMultipartUpload`・`CompleteMultipartUpload` は、チェックサムが要らない（「不要」）。

## 結果

| バケット | 12 日間の書き込み | 書き手（件数） | 判定 |
|---|---|---|---|
| td1-rlog | **0 件** | — | 書き手なし |
| tuscenes-calibration（旧） | **0 件** | — | 書き手なし |
| tuscenes-calibration（新） | 13 件 | backend-api の Lambda（boto3 1.43 系。13） | **付ける**（記号で確かめた）。コードと Lambda の環境変数にも、チェックサムの設定の変更は無い |
| tuscenes-annotation | 約 49 万件 | LocalizationNightly のジョブ（boto3 1.43。29.2 万）、TeamE2E の SSO（AWS CLI 2.38〜2.39・boto3 1.43。約 15.6 万）、PerceptionDetection のジョブ・Lambda（AWS CLI 2.36〜2.39・aws-sdk-js 3.1104。約 3.1 万）、LocalizationNightly の Lambda（aws-sdk-js。1.1 万） | **すべて付ける**（記号で確かめた） |
| td1-raw | 約 133 万件 | アップロード用の PC `tokyo30-dataupload-pc-01`（AWS CLI 2.15.58・2.16.9・2.23.7・2.25.8・2.38.5。約 103 万）、rlog のデコーダー（boto3 1.36.14。約 25 万）、FullAccess の `CopyObject`（11-05 の 1 日。約 4 万） | 2.38.5 は**付ける**（記号）。ほかの CLI の版と rlog のデコーダーは**付ける見込み（版）**。rlog のデコーダーは、コード（cdk-apps の `apps/datalake/lib/rlog-decoder`）が既定のクライアントで、環境変数にも設定が無いことを確かめた |
| tuscenes-raw | **0 件** | — | 書き手なし |
| denso-nx-raw | **0 件** | — | 書き手なし（DataSync のタスクは毎日動くが、期間中に Azure 側の変更が無かったとみる） |
| denso-taxi-processed | **0 件** | — | 書き手なし（DataSync のタスクのスケジュールは止まっている） |
| denso-taxi-video | **0 件** | — | 同上 |

- **チェックサムを付けない書き手（`when_required` の記号）は、9 本には 1 件も無かった。** 前回見つかった Cosmos の checkpoint（`when_required`）と jadd-cli の presigned URL は、どちらも tuscenes-model（対象外）への書き込みで、今回も同じ。
- エラーは、通信の途中切れ（`IncompleteBody`）・`InternalError`・`NoSuchUpload`・`PreconditionFailed`（条件付き書き込みのぶつかり）だけ。拒否（`AccessDenied`）は無かった。

## 限界と、残る確かめ

- **12 日間しか見ていない。** 書き込みが 0 件の 6 本は、たまにしか書かれない書き手を見落としている可能性がある。段階 1 の 2 本（td1-rlog・tuscenes-calibration（旧））は、もともと書き込みが止まっていると見ているバケット。tuscenes-raw と denso の 3 本は、書き込みの権限を持つ主体の一覧（第一弾の [s3-bucket-access-control.md](../done/s3-bucket-access-control.md)）と突き合わせ、持ち主に聞く。
- **アップロード用の PC の古い CLI（2.15〜2.25）は、版から推定しただけ。** PC の `~/.aws/config` と環境変数 `AWS_REQUEST_CHECKSUM_CALCULATION` で `when_required` にしていないかを確かめる（段階 3 の td1-raw の前）。
- DataSync は、期間中に書き込みが無く、振る舞いが分からない。[datasync-probe-runbook.md](datasync-probe-runbook.md) で試す。
- tuscenes-annotation には、TeamE2E の人の手での書き込みが多い（11-05 に 1 日で 8 万件など）。今回の道具はどれも付けていたが、ほかの道具（s5cmd・rclone など）を使う人が出ると止まる。段階 2 の前に、チームに知らせる。
