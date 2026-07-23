local _, ns = ...
local L = ns.L
local Util = ns.Util

local Resources = {}
ns.MythicDetailResources = Resources

-- Verified in the live WoW 12.0.7 client on 2026-07-16 with
-- C_CurrencyInfo.GetCurrencyInfo. All six entries are character currencies.
-- Verified iconFileIDs: 3347=7639523, 3345=7639521, 3418=7658128,
-- 3343=7639519, 3341=7639525, 3378=4622294. Icons are still read from
-- the API at runtime so client-side asset changes do not require an update.
-- The inactive duplicate currency 3513 is intentionally not used: the live
-- client returned discovered=false and quantity=0 while currency 3418 is the
-- discovered entry shown in Blizzard's currency panel.
local RESOURCE_ORDER = {
    "mythic",
    "heroic",
    "voidCore",
    "champion",
    "veteran",
    "manaSolvent",
}

local RESOURCE_DEFINITIONS = {
    mythic = { resourceType = "currency", id = 3347 },
    heroic = { resourceType = "currency", id = 3345 },
    voidCore = { resourceType = "currency", id = 3418 },
    champion = { resourceType = "currency", id = 3343 },
    veteran = { resourceType = "currency", id = 3341 },
    manaSolvent = { resourceType = "currency", id = 3378 },
}

local TRACKED_CURRENCIES = {}
local RESOURCE_INDEX_BY_KEY = {}
for index, key in ipairs(RESOURCE_ORDER) do
    TRACKED_CURRENCIES[RESOURCE_DEFINITIONS[key].id] = key
    RESOURCE_INDEX_BY_KEY[key] = index
end

local IsAccessibleValue = Util.IsAccessible
local SafeTable = Util.SafeTable
local SafeString = Util.SafeString
local SafeNumber = Util.SafeNumber
local SafeBoolean = Util.SafeBoolean

function Resources.NormalizeResourceQuantity(value)
    if not IsAccessibleValue(value) then
        return nil
    end

    local valueType = type(value)
    local numberValue
    if valueType == "number" then
        numberValue = value
    elseif valueType == "string" then
        local trimmed = value:match("^%s*(.-)%s*$")
        if not trimmed or trimmed == "" or trimmed == "-" then
            return nil
        end
        local normalized = trimmed:gsub("[,%s']", "")
        numberValue = tonumber(normalized)
    else
        return nil
    end

    if type(numberValue) ~= "number"
        or numberValue ~= numberValue
        or numberValue == math.huge
        or numberValue == -math.huge
        or numberValue < 0
    then
        return nil
    end
    return math.floor(numberValue)
end

local function GetCurrencyResource(key, definition, resource)
    resource = resource or {}
    Util.WipeArray(resource)
    resource.key = key
    resource.resourceType = definition.resourceType
    resource.id = definition.id
    resource.tooltipType = "currency"
    if not C_CurrencyInfo or type(C_CurrencyInfo.GetCurrencyInfo) ~= "function" then
        return resource
    end

    local info = SafeTable(C_CurrencyInfo.GetCurrencyInfo(definition.id))
    if not info then
        return resource
    end

    resource.name = SafeString(info.name)
    resource.icon = SafeNumber(info.iconFileID)
    resource.discovered = SafeBoolean(info.discovered)
    resource.maxQuantity = Resources.NormalizeResourceQuantity(info.maxQuantity)
    resource.maxWeeklyQuantity = Resources.NormalizeResourceQuantity(info.maxWeeklyQuantity)
    resource.canEarnPerWeek = SafeBoolean(info.canEarnPerWeek)
    resource.isAccountWide = SafeBoolean(info.isAccountWide)
    resource.isAccountTransferable = SafeBoolean(info.isAccountTransferable)
    if resource.discovered == true then
        resource.quantity = Resources.NormalizeResourceQuantity(info.quantity)
    end
    return resource
end

function Resources.GetAll(result)
    result = result or {}
    for index, key in ipairs(RESOURCE_ORDER) do
        result[index] = GetCurrencyResource(key, RESOURCE_DEFINITIONS[key], result[index])
    end
    for index = #RESOURCE_ORDER + 1, #result do
        result[index] = nil
    end
    return result
end

function Resources.GetKeyForCurrencyID(currencyID)
    local safeID = SafeNumber(currencyID)
    if not safeID then
        return nil
    end
    return TRACKED_CURRENCIES[safeID]
end

function Resources.GetIndexForKey(key)
    return RESOURCE_INDEX_BY_KEY[key]
end

function Resources.RefreshOne(currencyID, resource)
    local key = Resources.GetKeyForCurrencyID(currencyID)
    if not key then
        return nil
    end
    return GetCurrencyResource(key, RESOURCE_DEFINITIONS[key], resource)
end

function Resources.IsTrackedCurrencyID(currencyID)
    if not IsAccessibleValue(currencyID) then
        return true
    end
    local safeID = SafeNumber(currencyID)
    if not safeID then
        return false
    end
    return TRACKED_CURRENCIES[safeID] ~= nil
end

function Resources.ShowTooltip(owner, resource)
    if not owner or type(resource) ~= "table" or not GameTooltip then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if resource.tooltipType == "currency" and type(GameTooltip.SetCurrencyByID) == "function" then
        GameTooltip:SetCurrencyByID(resource.id)
        GameTooltip:Show()
        return
    end

    GameTooltip:SetText(resource.name or L.DETAIL_RESOURCE_UNAVAILABLE, 1, 0.82, 0)
    if resource.quantity ~= nil then
        GameTooltip:AddLine(string.format(L.DETAIL_RESOURCE_QUANTITY, resource.quantity), 1, 1, 1)
    else
        GameTooltip:AddLine(L.DETAIL_RESOURCE_UNAVAILABLE, 0.65, 0.65, 0.65)
    end
    if resource.maxQuantity and resource.maxQuantity > 0 then
        GameTooltip:AddLine(string.format(L.DETAIL_RESOURCE_MAXIMUM, resource.maxQuantity), 0.75, 0.75, 0.75)
    end
    GameTooltip:Show()
end

Resources.RESOURCE_ORDER = RESOURCE_ORDER
Resources.RESOURCE_DEFINITIONS = RESOURCE_DEFINITIONS
Resources.IsAccessibleValue = IsAccessibleValue
