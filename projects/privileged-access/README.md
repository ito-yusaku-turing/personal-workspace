# project:privileged-access 目録

組織の権限の頂点（GitHub の組織の owner・identity の admin・GCP・Okta・Google Workspace の管理者、AWS の管理アカウントなど）を把握し、管理する案件。関わるリポジトリは identity（`/usr/app/identity`）と cdk-apps（`/usr/app/cdk-apps`）。

2026-11-02 に、project:aws-data-protection の S3 の案件から分けて作った。ファイルを追加・移動・削除したら、この目録も同じコミットで更新する（ルールは personal-workspace の `AGENTS.md`「projects/（案件ごとの資料）」）。

## workstream/ — 進行中の作業記録

- [workstream/apex-privileges.md](./workstream/apex-privileges.md): **権限の頂点の把握と管理**。互いに届き合う頂点の群の把握、狭め方、使われたときの通知、頂点にいる人の要件
  - [workstream/apex-privileges/privilege-map.md](./workstream/apex-privileges/privilege-map.md): **権限の地図**（2026-11-02）。要承認操作と名簿に届く経路（P1〜P14）、見えない層、ヒアリング項目（I1〜I18）、構造上の上位権限者の台帳（U1〜U11）、上位の構造（頂点の群）とその評価、あるべき姿（頂点と、ほどく辺 E1〜E5）、人ごとの一覧
  - [workstream/apex-privileges/apex-cycle.html](./workstream/apex-privileges/apex-cycle.html): **頂点の輪の説明用の図**（2026-11-02）。現状の輪の中心・下に伸びる枝・あるべき姿の案を mermaid で描いた 1 枚のページ。公開先は <https://claude.ai/artifact/Gtzn6zWuQXYW4KC2zpuMMo>
  - [workstream/apex-privileges/corpit-hearing.md](./workstream/apex-privileges/corpit-hearing.md): **CorpIT への聞き取りのシート**（2026-11-02）。ヒアリング項目を聞く順に並べ直し、答えを書く欄を付けたもの
