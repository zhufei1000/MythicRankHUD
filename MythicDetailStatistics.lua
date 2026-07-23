local _, ns = ...
local Util = ns.Util

local Statistics = {}
ns.MythicDetailStatistics = Statistics

-- Verified against WoW 12.0.7 (build 68453) on 2026-07-16.
-- Reference: ExwindTools/Modules/ExM+InfoMythicFrame.lua, UpdateAllData.
-- EXWINDTOOLS does not use GetStatistic or a dungeon/statistic-ID map for these
-- columns. It aggregates C_MythicPlus.GetRunHistory with currentSeasonOnly=true.
-- Consequently this module intentionally contains no achievement statistic IDs.

local IsAccessible = Util.IsAccessible
local SafeTable = Util.SafeTable
local SafeBoolean = Util.SafeBoolean

function Statistics.NormalizeStatisticValue(value)
    local valueType = type(value)
    if valueType ~= "number" and valueType ~= "string" then
        return nil
    end
    if not IsAccessible(value) then
        return nil
    end

    local numberValue
    if valueType == "number" then
        numberValue = value
    else
        local trimmed = value:match("^%s*(.-)%s*$")
        if not trimmed or trimmed == "" or trimmed == "-" then
            return nil
        end
        local normalized = trimmed:gsub("[,%s']", "")
        if normalized == "" then
            return nil
        end
        numberValue = tonumber(normalized)
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

local function CreateMapRows(mapIDs)
    local rows = {}
    local order = {}
    local rawMapIDs = SafeTable(mapIDs)
    if not rawMapIDs then
        return rows, order
    end

    for _, rawMapID in ipairs(rawMapIDs) do
        local mapID = Statistics.NormalizeStatisticValue(rawMapID)
        if mapID and not rows[mapID] then
            rows[mapID] = {
                total = 0,
                timed = 0,
                overtime = 0,
                timingComplete = true,
            }
            order[#order + 1] = mapID
        end
    end
    return rows, order
end

local function InvalidateRows(rows, order)
    for _, mapID in ipairs(order) do
        local row = rows[mapID]
        row.total = nil
        row.timed = nil
        row.overtime = nil
        row.timingComplete = false
    end
end

local function BuildSummary(rows, order)
    if #order == 0 then
        return { total = nil, timed = nil, overtime = nil }
    end

    local total, timed, overtime = 0, 0, 0
    local totalComplete, timedComplete, overtimeComplete = true, true, true
    for _, mapID in ipairs(order) do
        local row = rows[mapID]
        if type(row.total) == "number" then
            total = total + row.total
        else
            totalComplete = false
        end
        if type(row.timed) == "number" then
            timed = timed + row.timed
        else
            timedComplete = false
        end
        if type(row.overtime) == "number" then
            overtime = overtime + row.overtime
        else
            overtimeComplete = false
        end
    end
    return {
        total = totalComplete and total or nil,
        timed = timedComplete and timed or nil,
        overtime = overtimeComplete and overtime or nil,
    }
end

local function AggregateRuns(mapIDs, rawRuns, ready)
    local rows, order = CreateMapRows(mapIDs)
    local result = {
        available = false,
        rows = rows,
        order = order,
        summary = { total = nil, timed = nil, overtime = nil },
    }

    local runs = SafeTable(rawRuns)
    if ready ~= true or not runs or #order == 0 then
        InvalidateRows(rows, order)
        return result
    end

    local placementComplete = true
    for _, rawRun in ipairs(runs) do
        local run = SafeTable(rawRun)
        if not run then
            placementComplete = false
            break
        end

        local mapID = Statistics.NormalizeStatisticValue(run.mapChallengeModeID)
        local row = mapID and rows[mapID] or nil
        if not row then
            placementComplete = false
            break
        end

        row.total = row.total + 1
        local completedInTime = SafeBoolean(run.completed)
        if completedInTime == true then
            row.timed = row.timed + 1
        elseif completedInTime == false then
            row.overtime = row.overtime + 1
        else
            row.timingComplete = false
        end
    end

    if not placementComplete then
        InvalidateRows(rows, order)
        return result
    end

    for _, mapID in ipairs(order) do
        local row = rows[mapID]
        if not row.timingComplete then
            row.timed = nil
            row.overtime = nil
        end
        row.timingComplete = nil
    end

    result.available = true
    result.summary = BuildSummary(rows, order)
    return result
end

function Statistics.BuildSingle(mapIDs, runs, ready, prefix)
    local aggregate = AggregateRuns(mapIDs, runs, ready)
    local byMapID = {}
    local totalKey = prefix .. "Total"
    local timedKey = prefix .. "Timed"
    local overtimeKey = prefix .. "Overtime"

    for _, mapID in ipairs(aggregate.order) do
        local row = aggregate.rows[mapID]
        byMapID[mapID] = {
            mapID = mapID,
            [totalKey] = row.total,
            [timedKey] = row.timed,
            [overtimeKey] = row.overtime,
        }
    end

    return {
        available = aggregate.available,
        byMapID = byMapID,
        summary = {
            [totalKey] = aggregate.summary.total,
            [timedKey] = aggregate.summary.timed,
            [overtimeKey] = aggregate.summary.overtime,
        },
    }
end

function Statistics.Build(mapIDs, seasonRuns, weeklyRuns, seasonReady, weeklyReady)
    local season = AggregateRuns(mapIDs, seasonRuns, seasonReady)
    local weekly = AggregateRuns(mapIDs, weeklyRuns, weeklyReady)
    local byMapID = {}

    for _, mapID in ipairs(season.order) do
        local seasonRow = season.rows[mapID]
        local weeklyRow = weekly.rows[mapID] or {}
        byMapID[mapID] = {
            mapID = mapID,
            seasonTotal = seasonRow.total,
            seasonTimed = seasonRow.timed,
            seasonOvertime = seasonRow.overtime,
            weeklyTotal = weeklyRow.total,
            weeklyTimed = weeklyRow.timed,
            weeklyOvertime = weeklyRow.overtime,
        }
    end

    return {
        byMapID = byMapID,
        seasonAvailable = season.available,
        weeklyAvailable = weekly.available,
        seasonSummary = {
            seasonTotal = season.summary.total,
            seasonTimed = season.summary.timed,
            seasonOvertime = season.summary.overtime,
        },
        weeklySummary = {
            weeklyTotal = weekly.summary.total,
            weeklyTimed = weekly.summary.timed,
            weeklyOvertime = weekly.summary.overtime,
        },
    }
end
