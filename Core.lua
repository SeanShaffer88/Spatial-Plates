-- SpatialPlates Core.lua
-- Main overlay engine: nameplate detection, friendly-player eligibility,
-- spatial field computation, visibility rules, throttled updates, cleanup.
--
-- SECRET-VALUE SAFETY (read this before editing):
-- * This addon is purely informational. It NEVER reads or computes health,
--   power, auras, cooldowns, damage, healing, threat, or any combat data.
-- * It NEVER uses the combat log, never automates decisions, and never hooks
--   insecure combat functions.
-- * Spatial API reads (UnitDistanceSquared, C_Map.*, UnitIsSubmerged, etc.)
--   are guarded with pcall, type checks, and issecretvalue checks where
--   available. Nil, wrong-type, or unreadable values fail closed (or the last
--   readable value is frozen in combat). This is defensive, not a guarantee
--   against errors or taint on every client build.
-- * Debug output prints only hide REASONS, never secret values.

SpatialPlates = SpatialPlates or {}
local SP = SpatialPlates

SP._overlays = {} -- [unit] = overlay frame (child of nameplate/custom parent)
SP._lastFields = {} -- [unit] = { distance=..., subzone=..., ... } last readable
SP._ticker = nil

-- ---------------------------------------------------------------------------
-- Secret-value guards
-- ---------------------------------------------------------------------------

-- True when `value` is safe to use: not nil, not secret (when the client
-- exposes issecretvalue), and of the expected type (when given).
local function IsReadable(value, expectedType)
  if value == nil then return false end
  if type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, value)
    -- If the client cannot tell whether a value is secret, fail closed.
    if not ok or secret == true then return false end
  end
  if expectedType and type(value) ~= expectedType then return false end
  return true
end
SP.IsReadable = IsReadable

-- pcall wrapper: returns the function's results, or nil on error.
-- Never throws. Use for every uncertain API call.
local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, result = pcall(fn, ...)
  if not ok then return nil end
  return result
end
SP.SafeCall = SafeCall

local function HasMethod(object, methodName)
  local objectType = type(object)
  if objectType ~= "table" and objectType ~= "userdata" then return false end
  local ok, method = pcall(function() return object[methodName] end)
  return ok and type(method) == "function"
end
SP.HasMethod = HasMethod

local function IsFrameLike(object)
  return IsReadable(object)
    and HasMethod(object, "SetPoint")
    and HasMethod(object, "CreateFontString")
end
SP.IsFrameLike = IsFrameLike

local function SafeBooleanCall(fn, ...)
  local value = SafeCall(fn, ...)
  if not IsReadable(value, "boolean") then return nil end
  return value
end
SP.SafeBooleanCall = SafeBooleanCall

-- ---------------------------------------------------------------------------
-- Unit eligibility (friendly players only)
-- ---------------------------------------------------------------------------

local function SafeUnitIsPlayer(unit)
  if type(UnitIsPlayer) ~= "function" then return false end
  return SafeBooleanCall(UnitIsPlayer, unit) == true
end

local function SafeUnitIsFriend(unit)
  if type(UnitIsFriend) ~= "function" then return false end
  return SafeBooleanCall(UnitIsFriend, "player", unit) == true
end

local function SafeIsSelf(unit)
  if type(UnitIsUnit) ~= "function" then return false end
  return SafeBooleanCall(UnitIsUnit, unit, "player") == true
end

-- True only for friendly players who are not the player.
-- Uses ONLY UnitIsPlayer / UnitIsFriend / UnitIsUnit (documented non-secret).
function SP.IsFriendlyPlayer(unit)
  if not IsReadable(unit, "string") or unit == "" then return false end
  if not SafeUnitIsPlayer(unit) then return false end
  if SafeIsSelf(unit) then return false end
  if not SafeUnitIsFriend(unit) then return false end
  return true
end

-- Apply the user's filter setting. All checks are pcall-guarded.
-- True only when the unit is on the player's actual friends list. Friendly
-- faction/UnitIsFriend status alone is not friend-list membership. If this
-- optional API is unavailable or cannot identify the unit, fail closed.
function SP.IsFriendListMember(unit)
  if type(unit) ~= "string" or unit == "" then return false end
  local friendQuery = C_FriendList and C_FriendList.IsFriend
  if type(friendQuery) ~= "function" then friendQuery = IsFriend end
  if type(friendQuery) ~= "function" then
    SP.DebugPrint("friends filter unavailable: friend-list query API missing")
    return false
  end

  local name, realm
  if type(UnitFullName) == "function" then
    local ok, n, r = pcall(UnitFullName, unit)
    if ok then name, realm = n, r end
  end
  if type(name) ~= "string" or name == "" then
    if type(UnitName) ~= "function" then return false end
    local ok, n, r = pcall(UnitName, unit)
    if ok then name, realm = n, r end
  end
  if not IsReadable(name, "string") or name == "" then return false end
  if realm ~= nil and (not IsReadable(realm, "string")) then return false end

  -- IsFriend accepts a character name; include the realm where available to
  -- avoid matching a same-named friend from another realm.
  local queryName = name
  if type(realm) == "string" and realm ~= "" then queryName = name .. "-" .. realm end
  local ok, result = pcall(friendQuery, queryName)
  if not ok or not IsReadable(result, "boolean") then return false end
  return result == true
end

function SP.PassesFilter(unit, profile)
  local filter = profile and profile.filter or "all"
  if filter == "all" then return true end
  if filter == "party" then
    if type(UnitIsParty) == "function" then return SafeBooleanCall(UnitIsParty, unit) == true end
    return false
  elseif filter == "raid" then
    if type(UnitIsRaid) == "function" then return SafeBooleanCall(UnitIsRaid, unit) == true end
    return false
  elseif filter == "guild" then
    if type(UnitIsInMyGuild) == "function" then return SafeBooleanCall(UnitIsInMyGuild, unit) == true end
    return false
  elseif filter == "friends" then
    return SP.IsFriendListMember(unit)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Nameplate / parent resolution
-- ---------------------------------------------------------------------------

-- Get the unit token for a nameplate frame, or nil.
local function GetNameplateUnit(frame)
  if not IsReadable(frame) or (type(frame) ~= "table" and type(frame) ~= "userdata") then return nil end
  -- Modern clients: frame:GetUnit(). Access and call are both protected
  -- because frames supplied by integrations may be unusual objects.
  local okGetUnit, getUnit = pcall(function() return frame.GetUnit end)
  if okGetUnit and type(getUnit) == "function" then
    local ok, unit = pcall(getUnit, frame)
    if ok and IsReadable(unit, "string") and unit ~= "" then return unit end
  end
  -- Legacy: frame.unit
  local ok, unit = pcall(function() return frame.unit end)
  if ok and IsReadable(unit, "string") and unit ~= "" then return unit end
  return nil
end

-- Get the default nameplate frame for a unit, or nil.
local function GetDefaultNameplate(unit)
  if C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function" then
    local frame = SafeCall(C_NamePlate.GetNamePlateForUnit, unit)
    if IsFrameLike(frame) then return frame end
  end
  if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
    local plates = SafeCall(C_NamePlate.GetNamePlates)
    if IsReadable(plates, "table") then
      for _, plate in ipairs(plates) do
        if GetNameplateUnit(plate) == unit and IsFrameLike(plate) then return plate end
      end
    end
  end
  return nil
end

-- Optional custom parent: user provides a global function name that returns
-- the frame to attach to for a given unit. Falls back safely when absent.
local function GetCustomParent(unit, profile)
  local funcName = profile and profile.customParentFunc
  if type(funcName) ~= "string" or funcName == "" then return nil end
  local fn = _G[funcName]
  if type(fn) ~= "function" then
    SP.DebugPrint("customParentFunc '" .. funcName .. "' not found; falling back")
    return nil
  end
  local frame = SafeCall(fn, unit)
  if IsFrameLike(frame) then return frame end
  SP.DebugPrint("customParentFunc '" .. funcName .. "' returned no frame; falling back")
  return nil
end

-- Optional auto-detection of common nameplate addons. Read-only checks of
-- known global names only; guarded when absent; never writes to their
-- frames (we only create our own child overlay). Disableable via profile.
local AUTO_DETECTORS = {
  -- Plater exposes nameplate lookup via its addon table (best-effort).
  function(unit)
    local plater = _G["Plater"]
    if type(plater) ~= "table" then return nil end
    if type(plater.GetNameplate) == "function" then
      return SafeCall(plater.GetNameplate, unit)
    end
    if type(plater.GetNamePlateForUnit) == "function" then
      return SafeCall(plater.GetNamePlateForUnit, unit)
    end
    return nil
  end,
  -- KuiNameplates exposes GetNameplateForUnit on its addon table.
  function(unit)
    local kui = _G["KuiNameplates"]
    if type(kui) ~= "table" then return nil end
    if type(kui.GetNameplateForUnit) == "function" then
      return SafeCall(kui.GetNameplateForUnit, unit)
    end
    if type(kui.GetNamePlateForUnit) == "function" then
      return SafeCall(kui.GetNamePlateForUnit, unit)
    end
    return nil
  end,
  -- ThreatPlates / ElvUI / TukUI: presence alone is not enough to find a
  -- frame safely, so these intentionally return nil and fall back to the
  -- default nameplate (which those suites still drive via the nameplate
  -- system). Listed here to document the read-only check.
  function(unit) return nil end, -- ThreatPlates placeholder
  function(unit) return nil end, -- ElvUI placeholder
  function(unit) return nil end, -- TukUI placeholder
}

local function GetAutoDetectedParent(unit, profile)
  if not (profile and profile.autoDetect) then return nil end
  for _, detector in ipairs(AUTO_DETECTORS) do
    local ok, frame = pcall(detector, unit)
    if ok and IsFrameLike(frame) then return frame end
  end
  return nil
end

-- Resolve the parent frame for an overlay: custom func -> auto-detect ->
-- default nameplate. Never nil-errors; returns nil only if no nameplate exists.
function SP.ResolveParent(unit, profile)
  profile = profile or SP.GetProfile()
  local custom = GetCustomParent(unit, profile)
  if custom then return custom end
  local auto = GetAutoDetectedParent(unit, profile)
  if auto then return auto end
  return GetDefaultNameplate(unit)
end

-- ---------------------------------------------------------------------------
-- Spatial field computation (each field hides cleanly when unreadable)
-- ---------------------------------------------------------------------------

local function GetPlayerMapID()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local id = SafeCall(C_Map.GetBestMapForUnit, "player")
  if IsReadable(id, "number") then return id end
  return nil
end

local function GetUnitMapID(unit)
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local id = SafeCall(C_Map.GetBestMapForUnit, unit)
  if IsReadable(id, "number") then return id end
  return nil
end

-- Distance in yards (integer) or nil. Requires UnitDistanceSquared AND a
-- same-map check via C_Map. Never does arithmetic on secret values: the
-- sqrt only runs after IsReadable confirms a plain number.
local function ComputeDistance(unit, profile)
  if not (profile and profile.showDistance) then return nil end
  if not UnitDistanceSquared then
    SP.DebugPrint("distance hidden: UnitDistanceSquared unavailable")
    return nil
  end
  local distSq = SafeCall(UnitDistanceSquared, unit)
  if not IsReadable(distSq, "number") then
    SP.DebugPrint("distance hidden: UnitDistanceSquared secret/unreadable")
    return nil
  end
  if distSq < 0 then
    SP.DebugPrint("distance hidden: negative value")
    return nil
  end
  -- Same-map requirement: distance is only meaningful on the same map.
  local playerMap = GetPlayerMapID()
  local unitMap = GetUnitMapID(unit)
  if playerMap == nil or unitMap == nil then
    SP.DebugPrint("distance hidden: map data unavailable")
    return nil
  end
  if playerMap ~= unitMap then
    SP.DebugPrint("distance hidden: different map")
    return nil
  end
  -- distSq is confirmed readable (plain number), so sqrt is safe.
  local yards = math.floor(math.sqrt(distSq) + 0.5)
  local fmt = (profile.formats and profile.formats.distance) or "{d}y"
  return SP.FormatTemplate(fmt, { d = tostring(yards) }), yards
end

-- Map-location text or nil. GetBestMapForUnit is map-granular, not a true subzone query.
local function ComputeSubzone(unit, profile)
  if not (profile and profile.showSubzone) then return nil end
  if not (C_Map and C_Map.GetBestMapForUnit) then
    SP.DebugPrint("map location hidden: C_Map.GetBestMapForUnit unavailable")
    return nil
  end
  local playerMap = GetPlayerMapID()
  local unitMap = GetUnitMapID(unit)
  if playerMap == nil or unitMap == nil then
    SP.DebugPrint("map location hidden: map data unavailable")
    return nil
  end
  local zoneName
  if playerMap == unitMap then
    zoneName = profile.sameSubzoneText or "Same map"
  else
    if not C_Map.GetMapInfo then
      SP.DebugPrint("map location hidden: C_Map.GetMapInfo unavailable")
      return nil
    end
    local info = SafeCall(C_Map.GetMapInfo, unitMap)
    if not IsReadable(info, "table") or not IsReadable(info.name, "string") or info.name == "" then
      SP.DebugPrint("map location hidden: map name unreadable")
      return nil
    end
    zoneName = info.name
  end
  local fmt = (profile.formats and profile.formats.subzone) or "{zone}"
  return SP.FormatTemplate(fmt, { zone = zoneName })
end

-- Indoors/outdoors text or nil. Only a readable UnitIsIndoors result is
-- authoritative; being in an instance does not imply indoors. Hide otherwise.
local function ComputeIndoors(unit, profile)
  if not (profile and profile.showIndoors) then return nil end
  local envText = nil
  if type(UnitIsIndoors) == "function" then
    local indoors = SafeBooleanCall(UnitIsIndoors, unit)
    if indoors == true then envText = "Indoors"
    elseif indoors == false then envText = "Outdoors" end
  end
  if envText == nil then
    SP.DebugPrint("indoors hidden: no supported environment API")
    return nil
  end
  local fmt = (profile.formats and profile.formats.indoors) or "{env}"
  return SP.FormatTemplate(fmt, { env = envText })
end

-- Underwater text or nil. Only shows when UnitIsSubmerged confirms submerged.
local function ComputeUnderwater(unit, profile)
  if not (profile and profile.showUnderwater) then return nil end
  if not UnitIsSubmerged then
    SP.DebugPrint("underwater hidden: UnitIsSubmerged unavailable")
    return nil
  end
  local submerged = SafeCall(UnitIsSubmerged, unit)
  -- UnitIsSubmerged returns 1 when submerged, nil otherwise. Check secrecy
  -- before even comparing the result; only a readable 1/true displays.
  if not IsReadable(submerged) then
    SP.DebugPrint("underwater hidden: value unreadable")
    return nil
  end
  if submerged ~= 1 and submerged ~= true then
    SP.DebugPrint("underwater hidden: not submerged or unreadable")
    return nil
  end
  local fmt = (profile.formats and profile.formats.underwater) or "{water}"
  return SP.FormatTemplate(fmt, { water = "Underwater" })
end

-- Bearing glyph/text or nil. There is NO safe non-secret bearing API in the
-- documented WoW API surface (unit facing/position are not exposed), so this
-- always returns nil. Kept internally only for backward compatibility with
-- imported profiles; no bearing control is offered in the UI.
local function ComputeBearing(unit, profile)
  if not (profile and profile.showBearing) then return nil end
  -- Imported older profiles may still request bearing. Log once rather than
  -- repeating the same unavailable-field warning on every ticker refresh.
  if not SP._bearingUnavailableLogged then
    SP._bearingUnavailableLogged = true
    SP.DebugPrint("bearing unavailable: this client exposes no safe non-secret API")
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Visibility rules
-- ---------------------------------------------------------------------------

local function IsInCombat()
  if type(InCombatLockdown) == "function" then
    local state = SafeBooleanCall(InCombatLockdown)
    -- Treat an unavailable/secret combat state conservatively as combat so
    -- previously readable fields freeze rather than being refreshed.
    if state == nil then return true end
    return state
  end
  return false
end

local function IsPlayerInInstance()
  if type(IsInInstance) ~= "function" then return false end
  return SafeBooleanCall(IsInInstance) == true
end

local function IsUnitVisible(unit)
  if type(UnitIsVisible) ~= "function" then return true end -- no API: assume visible
  local v = SafeBooleanCall(UnitIsVisible, unit)
  if v == nil then return true end -- unreadable: assume visible (do not hide)
  return v == true
end

-- Decide whether the overlay for `unit` should be visible.
-- `parent` is the resolved parent frame (may be nil). `distanceYards` is the
-- readable distance or nil. Returns (visible, reason).
local function ShouldShowOverlay(unit, profile, parent, distanceYards)
  if not profile.enabled then return false, "addon disabled" end
  if profile.hideInCombat and IsInCombat() then return false, "hideInCombat" end
  if profile.hideOutOfCombat and not IsInCombat() then return false, "hideOutOfCombat" end
  if profile.hideWhenNameplateHidden and parent and HasMethod(parent, "IsShown") then
    local shown = SafeCall(function() return parent:IsShown() end)
    if IsReadable(shown, "boolean") and shown == false then
      return false, "nameplate hidden"
    end
  end
  if profile.hideWhenUnitNotVisible and not IsUnitVisible(unit) then
    return false, "unit not visible"
  end
  if profile.hideInInstances and IsPlayerInInstance() then return false, "hideInInstances" end
  if profile.hideInOpenWorld and not IsPlayerInInstance() then return false, "hideInOpenWorld" end
  if profile.hideBeyondDistance then
    if distanceYards == nil then return false, "distance unavailable for max-distance rule" end
    if distanceYards > (profile.maxDistance or 60) then
      return false, "beyond max distance"
    end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Overlay lifecycle
-- ---------------------------------------------------------------------------

local function CreateOverlay(unit, parent)
  -- Nameplate unit tokens are reused (for example, nameplate1). Keep this
  -- frame unnamed so a removed/detached overlay cannot leave a stale global
  -- name that blocks creation when the token is assigned again.
  local overlay = CreateFrame("Frame", nil, parent)
  overlay:SetWidth(120)
  overlay:SetHeight(16)
  overlay:SetFrameStrata("MEDIUM")
  overlay:SetFrameLevel(10)
  local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("CENTER", overlay, "CENTER", 0, 0)
  overlay._spText = text
  overlay._spUnit = unit
  overlay._spParent = parent
  overlay:Hide()
  return overlay
end

-- Anchor the overlay to its parent per profile. Re-run every tick so custom
-- parents that move are followed (we only move our own child frame).
local function AnchorOverlay(overlay, parent, profile)
  if not overlay or not parent then return end
  local anchor = profile.anchor or "TOP"
  local anchorTo = profile.anchorTo or "TOP"
  local ox = profile.offsetX or 0
  local oy = profile.offsetY or 0
  overlay:ClearAllPoints()
  -- SetPoint(point, relativeTo, relativePoint, x, y). Anchor names like
  -- "TOP-LEFT" are valid points. Validate and guard frame operations.
  local ok = pcall(overlay.SetPoint, overlay, anchorTo, parent, anchor, ox, oy)
  if not ok then
    SP.DebugPrint("anchor failed for " .. tostring(anchorTo) .. "->" .. tostring(anchor))
    pcall(overlay.SetPoint, overlay, "TOP", parent, "TOP", 0, 4)
  end
end

local function HideOverlay(overlay)
  if not overlay then return end
  pcall(function()
    overlay:Hide()
    if overlay._spText then overlay._spText:SetText("") end
    overlay._spLastText = ""
  end)
end

-- Update one unit's overlay: compute fields, apply visibility, set text.
-- In combat, unreadable fields freeze at their last readable value instead
-- of clearing (never compute on secrets).
local function UpdateOverlay(unit)
  local profile = SP.GetProfile()
  local overlay = SP._overlays[unit]
  if not overlay then return end

  -- Re-check eligibility and the active filter on every refresh. Filters can
  -- change while these nameplate tokens remain tracked; hide rather than
  -- leaving stale overlays visible. They can show again if the filter changes.
  if not SP.IsFriendlyPlayer(unit) then
    HideOverlay(overlay)
    SP.DebugPrint("overlay hidden for " .. unit .. ": no longer a friendly player")
    return
  end
  if not SP.PassesFilter(unit, profile) then
    HideOverlay(overlay)
    SP.DebugPrint("overlay hidden for " .. unit .. ": filter=" .. tostring(profile.filter))
    return
  end

  -- Re-resolve parent (nameplate may have changed; custom func may return new).
  local parent = SP.ResolveParent(unit, profile)
  if not parent then
    HideOverlay(overlay)
    SP.DebugPrint("overlay hidden for " .. unit .. ": no parent frame")
    return
  end
  -- Re-parent if the resolved parent changed (e.g. nameplate reuse).
  if overlay._spParent ~= parent then
    overlay:SetParent(parent)
    overlay._spParent = parent
  end

  -- Compute each field (each hides cleanly when unreadable).
  local distText, distYards = ComputeDistance(unit, profile)
  local subText = ComputeSubzone(unit, profile)
  local envText = ComputeIndoors(unit, profile)
  local waterText = ComputeUnderwater(unit, profile)
  local dirText = ComputeBearing(unit, profile)

  -- Freeze last known non-secret values while in combat.
  local last = SP._lastFields[unit] or {}
  if IsInCombat() then
    if distText == nil and last.distance then
      distText = last.distance
      if distYards == nil then distYards = last.distanceYards end
    end
    if subText == nil and last.subzone then subText = last.subzone end
    if envText == nil and last.indoors then envText = last.indoors end
    if waterText == nil and last.underwater then waterText = last.underwater end
    if dirText == nil and last.bearing then dirText = last.bearing end
  else
    -- Out of combat: remember newly readable values for future freezes.
    if distText then last.distance = distText end
    if IsReadable(distYards, "number") then last.distanceYards = distYards end
    if subText then last.subzone = subText end
    if envText then last.indoors = envText end
    if waterText then last.underwater = waterText end
    if dirText then last.bearing = dirText end
  end
  SP._lastFields[unit] = last

  local fields = {
    distance = distText, subzone = subText,
    indoors = envText, underwater = waterText, bearing = dirText,
  }
  local combined = SP.BuildCombinedText(profile, fields)

  -- Visibility rules.
  local visible, reason = ShouldShowOverlay(unit, profile, parent, distYards)
  if not visible then
    HideOverlay(overlay)
    SP.DebugPrint("overlay hidden for " .. unit .. ": " .. tostring(reason))
    return
  end
  if combined == "" then
    HideOverlay(overlay)
    SP.DebugPrint("overlay hidden for " .. unit .. ": no readable fields")
    return
  end

  -- Show: only recompute anchor/layout when its inputs change. The ticker
  -- still tracks parent changes, while avoiding repeated ClearAllPoints calls.
  local anchor = profile.anchor or "TOP"
  local anchorTo = profile.anchorTo or "TOP"
  local offsetX = profile.offsetX or 0
  local offsetY = profile.offsetY or 0
  local anchorState = overlay._spAnchorState
  if not anchorState or anchorState.parent ~= parent
    or anchorState.anchor ~= anchor or anchorState.anchorTo ~= anchorTo
    or anchorState.offsetX ~= offsetX or anchorState.offsetY ~= offsetY then
    AnchorOverlay(overlay, parent, profile)
    overlay._spAnchorState = {
      parent = parent, anchor = anchor, anchorTo = anchorTo,
      offsetX = offsetX, offsetY = offsetY,
    }
  end

  -- Font/backdrop/size/color application is comparatively expensive. Reapply
  -- only when the profile revision changes; profile setters bump the revision.
  local appearanceRevision = SP._appearanceRevision or 0
  if overlay._spAppearanceRevision ~= appearanceRevision then
    local ok, err = pcall(SP.ApplyAppearanceToFrame, overlay, overlay._spText, unit)
    if ok then
      overlay._spAppearanceRevision = appearanceRevision
    else
      SP.DebugPrint("appearance apply failed")
    end
  end
  if overlay._spLastText ~= combined then
    overlay._spText:SetText(combined)
    overlay._spLastText = combined
  end
  overlay:Show()
end

-- Refresh every tracked overlay. Called by the ticker and on events.
function SP.RefreshAllOverlays()
  if type(SP._overlays) ~= "table" then return end
  -- Snapshot keys: UpdateOverlay may hide but never adds/removes here.
  local units = {}
  for unit in pairs(SP._overlays) do units[#units + 1] = unit end
  for _, unit in ipairs(units) do
    local ok, err = pcall(UpdateOverlay, unit)
    if not ok then SP.DebugPrint("overlay update failed") end
  end
end

-- Ensure an overlay exists for `unit` (create or reuse). Returns the overlay
-- or nil when the unit is not an eligible friendly player.
local function EnsureOverlay(unit)
  local profile = SP.GetProfile()
  if not SP.IsFriendlyPlayer(unit) then return nil end
  if not SP.PassesFilter(unit, profile) then
    SP.DebugPrint("overlay skipped for " .. unit .. ": filter=" .. tostring(profile.filter))
    return nil
  end
  local parent = SP.ResolveParent(unit, profile)
  if not parent then
    SP.DebugPrint("overlay skipped for " .. unit .. ": no parent frame")
    return nil
  end
  local existing = SP._overlays[unit]
  if existing then
    if existing._spParent ~= parent then
      existing:SetParent(parent)
      existing._spParent = parent
      existing._spAnchorState = nil
    end
    return existing
  end
  -- Never write bookkeeping fields onto nameplate/custom-parent frames: the
  -- only integration-side mutation is parenting our own overlay as a child.
  local overlay = CreateOverlay(unit, parent)
  SP._overlays[unit] = overlay
  return overlay
end

-- Clean up the overlay for `unit` (NAME_PLATE_UNIT_REMOVED). Hides and
-- releases the frame so nothing leaks. The frame itself is a child of the
-- nameplate, so it is collected with the nameplate; we just drop references.
local function CleanupOverlay(unit)
  local overlay = SP._overlays[unit]
  if overlay then
    local ok = pcall(function()
      HideOverlay(overlay)
      overlay:SetParent(nil)
      overlay:SetScript("OnUpdate", nil)
    end)
    if not ok then SP.DebugPrint("cleanup failed for " .. tostring(unit)) end
    SP._overlays[unit] = nil
  end
  SP._lastFields[unit] = nil
end
SP.CleanupOverlay = CleanupOverlay

-- Scan all current nameplates and ensure overlays for eligible units.
local function ScanNameplates()
  if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
  local plates = SafeCall(C_NamePlate.GetNamePlates)
  if type(plates) ~= "table" then return end
  for _, plate in ipairs(plates) do
    local unit = GetNameplateUnit(plate)
    if unit then
      local ok, err = pcall(EnsureOverlay, unit)
      if not ok then SP.DebugPrint("nameplate scan failed") end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Update loop (throttled ticker with OnUpdate fallback)
-- ---------------------------------------------------------------------------

local function RestartTicker()
  if SP._ticker then
    local ok = pcall(function() SP._ticker:Cancel() end)
    SP._ticker = nil
    if not ok then SP.DebugPrint("ticker cancel failed") end
  end
  local profile = SP.GetProfile()
  local interval = profile.updateInterval or 0.3
  if C_Timer and C_Timer.NewTicker then
    local ok, ticker = pcall(C_Timer.NewTicker, interval, function()
      SP.RefreshAllOverlays()
    end)
    if ok and ticker then
      SP._ticker = ticker
      return
    end
    SP.DebugPrint("C_Timer.NewTicker failed; using OnUpdate fallback")
  end
  -- Fallback: OnUpdate accumulator on the main frame.
  if SP._mainFrame then
    SP._mainFrame._spAccum = 0
    SP._mainFrame._spInterval = interval
    SP._mainFrame:SetScript("OnUpdate", function(self, dt)
      self._spAccum = (self._spAccum or 0) + (dt or 0)
      if self._spAccum >= (self._spInterval or 0.3) then
        self._spAccum = 0
        -- Pick up interval changes live.
        local p = SP.GetProfile()
        self._spInterval = p.updateInterval or 0.3
        SP.RefreshAllOverlays()
      end
    end)
  end
end
SP.RestartTicker = RestartTicker

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local mainFrame = CreateFrame("Frame", "SpatialPlates_MainFrame")
SP._mainFrame = mainFrame

mainFrame:RegisterEvent("ADDON_LOADED")
mainFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
mainFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
-- Friend-list events differ across client branches; registration is guarded so
-- an unavailable optional event cannot prevent the addon from loading.
pcall(mainFrame.RegisterEvent, mainFrame, "FRIENDLIST_UPDATE")
pcall(mainFrame.RegisterEvent, mainFrame, "BN_FRIEND_INFO_CHANGED")
mainFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
mainFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
mainFrame:RegisterEvent("ZONE_CHANGED")
mainFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

mainFrame:SetScript("OnEvent", function(self, event, unit)
  if event == "ADDON_LOADED" then
    -- Match a supported replacement addon whether it loaded before or after
    -- Spatial Plates. Preset application changes only our own visual profile.
    if SP.AutoMatchNameplateTheme then
      local ok, err = pcall(SP.AutoMatchNameplateTheme, unit)
      if not ok then SP.DebugPrint("theme auto-match failed") end
    end
    if unit ~= "SpatialPlates" then return end
    -- DB is initialized by Config.lua's ADDON_LOADED handler; ensure here too
    -- (handlers run in registration order, but be defensive).
    SP.EnsureDB()
    ScanNameplates()
    RestartTicker()
    SP.RefreshAllOverlays()
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    if IsReadable(unit, "string") then
      local ok, err = pcall(EnsureOverlay, unit)
      if not ok then SP.DebugPrint("nameplate add handling failed") end
      local ok2, err2 = pcall(UpdateOverlay, unit)
      if not ok2 then SP.DebugPrint("nameplate add update failed") end
    end
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    if IsReadable(unit, "string") then
      local ok, err = pcall(CleanupOverlay, unit)
      if not ok then SP.DebugPrint("nameplate cleanup failed") end
    end
  elseif event == "PLAYER_ENTERING_WORLD"
    or event == "GROUP_ROSTER_UPDATE"
    or event == "FRIENDLIST_UPDATE"
    or event == "BN_FRIEND_INFO_CHANGED"
    or event == "PLAYER_REGEN_ENABLED"
    or event == "PLAYER_REGEN_DISABLED"
    or event == "ZONE_CHANGED"
    or event == "ZONE_CHANGED_NEW_AREA" then
    -- Roster/combat/zone changes can affect eligibility or visibility.
    ScanNameplates()
    SP.RefreshAllOverlays()
  end
end)

-- Restart the ticker when the update interval changes (polled cheaply on
-- each refresh: if the ticker interval no longer matches, restart it).
local origRefresh = SP.RefreshAllOverlays
SP.RefreshAllOverlays = function()
  origRefresh()
  -- Cheap interval check: restart only when the value actually changed.
  local profile = SP.GetProfile()
  local interval = profile.updateInterval or 0.3
  if SP._mainFrame and SP._mainFrame._spInterval ~= nil then
    if math.abs((SP._mainFrame._spInterval or 0) - interval) > 0.001 then
      RestartTicker()
    end
  elseif SP._ticker then
    -- C_Timer ticker: restart when interval changes (track last interval).
    if SP._lastInterval == nil or math.abs(SP._lastInterval - interval) > 0.001 then
      SP._lastInterval = interval
      RestartTicker()
    end
  end
end
