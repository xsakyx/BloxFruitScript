--[[
    FruitSniper.lua
    Professional Fruit Detection, Collection, and Auto-Store System

    Features:
    - Detects fruits at workspace["FruitName Fruit"] with OriginalName attribute
    - Smart auto-store: tries to store, if already owned closes UI and continues
    - Configurable timeout for store attempts
    - Fruit filtering by tier
    - Server hop when no fruits found
]]

local FruitSniper = {}
FruitSniper.__index = FruitSniper

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- Constants
local FRUIT_SCAN_INTERVAL = 2
local DEFAULT_STORE_TIMEOUT = 5
local SERVER_HOP_DELAY = 30

-- Fruit tiers
local FruitTiers = {
    Mythical = {"Leopard", "Kitsune", "Spirit", "Dough", "Venom", "Control", "Shadow", "Gas", "Yeti", "Dragon"},
    Legendary = {"Phoenix", "Rumble", "Portal", "Gravity", "Pain", "Blizzard", "Sound", "Love", "Spider", "Creation", "Mammoth", "T-Rex"},
    Rare = {"Light", "Rubber", "Ghost", "Magma", "Quake"},
    Uncommon = {"Flame", "Sand", "Dark", "Diamond", "Eagle"},
    Common = {"Rocket", "Spin", "Blade", "Spring", "Bomb", "Smoke", "Spike"}
}

function FruitSniper.new(config, teleport)
    local self = setmetatable({}, FruitSniper)

    self.config = config
    self.teleport = teleport
    self.enabled = false
    self.autoStoreEnabled = false
    self.storeTimeout = DEFAULT_STORE_TIMEOUT
    self.scanLoop = nil
    self.foundFruits = {}
    self.collectedFruits = {}
    self.ignoredFruits = {} -- Fruits we've tried to store but couldn't (already owned)
    self.lastScanTime = 0
    self.lastServerHop = 0
    self.noFruitCount = 0
    self.isStoringFruit = false
    self.previousActivity = nil -- What we were doing before fruit pickup

    self.callbacks = {
        onFruitFound = nil,
        onFruitCollected = nil,
        onFruitStored = nil,
        onFruitIgnored = nil,
        onServerHop = nil
    }

    return self
end

-- Get character
local function GetCharacter()
    local character = LocalPlayer.Character
    if character then
        local humanoid = character:FindFirstChild("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if humanoid and rootPart and humanoid.Health > 0 then
            return character, humanoid, rootPart
        end
    end
    return nil, nil, nil
end

-- Get distance to position
local function GetDistance(position)
    local _, _, rootPart = GetCharacter()
    if not rootPart then return math.huge end

    if typeof(position) == "CFrame" then
        position = position.Position
    elseif typeof(position) == "Instance" then
        local part = position:FindFirstChild("Handle") or position:FindFirstChildOfClass("BasePart")
        if part then
            position = part.Position
        else
            return math.huge
        end
    end

    return (rootPart.Position - position).Magnitude
end

-- Get fruit tier from name
function FruitSniper:GetFruitTier(fruitName)
    for tier, fruits in pairs(FruitTiers) do
        for _, name in ipairs(fruits) do
            if fruitName:find(name) then
                return tier
            end
        end
    end
    return "Unknown"
end

-- Check if fruit should be collected
function FruitSniper:ShouldCollectFruit(fruitName)
    -- Check if we've already tried to store this fruit and it failed
    if self.ignoredFruits[fruitName] then
        return false
    end

    if not self.config then return true end

    local tier = self:GetFruitTier(fruitName)

    if self.config:Get("FruitSniper", "UseWhitelist") then
        local whitelist = self.config:Get("FruitSniper", "WhitelistedFruits") or {}
        return table.find(whitelist, fruitName) ~= nil
    end

    local blacklist = self.config:Get("FruitSniper", "BlacklistedFruits") or {}
    if table.find(blacklist, fruitName) then
        return false
    end

    if self.config:Get("FruitSniper", "OnlyMythical") then
        return tier == "Mythical"
    end

    if self.config:Get("FruitSniper", "OnlyLegendary") then
        return tier == "Mythical" or tier == "Legendary"
    end

    return true
end

-- Scan workspace for fruits
function FruitSniper:ScanForFruits()
    local fruits = {}

    local success = pcall(function()
        -- Scan direct children of workspace for fruit tools
        for _, obj in pairs(Workspace:GetChildren()) do
            local isFruit = false
            local fruitName = ""

            -- Fruits are Tools named "FruitName Fruit"
            if obj:IsA("Tool") and obj.Name:find("Fruit") then
                isFruit = true
                -- Get original name from attribute (format: "Rubber-Rubber")
                local originalName = obj:GetAttribute("OriginalName")
                if originalName then
                    -- Convert "Rubber-Rubber" to "Rubber"
                    fruitName = originalName:match("^([^-]+)") or originalName
                else
                    fruitName = obj.Name:gsub(" Fruit", "")
                end
            elseif obj:IsA("Model") and obj.Name:find("Fruit") then
                isFruit = true
                fruitName = obj.Name:gsub(" Fruit", "")
            end

            if isFruit and fruitName ~= "" and not self.collectedFruits[obj] and not self.ignoredFruits[fruitName] then
                local handle = obj:FindFirstChild("Handle")
                local position = handle and handle.Position or nil

                if position then
                    table.insert(fruits, {
                        Object = obj,
                        Name = fruitName,
                        Tier = self:GetFruitTier(fruitName),
                        Position = position,
                        Distance = GetDistance(obj)
                    })
                end
            end
        end
    end)

    if not success then return {} end

    -- Sort by tier (mythical first) then distance
    table.sort(fruits, function(a, b)
        local tierOrder = {Mythical = 1, Legendary = 2, Rare = 3, Uncommon = 4, Common = 5, Unknown = 6}
        local tierA = tierOrder[a.Tier] or 6
        local tierB = tierOrder[b.Tier] or 6

        if tierA ~= tierB then
            return tierA < tierB
        end
        return a.Distance < b.Distance
    end)

    return fruits
end

-- Check if fruit is in player inventory (backpack or equipped)
function FruitSniper:HasFruitInInventory(fruitName)
    local character = GetCharacter()

    -- Check equipped tools
    if character then
        for _, item in pairs(character:GetChildren()) do
            if item:IsA("Tool") and item.Name:find(fruitName) then
                return true, item
            end
        end
    end

    -- Check backpack
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        for _, item in pairs(backpack:GetChildren()) do
            if item:IsA("Tool") and item.Name:find(fruitName) then
                return true, item
            end
        end
    end

    return false, nil
end

-- Close any open fruit UI
function FruitSniper:CloseOpenFruitUI()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return end

    -- Look for fruit-related UIs and close them
    for _, gui in pairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            local guiName = gui.Name:lower()
            if guiName:find("fruit") or guiName:find("store") or guiName:find("eat") then
                pcall(function()
                    -- Try to find and click close button
                    for _, desc in pairs(gui:GetDescendants()) do
                        if (desc:IsA("TextButton") or desc:IsA("ImageButton")) then
                            local name = desc.Name:lower()
                            local text = desc:IsA("TextButton") and desc.Text:lower() or ""
                            if name:find("close") or name:find("cancel") or name:find("exit") or
                               text:find("close") or text:find("cancel") or text:find("x") then
                                if firesignal then
                                    firesignal(desc.Activated)
                                    firesignal(desc.MouseButton1Click)
                                end
                                return
                            end
                        end
                    end
                    -- If no close button found, just disable the gui
                    gui.Enabled = false
                end)
            end
        end
    end
end

-- Try to store fruit with timeout
function FruitSniper:TryStoreFruit(fruitName, fruitTool)
    if not self.autoStoreEnabled then return false end
    if self.isStoringFruit then return false end

    self.isStoringFruit = true
    local startTime = tick()
    local timeout = self.storeTimeout
    local stored = false

    -- Equip the fruit
    local character, humanoid = GetCharacter()
    if not humanoid then
        self.isStoringFruit = false
        return false
    end

    pcall(function()
        humanoid:EquipTool(fruitTool)
    end)
    task.wait(0.3)

    -- Activate to open store/eat UI
    pcall(function()
        fruitTool:Activate()
    end)
    task.wait(0.5)

    -- Find and click store button
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if playerGui then
        local storeClicked = false

        -- Search for store button
        for _, gui in pairs(playerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Enabled then
                for _, desc in pairs(gui:GetDescendants()) do
                    if (desc:IsA("TextButton") or desc:IsA("ImageButton")) then
                        local name = desc.Name:lower()
                        local text = desc:IsA("TextButton") and desc.Text:lower() or ""
                        if name:find("store") or text:find("store") then
                            pcall(function()
                                if firesignal then
                                    firesignal(desc.Activated)
                                    firesignal(desc.MouseButton1Click)
                                end
                            end)
                            storeClicked = true
                            break
                        end
                    end
                end
            end
            if storeClicked then break end
        end

        -- Wait and check if fruit was stored
        if storeClicked then
            -- Wait for store to process, but with timeout
            while tick() - startTime < timeout do
                task.wait(0.5)

                -- Check if fruit is still in inventory
                local stillHasFruit, _ = self:HasFruitInInventory(fruitName)
                if not stillHasFruit then
                    -- Fruit was stored successfully
                    stored = true
                    break
                end
            end
        end
    end

    -- Check result after timeout
    if not stored then
        -- Fruit wasn't stored - probably already have it in storage
        local stillHasFruit, _ = self:HasFruitInInventory(fruitName)
        if stillHasFruit then
            -- Close the UI
            self:CloseOpenFruitUI()
            task.wait(0.3)

            -- Add to ignored list so we don't try again
            self.ignoredFruits[fruitName] = true

            -- Callback for ignored fruit
            if self.callbacks.onFruitIgnored then
                pcall(self.callbacks.onFruitIgnored, fruitName, "Already in storage")
            end

            -- Unequip the fruit
            pcall(function()
                humanoid:UnequipTools()
            end)

            print("[FruitSniper] Could not store " .. fruitName .. " - likely already in storage. Continuing...")
        end
    else
        -- Successfully stored
        if self.callbacks.onFruitStored then
            pcall(self.callbacks.onFruitStored, fruitName)
        end
        print("[FruitSniper] Successfully stored " .. fruitName)
    end

    self.isStoringFruit = false
    return stored
end

-- Collect a fruit
function FruitSniper:CollectFruit(fruitData)
    if not fruitData or not fruitData.Object then return false end
    if not fruitData.Object.Parent then return false end

    local character, humanoid, rootPart = GetCharacter()
    if not rootPart then return false end

    self.collectedFruits[fruitData.Object] = true

    -- Tween to fruit
    local targetCFrame = CFrame.new(fruitData.Position + Vector3.new(0, 3, 0))

    if self.teleport then
        self.teleport:TweenTo(targetCFrame, function(success)
            if success and fruitData.Object.Parent then
                task.wait(0.5)

                -- Touch the fruit to collect
                local handle = fruitData.Object:FindFirstChild("Handle")
                if handle then
                    pcall(function()
                        rootPart.CFrame = handle.CFrame
                    end)
                end

                task.wait(1)

                -- Check if collected
                local hasFruit, fruitTool = self:HasFruitInInventory(fruitData.Name)
                if hasFruit and fruitTool then
                    if self.callbacks.onFruitCollected then
                        pcall(self.callbacks.onFruitCollected, fruitData.Name, fruitData.Tier)
                    end

                    -- Auto-store if enabled
                    if self.autoStoreEnabled then
                        task.wait(0.5)
                        self:TryStoreFruit(fruitData.Name, fruitTool)
                    end
                else
                    self.collectedFruits[fruitData.Object] = nil
                end
            else
                self.collectedFruits[fruitData.Object] = nil
            end
        end)
    else
        -- Direct teleport fallback
        pcall(function()
            rootPart.CFrame = targetCFrame
        end)
    end

    return true
end

-- Set auto-store enabled
function FruitSniper:SetAutoStore(enabled)
    self.autoStoreEnabled = enabled
end

-- Set store timeout
function FruitSniper:SetStoreTimeout(timeout)
    self.storeTimeout = timeout
end

-- Server hop
function FruitSniper:ServerHop()
    local now = tick()
    if now - self.lastServerHop < SERVER_HOP_DELAY then
        return false
    end
    self.lastServerHop = now

    if self.callbacks.onServerHop then
        pcall(self.callbacks.onServerHop)
    end

    local serverBrowser = ReplicatedStorage:FindFirstChild("__ServerBrowser")
    if serverBrowser then
        local success, servers = pcall(function()
            return serverBrowser:InvokeServer(1)
        end)

        if success and type(servers) == "table" then
            local currentJob = game.JobId
            local bestServer = nil
            local minPlayers = math.huge

            for jobId, serverInfo in pairs(servers) do
                if jobId ~= currentJob and serverInfo.Count < minPlayers then
                    minPlayers = serverInfo.Count
                    bestServer = jobId
                end
            end

            if bestServer then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, bestServer, LocalPlayer)
                return true
            end
        end
    end

    TeleportService:Teleport(game.PlaceId, LocalPlayer)
    return true
end

-- Start fruit sniping
function FruitSniper:Start()
    if self.enabled then return end
    self.enabled = true

    self.foundFruits = {}
    self.collectedFruits = {}
    -- Don't reset ignored fruits - keep memory of what we couldn't store
    self.noFruitCount = 0

    self.scanLoop = RunService.Heartbeat:Connect(function()
        if not self.enabled then return end
        if self.isStoringFruit then return end -- Don't scan while storing

        local now = tick()
        if now - self.lastScanTime < FRUIT_SCAN_INTERVAL then return end
        self.lastScanTime = now

        pcall(function()
            local fruits = self:ScanForFruits()

            for _, fruitData in ipairs(fruits) do
                if self.foundFruits[fruitData.Object] then continue end
                if not self:ShouldCollectFruit(fruitData.Name) then continue end

                self.foundFruits[fruitData.Object] = true

                if self.callbacks.onFruitFound then
                    pcall(self.callbacks.onFruitFound, fruitData.Name, fruitData.Tier, fruitData.Distance)
                end

                if self.config and self.config:Get("FruitSniper", "AutoCollect") then
                    self:CollectFruit(fruitData)
                    self.noFruitCount = 0
                    return
                end
            end

            if #fruits == 0 then
                self.noFruitCount = self.noFruitCount + 1
                if self.noFruitCount >= 5 and self.config and self.config:Get("FruitSniper", "ServerHop") then
                    if not self.teleport or not self.teleport:IsTweening() then
                        self.noFruitCount = 0
                        self:ServerHop()
                    end
                end
            else
                self.noFruitCount = 0
            end
        end)
    end)

    print("[FruitSniper] Started")
end

-- Stop fruit sniping
function FruitSniper:Stop()
    self.enabled = false

    if self.scanLoop then
        self.scanLoop:Disconnect()
        self.scanLoop = nil
    end

    if self.teleport then
        self.teleport:Stop()
    end

    print("[FruitSniper] Stopped")
end

-- Check if active
function FruitSniper:IsActive()
    return self.enabled
end

-- Get found fruits
function FruitSniper:GetFoundFruits()
    return self:ScanForFruits()
end

-- Get ignored fruits
function FruitSniper:GetIgnoredFruits()
    return self.ignoredFruits
end

-- Clear ignored fruits (allow retrying)
function FruitSniper:ClearIgnoredFruits()
    self.ignoredFruits = {}
end

-- Callbacks
function FruitSniper:OnFruitFound(callback)
    self.callbacks.onFruitFound = callback
end

function FruitSniper:OnFruitCollected(callback)
    self.callbacks.onFruitCollected = callback
end

function FruitSniper:OnFruitStored(callback)
    self.callbacks.onFruitStored = callback
end

function FruitSniper:OnFruitIgnored(callback)
    self.callbacks.onFruitIgnored = callback
end

function FruitSniper:OnServerHop(callback)
    self.callbacks.onServerHop = callback
end

-- Get fruit tiers data
function FruitSniper:GetFruitTiers()
    return FruitTiers
end

-- Cleanup
function FruitSniper:Destroy()
    self:Stop()
    self.callbacks = {}
    self.foundFruits = {}
    self.collectedFruits = {}
    self.ignoredFruits = {}
end

return {
    new = FruitSniper.new,
    FruitTiers = FruitTiers
}
