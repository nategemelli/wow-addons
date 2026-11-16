local _, ns = ...

-- Secret values must be checked BEFORE nil tests, comparisons, or formatting.
function ns.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

function ns.Number(value)
    if ns.IsSecret(value) then return nil end
    if type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

function ns.Text(value, fallback)
    if ns.IsSecret(value) or type(value) ~= "string" then return fallback end
    -- Unit labels are plain text, not player-controlled UI escape sequences.
    return (value:gsub("|", "||"))
end

function ns.Bool(value)
    if ns.IsSecret(value) or type(value) ~= "boolean" then return nil end
    return value
end

function ns.Query(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
    ns.queryFailures = (ns.queryFailures or 0) + 1
    return nil
end

function ns.ReadThreat(unit, mob)
    local state = ns.Query(UnitThreatSituation, unit, mob)
    local _, _, percent = ns.Query(UnitDetailedThreatSituation, unit, mob)
    local secret = ns.IsSecret(percent)
    local ordinary = ns.Number(percent)
    return {
        status = ns.Number(state),
        restricted = ns.IsSecret(state),
        -- Native UI sinks may display a secret. No decisions depend on it.
        percent = percent,
        percentDisplayable = secret or ordinary ~= nil,
        readablePercent = ordinary,
    }
end

function ns.Classify(input)
    -- All input fields here have already passed the guards above.
    if input.holderRole == "TANK" and not input.holderIsPlayer then
        return "cotank", "OTHER TANK", "Threat held by another tank; check assignments.", 4
    end
    if input.playerStatus and input.playerStatus >= 2 then
        if input.targetIsGroup and not input.targetIsPlayer then
            return "attention", "TARGETING ALLY", "You hold threat; a fixate or mechanic may be active.", 2
        end
        if input.playerStatus == 2 or (input.leadStatus and input.leadStatus > 0) then
            return "warning", "LOSING LEAD", "Build threat; another player is close or above you.", 1
        end
        return "safe", "ON YOU", "You hold threat.", 5
    end
    if input.holderIsGroup then
        return "danger", "OFF YOU", "Threat held by a group member; check whether to taunt.", 0
    end
    if input.targetIsGroup and not input.targetIsPlayer then
        return "attention", "TARGETING ALLY", "Check this enemy; threat ownership is unavailable.", 2
    end
    if input.playerStatus ~= nil then
        return "attention", "NOT ON YOU", "You have threat, but the threat holder is unconfirmed.", 3
    end
    return "unknown", "UNKNOWN", "Threat data is restricted or unavailable.", 6
end

function ns.MemberLabel(status)
    if status == 3 then return "Holds aggro" end
    if status == 2 then return "Holds aggro / weak lead" end
    if status == 1 then return "Above tank / no aggro" end
    if status == 0 then return "Below tank" end
    return "No readable status"
end

function ns.SortEnemies(rows)
    table.sort(rows, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.order < b.order
    end)
end

function ns.SortMembers(rows)
    -- Never rank incomplete/protected numbers; retain stable roster order.
    for _, row in ipairs(rows) do
        if row.readablePercent == nil then return false end
    end
    table.sort(rows, function(a, b)
        if a.readablePercent ~= b.readablePercent then return a.readablePercent > b.readablePercent end
        return a.order < b.order
    end)
    return true
end

function ns.ShouldAlert(previous, state, now, lastAlert, cooldown)
    return (state == "danger" or state == "warning") and state ~= previous
        and now - lastAlert >= cooldown
end
