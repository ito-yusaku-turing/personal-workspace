# Databricks の料金体系と見積もり（アプリのホスティング）

- 作成: 2026-11-10（同じ日に、実際の負荷から見積もり直した）
- 置き場所: **オレゴン（us-west-2）のいまの Workspace に作る**前提（2026-11-10、伊藤）。東京の単価は比較のために残す。
- 単価の出どころ: Databricks の公式の料金の計算機のデータ（`https://www.databricks.com/en-pricing-assets/data/pricing/AWS.json`）と、料金のページ（[Databricks Apps](https://www.databricks.com/product/pricing/databricks-apps)・[Lakebase](https://www.databricks.com/product/pricing/lakebase)・[Storage](https://www.databricks.com/product/pricing/storage)）の本文。2026-11-10 に取得した。
- **定価（従量課金の一覧価格）**。社の契約の割引は入っていない。社のプランと契約の単価の調べ方は、末尾の「社のプランと契約の単価の調べ方」。
- 金額はすべて米ドル。1 か月は 730 時間で数える（Databricks の料金のページと同じ）。

## 前提

- **社の Databricks の Workspace（`dbc-24f125d6-4420`）は us-west-2（オレゴン）にある**（2026-11-10、DNS で確かめた。`oregon.cloud.databricks.com` の別名）。データの本体もオレゴンにある。
- Apps も Lakebase も、Workspace のリージョンで動く。オレゴンなら、いまの Workspace に置ける。
- AWS の Databricks のプランは **Premium と Enterprise の 2 つだけ**（Standard は 2025-10-01 に Premium へ移った。[Manage your subscription](https://docs.databricks.com/aws/en/admin/account-settings/account)）。社がどちらかは確かめていないので、下では両方を出す。

## 料金体系

| 何に払うか | 課金の単位 | 決まり方 |
|---|---|---|
| **Databricks Apps**（アプリを動かす計算機） | DBU。請求では「Interactive Serverless」（または All-Purpose Serverless）の SKU に載る | **動いている時間 × 大きさ**。Medium（2 vCPU・6 GB）0.5 DBU/時、Large（4 vCPU・12 GB）1 DBU/時、XLarge（12 vCPU・48 GB）3 DBU/時。台数を増やすと台数倍。使われていなくても、動いていれば課金される |
| **Lakebase の計算機**（Postgres） | CU 時間（1 CU は RAM 2 GB）。請求では「Database Serverless Compute」の DBU に換算される | 実際に使った CU 時間。自動で伸び縮みし、止められる（scale to zero）。高可用性（HA）の分の CU 時間も数える |
| **Lakebase のストレージ** | DSU（Databricks Storage Unit） | DB の本体 1 GB・1 か月あたり 15 DSU、時点への復元（PITR）の履歴 8.60 DSU、スナップショット 3.91 DSU |
| Unity Catalog → Lakebase の同期（synced tables） | DBU（裏で動くサーバーレスのパイプライン） | 使ったときだけ |
| データの転送 | クラウドの転送料 | リージョンをまたぐとき・外に出すときにかかりうる（料金のページの「Data transfer and connectivity」。単価は見ていない）。オレゴンに置けば、データとの間はリージョンをまたがない |

補足:

- **Lakebase は 2027-01-31 まで 50% 引き**（"Promotion - Save 50% off price shown below until January 31, 2027"）。下の見積もりは割引前の定価で出す。
- Lakebase は、scale to zero を 24 時間を超えて切ったままにすると「Always-on」の料金になる。最低の容量のぶんが安い単価になる（単価は取れていない）。
- Apps の料金のページの例: 「Medium のアプリ 5 個を 30 日 24 時間、AWS Premium の US East で動かすと 1,800 DBU、$0.75/DBU で月 $1,350」。

## 単価（定価）

| リージョン・プラン | Apps（Interactive Serverless）$/DBU | Apps Medium 1 台・1 時間 | Lakebase $/CU 時間 |
|---|---|---|---|
| **オレゴン Premium** | 0.75 | $0.375 | 0.092 |
| **オレゴン Enterprise** | 0.95 | $0.475 | 0.111 |
| 東京 Premium（比較） | 0.83 | $0.415 | 0.110 |
| 東京 Enterprise（比較） | 1.05 | $0.525 | 0.134 |

- DSU の単価は公式のデータでは見つからなかった。外部の記事では、AWS の US East の Premium で $0.023/DSU（[Coupler.io](https://blog.coupler.io/?p=85874) ほか。**未確認**）。この単価だと、Lakebase の DB の本体は 1 GB・1 か月あたり $0.345。

## いまの負荷（2026-11-10 に取得）

Databricks に移す対象は jadd_studio3 と fleet-ops。いまの負荷から、Databricks の大きさを決める。

| | jadd_studio3（Vercel: jadd-studio3） | fleet-ops（Vercel: biz-fleet-ops） | 出どころ |
|---|---|---|---|
| Vercel の関数の CPU（10 月） | 44.8 時間 | 2.3 時間 | Vercel の請求の API（`Fluid Active CPU`） |
| Vercel の関数のメモリ（10 月） | 1,116 GB 時間（平均 1.5 GB） | 26 GB 時間 | 同（`Fluid Provisioned Memory`） |
| Vercel の関数の呼び出し（10 月） | 254 万回 | 13 万回 | 同（`Function Invocations`） |
| Vercel の使用量の料金（10 月、クレジット前） | 約 $75 | 約 $4 | 同（`EffectiveCost`） |
| 本番へのデプロイ | 30 日で 223 回 | 少ない | GitHub Actions の `deploy.yml` の実行 |
| Supabase のプロジェクト | `ebdfwtvfpemzevdpxmek`（名前は jadd-studio-dev。本番が `env/static.yaml` で使う）。**Small（RAM 2 GB）**、東京 | `qgnfaidhxcuqivmgubuy`（biz-fleet-ops）。**Micro（RAM 1 GB）**、東京 | Supabase の API（`GET /v2/organizations/{slug}/projects`） |
| Supabase のディスク | 8 GB（gp3） | 8 GB（gp3） | 同。データは 8 GB より小さい |

一次情報は git の外に置いた（`~/vercel/turing-inc/2026-11-10/`・`~/supabase/dhazyhuzuwitqasezcvr/2026-11-10/`）。

見立て:

- **Apps は Medium 1 台で足りそう**。jadd_studio3 が月に使う CPU は 45 時間で、Medium 1 台を 24 時間動かしたとき（2 vCPU × 730 時間）の 3% ほど。ただし、瞬間の山（同時のアクセス）は測っていない。Apps は台数が自動で増えないので、山に備えるなら Large か 2 台にする。
- **Lakebase は、Supabase の RAM に合わせる**（1 CU は RAM 2 GB）。jadd_studio3 は Small（2 GB）なので 1 CU、fleet-ops は Micro（1 GB）なので 0.5 CU（Lakebase の最小）。
- ストレージは小さい（それぞれ 8 GB 以下）。

## 見積もり（オレゴン、月額、定価）

| 項目 | 前提 | Premium | Enterprise |
|---|---|---|---|
| Apps: jadd_studio3 | Medium 1 台・24 時間 | $274 | $347 |
| Apps: fleet-ops | Medium 1 台・24 時間 | $274 | $347 |
| Lakebase: jadd_studio3 | 1 CU・24 時間 | $67 | $81 |
| Lakebase: fleet-ops | 0.5 CU・24 時間（scale to zero で減る） | $34 | $41 |
| ストレージ | 2 つ合わせて 16 GB 以下・DSU $0.023 | $6 以下 | $6 以下 |
| **合計** | | **約 $655** | **約 $822** |
| 参考: jadd_studio3 を 2 台にする | ＋Medium 1 台 | ＋$274 | ＋$347 |
| 参考: 2027-01-31 までの Lakebase の 50% 引き | | −$50 | −$61 |

含めていないもの: いまも払っている SQL Warehouse の料金（アプリが Databricks のデータを読むぶん。移しても変わらない）、HA、cron の代わりにする Jobs、ビルドの計算機（Apps のデプロイのときのビルドの扱いは確かめていない）。

## Vercel に残す場合との比較（月額、定価）

Vercel の見積もりは [vercel-accounts.md](../../information-resource-inventory/workstream/vercel-accounts.md) の「費用の見積もり（2026-11-10）」。

| | A. Vercel に残し、全員分の席を払う | B. jadd_studio3 と fleet-ops を Databricks（オレゴン）に移す |
|---|---|---|
| Vercel | 32 席 $640＋使用量 $110〜170 = **$750〜810** | 席の無い作者を足さずに済む。18 席 $360＋ほかのプロジェクトの使用量 約 $15 = **約 $375** |
| Databricks | なし | Premium **約 $655** / Enterprise **約 $822** |
| Supabase | いまのまま | 2 つのプロジェクトのぶん（Small と Micro の計算機）が減る。組織の Pro の基本料金はほかのプロジェクトで残る |
| **合計** | **$750〜810** | Premium **約 $1,030** / Enterprise **約 $1,200** |

- **定価で比べると、Vercel に残すほうが月 $200〜450 安い**。Vercel は使った分だけ払う（jadd_studio3 の使用量は月 $75 ほど）。Databricks の Apps は、使われていなくても 1 台ごとに月 $274 以上かかる。
- 差を縮める手: 契約の割引、fleet-ops を業務時間だけ動かす（Apps を時間で止めて起動し直せるかは未確認）、Lakebase の scale to zero。
- お金以外の差（デプロイのトークンが要らない、入口で社の SSO と MFA が必ず効く、など）は [workstream](../workstream/databricks-app-hosting.md) の「見立て」。

## 社のプランと契約の単価の調べ方

1. **アカウントコンソールで見る**（Databricks のアカウント管理者が要る）
   - https://accounts.cloud.databricks.com/login にログインし、サイドバーの **Settings** を開く。プランの横に **Upgrade** が出ていれば、そこにいまのプランがある（[Manage your subscription](https://docs.databricks.com/aws/en/admin/account-settings/account)）。
   - このページは従量課金（pay-as-you-go）の契約だけが対象。**年間の契約（commit）なら、Databricks のアカウントの担当者に聞くよう書かれている**。
   - 伊藤がアカウント管理者でなければ、管理者（CorpIT か、Databricks の契約を持っている人）に頼む。
2. **Workspace の SQL で見る**（システムテーブル `system.billing` を読む権限が要る）
   - 権限: アカウント管理者とメタストア管理者を兼ねる人は、初めから読める。ほかの人には、`system` カタログの `USE CATALOG`、`system.billing` の `USE SCHEMA` と `SELECT` を付けてもらう（[System tables](https://docs.databricks.com/aws/en/admin/system-tables/)）。クエリを走らせる計算機の料金だけがかかる。
   - いま使っている SKU と単価（SKU の名前の頭の `PREMIUM_` / `ENTERPRISE_` でプランが分かるのが通例。ドキュメントには書かれていないので、単価でも確かめる）:

     ```sql
     SELECT DISTINCT u.sku_name, p.pricing.default AS list_price, p.pricing.effective_list
     FROM system.billing.usage u
     JOIN system.billing.list_prices p
       ON u.sku_name = p.sku_name AND p.price_end_time IS NULL
     WHERE u.usage_date >= current_date() - INTERVAL 30 DAYS;
     ```

   - Apps と Lakebase の単価（定価）。オレゴンの Interactive Serverless が $0.75 なら Premium、$0.95 なら Enterprise:

     ```sql
     SELECT sku_name, pricing.default, pricing.promotional, pricing.effective_list, usage_unit
     FROM system.billing.list_prices
     WHERE price_end_time IS NULL
       AND (sku_name LIKE '%INTERACTIVE_SERVERLESS%' OR sku_name LIKE '%DATABASE_SERVERLESS%'
            OR sku_name LIKE '%STORAGE%');
     ```

   - すでに Apps や Lakebase を使っている人がいるか（`billing_origin_product` が `APPS`・`LAKEBASE`）:

     ```sql
     SELECT billing_origin_product, usage_metadata.app_name, sum(usage_quantity) AS dbu
     FROM system.billing.usage
     WHERE billing_origin_product IN ('APPS', 'LAKEBASE', 'DATABASE')
       AND usage_date >= current_date() - INTERVAL 90 DAYS
     GROUP BY ALL;
     ```

   - `list_prices` は**定価**のテーブル。契約の割引込みの単価のテーブルは、ドキュメントでは見つからなかった（[Pricing system table](https://docs.databricks.com/aws/en/admin/system-tables/pricing)）。割引は、契約書か担当者で確かめる。
3. **契約の形を確かめる**（経理か CorpIT）: 従量課金か年間の契約か、AWS Marketplace 経由か。割引の率は契約で決まる。

## 確かめていないこと

- 社のプランと契約の割引（上の手順）
- DSU の単価、Lakebase の Always-on の単価
- jadd_studio3 の瞬間の山（Apps の台数を決めるため）
- Apps を時間で止めて起動し直す運用ができるか
- Apps のデプロイのときのビルドに料金がかかるか
