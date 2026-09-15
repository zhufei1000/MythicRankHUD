-- EUI.lua tests: the EllesmereUI skin bridge queues frames until the skin
-- facade arrives, paints them when it does, and applies later frames
-- immediately. Without EllesmereUI every call stays a silent no-op.

local function NewFrame()
    local frame = {}
    function frame:SetBackdrop(value)
        self.backdrop = value
        self.backdropSets = (self.backdropSets or 0) + 1
    end
    return frame
end

local function LoadBridge(eui, addonName)
    _G.EllesmereUI = eui
    local ns = {}
    assert(loadfile(arg and arg[1] or "EUI.lua"))(addonName or "MythicRankHUD", ns)
    return ns
end

local function FindCall(calls, name, frame)
    for _, call in ipairs(calls) do
        if call[1] == name and call[2] == frame then return call end
    end
end

-- ---------------------------------------------------------------------------
-- Without EllesmereUI nothing is painted and no callback ever fires.
-- ---------------------------------------------------------------------------
local ns = LoadBridge(nil)
assert(ns.IsEUISkinActive() == false, "skin reported active without EllesmereUI")
assert(ns.GetEUISkin() == nil, "a skin facade exists without EllesmereUI")

local plainFrame = NewFrame()
ns.RegisterEUISkin(plainFrame, "panel")
ns.RegisterEUISkin(plainFrame, "shell")
assert(plainFrame.backdropSets == nil, "a frame was painted without EllesmereUI")

local plainReady = false
ns.RegisterEUISkinReady(function() plainReady = true end)
local plainLooks = false
ns.RegisterEUISkinLooks(function() plainLooks = true end)
assert(plainReady == false, "the ready callback fired without EllesmereUI")
assert(plainLooks == false, "the looks callback fired without EllesmereUI")
ns.ApplyEUISkinBarFill({})

-- ---------------------------------------------------------------------------
-- With EllesmereUI: registration is queued, dispatch paints every entry once,
-- and late frames are painted as they register.
-- ---------------------------------------------------------------------------
local registeredName, registeredFn
local eui = {
    RegisterSkin = function(name, fn)
        registeredName, registeredFn = name, fn
    end,
}
ns = LoadBridge(eui)
assert(registeredName == "MythicRankHUD", "the skin was not registered under the addon name")
assert(type(registeredFn) == "function", "no skin callback was registered")
assert(ns.IsEUISkinActive() == false, "skin reported active before the facade arrived")

local calls = {}
local looksFns = {}
local S = {
    IsEnabled = function() return true end,
    Panel = function(frame, opts) calls[#calls + 1] = { "Panel", frame, opts } end,
    Shell = function(frame, opts) calls[#calls + 1] = { "Shell", frame, opts } end,
    CloseButton = function(frame) calls[#calls + 1] = { "CloseButton", frame } end,
    Dropdown = function(frame) calls[#calls + 1] = { "Dropdown", frame } end,
    ApplyBarFill = function(bar) calls[#calls + 1] = { "ApplyBarFill", bar } end,
    GetAccentColor = function() return 0.1, 0.2, 0.3 end,
    OnLooksChanged = function(fn) looksFns[#looksFns + 1] = fn end,
}

local panelFrame = NewFrame()
local shellFrame = NewFrame()
local closeFrame = NewFrame()
ns.RegisterEUISkin(panelFrame, "panel")
ns.RegisterEUISkin(shellFrame, "shell")
ns.RegisterEUISkin(closeFrame, "close")

local readyCalls, readyFacade = 0, nil
ns.RegisterEUISkinReady(function(facade)
    readyCalls = readyCalls + 1
    readyFacade = facade
end)
local preLooksRuns = 0
ns.RegisterEUISkinLooks(function() preLooksRuns = preLooksRuns + 1 end)
assert(#calls == 0, "frames were painted before the facade arrived")

registeredFn(S)

assert(ns.IsEUISkinActive() == true, "skin reported inactive after dispatch")
assert(ns.GetEUISkin() == S, "the facade was not stored")
assert(readyCalls == 1 and readyFacade == S, "the ready callback did not run at dispatch")
assert(#looksFns == 1, "the queued looks callback was not registered at dispatch")

assert(panelFrame.backdrop == nil and panelFrame.backdropSets == 1,
    "the panel frame kept the addon backdrop under the EUI skin")
local panelCall = FindCall(calls, "Panel", panelFrame)
assert(panelCall, "the queued panel frame was not painted at dispatch")

assert(shellFrame.backdrop == nil and shellFrame.backdropSets == 1,
    "the shell frame kept the addon backdrop under the EUI skin")
assert(FindCall(calls, "Shell", shellFrame), "the queued shell frame was not painted at dispatch")

assert(FindCall(calls, "CloseButton", closeFrame), "the queued close button was not painted")

looksFns[1]()
assert(preLooksRuns == 1, "the looks callback is not callable")

-- Late frames (pooled rows, a detail window opened later) paint immediately.
local dropdownFrame = NewFrame()
ns.RegisterEUISkin(dropdownFrame, "dropdown")
assert(FindCall(calls, "Dropdown", dropdownFrame), "a late dropdown was not skinned immediately")

local bar = NewFrame()
ns.ApplyEUISkinBarFill(bar)
assert(FindCall(calls, "ApplyBarFill", bar), "the house bar fill was not applied")

local postLooks = 0
ns.RegisterEUISkinLooks(function() postLooks = postLooks + 1 end)
assert(#looksFns == 2, "a looks callback registered after dispatch was not forwarded")
looksFns[2]()
assert(postLooks == 1, "the post-dispatch looks callback is not callable")

local immediateReady = false
ns.RegisterEUISkinReady(function(facade)
    immediateReady = facade == S
end)
assert(immediateReady, "a ready callback registered after dispatch did not run immediately")

-- Re-registering the same frame stays safe (style-refresh path).
ns.RegisterEUISkin(panelFrame, "panel")
assert(panelFrame.backdropSets == 2, "re-registering did not re-run the idempotent primitive")

-- The regional build registers under its own folder name.
local cnName
LoadBridge({ RegisterSkin = function(name) cnName = name end }, "QFXMythicRankHUD")
assert(cnName == "QFXMythicRankHUD", "the regional build registered under the wrong name")

print("EUISkin_test: OK")
