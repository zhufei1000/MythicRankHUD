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

local namespace = {
    L = {

        RUN_GAIN_LINE_GAIN = "This run: <{score}> points | Rank up <~{rankGain}>",
        RUN_GAIN_LINE_NO_GAIN = "No score gain this run",
        RUN_GAIN_LINE_TODAY = "Today: <{todayScore}> points | <~{todayRank}> ranks",
        RUN_GAIN_LINE_CURRENT = "Current score <{currentScore}> | {region} rank <~{rank}>",
        RUN_GAIN_LINE_AD = "[MythicRankHUD-{date}]",
        RUN_REGION_LABEL_CN = "CN",
        PACK_DATE_SEPARATOR = ".",
        WELCOME_TEAMMATE_FORMAT = "{name} | M+ score: <{score}> | {region} rank <~{rank}>",
        WELCOME_CLOSING_FORMAT = "Glad to run with you all, good luck!! MythicRankHUD-{date}",
    },
    Util = { SafeNumber = SafeNumber, SafeTable = SafeTable },
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

-- Baseline capture on run start; run start itself schedules nothing.
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", "player")
assert(not StepTimer(), "run start scheduled a timer")

-- Completion: waits for the configured delay, polls until Blizzard refreshes
-- the score, then announces the four summary lines one second apart.
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
StepTimer() -- announcement delay (5s) elapsed, score still 3000 -> poll
StepTimer() -- poll retry 1
playerScore = 3032
assert(#chatMessages == 0, "announced before the score was refreshed")
StepTimer() -- poll retry 2: score updated -> the four lines are queued
assert(#chatMessages == 0, "summary lines were sent without their spacing")
assert(StepTimer(), "summary line 1 was not scheduled")
assert(chatMessages[1].message == "This run: <32> points | Rank up <~320>",
    "summary line 1 was incorrect: " .. tostring(chatMessages[1].message))
assert(chatMessages[1].channel == "PARTY", "summary did not use party chat")
assert(StepTimer(), "summary line 2 was not scheduled")
assert(chatMessages[2].message == "Today: <64> points | <~640> ranks",
    "summary line 2 was incorrect: " .. tostring(chatMessages[2].message))
assert(StepTimer(), "summary line 3 was not scheduled")
assert(chatMessages[3].message == "Current score <3032> | CN rank <~169680>",
    "summary line 3 was incorrect: " .. tostring(chatMessages[3].message))
assert(StepTimer(), "summary line 4 was not scheduled")
assert(chatMessages[4].message == "[MythicRankHUD-9.7]",
    "summary line 4 was incorrect: " .. tostring(chatMessages[4].message))
for index = 1, 4 do
    assert(not chatMessages[index].message:find("<QFX>"), "summary still carries the QFX suffix")
end
assert(#chatMessages == 4, "the summary did not send exactly four lines")
assert(not StepTimer(), "retry loop kept scheduling after announcing")
local converter = namespace.RunSummary and namespace.RunSummary.FormatDataVersionLocal
assert(converter("202609062044", "cn") == "09-07 04:44", "CN pack sample conversion was incorrect: " .. tostring(converter("202609062044", "cn")))
assert(converter("202609070404", "kr") == "09-07 13:04", "KR conversion was incorrect")
assert(converter("202609070404", "us") == "09-06 23:04", "US conversion was incorrect")
assert(converter("202609070404", "eu") == "09-07 05:04", "EU conversion was incorrect")
assert(converter("202612312359", "cn") == "01-01 07:59", "year rollover conversion was incorrect")
assert(converter("bad", "cn") == nil, "invalid dataVersion should not convert")

-- A second completion without a new run start has no baseline: skip silently.
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
playerScore = 3100
DrainTimers()
assert(#chatMessages == 4, "completed event without an active run announced again")

-- Score never improves (replay below previous best): line 1 uses the no-gain
-- wording while today's gain is still reported.
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", "player")
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
DrainTimers()
assert(#chatMessages == 8, "a run without score gain was not announced")
assert(chatMessages[5].message == "No score gain this run",
    "zero-gain line 1 was incorrect: " .. tostring(chatMessages[5].message))
assert(chatMessages[6].message == "Today: <132> points | <~1320> ranks",
    "zero-gain line 2 was incorrect: " .. tostring(chatMessages[6].message))
assert(chatMessages[7].message == "Current score <3100> | CN rank <~169000>",
    "zero-gain line 3 was incorrect: " .. tostring(chatMessages[7].message))
assert(chatMessages[8].message == "[MythicRankHUD-9.7]",
    "zero-gain line 4 was incorrect: " .. tostring(chatMessages[8].message))
assert(not StepTimer(), "retry loop kept scheduling after announcing")

-- Without a daily baseline the today line is dropped: three lines remain.
dailyBaseline = nil
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", "player")
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
playerScore = 3200
DrainTimers()
assert(#chatMessages == 11, "summary without a baseline did not send three lines: " .. #chatMessages)
assert(chatMessages[9].message == "This run: <100> points | Rank up <~1000>",
    "baseline-free line 1 was incorrect: " .. tostring(chatMessages[9].message))
assert(chatMessages[10].message == "Current score <3200> | CN rank <~168000>",
    "baseline-free line 2 was incorrect: " .. tostring(chatMessages[10].message))
assert(chatMessages[11].message == "[MythicRankHUD-9.7]",
    "baseline-free line 3 was incorrect: " .. tostring(chatMessages[11].message))
dailyBaseline = 2968

-- Disabled setting -> silent.
announcementEnabled = false
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", "player")
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
playerScore = 3300
DrainTimers()
assert(#chatMessages == 11, "announced while the setting was disabled")
announcementEnabled = true

-- Zero delay queues the four lines as soon as the completion is handled.
announceDelay = 0
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", "player")
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
playerScore = 3310
DrainTimers()
assert(#chatMessages == 15, "zero delay did not announce after completion: " .. #chatMessages)
assert(chatMessages[12].message == "This run: <10> points | Rank up <~100>",
    "zero delay line 1 was incorrect: " .. tostring(chatMessages[12].message))
assert(chatMessages[13].message == "Today: <342> points | <~3420> ranks",
    "zero delay line 2 was incorrect: " .. tostring(chatMessages[13].message))
assert(chatMessages[14].message == "Current score <3310> | CN rank <~166900>",
    "zero delay line 3 was incorrect: " .. tostring(chatMessages[14].message))
assert(chatMessages[15].message == "[MythicRankHUD-9.7]",
    "zero delay line 4 was incorrect: " .. tostring(chatMessages[15].message))
announceDelay = 5

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

-- Member whose score cannot be read: polling keeps going instead of giving up.
unitGuids["party4"] = "GUID-NOSCORE"
unitNames["party4"] = "查不到分"
unitScores["party4"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
for _ = 1, 40 do
    StepTimer()
end
assert(#chatMessages == welcomeBase + 5, "announced for a member without readable score")
assert(StepTimer(), "polling gave up before the run started")
-- The member leaving stops the poll chain.
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
assert(#chatMessages == welcomeBase + 5, "announced while the setting was disabled")
assert(charDB.encounters["GUID-DISABLED"] == nil, "recorded an encounter while disabled")
welcomeEnabled = true

-- Raid conversion -> party units disappear, nothing is announced.
raidMode = true
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(not StepTimer(), "raid roster scheduled a welcome")
assert(#chatMessages == welcomeBase + 5, "raid roster announced a welcome")
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
assert(#chatMessages == welcomeBase + 6, "the month rollover was not announced")
assert(newRecord.count == 1, "the monthly encounter counter did not reset: " .. tostring(newRecord.count))
assert(chatMessages[welcomeBase + 6].message
        == "新队友 | met 1x | no change, push! | last " .. ExpectedMeetTime(firstMeetTime),
    "month-rollover welcome text was incorrect: " .. tostring(chatMessages[welcomeBase + 6].message))

-- A score change after the reset announces the new month count.
unitGuids["party2"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
unitScores["party2"] = 3300
unitGuids["party2"] = "GUID-NEW"
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(#chatMessages == welcomeBase + 7, "a changed score after the month reset was not announced")
assert(chatMessages[welcomeBase + 7].message
        == "新队友 | met 2x | up 50 | last " .. ExpectedMeetTime(rolloverTime),
    "post-reset welcome text was incorrect: " .. tostring(chatMessages[welcomeBase + 7].message))

-- A score drop is reported as well.
local scoreChangeTime = serverTime
unitGuids["party2"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
unitScores["party2"] = 3280
unitGuids["party2"] = "GUID-NEW"
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(#chatMessages == welcomeBase + 8, "a score drop was not announced")
assert(chatMessages[welcomeBase + 8].message
        == "新队友 | met 3x | down 20 | last " .. ExpectedMeetTime(scoreChangeTime),
    "score-drop welcome text was incorrect: " .. tostring(chatMessages[welcomeBase + 8].message))

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
assert(#chatMessages == welcomeBase + 8, "a cancelled poll announced a welcome")
unitScores["party4"] = 3400
assert(#chatMessages == welcomeBase + 8, "a welcome was announced after the run started")

unitGuids["party1"] = "GUID-MIDRUN"
unitNames["party1"] = "中途加入"
unitScores["party1"] = 3500
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(charDB.encounters["GUID-MIDRUN"] == nil, "recorded an encounter during the run")
assert(#chatMessages == welcomeBase + 8, "greeted a member who joined during the run")
assert(not StepTimer(), "a mid-run join scheduled a welcome poll")

-- Direct helper sanity checks.
local summary = namespace.RunSummary
assert(summary, "RunSummary namespace was not exposed")
assert(summary.ReadPlayerScore() == 3310, "ReadPlayerScore returned an unexpected value")
assert(summary.EstimateRankForScore("cn", 3000) == 170000, "rank estimate helper returned an unexpected value")
assert(summary.ExpandTemplate("hi {unknown}", {}) == "hi {unknown}", "unknown placeholders stay literal")
assert(summary.ExpandTemplate("100% {score}", { score = 5 }) == "100% 5", "percent signs must not break expansion")

print("RunSummary_test: OK")
