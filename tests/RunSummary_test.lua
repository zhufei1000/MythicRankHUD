local scripts = {}
local chatMessages = {}
local timerQueue = {}
local playerScore = 3000
local dailyBaseline = 2968
local announceDelay = 5
local inGroup = true
local announcementEnabled = true

_G.IsInGroup = function() return inGroup end
_G.LE_PARTY_CATEGORY_HOME = 1
_G.SendChatMessage = function(message, channel)
    chatMessages[#chatMessages + 1] = { message = message, channel = channel }
end
_G.GetTime = function() return 0 end
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
        RUN_GAIN_UPDATE_TIME_FORMAT = " | Data updated %s",
        RUN_GAIN_ANNOUNCEMENT_FORMAT = "Run complete: +%s points | Rank up ~%s | Current %s rank ~%s",
        RUN_GAIN_NO_GAIN_FORMAT = "No score gain this run | Current %s rank ~%s",
        RUN_GAIN_NO_GAIN_TODAY_FORMAT = "No score gain this run | Current %s rank ~%s | Today +%s points, ~%s ranks",
        RUN_GAIN_ANNOUNCEMENT_TODAY_FORMAT = "Run complete: +%s points | Rank up ~%s | Current %s rank ~%s | Today +%s points, ~%s ranks",
        RUN_REGION_LABEL_CN = "CN",
    },
    Util = { SafeNumber = SafeNumber, SafeTable = SafeTable },
    GetSelectedRegion = function() return "cn" end,
    GetRegionLabel = function(region) return string.upper(region) end,
    IsRunGainAnnouncementEnabled = function() return announcementEnabled end,
    GetRunAnnounceDelay = function() return announceDelay end,
    GetDailyBaselineScore = function() return dailyBaseline end,
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

-- Baseline capture on run start.
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", "player")

-- Completion: waits for the configured delay, polls until Blizzard refreshes
-- the score, then announces with both the run gain and the daily gain.
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
StepTimer() -- announcement delay (5s) elapsed, score still 3000 -> poll
StepTimer() -- poll retry 1
playerScore = 3032
assert(#chatMessages == 0, "announced before the score was refreshed")
StepTimer() -- poll retry 2: score updated -> announce
assert(#chatMessages == 1, "run gain announcement was not sent")
local message = chatMessages[1].message
assert(chatMessages[1].channel == "PARTY", "run gain announcement did not use party chat")
assert(message == "Run complete: +32 points | Rank up ~320 | Current CN rank ~169680 | Today +64 points, ~640 ranks | Data updated 09-07 12:04",
    "run gain announcement text was incorrect: " .. tostring(message))
assert(not message:find("<QFX>"), "run gain announcement still carries the QFX suffix")
local converter = namespace.RunSummary and namespace.RunSummary.FormatDataVersionLocal
assert(converter("202609062044", "cn") == "09-07 04:44", "CN pack sample conversion was incorrect: " .. tostring(converter("202609062044", "cn")))
assert(converter("202609070404", "kr") == "09-07 13:04", "KR conversion was incorrect")
assert(converter("202609070404", "us") == "09-06 23:04", "US conversion was incorrect")
assert(converter("202609070404", "eu") == "09-07 05:04", "EU conversion was incorrect")
assert(converter("202612312359", "cn") == "01-01 07:59", "year rollover conversion was incorrect")
assert(converter("bad", "cn") == nil, "invalid dataVersion should not convert")
assert(not StepTimer(), "retry loop kept scheduling after announcing")

-- A second completion without a new run start has no baseline: skip silently.
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
playerScore = 3100
StepTimer()
StepTimer()
assert(#chatMessages == 1, "completed event without an active run announced again")

-- Score never improves (replay below previous best) -> still announced with 0 gain.
playerScore = 3100
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", "player")
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
for _ = 1, 5 do
    StepTimer()
end
assert(#chatMessages == 2, "a run without score gain was not announced")
assert(chatMessages[2].message == "No score gain this run | Current CN rank ~169000 | Today +132 points, ~1320 ranks | Data updated 09-07 12:04",
    "zero-gain announcement text was incorrect: " .. tostring(chatMessages[2].message))
assert(not StepTimer(), "retry loop kept scheduling after announcing")

-- Without a daily baseline the message falls back to the simple format.
dailyBaseline = nil
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", "player")
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
playerScore = 3200
StepTimer() -- delay
StepTimer() -- poll: score refreshed -> announce
assert(#chatMessages == 3, "announcement without baseline was not sent")
assert(chatMessages[3].message == "Run complete: +100 points | Rank up ~1000 | Current CN rank ~168000 | Data updated 09-07 12:04",
    "simple announcement text was incorrect: " .. tostring(chatMessages[3].message))
dailyBaseline = 2968

-- Disabled setting -> silent.
announcementEnabled = false
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", "player")
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
playerScore = 3300
StepTimer() -- delay
StepTimer() -- poll
assert(#chatMessages == 3, "announced while the setting was disabled")
announcementEnabled = true

-- Zero delay announces on the first timer tick after completion.
announceDelay = 0
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", "player")
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
playerScore = 3310
StepTimer()
assert(#chatMessages == 4, "zero delay did not announce after completion")
assert(chatMessages[4].message == "Run complete: +10 points | Rank up ~100 | Current CN rank ~166900 | Today +342 points, ~3420 ranks | Data updated 09-07 12:04",
    "zero delay announcement text was incorrect: " .. tostring(chatMessages[4].message))
announceDelay = 5

-- ---------------------------------------------------------------------------
-- Member join welcome scenarios.
-- ---------------------------------------------------------------------------
namespace.L.MEMBER_WELCOME_UPDATE_TIME_FORMAT = " (data updated %s)"
namespace.L.MEMBER_WELCOME_FORMAT = "%s | M+ score: %s | %s rank ~%s. Welcome aboard, good luck!"
local welcomeEnabled = true
namespace.IsMemberWelcomeEnabled = function() return welcomeEnabled end

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
assert(#chatMessages == 4, "login roster seeding announced a welcome")

-- A brand new member joining out of combat gets welcomed with score and rank.
unitGuids["party2"] = "GUID-NEW"
unitNames["party2"] = "新队友"
unitScores["party2"] = 3200
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(StepTimer(), "welcome timer was not scheduled")
assert(#chatMessages == 5, "new member welcome was not sent")
assert(chatMessages[5].message == "新队友 | M+ score: 3200 | CN rank ~168000. Welcome aboard, good luck! (data updated 09-07 12:04)",
    "member welcome text was incorrect: " .. tostring(chatMessages[5].message))
assert(chatMessages[5].channel == "PARTY", "member welcome did not use party chat")

-- The same player leaving and rejoining within the cooldown stays silent.
unitGuids["party2"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
unitGuids["party2"] = "GUID-NEW"
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(not StepTimer(), "rejoin within cooldown scheduled a welcome")
assert(#chatMessages == 5, "rejoin within cooldown announced again")

-- Joining during combat: greeting waits until out of combat.
combatLocked = true
unitGuids["party3"] = "GUID-COMBAT"
unitNames["party3"] = "战斗队友"
unitScores["party3"] = 3000
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
for _ = 1, 3 do
    StepTimer()
    assert(#chatMessages == 5, "announced while in combat")
end
combatLocked = false
StepTimer()
assert(#chatMessages == 6, "welcome was not sent after leaving combat")
assert(chatMessages[6].message == "战斗队友 | M+ score: 3000 | CN rank ~170000. Welcome aboard, good luck! (data updated 09-07 12:04)",
    "post-combat welcome text was incorrect: " .. tostring(chatMessages[6].message))

-- Roster reshuffle: member moved from party2 into party1 -> still greeted.
unitGuids["party2"] = "GUID-SHUFFLE"
unitNames["party2"] = "换位队友"
unitScores["party2"] = 2800
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
unitGuids["party2"] = nil
unitGuids["party1"] = "GUID-SHUFFLE"
unitNames["party1"] = "换位队友"
unitScores["party1"] = 2800
StepTimer()
assert(#chatMessages == 7, "shuffled member was not greeted")
assert(chatMessages[7].message == "换位队友 | M+ score: 2800 | CN rank ~172000. Welcome aboard, good luck! (data updated 09-07 12:04)",
    "shuffled member welcome text was incorrect: " .. tostring(chatMessages[7].message))

-- Member who left the party before the timer fires is skipped.
unitGuids["party4"] = "GUID-LEAVE"
unitNames["party4"] = "秒退队友"
unitScores["party4"] = 2600
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
unitGuids["party4"] = nil
StepTimer()
assert(#chatMessages == 7, "greeted a member who had already left")

-- Member whose score cannot be read: retries then stays silent.
unitGuids["party4"] = "GUID-NOSCORE"
unitNames["party4"] = "查不到分"
unitScores["party4"] = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
for _ = 1, 16 do
    StepTimer()
end
assert(#chatMessages == 7, "announced for a member without readable score")
assert(not StepTimer(), "retry loop kept scheduling after exhausting attempts")

-- Feature disabled -> silent.
welcomeEnabled = false
unitGuids["party4"] = "GUID-DISABLED"
unitNames["party4"] = "静默队友"
unitScores["party4"] = 2500
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
StepTimer()
assert(#chatMessages == 7, "announced while the setting was disabled")
welcomeEnabled = true

-- Raid conversion -> party units disappear, nothing is announced.
raidMode = true
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(not StepTimer(), "raid roster scheduled a welcome")
assert(#chatMessages == 7, "raid roster announced a welcome")
raidMode = false

-- Direct helper sanity checks.
local summary = namespace.RunSummary
assert(summary, "RunSummary namespace was not exposed")
assert(summary.ReadPlayerScore() == 3310, "ReadPlayerScore returned an unexpected value")
assert(summary.EstimateRankForScore("cn", 3000) == 170000, "rank estimate helper returned an unexpected value")

print("RunSummary_test: OK")
