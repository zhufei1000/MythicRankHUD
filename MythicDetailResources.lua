local _, ns = ...
local L = ns.L
local Util = ns.Util

local Resources = {}
ns.MythicDetailResources = Resources

-- Midnight Season 2 Mistcrests use the character-currency IDs 3442-3446.
-- The similarly named IDs 3437-3441 are non-collectible duplicates with a
-- maximum quantity of zero and must not be used for the displayed balance.
-- Icons and localized names are read from C_CurrencyInfo at runtime.
-- Season 2 keeps Dawnlight Manaflux 3378 replaced by Venomblight Manaflux
-- 3465, while the live collectible Voidcore stays on the Season 1 entry 3418
-- (confirmed on the live client). IDs 3511 and 3513 are unused duplicates in
-- the client data and must not be used for the displayed balance.
local RESOURCE_ORDER = {
    "mythic",
    "heroic",
    "champion",
    "veteran",
    "adventurer",
    "voidCore",
    "manaflux",
}

local RESOURCE_DEFINITIONS = {
    mythic = { resourceType = "currency", id = 3446 },
    heroic = { resourceType = "currency", id = 3445 },
    voidCore = { resourceType = "currency", id = 3418 },
    champion = { resourceType = "currency", id = 3444 },
    veteran = { resourceType = "currency", id = 3443 },
    manaflux = { resourceType = "currency", id = 3465 },
    adventurer = { resourceType = "currency", id = 3442 },
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

local function GetCurrencyResource(key, definition, resource, quantityOverride)
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
    local normalizedOverride = Resources.NormalizeResourceQuantity(quantityOverride)
    if normalizedOverride ~= nil then
        -- CURRENCY_DISPLAY_UPDATE includes the authoritative post-change
        -- quantity. Prefer it because GetCurrencyInfo can briefly return the
        -- pre-spend value while the synchronous event is being handled.
        resource.quantity = normalizedOverride
    end
    return resource
end

function Resources.GetAll(result, quantityOverrides)
    result = result or {}
    for index, key in ipairs(RESOURCE_ORDER) do
        local definition = RESOURCE_DEFINITIONS[key]
        local quantityOverride = type(quantityOverrides) == "table" and quantityOverrides[definition.id] or nil
        result[index] = GetCurrencyResource(key, definition, result[index], quantityOverride)
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

function Resources.RefreshOne(currencyID, resource, quantityOverride)
    local key = Resources.GetKeyForCurrencyID(currencyID)
    if not key then
        return nil
    end
    return GetCurrencyResource(key, RESOURCE_DEFINITIONS[key], resource, quantityOverride)
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
