--============================================================
-- FARM A FISH
-- TAB SHOP        : Gear / Bait / Egg / Golden
-- TAB GEAR        : Food / Craft Jumper Only / Auto Craft Gear (Multi)
-- TAB AUTO MUTASI : Auto Pet Mutation + Select All / Clear All
-- TAB BOOST       : Super FPS Boost / Hide Fish
-- TAB WEBHOOK     : Webhook Log
-- + AUTO ANTI-AFK (langsung aktif, tanpa GUI)
--============================================================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local RS          = game:GetService("ReplicatedStorage")
local Players     = game:GetService("Players")
local UIS         = game:GetService("UserInputService")
local VIM         = game:GetService("VirtualInputManager")
local Lighting    = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

local TS = RS:WaitForChild("TS", 30)
if not TS then return end

local remotes = require(TS:WaitForChild("remotes")).default
local pdm = require(TS:WaitForChild("state"):WaitForChild("player-data"))
local getPlayerData = pdm.getPlayerData
local srm = require(TS:WaitForChild("state"):WaitForChild("shop-restock"))
local shopRestock, ShopType, personalRestockItems = srm.shopRestock, srm.ShopType, srm.personalRestockItems
local tm = require(TS.state["travelling-merchant"])
local travellingMerchants = tm.travellingMerchants

local craftingUtils = nil
pcall(function() craftingUtils = require(TS:WaitForChild("utils"):WaitForChild("crafting.utils")) end)

local petAgeUtils = nil
pcall(function() petAgeUtils = require(TS:WaitForChild("utils"):WaitForChild("pet-age.utils")) end)

local rc = RS:WaitForChild("rbxts_include"):WaitForChild("node_modules"):WaitForChild("@rbxts"):WaitForChild("remo"):WaitForChild("src"):WaitForChild("container")
local goldenBuyRemote   = rc:WaitForChild("merchant.purchaseItem")
local placeRemote       = rc:WaitForChild("ponds.placeBuilding")
local selectCraftRemote = rc:WaitForChild("crafting.selectCraftingItem")
local submitRemote      = rc:WaitForChild("crafting.submitItems")
local startCraftRemote  = rc:WaitForChild("crafting.startCraft")
local collectRemote     = rc:WaitForChild("crafting.collectCraft")

local purchaseGear = remotes.shop.purchaseGear
local purchaseBait = remotes.shop.purchaseBait
local purchaseEgg  = remotes.shop.purchaseEgg

local GEAR_LIST = {"NetMover","FoodScoop","MagnifyingGlass","TeleportWand","StarLock","TradingTicket","BasicAutoFeeder","AdvancedAutoFeeder","SupremeAutoFeeder","ExtremeAutoFeeder","GodlyAutoFeeder","BasicFoodTray","AdvancedFoodTray","SupremeFoodTray","XpCookie","PetToy","PetWhistle","GoldenCookie","EggHatcher","EggIncubator","MutationBeacon","StormHorn"}
local EGG_WL = {"Tropical", "Exotic"}

local CFG = {
    Interval = 5, BuyAll = true, BaitWL = {}, BaitBL = {},
    StockTTL = 1.5, BuyDelay = 0.15,
    SchedulerTick = 0.5,
    GoldenInterval = 3, GoldenIdleInterval = 10, GoldenBuyDelay = 0.25,
    GoldenBulkLoopDelay = 0.4, GoldenMaxPass = 8,
    FoodOn = false, FoodInt = 300,
    FoodType = "SupremeFoodTray", FoodCat = "booster",
    FoodPos = Vector3.new(10.86, -0.012, -11),
    CraftOn = false, CraftItem = "TimeJumper", CraftCat = "gear",
    CraftMats = {{n = "TeleportWand", a = 10}, {n = "MagnifyingGlass", a = 25}, {n = "SupremeAutoFeeder", a = 1}},
}

local S = {
    gOn = false, gTot = 0, bOn = false, bTot = 0, eOn = false, eTot = 0,
    gdOn = false, gdTot = 0, gdActive = false,
    nextGear = 0, nextBait = 0, nextEgg = 0, nextGolden = 0,
    nextPlace = 0,
    _stockCache = {},
    pCnt = 0,
    cRun = false, cAtt = 0, cOk = 0, cFail = 0, cCd = 0, cPhase = "idle",
    _nextCraftTry = 0,
}

--============================================================
-- ANTI-AFK
--============================================================
local AntiAFK = { lastActivity = tick(), timeout = 1190, inputConnected = false, enabled = true }
local function markActivity() AntiAFK.lastActivity = tick() end

local function sendFakeActivity()
    pcall(function()
        VIM:SendKeyEvent(true, Enum.KeyCode.W, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game)
    end)
    pcall(function()
        VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
    end)
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam then
            local pos = UIS:GetMouseLocation()
            VIM:SendMouseMoveEvent(pos.X + 3, pos.Y + 3, game)
            task.wait(0.02)
            VIM:SendMouseMoveEvent(pos.X, pos.Y, game)
        end
    end)
end

local function setupAntiAFK()
    if AntiAFK.inputConnected then return end
    AntiAFK.inputConnected = true
    UIS.InputBegan:Connect(function() markActivity() end)
    local function hookHumanoid(char)
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        hum.Jumping:Connect(function() markActivity() end)
        hum.Running:Connect(function() markActivity() end)
    end
    if player.Character then hookHumanoid(player.Character) end
    player.CharacterAdded:Connect(function(char)
        task.wait(1)
        hookHumanoid(char)
        markActivity()
    end)
    task.spawn(function()
        while AntiAFK.enabled do
            task.wait(60)
            if not AntiAFK.enabled then break end
            local idle = tick() - AntiAFK.lastActivity
            if idle >= 240 then sendFakeActivity() markActivity() end
            if idle >= AntiAFK.timeout then
                pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
                markActivity()
            end
        end
    end)
end
setupAntiAFK()

--=== STOCK / BUY ===
local function stockKey(s, t) return s .. "|" .. t end

local function getStock(shopType, itemType)
    local k = stockKey(shopType, itemType)
    local now = os.clock()
    local c = S._stockCache[k]
    if c and (now - c.t) < CFG.StockTTL then return c.v end
    local val = 0
    local ok, rs, pi, data = pcall(function()
        return shopRestock(), personalRestockItems(), getPlayerData(player)
    end)
    if ok and rs and data then
        local nowT = os.time()
        local pr = data.personalRestocks and data.personalRestocks[shopType]
        local active = pr and pr.endTime and nowT < pr.endTime
        local uid = tostring(player.UserId)
        local avail
        if active then
            avail = pi[uid] and pi[uid][shopType] and pi[uid][shopType][itemType] or 0
        else
            avail = rs.availableItems and rs.availableItems[shopType] and rs.availableItems[shopType][itemType] or 0
        end
        local bought = 0
        local pur = data.shopPurchases and data.shopPurchases[shopType]
        if pur and pur.purchases then
            if active and pur.currentTimeSlot == pr.timeSlot then
                bought = pur.purchases[itemType] or 0
            elseif not active and pur.currentTimeSlot == rs.currentTimeSlot then
                bought = pur.purchases[itemType] or 0
            end
        end
        val = math.max(0, avail - bought)
    end
    S._stockCache[k] = {v = val, t = now}
    return val
end

local function invalidateStock(s, t) S._stockCache[stockKey(s, t)] = nil end

local function getAvail(shopType, wl, bl)
    local list = {}
    local rs = shopRestock()
    if not rs then return list end
    local shop = rs.availableItems and rs.availableItems[shopType]
    if not shop then return list end
    local wlSet, blSet
    if wl and #wl > 0 then wlSet = {} for _, v in ipairs(wl) do wlSet[v] = true end end
    if bl and #bl > 0 then blSet = {} for _, v in ipairs(bl) do blSet[v] = true end end
    for t, s in pairs(shop) do
        local inc = true
        if wlSet and not wlSet[t] then inc = false end
        if inc and blSet and blSet[t] then inc = false end
        if inc then list[#list + 1] = {type = t, stock = s} end
    end
    return list
end

local function buyGearSafe(t) local ok = pcall(purchaseGear, t) if ok then invalidateStock(ShopType.Gear, t) end return ok end
local function buyBaitSafe(t) local ok = pcall(purchaseBait, t) if ok then invalidateStock(ShopType.Bait, t) end return ok end
local function buyEggSafe(t) local ok = pcall(purchaseEgg, t) if ok then invalidateStock(ShopType.Eggs, t) end return ok end

local function bulkGear()
    for _, t in ipairs(GEAR_LIST) do
        if not S.gOn then return end
        local rem = getStock(ShopType.Gear, t)
        if rem > 0 then
            local max = CFG.BuyAll and (rem + 2) or 1
            for a = 1, max do
                if not S.gOn then return end
                if not buyGearSafe(t) then break end
                S.gTot += 1
                if a < max then task.wait(CFG.BuyDelay) end
            end
        end
    end
end

local function bulkBait()
    local list = getAvail(ShopType.Bait, CFG.BaitWL, CFG.BaitBL)
    if #list == 0 then return end
    for _, it in ipairs(list) do
        if not S.bOn then return end
        local rem = getStock(ShopType.Bait, it.type)
        if rem > 0 then
            local max = CFG.BuyAll and (rem + 2) or 1
            for a = 1, max do
                if not S.bOn then return end
                if not buyBaitSafe(it.type) then break end
                S.bTot += 1
                if a < max then task.wait(CFG.BuyDelay) end
            end
        end
    end
end

local function bulkEgg()
    local list = getAvail(ShopType.Eggs, EGG_WL, nil)
    if #list == 0 then return end
    for _, it in ipairs(list) do
        if not S.eOn then return end
        local rem = getStock(ShopType.Eggs, it.type)
        if rem > 0 then
            local max = CFG.BuyAll and (rem + 2) or 1
            for a = 1, max do
                if not S.eOn then return end
                if not buyEggSafe(it.type) then break end
                S.eTot += 1
                if a < max then task.wait(CFG.BuyDelay) end
            end
        end
    end
end

--=== GOLDEN ===
local function getGoldenData()
    local d = travellingMerchants()
    if not d then return nil end
    return d.golden
end

local function getGoldenStock()
    local md = getGoldenData()
    if not md or not md.isActive or not md.availableStock then return {}, false end
    local map = {}
    for k, v in pairs(md.availableStock) do map[k] = v end
    return map, true
end

local function goldenBuyOne(itemName)
    return pcall(function() goldenBuyRemote:FireServer("golden", itemName) end)
end

local function goldenBulkBuy()
    local total, pass = 0, 0
    while S.gdOn and pass < CFG.GoldenMaxPass do
        pass += 1
        local map, active = getGoldenStock()
        if not active then break end
        local targets = {}
        for itemName, stock in pairs(map) do
            if stock > 0 then table.insert(targets, itemName) end
        end
        if #targets == 0 then break end
        for _, itemName in ipairs(targets) do
            if not S.gdOn then break end
            if goldenBuyOne(itemName) then
                total += 1
                S.gdTot += 1
            end
            task.wait(CFG.GoldenBuyDelay)
        end
        task.wait(CFG.GoldenBulkLoopDelay)
    end
    return total
end

--=== FOOD ===
local function doFood()
    S.pCnt += 1
    pcall(function() placeRemote:InvokeServer(CFG.FoodCat, CFG.FoodType, CFG.FoodPos) end)
end

--=== CRAFT JUMPER (single) ===
local CRAFT_TIME_FALLBACK = {DiamondCookie = 300, YolkBreaker = 600, TimeJumper = 600, ShieldLock = 1500, NetRetractor = 1500}

local function getCraftTime(id, cat)
    if craftingUtils and craftingUtils.getCraftingTime then
        local ok, r = pcall(craftingUtils.getCraftingTime, id, cat)
        if ok and r then return r end
    end
    return CRAFT_TIME_FALLBACK[id] or 600
end

local function getCraftData()
    local data = getPlayerData(player)
    if not data or not data.crafting then return nil end
    local c = data.crafting[CFG.CraftCat]
    if not c or not c.id then return nil end
    return c
end

local function getCraftRem()
    local c = getCraftData()
    if not c or not c.timeStarted then return nil end
    local now = os.time()
    local tt = getCraftTime(c.id, CFG.CraftCat)
    local acc = c.accumulatedProgress or 0
    local lu = c.lastProgressUpdate or c.timeStarted
    local dr = c.depletionRate or 1
    return math.max(0, tt - (acc + (now - lu) * dr))
end

local function isCraftActive()
    local c = getCraftData()
    return c and c.timeStarted ~= nil
end

local function doCraftOnce()
    S.cAtt += 1
    S.cPhase = "submitting"
    local ok = pcall(function() selectCraftRemote:FireServer(CFG.CraftItem, CFG.CraftCat) end)
    task.wait(0.3)
    if ok then
        local mats, idx = {}, 1
        for _, m in ipairs(CFG.CraftMats) do
            for _ = 1, m.a do mats[idx] = m.n idx += 1 end
        end
        ok = pcall(function() submitRemote:FireServer(mats, CFG.CraftCat) end)
        task.wait(0.3)
    end
    if ok then
        ok = pcall(function() startCraftRemote:FireServer(CFG.CraftCat) end)
        task.wait(0.3)
    end
    if not ok then S.cFail += 1 S.cPhase = "idle" return false end
    S.cPhase = "crafting"
    return true
end

local function collectCraft()
    S.cPhase = "collecting"
    local ok = pcall(function() collectRemote:FireServer(CFG.CraftCat) end)
    if ok then S.cOk += 1 end
    S.cPhase = "idle"
    return ok
end

--============================================================
-- AUTO CRAFT GEAR (MULTI) - FIX REAL EXECUTOR CAPABILITY
--============================================================
local AC_GEARS = {
    {
        name  = "TimeJumper",
        items = {
            { id = "TeleportWand",      count = 10 },
            { id = "MagnifyingGlass",   count = 25 },
            { id = "SupremeAutoFeeder", count = 1  },
        },
    },
    {
        name  = "DiamondCookie",
        items = {
            { id = "XpCookie",     count = 1 },
            { id = "GoldenCookie", count = 1 },
            { id = "PetToy",       count = 1 },
        },
    },
    {
        name  = "NetRetractor",
        items = {
            { id = "NetMover",          count = 5 },
            { id = "ExtremeAutoFeeder", count = 1 },
        },
    },
}

local AC = {
    LoopDelay = 0.05,
    MachineType = "GearAutoCrafter",
}

local AC_State = {
    running = false, loopCount = 0,
    selectedGear = AC_GEARS[1], uid = nil, uidPond = nil,
    currentUid = nil, lastTick = 0
}

local function acExpandItems(spec)
    local list = {}
    for _, e in ipairs(spec) do
        for _ = 1, e.count do table.insert(list, e.id) end
    end
    return list
end

local function acFindAll()
    local found = {}
    local ok, data = pcall(getPlayerData, player)
    if not ok or not data or not data.ponds then return found end
    for pondKey, pondData in pairs(data.ponds) do
        if type(pondData) == "table" and type(pondData.machines) == "table" then
            for uid, mData in pairs(pondData.machines) do
                if type(mData) == "table" and mData.machineType == AC.MachineType then
                    table.insert(found, {
                        pondKey = pondKey, uid = uid,
                        position = mData.position,
                        customName = pondData.customName,
                    })
                end
            end
        end
    end
    return found
end

local function acPick()
    local list = acFindAll()
    if #list == 0 then return nil, list end
    for _, e in ipairs(list) do
        if tostring(e.pondKey):lower() == "pond2" then return e, list end
    end
    return list[1], list
end

local AC_Remote = {}
local function acFire(name, arg1, arg2, arg3)
    local r = rc:FindFirstChild(name)
    if r and r:IsA("RemoteEvent") then 
        if arg3 ~= nil then
            r:FireServer(arg1, arg2, arg3)
        elseif arg2 ~= nil then
            r:FireServer(arg1, arg2)
        elseif arg1 ~= nil then
            r:FireServer(arg1)
        else
            r:FireServer()
        end
        return true 
    end
    return false
end

function AC_Remote.selectItem(name, amount)
    if not AC_State.currentUid then return false end
    return acFire("autoCrafting.selectCraftingItem", AC_State.currentUid, name, amount or 1)
end
function AC_Remote.submitItems(list)
    if not AC_State.currentUid then return false end
    return acFire("autoCrafting.submitItems", AC_State.currentUid, list)
end
function AC_Remote.startCraft()
    if not AC_State.currentUid then return false end
    return acFire("autoCrafting.startCraft", AC_State.currentUid)
end
function AC_Remote.collectCraft()
    if not AC_State.currentUid then return false end
    return acFire("autoCrafting.collectCraft", AC_State.currentUid)
end
function AC_Remote.cancelCraft()
    if not AC_State.currentUid then return false end
    return acFire("autoCrafting.cancelCraft", AC_State.currentUid)
end

local function acRunCraft(gear)
    if not AC_State.currentUid then return end
    AC_Remote.selectItem(gear.name, 1)
    AC_Remote.submitItems(acExpandItems(gear.items))
    AC_Remote.startCraft()
    AC_Remote.collectCraft()
    AC_Remote.cancelCraft()
end

local function acRefreshUid()
    local chosen = acPick()
    if chosen then
        AC_State.uid = chosen.uid
        AC_State.uidPond = chosen.pondKey
        return chosen
    end
    AC_State.uid = nil
    AC_State.uidPond = nil
    return nil
end

--============================================================
-- SCHEDULER
--============================================================
local schedulerRunning = false

local function tickScheduler()
    local now = os.clock()
    if S.gOn and now >= S.nextGear then S.nextGear = now + CFG.Interval task.spawn(bulkGear) end
    if S.bOn and now >= S.nextBait then S.nextBait = now + CFG.Interval task.spawn(bulkBait) end
    if S.eOn and now >= S.nextEgg then S.nextEgg = now + CFG.Interval task.spawn(bulkEgg) end
    if S.gdOn and now >= S.nextGolden then
        local interval = S.gdActive and CFG.GoldenInterval or CFG.GoldenIdleInterval
        S.nextGolden = now + interval
        task.spawn(function()
            local _, active = getGoldenStock()
            S.gdActive = active
            if active then goldenBulkBuy() end
        end)
    end
    if CFG.FoodOn and now >= S.nextPlace then
        S.nextPlace = now + CFG.FoodInt
        task.spawn(doFood)
    end
    if CFG.CraftOn then
        if isCraftActive() then
            local rem = getCraftRem()
            if rem then
                S.cCd = rem
                S.cPhase = "crafting"
                if rem <= 0 then task.spawn(collectCraft) end
            else
                S.cPhase = "idle"
                S.cCd = 0
            end
        else
            if not S._nextCraftTry or now >= S._nextCraftTry then
                S._nextCraftTry = now + 2
                task.spawn(doCraftOnce)
            end
        end
    else
        S.cCd = 0
    end
end

local function startScheduler()
    if schedulerRunning then return end
    schedulerRunning = true
    task.spawn(function()
        while schedulerRunning do
            tickScheduler()
            task.wait(CFG.SchedulerTick)
        end
    end)
end
startScheduler()

--============================================================
-- RAYFIELD WINDOW
--============================================================
local Window = Rayfield:CreateWindow({
    Name = "Farm A fish",
    LoadingTitle = "Farm A fish",
    LoadingSubtitle = "by bang iqi",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
})

--============================================================
-- WEBHOOK SYSTEM CONFIG
--============================================================
local WEBHOOK = {
    url = "",
    enabled = true,
    notifyJumperEmpty = true,
    username = "Farm A Fish - Mutation Log",
    lastJumperEmptyNotify = 0,
}

local function sendWebhook(payload)
    if not WEBHOOK.enabled or WEBHOOK.url == "" then return end
    task.spawn(function()
        pcall(function()
            local body = HttpService:JSONEncode(payload)
            local req = (syn and syn.request) or (http and http.request) or http_request or request
            if req then
                req({
                    Url = WEBHOOK.url,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = body,
                })
            end
        end)
    end)
end

--============================================================
-- TAB SHOP
--============================================================
local ShopTab = Window:CreateTab("Shop", 4483362458)

ShopTab:CreateToggle({
    Name = "Auto Buy Gear", CurrentValue = false, Flag = "AutoGear",
    Callback = function(v) S.gOn = v S.nextGear = 0 end,
})
ShopTab:CreateToggle({
    Name = "Auto Buy Bait", CurrentValue = false, Flag = "AutoBait",
    Callback = function(v) S.bOn = v S.nextBait = 0 end,
})
ShopTab:CreateToggle({
    Name = "Auto Buy Egg", CurrentValue = false, Flag = "AutoEgg",
    Callback = function(v) S.eOn = v S.nextEgg = 0 end,
})
ShopTab:CreateToggle({
    Name = "Auto Buy Golden", CurrentValue = false, Flag = "AutoGolden",
    Callback = function(v) S.gdOn = v S.nextGolden = 0 end,
})

--============================================================
-- TAB GEAR
--============================================================
local GearTab = Window:CreateTab("Gear", 4483362458)

GearTab:CreateSection("Food")
GearTab:CreateInput({
    Name = "Interval Place Food (detik)",
    CurrentValue = tostring(CFG.FoodInt),
    PlaceholderText = "300",
    RemoveTextAfterFocusLost = false,
    Flag = "FoodInterval",
    Callback = function(text)
        local n = tonumber(text)
        if n and n > 0 then CFG.FoodInt = n S.nextPlace = 0 end
    end,
})
GearTab:CreateToggle({
    Name = "Auto Food", CurrentValue = false, Flag = "AutoFood",
    Callback = function(v) CFG.FoodOn = v S.nextPlace = 0 end,
})

GearTab:CreateSection("Craft Jumper Only")
GearTab:CreateToggle({
    Name = "Auto Craft Jumper", CurrentValue = false, Flag = "AutoCraftJumper",
    Callback = function(v)
        CFG.CraftOn = v
        S._nextCraftTry = 0
        if not CFG.CraftOn then S.cPhase = "idle" S.cCd = 0 end
    end,
})

GearTab:CreateSection("Auto Craft Gear (Multi)")

local acGearNames = {}
for _, g in ipairs(AC_GEARS) do table.insert(acGearNames, g.name) end

GearTab:CreateDropdown({
    Name = "Pilih Gear",
    Options = acGearNames,
    CurrentOption = { AC_GEARS[1].name },
    MultipleOptions = false,
    Flag = "AC_SelectGear",
    Callback = function(sel)
        local name = sel[1]
        for _, g in ipairs(AC_GEARS) do
            if g.name == name then AC_State.selectedGear = g break end
        end
    end,
})

GearTab:CreateInput({
    Name = "Loop Delay (detik)",
    CurrentValue = tostring(AC.LoopDelay),
    PlaceholderText = "0.05",
    RemoveTextAfterFocusLost = false,
    Flag = "AC_LoopDelay",
    Callback = function(text)
        local n = tonumber(text)
        if n and n >= 0 then AC.LoopDelay = n end
    end,
})

GearTab:CreateButton({
    Name = "🔄 Cari GearAutoCrafter (UID)",
    Callback = function()
        local chosen = acRefreshUid()
        if chosen then
            print(string.format("[AutoCraft] Found UID=%s pond=%s", tostring(chosen.uid), tostring(chosen.pondKey)))
        else
            warn("[AutoCraft] GearAutoCrafter tidak ditemukan")
        end
    end,
})

local acStatus = GearTab:CreateLabel("Status: OFF")

-- Gunakan RunService untuk bypass proteksi executor
game:GetService("RunService").Heartbeat:Connect(function()
    if not AC_State.running then return end
    local now = os.clock()
    if now - AC_State.lastTick < AC.LoopDelay then return end
    AC_State.lastTick = now

    local gear = AC_State.selectedGear
    acRunCraft(gear)
    
    AC_State.loopCount = AC_State.loopCount + 1
    pcall(function()
        acStatus:Set(string.format("Status: RUNNING (%d) - %s", AC_State.loopCount, gear.name))
    end)

    if AC_State.loopCount % 5 == 0 then
        acRefreshUid()
        if AC_State.uid then AC_State.currentUid = AC_State.uid end
    end
end)

GearTab:CreateToggle({
    Name = "Aktifkan Auto Craft Gear",
    CurrentValue = false, Flag = "AC_Toggle",
    Callback = function(state)
        if state then
            local chosen = acRefreshUid()
            if not chosen then
                warn("[AutoCraft] GearAutoCrafter tidak ditemukan")
                acStatus:Set("Status: GearAutoCrafter tidak ada")
                return
            end
            AC_State.currentUid = chosen.uid
            AC_State.running = true
            AC_State.loopCount = 0
            acStatus:Set("Status: RUNNING - " .. AC_State.selectedGear.name)
        else
            AC_State.running = false
            acStatus:Set("Status: OFF (Total: " .. AC_State.loopCount .. ")")
        end
    end,
})

--============================================================
-- TAB AUTO MUTASI
--============================================================
local MutTab = Window:CreateTab("Auto Mutasi", 4483362458)

local LOCKED_MUTATIONS = { diamond = true }
local function isLockedMutation(mutName)
    if not mutName or mutName == "" then return false end
    local n = string.lower(string.gsub(tostring(mutName), "^%s*(.-)%s*$", "%1"))
    return LOCKED_MUTATIONS[n] == true
end
local function normalizeMutation(name)
    if not name or name == "" then return "none" end
    return string.lower(string.gsub(tostring(name), "^%s*(.-)%s*$", "%1"))
end
local function safeRequire(path, ...)
    local ok, mod = pcall(require, path, ...)
    if ok then return mod end
    return nil
end

local BCONFIG = {
    TargetAge = 50, MaxPlacePerWave = 4, JumperInterval = 3,
    WaitAfterPlace = 0.5, JumperCooldown = 1.5, MutationCooldown = 2,
    BoostLoadout = 1, MutationInsertLoadout = 0,
    MutationWaitingLoadout = 3, MutationCollectLoadout = 0,
    LoadoutSwitchDelay = 1.5, MutationCollectSyncDelay = 1.5,
    MaxCyclesBeforeStop = 999, JumperBeforeSwitch = 3,
    JumperSwitchLoadoutA = 1, JumperSwitchLoadoutB = 0, JumperSwitchDelay = 1.5,
}
local ALL_MUTATIONS = { "Diamond", "Silver", "Radiant", "Huge", "Lightning", "Guardian", "Gold", "Tiny", "Aquatic", "Tamed" }
local COOKIE_DIAMOND = "DiamondCookie"
local COOKIE_XP      = "XpCookie"
local COOKIE_REFRESH_TIME = 600

local B = {
    isRunning = false, currentWave = {}, wavePhase = "idle",
    placedPets = {}, pickedUpPets = {}, selectedMutations = {},
    mutationInProgress = {}, processedMutation = {},
    lastMutationAction = 0, currentLoadout = nil, lastLoadoutSwitch = 0,
    totalBoosted = 0, totalMutated = 0, cycleCount = 0,
    jumperCounter = 0, lastJumperFire = 0,
    boostJumperCount = 0, boostLoadoutSwitching = false,
    selectedPets = {}, petList = {}, petById = {},
}

local playerDataMod = safeRequire(RS.TS.state["player-data"])
local petAgeMod     = safeRequire(RS.TS.utils["pet-age.utils"])

local invStateGear = nil
pcall(function()
    invStateGear = require(player.PlayerScripts.TS.ui.features.toolbar["inventory.state"])
end)

local function getRemote(name)
    local ok, remote = pcall(function()
        return RS:WaitForChild("rbxts_include", 10):WaitForChild("node_modules", 10)
            :WaitForChild("@rbxts", 10):WaitForChild("remo", 10)
            :WaitForChild("src", 10):WaitForChild("container", 10):WaitForChild(name, 10)
    end)
    return ok and remote or nil
end

local useTimeWatch          = getRemote("gear.useTimeWatch")
local equipTool             = getRemote("tools.equipTool")
local placePetFromInventory = getRemote("pets.placePetFromInventory")
local requestPosition       = getRemote("pets.requestPosition")
local pickUpPet             = getRemote("pets.pickUpPet")
local switchPetLoadout      = getRemote("pets.switchPetLoadout")
local startMutation         = getRemote("pets.startMutation")
local collectMutation       = getRemote("pets.collectMutation")
local usePetGearOnPet       = getRemote("pets.usePetGearOnPet")

local function getData()
    if not playerDataMod then return nil end
    local ok, d = pcall(function() return playerDataMod.getPlayerDataById(tostring(player.UserId)) end)
    return ok and d or nil
end

local function getPetAge(pd)
    if not petAgeMod or not pd then return 0 end
    local ok, age = pcall(petAgeMod.getPetAgeFromData, pd)
    return ok and (age or 0) or 0
end

local function getPetMutation(pd)
    if not pd then return "None" end
    local c = { pd.mutation, pd.mutations, pd.mutationType, pd.mutationName, pd.attributes and pd.attributes.mutation }
    for _, m in ipairs(c) do
        if m and m ~= "" and m ~= "None" then
            if type(m) == "table" then
                for _, v in pairs(m) do
                    if v and v ~= "" and v ~= "None" then return tostring(v) end
                end
            else return tostring(m) end
        end
    end
    return "None"
end

local function getJumperCount()
    local data = getData()
    if not data or not data.inventory or not data.inventory.gears then return 0 end
    local tj = data.inventory.gears.TimeJumper
    return tj and (tj.amount or 0) or 0
end

local function getPlayerDisplayName()
    return player.DisplayName or player.Name or "Unknown"
end

-- === FUNGSI BERAT PET (DARI DECOMPILE) ===
local function getFormattedPetWeight(pd)
    if not petAgeUtils or not petAgeUtils.calculatePetWeight then return "0.0kg" end
    local ok, weight = pcall(petAgeUtils.calculatePetWeight, pd)
    if not ok or not weight then return "0.0kg" end
    
    if petAgeUtils.formatPetWeight then
        local ok2, formatted = pcall(petAgeUtils.formatPetWeight, weight)
        if ok2 and formatted then return formatted end
    end
    
    if weight >= 1000 then
        return string.format("%.2ft", weight / 1000)
    else
        return string.format("%.2fkg", weight)
    end
end

-- === PERBAIKAN: KIRIM WEBHOOK SESUAI TARGET ===
local function sendMutationWebhook(petName, petWeightStr, mutationName, jumperLeft)
    local isTarget = false
    local nMut = normalizeMutation(mutationName)
    
    for target in pairs(B.selectedMutations) do
        if normalizeMutation(target) == nMut then
            isTarget = true
            break
        end
    end

    if not isTarget then return end

    local embed = {
        title = "🧬 Mutation Result (Target Tercapai!)",
        color = 0x9B59B6,
        fields = {
            { name = "👤 Player", value = tostring(getPlayerDisplayName()), inline = true },
            { name = "🐾 Pet", value = tostring(petName), inline = true },
            { name = "⚖️ Berat Pet", value = tostring(petWeightStr), inline = true },
            { name = "✨ Mutasi Didapat", value = tostring(mutationName or "None"), inline = true },
            { name = "⏱️ TimeJumper Sisa", value = tostring(jumperLeft), inline = true },
        },
        footer = { text = "Farm A fish | by bang iqi" },
        timestamp = DateTime.now():ToIsoDate(),
    }
    sendWebhook({
        username = WEBHOOK.username,
        embeds = { embed },
    })
end

local function sendJumperEmptyWebhook(jumperLeft)
    local embed = {
        title = "⚠️ TIMEJUMPER HABIS",
        description = "TimeJumper di inventory sudah habis. Auto mutasi akan berhenti sampai kamu craft / isi ulang.",
        color = 0xE74C3C,
        fields = {
            { name = "👤 Player", value = tostring(getPlayerDisplayName()), inline = true },
            { name = "⏱️ Sisa TimeJumper", value = tostring(jumperLeft or 0), inline = true },
        },
        footer = { text = "Farm A fish | by bang iqi" },
        timestamp = DateTime.now():ToIsoDate(),
    }
    sendWebhook({
        username = WEBHOOK.username,
        embeds = { embed },
    })
end

local function buildNameMap()
    local map = {}
    if not invStateGear then return map end
    local ok, stacked = pcall(function() return invStateGear.inventoryStackedData() end)
    if not ok or not stacked then return map end
    for _, item in pairs(stacked) do
        local tt = tostring(item.toolType):lower()
        if tt:find("pet") and item.items and item.items[1] then
            local pid = item.items[1].id
            if pid then map[pid] = item.displayName or item.itemName or tostring(pid) end
        end
    end
    return map
end

local function switchLoadout(idx)
    if B.currentLoadout == idx then return true end
    if not switchPetLoadout then return false end
    local now = os.clock()
    local elapsed = now - B.lastLoadoutSwitch
    if elapsed < BCONFIG.LoadoutSwitchDelay then task.wait(BCONFIG.LoadoutSwitchDelay - elapsed) end
    local ok = pcall(function() switchPetLoadout:InvokeServer(idx) end)
    if ok then
        B.currentLoadout = idx; B.lastLoadoutSwitch = os.clock()
        task.wait(BCONFIG.LoadoutSwitchDelay)
        return true
    end
    return false
end

local function ensureLoadout(idx)
    if B.currentLoadout == idx then return true end
    return switchLoadout(idx)
end

local function hasSelected()
    for _ in pairs(B.selectedMutations) do return true end
    return false
end

local function isDesired(m)
    if not hasSelected() then return false end
    local n = normalizeMutation(m)
    if n == "none" or n == "" then return false end
    for t in pairs(B.selectedMutations) do
        if normalizeMutation(t) == n then return true end
    end
    return false
end

local function getMachineState()
    local labels = CollectionService:GetTagged("petMutationLabel")
    if #labels == 0 then return "Unknown" end
    local text = labels[1].Text
    if text == "MUTATION" or text == "" then return "Idle"
    elseif text == "READY!" then return "Ready"
    else return "InProgress" end
end

local function isPetSelected(id) return B.selectedPets[id] == true end

local function gearPetLabel(p, idx)
    local mut = (p.mutation and p.mutation ~= "" and p.mutation ~= "None") and p.mutation or "No Mutation"
    local ageStr = string.format("%.1f", p.age or 0)
    local suffix = idx and string.format("  #%d", idx) or ""
    return string.format("%s | %s | Age %s%s", p.displayName, mut, ageStr, suffix)
end

local function getCookieTimeLeft(petId, pd, cookieName)
    if not pd or not pd.activeGearBuffs then return false, 0 end
    local expireTime = pd.activeGearBuffs[cookieName]
    if expireTime then
        local timeLeft = expireTime - os.time()
        if timeLeft > 0 then return true, timeLeft else return false, 0 end
    end
    return false, 0
end

local function needsCookie(petId, cookieName)
    local data = getData()
    if not data or not data.inventory or not data.inventory.pets[petId] then return false end
    local pd = data.inventory.pets[petId]
    local has, timeLeft = getCookieTimeLeft(petId, pd, cookieName)
    return not has or timeLeft <= COOKIE_REFRESH_TIME
end

local function giveCookie(petId, cookieName)
    local data = getData()
    if not data or not data.inventory or not data.inventory.gears then return false end
    local inv = data.inventory.gears[cookieName]
    if not inv or (inv.amount or 0) <= 0 then
        warn("[Cookie] Gear habis di inventory:", cookieName); return false
    end
    if equipTool then pcall(function() equipTool:FireServer(cookieName, "gear") end) end
    task.wait(0.5)
    local success = false
    if usePetGearOnPet then success = pcall(function() usePetGearOnPet:FireServer(petId) end) end
    if success then print("[Cookie] BERHASIL:", cookieName, "->", petId) else warn("[Cookie] GAGAL:", cookieName) end
    task.wait(0.5)
    return success
end

local function scanAllPetsForList()
    local data = getData(); if not data then return {} end
    if not data.inventory or not data.inventory.pets then return {} end
    local nameMap = buildNameMap()
    local list = {}
    for id, pd in pairs(data.inventory.pets) do
        local m = getPetMutation(pd)
        if not isLockedMutation(m) then
            local age = getPetAge(pd)
            local name = nameMap[id]
            if not name or name == "" or name == tostring(id) then
                name = pd.name or pd.displayName or pd.petName
                    or pd.petType or pd.type or pd.species or pd.model
                    or (pd.attributes and (pd.attributes.name or pd.attributes.displayName or pd.attributes.petName))
                    or tostring(id)
            end
            table.insert(list, {id=id, age=age, mutation=m, displayName=tostring(name), protected=isDesired(m)})
        end
    end
    table.sort(list, function(a, b)
        if a.displayName ~= b.displayName then return a.displayName < b.displayName end
        return a.age < b.age
    end)
    for i, p in ipairs(list) do p.label = gearPetLabel(p, i) end
    return list
end

local function scanLowAge()
    local data = getData(); if not data or not data.inventory then return {} end
    local list = {}
    for id, pd in pairs(data.inventory.pets) do
        if isPetSelected(id) then
            local m = getPetMutation(pd)
            if not isLockedMutation(m) then
                local age = getPetAge(pd)
                if not isDesired(m) and age < BCONFIG.TargetAge then
                    table.insert(list, { id = id, age = age })
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.age < b.age end)
    return list
end

local function scanForMutation()
    local data = getData(); if not data or not data.inventory then return {} end
    local list = {}
    for id, pd in pairs(data.inventory.pets) do
        if isPetSelected(id) then
            local m = getPetMutation(pd)
            if not isLockedMutation(m) then
                local age = getPetAge(pd)
                if not isDesired(m) and age >= BCONFIG.TargetAge
                    and not B.processedMutation[id] and not B.mutationInProgress[id] then
                    table.insert(list, { id = id, age = age })
                end
            end
        end
    end
    return list
end

local function countWave()
    local c, t = 0, 0
    local data = getData(); if not data or not data.inventory then return 0, 0 end
    for id in pairs(B.currentWave) do
        t = t + 1
        local pd = data.inventory.pets[id]
        if pd and getPetAge(pd) >= BCONFIG.TargetAge then c = c + 1 end
    end
    return c, t
end

local function hasMoreBoost() return #scanLowAge() > 0 end
local function hasMoreMutate() return #scanForMutation() > 0 end

local function allPetsMaxed()
    local data = getData(); if not data or not data.inventory then return false end
    local any = false
    for id, pd in pairs(data.inventory.pets) do
        if isPetSelected(id) then
            local m = getPetMutation(pd)
            if not isLockedMutation(m) and not isDesired(m) then
                any = true
                if getPetAge(pd) < BCONFIG.TargetAge then return false end
            end
        end
    end
    return any
end

local function allPetsAchieved()
    local data = getData(); if not data or not data.inventory then return false end
    local t, tar = 0, 0
    for id, pd in pairs(data.inventory.pets) do
        if isPetSelected(id) and not isLockedMutation(getPetMutation(pd)) then
            t = t + 1
            if isDesired(getPetMutation(pd)) then tar = tar + 1 end
        end
    end
    return t > 0 and tar >= t
end

local function placePet(id)
    if B.placedPets[id] then return true end
    local data = getData()
    if not data or not data.inventory or not data.inventory.pets[id] then B.placedPets[id] = true; return true end
    if isLockedMutation(getPetMutation(data.inventory.pets[id])) then return false end
    if equipTool then pcall(function() equipTool:FireServer(id, "pet") end) end
    task.wait(BCONFIG.WaitAfterPlace)
    local ok = false
    if placePetFromInventory then ok = pcall(function() placePetFromInventory:InvokeServer(id) end) end
    task.wait(BCONFIG.WaitAfterPlace)
    if ok and requestPosition then pcall(function() requestPosition:InvokeServer(id) end) end
    task.wait(0.3)
    B.placedPets[id] = true; B.pickedUpPets[id] = nil
    return ok
end

local function pickUp(id)
    if B.pickedUpPets[id] then return true end
    if not pickUpPet then return false end
    local ok = pcall(function() pickUpPet:InvokeServer(id) end)
    if not ok then return false end
    B.pickedUpPets[id] = true; B.placedPets[id] = nil
    return true
end

local function fireJumper(force)
    local now = os.clock()
    if not force and (now - B.lastJumperFire) < BCONFIG.JumperCooldown then return false end
    if B.currentLoadout ~= BCONFIG.JumperSwitchLoadoutA then return false end

    local data = getData()
    if not data or not data.inventory or not data.inventory.gears then return false end
    local tj = data.inventory.gears.TimeJumper
    local amount = tj and (tj.amount or 0) or 0

    if amount <= 0 then
        if WEBHOOK.notifyJumperEmpty then
            local now2 = os.time()
            if now2 - (WEBHOOK.lastJumperEmptyNotify or 0) > 120 then
                WEBHOOK.lastJumperEmptyNotify = now2
                sendJumperEmptyWebhook(0)
            end
        end
        return false
    end

    if not useTimeWatch then return false end
    local ok = pcall(function() useTimeWatch:FireServer("TimeJumper") end)
    if ok then
        B.lastJumperFire = now
        B.jumperCounter = B.jumperCounter + 1
        B.boostJumperCount = B.boostJumperCount + 1

        local data2 = getData()
        local left = 0
        if data2 and data2.inventory and data2.inventory.gears and data2.inventory.gears.TimeJumper then
            left = data2.inventory.gears.TimeJumper.amount or 0
        end
        if left <= 0 and WEBHOOK.notifyJumperEmpty then
            local now2 = os.time()
            if now2 - (WEBHOOK.lastJumperEmptyNotify or 0) > 120 then
                WEBHOOK.lastJumperEmptyNotify = now2
                sendJumperEmptyWebhook(left)
            end
        end
        return true
    end
    return false
end

local function doLoadoutCycle()
    if B.boostLoadoutSwitching then return end
    B.boostLoadoutSwitching = true
    ensureLoadout(BCONFIG.JumperSwitchLoadoutB); task.wait(BCONFIG.JumperSwitchDelay)
    ensureLoadout(BCONFIG.JumperSwitchLoadoutA); task.wait(BCONFIG.JumperSwitchDelay)
    B.boostJumperCount = 0; B.boostLoadoutSwitching = false
end

local function resetWave() B.currentWave = {}; B.wavePhase = "idle" end

local function placeNewWave()
    ensureLoadout(BCONFIG.BoostLoadout)
    local cands = scanLowAge()
    if #cands == 0 then B.wavePhase = "done"; return false end
    local toPlace = {}
    for i = 1, math.min(BCONFIG.MaxPlacePerWave, #cands) do table.insert(toPlace, cands[i]) end
    B.currentWave = {}; B.wavePhase = "placing"
    local sc = 0
    for _, p in ipairs(toPlace) do
        local petId = p.id
        local needDiamond = needsCookie(petId, COOKIE_DIAMOND)
        local needXP = needsCookie(petId, COOKIE_XP)
        local ok = placePet(petId)
        if ok ~= false then
            B.currentWave[petId] = true
            sc = sc + 1
            if needDiamond or needXP then
                task.wait(0.5)
                if needDiamond then giveCookie(petId, COOKIE_DIAMOND) end
                if needXP then giveCookie(petId, COOKIE_XP) end
            end
        end
        task.wait(0.2)
    end
    if sc == 0 then B.wavePhase = "done"; return false end
    B.boostJumperCount = 0; B.wavePhase = "boosting"
    return true
end

local function pickUpWave()
    for id in pairs(B.currentWave) do
        if pickUp(id) then B.totalBoosted = B.totalBoosted + 1 end
        task.wait(0.3)
    end
    resetWave()
end

local function insertPet(id)
    local data = getData()
    if not data or not data.inventory or not data.inventory.pets[id] then return false end
    if isLockedMutation(getPetMutation(data.inventory.pets[id])) then return false end
    if equipTool then pcall(function() equipTool:FireServer(id, "pet") end) end
    task.wait(0.5)
    if not startMutation then return false end
    local ok = pcall(function() startMutation:InvokeServer(id) end)
    if ok then
        B.mutationInProgress[id] = true; B.processedMutation[id] = true
        return true
    end
    return false
end

local function doMutation()
    local now = os.clock()
    if (now - B.lastMutationAction) < BCONFIG.MutationCooldown then return end
    local state = getMachineState()

    if state == "Ready" then
        if not ensureLoadout(BCONFIG.MutationCollectLoadout) then return end
        local col = {}
        for id in pairs(B.mutationInProgress) do table.insert(col, id) end
        if not collectMutation then return end
        
        local ok = pcall(function() collectMutation:InvokeServer() end)
        if ok then
            task.wait(BCONFIG.MutationCollectSyncDelay + 0.5)
            local data = getData()
            if data and data.inventory and data.inventory.pets then
                for _, id in ipairs(col) do
                    local pd = data.inventory.pets[id]
                    if pd then
                        local petName = pd.name or pd.displayName or pd.petName
                            or pd.petType or pd.type or pd.species or pd.model
                            or (pd.attributes and (pd.attributes.name or pd.attributes.displayName))
                            or tostring(id)
                        
                        local petWeightStr = getFormattedPetWeight(pd)
                        local mutName = getPetMutation(pd)
                        local jumperLeft = getJumperCount()
                        
                        sendMutationWebhook(tostring(petName), petWeightStr, tostring(mutName), jumperLeft)
                        
                        if jumperLeft <= 0 and WEBHOOK.notifyJumperEmpty then
                            sendJumperEmptyWebhook(jumperLeft)
                        end
                    end
                end
            end

            for _, id in ipairs(col) do
                B.totalMutated = B.totalMutated + 1; B.processedMutation[id] = nil
            end
            B.mutationInProgress = {}; B.lastMutationAction = now
        end
        return
    end

    if state == "InProgress" then
        if B.currentLoadout ~= BCONFIG.MutationWaitingLoadout then ensureLoadout(BCONFIG.MutationWaitingLoadout) end
        return
    end

    if state == "Idle" then
        if next(B.mutationInProgress) ~= nil then B.mutationInProgress = {} end
        local cands = scanForMutation()
        if #cands == 0 then B.wavePhase = "idle"; return end
        if not ensureLoadout(BCONFIG.MutationInsertLoadout) then return end
        if insertPet(cands[1].id) then
            B.lastMutationAction = now
            task.wait(0.5)
            ensureLoadout(BCONFIG.MutationWaitingLoadout)
        end
    end
end

local function boostLoop()
    ensureLoadout(BCONFIG.BoostLoadout)
    while B.isRunning do
        task.wait(BCONFIG.JumperInterval)
        local data = getData(); if not data then continue end
        if allPetsAchieved() and next(B.currentWave) == nil then
            B.wavePhase = "stopped"; B.isRunning = false; break
        end
        if B.cycleCount >= BCONFIG.MaxCyclesBeforeStop then
            B.wavePhase = "stopped"; B.isRunning = false; break
        end
        if B.wavePhase ~= "mutating" and allPetsMaxed() and next(B.currentWave) == nil then
            if hasMoreMutate() then
                B.wavePhase = "mutating"; ensureLoadout(BCONFIG.MutationInsertLoadout)
            else
                task.wait(10); B.wavePhase = "idle"
            end
        end
        if B.wavePhase == "mutating" then
            if hasMoreMutate() or getMachineState() == "Ready" or getMachineState() == "InProgress" then
                doMutation()
            else
                if allPetsAchieved() then B.wavePhase = "stopped"; B.isRunning = false; break end
                B.cycleCount = B.cycleCount + 1; B.wavePhase = "idle"
                ensureLoadout(BCONFIG.BoostLoadout)
            end
            continue
        end
        if B.wavePhase == "idle" or B.wavePhase == "done" then
            if hasMoreBoost() then placeNewWave()
            elseif next(B.currentWave) ~= nil then
                local c, t = countWave()
                if t > 0 and c >= t then pickUpWave() end
            end
        elseif B.wavePhase == "placing" then
            B.wavePhase = "boosting"
        elseif B.wavePhase == "boosting" then
            local c, t = countWave()
            if t > 0 and c >= t then
                pickUpWave(); B.boostJumperCount = 0
            else
                if B.boostJumperCount >= BCONFIG.JumperBeforeSwitch and not B.boostLoadoutSwitching then
                    doLoadoutCycle()
                else
                    if B.currentLoadout ~= BCONFIG.JumperSwitchLoadoutA then ensureLoadout(BCONFIG.JumperSwitchLoadoutA) end
                    fireJumper(false)
                end
            end
        end
    end
end

MutTab:CreateSection("Mode Mutasi")

MutTab:CreateToggle({
    Name = "Aktifkan", CurrentValue = false, Flag = "BoostToggle",
    Callback = function(state)
        B.isRunning = state
        if B.isRunning then
            if next(B.selectedPets) == nil then warn("Pilih pet dulu!"); return end
            if not hasSelected() then warn("Pilih target mutasi dulu!"); return end
            resetWave()
            B.placedPets = {}; B.pickedUpPets = {}
            B.mutationInProgress = {}; B.processedMutation = {}
            B.currentLoadout = nil; B.lastLoadoutSwitch = 0
            B.totalBoosted = 0; B.totalMutated = 0; B.cycleCount = 0
            B.jumperCounter = 0; B.lastJumperFire = 0; B.lastMutationAction = 0
            B.boostJumperCount = 0; B.boostLoadoutSwitching = false
            task.spawn(boostLoop)
        end
    end,
})

MutTab:CreateDropdown({
    Name = "Target Mutasi",
    Options = ALL_MUTATIONS, CurrentOption = {}, MultipleOptions = true,
    Callback = function(sel)
        B.selectedMutations = {}
        for _, m in ipairs(sel) do B.selectedMutations[m] = true end
    end,
})

local gearPetDropdownOptions = {}
local labelToId = {}

local gearPetDropdown = MutTab:CreateDropdown({
    Name = "Pilih Pet (dari inventory)",
    Options = {}, CurrentOption = {}, MultipleOptions = true,
    Callback = function(sel)
        B.selectedPets = {}
        for _, lbl in ipairs(sel) do
            local id = labelToId[lbl]
            if id then B.selectedPets[id] = true end
        end
    end,
})

MutTab:CreateButton({
    Name = "Scan Pet",
    Callback = function()
        if B.isRunning then warn("Stop dulu sebelum scan."); return end
        local pets = scanAllPetsForList()
        B.petList = pets
        B.petById = {}
        gearPetDropdownOptions = {}
        labelToId = {}
        local keepSelectedIds = {}
        for id in pairs(B.selectedPets) do keepSelectedIds[id] = true end
        B.selectedPets = {}
        local currentLabels = {}
        for _, p in ipairs(pets) do
            B.petById[p.id] = p
            table.insert(gearPetDropdownOptions, p.label)
            labelToId[p.label] = p.id
            if keepSelectedIds[p.id] then
                B.selectedPets[p.id] = true
                table.insert(currentLabels, p.label)
            end
        end
        for id in pairs(B.selectedPets) do
            if not B.petById[id] then B.selectedPets[id] = nil end
        end
        pcall(function()
            gearPetDropdown:Refresh(gearPetDropdownOptions)
            if #currentLabels > 0 then gearPetDropdown:Set(currentLabels) end
        end)
    end,
})

MutTab:CreateButton({
    Name = "✅ Select All Pet",
    Callback = function()
        if #gearPetDropdownOptions == 0 then
            warn("[SelectAll] Scan pet dulu sebelum select all.")
            return
        end
        if B.isRunning then warn("[SelectAll] Stop dulu sebelum ubah selection."); return end
        B.selectedPets = {}
        local allLabels = {}
        for _, lbl in ipairs(gearPetDropdownOptions) do
            local id = labelToId[lbl]
            if id then
                B.selectedPets[id] = true
                table.insert(allLabels, lbl)
            end
        end
        pcall(function() gearPetDropdown:Set(allLabels) end)
        print(string.format("[SelectAll] %d pet dipilih", #allLabels))
    end,
})

MutTab:CreateButton({
    Name = "❌ Clear All Pet",
    Callback = function()
        if B.isRunning then warn("[ClearAll] Stop dulu sebelum ubah selection."); return end
        B.selectedPets = {}
        pcall(function() gearPetDropdown:Set({}) end)
        print("[ClearAll] Semua pet di-unselect")
    end,
})

local mutStatus = MutTab:CreateLabel("Status: IDLE")

task.spawn(function()
    while true do
        task.wait(1)
        local c, t = countWave()
        local mq = #scanForMutation()
        local mi = 0
        for _ in pairs(B.mutationInProgress) do mi = mi + 1 end
        local prot, locked = 0, 0
        local data = getData()
        if data and data.inventory then
            for id, pd in pairs(data.inventory.pets) do
                local m = getPetMutation(pd)
                if isLockedMutation(m) then locked = locked + 1
                elseif B.selectedPets[id] and isDesired(m) then prot = prot + 1 end
            end
        end
        pcall(function()
            mutStatus:Set(string.format(
                "%s | Wave %d/%d | Queue %d | Prog %d | Mut %d | Prot %d | Locked %d | LO %s | Jump %d/%d",
                B.wavePhase:upper(), c, t, mq, mi, B.totalMutated, prot, locked,
                tostring(B.currentLoadout), B.boostJumperCount, BCONFIG.JumperBeforeSwitch))
        end)
    end
end)

--============================================================
-- TAB BOOST
--============================================================
local BoostTab = Window:CreateTab("Boost", 4483362458)

local FPS_STATE = {
    boosted = false, originalSettings = {}, hiddenObjects = {},
    terrainSettings = {}, fishHidden = false, hiddenFish = {},
    mutedSounds = {}, materialCache = {},
}
local Terrain = workspace:FindFirstChildOfClass("Terrain")
local function safeGetChildren(p) local ok, c = pcall(function() return p:GetChildren() end) if ok and c then return c end return {} end
local function safeGetDescendants(p) local ok, c = pcall(function() return p:GetDescendants() end) if ok and c then return c end return {} end

local function saveOriginalSettings()
    FPS_STATE.originalSettings = {
        GlobalShadows = Lighting.GlobalShadows, ShadowSoftness = Lighting.ShadowSoftness,
        Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient, FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart, FogColor = Lighting.FogColor,
        EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
        EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
        ExposureCompensation = Lighting.ExposureCompensation,
        ClockTime = Lighting.ClockTime,
        QualityLevel = UserSettings().GameSettings.SavedQualityLevel.Value,
    }
    if Terrain then
        pcall(function()
            FPS_STATE.terrainSettings = {
                WaterWaveSize = Terrain.WaterWaveSize, WaterWaveSpeed = Terrain.WaterWaveSpeed,
                WaterReflectance = Terrain.WaterReflectance, WaterTransparency = Terrain.WaterTransparency,
                Decoration = Terrain.Decoration,
            }
        end)
    end
end

local function hideHeavyObject(o, char)
    if not o or not o.Parent then return end
    if char and (o == char or o:IsDescendantOf(char)) then return end
    local cls = o.ClassName
    if cls == "ParticleEmitter" or cls == "Trail" or cls == "Beam"
       or cls == "Fire" or cls == "Smoke" or cls == "Sparkles"
       or cls == "PointLight" or cls == "SpotLight" or cls == "SurfaceLight"
       or cls == "Explosion" or cls == "Atmosphere" or cls == "Sky" then
        pcall(function()
            if o.Enabled then
                o.Enabled = false
                table.insert(FPS_STATE.hiddenObjects, {obj = o, prop = "Enabled", val = true})
            end
        end)
    elseif cls == "Decal" or cls == "Texture" then
        pcall(function()
            if o.Transparency < 1 then
                table.insert(FPS_STATE.hiddenObjects, {obj = o, prop = "Transparency", val = o.Transparency})
                o.Transparency = 1
            end
        end)
    elseif cls == "MeshPart" then
        pcall(function()
            if o.TextureID ~= "" then
                table.insert(FPS_STATE.hiddenObjects, {obj = o, prop = "TextureID", val = o.TextureID})
                o.TextureID = ""
            end
            if o.Material ~= Enum.Material.SmoothPlastic then
                table.insert(FPS_STATE.materialCache, {obj = o, prop = "Material", val = o.Material})
                o.Material = Enum.Material.SmoothPlastic
            end
        end)
    elseif cls == "SurfaceAppearance" then
        pcall(function()
            if o.Enabled then
                table.insert(FPS_STATE.hiddenObjects, {obj = o, prop = "Enabled", val = true})
                o.Enabled = false
            end
        end)
    elseif cls == "BasePart" then
        pcall(function()
            if o.Material ~= Enum.Material.SmoothPlastic then
                table.insert(FPS_STATE.materialCache, {obj = o, prop = "Material", val = o.Material})
                o.Material = Enum.Material.SmoothPlastic
            end
            if o.CastShadow then
                table.insert(FPS_STATE.hiddenObjects, {obj = o, prop = "CastShadow", val = true})
                o.CastShadow = false
            end
        end)
    end
end

local function boostFPS()
    if FPS_STATE.boosted then return false end
    local ok = pcall(function()
        saveOriginalSettings()
        FPS_STATE.boosted = true
        FPS_STATE.hiddenObjects = {} FPS_STATE.mutedSounds = {} FPS_STATE.materialCache = {}
        Lighting.GlobalShadows = false
        Lighting.ShadowSoftness = 0
        Lighting.Brightness = 1
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.FogEnd = 1e6
        Lighting.FogStart = 1e6
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        Lighting.ExposureCompensation = 0
        Lighting.ClockTime = 14
        for _, e in ipairs(safeGetChildren(Lighting)) do
            pcall(function()
                if e:IsA("PostEffect") or e:IsA("Atmosphere") or e:IsA("Sky") then
                    if e.Enabled ~= nil then
                        e.Enabled = false
                        table.insert(FPS_STATE.hiddenObjects, {obj = e, prop = "Enabled", val = true})
                    end
                end
            end)
        end
        if Terrain then
            pcall(function()
                Terrain.WaterWaveSize = 0
                Terrain.WaterWaveSpeed = 0
                Terrain.WaterReflectance = 0
                Terrain.WaterTransparency = 1
                Terrain.Decoration = false
            end)
        end
        pcall(function()
            UserSettings().GameSettings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
        end)
        local char = player.Character
        for _, o in ipairs(safeGetDescendants(workspace)) do hideHeavyObject(o, char) end
        for _, s in ipairs(safeGetDescendants(workspace)) do
            pcall(function()
                if s:IsA("Sound") and s.Playing then
                    s.Playing = false
                    table.insert(FPS_STATE.mutedSounds, s)
                end
            end)
        end
    end)
    if not ok then FPS_STATE.boosted = false return false end
    return true
end

local function unboostFPS()
    if not FPS_STATE.boosted then return false end
    FPS_STATE.boosted = false
    pcall(function()
        local o = FPS_STATE.originalSettings or {}
        Lighting.GlobalShadows = o.GlobalShadows ~= false
        Lighting.ShadowSoftness = o.ShadowSoftness or 0.2
        Lighting.Brightness = o.Brightness or 2
        Lighting.Ambient = o.Ambient or Color3.fromRGB(70, 70, 70)
        Lighting.OutdoorAmbient = o.OutdoorAmbient or Color3.fromRGB(128, 128, 128)
        Lighting.FogEnd = o.FogEnd or 100000
        Lighting.FogStart = o.FogStart or 0
        Lighting.FogColor = o.FogColor or Color3.fromRGB(192, 192, 192)
        Lighting.EnvironmentDiffuseScale = o.EnvironmentDiffuseScale or 1
        Lighting.EnvironmentSpecularScale = o.EnvironmentSpecularScale or 1
        Lighting.ExposureCompensation = o.ExposureCompensation or 0
        Lighting.ClockTime = o.ClockTime or 14
        if Terrain and FPS_STATE.terrainSettings then
            local t = FPS_STATE.terrainSettings
            Terrain.WaterWaveSize = t.WaterWaveSize or 0.15
            Terrain.WaterWaveSpeed = t.WaterWaveSpeed or 10
            Terrain.WaterReflectance = t.WaterReflectance or 0.1
            Terrain.WaterTransparency = t.WaterTransparency or 0.3
            Terrain.Decoration = t.Decoration ~= false
        end
        for _, e in ipairs(FPS_STATE.hiddenObjects) do
            pcall(function()
                if e.obj and e.obj.Parent then e.obj[e.prop] = e.val end
            end)
        end
        FPS_STATE.hiddenObjects = {}
        for _, m in ipairs(FPS_STATE.materialCache) do
            pcall(function()
                if m.obj and m.obj.Parent then m.obj[m.prop] = m.val end
            end)
        end
        FPS_STATE.materialCache = {}
        for _, s in ipairs(FPS_STATE.mutedSounds) do
            pcall(function()
                if s and s.Parent then s.Playing = true end
            end)
        end
        FPS_STATE.mutedSounds = {}
        pcall(function()
            UserSettings().GameSettings.SavedQualityLevel = o.QualityLevel or Enum.SavedQualitySetting.QualityLevel5
        end)
    end)
    return true
end

local function hideFish()
    if FPS_STATE.fishHidden then return 0 end
    FPS_STATE.hiddenFish = {}
    local count = 0
    local gameFolder = workspace:FindFirstChild("Game")
    if gameFolder then
        table.insert(FPS_STATE.hiddenFish, {obj = gameFolder, parent = gameFolder.Parent, type = "folder"})
        pcall(function() gameFolder.Parent = nil end)
        count += 1
    end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Parent then
            if obj.Parent.Name:lower():find("pond") then
                local n = obj.Name:lower()
                if n == "sardine" or n == "cod" or n == "salmon"
                   or n:find("_gold") or n:find("_silver") then
                    table.insert(FPS_STATE.hiddenFish, {obj = obj, parent = obj.Parent, type = "model"})
                    pcall(function() obj.Parent = nil end)
                    count += 1
                end
            end
        end
    end
    FPS_STATE.fishHidden = true
    return count
end

local function showFish()
    if not FPS_STATE.fishHidden then return 0 end
    local count = 0
    for _, entry in ipairs(FPS_STATE.hiddenFish) do
        if entry.obj then
            pcall(function()
                entry.obj.Parent = entry.parent or workspace
                count += 1
            end)
        end
    end
    FPS_STATE.hiddenFish = {}
    FPS_STATE.fishHidden = false
    return count
end

BoostTab:CreateToggle({
    Name = "Super FPS Boost", CurrentValue = false, Flag = "SuperFPSBoost",
    Callback = function(v)
        task.spawn(function()
            if v and not FPS_STATE.boosted then boostFPS()
            elseif not v and FPS_STATE.boosted then unboostFPS() end
        end)
    end,
})
BoostTab:CreateToggle({
    Name = "Hide Fish", CurrentValue = false, Flag = "HideFish",
    Callback = function(v)
        task.spawn(function()
            if v and not FPS_STATE.fishHidden then hideFish()
            elseif not v and FPS_STATE.fishHidden then showFish() end
        end)
    end,
})

--============================================================
-- TAB WEBHOOK
--============================================================
local WebhookTab = Window:CreateTab("Webhook", 4483362458)

WebhookTab:CreateSection("Konfigurasi Webhook")

WebhookTab:CreateInput({
    Name = "Webhook URL",
    CurrentValue = WEBHOOK.url,
    PlaceholderText = "https://discord.com/api/webhooks/...",
    RemoveTextAfterFocusLost = false,
    Flag = "WebhookURL_Input",
    Callback = function(text)
        WEBHOOK.url = text
    end,
})

WebhookTab:CreateToggle({
    Name = "Aktifkan Webhook",
    CurrentValue = WEBHOOK.enabled,
    Flag = "WebhookEnabled",
    Callback = function(v) WEBHOOK.enabled = v end,
})

WebhookTab:CreateToggle({
    Name = "Notif TimeJumper Habis",
    CurrentValue = WEBHOOK.notifyJumperEmpty,
    Flag = "WebhookJumperEmpty",
    Callback = function(v) WEBHOOK.notifyJumperEmpty = v end,
})

WebhookTab:CreateButton({
    Name = "🧪 Test Webhook",
    Callback = function()
        if WEBHOOK.url == "" then
            warn("[Webhook] URL kosong. Paste link dulu di kotak atas.")
            return
        end
        local embed = {
            title = "🧪 Test Webhook Berhasil",
            description = "Koneksi dari Farm A fish berjalan dengan baik!",
            color = 0x00FF00,
            fields = {
                { name = "👤 Player", value = tostring(getPlayerDisplayName()), inline = true },
                { name = "⏱️ TimeJumper Sisa", value = tostring(getJumperCount()), inline = true },
            },
            footer = { text = "Farm A fish | by bang iqi" },
            timestamp = DateTime.now():ToIsoDate(),
        }
        sendWebhook({
            username = WEBHOOK.username,
            embeds = { embed },
        })
        print("[Webhook] Pesan test berhasil dikirim ke Discord.")
    end,
})
