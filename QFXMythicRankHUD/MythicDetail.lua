local _, ns = ...
local L = ns.L
local Data = ns.MythicDetailData
local Resources = ns.MythicDetailResources
local Util = ns.Util
local RankTarget = ns.RankTarget

local detailFrame
local detailRefreshQueued = false
local detailEventsRegistered = false
local eventFrame
local RegisterDetailEvents
local RefreshCutoffTrendUI
local CLIENT_LOCALE = GetLocale()

local FRAME_WIDTH = 1100
local FRAME_HEIGHT = 680
local TABLE_WIDTH = 680
local SIDE_WIDTH = 360
local BODY_HEIGHT = 420
local FRAME_SIDE_PADDING = 20
local PANEL_GAP = 20
local TABLE_HEADER_HEIGHT = 52
local TABLE_ROW_HEIGHT = 31

local GOLD_R, GOLD_G, GOLD_B = 1.0, 0.82, 0.0
local GREEN_R, GREEN_G, GREEN_B = 0.35, 0.9, 0.45
local RED_R, RED_G, RED_B = 1.0, 0.35, 0.35
local MUTED_R, MUTED_G, MUTED_B = 0.65, 0.65, 0.65
local CYAN_R, CYAN_G, CYAN_B = 0.25, 0.85, 1.0
local DAY_MS = 86400000

local CUTOFF_LABEL_KEYS = {
    p999 = "DETAIL_CUTOFF_01",
    p990 = "DETAIL_CUTOFF_1",
    p900 = "DETAIL_CUTOFF_10",
    p750 = "DETAIL_CUTOFF_25",
    p600 = "DETAIL_CUTOFF_40",
}

local COLUMNS = {
    dungeon = { x = 0, width = 220 },
    level = { x = 220, width = 60 },
    score = { x = 280, width = 64 },
    seasonTotal = { x = 344, width = 56 },
    seasonTimed = { x = 400, width = 56 },
    seasonOvertime = { x = 456, width = 56 },
    weeklyTotal = { x = 512, width = 56 },
    weeklyTimed = { x = 568, width = 56 },
    weeklyOvertime = { x = 624, width = 56 },
}

local function FormatInteger(value)
    if type(value) ~= "number" then
        return "-"
    end
    return tostring(math.floor(value + 0.5))
end

local function FormatScore(value, decimals)
    if type(value) ~= "number" then
        return "-"
    end
    return string.format("%." .. tostring(decimals or 1) .. "f", value)
end

local function FormatPercent(value)
    if type(value) ~= "number" then
        return "-"
    end
    if math.abs(value - math.floor(value + 0.5)) < 0.005 then
        return tostring(math.floor(value + 0.5))
    end
    return string.format("%.1f", value)
end

local function FormatCompactRank(value)
    if type(value) ~= "number" then
        return "-"
    end
    if CLIENT_LOCALE == "zhCN" or CLIENT_LOCALE == "zhTW" then
        if value >= 10000 then
            return string.format("%.1f万", value / 10000)
        end
    elseif value >= 1000000 then
        return string.format("%.2fM", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.1fK", value / 1000)
    end
    return FormatInteger(value)
end

local function FormatResourceQuantity(value)
    if type(value) ~= "number" then
        return "-"
    end
    if CLIENT_LOCALE == "zhCN" and value >= 10000 then
        return string.format("%.1f万", value / 10000)
    elseif CLIENT_LOCALE == "zhTW" and value >= 10000 then
        return string.format("%.1f萬", value / 10000)
    elseif CLIENT_LOCALE ~= "zhCN" and CLIENT_LOCALE ~= "zhTW" then
        if value >= 1000000 then
            return string.format("%.2fM", value / 1000000)
        elseif value >= 1000 then
            return string.format("%.1fK", value / 1000)
        end
    end
    return FormatInteger(value)
end

local function GetDataDate(dataVersion)
    if type(dataVersion) ~= "string" then
        return L.DETAIL_DATA_UNAVAILABLE
    end
    local year, month, day = dataVersion:match("^(%d%d%d%d)(%d%d)(%d%d)")
    if not year or not month or not day then
        return L.DETAIL_DATA_UNAVAILABLE
    end
    return string.format(L.DATA_DATE_FORMAT, tonumber(year), tonumber(month), tonumber(day))
end

local function GetCurrentTimestamp()
    if type(GetServerTime) == "function" then
        local value = Util.SafeNumber(GetServerTime())
        if value then
            return value
        end
    end
    return type(time) == "function" and Util.SafeNumber(time()) or nil
end

local function GetSeasonAgeText(seasonInfo)
    local startsAt = seasonInfo and Util.SafeNumber(seasonInfo.startsAt) or nil
    if not startsAt then
        return nil
    end
    local now = GetCurrentTimestamp()
    if not now then
        return nil
    end
    local endsAt = Util.SafeNumber(seasonInfo.endsAt)
    local state = Util.SafeString(seasonInfo.state)
    if state == "upcoming" or now < startsAt then
        return L.DETAIL_SEASON_NOT_STARTED
    end
    if state == "ended" or (endsAt and now > endsAt) then
        if endsAt then
            local totalDays = math.floor(math.max(0, endsAt - startsAt) / 86400)
            return string.format(L.DETAIL_SEASON_ENDED_DAYS, totalDays)
        end
        return L.DETAIL_SEASON_ENDED
    end
    local elapsedDays = math.floor(math.max(0, now - startsAt) / 86400)
    return string.format(L.DETAIL_SEASON_ACTIVE_DAYS, elapsedDays)
end

local function GetRankText(ranking)
    if not ranking.available then
        return "-"
    end
    if ranking.inTop01 and ranking.topRankMax then
        return string.format(L.TOP_RANK_VALUE, FormatInteger(ranking.topRankMax))
    end
    if ranking.estimatedRank then
        return string.format(L.APPROX_RANK, FormatInteger(ranking.estimatedRank))
    end
    if ranking.rankMin and ranking.rankMax then
        local range = string.format(
            L.RANGE_JOIN,
            FormatCompactRank(ranking.rankMin),
            FormatCompactRank(ranking.rankMax)
        )
        return string.format(L.APPROX_RANK, range)
    end
    return "-"
end

local function GetSurpassedText(ranking)
    if not ranking.available then
        return "-"
    end
    if ranking.surpassedAtLeast then
        return string.format(L.SURPASSED_AT_LEAST, FormatPercent(ranking.surpassedAtLeast))
    end
    if ranking.surpassed then
        return string.format(L.APPROX, FormatPercent(ranking.surpassed) .. "%")
    end
    if ranking.surpassedMin and ranking.surpassedMax then
        local range = string.format(
            L.RANGE_JOIN,
            FormatPercent(ranking.surpassedMin) .. "%",
            FormatPercent(ranking.surpassedMax) .. "%"
        )
        return string.format(L.APPROX, range)
    end
    return "-"
end

local function GetBracketText(ranking)
    if not ranking.available then
        return "-"
    end
    if ranking.bracketKind == "top" then
        return string.format(L.TOP_PERCENTILE_RANGE_VALUE, "0.1")
    elseif ranking.bracketKind == "below" then
        return L.DETAIL_BELOW_TOP_40
    elseif ranking.bracketKind == "between" then
        return string.format(L.DETAIL_BRACKET_VALUE, ranking.bracketLow, ranking.bracketHigh)
    end
    return "-"
end

local function GetRankRangeText(ranking)
    if not ranking.available then
        return "-"
    end
    if ranking.inTop01 and ranking.topRankMax then
        return string.format(L.TOP_RANK_RANGE_VALUE, FormatInteger(ranking.topRankMax))
    end
    if ranking.rankMin and ranking.rankMax then
        return string.format(
            L.RANGE_JOIN,
            FormatCompactRank(ranking.rankMin),
            FormatCompactRank(ranking.rankMax)
        )
    end
    return "-"
end

local function GetNextCutoffText(ranking)
    local target = ranking and ranking.smartTarget or nil
    if not ranking.available or not target then
        return "-"
    end
    if target.mode == "complete" then
        return L.DETAIL_TARGET_COMPLETE
    end
    local name
    if target.targetKind == "bracket" then
        name = string.format(L.TOP_PERCENT, target.targetPercent)
    elseif target.targetKind == "cutoff" then
        name = string.format(L.SMART_CUTOFF_LINE_FORMAT, target.targetPercent)
    else
        name = target.targetName
    end
    return string.format(L.CUTOFF_VALUE, name or "-", FormatScore(target.targetScore, 1))
end

local function GetDistanceText(ranking)
    local target = ranking and ranking.smartTarget or nil
    if not ranking.available or not target then
        return "-"
    end
    return string.format(L.SCORE_POINTS, FormatScore(target.distance or 0, 1))
end

local function SetValueColor(fontString, colorKind)
    if colorKind == "timed" then
        fontString:SetTextColor(GREEN_R, GREEN_G, GREEN_B)
    elseif colorKind == "overtime" then
        fontString:SetTextColor(RED_R, RED_G, RED_B)
    elseif colorKind == "gold" then
        fontString:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
    elseif colorKind == "cyan" then
        fontString:SetTextColor(CYAN_R, CYAN_G, CYAN_B)
    elseif colorKind == "muted" then
        fontString:SetTextColor(MUTED_R, MUTED_G, MUTED_B)
    else
        fontString:SetTextColor(1, 1, 1)
    end
end

local function SetStatValue(fontString, value, colorKind)
    fontString:SetText(value ~= nil and FormatInteger(value) or "-")
    SetValueColor(fontString, value ~= nil and colorKind or "muted")
end

local function CreateInfoLine(parent, y, width, labelText, labelRatio)
    local line = {}
    local ratio = labelRatio or 0.48
    line.label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    line.label:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    line.label:SetWidth(width * ratio)
    line.label:SetJustifyH("LEFT")
    line.label:SetWordWrap(false)
    line.label:SetText(labelText)
    line.label:SetTextColor(0.72, 0.72, 0.72)

    line.value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.value:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    line.value:SetWidth(width * (1 - ratio) - 4)
    line.value:SetJustifyH("RIGHT")
    line.value:SetWordWrap(false)
    return line
end

local function CreateHeaderText(parent, text, x, y, width, justify, isGroup)
    local fontString = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fontString:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fontString:SetWidth(width)
    fontString:SetJustifyH(justify or "CENTER")
    fontString:SetWordWrap(false)
    fontString:SetText(text)
    if isGroup then
        fontString:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
    else
        fontString:SetTextColor(0.82, 0.82, 0.82)
    end
    return fontString
end

local function SetRowBackground(row, backgroundAlpha, hovered)
    if row.isSummary then
        row.background:SetColorTexture(0.04, 0.18, 0.28, backgroundAlpha * 0.18)
    else
        local base = row.rowIndex % 2 == 0 and 0.055 or 0.02
        row.background:SetColorTexture(1, 1, 1, backgroundAlpha * (hovered and 0.10 or base))
    end
end

local function CreateNumericCell(row, column)
    local fontString = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fontString:SetPoint("LEFT", row, "LEFT", column.x, 0)
    fontString:SetWidth(column.width)
    fontString:SetJustifyH("CENTER")
    fontString:SetWordWrap(false)
    return fontString
end

local function CreateStatRow(parent, index, isSummary)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(TABLE_WIDTH, TABLE_ROW_HEIGHT)
    row.isSummary = isSummary
    row.rowIndex = index

    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    SetRowBackground(row, 0.90, false)
    if not isSummary then
        row:SetScript("OnEnter", function(self)
            SetRowBackground(self, detailFrame and detailFrame.detailBackgroundAlpha or 0.90, true)
            if self.fullDungeonName
                and type(self.name.IsTruncated) == "function"
                and self.name:IsTruncated()
            then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.fullDungeonName, 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            SetRowBackground(self, detailFrame and detailFrame.detailBackgroundAlpha or 0.90, false)
            GameTooltip_Hide()
        end)
    end

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 36, 0)
    row.name:SetWidth(COLUMNS.dungeon.width - 42)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.level = CreateNumericCell(row, COLUMNS.level)
    row.score = CreateNumericCell(row, COLUMNS.score)
    row.seasonTotal = CreateNumericCell(row, COLUMNS.seasonTotal)
    row.seasonTimed = CreateNumericCell(row, COLUMNS.seasonTimed)
    row.seasonOvertime = CreateNumericCell(row, COLUMNS.seasonOvertime)
    row.weeklyTotal = CreateNumericCell(row, COLUMNS.weeklyTotal)
    row.weeklyTimed = CreateNumericCell(row, COLUMNS.weeklyTimed)
    row.weeklyOvertime = CreateNumericCell(row, COLUMNS.weeklyOvertime)
    return row
end

local function ApplyScale()
    if not detailFrame then
        return
    end
    local parentWidth = UIParent:GetWidth() or FRAME_WIDTH
    local parentHeight = UIParent:GetHeight() or FRAME_HEIGHT
    local fitScale = math.min(1, (parentWidth - 24) / FRAME_WIDTH, (parentHeight - 24) / FRAME_HEIGHT)
    detailFrame:SetScale(math.max(0.1, fitScale))
end

local function ApplyPosition()
    if not detailFrame then
        return
    end
    local db = ns.GetDB()
    detailFrame:ClearAllPoints()
    detailFrame:SetPoint(
        db.detailPoint or "CENTER",
        UIParent,
        db.detailRelativePoint or "CENTER",
        db.detailX or 0,
        db.detailY or 0
    )
end

local function SavePosition()
    if not detailFrame then
        return
    end
    local point, _, relativePoint, x, y = detailFrame:GetPoint(1)
    local db = ns.GetDB()
    db.detailPoint = point or "CENTER"
    db.detailRelativePoint = relativePoint or "CENTER"
    db.detailX = x or 0
    db.detailY = y or 0
end

local function ApplyVisualSettings()
    if not detailFrame then
        return
    end
    local visual = ns.GetDetailVisualSettings and ns.GetDetailVisualSettings() or nil
    local borderR = visual and visual.borderR or 0.72
    local borderG = visual and visual.borderG or 0.56
    local borderB = visual and visual.borderB or 0.18
    local borderAlpha = visual and visual.borderAlpha or 1.00
    local backgroundAlpha = visual and visual.backgroundAlpha or 0.90
    detailFrame.detailBackgroundAlpha = backgroundAlpha
    detailFrame:SetBackdropColor(0.035, 0.035, 0.045, backgroundAlpha)
    detailFrame:SetBackdropBorderColor(borderR, borderG, borderB, borderAlpha)
    detailFrame.title:SetTextColor(borderR, borderG, borderB)
    detailFrame.progress:SetStatusBarColor(borderR, borderG, borderB, 0.9)

    for _, background in ipairs(detailFrame.backgroundLayers) do
        background.texture:SetColorTexture(1, 1, 1, backgroundAlpha * background.multiplier)
    end

    local tableUI = detailFrame.tableUI
    for _, row in ipairs(tableUI.rows) do
        SetRowBackground(row, backgroundAlpha, false)
    end
    SetRowBackground(tableUI.summary, backgroundAlpha, false)
    if detailFrame.sideUI and detailFrame.sideUI.trendChart and RefreshCutoffTrendUI then
        detailFrame.sideUI.trendChart.background:SetColorTexture(
            0.01,
            0.01,
            0.015,
            backgroundAlpha * 0.22
        )
        RefreshCutoffTrendUI()
    end
end

local function EnsureMapRows(count)
    local tableUI = detailFrame.tableUI
    for index = #tableUI.rows + 1, count do
        local row = tableUI.rows[index]
        if not row then
            row = CreateStatRow(detailFrame.tablePanel, index, false)
            tableUI.rows[index] = row
            SetRowBackground(row, detailFrame.detailBackgroundAlpha or 0.90, false)
        end
    end
end

local function RefreshDungeonTable()
    local mapMeta = Data.GetCachedSection("mapMeta")
    local score = Data.GetCachedSection("score")
    local maps = mapMeta and mapMeta.ordered or {}
    local tableUI = detailFrame.tableUI
    EnsureMapRows(#maps)

    for index, mapInfo in ipairs(maps) do
        local row = tableUI.rows[index]
        local scoreInfo = score and score.maps[mapInfo.mapID] or nil
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", detailFrame.tablePanel, "TOPLEFT", 0, -TABLE_HEADER_HEIGHT - ((index - 1) * TABLE_ROW_HEIGHT))

        if mapInfo.texture then
            row.icon:SetTexture(mapInfo.texture)
            row.icon:Show()
        else
            row.icon:Hide()
        end
        row.fullDungeonName = mapInfo.name or "-"
        row.name:SetText(row.fullDungeonName)
        local level = scoreInfo and scoreInfo.level or nil
        local dungeonScore = scoreInfo and scoreInfo.dungeonScore or nil
        row.level:SetText(level ~= nil and string.format(L.DETAIL_LEVEL_VALUE, FormatInteger(level)) or "-")
        row.score:SetText(dungeonScore ~= nil and FormatScore(dungeonScore, 1) or "-")
        SetValueColor(row.level, level ~= nil and "gold" or "muted")
        SetValueColor(row.score, dungeonScore ~= nil and nil or "muted")
        row:Show()
    end

    for index = #maps + 1, #tableUI.rows do
        tableUI.rows[index]:Hide()
    end

    tableUI.empty:SetShown(#maps == 0)
    local summary = tableUI.summary
    if #maps > 0 then
        summary:ClearAllPoints()
        summary:SetPoint("TOPLEFT", detailFrame.tablePanel, "TOPLEFT", 0, -TABLE_HEADER_HEIGHT - (#maps * TABLE_ROW_HEIGHT))
        summary.icon:Hide()
        summary.name:SetText(L.DETAIL_STAT_SUMMARY)
        SetValueColor(summary.name, "cyan")
        local highestLevel = score and score.highestLevel or nil
        summary.level:SetText(highestLevel and string.format(L.DETAIL_LEVEL_VALUE, FormatInteger(highestLevel)) or "-")
        SetValueColor(summary.level, highestLevel and "gold" or "muted")
        summary.score:SetText("-")
        SetValueColor(summary.score, "muted")
        summary:Show()
    else
        summary:Hide()
    end
    if tableUI.regionSelector then
        tableUI.regionSelector:ClearAllPoints()
        tableUI.regionSelector:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 36, -8)
        tableUI.regionSelector:Show()
    end
end

local function RefreshSeasonStatisticsUI()
    local mapMeta = Data.GetCachedSection("mapMeta")
    local section = Data.GetCachedSection("seasonStats")
    for index, mapInfo in ipairs(mapMeta and mapMeta.ordered or {}) do
        local row = detailFrame.tableUI.rows[index]
        local stats = section and section.byMapID[mapInfo.mapID] or nil
        SetStatValue(row.seasonTotal, stats and stats.seasonTotal or nil, nil)
        SetStatValue(row.seasonTimed, stats and stats.seasonTimed or nil, "timed")
        SetStatValue(row.seasonOvertime, stats and stats.seasonOvertime or nil, "overtime")
    end
    local summary = section and section.summary or {}
    local summaryRow = detailFrame.tableUI.summary
    SetStatValue(summaryRow.seasonTotal, summary.seasonTotal, nil)
    SetStatValue(summaryRow.seasonTimed, summary.seasonTimed, "timed")
    SetStatValue(summaryRow.seasonOvertime, summary.seasonOvertime, "overtime")
end

local function RefreshWeeklyStatisticsUI()
    local mapMeta = Data.GetCachedSection("mapMeta")
    local section = Data.GetCachedSection("weeklyStats")
    for index, mapInfo in ipairs(mapMeta and mapMeta.ordered or {}) do
        local row = detailFrame.tableUI.rows[index]
        local stats = section and section.byMapID[mapInfo.mapID] or nil
        SetStatValue(row.weeklyTotal, stats and stats.weeklyTotal or nil, nil)
        SetStatValue(row.weeklyTimed, stats and stats.weeklyTimed or nil, "timed")
        SetStatValue(row.weeklyOvertime, stats and stats.weeklyOvertime or nil, "overtime")
    end
    local summary = section and section.summary or {}
    local summaryRow = detailFrame.tableUI.summary
    SetStatValue(summaryRow.weeklyTotal, summary.weeklyTotal, nil)
    SetStatValue(summaryRow.weeklyTimed, summary.weeklyTimed, "timed")
    SetStatValue(summaryRow.weeklyOvertime, summary.weeklyOvertime, "overtime")
end

local function PositionSideTitle(title, cursor)
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", detailFrame.sidePanel, "TOPLEFT", 0, -cursor)
    return cursor + 22
end

local function PositionSideRow(row, cursor)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", detailFrame.sidePanel, "TOPLEFT", 4, -cursor)
    return cursor + 19
end

local function ApplySidePanelLayout()
    local side = detailFrame.sideUI
    local cursor = 2

    side.keyLine:ClearAllPoints()
    side.keyLine:SetPoint("TOPLEFT", detailFrame.sidePanel, "TOPLEFT", 0, -cursor)
    cursor = cursor + 22
    cursor = cursor + 8

    cursor = PositionSideTitle(side.vaultTitle, cursor)
    for _, row in ipairs(side.vaultRows) do
        cursor = PositionSideRow(row, cursor)
    end
    cursor = cursor + 10

    side.trendTitle:ClearAllPoints()
    side.trendTitle:SetPoint("TOPLEFT", detailFrame.sidePanel, "TOPLEFT", 0, -cursor)
    side.trendPeriodDropdown:ClearAllPoints()
    side.trendPeriodDropdown:SetPoint("TOPRIGHT", detailFrame.sidePanel, "TOPRIGHT", -2, -cursor + 1)
    cursor = cursor + 23
    side.trendButtonBar:ClearAllPoints()
    side.trendButtonBar:SetPoint("TOPLEFT", detailFrame.sidePanel, "TOPLEFT", 0, -cursor)
    cursor = cursor + 24
    side.trendSummary:ClearAllPoints()
    side.trendSummary:SetPoint("TOPLEFT", detailFrame.sidePanel, "TOPLEFT", 0, -cursor)
    cursor = cursor + 22
    side.trendChart.frame:ClearAllPoints()
    side.trendChart.frame:SetPoint("TOPLEFT", detailFrame.sidePanel, "TOPLEFT", 4, -cursor)
    side.trendChart.frame:SetSize(SIDE_WIDTH - 8, BODY_HEIGHT - cursor)
end

local function RefreshKeystoneUI()
    local section = Data.GetCachedSection("keystone")
    local keystone = section and section.data or nil
    local value = detailFrame.sideUI.keyValue
    if keystone and keystone.name and keystone.level then
        value:SetText(string.format(L.DETAIL_KEY_VALUE, keystone.name, FormatInteger(keystone.level)))
        SetValueColor(value, "gold")
    elseif keystone then
        value:SetText("-")
        SetValueColor(value, "muted")
    else
        value:SetText(L.DETAIL_NO_KEY)
        SetValueColor(value, "muted")
    end
end

local function RefreshVaultUI()
    local section = Data.GetCachedSection("vault")
    local side = detailFrame.sideUI
    local categories = section and section.categories or {}
    local keys = { "raid", "mythicPlus", "world" }
    for index, key in ipairs(keys) do
        local row = side.vaultRows[index]
        local category = categories[key]
        local available = category and category.available == true
        local fallbackMaximum = key == "raid" and 6 or 8
        local maximum = math.max(1, Util.SafeNumber(category and category.maximum) or fallbackMaximum)
        local progress = available and Util.ClampNumber(category.progress, 0, maximum, 0) or 0
        row.bar:SetMinMaxValues(0, maximum)
        row.bar:SetValue(progress)
        if not available then
            row.bar:SetStatusBarColor(MUTED_R, MUTED_G, MUTED_B, 0.45)
            row.value:SetText("--/" .. FormatInteger(maximum))
            SetValueColor(row.value, "muted")
        elseif progress >= maximum then
            row.bar:SetStatusBarColor(GREEN_R, GREEN_G, GREEN_B, 0.9)
            row.value:SetText(FormatInteger(progress) .. "/" .. FormatInteger(maximum))
            SetValueColor(row.value, "timed")
        else
            row.bar:SetStatusBarColor(GOLD_R, GOLD_G, GOLD_B, 0.9)
            row.value:SetText(FormatInteger(progress) .. "/" .. FormatInteger(maximum))
            SetValueColor(row.value, "gold")
        end
        row:Show()
    end
end

local function FormatSignedScore(value)
    value = Util.SafeNumber(value) or 0
    if value > 0 then
        return "+" .. FormatScore(value, 1)
    end
    return FormatScore(value, 1)
end

local function GetTrendDateParts(timestampMs)
    local timestamp = Util.SafeNumber(timestampMs)
    if not timestamp or type(date) ~= "function" then
        return nil
    end
    return date("*t", timestamp / 1000)
end

local function FormatTrendDate(timestampMs, longFormat)
    local parts = GetTrendDateParts(timestampMs)
    if not parts then
        return "-"
    end
    if longFormat then
        return string.format(L.DATA_DATE_FORMAT, parts.year, parts.month, parts.day)
    end
    return string.format("%d/%d", parts.month, parts.day)
end

local function GetVisibleTrendPoints(series, periodDays)
    local source = series and type(series.points) == "table" and series.points or {}
    local result = {}
    if periodDays == 7 and #source > 0 then
        local latestTimestamp = source[#source].timestampMs
        local threshold = latestTimestamp - (6 * DAY_MS)
        for _, point in ipairs(source) do
            if point.timestampMs >= threshold then
                result[#result + 1] = point
            end
        end
        if #result < 2 then
            Util.WipeArray(result)
            for index = math.max(1, #source - 6), #source do
                result[#result + 1] = source[index]
            end
        end
        while #result > 7 do
            table.remove(result, 1)
        end
    else
        for index = math.max(1, #source - 29), #source do
            result[#result + 1] = source[index]
        end
    end
    return result
end

local function GetMajorTrendIndexes(points, periodDays)
    local indexes = {}
    if periodDays == 7 then
        for index = 1, #points do
            indexes[index] = true
        end
        return indexes
    end
    if #points == 0 then
        return indexes
    end
    indexes[1] = true
    indexes[#points] = true
    local latest = points[#points].timestampMs
    for _, daysAgo in ipairs({ 21, 14, 7 }) do
        local target = latest - (daysAgo * DAY_MS)
        local closestIndex
        local closestDistance
        for index, point in ipairs(points) do
            local distance = math.abs(point.timestampMs - target)
            if not closestDistance or distance < closestDistance then
                closestIndex = index
                closestDistance = distance
            end
        end
        if closestIndex then
            indexes[closestIndex] = true
        end
    end
    return indexes
end

local function HideTrendObjects(chart)
    for _, collection in ipairs({ chart.lines, chart.nodes, chart.hitFrames, chart.scoreLabels, chart.dateLabels }) do
        for _, object in ipairs(collection) do
            object:Hide()
        end
    end
    chart.status:Hide()
end

local function ShowTrendTooltip(hitFrame)
    local point = hitFrame.point
    local series = hitFrame.series
    if not point or not series then
        return
    end
    GameTooltip:SetOwner(hitFrame, "ANCHOR_RIGHT")
    local label = L[CUTOFF_LABEL_KEYS[series.key]] or series.percent or "-"
    GameTooltip:SetText(string.format(L.DETAIL_TREND_CUTOFF_TOOLTIP, label), GOLD_R, GOLD_G, GOLD_B)
    GameTooltip:AddLine(string.format(L.DETAIL_TREND_DATE, FormatTrendDate(point.timestampMs, true)), 1, 1, 1)
    GameTooltip:AddLine(string.format(L.DETAIL_TREND_SCORE, FormatScore(point.score, 1)), 1, 1, 1)
    if hitFrame.previousPoint then
        GameTooltip:AddLine(
            string.format(L.DETAIL_TREND_PREVIOUS_CHANGE, FormatSignedScore(point.score - hitFrame.previousPoint.score)),
            0.9, 0.75, 0.35
        )
    end
    if point.population then
        GameTooltip:AddLine(string.format(L.DETAIL_TREND_POPULATION, FormatInteger(point.population)), 0.75, 0.75, 0.75)
    end
    GameTooltip:Show()
end

local function RefreshCutoffTrendButtons(series)
    local side = detailFrame.sideUI
    for key, button in pairs(side.trendButtons) do
        local selected = key == side.trendState.cutoffKey
        local buttonSeries = Data.GetCachedSection("cutoffHistory").seriesByKey[key]
        local r, g, b = Util.HexColorToRGB(buttonSeries and buttonSeries.color, GOLD_R, GOLD_G, GOLD_B)
        button.selectedBackground:SetColorTexture(r, g, b, selected and 0.20 or 0)
        if selected then
            button.text:SetTextColor(r, g, b)
        else
            button.text:SetTextColor(0.78, 0.78, 0.78)
        end
    end
    local periodText = side.trendState.periodDays == 30 and L.DETAIL_TREND_30_DAYS or L.DETAIL_TREND_7_DAYS
    if side.trendPeriodDropdown.SetText then
        side.trendPeriodDropdown:SetText(periodText)
    elseif side.trendPeriodDropdown.Text then
        side.trendPeriodDropdown.Text:SetText(periodText)
    end
end

local function RefreshCutoffTrendSummary(series, points)
    local side = detailFrame.sideUI
    local current = side.trendSummary.current
    local change = side.trendSummary.change
    if #points == 0 then
        current:SetText("")
        change:SetText("")
        return
    end
    current:SetText(string.format(L.DETAIL_TREND_CURRENT, FormatScore(points[#points].score, 1)))
    local delta = #points >= 2 and points[#points].score - points[1].score or nil
    if delta then
        local coveredDays = math.max(
            1,
            math.floor((points[#points].timestampMs - points[1].timestampMs) / DAY_MS) + 1
        )
        local shownDays = math.min(side.trendState.periodDays, coveredDays)
        change:SetText(string.format(L.DETAIL_TREND_PERIOD_CHANGE, shownDays, FormatSignedScore(delta)))
        if delta > 0 then
            change:SetTextColor(1.0, 0.67, 0.28)
        elseif delta < 0 then
            change:SetTextColor(GREEN_R, GREEN_G, GREEN_B)
        else
            change:SetTextColor(MUTED_R, MUTED_G, MUTED_B)
        end
    else
        change:SetText("")
    end
end

local function GetTrendScoreLabelY(positionY, index, chartHeight, bottomPadding)
    local aboveY = positionY + 14
    local belowY = positionY - 16
    local minimumY = bottomPadding + 5
    local maximumY = chartHeight - 10
    local y = index % 2 == 1 and aboveY or belowY
    if y > maximumY then
        y = belowY
    end
    if y < minimumY then
        y = aboveY
    end
    return Util.ClampNumber(y, minimumY, maximumY, positionY)
end

local function RefreshCutoffTrendChart(series, points)
    local side = detailFrame.sideUI
    local chart = side.trendChart
    HideTrendObjects(chart)
    if #points == 0 then
        chart.status:SetText(L.DETAIL_TREND_NO_DATA)
        chart.status:Show()
        return
    end

    local width, height = chart.frame:GetSize()
    width = width > 0 and width or (SIDE_WIDTH - 8)
    height = height > 0 and height or 185
    local leftPadding, rightPadding, topPadding, bottomPadding = 14, 14, 22, 34
    local drawableWidth = width - leftPadding - rightPadding
    local drawableHeight = height - topPadding - bottomPadding
    local firstTimestamp = points[1].timestampMs
    local lastTimestamp = points[#points].timestampMs
    local minScore, maxScore = points[1].score, points[1].score
    for _, point in ipairs(points) do
        minScore = math.min(minScore, point.score)
        maxScore = math.max(maxScore, point.score)
    end
    local scoreRange = maxScore - minScore
    local displayMin, displayMax
    if scoreRange < 0.1 then
        displayMin, displayMax = minScore - 1, maxScore + 1
    else
        local verticalPadding = math.max(scoreRange * 0.12, 1.0)
        displayMin, displayMax = minScore - verticalPadding, maxScore + verticalPadding
    end

    local positions = {}
    for index, point in ipairs(points) do
        local x
        if lastTimestamp == firstTimestamp then
            x = leftPadding + (#points > 1 and ((index - 1) / (#points - 1)) * drawableWidth or drawableWidth / 2)
        else
            x = leftPadding + ((point.timestampMs - firstTimestamp) / (lastTimestamp - firstTimestamp)) * drawableWidth
        end
        local y = bottomPadding + ((point.score - displayMin) / (displayMax - displayMin)) * drawableHeight
        positions[index] = { x = x, y = y }
    end

    local r, g, b = Util.HexColorToRGB(series and series.color, GOLD_R, GOLD_G, GOLD_B)
    for index = 1, #points - 1 do
        local line = chart.lines[index]
        line:SetColorTexture(r, g, b, 0.95)
        line:SetStartPoint("BOTTOMLEFT", chart.frame, positions[index].x, positions[index].y)
        line:SetEndPoint("BOTTOMLEFT", chart.frame, positions[index + 1].x, positions[index + 1].y)
        line:Show()
    end

    local majorIndexes = GetMajorTrendIndexes(points, side.trendState.periodDays)
    for index, point in ipairs(points) do
        local position = positions[index]
        local isMajor = majorIndexes[index] == true
        local node = chart.nodes[index]
        node:SetColorTexture(r, g, b, isMajor and 1 or 0.65)
        node:SetSize(isMajor and 6 or 3, isMajor and 6 or 3)
        node:ClearAllPoints()
        node:SetPoint("CENTER", chart.frame, "BOTTOMLEFT", position.x, position.y)
        node:Show()

        local hit = chart.hitFrames[index]
        hit:ClearAllPoints()
        hit:SetPoint("CENTER", chart.frame, "BOTTOMLEFT", position.x, position.y)
        hit.point = point
        hit.previousPoint = index > 1 and points[index - 1] or nil
        hit.series = series
        hit:Show()

        if isMajor then
            local scoreLabel = chart.scoreLabels[index]
            scoreLabel:ClearAllPoints()
            local labelX = Util.ClampNumber(position.x, 32, width - 32, position.x)
            local labelY = GetTrendScoreLabelY(position.y, index, height, bottomPadding)
            scoreLabel:SetPoint("CENTER", chart.frame, "BOTTOMLEFT", labelX, labelY)
            scoreLabel:SetText(FormatScore(point.score, 1))
            scoreLabel:Show()
            local dateLabel = chart.dateLabels[index]
            dateLabel:ClearAllPoints()
            local dateX = Util.ClampNumber(position.x, 24, width - 24, position.x)
            dateLabel:SetPoint("CENTER", chart.frame, "BOTTOMLEFT", dateX, 8)
            dateLabel:SetText(FormatTrendDate(point.timestampMs, false))
            dateLabel:Show()
        end
    end

    if #points == 1 then
        chart.status:SetText(L.DETAIL_TREND_INSUFFICIENT_DATA)
        chart.status:Show()
    end
end

RefreshCutoffTrendUI = function()
    if not detailFrame then
        return
    end
    local side = detailFrame.sideUI
    local section = Data.GetCachedSection("cutoffHistory")
    local series = section and section.seriesByKey[side.trendState.cutoffKey] or nil
    local points = GetVisibleTrendPoints(series, side.trendState.periodDays)
    RefreshCutoffTrendButtons(series)
    RefreshCutoffTrendSummary(series, points)
    RefreshCutoffTrendChart(series, points)
end

local function UpdateResourceCell(key, resource)
    local button = detailFrame.resourceUI.byKey[key]
    if not button then
        return
    end
    button.resource = resource
    local available = resource and resource.discovered == true and resource.quantity ~= nil
    button.icon:SetTexture(resource and resource.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    button.icon:SetDesaturated(not available)
    button.icon:SetAlpha(available and 1 or 0.42)
    button.quantity:SetText(available and FormatResourceQuantity(resource.quantity) or "-")
    SetValueColor(button.quantity, available and nil or "muted")
end

local function RefreshResourceUI()
    local section = Data.GetCachedSection("resources")
    local resources = section and section.ordered or {}
    for index, button in ipairs(detailFrame.resourceUI.buttons) do
        local resource = resources[index]
        UpdateResourceCell(button.resourceKey, resource)
    end
end

local function RefreshDetailHeader()
    local scoreSection = Data.GetCachedSection("score")
    local seasonInfo = Data.GetCachedSection("seasonInfo")
    local rankingSection = Data.GetCachedSection("ranking")
    local score = scoreSection and scoreSection.overall or nil
    local ranking = rankingSection and rankingSection.result or { available = false }
    detailFrame.dataDate:SetText(string.format(
        L.DATA_UPDATED,
        GetDataDate(ranking.dataVersion or (seasonInfo and seasonInfo.dataVersion))
    ))
    detailFrame.dataSource:SetText(L.DATA_SOURCE)
    local regionLabel = ns.GetSelectedRegionLabel()
    local unavailableText = regionLabel and string.format(L.DETAIL_REGION_DATA_UNAVAILABLE, regionLabel)
        or L.DETAIL_DATA_UNAVAILABLE
    detailFrame.rankDataStatus:SetText(ranking.available and "" or unavailableText)
    detailFrame.rankLine.label:SetText(regionLabel
        and string.format(L.DETAIL_ESTIMATED_REGION_RANK, regionLabel)
        or L.SETTINGS_ROW_REGION_RANK)
    if ns.RefreshRegionSelector then
        ns.RefreshRegionSelector()
    end

    detailFrame.scoreValue:SetText(score ~= nil and FormatScore(score, 1) or "-")
    local overallColor = scoreSection and Util.SafeString(scoreSection.overallColor)
    if score ~= nil and overallColor then
        local r, g, b = Util.HexColorToRGB(overallColor, GOLD_R, GOLD_G, GOLD_B)
        detailFrame.scoreValue:SetTextColor(r, g, b)
    elseif score ~= nil then
        SetValueColor(detailFrame.scoreValue, "gold")
    else
        SetValueColor(detailFrame.scoreValue, "muted")
    end
    if seasonInfo and seasonInfo.shortName then
        detailFrame.scoreLabel:SetText(string.format(L.DETAIL_SEASON_SCORE_FORMAT, seasonInfo.shortName))
    else
        detailFrame.scoreLabel:SetText(L.DETAIL_CURRENT_SEASON_SCORE)
    end
    local seasonAgeText = GetSeasonAgeText(seasonInfo)
    detailFrame.seasonAgeText:SetText(seasonAgeText or "")
    detailFrame.seasonAgeText:SetShown(seasonAgeText ~= nil)
    detailFrame.rankLine.value:SetText(GetRankText(ranking))
    detailFrame.surpassedLine.value:SetText(GetSurpassedText(ranking))
    detailFrame.bracketLine.value:SetText(GetBracketText(ranking))
    detailFrame.rankRangeLine.value:SetText(GetRankRangeText(ranking))
    detailFrame.nextLine.value:SetText(GetNextCutoffText(ranking))
    detailFrame.distanceLine.value:SetText(GetDistanceText(ranking))

    local smartTarget = ranking.smartTarget
    detailFrame.nextLine.label:SetText(
        smartTarget and smartTarget.mode == "score" and L.DETAIL_SCORE_TARGET or L.DETAIL_BRACKET_TARGET
    )
    detailFrame.distanceLine.label:SetText(L.DETAIL_DISTANCE_TO_TARGET)
    if smartTarget and smartTarget.progress ~= nil then
        detailFrame.progress:SetValue(smartTarget.progress)
        local r, g, b = Util.HexColorToRGB(smartTarget.color, GOLD_R, GOLD_G, GOLD_B)
        detailFrame.progress:SetStatusBarColor(r, g, b, 0.9)
        detailFrame.progress:Show()
        detailFrame.progressBackground:Show()
    else
        detailFrame.progress:Hide()
        detailFrame.progressBackground:Hide()
    end
end

local function RefreshDirtyDetailSections()
    if not detailFrame or not detailFrame:IsShown() or not Data then
        return
    end
    local refreshDungeon
    local refreshHeader
    local refreshSeasonInfo
    local refreshCutoffHistory
    local refreshSeason
    local refreshWeekly
    local refreshKeystone
    local refreshVault
    local refreshResources

    if Data.IsDirty("mapMeta") then
        Data.RefreshMapMetadata()
        refreshDungeon = true
    end
    if Data.IsDirty("score") then
        Data.RefreshScoreData()
        refreshDungeon = true
        refreshHeader = true
    end
    if Data.IsDirty("seasonInfo") then
        Data.RefreshSeasonInfo()
        refreshSeasonInfo = true
    end
    if Data.IsDirty("ranking") then
        Data.RefreshRankingData()
        refreshHeader = true
    end
    if Data.IsDirty("cutoffHistory") then
        Data.RefreshCutoffHistory()
        refreshCutoffHistory = true
    end
    if Data.IsDirty("seasonStats") then
        Data.RefreshSeasonStatistics()
        refreshSeason = true
    end
    if Data.IsDirty("weeklyStats") then
        Data.RefreshWeeklyStatistics()
        refreshWeekly = true
    end
    if Data.IsDirty("keystone") then
        Data.RefreshKeystone()
        refreshKeystone = true
    end
    if Data.IsDirty("vault") then
        Data.RefreshVault()
        refreshVault = true
    end
    if Data.IsDirty("resources") then
        Data.RefreshResources()
        refreshResources = true
    end
    if refreshDungeon then
        RefreshDungeonTable()
    end
    if refreshHeader or refreshSeasonInfo then
        RefreshDetailHeader()
    end
    if refreshSeason then
        RefreshSeasonStatisticsUI()
    end
    if refreshWeekly then
        RefreshWeeklyStatisticsUI()
    end
    if refreshKeystone then
        RefreshKeystoneUI()
    end
    local cachedVault = Data.GetCachedSection and Data.GetCachedSection("vault")
    if refreshVault or (cachedVault and cachedVault.valid) then
        RefreshVaultUI()
    end
    if refreshResources then
        RefreshResourceUI()
    end
    if refreshCutoffHistory then
        RefreshCutoffTrendUI()
    end
end

local function QueueDetailRefresh(delay)
    if not detailFrame or not detailFrame:IsShown() or detailRefreshQueued then
        return
    end
    detailRefreshQueued = true
    local function RunQueuedRefresh()
        detailRefreshQueued = false
        if detailFrame and detailFrame:IsShown() then
            RefreshDirtyDetailSections()
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay or 0.25, RunQueuedRefresh)
    else
        RunQueuedRefresh()
    end
end

local function CreateModuleTitle(parent, text)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetWidth(SIDE_WIDTH)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText(text)
    title:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
    return title
end

local function CreateVaultProgressRow(parent, labelText)
    local row = CreateFrame("Frame", nil, parent)
    local rowWidth = SIDE_WIDTH - 8
    local labelWidth = 54
    local valueWidth = 42
    local leftGap = 4
    local rightGap = 8
    local barWidth = rowWidth - labelWidth - valueWidth - leftGap - rightGap
    row:SetSize(rowWidth, 19)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetWidth(labelWidth)
    row.label:SetJustifyH("LEFT")
    row.label:SetText(labelText)
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetPoint("LEFT", row, "LEFT", labelWidth + leftGap, 0)
    row.background:SetSize(barWidth, 9)
    row.background:SetColorTexture(0, 0, 0, 0.45)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("TOPLEFT", row.background, "TOPLEFT", 0, 0)
    row.bar:SetPoint("BOTTOMRIGHT", row.background, "BOTTOMRIGHT", 0, 0)
    row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetMinMaxValues(0, 1)
    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.value:SetWidth(valueWidth)
    row.value:SetJustifyH("RIGHT")
    return row
end

local function SetTrendPeriod(days)
    local side = detailFrame and detailFrame.sideUI
    if not side or (days ~= 7 and days ~= 30) then
        return
    end
    side.trendState.periodDays = days
    RefreshCutoffTrendUI()
end

local function CreateTrendPeriodDropdown(parent)
    local dropdown
    if type(MenuUtil) == "table" then
        local ok, native = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        if ok and native and type(native.SetupMenu) == "function" then
            dropdown = native
            dropdown:SetSize(76, 20)
            dropdown:SetupMenu(function(_, rootDescription)
                rootDescription:CreateRadio(L.DETAIL_TREND_7_DAYS, function()
                    return detailFrame.sideUI.trendState.periodDays == 7
                end, function()
                    SetTrendPeriod(7)
                end)
                rootDescription:CreateRadio(L.DETAIL_TREND_30_DAYS, function()
                    return detailFrame.sideUI.trendState.periodDays == 30
                end, function()
                    SetTrendPeriod(30)
                end)
            end)
        end
    end
    if dropdown then
        return dropdown
    end

    dropdown = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    dropdown:SetSize(76, 20)
    dropdown:SetScript("OnClick", function(self)
        if type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function" then
            MenuUtil.CreateContextMenu(self, function(_, rootDescription)
                rootDescription:CreateRadio(L.DETAIL_TREND_7_DAYS, function()
                    return detailFrame.sideUI.trendState.periodDays == 7
                end, function()
                    SetTrendPeriod(7)
                end)
                rootDescription:CreateRadio(L.DETAIL_TREND_30_DAYS, function()
                    return detailFrame.sideUI.trendState.periodDays == 30
                end, function()
                    SetTrendPeriod(30)
                end)
            end)
        elseif type(EasyMenu) == "function" then
            detailFrame.sideUI.trendFallbackMenu = detailFrame.sideUI.trendFallbackMenu
                or CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
            EasyMenu({
                { text = L.DETAIL_TREND_7_DAYS, checked = detailFrame.sideUI.trendState.periodDays == 7, func = function() SetTrendPeriod(7) end },
                { text = L.DETAIL_TREND_30_DAYS, checked = detailFrame.sideUI.trendState.periodDays == 30, func = function() SetTrendPeriod(30) end },
            }, detailFrame.sideUI.trendFallbackMenu, self, 0, 0, "MENU")
        end
    end)
    return dropdown
end

local function CreateTrendButtonBar(parent)
    local buttonGap = 4
    local buttonWidth = math.floor((SIDE_WIDTH - buttonGap * 4) / 5)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(SIDE_WIDTH, 22)
    local buttons = {}
    for index, definition in ipairs(RankTarget.CUTOFF_DEFS) do
        local key = definition.key
        local button = CreateFrame("Button", nil, bar)
        local x = (index - 1) * (buttonWidth + buttonGap)
        button:SetSize(buttonWidth, 20)
        button:SetPoint("LEFT", bar, "LEFT", x, 0)
        button.selectedBackground = button:CreateTexture(nil, "BACKGROUND")
        button.selectedBackground:SetAllPoints()
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.text:SetAllPoints()
        button.text:SetJustifyH("CENTER")
        button.text:SetText(L[CUTOFF_LABEL_KEYS[key]])
        button:SetScript("OnClick", function()
            detailFrame.sideUI.trendState.cutoffKey = key
            RefreshCutoffTrendUI()
        end)
        buttons[key] = button
    end
    return bar, buttons
end

local function CreateTrendChart(parent)
    local chart = {
        frame = CreateFrame("Frame", nil, parent),
        lines = {},
        nodes = {},
        hitFrames = {},
        scoreLabels = {},
        dateLabels = {},
    }
    chart.frame:SetSize(SIDE_WIDTH - 8, 220)
    chart.background = chart.frame:CreateTexture(nil, "BACKGROUND")
    chart.background:SetAllPoints()
    for index = 1, 29 do
        local line = chart.frame:CreateLine(nil, "ARTWORK")
        line:SetThickness(2)
        line:Hide()
        chart.lines[index] = line
    end
    for index = 1, 30 do
        local node = chart.frame:CreateTexture(nil, "ARTWORK")
        node:Hide()
        chart.nodes[index] = node

        local hit = CreateFrame("Frame", nil, chart.frame)
        hit:SetSize(22, 22)
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", ShowTrendTooltip)
        hit:SetScript("OnLeave", GameTooltip_Hide)
        hit:Hide()
        chart.hitFrames[index] = hit

        local scoreLabel = chart.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        scoreLabel:SetWidth(60)
        scoreLabel:SetJustifyH("CENTER")
        scoreLabel:SetWordWrap(false)
        if type(scoreLabel.SetNonSpaceWrap) == "function" then
            scoreLabel:SetNonSpaceWrap(false)
        end
        scoreLabel:SetTextColor(0.92, 0.92, 0.92)
        scoreLabel:Hide()
        chart.scoreLabels[index] = scoreLabel

        local dateLabel = chart.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dateLabel:SetWidth(44)
        dateLabel:SetJustifyH("CENTER")
        dateLabel:SetWordWrap(false)
        dateLabel:SetTextColor(0.55, 0.55, 0.55)
        dateLabel:Hide()
        chart.dateLabels[index] = dateLabel
    end
    chart.status = chart.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chart.status:SetPoint("CENTER", chart.frame, "CENTER", 0, 0)
    chart.status:SetTextColor(MUTED_R, MUTED_G, MUTED_B)
    chart.status:Hide()
    return chart
end

local function AddBackgroundLayer(frame, parent, multiplier)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    frame.backgroundLayers[#frame.backgroundLayers + 1] = {
        texture = texture,
        multiplier = multiplier,
    }
    return texture
end

local function CreateResourceCell(parent, x, y)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetSize(112, 24)
    button:EnableMouse(true)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("LEFT", button, "LEFT", 0, 0)
    button.icon:SetSize(22, 22)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.quantity = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.quantity:SetPoint("LEFT", button.icon, "RIGHT", 6, 0)
    button.quantity:SetWidth(78)
    button.quantity:SetJustifyH("LEFT")
    button.quantity:SetWordWrap(false)
    button.quantity:SetText("-")

    button:SetScript("OnEnter", function(self)
        if Resources and self.resource then
            Resources.ShowTooltip(self, self.resource)
        end
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

local function SetRegionSelectorEnabled(button, enabled)
    if not button then
        return
    end
    if enabled and type(button.Enable) == "function" then
        button:Enable()
    elseif not enabled and type(button.Disable) == "function" then
        button:Disable()
    elseif type(button.SetEnabled) == "function" then
        button:SetEnabled(enabled)
    end
end

local function SelectRegion(region)
    if not ns.SetSelectedRegion(region) then
        return
    end
    if Data and Data.MarkRegionDirty then
        Data.MarkRegionDirty()
    end
    if ns.RefreshRegionSelector then
        ns.RefreshRegionSelector()
    end
    if ns.RefreshHUDData then
        ns.RefreshHUDData()
    end
    if ns.RefreshMeetingStoneIntegration then
        ns.RefreshMeetingStoneIntegration("profile")
    end
    if detailFrame and detailFrame:IsShown() then
        QueueDetailRefresh(0)
    end
end

local function BuildRegionMenu(rootDescription)
    for _, region in ipairs(ns.GetLoadedRegions()) do
        local selectedRegion = region
        rootDescription:CreateRadio(ns.GetRegionLabel(selectedRegion), function()
            return ns.GetSelectedRegion() == selectedRegion
        end, function()
            SelectRegion(selectedRegion)
        end)
    end
end

local function CreateRegionSelector(parent)
    local selector = CreateFrame("Frame", nil, parent)
    selector:SetSize(300, 24)
    selector.label = selector:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selector.label:SetPoint("LEFT", selector, "LEFT", 0, 0)
    selector.label:SetWidth(88)
    selector.label:SetJustifyH("LEFT")
    selector.label:SetText(L.REGION_SELECTOR_LABEL)

    local dropdown
    if type(MenuUtil) == "table" then
        local ok, native = pcall(CreateFrame, "DropdownButton", nil, selector, "WowStyle1DropdownTemplate")
        if ok and native and type(native.SetupMenu) == "function" then
            dropdown = native
            dropdown:SetSize(130, 22)
            dropdown:SetupMenu(function(_, rootDescription)
                BuildRegionMenu(rootDescription)
            end)
        end
    end
    if not dropdown then
        dropdown = CreateFrame("Button", nil, selector, "UIPanelButtonTemplate")
        dropdown:SetSize(130, 22)
        dropdown:SetScript("OnClick", function(self)
            local loaded = ns.GetLoadedRegions()
            if #loaded <= 1 then
                return
            end
            if type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function" then
                MenuUtil.CreateContextMenu(self, function(_, rootDescription)
                    BuildRegionMenu(rootDescription)
                end)
            elseif type(EasyMenu) == "function" then
                selector.fallbackMenu = selector.fallbackMenu
                    or CreateFrame("Frame", nil, selector, "UIDropDownMenuTemplate")
                local menu = {}
                for _, region in ipairs(loaded) do
                    menu[#menu + 1] = {
                        text = ns.GetRegionLabel(region),
                        checked = ns.GetSelectedRegion() == region,
                        isNotRadio = false,
                        func = function()
                            SelectRegion(region)
                        end,
                    }
                end
                EasyMenu(menu, selector.fallbackMenu, self, 0, 0, "MENU")
            end
        end)
    end
    dropdown:SetPoint("LEFT", selector.label, "RIGHT", 8, 0)
    selector.dropdown = dropdown
    return selector
end

function ns.RefreshRegionSelector()
    if not detailFrame or not detailFrame.tableUI or not detailFrame.tableUI.regionSelector then
        return
    end
    local selector = detailFrame.tableUI.regionSelector
    local loaded = ns.GetLoadedRegions()
    local textValue = ns.GetSelectedRegionLabel() or L.REGION_NO_DATA_PACK
    if type(selector.dropdown.SetText) == "function" then
        selector.dropdown:SetText(textValue)
    elseif selector.dropdown.Text then
        selector.dropdown.Text:SetText(textValue)
    end
    SetRegionSelectorEnabled(selector.dropdown, #loaded > 1)
end

local function CreateDetailFrame()
    if detailFrame then
        return detailFrame
    end

    local frame = CreateFrame("Frame", "QFXMythicRankHUDDetailFrame", UIParent, "BackdropTemplate")
    detailFrame = frame
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.backgroundLayers = {}

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(36)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition()
    end)
    AddBackgroundLayer(frame, titleBar, 0.18)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", titleBar, "LEFT", 14, 0)
    title:SetText(L.DETAIL_TITLE)
    title:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
    frame.title = title

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    local dataSection = CreateFrame("Frame", nil, frame)
    dataSection:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -50)
    dataSection:SetSize(360, 184)
    AddBackgroundLayer(frame, dataSection, 0.055)
    frame.dataDate = dataSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.dataDate:SetPoint("TOPLEFT", dataSection, "TOPLEFT", 4, -2)
    frame.dataDate:SetWidth(352)
    frame.dataDate:SetJustifyH("LEFT")
    frame.dataSource = dataSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.dataSource:SetPoint("TOPLEFT", dataSection, "TOPLEFT", 4, -24)
    frame.dataSource:SetWidth(352)
    frame.dataSource:SetJustifyH("LEFT")
    frame.rankDataStatus = dataSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.rankDataStatus:SetPoint("TOPLEFT", dataSection, "TOPLEFT", 4, -44)
    frame.rankDataStatus:SetWidth(352)
    frame.rankDataStatus:SetJustifyH("LEFT")
    frame.rankDataStatus:SetTextColor(RED_R, RED_G, RED_B)

    frame.resourceUI = { buttons = {}, byKey = {} }
    frame.resourceUI.title = dataSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.resourceUI.title:SetPoint("TOPLEFT", dataSection, "TOPLEFT", 4, -66)
    frame.resourceUI.title:SetText(L.DETAIL_CREST_QUANTITIES)
    frame.resourceUI.title:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
    frame.resourceUI.buttons[1] = CreateResourceCell(dataSection, 4, -88)
    frame.resourceUI.buttons[2] = CreateResourceCell(dataSection, 124, -88)
    frame.resourceUI.buttons[3] = CreateResourceCell(dataSection, 244, -88)
    frame.resourceUI.buttons[4] = CreateResourceCell(dataSection, 4, -124)
    frame.resourceUI.buttons[5] = CreateResourceCell(dataSection, 124, -124)
    frame.resourceUI.buttons[6] = CreateResourceCell(dataSection, 244, -124)
    frame.resourceUI.buttons[7] = CreateResourceCell(dataSection, 4, -160)
    for index, key in ipairs(Resources.RESOURCE_ORDER) do
        local button = frame.resourceUI.buttons[index]
        button.resourceKey = key
        frame.resourceUI.byKey[key] = button
    end

    local scoreSection = CreateFrame("Frame", nil, frame)
    scoreSection:SetPoint("TOPLEFT", frame, "TOPLEFT", 410, -62)
    scoreSection:SetSize(270, 140)
    AddBackgroundLayer(frame, scoreSection, 0.055)
    frame.scoreLabel = scoreSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.scoreLabel:SetPoint("TOP", scoreSection, "TOP", 0, 0)
    frame.scoreLabel:SetWidth(250)
    frame.scoreLabel:SetJustifyH("CENTER")
    frame.scoreLabel:SetWordWrap(false)
    frame.scoreLabel:SetText(L.DETAIL_CURRENT_SEASON_SCORE)
    frame.scoreValue = scoreSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    frame.scoreValue:SetPoint("TOP", frame.scoreLabel, "BOTTOM", 0, -2)
    frame.seasonAgeText = scoreSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.seasonAgeText:SetPoint("TOP", scoreSection, "TOP", 0, -54)
    frame.seasonAgeText:SetWidth(250)
    frame.seasonAgeText:SetJustifyH("CENTER")
    frame.seasonAgeText:SetWordWrap(false)
    frame.seasonAgeText:SetTextColor(0.72, 0.72, 0.72)
    frame.rankLine = CreateInfoLine(scoreSection, -77, 270, L.SETTINGS_ROW_REGION_RANK, 0.52)
    frame.surpassedLine = CreateInfoLine(scoreSection, -103, 270, L.DETAIL_SURPASSED, 0.52)

    local targetSection = CreateFrame("Frame", nil, frame)
    targetSection:SetPoint("TOPLEFT", frame, "TOPLEFT", 710, -62)
    targetSection:SetSize(370, 140)
    AddBackgroundLayer(frame, targetSection, 0.055)
    frame.bracketLine = CreateInfoLine(targetSection, 0, 370, L.DETAIL_CURRENT_BRACKET)
    frame.rankRangeLine = CreateInfoLine(targetSection, -26, 370, L.RANK_RANGE)
    frame.nextLine = CreateInfoLine(targetSection, -52, 370, L.DETAIL_BRACKET_TARGET)
    frame.distanceLine = CreateInfoLine(targetSection, -78, 370, L.DETAIL_DISTANCE_TO_TARGET)
    frame.progressBackground = targetSection:CreateTexture(nil, "BACKGROUND")
    frame.progressBackground:SetPoint("TOPLEFT", targetSection, "TOPLEFT", 0, -112)
    frame.progressBackground:SetSize(370, 11)
    frame.progressBackground:SetColorTexture(0, 0, 0, 0.45)
    frame.progress = CreateFrame("StatusBar", nil, targetSection)
    frame.progress:SetPoint("TOPLEFT", frame.progressBackground, "TOPLEFT", 1, -1)
    frame.progress:SetPoint("BOTTOMRIGHT", frame.progressBackground, "BOTTOMRIGHT", -1, 1)
    frame.progress:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    frame.progress:SetMinMaxValues(0, 1)

    frame.tablePanel = CreateFrame("Frame", nil, frame)
    frame.tablePanel:SetPoint("TOPLEFT", frame, "TOPLEFT", FRAME_SIDE_PADDING, -240)
    frame.tablePanel:SetSize(TABLE_WIDTH, BODY_HEIGHT)
    frame.tableUI = { rows = {} }
    frame.tableUI.regionSelector = CreateRegionSelector(frame.tablePanel)
    AddBackgroundLayer(frame, frame.tablePanel, 0.035)

    local headerBackground = frame.tablePanel:CreateTexture(nil, "BACKGROUND")
    headerBackground:SetPoint("TOPLEFT", frame.tablePanel, "TOPLEFT", 0, 0)
    headerBackground:SetSize(TABLE_WIDTH, TABLE_HEADER_HEIGHT)
    frame.backgroundLayers[#frame.backgroundLayers + 1] = {
        texture = headerBackground,
        multiplier = 0.08,
    }

    CreateHeaderText(frame.tablePanel, L.DETAIL_GROUP_DUNGEON_DETAILS, 0, -5, 344, nil, true)
    CreateHeaderText(frame.tablePanel, L.DETAIL_GROUP_SEASON, 344, -5, 168, nil, true)
    CreateHeaderText(frame.tablePanel, L.DETAIL_GROUP_WEEK, 512, -5, 168, nil, true)
    CreateHeaderText(frame.tablePanel, L.DETAIL_COLUMN_NAME, 36, -29, COLUMNS.dungeon.width - 42, "LEFT")
    CreateHeaderText(frame.tablePanel, L.DETAIL_COLUMN_LEVEL, COLUMNS.level.x, -29, COLUMNS.level.width)
    CreateHeaderText(frame.tablePanel, L.DETAIL_COLUMN_SCORE, COLUMNS.score.x, -29, COLUMNS.score.width)
    CreateHeaderText(frame.tablePanel, L.DETAIL_COLUMN_TOTAL, COLUMNS.seasonTotal.x, -29, COLUMNS.seasonTotal.width)
    CreateHeaderText(frame.tablePanel, L.DETAIL_COLUMN_TIMED, COLUMNS.seasonTimed.x, -29, COLUMNS.seasonTimed.width)
    CreateHeaderText(frame.tablePanel, L.DETAIL_COLUMN_OVERTIME_SHORT or L.DETAIL_COLUMN_OVERTIME, COLUMNS.seasonOvertime.x, -29, COLUMNS.seasonOvertime.width)
    CreateHeaderText(frame.tablePanel, L.DETAIL_COLUMN_TOTAL, COLUMNS.weeklyTotal.x, -29, COLUMNS.weeklyTotal.width)
    CreateHeaderText(frame.tablePanel, L.DETAIL_COLUMN_TIMED, COLUMNS.weeklyTimed.x, -29, COLUMNS.weeklyTimed.width)
    CreateHeaderText(frame.tablePanel, L.DETAIL_COLUMN_OVERTIME_SHORT or L.DETAIL_COLUMN_OVERTIME, COLUMNS.weeklyOvertime.x, -29, COLUMNS.weeklyOvertime.width)

    frame.tableUI.empty = frame.tablePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.tableUI.empty:SetPoint("TOPLEFT", frame.tablePanel, "TOPLEFT", 36, -64)
    frame.tableUI.empty:SetWidth(300)
    frame.tableUI.empty:SetText(L.DETAIL_MAPS_UNAVAILABLE)
    frame.tableUI.empty:SetTextColor(MUTED_R, MUTED_G, MUTED_B)
    frame.tableUI.summary = CreateStatRow(frame.tablePanel, 0, true)

    frame.sidePanel = CreateFrame("Frame", nil, frame)
    frame.sidePanel:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        FRAME_SIDE_PADDING + TABLE_WIDTH + PANEL_GAP,
        -240
    )
    frame.sidePanel:SetSize(SIDE_WIDTH, BODY_HEIGHT)
    AddBackgroundLayer(frame, frame.sidePanel, 0.05)
    frame.sideUI = { vaultRows = {}, trendButtons = {} }
    local side = frame.sideUI
    side.keyLine = CreateFrame("Frame", nil, frame.sidePanel)
    side.keyLine:SetSize(SIDE_WIDTH, 22)
    side.keyTitle = side.keyLine:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    side.keyTitle:SetPoint("LEFT", side.keyLine, "LEFT", 0, 0)
    side.keyTitle:SetWidth(88)
    side.keyTitle:SetJustifyH("LEFT")
    side.keyTitle:SetWordWrap(false)
    side.keyTitle:SetText(L.DETAIL_CURRENT_KEY)
    side.keyTitle:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
    side.keyValue = side.keyLine:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    side.keyValue:SetPoint("RIGHT", side.keyLine, "RIGHT", -4, 0)
    side.keyValue:SetWidth(SIDE_WIDTH - 96)
    side.keyValue:SetJustifyH("RIGHT")
    side.keyValue:SetWordWrap(false)
    side.vaultTitle = CreateModuleTitle(frame.sidePanel, L.DETAIL_VAULT_PROGRESS)
    side.vaultRows[1] = CreateVaultProgressRow(frame.sidePanel, L.VAULT_RAID)
    side.vaultRows[2] = CreateVaultProgressRow(frame.sidePanel, L.VAULT_MYTHIC_PLUS)
    side.vaultRows[3] = CreateVaultProgressRow(frame.sidePanel, L.VAULT_WORLD)

    side.trendState = { cutoffKey = "p999", periodDays = 7 }
    side.trendTitle = CreateModuleTitle(frame.sidePanel, L.DETAIL_CUTOFF_TRENDS)
    side.trendTitle:SetWidth(SIDE_WIDTH - 84)
    side.trendPeriodDropdown = CreateTrendPeriodDropdown(frame.sidePanel)
    side.trendButtonBar, side.trendButtons = CreateTrendButtonBar(frame.sidePanel)
    side.trendSummary = CreateFrame("Frame", nil, frame.sidePanel)
    side.trendSummary:SetSize(SIDE_WIDTH, 22)
    local summaryColumnWidth = math.floor(SIDE_WIDTH / 2) - 4
    side.trendSummary.current = side.trendSummary:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    side.trendSummary.current:SetPoint("LEFT", side.trendSummary, "LEFT", 0, 0)
    side.trendSummary.current:SetWidth(summaryColumnWidth)
    side.trendSummary.current:SetJustifyH("LEFT")
    side.trendSummary.change = side.trendSummary:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    side.trendSummary.change:SetPoint("RIGHT", side.trendSummary, "RIGHT", -2, 0)
    side.trendSummary.change:SetWidth(summaryColumnWidth)
    side.trendSummary.change:SetJustifyH("RIGHT")
    side.trendChart = CreateTrendChart(frame.sidePanel)

    frame:SetScript("OnShow", function()
        ApplyScale()
        ApplyPosition()
        ApplyVisualSettings()
        RefreshDetailHeader()
        RefreshVaultUI()
        if Data and Data.HasDirtyData and Data.HasDirtyData() then
            if Data.IsDirty("mapMeta") and Data.RequestData then
                Data.RequestData()
            end
            QueueDetailRefresh(0)
        end
    end)

    if type(UISpecialFrames) == "table" then
        local found = false
        for _, frameName in ipairs(UISpecialFrames) do
            if frameName == "QFXMythicRankHUDDetailFrame" then
                found = true
                break
            end
        end
        if not found then
            table.insert(UISpecialFrames, "QFXMythicRankHUDDetailFrame")
        end
    end

    ApplyScale()
    ApplyPosition()
    ApplyVisualSettings()
    ApplySidePanelLayout()
    RegisterDetailEvents()
    frame:Hide()
    return frame
end

function ns.ToggleMythicDetail()
    local db = ns.GetDB()
    if db.enableMythicDetail == false then
        return
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return
    end
    local frame = CreateDetailFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function ns.OpenMythicDetail()
    local db = ns.GetDB()
    if db.enableMythicDetail == false then
        return
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return
    end
    CreateDetailFrame():Show()
end

function ns.ApplyDetailStyle()
    ApplyVisualSettings()
end

function ns.ApplyDetailFeatureState()
    if detailFrame and ns.GetDB().enableMythicDetail == false then
        detailFrame:Hide()
    end
end

RegisterDetailEvents = function()
    if detailEventsRegistered then
        return
    end

    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
    eventFrame:RegisterEvent("MYTHIC_PLUS_NEW_WEEKLY_RECORD")
    eventFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
    eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("UI_SCALE_CHANGED")
    eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
        ns.HandleMythicDetailEvent(event, arg1, arg2)
    end)

    local API = _G.QFXMythicRankData
    if API and type(API.RegisterCallback) == "function" then
        API:RegisterCallback(eventFrame, function(_, region)
            local selectedRegion = ns.GetSelectedRegion() or ns.ResolveSelectedRegion()
            if ns.RefreshRegionSelector then
                ns.RefreshRegionSelector()
            end
            if region == selectedRegion then
                Data.MarkRegionDirty()
                if detailFrame and detailFrame:IsShown() then
                    QueueDetailRefresh(0)
                end
            end
        end)
    end

    detailEventsRegistered = true
end

function ns.IsMythicDetailCreated()
    return detailFrame ~= nil
end

function ns.HandleMythicDetailEvent(event, arg1, arg2)
    if not detailFrame then
        return
    end

    if event == "CURRENCY_DISPLAY_UPDATE" then
        local resourceKey = Resources and Resources.GetKeyForCurrencyID(arg1) or nil
        if resourceKey then
            if detailFrame and detailFrame:IsShown() then
                local resource = Data.RefreshOneResource(arg1, arg2)
                if resource then
                    UpdateResourceCell(resource.key, resource)
                else
                    Data.MarkDirty("resources")
                    QueueDetailRefresh(0)
                end
            else
                Data.MarkDirty("resources")
            end
        elseif Resources and Resources.IsTrackedCurrencyID(arg1) then
            Data.MarkDirty("resources")
            QueueDetailRefresh(0)
        end
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        if detailFrame and detailFrame:IsShown() then
            detailFrame:Hide()
        end
        return
    end

    if event == "UI_SCALE_CHANGED" then
        if detailFrame:IsShown() then
            ApplyScale()
            ApplyPosition()
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        Data.MarkDirty("score")
        Data.MarkDirty("ranking")
        Data.MarkDirty("seasonInfo")
        QueueDetailRefresh(0.25)
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        Data.MarkDirty("score")
        Data.MarkDirty("ranking")
        Data.MarkDirty("weeklyStats")
        Data.MarkDirty("vault")
        QueueDetailRefresh(0.75)
    elseif event == "CHALLENGE_MODE_MAPS_UPDATE" then
        Data.MarkDirty("mapMeta")
        Data.MarkDirty("score")
        QueueDetailRefresh(0.75)
    elseif event == "MYTHIC_PLUS_NEW_WEEKLY_RECORD" then
        Data.MarkDirty("weeklyStats")
        Data.MarkDirty("vault")
        QueueDetailRefresh(0.75)
    elseif event == "WEEKLY_REWARDS_UPDATE" then
        Data.MarkDirty("vault")
        QueueDetailRefresh(0.25)
    end
end
