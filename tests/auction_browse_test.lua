-- Drive the scanner using the Forever browse API. GetBrowseResults returns
-- the whole list; the RESULTS_ADDED event carries only the new rows.
local ns = {}
assert(loadfile(TEST_ROOT .. "/AuctionPeek/Model.lua"))("AuctionPeek", ns)
assert(loadfile(TEST_ROOT .. "/AuctionPeek/Scanner.lua"))("AuctionPeek", ns)
local db, scanner, level, now, ready, full, rows, queries, pageRequests, replications, completions
local onMore
local function eq(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function row(id, suffix, price, itemLevel)
    return { itemKey = { itemID = id, itemSuffix = suffix, itemLevel = itemLevel or 0, battlePetSpeciesID = 0 },
        minPrice = price, totalQuantity = 7 }
end
local function reset(automatic)
    db, level, now, ready, full = { autoScan = automatic }, 10, 10000, true, false
    rows, queries, pageRequests, replications, completions = {}, {}, 0, 0, 0
    onMore = nil
    UnitLevel = function(unit) eq(unit, "player"); return level end
    UnitFactionGroup = function() return "Alliance" end
    GetNormalizedRealmName = function() return "TestRealm" end
    GetBuildInfo = function() return "1.60.1", "70888", "", 16001 end
    GetServerTime = function() return now end
    Enum = { AuctionHouseSortOrder = { Price = 0, Name = 1 },
        AuctionHouseFilter = { UsableOnly = 0, PoorQuality = 4, CommonQuality = 5, UncommonQuality = 6,
            RareQuality = 7, EpicQuality = 8, LegendaryQuality = 9, ArtifactQuality = 10 } }
    C_AuctionHouse = {
        IsThrottledMessageSystemReady = function() return ready end,
        SendBrowseQuery = function(query) queries[#queries + 1] = query end,
        HasFullBrowseResults = function() return full end,
        GetBrowseResults = function() return rows end,
        RequestMoreBrowseResults = function()
            pageRequests = pageRequests + 1
            if onMore then onMore() end
        end,
        ReplicateItems = function() replications = replications + 1 end,
        GetNumReplicateItems = function() return 0 end,
        GetReplicateItemInfo = function() end,
        GetReplicateItemLink = function() end,
    }
    hooksecurefunc = function(target, name, callback)
        local original = assert(target[name])
        target[name] = function(...)
            local result = original(...)
            callback(...)
            return result
        end
    end
    scanner = ns.CreateScanner(db, { completed = function() completions = completions + 1 end })
    scanner:OnEvent("AUCTION_HOUSE_SHOW")
end
local function tick()
    for i = 1, 10 do scanner:Tick(0.1) end
end
local function first(page, isFull)
    rows, full = page, isFull
    scanner:OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    tick()
end
local function append(page, isFull)
    for _, result in ipairs(page) do rows[#rows + 1] = result end
    full = isFull
    scanner:OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", page)
    tick()
end
local function lookup(id, suffix)
    return ns.Lookup(db, scanner:GetScope(), tostring(id) .. ":" .. tostring(suffix or 0), now)
end
local function browse(id, suffix)
    local _, info = lookup(id, suffix)
    return info.browse
end
local function reopen()
    scanner:OnEvent("AUCTION_HOUSE_CLOSED")
    scanner:OnEvent("AUCTION_HOUSE_SHOW")
    scanner:Tick(2)
end
local passed = 0
local function test(name, fn)
    reset(false)
    local ok, err = pcall(fn)
    if not ok then error("FAIL: " .. name .. ": " .. tostring(err)) end
    passed = passed + 1
end

test("default scan requests level 12 on the server for a level 10 character", function()
    assert(scanner:StartScan())
    eq(#queries, 1); eq(replications, 0)
    local query = queries[1]
    eq(query.maxLevel, 12)
    assert(query.minLevel == nil or query.minLevel == 0, "items without level requirements must qualify")
    assert(type(query.sorts) == "table" and #query.sorts > 0, "missing native sort")
    local qualities = {}
    for _, filter in ipairs(query.filters or {}) do qualities[filter] = true end
    assert(qualities[Enum.AuctionHouseFilter.CommonQuality] and qualities[Enum.AuctionHouseFilter.EpicQuality])
    assert(not qualities[Enum.AuctionHouseFilter.UsableOnly], "next-level gear must qualify")
end)

test("missing character level never starts a whole-market download", function()
    level = nil
    scanner:StartScan()
    eq(#queries, 0); eq(replications, 0)
    eq(scanner:GetState().busy, false)
    reset(true); level = 0; scanner:Tick(2); tick()
    eq(#queries, 0); eq(replications, 0)
end)

test("prices are available after each page and grouped minima stay independent of exact ranges", function()
    local scope = scanner:GetScope()
    local snapshot = ns.NewSnapshot(scope, now - 60, "Item refresh")
    ns.AddListing(snapshot, "item:100", 1, 500)
    ns.AddListing(snapshot, "item:100", 1, 800)
    ns.Commit(db, scope, snapshot, true, false)
    assert(scanner:StartScan())
    ready = false
    first({ row(100, 0, 210, 11), row(100, -7, 160, 20), row(101, 0, 140) }, false)
    eq(pageRequests, 0); eq(completions, 0)
    eq(browse(100).price, 210); eq(browse(100).maxLevel, 12)
    eq(browse(100, -7).price, 160); eq(browse(101).price, 140)
    eq(scanner:GetState().processed, 3)
    ready = true; tick(); tick()
    eq(pageRequests, 1)
    append({ row(100, 0, 75, 19), row(101, 0, 230, 3) }, true)
    eq(pageRequests, 1); eq(completions, 1); eq(scanner:GetState().busy, false)
    eq(scanner:GetState().processed, 5)
    eq(browse(100).price, 75); eq(browse(101).price, 140); eq(browse(100, -7).price, 160)
    local exact, meta = lookup(100)
    eq(exact.min, 500); eq(exact.max, 800); eq(meta.complete, true)
    eq(lookup(101), nil)
    local missing, missingMeta = lookup(999)
    eq(missing, nil); eq(missingMeta.browse, nil); eq(missingMeta.empty, false)
end)

test("invalid prices, zero-stock rows and cages cannot publish a group price", function()
    local pet, empty = row(300, 0, 25), row(301, 0, 30)
    pet.itemKey.battlePetSpeciesID, empty.totalQuantity = 45, 0
    assert(scanner:StartScan())
    first({ pet, empty, row(302, 0, 0), row(303, 0, -2), row(304, 0, "4"),
        row(305, 0, 75) }, true)
    for id = 300, 304 do eq(browse(id), nil) end
    eq(browse(305).price, 75)
end)

test("a synchronous added response is accepted while requesting the next page", function()
    onMore = function()
        full = true
        local added = { row(200, 0, 40) }
        rows[#rows + 1] = added[1]
        scanner:OnEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", added)
    end
    assert(scanner:StartScan())
    first({ row(100, 0, 75) }, false)
    eq(pageRequests, 1); eq(completions, 1)
    eq(browse(100).price, 75); eq(browse(200).price, 40)
    eq(scanner:GetState().processed, 2)
end)

test("leaving saves observed groups and prevents a late response from writing more", function()
    assert(scanner:StartScan())
    first({ row(100, 0, 75) }, false)
    eq(pageRequests, 1)
    scanner:OnEvent("AUCTION_HOUSE_CLOSED")
    append({ row(200, 0, 40) }, true)
    eq(browse(100).price, 75); eq(browse(200), nil)
    eq(completions, 0); eq(pageRequests, 1)
    scanner:OnEvent("AUCTION_HOUSE_SHOW")
    assert(scanner:StartScan(), "an interrupted scan must not mark its entire level range fresh")
end)

test("another browse cancels the outstanding request and its continuation", function()
    assert(scanner:StartScan())
    ready = false; first({ row(100, 0, 100) }, false)
    C_AuctionHouse.SendBrowseQuery({ searchString = "external" })
    ready = true
    first({ row(999, 0, 1) }, true)
    eq(pageRequests, 0); eq(completions, 0); eq(scanner:GetState().busy, false)
    eq(browse(100).price, 100); eq(browse(999), nil)
end)

test("automatic scan skips fresh coverage and expands after leveling", function()
    reset(true)
    scanner:Tick(2)
    eq(#queries, 1); eq(queries[1].maxLevel, 12)
    first({ row(100, 0, 100) }, true)
    now = now + 60; reopen(); eq(#queries, 1)
    level = 11; reopen(); eq(#queries, 2); eq(queries[2].maxLevel, 13)
    first({ row(105, 0, 85) }, true)
    now = now + 901; reopen(); eq(#queries, 3)
    first({ row(105, 0, 210) }, true)
    eq(browse(105).price, 210)
    eq(replications, 0)
end)

test("explicit full scan has an independent bulk cooldown", function()
    assert(scanner:StartScan()); first({ row(100, 0, 100) }, true)
    assert(scanner:StartScan(true)); eq(replications, 1)
    scanner:OnEvent("REPLICATE_ITEM_LIST_UPDATE"); tick()
    eq(scanner:StartScan(true), false); eq(replications, 1)
    level = 11; assert(scanner:StartScan())
    eq(#queries, 2); eq(queries[2].maxLevel, 13)
end)

test("another character's partial scan invalidates the previous cap's freshness", function()
    reset(true); scanner:Tick(2)
    first({ row(100, 0, 500) }, true)
    level = 50; reopen(); eq(queries[2].maxLevel, 52)
    first({ row(100, 0, 100) }, false)
    level = 10; reopen(); eq(queries[3].maxLevel, 12)
    first({ row(100, 0, 500) }, true)
    eq(browse(100).maxLevel, 12); eq(browse(100).price, 500)
end)

test("the native browse window can advance the same query without a duplicate request", function()
    assert(scanner:StartScan())
    ready = false; first({ row(100, 0, 10) }, false)
    C_AuctionHouse.RequestMoreBrowseResults()
    ready = true; tick(); eq(pageRequests, 1)
    append({ row(200, 0, 20) }, true)
    eq(browse(200).price, 20); eq(completions, 1)
end)

print("AUCTION BROWSE PASS: " .. passed .. " mocked-client cases")
