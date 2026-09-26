local ADDON_NAME, ns = ...
local L = ns.L
local Util = ns.Util
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Ceremony\\"

local SIZE_FACTOR = 0.72
local FADE_DURATION = 2
local ROW_GAP = 12
local DELTA_GAP = 7

local PREFIX = "|cffd9b85cQFX Ceremony|r "
local debugEnabled = false

local function JoinArgs(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(index, ...)))
    end
    return table.concat(parts, " ")
end

local function DebugPrint(...)
    if debugEnabled then
        print(PREFIX .. JoinArgs(...))
    end
end

-- Problems that silently swallow the result screen are always reported so a
-- missing ceremony can be diagnosed from the chat frame.
local function WarnPrint(...)
    print(PREFIX .. "|cffff8080" .. JoinArgs(...) .. "|r")
end

local function DescribeValue(value)
    local valueType = type(value)
    if valueType == "nil" then
        return "nil"
    end
    if not Util.IsAccessible(value) then
        return "<" .. valueType .. ">(secret)"
    end
    if valueType == "number" or valueType == "string" or valueType == "boolean" then
        local ok, text = pcall(tostring, value)
        local result = ok and text or ("<" .. valueType .. ">")
        return result
    end
    return valueType
end

local function GetSettings()
    local db = type(ns.GetDB) == "function" and ns.GetDB() or nil
    return db and db.ceremony or nil
end

local function SafeNumeric(value)
    if type(value) == "number" then
        return Util.SafeNumber(value)
    end
    if type(value) == "string" and Util.IsAccessible(value) then
        return Util.SafeNumber(tonumber(value))
    end
    return nil
end

local function FormatScore(value)
    local rounded = math.floor(value * 10 + 0.5) / 10
    if rounded == math.floor(rounded) then
        return tostring(math.floor(rounded))
    end
    return string.format("%.1f", rounded)
end

local function FormatRank(value)
    return tostring(math.floor(value + 0.5))
end

local frame = CreateFrame("Frame", ADDON_NAME .. "CeremonyFrame", UIParent)
frame:SetSize(600, 580)
frame:SetFrameStrata("MEDIUM")
frame:SetFrameLevel(120)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:EnableMouse(false)
frame:EnableMouseWheel(false)
frame:Hide()

frame.emblem = frame:CreateTexture(nil, "ARTWORK")
frame.emblem:SetAllPoints()

local function MakeText(parent, size, r, g, b)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    text:SetTextColor(r, g, b, 1)
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 0.9)
    return text
end

local function CreateInfoRow(y)
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(390, 38)
    row:SetPoint("CENTER", frame, "TOP", 0, y)
    row:EnableMouse(false)
    row:EnableMouseWheel(false)

    row.main = MakeText(row, 22, 1, 0.89, 0.66)
    row.main:SetJustifyH("RIGHT")

    row.arrow = row:CreateTexture(nil, "OVERLAY")
    row.arrow:SetTexture(MEDIA .. "green_up_arrow_taper_mask.png")
    row.arrow:SetVertexColor(0.25, 1, 0.25)
    row.arrow:SetSize(26, 26)
    row.arrow:SetBlendMode("ADD")

    row.delta = MakeText(row, 20, 0.32, 1, 0.34)
    return row
end

frame.scoreRow = CreateInfoRow(-430)
frame.rankRow = CreateInfoRow(-490)

local resultSerial = 0
local unlocked = false

local GetDefaultPosition = ns.GetCeremonyDefaultPosition

local function ApplyPosition(settings)
    local defaultX, defaultY = GetDefaultPosition()
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "CENTER",
        Util.ClampNumber(settings.x, -2000, 2000, defaultX),
        Util.ClampNumber(settings.y, -2000, 2000, defaultY))
end

local dragStartX, dragStartY
frame:SetScript("OnDragStart", function(self)
    if not unlocked or type(GetCursorPosition) ~= "function" then return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
    local ok, x, y = pcall(GetCursorPosition)
    x, y = ok and Util.SafeNumber(x), ok and Util.SafeNumber(y)
    if not x or not y then return end
    dragStartX, dragStartY = x, y
    self:StartMoving()
    self:SetUserPlaced(false)
end)

frame:SetScript("OnDragStop", function(self)
    if not dragStartX then return end
    self:StopMovingOrSizing()
    self:SetUserPlaced(false)
    local settings = GetSettings()
    local ok, x, y = pcall(GetCursorPosition)
    local scaleOK, scale = pcall(UIParent.GetEffectiveScale, UIParent)
    x, y = ok and Util.SafeNumber(x), ok and Util.SafeNumber(y)
    scale = scaleOK and Util.SafeNumber(scale) or nil
    if settings and x and y and scale and scale > 0 then
        settings.x = Util.ClampNumber((settings.x or 0) + (x - dragStartX) / scale, -2000, 2000, 0)
        settings.y = Util.ClampNumber((settings.y or 0) + (y - dragStartY) / scale, -2000, 2000, 0)
    end
    dragStartX, dragStartY = nil, nil
    if settings then ApplyPosition(settings) end
end)

local function SetUnlocked(value)
    local settings = GetSettings()
    if not settings then return end
    unlocked = value
    resultSerial = resultSerial + 1
    frame:SetScript("OnUpdate", nil)
    frame:EnableMouse(value)
    if value then
        frame.emblem:SetTexture(MEDIA .. "victory_emblem.png")
        frame.scoreRow:Hide()
        frame.rankRow:Hide()
        frame:SetScale(Util.ClampNumber(settings.scale, 0.5, 1.5, 1) * SIZE_FACTOR)
        ApplyPosition(settings)
        frame:SetAlpha(1)
        frame:Show()
        print(PREFIX .. L.CEREMONY_UNLOCKED)
    else
        frame:Hide()
        print(PREFIX .. L.CEREMONY_LOCKED)
    end
end

local function SetRow(row, label, value, delta, formatter, estimated)
    if value == nil then
        row:Hide()
        return
    end

    row:Show()
    row.main:SetText(label .. (estimated and "~" or "") .. formatter(value))
    row.main:ClearAllPoints()
    row.arrow:ClearAllPoints()
    row.delta:ClearAllPoints()

    if delta == nil then
        row.arrow:Hide()
        row.delta:Hide()
        row.main:SetPoint("CENTER", row, "CENTER", 0, 0)
        return
    end

    row.delta:Show()
    row.delta:SetText((estimated and "~" or "") .. formatter(delta))
    local mainWidth = row.main:GetStringWidth()
    local deltaWidth = row.delta:GetStringWidth()

    if delta > 0 then
        row.arrow:Show()
        row.delta:SetTextColor(0.32, 1, 0.34, 1)
        local rightWidth = ROW_GAP + row.arrow:GetWidth() + DELTA_GAP + deltaWidth
        local mainRight = (mainWidth - rightWidth) / 2
        row.main:SetPoint("RIGHT", row, "CENTER", mainRight, 0)
        row.arrow:SetPoint("LEFT", row, "CENTER", mainRight + ROW_GAP, 0)
        row.delta:SetPoint("LEFT", row.arrow, "RIGHT", DELTA_GAP, 0)
    else
        row.arrow:Hide()
        row.delta:SetTextColor(0.65, 0.7, 0.7, 1)
        local mainRight = (mainWidth - ROW_GAP - deltaWidth) / 2
        row.main:SetPoint("RIGHT", row, "CENTER", mainRight, 0)
        row.delta:SetPoint("LEFT", row, "CENTER", mainRight + ROW_GAP, 0)
    end
end

local function ShowResult(isVictory, score, scoreDelta, rank, rankDelta, estimatedRank)
    local settings = GetSettings()
    if not settings or settings.enabled == false then
        DebugPrint("result skipped: ceremony disabled")
        return
    end

    local victory = not not isVictory
    frame.emblem:SetTexture(MEDIA .. (victory and "victory_emblem.png" or "defeat_emblem.png"))
    frame.scoreRow:ClearAllPoints()
    frame.scoreRow:SetPoint("CENTER", frame, "TOP", 0, victory and -430 or -419)
    frame.rankRow:ClearAllPoints()
    frame.rankRow:SetPoint("CENTER", frame, "TOP", 0, victory and -490 or -476)

    score = SafeNumeric(score)
    scoreDelta = SafeNumeric(scoreDelta)
    rank = SafeNumeric(rank)
    rankDelta = SafeNumeric(rankDelta)
    SetRow(frame.scoreRow, L.CEREMONY_SCORE, score, scoreDelta, FormatScore, false)
    SetRow(frame.rankRow, L.CEREMONY_RANK, rank, rankDelta, FormatRank, estimatedRank == true)

    frame:SetScale(Util.ClampNumber(settings.scale, 0.5, 1.5, 1) * SIZE_FACTOR)
    ApplyPosition(settings)
    frame:SetScript("OnUpdate", nil)
    frame:SetAlpha(1)
    frame:Show()

    if settings.sound ~= false then
        local soundPath = MEDIA .. (victory and "Victory.ogg" or "Defeat.ogg")
        local ok, played = pcall(PlaySoundFile, soundPath, "Master")
        if not ok then
            WarnPrint("sound failed: " .. tostring(played))
        elseif played == false then
            WarnPrint("sound could not play: " .. soundPath)
        end
    end

    DebugPrint(string.format(
        "showing %s score=%s delta=%s rank=%s rankDelta=%s visible=%s",
        victory and "victory" or "defeat",
        tostring(score), tostring(scoreDelta), tostring(rank), tostring(rankDelta),
        tostring(frame:IsShown())))

    resultSerial = resultSerial + 1
    if unlocked then return end
    local thisResult = resultSerial
    local duration = Util.ClampNumber(settings.duration, 0.1, 60, 10)
    local fadeDuration = math.min(FADE_DURATION, duration)
    C_Timer.After(duration - fadeDuration, function()
        if thisResult ~= resultSerial or not frame:IsShown() then
            return
        end
        local elapsed = 0
        frame:SetScript("OnUpdate", function(self, delta)
            if thisResult ~= resultSerial then
                self:SetScript("OnUpdate", nil)
                return
            end
            elapsed = math.min(elapsed + delta, fadeDuration)
            self:SetAlpha(1 - elapsed / fadeDuration)
            if elapsed >= fadeDuration then
                self:SetScript("OnUpdate", nil)
                self:Hide()
            end
        end)
    end)
end

-- Kept for other QFX modules already calling the standalone ceremony API.
_G.QFXMythicCeremony_ShowResult = ShowResult

local function ReadPlayerScore()
    local summary = ns.RunSummary
    if summary and type(summary.ReadPlayerScore) == "function" then
        local ok, raw = pcall(summary.ReadPlayerScore)
        local score = ok and Util.SafeNumber(raw) or nil
        if score ~= nil then
            return score
        end
    end
    if C_ChallengeMode and type(C_ChallengeMode.GetOverallDungeonScore) == "function" then
        local ok, raw = pcall(C_ChallengeMode.GetOverallDungeonScore)
        return ok and Util.SafeNumber(raw) or nil
    end
    return nil
end

local function EstimateRank(score)
    if score == nil then
        return nil
    end
    local ok, rank = pcall(function()
        local region = type(ns.GetSelectedRegion) == "function" and ns.GetSelectedRegion() or nil
        if not region and type(ns.ResolveSelectedRegion) == "function" then
            region = ns.ResolveSelectedRegion()
        end
        local summary = ns.RunSummary
        if region and summary and type(summary.EstimateRankForScore) == "function" then
            return summary.EstimateRankForScore(region, score)
        end
    end)
    if not ok then
        DebugPrint("rank estimate unavailable: " .. tostring(rank))
        return nil
    end
    return Util.SafeNumber(rank)
end

local preRunScore
local lastCompletionIssue

local function ReadCompletionInfo()
    if not C_ChallengeMode or type(C_ChallengeMode.GetChallengeCompletionInfo) ~= "function" then
        lastCompletionIssue = "completion API unavailable"
        return nil
    end
    local ok, raw = pcall(C_ChallengeMode.GetChallengeCompletionInfo)
    if not ok then
        lastCompletionIssue = "completion API error: " .. tostring(raw)
        return nil
    end
    local info = Util.SafeTable(raw)
    if not info then
        lastCompletionIssue = "completion info inaccessible (" .. type(raw) .. ")"
        return nil
    end
    lastCompletionIssue = nil
    return info
end

-- Let Blizzard finish its completion processing (including system chat),
-- then dismiss only its banner. StopBanner cancels its timer, and notifying
-- the manager lets any other queued top banner play normally.
local bannerHooked = false
local function HideBlizzardCompletionBanner()
    local banner = _G.ChallengeModeCompleteBanner
    if bannerHooked or not banner or type(banner.PlayBanner) ~= "function"
        or type(banner.StopBanner) ~= "function" or type(hooksecurefunc) ~= "function"
        or type(TopBannerManager_BannerFinished) ~= "function" then
        return
    end
    banner:SetAlpha(0)
    if pcall(hooksecurefunc, banner, "PlayBanner", function(self)
        self:StopBanner()
        TopBannerManager_BannerFinished()
    end) then
        bannerHooked = true
    end
end

local bannerWatcher = CreateFrame("Frame")
bannerWatcher:RegisterEvent("ADDON_LOADED")
bannerWatcher:SetScript("OnEvent", function(self, _, addonName)
    if addonName == "Blizzard_ChallengesUI" then
        HideBlizzardCompletionBanner()
        if bannerHooked then self:UnregisterEvent("ADDON_LOADED") end
    end
end)
HideBlizzardCompletionBanner()
if bannerHooked then bannerWatcher:UnregisterEvent("ADDON_LOADED") end

local events = CreateFrame("Frame")
events:RegisterEvent("CHALLENGE_MODE_START")
events:RegisterEvent("CHALLENGE_MODE_COMPLETED")
events:SetScript("OnEvent", function(_, event)
    if event == "CHALLENGE_MODE_START" then
        preRunScore = ReadPlayerScore()
        DebugPrint("run start preRunScore=" .. tostring(preRunScore))
    else
        local info = ReadCompletionInfo()
        local scoreBefore = info and Util.SafeNumber(info.oldOverallDungeonScore) or preRunScore
        preRunScore = nil
        if not info then
            WarnPrint("no ceremony shown: " .. tostring(lastCompletionIssue))
            return
        end
        if Util.SafeBoolean(info.practiceRun) == true then
            DebugPrint("ceremony skipped: practice run")
            return
        end

        local scoreAfter = Util.SafeNumber(info.newOverallDungeonScore) or ReadPlayerScore()
        local scoreGain = scoreBefore and scoreAfter and math.max(0, scoreAfter - scoreBefore) or nil
        local rankAfter = EstimateRank(scoreAfter)
        local rankBefore = EstimateRank(scoreBefore)
        local rankGain = rankBefore and rankAfter and math.max(0, math.floor(rankBefore - rankAfter + 0.5)) or nil
        ShowResult(Util.SafeBoolean(info.onTime) == true, scoreAfter, scoreGain, rankAfter, rankGain, rankAfter ~= nil)
    end
end)

local function TestResult(victory, longRank)
    ShowResult(victory, 3400, 10, longRank and 3456789 or 3456, longRank and 1234567 or 128, true)
end

local testPanel = CreateFrame("Frame", ADDON_NAME .. "CeremonyTestPanel", UIParent, "BackdropTemplate")
testPanel:SetSize(250, 118)
testPanel:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
testPanel:SetFrameStrata("DIALOG")
testPanel:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
testPanel:SetBackdropColor(0.035, 0.045, 0.065, 0.95)
testPanel:SetBackdropBorderColor(0.72, 0.56, 0.24, 0.9)
testPanel:Hide()

local title = testPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -12)
title:SetText(L.CEREMONY_TEST_TITLE)

local function MakeTestButton(text, x, victory)
    local button = CreateFrame("Button", nil, testPanel, "UIPanelButtonTemplate")
    button:SetSize(100, 30)
    button:SetPoint("BOTTOM", testPanel, "BOTTOM", x, 18)
    button:SetText(text)
    button:SetScript("OnClick", function() TestResult(victory, false) end)
end

MakeTestButton(L.CEREMONY_TEST_VICTORY, -57, true)
MakeTestButton(L.CEREMONY_TEST_DEFEAT, 57, false)

SLASH_QFXVICTORY1 = "/qfxvictory"
SlashCmdList.QFXVICTORY = function() TestResult(true, false) end
SLASH_QFXDEFEAT1 = "/qfxdefeat"
SlashCmdList.QFXDEFEAT = function() TestResult(false, false) end
SLASH_QFXMYTHICCEREMONY1 = "/qfxmc"
SlashCmdList.QFXMYTHICCEREMONY = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "victory" then
        TestResult(true, false)
    elseif msg == "defeat" then
        TestResult(false, false)
    elseif msg == "longrank" then
        TestResult(true, true)
    elseif msg == "longrank defeat" then
        TestResult(false, true)
    elseif msg == "live" then
        local score = ReadPlayerScore()
        local rank = EstimateRank(score)
        ShowResult(true, score, nil, rank, nil, rank ~= nil)
    elseif msg == "test" then
        testPanel:SetShown(not testPanel:IsShown())
    elseif msg == "unlock" then
        SetUnlocked(true)
    elseif msg == "lock" then
        SetUnlocked(false)
    elseif msg == "resetpos" then
        local settings = GetSettings()
        settings.x, settings.y = GetDefaultPosition()
        ApplyPosition(settings)
        print(PREFIX .. L.CEREMONY_POSITION_RESET)
    elseif msg == "sound" then
        local settings = GetSettings()
        settings.sound = not settings.sound
        print(L.CEREMONY_SOUND .. (settings.sound and "ON" or "OFF"))
    elseif msg == "debug" then
        debugEnabled = not debugEnabled
        print(PREFIX .. "debug " .. (debugEnabled and "ON" or "OFF"))
    elseif msg == "dump" then
        local settings = GetSettings()
        print(PREFIX .. string.format(
            "enabled=%s sound=%s duration=%s score=%s region=%s",
            tostring(settings and settings.enabled),
            tostring(settings and settings.sound),
            tostring(settings and settings.duration),
            tostring(ReadPlayerScore()),
            tostring(type(ns.GetSelectedRegion) == "function" and ns.GetSelectedRegion() or nil)))
        local info = ReadCompletionInfo()
        if not info then
            print(PREFIX .. "completion info: " .. tostring(lastCompletionIssue))
        else
            print(PREFIX .. string.format(
                "completion map=%s level=%s time=%s onTime=%s practice=%s oldScore=%s newScore=%s",
                DescribeValue(info.mapChallengeModeID), DescribeValue(info.level),
                DescribeValue(info.time), DescribeValue(info.onTime),
                DescribeValue(info.practiceRun), DescribeValue(info.oldOverallDungeonScore),
                DescribeValue(info.newOverallDungeonScore)))
        end
    elseif msg == "reset" then
        local settings = GetSettings()
        local defaultX, defaultY = GetDefaultPosition()
        settings.enabled, settings.sound, settings.scale, settings.x, settings.y, settings.duration = true, true, 1, defaultX, defaultY, 10
        if unlocked then
            frame:SetScale(SIZE_FACTOR)
            ApplyPosition(settings)
        end
        print(L.CEREMONY_RESET)
    else
        local scale = msg:match("^scale%s+([%d%.]+)$")
        if scale then
            local settings = GetSettings()
            settings.scale = Util.ClampNumber(scale, 0.5, 1.5, settings.scale)
            print(string.format(L.CEREMONY_SCALE, settings.scale))
        else
            print(L.CEREMONY_HELP)
        end
    end
end

ns.Ceremony = {
    ShowResult = ShowResult,
    ReadCompletionInfo = ReadCompletionInfo,
    SetUnlocked = SetUnlocked,
    IsUnlocked = function() return unlocked end,
}
