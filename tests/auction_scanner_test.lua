-- State-machine tests use verified auction API shapes; no server transactions.
local ns = {}
assert(loadfile(TEST_ROOT .. "/AuctionPeek/Model.lua"))("AuctionPeek", ns)
assert(loadfile(TEST_ROOT .. "/AuctionPeek/Scanner.lua"))("AuctionPeek", ns)
local now, ready, full, pageReturnsFull, calls, rows, itemRows, commodities, legacyTotal
local db, scanner, changed, completed, combat, autoQueued
local secretValues = setmetatable({}, { __mode = "k" })
issecretvalue = function(value) return secretValues[value] == true end
local function secret()
    local value = setmetatable({}, { __tostring = function() error("secret inspected") end,
        __mul = function() error("secret arithmetic") end })
    secretValues[value] = true
    return value
end
local function link(id, suffix)
    return "item:" .. id .. ":0:0:0:0:0:" .. (suffix or 0)
end
local function key(id)
    return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end
local function info(row)
    return "Item", 1, row.quantity, 1, false, row.level or 10, row.levelType or "REQ_LEVEL_ABBR", 1, 1,
        row.buyout, 0, nil, nil, nil, nil, 0, row.id, row.loaded ~= false
end
local function Hook(target, name, callback)
    if type(target) == "string" then callback, name, target = name, target, _G end
    local original = target[name]
    target[name] = function(...)
        local result = { original(...) }
        callback(...)
        return unpack(result)
    end
end
local function reset(legacy, automatic)
    now, ready, full, pageReturnsFull, combat = 10000, true, true, false, false
    calls = { replicate = 0, search = 0, pages = 0, legacy = 0, readiness = 0 }
    rows, itemRows, commodities, legacyTotal = {}, {}, {}, nil
    changed, completed, autoQueued = 0, 0, 0
    GetServerTime = function() return now end
    GetNormalizedRealmName = function() return "RealmOne" end
    GetRealmName = GetNormalizedRealmName
    UnitFactionGroup = function() return "Alliance" end
    UnitLevel = function() return 10 end
    C_Item, GetItemInfo = nil, nil
    GetBuildInfo = function() return "1.60.1", "70888", "", 16001 end
    InCombatLockdown = function() return combat end
    Enum = { PlayerInteractionType = { Auctioneer = 21 } }
    hooksecurefunc = Hook
    C_AuctionHouse = {
        ReplicateItems = function() calls.replicate = calls.replicate + 1 end,
        GetNumReplicateItems = function() return #rows end,
        GetReplicateItemInfo = function(index)
            assert(index >= 0 and index < #rows, "replicate index must be in 0..N-1")
            calls.replicateFirst = calls.replicateFirst or index
            calls.replicateLast = index
            return info(rows[index + 1])
        end,
        GetReplicateItemLink = function(index)
            assert(index >= 0 and index < #rows, "replicate link index must be in 0..N-1")
            return rows[index + 1].link
        end,
        IsThrottledMessageSystemReady = function() calls.readiness = calls.readiness + 1; return ready end,
        MakeItemKey = function(id) return key(id) end,
        SendSellSearchQuery = function(itemKey, sorts, separate)
            assert(itemKey.itemLevel == 0 and itemKey.itemSuffix == 0)
            assert(type(sorts) == "table" and separate == false)
            calls.search = calls.search + 1
        end,
        SendSearchQuery = function() calls.search = calls.search + 1 end,
        SendBrowseQuery = function() end,
        RefreshItemSearchResults = function() end,
        RefreshCommoditySearchResults = function() end,
        SearchForItemKeys = function() end,
        SearchForFavorites = function() end,
        GetItemKeyInfo = function() return { isCommodity = #commodities > 0 } end,
        HasFullItemSearchResults = function() return full end,
        HasFullCommoditySearchResults = function() return full end,
        GetNumItemSearchResults = function() return #itemRows end,
        GetNumCommoditySearchResults = function() return #commodities end,
        GetItemSearchResultInfo = function(_, index) return itemRows[index] end,
        GetCommoditySearchResultInfo = function(_, index) return commodities[index] end,
        RequestMoreItemSearchResults = function() calls.pages = calls.pages + 1; return pageReturnsFull end,
        RequestMoreCommoditySearchResults = function() calls.pages = calls.pages + 1; return pageReturnsFull end,
    }
    QueryAuctionItems, CanSendAuctionQuery, GetNumAuctionItems, GetAuctionItemInfo, GetAuctionItemLink = nil, nil, nil, nil, nil
    if legacy then
        C_AuctionHouse = nil
        QueryAuctionItems = function(_, _, _, page, _, _, all) assert(page == 0 and all == true); calls.legacy = calls.legacy + 1 end
        CanSendAuctionQuery = function() return ready, ready end
        GetNumAuctionItems = function() return #rows, legacyTotal or #rows end
        GetAuctionItemInfo = function(_, index) return info(rows[index]) end
        GetAuctionItemLink = function(_, index) return rows[index].link end
    end
    db = { autoScan = automatic == true }
    scanner = ns.CreateScanner(db, { changed = function() changed = changed + 1 end,
        completed = function() completed = completed + 1 end, autoQueued = function() autoQueued = autoQueued + 1 end })
end
local function open() scanner:OnEvent("AUCTION_HOUSE_SHOW") end
local function record(id, suffix)
    return ns.Lookup(db, scanner:GetScope(), ns.ItemIdentity(link(id, suffix)), now)
end
local function seed(id, price)
    local snapshot = ns.NewSnapshot(scanner:GetScope(), now - 50, "Previous")
    ns.AddListing(snapshot, link(id), 1, price)
    ns.Commit(db, scanner:GetScope(), snapshot, true, false)
end
local function eq(actual, expected)
    if actual ~= expected then error("expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end
local passed = 0
local function test(name, fn)
    reset()
    local ok, err = pcall(fn)
    if not ok then error("FAIL: " .. name .. ": " .. tostring(err)) end
    passed = passed + 1
end

test("idle creation and events never query automatically", function()
    eq(calls.replicate, 0); eq(calls.search, 0)
    open(); scanner:Tick(1000); scanner:OnEvent("GET_ITEM_INFO_RECEIVED", 1)
    eq(calls.replicate, 0); eq(calls.search, 0); eq(scanner:GetState().busy, false)
end)
test("AH closed and combat requests do not query", function()
    eq(scanner:StartScan(), false); eq(scanner:RefreshItem(link(100)), false)
    open(); combat = true
    eq(scanner:StartScan(), false); eq(scanner:RefreshItem(link(100)), false)
    eq(calls.replicate, 0); eq(calls.search, 0)
end)
test("modern snapshot calculates per-unit observed extrema", function()
    open(); rows = { { id = 100, link = link(100), quantity = 10, buyout = 1000 }, { id = 100, link = link(100), quantity = 2, buyout = 700 } }
    assert(scanner:StartScan()); scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    local result = record(100)
    eq(result.min, 100); eq(result.max, 350); eq(result.complete, false)
    eq(result.units, 12); eq(completed, 1); eq(scanner:GetState().busy, false)
end)
test("replicate absence never claims market empty or clears unrelated cached prices", function()
    seed(999, 500); open(); assert(scanner:StartScan())
    scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    eq(record(999).min, 500); local result, meta = record(888); eq(result, nil); eq(meta.known, false)
end)
test("bulk reading is chunked and committed only after final row", function()
    seed(100, 777); open()
    for i = 1, 301 do rows[i] = { id = 100, link = link(100), quantity = 1, buyout = i } end
    assert(scanner:StartScan()); scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    eq(record(100).min, 777); eq(scanner:GetState().busy, true)
    scanner:Tick(0.1); eq(record(100).min, 777)
    scanner:Tick(0.1); eq(record(100).min, 1); eq(record(100).max, 301)
end)
test("cancel and auction close discard in-flight snapshots", function()
    seed(100, 777); open(); rows = { { id = 100, link = link(100), quantity = 1, buyout = 100 } }
    assert(scanner:StartScan()); scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Cancel()
    scanner:Tick(0.1); eq(record(100).min, 777)
    now = now + 901; assert(scanner:StartScan()); scanner:OnEvent("AUCTION_HOUSE_CLOSED")
    scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    eq(record(100).min, 777); eq(scanner:GetState().open, false)
end)
test("response timeout and cooldown preserve cached data", function()
    seed(100, 777); open(); assert(scanner:StartScan()); scanner:Tick(121)
    eq(record(100).min, 777); eq(scanner:GetState().busy, false)
    eq(scanner:StartScan(), false); eq(calls.replicate, 1)
    now = now + 901; assert(scanner:StartScan()); eq(calls.replicate, 2)
end)
test("native throttle readiness prevents requests", function()
    open(); ready = false
    eq(scanner:StartScan(), false); eq(scanner:RefreshItem(link(100)), false)
    eq(calls.replicate, 0); eq(calls.search, 0)
end)
test("focused item refresh filters other suffix variants", function()
    open(); itemRows = {
        { itemLink = link(100, 5), quantity = 1, buyoutAmount = 20 },
        { itemLink = link(100), quantity = 1, buyoutAmount = 200 },
        { itemLink = link(100), quantity = 1, buyoutAmount = 500 },
    }
    assert(scanner:RefreshItem(link(100))); scanner:OnEvent("ITEM_SEARCH_RESULTS_UPDATED", key(100)); scanner:Tick(0.1)
    eq(record(100).min, 200); eq(record(100).max, 500); eq(record(100).complete, true)
    eq(record(100, 5), nil)
end)
test("focused commodity refresh uses every returned price tier", function()
    open(); commodities = { { itemID = 100, quantity = 100, unitPrice = 10 }, { itemID = 100, quantity = 2, unitPrice = 800 } }
    assert(scanner:RefreshItem(link(100))); scanner:OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 100); scanner:Tick(0.1)
    eq(record(100).min, 10); eq(record(100).max, 800); eq(record(100).units, 102); eq(record(100).complete, true)
end)
test("incomplete item query waits for all pages and does not spam", function()
    seed(100, 777); open(); full = false
    itemRows = { { itemLink = link(100), quantity = 1, buyoutAmount = 10 } }
    assert(scanner:RefreshItem(link(100))); scanner:OnEvent("ITEM_SEARCH_RESULTS_UPDATED", key(100)); scanner:Tick(0.1)
    eq(calls.pages, 1); scanner:Tick(0.1); scanner:Tick(0.1); eq(calls.pages, 1)
    eq(record(100).min, 777)
    itemRows[2] = { itemLink = link(100), quantity = 1, buyoutAmount = 900 }
    full = true; scanner:OnEvent("ITEM_SEARCH_RESULTS_ADDED", key(100)); scanner:Tick(0.1)
    eq(record(100).min, 10); eq(record(100).max, 900)
end)
test("request-more full return finishes without another event", function()
    open(); full, pageReturnsFull = false, true
    itemRows = { { itemLink = link(100), quantity = 1, buyoutAmount = 800 } }
    assert(scanner:RefreshItem(link(100))); scanner:OnEvent("ITEM_SEARCH_RESULTS_UPDATED", key(100))
    scanner:Tick(0.1); scanner:Tick(0.1)
    eq(record(100).max, 800); eq(record(100).complete, true); eq(calls.pages, 1)
end)
test("complete empty search replaces only the selected quote", function()
    seed(100, 777); seed(999, 888); open()
    assert(scanner:RefreshItem(link(100))); scanner:OnEvent("ITEM_SEARCH_RESULTS_UPDATED", key(100)); scanner:Tick(0.1)
    eq(record(100).empty, true); eq(record(100).complete, true); eq(record(999).min, 888)
end)
test("unrelated and restricted result keys cannot finish active query", function()
    open(); assert(scanner:RefreshItem(link(100)))
    scanner:OnEvent("ITEM_SEARCH_RESULTS_UPDATED", key(999))
    scanner:OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", secret())
    local restricted = key(100); restricted.itemSuffix = secret()
    scanner:OnEvent("ITEM_SEARCH_RESULTS_UPDATED", restricted); scanner:Tick(0.1)
    eq(scanner:GetState().busy, true); eq(record(100), nil)
end)
test("unreadable prices produce incomplete range rather than false max", function()
    open(); commodities = { { itemID = 100, quantity = 2, unitPrice = 100 }, { itemID = 100, quantity = 2, unitPrice = secret() } }
    assert(scanner:RefreshItem(link(100))); scanner:OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 100); scanner:Tick(0.1)
    eq(record(100).min, 100); eq(record(100).complete, false)
end)
test("missing replica item link is omitted without claiming full coverage", function()
    open(); rows = { { id = 100, link = link(100), quantity = 1, buyout = 200 }, { id = 100, quantity = 1, buyout = 900 } }
    local legacyReads = 0
    GetAuctionItemLink = function() legacyReads = legacyReads + 1; return link(200) end
    assert(scanner:StartScan()); scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    eq(record(100).max, 200); eq(record(100).complete, false)
    eq(db.scopes[scanner:GetScope()].lastScanOmitted, 1)
    eq(legacyReads, 0); eq(record(200), nil)
end)
test("native new-results event can complete matching commodity query", function()
    open(); commodities = { { itemID = 100, quantity = 2, unitPrice = 90 } }
    assert(scanner:RefreshItem(link(100))); scanner:OnEvent("AUCTION_HOUSE_NEW_RESULTS_RECEIVED", key(100)); scanner:Tick(0.1)
    eq(record(100).min, 90)
end)
test("external modern searches cancel without overwriting prior quotes", function()
    seed(100, 777); open(); assert(scanner:RefreshItem(link(100)))
    C_AuctionHouse.RefreshItemSearchResults(key(100)); eq(scanner:GetState().busy, false)
    scanner:OnEvent("ITEM_SEARCH_RESULTS_UPDATED", key(100)); scanner:Tick(0.1); eq(record(100).min, 777)
end)
test("mid-read response changes cannot commit a mixed snapshot", function()
    seed(100, 777); open()
    for i = 1, 301 do itemRows[i] = { itemLink = link(100), quantity = 1, buyoutAmount = i } end
    assert(scanner:RefreshItem(link(100))); scanner:OnEvent("ITEM_SEARCH_RESULTS_UPDATED", key(100)); scanner:Tick(0.1)
    itemRows = {}; scanner:OnEvent("ITEM_SEARCH_RESULTS_UPDATED", key(100)); scanner:Tick(0.1)
    eq(scanner:GetState().busy, false); eq(record(100).min, 777)
end)
test("legacy full scan feature detection and scoped replacement", function()
    reset(true); seed(999, 888); open()
    rows = { { id = 100, link = link(100), quantity = 5, buyout = 500 } }
    assert(scanner:StartScan(true)); scanner:OnEvent("AUCTION_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    eq(record(100).min, 100); eq(record(100).complete, true); eq(record(999).empty, true)
    eq(scanner:GetState().canRefresh, false); eq(scanner:RefreshItem(link(100)), false)
end)
test("external legacy query cannot masquerade as a completed full scan", function()
    reset(true); seed(100, 777); open(); assert(scanner:StartScan())
    QueryAuctionItems("", nil, nil, 0, false, nil, true, false)
    eq(scanner:GetState().busy, false)
    scanner:OnEvent("AUCTION_ITEM_LIST_UPDATE"); scanner:Tick(0.1); eq(record(100).min, 777)
end)
test("legacy partial result waits rather than wiping cache", function()
    reset(true); seed(100, 777); open(); legacyTotal = 20
    rows = { { id = 100, link = link(100), quantity = 5, buyout = 500 } }
    assert(scanner:StartScan()); scanner:OnEvent("AUCTION_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    eq(scanner:GetState().busy, true); eq(record(100).min, 777)
end)
test("interaction manager open-close and world changes are query-free", function()
    scanner:OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8); eq(scanner:GetState().open, false)
    scanner:OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21); eq(scanner:GetState().open, true)
    assert(scanner:RefreshItem(link(100)))
    scanner:OnEvent("PLAYER_ENTERING_WORLD"); eq(scanner:GetState().busy, false); eq(scanner:GetState().open, false)
    eq(calls.search, 1)
end)
test("unavailable capability reports false without native calls", function()
    C_AuctionHouse = nil
    eq(scanner:GetState().canScan, false); eq(scanner:GetState().canRefresh, false)
    open(); eq(scanner:StartScan(), false); eq(scanner:RefreshItem(link(100)), false)
end)

test("result growth before first chunk refreshes count before claiming complete", function()
    open(); itemRows = { { itemLink = link(100), quantity = 1, buyoutAmount = 10 } }
    assert(scanner:RefreshItem(link(100))); scanner:OnEvent("ITEM_SEARCH_RESULTS_UPDATED", key(100))
    itemRows[2] = { itemLink = link(100), quantity = 1, buyoutAmount = 900 }
    scanner:OnEvent("ITEM_SEARCH_RESULTS_UPDATED", key(100)); scanner:Tick(0.1)
    eq(record(100).max, 900); eq(record(100).complete, true)
end)
test("bulk result growth before first chunk reads the new count", function()
    open(); rows = { { id = 100, link = link(100), quantity = 1, buyout = 10 } }
    assert(scanner:StartScan()); scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE")
    rows[2] = { id = 100, link = link(100), quantity = 1, buyout = 900 }
    scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    eq(record(100).max, 900)
end)
test("auction failure events end the job promptly and preserve prices", function()
    seed(100, 777); open(); assert(scanner:RefreshItem(link(100)))
    scanner:OnEvent("AUCTION_HOUSE_SHOW_ERROR", 1)
    eq(scanner:GetState().busy, false); eq(record(100).min, 777)
end)

test("replicate scan includes both first and last zero-based native rows", function()
    open(); rows = {
        { id = 100, link = link(100), quantity = 1, buyout = 12 },
        { id = 100, link = link(100), quantity = 1, buyout = 999 },
    }
    assert(scanner:StartScan()); scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    eq(calls.replicateFirst, 0); eq(calls.replicateLast, 1)
    eq(record(100).min, 12); eq(record(100).max, 999)
    eq(db.scopes[scanner:GetScope()].lastScanOmitted, 0)
end)

test("automatic scan queues once per visit after a quiet delay", function()
    reset(false, true); open()
    eq(scanner:GetState().autoPending, true); eq(scanner:GetState().phase, "queued")
    eq(scanner:GetState().progress, nil); eq(scanner:GetState().busy, false); eq(autoQueued, 1)
    scanner:Tick(1.5); open(); scanner:OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21)
    eq(autoQueued, 1); eq(calls.replicate, 0)
    scanner:Tick(0.5); eq(calls.replicate, 1); eq(scanner:GetState().phase, "waiting")
    eq(scanner:GetState().progress, nil); eq(scanner:GetState().autoPending, false)
    local status = scanner:GetState().status
    open(); scanner:Tick(3)
    eq(calls.replicate, 1); eq(scanner:GetState().status, status)
end)

test("automatic scan waits for throttle readiness without per-frame polling", function()
    reset(false, true); ready = false; open()
    scanner:Tick(2); eq(calls.replicate, 0); eq(scanner:GetState().autoPending, true)
    local before = calls.readiness
    for i = 1, 9 do scanner:Tick(0.05) end
    eq(calls.readiness, before)
    ready = true; scanner:Tick(0.1)
    eq(calls.replicate, 1); eq(scanner:GetState().busy, true)
end)

test("native startup searches restart only the quiet delay", function()
    reset(false, true); open(); scanner:Tick(1.5)
    C_AuctionHouse.SendBrowseQuery({})
    scanner:Tick(1.5); eq(calls.replicate, 0); eq(autoQueued, 1)
    scanner:Tick(0.5); eq(calls.replicate, 1)
end)

test("automatic cooldown skips the visit with saved prices intact", function()
    reset(false, true); seed(100, 777)
    db.scanRequestedAt[scanner:GetScope()] = now - 10
    open(); scanner:Tick(2)
    eq(scanner:GetState().phase, "cooldown"); eq(scanner:GetState().autoPending, false)
    eq(scanner:GetState().progress, nil); eq(record(100).min, 777); eq(calls.replicate, 0)
    now = now + 901; open(); scanner:Tick(1000); eq(calls.replicate, 0)
    scanner:OnEvent("AUCTION_HOUSE_CLOSED"); open(); scanner:Tick(2)
    eq(calls.replicate, 1); eq(autoQueued, 2)
end)

test("cancelled pending auto scan stays cancelled for the current visit", function()
    reset(false, true); open(); scanner:Cancel()
    eq(scanner:GetState().phase, "cancelled"); eq(scanner:GetState().autoPending, false)
    open(); scanner:Tick(10); eq(calls.replicate, 0)
    scanner:OnEvent("AUCTION_HOUSE_CLOSED"); open(); scanner:Tick(2); eq(calls.replicate, 1)
end)

test("closing or changing worlds clears pending automatic requests", function()
    reset(false, true); open(); scanner:OnEvent("AUCTION_HOUSE_CLOSED"); scanner:Tick(10)
    eq(calls.replicate, 0); eq(scanner:GetState().autoPending, false)
    open(); scanner:OnEvent("PLAYER_ENTERING_WORLD"); scanner:Tick(10)
    eq(calls.replicate, 0); eq(scanner:GetState().open, false)
end)

test("option changes cancel pending but preserve active scans", function()
    reset(false, true); open(); scanner:SetAutoScan(false); scanner:Tick(10)
    eq(db.autoScan, false); eq(calls.replicate, 0); eq(scanner:GetState().autoPending, false)
    scanner:SetAutoScan(true); open(); scanner:Tick(2); eq(calls.replicate, 0)
    scanner:OnEvent("AUCTION_HOUSE_CLOSED"); open(); scanner:Tick(2)
    eq(calls.replicate, 1); scanner:SetAutoScan(false)
    eq(scanner:GetState().busy, true); eq(db.autoScan, false)
    scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    eq(scanner:GetState().phase, "complete"); eq(completed, 1)
end)

test("manual market scan replaces the pending automatic request", function()
    reset(false, true); open(); assert(scanner:StartScan())
    eq(calls.replicate, 1); eq(scanner:GetState().autoPending, false)
    scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Tick(0.1); scanner:Tick(3)
    eq(calls.replicate, 1); eq(completed, 1)
end)

test("manual item refresh replaces the pending automatic request", function()
    reset(false, true); open(); assert(scanner:RefreshItem(link(100)))
    eq(calls.search, 1); eq(scanner:GetState().autoPending, false)
    scanner:OnEvent("ITEM_SEARCH_RESULTS_UPDATED", key(100)); scanner:Tick(0.1); scanner:Tick(3)
    eq(calls.replicate, 0); eq(calls.search, 1); eq(completed, 1)
end)

test("pending automatic readiness timeout never restarts on duplicate open", function()
    reset(false, true); ready = false; open(); scanner:Tick(2); scanner:Tick(28)
    eq(scanner:GetState().phase, "error"); eq(scanner:GetState().autoPending, false)
    ready = true; open(); scanner:Tick(10); eq(calls.replicate, 0)
end)

test("automatic scan waits for combat to end", function()
    reset(false, true); combat = true; open(); scanner:Tick(2)
    eq(calls.replicate, 0); eq(scanner:GetState().autoPending, true)
    combat = false; scanner:Tick(0.5); eq(calls.replicate, 1)
end)

test("legacy automatic scan waits for native full-query availability", function()
    reset(true, true); ready = false; open(); scanner:Tick(2); eq(calls.legacy, 0)
    ready = true; scanner:Tick(0.5); eq(calls.legacy, 1)
end)

test("progress is unknown until response then measures processed listings", function()
    open()
    for i = 1, 301 do rows[i] = { id = 100, link = link(100), quantity = 1, buyout = i } end
    assert(scanner:StartScan())
    eq(scanner:GetState().phase, "waiting"); eq(scanner:GetState().progress, nil); eq(scanner:GetState().total, nil)
    scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE")
    eq(scanner:GetState().phase, "processing"); eq(scanner:GetState().progress, 0)
    eq(scanner:GetState().processed, 0); eq(scanner:GetState().total, 301)
    scanner:Tick(0.1)
    eq(scanner:GetState().processed, 150); eq(scanner:GetState().progress, 150 / 301)
    scanner:Tick(0.1); eq(scanner:GetState().progress, 300 / 301)
    scanner:Tick(0.1); eq(scanner:GetState().phase, "complete"); eq(scanner:GetState().progress, 1)
    eq(scanner:GetState().processed, 301); eq(completed, 1)
end)

test("cancel and errors remove percentages rather than falsely showing completion", function()
    open()
    for i = 1, 301 do rows[i] = { id = 100, link = link(100), quantity = 1, buyout = i } end
    assert(scanner:StartScan()); scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    scanner:Cancel(); eq(scanner:GetState().phase, "cancelled"); eq(scanner:GetState().progress, nil)
    eq(scanner:GetState().processed, nil); eq(scanner:GetState().total, nil); eq(completed, 0)
    now = now + 901; assert(scanner:StartScan()); scanner:Tick(121)
    eq(scanner:GetState().phase, "error"); eq(scanner:GetState().progress, nil)
end)

test("failed cache commit cannot report100percent complete", function()
    open(); assert(scanner:StartScan()); scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE")
    local original = ns.Commit
    ns.Commit = function() return false end
    scanner:Tick(0.1)
    ns.Commit = original
    eq(scanner:GetState().phase, "error"); eq(scanner:GetState().progress, nil); eq(completed, 0)
end)

test("bulk level cap skips expensive reads for high requirements and expands on later scans", function()
    open()
    rows = {
        { id = 100, link = link(100), quantity = 1, buyout = 50, level = 0 },
        { id = 101, link = link(101), quantity = 1, buyout = 60, level = 12 },
        { id = 102, link = link(102), quantity = 1, buyout = 70, level = 13 },
    }
    local linksRead = 0
    C_AuctionHouse.GetReplicateItemLink = function(index) linksRead = linksRead + 1; return rows[index + 1].link end
    assert(scanner:StartScan()); scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    eq(linksRead, 2); eq(record(100).min, 50); eq(record(101).min, 60); eq(record(102), nil)
    eq(db.scopes[scanner:GetScope()].lastScanOmitted, 0)
    UnitLevel = function() return 11 end
    now = now + 901
    assert(scanner:StartScan()); scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    eq(linksRead, 5); eq(record(102).min, 70)
end)

test("bulk fallback uses required level per item link and omits unreadable requirements", function()
    open()
    rows = {
        { id = 100, link = link(100), quantity = 1, buyout = 70, level = 250, levelType = "SKILL_ABBR" },
        { id = 100, link = link(100), quantity = 1, buyout = 80, level = 250, levelType = "SKILL_ABBR" },
        { id = 100, link = link(100, 9), quantity = 1, buyout = 500, level = 2, levelType = "ITEM_LEVEL_ABBR" },
        { id = 101, link = link(101), quantity = 1, buyout = 600, level = 20, levelType = "SLOT_ABBR" },
        { id = 102, link = link(102), quantity = 1, buyout = 700, level = secret() },
    }
    local reads = 0
    C_Item = { GetItemInfo = function(item)
        reads = reads + 1
        local level
        if item == link(100) then level = 0
        elseif item == link(100, 9) then level = 40
        elseif item == link(101) then level = secret() end
        return "Item", item, 2, 99, level
    end }
    assert(scanner:StartScan()); scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    eq(reads, 4); eq(record(100).min, 70); eq(record(100).max, 80); eq(record(100, 9), nil)
    eq(record(101), nil); eq(record(102), nil); eq(db.scopes[scanner:GetScope()].lastScanOmitted, 2)
    now = now + 901
    assert(scanner:StartScan(true)); scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    eq(reads, 4); eq(record(100, 9).min, 500); eq(record(101).min, 600); eq(record(102).min, 700)
end)

test("filtered bulk scan covers more cheap rows per frame with a bound", function()
    open()
    local high = { id = 100, link = link(100), quantity = 1, buyout = 10, level = 15 }
    for index = 1, 1500 do rows[index] = high end
    assert(scanner:StartScan()); scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    local processed = scanner:GetState().processed
    assert(processed > 150 and processed < #rows)
    eq(scanner:GetState().busy, true); eq(record(100), nil)
    for index = 1, 9 do scanner:Tick(0.1) end
    eq(scanner:GetState().phase, "complete"); eq(record(100), nil)
end)

test("capped legacy snapshot leaves older prices and unknown market coverage intact", function()
    reset(true); seed(999, 300); open()
    rows = {
        { id = 100, link = link(100), quantity = 1, buyout = 50, level = 12 },
        { id = 999, link = link(999), quantity = 1, buyout = 900, level = 13 },
    }
    assert(scanner:StartScan()); scanner:OnEvent("AUCTION_ITEM_LIST_UPDATE"); scanner:Tick(0.1)
    eq(record(100).min, 50); eq(record(100).complete, false)
    eq(record(999).min, 300); eq(record(888), nil); eq(db.scopes[scanner:GetScope()].fullScanAt, nil)
end)

print("AUCTION SCANNER PASS: " .. passed .. " mocked-client cases")
