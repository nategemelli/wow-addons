local addonName, ns = ...

-- "log" follows Blizzard's details pane. "field" stays open while you play.
local mode, detailID, browsedID, displayedID, lastFieldDetail
local refreshPending, hookedDetails, hookedShowQuest

local function IndexOf(quests, questID)
    if not questID then return nil end
    for index, quest in ipairs(quests) do
        if quest.id == questID then return index end
    end
end

local function Refresh(step)
    if not mode then return end
    local quests = ns.ListQuests()
    local wanted = browsedID or detailID or lastFieldDetail or ns.SelectedQuestID()
    local quest = wanted and ns.ReadQuest(wanted)
    if not quest then
        if mode == "log" then
            -- Map details can also describe quests the character hasn't accepted.
            displayedID = nil
            ns.HideWindow()
            return
        end
        browsedID, lastFieldDetail = nil, nil
        local selectedID = ns.SelectedQuestID()
        if selectedID and selectedID ~= wanted then quest = ns.ReadQuest(selectedID) end
        if not quest then
            local watchedID = ns.WatchedQuestID and ns.WatchedQuestID()
            if watchedID then quest = ns.ReadQuest(watchedID) end
        end
        if not quest and quests[1] then quest = ns.ReadQuest(quests[1].id) end
    end

    if not quest then
        displayedID = nil
        ns.Render({title = "Quest log", position = "", canBrowse = false, lines = {
            {label = "", text = "Accept a quest or open an accepted quest in your log to see its tips."},
        }})
        return
    end

    local index = IndexOf(quests, quest.id)
    if not index then
        -- A focused, accepted quest may be inside a collapsed log header.
        quests[#quests + 1] = quest
        index = #quests
    end
    if step and #quests > 1 then
        local nextIndex = (index - 1 + step) % #quests + 1
        local nextQuest = ns.ReadQuest(quests[nextIndex].id)
        if nextQuest then
            index, quest, browsedID = nextIndex, nextQuest, nextQuest.id
        end
    end
    displayedID = quest.id
    ns.Render({
        id = quest.id, title = quest.title, position = index .. " / " .. #quests,
        canBrowse = #quests > 1, lines = ns.GuideLines(quest),
    })
end

local function RefreshSoon()
    if not mode or refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        Refresh()
    end)
end

function ns.Close()
    mode, browsedID, displayedID, lastFieldDetail = nil, nil, nil, nil
    ns.HideWindow()
end

function ns.FollowSelection()
    mode, browsedID, lastFieldDetail = "field", nil, nil
    Refresh()
end

function ns.Step(direction)
    if not mode then return end
    mode, browsedID = "field", displayedID
    Refresh(direction)
end

local function DetailHidden()
    if mode == "field" and displayedID == detailID then lastFieldDetail = detailID end
    detailID = nil
    if mode == "log" then ns.Close() end
end

local function DetailShown(questID)
    local details = QuestMapFrame and QuestMapFrame.DetailsFrame
    if not details or not details:IsVisible() then return end
    if issecretvalue and issecretvalue(questID) then return end
    if type(questID) ~= "number" or questID <= 0 or detailID == questID then return end
    detailID, lastFieldDetail = questID, nil
    if not mode and QuestTipsDB.autoShow then mode = "log" end
    RefreshSoon()
end

local function HookQuestDetails()
    local details = QuestMapFrame and QuestMapFrame.DetailsFrame
    if details and not hookedDetails then
        hookedDetails = true
        details:HookScript("OnShow", function(self) DetailShown(self.questID) end)
        details:HookScript("OnHide", DetailHidden)
        DetailShown(details.questID)
    end
    if not hookedShowQuest and type(QuestMapFrame_ShowQuestDetails) == "function" then
        hookedShowQuest = true
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", DetailShown)
    end
end

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100QuestTips|r  " .. message)
end

local function Command(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if command == "" then
        ns.FollowSelection()
    elseif command == "hide" then
        ns.Close()
    elseif command == "auto on" then
        QuestTipsDB.autoShow = true
        if not mode and detailID then
            mode = "log"
            Refresh()
        end
        Print("Tips will open when you inspect an accepted quest.")
    elseif command == "auto off" then
        QuestTipsDB.autoShow = false
        if mode == "log" then ns.Close() end
        Print("Automatic tips are off. Use /qtips to open your guide.")
    else
        Print("/qtips opens the guide. Use /qtips hide to close it or /qtips auto on|off to change automatic tips.")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
for _, event in ipairs({
    "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
    "QUEST_WATCH_UPDATE", "QUEST_POI_UPDATE", "QUEST_DATA_LOAD_RESULT",
    "WAYPOINT_UPDATE", "SUPER_TRACKING_CHANGED",
}) do
    events:RegisterEvent(event)
end

local ready = false
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        if type(QuestTipsDB) ~= "table" then QuestTipsDB = {} end
        if type(QuestTipsDB.autoShow) ~= "boolean" then QuestTipsDB.autoShow = true end
        SLASH_QUESTTIPS1, SLASH_QUESTTIPS2 = "/qtips", "/questtips"
        SlashCmdList.QUESTTIPS = Command
        ready = true
    end
    if not ready then return end
    if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
        HookQuestDetails()
    else
        RefreshSoon()
    end
end)
