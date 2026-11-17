# cdk-apps の PR の本文: 第 1 段階（手順 A）

- 作成: 2026-11-09 ／ 伊藤（エージェントが起草）
- 元: [worm-rollout-stages.md](worm-rollout-stages.md) の「全体」「第 1 段階」「第 3 段階」
- ブランチ: [`feat/original-bucket-worm-step-a`](https://github.com/turingmotors/cdk-apps/tree/feat/original-bucket-worm-step-a)（`38b26cd0`、レビューの指摘を直した `c8c8d394`・`d019123d`、gaming-data-collection を対象から外した `eb40da4f`）。**PR: [cdk-apps#2500](https://github.com/turingmotors/cdk-apps/pull/2500)**（2026-11-09 に作った）
- タイトル: `feat(original-bucket-guard,original-bucket-audit): Object Lock の導入に備え、迂回の禁止とジョブのロール・レポートの置き場を足す`

以下が本文。

---

## 概要

原本バケット（集め直せない走行データなどを置く S3 バケット）に、S3 Object Lock をガバナンスモードで入れる計画の、最初の PR です。次の段階で使う部品を先に置きます。

計画の全体は Notion の「原本バケットの WORM 化: 現在地と計画」（https://app.notion.com/p/40fa93b3e6f2811bb51ffaef3cc970e9）にあります。導入は次の 3 つの段階で進めます。

| 段階 | 目的 | 形 |
|---|---|---|
| **第 1 段階（この PR）** | 部品を置く | cdk-apps の PR |
| 第 2 段階 | Object Lock を入れる | CLI と S3 Batch Operations の作業 |
| 第 3 段階 | 抜け穴を塞ぐ | cdk-apps の PR（通知、例外の絞り込み）と、組織のポリシー |

## 対象のバケット

| 区分 | バケット |
|---|---|
| **Object Lock を入れる 9 本** | `td1-raw-767397804933`、`tuscenes-raw-767397804933`、`td1-rlog`、`tuscenes-calibration`、`tuscenes-calibration-767397804933`、`tuscenes-annotation-767397804933`、`denso-nx-raw-767397804933`、`denso-taxi-processed-767397804933`、`denso-taxi-video-767397804933` |
| 入れない 3 本 | `tuscenes-model-767397804933`、`gaming-data-collection-767397804933`、`denso-raw-767397804933`（tuscenes-model は費用をかければ作り直せ、入れ替わりが激しいため。gaming-data-collection はシミュレータで集めたデータで、収集を終えている。2026-11-10 に持ち主が除外を了承。denso-raw は持ち主が退職して不在で、使われた形跡も無いため。2026-11-10 に除外を決めた。tuscenes-annotation は 2026-11-10 に対象に戻した（人手のラベルで、付け直すのが難しい）） |
| カナリア | `original-bucket-canary-767397804933`。原本バケットと同じ守り（バージョニング・守りのバケットポリシー）を入れた検証用のバケットで、原本のデータは置かない（`OriginalBucketCanary` スタック、[#2267](https://github.com/turingmotors/cdk-apps/pull/2267)）。手順を原本バケットに入れる前に、ここで試す |

## この PR でやること

| 部品 | 中身 |
|---|---|
| 迂回の禁止 `DenyGovernanceBypass`（`packages/original-bucket-guard`） | 守りのバケットポリシーに、Object Lock の保持の迂回（`s3:BypassGovernanceRetention`）を**全員に**拒否する文を足す。原本バケット 12 本とカナリアに入る |
| 保持の変更の禁止 `DenyLockChange`（同上） | 守りのバケットポリシーに、保持の変更（`s3:PutObjectRetention`）とリーガルホールドを、ジョブのロール以外の**全員に**拒否する文を足す。IAM で同じ権限を持つ主体（td1-raw では 24）や、似た権限で新しく作ったロールも拒否される。当初は第 3 段階の予定だったが、第 2 段階で保持を付け始めてから第 3 段階までの間に誰でも外せる穴が残るので、前倒しした。第 2 段階で保持を変えるのはジョブのロールだけなので、作業は止まらない |
| コンプライアンスモードの禁止 `DenyComplianceMode`（同上） | 守りのバケットポリシーに、コンプライアンスモードの保持を付ける要求（`s3:PutObject` のヘッダー `x-amz-object-lock-mode` と `s3:PutObjectRetention`。条件キー `s3:object-lock-mode` が `COMPLIANCE`）を**全員に**拒否する文を足す。コンプライアンスモードの保持は root でも縮められず、期限まで版もバケットも消せない。既定の保持設定から付く保持には効かないので、書き込みは止まらない。ジョブのロールの同じ Deny は、二重の守りとして残す |
| テストを CI で走らせる（`.github/workflows/`） | `original-bucket-audit-diff.yml`・`datalake-diff.yml`・`gaming-data-collection-diff.yml` に `npm test` を足す。守りの権限（バケットポリシーの文・ロールのポリシー）はテストで固定しているが、これまで CI で走っていたのは denso-taxi だけだった。Lambda のバンドルは飛ばす（denso-taxi と同じ） |
| ジョブのロール `original-bucket-lock-batch`（`apps/original-bucket-audit`、新しいスタック `OriginalBucketLockBatch`） | S3 Batch Operations だけが引き受けられるロール（`aws:SourceAccount` で tuscenes-prod に固定）。Object Lock を入れる 9 本とカナリアの版の保持を付ける・外す・読むこと、ジョブに対象の一覧を作らせること（ManifestGenerator）、レポートの置き場への読み書きだけができる。**対象のバケットの版の削除・上書き・保持の迂回・タグ付けはできない**。ジョブの指定を誤ってもコンプライアンスモードの保持は付けられないよう、ロールのポリシーで拒む（コンプライアンスモードは root でも縮められず、期限まで版もバケットも消せない）。付けられるイベントホールドは、解除後の保持期間が `EVENT_HOLD_DAYS`（今は 30 日。仮の値）のものだけ。ほかの日数・年での指定・固定の期限は拒む（日数を誤ると、解除しても直せず、直すには迂回が要る）。解除の要求は日数を持たないので止まらない。権限はテストで文ごと固定した |
| レポートの置き場 `original-bucket-lock-batch-reports-767397804933`（同上） | ジョブが作った対象の一覧と、1 件ずつの結果を残す。何に保護を付けたかの記録なので、消さない（バージョニング・ライフサイクルなし）。原本バケットと同じ守りのバケットポリシー（`original-bucket-guard` の文）を入れる |

- 解除後の保持期間を変えるときは、`EVENT_HOLD_DAYS` を変える PR と、各バケットの既定の保持設定（CLI）を揃える。第 2 段階でホールドを付ける前なら、費用はかからない。
- ロールの名前は `LOCK_BATCH_ROLE_NAME` として `original-bucket-guard` に置いた。保持の変更の禁止（`DenyLockChange`）は、このロールだけを例外にする。

### deploy されるアプリ

`packages/original-bucket-guard` を変えたので、使っているアプリがすべて deploy される。どのアプリでも、変わるのは原本バケットのバケットポリシーに 1 文が加わることだけ。

| アプリ | 変わるもの |
|---|---|
| `apps/datalake` | 8 本（td1-raw・tuscenes-raw・tuscenes-calibration（新旧）・tuscenes-annotation・tuscenes-model・td1-rlog・denso-raw）のバケットポリシー |
| `apps/gaming-data-collection` | gaming-data-collection のバケットポリシー |
| `apps/denso-taxi` | denso-taxi-processed・denso-taxi-video のバケットポリシー |
| `apps/denso-nx` | denso-nx-raw のバケットポリシー |
| `apps/original-bucket-audit` | カナリアのバケットポリシーと、新しいスタック `OriginalBucketLockBatch`（ロール・ポリシー・レポートの置き場） |

## この次にやること（第 2 段階: Object Lock を入れる）

この PR の deploy のあと、CLI と S3 Batch Operations で、各バケットに Object Lock を入れる。cdk-apps は変えない。

1. **カナリアで予行する。** まず、この PR のロールで、対象の一覧を作らせてイベントホールドを付けるジョブを流す（この組み合わせは、第 2 段階の予行で初めて流す。下の「確かめたこと」）。あわせて、コンプライアンスモードの指定が拒まれること、後から Object Lock を有効にしたときの振る舞い、書き込みが止まったときの戻し方、イベントホールドを外すジョブが通るかを確かめる。カナリアは、そのあとも手順の訓練に使う。
2. **書き込みの少ないバケットから、段階 1〜3 の順に入れる。**

   | 段階 | バケット |
   |---|---|
   | 1 | `tuscenes-calibration`、`tuscenes-calibration-767397804933`、`td1-rlog` |
   | 2 | `denso-taxi-processed-767397804933`、`denso-taxi-video-767397804933`、`denso-nx-raw-767397804933`、`tuscenes-annotation-767397804933` |
   | 3 | `td1-raw-767397804933`、`tuscenes-raw-767397804933` |

   各バケットで、
   1. Object Lock を有効にし、既定の保持設定（ガバナンスモード、イベントホールド、解除後の保持期間 30 日）を入れる。有効にする操作は戻せない。
   2. 1 日ほど、書き込み元のエラーを見る。
   3. S3 Batch Operations のジョブ（この PR のロール）で、最新の版にイベントホールドを付ける。対象の一覧はジョブに作らせ、確認待ちで止めて、件数と中身を 2 人で確かめてから流す。
   4. 付いた件数を確かめる。

   `tuscenes-calibration-767397804933` だけは SSE-KMS（AWS 管理のキー `aws/s3`）で暗号化されている。カナリアでは確かめられないので、段階 1 で、このバケットは少ない件数で先に流す。

既定の保持設定は CDK に持たせない。CloudFormation で既存のバケットの `ObjectLockEnabled` を変えたときに、作り直しにならないかを確かめていないため。

## さらにその次にやること（第 3 段階: 抜け穴を塞ぐ）

第 2 段階で付けた保護を外せる主体を絞り、外されたら気づけるようにする。

1. **通知（cdk-apps の PR）:** イベントホールドの解除、バケットの設定の変更、S3 Batch Operations のジョブの作成と状態の変更、通知の仕組みの変更を、SNS からメールで知らせる。拒まれた試みも拾う。
2. **例外の絞り込み（cdk-apps の PR）:**
   - 既存の 2 文の例外から FullAccess を外す。古い版の削除・設定の変更は、AWSAdministratorAccess と deploy の経路だけになる。
3. **組織のポリシー（`apps/organization-policy`）:**
   - ジョブのロールを渡す操作を AWSAdministratorAccess だけにし、ロール自体の変更を deploy の経路以外に禁じる。
   - deploy の経路（`cdk-hnb659fds-*` のロールと、GitHub Actions の deploy のロール）を、GitHub Actions の deploy 以外から使えないようにする。手元の PC からの `cdk diff` は使えなくなる（差分は GitHub Actions で取る）。

終わった時点では、保護を外せるのは AWSAdministratorAccess の人がジョブを作ったときだけになり、外しても解除してから 30 日は消せず、解除は通知される。

## 確かめたこと

- `npx jest`（Lambda のバンドルを飛ばして）: original-bucket-audit（17 件）・datalake（25 件）・gaming-data-collection（5 件）・denso-taxi（8 件）が通る。この PR から、denso-taxi 以外の 3 つも CI で走る。ロールの権限のテストは、対象のバケットへの `s3:PutObject` をわざと足すと落ちることを確かめた。denso-nx にはテストが無い。
- `tsc --noEmit`: 上の 4 つと denso-nx で通る。
- `cdk diff`（ReadOnly）:
  - datalake・gaming-data-collection・カナリアは、バケットポリシーに `DenyGovernanceBypass` が加わるだけ（`DenyComplianceMode` を足したあとの差分は、この PR の CI の diff で確かめる）。
  - `OriginalBucketLockBatch` は新規（ロール・ポリシー・レポートの置き場と、そのバケットポリシー）。
  - denso-taxi・denso-nx は手元に docker が無いので取れていない（この PR の CI の diff で確かめる）。
- ジョブに対象の一覧を作らせる方法（ManifestGenerator）は、カナリアで一時的なロールを使って確かめた。一覧には最新版だけが版の ID つきで入り、古い版と、最新が削除マーカーのキーは入らなかった。ただし、そのロールは対象を読む権限（`s3:GetObject`）を持ち、操作はタグ付け、一覧の書き出し先はカナリア自身だった。この PR のロール（対象を読む権限なし・操作は保持の変更・書き出し先は別のバケット）の形では、第 2 段階の予行で初めて流す。AWS のドキュメントの例（保持の変更・一覧の作成）では、対象を読む権限は要らない。原本の中身を読める権限になるので、足していない。

## deploy の後に確かめること

1. 原本バケット 12 本とカナリアのバケットポリシーに、`DenyGovernanceBypass`・`DenyLockChange`・`DenyComplianceMode` があること（`aws s3api get-bucket-policy`）。
2. ロール `original-bucket-lock-batch` の信頼が S3 Batch Operations だけで、権限が上のとおりであること（`aws iam get-role`、`list-role-policies` でポリシーの名前を取ってから `get-role-policy`）。
3. レポートの置き場がバージョニングされ、守りのバケットポリシーが入っていること。

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01L82wrAnjNpQ8NfFjaQJs7g
