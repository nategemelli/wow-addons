local ns = {}
assert(loadfile(TEST_ROOT .. "/QuestTips/Data.lua"))("QuestTips", ns)

-- Only quest 10 is selected in the native log. The addon is browsing 20.
local selected, mutations = 10, 0
local secret = {}
issecretvalue = function(value) return rawequal(value, secret) end
local function forbidden()
    mutations = mutations + 1
    error("changed the quest log while reading it")
end
ExpandQuestHeader, CollapseQuestHeader, SelectQuestLogEntry = forbidden, forbidden, forbidden
local rows = {
    { questID = 0, isHeader = true, isCollapsed = true },
    { questID = 10, title = "Scouting" },
    { questID = 11, isHidden = true },
    { questID = 12, isInternalOnly = true },
    { questID = 13, isHeader = secret },
    { questID = 14, title = "Offered quest" },
    { questID = 20, title = "Gather supplies" },
    { questID = 20, title = "Duplicate" },
}
local complete, showItemWhenComplete = false, false
local itemLink = "|Hitem:123|h[Survey Kit]|h"
C_QuestLog = {
    GetNumQuestLogEntries = function() return #rows, 7 end,
    GetInfo = function(index) return rows[index] end,
    GetSelectedQuest = function() return selected end,
    SetSelectedQuest = forbidden,
    GetLogIndexForQuestID = function(id)
        for i, row in ipairs(rows) do if row.questID == id then return i end end
    end,
    IsOnQuest = function(id) return id ~= 14 end,
    IsComplete = function(id) return id == 20 and complete end,
    IsFailed = function(id) return id == 10 end,
    GetQuestObjectives = function(id)
        assert(id == 20)
        return {
            { text = "Supplies collected", type = "item", finished = false, numFulfilled = 2, numRequired = 5 },
            { text = secret }, secret, { text = "Camp found", type = "event", finished = true },
        }
    end,
    GetNextWaypointText = function(id) if id == 20 then return "Enter the mine." end end,
}
C_SuperTrack = { GetSuperTrackedQuestID = function() return 20 end }
GetQuestLogQuestText = function(index)
    assert(index == 7)
    return "The surveyor left his kit near the entrance.", "Collect supplies from the mine."
end
GetQuestLogSpecialItemInfo = function(index)
    assert(index == 7)
    return itemLink, 12345, 1, showItemWhenComplete
end
GetQuestLogCompletionText = function(index)
    assert(index == 7)
    return "Return to the surveyor."
end

local quests = ns.ListQuests()
assert(#quests == 2 and quests[1].id == 10 and quests[2].id == 20)
assert(quests[2].title == "Gather supplies" and ns.ReadQuest(10).failed)
assert(ns.SelectedQuestID() == 10 and ns.WatchedQuestID() == 20)
local quest = ns.ReadQuest(20)
assert(quest.complete == false and quest.description:find("entrance") and quest.instructions:find("mine"))
assert(quest.item == itemLink and quest.waypoint == "Enter the mine." and quest.completionText == nil)
assert(#quest.objectives == 2 and quest.objectives[1].type == "item" and quest.objectives[1].finished == false)
assert(quest.objectives[1].numFulfilled == 2 and quest.objectives[1].numRequired == 5)
assert(quest.objectives[2].finished == true and ns.SelectedQuestID() == 10 and mutations == 0)
assert(ns.ReadQuest(11) == nil and ns.ReadQuest(14) == nil and ns.ReadQuest(1000) == nil)
assert(ns.ReadQuest(secret) == nil)

complete = true
quest = ns.ReadQuest(20)
assert(quest.complete and quest.completionText == "Return to the surveyor." and quest.item == nil)
showItemWhenComplete = true
assert(ns.ReadQuest(20).item == itemLink)

C_QuestLog.GetNextWaypointText = nil
C_QuestLog.GetNextWaypoint = function() return 42, .125, .48 end
C_Map = { GetMapInfo = function(id) assert(id == 42); return { name = "Test Forest" } end }
assert(ns.ReadQuest(20).waypoint == "Test Forest (12.5, 48.0)")
C_QuestLog.GetNextWaypoint = function() return 42, secret, .48 end
GetQuestLogQuestText = function() return secret, secret end
C_QuestLog.GetQuestObjectives = function() error("data loading") end
quest = ns.ReadQuest(20)
assert(quest.waypoint == nil and quest.description == nil and quest.instructions == nil and #quest.objectives == 0)
GetNumQuestLeaderBoards = function(index) assert(index == 7); return 1 end
GetQuestLogLeaderBoard = function(n, index)
    assert(n == 1 and index == 7)
    return "Survey kit: 1/2", "item", false
end
quest = ns.ReadQuest(20)
assert(#quest.objectives == 1 and quest.objectives[1].text == "Survey kit: 1/2")

-- After turn-in, a reused index must never produce another quest's details.
C_QuestLog.GetLogIndexForQuestID = function() return 2 end
assert(ns.ReadQuest(20) == nil and mutations == 0)
C_QuestLog, C_SuperTrack = nil, nil
assert(#ns.ListQuests() == 0 and ns.ReadQuest(20) == nil)
assert(ns.SelectedQuestID() == nil and ns.WatchedQuestID() == nil)
print("QuestTips quest log and objective adapter passed.")
