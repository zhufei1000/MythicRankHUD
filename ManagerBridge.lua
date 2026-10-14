local ADDON_NAME, ns = ...
if ADDON_NAME ~= "QFXMythicRankHUD" then return end
local target = ns
if not target then return end
_G["QFXMythicRankHUDManagerAPI"] = target
local function OpenManager(tab)
    local api = rawget(_G, "QFXAddonManagerAPI")
    if not api or type(api.OpenAddonSettings) ~= "function" then return false end
    return api.OpenAddonSettings("QFXMythicRankHUD", tab)
end
target.TryOpenManager = OpenManager
local open = target.OpenSettings
target.OpenSettings = function(...)
    if OpenManager() then return true end
    return open(...)
end
