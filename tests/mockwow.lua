-- Minimal WoW 1.12 API mock for offline testing (Lua 5.0)
MOCK = { gear = {}, locale = "enUS", casts = {}, events = {}, frames = {} }

function GetLocale() return MOCK.locale end
function getglobal(n) return _G[n] end
function setglobal(n, v) _G[n] = v end
DEFAULT_CHAT_FRAME = { AddMessage = function(self, m) if MOCK.echo then print("[chat] " .. m) end end }
GREEN_FONT_COLOR_CODE, HIGHLIGHT_FONT_COLOR_CODE, LIGHTYELLOW_FONT_COLOR_CODE = "", "", ""
BOOKTYPE_SPELL = "spell"
SlashCmdList = {}
UIParent = {}

local SLOTIDS = { HeadSlot=1, NeckSlot=2, ShoulderSlot=3, ShirtSlot=4, ChestSlot=5, WaistSlot=6, LegsSlot=7,
  FeetSlot=8, WristSlot=9, HandsSlot=10, Finger0Slot=11, Finger1Slot=12, Trinket0Slot=13, Trinket1Slot=14,
  BackSlot=15, MainHandSlot=16, SecondaryHandSlot=17, RangedSlot=18, TabardSlot=19 }
function GetInventorySlotInfo(name) return SLOTIDS[name], "" end
MOCK.tooltipCalls = 0

local function newFrame(name)
  local f = { events = {}, scripts = {}, shown = true, name = name }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:SetScript(s, fn) self.scripts[s] = fn end
  function f:GetScript(s) return self.scripts[s] end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:IsShown() return self.shown end
  function f:IsVisible() return self.shown end
  -- UI no-ops
  local noop = function() end
  for _, m in ipairs({"SetWidth","SetHeight","SetPoint","SetBackdrop","SetMovable","EnableMouse","RegisterForDrag",
      "StartMoving","StopMovingOrSizing","SetText","SetChecked","SetFrameStrata","ClearAllPoints","SetJustifyH",
      "SetBackdropColor","SetClampedToScreen","SetAlpha"}) do f[m] = noop end
  f.GetChecked = function(self) return self.checked end
  f.CreateFontString = function() return newFrame() end
  if name then _G[name] = f end
  table.insert(MOCK.frames, f)
  return f
end
MOCK.newFrame = newFrame

function CreateFrame(kind, name, parent, template)
  local f = newFrame(name)
  f.kind = kind
  if kind == "GameTooltip" then
    f.lines = {}
    for i = 1, 30 do
      local idx = i
      local fs = { GetText = function() return f.lines[idx] end }
      if name then _G[name .. "TextLeft" .. i] = fs; _G[name .. "TextRight" .. i] = { GetText = function() return nil end } end
    end
    function f:SetOwner() end
    function f:ClearLines() self.lines = {} end
    function f:NumLines() return table.getn(self.lines) end
    function f:SetInventoryItem(unit, slot)
      MOCK.tooltipCalls = MOCK.tooltipCalls + 1
      local item = MOCK.gear[slot]
      if not item then self.lines = {}; return nil end
      self.lines = item
      return 1
    end
  end
  return f
end

-- emulate the XML-created objects BonusScanner expects
function MOCK.makeBonusScannerFrames()
  CreateFrame("GameTooltip", "BonusScannerTooltip")
  local f = newFrame("BonusScannerFrame")
  this = f
  BonusScanner:OnLoad()
  f.scripts.OnEvent = function() BonusScanner:OnEvent() end
  f.scripts.OnUpdate = function() BonusScanner:OnUpdate(arg1) end
  return f
end

function MOCK.fire(ev, a1)
  for _, f in ipairs(MOCK.frames) do
    if f.events[ev] and f.scripts.OnEvent then
      this, event, arg1 = f, ev, a1
      f.scripts.OnEvent()
    end
  end
end

function MOCK.tick(elapsed)
  for _, f in ipairs(MOCK.frames) do
    if f.shown and f.scripts.OnUpdate then
      this, arg1 = f, elapsed
      f.scripts.OnUpdate()
    end
  end
end

-- player state
MOCK.hp, MOCK.hpmax, MOCK.mana, MOCK.manamax = 3500, 3500, 1000, 5000
function UnitHealth() return MOCK.hp end
function UnitHealthMax() return MOCK.hpmax end
function UnitMana() return MOCK.mana end
function UnitManaMax() return MOCK.manamax end
function UnitClass() return "Warlock", "WARLOCK" end
function UnitBuff() return nil end
function CastSpellByName(s) table.insert(MOCK.casts, s) end
function CastSpell(id, book) table.insert(MOCK.casts, "id:" .. id) end

MOCK.spellbook = { {"Shadow Bolt","Rank 9"} }
function GetSpellName(i, book)
  local s = MOCK.spellbook[i]
  if s then return s[1], s[2] end
  return nil
end
MOCK.talents = { [1] = { {"Suppression"},{"Improved Corruption"},{"Improved Curse of Weakness"},{"Improved Drain Soul"},{"Improved Life Tap", 2} } }
function GetNumTalentTabs() return 3 end
function GetNumTalents(tab) return table.getn(MOCK.talents[tab] or {}) end
function GetTalentInfo(tab, i)
  local t = MOCK.talents[tab] and MOCK.talents[tab][i]
  if t then return t[1], "", 1, 1, t[2] or 0, 2 end
end
function IsAddOnLoaded(n) return MOCK.loaded and MOCK.loaded[n] end

-- realistic level-60 warlock gear (T2-ish / AQ40 / Naxx flavoured), tooltip lines incl. name line
MOCK.SAMPLE_GEAR = {
  [1] = {"Nemesis Skullcap","Binds when picked up","Head","Cloth","124 Armor","+26 Stamina","+16 Intellect","+10 Shadow Resistance","Durability 60 / 60","Classes: Warlock","Requires Level 60","Equip: Improves your chance to get a critical strike with spells by 1%.","Equip: Increases damage and healing done by magical spells and effects by up to 32.","+8 Spell Damage and Healing","Nemesis Raiment (3/8)","  Nemesis Skullcap","  Nemesis Robes","  Nemesis Leggings","(3) Set: Reduces the threat generated by your Destruction spells by 20%.","(5) Set: Reduces the cooldown of your Shadow Ward by 4 sec.","(8) Set: Your Shadow Bolt has a chance to..."},
  [2] = {"Choker of the Fire Lord","Binds when picked up","Neck","+7 Stamina","+7 Intellect","Requires Level 60","Equip: Increases damage and healing done by magical spells and effects by up to 34.","Equip: Decreases the magical resistances of your spell targets by 10."},
  [3] = {"Nemesis Spaulders","Binds when picked up","Shoulder","Cloth","+20 Stamina","+13 Intellect","Equip: Increases damage and healing done by magical spells and effects by up to 23.","Zandalar Signet of Mojo","Nemesis Raiment (3/8)"},
  [5] = {"Nemesis Robes","Binds when picked up","Chest","Cloth","+26 Stamina","+16 Intellect","+10 Fire Resistance","Equip: Increases damage and healing done by magical spells and effects by up to 32.","+4 All Stats","Nemesis Raiment (3/8)","(3) Set: Reduces the threat generated by your Destruction spells by 20%."},
  [6] = {"Belt of the Fallen Emperor","Binds when picked up","Waist","Cloth","+17 Stamina","+18 Intellect","Equip: Improves your chance to hit with spells by 1%.","Equip: Increases damage and healing done by magical spells and effects by up to 22."},
  [7] = {"Nemesis Leggings","Binds when picked up","Legs","Cloth","+23 Stamina","+16 Intellect","Equip: Increases damage and healing done by magical spells and effects by up to 39.","Equip: Improves your chance to get a critical strike with spells by 1%.","Nemesis Raiment (3/8)"},
  [8] = {"Boots of Epiphany","Binds when picked up","Feet","Cloth","+15 Stamina","+19 Intellect","Equip: Increases damage and healing done by magical spells and effects by up to 34.","Run Speed Increased"},
  [9] = {"Rejuvenating Bracers","Binds when picked up","Wrist","Cloth","+10 Intellect","Equip: Increases damage done by Shadow spells and effects by up to 21.","+9 Stamina"},
  [10] = {"Gloves of Ebru","Binds when picked up","Hands","Cloth","+20 Stamina","+13 Intellect","Equip: Increases damage and healing done by magical spells and effects by up to 28.","+2% Threat"},
  [11] = {"Ring of the Fallen God","Binds when picked up","Finger","+5 Stamina","+6 Intellect","Equip: Increases damage and healing done by magical spells and effects by up to 37.","Equip: Improves your chance to hit with spells by 1%."},
  [12] = {"Band of Forced Concentration","Binds when picked up","Finger","+12 Stamina","+9 Intellect","Equip: Improves your chance to hit with spells by 1%.","Equip: Increases damage and healing done by magical spells and effects by up to 21."},
  [13] = {"Talisman of Ephemeral Power","Binds when picked up","Trinket","Use: Increases damage and healing done by magical spells and effects by up to 175 for 15 sec."},
  [14] = {"Briarwood Reed","Binds when picked up","Trinket","Equip: Increases damage and healing done by magical spells and effects by up to 29."},
  [15] = {"Cloak of the Necropolis","Binds when picked up","Back","+11 Stamina","+12 Intellect","Equip: Improves your chance to hit with spells by 1%.","Equip: Increases damage and healing done by magical spells and effects by up to 26.","+3 Agility"},
  [16] = {"Spinal Reaper","Binds when picked up","Two-Hand","Staff","163 - 246 Damage","Speed 3.20","(63.9 damage per second)","+16 Stamina","+21 Intellect","Equip: Increases damage done by Shadow spells and effects by up to 54.","+30 Spell Damage","Brilliant Wizard Oil (30 min)"},
  [18] = {"Wand of Biting Cold","Binds when picked up","Ranged","Wand","Frost Damage","Equip: Increases damage and healing done by magical spells and effects by up to 12."},
}
-- expected SHADOWDMG + DMG (gear-only, no Use: or temporary oils since BonusScanner counts oils): computed in tests
