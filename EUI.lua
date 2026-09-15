local ADDON_NAME, ns = ...

-- EllesmereUI third-party skin bridge (developer guide: SKINNING_API.md in the
-- EllesmereUI addon). EUI calls the registered function once per session with a
-- skinning facade S; every primitive is idempotent and follows the user's live
-- theme, so frames created later are handed over as they appear. When
-- EllesmereUI is missing or its skinning is off, nothing here runs and the
-- addon keeps its own visuals.

local EUI = _G.EllesmereUI
local skin

-- frame -> { kind = "panel" | "shell" | "close" | "dropdown" }
local entries = setmetatable({}, { __mode = "k" })
local looksCallbacks = {}
local readyCallbacks = {}

local function ApplyEntry(entry)
    if not skin then return end
    local frame = entry.frame
    local kind = entry.kind
    if kind == "panel" or kind == "shell" then
        -- EUI paints its own backdrop; drop the addon's SetBackdrop art first
        -- so it cannot show through the house panel.
        if frame.SetBackdrop then frame:SetBackdrop(nil) end
        if kind == "shell" then
            if skin.Shell then skin.Shell(frame) end
        elseif skin.Panel then
            skin.Panel(frame)
        end
    elseif kind == "close" then
        if skin.CloseButton then skin.CloseButton(frame) end
    elseif kind == "dropdown" then
        if skin.Dropdown then skin.Dropdown(frame) end
    end
end

local function ApplyAll()
    for _, entry in pairs(entries) do
        ApplyEntry(entry)
    end
end

function ns.IsEUISkinActive()
    return skin ~= nil and (skin.IsEnabled == nil or skin.IsEnabled())
end

function ns.GetEUISkin()
    return skin
end

-- Register (or re-register) a frame for EUI styling. Safe to call before EUI
-- has dispatched the facade: the entry is queued and painted as soon as the
-- facade arrives. Re-registering the same frame is idempotent (EUI primitives
-- bail after one lookup), so style-refresh paths may call this freely.
function ns.RegisterEUISkin(frame, kind)
    if not frame or not kind then return end
    local entry = entries[frame]
    if not entry then
        entry = { frame = frame }
        entries[frame] = entry
    end
    entry.kind = kind
    ApplyEntry(entry)
end

-- EUI's house bar fill for a StatusBar (kept in sync with live color changes).
function ns.ApplyEUISkinBarFill(bar)
    if skin and bar and skin.ApplyBarFill then
        skin.ApplyBarFill(bar)
    end
end

-- Run fn on facade arrival and whenever the user's suite-wide looks change
-- (accent color, bar fill, ...). Never called while EUI skinning is off.
function ns.RegisterEUISkinLooks(fn)
    if type(fn) ~= "function" then return end
    looksCallbacks[#looksCallbacks + 1] = fn
    if skin and skin.OnLooksChanged then
        skin.OnLooksChanged(fn)
    end
end

function ns.RegisterEUISkinReady(fn)
    if type(fn) ~= "function" then return end
    if skin then
        fn(skin)
        return
    end
    readyCallbacks[#readyCallbacks + 1] = fn
end

local function OnSkinReady(S)
    skin = S
    ApplyAll()
    for index = 1, #looksCallbacks do
        if S.OnLooksChanged then S.OnLooksChanged(looksCallbacks[index]) end
    end
    for index = 1, #readyCallbacks do
        readyCallbacks[index](S)
    end
end

if EUI and type(EUI.RegisterSkin) == "function" then
    EUI.RegisterSkin(ADDON_NAME, OnSkinReady)
end
