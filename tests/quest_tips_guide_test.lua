local ns = {
    hints = { [42] = "Open the basket beside the wagon." },
    turnInHints = { [42] = "Look for the farmer upstairs." },
}
assert(loadfile(TEST_ROOT .. "/QuestTips/Guide.lua"))("QuestTips", ns)
local locale = "enUS"
GetLocale = function() return locale end
local function section(lines, label)
    for _, line in ipairs(lines) do
        if line.label == label then return line.text end
    end
end
local function test(name, fn)
    fn()
    print("PASS QuestTips guide " .. name)
end

test("uses the correct quest stage, remaining counts and client clues", function()
    local q = {
        id = 42, objectives = {
            { text = "Gather berries", numRequired = 5, numFulfilled = 3, finished = false },
            { text = "Gather herbs", numRequired = 2, numFulfilled = 2, finished = true },
            { text = "1 / 4 carrots", numRequired = 4, numFulfilled = 1 },
            { text = "Fill the tank: 60%", type = "progressbar", numRequired = 1, numFulfilled = 0 },
        },
        item = "|Hitem:123|h[Basket]|h", waypoint = "Take the ferry", instructions = "Gather berries",
    }
    local lines = ns.GuideLines(q)
    assert(lines[1].text == ns.hints[42])
    assert(section(lines, "Remaining objectives") == "Gather berries (3/5)\n1 / 4 carrots\nFill the tank: 60%")
    assert(section(lines, "Quest item") == q.item and section(lines, "Next waypoint") == q.waypoint)
    assert(not section(lines, "Quest instructions"))
    q.id = 43
    assert(not section(ns.GuideLines(q), "Field tip"))
end)

test("pulls a location clue forward and keeps the other quest text", function()
    local q = { description = "I haven't heard from her.\r\n\r\nFind her.\n\nFollow the path east to the ford." }
    local lines = ns.GuideLines(q)
    assert(lines[1].text == "Follow the path east to the ford.")
    assert(section(lines, "Quest text") == "I haven't heard from her.\n\nFind her.")
    q.instructions = q.description
    assert(not section(ns.GuideLines(q), "Quest instructions"))
end)

test("keeps unrecognized and localized quest text intact", function()
    local paragraph = "The third candle is blue."
    assert(section(ns.GuideLines({ description = paragraph }), "Quest text") == paragraph)
    locale = "deDE"
    local lines = ns.GuideLines({ description = "Der Name ist West.\n\nUntersuche das Tor." })
    assert(#lines == 1 and lines[1].text == "Der Name ist West.\n\nUntersuche das Tor.")
    locale = "enUS"
end)

test("suppresses repeated client lines across fields", function()
    local q = {
        objectives = { { text = "Read the scroll" }, { text = "Read the scroll" } },
        description = "Read the scroll", instructions = "|cffffd100Read the scroll|r", waypoint = " Read the scroll ",
    }
    local lines = ns.GuideLines(q)
    assert(#lines == 1 and lines[1].text == "Read the scroll")
end)

test("turn-in uses current directions and omits the work already done", function()
    local q = {
        id = 42, complete = true, description = "Climb the tree.", instructions = "Find the basket.",
        objectives = { { text = "Find the basket" } }, waypoint = "Go to the farmhouse",
        completionText = "Return to the farmer.",
    }
    local lines = ns.GuideLines(q)
    assert(#lines == 3 and lines[1].text == q.completionText)
    assert(section(lines, "Turn-in tip") == ns.turnInHints[42] and section(lines, "Next waypoint") == q.waypoint)
    q.item = "Basket for delivery"
    assert(section(ns.GuideLines(q), "Quest item") == q.item)
    q.completionText, q.id = nil, 43
    assert(section(ns.GuideLines(q), "Ready to turn in"))
    q.failed = true
    lines = ns.GuideLines(q)
    assert(#lines == 1 and lines[1].label == "Quest failed")
end)

test("handles hidden text and missing data without inventing a target", function()
    local lines = ns.GuideLines({ id = 999, objectives = { { finished = false, text = "   " } } })
    assert(#lines == 1 and lines[1].label == "Quest details")
    assert(section(ns.GuideLines({ instructions = "Visit the baker." }), "Quest instructions") == "Visit the baker.")
end)
