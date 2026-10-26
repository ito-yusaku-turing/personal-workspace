# IAM ユーザー jadd_studio_amplify の削除の手順書（AWS CLI）

- 作成: 2026-10-26
- **実施: 2026-10-26 17:57〜17:58 JST**（伊藤）。`get-user` が NoSuchEntity になり、`secretsmanager_GetSecretValue` の付け先が 2 になったことを ReadOnly で確かめた
- 対象: tuscenes-prod（767397804933）の IAM ユーザー `jadd_studio_amplify`（CDK の管理外）
- やること: 管理ポリシー 4 本を外し、アクセスキー 2 本を消し、ユーザーを消す
- 実行する人: 書き込みの権限を持つ人（SSO の FullAccess など）。ReadOnly ではできない
- 親資料: [jadd_studio_amplify を削除する](../jadd-studio-amplify-removal.md)（利用元の調査と、消してよい根拠）

## 消してよい根拠（要点）

- 2026-10-23 に、ロール 692 件・カスタム管理ポリシー 74 件・バケットポリシー 158 件のどれからも参照されていないことを確かめた。
- 2026-10-26 に ReadOnly で見直し、10-23 から変わりがないことを確かめた。
  - 管理ポリシーは 4 本、キーは 2 本とも Inactive。
  - ログイン・MFA・署名証明書・SSH 鍵・サービス用の資格情報・インラインポリシー・グループは、どれも無い。
  - 無効化（10-23 07:05 UTC）の後、CloudTrail にこのユーザーやキーの記録は無い。
- 1 本目のキーは jadd_studio3 の git 履歴に平文で残っている。有効に戻すことはしない。

## 手順

```sh
export AWS_PROFILE=<書き込みの権限のあるプロファイル>
export AWS_REGION=us-west-2

# 0. 正しいアカウントか確かめる（767397804933 であること）
aws sts get-caller-identity --query Account --output text

# 1. 実行前の状態を確かめる
#    - 管理ポリシーが次の 4 本であること
#    - キーが 2 本で、どちらも Inactive であること（末尾が GHTY と XTTO）
#    - インラインポリシー・グループが無いこと（[] が出る）
aws iam list-attached-user-policies --user-name jadd_studio_amplify --query 'AttachedPolicies[].PolicyArn' --output text
aws iam list-access-keys --user-name jadd_studio_amplify --query 'AccessKeyMetadata[].[AccessKeyId,Status]' --output text
aws iam list-user-policies --user-name jadd_studio_amplify --query 'PolicyNames'
aws iam list-groups-for-user --user-name jadd_studio_amplify --query 'Groups[].GroupName'

# 2. 管理ポリシーを外す（成功しても何も出ない）
aws iam detach-user-policy --user-name jadd_studio_amplify --policy-arn arn:aws:iam::767397804933:policy/secretsmanager_GetSecretValue
aws iam detach-user-policy --user-name jadd_studio_amplify --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam detach-user-policy --user-name jadd_studio_amplify --policy-arn arn:aws:iam::aws:policy/service-role/AmplifyBackendDeployFullAccess
aws iam detach-user-policy --user-name jadd_studio_amplify --policy-arn arn:aws:iam::aws:policy/AdministratorAccess-Amplify

# 3. アクセスキーを消す（<…GHTY> と <…XTTO> は、1 の出力のキー ID に置き換える。成功しても何も出ない）
aws iam delete-access-key --user-name jadd_studio_amplify --access-key-id <…GHTY のキー ID>
aws iam delete-access-key --user-name jadd_studio_amplify --access-key-id <…XTTO のキー ID>

# 4. ユーザーを消す（成功しても何も出ない）
aws iam delete-user --user-name jadd_studio_amplify

# 5. 結果を確かめる
#    - get-user が NoSuchEntity になること
#    - secretsmanager_GetSecretValue の付け先が 3 から 2 になること（ポリシーは消さない）
aws iam get-user --user-name jadd_studio_amplify
aws iam get-policy --policy-arn arn:aws:iam::767397804933:policy/secretsmanager_GetSecretValue --query 'Policy.AttachmentCount'
```

- 1 行に 1 つのコマンドで、ループも変数も使わない（1 行ずつ貼って結果を見ながら進められるように）。
- 順番は「ポリシー → キー → ユーザー」。ポリシーやキーが残っていると、`delete-user` は `DeleteConflict` で失敗する。
- `DeleteConflict` が出たら、ほかに付いているものを `get-login-profile`・`list-mfa-devices`・`list-signing-certificates`・`list-ssh-public-keys`・`list-service-specific-credentials` で確かめる（10-26 にはどれも無かった）。
- 途中で止めても困らない。2 で止めても 3 で止めても、キーはすでに無効なので状況は悪くならない。
- 5 の確認は ReadOnly の権限でもできる（実行後にエージェントに頼んでもよい）。CloudTrail の `DeleteUser` などの記録もエージェントが確かめる。
- `secretsmanager_GetSecretValue` は Resource が `*` だが、ほかに 2 つの主体に付いているので消さない。

## 戻し方

- **消したキーは戻せない。** 戻す必要も無い（漏れているキーなので、有効に戻すことはしない）。
- ユーザーは、同じ名前で作り直し、同じ 4 本のポリシーを付ければ形の上では戻る。ただし内部の ID（`AIDA…`）が変わるので、ID で参照している信頼ポリシーなどは元に戻らない（10-23 の調べでは、そういう参照は無い）。
- 苦情が出たときは、ユーザーを作り直さずに次のように案内する（親資料の TODO 2）。
  - jadd_studio3 の開発者: `.env.local` の AWS の行を、今の `jadd-studio` のキーに差し替える。
  - tern: `AWS_PROFILE` に SSO のプロファイルを入れて動かす。

## 削除の後にやること

- 親資料の「進捗と引き継ぎ」に、実施の日時と結果を書く。
- 親資料の TODO 3: [s3-data-protection-2.md](../../s3-data-protection-2.md) の TODO 13 で jadd_studio_amplify を済みにする。[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) のレビューへの返答で、この主体が消えたことを伝える（キーが漏れていたことは書かない）。
- 親資料の TODO 4（Amplify の一式を片付けるか）は、別に判断する。ユーザーを消しても一式は残る。
