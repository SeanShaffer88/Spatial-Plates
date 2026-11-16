-- Spatial Plates mocked-client regression suite.
-- Run from the repository root with Lua 5.1+ (or compatible WoW-era Lua):
--   lua tests/run.lua
-- The mock validates addon control flow; only a real client can validate API/version behavior.

local passed, failed = 0, 0
local failures = {}
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("PASS " .. name)
  else
    failed = failed + 1
    failures[#failures + 1] = name .. ": " .. tostring(err)
    print("FAIL " .. name .. ": " .. tostring(err))
  end
end
local function expect(value, message)
  if not value then error(message or "expected truthy value", 2) end
end
local function equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

-- -------------------------------------------------------------------------
-- Minimal WoW UI/API mock; individual tests can change the state below.
-- -------------------------------------------------------------------------
local frames, namedFrames = {}, {}
local units, friendNames, addonLoaded = {}, {}, {}
local mapByUnit, mapNames = { player = 100 }, { [100] = "Test Map", [200] = "Other Map" }
local secret = {}
local secretCheckThrows, distanceThrows, mapThrows, mapInfoThrows = false, false, false, false
local friendQueryThrows, friendQuerySecret = false, false
local combatState, instanceState = false, false
local tickerCallback, tickerThrows
local currentPlate
local currentCharName, currentRealm = "Tester", "Azeroth"

function issecretvalue(value)
  if secretCheckThrows then error("mock issecretvalue failure") end
  return value == secret
end

local function newFrame(name, parent)
  if name and namedFrames[name] then error("duplicate named frame: " .. name) end
  local frame = {
    _name = name, _parent = parent, _scripts = {}, _shown = true,
    _backdropCalls = 0, _pointCalls = 0, _width = 0, _height = 0,
  }
  if name then namedFrames[name] = frame end
  frames[#frames + 1] = frame
  function frame:RegisterEvent(event) self._events = self._events or {}; self._events[event] = true end
  function frame:SetScript(script, callback) self._scripts[script] = callback end
  function frame:SetPoint(...) self._pointCalls = self._pointCalls + 1; self._lastPoint = { ... } end
  function frame:ClearAllPoints() end
  function frame:SetWidth(value) self._width = value end
  function frame:SetHeight(value) self._height = value end
  function frame:SetScale(value) self._scale = value end
  function frame:SetFrameStrata(value) self._strata = value end
  function frame:SetFrameLevel(value) self._level = value end
  function frame:SetClampedToScreen(value) self._clamped = value end
  function frame:SetBackdrop(value) self._backdropCalls = self._backdropCalls + 1; self._backdrop = value end
  function frame:SetBackdropColor(...) end
  function frame:SetBackdropBorderColor(...) end
  function frame:SetMovable(value) end
  function frame:SetScrollChild(child) self._scrollChild = child end
  function frame:SetParent(parentValue) self._parent = parentValue end
  function frame:Hide() self._shown = false end
  function frame:Show() self._shown = true end
  function frame:IsShown() return self._shown end
  function frame:GetUnit() return self.unit end
  function frame:SetText(value) self._text = value end
  function frame:GetText() return self._text or "" end
  function frame:SetAutoFocus(value) end
  function frame:ClearFocus() end
  function frame:SetFocus() end
  function frame:SetChecked(value) self._checked = value end
  function frame:GetChecked() return self._checked end
  function frame:SetMinMaxValues() end
  function frame:SetValueStep() end
  function frame:SetObeyMessyMinMax() end
  function frame:SetValue(value) self._value = value end
  function frame:SetTexture(value) self._texture = value end
  function frame:SetColorTexture(...) end
  function frame:SetTexCoord(...) end
  function frame:SetAllPoints() end
  function frame:EnableMouse() end
  function frame:RegisterForDrag() end
  function frame:SetHighlightTexture() end
  function frame:GetCenter() return 100, 100 end
  function frame:GetEffectiveScale() return 1 end
  function frame:CreateFontString()
    local text = { _text = "", _fontCalls = 0, _pointCalls = 0 }
    function text:SetPoint(...) self._pointCalls = self._pointCalls + 1 end
    function text:ClearAllPoints() end
    function text:SetText(value) self._text = value end
    function text:GetText() return self._text end
    function text:SetTextColor(...) end
    function text:SetJustifyH() end
    function text:SetJustifyV() end
    function text:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function text:SetFont(...) self._fontCalls = self._fontCalls + 1 end
    function text:SetWidth() end
    function text:SetHeight() end
    return text
  end
  function frame:CreateTexture() return newFrame(nil, self) end
  return frame
end

function CreateFrame(frameType, name, parent, template)
  return newFrame(name, parent)
end
UIParent = newFrame("UIParent")
SlashCmdList = {}

function UnitName(unit)
  if unit == "player" then return currentCharName, currentRealm end
  local data = units[unit]
  if data then return data.name, data.realm end
  return nil
end
function UnitFullName(unit) return UnitName(unit) end
function GetRealmName() return currentRealm end
function UnitIsPlayer(unit) local d = units[unit]; return d and d.isPlayer or false end
function UnitIsFriend(_, unit) local d = units[unit]; return d and d.friendly or false end
function UnitIsUnit(unit, other) return unit == "self" or (unit == "player" and other == "player") end
function UnitIsParty(unit) local d = units[unit]; return d and d.party or false end
function UnitIsRaid(unit) local d = units[unit]; return d and d.raid or false end
function UnitIsInMyGuild(unit) local d = units[unit]; return d and d.guild or false end
function UnitIsVisible(unit) local d = units[unit]; return d and d.visible ~= false or false end
function UnitClass(unit) local d = units[unit]; return d and d.className or "Mage", d and d.classToken or "MAGE", 8 end
function UnitIsEnemy(_, unit) local d = units[unit]; return d and d.enemy or false end
function UnitCanAttack(_, unit) local d = units[unit]; return d and (d.canAttack or d.enemy) or false end
function UnitDistanceSquared(unit)
  if distanceThrows then error("mock distance error") end
  local d = units[unit]
  return d and d.distanceSq
end
function UnitIsIndoors(unit) local d = units[unit]; return d and d.indoors end
function UnitIsSubmerged(unit) local d = units[unit]; return d and d.submerged end
function InCombatLockdown() return combatState end
local interactRange = {} -- [unit] = yards for CheckInteractDistance mock
-- Installed only by the tests that exercise the coarse-range fallback.
local function MockCheckInteractDistance(unit, index)
  local yards = interactRange[unit]
  if yards == nil then return false end
  if index == 3 then return yards <= 10 end
  if index == 4 then return yards <= 28 end
  return false
end
function IsInInstance() return instanceState, instanceState and "party" or "none" end

C_Map = {
  GetBestMapForUnit = function(unit)
    if mapThrows then error("mock map error") end
    return mapByUnit[unit]
  end,
  GetMapInfo = function(mapID)
    if mapInfoThrows then error("mock map info error") end
    local name = mapNames[mapID]
    if name == secret then return secret end
    return name and { name = name } or nil
  end,
}
C_NamePlate = {
  GetNamePlateForUnit = function(unit)
    if currentPlate and currentPlate.unit == unit then return currentPlate end
    return nil
  end,
  GetNamePlates = function()
    return currentPlate and { currentPlate } or {}
  end,
}
C_FriendList = {
  IsFriend = function(fullName)
    if friendQueryThrows then error("mock friend API error") end
    if friendQuerySecret then return secret end
    return friendNames[fullName] == true
  end,
}
C_AddOns = { IsAddOnLoaded = function(addonName) return addonLoaded[addonName] == true end }
C_Timer = {
  NewTicker = function(interval, callback)
    if tickerThrows then error("mock ticker error") end
    tickerCallback = callback
    return { Cancel = function() end }
  end,
}
RAID_CLASS_COLORS = { MAGE = { r = 0.3, g = 0.7, b = 1.0 } }

-- Load the addon in its declared order, as the TOC does.
dofile("SpatialPlates/Config.lua")
dofile("SpatialPlates/Presets.lua")
dofile("SpatialPlates/Appearance.lua")
dofile("SpatialPlates/Range.lua")
dofile("SpatialPlates/Core.lua")
Minimap = newFrame("Minimap", UIParent)
UISpecialFrames = {}
function GetCursorPosition() return 150, 100 end
dofile("SpatialPlates/Minimap.lua")
local SP = SpatialPlates

local function resetProfile()
  SpatialPlatesDB = nil
  SP.EnsureDB()
  SP.ValidateProfile(SP.GetProfile())
end
local function setUnit(unit, values)
  units[unit] = values
  mapByUnit[unit] = values.map or 100
end
local function fire(eventName, arg)
  local handler = SP._mainFrame and SP._mainFrame._scripts.OnEvent
  if handler then handler(SP._mainFrame, eventName, arg) end
end
local function clearOverlays()
  local keys = {}
  for unit in pairs(SP._overlays or {}) do keys[#keys + 1] = unit end
  for _, unit in ipairs(keys) do SP.CleanupOverlay(unit) end
  currentPlate = nil
end

setUnit("friend", {
  isPlayer = true, friendly = true, name = "Alice", realm = "Azeroth",
  party = true, raid = true, guild = true, visible = true, distanceSq = 144,
  map = 100, className = "Mage", classToken = "MAGE",
})
setUnit("enemy", { isPlayer = true, friendly = false, enemy = true, visible = true, distanceSq = 16, map = 100 })
setUnit("npc", { isPlayer = false, friendly = true, visible = true, distanceSq = 16, map = 100 })
setUnit("mob", { isPlayer = false, friendly = false, enemy = true, visible = true, distanceSq = 16, map = 100 })
setUnit("neutralmob", { isPlayer = false, friendly = false, canAttack = true, visible = true, distanceSq = 16, map = 100 })
setUnit("critter", { isPlayer = false, friendly = false, canAttack = false, visible = true, distanceSq = 16, map = 100 })
setUnit("secret-player", { isPlayer = secret, friendly = true })
setUnit("secret-friend", { isPlayer = true, friendly = secret })

-- -------------------------------------------------------------------------
-- Matrix-linked regression tests.
-- -------------------------------------------------------------------------
test("DB1 defaults, corruption recovery, profile schema and numeric clamps", function()
  resetProfile()
  equal(SP.GetProfile().filter, "all")
  SpatialPlatesDB = "corrupt"
  expect(type(SP.EnsureDB()) == "table")
  local p = SP.GetProfile()
  p.fontSize = 0 / 0
  p.strata = "NOT_A_STRATUM"
  p.filter = "invalid"
  SP.ValidateProfile(p)
  equal(p.fontSize, 11)
  equal(p.strata, "MEDIUM")
  equal(p.filter, "all")
  expect(not SP.SetProfileValue("arbitrary.injected", true))
  expect(not SP.SetProfileValue("fontSize", "large"))
  expect(not SP.SetProfileValue("formats..distance", "oops"))
  expect(not SP.SetProfileValue(".fontSize", 12))
  SP.SetProfileValue("customParentFunc", "Bad|cffff0000Name")
  equal(SP.GetProfile().customParentFunc, "")
  SpatialPlatesDB.autoThemeAddon = "|cffff0000fake"
  SP.EnsureDB()
  equal(SpatialPlatesDB.autoThemeAddon, nil)
end)

test("DB2 account/character profiles deep-copy nested colors", function()
  resetProfile()
  SP.SetProfileValue("fieldColors.distance.r", 0.2)
  local account = SP.GetProfile()
  SpatialPlatesDB.accountWide = false
  local character = SP.GetProfile()
  expect(character.fieldColors.distance ~= account.fieldColors.distance)
  SP.SetProfileValue("fieldColors.distance.r", 0.8)
  equal(character.fieldColors.distance.r, 0.8)
  SpatialPlatesDB.accountWide = true
  equal(SP.GetProfile().fieldColors.distance.r, 0.2)
end)

test("CFG1 import/export round-trip, duplicate rejection and bounded malformed input", function()
  resetProfile()
  SP.SetProfileValue("fontSize", 19)
  SP.SetProfileValue("formats.combined", "{d}y | {zone} 100%")
  local exported = SP.ExportProfile()
  expect(exported:match("^SP1:1:"))
  SP.SetProfileValue("fontSize", 7)
  expect(SP.ImportProfile(exported))
  equal(SP.GetProfile().fontSize, 19)
  equal(SP.GetProfile().formats.combined, "{d}y | {zone} 100%")
  local before = SP.GetProfile().fontSize
  expect(not SP.ImportProfile("SP1:1:fontSize=2|fontSize=3"))
  expect(not SP.ImportProfile("SP1:1:unknown=1"))
  expect(not SP.ImportProfile("SP9:1:fontSize=12"))
  expect(not SP.ImportProfile("SP1:1:fontSize=nan"))
  expect(not SP.ImportProfile("SP1:1:broken"))
  expect(not SP.ImportProfile(string.rep("x", 8193)))
  equal(SP.GetProfile().fontSize, before, "bad import changed live profile")
  -- Unknown/cyclic SavedVariables are ignored by the export whitelist.
  local p = SP.GetProfile(); p.unknown = p
  local safeExport = SP.ExportProfile()
  expect(type(safeExport) == "string" and SP.ImportProfile(safeExport))
end)

test("FMT1 literal percent substitution, markup escaping and missing fields", function()
  resetProfile()
  equal(SP.FormatTemplate("{zone}", { zone = "Map%1" }), "Map%1")
  local escaped = SP.FormatTemplate("{zone}", { zone = "|cffff0000Spoof" })
  expect(escaped:find("||cffff0000Spoof", 1, true))
  local unsafeTemplate = SP.FormatTemplate("|cffff0000{zone}|r", { zone = "x" })
  expect(unsafeTemplate:find("||cffff0000", 1, true))
  local p = SP.GetProfile()
  equal(SP.BuildCombinedText(p, { subzone = "Same map" }), "Same map")
  equal(SP.BuildCombinedText(p, {}), "")
  p.colorMode = "perField"
  p.fieldColors.distance = { r = 1, g = 0, b = 0, a = 1 }
  p.fieldColors.subzone = { r = 0, g = 0, b = 1, a = 1 }
  local styled = SP.BuildCombinedText(p, { distance = "12y", subzone = "Same map" })
  expect(styled:find("|cffff0000", 1, true), "distance per-field color missing")
  expect(styled:find("|cff0000ff", 1, true), "map per-field color missing")
end)

test("ELIG1 friendly player eligibility rejects NPCs, enemies, self and secret booleans", function()
  expect(SP.IsFriendlyPlayer("friend"))
  expect(not SP.IsFriendlyPlayer("npc"))
  expect(not SP.IsFriendlyPlayer("enemy"))
  expect(not SP.IsFriendlyPlayer("secret-player"))
  expect(not SP.IsFriendlyPlayer("secret-friend"))
  expect(not SP.IsFriendlyPlayer("player"))
  secretCheckThrows = true
  expect(not SP.IsFriendlyPlayer("friend"), "secret check error must fail closed")
  secretCheckThrows = false
end)

test("FILTER1 party/raid/guild/friends semantics and unavailable friend API fail closed", function()
  resetProfile()
  local p = SP.GetProfile()
  for filter, expected in pairs({ all = true, party = true, raid = true, guild = true }) do
    p.filter = filter
    equal(SP.PassesFilter("friend", p), expected)
  end
  p.filter = "friends"
  friendNames["Alice-Azeroth"] = true
  expect(SP.PassesFilter("friend", p))
  friendNames["Alice-Azeroth"] = nil
  expect(not SP.PassesFilter("friend", p))
  local saved = C_FriendList
  C_FriendList = nil
  IsFriend = nil
  expect(not SP.PassesFilter("friend", p))
  C_FriendList = saved
  friendQueryThrows = true
  expect(not SP.PassesFilter("friend", p))
  friendQueryThrows = false
  friendQuerySecret = true
  expect(not SP.PassesFilter("friend", p))
  friendQuerySecret = false
end)

test("API1 nil, thrown, wrong-type and secret spatial API values fail closed", function()
  resetProfile(); clearOverlays()
  currentPlate = CreateFrame("Frame", "PlateAPI1", UIParent)
  currentPlate.unit = "friend"
  units.friend.distanceSq = secret
  fire("NAME_PLATE_UNIT_ADDED", "friend")
  local overlay = SP._overlays.friend
  expect(overlay and overlay:IsShown())
  equal(overlay._spText:GetText(), "Same map")
  units.friend.distanceSq = "12"
  SP.RefreshAllOverlays()
  equal(overlay._spText:GetText(), "Same map")
  distanceThrows = true
  SP.RefreshAllOverlays()
  expect(overlay:IsShown())
  distanceThrows = false
  units.friend.distanceSq = 144
  mapByUnit.friend = nil
  SP.RefreshAllOverlays()
  equal(overlay._spText:GetText(), "")
  expect(not overlay:IsShown())
  mapByUnit.friend = 100
  mapThrows = true
  SP.RefreshAllOverlays()
  expect(not overlay:IsShown())
  mapThrows = false
  clearOverlays()
  units.friend.distanceSq = 144
end)

test("API2 map names, percent characters and WoW markup are inert display text", function()
  resetProfile(); clearOverlays()
  currentPlate = CreateFrame("Frame", "PlateAPI2", UIParent); currentPlate.unit = "friend"
  mapByUnit.friend = 200
  mapNames[200] = "100% |cffff0000Spoof"
  fire("NAME_PLATE_UNIT_ADDED", "friend")
  local text = SP._overlays.friend._spText:GetText()
  expect(text:find("100%%", 1, false))
  expect(text:find("||cffff0000Spoof", 1, true))
  mapInfoThrows = true
  SP.RefreshAllOverlays()
  expect(not SP._overlays.friend:IsShown())
  mapInfoThrows = false
  mapByUnit.friend = 100
  clearOverlays()
end)

test("API3 secret indoors/underwater and issecretvalue failure never expose fields", function()
  resetProfile(); clearOverlays()
  local p = SP.GetProfile(); p.showIndoors = true; p.showUnderwater = true
  units.friend.indoors = secret; units.friend.submerged = secret
  currentPlate = CreateFrame("Frame", "PlateAPI3", UIParent); currentPlate.unit = "friend"
  fire("NAME_PLATE_UNIT_ADDED", "friend")
  equal(SP._overlays.friend._spText:GetText(), "12y | Same map")
  secretCheckThrows = true
  SP.RefreshAllOverlays()
  expect(not SP._overlays.friend:IsShown())
  secretCheckThrows = false
  clearOverlays(); units.friend.indoors = nil; units.friend.submerged = nil
end)

test("API4 negative distance, missing functions, secret map-info table and wrong boolean types degrade", function()
  resetProfile(); clearOverlays()
  local p = SP.GetProfile()
  currentPlate = CreateFrame("Frame", "PlateAPI4", UIParent); currentPlate.unit = "friend"
  units.friend.distanceSq = -1
  fire("NAME_PLATE_UNIT_ADDED", "friend")
  expect(SP._overlays.friend:IsShown())
  equal(SP._overlays.friend._spText:GetText(), "Same map")
  units.friend.distanceSq = 144
  local distanceAPI = UnitDistanceSquared
  UnitDistanceSquared = nil
  SP.RefreshAllOverlays()
  equal(SP._overlays.friend._spText:GetText(), "Same map")
  UnitDistanceSquared = distanceAPI
  p.showSubzone = true
  mapByUnit.friend = 200; mapNames[200] = secret
  SP.RefreshAllOverlays()
  expect(not SP._overlays.friend:IsShown())
  mapByUnit.friend = 100
  units.friend.indoors = 1 -- wrong type: never label as indoors/outdoors
  p.showIndoors = true
  SP.RefreshAllOverlays()
  expect(SP._overlays.friend:IsShown())
  expect(not SP._overlays.friend._spText:GetText():find("Indoors", 1, true))
  units.friend.indoors = nil
  clearOverlays()
end)

test("VIS1 distance threshold hides beyond and hides when distance unknown", function()
  resetProfile(); clearOverlays()
  local p = SP.GetProfile(); p.hideBeyondDistance = true; p.maxDistance = 5
  currentPlate = CreateFrame("Frame", "PlateVIS1", UIParent); currentPlate.unit = "friend"
  units.friend.distanceSq = 144
  fire("NAME_PLATE_UNIT_ADDED", "friend")
  expect(not SP._overlays.friend:IsShown())
  units.friend.distanceSq = secret
  SP.RefreshAllOverlays()
  expect(not SP._overlays.friend:IsShown())
  p.hideBeyondDistance = false; p.hideInCombat = true; combatState = true
  SP.RefreshAllOverlays(); expect(not SP._overlays.friend:IsShown())
  combatState = false; p.hideInCombat = false
  units.friend.distanceSq = 144
  clearOverlays()
end)

test("VIS2 plate/unit visibility and instance rules hide and restore without errors", function()
  resetProfile(); clearOverlays(); instanceState = false
  local p = SP.GetProfile()
  currentPlate = CreateFrame("Frame", "PlateVIS2", UIParent); currentPlate.unit = "friend"
  units.friend.visible = true
  fire("NAME_PLATE_UNIT_ADDED", "friend")
  local overlay = SP._overlays.friend
  expect(overlay:IsShown())
  p.hideWhenNameplateHidden = true; currentPlate:Hide(); SP.RefreshAllOverlays()
  expect(not overlay:IsShown())
  currentPlate:Show(); SP.RefreshAllOverlays(); expect(overlay:IsShown())
  p.hideWhenUnitNotVisible = true; units.friend.visible = false; SP.RefreshAllOverlays()
  expect(not overlay:IsShown())
  units.friend.visible = true; p.hideInInstances = true; instanceState = true
  SP.RefreshAllOverlays(); expect(not overlay:IsShown())
  instanceState = false; p.hideInInstances = false; SP.RefreshAllOverlays()
  expect(overlay:IsShown())
  clearOverlays(); instanceState = false; units.friend.visible = true
end)

test("COMBAT1 readable fields freeze in combat and cached max-distance checks remain safe", function()
  resetProfile(); clearOverlays(); combatState = false
  local p = SP.GetProfile()
  currentPlate = CreateFrame("Frame", "PlateCOMBAT1", UIParent); currentPlate.unit = "friend"
  units.friend.distanceSq = 144
  fire("NAME_PLATE_UNIT_ADDED", "friend")
  local overlay = SP._overlays.friend
  expect(overlay:IsShown())
  local previous = overlay._spText:GetText()
  combatState = true; units.friend.distanceSq = secret
  SP.RefreshAllOverlays()
  equal(overlay._spText:GetText(), previous)
  p.hideBeyondDistance = true; p.maxDistance = 20
  SP.RefreshAllOverlays(); expect(overlay:IsShown())
  p.maxDistance = 10
  SP.RefreshAllOverlays(); expect(not overlay:IsShown())
  combatState = false; units.friend.distanceSq = 144
  clearOverlays()
end)

test("FILTER2 tracked plates react immediately to profile and friend-list changes", function()
  resetProfile(); clearOverlays()
  local p = SP.GetProfile()
  currentPlate = CreateFrame("Frame", "PlateFILTER2", UIParent); currentPlate.unit = "friend"
  fire("NAME_PLATE_UNIT_ADDED", "friend")
  local overlay = SP._overlays.friend
  expect(overlay:IsShown())
  p.filter = "party"; units.friend.party = false; SP.RefreshAllOverlays(); expect(not overlay:IsShown())
  p.filter = "all"; SP.RefreshAllOverlays(); expect(overlay:IsShown())
  p.filter = "friends"; friendNames["Alice-Azeroth"] = true
  fire("FRIENDLIST_UPDATE"); expect(overlay:IsShown())
  friendNames["Alice-Azeroth"] = nil; fire("FRIENDLIST_UPDATE"); expect(not overlay:IsShown())
  clearOverlays(); units.friend.party = true
end)

test("FRAME1 unnamed overlays survive token reuse and never annotate host frames", function()
  resetProfile(); clearOverlays()
  local hostA = CreateFrame("Frame", "HostFrameA", UIParent); hostA.unit = "friend"
  currentPlate = hostA
  fire("NAME_PLATE_UNIT_ADDED", "friend")
  local first = SP._overlays.friend
  expect(first and first._name == nil)
  equal(hostA._spOverlay, nil, "host frame was modified")
  fire("NAME_PLATE_UNIT_REMOVED", "friend")
  local hostB = CreateFrame("Frame", "HostFrameB", UIParent); hostB.unit = "friend"
  currentPlate = hostB
  fire("NAME_PLATE_UNIT_ADDED", "friend")
  local second = SP._overlays.friend
  expect(second and second ~= first and second._name == nil)
  equal(hostB._spOverlay, nil, "new host frame was modified")
  clearOverlays()
end)

test("PARENT1 custom parent success, exception and invalid return safely fall back", function()
  resetProfile(); clearOverlays()
  local base = CreateFrame("Frame", "BaseParent", UIParent)
  currentPlate = CreateFrame("Frame", "DefaultParent", UIParent); currentPlate.unit = "friend"
  C_NamePlate.GetNamePlateForUnit = function() return currentPlate end
  local custom = CreateFrame("Frame", "CustomParent", UIParent)
  MySpatialParent = function() return custom end
  SP.SetProfileValue("customParentFunc", "MySpatialParent")
  fire("NAME_PLATE_UNIT_ADDED", "friend")
  local overlay = SP._overlays.friend
  equal(overlay._spParent, custom)
  equal(custom._spOverlay, nil)
  MySpatialParent = function() error("integration failure") end
  SP.RefreshAllOverlays()
  equal(overlay._spParent, currentPlate)
  MySpatialParent = function() return "not a frame" end
  SP.RefreshAllOverlays()
  equal(overlay._spParent, currentPlate)
  SP.SetProfileValue("customParentFunc", "missingFunction")
  SP.RefreshAllOverlays()
  equal(overlay._spParent, currentPlate)
  clearOverlays()
end)

test("PARENT2 optional Plater detection is read-only and bad detector objects fall back", function()
  resetProfile(); clearOverlays()
  local p = SP.GetProfile(); p.autoDetect = true
  currentPlate = CreateFrame("Frame", "PlatePARENT2", UIParent); currentPlate.unit = "friend"
  local addonFrame = CreateFrame("Frame", "AddonParent", UIParent)
  Plater = { GetNameplate = function(unit) return addonFrame end }
  fire("NAME_PLATE_UNIT_ADDED", "friend")
  equal(SP._overlays.friend._spParent, addonFrame)
  equal(addonFrame._spOverlay, nil)
  clearOverlays()
  currentPlate = CreateFrame("Frame", "PlatePARENT2Fallback", UIParent); currentPlate.unit = "friend"
  Plater = setmetatable({}, { __index = function() error("hostile detector metatable") end })
  fire("NAME_PLATE_UNIT_ADDED", "friend")
  equal(SP._overlays.friend._spParent, currentPlate)
  clearOverlays(); Plater = nil
end)

test("STYLE1 class colors use the class-file token and appearance work is cached", function()
  resetProfile(); clearOverlays()
  local p = SP.GetProfile(); p.colorMode = "class"
  local classColor = SP.GetClassColor("friend")
  equal(classColor.r, 0.3); equal(classColor.g, 0.7)
  local reactionColor = SP.GetReactionColor("friend")
  equal(reactionColor.g, 1.0)
  currentPlate = CreateFrame("Frame", "PlateSTYLE1", UIParent); currentPlate.unit = "friend"
  fire("NAME_PLATE_UNIT_ADDED", "friend")
  local overlay = SP._overlays.friend
  local backdropCount = overlay._backdropCalls
  local pointCount = overlay._pointCalls
  SP.RefreshAllOverlays(); SP.RefreshAllOverlays()
  equal(overlay._backdropCalls, backdropCount)
  equal(overlay._pointCalls, pointCount)
  SP.SetProfileValue("fontSize", 16)
  expect(overlay._backdropCalls > backdropCount)
  local afterChange = overlay._backdropCalls
  SP.RefreshAllOverlays()
  equal(overlay._backdropCalls, afterChange)
  clearOverlays()
end)

test("THEME1 presets match load order, manual force, disabled preference and status", function()
  resetProfile()
  local p = SP.GetProfile(); p.autoThemeMatch = true
  addonLoaded.Plater = true
  expect(SP.AutoMatchNameplateTheme() == true)
  equal(p.colorMode, "class")
  local addon, theme = SP.GetAutoThemeStatus()
  equal(addon, "Plater"); equal(theme, "Plater-like")
  p.fontSize = 27
  expect(SP.AutoMatchNameplateTheme() == false)
  equal(p.fontSize, 27)
  p.autoThemeMatch = false; addonLoaded.ThreatPlates = true
  local ok, forcedTheme, forcedAddon = SP.AutoMatchNameplateTheme("ThreatPlates", true)
  expect(ok); equal(forcedTheme, "ThreatPlates-like"); equal(forcedAddon, "ThreatPlates")
  equal(p.fontOutline, "thick")
  addonLoaded = {}
  expect(not SP.AutoMatchNameplateTheme(nil, true))
end)

test("SLASH1 invalid commands/import are non-throwing; map alias and unsupported bearing", function()
  resetProfile(); SP.RegisterSlashCommands()
  local handler = SlashCmdList.SPATIALPLATES
  expect(type(handler) == "function")
  local commands = { "", "help", "map off", "subzone on", "filter invalid", "theme missing", "bearing on", "import bad", "reset", "scope bad", "debug off", "unknown" }
  local originalPrint = print
  local printed = {}
  _G.print = function(...)
    local values = {}
    for i = 1, select("#", ...) do values[#values + 1] = tostring(select(i, ...)) end
    printed[#printed + 1] = table.concat(values, " ")
  end
  local ok, err = pcall(function()
    for _, command in ipairs(commands) do
      local commandOK = pcall(handler, command)
      expect(commandOK, "slash command threw: " .. command)
    end
    handler("theme |cffff0000Spoof")
    expect(SP.GetProfile().showSubzone)
    expect(table.concat(printed, " "):find("||cffff0000spoof", 1, true), "slash output did not escape markup")
  end)
  _G.print = originalPrint
  if not ok then error(err) end
end)

test("TICK1 ticker failure falls back to throttled OnUpdate", function()
  resetProfile(); tickerThrows = true
  SP.RestartTicker()
  expect(type(SP._mainFrame._scripts.OnUpdate) == "function")
  SP._mainFrame._scripts.OnUpdate(SP._mainFrame, 0.5)
  tickerThrows = false
end)

test("UI1 options panel and missing color-picker APIs fail gracefully", function()
  resetProfile()
  expect(pcall(SP.RegisterOptionsPanel))
  expect(SP.OpenOptions ~= nil)
  local colorButton
  for _, frame in ipairs(frames) do
    if frame._key == "fontColor" then colorButton = frame; break end
  end
  expect(colorButton and colorButton._scripts.OnClick)
  ColorPickerFrame = nil
  expect(pcall(colorButton._scripts.OnClick, colorButton))
end)

test("MODE1 friendly/party/friends-list checkboxes control friendly players", function()
  resetProfile()
  local p = SP.GetProfile()
  expect(SP.IsEligiblePlayer("friend", p))
  expect(not SP.IsEligiblePlayer("npc", p), "friendly NPCs never eligible")
  expect(not SP.IsEligiblePlayer("player", p), "self never eligible")
  p.showGlobal = false
  expect(SP.IsEligiblePlayer("friend", p), "party mode includes party member")
  p.showParty = false
  expect(not SP.IsEligiblePlayer("friend", p), "friend not on friends list")
  friendNames["Alice-Azeroth"] = true
  expect(SP.IsEligiblePlayer("friend", p), "friends-list mode")
  p.showFriendsList = false
  expect(not SP.IsEligiblePlayer("friend", p), "all modes off hides everyone")
  friendNames["Alice-Azeroth"] = nil
end)

test("MODE2 turning enemy players on creates overlays for already-visible hostile plates", function()
  resetProfile(); clearOverlays()
  SP.SetProfileValue("showEnemyPlayers", false)
  currentPlate = CreateFrame("Frame", "PlateMODE2", UIParent); currentPlate.unit = "enemy"
  fire("NAME_PLATE_UNIT_ADDED", "enemy")
  expect(SP._overlays.enemy == nil, "enemy skipped while enemy players off")
  SP.SetProfileValue("showEnemyPlayers", true)
  expect(SP._overlays.enemy and SP._overlays.enemy:IsShown(), "enemy overlay appears after enabling enemy players")
  clearOverlays()
end)

test("MODE3 enemy players and enemy NPCs have independent toggles", function()
  resetProfile()
  local p = SP.GetProfile()
  expect(SP.IsEligibleUnit("enemy", p), "enemy players on by default")
  expect(SP.IsEligibleUnit("mob", p), "hostile NPCs on by default")
  expect(SP.IsEligibleUnit("neutralmob", p), "attackable neutral NPCs count as enemies")
  expect(not SP.IsEligibleUnit("critter", p), "non-attackable NPCs never show")
  expect(not SP.IsEligibleUnit("npc", p), "friendly NPCs never show")
  p.showEnemyPlayers = false
  expect(not SP.IsEligibleUnit("enemy", p))
  expect(SP.IsEligibleUnit("mob", p), "NPC toggle independent of player toggle")
  p.showEnemyNPCs = false
  expect(not SP.IsEligibleUnit("mob", p))
  p.showEnemyPlayers = true
  p.showGlobal = false; p.showParty = false; p.showFriendsList = false
  expect(SP.IsEligibleUnit("enemy", p), "friendly modes do not affect enemy players")
  p.filter = "guild"
  expect(SP.PassesFilter("enemy", p), "group/guild filter narrows friendly players only")
end)

test("DIST3 players outside the group fall back to coarse interact-range buckets", function()
  resetProfile(); clearOverlays()
  setUnit("stranger", { isPlayer = true, friendly = false, enemy = true, visible = true, distanceSq = 0 })
  mapByUnit.stranger = nil -- GetBestMapForUnit only covers party members
  currentPlate = CreateFrame("Frame", "PlateDIST3", UIParent); currentPlate.unit = "stranger"
  interactRange.stranger = 8
  CheckInteractDistance = MockCheckInteractDistance
  fire("NAME_PLATE_UNIT_ADDED", "stranger")
  local overlay = SP._overlays.stranger
  expect(overlay and overlay:IsShown())
  expect(overlay._spText:GetText():find("<10y", 1, true), "near bucket: " .. tostring(overlay._spText:GetText()))
  interactRange.stranger = 20; SP.RefreshAllOverlays()
  expect(overlay._spText:GetText():find("<28y", 1, true))
  interactRange.stranger = 40; SP.RefreshAllOverlays()
  expect(overlay._spText:GetText():find(">28y", 1, true))
  clearOverlays(); interactRange.stranger = nil; CheckInteractDistance = nil
end)

test("MM1 minimap button opens mode popup on left or right click and toggles modes", function()
  resetProfile()
  local loaderEvent
  for _, f in ipairs(frames) do
    if f._events and f._events.PLAYER_LOGIN then loaderEvent = f._scripts.OnEvent end
  end
  expect(loaderEvent, "PLAYER_LOGIN loader registered")
  loaderEvent()
  local button = namedFrames.SpatialPlates_MinimapButton
  expect(button and button:IsShown(), "minimap button shown")
  button._scripts.OnMouseUp(button, "RightButton")
  local menu = namedFrames.SpatialPlates_ModeMenu
  expect(menu and menu:IsShown(), "right-click opens popup")
  button._scripts.OnMouseUp(button, "LeftButton")
  expect(not menu:IsShown(), "left-click closes popup")
  button._scripts.OnMouseUp(button, "LeftButton")
  expect(menu:IsShown(), "left-click opens popup")
  local globalCheck
  for _, c in ipairs(menu._spChecks) do if c._spKey == "showGlobal" then globalCheck = c end end
  expect(globalCheck:GetChecked() == true)
  globalCheck:SetChecked(false); globalCheck._scripts.OnClick(globalCheck)
  equal(SP.GetProfile().showGlobal, false)
  SlashCmdList.SPATIALPLATES("minimap off")
  expect(not button:IsShown(), "slash hides button")
  equal(SpatialPlatesDB.minimap.hide, true)
  SlashCmdList.SPATIALPLATES("minimap on")
  expect(button:IsShown())
end)

-- Spellbook / spell-range mocks for the finer range steps.
local function InstallSpellbook(spells)
  -- spells: list of { id, minRange, maxRange, helpful, harmful }
  local byId = {}
  for _, sp in ipairs(spells) do byId[sp.id] = sp end
  C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function(line)
      return { itemIndexOffset = 0, numSpellBookItems = #spells, isGuild = false }
    end,
    GetSpellBookItemInfo = function(slot)
      local sp = spells[slot]
      return sp and { itemType = 1, spellID = sp.id, isPassive = false, isOffSpec = false } or nil
    end,
  }
  C_Spell = {
    GetSpellInfo = function(id)
      local sp = byId[id]
      return sp and { minRange = sp.minRange, maxRange = sp.maxRange, spellID = id } or nil
    end,
    IsSpellHelpful = function(id) return byId[id] and byId[id].helpful or false end,
    IsSpellHarmful = function(id) return byId[id] and byId[id].harmful or false end,
    IsSpellInRange = function(id, unit)
      local sp, yards = byId[id], interactRange[unit]
      if not sp or yards == nil then return nil end
      return yards <= sp.maxRange
    end,
  }
end
local function RemoveSpellbook()
  C_SpellBook, C_Spell = nil, nil
  SP.RebuildRangeSteps()
end

test("RANGE1 known spells add finer range steps for friendly and hostile units", function()
  resetProfile()
  InstallSpellbook({
    { id = 1, minRange = 0, maxRange = 20, harmful = true },
    { id = 2, minRange = 0, maxRange = 30, harmful = true },
    { id = 3, minRange = 0, maxRange = 40, helpful = true },
    { id = 4, minRange = 8, maxRange = 35, harmful = true }, -- min range: ignored
  })
  CheckInteractDistance = MockCheckInteractDistance
  SP.RebuildRangeSteps()
  setUnit("hostile", { isPlayer = false, friendly = false, enemy = true, visible = true })
  setUnit("ally", { isPlayer = true, friendly = true, visible = true })
  interactRange.hostile = 15
  equal(SP.EstimateRange("hostile"), "<20")
  interactRange.hostile = 29
  equal(SP.EstimateRange("hostile"), "<30")
  interactRange.hostile = 33
  equal(SP.EstimateRange("hostile"), ">30", "35y min-range spell must not be used")
  interactRange.hostile = 5
  equal(SP.EstimateRange("hostile"), "<10", "search walks back down")
  interactRange.ally = 35
  equal(SP.EstimateRange("ally"), "<40", "helpful spells range friendly units")
  interactRange.ally = 50
  equal(SP.EstimateRange("ally"), ">40")
  interactRange.hostile, interactRange.ally = nil, nil
  CheckInteractDistance = nil
  RemoveSpellbook()
end)

test("RANGE2 erroring or nil range answers are skipped, never shown as out of range", function()
  resetProfile()
  InstallSpellbook({ { id = 1, minRange = 0, maxRange = 30, harmful = true } })
  SP.RebuildRangeSteps()
  setUnit("hostile", { isPlayer = false, friendly = false, enemy = true, visible = true })
  CheckInteractDistance = function() error("restricted") end
  interactRange.hostile = 12
  equal(SP.EstimateRange("hostile"), "<30", "spell step still answers")
  C_Spell.IsSpellInRange = function() return nil end
  equal(SP.EstimateRange("hostile"), nil, "no readable step: no estimate")
  interactRange.hostile = nil
  CheckInteractDistance = nil
  RemoveSpellbook()
end)

test("COMBAT2 estimated ranges hide in combat instead of freezing", function()
  resetProfile(); clearOverlays()
  local p = SP.GetProfile(); p.showSubzone = false
  setUnit("stranger", { isPlayer = true, friendly = false, enemy = true, visible = true, distanceSq = 0 })
  mapByUnit.stranger = nil
  CheckInteractDistance = MockCheckInteractDistance
  interactRange.stranger = 8
  currentPlate = CreateFrame("Frame", "PlateCOMBAT2", UIParent); currentPlate.unit = "stranger"
  fire("NAME_PLATE_UNIT_ADDED", "stranger")
  local overlay = SP._overlays.stranger
  expect(overlay:IsShown() and overlay._spText:GetText():find("<10y", 1, true))
  combatState = true
  CheckInteractDistance = function() return nil end
  SP.RefreshAllOverlays()
  expect(not overlay:IsShown(), "stale estimate must not stay on screen in combat")
  CheckInteractDistance = MockCheckInteractDistance
  SP.RefreshAllOverlays()
  expect(overlay:IsShown(), "estimate that still answers in combat is shown")
  combatState = false
  clearOverlays(); interactRange.stranger = nil; CheckInteractDistance = nil
end)

test("CACHE1 eligibility is cached until an event, profile change or TTL expiry", function()
  resetProfile(); clearOverlays()
  local clock = 100
  GetTime = function() return clock end
  local p = SP.GetProfile()
  setUnit("duelist", { isPlayer = true, friendly = true, visible = true, distanceSq = 16, map = 100 })
  p.showGlobal = false; p.showParty = false; p.showFriendsList = false
  currentPlate = CreateFrame("Frame", "PlateCACHE1", UIParent); currentPlate.unit = "duelist"
  expect(not SP.IsUnitWanted("duelist", p), "friendly with friendly modes off")
  units.duelist.friendly = false; units.duelist.enemy = true -- duel starts
  expect(not SP.IsUnitWanted("duelist", p), "cached until something invalidates it")
  fire("UNIT_FACTION", "duelist") -- no overlay yet: entry stays cached
  SP.InvalidateEligibility("duelist")
  expect(SP.IsUnitWanted("duelist", p), "re-evaluated after invalidation")
  units.duelist.friendly = true; units.duelist.enemy = false
  expect(SP.IsUnitWanted("duelist", p), "cached again")
  clock = clock + 3
  expect(not SP.IsUnitWanted("duelist", p), "TTL expiry re-evaluates")
  p.showGlobal = true
  expect(SP.IsUnitWanted("duelist", p), "profile change bypasses the cache")
  fire("NAME_PLATE_UNIT_ADDED", "duelist")
  local overlay = SP._overlays.duelist
  expect(overlay and overlay:IsShown())
  p.showGlobal = false; SP.RefreshAllOverlays()
  expect(not overlay:IsShown(), "direct profile edits take effect immediately")
  GetTime = nil
  clearOverlays()
end)

test("FEET1 feet mode sets the nameplate CVar, re-anchors, and restores on off", function()
  resetProfile(); clearOverlays()
  local cvars = { nameplateOtherAtBase = "0" }
  C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = value; return true end,
  }
  SP.SetProfileValue("markerAtFeet", true); SP.ApplyMarkerPosition()
  equal(cvars.nameplateOtherAtBase, "1")
  equal(SpatialPlatesDB.savedOtherAtBase, "0")
  expect(SP._feetActive)
  currentPlate = CreateFrame("Frame", "PlateFEET1", UIParent); currentPlate.unit = "friend"
  fire("NAME_PLATE_UNIT_ADDED", "friend")
  local overlay = SP._overlays.friend
  expect(overlay and overlay._lastPoint, "overlay anchored")
  equal(overlay._lastPoint[1], "TOP"); equal(overlay._lastPoint[3], "BOTTOM")
  SP.SetProfileValue("markerAtFeet", false); SP.ApplyMarkerPosition()
  equal(cvars.nameplateOtherAtBase, "0", "previous value restored")
  equal(SpatialPlatesDB.savedOtherAtBase, nil)
  expect(not SP._feetActive)
  -- Combat defers the CVar change until combat ends.
  combatState = true
  SP.SetProfileValue("markerAtFeet", true); SP.ApplyMarkerPosition()
  equal(cvars.nameplateOtherAtBase, "0", "no CVar write in combat")
  combatState = false
  fire("PLAYER_REGEN_ENABLED")
  equal(cvars.nameplateOtherAtBase, "1", "applied after combat")
  -- A client without the CVar: no error, marker stays at the nameplate.
  cvars.nameplateOtherAtBase = nil
  expect(pcall(SP.ApplyMarkerPosition))
  expect(not SP._feetActive)
  C_CVar = nil
  clearOverlays()
end)

test("COLOR1 reaction colors are the default and untouched old profiles migrate once", function()
  SpatialPlatesDB = nil
  equal(SP.GetProfile().colorMode, "reaction")
  SpatialPlatesDB = {
    profile = { colorMode = "custom", fontColor = { r = 1, g = 1, b = 1, a = 1 } },
    charProfiles = { ["A-B"] = { colorMode = "custom", fontColor = { r = 1, g = 0, b = 0, a = 1 } } },
  }
  SP.EnsureDB()
  equal(SpatialPlatesDB.profile.colorMode, "reaction", "default white custom migrates")
  equal(SpatialPlatesDB.charProfiles["A-B"].colorMode, "custom", "customized color kept")
  SpatialPlatesDB.profile.colorMode = "custom"
  SP.EnsureDB()
  equal(SpatialPlatesDB.profile.colorMode, "custom", "migration runs only once")
  resetProfile()
end)

if failed > 0 then
  print(string.format("\nRESULT: %d passed, %d failed", passed, failed))
  for _, failure in ipairs(failures) do print(" - " .. failure) end
  os.exit(1)
end
print(string.format("\nRESULT: %d passed, %d failed", passed, failed))
