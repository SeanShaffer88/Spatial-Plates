-- SpatialPlates Config.lua
-- Defaults, SavedVariables, profile access, validation, export/import codec,
-- slash commands, and the in-game options panel.
--
-- SECRET-VALUE SAFETY: This file performs NO combat-data reads at all. It only
-- touches UI/appearance data (fonts, colors, anchors, toggles). Nothing here
-- calls health/power/aura/cooldown/threat APIs, and nothing here does
-- arithmetic on values that could be secret. All profile values are plain
-- numbers/strings/booleans stored in SavedVariables.

-- Namespace table. Global name uses the required "SpatialPlates_" prefix.
SpatialPlates = SpatialPlates or {}
local SP = SpatialPlates
SP._VERSION = "1.0.2"
SP._PROFILE_VERSION = 1

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------

-- Anchor point names accepted by SetPoint. "CENTER" is also accepted.
local VALID_ANCHORS = {
  TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
  ["TOP-LEFT"] = true, ["TOP-RIGHT"] = true,
  ["BOTTOM-LEFT"] = true, ["BOTTOM-RIGHT"] = true, CENTER = true,
}
SP.VALID_ANCHORS = VALID_ANCHORS

local VALID_FILTERS = { all = true, party = true, raid = true, guild = true, friends = true }
SP.VALID_FILTERS = VALID_FILTERS

local VALID_COLOR_MODES = { custom = true, class = true, reaction = true, perField = true }
SP.VALID_COLOR_MODES = VALID_COLOR_MODES

local VALID_OUTLINES = { none = true, outline = true, thick = true }
SP.VALID_OUTLINES = VALID_OUTLINES

local VALID_STRATA = {
  BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true,
  DIALOG = true, FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true,
}
SP.VALID_STRATA = VALID_STRATA

-- Built-in font choices. The value is a font path usable with SetFont.
-- "default" falls back to the client's default UI font at runtime.
SP.BUILTIN_FONTS = {
  { label = "Default (client)", value = "default" },
  { label = "Arial Narrow", value = "Fonts\\ARIALN.TTF" },
  { label = "Friz Quadrata", value = "Fonts\\FRIZQT__.TTF" },
  { label = "Morpheus", value = "Fonts\\MORPHEUS.TTF" },
  { label = "Skurri", value = "Fonts\\SKURRI.TTF" },
}

-- Factory for a fresh default profile. A single profile table drives ALL
-- visual settings (data-driven appearance system). Presets are partial
-- profile tables merged on top of these defaults.
local function DefaultProfile()
  return {
    -- Enabled / fields
    enabled = true,
    showDistance = true,
    showSubzone = true,
    showIndoors = false,
    showUnderwater = false,
    showBearing = false,
    filter = "all", -- all | party | raid | guild | friends
    -- Player modes: any checked mode that matches makes a player eligible.
    showGlobal = true, -- every other player, friendly or hostile
    showParty = true, -- party/raid members
    showFriendsList = true, -- players on your friends list

    -- Font
    font = "default", -- builtin value or custom path
    customFontPath = "",
    fontSize = 11,
    fontOutline = "outline", -- none | outline | thick
    fontColor = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 },
    fontAlpha = 1.0,
    colorMode = "custom", -- custom | class | reaction | perField
    fieldColors = {
      distance = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 },
      subzone = { r = 0.85, g = 0.85, b = 0.85, a = 1.0 },
      indoors = { r = 0.7, g = 0.9, b = 1.0, a = 1.0 },
      underwater = { r = 0.4, g = 0.7, b = 1.0, a = 1.0 },
      bearing = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 },
    },

    -- Text format templates. Placeholders: {d} distance yards,
    -- {zone} subzone/map name, {env} indoors/outdoors text,
    -- {water} underwater text, {dir} bearing glyph/text.
    formats = {
      distance = "{d}y",
      subzone = "{zone}",
      indoors = "{env}",
      underwater = "{water}",
      bearing = "{dir}",
      combined = "{d}y | {zone}",
    },
    sameSubzoneText = "Same map",

    -- Background
    bgEnabled = true,
    bgColor = { r = 0.0, g = 0.0, b = 0.0, a = 0.45 },
    bgTexture = "Interface\\Buttons\\WHITE8x8",
    bgEdgeSize = 1,
    bgInset = 1,

    -- Border
    borderEnabled = false,
    borderColor = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 },
    borderTexture = "Interface\\Buttons\\WHITE8x8",
    borderEdgeSize = 1,
    borderFile = "Interface\\Buttons\\WHITE8x8",

    -- Layout
    anchor = "TOP", -- relative to nameplate (or custom parent)
    anchorTo = "TOP", -- which edge of the overlay anchors to the parent point
    offsetX = 0,
    offsetY = 4,
    scale = 1.0,
    width = 120,
    height = 16,
    padding = 2,
    strata = "MEDIUM",
    frameLevel = 10,
    clampToScreen = true,

    -- Visibility rules
    hideInCombat = false,
    hideOutOfCombat = false,
    hideWhenNameplateHidden = true,
    hideWhenUnitNotVisible = true,
    hideBeyondDistance = false,
    maxDistance = 60,
    hideInInstances = false,
    hideInOpenWorld = false,

    -- Update cadence (seconds). Clamped to [0.1, 2.0] at runtime.
    updateInterval = 0.3,

    -- Custom parent / auto-detection
    customParentFunc = "", -- global function name, e.g. "MyAddon_GetNameplateFrame"
    autoDetect = false, -- optional read-only parent-frame detection
    autoThemeMatch = true, -- apply a visual preset for a loaded nameplate addon

    -- Debug
    debug = false,
  }
end
SP.DefaultProfile = DefaultProfile

local function DefaultDB()
  return {
    version = SP._PROFILE_VERSION,
    accountWide = true,
    profile = DefaultProfile(),
    charProfiles = {},
    -- Slash-command toggles mirror the active profile for convenience, but
    -- the profile is the source of truth. Kept here so /reload preserves them.
    enabled = true,
    debug = false,
    -- Minimap button: angle in degrees around the minimap edge.
    minimap = { angle = 225, hide = false },
  }
end

-- ---------------------------------------------------------------------------
-- Database lifecycle
-- ---------------------------------------------------------------------------

local function GetCharKey()
  -- "Name-Realm" key for per-character profiles. Falls back to "Unknown".
  local ok, name = pcall(UnitName, "player")
  if not ok or type(name) ~= "string" or name == "" then return "Unknown" end
  local ok2, realm = pcall(GetRealmName)
  if ok2 and type(realm) == "string" and realm ~= "" then
    return name .. "-" .. realm
  end
  return name
end
SP.GetCharKey = GetCharKey

-- Copy profile/SavedVariables tables without sharing nested color subtables
-- between account and character profiles. A depth limit and seen map make
-- malformed cyclic/deep tables harmless.
local function DeepCopy(value, seen, depth)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  depth = depth or 0
  if depth >= 16 then return nil end
  if seen[value] then return seen[value] end
  local copy = {}
  seen[value] = copy
  for k, v in pairs(value) do
    if type(k) == "string" or type(k) == "number" then
      local copied = DeepCopy(v, seen, depth + 1)
      if copied ~= nil then copy[k] = copied end
    end
  end
  return copy
end
SP.DeepCopy = DeepCopy

-- Ensure SpatialPlatesDB exists and has the expected shape. Common malformed
-- saved-data cases are normalized to defaults; client/runtime guarantees are
-- intentionally not assumed.
function SP.EnsureDB()
  if type(SpatialPlatesDB) ~= "table" then
    SpatialPlatesDB = DefaultDB()
    return SpatialPlatesDB
  end
  local db = SpatialPlatesDB
  if type(db.profile) ~= "table" then db.profile = DefaultProfile() end
  if type(db.charProfiles) ~= "table" then db.charProfiles = {} end
  if type(db.accountWide) ~= "boolean" then db.accountWide = true end
  if type(db.version) ~= "number" or db.version ~= db.version then db.version = SP._PROFILE_VERSION end
  if type(db.minimap) ~= "table" then db.minimap = { angle = 225, hide = false } end
  local angle = db.minimap.angle
  if type(angle) ~= "number" or angle ~= angle or angle < 0 or angle >= 360 then db.minimap.angle = 225 end
  if type(db.minimap.hide) ~= "boolean" then db.minimap.hide = false end
  if type(db.autoThemeAddon) ~= "string" or #db.autoThemeAddon > 64
    or not db.autoThemeAddon:match("^[%w_]+$") then
    db.autoThemeAddon = nil
  end
  -- Fill any missing profile keys from defaults (forward-compatible).
  local defaults = DefaultProfile()
  for k, v in pairs(defaults) do
    if db.profile[k] == nil then db.profile[k] = v end
  end
  if type(db.profile.formats) ~= "table" then db.profile.formats = defaults.formats end
  if type(db.profile.fieldColors) ~= "table" then db.profile.fieldColors = defaults.fieldColors end
  if type(db.profile.fontColor) ~= "table" then db.profile.fontColor = defaults.fontColor end
  if type(db.profile.bgColor) ~= "table" then db.profile.bgColor = defaults.bgColor end
  if type(db.profile.borderColor) ~= "table" then db.profile.borderColor = defaults.borderColor end
  return db
end

-- Return the active profile table (account-wide or per-character).
-- The returned table is the LIVE table stored in SavedVariables; callers
-- mutate it via SP.SetProfileValue so validation always runs.
function SP.GetProfile()
  local db = SP.EnsureDB()
  if db.accountWide then
    return db.profile
  end
  local key = GetCharKey()
  if type(db.charProfiles[key]) ~= "table" then
    -- First use of this character: seed from account-wide profile.
    db.charProfiles[key] = DeepCopy(db.profile) or DefaultProfile()
  end
  return db.charProfiles[key]
end

-- ---------------------------------------------------------------------------
-- Validation helpers
-- ---------------------------------------------------------------------------

local function ConfigReadable(value, expectedType)
  if value == nil or (expectedType and type(value) ~= expectedType) then return false end
  if type(SP.IsReadable) == "function" then
    local ok, readable = pcall(SP.IsReadable, value, expectedType)
    return ok and readable == true
  end
  if type(issecretvalue) == "function" then
    local ok, isSecret = pcall(issecretvalue, value)
    if not ok or isSecret == true then return false end
  end
  return true
end

local function ClampNumber(v, lo, hi, fallback)
  if not ConfigReadable(v, "number") then return fallback end
  if v ~= v then return fallback end -- NaN guard
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end
SP.ClampNumber = ClampNumber

local function ClampColor(c, fallback)
  if not ConfigReadable(c, "table") then return { r = fallback.r, g = fallback.g, b = fallback.b, a = fallback.a } end
  return {
    r = ClampNumber(c.r, 0, 1, fallback.r),
    g = ClampNumber(c.g, 0, 1, fallback.g),
    b = ClampNumber(c.b, 0, 1, fallback.b),
    a = ClampNumber(c.a, 0, 1, fallback.a),
  }
end
SP.ClampColor = ClampColor

local function IsValidFontPath(s)
  if type(s) ~= "string" or s == "" then return false end
  -- Reject suspicious content: no newlines, no leading/trailing spaces only.
  if s:find("\n") or s:find("\r") then return false end
  return true
end
SP.IsValidFontPath = IsValidFontPath

-- Validate + normalize a profile table in place. Returns the profile.
-- Unknown keys are preserved (forward compatibility) but known keys are
-- type-checked and clamped so a corrupt SavedVariable can never break the UI.
function SP.ValidateProfile(p)
  if not ConfigReadable(p, "table") then return DefaultProfile() end
  local d = DefaultProfile()

  local function Bool(key)
    if not ConfigReadable(p[key], "boolean") then p[key] = d[key] end
  end
  local function Num(key, lo, hi)
    p[key] = ClampNumber(p[key], lo, hi, d[key])
  end
  local function Str(key, maxLen)
    if not ConfigReadable(p[key], "string") then p[key] = d[key] end
    if maxLen and #p[key] > maxLen then p[key] = p[key]:sub(1, maxLen) end
  end

  Bool("enabled"); Bool("showDistance"); Bool("showSubzone")
  Bool("showIndoors"); Bool("showUnderwater"); Bool("showBearing")
  Bool("bgEnabled"); Bool("borderEnabled")
  Bool("hideInCombat"); Bool("hideOutOfCombat")
  Bool("hideWhenNameplateHidden"); Bool("hideWhenUnitNotVisible")
  Bool("hideBeyondDistance"); Bool("hideInInstances"); Bool("hideInOpenWorld")
  Bool("showGlobal"); Bool("showParty"); Bool("showFriendsList")
  Bool("clampToScreen"); Bool("autoDetect"); Bool("autoThemeMatch"); Bool("debug")

  if not ConfigReadable(p.filter, "string") or not VALID_FILTERS[p.filter] then p.filter = d.filter end
  if not ConfigReadable(p.colorMode, "string") or not VALID_COLOR_MODES[p.colorMode] then p.colorMode = d.colorMode end
  if not ConfigReadable(p.fontOutline, "string") or not VALID_OUTLINES[p.fontOutline] then p.fontOutline = d.fontOutline end
  if not ConfigReadable(p.anchor, "string") or not VALID_ANCHORS[p.anchor] then p.anchor = d.anchor end
  if not ConfigReadable(p.anchorTo, "string") or not VALID_ANCHORS[p.anchorTo] then p.anchorTo = d.anchorTo end
  if not ConfigReadable(p.strata, "string") or not VALID_STRATA[p.strata] then p.strata = d.strata end

  Num("fontSize", 6, 32)
  Num("fontAlpha", 0, 1)
  Num("scale", 0.5, 2.0)
  Num("width", 20, 600)
  Num("height", 8, 80)
  Num("padding", 0, 24)
  Num("offsetX", -300, 300)
  Num("offsetY", -300, 300)
  Num("bgEdgeSize", 0, 32)
  Num("bgInset", 0, 32)
  Num("borderEdgeSize", 0, 32)
  Num("frameLevel", 0, 100)
  Num("maxDistance", 1, 200)
  Num("updateInterval", 0.1, 2.0)

  Str("font", 128); Str("customFontPath", 256)
  Str("strata", 32); Str("sameSubzoneText", 64)
  -- The field is based on GetBestMapForUnit (map granularity), not a true
  -- subzone query. Migrate the old built-in wording while preserving any
  -- custom text users supplied.
  if p.sameSubzoneText == "Same subzone" then p.sameSubzoneText = "Same map" end
  Str("bgTexture", 256); Str("borderTexture", 256); Str("borderFile", 256)
  Str("customParentFunc", 128)
  if p.customParentFunc ~= "" and not p.customParentFunc:match("^[%a_][%w_]*$") then
    p.customParentFunc = ""
  end

  if not ConfigReadable(p.formats, "table") then p.formats = d.formats end
  for _, k in ipairs({ "distance", "subzone", "indoors", "underwater", "bearing", "combined" }) do
    if not ConfigReadable(p.formats[k], "string") then p.formats[k] = d.formats[k] end
    if #p.formats[k] > 256 then p.formats[k] = p.formats[k]:sub(1, 256) end
  end

  p.fontColor = ClampColor(p.fontColor, d.fontColor)
  p.bgColor = ClampColor(p.bgColor, d.bgColor)
  p.borderColor = ClampColor(p.borderColor, d.borderColor)
  if not ConfigReadable(p.fieldColors, "table") then p.fieldColors = d.fieldColors end
  for _, k in ipairs({ "distance", "subzone", "indoors", "underwater", "bearing" }) do
    p.fieldColors[k] = ClampColor(p.fieldColors[k], d.fieldColors[k])
  end

  return p
end

-- Set a single profile value with validation, then refresh visuals live.
-- Returns true on success, false + message on failure.
function SP.SetProfileValue(key, value)
  local p = SP.GetProfile()
  if type(key) ~= "string" or key == "" then return false, "invalid key" end
  -- Nested keys use dot notation (including deeper values such as
  -- "fieldColors.distance.r"). Walk only existing tables so arbitrary paths
  -- cannot create unexpected SavedVariables structures.
  if key:sub(1, 1) == "." or key:sub(-1) == "." or key:find("..", 1, true) then
    return false, "invalid key path"
  end
  local parts = {}
  for part in key:gmatch("[^.]+") do
    if not part:match("^[%w_]+$") then return false, "invalid key path" end
    parts[#parts + 1] = part
  end
  if #parts == 0 then return false, "invalid key" end

  -- Validate against a fresh schema, not the live table: unexpected keys and
  -- type changes cannot smuggle arbitrary SavedVariables into a profile.
  local schema = DefaultProfile()
  for i = 1, #parts do
    if type(schema) ~= "table" or schema[parts[i]] == nil then
      return false, "unknown key: " .. key
    end
    schema = schema[parts[i]]
  end
  if type(value) ~= type(schema) then return false, "invalid value type for " .. key end

  local target = p
  for i = 1, #parts - 1 do
    if type(target[parts[i]]) ~= "table" then return false, "unknown key: " .. key end
    target = target[parts[i]]
  end
  target[parts[#parts]] = value
  SP.ValidateProfile(p)
  if SP.ApplyAllAppearances then
    local ok, err = pcall(SP.ApplyAllAppearances)
    if not ok then SP.DebugPrint("appearance refresh failed") end
  end
  if SP.ScanNameplates then
    local ok, err = pcall(SP.ScanNameplates)
    if not ok then SP.DebugPrint("nameplate rescan failed") end
  end
  if SP.RefreshAllOverlays then
    local ok, err = pcall(SP.RefreshAllOverlays)
    if not ok then SP.DebugPrint("overlay refresh failed") end
  end
  return true
end

-- Reset the active profile to defaults.
function SP.ResetProfile()
  local db = SP.EnsureDB()
  if db.accountWide then
    db.profile = DefaultProfile()
  else
    db.charProfiles[GetCharKey()] = DefaultProfile()
  end
  SP.ValidateProfile(SP.GetProfile())
  if SP.ApplyAllAppearances then pcall(SP.ApplyAllAppearances) end
  if SP.RefreshAllOverlays then pcall(SP.RefreshAllOverlays) end
end

-- ---------------------------------------------------------------------------
-- Export / import codec
-- ---------------------------------------------------------------------------
-- Format: "SP1:<profileVersion>:<k=v|k=v|...>" where keys are flattened with
-- "." for nested tables (e.g. "fontColor.r=1"). Values are URL-escaped
-- (%XX) so "|" and "=" inside strings cannot corrupt the payload.
-- Import validates the prefix, version, key whitelist, and value types, and
-- rejects anything malformed without touching the live profile.

local EXPORT_PREFIX = "SP1"

local function UrlEscape(s)
  return (s:gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("=", "%%3D"):gsub(":", "%%3A"))
end

local function UrlUnescape(s)
  return (s:gsub("%%3A", ":"):gsub("%%3D", "="):gsub("%%7C", "|"):gsub("%%25", function() return "%" end))
end

-- Whitelist of exportable keys -> expected type ("bool"/"num"/"str"/"color").
local EXPORT_KEYS = {
  enabled = "bool", showDistance = "bool", showSubzone = "bool",
  showIndoors = "bool", showUnderwater = "bool", showBearing = "bool",
  filter = "str", font = "str",
  showGlobal = "bool", showParty = "bool", showFriendsList = "bool", customFontPath = "str",
  fontSize = "num", fontOutline = "str", fontAlpha = "num",
  colorMode = "str", sameSubzoneText = "str",
  bgEnabled = "bool", bgEdgeSize = "num", bgInset = "num",
  bgTexture = "str", borderEnabled = "bool", borderEdgeSize = "num",
  borderTexture = "str", borderFile = "str",
  anchor = "str", anchorTo = "str", offsetX = "num", offsetY = "num",
  scale = "num", width = "num", height = "num", padding = "num",
  strata = "str", frameLevel = "num", clampToScreen = "bool",
  hideInCombat = "bool", hideOutOfCombat = "bool",
  hideWhenNameplateHidden = "bool", hideWhenUnitNotVisible = "bool",
  hideBeyondDistance = "bool", maxDistance = "num",
  hideInInstances = "bool", hideInOpenWorld = "bool",
  updateInterval = "num", customParentFunc = "str", autoDetect = "bool",
  autoThemeMatch = "bool", debug = "bool",
  ["fontColor.r"] = "num", ["fontColor.g"] = "num", ["fontColor.b"] = "num", ["fontColor.a"] = "num",
  ["bgColor.r"] = "num", ["bgColor.g"] = "num", ["bgColor.b"] = "num", ["bgColor.a"] = "num",
  ["borderColor.r"] = "num", ["borderColor.g"] = "num", ["borderColor.b"] = "num", ["borderColor.a"] = "num",
  ["formats.distance"] = "str", ["formats.subzone"] = "str", ["formats.indoors"] = "str",
  ["formats.underwater"] = "str", ["formats.bearing"] = "str", ["formats.combined"] = "str",
  ["fieldColors.distance.r"] = "num", ["fieldColors.distance.g"] = "num",
  ["fieldColors.distance.b"] = "num", ["fieldColors.distance.a"] = "num",
  ["fieldColors.subzone.r"] = "num", ["fieldColors.subzone.g"] = "num",
  ["fieldColors.subzone.b"] = "num", ["fieldColors.subzone.a"] = "num",
  ["fieldColors.indoors.r"] = "num", ["fieldColors.indoors.g"] = "num",
  ["fieldColors.indoors.b"] = "num", ["fieldColors.indoors.a"] = "num",
  ["fieldColors.underwater.r"] = "num", ["fieldColors.underwater.g"] = "num",
  ["fieldColors.underwater.b"] = "num", ["fieldColors.underwater.a"] = "num",
  ["fieldColors.bearing.r"] = "num", ["fieldColors.bearing.g"] = "num",
  ["fieldColors.bearing.b"] = "num", ["fieldColors.bearing.a"] = "num",
}

local function IsExportPrefix(prefix)
  for key in pairs(EXPORT_KEYS) do
    if key:sub(1, #prefix + 1) == prefix .. "." then return true end
  end
  return false
end

local function FlattenValue(out, prefix, value, ancestors, depth)
  ancestors = ancestors or {}
  depth = depth or 0
  if depth > 8 then return end
  if type(value) == "table" then
    if ancestors[value] then return end -- break malformed SavedVariables cycles
    ancestors[value] = true
    for k, v in pairs(value) do
      if type(k) == "string" then
        local newPrefix = prefix == "" and k or (prefix .. "." .. k)
        if EXPORT_KEYS[newPrefix] or IsExportPrefix(newPrefix) then
          FlattenValue(out, newPrefix, v, ancestors, depth + 1)
        end
      end
    end
    ancestors[value] = nil
  elseif type(value) == "boolean" and EXPORT_KEYS[prefix] == "bool" then
    out[#out + 1] = prefix .. "=" .. (value and "1" or "0")
  elseif type(value) == "number" and EXPORT_KEYS[prefix] == "num" then
    out[#out + 1] = prefix .. "=" .. string.format("%.4g", value)
  elseif type(value) == "string" and EXPORT_KEYS[prefix] == "str" then
    out[#out + 1] = prefix .. "=" .. UrlEscape(value)
  end
end

-- Export the active profile as a compact string. Never errors.
function SP.ExportProfile()
  local ok, result = pcall(function()
    local p = SP.GetProfile()
    local parts = {}
    FlattenValue(parts, "", p)
    table.sort(parts)
    return EXPORT_PREFIX .. ":" .. tostring(SP._PROFILE_VERSION) .. ":" .. table.concat(parts, "|")
  end)
  if not ok then return nil, "export failed (profile data could not be encoded)" end
  return result
end

-- Import a profile string. Returns true on success, false + reason on failure.
-- Malformed strings are rejected WITHOUT modifying the live profile.
function SP.ImportProfile(str)
  if type(str) ~= "string" or str == "" then return false, "empty string" end
  str = str:gsub("^%s+", ""):gsub("%s+$", "")
  if #str > 8192 then return false, "string too long" end

  local prefix, verStr, payload = str:match("^([^:]+):([^:]+):(.*)$")
  if prefix ~= EXPORT_PREFIX then return false, "bad prefix (expected SP1)" end
  local ver = tonumber(verStr)
  if not ver or ver < 1 or ver > SP._PROFILE_VERSION then
    return false, "unsupported profile version"
  end
  if payload == "" then return false, "empty payload" end

  -- Parse into a fresh table first; only commit if everything validates.
  local incoming, seenKeys = {}, {}
  for token in (payload .. "|"):gmatch("(.-)|") do
    local k, v = token:match("^([^=]+)=(.*)$")
    if not k then return false, "malformed profile token" end
    if seenKeys[k] then return false, "duplicate profile key" end
    seenKeys[k] = true
    local expected = EXPORT_KEYS[k]
    if not expected then return false, "unknown profile key" end
    if expected == "bool" then
      if v ~= "0" and v ~= "1" then return false, "invalid boolean value" end
      incoming[k] = (v == "1")
    elseif expected == "num" then
      local n = tonumber(v)
      -- Some C runtimes parse "nan"/"inf"; reject non-finite numbers too.
      if n == nil or n ~= n or n == math.huge or n == -math.huge then
        return false, "invalid numeric value"
      end
      incoming[k] = n
    else
      incoming[k] = UrlUnescape(v)
      if #incoming[k] > 512 then return false, "profile string value too long" end
    end
  end

  -- Apply onto a copy of the current profile, validate, then commit.
  local p = SP.GetProfile()
  local copy = DeepCopy(p) or DefaultProfile()
  for k, v in pairs(incoming) do
    local dot = k:find(".", 1, true)
    if dot then
      local head = k:sub(1, dot - 1)
      local rest = k:sub(dot + 1)
      if type(copy[head]) ~= "table" then return false, "invalid nested profile key" end
      local dot2 = rest:find(".", 1, true)
      if dot2 then
        local mid = rest:sub(1, dot2 - 1)
        local leaf = rest:sub(dot2 + 1)
        if type(copy[head][mid]) ~= "table" then return false, "invalid nested profile key" end
        copy[head][mid][leaf] = v
      else
        copy[head][rest] = v
      end
    else
      copy[k] = v
    end
  end
  SP.ValidateProfile(copy)

  -- Commit: replace the live profile's contents.
  for k in pairs(p) do p[k] = nil end
  for k, v in pairs(copy) do p[k] = v end
  if SP.ApplyAllAppearances then pcall(SP.ApplyAllAppearances) end
  if SP.RefreshAllOverlays then pcall(SP.RefreshAllOverlays) end
  return true
end

-- ---------------------------------------------------------------------------
-- Debug printing (never prints secret values — only hide reasons)
-- ---------------------------------------------------------------------------

local function SafeChatText(value)
  local ok, text = pcall(tostring, value or "")
  if not ok then text = "[unprintable message]" end
  text = text:gsub("|", "||"):gsub("[%z\1-\8\11\12\14-\31]", " ")
  return text:sub(1, 240)
end

function SP.DebugPrint(msg)
  local p
  local ok, prof = pcall(SP.GetProfile)
  if ok then p = prof end
  if p and p.debug then
    print("|cff33ccffSpatial Plates:|r " .. SafeChatText(msg))
  end
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

local function PrintHelp()
  print("|cff33ccffSpatial Plates|r commands:")
  print("  /splates toggle            - enable/disable the addon")
  print("  /splates distance [on|off] - toggle distance field")
  print("  /splates map [on|off]      - toggle same-map/map-name field (alias: subzone)")
  print("  /splates indoors [on|off]  - toggle indoors/outdoors field")
  print("  /splates underwater [on|off] - toggle underwater field")
  print("  Bearing is unavailable: this client has no safe non-secret bearing API")
  print("  /splates filter <all|party|raid|guild|friends>")
  print("  /splates minimap [on|off]  - show/hide the minimap button")
  print("  /splates global [on|off]   - show on all players (friendly + hostile)")
  print("  /splates party [on|off]    - show on party/raid members")
  print("  /splates friendslist [on|off] - show on friends-list players")
  print("  /splates theme <name>      - apply a theme preset")
  print("  /splates theme auto        - detect and apply the loaded addon match now")
  print("  /splates config            - open options panel")
  print("  /splates export            - print export string")
  print("  /splates import <string>   - import a profile string")
  print("  /splates reset             - reset profile to defaults")
  print("  /splates debug [on|off]    - toggle debug output")
  print("  /splates scope <account|char> - account-wide vs per-character")
end

local function ParseOnOff(arg, current)
  if arg == nil or arg == "" then return not current end
  local a = arg:lower()
  if a == "on" or a == "1" or a == "true" then return true end
  if a == "off" or a == "0" or a == "false" then return false end
  return nil
end

local function HandleSlash(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()

  local function ToggleField(key, label)
    local p = SP.GetProfile()
    local newVal = ParseOnOff(rest, p[key])
    if newVal == nil then
      print("|cff33ccffSpatial Plates:|r usage: /splates " .. label .. " [on|off]")
      return
    end
    SP.SetProfileValue(key, newVal)
    print("|cff33ccffSpatial Plates:|r " .. label .. " " .. (newVal and "ON" or "OFF"))
  end

  if cmd == "" or cmd == "help" then
    PrintHelp()
  elseif cmd == "toggle" then
    local p = SP.GetProfile()
    local newVal = ParseOnOff(rest, p.enabled)
    if newVal == nil then newVal = not p.enabled end
    SP.SetProfileValue("enabled", newVal)
    print("|cff33ccffSpatial Plates:|r " .. (newVal and "enabled" or "disabled"))
  elseif cmd == "distance" then ToggleField("showDistance", "distance")
  elseif cmd == "map" or cmd == "subzone" then ToggleField("showSubzone", "map")
  elseif cmd == "indoors" then ToggleField("showIndoors", "indoors")
  elseif cmd == "underwater" then ToggleField("showUnderwater", "underwater")
  elseif cmd == "minimap" then
    local db = SP.EnsureDB()
    local show = ParseOnOff(rest, not db.minimap.hide)
    if show == nil then
      print("|cff33ccffSpatial Plates:|r usage: /splates minimap [on|off]")
    else
      db.minimap.hide = not show
      if SP.UpdateMinimapButton then SP.UpdateMinimapButton() end
      print("|cff33ccffSpatial Plates:|r minimap button " .. (show and "shown" or "hidden"))
    end
  elseif cmd == "global" then ToggleField("showGlobal", "global")
  elseif cmd == "party" then ToggleField("showParty", "party")
  elseif cmd == "friendslist" then ToggleField("showFriendsList", "friendslist")
  elseif cmd == "bearing" then
    print("|cff33ccffSpatial Plates:|r bearing unavailable: no safe non-secret API on this client")
  elseif cmd == "filter" then
    local f = (rest or ""):lower()
    if VALID_FILTERS[f] then
      SP.SetProfileValue("filter", f)
      print("|cff33ccffSpatial Plates:|r filter set to " .. f)
    else
      print("|cff33ccffSpatial Plates:|r filter must be one of: all, party, raid, guild, friends")
    end
  elseif cmd == "theme" then
    local name = (rest or ""):lower()
    if name == "auto" then
      local ok, matchedTheme, addonName = false, nil, nil
      if SP.AutoMatchNameplateTheme then
        ok, matchedTheme, addonName = SP.AutoMatchNameplateTheme(nil, true)
      end
      if ok then
        print("|cff33ccffSpatial Plates:|r matched " .. tostring(addonName) .. " → " .. tostring(matchedTheme))
      else
        print("|cff33ccffSpatial Plates:|r no supported nameplate replacement addon is loaded")
      end
    elseif SP.ApplyPreset then
      local ok, err = SP.ApplyPreset(name)
      if ok then
        print("|cff33ccffSpatial Plates:|r theme applied: " .. name)
      else
        print("|cff33ccffSpatial Plates:|r " .. SafeChatText(err))
        print("  Available: " .. table.concat(SP.PresetNames and SP.PresetNames() or {}, ", "))
      end
    else
      print("|cff33ccffSpatial Plates:|r presets not loaded yet")
    end
  elseif cmd == "config" or cmd == "options" then
    if SP.OpenOptions then SP.OpenOptions() end
  elseif cmd == "export" then
    local s, err = SP.ExportProfile()
    if s then
      print("|cff33ccffSpatial Plates:|r export string:")
      print(s)
    else
print("|cff33ccffSpatial Plates:|r export failed: " .. SafeChatText(err))
    end
  elseif cmd == "import" then
    if not rest or rest == "" then
      print("|cff33ccffSpatial Plates:|r usage: /splates import <string>")
    else
      local ok, err = SP.ImportProfile(rest)
      if ok then
        print("|cff33ccffSpatial Plates:|r profile imported")
      else
        print("|cff33ccffSpatial Plates:|r import rejected: " .. SafeChatText(err))
      end
    end
  elseif cmd == "reset" then
    SP.ResetProfile()
    print("|cff33ccffSpatial Plates:|r profile reset to defaults")
  elseif cmd == "debug" then
    local p = SP.GetProfile()
    local newVal = ParseOnOff(rest, p.debug)
    if newVal == nil then newVal = not p.debug end
    SP.SetProfileValue("debug", newVal)
    print("|cff33ccffSpatial Plates:|r debug " .. (newVal and "ON" or "OFF"))
  elseif cmd == "scope" then
    local db = SP.EnsureDB()
    local s = (rest or ""):lower()
    if s == "account" or s == "accountwide" or s == "account-wide" then
      db.accountWide = true
      print("|cff33ccffSpatial Plates:|r using account-wide profile")
    elseif s == "char" or s == "character" or s == "perchar" or s == "per-character" then
      db.accountWide = false
      print("|cff33ccffSpatial Plates:|r using per-character profile (" .. GetCharKey() .. ")")
    else
      print("|cff33ccffSpatial Plates:|r scope is " .. (db.accountWide and "account-wide" or "per-character"))
      print("  usage: /splates scope <account|char>")
    end
  else
    PrintHelp()
  end
end

-- Register slash commands only when this addon's primary alias is not set.
local function RegisterSlashCommands()
  if not SLASH_SPATIALPLATES1 then
    SLASH_SPATIALPLATES1 = "/spatialplates"
    SLASH_SPATIALPLATES2 = "/splates"
    SlashCmdList["SPATIALPLATES"] = function(msg) HandleSlash(msg) end
  end
end
SP.RegisterSlashCommands = RegisterSlashCommands

-- ---------------------------------------------------------------------------
-- Options panel
-- ---------------------------------------------------------------------------
-- Built with plain frames so it works with or without InterfaceOptions /
-- Settings API. Live preview: a sample overlay frame that re-applies the
-- profile on every change.

local optionsFrame = nil
local previewText = nil
local previewFrame = nil

local function MakeLabel(parent, text, x, y)
  local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  f:SetText(text)
  return f
end

local function MakeCheck(parent, text, x, y, key)
  local c = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  c:SetWidth(24); c:SetHeight(24)
  local label = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("LEFT", c, "RIGHT", 2, 0)
  label:SetText(text)
  c:SetScript("OnClick", function(self)
    -- Guarded: if the template is missing on this client, GetChecked may
    -- not exist; treat as unchecked rather than erroring.
    local checked = false
    if self.GetChecked then
      local ok, v = pcall(self.GetChecked, self)
      checked = ok and v == true
    end
    SP.SetProfileValue(key, checked)
    if key == "autoThemeMatch" and checked and SP.AutoMatchNameplateTheme then
      SP.AutoMatchNameplateTheme()
    end
    if SP.RefreshPreview then SP.RefreshPreview() end
  end)
  c._key = key
  return c
end

local function MakeSlider(parent, labelText, x, y, minV, maxV, step, key, fmt)
  local label = MakeLabel(parent, labelText, x, y)
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 14)
  s:SetWidth(150); s:SetHeight(18)
  -- Guarded: template methods may be absent on clients without the template.
  if s.SetMinMaxValues then s:SetMinMaxValues(minV, maxV) end
  if s.SetValueStep then s:SetValueStep(step) end
  if s.SetObeyMessyMinMax then s:SetObeyMessyMinMax(true) end
  local val = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  val:SetPoint("LEFT", s, "RIGHT", 6, 0)
  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v / step + 0.5) * step
    SP.SetProfileValue(key, v)
    val:SetText(fmt and fmt(v) or tostring(v))
    if SP.RefreshPreview then SP.RefreshPreview() end
  end)
  s._key = key
  s._valLabel = val
  return s
end

local function MakeEdit(parent, labelText, x, y, key, width)
  MakeLabel(parent, labelText, x, y)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
  e:SetWidth(width or 160); e:SetHeight(20)
  e:SetAutoFocus(false)
  e:SetScript("OnEnterPressed", function(self)
    SP.SetProfileValue(key, self:GetText())
    if SP.RefreshPreview then SP.RefreshPreview() end
    self:ClearFocus()
  end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e._key = key
  return e
end

local function MakeDropdown(parent, labelText, x, y, options, key, width)
  MakeLabel(parent, labelText, x, y)
  local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 20, y - 16)
  dd:SetWidth(width or 170)
  -- Guarded: UIDropDownMenu globals may be absent on some clients.
  local hasDropdownAPI = UIDropDownMenu_Initialize and UIDropDownMenu_SetText
    and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton
  if hasDropdownAPI and UIDropDownMenu_SetWidth then
    UIDropDownMenu_SetWidth(dd, width or 170)
  end
  local function Refresh()
    if not hasDropdownAPI then return end
    local p = SP.GetProfile()
    UIDropDownMenu_SetText(dd, tostring(p[key]))
  end
  if hasDropdownAPI then
    UIDropDownMenu_Initialize(dd, function()
      for _, opt in ipairs(options) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = opt
        info.func = function()
          SP.SetProfileValue(key, opt)
          Refresh()
          if SP.RefreshPreview then SP.RefreshPreview() end
        end
        UIDropDownMenu_AddButton(info)
      end
    end)
  end
  dd._key = key
  dd._refresh = Refresh
  return dd
end

local function MakeColorButton(parent, labelText, x, y, key)
  MakeLabel(parent, labelText, x, y)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
  b:SetWidth(120); b:SetHeight(22)
  b:SetText("Pick color...")
  b:SetScript("OnClick", function()
    local picker = ColorPickerFrame
    if type(picker) ~= "table" and type(picker) ~= "userdata" then
      print("|cff33ccffSpatial Plates:|r color picker unavailable on this client")
      return
    end
    local pickerReady = pcall(function()
      if type(picker.SetColorRGB) ~= "function" or type(picker.Show) ~= "function" then
        error("missing legacy color-picker methods")
      end
    end)
    if not pickerReady then
      print("|cff33ccffSpatial Plates:|r color picker API unavailable on this client")
      return
    end
    local p = SP.GetProfile()
    local target = p
    for part in tostring(key):gmatch("[^.]+") do target = target and target[part] end
    local c = target or { r = 1, g = 1, b = 1, a = 1 }
    local prev = { r = c.r or 1, g = c.g or 1, b = c.b or 1, a = c.a or 1 }
    local function StoreColor(color)
      SP.SetProfileValue(key .. ".r", color.r)
      SP.SetProfileValue(key .. ".g", color.g)
      SP.SetProfileValue(key .. ".b", color.b)
      SP.SetProfileValue(key .. ".a", color.a)
    end
    local initialized = pcall(picker.SetColorRGB, picker, prev.r, prev.g, prev.b)
    if not initialized then
      print("|cff33ccffSpatial Plates:|r color picker could not be initialized")
      return
    end
    picker.hasOpacity = true
    picker.opacity = prev.a
    picker.previousValues = { prev.r, prev.g, prev.b, prev.a }
    picker.cancelFunc = function() StoreColor(prev) end
    picker.func = function()
      local ok, r, g, b = pcall(picker.GetColorRGB, picker)
      if not ok or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return end
      local a = prev.a
      if type(picker.GetColorAlpha) == "function" then
        local okAlpha, alpha = pcall(picker.GetColorAlpha, picker)
        if okAlpha and type(alpha) == "number" then a = alpha end
      elseif type(picker.opacity) == "number" then
        a = picker.opacity
      end
      StoreColor({ r = r, g = g, b = b, a = a })
      if SP.RefreshPreview then SP.RefreshPreview() end
    end
    local shown = pcall(picker.Show, picker)
    if not shown then print("|cff33ccffSpatial Plates:|r color picker could not be shown") end
  end)
  b._key = key
  return b
end

local function BuildOptionsPanel()
  if optionsFrame then return optionsFrame end
  local panel = CreateFrame("Frame", "SpatialPlates_OptionsPanel", UIParent)
  panel.name = "Spatial Plates"
  panel:SetWidth(440)
  panel:SetHeight(620)
  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(410)
  content:SetHeight(2400)
  scroll:SetScrollChild(content)

  MakeLabel(content, "Spatial Plates — Options", 12, -12)
  local sub = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  sub:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -30)
  sub:SetText("Changes apply live to player nameplate overlays. Use /splates help for commands.")
  sub:SetWidth(380)

  -- Column 1: toggles
  local y = -58
  local checks = {}
  local function AddCheck(text, key)
    local c = MakeCheck(content, text, 12, y, key)
    checks[#checks + 1] = c
    y = y - 24
  end
  AddCheck("Enabled", "enabled")
  AddCheck("Show distance", "showDistance")
  AddCheck("Show same map / map name", "showSubzone")
  AddCheck("Show indoors/outdoors", "showIndoors")
  AddCheck("Show underwater", "showUnderwater")
  MakeLabel(content, "Bearing unavailable: no safe non-secret API", 12, y)
  y = y - 24
  AddCheck("Background", "bgEnabled")
  AddCheck("Border", "borderEnabled")
  AddCheck("Hide in combat", "hideInCombat")
  AddCheck("Hide out of combat", "hideOutOfCombat")
  AddCheck("Hide when nameplate hidden", "hideWhenNameplateHidden")
  AddCheck("Hide when unit not visible", "hideWhenUnitNotVisible")
  AddCheck("Hide beyond max distance", "hideBeyondDistance")
  AddCheck("Hide in instances", "hideInInstances")
  AddCheck("Hide in open world", "hideInOpenWorld")
  AddCheck("Clamp to screen", "clampToScreen")
  AddCheck("Auto-detect nameplate parent frames", "autoDetect")
  AddCheck("Auto-match loaded nameplate addon theme", "autoThemeMatch")
  AddCheck("Debug output", "debug")

  -- Column 2 starts at the top independently; the scroll child keeps every
  -- control reachable even on the compact options canvas.
  y = -58
  local x2 = 230
  local sliders = {}
  local function AddSlider(labelText, minV, maxV, step, key, fmt)
    local s = MakeSlider(content, labelText, x2, y, minV, maxV, step, key, fmt)
    sliders[#sliders + 1] = s
    y = y - 44
  end
  AddSlider("Font size", 6, 32, 1, "fontSize", function(v) return tostring(v) .. "pt" end)
  AddSlider("Font alpha", 0, 1, 0.05, "fontAlpha", function(v) return string.format("%.2f", v) end)
  AddSlider("Scale", 0.5, 2.0, 0.05, "scale", function(v) return string.format("%.2f", v) end)
  AddSlider("Width", 20, 600, 5, "width")
  AddSlider("Height", 8, 80, 1, "height")
  AddSlider("Padding", 0, 24, 1, "padding")
  AddSlider("Offset X", -300, 300, 1, "offsetX")
  AddSlider("Offset Y", -300, 300, 1, "offsetY")
  AddSlider("Max distance (yd)", 1, 200, 1, "maxDistance")
  AddSlider("Update interval (s)", 0.1, 2.0, 0.05, "updateInterval", function(v) return string.format("%.2f", v) end)
  AddSlider("Frame level", 0, 100, 1, "frameLevel")
  AddSlider("Background edge size", 0, 32, 1, "bgEdgeSize")
  AddSlider("Background inset", 0, 32, 1, "bgInset")
  AddSlider("Border edge size", 0, 32, 1, "borderEdgeSize")

  local dropdowns = {}
  local function AddDropdown(labelText, options, key)
    local dd = MakeDropdown(content, labelText, x2, y, options, key)
    dropdowns[#dropdowns + 1] = dd
    y = y - 52
  end
  AddDropdown("Filter", { "all", "party", "raid", "guild", "friends" }, "filter")
  AddDropdown("Font outline", { "none", "outline", "thick" }, "fontOutline")
  AddDropdown("Color mode", { "custom", "class", "reaction", "perField" }, "colorMode")
  AddDropdown("Anchor", { "TOP", "BOTTOM", "LEFT", "RIGHT", "TOP-LEFT", "TOP-RIGHT", "BOTTOM-LEFT", "BOTTOM-RIGHT", "CENTER" }, "anchor")
  AddDropdown("Anchor to", { "TOP", "BOTTOM", "LEFT", "RIGHT", "TOP-LEFT", "TOP-RIGHT", "BOTTOM-LEFT", "BOTTOM-RIGHT", "CENTER" }, "anchorTo")
  AddDropdown("Strata", { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }, "strata")

  local edits = {}
  local function AddEdit(labelText, key, width)
    local e = MakeEdit(content, labelText, x2, y, key, width)
    edits[#edits + 1] = e
    y = y - 52
  end
  AddEdit("Distance format {d}", "formats.distance")
  AddEdit("Map-name format {zone}", "formats.subzone")
  AddEdit("Indoors format {env}", "formats.indoors")
  AddEdit("Underwater format {water}", "formats.underwater")
  AddEdit("Combined format", "formats.combined")
  AddEdit("Same-map text", "sameSubzoneText")
  AddEdit("Font (path or 'default')", "font")
  AddEdit("Background texture path", "bgTexture", 190)
  AddEdit("Border texture path", "borderTexture", 190)
  AddEdit("Border edge file path", "borderFile", 190)
  AddEdit("Custom parent func (global name)", "customParentFunc", 190)

  local colorButtons = {}
  local function AddColor(labelText, key)
    local b = MakeColorButton(content, labelText, x2, y, key)
    colorButtons[#colorButtons + 1] = b
    y = y - 52
  end
  AddColor("Font color", "fontColor")
  AddColor("Distance color", "fieldColors.distance")
  AddColor("Map-name color", "fieldColors.subzone")
  AddColor("Indoors color", "fieldColors.indoors")
  AddColor("Underwater color", "fieldColors.underwater")
  AddColor("Background color", "bgColor")
  AddColor("Border color", "borderColor")

  -- Theme preset buttons (row at bottom)
  local themeY = y - 8
  local autoThemeStatus = MakeLabel(content, "Last auto-match: none", 12, themeY + 26)
  if autoThemeStatus.SetWidth then autoThemeStatus:SetWidth(400) end
  MakeLabel(content, "Theme presets:", 12, themeY)
  local autoThemeButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  autoThemeButton:SetPoint("TOPLEFT", content, "TOPLEFT", 220, themeY)
  autoThemeButton:SetWidth(175); autoThemeButton:SetHeight(22)
  autoThemeButton:SetText("Detect / apply matching theme")
  autoThemeButton:SetScript("OnClick", function()
    local ok, theme, addonName = false, nil, nil
    if SP.AutoMatchNameplateTheme then
      ok, theme, addonName = SP.AutoMatchNameplateTheme(nil, true)
    end
    if ok then
      print("|cff33ccffSpatial Plates:|r matched " .. tostring(addonName) .. " → " .. tostring(theme))
    else
      print("|cff33ccffSpatial Plates:|r no supported nameplate replacement addon is loaded")
    end
  end)
  local themeNames = SP.PresetNames and SP.PresetNames() or { "Default" }
  local themeColumns = 4
  for index, name in ipairs(themeNames) do
    local col = (index - 1) % themeColumns
    local row = math.floor((index - 1) / themeColumns)
    local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", content, "TOPLEFT", 12 + col * 98, themeY - 18 - row * 26)
    b:SetWidth(92); b:SetHeight(22)
    b:SetText(name)
    b:SetScript("OnClick", function()
      if SP.ApplyPreset then
        local ok, err = SP.ApplyPreset(name)
        if not ok then print("|cff33ccffSpatial Plates:|r " .. SafeChatText(err)) end
        SP.RefreshOptionsPanel()
      end
    end)
  end

  -- Export / import / reset buttons follow however many rows of preset
  -- buttons are required, so new auto-match themes remain visible in-panel.
  local themeRows = math.max(1, math.ceil(#themeNames / themeColumns))
  local btnY = themeY - 52 - (themeRows - 1) * 26
  local expBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  expBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 12, btnY)
  expBtn:SetWidth(110); expBtn:SetHeight(22); expBtn:SetText("Export profile")
  expBtn:SetScript("OnClick", function()
    local s, err = SP.ExportProfile()
    if s then print("|cff33ccffSpatial Plates:|r export string:"); print(s)
    else print("|cff33ccffSpatial Plates:|r export failed: " .. tostring(err)) end
  end)

  local impBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  impBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 130, btnY)
  impBtn:SetWidth(110); impBtn:SetHeight(22); impBtn:SetText("Import profile")
  impBtn:SetScript("OnClick", function()
    -- Import via edit box below (avoids clipboard APIs).
    importBox:Show()
    importBox:SetFocus()
  end)

  local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  resetBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 248, btnY)
  resetBtn:SetWidth(110); resetBtn:SetHeight(22); resetBtn:SetText("Reset profile")
  resetBtn:SetScript("OnClick", function()
    SP.ResetProfile()
    SP.RefreshOptionsPanel()
  end)

  local importBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
  importBox:SetPoint("TOPLEFT", content, "TOPLEFT", 12, btnY - 28)
  importBox:SetWidth(380); importBox:SetHeight(20)
  importBox:SetText("Paste SP1:... string here, then press Enter")
  importBox:SetAutoFocus(false)
  importBox:Hide()
  importBox:SetScript("OnEnterPressed", function(self)
    local ok, err = SP.ImportProfile(self:GetText())
    if ok then
      print("|cff33ccffSpatial Plates:|r profile imported")
      SP.RefreshOptionsPanel()
    else
      print("|cff33ccffSpatial Plates:|r import rejected: " .. SafeChatText(err))
    end
    self:Hide()
  end)

  -- Scope toggle
  local scopeY = btnY - 60
  MakeLabel(content, "Profile scope:", 12, scopeY)
  local scopeBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  scopeBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 110, scopeY - 4)
  scopeBtn:SetWidth(150); scopeBtn:SetHeight(22)
  scopeBtn:SetScript("OnClick", function()
    local db = SP.EnsureDB()
    db.accountWide = not db.accountWide
    print("|cff33ccffSpatial Plates:|r scope: " .. (db.accountWide and "account-wide" or "per-character"))
    SP.RefreshOptionsPanel()
  end)
  scopeBtn._refresh = function()
    local db = SP.EnsureDB()
    scopeBtn:SetText(db.accountWide and "Account-wide" or "Per-character")
  end

  -- Live preview frame (bottom)
  local prevY = scopeY - 40
  MakeLabel(content, "Live preview:", 12, prevY)
  local pf = CreateFrame("Frame", "SpatialPlates_PreviewFrame", content)
  pf:SetPoint("TOPLEFT", content, "TOPLEFT", 12, prevY - 20)
  pf:SetWidth(380); pf:SetHeight(30)
  pf:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  local pt = pf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  pt:SetPoint("CENTER", pf, "CENTER", 0, 0)
  pt:SetText("12y | Same map")
  previewFrame = pf
  previewText = pt

  -- Refresh function: push current profile values into all controls.
  panel._refresh = function()
    local p = SP.GetProfile()
    for _, c in ipairs(checks) do
      if c.SetChecked then c:SetChecked(p[c._key] == true) end
    end
    for _, s in ipairs(sliders) do
      if s.SetValue then s:SetValue(p[s._key] or 0) end
    end
    for _, dd in ipairs(dropdowns) do if dd._refresh then dd._refresh() end end
    for _, e in ipairs(edits) do
      local value = p
      for part in tostring(e._key):gmatch("[^.]+") do value = value and value[part] end
      e:SetText(tostring(value or ""))
    end
    if scopeBtn._refresh then scopeBtn._refresh() end
    if autoThemeStatus.SetText then
      local addonName, matchedTheme
      if SP.GetAutoThemeStatus then addonName, matchedTheme = SP.GetAutoThemeStatus() end
      if addonName and matchedTheme then
        autoThemeStatus:SetText("Last auto-match: " .. addonName .. " → " .. matchedTheme)
      else
        autoThemeStatus:SetText("Last auto-match: none")
      end
    end
    if SP.RefreshPreview then SP.RefreshPreview() end
  end

  optionsFrame = panel
  return panel
end

-- Register the panel with the options UI. Tries the modern Settings API
-- first, falls back to InterfaceOptions, and finally to a plain frame.
local function RegisterOptionsPanel()
  local panel = BuildOptionsPanel()
  local registered = false
  if Settings and Settings.RegisterCanvasLayoutCategory then
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, panel.name)
    if ok and cat then
      pcall(Settings.RegisterAddOnCategory, cat)
      registered = true
    end
  end
  if not registered and InterfaceOptions_AddCategory then
    local ok = pcall(InterfaceOptions_AddCategory, panel)
    registered = ok
  end
  if not registered then
    -- Fallback: show as a movable frame via /splates config.
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:Hide()
  end
end
SP.RegisterOptionsPanel = RegisterOptionsPanel

function SP.RefreshOptionsPanel()
  if optionsFrame and optionsFrame._refresh then
    local ok, err = pcall(optionsFrame._refresh)
    if not ok then SP.DebugPrint("options refresh failed") end
  end
end

function SP.OpenOptions()
  RegisterOptionsPanel()
  if optionsFrame then
    SP.RefreshOptionsPanel()
    if optionsFrame:IsShown() then
      optionsFrame:Hide()
    else
      optionsFrame:Show()
    end
  end
end

-- Live preview updater (called by Appearance/Core after changes).
function SP.RefreshPreview()
  if not previewFrame or not previewText then return end
  if SP.ApplyAppearanceToFrame then
    local ok, err = pcall(SP.ApplyAppearanceToFrame, previewFrame, previewText)
    if not ok then SP.DebugPrint("preview apply failed") end
  end
  -- Sample text built from the combined template with fake readable values.
  local p = SP.GetProfile()
  local combined = (p.formats and p.formats.combined) or "{d}y | {zone}"
  local sample = combined:gsub("{d}", "12"):gsub("{zone}", p.sameSubzoneText or "Same map")
    :gsub("{env}", "Indoors"):gsub("{water}", "Underwater"):gsub("{dir}", "N")
  previewText:SetText(sample)
end

-- Initialize DB + slash + options on ADDON_LOADED (fires after all files load).
local initFrame = CreateFrame("Frame", "SpatialPlates_InitFrame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addonName)
  if event == "ADDON_LOADED" and addonName == "SpatialPlates" then
    SP.EnsureDB()
    SP.ValidateProfile(SP.GetProfile())
    RegisterSlashCommands()
    -- Defer options registration until Presets/Appearance exist.
    local ok, err = pcall(RegisterOptionsPanel)
    if not ok then SP.DebugPrint("options registration failed") end
    if SP.RefreshPreview then pcall(SP.RefreshPreview) end
  end
end)
