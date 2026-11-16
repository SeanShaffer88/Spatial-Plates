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
  local ok, _, _, classId = pcall(UnitClass, unit)
  if not ok or type(classId) ~= "string" then return nil end
  local colors = RAID_CLASS_COLORS
  if type(colors) ~= "table" then return nil end
  local c = colors[classId]
  if type(c) ~= "table" then return nil end
  return { r = c.r or 1, g = c.g or 1, b = c.b or 1, a = 1 }
end

-- Reaction color: green for friends, yellow for neutral, red for enemies.
-- Only friendly players are ever shown, but the helper is total.
function SP.GetReactionColor(unit)
  if not unit then return { r = 1, g = 1, b = 1, a = 1 } end
  local okFriend, isFriend = pcall(UnitIsFriend, "player", unit)
  if okFriend and isFriend == true then return { r = 0.4, g = 1.0, b = 0.4, a = 1 } end
  local okEnemy, isEnemy = pcall(UnitIsEnemy, "player", unit)
  if okEnemy and isEnemy == true then return { r = 1.0, g = 0.3, b = 0.3, a = 1 } end
  return { r = 1.0, g = 0.9, b = 0.4, a = 1 }
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
  end
  local c = profile.fontColor or { r = 1, g = 1, b = 1, a = 1 }
  return { r = c.r or 1, g = c.g or 1, b = c.b or 1, a = (c.a or 1) * (profile.fontAlpha or 1) }
end

-- ---------------------------------------------------------------------------
-- Text formatting
-- ---------------------------------------------------------------------------

-- Substitute {d}, {zone}, {env}, {water}, {dir} placeholders in a template.
-- `values` maps placeholder -> display string (already sanitized by Core).
-- Missing values leave the placeholder untouched so Core can decide to hide.
function SP.FormatTemplate(template, values)
  if type(template) ~= "string" then return "" end
  local out = template
  for key, val in pairs(values or {}) do
    if type(val) == "string" and val ~= "" then
      out = out:gsub("{" .. key .. "}", val)
    end
  end
  return out
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
      parts[#parts + 1] = fields[key]
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
      local rendered = combined
        :gsub("{d}", map.d)
        :gsub("{zone}", map.zone)
        :gsub("{env}", map.env)
        :gsub("{water}", map.water)
        :gsub("{dir}", map.dir)
      if not rendered:find("{") then
        -- Collapse accidental double separators from empty fields.
        rendered = rendered:gsub("%s*|%s*|%s*", " | "):gsub("^%s*|%s*", ""):gsub("%s*|%s*$", "")
        if rendered ~= "" then return rendered end
      end
    end
  end
  return table.concat(parts, " | ")
end

-- ---------------------------------------------------------------------------
-- Frame appearance application
-- ---------------------------------------------------------------------------

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
      local flag = OutlineFlag(profile)
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
      -- Padding: inset the text within the frame.
      local pad = profile.padding or 2
      text:ClearAllPoints()
      text:SetPoint("LEFT", overlay, "LEFT", pad, 0)
      text:SetPoint("RIGHT", overlay, "RIGHT", -pad, 0)
      text:SetPoint("TOP", overlay, "TOP", 0, 0)
      text:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 0)
      text:SetJustifyH("CENTER")
      text:SetJustifyV("MIDDLE")
    end
  end)
  if not ok then
    SP.DebugPrint("ApplyAppearanceToFrame failed: " .. tostring(err))
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
          SP.DebugPrint("ApplyAllAppearances unit failed: " .. tostring(err))
        end
      end
    end
  end
  -- Also refresh the options preview if it exists.
  if SP.RefreshPreview then pcall(SP.RefreshPreview) end
end
