local _, ns = ...

-- Zone visibility filter.
-- The HUD can be configured to show only in selected zone types:
--   dungeon : 5-player dungeons / Mythic+ (instanceType "party")
--   delve  : Delves (11.0+, scenario instances detected via C_Delves)
--   raid   : Raid instances (instanceType "raid")
--   pvp    : Battlegrounds & Arenas (instanceType "pvp" / "arena")
--   world  : Open world / cities / non-instanced areas

local ZONE_OPTIONS = {
    { key = "dungeon", label = "SETTINGS_ZONE_DUNGEON" },
    { key = "delve", label = "SETTINGS_ZONE_DELVE" },
    { key = "raid", label = "SETTINGS_ZONE_RAID" },
    { key = "pvp", label = "SETTINGS_ZONE_PVP" },
    { key = "world", label = "SETTINGS_ZONE_WORLD" },
}

local function GetInstanceType()
    if C_InstanceInfo and type(C_InstanceInfo.GetInstanceInfo) == "function" then
        local ok, info = pcall(C_InstanceInfo.GetInstanceInfo)
        if ok and info and info.instanceType then
            return info.instanceType
        end
    end
    if type(GetInstanceInfo) == "function" then
        local ok, instanceType = pcall(GetInstanceInfo)
        if ok and type(instanceType) == "string" then
            return instanceType
        end
    end
    return nil
end

local function IsInDelve()
    if C_Delves and type(C_Delves.IsInDelve) == "function" then
        local ok, result = pcall(C_Delves.IsInDelve)
        if ok then
            return result == true
        end
    end
    return false
end

function ns.GetCurrentZoneKey()
    if IsInDelve() then
        return "delve"
    end
    local instanceType = GetInstanceType()
    if instanceType == "party" then
        return "dungeon"
    elseif instanceType == "raid" then
        return "raid"
    elseif instanceType == "pvp" or instanceType == "arena" then
        return "pvp"
    elseif instanceType == "scenario" then
        -- Non-delve scenarios are rare; treat them as instanced group content.
        return "dungeon"
    end
    return "world"
end

function ns.GetZoneOptions()
    return ZONE_OPTIONS
end

function ns.IsZoneAllowed(zoneKey)
    local db = ns.GetDB and ns.GetDB() or nil
    if not db or type(db.showZones) ~= "table" then
        return true
    end
    return db.showZones[zoneKey] ~= false
end

function ns.ShouldShowInZone()
    return ns.IsZoneAllowed(ns.GetCurrentZoneKey())
end

function ns.SetZoneAllowed(zoneKey, value)
    local db = ns.GetDB and ns.GetDB() or nil
    if not db then
        return
    end
    if type(db.showZones) ~= "table" then
        db.showZones = {}
    end
    db.showZones[zoneKey] = value == true
end
