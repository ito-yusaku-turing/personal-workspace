# jadd_studio の Amplify の一式の削除の手順書（AWS CLI）

- 作成: 2026-10-26
- 実施: 未
- 対象: tuscenes-prod（767397804933）、us-west-2 の Amplify の一式（初代 jadd_studio。2024-11-22〜23 に作られたまま）
- やること: CloudFormation のスタックを消し、Amplify のアプリ 2 つを消し、スタックを消しても残るバケット 2 本とロググループ 1 つを消す
- 実行する人: 書き込みの権限を持つ人（SSO の FullAccess など）。ReadOnly ではできない
- 親資料: [jadd_studio_amplify を削除する](../jadd-studio-amplify-removal.md)。対象と、使われていないことの根拠は親資料の「Amplify の一式の洗い出し」

## 消すもの

| 消し方 | 対象 |
| --- | --- |
| スタックの削除で消える | スタック `amplify-jaddstudio-dev-2b103` と子のスタック 2 つ、Cognito のユーザープール `us-west-2_jb7jCOO9q`（クライアント 2 つ）と ID プール、IAM ロール 4 本とポリシー、Lambda 1 つ、deployment のバケットのバケットポリシー |
| 別に消す | Amplify アプリ `jadd_studio`（d34n309gf2fupw）・`jaddstudio`（d37k44pfh0i4bm） |
| 別に消す（テンプレートで `DeletionPolicy: Retain`） | バケット `amplify-jaddstudio-dev-2b103-deployment`（設定ファイル 11 件）・`jaddstudioc20f7c0d8d4347b286666288f7a6c6d22b103-dev`（空） |
| 別に消す | ロググループ `/aws/lambda/amplify-jaddstudio-dev-2b-UpdateRolesWithIDPFuncti-w97MZ0RwoviB`（992 バイト） |

- **消さない**: `amplify-turingapps-main-127f9`（2024-12-05、タグ `user:Application=turingapps`）。名前が似ているが別物。
- バケットは 2 本ともバージョニングが無いので、古い版は残らない。原本バケットではなく、ステージ 1 のバケットポリシーも入っていない。

## 手順

```sh
export AWS_PROFILE=<書き込みの権限のあるプロファイル>
export AWS_REGION=us-west-2

# 0. 正しいアカウントか確かめる（767397804933 であること）
aws sts get-caller-identity --query Account --output text

# 1. 実行前の状態を確かめる
#    - スタックが UPDATE_COMPLETE であること
#    - アプリが 2 つ（d34n309gf2fupw jadd_studio、d37k44pfh0i4bm jaddstudio）あること。ほかのアプリ ID が出ても、それは消さない
#    - ユーザープールのユーザーが 0 であること
#    - storage のバケットが 0、deployment のバケットが 11であること
aws cloudformation describe-stacks --stack-name amplify-jaddstudio-dev-2b103 --query 'Stacks[0].StackStatus' --output text
aws amplify list-apps --query 'apps[].[appId,name]' --output text
aws cognito-idp list-users --user-pool-id us-west-2_jb7jCOO9q --query 'length(Users)'
aws s3api list-objects-v2 --bucket jaddstudioc20f7c0d8d4347b286666288f7a6c6d22b103-dev --expected-bucket-owner 767397804933 --query 'KeyCount'
aws s3api list-objects-v2 --bucket amplify-jaddstudio-dev-2b103-deployment --expected-bucket-owner 767397804933 --query 'KeyCount'

# 2. スタックを消す（子のスタック 2 つもまとめて消える。成功しても何も出ない）
aws cloudformation delete-stack --stack-name amplify-jaddstudio-dev-2b103

# 3. 削除が終わるのを待つ（数分。終わると何も出ずに戻る。失敗したら下の「つまずいたとき」）
aws cloudformation wait stack-delete-complete --stack-name amplify-jaddstudio-dev-2b103

# 4. Amplify のアプリを消す（消したアプリの情報が JSON で出る）
aws amplify delete-app --app-id d34n309gf2fupw
aws amplify delete-app --app-id d37k44pfh0i4bm

# 5. 残ったバケットを空にして消す（storage のバケットはもともと空。rm は何も出ない）
aws s3 rm s3://amplify-jaddstudio-dev-2b103-deployment --recursive
aws s3api delete-bucket --bucket amplify-jaddstudio-dev-2b103-deployment --expected-bucket-owner 767397804933
aws s3api delete-bucket --bucket jaddstudioc20f7c0d8d4347b286666288f7a6c6d22b103-dev --expected-bucket-owner 767397804933

# 6. Lambda のロググループを消す（成功しても何も出ない）
aws logs delete-log-group --log-group-name /aws/lambda/amplify-jaddstudio-dev-2b-UpdateRolesWithIDPFuncti-w97MZ0RwoviB

# 7. 結果を確かめる
#    - スタック: "does not exist" のエラーになること
#    - アプリ: d34n309gf2fupw・d37k44pfh0i4bm が一覧に無いこと
#    - ユーザープール: ResourceNotFoundException になること
#    - バケット: 2 本とも 404（Not Found）になること
aws cloudformation describe-stacks --stack-name amplify-jaddstudio-dev-2b103
aws amplify list-apps --query 'apps[].[appId,name]' --output text
aws cognito-idp describe-user-pool --user-pool-id us-west-2_jb7jCOO9q
aws s3api head-bucket --bucket amplify-jaddstudio-dev-2b103-deployment
aws s3api head-bucket --bucket jaddstudioc20f7c0d8d4347b286666288f7a6c6d22b103-dev
```

- 1 行に 1 つのコマンドで、ループは使わない（1 行ずつ貼って結果を見ながら進められるように）。
- スタックを先に消し、アプリは後で消す。アプリの削除でバックエンドのスタックが消えるかは仕様が曖昧なので、スタックは自分で消す。
- `aws s3 rm --recursive` は、そのバケットの全オブジェクトを消す。**バケット名を必ず確かめてから**実行する。
- 7 の確認は ReadOnly の権限でもできる（実行後にエージェントに頼んでもよい）。IAM ロール 4 本と Lambda が消えたことは、エージェントが確かめる。

## つまずいたとき

- **3 で `DELETE_FAILED` になった**: 原因を見る。
  ```sh
  aws cloudformation describe-stack-events --stack-name amplify-jaddstudio-dev-2b103 --query "StackEvents[?ResourceStatus=='DELETE_FAILED'].[LogicalResourceId,ResourceStatusReason]" --output text
  ```
  - 子のスタックや Custom リソース（`Custom::LambdaCallout`。消すときに Lambda を呼ぶ）で失敗したら、その論理 ID を残して消し直す: `aws cloudformation delete-stack --stack-name amplify-jaddstudio-dev-2b103 --retain-resources <論理 ID>`。残ったものは、エージェントに知らせて個別に消す。
  - Lambda の runtime は nodejs18.x（サポート終了済み）。呼び出せなかった場合もここに当たる。
- **3 の `wait` が 1 時間ほど戻らない**: Custom リソースの応答待ちのことがある。`describe-stack-events` で進み具合を見る。
- **5 の `delete-bucket` が `BucketNotEmpty` になった**: `aws s3api list-object-versions --bucket <バケット名>` で版や削除マーカーが無いか見る（10-26 には無かった）。

## 戻し方

- 戻せない。スタックもアプリも Cognito も、消したものは作り直すしかない。
- ただ、作り直す理由も無い。どれも 2024-11 から更新が無く、ユーザー 0・ID 0・Lambda の呼び出し 0 で、公開 URL へのアクセスはボットだけ（親資料の洗い出し）。ページの中身は create-react-app の雛形で、元のコードは GitHub の turingmotors/jadd_studio にある。

## 削除の後にやること

- 親資料の「進捗と引き継ぎ」に、実施の日時と結果を書く。TODO 4 を済みにする。
