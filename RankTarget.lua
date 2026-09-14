local _, ns = ...
local Util = ns.Util

local RankTarget = {}
ns.RankTarget = RankTarget

RankTarget.CUTOFF_DEFS = {
    { key = "p999", percent = "0.1" },
    { key = "p990", percent = "1" },
    { key = "p900", percent = "10" },
    { key = "p750", percent = "25" },
    { key = "p600", percent = "40" },
}

local function CopyTarget(target, mode, targetKind, progress, distance)
    return {
        mode = mode,
        targetKind = targetKind,
        targetKey = target.key,
        targetName = target.localizedName,
        targetPercent = target.percent,
        targetScore = target.score,
        distance = math.max(0, distance or 0),
        progress = Util.ClampNumber(progress, 0, 1, 0),
        color = target.color,
    }
end

local function NormalizeTargets(source)
    local result = {}
    for _, raw in ipairs(type(source) == "table" and source or {}) do
        if type(raw) == "table" then
            local score = Util.SafeNumber(raw.score or raw.thresholdScore)
            if score then
                result[#result + 1] = {
                    key = Util.SafeString(raw.key),
                    percent = Util.SafeString(raw.percent),
                    score = score,
                    localizedName = Util.SafeString(raw.localizedName),
                    color = Util.SafeString(raw.color),
                }
            end
        end
    end
    return result
end

function RankTarget.Resolve(score, cutoffs, achievements)
    score = Util.SafeNumber(score)
    if not score then
        return nil
    end

    local normalizedCutoffs = NormalizeTargets(cutoffs)
    table.sort(normalizedCutoffs, function(left, right)
        return left.score < right.score
    end)
    if #normalizedCutoffs == 0 then
        return nil
    end

    local lowestCutoff = normalizedCutoffs[1]
    local highestCutoff = normalizedCutoffs[#normalizedCutoffs]
    if score >= highestCutoff.score then
        return CopyTarget(highestCutoff, "complete", "bracket", 1, 0)
    end

    if score >= lowestCutoff.score then
        for index = 2, #normalizedCutoffs do
            local target = normalizedCutoffs[index]
            if score < target.score then
                local lower = normalizedCutoffs[index - 1]
                local span = target.score - lower.score
                local progress = span > 0 and (score - lower.score) / span or 0
                return CopyTarget(target, "bracket", "bracket", progress, target.score - score)
            end
        end
    end

    local normalizedAchievements = NormalizeTargets(achievements)
    table.sort(normalizedAchievements, function(left, right)
        return left.score < right.score
    end)
    for _, target in ipairs(normalizedAchievements) do
        if score < target.score then
            local previousScore = 0
            for _, previous in ipairs(normalizedAchievements) do
                if previous.score >= target.score then
                    break
                end
                previousScore = previous.score
            end
            local span = target.score - previousScore
            local progress = span > 0 and (score - previousScore) / span or 0
            return CopyTarget(target, "score", "achievement", progress, target.score - score)
        end
    end

    local span = lowestCutoff.score - 3000
    local progress = span > 0 and (score - 3000) / span or 0
    return CopyTarget(lowestCutoff, "score", "cutoff", progress, lowestCutoff.score - score)
end
