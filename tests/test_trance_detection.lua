-- Shadow Trance under WoW: Forever's real secret-value rules. tests/mock_secrets.lua applies them: in combat aura
-- reads return nothing unless 17941 is flagged never-secret, UNIT_AURA payloads are secret, and the 17941 cast
-- event only arrives when a test switches it on. Covers every mode, spends from instant bolts and the countdown.
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
M.class = "WARLOCK"
local S = require("mock_secrets").install(M)
local check = M.check
local ns = M.loadAddon(".", "ShadowCount")
local SC, UI = KennyShadowCount, ns.UI
M.fire("PLAYER_LOGIN")
local fr = UI.Frame()
local T = SC.TRANCE

local function startFight() M.combat = true; M.fire("PLAYER_REGEN_DISABLED") end
local function endFight() M.combat = false; M.meter = { total = 1000, rows = { { 11661, 400 } } }
  M.fire("PLAYER_REGEN_ENABLED"); M.advance(5) end
local function tick(sec) M.advance(sec); local fn = fr:GetScript("OnUpdate"); if fn then fn(fr, sec) end end
local function head() return fr.head:GetText() or "" end
local n = 0
local function instantBolt(id) n = n + 1; M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sb-i" .. n, id or 11661) end
local function hardBolt(id) n = n + 1; local g = "sb-h" .. n
  M.fire("UNIT_SPELLCAST_START", "player", g, id or 11661); M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", g, id or 11661) end
-- a Nightfall proc: the aura lands (hidden in combat unless never-secret) and maybe the cast event fires
local function nightfall() S.procCast(T); return S.gain(T, 0, 10) end

-- 1. Strict client: gains hidden, so no Trance is shown and no countdown starts; instant bolts still count.
check(SC.mode == "none", "strict client: none mode")
startFight()
nightfall()
check(SC.fight.gained == 0 and not SC.tranceUp, "hidden Trance: not counted, not shown")
tick(1)
check(not head():find("NIGHTFALL", 1, true) and UI.TranceTimeLeft() == nil, "unknown Trance: no countdown")
hardBolt()
check(SC.fight.spent == 0, "hard-cast bolt is not a spend")
instantBolt()
check(SC.fight.spent == 1 and head() == "INSTANT SHADOW BOLT!", "instant bolt counts as a spent Trance")
check(not head():find("NIGHTFALL", 1, true) and not SC.tranceUp, "spend without a seen gain: still no countdown")
S.drop(T)
local secretGUID = {}; M.secret[secretGUID] = true
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", secretGUID, 11661)
check(SC.fight.spent == 1, "bolt with an unreadable cast GUID and no seen Trance: not counted")
M.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "x1", 11661)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "x2", T)
check(SC.fight.spent == 1 and SC.fight.gained == 0, "another player's bolts and Trances ignored")
endFight()
local lines = table.concat(UI.Lines(), "\n")
check(lines:find("Trances gained are not", 1, true) and not lines:find("Trances ·", 1, true), "none mode: honest note, no gain count shown")

-- 2. Mode B: the client sends the player's 17941 cast event.
S.castEvents = { [T] = true }
startFight()
nightfall()
check(SC.mode == "cast" and SC.fight.gained == 1 and SC.tranceUp, "cast event: Trance gained")
check(head() == "NIGHTFALL!  10s", "gain starts the 10s countdown")
tick(4)
check(head() == "NIGHTFALL!  6s", "countdown runs off our own clock while the aura is hidden")
M.fire("UNIT_AURA", "player", S.payload())
check(SC.tranceUp, "hidden aura read (secret nil) is unknown: the Trance is not cancelled")
instantBolt()
check(SC.fight.spent == 1 and not SC.tranceUp and UI.TranceTimeLeft() == nil, "spend stops and clears the countdown")
check(head() == "INSTANT SHADOW BOLT!", "spent headline replaces the countdown")
tick(7)
check(not head():find("NIGHTFALL", 1, true), "no countdown comes back after the spend")
S.drop(T)
nightfall()
check(SC.fight.gained == 2 and SC.tranceUp, "second Trance gained")
tick(9.5)
check(SC.tranceUp and head() == "NIGHTFALL!  1s", "countdown near the end")
tick(1)
check(not SC.tranceUp and UI.TranceTimeLeft() == nil, "Trance expires after 10s")
hardBolt()
check(SC.fight.spent == 1, "hard-cast bolt after the expiry: not a spend")
S.drop(T)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x3", secretGUID)
check(SC.fight.gained == 2, "secret spell ID ignored")
endFight()
check(KennyShadowCountDB.castSeen == true, "remembered that this client sends the Trance cast")

-- 3. Mode A: 17941 flagged never-secret, read from its aura in combat.
S.castEvents = {}
S.never = { [T] = true }
startFight()
check(SC.mode == "aura", "never-secret Trance: aura mode")
local a = S.gain(T, 0, 10)
check(SC.fight.gained == 1 and SC.tranceUp and head() == "NIGHTFALL!  10s", "aura gain starts the countdown")
tick(3)
S.update(T, nil, M.clock + 10)
check(SC.fight.gained == 2 and head() == "NIGHTFALL!  10s", "re-proc while up (later expiry): a gain, countdown restarts")
S.drop(T)
check(not SC.tranceUp, "aura gone (readable): Trance down")
S.castEvents = { [T] = true }
M.advance(1); nightfall()
check(SC.fight.gained == 3, "cast event and aura for one proc: one gain")
instantBolt(); S.drop(T)
check(SC.fight.spent == 1 and not SC.tranceUp, "aura mode: instant bolt spends")
endFight()
local _ = a

-- 4. /shc debug and a client without the APIs.
M.prints = {}
M.slash("/shc", "debug")
local out = table.concat(M.prints, "\n")
check(out:find("detection mode: aura", 1, true) and out:find("Shadow Trance 17941: secrecy 0", 1, true), "debug: mode and secrecy")
check(out:find("Trance cast events seen", 1, true) and out:find("secret restrictions: true", 1, true), "debug: casts seen and restrictions")
local keepS, keepU = C_Secrets, C_UnitAuras
C_Secrets, C_UnitAuras = nil, nil
check(pcall(SC.EvaluateMode) and pcall(SC.DetectionLines) and SC.mode == "cast", "missing APIs: no error, cast mode from memory")
startFight(); M.fire("UNIT_AURA", "player", {}); instantBolt(); endFight()
C_Secrets, C_UnitAuras = keepS, keepU
check(#ns.Core.errors == 0, "no Lua errors recorded")
M.done("ShadowCount Trance detection")
