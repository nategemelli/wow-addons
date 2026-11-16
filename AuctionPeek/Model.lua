local _, ns = ...

local MAX_EXACT_INTEGER = 9007199254740991
ns.FRESH_SECONDS = 30 * 60

function ns.Readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

function ns.Number(value)
    if not ns.Readable(value) or type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

function ns.Text(value)
    if ns.Readable(value) and type(value) == "string" and value ~= "" then return value end
end

local function Integer(value, minimum)
    value = ns.Number(value)
    if value and value >= (minimum or 0) and value <= MAX_EXACT_INTEGER and value % 1 == 0 then return value end
end

local function FieldNumber(value)
    if value == nil or value == "" then return 0 end
    if not value:match("^%-?%d+$") then return nil end
    local number = tonumber(value)
    if number and math.abs(number) <= MAX_EXACT_INTEGER and number % 1 == 0 then return number end
end

-- The auction market identifies the item and its intrinsic variant. Enchants,
-- gems, unique instance IDs, viewer level and specialization are not a market.
-- Preserve bonus/context/modifier data so differently scaled items never share
-- a quote merely because their base item ID matches.
function ns.ItemIdentity(link)
    link = ns.Text(link)
    if not link or #link > 4096 then return nil end
    local item = link:match("|H(item:[^|]+)|h") or link:match("^(item:[%d:%-]*)$")
    if not item then return nil end
    local fields = {}
    for field in (item:sub(6) .. ":"):gmatch("(.-):") do
        fields[#fields + 1] = field
        if #fields > 128 or FieldNumber(field) == nil then return nil end
    end
    local itemID = Integer(FieldNumber(fields[1]), 1)
    if not itemID then return nil end
    local suffix = FieldNumber(fields[7])
    local key = string.format("%d:%d", itemID, suffix)
    local bonusCount = Integer(FieldNumber(fields[13]), 0)
    if not bonusCount or bonusCount > 100 or (bonusCount > 0 and #fields < 13 + bonusCount) then return nil end
    local bonuses = {}
    for index = 14, 13 + bonusCount do
        local bonus = Integer(FieldNumber(fields[index]), 1)
        if not bonus then return nil end
        bonuses[#bonuses + 1] = bonus
    end
    if #bonuses > 0 then
        table.sort(bonuses)
        local text = {}
        for _, value in ipairs(bonuses) do text[#text + 1] = string.format("%d", value) end
        key = key .. ":b" .. table.concat(text, ",")
    end
    local context = FieldNumber(fields[12])
    if context ~= 0 then key = key .. ":c" .. string.format("%d", context) end
    local modifierMask = FieldNumber(fields[11])
    if modifierMask ~= 0 then key = key .. ":m" .. string.format("%d", modifierMask) end
    -- A trailing all-zero extension is equivalent to an omitted extension.
    local last = #fields
    while last > 13 + bonusCount and FieldNumber(fields[last]) == 0 do last = last - 1 end
    if last > 13 + bonusCount then
        local tail = {}
        for index = 14 + bonusCount, last do tail[#tail + 1] = string.format("%d", FieldNumber(fields[index])) end
        key = key .. ":x" .. table.concat(tail, ",")
    end
    return key, itemID
end

function ns.NewSnapshot(scope, now, source)
    return { scope = ns.Text(scope), updatedAt = Integer(now, 0) or 0,
        source = ns.Text(source) or "Auction scan", items = {}, rows = 0,
        bidOnly = 0, omitted = 0, incomplete = false }
end

local function EmptyRecord(now, source, complete)
    return { listingCount = 0, units = 0, updatedAt = now, complete = complete,
        source = source, empty = true }
end

function ns.AddListing(snapshot, link, quantity, totalBuyout)
    local key, itemID = ns.ItemIdentity(link)
    quantity = Integer(quantity, 1)
    totalBuyout = Integer(totalBuyout, 0)
    snapshot.rows = snapshot.rows + 1
    if not key or not quantity or not totalBuyout then
        snapshot.omitted = snapshot.omitted + 1
        snapshot.incomplete = true
        return false
    end
    -- Only the exact requested variant belongs to a targeted quote. Name
    -- searches can return other items or suffixes; those are not zero quotes.
    if snapshot.targetKey and key ~= snapshot.targetKey then return true end
    local record = snapshot.items[key]
    if not record then
        record = EmptyRecord(snapshot.updatedAt, snapshot.source, false)
        record.itemID = itemID
        snapshot.items[key] = record
    end
    if totalBuyout == 0 then
        snapshot.bidOnly = snapshot.bidOnly + 1
        return true
    end
    local unitPrice = totalBuyout / quantity
    record.min = record.min and math.min(record.min, unitPrice) or unitPrice
    record.max = record.max and math.max(record.max, unitPrice) or unitPrice
    record.listingCount = record.listingCount + 1
    record.units = record.units + quantity
    record.empty = false
    return true
end

local function CopyRecord(record, complete)
    return { min = record.min, max = record.max, itemID = record.itemID,
        listingCount = record.listingCount, units = record.units, updatedAt = record.updatedAt,
        source = record.source, empty = record.empty, complete = complete }
end

local function EnsureMarket(db, scope)
    if type(db.scopes) ~= "table" then db.scopes = {} end
    local market = db.scopes[scope]
    if type(market) ~= "table" then market = {}; db.scopes[scope] = market end
    return market
end

-- Browse prices cover the same base item and suffix across levels and bonuses.
-- Keep them separate from the buyout range calculated for a particular link.
local function BrowseKeyFields(itemKey)
    return itemKey.itemID, itemKey.itemSuffix, itemKey.battlePetSpeciesID
end

function ns.SaveBrowsePrice(db, scope, itemKey, price, timestamp, maxLevel, seen)
    scope, price = ns.Text(scope), Integer(price, 1)
    timestamp, maxLevel = Integer(timestamp, 0), Integer(maxLevel, 1)
    if type(db) ~= "table" or not scope or not price or not timestamp or not maxLevel then return false end
    if not ns.Readable(itemKey) or type(itemKey) ~= "table" then return false end
    local ok, itemID, suffix, species = pcall(BrowseKeyFields, itemKey)
    if not ok or Integer(species) ~= 0 then return false end
    itemID, suffix = Integer(itemID, 1), Integer(suffix, -MAX_EXACT_INTEGER)
    if not itemID or not suffix then return false end
    local group = string.format("%d:%d", itemID, suffix)
    if seen then
        if seen[group] and seen[group] <= price then return true end
        seen[group] = price
    end
    local market = EnsureMarket(db, scope)
    if type(market.browsePrices) ~= "table" then market.browsePrices = {} end
    market.browsePrices[group] = { price = price, updatedAt = timestamp, maxLevel = maxLevel }
    return true
end

function ns.Commit(db, scope, snapshot, complete, replaceAll)
    scope = ns.Text(scope)
    if type(db) ~= "table" or not scope or type(snapshot) ~= "table" or snapshot.scope ~= scope then return false end
    if type(snapshot.items) ~= "table" then return false end
    complete = complete == true and snapshot.incomplete ~= true
    local market = EnsureMarket(db, scope)
    if type(market.items) ~= "table" or (replaceAll and complete) then market.items = {} end
    for key, record in pairs(snapshot.items) do market.items[key] = CopyRecord(record, complete) end
    if snapshot.targetKey and complete and not snapshot.items[snapshot.targetKey] then
        market.items[snapshot.targetKey] = EmptyRecord(snapshot.updatedAt, snapshot.source, true)
    end
    if replaceAll and complete then
        market.fullScanAt, market.fullScanSource = snapshot.updatedAt, snapshot.source
    end
    market.lastScanAt, market.lastScanComplete = snapshot.updatedAt, complete
    market.lastScanRows, market.lastScanOmitted = snapshot.rows, snapshot.omitted
    return true, complete
end

local function RecordValid(record)
    if type(record) ~= "table" or not Integer(record.updatedAt, 0) then return false end
    if not Integer(record.listingCount, 0) or not Integer(record.units, 0) then return false end
    if record.empty == true then return record.min == nil and record.max == nil end
    local minimum, maximum = ns.Number(record.min), ns.Number(record.max)
    return minimum ~= nil and maximum ~= nil and minimum > 0 and maximum >= minimum
        and minimum <= MAX_EXACT_INTEGER and maximum <= MAX_EXACT_INTEGER
end

local function SetAge(info, timestamp, now)
    if now then
        info.age = math.max(0, now - timestamp)
        info.clockSkew = timestamp > now
    end
    info.stale = info.age == nil or info.age > ns.FRESH_SECONDS or info.clockSkew == true
end

function ns.Lookup(db, scope, key, now)
    local info = { known = false, empty = false, complete = false, stale = false }
    if type(db) ~= "table" or type(db.scopes) ~= "table" or not ns.Text(scope) or not ns.Text(key) then return nil, info end
    local market = db.scopes[scope]
    if type(market) ~= "table" then return nil, info end
    now = Integer(now, 0)
    if type(market.browsePrices) == "table" then
        local group = key:match("^%d+:%-?%d+")
        local browse = market.browsePrices[group]
        if type(browse) == "table" and Integer(browse.price, 1) and Integer(browse.updatedAt, 0) and Integer(browse.maxLevel, 1) then
            info.browse = { price = browse.price, maxLevel = browse.maxLevel }
            SetAge(info.browse, browse.updatedAt, now)
        end
    end
    local record = type(market.items) == "table" and market.items[key] or nil
    if record ~= nil and not RecordValid(record) then return nil, info end
    if record == nil then
        local fullScanAt = Integer(market.fullScanAt, 0)
        if not fullScanAt then return nil, info end
        record = EmptyRecord(fullScanAt, market.fullScanSource or "Full scan", true)
    end
    info.known, info.empty = true, record.empty == true
    info.complete, info.source = record.complete == true, record.source
    SetAge(info, record.updatedAt, now)
    return record, info
end

function ns.FormatMoney(copper)
    copper = ns.Number(copper)
    if not copper or copper < 0 or copper > MAX_EXACT_INTEGER then return "?" end
    if copper > 0 and copper < 1 then return "<1c" end
    local approximation = copper % 1 ~= 0 and "~" or ""
    if approximation ~= "" then copper = math.floor(copper + 0.5) end
    local gold, silver = math.floor(copper / 10000), math.floor(copper / 100) % 100
    local coins = copper % 100
    if gold > 0 then return approximation .. string.format("%dg %02ds %02dc", gold, silver, coins) end
    if silver > 0 then return approximation .. string.format("%ds %02dc", silver, coins) end
    return approximation .. string.format("%dc", coins)
end

function ns.StackQuote(record, info, count, isFullStack, isCommodity)
    count = Integer(count, 2)
    if not count then return end
    local minimum = record and ns.Number(record.min)
    local maximum = record and ns.Number(record.max)
    local basis = "buyout est."
    if not minimum or not maximum or minimum <= 0 or maximum < minimum then
        if isCommodity ~= true or not info or not info.browse then return end
        -- A commodity browse row exposes its lowest unit price. The amount
        -- available at that price is only known after an item search.
        minimum = Integer(info.browse.price, 1)
        if not minimum then return end
        maximum, basis = minimum, "browse est."
    end
    if maximum * count > MAX_EXACT_INTEGER then return end
    local label = string.format("%s of %d (%s)", isFullStack and "Full stack" or "Stack", count, basis)
    -- Keep fractional copper until after multiplication (e.g. 1c for 3).
    local total = ns.FormatMoney(minimum * count)
    if maximum > minimum then total = total .. " - " .. ns.FormatMoney(maximum * count) end
    return label, total
end

function ns.FormatAge(seconds)
    seconds = ns.Number(seconds)
    if not seconds or seconds < 0 then return "unknown age" end
    if seconds < 60 then return "just now" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m ago" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h ago" end
    return math.floor(seconds / 86400) .. "d ago"
end

function ns.FormatBrowseDetails(browse)
    return string.format("Through level %d, across item levels and bonuses. Cached %s%s", browse.maxLevel,
        ns.FormatAge(browse.age), browse.stale and " - stale" or "")
end
