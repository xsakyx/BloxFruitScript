--[[
    FruitSniper.lua
    Fruit detection and collection system
    Scans workspace for fruits, identifies them, and collects
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
local FRUIT_SCAN_INTERVAL = 0.5
local FRUIT_COLLECT_DISTANCE = 10
local SERVER_HOP_DELAY = 5

-- Fruit image to name mapping
local FruitImageMapping = {
    ["rbxassetid://15124425041"] = "Rocket",
    ["rbxassetid://15123685330"] = "Spin",
    ["rbxassetid://15123613404"] = "Blade",
    ["rbxassetid://15123689268"] = "Spring",
    ["rbxassetid://15123595806"] = "Bomb",
    ["rbxassetid://15123677932"] = "Smoke",
    ["rbxassetid://15124220207"] = "Spike",
    ["rbxassetid://121545956771325"] = "Flame",
    ["rbxassetid://15123673019"] = "Sand",
    ["rbxassetid://15123618591"] = "Dark",
    ["rbxassetid://77885466312115"] = "Eagle",
    ["rbxassetid://15112600534"] = "Diamond",
    ["rbxassetid://15123640714"] = "Light",
    ["rbxassetid://15123668008"] = "Rubber",
    ["rbxassetid://15123662036"] = "Ghost",
    ["rbxassetid://15123645682"] = "Magma",
    ["rbxassetid://15123606541"] = "Quake",
    ["rbxassetid://15123643097"] = "Love",
    ["rbxassetid://15123681598"] = "Spider",
    ["rbxassetid://116828771482820"] = "Creation",
    ["rbxassetid://15123679712"] = "Sound",
    ["rbxassetid://15123654553"] = "Phoenix",
    ["rbxassetid://15123656798"] = "Portal",
    ["rbxassetid://15123670514"] = "Rumble",
    ["rbxassetid://15123652069"] = "Pain",
    ["rbxassetid://15123587371"] = "Blizzard",
    ["rbxassetid://15123633312"] = "Gravity",
    ["rbxassetid://15123648309"] = "Mammoth",
    ["rbxassetid://15694681122"] = "T-Rex",
    ["rbxassetid://15123624401"] = "Dough",
    ["rbxassetid://15123675904"] = "Shadow",
    ["rbxassetid://10773719142"] = "Venom",
    ["rbxassetid://15123616275"] = "Control",
    ["rbxassetid://118054805452821"] = "Gas",
    ["rbxassetid://11911905519"] = "Spirit",
    ["rbxassetid://15123638064"] = "Leopard",
    ["rbxassetid://115276580506154"] = "Yeti",
    ["rbxassetid://15487764876"] = "Kitsune",
    ["rbxassetid://95749033139458"] = "Dragon East"
}

-- Fruit tiers
local FruitTiers = {
    Mythical = {"Leopard", "Kitsune", "Spirit", "Dough", "Venom", "Control", "Shadow", "Gas", "Yeti", "Dragon East"},
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
    self.scanLoop = nil
    self.foundFruits = {}
    self.collectedFruits = {}
    self.lastScanTime = 0
    self.lastServerHop = 0

    self.callbacks = {
        onFruitFound = nil,
        onFruitCollected = nil,
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
        position = position:GetPivot().Position
    end

    return (rootPart.Position - position).Magnitude
end

-- Identify fruit by image or mesh
function FruitSniper:IdentifyFruit(fruit)
    if not fruit then return nil end

    -- Check if already named
    if fruit.Name ~= "Fruit " and fruit.Name ~= "Fruit" then
        return fruit.Name:gsub(" Fruit", "")
    end

    -- Try to identify by mesh/image
    for _, child in pairs(fruit:GetDescendants()) do
        if child:IsA("MeshPart") then
            local meshId = child.MeshId
            if FruitImageMapping[meshId] then
                return FruitImageMapping[meshId]
            end
        elseif child:IsA("Decal") or child:IsA("ImageLabel") then
            local imageId = child.Image or child.Texture
            if imageId and FruitImageMapping[imageId] then
                return FruitImageMapping[imageId]
            end
        end
    end

    -- Check Animation if available
    local animation = fruit:FindFirstChild("Animation")
    if animation then
        local animId = animation.AnimationId
        if FruitImageMapping[animId] then
            return FruitImageMapping[animId]
        end
    end

    return "Unknown"
end

-- Get fruit tier
function FruitSniper:GetFruitTier(fruitName)
    for tier, fruits in pairs(FruitTiers) do
        for _, name in ipairs(fruits) do
            if name == fruitName then
                return tier
            end
        end
    end
    return "Unknown"
end

-- Check if fruit should be collected based on settings
function FruitSniper:ShouldCollectFruit(fruitName)
    if not self.config then return true end

    local tier = self:GetFruitTier(fruitName)

    -- Check whitelist
    if self.config:Get("FruitSniper", "UseWhitelist") then
        local whitelist = self.config:Get("FruitSniper", "WhitelistedFruits") or {}
        return table.find(whitelist, fruitName) ~= nil
    end

    -- Check blacklist
    local blacklist = self.config:Get("FruitSniper", "BlacklistedFruits") or {}
    if table.find(blacklist, fruitName) then
        return false
    end

    -- Check tier filters
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

    -- Common fruit spawn locations/containers
    local containers = {
        Workspace,
        Workspace:FindFirstChild("Fruits"),
        Workspace:FindFirstChild("FruitSpawns"),
        Workspace:FindFirstChild("Map")
    }

    for _, container in pairs(containers) do
        if container then
            for _, obj in pairs(container:GetDescendants()) do
                -- Check if it's a fruit
                local isFruit = false
                local fruitObj = obj

                if obj.Name == "Fruit " or obj.Name == "Fruit" then
                    isFruit = true
                elseif obj.Name:find("Fruit") and obj:IsA("Model") then
                    isFruit = true
                elseif obj:IsA("Tool") and obj.ToolTip == "Fruit" then
                    isFruit = true
                    fruitObj = obj
                end

                if isFruit and fruitObj then
                    local fruitName = self:IdentifyFruit(fruitObj)
                    local position = fruitObj:GetPivot().Position

                    if fruitName and not self.collectedFruits[fruitObj] then
                        table.insert(fruits, {
                            Object = fruitObj,
                            Name = fruitName,
                            Tier = self:GetFruitTier(fruitName),
                            Position = position,
                            Distance = GetDistance(position)
                        })
                    end
                end
            end
        end
    end

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

-- Collect a fruit
function FruitSniper:CollectFruit(fruitData)
    if not fruitData or not fruitData.Object then return false end
    if not fruitData.Object.Parent then return false end

    local character, humanoid, rootPart = GetCharacter()
    if not rootPart then return false end

    -- Mark as being collected
    self.collectedFruits[fruitData.Object] = true

    -- Tween to fruit
    local targetCFrame = CFrame.new(fruitData.Position + Vector3.new(0, 5, 0))

    self.teleport:TweenTo(targetCFrame, function(success)
        if success and fruitData.Object.Parent then
            -- Wait a moment then touch/collect
            task.wait(0.5)

            -- Try to touch the fruit
            if fruitData.Object:IsA("Tool") then
                -- Try to equip if it's a tool
                humanoid:EquipTool(fruitData.Object)
            else
                -- Move directly to fruit position to collect
                local fruitRoot = fruitData.Object:FindFirstChild("Handle") or
                                  fruitData.Object:FindFirstChildOfClass("MeshPart") or
                                  fruitData.Object.PrimaryPart

                if fruitRoot then
                    rootPart.CFrame = fruitRoot.CFrame
                end
            end

            task.wait(1)

            -- Fire callback
            if self.callbacks.onFruitCollected then
                self.callbacks.onFruitCollected(fruitData.Name, fruitData.Tier)
            end
        else
            -- Remove from collected list if failed
            self.collectedFruits[fruitData.Object] = nil
        end
    end)

    return true
end

-- Server hop to find fruits
function FruitSniper:ServerHop()
    local now = tick()
    local hopDelay = self.config and self.config:Get("FruitSniper", "ServerHopDelay") or SERVER_HOP_DELAY

    if now - self.lastServerHop < hopDelay then
        return false
    end

    self.lastServerHop = now

    if self.callbacks.onServerHop then
        self.callbacks.onServerHop()
    end

    -- Get server list
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

    -- Fallback: regular teleport
    TeleportService:Teleport(game.PlaceId, LocalPlayer)
    return true
end

-- Start fruit sniping
function FruitSniper:Start()
    if self.enabled then return end
    self.enabled = true

    self.foundFruits = {}
    self.collectedFruits = {}

    self.scanLoop = RunService.Heartbeat:Connect(function()
        if not self.enabled then return end

        local now = tick()
        if now - self.lastScanTime < FRUIT_SCAN_INTERVAL then
            return
        end
        self.lastScanTime = now

        -- Scan for fruits
        local fruits = self:ScanForFruits()

        -- Process found fruits
        for _, fruitData in ipairs(fruits) do
            -- Check if already processing
            if self.foundFruits[fruitData.Object] then
                continue
            end

            -- Check if should collect
            if not self:ShouldCollectFruit(fruitData.Name) then
                continue
            end

            -- Mark as found
            self.foundFruits[fruitData.Object] = true

            -- Fire callback
            if self.callbacks.onFruitFound then
                self.callbacks.onFruitFound(fruitData.Name, fruitData.Tier, fruitData.Distance)
            end

            -- Collect if auto-collect enabled
            if self.config and self.config:Get("FruitSniper", "AutoCollect") then
                self:CollectFruit(fruitData)
                return -- Only collect one at a time
            end
        end

        -- Server hop if no fruits and enabled
        if #fruits == 0 and self.config and self.config:Get("FruitSniper", "ServerHop") then
            if not self.teleport:IsTweening() then
                self:ServerHop()
            end
        end
    end)
end

-- Stop fruit sniping
function FruitSniper:Stop()
    self.enabled = false

    if self.scanLoop then
        self.scanLoop:Disconnect()
        self.scanLoop = nil
    end

    self.teleport:Stop()
end

-- Check if active
function FruitSniper:IsActive()
    return self.enabled
end

-- Get found fruits list
function FruitSniper:GetFoundFruits()
    return self:ScanForFruits()
end

-- Get closest fruit
function FruitSniper:GetClosestFruit()
    local fruits = self:ScanForFruits()
    if #fruits > 0 then
        return fruits[1]
    end
    return nil
end

-- Set callbacks
function FruitSniper:OnFruitFound(callback)
    self.callbacks.onFruitFound = callback
end

function FruitSniper:OnFruitCollected(callback)
    self.callbacks.onFruitCollected = callback
end

function FruitSniper:OnServerHop(callback)
    self.callbacks.onServerHop = callback
end

-- Get fruit tiers data
function FruitSniper:GetFruitTiers()
    return FruitTiers
end

-- Get all fruit names
function FruitSniper:GetAllFruitNames()
    local names = {}
    for _, name in pairs(FruitImageMapping) do
        if not table.find(names, name) then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

-- Cleanup
function FruitSniper:Destroy()
    self:Stop()
    self.callbacks = {}
    self.foundFruits = {}
    self.collectedFruits = {}
end

return {
    new = FruitSniper.new,
    FruitTiers = FruitTiers,
    FruitImageMapping = FruitImageMapping
}
