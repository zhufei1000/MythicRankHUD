local ADDON_NAME, ns = ...

local Util = ns.Util
local L = ns.L or {}
local integration = {
    cards = {},
    summaryRows = {},
    hookedFrames = setmetatable({}, { __mode = "k" }),
    attachAttempts = 0,
    refreshQueued = false,
    lastPlayerCastSentAt = 0,
    lastTeleportAnnouncementAt = 0,
}
ns.MeetingStoneIntegration = integration

local IS_CN_BUILD = ADDON_NAME == "QFXMythicRankHUD"
local IS_ZH_CN = IS_CN_BUILD and type(GetLocale) == "function" and GetLocale() == "zhCN"
local TEXT = IS_ZH_CN and {
    combinedTitle = "国服大秘境信息",
    score = "大秘境分数",
    weeklyVault = "周常宝库进度",
    weeklyDetails = "本周大米详情",
    weeklyDetailsStats = "%s（共%d，限|cff00ff00%d|r，超|cffff4444%d|r）",
    noScore = "暂无分数",
    clickDetails = "点击打开大秘境详情",
    clickTeleport = "点击传送到该副本",
    teleportLocked = "尚未解锁该副本传送",
    teleportCombat = "战斗中无法更改传送链接",
    clickVault = "点击打开周常宝库",
    rightClickSettings = "右键打开插件设置",
    dataPackMissing = "缺少国服排名数据库",
    dataPackInstall = "请安装并启用：%s",
    dataPackPurpose = "分数、排名与分数线由该插件提供",
    updateNoticeTitle = "数据库说明",
    updateNoticeBody = "数据库插件按各区当地时间每天 04:04、16:16 更新，请保持数据库的新鲜",
} or {
    combinedTitle = "Mythic+ Info",
    score = "Mythic+ Score",
    weeklyVault = "Great Vault Progress",
    weeklyDetails = "Weekly Mythic+ Details",
    weeklyDetailsStats = "%s (Total %d, Timed |cff00ff00%d|r, OT |cffff4444%d|r)",
    noScore = "No score",
    clickDetails = "Click to open Mythic+ details",
    clickTeleport = "Click to teleport to this dungeon",
    teleportLocked = "Dungeon teleport not unlocked",
    teleportCombat = "Teleport link cannot update in combat",
    clickVault = "Click to open the Great Vault",
    rightClickSettings = "Right-click to open settings",
    dataPackMissing = "Regional ranking database missing",
    dataPackInstall = "Install and enable: %s",
    dataPackPurpose = "This plugin provides scores, ranks, and cutoffs",
    updateNoticeTitle = "Database Notice",
    updateNoticeBody = "Database plugins update daily at 04:04 and 16:16 in each region's local time. Keep them current.",
}

local ABBREVIATIONS = IS_CN_BUILD and {
    [239] = "执政", [556] = "萨隆", [161] = "通天", [402] = "学院",
    [557] = "风行", [558] = "魔导", [560] = "洞窟", [559] = "节点",
    [525] = "水闸", [499] = "隐修", [505] = "破晨", [503] = "回响",
    [542] = "生态", [378] = "赎罪", [392] = "宏图", [391] = "天街",
    [500] = "鸦巢", [501] = "宝库", [502] = "千丝", [504] = "暗焰",
    [506] = "酒庄", [249] = "诸王", [250] = "神庙", [584] = "夺目",
    [585] = "竞技场", [586] = "洞穴", [587] = "密谋", [588] = "毒牙",
    [244] = "AD", [199] = "BRH", [405] = "BH", [210] = "CoS",
    [198] = "DHT", [463] = "永恒", [464] = "永恒", [245] = "FH",
    [507] = "格巴", [406] = "注能", [200] = "英灵", [375] = "仙林",
    [206] = "巢穴", [404] = "奈堡", [369] = "车间", [370] = "车间",
    [399] = "红玉", [165] = "影月", [353] = "围攻", [2] = "青龙",
    [382] = "剧场", [401] = "碧蓝", [168] = "永茂", [247] = "暴富",
    [376] = "通灵", [400] = "诺库德", [251] = "孢林", [438] = "旋云",
    [456] = "潮汐", [403] = "奥达", [248] = "庄园",
} or {}

-- Challenge map ID -> dungeon teleport spell IDs. These are the live 12.1
-- IDs used by QFXToolBox; multiple entries cover faction/legacy variants.
local TELEPORT_SPELLS = {
    [2] = { 131204 }, [161] = { 1254557, 159898 }, [163] = { 159895 },
    [164] = { 159897 }, [165] = { 159899 }, [166] = { 159900 },
    [167] = { 159902 }, [168] = { 159901 }, [169] = { 159896 },
    [198] = { 424163 }, [199] = { 424153 }, [200] = { 393764 },
    [206] = { 410078 }, [210] = { 393766 }, [239] = { 1254551 },
    [244] = { 424187 }, [245] = { 410071 }, [247] = { 467553, 467555 },
    [248] = { 424167 }, [249] = { 1286831 }, [250] = { 1286828 },
    [251] = { 410074 }, [353] = { 445418, 464256 }, [369] = { 373274 },
    [370] = { 373274 }, [375] = { 354464 }, [376] = { 354462 },
    [377] = { 354468 }, [378] = { 354465 }, [379] = { 354463 },
    [380] = { 354469 }, [381] = { 354466 }, [382] = { 354467 },
    [391] = { 367416 }, [392] = { 367416 }, [399] = { 393256 },
    [400] = { 393262 }, [401] = { 393279 }, [402] = { 393273 },
    [403] = { 393222 }, [404] = { 393276 }, [405] = { 393267 },
    [406] = { 393283 }, [438] = { 410080 }, [456] = { 424142 },
    [463] = { 424197 }, [464] = { 424197 }, [499] = { 445444 },
    [500] = { 445443 }, [501] = { 445269 }, [502] = { 445416 },
    [503] = { 445417 }, [504] = { 445441 }, [505] = { 445414 },
    [506] = { 445440 }, [507] = { 445424 }, [525] = { 1216786 },
    [542] = { 1237215 }, [556] = { 1254555 }, [557] = { 1254400 },
    [558] = { 1254572 }, [559] = { 1254563 }, [560] = { 1254559 },
    [583] = { 1254551 }, [584] = { 1286801 }, [585] = { 1286804 },
    [586] = { 1286807 }, [587] = { 1286809 }, [588] = { 1286812 },
}

local SUMMARY_KEYS = {
    "dataUpdated",
    "cutoff01",
    "cutoff1",
    "rank",
    "surpassed",
    "todayScore",
    "todayRank",
    "toTop25",
    "rankRange",
    "percentileRange",
}

local SUMMARY_ROW_HEIGHT = 17
local WEEKLY_LINE_HEIGHT = 18

local function SafeNumber(value, fallback)
    if Util and type(Util.SafeNumber) == "function" then
        return Util.SafeNumber(value) or fallback
    end
    local ok, number = pcall(tonumber, value)
    return ok and number or fallback
end

local function SafeString(value)
    if Util and type(Util.SafeString) == "function" then
        return Util.SafeString(value)
    end
    return type(value) == "string" and value or nil
end

local function GetNow()
    return type(GetTime) == "function" and (SafeNumber(GetTime(), 0) or 0) or 0
end

local function SafeCall(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(func, ...)
    if ok then return a, b, c, d, e end
    return nil
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function OpenMythicDetail()
    if ns.OpenMythicDetail then
        ns.OpenMythicDetail()
    elseif ns.ToggleMythicDetail then
        ns.ToggleMythicDetail()
    end
end

local function OpenGreatVault()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end
    if type(WeeklyRewards_ShowUI) == "function" then
        SafeCall(WeeklyRewards_ShowUI)
        return true
    end
    return false
end

local function IsKnownSpell(spellID)
    if not spellID then return false end
    if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
        local known = bank and SafeCall(C_SpellBook.IsSpellKnown, spellID, bank)
        if known ~= nil then return known == true end
        known = SafeCall(C_SpellBook.IsSpellKnown, spellID)
        if known ~= nil then return known == true end
    end
    if type(IsPlayerSpell) == "function" then
        local known = SafeCall(IsPlayerSpell, spellID)
        if known ~= nil then return known == true end
    end
    if type(IsSpellKnown) == "function" then
        local known = SafeCall(IsSpellKnown, spellID)
        if known ~= nil then return known == true end
    end
    return false
end

local function ResolveTeleportSpell(mapID)
    local spells = TELEPORT_SPELLS[mapID]
    if type(spells) ~= "table" then return nil, false end
    if mapID == 161 and type(UnitFactionGroup) == "function" and UnitFactionGroup("player") == "Horde" then
        spells = { 159898, 1254557 }
    end
    for _, spellID in ipairs(spells) do
        if IsKnownSpell(spellID) then return spellID, true end
    end
    return spells[1], false
end

local function SetFont(fontString, size, outline)
    if not fontString then return end
    fontString:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 13, outline or "OUTLINE")
    if fontString.SetShadowOffset then fontString:SetShadowOffset(1, -1) end
end

local function GetPlayerClassColor()
    if type(UnitClass) == "function" then
        local _, classToken = UnitClass("player")
        local color = classToken and CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classToken]
        if not color then
            color = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
        end
        if color then
            return color.r or 1, color.g or 0.82, color.b or 0
        end
    end
    return 1, 0.82, 0
end

local function GetMeetingStoneMainPanel()
    local libStub = _G.LibStub
    local netEaseEnv = libStub and libStub("NetEaseEnv-1.0", true)
    local env = netEaseEnv and netEaseEnv._NSList and netEaseEnv._NSList.MeetingStone
    return (env and env.MainPanel) or _G.MeetingStoneMainPanel
end

local function GetGroupFinderMainFrame()
    local addon = _G.GroupFinder
    return _G.GroupFinderAddonFrame
        or (type(addon) == "table" and addon.MainFrame and addon.MainFrame.frame)
end

local function GetPremadeGroupBoardMainFrame()
    local addon = _G.PremadeGroupBoard
    return _G.PremadeGroupBoardFrame
        or (type(addon) == "table" and addon.MainFrame and addon.MainFrame.frame)
end

local function GetMeetingStoneHappyMainFrame()
    local addon = _G.MeetingStone_Happy or _G.MeetingStoneHappy
    local candidate = _G.MeetingStone_HappyMainPanel
        or _G.MeetingStoneHappyMainPanel
        or _G.MeetingStone_HappyFrame
        or _G.MeetingStoneHappyFrame
        or (type(addon) == "table" and (
            addon.MainPanel
            or addon.MainFrame
            or (addon.UI and addon.UI.MainFrame)
        ))
        -- The currently installed happy build is MeetingStoneEX and extends
        -- NetEase MeetingStone's MainPanel instead of creating a second shell.
        or GetMeetingStoneMainPanel()
    if candidate and type(candidate.IsShown) ~= "function" and candidate.frame then
        candidate = candidate.frame
    end
    return candidate
end

local function GetNativeGroupFinderMainFrame()
    return _G.PVEFrame
end

local DATA_PACK_ADDONS = {
    us = "QFXMythicRankData_US",
    eu = "QFXMythicRankData_EU",
    kr = "QFXMythicRankData_KR",
    tw = "QFXMythicRankData_TW",
    cn = "QFXMythicRankData_CN",
}

local CLIENT_REGION_KEYS = { "us", "kr", "eu", "tw", "cn" }

local SUPPORTED_LOAD_EVENTS = {
    GroupFinder = true,
    PremadeGroupBoard = true,
    MeetingStone_Happy = true,
    MeetingStoneHappy = true,
    MeetingStoneEX = true,
    MeetingStone = true,
    Blizzard_GroupFinder = true,
}

local function GetAddOnEnableStateCompat(name)
    local state = C_AddOns and SafeCall(C_AddOns.GetAddOnEnableState, name)
    if state == nil and type(_G.GetAddOnEnableState) == "function" then
        state = SafeCall(_G.GetAddOnEnableState, nil, name)
    end
    return SafeNumber(state, 0) or 0
end

local function IsAddOnEnabledCompat(name)
    return GetAddOnEnableStateCompat(name) > 0
end

local function GetRequiredDataPack()
    local region
    if ns.GetSelectedRegion then
        region = ns.GetSelectedRegion()
    end
    if not region and ns.GetDB then
        local db = ns.GetDB()
        region = type(db) == "table" and db.selectedRegion or nil
    end
    if not region and IS_CN_BUILD then
        region = "cn"
    end
    if not region and type(_G.GetCurrentRegion) == "function" then
        region = CLIENT_REGION_KEYS[SafeNumber(SafeCall(_G.GetCurrentRegion))]
    end
    return region, DATA_PACK_ADDONS[region] or "QFXMythicRankData_<REGION>"
end

local function HasRankingDataPack()
    local region, addonName = GetRequiredDataPack()
    if region and type(ns.IsRegionLoaded) == "function" then
        local ok, loaded = pcall(ns.IsRegionLoaded, region)
        return ok and loaded == true, addonName
    end
    local API = _G.QFXMythicRankData
    return type(API) == "table" and type(API.GetMetadata) == "function", addonName
end

local HOST_ADAPTERS = {
    { key = "groupFinder", addonNames = { "GroupFinder" }, resolve = GetGroupFinderMainFrame },
    { key = "premadeGroupBoard", addonNames = { "PremadeGroupBoard" }, resolve = GetPremadeGroupBoardMainFrame },
    {
        key = "meetingStoneHappy",
        addonNames = { "MeetingStone_Happy", "MeetingStoneHappy", "MeetingStoneEX" },
        resolve = GetMeetingStoneHappyMainFrame,
    },
    { key = "meetingStone", addonNames = { "MeetingStone" }, resolve = GetMeetingStoneMainPanel },
    { key = "blizzard", native = true, resolve = GetNativeGroupFinderMainFrame },
}

local function IsAdapterEnabled(adapter)
    -- Always hook the native group finder as well. A custom board being
    -- enabled does not prevent the player from opening Blizzard's PVEFrame.
    if adapter.native then return true end
    for _, name in ipairs(adapter.addonNames or {}) do
        if IsAddOnEnabledCompat(name) then return true end
    end
    local hasEnableStateAPI = (C_AddOns and type(C_AddOns.GetAddOnEnableState) == "function")
        or type(_G.GetAddOnEnableState) == "function"
    if hasEnableStateAPI then return false end
    -- Older clients may not expose enable states; an already-created frame is
    -- definitive proof that the adapter is usable in that environment.
    return adapter.resolve() ~= nil
end

local function GetSeasonMapIDs()
    local maps = C_ChallengeMode and SafeCall(C_ChallengeMode.GetMapTable)
    return type(maps) == "table" and maps or {}
end

local function GetMapInfo(mapID)
    if not C_ChallengeMode then return nil, nil end
    local name, _, _, texture = SafeCall(C_ChallengeMode.GetMapUIInfo, mapID)
    return name, texture
end

local function GetMapAbbreviation(mapID, name)
    local abbreviation = ABBREVIATIONS[mapID]
    if abbreviation then return abbreviation end
    if type(name) ~= "string" or name == "" then return tostring(mapID or "?") end
    return name
end

local function IsTeleportSpellForMap(spellID, mapID)
    spellID = SafeNumber(spellID)
    local spells = TELEPORT_SPELLS[SafeNumber(mapID)]
    if not spellID or type(spells) ~= "table" then return false end
    for _, candidate in ipairs(spells) do
        if spellID == candidate then return true end
    end
    return false
end

local function FindTeleportMapID(spellID, preferredMapID)
    if preferredMapID and IsTeleportSpellForMap(spellID, preferredMapID) then
        return preferredMapID
    end
    for _, mapID in ipairs(GetSeasonMapIDs()) do
        if IsTeleportSpellForMap(spellID, mapID) then return mapID end
    end
    for mapID in pairs(TELEPORT_SPELLS) do
        if IsTeleportSpellForMap(spellID, mapID) then return mapID end
    end
end

local function GetTeleportDestinationName(mapID)
    local localizedName = GetMapInfo(mapID)
    return localizedName or GetMapAbbreviation(mapID, localizedName)
end

local function ClearTeleportIntent()
    integration.pendingTeleportMapID = nil
    integration.pendingTeleportAt = nil
    integration.lastPlayerCastSentGUID = nil
    integration.lastPlayerCastSentSpellID = nil
    integration.lastPlayerCastSentAt = 0
end

local function RecordTeleportClick(mapID)
    integration.pendingTeleportMapID = SafeNumber(mapID)
    integration.pendingTeleportAt = GetNow()
end

local function RecordPlayerCast(castGUID, spellID)
    integration.lastPlayerCastSentGUID = SafeString(castGUID)
    integration.lastPlayerCastSentSpellID = SafeNumber(spellID)
    integration.lastPlayerCastSentAt = GetNow()
end

local function SendTeleportAnnouncement(unit, castGUID, spellID)
    if unit ~= "player" then return end
    spellID = SafeNumber(spellID)
    local guid = SafeString(castGUID)
    local now = GetNow()
    local clickedMapID = integration.pendingTeleportMapID
    local clickedAt = integration.pendingTeleportAt
    if clickedMapID and clickedAt and clickedAt > 0 and now - clickedAt > 20 then
        clickedMapID = nil
    end
    local sentMatches = (guid and guid == integration.lastPlayerCastSentGUID)
        or (spellID and spellID == integration.lastPlayerCastSentSpellID
            and now - integration.lastPlayerCastSentAt < 3)
    if not sentMatches and not clickedMapID then return end

    ClearTeleportIntent()
    local mapID = FindTeleportMapID(spellID, clickedMapID)
    if not mapID then return end
    if ns.IsTeleportAnnouncementEnabled and not ns.IsTeleportAnnouncementEnabled() then return end
    if not ns.IsTeleportAnnouncementEnabled then
        local settings = ns.GetDB and ns.GetDB()
        if settings and settings.announceTeleport == false then return end
    end
    if (guid and guid == integration.lastTeleportAnnouncementGUID)
        or (not guid and spellID == integration.lastTeleportAnnouncementSpellID
            and now - integration.lastTeleportAnnouncementAt < 2)
    then
        return
    end
    if type(IsInGroup) == "function" then
        local ok, grouped = pcall(IsInGroup, LE_PARTY_CATEGORY_HOME)
        if not ok or not grouped then return end
    end
    local destination = GetTeleportDestinationName(mapID)
    if type(destination) ~= "string" or destination == "" then return end
    local formatText = L.TELEPORT_ANNOUNCEMENT_FORMAT or "Teleported to dungeon: %s"
    local ok, message = pcall(string.format, formatText, destination)
    if not ok or type(message) ~= "string" or message == "" then return end
    if type(SendChatMessage) ~= "function" then return end
    local sent = pcall(SendChatMessage, message, "PARTY")
    if sent then
        integration.lastTeleportAnnouncementGUID = guid
        integration.lastTeleportAnnouncementSpellID = spellID
        integration.lastTeleportAnnouncementAt = now
    end
end

local function GetRatingLookup()
    local lookup = {}
    if C_ChallengeMode and type(C_ChallengeMode.GetMapScoreInfo) == "function" then
        local scores = SafeCall(C_ChallengeMode.GetMapScoreInfo)
        if type(scores) == "table" then
            for _, raw in ipairs(scores) do
                if type(raw) == "table" then
                    local mapID = SafeNumber(raw.mapChallengeModeID)
                    if mapID then
                        lookup[mapID] = {
                            level = SafeNumber(raw.level, 0) or 0,
                            score = SafeNumber(raw.dungeonScore, 0) or 0,
                        }
                    end
                end
            end
        end
    end
    if C_PlayerInfo and type(C_PlayerInfo.GetPlayerMythicPlusRatingSummary) == "function" then
        local summary = SafeCall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, "player")
        if type(summary) == "table" and type(summary.runs) == "table" then
            for _, run in ipairs(summary.runs) do
                if type(run) == "table" then
                    local mapID = SafeNumber(run.challengeModeID)
                    if mapID and not lookup[mapID] then
                        lookup[mapID] = {
                            level = SafeNumber(run.bestRunLevel, 0) or 0,
                            score = SafeNumber(run.mapScore, 0) or 0,
                        }
                    end
                end
            end
        end
    end
    return lookup
end

local function GetScoreColor(score)
    local color
    if C_ChallengeMode and type(C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor) == "function" then
        color = SafeCall(C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor, score or 0)
    end
    if color then return color.r or 1, color.g or 1, color.b or 1 end
    return 0.4, 0.85, 1
end

local function GetLevelColor(level)
    local color
    if C_ChallengeMode and type(C_ChallengeMode.GetKeystoneLevelRarityColor) == "function" then
        color = SafeCall(C_ChallengeMode.GetKeystoneLevelRarityColor, level or 0)
    end
    if color then return color.r or 1, color.g or 1, color.b or 1 end
    return 1, 1, 1
end

local function ApplyBackdrop(frame, alpha)
    if not frame then return end
    local visual = ns.GetHUDVisualSettings and ns.GetHUDVisualSettings() or {}
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.025, 0.025, 0.035, alpha or visual.backgroundAlpha or 0.92)
    frame:SetBackdropBorderColor(
        visual.borderR or 0.72,
        visual.borderG or 0.56,
        visual.borderB or 0.18,
        visual.borderAlpha or 0.90
    )
end

local function CreateSectionTitle(parent, text)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(16)
    local label = frame:CreateFontString(nil, "OVERLAY")
    SetFont(label, 14, "OUTLINE")
    label:SetPoint("CENTER")
    label:SetText(text)
    label:SetTextColor(1, 0.82, 0, 1)
    frame.label = label
    local left = frame:CreateTexture(nil, "ARTWORK")
    left:SetHeight(1)
    left:SetPoint("LEFT")
    left:SetPoint("RIGHT", label, "LEFT", -7, 0)
    left:SetColorTexture(1, 0.82, 0, 0.25)
    local right = frame:CreateTexture(nil, "ARTWORK")
    right:SetHeight(1)
    right:SetPoint("RIGHT")
    right:SetPoint("LEFT", label, "RIGHT", 7, 0)
    right:SetColorTexture(1, 0.82, 0, 0.25)
    return frame
end

local function CreateVaultProgressRow(parent, labelText)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(236, 19)
    row.label = row:CreateFontString(nil, "OVERLAY")
    SetFont(row.label, 12, "OUTLINE")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetWidth(54)
    row.label:SetJustifyH("LEFT")
    row.label:SetText(labelText)
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetPoint("LEFT", row, "LEFT", 58, 0)
    row.background:SetSize(130, 9)
    row.background:SetColorTexture(0, 0, 0, 0.55)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("TOPLEFT", row.background, "TOPLEFT", 0, 0)
    row.bar:SetPoint("BOTTOMRIGHT", row.background, "BOTTOMRIGHT", 0, 0)
    row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetMinMaxValues(0, 1)
    row.value = row:CreateFontString(nil, "OVERLAY")
    SetFont(row.value, 12, "OUTLINE")
    row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.value:SetWidth(42)
    row.value:SetJustifyH("RIGHT")
    return row
end

local function CreateSeasonCard(parent)
    local card = CreateFrame(
        "Button",
        nil,
        parent,
        "SecureActionButtonTemplate,SecureHandlerStateTemplate"
    )
    card:EnableMouse(true)
    card:RegisterForClicks("LeftButtonUp")
    card:SetAttribute("useOnKeyDown", false)
    if type(card.SetToplevel) == "function" then
        card:SetToplevel(true)
    end
    card:HookScript("PreClick", function(self, button)
        if button == "LeftButton" and self.mapID and self.teleportSpellID then
            RecordTeleportClick(self.mapID)
        end
    end)

    card.background = card:CreateTexture(nil, "BACKGROUND")
    card.background:SetAllPoints()
    card.background:SetTexCoord(0.08, 0.92, 0.10, 0.90)
    card.background:SetDesaturated(false)
    card.background:SetVertexColor(1, 1, 1, 1)

    card.shade = card:CreateTexture(nil, "BORDER")
    card.shade:SetAllPoints()
    card.shade:SetColorTexture(0, 0, 0, 0.30)

    card.name = card:CreateFontString(nil, "OVERLAY")
    SetFont(card.name, 14, "THICKOUTLINE")
    card.name:SetPoint("TOP", 0, -3)
    card.name:SetTextColor(1, 0.66, 0.05)

    card.level = card:CreateFontString(nil, "OVERLAY")
    SetFont(card.level, 24, "THICKOUTLINE")
    card.level:SetPoint("CENTER", 0, -1)

    card.score = card:CreateFontString(nil, "OVERLAY")
    SetFont(card.score, 16, "OUTLINE")
    card.score:SetPoint("BOTTOM", 0, 3)

    card.highlight = card:CreateTexture(nil, "HIGHLIGHT")
    card.highlight:SetAllPoints()
    card.highlight:SetColorTexture(1, 1, 1, 0.10)

    card:SetScript("OnEnter", function(self)
        if not self.mapID then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(self.mapName or tostring(self.mapID), 1, 1, 1)
        if self.bestLevel and self.bestLevel > 0 then
            GameTooltip:AddLine(string.format("+%d", self.bestLevel), 1, 0.82, 0)
        end
        if self.dungeonScore and self.dungeonScore > 0 then
            GameTooltip:AddLine(string.format("%s: %d", TEXT.score, math.floor(self.dungeonScore + 0.5)), 0.45, 0.9, 1)
        end
        if self.teleportKnown then
            GameTooltip:AddLine(TEXT.clickTeleport, 0.35, 1, 0.45)
        elseif type(InCombatLockdown) == "function" and InCombatLockdown() then
            GameTooltip:AddLine(TEXT.teleportCombat, 1, 0.35, 0.25)
        else
            GameTooltip:AddLine(TEXT.teleportLocked, 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", GameTooltip_Hide)
    return card
end

local function CreateSeasonResourceItem(parent)
    local item = CreateFrame("Button", nil, parent)
    item.icon = item:CreateTexture(nil, "ARTWORK")
    item.icon:SetPoint("LEFT", item, "LEFT", 3, 0)
    item.icon:SetSize(16, 16)
    item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    item.value = item:CreateFontString(nil, "OVERLAY")
    SetFont(item.value, 12, "OUTLINE")
    item.value:SetPoint("LEFT", item.icon, "RIGHT", 4, 0)
    item.value:SetPoint("RIGHT", item, "RIGHT", -2, 0)
    item.value:SetJustifyH("LEFT")
    item:SetScript("OnEnter", function(self)
        local resources = ns.MythicDetailResources
        if resources and resources.ShowTooltip then
            resources.ShowTooltip(self, self.resource)
        end
    end)
    item:SetScript("OnLeave", GameTooltip_Hide)
    return item
end

local function LayoutSeasonCards()
    local frame = integration.seasonBar
    if not frame then return end
    local count = integration.visibleCardCount or 0
    if count < 1 then return end
    local width = math.max(1, frame:GetWidth() - 12)
    local resourceCount = integration.visibleResourceCount or 0
    if resourceCount > 0 then
        local resourceWidth = width / resourceCount
        for index = 1, resourceCount do
            local item = frame.resourceItems[index]
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", frame, "TOPLEFT", 6 + ((index - 1) * resourceWidth), -3)
            item:SetSize(resourceWidth - 1, 18)
        end
    end
    local cardWidth = width / count
    for index = 1, count do
        local card = integration.cards[index]
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", frame, "TOPLEFT", 6 + ((index - 1) * cardWidth), -23)
        card:SetSize(cardWidth - 2, 75)
        card.name:SetWidth(math.max(20, cardWidth - 8))
        card.name:SetWordWrap(false)
    end
end

local function CreateSeasonBar()
    if integration.seasonBar then return integration.seasonBar end
    local frame = CreateFrame("Frame", ADDON_NAME .. "GroupFinderSeasonBar", UIParent, "BackdropTemplate")
    frame:SetHeight(104)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(20)
    if type(frame.SetToplevel) == "function" then
        frame:SetToplevel(true)
    end
    ApplyBackdrop(frame)

    frame.resourceItems = {}
    frame.resourceData = {}
    frame:SetScript("OnSizeChanged", LayoutSeasonCards)
    frame:Hide()
    integration.seasonBar = frame
    return frame
end

local function UpdateSeasonResources()
    local frame = integration.seasonBar
    if not frame or not frame:IsShown() then return end
    local resources = ns.MythicDetailResources
    local quantityOverrides = integration.pendingCurrencyQuantities
    local resourceData = resources and resources.GetAll
        and resources.GetAll(frame.resourceData, quantityOverrides)
        or {}
    integration.pendingCurrencyQuantities = nil
    frame.resourceData = resourceData
    integration.visibleResourceCount = #resourceData
    for index, resource in ipairs(resourceData) do
        local item = frame.resourceItems[index]
        if not item then
            item = CreateSeasonResourceItem(frame)
            frame.resourceItems[index] = item
        end
        item.resource = resource
        item.icon:SetTexture(resource.icon or 134400)
        item.value:SetText(resource.quantity ~= nil and tostring(resource.quantity) or "-")
        item.value:SetTextColor(resource.discovered == false and 0.55 or 1, resource.discovered == false and 0.55 or 1, resource.discovered == false and 0.55 or 1)
        item:Show()
    end
    for index = #resourceData + 1, #frame.resourceItems do
        frame.resourceItems[index]:Hide()
    end
    LayoutSeasonCards()
end

local function UpdateTeleportBindings()
    local frame = integration.seasonBar
    if not frame or not frame:IsShown() then return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
    for _, card in ipairs(integration.cards) do
        if card.mapID then
            local teleportSpellID, teleportKnown = ResolveTeleportSpell(card.mapID)
            card.teleportSpellID = teleportSpellID
            card.teleportKnown = teleportKnown
            card:SetAttribute("type1", teleportSpellID and "spell" or nil)
            card:SetAttribute("spell1", teleportSpellID)
            card:SetAttribute("spell", teleportSpellID)
        end
    end
end

local function UpdateSeasonBar(refreshResources)
    local frame = integration.seasonBar
    if not frame or not frame:IsShown() then return end
    if refreshResources ~= false then
        UpdateSeasonResources()
    end

    local maps = GetSeasonMapIDs()
    local rating = GetRatingLookup()
    local count = math.min(#maps, 8)
    integration.visibleCardCount = count
    for index = 1, 8 do
        local card = integration.cards[index]
        if index <= count then
            if not card then
                card = CreateSeasonCard(frame)
                integration.cards[index] = card
            end
            local mapID = SafeNumber(maps[index])
            local name, texture = GetMapInfo(mapID)
            local best = rating[mapID] or {}
            local level = SafeNumber(best.level, 0) or 0
            local score = SafeNumber(best.score, 0) or 0
            card.mapID = mapID
            card.mapName = name
            card.bestLevel = level
            card.dungeonScore = score
            local teleportSpellID, teleportKnown = ResolveTeleportSpell(mapID)
            card.teleportSpellID = teleportSpellID
            card.teleportKnown = teleportKnown
            if not (type(InCombatLockdown) == "function" and InCombatLockdown()) then
                -- Bind whenever a map has a portal spell. Spellbook detection
                -- is advisory only: some clients return nil during login even
                -- though the spell is already usable.
                card:SetAttribute("type1", teleportSpellID and "spell" or nil)
                card:SetAttribute("spell1", teleportSpellID)
                card:SetAttribute("spell", teleportSpellID)
            end
            card.background:SetTexture(texture or 134400)
            card.name:SetText(GetMapAbbreviation(mapID, name))
            card.level:SetText(level > 0 and tostring(level) or "-")
            card.level:SetTextColor(GetLevelColor(level))
            card.score:SetText(score > 0 and tostring(math.floor(score + 0.5)) or "-")
            card.score:SetTextColor(GetScoreColor(score))
            card:Show()
        elseif card then
            card:Hide()
        end
    end
    LayoutSeasonCards()
end

local function TextureMarkup(texture)
    return string.format("|T%s:14:14:0:0|t", tostring(texture or 134400))
end

local function GetWeeklyRuns()
    if C_MythicPlus and type(C_MythicPlus.RequestMapInfo) == "function" then
        SafeCall(C_MythicPlus.RequestMapInfo)
    end
    local runs = C_MythicPlus and SafeCall(C_MythicPlus.GetRunHistory, false, true, true)
    return type(runs) == "table" and runs or {}
end

local function SortRuns(runs)
    table.sort(runs, function(left, right)
        local leftLevel = SafeNumber(left and left.level, 0) or 0
        local rightLevel = SafeNumber(right and right.level, 0) or 0
        if leftLevel ~= rightLevel then return leftLevel > rightLevel end
        return (SafeNumber(left and left.mapChallengeModeID, 0) or 0)
            < (SafeNumber(right and right.mapChallengeModeID, 0) or 0)
    end)
end

local function IsTimedRun(run)
    if type(run) ~= "table" then return false end
    local duration = SafeNumber(run.durationSec)
    local mapID = SafeNumber(run.mapChallengeModeID)
    if duration and mapID then
        local _, _, timeLimit = SafeCall(C_ChallengeMode and C_ChallengeMode.GetMapUIInfo, mapID)
        timeLimit = SafeNumber(timeLimit)
        if timeLimit and timeLimit > 0 then return duration <= timeLimit end
    end
    return run.completed == true
end

local function LayoutSidePanel(panel, visibleSummaryCount, weeklyContentHeight)
    if not panel then return end
    visibleSummaryCount = SafeNumber(visibleSummaryCount, panel.visibleSummaryCount or 0) or 0
    weeklyContentHeight = SafeNumber(weeklyContentHeight, panel.weeklyContentHeight or (8 * 17)) or (8 * 17)
    panel.visibleSummaryCount = math.max(0, visibleSummaryCount)
    panel.weeklyContentHeight = math.max(17, math.ceil(weeklyContentHeight))

    local vaultTitleTop = 101 + (panel.visibleSummaryCount * SUMMARY_ROW_HEIGHT) + 8
    local vaultRowsTop = vaultTitleTop + 21
    local detailsTitleTop = vaultRowsTop + (3 * 21) + 13
    local lowerDisplayTop = detailsTitleTop + 21
    local panelHeight = lowerDisplayTop + panel.weeklyContentHeight + 12

    panel.weeklyVaultTitle:ClearAllPoints()
    panel.weeklyVaultTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -vaultTitleTop)
    panel.weeklyVaultTitle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -vaultTitleTop)
    for index, row in ipairs(panel.vaultRows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -vaultRowsTop - ((index - 1) * 21))
    end
    panel.vaultButton:ClearAllPoints()
    panel.vaultButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -(vaultTitleTop - 2))
    panel.vaultButton:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", -8, -(detailsTitleTop - 8))
    panel.weeklyDetailsTitle:ClearAllPoints()
    panel.weeklyDetailsTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -detailsTitleTop)
    panel.weeklyDetailsTitle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -detailsTitleTop)
    panel.lowerDisplay:ClearAllPoints()
    panel.lowerDisplay:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -lowerDisplayTop)
    panel.lowerDisplay:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -lowerDisplayTop)
    panel:SetHeight(panelHeight)
end

local function UpdateProfileSummary()
    local panel = integration.sidePanel
    if not panel or not panel:IsShown() then return end
    local hasDataPack, requiredAddon = HasRankingDataPack()
    if not hasDataPack then
        panel.profileButton:Hide()
        for _, key in ipairs(SUMMARY_KEYS) do
            integration.summaryRows[key]:Hide()
        end
        panel.dataPackNotice:SetText(string.format(
            "|cffff5555%s|r\n|cffffffff%s|r\n|cffaaaaaa%s|r",
            TEXT.dataPackMissing,
            string.format(TEXT.dataPackInstall, requiredAddon),
            TEXT.dataPackPurpose
        ))
        panel.dataPackNotice:Show()
        LayoutSidePanel(panel, 0, panel.weeklyContentHeight)
        return
    end
    panel.dataPackNotice:Hide()
    panel.profileButton:Show()
    local snapshot, showRows
    if ns.GetHUDSnapshot then
        snapshot, showRows = ns.GetHUDSnapshot(true)
    else
        snapshot, showRows = {}, {}
    end
    snapshot = type(snapshot) == "table" and snapshot or {}
    showRows = type(showRows) == "table" and showRows or {}

    if type(SetPortraitTexture) == "function" then
        SetPortraitTexture(panel.profileButton.portrait, "player")
    end
    panel.profileButton.playerName:SetText(UnitName("player") or "")
    panel.profileButton.playerName:SetTextColor(GetPlayerClassColor())
    local score = snapshot.score
    panel.profileButton.score:SetText(score and score.value or TEXT.noScore)
    panel.profileButton.score:SetTextColor(
        score and score.r or 0.65,
        score and score.g or 0.65,
        score and score.b or 0.65
    )

    local visible = 0
    for _, key in ipairs(SUMMARY_KEYS) do
        local source = snapshot[key]
        local row = integration.summaryRows[key]
        local shouldShow = source and showRows[key] ~= false
        row:SetShown(shouldShow and true or false)
        if shouldShow then
            row:SetHeight(SUMMARY_ROW_HEIGHT)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -101 - (visible * SUMMARY_ROW_HEIGHT))
            row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -101 - (visible * SUMMARY_ROW_HEIGHT))
            if key == "dataUpdated" then
                row.label:SetText("")
                row.value:ClearAllPoints()
                row.value:SetAllPoints(row)
                row.value:SetJustifyH("CENTER")
                row.value:SetJustifyV("MIDDLE")
                row.value:SetWordWrap(false)
            else
                row.label:SetText(source.label or "")
                row.value:ClearAllPoints()
                row.value:SetPoint("LEFT", row, "CENTER", -4, 0)
                row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                row.value:SetJustifyH("RIGHT")
                row.value:SetWordWrap(false)
            end
            row.value:SetText(source.value or "--")
            row.value:SetTextColor(source.r or 1, source.g or 1, source.b or 1)
            visible = visible + 1
        end
    end
    LayoutSidePanel(panel, visible, panel.weeklyContentHeight)
end

local function UpdateWeeklyDetails()
    local panel = integration.sidePanel
    if not panel or not panel:IsShown() then return end
    local runs = GetWeeklyRuns()
    SortRuns(runs)

    local totalRuns = #runs
    local timedRuns = 0
    for _, run in ipairs(runs) do
        if IsTimedRun(run) then
            timedRuns = timedRuns + 1
        end
    end
    panel.weeklyDetailsTitle.label:SetText(string.format(
        TEXT.weeklyDetailsStats,
        TEXT.weeklyDetails,
        totalRuns,
        timedRuns,
        totalRuns - timedRuns
    ))

    local vaultData = ns.MythicDetailData
    local vault = vaultData and vaultData.RefreshVault and vaultData.RefreshVault()
    local categories = vault and vault.categories or {}
    local vaultKeys = { "raid", "mythicPlus", "world" }
    for index, key in ipairs(vaultKeys) do
        local row = panel.vaultRows[index]
        local category = categories[key]
        local available = category and category.available == true
        local fallbackMaximum = key == "raid" and 6 or 8
        local maximum = math.max(1, SafeNumber(category and category.maximum, fallbackMaximum) or fallbackMaximum)
        local progress = available and (SafeNumber(category.progress, 0) or 0) or 0
        progress = math.max(0, math.min(maximum, progress))
        row.bar:SetMinMaxValues(0, maximum)
        row.bar:SetValue(progress)
        if not available then
            row.bar:SetStatusBarColor(0.45, 0.45, 0.45, 0.45)
            row.value:SetText("--/" .. tostring(maximum))
            row.value:SetTextColor(0.6, 0.6, 0.6)
        elseif progress >= maximum then
            row.bar:SetStatusBarColor(0.2, 0.9, 0.35, 0.9)
            row.value:SetText(string.format("%d/%d", progress, maximum))
            row.value:SetTextColor(0.2, 1, 0.4)
        else
            row.bar:SetStatusBarColor(1, 0.72, 0.05, 0.9)
            row.value:SetText(string.format("%d/%d", progress, maximum))
            row.value:SetTextColor(1, 0.82, 0)
        end
    end

    local maps = GetSeasonMapIDs()
    local byMapID = {}
    for _, run in ipairs(runs) do
        local mapID = SafeNumber(run.mapChallengeModeID)
        if mapID then
            local entries = byMapID[mapID] or {}
            entries[#entries + 1] = {
                level = SafeNumber(run.level, 0) or 0,
                timed = IsTimedRun(run),
            }
            byMapID[mapID] = entries
        end
    end

    local lower = {}
    for index = 1, math.min(#maps, 8) do
        local mapID = SafeNumber(maps[index])
        local name, texture = GetMapInfo(mapID)
        local entries = byMapID[mapID] or {}
        table.sort(entries, function(left, right) return left.level > right.level end)
        local levels = {}
        for _, entry in ipairs(entries) do
            levels[#levels + 1] = (entry.timed and "|cff00ff00" or "|cffff4444") .. tostring(entry.level) .. "|r"
        end
        if #levels == 0 then levels[1] = "|cff888888-|r" end
        lower[#lower + 1] = string.format(
            "%s |cffffd100%s|r (%s)",
            TextureMarkup(texture), GetMapAbbreviation(mapID, name), table.concat(levels, " ")
        )
    end
    panel.lowerDisplay:SetText(table.concat(lower, "\n"))
    local weeklyContentHeight = math.max(1, math.min(#maps, 8)) * WEEKLY_LINE_HEIGHT
    if type(panel.lowerDisplay.GetStringHeight) == "function" then
        weeklyContentHeight = SafeNumber(panel.lowerDisplay:GetStringHeight(), weeklyContentHeight) or weeklyContentHeight
    end
    LayoutSidePanel(panel, panel.visibleSummaryCount, weeklyContentHeight)
end

local function CreateSidePanel()
    if integration.sidePanel then return integration.sidePanel end
    local panel = CreateFrame("Frame", ADDON_NAME .. "GroupFinderSidePanel", UIParent, "BackdropTemplate")
    panel:SetSize(260, 526)
    panel:SetFrameStrata("MEDIUM")
    panel:SetFrameLevel(20)
    ApplyBackdrop(panel)

    panel.title = panel:CreateFontString(nil, "OVERLAY")
    SetFont(panel.title, 14, "OUTLINE")
    panel.title:SetPoint("TOP", 0, -8)
    panel.title:SetText(TEXT.combinedTitle)
    panel.title:SetTextColor(1, 0.82, 0)

    panel.dataPackNotice = panel:CreateFontString(nil, "OVERLAY")
    SetFont(panel.dataPackNotice, 12, "OUTLINE")
    panel.dataPackNotice:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -31)
    panel.dataPackNotice:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -31)
    panel.dataPackNotice:SetHeight(56)
    panel.dataPackNotice:SetJustifyH("CENTER")
    panel.dataPackNotice:SetJustifyV("MIDDLE")
    panel.dataPackNotice:SetWordWrap(true)
    panel.dataPackNotice:Hide()

    local profile = CreateFrame("Button", nil, panel)
    profile:SetPoint("TOPLEFT", 10, -29)
    profile:SetPoint("TOPRIGHT", -10, -29)
    profile:SetHeight(62)
    profile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    panel.profileButton = profile

    profile.highlight = profile:CreateTexture(nil, "HIGHLIGHT")
    profile.highlight:SetAllPoints()
    profile.highlight:SetColorTexture(1, 0.82, 0, 0.10)

    profile.portraitBorder = profile:CreateTexture(nil, "BORDER")
    profile.portraitBorder:SetPoint("LEFT", 3, 0)
    profile.portraitBorder:SetSize(58, 58)
    profile.portraitBorder:SetColorTexture(0.72, 0.56, 0.18, 0.95)

    profile.portrait = profile:CreateTexture(nil, "ARTWORK")
    profile.portrait:SetPoint("CENTER", profile.portraitBorder)
    profile.portrait:SetSize(54, 54)
    profile.portrait:SetTexCoord(0.15, 0.85, 0.15, 0.85)

    profile.playerName = profile:CreateFontString(nil, "OVERLAY")
    SetFont(profile.playerName, 16, "OUTLINE")
    profile.playerName:SetPoint("TOPLEFT", profile.portraitBorder, "TOPRIGHT", 10, -3)
    profile.playerName:SetPoint("RIGHT", -4, 0)
    profile.playerName:SetJustifyH("LEFT")

    profile.scoreLabel = profile:CreateFontString(nil, "OVERLAY")
    SetFont(profile.scoreLabel, 12, "OUTLINE")
    profile.scoreLabel:SetPoint("BOTTOMLEFT", profile.portraitBorder, "BOTTOMRIGHT", 10, 5)
    profile.scoreLabel:SetText(TEXT.score)
    profile.scoreLabel:SetTextColor(0.75, 0.75, 0.75)

    profile.score = profile:CreateFontString(nil, "OVERLAY")
    SetFont(profile.score, 18, "THICKOUTLINE")
    profile.score:SetPoint("LEFT", profile.scoreLabel, "RIGHT", 6, 0)

    profile:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if ns.OpenSettings then ns.OpenSettings() end
        else
            OpenMythicDetail()
        end
    end)
    profile:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.L and ns.L.ADDON_TITLE or ADDON_NAME, 1, 0.82, 0)
        GameTooltip:AddLine(TEXT.clickDetails, 0.55, 0.85, 1)
        GameTooltip:AddLine(TEXT.rightClickSettings, 0.65, 0.65, 0.65)
        GameTooltip:Show()
    end)
    profile:SetScript("OnLeave", GameTooltip_Hide)

    for _, key in ipairs(SUMMARY_KEYS) do
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(SUMMARY_ROW_HEIGHT)
        row.label = row:CreateFontString(nil, "OVERLAY")
        SetFont(row.label, 12, "OUTLINE")
        row.label:SetPoint("LEFT")
        row.label:SetPoint("RIGHT", row, "CENTER", -7, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetTextColor(0.78, 0.78, 0.78)
        row.value = row:CreateFontString(nil, "OVERLAY")
        SetFont(row.value, 12, "OUTLINE")
        integration.summaryRows[key] = row
    end

    panel.weeklyVaultTitle = CreateSectionTitle(panel, TEXT.weeklyVault)
    panel.weeklyVaultTitle:SetPoint("TOPLEFT", 8, -222)
    panel.weeklyVaultTitle:SetPoint("TOPRIGHT", -8, -222)
    panel.vaultRows = {
        CreateVaultProgressRow(panel, L.VAULT_RAID or (IS_ZH_CN and "团本" or "Raid")),
        CreateVaultProgressRow(panel, L.VAULT_MYTHIC_PLUS or (IS_ZH_CN and "大秘境" or "Mythic+")),
        CreateVaultProgressRow(panel, L.VAULT_WORLD or (IS_ZH_CN and "世界" or "World")),
    }
    for index, row in ipairs(panel.vaultRows) do
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -243 - ((index - 1) * 21))
    end
    panel.vaultButton = CreateFrame("Button", nil, panel)
    panel.vaultButton:SetPoint("TOPLEFT", 8, -220)
    panel.vaultButton:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", -8, -310)
    panel.vaultButton:RegisterForClicks("LeftButtonUp")
    panel.vaultButton:SetScript("OnClick", OpenGreatVault)
    panel.vaultButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(TEXT.weeklyVault, 1, 0.82, 0)
        GameTooltip:AddLine(TEXT.clickVault, 0.55, 0.85, 1)
        GameTooltip:Show()
    end)
    panel.vaultButton:SetScript("OnLeave", GameTooltip_Hide)

    panel.weeklyDetailsTitle = CreateSectionTitle(panel, TEXT.weeklyDetails)
    SetFont(panel.weeklyDetailsTitle.label, 12, "OUTLINE")
    panel.weeklyDetailsTitle:SetPoint("TOPLEFT", 8, -322)
    panel.weeklyDetailsTitle:SetPoint("TOPRIGHT", -8, -322)
    panel.lowerDisplay = panel:CreateFontString(nil, "OVERLAY")
    SetFont(panel.lowerDisplay, 13, "OUTLINE")
    panel.lowerDisplay:SetPoint("TOPLEFT", 14, -343)
    panel.lowerDisplay:SetPoint("TOPRIGHT", -10, -343)
    panel.lowerDisplay:SetJustifyH("LEFT")
    panel.lowerDisplay:SetJustifyV("TOP")
    panel.lowerDisplay:SetWordWrap(true)
    panel.lowerDisplay:SetSpacing(1)

    LayoutSidePanel(panel, 0, 8 * WEEKLY_LINE_HEIGHT)

    panel:Hide()
    integration.sidePanel = panel
    return panel
end

local function CreateUpdateNotice()
    if integration.updateNotice then return integration.updateNotice end
    local notice = CreateFrame("Frame", ADDON_NAME .. "GroupFinderDatabaseNotice", UIParent, "BackdropTemplate")
    notice:SetSize(260, 104)
    notice:SetFrameStrata("MEDIUM")
    notice:SetFrameLevel(20)
    ApplyBackdrop(notice)

    notice.title = notice:CreateFontString(nil, "OVERLAY")
    SetFont(notice.title, 13, "OUTLINE")
    notice.title:SetPoint("TOP", notice, "TOP", 0, -9)
    notice.title:SetText(TEXT.updateNoticeTitle)
    notice.title:SetTextColor(1, 0.82, 0)

    notice.body = notice:CreateFontString(nil, "OVERLAY")
    SetFont(notice.body, 12, "OUTLINE")
    notice.body:SetPoint("TOPLEFT", notice, "TOPLEFT", 13, -31)
    notice.body:SetPoint("BOTTOMRIGHT", notice, "BOTTOMRIGHT", -13, 11)
    notice.body:SetJustifyH("CENTER")
    notice.body:SetJustifyV("MIDDLE")
    notice.body:SetWordWrap(true)
    notice.body:SetText(TEXT.updateNoticeBody)
    notice.body:SetTextColor(0.92, 0.92, 0.92)

    notice.closeButton = CreateFrame("Button", nil, notice, "UIPanelCloseButton")
    notice.closeButton:SetPoint("TOPRIGHT", notice, "TOPRIGHT", 1, 1)
    notice.closeButton:SetSize(22, 22)
    notice.closeButton:SetScript("OnClick", function()
        integration.updateNoticeDismissed = true
        notice:Hide()
    end)

    notice:Hide()
    integration.updateNotice = notice
    return notice
end

local function PositionIntegration()
    local mainPanel = integration.mainPanel
    if not mainPanel then return end
    local seasonBar = CreateSeasonBar()
    local strata = mainPanel.GetFrameStrata and mainPanel:GetFrameStrata()
    local level = mainPanel.GetFrameLevel and mainPanel:GetFrameLevel()
    if type(strata) == "string" then seasonBar:SetFrameStrata(strata) end
    if type(level) == "number" then seasonBar:SetFrameLevel(level + 5) end
    seasonBar:ClearAllPoints()
    seasonBar:SetPoint("BOTTOM", mainPanel, "TOP", 0, 3)
    local hostWidth = mainPanel.GetWidth and SafeNumber(mainPanel:GetWidth()) or nil
    seasonBar:SetWidth(math.max(320, math.min(680, hostWidth or 680)))

    local sidePanel = CreateSidePanel()
    if type(strata) == "string" then sidePanel:SetFrameStrata(strata) end
    if type(level) == "number" then sidePanel:SetFrameLevel(level + 5) end
    sidePanel:ClearAllPoints()
    sidePanel:SetPoint("TOPRIGHT", mainPanel, "TOPLEFT", -3, 0)

    local updateNotice = CreateUpdateNotice()
    if type(strata) == "string" then updateNotice:SetFrameStrata(strata) end
    if type(level) == "number" then updateNotice:SetFrameLevel(level + 5) end
    updateNotice:ClearAllPoints()
    updateNotice:SetPoint("BOTTOMLEFT", sidePanel, "TOPLEFT", 0, 3)
    updateNotice:SetWidth(sidePanel:GetWidth())
    updateNotice:SetHeight(seasonBar:GetHeight())
end

local function ApplyIntegrationStyle()
    ApplyBackdrop(integration.seasonBar)
    ApplyBackdrop(integration.sidePanel)
    ApplyBackdrop(integration.updateNotice)
end

local function UpdateVisibility(updates)
    local mainPanel = integration.mainPanel
    local settings = ns.GetDB and ns.GetDB()
    local enabled = not settings or settings.showHUD ~= false
    local shown = enabled and mainPanel and mainPanel.IsShown and mainPanel:IsShown()
    -- Anchoring to a protected host such as PVEFrame also protects the
    -- overlays. Defer mutations in combat and skip redundant SetShown calls.
    local locked = InCombat()
    local desired = shown and true or false
    local wantsStyle = updates and updates.style
    if locked then
        if integration.appliedShown ~= desired then
            integration.pendingVisibility = true
        end
        if wantsStyle then
            integration.pendingStyle = true
        end
    else
        integration.pendingVisibility = nil
        if shown and (not updates or updates.layout or integration.positionedHost ~= mainPanel) then
            PositionIntegration()
            integration.positionedHost = mainPanel
        end
        if wantsStyle or integration.pendingStyle then
            integration.pendingStyle = nil
            ApplyIntegrationStyle()
        end
        if integration.appliedShown ~= desired then
            integration.appliedShown = desired
            if integration.seasonBar then integration.seasonBar:SetShown(desired) end
            if integration.sidePanel then integration.sidePanel:SetShown(desired) end
        end
    end
    if shown then
        if not locked then
            integration.updateNotice:SetShown(not integration.updateNoticeDismissed)
        end
        local full = not updates or updates.full
        if full then
            UpdateSeasonBar(true)
        elseif updates.season then
            UpdateSeasonBar(false)
        else
            if updates.resources then UpdateSeasonResources() end
            if updates.teleports then UpdateTeleportBindings() end
        end
        if full or updates.profile then UpdateProfileSummary() end
        if full or updates.weekly then UpdateWeeklyDetails() end
    elseif integration.updateNotice and not locked then
        integration.updateNotice:Hide()
    end
end

local QueueRefresh
local SelectActiveHost

local function SetActiveHost(key, frame)
    if not frame then return false end
    integration.hostKey = key
    integration.mainPanel = frame
    UpdateVisibility()
    return true
end

local function HookHost(adapter, frame)
    if not frame or integration.hookedFrames[frame] then return frame ~= nil end
    integration.hookedFrames[frame] = adapter.key
    if type(frame.HookScript) ~= "function" then return true end
    frame:HookScript("OnShow", function(self)
        SetActiveHost(adapter.key, self)
    end)
    frame:HookScript("OnHide", function(self)
        if integration.mainPanel == self then
            -- Keep visibility state changes in UpdateVisibility so the
            -- bookkeeping stays synchronized and protected calls are deferred.
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0, function() SelectActiveHost() end)
            else
                SelectActiveHost()
            end
        end
    end)
    frame:HookScript("OnSizeChanged", function(self)
        if integration.mainPanel == self then QueueRefresh(0.05, "layout") end
    end)
    return true
end

local function HookAvailableHosts()
    local found = false
    local waiting = false
    local seen = {}
    for _, adapter in ipairs(HOST_ADAPTERS) do
        if IsAdapterEnabled(adapter) then
            local frame = adapter.resolve()
            if frame and not seen[frame] then
                seen[frame] = true
                found = HookHost(adapter, frame) or found
            elseif not frame and not adapter.native then
                waiting = true
            end
        end
    end
    return found, waiting
end

SelectActiveHost = function(updates)
    local current = integration.mainPanel
    if current and current.IsShown and current:IsShown() then
        UpdateVisibility(updates)
        return true
    end

    local firstAvailableKey, firstAvailableFrame
    for _, adapter in ipairs(HOST_ADAPTERS) do
        if IsAdapterEnabled(adapter) then
            local frame = adapter.resolve()
            if frame then
                if not firstAvailableFrame then
                    firstAvailableKey, firstAvailableFrame = adapter.key, frame
                end
                if frame.IsShown and frame:IsShown() then
                    return SetActiveHost(adapter.key, frame)
                end
            end
        end
    end

    integration.hostKey = firstAvailableKey
    integration.mainPanel = firstAvailableFrame
    UpdateVisibility(updates)
    return firstAvailableFrame ~= nil
end

QueueRefresh = function(delay, updateKind)
    updateKind = updateKind or "full"
    integration.pendingUpdates = integration.pendingUpdates or {}
    integration.pendingUpdates[updateKind] = true
    if integration.refreshQueued then return end
    integration.refreshQueued = true
    local function Run()
        integration.refreshQueued = false
        local updates = integration.pendingUpdates
        integration.pendingUpdates = {}
        HookAvailableHosts()
        SelectActiveHost(updates)
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay or 0.05, Run)
    else
        Run()
    end
end

-- Retry briefly while load-on-demand addons finish creating their frames.
-- Later addon/game events call HookAvailableHosts again, so no permanent
-- polling timer is needed.
local ATTACH_MAX_ATTEMPTS = 30

local TryAttach

local function ScheduleAttachRetry(delay)
    if not (C_Timer and type(C_Timer.After) == "function") then return end
    if integration.attachCheckScheduled then return end
    integration.attachCheckScheduled = true
    C_Timer.After(delay, function()
        integration.attachCheckScheduled = false
        TryAttach()
    end)
end

TryAttach = function()
    integration.attachAttempts = integration.attachAttempts + 1
    local attached, waiting = HookAvailableHosts()
    local current = integration.mainPanel
    if not (current and current.IsShown and current:IsShown()) then
        SelectActiveHost({ layout = true })
    end
    if (not attached or waiting) and integration.attachAttempts < ATTACH_MAX_ATTEMPTS then
        ScheduleAttachRetry(0.5)
    end
end

function ns.RefreshMeetingStoneIntegration(updateKind)
    QueueRefresh(0, updateKind)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
eventFrame:RegisterEvent("CHALLENGE_MODE_LEADERS_UPDATE")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("MYTHIC_PLUS_NEW_WEEKLY_RECORD")
eventFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
if type(eventFrame.RegisterUnitEvent) == "function" then
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
else
    eventFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
end
eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "UNIT_SPELLCAST_SENT" then
        if arg1 == "player" then RecordPlayerCast(arg3, arg4) end
        return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        SendTeleportAnnouncement(arg1, arg2, arg3)
        return
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        if arg1 == "player" then ClearTeleportIntent() end
        return
    end
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME or SUPPORTED_LOAD_EVENTS[arg1] then
            integration.attachAttempts = 0
            ScheduleAttachRetry(0.2)
            if not (C_Timer and type(C_Timer.After) == "function") then
                TryAttach()
            end
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        integration.attachAttempts = 0
        TryAttach()
        return
    end
    if event == "CURRENCY_DISPLAY_UPDATE" then
        local resources = ns.MythicDetailResources
        local currencyID = resources and resources.NormalizeResourceQuantity
            and resources.NormalizeResourceQuantity(arg1)
            or SafeNumber(arg1)
        local quantity = resources and resources.NormalizeResourceQuantity
            and resources.NormalizeResourceQuantity(arg2)
            or SafeNumber(arg2)
        local trackedKey = resources and resources.GetKeyForCurrencyID
            and resources.GetKeyForCurrencyID(currencyID)
        if currencyID and quantity and quantity >= 0
            and (not (resources and resources.GetKeyForCurrencyID) or trackedKey)
        then
            integration.pendingCurrencyQuantities = integration.pendingCurrencyQuantities or {}
            integration.pendingCurrencyQuantities[currencyID] = math.floor(quantity)
        end
        QueueRefresh(0.05, "resources")
    elseif event == "SPELLS_CHANGED" then
        QueueRefresh(0.10, "teleports")
    elseif event == "PLAYER_REGEN_ENABLED" then
        QueueRefresh(0.10, "teleports")
    elseif event == "WEEKLY_REWARDS_UPDATE" then
        QueueRefresh(0.10, "weekly")
    elseif event == "CHALLENGE_MODE_LEADERS_UPDATE" then
        QueueRefresh(0.10, "season")
    else
        QueueRefresh(event == "CHALLENGE_MODE_COMPLETED" and 1.0 or 0.10, "full")
    end
end)
