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
-- 1.1.0 state, declared up here because the theme, layout and Trance code below all read it
local draining = false -- frame.bar is the 10s Trance drain bar (not the Shadow Bolt share bar)
local preview = nil    -- { left = seconds } while the /shc test preview runs
local hovering = false -- the mouse is over the box (or one of its buttons)
local ICON = "Interface\\Icons\\Spell_Shadow_Twilight" -- 136223, Shadow Trance's own icon
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local LOCKED, UNLOCKED = "Interface\\Buttons\\LockButton-Locked-Up", "Interface\\Buttons\\LockButton-Unlocked-Up" -- 525906, 525908
local GOLD = "|cffffd100" -- labels in the game's own gold, values in white
local BG, EDGE = "Interface\\Tooltips\\UI-Tooltip-Background", "Interface\\Tooltips\\UI-Tooltip-Border"
local MIN_W, MIN_H, MAX_W, MAX_H = 180, 120, 480, 300
local FADE_ALPHA = 0.35 -- idle fade: out of combat the box rests at 35% alpha
local COMPACT_H = 60    -- compact mode: one strip (headline + instant count, then the bar)
local DRAIN_R, DRAIN_G, DRAIN_B = 0.92, 0.84, 1 -- the Trance drain bar: bright violet-white
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
  if not draining then frame.bar:SetStatusBarColor(ar, ag, ab) end -- the drain bar keeps its violet-white
  frame.flash:SetColorTexture(0.85, 0.75, 1, 1) -- violet-white
  frame.head:SetTextColor(ar, ag, ab)
  frame.rule:SetColorTexture(fr, fg, fb, 0.9)
  frame.tree:SetText(th.tree or "")
end

-- Padlock icon and resize grip follow the lock setting (no grip in compact mode: the strip keeps its fixed height).
function UI.UpdateLock()
  if not frame then return end
  frame.lock.icon:SetTexture(settings.locked and LOCKED or UNLOCKED)
  frame.grip:SetShown(not settings.locked and not settings.compact)
  UI.UpdateMouse()
end

-- Layout and mouse changes. The box is a plain (non-secure) frame, so they are safe at any time; if it were ever
-- protected (say a secure parent), they wait for the end of combat instead of tainting anything.
local function mustWait()
  if C.InCombat() and frame:IsProtected() then UI.layoutPending = true return true end
  return false
end

-- Click-through: only while the box is locked AND the setting is on. The padlock and Reset button stop taking clicks
-- too, so a click really lands on the world; /shc unlock or /shc clickthrough gives clicks back.
function UI.ClickThroughActive() return settings.locked == true and settings.clickThrough == true end
function UI.UpdateMouse()
  if not frame or mustWait() then return end
  local through = UI.ClickThroughActive()
  frame:EnableMouse(not through)
  frame.lock:EnableMouse(not through)
  frame.reset:EnableMouse(not through)
  if through then hovering = false; UI.UpdateAlpha() end
end

-- Full layout, or compact: one strip with the headline, the instant-bolt count and the bar. Compact never writes
-- settings.width / settings.height, so switching back restores the saved full size.
function UI.ApplyLayout()
  if not frame then return false end
  if mustWait() then return false end
  UI.layoutPending = false
  local compact = settings.compact == true
  local h = compact and COMPACT_H or settings.height
  frame:SetScale(settings.scale)
  frame:SetResizeBounds(MIN_W, compact and COMPACT_H or MIN_H, MAX_W, compact and COMPACT_H or MAX_H)
  frame:SetSize(settings.width, h)
  for _, w in ipairs({ frame.icon, frame.title, frame.tree, frame.rule, frame.lines }) do w:SetShown(not compact) end
  frame.count:SetShown(compact)
  frame.reset:SetShown(not compact and not C.InCombat())
  frame.head:ClearAllPoints()
  frame.bar:ClearAllPoints()
  if compact then
    frame.head:SetPoint("TOPLEFT", 10, -9)
    frame.head:SetPoint("RIGHT", frame.count, "LEFT", -6, 0)
    frame.bar:SetPoint("BOTTOMLEFT", 10, 10)
    frame.bar:SetPoint("BOTTOMRIGHT", -10, 10)
  else
    frame.head:SetPoint("TOPLEFT", 10, -33)
    frame.head:SetPoint("RIGHT", -10, 0)
    frame.bar:SetPoint("BOTTOMLEFT", 10, 29)
    frame.bar:SetPoint("BOTTOMRIGHT", -10, 29)
  end
  UI.UpdateLock()
  return true
end

-- Idle fade: 35% out of combat; full in combat, under the mouse, while a Trance is up and during the test preview.
-- SetAlpha on our own non-secure frame is fine in combat.
function UI.TargetAlpha()
  if not settings.fade then return 1 end
  if SC.fight.inCombat or C.InCombat() then return 1 end
  if hovering or SC.tranceUp or preview then return 1 end
  return FADE_ALPHA
end
function UI.UpdateAlpha()
  if frame then frame:SetAlpha(UI.TargetAlpha()) end
end
local function hoverCheck()
  hovering = frame:IsMouseOver() == true and not UI.ClickThroughActive()
  UI.UpdateAlpha()
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
  frame:SetScript("OnEnter", function() hovering = true; UI.UpdateAlpha() end)
  frame:SetScript("OnLeave", hoverCheck)
  -- right-click: the quick menu (out of combat only; see UI.OpenMenu)
  frame:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then UI.OpenMenu(self) end end)
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
  frame.icon = icon
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
  lock:SetScript("OnClick", function() UI.SetLocked(not settings.locked) end)
  lock:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
    GameTooltip:SetText(settings.locked and L["Box locked"] or L["Box unlocked"])
    GameTooltip:AddLine(settings.locked and L["Click to unlock it."] or L["Drag the box to move it. Click to lock it."], 1, 1, 1, true)
    GameTooltip:AddLine(L["Right-click the box for quick options."], 1, 1, 1, true)
    if settings.clickThrough then -- the padlock can't be clicked once click-through is active, so say how to undo it
      GameTooltip:AddLine(UI.ClickThroughNote(), 1, 0.82, 0, true)
    end
    GameTooltip:Show()
  end)
  lock:SetScript("OnLeave", function() GameTooltip:Hide(); hoverCheck() end)
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
  -- compact mode only: the instant-bolt count, right of the headline
  frame.count = fs(frame, "GameFontHighlight")
  frame.count:SetPoint("RIGHT", lock, "LEFT", -6, 0)
  frame.count:SetJustifyH("RIGHT")
  frame.count:Hide()

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
  reset:HookScript("OnLeave", hoverCheck)
  frame.reset = reset
  reset:SetShown(not C.InCombat()) -- a /reload in combat gets no PLAYER_REGEN_DISABLED, so start hidden

  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture(GRIP)
  grip:SetScript("OnMouseDown", function() if not settings.locked then frame:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnLeave", hoverCheck)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    if settings.compact then return end -- the saved full size only changes in the full layout
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

  UI.ApplyLayout() -- also sets the padlock, grip and click-through
  UI.Place()
  UI.ApplyTheme(SC.theme)
  UI.UpdateVisibility()
  UI.Refresh()
  UI.UpdateAlpha()
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
  if SC.mode == "none" then return nil end -- a Trance this client hides from us never gets a countdown
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

-- ---------- the 10s Trance drain bar ----------
-- While a seen Trance is up ("aura" or "cast" mode, never "none") or the /shc test preview runs, frame.bar drains
-- from 10 seconds to 0 in violet-white with "NIGHTFALL! 6.2s" on it; then the Shadow Bolt share bar comes back.
-- The time left is UI.TranceTimeLeft() (the aura's expirationTime, else our own clock from the gain); when no time
-- can be read the bar stays full with a plain "NIGHTFALL!" instead of a made-up countdown.
local drainText
local function drainState()
  if SC.tranceUp and SC.mode ~= "none" then return true, UI.TranceTimeLeft() end
  if preview then return true, math.max(0, preview.left) end
  return false
end

local function updateDrain()
  if not frame then return end
  local active, left = drainState()
  if active then
    if not draining then
      draining, drainText = true, nil
      frame.bar:SetStatusBarColor(DRAIN_R, DRAIN_G, DRAIN_B)
      frame.bar:SetMinMaxValues(0, SC.TRANCE_SECONDS)
    end
    frame.bar:SetValue(left and math.min(left, SC.TRANCE_SECONDS) or SC.TRANCE_SECONDS)
    local text = left and ("%s %.1fs"):format(L["NIGHTFALL!"], left) or L["NIGHTFALL!"]
    if text ~= drainText then drainText = text; frame.barText:SetText(text) end
  elseif draining then
    draining, drainText = false, nil
    UI.RenderShareBar()
  end
end
function UI.Draining() return draining end
function UI.PreviewActive() return preview ~= nil end

local function previewHead()
  local secs = math.max(1, math.ceil(preview.left))
  if secs == shownSecs then return end
  shownSecs = secs
  frame.head:SetText(("%s  %ds"):format(L["NIGHTFALL!"], secs))
end

-- The /shc test preview ends after 10s, when combat starts or when a real Trance shows up.
function UI.StopPreview()
  if not preview then return end
  preview = nil
  if not SC.tranceUp then frame.head:SetText(L["Trance faded"]); fadeLeft = 0.4 end -- the glow fades out in glowTick
  updateDrain()
  UI.UpdateAlpha()
end

local function glowTick(_, elapsed)
  if preview and not SC.tranceUp then
    preview.left = preview.left - elapsed
    if preview.left <= 0 then UI.StopPreview() end
  end
  if SC.tranceUp or preview then
    pulse = pulse + elapsed
    frame.flash:SetAlpha(GLOW_MID + GLOW_SWING * math.sin(pulse * 6))
    sinceRead = sinceRead + elapsed
    if sinceRead >= 0.2 then -- 5 reads a second is plenty for whole seconds
      sinceRead = 0
      if SC.tranceUp then showTranceHead() else previewHead() end
    end
    updateDrain() -- every frame, so the bar drains smoothly
    return
  end
  fadeLeft = fadeLeft - elapsed
  if fadeLeft <= 0 then frame.flash:SetAlpha(0); headColour(false); frame:SetScript("OnUpdate", nil) return end
  frame.flash:SetAlpha(GLOW_FADE * fadeLeft / 0.4)
end

-- /shc test: the whole Trance look for 10 seconds (glow, countdown, drain bar, sound), out of combat only.
function UI.StartPreview()
  if not frame or C.InCombat() then return false end
  preview = { left = SC.TRANCE_SECONDS }
  pulse, sinceRead, shownSecs = 0, 0, false
  previewHead()
  headColour(true)
  frame.flash:SetAlpha(GLOW_MID + GLOW_SWING)
  frame:SetScript("OnUpdate", glowTick)
  updateDrain()
  UI.UpdateAlpha()
  SC.Play()
  return true
end

function UI.OnTrance(up)
  if not frame then return end
  if up then
    preview = nil -- a real Trance replaces the preview
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
  updateDrain()
  UI.UpdateAlpha()
  UI.Refresh()
end

function UI.OnSpent()
  if not frame then return end
  frame.head:SetText(L["INSTANT SHADOW BOLT!"])
  fadeLeft = 0.4
  frame.flash:SetAlpha(GLOW_FADE)
  frame:SetScript("OnUpdate", glowTick)
  updateDrain()
  UI.Refresh()
end

function UI.OnCombat(inCombat)
  if frame then
    if inCombat then UI.StopPreview() end -- the box goes live; the preview never runs in a fight
    frame.reset:SetShown(not inCombat and not settings.compact) -- no Reset button in combat (or in compact mode)
    if inCombat and not SC.tranceUp then frame.head:SetText(L["Waiting for Nightfall..."]) end -- a fresh headline for each fight
  end
  if inCombat and not ticker then
    ticker = C_Timer.NewTicker(0.5, function() Core.SafeCall("live", UI.RenderLive) end)
  elseif not inCombat and ticker then
    ticker:Cancel(); ticker = nil
  end
  if not inCombat and UI.layoutPending then UI.ApplyLayout() end
  UI.UpdateAlpha()
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
  local hidden = SC.mode == "none" -- gains can't be seen on this client: show instant bolts only
  if hidden then
    out[#out + 1] = label(L["Fight"]) .. ("%d %s"):format(cur.spent, L["instant"])
  else
    out[#out + 1] = label(L["Fight"]) .. ("%d %s · %d %s"):format(cur.gained, trances(cur.gained), cur.spent, L["instant"])
  end
  if f and f.sb then
    -- a record shows "new best!" instead of the average (the new best is on the "Avg bolt" line below)
    out[#out + 1] = label(L["Shadow Bolt"]) .. ("%s · %s"):format(SC.Short(f.sb), SC.Pct(f.share))
      .. (f.record and ("  |cffffd200" .. L["new best!"] .. "|r") or (" · %s %s"):format(L["avg"], f.avg and SC.Short(f.avg) or "-"))
  end
  if countOnly then
    out[#out + 1] = hidden and label(L["Session"]) .. ("%d %s"):format(s.spent or 0, L["instant"])
      or label(L["Session"]) .. ("%d %s · %d %s"):format(s.gained or 0, trances(s.gained or 0), s.spent or 0, L["instant"])
    out[#out + 1] = "|cffaaaaaa" .. L["No Shadow Bolt meter line: counting procs only."] .. "|r"
  else
    out[#out + 1] = hidden and label(L["Session"]) .. ("%d %s · %s"):format(s.spent or 0, L["instant"], SC.Pct(s.share))
      or label(L["Session"]) .. ("%d %s · %d %s · %s"):format(s.gained or 0, trances(s.gained or 0), s.spent or 0, L["instant"], SC.Pct(s.share))
    out[#out + 1] = label(L["Avg bolt"]) .. ("%s · %s %s"):format(s.avg and SC.Short(s.avg) or "-", L["best"],
      (s.bestAvg or 0) > 0 and SC.Short(s.bestAvg) or "-")
  end
  if hidden then
    out[#out + 1] = "|cffaaaaaa" .. L["This client hides Shadow Trance from addons: instant Shadow Bolts are counted, Trances gained are not."] .. "|r"
  end
  return out
end

function UI.Refresh()
  if not frame then return end
  if SC.fight.inCombat then UI.RenderLive() return end
  if not frame.head:GetText() or frame.head:GetText() == "" then frame.head:SetText(L["Waiting for Nightfall..."]) end
  frame.lines:SetText(table.concat(UI.Lines(), "\n"))
  frame.count:SetText(UI.CountText())
  if not draining then UI.RenderShareBar() end
end

-- The normal bar: last fight's (else the session's) Shadow Bolt share, in the theme accent.
function UI.RenderShareBar()
  if not frame then return end
  local th = SC.theme
  if th then frame.bar:SetStatusBarColor(unpack(th.accent)) end
  local f = SC.lastFight
  local share = f and f.share or (SC.SessionStats() or {}).share
  frame.bar:SetMinMaxValues(0, 1)
  frame.bar:SetValue(share or 0)
  frame.barText:SetText(L["Shadow Bolt share"] .. " " .. SC.Pct(share))
end

-- Compact mode's count: instant Shadow Bolts this fight (in combat), else last fight.
function UI.CountText()
  local f = SC.fight.inCombat and SC.fight or SC.lastFight or SC.fight
  return ("%d %s"):format(f.spent or 0, L["instant"])
end

-- Live view (in combat). Counts are plain; damage values may be secret and are only handed to widgets.
function UI.RenderLive()
  if not frame then return end
  local f = SC.fight
  frame.count:SetText(UI.CountText())
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
UI.FADE_ALPHA, UI.COMPACT_H, UI.DRAIN_COLOR = FADE_ALPHA, COMPACT_H, { DRAIN_R, DRAIN_G, DRAIN_B }

function UI.ClickThroughNote()
  local c = ns.SLASH[1]
  return L["Click-through: while the box is locked, clicks pass through it. Type %s unlock or %s clickthrough to click it again."]:format(c, c)
end

function UI.SetLocked(v)
  settings.locked = v and true or false
  UI.UpdateLock()
  Core.Print(settings.locked and L["frame locked."] or L["frame unlocked."])
  if UI.ClickThroughActive() then Core.Print(UI.ClickThroughNote()) end
end

local function onOff(v) return v and L["on"] or L["off"] end

-- ---------- slash command (names live in ns.SLASH, top of ShadowCount.lua) ----------
local function help()
  local c = ns.SLASH[1]
  Core.Print(c .. " show | hide | lock | unlock | resetpos | scale 0.5-2 | size <w> <h> | reset | test")
  Core.Print(c .. " sound every|record|off  |  soundfile theme|trance|shadow|curse")
  Core.Print(c .. " fade | compact | clickthrough | menu  (" .. L["right-click the box for the same quick menu"] .. ")")
  Core.Print(UI.ClickThroughNote())
  Core.Print(c .. " meter (last fight's damage-meter lines) | theme | debug | report")
end

local function handle(msg)
  if not (db and frame) then return end
  local cmd, a, b = (msg or ""):lower():match("^(%S*)%s*(%S*)%s*(%S*)")
  if cmd == "show" then
    settings.shown = true
    if not SC.ClassMatches() then Core.Print(L["this box only shows on a Warlock."]) end
    UI.UpdateVisibility(); UI.Refresh()
  elseif cmd == "hide" then settings.shown = false; UI.UpdateVisibility()
  elseif cmd == "lock" then UI.SetLocked(true)
  elseif cmd == "unlock" then UI.SetLocked(false)
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
  elseif cmd == "fade" then
    settings.fade = not settings.fade; UI.UpdateAlpha()
    Core.Print(L["idle fade:"] .. " " .. onOff(settings.fade))
  elseif cmd == "compact" then
    settings.compact = not settings.compact; UI.ApplyLayout(); UI.Refresh()
    Core.Print(L["compact mode:"] .. " " .. onOff(settings.compact))
  elseif cmd == "clickthrough" then
    settings.clickThrough = not settings.clickThrough; UI.UpdateMouse()
    Core.Print(L["click-through when locked:"] .. " " .. onOff(settings.clickThrough))
    if settings.clickThrough then Core.Print(UI.ClickThroughNote()) end
  elseif cmd == "menu" then
    if not UI.OpenMenu(frame) and C.InCombat() then Core.Print(L["not in combat."]) end
  elseif cmd == "test" then
    if not UI.StartPreview() then Core.Print(L["not in combat."]) end
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

for i, cmd in ipairs(ns.SLASH) do _G["SLASH_KENNYSHADOWCOUNT" .. i] = cmd end
SlashCmdList.KENNYSHADOWCOUNT = handle

-- ---------- right-click quick menu ----------
-- Blizzard's own context menu (MenuUtil, Blizzard_Menu). It only opens out of combat, and every entry checks again
-- when clicked, so a menu left open into a fight does nothing. Each entry runs the matching slash command.
local function act(msg) return function() if not C.InCombat() then handle(msg) end end end

function UI.BuildMenu(_, root)
  root:CreateTitle("Shadow Count")
  local sound = root:CreateButton(L["Sound"])
  for _, m in ipairs({ { "every", L["Every Trance"] }, { "record", L["New best average only"] }, { "off", L["Off"] } }) do
    sound:CreateRadio(m[2], function() return settings.sound == m[1] end, act("sound " .. m[1]))
  end
  local file = root:CreateButton(L["Sound file"])
  for _, m in ipairs({ { "theme", L["Theme"] }, { "trance", L["Shadow Trance"] }, { "shadow", L["Shadow"] }, { "curse", L["Curse"] } }) do
    file:CreateRadio(m[2], function() return settings.soundFile == m[1] end, act("soundfile " .. m[1]))
  end
  root:CreateDivider()
  root:CreateCheckbox(L["Idle fade out of combat"], function() return settings.fade == true end, act("fade"))
  root:CreateCheckbox(L["Compact mode"], function() return settings.compact == true end, act("compact"))
  root:CreateCheckbox(L["Locked"], function() return settings.locked == true end,
    function() if not C.InCombat() then handle(settings.locked and "unlock" or "lock") end end)
  root:CreateCheckbox(L["Click-through when locked"], function() return settings.clickThrough == true end, act("clickthrough"))
  root:CreateDivider()
  root:CreateButton(L["Test preview"], act("test"))
  root:CreateButton(L["Reset session"], act("reset"))
  root:CreateButton(L["Reset position"], act("resetpos"))
end

-- Returns true when the menu opened. In combat, or without Blizzard's menu, nothing happens (no error, no taint).
function UI.OpenMenu(owner)
  if not frame or C.InCombat() then return false end
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    Core.Print(L["no quick menu on this client; type"] .. " " .. ns.SLASH[1] .. " " .. L["for the commands."])
    return false
  end
  return (Core.SafeCall("menu", MenuUtil.CreateContextMenu, owner or frame, UI.BuildMenu))
end
