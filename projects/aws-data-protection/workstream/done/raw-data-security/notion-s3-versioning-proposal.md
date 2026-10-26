# 走行データの S3 バケットに版管理を入れる提案

作成: 2026-10-16 ／ 伊藤

## この記事でお願いしたいこと

走行データの原本を、誤操作や不正な操作で消されても戻せる状態にします。そのために、S3 バケットに**版管理（Versioning）を入れたい**と考えています。

バケットごとの調査結果と処遇の案をまとめました。末尾の「合意したいこと」の 5 点について、**賛成か反対か（反対なら理由）**をコメントでお知らせください。

## 背景

- 走行データ消失リスクの調査（2026-10、安本さん）によると、原本約 3,667 TB の 99.5% に、版管理・Object Lock・レプリケーション・バックアップのどれもありません。
- 1 回の操作で、戻せない形で消せる経路が 12 本あります。削除は記録も検知もされません。
- 対策の案は数が多いので、次の順番で進めることにしました。

| 段階 | やること | 時期 |
|---|---|---|
| いますぐ | **版管理を入れる**（この記事） | すぐ |
| 次に | バケットポリシーで、削除系の操作を限られた主体以外に禁止する | 今週〜来週 |
| じっくり | 削除権限を持つ主体の洗い出しと掃除 | 期限なし |

## 版管理を入れると何が変わるか

- **普通の削除や上書きでは、データが消えなくなります。** 削除すると「削除マーカー」が付くだけで、元のデータは「古い版」として残ります。マーカーを外せば元に戻せます。
- **古い版は、決めた日数で自動的に消します**（ライフサイクルの `NoncurrentVersionExpiration`）。この日数が、そのまま「気づいて戻すまでの猶予」になります。
- **費用**
  - 版管理を有効にすること自体は無料です。
  - 費用がかかるのは、消したり上書きしたりしたデータが、古い版として残っている間だけです。
  - たとえば 100 TB を消すと、Intelligent-Tiering の深い層（月 0.004 ドル/GB）で月約 400 ドル、90 日で約 1,200 ドルです。
- **版管理だけでは止められない相手もいます。** 版を指定して消す権限（`s3:DeleteObjectVersion`）や、ライフサイクルを書き換える権限を持つ主体です。これは次の段階のバケットポリシーで塞ぎます。

## 調べ方

- tuscenes-prod（767397804933）を、ReadOnly の SSO と AWS CLI で、読み取り専用で調べました。設定は何も変えていません。
- 見たもの:
  - バケットの設定（版管理・ライフサイクル・ポリシー・Inventory など）
  - DataSync のタスクと実行履歴
  - CloudTrail の管理イベント（直近 90 日）
  - CloudWatch の日次の容量とオブジェクト数（過去 455 日）
  - cdk-apps の定義と履歴
- 利用状況（最終アクセス）は、最後の PUT・Intelligent-Tiering の層の動きから推定した読み出し・リクエストメトリクスの GET のうち、最も新しい日です。

## 対象のバケット

調査書で「原本（再収集できないもの）」とされ、版管理が無いバケットのうち、tuscenes-prod にある 10 本です。作り直せない音声を含む turing-video-ap-northeast-1 も、追加の候補にしています。

| バケット | 容量 | 中身 | 最終アクセス | 管理元 | 今消されたら | 提案 |
|---|---|---|---|---|---|---|
| td1-raw-767397804933 | 1,754 TB | TD1 の動画と rlog | 毎日（半年で GET 約 21 億回） | CDK `Datalake` | 戻せない | 版管理＋古い版 90 日 |
| tuscenes-raw-767397804933 | 914 TB | Turing Pilot v1 の動画と rlog（2025-04 に収集終了） | 2026-09 | CDK `Datalake` | 戻せない | 版管理＋古い版 90 日 |
| denso-taxi-video-767397804933 | 452 TB | タクシー動画（Azure 側の取り込み元は削除済み） | 2026-10 | CDK `DensoTaxiStack` | 戻せない | 版管理＋古い版 90 日 |
| turing-video-ap-northeast-1-767397804933 | 306 TB | 閲覧用の DASH 動画と commentary-audio | 2026-10 | CDK `VideoOrigin`（東京） | commentary-audio は戻せない | **追加の候補**。版管理＋古い版 90 日 |
| denso-nx-raw-767397804933 | 171 TB | DENSO NX の mcap | 2026-10 | CDK `DensoNx` | Azure から再転送できる見込みだった（下記の注意） | 版管理＋古い版 90 日 |
| databricks-workspace-e2e-bucket | 118 TB | Unity Catalog の管理テーブルの実体（約 2,880 表） | 毎日 | Databricks quickstart の CloudFormation | 戻せない | 版管理＋**古い版 7 日** |
| td1-rlog | 21 TB | 2024-10〜2025-04 の走行一式（唯一の原本） | 2025-09 | 手動 | 戻せない | 版管理＋古い版 90 日 |
| denso-raw-767397804933 | 15 TB | DENSO 納品の raw（7z） | 2026-04（少量） | 手動 | 戻せない | 版管理＋古い版 90 日 |
| tuscenes-annotation-767397804933 | 14 TB | 人手のラベル | 2026-10 | CDK `Datalake` | 戻せない | 版管理＋古い版 90 日 |
| denso-nx-sample-767397804933 | 6 TB | DENSO NX の mcap サンプル | 2026-05 | CDK `DensoNx` | 戻せない | 版管理＋古い版 90 日 |
| tuscenes-calibration | 1.3 TB | キャリブレーション（旧。新バケットに移っていない） | 2026-03 | 手動 | 戻せない | 版管理＋古い版 90 日 |
| （参考）tuscenes-calibration-767397804933 | ほぼ 0 | キャリブレーション（新） | — | CDK `Datalake` | 古い版で戻せる（失効なし） | 古い版 90 日を足す |

この表に無いもの:
- **amman-pipeline の amman-nbox-log-tmp（178 TB）と、e2e-dev の td1-raw-471112873671（27 TB）も原本です。** 別アカウントにあり、今回の権限では作業できないので、権限を持つ方に別途お願いします。
- 二次データ（作り直せるもの）と、1 年以上アクセスが無いバケットは、今回は後回しにします。

## 調査で分かったこと

### 全体

- 対象のどのバケットにも、版管理・Object Lock・レプリケーションがありません。版管理は、一時停止ではなく一度も ON にしたことがない状態です。
- ライフサイクルは、ほぼ全部が「Intelligent-Tiering への移行」だけです。Expiration は turing-video-ap-northeast-1 の `tmp/`（14 日）だけで、今 `tmp/` は空です。
  - したがって、「版管理を入れると Expiration が削除マーカーを付けるだけになり、容量が減らなくなる」問題は、実質起きません。
- **直近 90 日に、対象バケットのライフサイクル・ポリシー・版管理を変えたのは、すべて cdk deploy（cfn-exec-role）でした。** Databricks のロールや個人による変更はありません。

### 古い版はどれくらい増えるか

CloudWatch の日次の容量から、前日より減った分を足して見積もりました。上書きは見えないので、これは**下限**です。

| バケット | 直近 30 日の減少 | 直近 90 日の減少 | 見込み |
|---|---|---|---|
| databricks-workspace-e2e-bucket | 約 21 TB | 約 45 TB（減った日は 37 日） | 7 日で失効させても、古い版が常に数 TB ある |
| tuscenes-raw | 0 | 約 1,826 TB（08-31〜09-02 の LiDAR 間引き） | 間引きを再開しなければ、ほぼ増えない |
| td1-raw | 0 | 約 19 TB（08-28 の LiDAR 間引き） | 同上 |
| 残りの原本 | 0 | 0 | ほぼ増えない |

- **原本は、今の運用のままなら古い版はほぼ増えません。** 残す日数を 90 日にしても、費用はほとんど変わりません。
- 費用が増えるのは、databricks-workspace-e2e-bucket と、LiDAR の間引きを再開した場合です。
- 入れてから 1 週間後に Storage Lens で古い版の容量を確かめ、必要なら日数を見直します。

### バケットごとの注意点

**databricks-workspace-e2e-bucket**
- Databricks は、Delta Lake を置くバケットでは版管理を**推奨していません**。Delta 自身に版管理（time travel）があり、VACUUM で消すファイルまで S3 に残ってしまうためです。
  - 入れるなら「古い版は 3 つまで、7 日以内に消す」ライフサイクルにするよう勧めています。
  - 版管理による S3 API の遅延も報告されています。
  - 出典: [Delta Lake limitations on S3](https://docs.databricks.com/aws/delta/s3-limitations)、[Slow S3 API responses when using Delta Lake with versioning-enabled S3 buckets](https://kb.databricks.com/delta/slow-s3-api-responses-when-using-delta-lake-with-versioning-enabled-s3-buckets)
- 一方で、このバケットは SSO の約 40 名が、AWS 側から直接消せます。Delta の time travel は、Databricks の外で消されたファイルを戻せません。
- そこで、**推奨の上限の 7 日・3 版で入れ、遅くならないかを見る**ことを提案します。
- 管理しているのは Databricks の quickstart が 2024-08 に作った CloudFormation で、それ以来更新されていません。CLI で設定しても、上書きされる心配はありません。

**denso-nx-raw**
- Azure から毎日取り込む DataSync のタスクは、「変わったファイルだけを上書きし、削除はしない」設定です。直近 10 回は転送が 0 件なので、版管理を入れても余分な版はほぼできません。
- **気になる事実があります。** このタスクが毎回スキップしている件数（＝転送元の Azure にあるファイル数）が、10-14 の 187,810 件から、10-15 以降は 5,946 件に減っていました。
  - 「Azure に原本が残っているので、消えても再転送できる」という前提が、崩れているかもしれません。

**denso-taxi-video**
- DataSync のタスクは、無効になっているか、スケジュールがありません。最後の実行は 2026-09-19 で、転送は 0 件でした。

**turing-video-ap-northeast-1**
- 中身は `media/`（閲覧用の DASH 動画。作り直せる）と、`commentary-audio/`（作り直せない）です。
- 版管理はバケット単位なので、`media/` も一緒に対象になります。ただ、今は上書きも削除もないので、費用はほぼ変わりません。

**td1-raw・tuscenes-raw（LiDAR の間引き）**
- LiDAR の間引きは中断中です。ただ、`LidarDeleter` ロールは、SSO の FullAccess（14 名）が今も使えます。最終使用は 2026-09-03 です。
- このロールの権限は `s3:DeleteObject` だけで、版を指定して消す権限はありません。
- そのため、版管理の後に間引きが再開されると、**データは消えずに古い版として残り、課金が続きます**（残り約 1.3〜1.6 PiB。月 100 万円前後）。

**tuscenes-calibration（旧）**
- 2026-05 に、IaC の参照先が新バケット（`tuscenes-calibration-767397804933`）に移りました。ただ、旧バケットの 1.26 TB は、新バケットに移っていません。
- 移すかどうかは別に決めることにして、今回は旧バケットにも版管理を入れます。

**Inventory**
- td1-raw・denso-taxi-video は日次、tuscenes-raw は週次で、S3 Inventory を取っています。いずれも現行の版だけです。
- 「何が消されたか」を後から追えるように、全部の版を含める設定に変えることも、後で検討します。

## 入れ方

| 管理元 | バケット | 入れ方 |
|---|---|---|
| cdk-apps（CDK） | td1-raw、tuscenes-raw、tuscenes-annotation、tuscenes-calibration（新）、denso-taxi-video、denso-nx-raw、denso-nx-sample、turing-video-ap-northeast-1 | cdk-apps の PR で `versioned: true` と、ライフサイクルに古い版の失効を足して deploy する |
| Databricks の CloudFormation | databricks-workspace-e2e-bucket | AWS CLI で設定する |
| 手動で作ったもの | td1-rlog、denso-raw、tuscenes-calibration（旧） | AWS CLI で設定する。ライフサイクルは全体が置き換わるので、今の Intelligent-Tiering の規則も含めて書く |

- **CDK 管理のバケットは、必ず cdk-apps 経由で入れます。** ライフサイクルをテンプレートで持っているので、手で足した失効の規則は、次の deploy で消えてしまうためです。
  - 前例として、tuscenes-model は同じ手順で版管理を入れています。
- CLI での作業は、書き込み権限を持つ方にお願いします（手順書を用意します）。
- 古い版の失効と一緒に、期限切れの削除マーカーを片付ける規則（`ExpiredObjectDeleteMarker`）も入れます。

## 合意したいこと

各項目に、**賛成／反対**をお願いします。

1. **原本の 10 本と tuscenes-calibration（新）に版管理を入れ、古い版は 90 日で消す。**
   - 原本の古い版は今はほぼ増えないので、90 日でも費用はほぼかかりません。
2. **turing-video-ap-northeast-1 も対象に入れる（古い版は 90 日）。**
   - 作り直せない commentary-audio を守るためです。費用はほぼ変わりません。
3. **databricks-workspace-e2e-bucket にも版管理を入れ、古い版は 7 日・3 版までにする。**
   - Databricks の推奨の上限に合わせます。遅くなったら一時停止します。
4. **`LidarDeleter` ロールの信頼ポリシーを外し、間引きが勝手に再開されないようにする。**
   - 再開を決めたときに戻せば済み、外している間に困ることはありません。
5. **denso-nx-raw の Azure 側のファイル数の減少を、denso-nx の担当の方に確かめていただく。**

合意ができたら、cdk-apps の PR と CLI の手順書を出します。
