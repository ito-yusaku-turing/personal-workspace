# IAM ユーザー jadd_studio_amplify を削除する

- 開始: 2026-10-23
- 状態: **ユーザーと Amplify の一式を削除した**（2026-10-26）。残りは苦情への対応と、[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) での返答
- 所属: project:aws-data-protection（2026-10-26 に `~/docs/workstream/` から移した）
- 実施: 伊藤（書き込みは Full の権限で CLI。このユーザーは CDK の管理外）
- 経緯: [S3 バケットのデータ保護 第二弾](s3-data-protection-2.md) の TODO 13 から切り出した。[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) のレビューで犬塚さん（graph226）が「cfn-exec-role を名乗れる主体」として挙げたユーザー

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
- 読み出しのあった 4 日すべてで、井上さん（inuex35）が `leverarm-calibration` をコミットしている（8/13 は 15:57〜19:11、8/14 は 15:50・17:36、9/28 は 17:33 の [cdk-apps#1043](https://github.com/turingmotors/cdk-apps/pull/1043)、10/16 は 18:34 の [cdk-apps#1190](https://github.com/turingmotors/cdk-apps/pull/1190)）。
- 調べて外したもの:
  - jadd_studio3 の本番。別のユーザー `jadd-studio` を使っている。PR ごとのプレビュー環境も無い。
  - Databricks のキャリブレーション取り込み。別のユーザーで、ロールを経由する。
  - scenario-test の Batch と backend-api。ロールで動く。
  - jadd-cli。backend-api を呼ぶだけ。
  - 伊藤のコンテナの `default` のプロファイル。キーが入っていない。
- ユーザー名もキー ID も、cdk-apps・mono-e2e・jadd-cli・databricks-jobs・drivers-app3・fleet-ops には出てこない（git 履歴を含む）。

### 推測（未確認）

- 8/13〜10/16 は、井上さんの手元の jadd_studio3 の開発サーバー。`.env.local` の AWS の行が 3 月のパッケージのまま、という筋。本人は「最近は触っていない」とのことで、10/16 より後の話なら矛盾しない。
- 10/23 11:30 は別の人。候補は中村さん（yutyan0119）。11:15〜11:35 に tern の渋滞表示（[cdk-apps#1244](https://github.com/turingmotors/cdk-apps/pull/1244)）を作業していた。手元の tern は `fromIni()` で資格情報を取るので、`AWS_PROFILE` が無いと `~/.aws/credentials` の `[default]` を使う。渋滞のバケット（`tern-traffic-767397804933-us-west-2`）は暗号化が AES256 でアクセスログも無く、記録では確かめられない。
- 一時は Devin を疑ったが、時刻の一致だけが根拠で、依頼者の 3 人（合田・三輪・横井）も知らないと答えたため取り下げた。

## 現状（2026-10-23）

- 2 本のキーはどちらも **Inactive**（伊藤が無効化した）。利用元は、悲鳴があがったところで特定する方針。
- 削除を妨げるものは無い（ReadOnly で確認）:
  - コンソールのログイン・MFA・署名証明書・SSH 鍵・サービス用の資格情報・グループ・インラインポリシーは、どれも無い。
  - ロール 692 件の信頼ポリシーとインラインポリシー、カスタム管理ポリシー 74 件、S3 のバケットポリシー 158 件のどれにも、このユーザーは出てこない。
  - 付いている管理ポリシーは 4 本。カスタムの `secretsmanager_GetSecretValue`（Resource は `*`）は、ほかに 2 つの主体に付いているので、ポリシーそのものは消さない。
- 様子見は要らない。漏れているキーを有効に戻すことはしないので、悲鳴への対処はどのみち「今のキーか SSO に切り替える」になる。削除しても無効のときと同じ `InvalidAccessKeyId` になるので、悲鳴で利用元を見つける効果も変わらない。

## TODO

1. ~~**ユーザーを削除する**~~ → 済み（2026-10-26 17:58 JST、伊藤）。（伊藤、Full の権限）。手順は [delete-runbook.md](jadd-studio-amplify-removal/delete-runbook.md) を正本にする（1 行ずつ貼る形。ループや変数は使わない。実行前後の確認と戻し方つき）。順番は、管理ポリシーを外す → キーを消す → ユーザーを消す。
   - ポリシーの ARN は 2026-10-23 と 10-26 に `list-attached-user-policies` で確かめたもの。
2. **悲鳴への対応**。jadd_studio3 の開発者には、次の 2 点を案内する。
   - `.env.local` の AWS の行を、今の `jadd-studio` のキーに差し替える。
   - tern は `AWS_PROFILE` に SSO のプロファイルを入れて動かす。
   - 古いキーが残っているかは、次のコマンドで確かめられる（値は出ない）: `grep -l HOC2HR6GHTY ~/.aws/credentials ~/.aws/config /usr/app/jadd_studio3/.env.local /usr/app/jadd_studio3/docker/.env 2>/dev/null`
3. **s3-data-protection-2 に反映する**。TODO 13 の jadd_studio_amplify を済みにする。[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) のレビューへの返答で、この主体が消えたことを伝える。
4. ~~**Amplify の一式を片付けるか決める**~~ → 済み（2026-10-26 に消した）。（2026-10-26 に片付けることにした。対象は下の「Amplify の一式の洗い出し」、手順書は [amplify-cleanup-runbook.md](jadd-studio-amplify-removal/amplify-cleanup-runbook.md)）（別に判断する。ユーザーを消しても残る）。対象は、アプリ 2 つ（`jadd_studio` d34n309gf2fupw・`jaddstudio` d37k44pfh0i4bm）、スタック `amplify-jaddstudio-dev-2b103` と子 2 つ、Cognito のユーザープール `us-west-2_jb7jCOO9q` と ID プール、IAM のロール 4 本、Lambda 1 つ、S3 のバケット（deployment と storage）。使われていないことを確かめてから消す（Cognito のユーザー数、ID プールと Lambda の最終利用など）。

## Amplify の一式の洗い出し（2026-10-26、ReadOnly、us-west-2）

TODO 4 の対象。どれも 2024-11-22〜23 に作られたまま、更新されていない。

| 種類 | 名前・ID | 使われているか |
| --- | --- | --- |
| Amplify アプリ | `jadd_studio`（d34n309gf2fupw） | ホスティングのみ。ブランチ `main` のビルドは 2024-11-23 の 1 回だけで、中身は create-react-app の雛形（`<title>React App`、644 バイト）。直近 90 日のリクエストは 3,501 件で 83% が 4xx、平均 400 バイト。ボットとみられる |
| Amplify アプリ | `jaddstudio`（d37k44pfh0i4bm） | ブランチ無し。バックエンド環境 `dev` だけ。リクエスト 3,030 件で 80% が 4xx。ボットとみられる |
| CFn スタック | `amplify-jaddstudio-dev-2b103` と、子の `…-authjaddstudioc386240f-…`・`…-storagejaddstudio-…` | 終了保護は無し。エクスポート 4 件は、どのスタックからも import されていない |
| Cognito ユーザープール | `us-west-2_jb7jCOO9q` | ユーザー 0、削除保護は無効、トリガー無し。直近 90 日の CloudTrail は AWS Config の読み取りだけ |
| Cognito ID プール | `us-west-2:cbda723b-956f-42ab-b71e-13cb59f28535` | ID 0、未認証は不可。直近 90 日の CloudTrail は Config の読み取りだけ |
| IAM ロール | `amplify-jaddstudio-dev-2b103-authRole`・`-unauthRole`・`-authRole-idp`・`upClientLambdaRolec386240f2b103-dev` | `-authRole-idp` の最終利用が 2024-11-22（作成時の Lambda）。ほかの 3 本は利用記録が無い |
| Lambda | `amplify-jaddstudio-dev-2b-UpdateRolesWithIDPFuncti-w97MZ0RwoviB`（nodejs18.x） | 直近 90 日の呼び出し 0 |
| S3 | `amplify-jaddstudio-dev-2b103-deployment` | Amplify の設定ファイル 11 件（2024-11-23）。バージョニング無し |
| S3 | `jaddstudioc20f7c0d8d4347b286666288f7a6c6d22b103-dev`（storage） | 空（版も削除マーカーも 0） |

- 参照: 上の ID・バケット名・アプリ ID は、jadd_studio3（git 履歴を含む）・cdk-apps・mono-e2e・drivers-app3・fleet-ops・databricks-jobs のどれにも出てこない。ほかの IAM ポリシーやバケットポリシーからの参照はスキャンしていない。
- 消すときの注意: バケット 2 本はテンプレートで `DeletionPolicy: Retain`。スタックを消しても残るので、中身を空にしてから別に消す。
- 対象外: `amplify-turingapps-main-127f9`（2024-12-05、タグ `user:Application=turingapps`）は名前が似ているが別物。

## ついでに見つかったこと

- `tuscenes-calibration-767397804933` は、cdk-apps の `apps/datalake/lib/datalake-stack.ts:399` では `S3_MANAGED` なのに、実物の既定の暗号化は `aws:kms`（`alias/aws/s3`）。オブジェクト 235 件のうち 228 件が KMS。CDK のコードと実物がずれている。
- 3 月に配った `jadd-studio-secrets.tgz` には、ほかの秘密（Supabase のサービスロールキー、Databricks の資格情報など）も入っている。それらが今も有効かは、この案件では確かめていない。

## 進捗と引き継ぎ

- 2026-10-23: 利用元を調べた（上記）。伊藤がキー 2 本を無効化した。削除を妨げる依存が無いことを確かめ、起票した。
- 2026-10-26: 削除の前に ReadOnly で見直した。10-23 から変わりなし。管理ポリシーは同じ 4 本、キーは 2 本とも Inactive、ログイン・MFA・証明書・SSH 鍵・サービス用の資格情報・インラインポリシー・グループは 0。`secretsmanager_GetSecretValue` の付け先は 3（このユーザーを外すと 2 が残る）。キーの最終利用は 1 本目の 10-23 02:30 UTC（無効化の 07:05 UTC より前）で、2 本目は未使用。無効化の後、us-west-2・us-east-1・ap-northeast-1 の CloudTrail にこのユーザーやキーの記録は無い（S3 の失敗はデータイベントなので記録されない。手がかりにならない）。ロール・ポリシー・バケットポリシーからの参照の再スキャンはしていない。
- 2026-10-26: 伊藤が [delete-runbook.md](jadd-studio-amplify-removal/delete-runbook.md) のとおりに削除した（17:57〜17:58 JST）。ReadOnly で、`get-user` が NoSuchEntity になること、`secretsmanager_GetSecretValue` の付け先が 2 になったことを確かめた。CloudTrail（us-east-1、09:00 UTC 時点）に `DetachUserPolicy` 4 件（4 本すべて）・`DeleteAccessKey`（…GHTY）・`DeleteUser` が出ていて、どれもエラーは無い。2 本目（…XTTO）の `DeleteAccessKey` はまだ届いていなかった。`DeleteUser` が成功したので、ポリシーとキーは残っていない（残っていれば `DeleteConflict` になる）。
- 2026-10-26: 伊藤が [amplify-cleanup-runbook.md](jadd-studio-amplify-removal/amplify-cleanup-runbook.md) のとおりに Amplify の一式を消した。ReadOnly で確かめた結果:
  - スタック 3 つは DELETE_COMPLETE（09:14 UTC）。失敗は無く、DELETE_SKIPPED は `Retain` のバケット 2 本だけ（想定どおり）。エクスポートも消えた。
  - Amplify のアプリは us-west-2 に 0。Cognito のユーザープール・ID プール、IAM ロール 4 本、Lambda はどれも見つからない。
  - バケット 2 本は `head-bucket` が 404。Lambda のロググループも無い。
  - 消さない `amplify-turingapps-main-127f9` は CREATE_COMPLETE のまま。
- **次にやること**: TODO 2（苦情が出たら案内する）、TODO 3 の残り（[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) のレビューへの返答で、この主体が消えたことを伝える）。返答の投稿は伊藤の了承を取ってから。
