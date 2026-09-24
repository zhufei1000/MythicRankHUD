local scripts = {}
local chatMessages = {}
local timerQueue = {}
local savedDB = { encounters = {} }
local charDB = { encounters = {} }
local playerScore = 3000
local dailyBaseline = 2968
local announceDelay = 5
local inGroup = true
local announcementEnabled = true
local welcomeEnabled = false
local templateOverrides = {}

_G.IsInGroup = function() return inGroup end
_G.LE_PARTY_CATEGORY_HOME = 1
_G.SendChatMessage = function(message, channel)
    chatMessages[#chatMessages + 1] = { message = message, channel = channel }
end
_G.GetTime = function() return 0 end
local serverTime = 1789000000
_G.GetServerTime = function() return serverTime end
_G.C_Timer = {
    After = function(delay, callback)
        timerQueue[#timerQueue + 1] = { delay = delay, callback = callback }
    end,
}

-- Runs exactly one queued timer callback (mirrors one in-game timer tick).
local function StepTimer()
    local nextItem = table.remove(timerQueue, 1)
    if nextItem then
        nextItem.callback()
    end
    return nextItem ~= nil
end

-- Drains every pending timer, running the announcement chains to completion.
local function DrainTimers()
    while StepTimer() do end
end

_G.CreateFrame = function()
    local frame = {
        events = {},
        scripts = {},
        RegisterEvent = function(self, event) self.events[event] = true end,
        SetScript = function(self, name, callback) self.scripts[name] = callback end,
    }
    scripts[#scripts + 1] = frame
    return frame
end

_G.QFXMythicRankData = {
    GetPlayerScore = function() return playerScore end,
    EstimateRank = function(_, region, score, faction)
        assert(region == "cn", "estimate used the selected region")
        assert(faction == "all", "estimate used the all faction scope")
        return { estimatedRank = 200000 - score * 10 }
    end,
    GetMetadata = function() return { population = 200000, dataVersion = "202609070404" } end,
    GetCutoff = function(_, region, key, faction)
        assert(region == "cn", "cutoff used the selected region")
        assert(faction == "all", "cutoff used the all faction scope")
        local cutoffScores = { p999 = 3800, p990 = 3500, p900 = 3200, p750 = 3000, p600 = 2800 }
        return { score = cutoffScores[key], color = "#ff8000" }
    end,
    GetAchievementCutoff = function() return nil end,
}

local function SafeNumber(value)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        return value
    end
    return nil
end

local function SafeTable(value)
    if type(value) == "table" then
        return value
    end
    return nil
end

local function SafeString(value)
    return type(value) == "string" and value or nil
end

local function ClampNumber(value, minimum, maximum, fallback)
    local numberValue = tonumber(value)
    if not numberValue then
        return fallback
    end
    return math.max(minimum, math.min(maximum, numberValue))
end

local namespace = {
    L = {

        RUN_GAIN_LINE_GAIN = "This run: <{score}> points | Rank up <~{rankGain}>",
        RUN_GAIN_LINE_NO_GAIN = "No score gain this run",
        RUN_GAIN_LINE_TODAY = "Today: <{todayScore}> points | <~{todayRank}> ranks",
        RUN_GAIN_LINE_CURRENT = "Current score <{currentScore}> | {region} rank <~{rank}>",
        RUN_GAIN_LINE_AD = "[MythicRankHUD-{date}]",
        RUN_REGION_LABEL_CN = "CN",
        PACK_DATE_SEPARATOR = ".",
        TOP_PERCENT = "top %s%%",
        SMART_CUTOFF_LINE_FORMAT = "Top %s%% cutoff",
        RUN_NEXT_TARGET_FORMAT = "%s in %s pts",
        RUN_NEXT_TARGET_COMPLETE = "all targets reached",
        ACHIEVEMENT_KEYSTONE_EXPLORER = "Keystone Explorer",
        ACHIEVEMENT_KEYSTONE_CONQUEROR = "Keystone Conqueror",
        ACHIEVEMENT_KEYSTONE_MASTER = "Keystone Master",
        ACHIEVEMENT_KEYSTONE_HERO = "Keystone Hero",
        ACHIEVEMENT_KEYSTONE_LEGEND = "Keystone Legend",
    },
    Util = {
        SafeNumber = SafeNumber,
        SafeTable = SafeTable,
        SafeString = SafeString,
        ClampNumber = ClampNumber,
    },
    GetSelectedRegion = function() return "cn" end,
    GetRegionLabel = function(region) return string.upper(region) end,
    IsRunGainAnnouncementEnabled = function() return announcementEnabled end,
    IsMemberWelcomeEnabled = function() return welcomeEnabled end,
    GetRunAnnounceDelay = function() return announceDelay end,
    GetDailyBaselineScore = function() return dailyBaseline end,
    GetAnnounceTemplate = function(key) return templateOverrides[key] end,
    GetDB = function() return savedDB end,
    GetCharacterDB = function() return charDB end,
}

local modulePath = arg and arg[1] or "RunSummary.lua"
local addonName = arg and arg[2] or "MythicRankHUD"
local rankTargetChunk = assert(loadfile("RankTarget.lua"))
rankTargetChunk(addonName, namespace)
local chunk = assert(loadfile(modulePath))
chunk(addonName, namespace)

local eventFrame
for _, frame in ipairs(scripts) do
    if frame.events.CHALLENGE_MODE_START and frame.events.CHALLENGE_MODE_COMPLETED then
        eventFrame = frame
        break
    end
end
assert(eventFrame, "run summary event frame was not created")
assert(eventFrame.events.PLAYER_ENTERING_WORLD and eventFrame.events.GROUP_ROSTER_UPDATE,
    "roster events must be registered for the party-join welcome")

-- A run captures full identities and scores, but party chat uses short names.
local runGuids = { party1 = "GUID-A", party2 = "GUID-B" }
local runNames = { party1 = "同名-甲服", party2 = "同名-乙服" }
local runRealms = { party1 = "甲服", party2 = "乙服" }
local runScores = { party1 = 3000, party2 = 3200 }
_G.UnitGUID = function(unit) return runGuids[unit] end
_G.GetUnitName = function(unit) return runNames[unit] end
_G.UnitFullName = function(unit)
    local name = runNames[unit]
    return name and name:match("^([^-]+)") or nil, runRealms[unit]
end
_G.C_PlayerInfo = {
    GetPlayerMythicPlusRatingSummary = function(unit)
        return runScores[unit] and { currentSeasonScore = runScores[unit] } or nil
    end,
}

local utilNamespace = {}
assert(loadfile("Util.lua"))("MythicRankHUD", utilNamespace)
namespace.Util.SendPartyMessage = utilNamespace.Util.SendPartyMessage
namespace.L.RUN_MEMBER_LINE = "{name}: {score} +{scoreGain} | {rank} +{rankGain} | {nextTargetText}"
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START")
local captured = namespace.RunSummary.CaptureRunMembers()
assert(#captured == 2 and captured[1].fullName == "同名-甲服" and captured[2].fullName == "同名-乙服",
    "same-name members did not retain their realms")
assert(not StepTimer(), "run start scheduled an unexpected timer")
-- Roster slots swap while the key is active; GUID lookup must still match.
runGuids.party1, runGuids.party2 = runGuids.party2, runGuids.party1
runNames.party1, runNames.party2 = runNames.party2, runNames.party1
runRealms.party1, runRealms.party2 = runRealms.party2, runRealms.party1
runScores.party1, runScores.party2 = 3220, 3010
local banner = {
    shown = true,
    Hide = function(self) self.shown = false end,
    HookScript = function(self, event, callback) self[event] = callback end,
}
_G.ChallengeModeCompleteBanner = banner
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
assert(not banner.shown and type(banner.OnShow) == "function", "Blizzard completion banner was not suppressed")
banner.shown = true
banner.OnShow(banner)
assert(not banner.shown, "a later Blizzard banner show was not suppressed")
DrainTimers()
assert(#chatMessages == 3, "expected two teammate lines and one ad")
assert(chatMessages[1].message == "同名: 3010 +10 | 169900 +100 | top 10% in 190 pts", "first teammate result mismatch")
assert(chatMessages[2].message == "同名: 3220 +20 | 167800 +200 | top 1% in 280 pts", "second teammate result mismatch")
assert(chatMessages[3].message == "[MythicRankHUD-9.7]", "advertisement must be last")
assert(chatMessages[1].channel == "PARTY", "teammate summary used the wrong channel")
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
DrainTimers()
assert(#chatMessages == 3, "completion without start announced twice")
local converter = namespace.RunSummary.FormatDataVersionLocal
assert(converter("202609062044", "cn") == "09-07 04:44")
assert(converter("202609070404", "kr") == "09-07 13:04")
assert(converter("202609070404", "us") == "09-06 23:04")
assert(converter("202609070404", "eu") == "09-07 05:04")
assert(converter("202612312359", "cn") == "01-01 07:59")
assert(converter("bad", "cn") == nil)

-- A missing post-run score is not guessed.
runScores.party2 = nil
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START")
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
DrainTimers()
assert(chatMessages[5].message == "同名: -- +-- | -- +-- | ", "missing score was fabricated: " .. tostring(chatMessages[5].message))
assert(#chatMessages == 6, "missing score should still get one teammate line")
announcementEnabled = false
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START")
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
DrainTimers()
assert(#chatMessages == 6, "disabled announcement still sent chat")
announcementEnabled = true
runScores.party2 = 3010
-- The party-join welcome cases count from the summary messages above, so both
-- their totals and their indices are relative to this baseline.
local welcomeBase = #chatMessages
-- Member join welcome scenarios.
-- ---------------------------------------------------------------------------
namespace.L.MEMBER_WELCOME_FORMAT = "{name} | met {meetCount}x this month"
namespace.L.MEMBER_WELCOME_AGAIN_FORMAT =
    "{name} | met {meetCount}x | {scoreChangeText} | last {lastMeetTime}"
namespace.L.MEMBER_SCORE_UP_TEXT = "up %s"
namespace.L.MEMBER_SCORE_DOWN_TEXT = "down %s"
namespace.L.MEMBER_SCORE_SAME_TEXT = "no change, push!"
welcomeEnabled = true

-- The welcome shows the previous meeting time in the client timezone.
local function ExpectedMeetTime(timestamp)
    local parts = os.date("*t", timestamp)
    return string.format("%d-%d %02d:%02d", parts.month, parts.day, parts.hour, parts.min)
end

local unitGuids = {}
local unitNames = {}
local unitScores = {}
local combatLocked = false
local raidMode = false

_G.UnitGUID = function(unit) return unitGuids[unit] end
_G.GetUnitName = function(unit) return unitNames[unit] end
_G.InCombatLockdown = function() return combatLocked end
_G.IsInRaid = function() return raidMode end
_G.C_PlayerInfo = {
    GetPlayerMythicPlusRatingSummary = function(unit)
        local score = unitScores[unit]
        if score then
            return { currentSeasonScore = score }
        end
        return nil
    end,
}

-- Login seeding with an existing member must stay silent.
unitGuids["party1"] = "GUID-EXISTING"
unitNames["party1"] = "老队友"
unitScores["party1"] = 2000
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")
assert(#chatMessages == welcomeBase, "login roster seeding announced a welcome")

-- A brand new member joining out of combat is announced immediately with the
-- first-meeting template.
unitGuids["party2"] = "GUID-NEW"
unitNames["party2"] = "新队友"
unitScores["party2"] = 3200
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(#chatMessages == welcomeBase + 1, "new member welcome was not sent immediately")
assert(chatMessages[welcomeBase + 1].message == "新队友 | met 1x this month",
    "first-meeting welcome text was incorrect: " .. tostring(chatMessages[welcomeBase + 1].message))
assert(chatMessages[welcomeBase + 1].channel == "PARTY", "member welcome did not use party chat")
assert(not StepTimer(), "an immediate welcome should not schedule a retry")
local firstMeetTime = serverTime
local newRecord = charDB.encounters["GUID-NEW"]
assert(newRecord and newRecord.count == 1, "first encounter was not recorded")
assert(newRecord.score == 3200 and newRecord.name == "新队友", "encounter identity was not recorded")

-- A repeat meeting with an unchanged score still announces, with the
-- no-change wording and the previous meeting time.
unitGuids["party2"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
unitGuids["party2"] = "GUID-NEW"
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(#chatMessages == welcomeBase + 2, "an unchanged score was not announced")
assert(chatMessages[welcomeBase + 2].message
        == "新队友 | met 2x | no change, push! | last " .. ExpectedMeetTime(firstMeetTime),
    "unchanged-score welcome text was incorrect: " .. tostring(chatMessages[welcomeBase + 2].message))
assert(newRecord.count == 2, "the second encounter was not counted")

-- A changed score reports the increase and the previous meeting time.
unitGuids["party2"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
unitScores["party2"] = 3250
unitGuids["party2"] = "GUID-NEW"
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(#chatMessages == welcomeBase + 3, "a score change was not announced")
assert(chatMessages[welcomeBase + 3].message
        == "新队友 | met 3x | up 50 | last " .. ExpectedMeetTime(firstMeetTime),
    "changed-score welcome text was incorrect: " .. tostring(chatMessages[welcomeBase + 3].message))

-- Joining during combat: greeting waits until out of combat.
combatLocked = true
unitGuids["party3"] = "GUID-COMBAT"
unitNames["party3"] = "战斗队友"
unitScores["party3"] = 3000
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
for _ = 1, 3 do
    StepTimer()
    assert(#chatMessages == welcomeBase + 3, "announced while in combat")
end
combatLocked = false
StepTimer()
assert(#chatMessages == welcomeBase + 4, "welcome was not sent after leaving combat")
assert(chatMessages[welcomeBase + 4].message == "战斗队友 | met 1x this month",
    "post-combat welcome text was incorrect: " .. tostring(chatMessages[welcomeBase + 4].message))

-- Roster reshuffle: member changed slots -> known GUID stays silent.
unitGuids["party2"] = "GUID-SHUFFLE"
unitNames["party2"] = "换位队友"
unitScores["party2"] = 2800
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(#chatMessages == welcomeBase + 5, "new member was not greeted")
unitGuids["party2"] = nil
unitGuids["party1"] = "GUID-SHUFFLE"
unitNames["party1"] = "换位队友"
unitScores["party1"] = 2800
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(#chatMessages == welcomeBase + 5, "a roster reshuffle announced a second welcome")
assert(not StepTimer(), "a roster reshuffle scheduled a retry")

-- Member who left before their score became readable is skipped.
unitGuids["party4"] = "GUID-LEAVE"
unitNames["party4"] = "秒退队友"
unitScores["party4"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
unitGuids["party4"] = nil
StepTimer()
assert(#chatMessages == welcomeBase + 5, "greeted a member who had already left")

-- Member whose score is not readable yet: the slow poll keeps running every
-- retry interval until the score appears or the key starts.
unitGuids["party4"] = "GUID-NOSCORE"
unitNames["party4"] = "查不到分"
unitScores["party4"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
for _ = 1, 6 do
    StepTimer()
end
assert(#chatMessages == welcomeBase + 5, "greeted a member without a readable score")
assert(StepTimer(), "polling stopped before the score became readable")
-- The score appears later; the next poll sends the full welcome.
unitScores["party4"] = 3100
StepTimer()
assert(#chatMessages == welcomeBase + 6, "the welcome was not sent once the score became readable")
assert(chatMessages[welcomeBase + 6].message == "查不到分 | met 1x this month",
    "late welcome text was incorrect: " .. tostring(chatMessages[welcomeBase + 6].message))
assert(not StepTimer(), "polling continued after the welcome was sent")
-- The member leaving stops any remaining poll chain.
unitGuids["party4"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
while StepTimer() do end
assert(not StepTimer(), "polling continued after the member left")

-- Feature disabled -> silent and no encounter is recorded.
welcomeEnabled = false
unitGuids["party4"] = "GUID-DISABLED"
unitNames["party4"] = "静默队友"
unitScores["party4"] = 2500
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
StepTimer()
assert(#chatMessages == welcomeBase + 6, "announced while the setting was disabled")
assert(charDB.encounters["GUID-DISABLED"] == nil, "recorded an encounter while disabled")
welcomeEnabled = true

-- Raid conversion -> party units disappear, nothing is announced.
raidMode = true
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(not StepTimer(), "raid roster scheduled a welcome")
assert(#chatMessages == welcomeBase + 6, "raid roster announced a welcome")
raidMode = false

-- Records older than a month are pruned; recent records stay.
charDB.encounters["GUID-OLD"] = {
    score = 1000,
    count = 3,
    lastSeen = serverTime - (31 * 86400),
}
serverTime = serverTime + 3601
namespace.RunSummary.PruneEncounters()
assert(charDB.encounters["GUID-OLD"] == nil, "an expired encounter was not pruned")
assert(charDB.encounters["GUID-NEW"] ~= nil, "a recent encounter was pruned")

-- A new month resets the encounter counter; the unchanged score is still
-- announced with the previous meeting time from the old month.
serverTime = serverTime + (25 * 86400)
unitGuids["party2"] = nil
unitGuids["party4"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
local rolloverTime = serverTime
unitNames["party2"] = "新队友"
unitScores["party2"] = 3250
unitGuids["party2"] = "GUID-NEW"
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(#chatMessages == welcomeBase + 7, "the month rollover was not announced")
assert(newRecord.count == 1, "the monthly encounter counter did not reset: " .. tostring(newRecord.count))
assert(chatMessages[welcomeBase + 7].message
        == "新队友 | met 1x | no change, push! | last " .. ExpectedMeetTime(firstMeetTime),
    "month-rollover welcome text was incorrect: " .. tostring(chatMessages[welcomeBase + 7].message))

-- A score change after the reset announces the new month count.
unitGuids["party2"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
unitScores["party2"] = 3300
unitGuids["party2"] = "GUID-NEW"
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(#chatMessages == welcomeBase + 8, "a changed score after the month reset was not announced")
assert(chatMessages[welcomeBase + 8].message
        == "新队友 | met 2x | up 50 | last " .. ExpectedMeetTime(rolloverTime),
    "post-reset welcome text was incorrect: " .. tostring(chatMessages[welcomeBase + 8].message))

-- A score drop is reported as well.
local scoreChangeTime = serverTime
unitGuids["party2"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
unitScores["party2"] = 3280
unitGuids["party2"] = "GUID-NEW"
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(#chatMessages == welcomeBase + 9, "a score drop was not announced")
assert(chatMessages[welcomeBase + 9].message
        == "新队友 | met 3x | down 20 | last " .. ExpectedMeetTime(scoreChangeTime),
    "score-drop welcome text was incorrect: " .. tostring(chatMessages[welcomeBase + 9].message))

-- Several members waiting for scores share one poll timer instead of one
-- retry chain per teammate.
local sharedBase = #chatMessages
unitGuids["party1"] = "GUID-SH1"
unitGuids["party2"] = "GUID-SH2"
unitGuids["party3"] = "GUID-SH3"
unitNames["party1"] = "共享甲"
unitNames["party2"] = "共享乙"
unitNames["party3"] = "共享丙"
unitScores["party1"] = nil
unitScores["party2"] = nil
unitScores["party3"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(#timerQueue == 1, "pending welcomes did not share a single poll timer")
unitScores["party1"] = 3000
unitScores["party2"] = 3100
unitScores["party3"] = 3200
StepTimer()
assert(#chatMessages == sharedBase + 3, "the shared poll did not greet every waiting member")
assert(#timerQueue == 0, "the poll timer survived after every welcome was sent")
unitGuids["party1"] = nil
unitGuids["party2"] = nil
unitGuids["party3"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")

-- Applicant score cache: a member who applied through the Group Finder is
-- greeted immediately with the score the applicant list exposed, even while
-- the unit rating API still has no data for them.
local applicantBase = #chatMessages
_G.C_LFGList = {
    GetApplicants = function() return { 1 } end,
    GetApplicantInfo = function() return { numMembers = 1 } end,
    GetApplicantMemberInfo = function(_, memberIndex)
        if memberIndex == 1 then
            -- Applicant member shape: name, class, localizedClass, level,
            -- itemLevel, honorLevel, tank, healer, damage, assignedRole,
            -- relationship, dungeonScore.
            return "缓存队友", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 3333
        end
        return nil
    end,
}
eventFrame.scripts.OnEvent(eventFrame, "LFG_LIST_APPLICANT_UPDATED", 1)
unitGuids["party3"] = "GUID-CACHE"
unitNames["party3"] = "缓存队友"
unitScores["party3"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(#chatMessages == applicantBase + 1, "the cached applicant score was not used")
assert(chatMessages[applicantBase + 1].message == "缓存队友 | met 1x this month",
    "cached welcome text was incorrect: " .. tostring(chatMessages[applicantBase + 1].message))
assert(#timerQueue == 0, "a cached welcome still scheduled a poll")
unitGuids["party3"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")

-- Starting the run cancels every pending welcome poll and members joining
-- mid-run are not greeted or recorded.
unitGuids["party4"] = "GUID-POLL"
unitNames["party4"] = "轮询队友"
unitScores["party4"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(StepTimer(), "a pending welcome poll was not scheduled")
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", "player")
while StepTimer() do end
assert(not StepTimer(), "a pending welcome poll survived the run start")
assert(#chatMessages == welcomeBase + 13, "a cancelled poll announced a welcome")
unitScores["party4"] = 3400
assert(#chatMessages == welcomeBase + 13, "a welcome was announced after the run started")

unitGuids["party1"] = "GUID-MIDRUN"
unitNames["party1"] = "中途加入"
unitScores["party1"] = 3500
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(charDB.encounters["GUID-MIDRUN"] == nil, "recorded an encounter during the run")
assert(#chatMessages == welcomeBase + 13, "greeted a member who joined during the run")
assert(not StepTimer(), "a mid-run join scheduled a welcome poll")

-- Retail chat uses C_ChatInfo even when the deprecated global is absent.
local legacySender = _G.SendChatMessage
_G.SendChatMessage = nil
_G.C_ChatInfo = {
    InChatMessagingLockdown = function() return false end,
    SendChatMessage = function(message, channel)
        chatMessages[#chatMessages + 1] = { message = message, channel = channel }
    end,
}
local sent = namespace.RunSummary.AnnounceMemberWelcome("party1", "GUID-MIDRUN", 3500)
assert(sent and chatMessages[#chatMessages].message == "中途加入 | met 1x this month",
    "member welcome required the removed global chat function")

-- A stray pipe is retried with a full-width bar instead of failing with an
-- "Invalid escape code" chat error.
local escapeRetry
_G.C_ChatInfo.SendChatMessage = function(message, channel)
    if message:find("|", 1, true) then
        error("SendChatMessage(): Invalid escape code in chat message")
    end
    escapeRetry = { message = message, channel = channel }
end
local retried, retryReason = namespace.Util.SendPartyMessage("名 | 分")
assert(retried, "escape retry failed: " .. tostring(retryReason))
assert(escapeRetry and escapeRetry.message == "名 ｜ 分", "escape retry text mismatch")

_G.C_ChatInfo.InChatMessagingLockdown = function() return true end
local blocked, reason = namespace.Util.SendPartyMessage("blocked chat")
assert(not blocked and reason == "chat lockdown", "chat lockdown was not reported")
_G.C_ChatInfo = nil
_G.SendChatMessage = legacySender

-- Direct helper sanity checks.
local summary = namespace.RunSummary
assert(summary, "RunSummary namespace was not exposed")
assert(summary.ReadPlayerScore() == 3000, "ReadPlayerScore returned an unexpected value")
assert(summary.EstimateRankForScore("cn", 3000) == 170000, "rank estimate helper returned an unexpected value")
assert(summary.ExpandTemplate("hi {unknown}", {}) == "hi {unknown}", "unknown placeholders stay literal")
assert(summary.ExpandTemplate("100% {score}", { score = 5 }) == "100% 5", "percent signs must not break expansion")

-- Auto mode waits for the HELLO exchange, then checks the elected sender.
announcementEnabled = false
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
timerQueue = {}
for unit in pairs(unitGuids) do unitGuids[unit] = nil end
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
local elected = false
namespace.Announcer = { IsAnnouncer = function() return elected end }
namespace.GetAnnounceMode = function() return "auto" end
local autoBase = #chatMessages
unitGuids.party2 = "GUID-AUTO-SILENT"
unitNames.party2 = "自动静默"
unitScores.party2 = 3100
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(#chatMessages == autoBase and #timerQueue == 1, "auto welcome did not wait for election")
StepTimer()
assert(#chatMessages == autoBase, "non-elected member sent a welcome")
unitGuids.party2 = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
elected = true
unitGuids.party2 = "GUID-AUTO-ELECTED"
unitNames.party2 = "自动当选"
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(#chatMessages == autoBase, "elected member announced before election settled")
StepTimer()
assert(#chatMessages == autoBase + 1, "elected member did not send the welcome")

-- A completion-time non-announcer can become the sender before score polling
-- finishes; it must keep the run snapshot until the final election check.
welcomeEnabled = false
announcementEnabled = true
elected = false
timerQueue = {}
local summaryBase = #chatMessages
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START")
unitScores.party2 = 3120
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
assert(#timerQueue == 1, "post-run score check was skipped before election settled")
elected = true
DrainTimers()
assert(#chatMessages > summaryBase, "newly elected member lost the run summary")

print("RunSummary_test: OK")
