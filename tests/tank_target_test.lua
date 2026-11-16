-- Core targeting guard with deterministic native APIs. WoW's protected-action
-- enforcement still requires an in-game check; these tests validate our gates.
local ns, core, units, lastSnapshot, requests, messages
local combatLock, combatUnknown, failTarget, hideGUID, unitUnknown
local function noop() end
local function secret() return { secretValue = true } end
issecretvalue = function(value) return type(value) == "table" and value.secretValue == true end

local passed = 0
local function test(name, fn)
    local ok, message = pcall(fn)
    if not ok then error("FAIL: " .. name .. ": " .. tostring(message)) end
    passed = passed + 1
end
local function eq(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function boot()
    requests, messages = {}, {}
    combatLock, combatUnknown, failTarget, hideGUID, unitUnknown = false, false, false, false, false
    units = {
        player = { guid = "Player-self", name = "Tank", player = true, role = "TANK", combat = false },
        party1 = { guid = "Player-healer", name = "Healer", player = true, role = "HEALER" },
        nameplate1 = { guid = "Creature-first", name = "First enemy", hostile = true, combat = true },
        nameplate2 = { guid = "Creature-second", name = "Second enemy", hostile = true, combat = true },
    }
    CreateFrame = function()
        local frame = { scripts = {}, events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:SetScript(event, fn) self.scripts[event] = fn end
        core = frame
        return frame
    end
    InCombatLockdown = function() return combatUnknown and secret() or combatLock end
    UnitAffectingCombat = function(unit) return units[unit] ~= nil and units[unit].combat == true end
    UnitExists = function(unit) return units[unit] ~= nil end
    UnitCanAttack = function(_, unit) return units[unit] ~= nil and units[unit].hostile == true end
    UnitIsDeadOrGhost = function(unit)
        if unitUnknown then return secret() end
        return units[unit] ~= nil and units[unit].dead == true
    end
    UnitIsPlayer = function(unit) return units[unit] ~= nil and units[unit].player == true end
    UnitGUID = function(unit)
        if hideGUID then return secret() end
        return units[unit] and units[unit].guid
    end
    UnitName = function(unit) return units[unit] and units[unit].name end
    UnitIsUnit = function(a, b) return units[a] ~= nil and units[a] == units[b] end
    UnitGroupRolesAssigned = function(unit) return units[unit] and units[unit].role or "NONE" end
    UnitThreatSituation = function(member, unit)
        if units[unit] and units[unit].hostile then return member == "player" and 3 or 0 end
    end
    UnitDetailedThreatSituation = function() return nil, nil, 100 end
    UnitThreatLeadSituation = function() return 0 end
    GetRaidTargetIndex = function() return nil end
    GetNumGroupMembers = function() return 2 end
    IsInRaid = function() return false end
    GetTime = function() return 100 end
    PlaySound = noop
    TargetUnit = function(unit)
        if failTarget then error("native targeting blocked") end
        requests[#requests + 1] = unit
        units.target = units[unit]
    end
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) messages[#messages + 1] = text end }
    TankWatchDB, SlashCmdList = nil, {}
    ns = {}
    assert(loadfile(TEST_ROOT .. "/TankWatch/Model.lua"))("TankWatch", ns)
    ns.CreateUI = function()
        return { Render = function(_, snapshot) lastSnapshot = snapshot end,
            SetVisible = noop, SetLocked = noop }
    end
    assert(loadfile(TEST_ROOT .. "/TankWatch/Core.lua"))("TankWatch", ns)
    core.scripts.OnEvent(core, "ADDON_LOADED", "TankWatch")
end

local function item(unit)
    unit = unit or "nameplate1"
    for _, row in ipairs(ns.BuildSnapshot().enemies) do if row.unit == unit then return row end end
    error("missing enemy row: " .. unit)
end
local function rejects(row)
    local count = #requests
    local ok, reason = ns.TargetEnemy(row)
    eq(ok, false); assert(type(reason) == "string" and #reason > 0)
    eq(#requests, count)
    assert(#messages > 0)
end

test("snapshots expose verified identity without targeting automatically", function()
    boot()
    eq(lastSnapshot.targetingLocked, false)
    eq(item().guid, "Creature-first"); eq(#requests, 0)
    for _ = 1, 4 do
        ns.BuildSnapshot()
        core.scripts.OnUpdate(core, 0.31)
    end
    eq(#requests, 0)
end)

test("one explicit request targets the displayed token and target events refresh group threat", function()
    boot()
    eq(#lastSnapshot.members, 0)
    local ok = ns.TargetEnemy(item("nameplate2"))
    eq(ok, true); eq(#requests, 1); eq(requests[1], "nameplate2")
    core.scripts.OnEvent(core, "PLAYER_TARGET_CHANGED")
    core.scripts.OnUpdate(core, 0.31)
    eq(lastSnapshot.targetName, "Second enemy"); eq(#lastSnapshot.members, 2)
    eq(#requests, 1)
end)

test("combat beginning after a row was rendered rejects the click", function()
    boot(); local row = item()
    combatLock = true
    rejects(row); eq(ns.BuildSnapshot().targetingLocked, true)
    combatLock = false; units.player.combat = true
    rejects(row); eq(ns.BuildSnapshot().targetingLocked, true)
end)

test("unknown combat status fails closed", function()
    boot(); local row = item()
    combatUnknown = true; rejects(row); eq(ns.BuildSnapshot().targetingLocked, true)
    InCombatLockdown = nil; rejects(row)
    InCombatLockdown = function() return false end
    UnitAffectingCombat = function() return secret() end
    rejects(row); eq(ns.BuildSnapshot().targetingLocked, true)
end)

test("recycled or restricted identities never target another mob", function()
    boot(); local row = item()
    units.nameplate1 = { guid = "Creature-replacement", name = "Replacement", hostile = true }
    rejects(row)
    units.nameplate1.guid = row.guid; hideGUID = true
    rejects(row)
    hideGUID = false; row.guid = nil; rejects(row)
    row.guid = secret(); rejects(row)
end)

test("liveness hostility and player checks are repeated at click time", function()
    for _, change in ipairs({ "gone", "dead", "friendly", "player", "unknown" }) do
        boot(); local row = item()
        if change == "gone" then units.nameplate1 = nil
        elseif change == "dead" then units.nameplate1.dead = true
        elseif change == "friendly" then units.nameplate1.hostile = false
        elseif change == "player" then units.nameplate1.player = true
        else unitUnknown = true end
        rejects(row)
    end
end)

test("samples and arbitrary tokens cannot request targets", function()
    boot()
    rejects(nil); rejects({ name = "Sample" }); rejects({ unit = "mouseover", guid = "Creature-first" })
    rejects({ unit = secret(), guid = "Creature-first" })
    local row = item(); row.demo = true; rejects(row)
    row.demo = nil; ns.ToggleDemo(); rejects(row)
    eq(#requests, 0)
end)

test("native API failures leave the addon usable", function()
    boot(); local row = item()
    TargetUnit = nil; rejects(row)
    TargetUnit = function() error("blocked") end; rejects(row)
    core.scripts.OnUpdate(core, 0.31)
    eq(#lastSnapshot.enemies, 2); eq(#requests, 0)
end)

print("TANK TARGET PASS: " .. passed .. " mocked-client cases")
