-- Shadow Count window: Reset button in combat (incl. /reload in combat) and the Trance countdown failing quietly.
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
M.class = "WARLOCK"
M.combat = true -- loaded mid-fight, as after a /reload in combat: no PLAYER_REGEN_DISABLED will come
local ns = M.loadAddon(".", "ShadowCount")
local SC, UI = KennyShadowCount, ns.UI
local check = M.check
M.fire("PLAYER_LOGIN")
local fr = UI.Frame()
check(fr.reset:IsShown() == false, "/reload in combat: Reset starts hidden")
M.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(5)
check(fr.reset:IsShown() == true, "combat ends: Reset shown")
M.fire("PLAYER_REGEN_DISABLED"); M.combat = true
check(fr.reset:IsShown() == false, "combat starts: Reset hidden")
M.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(5)
check(fr.reset:IsShown() == true, "combat ends again: Reset shown")

local function errors() return #ns.Core.errors end
local base = errors()
local function tick(sec) M.advance(sec); fr:GetScript("OnUpdate")(fr, sec) end
local function gain(aura)
  M.auras[SC.TRANCE] = aura
  M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "t" .. M.clock, SC.TRANCE)
end
local function clear() M.auras[SC.TRANCE] = nil; M.fire("UNIT_AURA", "player", {}); M.advance(1) end

-- readable expirationTime: the countdown follows the aura (here 6s left, not our own 10s)
gain({ spellId = SC.TRANCE, expirationTime = M.clock + 6 })
check(fr.head:GetText() == "NIGHTFALL!  6s", "countdown from the aura's expirationTime")
tick(1)
check(fr.head:GetText() == "NIGHTFALL!  5s", "aura countdown ticks")
clear()

-- nil, 0, secret, NaN and non-number expirationTime: fall back to our own 10s clock from the gain
local secret = {}; M.secret[secret] = true
for name, exp in pairs({ ["nil"] = false, zero = 0, secret = secret, nan = 0 / 0, text = "soon" }) do
  gain({ spellId = SC.TRANCE, expirationTime = exp or nil })
  check(fr.head:GetText() == "NIGHTFALL!  10s", "expirationTime " .. name .. ": own 10s countdown")
  tick(2)
  check(fr.head:GetText() == "NIGHTFALL!  8s", "expirationTime " .. name .. ": still counting")
  clear()
end
-- the aura table itself throws when read, or is a secret value
gain(setmetatable({}, { __index = function() error("aura data hidden") end }))
tick(1)
check(fr.head:GetText() == "NIGHTFALL!  9s", "aura that throws on read: own countdown, no error")
clear()
local secretAura = {}; M.secret[secretAura] = true
gain(secretAura); tick(1)
check(fr.head:GetText() == "NIGHTFALL!  9s", "secret aura: own countdown")
clear()
-- the aura API itself throws
local api = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = function() error("no aura API in combat") end
UI.OnTrance(true); SC.tranceUp = true; tick(1)
check(fr.head:GetText() == "NIGHTFALL!  9s", "aura API that throws: own countdown")
SC.tranceUp = false; UI.OnTrance(false)
C_UnitAuras.GetPlayerAuraBySpellID = api
-- nothing readable at all (aura API missing, clock throws): plain NIGHTFALL!, no countdown, no error
local getTime = GetTime
C_UnitAuras.GetPlayerAuraBySpellID = nil
GetTime = function() error("clock hidden") end
SC.tranceUp = true; UI.OnTrance(true)
check(fr.head:GetText() == "NIGHTFALL!", "no readable time: plain NIGHTFALL!")
fr:GetScript("OnUpdate")(fr, 1)
check(fr.head:GetText() == "NIGHTFALL!", "no readable time: stays plain on ticks")
GetTime = function() return secret end
fr:GetScript("OnUpdate")(fr, 1)
check(fr.head:GetText() == "NIGHTFALL!", "secret clock: stays plain")
GetTime, C_UnitAuras.GetPlayerAuraBySpellID = getTime, api
SC.tranceUp = false; UI.OnTrance(false)
check(errors() == base, "no Lua errors recorded")
M.done("ShadowCount UI")
