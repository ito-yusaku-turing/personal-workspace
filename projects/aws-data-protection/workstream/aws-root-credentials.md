# メンバーアカウントの root の認証情報を消す

- 開始: 2026-10-20
- 状態: **起票した**。CorpIT に依頼する段
- 所属: project:aws-data-protection（2026-10-26 に `~/docs/workstream/` から移した）
- 実施: CorpIT（管理アカウント 210332786925 の権限が要る）
- 経緯: [S3 バケットのデータ保護 第二弾](s3-data-protection-2.md) の洗い出しで見つかった（調査書の G11、critical）。root はアカウント全体の問題なので、S3 とは別の案件として進める（2026-10-20 伊藤が決定）

## 背景

tuscenes-prod（767397804933）の root は、パスワードが有効で MFA がない。root は IAM ポリシーでもバケットポリシーでも止められない。

## 決まったこと（2026-10-20）

- root の認証情報は**削除する**。MFA を付ける案は採らない。MFA を付けても、キーを持つ人と root のメールの管理が残るため。
- 実施は CorpIT に依頼する。

## 現状（2026-10-20、tuscenes-prod から ReadOnly で確認）

- 組織（o-5ncqlr6fzq）の FeatureSet は `ALL`。root の一元管理を使う前提は満たしている。
- root はパスワードが有効で、MFA はない。アクセスキーも署名証明書もない（`get-account-summary` と認証情報レポートで確認）。
- パスワードは、アカウントを作った 2024-02-01 から一度も変わっておらず、使われた記録もない（`password_last_used: no_information`）。Organizations で作ったときの初期パスワードで、誰も知らないとみられる。
- 直近 90 日の CloudTrail に root の操作はない（us-east-1・ap-northeast-1・us-west-2）。
- **実際の弱点は root のメールアドレス**。その受信箱を読める人は、パスワードを再設定して入れる。
- メンバーアカウントからは見えないため、次の 2 点は未確認。
  - root を拒否する SCP があるか。
  - 一元管理が有効になっているか。

### 仕様の確認

- 一元管理を有効にした**後**に作ったアカウントは、root の認証情報なしで作られる。
- 有効にする**前から**あるアカウントには、認証情報が残る。管理アカウントから `sts:AssumeRoot`（タスクは `IAMDeleteRootUserCredentials`）を使うか、IAM コンソールで、**1 アカウントずつ明示的に消す**必要がある。
- tuscenes-prod は一元管理の提供開始（2024-11）より前に作られている。仮に今は有効でも、認証情報は残っている。
- 私の知る限り、Control Tower はこれを自動で行わない。root を拒否するコントロールも、既定では付かない。ランディングゾーンのバージョンによる違いは未確認。

## TODO（優先度順）

1. **CorpIT に依頼する**。依頼の内容:
   - 一元管理（IAM の root access management）が有効か確かめてもらう。確かめ方は、管理アカウントで `aws iam list-organizations-features` を実行すること。無効なら有効にしてもらう。
   - **全メンバーアカウント**の root の認証情報を消してもらう。tuscenes-prod だけでなく、amman-pipeline・e2e-dev・biz-dev なども同じく初期パスワードが残っているはず。
   - 削除が済むまでは、root の宛先のメールが誰の受信箱かを確かめてもらう。
   - root を拒否する SCP（Control Tower の「root ユーザーとしての操作を禁止する」コントロールでもよい）が各 OU にあるか確かめ、なければ付けてもらう。
   - その SCP が `sts:AssumeRoot` のセッションまで拒否しないか確かめてもらう。S3 のステージ 1 で締め出されたときの戻し道（`S3UnlockBucketPolicy`）になるため。
2. **root と `AssumeRoot` の使用を通知する**。EventBridge から Slack に送る。サインインのイベントは us-east-1 で受ける。管理アカウント側で組織全体に置くか、各アカウントに cdk-apps で置くかは CorpIT と決める。
3. **削除の後に確かめる**。各アカウントの `get-account-summary` で `AccountMFAEnabled` などを見て、認証情報レポートで `password_enabled: false` になっていることを確かめる。

## S3 の案件との接点

- 一元管理が入ると、管理アカウントの管理者が `S3UnlockBucketPolicy` でバケットポリシーを消せるようになる。これは S3 のステージ 1 で締め出されたときの戻し道になる。一方で、守りを外せる経路でもある。
- そのため、S3 の案件では、管理アカウントで最大権限を持つ人も「最大権限を持つ人」に数える。

## 進捗と引き継ぎ

- 2026-10-20: 起票した。tuscenes-prod の root の現状を ReadOnly で確かめた。削除の方針を決め、CorpIT に依頼することにした。
- **次にやること**: TODO の 1（CorpIT への依頼）。
