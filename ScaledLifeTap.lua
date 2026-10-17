-- ScaledLifeTap 4.0
-- Original by Kimilly (thanks to Aredia of Gilneas for the macro and research).
-- Casts the highest Life Tap rank whose mana return fits in your missing mana.
--
-- Macro:  /slt cast        (or the old  /script ScaledLifeTap_CastLifeTap()  )

local L = SCALEDLIFETAP_L
local Scanner = ScaledLifeTap_Scanner

-- Base health converted per rank, and spell damage coefficient per rank.
-- Coefficient is 0.8 reduced by the sub-level-20 penalty for ranks 1 (lvl 6) and 2 (lvl 16).
local BASE  = { 30, 75, 140, 220, 310, 424 }
local COEF  = { 0.38, 0.68, 0.8, 0.8, 0.8, 0.8 }

local DEFAULTS = {
	overtap   = true,     -- cast rank 1 if no rank fits but mana is not full
	debug     = false,
	reserve   = 0,        -- never tap below this % of max health
	bonus     = 0,        -- extra spell damage to add (e.g. elixirs/buffs the scanner can't see)
	source    = "auto",   -- "auto" = ClassicAPI > Nampower > built-in; or force one (incl. bonusscanner)
	calibrate = true,     -- learn a mana correction from Nampower energize events
	gainFactor = 1,
	samples   = 0,
}

local spellIndex = {}     -- [rank] = spellbook index
local maxRank = 0
local spellsDirty = true
local talentMult, talentDirty = 1, true

local function msg(text) DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9ScaledLifeTap:|r " .. text) end
local function dbg(text) if SLT_Config and SLT_Config.debug then msg(text) end end

---------------------------------------------------------------------------
-- spellbook / talents (cached, refreshed on events)
---------------------------------------------------------------------------
local function scanSpellbook()
	for k in pairs(spellIndex) do spellIndex[k] = nil end
	maxRank = 0
	local i = 1
	while true do
		local name, rankText = GetSpellName(i, BOOKTYPE_SPELL)
		if not name then break end      -- end of spellbook (v3 looped forever here)
		if name == L.LIFETAP then
			local _, _, r = string.find(rankText or "", "(%d+)")
			r = tonumber(r) or 1
			if BASE[r] then
				spellIndex[r] = i
				if r > maxRank then maxRank = r end
			end
		end
		i = i + 1
	end
	spellsDirty = false
end

local function scanTalents()
	talentMult = 1
	for tab = 1, (GetNumTalentTabs() or 0) do
		for t = 1, (GetNumTalents(tab) or 0) do
			local name, _, _, _, rank = GetTalentInfo(tab, t)
			if name == L.IMP_LIFETAP then
				talentMult = 1 + 0.1 * (rank or 0)
				talentDirty = false
				return
			end
		end
	end
	talentDirty = false
end

---------------------------------------------------------------------------
-- spell damage
---------------------------------------------------------------------------
-- Each source returns (genericDamage, shadowDamage) or nil when unavailable.
-- ClassicAPI and Nampower read the client's own computed shadow spell damage,
-- which already includes gear, enchants, buffs and set bonuses.
local SOURCES = {
	classicapi = function()
		if type(GetSpellBonusDamage) ~= "function" then return nil end
		local ok, v = pcall(GetSpellBonusDamage, 6)          -- 6 = Shadow (1-based)
		if ok and tonumber(v) then return 0, tonumber(v) end
	end,
	nampower = function()
		if type(GetSpellPower) ~= "function" or type(GetNampowerVersion) ~= "function" then return nil end
		local ok, _, _, _, _, _, shadow = pcall(GetSpellPower)  -- 6th value = Shadow
		if ok and tonumber(shadow) then return 0, tonumber(shadow) end
	end,
	bonusscanner = function()
		if not (BonusScanner and BonusScanner.GetBonus and IsAddOnLoaded("BonusScanner")) then return nil end
		return tonumber(BonusScanner:GetBonus("DMG")) or 0, tonumber(BonusScanner:GetBonus("SHADOWDMG")) or 0
	end,
	internal = function() return Scanner:Get() end,
}
local SOURCE_NAMES = { classicapi = "ClassicAPI", nampower = "Nampower", bonusscanner = "BonusScanner", internal = "built-in scanner" }
-- BonusScanner is deliberately not in the auto order: it gives the same totals
-- as the built-in scanner on English clients and likely 0 on German/French ones.
-- It can still be forced with /slt source bonusscanner.
local AUTO_ORDER = { "classicapi", "nampower", "internal" }
local LIVE_SOURCES = { classicapi = true, nampower = true }   -- these already include buffs

function ScaledLifeTap_GetDamageBonus()
	local want = SLT_Config.source or "auto"
	local dmg, shadow, key
	if want ~= "auto" and SOURCES[want] then
		dmg, shadow = SOURCES[want]()
		key = want
	end
	if not dmg then
		for i = 1, table.getn(AUTO_ORDER) do
			key = AUTO_ORDER[i]
			dmg, shadow = SOURCES[key]()
			if dmg then break end
		end
	end
	local total = (dmg or 0) + (shadow or 0) + (SLT_Config.bonus or 0)
	return total, dmg or 0, shadow or 0, SOURCE_NAMES[key], LIVE_SOURCES[key]
end

---------------------------------------------------------------------------
-- mana check (Nampower SPELL_ENERGIZE_BY_SELF): compares predicted mana per
-- Life Tap with what the server actually gave, and learns a correction factor
-- if your server's numbers differ from standard 1.12.
---------------------------------------------------------------------------
local lastCast       -- { rank, predicted, time }
local warned = false

local function onEnergize(spellId, powerType, amount)
	if not lastCast or powerType ~= 0 or not tonumber(amount) then return end
	if GetTime() - lastCast.time > 3 then lastCast = nil; return end
	if type(GetSpellNameAndRankForId) == "function" then
		local ok, name = pcall(GetSpellNameAndRankForId, spellId)
		if not ok or name ~= L.LIFETAP then return end
	end
	local base = lastCast.predicted / (SLT_Config.gainFactor or 1)
	lastCast = nil
	if base <= 0 or not SLT_Config.calibrate then return end
	local ratio = amount / base
	if ratio < 0.5 or ratio > 2 then return end           -- ignore nonsense
	-- smooth toward the observed ratio
	SLT_Config.gainFactor = (SLT_Config.gainFactor or 1) * 0.7 + ratio * 0.3
	SLT_Config.samples = (SLT_Config.samples or 0) + 1
	if not warned and SLT_Config.samples >= 3 and math.abs(SLT_Config.gainFactor - 1) > 0.03 then
		warned = true
		msg(string.format("Life Tap is giving %d%% of the predicted mana on this server; adjusting automatically (/slt calibrate reset to undo).",
			SLT_Config.gainFactor * 100 + 0.5))
	end
end

---------------------------------------------------------------------------
-- rank selection
---------------------------------------------------------------------------
-- returns rank (or nil), hpCost, manaGain
function ScaledLifeTap_ChooseRank()
	if spellsDirty then scanSpellbook() end
	if talentDirty then scanTalents() end
	if maxRank == 0 then return nil end

	local bonus = ScaledLifeTap_GetDamageBonus()
	local mult = talentMult * (SLT_Config.gainFactor or 1)
	local hp = UnitHealth("player")
	local missing = UnitManaMax("player") - UnitMana("player")
	local floor = UnitHealthMax("player") * (SLT_Config.reserve or 0) / 100

	for r = maxRank, 1, -1 do
		if spellIndex[r] then
			local cost = BASE[r] + COEF[r] * bonus
			local gain = cost * mult
			if hp - cost > floor and missing >= gain then return r, cost, gain, true end
		end
	end

	if SLT_Config.overtap and missing > 0 then
		local r = 1
		while r <= maxRank and not spellIndex[r] do r = r + 1 end
		if spellIndex[r] then
			local cost = BASE[r] + COEF[r] * bonus
			if hp - cost > floor then return r, cost, cost * mult, false end
		end
	end
	return nil
end

function ScaledLifeTap_CastLifeTap()
	local r, cost, gain, fits = ScaledLifeTap_ChooseRank()
	if r then
		CastSpell(spellIndex[r], BOOKTYPE_SPELL)
		-- only fully-fitting casts are used for the mana check (overtap casts may hit the mana cap)
		if fits then lastCast = { rank = r, predicted = gain, time = GetTime() } else lastCast = nil end
		dbg(string.format("Rank %d: -%d hp, +%d mana", r, cost, gain))
	elseif maxRank == 0 then
		dbg("Life Tap not found in spellbook.")
	else
		dbg("No rank fits (mana full or health too low).")
	end
end

-- backwards compatibility with v3 macros
ScaledLifetap_CastLifeTap = ScaledLifeTap_CastLifeTap
function ScaledLifeTap_Debug(arg)
	if arg == nil then return SLT_Config.debug end
	SLT_Config.debug = (arg == 1 or arg == true)
end

---------------------------------------------------------------------------
-- status / slash commands
---------------------------------------------------------------------------
local function onoff(v) return v and "|cff00ff00on|r" or "|cffff0000off|r" end

local function printStatus()
	if spellsDirty then scanSpellbook() end
	if talentDirty then scanTalents() end
	local total, dmg, shadow, source, live = ScaledLifeTap_GetDamageBonus()
	if live then
		msg(string.format("shadow spell damage %d (incl. buffs) + manual %d = %d  (source: %s)", shadow, SLT_Config.bonus or 0, total, source))
	else
		msg(string.format("spell dmg %d + shadow %d + manual %d = %d  (source: %s, gear only)", dmg, shadow, SLT_Config.bonus or 0, total, source))
	end
	local mult = talentMult * (SLT_Config.gainFactor or 1)
	msg(string.format("Improved Life Tap x%.1f | server correction x%.3f (%d samples) | overtap %s | reserve %d%% | highest rank %d",
		talentMult, SLT_Config.gainFactor or 1, SLT_Config.samples or 0, onoff(SLT_Config.overtap), SLT_Config.reserve or 0, maxRank))
	for r = maxRank, 1, -1 do
		if spellIndex[r] then
			local cost = BASE[r] + COEF[r] * total
			msg(string.format("  Rank %d: -%d hp  +%d mana", r, cost, cost * mult))
		end
	end
end

local function toggleArg(arg, current)
	if arg == "on" then return true elseif arg == "off" then return false end
	return not current
end

SLASH_SCALEDLIFETAP1 = "/slt"
SLASH_SCALEDLIFETAP2 = "/scaledlifetap"
SlashCmdList["SCALEDLIFETAP"] = function(input)
	local _, _, cmd, arg = string.find(string.lower(input or ""), "^%s*(%S*)%s*(.-)%s*$")
	if cmd == "cast" then
		ScaledLifeTap_CastLifeTap()
	elseif cmd == "status" then
		printStatus()
	elseif cmd == "overtap" then
		SLT_Config.overtap = toggleArg(arg, SLT_Config.overtap); msg("overtap " .. onoff(SLT_Config.overtap))
	elseif cmd == "debug" then
		SLT_Config.debug = toggleArg(arg, SLT_Config.debug); msg("debug " .. onoff(SLT_Config.debug))
	elseif cmd == "reserve" and tonumber(arg) then
		local v = math.max(0, math.min(90, tonumber(arg)))
		SLT_Config.reserve = v; msg("health reserve " .. v .. "%")
	elseif cmd == "bonus" and tonumber(arg) then
		SLT_Config.bonus = tonumber(arg); msg("manual spell damage bonus " .. SLT_Config.bonus)
	elseif cmd == "calibrate" and (arg == "on" or arg == "off" or arg == "") then
		SLT_Config.calibrate = toggleArg(arg, SLT_Config.calibrate); msg("mana check " .. onoff(SLT_Config.calibrate))
	elseif cmd == "calibrate" and arg == "reset" then
		SLT_Config.gainFactor, SLT_Config.samples = 1, 0; warned = false; msg("mana correction reset")
	elseif cmd == "source" and (arg == "auto" or SOURCES[arg]) then
		SLT_Config.source = arg; Scanner:MarkDirty(); msg("damage source " .. arg)
	elseif cmd == "rescan" then
		Scanner:MarkDirty(); spellsDirty = true; talentDirty = true; printStatus()
	else
		msg("commands:")
		msg("  /slt cast  - cast the best Life Tap rank (put this in a macro)")
		msg("  /slt status  - show bonus, talent and per-rank numbers")
		msg("  /slt overtap [on|off]  - fall back to rank 1 when no rank fits (" .. onoff(SLT_Config.overtap) .. ")")
		msg("  /slt reserve <0-90>  - never tap below this % health (" .. (SLT_Config.reserve or 0) .. "%)")
		msg("  /slt bonus <n>  - extra spell damage to add, e.g. from elixirs (" .. (SLT_Config.bonus or 0) .. ")")
		msg("  /slt source auto|classicapi|nampower|bonusscanner|internal  - where spell damage comes from (" .. SLT_Config.source .. ")")
		msg("  /slt calibrate [on|off|reset]  - learn actual mana per tap (needs Nampower) (" .. onoff(SLT_Config.calibrate) .. ")")
		msg("  /slt debug [on|off]  - print each cast (" .. onoff(SLT_Config.debug) .. ")")
		msg("  /slt rescan  - force a gear/spellbook/talent rescan")
	end
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
SLT_Config = SLT_Config or {}

local f = CreateFrame("Frame", "ScaledLifeTapEventFrame")
f:RegisterEvent("VARIABLES_LOADED")
f:RegisterEvent("UNIT_INVENTORY_CHANGED")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("LEARNED_SPELL_IN_TAB")
f:RegisterEvent("CHARACTER_POINTS_CHANGED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Nampower custom event (registering it enables it on Nampower 4.5+; older
-- versions need  /run SetCVar("NP_EnableSpellEnergizeEvents","1")  ). Harmless otherwise.
pcall(f.RegisterEvent, f, "SPELL_ENERGIZE_BY_SELF")
f:SetScript("OnEvent", function()
	if event == "SPELL_ENERGIZE_BY_SELF" then
		onEnergize(arg3, arg4, arg5)
	elseif event == "UNIT_INVENTORY_CHANGED" then
		if arg1 == "player" then Scanner:MarkDirty() end
	elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
		spellsDirty = true
	elseif event == "CHARACTER_POINTS_CHANGED" then
		talentDirty = true
	elseif event == "PLAYER_ENTERING_WORLD" then
		Scanner:MarkDirty(); spellsDirty = true; talentDirty = true
	elseif event == "VARIABLES_LOADED" then
		if type(SLT_Config) ~= "table" then SLT_Config = {} end
		-- v3 stored "overtapEnabled"
		if SLT_Config.overtapEnabled ~= nil and SLT_Config.overtap == nil then
			SLT_Config.overtap = SLT_Config.overtapEnabled
		end
		SLT_Config.overtapEnabled = nil
		for k, v in pairs(DEFAULTS) do
			if SLT_Config[k] == nil then SLT_Config[k] = v end
		end
	end
end)

-- make sure defaults exist even before VARIABLES_LOADED (e.g. when loaded late)
for k, v in pairs(DEFAULTS) do if SLT_Config[k] == nil then SLT_Config[k] = v end end
