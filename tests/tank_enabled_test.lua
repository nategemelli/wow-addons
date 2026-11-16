-- Per-character enablement is tested with separate saved-variable tables and
-- counters for client queries, rendering, and alerts. This is not an engine test.
local passed = 0
local function test(name, fn)
    local ok, message = pcall(fn)
    if not ok then error("FAIL: " .. name .. ": " .. tostring(message)) end
    passed = passed + 1
end
local function eq(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function noop() end

local function boot(character, account)
    local env = { queries = 0, scans = 0, renders = 0, sounds = 0, targets = 0,
        messages = {}, now = 100, threats = {}, visible = nil }
    env.units = {
        player = { guid = "Player-self", name = "Tank", player = true, role = "TANK" },
        party1 = { guid = "Player-ally", name = "Healer", player = true, role = "HEALER" },
        nameplate1 = { guid = "Creature-first", name = "First enemy", hostile = true, combat = true },
    }
    local function api(name, fn)
        _G[name] = function(...)
            env.queries = env.queries + 1
            return fn(...)
        end
    end
    issecretvalue = function() return false end
    api("UnitExists", function(unit) return env.units[unit] ~= nil end)
    api("UnitName", function(unit) return env.units[unit] and env.units[unit].name end)
    api("UnitGUID", function(unit) return env.units[unit] and env.units[unit].guid end)
    api("UnitGroupRolesAssigned", function(unit) return env.units[unit] and env.units[unit].role or "NONE" end)
    api("UnitCanAttack", function(_, unit) return env.units[unit] ~= nil and env.units[unit].hostile == true end)
    api("UnitIsDeadOrGhost", function(unit) return env.units[unit] ~= nil and env.units[unit].dead == true end)
    api("UnitIsPlayer", function(unit) return env.units[unit] ~= nil and env.units[unit].player == true end)
    api("UnitAffectingCombat", function(unit) return env.units[unit] ~= nil and env.units[unit].combat == true end)
    api("UnitIsUnit", function(a, b) return env.units[a] ~= nil and env.units[a] == env.units[b] end)
    api("InCombatLockdown", function() return env.units.player.combat == true end)
    api("UnitThreatSituation", function(member, unit)
        if env.units[unit] and env.units[unit].hostile then return env.threats[member] end
    end)
    api("UnitDetailedThreatSituation", function() return nil, nil, 100 end)
    api("UnitThreatLeadSituation", function() return 0 end)
    api("GetRaidTargetIndex", function() return nil end)
    api("GetNumGroupMembers", function() return 2 end)
    api("IsInRaid", function() return false end)
    api("GetTime", function() return env.now end)
    api("GetBuildInfo", function() return "1.60.1", "70888", "", 16001 end)
    PlaySound = function() env.sounds = env.sounds + 1 end
    TargetUnit = function() env.targets = env.targets + 1 end
    UIParent = {}
    CreateFrame = function()
        local frame = { scripts = {}, events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(event, fn) self.scripts[event] = fn end
        env.core = frame
        return frame
    end
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) env.messages[#env.messages + 1] = message end }
    TankWatchDB, TankWatchCharDB, SlashCmdList = account, character, {}
    local ns = {}
    env.ns = ns
    assert(loadfile(TEST_ROOT .. "/TankWatch/Model.lua"))("TankWatch", ns)
    ns.CreateUI = function(settings)
        local panel = { ClearAllPoints = noop, SetPoint = noop, StopMovingOrSizing = noop }
        return {
            frame = panel,
            Render = function(_, snapshot)
                env.renders = env.renders + 1
                env.snapshot = snapshot
            end,
            SetVisible = function(_, visible) env.visible = visible end,
            SetLocked = function(_, locked) settings.locked = locked end,
        }
    end
    assert(loadfile(TEST_ROOT .. "/TankWatch/Core.lua"))("TankWatch", ns)
    local build = ns.BuildSnapshot
    ns.BuildSnapshot = function(...)
        env.scans = env.scans + 1
        return build(...)
    end
    function env:event(name, arg) self.core.scripts.OnEvent(self.core, name, arg) end
    function env:tick(delta) self.core.scripts.OnUpdate(self.core, delta or 0.31) end
    function env:command(message) SlashCmdList.TANKWATCH(message) end
    env:event("ADDON_LOADED", "TankWatch")
    env.character, env.account = TankWatchCharDB, TankWatchDB
    return env
end

test("manifest saves enablement per character while keeping existing settings account-wide", function()
    local file = assert(io.open(TEST_ROOT .. "/TankWatch/TankWatch.toc", "r"))
    local toc = file:read("*a"); file:close()
    assert(toc:match("## SavedVariablesPerCharacter:%s*TankWatchCharDB%s*[\r\n]"))
    assert(toc:match("## SavedVariables:%s*TankWatchDB%s*[\r\n]"))
end)

test("new characters and invalid saved enablement default to enabled", function()
    for _, settings in ipairs({ {}, { enabled = "false" } }) do
        local env = boot(settings)
        eq(env.character.enabled, true)
        eq(env.visible, true)
        assert(env.scans > 0 and env.renders > 0)
        eq(env.account.sound, true)
        eq(SLASH_TANKWATCH2, "/tw")
    end
    local env = boot()
    eq(env.character.enabled, true)
end)

test("a disabled character starts hidden without any client queries or snapshots", function()
    local env = boot({ enabled = false }, { visible = true, sound = true })
    eq(env.character.enabled, false)
    eq(env.visible, false)
    eq(env.queries, 0); eq(env.scans, 0); eq(env.renders, 0); eq(env.sounds, 0)
    env:tick(10)
    env:event("PLAYER_ENTERING_WORLD")
    env:tick(10)
    eq(env.queries, 0); eq(env.scans, 0); eq(env.renders, 0); eq(env.sounds, 0)
end)

test("off persists across reload and does not turn off other characters or overwrite account settings", function()
    local position = { point = "TOP", relativePoint = "TOP", x = 42, y = -78 }
    local tanks = { other = true }
    local account = { visible = true, sound = false, locked = true, tanks = tanks, position = position }
    local first = boot(nil, account)
    first:command("off")
    eq(first.character.enabled, false)
    eq(account.visible, true); eq(account.sound, false); eq(account.locked, true)
    eq(account.position, position); eq(account.tanks, tanks)
    eq(account.enabled, nil)
    local other = boot(nil, account)
    eq(other.character.enabled, true); eq(other.visible, true)
    eq(first.character.enabled, false)
    local reloaded = boot(first.character, account)
    eq(reloaded.character.enabled, false); eq(reloaded.visible, false)
    eq(reloaded.scans, 0); eq(reloaded.renders, 0)
    reloaded:command("on")
    eq(first.character.enabled, true); eq(reloaded.visible, true)
    eq(account.sound, false); eq(account.locked, true)
    eq(account.position, position); eq(account.tanks, tanks)
end)

test("disabled panel commands explain how to resume and cannot scan or reveal the panel", function()
    local env = boot({ enabled = false })
    for _, command in ipairs({ "test", "show", "reset" }) do
        env.messages = {}
        env:command(command)
        eq(env.visible, false); eq(env.character.enabled, false)
        eq(env.scans, 0); eq(env.renders, 0)
        assert(table.concat(env.messages, "\n"):find("/tw on", 1, true), command .. " needs an enable hint")
    end
    for _, command in ipairs({ "sound", "lock", "tank Other", "diag", "help" }) do
        env:command(command)
        eq(env.visible, false); eq(env.character.enabled, false)
        eq(env.scans, 0); eq(env.renders, 0); eq(env.sounds, 0)
    end
    eq(env.account.sound, false); eq(env.account.locked, true); eq(env.account.tanks.other, true)
end)

test("off during combat silences queued warnings and all event or polling work", function()
    local env = boot()
    env.units.player.combat = true
    env.threats.player = 2
    env:event("PLAYER_REGEN_DISABLED"); env:tick()
    eq(env.sounds, 1)
    env.now = env.now + 1
    env.threats.player, env.threats.party1 = 0, 3
    env:tick()
    eq(env.sounds, 1) -- The loss warning is waiting for the four-second cooldown.
    env:command("off")
    eq(env.visible, false)
    local queries, scans, renders, sounds = env.queries, env.scans, env.renders, env.sounds
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_REMOVED", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED" }) do
        env.now = env.now + 10
        env:event(event, "nameplate1"); env:tick()
    end
    eq(env.queries, queries); eq(env.scans, scans); eq(env.renders, renders); eq(env.sounds, sounds)
    local accepted, reason = env.ns.TargetEnemy({ unit = "nameplate1", guid = "Creature-first" })
    eq(accepted, false); assert(type(reason) == "string")
    eq(env.targets, 0); eq(env.queries, queries)
    env.threats.player, env.threats.party1 = 3, 0
    env:command("on")
    eq(env.snapshot.enemies[1].state, "safe"); eq(env.sounds, sounds)
    env.now = env.now + 10; env:tick()
    eq(env.sounds, sounds)
end)

test("reenabling leaves demo and refreshes a roster that changed while disabled", function()
    local env = boot()
    env.units.target = env.units.nameplate1
    env.threats.player, env.threats.party1 = 0, 3
    env:tick()
    eq(env.snapshot.enemies[1].state, "danger")
    env:command("test"); eq(env.snapshot.demo, true)
    env.ns.SetEnabled(false)
    env.units.party1.name, env.units.party1.role = "New tank", "TANK"
    env:event("GROUP_ROSTER_UPDATE")
    local scans = env.scans
    env:tick(); eq(env.scans, scans)
    env.ns.SetEnabled(true)
    eq(env.character.enabled, true); eq(env.visible, true)
    assert(not env.snapshot.demo)
    eq(env.snapshot.enemies[1].state, "cotank")
    eq(env.snapshot.members[2].name, "New tank"); eq(env.snapshot.members[2].role, "TANK")
end)

test("enable aliases restore a hidden panel and start a fresh warning cooldown", function()
    local env = boot()
    env.units.player.combat = true
    env.threats.player = 2
    env:event("PLAYER_REGEN_DISABLED"); env:tick()
    eq(env.sounds, 1)
    env:command("hide"); eq(env.account.visible, false)
    env:command("disable"); eq(env.character.enabled, false)
    env.now = env.now + 1
    env:command("enable")
    eq(env.character.enabled, true); eq(env.visible, true); eq(env.account.visible, true)
    eq(env.sounds, 2)
    env:tick(); eq(env.sounds, 2)
end)

print("TANK ENABLED PASS: " .. passed .. " mocked-client cases")
