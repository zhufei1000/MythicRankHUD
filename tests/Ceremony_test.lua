local timers = {}
local frames = {}
local sounds = {}
local score = 3000
local completionInfo
local defaultX, defaultY = -1.110935236012978, 274.444395477572
local settings = { enabled = true, sound = true, scale = 1, x = defaultX, y = defaultY, duration = 10 }
local cursorX, cursorY = 500, 500

local widgetMethods = {}
function widgetMethods:SetSize(width, height) self.width, self.height = width, height end
function widgetMethods:GetWidth() return self.width or 0 end
function widgetMethods:GetHeight() return self.height or 0 end
function widgetMethods:GetEffectiveScale() return 1 end
function widgetMethods:SetText(value) self.text = value end
function widgetMethods:GetStringWidth() return #(self.text or "") * 7 end
function widgetMethods:SetTexture(value) self.texture = value end
function widgetMethods:SetFrameStrata(value) self.strata = value end
function widgetMethods:SetPoint(point, relative, relativePoint, x, y)
    self.point = { point, relative, relativePoint, x, y }
end
function widgetMethods:SetScript(name, callback) self.scripts[name] = callback end
function widgetMethods:RegisterEvent(name) self.events[name] = true end
function widgetMethods:UnregisterEvent(name) self.events[name] = nil end
function widgetMethods:Show() self.visible = true end
function widgetMethods:Hide() self.visible = false end
function widgetMethods:IsShown() return self.visible == true end
function widgetMethods:SetShown(shown) self.visible = shown end
function widgetMethods:EnableMouse(enabled) self.mouse = enabled end
function widgetMethods:EnableMouseWheel(enabled) self.wheel = enabled end
function widgetMethods:RegisterForDrag(button) self.dragButton = button end
function widgetMethods:StartMoving() self.moving = true end
function widgetMethods:StopMovingOrSizing() self.moving = false end
function widgetMethods:SetUserPlaced(value) self.userPlaced = value end
function widgetMethods:SetAlpha(alpha) self.alpha = alpha end
function widgetMethods:CreateTexture() return setmetatable({ scripts = {}, events = {} }, { __index = widgetMethods }) end
function widgetMethods:CreateFontString() return self:CreateTexture() end
setmetatable(widgetMethods, { __index = function() return function() end end })

_G.UIParent = setmetatable({ height = 1080 }, { __index = widgetMethods })
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.GetCursorPosition = function() return cursorX, cursorY end
_G.SlashCmdList = {}
_G.CreateFrame = function(_, name)
    local frame = setmetatable({ name = name, scripts = {}, events = {} }, { __index = widgetMethods })
    frames[#frames + 1] = frame
    return frame
end
_G.C_Timer = { After = function(delay, callback)
    timers[#timers + 1] = { delay = delay, callback = callback }
end }
_G.PlaySoundFile = function(path) sounds[#sounds + 1] = path end
_G.hooksecurefunc = function(object, methodName, callback)
    local original = object[methodName]
    object[methodName] = function(self, ...)
        original(self, ...)
        callback(self, ...)
    end
end
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
        CEREMONY_UNLOCKED = "Unlocked", CEREMONY_LOCKED = "Locked",
        CEREMONY_POSITION_RESET = "Position reset",
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
    GetCeremonyDefaultPosition = function() return defaultX, defaultY end,
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

local ceremonyFrame, eventFrame, bannerWatcher
for _, frame in ipairs(frames) do
    if frame.name == "MythicRankHUDCeremonyFrame" then ceremonyFrame = frame end
    if frame.events.CHALLENGE_MODE_START and frame.events.CHALLENGE_MODE_COMPLETED then eventFrame = frame end
    if frame.events.ADDON_LOADED then bannerWatcher = frame end
end
assert(ceremonyFrame and eventFrame and bannerWatcher, "ceremony UI or events were not registered")
assert(ceremonyFrame.mouse == false and ceremonyFrame.wheel == false, "ceremony blocks mouse input")
assert(ceremonyFrame.strata == "MEDIUM", "ceremony image could sit behind the game UI")
assert(ceremonyFrame.dragButton == "LeftButton", "image is not draggable")
assert(ns.Ceremony.ReadCompletionInfo() == nil, "missing completion info was accepted")

bannerWatcher.scripts.OnEvent(bannerWatcher, "ADDON_LOADED", "AnotherAddOn")
assert(bannerWatcher.events.ADDON_LOADED, "unrelated addon load disabled the banner watcher")
local nativeMessages, finishedBanners = 0, 0
local nativeBanner = setmetatable({ scripts = {}, events = {}, PlayBanner = function(self)
    nativeMessages = nativeMessages + 1
    self:Show()
end, StopBanner = function(self)
    self.stopped = true
    self:Hide()
end }, { __index = widgetMethods })
_G.ChallengeModeCompleteBanner = nativeBanner
_G.TopBannerManager_BannerFinished = function() finishedBanners = finishedBanners + 1 end
bannerWatcher.scripts.OnEvent(bannerWatcher, "ADDON_LOADED", "Blizzard_ChallengesUI")
assert(not bannerWatcher.events.ADDON_LOADED and nativeBanner.alpha == 0,
    "native completion banner was not hidden when Blizzard UI loaded")
nativeBanner:PlayBanner()
assert(nativeMessages == 1 and nativeBanner.stopped and not nativeBanner:IsShown(),
    "hiding the native banner skipped its processing or left it visible")
assert(finishedBanners == 1, "hiding the native banner blocked the top-banner queue")

eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 2520)
score = 3032
completionInfo = {
    mapChallengeModeID = 586, level = 10, time = 1200,
    onTime = true, practiceRun = false,
    oldOverallDungeonScore = 3000, newOverallDungeonScore = 3032,
}
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
assert(ceremonyFrame:IsShown(), "completion did not show the result immediately")
assert(ceremonyFrame.point[1] == "TOP" and ceremonyFrame.point[3] == "CENTER"
    and ceremonyFrame.point[4] == defaultX and ceremonyFrame.point[5] == defaultY,
    "default image position does not match the saved placement")
assert(ceremonyFrame.emblem.texture:find("victory_emblem.png", 1, true), "victory image missing")
assert(ceremonyFrame.scoreRow.main.text == "Score: 3032", "current score was not shown")
assert(ceremonyFrame.scoreRow.delta.text == "32", "this run's score gain was not shown")
assert(ceremonyFrame.rankRow.main.text == "Rank: ~169680", "current estimated rank was not shown")
assert(ceremonyFrame.rankRow.delta.text == "~320", "this run's estimated rank gain was not shown")
assert(#sounds == 1, "result sound did not play once")

-- An overtime result must play immediately, even when the score did not rise.
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 2521)
completionInfo = {
    mapChallengeModeID = 587, level = 10, time = 1500,
    onTime = false, practiceRun = false,
    oldOverallDungeonScore = 3032, newOverallDungeonScore = 3032,
}
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
assert(ceremonyFrame.emblem.texture:find("defeat_emblem.png", 1, true), "defeat image missing")
assert(#sounds == 2 and sounds[2]:find("Defeat.ogg", 1, true), "overtime sound missing")
assert(ceremonyFrame.scoreRow.delta.text == "0", "zero score gain was hidden")
assert(ceremonyFrame.scoreRow.arrow.visible == false, "zero gain showed an upward arrow")
assert(ceremonyFrame.rankRow.delta.text == "~0", "zero rank gain was hidden")

-- The start event and completion info may use different map IDs. A mismatch
-- must not suppress the picture and sound.
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 2522)
completionInfo = {
    mapChallengeModeID = 588, level = 10, time = 1800,
    onTime = true, practiceRun = false,
    oldOverallDungeonScore = 3032, newOverallDungeonScore = 3100,
}
local soundCount = #sounds
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
assert(ceremonyFrame.emblem.texture:find("victory_emblem.png", 1, true),
    "mismatched map ID suppressed the victory image")
assert(ceremonyFrame.scoreRow.main.text == "Score: 3100",
    "completion score was not shown")
assert(#sounds == soundCount + 1, "mismatched map ID suppressed the sound")

-- Missing score data can hide number rows, but not the result itself.
score = nil
local readScore = ns.RunSummary.ReadPlayerScore
ns.RunSummary.ReadPlayerScore = function() error("score data unavailable") end
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 2523)
completionInfo = {
    mapChallengeModeID = 589, level = 10, time = 1900,
    onTime = false, practiceRun = false,
}
soundCount = #sounds
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
assert(ceremonyFrame.emblem.texture:find("defeat_emblem.png", 1, true),
    "missing score data suppressed the overtime image")
assert(#sounds == soundCount + 1, "missing score data suppressed the sound")
assert(ceremonyFrame.scoreRow.visible == false, "missing score data showed a score row")
ns.RunSummary.ReadPlayerScore = readScore
score = 3032

-- An optional rank-data failure must not prevent the result media from playing.
local estimateRank = ns.RunSummary.EstimateRankForScore
ns.RunSummary.EstimateRankForScore = function() error("rank data unavailable") end
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 2525)
completionInfo = {
    mapChallengeModeID = 591, level = 10, time = 2000,
    onTime = true, practiceRun = false,
    oldOverallDungeonScore = 3032, newOverallDungeonScore = 3050,
}
soundCount = #sounds
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
assert(ceremonyFrame.emblem.texture:find("victory_emblem.png", 1, true),
    "rank-data failure suppressed the victory image")
assert(#sounds == soundCount + 1, "rank-data failure suppressed the sound")
assert(ceremonyFrame.rankRow.visible == false, "failed rank estimate showed a rank row")
ns.RunSummary.EstimateRankForScore = estimateRank

SlashCmdList.QFXMYTHICCEREMONY("live")
assert(ceremonyFrame.scoreRow.main.text == "Score: 3032", "live test used sample score")
assert(ceremonyFrame.scoreRow.delta.visible == false, "live test invented a run gain")
assert(ceremonyFrame.rankRow.main.text == "Rank: ~169680", "live test used sample rank")

-- The local result is independent of party chat announcer election.
ns.Announcer = { IsAnnouncer = function() return false end }
local announcerSoundCount = #sounds
score = 3100
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 2524)
score = 3200
completionInfo = {
    mapChallengeModeID = 590, level = 10, time = 2400,
    onTime = true, practiceRun = false,
    oldOverallDungeonScore = 3100, newOverallDungeonScore = 3200,
}
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
assert(ceremonyFrame.emblem.texture:find("victory_emblem.png", 1, true),
    "a non-announcer lost the result image")
assert(#sounds == announcerSoundCount + 1,
    "a non-announcer lost the result sound")
ns.Announcer = nil

-- Older fade timers must leave the latest result alone.
for index = 1, #timers - 1 do
    timers[index].callback()
    assert(ceremonyFrame:IsShown(), "older fade timer hid the latest result")
end
timers[#timers].callback()
assert(type(ceremonyFrame.scripts.OnUpdate) == "function", "latest fade did not start")
ceremonyFrame.scripts.OnUpdate(ceremonyFrame, 2)
assert(not ceremonyFrame:IsShown(), "latest result did not fade out")

-- Unlocking shows a silent preview, cancels prior fade timers, and allows
-- mouse dragging. The saved offsets must be reused by later real results.
SlashCmdList.QFXMYTHICCEREMONY("victory")
local pendingFade = timers[#timers]
local soundBeforeUnlock = #sounds
SlashCmdList.QFXMYTHICCEREMONY("unlock")
assert(ceremonyFrame:IsShown() and ceremonyFrame.mouse == true, "unlock did not show a draggable preview")
assert(ns.Ceremony.IsUnlocked() == true, "settings cannot read the unlock state")
assert(ceremonyFrame.scoreRow.visible == false and ceremonyFrame.rankRow.visible == false,
    "unlock preview showed sample scores")
assert(#sounds == soundBeforeUnlock, "unlock preview played sound")
pendingFade.callback()
assert(ceremonyFrame:IsShown() and ceremonyFrame.scripts.OnUpdate == nil,
    "old fade timer interrupted the unlock preview")
ceremonyFrame.scripts.OnDragStart(ceremonyFrame)
assert(ceremonyFrame.moving == true and ceremonyFrame.userPlaced == false,
    "drag did not start or kept WoW layout-cache placement")
cursorX, cursorY = 620, 460
ceremonyFrame.scripts.OnDragStop(ceremonyFrame)
assert(settings.x == defaultX + 120 and settings.y == defaultY - 40, "drag offsets were not saved")
assert(ceremonyFrame.point[1] == "TOP" and ceremonyFrame.point[4] == defaultX + 120
    and ceremonyFrame.point[5] == defaultY - 40, "drag did not restore the saved anchor")
SlashCmdList.QFXMYTHICCEREMONY("lock")
assert(not ceremonyFrame:IsShown() and ceremonyFrame.mouse == false, "lock did not restore mouse passthrough")
assert(ns.Ceremony.IsUnlocked() == false, "settings cannot read the locked state")
SlashCmdList.QFXMYTHICCEREMONY("victory")
assert(ceremonyFrame.point[4] == defaultX + 120 and ceremonyFrame.point[5] == defaultY - 40,
    "real result lost the dragged position")
SlashCmdList.QFXMYTHICCEREMONY("resetpos")
assert(settings.x == defaultX and settings.y == defaultY and ceremonyFrame.point[4] == defaultX
    and ceremonyFrame.point[5] == defaultY, "resetpos did not restore default position")

print("Ceremony_test: OK")
