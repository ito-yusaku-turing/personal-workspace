# 権限の頂点の把握と管理

- 開始: 2026-11-02
- 状態: **CorpIT に 1 回目の聞き取りをし、S3 の案件で人のグループ（最高権限者ほか）を整理した段**（2026-11-02）。次は 2 回目の聞き取り（I19・I27・I28・I26・I29・I30 ほか）

GitHub の組織の owner・identity の admin・GCP の管理者・Okta の管理者が互いに届き合う「頂点の群」と、別系統の AWS の管理アカウントについて、何が存在するかを把握し、管理を徹底する案件。

## 背景・目的

S3 の原本バケットの保護（[第二弾](../../aws-data-protection/workstream/s3-data-protection-2.md)）で、要承認操作の 2 人目の確認を仕組みで強制する前に、流れを迂回できる経路を調べた（2026-11-02）。その結果、1 人で、誰にも通知されずに組織のほぼすべてに届く人が 10 名を超え、その頂点が輪になっていることが分かった（[privilege-map.md](apex-privileges/privilege-map.md) の 9 章）。

この問題はデータの保全の範囲を超えるので、S3 の案件から分けた（伊藤）。

目的:

- 構造上の上位権限者は無くせないので、存在は受け入れ、**何が存在しているかの把握と管理を徹底する**（2026-11-02、伊藤。S3 の案件の [requirements.md](../../aws-data-protection/workstream/s3-data-protection-2/requirements.md) の 7.4 から引き継いだ方針）。
- 管理の目指す形: 数を絞る、使えば即時に通知する、残るリスクとして明記する。

## 設計判断と理由

- **CorpIT は別の部署として扱わない。** 一体となってこの問題に取り組む（2026-11-02、伊藤）。
- **S3 の案件との分け方**（2026-11-02、伊藤）:
  - この案件: 頂点の台帳、頂点を狭めること、頂点が使われたときの通知、頂点にいる人の要件。
  - S3 の案件: WORM、2 人目の確認、システム保全責任者、輪の外への通知の受け手（頂点に頼らない守り）。S3 の案件は「頂点の群の乗っ取りは、この案件で扱う残るリスク」として進める。

## 進捗チェックリスト

- [x] GitHub の組織・identity・cdk-apps の層の経路を洗い出す（privilege-map.md の 2〜5 章）
- [x] 構造上の上位権限者の台帳を作る（8 章、U1〜U11）
- [x] 上位の構造を整理し、評価する（9 章）
- [x] あるべき姿の案を立てる（10 章。頂点は Workspace の super admin、ほどく辺は E1〜E5）
- [x] CorpIT に 1 回目の聞き取りをする（2026-11-02。結果は [corpit-hearing.md](apex-privileges/corpit-hearing.md)）
- [ ] 2 回目の聞き取りで、止められている循環の詳細を聞く（I27・I26・I28・I19）。地図の C1〜C4 を実際の経路に直す
- [ ] 見えない層を確かめる（ヒアリング項目 I1〜I18。GCP・Okta・Google・AWS の管理アカウント・GitHub の組織の設定）
- [ ] 頂点を狭める方針を決める（owner の人数、`all_repo_admin`、identity の `enforce_admins`、environment の制限）
- [ ] 頂点が使われたときの通知の方針を決める
- [ ] 頂点にいる人の要件を決める（MFA、管理用のアカウントの分離など）。S3 の案件で、最高権限者に普段使いとは別の管理用のアカウントを持ってもらう TODO が出た（requirements.md の 7.5.1）

## 次セッションへの引き継ぎ

- 現在地: 2026-11-02 に CorpIT へ 1 回目の聞き取りをした。結果は corpit-hearing.md の冒頭にあり、地図の 7 章・8 章（U7）・9.1・10.1・11 章に反映した。
- 分かったこと: GCP がすでに最上位（Okta を飛ばしてログインできるのは GCP だけ）。実質の最高権限者は 4 名（渡辺 晃平・山口 祐・山本 修平・大戸 一希）。指摘した循環のいくつかは止めてある（詳細は後日）。
- 頂点を Google の側に置く点は、10 章の案と CorpIT の設計で一致した。残る問いは、4 名が Workspace の super admin と一致しているか（I26）と、どの循環が止まっているか（I27）。
- I19（`gcp-organization-admins@` のロール）は、まだ聞けていない。
- 9.1 の図は、GCP を最上位にした上から下への階層に描き直した。下から上へ戻る矢印（C1・C2・C4・E4）が異常ポイント。
- 2026-11-02 の終わり: S3 の案件で、人のグループを最高権限者・システム保全責任者・通常権限メンバーに整理した（requirements.md の 7.5.1）。この案件に関わる宿題: 組織の owner を最高権限者の中に収めること（今は 4 名が外。I1・I28）、最高権限者の管理用のアカウントの分離（TODO）。未反映の提案は S3 の案件の workstream の最後の項にある。
- 次の聞き取りの優先: I19（`gcp-organization-admins@` のロール。最高権限者が 4 名より多いかが決まる）→ I27（止めてある循環）→ I30（組織のルールセット）→ I29（Workspace の apply のロールの範囲）。
- 説明資料のページ（apex-cycle.html、<https://claude.ai/artifact/Gtzn6zWuQXYW4KC2zpuMMo>）は、GCP を最上位にした階層図に差し替え済み。人のグループの整理は、まだ載せていない。
- S3 の案件で、最上位の 4 名を前提にしたシステム保全責任者の設計の案を書いた（[requirements.md](../../aws-data-protection/workstream/s3-data-protection-2/requirements.md) の 7.5）。この案件の聞き取りの答えが、その案の前提になる。
- 10 章の案は、セカンドオピニオン（別のエージェントの独立した考察）と突き合わせたもの。聞き取りの結果で見直す。
- identity の見た時点は、2〜5 章が ed1f678、10 章が 8b8e953。
- 調べるときの権限: GitHub は伊藤のアカウント（組織では member、cdk-apps では admin、identity では write）。devbox の gcloud にはユーザーのログインが無い。AWS は tuscenes-prod の ReadOnly（`--profile readonly`）だけ。

## 関連リンク

- [privilege-map.md](apex-privileges/privilege-map.md): 権限の地図（経路・ヒアリング項目・台帳・構造と評価・人ごとの一覧）
- [S3 バケットのデータ保護 第二弾](../../aws-data-protection/workstream/s3-data-protection-2.md)（分けた元）
- [AWS の権限の階層](../../aws-data-protection/documents/aws-privilege-hierarchy.md)（organization-policy の経路の調査）
- [特権アクセスと break-glass の一般論](../../aws-data-protection/documents/privileged-access-and-break-glass.md)
- identity（`/usr/app/identity`）・cdk-apps（`/usr/app/cdk-apps`）
