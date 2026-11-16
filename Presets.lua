-- SpatialPlates Presets.lua
-- Theme presets as partial profile tables. Each preset only sets safe visual
-- values (fonts, colors, anchors, sizes, toggles) — never combat data.
-- Applying a preset merges its values onto the active profile and refreshes
-- all overlays live. No other addon is required or referenced.

SpatialPlates = SpatialPlates or {}
local SP = SpatialPlates

-- Preset definitions. Keys match the profile schema in Config.lua.
local PRESETS = {
  ["Default"] = {
    enabled = true,
    showDistance = true, showSubzone = true,
    showIndoors = false, showUnderwater = false, showBearing = false,
    filter = "all",
    font = "default", customFontPath = "", fontSize = 11,
    fontOutline = "outline",
    fontColor = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 },
    fontAlpha = 1.0, colorMode = "custom",
    formats = { distance = "{d}y", subzone = "{zone}", indoors = "{env}", underwater = "{water}", bearing = "{dir}", combined = "{d}y | {zone}" },
    sameSubzoneText = "Same map",
    bgEnabled = true, bgColor = { r = 0, g = 0, b = 0, a = 0.45 },
    bgTexture = "Interface\\Buttons\\WHITE8x8", bgEdgeSize = 1, bgInset = 1,
    borderEnabled = false, borderColor = { r = 1, g = 1, b = 1, a = 1 },
    borderTexture = "Interface\\Buttons\\WHITE8x8", borderEdgeSize = 1,
    borderFile = "Interface\\Buttons\\WHITE8x8",
    anchor = "TOP", anchorTo = "TOP", offsetX = 0, offsetY = 4,
    scale = 1.0, width = 120, height = 16, padding = 2,
    strata = "MEDIUM", frameLevel = 10, clampToScreen = true,
    hideInCombat = false, hideOutOfCombat = false,
    hideWhenNameplateHidden = true, hideWhenUnitNotVisible = true,
    hideBeyondDistance = false, maxDistance = 60,
    hideInInstances = false, hideInOpenWorld = false,
  },

  ["Minimal"] = {
    enabled = true,
    showDistance = true, showSubzone = false,
    showIndoors = false, showUnderwater = false, showBearing = false,
    filter = "all",
    font = "default", fontSize = 10, fontOutline = "outline",
    fontColor = { r = 1, g = 1, b = 1, a = 1 }, fontAlpha = 0.9,
    colorMode = "custom",
    formats = { distance = "{d}y", subzone = "{zone}", indoors = "{env}", underwater = "{water}", bearing = "{dir}", combined = "{d}y" },
    sameSubzoneText = "Same map",
    bgEnabled = false, borderEnabled = false,
    anchor = "TOP", anchorTo = "TOP", offsetX = 0, offsetY = 2,
    scale = 1.0, width = 60, height = 14, padding = 0,
    strata = "MEDIUM", frameLevel = 10, clampToScreen = true,
    hideInCombat = false, hideOutOfCombat = false,
    hideWhenNameplateHidden = true, hideWhenUnitNotVisible = true,
    hideBeyondDistance = false, maxDistance = 60,
    hideInInstances = false, hideInOpenWorld = false,
  },

  ["Plater-like"] = {
    -- Compact, dark, class-colored text above the nameplate. Visual only;
    -- does not require or interact with Plater.
    enabled = true,
    showDistance = true, showSubzone = true,
    showIndoors = false, showUnderwater = true, showBearing = false,
    filter = "all",
    font = "default", fontSize = 10, fontOutline = "outline",
    fontColor = { r = 1, g = 1, b = 1, a = 1 }, fontAlpha = 1.0,
    colorMode = "class",
    formats = { distance = "{d}y", subzone = "{zone}", indoors = "{env}", underwater = "{water}", bearing = "{dir}", combined = "{d}y | {zone}" },
    sameSubzoneText = "Same map",
    bgEnabled = true, bgColor = { r = 0, g = 0, b = 0, a = 0.55 },
    bgTexture = "Interface\\Buttons\\WHITE8x8", bgEdgeSize = 1, bgInset = 1,
    borderEnabled = false,
    anchor = "TOP", anchorTo = "TOP", offsetX = 0, offsetY = 6,
    scale = 1.0, width = 140, height = 16, padding = 2,
    strata = "MEDIUM", frameLevel = 10, clampToScreen = true,
    hideInCombat = false, hideOutOfCombat = false,
    hideWhenNameplateHidden = true, hideWhenUnitNotVisible = true,
    hideBeyondDistance = false, maxDistance = 80,
    hideInInstances = false, hideInOpenWorld = false,
  },

  ["ElvUI-like"] = {
    -- Thin, subtle, centered text with a faint backdrop. Visual only.
    enabled = true,
    showDistance = true, showSubzone = true,
    showIndoors = false, showUnderwater = false, showBearing = false,
    filter = "all",
    font = "default", fontSize = 11, fontOutline = "outline",
    fontColor = { r = 0.9, g = 0.9, b = 0.9, a = 1 }, fontAlpha = 1.0,
    colorMode = "custom",
    formats = { distance = "{d}y", subzone = "{zone}", indoors = "{env}", underwater = "{water}", bearing = "{dir}", combined = "{d}y | {zone}" },
    sameSubzoneText = "Same map",
    bgEnabled = true, bgColor = { r = 0, g = 0, b = 0, a = 0.35 },
    bgTexture = "Interface\\Buttons\\WHITE8x8", bgEdgeSize = 1, bgInset = 1,
    borderEnabled = false,
    anchor = "TOP", anchorTo = "TOP", offsetX = 0, offsetY = 4,
    scale = 1.0, width = 130, height = 15, padding = 2,
    strata = "MEDIUM", frameLevel = 10, clampToScreen = true,
    hideInCombat = false, hideOutOfCombat = false,
    hideWhenNameplateHidden = true, hideWhenUnitNotVisible = true,
    hideBeyondDistance = false, maxDistance = 60,
    hideInInstances = false, hideInOpenWorld = false,
  },

  ["TukUI-like"] = {
    -- Small square-ish backdrop, yellow-white text. Visual only.
    enabled = true,
    showDistance = true, showSubzone = true,
    showIndoors = false, showUnderwater = false, showBearing = false,
    filter = "all",
    font = "default", fontSize = 10, fontOutline = "thick",
    fontColor = { r = 1, g = 0.95, b = 0.6, a = 1 }, fontAlpha = 1.0,
    colorMode = "custom",
    formats = { distance = "{d}y", subzone = "{zone}", indoors = "{env}", underwater = "{water}", bearing = "{dir}", combined = "{d}y | {zone}" },
    sameSubzoneText = "Same map",
    bgEnabled = true, bgColor = { r = 0.08, g = 0.08, b = 0.08, a = 0.7 },
    bgTexture = "Interface\\Buttons\\WHITE8x8", bgEdgeSize = 1, bgInset = 1,
    borderEnabled = true, borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 },
    borderTexture = "Interface\\Buttons\\WHITE8x8", borderEdgeSize = 1,
    borderFile = "Interface\\Buttons\\WHITE8x8",
    anchor = "TOP", anchorTo = "TOP", offsetX = 0, offsetY = 5,
    scale = 1.0, width = 130, height = 16, padding = 2,
    strata = "MEDIUM", frameLevel = 10, clampToScreen = true,
    hideInCombat = false, hideOutOfCombat = false,
    hideWhenNameplateHidden = true, hideWhenUnitNotVisible = true,
    hideBeyondDistance = false, maxDistance = 60,
    hideInInstances = false, hideInOpenWorld = false,
  },

  ["Classic-like"] = {
    -- Plain text, no backdrop, below the nameplate. Visual only.
    enabled = true,
    showDistance = true, showSubzone = true,
    showIndoors = false, showUnderwater = false, showBearing = false,
    filter = "all",
    font = "default", fontSize = 12, fontOutline = "outline",
    fontColor = { r = 1, g = 1, b = 0.6, a = 1 }, fontAlpha = 1.0,
    colorMode = "custom",
    formats = { distance = "{d}y", subzone = "{zone}", indoors = "{env}", underwater = "{water}", bearing = "{dir}", combined = "{d}y | {zone}" },
    sameSubzoneText = "Same map",
    bgEnabled = false, borderEnabled = false,
    anchor = "BOTTOM", anchorTo = "BOTTOM", offsetX = 0, offsetY = -2,
    scale = 1.0, width = 140, height = 16, padding = 0,
    strata = "MEDIUM", frameLevel = 10, clampToScreen = true,
    hideInCombat = false, hideOutOfCombat = false,
    hideWhenNameplateHidden = true, hideWhenUnitNotVisible = true,
    hideBeyondDistance = false, maxDistance = 60,
    hideInInstances = false, hideInOpenWorld = false,
  },

  ["High Contrast"] = {
    -- Maximum legibility: thick outline, opaque backdrop, bright text.
    enabled = true,
    showDistance = true, showSubzone = true,
    showIndoors = true, showUnderwater = true, showBearing = false,
    filter = "all",
    font = "default", fontSize = 12, fontOutline = "thick",
    fontColor = { r = 1, g = 1, b = 1, a = 1 }, fontAlpha = 1.0,
    colorMode = "custom",
    formats = { distance = "{d}y", subzone = "{zone}", indoors = "{env}", underwater = "{water}", bearing = "{dir}", combined = "{d}y | {zone}" },
    sameSubzoneText = "Same map",
    bgEnabled = true, bgColor = { r = 0, g = 0, b = 0, a = 0.85 },
    bgTexture = "Interface\\Buttons\\WHITE8x8", bgEdgeSize = 1, bgInset = 1,
    borderEnabled = true, borderColor = { r = 1, g = 1, b = 1, a = 1 },
    borderTexture = "Interface\\Buttons\\WHITE8x8", borderEdgeSize = 1,
    borderFile = "Interface\\Buttons\\WHITE8x8",
    anchor = "TOP", anchorTo = "TOP", offsetX = 0, offsetY = 4,
    scale = 1.1, width = 150, height = 18, padding = 3,
    strata = "HIGH", frameLevel = 10, clampToScreen = true,
    hideInCombat = false, hideOutOfCombat = false,
    hideWhenNameplateHidden = true, hideWhenUnitNotVisible = true,
    hideBeyondDistance = false, maxDistance = 60,
    hideInInstances = false, hideInOpenWorld = false,
  },

  ["ThreatPlates-like"] = {
    -- Bold, high-legibility presentation inspired by ThreatPlates. Purely
    -- visual; no ThreatPlates integration or dependency is used.
    enabled = true,
    showDistance = true, showSubzone = true,
    showIndoors = false, showUnderwater = false, showBearing = false,
    filter = "all",
    font = "default", fontSize = 11, fontOutline = "thick",
    fontColor = { r = 1, g = 0.9, b = 0.35, a = 1 }, fontAlpha = 1,
    colorMode = "custom",
    formats = { distance = "{d}y", subzone = "{zone}", indoors = "{env}", underwater = "{water}", bearing = "{dir}", combined = "{d}y | {zone}" },
    bgEnabled = true, bgColor = { r = 0.04, g = 0.04, b = 0.04, a = 0.78 },
    bgTexture = "Interface\\Buttons\\WHITE8x8", bgEdgeSize = 1, bgInset = 1,
    borderEnabled = true, borderColor = { r = 0.65, g = 0.48, b = 0.12, a = 0.9 },
    borderTexture = "Interface\\Buttons\\WHITE8x8", borderEdgeSize = 1,
    borderFile = "Interface\\Buttons\\WHITE8x8",
    anchor = "TOP", anchorTo = "TOP", offsetX = 0, offsetY = 5,
    scale = 1, width = 140, height = 17, padding = 2,
    strata = "MEDIUM", frameLevel = 10, clampToScreen = true,
  },
}

SP.PRESETS = PRESETS

-- Sorted list of preset names for UI + slash help.
function SP.PresetNames()
  local names = {}
  for name in pairs(PRESETS) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- Look up a preset by case-insensitive name. Returns the table or nil.
function SP.GetPreset(name)
  if type(name) ~= "string" then return nil end
  if PRESETS[name] then return PRESETS[name] end
  local lower = name:lower()
  for k, v in pairs(PRESETS) do
    if k:lower() == lower then return v end
  end
  return nil
end

-- Apply a preset by name (case-insensitive). Merges onto the active profile,
-- validates, and refreshes live. Returns true on success, false + message
-- on failure. Never errors.
function SP.ApplyPreset(name)
  local preset = SP.GetPreset(name)
  if not preset then
    return false, "unknown preset: " .. tostring(name) .. " (available: " .. table.concat(SP.PresetNames(), ", ") .. ")"
  end
  local ok, err = pcall(function()
    local p = SP.GetProfile()
    for k, v in pairs(preset) do
      if type(v) == "table" then
        if type(p[k]) ~= "table" then p[k] = {} end
        for kk, vv in pairs(v) do p[k][kk] = vv end
      else
        p[k] = v
      end
    end
    SP.ValidateProfile(p)
  end)
  if not ok then return false, "preset apply failed: " .. tostring(err) end
  if SP.ApplyAllAppearances then pcall(SP.ApplyAllAppearances) end
  if SP.RefreshAllOverlays then pcall(SP.RefreshAllOverlays) end
  if SP.RefreshOptionsPanel then pcall(SP.RefreshOptionsPanel) end
  return true
end

-- Known nameplate/UI addon identifiers -> visual preset names. Detection is
-- based only on official addon-loaded state; no addon globals or frames are
-- inspected or modified. Aliases cover common addon folder-name variants.
local THEME_ADDONS = {
  { theme = "Plater-like", ids = { "Plater" } },
  { theme = "ThreatPlates-like", ids = { "ThreatPlates", "TidyPlates_ThreatPlates" } },
  { theme = "ElvUI-like", ids = { "ElvUI" } },
  { theme = "TukUI-like", ids = { "Tukui", "TukUI" } },
  { theme = "Minimal", ids = { "Kui_Nameplates", "KuiNameplates", "Kui_Nameplates_Core" } },
  { theme = "Classic-like", ids = { "NeatPlates", "NeatPlatesHub" } },
}

local function IsAddonLoaded(addonName)
  local api = C_AddOns and C_AddOns.IsAddOnLoaded
  if type(api) == "function" then
    local ok, loaded = pcall(api, addonName)
    if ok then return loaded == true end
  end
  if type(IsAddOnLoaded) == "function" then
    local ok, loaded = pcall(IsAddOnLoaded, addonName)
    if ok then return loaded == true end
  end
  return false
end

local function NormalizeAddonName(name)
  return type(name) == "string" and name:lower():gsub("[^%w]", "") or ""
end

local function ThemeForAddon(addonName)
  local normalized = NormalizeAddonName(addonName)
  if normalized == "" then return nil end
  for _, item in ipairs(THEME_ADDONS) do
    for _, id in ipairs(item.ids) do
      if NormalizeAddonName(id) == normalized then
        return item.theme, id
      end
    end
  end
  return nil
end

-- Auto-select a matching preset once when a different supported nameplate
-- addon is detected. The chosen addon ID is persisted at the DB root so later
-- reloads do not overwrite the user's subsequent appearance edits. If an
-- addon loads after Spatial Plates, pass its name; with no argument this
-- scans the known IDs already loaded. Returns true only when a preset applies.
function SP.AutoMatchNameplateTheme(loadedAddonName, force)
  local profile = SP.GetProfile and SP.GetProfile()
  if not profile or (profile.autoThemeMatch ~= true and force ~= true) then return false end

  local theme, detectedId
  if type(loadedAddonName) == "string" then
    -- ADDON_LOADED itself is authoritative for this argument; do not require
    -- an optional addon-query API merely to handle late-loaded addons.
    theme, detectedId = ThemeForAddon(loadedAddonName)
  end
  -- On our own ADDON_LOADED event, or when enabling auto-match in options,
  -- scan supported IDs already loaded in the client.
  if not theme then
    for _, item in ipairs(THEME_ADDONS) do
      for _, id in ipairs(item.ids) do
        if IsAddonLoaded(id) then
          theme, detectedId = item.theme, id
          break
        end
      end
      if theme then break end
    end
  end
  if not theme then return false end

  local db = SP.EnsureDB and SP.EnsureDB()
  if not db or (db.autoThemeAddon == detectedId and force ~= true) then return false end
  db.autoThemeAddon = detectedId
  local ok = SP.ApplyPreset(theme)
  if ok and SP.DebugPrint then
    SP.DebugPrint("matched loaded nameplate addon " .. detectedId .. " with " .. theme .. " theme")
  end
  return ok == true, theme, detectedId
end

function SP.GetAutoThemeStatus()
  local db = SP.EnsureDB and SP.EnsureDB()
  if not db or type(db.autoThemeAddon) ~= "string" or db.autoThemeAddon == "" then
    return nil, nil
  end
  local theme = ThemeForAddon(db.autoThemeAddon)
  return db.autoThemeAddon, theme
end

SP.NameplateThemeAddons = THEME_ADDONS
