local _, ns = ...
local L = ns.L
local Util = ns.Util
local RankTarget = ns.RankTarget

-- Post-run summary: snapshot party members at the key start and announce
-- each teammate's score and estimated rank changes after completion.
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
    members = {},
    generation = 0,
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

-- Ranked achievement cutoffs that can act as a "next target" when the score
-- has not yet reached a percentile cutoff.
local ACHIEVEMENT_TARGET_KEYS = {
    { key = "keystoneExplorer", nameKey = "ACHIEVEMENT_KEYSTONE_EXPLORER" },
    { key = "keystoneConqueror", nameKey = "ACHIEVEMENT_KEYSTONE_CONQUEROR" },
    { key = "keystoneMaster", nameKey = "ACHIEVEMENT_KEYSTONE_MASTER" },
    { key = "keystoneHero", nameKey = "ACHIEVEMENT_KEYSTONE_HERO" },
    { key = "keystoneLegend", nameKey = "ACHIEVEMENT_KEYSTONE_LEGEND" },
}

-- Reads the selected region's percentile cutoffs and achievement cutoffs once
-- per announcement; the resolved target per member is pure math on top.
local function BuildRankTargetContext(region)
    if not RankTarget or type(RankTarget.Resolve) ~= "function" or type(region) ~= "string" then
        return nil
    end
    local API = _G.QFXMythicRankData
    if type(API) ~= "table" or type(API.GetCutoff) ~= "function" then
        return nil
    end

    local cutoffs = {}
    for _, definition in ipairs(RankTarget.CUTOFF_DEFS) do
        local ok, raw = pcall(API.GetCutoff, API, region, definition.key, "all")
        local value = ok and Util.SafeTable(raw) or nil
        local score = value and Util.SafeNumber(value.score) or nil
        if score then
            cutoffs[#cutoffs + 1] = {
                key = definition.key,
                percent = definition.percent,
                score = score,
                color = value and Util.SafeString(value.color) or nil,
            }
        end
    end
    if #cutoffs == 0 then
        return nil
    end

    local achievements = {}
    if type(API.GetAchievementCutoff) == "function" then
        for _, definition in ipairs(ACHIEVEMENT_TARGET_KEYS) do
            local ok, raw = pcall(API.GetAchievementCutoff, API, region, definition.key)
            if not ok or raw == nil then
                ok, raw = pcall(API.GetAchievementCutoff, API, definition.key)
            end
            local value = ok and Util.SafeTable(raw) or nil
            local threshold = value and Util.SafeNumber(value.thresholdScore or value.score)
                or (ok and Util.SafeNumber(raw)) or nil
            if threshold then
                achievements[#achievements + 1] = {
                    key = definition.key,
                    thresholdScore = threshold,
                    localizedName = L[definition.nameKey],
                    color = value and Util.SafeString(value.color) or nil,
                }
            end
        end
    end
    return cutoffs, achievements
end

local function GetRankTargetName(target)
    if target.targetKind == "bracket" then
        return string.format(L.TOP_PERCENT or "top %s%%", target.targetPercent or "?")
    end
    if target.targetKind == "cutoff" then
        return string.format(L.SMART_CUTOFF_LINE_FORMAT or "Top %s%% cutoff", target.targetPercent or "?")
    end
    return target.targetName
end

-- Next percentile cutoff or achievement the score still has to reach.
-- Returns the target name, the plain point distance and the full phrase
-- ("距前10%差123分"); all three are nil when no target can be computed.
local function BuildNextTargetValues(score, cutoffs, achievements)
    if not score or not cutoffs then
        return nil, nil, nil
    end
    local target = RankTarget.Resolve(score, cutoffs, achievements)
    if not target then
        return nil, nil, nil
    end
    if target.mode == "complete" then
        return nil, nil, L.RUN_NEXT_TARGET_COMPLETE or ""
    end
    local targetName = GetRankTargetName(target)
    if not targetName then
        return nil, nil, nil
    end
    local distanceText = FormatScoreValue(target.distance or 0)
    local format = L.RUN_NEXT_TARGET_FORMAT or "%s pts to %s"
    return targetName, distanceText, string.format(format, targetName, distanceText)
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
local ANNOUNCE_LINE_INTERVAL = 0.5

-- Queues one chat message at `delay` seconds from now. Queued lines are
-- dropped once the run has started, so a key inserted mid-burst never gets
-- interrupted by ads.
local function QueueChatMessage(message, delay, generation)
    if delay > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, function()
            if run.active or run.generation ~= generation then
                return
            end
            Util.SendPartyMessage(message)
        end)
    elseif not run.active and run.generation == generation then
        Util.SendPartyMessage(message)
    end
end

local SchedulePostRunCheck


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

-- One shared slow-poll queue for every member still waiting for a readable
-- score: a single timer serves all pending welcomes instead of one chain per
-- teammate.
local pendingWelcomes = {}
local welcomePollScheduled = false

local function ClearPendingWelcomes()
    for guid in pairs(pendingWelcomes) do
        pendingWelcomes[guid] = nil
    end
end

-- Last outcome of the welcome pipeline, surfaced by /qfxrank debug so a
-- missing greeting can be diagnosed in-game.
local lastWelcomeIssue = "none"

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
    if not ok then
        return nil
    end
    -- 12.x marks UnitGUID secret under unit-identity restrictions; a secret
    -- GUID must never become a table key.
    return Util.SafeString(guid)
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
        local safeName = ok and Util.SafeString(name) or nil
        if safeName and safeName ~= "" then
            return safeName
        end
    end
    if type(UnitName) == "function" then
        local ok, name = pcall(UnitName, unit)
        local safeName = ok and Util.SafeString(name) or nil
        if safeName and safeName ~= "" then
            return safeName
        end
    end
    return nil
end

local function GetUnitRealm(unit)
    if type(UnitFullName) ~= "function" then
        return nil
    end
    local ok, _, realm = pcall(UnitFullName, unit)
    local safeRealm = ok and Util.SafeString(realm) or nil
    if safeRealm and safeRealm ~= "" then
        return safeRealm
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

-- ---------------------------------------------------------------------------
-- Applicant score cache: while the player is listed in the Group Finder, the
-- applicant list exposes each applicant's Mythic+ score (the same value the
-- default applicant tooltip shows). Members who join from that list can be
-- greeted with the cached score even when the unit rating API has no data for
-- them. Only the welcome path uses this cache; run summaries keep reading the
-- live unit value so a stale applicant score can never leak into a run report.
-- ---------------------------------------------------------------------------

local APPLICANT_CACHE_TTL = 30 * 60
local applicantScores = {} -- [lowercase short name] = { score = number, at = wall clock }

local function NormalizeShortName(name)
    local value = Util.SafeString(name)
    if not value or value == "" then
        return nil
    end
    local short = value:match("^([^%-]+)") or value
    return string.lower(short)
end

local function CacheApplicantScores()
    if type(C_LFGList) ~= "table"
        or type(C_LFGList.GetApplicants) ~= "function"
        or type(C_LFGList.GetApplicantInfo) ~= "function"
        or type(C_LFGList.GetApplicantMemberInfo) ~= "function"
    then
        return
    end
    local ok, applicants = pcall(C_LFGList.GetApplicants)
    local list = ok and Util.SafeTable(applicants) or nil
    if not list then
        return
    end
    local now = GetWallClock()
    if now <= 0 then
        return
    end
    for _, applicantID in ipairs(list) do
        local okInfo, rawInfo = pcall(C_LFGList.GetApplicantInfo, applicantID)
        local info = okInfo and Util.SafeTable(rawInfo) or nil
        local numMembers = info and Util.SafeNumber(info.numMembers) or nil
        if numMembers then
            for memberIndex = 1, numMembers do
                -- Return order: name, class, localizedClass, level, itemLevel,
                -- honorLevel, tank, healer, damage, assignedRole, relationship,
                -- dungeonScore, ... With pcall's leading boolean that puts the
                -- eleventh underscore slot on relationship and the last
                -- captured value on dungeonScore.
                local okMember, rawName, _, _, _, _, _, _, _, _, _, _, rawScore =
                    pcall(C_LFGList.GetApplicantMemberInfo, applicantID, memberIndex)
                if okMember then
                    local name = NormalizeShortName(rawName)
                    local score = Util.SafeNumber(rawScore)
                    if name and score then
                        applicantScores[name] = { score = score, at = now }
                    end
                end
            end
        end
    end
    for name, entry in pairs(applicantScores) do
        if (now - entry.at) > APPLICANT_CACHE_TTL then
            applicantScores[name] = nil
        end
    end
end

local function GetApplicantScore(unit)
    local name = NormalizeShortName(GetUnitDisplayName(unit))
    local entry = name and applicantScores[name] or nil
    return entry and entry.score or nil
end

local function CaptureRunMembers()
    local members = {}
    local region = ns.GetSelectedRegion()
    for _, unit in ipairs(GetPartyUnits()) do
        local guid = GetUnitGUID(unit)
        if guid then
            local fullName = GetUnitDisplayName(unit)
            local realm = GetUnitRealm(unit)
            if type(UnitFullName) == "function" then
                local ok, name, fullRealm = pcall(UnitFullName, unit)
                name = ok and Util.SafeString(name) or nil
                fullRealm = ok and Util.SafeString(fullRealm) or nil
                if name and name ~= "" then
                    realm = (fullRealm and fullRealm ~= "" and fullRealm) or realm
                    fullName = name .. (realm and ("-" .. realm) or "")
                end
            end
            local score = ReadUnitMythicPlusScore(unit)
            members[#members + 1] = {
                guid = guid,
                fullName = fullName,
                realm = realm,
                name = fullName and fullName:match("^([^-]+)") or nil,
                scoreBefore = score,
                rankBefore = score and EstimateRankForScore(region, score) or nil,
            }
        end
    end
    return members
end

local function AnnounceRunMembers(members, generation)
    if run.generation ~= generation or run.active then return end
    if type(ns.IsRunGainAnnouncementEnabled) == "function" and not ns.IsRunGainAnnouncementEnabled() then return end
    if ns.Announcer and not ns.Announcer.IsAnnouncer("run") then return end
    if type(IsInGroup) == "function" then
        local ok, grouped = pcall(IsInGroup, LE_PARTY_CATEGORY_HOME or 1)
        if not ok or not grouped then return end
    end
    local region = ns.GetSelectedRegion()
    local regionLabel = GetRegionLabel()
    local targetCutoffs, targetAchievements = BuildRankTargetContext(region)
    local messages = {}
    for _, member in ipairs(members) do
        local score = member.scoreAfter
        local rank = score and EstimateRankForScore(region, score) or nil
        local nextTarget, nextDistance, nextTargetText =
            BuildNextTargetValues(score, targetCutoffs, targetAchievements)
        local values = {
            name = member.name or "?",
            score = score and FormatScoreValue(score) or "--",
            scoreGain = score and member.scoreBefore and FormatScoreValue(math.max(0, score - member.scoreBefore)) or "--",
            region = regionLabel or "",
            rank = rank and FormatRankValue(rank) or "--",
            rankGain = rank and member.rankBefore and FormatRankValue(math.max(0, member.rankBefore - rank)) or "--",
            nextTarget = nextTarget or "",
            nextDistance = nextDistance or "",
            nextTargetText = nextTargetText or "",
        }
        local message = ExpandTemplate(GetAnnounceTemplate("RUN_MEMBER_LINE"), values)
        if message then messages[#messages + 1] = message end
    end
    if #messages == 0 then return end
    local ad = ExpandTemplate(GetAnnounceTemplate("RUN_GAIN_LINE_AD"), {
        region = regionLabel or "",
        date = GetPackDateText(region) or "",
        updateTime = GetUpdateTimeText(region) or "",
    })
    if ad then messages[#messages + 1] = ad end
    for index, message in ipairs(messages) do
        QueueChatMessage(message, index * ANNOUNCE_LINE_INTERVAL, generation)
    end
end

SchedulePostRunCheck = function()
    if not run.active then return end
    run.active = false
    -- Elect at send time: peer HELLO messages may arrive after completion.
    local generation = run.generation
    local members = run.members
    if #members == 0 then return end
    local attempts = 0
    local function CheckMembers()
        if run.generation ~= generation or run.active then return end
        local allChanged = true
        for _, member in ipairs(members) do
            local unit = FindUnitByGUID(member.guid)
            if unit then
                local score = ReadUnitMythicPlusScore(unit)
                if score then member.scoreAfter = score end
            end
            if not member.scoreAfter or (member.scoreBefore and member.scoreAfter <= member.scoreBefore + 0.05) then
                allChanged = false
            end
        end
        attempts = attempts + 1
        if not allChanged and attempts < 4 and C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(2, CheckMembers)
        else
            AnnounceRunMembers(members, generation)
        end
    end
    local delay = GetRunAnnounceDelay()
    if delay > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, CheckMembers)
    else
        CheckMembers()
    end
end

local function AnnounceMemberWelcome(unit, guid, score, record, previousScore, previousSeen)
    local name = GetUnitDisplayName(unit)
    if not name then
        lastWelcomeIssue = "no name"
        return false
    end
    local region = ns.GetSelectedRegion()
    local regionLabel = GetRegionLabel()
    if not region or not regionLabel then
        lastWelcomeIssue = "no region"
        return false
    end
    local rank = EstimateRankForScore(region, score)
    if not rank then
        lastWelcomeIssue = "no rank"
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
        lastWelcomeIssue = "no template"
        return false
    end
    local sent, reason = Util.SendPartyMessage(message)
    if sent then
        lastWelcomeIssue = "sent"
        if record then
            record.score = score
            record.name = name
        end
        return true
    end
    lastWelcomeIssue = reason or "send failed"
    return false
end

local ProcessPendingWelcomes

local function ScheduleWelcomePoll()
    if welcomePollScheduled or next(pendingWelcomes) == nil then
        return
    end
    if not (C_Timer and type(C_Timer.After) == "function") then
        return
    end
    welcomePollScheduled = true
    C_Timer.After(WELCOME_RETRY_INTERVAL, function()
        welcomePollScheduled = false
        ProcessPendingWelcomes()
    end)
end

-- One pass over every member still waiting for a readable score. Members that
-- were greeted, left the party, or were cancelled by the key start leave the
-- queue; a single shared timer carries the remaining ones to the next pass.
ProcessPendingWelcomes = function()
    if run.active then
        ClearPendingWelcomes()
        lastWelcomeIssue = "cancelled"
        return
    end
    for guid, entry in pairs(pendingWelcomes) do
        if entry.generation ~= pollGeneration then
            pendingWelcomes[guid] = nil
            lastWelcomeIssue = "cancelled"
        else
            -- Roster reshuffles move members between party slots; re-locate by
            -- GUID. Only give up when they actually left the party.
            local unit = FindUnitByGUID(guid)
            if not unit then
                pendingWelcomes[guid] = nil
                lastWelcomeIssue = "member left"
            elseif not IsWelcomeEligible() then
                pendingWelcomes[guid] = nil
                lastWelcomeIssue = "welcome disabled"
            elseif ns.Announcer and not ns.Announcer.IsAnnouncer("welcome") then
                pendingWelcomes[guid] = nil
                lastWelcomeIssue = "not announcer"
            elseif IsCombatLocked() then
                lastWelcomeIssue = "combat lockdown"
            else
                local score = ReadUnitMythicPlusScore(unit)
                if not score then
                    -- Fall back to the score the Group Finder showed while this
                    -- member was still an applicant.
                    score = GetApplicantScore(unit)
                end
                local welcomed = score and AnnounceMemberWelcome(
                    unit, guid, score, entry.record, entry.previousScore, entry.previousSeen
                )
                if welcomed then
                    pendingWelcomes[guid] = nil
                elseif not score then
                    -- The client may have no cached rating for this player yet;
                    -- the shared poll retries until it becomes readable, the
                    -- member leaves, or the key starts.
                    lastWelcomeIssue = "no score"
                end
            end
        end
    end
    ScheduleWelcomePoll()
end

local function ScheduleMemberWelcome(guid, record, previousScore, previousSeen)
    pendingWelcomes[guid] = {
        record = record,
        previousScore = previousScore,
        previousSeen = previousSeen,
        generation = pollGeneration,
    }
end

-- A run whose completion event never arrived (abandoned key, leaving the
-- instance before the summary, disconnect) must not suppress later welcomes
-- and run summaries for the rest of the session.
local function ResetStaleRunState()
    if not run.active then
        return
    end
    if type(IsInInstance) ~= "function" then
        return
    end
    local ok, inInstance = pcall(IsInInstance)
    if ok and not inInstance then
        run.active = false
    end
end

-- Refreshes the tracked party roster. New members are greeted only when
-- announceNew is true (roster seeding at login must stay silent).
local function RefreshRoster(announceNew)
    PruneEncounters()
    ResetStaleRunState()
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
            if run.active or not announceNew then
                -- Mid-run joins stay ungreeted and roster seeding at login
                -- stays silent; both are still recorded as seen.
                welcomeState.known[guid] = true
            elseif IsWelcomeEligible() then
                welcomeState.known[guid] = true
                local record, previousScore, previousSeen = RecordEncounter(
                    guid,
                    GetUnitDisplayName(unit),
                    GetUnitRealm(unit)
                )
                if record then
                    ScheduleMemberWelcome(guid, record, previousScore, previousSeen)
                end
            end
            -- When the welcome setting is off (or the party state is still
            -- settling), the member is not marked as known so a later roster
            -- update can still greet them.
        end
    end
    -- In auto mode, let the HELLO exchange settle before electing the sender.
    if next(pendingWelcomes) ~= nil then
        if ns.Announcer and ns.GetAnnounceMode and ns.GetAnnounceMode() == "auto" then
            ScheduleWelcomePoll()
        else
            ProcessPendingWelcomes()
        end
    end
end

local eventFrame = CreateFrame("Frame")
local bannerSuppressed = false
local function SuppressBlizzardCompletionBanner()
    local banner = _G.ChallengeModeCompleteBanner
    if not banner then return end
    if not bannerSuppressed and type(banner.HookScript) == "function" then
        banner:HookScript("OnShow", function(self) self:Hide() end)
        bannerSuppressed = true
    end
    if type(banner.Hide) == "function" then banner:Hide() end
end

eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("LFG_LIST_APPLICANT_UPDATED")
eventFrame:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "CHALLENGE_MODE_START" then
        run.active = true
        run.generation = run.generation + 1
        run.members = CaptureRunMembers()
        -- Cancels every pending welcome poll chain.
        pollGeneration = pollGeneration + 1
        ClearPendingWelcomes()
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        SuppressBlizzardCompletionBanner()
        SchedulePostRunCheck()
    elseif event == "ADDON_LOADED" then
        SuppressBlizzardCompletionBanner()
    elseif event == "PLAYER_ENTERING_WORLD" then
        RefreshRoster(false)
    elseif event == "GROUP_ROSTER_UPDATE" then
        CacheApplicantScores()
        RefreshRoster(true)
    elseif event == "LFG_LIST_APPLICANT_UPDATED" or event == "LFG_LIST_APPLICANT_LIST_UPDATED" then
        CacheApplicantScores()
    end
end)

-- One-line state dump for the debug slash commands.
local function DescribeAnnounceState()
    local db = type(ns.GetDB) == "function" and ns.GetDB() or nil
    local knownCount = 0
    for _ in pairs(welcomeState.known) do
        knownCount = knownCount + 1
    end
    return table.concat({
        "announce:",
        "region=" .. tostring(ns.GetSelectedRegion and ns.GetSelectedRegion() or nil),
        "summary=" .. tostring(not (db and db.announceRunGain == false)),
        "welcome=" .. tostring(not (db and db.announceMemberJoin == false)),
        "teleport=" .. tostring(not (db and db.announceTeleport == false)),
        "delay=" .. tostring(db and db.announceDelay or nil),
        "runActive=" .. tostring(run.active == true),
        "known=" .. tostring(knownCount),
        "welcomeIssue=" .. tostring(lastWelcomeIssue),
        "members=" .. tostring(#GetPartyUnits()),
    }, " ")
end

-- Exposed for tests and diagnostics only.
ns.RunSummary = {
    AnnounceRunMembers = AnnounceRunMembers,
    CaptureRunMembers = CaptureRunMembers,
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
