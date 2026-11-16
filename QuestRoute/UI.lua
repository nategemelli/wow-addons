local addonName, ns = ...

local gold, light, muted = { 1, 0.82, 0 }, { 0.92, 0.87, 0.76 }, { 0.67, 0.63, 0.55 }
local modeOrder = { "balanced", "distance", "level", "time" }
local singleModeOrder = { "distance", "level", "time" }
local optimizationOrder = { "multi", "single" }
local optimizationLabels = { multi = "Multi-objective", single = "Single-objective" }
local modeLabels = { balanced = "Balanced", distance = "Shortest travel", level = "Safer levels", time = "Time / effort" }
local singleHints = {
    distance = "Score travel only, with grouping and the hard-quest rule still applied.",
    level = "Score quest difficulty only, with grouping and the hard-quest rule still applied.",
    time = "Score estimated objective effort only; excludes travel and is not an ETA. Grouping and the hard-quest rule still apply.",
}
local clusterOrder = { "tight", "normal", "wide" }
local clusterLabels = { tight = "Tight", normal = "Normal", wide = "Wide" }

local function Text(parent, size, color)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetFont(STANDARD_TEXT_FONT, size)
    text:SetTextColor(unpack(color or light))
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local function Outline(control, inset, anchor)
    inset, anchor = inset or 0, anchor or control
    -- A mouse-disabled child keeps the edge above native hover/pressed art
    -- without stealing clicks from the control underneath.
    local border = CreateFrame("Frame", nil, control)
    border:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -inset)
    border:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, inset)
    border:EnableMouse(false)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = border:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(0, 0, 0, 1)
        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT")
            edge:SetPoint(side .. "RIGHT")
            edge:SetHeight(1)
        else
            edge:SetPoint("TOP" .. side)
            edge:SetPoint("BOTTOM" .. side)
            edge:SetWidth(1)
        end
    end
end

local function OutlineScroll(scroll)
    local bar = scroll.ScrollBar
    if not bar then return end
    for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
        if bar[key] then Outline(bar[key]) end
    end
    local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
    if thumb then Outline(bar, 0, thumb) end
end

local function Button(parent, label, width, fn)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetText(label)
    button:SetScript("OnClick", fn)
    Outline(button)
    return button
end

local function Tooltip(control, title, body)
    control:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(body, 0.9, 0.85, 0.73, true)
        GameTooltip:Show()
    end)
    control:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function Window(name, width, height, db, positionKey)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    local position = type(db[positionKey]) == "table" and db[positionKey] or {}
    local anchors = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
        TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
    local function Offset(value)
        return type(value) == "number" and value == value and math.abs(value) < math.huge and value or 0
    end
    frame:SetPoint(anchors[position.point] and position.point or "CENTER", UIParent,
        anchors[position.relativePoint] and position.relativePoint or "CENTER", Offset(position.x), Offset(position.y))
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", 12, -8)
    -- Reserve the right side for Plan/Minimize. A sibling drag frame must
    -- never overlap their hitboxes, regardless of frame stacking order.
    drag:SetPoint("TOPRIGHT", -112, -8)
    drag:SetHeight(32)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint(1)
        db[positionKey] = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)
    return frame, drag
end

local function Cycle(order, current)
    for i, value in ipairs(order) do if current == value then return order[i % #order + 1] end end
    return order[1]
end

local function Area(step)
    local name = step.mapName or step.zone or "Unknown area"
    if step.x and step.y then
        return string.format("%s  (%.1f, %.1f)", name, step.x * 100, step.y * 100)
    end
    return name .. "  - location unavailable"
end

local function Level(step, playerLevel)
    if not step.level or step.level <= 0 then return "Lv ?" end
    if type(playerLevel) == "number" and playerLevel > 0 and step.level > playerLevel then
        return string.format("Lv %d (+%d)", step.level, step.level - playerLevel)
    end
    return string.format("Lv %d", step.level)
end

local function Check(parent, label, y, fn)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", 22, y)
    local text = Text(check, 12, light)
    text:SetPoint("LEFT", check, "RIGHT", 5, 0)
    text:SetText(label)
    check:SetScript("OnClick", function(self) fn(self:GetChecked() == true) end)
    Outline(check, 4)
    return check
end

local function Row(parent, index, callbacks)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(488, 58)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * 60)
    Outline(row)
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    row:GetHighlightTexture():SetVertexColor(1, 0.82, 0.3, 0.1)
    row.number = Text(row, 14, gold)
    row.number:SetPoint("TOPLEFT", 8, -8)
    row.number:SetWidth(30)
    row.title = Text(row, 12, light)
    row.title:SetPoint("TOPLEFT", 40, -6)
    row.title:SetWidth(332)
    row.level = Text(row, 11, muted)
    row.level:SetPoint("TOPRIGHT", -7, -7)
    row.level:SetWidth(99)
    row.level:SetJustifyH("RIGHT")
    row.area = Text(row, 11, muted)
    row.area:SetPoint("TOPLEFT", 40, -24)
    row.area:SetWidth(439)
    row.reason = Text(row, 10, muted)
    row.reason:SetPoint("TOPLEFT", 40, -42)
    row.reason:SetWidth(376)
    row.selectHint = Text(row, 10, gold)
    row.selectHint:SetPoint("TOPRIGHT", -8, -42)
    row.selectHint:SetWidth(58)
    row.selectHint:SetJustifyH("RIGHT")
    row:SetScript("OnClick", function() callbacks.select(index) end)
    row:SetScript("OnEnter", function(self)
        if not self.step or not GameTooltip then return end
        local step = self.step
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(step.title)
        GameTooltip:AddLine(Area(step), 0.95, 0.86, 0.64, true)
        GameTooltip:AddLine(step.reason or "", 0.8, 0.8, 0.8, true)
        if step.objectiveText then GameTooltip:AddLine(step.objectiveText, 0.9, 0.9, 0.9, true) end
        if step.locationReason then GameTooltip:AddLine(step.locationReason, 0.9, 0.7, 0.4, true) end
        if step.locationSource then GameTooltip:AddLine("Location: " .. step.locationSource, 0.65, 0.65, 0.65, true) end
        if step.estimatedMinutes then
            GameTooltip:AddLine(string.format("Rough objective effort: %.0f min (excludes travel; not an ETA).", step.estimatedMinutes), 0.7, 0.7, 0.7, true)
        end
        GameTooltip:AddLine("Click to select this step. Details opens the game's quest view.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
end

function ns.CreateUI(db, callbacks)
    local currentState, updatingWeights
    local routeHeight = 206
    local full, drag = Window("QuestRoutePlanner", 560, 720, db, "plannerPosition")
    local header = CreateFrame("Frame", nil, drag, "DialogHeaderTemplate")
    header:ClearAllPoints()
    header:SetPoint("TOP", full, "TOP", 0, 6)
    header:SetWidth(250)
    header.Text:SetText("QUESTROUTE")
    local minimize = Button(full, "Minimize", 82, callbacks.minimize)
    minimize:SetPoint("TOPRIGHT", -18, -15)
    local introduction = Text(full, 12, muted)
    introduction:SetPoint("TOPLEFT", 26, -47)
    introduction:SetText("Plan your current quest log, then keep the route beside you.")

    local optimizationTitle = Text(full, 12, gold)
    optimizationTitle:SetPoint("TOPLEFT", 26, -80)
    optimizationTitle:SetText("Optimization")
    local optimization = Button(full, "Multi-objective", 180, function()
        callbacks.option("optimization", Cycle(optimizationOrder, currentState.options.optimization))
    end)
    optimization:SetPoint("TOPLEFT", 124, -72)
    Tooltip(optimization, "Optimization strategy", "Click to switch Single-objective and Multi-objective. Single scores one selected factor. Multi combines travel, level, effort, and area density. Grouping and the hard-quest rule apply to both. Generate again to update your route.")
    local modeTitle = Text(full, 12, gold)
    modeTitle:SetPoint("TOPLEFT", 26, -114)
    modeTitle:SetText("Emphasis")
    local mode = Button(full, "Balanced", 161, function()
        local order = currentState.options.optimization == "single" and singleModeOrder or modeOrder
        local custom = currentState.options.optimization == "multi" and currentState.options.customWeights
        callbacks.option("mode", custom and "balanced" or Cycle(order, currentState.options.mode))
    end)
    mode:SetPoint("TOPLEFT", 124, -106)
    Tooltip(mode, "Objective or emphasis", "Click to cycle presets. In Multi-objective, choosing a preset replaces all four slider values; Custom returns to Balanced. Single-objective scores only its selected factor, with the shared grouping and hard-quest rule. Generate again to apply.")
    local resetWeights = Button(full, "Reset to Balanced", 148, function() callbacks.option("mode", "balanced") end)
    resetWeights:SetPoint("TOPRIGHT", -28, -106)
    Tooltip(resetWeights, "Reset weights", "Restore the Balanced preset's four weights. Your existing route stays unchanged until you generate again.")
    local clusterTitle = Text(full, 12, gold)
    clusterTitle:SetPoint("TOPLEFT", 319, -80)
    clusterTitle:SetText("Grouping")
    local cluster = Button(full, "Normal", 118, function()
        callbacks.option("cluster", Cycle(clusterOrder, currentState.options.cluster))
    end)
    cluster:SetPoint("TOPLEFT", 414, -72)
    Tooltip(cluster, "Area grouping", "Click to cycle Tight, Normal, and Wide. Wider groups keep more nearby objectives together before leaving the area.")
    local modeHint = Text(full, 11, muted)
    modeHint:SetPoint("TOPLEFT", 26, -143)
    modeHint:SetSize(506, 28)
    modeHint:SetWordWrap(true)
    modeHint:SetJustifyV("TOP")
    local weightSliders = {}
    local function WeightSlider(key, name, label, x, y, help)
        local slider = CreateFrame("Slider", name, full, "UISliderTemplate")
        slider:SetPoint("TOPLEFT", x, y)
        slider:SetSize(236, 14)
        slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(0, 10)
        slider:SetValueStep(0.05)
        slider:SetObeyStepOnDrag(true)
        slider:SetHitRectInsets(0, 0, -2, -2)
        Outline(slider)
        local thumb = slider:GetThumbTexture()
        if thumb then Outline(slider, 8, thumb) end
        local title = Text(slider, 11, light)
        title:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 6)
        title:SetWidth(150)
        slider.valueText = Text(slider, 11, gold)
        slider.valueText:SetPoint("BOTTOMRIGHT", slider, "TOPRIGHT", 0, 6)
        slider.valueText:SetWidth(80)
        slider.valueText:SetJustifyH("RIGHT")
        title:SetText(label)
        Tooltip(slider, label .. " priority", help .. " Drag from 0 to 10; higher means more influence, and 0 removes this scoring factor. Shared grouping and hard-quest rules still apply. Generate Route applies the change.")
        slider:SetScript("OnValueChanged", function(_, value)
            if not updatingWeights and currentState and currentState.options.optimization == "multi" then
                callbacks.weight(key, value)
            end
        end)
        weightSliders[key] = slider
    end
    WeightSlider("travel", "QuestRouteWeightTravel", "Distance", 26, -196,
        "Favors shorter straight-line trips between quest destinations.")
    WeightSlider("level", "QuestRouteWeightLevel", "Quest level", 296, -196,
        "Favors quests at easier levels. The 2+ level rule remains active even at zero.")
    WeightSlider("work", "QuestRouteWeightWork", "Time / effort", 26, -240,
        "Favors lower estimated objective effort. This excludes travel and is not an ETA.")
    WeightSlider("density", "QuestRouteWeightDensity", "Clustering", 296, -240,
        "Favors areas containing more nearby quests. The Grouping button separately sets cluster size; zero removes only the density preference.")
    local hard = Check(full, "Defer quests 2+ levels above me", -267, function(value) callbacks.option("deferHard", value) end)
    Tooltip(hard, "Quest difficulty", "When checked, harder quests go after other quests. When unchecked, they can be mixed into nearby stops but still receive a difficulty penalty.")
    local turnins = Check(full, "Favor completed turn-ins (Multi-objective only)", -295, function(value) callbacks.option("preferTurnIns", value) end)
    Tooltip(turnins, "Completed quests", "Multi-objective can add a turn-in preference. Single-objective ignores this bonus so it does not add another goal; your saved choice is kept. Completed quests remain in both schedules, and Time / effort includes their interaction effort.")
    local generate = Button(full, "Generate Route", 154, callbacks.generate)
    generate:SetPoint("TOPLEFT", 26, -334)
    local count = Text(full, 11, gold)
    count:SetPoint("TOPLEFT", 193, -342)
    count:SetWidth(337)
    local status = Text(full, 11, muted)
    status:SetPoint("TOPLEFT", 26, -370)
    status:SetSize(506, 30)
    status:SetWordWrap(true)
    status:SetJustifyV("TOP")
    local routeTitle = Text(full, 11, gold)
    routeTitle:SetPoint("TOPLEFT", 26, -405)
    routeTitle:SetText("SCHEDULE")
    local routeMode = Text(full, 10, muted)
    routeMode:SetPoint("TOPRIGHT", -47, -405)
    routeMode:SetJustifyH("RIGHT")

    local inset = CreateFrame("Frame", nil, full, "BackdropTemplate")
    inset:SetPoint("TOPLEFT", 19, -417)
    inset:SetSize(520, routeHeight + 10)
    inset:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    inset:SetBackdropBorderColor(0.55, 0.49, 0.37, 1)
    local scroll = CreateFrame("ScrollFrame", nil, full, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 26, -422)
    scroll:SetSize(488, routeHeight)
    OutlineScroll(scroll)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(488, routeHeight)
    scroll:SetScrollChild(child)
    local empty = Text(child, 12, muted)
    empty:SetPoint("TOPLEFT", 18, -24)
    empty:SetSize(445, 60)
    empty:SetWordWrap(true)
    empty:SetJustifyV("TOP")
    local rows = {}
    local notice = CreateFrame("Frame", nil, full)
    notice:SetPoint("TOPLEFT", 26, -645)
    notice:SetSize(506, 27)
    notice:EnableMouse(true)
    local note = Text(notice, 10, muted)
    note:SetPoint("TOPLEFT")
    note:SetSize(506, 27)
    note:SetWordWrap(true)
    note:SetJustifyV("TOP")
    notice:SetScript("OnEnter", function(self)
        if not GameTooltip or not currentState then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Quest data and route limits")
        for _, warning in ipairs(currentState.warnings or {}) do
            GameTooltip:AddLine(warning, 0.95, 0.75, 0.4, true)
        end
        GameTooltip:AddLine("Each quest contributes its current native destination. Generate again after objectives change to find the next stop or turn-in.", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine("Distances are straight-line estimates. Terrain and transport are not included.", 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    notice:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local details = Button(full, "Quest Details", 122, callbacks.details)
    details:SetPoint("BOTTOMLEFT", 26, 19)
    local use = Button(full, "Use Route", 126, callbacks.minimize)
    use:SetPoint("BOTTOMRIGHT", -26, 19)
    local manual = Text(full, 10, muted)
    manual:SetPoint("BOTTOMLEFT", 165, 26)
    manual:SetWidth(220)
    manual:SetText("Updates only when you generate.")

    local compact = Window("QuestRouteCompact", 320, 132, db, "compactPosition")
    local miniTitle = Text(compact, 12, gold)
    miniTitle:SetPoint("TOPLEFT", 23, -18)
    miniTitle:SetText("QUESTROUTE")
    local plan = Button(compact, "Plan", 73, callbacks.open)
    plan:SetPoint("TOPRIGHT", -18, -12)
    local miniQuest = Text(compact, 12, light)
    miniQuest:SetPoint("TOPLEFT", 23, -47)
    miniQuest:SetWidth(274)
    local miniArea = Text(compact, 10, muted)
    miniArea:SetPoint("TOPLEFT", 23, -66)
    miniArea:SetWidth(274)
    local previous = Button(compact, "<", 27, callbacks.previous)
    previous:SetPoint("BOTTOMLEFT", 21, 16)
    local progress = Text(compact, 11, muted)
    progress:SetPoint("BOTTOMLEFT", 57, 23)
    progress:SetWidth(53)
    local miniDetails = Button(compact, "Details", 80, callbacks.details)
    miniDetails:SetPoint("BOTTOMLEFT", 115, 16)
    local nextStep = Button(compact, "Next >", 81, callbacks.next)
    nextStep:SetPoint("BOTTOMRIGHT", -21, 16)

    local ui = { frame = full, compact = compact }
    function ui:Render(state)
        currentState = state
        local steps = state.plan and state.plan.steps or {}
        local stats = state.plan and state.plan.stats or {}
        local selected = steps[state.current]
        local fullVisible = state.visible and state.expanded
        local compactVisible = state.visible and not state.expanded
        local openingFull = fullVisible and not full:IsShown()
        local openingCompact = compactVisible and not compact:IsShown()
        full:SetShown(fullVisible)
        compact:SetShown(compactVisible)
        if openingFull then full:Raise() end
        if openingCompact then compact:Raise() end
        local single = state.options.optimization == "single"
        optimization:SetText((single and optimizationLabels.single or optimizationLabels.multi) .. " >")
        modeTitle:SetText(single and "Objective" or "Emphasis")
        local custom = not single and state.options.customWeights
        mode:SetText((custom and "Custom" or (modeLabels[state.options.mode] or "Balanced")) .. " >")
        cluster:SetText((clusterLabels[state.options.cluster] or "Normal") .. " >")
        local weights = state.options.weights or ns.GetWeightPreset(state.options.mode)
        local allZero = weights.travel == 0 and weights.level == 0 and weights.work == 0 and weights.density == 0
        modeHint:SetText(single and "Multi-objective sliders are inactive here. " .. (singleHints[state.options.mode] or singleHints.distance)
            or (allZero and "All weights are 0. Grouping, hard-quest and turn-in rules still apply."
                or "Drag weights (0-10): higher means more influence; 0 removes that score. Grouping and hard-quest rules still apply."))
        updatingWeights = true
        for key, slider in pairs(weightSliders) do
            slider:SetEnabled(not single)
            slider:SetAlpha(single and 0.45 or 1)
            slider:SetValue(weights[key])
            slider.valueText:SetText(string.format("%.2f / 10", weights[key]))
        end
        updatingWeights = false
        resetWeights:SetEnabled(not single)
        hard:SetChecked(state.options.deferHard)
        turnins:SetChecked(state.options.preferTurnIns)
        turnins:SetEnabled(not single)
        header.Text:SetText(state.demo and "QUESTROUTE / SAMPLE" or "QUESTROUTE")
        count:SetText(state.plan and string.format("%d quests  /  %d located  /  %d harder", #steps, stats.located or 0, stats.hard or 0) or "No route generated yet")
        status:SetText(state.status or "")
        routeMode:SetText(state.plan and ((state.plan.options.optimization == "single" and "Single: " or "Multi: ")
            .. (state.plan.options.optimization ~= "single" and state.plan.options.customWeights and "Custom weights"
                or (modeLabels[state.plan.options.mode] or "Balanced")) .. (state.dirty and "  - refresh needed" or "")) or "")
        child:SetHeight(math.max(routeHeight, #steps * 60))
        local maximum = math.max(0, #steps * 60 - routeHeight)
        if scroll:GetVerticalScroll() > maximum then scroll:SetVerticalScroll(maximum) end
        if self.lastPlan ~= state.plan then scroll:SetVerticalScroll(0); self.lastPlan = state.plan end
        empty:SetShown(#steps == 0)
        empty:SetText(state.plan and "No quests to schedule. Accept a quest, then generate a new route." or "Click Generate Route to read your quest log and build a schedule. Your route stays unchanged until you generate again.")
        for index, step in ipairs(steps) do
            local row = rows[index]
            if not row then row = Row(child, index, callbacks); rows[index] = row end
            row.step = step
            row.background:SetColorTexture(0.28, 0.21, 0.09, index == state.current and 0.95 or 0.65)
            row.number:SetText(string.format("%02d", index))
            row.title:SetText((step.complete and "Turn in: " or "") .. step.title)
            row.level:SetText(Level(step, state.playerLevel))
            row.level:SetTextColor(unpack(step.hard and { 1, 0.48, 0.25 } or muted))
            row.area:SetText(Area(step))
            row.reason:SetText(step.reason or "")
            row.selectHint:SetText(index == state.current and "Selected" or "Select >")
            row:Show()
        end
        for index = #steps + 1, #rows do rows[index]:Hide() end
        local warnings = state.warnings or {}
        if #warnings > 0 then note:SetText(warnings[1] .. " (Hover for details.)")
        elseif (stats.unlocated or 0) > 0 then note:SetText(string.format("%d quests lack coordinates and are grouped by area. Hover a row for details.", stats.unlocated))
        else note:SetText("Suggested waypoint order; terrain, quest phases, and transport may change the best route.") end
        details:SetEnabled(selected ~= nil and not state.demo)
        use:SetEnabled(#steps > 0)
        miniTitle:SetText(state.demo and "SAMPLE ROUTE" or (state.dirty and "QUESTROUTE *" or "QUESTROUTE"))
        miniQuest:SetText(selected and ((selected.complete and "Turn in: " or "") .. selected.title) or "No route yet - click Plan")
        miniArea:SetText(state.dirty and "Plan to refresh this route" or (selected and Area(selected) or "Generate only when you want a new schedule."))
        progress:SetText(string.format("%d / %d", #steps > 0 and state.current or 0, #steps))
        previous:SetEnabled(#steps > 0 and state.current > 1)
        nextStep:SetEnabled(#steps > 0 and state.current < #steps)
        miniDetails:SetEnabled(selected ~= nil and not state.demo)
    end
    return ui
end
