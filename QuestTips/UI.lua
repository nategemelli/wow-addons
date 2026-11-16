local _, ns = ...

local window
local width, height = 354, 332
local bodyWidth, bodyHeight = width - 68, height - 98

local function Button(parent, label, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    return button
end

local function WrappedText(parent, font)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    text:SetWidth(bodyWidth)
    text:SetWordWrap(true)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    return text
end

local function CreateWindow()
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER", UIParent, "CENTER", -108, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 14, -10)
    header:SetPoint("TOPRIGHT", -39, -10)
    header:SetHeight(30)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local name = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", 8, 0)
    name:SetText("QuestTips")
    frame.position = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.position:SetPoint("RIGHT", -4, 0)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() ns.Close() end)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 22, -44)
    scroll:SetSize(bodyWidth, bodyHeight)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(bodyWidth, bodyHeight)
    scroll:SetScrollChild(child)
    frame.scroll, frame.child = scroll, child
    frame.title = WrappedText(child, "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT")
    frame.body = WrappedText(child, "GameFontHighlight")
    frame.body:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -12)
    frame.body:SetSpacing(2)

    frame.prev = Button(frame, "Previous", 84, function() ns.Step(-1) end)
    frame.prev:SetPoint("BOTTOMLEFT", 18, 16)
    local selected = Button(frame, "Selected quest", 120, function() ns.FollowSelection() end)
    selected:SetPoint("BOTTOM", 0, 16)
    frame.next = Button(frame, "Next", 84, function() ns.Step(1) end)
    frame.next:SetPoint("BOTTOMRIGHT", -18, 16)
    return frame
end

function ns.Render(view)
    window = window or CreateWindow()
    local key = view.id or view.title
    local previousOffset = window.lastKey == key and window.scroll:GetVerticalScroll() or 0
    window.lastKey = key
    window:Show()
    window.title:SetText(view.title)
    window.position:SetText(view.position)
    window.prev:SetEnabled(view.canBrowse)
    window.next:SetEnabled(view.canBrowse)

    local sections = {}
    for _, line in ipairs(view.lines) do
        local heading = line.label and line.label ~= "" and ("|cffffd100" .. line.label .. "|r\n") or ""
        sections[#sections + 1] = heading .. line.text
    end
    window.body:SetText(table.concat(sections, "\n\n"))
    local contentHeight = math.ceil(window.title:GetStringHeight() + 12 + window.body:GetStringHeight() + 4)
    window.child:SetHeight(math.max(contentHeight, bodyHeight))
    window.scroll:SetVerticalScroll(math.min(previousOffset, math.max(0, contentHeight - bodyHeight)))
end

function ns.HideWindow()
    if window then
        window.lastKey = nil
        window:Hide()
    end
end
