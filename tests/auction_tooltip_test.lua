-- These mocks exercise real tooltip wiring without rebuilding or replacing
-- native tooltip contents. No auction/network operation is available here.
local passed = 0
local function test(name, fn)
    local ok, message = pcall(fn)
    if not ok then error("FAIL: " .. name .. ": " .. tostring(message)) end
    passed = passed + 1
end
local function eq(actual, expected)
    if actual ~= expected then error("expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end
local secrets = setmetatable({}, { __mode = "k" })
local function secret()
    local value = setmetatable({}, { __tostring = function() error("secret inspected") end })
    secrets[value] = true
    return value
end
issecretvalue = function(value) return secrets[value] == true end
local ns, processor, hookCount, hovered, lookupCount, enabled, cache, modern, lastStack
local function tooltip(name, link)
    local self = { name = name, link = link, lines = { "Native item heading" }, hooks = {}, clears = 0, shows = 0 }
    function self:GetName() return self.name end
    function self:GetItem() return "An item", self.link end
    function self:IsForbidden() return self.forbidden end
    function self:NumLines() return #self.lines end
    function self:AddLine(text) self.lines[#self.lines + 1] = text end
    function self:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " = " .. right end
    function self:Show() self.shows = self.shows + 1 end
    function self:HookScript(event, fn)
        if self.rejectScripts then error("unsupported script") end
        self.hooks[event] = self.hooks[event] or {}
        self.hooks[event][#self.hooks[event] + 1] = fn
    end
    function self:Fire(event)
        for _, fn in ipairs(self.hooks[event] or {}) do fn(self) end
    end
    function self:ClearLines()
        self.lines = {}
        self.clears = self.clears + 1
        self:Fire("OnTooltipCleared")
    end
    function self:Rebuild(link)
        self:ClearLines()
        self.link = link or self.link
        self.lines[1] = "Native rebuilt heading"
    end
    function self:SetScript() error("must never replace native tooltip scripts") end
    function self:SetHyperlink() error("must never replace native tooltip content") end
    return self
end
local function has(tip, fragment)
    for _, line in ipairs(tip.lines) do if line:find(fragment, 1, true) then return true end end
    return false
end
local function emit(tip)
    if modern then processor(tip, { id = 999 }) else tip:Fire("OnTooltipSetItem") end
end
local function install(isModern)
    modern, hookCount, hovered, lookupCount, enabled, cache = isModern, 0, {}, 0, true, {}
    TooltipUtil = nil
    C_Item, C_Container, C_AuctionHouse, C_MerchantFrame = nil, nil, nil, nil
    GetContainerItemInfo, GetMerchantItemLink, GetItemInfo = nil, nil, nil
    Enum = { TooltipDataType = { Item = 2 } }
    TooltipDataProcessor = isModern and { AddTooltipPostCall = function(kind, fn)
        eq(kind, 2); hookCount = hookCount + 1; processor = fn
    end } or nil
    hooksecurefunc = function(object, method, fn)
        local original = object[method]
        object[method] = function(self, ...)
            local result = original(self, ...)
            fn(self, ...)
            return result
        end
    end
    GameTooltip = tooltip("GameTooltip", "item:100:0:0:0:0:0:7")
    ItemRefTooltip = tooltip("ItemRefTooltip", "item:101")
    ShoppingTooltip1 = tooltip("ShoppingTooltip1", "item:102")
    ShoppingTooltip2, ItemRefShoppingTooltip1, ItemRefShoppingTooltip2 = nil, nil, nil
    ns = {}
    assert(loadfile(TEST_ROOT .. "/AuctionPeek/Model.lua"))("AuctionPeek", ns)
    assert(loadfile(TEST_ROOT .. "/AuctionPeek/ReagentData.lua"))("AuctionPeek", ns)
    ns.FormatMoney = function(value) return string.format("%.0fc", value) end
    ns.FormatAge = function(value) return string.format("%.0fs ago", value) end
    assert(loadfile(TEST_ROOT .. "/AuctionPeek/Tooltip.lua"))("AuctionPeek", ns)
    local callbacks = {
        lookup = function(link) lookupCount = lookupCount + 1; local entry = cache[link]; return entry and entry.record, entry and entry.info or { known = false } end,
        hovered = function(link, count, full, commodity)
            hovered[#hovered + 1] = link
            lastStack = { count = count, full = full, commodity = commodity }
        end,
        enabled = function() return enabled end,
    }
    local ok, mode = ns.InstallTooltipHooks(callbacks)
    eq(ok, true); eq(mode, isModern and "modern" or "legacy")
    return callbacks
end
local function priced(tip, complete, stale)
    cache[tip.link] = {
        record = { min = 120, max = 900, listingCount = 4, units = 30 },
        info = { known = true, complete = complete, age = stale and 4000 or 10, stale = stale, source = "Auction snapshot" },
    }
end

test("modern processor is installed once and leaves native tooltip intact", function()
    local callbacks = install(true)
    ns.InstallTooltipHooks(callbacks); eq(hookCount, 1)
    priced(GameTooltip, true, false); emit(GameTooltip)
    eq(GameTooltip.lines[1], "Native item heading"); eq(GameTooltip.clears, 0); eq(GameTooltip.shows, 0)
    assert(has(GameTooltip, "Min buyout = 120c")); assert(has(GameTooltip, "Max buyout = 900c"))
    assert(has(GameTooltip, "Cached 10s ago")); assert(has(GameTooltip, "4 listings / 30 items"))
    eq(hovered[1], GameTooltip.link)
end)

test("repeated processing does not duplicate price lines or repeat lookup", function()
    local lines, count = #GameTooltip.lines, lookupCount
    emit(GameTooltip); emit(GameTooltip)
    eq(#GameTooltip.lines, lines); eq(lookupCount, count)
end)

test("cleared tooltip is priced again even for the same item", function()
    local count = lookupCount
    GameTooltip:Rebuild(); emit(GameTooltip)
    eq(lookupCount, count + 1); assert(has(GameTooltip, "Min buyout = 120c"))
    eq(GameTooltip.lines[1], "Native rebuilt heading")
end)

test("switching items uses full variant link and discards old display", function()
    GameTooltip:Rebuild("item:100:0:0:0:0:0:8"); emit(GameTooltip)
    eq(hovered[#hovered], "item:100:0:0:0:0:0:8")
    assert(has(GameTooltip, "No cached prices")); assert(not has(GameTooltip, "120c"))
end)

test("partial results have observed labels and an explicit limitation", function()
    GameTooltip:Rebuild(); priced(GameTooltip, false, false); emit(GameTooltip)
    assert(has(GameTooltip, "Observed min = 120c")); assert(has(GameTooltip, "Observed max = 900c"))
    assert(has(GameTooltip, "Partial results")); assert(not has(GameTooltip, "Min buyout ="))
end)

test("stale cached prices remain visible with age and stale label", function()
    GameTooltip:Rebuild(); priced(GameTooltip, true, true); emit(GameTooltip)
    assert(has(GameTooltip, "Cached 4000s ago - stale")); assert(has(GameTooltip, "120c"))
end)

test("complete empty snapshot differs from never-scanned and partial empty", function()
    GameTooltip:Rebuild()
    cache[GameTooltip.link] = { record = { empty = true }, info = { known = true, empty = true, complete = true, age = 20 } }
    emit(GameTooltip); assert(has(GameTooltip, "No buyout listings in this snapshot.")); assert(not has(GameTooltip, "No cached prices"))
    GameTooltip:Rebuild(); cache[GameTooltip.link].info.complete = false; emit(GameTooltip)
    assert(has(GameTooltip, "No buyouts in the loaded results.")); assert(has(GameTooltip, "Partial results"))
end)

test("comparison tooltips display prices without replacing hovered target", function()
    local before = #hovered
    priced(ShoppingTooltip1, true, false); emit(ShoppingTooltip1)
    eq(#hovered, before); assert(has(ShoppingTooltip1, "Min buyout"))
end)

test("disabled display leaves tooltip alone while remembering hover", function()
    enabled = false; GameTooltip:Rebuild(); local count = lookupCount
    local before = #hovered; emit(GameTooltip)
    eq(#GameTooltip.lines, 1); eq(lookupCount, count); eq(#hovered, before + 1)
    enabled = true
end)

test("secret links and forbidden tooltips are not inspected or priced", function()
    local count, before = lookupCount, #hovered
    GameTooltip:Rebuild(); GameTooltip.link = secret(); emit(GameTooltip)
    eq(#GameTooltip.lines, 1); eq(lookupCount, count); eq(#hovered, before)
    GameTooltip.link, GameTooltip.forbidden = "item:100", true; emit(GameTooltip)
    eq(lookupCount, count); eq(ns.tooltipFailures, nil)
end)

test("modern link helper supports tooltips without GetItem and never uses data id", function()
    install(true); GameTooltip.GetItem = nil
    TooltipUtil = { GetDisplayedItem = function() return "An item", "item:777:0:0:0:0:0:12", 777 end }
    emit(GameTooltip); eq(hovered[1], "item:777:0:0:0:0:0:12")
    GameTooltip:Rebuild(); TooltipUtil.GetDisplayedItem = function() return nil end
    local count = lookupCount; emit(GameTooltip); eq(lookupCount, count); eq(#GameTooltip.lines, 1)
end)

test("legacy scripts are appended once for stock and comparison tooltips", function()
    local callbacks = install(false)
    ns.InstallTooltipHooks(callbacks)
    eq(#GameTooltip.hooks.OnTooltipSetItem, 1); eq(#ItemRefTooltip.hooks.OnTooltipSetItem, 1)
    priced(GameTooltip, true, false); emit(GameTooltip); assert(has(GameTooltip, "Min buyout"))
    local count = #GameTooltip.lines; emit(GameTooltip); eq(#GameTooltip.lines, count)
    GameTooltip:Rebuild(); emit(GameTooltip); assert(has(GameTooltip, "Min buyout"))
end)

test("secure ClearLines fallback resets dedup when old clear script is absent", function()
    install(true); GameTooltip.rejectScripts = true
    priced(GameTooltip, true, false); emit(GameTooltip)
    local count = lookupCount; GameTooltip:Rebuild(); emit(GameTooltip)
    eq(lookupCount, count + 1); assert(has(GameTooltip, "Min buyout"))
end)

test("browse price appears independently with level cap and exact buyouts retain their own age", function()
    install(true)
    local browse = { price = 30, maxLevel = 12, age = 2000, stale = true }
    cache[GameTooltip.link] = { info = { known = false, browse = browse } }
    emit(GameTooltip)
    assert(has(GameTooltip, "Browse minimum (item and suffix) = 30c"))
    assert(has(GameTooltip, "Through level 12")); assert(has(GameTooltip, "2000s ago - stale"))
    assert(not has(GameTooltip, "No cached prices")); assert(not has(GameTooltip, "Min buyout"))
    GameTooltip:Rebuild(); priced(GameTooltip, true, false)
    cache[GameTooltip.link].info.browse = browse
    emit(GameTooltip)
    assert(has(GameTooltip, "Min buyout = 120c")); assert(has(GameTooltip, "Max buyout = 900c"))
    assert(has(GameTooltip, "Browse minimum (item and suffix) = 30c")); assert(has(GameTooltip, "Cached 10s ago"))
end)

test("failed lookup never propagates an error into native processing", function()
    local callbacks = install(true)
    callbacks.lookup = function() error("fixture unavailable") end
    emit(GameTooltip); eq(ns.tooltipFailures, 1); eq(#GameTooltip.lines, 1)
end)

test("primary GUID prices the actual hovered quantity and ignores appended items", function()
    install(true); priced(GameTooltip, true, false)
    local location, count = {}, 7
    GameTooltip.GetPrimaryTooltipData = function() return { guid = "primary" } end
    C_Item = {
        GetItemLocation = function(guid) eq(guid, "primary"); return location end,
        GetStackCount = function(loc) eq(loc, location); return count end,
        GetItemMaxStackSizeByID = function() return 20 end,
    }
    Enum.ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 }
    C_AuctionHouse = { GetItemCommodityStatus = function(loc) eq(loc, location); return 2 end }
    cache[GameTooltip.link].info.browse = { price = 25, maxLevel = 12, age = 20 }
    processor(GameTooltip, { guid = "secondary" })
    eq(lastStack.count, 7); eq(lastStack.full, false); eq(lastStack.commodity, true)
    assert(has(GameTooltip, "Stack of 7 (buyout est.) = 840c - 6300c"))
    assert(has(GameTooltip, "Min buyout = 120c"))
    for i, line in ipairs(GameTooltip.lines) do
        if line == "Max buyout = 900c" then eq(GameTooltip.lines[i + 1], "Stack of 7 (buyout est.) = 840c - 6300c") end
    end
    local lines = #GameTooltip.lines
    emit(GameTooltip); eq(#GameTooltip.lines, lines)
    count = 3; GameTooltip:Rebuild(); emit(GameTooltip)
    eq(lastStack.count, 3); assert(has(GameTooltip, "Stack of 3 (buyout est.) = 360c - 2700c"))
    assert(not has(GameTooltip, "Stack of 7"))
    count = 1; GameTooltip:Rebuild(); emit(GameTooltip)
    eq(lastStack.full, true); assert(has(GameTooltip, "Full stack of 20 (buyout est.) = 2400c - 18000c"))
end)

test("bag slot quantity is matched against the hovered variant", function()
    install(true); priced(GameTooltip, true, false)
    GameTooltip.GetPrimaryTooltipInfo = function() return { getterName = "GetBagItem", getterArgs = { 0, 3 } } end
    local entry = { hyperlink = GameTooltip.link, stackCount = 5 }
    C_Container = { GetContainerItemInfo = function(bag, slot) eq(bag, 0); eq(slot, 3); return entry end }
    C_Item = { GetItemMaxStackSizeByID = function() return 20 end }
    emit(GameTooltip); eq(lastStack.count, 5); eq(lastStack.full, false)
    entry.hyperlink = "item:100"; GameTooltip:Rebuild(); emit(GameTooltip)
    eq(lastStack.count, 20); eq(lastStack.full, true)
end)

test("legacy bag owner supplies a stack only on the matching slot", function()
    install(false); priced(GameTooltip, false, false)
    GameTooltip.GetOwner = function()
        return { GetBagID = function() return -1 end, GetID = function() return 8 end }
    end
    GetContainerItemInfo = function(bag, slot)
        eq(bag, -1); eq(slot, 8); return 123, 4, false, 0, false, false, GameTooltip.link
    end
    emit(GameTooltip); eq(lastStack.count, 4); eq(lastStack.full, false)
    assert(has(GameTooltip, "Stack of 4 (buyout est.) = 480c - 3600c"))
end)

test("merchant tooltip uses the bundle size of the displayed item", function()
    install(true); priced(GameTooltip, true, false)
    GameTooltip.GetPrimaryTooltipInfo = function() return { getterName = "GetMerchantItem", getterArgs = { 2 } } end
    C_MerchantFrame = { GetItemInfo = function(index) eq(index, 2); return { stackCount = 5, numAvailable = 200 } end }
    GetMerchantItemLink = function(index) eq(index, 2); return GameTooltip.link end
    emit(GameTooltip); eq(lastStack.count, 5); eq(lastStack.full, false)
    assert(has(GameTooltip, "Stack of 5 (buyout est.) = 600c - 4500c"))
end)

test("chat links can show a full commodity stack from a grouped browse price", function()
    install(true)
    local browse = { price = 30, maxLevel = 12, age = 20 }
    cache[ItemRefTooltip.link] = { info = { known = false, browse = browse } }
    GetItemInfo = function(link) eq(link, ItemRefTooltip.link); return "Herb", link, 0, 0, 0, "", "", 20 end
    local commodity = true
    C_AuctionHouse = {
        MakeItemKey = function(id) eq(id, 101); return { itemID = id } end,
        GetItemKeyInfo = function() return { isCommodity = commodity } end,
    }
    emit(ItemRefTooltip); eq(lastStack.count, 20); eq(lastStack.full, true)
    assert(has(ItemRefTooltip, "Browse minimum per item = 30c"))
    assert(has(ItemRefTooltip, "Full stack of 20 (browse est.) = 600c"))
    commodity = false; ItemRefTooltip:Rebuild(); emit(ItemRefTooltip)
    assert(has(ItemRefTooltip, "Browse minimum (item and suffix) = 30c")); assert(not has(ItemRefTooltip, "Full stack"))
end)

test("invalid and restricted counts cannot create a stack estimate", function()
    install(true); priced(GameTooltip, true, false)
    local entry = { hyperlink = GameTooltip.link, stackCount = secret() }
    C_Container = { GetContainerItemInfo = function() return entry end }
    GameTooltip.GetPrimaryTooltipInfo = function() return { getterName = "GetBagItem", getterArgs = { 0, 1 } } end
    C_Item = { GetItemMaxStackSizeByID = function() return 1 end }
    emit(GameTooltip); eq(lastStack.count, nil); assert(not has(GameTooltip, "stack of")); eq(ns.tooltipFailures, nil)
    entry.stackCount = 2.5; GameTooltip:Rebuild(); emit(GameTooltip)
    eq(lastStack.count, nil); assert(has(GameTooltip, "Max buyout")); eq(ns.tooltipFailures, nil)
end)

test("crafting uses show concrete recipes for each profession before uncached prices", function()
    install(true)
    -- Use a full link with a suffix to exercise base-item lookup.
    GameTooltip:Rebuild("|cffffffff|Hitem:2589:0:0:0:0:0:7|h[Linen Cloth]|h|r")
    emit(GameTooltip)
    local rows = assert(ns.reagentUses[2589])
    local headings, professions, headingIndex, priceIndex = 0, {}, nil, nil
    for index, line in ipairs(GameTooltip.lines) do
        if line:find("Crafting uses", 1, true) then headings, headingIndex = headings + 1, index end
        if line:find("No cached prices", 1, true) then priceIndex = index end
        for _, use in ipairs(rows) do
            if line:find(use.profession, 1, true) then
                eq(professions[use.profession], nil)
                professions[use.profession] = index
                for _, recipe in ipairs(use.examples) do assert(line:find(recipe, 1, true)) end
                local remaining = use.total - #use.examples
                if remaining > 0 then assert(line:find(tostring(remaining) .. " more", 1, true)) end
            end
        end
    end
    eq(headings, 1)
    for _, use in ipairs(rows) do
        local index = assert(professions[use.profession])
        assert(headingIndex < index and index < priceIndex)
    end
    assert(professions["First Aid"] and professions["Tailoring"])
    assert(has(GameTooltip, "Linen Bandage"))
    assert(has(GameTooltip, "Bolt of Linen Cloth"))
    local lines = #GameTooltip.lines; emit(GameTooltip)
    eq(#GameTooltip.lines, lines); eq(lookupCount, 1)
end)

test("legacy tooltips keep crafting uses when pricing is off and clear them for other items", function()
    install(false); enabled = false
    GameTooltip:Rebuild("item:2835"); emit(GameTooltip) -- Rough Stone
    assert(has(GameTooltip, "Crafting uses"))
    assert(has(GameTooltip, "Blacksmithing")); assert(has(GameTooltip, "Engineering"))
    eq(has(GameTooltip, "No cached prices"), false); eq(lookupCount, 0)
    local lineCount = #GameTooltip.lines; emit(GameTooltip); eq(#GameTooltip.lines, lineCount)
    GameTooltip:Rebuild("item:99999999"); emit(GameTooltip)
    eq(#GameTooltip.lines, 1); eq(hovered[#hovered], GameTooltip.link); eq(lookupCount, 0)
end)

test("Rogue Poisons is included alongside other uses for Fadeleaf", function()
    install(true); GameTooltip:Rebuild("item:3818")
    priced(GameTooltip, true, false); emit(GameTooltip)
    assert(has(GameTooltip, "Rogue Poisons")); assert(has(GameTooltip, "Blinding Powder"))
    assert(has(GameTooltip, "Alchemy")); assert(has(GameTooltip, "Min buyout"))
end)

test("price lookup failure preserves one copy of reagent uses", function()
    local callbacks = install(true)
    callbacks.lookup = function() error("unavailable price cache") end
    GameTooltip:Rebuild("item:2835"); emit(GameTooltip)
    assert(has(GameTooltip, "Crafting uses")); assert(has(GameTooltip, "Engineering"))
    local count = #GameTooltip.lines
    emit(GameTooltip); eq(#GameTooltip.lines, count); eq(ns.tooltipFailures, 1)
end)

test("catalog groups have distinct professions and nonempty named recipe examples", function()
    install(true)
    for itemID, uses in pairs(ns.reagentUses) do
        assert(type(itemID) == "number" and itemID > 0 and itemID % 1 == 0)
        assert(#uses > 0)
        local professions = {}
        for _, use in ipairs(uses) do
            assert(type(use.profession) == "string" and use.profession ~= "")
            eq(professions[use.profession], nil)
            professions[use.profession] = true
            assert(#use.examples >= 1 and #use.examples <= 2 and use.total >= #use.examples and use.total % 1 == 0)
            assert(use.examples[1] ~= use.examples[2])
            for _, recipe in ipairs(use.examples) do assert(type(recipe) == "string" and recipe ~= "") end
        end
    end
end)

test("no supported tooltip path is reported without replacing scripts", function()
    install(false)
    GameTooltip, ItemRefTooltip, ShoppingTooltip1 = nil, nil, nil
    local fresh = { Readable = ns.Readable }
    assert(loadfile(TEST_ROOT .. "/AuctionPeek/Tooltip.lua"))("AuctionPeek", fresh)
    local ok, reason = fresh.InstallTooltipHooks({})
    eq(ok, false); assert(reason:find("No supported", 1, true))
end)

print("AUCTION TOOLTIP PASS: " .. passed .. " mocked-client cases")
