# projects/ 目録

案件ごとの資料の置き場（ルールは personal-workspace の `AGENTS.md`「projects/（案件ごとの資料）」）。各案件の資料の一覧は、それぞれのフォルダの `README.md` にある。

一覧はコマンドで出せる。

- `bin/now.sh`（Claude Code では `/now`）: 下の「取り組み中」「待ち・保留」の順に、workstream の状態を出す。どちらにも載っていない進行中の workstream は「未分類」として出す
- `bin/list-workstream.sh`（`/list-workstream`）: workstream を project ごとに出す。`-a` で完了したものも出す

## 取り組み中

注力している順に並べる。1件は `- [<project-id>/workstream/<名前>.md](./<同じパス>): 一言メモ` の1行にする。状態そのものは各 workstream の `- 状態:` 行に書き、ここには写さない。

- [aws-data-protection/workstream/s3-data-protection-2.md](./aws-data-protection/workstream/s3-data-protection-2.md): WORM のガバナンスモードでの導入。共有用の資料 2 本を Notion に下書きで上げた。次はチームで話し合う
- [privileged-access/workstream/apex-privileges.md](./privileged-access/workstream/apex-privileges.md): 権限の頂点の群の把握と管理。CorpIT に 1 回目の聞き取りをした。次は止めてある循環の詳細を聞く
- [tern-ios-auth/workstream/tern-backend-api.md](./tern-ios-auth/workstream/tern-backend-api.md):
- [m2m-auth/workstream/m2m-auth.md](./m2m-auth/workstream/m2m-auth.md):
- [information-resource-inventory/workstream/aws-resource-inventory.md](./information-resource-inventory/workstream/aws-resource-inventory.md): tuscenes-prod の総ざらい
- [idp-broker/workstream/idp-auth0-role-division.md](./idp-broker/workstream/idp-auth0-role-division.md):
- [information-resource-inventory/workstream/supabase-accounts.md](./information-resource-inventory/workstream/supabase-accounts.md): Supabase。SSO は見送り、MFA の必須化と使っていない人を外す。山本さんへの依頼とヒアリングの段
- [information-resource-inventory/workstream/vercel-accounts.md](./information-resource-inventory/workstream/vercel-accounts.md): 起票した。Vercel のアカウントの棚卸しと SSO 化の検討

## 待ち・保留

ほかの人の対応を待っているもの、手を止めているもの。

- [aws-data-protection/workstream/aws-root-credentials.md](./aws-data-protection/workstream/aws-root-credentials.md): CorpIT の対応待ち
- [aws-data-protection/workstream/tuscenes-stack-cleanup.md](./aws-data-protection/workstream/tuscenes-stack-cleanup.md): 積んでいる（そのうちやる）

## 案件

- [aws-data-protection/](./aws-data-protection/README.md): S3 原本バケットの保護
- [gaming-data-collection/](./gaming-data-collection/README.md): BeamNG の MOD と資料
- [idp-broker/](./idp-broker/README.md): 社内アプリの認証の入口（IdP）の選定
- [information-resource-inventory/](./information-resource-inventory/README.md): 情報資源の棚卸し
- [m2m-auth/](./m2m-auth/README.md): 車載装置・CI 用マシンの認証
- [personal-dev-hardware/](./personal-dev-hardware/README.md): 作業用 PC など物理的な個人開発環境の管理と購買
- [privileged-access/](./privileged-access/README.md): 組織の権限の頂点の把握と管理
- [tern-ios-auth/](./tern-ios-auth/README.md): Tern iOS アプリの認証
- [what-did-i-do/](./what-did-i-do/README.md): 自分の操作の通知と、人でない主体の見張り
