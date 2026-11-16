local _, ns = ...

-- A deterministic route heuristic, not a pathfinder or a promise of the
-- mathematically shortest tour. No game APIs are called while optimizing.
local modes = {
    balanced = { travel = 6, level = 3, work = 0.18, density = 1.6 },
    distance = { travel = 10, level = 1.5, work = 0.03, density = 0.35 },
    level = { travel = 3, level = 7, work = 0.08, density = 0.7 },
    time = { travel = 5, level = 2, work = 1, density = 1.1 },
}
local singleModes = {
    distance = { travel = 10, level = 0, work = 0, density = 0 },
    level = { travel = 0, level = 7, work = 0, density = 0 },
    time = { travel = 0, level = 0, work = 1, density = 0 },
}
local radii = {
    tight = { yards = 180, map = 0.035 },
    normal = { yards = 350, map = 0.07 },
    wide = { yards = 700, map = 0.14 },
}

local function Number(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function Copy(source)
    local target = {}
    for key, value in pairs(source) do target[key] = value end
    return target
end

local weightKeys = { "travel", "level", "work", "density" }
local function Priority(value)
    value = Number(value)
    if not value then return nil end
    return math.floor(math.max(0, math.min(10, value)) * 20 + 0.5) / 20
end

function ns.GetWeightPreset(mode)
    local weights = modes[mode] or modes.balanced
    -- Effort uses a smaller scoring coefficient because its inputs are
    -- minute proxies. Present all four controls on the same 0..10 scale.
    return { travel = Priority(weights.travel), level = Priority(weights.level),
        work = Priority(weights.work * 10), density = Priority(weights.density) }
end

function ns.NormalizeOptions(options)
    options = type(options) == "table" and options or {}
    local optimization = options.optimization == "single" and "single" or "multi"
    local available = optimization == "single" and singleModes or modes
    local mode = available[options.mode] and options.mode or (optimization == "single" and "distance" or "balanced")
    local customWeights = options.customWeights == true
    local weights = ns.GetWeightPreset(mode)
    if customWeights then
        local saved = options.weights
        if type(issecretvalue) == "function" and issecretvalue(saved) then saved = nil end
        saved = type(saved) == "table" and saved or {}
        for _, key in ipairs(weightKeys) do weights[key] = Priority(saved[key]) or weights[key] end
    end
    return {
        optimization = optimization,
        mode = mode,
        customWeights = customWeights,
        weights = weights,
        cluster = radii[options.cluster] and options.cluster or "normal",
        deferHard = options.deferHard ~= false,
        preferTurnIns = options.preferTurnIns ~= false,
    }
end

local function HasWorld(point)
    return point and Number(point.instanceID) ~= nil
        and Number(point.worldX) ~= nil and Number(point.worldY) ~= nil
end

local function HasMap(point)
    local x, y = point and Number(point.x), point and Number(point.y)
    return point and Number(point.mapID) ~= nil and x ~= nil and y ~= nil
        and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

local function Located(point)
    return HasWorld(point) or HasMap(point)
end

-- The second return value is a unit label. Normalized map distances must
-- never be formatted as yards or compared directly across different maps.
local function Distance(a, b)
    if HasWorld(a) and HasWorld(b) and a.instanceID == b.instanceID then
        local dx, dy = a.worldX - b.worldX, a.worldY - b.worldY
        return math.sqrt(dx * dx + dy * dy), "yards"
    end
    if HasMap(a) and HasMap(b) and a.mapID == b.mapID then
        local dx, dy = a.x - b.x, a.y - b.y
        return math.sqrt(dx * dx + dy * dy), "map"
    end
    return nil
end

local function TravelCost(a, b)
    local distance, unit = Distance(a, b)
    if distance then return unit == "yards" and distance / 1000 or distance / 0.2 end
    if not a or not Located(a) then return 0 end
    -- Unknown transitions receive a heuristic penalty, never a made-up
    -- distance or travel duration. Terrain, portals, and flights are unknown.
    if a.mapID and b.mapID and a.mapID == b.mapID then return 1.5 end
    if HasWorld(a) and HasWorld(b) and a.instanceID ~= b.instanceID then return 5 end
    return 3
end

local function AreaKey(quest)
    if Number(quest.mapID) then return "map:" .. quest.mapID end
    return "zone:" .. (quest.zone or quest.mapName or "Unknown area")
end

local function AreaName(quest)
    return quest.mapName or quest.zone or "Unknown area"
end

local function LevelGap(quest, playerLevel)
    local level = Number(quest.level)
    if not level or level <= 0 or not playerLevel or playerLevel <= 0 then return nil end
    return level - playerLevel
end

local function EstimateWork(quest, gap)
    if quest.complete then return 1 end
    local remaining = Number(quest.objectivesLeft)
    if not remaining or remaining <= 0 then return nil end
    -- A configurable scheduler mode needs a work proxy, but the client has
    -- no completion-time model. Three minutes per unfinished objective line
    -- is intentionally a rough estimate, not an observed or promised ETA.
    local group = math.max(1, math.min(5, Number(quest.groupSize) or 1))
    local difficulty = 1 + math.min(6, math.max(0, gap or 0)) * 0.2
    return math.floor(remaining * 3 * (1 + (group - 1) * 0.35) * difficulty + 0.5)
end

local function QuestScore(quest, cursor, weights, options)
    local gap = quest._gap
    local levelCost = gap and math.max(-3, gap) * weights.level or 0
    -- Even when the user permits hard quests to mix into the route, every
    -- quest two or more levels up retains an explicit difficulty penalty.
    if quest.hard then levelCost = levelCost + 12 end
    -- A turn-in bonus would introduce an additional objective in single
    -- mode. Keep the saved preference for switching back to multi mode.
    local turnIn = options.optimization == "multi" and options.preferTurnIns and quest.complete and 4 or 0
    return TravelCost(cursor, quest) * weights.travel + levelCost
        + (quest.estimatedMinutes or 6) * weights.work - turnIn
end

local function Earlier(a, b)
    return a.id < b.id
end

local function BestQuest(items, cursor, weights, options)
    local best, score
    for index, quest in ipairs(items) do
        local value = QuestScore(quest, cursor, weights, options)
        -- A short look-ahead reduces isolated detours without a costly
        -- factorial tour search. The same weights apply to each candidate.
        if #items > 1 and weights.travel > 0 then
            local onward
            for _, other in ipairs(items) do
                if other ~= quest then
                    local cost = TravelCost(quest, other)
                    if not onward or cost < onward then onward = cost end
                end
            end
            value = value + (onward or 0) * weights.travel * 0.15
        end
        if not best or value < score or (value == score and Earlier(quest, items[best])) then
            best, score = index, value
        end
    end
    return best, score
end

local function Clusters(items, radius)
    local clusters, used = {}, {}
    -- Connected neighborhoods keep nearby objectives together; membership
    -- is fixed before routing so ties and log order cannot change the result.
    for index, quest in ipairs(items) do
        if not used[index] then
            local cluster = { quest }
            used[index] = true
            local head = 1
            while head <= #cluster do
                for otherIndex, other in ipairs(items) do
                    if not used[otherIndex] then
                        local distance, unit = Distance(cluster[head], other)
                        if distance and distance <= (unit == "yards" and radius.yards or radius.map) then
                            used[otherIndex] = true
                            cluster[#cluster + 1] = other
                        end
                    end
                end
                head = head + 1
            end
            table.sort(cluster, Earlier)
            clusters[#clusters + 1] = cluster
        end
    end
    return clusters
end

local function BestCluster(clusters, cursor, weights, options)
    local best, score
    for index, cluster in ipairs(clusters) do
        local _, value = BestQuest(cluster, cursor, weights, options)
        value = value - math.log(#cluster + 1) * weights.density
        if not best or value < score or (value == score and Earlier(cluster[1], clusters[best][1])) then
            best, score = index, value
        end
    end
    return best, score
end

local function MakeGroups(items, radius)
    local groups, byArea = {}, {}
    for _, quest in ipairs(items) do
        local key = AreaKey(quest)
        local group = byArea[key]
        if not group then
            group = { items = {}, firstID = quest.id }
            byArea[key] = group
            groups[#groups + 1] = group
        end
        group.items[#group.items + 1] = quest
    end
    for _, group in ipairs(groups) do group.clusters = Clusters(group.items, radius) end
    return groups
end

local function Reason(quest, count, options)
    local parts = {}
    if quest.complete then parts[#parts + 1] = "Ready to turn in" end
    if quest.hard then
        parts[#parts + 1] = "Level +" .. quest._gap .. (options.deferHard and ": scheduled later" or ": reduced priority")
    elseif not quest._gap then
        parts[#parts + 1] = "Quest level unavailable"
    end
    if not quest._located then
        parts[#parts + 1] = "Location unavailable; grouped by " .. AreaName(quest)
    elseif count > 1 then
        parts[#parts + 1] = count .. " nearby quests in " .. AreaName(quest)
    else
        parts[#parts + 1] = AreaName(quest)
    end
    return table.concat(parts, ". ")
end

local function RouteGroup(group, cursor, steps, weights, options)
    while #group.clusters > 0 do
        local index = BestCluster(group.clusters, cursor, weights, options)
        local cluster = table.remove(group.clusters, index)
        local count = #cluster
        while #cluster > 0 do
            local questIndex = BestQuest(cluster, cursor, weights, options)
            local quest = table.remove(cluster, questIndex)
            local distance, unit = Distance(cursor, quest)
            quest.distanceYards = unit == "yards" and distance or nil
            quest.reason = Reason(quest, count, options)
            quest._gap, quest._located = nil, nil
            steps[#steps + 1] = quest
            -- An unknown location must not erase the last known position.
            if Located(quest) then cursor = quest end
        end
    end
    return cursor
end

local function RouteAreas(items, cursor, steps, weights, options)
    local groups = MakeGroups(items, radii[options.cluster])
    while #groups > 0 do
        local best, score
        for index, group in ipairs(groups) do
            local _, value = BestCluster(group.clusters, cursor, weights, options)
            if not best or value < score or (value == score and group.firstID < groups[best].firstID) then
                best, score = index, value
            end
        end
        cursor = RouteGroup(table.remove(groups, best), cursor, steps, weights, options)
    end
    return cursor
end

function ns.Optimize(quests, context, options)
    context = context or {}
    options = ns.NormalizeOptions(options)
    local weights = (options.optimization == "single" and singleModes or modes)[options.mode]
    if options.optimization == "multi" and options.customWeights then
        weights = { travel = options.weights.travel, level = options.weights.level,
            work = options.weights.work / 10, density = options.weights.density }
    end
    local items, seen = {}, {}
    local stats = { total = 0, located = 0, unlocated = 0, hard = 0, estimatedMinutes = 0 }
    local unknownWork = false
    local playerLevel = Number(context.playerLevel)
    for _, input in ipairs(quests or {}) do
        local id = Number(input.id)
        if id and id > 0 and id == math.floor(id) and not seen[id] then
            seen[id] = true
            local quest = Copy(input)
            quest._gap = LevelGap(quest, playerLevel)
            quest.hard = quest._gap ~= nil and quest._gap >= 2
            quest._located = Located(quest) and true or false
            quest.estimatedMinutes = EstimateWork(quest, quest._gap)
            stats.total = stats.total + 1
            if quest._located then stats.located = stats.located + 1 else stats.unlocated = stats.unlocated + 1 end
            if quest.hard then stats.hard = stats.hard + 1 end
            if quest.estimatedMinutes then stats.estimatedMinutes = stats.estimatedMinutes + quest.estimatedMinutes
            else unknownWork = true end
            items[#items + 1] = quest
        end
    end
    if unknownWork then stats.estimatedMinutes = nil end
    table.sort(items, Earlier)
    local steps, cursor = {}, context.player
    local tiers = options.deferHard and { false, true } or { "mixed" }
    for _, hardTier in ipairs(tiers) do
        local located, unlocated = {}, {}
        for _, quest in ipairs(items) do
            if hardTier == "mixed" or quest.hard == hardTier then
                local bucket = quest._located and located or unlocated
                bucket[#bucket + 1] = quest
            end
        end
        cursor = RouteAreas(located, cursor, steps, weights, options)
        cursor = RouteAreas(unlocated, cursor, steps, weights, options)
    end
    return { steps = steps, stats = stats, options = options }
end
