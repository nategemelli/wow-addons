local addonName, ns = ...

local state, ui

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100QuestRoute:|r " .. message)
    end
end

local function CopyOptions(options)
    return ns.NormalizeOptions(options)
end

local function SavedPlan(plan)
    if type(plan) ~= "table" or type(plan.steps) ~= "table" or #plan.steps > 200 then return nil end
    local copy = { steps = {}, stats = {}, options = CopyOptions(plan.options) }
    -- SavedVariables contain only a plain snapshot, never native map vectors.
    for _, step in ipairs(plan.steps) do
        if type(step) ~= "table" or type(step.id) ~= "number" or type(step.title) ~= "string" then return nil end
        local item = {}
        for key, value in pairs(step) do
            local kind = type(value)
            if type(key) == "string" and (kind == "string" or kind == "boolean"
                or (kind == "number" and value == value and math.abs(value) < math.huge)) then item[key] = value end
        end
        copy.steps[#copy.steps + 1] = item
    end
    if type(plan.stats) == "table" then
        for key, value in pairs(plan.stats) do
            if type(key) == "string" and type(value) == "number" and value == value and math.abs(value) < math.huge then
                copy.stats[key] = value
            end
        end
    end
    copy.stats.total = #copy.steps
    return copy
end

local function Render()
    if ui then ui:Render(state) end
end

function ns.OpenPlanner()
    if not state then return end
    state.visible, state.expanded = true, true
    Render()
end

function ns.Minimize()
    if not state then return end
    state.visible, state.expanded = true, false
    Render()
end

function ns.SetOption(key, value)
    if not state then return end
    local options = CopyOptions(state.options)
    options[key] = value
    if key == "mode" and options.optimization == "multi" then
        options.customWeights, options.weights = false, nil
    end
    QuestRouteDB.options = CopyOptions(options)
    state.options = QuestRouteDB.options
    if state.plan then state.dirty = true end
    state.status = "Options changed. Generate a new route to apply them."
    Render()
end

function ns.SetWeight(key, value)
    if not state or state.options.optimization ~= "multi" then return end
    if key ~= "travel" and key ~= "level" and key ~= "work" and key ~= "density" then return end
    local options = CopyOptions(state.options)
    options.customWeights = true
    options.weights[key] = value
    QuestRouteDB.options = CopyOptions(options)
    state.options = QuestRouteDB.options
    if state.plan then state.dirty = true end
    state.status = "Weights changed. Generate a new route to apply them."
    Render()
end

function ns.SelectStep(index)
    if not state or not state.plan or #state.plan.steps == 0 then return end
    state.current = math.max(1, math.min(#state.plan.steps, index))
    if not state.demo then QuestRouteDB.current = state.current end
    Render()
end

function ns.ShowStep()
    local step = state and state.plan and state.plan.steps[state.current]
    if not step then return end
    if state.demo then Print("Sample quests have no live quest details. Generate a route from your log."); return end
    local ok, reason = ns.OpenQuest(step)
    if not ok then Print(reason or "Quest details are unavailable.") end
end

function ns.Generate()
    if not state then return end
    state.visible, state.expanded = true, true
    -- Route generation is always an explicit click or slash command.
    if InCombatLockdown and InCombatLockdown() then
        state.status = "Leave combat to generate a route."
        Render()
        return
    end
    local ok, quests, context = pcall(ns.CollectQuests)
    if not ok or context.unavailable then
        state.status = "Could not read your quest log. Your previous route is kept; try again when the log has loaded."
        Print(state.status)
        Render()
        return
    end
    local planned, plan = pcall(ns.Optimize, quests, context, CopyOptions(state.options))
    if not planned then
        state.status = "Could not build a route. Your previous schedule is still available."
        Print(state.status)
        Render()
        return
    end
    state.plan, state.current, state.dirty, state.demo = plan, 1, false, false
    state.playerLevel = context.playerLevel
    state.warnings = context.warnings or {}
    state.visible, state.expanded = true, true
    state.status = #plan.steps == 0 and "Your quest log has no schedulable quests." or "Route ready. Use Route returns to the compact view."
    QuestRouteDB.plan = SavedPlan(plan)
    QuestRouteDB.current = 1
    QuestRouteDB.playerLevel = state.playerLevel
    Render()
end

function ns.Demo()
    if not state then return end
    local quests = {
        { id = 900001, title = "Wolves at the farm", level = 12, mapID = 1, mapName = "Sample: Greenvale", zone = "Greenvale", x = 0.25, y = 0.34, objectivesLeft = 1 },
        { id = 900002, title = "Gather healing herbs", level = 11, mapID = 1, mapName = "Sample: Greenvale", zone = "Greenvale", x = 0.28, y = 0.36, objectivesLeft = 2 },
        { id = 900003, title = "Report to the captain", level = 12, mapID = 1, mapName = "Sample: Greenvale", zone = "Greenvale", x = 0.46, y = 0.51, complete = true, objectivesLeft = 0 },
        { id = 900004, title = "Scouts at the watchtower", level = 13, mapID = 1, mapName = "Sample: Greenvale", zone = "Greenvale", x = 0.49, y = 0.55, objectivesLeft = 1 },
        { id = 900005, title = "The ogre stronghold", level = 14, mapID = 1, mapName = "Sample: Greenvale", zone = "Greenvale", x = 0.27, y = 0.35, objectivesLeft = 2, groupSize = 3 },
        { id = 900006, title = "A forgotten trail", level = 12, zone = "Distant Highlands", locationReason = "No waypoint supplied by the game.", objectivesLeft = 1 },
    }
    local context = { playerLevel = 12, player = { mapID = 1, x = 0.23, y = 0.31 } }
    state.plan = ns.Optimize(quests, context, CopyOptions(state.options))
    state.current, state.playerLevel, state.demo, state.dirty = 1, 12, true, false
    state.warnings = {}
    state.status = "SAMPLE ROUTE - fictional quests. Your saved route has not changed."
    state.visible, state.expanded = true, true
    Render()
end

local function MarkStale()
    if not state or not state.plan or state.demo then return end
    state.dirty = true
    state.status = "Quest log or level changed. Generate again when you want an updated route."
    Render()
end

local function Command(message)
    local command = (message or ""):lower():match("^%s*(%S*)")
    if command == "generate" or command == "plan" then ns.Generate()
    elseif command == "min" or command == "minimize" or command == "show" then ns.Minimize()
    elseif command == "hide" then state.visible = false; Render()
    elseif command == "next" then ns.SelectStep(state.current + 1)
    elseif command == "prev" then ns.SelectStep(state.current - 1)
    elseif command == "test" or command == "demo" then ns.Demo()
    elseif command == "help" then
        Print("/qr opens the planner; /qr generate builds a route; /qr min returns to compact view; /qr next or prev changes the step; /qr test shows sample quests; /qr hide hides both windows.")
    else ns.OpenPlanner() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addonName or state then return end
        if type(QuestRouteDB) ~= "table" then QuestRouteDB = {} end
        QuestRouteDB.options = CopyOptions(QuestRouteDB.options)
        local plan = SavedPlan(QuestRouteDB.plan)
        local current = type(QuestRouteDB.current) == "number" and QuestRouteDB.current or 1
        if current ~= current or math.abs(current) == math.huge then current = 1 end
        current = math.max(1, math.min(plan and #plan.steps or 1, math.floor(current)))
        state = { options = QuestRouteDB.options, plan = plan, current = current, expanded = false,
            visible = true, dirty = plan ~= nil, demo = false, playerLevel = QuestRouteDB.playerLevel,
            warnings = {}, status = plan and "Saved route. Generate again to refresh it." or "Choose your preferences, then generate a route." }
        ui = ns.CreateUI(QuestRouteDB, {
            open = ns.OpenPlanner, minimize = ns.Minimize, generate = ns.Generate, option = ns.SetOption, weight = ns.SetWeight,
            select = ns.SelectStep, details = ns.ShowStep,
            next = function() ns.SelectStep(state.current + 1) end,
            previous = function() ns.SelectStep(state.current - 1) end,
        })
        SLASH_QUESTROUTE1, SLASH_QUESTROUTE2 = "/questroute", "/qr"
        SlashCmdList.QUESTROUTE = Command
        events:RegisterEvent("QUEST_LOG_UPDATE")
        events:RegisterEvent("PLAYER_LEVEL_UP")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        Render()
    else MarkStale() end
end)
