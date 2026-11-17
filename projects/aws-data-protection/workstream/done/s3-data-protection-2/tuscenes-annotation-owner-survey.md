# tuscenes-annotation の関係者と削除の頻度（2026-11-16）

tuscenes-annotation-767397804933 だけ、Object Lock を入れるかの最終確認（アクション 4c-1）が済んでいない。確認のためのヒアリング先を探し、あわせて通常の削除（`DeleteObject`）の頻度を調べた。エージェントが ReadOnly で調べた。

## 決定（2026-11-16、伊藤）

**通常の削除がほとんど無いので、tuscenes-annotation にも WORM（Object Lock と既定の保持設定）を入れる**（D36）。自動の出力も含めてバケット全体に付ける。下のヒアリングの候補には、決める前の確認ではなく、入れる前の周知として知らせる（チェックサムを付けない道具を使わないことも合わせて）。

## 結論

- **10-30〜11-15 の 17 日間で、このバケットへの削除は 0 件**（`DeleteObject`・`DeleteObjects` とも）。同じトレイルで tuscenes-model の `DeleteObject` は記録されていたので、記録漏れではない。
- 書き込みは約 74 万件で、すべて自動の処理の出力か、開発者が手で置いたものだった。**人手のラベル（外注の成果物）への書き込みは 0 件**。
- 同じキーへの上書きは 741 キー・計 28,019 回あった。上書きは Object Lock の下でも通る（新しい版ができ、古い版が残るだけ）。古い版は、今もバケットポリシーで例外の主体（FullAccess など）を除いて消せない。ライフサイクルには古い版を消す規則も無い。そのため、Object Lock を入れても容量の増え方は変わらない。
- ライフサイクルは Intelligent-Tiering への移行だけで、期限切れによる削除は無い。

このため、Object Lock を入れても書き込み元が困ることは、トレイルの上では見当たらない。

## バケットの中身（最上位のプレフィクス）

| プレフィクス | 中身 | 書き手（17 日間） |
|---|---|---|
| `object_detection/appen/` | 外注（Appen）の人手のラベル。4,029 件、最終更新 2025-07-04。古い版・削除マーカー 0 | なし |
| `object_detection/linker_vision/` | 外注（Linker Vision）の人手のラベル。5 件、2024-07-16 | なし |
| `object_detection/v2.5.11/` | JADD の v2.5.11 の変換物（2026-05） | なし |
| `object_detection/auto_label/` | 物体検出の自動ラベル | PerceptionDetection のジョブ・Lambda、イバイさん（手） |
| `object_detection/frame_records/`・`migration_backups/` | 自動ラベルの補助・移行の控え（2026-07〜10） | なし |
| `lane_master_kun/`・`lane_master_kun_v2/` | 車線の自動ラベル（v2 は 11-09 から） | PerceptionDetection の Lane のジョブ・Lambda、川村さん（手、v2） |
| `localization/` | 位置推定の毎晩の出力（`odometry/`）、開発用の試し出力（`dev-loader-canary/`）、航空写真（`imagery/`）、参照・取り込み・実験 | LocalizationNightly のジョブ・メタデータ、イバイさん（手） |
| `semantic_masks/` | セマンティックマスク（2026-09） | なし |
| `models/` | Cosmos-Reason1-7B のモデルの写し（2026-07） | なし |

## 書き込みの内訳（10-30〜11-15、`PutObject`・`CopyObject`・`CompleteMultipartUpload`）

| 書き手 | プレフィクス | 件数 |
|---|---|---|
| LocalizationNightly のジョブのロール | `localization/odometry` | 487,943 |
| SSO TeamE2E（ibai.gorordo） | `localization/imagery` | 81,501 |
| LocalizationNightly のメタデータのロール | `localization/odometry` | 24,200 |
| LocalizationNightly のジョブのロール | `localization/dev-loader-canary` | 23,948 |
| SSO TeamE2E（masaki.kawamura） | `lane_master_kun_v2/auto_label` | 14,437 |
| PerceptionDetection のジョブのロール | `object_detection/auto_label` | 10,437 |
| PerceptionDetection の Lane のジョブのロール | `lane_master_kun/`・`lane_master_kun_v2/` | 16,752 |
| SSO TeamE2E（ibai.gorordo） | `object_detection/auto_label`・`localization/`（そのほか） | 10,765 |
| PerceptionDetection の Lambda（PlanJobs 2 本） | 各 `auto_label` | 2,020 |

上書きのあったキーは `localization/odometry`（269）・`lane_master_kun/auto_label`（252）・`object_detection/auto_label`（196）に多い。エラーは `PreconditionFailed` 6 件（条件付きの書き込み）と `InternalError` 2 件だけ。

## 知らせる相手（当初はヒアリングの候補）

| 人 | 関わり | 聞くこと |
|---|---|---|
| イバイ（Ibai Gorordo）さん | perception-detection の作者（cdk-apps の [cdk-apps#998](https://github.com/turingmotors/cdk-apps/pull/998) ほか 14 コミット）。localization の毎晩の処理（[cdk-apps#2366](https://github.com/turingmotors/cdk-apps/pull/2366) など）。手での書き込みも最も多い | 物体検出・位置推定の自動の出力と、開発用の試し出力（`dev-loader-canary/`・`restoration/experiments/`）が消せなくなってよいか。いずれ消すつもりの出力はあるか |
| 川村（Masaki Kawamura）さん（GitHub `Masakichi210`） | 車線の自動ラベル（lane nightly の v3・v4、[cdk-apps#2464](https://github.com/turingmotors/cdk-apps/pull/2464) で `lane_master_kun_v2/` を追加）。手での書き込みもある | `lane_master_kun/`（v1）を消す予定はあるか。自動の出力が消せなくなってよいか |
| 塚本 周平さん | バケットを作った（[cdk-apps#7](https://github.com/turingmotors/cdk-apps/pull/7)、2025-01） | 外注のラベル（Appen・Linker Vision）を誰が入れたか、ほかに写しがあるか |
| 安本さん | 対象に戻すよう求めた（D30） | 守りたいのは人手のラベルだけか、バケット全体か |

- 外注のラベルを入れた人は、まだ分かっていない（トレイルの記録は 10-30 から。Notion の検索は notion-guard が許していない）。
- 中村 優斗さん（`yutyan0119`）は lane_master_kun の最初の PR（[cdk-apps#1671](https://github.com/turingmotors/cdk-apps/pull/1671)、Devin が作成）をマージした人。当面のヒアリングの対象には入れていない。

## 調べ方

- トレイル: `original-bucket-audit-logs-767397804933` の `trail/`（書き込み系のデータイベント。記録は 10-30 から）を 10-30〜11-15 の 17 日分（約 4.4 GB）落として集計した。11-16 は Batch Operations の記録で 23 GB あり、対象から外した。スクリプトは scratchpad に置いた（残していない）。
- バケット: `list-objects-v2`（最上位と 2 階層目）、`get-bucket-lifecycle-configuration`、外注の 2 プレフィクスの `list-object-versions`。
- コード: cdk-apps の `git log -S tuscenes-annotation`、`apps/datalake`・`apps/perception-detection`。mono-e2e では、外注のプレフィクスを参照するコードは見つからなかった。
- 10-30 より前の削除は分からない（データイベントの記録が無い）。
