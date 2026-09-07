local _, ns = ...
local L = ns.L

local categoryID
local showHUDCheck
local detailCheck
local announceTeleportCheck
local borderAlphaSlider
local backgroundAlphaSlider
local detailBorderAlphaSlider
local detailBackgroundAlphaSlider
local borderChecks = {}
local rowChecks = {}
local refreshingControls = false
local pendingHUDStyle = false
local pendingDetailStyle = false
local controlsCreated = false

local function QueueHUDStyleApply()
    if pendingHUDStyle then
        return
    end
    pendingHUDStyle = true
    local function Apply()
        pendingHUDStyle = false
        ns.ApplyHUDStyle()
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, Apply)
    else
        Apply()
    end
end

local function QueueDetailStyleApply()
    if ns.IsMythicDetailCreated and not ns.IsMythicDetailCreated() then
        return
    end
    if pendingDetailStyle then
        return
    end
    pendingDetailStyle = true
    local function Apply()
        pendingDetailStyle = false
        ns.ApplyDetailStyle()
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, Apply)
    else
        Apply()
    end
end

local ROW_OPTIONS = {
    { key = "dataUpdated", label = "SETTINGS_ROW_DATA_UPDATED" },
    { key = "cutoff01", label = "CUTOFF_01" },
    { key = "cutoff1", label = "CUTOFF_1" },
    { key = "score", label = "SCORE" },
    { key = "rank", label = "SETTINGS_ROW_REGION_RANK" },
    { key = "surpassed", label = "SURPASSED" },
    { key = "todayScore", label = "TODAY_SCORE" },
    { key = "todayRank", label = "TODAY_RANK" },
    { key = "toTop25", label = "SETTINGS_ROW_NEXT_CUTOFF" },
    { key = "rankRange", label = "RANK_RANGE" },
    { key = "percentileRange", label = "PERCENTILE_RANGE" },
}

local function SetChecked(check, value)
    check:SetChecked(value and true or false)
end

local function CreateCheckButton(parent, x, y, label, onClick)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check.Text:SetText(label)
    check:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    return check
end

local function CreateBorderOption(parent, x, y, key, label)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check.Text:SetText(label)
    check:SetScript("OnClick", function()
        ns.SetHUDBorderStyle(key)
        for style, button in pairs(borderChecks) do
            SetChecked(button, style == key)
        end
        ns.ApplyHUDStyle()
        ns.ApplyDetailStyle()
    end)
    borderChecks[key] = check
    return check
end

local function SetSliderText(slider, text)
    if slider.Text then
        slider.Text:SetText(text)
        return
    end
    if not slider.ValueText then
        slider.ValueText = slider:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        slider.ValueText:SetPoint("BOTTOM", slider, "TOP", 0, 2)
    end
    slider.ValueText:SetText(text)
end

local function CreateSlider(parent, x, y, width, lowText, highText, minValue, maxValue, step, onValueChanged)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:SetWidth(width)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end
    if slider.Low then
        slider.Low:SetText(lowText)
    end
    if slider.High then
        slider.High:SetText(highText)
    end
    slider:SetScript("OnValueChanged", function(self, value)
        onValueChanged(self, value)
    end)
    return slider
end

local function RefreshControls()
    local db = ns.GetDB()
    refreshingControls = true

    if showHUDCheck then
        SetChecked(showHUDCheck, db.showHUD)
    end
    if detailCheck then
        SetChecked(detailCheck, db.enableMythicDetail ~= false)
    end
    if announceTeleportCheck then
        SetChecked(announceTeleportCheck, db.announceTeleport ~= false)
    end
    for key, check in pairs(rowChecks) do
        SetChecked(check, db.showRows[key] ~= false)
    end
    for style, check in pairs(borderChecks) do
        SetChecked(check, db.borderStyle == style)
    end
    if borderAlphaSlider then
        borderAlphaSlider:SetValue(db.borderAlpha)
        SetSliderText(borderAlphaSlider, string.format("%d%%", math.floor(db.borderAlpha * 100 + 0.5)))
    end
    if backgroundAlphaSlider then
        backgroundAlphaSlider:SetValue(db.backgroundAlpha)
        SetSliderText(backgroundAlphaSlider, string.format("%d%%", math.floor(db.backgroundAlpha * 100 + 0.5)))
    end
    if detailBorderAlphaSlider then
        detailBorderAlphaSlider:SetValue(db.detailBorderAlpha)
        SetSliderText(
            detailBorderAlphaSlider,
            string.format("%d%%", math.floor(db.detailBorderAlpha * 100 + 0.5))
        )
    end
    if detailBackgroundAlphaSlider then
        detailBackgroundAlphaSlider:SetValue(db.detailBackgroundAlpha)
        SetSliderText(
            detailBackgroundAlphaSlider,
            string.format("%d%%", math.floor(db.detailBackgroundAlpha * 100 + 0.5))
        )
    end
    refreshingControls = false
end

local function CreateSettingsPanel()
    if not Settings or type(Settings.RegisterCanvasLayoutCategory) ~= "function" then
        return
    end

    local panel = CreateFrame("Frame")
    panel.name = L.ADDON_TITLE
    panel:SetSize(660, 620)

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 4)
    scrollFrame:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(620, 720)
    scrollFrame:SetScrollChild(content)

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maximum = self:GetVerticalScrollRange() or 0
        local nextValue = current - (delta * 36)
        self:SetVerticalScroll(math.max(0, math.min(maximum, nextValue)))
    end)

    panel:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 then
            content:SetWidth(math.max(600, width - 44))
        end
    end)

    local function BuildSettingsControls()
        if controlsCreated then
            return
        end
        controlsCreated = true

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
    title:SetText(L.ADDON_TITLE)

    showHUDCheck = CreateCheckButton(content, 18, -56, L.SETTINGS_SHOW_HUD, function(checked)
        ns.SetHUDShown(checked)
    end)

    announceTeleportCheck = CreateCheckButton(content, 326, -56, L.SETTINGS_ANNOUNCE_TELEPORT, function(checked)
        ns.SetTeleportAnnouncementEnabled(checked)
    end)

    local rowsLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rowsLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 20, -104)
    rowsLabel:SetText(L.SETTINGS_VISIBLE_ROWS)

    for index, option in ipairs(ROW_OPTIONS) do
        local optionKey = option.key
        local optionLabel = option.label
        local column = index <= 6 and 0 or 1
        local rowIndex = column == 0 and index or index - 6
        local x = column == 0 and 18 or 326
        local y = -128 - ((rowIndex - 1) * 32)
        local check = CreateCheckButton(content, x, y, L[optionLabel], function(checked)
            ns.SetRowVisible(optionKey, checked)
        end)
        rowChecks[optionKey] = check
    end

    local borderStyleLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    borderStyleLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 20, -340)
    borderStyleLabel:SetText(L.SETTINGS_BORDER_STYLE)

    CreateBorderOption(content, 18, -364, "transparent", L.SETTINGS_BORDER_TRANSPARENT)
    CreateBorderOption(content, 170, -364, "gold", L.SETTINGS_BORDER_GOLD)
    CreateBorderOption(content, 300, -364, "class", L.SETTINGS_BORDER_CLASS)

    local borderAlphaLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    borderAlphaLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 20, -418)
    borderAlphaLabel:SetText(L.SETTINGS_BORDER_ALPHA)

    borderAlphaSlider = CreateSlider(content, 24, -448, 240, "0%", "100%", 0, 1, 0.05, function(slider, value)
        value = math.floor(value * 20 + 0.5) / 20
        SetSliderText(slider, string.format("%d%%", math.floor(value * 100 + 0.5)))
        if not refreshingControls then
            ns.SetHUDBorderAlpha(value)
            QueueHUDStyleApply()
        end
    end)

    local backgroundAlphaLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    backgroundAlphaLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 336, -418)
    backgroundAlphaLabel:SetText(L.SETTINGS_BACKGROUND_ALPHA)

    backgroundAlphaSlider = CreateSlider(content, 340, -448, 240, "0%", "100%", 0, 1, 0.05, function(slider, value)
        value = math.floor(value * 20 + 0.5) / 20
        SetSliderText(slider, string.format("%d%%", math.floor(value * 100 + 0.5)))
        if not refreshingControls then
            ns.SetHUDBackgroundAlpha(value)
            QueueHUDStyleApply()
        end
    end)

    local detailGroupLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    detailGroupLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 20, -540)
    detailGroupLabel:SetText(L.SETTINGS_DETAIL_GROUP)

    detailCheck = CreateCheckButton(content, 18, -566, L.SETTINGS_ENABLE_DETAIL, function(checked)
        ns.SetDetailEnabled(checked)
        ns.ApplyDetailFeatureState()
    end)

    local detailBorderAlphaLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    detailBorderAlphaLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 20, -618)
    detailBorderAlphaLabel:SetText(L.SETTINGS_DETAIL_BORDER_ALPHA)

    detailBorderAlphaSlider = CreateSlider(content, 24, -648, 240, "0%", "100%", 0, 1, 0.05, function(slider, value)
        value = math.floor(value * 20 + 0.5) / 20
        SetSliderText(slider, string.format("%d%%", math.floor(value * 100 + 0.5)))
        if not refreshingControls then
            ns.SetDetailBorderAlpha(value)
            QueueDetailStyleApply()
        end
    end)

    local detailBackgroundAlphaLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    detailBackgroundAlphaLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 336, -618)
    detailBackgroundAlphaLabel:SetText(L.SETTINGS_DETAIL_BACKGROUND_ALPHA)

    detailBackgroundAlphaSlider = CreateSlider(content, 340, -648, 240, "0%", "100%", 0, 1, 0.05, function(slider, value)
        value = math.floor(value * 20 + 0.5) / 20
        SetSliderText(slider, string.format("%d%%", math.floor(value * 100 + 0.5)))
        if not refreshingControls then
            ns.SetDetailBackgroundAlpha(value)
            QueueDetailStyleApply()
        end
    end)

    end

    panel:SetScript("OnShow", function()
        BuildSettingsControls()
        RefreshControls()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, L.ADDON_TITLE)
    Settings.RegisterAddOnCategory(category)
    if category.GetID then
        categoryID = category:GetID()
    else
        categoryID = category.ID
    end
end

function ns.OpenSettings()
    if categoryID and Settings and type(Settings.OpenToCategory) == "function" then
        Settings.OpenToCategory(categoryID)
    else
        print("|cffffd100QFX:|r " .. L.SLASH_HELP)
    end
end

SLASH_QFXMYTHICRANKHUD1 = "/qfxrank"
SlashCmdList.QFXMYTHICRANKHUD = function(message)
    local command = strtrim((message or "")):lower()
    local db = ns.GetDB()

    if command == "show" then
        ns.SetHUDShown(true)
    elseif command == "hide" then
        ns.SetHUDShown(false)
    elseif command == "ranges" then
        local enabled = not (db.showRows.rankRange and db.showRows.percentileRange)
        ns.SetRowVisible("rankRange", enabled)
        ns.SetRowVisible("percentileRange", enabled)
    elseif command == "" then
        ns.OpenSettings()
    else
        print("|cffffd100QFX:|r " .. L.SLASH_HELP)
    end
end

function ns.InitializeSettings()
    CreateSettingsPanel()
end
