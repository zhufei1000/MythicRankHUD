local _, ns = ...
local L = ns.L
local Util = ns.Util

-- Post-run summary: after a Mythic+ run completes, compare the player's
-- overall score before/after the run and announce the score gain plus the
-- estimated rank improvement (this run only, not the daily delta) in party.
-- Dungeon entry welcome: when the party loads into a dungeon, wait until
-- every member's Mythic+ score is readable, then announce one line per
-- teammate followed by a closing greeting - while the group is still
-- settling in, never once the run itself has started.
--
-- All announcement texts are {name}-style templates (editable in settings);
-- scores/ranks are inserted as plain numbers, so templates decide whether a
-- value reads "<3456>" or "<~12345>".

local run = {
    active = false,
    scoreBefore = nil,
}

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

-- Signed score difference for the "{scoreGain}" placeholder.
local function FormatSignedScoreValue(value)
    if type(value) ~= "number" then
        return "?"
    end
    if value > 0 then
        return "+" .. FormatScoreValue(value)
    end
    return FormatScoreValue(value)
end

-- The previous encounter time as "M-D HH:MM" (e.g. 9-13 23:33).
local function FormatMeetTime(timestamp)
    if type(timestamp) ~= "number" or timestamp <= 0 then
        return nil
    end
    local dateFn = type(date) == "function" and date or (type(os) == "table" and os.date) or nil
    if not dateFn then
        return nil
    end
    local ok, parts = pcall(dateFn, "*t", timestamp)
    if not ok or type(parts) ~= "table" then
        return nil
    end
    local month = tonumber(parts.month)
    local day = tonumber(parts.day)
    local hour = tonumber(parts.hour)
    local minute = tonumber(parts.min)
    if not month or not day or not hour or not minute then
        return nil
    end
    return string.format("%d-%d %02d:%02d", month, day, hour, minute)
end

-- Data pack dataVersion strings are UTC ("YYYYMMDDHHMM"); announcements show
-- them as each region's local wall clock. Fixed offsets, no DST.
local REGION_UTC_OFFSETS = {
    cn = 8,
    tw = 8,
    kr = 9,
    eu = 1,
    us = -5,
}

-- Returns region-local month, day, hour, minute for a dataVersion string.
local function GetDataVersionParts(version, region)
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
    return mm2, dd2, localHour, localMin
end

local function FormatDataVersionLocal(version, region)
    local month, day, hour, minute = GetDataVersionParts(version, region)
    if not month then
        return nil
    end
    return string.format("%02d-%02d %02d:%02d", month, day, hour, minute)
end

-- Reads the data pack's update date and returns the region-local
-- month/day/hour/minute parts used by the announcement templates.
local function GetLocalDataTime(region)
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
    return GetDataVersionParts(version, region)
end

-- Data pack update date without year or time ("9-11" style).
local function GetPackDateText(region)
    local month, day = GetLocalDataTime(region)
    if not month then
        return nil
    end
    local separator = type(L) == "table" and L.PACK_DATE_SEPARATOR or "-"
    if type(separator) ~= "string" or separator == "" then
        separator = "-"
    end
    return tostring(month) .. separator .. tostring(day)
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

-- Resolves an announcement template: a non-empty settings override wins,
-- otherwise the locale default. Empty overrides restore the default.
local function GetAnnounceTemplate(key)
    if type(ns.GetAnnounceTemplate) == "function" then
        local override = ns.GetAnnounceTemplate(key)
        if type(override) == "string" and override ~= "" then
            return override
        end
    end
    local default = type(L) == "table" and L[key] or nil
    if type(default) == "string" and default ~= "" then
        return default
    end
    return nil
end

-- Expands {placeholder} keys; unknown or missing values keep the literal
-- {key} so broken templates stay visible instead of sending broken text.
local function ExpandTemplate(template, values)
    if type(template) ~= "string" or template == "" then
        return nil
    end
    local expanded = template:gsub("{(%w+)}", function(key)
        local value = values and values[key]
        if value == nil then
            return nil
        end
        return tostring(value)
    end)
    if type(expanded) ~= "string" or expanded == "" then
        return nil
    end
    return expanded
end

-- The pack's update date and time, both region-local. The footer line shows
-- the date on its own, so the full time stamp is only exposed as a
-- placeholder for templates that ask for it.
local function GetUpdateTimeText(region)
    local month, day, hour, minute = GetLocalDataTime(region)
    if not month then
        return nil
    end
    return string.format("%02d-%02d %02d:%02d", month, day, hour, minute)
end

-- Announcement lines are sent this far apart: a burst of separate sentences
-- would otherwise hit the client's chat rate limit.
local ANNOUNCE_LINE_INTERVAL = 1

-- Queues one chat message at `delay` seconds from now. Queued lines are
-- dropped once the run has started, so a key inserted mid-burst never gets
-- interrupted by ads.
local function QueueChatMessage(message, delay)
    if delay > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, function()
            if run.active then
                return
            end
            if type(SendChatMessage) == "function" then
                pcall(SendChatMessage, message, "PARTY")
            end
        end)
    elseif type(SendChatMessage) == "function" and not run.active then
        pcall(SendChatMessage, message, "PARTY")
    end
end

-- Builds the post-run summary as separate lines, sent one second apart:
--   1. this run's gain (or the no-gain wording)
--   2. today's gain          (only when the daily baseline is known)
--   3. current score + rank
--   4. the footer line carrying the data pack date and update time
-- A run always reports at least lines 1, 3 and 4.
local function BuildRunGainMessages(region, regionLabel, rankAfter, scoreGain, rankGain, scoreAfter)
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

    local values = {
        region = regionLabel,
        rank = FormatRankValue(rankAfter),
        score = FormatScoreValue(scoreGain),
        rankGain = FormatRankValue(rankGain),
        currentScore = FormatScoreValue(scoreAfter),
        todayScore = FormatScoreValue(baseline and math.max(0, scoreAfter - baseline) or 0),
        todayRank = FormatRankValue(todayRankGain or 0),
        date = GetPackDateText(region) or "",
        updateTime = GetUpdateTimeText(region) or "",
    }

    local messages = {}
    local function Add(key)
        local line = ExpandTemplate(GetAnnounceTemplate(key), values)
        if line then
            messages[#messages + 1] = line
        end
        return line
    end

    -- Zero-gain runs get their own wording instead of "improved by 0".
    Add(scoreGain > 0 and "RUN_GAIN_LINE_GAIN" or "RUN_GAIN_LINE_NO_GAIN")
    if todayRankGain then
        Add("RUN_GAIN_LINE_TODAY")
    end
    Add("RUN_GAIN_LINE_CURRENT")
    -- Footer carries the pack date, so no separate update-time suffix is
    -- appended: that would repeat the same date the footer already shows.
    Add("RUN_GAIN_LINE_AD")
    return messages
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
    local messages = BuildRunGainMessages(region, regionLabel, rankAfter, scoreGain, rankGain, scoreAfter)
    if #messages == 0 then
        return
    end
    for index, message in ipairs(messages) do
        QueueChatMessage(message, index * ANNOUNCE_LINE_INTERVAL)
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
-- Member join welcome: when a new member joins the (non-raid) party, read
-- their Mythic+ score and announce a welcome with their score and estimated
-- regional rank in party chat. The first read is immediate; otherwise the
-- module keeps polling until the score becomes readable. Polling stops when
-- the welcome was sent (all members greeted), the member leaves, or the run
-- starts. Encounters are persisted per player and per month: a member is only
-- announced again once their score changed, and records expire after a month.
-- ---------------------------------------------------------------------------

local WELCOME_RETRY_INTERVAL = 2
local ENCOUNTER_RETENTION_SECONDS = 30 * 24 * 60 * 60
local ENCOUNTER_PRUNE_INTERVAL = 60 * 60

local welcomeState = {
    known = {}, -- [guid] = true, current party roster
}

-- Poll chains capture the current generation and stop as soon as the run
-- starts (the key was inserted); the counter is bumped on CHALLENGE_MODE_START.
local pollGeneration = 0

local inMemoryEncounters = {}

local function GetWallClock()
    if type(GetServerTime) == "function" then
        local ok, value = pcall(GetServerTime)
        if ok and type(value) == "number" and value > 0 then
            return value
        end
    end
    local timeFn = type(time) == "function" and time or (type(os) == "table" and os.time) or nil
    if timeFn then
        local ok, value = pcall(timeFn)
        if ok and type(value) == "number" and value > 0 then
            return value
        end
    end
    return 0
end

local function GetMonthKey(timestamp)
    local dateFn = type(date) == "function" and date or (type(os) == "table" and os.date) or nil
    if not dateFn then
        return "unknown"
    end
    local ok, value = pcall(dateFn, "%Y%m", timestamp)
    if ok and type(value) == "string" then
        return value
    end
    return "unknown"
end

local function GetEncounterStore()
    -- Encounter history is per character; the account-wide table is only a
    -- fallback for diagnostics and for standalone test harnesses.
    if type(ns.GetCharacterDB) == "function" then
        local characterDB = ns.GetCharacterDB()
        if type(characterDB) == "table" then
            if type(characterDB.encounters) ~= "table" then
                characterDB.encounters = {}
            end
            return characterDB.encounters
        end
    end
    if type(ns.GetDB) == "function" then
        local db = ns.GetDB()
        if type(db) == "table" then
            if type(db.encounters) ~= "table" then
                db.encounters = {}
            end
            return db.encounters
        end
    end
    return inMemoryEncounters
end

local lastPruneAt = nil

-- Drops records that have not been seen for a month. Runs at most once an hour.
local function PruneEncounters()
    local store = GetEncounterStore()
    local now = GetWallClock()
    if not store or now <= 0 then
        return
    end
    if lastPruneAt and (now - lastPruneAt) < ENCOUNTER_PRUNE_INTERVAL then
        return
    end
    lastPruneAt = now
    for guid, record in pairs(store) do
        local lastSeen = type(record) == "table" and tonumber(record.lastSeen) or nil
        if not lastSeen or (now - lastSeen) > ENCOUNTER_RETENTION_SECONDS then
            store[guid] = nil
        end
    end
end

local function RecordEncounter(guid, displayName, realm)
    local store = GetEncounterStore()
    if not store then
        return nil
    end
    local now = GetWallClock()
    local record = store[guid]
    if type(record) ~= "table" then
        record = {}
        store[guid] = record
    end
    local previousScore = tonumber(record.score)
    local previousSeen = tonumber(record.lastSeen)
    local monthKey = GetMonthKey(now)
    if record.monthKey ~= monthKey then
        record.monthKey = monthKey
        record.count = 0
    end
    record.count = (tonumber(record.count) or 0) + 1
    record.lastSeen = now
    if type(displayName) == "string" and displayName ~= "" then
        record.name = displayName
    end
    if type(realm) == "string" and realm ~= "" then
        record.realm = realm
    end
    return record, previousScore, previousSeen
end

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

local function GetUnitRealm(unit)
    if type(UnitFullName) ~= "function" then
        return nil
    end
    local ok, _, realm = pcall(UnitFullName, unit)
    if ok and type(realm) == "string" and realm ~= "" then
        return realm
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

local function AnnounceMemberWelcome(unit, guid, score, record, previousScore, previousSeen)
    local name = GetUnitDisplayName(unit)
    if not name then
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
    local values = {
        name = name,
        score = FormatScoreValue(score),
        region = regionLabel,
        rank = FormatRankValue(rank),
        meetCount = tostring(tonumber(record and record.count) or 1),
    }
    local message
    if previousScore ~= nil then
        -- Repeat meeting: compare with the score recorded last time and show
        -- when that meeting happened.
        local difference = score - previousScore
        local changeText
        if difference > 0.05 then
            changeText = string.format(
                L.MEMBER_SCORE_UP_TEXT or "Up %s points",
                FormatScoreValue(difference)
            )
        elseif difference < -0.05 then
            changeText = string.format(
                L.MEMBER_SCORE_DOWN_TEXT or "Down %s points",
                FormatScoreValue(math.abs(difference))
            )
        else
            changeText = L.MEMBER_SCORE_SAME_TEXT or "Your score has not changed"
        end
        values.scoreGain = FormatSignedScoreValue(difference)
        values.scoreChangeText = changeText
        values.lastMeetTime = FormatMeetTime(previousSeen) or ""
        message = ExpandTemplate(GetAnnounceTemplate("MEMBER_WELCOME_AGAIN_FORMAT"), values)
    end
    if not message then
        message = ExpandTemplate(GetAnnounceTemplate("MEMBER_WELCOME_FORMAT"), values)
    end
    if not message then
        return false
    end
    if type(SendChatMessage) == "function" then
        local sent = pcall(SendChatMessage, message, "PARTY")
        if sent then
            if record then
                record.score = score
                record.name = name
            end
            return true
        end
    end
    return false
end

local function ScheduleMemberWelcome(guid, record, previousScore, previousSeen)
    local generation = pollGeneration
    local TryWelcome
    local function Retry()
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(WELCOME_RETRY_INTERVAL, TryWelcome)
        end
    end
    TryWelcome = function()
        -- The run starting (or a newer poll generation) cancels every pending
        -- welcome; polling otherwise continues until the score is available or
        -- the member leaves.
        if generation ~= pollGeneration or run.active then
            return
        end
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
            Retry()
            return
        end
        local score = ReadUnitMythicPlusScore(currentUnit)
        if score
            and AnnounceMemberWelcome(currentUnit, guid, score, record, previousScore, previousSeen)
        then
            return
        end
        Retry()
    end
    -- The first read is attempted immediately; retries only happen while the
    -- score is not readable yet (or while combat lockdown blocks party chat UI
    -- work), so an immediately available score is announced right away.
    TryWelcome()
end

-- Refreshes the tracked party roster. New members are greeted only when
-- announceNew is true (roster seeding at login must stay silent).
local function RefreshRoster(announceNew)
    PruneEncounters()
    -- Raid rosters are not tracked; keeping the party history avoids greeting
    -- everyone again when a raid converts back to a party.
    if type(IsInRaid) == "function" then
        local ok, raid = pcall(IsInRaid)
        if ok and raid then
            return
        end
    end
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
    for guid, unit in pairs(seen) do
        if not welcomeState.known[guid] then
            welcomeState.known[guid] = true
            -- Members joining mid-run are not counted or greeted: the lobby
            -- welcome already ended when the key started.
            if announceNew and not run.active and IsWelcomeEligible() then
                local record, previousScore, previousSeen = RecordEncounter(
                    guid,
                    GetUnitDisplayName(unit),
                    GetUnitRealm(unit)
                )
                if record then
                    ScheduleMemberWelcome(guid, record, previousScore, previousSeen)
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
        -- Cancels every pending welcome poll chain.
        pollGeneration = pollGeneration + 1
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        SchedulePostRunCheck()
    elseif event == "PLAYER_ENTERING_WORLD" then
        RefreshRoster(false)
    elseif event == "GROUP_ROSTER_UPDATE" then
        RefreshRoster(true)
    end
end)

-- One-line state dump for the debug slash commands.
local function DescribeAnnounceState()
    local db = type(ns.GetDB) == "function" and ns.GetDB() or nil
    return table.concat({
        "announce:",
        "region=" .. tostring(ns.GetSelectedRegion and ns.GetSelectedRegion() or nil),
        "summary=" .. tostring(not (db and db.announceRunGain == false)),
        "welcome=" .. tostring(not (db and db.announceMemberJoin == false)),
        "teleport=" .. tostring(not (db and db.announceTeleport == false)),
        "delay=" .. tostring(db and db.announceDelay or nil),
        "runActive=" .. tostring(run.active == true),
        "members=" .. tostring(#GetPartyUnits()),
    }, " ")
end

-- Exposed for tests and diagnostics only.
ns.RunSummary = {
    AnnounceRunGain = AnnounceRunGain,
    EstimateRankForScore = EstimateRankForScore,
    ReadPlayerScore = ReadPlayerScore,
    RefreshRoster = RefreshRoster,
    AnnounceMemberWelcome = AnnounceMemberWelcome,
    PruneEncounters = PruneEncounters,
    FormatDataVersionLocal = FormatDataVersionLocal,
    ExpandTemplate = ExpandTemplate,
    GetAnnounceTemplate = GetAnnounceTemplate,
    DescribeAnnounceState = DescribeAnnounceState,
}
