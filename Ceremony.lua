local ADDON_NAME, ns = ...
local L = ns.L
local Util = ns.Util
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Ceremony\\"

local SIZE_FACTOR = 0.72
local DOWN_OFFSET = 20
local FADE_DURATION = 2
local ROW_GAP = 12
local DELTA_GAP = 7

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
frame:SetFrameStrata("HIGH")
frame:SetFrameLevel(120)
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

local function ApplyPosition(settings)
    local scale = Util.ClampNumber(settings.scale, 0.5, 1.5, 1) * SIZE_FACTOR
    local fromTop = math.max(UIParent:GetHeight() * 0.25, frame:GetHeight() * scale * 0.5 + 12) + DOWN_OFFSET
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "TOP", 0, -fromTop + Util.ClampNumber(settings.y, -1000, 1000, 0))
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
        PlaySoundFile(MEDIA .. (victory and "Victory.ogg" or "Defeat.ogg"), "Master")
    end

    resultSerial = resultSerial + 1
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
        local score = summary.ReadPlayerScore()
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
    local region = type(ns.GetSelectedRegion) == "function" and ns.GetSelectedRegion() or nil
    if not region and type(ns.ResolveSelectedRegion) == "function" then
        region = ns.ResolveSelectedRegion()
    end
    local summary = ns.RunSummary
    if not region or not summary or type(summary.EstimateRankForScore) ~= "function" then
        return nil
    end
    return Util.SafeNumber(summary.EstimateRankForScore(region, score))
end

local preRunScore
local activeMapID
local completionSerial = 0
local lastCompletionKey
local lastCompletionAt = 0

local function ReadCompletionInfo()
    if not C_ChallengeMode or type(C_ChallengeMode.GetChallengeCompletionInfo) ~= "function" then
        return nil
    end
    local ok, raw = pcall(C_ChallengeMode.GetChallengeCompletionInfo)
    local info = ok and Util.SafeTable(raw) or nil
    local mapID = info and Util.SafeNumber(info.mapChallengeModeID) or nil
    if not mapID or mapID <= 0 then
        return nil
    end
    return info
end

local function ProcessCompletion(serial, scoreBefore, expectedMapID, infoAttempts, scoreAttempts)
    if serial ~= completionSerial then
        return
    end
    local info = ReadCompletionInfo()
    local oldFromInfo = info and Util.SafeNumber(info.oldOverallDungeonScore) or nil
    if not info
        or (expectedMapID and info.mapChallengeModeID ~= expectedMapID)
        or (scoreBefore and oldFromInfo and math.abs(scoreBefore - oldFromInfo) > 0.2)
    then
        if infoAttempts < 8 then
            C_Timer.After(0.25, function()
                ProcessCompletion(serial, scoreBefore, expectedMapID, infoAttempts + 1, scoreAttempts)
            end)
        end
        return
    end
    if Util.SafeBoolean(info.practiceRun) == true then
        return
    end

    local scoreAfter = Util.SafeNumber(info.newOverallDungeonScore)
    scoreBefore = oldFromInfo or scoreBefore
    if scoreAfter == nil then
        local current = ReadPlayerScore()
        if current ~= nil and (scoreBefore == nil or current > scoreBefore + 0.05 or scoreAttempts >= 8) then
            scoreAfter = current
        elseif scoreAttempts < 8 then
            C_Timer.After(1, function()
                ProcessCompletion(serial, scoreBefore, expectedMapID, infoAttempts, scoreAttempts + 1)
            end)
            return
        end
    end

    local key = table.concat({
        tostring(info.mapChallengeModeID),
        tostring(Util.SafeNumber(info.level) or 0),
        tostring(Util.SafeNumber(info.time) or 0),
    }, ":")
    local now = type(GetTime) == "function" and GetTime() or 0
    if key == lastCompletionKey and now - lastCompletionAt < 8 then
        return
    end
    lastCompletionKey = key
    lastCompletionAt = now

    local scoreGain = scoreBefore and scoreAfter and math.max(0, scoreAfter - scoreBefore) or nil
    local rankAfter = EstimateRank(scoreAfter)
    local rankBefore = EstimateRank(scoreBefore)
    local rankGain = rankBefore and rankAfter and math.max(0, math.floor(rankBefore - rankAfter + 0.5)) or nil
    ShowResult(Util.SafeBoolean(info.onTime) == true, scoreAfter, scoreGain, rankAfter, rankGain, rankAfter ~= nil)
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHALLENGE_MODE_START")
events:RegisterEvent("CHALLENGE_MODE_COMPLETED")
events:SetScript("OnEvent", function(_, event, mapID)
    if event == "CHALLENGE_MODE_START" then
        completionSerial = completionSerial + 1
        activeMapID = Util.SafeNumber(mapID)
        preRunScore = ReadPlayerScore()
    else
        completionSerial = completionSerial + 1
        local serial = completionSerial
        local scoreBefore = preRunScore
        local expectedMapID = activeMapID
        preRunScore = nil
        activeMapID = nil
        C_Timer.After(0.1, function()
            ProcessCompletion(serial, scoreBefore, expectedMapID, 1, 0)
        end)
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
    elseif msg == "sound" then
        local settings = GetSettings()
        settings.sound = not settings.sound
        print(L.CEREMONY_SOUND .. (settings.sound and "ON" or "OFF"))
    elseif msg == "reset" then
        local settings = GetSettings()
        settings.enabled, settings.sound, settings.scale, settings.y, settings.duration = true, true, 1, 0, 10
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
}
