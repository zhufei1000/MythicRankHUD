local ADDON_NAME, ns = ...
local L = ns.L

local categoryID
local showHUDCheck
local announceDelaySlider
local announceChecks = {}
local templateBoxes = {}
local detailCheck
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

local function PrintAddonMessage(message)
    print("|cffffd100" .. L.ADDON_TITLE .. ":|r " .. message)
end

local function GetAddOnVersion()
    local getter = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if type(getter) ~= "function" then
        return "Unknown"
    end
    local ok, version = pcall(getter, ADDON_NAME, "Version")
    return ok and version or "Unknown"
end

local function PrintDebugInfo()
    print(L.ADDON_TITLE)
    print("Addon name: " .. tostring(ADDON_NAME))
    print("TOC version: " .. tostring(GetAddOnVersion()))
    print("Client locale: " .. tostring(type(GetLocale) == "function" and GetLocale() or "Unknown"))
    print("Selected region: " .. tostring(ns.GetSelectedRegionLabel() or "None"))
    print("Score label: " .. tostring(L.SCORE))
    print("Dungeon label: " .. tostring(L.DETAIL_COLUMN_NAME))
    print("Runs label: " .. tostring(L.DETAIL_COLUMN_TOTAL))
    print("Raid label: " .. tostring(L.VAULT_RAID))
    print("Trend label: " .. tostring(L.DETAIL_CUTOFF_1))
    local integration = ns.MeetingStoneIntegration
    if type(integration) == "table" then
        local host = integration.mainPanel
        local hostShown = type(host) == "table" and host.IsShown and host:IsShown()
        local db = ns.GetDB and ns.GetDB() or {}
        print("Group board host: " .. tostring(integration.hostKey or "None"))
        print("Host frame found: " .. tostring(host ~= nil) .. ", shown: " .. tostring(hostShown == true))
        print("HUD enabled: " .. tostring(not db or db.showHUD ~= false))
        print("PremadeGroupBoardFrame exists: " .. tostring(_G.PremadeGroupBoardFrame ~= nil))
        print("Attach attempts: " .. tostring(integration.attachAttempts or 0)
            .. ", watcher scheduled: " .. tostring(integration.attachCheckScheduled == true))
    end
    local summary = ns.RunSummary
    if summary and type(summary.DescribeAnnounceState) == "function" then
        print(summary.DescribeAnnounceState())
    end
end

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

local function SetControlLabel(control, label)
    if control.Text then
        control.Text:SetText(label)
        return
    end
    -- Radio templates have no text region on some clients; attach one and
    -- widen the hit rectangle so clicking the label selects the option too.
    if not control.LabelText then
        control.LabelText = control:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        control.LabelText:SetPoint("LEFT", control, "RIGHT", 6, 0)
        control.LabelText:SetJustifyH("LEFT")
    end
    control.LabelText:SetText(label)
    if type(control.SetHitRectInsets) == "function" then
        local width
        if type(control.LabelText.GetStringWidth) == "function" then
            width = control.LabelText:GetStringWidth()
        end
        if type(width) ~= "number" or width <= 0 then
            width = #tostring(label) * 8
        end
        control:SetHitRectInsets(0, -(width + 12), 0, 0)
    end
end

local function CreateCheckButton(parent, x, y, label, onClick, template)
    local check
    if template then
        local ok, created = pcall(CreateFrame, "CheckButton", nil, parent, template)
        if ok and created then
            check = created
        end
    end
    check = check or CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    SetControlLabel(check, label)
    check:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    return check
end

local function CreateBorderOption(parent, x, y, key, label)
    local check = CreateCheckButton(parent, x, y, label, function()
        ns.SetHUDBorderStyle(key)
        for style, button in pairs(borderChecks) do
            SetChecked(button, style == key)
        end
        ns.ApplyHUDStyle()
        ns.ApplyDetailStyle()
    end, "UIRadioButtonTemplate")
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

-- A gold section title with a divider line gives the long scroll page a
-- readable hierarchy; both helpers return the next cursor position.
local function CreateSectionHeader(parent, text, y, width)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    title:SetWidth(math.max(100, width - 32))
    title:SetJustifyH("LEFT")
    title:SetText(text)
    title:SetTextColor(1, 0.82, 0)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y - 19)
    line:SetSize(math.max(100, width - 32), 1)
    line:SetColorTexture(1, 0.82, 0, 0.22)
    return y - 30
end

local function CreateDescription(parent, text, y, width)
    if type(text) ~= "string" or text == "" then
        return y
    end
    local desc = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    desc:SetWidth(math.max(100, width - 32))
    desc:SetJustifyH("LEFT")
    if desc.SetWordWrap then
        desc:SetWordWrap(true)
    end
    desc:SetText(text)
    desc:SetTextColor(0.62, 0.62, 0.62)
    return y - 18
end

local function CreateOptionLabel(parent, x, y, text)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(text)
    return label
end

local function RefreshControls()
    local db = ns.GetDB()
    refreshingControls = true

    if showHUDCheck then
        SetChecked(showHUDCheck, db.showHUD)
    end
    if announceChecks.announceTeleport then
        SetChecked(announceChecks.announceTeleport, db.announceTeleport ~= false)
    end
    if announceChecks.announceRunGain then
        SetChecked(announceChecks.announceRunGain, db.announceRunGain ~= false)
    end
    if announceChecks.announceMemberJoin then
        SetChecked(announceChecks.announceMemberJoin, db.announceMemberJoin ~= false)
    end
    if announceDelaySlider then
        announceDelaySlider:SetValue(db.announceDelay or 5)
        SetSliderText(announceDelaySlider, string.format(L.ANNOUNCE_DELAY_SECONDS, math.floor((db.announceDelay or 5) + 0.5)))
    end
    for key, box in pairs(templateBoxes) do
        if box then
            box:SetText(ns.GetAnnounceTemplate(key) or L[key] or "")
        end
    end
    if detailCheck then
        SetChecked(detailCheck, db.enableMythicDetail ~= false)
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

    -- The canvas width drives the two-column grid; the content height is set
    -- once the controls are built so the scrollbar matches the real page.
    local contentWidth = 620
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(contentWidth, 100)
    scrollFrame:SetScrollChild(content)

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maximum = self:GetVerticalScrollRange() or 0
        local nextValue = current - (delta * 36)
        self:SetVerticalScroll(math.max(0, math.min(maximum, nextValue)))
    end)

    panel:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 then
            contentWidth = math.max(600, width - 44)
            content:SetWidth(contentWidth)
        end
    end)

    local function BuildSettingsControls()
        if controlsCreated then
            return
        end
        controlsCreated = true

    local width = contentWidth
    local columnX = math.floor(width / 2) + 6
    local y = -14

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    title:SetText(L.ADDON_TITLE)
    local version = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    version:SetPoint("TOPRIGHT", content, "TOPRIGHT", -16, y + 2)
    version:SetText("v" .. tostring(GetAddOnVersion()))
    version:SetTextColor(0.55, 0.55, 0.55)
    y = y - 32

    -- Group Finder HUD -------------------------------------------------------
    y = CreateSectionHeader(content, L.SETTINGS_SECTION_HUD or "Group Finder HUD", y, width)
    showHUDCheck = CreateCheckButton(content, 18, y, L.SETTINGS_SHOW_HUD, function(checked)
        ns.SetHUDShown(checked)
    end)
    y = y - 26
    y = CreateDescription(content, L.SETTINGS_SHOW_HUD_DESC, y, width)
    y = y - 12

    -- Displayed rows --------------------------------------------------------
    y = CreateSectionHeader(content, L.SETTINGS_VISIBLE_ROWS, y, width)
    y = CreateDescription(content, L.SETTINGS_VISIBLE_ROWS_DESC, y, width)
    y = y - 2
    local rowsTop = y
    for index, option in ipairs(ROW_OPTIONS) do
        local optionKey = option.key
        local optionLabel = option.label
        local column = index <= 6 and 0 or 1
        local rowIndex = column == 0 and index or index - 6
        local x = column == 0 and 18 or columnX
        local rowY = rowsTop - ((rowIndex - 1) * 26)
        local check = CreateCheckButton(content, x, rowY, L[optionLabel], function(checked)
            ns.SetRowVisible(optionKey, checked)
        end)
        rowChecks[optionKey] = check
    end
    y = rowsTop - (6 * 26) - 4

    -- Appearance ------------------------------------------------------------
    y = CreateSectionHeader(content, L.SETTINGS_SECTION_APPEARANCE or "Appearance", y, width)
    y = CreateDescription(content, L.SETTINGS_APPEARANCE_DESC, y, width)
    y = y - 2
    CreateOptionLabel(content, 18, y, L.SETTINGS_BORDER_STYLE)
    y = y - 24
    CreateBorderOption(content, 18, y, "transparent", L.SETTINGS_BORDER_TRANSPARENT)
    CreateBorderOption(content, 170, y, "gold", L.SETTINGS_BORDER_GOLD)
    CreateBorderOption(content, 300, y, "class", L.SETTINGS_BORDER_CLASS)
    y = y - 34

    CreateOptionLabel(content, 18, y, L.SETTINGS_BORDER_ALPHA)
    CreateOptionLabel(content, columnX, y, L.SETTINGS_BACKGROUND_ALPHA)
    y = y - 30
    borderAlphaSlider = CreateSlider(content, 22, y, 240, "0%", "100%", 0, 1, 0.05, function(slider, value)
        value = math.floor(value * 20 + 0.5) / 20
        SetSliderText(slider, string.format("%d%%", math.floor(value * 100 + 0.5)))
        if not refreshingControls then
            ns.SetHUDBorderAlpha(value)
            QueueHUDStyleApply()
        end
    end)

    backgroundAlphaSlider = CreateSlider(content, columnX + 4, y, 240, "0%", "100%", 0, 1, 0.05, function(slider, value)
        value = math.floor(value * 20 + 0.5) / 20
        SetSliderText(slider, string.format("%d%%", math.floor(value * 100 + 0.5)))
        if not refreshingControls then
            ns.SetHUDBackgroundAlpha(value)
            QueueHUDStyleApply()
        end
    end)
    y = y - 46

    -- Details window --------------------------------------------------------
    y = CreateSectionHeader(content, L.SETTINGS_DETAIL_GROUP, y, width)
    detailCheck = CreateCheckButton(content, 18, y, L.SETTINGS_ENABLE_DETAIL, function(checked)
        ns.SetDetailEnabled(checked)
        ns.ApplyDetailFeatureState()
    end)
    y = y - 34
    CreateOptionLabel(content, 18, y, L.SETTINGS_DETAIL_BORDER_ALPHA)
    CreateOptionLabel(content, columnX, y, L.SETTINGS_DETAIL_BACKGROUND_ALPHA)
    y = y - 30
    detailBorderAlphaSlider = CreateSlider(content, 22, y, 240, "0%", "100%", 0, 1, 0.05, function(slider, value)
        value = math.floor(value * 20 + 0.5) / 20
        SetSliderText(slider, string.format("%d%%", math.floor(value * 100 + 0.5)))
        if not refreshingControls then
            ns.SetDetailBorderAlpha(value)
            QueueDetailStyleApply()
        end
    end)

    detailBackgroundAlphaSlider = CreateSlider(content, columnX + 4, y, 240, "0%", "100%", 0, 1, 0.05, function(slider, value)
        value = math.floor(value * 20 + 0.5) / 20
        SetSliderText(slider, string.format("%d%%", math.floor(value * 100 + 0.5)))
        if not refreshingControls then
            ns.SetDetailBackgroundAlpha(value)
            QueueDetailStyleApply()
        end
    end)
    y = y - 46

    -- Announcements ---------------------------------------------------------
    y = CreateSectionHeader(content, L.SETTINGS_ANNOUNCE_TEXTS, y, width)
    y = CreateDescription(content, L.SETTINGS_ANNOUNCE_DESC, y, width)

    -- One cursor drives the whole section: every control is placed below the
    -- previous one, so a longer label or a wrapped line can never overlap.
    local rowY = y - 2
    local function AddTemplateRow(fieldKey, labelKey)
        local fieldLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        fieldLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 44, rowY)
        fieldLabel:SetText(L[labelKey])
        rowY = rowY - 20
        local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
        box:SetSize(520, 26)
        box:SetPoint("TOPLEFT", content, "TOPLEFT", 44, rowY)
        box:SetAutoFocus(false)
        box:SetScript("OnEnterPressed", function(self)
            ns.SetAnnounceTemplate(fieldKey, self:GetText())
            self:SetText(ns.GetAnnounceTemplate(fieldKey) or L[fieldKey] or "")
            self:ClearFocus()
        end)
        box:SetScript("OnEscapePressed", function(self)
            self:SetText(ns.GetAnnounceTemplate(fieldKey) or L[fieldKey] or "")
            self:ClearFocus()
        end)
        box:SetScript("OnEditFocusLost", function(self)
            ns.SetAnnounceTemplate(fieldKey, self:GetText())
        end)
        templateBoxes[fieldKey] = box
        rowY = rowY - 36
    end

    -- Each switch sits directly above the templates it turns on and off.
    local function AddAnnouncement(titleKey, checkKey, setterName, templates)
        announceChecks[checkKey] = CreateCheckButton(content, 18, rowY, L[titleKey], function(checked)
            ns[setterName](checked)
        end)
        rowY = rowY - 32
        for _, field in ipairs(templates) do
            AddTemplateRow(field.key, field.label)
        end
        rowY = rowY - 14
    end

    AddAnnouncement("SETTINGS_ANNOUNCE_TELEPORT", "announceTeleport", "SetTeleportAnnouncementEnabled", {
        { key = "TELEPORT_ANNOUNCEMENT_FORMAT", label = "SETTINGS_TEXT_TELEPORT" },
    })

    AddAnnouncement("SETTINGS_ANNOUNCE_RUN_GAIN", "announceRunGain", "SetRunGainAnnouncementEnabled", {
        { key = "RUN_GAIN_LINE_GAIN", label = "SETTINGS_TEXT_RUN_LINE_GAIN" },
        { key = "RUN_GAIN_LINE_NO_GAIN", label = "SETTINGS_TEXT_RUN_LINE_NO_GAIN" },
        { key = "RUN_GAIN_LINE_TODAY", label = "SETTINGS_TEXT_RUN_LINE_TODAY" },
        { key = "RUN_GAIN_LINE_CURRENT", label = "SETTINGS_TEXT_RUN_LINE_CURRENT" },
        { key = "RUN_GAIN_LINE_AD", label = "SETTINGS_TEXT_RUN_LINE_AD" },
    })

    -- The delay belongs to the run announcement it delays.
    local announceDelayLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    announceDelayLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 44, rowY)
    announceDelayLabel:SetText(L.SETTINGS_ANNOUNCE_DELAY)
    rowY = rowY - 22

    announceDelaySlider = CreateSlider(content, 48, rowY, 240, "0", "30", 0, 30, 1, function(slider, value)
        value = math.floor(value + 0.5)
        SetSliderText(slider, string.format(L.ANNOUNCE_DELAY_SECONDS, value))
        if not refreshingControls then
            ns.SetRunAnnounceDelay(value)
        end
    end)
    rowY = rowY - 54

    AddAnnouncement("SETTINGS_ANNOUNCE_MEMBER_JOIN", "announceMemberJoin", "SetMemberWelcomeEnabled", {
        { key = "MEMBER_WELCOME_FORMAT", label = "SETTINGS_TEXT_WELCOME" },
        { key = "MEMBER_WELCOME_AGAIN_FORMAT", label = "SETTINGS_TEXT_WELCOME_AGAIN" },
    })

    -- The placeholder list comes last: it wraps to as many lines as the client
    -- needs, so it is placed where nothing follows it but the reset button.
    local hintText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hintText:SetPoint("TOPLEFT", content, "TOPLEFT", 18, rowY)
    hintText:SetWidth(math.max(480, width - 40))
    hintText:SetJustifyH("LEFT")
    hintText:SetText(L.SETTINGS_TEXT_HINT)
    rowY = rowY - 96

    local resetTextsButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetTextsButton:SetSize(160, 24)
    resetTextsButton:SetPoint("TOPLEFT", content, "TOPLEFT", 18, rowY)
    resetTextsButton:SetText(L.SETTINGS_TEXT_RESET)
    resetTextsButton:SetScript("OnClick", function()
        ns.ResetAnnounceTemplates()
        RefreshControls()
        PrintAddonMessage(L.SETTINGS_TEXT_RESET_DONE)
    end)
    rowY = rowY - 40

    content:SetHeight(math.max(620, -rowY))

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
        PrintAddonMessage(L.SLASH_HELP)
    end
end

SLASH_QFXMYTHICRANKHUDGLOBAL1 = "/myrank"
SlashCmdList.QFXMYTHICRANKHUDGLOBAL = function(message)
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
    elseif command == "debug" then
        PrintDebugInfo()
    elseif command == "" then
        ns.OpenSettings()
    else
        PrintAddonMessage(L.SLASH_HELP)
    end
end

-- The regional build shipped as /qfxrank before both variants shared one code
-- base; keep the alias working there (and harmlessly elsewhere).
SLASH_QFXMYTHICRANKHUD1 = "/qfxrank"
SlashCmdList.QFXMYTHICRANKHUD = SlashCmdList.QFXMYTHICRANKHUDGLOBAL

function ns.InitializeSettings()
    CreateSettingsPanel()
end
