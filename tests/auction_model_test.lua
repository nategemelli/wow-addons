local ns = {}
local restricted = setmetatable({}, { __mode = "k" })
issecretvalue = function(value) return type(value) == "table" and restricted[value] == true end
local function secret()
    local function forbidden() error("restricted value was inspected") end
    local value = setmetatable({}, { __tostring = forbidden, __concat = forbidden,
        __lt = forbidden, __le = forbidden, __add = forbidden, __div = forbidden })
    restricted[value] = true
    return value
end
assert(loadfile(TEST_ROOT .. "/AuctionPeek/Model.lua"))("AuctionPeek", ns)
local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error("FAIL: " .. name .. ": " .. tostring(err)) end
    passed = passed + 1
end
local function eq(actual, expected) assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
local function identity(link) return assert(ns.ItemIdentity(link)) end
local function snapshot() return ns.NewSnapshot("Realm/Alliance", 1000, "Test search") end
local function link(fields)
    return "|cff1eff00|Hitem:" .. table.concat(fields, ":") .. "|h[Test Item]|h|r"
end

test("raw and full ordinary item links have the same identity", function()
    eq(identity("item:123"), identity("|cffffffff|Hitem:123:0:0:0:0:0:0:0:80:0:0:0:0|h[Item]|h|r"))
    local key, itemID = ns.ItemIdentity("item:123")
    eq(key, "123:0"); eq(itemID, 123)
end)

test("viewer level enchant gems and unique IDs do not split a market", function()
    eq(identity("item:123:55:1:2:3:4:0:456:20:1"), identity("item:123:0:0:0:0:0:0:999:80:2"))
end)

test("suffix variants remain separate including negative random suffix IDs", function()
    assert(identity("item:123:0:0:0:0:0:-42") ~= identity("item:123:0:0:0:0:0:-43"))
    assert(identity("item:123:0:0:0:0:0:42") ~= identity("item:123"))
end)

test("bonus identity is independent of bonus ordering", function()
    local a = { 123, 0, 0, 0, 0, 0, 0, 0, 80, 0, 0, 2, 2, 102, 101 }
    local b = { 123, 0, 0, 0, 0, 0, 0, 7, 20, 0, 0, 2, 2, 101, 102 }
    eq(identity(link(a)), identity(link(b)))
    b[15] = 103
    assert(identity(link(a)) ~= identity(link(b)))
end)

test("context and modifier data are not silently merged", function()
    local a = { 123, 0, 0, 0, 0, 0, 0, 0, 80, 0, 0, 2, 0 }
    local b = { 123, 0, 0, 0, 0, 0, 0, 0, 80, 0, 0, 3, 0 }
    assert(identity(link(a)) ~= identity(link(b)))
    b[12], b[14], b[15] = 2, 1, 500
    assert(identity(link(a)) ~= identity(link(b)))
end)

test("empty fields and trailing zero extensions normalize", function()
    eq(identity("item:123::::::"), identity("item:123:0:0:0:0:0:0:0:0:0:0:0:0:0:0"))
end)

test("malformed secret nonitem and incomplete bonus links are rejected", function()
    for _, value in ipairs({ "battlepet:123", "item:0", "item:-2", "item:x", "item:123:bogus",
        "item:123:0:0:0:0:0:0:0:0:0:0:0:2:11", "item:123:0:0:0:0:0:0:0:0:0:0:0:-1", secret() }) do
        eq(ns.ItemIdentity(value), nil)
    end
    eq(ns.ItemIdentity(nil), nil)
end)

test("per-unit range and quantities come from priced auctions only", function()
    local scan = snapshot()
    assert(ns.AddListing(scan, "item:123", 20, 4000))
    assert(ns.AddListing(scan, "item:123", 2, 1000))
    assert(ns.AddListing(scan, "item:123", 5, 0))
    local row = scan.items[identity("item:123")]
    eq(row.min, 200); eq(row.max, 500); eq(row.listingCount, 2); eq(row.units, 22)
    eq(scan.rows, 3); eq(scan.bidOnly, 1); eq(scan.omitted, 0)
end)

test("fractional copper stays numeric and never becomes a free quote", function()
    local scan = snapshot()
    ns.AddListing(scan, "item:123", 20, 1)
    eq(scan.items[identity("item:123")].min, 0.05)
    eq(ns.FormatMoney(0.05), "<1c"); eq(ns.FormatMoney(50.5), "~51c")
end)

test("invalid price quantity and restricted fields mark the range incomplete", function()
    local scan = snapshot()
    for _, row in ipairs({ { "item:123", 0, 10 }, { "item:123", -1, 10 }, { "item:123", 1, -2 },
        { "item:123", 1, secret() }, { secret(), 1, 10 }, { "item:123", secret(), 10 },
        { "item:123", 1, 1 / 0 }, { "item:123", 1, 0 / 0 }, { "item:123", 1, 1.5 } }) do
        eq(ns.AddListing(scan, unpack(row)), false)
    end
    eq(scan.omitted, 9); eq(scan.incomplete, true)
    local db = {}
    local ok, complete = ns.Commit(db, scan.scope, scan, true, true)
    eq(ok, true); eq(complete, false); eq(db.scopes[scan.scope].fullScanAt, nil)
end)

test("unknown cache differs from a completed empty target search", function()
    local db, scan = {}, snapshot()
    local key = identity("item:123")
    local record, info = ns.Lookup(db, scan.scope, key, 1001)
    eq(record, nil); eq(info.known, false)
    scan.targetKey = key
    ns.Commit(db, scan.scope, scan, true, false)
    record, info = ns.Lookup(db, scan.scope, key, 1001)
    eq(record.min, nil); eq(record.listingCount, 0); eq(info.known, true); eq(info.empty, true); eq(info.complete, true)
end)

test("targeted searches exclude other name matches and suffixes", function()
    local scan = snapshot()
    scan.targetKey = identity("item:123:0:0:0:0:0:42")
    ns.AddListing(scan, "item:123:0:0:0:0:0:43", 1, 1)
    ns.AddListing(scan, "item:124", 1, 1)
    ns.AddListing(scan, "item:123:0:0:0:0:0:42", 1, 200)
    eq(scan.items[identity("item:124")], nil)
    eq(scan.items[scan.targetKey].min, 200)
end)

test("bid-only results report no observed buyout rather than zero price", function()
    local db, scan = {}, snapshot()
    ns.AddListing(scan, "item:123", 1, 0)
    ns.Commit(db, scan.scope, scan, true, false)
    local record, info = ns.Lookup(db, scan.scope, identity("item:123"), 1001)
    eq(record.min, nil); eq(info.empty, true); eq(info.complete, true)
end)

test("new snapshots replace ranges without historical extrema", function()
    local db, scan = {}, snapshot()
    ns.AddListing(scan, "item:123", 1, 10000); ns.Commit(db, scan.scope, scan, true, false)
    local newer = ns.NewSnapshot(scan.scope, 1100, "New search")
    ns.AddListing(newer, "item:123", 1, 50); ns.Commit(db, newer.scope, newer, true, false)
    local record = ns.Lookup(db, newer.scope, identity("item:123"), 1101)
    eq(record.min, 50); eq(record.max, 50); eq(record.updatedAt, 1100)
end)

test("realm and faction scopes remain isolated", function()
    local db, scan = {}, snapshot()
    ns.AddListing(scan, "item:123", 1, 300); ns.Commit(db, scan.scope, scan, true, false)
    eq(ns.Lookup(db, "OtherRealm/Alliance", identity("item:123"), 1001), nil)
    eq(ns.Lookup(db, "Realm/Horde", identity("item:123"), 1001), nil)
    eq(ns.Commit(db, "OtherRealm/Alliance", scan, true, false), false)
end)

test("only a complete full scan establishes absence and removes obsolete records", function()
    local db, scan = {}, snapshot()
    ns.AddListing(scan, "item:123", 1, 100); ns.Commit(db, scan.scope, scan, true, false)
    local full = ns.NewSnapshot(scan.scope, 1200, "Full scan")
    ns.AddListing(full, "item:124", 1, 400); ns.Commit(db, full.scope, full, true, true)
    local record, info = ns.Lookup(db, full.scope, identity("item:123"), 1201)
    eq(record.min, nil); eq(info.empty, true); eq(info.complete, true); eq(record.updatedAt, 1200)
    eq(db.scopes[scan.scope].items[identity("item:123")], nil)
end)

test("partial scans cannot erase unrelated quotes or assert market absence", function()
    local db, scan = {}, snapshot()
    ns.AddListing(scan, "item:123", 1, 100); ns.Commit(db, scan.scope, scan, true, false)
    local partial = ns.NewSnapshot(scan.scope, 1300, "Observed page")
    ns.AddListing(partial, "item:124", 1, 200); ns.Commit(db, partial.scope, partial, false, true)
    eq(ns.Lookup(db, partial.scope, identity("item:123"), 1301).min, 100)
    local record, info = ns.Lookup(db, partial.scope, identity("item:124"), 1301)
    eq(record.min, 200); eq(info.complete, false)
    eq(ns.Lookup(db, partial.scope, identity("item:125"), 1301), nil)
end)

test("incomplete empty target does not erase the previous complete quote", function()
    local db, scan = {}, snapshot()
    ns.AddListing(scan, "item:123", 1, 100); ns.Commit(db, scan.scope, scan, true, false)
    local partial = ns.NewSnapshot(scan.scope, 1300, "Partial search")
    partial.targetKey = identity("item:123")
    ns.Commit(db, partial.scope, partial, false, false)
    eq(ns.Lookup(db, partial.scope, partial.targetKey, 1301).min, 100)
end)

test("committed records are independent of mutable snapshots", function()
    local db, scan = {}, snapshot()
    ns.AddListing(scan, "item:123", 1, 100); ns.Commit(db, scan.scope, scan, true, false)
    scan.items[identity("item:123")].min = 1
    eq(ns.Lookup(db, scan.scope, identity("item:123"), 1001).min, 100)
end)

test("freshness reports age stale data and future-clock anomalies", function()
    local db, scan = {}, snapshot()
    ns.AddListing(scan, "item:123", 1, 100); ns.Commit(db, scan.scope, scan, true, false)
    local _, info = ns.Lookup(db, scan.scope, identity("item:123"), 2800)
    eq(info.age, 1800); eq(info.stale, false)
    _, info = ns.Lookup(db, scan.scope, identity("item:123"), 2801); eq(info.stale, true)
    _, info = ns.Lookup(db, scan.scope, identity("item:123"), 999); eq(info.clockSkew, true); eq(info.stale, true)
    _, info = ns.Lookup(db, scan.scope, identity("item:123"), nil); eq(info.stale, true)
end)

test("corrupt saved prices do not become trustworthy zero or full-scan absence", function()
    local db, scan = {}, snapshot()
    ns.AddListing(scan, "item:123", 1, 100); ns.Commit(db, scan.scope, scan, true, true)
    db.scopes[scan.scope].items[identity("item:123")].min = "bad"
    local record, info = ns.Lookup(db, scan.scope, identity("item:123"), 1001)
    eq(record, nil); eq(info.known, false)
end)

test("browse minima span levels and bonuses within a suffix and refresh independently of exact quotes", function()
    local db, scan, seen = {}, snapshot(), {}
    local link = "item:123:0:0:0:0:0:-2:0:0:0:0:0:1:777"
    ns.AddListing(scan, link, 1, 900); ns.Commit(db, scan.scope, scan, true, false)
    local group = { itemID = 123, itemSuffix = -2, battlePetSpeciesID = 0, itemLevel = 5 }
    assert(ns.SaveBrowsePrice(db, scan.scope, group, 150, 2000, 18, seen))
    group.itemLevel = 15
    assert(ns.SaveBrowsePrice(db, scan.scope, group, 80, 2000, 18, seen))
    assert(ns.SaveBrowsePrice(db, scan.scope, group, 400, 2000, 18, seen))
    local record, info = ns.Lookup(db, scan.scope, identity(link), 3000)
    eq(record.min, 900); eq(info.complete, true); eq(info.stale, true)
    eq(info.browse.price, 80); eq(info.browse.age, 1000); eq(info.browse.stale, false); eq(info.browse.maxLevel, 18)
    record, info = ns.Lookup(db, scan.scope, "123:-2", 4200)
    eq(record, nil); eq(info.known, false); eq(info.browse.price, 80); eq(info.browse.stale, true)
    record, info = ns.Lookup(db, scan.scope, "123:2", 4200); eq(info.browse, nil)
    record, info = ns.Lookup(db, "OtherRealm", "123:-2", 4200); eq(info.browse, nil)
    assert(ns.SaveBrowsePrice(db, scan.scope, group, 250, 4200, 22, {}))
    record, info = ns.Lookup(db, scan.scope, identity(link), 4200)
    eq(info.browse.price, 250); eq(info.browse.maxLevel, 22); eq(info.browse.age, 0)
end)

test("invalid browse rows and pets cannot overwrite a saved minimum", function()
    local db, group = {}, { itemID = 420, itemSuffix = 0, battlePetSpeciesID = 0 }
    assert(ns.SaveBrowsePrice(db, "realm", group, 321, 100, 6))
    for _, bad in ipairs({ 0, -1, math.huge, 0.5, secret() }) do
        eq(ns.SaveBrowsePrice(db, "realm", group, bad, 100, 6), false)
    end
    for _, bad in ipairs({ secret(), setmetatable({}, { __index = function() error("restricted field") end }),
        { itemID = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
        { itemID = 420, itemSuffix = secret(), battlePetSpeciesID = 0 },
        { itemID = 420, itemSuffix = 0, battlePetSpeciesID = 12 } }) do
        eq(ns.SaveBrowsePrice(db, "realm", bad, 1, 100, 6), false)
    end
    local _, info = ns.Lookup(db, "realm", "420:0", 100)
    eq(info.browse.price, 321)
    db.scopes.realm.browsePrices["420:0"].maxLevel = "invalid"
    _, info = ns.Lookup(db, "realm", "420:0", 100); eq(info.browse, nil)
end)

test("money and ages use readable safe display values", function()
    eq(ns.FormatMoney(10000), "1g 00s 00c"); eq(ns.FormatMoney(105), "1s 05c")
    eq(ns.FormatMoney(5), "5c"); eq(ns.FormatMoney(0), "0c")
    eq(ns.FormatMoney(secret()), "?"); eq(ns.FormatMoney(-1), "?")
    eq(ns.FormatAge(59), "just now"); eq(ns.FormatAge(60), "1m ago")
    eq(ns.FormatAge(3600), "1h ago"); eq(ns.FormatAge(86400), "1d ago")
    eq(ns.FormatAge(secret()), "unknown age")
end)

test("stack buyout estimates multiply the raw unit range before rounding", function()
    local scan = snapshot()
    ns.AddListing(scan, "item:123", 3, 1)
    ns.AddListing(scan, "item:123", 20, 100000)
    local record = scan.items[identity("item:123")]
    local label, amount = ns.StackQuote(record, { browse = { price = 9 } }, 3, false, true)
    eq(label, "Stack of 3 (buyout est.)"); eq(amount, "1c - 1g 50s 00c")
    label, amount = ns.StackQuote({ min = 5000, max = 5000 }, {}, 20, true)
    eq(label, "Full stack of 20 (buyout est.)"); eq(amount, "10g 00s 00c")
end)

test("a browse stack estimate needs a confirmed commodity and a valid quantity", function()
    local info = { browse = { price = 250 } }
    local label, value = ns.StackQuote(nil, info, 7, false, true)
    eq(label, "Stack of 7 (browse est.)"); eq(value, "17s 50c")
    eq(ns.StackQuote(nil, info, 7, false, false), nil)
    eq(ns.StackQuote(nil, info, 7), nil)
    eq(ns.StackQuote(nil, {}, 7, false, true), nil)
    for _, count in ipairs({ 1, 0, -1, 2.5, secret(), math.huge }) do
        eq(ns.StackQuote(nil, info, count, false, true), nil)
    end
    eq(ns.StackQuote({ min = 1, max = 9007199254740991 }, {}, 2), nil)
end)

print("AUCTION MODEL PASS: " .. passed .. " cases")
