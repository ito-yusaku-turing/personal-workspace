# IAM ユーザー jadd_studio_amplify を削除する

- 開始: 2026-10-23
- 状態: **起票した**。キーは 2 本とも無効にした。削除は未着手
- 所属: project:aws-data-protection（2026-10-26 に `~/docs/workstream/` から移した）
- 実施: 伊藤（書き込みは Full の権限で CLI。このユーザーは CDK の管理外）
- 経緯: [S3 バケットのデータ保護 第二弾](s3-data-protection-2.md) の TODO 13 から切り出した。cdk-apps #2252 のレビューで犬塚さん（graph226）が「cfn-exec-role を名乗れる主体」として挙げたユーザー

## 背景

tuscenes-prod（767397804933）の IAM ユーザー `jadd_studio_amplify` は、2024-11-22 に Amplify CLI（初代 jadd_studio）のために作られた。`AmazonS3FullAccess`・`AdministratorAccess-Amplify`・`AmplifyBackendDeployFullAccess`・`secretsmanager_GetSecretValue` を持つ。
1 本目のキー（…GHTY）は、jadd_studio3 の git 履歴（2026-03-19 のマージ 49487053 の `secret.txt` と `jadd-studio-secrets.tgz`）に平文で残っている。そのキーが今も使われていた。

## 利用元の調査（2026-10-23）

### 確定していること

- 直近 90 日の記録で残っていたのは、`tuscenes-calibration-767397804933` の読み出しだけ。KMS の Decrypt を S3 が代わりに呼んだ記録（`invokedBy=fas.s3.amazonaws.com`）で、時刻は 8/13（18:11〜19:13 JST に 11 回）・8/14（14:37、17:54）・9/28（16:39 に 2 回）・10/16（18:16）。送信元の IP と User-Agent は、S3 経由のため取れない。このバケットにはアクセスログが無い。
  - CloudTrail はキー ID で引くと 0 件になる。記録上のキーが一時的なもの（ASIA…）に置き換わるため。ユーザー名（`Username=jadd_studio_amplify`）で引くと出る。
- 最後の利用は 2026-10-23 11:30 JST（us-west-2 の S3）。KMS の記録が無いので、暗号化していないものの読み出しか、一覧の取得。
- 3 月に開発者へ配った `jadd-studio-secrets.tgz` の `.env.local` は、`AWS_ACCESS_KEY_ID` がこのキーだった（キー ID の照合だけで確認）。
- jadd_studio3 はキャリブレーションのバケットを、既定の資格情報（`.env.local` の `AWS_ACCESS_KEY_ID`）で直接読む。読む箇所は `lib/leverarm-calibration/server/ohkamiParametersStore.ts`、`lib/database/databricks/sql/repository/CalibrationRepository.ts`、`lib/wheel-base-calibration/server/wheelBaseCenterMerge.ts`。
- 読み出しのあった 4 日すべてで、井上さん（inuex35）が `leverarm-calibration` をコミットしている（8/13 は 15:57〜19:11、8/14 は 15:50・17:36、9/28 は 17:33 の #1043、10/16 は 18:34 の #1190）。
- 調べて外したもの:
  - jadd_studio3 の本番。別のユーザー `jadd-studio` を使っている。PR ごとのプレビュー環境も無い。
  - Databricks のキャリブレーション取り込み。別のユーザーで、ロールを経由する。
  - scenario-test の Batch と backend-api。ロールで動く。
  - jadd-cli。backend-api を呼ぶだけ。
  - 伊藤のコンテナの `default` のプロファイル。キーが入っていない。
- ユーザー名もキー ID も、cdk-apps・mono-e2e・jadd-cli・databricks-jobs・drivers-app3・fleet-ops には出てこない（git 履歴を含む）。

### 推測（未確認）

- 8/13〜10/16 は、井上さんの手元の jadd_studio3 の開発サーバー。`.env.local` の AWS の行が 3 月のパッケージのまま、という筋。本人は「最近は触っていない」とのことで、10/16 より後の話なら矛盾しない。
- 10/23 11:30 は別の人。候補は中村さん（yutyan0119）。11:15〜11:35 に tern の渋滞表示（#1244）を作業していた。手元の tern は `fromIni()` で資格情報を取るので、`AWS_PROFILE` が無いと `~/.aws/credentials` の `[default]` を使う。渋滞のバケット（`tern-traffic-767397804933-us-west-2`）は暗号化が AES256 でアクセスログも無く、記録では確かめられない。
- 一時は Devin を疑ったが、時刻の一致だけが根拠で、依頼者の 3 人（合田・三輪・横井）も知らないと答えたため取り下げた。

## 現状（2026-10-23）

- 2 本のキーはどちらも **Inactive**（伊藤が無効化した）。利用元は、悲鳴があがったところで特定する方針。
- 削除を妨げるものは無い（ReadOnly で確認）:
  - コンソールのログイン・MFA・署名証明書・SSH 鍵・サービス用の資格情報・グループ・インラインポリシーは、どれも無い。
  - ロール 692 件の信頼ポリシーとインラインポリシー、カスタム管理ポリシー 74 件、S3 のバケットポリシー 158 件のどれにも、このユーザーは出てこない。
  - 付いている管理ポリシーは 4 本。カスタムの `secretsmanager_GetSecretValue`（Resource は `*`）は、ほかに 2 つの主体に付いているので、ポリシーそのものは消さない。
- 様子見は要らない。漏れているキーを有効に戻すことはしないので、悲鳴への対処はどのみち「今のキーか SSO に切り替える」になる。削除しても無効のときと同じ `InvalidAccessKeyId` になるので、悲鳴で利用元を見つける効果も変わらない。

## TODO

1. **ユーザーを削除する**（伊藤、Full の権限）。管理ポリシーを外し、キーを消し、ユーザーを消す順:
   ```bash
   U=jadd_studio_amplify
   for a in arn:aws:iam::767397804933:policy/secretsmanager_GetSecretValue \
            arn:aws:iam::aws:policy/AmazonS3FullAccess \
            arn:aws:iam::aws:policy/service-role/AmplifyBackendDeployFullAccess \
            arn:aws:iam::aws:policy/AdministratorAccess-Amplify; do
     aws iam detach-user-policy --user-name $U --policy-arn $a
   done
   for k in $(aws iam list-access-keys --user-name $U --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
     aws iam delete-access-key --user-name $U --access-key-id $k
   done
   aws iam delete-user --user-name $U
   ```
   - ARN は 2026-10-23 に `list-attached-user-policies` で確かめたもの。
2. **悲鳴への対応**。jadd_studio3 の開発者には、次の 2 点を案内する。
   - `.env.local` の AWS の行を、今の `jadd-studio` のキーに差し替える。
   - tern は `AWS_PROFILE` に SSO のプロファイルを入れて動かす。
   - 古いキーが残っているかは、次のコマンドで確かめられる（値は出ない）: `grep -l HOC2HR6GHTY ~/.aws/credentials ~/.aws/config /usr/app/jadd_studio3/.env.local /usr/app/jadd_studio3/docker/.env 2>/dev/null`
3. **s3-data-protection-2 に反映する**。TODO 13 の jadd_studio_amplify を済みにする。#2252 のレビューへの返答で、この主体が消えたことを伝える。
4. **Amplify の一式を片付けるか決める**（別に判断する。ユーザーを消しても残る）。対象は、アプリ 2 つ（`jadd_studio` d34n309gf2fupw・`jaddstudio` d37k44pfh0i4bm）、スタック `amplify-jaddstudio-dev-2b103` と子 2 つ、Cognito のユーザープール `us-west-2_jb7jCOO9q` と ID プール、IAM のロール 4 本、Lambda 1 つ、S3 のバケット（deployment と storage）。使われていないことを確かめてから消す（Cognito のユーザー数、ID プールと Lambda の最終利用など）。

## ついでに見つかったこと

- `tuscenes-calibration-767397804933` は、cdk-apps の `apps/datalake/lib/datalake-stack.ts:399` では `S3_MANAGED` なのに、実物の既定の暗号化は `aws:kms`（`alias/aws/s3`）。オブジェクト 235 件のうち 228 件が KMS。CDK のコードと実物がずれている。
- 3 月に配った `jadd-studio-secrets.tgz` には、ほかの秘密（Supabase のサービスロールキー、Databricks の資格情報など）も入っている。それらが今も有効かは、この案件では確かめていない。

## 進捗と引き継ぎ

- 2026-10-23: 利用元を調べた（上記）。伊藤がキー 2 本を無効化した。削除を妨げる依存が無いことを確かめ、起票した。
- **次にやること**: TODO の 1（削除）。今日はやらない。
