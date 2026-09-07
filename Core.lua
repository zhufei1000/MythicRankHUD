local ADDON_NAME, ns = ...
local L = ns.L
local Util = ns.Util
local RankTarget = ns.RankTarget

local DEFAULT_ROW_VISIBILITY = {
    dataUpdated = true,
    cutoff01 = true,
    cutoff1 = true,
    score = true,
    todayScore = true,
    rank = true,
    surpassed = true,
    todayRank = true,
    toTop25 = true,
    rankRange = false,
    percentileRange = false,
}

local DEFAULTS = {
    showHUD = true,
    announceTeleport = true,
    announceRunGain = true,
    announceMemberJoin = true,
    announceDelay = 5,
    enableMythicDetail = true,
    borderStyle = "gold",
    borderAlpha = 0.85,
    backgroundAlpha = 0.88,
    detailBorderAlpha = 1.00,
    detailBackgroundAlpha = 0.90,
    detailPoint = "CENTER",
    detailRelativePoint = "CENTER",
    detailX = 0,
    detailY = 0,
    showRows = DEFAULT_ROW_VISIBILITY,
    characters = {},
    selectedRegion = nil,
}

local ROW_ORDER = {
    "dataUpdated",
    "cutoff01",
    "cutoff1",
    "score",
    "rank",
    "surpassed",
    "todayScore",
    "todayRank",
    "toTop25",
    "rankRange",
    "percentileRange",
}

local VALID_ANCHOR_POINTS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local rows = {}
for _, key in ipairs(ROW_ORDER) do
    rows[key] = { key = key }
end
local hudSnapshot = {}
local db
local databaseInitialized = false
local englishTextWarningPrinted = false
local GOLD_R, GOLD_G, GOLD_B = 1.0, 0.82, 0.0

local function CopyDefaults(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = CopyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

local function InitializeDatabase()
    if databaseInitialized then
        return db
    end

    local oldDB = type(QFXMythicRankHUDGlobalDB) == "table" and QFXMythicRankHUDGlobalDB or nil
    local hadShowRows = oldDB and type(oldDB.showRows) == "table"
    local oldShowRanges = oldDB and oldDB.showRanges
    local hadDetailBorderAlpha = oldDB and oldDB.detailBorderAlpha ~= nil
    local hadDetailBackgroundAlpha = oldDB and oldDB.detailBackgroundAlpha ~= nil
    local legacyBorderAlpha = oldDB and oldDB.borderAlpha or nil
    local legacyBackgroundAlpha = oldDB and oldDB.backgroundAlpha or nil

    QFXMythicRankHUDGlobalDB = CopyDefaults(oldDB, DEFAULTS)

    if not hadShowRows and oldShowRanges == true then
        QFXMythicRankHUDGlobalDB.showRows.rankRange = true
        QFXMythicRankHUDGlobalDB.showRows.percentileRange = true
    end

    db = QFXMythicRankHUDGlobalDB
    db.showRanges = nil

    if type(db.showHUD) ~= "boolean" then
        db.showHUD = DEFAULTS.showHUD
    end
    if type(db.announceTeleport) ~= "boolean" then
        db.announceTeleport = DEFAULTS.announceTeleport
    end
    if type(db.announceRunGain) ~= "boolean" then
        db.announceRunGain = DEFAULTS.announceRunGain
    end
    if type(db.announceMemberJoin) ~= "boolean" then
        db.announceMemberJoin = DEFAULTS.announceMemberJoin
    end
    db.announceDelay = Util.ClampNumber(db.announceDelay, 0, 60, DEFAULTS.announceDelay)
    if type(db.enableMythicDetail) ~= "boolean" then
        db.enableMythicDetail = DEFAULTS.enableMythicDetail
    end
    db.borderAlpha = Util.ClampNumber(db.borderAlpha, 0, 1, DEFAULTS.borderAlpha)
    db.backgroundAlpha = Util.ClampNumber(db.backgroundAlpha, 0, 1, DEFAULTS.backgroundAlpha)
    if not hadDetailBorderAlpha and oldDB then
        db.detailBorderAlpha = Util.ClampNumber(legacyBorderAlpha, 0, 1, DEFAULTS.detailBorderAlpha)
    else
        db.detailBorderAlpha = Util.ClampNumber(db.detailBorderAlpha, 0, 1, DEFAULTS.detailBorderAlpha)
    end
    if not hadDetailBackgroundAlpha and oldDB then
        db.detailBackgroundAlpha = Util.ClampNumber(
            legacyBackgroundAlpha,
            0,
            1,
            DEFAULTS.detailBackgroundAlpha
        )
    else
        db.detailBackgroundAlpha = Util.ClampNumber(
            db.detailBackgroundAlpha,
            0,
            1,
            DEFAULTS.detailBackgroundAlpha
        )
    end
    if db.borderStyle ~= "transparent" and db.borderStyle ~= "class" and db.borderStyle ~= "gold" then
        db.borderStyle = DEFAULTS.borderStyle
    end
    db.detailPoint = VALID_ANCHOR_POINTS[db.detailPoint] and db.detailPoint or DEFAULTS.detailPoint
    db.detailRelativePoint = VALID_ANCHOR_POINTS[db.detailRelativePoint]
        and db.detailRelativePoint
        or DEFAULTS.detailRelativePoint
    db.detailX = Util.ClampNumber(db.detailX, -100000, 100000, DEFAULTS.detailX)
    db.detailY = Util.ClampNumber(db.detailY, -100000, 100000, DEFAULTS.detailY)

    for _, key in ipairs(ROW_ORDER) do
        if type(db.showRows[key]) ~= "boolean" then
            db.showRows[key] = DEFAULT_ROW_VISIBILITY[key]
        end
    end

    databaseInitialized = true
    return db
end

local function GetDB()
    return db or InitializeDatabase()
end

local function GetCharacterKey()
    local guid = UnitGUID("player")
    if guid then
        return guid
    end
    local name, realm = UnitFullName("player")
    if not name then
        return "unknown"
    end
    return name .. "-" .. (realm or GetRealmName() or "")
end

local function GetDateKey()
    if C_DateAndTime and type(C_DateAndTime.GetCurrentCalendarTime) == "function" then
        local calendar = C_DateAndTime.GetCurrentCalendarTime()
        if calendar and calendar.year and calendar.month and calendar.monthDay then
            return string.format("%04d%02d%02d", calendar.year, calendar.month, calendar.monthDay)
        end
    end
    return date("%Y%m%d")
end

local function FormatVersionTimestamp(version)
    local year, month, day, hour, minute = tostring(version or ""):match(
        "^(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)"
    )
    if not year then return "--" end
    return string.format(
        L.DATA_TIME_FORMAT,
        tonumber(month),
        tonumber(day),
        tonumber(hour),
        tonumber(minute)
    )
end

local function GetDataUpdatedTime(metadata)
    local sourceTime = FormatVersionTimestamp(metadata and metadata.dataVersion)
    return string.format(L.DATA_UPDATED, sourceTime)
end

local function FormatScore(value, decimals)
    if type(value) ~= "number" then
        return "--"
    end
    return string.format("%." .. tostring(decimals or 1) .. "f", value)
end

local function FormatInteger(value)
    if type(value) ~= "number" then
        return "--"
    end
    return tostring(math.floor(value + 0.5))
end

local function FormatCompactRank(value)
    if type(value) ~= "number" then
        return "--"
    end
    if value >= 1000000 then
        return string.format("%.2fM", value / 1000000)
    elseif value >= 1000 then
        return FormatInteger(value)
    end
    return FormatInteger(value)
end

local function FormatPercent(value)
    if type(value) ~= "number" then
        return "--"
    end
    if math.abs(value - math.floor(value + 0.5)) < 0.005 then
        return tostring(math.floor(value + 0.5))
    end
    return string.format("%.1f", value)
end

local function HexToRGB(hex)
    if type(hex) ~= "string" then
        return GOLD_R, GOLD_G, GOLD_B
    end
    hex = hex:gsub("#", "")
    if #hex ~= 6 then
        return GOLD_R, GOLD_G, GOLD_B
    end
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)
    if not r or not g or not b then
        return GOLD_R, GOLD_G, GOLD_B
    end
    return r / 255, g / 255, b / 255
end

local function SetRow(row, label, value, r, g, b)
    if row.label and row.value then
        row.label:SetText(label)
        row.value:SetText(value)
        row.value:SetTextColor(r or 1, g or 1, b or 1)
    end
    if row.key then
        local snapshot = hudSnapshot[row.key] or {}
        snapshot.label = label
        snapshot.value = value
        snapshot.r = r or 1
        snapshot.g = g or 1
        snapshot.b = b or 1
        hudSnapshot[row.key] = snapshot
    end
end

local function GetClassColor()
    local _, classToken = UnitClass("player")
    local color = classToken and CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classToken]
    if not color then
        color = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    end
    if color then
        return color.r or GOLD_R, color.g or GOLD_G, color.b or GOLD_B
    end
    return GOLD_R, GOLD_G, GOLD_B
end

local function GetAccentColor(alpha)
    local db = GetDB()
    local r, g, b = 0.72, 0.56, 0.18
    if db.borderStyle == "class" then
        r, g, b = GetClassColor()
    elseif db.borderStyle == "transparent" then
        return r, g, b, 0
    end
    return r, g, b, alpha
end

local function GetHUDAccentColor()
    local db = GetDB()
    return GetAccentColor(db.borderAlpha)
end

local function GetDetailAccentColor()
    local db = GetDB()
    return GetAccentColor(db.detailBorderAlpha)
end

local function UpdateDailyState(score)
    local db = GetDB()
    local key = GetCharacterKey()
    local state = db.characters[key]
    if type(state) ~= "table" then
        state = {}
        db.characters[key] = state
    end

    local today = GetDateKey()
    if state.dateKey ~= today then
        state.dateKey = today
        state.baselineScore = tonumber(state.lastScore) or score
    elseif type(state.baselineScore) ~= "number" then
        state.baselineScore = score
    end

    state.lastScore = score
    return state
end

local function UpdateDailyScoreStateOnly()
    local API = _G.QFXMythicRankData
    if type(API) ~= "table" or type(API.GetPlayerScore) ~= "function" then
        return
    end

    local score = Util.SafeNumber(API:GetPlayerScore())
    if score == nil then
        return
    end

    UpdateDailyState(score)
end

local function SetUnavailable(message)
    local unavailable = message or L.UNAVAILABLE
    local regionLabel = ns.GetSelectedRegionLabel()
    local rankLabel = regionLabel and string.format(L.REGION_RANK_FORMAT, regionLabel)
        or L.SETTINGS_ROW_REGION_RANK
    SetRow(rows.dataUpdated, "", string.format(L.DATA_UPDATED, unavailable), GOLD_R, GOLD_G, GOLD_B)
    SetRow(rows.cutoff01, L.CUTOFF_01, unavailable, 0.65, 0.65, 0.65)
    SetRow(rows.cutoff1, L.CUTOFF_1, unavailable, 0.65, 0.65, 0.65)
    SetRow(rows.score, L.SCORE, unavailable, 0.65, 0.65, 0.65)
    SetRow(rows.todayScore, L.TODAY_SCORE, "--", 0.65, 0.65, 0.65)
    SetRow(rows.rank, rankLabel, "--", 0.65, 0.65, 0.65)
    SetRow(rows.surpassed, L.SURPASSED, "--", 0.65, 0.65, 0.65)
    SetRow(rows.todayRank, L.TODAY_RANK, "--", 0.65, 0.65, 0.65)
    SetRow(rows.toTop25, L.SMART_NEXT_TARGET, "--", 0.65, 0.65, 0.65)
    SetRow(rows.rankRange, L.RANK_RANGE, "--", 0.65, 0.65, 0.65)
    SetRow(rows.percentileRange, L.PERCENTILE_RANGE, "--", 0.65, 0.65, 0.65)
end

local function GetHUDAchievementTargets(API, region)
    if type(API.GetAchievementCutoff) ~= "function" then
        return nil
    end
    local definitions = {
        { key = "keystoneExplorer", name = L.ACHIEVEMENT_KEYSTONE_EXPLORER_SHORT },
        { key = "keystoneConqueror", name = L.ACHIEVEMENT_KEYSTONE_CONQUEROR_SHORT },
        { key = "keystoneMaster", name = L.ACHIEVEMENT_KEYSTONE_MASTER_SHORT },
        { key = "keystoneHero", name = L.ACHIEVEMENT_KEYSTONE_HERO_SHORT },
        { key = "keystoneLegend", name = L.ACHIEVEMENT_KEYSTONE_LEGEND_SHORT },
    }
    local targets = {}
    for _, definition in ipairs(definitions) do
        local ok, raw = pcall(API.GetAchievementCutoff, API, region, definition.key)
        local value = Util.SafeTable(raw)
        local threshold = Util.SafeNumber(value and (value.thresholdScore or value.score) or raw)
        if threshold then
            targets[#targets + 1] = {
                key = definition.key,
                thresholdScore = threshold,
                localizedName = definition.name,
                color = value and Util.SafeString(value.color) or nil,
            }
        end
    end
    return targets
end

local function RefreshHUDData()

    local API = _G.QFXMythicRankData
    local region = ns.GetSelectedRegion()
    local regionLabel = ns.GetSelectedRegionLabel()
    local rankLabel = regionLabel and string.format(L.REGION_RANK_FORMAT, regionLabel)
        or L.SETTINGS_ROW_REGION_RANK
    if type(API) ~= "table"
        or type(API.GetMetadata) ~= "function"
        or type(API.GetCutoff) ~= "function"
        or type(API.GetPlayerScore) ~= "function"
        or type(API.EstimateRank) ~= "function"
        or not region
    then
        SetUnavailable()
        return
    end

    local metadata = Util.SafeTable(API:GetMetadata(region))
    local cutoffByKey = {}
    for _, definition in ipairs(RankTarget.CUTOFF_DEFS) do
        cutoffByKey[definition.key] = Util.SafeTable(API:GetCutoff(region, definition.key, "all"))
    end
    local cutoff01 = cutoffByKey.p999
    local cutoff1 = cutoffByKey.p990
    local cutoff10 = cutoffByKey.p900
    local cutoff25 = cutoffByKey.p750
    local cutoff40 = cutoffByKey.p600
    local score = Util.SafeNumber(API:GetPlayerScore())

    local cutoff01Score = cutoff01 and Util.SafeNumber(cutoff01.score)
    local cutoff1Score = cutoff1 and Util.SafeNumber(cutoff1.score)
    local cutoff10Score = cutoff10 and Util.SafeNumber(cutoff10.score)
    local cutoff25Score = cutoff25 and Util.SafeNumber(cutoff25.score)
    local cutoff40Score = cutoff40 and Util.SafeNumber(cutoff40.score)
    if not metadata
        or not cutoff01Score
        or not cutoff1Score
        or not cutoff10Score
        or not cutoff25Score
        or not cutoff40Score
    then
        SetUnavailable()
        return
    end

    local c01r, c01g, c01b = HexToRGB(cutoff01.color)
    local c1r, c1g, c1b = HexToRGB(cutoff1.color)
    SetRow(rows.dataUpdated, "", GetDataUpdatedTime(metadata), GOLD_R, GOLD_G, GOLD_B)
    SetRow(rows.cutoff01, L.CUTOFF_01, FormatScore(cutoff01Score, 1), c01r, c01g, c01b)
    SetRow(rows.cutoff1, L.CUTOFF_1, FormatScore(cutoff1Score, 1), c1r, c1g, c1b)

    if type(score) ~= "number" then
        SetRow(rows.score, L.SCORE, L.NO_SCORE, 0.65, 0.65, 0.65)
        SetRow(rows.todayScore, L.TODAY_SCORE, "--", 0.65, 0.65, 0.65)
        SetRow(rows.rank, rankLabel, "--", 0.65, 0.65, 0.65)
        SetRow(rows.surpassed, L.SURPASSED, "--", 0.65, 0.65, 0.65)
        SetRow(rows.todayRank, L.TODAY_RANK, "--", 0.65, 0.65, 0.65)
        SetRow(rows.toTop25, L.SMART_NEXT_TARGET, "--", 0.65, 0.65, 0.65)
        SetRow(rows.rankRange, L.RANK_RANGE, "--", 0.65, 0.65, 0.65)
        SetRow(rows.percentileRange, L.PERCENTILE_RANGE, "--", 0.65, 0.65, 0.65)
        return
    end

    local result = Util.SafeTable(API:EstimateRank(region, score, "all"))
    if not result then
        SetUnavailable()
        return
    end

    local state = UpdateDailyState(score)
    local baselineScore = tonumber(state.baselineScore) or score
    local baselineResult = Util.SafeTable(API:EstimateRank(region, baselineScore, "all"))
    local scoreGain = score - baselineScore
    local estimatedRank = Util.SafeNumber(result.estimatedRank)
    local rankMin = Util.SafeNumber(result.rankMin)
    local rankMax = Util.SafeNumber(result.rankMax)
    local percentileMin = Util.SafeNumber(result.percentileMin)
    local percentileMax = Util.SafeNumber(result.percentileMax)
    local extendedEstimate
    if not estimatedRank then
        extendedEstimate = Util.EstimateRankBelowTop40(API, region, score, "all")
        if extendedEstimate then
            estimatedRank = Util.SafeNumber(extendedEstimate.estimatedRank)
            rankMin = Util.SafeNumber(extendedEstimate.rankMin) or rankMin
            rankMax = Util.SafeNumber(extendedEstimate.rankMax) or rankMax
            percentileMin = Util.SafeNumber(extendedEstimate.percentileMin) or percentileMin
            percentileMax = Util.SafeNumber(extendedEstimate.percentileMax) or percentileMax
        end
    end
    local resultBracket = Util.SafeString(result.bracket)
    local baselineEstimatedRank = baselineResult and Util.SafeNumber(baselineResult.estimatedRank) or nil
    if not baselineEstimatedRank then
        local baselineExtendedEstimate = Util.EstimateRankBelowTop40(API, region, baselineScore, "all")
        baselineEstimatedRank = baselineExtendedEstimate
            and Util.SafeNumber(baselineExtendedEstimate.estimatedRank) or nil
    end
    local baselineBracket = baselineResult and Util.SafeString(baselineResult.bracket) or nil
    local currentTop01 = score >= cutoff01Score or resultBracket == "p999"
    local baselineTop01 = baselineScore >= cutoff01Score
        or baselineBracket == "p999"
    local topRankMax = rankMax or Util.SafeNumber(cutoff01.rank)
    local topPercentile = percentileMax or Util.SafeNumber(cutoff01.percentile) or 0.1

    local scoreColor = Util.GetPlayerScoreColor(API, region, score)
    local scoreR, scoreG, scoreB
    if scoreColor then
        scoreR, scoreG, scoreB = Util.HexColorToRGB(scoreColor, 1, 1, 1)
    else
        scoreR, scoreG, scoreB = 1, 1, 1
    end
    SetRow(rows.score, L.SCORE, FormatScore(score, 1), scoreR, scoreG, scoreB)

    local scoreGainText = (scoreGain >= 0 and "+" or "") .. FormatScore(scoreGain, 1)
    local gainR, gainG, gainB = 0.6, 0.85, 0.6
    if scoreGain < 0 then
        gainR, gainG, gainB = 1, 0.45, 0.45
    end
    SetRow(rows.todayScore, L.TODAY_SCORE, string.format(L.SCORE_POINTS, scoreGainText), gainR, gainG, gainB)

    if currentTop01 and topRankMax then
        SetRow(rows.rank, rankLabel, string.format(L.TOP_RANK_VALUE, FormatInteger(topRankMax)), 1, 0.82, 0)
    elseif estimatedRank then
        SetRow(rows.rank, rankLabel, string.format(L.APPROX_RANK, FormatCompactRank(estimatedRank)), 1, 0.82, 0)
    elseif rankMin and rankMax then
        local range = string.format(L.RANGE_JOIN, FormatCompactRank(rankMin), FormatCompactRank(rankMax))
        SetRow(rows.rank, rankLabel, string.format(L.APPROX_RANK, range), 1, 0.82, 0)
    else
        SetRow(rows.rank, rankLabel, L.UNAVAILABLE, 0.65, 0.65, 0.65)
    end

    local population = Util.SafeNumber(metadata.population)
    if currentTop01 then
        local surpassedAtLeast = math.max(0, math.min(100, 100 - topPercentile))
        SetRow(
            rows.surpassed,
            L.SURPASSED,
            string.format(L.SURPASSED_AT_LEAST, FormatPercent(surpassedAtLeast)),
            0.45,
            0.85,
            1
        )
    elseif estimatedRank and population and population > 0 then
        local surpassed = math.max(0, math.min(100, 100 - (estimatedRank / population * 100)))
        SetRow(rows.surpassed, L.SURPASSED, string.format(L.APPROX, string.format("%.1f%%", surpassed)), 0.45, 0.85, 1)
    elseif percentileMin and percentileMax then
        local low = math.max(0, 100 - percentileMax)
        local high = math.min(100, 100 - percentileMin)
        local range = string.format(L.RANGE_JOIN, string.format("%.1f%%", low), string.format("%.1f%%", high))
        SetRow(rows.surpassed, L.SURPASSED, string.format(L.APPROX, range), 0.45, 0.85, 1)
    else
        SetRow(rows.surpassed, L.SURPASSED, L.UNAVAILABLE, 0.65, 0.65, 0.65)
    end

    if currentTop01 then
        if baselineTop01 then
            SetRow(rows.todayRank, L.TODAY_RANK, L.TODAY_WITHIN_TOP_01, 0.82, 0.82, 0.82)
        else
            SetRow(rows.todayRank, L.TODAY_RANK, L.TODAY_ENTERED_TOP_01, 0.6, 0.9, 0.6)
        end
    elseif baselineTop01 then
        SetRow(rows.todayRank, L.TODAY_RANK, L.TODAY_LEFT_TOP_01, 1, 0.45, 0.45)
    elseif estimatedRank and baselineEstimatedRank then
        local movement = baselineEstimatedRank - estimatedRank
        if movement > 0 then
            SetRow(rows.todayRank, L.TODAY_RANK, string.format(L.TODAY_FORWARD_VALUE, FormatCompactRank(movement)), 0.6, 0.85, 0.6)
        elseif movement < 0 then
            SetRow(rows.todayRank, L.TODAY_RANK, string.format(L.TODAY_BACK_VALUE, FormatCompactRank(math.abs(movement))), 1, 0.45, 0.45)
        else
            SetRow(rows.todayRank, L.TODAY_RANK, string.format(L.APPROX_RANK, FormatCompactRank(0)), 0.82, 0.82, 0.82)
        end
    else
        SetRow(rows.todayRank, L.TODAY_RANK, "--", 0.65, 0.65, 0.65)
    end

    local smartCutoffs = {}
    for index = #RankTarget.CUTOFF_DEFS, 1, -1 do
        local definition = RankTarget.CUTOFF_DEFS[index]
        local cutoff = Util.SafeTable(cutoffByKey[definition.key])
        if cutoff then
            local cutoffScore = Util.SafeNumber(cutoff.score)
            if cutoffScore then
                smartCutoffs[#smartCutoffs + 1] = {
                    key = definition.key,
                    percent = definition.percent,
                    score = cutoffScore,
                    color = Util.SafeString(cutoff.color),
                }
            end
        end
    end
    local achievementTargets = GetHUDAchievementTargets(API, region)
    local smartTarget = RankTarget.Resolve(score, smartCutoffs, achievementTargets)

    if smartTarget then
        local targetR, targetG, targetB = HexToRGB(smartTarget.color)
        local label = smartTarget.targetKind == "achievement"
            and (smartTarget.targetName or L.SMART_NEXT_TARGET)
            or string.format(L.SMART_CUTOFF_LINE_FORMAT, smartTarget.targetPercent or "0.1")
        local value
        if smartTarget.mode == "complete" then
            value = L.SMART_TARGET_REACHED
            targetR, targetG, targetB = 0.45, 0.9, 0.45
        else
            value = string.format(
                L.SMART_TARGET_DISTANCE_COMPACT,
                FormatScore(smartTarget.distance or 0, 0)
            )
        end
        SetRow(
            rows.toTop25,
            label,
            value,
            targetR,
            targetG,
            targetB
        )
    else
        SetRow(rows.toTop25, L.SMART_NEXT_TARGET, "--", 0.65, 0.65, 0.65)
    end

    if currentTop01 and topRankMax then
        SetRow(
            rows.rankRange,
            L.RANK_RANGE,
            string.format(L.TOP_RANK_RANGE_VALUE, FormatInteger(topRankMax)),
            0.82,
            0.82,
            0.82
        )
    elseif rankMin and rankMax then
        local range = string.format(L.RANGE_JOIN, FormatCompactRank(rankMin), FormatCompactRank(rankMax))
        SetRow(rows.rankRange, L.RANK_RANGE, range, 0.82, 0.82, 0.82)
    else
        SetRow(rows.rankRange, L.RANK_RANGE, "--", 0.65, 0.65, 0.65)
    end

    if currentTop01 then
        SetRow(
            rows.percentileRange,
            L.PERCENTILE_RANGE,
            string.format(L.TOP_PERCENTILE_RANGE_VALUE, FormatPercent(topPercentile)),
            0.82,
            0.82,
            0.82
        )
    elseif percentileMin and percentileMax then
        local range = string.format(
            L.PERCENT_RANGE_VALUE,
            FormatPercent(percentileMin),
            FormatPercent(percentileMax)
        )
        SetRow(rows.percentileRange, L.PERCENTILE_RANGE, range, 0.82, 0.82, 0.82)
    else
        SetRow(rows.percentileRange, L.PERCENTILE_RANGE, "--", 0.65, 0.65, 0.65)
    end
end

function ns.RefreshHUDData()
    RefreshHUDData()
end

function ns.GetHUDSnapshot(refresh)
    if refresh ~= false then
        RefreshHUDData()
    end
    return hudSnapshot, GetDB().showRows
end

function ns.ApplyHUDStyle()
    if ns.RefreshMeetingStoneIntegration then
        ns.RefreshMeetingStoneIntegration("style")
    end
end

function ns.GetDB()
    return GetDB()
end

function ns.SetHUDShown(enabled)
    local currentDB = GetDB()
    currentDB.showHUD = enabled == true

    if ns.RefreshMeetingStoneIntegration then
        ns.RefreshMeetingStoneIntegration("visibility")
    end
end

function ns.IsTeleportAnnouncementEnabled()
    return GetDB().announceTeleport ~= false
end

function ns.SetTeleportAnnouncementEnabled(enabled)
    GetDB().announceTeleport = enabled == true
end

function ns.IsRunGainAnnouncementEnabled()
    return GetDB().announceRunGain ~= false
end

function ns.SetRunGainAnnouncementEnabled(enabled)
    GetDB().announceRunGain = enabled == true
end

function ns.IsMemberWelcomeEnabled()
    return GetDB().announceMemberJoin ~= false
end

function ns.SetMemberWelcomeEnabled(enabled)
    GetDB().announceMemberJoin = enabled == true
end

function ns.GetRunAnnounceDelay()
    return GetDB().announceDelay
end

function ns.SetRunAnnounceDelay(value)
    GetDB().announceDelay = Util.ClampNumber(value, 0, 60, DEFAULTS.announceDelay)
end

function ns.GetDailyBaselineScore()
    local state = GetDB().characters[GetCharacterKey()]
    if type(state) == "table"
        and state.dateKey == GetDateKey()
        and type(state.baselineScore) == "number"
    then
        return state.baselineScore
    end
    return nil
end

function ns.SetDetailEnabled(value)
    GetDB().enableMythicDetail = value == true
end

function ns.SetHUDBorderAlpha(value)
    GetDB().borderAlpha = Util.ClampNumber(value, 0, 1, DEFAULTS.borderAlpha)
end

function ns.SetHUDBackgroundAlpha(value)
    GetDB().backgroundAlpha = Util.ClampNumber(value, 0, 1, DEFAULTS.backgroundAlpha)
end

function ns.SetDetailBorderAlpha(value)
    GetDB().detailBorderAlpha = Util.ClampNumber(value, 0, 1, DEFAULTS.detailBorderAlpha)
end

function ns.SetDetailBackgroundAlpha(value)
    GetDB().detailBackgroundAlpha = Util.ClampNumber(value, 0, 1, DEFAULTS.detailBackgroundAlpha)
end

function ns.SetHUDBorderStyle(value)
    if value ~= "transparent" and value ~= "class" and value ~= "gold" then
        value = DEFAULTS.borderStyle
    end
    GetDB().borderStyle = value
end

function ns.SetRowVisible(key, value)
    if DEFAULT_ROW_VISIBILITY[key] ~= nil then
        GetDB().showRows[key] = value == true
        if ns.RefreshMeetingStoneIntegration then
            ns.RefreshMeetingStoneIntegration("profile")
        end
    end
end

function ns.GetHUDVisualSettings()
    local db = GetDB()
    local r, g, b, a = GetHUDAccentColor()
    return {
        borderStyle = db.borderStyle,
        borderR = r,
        borderG = g,
        borderB = b,
        borderAlpha = a,
        backgroundAlpha = db.backgroundAlpha,
    }
end

function ns.GetDetailVisualSettings()
    local db = GetDB()
    local r, g, b, a = GetDetailAccentColor()
    return {
        borderStyle = db.borderStyle,
        borderR = r,
        borderG = g,
        borderB = b,
        borderAlpha = a,
        backgroundAlpha = db.detailBackgroundAlpha,
    }
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")
        InitializeDatabase()
        ns.ResolveSelectedRegion()
        if not englishTextWarningPrinted
            and (L.SCORE ~= "M+ Score"
                or L.DETAIL_COLUMN_NAME ~= "Dungeon"
                or L.VAULT_RAID ~= "Raid")
        then
            englishTextWarningPrinted = true
            print(L.ADDON_TITLE .. ": English UI text was overwritten by another addon or an outdated build.")
        end
        if ns.InitializeSettings then
            ns.InitializeSettings()
        end
        local API = _G.QFXMythicRankData
        if API and type(API.RegisterCallback) == "function" then
            API:RegisterCallback(ns, function(_, region)
                local selectedRegion = ns.GetSelectedRegion() or ns.ResolveSelectedRegion()
                if ns.RefreshRegionSelector then
                    ns.RefreshRegionSelector()
                end
                if region == selectedRegion then
                    if ns.RefreshMeetingStoneIntegration then
                        ns.RefreshMeetingStoneIntegration("profile")
                    end
                end
            end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateDailyScoreStateOnly()
        if ns.HandleMythicDetailEvent then
            ns.HandleMythicDetailEvent(event, arg1)
        end
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(2, function()
                UpdateDailyScoreStateOnly()
            end)
        else
            UpdateDailyScoreStateOnly()
        end
        if ns.HandleMythicDetailEvent then
            ns.HandleMythicDetailEvent(event, arg1)
        end
    end
end)
