-- Native UI mocks check addon wiring, not actual WoW rendering or engine protection.
local objects, frames, methods = {}, {}, {}
local function object(kind, name, parent)
    local item = setmetatable({ kind = kind, name = name, parent = parent, shown = true,
        scripts = {}, events = {}, scroll = 0, enabled = true }, { __index = methods })
    objects[#objects + 1] = item
    if name then _G[name] = item end
    return item
end
local function noop() end
for _, key in ipairs({ "SetFont", "SetTextColor", "SetJustifyH", "SetJustifyV", "SetWordWrap",
    "SetShadowColor", "SetShadowOffset", "SetAllPoints", "SetColorTexture", "SetVertexColor",
    "SetHighlightTexture", "SetNormalTexture", "SetPushedTexture", "SetDisabledTexture", "SetTexture",
    "SetTexCoord", "SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse",
    "RegisterForDrag", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetAlpha",
    "EnableMouseWheel", "SetFrameLevel", "SetNormalFontObject", "SetHighlightFontObject", "SetDisabledFontObject", "Raise", "SetHitRectInsets" }) do
    methods[key] = noop
end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetWidth() return self.width or 0 end
function methods:GetHeight() return self.height or 0 end
function methods:GetFrameLevel() return 1 end
function methods:SetPoint(...)
    local point = { ... }
    self.point = point
    self.points = self.points or {}
    -- WoW keeps different anchors, replacing an existing anchor of the same name.
    for i, existing in ipairs(self.points) do
        if existing[1] == point[1] then self.points[i] = point; return end
    end
    self.points[#self.points + 1] = point
end
function methods:GetPoint() return unpack(self.point or { "CENTER", UIParent, "CENTER", 0, 0 }) end
function methods:ClearAllPoints() self.point, self.points = nil, {} end
function methods:EnableMouse(enabled) self.mouseEnabled = enabled end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:UnregisterAllEvents() self.events = {} end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(shown) self.shown = shown end
function methods:IsShown() return self.shown end
function methods:SetEnabled(enabled) self.enabled = enabled end
function methods:Enable() self.enabled = true end
function methods:Disable() self.enabled = false end
function methods:SetChecked(checked) self.checked = checked end
function methods:GetChecked() return self.checked end
function methods:SetOrientation(orientation) self.orientation = orientation end
function methods:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
function methods:SetValueStep(step) self.valueStep = step end
function methods:SetObeyStepOnDrag(obey) self.obeyStep = obey end
function methods:GetValue() return self.value end
function methods:SetValue(value)
    local changed = self.value ~= value
    self.value = value
    if changed and self.scripts.OnValueChanged then
        self.valueChanges = (self.valueChanges or 0) + 1
        self.scripts.OnValueChanged(self, value)
    end
end
function methods:SetThumbTexture(texture)
    self.thumb = type(texture) == "table" and texture or object("Texture", nil, self)
end
function methods:GetThumbTexture() return self.thumb end
function methods:SetScrollChild(child) self.child = child end
function methods:GetVerticalScroll() return self.scroll end
function methods:SetVerticalScroll(value) self.scroll = value end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:CreateFontString() return object("FontString", nil, self) end
function methods:CreateTexture() return object("Texture", nil, self) end
function methods:GetHighlightTexture()
    self.highlight = self.highlight or object("Texture", nil, self)
    return self.highlight
end
function methods:GetFontString()
    self.fontString = self.fontString or object("FontString", nil, self)
    return self.fontString
end
function methods:SetText(value)
    self.text = value
    if self.kind == "Button" then self:GetFontString().text = value end
end
function methods:SetFormattedText(format, ...) self:SetText(string.format(format, ...)) end
CreateFrame = function(kind, name, parent, template)
    local frame = object(kind, name, parent)
    frame.template = template
    if template == "DialogHeaderTemplate" then frame.Text = object("FontString", nil, frame) end
    if template == "UISliderTemplate" then frame.thumb = object("Texture", nil, frame) end
    frames[#frames + 1] = frame
    return frame
end
UIParent = object("Frame", "UIParent")
STANDARD_TEXT_FONT = "mock-font"
GameTooltip = { SetOwner = noop, SetText = noop, AddLine = noop, Show = noop, Hide = noop }

local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error("FAIL: " .. name .. ": " .. tostring(err)) end
    passed = passed + 1
end
local function eq(actual, expected)
    if actual ~= expected then error("expected " .. tostring(expected) .. ", received " .. tostring(actual)) end
end
local function contains(text, fragment) return type(text) == "string" and text:find(fragment, 1, true) ~= nil end

local ns, core, captured, callbacks, activeUI
local collects, optimizes, details, combat, readFailure, readUnavailable, planFailure, questCount, revision
local function boot(saved, realUI)
    objects, frames = {}, {}
    collects, optimizes, details, combat, readFailure, planFailure, questCount, revision = 0, 0, 0, false, false, false, 3, 1
    readUnavailable = false
    captured, callbacks, activeUI = nil, nil, nil
    QuestRouteDB = saved
    SlashCmdList = {}
    DEFAULT_CHAT_FRAME = { messages = {}, AddMessage = function(self, message) self.messages[#self.messages + 1] = message end }
    InCombatLockdown = function() return combat end
    ns = {}
    assert(loadfile(TEST_ROOT .. "/QuestRoute/Model.lua"))("QuestRoute", ns)
    ns.CollectQuests = function()
        collects = collects + 1
        if readFailure then error("fixture read failed") end
        if readUnavailable then return {}, { playerLevel = 10, player = {}, warnings = { "Quest log unavailable" }, unavailable = true } end
        local quests = {}
        for i = 1, questCount do
            quests[i] = { id = i, title = "Quest " .. i .. " revision " .. revision, level = 10 + i % 4,
                mapID = 1, mapName = "Test Area", zone = "Test Area", x = 0.2 + i / 100, y = 0.3,
                complete = i == 2, objectivesLeft = i == 2 and 0 or 1, objectiveText = "An objective",
                nativeVector = { x = 0.2 }, hard = i % 4 >= 2 }
        end
        return quests, { playerLevel = 10, player = { mapID = 1, x = 0.2, y = 0.2 }, warnings = {} }
    end
    ns.Optimize = function(quests, context, options)
        optimizes = optimizes + 1
        if planFailure then error("fixture optimizer failed") end
        local steps = {}
        for i, quest in ipairs(quests) do
            local step = {}
            for k, v in pairs(quest) do step[k] = v end
            step.reason = "Nearby quest cluster"
            step.estimatedMinutes = 2
            steps[i] = step
        end
        return { steps = steps, stats = { total = #steps, located = #steps, unlocated = 0, hard = 1, estimatedMinutes = #steps * 2 }, options = options }
    end
    ns.OpenQuest = function(quest) details = details + 1; eq(quest.id, captured.plan.steps[captured.current].id); return true end
    if realUI then assert(loadfile(TEST_ROOT .. "/QuestRoute/UI.lua"))("QuestRoute", ns) end
    local createUI = ns.CreateUI
    ns.CreateUI = function(db, cb)
        callbacks = cb
        local result = createUI and createUI(db, cb) or { Render = noop }
        local render = result.Render
        result.Render = function(self, state) captured = state; return render(self, state) end
        activeUI = result
        return result
    end
    assert(loadfile(TEST_ROOT .. "/QuestRoute/Core.lua"))("QuestRoute", ns)
    core = frames[#frames]
    core.scripts.OnEvent(core, "ADDON_LOADED", "QuestRoute")
end
local function event(name, arg) core.scripts.OnEvent(core, name, arg) end
local function command(text) SlashCmdList.QUESTROUTE(text) end
local function button(label)
    for _, frame in ipairs(frames) do
        if frame.kind == "Button" and (frame.fontString and frame.fontString.text or frame.text) == label then return frame end
    end
end
local function click(label)
    local frame = assert(button(label), "missing button: " .. label)
    assert(frame.enabled, "disabled button: " .. label)
    frame.scripts.OnClick(frame)
end

local function checkbox(label)
    for _, item in ipairs(objects) do
        if item.kind == "FontString" and item.text == label and item.parent and item.parent.kind == "CheckButton" then
            return item.parent
        end
    end
    error("missing checkbox: " .. label)
end

local function hasPlannerText(first, second)
    for _, item in ipairs(objects) do
        if item.kind == "FontString" and item.parent == activeUI.frame and contains(item.text, first)
            and (not second or contains(item.text, second)) then return true end
    end
    return false
end

local weightNames = { travel = "QuestRouteWeightTravel", level = "QuestRouteWeightLevel",
    work = "QuestRouteWeightWork", density = "QuestRouteWeightDensity" }
local weightKeys = { "travel", "level", "work", "density" }
local function weightSlider(key)
    local slider = assert(_G[weightNames[key]], "missing slider: " .. tostring(key))
    eq(slider.kind, "Slider")
    return slider
end
local function dragWeight(key, value)
    local slider = weightSlider(key)
    assert(slider.enabled and slider.mouseEnabled ~= false, "slider disabled: " .. key)
    slider:SetValue(value)
end
local function hasText(fragment)
    for _, item in ipairs(objects) do
        if item.kind == "FontString" and contains(item.text, fragment) then return true end
    end
    return false
end
local function assertWeights(actual, expected)
    for _, key in ipairs(weightKeys) do eq(actual[key], expected[key]) end
end

-- Resolve only the parent-relative anchors used by sibling header controls.
-- A two-anchor drag region has an inferred width, while native buttons have
-- explicit dimensions. This catches overlap even when offsets or sizes change.
local anchorFractions = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
local function headerBounds(frame)
    local constraints = { {}, {} }
    local parent = assert(frame.parent, "header control needs a parent")
    for _, point in ipairs(frame.points or {}) do
        local anchor, relative, relativeAnchor, x, y = unpack(point)
        if type(relative) == "number" then
            x, y, relative, relativeAnchor = relative, relativeAnchor, parent, anchor
        else
            relative, relativeAnchor = relative or parent, relativeAnchor or anchor
        end
        assert(relative == parent, "header geometry resolver only accepts sibling controls")
        local own = assert(anchorFractions[anchor], "unsupported own anchor")
        local other = assert(anchorFractions[relativeAnchor], "unsupported relative anchor")
        constraints[1][#constraints[1] + 1] = { factor = own[1], coordinate = parent.width * other[1] + (x or 0) }
        constraints[2][#constraints[2] + 1] = { factor = own[2], coordinate = parent.height * other[2] + (y or 0) }
    end
    local function axis(points, size)
        local first = assert(points[1], "header control has no anchor")
        if not size then
            for _, other in ipairs(points) do
                if other.factor ~= first.factor then
                    size = (other.coordinate - first.coordinate) / (other.factor - first.factor)
                    break
                end
            end
        end
        assert(size and size > 0, "header control has no positive extent")
        local start = first.coordinate - first.factor * size
        return start, start + size
    end
    local left, right = axis(constraints[1], frame.width)
    local bottom, top = axis(constraints[2], frame.height)
    return { left = left, right = right, bottom = bottom, top = top }
end
local function assertNoHeaderDragOverlap(control)
    local bounds, found = headerBounds(control), false
    for _, candidate in ipairs(frames) do
        if candidate.parent == control.parent and candidate.scripts.OnDragStart and candidate.mouseEnabled then
            found = true
            local drag = headerBounds(candidate)
            local overlaps = math.min(bounds.right, drag.right) > math.max(bounds.left, drag.left)
                and math.min(bounds.top, drag.top) > math.max(bounds.bottom, drag.bottom)
            assert(not overlaps, "header drag region overlaps " .. (control:GetFontString().text or control.name or "control"))
        end
    end
    assert(found, "expected a draggable header beside the control")
end

test("cold start is compact and never reads or schedules quests", function()
    boot(nil, false)
    eq(captured.expanded, false); eq(captured.visible, true)
    eq(captured.plan, nil); eq(collects, 0); eq(optimizes, 0)
    eq(SLASH_QUESTROUTE2, "/qr")
    local initialUI = activeUI
    event("ADDON_LOADED", "QuestRoute"); eq(activeUI, initialUI)
end)
test("ordinary quest and login events never generate or expand", function()
    for _, name in ipairs({ "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do event(name) end
    eq(collects, 0); eq(optimizes, 0); eq(captured.expanded, false)
end)
test("opening and changing preferences do not generate a route", function()
    callbacks.open(); eq(captured.expanded, true)
    callbacks.option("mode", "distance"); callbacks.option("cluster", "wide")
    callbacks.option("deferHard", false); callbacks.option("preferTurnIns", false)
    eq(captured.options.mode, "distance"); eq(captured.options.cluster, "wide")
    eq(captured.options.deferHard, false); eq(captured.options.preferTurnIns, false)
    eq(collects, 0); eq(optimizes, 0)
end)
test("explicit generation snapshots current quests and selected options", function()
    callbacks.generate()
    eq(collects, 1); eq(optimizes, 1); eq(#captured.plan.steps, 3)
    eq(captured.current, 1); eq(captured.expanded, true); eq(captured.dirty, false)
    eq(captured.plan.options.mode, "distance")
    eq(captured.plan.steps[1].title, "Quest 1 revision 1")
    eq(QuestRouteDB.plan.steps[1].nativeVector, nil)
    assert(QuestRouteDB.plan ~= captured.plan)
    assert(QuestRouteDB.plan.steps[1] ~= captured.plan.steps[1])
end)
test("minimized stale route remains frozen until manually regenerated", function()
    callbacks.minimize(); eq(captured.expanded, false)
    local plan = captured.plan
    revision = 2
    for _, name in ipairs({ "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do event(name) end
    eq(captured.dirty, true); eq(captured.expanded, false); eq(captured.plan, plan)
    eq(captured.plan.steps[1].title, "Quest 1 revision 1")
    eq(collects, 1); eq(optimizes, 1)
    command("generate")
    eq(collects, 2); eq(optimizes, 2); eq(captured.dirty, false)
    eq(captured.plan.steps[1].title, "Quest 1 revision 2")
end)
test("step navigation is manual bounded and saved", function()
    callbacks.previous(); eq(captured.current, 1)
    callbacks.next(); eq(captured.current, 2); eq(QuestRouteDB.current, 2)
    command("next"); command("next"); eq(captured.current, 3)
    command("prev"); eq(captured.current, 2)
    callbacks.select(999); eq(captured.current, 3)
    callbacks.select(-5); eq(captured.current, 1)
    callbacks.details(); eq(details, 1)
end)
test("read failure and optimizer failure preserve previous schedule", function()
    local plan, saved = captured.plan, QuestRouteDB.plan
    readFailure = true; callbacks.generate(); readFailure = false
    eq(captured.plan, plan); eq(QuestRouteDB.plan, saved)
    assert(contains(captured.status, "Could not read"))
    planFailure = true; callbacks.generate(); planFailure = false
    eq(captured.plan, plan); eq(QuestRouteDB.plan, saved)
    assert(contains(captured.status, "previous schedule"))
end)
test("unavailable empty scan preserves saved route and current step without optimizing", function()
    callbacks.select(2)
    local plan, saved, beforeOptimize = captured.plan, QuestRouteDB.plan, optimizes
    callbacks.minimize()
    readUnavailable = true; command("generate"); readUnavailable = false
    eq(captured.plan, plan); eq(QuestRouteDB.plan, saved)
    eq(captured.current, 2); eq(QuestRouteDB.current, 2); eq(optimizes, beforeOptimize)
    eq(captured.expanded, true); eq(captured.visible, true)
    assert(contains(captured.status, "Could not read"))
end)
test("combat refuses generation without reading log or changing route", function()
    local beforeCollect, beforeOptimize, plan = collects, optimizes, captured.plan
    callbacks.minimize()
    combat = true; callbacks.generate(); combat = false
    eq(collects, beforeCollect); eq(optimizes, beforeOptimize); eq(captured.plan, plan)
    eq(captured.expanded, true); eq(captured.visible, true)
    assert(contains(captured.status, "Leave combat"))
end)
test("demo is identified and cannot overwrite saved live route or open details", function()
    local saved, position, beforeDetails = QuestRouteDB.plan, QuestRouteDB.current, details
    command("test")
    eq(captured.demo, true); eq(#captured.plan.steps, 6)
    eq(QuestRouteDB.plan, saved); assert(contains(captured.status, "SAMPLE"))
    callbacks.next(); eq(QuestRouteDB.current, position)
    callbacks.details(); eq(details, beforeDetails)
    event("QUEST_LOG_UPDATE"); eq(captured.dirty, false)
end)
test("reload restores live route compact and stale without regenerating", function()
    local saved, expectedTitle = QuestRouteDB, QuestRouteDB.plan.steps[1].title
    boot(saved, false)
    eq(captured.expanded, false); eq(captured.dirty, true); eq(captured.demo, false)
    eq(captured.plan.steps[1].title, expectedTitle)
    eq(collects, 0); eq(optimizes, 0)
end)
test("hide show and opening planner affect visibility only", function()
    command("hide"); eq(captured.visible, false)
    event("QUEST_LOG_UPDATE"); eq(captured.visible, false)
    command("show"); eq(captured.visible, true); eq(captured.expanded, false)
    command(""); eq(captured.expanded, true)
    command("min"); eq(captured.expanded, false)
    eq(collects, 0); eq(optimizes, 0)
end)
test("empty log produces empty route and bounded navigation", function()
    local beforeOptimize = optimizes
    questCount = 0; command("generate")
    eq(#captured.plan.steps, 0); assert(contains(captured.status, "no schedulable"))
    eq(#QuestRouteDB.plan.steps, 0); eq(optimizes, beforeOptimize + 1)
    callbacks.next(); callbacks.previous(); callbacks.details(); eq(captured.current, 1)
end)
test("invalid saved options and plan recover to a usable compact planner", function()
    boot({ options = { mode = "bogus", cluster = "bogus", deferHard = "yes" }, plan = { steps = { false } }, current = 0 / 0 }, false)
    eq(captured.options.mode, "balanced"); eq(captured.options.cluster, "normal"); eq(captured.options.deferHard, true)
    eq(captured.plan, nil); eq(captured.current, 1); eq(captured.expanded, false)
end)

-- Real UI + Core integration follows. The renderer is still a mock, but every
-- widget and callback below is constructed by the actual addon implementation.
test("native UI constructs and opens without triggering generation", function()
    boot(nil, true)
    eq(captured.expanded, false); eq(collects, 0)
    eq(activeUI.frame.shown, false); eq(activeUI.compact.shown, true)
    click("Plan"); eq(captured.expanded, true); eq(collects, 0)
    eq(activeUI.frame.shown, true); eq(activeUI.compact.shown, false)
end)
test("header drag regions leave Plan and Minimize button hitboxes unobstructed", function()
    callbacks.minimize()
    assertNoHeaderDragOverlap(assert(button("Plan")))
    click("Plan")
    eq(activeUI.frame.shown, true); eq(activeUI.compact.shown, false)
    assertNoHeaderDragOverlap(assert(button("Minimize")))
    click("Minimize")
    eq(activeUI.frame.shown, false); eq(activeUI.compact.shown, true)
    eq(collects, 0); eq(optimizes, 0)
    click("Plan")
end)
test("native preference buttons and checkboxes update settings without scheduling", function()
    click("Balanced >"); eq(captured.options.mode, "distance")
    click("Normal >"); eq(captured.options.cluster, "wide")
    local checkboxes = {}
    for _, frame in ipairs(frames) do if frame.kind == "CheckButton" then checkboxes[#checkboxes + 1] = frame end end
    eq(#checkboxes, 2)
    for _, check in ipairs(checkboxes) do check:SetChecked(false); check.scripts.OnClick(check) end
    eq(captured.options.deferHard, false); eq(captured.options.preferTurnIns, false)
    eq(collects, 0); eq(optimizes, 0)
end)
test("native UI renders a large schedule without refresh allocation", function()
    questCount = 40
    click("Generate Route")
    eq(#captured.plan.steps, 40)
    local count = #objects
    callbacks.select(2); callbacks.select(3)
    eq(#objects, count)
end)
test("native route rows and compact controls navigate without refreshing", function()
    local row
    for _, frame in ipairs(frames) do if frame.step and frame.step.id == 7 then row = frame; break end end
    assert(row); row.scripts.OnClick(row); eq(captured.current, 7)
    row.scripts.OnEnter(row); row.scripts.OnLeave(row)
    click("Use Route"); eq(captured.expanded, false)
    eq(activeUI.frame.shown, false); eq(activeUI.compact.shown, true)
    click("Next >"); eq(captured.current, 8)
    click("<"); eq(captured.current, 7)
    click("Details"); eq(details, 1)
    eq(collects, 1); eq(optimizes, 1)
end)
test("native UI shrinking schedule clamps scroll offsets", function()
    for _, frame in ipairs(frames) do if frame.kind == "ScrollFrame" then frame.scroll = 1000 end end
    questCount = 1; callbacks.generate()
    for _, frame in ipairs(frames) do if frame.kind == "ScrollFrame" then eq(frame.scroll, 0) end end
    local shownRows = 0
    for _, frame in ipairs(frames) do if frame.step and frame.shown then shownRows = shownRows + 1 end end
    eq(shownRows, 1)
    click("Minimize"); eq(captured.expanded, false)
    callbacks.open(); eq(captured.expanded, true)
end)
test("native windows persist their drag positions independently", function()
    local drags = {}
    for _, frame in ipairs(frames) do if frame.scripts.OnDragStop then drags[#drags + 1] = frame end end
    eq(#drags, 2)
    for i, drag in ipairs(drags) do
        drag.parent:SetPoint("TOP", UIParent, "TOP", i * 20, -i * 30)
        drag.scripts.OnDragStart(); eq(drag.parent.moving, true)
        drag.scripts.OnDragStop(); eq(drag.parent.moving, false)
    end
    eq(QuestRouteDB.plannerPosition.x, 20); eq(QuestRouteDB.plannerPosition.y, -30)
    eq(QuestRouteDB.compactPosition.x, 40); eq(QuestRouteDB.compactPosition.y, -60)
end)
test("native empty route disables step actions and sample route disables details", function()
    questCount = 0; click("Generate Route")
    eq(button("Quest Details").enabled, false); eq(button("Use Route").enabled, false)
    eq(button("Details").enabled, false); eq(button("Next >").enabled, false); eq(button("<").enabled, false)
    command("test")
    eq(button("Quest Details").enabled, false); eq(button("Details").enabled, false)
end)

test("legacy options and saved routes retain their multi-objective emphasis", function()
    for _, mode in ipairs({ "balanced", "distance", "level", "time" }) do
        boot({ options = { mode = mode, cluster = "wide", preferTurnIns = false },
            plan = { steps = { { id = 1, title = "Saved quest" } }, options = { mode = mode } } }, false)
        eq(captured.options.optimization, "multi"); eq(captured.options.mode, mode)
        eq(captured.options.cluster, "wide"); eq(captured.options.preferTurnIns, false)
        eq(captured.plan.options.optimization, "multi"); eq(captured.plan.options.mode, mode)
        eq(captured.expanded, false); eq(captured.dirty, true)
        eq(collects, 0); eq(optimizes, 0)
    end
end)

test("invalid strategies and unsupported single goals normalize without scheduling", function()
    boot({ options = { optimization = "invalid", mode = "level" } }, false)
    eq(captured.options.optimization, "multi"); eq(captured.options.mode, "level")
    for _, mode in ipairs({ "balanced", "invalid" }) do
        boot({ options = { optimization = "single", mode = mode } }, false)
        eq(captured.options.optimization, "single"); eq(captured.options.mode, "distance")
        eq(QuestRouteDB.options.mode, "distance"); eq(collects, 0); eq(optimizes, 0)
    end
end)

test("strategy and goal buttons expose both optimization choices without generating", function()
    boot(nil, true); click("Plan")
    eq(captured.options.optimization, "multi"); assert(hasPlannerText("Emphasis"))
    click("Multi-objective >")
    eq(captured.options.optimization, "single"); eq(captured.options.mode, "distance")
    assert(hasPlannerText("Objective")); eq(button("Balanced >"), nil)
    click("Shortest travel >"); eq(captured.options.mode, "level")
    click("Safer levels >"); eq(captured.options.mode, "time")
    click("Time / effort >"); eq(captured.options.mode, "distance")
    click("Single-objective >")
    eq(captured.options.optimization, "multi"); assert(hasPlannerText("Emphasis"))
    click("Shortest travel >"); eq(captured.options.mode, "level")
    click("Safer levels >"); eq(captured.options.mode, "time")
    click("Time / effort >"); eq(captured.options.mode, "balanced")
    click("Balanced >"); eq(captured.options.mode, "distance")
    eq(collects, 0); eq(optimizes, 0)
end)

test("single-objective mode disables turn-in preference while preserving both saved choices", function()
    boot(nil, true); click("Plan")
    local turnins = checkbox("Favor completed turn-ins (Multi-objective only)")
    local hard = checkbox("Defer quests 2+ levels above me")
    eq(turnins.enabled, true); eq(turnins.checked, true)
    click("Multi-objective >")
    eq(turnins.enabled, false); eq(turnins.checked, true); eq(captured.options.preferTurnIns, true)
    eq(hard.enabled, true)
    hard:SetChecked(false); hard.scripts.OnClick(hard)
    eq(captured.options.deferHard, false)
    click("Single-objective >")
    eq(turnins.enabled, true); eq(turnins.checked, true); eq(hard.checked, false)
    turnins:SetChecked(false); turnins.scripts.OnClick(turnins)
    click("Multi-objective >"); eq(turnins.enabled, false); eq(turnins.checked, false)
    click("Single-objective >"); eq(turnins.enabled, true); eq(turnins.checked, false)
    eq(captured.options.preferTurnIns, false); eq(collects, 0); eq(optimizes, 0)
end)

test("strategy changes freeze the old route until generation and survive reload", function()
    boot(nil, true); click("Plan"); click("Generate Route")
    local previous, saved = captured.plan, QuestRouteDB.plan
    eq(previous.options.optimization, "multi"); eq(previous.options.mode, "balanced")
    click("Multi-objective >"); click("Shortest travel >")
    eq(captured.options.optimization, "single"); eq(captured.options.mode, "level")
    eq(captured.dirty, true); eq(captured.plan, previous); eq(QuestRouteDB.plan, saved)
    eq(previous.options.optimization, "multi"); eq(previous.options.mode, "balanced")
    assert(hasPlannerText("Multi", "Balanced"))
    eq(collects, 1); eq(optimizes, 1)
    click("Generate Route")
    eq(captured.dirty, false); eq(captured.plan.options.optimization, "single")
    eq(captured.plan.options.mode, "level"); assert(hasPlannerText("Single", "Safer levels"))
    eq(QuestRouteDB.plan.options.optimization, "single"); eq(QuestRouteDB.plan.options.mode, "level")
    eq(collects, 2); eq(optimizes, 2)
    local persisted = QuestRouteDB
    boot(persisted, true)
    eq(captured.options.optimization, "single"); eq(captured.options.mode, "level")
    eq(captured.plan.options.optimization, "single"); eq(captured.plan.options.mode, "level")
    eq(captured.expanded, false); eq(captured.dirty, true); eq(collects, 0); eq(optimizes, 0)
end)

test("optimization controls retain unobstructed outlined button affordances", function()
    boot(nil, true); click("Plan")
    for _, label in ipairs({ "Multi-objective >", "Balanced >", "Normal >" }) do
        local control = assert(button(label))
        assertNoHeaderDragOverlap(control)
        local outline
        for _, frame in ipairs(frames) do
            if frame.kind == "Frame" and frame.parent == control and frame.mouseEnabled == false then
                outline = frame; break
            end
        end
        assert(outline, "missing noninteractive outline: " .. label)
        eq(next(outline.scripts), nil)
        local edges = 0
        for _, item in ipairs(objects) do
            if item.kind == "Texture" and item.parent == outline and (item.width == 1 or item.height == 1) then
                edges = edges + 1
            end
        end
        eq(edges, 4)
    end
end)

test("legacy presets populate four sliders without turning renders into option edits", function()
    local expected = {
        balanced = { travel = 6, level = 3, work = 1.8, density = 1.6 },
        distance = { travel = 10, level = 1.5, work = 0.3, density = 0.35 },
        level = { travel = 3, level = 7, work = 0.8, density = 0.7 },
        time = { travel = 5, level = 2, work = 10, density = 1.1 },
    }
    for _, mode in ipairs({ "balanced", "distance", "level", "time" }) do
        boot({ options = { mode = mode } }, true); click("Plan")
        eq(captured.options.customWeights, false)
        assertWeights(captured.options.weights, expected[mode])
        local sliders = 0
        for _, frame in ipairs(frames) do if frame.kind == "Slider" then sliders = sliders + 1 end end
        eq(sliders, 4)
        for _, key in ipairs(weightKeys) do
            local slider = weightSlider(key)
            eq(slider.minimum, 0); eq(slider.maximum, 10); eq(slider.valueStep, 0.05)
            eq(slider.value, expected[mode][key]); eq(slider.enabled, true)
        end
        eq(collects, 0); eq(optimizes, 0)
    end
end)

test("each weight slider changes its factor while preserving the generated schedule", function()
    boot(nil, true); click("Plan"); click("Generate Route")
    local plan, saved = captured.plan, QuestRouteDB.plan
    local target = { travel = 8.25, level = 2.5, work = 7.75, density = 0 }
    for _, key in ipairs(weightKeys) do
        dragWeight(key, target[key])
        eq(captured.options.weights[key], target[key]); eq(weightSlider(key).value, target[key])
        assert(hasText(string.format("%.2f", target[key])), "weight value is not displayed: " .. key)
    end
    eq(captured.options.customWeights, true); assert(button("Custom >"))
    eq(captured.plan, plan); eq(QuestRouteDB.plan, saved); eq(captured.dirty, true)
    eq(plan.options.customWeights, false); assert(hasPlannerText("Multi", "Balanced"))
    eq(collects, 1); eq(optimizes, 1)
    click("Generate Route")
    eq(captured.plan.options.customWeights, true); assertWeights(captured.plan.options.weights, target)
    assert(hasPlannerText("Multi", "Custom")); eq(captured.dirty, false)
    eq(collects, 2); eq(optimizes, 2)
end)

test("preset selection and reset replace custom weights without losing other preferences", function()
    boot(nil, true); click("Plan")
    callbacks.option("cluster", "wide"); callbacks.option("deferHard", false)
    dragWeight("travel", 9); dragWeight("level", 0)
    click("Custom >")
    eq(captured.options.mode, "balanced"); eq(captured.options.customWeights, false)
    assertWeights(captured.options.weights, ns.GetWeightPreset("balanced"))
    click("Balanced >")
    eq(captured.options.mode, "distance"); eq(captured.options.customWeights, false)
    assertWeights(captured.options.weights, ns.GetWeightPreset("distance"))
    for _, key in ipairs(weightKeys) do eq(weightSlider(key).value, captured.options.weights[key]) end
    dragWeight("density", 8)
    click("Reset to Balanced")
    eq(captured.options.mode, "balanced"); eq(captured.options.customWeights, false)
    assertWeights(captured.options.weights, ns.GetWeightPreset("balanced"))
    eq(captured.options.cluster, "wide"); eq(captured.options.deferHard, false)
    eq(collects, 0); eq(optimizes, 0)
end)

test("single-objective disables weight controls and restores custom priorities on return", function()
    boot(nil, true); click("Plan")
    local target = { travel = 8, level = 1, work = 2, density = 9 }
    for _, key in ipairs(weightKeys) do dragWeight(key, target[key]) end
    click("Multi-objective >")
    eq(captured.options.optimization, "single"); eq(captured.options.customWeights, true)
    eq(button("Reset to Balanced").enabled, false)
    for _, key in ipairs(weightKeys) do
        local slider = weightSlider(key)
        assert(slider.enabled == false or slider.mouseEnabled == false, "single mode slider remains interactive")
        callbacks.weight(key, 5)
    end
    assertWeights(captured.options.weights, target)
    click("Shortest travel >"); eq(captured.options.mode, "level")
    assertWeights(captured.options.weights, target)
    click("Single-objective >")
    eq(captured.options.optimization, "multi"); eq(captured.options.customWeights, true)
    assert(button("Custom >")); eq(button("Reset to Balanced").enabled, true)
    assertWeights(captured.options.weights, target)
    for _, key in ipairs(weightKeys) do
        eq(weightSlider(key).enabled, true); eq(weightSlider(key).value, target[key])
    end
    eq(collects, 0); eq(optimizes, 0)
end)

test("custom priorities and generated snapshots persist independently across reload", function()
    boot(nil, true); click("Plan")
    dragWeight("travel", 8.5); dragWeight("density", 4.25); click("Generate Route")
    local plan, saved = captured.plan, QuestRouteDB.plan
    assert(captured.options.weights ~= plan.options.weights)
    assert(saved.options.weights ~= plan.options.weights)
    assert(saved.options.weights ~= captured.options.weights)
    dragWeight("travel", 0)
    eq(captured.options.weights.travel, 0)
    eq(plan.options.weights.travel, 8.5); eq(saved.options.weights.travel, 8.5)
    local persisted = QuestRouteDB
    boot(persisted, true)
    eq(captured.options.customWeights, true); eq(captured.options.weights.travel, 0)
    eq(captured.options.weights.density, 4.25)
    eq(captured.plan.options.customWeights, true); eq(captured.plan.options.weights.travel, 8.5)
    assert(captured.plan.options.weights ~= captured.options.weights)
    eq(captured.expanded, false); eq(captured.dirty, true)
    eq(collects, 0); eq(optimizes, 0)
end)

test("slider renders neither dirty a fresh schedule nor trigger recursive edits", function()
    boot(nil, true); click("Plan")
    callbacks.option("mode", "time"); click("Generate Route")
    eq(captured.options.customWeights, false); eq(captured.dirty, false)
    local options, plan = captured.options, captured.plan
    for _ = 1, 3 do activeUI:Render(captured) end
    eq(captured.options, options); eq(captured.plan, plan); eq(captured.dirty, false)
    eq(captured.options.customWeights, false)
    local changes = 0
    for _, key in ipairs(weightKeys) do changes = changes + (weightSlider(key).valueChanges or 0) end
    assert(changes > 0, "mock must exercise native OnValueChanged from programmatic values")
    eq(collects, 1); eq(optimizes, 1)
    dragWeight("travel", 8.27)
    eq(captured.options.weights.travel, 8.25); eq(weightSlider("travel").value, 8.25)
    eq(captured.plan, plan); eq(captured.dirty, true); eq(collects, 1); eq(optimizes, 1)
end)

test("weight sliders have outlined tracks and thumbs without an input-stealing overlay", function()
    boot(nil, true); click("Plan")
    for _, key in ipairs(weightKeys) do
        local slider = weightSlider(key)
        assert(slider:GetThumbTexture(), "slider needs a visible thumb")
        assertNoHeaderDragOverlap(slider)
        local outlines = 0
        for _, frame in ipairs(frames) do
            if frame.kind == "Frame" and frame.parent == slider then
                eq(frame.mouseEnabled, false); eq(next(frame.scripts), nil)
                local edges = 0
                for _, item in ipairs(objects) do
                    if item.kind == "Texture" and item.parent == frame and (item.width == 1 or item.height == 1) then
                        edges = edges + 1
                    end
                end
                if edges == 4 then outlines = outlines + 1 end
            end
        end
        assert(outlines >= 2, "slider track and thumb need thin outlines: " .. key)
    end
    assertNoHeaderDragOverlap(assert(button("Reset to Balanced")))
end)

print("QUEST INTEGRATION PASS: " .. passed .. " mocked-client cases")
