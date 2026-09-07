local _, ns = ...
local L = ns.L
local Util = ns.Util

-- Post-run summary: after a Mythic+ run completes, compare the player's
-- overall score before/after the run and announce the score gain plus the
-- estimated rank improvement (this run only, not the daily delta) in party.

local run = {
    active = false,
    scoreBefore = nil,
}

local function GetNow()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok and type(value) == "number" then
            return value
        end
    end
    return 0
end

local function ReadPlayerScore()
    local API = _G.QFXMythicRankData
    if type(API) ~= "table" or type(API.GetPlayerScore) ~= "function" then
        return nil
    end
    local ok, score = pcall(API.GetPlayerScore, API)
    if not ok then
        return nil
    end
    return Util.SafeNumber(score)
end

local function EstimateRankForScore(region, score)
    local API = _G.QFXMythicRankData
    if type(API) ~= "table"
        or type(API.EstimateRank) ~= "function"
        or type(region) ~= "string"
        or not score
    then
        return nil
    end
    local ok, raw = pcall(API.EstimateRank, API, region, score, "all")
    local result = ok and Util.SafeTable(raw) or nil
    local rank = result and Util.SafeNumber(result.estimatedRank) or nil
    if not rank and type(Util.EstimateRankBelowTop40) == "function" then
        local okExt, extended = pcall(Util.EstimateRankBelowTop40, API, region, score, "all")
        rank = okExt and Util.SafeNumber(extended and extended.estimatedRank) or nil
    end
    return rank
end

local function FormatScoreValue(value)
    if type(value) ~= "number" then
        return "?"
    end
    local rounded = math.floor(value * 10 + 0.5) / 10
    if rounded == math.floor(rounded) then
        return tostring(math.floor(rounded))
    end
    return string.format("%.1f", rounded)
end

local function FormatRankValue(value)
    if type(value) ~= "number" then
        return "?"
    end
    return tostring(math.floor(value + 0.5))
end

-- Data pack dataVersion strings are UTC ("YYYYMMDDHHMM"); the run summary
-- converts them to each region's local wall clock. Fixed offsets, no DST.
local REGION_UTC_OFFSETS = {
    cn = 8,
    tw = 8,
    kr = 9,
    eu = 1,
    us = -5,
}

local function FormatDataVersionLocal(version, region)
    local text = tostring(version or "")
    local y, m, d, hh, mm = text:match("^(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)$")
    if not y then
        return nil
    end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    hh, mm = tonumber(hh), tonumber(mm)
    local offset = REGION_UTC_OFFSETS[region]
    if not offset then
        return nil
    end
    -- days_from_civil (proleptic Gregorian, Hinnant's algorithm)
    local yy = y
    if m <= 2 then
        yy = yy - 1
    end
    local era = math.floor(yy / 400)
    local yoe = yy - era * 400
    local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    local days = era * 146097 + doe - 719468
    local totalMinutes = days * 1440 + hh * 60 + mm + offset * 60
    local localDays = math.floor(totalMinutes / 1440)
    local minsOfDay = totalMinutes - localDays * 1440
    local localHour = math.floor(minsOfDay / 60)
    local localMin = minsOfDay - localHour * 60
    -- civil_from_days
    local z = localDays + 719468
    local era2 = math.floor(z / 146097)
    local doe2 = z - era2 * 146097
    local yoe2 = math.floor((doe2 - math.floor(doe2 / 1460) + math.floor(doe2 / 36524) - math.floor(doe2 / 146096)) / 365)
    local yr = yoe2 * 400 + era2 * 146097
    local doy2 = doe2 - (365 * yoe2 + math.floor(yoe2 / 4) - math.floor(yoe2 / 100))
    local mp = math.floor((5 * doy2 + 2) / 153)
    local dd2 = doy2 - math.floor((153 * mp + 2) / 5) + 1
    local mm2 = mp + (mp < 10 and 3 or -9)
    if mm2 <= 2 then
        yr = yr + 1
    end
    return string.format("%02d-%02d %02d:%02d", mm2, dd2, localHour, localMin)
end

local function GetUpdateTimeText(region)
    local API = _G.QFXMythicRankData
    if type(API) ~= "table" or type(API.GetMetadata) ~= "function" then
        return nil
    end
    local ok, raw = pcall(API.GetMetadata, API, region)
    local metadata = ok and Util.SafeTable(raw) or nil
    local version = metadata and metadata.dataVersion
    if type(version) ~= "string" and type(version) ~= "number" then
        return nil
    end
    return FormatDataVersionLocal(version, region)
end

local function GetRegionLabel()
    local region = ns.GetSelectedRegion()
    if not region then
        return nil
    end
    local labelKey = "RUN_REGION_LABEL_" .. string.upper(tostring(region))
    local localized = type(L) == "table" and L[labelKey] or nil
    if type(localized) == "string" and localized ~= "" then
        return localized
    end
    if type(ns.GetRegionLabel) == "function" then
        local fallback = ns.GetRegionLabel(region)
        if type(fallback) == "string" and fallback ~= "" then
            return fallback
        end
    end
    return string.upper(tostring(region))
end

local function GetRunAnnounceDelay()
    local delay = 5
    if type(ns.GetRunAnnounceDelay) == "function" then
        local value = ns.GetRunAnnounceDelay()
        if type(value) == "number" then
            delay = value
        end
    end
    return math.max(0, math.min(60, delay))
end

local function AppendUpdateTime(region, message, suffixKey)
    local updateTime = GetUpdateTimeText(region)
    if not updateTime then
        return message
    end
    local suffixFormat = L[suffixKey or "RUN_GAIN_UPDATE_TIME_FORMAT"]
    if type(suffixFormat) ~= "string" or suffixFormat == "" then
        return message
    end
    local ok, suffix = pcall(string.format, suffixFormat, updateTime)
    if ok and type(suffix) == "string" then
        return message .. suffix
    end
    return message
end

local function BuildRunGainMessage(region, regionLabel, rankAfter, scoreGain, rankGain, scoreAfter)
    local baseline
    if type(ns.GetDailyBaselineScore) == "function" then
        baseline = ns.GetDailyBaselineScore()
    end
    local todayRankGain
    if baseline then
        local todayRankBefore = EstimateRankForScore(region, baseline)
        if todayRankBefore then
            todayRankGain = math.max(0, math.floor(todayRankBefore - rankAfter + 0.5))
        end
    end

    -- Zero-gain runs get their own wording instead of "improved by 0".
    if scoreGain <= 0 then
        if baseline and todayRankGain then
            local formatText = L.RUN_GAIN_NO_GAIN_TODAY_FORMAT
            if type(formatText) == "string" and formatText ~= "" then
                local okMsg, message = pcall(
                    string.format,
                    formatText,
                    regionLabel,
                    FormatRankValue(rankAfter),
                    FormatScoreValue(math.max(0, scoreAfter - baseline)),
                    FormatRankValue(todayRankGain)
                )
                if okMsg and type(message) == "string" and message ~= "" then
                    return AppendUpdateTime(region, message)
                end
            end
        end
        local formatText = L.RUN_GAIN_NO_GAIN_FORMAT
        if type(formatText) ~= "string" or formatText == "" then
            return nil
        end
        local okMsg, message = pcall(string.format, formatText, regionLabel, FormatRankValue(rankAfter))
        if okMsg and type(message) == "string" and message ~= "" then
            return AppendUpdateTime(region, message)
        end
        return nil
    end

    if baseline and todayRankGain then
        local formatText = L.RUN_GAIN_ANNOUNCEMENT_TODAY_FORMAT
        if type(formatText) == "string" and formatText ~= "" then
            local okMsg, message = pcall(
                string.format,
                formatText,
                FormatScoreValue(scoreGain),
                FormatRankValue(rankGain),
                regionLabel,
                FormatRankValue(rankAfter),
                FormatScoreValue(math.max(0, scoreAfter - baseline)),
                FormatRankValue(todayRankGain)
            )
            if okMsg and type(message) == "string" and message ~= "" then
                return AppendUpdateTime(region, message)
            end
        end
        return nil
    end
    local formatText = L.RUN_GAIN_ANNOUNCEMENT_FORMAT
    if type(formatText) ~= "string" or formatText == "" then
        return nil
    end
    local okMsg, message = pcall(
        string.format,
        formatText,
        FormatScoreValue(scoreGain),
        FormatRankValue(rankGain),
        regionLabel,
        FormatRankValue(rankAfter)
    )
    if okMsg and type(message) == "string" and message ~= "" then
        return AppendUpdateTime(region, message)
    end
    return nil
end

local function AnnounceRunGain(scoreBefore, scoreAfter)
    if type(ns.IsRunGainAnnouncementEnabled) == "function"
        and not ns.IsRunGainAnnouncementEnabled()
    then
        return
    end
    if type(IsInGroup) == "function" then
        local ok, grouped = pcall(IsInGroup, LE_PARTY_CATEGORY_HOME or 1)
        if not ok or not grouped then
            return
        end
    end
    local region = ns.GetSelectedRegion()
    local regionLabel = GetRegionLabel()
    if not region or not regionLabel then
        return
    end
    local rankBefore = EstimateRankForScore(region, scoreBefore)
    local rankAfter = EstimateRankForScore(region, scoreAfter)
    if not rankBefore or not rankAfter then
        return
    end
    local scoreGain = math.max(0, scoreAfter - scoreBefore)
    local rankGain = math.max(0, math.floor(rankBefore - rankAfter + 0.5))
    local message = BuildRunGainMessage(region, regionLabel, rankAfter, scoreGain, rankGain, scoreAfter)
    if not message then
        return
    end
    if type(SendChatMessage) == "function" then
        pcall(SendChatMessage, message, "PARTY")
    end
end

local function SchedulePostRunCheck()
    if not run.active then
        return
    end
    local scoreBefore = run.scoreBefore
    run.active = false
    if not scoreBefore then
        return
    end

    -- Announcement waits for the configured delay after the run ends, then
    -- briefly polls for Blizzard's score refresh before sending. The run is
    -- always announced, even when the score did not improve (gain of 0).
    local attempts = 0
    local function CheckScoreUpdated()
        local scoreAfter = ReadPlayerScore()
        if scoreAfter and scoreAfter > scoreBefore + 0.05 then
            AnnounceRunGain(scoreBefore, scoreAfter)
            return
        end
        attempts = attempts + 1
        if attempts < 4 and C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(2, CheckScoreUpdated)
            return
        end
        -- Score never refreshed (or genuinely did not improve): announce with
        -- whatever is readable so every finished run gets its summary.
        local finalScore = scoreAfter or ReadPlayerScore() or scoreBefore
        AnnounceRunGain(scoreBefore, finalScore)
    end

    local delay = GetRunAnnounceDelay()
    if delay > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, CheckScoreUpdated)
    else
        CheckScoreUpdated()
    end
end

-- ---------------------------------------------------------------------------
-- Member join welcome: when a new member joins the (non-raid) party while the
-- player is out of combat, try to read their Mythic+ score and announce a
-- welcome with their score and estimated regional rank in party chat.
-- ---------------------------------------------------------------------------

local WELCOME_RETRY_INTERVAL = 2
local WELCOME_MAX_RETRIES = 15
local WELCOME_COOLDOWN = 600

local welcomeState = {
    known = {},    -- [guid] = true, current party roster
    cooldown = {}, -- [guid] = time of the last welcome announcement
}

local function IsCombatLocked()
    if type(InCombatLockdown) == "function" then
        local ok, locked = pcall(InCombatLockdown)
        if ok and locked then
            return true
        end
    end
    return false
end

local function IsWelcomeEligible()
    if type(ns.IsMemberWelcomeEnabled) == "function"
        and not ns.IsMemberWelcomeEnabled()
    then
        return false
    end
    if type(IsInGroup) == "function" then
        local ok, grouped = pcall(IsInGroup, LE_PARTY_CATEGORY_HOME or 1)
        if not ok or not grouped then
            return false
        end
        if type(IsInRaid) == "function" then
            local okRaid, raid = pcall(IsInRaid)
            if okRaid and raid then
                return false
            end
        end
    end
    return true
end

local function GetPartyUnits()
    local units = {}
    if type(IsInRaid) == "function" then
        local ok, raid = pcall(IsInRaid)
        if ok and raid then
            return units
        end
    end
    for index = 1, 4 do
        units[#units + 1] = "party" .. index
    end
    return units
end

local function GetUnitGUID(unit)
    if type(UnitGUID) ~= "function" then
        return nil
    end
    local ok, guid = pcall(UnitGUID, unit)
    if ok and type(guid) == "string" then
        return guid
    end
    return nil
end

-- Roster reshuffles move members between party slots; locate the member's
-- current unit by GUID instead of trusting a slot captured at join time.
local function FindUnitByGUID(guid)
    for _, unit in ipairs(GetPartyUnits()) do
        if GetUnitGUID(unit) == guid then
            return unit
        end
    end
    return nil
end

local function GetUnitDisplayName(unit)
    if type(GetUnitName) == "function" then
        local ok, name = pcall(GetUnitName, unit, true)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    if type(UnitName) == "function" then
        local ok, name = pcall(UnitName, unit)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return nil
end

local function ReadUnitMythicPlusScore(unit)
    if C_PlayerInfo and type(C_PlayerInfo.GetPlayerMythicPlusRatingSummary) == "function" then
        local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
        if ok and type(summary) == "table" then
            return Util.SafeNumber(summary.currentSeasonScore)
        end
    end
    return nil
end

local function AnnounceMemberWelcome(unit, guid)
    local now = GetNow()
    local name = GetUnitDisplayName(unit)
    if not name then
        return false
    end
    local score = ReadUnitMythicPlusScore(unit)
    if not score then
        return false
    end
    local region = ns.GetSelectedRegion()
    local regionLabel = GetRegionLabel()
    if not region or not regionLabel then
        return false
    end
    local rank = EstimateRankForScore(region, score)
    if not rank then
        return false
    end
    local formatText = L.MEMBER_WELCOME_FORMAT
    if type(formatText) ~= "string" or formatText == "" then
        return false
    end
    local okMsg, message = pcall(
        string.format,
        formatText,
        name,
        FormatScoreValue(score),
        regionLabel,
        FormatRankValue(rank)
    )
    if not okMsg or type(message) ~= "string" or message == "" then
        return false
    end
    message = AppendUpdateTime(region, message, "MEMBER_WELCOME_UPDATE_TIME_FORMAT")
    if type(SendChatMessage) == "function" then
        local sent = pcall(SendChatMessage, message, "PARTY")
        if sent then
            welcomeState.cooldown[guid] = now
            return true
        end
    end
    return false
end

local function ScheduleMemberWelcome(guid)
    local attempts = 0
    local function TryWelcome()
        -- The member may have moved to a different party slot; re-locate by
        -- GUID. Only give up when they actually left the party.
        local currentUnit = FindUnitByGUID(guid)
        if not currentUnit then
            return -- member left before we could greet them
        end
        if not IsWelcomeEligible() then
            return
        end
        if IsCombatLocked() then
            -- stay pending until the player leaves combat
            attempts = attempts + 1
            if attempts < WELCOME_MAX_RETRIES and C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(WELCOME_RETRY_INTERVAL, TryWelcome)
            end
            return
        end
        if AnnounceMemberWelcome(currentUnit, guid) then
            return
        end
        attempts = attempts + 1
        if attempts < WELCOME_MAX_RETRIES and C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(WELCOME_RETRY_INTERVAL, TryWelcome)
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(WELCOME_RETRY_INTERVAL, TryWelcome)
    else
        TryWelcome()
    end
end

-- Refreshes the tracked party roster. New members are greeted only when
-- announceNew is true (roster seeding at login must stay silent).
local function RefreshRoster(announceNew)
    local now = GetNow()
    local seen = {}
    for _, unit in ipairs(GetPartyUnits()) do
        local guid = GetUnitGUID(unit)
        if guid then
            seen[guid] = unit
        end
    end
    for guid in pairs(welcomeState.known) do
        if not seen[guid] then
            welcomeState.known[guid] = nil
        end
    end
    -- Expired cooldown entries would otherwise accumulate all session long.
    for guid, last in pairs(welcomeState.cooldown) do
        if now - last > WELCOME_COOLDOWN then
            welcomeState.cooldown[guid] = nil
        end
    end
    for guid, unit in pairs(seen) do
        if not welcomeState.known[guid] then
            welcomeState.known[guid] = true
            if announceNew and IsWelcomeEligible() then
                local last = welcomeState.cooldown[guid]
                if not last or now - last > WELCOME_COOLDOWN then
                    ScheduleMemberWelcome(guid)
                end
            end
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "CHALLENGE_MODE_START" then
        run.active = true
        run.scoreBefore = ReadPlayerScore()
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        SchedulePostRunCheck()
    elseif event == "PLAYER_ENTERING_WORLD" then
        RefreshRoster(false)
    elseif event == "GROUP_ROSTER_UPDATE" then
        RefreshRoster(true)
    end
end)

-- Exposed for tests and diagnostics only.
ns.RunSummary = {
    AnnounceRunGain = AnnounceRunGain,
    EstimateRankForScore = EstimateRankForScore,
    ReadPlayerScore = ReadPlayerScore,
    RefreshRoster = RefreshRoster,
    AnnounceMemberWelcome = AnnounceMemberWelcome,
    FormatDataVersionLocal = FormatDataVersionLocal,
}
