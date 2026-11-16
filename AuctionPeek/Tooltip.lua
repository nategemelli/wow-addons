local _, ns = ...

local callbacks = {}
local installedMode
local marks = setmetatable({}, { __mode = "k" })
local resetHooked = setmetatable({}, { __mode = "k" })
local legacyHooked = setmetatable({}, { __mode = "k" })

local function Field(value, key)
    if not ns.Readable(value) or value == nil then return nil end
    local ok, result = pcall(function() return value[key] end)
    if ok then return result end
end

local function Query(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h end
end

local function Call(object, method, ...)
    local fn = Field(object, method)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, object, ...)
    if ok then return a, b end
end

local function SafeText(value)
    local text = ns.Text(value)
    return text and text:gsub("|", "||") or nil
end

local function Reset(tooltip)
    marks[tooltip] = nil
end

local function WatchClear(tooltip)
    if resetHooked[tooltip] then return end
    local hook = Field(tooltip, "HookScript")
    if type(hook) == "function" then
        local ok = pcall(hook, tooltip, "OnTooltipCleared", Reset)
        if ok then resetHooked[tooltip] = true; return end
    end
    -- Some data-based tooltips do not expose the old script. A secure post-
    -- hook retains the original ClearLines implementation and its handlers.
    if type(hooksecurefunc) == "function" and type(Field(tooltip, "ClearLines")) == "function" then
        local ok = pcall(hooksecurefunc, tooltip, "ClearLines", Reset)
        if ok then resetHooked[tooltip] = true end
    end
end

local function ItemLink(tooltip)
    local _, link = Call(tooltip, "GetItem")
    link = ns.Text(link)
    if not link and TooltipUtil and type(TooltipUtil.GetDisplayedItem) == "function" then
        local ok, _, displayed = pcall(TooltipUtil.GetDisplayedItem, tooltip)
        if ok then link = ns.Text(displayed) end
    end
    -- A bare item ID would discard suffixes and bonus variants. Wait for the
    -- client's full link rather than borrowing another item's price range.
    local key, itemID = ns.ItemIdentity(link)
    if key then return link, key, itemID end
end

local function IsComparison(tooltip)
    if tooltip == ShoppingTooltip1 or tooltip == ShoppingTooltip2
        or tooltip == ItemRefShoppingTooltip1 or tooltip == ItemRefShoppingTooltip2 then return true end
    local name = ns.Text(Call(tooltip, "GetName"))
    return name and name:find("ShoppingTooltip", 1, true) ~= nil
end

local function Count(value)
    value = ns.Number(value)
    if value and value >= 1 and value <= 9007199254740991 and value % 1 == 0 then return value end
end

local function BagCount(bag, slot, key)
    bag, slot = ns.Number(bag), Count(slot)
    if not bag or bag % 1 ~= 0 or not slot then return end
    local count, link
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local row = Query(C_Container.GetContainerItemInfo, bag, slot)
        count, link = Field(row, "stackCount"), Field(row, "hyperlink")
    else
        local _, quantity, _, _, _, _, hyperlink = Query(GetContainerItemInfo, bag, slot)
        count, link = quantity, hyperlink
    end
    if ns.ItemIdentity(link) == key then return Count(count) end
end

local function HoverCount(tooltip, key)
    -- A secondary item can be appended to a tooltip. Resolve the same primary
    -- item that GetDisplayedItem uses, independent of the current post-call.
    local data = Call(tooltip, "GetPrimaryTooltipData")
    local guid = ns.Text(Field(data, "guid"))
    if guid and C_Item then
        local location = Query(C_Item.GetItemLocation, guid)
        if ns.Readable(location) and type(location) == "table" then
            local count = Count(Query(C_Item.GetStackCount, location))
            if count then return count, location end
        end
    end
    local info = Call(tooltip, "GetPrimaryTooltipInfo")
    local getter, args = ns.Text(Field(info, "getterName")), Field(info, "getterArgs")
    if getter == "GetBagItem" then
        return BagCount(Field(args, 1), Field(args, 2), key)
    elseif getter == "GetMerchantItem" then
        local index = Count(Field(args, 1))
        if index and ns.ItemIdentity(Query(GetMerchantItemLink, index)) == key then
            local row = Query(C_MerchantFrame and C_MerchantFrame.GetItemInfo, index)
            return Count(Field(row, "stackCount"))
        end
    elseif installedMode == "legacy" and not IsComparison(tooltip) then
        local owner = Call(tooltip, "GetOwner")
        return BagCount(Call(owner, "GetBagID"), Call(owner, "GetID"), key)
    end
end

local function IsCommodity(location, itemID)
    if not C_AuctionHouse then return end
    local statuses = Enum and Enum.ItemCommodityStatus
    if location and statuses then
        local status = ns.Number(Query(C_AuctionHouse.GetItemCommodityStatus, location))
        if status ~= nil and status == statuses.Commodity then return true end
        if status ~= nil and status == statuses.Item then return false end
    end
    local itemKey = Query(C_AuctionHouse.MakeItemKey, itemID, 0, 0, 0)
    if not ns.Readable(itemKey) or type(itemKey) ~= "table" then return end
    local info = Query(C_AuctionHouse.GetItemKeyInfo, itemKey)
    local commodity = Field(info, "isCommodity")
    if ns.Readable(commodity) and type(commodity) == "boolean" then return commodity end
end

local function StackContext(tooltip, link, key, itemID)
    local count, location = HoverCount(tooltip, key)
    if count and count > 1 then return count, false, IsCommodity(location, itemID) end
    local maximum = Count(Query(C_Item and C_Item.GetItemMaxStackSizeByID, link))
    if not maximum then
        local _, _, _, _, _, _, _, stackSize = Query(C_Item and C_Item.GetItemInfo or GetItemInfo, link)
        maximum = Count(stackSize)
    end
    if maximum and maximum > 1 then return maximum, true, IsCommodity(location, itemID) end
end

local function AppendCraftingUses(tooltip, uses)
    tooltip:AddLine(" ")
    tooltip:AddLine("Crafting uses", 1, 0.82, 0)
    for _, use in ipairs(uses) do
        local examples = table.concat(use.examples, ", ")
        local more = use.total - #use.examples
        if more > 0 then examples = examples .. string.format(" (+%d more)", more) end
        tooltip:AddLine("|cffffffff" .. use.profession .. "|r  -  " .. examples, 0.82, 0.82, 0.82, true)
    end
end

local function AppendPrices(tooltip, link, count, fullStack, commodity)
    local ok, record, info = pcall(callbacks.lookup, link)
    if not ok then
        ns.tooltipFailures = (ns.tooltipFailures or 0) + 1
        return
    end
    info = type(info) == "table" and info or {}
    record = type(record) == "table" and record or nil

    tooltip:AddLine(" ")
    tooltip:AddLine("AuctionPeek", 1, 0.82, 0)
    local minimum = record and ns.Number(record.min)
    local maximum = record and ns.Number(record.max)
    local hasRange = minimum and maximum and minimum > 0 and maximum >= minimum
    local stackLabel, stackValue = ns.StackQuote(record, info, count, fullStack, commodity)
    local browse = info.browse
    if browse then
        local label = commodity and "Browse minimum per item" or "Browse minimum (item and suffix)"
        tooltip:AddDoubleLine(label, ns.FormatMoney(browse.price), 0.85, 0.85, 0.85, 0.4, 1, 0.5)
        if stackLabel and not hasRange then
            tooltip:AddDoubleLine(stackLabel, stackValue, 0.85, 0.85, 0.85, 1, 0.85, 0.45)
        end
        tooltip:AddLine(ns.FormatBrowseDetails(browse), 0.75, 0.75, 0.75, true)
    end
    if not info.known then
        tooltip:AddLine(browse and "Refresh Item for this variant's buyout range."
            or "No cached prices - scan at an auctioneer.", 0.65, 0.65, 0.65, true)
    else
        tooltip:AddLine("Buyout per item (this variant)", 1, 0.82, 0)
        local complete = info.complete == true
        if info.empty then
            tooltip:AddLine(complete and "No buyout listings in this snapshot." or "No buyouts in the loaded results.", 0.75, 0.75, 0.75, true)
        elseif hasRange then
            tooltip:AddDoubleLine(complete and "Min buyout" or "Observed min", ns.FormatMoney(minimum), 0.85, 0.85, 0.85, 0.4, 1, 0.5)
            tooltip:AddDoubleLine(complete and "Max buyout" or "Observed max", ns.FormatMoney(maximum), 0.85, 0.85, 0.85, 1, 0.85, 0.45)
            if stackLabel then tooltip:AddDoubleLine(stackLabel, stackValue, 0.85, 0.85, 0.85, 1, 0.85, 0.45) end
            local listings = record and ns.Number(record.listingCount)
            local units = record and ns.Number(record.units)
            if listings and units and listings >= 0 and units >= 0 then
                tooltip:AddLine(string.format("%.0f listings / %.0f items", listings, units), 0.65, 0.65, 0.65)
            end
        else
            tooltip:AddLine("Cached price data unavailable. Scan again.", 0.75, 0.75, 0.75, true)
        end
        local age = ns.Number(info.age)
        local freshness = age and ("Cached " .. ns.FormatAge(age)) or "Cached snapshot - age unknown"
        if info.stale then freshness = freshness .. " - stale" end
        tooltip:AddLine(freshness, info.stale and 1 or 0.65, info.stale and 0.65 or 0.65, info.stale and 0.25 or 0.65, true)
        if not complete then tooltip:AddLine("Partial results; the full price range may differ.", 1, 0.65, 0.25, true) end
        local source = SafeText(info.source)
        if source then tooltip:AddLine(source, 0.55, 0.55, 0.55, true) end
    end
end

local function Append(tooltip)
    if not ns.Readable(tooltip) or tooltip == nil then return end
    local forbidden = Call(tooltip, "IsForbidden")
    if not ns.Readable(forbidden) or forbidden == true then return end
    if type(Field(tooltip, "AddLine")) ~= "function" or type(Field(tooltip, "AddDoubleLine")) ~= "function" then return end
    local link, key, itemID = ItemLink(tooltip)
    if not link then return end
    WatchClear(tooltip)
    local count, fullStack, commodity = StackContext(tooltip, link, key, itemID)
    -- Comparison tooltips must not replace the manual Refresh Item target.
    if not IsComparison(tooltip) and type(callbacks.hovered) == "function" then
        callbacks.hovered(link, count, fullStack, commodity)
    end
    local uses = ns.reagentUses and ns.reagentUses[itemID]
    local showPrices = type(callbacks.lookup) == "function"
        and (type(callbacks.enabled) ~= "function" or callbacks.enabled())
    if not uses and not showPrices then return end
    local lineCount = ns.Number(Call(tooltip, "NumLines"))
    local mark = marks[tooltip]
    if mark and mark.link == link and (not lineCount or not mark.lines or lineCount >= mark.lines) then return end
    if uses then AppendCraftingUses(tooltip, uses) end
    if showPrices then AppendPrices(tooltip, link, count, fullStack, commodity) end
    marks[tooltip] = { link = link, lines = ns.Number(Call(tooltip, "NumLines")) }
    -- The native processor shows/layouts its tooltip after post-calls. Do not
    -- call SetHyperlink, ClearLines, Show, or a server query from this hook.
end

local function SafeAppend(tooltip)
    local ok = pcall(Append, tooltip)
    if not ok then ns.tooltipFailures = (ns.tooltipFailures or 0) + 1 end
end

function ns.InstallTooltipHooks(newCallbacks)
    callbacks = newCallbacks or callbacks
    if installedMode == "modern" then return true, installedMode end
    local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function" and itemType ~= nil then
        local ok = pcall(TooltipDataProcessor.AddTooltipPostCall, itemType, SafeAppend)
        if ok then installedMode = "modern"; return true, installedMode end
    end
    local supported = false
    local tooltips = { GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2,
        ItemRefShoppingTooltip1, ItemRefShoppingTooltip2 }
    -- pairs also reaches later tooltips if an earlier optional global is nil.
    for _, tooltip in pairs(tooltips) do
        if ns.Readable(tooltip) then
            if legacyHooked[tooltip] then supported = true
            else
                local hook = Field(tooltip, "HookScript")
                if type(hook) == "function" then
                    local ok = pcall(hook, tooltip, "OnTooltipSetItem", SafeAppend)
                    if ok then legacyHooked[tooltip] = true; WatchClear(tooltip); supported = true end
                end
            end
        end
    end
    if supported then installedMode = "legacy"; return true, installedMode end
    return false, "No supported item-tooltip hook is available."
end
