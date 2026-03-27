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
    "RegisterCallback",
    "UnregisterCallback",
    "UnregisterAllCallbacks"
)

-- -------------------------------------------------------------------
-- WoW API
-- -------------------------------------------------------------------

local UnitGUID = UnitGUID
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local UnitCastingInfo = UnitCastingInfo
local GetTime = GetTime
local CreateFrame = CreateFrame

-- -------------------------------------------------------------------
-- Internal state
-- -------------------------------------------------------------------

-- GUID → last known valid unitID (validation only)
local UnitFromGUID = {}

-- Resurrection state by target GUID
local ResByTarget = {}

-- Active cast tracking (pre-target association)
local ActiveCasters = {}

-- -------------------------------------------------------------------
-- Unit tracking / validation
-- -------------------------------------------------------------------

local function TrackUnit(unit)
    if not unit then return end

    local guid = UnitGUID(unit)
    if not guid then return end

    local existing = UnitFromGUID[guid]

    -- Update mapping only if missing or stale
    if not existing or UnitGUID(existing) ~= guid then
        UnitFromGUID[guid] = unit
    end

    return guid
end

local function ResolveUnit(guid)
    local unit = UnitFromGUID[guid]

    if unit and UnitGUID(unit) == guid then
        return unit
    end
end

local function ClearUnitMapping(guid)
    UnitFromGUID[guid] = nil
end

-- -------------------------------------------------------------------
-- Spell registry
-- -------------------------------------------------------------------

local RES_SPELLS = {
    -- Priest
    [2006]   = true, -- Resurrection

    -- Paladin
    [7328]   = true, -- Redemption

    -- Shaman
    [2008]   = true, -- Ancestral Spirit

    -- Druid
    [50769]  = true, -- Revive

    -- Monk
    [115178] = true, -- Resuscitate

    -- Hunter
    [982]    = true, -- Revive Pet

    -- Engineering
    [8342]   = true, -- Goblin Jumper Cables
    [22999]  = true, -- Goblin Jumper Cables XL
    [54732]  = true, -- Gnomish Army Knife
    [164729] = true, -- Ultimate Gnomish Army Knife

    -- World / Object
    [199119] = true, -- Failure Detection Aura
    [187777] = true, -- Reawaken (Brazier)

    -- Combat res
    [20484]  = true, -- Rebirth
    [61999]  = true, -- Raise Ally
    [20707]  = true, -- Soulstone Resurrection

    -- Mass res
    [212056] = true, -- Absolution
    [212048] = true, -- Ancestral Vision
    [212036] = true, -- Mass Resurrection
    [212051] = true, -- Reawaken (Monk)
    [212040] = true, -- Revitalize
}

local RES_PENDING_TIMEOUT = 60

-- -------------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------------

local function ResolveGUID(input)
    if not input then return end

    local guid = UnitGUID(input)
    if guid then return guid end

    if type(input) == "string" then
        return input
    end
end

local function CopyResInfo(src)
    if not src then return end

    return {
        state = src.state,
        targetGUID = src.targetGUID,
        casterGUID = src.casterGUID,
        spellID = src.spellID,
        castStartTime = src.castStartTime,
        castEndTime = src.castEndTime,
        expiresAt = src.expiresAt,
        confidence = src.confidence,
        isFastest = src.isFastest,
        baseTexture = src.baseTexture,
        overrideTexture = src.overrideTexture,
    }
end

local function GetUnitCastInfo(unit)
    local _, _, _, startTime, endTime, _, _, _, spellID = UnitCastingInfo(unit)

    if startTime and endTime then
        return spellID, startTime / 1000, endTime / 1000
    end

    return spellID, nil, nil
end

local function GetSpellTextures(spellID)
    if not spellID or not C_Spell then return end

    local info = C_Spell.GetSpellInfo(spellID)
    if not info then return end

    local icon = info.iconID
    local base = info.originalIconID

    if base and icon ~= base then
        return base, icon
    end

    return icon, nil
end

-- -------------------------------------------------------------------
-- Fastest calculation
-- -------------------------------------------------------------------

local function UpdateFastestCaster(targetGUID)
    local entry = ResByTarget[targetGUID]
    if not entry then return end

    local fastestTime
    local fastestCasterGUID
    local foundKnownTime = false

    for casterGUID, info in pairs(entry.casters) do
        local t = info.castEndTime

        if t then
            foundKnownTime = true
            if not fastestTime or t < fastestTime then
                fastestTime = t
                fastestCasterGUID = casterGUID
            end
        end
    end

    if not foundKnownTime then
        for casterGUID in pairs(entry.casters) do
            fastestCasterGUID = casterGUID
            break
        end
    end

    entry.fastestCasterGUID = fastestCasterGUID

    for casterGUID, info in pairs(entry.casters) do
        info.isFastest = (casterGUID == fastestCasterGUID)
    end
end

local function Fire(event, data)
    lib.callbacks:Fire(event, CopyResInfo(data))
end

-- -------------------------------------------------------------------
-- State machine
-- -------------------------------------------------------------------

local function SetResState(targetGUID, newState, data)
    local entry = ResByTarget[targetGUID]

    if not entry then
        entry = { casters = {}, fastestCasterGUID = nil }
        ResByTarget[targetGUID] = entry
    end

    local casterGUID = data.casterGUID or false
    data.casterGUID = casterGUID

    local baseTexture, overrideTexture = GetSpellTextures(data.spellID)
    data.baseTexture = baseTexture
    data.overrideTexture = overrideTexture

    local existing = entry.casters[casterGUID]

    if not existing or existing.state ~= newState then
        entry.casters[casterGUID] = data

        UpdateFastestCaster(targetGUID)

        if newState == "CASTING" then
            Fire("LRI2_UnitResStarted", data)
        elseif newState == "PENDING" then
            Fire("LRI2_UnitResPending", data)
        elseif newState == "SUCCESS" then
            Fire("LRI2_UnitResSuccess", data)
        elseif newState == "EXPIRED" then
            Fire("LRI2_UnitResExpired", data)
        end
    end
end

-- -------------------------------------------------------------------
-- Events
-- -------------------------------------------------------------------

local frame = CreateFrame("Frame")

frame:SetScript("OnEvent", function(self, event, ...)
    if self[event] then
        self[event](self, event, ...)
    end
end)

function frame:UNIT_SPELLCAST_START(event, unit)
    local casterGUID = TrackUnit(unit)
    if not casterGUID then return end

    local spellID, startTime, endTime = GetUnitCastInfo(unit)
    if not spellID or not RES_SPELLS[spellID] then return end

    ActiveCasters[casterGUID] = {
        spellID = spellID,
        castStartTime = startTime,
        castEndTime = endTime,
    }
end

function frame:UNIT_SPELLCAST_SUCCEEDED(event, unit, _, spellID)
    local casterGUID = TrackUnit(unit)
    if not casterGUID then return end

    if not spellID or not RES_SPELLS[spellID] then return end

    local now = GetTime()

    ActiveCasters[casterGUID] = {
        spellID = spellID,
        castStartTime = now,
        castEndTime = now,
    }
end

local function ClearActiveCaster(unit)
    local casterGUID = TrackUnit(unit)
    if not casterGUID then return end

    local data = ActiveCasters[casterGUID]

    if data and not data.targetGUID then
        ActiveCasters[casterGUID] = nil
    end
end

function frame:UNIT_SPELLCAST_INTERRUPTED(event, unit)
    ClearActiveCaster(unit)
end

function frame:UNIT_SPELLCAST_FAILED(event, unit)
    ClearActiveCaster(unit)
end

function frame:UNIT_SPELLCAST_STOP(event, unit)
    ClearActiveCaster(unit)
end

function frame:INCOMING_RESURRECT_CHANGED(event, unit)
    local targetGUID = TrackUnit(unit)
    if not targetGUID then return end

    if not UnitHasIncomingResurrection(unit) then return end

    local casterGUID, castData

    for candidateCasterGUID, data in pairs(ActiveCasters) do
        if not data.targetGUID then
            casterGUID = candidateCasterGUID
            castData = data
            break
        end
    end

    if castData then
        castData.targetGUID = targetGUID
        ActiveCasters[casterGUID] = nil
    end

    SetResState(targetGUID, "CASTING", {
        state = "CASTING",
        targetGUID = targetGUID,
        casterGUID = casterGUID,
        spellID = castData and castData.spellID,
        castStartTime = castData and castData.castStartTime,
        castEndTime = castData and castData.castEndTime,
        confidence = "MEDIUM",
    })

    SetResState(targetGUID, "PENDING", {
        state = "PENDING",
        targetGUID = targetGUID,
        casterGUID = casterGUID,
        spellID = castData and castData.spellID,
        expiresAt = GetTime() + RES_PENDING_TIMEOUT,
        confidence = "HIGH",
    })
end

function frame:RESURRECT_REQUEST()
    local guid = UnitGUID("player")
    if not guid then return end

    SetResState(guid, "PENDING", {
        state = "PENDING",
        targetGUID = guid,
        casterGUID = false,
        expiresAt = GetTime() + RES_PENDING_TIMEOUT,
        confidence = "HIGH",
    })
end

function frame:UNIT_FLAGS(event, unit)
    local guid = TrackUnit(unit)
    if not guid then return end

    local entry = ResByTarget[guid]
    if not entry then return end

    if not UnitIsDeadOrGhost(unit) then
        local fastest = entry.fastestCasterGUID
        local data = fastest and entry.casters[fastest]

        if data then
            SetResState(guid, "SUCCESS", data)
        end

        ResByTarget[guid] = nil
        ClearUnitMapping(guid)
    end
end

-- -------------------------------------------------------------------
-- Expiration
-- -------------------------------------------------------------------

local elapsed = 0

local function OnUpdate(self, delta)
    elapsed = elapsed + delta
    if elapsed < 0.5 then return end
    elapsed = 0

    if not next(ResByTarget) then
        self:SetScript("OnUpdate", nil)
        return
    end

    local now = GetTime()

    for guid, entry in pairs(ResByTarget) do
        for casterGUID, data in pairs(entry.casters) do
            if data.state == "PENDING" and data.expiresAt and now > data.expiresAt then
                local unit = ResolveUnit(guid)

                if unit and UnitHasIncomingResurrection(unit) then
                    data.expiresAt = now + RES_PENDING_TIMEOUT
                else
                    SetResState(guid, "EXPIRED", data)
                    entry.casters[casterGUID] = nil
                end
            end
        end

        if not next(entry.casters) then
            ResByTarget[guid] = nil
            ClearUnitMapping(guid)
        else
            UpdateFastestCaster(guid)
        end
    end
end

-- -------------------------------------------------------------------
-- Event registration
-- -------------------------------------------------------------------

frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
frame:RegisterEvent("UNIT_SPELLCAST_STOP")
frame:RegisterEvent("INCOMING_RESURRECT_CHANGED")
frame:RegisterEvent("RESURRECT_REQUEST")
frame:RegisterEvent("UNIT_FLAGS")

frame:SetScript("OnUpdate", OnUpdate)

-- -------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------

lib.API = {}

function lib.API:GetIncomingResInfo(unitOrGUID)
    local guid = ResolveGUID(unitOrGUID)
    if not guid then return end

    local entry = ResByTarget[guid]
    if not entry then return end

    local fastest = entry.fastestCasterGUID
    if not fastest then return end

    return CopyResInfo(entry.casters[fastest])
end

function lib.API:GetUnitIDFromGUID(guid)
    if not guid then return end

    local unit = UnitFromGUID[guid]

    if unit and UnitGUID(unit) == guid then
        return unit
    end
end

-- -------------------------------------------------------------------
-- Callback wrappers
-- -------------------------------------------------------------------

function lib:RegisterCallback(...)
    return self.callbacks.RegisterCallback(self, ...)
end

function lib:UnregisterCallback(...)
    return self.callbacks.UnregisterCallback(self, ...)
end

function lib:UnregisterAllCallbacks(...)
    return self.callbacks.UnregisterAllCallbacks(self, ...)
end

-- -------------------------------------------------------------------
-- API mixin (expose API on lib)
-- -------------------------------------------------------------------

for name, func in pairs(lib.API) do
    lib[name] = func
end

-- -------------------------------------------------------------------
-- Embedding support
-- -------------------------------------------------------------------
lib.mixinTargets = lib.mixinTargets or {}
-- -------------------------------------------------------------------

local mixins = {
    "GetIncomingResInfo",
    "GetUnitIDFromGUID",
    "RegisterCallback",
    "UnregisterCallback",
    "UnregisterAllCallbacks",
}

function lib:Embed(target)
    for _, name in ipairs(mixins) do
        target[name] = self[name]
    end

    self.mixinTargets[target] = true
    return target
end

-- Re-embed existing targets on upgrade
for target in pairs(lib.mixinTargets) do
    lib:Embed(target)
end