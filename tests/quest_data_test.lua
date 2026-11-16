-- Actual Forever API return shapes, with deliberately failing/restricted data.
local ns = {}
local secretValues = setmetatable({}, { __mode = "k" })
local function secret()
    local function forbidden() error("restricted value inspected") end
    local value = setmetatable({}, { __index = forbidden, __tostring = forbidden,
        __concat = forbidden, __lt = forbidden, __le = forbidden, __add = forbidden })
    secretValues[value] = true
    return value
end
issecretvalue = function(value) return type(value) == "table" and secretValues[value] == true end
local entries, waypoints, pois, objectives, completions, questMaps, difficulties, worldSpaces
local playerLevel, playerPosition, mutations, opened, combat
local function vector(x, y)
    return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
end
local function reset()
    entries, waypoints, pois, objectives, completions, questMaps, difficulties, worldSpaces = {}, {}, {}, {}, {}, {}, {}, {}
    playerLevel, playerPosition, mutations, opened, combat = 20, vector(.1, .2), 0, nil, false
    UnitLevel = function(unit) assert(unit == "player"); return playerLevel end
    CreateVector2D = vector
    C_Map = {
        GetBestMapForUnit = function(unit) assert(unit == "player"); return 100 end,
        GetPlayerMapPosition = function(map, unit) assert(map == 100 and unit == "player"); return playerPosition end,
        GetMapInfo = function(id) return { name = "Map " .. id } end,
        GetWorldPosFromMapPos = function(map, point)
            return worldSpaces[map] or 1, vector(point.x * 1000 + map, point.y * 2000)
        end,
        OpenWorldMap = function(id) opened = { mapID = id } end,
    }
    C_QuestLog = {
        GetNumQuestLogEntries = function() return #entries, #entries end,
        GetInfo = function(index) return entries[index] end,
        GetNextWaypoint = function(id)
            local point = waypoints[id]
            if point then return point[1], point[2], point[3] end
        end,
        GetNextWaypointForMap = function() end,
        GetMapForQuestPOIs = function() return 100 end,
        GetQuestsOnMap = function(id) return pois[id] end,
        GetQuestObjectives = function(id) return objectives[id] end,
        IsComplete = function(id) return completions[id] or false end,
        GetQuestDifficultyLevel = function(id) return difficulties[id] end,
        GetSuggestedGroupSize = function() return nil end,
    }
    GetQuestUiMapID = function(id) return questMaps[id] end
    InCombatLockdown = function() return combat end
    QuestMapFrame_OpenToQuestDetails = function(id) opened = { id = id } end
    local function forbidden() mutations = mutations + 1; error("scan changed client state") end
    ExpandQuestHeader, CollapseQuestHeader, SelectQuestLogEntry = forbidden, forbidden, forbidden
    C_QuestLog.SetSelectedQuest, C_QuestLog.AddQuestWatch = forbidden, forbidden
end
local function quest(id, extra)
    local info = { questID = id, title = "Quest " .. id, level = 20, isHeader = false, isHidden = false }
    for k, v in pairs(extra or {}) do info[k] = v end
    entries[#entries + 1] = info
    return info
end
local function eq(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local passed = 0
local function test(name, fn)
    reset()
    local ok, err = pcall(fn)
    if not ok then error("FAIL quest data: " .. name .. ": " .. tostring(err)) end
    passed = passed + 1
end
assert(loadfile(TEST_ROOT .. "/QuestRoute/Data.lua"))("QuestRoute", ns)

test("log scan skips headers and hidden/internal entries and deduplicates IDs", function()
    entries[1] = { title = "Elwynn", isHeader = true, isCollapsed = true }
    quest(1); quest(2, { isHidden = true }); quest(3, { isInternalOnly = true }); quest(1)
    local quests = ns.CollectQuests()
    eq(#quests, 1); eq(quests[1].id, 1); eq(quests[1].zone, "Elwynn")
    eq(mutations, 0); eq(opened, nil)
end)

test("native waypoint has priority and world vectors retain shared space", function()
    quest(1); waypoints[1] = { 201, .25, .75 }; questMaps[1] = 200
    local quests, context = ns.CollectQuests()
    local q = quests[1]
    eq(q.mapID, 201); eq(q.x, .25); eq(q.y, .75); eq(q.mapName, "Map 201")
    eq(q.zone, "Map 201"); eq(q.worldX, 451); eq(q.worldY, 1500); eq(q.instanceID, 1)
    eq(context.player.worldX, 200); eq(context.player.worldY, 400)
end)

test("POI coordinate space is queried map, not child map field", function()
    quest(1); questMaps[1] = 200
    pois[200] = { { questID = 1, mapID = 300, x = .4, y = .6 } }
    local q = ns.CollectQuests()[1]
    eq(q.mapID, 200); eq(q.x, .4); eq(q.y, .6); eq(q.locationSource, "Quest map pin")
end)

test("quest-start and map-indicator POIs are not objective destinations", function()
    quest(1); quest(2)
    pois[100] = {
        { questID = 1, x = .2, y = .3, isQuestStart = true },
        { questID = 2, x = .4, y = .5, isMapIndicatorQuest = true },
    }
    local quests = ns.CollectQuests()
    eq(quests[1].x, nil); eq(quests[2].x, nil)
end)

test("waypoint for known map is usable when generic waypoint absent", function()
    quest(1); questMaps[1] = 200
    C_QuestLog.GetNextWaypointForMap = function(id, map)
        assert(id == 1 and map == 200); return .3, .7
    end
    local q = ns.CollectQuests()[1]
    eq(q.mapID, 200); eq(q.x, .3); eq(q.y, .7)
end)

test("known map without coordinates does not become an invented center", function()
    quest(1); questMaps[1] = 200
    local quests, context = ns.CollectQuests()
    eq(quests[1].mapID, 200); eq(quests[1].zone, "Map 200")
    eq(quests[1].x, nil); eq(quests[1].worldX, nil); assert(#context.warnings > 0)
end)

test("invalid and non-finite coordinates remain unlocated", function()
    quest(1); quest(2); quest(3)
    waypoints[1] = { 200, 0, 0 }; waypoints[2] = { 200, math.huge, .5 }; waypoints[3] = { 200, -1, .5 }
    local quests = ns.CollectQuests()
    for _, q in ipairs(quests) do eq(q.x, nil); eq(q.y, nil) end
end)

test("restricted data never escapes into scheduling primitives", function()
    quest(1, { title = secret(), level = secret(), suggestedGroup = secret() })
    entries[#entries + 1] = { questID = secret(), title = "Restricted quest", isHeader = false }
    quest(3, { isHidden = secret() })
    waypoints[1] = { secret(), secret(), secret() }
    difficulties[1] = secret(); playerPosition = vector(secret(), .5)
    objectives[1] = { { finished = secret(), text = secret() } }
    local quests, context = ns.CollectQuests()
    eq(#quests, 1); eq(quests[1].title, "Quest 1"); eq(quests[1].level, nil)
    eq(quests[1].objectivesLeft, nil); eq(quests[1].mapID, nil); eq(context.player.x, nil)
end)

test("restricted entire records and arrays cannot be indexed", function()
    entries[1] = secret(); quest(1); objectives[1] = secret(); pois[100] = secret()
    local quests = ns.CollectQuests()
    eq(#quests, 1); eq(quests[1].objectivesLeft, nil); eq(quests[1].x, nil)
end)

test("difficulty uses effective level with raw and explicit scaling fallbacks", function()
    quest(1, { level = 50 }); difficulties[1] = 21
    quest(2, { level = 19 }); difficulties[2] = 0
    quest(3, { level = -1, isScaling = true })
    quest(4, { level = 0 })
    local quests = ns.CollectQuests()
    eq(quests[1].level, 21); eq(quests[2].level, 19); eq(quests[3].level, 20); eq(quests[4].level, nil)
end)

test("objective count tracks unfinished goals, not raw kill quantities", function()
    quest(1)
    objectives[1] = {
        { finished = false, text = "Wolves 2/10", numFulfilled = 2, numRequired = 10 },
        { finished = true, text = "Visit town" },
        { finished = false, text = "Find supplies" },
    }
    local q = ns.CollectQuests()[1]
    eq(q.objectivesLeft, 2); eq(q.objectiveText, "Wolves 2/10")
end)

test("completed quest yields turn-in stage while missing objectives stay unknown", function()
    quest(1); completions[1] = true
    quest(2); objectives[2] = {}
    local quests = ns.CollectQuests()
    eq(quests[1].complete, true); eq(quests[1].objectivesLeft, 0)
    eq(quests[2].complete, false); eq(quests[2].objectivesLeft, nil)
end)

test("missing quest API produces usable context and warning", function()
    C_QuestLog = nil
    local quests, context = ns.CollectQuests()
    eq(#quests, 0); eq(context.playerLevel, 20); assert(#context.warnings > 0)
    eq(context.unavailable, true)
end)

test("valid empty log is distinct from an unavailable log", function()
    local quests, context = ns.CollectQuests()
    eq(#quests, 0); eq(context.unavailable, nil)
    quest(1); C_QuestLog.GetInfo = nil
    quests, context = ns.CollectQuests()
    eq(#quests, 0); eq(context.unavailable, true)
end)

test("fully unreadable quest log preserves unavailable status", function()
    entries[1] = { isHeader = true, title = "Zone" }
    entries[2] = secret()
    local quests, context = ns.CollectQuests()
    eq(#quests, 0); eq(context.unavailable, true)
end)

test("failed quests are excluded once with restart warning", function()
    quest(1); quest(1)
    C_QuestLog.IsFailed = function(id) return id == 1 end
    local quests, context = ns.CollectQuests()
    eq(#quests, 0); eq(context.unavailable, nil)
    assert(context.warnings[#context.warnings]:find("1 failed quests", 1, true))
end)

test("throwing APIs degrade to unlocated rows without scan writes", function()
    quest(1)
    C_QuestLog.GetNextWaypoint = function() error("unavailable") end
    C_Map.GetWorldPosFromMapPos = function() error("unavailable") end
    local quests, context = ns.CollectQuests()
    eq(#quests, 1); eq(quests[1].x, nil); eq(mutations, 0); assert(#context.warnings > 0)
end)

test("opening is explicit and combat guarded with map fallback", function()
    eq(ns.OpenQuest({ id = 11 }), true); eq(opened.id, 11)
    combat, opened = true, nil
    eq(ns.OpenQuest({ id = 11, mapID = 200 }), false); eq(opened, nil)
    combat, QuestMapFrame_OpenToQuestDetails = false, nil
    eq(ns.OpenQuest({ id = 11, mapID = 200 }), true); eq(opened.mapID, 200)
    C_Map.OpenWorldMap = nil
    eq(ns.OpenQuest({ id = 11 }), false)
end)

test("unknown player level remains unknown rather than level one", function()
    playerLevel = secret(); quest(1, { level = -1, isScaling = true })
    local quests, context = ns.CollectQuests()
    eq(context.playerLevel, 0); eq(quests[1].level, nil); assert(#context.warnings > 0)
end)

print("QUEST DATA PASS: " .. passed .. " mocked-client cases")
