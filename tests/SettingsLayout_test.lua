-- Smoke test for the settings panel layout: builds the real control tree with a
-- stubbed WoW UI and checks that the announcement switches ended up in the
-- templates section and that nothing overlaps the way it used to.
local scripts = {}
local anchored = {} -- every control anchored to the panel canvas

local function NewRegion(kind, height, template)
    local region = { kind = kind, height = height, template = template, scripts = {} }
    function region:SetPoint(_, _, _, x, y)
        self.x, self.y = x, y
        if x and y then
            anchored[#anchored + 1] = { kind = kind, x = x, y = y, height = height }
        end
    end
    function region:SetSize(w, h) self.width, self.height = w, h end
    function region:SetWidth(w) self.width = w end
    function region:SetHeight(h) self.height = h end
    function region:SetText(text) self.text = text end
    function region:GetText() return self.text end
    function region:SetChecked(value) self.checked = value end
    function region:GetChecked() return self.checked end
    function region:SetScript(name, callback) self.scripts[name] = callback end
    function region:SetAutoFocus() end
    function region:ClearFocus() end
    function region:SetJustifyH() end
    function region:SetJustifyV() end
    function region:SetWordWrap() end
    function region:SetTextColor() end
    function region:CreateTexture()
        local texture = NewRegion("Texture", 0)
        function texture:SetColorTexture() end
        return texture
    end
    function region:EnableMouseWheel() end
    function region:SetScrollChild() end
    function region:SetVerticalScroll() end
    function region:GetVerticalScroll() return 0 end
    function region:GetVerticalScrollRange() return 0 end
    function region:SetMinMaxValues() end
    function region:SetValueStep() end
    function region:SetObeyStepOnDrag() end
    function region:SetValue(value) self.value = value end
    function region:GetValue() return self.value end
    function region:CreateFontString()
        local fontString = NewRegion("FontString", 12)
        scripts[#scripts + 1] = fontString
        return fontString
    end
    scripts[#scripts + 1] = region
    return region
end

_G.CreateFrame = function(_, _, _, template)
    local frame = NewRegion("Frame", 24, template)
    if template == "OptionsSliderTemplate" then
        frame.height = 16
        frame.Text = NewRegion("FontString", 12)
        frame.Low = NewRegion("FontString", 12)
        frame.High = NewRegion("FontString", 12)
    end
    if template == "UICheckButtonTemplate" or template == "InputBoxTemplate" then
        -- Mirror the label onto the frame so tests can find controls by text.
        frame.Text = NewRegion("FontString", 12)
        frame.Text.SetText = function(_, text)
            frame.text = text
        end
    end
    return frame
end

_G.C_Timer = { After = function(_, callback) callback() end }
_G.GetLocale = function() return "zhCN" end
_G.strtrim = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.SlashCmdList = {}
_G.GetAddOnMetadata = function() return "1.3.28" end

local category = { GetID = function() return 1 end }
_G.Settings = {
    RegisterCanvasLayoutCategory = function(panel)
        _G.createdPanel = panel
        return category
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}

local db = {
    showHUD = true,
    enableMythicDetail = true,
    announceTeleport = true,
    announceRunGain = true,
    announceMemberJoin = true,
    announceDelay = 5,
    borderStyle = "gold",
    borderAlpha = 0.85,
    backgroundAlpha = 0.88,
    detailBorderAlpha = 1,
    detailBackgroundAlpha = 0.9,
    showRows = {},
}

local L = {}
for _, key in ipairs({
    "ADDON_TITLE", "SETTINGS_SHOW_HUD", "SETTINGS_SHOW_HUD_DESC", "SETTINGS_VISIBLE_ROWS",
    "SETTINGS_VISIBLE_ROWS_DESC", "SETTINGS_SECTION_HUD", "SETTINGS_SECTION_APPEARANCE",
    "SETTINGS_APPEARANCE_DESC", "SETTINGS_ANNOUNCE_DESC", "SETTINGS_BORDER_STYLE",
    "SETTINGS_BORDER_TRANSPARENT", "SETTINGS_BORDER_GOLD", "SETTINGS_BORDER_CLASS",
    "SETTINGS_BORDER_ALPHA", "SETTINGS_BACKGROUND_ALPHA", "SETTINGS_DETAIL_GROUP",
    "SETTINGS_ENABLE_DETAIL", "SETTINGS_DETAIL_BORDER_ALPHA", "SETTINGS_DETAIL_BACKGROUND_ALPHA",
    "SETTINGS_ANNOUNCE_DELAY", "ANNOUNCE_DELAY_SECONDS", "SETTINGS_ANNOUNCE_TEXTS",
    "SETTINGS_TEXT_HINT", "SETTINGS_TEXT_RESET", "SETTINGS_TEXT_RESET_DONE",
    "SETTINGS_ANNOUNCE_TELEPORT", "SETTINGS_ANNOUNCE_RUN_GAIN", "SETTINGS_ANNOUNCE_MEMBER_JOIN",
    "SETTINGS_TEXT_TELEPORT", "SETTINGS_TEXT_RUN_LINE_GAIN", "SETTINGS_TEXT_RUN_LINE_NO_GAIN",
    "SETTINGS_TEXT_RUN_LINE_TODAY", "SETTINGS_TEXT_RUN_LINE_CURRENT", "SETTINGS_TEXT_RUN_LINE_AD",
    "SETTINGS_TEXT_WELCOME", "SETTINGS_TEXT_WELCOME_AGAIN", "SETTINGS_TEXT_WELCOME_TEAMMATE",
    "SETTINGS_TEXT_WELCOME_CLOSING", "SLASH_HELP",
    "CUTOFF_01", "CUTOFF_1", "SCORE", "SETTINGS_ROW_REGION_RANK", "SURPASSED", "TODAY_SCORE",
    "TODAY_RANK", "SETTINGS_ROW_NEXT_CUTOFF", "RANK_RANGE", "PERCENTILE_RANGE",
    "SETTINGS_ROW_DATA_UPDATED",
    "TELEPORT_ANNOUNCEMENT_FORMAT", "RUN_GAIN_LINE_GAIN", "RUN_GAIN_LINE_NO_GAIN",
    "RUN_GAIN_LINE_TODAY", "RUN_GAIN_LINE_CURRENT", "RUN_GAIN_LINE_AD",
    "WELCOME_TEAMMATE_FORMAT", "WELCOME_CLOSING_FORMAT",
}) do
    L[key] = key
end

local namespace = {
    L = L,
    GetDB = function() return db end,
    GetSelectedRegionLabel = function() return "国服" end,
    SetHUDShown = function() end,
    SetRowVisible = function() end,
    SetHUDBorderStyle = function() end,
    SetHUDBorderAlpha = function() end,
    SetHUDBackgroundAlpha = function() end,
    SetDetailEnabled = function() end,
    SetDetailBorderAlpha = function() end,
    SetDetailBackgroundAlpha = function() end,
    SetTeleportAnnouncementEnabled = function() end,
    SetRunGainAnnouncementEnabled = function() end,
    SetMemberWelcomeEnabled = function() end,
    SetRunAnnounceDelay = function() end,
    SetAnnounceTemplate = function() end,
    GetAnnounceTemplate = function() return nil end,
    ResetAnnounceTemplates = function() end,
    ApplyHUDStyle = function() end,
    ApplyDetailStyle = function() end,
    ApplyDetailFeatureState = function() end,
    IsMythicDetailCreated = function() return true end,
    OpenSettings = function() end,
}

local modulePath = arg and arg[1] or "Settings.lua"
assert(loadfile(modulePath))("QFXMythicRankHUD", namespace)

namespace.InitializeSettings()
assert(_G.createdPanel, "the settings panel was not registered")
_G.createdPanel.scripts.OnShow() -- builds the controls exactly like opening it

-- The three announcement switches must sit in the templates section (left
-- column, below it), not up in the top-right HUD area.
local switches, hintY, resetY, boxes = 0, nil, nil, 0
local boxRows = {}
for _, item in ipairs(scripts) do
    if item.text == "SETTINGS_ANNOUNCE_TELEPORT" or item.text == "SETTINGS_ANNOUNCE_RUN_GAIN"
        or item.text == "SETTINGS_ANNOUNCE_MEMBER_JOIN"
    then
        switches = switches + 1
        assert(item.x == 18, "an announcement switch is not in the left column: x=" .. tostring(item.x))
        assert(item.y and item.y <= -700, "an announcement switch is still in the top area: y=" .. tostring(item.y))
    end
    if item.text == "SETTINGS_TEXT_HINT" then hintY = item.y end
    if item.text == "SETTINGS_TEXT_RESET" then resetY = item.y end
    if item.template == "InputBoxTemplate" then
        boxes = boxes + 1
        assert(item.y, "a template box has no position")
        assert(not boxRows[item.y], "two template boxes share a row at y=" .. tostring(item.y))
        boxRows[item.y] = true
    end
end
assert(switches == 3, "expected 3 announcement switches, found " .. switches)
assert(boxes == 8, "expected 8 template boxes, found " .. boxes)
assert(hintY and resetY, "hint or reset button was not placed")

-- Radio options must carry visible labels even when the client's radio
-- template provides no text region (only the selection dot).
local radioCount = 0
for _, item in ipairs(scripts) do
    if item.template == "UIRadioButtonTemplate" then
        radioCount = radioCount + 1
        assert(item.LabelText and item.LabelText.text and item.LabelText.text ~= "",
            "a border color radio option has no label")
    end
end
assert(radioCount == 3, "expected 3 border color radio options, found " .. radioCount)

-- The hint is the last control before the reset button and leaves it room to
-- wrap, which is what the overlap fix is about.
assert(resetY <= hintY - 80, "the reset button does not leave room for the hint text")
for y in pairs(boxRows) do
    assert(y > hintY, "a template box sits at or below the hint line")
end

-- The top area keeps its spacing: moving the "displayed content" label up made
-- it sit on top of the "show in group finder" switch.
local showY, rowsLabelY
for _, item in ipairs(scripts) do
    if item.text == "SETTINGS_SHOW_HUD" then showY = item.y end
    if item.text == "SETTINGS_VISIBLE_ROWS" then rowsLabelY = item.y end
end
assert(showY and rowsLabelY, "the top-area controls were not placed")
assert(rowsLabelY <= showY - 40,
    "the displayed-content label sits too close to the switch above it: "
        .. tostring(rowsLabelY) .. " vs " .. tostring(showY))

-- Each template is a label line with a full-width input line under it, so the
-- box can never cover its own label.
local labels = {}
for _, item in ipairs(scripts) do
    if item.kind == "FontString" and item.x == 44 and item.y then
        labels[item.y] = true
    end
end
for _, item in ipairs(scripts) do
    if item.template == "InputBoxTemplate" then
        assert(item.width and item.width >= 480,
            "a template box is too narrow: " .. tostring(item.width))
        assert(item.x == 44, "a template box is not under its label: x=" .. tostring(item.x))
        assert(labels[item.y + 20],
            "no label line directly above the box at y=" .. tostring(item.y))
    end
end

print("SettingsLayout_test: OK")
