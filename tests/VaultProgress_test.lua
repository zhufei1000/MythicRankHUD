local function SafeTable(value)
    return type(value) == "table" and value or nil
end

local namespace = {
    L = {},
    Util = {
        SafeTable = SafeTable,
        SafeNumber = tonumber,
        SafeString = function(value)
            return type(value) == "string" and value or nil
        end,
        ClampNumber = function(value, minimum, maximum, fallback)
            value = tonumber(value) or fallback
            return math.max(minimum, math.min(maximum, value))
        end,
        WipeArray = function(value)
            for key in pairs(value) do value[key] = nil end
            return value
        end,
    },
    MythicDetailStatistics = {},
    MythicDetailResources = {},
    RankTarget = {},
}

Enum = {
    WeeklyRewardChestThresholdType = {
        Raid = 1,
        Activities = 2,
        World = 3,
    },
}

C_WeeklyRewards = {
    GetActivities = function(activityType)
        if activityType == 1 then
            return {
                { threshold = 2, progress = 6 },
                { threshold = 4, progress = 6 },
                { threshold = 6, progress = 6 },
            }
        end
        return {
            { threshold = 2, progress = 4 },
            { threshold = 4, progress = 4 },
            { threshold = 8, progress = 4 },
        }
    end,
}

local modulePath = arg and arg[1] or "MythicDetailData.lua"
local chunk = assert(loadfile(modulePath))
chunk("MythicRankHUD", namespace)

local vault = namespace.MythicDetailData.RefreshVault()
assert(vault.categories.raid.maximum == 6, "raid vault maximum was not derived from its highest threshold")
assert(vault.categories.raid.progress == 6, "raid vault progress was not preserved at six")
assert(vault.categories.mythicPlus.maximum == 8, "Mythic+ vault maximum is incorrect")
assert(vault.categories.world.maximum == 8, "world vault maximum is incorrect")

print("VaultProgress_test: OK")
