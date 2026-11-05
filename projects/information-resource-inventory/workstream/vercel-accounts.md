# Vercel のアカウントの棚卸しと SSO 化の検討

- 開始: 2026-11-05
- 状態: **着手した**（2026-11-05）。リポジトリからチーム `turing-inc` と使われ方を洗い出した。次は SSO・2FA・ロール・料金を公式ドキュメントで調べる
- 所属: project:information-resource-inventory

Vercel のアカウント（組織・チームのメンバーと、その権限）を棚卸しし、社の IdP（Okta / Google Workspace）による SSO に寄せられるかを検討する。

## 背景・目的

- Vercel のアカウントの一覧と権限を把握する。
- 退職者・協力会社のアカウントが残っていないか、Owner など強い権限を誰が持っているかを確かめる。
- 入退社に合わせてアカウントを管理できるよう、SSO 化（あわせて可能ならプロビジョニング）を検討する。

## 現状（2026-11-05 時点）

リポジトリから分かったこと（`/usr/app/` 配下を grep）:

- チームは `turing-inc`（`vercel.com/turing-inc`。cdk-apps の jadd-studio・backend-api・tern-api の README とテストに出てくる）。
- プランは未確認。jadd_studio3 の資料には、cron の挙動から「Pro 以上と判断した」とある。
- `vercel.json` があるリポジトリ: jadd_studio3、jadd-studio-signage、fleet-ops、drivers-app-mono（`apps/drivers-app-manager`）。
- 参照されている `*.vercel.app`: jadd-studio2、studio2、drivers-app3、fleet-ops-sandy、fleet-management-blush、road-curvature-map、jadd-studio-ex。どれも `turing-inc` のチームにあるかは未確認。
- JADD Studio の本番の project ID は `prj_ywCO4lG6pJIo5tdrnGaMz4AxVbAS`（jadd_studio3 の監査ログの workstream）。

伊藤のアカウント・ロール、Owner、メンバーの数、2FA の状況はまだ聞いていない。

## 設計判断と理由

（まだ無い）

## 進捗チェックリスト

- [ ] 棚卸しの対象（組織・チーム・プロジェクト）を洗い出す
- [ ] メンバーと権限（Owner・管理者など）の一覧を作る
- [ ] 退職者・不明なアカウント・強すぎる権限を掃除の候補にする
- [ ] Vercel の SSO の機能・必要なプラン・費用を調べる
- [ ] SSO 化の案（IdP・移行手順・影響）をまとめる

## 次セッションへの引き継ぎ

起票しただけ。調査は未着手。

## 関連リンク

- [project:privileged-access](../../privileged-access/README.md): 組織の Owner は権限の頂点の地図（privilege-map.md）に反映する
- [project:idp-broker](../../idp-broker/README.md): 社内アプリを使う人の認証の入口の選定（この案件は社員が Vercel そのものに入るためのアカウントで、別物）
