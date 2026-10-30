# 原本バケットの WORM 化: 比較と調査の記録

- 作成: 2026-10-30
- 親: [原本バケットの WORM 化の設計](worm-design.md)（この資料はその添付）
- 一般論: [S3 Object Lock（WORM）の整理](../../documents/notion-s3-object-lock.md)（以下「整理」）

設計の決定のために比べたことと、そのために調べたことを残す。決定そのものと理由は設計資料に書く。

## 1. 鍵の表し方の比較（決定 3 のため）

要件は「時間がたっても鍵が外れない。外すには、記録に残る明示的な操作が要る」。期間の長さは要件にしない。

| 案 | 時間がたつと外れるか | 新しく書かれた版に自動でかかるか | 消すときの操作 | 評価 |
|---|---|---|---|---|
| **A. 可変の保持期間（イベントホールド）** | 外れない。解除するまで守られる | かかる（バケットの既定） | ホールドを解除し、決めた日数を待つ | **採った** |
| B. 100 年の固定の保持期間 | 100 年後に外れる（実質的に外れない） | かかる | ガバナンスなら迂回。コンプライアンスなら 100 年消せない | 予備。A が使えなかったとき |
| C. 短い固定の保持期間を定期的に延ばす | 延ばし忘れると外れる | かかる | 迂回、または期限切れを待つ | 「いつの間にか消せる」そのもの。採らない |
| D. リーガルホールド | 外れない | **かからない**（既定の設定が無い） | `s3:PutObjectLegalHold` で外す（モードに関係しない） | 書き込む側がすべて付ける必要がある。採らない |

A の利点:

- 鍵を外すこと（ホールドの解除）が、記録に残る操作になる。解除しても決めた日数は誰も消せない。
- コンプライアンスと組み合わせられる。B をコンプライアンスにすると「100 年誰も消せない」になる。

## 2. モードの比較（決定 2 のため）

### 2.1 一般的な違い

| | ガバナンスモード | コンプライアンスモード |
|---|---|---|
| 期限前の削除・期間の短縮 | `s3:BypassGovernanceRetention` を持ち、迂回のヘッダーを付けたときだけできる | 誰もできない。root もできない |
| モードの変更 | 迂回の権限でできる | できない |
| ガバナンス → コンプライアンス | 移せる | 逆はできない |
| S3 のコンソール | 迂回のヘッダーを自動で付ける | 関係ない |

### 2.2 固定の保持期間で比べた場合（当初）

| | ガバナンス（＋迂回を BreakGlass に絞る） | コンプライアンス |
|---|---|---|
| 例外の主体・deploy の経路・root | BreakGlass 以外は止まる | 止まる |
| BreakGlass 自身の誤操作・乗っ取り | 通る（コンソールなら自動で迂回） | 止まる |
| 設定を誤ったとき | BreakGlass で直せる | 直せない。期間中、費用がかかり続ける |
| 消す必要が出たとき | BreakGlass で消せる | 消せない |
| 前提 | BreakGlass の導入と RCP | なし |

この時点のベースラインはガバナンスだった。期間を長くするほど、コンプライアンスは「二度と消せない」に近づくため。

### 2.3 可変の保持期間（解除の後 30 日）で比べた場合（決定に使った）

| | ガバナンス | コンプライアンス |
|---|---|---|
| BreakGlass の誤操作・乗っ取り | 迂回ですぐ消せる可能性がある（試しの Q2） | 解除して 30 日待つまで、誰も消せない。そのあいだに検知できる |
| 守りが効く前提 | BreakGlass と RCP が入ってから | BreakGlass の議論を待たずに効く |
| 設定の誤り・急いで消したいとき | すぐ直せる | 解除して 30 日待つ |
| 後からモードを変えるとき | 既存の版の変更に、再び Batch Operations（約 $3,900）が要る | 戻せない |

可変の保持期間にしたことで、コンプライアンスの取り返しのつかない範囲が「30 日待つ」に収まった。これでコンプライアンスに決めた。

### 2.4 ガバナンスで迂回できる主体（2026-10-30 時点）

ガバナンスで止まるのは、`s3:BypassGovernanceRetention` を持たない主体だけ。今これを持つのは、ステージ 1 のバケットポリシーの例外とほぼ同じ顔ぶれ。

- SSO の FullAccess（13 名）と AWSAdministratorAccess（`s3:*` に含まれる）
- deploy の経路（cfn-exec-role は AdministratorAccess）
- root

迂回の権限を絞らないかぎり、ガバナンスで増える守りは 2 つだけ。ライフサイクルに Expiration を混ぜる攻撃（調査の G08）が効かなくなることと、バージョニングを止められなくなること。

## 3. 解除の後に守る日数の比較（決定 3' のため）

| 日数 | 利点 | 欠点 |
|---|---|---|
| 7 日 | 早く消せる | 気づくのが遅れると間に合わない |
| **30 日** | 長い休みをまたいでも、検知と通知で気づいて止められる | 消すのが 30 日遅れる |
| 90 日 | 最も安全 | 間引きなどで消すのに 3 か月かかる |

費用への影響は「消すのが N 日遅れる」分だけ。

## 4. 可変の保持期間の仕様（AWS のドキュメント、2026-10-30 に確認）

### 4.1 設定の形

バケットの既定（`PutObjectLockConfiguration`）。CLI の例をそのまま写す。

```json
{
  "ObjectLockEnabled": "Enabled",
  "Rule": {
    "DefaultRetention": {
      "Mode": "COMPLIANCE",
      "Days": 365,
      "DefaultEventHold": {"Days": 90}
    }
  }
}
```

- `DefaultRetention` は `Mode`・`Days` か `Years`・`DefaultEventHold`（`Days` か `Years`）を持つ。
- コンソールの説明では、既定の期間は最低の期間: "Each new object stays protected for at least this period, even if its event hold is released earlier."
- `Days` と `DefaultEventHold.Days` のそれぞれの意味、`Days` を省けるかは、ドキュメントからは読み切れない（試しの Q1）。
- 既定を外すには `{"ObjectLockEnabled":"Enabled"}`（`Rule` なし）を設定する。

版ごと（`PutObjectRetention`）:

```bash
# かける
aws s3api put-object-retention --bucket B --key K \
  --retention '{"Mode":"COMPLIANCE","EventHold":"ON","EventHoldDuration":{"Days":30}}'
# 解除（日数は書かない）
aws s3api put-object-retention --bucket B --key K \
  --retention '{"Mode":"COMPLIANCE","EventHold":"OFF"}'
```

- 書き込むときにも付けられる: `put-object --object-lock-mode COMPLIANCE --object-lock-event-hold ON --object-lock-event-hold-duration-days 30`。
- 版ごとの日数の範囲は 1〜36,500 日、または 1〜100 年。保持期間の上限は 100 年。1 年は 365 日として数える。
- 解除のときに日数を書いてはいけない: "Don't specify an event hold duration when you release an event hold."

### 4.2 挙動

- ホールド中: 保持期限は「今 ＋ 決めた日数」として計算され、`GetObjectRetention`・`HeadObject`・`GetObject` で返る。
- 解除: "Amazon S3 sets the final retain-until-date to the release time plus the configured duration."
- 日数を縮めても、保持期限は前に戻らない: "Amazon S3 does not set the retain-until-date to an earlier date than its current value."
- 最低の日付（`RetainUntilDate`）も付けると、「その日付」と「解除の時刻 ＋ 日数」の遅いほうになる。
- ガバナンスとコンプライアンスの両方で使える。ホールドにはモードが要る。
- ガバナンスの迂回が、解除前のホールドにも効くか → 書かれていない（試しの Q2）。
- コンプライアンスで、解除が「期間の短縮」として拒まれないか → 書かれていない（試しの Q4）。

### 4.3 権限と通知

- 権限は `s3:PutObjectRetention`。新しいアクションは無い。
- 条件キー:
  - `s3:object-lock-event-hold`（`ON`・`OFF`）で、誰が付け外しできるかを絞れる。
  - `s3:object-lock-event-hold-duration-days` で、日数の上限・下限を強制できる。
  - これらは、バケットの既定でかかるホールドには効かない。既定を守るには `s3:PutBucketObjectLockConfiguration` を Deny する。
- `HeadObject` の応答ヘッダー: `x-amz-object-lock-mode`・`x-amz-object-lock-retain-until-date`・`x-amz-object-lock-event-hold`・`x-amz-object-lock-event-hold-duration-days`（または `-years`）。どれも `s3:GetObjectRetention` が要る。
- イベント通知: "Amazon S3 publishes an `s3:ObjectRetention:Put` event notification for explicit `PutObjectRetention` calls. This includes setting fixed or variable retention, releasing an event hold, modifying the duration, and extending a retain-until-date."
- CloudTrail での解除のイベント名は書かれていない（`PutObjectRetention` と見込む）。
- S3 Inventory はホールドの状態を出せる。最大 48 時間遅れる。

### 4.4 そのほか

- 追加の費用は無い。全リージョン（中国を含む）で使える。
- Cohasset Associates が、SEC Rule 17a-4(f)・FINRA Rule 4511・CFTC Regulation 1.31 への適合を評価している。
- レプリケーション: ホールドと日数は複製される。解除も複製され、複製先は複製した時刻から日数を数える。
- ライフサイクルは、鍵のかかった版を消せない。削除マーカーは守られない。

### 4.5 書き込みのチェックサムのヘッダー

- "The `Content-MD5` or `x-amz-sdk-checksum-algorithm` header is required for any request to upload an object with a retention period configured using Object Lock."
- "If you use the PutObject API you must specify the `Content-MD5` header, the `x-amz-sdk-checksum-algorithm` header, or both to configure the Object Lock retention period."
- バケットの既定でかかる場合にも要るかは、書かれていない（試しの Q5）。

## 5. 道具の対応（2026-10-30 に確認）

| 道具 | 対応 | 確かめ方 |
|---|---|---|
| CloudFormation `AWS::S3::Bucket` | `DefaultRetention` に `Years`・`Days`・`Mode`・`DefaultEventHold`（`Years`・`Days`）がある | `aws cloudformation describe-type` のスキーマ |
| AWS CLI 2.38.5 | `put-object-retention`・`put-object-lock-configuration`・`put-object` が、ホールドのフィールドを受け付ける | `--generate-cli-skeleton` |
| S3 Batch Operations | `S3PutObjectRetention` の `Retention` が `EventHold`・`EventHoldDuration` を受け付ける | `s3control create-job --generate-cli-skeleton` |
| CDK | CloudFormation に対応があるので、入れられる見込み（未確認） | — |

## 6. 対象の 12 本の今の設定（2026-10-30、ReadOnly で確認）

`readonly` プロファイル（tuscenes-prod の SSO の ReadOnly）で見た。12 本とも us-west-2。

| 確かめたこと | 結果 | Object Lock への影響 |
|---|---|---|
| Object Lock | 12 本とも未設定 | なし。後から有効にできる |
| バージョニング | 12 本とも有効 | 前提を満たす |
| ライフサイクル | Intelligent-Tiering への移動だけ（denso-raw は `tmp/` だけ。tuscenes-calibration（新）は規則なし）。Expiration・`NoncurrentVersionExpiration` は無い | ぶつからない。移動は鍵のかかった版にも効く |
| Intelligent-Tiering のアーカイブ層 | 12 本とも設定なし | アーカイブ層のオブジェクトに鍵をかける手間は無い |
| サーバーアクセスログ | アカウントのどのバケットも、ログを出していない | 書き込み先の制約に当たらない |
| レプリケーション | 12 本とも無し | 複製先の手当ては要らない |
| 暗号化 | 11 本は SSE-S3。tuscenes-calibration（新）は SSE-KMS で、鍵は AWS 管理キー（`aws/s3`） | AWS 管理キーは利用者が消せないので、鍵の削除の心配は無い |
| S3 Inventory（今の版） | td1-raw（毎日）・tuscenes-raw（毎週）・denso-taxi-video（毎日）。出力先は `s3-inventory-results-767397804933` | Batch Operations の対象の一覧に使える。残りの 9 本は、Inventory を足すか、一覧の生成を使う |
| イベント通知 | Databricks の自動取り込み（td1-raw・tuscenes-raw・tuscenes-annotation）、`csms-topic-by-path-…`（gaming-data-collection・denso-nx-raw・denso-taxi-processed）、EventBridge（tuscenes-model） | 影響なし。書き込みの経路を確かめるときの手がかりになる |

件数（CloudWatch の `NumberOfObjects`、2026-10-30 の直近の値）:

| バケット | 件数 |
|---|---|
| td1-raw | 385,947,691 |
| tuscenes-raw | 205,524,662 |
| denso-taxi-video | 19,694,561 |
| tuscenes-annotation | 13,268,616 |
| denso-taxi-processed | 11,264,019 |
| denso-raw | 9,217,039 |
| td1-rlog | 4,557,929 |
| tuscenes-model | 543,008 |
| tuscenes-calibration（旧） | 271,914 |
| denso-nx-raw | 188,139 |
| gaming-data-collection | 77,667 |
| tuscenes-calibration（新） | 354 |
| **計** | **650,555,599** |

- この件数は古い版も含むとみられる。ただし、バージョニングを入れたのは 2026-10-20 で、LiDAR の間引き（2026-08〜09）はその前なので、古い版はほとんど無い。今の版だけに絞っても、件数はほぼ減らない。
- 既存の版にかける費用の見込み: Batch Operations の 1 件あたりの料金で約 $650、`PutObjectRetention` のリクエスト（PUT の料金、1,000 件あたり $0.005）で約 $3,250。**計 約 $3,900。** td1-raw と tuscenes-raw で 9 割を占める。
- 未確認: `PutObjectRetention` の料金が、Intelligent-Tiering の低頻度層のオブジェクトでも PUT の料金で済むか。

## 7. 出典

- [Amazon S3 Object Lock now supports variable retention with event holds](https://aws.amazon.com/about-aws/whats-new/2026/09/amazon-s3-object-lock-variable-retention/)（2026-09-08）
- [Locking objects with Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)
- [Configuring S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-configure.html)
- [Object Lock considerations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-managing.html)
- [PutObjectRetention](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutObjectRetention.html)・[PutObjectLockConfiguration](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutObjectLockConfiguration.html)・[HeadObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_HeadObject.html)（API リファレンス）
- [Amazon S3 pricing](https://aws.amazon.com/s3/pricing/)
