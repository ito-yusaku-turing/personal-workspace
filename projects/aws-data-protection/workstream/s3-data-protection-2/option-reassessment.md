# BreakGlass と WORM の再評価

- 作成: 2026-10-30 ／ 伊藤（下書きはエージェント）
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)
- 前提: [requirements.md](requirements.md) の要件 1〜14（2026-10-30 に問い a〜h に答えたもの）、[current-state.md](current-state.md) の弱点 W1〜W16
- 状態: **1・2・4 は回答済み（6 章）。3 は調べ終えた（7 章）**
- 対象: [BreakGlass の提案](breakglass-proposal.md)（第一版、2026-10-29）と [WORM 化の設計](worm-design.md)（大枠、2026-10-30）

2 つとも、要件を固める前に設計したもの。固まった要件に照らして、要るか・役に立つかを見直す。

## 1. 要点

- **BreakGlass（昇格用の権限）は、要件からは必要性が下がった。**
  - 設計の軸の「許可を待たずに使える」が、要件 12（2 人目の確認）とぶつかる。
  - 乗っ取りへの守りとしては、WORM のほうが強い。
  - 「判断の記録＋2 人目の確認＋即時の通知」は、人に強い権限を持たせなくても、cdk-apps の PR を唯一の経路にすれば満たせる見込み（3.3）。
  - 本来の意味の break-glass（ふだんの経路が使えないときの入口）は、管理アカウントからポリシーを外す道がすでにある（3.4）。
- **WORM は、要件からは有用性が上がった。**
  - b で乗っ取りを含めたので、「同じアカウントの中の誰にも外せない層」が要る。WORM はそれを直接満たす。
  - c でアカウントの閉鎖を範囲の外にしたので、WORM が守れない残りはほぼ無い。
  - 解除の後の 30 日は「遅らせる」役割を担い、即時の通知（要件 10）と組み合わさる。
  - 前提は 2 つ。試しで、コンプライアンスでもホールドを解除できること（Q4）。解除の経路を BreakGlass 以外に置き直すこと（4.4）。
- **組み合わせの見立て:** WORM（外せない層・遅らせる）＋即時の通知（気づく）＋cdk-apps の PR の経路（判断・2 人目）＋SCP（deploy の経路を守る補助）。人の例外はバケットポリシーから外す。

## 2. 見直しの基準

効く要件だけを挙げる。

| 要件 | 中身 | 何を求めるか |
|---|---|---|
| 6 | 存続＋完全性 | 消えないこと、元の版が残ること |
| 7 | 誤操作＋乗っ取られた主体 | 1 つの主体を乗っ取られても、取り返しのつかない操作が通らないこと |
| 9・10 | 取り返しのつかない操作は即時に通知 | 経路を問わず、すぐ分かること |
| 12 | 判断の記録と、2 人目の確認 | 1 人では実行できないこと |
| 2 | 判断と責任は MLOps | 経路が MLOps の手の中にあること |
| 11 | 戻すまでの期限は問わない | 急いで消す・戻す経路は要らない |

## 3. BreakGlass

### 3.1 前の提案の中身

FullAccess（13 名）はふだんの権限のまま残し、原本バケットの古い版の削除と守りを外す操作だけを、別の入口（専用の Okta アプリ → IAM ロール `BreakGlass`、パスキー、2〜3 名に固定）に移す。設計の軸は「必要なときは、許可を待たずに使える」と「使ったことが必ず分かる」。

### 3.2 要件に照らす

| 要件 | BreakGlass で満たせるか |
|---|---|
| 7 乗っ取り | **一部。** 14 名のふだんのセッション（W1）を乗っ取られても、古い版は消せなくなる。ただし BreakGlass の 1 名を乗っ取られれば、すべてできる。deploy の経路（W2・W4）、GitHub App（W3）、root・管理アカウント（W5）には効かない |
| 9・10 即時の通知 | 満たせる。ただし BreakGlass に限らず、どの経路にも要る仕組みで、BreakGlass が生むものではない |
| 12 2 人目の確認 | **満たせない。** 「許可を待たずに使える」が設計の軸なので、1 人で実行できる。2 人目を足すと、BreakGlass の意味（すぐ使える）が薄れる |
| 2 MLOps の判断 | 満たせる |
| 11 期限なし | 「すぐ使える」の価値が下がる。急いで消す・戻す必要が無いため |

### 3.3 再評価: 必要性は下がった

理由は 3 つ。

1. **要件 12 とぶつかる。** BreakGlass は「1 人で、すぐ」のための仕組み。要件は「2 人で、記録を残して」。急ぐ必要も無い（要件 11）。
2. **乗っ取りへの守りとして弱い。** 守れるのはふだんのセッションの乗っ取りだけで、一番大きい穴（W2: deploy の経路）は別の手当て（SCP）が要る。外せない層は WORM が担える（4 章）。
3. **同じことを、人に強い権限を持たせずに満たせる見込みがある。** 意図した削除と守りの変更の経路を、cdk-apps の PR だけにする。
   - PR の本文が判断の記録になり、承認が 2 人目の確認になる（要件 12）。
   - 大量に消すときはライフサイクルで消す（共有済みのプランの原則 2 と同じ）。1〜2 日かかるが、急がない（要件 11）。
   - バケットポリシーの例外から人（FullAccess・AWSAdministratorAccess）を外し、deploy の経路だけを残す。W1 が消える。
   - 削除マーカーからの戻しは、古い版を上にコピーし直せば、例外の権限が無くてもできる（W12）。

この案の弱いところと、要る手当て:

| 弱いところ | 手当て |
|---|---|
| 承認が 1 名で、どのアプリの PR からでも 12 本を変えられる（W2） | 原本バケットの守りに触れる変更は、承認を 2 名にする。CODEOWNERS を共通部と各アプリのバケットの定義に付ける。ただし、どのアプリからでも書けてしまう点は CODEOWNERS では塞げないので、即時の通知（要件 10）と WORM に頼る |
| 承認なしでマージできる GitHub App（W3） | 正体と権限を確かめ、原本バケットに届く変更を出せないようにする |
| deploy のロールを、アカウント内の誰でも引き受けられる（W4） | SCP で、`cdk-hnb659fds-*` の作成・信頼の変更を止める（TODO 24）。deploy のロールの引き受けを GitHub Actions のロールに絞る |
| 特定の版を 1 つだけ消す、が CloudFormation ではできない | 要るのは、混入したデータを消す場合くらい（WORM の設計の 4 章）。要るときは、その時だけ例外を足す PR を出す（PR が記録と 2 人目になる） |
| CI が止まると、誰も守りを変えられない | 3.4 の道で足りる |

### 3.4 本来の意味の break-glass

ふだんの経路（Okta・SSO・GitHub・CI）が使えないときの入口は、今もある。

- 管理アカウントの管理者が、root の一元管理（`sts:AssumeRoot` → `S3UnlockBucketPolicy`）で、バケットポリシーを外せる。締め出されたときの戻し道になる。
- これは CorpIT の手の中にあり、MLOps の判断（要件 2）とは別の経路になる。使われたら即時に通知する対象（要件 9 の「例外に届く権限の変更」）に入れる。

前の提案のうち、残す価値があるもの:

- フィッシングに強い MFA の考え方（パスキー）。PR を承認する人の GitHub のアカウントと、FullAccess の Okta に当てはめられる。
- 「使ったことが必ず分かる」の通知の設計（`AssumeRoleWithSAML` が `readOnly: true` で記録される落とし穴など）。

## 4. WORM

### 4.1 前の設計の中身

12 本にコンプライアンスモードの Object Lock を入れ、鍵は可変の保持期間（イベントホールド）にする。時間がたっても外れず、ホールドを解除しても 30 日は誰も消せない。解除と既定の変更は BreakGlass だけに許す。今ある各オブジェクトの最新版にもかける（一度きり約 $3,900）。

### 4.2 要件に照らす

| 要件 | WORM で満たせるか |
|---|---|
| 6 存続＋完全性 | **満たせる。** 鍵のかかった版は、上書きされても消えず、中身も変えられない |
| 7 乗っ取り | **満たせる。** コンプライアンスモードの鍵は、root を含め、アカウントの中の誰にも外せない。deploy の経路（W2・W4）、GitHub App（W3）、root・管理アカウント（W5）を乗っ取られても、鍵のかかった版は消えない。ホールドを解除されても 30 日あるので、通知で気づける。守れないのはアカウントの閉鎖で、範囲の外（c） |
| 9・10 即時の通知 | 通知そのものは別の仕組み。解除の後の 30 日が、通知で気づいてから止めるまでの猶予になる |
| 12 2 人目の確認 | WORM だけでは満たせない。解除の経路（4.4）に 2 人目を組み込む |
| 11 期限なし | 合う。消すのが最短 30 日遅れても困らない |

### 4.3 再評価: 有用性は上がった

- 乗っ取りを範囲に入れたことで、「アカウントの中の守りは、強い主体を乗っ取られると外される」（W6）への答えが要る。候補の 3 つを比べると、WORM がいちばん直接に効く。

| | WORM（コンプライアンス） | SCP・RCP | 別のアカウントへの写し |
|---|---|---|---|
| tuscenes-prod の中の乗っ取り | 守れる | 守れる | 守れる（写しが残る） |
| 管理アカウントの乗っ取り | **守れる**（30 日の猶予） | 守れない（SCP を外される） | 写し先次第 |
| 完全性（中身を変えられない） | 守れる | 守れる | 写しの側で要る |
| 外れたら戻せるか | 戻せない（設定の誤りに上限なし） | 戻せる | 戻せる |
| 前提・手間 | 書き込みの経路、試し、既存の版にかける作業 | 例外の経路の設計 | 写し先のアカウントの守り、保存の費用が倍 |

- c でアカウントの閉鎖を外にしたので、WORM で守れない経路は、ほぼ残らない。
- 解除の後の 30 日は、5 章の骨格の「遅らせる」を担える唯一の選択肢。即時の通知（要件 10）と組み合わさって、「外されても、消える前に気づいて止める」になる。

### 4.4 前提と、直すところ

| 項目 | 中身 |
|---|---|
| **解除の経路** | 前の設計では「解除と既定の変更は BreakGlass だけ」。3 章のとおり BreakGlass を置かないなら、cdk-apps の PR を経路にする。ホールドの解除は Batch Operations のジョブで行うので、CI からジョブを作れるか（カスタムリソースなど）を調べる |
| 解除の経路が乗っ取られても | 30 日あり、解除は即時に通知される（要件 9）。経路を強くしすぎなくてよい |
| 試し | コンプライアンスでもホールドを解除できるか（Q4）が条件。試しの手順書（[worm-probe-runbook.md](worm-probe-runbook.md)）は未実行 |
| 戻せない | 一度入れたら外せない。入れ方の誤り（日数・対象）の費用には上限が無い。小さいバケットから段階的に入れ、2 人で確かめる（設計の 2.4） |
| 書き込みの経路 | 新しいオブジェクトに既定でホールドがかかること、書き込み側にヘッダーが要らないことを、試しで確かめる |
| 混入したデータ | 30 日は消せない。読み取りを Deny して対処する（設計の 4 章） |
| 監査ログ | 範囲の外（c）だが、通知と調査は記録に頼る。記録の守り（W11）は、別の問題として早めに扱う |

## 5. 組み合わせの見立て

5 章の骨格の役割ごと。

| 役割 | 担うもの | 塞ぐ弱点 |
|---|---|---|
| 止める（外せない層） | WORM（コンプライアンス・イベントホールド） | W2・W4〜W6 の行き着く先（古い版の削除） |
| 止める（補助） | バケットポリシーの Deny（今ある層）。例外から人を外し、deploy の経路だけにする | W1 |
| 止める（補助） | SCP で deploy のロールを守る。GitHub App の確認。原本バケットに触れる PR の承認を 2 名に | W2〜W4 |
| 遅らせる | WORM の解除の後の 30 日 | W14 |
| 気づく | 取り返しのつかない操作（要件 9）の即時の通知。ふつうの削除・上書きは本人に知らせる。記録は先に始めた（[cdk-apps#2387](https://github.com/turingmotors/cdk-apps/pull/2387)） | W8〜W10 |
| 戻す | バージョニング＋WORM。古い版のコピーし直しで戻す手順 | W12・W13 |
| 判断と特権の経路 | cdk-apps の PR（判断の記録＋2 人目）。非常時は管理アカウントの解除 | W15 |
| 対象 | 台帳を共通部に置く | W16 |

順番の見込み: WORM は試しと解除の経路の設計が先に要り、時間がかかる。そのあいだは、即時の通知と SCP・PR の承認で、W2 を先に狭める。

## 6. 決めてほしいこと

**2026-10-30 の回答（伊藤）:**

1. **BreakGlass は撤回する方向で検討を進める。**
2. **WORM は「外せない層」の本命の候補にする（仮決定）。** 確定ではない。
3. ホールドの解除を cdk-apps の PR から行う形を調べる（7 章）。
4. Notion（BreakGlass の提案・プラン）の修正は最後にする。

当初の問い:

1. **BreakGlass の扱い。** 置かない（cdk-apps の PR を唯一の経路にする）方向でよいか。置かないなら、バケットポリシーの例外から FullAccess・AWSAdministratorAccess を外すことになり、チームへの周知が要る。
2. **WORM を「外せない層」の本命にするか。** するなら、試し（Q4）を再開する。
3. **解除の経路。** WORM のホールドの解除を、cdk-apps の PR から行う形を調べてよいか。
4. **共有済みの資料の扱い。** BreakGlass の提案（Notion、第一版）と、プランの原則 4（承認ではなく通知）を、この再評価に合わせて直すか。

## 7. 解除の経路の調査（2026-10-30）

問い: WORM のホールドの解除を、cdk-apps の PR から行えるか。要件 12（判断の記録＋2 人目の確認）を満たせるか。

### 7.1 結論

- **できる。ただし CDK（CloudFormation）ではなく、GitHub Actions の専用の workflow から行う。** CloudFormation には Batch Operations のジョブの型が無い。カスタムリソースでも作れるが、deploy の経路（cfn-exec-role、どのアプリの PR からでも使える）に解除の力を足すことになり、W2 を広げるので採らない。
- 形の案:
  1. 解除の依頼（対象の一覧・理由・判断した人）を、PR で cdk-apps に足す。PR の本文と依頼のファイルが判断の記録になる。
  2. マージされると、専用の workflow が動く。workflow のジョブは専用の environment（例 `original-bucket-release`。`main` からだけ使える）を参照する。
  3. ジョブは GitHub の OIDC で専用のロールに入る。ロールの信頼は `sub` を `repo:turingmotors/cdk-apps:environment:original-bucket-release` に固定する。権限は、Batch Operations のジョブを作ること（`s3:CreateJob`）と、解除用のロールを渡すこと（`iam:PassRole`）だけ。
  4. Batch Operations のジョブが、解除用のロールで各版のホールドを外す（`S3PutObjectRetention`、`EventHold: OFF`）。解除の時刻から 30 日後に消せるようになる。
  5. 解除は即時に通知される（EventBridge の `Object Retention Updated`）。
- **2 人目の確認は、PR の承認に頼ることになる。** GitHub の environment の承認者（required reviewers）は、Team プランの非公開リポジトリでは使えない。cdk-apps は非公開で、組織のプランは Team。
- **今の PR の承認は、2 人目の確認として弱い。** 承認のあとに作者が変更を足しても、承認し直しが要らない設定になっている（7.3）。
- 解除の経路が乗っ取られても、30 日は消せず、解除は即時に通知される。この経路の強さは、要件 7（乗っ取り）よりも、要件 12（2 人目）のために要る。

### 7.2 守るために要る設定

| 設定 | 中身 | 理由 |
|---|---|---|
| バケットポリシー | **`s3:PutObjectRetention` を、解除用のロール以外すべてに Deny する**（`EventHold: OFF` に限らない） | 固定の保持期限を指定するリクエストでも、ホールドは外れる。条件キー `s3:object-lock-event-hold` がそのリクエストに付くかは書かれていない |
| バケットポリシー | `s3:PutBucketObjectLockConfiguration` を、deploy の経路以外に Deny する（今の `DenyIrreversibleDelete` は例外が人になっている） | 既定の保持の変更。条件キーはバケットの既定には効かない |
| SCP | 解除用のロールを渡すこと（`iam:PassRole`）を、専用の OIDC ロール以外に Deny する。2 つのロールの作成・削除・信頼とポリシーの変更も止める | FullAccess など `iam:PassRole` を持つ主体は、解除用のロールでジョブを作れてしまう。アカウントの中のポリシーでは塞げない（TODO 24 と同じ作業） |
| GitHub | ルールセットで「最後の push の承認」（`require_last_push_approval`）を有効にする。解除の依頼のファイルの CODEOWNERS を決まった人にする | 承認のあとの変更が承認なしでマージされるのを防ぐ |
| 通知 | EventBridge の `Object Retention Updated`。CloudTrail ではデータイベントの `PutObjectLockRetention`（API の名前と違う）と、管理イベントの `CreateJob`・`JobCreated` | 要件 9・10 |

2 人目を AWS の側で求める対案: ジョブを確認待ち（`ConfirmationRequired`）で作り、別の人が `UpdateJobStatus` で開始する。ただし、作った主体と確認する主体を分ける仕組みは AWS に無い。分けるには、OIDC ロールに `s3:UpdateJobStatus` を持たせず、確認する人の権限を SCP で絞る必要がある。手間が増えるので、まずは PR の承認を強くする方を推す。

### 7.3 調べた場所

| 調べた場所 | 分かったこと |
|---|---|
| CloudFormation の型の一覧（`aws cloudformation list-types`、`AWS::S3*`）と、[AWS::S3 のリファレンス](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/AWS_S3.html) | Batch Operations のジョブの型は無い |
| AWS CLI 2.38.5 に入っている S3 Control の API の定義（`botocore/data/s3control/2018-08-20/service-2.json`） | ジョブの `S3PutObjectRetention` は `EventHold: ON/OFF` と日数（1〜36,500 日）を受け付ける。`ConfirmationRequired` がある |
| [Batch Operations の権限](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops-iam-role-policies.html)・[CreateJob](https://docs.aws.amazon.com/AmazonS3/latest/API/API_control_CreateJob.html) | ジョブを作るには `s3:CreateJob` と、ジョブのロールへの `iam:PassRole` が要る。各オブジェクトの操作はジョブのロールで行う |
| [Batch Operations と保持](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops-retention-date.html) | ジョブでホールドの解除ができる。**固定の保持期限を指定すると、ホールドは外れる** |
| [ジョブの状態](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops-job-status.html)・[UpdateJobStatus](https://docs.aws.amazon.com/AmazonS3/latest/API/API_control_UpdateJobStatus.html)・[ジョブのタグ](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops-job-tags-examples.html) | 確認待ちのジョブは `UpdateJobStatus`（`s3:UpdateJobStatus`）で開始する。作る人と確認する人を分ける仕組みは無い（IAM とジョブのタグで絞るだけ）。確認が要る条件はページによって書き方が食い違う |
| [Object Lock の注意点](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-managing.html)・[設定](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-configure.html)・[概要](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html) | 条件キー `s3:object-lock-event-hold`・`-duration-days` がある（バケットの既定には効かない）。**コンプライアンスでも解除できる**（解除の時刻＋日数が最終の期限になり、短縮にはならない）。試しの Q4 の答えはドキュメント上は「できる」 |
| [CloudTrail の S3 の記録](https://docs.aws.amazon.com/AmazonS3/latest/userguide/cloudtrail-logging-s3-info.html)・[Batch Operations と EventBridge・CloudTrail](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops-examples-event-bridge-cloud-trail.html)・[トラブルシューティング](https://docs.aws.amazon.com/AmazonS3/latest/userguide/troubleshooting-batch-operations.html) | `PutObjectRetention` は `eventName` が `PutObjectLockRetention` のデータイベントになる（保持の中身が `additionalEventData` に入る）。`CreateJob` は `eventSource` が `s3.amazonaws.com` の管理イベント。`JobCreated`・`JobStatusChanged` のサービスイベントもある |
| [S3 のイベント通知の種類](https://docs.aws.amazon.com/AmazonS3/latest/userguide/notification-how-to-event-types-and-destinations.html)・[S3 と EventBridge](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventBridge.html) | 解除は `s3:ObjectRetention:Put`、EventBridge では `Object Retention Updated` になる。即時に通知できる |
| [GitHub の OIDC](https://docs.github.com/en/actions/reference/security/oidc) | ジョブが environment を参照すると、`sub` は `repo:ORG/REPO:environment:NAME` になる |
| [GitHub の environment](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments) | Team プランでは、承認者は公開リポジトリだけ。ブランチの制限は非公開でも使える |
| [IAM の OIDC の条件キー](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_iam-condition-keys.html) | GitHub の `environment`・`workflow`・`job_workflow_ref`・`repository_id` なども条件に使える |
| GitHub の API（`repos/turingmotors/cdk-apps`、`orgs/turingmotors`、`environments`、`rulesets`、`rules/branches/main`） | 非公開、プランは Team。environment は `auto-merge`（ブランチの制限だけ）と `copilot`。`main` のルールは PR 必須・承認 1 名・CODEOWNERS 必須で、**承認のあとの push の承認し直しも、古い承認の取り消しも無効** |
| cdk-apps の main（`git grep`）と `update-cdk-context-image-digest.yml` | Batch Operations の先例は無い。OIDC のロールはどれも `sub` で絞る形。W3 の App は `cdk-apps-auto-merge` で、権限はマージだけ、認証情報は `main` からしか使えない environment に置かれ、送り手も固定されている（W3 のおそれは小さい。鍵が漏れたら、開いている PR を承認なしでマージできる点は残る） |

### 7.4 カナリアでの実測（2026-10-30、pw-1030-pr のセッション）

[cdk-apps#2387](https://github.com/turingmotors/cdk-apps/pull/2387) のレビュー対応で、別のセッション（pw-1030-pr）がカナリアで確かめた。2026-10-30 06:33 UTC に、`batch-probe/` の 2 件へ Batch Operations のジョブ（`S3PutObjectTagging`、一時ロール `original-bucket-canary-batch-probe`）を流し、トレイル `original-bucket-audit` のログを ReadOnly で読んだ。

- **キーごとに 1 件ずつ、データイベントとして記録される。** 費用は 1 億件あたり $100 で、Batch Operations の料金（100 万件あたり $1）と同じ額が上乗せされる。WORM で 6.5 億件にホールドをかけると、トレイルの分が約 $650 増える（12 本の記録を始めた後なら）。
- **主体は、ジョブを作った人ではなく、ジョブに渡したロール。** `userIdentity.arn` は `assumed-role/<ジョブのロール>/s3-batch-operations_<ジョブ ID>`。`invokedBy`・`sourceIPAddress`・`userAgent` は `batchoperations.s3.amazonaws.com`。→ 7.2 の「バケットポリシーで、解除用のロールだけに `PutObjectRetention` を許す」は、この形で効く。
- **人までは、管理イベントを時刻で突き合わせて辿る。** `CreateJob` の主体は作った人で、`RoleArn`・`Operation`・`Manifest` は載るが、ジョブ ID は載らない。`JobCreated` にはジョブ ID が載るが、主体は `s3.amazonaws.com`。「データイベントのセッション名のジョブ ID → `JobCreated` の時刻 → 同じ時刻・同じ `RoleArn` の `CreateJob` → 人」の順に辿る。7.1 の形なら `CreateJob` の主体は OIDC のロールになるので、workflow の実行の記録にジョブ ID を残し、PR（人）につなぐ。
- **Batch Operations には削除の操作が無い。** 削除は `LambdaInvoke` 経由だけで、そのときは Lambda のロールの `DeleteObject` がキーごとに記録される。
- `S3BatchDeleteLidar` のロールは一度も使われていない。2026-08〜09 の LiDAR の削除は、LidarDeleter による直接の削除だった。

### 7.5 確かめていないこと（試しに足す）

- 固定の保持期限を指定するリクエストに、条件キー `s3:object-lock-event-hold` が付くか（付かなくても、7.2 のとおり `PutObjectRetention` 全体を Deny すれば足りる）。
- API から作ったジョブで、`ConfirmationRequired: true` が効くか（ドキュメントが食い違う）。
- コンプライアンスでの解除（Q4）。ドキュメントでは「できる」と読めるので、試しは確認の意味になった。
