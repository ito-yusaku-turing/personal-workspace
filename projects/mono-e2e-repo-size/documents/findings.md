# mono-e2e のリポジトリの肥大: 分かったことと結論

2026-11-04〜11-11 の調査の結論。経緯と根拠の詳細は [../workstream/done/mono-e2e-repo-size.md](../workstream/done/mono-e2e-repo-size.md) にある。**2026-11-11 に、本件は岩政さん（MLOps）が引き取った。** こちらでは閉じた。

## 重さの原因

- clone・fetch が重い主な原因は、**main にマージされない作業ブランチに積まれた画像・PDF**（`shuhei_goda/ego-mask-sam2-boundary-parts` の 1,317MB など）。clone・fetch は既定で全ブランチを取るので、main の外でも全員に届く。
- main の履歴全体は圧縮後 338MB。fullcombo の workspace（展開後 574MB、うち uv.lock と `.py` で 365MB）は、圧縮後は 66MB で、clone の重さへの寄与は小さい。

## ブランチを消せば軽くなるか

- 新しく clone する人と、しばらく fetch していない人には、消した時点から効く（どの ref からもたどれないオブジェクトは送られない）。手元の見積もりで、全ブランチの 2,245MB → ego のブランチを消して 863MB → 重い 4 本を消して 580MB。
- すでに取った人の手元は減らない（参照を消して gc する）。PR の参照（`refs/pull/N/head`）は GitHub に残るが、既定の clone は取らない。

## なぜこうなったか（Miwa さんへのヒアリングを含む）

- 本質のデマンドは 2 つ。
  - **D1. クラスター間でファイルを共有したい**（大きさ・種類は様々）。
  - **D2. 結果ファイルをメンバーに共有したい**（ファイルに URL があり、見るには認証が要る）。
- **いまは Git（GitHub）が D1・D2 を一番よく満たすので、mono-e2e に commit している**（Miwa さん）。
- クラスターの操作はコーディングエージェントがしている。新しい仕組みやルールは、エージェントが対応できれば普及の障壁にならない。
- workspace のルール（commit の関所、重複の lint、uv.lock の除外、skill の注意）は main しか見ておらず、マージしないブランチは止まらない。
- workspace の肥大の大半は、実験ごとに `main.py`・uv.lock・データを写す設計（ADR 0002）から来ている。その前提の再現性は 2026-11-09 にやめている。

## 解決の方向への所見（岩政さんに渡す材料）

- 岩政さんの設計（[各クラスターでデータ共有をするようにする](https://app.notion.com/p/turing-motors/413a93b3e6f2809088c5fcf78b388b53)）は、テキストだけ・64MB までなので D1 の一部にしか応えず、D2 は範囲外。daemon で先に配る形は、操作するのがエージェントなら必要性が弱い。
- 代わりの候補: 使うときに取りに行く形、既存の `jadd backup` を広げる形、ハッシュの一覧だけを Git に置く形、**workspace を別リポジトリにして Git LFS を付ける形**（D1・D2 によく合う。mono-e2e とのつなぎ方、LFS の費用と消しにくさ、車載カメラの画像を GitHub に置いてよいかを確かめる必要がある）。
- 重い作業ブランチ（[mono-e2e#6875](https://github.com/turingmotors/mono-e2e/pull/6875)、[mono-e2e#7061](https://github.com/turingmotors/mono-e2e/pull/7061)、[mono-e2e#6700](https://github.com/turingmotors/mono-e2e/pull/6700)、`feat/fullcombo-back`）は、2026-11-11 時点で残っている。消すかどうかは担当の方と岩政さんに任せた。
