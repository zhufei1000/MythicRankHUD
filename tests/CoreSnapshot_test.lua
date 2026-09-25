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

QFXMythicRankHUDGlobalDB = {
    encounters = {
        ["GUID-MIGRATE"] = { score = 1234, count = 2, lastSeen = 111 },
    },
}
QFXMythicRankHUDDB = nil
QFXMythicRankHUDGlobalCharDB = nil
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
    TOP_EXACT_RANK_VALUE = "leaderboard #%s",
    TOP_TIED_RANK_VALUE = "tied #%s",
    APPROX_RANK_WITH_MARGIN = "~#%s (±%s)",
    RANGE_JOIN = "%s-%s",
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

-- Encounter history moved from the account database to a per-character one.
assert(type(QFXMythicRankHUDGlobalCharDB) == "table", "per-character database was not created")
assert(QFXMythicRankHUDGlobalCharDB.encounters["GUID-MIGRATE"] ~= nil,
    "account-level encounters were not migrated")
assert(QFXMythicRankHUDGlobalDB.encounters == nil, "account encounter table was not cleared")
assert(namespace.GetCharacterDB() == QFXMythicRankHUDGlobalCharDB,
    "GetCharacterDB did not return the per-character database")
assert(namespace.GetCharacterKey() == "Player-1-00000001",
    "announcer character key did not resolve to the player's GUID")

assert(namespace.GetDB().announceTeleport == false, "teleport announcements are not disabled by default")
namespace.SetTeleportAnnouncementEnabled(true)
assert(namespace.IsTeleportAnnouncementEnabled() == true, "teleport announcement setting did not enable")
namespace.SetTeleportAnnouncementEnabled(false)

local frameCountBeforeSnapshot = #createdFrames
local snapshot = namespace.GetHUDSnapshot(true)

assert(type(snapshot) == "table", "snapshot refresh did not return a table")
assert(type(snapshot.score) == "table", "snapshot refresh did not produce score metadata")
assert(
    snapshot.dataUpdated.value == "Updated: 08-31 14:07 UTC",
    "snapshot did not show only the source update timestamp"
)
assert(#createdFrames == frameCountBeforeSnapshot, "snapshot refresh created a UI frame")

QFXMythicRankData.GetPlayerScore = function() return 4453 end
QFXMythicRankData.EstimateRank = function()
    return {
        bracket = "p999", estimatedRank = 5, rankMin = 5, rankMax = 20,
        isRoundedLeaderboardRank = true, isRoundedTie = true,
    }
end
local topSnapshot = namespace.GetHUDSnapshot(true)
assert(topSnapshot.rank.value == "tied #5", "rounded leaderboard tie was not displayed")
assert(topSnapshot.rankRange.value == "5-20", "rounded leaderboard tie range was not displayed")

QFXMythicRankData.EstimatePlayerRank = function()
    return {
        bracket = "p999", estimatedRank = 8, rankMin = 8, rankMax = 8,
        isExactLeaderboardRank = true,
    }
end
local exactSnapshot = namespace.GetHUDSnapshot(true)
assert(exactSnapshot.rank.value == "leaderboard #8", "Top 100 identity rank was not displayed")
assert(exactSnapshot.rankRange.value == "8", "Top 100 rank range was not exact")

QFXMythicRankData.GetPlayerScore = function() return 3900 end
QFXMythicRankData.EstimatePlayerRank = function()
    return {
        bracket = "p999-p990", estimatedRank = 80, rankMin = 80, rankMax = 80,
        isExactLeaderboardRank = true,
    }
end
local outsideTop01Snapshot = namespace.GetHUDSnapshot(true)
assert(outsideTop01Snapshot.rank.value == "leaderboard #80",
    "Top 100 identity rank outside the Top 0.1% was not displayed")

QFXMythicRankData.GetPlayerScore = function() return 3500 end
QFXMythicRankData.EstimatePlayerRank = nil
QFXMythicRankData.EstimateRank = function()
    return {
        bracket = "p999-p990", estimatedRank = 1051,
        rankMin = 1001, rankMax = 1100, rankUncertainty = 50,
        isRoundedLeaderboardRank = true, isRoundedTie = true,
    }
end
local groupedSnapshot = namespace.GetHUDSnapshot(true)
assert(groupedSnapshot.rank.value == "~#1051 (±50)",
    "rounded score group did not show its middle rank and uncertainty")
assert(groupedSnapshot.rankRange.value == "1001-1100",
    "rounded score group did not retain its full rank range")

for _, frame in ipairs(createdFrames) do
    assert(frame.name ~= "QFXMythicRankHUDGlobalFrame", "retired standalone HUD frame was created")
end

print("CoreSnapshot_test: OK")
