-- SpatialPlates Minimap.lua
-- Minimap button and a small settings window: which nameplates get a
-- marker, text size/color/outline, background, and position. Left- or
-- right-click the button to toggle the window; drag the button to move it.
-- No libraries: plain frames. Uses OnMouseUp rather than click registration
-- so both mouse buttons work without touching secure click handling.

SpatialPlates = SpatialPlates or {}
local SP = SpatialPlates

-- The addon's own icon (Media/Icon.tga, drawn by scripts/make_icon.py).
local ICON = "Interface\\AddOns\\SpatialPlates\\Media\\Icon"
local RADIUS = 80
local WINDOW_NAME = "SpatialPlates_SettingsWindow"

local button, window

-- ---------------------------------------------------------------------------
-- Small widget helpers (each returns a control with a _spRefresh function)
-- ---------------------------------------------------------------------------

local function Label(parent, text, x, y, template)
  local f = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  f:SetText(text)
  return f
end

local function GetPath(profile, key)
  local value = profile
  for part in tostring(key):gmatch("[^.]+") do
    if type(value) ~= "table" then return nil end
    value = value[part]
  end
  return value
end

local function Check(parent, text, x, y, key)
  local c = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  c:SetWidth(22); c:SetHeight(22)
  local label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("LEFT", c, "RIGHT", 1, 0)
  label:SetText(text)
  c._spKey = key
  c:SetScript("OnClick", function(self)
    local ok, checked = pcall(self.GetChecked, self)
    SP.SetProfileValue(key, ok and checked == true)
  end)
  c._spRefresh = function()
    pcall(c.SetChecked, c, SP.GetProfile()[key] == true)
  end
  return c
end

-- A row of mutually exclusive choices. `choices` = { {label, apply, isOn} }.
local function Radio(parent, x, y, choices)
  local buttons = {}
  local col = x
  for _, choice in ipairs(choices) do
    local c = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", col, y)
    c:SetWidth(22); c:SetHeight(22)
    local label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", c, "RIGHT", 1, 0)
    label:SetText(choice[1])
    c._spChoice = choice
    c:SetScript("OnClick", function(self)
      self._spChoice[2]()
      for _, other in ipairs(buttons) do other._spRefresh() end
    end)
    c._spRefresh = function()
      pcall(c.SetChecked, c, c._spChoice[3](SP.GetProfile()) == true)
    end
    buttons[#buttons + 1] = c
    col = col + (choice.width or 80)
  end
  return buttons
end

local function Slider(parent, text, x, y, minV, maxV, step, key, fmt)
  local label = Label(parent, text, x, y)
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y - 14)
  s:SetWidth(170); s:SetHeight(16)
  pcall(s.SetMinMaxValues, s, minV, maxV)
  pcall(s.SetValueStep, s, step)
  if s.SetObeyStepOnDrag then pcall(s.SetObeyStepOnDrag, s, true) end
  -- Hide the template's own Low/High/Text labels when present; our label and
  -- value text replace them.
  for _, region in ipairs({ s.Low, s.High, s.Text }) do
    if region and region.Hide then pcall(region.Hide, region) end
  end
  local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  value:SetPoint("LEFT", s, "RIGHT", 8, 0)
  local function Show(v)
    value:SetText(fmt and fmt(v) or tostring(v))
  end
  s._spKey = key
  s:SetScript("OnValueChanged", function(self, v)
    if self._spUpdating then return end
    if type(v) ~= "number" then return end
    v = math.floor(v / step + 0.5) * step
    -- Avoid float noise such as 0.30000000000000004 in saved values.
    v = tonumber(string.format("%.2f", v))
    SP.SetProfileValue(key, v)
    Show(v)
  end)
  s._spRefresh = function()
    local v = GetPath(SP.GetProfile(), key)
    if type(v) ~= "number" then return end
    s._spUpdating = true
    pcall(s.SetValue, s, v)
    s._spUpdating = false
    Show(v)
  end
  s._spLabel = label
  return s
end

local function ColorSwatch(parent, text, x, y, key)
  local b = CreateFrame("Button", nil, parent)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetWidth(18); b:SetHeight(18)
  local border = b:CreateTexture(nil, "BACKGROUND")
  border:SetAllPoints(b)
  border:SetColorTexture(0.8, 0.8, 0.8, 1)
  local swatch = b:CreateTexture(nil, "ARTWORK")
  swatch:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
  swatch:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  swatch:SetColorTexture(1, 1, 1, 1)
  local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("LEFT", b, "RIGHT", 6, 0)
  label:SetText(text)
  b._spKey = key
  b._spSwatch = swatch
  b._spRefresh = function()
    local c = GetPath(SP.GetProfile(), key)
    if type(c) == "table" then
      pcall(swatch.SetColorTexture, swatch, c.r or 1, c.g or 1, c.b or 1, 1)
    end
  end
  b:SetScript("OnClick", function()
    if SP.OpenColorPicker then SP.OpenColorPicker(key, b._spRefresh) end
  end)
  return b
end

local function PushButton(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetWidth(width); b:SetHeight(22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

-- ---------------------------------------------------------------------------
-- Settings window
-- ---------------------------------------------------------------------------

local function SetAnchorPreset(above)
  if above then
    SP.SetProfileValue("anchor", "TOP")
    SP.SetProfileValue("anchorTo", "BOTTOM")
  else
    SP.SetProfileValue("anchor", "BOTTOM")
    SP.SetProfileValue("anchorTo", "TOP")
  end
end

local function IsBelow(p) return p.anchor == "BOTTOM" and p.anchorTo == "TOP" end

local function RefreshWindow()
  if not window then return end
  for _, control in ipairs(window._spControls) do
    pcall(control._spRefresh)
  end
end
SP.RefreshSettingsWindow = RefreshWindow

local function BuildWindow()
  local f = CreateFrame("Frame", WINDOW_NAME, UIParent)
  f:SetWidth(300); f:SetHeight(530)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) pcall(self.StartMoving, self) end)
  f:SetScript("OnDragStop", function(self) pcall(self.StopMovingOrSizing, self) end)
  f:Hide()

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(f)
  bg:SetColorTexture(0.05, 0.05, 0.07, 0.92)
  local edge = f:CreateTexture(nil, "BORDER")
  edge:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  edge:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  edge:SetHeight(24)
  edge:SetColorTexture(0.15, 0.35, 0.55, 0.9)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -6)
  title:SetText("Spatial Plates")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 3)
  close:SetScript("OnClick", function() f:Hide() end)

  local controls = {}
  local function Add(control) controls[#controls + 1] = control; return control end

  -- Show on
  local y = -32
  Label(f, "Show markers on", 10, y, "GameFontNormal")
  y = y - 18
  Add(Check(f, "Friendly players", 12, y, "showGlobal"))
  Add(Check(f, "Enemy players", 150, y, "showEnemyPlayers"))
  y = y - 22
  Add(Check(f, "Party / raid", 12, y, "showParty"))
  Add(Check(f, "Enemy NPCs", 150, y, "showEnemyNPCs"))
  y = y - 22
  Add(Check(f, "Friends list", 12, y, "showFriendsList"))

  -- Text
  y = y - 30
  Label(f, "Text", 10, y, "GameFontNormal")
  y = y - 18
  Add(Check(f, "Distance", 12, y, "showDistance"))
  Add(Check(f, "Map name", 150, y, "showSubzone"))
  y = y - 26
  Add(Slider(f, "Size", 12, y, 6, 32, 1, "fontSize", function(v) return v .. " pt" end))
  y = y - 38
  Label(f, "Color", 12, y)
  y = y - 14
  for _, b in ipairs(Radio(f, 12, y, {
    { "Name", function() SP.SetProfileValue("colorMode", "name") end,
      function(p) return p.colorMode == "name" end, width = 64 },
    { "Reaction", function() SP.SetProfileValue("colorMode", "reaction") end,
      function(p) return p.colorMode == "reaction" end, width = 82 },
    { "Class", function() SP.SetProfileValue("colorMode", "class") end,
      function(p) return p.colorMode == "class" end, width = 64 },
    { "Custom", function() SP.SetProfileValue("colorMode", "custom") end,
      function(p) return p.colorMode == "custom" end },
  })) do Add(b) end
  y = y - 24
  Add(ColorSwatch(f, "Custom color", 14, y, "fontColor"))
  y = y - 26
  Label(f, "Outline", 12, y)
  for _, b in ipairs(Radio(f, 50, y + 5, {
    { "None", function() SP.SetProfileValue("fontOutline", "none") end,
      function(p) return p.fontOutline == "none" end, width = 62 },
    { "Thin", function() SP.SetProfileValue("fontOutline", "outline") end,
      function(p) return p.fontOutline == "outline" end, width = 62 },
    { "Thick", function() SP.SetProfileValue("fontOutline", "thick") end,
      function(p) return p.fontOutline == "thick" end },
  })) do Add(b) end
  y = y - 24
  Add(Check(f, "Background", 12, y, "bgEnabled"))
  Add(ColorSwatch(f, "Background color", 150, y - 2, "bgColor"))

  -- Position
  y = y - 32
  Label(f, "Position", 10, y, "GameFontNormal")
  y = y - 18
  for _, b in ipairs(Radio(f, 12, y, {
    { "Above nameplate", function() SetAnchorPreset(true) end,
      function(p) return not IsBelow(p) end, width = 138 },
    { "Below nameplate", function() SetAnchorPreset(false) end, IsBelow },
  })) do Add(b) end
  y = y - 28
  Add(Slider(f, "Offset X", 12, y, -100, 100, 1, "offsetX"))
  y = y - 36
  Add(Slider(f, "Offset Y", 12, y, -100, 100, 1, "offsetY"))
  y = y - 36
  Add(Slider(f, "Scale", 12, y, 0.5, 2.0, 0.05, "scale",
    function(v) return string.format("%.2f", v) end))

  -- Footer
  local reset = PushButton(f, "Reset", 80, function()
    if SP.ResetProfile then SP.ResetProfile() end
    RefreshWindow()
  end)
  reset:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
  local more = PushButton(f, "All options...", 110, function()
    f:Hide()
    if SP.OpenOptions then SP.OpenOptions() end
  end)
  more:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
  f._spReset, f._spMore = reset, more

  f._spControls = controls
  f:SetScript("OnShow", RefreshWindow)

  -- Escape closes the window.
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, WINDOW_NAME)
  end
  return f
end

function SP.ToggleSettingsWindow()
  if not window then
    local ok, built = pcall(BuildWindow)
    if not ok then
      SP.DebugPrint("settings window creation failed")
      return
    end
    window = built
  end
  if window:IsShown() then
    window:Hide()
  else
    window:Show()
    RefreshWindow()
  end
end

-- ---------------------------------------------------------------------------
-- Minimap button
-- ---------------------------------------------------------------------------

local function PositionButton()
  if not button then return end
  local db = SP.EnsureDB()
  local rad = math.rad(db.minimap.angle or 225)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * RADIUS, math.sin(rad) * RADIUS)
end

local function DragUpdate()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  if not (mx and cx and scale and scale > 0) then return end
  local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
  SP.EnsureDB().minimap.angle = angle
  PositionButton()
end

local function CreateButton()
  local b = CreateFrame("Button", "SpatialPlates_MinimapButton", Minimap)
  b:SetWidth(31); b:SetHeight(31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:SetMovable(true)
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetWidth(20); bg:SetHeight(20)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)

  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetWidth(20); icon:SetHeight(20)
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetWidth(53); border:SetHeight(53)
  border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

  b:SetScript("OnMouseUp", function(self, mouseButton)
    if self._spDragging then return end
    if mouseButton == "LeftButton" or mouseButton == "RightButton" then
      if GameTooltip then GameTooltip:Hide() end
      SP.ToggleSettingsWindow()
    end
  end)
  b:SetScript("OnDragStart", function(self)
    self._spDragging = true
    self:SetScript("OnUpdate", DragUpdate)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    -- OnMouseUp fires after OnDragStop; clear the flag on the next frame so
    -- finishing a drag does not also open the window.
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function() self._spDragging = false end)
    else
      self._spDragging = false
    end
  end)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Spatial Plates")
    GameTooltip:AddLine("Click: settings", 1, 1, 1)
    GameTooltip:AddLine("Drag: move button", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
  return b
end

function SP.UpdateMinimapButton()
  if type(Minimap) ~= "table" and type(Minimap) ~= "userdata" then return end
  local db = SP.EnsureDB()
  if db.minimap.hide then
    if button then button:Hide() end
    return
  end
  if not button then
    local ok, b = pcall(CreateButton)
    if not ok then
      SP.DebugPrint("minimap button creation failed")
      return
    end
    button = b
  end
  PositionButton()
  button:Show()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  local ok = pcall(SP.UpdateMinimapButton)
  if not ok then SP.DebugPrint("minimap button setup failed") end
end)
