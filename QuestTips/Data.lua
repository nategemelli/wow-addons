local _, ns = ...

local function Query(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local function Readable(value)
    return not issecretvalue or not issecretvalue(value)
end

local function Text(value)
    if Readable(value) and type(value) == "string" and value:find("%S") then return value end
end

local function Number(value)
    if Readable(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge then
        return value
    end
end

local function ID(value)
    value = Number(value)
    if value and value > 0 and value % 1 == 0 then return value end
end

local function Bool(value)
    if Readable(value) and type(value) == "boolean" then return value end
end

local function QuestAtIndex(index)
    local info = C_QuestLog.GetInfo(index)
    if not Readable(info) or type(info) ~= "table" then return end
    if not Readable(info.isHeader) or not Readable(info.isHidden) or not Readable(info.isInternalOnly)
        or info.isHeader or info.isHidden or info.isInternalOnly then return end
    local id = ID(info.questID)
    if not id or Bool(Query(C_QuestLog.IsOnQuest, id)) == false then return end
    return {
        id = id,
        title = Text(info.title) or ("Quest " .. id),
    }
end

function ns.ListQuests()
    local quests, seen = {}, {}
    local count = Number(Query(C_QuestLog and C_QuestLog.GetNumQuestLogEntries)) or 0
    -- Some clients expose child rows under a collapsed header. Read every
    -- supplied index in order without changing the player's header state.
    for index = 1, count do
        local quest = Query(QuestAtIndex, index)
        if quest and not seen[quest.id] then
            quests[#quests + 1] = quest
            seen[quest.id] = true
        end
    end
    return quests
end

function ns.SelectedQuestID()
    return ID(Query(C_QuestLog and C_QuestLog.GetSelectedQuest))
end

function ns.WatchedQuestID()
    return ID(Query(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID))
end

local function ObjectiveAtIndex(rows, index)
    local row = rows[index]
    if not Readable(row) or type(row) ~= "table" then return end
    local text = Text(row.text)
    if text then
        return {
            text = text, type = Text(row.type), finished = Bool(row.finished),
            numFulfilled = Number(row.numFulfilled), numRequired = Number(row.numRequired),
        }
    end
end

local function ReadObjectives(id, logIndex)
    local objectives = {}
    local rows = Query(C_QuestLog.GetQuestObjectives, id)
    if Readable(rows) and type(rows) == "table" then
        local count = Query(function() return #rows end) or 0
        for index = 1, count do
            local row = Query(ObjectiveAtIndex, rows, index)
            if row then objectives[#objectives + 1] = row end
        end
    end
    -- The Forever quest map also reads objective rows by log index.
    if #objectives == 0 then
        local count = Number(Query(GetNumQuestLeaderBoards, logIndex)) or 0
        for index = 1, count do
            local text, kind, finished = Query(GetQuestLogLeaderBoard, index, logIndex)
            text = Text(text)
            if text then
                objectives[#objectives + 1] = {text = text, type = Text(kind), finished = Bool(finished)}
            end
        end
    end
    return objectives
end

local function ReadWaypoint(id)
    local label = Text(Query(C_QuestLog.GetNextWaypointText, id))
    if label then return label end
    local mapID, x, y = Query(C_QuestLog.GetNextWaypoint, id)
    mapID, x, y = ID(mapID), Number(x), Number(y)
    if not mapID or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then return end
    local map = Query(C_Map and C_Map.GetMapInfo, mapID)
    if Readable(map) and type(map) == "table" then
        local name = Text(map.name)
        if name then return string.format("%s (%.1f, %.1f)", name, x * 100, y * 100) end
    end
end

function ns.ReadQuest(id)
    id = ID(id)
    if not id then return end
    local index = ID(Query(C_QuestLog and C_QuestLog.GetLogIndexForQuestID, id))
    if not index then return end
    local quest = Query(QuestAtIndex, index)
    if not quest or quest.id ~= id then return end
    quest.complete = Bool(Query(C_QuestLog.IsComplete, id))
    quest.failed = Bool(Query(C_QuestLog.IsFailed, id))

    -- The native map reads these by log index, including for unselected quests.
    local description, instructions = Query(GetQuestLogQuestText, index)
    quest.description, quest.instructions = Text(description), Text(instructions)
    quest.objectives = ReadObjectives(id, index)
    quest.waypoint = Query(ReadWaypoint, id)
    if quest.complete then quest.completionText = Text(Query(GetQuestLogCompletionText, index)) end

    local link, _, _, showWhenComplete = Query(GetQuestLogSpecialItemInfo, index)
    if not quest.complete or Bool(showWhenComplete) then quest.item = Text(link) end
    return quest
end
