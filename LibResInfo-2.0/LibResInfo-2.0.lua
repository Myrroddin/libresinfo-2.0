--[[--------------------------------------------------------------------
LibResInfo-2.0

CLEU-free resurrection tracking library.

Design philosophy:
- Use GUIDs, never unitIDs, for identity
- Use spellIDs, never names, for logic
- Infer caster → target (no direct API exists)
- Model uncertainty explicitly (confidence levels)
- Keep API safe (never expose internal tables)

----------------------------------------------------------------------]]

local MAJOR, MINOR = "LibResInfo-2.0", 1
assert(LibStub, MAJOR .. " requires LibStub")
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local CallbackHandler = LibStub("CallbackHandler-1.0")

-- Callback registry
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
-- Internal state (PRIVATE)
-- -------------------------------------------------------------------

-- Tracks all resurrection attempts per target
-- Multiple casters can target the same unit
local ResByTarget = {}

-- Tracks active casts before we know their target
-- We match these later using timing heuristics
local ActiveCasters = {}

-- Best-effort GUID → unit mapping (not authoritative)
local UnitFromGUID = {}

-- -------------------------------------------------------------------
-- Resurrection spell registry
-- -------------------------------------------------------------------
-- NOTE:
-- This table defines all resurrection-capable spells the library recognizes.
-- Keep this updated as expansions add/remove/modify resurrection mechanics.
-- Use Wowhead or in-game testing to verify missing entries.

local RES_SPELLS = {
    -- Priest
    [2006]   = true, -- Resurrection

    -- Paladin
    [7328]   = true, -- Redemption

    -- Shaman
    [2008]   = true, -- Ancestral Spirit

    -- Druid
    [50769]  = true, -- Revive
    [115178] = true, -- Resuscitate

    -- Hunter
    [982]    = true, -- Revive Pet

    -- Engineering
    [8342]   = true, -- Goblin Jumper Cables
    [22999]  = true, -- Goblin Jumper Cables XL
    [54732]  = true, -- Gnomish Army Knife
    [164729] = true, -- Ultimate Gnomish Army Knife
}

local RES_PENDING_TIMEOUT = 60

-- -------------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------------

-- Defensive copy (never expose internal tables)
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

-- Extract casting info (normalized)
local function GetUnitCastInfo(unit)
    local _, _, _, startTime, endTime, _, _, _, spellID = UnitCastingInfo(unit)

    if startTime and endTime then
        return spellID, startTime / 1000, endTime / 1000
    end

    return spellID, nil, nil
end

-- Resolve spell textures
-- Blizzard gives:
--   iconID = current (possibly modified)
--   originalIconID = base (if available)
local function GetSpellTextures(spellID)
    if not spellID or not C_Spell or not C_Spell.GetSpellInfo then
        return nil, nil
    end

    local info = C_Spell.GetSpellInfo(spellID)
    if not info then return nil, nil end

    local icon = info.iconID
    local base = info.originalIconID

    -- If spell is modified (talent/glyph/etc)
    if base and icon ~= base then
        return base, icon
    end

    return icon, nil
end

-- -------------------------------------------------------------------
-- Fastest res calculation
-- -------------------------------------------------------------------

-- Determines which caster's res lands first.
-- IMPORTANT:
--   - We only compare known castEndTimes
--   - Unknown times are ignored if known ones exist
--   - If none are known → first seen wins
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

    -- Fallback when no timing info exists
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

-- Fire callbacks safely
local function Fire(event, data)
    lib.callbacks:Fire(event, CopyResInfo(data))
end

-- -------------------------------------------------------------------
-- State machine
-- -------------------------------------------------------------------

-- Centralized state transition handler
-- This is where all res data is normalized and emitted
local function SetResState(targetGUID, newState, data)
    local entry = ResByTarget[targetGUID]

    if not entry then
        entry = { casters = {}, fastestCasterGUID = nil }
        ResByTarget[targetGUID] = entry
    end

    -- Normalize caster identity
    -- Always string (GUID) OR false (unknown)
    local casterGUID = data.casterGUID or false
    data.casterGUID = casterGUID

    -- Resolve textures once (not per API call)
    local baseTexture, overrideTexture = GetSpellTextures(data.spellID)
    data.baseTexture = baseTexture
    data.overrideTexture = overrideTexture

    local existing = entry.casters[casterGUID]

    -- Avoid duplicate state spam
    if not existing or existing.state ~= newState then
        entry.casters[casterGUID] = data

        UpdateFastestCaster(targetGUID)

        if newState == "CASTING" then
            Fire("LRI2_ResStarted", data)

        elseif newState == "PENDING" then
            Fire("LRI2_ResPending", data)

        elseif newState == "SUCCESS" then
            Fire("LRI2_ResSuccess", data)

        elseif newState == "EXPIRED" then
            Fire("LRI2_ResExpired", data)
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

-- Detect res cast start (no target yet)
function frame:UNIT_SPELLCAST_START(event, unit)
    local spellID, startTime, endTime = GetUnitCastInfo(unit)
    if not spellID or not RES_SPELLS[spellID] then return end

    local casterGUID = UnitGUID(unit)
    if not casterGUID then return end

    -- Store until we can match to a target
    ActiveCasters[casterGUID] = {
        spellID = spellID,
        castStartTime = startTime,
        castEndTime = endTime,
    }
end

-- Detect target receiving res
function frame:INCOMING_RESURRECT_CHANGED(event, unit)
    if not UnitHasIncomingResurrection(unit) then return end

    local targetGUID = UnitGUID(unit)
    if not targetGUID then return end

    UnitFromGUID[targetGUID] = unit

    local casterGUID, castData

    -- WTH zone:
    -- We must infer caster → target mapping.
    -- There is NO direct API for this.
    for candidateCasterGUID, data in pairs(ActiveCasters) do
        if not data.targetGUID and data.castEndTime then
            casterGUID = candidateCasterGUID
            castData = data
            break
        end
    end

    if castData then
        castData.targetGUID = targetGUID
        ActiveCasters[casterGUID] = nil
    end

    -- CASTING = inferred
    SetResState(targetGUID, "CASTING", {
        state = "CASTING",
        targetGUID = targetGUID,
        casterGUID = casterGUID,
        spellID = castData and castData.spellID or nil,
        castStartTime = castData and castData.castStartTime or nil,
        castEndTime = castData and castData.castEndTime or nil,
        confidence = "MEDIUM",
    })

    -- PENDING = confirmed
    SetResState(targetGUID, "PENDING", {
        state = "PENDING",
        targetGUID = targetGUID,
        casterGUID = casterGUID,
        spellID = castData and castData.spellID or nil,
        expiresAt = GetTime() + RES_PENDING_TIMEOUT,
        confidence = "HIGH",
    })
end

-- Player-only fallback
function frame:RESURRECT_REQUEST()
    local guid = UnitGUID("player")
    if not guid then return end

    -- No caster or timing info available
    SetResState(guid, "PENDING", {
        state = "PENDING",
        targetGUID = guid,
        casterGUID = false,
        expiresAt = GetTime() + RES_PENDING_TIMEOUT,
        confidence = "HIGH",
    })
end

-- Detect successful res (dead → alive)
function frame:UNIT_FLAGS(event, unit)
    local guid = UnitGUID(unit)
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
    end
end

-- -------------------------------------------------------------------
-- Expiration (gated, efficient)
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
                SetResState(guid, "EXPIRED", data)
                entry.casters[casterGUID] = nil
            end
        end

        if not next(entry.casters) then
            ResByTarget[guid] = nil
        else
            UpdateFastestCaster(guid)
        end
    end
end

-- -------------------------------------------------------------------
-- Events
-- -------------------------------------------------------------------

frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("INCOMING_RESURRECT_CHANGED")
frame:RegisterEvent("RESURRECT_REQUEST")
frame:RegisterEvent("UNIT_FLAGS")

-- -------------------------------------------------------------------
-- API
-- -------------------------------------------------------------------

lib.API = {}

-- Returns fastest res for unit
function lib.API:GetIncomingResInfo(unit)
    local guid = UnitGUID(unit)
    if not guid then return end

    local entry = ResByTarget[guid]
    if not entry then return end

    local fastest = entry.fastestCasterGUID
    if not fastest then return end

    return CopyResInfo(entry.casters[fastest])
end

function lib.API:UnitHasIncomingRes(unit)
    return self:GetIncomingResInfo(unit) ~= nil
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