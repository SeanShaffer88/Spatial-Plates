-- SpatialPlates Minimap.lua
-- Minimap button with a small popup for the player-mode checkboxes
-- (Global / Party / Friends list). Left- or right-click opens the popup,
-- drag moves the button around the minimap edge. No libraries: one plain
-- Button parented to Minimap. Uses OnMouseUp rather than click registration
-- so both mouse buttons work without touching secure click handling.

SpatialPlates = SpatialPlates or {}
local SP = SpatialPlates

local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
local RADIUS = 80

local MODES = {
  { key = "showGlobal", label = "Global (all players)" },
  { key = "showParty", label = "Party / raid members" },
  { key = "showFriendsList", label = "Friends-list friends" },
}

local button, menu

-- ---------------------------------------------------------------------------
-- Popup menu
-- ---------------------------------------------------------------------------

local function RefreshMenuChecks()
  if not menu then return end
  local profile = SP.GetProfile()
  for _, check in ipairs(menu._spChecks) do
    pcall(check.SetChecked, check, profile[check._spKey] == true)
  end
end

local function CreateMenu()
  local f = CreateFrame("Frame", "SpatialPlates_ModeMenu", UIParent)
  f:SetWidth(190)
  f:SetHeight(28 + #MODES * 24)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:Hide()

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(f)
  bg:SetColorTexture(0, 0, 0, 0.85)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
  title:SetText("Spatial Plates: show on")

  f._spChecks = {}
  for i, mode in ipairs(MODES) do
    local c = CreateFrame("CheckButton", nil, f, "InterfaceOptionsCheckButtonTemplate")
    c:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -2 - i * 24)
    c:SetWidth(24); c:SetHeight(24)
    local label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    label:SetText(mode.label)
    c._spKey = mode.key
    c:SetScript("OnClick", function(self)
      local ok, checked = pcall(self.GetChecked, self)
      SP.SetProfileValue(self._spKey, ok and checked == true)
      RefreshMenuChecks()
    end)
    f._spChecks[#f._spChecks + 1] = c
  end

  -- Escape closes the popup.
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "SpatialPlates_ModeMenu")
  end
  return f
end

local function ToggleMenu()
  if not menu then menu = CreateMenu() end
  if menu:IsShown() then
    menu:Hide()
    return
  end
  RefreshMenuChecks()
  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", button, "BOTTOMLEFT", 0, 0)
  menu:Show()
end
SP.ToggleModeMenu = ToggleMenu

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
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetWidth(53); border:SetHeight(53)
  border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

  b:SetScript("OnMouseUp", function(self, mouseButton)
    if self._spDragging then return end
    if mouseButton == "LeftButton" or mouseButton == "RightButton" then
      if GameTooltip then GameTooltip:Hide() end
      ToggleMenu()
    end
  end)
  b:SetScript("OnDragStart", function(self)
    self._spDragging = true
    self:SetScript("OnUpdate", DragUpdate)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    -- OnMouseUp fires after OnDragStop; clear the flag on the next frame so
    -- finishing a drag does not also open the popup.
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
    GameTooltip:AddLine("Left/Right-click: choose which players get overlays", 1, 1, 1)
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
    if menu then menu:Hide() end
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
