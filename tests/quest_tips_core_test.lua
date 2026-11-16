-- Exercise the native quest-detail hooks and field window with a changing log.
local frame, details, detailHook, pending, command, view
local ns, rows, inspected, tracked, reads, visible
local function boot(withMap, saved)
    pending, rows, reads, visible = {}, {}, 0, true
    detailHook, view, inspected, tracked = nil, nil, nil, nil
    QuestTipsDB, SlashCmdList = saved, {}
    DEFAULT_CHAT_FRAME = { AddMessage = function() end }
    C_Timer = { After = function(_, callback) table.insert(pending, callback) end }
    CreateFrame = function()
        frame = {
            events = {},
            RegisterEvent = function(self, event) self.events[event] = true end,
            SetScript = function(self, _, callback) self.fire = callback end,
        }
        return frame
    end
    details = {
        HookScript = function(self, script, callback) self[script] = callback end,
        IsVisible = function() return visible end,
    }
    QuestMapFrame = withMap and {DetailsFrame = details} or nil
    QuestMapFrame_ShowQuestDetails = withMap and function() end or nil
    hooksecurefunc = function(name, callback)
        assert(name == "QuestMapFrame_ShowQuestDetails" and not detailHook)
        detailHook = callback
    end
    ns = {
        ListQuests = function()
            reads = reads + 1
            local copy = {}
            for i, row in ipairs(rows) do copy[i] = row end
            return copy
        end,
        SelectedQuestID = function() return inspected end,
        WatchedQuestID = function() return tracked end,
        ReadQuest = function(id)
            for _, row in ipairs(rows) do if row.id == id then return row end end
        end,
        GuideLines = function(q) return {{label = "", text = q.note or "hint"}} end,
        Render = function(v) view = v end,
        HideWindow = function() view = nil end,
    }
    assert(loadfile(TEST_ROOT .. "/QuestTips/Core.lua"))("QuestTips", ns)
    frame:fire("ADDON_LOADED", "QuestTips")
    command = assert(SlashCmdList.QUESTTIPS)
end

local function flush()
    while #pending > 0 do table.remove(pending, 1)() end
end
local function showDetail(id)
    inspected, details.questID, visible = id, id, true
    details:OnShow()
    detailHook(id)
    flush()
end
local function hideDetail()
    visible = false
    details:OnHide()
end
local function quests()
    rows = {{id = 10, title = "First"}, {id = 20, title = "Sarkoth"}, {id = 30, title = "Sarkoth"}}
end

boot(true)
assert(QuestTipsDB.autoShow and SLASH_QUESTTIPS1 == "/qtips")
frame:fire("QUEST_LOG_UPDATE")
assert(reads == 0 and #pending == 0, "closed guide should never scan the quest log")
quests()
showDetail(20)
assert(view.id == 20 and view.canBrowse and view.position == "2 / 3")
frame:fire("QUEST_LOG_UPDATE")
rows[2].note = "new progress"
frame:fire("QUEST_WATCH_UPDATE")
assert(#pending == 1, "related events should refresh together")
flush()
assert(view.lines[1].text == "new progress")
ns.Close()
detailHook(20)
frame:fire("QUEST_POI_UPDATE")
flush()
assert(not view, "Blizzard refresh of the same quest should respect the close button")
showDetail(30)
assert(view.id == 30)
hideDetail()
assert(not view, "automatic guide should close with native details")
showDetail(999)
assert(not view, "an unaccepted quest must not display another quest's hint")

showDetail(10)
ns.Step(-1)
assert(view.id == 30)
showDetail(20)
assert(view.id == 30, "browsing should keep the chosen quest")
hideDetail()
assert(view.id == 30, "field guide stays open while playing")
ns.FollowSelection()
assert(view.id == 20)
ns.Step(1)
table.remove(rows)
frame:fire("QUEST_REMOVED", 30)
flush()
assert(view.id == 20 and view.position == "2 / 2", "abandoned quest should disappear")
command("hide")
command("auto off")
showDetail(10)
assert(not view and QuestTipsDB.autoShow == false)
command("")
assert(view.id == 10, "manual guide still works with automatic tips off")
hideDetail()
inspected, tracked = nil, 30
frame:fire("QUEST_LOG_UPDATE")
flush()
assert(view.id == 10, "closing the map must keep the field guide on the same quest")
showDetail(20)
assert(view.id == 20, "inspecting a new quest should resume following the quest log")
showDetail(10)
ns.Close()
command("auto on")
assert(view.id == 10, "enabling auto while inspecting a quest should take effect now")
hideDetail()

boot(false, {autoShow = false})
assert(not QuestTipsDB.autoShow and not detailHook)
command("")
assert(view.title == "Quest log" and not view.canBrowse)
quests()
tracked = 30
frame:fire("QUEST_ACCEPTED")
flush()
assert(view.id == 30, "missing selection should use the tracked quest")
tracked = nil
frame:fire("SUPER_TRACKING_CHANGED")
flush()
assert(view.id == 10, "missing selection and tracking should use the first quest")
QuestMapFrame, QuestMapFrame_ShowQuestDetails = {DetailsFrame = details}, function() end
frame:fire("ADDON_LOADED", "Blizzard_UIPanels_Game")
frame:fire("PLAYER_LOGIN")
assert(detailHook and details.OnHide, "late-loaded native UI must be hooked once")
showDetail(20)
frame:fire("QUEST_LOG_UPDATE")
ns.Close()
flush()
assert(not view, "pending refresh should respect a closed window")
print("PASS QuestTips automatic and manual window behavior")
