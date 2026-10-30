# 原本バケットの WORM 化の設計

- 作成: 2026-10-30 ／ 伊藤
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md) の TODO 26
- 前提の資料: [S3 Object Lock（WORM）の整理](../../documents/notion-s3-object-lock.md)（以下「整理」。章の番号はこの資料のもの）

整理の 8 章「決めること」への回答と、そこから出てくる論点をまとめる。内部の検討の記録で、チーム向けの資料は別に作る。

## 1. 決めたこと（2026-10-30、伊藤）

| # | 決めること | 決定 |
|---|---|---|
| 1 | 対象 | **原則として原本バケット 12 本すべて** |
| 2 | モード | **要議論。ベースラインはガバナンス** |
| 3 | 鍵の期間 | **時間がたっても鍵が外れないこと。外すには、記録に残る明示的な操作が要ること。** 期間の長さそのものは要件にしない（期限を決める意味が薄いため）。**可変の保持期間（イベントホールド）を使う（案 A、2026-10-30）**。当初は「無期限」と書いたが、要件を言い直した |
| 4 | 消す必要が出たときの手順 | 想定するケースを列挙しておく（4 章）。今は個人情報も、契約終了で消すものも無い |
| 5 | 既存の版にさかのぼるか | **古い版（noncurrent）は不要。今ある今の版（current）だけに鍵をかける** |
| 6 | アカウントの閉鎖への備え | **備えない。** 閉鎖の操作の保護は別の議論 |

- 5 の読み方は「既存のオブジェクトの今の版には Batch Operations で鍵をかけ、古い版にはかけない」とした（要確認）。

対象の 12 本（バケット名の `-767397804933` は省略。`tuscenes-calibration`（旧）と `td1-rlog` は接尾辞なし）:

| バケット | 種別 | 入れ方の見込み |
|---|---|---|
| td1-raw | S1 | cdk-apps（Datalake） |
| tuscenes-raw | S1 | cdk-apps（Datalake） |
| td1-rlog | S1 | AWS CLI |
| gaming-data-collection | S1 | cdk-apps |
| tuscenes-calibration（旧） | S1 | AWS CLI |
| tuscenes-calibration（新） | S1 | cdk-apps（Datalake） |
| denso-taxi-video | S2 | cdk-apps（DensoTaxiStack） |
| denso-nx-raw | S2 | cdk-apps（DensoNx） |
| denso-raw | S2 | AWS CLI |
| denso-taxi-processed | S2 | cdk-apps（DensoTaxiStack） |
| tuscenes-model | S3 | 要確認（第一弾では手を入れていない） |
| tuscenes-annotation | S4 | cdk-apps（Datalake） |

## 2. 決定を組み合わせて出てくる論点

### 2.1 「時間がたっても外れない鍵」をどう表すか → 可変の保持期間（決めた）

要件は「時間がたっても鍵が外れない。外すには、記録に残る明示的な操作が要る」（決定 3）。期間の長さは要件にしない。

| 案 | 時間がたつと外れるか | 消すときの操作 | 評価 |
|---|---|---|---|
| **A. 可変の保持期間（イベントホールド）** | 外れない。解除するまで守られる | ホールドを解除し、決めた日数を待つ | **採る（2026-10-30）** |
| B. 100 年の固定の保持期間 | 100 年後に外れる（実質的に外れない） | ガバナンスの迂回で消す | 予備。A が試しで使えなかったときに切り替える |
| C. 短い固定の保持期間を定期的に延ばす | 延ばし忘れると外れる | 迂回で消す | 「いつの間にか消せる」そのものなので採らない |
| D. リーガルホールド | 外れない | `s3:PutObjectLegalHold` で外す | バケットの既定にできず、書き込む側がすべて付ける必要があるので使えない |

A を採る理由:

- 鍵を外すこと（ホールドの解除）が、記録に残る操作になる。解除しても決めた日数は誰も消せず、そのあいだに検知して止められる。
- モードの議論（決定 2）の余地が残る。B をコンプライアンスにすると「100 年誰も消せない」になり、事実上選べない。A なら、コンプライアンスでも「解除して N 日待てば消せる」。
- 4 章のケースの消し方を「解除して待つ」の 1 本にまとめられる。原則 2 の直し（2.3）も同じ形で書ける。

ドキュメントと手元の道具で確かめたこと（2026-10-30）:

- バケットの既定は `ObjectLockConfiguration.Rule.DefaultRetention` に `Mode`・`Days`（または `Years`）・`DefaultEventHold.Days`（または `Years`）を書く。版ごとの設定は `PutObjectRetention` の `Retention` に `EventHold`（`ON`/`OFF`）と `EventHoldDuration` を書く。
- 解除すると、保持期限が「解除した時刻 ＋ 決めた日数」になる。ホールド中は「今 ＋ 決めた日数」と計算された日付が返る。
- 権限は `s3:PutObjectRetention`（新しいアクションは無い）。条件キー `s3:object-lock-event-hold` で、誰が付け外しできるかを絞れる。ただし、バケットの既定でかかるホールドには効かない。
- 解除は `s3:ObjectRetention:Put` のイベント通知になる。
- 費用は追加なし。全リージョンで使える。
- CloudFormation の `AWS::S3::Bucket` は `DefaultEventHold` に対応している（スキーマで確認）。CDK でも入れられる見込み。
- Batch Operations の `S3PutObjectRetention` は `EventHold`・`EventHoldDuration` を受け付ける（CLI 2.38.5 の入力の形で確認）。既存の版にもかけられる見込み。

ドキュメントに書かれておらず、試して確かめること（[worm-probe-runbook.md](worm-probe-runbook.md)）:

1. バケットの既定の `Days` と `DefaultEventHold.Days` の意味の違い（最低の保持期間と、解除後の期間か）。`Days` を省けるか。
2. ガバナンスモードで、迂回の権限があればホールド中の版を直接消せるか。解除に迂回の権限が要るか。
3. コンプライアンスモードで、ホールドを解除できるか（解除が「期間の短縮」として拒まれないか）。
4. 書き込みの経路にチェックサムのヘッダーが要るか（バケットの既定でかかる場合）。

### 2.2 ガバナンスの強さは「迂回できる主体」で決まる

ガバナンスモードで止まるのは、`s3:BypassGovernanceRetention` を持たない主体だけ。今これを持つのは次のとおりで、**ステージ 1 のバケットポリシーの例外とほぼ同じ顔ぶれ**になる。

- SSO の FullAccess（13 名）・AWSAdministratorAccess（`s3:*` に含まれる）
- deploy の経路（cfn-exec-role は AdministratorAccess）
- root

さらに、**S3 のコンソールは迂回のヘッダーを自動で付ける**。FullAccess の人がコンソールで版を消すと、鍵は効かない。

したがって、ガバナンスを入れるだけで増える守りは次の 2 つに限られる。

- ライフサイクルに Expiration を混ぜる攻撃（調査の G08）が効かなくなる。
- バージョニングを止められなくなる。

ガバナンスを実質的な守りにするには、迂回の権限を BreakGlass だけに絞る必要がある。

- **バケットポリシー（すぐできる）:** `s3:BypassGovernanceRetention`・`s3:PutObjectRetention`・`s3:PutObjectLegalHold`・`s3:PutBucketObjectLockConfiguration` を、例外の主体以外に Deny する。ステージ 1 の 2 文に足す形になる。ただし、例外が FullAccess のうちは効果が小さい。BreakGlass への差し替え（提案の手順 7）が済んでから意味を持つ。
- **RCP（TODO 24）:** バケットポリシーを消されても効く。整理の案 A。
- deploy の経路から迂回を拒否するとき、CloudFormation が `PutBucketObjectLockConfiguration` を呼べなくなる。鍵の設定をバケットに入れる順番に注意する（先に CDK で有効にし、後から Deny を足す）。

### 2.3 ライフサイクルで消す運用と両立しない

第二弾の原則 2 は「意図して大量に消すときはライフサイクルで消す」としている。しかし、ライフサイクルは鍵のかかった版を消せない。**ホールドがかかっているあいだ、ライフサイクルでは原本を消せない。**

- 大量に消すときは、Batch Operations でホールドを解除し、決めた日数を待ってから、ライフサイクルか Batch Operations で消す形に変わる。解除を誰に許すか（BreakGlass だけか）は 2.2 と合わせて決める。原則 2 と、BreakGlass の提案の「BreakGlass 権限を使う場面」を直す必要がある。
- 古い版（鍵なし）は、これまでどおりライフサイクルの `NoncurrentVersionExpiration` で消せる。ただし、鍵のかかった今の版に削除マーカーを置いても、その版は古い版になるだけで、鍵は残る。

### 2.4 今の版だけに鍵をかける（決定 5）ことの意味

- 古い版は、これまでどおり例外の主体なら消せる。今の古い版は、ほとんどが LiDAR の間引きの名残（tuscenes-raw・td1-raw）と見込む。守る価値は低いので、決定と整合する。
- 対象の一覧は S3 Inventory（今の版だけ）から作る。件数と費用は 2.5（約 6.5 億件、約 $3,900）。
- 鍵をかける前（有効化から Batch Operations が終わるまで）に、今の版が守られない期間ができる。順番は「有効化と既定の保持期間 → 新しい書き込みに鍵がかかる → 既存の今の版に Batch Operations」。

### 2.5 対象のバケットごとの今の設定（2026-10-30、ReadOnly で確認）

`readonly` プロファイル（tuscenes-prod の SSO の ReadOnly）で 12 本を見た。12 本とも us-west-2。

| 確かめたこと | 結果 | Object Lock への影響 |
|---|---|---|
| Object Lock | 12 本とも未設定 | なし。後から有効にできる |
| バージョニング | 12 本とも有効 | 前提を満たす |
| ライフサイクル | Intelligent-Tiering への移動だけ（denso-raw は `tmp/` だけ。tuscenes-calibration（新）は規則なし）。Expiration・`NoncurrentVersionExpiration` は無い | **ぶつからない。** 移動は鍵のかかった版にも効く |
| Intelligent-Tiering のアーカイブ層 | 12 本とも設定なし | アーカイブ層のオブジェクトに鍵をかける手間は無い |
| サーバーアクセスログ | アカウントのどのバケットも、ログを出していない | 書き込み先の制約に当たらない |
| レプリケーション | 12 本とも無し | 複製先の手当ては要らない |
| 暗号化 | 11 本は SSE-S3。tuscenes-calibration（新）は SSE-KMS で、鍵は AWS 管理キー（`aws/s3`） | AWS 管理キーは利用者が消せないので、鍵の削除の心配は無い |
| S3 Inventory（今の版） | td1-raw（毎日）・tuscenes-raw（毎週）・denso-taxi-video（毎日）にある。出力先は `s3-inventory-results-767397804933` | Batch Operations の対象の一覧に使える。残りの 9 本は、Inventory を足すか、Batch Operations の一覧の生成を使う |
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

- この件数は古い版も含むとみられる。ただし、バージョニングを入れたのは 2026-10-20 で、LiDAR の間引き（2026-08〜09）はその前なので、古い版はほとんど無い。**今の版だけにしても、件数（と費用）はほぼ減らない。**
- 費用の見込み: Batch Operations の 1 件あたりの料金で約 $650、`PutObjectRetention` のリクエスト（PUT の料金、1,000 件あたり $0.005）で約 $3,250。**計 約 $3,900。** td1-raw と tuscenes-raw で 9 割を占める。

まだ確かめていないこと:

- [ ] 書き込みの経路が、`Content-MD5` かチェックサムのヘッダーを付けるか（Databricks、DataSync、Azure からの転送〈denso-nx-raw〉、手元のマシンからのアクセスキーでの書き込み〈gaming-data-collection〉、学習のジョブ〈tuscenes-model〉、アノテーションの取り込み〈tuscenes-annotation〉）。バケットの既定の保持期間で鍵がかかる場合も要るのかを、使い捨てのバケットで確かめる
- [ ] `PutObjectRetention` の料金が、Intelligent-Tiering の低頻度層のオブジェクトでも PUT の料金で済むか

## 3. モードの議論のための材料（決定 2）

ベースラインはガバナンス。コンプライアンスにするかは議論する。

| | ガバナンス（＋迂回を BreakGlass に絞る） | コンプライアンス |
|---|---|---|
| 例外の主体・deploy の経路・root | BreakGlass 以外は止まる | 止まる |
| BreakGlass 自身の誤操作・乗っ取り | **通る**（コンソールなら自動で迂回） | 止まる |
| 設定を誤ったとき | BreakGlass で直せる | ホールドを解除して決めた日数を待てば消せる（試しの 3 で確かめる）。モードは戻せない |
| 消す必要が出たとき（4 章） | BreakGlass で消せる | **消せない** |
| 前提 | BreakGlass の導入（提案の手順）と RCP | なし |

- 可変の保持期間なら、コンプライアンスでも「解除して決めた日数を待てば消せる」。違いは、解除の後に迂回で早く消せるかどうかと、モードを戻せるかどうか。
- 中間の形として、ガバナンスで始め、運用が固まったバケットだけ後からコンプライアンスに移せる（ガバナンス → コンプライアンスは移せる。逆はできない）。

## 4. 消す必要が出る想定ケース（決定 4）

今は、どれも起きていない（2026-10-30、伊藤）。ガバナンスなら、どれも BreakGlass で対応できる。コンプライアンスなら、どれにも応じられない。

| # | ケース | 今の見込み | 起きたときの対応（ガバナンスの場合） |
|---|---|---|---|
| 1 | **個人情報の削除依頼**（走行映像に写った人・ナンバープレートの本人から） | 今は個人情報として扱うデータが無い | BreakGlass が該当の版を迂回して消す。映像の加工で済むなら、新しい版を書く |
| 2 | **契約の終了による消去・返却**（DENSO のデータ〈S2〉など、他社から受け取ったデータ） | 今は該当なし | BreakGlass が Batch Operations でプレフィックスやバケットごと消す |
| 3 | **費用の削減のための間引き**（LiDAR の間引き〈2026-08〜09 に tuscenes-raw で約 6.2 億件〉の再開など） | 過去に実績あり | BreakGlass が Batch Operations で消す（2.3） |
| 4 | **誤って書いたデータ**（テストのデータ・壊れたファイル・別のバケット宛てのもの） | 起こりうる | 小さければ残す。大きければ BreakGlass が消す |
| 5 | **機密情報の混入**（認証情報・社外秘の文書などを誤って上げた） | 起こりうる | BreakGlass がすぐ消す。消せない間は、読める主体を絞る |
| 6 | **法令・当局の要請による削除** | 今は該当なし | BreakGlass が消す |
| 7 | **バケットの廃止・移行**（別のアカウントやリージョンへ移す、バケットを統合する） | 今は予定なし（tuscenes-calibration の旧から新への移行は、関係しうる） | 写してから、BreakGlass が元を消す。バケットそのものは、全版が消えるまで消せない |
| 8 | **鍵の設定の誤り**（期間・モードを誤った、対象でないバケットにかけた） | 導入の直後に起こりうる | BreakGlass が直す（ガバナンスの場合に限る） |

## 5. 残っていること

- [ ] 決定 5 の読み方の確認（今の版には鍵をかける、でよいか）
- [ ] モードの議論（3 章）
- [ ] 2.1 の確かめることを、使い捨てのバケットで試す（[worm-probe-runbook.md](worm-probe-runbook.md)）
- [x] 2.5 のバケットごとの確認（ReadOnly。2026-10-30。書き込みの経路のヘッダーは残り）
- [ ] 監査ログのバケット（`original-bucket-audit-logs-767397804933`）の扱い（整理の 9 章では、コンプライアンスの最初の対象にする案）
- [ ] 原則 2（ライフサイクルで消す）と、BreakGlass の提案の直し（2.3）
- [ ] バケットポリシーへの Deny の追加（2.2）を、ステージ 1 と BreakGlass の差し替えの手順のどこに入れるか
