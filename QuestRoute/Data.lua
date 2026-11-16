local _, ns = ...

-- Only readable primitives leave this adapter. Restricted values never become
-- table keys, comparisons, coordinates, or saved route data.
function ns.Readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

function ns.Query(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
    ns.queryFailures = (ns.queryFailures or 0) + 1
end

local function Number(value)
    if not ns.Readable(value) or type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function ID(value)
    value = Number(value)
    if value and value > 0 and value % 1 == 0 then return value end
end

local function Text(value)
    if ns.Readable(value) and type(value) == "string" and value ~= "" then
        return (value:gsub("|", "||"))
    end
end

local function Bool(value)
    if ns.Readable(value) and type(value) == "boolean" then return value end
end

local function Field(value, key)
    if not ns.Readable(value) or type(value) ~= "table" then return nil end
    local ok, result = pcall(function() return value[key] end)
    if ok then return result end
end

local function Coordinates(x, y)
    x, y = Number(x), Number(y)
    if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 and (x ~= 0 or y ~= 0) then
        return x, y
    end
end

local function VectorXY(vector)
    if not ns.Readable(vector) then return nil end
    local getXY = Field(vector, "GetXY")
    local x, y = ns.Query(getXY, vector)
    return Number(x), Number(y)
end

local function AddWorldPosition(point)
    if not point.mapID or not point.x or not point.y then return end
    local vector = ns.Query(CreateVector2D, point.x, point.y)
    if not ns.Readable(vector) or type(vector) ~= "table" then return end
    local continent, position = ns.Query(C_Map and C_Map.GetWorldPosFromMapPos, point.mapID, vector)
    -- The native API calls this continentID. This is the common coordinate
    -- space identifier, NOT a UI map ID or a connection between continents.
    continent = Number(continent)
    local x, y = VectorXY(position)
    if continent and x and y then
        point.instanceID, point.worldX, point.worldY = continent, x, y
    end
end

local function MapName(mapID)
    if not mapID then return nil end
    return Text(Field(ns.Query(C_Map and C_Map.GetMapInfo, mapID), "name"))
end

local function PlayerPosition()
    local player = { mapID = ID(ns.Query(C_Map and C_Map.GetBestMapForUnit, "player")) }
    if player.mapID then
        local vector = ns.Query(C_Map and C_Map.GetPlayerMapPosition, player.mapID, "player")
        player.x, player.y = Coordinates(VectorXY(vector))
        AddWorldPosition(player)
    end
    return player
end

local function ReadObjectives(questID, complete)
    if complete then return 0, "Ready to turn in" end
    local objectives = ns.Query(C_QuestLog and C_QuestLog.GetQuestObjectives, questID)
    if not ns.Readable(objectives) or type(objectives) ~= "table" then return nil, nil end
    local left, firstText, known, count = 0, nil, true, 0
    for index = 1, 128 do
        local objective = Field(objectives, index)
        if ns.Readable(objective) and objective == nil then break end
        count = count + 1
        if not ns.Readable(objective) or type(objective) ~= "table" then
            known = false
        else
            local finished = Bool(Field(objective, "finished"))
            if finished == nil then
                known = false
            elseif not finished then
                left = left + 1
                firstText = firstText or Text(Field(objective, "text"))
            end
        end
    end
    return known and count > 0 and left or nil, firstText
end

local function ReadLevel(info, questID, playerLevel)
    local level = Number(ns.Query(C_QuestLog and C_QuestLog.GetQuestDifficultyLevel, questID))
    if not level or level <= 0 then level = Number(Field(info, "difficultyLevel")) end
    if not level or level <= 0 then level = Number(Field(info, "level")) end
    if level and level > 0 then return level end
    -- Scaling quests without a positive native difficulty level are treated as
    -- player-level only when the client explicitly identifies them as scaling.
    if Bool(Field(info, "isScaling")) and playerLevel > 0 then return playerLevel end
end

local function POIsForMap(mapID, cache)
    if cache[mapID] then return cache[mapID] end
    local result = {}
    local pois = ns.Query(C_QuestLog and C_QuestLog.GetQuestsOnMap, mapID)
    for index = 1, 512 do
        local poi = Field(pois, index)
        if ns.Readable(poi) and poi == nil then break end
        local questID = ID(Field(poi, "questID"))
        local x, y = Coordinates(Field(poi, "x"), Field(poi, "y"))
        if questID and x and y and Bool(Field(poi, "isQuestStart")) ~= true
            and Bool(Field(poi, "isMapIndicatorQuest")) ~= true then
            -- As in Blizzard's QuestDataProvider, coordinates belong to the
            -- queried map; poi.mapID may instead identify a child map.
            result[questID] = { mapID = mapID, x = x, y = y }
        end
    end
    cache[mapID] = result
    return result
end

local function ReadLocation(quest, playerMap, poiMap, cache)
    local waypointMap, waypointX, waypointY = ns.Query(C_QuestLog and C_QuestLog.GetNextWaypoint, quest.id)
    waypointMap = ID(waypointMap)
    local x, y = Coordinates(waypointX, waypointY)
    local questMap = ID(ns.Query(GetQuestUiMapID, quest.id))
    if waypointMap and x and y then
        quest.mapID, quest.x, quest.y = waypointMap, x, y
        quest.locationSource = "Next quest waypoint"
    else
        quest.mapID = questMap or waypointMap
        local candidates, seen = {}, {}
        for _, candidate in ipairs({ questMap or 0, waypointMap or 0, playerMap or 0, poiMap or 0 }) do
            if candidate > 0 and not seen[candidate] then
                candidates[#candidates + 1] = candidate
                seen[candidate] = true
            end
        end
        for _, mapID in ipairs(candidates) do
            local nextX, nextY = ns.Query(C_QuestLog and C_QuestLog.GetNextWaypointForMap, quest.id, mapID)
            x, y = Coordinates(nextX, nextY)
            if x and y then
                quest.mapID, quest.x, quest.y = mapID, x, y
                quest.locationSource = "Next quest waypoint"
                break
            end
            local poi = POIsForMap(mapID, cache)[quest.id]
            if poi then
                quest.mapID, quest.x, quest.y = mapID, poi.x, poi.y
                quest.locationSource = "Quest map pin"
                break
            end
        end
    end
    quest.mapName = MapName(quest.mapID)
    quest.zone = quest.mapName or quest.zone
    if quest.x and quest.y then
        AddWorldPosition(quest)
        quest.locationReason = "Native next destination; may be a travel waypoint or an objective-area marker."
    else
        quest.locationReason = "No readable quest coordinates; grouped by area only."
    end
end

function ns.CollectQuests()
    local quests, seen, poiCache = {}, {}, {}
    local level = Number(ns.Query(UnitLevel, "player")) or 0
    if level < 1 then level = 0 end
    local context = { playerLevel = level, player = PlayerPosition(), warnings = {} }
    if level == 0 then
        context.warnings[#context.warnings + 1] = "Player level unavailable; difficulty cannot be compared."
    end
    if not context.player.x then
        context.warnings[#context.warnings + 1] = "Player position unavailable; route starts with an area cluster."
    end
    local entries = Number(ns.Query(C_QuestLog and C_QuestLog.GetNumQuestLogEntries))
    if not entries then
        context.unavailable = true
        context.warnings[#context.warnings + 1] = "Quest log is unavailable. Try generating again outside combat."
        return quests, context
    end
    if entries > 0 and type(C_QuestLog and C_QuestLog.GetInfo) ~= "function" then
        context.unavailable = true
        context.warnings[#context.warnings + 1] = "Quest-log entries cannot be read on this client."
        return quests, context
    end
    local poiMap = ID(ns.Query(C_QuestLog and C_QuestLog.GetMapForQuestPOIs))
    local zone, omitted, missing, failed = "Unknown area", 0, 0, 0
    local failuresBefore = ns.queryFailures or 0
    for index = 1, math.min(1024, math.max(0, math.floor(entries))) do
        local info = ns.Query(C_QuestLog and C_QuestLog.GetInfo, index)
        if Bool(Field(info, "isHeader")) == true then
            zone = Text(Field(info, "title")) or "Unknown area"
        elseif ns.Readable(info) and type(info) == "table" then
            local questID = ID(Field(info, "questID"))
            local hidden = Bool(Field(info, "isHidden"))
            local internal = Bool(Field(info, "isInternalOnly"))
            local flagsReadable = ns.Readable(Field(info, "isHeader"))
                and ns.Readable(Field(info, "isHidden")) and ns.Readable(Field(info, "isInternalOnly"))
            if questID and flagsReadable and hidden ~= true and internal ~= true and not seen[questID] then
                seen[questID] = true
                if Bool(ns.Query(C_QuestLog and C_QuestLog.IsFailed, questID)) == true then
                    failed = failed + 1
                else
                    local complete = Bool(ns.Query(C_QuestLog and C_QuestLog.IsComplete, questID)) == true
                    local quest = {
                        id = questID,
                        title = Text(Field(info, "title")) or ("Quest " .. questID),
                        level = ReadLevel(info, questID, level),
                        zone = zone,
                        complete = complete,
                        groupSize = Number(ns.Query(C_QuestLog and C_QuestLog.GetSuggestedGroupSize, questID))
                            or Number(Field(info, "suggestedGroup")),
                    }
                    quest.objectivesLeft, quest.objectiveText = ReadObjectives(questID, complete)
                    ReadLocation(quest, context.player.mapID, poiMap, poiCache)
                    if not quest.x then missing = missing + 1 end
                    quests[#quests + 1] = quest
                end
            elseif not questID or not flagsReadable then
                omitted = omitted + 1
            end
        else
            omitted = omitted + 1
        end
    end
    if omitted > 0 then
        context.warnings[#context.warnings + 1] = omitted .. " quest-log entries were unreadable and could not be scheduled."
        if #quests == 0 and failed == 0 then context.unavailable = true end
    end
    if failed > 0 then
        context.warnings[#context.warnings + 1] = failed .. " failed quests were excluded; restart them before scheduling."
    end
    if missing > 0 then
        context.warnings[#context.warnings + 1] = missing .. " quests have no coordinates; their area grouping is approximate."
    end
    if (ns.queryFailures or 0) > failuresBefore then
        context.warnings[#context.warnings + 1] = "Some quest data was unavailable; regenerate when the quest log has loaded."
    end
    return quests, context
end

-- This helper is used only by explicit quest/map button clicks, never a scan.
function ns.OpenQuest(quest)
    local questID = ID(Field(quest, "id"))
    if not questID then return false, "No quest is selected." end
    if Bool(ns.Query(InCombatLockdown)) then
        return false, "Open quest details outside combat."
    end
    if type(QuestMapFrame_OpenToQuestDetails) == "function" then
        local ok = pcall(QuestMapFrame_OpenToQuestDetails, questID)
        if ok then return true end
    end
    local mapID = ID(Field(quest, "mapID"))
    if mapID and C_Map and type(C_Map.OpenWorldMap) == "function" then
        local ok = pcall(C_Map.OpenWorldMap, mapID)
        if ok then return true end
    end
    return false, "Quest details are unavailable. Open the quest log to inspect this quest."
end
