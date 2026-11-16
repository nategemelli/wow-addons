local addonName, ns = ...
local gold, light, muted = { 1, 0.82, 0 }, { 0.92, 0.87, 0.76 }, { 0.68, 0.64, 0.56 }

local function Text(parent, size, color)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetFont(STANDARD_TEXT_FONT, size)
    text:SetTextColor(unpack(color or light))
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local function Outline(control, inset)
    inset = inset or 0
    local border = CreateFrame("Frame", nil, control)
    border:SetPoint("TOPLEFT", inset, -inset)
    border:SetPoint("BOTTOMRIGHT", -inset, inset)
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

local function Button(parent, label, width, fn)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 26)
    button:SetText(label)
    button:SetScript("OnClick", fn)
    Outline(button)
    return button
end

local function Window(name, width, height, db, positionKey, rightInset)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    local p = type(db[positionKey]) == "table" and db[positionKey] or {}
    local anchors = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
        TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
    frame:SetPoint(anchors[p.point] and p.point or "RIGHT", UIParent,
        anchors[p.relativePoint] and p.relativePoint or "RIGHT", ns.Number(p.x) or -30, ns.Number(p.y) or 0)
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", 12, -8)
    -- Keep the drag region clear of the real button hitboxes.
    drag:SetPoint("TOPRIGHT", -rightInset, -8)
    drag:SetHeight(30)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint(1)
        db[positionKey] = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)
    frame:Hide()
    return frame, drag
end

local function Progress(parent, width, x, y)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetPoint("TOPLEFT", x, y)
    bar:SetSize(width, 20)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:EnableMouse(false)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0.06, 0.05, 0.035, 1)
    local label = Text(bar, 11, light)
    label:SetPoint("CENTER")
    label:SetWidth(width - 10)
    label:SetJustifyH("CENTER")
    return { bar = bar, label = label }
end

local function RenderProgress(progress, auction)
    local phase = auction.phase or "idle"
    local fraction = ns.Number(auction.progress)
    local label, detail = "No scan running", ""
    local bar = progress.bar
    bar:SetStatusBarColor(0.77, 0.62, 0.22)
    bar:SetValue(0)
    if phase == "browsing" then
        label = string.format("%d item groups read", auction.processed or 0)
        detail = string.format("Scanning through level %d. Prices appear as results arrive.", auction.maxLevel)
    elseif phase == "processing" and fraction then
        fraction = math.max(0, math.min(1, fraction))
        -- Reserve 100% for a successful cache commit, even if rounding
        -- would otherwise make the final processing chunk look finished.
        bar:SetValue(fraction)
        label = string.format("%d%% complete", math.min(99, math.floor(fraction * 100)))
        detail = string.format("%d / %d listings read", auction.processed or 0, auction.total or 0)
    elseif phase == "complete" then
        bar:SetValue(1)
        bar:SetStatusBarColor(0.30, 0.65, 0.38)
        label = "100% complete"
        if auction.mode == "browse" then
            detail = string.format("%d item groups read through level %d", auction.processed or 0, auction.maxLevel)
        else
            detail = string.format("%d listings processed - prices saved", auction.total or 0)
        end
    elseif phase == "queued" or auction.autoPending then
        label = "Waiting to start"
        detail = "The scan starts after the auction house is ready."
    elseif phase == "waiting" or auction.busy then
        label = "Waiting for auction house..."
        detail = auction.mode == "browse" and "Item group counts appear as results arrive."
            or "Percent complete is available once the listing count is known."
    elseif phase == "cooldown" then
        label, detail = "Scan on cooldown", "Saved prices remain available."
    elseif phase == "cancelled" then
        label, detail = "Scan cancelled", "Saved prices remain available."
    elseif phase == "error" then
        label, detail = "Scan not completed", "Saved prices remain available."
    end
    progress.label:SetText(label)
    if progress.detail then progress.detail:SetText(detail) end
end

function ns.CreateUI(db, callbacks)
    local frame, drag = Window("AuctionPeekPanel", 470, 580, db, "position", 188)
    local header = CreateFrame("Frame", nil, drag, "DialogHeaderTemplate")
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, 6)
    header:SetWidth(220)
    header:EnableMouse(false)
    header.Text:SetText("AUCTIONPEEK")
    local minimize = Button(frame, "Minimize", 82, callbacks.minimize)
    minimize:SetPoint("TOPRIGHT", -96, -14)
    local close = Button(frame, "Close", 70, callbacks.close)
    close:SetPoint("TOPRIGHT", -18, -14)
    local intro = Text(frame, 12, light)
    intro:SetPoint("TOPLEFT", 25, -51)
    intro:SetSize(420, 32)
    intro:SetWordWrap(true)
    intro:SetJustifyV("TOP")
    intro:SetText("Scan Market checks prices up to two levels above your character. Use /apeek scan full for the whole market.")
    local location = Text(frame, 12, gold)
    location:SetPoint("TOPLEFT", 25, -99)
    location:SetWidth(420)
    local status = Text(frame, 11, muted)
    status:SetPoint("TOPLEFT", 25, -120)
    status:SetSize(420, 43)
    status:SetWordWrap(true)
    status:SetJustifyV("TOP")
    local progress = Progress(frame, 420, 25, -177)
    progress.detail = Text(frame, 10, muted)
    progress.detail:SetPoint("TOPLEFT", 25, -204)
    progress.detail:SetWidth(420)
    local scan = Button(frame, "Scan Market", 155, callbacks.scan)
    scan:SetPoint("TOPRIGHT", -25, -237)
    local refresh = Button(frame, "Refresh Item", 155, callbacks.refresh)
    refresh:SetPoint("TOPLEFT", 25, -237)
    local selectedLabel = Text(frame, 11, gold)
    selectedLabel:SetPoint("TOPLEFT", 25, -282)
    selectedLabel:SetText("LAST HOVERED ITEM")
    local selected = Text(frame, 13, light)
    selected:SetPoint("TOPLEFT", 25, -304)
    selected:SetWidth(420)
    local price = Text(frame, 12, light)
    price:SetPoint("TOPLEFT", 25, -331)
    price:SetWidth(420)
    local stackPrice = Text(frame, 12, light)
    stackPrice:SetPoint("TOPLEFT", 25, -351)
    stackPrice:SetWidth(420)
    local age = Text(frame, 10, muted)
    age:SetPoint("TOPLEFT", 25, -373)
    age:SetWidth(420)
    local browsePrice = Text(frame, 12, light)
    browsePrice:SetPoint("TOPLEFT", 25, -394)
    browsePrice:SetWidth(420)
    local browseDetails = Text(frame, 10, muted)
    browseDetails:SetPoint("TOPLEFT", 25, -413)
    browseDetails:SetWidth(420)
    local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", 22, -469)
    Outline(check, 4)
    local checkLabel = Text(check, 12, light)
    checkLabel:SetPoint("LEFT", check, "RIGHT", 5, 0)
    checkLabel:SetText("Show prices in item tooltips")
    check:SetScript("OnClick", function(self) callbacks.tooltip(self:GetChecked() == true) end)
    local auto = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    auto:SetSize(26, 26)
    auto:SetPoint("TOPLEFT", 22, -441)
    Outline(auto, 4)
    local autoLabel = Text(auto, 12, light)
    autoLabel:SetPoint("LEFT", auto, "RIGHT", 5, 0)
    autoLabel:SetText("Scan automatically when auction house opens")
    auto:SetScript("OnClick", function(self) callbacks.autoScan(self:GetChecked() == true) end)
    local hint = Text(frame, 10, muted)
    hint:SetPoint("TOPLEFT", 25, -504)
    hint:SetSize(420, 27)
    hint:SetWordWrap(true)
    hint:SetJustifyV("TOP")
    hint:SetText("Refresh Item checks buyouts for the selected variant. Re-hover the item to see updated prices.")
    local cancel = Button(frame, "Cancel Scan", 119, callbacks.cancel)
    cancel:SetPoint("BOTTOMRIGHT", -25, 17)
    local footer = Text(frame, 10, muted)
    footer:SetPoint("BOTTOMLEFT", 25, 25)
    footer:SetText("/apeek help  |  Drag the header to move")
    local mini, miniDrag = Window("AuctionPeekMiniPanel", 300, 88, db, "miniPosition", 102)
    local miniTitle = Text(miniDrag, 12, gold)
    miniTitle:SetPoint("TOPLEFT", 6, -11)
    miniTitle:SetWidth(174)
    miniTitle:SetText("AUCTIONPEEK")
    local expand = Button(mini, "Expand", 70, callbacks.expand)
    expand:SetPoint("TOPRIGHT", -18, -13)
    local miniProgress = Progress(mini, 264, 18, -49)

    local ui = { frame = frame, miniFrame = mini }
    function ui:Render(state)
        local auction = state.auction or {}
        local fullVisible = state.visible == true and state.minimized ~= true
        -- Queueing an automatic scan only arms this view. Show it once a
        -- request is running, so cooldown/readiness checks never flash a bar.
        local miniVisible = state.visible == true and state.minimized == true and auction.busy == true
        local opening, miniOpening = fullVisible and not frame:IsShown(), miniVisible and not mini:IsShown()
        frame:SetShown(fullVisible)
        mini:SetShown(miniVisible)
        if opening then frame:Raise() end
        if miniOpening then mini:Raise() end
        location:SetText(auction.open and "AUCTION HOUSE OPEN" or "VISIT AN AUCTIONEER TO UPDATE PRICES")
        status:SetText(auction.status or "Open the auction house, then choose Scan Market or Refresh Item.")
        scan:SetEnabled(auction.open == true and not auction.busy and auction.canScan ~= false)
        refresh:SetEnabled(auction.open == true and not auction.busy and state.hasItem and auction.canRefresh ~= false)
        cancel:SetEnabled(auction.busy == true or auction.autoPending == true)
        RenderProgress(progress, auction)
        RenderProgress(miniProgress, auction)
        selected:SetText(state.lastName or "Hover an item to select it for a price refresh.")
        local record, info = state.record, state.info or {}
        local rangeText
        if record and record.min and record.max then
            rangeText = (info.complete and "Min " or "Observed min ") .. ns.FormatMoney(record.min)
                .. "   /   Max " .. ns.FormatMoney(record.max) .. " buyout each"
        elseif info.empty then rangeText = "No buyout listings in this cached result." end
        local rangeAge = info.known and ((info.stale and "Stale cache - " or "Cached ") .. ns.FormatAge(info.age)
            .. (info.complete and " - complete item results" or " - observed listings only")) or ""
        local browse = info.browse
        local groupText = browse and ("Browse minimum (item and suffix)   " .. ns.FormatMoney(browse.price)
            .. (state.isCommodity and " each" or ""))
        local groupAge = browse and ns.FormatBrowseDetails(browse)
        price:SetText(rangeText or groupText or "No cached prices for this item variant.")
        local stackLabel, stackValue = ns.StackQuote(record, info, state.stackCount, state.isFullStack, state.isCommodity)
        stackPrice:SetText(stackLabel and (stackLabel .. "   " .. stackValue) or "")
        age:SetText(rangeText and rangeAge or groupAge or "")
        browsePrice:SetText(rangeText and groupText or "")
        browseDetails:SetText(rangeText and groupAge or "")
        check:SetChecked(state.tooltipEnabled)
        auto:SetChecked(state.autoScan)
    end
    return ui
end
