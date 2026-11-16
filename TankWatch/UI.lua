local addonName, ns = ...

-- Combat values belong to the native widgets. Only the plain metadata supplied
-- by Core is inspected here; percent may be a protected (secret) number.
local colors = {
    danger = { 1.00, 0.30, 0.28 },
    warning = { 1.00, 0.76, 0.26 },
    safe = { 0.28, 0.84, 0.65 },
    cotank = { 0.43, 0.69, 1.00 },
    attention = { 1.00, 0.57, 0.26 },
    unknown = { 0.62, 0.66, 0.73 },
}

local gold = { 1.00, 0.82, 0.00 }
local parchment = { 0.88, 0.83, 0.71 }
local listWidth = 396

local function Text(parent, size, color)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetFont(STANDARD_TEXT_FONT, size)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    text:SetTextColor(color[1], color[2], color[3])
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local function Fill(parent, r, g, b, a)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(r, g, b, a)
    return texture
end

local function Outline(control)
    local border = CreateFrame("Frame", nil, control)
    border:SetAllPoints()
    border:EnableMouse(false)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = border:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(0, 0, 0, 1)
        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT"); edge:SetPoint(side .. "RIGHT"); edge:SetHeight(1)
        else
            edge:SetPoint("TOP" .. side); edge:SetPoint("BOTTOM" .. side); edge:SetWidth(1)
        end
    end
end

local function Button(parent, label, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetText(label)
    button.label = button:GetFontString()
    button:SetScript("OnClick", onClick)
    Outline(button)
    return button
end

local function MakeList(parent, y, height, rowHeight, createRow)
    local inset = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    inset:SetPoint("TOPLEFT", 16, y + 5)
    inset:SetSize(430, height + 10)
    inset:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    inset:SetBackdropColor(0.65, 0.65, 0.65, 1)
    inset:SetBackdropBorderColor(0.55, 0.49, 0.37, 1)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 22, y)
    scroll:SetSize(listWidth, height)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(listWidth, height)
    scroll:SetScrollChild(child)
    local empty = Text(child, 11, colors.unknown)
    empty:SetPoint("TOPLEFT", 10, -12)
    empty:SetWidth(listWidth - 20)
    empty:SetWordWrap(true)
    local list = { scroll = scroll, child = child, rows = {}, empty = empty }

    function list:Render(data, updateRow, emptyText)
        self.child:SetHeight(math.max(height, #data * rowHeight))
        -- Clamp after a roster shrinks so the next encounter is not scrolled
        -- into blank space. This operates only on ordinary layout numbers.
        local maximum = math.max(0, #data * rowHeight - height)
        if self.scroll:GetVerticalScroll() > maximum then
            self.scroll:SetVerticalScroll(maximum)
        end
        self.empty:SetText(emptyText)
        self.empty:SetShown(#data == 0)
        for index, item in ipairs(data) do
            local row = self.rows[index]
            if not row then
                row = createRow(self.child, rowHeight)
                row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
                self.rows[index] = row
            end
            updateRow(row, item)
            row:Show()
        end
        for index = #data + 1, #self.rows do
            self.rows[index]:Hide()
        end
    end
    return list
end

local function BaseRow(parent, height, kind)
    local row = CreateFrame(kind or "Frame", nil, parent)
    row:SetSize(listWidth, height - 2)
    Fill(row, 0.12, 0.10, 0.07, 0.58)
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetPoint("TOPLEFT", 1, -2)
    row.accent:SetPoint("BOTTOMLEFT", 1, 2)
    row.accent:SetWidth(2)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("BOTTOMLEFT", 7, 2)
    row.bar:SetPoint("BOTTOMRIGHT", -6, 2)
    row.bar:SetHeight(5)
    row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar:SetMinMaxValues(0, 100)
    row.bar:EnableMouse(false)
    Fill(row.bar, 0.03, 0.025, 0.02, 0.9)
    row.percentText = Text(row, 12, parchment)
    row.percentText:SetPoint("TOPRIGHT", -7, -5)
    row.percentText:SetWidth(47)
    row.percentText:SetJustifyH("RIGHT")
    return row
end

local function DisplayPercent(row, item, color)
    row.bar:SetStatusBarColor(color[1], color[2], color[3], 0.9)
    row.bar:SetValue(0)
    row.percentText:SetText("--")
    if item.percentDisplayable == true then
        -- Do not clamp, compare, concatenate, tostring, or string.format this
        -- value. Native sinks can display secret values without reading them.
        local barOK = pcall(row.bar.SetValue, row.bar, item.percent)
        local textOK = pcall(row.percentText.SetFormattedText, row.percentText, "%.0f%%", item.percent)
        if not barOK then row.bar:SetValue(0) end
        if not textOK then row.percentText:SetText("?") end
    end
end

local function DisplayName(fontString, item, fallback)
    fontString:SetText(item.name or fallback)
    if item.nameDisplayable == true then
        local ok = pcall(fontString.SetText, fontString, item.nameDisplay)
        if not ok then fontString:SetText(item.name or fallback) end
    end
end

local function EnemyRow(parent, height)
    -- Ordinary buttons keep the threat-sorted list free to update in combat.
    -- TargetEnemy performs the final outside-combat and identity checks.
    local row = BaseRow(parent, height, "Button")
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp")
    row:SetMotionScriptsWhileDisabled(true)
    row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    row:GetHighlightTexture():SetVertexColor(1, 0.82, 0.3, 0.10)
    Outline(row)
    row:SetScript("OnMouseDown", function(self, button)
        self.pressedItem = nil
        if button == "LeftButton" and self.canTarget and self.item then
            self.pressedItem = { unit = self.item.unit, guid = self.item.guid }
        end
    end)
    row:SetScript("OnClick", function(self, button)
        local pressed = self.pressedItem
        self.pressedItem = nil
        if button ~= "LeftButton" or not self.canTarget or not pressed or not self.item then return end
        -- A threat update can reorder rows while the mouse is held down.
        if self.item.unit ~= pressed.unit or self.item.guid ~= pressed.guid then return end
        ns.TargetEnemy(pressed)
    end)
    row:SetScript("OnHide", function(self) self.pressedItem = nil end)
    row:SetScript("OnEnter", function(self)
        if not GameTooltip or not self.item then return end
        local item = self.item
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(item.name or "Enemy")
        GameTooltip:AddLine(item.label or "UNKNOWN", 1, 0.82, 0.4)
        GameTooltip:AddLine("Target: " .. (item.targetName or "Unknown"), 0.8, 0.85, 0.9)
        GameTooltip:AddLine(item.detail or "", 0.8, 0.85, 0.9, true)
        GameTooltip:AddLine(self.targetHint or "Targeting unavailable.", 1, 0.82, 0, true)
        GameTooltip:AddLine("Percent is your progress toward pulling aggro, not your lead over the next player.", 0.6, 0.7, 0.8, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row.marker = row:CreateTexture(nil, "ARTWORK")
    row.marker:SetSize(14, 14)
    row.marker:SetPoint("TOPLEFT", 7, -4)
    row.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    row.name = Text(row, 12, { 0.95, 0.91, 0.82 })
    row.name:SetPoint("TOPLEFT", 25, -4)
    row.name:SetWidth(164)
    row.label = Text(row, 11, colors.unknown)
    row.label:SetPoint("TOPLEFT", 194, -5)
    row.label:SetWidth(140)
    row.label:SetJustifyH("RIGHT")
    row.target = Text(row, 10, parchment)
    row.target:SetPoint("TOPLEFT", 8, -19)
    row.target:SetWidth(166)
    row.detail = Text(row, 10, { 0.65, 0.61, 0.53 })
    row.detail:SetPoint("TOPLEFT", 181, -19)
    row.detail:SetWidth(208)
    row.detail:SetJustifyH("RIGHT")
    return row
end

local function UpdateEnemy(row, item, targetingLocked, demo)
    row.item = item
    row.canTarget = not demo and not targetingLocked and ns.Text(item.unit) ~= nil and ns.Text(item.guid) ~= nil
    if not row.canTarget then row.pressedItem = nil end
    row:SetEnabled(row.canTarget)
    local action
    if demo then action = "Sample only"; row.targetHint = "Sample rows cannot target real enemies."
    elseif targetingLocked then action = "Combat locked"; row.targetHint = "Click-to-target is available outside combat. Use normal game targeting during combat."
    elseif row.canTarget then action = "Click to target"; row.targetHint = "Left-click to target this enemy. Does not attack or taunt."
    else action = "Unavailable"; row.targetHint = "Targeting unavailable: this enemy has no readable identity." end
    local color = colors[item.state] or colors.unknown
    row.accent:SetColorTexture(color[1], color[2], color[3], 1)
    row.label:SetTextColor(color[1], color[2], color[3])
    DisplayName(row.name, item, "Enemy")
    row.label:SetText(item.label or "UNKNOWN")
    row.target:SetText("Target: " .. (item.targetName or "Unknown"))
    if item.targetDisplayable == true then
        local ok = pcall(row.target.SetFormattedText, row.target, "Target: %s", item.targetDisplay)
        if not ok then row.target:SetText("Target: " .. (item.targetName or "Unknown")) end
    end
    row.detail:SetText(action)
    row.detail:SetTextColor(unpack(row.canTarget and gold or colors.unknown))
    if item.marker then
        SetRaidTargetIconTexture(row.marker, item.marker)
        row.marker:Show()
    else
        row.marker:Hide()
    end
    DisplayPercent(row, item, color)
end

local function MemberRow(parent, height)
    local row = BaseRow(parent, height)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not GameTooltip or not self.item then return end
        local item = self.item
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(item.name or "Group member")
        GameTooltip:AddLine(item.role or "", 0.8, 0.85, 0.9)
        GameTooltip:AddLine(item.statusLabel or "Unknown", 0.8, 0.85, 0.9, true)
        GameTooltip:AddLine("Percent is this member's progress toward pulling aggro on your selected target.", 0.6, 0.7, 0.8, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row.name = Text(row, 12, parchment)
    row.name:SetPoint("TOPLEFT", 8, -3)
    row.name:SetWidth(159)
    row.role = Text(row, 10, colors.unknown)
    row.role:SetPoint("TOPLEFT", 174, -4)
    row.role:SetWidth(58)
    row.status = Text(row, 10, colors.unknown)
    row.status:SetPoint("TOPLEFT", 237, -4)
    row.status:SetWidth(97)
    row.status:SetJustifyH("RIGHT")
    return row
end

local function UpdateMember(row, item)
    row.item = item
    local color = item.isPlayer and colors.safe or colors.unknown
    row.accent:SetColorTexture(color[1], color[2], color[3], 1)
    DisplayName(row.name, item, "Group member")
    row.name:SetTextColor(color[1], color[2], color[3])
    row.role:SetText(item.role or "")
    row.status:SetText(item.statusLabel or "Unknown")
    DisplayPercent(row, item, color)
end

function ns.CreateUI(db)
    local frame = CreateFrame("Frame", "TankWatchPanel", UIParent, "BackdropTemplate")
    frame:SetSize(462, 662)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetBackdropColor(1, 1, 1, 1)
    frame:SetBackdropBorderColor(1, 1, 1, 1)
    local position = db.position or {}
    frame:SetPoint(position.point or "CENTER", UIParent, position.relativePoint or "CENTER", position.x or 0, position.y or 0)

    local titlebar = CreateFrame("Frame", nil, frame)
    titlebar:SetPoint("TOPLEFT", 12, -6)
    titlebar:SetPoint("TOPRIGHT", -12, -6)
    titlebar:SetHeight(61)
    local plaque = CreateFrame("Frame", nil, titlebar, "DialogHeaderTemplate")
    plaque:ClearAllPoints()
    plaque:SetPoint("TOP", frame, "TOP", 0, 6)
    plaque:SetWidth(270)
    titlebar:EnableMouse(true)
    titlebar:RegisterForDrag("LeftButton")
    titlebar:SetScript("OnDragStart", function()
        if not db.locked then frame:StartMoving() end
    end)
    titlebar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint(1)
        db.position = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)
    local title = plaque.Text
    title:SetFont(STANDARD_TEXT_FONT, 14)
    title:SetText("TANKWATCH")
    local test = Button(titlebar, "Test", 64, function() ns.ToggleDemo() end)
    test:SetPoint("TOP", -89, -31)
    local sound = Button(titlebar, "Sound", 92, function() ns.ToggleSound() end)
    sound:SetPoint("TOP", -5, -31)
    local lock = Button(titlebar, "Lock", 72, function() ns.ToggleLock() end)
    lock:SetPoint("TOP", 83, -31)

    local headline = Text(frame, 13, parchment)
    headline:SetPoint("TOPLEFT", 24, -78)
    headline:SetWidth(414)
    local summary = Text(frame, 10, { 0.65, 0.61, 0.53 })
    summary:SetPoint("TOPLEFT", 24, -99)
    summary:SetWidth(414)
    local enemyTitle = Text(frame, 11, gold)
    enemyTitle:SetPoint("TOPLEFT", 24, -123)
    enemyTitle:SetText("ENEMIES IN COMBAT")
    local enemyPercent = Text(frame, 10, parchment)
    enemyPercent:SetPoint("TOPRIGHT", -44, -124)
    enemyPercent:SetText("Your threat %")
    local enemies = MakeList(frame, -142, 240, 40, EnemyRow)

    local groupTitle = Text(frame, 11, gold)
    groupTitle:SetPoint("TOPLEFT", 24, -400)
    groupTitle:SetWidth(414)
    local function Column(label, x, width, align)
        local text = Text(frame, 10, parchment)
        text:SetPoint("TOPLEFT", x, -422)
        text:SetWidth(width)
        text:SetJustifyH(align or "LEFT")
        text:SetText(label)
    end
    Column("Member", 30, 159)
    Column("Role", 196, 58)
    Column("Threat state", 259, 97, "RIGHT")
    Column("Aggro %", 361, 50, "RIGHT")
    local members = MakeList(frame, -441, 140, 28, MemberRow)

    local legendItems = {
        { "Off you", colors.danger, 0, 55 },
        { "At risk", colors.warning, 71, 48 },
        { "Held", colors.safe, 135, 38 },
        { "Other tank", colors.cotank, 189, 70 },
        { "Check", colors.attention, 275, 43 },
        { "Unknown", colors.unknown, 334, 65 },
    }
    for _, item in ipairs(legendItems) do
        local text = Text(frame, 10, item[2])
        text:SetPoint("TOPLEFT", 24 + item[3], -596)
        text:SetWidth(item[4])
        text:SetText(item[1])
    end
    local hint = Text(frame, 10, { 0.65, 0.61, 0.53 })
    hint:SetPoint("TOPLEFT", 24, -616)
    hint:SetWidth(414)
    hint:SetText("Left-click enemies outside combat; targeting is locked in combat.")
    local footer = Text(frame, 10, { 0.56, 0.52, 0.44 })
    footer:SetPoint("BOTTOMLEFT", 24, 17)
    footer:SetWidth(414)
    footer:SetText("/tw off: disable this character  |  /tw help  |  Drag header to move")

    local ui = { frame = frame }
    function ui:Render(snapshot)
        title:SetText(snapshot.demo and "TANKWATCH  /  DEMO" or "TANKWATCH")
        headline:SetText(snapshot.headline or "Watching for combat")
        summary:SetText(snapshot.summary or "")
        groupTitle:SetText("GROUP THREAT  /  " .. (snapshot.targetName or "Select an enemy"))
        test.label:SetText(snapshot.demo and "Live" or "Test")
        sound.label:SetText(db.sound and "Sound on" or "Muted")
        lock.label:SetText(db.locked and "Unlock" or "Lock")
        enemies:Render(snapshot.enemies or {}, function(row, item)
            UpdateEnemy(row, item, snapshot.targetingLocked ~= false, snapshot.demo == true)
        end, "No engaged enemies visible. Turn on enemy nameplates (V) and enter combat.")
        members:Render(snapshot.members or {}, UpdateMember, "Select a hostile target to inspect your group's threat against it.")
    end
    function ui:SetVisible(visible)
        frame:SetShown(visible)
    end
    function ui:SetLocked(locked)
        db.locked = locked
        if locked then frame:StopMovingOrSizing() end
        lock.label:SetText(locked and "Unlock" or "Lock")
    end
    return ui
end
