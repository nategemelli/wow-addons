local ns = {}
assert(loadfile(TEST_ROOT .. "/QuestRoute/Model.lua"))("QuestRoute", ns)
local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error("FAIL: " .. name .. ": " .. tostring(err)) end
    passed = passed + 1
end
local function eq(a, b) assert(a == b, "expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function quest(id, x, y, level, map)
    return { id = id, title = "Quest " .. id, level = level or 20,
        mapID = map or 1, mapName = "Area " .. (map or 1), x = x, y = y,
        objectivesLeft = 2 }
end
local function context(x, y)
    return { playerLevel = 20, player = { mapID = 1, x = x or 0, y = y or 0 } }
end
local function ids(plan)
    local values = {}
    for _, step in ipairs(plan.steps) do values[#values + 1] = step.id end
    return table.concat(values, ",")
end

test("empty input has an empty schedule", function()
    local result = ns.Optimize({}, context())
    eq(#result.steps, 0); eq(result.stats.total, 0)
end)
test("one quest produces copied metadata and a reason", function()
    local input = quest(1, 0.1, 0.1)
    local result = ns.Optimize({ input }, context())
    eq(result.steps[1].id, 1)
    assert(result.steps[1] ~= input)
    assert(#result.steps[1].reason > 0)
    eq(input.reason, nil); eq(input.hard, nil)
end)
test("player location sets the beginning of a distance route", function()
    local input = { quest(1, 0.1, 0.1), quest(2, 0.9, 0.9) }
    eq(ns.Optimize(input, context(0.85, 0.85), { mode = "distance" }).steps[1].id, 2)
end)
test("exactly two levels above is deferred after all easier quests", function()
    local input = { quest(1, 0, 0, 22), quest(2, 0.9, 0.9, 21), quest(3, 0.7, 0.7, 20) }
    local plan = ns.Optimize(input, context(), { mode = "distance" })
    eq(plan.steps[#plan.steps].id, 1); eq(plan.stats.hard, 1)
    assert(plan.steps[3].reason:find("scheduled later", 1, true))
end)
test("mixed hard quests retain a penalty", function()
    local plan = ns.Optimize({ quest(1, 0.1, 0.1, 22), quest(2, 0.1, 0.1, 20) },
        context(), { mode = "distance", deferHard = false })
    eq(plan.steps[1].id, 2); eq(plan.steps[2].hard, true)
    assert(plan.steps[2].reason:find("reduced priority", 1, true))
end)
test("hard quests may be mixed when a very distant easy detour costs more", function()
    local plan = ns.Optimize({ quest(1, 0, 0, 22), quest(2, 1, 1, 20) },
        context(), { mode = "distance", deferHard = false, cluster = "tight" })
    eq(plan.steps[1].id, 1)
end)
test("unknown quest levels are never labeled hard", function()
    local input = quest(1, 0.2, 0.2); input.level = nil
    local step = ns.Optimize({ input }, context()).steps[1]
    eq(step.hard, false); assert(step.reason:find("level unavailable", 1, true))
end)
test("scaling and unavailable player levels do not invent a comparison", function()
    local q = quest(1, 0.2, 0.2); q.level = -1
    eq(ns.Optimize({ q }, context()).steps[1].hard, false)
    eq(ns.Optimize({ quest(2, 0.2, 0.2, 100) }, { player = {} }).steps[1].hard, false)
end)
test("located quests precede unlocated quests within difficulty tier", function()
    local plan = ns.Optimize({ quest(1, nil, nil), quest(2, 0.9, 0.9) }, context())
    eq(ids(plan), "2,1"); eq(plan.stats.unlocated, 1)
    assert(plan.steps[2].reason:find("Location unavailable", 1, true))
end)
test("an easy unmapped quest still precedes a deferred hard mapped quest", function()
    local plan = ns.Optimize({ quest(1, 0, 0, 22), quest(2, nil, nil, 20) }, context())
    eq(ids(plan), "2,1")
end)
test("area blocks prevent map ping-pong", function()
    local plan = ns.Optimize({ quest(1, 0.02, 0.02, 20, 1), quest(2, 0.9, 0.9, 20, 1),
        quest(3, 0.1, 0.1, 20, 2), quest(4, 0.8, 0.8, 20, 2) }, context(), { mode = "distance" })
    eq(plan.steps[1].mapID, 1); eq(plan.steps[2].mapID, 1)
    eq(plan.steps[3].mapID, 2); eq(plan.steps[4].mapID, 2)
end)
test("map coordinates from different maps are never treated as distances", function()
    local input = { quest(1, 0.99, 0.99, 20, 2), quest(2, 0.01, 0.01, 20, 3) }
    local plan = ns.Optimize(input, context())
    eq(plan.steps[1].id, 1)
    for _, step in ipairs(plan.steps) do eq(step.distanceYards, nil) end
end)
test("same-instance world coordinates supply real straight-line yards", function()
    local q = quest(1, 0.5, 0.5, 20, 2)
    q.worldX, q.worldY, q.instanceID = 300, 400, 0
    local plan = ns.Optimize({ q }, { playerLevel = 20, player = { worldX = 0, worldY = 0, instanceID = 0 } })
    eq(plan.steps[1].distanceYards, 500)
end)
test("cross-instance coordinates never produce false yard distances", function()
    local q = quest(1, nil, nil, 20, 2)
    q.worldX, q.worldY, q.instanceID = 300, 400, 1
    local plan = ns.Optimize({ q }, { playerLevel = 20, player = { worldX = 0, worldY = 0, instanceID = 0 } })
    eq(plan.steps[1].distanceYards, nil)
end)
test("invalid normalized coordinates count as unmapped", function()
    local plan = ns.Optimize({ quest(1, -1, 0.1), quest(2, 0.2, 1.2), quest(3, 0 / 0, 0.2) }, context())
    eq(plan.stats.unlocated, 3)
end)
test("every quest ID appears only once", function()
    local q = quest(1, 0.1, 0.1)
    local plan = ns.Optimize({ q, q, quest(2, 0.2, 0.2), quest(3, nil, nil) }, context())
    eq(#plan.steps, 3); eq(plan.stats.total, 3)
    local seen = {}
    for _, step in ipairs(plan.steps) do assert(not seen[step.id]); seen[step.id] = true end
end)
test("route is deterministic across log order and repeated calls", function()
    local a, b, c = quest(1, 0.4, 0.3), quest(2, 0.1, 0.2), quest(3, 0.8, 0.9)
    local expected = ids(ns.Optimize({ a, b, c }, context()))
    eq(ids(ns.Optimize({ c, a, b }, context())), expected)
    eq(ids(ns.Optimize({ a, b, c }, context())), expected)
end)
test("level mode can favor an easier quest over a nearby higher one", function()
    local input = { quest(1, 0.01, 0.01, 21), quest(2, 0.2, 0.2, 18) }
    eq(ns.Optimize(input, context(), { mode = "distance" }).steps[1].id, 1)
    eq(ns.Optimize(input, context(), { mode = "level" }).steps[1].id, 2)
end)
test("time mode favors lighter objective workload", function()
    local a, b = quest(1, 0.01, 0.01), quest(2, 0.1, 0.1)
    a.objectivesLeft, b.objectivesLeft = 8, 1
    eq(ns.Optimize({ a, b }, context(), { mode = "distance" }).steps[1].id, 1)
    eq(ns.Optimize({ a, b }, context(), { mode = "time" }).steps[1].id, 2)
end)
test("prefer turn-ins changes ordering at otherwise comparable locations", function()
    local a, b = quest(1, 0.01, 0.01), quest(2, 0.08, 0.08)
    b.complete = true
    eq(ns.Optimize({ a, b }, context(), { preferTurnIns = true }).steps[1].id, 2)
    eq(ns.Optimize({ a, b }, context(), { preferTurnIns = false }).steps[1].id, 1)
end)
test("cluster radius changes nearby membership", function()
    local input = { quest(1, 0.1, 0.1), quest(2, 0.16, 0.1) }
    local tight = ns.Optimize(input, context(), { cluster = "tight" })
    local wide = ns.Optimize(input, context(), { cluster = "wide" })
    assert(not tight.steps[1].reason:find("nearby quests", 1, true))
    assert(wide.steps[1].reason:find("2 nearby quests", 1, true))
end)
test("cluster radius changes the route when a dense nearby pocket is separate", function()
    local input = { quest(1, 0.1, 0), quest(2, 0.09, 0.06), quest(3, 0.12, 0.06) }
    local tight = ns.Optimize(input, context(), { cluster = "tight" })
    local wide = ns.Optimize(input, context(), { cluster = "wide" })
    eq(ids(tight), "2,3,1")
    eq(ids(wide), "1,2,3")
end)
test("connected clusters are completed without visiting another cluster", function()
    local input = { quest(1, 0.1, 0.1), quest(2, 0.12, 0.1), quest(3, 0.8, 0.8), quest(4, 0.82, 0.8) }
    local plan = ns.Optimize(input, context(), { cluster = "tight" })
    eq(ids(plan), "1,2,3,4")
end)
test("missing workload does not produce a fabricated total ETA", function()
    local a = quest(1, 0.2, 0.2); a.objectivesLeft = nil
    local plan = ns.Optimize({ a, quest(2, 0.5, 0.5) }, context(), { mode = "time" })
    eq(plan.steps[1].estimatedMinutes, nil); eq(plan.stats.estimatedMinutes, nil)
end)
test("option defaults are normalized without mutating user settings", function()
    local options = { mode = "bogus", cluster = "bad" }
    local result = ns.Optimize({}, context(), options)
    eq(result.options.mode, "balanced"); eq(result.options.cluster, "normal")
    eq(result.options.deferHard, true); eq(result.options.preferTurnIns, true)
    eq(options.mode, "bogus")
end)
test("large mixed log has full unique coverage and no internal fields", function()
    local input = {}
    for id = 1, 100 do
        input[id] = quest(id, (id % 10) / 10, (id % 7) / 7, 18 + id % 6, 1 + id % 3)
        if id % 9 == 0 then input[id].x, input[id].y = nil, nil end
    end
    local plan = ns.Optimize(input, context())
    eq(#plan.steps, 100)
    local hardSeen = false
    for _, step in ipairs(plan.steps) do
        if step.hard then hardSeen = true else assert(not hardSeen) end
        eq(step._gap, nil); eq(step._located, nil)
        assert(type(step.reason) == "string")
    end
end)

test("legacy options retain multi-objective routes and invalid single goals normalize safely", function()
    local a, b = quest(1, 0.01, 0.01, 21), quest(2, 0.08, 0.08, 18)
    b.complete = true
    for _, mode in ipairs({ "balanced", "distance", "level", "time" }) do
        local legacy = ns.Optimize({ a, b }, context(), { mode = mode })
        local explicit = ns.Optimize({ a, b }, context(), { optimization = "multi", mode = mode })
        eq(legacy.options.optimization, "multi"); eq(ids(legacy), ids(explicit))
    end
    local saved = { optimization = "single", mode = "balanced", preferTurnIns = true }
    local normalized = ns.NormalizeOptions(saved)
    eq(normalized.optimization, "single"); eq(normalized.mode, "distance")
    eq(normalized.preferTurnIns, true); eq(saved.mode, "balanced")
    eq(ns.NormalizeOptions({ optimization = "single", mode = "bogus" }).mode, "distance")
    eq(ns.NormalizeOptions({ optimization = "bogus", mode = "bogus" }).optimization, "multi")
end)

test("single travel does not trade distance for lower levels workload or turn-ins", function()
    local a, b = quest(1, 0.01, 0.01, 21), quest(2, 0.02, 0.02, 18)
    a.objectivesLeft, b.objectivesLeft, b.complete = 100, 1, true
    local single = { optimization = "single", mode = "distance", preferTurnIns = true }
    eq(ids(ns.Optimize({ a, b }, context(), single)), "1,2")
    eq(ns.Optimize({ a, b }, context(), { optimization = "multi", mode = "distance" }).steps[1].id, 2)
    a.level, b.level = 18, 21
    a.objectivesLeft, b.objectivesLeft, a.complete, b.complete = 1, 100, true, false
    eq(ids(ns.Optimize({ a, b }, context(), single)), "1,2")
end)

test("single levels ignores travel workload and turn-in bonuses within grouping rules", function()
    local a, b = quest(1, 0.01, 0.01, 20), quest(2, 0.9, 0.9, 19)
    a.complete, a.objectivesLeft, b.objectivesLeft = true, 0, 100
    local options = { optimization = "single", mode = "level", cluster = "tight" }
    eq(ids(ns.Optimize({ a, b }, context(), options)), "2,1")
    eq(ns.Optimize({ a, b }, context(), { optimization = "multi", mode = "level", cluster = "tight" }).steps[1].id, 1)
    a.x, a.y, b.x, b.y = 0.9, 0.9, 0.01, 0.01
    a.complete, b.complete, a.objectivesLeft, b.objectivesLeft = false, true, 100, 0
    eq(ids(ns.Optimize({ a, b }, context(), options)), "2,1")
end)

test("single effort favors lighter work without a separate travel or level preference", function()
    local a, b = quest(1, 0.01, 0.01, 17), quest(2, 0.9, 0.9, 20)
    a.objectivesLeft, b.objectivesLeft = 2, 1
    local options = { optimization = "single", mode = "time", cluster = "tight" }
    eq(ids(ns.Optimize({ a, b }, context(), options)), "2,1")
    eq(ns.Optimize({ a, b }, context(), { optimization = "multi", mode = "time", cluster = "tight" }).steps[1].id, 1)
    -- Both levels are at or below the player, so the work estimate itself
    -- is unchanged when swapping levels. Travel also has zero weight.
    a.level, b.level, a.x, a.y, b.x, b.y = 20, 17, 0.9, 0.9, 0.01, 0.01
    eq(ids(ns.Optimize({ a, b }, context(), options)), "2,1")
end)

test("single objectives do not gain an extra preference from cluster density", function()
    local input = { quest(1, 0.1, 0.1), quest(2, 0.5, 0.5), quest(3, 0.51, 0.5) }
    local origin = { playerLevel = 20 }
    local single = ns.Optimize(input, origin, { optimization = "single", mode = "level", cluster = "tight" })
    local multi = ns.Optimize(input, origin, { optimization = "multi", mode = "level", cluster = "tight" })
    eq(single.steps[1].id, 1); eq(multi.steps[1].id, 2)
end)

test("every single objective retains hard quest deferral and mixed difficulty penalty", function()
    for _, mode in ipairs({ "distance", "level", "time" }) do
        local input = { quest(1, 0.1, 0.1, 22), quest(2, 0.1, 0.1, 20), quest(3, nil, nil, 20) }
        local deferred = ns.Optimize(input, context(), { optimization = "single", mode = mode })
        eq(ids(deferred), "2,3,1"); eq(deferred.stats.hard, 1)
        local mixed = ns.Optimize({ input[1], input[2] }, context(),
            { optimization = "single", mode = mode, deferHard = false })
        eq(ids(mixed), "2,1"); assert(mixed.steps[2].reason:find("reduced priority", 1, true))
    end
end)

test("single and multi objectives remain deterministic with complete quest coverage", function()
    local input, reversed = {}, {}
    for id = 1, 30 do
        input[id] = quest(id, (id % 10) / 10, (id % 7) / 7, 18 + id % 6, 1 + id % 3)
        if id % 9 == 0 then input[id].x, input[id].y = nil, nil end
    end
    for index = #input, 1, -1 do reversed[#reversed + 1] = input[index] end
    for _, optimization in ipairs({ "single", "multi" }) do
        for _, mode in ipairs({ "distance", "level", "time" }) do
            local options = { optimization = optimization, mode = mode }
            local plan = ns.Optimize(input, context(), options)
            eq(ids(ns.Optimize(reversed, context(), options)), ids(plan)); eq(#plan.steps, #input)
            local seen, hardSeen = {}, false
            for _, step in ipairs(plan.steps) do
                assert(not seen[step.id]); seen[step.id] = true
                if step.hard then hardSeen = true else assert(not hardSeen) end
                eq(step._gap, nil); eq(step._located, nil)
            end
        end
    end
end)

local function custom(travel, level, work, density)
    return { optimization = "multi", customWeights = true, preferTurnIns = false,
        weights = { travel = travel, level = level, work = work, density = density } }
end

test("weight presets are independent copies with all existing values represented", function()
    local balanced = ns.GetWeightPreset("balanced")
    eq(balanced.travel, 6); eq(balanced.level, 3); eq(balanced.work, 1.8); eq(balanced.density, 1.6)
    local distance = ns.GetWeightPreset("distance")
    eq(distance.work, 0.3); eq(distance.density, 0.35)
    balanced.travel = 0; eq(ns.GetWeightPreset("balanced").travel, 6)
    eq(ns.GetWeightPreset("invalid").travel, 6)
    local a, b = quest(1, 0.01, 0.01, 21), quest(2, 0.08, 0.08, 18)
    b.complete = true
    for _, mode in ipairs({ "balanced", "distance", "level", "time" }) do
        local legacy = ns.Optimize({ a, b }, context(), { mode = mode })
        local inactive = ns.Optimize({ a, b }, context(), { mode = mode, customWeights = false,
            weights = { travel = 10, level = 0, work = 0, density = 0 } })
        eq(ids(inactive), ids(legacy)); eq(inactive.options.customWeights, false)
        eq(inactive.options.weights.travel, ns.GetWeightPreset(mode).travel)
    end
end)

test("custom priorities clamp round and safely default invalid entries", function()
    local options = custom(-1, 12, 1.824, 0.35)
    local result = ns.NormalizeOptions(options)
    eq(result.weights.travel, 0); eq(result.weights.level, 10)
    eq(result.weights.work, 1.8); eq(result.weights.density, 0.35)
    eq(options.weights.travel, -1); eq(options.weights.level, 12)
    local invalid = ns.NormalizeOptions(custom(0 / 0, math.huge, -math.huge, "5"))
    eq(invalid.weights.travel, 6); eq(invalid.weights.level, 3)
    eq(invalid.weights.work, 1.8); eq(invalid.weights.density, 1.6)
    local missing = ns.NormalizeOptions({ customWeights = true, weights = { travel = 0 } })
    eq(missing.weights.travel, 0); eq(missing.weights.level, 3)
    eq(ns.NormalizeOptions({ customWeights = true, weights = "bad" }).weights.work, 1.8)
    local secret = {}
    issecretvalue = function(value) return value == secret end
    local restricted = ns.NormalizeOptions(custom(secret, 0, 0, 0))
    local restrictedTable = ns.NormalizeOptions({ customWeights = true, weights = secret })
    issecretvalue = nil
    eq(restricted.weights.travel, 6); eq(restricted.weights.level, 0)
    eq(restrictedTable.weights.work, 1.8)
end)

test("distance slider changes route order without changing other priorities", function()
    local input = { quest(1, 0.8, 0.8), quest(2, 0.1, 0.1) }
    eq(ns.Optimize(input, context(), custom(0, 0, 0, 0)).steps[1].id, 1)
    eq(ns.Optimize(input, context(), custom(10, 0, 0, 0)).steps[1].id, 2)
end)

test("level slider changes ordering of equally located non-hard quests", function()
    local input = { quest(1, 0.1, 0.1, 21), quest(2, 0.1, 0.1, 18) }
    eq(ns.Optimize(input, context(), custom(0, 0, 0, 0)).steps[1].id, 1)
    eq(ns.Optimize(input, context(), custom(0, 10, 0, 0)).steps[1].id, 2)
end)

test("effort slider changes ordering for remaining work at a shared location", function()
    local a, b = quest(1, 0.1, 0.1), quest(2, 0.1, 0.1)
    a.objectivesLeft, b.objectivesLeft = 8, 1
    eq(ns.Optimize({ a, b }, context(), custom(0, 0, 0, 0)).steps[1].id, 1)
    eq(ns.Optimize({ a, b }, context(), custom(0, 0, 10, 0)).steps[1].id, 2)
end)

test("clustering slider rewards denser clusters without changing grouping radius", function()
    local input = { quest(1, 0.1, 0.1), quest(2, 0.5, 0.5), quest(3, 0.51, 0.5) }
    local off, high = custom(0, 0, 0, 0), custom(0, 0, 0, 10)
    eq(ns.Optimize(input, context(), off).steps[1].id, 1)
    local plan = ns.Optimize(input, context(), high)
    eq(ids(plan), "2,3,1"); eq(plan.options.cluster, "normal")
    assert(plan.steps[1].reason:find("2 nearby quests", 1, true))
end)

test("custom weights in saved plans cannot alias later settings edits", function()
    local options = custom(1, 2, 3, 4)
    local normalized = ns.NormalizeOptions(options)
    local plan = ns.Optimize({ quest(1, 0.1, 0.1) }, context(), normalized)
    options.weights.travel = 10; normalized.weights.level = 10
    eq(plan.options.weights.travel, 1); eq(plan.options.weights.level, 2)
    plan.options.weights.work = 10
    eq(normalized.weights.work, 3); eq(options.weights.work, 3)
end)

test("single objectives ignore custom priorities while keeping them for switching back", function()
    local a, b = quest(1, 0.01, 0.01, 21), quest(2, 0.7, 0.7, 18)
    a.objectivesLeft, b.objectivesLeft = 8, 1
    local options = custom(0.35, 9.5, 1.25, 10)
    options.optimization = "single"
    for _, mode in ipairs({ "distance", "level", "time" }) do
        options.mode = mode
        local baseline = ns.Optimize({ a, b }, context(), { optimization = "single", mode = mode })
        local plan = ns.Optimize({ a, b }, context(), options)
        eq(ids(plan), ids(baseline)); eq(plan.options.customWeights, true)
        eq(plan.options.weights.travel, 0.35); eq(plan.options.weights.level, 9.5)
        eq(plan.options.weights.work, 1.25); eq(plan.options.weights.density, 10)
        options = ns.NormalizeOptions(plan.options)
    end
    options.optimization = "multi"
    local restored = ns.NormalizeOptions(options)
    eq(restored.weights.travel, 0.35); eq(restored.weights.density, 10)
end)

test("all zero custom weights remain deterministic and retain shared difficulty rules", function()
    local input = { quest(1, 0.1, 0.1, 22), quest(2, 0.1, 0.1, 20), quest(3, nil, nil, 20) }
    local options = custom(0, 0, 0, 0)
    local plan = ns.Optimize(input, context(), options)
    eq(ids(plan), "2,3,1"); eq(#plan.steps, 3)
    eq(ids(ns.Optimize({ input[3], input[2], input[1] }, context(), options)), ids(plan))
    options.deferHard = false
    eq(ns.Optimize({ input[1], input[2] }, context(), options).steps[1].id, 2)
end)

print("QUEST MODEL PASS: " .. passed .. " cases")
