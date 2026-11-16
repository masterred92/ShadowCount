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
local LOCKED, UNLOCKED = "Interface\\Buttons\\LockButton-Locked-Up", "Interface\\Buttons\\LockButton-Unlocked-Up" -- 525906, 525908
local GOLD = "|cffffd100" -- labels in the game's own gold, values in white
local BG, EDGE = "Interface\\Tooltips\\UI-Tooltip-Background", "Interface\\Tooltips\\UI-Tooltip-Border"
local MIN_W, MIN_H, MAX_W, MAX_H = 180, 120, 480, 300
UI.DEFAULT_POINT = { "CENTER", 0, -210 }

local function fs(parent, font)
  local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  f:SetJustifyH("LEFT")
  return f
end

-- "Fight: " in gold, so the numbers after it are easy to pick out
local function label(text) return GOLD .. text .. ":|r " end
local function trances(n) return n == 1 and L["Trance"] or L["Trances"] end

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

-- Padlock icon and resize grip follow the lock setting.
function UI.UpdateLock()
  if not frame then return end
  frame.lock.icon:SetTexture(settings.locked and LOCKED or UNLOCKED)
  frame.grip:SetShown(not settings.locked)
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
  -- padlock, top right: click to lock or unlock the box (same as the lock and unlock slash commands)
  local lock = CreateFrame("Button", nil, frame)
  lock:SetSize(16, 16)
  lock:SetPoint("TOPRIGHT", -7, -8)
  lock.icon = lock:CreateTexture(nil, "ARTWORK")
  lock.icon:SetAllPoints()
  lock.icon:SetTexCoord(6 / 32, 25 / 32, 7 / 32, 25 / 32) -- just the padlock, not the empty edge of the texture
  lock:SetScript("OnClick", function()
    settings.locked = not settings.locked
    UI.UpdateLock()
    Core.Print(settings.locked and L["frame locked."] or L["frame unlocked."])
  end)
  lock:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
    GameTooltip:SetText(settings.locked and L["Box locked"] or L["Box unlocked"])
    GameTooltip:AddLine(settings.locked and L["Click to unlock it."] or L["Drag the box to move it. Click to lock it."], 1, 1, 1, true)
    GameTooltip:Show()
  end)
  lock:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.lock = lock
  frame.tree = fs(frame, "GameFontDisableSmall")
  frame.tree:SetPoint("RIGHT", lock, "LEFT", -2, 0)
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
  frame.lines = fs(frame, "GameFontHighlight") -- 12 pt (was 10 pt)
  frame.lines:SetPoint("TOPLEFT", frame.head, "BOTTOMLEFT", 0, -4)
  frame.lines:SetPoint("RIGHT", -10, 0)
  frame.lines:SetJustifyV("TOP")
  frame.lines:SetSpacing(2)

  frame.bar = CreateFrame("StatusBar", nil, frame)
  frame.bar:SetStatusBarTexture(BAR)
  frame.bar:SetPoint("BOTTOMLEFT", 10, 29)
  frame.bar:SetPoint("BOTTOMRIGHT", -10, 29)
  frame.bar:SetHeight(12) -- was 10
  frame.lines:SetPoint("BOTTOM", frame.bar, "TOP", 0, 1) -- extra lines are cut off instead of running into the bar
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
  reset:SetShown(not C.InCombat()) -- a /reload in combat gets no PLAYER_REGEN_DISABLED, so start hidden

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
  frame.grip = grip

  -- Trance glow: the whole box pulses violet-white while Shadow Trance is up, then clears
  frame.flash = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  frame.flash:SetPoint("TOPLEFT", 3, -3)
  frame.flash:SetPoint("BOTTOMRIGHT", -3, 3)
  frame.flash:SetBlendMode("ADD")
  frame.flash:SetAlpha(0)

  UI.ApplyLayout()
  UI.Place()
  UI.ApplyTheme(SC.theme)
  UI.UpdateLock()
  UI.UpdateVisibility()
  UI.Refresh()
  return frame
end

function UI.Frame() return frame end

-- While the Trance is up: a gentle pulse between 0.10 and 0.20 alpha (was 0.25-0.6). At the 0.20 peak, white text
-- is at least 7:1 and the gold labels at least 5:1 (WCAG) on the glow, even over a bright world. A spent bolt: one short fade.
local GLOW_MID, GLOW_SWING, GLOW_FADE = 0.15, 0.05, 0.20

-- The headline counts down the Trance ("NIGHTFALL!  7s"). Time left comes from the aura's expirationTime when the
-- game lets us read it, else from our own clock at the gain (the Trance lasts 10 seconds). Buff data can be hidden or
-- secret in combat on this client, so every read is guarded; when nothing is readable the headline is plain "NIGHTFALL!".
local pulse, fadeLeft, tranceEnds, shownSecs, sinceRead = 0, 0, nil, nil, 0

local function clock()
  local ok, t = pcall(C.Clock)
  t = ok and C.SafeNumber(t) or nil
  if t and t == t then return t end -- t == t rules out NaN
  return nil
end

local function auraTimeLeft(now)
  if not now or not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
  local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, SC.TRANCE)
  if not ok or type(aura) ~= "table" or C.IsSecret(aura) then return nil end
  local ok2, exp = pcall(function() return aura.expirationTime end)
  exp = ok2 and C.SafeNumber(exp) or nil
  if not exp or exp ~= exp or exp <= 0 then return nil end -- 0 = no expiry (or hidden)
  local left = exp - now
  if left <= 0 or left > 60 then return nil end
  return left
end

-- Seconds left (a positive number), or nil when it can't be told.
function UI.TranceTimeLeft()
  local now = clock()
  local left = auraTimeLeft(now)
  if left then return left end
  if now and tranceEnds and tranceEnds - now > 0 then return tranceEnds - now end
  return nil
end

local function showTranceHead()
  local left = UI.TranceTimeLeft()
  local secs = left and math.ceil(left) or nil
  if secs == shownSecs then return end
  shownSecs = secs
  frame.head:SetText(secs and ("%s  %ds"):format(L["NIGHTFALL!"], secs) or L["NIGHTFALL!"])
end

-- While the glow is on, the headline uses the light title colour instead of the accent, so it reads on the glow.
local function headColour(onGlow)
  local th = SC.theme
  if th then frame.head:SetTextColor(unpack(onGlow and th.title or th.accent)) end
end

local function glowTick(_, elapsed)
  if SC.tranceUp then
    pulse = pulse + elapsed
    frame.flash:SetAlpha(GLOW_MID + GLOW_SWING * math.sin(pulse * 6))
    sinceRead = sinceRead + elapsed
    if sinceRead >= 0.2 then sinceRead = 0; showTranceHead() end -- 5 reads a second is plenty for whole seconds
    return
  end
  fadeLeft = fadeLeft - elapsed
  if fadeLeft <= 0 then frame.flash:SetAlpha(0); headColour(false); frame:SetScript("OnUpdate", nil) return end
  frame.flash:SetAlpha(GLOW_FADE * fadeLeft / 0.4)
end

function UI.OnTrance(up)
  if not frame then return end
  if up then
    local now = clock()
    pulse, sinceRead, shownSecs = 0, 0, false -- false = nothing shown yet (nil means "no countdown")
    tranceEnds = now and now + SC.TRANCE_SECONDS or nil
    showTranceHead()
    headColour(true)
    frame.flash:SetAlpha(GLOW_MID + GLOW_SWING)
    frame:SetScript("OnUpdate", glowTick)
  else
    tranceEnds = nil
    if (frame.head:GetText() or ""):find(L["NIGHTFALL!"], 1, true) then
      frame.head:SetText(L["Trance faded"])
      fadeLeft = 0
    end
  end
  UI.Refresh()
end

function UI.OnSpent()
  if not frame then return end
  frame.head:SetText(L["INSTANT SHADOW BOLT!"])
  fadeLeft = 0.4
  frame.flash:SetAlpha(GLOW_FADE)
  frame:SetScript("OnUpdate", glowTick)
  UI.Refresh()
end

function UI.OnCombat(inCombat)
  if frame then
    frame.reset:SetShown(not inCombat) -- no Reset button in combat
    if inCombat and not SC.tranceUp then frame.head:SetText(L["Waiting for Nightfall..."]) end -- a fresh headline for each fight
  end
  if inCombat and not ticker then
    ticker = C_Timer.NewTicker(0.5, function() Core.SafeCall("live", UI.RenderLive) end)
  elseif not inCombat and ticker then
    ticker:Cancel(); ticker = nil
  end
  UI.Refresh()
end

-- Plain-number view (out of combat): last fight + session, one short line each. Labels gold, numbers white.
function UI.Lines()
  local f, s = SC.lastFight, SC.SessionStats() or {}
  local countOnly = db and db.meterSplits == false
  if not f and (s.gained or 0) == 0 and (s.fights or 0) == 0 and SC.fight.gained == 0 then
    return { L["No fights yet."], "|cffaaaaaa" .. L["Fight with Nightfall talented and the Trances show up here."] .. "|r" }
  end
  local out = {}
  local cur = f or SC.fight
  out[#out + 1] = label(L["Fight"]) .. ("%d %s · %d %s"):format(cur.gained, trances(cur.gained), cur.spent, L["instant"])
  if f and f.sb then
    -- a record shows "new best!" instead of the average (the new best is on the "Avg bolt" line below)
    out[#out + 1] = label(L["Shadow Bolt"]) .. ("%s · %s"):format(SC.Short(f.sb), SC.Pct(f.share))
      .. (f.record and ("  |cffffd200" .. L["new best!"] .. "|r") or (" · %s %s"):format(L["avg"], f.avg and SC.Short(f.avg) or "-"))
  end
  if countOnly then
    out[#out + 1] = label(L["Session"]) .. ("%d %s · %d %s"):format(s.gained or 0, trances(s.gained or 0), s.spent or 0, L["instant"])
    out[#out + 1] = "|cffaaaaaa" .. L["No Shadow Bolt meter line: counting procs only."] .. "|r"
  else
    out[#out + 1] = label(L["Session"]) .. ("%d %s · %d %s · %s"):format(s.gained or 0, trances(s.gained or 0), s.spent or 0, L["instant"], SC.Pct(s.share))
    out[#out + 1] = label(L["Avg bolt"]) .. ("%s · %s %s"):format(s.avg and SC.Short(s.avg) or "-", L["best"],
      (s.bestAvg or 0) > 0 and SC.Short(s.bestAvg) or "-")
  end
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
  local head = label(L["Fight"]) .. ("%d %s · %d %s"):format(f.gained, trances(f.gained), f.spent, L["instant"])
  local src = SC.LiveSource and SC.LiveSource()
  local total = src and src.totalAmount
  if total ~= nil and AbbreviateNumbers then
    -- plain white here (not grey): this text can sit on the Trance glow
    frame.lines:SetFormattedText("%s\n%s%s\n%s", head, label(L["You"]), AbbreviateNumbers(total), L["Shadow Bolt share after combat"])
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
  elseif cmd == "lock" then settings.locked = true; UI.UpdateLock(); Core.Print(L["frame locked."])
  elseif cmd == "unlock" then settings.locked = false; UI.UpdateLock(); Core.Print(L["frame unlocked."])
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
    frame.head:SetText(L["NIGHTFALL!"]); headColour(true); frame.flash:SetAlpha(GLOW_MID + GLOW_SWING); fadeLeft = 0.8; frame:SetScript("OnUpdate", glowTick); SC.Play()
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
