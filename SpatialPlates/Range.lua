-- SpatialPlates Range.lua
-- Estimated range for units the client cannot measure exactly (anyone
-- outside the player's group, including all enemies).
--
-- The player's own spellbook is scanned for active spells with a maximum
-- range (and no minimum range). Helpful spells test friendly units, harmful
-- spells test attackable units, and CheckInteractDistance adds 10y / 28y
-- steps for any unit. C_Spell.IsSpellInRange is documented as usable from
-- tainted code; every call is pcall-guarded and a nil, secret or erroring
-- answer simply skips that step.

SpatialPlates = SpatialPlates or {}
local SP = SpatialPlates

-- Interaction distance indexes: 3 = duel (~10y), 4 = follow (~28y).
local INTERACT_STEPS = {
  { yards = 10, interact = 3 },
  { yards = 28, interact = 4 },
}

SP._rangeSteps = { friendly = INTERACT_STEPS, hostile = INTERACT_STEPS, neutral = INTERACT_STEPS }
SP._rangeIndex = {} -- [unit] = index of the last matching step (search start)

local function Readable(value, expectedType)
  if SP.IsReadable then return SP.IsReadable(value, expectedType) end
  return value ~= nil and (expectedType == nil or type(value) == expectedType)
end

local function Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, result = pcall(fn, ...)
  if not ok then return nil end
  return result
end

-- Merge spell steps with the interaction steps: one step per distinct
-- yard value, ascending, preferring a spell when both exist.
local function BuildSteps(spellByYards)
  local byYards = {}
  for _, step in ipairs(INTERACT_STEPS) do byYards[step.yards] = step end
  for yards, spellID in pairs(spellByYards) do
    byYards[yards] = { yards = yards, spellID = spellID }
  end
  local steps = {}
  for _, step in pairs(byYards) do steps[#steps + 1] = step end
  table.sort(steps, function(a, b) return a.yards < b.yards end)
  return steps
end

-- Rebuild the step lists from the spellbook. Called on login and when the
-- player's spells change; never per refresh.
function SP.RebuildRangeSteps()
  local helpful, harmful = {}, {}
  local book, spell = C_SpellBook, C_Spell
  if type(book) == "table" and type(spell) == "table"
    and type(book.GetNumSpellBookSkillLines) == "function"
    and type(book.GetSpellBookSkillLineInfo) == "function"
    and type(book.GetSpellBookItemInfo) == "function"
    and type(spell.GetSpellInfo) == "function" then
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local spellType = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
    local numLines = Call(book.GetNumSpellBookSkillLines)
    if Readable(numLines, "number") then
      for line = 1, numLines do
        local lineInfo = Call(book.GetSpellBookSkillLineInfo, line)
        if Readable(lineInfo, "table") and lineInfo.isGuild ~= true
          and Readable(lineInfo.itemIndexOffset, "number")
          and Readable(lineInfo.numSpellBookItems, "number") then
          local first = lineInfo.itemIndexOffset + 1
          for slot = first, lineInfo.itemIndexOffset + lineInfo.numSpellBookItems do
            local item = Call(book.GetSpellBookItemInfo, slot, bank)
            if Readable(item, "table") and item.itemType == spellType
              and item.isPassive ~= true and item.isOffSpec ~= true
              and Readable(item.spellID, "number") then
              local info = Call(spell.GetSpellInfo, item.spellID)
              if Readable(info, "table") and Readable(info.maxRange, "number")
                and Readable(info.minRange, "number")
                and info.minRange == 0 and info.maxRange > 0 then
                local yards = math.floor(info.maxRange + 0.5)
                if Call(spell.IsSpellHelpful, item.spellID) == true and not helpful[yards] then
                  helpful[yards] = item.spellID
                end
                if Call(spell.IsSpellHarmful, item.spellID) == true and not harmful[yards] then
                  harmful[yards] = item.spellID
                end
              end
            end
          end
        end
      end
    end
  end
  SP._rangeSteps = {
    friendly = BuildSteps(helpful),
    hostile = BuildSteps(harmful),
    neutral = INTERACT_STEPS,
  }
  SP._rangeIndex = {}
end

-- true / false when the step gives a readable answer, nil otherwise.
local function TestStep(step, unit)
  local result
  if step.spellID then
    result = Call(C_Spell and C_Spell.IsSpellInRange, step.spellID, unit)
  else
    result = Call(CheckInteractDistance, unit, step.interact)
  end
  if not Readable(result) then return nil end
  if result == true or result == 1 then return true end
  if result == false or result == 0 then return false end
  return nil
end

local function StepsForUnit(unit)
  if type(UnitIsFriend) == "function" and Call(UnitIsFriend, "player", unit) == true then
    return SP._rangeSteps.friendly
  end
  if type(UnitCanAttack) == "function" and Call(UnitCanAttack, "player", unit) == true then
    return SP._rangeSteps.hostile
  end
  return SP._rangeSteps.neutral
end

-- Returns (label, upperYards) such as ("<20", 20), or (">40", nil) when
-- every readable step says out of range, or nil when no step could answer.
-- Searches outward from the step that matched last time, so a unit that has
-- not moved much costs about two checks per refresh.
function SP.EstimateRange(unit)
  if not Readable(unit, "string") then return nil end
  local steps = StepsForUnit(unit)
  if type(steps) ~= "table" or #steps == 0 then return nil end
  local n = #steps
  local answers = {}
  local function Ask(i)
    if answers[i] == nil then
      local value = TestStep(steps[i], unit)
      answers[i] = (value == nil) and "none" or value
    end
    return answers[i]
  end

  local start = SP._rangeIndex[unit]
  if type(start) ~= "number" or start < 1 or start > n then start = 1 end

  -- Find the smallest in-range step. Walk down while in range, else walk up.
  local found
  if Ask(start) == true then
    found = start
    for i = start - 1, 1, -1 do
      local a = Ask(i)
      if a == true then found = i elseif a == false then break end
    end
  else
    for i = start + 1, n do
      if Ask(i) == true then found = i; break end
    end
    if not found and Ask(start) == "none" then
      for i = start - 1, 1, -1 do
        local a = Ask(i)
        if a == true then found = i elseif a == false then break end
      end
    end
  end

  if found then
    SP._rangeIndex[unit] = found
    return "<" .. tostring(steps[found].yards), steps[found].yards
  end
  -- Nothing in range: report beyond the largest step that answered false.
  for i = n, 1, -1 do
    if answers[i] == nil then Ask(i) end
    if answers[i] == false then
      SP._rangeIndex[unit] = n
      return ">" .. tostring(steps[i].yards), nil
    end
  end
  return nil
end

function SP.ForgetRange(unit)
  if unit then SP._rangeIndex[unit] = nil else SP._rangeIndex = {} end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
pcall(loader.RegisterEvent, loader, "SPELLS_CHANGED")
loader:SetScript("OnEvent", function()
  local ok = pcall(SP.RebuildRangeSteps)
  if not ok and SP.DebugPrint then SP.DebugPrint("range step rebuild failed") end
end)
