package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
M.class, M.className = "WARLOCK", "Warlock"
M.trees = { { 355, "Affliction", 31 }, { 354, "Demonology", 0 }, { 593, "Destruction", 20 } }
local ns = M.loadAddon(".", "ShadowCount")
local SC, UI = KennyShadowCount, ns.UI
local check = M.check
M.fire("PLAYER_LOGIN")
check(KennyShadowCountDB and KennyShadowCountDB.session, "saved variables set up")
check(UI.Frame() ~= nil and UI.Frame():IsShown(), "window built and shown for a Warlock")
local pt = UI.Frame().points[#UI.Frame().points]
check(pt[1] == "CENTER" and pt[4] == 0 and pt[5] == -210, "default spot CENTER 0,-210")
check(SC.theme.tree == "Affliction" and SC.theme.sound == 568263, "Affliction theme, Shadow Trance alert sound")
M.trees = { { 355, "Affliction", 5 }, { 354, "Demonology", 5 }, { 593, "Destruction", 0 } }
SC.UpdateTheme()
check(SC.theme.tree == nil, "tie: class theme")
for _, sl in ipairs(ns.THEME.order) do check(ns.THEME.trees[sl], "tree " .. sl .. " has an entry") end

-- Trance gained: cast + aura for one proc count once, NIGHTFALL! shows and the sound plays
M.fire("PLAYER_REGEN_DISABLED"); M.combat = true
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "t1", 17941)
M.auras[17941] = { spellId = 17941 }
M.fire("UNIT_AURA", "player", { addedAuras = { { spellId = 17941 } } })
check(SC.fight.gained == 1 and SC.tranceUp, "one Trance, cast and aura deduped")
check(UI.Frame().head:GetText() == "NIGHTFALL!  10s", "NIGHTFALL! with a 10s countdown while the Trance is up")
check(#M.sounds == 1 and M.sounds[1][1] == 568263, "dark Trance sound")
-- a hard-cast Shadow Bolt that started before the Trance does not spend it
M.fire("UNIT_SPELLCAST_START", "player", "sb-hard", 11661)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sb-hard", 11661)
check(SC.fight.spent == 0 and SC.fight.bolts == 1 and SC.tranceUp, "hard-cast bolt keeps the Trance")
-- instant bolt: spent
M.advance(1)
UI.Frame():GetScript("OnUpdate")(UI.Frame(), 1)
check(UI.Frame().head:GetText() == "NIGHTFALL!  9s", "countdown ticks down")
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sb-1", 11661)
M.auras[17941] = nil; M.fire("UNIT_AURA", "player", {})
check(SC.fight.spent == 1 and not SC.tranceUp and SC.fight.bolts == 2, "instant bolt spends the Trance")
check(UI.Frame().head:GetText() == "INSTANT SHADOW BOLT!", "spent headline")
-- aura disappears just before the bolt event: still counted as spent
M.advance(2)
M.auras[17941] = { spellId = 17941 }; M.fire("UNIT_AURA", "player", {})
check(SC.fight.gained == 2, "aura-only gain counts")
M.auras[17941] = nil; M.fire("UNIT_AURA", "player", {})
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sb-2", 25307)
check(SC.fight.spent == 2, "bolt right after the aura ends still counts as spent")
-- a Trance that times out is not spent; a later bolt is a normal bolt
M.advance(2)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "t3", 17941)
M.advance(11)
check(not SC.tranceUp and SC.fight.gained == 3, "Trance ends after 10 seconds when the aura can't be read")
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sb-3", 686)
check(SC.fight.spent == 2 and SC.fight.bolts == 4, "bolt with no Trance is not instant")
-- other units, other spells and secret IDs ignored
local secretID = {}; M.secret[secretID] = true
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", secretID)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "x2", 17941)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x3", 172) -- Corruption
check(SC.fight.gained == 3 and SC.fight.bolts == 4, "other units, other spells and secret IDs ignored")
-- secret aura in combat: no guesses
local secretAura = {}; M.secret[secretAura] = true
M.auras[17941] = secretAura
M.fire("UNIT_AURA", "player", secretAura)
check(SC.fight.gained == 3, "secret aura info skipped quietly")
M.auras[17941] = nil
local secretTotal = setmetatable({}, { __tostring = function() return "SECRET" end }); M.secret[secretTotal] = true
M.meter = { total = secretTotal, rows = { { 11661, secretTotal } } }
UI.RenderLive()
check(true, "live render with secret values")
check(UI.Frame().reset.shown == false, "Reset button hidden in combat")

-- fight ends: Shadow Bolt rows (all ranks) give damage, share and average per bolt
M.combat = false
M.meter = { total = 10000, rows = { { 11661, 3000 }, { 25307, 1000 }, { 686, 200 }, { 172, 5800 } } }
M.fire("PLAYER_REGEN_ENABLED"); M.advance(1)
local f = SC.lastFight
check(f and f.sb == 4200 and math.abs(f.share - 0.42) < 1e-9 and f.avg == 1050, "fight: Shadow Bolt damage, share, avg per bolt")
check(f.gained == 3 and f.spent == 2, "fight: Trances gained vs spent")
local s = SC.SessionStats()
check(s.gained == 3 and s.spent == 2 and s.sb == 4200 and s.total == 10000 and s.bestAvg == 1050, "session totals")
check(UI.Frame().reset.shown == true, "Reset back after combat")
-- no Shadow Bolt line: counting procs only
M.fire("PLAYER_REGEN_DISABLED"); M.combat = true; M.advance(5)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sb-9", 11661)
M.combat = false; M.meter = { total = 500, rows = { { 172, 500 } } }
M.fire("PLAYER_REGEN_ENABLED"); M.advance(1)
check(SC.lastFight.sb == nil and KennyShadowCountDB.meterSplits == false, "no Shadow Bolt line: no damage made up")
check(table.concat(UI.Lines(), "\n"):find("counting procs only", 1, true), "window says counting procs only")
-- secret meter after combat: gives up without numbers
M.fire("PLAYER_REGEN_DISABLED"); M.combat = true; M.advance(5)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "t9", 17941)
M.combat = false; M.meter = { total = secretTotal, rows = {} }
M.fire("PLAYER_REGEN_ENABLED"); M.advance(10)
check(SC.lastFight.total == nil and SC.lastFight.gained == 1, "secret meter: counts only")

-- record sound on a better average
SC.ResetSession(); SC.Settings().sound = "record"; M.sounds = {}
for i, dmg in ipairs({ 2000, 3000 }) do
  M.fire("PLAYER_REGEN_DISABLED"); M.combat = true; M.advance(12)
  M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "ra" .. i, 11661); M.advance(1)
  M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "rb" .. i, 11661)
  M.combat = false; M.meter = { total = 10000, rows = { { 11661, dmg } } }
  M.fire("PLAYER_REGEN_ENABLED"); M.advance(1)
end
check(#M.sounds == 1 and SC.SessionStats().bestAvg == 1500, "record sound only when a best is beaten")
SC.Settings().sound = "every"

-- slash commands (both names)
M.slash("/shadowcount", "reset")
check(SC.SessionStats().gained == 0, "reset")
M.slash("/shc", "size 9999 1")
check(SC.Settings().width == UI.MAX_W and SC.Settings().height == UI.MIN_H, "size is clamped")
M.slash("/shc", "scale 0.1")
check(SC.Settings().scale == 0.5, "scale is clamped")
M.sounds = {}
M.slash("/shc", "soundfile curse")
check(SC.Settings().soundFile == "curse" and M.sounds[1][1] == 569079, "sound file preview")
M.slash("/shc", "sound bogus")
check(SC.Settings().sound == "every", "unknown sound mode refused")
M.prints = {}
M.slash("/shc", "meter")
check(M.printed("Shadow Bolt") or M.printed("your damage"), "meter lists lines")
M.combat = true; M.prints = {}
M.slash("/shc", "test")
check(M.printed("not in combat"), "no test in combat")
M.combat = false
M.slash("/shc", "lock")
check(SC.Settings().locked, "lock")
M.slash("/shc", "resetpos")
check(KennyShadowCountDB.point == nil, "resetpos")
M.class = "MAGE"; M.prints = {}
M.slash("/shc", "show")
check(not UI.Frame():IsShown() and M.printed("only shows on a Warlock"), "hidden for non-Warlocks")
M.class = "WARLOCK"; M.slash("/shc", "show")
check(UI.Frame():IsShown(), "show")
-- padlock: the lock slash commands and the padlock button agree, and the resize grip hides while locked
M.slash("/shc", "lock")
check(SC.Settings().locked == true and UI.Frame().grip:IsShown() == false, "locked: grip hidden")
UI.Frame().lock:GetScript("OnClick")(UI.Frame().lock)
check(SC.Settings().locked == false and UI.Frame().grip:IsShown(), "padlock click unlocks")
M.done("ShadowCount")
