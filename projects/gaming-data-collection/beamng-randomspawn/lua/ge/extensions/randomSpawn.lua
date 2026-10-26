-- randomSpawn.lua
-- リスポーン（R / リカバリー）のたびに、レベルごとに定義した複数地点から
-- ランダムに 1 つを選んでプレイヤー車両を出現させる GE 拡張。
--
-- 配置（選定）は本ファイルの levelSpawns に座標+オイラー角で定義する。
-- データ収集用途を想定し、リセット時は車両を停止状態でその地点へ瞬間移動させる。

local M = {}

-- =====================================================================
-- リスポーン地点定義
--   p  = {x, y, z}            位置
--   rE = {x, y, z} (degrees)  オイラー角（World Editor の rotationEuler 相当・度）
--   キーはレベル識別子（小文字・英数字のみに正規化して照合する）
-- =====================================================================
-- 注意: キーは「マップ表示名」ではなく BeamNG の**レベル識別子**（小文字英数字に正規化して照合）。
-- チャイナタウンは公式マップ West Coast USA 内の地区で、レベル識別子は `west_coast_usa`。
-- （旧版はキーを `chinatown` にしていたため実 id `westcoastusa` と一致せず idle だった。）
local levelSpawns = {
  west_coast_usa = {  -- West Coast USA／チャイナタウン地区の 5 地点
    { p = { -582.916,  247.545,  110.272 }, rE = { 35.868,  49.172,  57.849 } },
    { p = { -838.919, -503.575,  104.191 }, rE = {  0.000,  -0.000, -64.008 } },
    { p = { -753.541, 1972.797,   80.610 }, rE = {  0.671,  -0.175, 117.329 } },
    { p = {  432.695, -190.363,  145.351 }, rE = { -0.000,  -0.000,  43.377 } },
    { p = {  553.703, -894.954,  153.191 }, rE = {  0.099,  -0.080, -18.581 } },
  },
  italy = {  -- Italy の 5 地点
    { p = {  1200.856, -796.306, 146.019 }, rE = { 0.000, -0.000, 179.589 } },
    { p = {  -969.635,  953.629, 392.483 }, rE = { 0.000, -0.000,  75.000 } },
    { p = {  1046.068, 1103.881, 156.222 }, rE = { -0.000, -0.000, 87.366 } },
    { p = {   139.191, -366.489, 194.218 }, rE = { 0.000, -0.000, -89.877 } },
    { p = { -1805.065, 1517.674, 143.219 }, rE = { -0.000, -0.000, 172.483 } },
  },
}

-- =====================================================================
-- 内部状態
-- =====================================================================
local enabled     = true
-- 瞬間移動 (setPositionRotation) はそれ自体が onVehicleResetted を**非同期**で再発火させる。
-- 同期 bool ガードでは間に合わず無限ワープするため、テレポート後 cooldownSec の間は
-- reset を無視する実時間クールダウン方式にする（2026-06-16 修正）。
local cooldown    = 0       -- 残り無視時間（秒）。>0 の間は reset を無視
local cooldownSec = 0.5     -- 自己誘発リセットを吸収する窓
local lastIndex   = 0       -- 直前に使った地点（連続重複を避ける）

-- =====================================================================
-- ユーティリティ
-- =====================================================================

-- レベル識別子を正規化（小文字・英数字のみ）
local function normalize(s)
  if not s then return nil end
  return (tostring(s):lower():gsub("[^%a%d]", ""))
end

-- 現在のレベル識別子を取得
local function currentLevelKey()
  local id
  if getCurrentLevelIdentifier then
    local ok, v = pcall(getCurrentLevelIdentifier)
    if ok then id = v end
  end
  if (not id or id == "") and getMissionFilename then
    local ok, fn = pcall(getMissionFilename)
    if ok and fn then
      id = fn:match("/levels/([^/]+)/")
    end
  end
  return normalize(id)
end

-- オイラー角(度) -> クォータニオン(x,y,z,w)
-- BeamNG 標準 quatFromEuler が使えればそれを使う（エンジンと同一の解釈）。
-- 使えない環境向けに XYZ 順の手動変換をフォールバックとして用意。
local function eulerDegToQuat(ex, ey, ez)
  local rx, ry, rz = math.rad(ex), math.rad(ey), math.rad(ez)
  if quatFromEuler then
    local q = quatFromEuler(rx, ry, rz)
    if q then return q.x, q.y, q.z, q.w end
  end
  local cx, sx = math.cos(rx * 0.5), math.sin(rx * 0.5)
  local cy, sy = math.cos(ry * 0.5), math.sin(ry * 0.5)
  local cz, sz = math.cos(rz * 0.5), math.sin(rz * 0.5)
  local qx = sx * cy * cz - cx * sy * sz
  local qy = cx * sy * cz + sx * cy * sz
  local qz = cx * cy * sz - sx * sy * cz
  local qw = cx * cy * cz + sx * sy * sz
  return qx, qy, qz, qw
end

-- 現在レベルの地点リストを取得（無ければ nil）
local function pointsForCurrentLevel()
  local key = currentLevelKey()
  if not key then return nil, nil end
  for k, list in pairs(levelSpawns) do
    if normalize(k) == key then return list, key end
  end
  return nil, key
end

-- 連続重複を避けたランダム選択
local function pickIndex(n)
  if n <= 1 then return 1 end
  local idx = math.random(n)
  if idx == lastIndex then
    idx = (idx % n) + 1
  end
  lastIndex = idx
  return idx
end

-- =====================================================================
-- 本体
-- =====================================================================
local function teleportToRandom(vid)
  if not enabled then return end
  local list = pointsForCurrentLevel()
  if not list or #list == 0 then return end

  local veh = (vid and be:getObjectByID(vid)) or be:getPlayerVehicle(0)
  if not veh then return end

  local s  = list[pickIndex(#list)]
  local p  = s.p
  local qx, qy, qz, qw = eulerDegToQuat(s.rE[1], s.rE[2], s.rE[3])

  veh:setPositionRotation(p[1], p[2], p[3], qx, qy, qz, qw)
  cooldown = cooldownSec   -- この移動が誘発する reset 通知を無視する
end

-- =====================================================================
-- エンジンフック
-- =====================================================================

-- フレーム更新：cooldown を実時間で減衰（自己誘発リセットの吸収窓）
function M.onUpdate(dtReal, dtSim, dtRaw)
  if cooldown > 0 then
    cooldown = cooldown - (dtReal or dtSim or 0)
    if cooldown < 0 then cooldown = 0 end
  end
end

-- 車両リセット（R / リカバリー）直後に発火
function M.onVehicleResetted(vid)
  if not enabled or cooldown > 0 then return end  -- cooldown 中は自己誘発リセットなので無視
  local pv = be:getPlayerVehicle(0)
  if not pv or pv:getID() ~= vid then return end  -- プレイヤー車両のみ対象
  teleportToRandom(vid)
end

-- レベル読み込み完了時：状態リセット＆対象レベルか通知
function M.onClientPostStartMission()
  lastIndex = 0
  local list, key = pointsForCurrentLevel()
  if list then
    log('I', 'randomSpawn', ('active on level "%s" with %d spawn points'):format(tostring(key), #list))
  else
    log('I', 'randomSpawn', ('no spawn points defined for level "%s" (idle)'):format(tostring(key)))
  end
end

-- =====================================================================
-- コンソール用 公開関数
-- =====================================================================
function M.setEnabled(v) enabled = (v ~= false) end
function M.isEnabled()   return enabled end

-- 今のレベルで即テスト（リセットを待たずに 1 回ランダム移動）
function M.test() teleportToRandom(nil) end

-- 現在レベルの認識状況を表示
function M.status()
  local list, key = pointsForCurrentLevel()
  log('I', 'randomSpawn', ('level="%s" points=%d enabled=%s'):format(
    tostring(key), list and #list or 0, tostring(enabled)))
end

return M
