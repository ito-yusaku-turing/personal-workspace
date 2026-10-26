-- modScript.lua
-- BeamNG の modmanager が mod 有効化時（ゲーム起動時の initDB / 実行中の activateMod）に
-- 自動実行する。ここで GE 拡張 randomSpawn を読み込み、常駐（manual unload）させる。
-- これにより Free Roam（レベル）ロードごとに randomSpawn の onClientPostStartMission /
-- onVehicleResetted が自動で効く（手動の extensions.load('randomSpawn') は不要になる）。
--
-- 注: initDB 経路では extensions.load がラップされ setExtensionUnloadMode(...,'manual') を
-- 自動付与するが、activateMod 経路ではラップされないため、両経路で確実に常駐させるよう
-- ここで明示的に両方を呼ぶ（idempotent）。
extensions.load('randomSpawn')
setExtensionUnloadMode('randomSpawn', 'manual')
log('I', 'randomSpawn.modScript', 'randomSpawn auto-loaded via modScript (manual unload mode)')
