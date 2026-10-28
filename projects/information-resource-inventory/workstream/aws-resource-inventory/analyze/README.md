# 一次情報を集計するスクリプト

`~/aws/tuscenes-prod/<取得日>/` の一次情報を読み、`<取得日>/derived/` に表（TSV）を出す。どれも `python3 -I <スクリプト> <取得日のフォルダ>` で動く。順番は上から。

- `iam_users.py`: IAM ユーザーに、クレデンシャルレポートの最終利用・キーの状態・権限の要約を付ける（→ 標準出力。`derived/iam-users.tsv` に保存して使う）。
- `iam_roles.py`: IAM ロールに、最終利用・種類（サービスリンク・SSO など）・信頼する主体（OIDC の条件を含む）・強い権限を付ける（→ `derived/iam-roles.tsv`）。
- `cfn_stacks.py`: ルートのスタックに、最終更新・リソース数・持ち主のリポジトリの候補を付ける。2 つ目以降の引数にリポジトリのフォルダを渡す（→ `derived/cfn-stacks.tsv`）。
- `conflicts.py`: EventBridge のルール・S3 の通知・Lambda を突き合わせ、眠っている仕掛け・丸ごと上書きする持ち主・宛先の消えた配線を判定する（→ `derived/events-rules.tsv`・`s3-notifications.tsv`・`lambda.tsv`）。`cfn-stacks.tsv` を先に作っておく。
