# S3 バケットのデータ保護 第二弾（権限設計のアップグレード）

- 開始: 2026-10-20
- 状態: **BreakGlass 権限の提案（第一版）を Notion に上げ、チームの議論待ち**（2026-10-29）。次は議論の結果を原本に取り込む。WORM 化の検討（TODO 26）は未着手。ステージ 2 の監視は保留
- 所属: project:aws-data-protection（2026-10-26 に `~/docs/workstream/` から移した）
- 前段（第一弾、完了）:
  - [走行データ消失リスクへの対応](done/raw-data-security.md)（バケットの種別と処遇、裁定の正本）
  - [原本バケットのバージョニング（cdk-apps）](done/s3-versioning-cdk.md)
  - [原本バケットへのアクセスの洗い出し](done/s3-bucket-access-control.md)（誰が何をできるかの表。本資料の根拠）
- 共有用の資料: [permission-upgrade-plan.md](s3-data-protection-2/permission-upgrade-plan.md)（2026-10-21 に Notion に上げた。2026-10-26 に手元の写しを 10-21〜22 の決定に合わせて直したので、上げ直しが要る）
- 参考資料: [AWS の権限の階層](../documents/aws-privilege-hierarchy.md)（一般論と、管理アカウントへの CI の経路の調査）
- 用語: S3 の Versioning は「バージョニング」。旧版を指すときは「古い版」
- 番号の付け方: 案件は「第一弾・第二弾」、第二弾の中の手順は「ステージ 1〜4」、TODO は通し番号で「TODO 6」のように呼ぶ（2026-10-22。以前の「第 1 段」「P1」はやめた）

## 背景

第一弾で、原本バケット 12 本にバージョニングを入れ終えた（2026-10-20）。ふつうの削除・上書きは戻せるようになった。

一方で、古い版ごと消す操作と、守りを外す操作（バージョニングの停止・ライフサイクル・バケットポリシー・バケットの削除）ができる主体が 37 ある。主な原因は次の 3 つ。

- CDK の `grantReadWrite` が古い版の削除まで許す。
- 最大権限の持ち主が多い。
- root に MFA が無い（別案件で認証情報を消す。[aws-root-credentials.md](aws-root-credentials.md)）。

第二弾では、これを権限設計から直す。

## 決まったこと（2026-10-20）

目指す形（共有用のプランの 4 原則）と、レビューの結果の優先順は、伊藤が妥当と判断した。チームの合意はこれから取る。

1. 最大権限を持つのは人間だけにし、人数を必要最小限に絞る（例外は IaC の deploy の経路と、AWS が管理するロール）。
2. 古い版の削除と守りを外す操作は、break-glass の人だけに限る。意図して大量に消すときは、ライフサイクルで消す。
3. 最大権限の人は MFA を必須にする（Okta 側で強制）。root は認証情報を無くす。
4. 普段は使わず、必要なときに昇格する（承認ではなく、短いセッション＋通知）。

## TODO（優先度順）

### 優先度の変更（2026-10-29、伊藤）

**次の 2 件を先にやる。ステージ 2 の監視の仕組み（PR-A 以降）は保留にする。**

- **BreakGlass の議論と設計**（TODO 10・11。ステージ 3 から前に出した）。ステージ 1 の暫定の例外（FullAccess・AWSAdministratorAccess）を差し替える先であり、WORM 化の案 A（ガバナンスモードの迂回を BreakGlass だけに許す）の前提にもなる。今の設計案は [permission-upgrade-plan.md](s3-data-protection-2/permission-upgrade-plan.md) の「ステージ 3 の詳細」と「break-glass の権限セットはどれか」。名簿（誰を BreakGlass にするか）はまだ無い。
- **原本バケットの WORM 化の検討**（TODO 26）。

保留にしたもの（再開するときは「進捗と引き継ぎ」の 10-27 の引き継ぎと 10-29 の記録から）:
- Slack の bot の準備（0-2・0-3）、PR-A（毎時の集計と報告）、PR-B（12 本への拡大）。
- 守りの設定の変更は EventBridge で受けると決めた（10-29）。管理イベントが default のバスに流れるかは未確認。
- カナリアの失効の確認（ReadOnly で見るだけなので、手が空いたときにやってよい）。カナリアは、WORM 化の検証でも使う。

26. **原本バケットの WORM 化（S3 Object Lock）を検討する**（2026-10-29 に優先度を上げた）。整理の資料は [S3 Object Lock（WORM）の整理](../documents/notion-s3-object-lock.md)（2026-10-26、Notion に上げてある）。
    - 決めること（資料の 8 章）: 対象のバケット、モード（コンプライアンスかガバナンスか）、鍵の種類と期間（固定か、可変の保持期間か）、消す必要が出たときの手順、既存の版にさかのぼって鍵をかけるか、アカウントの閉鎖にも備えるか。
    - 資料の推奨（9 章）: カナリアとは別の使い捨てのバケットで試す。監査ログのバケットから入れる。原本は案 A（ガバナンス ＋ RCP で迂回を BreakGlass だけに許す）か、案 B（コンプライアンス ＋ 可変の保持期間）。
    - BreakGlass（TODO 10）と、SCP・RCP（TODO 24）に関わる。

### すぐやる

1. **共有用のプランをチームに出す**（~~[permission-upgrade-plan.md](s3-data-protection-2/permission-upgrade-plan.md) を Notion に上げる~~ → 済み（2026-10-21。「進捗と引き継ぎ」の 10-21）。2026-10-26 に手元の写しを 10-21〜22 の決定に合わせて直したので、Notion への上げ直しが要る）。「決めてほしいこと」の 1〜4 への回答を集める。とくに break-glass の人を誰にするか（名簿はまだ無い）。
2. **root の認証情報の削除**は別の案件にした（[メンバーアカウントの root の認証情報を消す](aws-root-credentials.md)。CorpIT に依頼する）。S3 の案件としては、進み具合を見るだけにする。

### ステージ 1: バケットポリシーの Deny

**例外は暫定で SSO の FullAccess と AWSAdministratorAccess にする**（2026-10-21 決定）。BreakGlass の権限セットと名簿を待たずに入れ、BreakGlass ができたら例外の行を差し替える（TODO 10）。これで人以外の主体（アプリ・Databricks・IAM ユーザー・使われていないロール・TeamE2E）は全部止まる。

3. ~~**バケットポリシーの文を書く**~~ → 済み（2026-10-21）。[bucket-policy/](s3-data-protection-2/bucket-policy/)
   - `statements.json`: 2 文の雛形。消す操作の例外は暫定の 2 つ、守りを外す操作は加えて `cdk-hnb659fds-cfn-exec-role-767397804933-*`。
   - `render.py`: 今のポリシーに 2 文を足した全文を `rendered/` に作り、Access Analyzer の `validate-policy` にかける。12 本とテスト用の 13 本すべて指摘なし。
   - `simulate.sh`: ポリシーシミュレーターで主体ごとの許可・拒否を確かめる。td1-raw・denso-raw で想定どおり（下の注）。
   - 注: td1-raw・tuscenes-raw では、FullAccess の既存の Deny（`s3:DeleteObject*`）が残るので、FullAccess でも古い版を消せない（削除マーカーを消す復旧もできない）。できるのは AWSAdministratorAccess（`Engineers` の 1 名）だけ。今と同じ状態。
4. ~~**検証用のバケットで試す**~~ → 済み（2026-10-21）。使い捨てのバケットで、伊藤が [test-bucket.sh](s3-data-protection-2/bucket-policy/test-bucket.sh) を Full 権限で実行した。例外以外の主体は 12 操作が期待どおり（ふつうの削除・上書きは許可、残り 10 は拒否）。FullAccess はポリシーの上書き・バージョニング・古い版の削除ができ、締め出されない。後片付けも ReadOnly で確認した。確かめたこと:
   - 例外以外が拒否される（一時的なロールで試す）。
   - 例外の主体がポリシーを直せる（締め出されない）。
   - ~~Control Tower・StackSets のロールが止まっても困らない~~ → 困らない（2026-10-21、ReadOnly で確認）。3 本（`AWSControlTowerExecution`・`aws-controltower-AdministratorExecutionRole`・`stacksets-exec-ff6b…`）とも直近 90 日の CloudTrail に呼び出しが 0 件（最終利用は 2025-09-12・未使用・2026-02-02）。このアカウントの StackSet のスタック 9 個は Control Tower の基本設定と SSM の Quick Setup で、S3 は SSM 用のバケット 2 本だけ。12 本には触れていない。
   - ~~deploy の経路（cfn-exec-role）は、B3 の datalake の PR で `tuscenes-calibration-test` に入れて確かめる。~~ → 済み。`tuscenes-calibration-test` では試さず、本番で確かめた（2026-10-22 にシミュレーターで cfn-exec-role が書き換えられることを確認（TODO 7）。2026-10-23 に [cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) の deploy で cfn-exec-role が denso-raw に `PutBucketPolicy` し、スタックの更新も完了した（「進捗と引き継ぎ」の 10-23））。
5. ~~**Databricks**: 直近 90 日に、Databricks のロールによるライフサイクルの読み書きは 0 件（`GetBucketLifecycle` 約 4.5 万件・`PutBucketLifecycle` 15 件を確認。2026-10-21）。別の検証は立てず、本番の 1 本目で Unity Catalog が動くかを見る。~~ → 済み（2026-10-23。denso-raw に入れた前後で、Databricks の `denso.default.raw` から書き込みと削除ができた。「進捗と引き継ぎ」の 10-23）。
6. ~~**本番の 1 本目に入れる**（[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252)）~~ → 済み（2026-10-23。結果は「進捗と引き継ぎ」の 10-23）。denso-raw。共通部 `packages/original-bucket-guard` もこの PR で足す。マージ後 30 分〜1 時間、Unity Catalog の読み書きと CloudTrail の AccessDenied を見る。
7. ~~**残りの 11 本に入れる**（[cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253)）~~ → 済み（2026-10-26。結果は「進捗と引き継ぎ」の 10-26）。
   - 2026-10-22 の方針の変更（伊藤が決定）:
     - **手で作った 3 本（td1-rlog・tuscenes-calibration（旧）・denso-raw）も CDK で持つ。** datalake の `CfnBucketPolicy` として持ち、バケット自体は管理外のまま。例外の主体を 1 か所で変えられるようにするため。3 本ともどのスタックにも属さず、今のポリシーも無いので、ぶつかる文は無い。
     - **様子を見る期間は 1 週間でなく、同じ日のうちの 30 分〜1 時間にする。**
   - 確かめたこと（2026-10-22）:
     - 変更前後の synth を比べ、差が 12 本のバケットポリシーだけで、既存の文がすべて残ることを確かめた。比べるときは `cdk.json` の context を渡すこと（渡さないと、`minimizePolicies` などが効かずに大量の差が出る）。道具は `bucket-policy/` の `synth-compare.sh`（synth）・`compare-templates.py`（template の比較）・`extract-final.py`（最終形のポリシーを具体値で書き出す）。
     - deploy 済みの template と main の synth の間に、差は無かった。
     - 12 本の最終形のポリシーが、`statements.json` と同じ文であること（Action の並び順を除く）。Access Analyzer の指摘は無い。
     - シミュレーターで、cfn-exec-role がポリシー・バージョニング・ライフサイクルを書き換えられることを確かめた。書き換えられないと、deploy が失敗し、ロールバックまで拒否されてスタックが止まるため。
     - 古い版を消すコードは、cdk-apps にも mono-e2e にも無い。

### ステージ 2: 削除の検知（ステージ 1 と並行してよい）

**要件（2026-10-22 伊藤が決定）**:
- 前日（JST の 0〜24 時）の削除を、毎朝 10 時に Slack に報告する。中身は「誰が・どのバケットで・何件・何バイト」。ログとしても残す。
- 本人にメンションを付ける。意図しない操作なら、まず本人が気づく仕組みにする。
- 手段は問わない。費用もかけてよい。
- 同日の追加の決定:
  - バイト数は S3 Inventory から取る（費用は問題ない）。
  - 削除が無いときは投稿しない。
  - 新しいアプリとして作る（cdk-apps）。
  - Slack のセットアップ（チャンネル・bot）は後で決める。
  - **毎朝ではなく 1 時間ごとに報告する。大量に消したときは、即座に強く鳴らす。** 生データはめったに消さないため。
  - 即時のアラートはオプションとしてスコープから外し、毎時の報告に絞る。届いた時刻で区切ってよいが、取りこぼさないことが前提。保存期間は見積もりどおり（報告 3 年・生のイベント 1 年・Inventory 7 日、月約 $60）。見張りは後回し。アプリ名は `original-bucket-audit`。
  - 設計: [stage2-hourly-report.md](s3-data-protection-2/stage2-hourly-report.md)。
  - 検証は、個人のアカウントではなく tuscenes-prod に**常設のカナリア**（原本バケットと同じ条件の検証用のバケット）を置いて行う（2026-10-22 伊藤が決定）。カナリアにもステージ 1 のバケットポリシーを入れる。今後の検証（例外の差し替えなど）と、毎時の報告の見張りにも使う。
  - [cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267)（`apps/original-bucket-audit`、[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) の上に積んだ）: カナリアと、記録を集める仕組み（EventBridge・Firehose・トレイル・Inventory・ログのバケット）。監査の対象はカナリアだけ。毎時の集計と 12 本への拡大は次の PR。チームのレビューを経て deploy する。 Copilot の指摘 2 件（deploy の直列化・バージョニングしたログの古い版が残る）に対応し、再レビューで指摘なし。CI も全部通った。チームのレビュー待ち。

8. **root の案件との接点を押さえる**（root の側は別の案件）。
   - root の一元管理が入ると、管理アカウントの管理者が `S3UnlockBucketPolicy` でバケットポリシーを消せる。これはステージ 1 で締め出されたときの戻し道になる。一方で、守りを外せる経路にもなる。
   - そのため、管理アカウントで最大権限を持つ人も、最大権限を持つ人に数える。
9. **削除のデータイベントを記録する**。~~12 本の書き込み系だけ。費用を見積もってから決める（書き込みは少ないはず）。古い版の削除・ライフサイクルの変更を通知する。~~ → 範囲と費用は上の要件で決めた（2026-10-22）。記録は 12 本の `DeleteObject`・`DeleteObjects` だけ（データイベントは月 $1 未満、仕組み全体で月約 $60）。通知は毎時の報告にし、即時のアラートはスコープ外。設計は [stage2-hourly-report.md](s3-data-protection-2/stage2-hourly-report.md)、1 本目の PR は [cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267)（対象はカナリアだけ）。
24. **SCP・RCP で 2 枚目の守りを足す**（2026-10-23。[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) のレビューで graph226 さんの指摘から）。バケットポリシーは例外の主体なら書き換えられるので、tuscenes-prod の中から外せない守りを重ねる。仕様を調べてから決める。
    - `cdk-hnb659fds-*` のロールの作成・削除・信頼の変更を Deny する。[cdk-apps#2150](https://github.com/turingmotors/cdk-apps/pull/2150) の `iam-guardrails` の `DenyReservedPathRoles` と同じ形。deploy のロールを名乗る抜け道を、主体がだれでも塞げる。
    - 12 本への `DeleteObjectVersion` などの Deny を SCP か RCP に重ねる。
    - 調べること: RCP の対象（S3 は可）・root にどう効くか・サービスにリンクされたロールの扱い・SCP との違い（他のアカウントの主体に効くか）・大きさの上限。
    - 経路は cdk-apps の `apps/organization-policy`（管理アカウントに deploy）。
25. ~~**tuscenes-raw のルール `tuscenes-NewTripEventRule…` を止める**~~ → 済み（2026-10-27。伊藤が止め、`DISABLED` を ReadOnly で確かめた）。（2026-10-27 決定。PR-B の前に要る）tuscenes-raw の EventBridge を有効にすると、古いスタック `tuscenes` のこのルールが動き出し、cleaning の job・Supabase・Slack への投稿が起きるため。伊藤が Full 権限で止める。持ち主への確認はしない（本件の障害を自らの手で取り除く）。スタック全体の片付けは別の資料にした（[tuscenes-stack-cleanup.md](tuscenes-stack-cleanup.md)）。
    - 手順（伊藤、Full 権限）:
      ```bash
      aws events disable-rule --region us-west-2 --name tuscenes-NewTripEventRule9F52899F-dXQQ5emHVD08
      ```
    - 止めた後の確認（エージェント、ReadOnly）: `aws events describe-rule --region us-west-2 --name tuscenes-NewTripEventRule9F52899F-dXQQ5emHVD08 --query State` が `DISABLED`。
    - 戻すとき: 同じ名前で `aws events enable-rule`。
    - PR-B では、datalake の `eventBridgeEnabled: false, // cleaning 処理に必要` のコメントを、経緯（ルールを止めたこと・監査のアプリが EventBridge を入れること）が分かるように直す。この指定はテンプレートに何も生まないので、datalake の deploy で監査の EventBridge が消えることは無い。

### ステージ 3: 人の権限

10. **権限セットを分ける**。普段用と昇格用（BreakGlass。名簿は identity の Okta グループ、割り当ては cdk-apps）。できたらステージ 1 の例外を BreakGlass に差し替える。FullAccess（14 名）・AWSAdministratorAccess の持ち主を棚卸しし、昇格用を持つ人を必要最小限に絞る。チームへの周知が要る。
11. **Okta で MFA を強化する**。昇格用のアプリにフィッシングに強い要素を必須にする（identity の担当と相談。`/usr/app/identity`）。

### ステージ 4: 主体の掃除（急がない）

12. **`grantReadWrite` を見直す**。版の削除ができる 5 本は、すべて `grantReadWrite` が原因（2026-10-20 に確認）。
    - backend-api（`apps/backend-api/lib/api.ts:514`、tuscenes-model）
    - modelcore-build（`apps/modelcore-build/lib/modelcore-build-stack.ts:134`）
    - model-converter（`apps/model-converter/lib/model-converter-sfn.ts:314`）
    - denso-nx の抽出（`apps/denso-nx/lib/extractor-batch.ts:175`。mp4 を書くだけなのに td1-raw 全体）

    書き込みとプレフィックスに絞る。cdk-apps に Aspect などの再発防止を置くかも検討する。
13. **IAM ユーザーと長期キーを片付ける**。
    - `tokyo30-dataupload-pc-01`：td1-raw ほか 3 本でバケットの削除まで可能。今も使用中なので、持ち主に確認する。
    - `AmazonS3FullAccess` の 4 本：jadd-datasync、jadd-remote-sync-kohei.watanabe、jadd_studio_amplify、shio-secretsmanager_GetSecretValue。
    - **jadd_studio_amplify**（2026-10-23 に正体を調べた）。Amplify CLI の時代（2024-11-22、初代 jadd_studio）に `amplify configure` で作ったユーザー。`AmazonS3FullAccess`・`AdministratorAccess-Amplify`・`AmplifyBackendDeployFullAccess`・`secretsmanager_GetSecretValue` を持つ。cfn-exec-role を名乗れるので、ステージ 1 の守りを外せる（[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) のレビュー）。
      - **2026-10-26 にユーザーを削除した**（伊藤）。cfn-exec-role を名乗れる抜け穴の主体の 1 つが消えた。[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) のレビューへの返答は対処不要とした。
      - **別の資料に切り出した: [jadd_studio_amplify を削除する](done/jadd-studio-amplify-removal.md)**（2026-10-23）。利用元の調査の結果・削除の手順・Amplify の一式の扱いはそちらが正本。
      - 要点: キーは 2 本とも 2026-10-23 に無効化した（伊藤）。利用元の最有力は、jadd_studio3 の開発者の手元の `.env.local`（3 月に配った秘密情報のパッケージにこのキーが入っていた）。Devin の線は取り下げた。削除を妨げる依存は無い。
      - PR には、キーが漏れていることを書かない（「ステージ 4 で片付ける」とだけ書いた）。
14. **使われていない強いロールを消す**。ecsTaskExecutionRole、AmazonEMRStudio_RuntimeRole、CodeCatalyst、tuscenes-sampler-test、sfn-auto-labeling、tuscenes-processing（どれも最終利用は 1 年以上前）。cdk の us-east-2 の bootstrap は使う予定を確かめてから。
15. **SSO の JADDViewer を見直す**。名前は閲覧用だが、`DataScientist` で 12 本の削除・上書きができる。

### 第一弾からの持ち越し（作った人に確認する。後回し）

16. **LidarDeleter・S3BatchDeleteLidar**：周知するか、信頼ポリシーを外すか。ステージ 1 が入れば古い版は消せなくなるが、間引きを再開すると古い版が残り、課金が続く。間引きはライフサイクルで行う形に改める（原則 2）。
17. **denso-nx-raw の Azure 側の件数の減少**：10-14 までの 187,810 件が、10-17 以降は 0 件。調査書の G01 の前提が崩れている可能性がある。
18. ~~**[cdk-apps#2231](https://github.com/turingmotors/cdk-apps/pull/2231)**（azure-data-sync の変更で denso の deploy・diff を走らせる）：作った人に確認してから進める。それまでレビュー依頼・マージはしない。~~ → 閉じた（2026-10-27。同じ 3 行が [cdk-apps#2285](https://github.com/turingmotors/cdk-apps/pull/2285) で main に入っていたため）。
19. ~~**azure-data-sync の SAS の次のローテーション**：今の SAS は 2026-10-26 まで有効。その前の自動のローテーションと、次の日の DataSync の成功を確かめる。~~ → 済み（2026-10-27。自動のローテーションが 10-25 に走り、その後の DataSync も成功。「進捗と引き継ぎ」の 10-27）。

### 第一弾からの持ち越し（チームの合意待ち）

20. **バケットの種別の記事を Notion に上げ直す**（[`done/raw-data-security/notion-bucket-classification.md`](done/raw-data-security/notion-bucket-classification.md)。10-19 の変更を反映済み。2026-10-26 に、tuscenes-calibration（新）の失効の記述と denso-nx-raw の件数の記述も手元の写しで直した）。
21. **databricks-workspace-e2e-bucket の A 案**（バージョニングを入れない）をチームで議論する。S3 を直接消されることへの手当ては、ステージ 1 と同じバケットポリシーで考えられる（Databricks のロール以外の削除を拒否する）。
22. **調べ残し**：手で作ったバケットの持ち主と出所、tuscenes-calibration（旧）の写しの有無、他アカウント（amman-pipeline・e2e-dev・biz-dev）の同じ集計。（2026-10-27: `alphaspp-raw`・`alphaspp-data` の出所は tuscenes-infra（スタック `alphaspp-pipeline`、削除済み）と分かった。tuscenes-basicai-datasets はスタック `tuscenes` の管理下。どちらも [tuscenes-stack-cleanup.md](tuscenes-stack-cleanup.md) に書いた）
23. **datalake の td1-raw の通知の設定**: datalake は td1-raw の通知を CDK の「丸ごと上書き」の方式（`Managed: true`）で持っている。datalake の通知の設定を変えて deploy すると、Databricks の auto-ingest の通知が消えるおそれがある（2026-10-22 に気づいた。ステージ 2 の設計を参照）。
    - **2026-10-27 に調べた（結果は「進捗と引き継ぎ」の 10-27）。** 監査のアプリ（PR-B）と td1-raw はぶつからない。一方で、td1-raw には監査とは関係なく前からある危険が 1 つある。また、tuscenes-raw に EventBridge を入れると、止まっている cleaning の処理が動き出すおそれがあることが分かった。

## 進捗と引き継ぎ

- 2026-10-20: 起票した。第一弾の 3 本を `done/` に移した。共有用のプランを書いた。
- 2026-10-20: root の現状を ReadOnly で確かめた（記録は aws-root-credentials.md に移した）。root の認証情報は削除する方針に決め、CorpIT に依頼することにした。
- 2026-10-20: root の件を別の案件に切り出した（[aws-root-credentials.md](aws-root-credentials.md)）。
- 2026-10-21: Notion の記事に 5 件のコメント（12 本の内訳・データイベントの費用・ステージ 3 の詳細・break-glass の権限セット・Databricks のライフサイクルの権限）が付いた。回答を共有用のプランの末尾に「2026-10-21 追記」として足した。Databricks の権限は古い CFn の雛形由来で、今の公式ドキュメントには無い（TODO 5 の検証は予定どおり行う）。
- 2026-10-21: 回答を Notion の記事に反映した。break-glass の名簿はまだ無い。候補は tuscenes-prod の FullAccess 13 名（identity の第 3・第 4 グループの役員・正社員）と `Engineers` の 1 名。ステージ 1 は、例外を暫定で FullAccess・AWSAdministratorAccess にして先に進めることにした。ポリシーの雛形・検証のスクリプトを書き、13 本で `validate-policy` とシミュレーターを通した。
- 2026-10-21: 使い捨てのバケットでの検証が全項目 OK だった（TODO 4）。Control Tower・StackSets のロールも 12 本に触れていないことを ReadOnly で確かめた。
- 2026-10-21 のセッションの終わり。引き継ぎ:
  - **運用の前提**: エージェントは AWS を ReadOnly（`--profile readonly`）でだけ使う。少量の読み取りは無断でよく、大量のスキャンは指示を受けてから。書き込みは伊藤が Full 権限で行う。CDK は `cdk diff` で確かめてから GitHub でマージし、deploy は GitHub Actions に任せる（`cdk deploy` はしない）。一時的なリソースや手で作ったバケットは CLI の手順書を渡す。
  - **次にやること**: TODO 6（本番の 1 本目に入れる）。
    1. 1 本目を決める。推奨は denso-raw。CLI ですぐ戻せる、既存のポリシーが無い（2 文だけになる）、Databricks のロール（`databricks-s3-ingest-9bf18-db_s3_iam`。最終利用 10-09）が付いていて Unity Catalog も見られる。伊藤の了承はまだ。
    2. 手順書を書く（`bucket-policy/` に置く）。中身は、入れる前の確認（ポリシーが無いこと）、`put-bucket-policy`、入れた後の確認、戻す手順（例外の主体で `delete-bucket-policy`）。ポリシーの全文は `render.py` で `rendered/` に作り直す（今のポリシーを読み直すため）。
    3. 入れた後に確かめること: Unity Catalog の external location で読み書きできるか（Databricks の担当に依頼するか、伊藤が確かめる）。CloudTrail の管理イベントで、denso-raw への AccessDenied が出ていないか（ReadOnly で見る）。1 週間ほど様子を見てから TODO 7 に進む。
  - **期限があるもの**: TODO 19（azure-data-sync の SAS は 2026-10-26 まで）。
- 2026-10-22: 12 本のバケットポリシーを cdk-apps の 2 本の PR にした（[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252)・[cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253)）。手で作った 3 本も CDK で持つことにし、同じ日に 2 回に分けて入れることにした（TODO 6・7）。
  - 次にやること:
    - ~~2 本の PR で、Copilot の指摘を片付ける~~ → 済み。[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) の 1 件（テストが Sid しか見ていない）に対応し、2 文の中身を丸ごと確かめるテストを足した。再レビューでは両方とも指摘なし。CI も全部通った。
    - チームにレビューを頼む（CODEOWNERS で、チームは PR を作った時点でレビュアーに入っている）。
    - [cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) をマージし、denso-raw で Unity Catalog と AccessDenied を確かめる。そのあと [cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253) をマージする。
    - 入ったら、12 本のポリシーを `get-bucket-policy` で確かめる。
  - 注意: [cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253) は [cdk-apps#2231](https://github.com/turingmotors/cdk-apps/pull/2231) と、denso の workflow の同じ箇所を触る。後からマージする側で行をそろえる。
- 2026-10-23: [cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) が graph226 さんに approve された。指摘 4 件に対応した。
  - テストの workflow の `paths` に共通部を足した（debb6f4c）。
  - README に「守りの前提と、残っている抜け穴」を書いた（9a2386b4）。対象は、deploy のロールを名乗れる主体・root・管理アカウントの管理者。SSO の例外は [cdk-apps#2150](https://github.com/turingmotors/cdk-apps/pull/2150) の SCP に頼っている。
  - PR 本文に「バケットポリシーにした理由」「残っている抜け穴」を足し、手順 2（AccessDenied では古い版の削除の拒否が見えない）を直した。返事も投稿した。
  - 方針（伊藤が決定）: バケットポリシーで取り急ぎ対応する。抜け穴は承知のうえで書いておく。SCP・RCP は仕様を調べてから、2 枚目の守りとして予定する（TODO 24）。
  - 抜け穴の主体 `jadd_studio_amplify` の正体を調べた（TODO 13）。
  - **[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) をマージし、denso-raw に入れた**（2026-10-23 13:57 JST マージ、13:59 に Datalake スタックの更新完了）。
    - `get-bucket-policy` で 2 文が仕様どおりに入ったことを確かめた（ほかの文は無い）。
    - Databricks（`denso.default.raw`、伊藤の主体）で、入れる前（13:55〜13:56）と後（14:41）の両方で、書き込みと削除ができた。読み取りは入れる前に確認した。テストのファイルは `_policy-check/` に置いた（古い版と削除マーカーが残っている。伊藤が FullAccess で消す。例外の主体なら古い版を消せることの確認を兼ねる）。
    - CloudTrail（〜15:27）: deploy の後の denso-raw の操作は、cfn-exec-role の `PutBucketPolicy` の 1 件だけで、AccessDenied は無い。S3 全体の AccessDenied は 4 件あったが、すべて別のバケット（Databricks の `GetBucketNotification` 2 件、diff のロールの assets のバケット 2 件。どれも前からあるもの）。
  - [cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253)・[cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) に main を取り込み、squash マージによる競合を解いた（d741d5b2 を基準に 3-way。結果と main の差が各 PR 自身の差分と一致することを patch-id で確認）。push 済み。
  - [cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253) の本文を現状に合わせて書き直した。「[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) の上に積んだ」を消し、「1 本目の結果（denso-raw）」の節と「残っている抜け穴」（手で作った td1-rlog・tuscenes-calibration（旧）にも及ぶ）を足した。手順 3 に「データイベントは記録していないので、書き手のいるバケットではアプリ側のエラーで見る」と書き添えた。gaming-data-collection のテストは、もともと CI で走っていないことも書いた。
  - [cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) の本文の古い記述（「[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) の上に積んだ…main に向け直す」）を直し、守りの表の状態を「denso-raw は済み（[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252)）、残りの 11 本は [cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253)」にした。
  - CI は [cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253) が 12 件、[cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) が 10 件、すべて通過。どちらも MERGEABLE で、BLOCKED は承認待ちのため。
- 2026-10-22 のセッションの終わり。引き継ぎ:
  - **レビュー待ちの PR**（cdk-apps。どれもチームの承認待ち。CODEOWNERS でチームはレビュアーに入っている。Copilot は指摘なし、CI は通過）:

    | PR | 中身 | base | マージ後にやること |
    | --- | --- | --- | --- |
    | [cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) | ステージ 1: 共通部 `packages/original-bucket-guard` と denso-raw の 1 本 | main | Actions の `datalake-deploy` の成功を確かめる。30 分〜1 時間、Unity Catalog で denso-raw を読み書きできること（Databricks の担当か伊藤）と、CloudTrail に denso-raw への AccessDenied が無いこと（ReadOnly）を見る |
    | [cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253) | ステージ 1: 残りの 11 本 | [cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) のブランチ | 4 アプリの deploy の成功、12 本の `get-bucket-policy`（ReadOnly）、1 時間ほど AccessDenied を見る |
    | [cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) | ステージ 2 の 1 本目: `apps/original-bucket-audit`（カナリアと記録の仕組み。対象はカナリアだけ） | [cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) のブランチ | 下の「[cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) の deploy の後」 |

  - **マージの順番**: [cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) → [cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253) → [cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267)。マージは伊藤が行う（エージェントは `gh pr merge` しない）。
    - [cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252) が入ると、[cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253) と [cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) の向け先は自動で main に変わる。競合や古さがあれば main を取り込む（force push はしない）。
    - [cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) は原本バケットに触れないので、[cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253) の様子見を待たなくてよい。
  - **[cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) の deploy の後**（確認の 4 点。設計: [stage2-hourly-report.md](s3-data-protection-2/stage2-hourly-report.md)、手順: cdk-apps の `apps/original-bucket-audit/README.md`）:
    1. ReadOnly: `aws s3api get-bucket-notification-configuration --bucket original-bucket-canary-767397804933` に、`canary-external`（SNS）と `EventBridgeConfiguration` の両方があること。
    2. 伊藤（書き込みの権限）: `aws lambda invoke --function-name original-bucket-canary-exerciser --region us-west-2 out.json`。`out.json` に各操作の request-id が出る。
    3. 15 分後に ReadOnly で、ログのバケット `original-bucket-audit-logs-767397804933` の `events/`（Firehose。GZIP、JSON が区切りなしに連なる）と `trail/` を読み、次を確かめる。
       - request-id のつながり。
       - 一括削除の出方（S3 のイベントがオブジェクトごとか、CloudTrail の eventName・キー）。
       - `deletion-type`・`reason`・`size`。
       - 古い版の削除が AccessDenied になること。
    4. 1〜2 日後に、失効（`expire/`）のイベントを確かめる。
    5. 結果を設計の資料に書く。次の PR は、トレイルを削除系に絞ること、毎時の集計（Lambda・Athena。未処理のファイルを拾う、保留、重複の除去、日次の突き合わせ）、原本バケット 12 本を足すこと。
  - **決まっていない・後回し**: Slack（チャンネルと bot）、見張り（カナリアで定期的に削除を起こす）、即時のアラート（オプション）、ロールと担当者の対応表。
  - **伊藤にお願いしたこと**: Notion の共有用プランの「第 N 段」「段階」を「ステージ N」に直す（[`permission-upgrade-plan.md`](s3-data-protection-2/permission-upgrade-plan.md) は直し済み）。
  - **作業場所**: cdk-apps の作業は、エージェントの一時ディレクトリの worktree で行った。ブランチはすべて push 済みなので、次のセッションでは `/usr/app/cdk-apps` から worktree を作り直せばよい（`/usr/app/cdk-apps` 自体は触っていない。未追跡の `apps/valhalla-turing-api` は伊藤のもの）。PR の本文は GitHub 上のものを正とする。
  - **期限があるもの**: TODO 19（azure-data-sync の SAS は 2026-10-26 まで。その前の自動のローテーションと、次の日の DataSync の成功を確かめる）。
  - **注意**:
    - [cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253) は [cdk-apps#2231](https://github.com/turingmotors/cdk-apps/pull/2231) と、denso の workflow の同じ箇所を触る。後からマージする側で行をそろえる。[cdk-apps#2231](https://github.com/turingmotors/cdk-apps/pull/2231) は作った人に確認してから（TODO 18）。
    - datalake で原本バケットに通知（`eventBridgeEnabled`・`addEventNotification`）を足さない（TODO 23）。
- 2026-10-23 のセッションの終わり。引き継ぎ（10-22 の引き継ぎの表より、こちらを正とする）:
  - **レビュー待ちの PR**（どれも main 向け。チームの承認待ち。マージは伊藤）:

    | PR | 中身 | マージ後にやること |
    | --- | --- | --- |
    | [cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253) | ステージ 1: 残りの 11 本 | 4 アプリの deploy の成功、12 本の `get-bucket-policy`（ReadOnly）、1 時間ほど AccessDenied を見る。td1-raw など書き手のいるバケットは、アプリ側のエラーも見る |
    | [cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) | ステージ 2 の 1 本目: カナリアと記録の仕組み | 10-22 の引き継ぎの「[cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) の deploy の後」の 4 点 |

  - **伊藤の作業**: denso-raw の `_policy-check/` の片付け（FullAccess で古い版と削除マーカーを消す）。
  - **待っているもの**: jadd-1023-search（並行のセッション）の結果。1 本目のキーの利用元（Devin の Secrets・Slurm の資格情報）。片付けは TODO 13（切り出した workstream）で。（2026-10-26 注: Devin の線は取り下げた。利用元は TODO 13 と [jadd-studio-amplify-removal.md](done/jadd-studio-amplify-removal.md) を正とする）
  - **作業場所**: worktree はエージェントの一時ディレクトリ（cdk-2253・cdk-2267）。ブランチはすべて push 済みなので、次は `/usr/app/cdk-apps` から作り直せばよい。`/usr/app/cdk-apps` は片付け済み（main は c8698ee2 まで fast-forward、ローカルブランチは PR 中のものだけ。valhalla-turing-api の残骸は控えを取って消した）。
  - **期限があるもの**: TODO 19（azure-data-sync の SAS は 2026-10-26 まで）。
  - **注意**: [cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253) と [cdk-apps#2231](https://github.com/turingmotors/cdk-apps/pull/2231) は denso の workflow の同じ箇所を触る（後からマージする側で行をそろえる）。
- 2026-10-26: 再レビューに出す前に、2 本の PR の最終確認をした。
  - [cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253) が main と競合していた。[cdk-apps#2285](https://github.com/turingmotors/cdk-apps/pull/2285)（certifi の修正）が、denso の workflow 3 本に `packages/azure-data-sync/**` を足していたため。両方の行を残して解き、push した（31ade80f。main との差はファイル 18 本・+152/−14 で、元の PR と同じ）。本文の「[cdk-apps#2231](https://github.com/turingmotors/cdk-apps/pull/2231) と行をそろえる」の注意を、[cdk-apps#2285](https://github.com/turingmotors/cdk-apps/pull/2285) の行と並べた旨に直した。
  - [cdk-apps#2231](https://github.com/turingmotors/cdk-apps/pull/2231) の 3 行は、すべて [cdk-apps#2285](https://github.com/turingmotors/cdk-apps/pull/2285) で main に入った。[cdk-apps#2231](https://github.com/turingmotors/cdk-apps/pull/2231) は閉じてよい状態（TODO 18。閉じるかは伊藤が決める）。
  - [cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253) のテスト: datalake 20 件・gaming-data-collection 7 件・denso-taxi 8 件が通過。denso-nx はテストが無いので、synth して denso-nx-raw に 2 文が付くことを確かめた。devbox には Docker が無いので、`CDK_CONTEXT_JSON='{"aws:cdk:bundling-stacks":[]}'` で Lambda のバンドルを飛ばす必要がある。main との synth の比べ直しはしていない（PR のコードは変わっていない）。
  - [cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) をサブエージェントでレビューした。止めるほどのバグは無し。指摘のうち、Firehose のロールに `s3:DeleteObject*` などが付いていた件（L2 の `grantReadWrite`）を直した（51414353）。`withoutPolicyUpdates()` のロールを渡し、書き込みの 6 操作とログだけを自前のポリシーで付ける。テストを 1 件足した（直す前のコードでは落ちる）。`.nvmrc` が無くて CI の format-diff が落ちたので、main を取り込んだ（5e814a64）。本文の件数と、deploy 後の確認（一括削除がトレイルの範囲に入るか）を直した。
  - 対応を決めること（伊藤）:
    1. ログのバケットを改ざんから守る（古い版は 1 日で消えるので、ふつうの削除の権限で監査ログを消せる）。
    2. DLQ と Firehose の配信失敗のアラーム。
    3. Firehose の出力を改行区切りにするか（`AppendDelimiterToRecord`）。
    4. 一括削除がトレイルの範囲に入るか（deploy 後の確認で見る）。
    5. diff の workflow のコメントの古い記述（「Docker 内の pip install」）。
    6. denso-nx に CDK のテストが無い。
    7. [cdk-apps#2231](https://github.com/turingmotors/cdk-apps/pull/2231) を閉じるか。
  - 作業場所: worktree は scratchpad の cdk-2253・cdk-2267（push 済み）。
- 2026-10-26: [cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253) と [cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) をマージした（マージは伊藤）。
  - **[cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253)**（05:40 UTC）: 4 アプリの deploy はすべて成功した。12 本の `get-bucket-policy`（ReadOnly）で、2 文が雛形どおりに入り、既存の文も残っていることを確かめた。
    - 1 時間（〜06:45 UTC）、CloudTrail の S3 の管理イベントを 15 分おきに見た。**原本バケットへの AccessDenied は 0 件。** 原本バケットへの書き込みは、cfn-exec-role の `PutBucketPolicy` だけだった。
    - ほかの AccessDenied は、どれも原本ではないバケットへの読み取りで、前からあるもの（Databricks のロールの `GetBucketNotification`（wm-data・dev のバケット）、diff のロールなどの assets のバケットの `GetBucketLocation`）。
    - main に入った `package-lock.json` の変更で、ota・tern・feature-cache の deploy も走ったが、すべて成功した。
  - **[cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267)**: マージ前に main（[cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253) の後）と競合していた。`packages/original-bucket-guard/README.md` の利用アプリの一覧で、main の一覧にカナリアの行を足して解いた（42103e07。CI 13 件通過）。PR 本文の守りの表を「12 本すべて済み」に直した。
    - 06:37 UTC にマージした。9 本の deploy（共通部の変更で原本バケットのアプリも再 deploy）はすべて成功し、12 本のポリシーも変わっていない。
    - カナリアの通知に SNS と EventBridge の両方があり、ポリシーは SSL 以外の拒否＋守りの 2 文。
    - 06:48 UTC に伊藤が exerciser を起動した。記録の突き合わせの結果と設計への反映は、[stage2-hourly-report.md](s3-data-protection-2/stage2-hourly-report.md) の「カナリアでの確認の結果」。要点: request-id はつながる。一括削除はオブジェクトごとの記録に `parentRequestID` が付く。古い版の削除は拒否され、CloudTrail にだけ出る。
  - 次にやること:
    - 2026-10-27〜28: カナリアの失効（`expire/`）のイベントを確かめる。`aws s3 ls` でログのバケットの `events/2026/10/27/` 以降を読み、`reason=Lifecycle` の `Object Deleted` を探す。
    - ステージ 2 の 2 本目の PR: トレイルを削除系（`DeleteObject`・`DeleteObjects`）に絞る、毎時の集計（Lambda・Athena）、12 本を足す。
    - 2026-10-26 追記: ステージ 2 は、構想「今日なにしたかわかる君」（[project:what-did-i-do の構想](../../what-did-i-do/documents/notion-what-did-i-do-concept.md)）の**フェーズ 1（今日なに消したかわかる君）**にあたる。段階 3・4 は、構想の 9 章のフェーズ 1 の中身（MLOps チームのチャンネルへの通知、出力を共通の記録の形にそろえる、1b の日次の突き合わせ・本人へのメンション・ログのバケットの Object Lock）に合わせて進める。伊藤が進めるのはフェーズ 1 まで。フェーズ 2 以降はチームへの提案で、着手が決まったら project:what-did-i-do に workstream を作る。
    - レビューで出た課題（10-26 の一覧の 1〜6）の対応を決める。
  - 作業場所: cdk-apps の worktree は scratchpad の cdk-2267b（push 済み）。前の cdk-2253・cdk-2267 はディレクトリが消えている。
- 2026-10-26: tuscenes-prod の CloudTrail の今の設定を ReadOnly で確かめた（全リージョン）。トレイルは 2 本のままで、S3 の削除のデータイベントはまだ記録されていない。`aws-controltower-BaselineCloudTrail`（us-west-2、マルチリージョン、ログは 617808723336 のバケット）は管理イベントだけで `DataResources` は空。`garuda-index-access`（us-west-2 だけ）は `*/index.json` の `GetObject` だけ。CloudTrail Lake のイベントデータストアも無い。`DeleteBucket`・`PutBucketLifecycle` などの管理イベントは記録されている。`DeleteObject`・`DeleteObjects` を記録するトレイル `original-bucket-audit` は [cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) で足す予定で、PR はまだ OPEN（レビュー待ち）。（2026-10-26 注: この記録はマージ前のもの。[cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) は 06:37 UTC にマージされ、トレイル `original-bucket-audit` は deploy 済み。今の対象はカナリアだけ）
- 2026-10-26 のセッションの終わり。引き継ぎ（これより前の引き継ぎより、こちらを正とする）:
  - **今日の結果:** ステージ 1 は 12 本すべてに入った（[cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253)）。ステージ 2 の 1 本目（[cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267)）も入り、カナリアの確認は失効の 1 点を残すだけ。1 時間の見張りで、原本バケットへの AccessDenied は 0 件。
  - **構想:** ステージ 2 は、構想「今日なにしたかわかる君」の**フェーズ 1（今日なに消したかわかる君）**として進める。伊藤が進めるのはフェーズ 1 まで。構想は [project:what-did-i-do の構想](../../what-did-i-do/documents/notion-what-did-i-do-concept.md)（Notion: https://app.notion.com/p/405a93b3e6f28156a7c0fbc3db578957 、下書き）。
  - **フェーズ 1 の計画（案。伊藤の決定待ち）:**
    - 着手の前に:
      - 0-1: カナリアの失効の確認（10-27〜28。ログのバケットの `events/2026/10/27/` 以降で `reason=Lifecycle` の `Object Deleted` を探す。ReadOnly）。
      - 0-2: Slack の通知先のチャンネルと bot を決める（伊藤）。
      - 0-3: bot のトークンを Secrets Manager の `original-bucket-audit/slack-bot-token` に置く（伊藤が Full 権限で。手順書はエージェントが用意）。
    - **PR-A（対象はカナリアのまま）:**
      - 毎時 15 分の集計の Lambda。過去 3 時間を読み直し、単発は request-id、一括は `parentRequestID`＋キーでつなぐ。「誰が」の保留（24 時間で「不明」）。
      - 報告済みの印は DynamoDB（条件付きの書き込み、TTL 30 日）。Slack の投稿は取り消せないため、garuda の「状態を持たない」方式は使わない。
      - 守りの設定の変更は、CloudTrail のイベント履歴（LookupEvents）を操作の名前で毎時引く案。
      - 報告は Slack ＋ ログのバケットの `reports/`（3 年）。出力は構想の共通の記録の形。
      - exerciser を毎日定期起動し、カナリアの削除は通知に出さず「拾えたか」だけを確かめる。拾えなければアラーム。
      - アラームは、失敗・未実行・DLQ・Firehose の配信の失敗・カナリアを拾えない、の 5 種類。通知は Slack（garuda の `alarm_notify.py` と同じ形。Web API を urllib3 で直接、`chat:write`）。
    - **PR-B:**
      - トレイルを `eventName` の `DeleteObject`・`DeleteObjects` に絞る。12 本の一覧を `packages/original-bucket-guard` に置く。
      - 12 本の EventBridge と Inventory を入れる。サイズは、作成のイベント、無ければ Inventory を Athena で引く。
      - 書き込みの少ないバケットから 2 回に分けて入れる。
      - **先に調べること:** datalake が td1-raw の通知を「丸ごと上書き」（`Managed: true`）で持っているため、監査のアプリが足した EventBridge が datalake の deploy で消えるおそれがある（TODO 23）。
    - **1b:** 日次の突き合わせ（Inventory の差分、Athena）、本人へのメンション（`users:read.email`）、ログのバケットの Object Lock（古い版を 1 日で消すライフサイクルとぶつかるので、保存の設計から見直す）。
    - **伊藤に決めてほしいこと:**
      1. Slack の通知先（新しいチャンネルか既存の MLOps のチャンネルか）と bot（新規か使い回しか）。
      2. 守りの設定の変更を、イベント履歴から引く案でよいか。
      3. カナリアの削除を、通知に出さない扱いでよいか。
  - **先例（cdk-apps）:** garuda の `apps/garuda/lib/constructs/index-access-aggregator.ts`（定期実行・読み直し・アラーム 3 種）と `apps/garuda/functions/index-access-aggregator/alarm_notify.py`（Slack への投稿）。Slack の bot のトークンは、アプリごとに Secrets Manager の `<アプリ>/slack-bot-token` に置く形が多い。cdk-apps に Athena の先例は無い。
  - **Notion の運用:** personal-workspace のセッションにだけ Notion の MCP がある。書き込みは毎回確認が出る（`AGENTS.md` の「Notion」）。上げ直しが溜まっているもの: permission-upgrade-plan.md、バケットの種別の記事（どちらも既存の Notion のページの URL が要る）。
  - **期限があるもの:** TODO 19（azure-data-sync の SAS は 2026-10-26 まで）は、今日も確かめられなかった。次のセッションの最初に、ローテーションと DataSync の成功を ReadOnly で確かめる。
  - **作業場所:** cdk-apps の worktree は scratchpad の cdk-2267b（push 済みで、作業は残っていない）。次は `/usr/app/cdk-apps` から作り直せばよい。
- 2026-10-27（01:05 UTC）: カナリアの失効（0-1）を ReadOnly で見た。**まだ起きていない。仕様どおり。**
  - ログのバケットの `events/` は、10-26 06:48 の exerciser の 1 ファイルだけ。
  - `expire/20261026T064825Z.txt` は、今の版と古い版が 1 つずつ残っている（どちらも 10-26 06:48:27 UTC）。ライフサイクル `canary-expire` は `Expiration.Days=1` と `NoncurrentDays=1`。
  - S3 のライフサイクルは「作成から N 日後の、次の 0 時（UTC）」から対象になる。なので、失効の対象になるのは **10-28 00:00 UTC（09:00 JST）以降**。そこから実行まで最大 1 日ほど遅れることがある。
  - 次は **10-28 の午後（JST）以降**に見る。期待するのは 2 件。今の版の失効（削除マーカーができる）と、古い版の完全な削除。どちらも `Object Deleted` で、`reason` がライフサイクル由来のもの。10-29 になっても出なければ、ルールか EventBridge の経路を疑う。
- 2026-10-27: TODO 19（azure-data-sync の SAS）を ReadOnly で確かめた。**済み。期限の前に自動で差し替わり、その後の転送も成功している。**
  - rotator（`DensoNx-AzureDataSyncSasRotatorRotatorFn…`）が、2026-10-25 12:00 UTC（21:00 JST）にスケジュールで起動した。新しい SAS（有効期限 2026-11-01 11:55 UTC）を `azure-data-sync/mlops1/sas-token` に書いた。シークレットの `LastChangedDate` も同じ時刻。
  - その後の `azure-mlops1-dcorp-inbound-daily` は、10-26 03:00 JST・10-27 03:00 JST とも `SUCCESS`。`SasRotationFailureAlarm`・`LongRunningAlarm` も OK のまま。
  - ローテーションの仕組み: スケジュールは `cron(0 12 */6 * ? *)`（毎月 1・7・13・19・25・31 日の 12:00 UTC）、SAS の寿命は 7 日。間隔は最大 6 日なので、期限まで 1 日以上の余裕がある。今後も手で見る必要は無い。
  - 転送したファイルは 0 件のまま（送り元が 10-17 から 0 件。TODO 17）。分かったのは、認証が通っていることまで。
- 2026-10-27: [cdk-apps#2231](https://github.com/turingmotors/cdk-apps/pull/2231) を閉じた（TODO 18。10-26 の課題の 7）。差分の 3 行が、どれも main（[cdk-apps#2285](https://github.com/turingmotors/cdk-apps/pull/2285)）にあることを確かめた。閉じた理由は PR にコメントで残した。
- 2026-10-27: フェーズ 1 の計画の「伊藤に決めてほしいこと」のうち 2 点が決まった（伊藤）。
  - 1（Slack）: **bot もチャンネルも新しく作る。**
  - 3（カナリアの削除）: **今回は通知に出さない。** 将来は、AWS のリソースの変更を見張る仕組みで拾う。
  - 2（守りの設定の変更をイベント履歴から引く案）は、まだ決まっていない。
- 2026-10-27: TODO 23 を調べた（cdk-apps の main は 7e64e5ce、aws-cdk-lib は 2.173.2。AWS は ReadOnly）。
  - **td1-raw の通知の持ち方**: datalake の `RlogDecoder`（`apps/datalake/lib/rlog-decoder/index.ts:40`、2025-03 の [cdk-apps#111](https://github.com/turingmotors/cdk-apps/pull/111)）が、`new s3.Bucket` の td1-raw に `enableEventBridgeNotification()` を呼んでいる。そのため、テンプレートに `Custom::S3BucketNotifications`（`RawBucketNotificationsAC3090B1`、`Managed: true`、設定は `EventBridgeConfiguration` だけ）がある。
  - **ハンドラーの動き**（`custom-resource-handlers/dist/aws-s3/notifications-resource-handler/index.py`）:
    - `Managed: true` では、Create・Update のたびに、CDK が持つ設定で丸ごと置き換える（`handle_managed`）。Delete のときは空にする（`{}`）。
    - `Managed: false`（`fromBucketName`）では、今ある設定を読んで、外部の通知と EventBridge を残したまま足す（`handle_unmanaged`）。Delete のときも、EventBridge は外部の設定として残す。
  - **いまの td1-raw の通知**: EventBridge と、Databricks の auto-ingest の SNS が 2 本（`collect/`・`control/`）。SNS が残っているのは、このリソースの Update が 2025-10-27 01:39 UTC を最後に走っていないから。ステージ 1 の deploy（10-23・10-26）でも走っていない（バケットポリシーの変更では走らない）。
  - **前からある危険（監査とは関係ない）**: 次のどれかで Update か Delete が走ると、Databricks の SNS 2 本が消え、auto-ingest が止まる。
    - datalake で td1-raw に通知を足す・変える。
    - aws-cdk-lib を上げたときに、このリソースのプロパティが増える（2025-10-27 の Update の原因は確かめていない）。
    - rlog-decoder の `enableEventBridgeNotification()` を外す（Delete で空になり、EventBridge まで消えて rlog のデコードも止まる）。
    - 直すなら、2 段階に分ける案がある。①このリソースに `DeletionPolicy: Retain` を付ける。②`fromBucketName` の側（`Managed: false`）に付け替える。①だけで Update が走らないかは、カナリアで確かめてから入れる。直すかどうか・誰が直すかは未定。
  - **監査のアプリ（PR-B）と td1-raw はぶつからない**: td1-raw の EventBridge はすでに有効で、datalake が持つ設定にも EventBridge が入っている。datalake が丸ごと置き換えても EventBridge は残る。監査のアプリは `fromBucketName` で足すので、Create のときも外部の通知を残す。
  - **ほかの 11 本**: CDK が通知を持っているのは tuscenes-model だけ。L1 の `EventBridgeEnabled: true` で、ほかの通知は無いので、ぶつからない。残りの 10 本は CDK が通知を持っていない。Databricks の SNS（auto-ingest か `csms-topic-by-path`）が付いているのは tuscenes-raw・tuscenes-annotation・gaming-data-collection・denso-taxi-processed・denso-nx-raw。`Managed: false` で足せば残る。
  - **新しく見つかった問題（tuscenes-raw）**: default のバスに `tuscenes-NewTripEventRule9F52899F-dXQQ5emHVD08`（ENABLED）がある。中身は、`tuscenes-raw-*` の `*/*/*/*/*/metadata.json` の作成・削除で、`tuscenes-NewTripEvent-Handler` を呼ぶもの。
    - この Lambda の環境変数には `CLEANING_JOB_FUNCTION_NAME`・`TRIP_VALIDATION_FUNCTION_NAME`・`SUPABASE_SECRET_ARN`・`TOPIC_ARN` がある。最終更新は 2025-04-09 で、直近 90 日の呼び出しは 0 件。
    - スタック `tuscenes` は cdk-apps の外にあり、最終更新は 2025-05-23（tuscenes-pipeline のものとみられる）。
    - いまは tuscenes-raw の EventBridge が無効なので、発火しない。datalake の `eventBridgeEnabled: false, // cleaning 処理に必要` は、これを止めておくためのものとみられる（2025-04 の [cdk-apps#169](https://github.com/turingmotors/cdk-apps/pull/169) で tuscenes-pipeline から移したもの）。
    - **PR-B で tuscenes-raw に EventBridge を入れると、metadata.json の作成・削除で cleaning などが動き出す。** 案は次の 2 つ。(a) tuscenes-raw は EventBridge を入れず、CloudTrail のデータイベントと Inventory だけで報告する。(b) 持ち主に確かめて、このルールを止めるか消してから入れる。伊藤の判断待ち。
- 2026-10-27: tuscenes-raw の沿革を調べた（伊藤の依頼。cdk-apps と、アーカイブ済みの turingmotors/tuscenes-pipeline・tuscenes-infra の git の履歴、AWS は ReadOnly）。**CDK を整える前からあったバケットではない。** 作ったのは tuscenes-pipeline の CDK（Python）で、2025-04 に cdk-apps に移ってきた。
  - 2024-02-02: tuscenes-infra（CDK、TypeScript）が前身を作った。`alphaspp-raw`・`alphaspp-data`・`alphaspp-ingest` と、Glue の cleaning の job。スタック `alphaspp-pipeline` はもう無いが、バケットは残っている。`alphaspp-raw-767397804933` は 42 オブジェクト・約 0.9 TB で、`ad01/`〜`ad03/`・`alphaspp01/`・`1.0/2024/04/` がある。第一弾の分類では S10（「不明」「行わない」）にしていた。出所はこれで分かった（TODO 22 の調べ残しの一部）。
  - 2024-03-12: tuscenes-pipeline（CDK、Python）が `RawDataBucket` を `{STACK_NAME}-raw-{account}` の名前で足した。スタック `tuscenes` の作成は 2024-03-11 なので、名前は `tuscenes-raw-767397804933` になる。2024-06-27 の [tuscenes-pipeline#3](https://github.com/turingmotors/tuscenes-pipeline/pull/3) で、同じ名前を明示する書き方に変わった。
  - 2024-05-17: `1.0/` のいちばん古いデータ（`1.0/2024/05/17/`）。
  - tuscenes-pipeline の時代は `event_bridge_enabled=True` だった。`NewTripEvent` が `metadata.json` の作成・削除を受けて、検証（`trip_validation`）と cleaning の job（`create_cleaning_job`。出力は tuscenes-cleaned）を起動し、Supabase と SNS に書いていた。
  - 2025-04-08: [tuscenes-pipeline#27](https://github.com/turingmotors/tuscenes-pipeline/pull/27)（「cdk-apps にリソース移管します」）で、`s3.Bucket` から `from_bucket_name` に変わった。同じ日の cdk-apps の [cdk-apps#169](https://github.com/turingmotors/cdk-apps/pull/169) で、datalake に `new s3.Bucket(TuscenesRawBucket)` として移った。このとき `eventBridgeEnabled: false, // cleaning 処理に必要` になった。コミットの箇条書きには「cleaning 処理を停止」とある。**コメントの意味は「cleaning を止めるために必要」**と読める。収集も 2025-04 に終わっている。
  - 2025-05-23: tuscenes-pipeline の最後の変更（「tuscenes studio を削除」、[tuscenes-pipeline#30](https://github.com/turingmotors/tuscenes-pipeline/pull/30)）。リポジトリはアーカイブ済み。それでもスタック `tuscenes` は残っていて、`NewTripEventRule`（ENABLED）と Lambda も生きている。tuscenes-raw の EventBridge が無効なので、発火していないだけ。
  - 第二弾への影響: 先に出した案 (a)・(b) の前提は変わらない。(b) の「持ち主」は、アーカイブ済みのリポジトリが残したスタックになる。ルールを止めるのは、残骸の片付けにあたる。
- 2026-10-27: tuscenes-raw の扱いを決めた（伊藤）。
  - **(b) にする。** 本件の障害になるルール `tuscenes-NewTripEventRule…` を、伊藤が自分の手で止める（TODO 25）。そのうえで、PR-B で 12 本すべてに同じ形で EventBridge を入れる。
  - 比べた案: (a) tuscenes-raw だけ EventBridge を入れず、CloudTrail だけで報告する。ライフサイクルで消えた分と一括削除の種類が見えず、1 本だけ別の処理が残るので採らなかった。
  - カナリアの記録で確かめたこと（(a) を比べるため）: CloudTrail では、単発の `DeleteObject` の応答に `x-amz-delete-marker` と `x-amz-version-id` が載る。一括削除のオブジェクトごとの記録には、`resources` のキーしか載らない（版も種類も無い）。ライフサイクルの削除は CloudTrail に出ない。
  - **スタック `tuscenes` 全体の片付けは、別の資料に起票した: [tuscenes-stack-cleanup.md](tuscenes-stack-cleanup.md)**（積んでいる。そのうちやる）。ルール 3 本・Lambda 7 本・IAM ユーザー `tuscenes-basicai-user`・バケット 5 本などの中身と注意点は、そちらにまとめた。
- 2026-10-27: 伊藤が `tuscenes-NewTripEventRule9F52899F-dXQQ5emHVD08` を止めた（TODO 25）。ReadOnly で `DISABLED` を確かめた。ほかのルール（tuscenes の NewSceneEvent・CleaningJobStateChange、rlog-decoder、監査のアプリ）は ENABLED のまま。これで PR-B で tuscenes-raw にも EventBridge を入れられる。
- 2026-10-27 のセッションの終わり。引き継ぎ（これより前の引き継ぎより、こちらを正とする）:
  - **今日の結果:**
    - TODO 19（SAS）は済み。期限の前に自動で差し替わり、転送も成功していた。今後は手で見なくてよい。
    - TODO 18 は済み。[cdk-apps#2231](https://github.com/turingmotors/cdk-apps/pull/2231) を閉じた。
    - TODO 23 を調べた。監査のアプリと td1-raw はぶつからない。td1-raw の通知の持ち方には、前からある危険がある。
    - tuscenes-raw は (b) に決め、古いルールを止めた（TODO 25）。スタック `tuscenes` の片付けは [tuscenes-stack-cleanup.md](tuscenes-stack-cleanup.md) に起票した（積んでいる）。
    - カナリアの失効は、まだ起きていない（仕様どおり）。
  - **フェーズ 1 の計画の決定の状況:** 1（Slack）は、bot もチャンネルも新しく作る。3（カナリアの削除）は、通知に出さない。2（守りの設定の変更をイベント履歴から引く案）は未定。
  - **次にやること（10-28）:**
    1. **Slack の bot の準備**（伊藤と一緒に）。手順は計画の 0-2・0-3。
       - 新しいチャンネルと bot（Slack アプリ）を作る。権限は `chat:write`。1b で本人へのメンションをするなら `users:read.email` も。
       - bot のトークンを Secrets Manager の `original-bucket-audit/slack-bot-token` に置く（伊藤が Full 権限で。手順書はエージェントが用意する）。
       - 先例は garuda の `alarm_notify.py`（Web API を urllib3 で直接呼ぶ）。
    2. カナリアの失効の確認（10-28 の午後 JST 以降。ReadOnly）。ログのバケットの `events/2026/10/28/` 以降で、`expire/20261026T064825Z.txt` の `Object Deleted` を 2 件（削除マーカーの作成と、古い版の完全な削除）探す。`reason` がライフサイクル由来であること。10-29 になっても出なければ、ルールか経路を疑う。
    3. そのあと PR-A に着手する。
  - **決まっていないこと:**
    - ~~守りの設定の変更を、CloudTrail のイベント履歴から引く案でよいか。~~ → EventBridge で受ける方式に決めた（2026-10-29）。
    - td1-raw の通知の持ち方（TODO 23。`Managed: true` の丸ごと上書き）を直すか、誰が直すか。
    - [cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) のレビューで出た課題の 1〜6。
    - [cdk-apps#1967](https://github.com/turingmotors/cdk-apps/pull/1967)（graph226 さん、denso-nx の DataSync を 10 本に分ける。9-18 からレビュー待ち）を TODO に足すか。マージされると denso-nx-raw に書き込む DataSync が増え、PR-B の主体の一覧に効く。
  - **PR-B に向けたメモ:** tuscenes-raw の古いルールは止めた。datalake の `eventBridgeEnabled: false, // cleaning 処理に必要` のコメントを直すこと。td1-raw・tuscenes-model は、EventBridge がすでに有効。
  - **作業場所:** cdk-apps は触っていない（読んだだけ）。scratchpad に、tuscenes-pipeline・tuscenes-infra の clone と、カナリアのログの写しがある（使い捨て）。
  - **環境のメモ:** `jbcontext` の CLI はこの devbox に無い。MCP の検索ツールは personal-workspace の索引しか無く、cdk-apps は検索できない。
- 2026-10-29: フェーズ 1 の計画の「伊藤に決めてほしいこと」の 2（守りの設定の変更の拾い方）が決まった（伊藤）。**イベント履歴（LookupEvents）は使わず、EventBridge で受ける。**
  - 方式: default のバスに流れる CloudTrail の管理イベント（`detail-type: AWS API Call via CloudTrail`）を、操作の名前（`PutBucketPolicy`・`DeleteBucketPolicy`・`PutBucketVersioning`・`PutBucketLifecycleConfiguration`・`DeleteBucketLifecycle`・`DeleteBucket` など）と対象のバケットで絞るルールで受け、今の Firehose に流す。毎時の集計は、削除と同じく `events/` を読む。
  - LookupEvents を採らなかった理由: 遅れて届いたイベントを取りこぼしても気づけない。絞り込みの条件が 1 つしか使えない。呼び出しの上限（毎秒 2 回）をアカウント内のほかの利用と共有している。元のイベントが 90 日で消え、削除の記録とは別の経路になる。LookupEvents は、日次の突き合わせ（1b）で漏れを拾う予備の手段として使う余地を残す。
  - ReadOnly で確かめたこと:
    - 12 本とカナリアは、すべて us-west-2。ルールは us-west-2 の 1 か所で足りる。
    - 管理イベントを記録するトレイルは、Control Tower の組織のトレイル `aws-controltower-BaselineCloudTrail`（管理アカウント 617808723336 が持つ、マルチリージョン）だけ。tuscenes-prod の中のトレイル（`garuda-index-access`・`original-bucket-audit`）は、どちらもデータイベントだけ。
    - **確かめられなかったこと:** 管理イベントが tuscenes-prod の default のバスに実際に流れているか。us-west-2 のルール 56 本の中に `AWS API Call via CloudTrail` を受けるものが無く、過去の流れを見る手段が無い。組織のトレイルの状態（`GetTrailStatus`）も、ReadOnly では管理アカウントのものなので見られない。
    - そのため、PR-A でルールを入れたら、カナリアのポリシーなどを変えて、`events/` に届くかを最初に確かめる。届かなければ、tuscenes-prod に管理イベントだけのトレイルを足す（組織のトレイルが 1 本目にあたるので、2 本目の写しとして 10 万件あたり $2 かかる。書き込み系だけに絞れば少額）。
- 2026-10-29: BreakGlass の議論を始めた（伊藤の関心は、大きな企業の組織と人のレイヤーの設計と、BreakGlass の人に課される要件）。資料を 2 本書いた。
  - 一般論（学習用）: [特権アクセスと break-glass の一般論](../documents/privileged-access-and-break-glass.md)。出典はサブエージェントが原典で確かめた（ISO は二次資料だけ、FISC は未確認）。
  - 当社への当てはめ（叩き台）: [breakglass-design-draft.md](s3-data-protection-2/breakglass-design-draft.md)。6 章の「決めてほしいこと」が伊藤の判断待ち。
  - 分かったこと:
    - 今の設計の「BreakGlass」は、昇格用の権限セットで、本来の意味の break-glass（Okta が止まったときの入口）ではない。名前の扱いは論点 A。
    - 管理アカウントからの `sts:AssumeRoot` は、S3・SQS の全拒否のポリシーの削除と root の認証情報の管理しかできない。緊急用の入口にはならない（ステージ 1 の戻し道にはなる）。
    - BreakGlass の利用の通知は、保留にした Slack の bot と、管理イベントを EventBridge で受ける仕組みに頼る。使い始める前に、この 2 つだけ先に作る必要がある。
    - Okta の認証ポリシーは identity の Terraform に無く、今の設定は確かめていない。
- 2026-10-29: BreakGlass の方針と、チーム向けの資料の構成を決めた（伊藤）。
  - **方針:** MLOps チームは日常的に AWS を変更するので、ふだんの権限は今の FullAccess のまま変えない。昇格するのは BreakGlass（原本バケットの古い版の削除と、守りを外す操作）のときだけにする。ステージ 3 の「普段用の権限セット」は、大きく縮められる。
  - そのため、CDK の deploy のロールを経由する抜け道を塞ぐ TODO 24（SCP）の重みが上がった。
  - 昇格のときの MFA は、OTP ではなくフィッシングに強い要素を推した（まれにしか使わないので手間は増えない）。
  - **チーム向けの資料:** [breakglass-proposal.md](s3-data-protection-2/breakglass-proposal.md)（下書き）。対象は MLOps チームと CorpIT チーム（Okta など会社全体のサービスの管理者）。構成は、目次 → BreakGlass 権限とは（設計の考え方・守る側で止める・使ってよい場面とルール・BreakGlass 権限でないもの）→ 今の FullAccess → ギャップ → 移行の手順（担当つき）→ 残るリスク → 決めてほしいこと・お願いしたいこと（チームごと）。呼び名は「BreakGlass 権限」にし、権限であることを明記する。設計の考え方は「許可を待たずに使える」と「使ったことが必ず分かる」の 2 つの性質を軸にする（伊藤のレビュー）。
  - 叩き台（[breakglass-design-draft.md](s3-data-protection-2/breakglass-design-draft.md)）は、内部の検討の記録として残す。
  - 次: 伊藤が提案の下書きをレビューする。そのあと Notion に上げるか決める。
- 2026-10-29: FullAccess の扱いを決めた（伊藤）。**案 A: FullAccess から BreakGlass 権限にあたる操作を削る。** 権限セット自体は書き換えず、原本バケットのバケットポリシーの例外から外すことと、SCP で CDK の deploy のロールを CI 以外から名乗れなくすること（TODO 24）で実現する。
  - 案 B（新しく権限を設計し、FullAccess を廃止する）を採らなかった理由: FullAccess は複数のアカウントで使われ、EKS（closed-loop-scenario-test）・coder・skypilot がロール名 `AWSReservedSSO_FullAccess_…` を直接参照しているため、影響が大きい。名前と中身の食い違いは今もある（インラインの Deny で td1-raw・tuscenes-raw の削除を拒否している）。名前の見直しは、組織全体の権限設計で別に考える。
  - 提案の資料は、ギャップの表を外し、「FullAccess はどう変わるか」（今の FullAccess・削るもの・変わらないもの）にまとめた。案 B を採らなかった理由は末尾の補足に書いた。
- 2026-10-29: tuscenes-prod の FullAccess を持つ人を、リポジトリから数えた（cdk-apps の main 9a5bbd22、identity の main db8f027）。**13 名。** 割り当て先は Okta から同期するグループ 2 つ（`ORG:Autonomous Driving Group 3 Regular Employees` 6 名＝Infrastructure Team と担当役員、`ORG:Autonomous Driving Group 4 Regular Employees` 8 名＝MLOps 1・3 Team と担当役員）で、1 名が両方に入っている。プランの「14 名」は、この重複を数えたものとみられる。
  - 管理画面で直接した割り当ては、リポジトリからは見えない。AWS で確かめるには管理アカウントの権限が要る（`default` プロファイルは tuscenes-prod の ReadOnly だった）。
  - Fable のレビュー（高 3・中 9・低 9）を提案に反映した。BreakGlass 権限の中身は AdministratorAccess を仮採用し、S3 に絞る対案を補足 2 に書いた（伊藤）。
  - BreakGlass 権限を使うときの MFA を検討中。今の構成（Okta → IAM Identity Center）では、権限セットを切り替える瞬間に MFA を求められない。案 2（BreakGlass 権限の専用の Okta ユーザー）＋スマートフォンのパスキーを推した。伊藤の判断待ち。
- 2026-10-29: BreakGlass 権限の MFA の案を、Fable にセカンドオピニオンとして見てもらった。**案 3（BreakGlass 専用の Okta アプリから、tuscenes-prod の IAM ロールに直接 SAML で入る）を推す点で一致。** 推奨順は 案 3 ＞ 案 1'（下記）＞ 案 1 ＞ 案 2 ＞ assume role 案。伊藤の判断待ち。
  - 事実の確認（公式ドキュメント）: IAM Identity Center は外部 IdP のとき MFA を持たず、権限セットの選択時に MFA を求める手段は無い。フェデレーションのセッションには `aws:MultiFactorAuthPresent` が無い。Okta の認証ポリシーはアプリごとに付き、グループ別に「毎回」「フィッシングに強い要素（パスキー・FastPass）」を設定できる。同期されるパスキーもフィッシングに強い要素として扱われる（Okta の「Block synced passkeys」の今の値は要確認）。
  - 案 3 に足すこと: 信頼ポリシーで `saml:sub` を 2〜3 名に固定する（Okta の管理者が自分を割り当てるだけでは入れない）。SCP でロールと SAML プロバイダーの変更（`UpdateAssumeRolePolicy`・`UpdateSAMLProvider` など）を deploy の経路以外から拒否する。Okta の公式の AWS アプリは IAM ユーザーのキーが要るので、汎用の SAML アプリにする。CLI は最初は対象外にし、コンソールと CloudShell で使う。
  - 通知の落とし穴: `AssumeRoleWithSAML` は CloudTrail で `readOnly: true`。EventBridge のルールは `ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS` で作る必要がある。記録されるリージョンは、実際のイベントで確かめる。
  - 案 1'（途中段階）: IAM Identity Center のアプリの Okta の認証ポリシーに BreakGlass のグループ用のルール（毎回・フィッシングに強い要素）を足し、AWS アクセスポータルのセッションを短くする。新しい AWS のリソースは要らない。
  - 注意: 想定する脅威の一番上は誤操作で、それを止めるのはバケットポリシー。MFA の議論で例外の差し替え（手順 7）を止めない。
- 2026-10-29: **BreakGlass 権限の入り方は案 3 に決めた（伊藤）。** BreakGlass 専用の Okta アプリ（汎用の SAML、入るたびにフィッシングに強い要素）から、tuscenes-prod の IAM ロール `BreakGlass` に直接入る。つなぎの案 1' は入れない。
  - 提案の資料に「4. BreakGlass 権限の入り方と MFA の実装」を足した（Okta の設定、MFA の要素〈パスキーを推す・物理キーを予備〉、AWS の設定〈`saml:aud`・`saml:sub` で 2〜3 名に固定〉、SCP での守り、通知〈`ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS`〉、使うときの流れ〈CLI は対象外、CloudShell〉、確かめること）。移行の手順は 11 段になった。対案の案 1・案 2（と assume role）は補足 3 に書いた。
  - 叩き台（breakglass-design-draft.md）は、権限セットの案のままで古い。記録として残す。
- 2026-10-29: BreakGlass 権限の提案を**第一版**として Notion に上げた（https://app.notion.com/p/408a93b3e6f281b38292d14cbbed304c 、ドキュメント置き場、Status は下書き）。手元の原本の冒頭に URL を書いた。直すときは、先に手元の原本を直してから Notion を更新する。
  - Notion 版では、プラン（permission-upgrade-plan.md）への相対リンクを題名だけにした。プランの Notion の URL は手元に記録が無い。
- 2026-10-29 のセッションの終わり。引き継ぎ（これより前の引き継ぎより、こちらを正とする）:
  - **今日の結果:**
    - 優先度を組み替えた。BreakGlass の議論と設計、原本バケットの WORM 化の検討（TODO 26）を先にやる。ステージ 2 の監視（PR-A 以降）は保留。守りの設定の変更は EventBridge で受けると決めた。
    - BreakGlass 権限の提案を書き、第一版を Notion に上げた（[breakglass-proposal.md](s3-data-protection-2/breakglass-proposal.md)、https://app.notion.com/p/408a93b3e6f281b38292d14cbbed304c ）。決めたこと: FullAccess は変えずに削る（案 A）、BreakGlass 権限の中身は AdministratorAccess（仮）、入り方は専用の Okta アプリから IAM ロール `BreakGlass` に直接 SAML（案 3）、MFA はスマートフォンのパスキー。
    - 一般論の学習用の資料を書いた（[privileged-access-and-break-glass.md](../documents/privileged-access-and-break-glass.md)）。
    - tuscenes-prod の FullAccess は 13 名（リポジトリから数えた）。
  - **次にやること:**
    1. 伊藤がチームで提案を議論する。Notion のコメントや編集を読んで、手元の原本に取り込んでから Notion を更新する。
    2. 議論の結果を待つあいだにできること: WORM 化の検討（TODO 26。[S3 Object Lock の整理](../documents/notion-s3-object-lock.md) が起点）、TODO 24（SCP。提案の 2.2 の ②・③ と重なる）の仕様の調査。
  - **決まっていないこと:** 提案の移行の手順 1（BreakGlass 権限を持つ人、Slack のチャンネル、通知を確かめる人）と、4.7 の確かめること（CorpIT への確認が主）。プランの Notion の URL（提案の Notion 版で、リンクにできていない）。
  - **注意:**
    - 叩き台（breakglass-design-draft.md）は権限セットの案のままで古い。記録として残している。
    - 共有済みのプランの「FullAccess 14 名」は、重複を数えたもの。正しくは 13 名。プランを上げ直すときに直す。
    - `default` の AWS プロファイルは tuscenes-prod の ReadOnly で、管理アカウントの権限ではない。

