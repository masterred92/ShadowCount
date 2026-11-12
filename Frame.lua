-- Shadow Count window: a small shadow-purple box. Blizzard textures and fonts only.
-- In combat the damage numbers from Blizzard's meter are secret: they go straight into SetFormattedText and
-- StatusBar values (both accept secret values) and are never compared or added here.
local _, ns = ...
local C, Core = ns.Compat, ns.Core
local L = Core.L
local SC = ns.SC

local UI = {}
ns.UI = UI
local frame, db, settings, ticker
local ICON = "Interface\\Icons\\Spell_Shadow_Twilight" -- 136223, Shadow Trance's own icon
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local BG, EDGE = "Interface\\Tooltips\\UI-Tooltip-Background", "Interface\\Tooltips\\UI-Tooltip-Border"
local MIN_W, MIN_H, MAX_W, MAX_H = 180, 120, 480, 300
UI.DEFAULT_POINT = { "CENTER", 0, -210 }

local function fs(parent, font)
  local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  f:SetJustifyH("LEFT")
  return f
end

function UI.Place()
  local p = db.point or UI.DEFAULT_POINT
  frame:ClearAllPoints()
  frame:SetPoint(p[1], UIParent, p[1], p[2], p[3])
end

function UI.ApplyTheme(th)
  if not frame or not th then return end
  local fr, fg, fb = unpack(th.frame)
  local ar, ag, ab = unpack(th.accent)
  frame:SetBackdropBorderColor(fr, fg, fb, 1)
  frame.title:SetTextColor(unpack(th.title))
  frame.bar:SetStatusBarColor(ar, ag, ab)
  frame.flash:SetColorTexture(0.85, 0.75, 1, 1) -- violet-white
  frame.head:SetTextColor(ar, ag, ab)
  frame.rule:SetColorTexture(fr, fg, fb, 0.9)
  frame.tree:SetText(th.tree or "")
end

function UI.ApplyLayout()
  frame:SetSize(settings.width, settings.height)
  frame:SetScale(settings.scale)
end

-- Shown when the setting is on and the character is a Warlock.
function UI.UpdateVisibility()
  if not frame then return end
  frame:SetShown(settings.shown and SC.ClassMatches())
end

function UI.Build(database, s)
  db, settings = database, s
  frame = CreateFrame("Frame", "KennyShadowCountFrame", UIParent, "BackdropTemplate")
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetBackdrop({ bgFile = BG, edgeFile = EDGE, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  frame:SetBackdropColor(0.04, 0.02, 0.07, 0.9) -- near-black violet
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) if not settings.locked then self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint()
    db.point = { p, x, y }
  end)

  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetSize(18, 18)
  icon:SetPoint("TOPLEFT", 8, -7)
  frame.title = fs(frame, "GameFontNormal")
  frame.title:SetPoint("LEFT", icon, "RIGHT", 5, 0)
  frame.title:SetText("Shadow Count")
  frame.tree = fs(frame, "GameFontDisableSmall")
  frame.tree:SetPoint("TOPRIGHT", -9, -11)
  frame.tree:SetJustifyH("RIGHT")
  frame.title:SetPoint("RIGHT", frame.tree, "LEFT", -4, 0)
  frame.title:SetWordWrap(false)
  frame.rule = frame:CreateTexture(nil, "ARTWORK")
  frame.rule:SetHeight(1)
  frame.rule:SetPoint("TOPLEFT", 8, -28)
  frame.rule:SetPoint("TOPRIGHT", -8, -28)

  frame.head = fs(frame, "GameFontNormalLarge")
  frame.head:SetPoint("TOPLEFT", 10, -33)
  frame.head:SetPoint("RIGHT", -10, 0)
  frame.head:SetWordWrap(false)
  frame.lines = fs(frame)
  frame.lines:SetPoint("TOPLEFT", frame.head, "BOTTOMLEFT", 0, -4)
  frame.lines:SetPoint("RIGHT", -10, 0)
  frame.lines:SetJustifyV("TOP")
  frame.lines:SetSpacing(2)

  frame.bar = CreateFrame("StatusBar", nil, frame)
  frame.bar:SetStatusBarTexture(BAR)
  frame.bar:SetPoint("BOTTOMLEFT", 10, 30)
  frame.bar:SetPoint("BOTTOMRIGHT", -10, 30)
  frame.bar:SetHeight(10)
  frame.bar:SetMinMaxValues(0, 1)
  frame.bar:SetValue(0)
  local barBg = frame.bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetColorTexture(0, 0, 0, 0.5)
  frame.barText = fs(frame.bar, "GameFontHighlightSmall")
  frame.barText:SetPoint("CENTER")

  local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  reset:SetSize(96, 18)
  reset:SetPoint("BOTTOMLEFT", 8, 7)
  reset:SetText(L["Reset session"])
  reset:SetScript("OnClick", function() SC.ResetSession(); Core.Print(L["session reset."]) end)
  frame.reset = reset

  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture(GRIP)
  grip:SetScript("OnMouseDown", function() if not settings.locked then frame:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    settings.width = math.floor(frame:GetWidth() + 0.5)
    settings.height = math.floor(frame:GetHeight() + 0.5)
  end)

  -- Trance glow: the whole box pulses violet-white while Shadow Trance is up, then clears
  frame.flash = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  frame.flash:SetPoint("TOPLEFT", 3, -3)
  frame.flash:SetPoint("BOTTOMRIGHT", -3, 3)
  frame.flash:SetBlendMode("ADD")
  frame.flash:SetAlpha(0)

  UI.ApplyLayout()
  UI.Place()
  UI.ApplyTheme(SC.theme)
  UI.UpdateVisibility()
  UI.Refresh()
  return frame
end

function UI.Frame() return frame end

-- While the Trance is up: a steady pulse between 0.25 and 0.6 alpha. A spent bolt: one short fade.
local pulse, fadeLeft = 0, 0
local function glowTick(_, elapsed)
  if SC.tranceUp then
    pulse = pulse + elapsed
    frame.flash:SetAlpha(0.425 + 0.175 * math.sin(pulse * 6))
    return
  end
  fadeLeft = fadeLeft - elapsed
  if fadeLeft <= 0 then frame.flash:SetAlpha(0); frame:SetScript("OnUpdate", nil) return end
  frame.flash:SetAlpha(0.5 * fadeLeft / 0.4)
end

function UI.OnTrance(up)
  if not frame then return end
  if up then
    pulse = 0
    frame.head:SetText(L["NIGHTFALL!"])
    frame.flash:SetAlpha(0.6)
    frame:SetScript("OnUpdate", glowTick)
  elseif frame.head:GetText() == L["NIGHTFALL!"] then
    frame.head:SetText(L["Trance faded"])
    fadeLeft = 0
  end
  UI.Refresh()
end

function UI.OnSpent()
  if not frame then return end
  frame.head:SetText(L["INSTANT SHADOW BOLT!"])
  fadeLeft = 0.4
  frame.flash:SetAlpha(0.5)
  frame:SetScript("OnUpdate", glowTick)
  UI.Refresh()
end

function UI.OnCombat(inCombat)
  if frame then frame.reset:SetShown(not inCombat) end -- no Reset button in combat
  if inCombat and not ticker then
    ticker = C_Timer.NewTicker(0.5, function() Core.SafeCall("live", UI.RenderLive) end)
  elseif not inCombat and ticker then
    ticker:Cancel(); ticker = nil
  end
  UI.Refresh()
end

-- Plain-number view (out of combat): last fight + session.
function UI.Lines()
  local f, s = SC.lastFight, SC.SessionStats() or {}
  local out = {}
  local cur = f or SC.fight
  out[#out + 1] = ("%s: %d %s, %d %s"):format(L["Fight"], cur.gained, L["Trances"], cur.spent, L["instant bolts"])
  if f and f.sb then
    out[#out + 1] = ("%s: %s (%s), %s %s%s"):format(L["Shadow Bolt"], SC.Short(f.sb), SC.Pct(f.share), L["avg"],
      f.avg and SC.Short(f.avg) or "-", f.record and ("  |cffffd200" .. L["new best!"] .. "|r") or "")
  end
  out[#out + 1] = ("%s: %d %s, %d %s (%s)"):format(L["Session"], s.gained or 0, L["Trances"], s.spent or 0, L["instant"], SC.Pct(s.share))
  out[#out + 1] = ("%s: %s   %s: %s"):format(L["Avg bolt"], s.avg and SC.Short(s.avg) or "-", L["Best avg"], (s.bestAvg or 0) > 0 and SC.Short(s.bestAvg) or "-")
  if db and db.meterSplits == false then out[#out + 1] = "|cffaaaaaa" .. L["No Shadow Bolt meter line: counting procs only."] .. "|r" end
  return out
end

function UI.Refresh()
  if not frame then return end
  if SC.fight.inCombat then UI.RenderLive() return end
  if not frame.head:GetText() or frame.head:GetText() == "" then frame.head:SetText(L["Waiting for Nightfall..."]) end
  frame.lines:SetText(table.concat(UI.Lines(), "\n"))
  local f = SC.lastFight
  local share = f and f.share or (SC.SessionStats() or {}).share
  frame.bar:SetMinMaxValues(0, 1)
  frame.bar:SetValue(share or 0)
  frame.barText:SetText(L["Shadow Bolt share"] .. " " .. SC.Pct(share))
end

-- Live view (in combat). Counts are plain; damage values may be secret and are only handed to widgets.
function UI.RenderLive()
  if not frame then return end
  local f = SC.fight
  local head = ("%s: %d %s, %d %s"):format(L["Fight"], f.gained, L["Trances"], f.spent, L["instant"])
  local src = SC.LiveSource and SC.LiveSource()
  local total = src and src.totalAmount
  if total ~= nil and AbbreviateNumbers then
    frame.lines:SetFormattedText("%s\n%s: %s\n%s", head, L["You"], AbbreviateNumbers(total), L["Shadow Bolt share after combat"])
  else
    frame.lines:SetText(head)
  end
end

UI.MIN_W, UI.MIN_H, UI.MAX_W, UI.MAX_H = MIN_W, MIN_H, MAX_W, MAX_H

-- ---------- slash command (names live in ns.SLASH, top of ShadowCount.lua) ----------
local function help()
  local c = ns.SLASH[1]
  Core.Print(c .. " show | hide | lock | unlock | resetpos | scale 0.5-2 | size <w> <h> | reset | test")
  Core.Print(c .. " sound every|record|off  |  soundfile theme|trance|shadow|curse")
  Core.Print(c .. " meter (last fight's damage-meter lines) | theme | debug | report")
end

for i, cmd in ipairs(ns.SLASH) do _G["SLASH_KENNYSHADOWCOUNT" .. i] = cmd end
SlashCmdList.KENNYSHADOWCOUNT = function(msg)
  if not (db and frame) then return end
  local cmd, a, b = (msg or ""):lower():match("^(%S*)%s*(%S*)%s*(%S*)")
  if cmd == "show" then
    settings.shown = true
    if not SC.ClassMatches() then Core.Print(L["this box only shows on a Warlock."]) end
    UI.UpdateVisibility(); UI.Refresh()
  elseif cmd == "hide" then settings.shown = false; UI.UpdateVisibility()
  elseif cmd == "lock" then settings.locked = true; Core.Print(L["frame locked."])
  elseif cmd == "unlock" then settings.locked = false; Core.Print(L["frame unlocked."])
  elseif cmd == "resetpos" then
    db.point = nil; settings.width, settings.height, settings.scale = SC.DEFAULTS.width, SC.DEFAULTS.height, 1
    UI.ApplyLayout(); UI.Place(); Core.Print(L["frame moved back to its default spot and size."])
  elseif cmd == "scale" and tonumber(a) then
    settings.scale = math.max(0.5, math.min(2, tonumber(a))); UI.ApplyLayout()
  elseif cmd == "size" and tonumber(a) and tonumber(b) then
    settings.width = math.max(MIN_W, math.min(MAX_W, math.floor(tonumber(a))))
    settings.height = math.max(MIN_H, math.min(MAX_H, math.floor(tonumber(b))))
    UI.ApplyLayout()
  elseif cmd == "reset" then SC.ResetSession(); Core.Print(L["session reset."])
  elseif cmd == "sound" and SC.SOUND_MODES[a] then settings.sound = a; Core.Print(L["sound:"] .. " " .. a)
  elseif cmd == "soundfile" and (a == "theme" or SC.SOUNDS[a]) then settings.soundFile = a; SC.Play()
  elseif cmd == "test" then
    if C.InCombat() then Core.Print(L["not in combat."]) return end
    frame.head:SetText(L["NIGHTFALL!"]); frame.flash:SetAlpha(0.6); fadeLeft = 0.8; frame:SetScript("OnUpdate", glowTick); SC.Play()
  elseif cmd == "theme" then
    local th = SC.UpdateTheme()
    Core.Print(L["theme"] .. ": " .. tostring(th.tree or L["class default"]))
  elseif cmd == "meter" then
    if C.InCombat() then Core.Print(L["not in combat."]) return end
    local r, why = SC.ReadMeter()
    if not r then Core.Print(L["no readable meter data"] .. " (" .. tostring(why) .. ")") return end
    Core.Print(("%s %s"):format(L["your damage:"], SC.Short(r.total)))
    for i = 1, math.min(8, #r.rows) do
      local row = r.rows[i]
      local name = C_Spell and C_Spell.GetSpellName and C.Safe(C_Spell.GetSpellName(row.spellID)) or "?"
      Core.Print(("  %d  %s  %s%s"):format(row.spellID, tostring(name), SC.Short(row.amount), SC.BOLTS[row.spellID] and "  <- Shadow Bolt" or ""))
    end
  elseif cmd == "debug" then Core.PrintDebug()
  elseif cmd == "report" then Core.ShowReport(SC.StateLines())
  else help() end
end
