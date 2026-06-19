# BeamNG.tech で「推論の遅い自動運転モデル」を動かす構想メモ

- 作成日: 2026-06-15
- ステータス: 下調べ・構想段階（実装着手前）
- テーマ: 極めて推論時間の長い自動運転モデルに、BeamNG.tech 上で車両操作を行わせる

---

## 1. 背景・課題

極めて推論に時間のかかる自動運転モデル（1tick あたり数秒〜数分かかりうる）で BeamNG の車両を
操作したい。リアルタイム実行ではモデルの推論が間に合わず、シミュレーション内時間が先に進んでしまう。

**問い:** BeamNG 側に「シミュレーション速度を遅くして、tick 単位で推論ループを回す」インターフェースはあるか？

**結論:** ある。ただし正攻法は「シミュレーションを遅くする」ではなく、
**決定論的ステップ実行（Deterministic Mode + stepped simulation）でウォールクロックとシミュレーション内時間を切り離す**こと。
推論が終わるまでシミュレーションを停止させ、`step()` で必要なぶんだけ前進させる。
推論レイテンシはシミュレーション内時間に一切影響しない。

---

## 2. 仕組み（基本ループ）

1. `set_steps_per_second()` で時間分解能（1秒＝何ステップか）を決める
2. `set_deterministic()` で決定論モードにし、実時間と切り離す
3. `control.pause()` で停止
4. ループ:
   - センサ取得（観測）
   - 推論（**何時間かかってもよい**。停止中はシミュレーションが進まない）
   - 車両制御入力をセット
   - `control.step(n, wait=True)` で n ステップ前進（完了までブロック）

```python
from beamngpy import BeamNGpy, Scenario, Vehicle

bng = BeamNGpy('localhost', 25252)
bng.open()

# ... scenario / vehicle のセットアップ ...

bng.settings.set_steps_per_second(60)   # 1秒=60ステップ → 1step ≈ 16.7ms
bng.settings.set_deterministic()        # 決定論モード（要: 事前のsps指定）
bng.control.pause()

while True:
    data   = vehicle.sensors.poll()                 # 観測
    action = slow_model.infer(data)                 # ← 推論。時間無制限
    vehicle.control(steering=action.steer,
                    throttle=action.throttle,
                    brake=action.brake)
    bng.control.step(1, wait=True)                  # 1ステップ進めて完了まで待つ
```

---

## 3. 確認できた API（裏取り済み）

公式ドキュメント（documentation.beamng.com, v1.32 リファレンス）で確認。

### Control API
- `bng.control.pause()` — 一時停止リクエストを送り、停止完了までブロック
- `bng.control.resume()` — 再開
- `bng.control.step(count: int, wait: bool = True)` — 停止中の前提で `count` ステップ前進。
  - `wait=True`（デフォルト）: 該当ステップ分のシミュレーション完了までブロック
  - `wait=False`: 即座に戻る（「ステップ完了直後に実行すべきコマンドをキューする」用途）

### Settings API
- `bng.settings.set_steps_per_second(sps: int)` — 1秒を何ステップに分割するか（時間分解能）
- `bng.settings.set_deterministic(steps_per_second=None)` — 決定論モードへ。事前に sps 指定が必要
- `bng.settings.set_nondeterministic()` — 解除（sps 設定は保持）

### 低レベル（Lua / エンジン側）
- `be:setPhysicsSpeedFactor(factor)` — 1フレームあたりの物理進行量を制御
  - `-1`: `1.0/fpslimit` 秒/フレーム（フレームレートが上限に達していれば実時間相当）
  - `0`: 実経過時間ベース（非決定論）
  - `n`（正の整数）: 1レンダリングフレームあたり `n * 50ms` 進める
- `be:setPhysicsDeterministic(bool)` — 上の便利ラッパ（true=factor 1 / false=factor 0）

---

## 4. 重要な訂正・注意点

- **step の粒度は固定 0.5ms ではない。** `set_steps_per_second()` で決める値。
  例: `set_steps_per_second(2000)` → 1step=0.5ms、`set_steps_per_second(60)` → 1step≈16.7ms。
  （初回相談時に「常に2000Hz固定で1step=0.5ms」と説明したが不正確だった。訂正済み。）
- `step(wait=True)` が**ブロッキング**である点が肝。これにより推論レイテンシがシミュレーション内時間に影響しない。
- メソッド名はバージョンで異なる:
  - BeamNGpy 1.26+ は名前空間化（`bng.control.*` / `bng.settings.*`）
  - 旧版はトップレベル（`bng.step()` / `bng.pause()` / `bng.set_deterministic()`）
- 高速化（faster-than-realtime）用に `set_deterministic` の `speed_factor` 引数が CHANGELOG に出てくるが、
  v1.32 リファレンス本体には見当たらず**バージョン差の可能性**あり。今回の「遅い推論を待たせる」用途では step ベースで十分。

---

## 5. 設計上の検討事項（次フェーズ）

- **BeamNGpy のバージョン確定**: 名前空間 API（1.26+）前提でよいか。導入する版で `speed_factor` 有無を確認。
- **観測の設計**: どのセンサを使うか（カメラ / LiDAR / 車両状態 / Camera+Annotation 等）と poll コスト。
- **制御周期**: 1step ごとに推論するのか、N step まとめて進めて間引くのか（sps と step 数の設計）。
- **マルチ車両・非同期センサ**: `step()` がブロッキングなので、複数エージェント並列時はアーキテクチャ要工夫。
- **データ収集との接続**: 本リポジトリ（gaming-data-collection）のデータ収集パイプラインへの観測・行動ログの流し込み方。
- **再現性**: 決定論モードを使うため、同一入力→同一結果が前提にできる（テスト・再現の利点）。

---

## 6. 参照

- [Deterministic Mode — BeamNG Documentation](https://documentation.beamng.com/beamng_tech/deterministic_mode/)
- [BeamNGpy Reference v1.32 (Control / Settings API)](https://documentation.beamng.com/api/beamngpy/v1.32/beamngpy.html)
- [BeamNGpy CHANGELOG (set_deterministic / steps_per_second / speed_factor)](https://github.com/BeamNG/BeamNGpy/blob/master/CHANGELOG.rst)
