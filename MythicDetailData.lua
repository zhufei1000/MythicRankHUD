local _, ns = ...
local Util = ns.Util
local Statistics = ns.MythicDetailStatistics
local Resources = ns.MythicDetailResources
local RankTarget = ns.RankTarget
local L = ns.L

local Data = {}
ns.MythicDetailData = Data

local SafeTable = Util.SafeTable
local SafeNumber = Util.SafeNumber
local SafeString = Util.SafeString

local cache = {
    mapMeta = { valid = false, signature = nil, ordered = {}, byMapID = {}, mapIDs = {} },
    score = { valid = false, overall = nil, overallColor = nil, highestLevel = nil, maps = {} },
    seasonInfo = {
        valid = false,
        available = false,
        shortName = nil,
        name = nil,
        slug = nil,
        state = nil,
        startsAt = nil,
        endsAt = nil,
        blizzardSeasonID = nil,
        dataVersion = nil,
        dungeonByChallengeModeID = {},
    },
    ranking = { valid = false, result = { available = false } },
    cutoffHistory = {
        valid = false,
        available = false,
        maxPointCount = 0,
        order = { "p999", "p990", "p900", "p750", "p600" },
        seriesByKey = {},
    },
    seasonStats = { valid = false, available = false, byMapID = {}, summary = {} },
    weeklyStats = {
        valid = false,
        available = false,
        byMapID = {},
        summary = {},
        reportedTotal = nil,
    },
    keystone = { valid = false, data = nil },
    vault = {
        valid = false,
        categories = {
            raid = { available = false, progress = 0, maximum = 6 },
            mythicPlus = { available = false, progress = 0, maximum = 8 },
            world = { available = false, progress = 0, maximum = 8 },
        },
    },
    resources = { valid = false, ordered = {}, byKey = {} },
}

local dirty = {
    mapMeta = true,
    score = true,
    seasonInfo = true,
    ranking = true,
    cutoffHistory = true,
    seasonStats = true,
    weeklyStats = true,
    keystone = true,
    vault = true,
    resources = true,
}

local SECTION_ORDER = {
    "mapMeta",
    "score",
    "seasonInfo",
    "ranking",
    "cutoffHistory",
    "seasonStats",
    "weeklyStats",
    "keystone",
    "vault",
    "resources",
}

local VAULT_CATEGORY_DEFS = {
    { key = "raid", enumKey = "Raid", fallbackMaximum = 6 },
    { key = "mythicPlus", enumKey = "Activities", fallbackMaximum = 8 },
    { key = "world", enumKey = "World", fallbackMaximum = 8 },
}

local ACHIEVEMENT_DEFS = {
    { key = "keystoneExplorer", localizedNameKey = "ACHIEVEMENT_KEYSTONE_EXPLORER", fallbackScore = 1000 },
    { key = "keystoneConqueror", localizedNameKey = "ACHIEVEMENT_KEYSTONE_CONQUEROR", fallbackScore = 1500 },
    { key = "keystoneMaster", localizedNameKey = "ACHIEVEMENT_KEYSTONE_MASTER", fallbackScore = 2000 },
    { key = "keystoneHero", localizedNameKey = "ACHIEVEMENT_KEYSTONE_HERO", fallbackScore = 2500 },
    { key = "keystoneLegend", localizedNameKey = "ACHIEVEMENT_KEYSTONE_LEGEND", fallbackScore = 3000 },
}

local function GetOverallScore()
    if not C_ChallengeMode or type(C_ChallengeMode.GetOverallDungeonScore) ~= "function" then
        return nil
    end
    return SafeNumber(C_ChallengeMode.GetOverallDungeonScore())
end

local function GetRunHistory(includePreviousWeeks)
    if not C_MythicPlus or type(C_MythicPlus.GetRunHistory) ~= "function" then
        return nil
    end
    return SafeTable(C_MythicPlus.GetRunHistory(includePreviousWeeks, true, true))
end

local function GetWeeklyTotal()
    if not C_WeeklyRewards or type(C_WeeklyRewards.GetNumCompletedDungeonRuns) ~= "function" then
        return nil
    end
    local _, _, mythicPlusRuns = C_WeeklyRewards.GetNumCompletedDungeonRuns()
    return SafeNumber(mythicPlusRuns)
end

local function BuildAchievementTargets(API, region)
    local targets = {}
    if type(API.GetAchievementCutoff) ~= "function" then
        return targets
    end
    for _, definition in ipairs(ACHIEVEMENT_DEFS) do
        local ok, raw = pcall(API.GetAchievementCutoff, API, region, definition.key)
        if not ok or raw == nil then
            -- Older regional data packs exposed the key without a region
            -- argument; keep working with them.
            ok, raw = pcall(API.GetAchievementCutoff, API, definition.key)
        end
        local value = SafeTable(raw)
        local threshold = value and SafeNumber(value.thresholdScore or value.score)
            or SafeNumber(raw)
        if threshold then
            targets[#targets + 1] = {
                key = definition.key,
                thresholdScore = threshold,
                localizedName = L[definition.localizedNameKey],
                color = value and SafeString(value.color) or nil,
            }
        end
    end
    return targets
end

local function BuildRanking(score)
    local ranking = { available = false }
    local API = _G.QFXMythicRankData
    local region = ns.GetSelectedRegion()
    if type(API) ~= "table"
        or type(API.GetMetadata) ~= "function"
        or type(API.GetCutoff) ~= "function"
        or type(API.EstimateRank) ~= "function"
        or not score
        or not region
    then
        return ranking
    end

    local metadata = SafeTable(API:GetMetadata(region))
    local cutoffs = {}
    local cutoffByKey = {}
    for _, definition in ipairs(RankTarget.CUTOFF_DEFS) do
        local value = SafeTable(API:GetCutoff(region, definition.key, "all"))
        local target = {
            key = definition.key,
            percent = definition.percent,
            value = value,
            score = value and SafeNumber(value.score) or nil,
            color = value and SafeString(value.color) or nil,
        }
        cutoffs[#cutoffs + 1] = target
        cutoffByKey[target.key] = target
    end
    if not metadata then
        return ranking
    end
    for _, target in ipairs(cutoffs) do
        if not target.score then
            return ranking
        end
    end

    local result = SafeTable(API:EstimateRank(region, score, "all"))
    if not result then
        return ranking
    end

    ranking.available = true
    ranking.dataVersion = SafeString(metadata.dataVersion)
    ranking.population = SafeNumber(metadata.population)
    ranking.estimatedRank = SafeNumber(result.estimatedRank)
    ranking.rankMin = SafeNumber(result.rankMin)
    ranking.rankMax = SafeNumber(result.rankMax)
    ranking.percentileMin = SafeNumber(result.percentileMin)
    ranking.percentileMax = SafeNumber(result.percentileMax)
    local extendedEstimate
    if not ranking.estimatedRank then
        extendedEstimate = Util.EstimateRankBelowTop40(API, region, score, "all")
        if extendedEstimate then
            ranking.estimatedRank = SafeNumber(extendedEstimate.estimatedRank)
            ranking.rankMin = SafeNumber(extendedEstimate.rankMin) or ranking.rankMin
            ranking.rankMax = SafeNumber(extendedEstimate.rankMax) or ranking.rankMax
            ranking.percentileMin = SafeNumber(extendedEstimate.percentileMin) or ranking.percentileMin
            ranking.percentileMax = SafeNumber(extendedEstimate.percentileMax) or ranking.percentileMax
            ranking.isExtendedEstimate = true
        end
    end

    local smartCutoffs = {}
    for index = #cutoffs, 1, -1 do
        smartCutoffs[#smartCutoffs + 1] = cutoffs[index]
    end
    ranking.smartTarget = RankTarget.Resolve(score, smartCutoffs, BuildAchievementTargets(API, region))

    local topTarget = cutoffByKey.p999
    ranking.inTop01 = score >= topTarget.score
    if ranking.inTop01 then
        ranking.bracketKind = "top"
        ranking.topRankMax = ranking.rankMax or SafeNumber(topTarget.value.rank)
        ranking.surpassedAtLeast = 99.9
    elseif score < cutoffByKey.p600.score then
        if extendedEstimate then
            ranking.bracketKind = "between"
            ranking.bracketLow = string.format("%.1f", extendedEstimate.percentileMin)
            ranking.bracketHigh = string.format("%.1f", extendedEstimate.percentileMax)
        else
            ranking.bracketKind = "below"
        end
    else
        for index = #cutoffs - 1, 1, -1 do
            local lower = cutoffs[index + 1]
            local target = cutoffs[index]
            if score >= lower.score and score < target.score then
                ranking.bracketKind = "between"
                ranking.bracketLow = lower.percent
                ranking.bracketHigh = target.percent
                break
            end
        end
    end

    if ranking.estimatedRank and ranking.population and ranking.population > 0 then
        ranking.surpassed = Util.ClampNumber(100 - (ranking.estimatedRank / ranking.population * 100), 0, 100, nil)
    elseif ranking.percentileMin and ranking.percentileMax then
        ranking.surpassedMin = Util.ClampNumber(100 - ranking.percentileMax, 0, 100, nil)
        ranking.surpassedMax = Util.ClampNumber(100 - ranking.percentileMin, 0, 100, nil)
    end
    return ranking
end

function Data.MarkDirty(section)
    if dirty[section] ~= nil then
        dirty[section] = true
    end
end

function Data.MarkRegionDirty()
    dirty.score = true
    dirty.ranking = true
    dirty.seasonInfo = true
    dirty.cutoffHistory = true
end

function Data.IsDirty(section)
    return dirty[section] == true
end

function Data.HasDirtyData()
    for _, section in ipairs(SECTION_ORDER) do
        if dirty[section] then
            return true
        end
    end
    return false
end

function Data.GetCachedSection(section)
    return cache[section]
end

function Data.RefreshMapMetadata()
    local section = cache.mapMeta
    local previousSignature = section.signature
    Util.WipeArray(section.ordered)
    Util.WipeArray(section.byMapID)
    Util.WipeArray(section.mapIDs)
    section.valid = false

    if not C_ChallengeMode
        or type(C_ChallengeMode.GetMapTable) ~= "function"
        or type(C_ChallengeMode.GetMapUIInfo) ~= "function"
    then
        dirty.mapMeta = false
        return section
    end

    local mapIDs = SafeTable(C_ChallengeMode.GetMapTable())
    if not mapIDs then
        dirty.mapMeta = false
        return section
    end

    local signatureParts = {}
    for _, rawMapID in ipairs(mapIDs) do
        local mapID = SafeNumber(rawMapID)
        if mapID then
            local rawName, _, rawTimeLimit, rawTexture = C_ChallengeMode.GetMapUIInfo(mapID)
            local info = {
                mapID = mapID,
                name = SafeString(rawName),
                timeLimit = SafeNumber(rawTimeLimit),
                texture = SafeNumber(rawTexture),
            }
            section.ordered[#section.ordered + 1] = info
            section.byMapID[mapID] = info
            section.mapIDs[#section.mapIDs + 1] = mapID
            signatureParts[#signatureParts + 1] = tostring(mapID)
        end
    end

    section.signature = table.concat(signatureParts, ",")
    section.valid = true
    dirty.mapMeta = false
    if previousSignature and previousSignature ~= section.signature then
        dirty.score = true
        dirty.seasonStats = true
        dirty.weeklyStats = true
        dirty.keystone = true
    end
    return section
end

function Data.RefreshScoreData()
    if dirty.mapMeta then
        Data.RefreshMapMetadata()
    end
    local section = cache.score
    local previousScore = section.overall
    section.overall = GetOverallScore()
    section.overallColor = nil
    local API = _G.QFXMythicRankData
    local region = ns.GetSelectedRegion()
    if section.overall and region then
        section.overallColor = Util.GetPlayerScoreColor(API, region, section.overall)
    end
    section.highestLevel = nil
    for mapID, dynamic in pairs(section.maps) do
        if cache.mapMeta.byMapID[mapID] then
            dynamic.level = nil
            dynamic.dungeonScore = nil
        else
            section.maps[mapID] = nil
        end
    end

    local displayScores
    if C_ChallengeMode and type(C_ChallengeMode.GetMapScoreInfo) == "function" then
        displayScores = SafeTable(C_ChallengeMode.GetMapScoreInfo())
    end
    if displayScores then
        for _, rawScoreInfo in ipairs(displayScores) do
            local scoreInfo = SafeTable(rawScoreInfo)
            local mapID = scoreInfo and SafeNumber(scoreInfo.mapChallengeModeID) or nil
            if mapID then
                local dynamic = section.maps[mapID] or {}
                dynamic.level = SafeNumber(scoreInfo.level)
                dynamic.dungeonScore = SafeNumber(scoreInfo.dungeonScore)
                section.maps[mapID] = dynamic
            end
        end
    end

    for _, mapInfo in ipairs(cache.mapMeta.ordered) do
        local mapID = mapInfo.mapID
        local dynamic = section.maps[mapID]
        if not dynamic then
            dynamic = {}
            section.maps[mapID] = dynamic
        end
        if C_MythicPlus and type(C_MythicPlus.GetSeasonBestForMap) == "function" then
            local rawInTime, rawOvertime = C_MythicPlus.GetSeasonBestForMap(mapID)
            local inTime = SafeTable(rawInTime)
            local overtime = SafeTable(rawOvertime)
            local inTimeLevel = inTime and SafeNumber(inTime.level) or nil
            local overtimeLevel = overtime and SafeNumber(overtime.level) or nil
            if inTimeLevel and overtimeLevel then
                dynamic.level = math.max(inTimeLevel, overtimeLevel)
            elseif inTimeLevel then
                dynamic.level = inTimeLevel
            elseif overtimeLevel then
                dynamic.level = overtimeLevel
            end
        end
        if dynamic.level and (not section.highestLevel or dynamic.level > section.highestLevel) then
            section.highestLevel = dynamic.level
        end
    end

    section.valid = true
    dirty.score = false
    if previousScore ~= section.overall then
        dirty.ranking = true
    end
    return section
end

function Data.RefreshSeasonInfo()
    local section = cache.seasonInfo
    section.shortName = nil
    section.name = nil
    section.slug = nil
    section.state = nil
    section.startsAt = nil
    section.endsAt = nil
    section.blizzardSeasonID = nil
    section.dataVersion = nil
    Util.WipeArray(section.dungeonByChallengeModeID)
    section.available = false

    local API = _G.QFXMythicRankData
    local region = ns.GetSelectedRegion()
    if type(API) == "table" and region then
        local rawSeason = type(API.GetSeasonInfo) == "function"
            and SafeTable(API:GetSeasonInfo(region)) or nil
        local metadata = type(API.GetMetadata) == "function"
            and SafeTable(API:GetMetadata(region)) or nil
        if rawSeason then
            section.shortName = SafeString(rawSeason.shortName)
            section.name = SafeString(rawSeason.name)
            section.slug = SafeString(rawSeason.slug)
            section.startsAt = SafeNumber(rawSeason.startsAt)
            section.endsAt = SafeNumber(rawSeason.endsAt)
            section.blizzardSeasonID = SafeNumber(rawSeason.blizzardSeasonID)
        end
        section.state = metadata and SafeString(metadata.seasonState) or nil
        section.dataVersion = metadata and SafeString(metadata.dataVersion) or nil
        if type(API.GetSeasonDungeons) == "function" then
            local dungeons = SafeTable(API:GetSeasonDungeons(region))
            for _, rawDungeon in ipairs(dungeons or {}) do
                local dungeon = SafeTable(rawDungeon)
                local mapID = dungeon and SafeNumber(dungeon.challengeModeID) or nil
                if mapID then
                    section.dungeonByChallengeModeID[mapID] = {
                        name = SafeString(dungeon.name),
                        shortName = SafeString(dungeon.shortName),
                    }
                end
            end
        end
        section.available = section.shortName ~= nil
            or section.name ~= nil
            or section.startsAt ~= nil
    end
    section.valid = true
    dirty.seasonInfo = false
    return section
end

function Data.GetEnglishDungeonInfo(mapID)
    local safeMapID = SafeNumber(mapID)
    local info = safeMapID and cache.seasonInfo.dungeonByChallengeModeID[safeMapID] or nil
    if not info then
        if ns.GetFallbackEnglishDungeonInfo then
            return ns.GetFallbackEnglishDungeonInfo(safeMapID)
        end
        return nil, nil
    end
    return SafeString(info.name), SafeString(info.shortName)
end

local function ParseDataVersionTimestamp(dataVersion)
    local value = SafeString(dataVersion)
    if not value then
        return nil
    end
    local year, month, day, hour, minute = value:match("^(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)")
    year, month, day, hour, minute = tonumber(year), tonumber(month), tonumber(day), tonumber(hour), tonumber(minute)
    if not year or not month or not day or not hour or not minute or type(time) ~= "function" then
        return nil
    end
    local timestamp = SafeNumber(time({
        year = year,
        month = month,
        day = day,
        hour = hour,
        min = minute,
        sec = 0,
    }))
    return timestamp and timestamp * 1000 or nil
end

local function GetCurrentTimestampMs(metadata)
    local parsed = metadata and ParseDataVersionTimestamp(metadata.dataVersion) or nil
    if parsed then
        return parsed
    end
    if type(GetServerTime) == "function" then
        local serverTime = SafeNumber(GetServerTime())
        if serverTime then
            return serverTime * 1000
        end
    end
    local localTime = type(time) == "function" and SafeNumber(time()) or nil
    return localTime and localTime * 1000 or nil
end

local function RecalculatePointDeltas(points)
    local previous
    for _, point in ipairs(points) do
        point.delta = previous and (point.score - previous.score) or nil
        previous = point
    end
end

local function NormalizeHistoryPoints(rawHistory, currentCutoff, metadata)
    local byTimestamp = {}
    for _, rawPoint in ipairs(SafeTable(rawHistory) or {}) do
        local point = SafeTable(rawPoint)
        local timestampMs = point and SafeNumber(point.timestampMs) or nil
        local score = point and SafeNumber(point.score) or nil
        if timestampMs and score then
            byTimestamp[timestampMs] = {
                timestampMs = timestampMs,
                score = score,
                population = SafeNumber(point.population),
            }
        end
    end

    local ordered = {}
    for _, point in pairs(byTimestamp) do
        ordered[#ordered + 1] = point
    end
    table.sort(ordered, function(left, right)
        return left.timestampMs < right.timestampMs
    end)

    local daily = {}
    local indexByDay = {}
    for _, point in ipairs(ordered) do
        local dayKey = math.floor(point.timestampMs / 86400000)
        local existingIndex = indexByDay[dayKey]
        if existingIndex then
            daily[existingIndex] = point
        else
            daily[#daily + 1] = point
            indexByDay[dayKey] = #daily
        end
    end

    while #daily > 30 do
        table.remove(daily, 1)
    end

    local currentScore = currentCutoff and SafeNumber(currentCutoff.score) or nil
    if currentScore then
        local last = daily[#daily]
        if last and math.abs(last.score - currentScore) <= 0.05 then
            last.score = currentScore
        else
            local timestampMs = GetCurrentTimestampMs(metadata)
            if timestampMs then
                daily[#daily + 1] = {
                    timestampMs = timestampMs,
                    score = currentScore,
                    population = currentCutoff and SafeNumber(currentCutoff.population) or nil,
                }
            end
        end
    end

    table.sort(daily, function(left, right)
        return left.timestampMs < right.timestampMs
    end)
    while #daily > 30 do
        table.remove(daily, 1)
    end
    RecalculatePointDeltas(daily)
    return daily
end

function Data.RefreshCutoffHistory()
    local section = cache.cutoffHistory
    section.available = false
    section.maxPointCount = 0
    Util.WipeArray(section.seriesByKey)

    local API = _G.QFXMythicRankData
    local region = ns.GetSelectedRegion()
    if type(API) == "table"
        and type(API.GetCutoff) == "function"
        and type(API.GetCutoffHistory) == "function"
        and region
    then
        local metadata = type(API.GetMetadata) == "function" and SafeTable(API:GetMetadata(region)) or nil
        for _, definition in ipairs(RankTarget.CUTOFF_DEFS) do
            local cutoff = SafeTable(API:GetCutoff(region, definition.key, "all"))
            local rawHistory = SafeTable(API:GetCutoffHistory(region, definition.key))
            local points = NormalizeHistoryPoints(rawHistory, cutoff, metadata)
            local series = {
                key = definition.key,
                percent = definition.percent,
                color = cutoff and SafeString(cutoff.color) or nil,
                currentScore = cutoff and SafeNumber(cutoff.score) or nil,
                points = points,
                available = #points >= 2,
            }
            section.seriesByKey[definition.key] = series
            section.maxPointCount = math.max(section.maxPointCount, #points)
            section.available = section.available or series.available
        end
    end
    section.valid = true
    dirty.cutoffHistory = false
    return section
end

function Data.RefreshRankingData()
    if dirty.score then
        Data.RefreshScoreData()
    end
    cache.ranking.result = BuildRanking(cache.score.overall)
    cache.ranking.valid = true
    dirty.ranking = false
    return cache.ranking
end

function Data.RefreshSeasonStatistics()
    if dirty.mapMeta then
        Data.RefreshMapMetadata()
    end
    if dirty.score then
        Data.RefreshScoreData()
    end
    local runs = GetRunHistory(true)
    local ready = runs ~= nil
    if ready and #runs == 0 and (cache.score.overall == nil or cache.score.overall > 0) then
        ready = false
    end
    local result = Statistics and Statistics.BuildSingle(
        cache.mapMeta.mapIDs,
        runs,
        ready,
        "season"
    ) or { available = false, byMapID = {}, summary = {} }
    cache.seasonStats.available = result.available
    cache.seasonStats.byMapID = result.byMapID
    cache.seasonStats.summary = result.summary
    cache.seasonStats.valid = true
    dirty.seasonStats = false
    return cache.seasonStats
end

function Data.RefreshWeeklyStatistics()
    if dirty.mapMeta then
        Data.RefreshMapMetadata()
    end
    local runs = GetRunHistory(false)
    local reportedTotal = GetWeeklyTotal()
    local ready = runs ~= nil
    if ready and reportedTotal and #runs ~= reportedTotal then
        ready = false
    end
    local result = Statistics and Statistics.BuildSingle(
        cache.mapMeta.mapIDs,
        runs,
        ready,
        "weekly"
    ) or { available = false, byMapID = {}, summary = {} }
    cache.weeklyStats.available = result.available
    cache.weeklyStats.byMapID = result.byMapID
    cache.weeklyStats.summary = result.summary
    cache.weeklyStats.reportedTotal = reportedTotal
    cache.weeklyStats.valid = true
    dirty.weeklyStats = false
    return cache.weeklyStats
end

function Data.RefreshKeystone()
    if dirty.mapMeta then
        Data.RefreshMapMetadata()
    end
    local result
    if C_MythicPlus
        and type(C_MythicPlus.GetOwnedKeystoneChallengeMapID) == "function"
        and type(C_MythicPlus.GetOwnedKeystoneLevel) == "function"
    then
        local mapID = SafeNumber(C_MythicPlus.GetOwnedKeystoneChallengeMapID())
        local level = SafeNumber(C_MythicPlus.GetOwnedKeystoneLevel())
        if mapID and level and mapID > 0 and level > 0 then
            local mapInfo = cache.mapMeta.byMapID[mapID]
            local name = mapInfo and mapInfo.name or nil
            if not name and C_ChallengeMode and type(C_ChallengeMode.GetMapUIInfo) == "function" then
                name = SafeString(C_ChallengeMode.GetMapUIInfo(mapID))
            end
            result = { mapID = mapID, name = name, level = level }
        end
    end
    cache.keystone.data = result
    cache.keystone.valid = true
    dirty.keystone = false
    return cache.keystone
end

function Data.RefreshVault()
    local apiAvailable = C_WeeklyRewards
        and type(C_WeeklyRewards.GetActivities) == "function"
        and type(Enum) == "table"
        and type(Enum.WeeklyRewardChestThresholdType) == "table"
    for _, definition in ipairs(VAULT_CATEGORY_DEFS) do
        local category = cache.vault.categories[definition.key]
        category.available = false
        category.progress = 0
        category.maximum = definition.fallbackMaximum
        if apiAvailable then
            local activityType = SafeNumber(Enum.WeeklyRewardChestThresholdType[definition.enumKey])
            local activities = activityType and SafeTable(C_WeeklyRewards.GetActivities(activityType)) or nil
            if activities then
                category.available = true
                local progress = 0
                local maximum = 0
                for _, rawActivity in ipairs(activities) do
                    local activity = SafeTable(rawActivity)
                    local value = activity and SafeNumber(activity.progress) or 0
                    local threshold = activity and SafeNumber(activity.threshold) or 0
                    progress = math.max(progress, value or 0)
                    maximum = math.max(maximum, threshold or 0)
                end
                category.maximum = maximum > 0 and maximum or definition.fallbackMaximum
                category.progress = Util.ClampNumber(progress, 0, category.maximum, 0)
            end
        end
    end
    cache.vault.valid = true
    dirty.vault = false
    return cache.vault
end

function Data.RefreshResources()
    local result = Resources and Resources.GetAll and Resources.GetAll(cache.resources.ordered) or {}
    Util.WipeArray(cache.resources.byKey)
    for _, resource in ipairs(result) do
        if resource and resource.key then
            cache.resources.byKey[resource.key] = resource
        end
    end
    cache.resources.valid = true
    dirty.resources = false
    return cache.resources
end

function Data.RefreshOneResource(currencyID, quantityOverride)
    if dirty.resources or not cache.resources.valid or not Resources then
        return nil
    end
    local key = Resources.GetKeyForCurrencyID(currencyID)
    local index = key and Resources.GetIndexForKey(key) or nil
    if not key or not index then
        return nil
    end
    local resource = Resources.RefreshOne(currencyID, cache.resources.byKey[key], quantityOverride)
    if not resource then
        return nil
    end
    cache.resources.byKey[key] = resource
    cache.resources.ordered[index] = resource
    return resource
end

-- The map table is static for the session; asking the client for it on every
-- refresh would spam the server side request for no benefit.
local MAP_INFO_REQUEST_INTERVAL = 10
local lastMapInfoRequestAt = nil

function Data.RequestData()
    local now = type(GetTime) == "function" and Util.SafeNumber(GetTime()) or nil
    if now and now > 0 and lastMapInfoRequestAt
        and (now - lastMapInfoRequestAt) < MAP_INFO_REQUEST_INTERVAL
    then
        return
    end
    if now and now > 0 then
        lastMapInfoRequestAt = now
    end
    if C_MythicPlus and type(C_MythicPlus.RequestMapInfo) == "function" then
        C_MythicPlus.RequestMapInfo()
    end
end

