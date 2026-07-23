local _, ns = ...

local Util = {}
ns.Util = Util

function Util.IsAccessible(value)
    if value == nil then
        return false
    end
    if type(_G.issecretvalue) == "function" and _G.issecretvalue(value) then
        return false
    end
    if type(_G.canaccessvalue) == "function" and not _G.canaccessvalue(value) then
        return false
    end
    return true
end

function Util.SafeNumber(value)
    if type(value) ~= "number"
        or not Util.IsAccessible(value)
        or value ~= value
        or value == math.huge
        or value == -math.huge
    then
        return nil
    end
    return value
end

function Util.SafeString(value)
    if type(value) ~= "string" or not Util.IsAccessible(value) then
        return nil
    end
    return value
end

function Util.SafeBoolean(value)
    if type(value) ~= "boolean" or not Util.IsAccessible(value) then
        return nil
    end
    return value
end

function Util.SafeTable(value)
    if type(value) ~= "table" or not Util.IsAccessible(value) then
        return nil
    end
    if type(_G.canaccesstable) == "function" and not _G.canaccesstable(value) then
        return nil
    end
    return value
end

function Util.ClampNumber(value, minimum, maximum, fallback)
    if not Util.IsAccessible(value) then
        return fallback
    end
    local valueType = type(value)
    if valueType ~= "number" and valueType ~= "string" then
        return fallback
    end
    local numberValue = tonumber(value)
    if not Util.SafeNumber(numberValue) then
        return fallback
    end
    return math.max(minimum, math.min(maximum, numberValue))
end

local EXTENDED_RANK_ACHIEVEMENT_KEYS = {
    "keystoneLegend",
    "keystoneHero",
    "keystoneMaster",
    "keystoneConqueror",
    "keystoneExplorer",
}

local function RoundNumber(value)
    return math.floor(value + 0.5)
end

-- The data API's normal rank estimate stops at the published Top 40% cutoff,
-- even though the data pack also contains ranked achievement cutoff nodes.
-- Use those nodes to extend the same logarithmic rank interpolation downward.
function Util.EstimateRankBelowTop40(API, region, score, faction)
    local normalizedScore = Util.SafeNumber(score)
    if type(API) ~= "table"
        or type(API.GetCutoff) ~= "function"
        or type(region) ~= "string"
        or not normalizedScore
    then
        return nil
    end

    faction = faction or "all"
    local population
    if type(API.GetMetadata) == "function" then
        local ok, rawMetadata = pcall(API.GetMetadata, API, region)
        local metadata = ok and Util.SafeTable(rawMetadata) or nil
        population = metadata and Util.SafeNumber(metadata.population) or nil
    end

    local nodes = {}
    local function AddNode(rawNode, key)
        local node = Util.SafeTable(rawNode)
        local nodeScore = node and Util.SafeNumber(node.score) or nil
        local rank = node and Util.SafeNumber(node.rank) or nil
        local nodePopulation = node and Util.SafeNumber(node.population) or nil
        if not population then
            population = nodePopulation
        end
        if nodeScore and rank and nodeScore >= 0 and rank >= 1 then
            nodes[#nodes + 1] = {
                key = key,
                score = nodeScore,
                rank = rank,
                percentile = Util.SafeNumber(node.percentile),
            }
        end
    end

    local okTop40, rawTop40 = pcall(API.GetCutoff, API, region, "p600", faction)
    if okTop40 then
        AddNode(rawTop40, "p600")
    end
    if type(API.GetAchievementCutoff) == "function" then
        for _, key in ipairs(EXTENDED_RANK_ACHIEVEMENT_KEYS) do
            local ok, rawAchievement = pcall(API.GetAchievementCutoff, API, region, key, faction)
            if ok then
                AddNode(rawAchievement, key)
            end
        end
    end

    if not population or population < 1 or #nodes == 0 then
        return nil
    end

    table.sort(nodes, function(left, right)
        if left.score == right.score then
            return left.rank < right.rank
        end
        return left.score > right.score
    end)

    local ordered = {}
    for _, node in ipairs(nodes) do
        local previous = ordered[#ordered]
        if node.rank <= population
            and (not previous or (node.score < previous.score and node.rank >= previous.rank))
        then
            if not node.percentile then
                node.percentile = node.rank / population * 100
            end
            ordered[#ordered + 1] = node
        end
    end
    if #ordered == 0 or normalizedScore >= ordered[1].score then
        return nil
    end

    local last = ordered[#ordered]
    if last.score > 0 and last.rank < population then
        ordered[#ordered + 1] = {
            key = "population",
            score = 0,
            rank = population,
            percentile = 100,
        }
    end

    local clampedScore = math.max(0, normalizedScore)
    for index = 1, #ordered - 1 do
        local high = ordered[index]
        local low = ordered[index + 1]
        if clampedScore < high.score and clampedScore >= low.score then
            local scoreSpan = high.score - low.score
            local t = scoreSpan > 0 and ((high.score - clampedScore) / scoreSpan) or 0
            local estimatedRank = high.rank
            if low.rank > high.rank then
                estimatedRank = math.exp(
                    math.log(high.rank) + t * (math.log(low.rank) - math.log(high.rank))
                )
            end
            estimatedRank = math.max(1, math.min(population, RoundNumber(estimatedRank)))
            return {
                estimatedRank = estimatedRank,
                rankMin = high.rank,
                rankMax = low.rank,
                percentileMin = high.percentile or (high.rank / population * 100),
                percentileMax = low.percentile or (low.rank / population * 100),
                population = population,
                bracket = high.key .. "-" .. low.key,
                isEstimate = true,
                isExtendedEstimate = true,
            }
        end
    end

    return nil
end

function Util.NormalizeNonNegativeInteger(value)
    local numberValue = Util.SafeNumber(value)
    if not numberValue or numberValue < 0 then
        return nil
    end
    return math.floor(numberValue)
end

function Util.WipeArray(array)
    if type(array) ~= "table" then
        return array
    end
    for key in pairs(array) do
        array[key] = nil
    end
    return array
end

function Util.HexColorToRGB(color, fallbackR, fallbackG, fallbackB)
    local value = Util.SafeString(color)
    if value then
        value = value:gsub("^#", ""):gsub("^|c", ""):gsub("|r$", "")
        if #value == 8 then
            value = value:sub(3)
        end
        if #value == 6 and value:match("^[%x]+$") then
            return tonumber(value:sub(1, 2), 16) / 255,
                tonumber(value:sub(3, 4), 16) / 255,
                tonumber(value:sub(5, 6), 16) / 255
        end
    end
    return fallbackR or 1.0, fallbackG or 0.82, fallbackB or 0.0
end

function Util.ResolveScoreTierColor(score, rawTiers)
    local normalizedScore = Util.SafeNumber(score)
    local tiers = Util.SafeTable(rawTiers)
    if not normalizedScore or not tiers then
        return nil
    end

    local matchedThreshold
    local matchedColor
    local lowestThreshold
    local lowestColor
    for _, rawTier in ipairs(tiers) do
        local tier = Util.SafeTable(rawTier)
        local threshold = tier and Util.SafeNumber(tier.score) or nil
        local color = tier and Util.SafeString(tier.color) or nil
        if threshold and color then
            if not lowestThreshold or threshold < lowestThreshold then
                lowestThreshold = threshold
                lowestColor = color
            end
            if threshold <= normalizedScore and (not matchedThreshold or threshold > matchedThreshold) then
                matchedThreshold = threshold
                matchedColor = color
            end
        end
    end

    return matchedColor or lowestColor
end

function Util.GetPlayerScoreColor(API, region, score)
    if type(API) ~= "table" or type(API.GetScoreTiers) ~= "function" or type(region) ~= "string" then
        return nil
    end
    local ok, tiers = pcall(API.GetScoreTiers, API, region)
    if not ok then
        return nil
    end
    return Util.ResolveScoreTierColor(score, tiers)
end
