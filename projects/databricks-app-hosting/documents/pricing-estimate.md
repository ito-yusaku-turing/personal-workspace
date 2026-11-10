# Databricks の料金体系と試算（アプリのホスティング）

- 作成: 2026-11-10
- 単価の出どころ: Databricks の公式の料金の計算機のデータ（`https://www.databricks.com/en-pricing-assets/data/pricing/AWS.json`）と、料金のページ（[Databricks Apps](https://www.databricks.com/product/pricing/databricks-apps)・[Lakebase](https://www.databricks.com/product/pricing/lakebase)・[Storage](https://www.databricks.com/product/pricing/storage)）の本文。2026-11-10 に取得した。
- **定価（従量課金の一覧価格）**。社の契約の割引は入っていない。社の実際の単価は、Workspace の `system.billing.list_prices` か、アカウントの担当者で確かめる。
- 金額はすべて米ドル。1 か月は 730 時間で数える（Databricks の料金のページと同じ）。

## 前提

- **社の Databricks の Workspace（`dbc-24f125d6-4420`）は us-west-2（オレゴン）にある**（2026-11-10、DNS で確かめた。`oregon.cloud.databricks.com` の別名）。データの本体もオレゴンにある。
- 東京に置くなら、東京（ap-northeast-1）に別の Workspace が要る。Apps も Lakebase も、Workspace のリージョンで動く。
- 社のプラン（Premium / Enterprise）は確かめていない。下では両方を出す。

## 料金体系

| 何に払うか | 課金の単位 | 決まり方 |
|---|---|---|
| **Databricks Apps**（アプリを動かす計算機） | DBU。請求では「Interactive Serverless」（または All-Purpose Serverless）の SKU に載る | **動いている時間 × 大きさ**。Medium（2 vCPU・6 GB）0.5 DBU/時、Large（4 vCPU・12 GB）1 DBU/時、XLarge（12 vCPU・48 GB）3 DBU/時。台数を増やすと台数倍。使われていなくても、動いていれば課金される |
| **Lakebase の計算機**（Postgres） | CU 時間（1 CU は RAM 2 GB）。請求では「Database Serverless Compute」の DBU に換算される | 実際に使った CU 時間。自動で伸び縮みし、止められる（scale to zero）。高可用性（HA）の分の CU 時間も数える |
| **Lakebase のストレージ** | DSU（Databricks Storage Unit） | DB の本体 1 GB・1 か月あたり 15 DSU、時点への復元（PITR）の履歴 8.60 DSU、スナップショット 3.91 DSU |
| Unity Catalog → Lakebase の同期（synced tables） | DBU（裏で動くサーバーレスのパイプライン） | 使ったときだけ |
| データの転送 | クラウドの転送料 | リージョンをまたぐとき・外に出すときにかかりうる（料金のページの「Data transfer and connectivity」。単価は見ていない） |

補足:

- **Lakebase は 2027-01-31 まで 50% 引き**（"Promotion - Save 50% off price shown below until January 31, 2027"）。下の試算は割引前の定価で出す。
- Lakebase は、scale to zero を 24 時間を超えて切ったままにすると「Always-on」の料金になる。最低の容量のぶんが安い単価になる（単価は取れていない）。
- Apps の料金のページの例: 「Medium のアプリ 5 個を 30 日 24 時間、AWS Premium の US East で動かすと 1,800 DBU、$0.75/DBU で月 $1,350」。

## 単価（定価）

| リージョン・プラン | Apps（Interactive Serverless）$/DBU | Medium 1 台・1 時間 | Lakebase $/CU 時間 |
|---|---|---|---|
| 東京 Premium | 0.83 | $0.415 | 0.110 |
| 東京 Enterprise | 1.05 | $0.525 | 0.134 |
| オレゴン Premium | 0.75 | $0.375 | 0.092 |
| オレゴン Enterprise | 0.95 | $0.475 | 0.111 |

- 東京は、オレゴンより Apps で約 1.1 倍、Lakebase で約 1.2 倍高い。
- DSU の単価は公式のデータでは見つからなかった。外部の記事では、AWS の US East の Premium で $0.023/DSU（[Coupler.io](https://blog.coupler.io/?p=85874) ほか。**未確認**）。この単価だと、Lakebase の DB の本体は 1 GB・1 か月あたり $0.345。東京の DSU の単価は分からない。

## 試算（アプリ 1 つあたりの月額、定価）

置いた前提:

- アプリ: Medium 1 台。
- DB: Lakebase 2 CU（新しく作ったときの既定の範囲「2〜4 CU」の下限）。DB の大きさは 50 GB と置いた（jadd_studio3・fleet-ops のいまの DB の大きさは確かめていない）。
- 「業務時間だけ」は平日 8〜22 時（14 時間 × 21 日 = 294 時間）だけ動かす場合。Apps を時間で止めて起動し直す運用ができるかは確かめていない。Lakebase は scale to zero で止まる。

| 構成 | 東京 Premium | 東京 Enterprise | オレゴン Premium | オレゴン Enterprise |
|---|---|---|---|---|
| Apps Medium・24 時間 | $303 | $383 | $274 | $347 |
| Apps Medium・業務時間だけ | $122 | $154 | $110 | $140 |
| Apps Large・24 時間 | $606 | $766 | $548 | $694 |
| Lakebase 0.5 CU・24 時間 | $40 | $49 | $34 | $41 |
| Lakebase 2 CU・24 時間 | $161 | $196 | $134 | $162 |
| Lakebase 2 CU・業務時間だけ | $65 | $79 | $54 | $65 |
| ストレージ 50 GB（DSU を $0.023 と置く） | $17 | $17 | $17 | $17 |
| **合計: 24 時間（Apps Medium＋Lakebase 2 CU＋50 GB）** | **$481** | **$596** | **$425** | **$526** |
| **合計: 最小（Apps Medium 24 時間＋Lakebase 0.5 CU＋50 GB）** | $360 | $449 | $325 | $405 |
| **合計: 業務時間だけ** | $204 | $250 | $182 | $222 |

- アプリが 2 つ（jadd_studio3 と fleet-ops）なら、おおむね 2 倍。
- Lakebase は 2027-01-31 までは半額。
- 含めていないもの: いまも払っている SQL Warehouse の料金（アプリが Databricks のデータを読むぶん）、リージョンをまたぐ転送料、HA、Apps の台数を増やしたぶん、cron の代わりにする Jobs。

## Vercel・Supabase との比べ方

- Vercel は、コミットの作者全員の席を払う方針で、チーム全体で **月 $620 前後**（31 席。[vercel-accounts.md](../../information-resource-inventory/workstream/vercel-accounts.md) の試算）。これでチームの 12 プロジェクトをまかなう。使用量が含まれる分を超えたら別に払う。
- Databricks は、**アプリごとに**課金される。上の構成なら、アプリ 1 つで月 $200〜600。席の料金は無い（人ごとの課金は無いと思われる。未確認）。
- Supabase の料金は、この資料では見ていない。比べるなら、移すアプリが使っている Supabase のプロジェクトの月額を足す。
- アプリが 1〜2 個なら、Databricks のほうが安くなりうる。Vercel の 12 プロジェクトを全部移すと、Databricks のほうが高くなりそう（推測）。

## 東京とオレゴンのどちらに置くか

| | 東京（ap-northeast-1） | オレゴン（us-west-2） |
|---|---|---|
| 料金 | 1.1〜1.2 倍高い | 安い |
| 東京のオフィスからの近さ | 近い | 往復で 100 ms 前後の遅れ（一般的な値。測っていない） |
| データとの距離 | データはオレゴンにある。アプリから読むたびにリージョンをまたぐ | 同じリージョン |
| Workspace | 新しく作る。Unity Catalog の metastore もリージョンごとに要る（推測。未確認） | いまの Workspace に置ける |
| Unity Catalog → Lakebase の同期 | リージョンをまたいで使えるかは未確認 | 同じリージョンで使える |

見立て（まだ決めていない）: 料金と運用の手間だけを見ると、いまの Workspace に置けるオレゴンが有利。東京にする理由は、画面の応答の速さ。東京に置いても、オレゴンのデータを読むたびに太平洋を往復するので、データを多く読む画面では速くならないおそれがある（推測）。

## 確かめていないこと

- 社のプラン（Premium / Enterprise）と、契約の割引。`system.billing.list_prices` で見られる
- DSU の単価（東京・オレゴン）、Lakebase の Always-on の単価、データの転送料
- jadd_studio3・fleet-ops のいまの DB の大きさと負荷（必要な CU の見積もりのため）
- Apps を時間で止めて起動し直す運用ができるか
- 東京の Workspace から、オレゴンのデータ（Unity Catalog）をどう読むか
