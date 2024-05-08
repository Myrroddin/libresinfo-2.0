--[[
Classic Era and hardcore do not return unitIDs except for the player with UNIT_SPELLCAST_* events
Furthermore, COMBAT_LOG_EVENT_UNFILTERED is also restricted for what is availbable
Therefore, we need to build multiple versions of the library; one for each game version
The CE/HC/seasons version will use addon comms and the other versions will use events

This is the CE/HC/seasons version of the library

Date: @project-date-iso@
]]--

local isClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC

if not isClassic then
    error("This version of LibResInfo-2.0 only works for Classic", 2)
end

assert(LibStub, "LibResInfo-2.0 requires LibStub")
assert(LibStub:GetLibrary("CallbackHandler-1.0", true), "LibResInfo-2.0 requires CallbackHandler-1.0")

local version_bump = 0
--@debug@
version_bump = 1000
--@end-debug@

local MAJOR, MINOR = "LibResInfo-2.0", version_bump + 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end -- no upgrade necessary
lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)
--@debug@
local function Debug(text, ...)
    if ... then
        if type(text) == "string" and strfind(text, "%%[dfqsx%d%.]") then
            text = format(text, ...)
        else
            text = strjoin(" ", tostringall(text, ...))
        end
    else
        text = tostring(text)
    end
    ChatFrame1:AddMessage("|cff00ddbaLRI2|r " .. text)
end
--@end-debug@

-- embed APIs and callbacks into the addon which calls them
lib.mixinTargets = lib.mixinTargets or {}
local mixins = {}
function lib:Embed(target)
    for _, name in pairs(mixins) do
        target[name] = lib[name]
    end
    lib.mixinTargets[target] = true
end

-- table of spellIDs for single target res spells
local singleSpells = {}

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    lib[event](self, ...)
end)

-- eof, handle library upgrades
for target in pairs(lib.mixinTargets) do
    lib:Embed(target)
end