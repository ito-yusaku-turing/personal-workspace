# 可変の保持期間（イベントホールド）を使い捨てのバケットで試す手順書

- 作成: 2026-10-30
- 親: [原本バケットの WORM 化の設計](worm-design.md) の 2.1「試して確かめること」
- 状態: **保留（2026-10-30）。** WORM は「外せない層」の本命の候補（仮決定）。Q4（コンプライアンスで解除できるか）はドキュメントで「できる」と確かめた（[option-reassessment.md](option-reassessment.md) の 7.3）。WORM を採ると決めたときに再開する。Batch Operations の CloudTrail の記録は、別のセッション（pw-1030-pr）がカナリアで確かめ済み（option-reassessment.md の 7.4）
- 実行する人: 伊藤（`full` プロファイル＝tuscenes-prod の SSO の FullAccess）。エージェントは ReadOnly で結果を確かめる

原本バケットに入れる前に、ドキュメントに書かれていない挙動を、使い捨てのバケット 1 本で確かめる。

## 確かめること

| # | 問い | 試す節 |
|---|---|---|
| Q1 | バケットの既定の `Days` と `DefaultEventHold.Days` は、それぞれ何を決めるか。`Days` を省けるか | 2 |
| Q2 | ガバナンスモードで、迂回の権限があればホールド中の版を直接消せるか | 3 |
| Q3 | ホールドの解除に、迂回のヘッダーが要るか。解除の後、期限前の版は消せないか | 4 |
| Q4 | コンプライアンスモードで、ホールドを解除できるか | 5 |
| Q5 | チェックサムのヘッダーを付けない書き込みが拒まれるか（バケットの既定でかかる場合） | 6 |
| Q6 | Batch Operations で、既存の版にホールドをかけられるか | 7 |

**Q4 が一番大事。** 原本のモードはコンプライアンスに決めた（設計の決定 2）。その条件が Q4。Q4 が通らなければガバナンスに戻す。その場合は Q2 が効いてくる。

## 0. 前提と注意

- **Object Lock は外せない。** このバケットは、鍵のかかった版がすべて消えるまで消せない。期間はすべて 1 日にし、片付けで消し切る。
- **コンプライアンスの版は、解除して 1 日たつまで誰も消せない。** 5 で解除に失敗すると、その版（数バイト）とバケットはずっと残る。費用はほぼ 0 だが、残ることは受け入れる。
- tuscenes-prod（767397804933）、us-west-2 に作る。書き込みの経路の条件を原本に近づけるため。
- バケットポリシー（ステージ 1）・削除の検知（ステージ 2）・Inventory の対象には入れない。
- 費用はほぼ 0（数件のオブジェクトと、Batch Operations のジョブ 1 本 $0.25）。

```bash
export AWS_PROFILE=full AWS_REGION=us-west-2 AWS_PAGER=
aws sso login --profile full         # 切れていれば
aws sts get-caller-identity --query Arn --output text   # AWSReservedSSO_FullAccess_… であること
B=worm-probe-767397804933
```

## 1. バケットを作る

```bash
aws s3api create-bucket --bucket $B \
  --create-bucket-configuration LocationConstraint=us-west-2 \
  --object-lock-enabled-for-bucket
aws s3api put-bucket-tagging --bucket $B --tagging 'TagSet=[{Key=purpose,Value=worm-probe},{Key=owner,Value=yusaku.ito}]'
aws s3api get-bucket-versioning --bucket $B          # Status: Enabled（Object Lock で自動）
aws s3api get-object-lock-configuration --bucket $B  # ObjectLockEnabled: Enabled、Rule なし
```

7 で使うため、**既定を設定する前に**オブジェクトを 2 つ置く（鍵のかかっていない既存の版の代わり）。

```bash
echo pre-1 | aws s3api put-object --bucket $B --key pre/1.txt --body /dev/stdin
echo pre-2 | aws s3api put-object --bucket $B --key pre/2.txt --body /dev/stdin
aws s3api head-object --bucket $B --key pre/1.txt --query '{m:ObjectLockMode,h:ObjectLockEventHold}'   # どちらも null
```

## 2. バケットの既定（Q1）

まず `Days` を省いて設定する。

```bash
aws s3api put-object-lock-configuration --bucket $B --object-lock-configuration '{
  "ObjectLockEnabled":"Enabled",
  "Rule":{"DefaultRetention":{"Mode":"GOVERNANCE","DefaultEventHold":{"Days":1}}}}'
```

- 通れば → `Days` は省ける。記録して次へ。
- 拒まれれば → エラーの文言を記録し、`"Days":1` を足して設定し直す。

```bash
echo q1 | aws s3api put-object --bucket $B --key q1.txt --body /dev/stdin
aws s3api head-object --bucket $B --key q1.txt \
  --query '{v:VersionId,m:ObjectLockMode,until:ObjectLockRetainUntilDate,h:ObjectLockEventHold,hd:ObjectLockEventHoldDurationDays}'
aws s3api get-object-retention --bucket $B --key q1.txt
```

期待: `m=GOVERNANCE`、`h=ON`、`hd=1`、`until` は「今 ＋ 1 日」。`Days` を足した場合は、`until` が `Days` と `DefaultEventHold.Days` のどちらで決まるかを記録する。

## 3. ホールド中の版を消す（Q2）

```bash
echo q2 | aws s3api put-object --bucket $B --key q2.txt --body /dev/stdin
V=$(aws s3api head-object --bucket $B --key q2.txt --query VersionId --output text)

# 3-1. 版を指定しない削除 → 成功し、削除マーカーが付くだけ
aws s3api delete-object --bucket $B --key q2.txt
# 3-2. 版を指定した削除 → AccessDenied のはず
aws s3api delete-object --bucket $B --key q2.txt --version-id $V
# 3-3. 迂回のヘッダーを付けて版を指定した削除 → Q2 の答え
aws s3api delete-object --bucket $B --key q2.txt --version-id $V --bypass-governance-retention
```

- 3-3 が通れば、ガバナンスでは迂回の権限を持つ人がホールドを無視して消せる。迂回の権限を BreakGlass に絞る（設計の 2.2）ことが必須になる。
- 3-3 が拒まれれば、ガバナンスでもホールドは迂回できない。消すには必ず解除が要る。

## 4. 解除（Q3）

```bash
echo q3 | aws s3api put-object --bucket $B --key q3.txt --body /dev/stdin
V=$(aws s3api head-object --bucket $B --key q3.txt --query VersionId --output text)

# 4-1. 迂回のヘッダーなしで解除 → 通るか
aws s3api put-object-retention --bucket $B --key q3.txt --version-id $V \
  --retention '{"Mode":"GOVERNANCE","EventHold":"OFF"}'
#      拒まれたら、--bypass-governance-retention を付けて解除し、そのことを記録する
# 4-2. 解除の後の状態 → h=OFF、until は「解除した時刻 ＋ 1 日」
aws s3api get-object-retention --bucket $B --key q3.txt --version-id $V
# 4-3. 解除の後、期限前に版を指定して削除 → AccessDenied のはず
aws s3api delete-object --bucket $B --key q3.txt --version-id $V
```

`Mode` を省いた解除（`{"EventHold":"OFF"}`）が通るかも、別の版で試して記録する。

## 5. コンプライアンスモードでの解除（Q4）

版ごとにコンプライアンスにする。バケットの既定はガバナンスのまま。

```bash
echo q4 | aws s3api put-object --bucket $B --key q4.txt --body /dev/stdin
V=$(aws s3api head-object --bucket $B --key q4.txt --query VersionId --output text)

# 5-1. ガバナンスからコンプライアンスへ（ホールドは付けたまま）。迂回のヘッダーが要るかも記録
aws s3api put-object-retention --bucket $B --key q4.txt --version-id $V \
  --retention '{"Mode":"COMPLIANCE","EventHold":"ON","EventHoldDuration":{"Days":1}}'
aws s3api get-object-retention --bucket $B --key q4.txt --version-id $V
# 5-2. 迂回のヘッダーを付けても消せないこと → AccessDenied のはず
aws s3api delete-object --bucket $B --key q4.txt --version-id $V --bypass-governance-retention
# 5-3. 解除 → Q4 の答え
aws s3api put-object-retention --bucket $B --key q4.txt --version-id $V \
  --retention '{"Mode":"COMPLIANCE","EventHold":"OFF"}'
aws s3api get-object-retention --bucket $B --key q4.txt --version-id $V
```

5-3 が拒まれたら、エラーの文言を記録する。その版は消せなくなる（0 の注意）。

## 6. チェックサムのヘッダー（Q5）

古い SDK の振る舞い（必要なときだけチェックサムを付ける）を、CLI の設定で真似る。

```bash
# 6-1. チェックサムなし → 拒まれるか
AWS_REQUEST_CHECKSUM_CALCULATION=WHEN_REQUIRED \
  aws s3api put-object --bucket $B --key q5/no-checksum.txt --body /etc/hostname
# 6-2. Content-MD5 だけ付ける → 通るはず
MD5=$(openssl md5 -binary /etc/hostname | base64)
AWS_REQUEST_CHECKSUM_CALCULATION=WHEN_REQUIRED \
  aws s3api put-object --bucket $B --key q5/md5.txt --body /etc/hostname --content-md5 "$MD5"
# 6-3. 既定（今の CLI は CRC を付ける） → 通るはず
aws s3api put-object --bucket $B --key q5/default.txt --body /etc/hostname
# 6-4. マルチパート（8 MiB 超）をチェックサムなしで
head -c 20M /dev/urandom > /tmp/worm-probe-20m.bin
AWS_REQUEST_CHECKSUM_CALCULATION=WHEN_REQUIRED aws s3 cp /tmp/worm-probe-20m.bin s3://$B/q5/multipart.bin
rm /tmp/worm-probe-20m.bin
# 結果: 各キーにホールドが付いたか
for k in no-checksum.txt md5.txt default.txt multipart.bin; do
  echo "$k $(aws s3api head-object --bucket $B --key q5/$k --query '[ObjectLockMode,ObjectLockEventHold]' --output text 2>&1)"; done
```

- 6-1 が通れば、バケットの既定でかかるホールドには、チェックサムのヘッダーは要らない。書き込みの経路の確認は不要になる。
- 6-1 が拒まれれば、経路ごとに確かめる（8）。

## 7. Batch Operations で既存の版にかける（Q6）

1 で置いた `pre/` の 2 件にホールドをかける。Batch Operations 用のロールを一時的に作る。

```bash
ACCT=767397804933
cat > /tmp/worm-probe-trust.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"batchoperations.s3.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
cat > /tmp/worm-probe-perm.json <<JSON
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow","Action":["s3:PutObjectRetention","s3:BypassGovernanceRetention","s3:GetObject","s3:GetObjectVersion"],"Resource":"arn:aws:s3:::$B/*"},
 {"Effect":"Allow","Action":["s3:PutObject"],"Resource":"arn:aws:s3:::$B/batch-report/*"},
 {"Effect":"Allow","Action":["s3:GetBucketObjectLockConfiguration","s3:GetBucketLocation"],"Resource":"arn:aws:s3:::$B"}]}
JSON
aws iam create-role --role-name worm-probe-batch --assume-role-policy-document file:///tmp/worm-probe-trust.json
aws iam put-role-policy --role-name worm-probe-batch --policy-name worm-probe --policy-document file:///tmp/worm-probe-perm.json

# マニフェスト（CSV: バケット,キー,版）
V1=$(aws s3api head-object --bucket $B --key pre/1.txt --query VersionId --output text)
V2=$(aws s3api head-object --bucket $B --key pre/2.txt --query VersionId --output text)
printf '%s,pre/1.txt,%s\n%s,pre/2.txt,%s\n' $B $V1 $B $V2 > /tmp/worm-probe-manifest.csv
aws s3api put-object --bucket $B --key batch-manifest/manifest.csv --body /tmp/worm-probe-manifest.csv
ETAG=$(aws s3api head-object --bucket $B --key batch-manifest/manifest.csv --query ETag --output text | tr -d '"')

aws s3control create-job --account-id $ACCT --no-confirmation-required --priority 10 \
  --role-arn arn:aws:iam::$ACCT:role/worm-probe-batch \
  --operation '{"S3PutObjectRetention":{"Retention":{"Mode":"GOVERNANCE","EventHold":"ON","EventHoldDuration":{"Days":1}}}}' \
  --manifest "{\"Spec\":{\"Format\":\"S3BatchOperations_CSV_20180820\",\"Fields\":[\"Bucket\",\"Key\",\"VersionId\"]},\"Location\":{\"ObjectArn\":\"arn:aws:s3:::$B/batch-manifest/manifest.csv\",\"ETag\":\"$ETAG\"}}" \
  --report "{\"Bucket\":\"arn:aws:s3:::$B\",\"Prefix\":\"batch-report\",\"Format\":\"Report_CSV_20180820\",\"Enabled\":true,\"ReportScope\":\"AllTasks\"}"
# 出力の JobId で状態を見る（Complete まで数分）
aws s3control describe-job --account-id $ACCT --job-id <JobId> --query 'Job.{s:Status,p:ProgressSummary,f:FailureReasons}'
aws s3api head-object --bucket $B --key pre/1.txt --query '[ObjectLockMode,ObjectLockEventHold,ObjectLockRetainUntilDate]'
```

期待: 2 件とも `GOVERNANCE`・`ON`。マニフェストとレポートのオブジェクトにも、バケットの既定でホールドがかかる（片付けの対象に含める）。

## 8. 書き込みの経路（6-1 が拒まれた場合だけ）

経路ごとに、使っている SDK とその版を調べる。新しい SDK は既定でチェックサムを付ける（AWS CLI v2・boto3 は 2025 年初めの版から）。

| 原本バケット | 経路 | 調べること |
|---|---|---|
| td1-raw・tuscenes-raw・tuscenes-annotation | Databricks のジョブ（S3A・boto3） | ランタイムの hadoop-aws と AWS SDK の版 |
| denso-taxi-video・denso-nx-raw・denso-taxi-processed | DataSync・Azure からの転送 | 転送の道具（DataSync なら AWS のサービスなので付くはず） |
| gaming-data-collection | 手元のマシンからアクセスキー | 上げている道具と版 |
| tuscenes-model | 学習のジョブ | SDK の版 |
| td1-rlog・tuscenes-calibration（旧）・denso-raw | 今は書き込みなし | — |

## 9. 片付け

すべての版と削除マーカーを消してから、バケットとロールを消す。

```bash
# 3-3 で迂回の削除が通った場合: ガバナンスの版は迂回ですぐ消せる
# 通らなかった場合: すべての版のホールドを解除し、1 日待ってから消す
aws s3api list-object-versions --bucket $B --query '{v:Versions[].[Key,VersionId],d:DeleteMarkers[].[Key,VersionId]}' --output text
# 版ごとに:
#   aws s3api put-object-retention --bucket $B --key K --version-id V --retention '{"Mode":"GOVERNANCE","EventHold":"OFF"}' [--bypass-governance-retention]
#   （1 日後）aws s3api delete-object --bucket $B --key K --version-id V [--bypass-governance-retention]
# q4.txt（コンプライアンス）は、5-3 の解除から 1 日たってから消す
aws s3api delete-bucket --bucket $B
aws iam delete-role-policy --role-name worm-probe-batch --policy-name worm-probe
aws iam delete-role --role-name worm-probe-batch
rm -f /tmp/worm-probe-*.json /tmp/worm-probe-manifest.csv
```

## 結果（実行したら書く）

| # | 結果 | 日時・メモ |
|---|---|---|
| Q1 | | |
| Q2 | | |
| Q3 | | |
| Q4 | | |
| Q5 | | |
| Q6 | | |
| 片付け | | |
