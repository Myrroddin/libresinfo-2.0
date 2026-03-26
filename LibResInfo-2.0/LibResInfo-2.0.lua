--[[--------------------------------------------------------------------
LibResInfo-2.0

Modern resurrection tracking library (CLEU-free, inference-based)

Design goals:
- Track resurrection state by GUID (unitIDs are observational only)
- Work across Retail, Classic variants, and hybrid clients
- Avoid COMBAT_LOG_EVENT_UNFILTERED entirely
- Provide embedded API via LibStub
- Provide lifecycle-safe callbacks via CallbackHandler-1.0
- Use table-based API returns and callback payloads
- Never expose internal tables (defensive copying)

Core model:
- Detect cast start (low confidence)
- Match target via INCOMING_RESURRECT_CHANGED (medium confidence)
- Confirm pending via API (high confidence)
- Detect success via dead -> alive transition

----------------------------------------------------------------------]]

local MAJOR, MINOR = "LibResInfo-2.0", 1
assert(LibStub, MAJOR .. " requires LibStub")
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local CallbackHandler = LibStub("CallbackHandler-1.0")

-- Explicit callback API
lib.callbacks = lib.callbacks or CallbackHandler:New(lib,
    "RegisterCallback",
    "UnregisterCallback",
    "UnregisterAllCallbacks"
)

-- -------------------------------------------------------------------
-- Lua upvalues
-- -------------------------------------------------------------------

local pairs = pairs

-- -------------------------------------------------------------------
-- WoW API upvalues
-- -------------------------------------------------------------------

local UnitGUID = UnitGUID
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local GetTime = GetTime
local CreateFrame = CreateFrame

-- -------------------------------------------------------------------
-- Internal state (PRIVATE)
-- -------------------------------------------------------------------

local ResByTarget = {}
local ActiveCasters = {}
local UnitFromGUID = {}

-- -------------------------------------------------------------------
-- Resurrection spell registry
-- -------------------------------------------------------------------

local RES_SPELLS = {
    [2008] = true,
    [7328] = true,
    [2006] = true,
    [50769] = true,
    [115178] = true,
    [982] = true,

    [8342] = true,
    [22999] = true,
    [54732] = true,
    [164729] = true,
}

-- -------------------------------------------------------------------
-- Constants
-- -------------------------------------------------------------------

local RES_PENDING_TIMEOUT = 60

-- -------------------------------------------------------------------
-- Copy helper (EXPLICIT SCHEMA)
-- -------------------------------------------------------------------

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
    }
end

-- -------------------------------------------------------------------
-- Casting info helper
-- -------------------------------------------------------------------

local function GetUnitCastInfo(unit)
    local _, _, _, startTime, endTime, _, _, spellID = UnitCastingInfo(unit)

    if not spellID then
        _, _, _, startTime, endTime, _, spellID = UnitChannelInfo(unit)
    end

    if startTime and endTime then
        return spellID, startTime / 1000, endTime / 1000
    end

    return spellID, nil, nil
end

-- -------------------------------------------------------------------
-- Callback firing (SAFE COPY)
-- -------------------------------------------------------------------

local function Fire(event, data)
    lib.callbacks:Fire(event, CopyResInfo(data))
end

-- -------------------------------------------------------------------
-- State transition handler
-- -------------------------------------------------------------------

local function SetResState(guid, newState, data)
    local current = ResByTarget[guid]

    if not current or current.state ~= newState then
        ResByTarget[guid] = data

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
-- Event frame
-- -------------------------------------------------------------------

local frame = CreateFrame("Frame")

frame:SetScript("OnEvent", function(self, event, ...)
    if self[event] then
        self[event](self, event, ...)
    end
end)

-- -------------------------------------------------------------------
-- UNIT_SPELLCAST_START
-- -------------------------------------------------------------------

function frame:UNIT_SPELLCAST_START(event, unit)
    local spellID, startTime, endTime = GetUnitCastInfo(unit)
    if not spellID or not RES_SPELLS[spellID] then return end

    local casterGUID = UnitGUID(unit)
    if not casterGUID then return end

    ActiveCasters[casterGUID] = {
        spellID = spellID,
        castStartTime = startTime,
        castEndTime = endTime,
    }
end

-- -------------------------------------------------------------------
-- INCOMING_RESURRECT_CHANGED
-- -------------------------------------------------------------------

function frame:INCOMING_RESURRECT_CHANGED(event, unit)
    if not UnitHasIncomingResurrection or not UnitHasIncomingResurrection(unit) then return end

    local targetGUID = UnitGUID(unit)
    if not targetGUID then return end

    UnitFromGUID[targetGUID] = unit

    local casterGUID, castData

    for cg, data in pairs(ActiveCasters) do
        if not data.targetGUID then
            casterGUID = cg
            castData = data
            break
        end
    end

    if castData then
        castData.targetGUID = targetGUID
    end

    SetResState(targetGUID, "CASTING", {
        state = "CASTING",
        targetGUID = targetGUID,
        casterGUID = casterGUID,
        spellID = castData and castData.spellID or nil,
        castStartTime = castData and castData.castStartTime or nil,
        castEndTime = castData and castData.castEndTime or nil,
        confidence = "MEDIUM",
    })

    SetResState(targetGUID, "PENDING", {
        state = "PENDING",
        targetGUID = targetGUID,
        casterGUID = casterGUID,
        spellID = castData and castData.spellID or nil,
        expiresAt = GetTime() + RES_PENDING_TIMEOUT,
        confidence = "HIGH",
    })
end

-- -------------------------------------------------------------------
-- RESURRECT_REQUEST (player fallback)
-- -------------------------------------------------------------------

function frame:RESURRECT_REQUEST(event)
    local guid = UnitGUID("player")
    if not guid then return end

    SetResState(guid, "PENDING", {
        state = "PENDING",
        targetGUID = guid,
        casterGUID = nil,
        spellID = nil,
        expiresAt = GetTime() + RES_PENDING_TIMEOUT,
        confidence = "HIGH",
    })
end

-- -------------------------------------------------------------------
-- UNIT_FLAGS
-- -------------------------------------------------------------------

function frame:UNIT_FLAGS(event, unit)
    local guid = UnitGUID(unit)
    if not guid then return end

    UnitFromGUID[guid] = unit

    local data = ResByTarget[guid]
    if not data then return end

    if not UnitIsDeadOrGhost(unit) then
        SetResState(guid, "SUCCESS", data)
        ResByTarget[guid] = nil
    end
end

-- -------------------------------------------------------------------
-- Expiration handler
-- -------------------------------------------------------------------

local elapsed = 0
frame:SetScript("OnUpdate", function(self, delta)
    elapsed = elapsed + delta
    if elapsed < 0.5 then return end
    elapsed = 0

    local now = GetTime()

    for guid, data in pairs(ResByTarget) do
        if data.state == "PENDING" and data.expiresAt and now > data.expiresAt then
            SetResState(guid, "EXPIRED", data)
            ResByTarget[guid] = nil
        end
    end
end)

-- -------------------------------------------------------------------
-- Event registration
-- -------------------------------------------------------------------

frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("INCOMING_RESURRECT_CHANGED")
frame:RegisterEvent("RESURRECT_REQUEST")
frame:RegisterEvent("UNIT_FLAGS")

-- -------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------

lib.API = {}

function lib.API:GetIncomingResInfo(unit)
    local guid = UnitGUID(unit)
    if not guid then return end

    return CopyResInfo(ResByTarget[guid])
end

function lib.API:UnitHasIncomingRes(unit)
    return self:GetIncomingResInfo(unit) ~= nil
end

-- -------------------------------------------------------------------
-- CallbackHandler passthrough
-- -------------------------------------------------------------------

lib.RegisterCallback = lib.callbacks.RegisterCallback
lib.UnregisterCallback = lib.callbacks.UnregisterCallback
lib.UnregisterAllCallbacks = lib.callbacks.UnregisterAllCallbacks

-- -------------------------------------------------------------------
-- Embedding
-- -------------------------------------------------------------------

lib.embeds = lib.embeds or {}

local mixins = {
    "GetIncomingResInfo",
    "UnitHasIncomingRes",
    "RegisterCallback",
    "UnregisterCallback",
    "UnregisterAllCallbacks",
}

function lib:Embed(target)
    for _, name in pairs(mixins) do
        target[name] = self.API[name] or self[name]
    end

    self.embeds[target] = true
    return target
end

for target in pairs(lib.embeds) do
    lib:Embed(target)
end

-- -------------------------------------------------------------------
-- Callback documentation
-- -------------------------------------------------------------------

--[[--------------------------------------------------------------------
Callbacks (via RegisterCallback)

All callbacks receive:
    eventName, infoTable

infoTable fields:
    state
    targetGUID
    casterGUID
    spellID
    castStartTime
    castEndTime
    expiresAt
    confidence

Events:
    LRI2_ResStarted
    LRI2_ResPending
    LRI2_ResSuccess
    LRI2_ResExpired

Notes:
- infoTable is a copy (safe to read)
- Register in OnEnable
- Unregister in OnDisable
----------------------------------------------------------------------]]