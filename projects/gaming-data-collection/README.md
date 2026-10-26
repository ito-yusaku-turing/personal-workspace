# project:gaming-data-collection 目録

シミュレータ（BeamNG など）を使ったデータ収集案件の資料置き場。開発本体は gaming-data-collection リポジトリ（`/usr/app/gaming-data-collection`）にあり、ここにはリポジトリに入れていない MOD と作業資料を置く。

ファイルを追加・移動・削除したら、この目録も同じコミットで更新する（ルールは personal-workspace の `AGENTS.md`「projects/（案件ごとの資料）」）。

## beamng-randomspawn/ — BeamNG.drive MOD

- [beamng-randomspawn/](./beamng-randomspawn/README.md): **randomSpawn MOD**。リスポーンのたびに、レベルごとに事前定義した地点からランダムに1つを選んで車両を出現させる Game Engine 拡張（データ収集用）。ソース（`lua/` `scripts/`）、配布用の `randomspawn.zip`、スポーン地点の指定ガイド（`docs/spawn-points-guide.md`）を含む

## documents/ — 作業資料

- [documents/beamng-tech-slow-inference-driving.md](./documents/beamng-tech-slow-inference-driving.md): BeamNG.tech で推論の遅い自動運転モデルを動かす構想メモ（シミュレーション速度を落として tick 単位で推論ループを回せるかの下調べ。2026-06-15、構想段階）
