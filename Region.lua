local _, ns = ...

local REGIONS = {
    { key = "us", label = "US", addon = "QFXMythicRankData_US" },
    { key = "eu", label = "EU", addon = "QFXMythicRankData_EU" },
    { key = "kr", label = "KR", addon = "QFXMythicRankData_KR" },
    { key = "tw", label = "TW", addon = "QFXMythicRankData_TW" },
    { key = "cn", label = "CN", addon = "QFXMythicRankData_CN" },
}

local REGION_BY_KEY = {}
for _, definition in ipairs(REGIONS) do
    REGION_BY_KEY[definition.key] = definition
end

ns.REGIONS = REGIONS

-- Current-season fallback names keep the international UI in English even
-- when the regional data pack is temporarily unavailable. The data pack's
-- season dungeon metadata remains the primary source so future seasons do not
-- require a HUD update merely to learn new abbreviations.
local ENGLISH_DUNGEON_FALLBACKS = {
    [249] = { name = "Kings' Rest", shortName = "KR" },
    [250] = { name = "Temple of Sethraliss", shortName = "TOS" },
    [399] = { name = "Ruby Life Pools", shortName = "RLP" },
    [584] = { name = "The Blinding Vale", shortName = "BV" },
    [585] = { name = "Voidscar Arena", shortName = "VSA" },
    [586] = { name = "Den of Nalorakk", shortName = "DON" },
    [587] = { name = "Murder Row", shortName = "MR" },
    [588] = { name = "Altar of Fangs", shortName = "AOF" },
}

function ns.GetFallbackEnglishDungeonInfo(mapID)
    local info = ENGLISH_DUNGEON_FALLBACKS[tonumber(mapID)]
    return info and info.name or nil, info and info.shortName or nil
end

local function GetAPI()
    local API = _G.QFXMythicRankData
    return type(API) == "table" and API or nil
end

function ns.IsRegionLoaded(region)
    if not REGION_BY_KEY[region] then
        return false
    end
    local API = GetAPI()
    if not API or type(API.GetMetadata) ~= "function" then
        return false
    end
    local ok, metadata = pcall(API.GetMetadata, API, region)
    return ok and type(metadata) == "table"
end

function ns.GetLoadedRegions()
    local loaded = {}
    for _, definition in ipairs(REGIONS) do
        if ns.IsRegionLoaded(definition.key) then
            loaded[#loaded + 1] = definition.key
        end
    end
    return loaded
end

function ns.GetSelectedRegion()
    local db = ns.GetDB and ns.GetDB() or nil
    local region = db and db.selectedRegion or nil
    return ns.IsRegionLoaded(region) and region or nil
end

function ns.GetSelectedRegionLabel()
    local definition = REGION_BY_KEY[ns.GetSelectedRegion()]
    return definition and definition.label or nil
end

function ns.GetRegionLabel(region)
    local definition = REGION_BY_KEY[region]
    return definition and definition.label or nil
end

function ns.ResolveSelectedRegion()
    local db = ns.GetDB and ns.GetDB() or nil
    if not db then
        return nil
    end

    if ns.IsRegionLoaded(db.selectedRegion) then
        return db.selectedRegion
    end

    local API = GetAPI()
    local currentRegion
    if API and type(API.GetCurrentRegion) == "function" then
        local ok, value = pcall(API.GetCurrentRegion, API)
        if ok and type(value) == "string" then
            currentRegion = value:lower()
        end
    end
    if ns.IsRegionLoaded(currentRegion) then
        db.selectedRegion = currentRegion
        return currentRegion
    end

    local loaded = ns.GetLoadedRegions()
    db.selectedRegion = loaded[1]
    return db.selectedRegion
end

function ns.SetSelectedRegion(region)
    if not ns.IsRegionLoaded(region) then
        return false
    end
    local db = ns.GetDB and ns.GetDB() or nil
    if not db then
        return false
    end
    if db.selectedRegion == region then
        return true
    end
    db.selectedRegion = region
    return true
end
