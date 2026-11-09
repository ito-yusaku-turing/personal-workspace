# 原本バケットの WORM 化: 導入の段階

- 作成: 2026-11-09 ／ 伊藤（エージェントが起草）
- 親: [S3 バケットのデータ保護 第二弾](../s3-data-protection-2.md)
- 状態: **第 1 段階の PR を作った**（[cdk-apps#2500](https://github.com/turingmotors/cdk-apps/pull/2500)、2026-11-09）
- 使い道: 導入の段階の正本。ここから、共有用の資料（[notion-worm-governance-rollout.md](../../documents/notion-worm-governance-rollout.md)）の 5.1 と、cdk-apps の各 PR の本文（[pr-step-a.md](pr-step-a.md) など）を作る。段階を変えたら、先にここを直す
- 前提: [worm-decisions.md](worm-decisions.md)（D1〜D24）、[permission-model.md](permission-model.md)（層と抜け穴）

**要点**

- 導入は 3 つの段階で進める。**部品を置く → Object Lock を入れる → 抜け穴を塞ぐ。**
- 第 1 段階と第 3 段階は cdk-apps の PR、第 2 段階は CLI と S3 Batch Operations の作業。
- どの段階も、日々の読み取り・書き込み・上書き・通常の削除は止めない。止まりうるのは、チェックサムを付けない書き込みだけで、第 2 段階で、書き込みの少ないバケットから順に確かめる。

## 対象のバケット

| 区分 | バケット |
|---|---|
| **Object Lock を入れる 10 本** | `td1-raw-767397804933`、`tuscenes-raw-767397804933`、`td1-rlog`、`tuscenes-calibration`、`tuscenes-calibration-767397804933`、`denso-raw-767397804933`、`denso-nx-raw-767397804933`、`denso-taxi-processed-767397804933`、`denso-taxi-video-767397804933`、`gaming-data-collection-767397804933` |
| 入れない 2 本 | `tuscenes-model-767397804933`、`tuscenes-annotation-767397804933`（費用をかければ作り直せるため。バージョニングと守りのバケットポリシーは残る） |
| カナリア | `original-bucket-canary-767397804933`。原本バケットと同じ守り（バージョニング・守りのバケットポリシー）を入れた検証用のバケットで、原本のデータは置かない。`apps/original-bucket-audit` の `OriginalBucketCanary` スタックが持つ。手順を原本バケットに入れる前に、ここで試す |

原本バケットは、上の 10 本と 2 本の計 12 本。どれも tuscenes-prod（767397804933）の us-west-2 にある。

## 全体

| 段階 | 目的 | 手順 | 形 | 終わった時点の姿 |
|---|---|---|---|---|
| 第 1 段階 | 部品を置く | A | cdk-apps の PR 1 本 | 迂回の禁止がバケットポリシーに入り、ジョブのロールとレポートの置き場ができている。止まる操作は無い |
| 第 2 段階 | Object Lock を入れる | B（カナリアで予行）→ C（段階 1〜3 の順に各バケットへ） | CLI と S3 Batch Operations の作業 | 対象の 10 本で、新しく書かれる版と、今ある最新の版が保護されている |
| 第 3 段階 | 抜け穴を塞ぐ | 通知 → D | cdk-apps の PR 2 本（通知、手順 D）と、組織のポリシー | 保護を外せるのは完全削除用の権限（AWSAdministratorAccess）がジョブを作ったときだけ。解除と設定の変更は通知される |

## 第 1 段階: 部品を置く（手順 A）

第 2 段階の作業に要る部品を、先に置く。

| 部品 | 中身 | 置き場 |
|---|---|---|
| 迂回の禁止 `DenyGovernanceBypass` | Object Lock の保持の迂回（`s3:BypassGovernanceRetention`）を、全員に禁じる文。原本バケット 12 本とカナリアのバケットポリシーに入る | `packages/original-bucket-guard` |
| ジョブのロール `original-bucket-lock-batch` | S3 Batch Operations だけが使えるロール。原本バケット 10 本とカナリアの版の保持を付ける・外す・読むことと、ジョブに対象の一覧を作らせることだけができる。版の削除・迂回・タグ付けはできない | `apps/original-bucket-audit` |
| レポートの置き場 `original-bucket-lock-batch-reports-767397804933` | ジョブが作った対象の一覧と、1 件ずつの結果を残す。何に保護を付けたかの記録なので、消さない。原本バケットと同じ守りのバケットポリシーを入れる | `apps/original-bucket-audit` |

- **変わらないこと:** 今は Object Lock が無いので、迂回の禁止が止める操作は無い。ジョブのロールも、ジョブを作るまで何もしない。
- **迂回の禁止を先に入れる理由:** 第 2 段階で Object Lock を入れたその時から、保護された版を迂回して消せない状態にするため。
- **誰が:** 伊藤が PR を作り、チームがレビューする。deploy は GitHub Actions（`main` へのマージ）。
- **終わった条件:** deploy が済み、3 つの部品ができている。

## 第 2 段階: Object Lock を入れる（手順 B・C）

### 手順 B: カナリアで予行する

カナリア（上の「対象のバケット」）に、後から Object Lock を入れて試す。カナリアは、そのあとも Object Lock を入れたまま、手順の訓練に使う。

確かめること:

- 既存のバケットに、後から Object Lock を有効にしたときの振る舞い。
- 既定の保持設定を外すと、チェックサムなしで書けるようになるか（書き込みが止まったときの戻し方）。
- ジョブのロールで、対象の一覧を作らせてイベントホールドを付けるジョブが通るか（このロールの形では初めて流す）。外すジョブが通るか。
- ジョブのロールで、コンプライアンスモードの保持を指定すると拒まれるか（ロールのポリシーで拒んでいる）。保持の変更の要求が、モードや期限の条件キーをどう持つか（固定の期限も止めるかを、これで決める）。
- DataSync が、Object Lock のバケットに書き込めるか。

ジョブに対象の一覧を作らせる方法（ManifestGenerator）は、2026-11-09 にカナリアで確かめた。一覧には最新版だけが版の ID つきで入り、古い版と、最新が削除マーカーのキーは入らない。確認待ちの設定で止めて、流す前に一覧を確かめられる（[manifest-generator-probe-runbook.md](manifest-generator-probe-runbook.md)）。

### 手順 C: 各バケットに入れる

書き込みが少なく、書き込み元の問題が無いものから入れる。

| 段階 | バケット | 理由 |
|---|---|---|
| 1 | tuscenes-calibration（新・旧）、td1-rlog、denso-raw | 書き込みが止まっている。件数が少ない |
| 2 | gaming-data-collection、denso-taxi-processed、denso-taxi-video、denso-nx-raw | 書き込み元が SDK の既定で書く見込み。denso の 3 本は Azure から DataSync で書き込まれる |
| 3 | td1-raw、tuscenes-raw | 対象の 10 本の版の数の 9 割を占める |

各バケットでの作業:

1. Object Lock を有効にし、既定の保持設定（ガバナンスモード、イベントホールド、解除後の保持期間 30 日）を CLI で入れる。**有効にする操作は戻せない。**
2. 1 日ほど、書き込み元のエラーを見る。
3. S3 Batch Operations のジョブで、最新の版にイベントホールドを付ける。対象の一覧はジョブに作らせ、確認待ちで止めて、件数と中身を 2 人で確かめてから流す。
4. 付いた件数を確かめる。

`tuscenes-calibration-767397804933` だけは SSE-KMS（AWS 管理のキー `aws/s3`）で暗号化されている。カナリアでは確かめられないので、段階 1 で、このバケットは少ない件数で先に流す。

- **誰が:** 伊藤（FullAccess）。ジョブの設定は、伊藤ともう 1 人で確かめる。
- **終わった条件:** 段階ごとに数日、書き込みのエラーが無い。10 本の最新の版に、イベントホールドが付いている。

## 第 3 段階: 抜け穴を塞ぐ（通知・手順 D）

第 2 段階までで付けた保護を、外せる主体を絞り、外されたら気づけるようにする。

### 通知（cdk-apps の PR）

第 2 段階の作業には使わないので、別の PR にする。手順 A〜C と並行して進め、手順 D の前に入れる。

| 何を | どう拾うか |
|---|---|
| イベントホールドの解除 | EventBridge の `Object Retention Updated` のうち、`ON` 以外。CloudWatch のアラームでまとめて、SNS からメール |
| バケットの設定の変更（バケットポリシー・既定の保持設定・ライフサイクル・バージョニング・通知の設定・削除など）と、S3 Batch Operations のジョブの作成と状態の変更 | CloudTrail の管理イベント。拒まれた試みも拾う |
| 通知の仕組みそのものの変更 | 同上 |

- **前に決めること:** 通知の受け手。
- **終わった条件:** カナリアで、すべての通知が届く。

### 手順 D（cdk-apps の PR と、組織のポリシー）

| 何を | 中身 |
|---|---|
| 保持の変更の禁止 `DenyLockChange` | 保持の変更とリーガルホールドを、ジョブのロール以外に禁じる文を、バケットポリシーに足す |
| FullAccess を例外から外す | 既存の 2 文（`DenyIrreversibleDelete`・`DenyProtectionRemoval`）の例外から FullAccess を外す。古い版の削除・バケットの設定の変更は、AWSAdministratorAccess と deploy の経路だけになる |
| ジョブのロールを守る組織のポリシー | ロールを渡す操作（`iam:PassRole`）を AWSAdministratorAccess だけにする。ロールの作成・削除・信頼の変更・ポリシーの変更を、deploy の経路以外に禁じる |
| deploy の経路を守る組織のポリシー | deploy のロールの引き受けを GitHub Actions の deploy のロールだけにする。cfn-exec-role を渡す操作を deploy のロールだけにする。`cdk-hnb659fds-*` のロールと GitHub Actions の deploy のロールの、作成・削除・信頼の変更・ポリシーの変更を禁じる |

- **前に済ませること:** AWSAdministratorAccess を持つ人の確認と、役を引き受けてもらえるかの相談。deploy のロールを引き受けている主体と、cfn-exec-role を渡している主体の確認（CloudTrail）。
- **止まるもの:** 手元の PC からの `cdk diff`（差分は GitHub Actions で取る）。`cdk bootstrap` のやり直し（組織のポリシーの例外を一時的に足す PR で行う）。
- **終わった時点の姿:** 保護を外せるのは、AWSAdministratorAccess の人がジョブのロールを渡してジョブを作ったときだけ。外しても、解除してから 30 日は消せない。解除と設定の変更は通知される。

## この計画のあとに残すもの

| もの | 中身 | 扱い |
|---|---|---|
| 既存のスタックの更新 | cdk-apps のスタックには deploy の経路のロールが付いたままなので、スタックを更新できる主体は、そのロールでバケットポリシーを書き換えられる | 把握した抜け道として残す。バケットポリシーの変更の通知で気づく。手当ては次の検討（D20） |
| バケットポリシーを書き換えられる主体 | AWSAdministratorAccess・deploy の経路・root・管理アカウントは、迂回の禁止を外せば、すぐ消せる | 受け入れる。変更の通知で気づく（D16） |
| 意図して消すときの手順 | 対象の決め方・承認・消す方法 | 消す必要が出たときに決める（D13） |
