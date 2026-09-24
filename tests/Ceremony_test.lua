local timers = {}
local frames = {}
local sounds = {}
local score = 3000
local completionInfo
local now = 100
local settings = { enabled = true, sound = true, scale = 1, y = 0, duration = 10 }

local widgetMethods = {}
function widgetMethods:SetSize(width, height) self.width, self.height = width, height end
function widgetMethods:GetWidth() return self.width or 0 end
function widgetMethods:GetHeight() return self.height or 0 end
function widgetMethods:SetText(value) self.text = value end
function widgetMethods:GetStringWidth() return #(self.text or "") * 7 end
function widgetMethods:SetTexture(value) self.texture = value end
function widgetMethods:SetPoint(point, relative, relativePoint, x, y)
    self.point = { point, relative, relativePoint, x, y }
end
function widgetMethods:SetScript(name, callback) self.scripts[name] = callback end
function widgetMethods:RegisterEvent(name) self.events[name] = true end
function widgetMethods:Show() self.visible = true end
function widgetMethods:Hide() self.visible = false end
function widgetMethods:IsShown() return self.visible == true end
function widgetMethods:SetShown(shown) self.visible = shown end
function widgetMethods:EnableMouse(enabled) self.mouse = enabled end
function widgetMethods:EnableMouseWheel(enabled) self.wheel = enabled end
function widgetMethods:SetAlpha(alpha) self.alpha = alpha end
function widgetMethods:CreateTexture() return setmetatable({ scripts = {}, events = {} }, { __index = widgetMethods }) end
function widgetMethods:CreateFontString() return self:CreateTexture() end
setmetatable(widgetMethods, { __index = function() return function() end end })

_G.UIParent = setmetatable({ height = 1080 }, { __index = widgetMethods })
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.SlashCmdList = {}
_G.CreateFrame = function(_, name)
    local frame = setmetatable({ name = name, scripts = {}, events = {} }, { __index = widgetMethods })
    frames[#frames + 1] = frame
    return frame
end
_G.C_Timer = { After = function(delay, callback)
    timers[#timers + 1] = { delay = delay, callback = callback }
end }
_G.GetTime = function() return now end
_G.PlaySoundFile = function(path) sounds[#sounds + 1] = path end
_G.C_ChallengeMode = {
    GetChallengeCompletionInfo = function() return completionInfo end,
    GetOverallDungeonScore = function() return score end,
}

local function SafeNumber(value)
    if type(value) == "number" and value == value then return value end
    return nil
end

local ns = {
    L = {
        CEREMONY_SCORE = "Score: ", CEREMONY_RANK = "Rank: ",
        CEREMONY_TEST_TITLE = "Test", CEREMONY_TEST_VICTORY = "Victory",
        CEREMONY_TEST_DEFEAT = "Defeat", CEREMONY_SOUND = "Sound: ",
        CEREMONY_RESET = "Reset", CEREMONY_SCALE = "Scale %.2f", CEREMONY_HELP = "Help",
    },
    Util = {
        SafeNumber = SafeNumber,
        SafeBoolean = function(value) return type(value) == "boolean" and value or nil end,
        SafeTable = function(value) return type(value) == "table" and value or nil end,
        IsAccessible = function() return true end,
        ClampNumber = function(value, minValue, maxValue, fallback)
            value = tonumber(value)
            return value and math.max(minValue, math.min(maxValue, value)) or fallback
        end,
    },
    GetDB = function() return { ceremony = settings } end,
    GetSelectedRegion = function() return "cn" end,
    RunSummary = {
        ReadPlayerScore = function() return score end,
        EstimateRankForScore = function(region, value)
            assert(region == "cn", "rank estimate used the wrong region")
            return 200000 - value * 10
        end,
    },
}

assert(loadfile("Ceremony.lua"))("MythicRankHUD", ns)

local ceremonyFrame, eventFrame
for _, frame in ipairs(frames) do
    if frame.name == "MythicRankHUDCeremonyFrame" then ceremonyFrame = frame end
    if frame.events.CHALLENGE_MODE_START and frame.events.CHALLENGE_MODE_COMPLETED then eventFrame = frame end
end
assert(ceremonyFrame and eventFrame, "ceremony UI or events were not registered")
assert(ceremonyFrame.mouse == false and ceremonyFrame.wheel == false, "ceremony blocks mouse input")
completionInfo = { mapChallengeModeID = 0 }
assert(ns.Ceremony.ReadCompletionInfo() == nil, "empty completion info was accepted")

local function StepTimer()
    local item = table.remove(timers, 1)
    assert(item, "expected a timer")
    now = now + item.delay
    item.callback()
end

eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 586)
score = 3032
completionInfo = {
    mapChallengeModeID = 586, level = 10, time = 1200,
    onTime = true, practiceRun = false,
    oldOverallDungeonScore = 3000, newOverallDungeonScore = 3032,
}
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
StepTimer()
assert(ceremonyFrame.emblem.texture:find("victory_emblem.png", 1, true), "victory image missing")
assert(ceremonyFrame.scoreRow.main.text == "Score: 3032", "current score was not shown")
assert(ceremonyFrame.scoreRow.delta.text == "32", "this run's score gain was not shown")
assert(ceremonyFrame.rankRow.main.text == "Rank: ~169680", "current estimated rank was not shown")
assert(ceremonyFrame.rankRow.delta.text == "~320", "this run's estimated rank gain was not shown")
assert(#sounds == 1, "result sound did not play once")

-- A run with no gain still reports zero, without a green upward arrow.
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 587)
completionInfo = {
    mapChallengeModeID = 587, level = 10, time = 1500,
    onTime = false, practiceRun = false,
    oldOverallDungeonScore = 3032, newOverallDungeonScore = 3032,
}
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
StepTimer() -- old result's fade timer, which must not affect the next result
StepTimer() -- new result
assert(ceremonyFrame.emblem.texture:find("defeat_emblem.png", 1, true), "defeat image missing")
assert(ceremonyFrame.scoreRow.delta.text == "0", "zero score gain was hidden")
assert(ceremonyFrame.scoreRow.arrow.visible == false, "zero gain showed an upward arrow")
assert(ceremonyFrame.rankRow.delta.text == "~0", "zero rank gain was hidden")

-- Completion data that never matches the local run start (e.g. a lagging
-- local score cache) must still show the result after the retry window
-- instead of silently swallowing the whole ceremony.
timers = {}
score = 3100
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 588)
completionInfo = {
    mapChallengeModeID = 588, level = 10, time = 1800,
    onTime = true, practiceRun = false,
    oldOverallDungeonScore = 3000, newOverallDungeonScore = 3100,
}
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
for _ = 1, 8 do
    StepTimer()
end
assert(ceremonyFrame.emblem.texture:find("victory_emblem.png", 1, true),
    "late completion data did not show the victory image")
assert(ceremonyFrame.scoreRow.main.text == "Score: 3100",
    "late completion data did not show the completion score")
assert(ceremonyFrame.scoreRow.delta.text == "100",
    "late completion data did not use the completion pre-run score")

-- A previous dungeon result must never select this run's image and sound.
timers = {}
local soundCount = #sounds
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 589)
completionInfo.mapChallengeModeID = 588
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
for _ = 1, 8 do StepTimer() end
assert(#sounds == soundCount, "stale dungeon info played a result sound")
assert(ceremonyFrame.emblem.texture:find("victory_emblem.png", 1, true),
    "stale dungeon info replaced the displayed result")
score = 3032

SlashCmdList.QFXMYTHICCEREMONY("live")
assert(ceremonyFrame.scoreRow.main.text == "Score: 3032", "live test used sample score")
assert(ceremonyFrame.scoreRow.delta.visible == false, "live test invented a run gain")
assert(ceremonyFrame.rankRow.main.text == "Rank: ~169680", "live test used sample rank")

-- The result image and sound are local and must play for every party member;
-- only the party chat announcements are limited to the elected announcer.
timers = {}
ns.Announcer = { IsAnnouncer = function() return false end }
local announcerSoundCount = #sounds
score = 3100
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 590)
score = 3200
completionInfo = {
    mapChallengeModeID = 590, level = 10, time = 2400,
    onTime = true, practiceRun = false,
    oldOverallDungeonScore = 3100, newOverallDungeonScore = 3200,
}
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
StepTimer()
assert(ceremonyFrame.emblem.texture:find("victory_emblem.png", 1, true),
    "a non-announcer lost the result image")
assert(#sounds == announcerSoundCount + 1,
    "a non-announcer lost the result sound")
ns.Announcer = nil

print("Ceremony_test: OK")
