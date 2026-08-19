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
    locked = true,
    enableMythicDetail = true,
    scale = 1,
    width = 292,
    borderStyle = "gold",
    borderAlpha = 0.85,
    backgroundAlpha = 0.88,
    detailBorderAlpha = 1.00,
    detailBackgroundAlpha = 0.90,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -140,
    detailPoint = "CENTER",
    detailRelativePoint = "CENTER",
    detailX = 0,
    detailY = 0,
    showRows = DEFAULT_ROW_VISIBILITY,
    showZones = {
        dungeon = true,
        delve = true,
        raid = true,
        pvp = true,
        world = true,
    },
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

local frame
local divider
local rows = {}
local hudDirty = true
local hudRefreshQueued = false
local hudCreated = false
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
    if type(db.locked) ~= "boolean" then
        db.locked = DEFAULTS.locked
    end
    if type(db.enableMythicDetail) ~= "boolean" then
        db.enableMythicDetail = DEFAULTS.enableMythicDetail
    end
    db.scale = Util.ClampNumber(db.scale, 0.75, 1.50, DEFAULTS.scale)
    db.width = Util.ClampNumber(db.width, 220, 420, DEFAULTS.width)
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
    db.point = VALID_ANCHOR_POINTS[db.point] and db.point or DEFAULTS.point
    db.relativePoint = VALID_ANCHOR_POINTS[db.relativePoint] and db.relativePoint or DEFAULTS.relativePoint
    db.x = Util.ClampNumber(db.x, -100000, 100000, DEFAULTS.x)
    db.y = Util.ClampNumber(db.y, -100000, 100000, DEFAULTS.y)
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

local function IsHUDEnabled()
    local currentDB = GetDB()
    return currentDB and currentDB.showHUD == true
end

local function IsHUDVisible()
    return IsHUDEnabled()
        and frame
        and frame:IsShown()
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

local function GetDataDateParts(metadata)
    local version = metadata and tostring(metadata.dataVersion or "") or ""
    local year, month, day = version:match("^(%d%d%d%d)(%d%d)(%d%d)")
    if year and month and day then
        return tonumber(year), tonumber(month), tonumber(day)
    end
    return nil
end

local function GetDataDate(metadata)
    local year, month, day = GetDataDateParts(metadata)
    if not year then
        return "--"
    end
    return string.format(L.DATA_DATE_FORMAT, year, month, day)
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
    row.label:SetText(label)
    row.value:SetText(value)
    row.value:SetTextColor(r or 1, g or 1, b or 1)
end

local function CreateRow(parent, key, labelTemplate, valueTemplate, height)
    local row = {
        key = key,
        height = height or 20,
    }

    row.label = parent:CreateFontString(nil, "OVERLAY", labelTemplate or "GameFontNormal")
    row.label:SetWidth(112)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetTextColor(0.82, 0.82, 0.82)

    row.value = parent:CreateFontString(nil, "OVERLAY", valueTemplate or "GameFontHighlight")
    row.value:SetJustifyH("RIGHT")
    row.value:SetWordWrap(false)
    return row
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

local function HasVisibleRowInRange(showRows, firstIndex, lastIndex)
    for index = firstIndex, lastIndex do
        if showRows[ROW_ORDER[index]] ~= false then
            return true
        end
    end
    return false
end

local function ApplyHUDLayout()
    if not frame then
        return
    end

    local db = GetDB()
    local showRows = db.showRows
    local width = tonumber(db.width) or DEFAULTS.width
    local labelWidth = math.max(76, math.min(104, width * 0.34))
    local gap = math.max(4, math.min(6, 4 + (width - 220) / 46))
    local topPadding = 10
    local bottomPadding = 10
    local cursor = topPadding
    local hasTopSection = HasVisibleRowInRange(showRows, 1, 3)
    local hasMainSection = HasVisibleRowInRange(showRows, 4, #ROW_ORDER)
    local dividerUsed = false

    for index, key in ipairs(ROW_ORDER) do
        local row = rows[key]
        local visible = showRows[key] ~= false

        if index == 4 and hasTopSection and hasMainSection then
            cursor = cursor + 4
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -cursor)
            divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -cursor)
            divider:Show()
            cursor = cursor + 8
            dividerUsed = true
        end

        row.value:SetShown(visible)

        if row.centered then
            row.label:Hide()
            if visible then
                row.value:ClearAllPoints()
                row.value:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -cursor)
                row.value:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -cursor)
                row.value:SetJustifyH("CENTER")
                cursor = cursor + row.height
            end
        else
            row.label:SetShown(visible)
            if visible then
                row.label:ClearAllPoints()
                row.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -cursor)
                row.label:SetWidth(labelWidth)

                row.value:ClearAllPoints()
                row.value:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -cursor)
                row.value:SetPoint("LEFT", row.label, "RIGHT", gap, 0)
                row.value:SetJustifyH("RIGHT")

                cursor = cursor + row.height
            end
        end
    end

    if not dividerUsed then
        divider:Hide()
    end

    frame:SetWidth(width)
    frame:SetHeight(math.max(32, cursor + bottomPadding))
end

local function ApplyHUDStyle()
    if not frame then
        return
    end

    local db = GetDB()
    frame:SetBackdropColor(0.035, 0.035, 0.045, db.backgroundAlpha)

    local accentR, accentG, accentB, accentA = GetHUDAccentColor()
    frame:SetBackdropBorderColor(accentR, accentG, accentB, accentA)
    divider:SetColorTexture(accentR, accentG, accentB, accentA)
end

local function SavePosition()
    if not frame then
        return
    end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    local db = GetDB()
    db.point = point or "CENTER"
    db.relativePoint = relativePoint or "CENTER"
    db.x = x or 0
    db.y = y or 0
end

local function ApplyHUDPosition()
    if not frame then
        return
    end
    local db = GetDB()
    frame:ClearAllPoints()
    frame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
end

local function ApplyHUDScale()
    if not frame then
        return
    end
    local db = GetDB()
    frame:SetScale(db.scale)
end

local function OpenSettings()
    if ns.OpenSettings then
        ns.OpenSettings()
    end
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.ADDON_TITLE, 1, 0.82, 0)
    local API = _G.QFXMythicRankData
    local region = ns.GetSelectedRegion()
    local metadata = region and API and API.GetMetadata and API:GetMetadata(region)
    if metadata then
        GameTooltip:AddLine(string.format(L.DATA_UPDATED, GetDataDate(metadata)), 1, 1, 1)
    end
    GameTooltip:AddLine(L.DATA_SOURCE, 0.75, 0.75, 0.75)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.ESTIMATE_NOTICE, 1, 0.82, 0, true)
    local db = GetDB()
    if db.locked and db.enableMythicDetail ~= false then
        GameTooltip:AddLine(L.DETAIL_LEFT_CLICK_HINT, 0.65, 0.85, 1, true)
    elseif not db.locked then
        GameTooltip:AddLine(L.DETAIL_DRAG_HINT, 0.65, 0.85, 1, true)
    end
    GameTooltip:AddLine(L.DETAIL_SETTINGS_HINT, 0.65, 0.85, 1, true)
    GameTooltip:Show()
end

local function CreateHUD()
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", "QFXMythicRankHUDGlobalFrame", UIParent, "BackdropTemplate")
    hudCreated = true
    frame:SetSize(DEFAULTS.width, 218)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetScript("OnDragStart", function(self)
        if not GetDB().locked and not (type(InCombatLockdown) == "function" and InCombatLockdown()) then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        local db = GetDB()
        if button == "RightButton" then
            OpenSettings()
        elseif button == "LeftButton" and db.locked then
            if db.enableMythicDetail == false then
                return
            end
            if type(InCombatLockdown) == "function" and InCombatLockdown() then
                return
            end
            if ns.ToggleMythicDetail then
                ns.ToggleMythicDetail()
            end
        end
    end)
    frame:SetScript("OnEnter", ShowTooltip)
    frame:SetScript("OnLeave", GameTooltip_Hide)
    frame:SetScript("OnShow", function()
        if hudDirty then
            ns.QueueHUDRefresh(0)
        end
    end)

    divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)

    rows.dataUpdated = CreateRow(frame, "dataUpdated", "GameFontNormalSmall", "GameFontNormalSmall", 20)
    rows.dataUpdated.centered = true
    rows.cutoff01 = CreateRow(frame, "cutoff01", "GameFontNormalSmall", "GameFontHighlightSmall", 18)
    rows.cutoff1 = CreateRow(frame, "cutoff1", "GameFontNormalSmall", "GameFontHighlightSmall", 18)
    rows.score = CreateRow(frame, "score", "GameFontNormal", "GameFontHighlightLarge", 26)
    rows.todayScore = CreateRow(frame, "todayScore")
    rows.rank = CreateRow(frame, "rank")
    rows.surpassed = CreateRow(frame, "surpassed")
    rows.todayRank = CreateRow(frame, "todayRank")
    rows.toTop25 = CreateRow(frame, "toTop25")
    rows.rankRange = CreateRow(frame, "rankRange")
    rows.percentileRange = CreateRow(frame, "percentileRange")

    ApplyHUDPosition()
    ApplyHUDScale()
    ApplyHUDStyle()
    ApplyHUDLayout()
    return frame
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
    hudRefreshQueued = false

    if not IsHUDEnabled() then
        hudDirty = true
        return
    end

    CreateHUD()
    if not frame:IsShown() then
        hudDirty = true
        return
    end

    hudDirty = false

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
    SetRow(rows.dataUpdated, "", string.format(L.DATA_UPDATED, GetDataDate(metadata)), GOLD_R, GOLD_G, GOLD_B)
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

local function QueueHUDRefresh(delay)
    if not IsHUDEnabled() or (frame and not frame:IsShown()) then
        hudDirty = true
        return
    end
    if hudRefreshQueued then
        return
    end
    hudRefreshQueued = true
    local function RunQueuedRefresh()
        hudRefreshQueued = false
        if not IsHUDEnabled() or (frame and not frame:IsShown()) then
            hudDirty = true
            return
        end
        RefreshHUDData()
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay or 0, RunQueuedRefresh)
    else
        RunQueuedRefresh()
    end
end

ns.QueueHUDRefresh = QueueHUDRefresh

function ns.Refresh()
    QueueHUDRefresh(0)
end

function ns.RefreshHUDData()
    RefreshHUDData()
end

function ns.ApplyHUDPosition()
    if IsHUDVisible() then
        ApplyHUDPosition()
    end
end

function ns.ApplyHUDScale()
    if IsHUDVisible() then
        ApplyHUDScale()
    end
end

function ns.ApplyHUDStyle()
    ApplyHUDStyle()
end

function ns.ApplyHUDLayout()
    if IsHUDVisible() then
        ApplyHUDLayout()
    end
end

function ns.ApplyHUDVisibility()
    ns.SetHUDShown(IsHUDEnabled())
end

function ns.ApplySettings()
    if frame then
        ApplyHUDStyle()
        if IsHUDVisible() then
            ApplyHUDPosition()
            ApplyHUDScale()
            ApplyHUDLayout()
        end
    end
    if ns.ApplyMythicDetailSettings then
        ns.ApplyMythicDetailSettings()
    end
end

function ns.ResetPosition()
    local db = GetDB()
    db.point = DEFAULTS.point
    db.relativePoint = DEFAULTS.relativePoint
    db.x = DEFAULTS.x
    db.y = DEFAULTS.y
    if IsHUDVisible() then
        ApplyHUDPosition()
    end
end

function ns.GetDB()
    return GetDB()
end

function ns.IsHUDCreated()
    return hudCreated and frame ~= nil
end

function ns.IsHUDVisible()
    return IsHUDVisible() and true or false
end

local function UpdateZoneVisibility()
    local currentDB = GetDB()
    if not currentDB.showHUD then
        hudDirty = true
        return
    end
    local shouldShow = ns.ShouldShowInZone()
    if frame then
        if shouldShow and not frame:IsShown() then
            frame:Show()
            hudDirty = true
            QueueHUDRefresh(0)
        elseif not shouldShow and frame:IsShown() then
            frame:Hide()
            hudDirty = true
        end
    else
        hudDirty = true
        if shouldShow then
            ns.SetHUDShown(true)
        end
    end
end

function ns.ApplyZoneVisibility()
    UpdateZoneVisibility()
end

function ns.SetHUDShown(enabled)
    local currentDB = GetDB()
    currentDB.showHUD = enabled == true

    if currentDB.showHUD then
        CreateHUD()
        ApplyHUDPosition()
        ApplyHUDScale()
        ApplyHUDStyle()
        ApplyHUDLayout()
        if ns.ShouldShowInZone() then
            frame:Show()
            hudDirty = true
            QueueHUDRefresh(0)
        else
            frame:Hide()
            hudDirty = true
        end
    else
        hudDirty = true
        if frame then
            frame:Hide()
        end
    end
end

function ns.SetShowHUD(value)
    ns.SetHUDShown(value)
end

function ns.SetLocked(value)
    GetDB().locked = value == true
end

function ns.SetDetailEnabled(value)
    GetDB().enableMythicDetail = value == true
end

function ns.SetHUDWidth(value)
    GetDB().width = Util.ClampNumber(value, 220, 420, DEFAULTS.width)
end

function ns.SetHUDScale(value)
    GetDB().scale = Util.ClampNumber(value, 0.75, 1.50, DEFAULTS.scale)
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

function ns.GetHUDAccentColor()
    return GetHUDAccentColor()
end

function ns.GetDetailAccentColor()
    return GetDetailAccentColor()
end

function ns.GetDetailBorderAlpha()
    return GetDB().detailBorderAlpha
end

function ns.GetDetailBackgroundAlpha()
    return GetDB().detailBackgroundAlpha
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
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
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
        if IsHUDEnabled() then
            ns.SetHUDShown(true)
        else
            hudDirty = true
        end
        if ns.InitializeSettings then
            ns.InitializeSettings()
        end
        if ns.InitializeMythicDetail then
            ns.InitializeMythicDetail()
        end
        local API = _G.QFXMythicRankData
        if API and type(API.RegisterCallback) == "function" then
            API:RegisterCallback(ns, function(_, region)
                local selectedRegion = ns.GetSelectedRegion() or ns.ResolveSelectedRegion()
                if ns.RefreshRegionSelector then
                    ns.RefreshRegionSelector()
                end
                if region == selectedRegion then
                    hudDirty = true
                    if IsHUDVisible() then
                        QueueHUDRefresh(0)
                    end
                end
            end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateZoneVisibility()
        hudDirty = true
        if IsHUDVisible() then
            QueueHUDRefresh(1)
        else
            UpdateDailyScoreStateOnly()
        end
        if ns.HandleMythicDetailEvent then
            ns.HandleMythicDetailEvent(event, arg1)
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        UpdateZoneVisibility()
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        hudDirty = true
        if IsHUDVisible() then
            QueueHUDRefresh(2)
        elseif C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(2, function()
                if not IsHUDVisible() then
                    UpdateDailyScoreStateOnly()
                end
            end)
        else
            UpdateDailyScoreStateOnly()
        end
        if ns.HandleMythicDetailEvent then
            ns.HandleMythicDetailEvent(event, arg1)
        end
    end
end)
