# ステージ 1 のバケットポリシーを使い捨てのバケットで試す手順

- 実行する人: Full 権限を持つ人（エージェントは ReadOnly なので実行しない）
- 使うもの: `test-bucket.sh`、`test-policy.json`（`statements.json` をこのバケット向けにしたもの。Access Analyzer の指摘なし）
- 作るもの: バケット `s3-policy-test-767397804933`（us-west-2）と、IAM ロール `s3-policy-test-denied`。どちらも最後に消す
- 所要時間: 10 分ほど
- 前提: `full` のプロファイルが tuscenes-prod の FullAccess か AWSAdministratorAccess のセッションであること（違うと何も作らずに止まる）。別の名前のプロファイルなら `PROFILE=<名前> bash test-bucket.sh ...`
- 触るもの: 上で作るバケットとロールだけ。既存のバケット・ロール・アカウントの設定は変えない

## アカウントの状態への依存

| 依存するもの | 内容 | 外れたとき |
|---|---|---|
| アカウントとリージョン | tuscenes-prod（767397804933）・us-west-2 に固定 | 止まる（別アカウントのセッションなら setup の前で止まる） |
| 例外のロール名 | `test-policy.json` の例外は `AWSReservedSSO_FullAccess_*` と `AWSReservedSSO_AWSAdministratorAccess_*`。実行する人のロールは実行時に取得する | 権限セットの名前が変われば exempt が NG になる（＝本番でも締め出される。検証したいこと） |
| 名前の空き | バケット `s3-policy-test-767397804933` とロール `s3-policy-test-denied` が無いこと（2026-10-21 に確認） | setup がエラーで止まる |
| 組織の SCP | バケットやロールの作成を禁じる SCP があれば失敗する（メンバーアカウントからは見えない） | setup がエラーで止まる |
| IAM の反映 | 作ったロールが使えるまで数秒〜数十秒 | denied の assume-role が失敗する。少しおいてやり直す |

## 手順

Claude Code の入力欄から `!` を付けて 1 行ずつ実行する。

```bash
! bash /usr/app/personal-workspace/projects/aws-data-protection/workstream/s3-data-protection-2/bucket-policy/test-bucket.sh setup
# 30 秒ほどおく（IAM の反映待ち）
! bash /usr/app/personal-workspace/projects/aws-data-protection/workstream/s3-data-protection-2/bucket-policy/test-bucket.sh denied
! bash /usr/app/personal-workspace/projects/aws-data-protection/workstream/s3-data-protection-2/bucket-policy/test-bucket.sh exempt
! bash /usr/app/personal-workspace/projects/aws-data-protection/workstream/s3-data-protection-2/bucket-policy/test-bucket.sh cleanup
```

| 手順 | 何をするか | 期待 |
|---|---|---|
| setup | バケットを作り、バージョニングを有効にして同じキーに 2 回書く（古い版を 1 つ作る）。`s3:*` を持つ一時的なロールを作る（信頼先は FullAccess のロールだけ）。2 文のポリシーを当てる | エラーなく終わる |
| denied | 一時的なロールで 12 の操作を試す | ふつうの削除・上書きの 2 つは allow、残りの 10 は deny。全行が `OK` |
| exempt | FullAccess でポリシーの上書き・バージョニング・古い版の削除を試す | 3 つとも allow（締め出されない）。全行が `OK` |
| cleanup | 全版を消し、ポリシー・バケット・ロールを消す | 「cleanup 完了」 |

`NG` が出たら、そこで止めて cleanup を実行し、出力を共有する。

## この手順で確かめないもの

- **AWSAdministratorAccess の例外**: FullAccess と同じ書き方（`AWSReservedSSO_<名前>_*`）なので、FullAccess で確かめれば足りる。
- **CDK の deploy（cfn-exec-role）**: datalake の PR で `tuscenes-calibration-test` に入れ、`cdk diff` を確かめてからマージし、GitHub Actions の deploy が通ることで確かめる。（2026-10-23 追記: `tuscenes-calibration-test` では試さず、本番の #2252 の deploy で確かめた。[親](../../s3-data-protection-2.md) の TODO 4）
- **Control Tower・StackSets のロールが止まっても困らないか**: ReadOnly で確かめ済み（2026-10-21）。直近 90 日の呼び出しは 0 件で、StackSet のスタックは 12 本に触れていない。
