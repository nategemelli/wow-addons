local addonName, ns = ...

local scanner, ui, db, lastLink, lastName
local lastCount, lastFullStack, lastCommodity
local visible, initialized = false, false
local tooltipMode = "not initialized"

function ns.Now()
    local clock = GetServerTime or time
    if type(clock) == "function" then
        local ok, value = pcall(clock)
        if ok and ns.Number(value) then return value end
    end
    return 0
end

local function Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffd100AuctionPeek:|r " .. message) end
end

local function Lookup(link)
    local key = ns.ItemIdentity(link)
    if not key or not scanner then return nil, { known = false } end
    return ns.Lookup(db, scanner:GetScope(), key, ns.Now())
end

local function Render()
    if not ui or not scanner then return end
    local record, info = Lookup(lastLink)
    ui:Render({ visible = visible, minimized = db.minimized, auction = scanner:GetState(), lastName = lastName,
        hasItem = lastLink ~= nil, stackCount = lastCount, isFullStack = lastFullStack, isCommodity = lastCommodity,
        record = record, info = info, tooltipEnabled = db.tooltipEnabled,
        tooltipMode = tooltipMode, autoScan = db.autoScan })
end

local function ScanCompleted()
    local state = scanner:GetState()
    -- Hide only on successful completion, so ordinary renders cannot hide a
    -- panel the user reopens to inspect the saved result.
    if db.minimized and state.phase == "complete" and not state.busy and not state.autoPending then
        visible = false
    end
    Render()
end

local function RememberItem(link, count, isFullStack, isCommodity)
    local _, itemID = ns.ItemIdentity(link)
    if not itemID then return end
    isFullStack, isCommodity = isFullStack == true, isCommodity == true
    if link == lastLink and count == lastCount and isFullStack == lastFullStack and isCommodity == lastCommodity then return end
    if link ~= lastLink then
        local name = link:match("%[(.-)%]")
        if not name then
            local getter = C_Item and C_Item.GetItemInfo or GetItemInfo
            if type(getter) == "function" then
                local ok, value = pcall(getter, link)
                if ok then name = ns.Text(value) end
            end
        end
        lastName = (name or ("Item " .. itemID)):gsub("|", "||")
        lastLink = link
    end
    lastCount, lastFullStack, lastCommodity = count, isFullStack, isCommodity
    Render()
end

function ns.ShowPanel()
    if not db then return end
    visible = true
    db.minimized = false
    Render()
end

function ns.MinimizePanel()
    if not db then return end
    visible = true
    db.minimized = true
    Render()
end

function ns.HidePanel()
    visible = false
    Render()
end

function ns.StartScan(full)
    if not scanner then return end
    visible = true
    db.minimized = false
    local ok, reason = scanner:StartScan(full == true)
    if not ok and reason then Print(reason) end
    Render()
end

function ns.RefreshItem()
    if not scanner then return end
    visible = true
    db.minimized = false
    if not lastLink then Print("Hover an item first, then choose Refresh Item at an auctioneer."); Render(); return end
    local ok, reason = scanner:RefreshItem(lastLink)
    if not ok and reason then Print(reason) end
    Render()
end

local function Cancel()
    if scanner then scanner:Cancel(); Render() end
end

local function SetTooltip(enabled)
    db.tooltipEnabled = enabled == true
    Render()
end

function ns.SetAutoScan(enabled)
    if not scanner then return end
    scanner:SetAutoScan(enabled == true)
    Render()
end

local function Command(message)
    local command, argument = (message or ""):lower():match("^%s*(%S*)%s*(%S*)")
    if command == "scan" then
        if argument == "" or argument == "full" then ns.StartScan(argument == "full")
        else Print("Use /apeek scan or /apeek scan full.") end
    elseif command == "refresh" then ns.RefreshItem()
    elseif command == "stop" or command == "cancel" then Cancel()
    elseif command == "hide" then ns.HidePanel()
    elseif command == "minimize" or command == "min" then ns.MinimizePanel()
    elseif command == "auto" then
        if argument == "on" then ns.SetAutoScan(true)
        elseif argument == "off" then ns.SetAutoScan(false)
        elseif argument == "" then ns.SetAutoScan(not db.autoScan)
        else Print("Use /apeek auto on or /apeek auto off."); return end
        Print(db.autoScan and "Automatic scanning enabled for your next auction-house visit."
            or "Automatic scanning disabled. An active scan can be stopped with Cancel Scan.")
    elseif command == "on" then SetTooltip(true); Print("Price tooltips enabled. Re-hover an item to update its tooltip.")
    elseif command == "off" then SetTooltip(false); Print("Price tooltips disabled.")
    elseif command == "diag" then
        local version, build, _, interface = GetBuildInfo()
        local state = scanner:GetState()
        Print(string.format("Client %s (%s), interface %s; scanner: %s; tooltip: %s; scope: %s",
            tostring(version), tostring(build), tostring(interface), tostring(state.mode), tooltipMode, tostring(scanner:GetScope())))
        Print(state.status or "Ready.")
        Print("Tooltip failures: " .. tostring(ns.tooltipFailures or 0))
    elseif command == "help" then
        Print("/apeek scan checks prices through your level + 2. /apeek scan full requests every listing. /apeek refresh checks buyouts for the last hovered item. /apeek stop cancels.")
        Print("/apeek opens the scanner. /apeek minimize or hide changes the view. /apeek auto on or off toggles automatic scans. /apeek on or off toggles tooltip prices.")
    else ns.ShowPanel() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= addonName or initialized then return end
        initialized = true
        AuctionPeekDB = type(AuctionPeekDB) == "table" and AuctionPeekDB or {}
        db = AuctionPeekDB
        if type(db.scopes) ~= "table" then db.scopes = {} end
        if type(db.tooltipEnabled) ~= "boolean" then db.tooltipEnabled = true end
        if type(db.autoScan) ~= "boolean" then db.autoScan = true end
        if type(db.minimized) ~= "boolean" then db.minimized = false end
        scanner = ns.CreateScanner(db, { changed = Render, completed = ScanCompleted,
            autoQueued = ns.MinimizePanel })
        ui = ns.CreateUI(db, { scan = ns.StartScan, refresh = ns.RefreshItem, cancel = Cancel,
            close = ns.HidePanel, minimize = ns.MinimizePanel, expand = ns.ShowPanel,
            tooltip = SetTooltip, autoScan = ns.SetAutoScan })
        local hooked, mode = ns.InstallTooltipHooks({ lookup = Lookup, hovered = RememberItem,
            enabled = function() return db.tooltipEnabled end })
        tooltipMode = mode or (hooked and "active" or "unavailable")
        for _, name in ipairs(scanner.events or {}) do
            pcall(events.RegisterEvent, events, name)
        end
        SLASH_AUCTIONPEEK1, SLASH_AUCTIONPEEK2 = "/apeek", "/auctionpeek"
        SlashCmdList.AUCTIONPEEK = Command
        Render()
    elseif scanner then
        scanner:OnEvent(event, ...)
    end
end)
events:SetScript("OnUpdate", function(_, elapsed)
    if scanner then scanner:Tick(elapsed) end
end)
