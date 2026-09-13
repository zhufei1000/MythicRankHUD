local scripts = {}

local function Noop() end

local objectMethods = {}
function objectMethods:SetSize(width, height) self.width, self.height = width, height end
function objectMethods:SetWidth(width) self.width = width end
function objectMethods:SetHeight(height) self.height = height end
function objectMethods:SetFont(font, size, flags) self.font, self.fontSize, self.fontFlags = font, size, flags end
function objectMethods:SetFrameStrata(strata) self.frameStrata = strata end
function objectMethods:GetFrameStrata() return self.frameStrata end
function objectMethods:SetFrameLevel(level) self.frameLevel = level end
function objectMethods:GetFrameLevel() return self.frameLevel end
function objectMethods:SetToplevel(enabled) self.topLevel = enabled and true or false end
function objectMethods:EnableMouse(enabled) self.mouseEnabled = enabled ~= false end
function objectMethods:GetWidth() return self.width or 922 end
function objectMethods:GetHeight() return self.height or 447 end
function objectMethods:ClearAllPoints() self.points = {} end
function objectMethods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function objectMethods:SetScript(name, callback) self.scripts[name] = callback end
function objectMethods:HookScript(name, callback)
    local previous = self.scripts[name]
    self.scripts[name] = function(...)
        if previous then previous(...) end
        callback(...)
    end
end
function objectMethods:RegisterEvent(event) self.events[event] = true end
function objectMethods:RegisterUnitEvent(event, unit) self.events[event], self.eventUnit = true, unit end
function objectMethods:RegisterForClicks() end
function objectMethods:SetDesaturated(value) self.desaturated = value end
function objectMethods:SetVertexColor(...) self.vertexColor = { ... } end
function objectMethods:SetWordWrap(value) self.wordWrap = value end
function objectMethods:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
function objectMethods:SetValue(value) self.value = value end
function objectMethods:SetAttribute(key, value)
    self.attributes = rawget(self, "attributes") or {}
    self.attributes[key] = value
end
function objectMethods:SetBackdropColor(...) self.backdropColor = { ... } end
function objectMethods:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
function objectMethods:SetShown(shown) self.shown = shown and true or false end
function objectMethods:Show() self.shown = true end
function objectMethods:Hide() self.shown = false end
function objectMethods:IsShown() return self.shown == true end
function objectMethods:CreateTexture()
    return setmetatable({ scripts = {}, events = {}, points = {} }, { __index = function(_, key) return objectMethods[key] or Noop end })
end
function objectMethods:CreateFontString()
    local fontString = setmetatable({ scripts = {}, events = {}, points = {} }, { __index = function(_, key) return objectMethods[key] or Noop end })
    function fontString:SetText(text) self.text = text end
    function fontString:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
    function fontString:GetStringHeight()
        local lineCount = 0
        for line in (tostring(self.text or "") .. "\n"):gmatch("(.-)\n") do
            local visible = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "[]")
            lineCount = lineCount + math.max(1, math.ceil(#visible / 15))
        end
        return lineCount * 17
    end
    return fontString
end

local function NewObject(shown)
    return setmetatable({
        shown = shown == true,
        width = 922,
        height = 447,
        frameStrata = "MEDIUM",
        frameLevel = 10,
        scripts = {},
        events = {},
        points = {},
    }, {
        __index = function(_, key) return objectMethods[key] or Noop end,
    })
end

UIParent = NewObject(true)
MeetingStoneMainPanel = NewObject(true)
MeetingStoneMainPanel.__QFXMythicRankHUDIntegrationHooked = false
PVEFrame = NewObject(false)
STANDARD_TEXT_FONT = "font"
function GetLocale() return "enUS" end
function UnitName() return "Test Player" end
function UnitClass() return "Mage", "MAGE" end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
local currentTime = 100
local inGroup = true
local chatMessages = {}
function GetTime() return currentTime end
function IsInGroup() return inGroup end
function SendChatMessage(message, channel)
    chatMessages[#chatMessages + 1] = { message = message, channel = channel }
end
function SetPortraitTexture(texture, unit) texture.unit = unit end
local vaultOpened = false
function WeeklyRewards_ShowUI() vaultOpened = true end
function CreateFrame()
    local frame = NewObject(true)
    scripts[#scripts + 1] = frame
    return frame
end

GameTooltip = setmetatable({}, { __index = function() return Noop end })
GameTooltip_Hide = Noop
C_Timer = { After = function(_, callback) callback() end }
Enum = { SpellBookSpellBank = { Player = 1 } }
C_SpellBook = { IsSpellKnown = function() return false end }

local enabledAddons = { MeetingStone = true }
C_AddOns = {
    GetAddOnEnableState = function(name) return enabledAddons[name] and 2 or 0 end,
}

C_ChallengeMode = {
    GetMapTable = function() return { 249, 250, 399, 584, 585, 586, 587, 588 } end,
    GetMapUIInfo = function(mapID) return "Localized Dungeon " .. mapID, nil, 1800, 100000 + mapID end,
    GetMapScoreInfo = function()
        mapScoreRefreshCount = (mapScoreRefreshCount or 0) + 1
        local result = {}
        for _, mapID in ipairs(C_ChallengeMode.GetMapTable()) do
            result[#result + 1] = { mapChallengeModeID = mapID, level = 12, dungeonScore = 375 }
        end
        return result
    end,
    GetKeystoneLevelRarityColor = function() return { r = 0.7, g = 0.2, b = 1 } end,
    GetSpecificDungeonOverallScoreRarityColor = function() return { r = 1, g = 0.5, b = 0 } end,
}

local nonEnglishDataName = string.char(230, 181, 139, 232, 175, 149)
QFXMythicRankData = {
    GetSeasonDungeons = function()
        return {
            { challengeModeID = 249, name = nonEnglishDataName, shortName = nonEnglishDataName },
            { challengeModeID = 250, name = "Temple of Sethraliss", shortName = "TOS" },
            { challengeModeID = 399, name = "Ruby Life Pools", shortName = "RLP" },
            { challengeModeID = 584, name = "The Blinding Vale", shortName = "BV" },
            { challengeModeID = 585, name = "Voidscar Arena", shortName = "VSA" },
            { challengeModeID = 586, name = "Den of Nalorakk", shortName = "DON" },
            { challengeModeID = 587, name = "Murder Row", shortName = "MR" },
            { challengeModeID = 588, name = "Altar of Fangs", shortName = "AOF" },
        }
    end,
}

C_PlayerInfo = { GetPlayerMythicPlusRatingSummary = function() return { runs = {} } end }
C_MythicPlus = {
    RequestMapInfo = Noop,
    GetRunHistory = function()
        runHistoryRefreshCount = (runHistoryRefreshCount or 0) + 1
        return {
            { mapChallengeModeID = 249, level = 13, durationSec = 1700, completed = true },
            { mapChallengeModeID = 249, level = 12, durationSec = 1600, completed = true },
            { mapChallengeModeID = 249, level = 11, durationSec = 1500, completed = true },
            { mapChallengeModeID = 249, level = 10, durationSec = 1400, completed = true },
            { mapChallengeModeID = 249, level = 9, durationSec = 1300, completed = true },
            { mapChallengeModeID = 249, level = 8, durationSec = 1900, completed = true },
            { mapChallengeModeID = 249, level = 7, durationSec = 2000, completed = true },
        }
    end,
}

local toggled = false
local teleportAnnouncementEnabled = true
local showExtraRows = true
local dataPackLoaded = true
local selectedRegion = "cn"
local loadedRegions = { cn = true }
local hudVisual = {
    borderR = 1,
    borderG = 0.82,
    borderB = 0,
    borderAlpha = 0.9,
    backgroundAlpha = 0.9,
}
local namespace = {
    Util = { SafeNumber = tonumber },
    L = {
        ADDON_TITLE = "MythicRankHUD",
        VAULT_RAID = "Raid",
        VAULT_MYTHIC_PLUS = "Mythic+",
        VAULT_WORLD = "World",
        TELEPORT_ANNOUNCEMENT_FORMAT = "Teleported to dungeon: {dungeon}----<QFX>",
    },
    GetHUDVisualSettings = function()
        return hudVisual
    end,
    IsTeleportAnnouncementEnabled = function()
        return teleportAnnouncementEnabled
    end,
    GetHUDSnapshot = function()
        profileRefreshCount = (profileRefreshCount or 0) + 1
        return {
            score = { label = "Score", value = "3000.0", r = 1, g = 0.5, b = 0 },
            dataUpdated = { label = "", value = "Updated: today", r = 1, g = 0.82, b = 0 },
            cutoff01 = { label = "Top 0.1%", value = "3500", r = 1, g = 0, b = 1 },
            cutoff1 = { label = "Top 1%", value = "3300", r = 0, g = 0.4, b = 1 },
            rank = { label = "Regional rank", value = "1000", r = 1, g = 0.82, b = 0 },
            rankRange = { label = "Rank range", value = "900-1100", r = 1, g = 1, b = 1 },
            percentileRange = { label = "Percentile range", value = "0.2%-0.3%", r = 1, g = 1, b = 1 },
        }, {
            dataUpdated = true,
            cutoff01 = true,
            cutoff1 = true,
            rank = true,
            rankRange = showExtraRows,
            percentileRange = showExtraRows,
        }
    end,
    OpenMythicDetail = function() toggled = true end,
    GetSelectedRegion = function() return selectedRegion end,
    IsRegionLoaded = function(region) return dataPackLoaded and loadedRegions[region] == true end,
    GetFallbackEnglishDungeonInfo = function(mapID)
        if tonumber(mapID) == 249 then return "Kings' Rest", "KR" end
    end,
    MythicDetailResources = {
        RESOURCE_ORDER = { "mythic", "heroic", "champion", "veteran", "adventurer", "voidCore", "manaflux" },
        GetAll = function(result, quantityOverrides)
            resourceRefreshCount = (resourceRefreshCount or 0) + 1
            result = result or {}
            local keys = { "mythic", "heroic", "champion", "veteran", "adventurer", "voidCore", "manaflux" }
            for index = 1, 7 do
                result[index] = {
                    key = keys[index],
                    id = 3400 + index,
                    name = "Resource " .. index,
                    icon = 200000 + index,
                    quantity = index * 10,
                    discovered = true,
                }
                if quantityOverrides and quantityOverrides[result[index].id] ~= nil then
                    result[index].quantity = quantityOverrides[result[index].id]
                end
            end
            return result
        end,
        ShowTooltip = Noop,
    },
    MythicDetailData = {
        RefreshVault = function()
            vaultRefreshCount = (vaultRefreshCount or 0) + 1
            return {
                categories = {
                    raid = { available = true, progress = 6, maximum = 6 },
                    mythicPlus = { available = true, progress = 4, maximum = 8 },
                    world = { available = true, progress = 8, maximum = 8 },
                },
            }
        end,
    },
}

local modulePath = arg and arg[1] or "MeetingStoneIntegration.lua"
local addonName = arg and arg[2] or "MythicRankHUD"
local isCNBuild = addonName == "QFXMythicRankHUD"
local chunk = assert(loadfile(modulePath))
chunk(addonName, namespace)

local eventFrame
for _, frame in ipairs(scripts) do
    if frame.events.ADDON_LOADED then eventFrame = frame end
end
assert(eventFrame, "event frame was not created")
eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", addonName)

local integration = assert(namespace.MeetingStoneIntegration)
assert(integration.mainPanel == MeetingStoneMainPanel, "MeetingStone main panel was not attached")
assert(integration.seasonBar and integration.seasonBar:IsShown(), "season bar is not visible")
assert(integration.seasonBar.frameStrata == MeetingStoneMainPanel.frameStrata,
    "teleport bar did not follow the host frame strata")
assert(integration.seasonBar.frameLevel == MeetingStoneMainPanel.frameLevel + 5,
    "teleport bar did not follow the host frame level")
assert(integration.seasonBar.topLevel == true and integration.seasonBar.mouseEnabled == true,
    "teleport bar is not configured to move to the front on mouse interaction")
assert(integration.cards[1].topLevel == true,
    "teleport button is not configured to move to the front when clicked")
assert(integration.sidePanel and integration.sidePanel:IsShown(), "left side panel is not visible")
assert(integration.visibleCardCount == 8, "season card count is incorrect")
assert(integration.hostKey == "meetingStoneHappy" or integration.hostKey == "meetingStone",
    "MeetingStone adapter was not selected")
assert(integration.seasonBar.width == 680, "season bar is not using the centered compact width")
assert(rawget(integration.seasonBar, "title") == nil, "obsolete Season Best title is still present")
assert(integration.visibleResourceCount == 7, "season resources were not mirrored into the header row")
assert(integration.seasonBar.resourceItems[1].value.text == "10", "season resource quantity was not rendered")
assert(integration.seasonBar.resourceItems[5].resource.key == "adventurer", "the five crests are not first")
assert(integration.seasonBar.resourceItems[6].resource.key == "voidCore", "void core is not after the five crests")
assert(integration.seasonBar.resourceItems[7].resource.key == "manaflux", "manaflux is not last")
assert(integration.updateNotice:IsShown(), "database update notice was not shown")
assert(integration.updateNotice.width == integration.sidePanel.width, "database notice width does not match the side panel")
assert(integration.updateNotice.height == integration.seasonBar.height, "database notice height does not match the season bar")
local expectedNotice = "Database plugins update daily at 04:04 and 16:16 in each region's local time. Keep them current."
assert(integration.updateNotice.body.text == expectedNotice,
    "database update notice text is incorrect")
integration.updateNotice.closeButton.scripts.OnClick(integration.updateNotice.closeButton)
assert(not integration.updateNotice:IsShown(), "database update notice did not close")
assert(integration.updateNoticeDismissed == true, "database update notice dismissal was not kept for the session")
assert(integration.sidePanel.profileButton.score.text == "3000.0", "score was not copied into profile header")
assert(integration.sidePanel.profileButton.score.fontSize == 18, "profile score font was not reduced")
assert(integration.sidePanel.profileButton.playerName.fontSize == 16, "player name font was not enlarged to 16")
assert(integration.sidePanel.profileButton.scoreLabel.fontSize == 12, "score label font did not return to its original size")
assert(integration.summaryRows.cutoff01.label.fontSize == 12 and integration.summaryRows.cutoff01.value.fontSize == 12,
    "ranking summary fonts were not enlarged")
assert(integration.sidePanel.vaultRows[1].label.fontSize == 12 and integration.sidePanel.vaultRows[1].value.fontSize == 12,
    "vault progress fonts did not return to their original size")
assert(integration.sidePanel.weeklyDetailsTitle.label.fontSize == 12,
    "weekly details title font did not return to its original size")
assert(integration.sidePanel.lowerDisplay.fontSize == 13,
    "weekly details font did not return to its original size")
local playerNameColor = integration.sidePanel.profileButton.playerName.color
assert(playerNameColor and playerNameColor[1] == 0.25 and playerNameColor[2] == 0.78 and playerNameColor[3] == 0.92,
    "player name did not use the player's class color")
assert(integration.summaryRows.dataUpdated.height == 17, "update timestamp row height is incorrect")
assert(integration.summaryRows.dataUpdated.value.wordWrap == false, "update timestamp still wraps onto two lines")
assert(integration.sidePanel.vaultRows[1].bar.minimum == 0 and integration.sidePanel.vaultRows[1].bar.maximum == 6,
    "raid vault bar did not use the six-boss maximum")
assert(integration.sidePanel.vaultRows[1].value.text == "6/6", "raid vault progress was not rendered as complete at six")
assert(integration.sidePanel.vaultRows[2].value.text == "4/8", "Mythic+ vault progress was not rendered")
local expectedWeeklyTitle = "Weekly Mythic+ Details (Total 7, Timed |cff00ff005|r, OT |cffff44442|r)"
assert(integration.sidePanel.weeklyDetailsTitle.label.text == expectedWeeklyTitle,
    "weekly run totals were not added to the section title")
assert(integration.sidePanel.lowerDisplay.wordWrap == true, "weekly dungeon summary does not enable wrapping")
assert(integration.sidePanel.weeklyContentHeight > (8 * 17), "wrapped weekly details did not increase the panel content height")
if isCNBuild then
    for index = 1, 8 do
        local label = integration.cards[index].name.text
        assert(type(label) == "string" and label ~= "", "CN season card abbreviation is empty")
        assert(integration.sidePanel.lowerDisplay.text:find(label, 1, true),
            "CN weekly record did not reuse its season card abbreviation")
    end
else
    local expectedMapLabels = { "KR", "TOS", "RLP", "BV", "VSA", "DON", "MR", "AOF" }
    for index, label in ipairs(expectedMapLabels) do
        assert(integration.cards[index].name.text == label,
            "season card " .. index .. " did not use abbreviation " .. label)
        assert(integration.sidePanel.lowerDisplay.text:find(label, 1, true),
            "weekly record did not use abbreviation " .. label)
    end
    assert(not integration.cards[1].name.text:find("Localized Dungeon", 1, true),
        "international season card used a localized fallback name")
    assert(not integration.sidePanel.lowerDisplay.text:find("Localized Dungeon", 1, true),
        "international weekly record used localized fallback names")
    assert(integration.cards[1].mapName == "Kings' Rest", "international tooltip name was not English")
end
assert(integration.cards[1].background.desaturated == false, "dungeon artwork is still desaturated")
assert(integration.cards[1].background.vertexColor[1] == 1, "dungeon artwork is still tinted gray")
assert(integration.cards[1].attributes.type1 == "spell", "dungeon card is not a secure spell action")
assert(integration.cards[1].attributes.useOnKeyDown == false, "secure action is not configured for button-up")
assert(integration.cards[1].attributes.spell1 == 1286831, "numbered spell attribute is missing")
assert(integration.cards[1].attributes.spell == 1286831, "dungeon card has the wrong teleport spell")

assert(eventFrame.events.UNIT_SPELLCAST_SENT and eventFrame.events.UNIT_SPELLCAST_SUCCEEDED,
    "player spellcast events were not registered")
eventFrame.scripts.OnEvent(eventFrame, "UNIT_SPELLCAST_SENT", "player", nil, "Cast-1", 1286831)
currentTime = 110
eventFrame.scripts.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 1286831)
assert(#chatMessages == 1, "successful dungeon teleport was not announced")
assert(chatMessages[1].channel == "PARTY", "teleport announcement used the wrong chat channel")
local expectedAnnouncementDestination = isCNBuild and "Localized Dungeon 249" or "Kings' Rest"
assert(chatMessages[1].message == "Teleported to dungeon: " .. expectedAnnouncementDestination .. "----<QFX>",
    "teleport announcement used the wrong destination")
eventFrame.scripts.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 1286831)
assert(#chatMessages == 1, "duplicate teleport success produced another announcement")

currentTime = 120
integration.cards[1].scripts.PreClick(integration.cards[1], "LeftButton")
eventFrame.scripts.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 1286831)
assert(#chatMessages == 2, "teleport button fallback did not announce without a SENT event")

teleportAnnouncementEnabled = false
currentTime = 130
eventFrame.scripts.OnEvent(eventFrame, "UNIT_SPELLCAST_SENT", "player", nil, "Cast-3", 1286831)
eventFrame.scripts.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 1286831)
assert(#chatMessages == 2, "disabled teleport announcement still sent a message")
teleportAnnouncementEnabled = true

local initialProfileRefreshes = profileRefreshCount
local initialResourceRefreshes = resourceRefreshCount
local initialRunHistoryRefreshes = runHistoryRefreshCount
local initialVaultRefreshes = vaultRefreshCount
local initialMapScoreRefreshes = mapScoreRefreshCount
eventFrame.scripts.OnEvent(eventFrame, "CURRENCY_DISPLAY_UPDATE", 3406, 3, -57)
assert(resourceRefreshCount == initialResourceRefreshes + 1, "currency event did not refresh season resources")
assert(integration.seasonBar.resourceItems[6].value.text == "3",
    "currency event quantity did not override a stale resource query")
assert(profileRefreshCount == initialProfileRefreshes, "currency event triggered a ranking refresh")
assert(runHistoryRefreshCount == initialRunHistoryRefreshes, "currency event triggered a weekly history refresh")
assert(vaultRefreshCount == initialVaultRefreshes, "currency event triggered a vault refresh")
assert(mapScoreRefreshCount == initialMapScoreRefreshes, "currency event triggered a season score refresh")

eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
-- Combat exit must apply deferred visibility and secure bindings without
-- re-querying unrelated ranking, resource, weekly, vault, or score data.
assert(profileRefreshCount == initialProfileRefreshes, "combat exit refreshed rankings")
assert(resourceRefreshCount == initialResourceRefreshes + 1, "combat exit refreshed resources")
assert(runHistoryRefreshCount == initialRunHistoryRefreshes, "combat exit refreshed weekly details")
assert(vaultRefreshCount == initialVaultRefreshes, "combat exit refreshed vault progress")
assert(mapScoreRefreshCount == initialMapScoreRefreshes, "combat exit refreshed season scores")
initialProfileRefreshes = profileRefreshCount
initialResourceRefreshes = resourceRefreshCount
initialRunHistoryRefreshes = runHistoryRefreshCount
initialVaultRefreshes = vaultRefreshCount
initialMapScoreRefreshes = mapScoreRefreshCount

eventFrame.scripts.OnEvent(eventFrame, "WEEKLY_REWARDS_UPDATE")
assert(profileRefreshCount == initialProfileRefreshes, "vault event triggered a ranking refresh")
assert(resourceRefreshCount == initialResourceRefreshes, "vault event triggered a resource refresh")
assert(runHistoryRefreshCount == initialRunHistoryRefreshes + 1, "vault event did not refresh weekly details")
assert(vaultRefreshCount == initialVaultRefreshes + 1, "vault event did not refresh vault progress")

initialProfileRefreshes = profileRefreshCount
initialResourceRefreshes = resourceRefreshCount
initialRunHistoryRefreshes = runHistoryRefreshCount
initialVaultRefreshes = vaultRefreshCount
initialMapScoreRefreshes = mapScoreRefreshCount
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_LEADERS_UPDATE")
assert(mapScoreRefreshCount == initialMapScoreRefreshes + 1, "leader event did not refresh season scores")
assert(resourceRefreshCount == initialResourceRefreshes, "leader event refreshed unrelated resources")
assert(profileRefreshCount == initialProfileRefreshes, "leader event refreshed unrelated rankings")
assert(runHistoryRefreshCount == initialRunHistoryRefreshes, "leader event refreshed unrelated weekly details")
assert(vaultRefreshCount == initialVaultRefreshes, "leader event refreshed unrelated vault progress")

MeetingStoneMainPanel.scripts.OnSizeChanged(MeetingStoneMainPanel)
assert(profileRefreshCount == initialProfileRefreshes, "host resize triggered a ranking refresh")
assert(runHistoryRefreshCount == initialRunHistoryRefreshes, "host resize triggered a weekly history refresh")

local expandedHeight = integration.sidePanel.height
showExtraRows = false
namespace.RefreshMeetingStoneIntegration()
assert(integration.sidePanel.height == expandedHeight - 34, "side panel did not shrink with two hidden rows")

integration.sidePanel.vaultButton.scripts.OnClick(integration.sidePanel.vaultButton, "LeftButton")
assert(vaultOpened, "vault progress click did not open the Great Vault")

integration.sidePanel.profileButton.scripts.OnClick(integration.sidePanel.profileButton, "LeftButton")
assert(toggled, "profile click did not open Mythic+ details")

dataPackLoaded = false
namespace.RefreshMeetingStoneIntegration()
assert(not integration.sidePanel.profileButton:IsShown(), "profile content remained visible without the ranking database")
assert(integration.sidePanel.dataPackNotice:IsShown(), "ranking database requirement was not shown")
assert(integration.sidePanel.dataPackNotice.text:find("QFXMythicRankData_CN", 1, true),
    "ranking database notice did not identify the required CN plugin")
for _, row in pairs(integration.summaryRows) do
    assert(not row:IsShown(), "ranking summary row remained visible without the database")
end
dataPackLoaded = true
namespace.RefreshMeetingStoneIntegration()
assert(integration.sidePanel.profileButton:IsShown(), "profile content did not return after the database became available")
assert(not integration.sidePanel.dataPackNotice:IsShown(), "database requirement remained visible after recovery")

selectedRegion = "eu"
loadedRegions.eu = false
namespace.RefreshMeetingStoneIntegration("profile")
assert(integration.sidePanel.dataPackNotice.text:find("QFXMythicRankData_EU", 1, true),
    "selected non-CN region did not request its own data pack")
loadedRegions.eu = true
selectedRegion = "cn"

hudVisual.backgroundAlpha = 0.42
hudVisual.borderAlpha = 0.37
namespace.RefreshMeetingStoneIntegration("style")
assert(integration.seasonBar.backdropColor[4] == 0.42, "HUD background opacity was ignored")
assert(integration.seasonBar.backdropBorderColor[4] == 0.37, "HUD border opacity was ignored")

MeetingStoneMainPanel.shown = false
MeetingStoneMainPanel.scripts.OnHide(MeetingStoneMainPanel)
assert(not integration.seasonBar:IsShown(), "season bar stayed visible after MeetingStone closed")
assert(not integration.sidePanel:IsShown(), "side panel stayed visible after MeetingStone closed")

GroupFinderAddonFrame = NewObject(true)
enabledAddons.GroupFinder = true
eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", "GroupFinder")
assert(integration.mainPanel == GroupFinderAddonFrame, "GroupFinder main frame was not selected")
assert(integration.hostKey == "groupFinder", "GroupFinder adapter key is incorrect")

GroupFinderAddonFrame.shown = false
GroupFinderAddonFrame.scripts.OnHide(GroupFinderAddonFrame)
PremadeGroupBoardFrame = NewObject(true)
enabledAddons.PremadeGroupBoard = true
eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", "PremadeGroupBoard")
assert(integration.mainPanel == PremadeGroupBoardFrame, "Premade Group Board main frame was not selected")
assert(integration.hostKey == "premadeGroupBoard", "Premade Group Board adapter key is incorrect")

PremadeGroupBoardFrame.shown = false
PremadeGroupBoardFrame.scripts.OnHide(PremadeGroupBoardFrame)
MeetingStoneHappyFrame = NewObject(true)
enabledAddons.MeetingStone_Happy = true
eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", "MeetingStone_Happy")
assert(integration.mainPanel == MeetingStoneHappyFrame, "MeetingStone_Happy frame was not selected")
assert(integration.hostKey == "meetingStoneHappy", "MeetingStone_Happy adapter key is incorrect")

MeetingStoneHappyFrame.shown = false
MeetingStoneHappyFrame.scripts.OnHide(MeetingStoneHappyFrame)
for name in pairs(enabledAddons) do enabledAddons[name] = false end
PVEFrame.shown = true
eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", "Blizzard_GroupFinder")
PVEFrame.scripts.OnShow(PVEFrame)
assert(integration.mainPanel == PVEFrame, "Blizzard PVEFrame fallback was not selected")
assert(integration.hostKey == "blizzard", "Blizzard fallback adapter key is incorrect")
assert(integration.seasonBar:IsShown(), "season bar is not visible on Blizzard fallback")
assert(integration.sidePanel:IsShown(), "side panel is not visible on Blizzard fallback")

-- Regression: frame discovery is single-flight and bounded. Once the short
-- load window expires, normal events still discover a late-created frame.
do
    local queue = {}
    local syncAfter = C_Timer.After
    C_Timer.After = function(_, callback) queue[#queue + 1] = callback end
    local function pump()
        local callbacks = queue
        queue = {}
        for _, callback in ipairs(callbacks) do callback() end
    end

    for name in pairs(enabledAddons) do enabledAddons[name] = false end
    PVEFrame.shown = false
    PremadeGroupBoardFrame = nil
    enabledAddons.PremadeGroupBoard = true
    eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", "PremadeGroupBoard")
    eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", "PremadeGroupBoard")
    assert(#queue == 1, "duplicate attach watcher chains were scheduled")

    -- The short login window expires with no permanent polling timer left.
    for _ = 1, 31 do pump() end
    assert(not integration.seasonBar:IsShown(), "season bar shown without a visible host")
    assert(integration.attachAttempts == 30, "attach watcher did not stop at its bound")
    assert(integration.attachCheckScheduled == false, "attach watcher remained scheduled")
    assert(#queue == 0, "attach watcher left a permanent timer behind")

    -- The player opens PGB later; the next normal event discovers it.
    PremadeGroupBoardFrame = NewObject(true)
    eventFrame.scripts.OnEvent(eventFrame, "CURRENCY_DISPLAY_UPDATE", 3446)
    pump()
    assert(integration.mainPanel == PremadeGroupBoardFrame,
        "event-triggered discovery did not attach to the late PGB frame")
    assert(integration.hostKey == "premadeGroupBoard", "late PGB adapter key is incorrect")
    assert(integration.seasonBar:IsShown(), "season bar did not follow the late PGB frame")

    -- closing PGB must still hide the followers
    PremadeGroupBoardFrame.shown = false
    PremadeGroupBoardFrame.scripts.OnHide(PremadeGroupBoardFrame)
    pump()
    assert(not integration.seasonBar:IsShown(), "season bar stayed visible after late PGB closed")

    C_Timer.After = syncAfter
    enabledAddons.PremadeGroupBoard = false
end

-- Regression: the native group finder must stay a supported host even while a
-- custom group addon is installed. Opening PVEFrame by any path has to move
-- the HUD onto it, and closing it hands the HUD back to the open custom
-- window. Before this was fixed, the Blizzard adapter was disabled whenever
-- any supported group addon was enabled, so PVEFrame was never hooked.
do
    enabledAddons.MeetingStone = true
    MeetingStoneMainPanel.shown = true
    MeetingStoneMainPanel.scripts.OnShow(MeetingStoneMainPanel)
    assert(integration.mainPanel == MeetingStoneMainPanel, "MeetingStone window did not regain the HUD")
    assert(integration.seasonBar:IsShown(), "season bar is not visible on the MeetingStone window")

    -- simulate the native group finder window appearing (load-on-demand) and
    -- being opened while MeetingStone stays installed and visible
    PVEFrame = NewObject(false)
    eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", "Blizzard_GroupFinder")
    assert(PVEFrame.scripts.OnShow, "native group finder was not hooked while a group addon is installed")
    PVEFrame.shown = true
    PVEFrame.scripts.OnShow(PVEFrame)
    assert(integration.mainPanel == PVEFrame, "native group finder was ignored while a group addon is installed")
    assert(integration.hostKey == "blizzard", "native adapter key is incorrect")
    assert(integration.seasonBar:IsShown(), "season bar is not visible on the native window with a group addon installed")
    assert(integration.sidePanel:IsShown(), "side panel is not visible on the native window with a group addon installed")

    PVEFrame.shown = false
    PVEFrame.scripts.OnHide(PVEFrame)
    assert(integration.mainPanel == MeetingStoneMainPanel, "HUD did not return to the open MeetingStone window")
    assert(integration.seasonBar:IsShown(), "season bar did not follow the MeetingStone window back")

    enabledAddons.MeetingStone = false
    MeetingStoneMainPanel.shown = false
end

-- Regression: the overlays get anchored to protected hosts such as PVEFrame,
-- which makes them protected too, so the client blocks Show/Hide during combat
-- (ADDON_ACTION_BLOCKED). Combat refreshes must defer the mutations and
-- PLAYER_REGEN_ENABLED must apply them.
do
    local inCombat = false
    InCombatLockdown = function() return inCombat end

    enabledAddons.MeetingStone = true
    MeetingStoneMainPanel.shown = true
    MeetingStoneMainPanel.scripts.OnShow(MeetingStoneMainPanel)
    assert(integration.seasonBar:IsShown(), "season bar did not return with MeetingStone")

    MeetingStoneMainPanel.shown = false
    inCombat = true
    eventFrame.scripts.OnEvent(eventFrame, "CURRENCY_DISPLAY_UPDATE", 3446)
    assert(integration.seasonBar:IsShown(), "combat refresh performed a protected hide")
    assert(integration.pendingVisibility == true, "combat deferral was not recorded")

    inCombat = false
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
    assert(not integration.seasonBar:IsShown(), "deferred hide was not applied after combat")
    assert(not integration.sidePanel:IsShown(), "side panel stayed visible after the deferred hide")
    assert(integration.pendingVisibility == nil, "pending visibility flag was not cleared")

    MeetingStoneMainPanel.shown = true
    MeetingStoneMainPanel.scripts.OnShow(MeetingStoneMainPanel)
    assert(integration.seasonBar:IsShown(), "season bar did not return once combat ended")
    assert(integration.sidePanel:IsShown(), "side panel did not return once combat ended")
end

-- While every group window is closed, event refreshes must not touch overlay
-- visibility at all: a redundant SetShown(false) is still a protected call on
-- a protected overlay and is what produced the ADDON_ACTION_BLOCKED spam.
do
    local setShownCalls = 0
    local seasonBar = integration.seasonBar
    local originalSetShown = seasonBar.SetShown
    seasonBar.SetShown = function(self, value)
        setShownCalls = setShownCalls + 1
        originalSetShown(self, value)
    end

    MeetingStoneMainPanel.shown = false
    MeetingStoneMainPanel.scripts.OnHide(MeetingStoneMainPanel)
    local baseline = setShownCalls
    eventFrame.scripts.OnEvent(eventFrame, "CURRENCY_DISPLAY_UPDATE", 3446)
    assert(setShownCalls == baseline, "closed-state refresh still touched overlay visibility")
    assert(not integration.seasonBar:IsShown(), "season bar came back while closed")

    MeetingStoneMainPanel.shown = true
    MeetingStoneMainPanel.scripts.OnShow(MeetingStoneMainPanel)
    assert(setShownCalls == baseline + 1, "opening a host did not apply the visibility change")
    assert(integration.seasonBar:IsShown(), "season bar did not show after reopening")

    enabledAddons.MeetingStone = false
    MeetingStoneMainPanel.shown = false
    seasonBar.SetShown = originalSetShown
end

print("MeetingStoneIntegration_test: OK")
