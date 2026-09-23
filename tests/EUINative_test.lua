-- EUI.lua + EUINative.lua tests: on the stock whole-UI looks ("blizzard" /
-- "classic") the bridge paints the native shell and never hands the frame to
-- the facade; on the house look everything stays with EUI. Without
-- EllesmereUI the whole path stays a silent no-op.

local function NewFrame()
    local frame = {}
    function frame:SetBackdrop(value)
        self.backdrop = value
        self.backdropSets = (self.backdropSets or 0) + 1
    end
    function frame:SetBackdropColor(...) self.backdropColor = { ... } end
    function frame:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
    return frame
end

local function Load(look, eui)
    _G.EllesmereUI = eui
    _G.EllesmereUIDB = look and { windowSkinStyleSlots = { active = look } } or nil
    local ns = {}
    assert(loadfile(arg and arg[1] or "EUI.lua"))("MythicRankHUD", ns)
    assert(loadfile(arg and arg[2] or "EUINative.lua"))("MythicRankHUD", ns)
    return ns
end

-- ---------------------------------------------------------------------------
-- Without EllesmereUI nothing is painted and no look is reported.
-- ---------------------------------------------------------------------------
local ns = Load(nil, nil)
assert(ns.GetEUIGlobalStyle() == nil, "a look was reported without EllesmereUI")
assert(ns.IsEUINativeActive() == false, "the native shell reported active without EllesmereUI")
local bare = NewFrame()
ns.RegisterEUISkin(bare, "shell")
assert(bare.backdropSets == nil, "a frame was painted without EllesmereUI")

-- ---------------------------------------------------------------------------
-- A database from before the Style page (no slots) reports the house look.
-- ---------------------------------------------------------------------------
ns = Load(nil, { RegisterSkin = function() end })
assert(ns.GetEUIGlobalStyle() == "eui", "a missing slots table did not fall back to the house look")
assert(ns.IsEUINativeActive() == false, "the native shell reported active on the house look")
assert(ns.IsEUISkinActive() == false, "the facade reported active before dispatch")

-- ---------------------------------------------------------------------------
-- Blizzard Style: shell wears the stock dialog, panels the tooltip box, and
-- the facade is never called -- not even when it arrives later.
-- ---------------------------------------------------------------------------
local eui
eui = { RegisterSkin = function(_, fn) eui._fn = fn end }
ns = Load("blizzard", eui)
assert(ns.GetEUIGlobalStyle() == "blizzard", "the blizzard look was not reported")
assert(ns.IsEUINativeActive() == true, "the native shell did not report active")
assert(ns.IsEUISkinActive() == false, "the facade reported active on a stock look")

local shellFrame = NewFrame()
local panelFrame = NewFrame()
local closeFrame = NewFrame()
ns.RegisterEUISkin(shellFrame, "shell")
ns.RegisterEUISkin(panelFrame, "panel")
ns.RegisterEUISkin(closeFrame, "close")
assert(shellFrame.backdrop and shellFrame.backdrop.edgeFile == "Interface\\DialogFrame\\UI-DialogBox-Border",
    "the shell did not wear the stock dialog border")
assert(shellFrame.backdrop.bgFile == "Interface\\DialogFrame\\UI-DialogBox-Background",
    "the shell did not wear the stock dialog background")
assert(panelFrame.backdrop and panelFrame.backdrop.edgeFile == "Interface\\Tooltips\\UI-Tooltip-Border",
    "the panel did not wear the tooltip border")
assert(closeFrame.backdropSets == nil, "the close button was painted a backdrop")
assert(shellFrame.backdropColor and shellFrame.backdropColor[4] == 1,
    "the shell backdrop was not tinted opaque")
assert(shellFrame.backdropColor[1] < 0.2 and shellFrame.backdropColor[2] < 0.2
    and shellFrame.backdropColor[3] < 0.2, "the shell backdrop was not tinted dark")
local tintR, tintG, tintB = ns.GetNativeShellBackdropColor()
assert(tintR and tintR < 0.2 and tintG < 0.2 and tintB < 0.2,
    "the shared backdrop fill is not dark")

local facadeCalls = {}
if eui._fn then
    eui._fn({
        IsEnabled = function() return true end,
        Shell = function(frame) facadeCalls[#facadeCalls + 1] = { "Shell", frame } end,
        Panel = function(frame) facadeCalls[#facadeCalls + 1] = { "Panel", frame } end,
        CloseButton = function(frame) facadeCalls[#facadeCalls + 1] = { "CloseButton", frame } end,
    })
    assert(#facadeCalls == 0, "the facade painted a frame on a stock look")
    assert(shellFrame.backdropSets == 1, "the shell was rebuilt when the facade arrived")
    assert(closeFrame.backdropSets == nil, "the close button was painted when the facade arrived")
    assert(ns.IsEUISkinActive() == false, "the facade reported active after dispatch on a stock look")
else
    error("the bridge did not register with EllesmereUI")
end

-- Re-registering with a new kind re-sets the backdrop once (panel -> shell).
local kindFrame = NewFrame()
ns.RegisterEUISkin(kindFrame, "panel")
assert(kindFrame.backdrop.edgeFile == "Interface\\Tooltips\\UI-Tooltip-Border",
    "the panel did not wear the tooltip border")
ns.RegisterEUISkin(kindFrame, "shell")
assert(kindFrame.backdrop.edgeFile == "Interface\\DialogFrame\\UI-DialogBox-Border",
    "a kind change did not repaint the native shell")
assert(kindFrame.backdropSets == 2, "a kind change rebuilt more than once")

-- ---------------------------------------------------------------------------
-- Classic WoW UI: the vanilla rock window.
-- ---------------------------------------------------------------------------
ns = Load("classic", { RegisterSkin = function() end })
local rockFrame = NewFrame()
ns.RegisterEUISkin(rockFrame, "shell")
assert(rockFrame.backdrop and rockFrame.backdrop.bgFile == "Interface\\FrameGeneral\\UI-Background-Rock",
    "the classic shell did not wear the vanilla rock background")
assert(rockFrame.backdrop.edgeFile == "Interface\\Tooltips\\UI-Tooltip-Border",
    "the classic shell did not wear the tooltip border")

-- ---------------------------------------------------------------------------
-- A settings pick wins over the EUI look.
-- ---------------------------------------------------------------------------
ns = Load("eui", { RegisterSkin = function() end })
ns.GetAppearanceMode = function() return "blizzard" end
assert(ns.GetWindowShellStyle() == "blizzard", "the settings pick did not override the EUI look")
local pinnedFrame = NewFrame()
ns.RegisterEUISkin(pinnedFrame, "shell")
assert(pinnedFrame.backdrop and pinnedFrame.backdrop.edgeFile == "Interface\\DialogFrame\\UI-DialogBox-Border",
    "the pinned blizzard look did not paint the native shell")

ns.GetAppearanceMode = function() return "addon" end
assert(ns.GetWindowShellStyle() == "addon", "the addon pick was not reported")
local addonFrame = NewFrame()
ns.RegisterEUISkin(addonFrame, "shell")
assert(addonFrame.backdropSets == nil, "the addon look painted a shell")
assert(ns.IsEUISkinActive() == false, "the addon look reported the EUI theme active")

ns.GetAppearanceMode = function() return "classic" end
assert(ns.GetWindowShellStyle() == "classic", "the classic pick was not reported")

ns.GetAppearanceMode = function() return "auto" end
assert(ns.GetWindowShellStyle() == "eui", "auto did not fall back to the EUI look")

-- ---------------------------------------------------------------------------
-- House look: everything stays with the facade.
-- ---------------------------------------------------------------------------
local houseEui
houseEui = { RegisterSkin = function(_, fn) houseEui._fn = fn end }
ns = Load("eui", houseEui)
local houseFrame = NewFrame()
ns.RegisterEUISkin(houseFrame, "shell")
assert(houseFrame.backdropSets == nil, "a frame was painted before the facade arrived")
local houseCalls = {}
houseEui._fn({
    IsEnabled = function() return true end,
    Shell = function(frame) houseCalls[#houseCalls + 1] = frame end,
})
assert(houseCalls[1] == houseFrame, "the facade did not paint the frame on the house look")
assert(houseFrame.backdropSets == 1, "the house look did not clear the addon backdrop")
assert(ns.IsEUINativeActive() == false, "the native shell reported active on the house look")
assert(ns.IsEUISkinActive() == true, "the facade did not report active on the house look")

print("EUINative_test: OK")
