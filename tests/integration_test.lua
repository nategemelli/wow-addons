-- A deliberately small mock client verifies Lua wiring, not WoW engine taint,
-- actual font layout, server visibility, or combat protection behavior.
local ns = {}
local objects, frames, secretValues = {}, {}, setmetatable({}, { __mode = "k" })
local rejectSecrets = false
local nativeSecretDisplays = 0
local function secret()
    local function forbidden() error("secret was inspected by Lua") end
    local value = setmetatable({}, { __tostring = forbidden, __concat = forbidden,
        __lt = forbidden, __le = forbidden, __add = forbidden, __sub = forbidden })
    secretValues[value] = true
    return value
end
issecretvalue = function(value) return type(value) == "table" and secretValues[value] == true end

local methods = {}
local function object(kind, name, parent)
    local result = setmetatable({ kind = kind, name = name, parent = parent,
        scripts = {}, events = {}, shown = true, enabled = true, scroll = 0 }, { __index = methods })
    objects[#objects + 1] = result
    if name then _G[name] = result end
    return result
end
local function noop() end
for _, method in ipairs({ "SetFont", "SetTextColor", "SetJustifyH", "SetJustifyV", "SetWordWrap",
    "SetShadowColor", "SetShadowOffset",
    "SetAllPoints", "SetColorTexture", "SetHighlightTexture", "SetVertexColor", "SetStatusBarTexture",
    "SetStatusBarColor", "SetMinMaxValues", "SetTexture", "SetTexCoord", "SetFrameStrata",
    "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag", "SetBackdrop",
    "SetBackdropColor", "SetBackdropBorderColor", "EnableMouseWheel", "UnregisterAllEvents" }) do
    methods[method] = noop
end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetWidth() return self.width or 0 end
function methods:GetHeight() return self.height or 0 end
function methods:SetPoint(...) self.point = { ... } end
function methods:GetPoint() return unpack(self.point or { "CENTER", UIParent, "CENTER", 0, 0 }) end
function methods:ClearAllPoints() self.point = nil end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:RegisterForClicks(...) self.clicks = { ... } end
function methods:SetMotionScriptsWhileDisabled(value) self.motionWhileDisabled = value end
function methods:SetEnabled(value) self.enabled = value end
function methods:IsEnabled() return self.enabled end
function methods:EnableMouse(value) self.mouseEnabled = value end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:Show() self.shown = true end
function methods:Hide()
    local wasShown = self.shown
    self.shown = false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
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
function methods:SetValue(value)
    if issecretvalue(value) then
        assert(not rejectSecrets, "native sink unavailable")
        nativeSecretDisplays = nativeSecretDisplays + 1
    end
    self.value = value
end
function methods:SetText(value)
    if issecretvalue(value) then
        assert(not rejectSecrets, "native sink unavailable")
        nativeSecretDisplays = nativeSecretDisplays + 1
    end
    self.text = value
end
function methods:SetFormattedText(format, value)
    if issecretvalue(value) then
        assert(not rejectSecrets, "native sink unavailable")
        nativeSecretDisplays = nativeSecretDisplays + 1
        self.text = "<native secret display>"
    else
        self.text = string.format(format, value)
    end
end
CreateFrame = function(kind, name, parent, template)
    local frame = object(kind, name, parent)
    frame.template = template
    if template == "DialogHeaderTemplate" then
        frame.Text = object("FontString", nil, frame)
    end
    frames[#frames + 1] = frame
    return frame
end
UIParent = object("Frame", "UIParent")
STANDARD_TEXT_FONT = "mock-font"
SetRaidTargetIconTexture = function(texture, index) texture.marker = index end
local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error("FAIL: " .. name .. ": " .. tostring(err)) end
    passed = passed + 1
end
local function eq(a, b)
    if a ~= b then error("expected " .. tostring(b) .. ", received " .. tostring(a)) end
end
local function hasText(text)
    for _, item in ipairs(objects) do if item.text == text then return true end end
    return false
end
assert(loadfile(TEST_ROOT .. "/TankWatch/Model.lua"))("TankWatch", ns)
assert(loadfile(TEST_ROOT .. "/TankWatch/UI.lua"))("TankWatch", ns)
local db = { sound = true, locked = false }
local ui = ns.CreateUI(db)
local snapshot = { enemies = {}, members = {}, targetName = "Enemy", headline = "Ready", summary = "Group", demo = false,
    targetingLocked = false }

test("empty snapshot renders both empty states", function()
    ui:Render(snapshot)
    assert(hasText("Ready"))
    assert(hasText("GROUP THREAT  /  Enemy"))
    assert(hasText("Select a hostile target to inspect your group's threat against it."))
end)
test("full raid and enemy list render without allocating every refresh", function()
    for i = 1, 40 do
        snapshot.enemies[i] = { name = "Enemy " .. i, targetName = "Ally", state = "safe", label = "ON YOU",
            detail = "Threat held", percent = 100, percentDisplayable = true, marker = i <= 8 and i or nil }
        snapshot.members[i] = { name = "Ally " .. i, role = "DAMAGER", statusLabel = "Below tank",
            percent = i, percentDisplayable = true, isPlayer = i == 1 }
    end
    ui:Render(snapshot)
    local total = #objects
    ui:Render(snapshot)
    eq(#objects, total)
end)
test("secret percentage reaches native display without Lua formatting", function()
    snapshot.enemies[1].percent = secret()
    snapshot.members[1].percent = secret()
    nativeSecretDisplays = 0
    ui:Render(snapshot)
    eq(nativeSecretDisplays, 4)
end)
test("unsupported native secret display has visible fallback", function()
    rejectSecrets = true
    ui:Render(snapshot)
    assert(hasText("?"))
    rejectSecrets = false
end)
test("shrinking lists clamp scrolling and hide stale rows", function()
    for _, frame in ipairs(frames) do
        if frame.kind == "ScrollFrame" then frame.scroll = 1000 end
    end
    snapshot.enemies = {}; snapshot.members = {}
    ui:Render(snapshot)
    for _, frame in ipairs(frames) do
        if frame.kind == "ScrollFrame" then eq(frame.scroll, 0) end
    end
end)
test("visibility and lock controls update the frame and saved setting", function()
    ui:SetVisible(false); eq(ui.frame.shown, false)
    ui:SetVisible(true); eq(ui.frame.shown, true)
    ui:SetLocked(true); eq(db.locked, true)
    ui:SetLocked(false); eq(db.locked, false)
end)
test("dragging persists position", function()
    local titlebar
    for _, frame in ipairs(frames) do
        if frame.scripts.OnDragStop then titlebar = frame; break end
    end
    assert(titlebar)
    ui.frame:SetPoint("TOP", UIParent, "TOP", 42, -78)
    titlebar.scripts.OnDragStart(); eq(ui.frame.moving, true)
    titlebar.scripts.OnDragStop(); eq(ui.frame.moving, false)
    eq(db.position.point, "TOP"); eq(db.position.x, 42); eq(db.position.y, -78)
end)
test("demo is explicitly identified", function()
    snapshot.demo = true
    ui:Render(snapshot)
    assert(hasText("TANKWATCH  /  DEMO"))
    assert(hasText("Live"))
end)

local targetClicks = {}
ns.TargetEnemy = function(item)
    targetClicks[#targetClicks + 1] = item
    return true
end
GameTooltip = { SetOwner = noop, SetText = noop, AddLine = noop, Show = noop, Hide = noop }
local function clickableEnemy(unit, guid)
    return { unit = unit or "nameplate1", guid = guid or "Enemy-A", name = "Clickable enemy", targetName = "Tank",
        state = "safe", label = "ON YOU", detail = "Threat held", percent = 100, percentDisplayable = true }
end
local function showEnemy(item, locked, demo)
    snapshot.enemies, snapshot.members = { item }, {}
    snapshot.targetingLocked, snapshot.demo = locked == true, demo == true
    ui:Render(snapshot)
    for _, frame in ipairs(frames) do
        if frame.item == item and frame.name and frame.target then return frame end
    end
    error("enemy row missing")
end
local function press(row, button)
    row.scripts.OnMouseDown(row, button or "LeftButton")
end
local function release(row, button)
    row.scripts.OnClick(row, button or "LeftButton")
end

test("enemy targeting is an explicit left click carrying the displayed identity", function()
    local item = clickableEnemy()
    local row = showEnemy(item)
    eq(row.kind, "Button"); eq(row.enabled, true)
    eq(row.clicks[1], "LeftButtonUp"); eq(row.detail.text, "Click to target")
    eq(#targetClicks, 0)
    ui:Render(snapshot); row.scripts.OnEnter(row); row.scripts.OnLeave(row)
    eq(#targetClicks, 0)
    press(row); release(row)
    eq(#targetClicks, 1); eq(targetClicks[1].unit, item.unit); eq(targetClicks[1].guid, item.guid)
    release(row); eq(#targetClicks, 1)
    press(row, "RightButton"); release(row, "RightButton"); eq(#targetClicks, 1)
end)

test("combat demo and unavailable identities visibly disable targeting", function()
    local item = clickableEnemy()
    local before = #targetClicks
    local row = showEnemy(item, true)
    eq(row.enabled, false); eq(row.detail.text, "Combat locked")
    press(row); release(row); eq(#targetClicks, before)
    row = showEnemy(item, false, true)
    eq(row.enabled, false); eq(row.detail.text, "Sample only")
    press(row); release(row); eq(#targetClicks, before)
    for _, missing in ipairs({ "guid", "unit" }) do
        local unavailable = clickableEnemy(); unavailable[missing] = nil
        row = showEnemy(unavailable)
        eq(row.enabled, false); eq(row.detail.text, "Unavailable")
        press(row); release(row); eq(#targetClicks, before)
    end
    local restricted = clickableEnemy(); restricted.guid = secret()
    row = showEnemy(restricted)
    eq(row.enabled, false); eq(row.detail.text, "Unavailable")
    press(row); release(row); eq(#targetClicks, before)
    row = showEnemy(item)
    snapshot.targetingLocked = nil; ui:Render(snapshot)
    eq(row.enabled, false); eq(row.detail.text, "Combat locked")
    press(row); release(row); eq(#targetClicks, before)
end)

test("reordering or recycling a row between mouse down and release never targets its replacement", function()
    local first = clickableEnemy()
    local row = showEnemy(first)
    local before = #targetClicks
    press(row)
    eq(showEnemy(clickableEnemy("nameplate2", "Enemy-B")), row)
    release(row); eq(#targetClicks, before)
    row = showEnemy(first); press(row)
    showEnemy(clickableEnemy("nameplate1", "Enemy-C"))
    release(row); eq(#targetClicks, before)
    row = showEnemy(first); press(row)
    local updated = clickableEnemy(); updated.state, updated.label = "danger", "OFF YOU"
    showEnemy(updated); release(row)
    eq(#targetClicks, before + 1); eq(targetClicks[#targetClicks].guid, first.guid)
end)

test("hiding or disabling a row clears a pending target click", function()
    local item = clickableEnemy()
    local row = showEnemy(item)
    local before = #targetClicks
    press(row)
    snapshot.enemies = {}; ui:Render(snapshot)
    eq(row.shown, false)
    showEnemy(item); release(row); eq(#targetClicks, before)
    press(row); showEnemy(item, true); showEnemy(item, false)
    release(row); eq(#targetClicks, before)
end)

test("enemy rows and native buttons have mouse-transparent thin black outlines", function()
    local row = showEnemy(clickableEnemy())
    local controls = 0
    for _, control in ipairs(frames) do
        if control.kind == "Button" and (control == row or control.template == "UIPanelButtonTemplate") then
            controls = controls + 1
            local outline
            for _, child in ipairs(frames) do
                if child.parent == control and child.kind == "Frame" and child.mouseEnabled == false then outline = child; break end
            end
            assert(outline, "actionable control is missing an outline")
            eq(next(outline.scripts), nil)
            local edges = 0
            for _, child in ipairs(objects) do
                if child.parent == outline and child.kind == "Texture" and (child.width == 1 or child.height == 1) then edges = edges + 1 end
            end
            eq(edges, 4)
        end
    end
    eq(controls, 4)
end)

-- Export only to the remainder of this test file if a Core smoke test follows.
TankWatchMock = { ns = ns, objects = objects, frames = frames, methods = methods,
    secret = secret, test = test, eq = eq, hasText = hasText }
print("UI PASS: " .. passed .. " mocked-client cases")

local uiPassed = passed
local units, threats, percentages = {}, {}, {}
local raid, groupCount, clock, sounds = false, 0, 100, 0
local secretTargets, hideGUIDs = false, false
local lastSnapshot
local core
local originalCreateUI = ns.CreateUI
ns.CreateUI = function(settings)
    local result = originalCreateUI(settings)
    local render = result.Render
    result.Render = function(self, data) lastSnapshot = data; return render(self, data) end
    return result
end
local function reset()
    units = {
        player = { id = "self", name = "Tank", role = "TANK", player = true, combat = false },
        party1 = { id = "healer", name = "Healer", role = "HEALER", player = true },
        party2 = { id = "damage", name = "Damage", role = "DAMAGER", player = true },
    }
    threats, percentages = {}, {}
    raid, groupCount, secretTargets, hideGUIDs = false, 3, false, false
    if core then core.scripts.OnEvent(core, "GROUP_ROSTER_UPDATE") end
end
local function addEnemy(token, id, combat)
    units[token] = { id = id, name = id, enemy = true, combat = combat }
    return units[token]
end
local function setThreat(member, enemy, status, percent)
    threats[member] = threats[member] or {}; threats[member][enemy] = status
    percentages[member] = percentages[member] or {}; percentages[member][enemy] = percent
end
UnitExists = function(unit) return units[unit] ~= nil end
UnitName = function(unit) return units[unit] and units[unit].name end
UnitGUID = function(unit) if not hideGUIDs then return units[unit] and units[unit].id end end
UnitGroupRolesAssigned = function(unit) return units[unit] and units[unit].role or "NONE" end
UnitIsUnit = function(a, b)
    if secretTargets and a ~= "target" and a:match("target$") then return secret() end
    return units[a] ~= nil and units[b] ~= nil and units[a].id == units[b].id
end
UnitCanAttack = function(_, unit) return units[unit] ~= nil and units[unit].enemy == true end
UnitIsDeadOrGhost = function(unit) return units[unit] ~= nil and units[unit].dead == true end
UnitIsPlayer = function(unit) return units[unit] ~= nil and units[unit].player == true end
UnitAffectingCombat = function(unit) return units[unit] ~= nil and units[unit].combat == true end
UnitThreatSituation = function(member, enemy)
    local m, e = units[member], units[enemy]
    return m and e and threats[m.id] and threats[m.id][e.id]
end
UnitDetailedThreatSituation = function(member, enemy)
    local m, e = units[member], units[enemy]
    local value = m and e and percentages[m.id] and percentages[m.id][e.id]
    return nil, nil, value
end
UnitThreatLeadSituation = function(_, enemy) return units[enemy] and units[enemy].lead end
GetRaidTargetIndex = function(unit) return units[unit] and units[unit].marker end
IsInRaid = function() return raid end
GetNumGroupMembers = function() return groupCount end
GetTime = function() return clock end
GetBuildInfo = function() return "1.60.1", "70888", "", 16001 end
PlaySound = function() sounds = sounds + 1 end
DEFAULT_CHAT_FRAME = { messages = {}, AddMessage = function(self, message) self.messages[#self.messages + 1] = message end }
SlashCmdList = {}
reset()
assert(loadfile(TEST_ROOT .. "/TankWatch/Core.lua"))("TankWatch", ns)
core = frames[#frames]
local function event(name, arg) core.scripts.OnEvent(core, name, arg) end
local function tick() core.scripts.OnUpdate(core, 0.31) end

test("entire addon initializes from ADDON_LOADED and registers commands", function()
    event("ADDON_LOADED", "UnrelatedAddon")
    eq(SlashCmdList.TANKWATCH, nil)
    event("ADDON_LOADED", "TankWatch")
    assert(type(SlashCmdList.TANKWATCH) == "function")
    eq(SLASH_TANKWATCH2, "/tw")
    eq(#lastSnapshot.enemies, 0)
    local count = #frames
    event("ADDON_LOADED", "TankWatch")
    eq(#frames, count)
end)
test("idle mobs without group threat are excluded", function()
    reset(); addEnemy("nameplate1", "IdleMob", false)
    eq(#ns.BuildSnapshot().enemies, 0)
end)
test("nearby unrelated combat is excluded", function()
    reset(); units.player.combat = true; addEnemy("nameplate1", "StrangersMob", true)
    eq(#ns.BuildSnapshot().enemies, 0)
end)
test("dead, friendly, and player-controlled enemies are excluded", function()
    reset()
    addEnemy("nameplate1", "DeadMob", true).dead = true
    addEnemy("nameplate2", "Friendly", true).enemy = false
    addEnemy("nameplate3", "EnemyPlayer", true).player = true
    eq(#ns.BuildSnapshot().enemies, 0)
end)
test("GUID aliases do not duplicate selected enemy nameplates", function()
    reset(); local mob = addEnemy("target", "Mob", true); units.nameplate1 = mob; units.focus = mob
    setThreat("self", "Mob", 3, 100)
    eq(#ns.BuildSnapshot().enemies, 1)
end)
test("readable unit comparison deduplicates when GUIDs are missing", function()
    reset(); local mob = addEnemy("target", "Mob", true); units.nameplate1 = mob; hideGUIDs = true
    setThreat("self", "Mob", 3, 100)
    eq(#ns.BuildSnapshot().enemies, 1)
end)
test("group panel requires a hostile non-player target", function()
    reset(); addEnemy("nameplate1", "Mob", true)
    eq(#ns.BuildSnapshot().members, 0)
    units.target = units.party1
    eq(#ns.BuildSnapshot().members, 0)
end)
test("raid roster contains the player exactly once", function()
    reset(); raid = true; groupCount = 3
    units.raid1 = units.player; units.raid2 = units.party1; units.raid3 = units.party2
    addEnemy("target", "Mob", true)
    local snapshot = ns.BuildSnapshot()
    eq(#snapshot.members, 3)
    local count = 0
    for _, member in ipairs(snapshot.members) do if member.isPlayer then count = count + 1 end end
    eq(count, 1)
end)
test("restricted target identity does not prevent readable group ownership", function()
    reset(); addEnemy("nameplate1", "Mob", true)
    units.nameplate1target = { id = "healer", name = secret(), player = true }
    secretTargets = true
    setThreat("self", "Mob", 0, secret()); setThreat("healer", "Mob", 3, secret())
    local enemy = ns.BuildSnapshot().enemies[1]
    eq(enemy.state, "danger")
    eq(enemy.targetName, "Unknown / restricted")
    eq(enemy.targetDisplayable, true)
    assert(issecretvalue(enemy.targetDisplay))
end)
test("ambiguous threat holders never produce a taunt warning", function()
    reset(); addEnemy("nameplate1", "Mob", true)
    setThreat("self", "Mob", 0, 40)
    setThreat("healer", "Mob", 3, 100); setThreat("damage", "Mob", 3, 100)
    eq(ns.BuildSnapshot().enemies[1].state, "attention")
end)
test("readable target differing from threat holder flags possible fixate", function()
    reset(); addEnemy("nameplate1", "Mob", true); units.nameplate1target = units.party1
    setThreat("self", "Mob", 3, 100)
    eq(ns.BuildSnapshot().enemies[1].state, "attention")
end)
test("fully restricted threat and marker values remain unknown", function()
    reset(); units.player.combat = true; addEnemy("nameplate1", "Mob", true).marker = secret()
    setThreat("self", "Mob", secret(), secret())
    setThreat("healer", "Mob", secret(), secret()); setThreat("damage", "Mob", secret(), secret())
    local enemy = ns.BuildSnapshot().enemies[1]
    eq(enemy.state, "unknown"); eq(enemy.marker, nil)
end)
test("demo is silent and automatically ends when combat starts", function()
    reset(); local before = sounds
    ns.ToggleDemo(); eq(lastSnapshot.demo, true); eq(sounds, before)
    units.player.combat = true
    event("PLAYER_REGEN_DISABLED"); tick()
    assert(not lastSnapshot.demo)
end)
test("danger sounds only in player combat and once per transition", function()
    reset(); addEnemy("nameplate1", "Mob", true)
    setThreat("self", "Mob", 0, 30); setThreat("healer", "Mob", 3, 100)
    local before = sounds
    clock = clock + 10; event("PLAYER_ENTERING_WORLD"); tick()
    eq(sounds, before)
    units.player.combat = true; event("PLAYER_REGEN_DISABLED"); tick()
    eq(sounds, before + 1)
    clock = clock + 10; tick()
    eq(sounds, before + 1)
end)
test("co-tank ownership produces no loss sound", function()
    reset(); addEnemy("nameplate1", "Mob", true); units.party1.role = "TANK"; units.player.combat = true
    setThreat("self", "Mob", 0, 30); setThreat("healer", "Mob", 3, 100)
    clock = clock + 10; local before = sounds
    event("PLAYER_REGEN_DISABLED"); tick()
    eq(lastSnapshot.enemies[1].state, "cotank"); eq(sounds, before)
end)
test("manual tank designation handles parties without assigned roles", function()
    reset(); addEnemy("nameplate1", "Mob", true); units.party1.role = "NONE"
    setThreat("self", "Mob", 0, 30); setThreat("healer", "Mob", 3, 100)
    SlashCmdList.TANKWATCH("tank Healer")
    eq(ns.BuildSnapshot().enemies[1].state, "cotank")
    SlashCmdList.TANKWATCH("tank Healer")
    eq(ns.BuildSnapshot().enemies[1].state, "danger")
end)
test("persistent pending alert survives global cooldown and sounds once", function()
    reset(); units.player.combat = true; addEnemy("nameplate1", "Mob", true)
    setThreat("self", "Mob", 2, 100)
    clock = clock + 10; event("PLAYER_REGEN_DISABLED"); tick()
    local before = sounds
    clock = clock + 1
    setThreat("self", "Mob", 0, 40); setThreat("healer", "Mob", 3, 100)
    tick(); eq(sounds, before)
    clock = clock + 4; tick(); eq(sounds, before + 1)
    clock = clock + 5; tick(); eq(sounds, before + 1)
end)
test("pending loss alert is cancelled when threat recovers", function()
    reset(); units.player.combat = true; addEnemy("nameplate1", "Mob", true)
    setThreat("self", "Mob", 2, 100)
    clock = clock + 10; event("PLAYER_REGEN_DISABLED"); tick()
    local before = sounds
    clock = clock + 1; setThreat("self", "Mob", 0, 40); setThreat("healer", "Mob", 3, 100); tick()
    setThreat("self", "Mob", 3, 100); setThreat("healer", "Mob", 0, 40); tick()
    clock = clock + 5; tick(); eq(sounds, before)
end)
test("tab-targeting does not repeat a nameplate loss alert", function()
    reset(); units.player.combat = true; local mob = addEnemy("nameplate1", "Mob", true)
    setThreat("self", "Mob", 0, 30); setThreat("healer", "Mob", 3, 100)
    hideGUIDs = true
    clock = clock + 10; event("PLAYER_REGEN_DISABLED"); tick()
    local before = sounds
    units.target = mob; event("PLAYER_TARGET_CHANGED"); clock = clock + 5; tick()
    eq(#lastSnapshot.enemies, 1); eq(sounds, before)
    units.target = nil; event("PLAYER_TARGET_CHANGED"); clock = clock + 5; tick()
    eq(#lastSnapshot.enemies, 1); eq(sounds, before)
end)
test("secret event payload cannot become a history table key", function()
    event("NAME_PLATE_UNIT_REMOVED", secret()); tick()
end)
test("slash visibility, reset, diagnostic, and sound controls execute", function()
    reset()
    for _, command in ipairs({ "hide", "show", "reset", "diag", "sound", "sound", "help" }) do
        SlashCmdList.TANKWATCH(command)
    end
    eq(TankWatchDB.visible, true)
    eq(TankWatchDB.sound, true)
end)

test("character toggle hides the real panel and resumes live mode", function()
    reset(); ns.ToggleDemo()
    eq(lastSnapshot.demo, true)
    TankWatchPanel:StartMoving()
    SlashCmdList.TANKWATCH("off")
    eq(TankWatchCharDB.enabled, false)
    eq(TankWatchPanel.shown, false)
    eq(TankWatchPanel.moving, false)
    for _, command in ipairs({ "show", "test", "reset" }) do
        SlashCmdList.TANKWATCH(command)
        eq(TankWatchPanel.shown, false)
    end
    SlashCmdList.TANKWATCH("on")
    eq(TankWatchCharDB.enabled, true)
    eq(TankWatchPanel.shown, true)
    assert(not lastSnapshot.demo)
end)
print("CORE PASS: " .. (passed - uiPassed) .. " mocked-client cases")
