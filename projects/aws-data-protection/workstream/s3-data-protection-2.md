# S3 バケットのデータ保護 第二弾（権限設計のアップグレード）

- 開始: 2026-10-20
- 状態: **ステージ 1 の残りの 11 本とステージ 2 の 1 本目を、再レビューに出す前の最終確認まで済ませた**（2026-10-26）。[cdk-apps#2252](https://github.com/turingmotors/cdk-apps/pull/2252)（共通部と denso-raw）は 2026-10-23 にマージし、denso-raw に入れた。[cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253)（残りの 11 本）・[cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267)（ステージ 2 のカナリアと記録の仕組み）は、2026-10-26 に main を取り込み、[cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) には Firehose のロールの修正を足した。チームの承認待ち。レビューで見つかった問題の対応は伊藤が決める（「進捗と引き継ぎ」の 10-26）
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
7. **残りの 11 本に入れる**（[cdk-apps#2253](https://github.com/turingmotors/cdk-apps/pull/2253)。今は main 向け。チームの承認待ち）。
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
      - **別の資料に切り出した: [jadd_studio_amplify を削除する](jadd-studio-amplify-removal.md)**（2026-10-23）。利用元の調査の結果・削除の手順・Amplify の一式の扱いはそちらが正本。
      - 要点: キーは 2 本とも 2026-10-23 に無効化した（伊藤）。利用元の最有力は、jadd_studio3 の開発者の手元の `.env.local`（3 月に配った秘密情報のパッケージにこのキーが入っていた）。Devin の線は取り下げた。削除を妨げる依存は無い。
      - PR には、キーが漏れていることを書かない（「ステージ 4 で片付ける」とだけ書いた）。
14. **使われていない強いロールを消す**。ecsTaskExecutionRole、AmazonEMRStudio_RuntimeRole、CodeCatalyst、tuscenes-sampler-test、sfn-auto-labeling、tuscenes-processing（どれも最終利用は 1 年以上前）。cdk の us-east-2 の bootstrap は使う予定を確かめてから。
15. **SSO の JADDViewer を見直す**。名前は閲覧用だが、`DataScientist` で 12 本の削除・上書きができる。

### 第一弾からの持ち越し（作った人に確認する。後回し）

16. **LidarDeleter・S3BatchDeleteLidar**：周知するか、信頼ポリシーを外すか。ステージ 1 が入れば古い版は消せなくなるが、間引きを再開すると古い版が残り、課金が続く。間引きはライフサイクルで行う形に改める（原則 2）。
17. **denso-nx-raw の Azure 側の件数の減少**：10-14 までの 187,810 件が、10-17 以降は 0 件。調査書の G01 の前提が崩れている可能性がある。
18. **[cdk-apps#2231](https://github.com/turingmotors/cdk-apps/pull/2231)**（azure-data-sync の変更で denso の deploy・diff を走らせる）：作った人に確認してから進める。それまでレビュー依頼・マージはしない。
19. **azure-data-sync の SAS の次のローテーション**：今の SAS は 2026-10-26 まで有効。その前の自動のローテーションと、次の日の DataSync の成功を確かめる。

### 第一弾からの持ち越し（チームの合意待ち）

20. **バケットの種別の記事を Notion に上げ直す**（[`done/raw-data-security/notion-bucket-classification.md`](done/raw-data-security/notion-bucket-classification.md)。10-19 の変更を反映済み。2026-10-26 に、tuscenes-calibration（新）の失効の記述と denso-nx-raw の件数の記述も手元の写しで直した）。
21. **databricks-workspace-e2e-bucket の A 案**（バージョニングを入れない）をチームで議論する。S3 を直接消されることへの手当ては、ステージ 1 と同じバケットポリシーで考えられる（Databricks のロール以外の削除を拒否する）。
22. **調べ残し**：手で作ったバケットの持ち主と出所、tuscenes-calibration（旧）の写しの有無、他アカウント（amman-pipeline・e2e-dev・biz-dev）の同じ集計。
23. **datalake の td1-raw の通知の設定**: datalake は td1-raw の通知を CDK の「丸ごと上書き」の方式（`Managed: true`）で持っている。datalake の通知の設定を変えて deploy すると、Databricks の auto-ingest の通知が消えるおそれがある（2026-10-22 に気づいた。ステージ 2 の設計を参照）。

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
  - **待っているもの**: jadd-1023-search（並行のセッション）の結果。1 本目のキーの利用元（Devin の Secrets・Slurm の資格情報）。片付けは TODO 13（切り出した workstream）で。（2026-10-26 注: Devin の線は取り下げた。利用元は TODO 13 と [jadd-studio-amplify-removal.md](jadd-studio-amplify-removal.md) を正とする）
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
- 2026-10-26: tuscenes-prod の CloudTrail の今の設定を ReadOnly で確かめた（全リージョン）。トレイルは 2 本のままで、S3 の削除のデータイベントはまだ記録されていない。`aws-controltower-BaselineCloudTrail`（us-west-2、マルチリージョン、ログは 617808723336 のバケット）は管理イベントだけで `DataResources` は空。`garuda-index-access`（us-west-2 だけ）は `*/index.json` の `GetObject` だけ。CloudTrail Lake のイベントデータストアも無い。`DeleteBucket`・`PutBucketLifecycle` などの管理イベントは記録されている。`DeleteObject`・`DeleteObjects` を記録するトレイル `original-bucket-audit` は [cdk-apps#2267](https://github.com/turingmotors/cdk-apps/pull/2267) で足す予定で、PR はまだ OPEN（レビュー待ち）。
