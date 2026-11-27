-- SavedVariables from Shadow Count 1.0.x (schema 1) load into 1.1.0 (schema 2) with everything kept.
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
M.class = "WARLOCK"
KennyShadowCountDB = { schema = 1, point = { "TOPLEFT", 40, -60 }, castSeen = true, meterSplits = true,
  settings = { width = 300, height = 200, locked = true, sound = "record", soundFile = "curse", scale = 1.2,
    fade = "yes", compact = 1 }, -- hand-edited junk where the new switches go
  session = { gained = 7, spent = 5, bolts = 20, fights = 3, total = 90000, sb = 30000, measuredBolts = 20, bestAvg = 1600, since = 1 } }
local ns = M.loadAddon(".", "ShadowCount")
local SC, UI = KennyShadowCount, ns.UI
local check = M.check
M.fire("PLAYER_LOGIN")
local db, S, fr = KennyShadowCountDB, SC.Settings(), UI.Frame()
check(db.schema == 2, "1.0.x schema 1 -> 2")
check(S.width == 300 and S.height == 200 and S.locked == true and S.sound == "record" and S.soundFile == "curse" and S.scale == 1.2,
  "1.0.x settings kept")
check(db.point[1] == "TOPLEFT" and db.point[2] == 40 and db.castSeen == true, "spot and Trance cast flag kept")
check(db.session.gained == 7 and db.session.bestAvg == 1600, "session kept")
check(S.fade == true and S.compact == false and S.clickThrough == false, "new switches start at their defaults")
check(db.settings.fade == nil and db.settings.compact == nil, "junk values for the new switches dropped")
check(fr.width == 300 and fr.height == 200 and fr:IsMouseEnabled(), "full layout at the saved size; locked but clickable")
check(math.abs(fr:GetAlpha() - 0.35) < 1e-6, "idle fade on after the upgrade")
-- the migration on its own
local m = SC.migrations[2]
local fresh = m({ schema = 1 })
check(type(fresh.settings) == "table" and next(fresh.settings) == nil, "no settings table: an empty one")
local kept = m({ schema = 1, settings = { fade = false, clickThrough = true, compact = true, shown = "x" } })
check(kept.settings.fade == false and kept.settings.clickThrough == true and kept.settings.compact == true and kept.settings.shown == nil,
  "valid true/false values kept, junk dropped")
M.done("ShadowCount migration")
