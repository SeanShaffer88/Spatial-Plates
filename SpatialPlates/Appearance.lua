-- SpatialPlates Appearance.lua
-- Data-driven appearance system: a single profile table drives every visual
-- setting. This file applies that profile to overlay frames (fonts, colors,
-- backgrounds, borders, anchors, sizes, strata) and formats field text.
--
-- SECRET-VALUE SAFETY: This file only reads the appearance profile and the
-- already-sanitized display strings produced by Core.lua. It never calls
-- health/power/aura/cooldown/threat APIs and never does arithmetic on
-- secret values. All API calls that could fail are guarded.

SpatialPlates = SpatialPlates or {}
local SP = SpatialPlates

-- ---------------------------------------------------------------------------
-- Font resolution
-- ---------------------------------------------------------------------------

-- Resolve the effective font path for SetFont. Falls back to the client's
-- default font when the configured path is empty/invalid.
function SP.ResolveFontPath(profile)
  profile = profile or SP.GetProfile()
  local font = profile.font
  if type(font) == "string" and font ~= "" and font ~= "default" then
    if SP.IsValidFontPath and SP.IsValidFontPath(font) then
      return font
    end
  end
  -- Custom path takes precedence when set.
  if type(profile.customFontPath) == "string" and profile.customFontPath ~= "" then
    if SP.IsValidFontPath(profile.customFontPath) then
      return profile.customFontPath
    end
  end
  -- Built-in fallback: use a well-known client font, else the default.
  if font == "Fonts\\ARIALN.TTF" or font == "Fonts\\FRIZQT__.TTF"
    or font == "Fonts\\MORPHEUS.TTF" or font == "Fonts\\SKURRI.TTF" then
    return font
  end
  -- "default": return nil so callers use the FontString's existing font
  -- object (or GameFontNormal) instead of forcing a path.
  return nil
end

local function OutlineFlag(profile)
  if profile.fontOutline == "thick" then return "THICKOUTLINE" end
  if profile.fontOutline == "outline" then return "OUTLINE" end
  return ""
end

-- ---------------------------------------------------------------------------
-- Color resolution
-- ---------------------------------------------------------------------------

-- Class color for a unit, or nil when unreadable. UnitClass is a documented
-- non-secret API; still guarded with pcall + type checks.
function SP.GetClassColor(unit)
  if not unit or not UnitClass then return nil end
  -- UnitClass returns localized class name, class-file token, then numeric
  -- class ID on current clients. RAID_CLASS_COLORS is keyed by the token.
  local ok, _, classToken = pcall(UnitClass, unit)
  if not ok or not SP.IsReadable(classToken, "string") then return nil end
  local colors = RAID_CLASS_COLORS
  if type(colors) ~= "table" then return nil end
  local c = colors[classToken]
  if type(c) ~= "table" then return nil end
  return { r = c.r or 1, g = c.g or 1, b = c.b or 1, a = 1 }
end

-- Reaction color: green for friends, yellow for neutral, red for enemies.
-- Friendly and enemy units can both be shown; the helper is total.
function SP.GetReactionColor(unit)
  if not unit then return { r = 1, g = 1, b = 1, a = 1 } end
  local okFriend, isFriend = pcall(UnitIsFriend, "player", unit)
  if okFriend and SP.IsReadable(isFriend, "boolean") and isFriend == true then
    return { r = 0.4, g = 1.0, b = 0.4, a = 1 }
  end
  local okEnemy, isEnemy = pcall(UnitIsEnemy, "player", unit)
  if okEnemy and SP.IsReadable(isEnemy, "boolean") and isEnemy == true then
    return { r = 1.0, g = 0.3, b = 0.3, a = 1 }
  end
  return { r = 1.0, g = 0.9, b = 0.4, a = 1 }
end

-- Name color: the color the nameplate itself uses for the unit's name.
-- First the plate's own name FontString (Blizzard plates keep it at
-- plate.UnitFrame.name), then UnitSelectionColor (the reaction color the
-- game uses for names). Returns nil when neither is readable.
function SP.GetNameColor(unit)
  if not unit then return nil end
  local function Readable3(r, g, b)
    return SP.IsReadable(r, "number") and SP.IsReadable(g, "number") and SP.IsReadable(b, "number")
  end
  if C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function" then
    local okPlate, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if okPlate and plate then
      local ok, r, g, b = pcall(function()
        local unitFrame = plate.UnitFrame
        local name = unitFrame and unitFrame.name
        if name and name.GetTextColor then return name:GetTextColor() end
      end)
      if ok and Readable3(r, g, b) then return { r = r, g = g, b = b, a = 1 } end
    end
  end
  if type(UnitSelectionColor) == "function" then
    local ok, r, g, b = pcall(UnitSelectionColor, unit)
    if ok and Readable3(r, g, b) then return { r = r, g = g, b = b, a = 1 } end
  end
  return nil
end

-- Distance bands for the colored outline, by yards (exact distance or the
-- estimate's upper bound): green close, then yellow-green, yellow, orange,
-- and red beyond 40 yards or when only "beyond N" is known.
SP.DISTANCE_BANDS = {
  { yards = 10, r = 0.2, g = 1.0, b = 0.2 },
  { yards = 20, r = 0.75, g = 1.0, b = 0.2 },
  { yards = 30, r = 1.0, g = 0.9, b = 0.2 },
  { yards = 40, r = 1.0, g = 0.55, b = 0.1 },
}
SP.DISTANCE_FAR = { r = 1.0, g = 0.2, b = 0.2 }

-- Outline color for a distance, or nil when no distance is shown.
function SP.GetDistanceColor(yards, hasDistance)
  if not hasDistance then return nil end
  if type(yards) ~= "number" then return SP.DISTANCE_FAR end
  for _, band in ipairs(SP.DISTANCE_BANDS) do
    if yards <= band.yards then return band end
  end
  return SP.DISTANCE_FAR
end

-- Resolve the text color for an overlay. `field` selects per-field colors
-- when colorMode == "perField"; otherwise the mode decides.
-- `unit` may be nil (preview frame) — class/reaction modes fall back to custom.
function SP.ResolveTextColor(profile, field, unit)
  profile = profile or SP.GetProfile()
  local mode = profile.colorMode or "custom"
  if mode == "perField" and field and type(profile.fieldColors) == "table" then
    local c = profile.fieldColors[field]
    if type(c) == "table" then
      return { r = c.r or 1, g = c.g or 1, b = c.b or 1, a = (c.a or 1) * (profile.fontAlpha or 1) }
    end
  elseif mode == "class" and unit then
    local c = SP.GetClassColor(unit)
    if c then c.a = c.a * (profile.fontAlpha or 1); return c end
  elseif mode == "reaction" and unit then
    local c = SP.GetReactionColor(unit)
    c.a = c.a * (profile.fontAlpha or 1)
    return c
  elseif mode == "name" and unit then
    local c = SP.GetNameColor(unit) or SP.GetReactionColor(unit)
    return { r = c.r, g = c.g, b = c.b, a = (c.a or 1) * (profile.fontAlpha or 1) }
  end
  local c = profile.fontColor or { r = 1, g = 1, b = 1, a = 1 }
  return { r = c.r or 1, g = c.g or 1, b = c.b or 1, a = (c.a or 1) * (profile.fontAlpha or 1) }
end

-- ---------------------------------------------------------------------------
-- Text formatting
-- ---------------------------------------------------------------------------

local function SanitizeTemplate(template)
  template = template:sub(1, 256)
  -- WoW FontStrings interpret pipe-prefixed rich-text escapes. Preserve the
  -- intentional spaced ` | ` separator, but escape other pipe sequences so
  -- imported templates cannot inject colors, links, or textures.
  local out = {}
  for i = 1, #template do
    local ch = template:sub(i, i)
    if ch == "|" then
      local prev = i > 1 and template:sub(i - 1, i - 1) or ""
      local nextc = i < #template and template:sub(i + 1, i + 1) or ""
      if prev:match("%s") and nextc:match("%s") then
        out[#out + 1] = "|"
      else
        out[#out + 1] = "||"
      end
    elseif ch:byte() < 32 and ch ~= "\t" then
      out[#out + 1] = " "
    else
      out[#out + 1] = ch
    end
  end
  return table.concat(out)
end

local function EscapeDynamicText(value)
  local text = tostring(value):gsub("|", "||")
  return (text:gsub("[%z\1-\8\11\12\14-\31]", " "))
end

local function ColorizeField(profile, field, value)
  if profile.colorMode ~= "perField" or value == "" then return value end
  local color = SP.ResolveTextColor(profile, field, nil)
  local a = math.floor((color.a or 1) * 255 + 0.5)
  local r = math.floor((color.r or 1) * 255 + 0.5)
  local g = math.floor((color.g or 1) * 255 + 0.5)
  local b = math.floor((color.b or 1) * 255 + 0.5)
  return string.format("|c%02x%02x%02x%02x%s|r", a, r, g, b, value)
end

-- Substitute {d}, {zone}, {env}, {water}, {dir} placeholders. Dynamic
-- strings are escaped and substitutions use callbacks so percent signs in a
-- map/name template cannot be treated as gsub replacement directives.
function SP.FormatTemplate(template, values)
  if type(template) ~= "string" then return "" end
  local out = SanitizeTemplate(template)
  for key, val in pairs(values or {}) do
    if type(key) == "string" and type(val) == "string" and val ~= "" then
      local replacement = EscapeDynamicText(val):sub(1, 256)
      out = out:gsub("{" .. key .. "}", function() return replacement end)
    end
  end
  return out:sub(1, 512)
end

-- Build the combined display string from per-field values.
-- `fields` = { distance="12y", subzone="Same subzone", ... } (only readable ones).
-- Uses the combined template when it references available placeholders;
-- otherwise joins available fields with " | ".
function SP.BuildCombinedText(profile, fields)
  profile = profile or SP.GetProfile()
  fields = fields or {}
  local parts = {}
  local order = { "distance", "subzone", "indoors", "underwater", "bearing" }
  for _, key in ipairs(order) do
    if type(fields[key]) == "string" and fields[key] ~= "" then
      parts[#parts + 1] = ColorizeField(profile, key, fields[key])
    end
  end
  if #parts == 0 then return "" end

  local combined = (profile.formats and profile.formats.combined) or ""
  if type(combined) == "string" and combined ~= "" then
    -- Map combined placeholders to field values. Distance is stored
    -- formatted (e.g. "12y"); the combined template expects raw {d}, so
    -- extract the number (unanchored, so custom distance formats work).
    local map = {
      d = fields.distance and (fields.distance:match("(%d+)") or fields.distance) or "",
      zone = fields.subzone or "",
      env = fields.indoors or "",
      water = fields.underwater or "",
      dir = fields.bearing or "",
    }
    -- The combined template is only usable when EVERY placeholder it
    -- references has a readable field. Otherwise fall back to joining the
    -- available fields (e.g. distance hidden -> just "Same subzone",
    -- never "y | Same subzone").
    local allAvailable = true
    for placeholder in combined:gmatch("{(.-)}") do
      local v = map[placeholder]
      if v == nil or v == "" then
        allAvailable = false
        break
      end
    end
    if allAvailable then
      local fieldForPlaceholder = {
        d = "distance", zone = "subzone", env = "indoors",
        water = "underwater", dir = "bearing",
      }
      local replacements = {}
      for placeholder, value in pairs(map) do
        local field = fieldForPlaceholder[placeholder]
        replacements[placeholder] = ColorizeField(profile, field, value)
      end
      local rendered = SanitizeTemplate(combined)
      for placeholder, value in pairs(replacements) do
        rendered = rendered:gsub("{" .. placeholder .. "}", function() return value end)
      end
      if not rendered:find("{") and rendered ~= "" then
        -- All referenced fields are known readable here, so no separator
        -- cleanup is needed. Avoid applying pipe patterns to generated
        -- per-field color tags, which are valid FontString markup.
        return rendered:sub(1, 1024)
      end
    end
  end
  return table.concat(parts, " | "):sub(1, 1024)
end

-- ---------------------------------------------------------------------------
-- Frame appearance application
-- ---------------------------------------------------------------------------

-- Distance outline: eight copies of the text, offset by the outline
-- thickness in every direction and drawn behind it in the distance color.
-- Plain font outlines are always black, so this is how a colored outline is
-- drawn.
local OUTLINE_OFFSETS = {
  { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 },
  { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 },
}

local function StripColorCodes(s)
  s = tostring(s or "")
  s = s:gsub("||", "\001")
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return (s:gsub("\001", "||"))
end

local function EnsureOutline(overlay)
  if overlay._spOutline then return overlay._spOutline end
  local copies = {}
  for i = 1, #OUTLINE_OFFSETS do
    copies[i] = overlay:CreateFontString(nil, "ARTWORK")
  end
  overlay._spOutline = copies
  return copies
end

local function HideOutline(overlay)
  for _, fs in ipairs(overlay._spOutline or {}) do
    if fs.Hide then pcall(fs.Hide, fs) end
  end
end

-- Set the overlay's text (and its outline copies).
function SP.SetOverlayText(overlay, value)
  if not overlay or not overlay._spText then return end
  overlay._spText:SetText(value)
  local plain
  for _, fs in ipairs(overlay._spOutline or {}) do
    plain = plain or StripColorCodes(value)
    pcall(fs.SetText, fs, plain)
  end
end

-- Per-refresh colors that change without a profile change: the name color
-- (target/tapped changes) and the distance outline. Each is reapplied only
-- when the color actually changes.
function SP.UpdateDynamicStyle(overlay, unit, yards, hasDistance)
  if not overlay or not overlay._spText then return end
  local profile = SP.GetProfile()
  if profile.colorMode == "name" then
    local c = SP.ResolveTextColor(profile, nil, unit)
    local key = string.format("%.3f,%.3f,%.3f,%.3f", c.r, c.g, c.b, c.a)
    if overlay._spTextColorKey ~= key then
      pcall(overlay._spText.SetTextColor, overlay._spText, c.r, c.g, c.b, c.a)
      overlay._spTextColorKey = key
    end
  end
  if profile.distanceOutline and overlay._spOutline then
    local c = SP.GetDistanceColor(yards, hasDistance)
    local alpha = profile.fontAlpha or 1
    local r, g, b = 0, 0, 0
    if c then r, g, b = c.r, c.g, c.b end
    local key = string.format("%.2f,%.2f,%.2f,%.2f", r, g, b, alpha)
    if overlay._spOutlineColorKey ~= key then
      for _, fs in ipairs(overlay._spOutline) do
        pcall(fs.SetTextColor, fs, r, g, b, alpha)
      end
      overlay._spOutlineColorKey = key
    end
  end
end

local FALLBACK_TEXTURE = "Interface\\Buttons\\WHITE8x8"

local function SafeTexture(path)
  if type(path) == "string" and path ~= "" then return path end
  return FALLBACK_TEXTURE
end

-- Apply the active profile to a single overlay frame + its font string.
-- `overlay` is the frame; `text` is its FontString (or nil for preview).
-- `unit` is optional (used for class/reaction color modes).
-- Never errors: every step is pcall-guarded.
function SP.ApplyAppearanceToFrame(overlay, text, unit)
  if not overlay then return end
  local profile = SP.GetProfile()

  local ok, err = pcall(function()
    -- Size / scale
    overlay:SetWidth(profile.width or 120)
    overlay:SetHeight(profile.height or 16)
    overlay:SetScale(profile.scale or 1.0)
    overlay:SetFrameStrata(profile.strata or "MEDIUM")
    overlay:SetFrameLevel(profile.frameLevel or 10)
    if overlay.SetClampedToScreen then
      overlay:SetClampedToScreen(profile.clampToScreen == true)
    end

    -- Background + border via backdrop (guarded: SetBackdrop can fail on
    -- bad texture paths, so fall back to a plain color fill).
    if overlay.SetBackdrop then
      local bgFile = profile.bgEnabled and SafeTexture(profile.bgTexture) or FALLBACK_TEXTURE
      local edgeFile = profile.borderEnabled and SafeTexture(profile.borderFile) or FALLBACK_TEXTURE
      local backdropOk = pcall(overlay.SetBackdrop, overlay, {
        bgFile = bgFile,
        edgeFile = edgeFile,
        edgeSize = profile.borderEnabled and (profile.borderEdgeSize or 1) or 0,
        insets = { left = profile.bgInset or 1, right = profile.bgInset or 1, top = profile.bgInset or 1, bottom = profile.bgInset or 1 },
      })
      if not backdropOk then
        pcall(overlay.SetBackdrop, overlay, {
          bgFile = FALLBACK_TEXTURE, edgeFile = FALLBACK_TEXTURE,
          edgeSize = 0, insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
      end
    end
    if overlay.SetBackdropColor then
      local bg = profile.bgColor or { r = 0, g = 0, b = 0, a = 0.45 }
      if profile.bgEnabled then
        overlay:SetBackdropColor(bg.r or 0, bg.g or 0, bg.b or 0, bg.a or 0.45)
      else
        overlay:SetBackdropColor(0, 0, 0, 0)
      end
    end
    if overlay.SetBackdropBorderColor then
      local bc = profile.borderColor or { r = 1, g = 1, b = 1, a = 1 }
      if profile.borderEnabled then
        overlay:SetBackdropBorderColor(bc.r or 1, bc.g or 1, bc.b or 1, bc.a or 1)
      else
        overlay:SetBackdropBorderColor(0, 0, 0, 0)
      end
    end

    -- Font string
    if text then
      local path = SP.ResolveFontPath(profile)
      local size = profile.fontSize or 11
      local useOutline = profile.distanceOutline == true
      -- The colored outline replaces the client's black outline.
      local flag = useOutline and "" or OutlineFlag(profile)
      if path then
        local fontOk = pcall(text.SetFont, text, path, size, flag)
        if not fontOk then
          -- Bad custom path: fall back to default font object.
          pcall(text.SetFont, text, "Fonts\\FRIZQT__.TTF", size, flag)
        end
      else
        -- "default": keep the FontString's template font, just resize/flag.
        -- SetFont with the current font path preserves the default look.
        local curPath = text:GetFont()
        if curPath then
          pcall(text.SetFont, text, curPath, size, flag)
        end
      end
      local c = SP.ResolveTextColor(profile, nil, unit)
      text:SetTextColor(c.r, c.g, c.b, c.a)
      overlay._spTextColorKey = nil
      -- Padding: inset the text within the frame.
      local pad = profile.padding or 2
      text:ClearAllPoints()
      text:SetPoint("LEFT", overlay, "LEFT", pad, 0)
      text:SetPoint("RIGHT", overlay, "RIGHT", -pad, 0)
      text:SetPoint("TOP", overlay, "TOP", 0, 0)
      text:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 0)
      text:SetJustifyH("CENTER")
      text:SetJustifyV("MIDDLE")

      if useOutline then
        local copies = EnsureOutline(overlay)
        local fontPath = text:GetFont()
        local thickness = (profile.fontOutline == "thick") and 2 or 1
        local current = StripColorCodes(text:GetText() or "")
        for i, fs in ipairs(copies) do
          local off = OUTLINE_OFFSETS[i]
          pcall(fs.SetFont, fs, fontPath or "Fonts\\FRIZQT__.TTF", size, "")
          fs:ClearAllPoints()
          fs:SetPoint("TOPLEFT", text, "TOPLEFT", off[1] * thickness, off[2] * thickness)
          fs:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", off[1] * thickness, off[2] * thickness)
          fs:SetJustifyH("CENTER")
          fs:SetJustifyV("MIDDLE")
          fs:SetText(current)
          if fs.Show then fs:Show() end
        end
        overlay._spOutlineColorKey = nil
      else
        HideOutline(overlay)
      end
    end
  end)
  if not ok then
    SP.DebugPrint("appearance application failed")
  end
end

-- Re-apply appearance to every live overlay (called on any profile change).
function SP.ApplyAllAppearances()
  -- A revision counter lets Core skip backdrop/font/layout work on every
  -- ticker update. Profile mutations go through SetProfileValue, Reset,
  -- Import, or ApplyPreset, all of which call this function.
  SP._appearanceRevision = (SP._appearanceRevision or 0) + 1
  local revision = SP._appearanceRevision
  if type(SP._overlays) == "table" then
    for unit, overlay in pairs(SP._overlays) do
      if overlay and overlay:IsShown() then
        local text = overlay._spText
        local ok, err = pcall(SP.ApplyAppearanceToFrame, overlay, text, unit)
        if ok then
          overlay._spAppearanceRevision = revision
        else
          SP.DebugPrint("appearance refresh for overlay failed")
        end
      end
    end
  end
  -- Also refresh the options preview if it exists.
  if SP.RefreshPreview then pcall(SP.RefreshPreview) end
end
