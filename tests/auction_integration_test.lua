-- Actual Core/UI with a deterministic scanner stub. Network pagination and
-- native tooltip processing have their own scanner/tooltip test suites.
local objects, frames, methods = {}, {}, {}
local function object(kind, name, parent)
    local item = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, events = {},
        shown = true, enabled = true, points = {} }, { __index = methods })
    objects[#objects + 1] = item
    if name then _G[name] = item end
    return item
end
local function noop() end
for _, key in ipairs({ "SetFont", "SetTextColor", "SetShadowColor", "SetShadowOffset", "SetJustifyH",
    "SetJustifyV", "SetWordWrap", "SetAllPoints", "SetColorTexture", "SetFrameStrata",
    "SetClampedToScreen", "SetMovable", "SetBackdrop", "RegisterForDrag", "SetStatusBarTexture",
    "SetStatusBarColor" }) do methods[key] = noop end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:SetPoint(...) self.point = { ... }; self.points[#self.points + 1] = self.point end
function methods:GetPoint() return unpack(self.point or { "CENTER", UIParent, "CENTER", 0, 0 }) end
function methods:ClearAllPoints() self.point, self.points = nil, {} end
function methods:EnableMouse(enabled) self.mouseEnabled = enabled end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:SetText(text) self.text = text end
function methods:SetShown(shown) self.shown = shown end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:Raise() self.raises = (self.raises or 0) + 1 end
function methods:SetEnabled(enabled) self.enabled = enabled end
function methods:SetChecked(checked) self.checked = checked end
function methods:GetChecked() return self.checked end
function methods:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
function methods:SetValue(value) self.value = value end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:CreateTexture() return object("Texture", nil, self) end
function methods:CreateFontString() return object("FontString", nil, self) end
CreateFrame = function(kind, name, parent, template)
    local frame = object(kind, name, parent)
    frame.template = template
    if template == "DialogHeaderTemplate" then frame.Text = object("FontString", nil, frame) end
    frames[#frames + 1] = frame
    return frame
end
UIParent = object("Frame", "UIParent")
STANDARD_TEXT_FONT = "mock-font"
GetBuildInfo = function() return "1.60.1", "70888", "", 16001 end
GetServerTime = function() return 2000 end
C_Item = { GetItemInfo = function() return "Test item" end }

local passed = 0
local function test(name, fn)
    local ok, message = pcall(fn)
    if not ok then error("FAIL: " .. name .. ": " .. tostring(message)) end
    passed = passed + 1
end
local function eq(actual, expected)
    if actual ~= expected then error("expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end
local ns, core, scanner, scannerCallbacks, tooltipCallbacks, captured, ui
local scans, refreshes, cancels, ticks, received, lastRefresh, priceRecord, priceInfo, autoSettings
local function boot(saved)
    objects, frames = {}, {}
    scans, refreshes, cancels, ticks, received = 0, 0, 0, 0, {}
    lastRefresh, priceRecord, priceInfo = nil, nil, { known = false }
    autoSettings = {}
    AuctionPeekDB, SlashCmdList = saved, {}
    DEFAULT_CHAT_FRAME = { messages = {}, AddMessage = function(self, message) self.messages[#self.messages + 1] = message end }
    ns = {}
    assert(loadfile(TEST_ROOT .. "/AuctionPeek/Model.lua"))("AuctionPeek", ns)
    ns.Lookup = function(db, scope, key, now)
        eq(db, AuctionPeekDB); eq(scope, "test:realm:faction"); eq(now, 2000)
        return priceRecord, priceInfo
    end
    ns.CreateScanner = function(db, callbacks)
        eq(db, AuctionPeekDB); scannerCallbacks = callbacks
        scanner = { events = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE" },
            state = { open = false, busy = false, autoPending = false, phase = "idle", mode = "modern", status = "Visit an auctioneer" } }
        function scanner:GetScope() return "test:realm:faction" end
        function scanner:GetState() return self.state end
        function scanner:StartScan(full)
            if not self.state.open or self.state.busy then return false, "Auction house unavailable or busy" end
            self.fullRequested = full
            scans = scans + 1; self.state.busy = true; self.state.autoPending = false
            self.state.phase, self.state.progress = "waiting", nil
            callbacks.changed(); return true
        end
        function scanner:RefreshItem(link)
            if not self.state.open or self.state.busy then return false, "Auction house unavailable or busy" end
            refreshes = refreshes + 1; lastRefresh = link; self.state.busy = true; self.state.autoPending = false
            self.state.phase, self.state.progress = "waiting", nil
            callbacks.changed(); return true
        end
        function scanner:Cancel()
            cancels = cancels + 1; self.state.busy, self.state.autoPending = false, false
            self.state.phase, self.state.progress = "cancelled", nil
            callbacks.changed()
        end
        function scanner:SetAutoScan(enabled)
            autoSettings[#autoSettings + 1] = enabled
            db.autoScan = enabled == true
            if not db.autoScan then self.state.autoPending = false end
            callbacks.changed()
        end
        function scanner:OnEvent(event, ...)
            received[#received + 1] = { event, ... }
            if event == "AUCTION_HOUSE_SHOW" then
                local opening = not self.state.open
                self.state.open = true
                if opening and db.autoScan ~= false then
                    self.state.autoPending, self.state.phase = true, "queued"
                    callbacks.changed()
                    if callbacks.autoQueued then callbacks.autoQueued() end
                end
            elseif event == "AUCTION_HOUSE_CLOSED" then
                self.state.open, self.state.busy, self.state.autoPending = false, false, false
                self.state.phase, self.state.progress = "cancelled", nil
            end
            callbacks.changed()
        end
        function scanner:Tick(elapsed) ticks = ticks + elapsed end
        return scanner
    end
    ns.InstallTooltipHooks = function(callbacks) tooltipCallbacks = callbacks; return true, "modern" end
    assert(loadfile(TEST_ROOT .. "/AuctionPeek/UI.lua"))("AuctionPeek", ns)
    local create = ns.CreateUI
    ns.CreateUI = function(db, callbacks)
        ui = create(db, callbacks)
        local render = ui.Render
        ui.Render = function(self, state) captured = state; return render(self, state) end
        return ui
    end
    assert(loadfile(TEST_ROOT .. "/AuctionPeek/Core.lua"))("AuctionPeek", ns)
    core = frames[#frames]
    core.scripts.OnEvent(core, "ADDON_LOADED", "AuctionPeek")
end
local function event(name, ...) core.scripts.OnEvent(core, name, ...) end
local function command(text) SlashCmdList.AUCTIONPEEK(text) end
local function button(text)
    for _, frame in ipairs(frames) do if frame.kind == "Button" and frame.text == text then return frame end end
end
local function click(text)
    local control = assert(button(text), "button missing: " .. text)
    assert(control.enabled, "button disabled: " .. text)
    control.scripts.OnClick(control)
end
local function hasText(fragment)
    for _, item in ipairs(objects) do if type(item.text) == "string" and item.text:find(fragment, 1, true) then return true end end
    return false
end
local function checkbox(label)
    for _, item in ipairs(objects) do
        if item.kind == "FontString" and item.text == label and item.parent and item.parent.kind == "CheckButton" then
            return item.parent
        end
    end
end
local function progressBar(parent)
    parent = parent or ui.frame
    for _, frame in ipairs(frames) do if frame.kind == "StatusBar" and frame.parent == parent then return frame end end
    error("scan progress bar is missing")
end
local function dragHandle(parent)
    for _, frame in ipairs(frames) do if frame.parent == parent and frame.scripts.OnDragStart then return frame end end
    error("panel drag handle is missing")
end
local function childText(parent, fragment)
    for _, item in ipairs(objects) do
        local owner = item.parent
        while owner do
            if owner == parent and type(item.text) == "string" and item.text:find(fragment, 1, true) then return true end
            owner = owner.parent
        end
    end
    return false
end

test("addon initializes hidden with tooltip hooks and no auction requests", function()
    boot({ autoScan = false })
    eq(ui.frame.shown, false); eq(scans, 0); eq(refreshes, 0)
    eq(AuctionPeekDB.tooltipEnabled, true); assert(type(AuctionPeekDB.scopes) == "table")
    eq(SLASH_AUCTIONPEEK1, "/apeek"); eq(SLASH_AUCTIONPEEK2, "/auctionpeek")
    for _, name in ipairs(scanner.events) do eq(core.events[name], true) end
    local count = #frames; event("ADDON_LOADED", "AuctionPeek"); eq(#frames, count)
end)

test("hover remembers exact item link without opening panel or querying", function()
    tooltipCallbacks.hovered("item:123:0:0:0:0:0:7")
    eq(captured.hasItem, true); eq(captured.lastName, "Test item")
    eq(ui.frame.shown, false); eq(scans, 0); eq(refreshes, 0)
    tooltipCallbacks.lookup("item:123:0:0:0:0:0:7")
    eq(scans, 0); eq(refreshes, 0)
end)

test("opening auction house routes state without opening scanner or querying", function()
    event("AUCTION_HOUSE_SHOW")
    eq(scanner.state.open, true); eq(ui.frame.shown, false)
    eq(scans, 0); eq(refreshes, 0)
    eq(button("Scan Market").enabled, true); eq(button("Refresh Item").enabled, true)
end)

test("panel opens and closes through native controls without querying", function()
    command(""); eq(ui.frame.shown, true); eq(ui.frame.raises, 1)
    click("Close"); eq(ui.frame.shown, false); eq(scans, 0); eq(refreshes, 0)
    command(""); eq(ui.frame.shown, true); eq(ui.frame.raises, 2)
end)

test("Scan Market starts one request and disables competing actions", function()
    click("Scan Market")
    eq(scans, 1); eq(scanner.state.busy, true)
    eq(button("Scan Market").enabled, false); eq(button("Refresh Item").enabled, false)
    eq(button("Cancel Scan").enabled, true)
    core.scripts.OnUpdate(core, 0.5); eq(ticks, 0.5); eq(scans, 1)
end)

test("cancel delegates cancellation and re-enables actions", function()
    click("Cancel Scan")
    eq(cancels, 1); eq(scanner.state.busy, false)
    eq(button("Scan Market").enabled, true); eq(button("Cancel Scan").enabled, false)
end)

test("Refresh Item sends the remembered full variant only on explicit action", function()
    click("Refresh Item"); eq(refreshes, 1); eq(lastRefresh, "item:123:0:0:0:0:0:7")
    tooltipCallbacks.hovered("item:123:0:0:0:0:0:8"); eq(refreshes, 1)
    command("stop"); command("refresh")
    eq(refreshes, 2); eq(lastRefresh, "item:123:0:0:0:0:0:8")
end)

test("auction close disables controls and forwards completion lifecycle", function()
    event("REPLICATE_ITEM_LIST_UPDATE", 42)
    eq(received[#received][1], "REPLICATE_ITEM_LIST_UPDATE"); eq(received[#received][2], 42)
    event("AUCTION_HOUSE_CLOSED")
    eq(button("Scan Market").enabled, false); eq(button("Refresh Item").enabled, false)
    eq(button("Cancel Scan").enabled, false)
    command("scan"); eq(scans, 1)
    assert(#DEFAULT_CHAT_FRAME.messages > 0)
end)

test("tooltip toggle persists and does not cause an auction request", function()
    command("off"); eq(tooltipCallbacks.enabled(), false); eq(AuctionPeekDB.tooltipEnabled, false)
    local check = checkbox("Show prices in item tooltips")
    assert(check); check:SetChecked(true); check.scripts.OnClick(check)
    eq(tooltipCallbacks.enabled(), true); eq(AuctionPeekDB.tooltipEnabled, true)
    eq(scans, 1); eq(refreshes, 2)
end)

test("completed cache appears in panel without refresh allocation", function()
    priceRecord = { min = 100, max = 800, listingCount = 2, units = 10 }
    priceInfo = { known = true, complete = false, age = 300, stale = true }
    local count = #objects; scannerCallbacks.completed()
    eq(#objects, count); assert(hasText("Observed min")); assert(hasText("Stale cache"))
    assert(hasText("observed listings only"))
    eq(scans, 1); eq(refreshes, 2)
end)

test("outline frames cannot intercept input from their parent controls", function()
    local outlines, controls = 0, 0
    for _, frame in ipairs(frames) do
        if frame.kind == "Button" or frame.kind == "CheckButton" then controls = controls + 1 end
        if frame.kind == "Frame" and frame.parent and (frame.parent.kind == "Button" or frame.parent.kind == "CheckButton") then
            eq(frame.mouseEnabled, false); eq(next(frame.scripts), nil); outlines = outlines + 1
        end
    end
    assert(controls > 0); eq(outlines, controls)
end)

test("draggable headers stay clear of minimize close and expand controls", function()
    local drag = dragHandle(ui.frame)
    for _, label in ipairs({ "Close", "Minimize", "Expand" }) do
        local control = assert(button(label))
        local parent = control.parent
        drag = dragHandle(parent)
        local right, left, top, height = parent.width + drag.points[2][2], parent.width + control.point[2] - control.width,
            -drag.points[1][3], drag.height
        local controlTop = -control.point[3]
        assert(right <= left or top + height <= controlTop or controlTop + control.height <= top, "drag area overlaps " .. label)
    end
end)

test("dragging stores position and diagnostics remain local", function()
    local drag = dragHandle(ui.frame)
    ui.frame:SetPoint("TOP", UIParent, "TOP", 32, -64)
    drag.scripts.OnDragStart(); eq(ui.frame.moving, true)
    drag.scripts.OnDragStop(); eq(ui.frame.moving, false)
    eq(AuctionPeekDB.position.x, 32); eq(AuctionPeekDB.position.y, -64)
    command("diag"); command("help")
    eq(scans, 1); eq(refreshes, 2)
end)

test("refresh without a hovered item is explained and sends nothing", function()
    boot({ tooltipEnabled = false, autoScan = false, scopes = {} })
    event("AUCTION_HOUSE_SHOW")
    eq(button("Refresh Item").enabled, false)
    command("refresh"); eq(refreshes, 0)
    assert(DEFAULT_CHAT_FRAME.messages[1]:find("Hover an item first", 1, true))
    eq(tooltipCallbacks.enabled(), false)
end)

test("invalid saved state safely falls back to defaults", function()
    boot("invalid")
    eq(type(AuctionPeekDB), "table"); eq(AuctionPeekDB.tooltipEnabled, true)
    eq(scans, 0); eq(refreshes, 0); eq(ui.frame.shown, false)
end)

test("automatic scanning defaults on for new and existing installations but preserves opt-out", function()
    boot(nil); eq(AuctionPeekDB.autoScan, true); eq(captured.autoScan, true)
    eq(scans, 0); eq(refreshes, 0); eq(ui.frame.shown, false)
    boot({ tooltipEnabled = false, autoScan = "invalid", scopes = { retained = {} } })
    eq(AuctionPeekDB.autoScan, true); eq(AuctionPeekDB.tooltipEnabled, false)
    assert(AuctionPeekDB.scopes.retained)
    boot({ autoScan = false }); eq(AuctionPeekDB.autoScan, false); eq(captured.autoScan, false)
    event("AUCTION_HOUSE_SHOW"); eq(ui.frame.shown, false); eq(scanner.state.autoPending, false)
end)

test("automatic queue stays hidden and only active work opens progress once per visit", function()
    boot(nil); event("AUCTION_HOUSE_SHOW")
    eq(scanner.state.autoPending, true); eq(ui.frame.shown, false); eq(AuctionPeekMiniPanel.shown, false)
    eq(button("Cancel Scan").enabled, true); eq(scans, 0); eq(refreshes, 0)
    command("hide"); eq(ui.frame.shown, false); eq(AuctionPeekMiniPanel.shown, false)
    event("AUCTION_HOUSE_SHOW"); eq(ui.frame.shown, false); eq(AuctionPeekMiniPanel.shown, false)
    scannerCallbacks.changed(); eq(ui.frame.shown, false); eq(AuctionPeekMiniPanel.shown, false)
    event("AUCTION_HOUSE_CLOSED"); event("AUCTION_HOUSE_SHOW")
    eq(ui.frame.shown, false); eq(AuctionPeekMiniPanel.shown, false); eq(scans, 0); eq(refreshes, 0)
    scanner:StartScan()
    eq(AuctionPeekMiniPanel.shown, true); eq(ui.frame.shown, false); eq(scans, 1)
    event("AUCTION_HOUSE_SHOW"); scannerCallbacks.changed()
    eq(AuctionPeekMiniPanel.raises, 1); eq(scans, 1)
    event("AUCTION_HOUSE_CLOSED")
end)

test("auto-scan checkbox and slash preference persist and delegate without hover queries", function()
    command("")
    local check = assert(checkbox("Scan automatically when auction house opens"))
    eq(check.checked, true)
    check:SetChecked(false); check.scripts.OnClick(check)
    eq(AuctionPeekDB.autoScan, false); eq(autoSettings[#autoSettings], false)
    eq(scanner.state.autoPending, false); eq(button("Cancel Scan").enabled, false)
    command("auto"); eq(AuctionPeekDB.autoScan, true); eq(check.checked, true)
    eq(autoSettings[#autoSettings], true)
    command("auto off"); eq(AuctionPeekDB.autoScan, false); eq(check.checked, false)
    command("auto on"); eq(AuctionPeekDB.autoScan, true); eq(check.checked, true)
    local changes = #autoSettings
    command("auto invalid"); eq(AuctionPeekDB.autoScan, true); eq(#autoSettings, changes)
    tooltipCallbacks.hovered("item:123:0:0:0:0:0:8")
    eq(scans, 1); eq(refreshes, 0)
end)

test("pending auto work can be cancelled from the visible native control", function()
    event("AUCTION_HOUSE_CLOSED"); event("AUCTION_HOUSE_SHOW")
    eq(scanner.state.autoPending, true); eq(scanner.state.busy, false)
    command("")
    click("Cancel Scan")
    eq(scanner.state.autoPending, false); eq(cancels, 1)
    eq(button("Cancel Scan").enabled, false); eq(scans, 1)
end)

test("waiting progress never invents a percentage before a result total exists", function()
    scanner.state.phase, scanner.state.progress = "waiting", nil
    scanner.state.busy, scanner.state.processed, scanner.state.total = true, nil, nil
    scannerCallbacks.changed()
    local bar = progressBar()
    eq(bar.value, bar.minimum)
    assert(hasText("Waiting for auction house"))
    for _, item in ipairs(objects) do
        if type(item.text) == "string" then assert(not item.text:find("%d+%%"), "unknown server progress must not show a percentage") end
    end
end)

test("known processing progress displays measured percent and listing counts", function()
    scanner.state.phase, scanner.state.progress = "processing", 0.25
    scanner.state.processed, scanner.state.total = 150, 600
    scannerCallbacks.changed()
    local bar = progressBar()
    eq((bar.value - bar.minimum) / (bar.maximum - bar.minimum), 0.25)
    assert(hasText("25%")); assert(hasText("150 / 600"))
    eq(button("Cancel Scan").enabled, true)
end)

test("only successful completion fills the progress indicator", function()
    scanner.state.busy, scanner.state.phase, scanner.state.progress = false, "complete", 1
    scanner.state.processed, scanner.state.total = 600, 600
    scannerCallbacks.completed()
    local bar = progressBar()
    eq(bar.value, bar.maximum); assert(hasText("100%"))
    eq(button("Cancel Scan").enabled, false)
    for _, phase in ipairs({ "cancelled", "error", "cooldown" }) do
        scanner.state.phase, scanner.state.progress = phase, nil
        scanner.state.processed, scanner.state.total = nil, nil
        scannerCallbacks.changed()
        eq(bar.value, bar.minimum)
        for _, item in ipairs(objects) do
            if type(item.text) == "string" then assert(not item.text:find("100%%"), phase .. " must not retain completion text") end
        end
    end
end)

test("minimized preference defaults safely and initialization keeps both panels hidden", function()
    boot({ minimized = "invalid" })
    eq(AuctionPeekDB.minimized, false); eq(captured.minimized, false)
    eq(ui.frame.shown, false); eq(AuctionPeekMiniPanel.shown, false)
    eq(scans, 0); eq(refreshes, 0); eq(cancels, 0)
    boot({ minimized = true })
    eq(AuctionPeekDB.minimized, true); eq(captured.minimized, true)
    eq(ui.frame.shown, false); eq(AuctionPeekMiniPanel.shown, false)
end)

test("minimizing queued work preserves the queue and expanding does not start another scan", function()
    boot(nil); event("AUCTION_HOUSE_SHOW")
    eq(scanner.state.autoPending, true); eq(AuctionPeekMiniPanel.shown, false)
    command(""); eq(ui.frame.shown, true)
    click("Minimize")
    eq(ui.frame.shown, false); eq(AuctionPeekMiniPanel.shown, false)
    eq(AuctionPeekDB.minimized, true); eq(captured.minimized, true)
    eq(scanner.state.autoPending, true); eq(scans, 0); eq(cancels, 0)
    assert(childText(AuctionPeekMiniPanel, "Waiting"))
    core.scripts.OnUpdate(core, 0.5); eq(ticks, 0.5)
    command("")
    eq(ui.frame.shown, true); eq(AuctionPeekMiniPanel.shown, false)
    eq(AuctionPeekDB.minimized, false); eq(scanner.state.autoPending, true)
    eq(scans, 0); eq(cancels, 0)
end)

test("minimized active scan keeps ticking and hides after saving its result", function()
    boot({ autoScan = false }); event("AUCTION_HOUSE_SHOW")
    tooltipCallbacks.hovered("item:123:0:0:0:0:0:7"); command("scan")
    eq(scans, 1); eq(scanner.state.busy, true)
    click("Minimize")
    eq(scanner.state.busy, true); eq(cancels, 0)
    core.scripts.OnUpdate(core, 0.75); eq(ticks, 0.75)
    scanner.state.phase, scanner.state.progress = "processing", 0.25
    scanner.state.processed, scanner.state.total = 150, 600
    scannerCallbacks.changed()
    local compactBar = progressBar(AuctionPeekMiniPanel)
    eq(compactBar.value, 0.25); assert(childText(compactBar, "25%"))
    eq(ui.frame.shown, false); eq(AuctionPeekMiniPanel.shown, true)
    priceRecord = { min = 100, max = 800, listingCount = 2, units = 10 }
    priceInfo = { known = true, complete = false, age = 0, stale = false }
    scanner.state.busy, scanner.state.phase, scanner.state.progress = false, "complete", 1
    scanner.state.processed = 600
    scannerCallbacks.completed()
    eq(compactBar.value, 1); assert(childText(compactBar, "100%"))
    eq(ui.frame.shown, false); eq(AuctionPeekMiniPanel.shown, false)
    command(""); assert(childText(ui.frame, "Observed min"))
    eq(scans, 1); eq(refreshes, 0); eq(cancels, 0)
end)

test("compact progress clears stale percentages on waiting and failure states", function()
    boot({ minimized = true }); event("AUCTION_HOUSE_SHOW")
    local compactBar = progressBar(AuctionPeekMiniPanel)
    for _, phase in ipairs({ "queued", "waiting", "cancelled", "error", "cooldown" }) do
        scanner.state.phase, scanner.state.progress = "complete", 1
        scanner.state.autoPending, scanner.state.busy = false, false
        scannerCallbacks.completed(); eq(compactBar.value, 1)
        command("min")
        scanner.state.phase, scanner.state.progress = phase, nil
        scanner.state.autoPending, scanner.state.busy = phase == "queued", phase == "waiting"
        scannerCallbacks.changed()
        eq(compactBar.value, 0); eq(childText(compactBar, "%"), false)
        eq(AuctionPeekMiniPanel.shown, phase == "waiting"); eq(ui.frame.shown, false)
    end
end)

test("automatic reopening respects compact preference and hides do not cancel work", function()
    boot({ minimized = true }); event("AUCTION_HOUSE_SHOW")
    eq(AuctionPeekMiniPanel.shown, false); eq(ui.frame.shown, false)
    command("hide")
    eq(AuctionPeekMiniPanel.shown, false); eq(ui.frame.shown, false)
    eq(AuctionPeekDB.minimized, true); eq(scanner.state.autoPending, true); eq(cancels, 0)
    scannerCallbacks.changed(); event("AUCTION_HOUSE_SHOW")
    eq(AuctionPeekMiniPanel.shown, false); eq(ui.frame.shown, false)
    event("AUCTION_HOUSE_CLOSED"); event("AUCTION_HOUSE_SHOW")
    eq(AuctionPeekMiniPanel.shown, false); eq(ui.frame.shown, false)
    eq(scans, 0); eq(cancels, 0)
end)

test("every automatic visit starts compact even after an expanded prior visit", function()
    boot({ minimized = false }); event("AUCTION_HOUSE_SHOW")
    eq(AuctionPeekMiniPanel.shown, false); eq(ui.frame.shown, false)
    eq(AuctionPeekDB.minimized, true)
    scanner:StartScan(); eq(AuctionPeekMiniPanel.shown, true)
    click("Expand"); eq(ui.frame.shown, true); eq(AuctionPeekDB.minimized, false)
    event("AUCTION_HOUSE_SHOW")
    eq(ui.frame.shown, true); eq(AuctionPeekMiniPanel.shown, false)
    event("AUCTION_HOUSE_CLOSED"); event("AUCTION_HOUSE_SHOW")
    eq(AuctionPeekMiniPanel.shown, false); eq(ui.frame.shown, false)
    scanner:StartScan(); eq(AuctionPeekMiniPanel.shown, true)
    eq(AuctionPeekDB.minimized, true); eq(scans, 2); eq(cancels, 0)
end)

test("successful automatic scan hides compact progress without losing cached prices or reopening", function()
    boot(nil); event("AUCTION_HOUSE_SHOW")
    tooltipCallbacks.hovered("item:123:0:0:0:0:0:7")
    scanner.state.autoPending, scanner.state.busy = false, true
    scanner.state.phase, scanner.state.progress = "processing", 0.5
    scanner.state.processed, scanner.state.total = 150, 300
    scannerCallbacks.changed(); eq(AuctionPeekMiniPanel.shown, true)
    priceRecord = { min = 200, max = 900, listingCount = 2, units = 10 }
    priceInfo = { known = true, complete = false, age = 0, stale = false }
    scanner.state.busy, scanner.state.phase, scanner.state.progress = false, "complete", 1
    scanner.state.processed = 300
    scannerCallbacks.changed(); scannerCallbacks.completed()
    eq(AuctionPeekMiniPanel.shown, false); eq(ui.frame.shown, false)
    eq(cancels, 0)
    local quote, info = tooltipCallbacks.lookup("item:123:0:0:0:0:0:7")
    eq(quote.min, 200); eq(info.known, true)
    tooltipCallbacks.hovered("item:123:0:0:0:0:0:8")
    scannerCallbacks.changed(); event("AUCTION_HOUSE_SHOW")
    eq(AuctionPeekMiniPanel.shown, false); eq(ui.frame.shown, false)
    command(""); eq(ui.frame.shown, true); assert(childText(ui.frame, "Observed min"))
    command("min"); eq(AuctionPeekMiniPanel.shown, false)
    scannerCallbacks.changed(); eq(AuctionPeekMiniPanel.shown, false)
    eq(scans, 0); eq(refreshes, 0); eq(cancels, 0)
end)

test("finishing an automatic scan leaves deliberately expanded controls available", function()
    boot(nil); event("AUCTION_HOUSE_SHOW"); scanner:StartScan(); click("Expand")
    scanner.state.autoPending, scanner.state.busy = false, false
    scanner.state.phase, scanner.state.progress = "complete", 1
    scanner.state.processed, scanner.state.total = 300, 300
    scannerCallbacks.changed(); scannerCallbacks.completed()
    eq(ui.frame.shown, true); eq(AuctionPeekMiniPanel.shown, false)
    assert(childText(ui.frame, "100%")); eq(cancels, 0)
end)

test("slash commands switch views and explicit scan or refresh restores controls", function()
    boot({ autoScan = false })
    command("minimize"); eq(AuctionPeekMiniPanel.shown, false); eq(ui.frame.shown, false)
    command(""); eq(AuctionPeekMiniPanel.shown, false); eq(ui.frame.shown, true)
    command("min"); eq(AuctionPeekMiniPanel.shown, false); eq(ui.frame.shown, false)
    event("AUCTION_HOUSE_SHOW"); command("scan")
    eq(scans, 1); eq(AuctionPeekDB.minimized, false)
    eq(AuctionPeekMiniPanel.shown, false); eq(ui.frame.shown, true)
    command("stop"); command("min")
    tooltipCallbacks.hovered("item:123:0:0:0:0:0:7")
    command("refresh")
    eq(refreshes, 1); eq(AuctionPeekDB.minimized, false)
    eq(AuctionPeekMiniPanel.shown, false); eq(ui.frame.shown, true)
end)

test("compact dragging persists independently from full panel position", function()
    boot({ position = { point = "TOP", relativePoint = "TOP", x = 32, y = -64 } })
    event("AUCTION_HOUSE_SHOW"); scanner:StartScan()
    command("min")
    local mini = AuctionPeekMiniPanel
    local drag = dragHandle(mini)
    mini:SetPoint("BOTTOM", UIParent, "BOTTOM", 50, 80)
    drag.scripts.OnDragStart(); eq(mini.moving, true)
    drag.scripts.OnDragStop(); eq(mini.moving, false)
    eq(AuctionPeekDB.miniPosition.x, 50); eq(AuctionPeekDB.miniPosition.y, 80)
    eq(AuctionPeekDB.position.x, 32); eq(AuctionPeekDB.position.y, -64)
    local saved = AuctionPeekDB
    boot(saved)
    eq(AuctionPeekMiniPanel.point[1], "BOTTOM"); eq(AuctionPeekMiniPanel.point[4], 50)
    eq(AuctionPeekMiniPanel.point[5], 80)
    eq(ui.frame.point[4], 32); eq(ui.frame.point[5], -64)
end)

test("cooldown visits never flash compact progress and full status remains available", function()
    boot(nil); event("AUCTION_HOUSE_SHOW")
    eq(AuctionPeekMiniPanel.shown, false); eq(AuctionPeekMiniPanel.raises, nil)
    core.scripts.OnUpdate(core, 2)
    scanner.state.autoPending, scanner.state.busy = false, false
    scanner.state.phase, scanner.state.status = "cooldown", "Full-scan cooldown: about 10 minute(s)."
    scannerCallbacks.changed(); event("AUCTION_HOUSE_SHOW")
    tooltipCallbacks.hovered("item:123:0:0:0:0:0:7")
    eq(AuctionPeekMiniPanel.shown, false); eq(AuctionPeekMiniPanel.raises, nil)
    eq(ui.frame.shown, false); eq(scans, 0); eq(cancels, 0)
    command(""); eq(ui.frame.shown, true)
    assert(childText(ui.frame, "Full-scan cooldown"))
    scannerCallbacks.changed(); eq(ui.frame.shown, true)
    click("Minimize"); eq(ui.frame.shown, false); eq(AuctionPeekMiniPanel.shown, false)
end)

test("hiding during the queue prevents the bar from reopening when the request starts", function()
    boot(nil); event("AUCTION_HOUSE_SHOW"); command("hide")
    scanner:StartScan()
    eq(scanner.state.busy, true); eq(scans, 1); eq(cancels, 0)
    eq(AuctionPeekMiniPanel.shown, false); eq(ui.frame.shown, false)
    eq(AuctionPeekMiniPanel.raises, nil)
    event("AUCTION_HOUSE_SHOW"); scannerCallbacks.changed()
    eq(AuctionPeekMiniPanel.shown, false)
    command("min"); eq(AuctionPeekMiniPanel.shown, true)
    assert(childText(AuctionPeekMiniPanel, "Waiting for auction house"))
    eq(scans, 1); eq(cancels, 0)
end)

test("stopped or failed work hides compact progress while full details can be opened", function()
    for _, phase in ipairs({ "cancelled", "error" }) do
        boot(nil); event("AUCTION_HOUSE_SHOW"); scanner:StartScan()
        eq(AuctionPeekMiniPanel.shown, true)
        if phase == "cancelled" then command("stop")
        else
            scanner.state.busy, scanner.state.phase = false, "error"
            scanner.state.status = "Auction request timed out."
            scannerCallbacks.changed()
        end
        eq(AuctionPeekMiniPanel.shown, false); eq(ui.frame.shown, false)
        scannerCallbacks.changed(); eq(AuctionPeekMiniPanel.shown, false)
        command(""); eq(ui.frame.shown, true)
        assert(childText(ui.frame, phase == "cancelled" and "Scan cancelled" or "Scan not completed"))
        eq(scans, 1)
    end
end)

test("level scan shows progressive counts and browse prices before completion", function()
    boot(nil); event("AUCTION_HOUSE_SHOW"); scanner:StartScan()
    tooltipCallbacks.hovered("item:123:0:0:0:0:0:7")
    priceInfo = { known = false, browse = { price = 505, maxLevel = 12, age = 300, stale = false } }
    scanner.state.mode, scanner.state.phase = "browse", "browsing"
    scanner.state.processed, scanner.state.maxLevel = 85, 12
    scannerCallbacks.changed()
    local compact = progressBar(AuctionPeekMiniPanel)
    assert(childText(compact, "85 item groups read")); eq(childText(compact, "%"), false)
    click("Expand")
    assert(childText(ui.frame, "85 item groups read")); assert(childText(ui.frame, "Scanning through level 12"))
    assert(childText(ui.frame, "Browse minimum (item and suffix)   5s 05c"))
    assert(childText(ui.frame, "Through level 12")); eq(childText(ui.frame, "No cached prices"), false)
    eq(childText(ui.frame, "Max "), false)
    priceRecord, priceInfo.known = { min = 600, max = 800 }, true
    priceInfo.complete, priceInfo.age = true, 10
    scanner.state.busy, scanner.state.phase, scanner.state.progress = false, "complete", 1
    scannerCallbacks.completed()
    assert(childText(ui.frame, "85 item groups read through level 12"))
    assert(childText(ui.frame, "Browse minimum (item and suffix)")); assert(childText(ui.frame, "Max 8s 00c"))
end)

test("only the explicit full command opts out of the character's level cap", function()
    boot({ autoScan = false }); event("AUCTION_HOUSE_SHOW"); command("scan full")
    eq(scanner.fullRequested, true)
    scanner:Cancel(); command("scan"); eq(scanner.fullRequested, false)
    scanner:Cancel()
    local scanButton = button("Scan Market")
    scanButton.scripts.OnClick(scanButton, "LeftButton"); eq(scanner.fullRequested, false)
end)

test("panel follows the hovered stack even when the item link stays the same", function()
    boot({ autoScan = false }); event("AUCTION_HOUSE_SHOW"); command("")
    local link = "item:123:0:0:0:0:0:7"
    priceRecord = { min = 500, max = 500 }
    priceInfo = { known = true, complete = true, age = 10 }
    tooltipCallbacks.hovered(link, 4, false)
    assert(childText(ui.frame, "20s 00c")); assert(childText(ui.frame, "5s 00c buyout each"))
    tooltipCallbacks.hovered(link, 7, false)
    assert(childText(ui.frame, "35s 00c")); eq(childText(ui.frame, "20s 00c"), false)
    tooltipCallbacks.hovered(link, 20, true)
    local fullLabel, fullValue = ns.StackQuote(priceRecord, priceInfo, 20, true)
    assert(childText(ui.frame, fullLabel .. "   " .. fullValue)); assert(childText(ui.frame, "1g 00s 00c"))
    tooltipCallbacks.hovered(link)
    eq(childText(ui.frame, fullLabel), false); eq(childText(ui.frame, "1g 00s 00c"), false)
    eq(scans, 0); eq(refreshes, 0)
    click("Refresh Item"); eq(lastRefresh, link)
end)

test("browse-only stack estimate in the panel follows confirmed commodity status", function()
    boot({ autoScan = false }); command("")
    local link = "item:123"
    priceInfo = { known = false, browse = { price = 505, maxLevel = 12, age = 0 } }
    tooltipCallbacks.hovered(link, 2, false, true)
    assert(childText(ui.frame, "5s 05c each")); assert(childText(ui.frame, "10s 10c"))
    tooltipCallbacks.hovered(link, 2, false, false)
    assert(childText(ui.frame, "5s 05c")); eq(childText(ui.frame, "5s 05c each"), false)
    eq(childText(ui.frame, "10s 10c"), false)
end)

print("AUCTION INTEGRATION PASS: " .. passed .. " mocked-client cases")
