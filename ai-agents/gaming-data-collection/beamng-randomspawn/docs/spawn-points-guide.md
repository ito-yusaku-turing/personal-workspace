# スポーン地点データの指定ガイド（randomSpawn）

`randomSpawn.lua` の `levelSpawns` に書くスポーン地点（位置＋向き）の**意味・捕捉方法・反映手順**をまとめる。
位置・向きの微調整はこの手順で行う。

---

## 1. データ形式

`lua/ge/extensions/randomSpawn.lua` の `levelSpawns` テーブル：

```lua
local levelSpawns = {
  west_coast_usa = {                                  -- ① レベルキー
    { p = { -584.7, 413.6, 109.5 }, rE = { -3.6, -4.1, -64.6 } },  -- 1 地点
    ...
  },
}
```

### ① レベルキー
- BeamNG の**レベル識別子**（`/levels/<id>/` の `<id>`）。
- 照合は **小文字・英数字のみに正規化**して行う（`normalize()`）。例: `west_coast_usa` も `westcoastusa` も同じ扱い。
- 現在のチャイナタウンは公式マップ **West Coast USA** 内の地区なのでキーは `west_coast_usa`。
- 別マップを足すときは、そのマップをロードしてコンソールで `getCurrentLevelIdentifier()` を実行し、出た id をキーにする（または `randomSpawn.status()` のログ `level="..."` を見る）。

### ② `p`（position）= ワールド座標 `{ x, y, z }`（メートル）
- `x, y` が水平、`z` が高さ。
- `z` は**車両の基準点の高さ**。地面ぴったりより**少し高め**にしておくと、出現時に地面へ落として接地する（埋まり防止）。数 cm〜数十 cm 上げる程度でよい。

### ③ `rE`（rotationEuler）= オイラー角 `{ x, y, z }`（**度**）
- **World Editor の Transform に出る `rotationEuler` と同じ値・同じ解釈**。
- 各軸の意味（BeamNG 標準）：
  - `x` = ピッチ（前後の傾き）
  - `y` = ロール（左右の傾き）
  - `z` = **ヨー（向き＝水平回転）** ← 道路に対する向きはこれが主役
- 平地なら `x, y` はほぼ 0 でよく、`z`(ヨー) だけ合わせれば向きが決まる。坂・バンクのある場所は `x, y` も実測値を入れる。
- 変換はコード内で BeamNG 標準 `quatFromEuler` を使用（エンジンと同一解釈なので、**下記 World Editor の値をそのまま転記すれば一致**する）。

---

## 2. 値の捕捉方法

### 方法A（推奨）：World Editor で読む — 位置も向きも正確

1. 目的の場所・向きに車両を止める（リカバリーや自由移動で調整）。
2. **F11** で World Editor を開く。
3. シーンツリーでプレイヤー車両を選択（または `Scene Tree` から該当オブジェクト）。
4. **Inspector の Transform** を見る：
   - **Position** → そのまま `p = { x, y, z }`
   - **rotationEuler** → そのまま `rE = { x, y, z }`（度）
5. 値を `levelSpawns` の該当行に転記。**editor の rotationEuler は `quatFromEuler` と同じ規約**なので符号変換は不要。

> 💡 向きだけ直したいときは、車を「道路に正しく向けた状態」にしてから Transform の rotationEuler を読み、`rE` を差し替えるのが最短。

### 方法B（簡易）：コンソールで現在地を出力 — 位置＋ヨー概算

平地で素早く拾いたいとき。コンソール（`` ` `` / `~`）で：

```lua
local v = be:getPlayerVehicle(0)
local p = v:getPosition()
local q = v:getRotation()
local yaw = math.deg(math.atan2(2*(q.w*q.z + q.x*q.y), 1 - 2*(q.y*q.y + q.z*q.z)))
print(string.format("{ p = { %.1f, %.1f, %.1f }, rE = { 0.0, 0.0, %.1f } },", p.x, p.y, p.z, yaw))
```

- 出力行をそのまま `levelSpawns` に貼れる形にしてある。
- ⚠ これは**平地前提（ピッチ/ロール=0）かつヨーは概算**。坂や、出現直後に向きがズレる場合は **方法A（World Editor の rotationEuler 実測）**を使う（符号・軸順の解釈差を避けられる）。

---

## 3. 反映手順

1. `lua/ge/extensions/randomSpawn.lua` の `levelSpawns` を編集。
2. zip を作り直す（`lua/` と `scripts/` を同梱）：
   ```bash
   cd beamng-randomspawn
   rm -f randomspawn.zip
   python3 - <<'PY'
   import zipfile, os
   with zipfile.ZipFile("randomspawn.zip","w",zipfile.ZIP_DEFLATED) as z:
       for top in ("lua","scripts"):
           for r,_,fs in os.walk(top):
               for f in fs: z.write(os.path.join(r,f), os.path.join(r,f))
   PY
   ```
3. 実機の mods へ配置（game-pc / WSL 経由）：
   ```
   %LOCALAPPDATA%\BeamNG\BeamNG.tech\current\mods\randomspawn.zip
   ```
   （WSL から: `/mnt/c/Users/steam01/AppData/Local/BeamNG/BeamNG.tech/current/mods/`）
4. 反映：**BeamNG を再起動**（確実）。または起動中なら コンソールで
   `extensions.reload('randomSpawn')` → レベルを再ロード。
   ※ ディスクの zip を差し替えても、起動中はマウント済みの旧内容が残ることがあるため、確実なのは再起動。
5. 確認：コンソールで `randomSpawn.status()` → `level="westcoastusa" points=N enabled=true`。
   `randomSpawn.test()` でリセットを待たず即 1 回ランダム移動して各地点を目視チェック。

---

## 4. 動作確認コマンド（再掲）

```lua
randomSpawn.status()           -- 認識状況・地点数・有効状態
randomSpawn.test()             -- 即 1 回ランダム移動（地点・向き確認）
randomSpawn.setEnabled(false)  -- 一時無効化（暴走時の停止にも使える）
randomSpawn.setEnabled(true)   -- 再有効化
```

---

## 5. よくある調整

| 症状 | 対処 |
|---|---|
| 向きが道路に対しておかしい | `rE` の **z（ヨー）** を方法A で実測し直す。坂なら `x,y` も実測 |
| 出現時に少し埋まる／弾む | `p` の **z** を少し上げる（数十 cm） |
| 別マップでも使いたい | そのマップの id をキーに `levelSpawns` へ追記（§1①） |
| 発火しない | レベル id とキーの**正規化後**が一致しているか `status()` で確認 |
