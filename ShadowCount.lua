-- Shadow Count: a Nightfall / Shadow Trance counter for Warlocks on WoW: Forever. Written from scratch (MIT).
--
-- What the client data says (wago.tools db2, build 1.60.1.70862):
--   * Nightfall 18094 (Affliction talent) gives Corruption, Drain Soul, Drain Life and Wrack a chance to put you in
--     Shadow Trance, 17941: "Your next Shadow Bolt becomes an instant cast spell." It lasts 10 seconds (SpellDuration 1).
--   * The player's Shadow Bolt ranks are 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661 and 25307
--     (SkillLineAbility, Destruction 593, Warlock class mask).
--
-- How it counts:
--   * Spent: a Shadow Bolt that succeeds with no cast bar (no UNIT_SPELLCAST_START for its cast GUID) is instant,
--     and only a Trance makes it instant. The player's own cast events are never secret on this client
--     (SecretWhenUnitSpellCastRestricted only hides other units), so spends are counted on any client.
--   * Gained: only when the client lets us see it. In combat auras are secret unless the spell is flagged
--     never-secret (GetPlayerAuraBySpellID: SecretWhenUnitAuraRestricted + RequiresNonSecretAura, so a hidden aura
--     returns nothing), and nobody outside the game knows whether 17941 has that flag. So the mode is picked at
--     runtime (login, each fight start, /shc debug): "aura" when C_Secrets.GetSpellAuraSecrecy(17941) == 0 or the
--     client has no secret restrictions; "cast" once the player's UNIT_SPELLCAST_SUCCEEDED for 17941 has been seen;
--     otherwise "none": gains aren't shown, and the 10-second countdown never starts for a Trance we didn't see.
--   * An aura read that returns nothing while auras are hidden means "unknown", never "the Trance is down".
--
-- Addons on this client get no combat log and every hit amount is a secret value, so nothing here guesses a number.
-- Shadow Bolt damage, share and average come from Blizzard's own damage meter (C_DamageMeter) after combat.
local ADDON, ns = ...
local C, Core = ns.Compat, ns.Core
local L = Core.L

-- Slash commands: the first is the main one shown in help text. Change them here only.
ns.SLASH = { "/shc", "/shadowcount" }

local SC = {}
KennyShadowCount = SC
ns.SC = SC

local SCHEMA = 2 -- 2 = 1.1.0: fade, compact and clickThrough settings
local DEDUPE = 0.25 -- seconds: the 17941 cast event and its aura appearing are one gain, not two

SC.TRANCE = 17941
SC.TRANCE_SECONDS = 10
SC.BOLTS = { [686] = 1, [695] = 2, [705] = 3, [1088] = 4, [1106] = 5, [7641] = 6, [11659] = 7, [11660] = 8, [11661] = 9, [25307] = 10 }

-- Built-in sound files (FileDataIDs, from the community listfile; checked by tools/verify_media.sh). No bundled audio.
SC.SOUNDS = {
  trance = 568263, -- sound/spells/alert_wl_shadowtrance.ogg
  shadow = 569040, -- sound/spells/shadowformimpact.ogg
  curse = 569079,  -- sound/spells/curse.ogg
}
SC.SOUND_MODES = { every = true, record = true, off = true }

SC.DEFAULTS = {
  shown = true, locked = false, scale = 1, width = 240, height = 160, sound = "every", soundFile = "theme", -- 160 tall: room for four 12 pt lines
  fade = true,         -- 1.1.0: out of combat the box rests at 35% alpha (full in combat, on hover, during a Trance or the test)
  compact = false,     -- 1.1.0: one slim strip (headline, instant count, bar); width and height above stay the full size
  clickThrough = false, -- 1.1.0: while locked, clicks pass through the box (/shc unlock or /shc clickthrough gives them back)
}
SC.BOOL_SETTINGS = { "shown", "locked", "fade", "compact", "clickThrough" }

local db, settings
local migrations = {} -- schema 1 is the first release
-- 1.0.x -> 1.1.0: settings keep everything already saved (size, spot, sounds); the three new switches start at their
-- defaults. Anything that isn't a true/false where one belongs (a hand-edited file) is dropped, so the default applies.
migrations[2] = function(d)
  d.settings = type(d.settings) == "table" and d.settings or {}
  for _, k in ipairs(SC.BOOL_SETTINGS) do
    if d.settings[k] ~= nil and type(d.settings[k]) ~= "boolean" then d.settings[k] = nil end
  end
  return d
end
SC.migrations = migrations

local function now() return C.Clock() end

local function newFight()
  return { gained = 0, spent = 0, bolts = 0, start = now() }
end
local function newSession()
  return { gained = 0, spent = 0, bolts = 0, fights = 0, total = 0, sb = 0, measuredBolts = 0, bestAvg = 0, since = C.Now() }
end

SC.fight = newFight()
SC.lastFight = nil
SC.tranceUp = false

function SC.DB() return db end
function SC.Settings() return settings end
function SC.Session() return db and db.session end

function SC.ClassFile() return C.Safe(UnitClass and select(2, UnitClass("player"))) end
function SC.ClassMatches() return SC.ClassFile() == "WARLOCK" end

function SC.Play()
  local pick = settings and settings.soundFile or "theme"
  local id = (pick == "theme" and SC.theme and SC.theme.sound) or SC.SOUNDS[pick] or SC.SOUNDS.trance
  local ok, willPlay = pcall(PlaySoundFile, id, "Master")
  return ok and willPlay ~= false
end

-- ---------- detection mode ----------
SC.mode = "none"        -- "aura", "cast" or "none" (see the header)
SC.restricted = nil     -- C_Secrets.HasSecretRestrictions(): true / false / nil (unknown)
SC.secrecy = nil        -- C_Secrets.GetSpellAuraSecrecy(17941): 0 never, 1 always, 2 contextually secret
SC.auraReadable = false -- 17941's aura can be read in combat
SC.castsSeen = 0        -- plain 17941 cast events this session

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok or C.IsSecret(v) then return nil end
  return v
end

function SC.EvaluateMode()
  local S = C_Secrets
  SC.restricted = S and call(S.HasSecretRestrictions)
  -- a client with neither C_Secrets nor issecretvalue has no secret values at all
  if SC.restricted == nil and type(S) ~= "table" and issecretvalue == nil then SC.restricted = false end
  local level = S and call(S.GetSpellAuraSecrecy, SC.TRANCE)
  SC.secrecy = type(level) == "number" and level or nil
  SC.auraReadable = (SC.restricted == false or SC.secrecy == 0) and C_UnitAuras ~= nil
    and type(C_UnitAuras.GetPlayerAuraBySpellID) == "function"
  SC.mode = SC.auraReadable and "aura" or (db and db.castSeen and "cast") or "none"
  return SC.mode
end

-- ---------- Shadow Trance ----------
local lastGain, expiry, auraExp
local hardCasts = {} -- castGUID -> true for Shadow Bolts that showed a cast bar

local function setTrance(up)
  SC.tranceUp = up
  if expiry then expiry:Cancel(); expiry = nil end
  if up then
    -- the Trance lasts 10 seconds: our own end time, used when the aura's time left can't be read
    expiry = C_Timer.NewTimer(SC.TRANCE_SECONDS, function() if SC.tranceUp then setTrance(false) end end)
  else
    auraExp = nil
  end
  if ns.UI then ns.UI.OnTrance(up) end
end

-- A Trance gain we actually saw (its cast event, or its aura in "aura" mode). Never called on a guess.
function SC.OnTranceGain(t)
  t = t or now()
  if lastGain and t - lastGain < DEDUPE then return false end
  lastGain = t
  local f = SC.fight
  f.gained = f.gained + 1
  if db then db.session.gained = db.session.gained + 1 end
  if (settings and settings.sound or SC.DEFAULTS.sound) == "every" then SC.Play() end
  setTrance(true)
  return true
end

-- A Shadow Bolt went off. No cast bar = instant = a Trance was spent, seen or not. If its cast GUID can't be read,
-- it only counts when a seen Trance is up.
function SC.OnBolt(castGUID)
  local f = SC.fight
  f.bolts = f.bolts + 1
  if db then db.session.bolts = db.session.bolts + 1 end
  local guid = C.Safe(castGUID)
  local hard = guid ~= nil and hardCasts[guid]
  if guid ~= nil then hardCasts[guid] = nil end
  if hard or (guid == nil and not SC.tranceUp) then return false end
  f.spent = f.spent + 1
  if db then db.session.spent = db.session.spent + 1 end
  if SC.tranceUp then setTrance(false) end
  if ns.UI then ns.UI.OnSpent() end
  return true
end

function SC.OnCastStart(unit, castGUID, spellID)
  if unit ~= "player" or C.IsSecret(spellID) or not SC.BOLTS[spellID] then return end
  local guid = C.Safe(castGUID)
  if guid ~= nil then hardCasts[guid] = true end
end

function SC.OnSpellcast(unit, castGUID, spellID)
  if unit ~= "player" or C.IsSecret(spellID) then return end
  if spellID == SC.TRANCE then
    SC.castsSeen = SC.castsSeen + 1
    if db and not db.castSeen then db.castSeen = true end
    if SC.mode == "none" then SC.mode = "cast" end
    SC.OnTranceGain()
  elseif SC.BOLTS[spellID] then SC.OnBolt(castGUID) end
end

-- The Trance aura in "aura" mode: true + expirationTime, or false when it is not on the player. nil = unknown
-- (not readable on this client, a failed read or a secret value), which never ends a Trance.
function SC.ReadTrance()
  if not SC.auraReadable then return nil end
  local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, SC.TRANCE)
  if not ok or C.IsSecret(aura) then return nil end
  if aura == nil then return false end
  if type(aura) ~= "table" then return nil end
  local ok2, exp = pcall(function() return aura.expirationTime end)
  return true, ok2 and C.SafeNumber(exp) or nil
end

-- UNIT_AURA on the player: only "aura" mode reads anything (the payload itself is secret in combat).
function SC.OnAura(unit)
  if unit ~= "player" then return end
  local up, exp = SC.ReadTrance()
  if up == true then
    -- appeared, or refreshed by a new Nightfall proc (later expirationTime): a gain
    if not SC.tranceUp or (exp and auraExp and exp > auraExp) then SC.OnTranceGain() end
    auraExp = exp or auraExp
  elseif up == false and SC.tranceUp then
    setTrance(false)
  end
end

function SC.DetectionLines()
  SC.EvaluateMode()
  local S = C_Secrets
  local up = SC.ReadTrance()
  return {
    ("detection mode: %s  (aura = buff read, cast = cast event, none = gains hidden; instant bolts always count)"):format(SC.mode),
    ("secret restrictions: %s, auras secret now: %s, in combat: %s"):format(tostring(SC.restricted),
      tostring(S and call(S.ShouldAurasBeSecret)), tostring(C.InCombat())),
    ("Shadow Trance 17941: secrecy %s (0 = never secret), aura %s, Trance up: %s"):format(tostring(SC.secrecy),
      up == nil and "unknown" or (up and "up" or "not up"), tostring(SC.tranceUp)),
    ("Trance cast events seen: %d this session, ever: %s"):format(SC.castsSeen, tostring(db and db.castSeen or false)),
  }
end

-- ---------- Blizzard's damage meter ----------
local function playerGUID() return UnitGUID and UnitGUID("player") end

function SC.MeterAvailable()
  if not (C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable) then return false, "no C_DamageMeter" end
  local ok, avail, why = pcall(C_DamageMeter.IsDamageMeterAvailable)
  if not ok then return false, tostring(avail) end
  return avail == true, why
end

function SC.MeterSource()
  if not C_DamageMeter then return nil end
  local guid = playerGUID()
  local dmg = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
  if C_DamageMeter.GetAvailableCombatSessions and C_DamageMeter.GetCombatSessionSourceFromID then
    local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
    local newest
    if ok and type(list) == "table" then
      for _, s in ipairs(list) do
        local id = C.SafeNumber(s.sessionID)
        if id and (not newest or id > newest) then newest = id end
      end
    end
    if newest then
      local ok2, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID, newest, dmg, guid)
      if ok2 and type(src) == "table" then return src end
    end
  end
  if C_DamageMeter.GetCombatSessionSourceFromType then
    local cur = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
    local ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, cur, dmg, guid)
    if ok and type(src) == "table" then return src end
  end
  return nil
end

function SC.LiveSource()
  if not (C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType) then return nil end
  local cur = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
  local dmg = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
  local ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, cur, dmg, playerGUID())
  if ok and type(src) == "table" then return src end
  return nil
end

-- Plain-number summary: { total, sb, split, rows }, or nil while anything is secret.
function SC.ReadMeter(src)
  src = src or SC.MeterSource()
  if type(src) ~= "table" then return nil, "no meter data" end
  local total = C.SafeNumber(src.totalAmount)
  if not total then return nil, "secret" end
  local out = { total = total, sb = 0, rows = {}, split = false }
  for _, sp in ipairs(type(src.combatSpells) == "table" and src.combatSpells or {}) do
    local id, amount = C.SafeNumber(sp.spellID), C.SafeNumber(sp.totalAmount)
    if not (id and amount) then return nil, "secret" end
    out.rows[#out.rows + 1] = { spellID = id, amount = amount }
    if SC.BOLTS[id] then out.sb = out.sb + amount; out.split = true end
  end
  table.sort(out.rows, function(a, b) return a.amount > b.amount end)
  return out
end

-- ---------- fights ----------
function SC.StartFight()
  SC.fight = newFight()
  SC.fight.inCombat = true
  if ns.UI then ns.UI.OnCombat(true) end
end

function SC.EndFight()
  local f = SC.fight
  f.inCombat = false
  f.duration = math.max(0, now() - f.start)
  if ns.UI then ns.UI.OnCombat(false) end
  local tries = 0
  local function attempt()
    tries = tries + 1
    if SC.fight ~= f or f.done then return end
    local r = SC.ReadMeter()
    if r or tries >= 4 then SC.FinishFight(f, r) return end
    C_Timer.After(1, attempt)
  end
  C_Timer.After(0.5, attempt)
end

function SC.FinishFight(f, r)
  f.done = true
  local res = { gained = f.gained, spent = f.spent, bolts = f.bolts, duration = f.duration or 0 }
  if r then
    res.total = r.total
    if r.split then
      res.sb = r.sb
      res.share = r.total > 0 and r.sb / r.total or 0
      res.avg = f.bolts > 0 and r.sb / f.bolts or nil
    end
  end
  SC.lastFight = res
  if db and (f.gained > 0 or f.bolts > 0 or (r and r.total > 0)) then
    local s = db.session
    s.fights = s.fights + 1
    if r then
      s.total = s.total + r.total
      if f.bolts > 0 then db.meterSplits = r.split end
      if r.split then
        s.sb = s.sb + r.sb
        s.measuredBolts = s.measuredBolts + f.bolts
        if res.avg and res.avg > s.bestAvg and f.bolts >= 2 then
          local beaten = s.bestAvg > 0
          s.bestAvg = res.avg
          res.record = beaten
          if beaten and settings.sound == "record" then SC.Play() end
        end
      end
    end
  end
  if ns.UI then ns.UI.Refresh() end
  return res
end

function SC.ResetSession()
  if not db then return end
  db.session = newSession()
  SC.lastFight = nil
  if ns.UI then ns.UI.Refresh() end
end

function SC.SessionStats()
  local s = db and db.session
  if not s then return nil end
  return {
    gained = s.gained, spent = s.spent, bolts = s.bolts, fights = s.fights, total = s.total, sb = s.sb, bestAvg = s.bestAvg,
    share = (s.total > 0 and s.sb > 0) and s.sb / s.total or nil,
    avg = s.measuredBolts > 0 and s.sb / s.measuredBolts or nil,
  }
end

-- ---------- theme: Warlock colours, then the talent tree with the most points ----------
local function hex(h)
  h = tostring(h or "FFFFFF")
  return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
SC.Hex = hex

function SC.TreePoints()
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo
    and C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupCurrencyInfo) then return nil end
  local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
  configID = ok and C.SafeNumber(configID)
  if not configID then return nil end
  local ok2, cfg = pcall(C_Traits.GetConfigInfo, configID)
  local treeID = ok2 and type(cfg) == "table" and type(cfg.treeIDs) == "table" and C.SafeNumber(cfg.treeIDs[1])
  if not treeID then return nil end
  local ok3, displays = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
  if not ok3 or type(displays) ~= "table" or #displays == 0 then return nil end
  local ids = {}
  for i, d in ipairs(displays) do ids[i] = d.groupID end
  local ok4, groups = pcall(C_Traits.GetGroupCurrencyInfo, configID, ids)
  if not ok4 or type(groups) ~= "table" then return nil end
  local spentBy = {}
  for _, g in ipairs(groups) do
    local cur = type(g.currencyInfos) == "table" and g.currencyInfos[1]
    local id = C.SafeNumber(g.traitNodeGroupID)
    if id and cur then spentBy[id] = C.SafeNumber(cur.spent) end
  end
  local out = {}
  for _, d in ipairs(displays) do
    out[#out + 1] = { skillLine = C.SafeNumber(d.skillLineID), order = C.SafeNumber(d.orderIndex) or #out,
      name = C.Safe(d.displayName), spent = spentBy[C.SafeNumber(d.groupID) or -1] or 0 }
  end
  table.sort(out, function(a, b) return a.order < b.order end)
  return out
end

function SC.PickTree(classTheme, points)
  if type(points) ~= "table" or not classTheme then return nil end
  local best, bestPos, second = nil, nil, -1
  for pos, t in ipairs(points) do
    if not best or t.spent > best.spent then
      if best then second = best.spent end
      best, bestPos = t, pos
    elseif t.spent > second then second = t.spent end
  end
  if not best or best.spent <= 0 or best.spent == second then return nil end
  local trees = classTheme.trees or {}
  if best.skillLine and trees[best.skillLine] then return trees[best.skillLine], best end
  local byOrder = classTheme.order and classTheme.order[bestPos]
  if byOrder and trees[byOrder] then return trees[byOrder], best end
  return nil
end

function SC.ResolveTheme(points)
  local base = ns.THEME
  local tree, info = SC.PickTree(base, points)
  local th = { tree = info and info.name, sound = tree and tree.sound or base.sound }
  th.frame = { hex(base.frame) }
  th.accent = { hex(tree and tree.accent or base.accent) }
  th.title = { hex(base.title or base.frame) }
  return th
end

function SC.UpdateTheme()
  SC.theme = SC.ResolveTheme(SC.TreePoints())
  if ns.UI and ns.UI.ApplyTheme then ns.UI.ApplyTheme(SC.theme) end
  return SC.theme
end
SC.theme = SC.ResolveTheme(nil)

-- ---------- text helpers ----------
function SC.Short(n)
  n = C.SafeNumber(n)
  if not n then return "?" end
  if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
  if n >= 1e4 then return ("%.1fK"):format(n / 1e3) end
  return tostring(math.floor(n + 0.5))
end
function SC.Pct(x) return x and ("%d%%"):format(math.floor(x * 100 + 0.5)) or "-" end

function SC.StateLines()
  local s = SC.SessionStats() or {}
  local avail, why = SC.MeterAvailable()
  local f = SC.lastFight
  local out = {
    "settings: sound=" .. tostring(settings and settings.sound) .. " file=" .. tostring(settings and settings.soundFile),
    "class: " .. tostring(SC.ClassFile()) .. " / tree: " .. tostring(SC.theme and SC.theme.tree or "class default"),
    "damage meter available: " .. tostring(avail) .. (why and why ~= "" and (" (" .. tostring(why) .. ")") or ""),
    "meter lists Shadow Bolt: " .. tostring(db and db.meterSplits),
    ("session: %s Trances, %s instant bolts, %s bolts, %s fights"):format(tostring(s.gained), tostring(s.spent), tostring(s.bolts), tostring(s.fights)),
    "last fight: " .. (f and ("%d Trances, %d instant, %d bolts, total %s"):format(f.gained, f.spent, f.bolts, SC.Short(f.total)) or "none"),
  }
  for _, l in ipairs(SC.DetectionLines()) do out[#out + 1] = l end
  return out
end

-- ---------- events ----------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:RegisterUnitEvent("UNIT_AURA", "player")
for _, e in ipairs({ "PLAYER_LOGIN", "TRAIT_CONFIG_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE" }) do ev:RegisterEvent(e) end

local handlers = {
  PLAYER_REGEN_DISABLED = function() SC.EvaluateMode(); SC.StartFight() end,
  PLAYER_REGEN_ENABLED = function()
    SC.EndFight()
    if SC.themeStale then SC.themeStale = false; SC.UpdateTheme() end
  end,
  UNIT_SPELLCAST_START = SC.OnCastStart,
  UNIT_SPELLCAST_SUCCEEDED = SC.OnSpellcast,
  UNIT_AURA = SC.OnAura,
  PLAYER_LOGIN = function()
    SC.EvaluateMode()
    SC.UpdateTheme()
    if ns.UI then ns.UI.UpdateVisibility() end
  end,
}
local function talentsChanged() if C.InCombat() then SC.themeStale = true else SC.UpdateTheme() end end
handlers.TRAIT_CONFIG_UPDATED, handlers.ACTIVE_TALENT_GROUP_CHANGED, handlers.PLAYER_TALENT_UPDATE = talentsChanged, talentsChanged, talentsChanged

ev:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    db = Core.Migrate(KennyShadowCountDB, migrations, SCHEMA)
    db.session = db.session or newSession()
    KennyShadowCountDB = db
    settings = Core.Settings(db.settings, SC.DEFAULTS)
    if ns.UI then Core.SafeCall("build", ns.UI.Build, db, settings) end
    return
  end
  local h = handlers[event]
  if h and db then Core.SafeCall(event, h, ...) end
end)

Core.Setup({ cmd = ns.SLASH[1],
  required = { "C_DamageMeter.GetCombatSessionSourceFromType", "C_DamageMeter.GetAvailableCombatSessions",
    "C_DamageMeter.GetCombatSessionSourceFromID", "PlaySoundFile", "C_Timer.After", "C_Timer.NewTimer", "UnitGUID" },
  optional = { "C_UnitAuras.GetPlayerAuraBySpellID", "C_Secrets.HasSecretRestrictions", "C_Secrets.GetSpellAuraSecrecy",
    "C_Secrets.ShouldAurasBeSecret", "C_DamageMeter.IsDamageMeterAvailable", "AbbreviateNumbers",
    "C_ClassTalents.GetActiveConfigID", "C_Traits.GetGroupDisplayInfoByTreeID", "C_Traits.GetGroupCurrencyInfo" },
  db = function() return db end,
  firstRun = { L["Nightfall counter ready. Drag the box to move it; type %s for options."]:format(ns.SLASH[1]) },
  debugLines = function() return SC.StateLines() end })
