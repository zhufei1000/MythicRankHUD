local modulePath = arg and arg[1] or "MythicDetailResources.lua"

local namespace = {}
assert(loadfile("Util.lua"))("MythicRankHUD", namespace)

C_CurrencyInfo = {
    GetCurrencyInfo = function(currencyID)
        return {
            name = "Currency " .. tostring(currencyID),
            iconFileID = 100000 + currencyID,
            discovered = true,
            quantity = currencyID == 3418 and 60 or 10,
            maxQuantity = 100,
            maxWeeklyQuantity = 0,
            canEarnPerWeek = false,
            isAccountWide = false,
            isAccountTransferable = false,
        }
    end,
}

assert(loadfile(modulePath))("MythicRankHUD", namespace)
local resources = namespace.MythicDetailResources

local initial = resources.GetAll()
local voidCoreIndex = resources.GetIndexForKey("voidCore")
assert(initial[voidCoreIndex].quantity == 60, "baseline currency quantity is incorrect")

local refreshed = resources.GetAll(initial, { [3418] = 3 })
assert(refreshed[voidCoreIndex].quantity == 3,
    "event quantity did not override a stale GetCurrencyInfo result")

local one = resources.RefreshOne(3418, refreshed[voidCoreIndex], 2)
assert(one.quantity == 2, "single-resource refresh ignored the event quantity")

local fallback = resources.RefreshOne(3418, one, nil)
assert(fallback.quantity == 60, "missing event quantity did not fall back to GetCurrencyInfo")

print("MythicDetailResources_test: OK")
