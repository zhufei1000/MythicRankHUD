local createdFrames = {}

local function Noop()
end

local function NewFrame(name)
    local frame = {
        name = name,
        events = {},
        scripts = {},
        shown = false,
    }

    function frame:RegisterEvent(event)
        self.events[event] = true
    end

    function frame:UnregisterEvent(event)
        self.events[event] = nil
    end

    function frame:SetScript(scriptType, callback)
        self.scripts[scriptType] = callback
    end

    function frame:IsShown()
        return self.shown
    end

    function frame:Show()
        self.shown = true
    end

    function frame:Hide()
        self.shown = false
    end

    return setmetatable(frame, {
        __index = function()
            return Noop
        end,
    })
end

UIParent = NewFrame("UIParent")
GameTooltip = setmetatable({ Hide = Noop }, { __index = function() return Noop end })

function CreateFrame(_, name)
    local frame = NewFrame(name)
    createdFrames[#createdFrames + 1] = frame
    return frame
end

function UnitGUID()
    return "Player-1-00000001"
end

function UnitFullName()
    return "Tester", "TestRealm"
end

function GetRealmName()
    return "TestRealm"
end

function GetLocale()
    return "zhCN"
end

function UnitClass()
    return "Warrior", "WARRIOR"
end

function GetServerTime()
    return 1788134400
end

function InCombatLockdown()
    return false
end

CUSTOM_CLASS_COLORS = nil
RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
}

C_Timer = {
    After = function(_, callback)
        callback()
    end,
}

QFXMythicRankHUDGlobalDB = nil
QFXMythicRankHUDDB = nil
QFXMythicRankData = {
    GetMetadata = function()
        return {
            dataVersion = "202608311407",
            packageVersion = "202609010404",
        }
    end,
    GetCutoff = function(_, _, key)
        local values = {
            p999 = 4100,
            p990 = 3900,
            p900 = 3500,
            p750 = 3100,
            p600 = 2800,
        }
        return {
            score = values[key],
            rank = 1,
            color = "ffffff",
        }
    end,
    GetPlayerScore = function()
        return nil
    end,
    EstimateRank = function()
        return nil
    end,
    RegisterCallback = Noop,
}

local L = setmetatable({
    ADDON_TITLE = "Test",
    SCORE = "M+ Score",
    NO_SCORE = "No score",
    TODAY_SCORE = "Today",
    CUTOFF_01 = "Top 0.1%",
    CUTOFF_1 = "Top 1%",
    SETTINGS_ROW_REGION_RANK = "Rank",
    SURPASSED = "Surpassed",
    TODAY_RANK = "Today rank",
    SMART_NEXT_TARGET = "Next",
    RANK_RANGE = "Range",
    PERCENTILE_RANGE = "Percentile",
    UNAVAILABLE = "Unavailable",
    REGION_RANK_FORMAT = "%s Rank",
    DATA_DATE_FORMAT = "%04d-%02d-%02d",
    DATA_UPDATED = "Updated: %s",
    DATA_TIME_FORMAT = "%02d-%02d %02d:%02d UTC",
    DETAIL_COLUMN_NAME = "Dungeon",
    VAULT_RAID = "Raid",
}, {
    __index = function(_, key)
        return key
    end,
})

local namespace = {
    L = L,
    Util = {
        ClampNumber = function(value, minimum, maximum, fallback)
            value = tonumber(value) or fallback
            return math.max(minimum, math.min(maximum, value))
        end,
        SafeNumber = tonumber,
        SafeTable = function(value)
            return type(value) == "table" and value or nil
        end,
        SafeString = function(value, fallback)
            return type(value) == "string" and value or fallback
        end,
        GetPlayerScoreColor = function()
            return 1, 1, 1
        end,
        EstimateRankBelowTop40 = function()
            return nil
        end,
        HexColorToRGB = function()
            return 1, 1, 1
        end,
    },
    RankTarget = {
        CUTOFF_DEFS = {
            { key = "p999", percent = 0.1 },
            { key = "p990", percent = 1 },
            { key = "p900", percent = 10 },
            { key = "p750", percent = 25 },
            { key = "p600", percent = 40 },
        },
        Resolve = function()
            return nil
        end,
    },
    ResolveSelectedRegion = function()
        return "cn"
    end,
    GetSelectedRegion = function()
        return "cn"
    end,
    GetSelectedRegionLabel = function()
        return "CN"
    end,
}

local modulePath = arg and arg[1] or "Core.lua"
local addonName = arg and arg[2] or "MythicRankHUD"
local chunk = assert(loadfile(modulePath))
chunk(addonName, namespace)

local eventFrame
for _, frame in ipairs(createdFrames) do
    if frame.events.ADDON_LOADED then
        eventFrame = frame
        break
    end
end

assert(eventFrame, "Core event frame was not created")
eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", addonName)

assert(namespace.GetDB().announceTeleport == true, "teleport announcements are not enabled by default")
namespace.SetTeleportAnnouncementEnabled(false)
assert(namespace.IsTeleportAnnouncementEnabled() == false, "teleport announcement setting did not disable")
namespace.SetTeleportAnnouncementEnabled(true)

local frameCountBeforeSnapshot = #createdFrames
local snapshot = namespace.GetHUDSnapshot(true)

assert(type(snapshot) == "table", "snapshot refresh did not return a table")
assert(type(snapshot.score) == "table", "snapshot refresh did not produce score metadata")
assert(
    snapshot.dataUpdated.value == "Updated: 08-31 14:07 UTC",
    "snapshot did not show only the source update timestamp"
)
assert(#createdFrames == frameCountBeforeSnapshot, "snapshot refresh created a UI frame")

for _, frame in ipairs(createdFrames) do
    assert(frame.name ~= "QFXMythicRankHUDGlobalFrame", "retired standalone HUD frame was created")
end

print("CoreSnapshot_test: OK")
