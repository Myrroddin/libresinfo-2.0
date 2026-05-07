--[[--------------------------------------------------------------------
LibResInfo-2.0

CLEU-free resurrection tracking library.

Design philosophy:
- GUID-first identity (unitIDs are transient)
- SpellID-based logic (no localized names)
- Event correlation (no direct caster→target API)
- Explicit uncertainty modeling
- Safe API (never expose internal state)
----------------------------------------------------------------------]]

local MAJOR, MINOR = "LibResInfo-2.0", 1
assert(LibStub, MAJOR .. " requires LibStub")
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local CallbackHandler = LibStub("CallbackHandler-1.0")

lib.callbacks = lib.callbacks or CallbackHandler:New(lib,
	"ResCast_Started",
)

lib.embeds = lib.embeds or {}

-- -------------------------------------------------------------------
-- Events registration
-- -------------------------------------------------------------------
local events = {
	["UNIT_SPELLCAST_START"]		= true,
	["UNIT_SPELLCAST_STOP"]			= true,
	["UNIT_SPELLCAST_SUCCEEDED"]	= true,
	["UNIT_SPELLCAST_FAILED"]		= true,
	["UNIT_SPELLCAST_FAILED_QUIET"]	= true,
	["UNIT_SPELLCAST_INTERRUPTED"]	= true,
	["INCOMING_RESURRECT_CHANGED"]	= true,
	["UNIT_HEALTH"]					= true,
}

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, ...)
	self[event](self, event, ...)
end)

for k in pairs(events) do
	frame:RegisterEvent(k)
end

-- These events result in the same state changes, so we can handle them with the same function
lib.UNIT_SPELLCAST_FAILED			= lib.UNIT_SPELLCAST_STOP
lib.UNIT_SPELLCAST_FAILED_QUIET		= lib.UNIT_SPELLCAST_STOP
lib.UNIT_SPELLCAST_INTERRUPTED		= lib.UNIT_SPELLCAST_STOP

-- -------------------------------------------------------------------
-- WoW API
-- -------------------------------------------------------------------

local UnitGUID = UnitGUID
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local UnitCastingInfo = UnitCastingInfo
local UnitNameFromGUID = UnitNameFromGUID
local GetSpellInfo = C_Spell.GetSpellInfo
local After = C_Timer.After
local GetNumGroupMembers = GetNumGroupMembers

-- -------------------------------------------------------------------
-- Internal state
-- -------------------------------------------------------------------

-- Resurrection state by caster GUID
local resCastersInfo = {}

-- Resurrection state by target GUID
local resTargetsInfo = {}

local massResTargets = {}
local callbackPending
local massResScanPending

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

	-- Engineering
	[8342]		= true,		-- Goblin Jumper Cables
	[22999]		= true,		-- Goblin Jumper Cables XL
	[54732]		= true,		-- Gnomish Army Knife
	[164729]	= true,		-- Ultimate Gnomish Army Knife

	-- Combat res
	[20484]		= true,		-- Rebirth
	[61999]		= true,		-- Raise Ally
	[20707]		= true,		-- Soulstone Resurrection

	-- World / Object
	[199119]	= true,		-- Failure Detection Aura (this is a res aura, and will be moved out of this table later)
	[187777]	= true,		-- Reawaken (Brazier of Awakening)
}

local MASS_RES_SPELLS = {
	-- Priest
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
local PLAYER_GUID = UnitGUID("player")

-- -------------------------------------------------------------------
-- Helper functions
-- -------------------------------------------------------------------

local function FireResCastStarted()
	callbackPending = nil
	lib.callbacks:Fire("ResCast_Started", resCastersInfo, resTargetsInfo)
end

local function QueueResCastStarted()
	if callbackPending then return end
	callbackPending = true
	After(0, FireResCastStarted)
end

local function ScanMassResTargets(casterGUID, casterInfo)
	massResScanPending = nil
	local groupType = IsInRaid() and "raid" or "party"

	for i = 1, GetNumGroupMembers() do
		local UnitID = groupType .. i

		if UnitIsDeadOrGhost(UnitID) and UnitHasIncomingResurrection(UnitID) then
			local targetGUID = UnitGUID(UnitID)

			if targetGUID and not resTargetsInfo[targetGUID] and not massResTargets[casterGUID][targetGUID] then
				massResTargets[casterGUID][targetGUID] = true

				resTargetsInfo[targetGUID] = {
					castTime = casterInfo.castTime,
					casterGUID = casterGUID,
				}
			end
		end
	end

	QueueResCastStarted()
end

-- -------------------------------------------------------------------
-- Event handlers
-- -------------------------------------------------------------------

-- A resurrection spellcast has started. We don't know the target yet, so we just record the caster's intent.
function lib:UNIT_SPELLCAST_START(_, unitID, _, spellID)
	local casterGUID = UnitGUID(unitID)
	-- We recorded this caster, exit early to avoid duplicate tracking for the same active resurrection cast.
	if resCastersInfo[casterGUID] then return end
	-- Only track if it's a resurrection spell.
	if not SINGLE_TARGET_RES_SPELLS[spellID] and not MASS_RES_SPELLS[spellID] then return end
	-- Can't track without a GUID, exit early.
	if not casterGUID then return end

	local _, textureID, startTime, endTime, castTime, unitName, unitRealm
	_, _, textureID, startTime, endTime = UnitCastingInfo(unitID)
	if startTime and endTime then
		castTime = (endTime - startTime) / 1000
	end
	local spellInfo = GetSpellInfo(spellID)

	resCastersInfo[casterGUID] = {
		spellID = spellID or (spellInfo and spellInfo.spellID),
		textureID = textureID or (spellInfo and spellInfo.iconID),
		castTime = castTime or (spellInfo and spellInfo.castTime and (spellInfo.castTime / 1000)),
	}

	if MASS_RES_SPELLS[spellID] then
		massResTargets[casterGUID] = {}
	end

	-- Get the caster's name for RESURRECT_REQUEST, which only passes in the caster's name and not GUID.
	unitName, unitRealm = UnitNameFromGUID(casterGUID)

	if unitName and unitRealm then
		resCastersInfo[casterGUID].casterName = unitName .. "-" .. unitRealm
		if MASS_RES_SPELLS[spellID] then
			massResTargets[casterGUID].casterName = resCastersInfo[casterGUID].casterName
		end
	elseif unitName and not unitRealm then
		resCastersInfo[casterGUID].casterName = unitName
		if MASS_RES_SPELLS[spellID] then
			massResTargets[casterGUID].casterName = resCastersInfo[casterGUID].casterName
		end
	end
end

-- A targetID has an incoming resurrection. Verify the targetID is being tracked
function lib:INCOMING_RESURRECT_CHANGED(_, targetID)
	if not UnitHasIncomingResurrection(targetID) then return end

	local targetGUID = UnitGUID(targetID)
	if not targetGUID then return end
	if resTargetsInfo[targetGUID] then return end

	for casterGUID, casterInfo in pairs(resCastersInfo) do
		if SINGLE_TARGET_RES_SPELLS[casterInfo.spellID] and not casterInfo.targetGUID then
			casterInfo.targetGUID = targetGUID

			resTargetsInfo[targetGUID] = {
				castTime = casterInfo.castTime,
				casterGUID = casterGUID,
			}

			QueueResCastStarted()
			return
		elseif MASS_RES_SPELLS[casterInfo.spellID] and massResTargets[casterGUID] then
			if massResScanPending then return end
			massResScanPending = true
			After(0, function()
				ScanMassResTargets(casterGUID, casterInfo)
			end)
			return
		end
	end
end

-- -------------------------------------------------------------------
-- Embed mixins into target addon objects
-- -------------------------------------------------------------------

local mixins = {"ResCast_Started", }

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