-- Shadow Count 1.1.0 quality-of-life features: idle fade, the 10s Trance drain bar, the right-click quick menu,
-- compact mode and click-through when locked. Starts on a client where the Trance aura is readable ("aura" mode),
-- then replays "cast" and "none" mode by switching the mocked C_Secrets answers.
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
M.class = "WARLOCK"
local OPEN = { HasSecretRestrictions = function() return false end, GetSpellAuraSecrecy = function() return 0 end }
local STRICT = { HasSecretRestrictions = function() return true end, GetSpellAuraSecrecy = function() return 1 end }
C_Secrets = OPEN

-- Blizzard's context menu (MenuUtil.CreateContextMenu + element descriptions), recorded so entries can be clicked
local menus = {}
local function desc(kind, text, a, b)
  local d = { kind = kind, text = text, a = a, b = b, kids = {} }
  for _, m in ipairs({ "CreateTitle", "CreateButton", "CreateCheckbox", "CreateRadio", "CreateDivider" }) do
    d[m] = function(self, t, x, y) local c = desc(m, t, x, y); self.kids[#self.kids + 1] = c; return c end
  end
  return d
end
local realMenu = { CreateContextMenu = function(owner, gen)
  local root = desc("root"); gen(owner, root); menus[#menus + 1] = root; return {} end }
MenuUtil = realMenu
GameTooltip = M.frameObj("GameTooltip")

local ns = M.loadAddon(".", "ShadowCount")
local SC, UI = KennyShadowCount, ns.UI
local check = M.check
M.fire("PLAYER_LOGIN")
local fr = UI.Frame()
local S = SC.Settings()
local T = SC.TRANCE
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end
local function tick(sec) M.advance(sec); local fn = fr:GetScript("OnUpdate"); if fn then fn(fr, sec) end end
local function errors() return #ns.Core.errors end
local base = errors()
local function barText() return fr.barText:GetText() or "" end
local function shareBar() return fr.bar.maxV == 1 and barText():find("Shadow Bolt share", 1, true) ~= nil
  and fr.bar.color and near(fr.bar.color[1], SC.theme.accent[1]) and near(fr.bar.color[3], SC.theme.accent[3]) end
local function drainColour() local c = fr.bar.color or {}
  return near(c[1], UI.DRAIN_COLOR[1]) and near(c[2], UI.DRAIN_COLOR[2]) and near(c[3], UI.DRAIN_COLOR[3]) end
local n = 0
local function castTrance() n = n + 1; M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "t" .. n, T) end
local function instantBolt() n = n + 1; M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sb" .. n, 11661) end
local function startFight() M.combat = true; M.fire("PLAYER_REGEN_DISABLED") end
local function endFight() M.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(5) end

-- ---------- defaults ----------
check(S.fade == true and S.compact == false and S.clickThrough == false, "1.1.0 defaults: fade on, compact off, click-through off")
check(KennyShadowCountDB.schema == 2, "SavedVariables schema 2")
check(KennyShadowCountDB.settings.fade == nil, "defaults are not written into SavedVariables")
check(SC.mode == "aura", "readable client: aura mode")

-- ---------- 1. idle fade ----------
check(near(fr:GetAlpha(), 0.35) and near(UI.FADE_ALPHA, 0.35), "idle out of combat: 35% alpha")
fr:GetScript("OnEnter")(fr)
check(near(fr:GetAlpha(), 1), "hover: full alpha")
M.mouseOver = fr; fr:GetScript("OnLeave")(fr)
check(near(fr:GetAlpha(), 1), "mouse moved onto the padlock (still over the box): stays full")
M.mouseOver = nil; fr.lock:GetScript("OnLeave")(fr.lock)
check(near(fr:GetAlpha(), 0.35), "mouse left the box from the padlock: fades again")
fr:GetScript("OnEnter")(fr); fr:GetScript("OnLeave")(fr)
check(near(fr:GetAlpha(), 0.35), "hover ends: back to 35%")
startFight()
check(near(fr:GetAlpha(), 1), "in combat: full alpha")
endFight()
check(near(fr:GetAlpha(), 0.35), "combat over: back to 35%")
M.combat = true; UI.UpdateAlpha()
check(near(fr:GetAlpha(), 1), "combat lockdown without a fight start (/reload in combat): full alpha")
M.combat = false; UI.UpdateAlpha()
M.prints = {}
M.slash("/shc", "fade")
check(S.fade == false and near(fr:GetAlpha(), 1) and M.printed("idle fade: off"), "/shc fade off: full alpha at once")
fr:GetScript("OnEnter")(fr); fr:GetScript("OnLeave")(fr)
check(near(fr:GetAlpha(), 1), "fade off: hover ending keeps full alpha")
M.slash("/shc", "fade")
check(S.fade == true and near(fr:GetAlpha(), 0.35) and M.printed("idle fade: on"), "/shc fade on: fades at once")

-- ---------- 2. the 10s Trance drain bar: aura mode ----------
check(not UI.Draining() and shareBar(), "no Trance: Shadow Bolt share bar")
M.auras[T] = { spellId = T, expirationTime = M.clock + 10 }
castTrance()
check(SC.tranceUp and UI.Draining(), "aura mode Trance: drain bar on")
check(near(fr:GetAlpha(), 1), "Trance up out of combat: full alpha")
check(fr.bar.minV == 0 and fr.bar.maxV == 10 and near(fr.bar.value, 10) and drainColour(), "drain bar: 0-10s, full, violet-white")
check(barText() == "NIGHTFALL! 10.0s", "drain bar text at the gain")
tick(3.8)
check(near(fr.bar.value, 6.2) and barText() == "NIGHTFALL! 6.2s", "drains with time: NIGHTFALL! 6.2s")
tick(0.05)
check(near(fr.bar.value, 6.15), "drains smoothly between whole seconds")
SC.UpdateTheme()
check(drainColour(), "a theme change mid-Trance keeps the drain colour")
M.auras[T] = nil
instantBolt()
check(not SC.tranceUp and not UI.Draining() and shareBar(), "Trance spent: Shadow Bolt share bar restored")
check(near(fr:GetAlpha(), 0.35), "Trance spent out of combat: fades again")
-- a Trance that runs out
M.advance(1)
M.auras[T] = { spellId = T, expirationTime = M.clock + 10 }
castTrance()
check(UI.Draining(), "second Trance: drain bar on")
M.auras[T] = nil; M.fire("UNIT_AURA", "player", {})
check(not SC.tranceUp and not UI.Draining() and shareBar(), "aura gone (Trance ended): share bar restored")
-- in combat, the bar restores too (the live view never redraws the bar itself)
startFight()
M.advance(1)
M.auras[T] = { spellId = T, expirationTime = M.clock + 10 }
castTrance()
tick(9.9)
check(UI.Draining() and barText() == "NIGHTFALL! 0.1s", "in combat: drain bar near the end")
M.auras[T] = nil
M.advance(0.2)
check(not SC.tranceUp and not UI.Draining() and shareBar(), "in combat, Trance expired: share bar restored")
endFight()

-- ---------- 2b. cast mode: own 10s clock ----------
C_Secrets = STRICT
check(SC.EvaluateMode() == "cast", "aura hidden, cast event seen before: cast mode")
castTrance()
check(UI.Draining() and barText() == "NIGHTFALL! 10.0s", "cast mode Trance: drain bar from our own 10s clock")
tick(4)
check(near(fr.bar.value, 6) and barText() == "NIGHTFALL! 6.0s", "cast mode: drains with our own clock")
M.advance(6.1)
check(not SC.tranceUp and not UI.Draining() and shareBar(), "cast mode: expired after 10s, share bar restored")
-- clock unreadable: full bar with a plain NIGHTFALL!, no made-up countdown
local getTime = GetTime
castTrance()
GetTime = function() error("clock hidden") end
tick(0)
check(UI.Draining() and near(fr.bar.value, 10) and barText() == "NIGHTFALL!", "no readable time: full bar, no countdown")
GetTime = getTime
instantBolt()
check(not UI.Draining() and shareBar(), "spent: restored")

-- ---------- 2c. none mode: never a countdown ----------
KennyShadowCountDB.castSeen = nil
check(SC.EvaluateMode() == "none", "strict client, no cast event ever: none mode")
M.auras[T] = { spellId = T, expirationTime = M.clock + 10 }
M.fire("UNIT_AURA", "player", {})
tick(1)
check(not SC.tranceUp and not UI.Draining() and shareBar(), "none mode: a hidden Trance never starts the drain bar")
-- even if something marked the Trance up in none mode, no countdown is faked
SC.tranceUp = true; UI.OnTrance(true); tick(1)
check(not UI.Draining() and shareBar() and not barText():find("NIGHTFALL", 1, true), "none mode, Trance flagged up: still no drain bar")
check(UI.TranceTimeLeft() == nil and fr.head:GetText() == "NIGHTFALL!", "none mode: plain NIGHTFALL!, no seconds")
SC.tranceUp = false; UI.OnTrance(false)
M.auras[T] = nil
C_Secrets = OPEN; SC.EvaluateMode()

-- ---------- 2d. /shc test preview ----------
M.sounds = {}
M.slash("/shc", "test")
check(UI.PreviewActive() and UI.Draining() and #M.sounds == 1, "test preview: drain bar and sound")
check(near(fr:GetAlpha(), 1) and fr.head:GetText() == "NIGHTFALL!  10s", "test preview: full alpha, headline countdown")
tick(2.5)
check(near(fr.bar.value, 7.5) and barText() == "NIGHTFALL! 7.5s", "test preview drains")
tick(8)
check(not UI.PreviewActive() and not UI.Draining() and shareBar(), "test preview over after 10s: share bar back")
check(near(fr:GetAlpha(), 0.35) and fr.head:GetText() == "Trance faded", "test preview over: fades, headline says so")
M.slash("/shc", "test")
startFight()
check(not UI.PreviewActive() and not UI.Draining() and shareBar(), "combat starts: test preview stops")
M.prints = {}
M.slash("/shc", "test")
check(not UI.PreviewActive() and M.printed("not in combat"), "no test preview in combat")
endFight()
M.slash("/shc", "test")
M.auras[T] = { spellId = T, expirationTime = M.clock + 10 }
castTrance()
check(not UI.PreviewActive() and UI.Draining() and barText() == "NIGHTFALL! 10.0s", "a real Trance replaces the preview")
M.auras[T] = nil; instantBolt()
check(not UI.Draining(), "real Trance spent: restored")

-- ---------- 4. compact mode ----------
M.slash("/shc", "size 300 200")
check(fr.width == 300 and fr.height == 200, "full size 300x200")
M.prints = {}
M.slash("/shc", "compact")
check(S.compact == true and M.printed("compact mode: on"), "/shc compact on")
check(fr.height == UI.COMPACT_H and UI.COMPACT_H >= 56 and UI.COMPACT_H <= 64 and fr.width == 300, "compact: slim strip, width kept")
check(not fr.lines:IsShown() and not fr.reset:IsShown() and not fr.title:IsShown() and not fr.rule:IsShown(), "compact: breakdown, reset, title hidden")
check(fr.head:IsShown() and fr.count:IsShown() and fr.bar:IsShown() and not fr.grip:IsShown(), "compact: headline, count, bar; no grip")
check(fr.count:GetText() == UI.CountText() and UI.CountText():find("instant", 1, true), "compact: instant bolt count")
check(S.width == 300 and S.height == 200, "compact: saved full size untouched")
fr.width = 999; fr.grip:GetScript("OnMouseUp")(fr.grip)
check(S.width == 300 and S.height == 200, "compact: a stray grip release doesn't overwrite the full size")
startFight()
instantBolt()
check(fr.count:GetText() == "1 instant", "compact in combat: live instant count")
endFight()
check(not fr.reset:IsShown(), "compact: Reset stays hidden after combat")
M.slash("/shc", "size 320 180")
check(S.width == 320 and S.height == 180 and fr.width == 320 and fr.height == UI.COMPACT_H, "/shc size in compact: saves the full size, strip stays slim")
M.slash("/shc", "compact")
check(S.compact == false and fr.width == 320 and fr.height == 180, "compact off: full size restored")
check(fr.lines:IsShown() and fr.reset:IsShown() and fr.title:IsShown() and not fr.count:IsShown() and fr.grip:IsShown(), "full layout back")
-- a protected box would wait for the end of combat (ours isn't protected, so this is only the guard)
fr.protected = true
startFight()
M.slash("/shc", "compact")
check(S.compact == true and fr.height == 180 and UI.layoutPending, "protected frame in combat: layout waits")
endFight()
check(fr.height == UI.COMPACT_H and not UI.layoutPending, "combat over: waiting layout applied")
fr.protected = false
M.slash("/shc", "compact")
check(fr.height == 180, "compact off again")

-- ---------- 5. click-through when locked ----------
check(fr:IsMouseEnabled(), "mouse on by default")
M.prints = {}
M.slash("/shc", "clickthrough")
check(S.clickThrough == true and fr:IsMouseEnabled() and M.printed("click-through when locked: on"), "click-through on but unlocked: still clickable")
M.prints = {}
M.slash("/shc", "lock")
check(not fr:IsMouseEnabled() and not fr.lock:IsMouseEnabled() and not fr.reset:IsMouseEnabled(), "locked + click-through: box, padlock and Reset pass clicks through")
check(M.printed("/shc unlock") and M.printed("/shc clickthrough"), "locking with click-through says how to undo it")
M.slash("/shc", "unlock")
check(fr:IsMouseEnabled() and fr.lock:IsMouseEnabled() and fr.reset:IsMouseEnabled(), "/shc unlock restores clicks")
M.slash("/shc", "lock")
check(not fr:IsMouseEnabled(), "locked again: clicks pass through")
M.slash("/shc", "clickthrough")
check(S.clickThrough == false and S.locked and fr:IsMouseEnabled(), "/shc clickthrough off restores clicks while still locked")
check(fr:IsMouseEnabled(), "locked without click-through: clickable (needs both)")
M.slash("/shc", "unlock")
M.prints = {}; M.slash("/shc", "help")
check(M.printed("fade | compact | clickthrough") and M.printed("/shc unlock or /shc clickthrough"), "help lists the new commands and how to undo click-through")

-- ---------- 3. right-click quick menu ----------
local function find(d, text) for _, k in ipairs(d.kids) do if k.text == text then return k end end end
fr:GetScript("OnMouseUp")(fr, "LeftButton")
check(#menus == 0, "left click: no menu")
fr:GetScript("OnMouseUp")(fr, "RightButton")
check(#menus == 1, "right-click out of combat: menu opens")
local root = menus[1]
check(root.kids[1].kind == "CreateTitle" and root.kids[1].text == "Shadow Count", "menu title")
local snd, file = find(root, "Sound"), find(root, "Sound file")
check(snd and #snd.kids == 3 and file and #file.kids == 4, "sound mode (3) and sound file (4) submenus")
local labels = { "Idle fade out of combat", "Compact mode", "Locked", "Click-through when locked", "Test preview", "Reset session", "Reset position" }
local all = true
for _, l in ipairs(labels) do all = all and find(root, l) ~= nil end
check(all, "fade, compact, lock, click-through, test, reset session, reset position entries")
find(snd, "Off").b()
check(S.sound == "off" and find(snd, "Off").a() and not find(snd, "Every Trance").a(), "menu: sound off")
find(snd, "Every Trance").b()
check(S.sound == "every", "menu: sound every")
M.sounds = {}
find(file, "Curse").b()
check(S.soundFile == "curse" and M.sounds[1] and M.sounds[1][1] == 569079 and find(file, "Curse").a(), "menu: sound file curse, previewed")
find(file, "Theme").b()
local fade = find(root, "Idle fade out of combat")
fade.b()
check(S.fade == false and not fade.a() and near(fr:GetAlpha(), 1), "menu: idle fade off")
fade.b()
check(S.fade == true and fade.a(), "menu: idle fade on")
local compact = find(root, "Compact mode")
compact.b()
check(S.compact == true and compact.a() and fr.height == UI.COMPACT_H, "menu: compact on")
compact.b()
check(S.compact == false and fr.height == 180, "menu: compact off, full size back")
local locked = find(root, "Locked")
locked.b()
check(S.locked == true and locked.a(), "menu: lock")
local ct = find(root, "Click-through when locked")
ct.b()
check(S.clickThrough == true and ct.a() and not fr:IsMouseEnabled(), "menu: click-through on while locked")
ct.b()
check(S.clickThrough == false and fr:IsMouseEnabled(), "menu: click-through off")
locked.b()
check(S.locked == false, "menu: unlock")
find(root, "Test preview").a()
check(UI.PreviewActive(), "menu: test preview")
tick(11)
KennyShadowCountDB.session.gained = 5
find(root, "Reset session").a()
check(KennyShadowCountDB.session.gained == 0, "menu: reset session")
KennyShadowCountDB.point = { "TOPLEFT", 5, -5 }
find(root, "Reset position").a()
check(KennyShadowCountDB.point == nil and S.width == SC.DEFAULTS.width, "menu: reset position")
-- combat: the menu doesn't open, and entries of a menu left open do nothing
M.combat = true
fr:GetScript("OnMouseUp")(fr, "RightButton")
check(#menus == 1 and UI.OpenMenu(fr) == false, "in combat: no menu")
M.prints = {}; M.slash("/shc", "menu")
check(#menus == 1 and M.printed("not in combat"), "/shc menu in combat: refused")
fade.b(); compact.b(); locked.b(); find(root, "Reset position").a(); find(root, "Test preview").a()
check(S.fade == true and S.compact == false and S.locked == false and not UI.PreviewActive(), "in combat: menu entries ignored")
M.combat = false
M.slash("/shc", "menu")
check(#menus == 2, "/shc menu out of combat opens it")
-- no Blizzard menu on the client: a hint, no error
MenuUtil = nil; M.prints = {}
fr:GetScript("OnMouseUp")(fr, "RightButton")
check(UI.OpenMenu(fr) == false and M.printed("no quick menu"), "no MenuUtil: hint instead of an error")
MenuUtil = realMenu
check(errors() == base, "no Lua errors recorded")
-- a menu call that throws is caught and reported, never raised
MenuUtil = { CreateContextMenu = function() error("menu broke") end }
check(UI.OpenMenu(fr) == false and errors() == base + 1, "menu error caught")
MenuUtil = realMenu
M.done("ShadowCount 1.1.0 QoL")
