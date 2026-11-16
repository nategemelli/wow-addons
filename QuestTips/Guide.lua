local _, ns = ...

local function Clean(value)
    if type(value) ~= "string" then return "" end
    return (value:gsub("\r\n?", "\n"):match("^%s*(.-)%s*$"))
end

local function Key(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", " "):lower())
end

-- Choose an excerpt of the actual quest text. A direction can be useful even
-- when a quest has no authored tip or map pin. Preserve the remaining text.
local directions = {
    north = true, east = true, south = true, west = true,
    northeast = true, northwest = true, southeast = true, southwest = true,
    behind = true, beneath = true, beside = true, underneath = true, inside = true,
}
local actions = {
    use = true, equip = true, follow = true, enter = true, search = true,
    climb = true, dive = true, swim = true, travel = true, carry = true,
    bring = true, speak = true, find = true, gather = true, collect = true,
}

local function QuestText(description)
    local paragraphs, best, bestScore = {}, nil, 0
    local locale = GetLocale and GetLocale()
    for line in Clean(description):gmatch("[^\n]+") do
        local paragraph = Clean(line)
        if paragraph ~= "" then
            paragraphs[#paragraphs + 1] = paragraph
            if locale == "enUS" or locale == "enGB" then
                local direction, action = false, false
                for word in paragraph:lower():gmatch("%a+") do
                    direction = direction or directions[word]
                    action = action or actions[word]
                end
                local score = (direction and 2 or 0) + (action and 1 or 0)
                if score > bestScore then best, bestScore = #paragraphs, score end
            end
        end
    end
    local clue = best and table.remove(paragraphs, best)
    return clue, paragraphs
end

local function ObjectiveText(objective)
    local text = Clean(objective.text)
    local have, need = objective.numFulfilled, objective.numRequired
    if text ~= "" and type(have) == "number" and type(need) == "number"
        and have >= 0 and need > 0 and objective.type ~= "progressbar"
        and not text:match("%d+%s*/%s*%d+") and not text:match("%d+%s*%%") then
        return string.format("%s (%d/%d)", text, have, need)
    end
    return text
end

function ns.GuideLines(q)
    local lines, seen = {}, {}
    local function Unique(value)
        local text = Clean(value)
        local key = Key(text)
        if key ~= "" and not seen[key] then
            seen[key] = true
            return text
        end
    end
    local function Add(label, value)
        local text = Unique(value)
        if text then lines[#lines + 1] = { label = label, text = text } end
    end
    if q.failed then
        Add("Quest failed", "Open this quest in your log to review the failed attempt.")
        return lines
    end
    if q.complete then
        local completion = Clean(q.completionText)
        Add("Ready to turn in", completion ~= "" and completion or "Your quest log marks the objectives complete. Check the quest details for the turn-in.")
        Add("Turn-in tip", ns.turnInHints and ns.turnInHints[q.id])
        -- The log supplies this field at turn-in only for items still relevant.
        Add("Quest item", q.item)
        Add("Next waypoint", q.waypoint)
        return lines
    end

    Add("Field tip", ns.hints and ns.hints[q.id])
    local objectives = {}
    for _, objective in ipairs(q.objectives or {}) do
        if not objective.finished then
            local text = Unique(ObjectiveText(objective))
            if text then
                objectives[#objectives + 1] = text
                seen[Key(Clean(objective.text))] = true
            end
        end
    end
    if #objectives > 0 then
        lines[#lines + 1] = { label = "Remaining objectives", text = table.concat(objectives, "\n") }
        seen[Key(lines[#lines].text)] = true
    end
    local clue, context = QuestText(q.description)
    Add("From the quest giver", clue)
    Add("Quest item", q.item)
    Add("Next waypoint", q.waypoint)
    if Key(Clean(q.description)) ~= Key(Clean(q.instructions)) then
        Add("Quest instructions", q.instructions)
    end

    local remaining = {}
    for _, paragraph in ipairs(context) do
        local text = Unique(paragraph)
        if text then remaining[#remaining + 1] = text end
    end
    if #remaining > 0 then
        lines[#lines + 1] = { label = "Quest text", text = table.concat(remaining, "\n\n") }
    end
    if #lines == 0 then
        Add("Quest details", "Select this quest in your quest log to load its directions.")
    end
    return lines
end
