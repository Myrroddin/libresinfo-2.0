--[[--------------------------------------------------------------------
LibResInfo-2.0

CLEU-free resurrection tracking library.

Design philosophy:
- GUID-first identity (unitIDs are transient)
- SpellID-based logic (no localized names)
- Event correlation (no direct caster→target API)
- Explicit uncertainty modeling
----------------------------------------------------------------------]]

local MAJOR, MINOR = "LibResInfo-2.0", 1
assert(LibStub, MAJOR .. " requires LibStub")
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local CallbackHandler = LibStub("CallbackHandler-1.0")

lib.callbacks = lib.callbacks or CallbackHandler:New(lib)

lib.embeds = lib.embeds or {}

-- -------------------------------------------------------------------
-- Events functions
-- -------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, ...)
	self[event](self, event, ...)
end)

frame:RegisterEvent("PLAYER_LOGIN")

-- -------------------------------------------------------------------
-- WoW API
-- -------------------------------------------------------------------

local UnitGUID = UnitGUID
local UnitCastingInfo = UnitCastingInfo
local UnitName = UnitName
local UnitTokenFromGUID = UnitTokenFromGUID
local UnitSpellTargetName = UnitSpellTargetName
local wipe = table.wipe
local IsInInstance = IsInInstance
local pairs = pairs
local IsPlayerNeutral = IsPlayerNeutral
local UnitFactionGroup = UnitFactionGroup
local GetTime = GetTime
local type = type
local GetNamePlates = C_NamePlate.GetNamePlates
local GetSpellInfo = C_Spell.GetSpellInfo

-- -------------------------------------------------------------------
-- Internal state
-- -------------------------------------------------------------------

-- Resurrection state by caster GUID
local resCasterInfo = {}

-- Mass resurrection state by caster GUID
local massResCasterInfo = {}

-- Resurrection state by target GUID
local resTargetInfo = {}

-- -------------------------------------------------------------------
-- Spell tables
-- -------------------------------------------------------------------

local SINGLE_TARGET_RES_SPELLS = {
	-- Priest
	[2006]		= true,		-- Resurrection

	-- Paladin
	[7328]		= true,		-- Redemption

	-- Shaman
	[2008]		= true,		-- Ancestral Spirit

	-- Druid
	[50769]		= true,		-- Revive

	-- Monk
	[115178]	= true,		-- Resuscitate

	-- Hunter
	[982]		= true,		-- Revive Pet

	-- Evoker
	[361227]	= true,		-- Return

	-- Engineering (Defibrillate)
	[8342]		= true,		-- Goblin Jumper Cables
	[22999]		= true,		-- Goblin Jumper Cables XL
	[54732]		= true,		-- Gnomish Army Knife
	[164729]	= true,		-- Ultimate Gnomish Army Knife
	[385404]	= true,		-- Arclight Vital Correctors

	-- Combat res
	[20707]		= true,		-- Soulstone Resurrection
	[20484]		= true,		-- Rebirth
	[61999]		= true,		-- Raise Ally
	[391054]	= true,		-- Intercession
	[159956]	= true,		-- Eternal Guardian

	-- Self res spells (auras are tracked elsewhere)
	[20608]		= true,		-- Reincarnation
	[18976]		= true,		-- Self Resurrection
	[23683]		= true,		-- Twisting Nether
	[23700]		= true,		-- Twisting Nether
	[23701]		= true,		-- Twisting Nether
	[148623]	= true,		-- Cauterizing Core
	[280007]	= true,		-- Drust Soulcatcher

	-- World Object
	[187777]	= true,		-- Reawaken (Brazier of Awakening)
	[199119]	= true,		-- Failure Detection Aura (Failure Detection Pylon)
	[339643]	= true,		-- Gift of Life (Mi'kai's Deathscythe)
}

local MASS_RES_SPELLS = {
	-- Paladin
	[212056]	= true,		-- Absolution

	-- Shaman
	[212048]	= true,		-- Ancestral Vision

	-- Priest
	[212036]	= true,		-- Mass Resurrection

	-- Monk
	[212051]	= true,		-- Reawaken

	-- Druid
	[212040]	= true,		-- Revitalize

	-- Evoker
	[361178]	= true,		-- Mass Return
}

-- -------------------------------------------------------------------
-- Constants
-- -------------------------------------------------------------------

local RES_PENDING_TIMEOUT = 60
local PLAYER_GUID, PLAYER_NAME, PLAYER_REALM
local isMists = WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC
local isMainline = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

local events = {
	["INCOMING_RESURRECT_CHANGED"]	= true,
	["PLAYER_REGEN_DISABLED"]		= true,
	["RESURRECT_REQUEST"]			= true,
	["UNIT_HEALTH"]					= true,
	["UNIT_SPELLCAST_FAILED"]		= true,
	["UNIT_SPELLCAST_FAILED_QUIET"]	= true,
	["UNIT_SPELLCAST_INTERRUPTED"]	= true,
	["UNIT_SPELLCAST_START"]		= true,
	["UNIT_SPELLCAST_STOP"]			= true,
	["UNIT_SPELLCAST_SUCCEEDED"]	= true,
	["UNIT_SPELLCAST_SENT"]			= true,
}

-- -------------------------------------------------------------------
-- Helper functions
-- -------------------------------------------------------------------
-- Helper function to determine the fastest resurrection caster for a given targetGUID, and update resTargetInfo with that caster's GUID and resurrection type.
-- This is called whenever we add/update/remove a resurrection cast for a targetGUID, and also when mass resurrection casts are added/updated/removed since they can affect any targetGUID.
local function UpdateFastestCasterGUID(targetGUID)
	if not targetGUID then return end
	if not resTargetInfo[targetGUID] then return end

	local fastestCasterGUID
	local fastestResType
	local fastestEndTime

	for casterGUID, casterInfo in pairs(resTargetInfo[targetGUID]) do
		if type(casterInfo) == "table" then
			if not fastestEndTime or (casterInfo.endTime and casterInfo.endTime < fastestEndTime) then
				fastestCasterGUID = casterGUID
				fastestResType = "SINGLE"
				fastestEndTime = casterInfo.endTime
			end
		end
	end

	for casterGUID, casterInfo in pairs(massResCasterInfo) do
		if type(casterInfo) == "table" then
			if not fastestEndTime or (casterInfo.endTime and casterInfo.endTime < fastestEndTime) then
				fastestCasterGUID = casterGUID
				fastestResType = "MASS"
				fastestEndTime = casterInfo.endTime
			end
		end
	end

	local oldFastestCasterGUID = resTargetInfo[targetGUID].fastestCasterGUID
	local oldFastestResType = resTargetInfo[targetGUID].fastestResType
	local hadFastestCaster = oldFastestCasterGUID ~= nil

	resTargetInfo[targetGUID].fastestCasterGUID = fastestCasterGUID
	resTargetInfo[targetGUID].fastestResType = fastestResType

	if hadFastestCaster and ((oldFastestCasterGUID ~= fastestCasterGUID) or (oldFastestResType ~= fastestResType)) then
		return resTargetInfo[targetGUID]
	end
end

-- Helper function to update the fastest caster for all targetGUIDs. This is called when mass resurrection casts are added/updated/removed since they can affect any targetGUID.
local function UpdateAllFastestCasterGUIDs()
	local changedTargetInfo

	for targetGUID in pairs(resTargetInfo) do
		local targetInfo = UpdateFastestCasterGUID(targetGUID)

		if targetInfo then
			changedTargetInfo = changedTargetInfo or {}
			changedTargetInfo[#changedTargetInfo + 1] = targetInfo
		end
	end

	return changedTargetInfo
end

-- Helper function to populate resCasterInfo, massResCasterInfo, and resTargetInfo when we detect a cast of a resurrection spell. This is called from UNIT_SPELLCAST_START.
local function PopulateResInfoTables(unitID)
	local casterGUID = UnitGUID(unitID)
	if not casterGUID then return end

	local spellName, _, textureID, startTimeMs, endTimeMs, _, castGUID, _, spellID = UnitCastingInfo(unitID)
	local castTime = (endTimeMs and startTimeMs) and ((endTimeMs - startTimeMs) / 1000)
	local endTime = endTimeMs and (endTimeMs / 1000)

	if not castTime then castTime = 0 end
	if not endTime then endTime = GetTime() end

	local targetGUID = "UNKNOWN"
	local resType = (SINGLE_TARGET_RES_SPELLS[spellID] and "SINGLE") or (MASS_RES_SPELLS[spellID] and "MASS") or nil
	local fastestTargetInfo

	if spellName and spellID and SINGLE_TARGET_RES_SPELLS[spellID] then
		local existingCasterInfo = resCasterInfo[casterGUID]
		local existingTargetGUID = existingCasterInfo and existingCasterInfo.targetGUID

		local targetName = UnitSpellTargetName(unitID)
		targetGUID = UnitGUID(targetName) or existingTargetGUID or "UNKNOWN"

		resCasterInfo[casterGUID] = resCasterInfo[casterGUID] or {}
		resCasterInfo[casterGUID].castGUID = resCasterInfo[casterGUID].castGUID or castGUID
		resCasterInfo[casterGUID].casterGUID = resCasterInfo[casterGUID].casterGUID or casterGUID
		resCasterInfo[casterGUID].castTime = resCasterInfo[casterGUID].castTime or castTime
		resCasterInfo[casterGUID].spellID = resCasterInfo[casterGUID].spellID or spellID
		resCasterInfo[casterGUID].targetGUID = resCasterInfo[casterGUID].targetGUID or targetGUID
		resCasterInfo[casterGUID].textureID = resCasterInfo[casterGUID].textureID or textureID
		resCasterInfo[casterGUID].endTime = resCasterInfo[casterGUID].endTime or endTime

		resTargetInfo[targetGUID] = resTargetInfo[targetGUID] or {}
		resTargetInfo[targetGUID].targetGUID = resTargetInfo[targetGUID].targetGUID or targetGUID
		resTargetInfo[targetGUID][casterGUID] = resTargetInfo[targetGUID][casterGUID] or {}
		resTargetInfo[targetGUID][casterGUID].castGUID = resTargetInfo[targetGUID][casterGUID].castGUID or castGUID
		resTargetInfo[targetGUID][casterGUID].casterGUID = resTargetInfo[targetGUID][casterGUID].casterGUID or casterGUID
		resTargetInfo[targetGUID][casterGUID].castTime = resTargetInfo[targetGUID][casterGUID].castTime or castTime
		resTargetInfo[targetGUID][casterGUID].spellID = resTargetInfo[targetGUID][casterGUID].spellID or spellID
		resTargetInfo[targetGUID][casterGUID].targetGUID = resTargetInfo[targetGUID][casterGUID].targetGUID or targetGUID
		resTargetInfo[targetGUID][casterGUID].textureID = resTargetInfo[targetGUID][casterGUID].textureID or textureID
		resTargetInfo[targetGUID][casterGUID].endTime = resTargetInfo[targetGUID][casterGUID].endTime or endTime

		fastestTargetInfo = UpdateFastestCasterGUID(targetGUID)
	elseif spellName and spellID and MASS_RES_SPELLS[spellID] then
		massResCasterInfo[casterGUID] = massResCasterInfo[casterGUID] or {}
		massResCasterInfo[casterGUID].castGUID = massResCasterInfo[casterGUID].castGUID or castGUID
		massResCasterInfo[casterGUID].casterGUID = massResCasterInfo[casterGUID].casterGUID or casterGUID
		massResCasterInfo[casterGUID].castTime = massResCasterInfo[casterGUID].castTime or castTime
		massResCasterInfo[casterGUID].spellID = massResCasterInfo[casterGUID].spellID or spellID
		massResCasterInfo[casterGUID].textureID = massResCasterInfo[casterGUID].textureID or textureID
		massResCasterInfo[casterGUID].endTime = massResCasterInfo[casterGUID].endTime or endTime

		fastestTargetInfo = UpdateAllFastestCasterGUIDs()
	end

	return resType, casterGUID, targetGUID, fastestTargetInfo
end

-- Helper function to replace "UNKNOWN" targetGUID with the correct targetGUID when we get a match in INCOMING_RESURRECT_CHANGED.
-- This involves moving all of the incoming resurrection info from the "UNKNOWN" entry to the correct targetGUID entry, and then removing the "UNKNOWN" entry if it's empty.
local function ReplaceUnknownTargetGUID(targetGUID, casterGUID)
	if not targetGUID or not casterGUID then return end
	if not resTargetInfo["UNKNOWN"] then return end
	if not resTargetInfo["UNKNOWN"][casterGUID] then return end

	resTargetInfo[targetGUID] = resTargetInfo[targetGUID] or {}
	resTargetInfo[targetGUID].targetGUID = targetGUID

	resTargetInfo[targetGUID][casterGUID] = resTargetInfo["UNKNOWN"][casterGUID]
	resTargetInfo[targetGUID][casterGUID].targetGUID = targetGUID

	resTargetInfo["UNKNOWN"][casterGUID] = nil

	if resTargetInfo["UNKNOWN"].fastestCasterGUID == casterGUID then
		resTargetInfo["UNKNOWN"].fastestCasterGUID = nil
		resTargetInfo["UNKNOWN"].fastestResType = nil
	end

	UpdateFastestCasterGUID("UNKNOWN")
	UpdateFastestCasterGUID(targetGUID)

	local hasUnknownEntries

	for _, info in pairs(resTargetInfo["UNKNOWN"]) do
		if type(info) == "table" then
			hasUnknownEntries = true
			break
		end
	end

	if not hasUnknownEntries then
		resTargetInfo["UNKNOWN"] = nil
	end
end

-- Helper function to check if a targetGUID has any caster entries in resTargetInfo.
-- This is used to determine if we can remove a targetGUID entry after a single-target resurrection cast ends, or if we need to keep it
-- because there are other casts (single-target or mass) that are still active for that targetGUID.
local function HasTargetCasterEntries(targetGUID)
	if not targetGUID or not resTargetInfo[targetGUID] then return end

	for _, info in pairs(resTargetInfo[targetGUID]) do
		if type(info) == "table" then
			return true
		end
	end
end

local function NormalizeCallbackTable(info)
	if info and not next(info) then
		return nil
	end

	return info
end

local function RemoveSingleResCast(casterGUID, targetGUID, updateFastest, removeTargetInfo)
	if not casterGUID then return end

	targetGUID = targetGUID or "UNKNOWN"

	resCasterInfo[casterGUID] = nil

	if resTargetInfo[targetGUID] then
		resTargetInfo[targetGUID][casterGUID] = nil
	end

	local targetInfo
	local changedTargetInfo

	if removeTargetInfo and targetGUID ~= "UNKNOWN" then
		resTargetInfo[targetGUID] = nil
	elseif HasTargetCasterEntries(targetGUID) then
		if updateFastest then
			changedTargetInfo = UpdateFastestCasterGUID(targetGUID)
		else
			if resTargetInfo[targetGUID].fastestCasterGUID == casterGUID then
				resTargetInfo[targetGUID].fastestCasterGUID = nil
				resTargetInfo[targetGUID].fastestResType = nil
				UpdateFastestCasterGUID(targetGUID)
			end
		end

		targetInfo = resTargetInfo[targetGUID]
	else
		resTargetInfo[targetGUID] = nil
	end

	return NormalizeCallbackTable(resCasterInfo[casterGUID]), NormalizeCallbackTable(targetInfo), changedTargetInfo
end

local function RemoveMassResCast(casterGUID, updateFastest)
	if not casterGUID then return end

	massResCasterInfo[casterGUID] = nil

	local changedTargetInfo

	if updateFastest then
		changedTargetInfo = UpdateAllFastestCasterGUIDs()
	end

	return NormalizeCallbackTable(massResCasterInfo[casterGUID]), changedTargetInfo
end

-- -------------------------------------------------------------------
-- Event handlers
-- -------------------------------------------------------------------

-- Assign values to constants and register events.
function lib:PLAYER_LOGIN()
	PLAYER_GUID = PLAYER_GUID or UnitGUID("player")
	PLAYER_NAME, PLAYER_REALM = PLAYER_NAME, PLAYER_REALM or UnitName("player")

	-- Clear all states. This is important for handling logouts/reloads while casts are active.
	wipe(resCasterInfo)
	wipe(massResCasterInfo)
	wipe(resTargetInfo)

	for k, v in pairs(events) do
		if v then
			frame:RegisterEvent(k)
		end
	end

	if IsPlayerNeutral() and (isMists or isMainline) then
		frame:RegisterEvent("NEUTRAL_FACTION_SELECT_RESULT") -- Neutral factioned players can change GUIDs when they select a faction, so we need to update our stored PLAYER_GUID when that happens.
	end

	-- These events result in the same state changes, so we can handle them with the same function
	lib.UNIT_SPELLCAST_FAILED			= lib.UNIT_SPELLCAST_STOP
	lib.UNIT_SPELLCAST_FAILED_QUIET		= lib.UNIT_SPELLCAST_STOP
	lib.UNIT_SPELLCAST_INTERRUPTED		= lib.UNIT_SPELLCAST_STOP
end

-- Update the player's GUID if they changed factions.
function lib:NEUTRAL_FACTION_SELECT_RESULT(_, success)
	if success then
		local factionGroup = UnitFactionGroup("player")
		if factionGroup == "Alliance" or factionGroup == "Horde" then
			PLAYER_GUID = UnitGUID("player")
			frame:UnregisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
		end
	end
end

-- The player has cast a spell. Check if it's a resurrection spell, and if so, populate the relevant tables and fire the callback.
function lib:UNIT_SPELLCAST_SENT(_, unitID, targetID, castGUID, spellID)
	local endTime = GetTime()

	if SINGLE_TARGET_RES_SPELLS[spellID] then
		local targetGUID = UnitGUID(targetID) or "UNKNOWN"

		resCasterInfo[PLAYER_GUID] = resCasterInfo[PLAYER_GUID] or {}
		resCasterInfo[PLAYER_GUID].castGUID = castGUID
		resCasterInfo[PLAYER_GUID].casterGUID = PLAYER_GUID
		resCasterInfo[PLAYER_GUID].spellID = spellID
		resCasterInfo[PLAYER_GUID].targetGUID = targetGUID
		resCasterInfo[PLAYER_GUID].endTime = endTime

		resTargetInfo[targetGUID] = resTargetInfo[targetGUID] or {}
		resTargetInfo[targetGUID].targetGUID = targetGUID
		resTargetInfo[targetGUID][PLAYER_GUID] = resTargetInfo[targetGUID][PLAYER_GUID] or {}
		resTargetInfo[targetGUID][PLAYER_GUID].castGUID = castGUID
		resTargetInfo[targetGUID][PLAYER_GUID].casterGUID = PLAYER_GUID
		resTargetInfo[targetGUID][PLAYER_GUID].spellID = spellID
		resTargetInfo[targetGUID][PLAYER_GUID].targetGUID = targetGUID
		resTargetInfo[targetGUID][PLAYER_GUID].endTime = endTime
	elseif MASS_RES_SPELLS[spellID] then
		massResCasterInfo[PLAYER_GUID] = massResCasterInfo[PLAYER_GUID] or {}
		massResCasterInfo[PLAYER_GUID].castGUID = castGUID
		massResCasterInfo[PLAYER_GUID].casterGUID = PLAYER_GUID
		massResCasterInfo[PLAYER_GUID].spellID = spellID
		massResCasterInfo[PLAYER_GUID].endTime = endTime
	end

	local resType, casterGUID, targetGUID, fastestTargetInfo = PopulateResInfoTables(unitID)

	if resType == "SINGLE" then
		local casterInfo = resCasterInfo[casterGUID]
		local targetInfo = resTargetInfo[targetGUID]

		lib.callbacks:Fire("ResCast_Started", casterInfo, targetInfo)

		if fastestTargetInfo then
			lib.callbacks:Fire("FastestResChanged", fastestTargetInfo)
		end
	elseif resType == "MASS" then
		local casterInfo = massResCasterInfo[casterGUID]

		lib.callbacks:Fire("MassResCast_Started", casterInfo)

		if fastestTargetInfo then
			for _, targetInfo in pairs(fastestTargetInfo) do
				lib.callbacks:Fire("FastestResChanged", targetInfo)
			end
		end
	end
end

-- A spellcast has started. Check if it's a resurrection spell, and if so, populate the relevant tables and fire the callback.
function lib:UNIT_SPELLCAST_START(_, unitID)
	local resType, casterGUID, targetGUID, fastestTargetInfo = PopulateResInfoTables(unitID)

	if resType == "SINGLE" then
		local casterInfo = resCasterInfo[casterGUID]
		local targetInfo = resTargetInfo[targetGUID]

		lib.callbacks:Fire("ResCast_Started", casterInfo, targetInfo)

		if fastestTargetInfo then
			lib.callbacks:Fire("FastestResChanged", fastestTargetInfo)
		end
	elseif resType == "MASS" then
		local casterInfo = massResCasterInfo[casterGUID]

		lib.callbacks:Fire("MassResCast_Started", casterInfo)

		if fastestTargetInfo then
			for _, targetInfo in pairs(fastestTargetInfo) do
				lib.callbacks:Fire("FastestResChanged", targetInfo)
			end
		end
	end
end

-- A targetID has an incoming resurrection. Verify the targetID is being tracked
function lib:INCOMING_RESURRECT_CHANGED(_, targetID)
	local targetGUID = UnitGUID(targetID)
	-- Can't track without a GUID, exit early.
	if not targetGUID then return end
	local casterGUID
	local targetName, targetRealm = UnitName(targetID)

	for _, info in pairs(resCasterInfo) do
		-- This is a single-target res cast with an unknown targetGUID, update if possible.
		if info.targetGUID == "UNKNOWN" then
			casterGUID = info.casterGUID
			-- We can't trust the unit token between events, so we get the casterID from the GUID every time we want to correlate.
			local casterID = UnitTokenFromGUID(casterGUID)
			if casterID then
				local spellTargetName = UnitSpellTargetName(casterID)
				if spellTargetName then
					if spellTargetName == (targetRealm and targetName .. "-" .. targetRealm) or (spellTargetName == targetName) then
						-- We have a match! Update the caster's targetGUID and the targetGUID's incoming resurrection info.
						info.targetGUID = targetGUID -- No longer "UNKNOWN", we have a confirmed target!

						ReplaceUnknownTargetGUID(targetGUID, casterGUID)

						local casterInfo = resCasterInfo[casterGUID]
						local targetInfo = resTargetInfo[targetGUID]

						lib.callbacks:Fire("ResTargetInfo_Updated", casterInfo, targetInfo)
					end
				end
			end
		end
	end
end

-- The player has received a resurrection request.
function lib:RESURRECT_REQUEST(_, inviterName)
	PLAYER_GUID = PLAYER_GUID or UnitGUID("player")
	-- We can't track if we're in any instance or in combat, exit early because we cannot scan nameplates.
	if IsInInstance() then return end
	if InCombatLockdown() or UnitAffectingCombat("player") then return end
end

-- A resurrection cast has ended, either stoppped, failed, or interrupted. Clear the relevant tables and fire the callback.
function lib:UNIT_SPELLCAST_STOP(_, unitID, castGUID, spellID)
	local casterGUID = UnitGUID(unitID)
	if not casterGUID then return end
	local targetInfo, changedTargetInfo

	if SINGLE_TARGET_RES_SPELLS[spellID] then
		local casterInfo = resCasterInfo[casterGUID]
		if not casterInfo then return end
		if casterInfo.castGUID and castGUID and casterInfo.castGUID ~= castGUID then return end

		local targetGUID = casterInfo.targetGUID or "UNKNOWN"

		casterInfo, targetInfo, changedTargetInfo = RemoveSingleResCast(casterGUID, targetGUID, true, false)

		lib.callbacks:Fire("ResCast_Stopped", casterGUID, targetGUID, casterInfo, targetInfo)

		if changedTargetInfo then
			lib.callbacks:Fire("FastestResChanged", changedTargetInfo)
		end
	elseif MASS_RES_SPELLS[spellID] then
		local casterInfo = massResCasterInfo[casterGUID]
		if not casterInfo then return end
		if casterInfo.castGUID and castGUID and casterInfo.castGUID ~= castGUID then return end

		casterInfo, changedTargetInfo = RemoveMassResCast(casterGUID, true)

		lib.callbacks:Fire("MassResCast_Stopped", casterGUID, casterInfo)

		if changedTargetInfo then
			for _, changedInfo in pairs(changedTargetInfo) do
				if changedInfo then
					lib.callbacks:Fire("FastestResChanged", changedInfo)
				end
			end
		end
	end
end

-- A spellcast succeeded. This could be an instant cast resurrection which wasn't tracked, or it could be a non-instant cast which successfully ended its lifecycle.
function lib:UNIT_SPELLCAST_SUCCEEDED(_, unitID, castGUID, spellID)
	local casterGUID = UnitGUID(unitID)
	if not casterGUID then return end

	if SINGLE_TARGET_RES_SPELLS[spellID] then
		local casterInfo = resCasterInfo[casterGUID]
		local wasTracked = casterInfo ~= nil

		if casterInfo and casterInfo.castGUID and castGUID and casterInfo.castGUID ~= castGUID then return end

		local targetGUID

		if wasTracked then
			targetGUID = casterInfo.targetGUID or "UNKNOWN"
		else
			targetGUID = UnitGUID(UnitSpellTargetName(unitID)) or "UNKNOWN"
		end

		if not wasTracked then
			local endTime = GetTime()

			resCasterInfo[casterGUID] = resCasterInfo[casterGUID] or {}
			resCasterInfo[casterGUID].castGUID = castGUID
			resCasterInfo[casterGUID].casterGUID = casterGUID
			resCasterInfo[casterGUID].castTime = 0
			resCasterInfo[casterGUID].spellID = spellID
			resCasterInfo[casterGUID].targetGUID = targetGUID
			resCasterInfo[casterGUID].endTime = endTime

			resTargetInfo[targetGUID] = resTargetInfo[targetGUID] or {}
			resTargetInfo[targetGUID].targetGUID = targetGUID
			resTargetInfo[targetGUID][casterGUID] = resTargetInfo[targetGUID][casterGUID] or {}
			resTargetInfo[targetGUID][casterGUID].castGUID = castGUID
			resTargetInfo[targetGUID][casterGUID].casterGUID = casterGUID
			resTargetInfo[targetGUID][casterGUID].castTime = 0
			resTargetInfo[targetGUID][casterGUID].spellID = spellID
			resTargetInfo[targetGUID][casterGUID].targetGUID = targetGUID
			resTargetInfo[targetGUID][casterGUID].endTime = endTime

			UpdateFastestCasterGUID(targetGUID)

			lib.callbacks:Fire("ResCast_Started", resCasterInfo[casterGUID], resTargetInfo[targetGUID])
		end

		local finishedCasterInfo = resCasterInfo[casterGUID]
		local finishedTargetInfo = resTargetInfo[targetGUID]

		lib.callbacks:Fire("ResCast_Finished", casterGUID, targetGUID, NormalizeCallbackTable(finishedCasterInfo), NormalizeCallbackTable(finishedTargetInfo))

		RemoveSingleResCast(casterGUID, targetGUID, false, true)
	elseif MASS_RES_SPELLS[spellID] then
		local casterInfo = massResCasterInfo[casterGUID]
		if not casterInfo then return end
		if casterInfo.castGUID and castGUID and casterInfo.castGUID ~= castGUID then return end

		local finishedCasterInfo = massResCasterInfo[casterGUID]

		lib.callbacks:Fire("MassResCast_Finished", casterGUID, NormalizeCallbackTable(finishedCasterInfo))

		RemoveMassResCast(casterGUID, false)
	end
end

-- -------------------------------------------------------------------
-- Embed mixins into target addon objects
-- -------------------------------------------------------------------

local mixins = {
	"RegisterCallback",
	"UnregisterCallback",
	"UnregisterAllCallbacks",
}

function lib:Embed(target)
	for _, v in pairs(mixins) do
		target[v] = self[v]
	end
	self.embeds[target] = true
	return target
end

for target in pairs(lib.embeds) do
	lib:Embed(target)
end