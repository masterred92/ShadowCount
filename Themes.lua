-- Shadow Count theme: shadow purple, then the talent tree with the most points. Plain data, easy to tweak.
--   frame = border colour, title = title text, accent = bar, flash and highlights (hex RRGGBB), sound = built-in FileDataID.
-- A tree entry overrides only what it lists. Trees are keyed by the client's SkillLine ID (SkillLine table,
-- build 1.60.1.70862: Affliction 355, Demonology 354, Destruction 593). `order` is used when an ID isn't recognised.
-- Every sound and texture here was checked to exist in build 1.60.1.70862 (see tools/verify_media.sh).
local _, ns = ...

ns.THEME = { frame = "7A3FD0", title = "D9C2FF", accent = "B07CFF", sound = 568263, -- alert_wl_shadowtrance
  order = { 355, 354, 593 },
  trees = { [355] = { accent = "A060FF" },   -- Affliction: shadow violet
            [354] = { accent = "C08CFF" },   -- Demonology: fel lilac
            [593] = { accent = "8E6CFF" } } } -- Destruction: deep indigo
