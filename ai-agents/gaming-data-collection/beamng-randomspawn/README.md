# randomSpawn (BeamNG.drive MOD)

リスポーン（`R` / リカバリー `Insert`）のたびに、レベルごとに事前定義した複数地点から
ランダムに 1 つを選んでプレイヤー車両を出現させる Game Engine 拡張です。

データ収集用途を想定し、リセット時は車両を停止状態でその地点へ移動させます。

## 収録スポーン地点

### West Coast USA／チャイナタウン地区（5 地点）

> マップは公式プリインストールの **West Coast USA**（レベル識別子 `west_coast_usa`）。
> 「チャイナタウン」はその中の地区／スポーン地点名であり、別途 MOD マップは不要。

| # | position (x, y, z) | rotationEuler (x, y, z) [deg] |
|---|---|---|
| 1 | -582.916, 247.545, 110.272 | 35.868, 49.172, 57.849 |
| 2 | -838.919, -503.575, 104.191 | 0.000, -0.000, -64.008 |
| 3 | -753.541, 1972.797, 80.610 | 0.671, -0.175, 117.329 |
| 4 | 432.695, -190.363, 145.351 | -0.000, -0.000, 43.377 |
| 5 | 553.703, -894.954, 153.191 | 0.099, -0.080, -18.581 |

### Italy（5 地点）

> 公式プリインストールの **Italy**（レベル識別子 `italy`）。

| # | position (x, y, z) | rotationEuler (x, y, z) [deg] |
|---|---|---|
| 1 | 1200.856, -796.306, 146.019 | 0.000, -0.000, 179.589 |
| 2 | -969.635, 953.629, 392.483 | 0.000, -0.000, 75.000 |
| 3 | 1046.068, 1103.881, 156.222 | -0.000, -0.000, 87.366 |
| 4 | 139.191, -366.489, 194.218 | 0.000, -0.000, -89.877 |
| 5 | -1805.065, 1517.674, 143.219 | -0.000, -0.000, 172.483 |

直前と同じ地点が連続しないように選択します。

## インストール（game-pc）

### 方法A：zip をそのまま導入（推奨）

1. `randomspawn.zip` を以下へコピー:
   ```
   %LOCALAPPDATA%\BeamNG.drive\<version>\mods\
   ```
2. BeamNG を起動（または `mods` 画面でリロード）し、MOD が有効になっていることを確認。

### 方法B：unpacked で開発・編集する場合

`lua/` フォルダを以下へ配置:
```
%LOCALAPPDATA%\BeamNG.drive\<version>\mods\unpacked\randomspawn\lua\...
```

## 有効化（自動）

MOD に同梱した **`scripts/randomspawn/modScript.lua`** を BeamNG の modmanager が
**mod 有効化時（ゲーム起動時 / 実行中の有効化時）に自動実行**し、その中で
`extensions.load('randomSpawn')` + `setExtensionUnloadMode('randomSpawn','manual')` を呼ぶため、
**手動操作なしで常駐ロード**される。以後 **West Coast USA**（チャイナタウン地区）や
**Italy** を Free Roam でロードした時点で自動的に有効になる（ログに
`active on level "westcoastusa" with 5 spawn points` 等が出る）。

> ⚠ GE 拡張は `lua/ge/extensions/` に置く「だけ」では自動ロードされない（オンデマンド）。
> 自動ロードには上記の **modScript** 同梱が必須（旧 README の「起動時に自動ロード」記述は誤り）。

もし何らかの理由でロードされていない場合のフォールバック（コンソール `` ` `` で一度だけ）:

```lua
extensions.load('randomSpawn')
```

## 動作確認コマンド（コンソール）

```lua
randomSpawn.status()        -- 現在レベルの認識状況・地点数・有効状態を表示
randomSpawn.test()          -- リセットを待たず即 1 回ランダム移動（地点確認用）
randomSpawn.setEnabled(false) -- 一時無効化
randomSpawn.setEnabled(true)  -- 再有効化
```

## 注意 / 調整ポイント

- **レベル判定**: 現在レベルの識別子を小文字・英数字のみに正規化して `levelSpawns` のキー（正規化後）と照合します。
  現在は `west_coast_usa`（正規化 `westcoastusa`）。別マップ対応や id 不一致時は、ログに出る
  `level="..."` を見て `randomSpawn.lua` の `levelSpawns` のキー名を実 id に合わせてください。
  （※ 旧版はキーが `chinatown` で実 id `westcoastusa` と一致せず idle だった。2026-06-16 修正）
- **向き（回転）**: `rotationEuler`(度) を BeamNG 標準 `quatFromEuler` で変換しています。
  万一向きがずれる場合は、オイラー角の順序/符号の解釈差が原因の可能性があるため、
  実機で確認のうえ調整します（特に Z=ヨーが主要因）。
- **見た目**: リセット時に「一度元のスポーン地点へ戻ってから即ランダム地点へ移動」する
  ため、一瞬の切り替わりが見える場合があります（データ収集では通常問題なし）。

## 地点の追加 / 別マップ対応 / 位置データの調整

`randomSpawn.lua` の `levelSpawns` テーブルに、レベルキーごとに
`{ p = {x,y,z}, rE = {x,y,z} }` を追記するだけです。

座標・向き（`rotationEuler`）の**捕捉方法（World Editor / コンソール）と反映手順**は
**[docs/spawn-points-guide.md](docs/spawn-points-guide.md)** にまとめています。向きの微調整・
別マップ対応はこちらを参照してください。
