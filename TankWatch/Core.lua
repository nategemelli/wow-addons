local addonName, ns = ...
local frame = CreateFrame("Frame")
local ui, db, characterDB
local cachedRoster
local demo, elapsed = false, 0
local previous, pendingAlerts, lastAlert = {}, {}, -math.huge
local tokens = {}
for i = 1, 40 do tokens[#tokens + 1] = "nameplate" .. i end
for _, token in ipairs({ "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }) do
    tokens[#tokens + 1] = token
end
local targetTokens = {}
for _, token in ipairs(tokens) do targetTokens[token] = true end

local function Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff79c9e6TankWatch:|r " .. message) end
end

local function IsEnabled()
    return characterDB and characterDB.enabled == true
end

local function RequireEnabled()
    if IsEnabled() then return true end
    Print("Off for this character. Use /tw on to enable TankWatch.")
    return false
end

local function IsTrue(fn, ...)
    return ns.Bool(ns.Query(fn, ...)) == true
end

local function TargetingLocked()
    -- A hidden or unavailable combat state is not permission to perform a
    -- protected action. Recheck this at click time, not just while rendering.
    return ns.Bool(ns.Query(InCombatLockdown)) ~= false
        or ns.Bool(ns.Query(UnitAffectingCombat, "player")) ~= false
end

function ns.TargetEnemy(item)
    local function Reject(reason)
        Print(reason)
        return false, reason
    end
    if not IsEnabled() then
        return Reject("TankWatch is off for this character. Use /tw on to enable it.")
    end
    if TargetingLocked() then
        return Reject("Click targeting is locked during combat or while combat status is unavailable.")
    end
    if demo or ns.IsSecret(item) or type(item) ~= "table" then
        return Reject("Sample rows cannot target enemies. Switch TankWatch back to Live.")
    end
    local unit = ns.Text(item.unit)
    if not unit or not targetTokens[unit] or ns.Bool(item.demo) == true then
        return Reject("This row has no live enemy to target.")
    end
    if not IsTrue(UnitExists, unit) or not IsTrue(UnitCanAttack, "player", unit)
        or ns.Bool(ns.Query(UnitIsDeadOrGhost, unit)) ~= false
        or ns.Bool(ns.Query(UnitIsPlayer, unit)) ~= false then
        return Reject("That enemy is no longer available to target.")
    end
    -- Nameplate tokens can be recycled between refreshes. Never target a
    -- different mob merely because it now occupies the same token.
    local guid = ns.Text(ns.Query(UnitGUID, unit))
    if ns.IsSecret(item.guid) or type(item.guid) ~= "string" or item.guid == ""
        or not guid or guid ~= item.guid then
        return Reject("That enemy changed or its identity is unavailable. Wait for TankWatch to refresh.")
    end
    if type(TargetUnit) ~= "function" then
        return Reject("This client does not expose click targeting.")
    end
    -- This function is called only by a physical row click. No targeting is
    -- attempted by polling, sorting, hovering, alerts, or demo mode.
    local ok = pcall(TargetUnit, unit)
    if not ok then return Reject("The client blocked targeting. Use the game's targeting controls.") end
    return true
end

local function Roster()
    if cachedRoster then return cachedRoster end
    local list = {}
    local function Add(unit)
        if not IsTrue(UnitExists, unit) then return end
        local name = ns.Text(ns.Query(UnitName, unit), unit)
        local role = ns.Text(ns.Query(UnitGroupRolesAssigned, unit), "NONE")
        if db and db.tanks[name:lower()] then role = "TANK" end
        list[#list + 1] = {
            unit = unit,
            name = name,
            role = role,
            isPlayer = unit == "player" or IsTrue(UnitIsUnit, unit, "player"),
        }
    end
    Add("player")
    if IsInRaid() then
        for i = 1, math.min(40, GetNumGroupMembers()) do
            local unit = "raid" .. i
            if not IsTrue(UnitIsUnit, unit, "player") then Add(unit) end
        end
    else
        for i = 1, 4 do Add("party" .. i) end
    end
    cachedRoster = list
    return list
end

local function TargetInfo(mob, roster)
    local target = mob .. "target"
    local rawName = ns.Query(UnitName, target)
    local info = {
        name = ns.Text(rawName, "Unknown / restricted"),
        display = rawName,
        displayable = ns.IsSecret(rawName) or ns.Text(rawName) ~= nil,
    }
    if not IsTrue(UnitExists, target) then return info end
    for _, member in ipairs(roster) do
        local same = ns.Query(UnitIsUnit, target, member.unit)
        -- On restricted maps compound comparisons are secret. Do not infer
        -- identity from names or attempt any alternate route around this.
        if ns.IsSecret(same) then return info end
        if ns.Bool(same) then
            info.isGroup, info.isPlayer = true, member.isPlayer
            info.role = member.role
            break
        end
    end
    return info
end

local function Holder(mob, roster, playerStatus)
    if playerStatus and playerStatus >= 2 then
        return { name = roster[1] and roster[1].name or "You", isPlayer = true, role = "TANK" }, true
    end
    local holder, hasGroupThreat, ambiguous = nil, false, false
    for _, member in ipairs(roster) do
        if not member.isPlayer then
            local status = ns.Number(ns.Query(UnitThreatSituation, member.unit, mob))
            if status ~= nil then hasGroupThreat = true end
            if status and status >= 2 then
                -- Ambiguous ownership should never produce a taunt warning.
                if holder then ambiguous = true end
                holder = member
            end
        end
    end
    if ambiguous then holder = nil end
    return holder, hasGroupThreat
end

local function ReadEnemy(unit, roster, order, guid)
    if not IsTrue(UnitExists, unit) or not IsTrue(UnitCanAttack, "player", unit)
        or IsTrue(UnitIsDeadOrGhost, unit) or IsTrue(UnitIsPlayer, unit) then return nil end
    local queryUnit = IsTrue(UnitIsUnit, unit, "target") and "target" or unit
    local threat = ns.ReadThreat("player", queryUnit)
    if threat.status == nil and not IsTrue(UnitAffectingCombat, unit) then return nil end
    local holder, hasGroupThreat = Holder(unit, roster, threat.status)
    -- Mere nearby combat does not mean this enemy belongs to our pull.
    if threat.status == nil and not hasGroupThreat then
        if not (threat.restricted and IsTrue(UnitAffectingCombat, "player")
            and IsTrue(UnitAffectingCombat, unit)) then return nil end
    end
    local target = TargetInfo(unit, roster)
    local lead = ns.Number(ns.Query(UnitThreatLeadSituation, "player", unit))
    local state, label, detail, priority = ns.Classify({
        playerStatus = threat.status, leadStatus = lead,
        holderRole = holder and holder.role, holderIsPlayer = holder and holder.isPlayer,
        holderIsGroup = holder ~= nil,
        targetIsGroup = target.isGroup, targetIsPlayer = target.isPlayer,
    })
    if holder and not holder.isPlayer then detail = "Threat: " .. holder.name .. ". " .. detail end
    local marker = ns.Number(ns.Query(GetRaidTargetIndex, unit))
    if marker and (marker < 1 or marker > 8 or marker % 1 ~= 0) then marker = nil end
    local rawName = ns.Query(UnitName, unit)
    return {
        unit = unit, guid = guid, order = order, state = state, label = label, detail = detail, priority = priority,
        name = ns.Text(rawName, "Enemy (" .. unit .. ")"),
        nameDisplay = rawName, nameDisplayable = ns.IsSecret(rawName) or ns.Text(rawName) ~= nil,
        targetName = target.name, targetDisplay = target.display, targetDisplayable = target.displayable,
        percent = threat.percent, percentDisplayable = threat.percentDisplayable,
        marker = marker,
    }
end

function ns.BuildSnapshot()
    local roster, enemies, seenGUIDs = Roster(), {}, {}
    for order, unit in ipairs(tokens) do
        if IsTrue(UnitExists, unit) then
            local guid = ns.Text(ns.Query(UnitGUID, unit))
            local duplicate = guid and seenGUIDs[guid]
            if not duplicate then
                -- UnitIsUnit may return nil/secret for some token pairs.
                for _, enemy in ipairs(enemies) do
                    if IsTrue(UnitIsUnit, unit, enemy.unit) then duplicate = true; break end
                end
            end
            if not duplicate then
                local enemy = ReadEnemy(unit, roster, order, guid)
                if enemy then
                    enemies[#enemies + 1] = enemy
                    if guid then seenGUIDs[guid] = true end
                end
            end
        end
    end
    ns.SortEnemies(enemies)
    local members, targetName = {}, "Select an enemy"
    if IsTrue(UnitExists, "target") and IsTrue(UnitCanAttack, "player", "target")
        and not IsTrue(UnitIsPlayer, "target") then
        targetName = ns.Text(ns.Query(UnitName, "target"), "Selected enemy (name restricted)")
        for order, member in ipairs(roster) do
            local threat = ns.ReadThreat(member.unit, "target")
            members[#members + 1] = {
                name = member.name, role = member.role, isPlayer = member.isPlayer,
                statusLabel = threat.restricted and "Restricted" or ns.MemberLabel(threat.status),
                percent = threat.percent, percentDisplayable = threat.percentDisplayable,
                readablePercent = threat.readablePercent, order = order,
            }
        end
    end
    local ranked = ns.SortMembers(members)
    local danger, warning, unknown = 0, 0, 0
    for _, enemy in ipairs(enemies) do
        if enemy.state == "danger" then danger = danger + 1 end
        if enemy.state == "warning" then warning = warning + 1 end
        if enemy.state == "unknown" then unknown = unknown + 1 end
    end
    local headline = "Watching for combat"
    if #enemies > 0 then headline = "Watching " .. #enemies .. " engaged enemies" end
    if danger > 0 then headline = danger .. " enemies off you - check for taunts"
    elseif warning > 0 then headline = "Threat lead weakening - build threat" end
    return {
        enemies = enemies, members = members, targetName = targetName, headline = headline,
        targetingLocked = TargetingLocked(),
        summary = danger .. " off you  /  " .. warning .. " at risk  /  " .. unknown .. " unknown  |  "
            .. (ranked and #members > 0 and "Group sorted by aggro %" or "Group in roster order"),
    }
end

local function DemoSnapshot()
    local function Enemy(name, target, state, label, percent, marker, detail)
        return { name = name, targetName = target, state = state, label = label,
            percent = percent, percentDisplayable = true, marker = marker, detail = detail }
    end
    return {
        demo = true, targetName = "Training Marauder", headline = "DEMO - 1 enemy off you, 1 at risk",
        summary = "Sample data only. Test mode ends automatically when combat starts.",
        enemies = {
            Enemy("Training Marauder", "Mira (healer)", "danger", "OFF YOU", 72, 8, "Threat: Mira. Check whether to taunt."),
            Enemy("Training Brute", "You", "warning", "LOSING LEAD", 100, 7, "An ally is close to taking aggro."),
            Enemy("Training Sentinel", "You", "safe", "ON YOU", 100, nil, "You hold threat."),
            Enemy("Training Warden", "Other tank", "cotank", "OTHER TANK", 43, nil, "Check tank assignments before taunting."),
            Enemy("Training Stalker", "Rook", "attention", "TARGETING ALLY", 100, nil, "You hold threat; possible fixate."),
            { name = "Restricted encounter", targetName = "Unknown / restricted", state = "unknown",
                label = "UNKNOWN", detail = "Hidden data never produces an alert.", percentDisplayable = false },
        },
        members = {
            { name = "Mira", role = "HEALER", statusLabel = "Holds aggro", percentDisplayable = true, percent = 100 },
            { name = "You", role = "TANK", statusLabel = "Below tank", percentDisplayable = true, percent = 72, isPlayer = true },
            { name = "Rook", role = "DAMAGER", statusLabel = "Below tank", percentDisplayable = true, percent = 61 },
            { name = "Ember", role = "DAMAGER", statusLabel = "Below tank", percentDisplayable = true, percent = 40 },
            { name = "Vale", role = "DAMAGER", statusLabel = "Below tank", percentDisplayable = true, percent = 26 },
        },
    }
end

local function Update()
    if not ui or not IsEnabled() then return end
    if demo then ui:Render(DemoSnapshot()); return end
    local snapshot = ns.BuildSnapshot()
    local now, nextPrevious = GetTime(), {}
    local alert
    for _, enemy in ipairs(snapshot.enemies) do
        local guid = ns.Text(ns.Query(UnitGUID, enemy.unit))
        local key = guid or enemy.unit
        if enemy.state ~= previous[key] and (enemy.state == "danger" or enemy.state == "warning") then
            pendingAlerts[key] = enemy.state
        end
        if pendingAlerts[key] ~= enemy.state then pendingAlerts[key] = nil end
        if pendingAlerts[key] and ns.ShouldAlert(nil, enemy.state, now, lastAlert, db.alertCooldown) then
            alert = alert or { enemy = enemy, key = key }
        end
        nextPrevious[key] = enemy.state
    end
    previous = nextPrevious
    for key in pairs(pendingAlerts) do
        if not nextPrevious[key] then pendingAlerts[key] = nil end
    end
    if alert and IsTrue(UnitAffectingCombat, "player") then
        lastAlert = now
        pendingAlerts[alert.key] = nil
        if db.sound then PlaySound(8959, "Master") end
        -- Text remains in the panel; no party/raid chat messages are sent.
    elseif not IsTrue(UnitAffectingCombat, "player") then pendingAlerts = {} end
    ui:Render(snapshot)
    ui:SetVisible(db.visible)
end

function ns.SetEnabled(enabled)
    if not ui then return end
    characterDB.enabled = enabled == true
    demo, elapsed = false, 0
    previous, pendingAlerts, lastAlert = {}, {}, -math.huge
    cachedRoster = nil
    if characterDB.enabled then
        db.visible = true
        Update()
        Print("On for this character. Use /tw off to turn it off.")
    else
        ui.frame:StopMovingOrSizing()
        ui:SetVisible(false)
        Print("Off for this character: panel, scanning, and alerts disabled. Use /tw on to enable it.")
    end
end

function ns.ToggleDemo()
    if not RequireEnabled() then return end
    if IsTrue(UnitAffectingCombat, "player") then Print("Test mode is available outside combat."); return end
    demo = not demo
    db.visible = true
    ui:SetVisible(true)
    Update()
end

function ns.ToggleLock()
    db.locked = not db.locked
    ui:SetLocked(db.locked)
end

function ns.ToggleSound()
    db.sound = not db.sound
    Update()
end

local function Initialize()
    if type(TankWatchDB) ~= "table" then TankWatchDB = {} end
    db = TankWatchDB
    if type(TankWatchCharDB) ~= "table" then TankWatchCharDB = {} end
    characterDB = TankWatchCharDB
    if type(characterDB.enabled) ~= "boolean" then characterDB.enabled = true end
    if type(db.visible) ~= "boolean" then db.visible = true end
    if type(db.sound) ~= "boolean" then db.sound = true end
    if type(db.locked) ~= "boolean" then db.locked = false end
    if type(db.tanks) ~= "table" then db.tanks = {} end
    db.alertCooldown = 4
    if type(db.position) ~= "table" then db.position = nil end
    ui = ns.CreateUI(db)
    ui:SetLocked(db.locked)
    ui:SetVisible(IsEnabled() and db.visible)
    SLASH_TANKWATCH1, SLASH_TANKWATCH2 = "/tankwatch", "/tw"
    SlashCmdList.TANKWATCH = function(message)
        local command = message:lower():match("^%s*(%S+)") or ""
        if command == "on" or command == "enable" then ns.SetEnabled(true)
        elseif command == "off" or command == "disable" then ns.SetEnabled(false)
        elseif command == "test" then ns.ToggleDemo()
        elseif command == "sound" then ns.ToggleSound(); Print(db.sound and "Sound on." or "Sound muted.")
        elseif command == "lock" then ns.ToggleLock()
        elseif command == "tank" then
            local name = message:match("^%s*%S+%s+(.+)%s*$")
            if not name then
                Print("/tw tank Name toggles a manual other-tank designation. Use the name shown in the group list.")
            else
                name = name:gsub("%s+$", ""):lower()
                db.tanks[name] = not db.tanks[name] or nil
                cachedRoster = nil
                Print("Manual tank '" .. name .. "': " .. (db.tanks[name] and "on" or "off") .. ".")
                Update()
            end
        elseif command == "show" then
            if not RequireEnabled() then return end
            db.visible = true; ui:SetVisible(true); Update()
        elseif command == "hide" then db.visible = false; ui:SetVisible(false)
        elseif command == "reset" then
            if not RequireEnabled() then return end
            ui.frame:ClearAllPoints(); ui.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            db.position = nil; db.visible = true; ui:SetVisible(true)
        elseif command == "diag" then
            local version, build, _, interface = GetBuildInfo()
            Print("Client " .. version .. " / " .. build .. " / interface " .. interface
                .. "; API failures: " .. (ns.queryFailures or 0) .. ".")
            Print("Threat states: " .. type(UnitThreatSituation) .. "; lead states: " .. type(UnitThreatLeadSituation)
                .. "; secret checks: " .. type(issecretvalue) .. ".")
            Print("This character: " .. (IsEnabled() and "on" or "off") .. ". /tw on or /tw off changes it.")
        else
            Print("/tw on, off (this character), test, show, hide, lock, sound, tank Name, reset, diag.")
            Print("Off stops the panel and alerts; hide only hides the panel. Enable enemy nameplates (V).")
            Print("Percent is progress toward pulling aggro, not your safety margin. Hover rows for details.")
        end
    end
    Update()
    if IsEnabled() then
        Print("Loaded. /tw off disables this character; /tw test previews the panel; /tw help lists commands.")
    else
        Print("Off for this character. Use /tw on to enable TankWatch.")
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
frame:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg == addonName and not ui then Initialize() end
        return
    end
    if not ui or not IsEnabled() then return end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "PLAYER_ENTERING_WORLD" then
        cachedRoster = nil
    end
    if event == "PLAYER_REGEN_DISABLED" then demo = false; previous = {}; pendingAlerts = {} end
    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then previous = {}; pendingAlerts = {} end
    if event == "PLAYER_TARGET_CHANGED" then previous.target = nil; pendingAlerts.target = nil end
    if event == "NAME_PLATE_UNIT_REMOVED" and not ns.IsSecret(arg) and type(arg) == "string" then
        previous[arg] = nil; pendingAlerts[arg] = nil
    end
    elapsed = 0.3
end)
frame:SetScript("OnUpdate", function(_, delta)
    if not ui or not IsEnabled() then return end
    elapsed = elapsed + delta
    if elapsed >= 0.3 then elapsed = 0; Update() end
end)
