local _, ns = ...

local SCAN_INTERVAL, TIMEOUT, CHUNK = 15 * 60, 120, 150
local AUTO_QUIET, AUTO_TIMEOUT, AUTO_CHECK = 2, 30, 0.5

local function Query(fn, ...)
    if type(fn) ~= "function" then return nil end
    local values = { pcall(fn, ...) }
    if not values[1] then return nil end
    return unpack(values, 2, 20)
end

local function Number(value)
    return ns.Number(value)
end

local function Bool(value)
    return ns.Readable(value) and type(value) == "boolean" and value
end

local function Field(value, key)
    if not ns.Readable(value) or type(value) ~= "table" then return nil end
    return Query(function() return value[key] end)
end

local function Now()
    return Number(Query(GetServerTime)) or Number(Query(time)) or 0
end

local function Scope()
    local realm = ns.Text(Query(GetNormalizedRealmName)) or ns.Text(Query(GetRealmName))
    local faction = ns.Text(Query(UnitFactionGroup, "player"))
    local _, _, _, interface = Query(GetBuildInfo)
    interface = Number(interface)
    if not realm or not faction or not interface then return nil end
    -- Deliberately separate client/realm/faction caches. A server may combine
    -- some markets, but that is not an excuse to mix unrelated snapshots.
    return tostring(interface) .. ":" .. realm .. ":" .. faction
end

local function Modern()
    return C_AuctionHouse and type(C_AuctionHouse.ReplicateItems) == "function"
        and type(C_AuctionHouse.GetNumReplicateItems) == "function"
        and type(C_AuctionHouse.GetReplicateItemInfo) == "function"
        and type(C_AuctionHouse.GetReplicateItemLink) == "function"
end

local function CanBrowse()
    return C_AuctionHouse and type(C_AuctionHouse.SendBrowseQuery) == "function"
        and type(C_AuctionHouse.GetBrowseResults) == "function"
        and type(C_AuctionHouse.HasFullBrowseResults) == "function"
        and type(C_AuctionHouse.RequestMoreBrowseResults) == "function"
end

local function ScanLevel()
    local level = Number(Query(UnitLevel, "player"))
    if level and level >= 1 and level % 1 == 0 then return level + 2 end
end

local function BrowseQuery(maxLevel)
    local sorts, filters = {}, {}
    local orders = Enum and Enum.AuctionHouseSortOrder or {}
    for _, name in ipairs({ "Price", "Name" }) do
        if orders[name] then sorts[#sorts + 1] = { sortOrder = orders[name], reverseSort = false } end
    end
    local qualities = Enum and Enum.AuctionHouseFilter or {}
    for _, name in ipairs({ "PoorQuality", "CommonQuality", "UncommonQuality", "RareQuality",
            "EpicQuality", "LegendaryQuality", "ArtifactQuality" }) do
        if qualities[name] then filters[#filters + 1] = qualities[name] end
    end
    return { searchString = "", maxLevel = maxLevel, sorts = sorts, filters = filters }
end

local function Legacy()
    return type(QueryAuctionItems) == "function" and type(CanSendAuctionQuery) == "function"
        and type(GetNumAuctionItems) == "function" and type(GetAuctionItemInfo) == "function"
        and type(GetAuctionItemLink) == "function"
end

local function ScanMode(full)
    if not full and CanBrowse() then return "browse" end
    if Modern() then return "replicate" end
    if Legacy() then return "legacy" end
end

function ns.CreateScanner(db, callbacks)
    callbacks = callbacks or {}
    local scanner = { events = {
        "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_DISABLED",
        "AUCTION_HOUSE_BROWSE_FAILURE", "AUCTION_HOUSE_SHOW_ERROR",
        "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
        "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_ITEM_LIST_UPDATE",
        "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED",
        "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED",
        "AUCTION_HOUSE_NEW_RESULTS_RECEIVED",
        "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
        "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
        "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED",
    } }
    local state = { open = false, busy = false, autoPending = false, phase = "idle",
        status = "Visit an auctioneer to scan prices.", scope = Scope() }
    local job, pending
    if type(db.scanRequestedAt) ~= "table" then db.scanRequestedAt = {} end
    if type(db.browseCompletedAt) ~= "table" then db.browseCompletedAt = {} end

    local function Changed()
        if callbacks.changed then callbacks.changed() end
    end

    local function Status(message, force)
        if state.status ~= message or force then state.status = message; Changed() end
    end

    local function Progress(phase, value, processed, total)
        state.phase, state.progress, state.processed, state.total = phase, value, processed, total
    end

    local function ClearPending()
        pending, state.autoPending = nil, false
    end

    local function QueueAuto()
        pending = { elapsed = 0, quiet = 0, check = 0 }
        state.autoPending = true
        Progress("queued")
        Status("Automatic scan queued. Waiting for the auction house to settle.", true)
        if callbacks.autoQueued then callbacks.autoQueued() end
    end

    function scanner:GetScope()
        return state.scope or Scope()
    end

    function scanner:GetState()
        state.canScan = ScanMode() ~= nil
        state.canRefresh = C_AuctionHouse ~= nil and type(C_AuctionHouse.MakeItemKey) == "function"
            and type(C_AuctionHouse.SendSellSearchQuery) == "function"
        state.mode = state.mode or ScanMode() or "unavailable"
        return state
    end

    local function Fail(message, phase)
        job = nil
        ClearPending()
        state.busy = false
        Progress(phase or "error")
        state.status = message
        Changed()
        return false, message
    end

    function scanner:Cancel(reason)
        if not job and not pending then return false end
        return Fail(reason or "Scan cancelled. Saved prices are available.", "cancelled")
    end

    function scanner:SetAutoScan(enabled)
        db.autoScan = enabled == true
        if not db.autoScan and pending then
            ClearPending()
            Progress("idle")
            Status("Automatic scan disabled. Saved prices are unchanged.", true)
        elseif pending then Changed()
        elseif not job then
            Status(db.autoScan and "Automatic scanning enabled for your next auction-house visit."
                or "Automatic scanning disabled. Use Scan Market when needed.", true)
        else Changed() end
    end

    local function Ready()
        if not C_AuctionHouse or type(C_AuctionHouse.IsThrottledMessageSystemReady) ~= "function" then return true end
        return Bool(Query(C_AuctionHouse.IsThrottledMessageSystemReady)) == true
    end

    local function Send(fn, ...)
        if type(fn) ~= "function" then return false end
        scanner.sending = true
        local ok, result = pcall(fn, ...)
        scanner.sending = false
        return ok, result
    end

    local function Begin(mode, source)
        if state.busy then return false, "A scan is already running. Cancel it first." end
        if not state.open then return false, "Open the auction house before requesting prices." end
        if Bool(Query(InCombatLockdown)) then return false, "Leave combat before requesting prices." end
        state.scope = Scope()
        if not state.scope then return false, "Realm or faction is unavailable; try again after login." end
        job = { mode = mode, source = source, scope = state.scope, elapsed = 0,
            pages = 0, phase = "waiting", snapshot = ns.NewSnapshot(state.scope, Now(), source) }
        state.mode, state.busy, state.maxLevel = mode, true, nil
        Progress("waiting")
        return true
    end

    local function Cooldown(scope)
        local previous = scope and Number(db.scanRequestedAt[scope])
        local now = Now()
        if previous and now >= previous and now - previous < SCAN_INTERVAL then
            return string.format("Full-scan cooldown: about %d minute(s). Saved prices remain available.",
                math.ceil((SCAN_INTERVAL - (now - previous)) / 60))
        end
    end

    function scanner:StartScan(full)
        if state.busy then return false, "A scan is already running. Cancel it first." end
        ClearPending()
        full = full == true
        local mode = ScanMode(full)
        if not mode then return Fail("This client's auction scan API is unavailable.") end
        if not state.open then return Fail("Open the auction house before scanning.") end
        local maxLevel
        if not full then
            maxLevel = ScanLevel()
            if not maxLevel then return Fail("Character level is unavailable. Try scanning again after login.") end
        end
        if mode ~= "browse" then
            local cooldown = Cooldown(Scope())
            if cooldown then return Fail(cooldown, "cooldown") end
        end
        if mode == "legacy" then
            local ready, all = Query(CanSendAuctionQuery)
            if not Bool(ready) or not Bool(all) then return Fail("The server is not ready for a full scan. Try again later.") end
        elseif not Ready() then return Fail("The auction house is busy. Try again when its current search finishes.") end
        local source = maxLevel and ("Market through level " .. maxLevel) or "Full market scan"
        local ok, reason = Begin(mode, source)
        if not ok then return Fail(reason) end
        job.maxLevel, state.maxLevel = maxLevel, maxLevel
        local sent
        if mode == "browse" then
            -- Group prices share the realm/faction cache. Once another cap
            -- writes observations, an older cap must qualify for a new scan.
            db.browseCompletedAt[state.scope] = nil
            job.browsePages, job.seen, job.processed = {}, {}, 0
            sent = Send(C_AuctionHouse.SendBrowseQuery, BrowseQuery(maxLevel))
        elseif mode == "replicate" then sent = Send(C_AuctionHouse.ReplicateItems)
        else sent = Send(QueryAuctionItems, "", nil, nil, 0, false, nil, true, false, nil) end
        if not sent then return Fail("The auction house rejected the scan. Previous prices are unchanged.") end
        if not job then return false, state.status end
        if mode ~= "browse" then db.scanRequestedAt[state.scope] = Now() end
        if job.phase == "waiting" then
            Status(maxLevel and ("Scanning through required level " .. maxLevel .. ". Waiting for auction prices.")
                or "Waiting for auction snapshot. Keep the auction house open.", true)
        end
        return true
    end

    function scanner:RefreshItem(link)
        if state.busy then return false, "A scan is already running. Cancel it first." end
        ClearPending()
        local key, itemID = ns.ItemIdentity(link)
        if not key then return Fail("Hover over an item first, then choose Refresh Item.") end
        if not C_AuctionHouse or type(C_AuctionHouse.MakeItemKey) ~= "function"
            or type(C_AuctionHouse.SendSellSearchQuery) ~= "function" then
            return Fail("Focused refresh is unavailable on this client. Use Scan at an auctioneer.")
        end
        if not Ready() then return Fail("The auction house is busy. Try Refresh Item again shortly.") end
        local itemKey = Query(C_AuctionHouse.MakeItemKey, itemID, 0, 0, 0)
        if not ns.Readable(itemKey) or type(itemKey) ~= "table" then return Fail("This item cannot be searched right now.") end
        local ok, reason = Begin("refresh", "Item refresh")
        if not ok then return Fail(reason) end
        job.key, job.itemID, job.link, job.itemKey = key, itemID, link, itemKey
        job.snapshot.targetKey = key
        -- The native sell-search is a read-only all-variants query. Filter its
        -- returned links to the hovered variant before writing the cache.
        local itemInfo = Query(C_AuctionHouse.GetItemKeyInfo, itemKey)
        local commodity = Bool(Field(itemInfo, "isCommodity"))
        local search = commodity and C_AuctionHouse.SendSearchQuery or C_AuctionHouse.SendSellSearchQuery
        if not Send(search, itemKey, {}, false) then
            return Fail("The item search was rejected. Previous prices are unchanged.")
        end
        if not job then return false, state.status end
        Status("Refreshing item prices. Keep the auction house open.", true)
        return true
    end

    local function BrowseRow(rows, index)
        local row = rows[index]
        if not ns.Readable(row) or type(row) ~= "table" then return end
        return row.itemKey, row.minPrice, row.totalQuantity
    end

    -- UPDATED replaces the native result list. ADDED contains only the new
    -- groups. Keep queued pages if another arrives before the next frame.
    local function ReceiveBrowsePage(added, rows)
        if added and not job.receivedBrowse then return end
        if not added then
            rows = Query(C_AuctionHouse.GetBrowseResults)
            job.browsePages, job.seen, job.processed = {}, {}, 0
        end
        local full = Query(C_AuctionHouse.HasFullBrowseResults)
        if not ns.Readable(rows) or type(rows) ~= "table" or not ns.Readable(full) or type(full) ~= "boolean" then
            return Fail("The auction house returned unreadable browse results. Saved prices are available.")
        end
        local ok, count = pcall(function() return #rows end)
        if not ok then return Fail("The auction house returned an unreadable browse page.") end
        if added and count == 0 and not full then
            return Fail("The auction house returned no more groups. Prices read so far are saved.")
        end
        job.moreRequested = false
        job.browsePages[#job.browsePages + 1] = { rows = rows, count = count, index = 1 }
        job.phase, job.elapsed, job.browseFull, job.receivedBrowse = "browsing", 0, full, true
        Progress("browsing", nil, job.processed)
        Status("Reading auction prices through required level " .. job.maxLevel .. ".", true)
    end

    local function TickBrowse(elapsed)
        if job.phase == "browseMore" then
            job.check = job.check - elapsed
            if job.check > 0 then return end
            job.check = AUTO_CHECK
            if not Ready() then return end
            job.phase, job.elapsed, job.pages, job.moreRequested = "waiting", 0, job.pages + 1, true
            if not Send(C_AuctionHouse.RequestMoreBrowseResults) then
                Fail("The auction house could not load another page. Prices read so far are saved.")
            end
            return
        end
        if job.phase ~= "browsing" then return end
        local page = job.browsePages[1]
        local last = math.min(page.count, page.index + CHUNK - 1)
        for index = page.index, last do
            local ok, itemKey, price, quantity = pcall(BrowseRow, page.rows, index)
            quantity = Number(quantity)
            if ok and quantity and quantity > 0 then
                ns.SaveBrowsePrice(db, job.scope, itemKey, price, job.snapshot.updatedAt, job.maxLevel, job.seen)
            end
        end
        job.processed = job.processed + last - page.index + 1
        page.index = last + 1
        Progress("browsing", nil, job.processed)
        if last >= page.count then table.remove(job.browsePages, 1) end
        if #job.browsePages == 0 then
            if job.browseFull then
                db.browseCompletedAt[job.scope] = { maxLevel = job.maxLevel, updatedAt = Now() }
                Progress("complete", 1, job.processed, job.processed)
                state.status = "Market prices saved through required level " .. job.maxLevel .. "."
                job, state.busy = nil, false
                Changed()
                if callbacks.completed then callbacks.completed() end
                return
            end
            if job.pages >= 200 then return Fail("Browse page limit reached. Prices read so far are saved.") end
            job.phase = job.moreRequested and "waiting" or "browseMore"
            job.elapsed, job.check = 0, 0
        end
        Changed()
    end

    local function ProcessStart(total, kind)
        total = Number(total)
        if not total or total < 0 or total % 1 ~= 0 or total > 2000000 then
            return Fail("Auction results were unreadable. Previous prices are unchanged.")
        end
        job.phase, job.total, job.index, job.kind = "processing", total, 1, kind
        Progress("processing", 0, 0, total)
        Status("Reading auction prices...", true)
    end

    local function SearchResults(kind, confirmedFull)
        if not job or job.mode ~= "refresh" then return end
        if job.phase == "processing" then
            if job.index > 1 then
                Fail("Auction results changed while reading. Previous prices are unchanged; refresh again.")
                return
            end
            -- Before the first row, a second response may safely replace the
            -- count/completeness metadata. Never keep a stale shorter count.
        end
        local commodity = kind == "commodity"
        local target = commodity and job.itemID or job.itemKey
        local full = confirmedFull or Query(commodity and C_AuctionHouse.HasFullCommoditySearchResults or C_AuctionHouse.HasFullItemSearchResults, target)
        if Bool(full) == true then
            local total = Query(commodity and C_AuctionHouse.GetNumCommoditySearchResults or C_AuctionHouse.GetNumItemSearchResults, target)
            job.authoritative = true
            ProcessStart(total, kind)
        else
            job.kind, job.phase = kind, "more"
            Progress("waiting")
            Status("Loading all price results before calculating the range...", true)
        end
    end

    local function Omit()
        job.snapshot.omitted = job.snapshot.omitted + 1
        job.snapshot.incomplete = true
    end

    local function RequiredLevel(value)
        value = Number(value)
        if value and value >= 0 and value % 1 == 0 then return value end
    end

    local function RequiredLevelFromLink(link)
        -- A recipe's auction level can be profession skill, and a bag's can
        -- be its slot count. The exact item link resolves its character level.
        if not job.requiredLevels then job.requiredLevels = {} end
        local level = job.requiredLevels[link]
        if level == nil then
            local getter = C_Item and C_Item.GetItemInfo or GetItemInfo
            local _, _, _, _, minimum = Query(getter, link)
            level = RequiredLevel(minimum) or false
            job.requiredLevels[link] = level
        end
        return level
    end

    local function ReadRow(index)
        if job.mode == "replicate" or job.mode == "legacy" then
            local values
            -- Replicate results uniquely use 0..N-1; the legacy and focused
            -- search APIs use Lua's 1..N indices.
            if job.mode == "replicate" then
                values = { Query(C_AuctionHouse.GetReplicateItemInfo, index - 1) }
            else
                values = { Query(GetAuctionItemInfo, "list", index) }
            end
            local required
            if job.maxLevel and ns.Text(values[7]) == "REQ_LEVEL_ABBR" then
                required = RequiredLevel(values[6])
                if required and required > job.maxLevel then return true end
            end
            if job.mode == "replicate" and ns.Readable(values[18]) and values[18] == false then Omit(); return end
            local link
            if job.mode == "replicate" then link = Query(C_AuctionHouse.GetReplicateItemLink, index - 1)
            else link = Query(GetAuctionItemLink, "list", index) end
            link = ns.Text(link)
            if not link then Omit(); return end
            if job.maxLevel and not required then
                required = RequiredLevelFromLink(link)
                if not required then Omit(); return end
                if required > job.maxLevel then return end
            end
            ns.AddListing(job.snapshot, link, values[3], values[10])
        elseif job.kind == "commodity" then
            local row = Query(C_AuctionHouse.GetCommoditySearchResultInfo, job.itemID, index)
            local id, quantity, unitPrice = Number(Field(row, "itemID")), Number(Field(row, "quantity")), Number(Field(row, "unitPrice"))
            if id ~= job.itemID or not quantity or not unitPrice then Omit(); return end
            ns.AddListing(job.snapshot, job.link, quantity, quantity * unitPrice)
        else
            local row = Query(C_AuctionHouse.GetItemSearchResultInfo, job.itemKey, index)
            local link = Field(row, "itemLink")
            local identity = ns.ItemIdentity(link)
            if not identity then Omit(); return end
            if identity == job.key then
                local buyout = Field(row, "buyoutAmount")
                if ns.Readable(buyout) and buyout == nil then buyout = 0 end
                ns.AddListing(job.snapshot, link, Field(row, "quantity"), buyout)
            end
        end
    end

    local function Finish()
        local snapshot = job.snapshot
        local fullLegacy = job.mode == "legacy" and job.maxLevel == nil
        local complete = fullLegacy or (job.mode == "refresh" and job.authoritative)
        -- Replicate coverage can vary by market/client, especially commodities.
        -- Only a fully read, unfiltered legacy scan can replace the market.
        local saved = ns.Commit(db, job.scope, snapshot, complete == true, fullLegacy)
        if not saved then return Fail("Could not save auction prices. Try scanning again.") end
        local omitted, mode, maxLevel = snapshot.omitted, job.mode, job.maxLevel
        Progress("complete", 1, job.total, job.total)
        job = nil
        state.busy = false
        if maxLevel then state.status = string.format("Saved observed prices through required level %d.", maxLevel)
        elseif mode == "refresh" then state.status = "Item refresh saved. Hover the item again to see its prices."
        else state.status = "Snapshot saved. Hover items to see observed prices; Refresh Item checks a complete item search." end
        if omitted > 0 then state.status = state.status .. " Some rows were unreadable; the range is incomplete." end
        Changed()
        if callbacks.completed then callbacks.completed() end
    end

    function scanner:Tick(elapsed)
        elapsed = math.max(0, Number(elapsed) or 0)
        if pending then
            pending.elapsed, pending.quiet, pending.check = pending.elapsed + elapsed, pending.quiet + elapsed, pending.check + elapsed
            if pending.elapsed >= AUTO_TIMEOUT then
                Fail("Automatic scan could not start while the auction house was busy. Saved prices remain available.")
                return
            end
            if pending.quiet < AUTO_QUIET or pending.check < AUTO_CHECK then return end
            pending.check = 0
            local mode, scope = ScanMode(), Scope()
            if not mode then Fail("This client's auction scan API is unavailable."); return end
            local maxLevel = ScanLevel()
            if not maxLevel then
                Status("Automatic scan queued. Waiting for your character level.")
                return
            end
            if mode == "browse" then
                local history = db.browseCompletedAt[scope]
                local previous = type(history) == "table" and history.maxLevel == maxLevel and Number(history.updatedAt)
                local now = Now()
                if previous and now >= previous and now - previous < SCAN_INTERVAL then
                    Fail("Market prices through level " .. maxLevel .. " were recently scanned.", "cooldown")
                    return
                end
            else
                local cooldown = Cooldown(scope)
                if cooldown then Fail(cooldown, "cooldown"); return end
            end
            if Bool(Query(InCombatLockdown)) then
                Status("Automatic scan queued. Waiting for combat to end.")
                return
            end
            local ready = Ready()
            if mode == "legacy" then
                local canQuery, canAll = Query(CanSendAuctionQuery)
                ready = Bool(canQuery) and Bool(canAll)
            end
            if not ready then
                Status("Automatic scan queued. Waiting for the auction house to become ready.")
                return
            end
            self:StartScan()
            return
        end
        if not job then return end
        job.elapsed = job.elapsed + math.max(0, elapsed)
        if job.elapsed > TIMEOUT and job.phase ~= "browsing" and job.phase ~= "processing" then
            Fail("Auction request timed out or was throttled. Saved prices are available.")
            return
        end
        if job.mode == "browse" then TickBrowse(elapsed); return end
        if job.phase == "processing" then
            -- A row excluded before even fetching its link costs much less
            -- than decoding and aggregating a listing. Bound both workloads.
            local cheapRowsPerListing = 4
            local budget = CHUNK * cheapRowsPerListing
            while job.index <= job.total and budget > 0 do
                local skippedBeforeLink = ReadRow(job.index)
                budget = budget - (skippedBeforeLink and 1 or cheapRowsPerListing)
                job.index = job.index + 1
            end
            local maximum = job.index - 1
            Progress("processing", job.total > 0 and maximum / job.total or 0, maximum, job.total)
            if job.index > job.total then Finish() else Changed() end
        elseif job.phase == "more" and Ready() then
            if job.pages >= 200 then Fail("Too many auction result pages. Previous prices are unchanged."); return end
            local commodity = job.kind == "commodity"
            local target = commodity and job.itemID or job.itemKey
            local fn = commodity and C_AuctionHouse.RequestMoreCommoditySearchResults or C_AuctionHouse.RequestMoreItemSearchResults
            job.phase, job.pages = "waiting", job.pages + 1
            local sent, full = Send(fn, target)
            if not sent then Fail("More auction results are unavailable. Previous prices are unchanged.") end
            if job and (Bool(full) or Bool(Query(commodity and C_AuctionHouse.HasFullCommoditySearchResults or C_AuctionHouse.HasFullItemSearchResults, target))) then
                SearchResults(job.kind, true)
            end
        end
    end

    function scanner:OnEvent(event, arg)
        local interaction = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Auctioneer
        local auctionInteraction = interaction and Number(arg) == interaction
        if event == "AUCTION_HOUSE_SHOW" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and auctionInteraction) then
            if state.open then return end
            state.open, state.scope = true, Scope()
            if db.autoScan == true then QueueAuto()
            else
                Progress("idle")
                Status("Auction house open. Scan through your level + 2 or refresh a hovered item.", true)
            end
        elseif event == "AUCTION_HOUSE_CLOSED" or event == "AUCTION_HOUSE_DISABLED"
            or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and auctionInteraction) then
            state.open = false
            if job or pending then self:Cancel("Auction house closed. Saved prices are available.")
            else Status("Cached prices remain available away from the auction house.", true) end
        elseif event == "PLAYER_ENTERING_WORLD" then
            if job or pending then self:Cancel("World changed. Saved prices are available.")
            else Progress("idle") end
            state.open, state.scope = false, Scope()
            Changed()
        elseif job then
            if event == "AUCTION_HOUSE_BROWSE_FAILURE" or event == "AUCTION_HOUSE_SHOW_ERROR" then
                return Fail("The auction house reported an error. Saved prices are available.")
            elseif job.mode == "browse" and event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
                return ReceiveBrowsePage(false)
            elseif job.mode == "browse" and event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
                return ReceiveBrowsePage(true, arg)
            elseif job.phase == "processing" and job.index > 1
                and ((event == "REPLICATE_ITEM_LIST_UPDATE" and job.mode == "replicate")
                    or (event == "AUCTION_ITEM_LIST_UPDATE" and job.mode == "legacy")) then
                return Fail("Auction results changed while reading. Previous prices are unchanged; scan again later.")
            elseif event == "REPLICATE_ITEM_LIST_UPDATE" and job.mode == "replicate"
                and (job.phase == "waiting" or (job.phase == "processing" and job.index == 1)) then
                ProcessStart(Query(C_AuctionHouse.GetNumReplicateItems), "replicate")
            elseif event == "AUCTION_ITEM_LIST_UPDATE" and job.mode == "legacy"
                and (job.phase == "waiting" or (job.phase == "processing" and job.index == 1)) then
                local count, total = Query(GetNumAuctionItems, "list")
                if Number(count) ~= nil and Number(count) == Number(total) then ProcessStart(count, "legacy")
                else
                    job.phase = "waiting"
                    Progress("waiting")
                    Status("Waiting for the complete auction snapshot...", true)
                end
            elseif job.mode == "refresh" then
                local matches = Number(Field(arg, "itemID")) == job.itemID
                    and Number(Field(arg, "itemLevel")) == 0 and Number(Field(arg, "itemSuffix")) == 0
                    and Number(Field(arg, "battlePetSpeciesID")) == 0
                if (event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED") and Number(arg) == job.itemID then
                    SearchResults("commodity")
                elseif (event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED")
                    and matches then
                    SearchResults("item")
                elseif event == "AUCTION_HOUSE_NEW_RESULTS_RECEIVED" and matches then
                    local info = Query(C_AuctionHouse.GetItemKeyInfo, job.itemKey)
                    local commodity = Field(info, "isCommodity")
                    if ns.Readable(commodity) and type(commodity) == "boolean" then
                        SearchResults(commodity and "commodity" or "item")
                    end
                end
            end
            if event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then self:Cancel("Auction request was dropped. Saved prices are available.") end
        end
    end

    -- Native searches and other addons share the same result storage. If one
    -- starts a new query, discard our in-flight work instead of mixing results.
    local function ExternalSearch()
        if scanner.sending then return end
        if pending then
            -- Initial Blizzard queries can follow the open event. Let them
            -- settle before starting, rather than fighting over the throttle.
            pending.quiet, pending.check = 0, 0
            Status("Automatic scan queued. Waiting for the current auction search to settle.")
        elseif job then scanner:Cancel("Another auction search started. Saved prices are available.") end
    end
    if type(hooksecurefunc) == "function" and C_AuctionHouse then
        for _, method in ipairs({ "SendSearchQuery", "SendSellSearchQuery", "SendBrowseQuery", "ReplicateItems",
            "RefreshItemSearchResults", "RefreshCommoditySearchResults", "SearchForItemKeys", "SearchForFavorites" }) do
            if type(C_AuctionHouse[method]) == "function" then
                pcall(hooksecurefunc, C_AuctionHouse, method, ExternalSearch)
            end
        end
        -- The native browse list can request its own next page as it scrolls.
        -- Consume that response without making a competing request for it.
        if type(C_AuctionHouse.RequestMoreBrowseResults) == "function" then
            pcall(hooksecurefunc, C_AuctionHouse, "RequestMoreBrowseResults", function()
                if scanner.sending or not job or job.mode ~= "browse" or not job.receivedBrowse then return end
                job.moreRequested = true
                if job.phase == "browseMore" then job.phase = "waiting" end
            end)
        end
    end
    if type(hooksecurefunc) == "function" and type(QueryAuctionItems) == "function" then
        pcall(hooksecurefunc, "QueryAuctionItems", ExternalSearch)
    end
    return scanner
end
