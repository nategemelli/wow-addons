local ns = {}
local secretValues = setmetatable({}, { __mode = "k" })
local function secret()
    local function forbidden() error("A secret was inspected") end
    local value = setmetatable({}, { __tostring = forbidden, __lt = forbidden,
        __le = forbidden, __add = forbidden, __sub = forbidden, __mul = forbidden,
        __div = forbidden, __concat = forbidden })
    secretValues[value] = true
    return value
end
issecretvalue = function(value) return type(value) == "table" and secretValues[value] == true end
assert(loadfile(TEST_ROOT .. "/TankWatch/Model.lua"))("TankWatch", ns)
local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error("FAIL: " .. name .. ": " .. tostring(err)) end
    passed = passed + 1
end
local function eq(actual, expected)
    assert(actual == expected, "unexpected result")
end
local function state(input, expected)
    local actual, label, detail, priority = ns.Classify(input)
    eq(actual, expected)
    assert(type(label) == "string" and #label > 0)
    assert(type(detail) == "string" and #detail > 0)
    assert(type(priority) == "number")
end

test("secret guards reject unknown values before operations", function()
    local value = secret()
    eq(ns.Number(value), nil)
    eq(ns.Bool(value), nil)
    eq(ns.Text(value, "Restricted"), "Restricted")
end)
test("finite threat values only", function()
    eq(ns.Number(0), 0)
    eq(ns.Number(72.5), 72.5)
    eq(ns.Number(0 / 0), nil)
    eq(ns.Number(math.huge), nil)
    eq(ns.Number(-math.huge), nil)
    eq(ns.Number("100"), nil)
end)
test("false boolean remains false", function() eq(ns.Bool(false), false) end)
test("unit text cannot insert WoW markup", function()
    eq(ns.Text("|cffff0000Enemy|r", "?"), "||cffff0000Enemy||r")
end)
test("absent and failed API calls degrade to no data", function()
    eq(ns.Query(nil), nil)
    eq(ns.Query(function() error("restricted") end), nil)
    eq(ns.queryFailures, 1)
end)
test("API wrapper preserves false and sparse multi-return values", function()
    local a, b, c, d, e = ns.Query(function() return false, nil, 12, nil, 5 end)
    eq(a, false); eq(b, nil); eq(c, 12); eq(d, nil); eq(e, 5)
end)
test("secret percentages reach only display payload", function()
    local value = secret()
    UnitThreatSituation = function() return 3 end
    UnitDetailedThreatSituation = function() return secret(), secret(), value, secret(), secret() end
    local result = ns.ReadThreat("player", "nameplate1")
    eq(result.status, 3)
    eq(result.restricted, false)
    eq(result.percent, value)
    eq(result.percentDisplayable, true)
    eq(result.readablePercent, nil)
end)
test("secret status cannot become a taunt recommendation", function()
    UnitThreatSituation = function() return secret() end
    UnitDetailedThreatSituation = function() return secret(), secret(), secret() end
    local result = ns.ReadThreat("player", "boss1")
    eq(result.status, nil)
    eq(result.restricted, true)
    state({ playerStatus = result.status }, "unknown")
end)
test("ordinary percentages remain usable for ranking", function()
    UnitThreatSituation = function() return 0 end
    UnitDetailedThreatSituation = function() return false, 0, 42.5, 39.5, 120 end
    local result = ns.ReadThreat("party1", "target")
    eq(result.status, 0)
    eq(result.readablePercent, 42.5)
    eq(result.percentDisplayable, true)
end)
test("missing detail API does not suppress readable threat state", function()
    UnitThreatSituation = function() return 2 end
    UnitDetailedThreatSituation = nil
    local result = ns.ReadThreat("player", "target")
    eq(result.status, 2)
    eq(result.percentDisplayable, false)
end)
test("secure tank with zero lead warning is safe", function()
    state({ playerStatus = 3, leadStatus = 0, targetIsPlayer = true }, "safe")
end)
test("insecure tank status warns without exact numbers", function()
    state({ playerStatus = 2 }, "warning")
end)
for lead = 1, 3 do
    test("lead warning " .. lead .. " warns while tanking", function()
        state({ playerStatus = 3, leadStatus = lead }, "warning")
    end)
end
test("not holding threat with lead red does not claim merely losing lead", function()
    state({ playerStatus = 0, leadStatus = 3, holderIsGroup = true, holderRole = "DAMAGER" }, "danger")
end)
test("healer holding aggro is high priority", function()
    state({ playerStatus = 1, holderIsGroup = true, holderRole = "HEALER" }, "danger")
end)
test("co-tank holding aggro avoids taunt recommendation", function()
    state({ playerStatus = 0, holderIsGroup = true, holderRole = "TANK", holderIsPlayer = false }, "cotank")
end)
test("self marked tank does not become other tank", function()
    state({ playerStatus = 3, holderRole = "TANK", holderIsPlayer = true }, "safe")
end)
test("fixate possibility overrides reassuring safe state", function()
    state({ playerStatus = 3, targetIsGroup = true, targetIsPlayer = false }, "attention")
end)
test("known target without threat ownership asks for inspection only", function()
    state({ targetIsGroup = true, targetIsPlayer = false }, "attention")
end)
test("no data is unknown", function() state({}, "unknown") end)
test("status zero is not misread as nonexistent in Lua", function()
    state({ playerStatus = 0 }, "attention")
end)
test("enemy ordering prioritizes danger and uses stable tie order", function()
    local rows = { { priority = 5, order = 1 }, { priority = 0, order = 3 },
        { priority = 1, order = 4 }, { priority = 0, order = 2 } }
    ns.SortEnemies(rows)
    eq(rows[1].order, 2); eq(rows[2].order, 3); eq(rows[3].order, 4); eq(rows[4].order, 1)
end)
test("numeric threat ranking preserves ties", function()
    local rows = { { readablePercent = 50, order = 1 }, { readablePercent = 90, order = 3 },
        { readablePercent = 90, order = 2 } }
    eq(ns.SortMembers(rows), true)
    eq(rows[1].order, 2); eq(rows[2].order, 3); eq(rows[3].order, 1)
end)
test("one missing percentage retains original roster order", function()
    local rows = { { readablePercent = 5, order = 1 }, { percent = secret(), order = 2 },
        { readablePercent = 99, order = 3 } }
    eq(ns.SortMembers(rows), false)
    eq(rows[1].order, 1); eq(rows[2].order, 2); eq(rows[3].order, 3)
end)
test("new danger sounds after cooldown", function()
    eq(ns.ShouldAlert("safe", "danger", 10, 0, 3), true)
end)
test("persistent danger does not repeat", function()
    eq(ns.ShouldAlert("danger", "danger", 100, 0, 3), false)
end)
test("warning transition obeys cooldown", function()
    eq(ns.ShouldAlert("safe", "warning", 1, 0, 3), false)
    eq(ns.ShouldAlert("safe", "warning", 3, 0, 3), true)
end)
for _, value in ipairs({ "safe", "cotank", "attention", "unknown" }) do
    test(value .. " state never emits loss warning", function()
        eq(ns.ShouldAlert("danger", value, 100, 0, 3), false)
    end)
end
print("MODEL PASS: " .. passed .. " regression cases")
