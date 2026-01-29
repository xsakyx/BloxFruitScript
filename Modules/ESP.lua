--[[
    ESP.lua
    Visual ESP system for fruits, players, bosses, chests
    Correct paths for Blox Fruits game structure
    NOTE: Mob ESP removed as requested
]]

local ESP = {}
ESP.__index = ESP

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- Constants
local UPDATE_INTERVAL = 0.5 -- Faster updates
local MAX_ESP_OBJECTS = 100 -- Increased limit

-- Increased default distances (not affected by graphics)
local DEFAULT_DISTANCES = {
    Player = 2000,
    Boss = 5000,
    Fruit = 10000,
    Chest = 1000
}

local DEFAULT_COLORS = {
    Player = Color3.fromRGB(255, 0, 0),
    Boss = Color3.fromRGB(255, 0, 255),
    Fruit = Color3.fromRGB(0, 255, 0),
    Chest = Color3.fromRGB(255, 170, 0)
}

local FRUIT_TIER_COLORS = {
    Mythical = Color3.fromRGB(255, 0, 255),
    Legendary = Color3.fromRGB(255, 215, 0),
    Rare = Color3.fromRGB(0, 112, 221),
    Uncommon = Color3.fromRGB(0, 200, 0),
    Common = Color3.fromRGB(200, 200, 200),
    Unknown = Color3.fromRGB(150, 150, 150)
}

-- Fruit tiers for color coding
local FRUIT_TIERS = {
    Mythical = {"Leopard", "Kitsune", "Spirit", "Dough", "Venom", "Control", "Shadow", "Gas", "Yeti", "Dragon"},
    Legendary = {"Phoenix", "Rumble", "Portal", "Gravity", "Pain", "Blizzard", "Sound", "Love", "Spider", "Creation", "Mammoth", "T-Rex"},
    Rare = {"Light", "Rubber", "Ghost", "Magma", "Quake"},
    Uncommon = {"Flame", "Sand", "Dark", "Diamond", "Eagle"},
    Common = {"Rocket", "Spin", "Blade", "Spring", "Bomb", "Smoke", "Spike"}
}

function ESP.new(config)
    local self = setmetatable({}, ESP)

    self.config = config
    self.enabled = false
    self.espObjects = {}
    self.updateLoop = nil
    self.lastUpdate = 0

    return self
end

-- Get character
local function GetCharacter()
    local character = LocalPlayer.Character
    if character then
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            return character, rootPart
        end
    end
    return nil, nil
end

-- Get distance to position/entity
local function GetDistance(target)
    local _, rootPart = GetCharacter()
    if not rootPart then return math.huge end

    local position
    if typeof(target) == "Vector3" then
        position = target
    elseif typeof(target) == "CFrame" then
        position = target.Position
    elseif typeof(target) == "Instance" then
        if target:IsA("BasePart") then
            position = target.Position
        else
            local part = target:FindFirstChild("HumanoidRootPart") or
                        target:FindFirstChild("Head") or
                        target:FindFirstChild("UpperTorso") or
                        target:FindFirstChild("Handle") or
                        target:FindFirstChildOfClass("BasePart")
            if part then
                position = part.Position
            end
        end
    end

    if not position then return math.huge end
    return (rootPart.Position - position).Magnitude
end

-- Get fruit tier
local function GetFruitTier(fruitName)
    for tier, fruits in pairs(FRUIT_TIERS) do
        for _, name in ipairs(fruits) do
            if fruitName:find(name) then
                return tier
            end
        end
    end
    return "Unknown"
end

-- Create billboard GUI
function ESP:CreateBillboard(entity, text, color, entityType, adorneeOverride)
    if not entity then return nil end
    if self:GetESPCount() >= MAX_ESP_OBJECTS then return nil end

    -- Find attachment point
    local adornee = adorneeOverride or
                   entity:FindFirstChild("Head") or
                   entity:FindFirstChild("UpperTorso") or
                   entity:FindFirstChild("Handle") or
                   entity:FindFirstChild("HumanoidRootPart") or
                   entity:FindFirstChildOfClass("BasePart")

    if not adornee then return nil end

    -- Remove existing
    local existing = adornee:FindFirstChild("ESP_Billboard")
    if existing then existing:Destroy() end

    -- Create billboard
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP_Billboard"
    billboard.Adornee = adornee
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = adornee

    local textLabel = Instance.new("TextLabel")
    textLabel.Name = "ESPText"
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.TextColor3 = color
    textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    textLabel.TextStrokeTransparency = 0.5
    textLabel.Font = Enum.Font.GothamBold
    textLabel.TextSize = 14
    textLabel.Text = text
    textLabel.Parent = billboard

    self.espObjects[entity] = {
        Billboard = billboard,
        TextLabel = textLabel,
        Type = entityType,
        Color = color
    }

    return billboard
end

-- Remove ESP from entity
function ESP:RemoveESP(entity)
    if not entity then return end

    local data = self.espObjects[entity]
    if data and data.Billboard then
        pcall(function() data.Billboard:Destroy() end)
    end
    self.espObjects[entity] = nil

    -- Also try to find and remove any billboards
    pcall(function()
        for _, part in pairs(entity:GetDescendants()) do
            if part.Name == "ESP_Billboard" then
                part:Destroy()
            end
        end
    end)
end

-- Update ESP text with distance
function ESP:UpdateESP(entity, text, showDistance)
    local data = self.espObjects[entity]
    if not data then return end

    local displayText = text
    if showDistance then
        local distance = math.floor(GetDistance(entity))
        displayText = displayText .. "\n[" .. distance .. "m]"
    end

    pcall(function()
        data.TextLabel.Text = displayText
    end)
end

-- Player ESP - uses workspace.Characters
function ESP:UpdatePlayerESP()
    if not self.config or not self.config:Get("ESP", "PlayerESP") then return end

    local maxDistance = self.config:Get("ESP", "PlayerDistance") or DEFAULT_DISTANCES.Player
    local showDistance = self.config:Get("ESP", "ShowDistance")

    -- Players are in workspace.Characters as models named by username
    local characters = Workspace:FindFirstChild("Characters")
    if characters then
        for _, playerModel in pairs(characters:GetChildren()) do
            if playerModel:IsA("Model") then
                -- Skip local player
                if playerModel.Name == LocalPlayer.Name then continue end

                local distance = GetDistance(playerModel)
                if distance > maxDistance then
                    self:RemoveESP(playerModel)
                    continue
                end

                local text = playerModel.Name
                local color = DEFAULT_COLORS.Player

                -- Use Head or UpperTorso for adornee
                local adornee = playerModel:FindFirstChild("Head") or playerModel:FindFirstChild("UpperTorso")

                if not self.espObjects[playerModel] then
                    self:CreateBillboard(playerModel, text, color, "Player", adornee)
                else
                    self:UpdateESP(playerModel, text, showDistance)
                end
            end
        end
    end
end

-- Boss ESP - bosses have Head and UpperTorso
function ESP:UpdateBossESP()
    if not self.config or not self.config:Get("ESP", "BossESP") then return end

    local maxDistance = self.config:Get("ESP", "BossDistance") or DEFAULT_DISTANCES.Boss
    local showDistance = self.config:Get("ESP", "ShowDistance")

    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return end

    for _, enemy in pairs(enemies:GetChildren()) do
        -- Check if it's a boss (bosses typically have certain attributes or names)
        local isBoss = enemy:GetAttribute("IsBoss") or
                      enemy:GetAttribute("RaidBoss") or
                      enemy.Name:find("Boss") or
                      enemy.Name:find("Captain") or
                      enemy.Name:find("King") or
                      enemy.Name:find("Admiral")

        if not isBoss then continue end

        local humanoid = enemy:FindFirstChild("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            self:RemoveESP(enemy)
            continue
        end

        local distance = GetDistance(enemy)
        if distance > maxDistance then
            self:RemoveESP(enemy)
            continue
        end

        local text = enemy.Name
        local color = DEFAULT_COLORS.Boss
        local adornee = enemy:FindFirstChild("Head") or enemy:FindFirstChild("UpperTorso")

        if not self.espObjects[enemy] then
            self:CreateBillboard(enemy, text, color, "Boss", adornee)
        else
            self:UpdateESP(enemy, text, showDistance)
        end
    end
end

-- Fruit ESP - fruits are Tools in workspace named "FruitName Fruit"
function ESP:UpdateFruitESP()
    if not self.config or not self.config:Get("ESP", "FruitESP") then return end

    local maxDistance = self.config:Get("ESP", "FruitDistance") or DEFAULT_DISTANCES.Fruit
    local showDistance = self.config:Get("ESP", "ShowDistance")

    -- Scan workspace direct children for fruit tools
    for _, obj in pairs(Workspace:GetChildren()) do
        local isFruit = false
        local fruitName = ""

        -- Check if it's a fruit tool (named "FruitName Fruit")
        if obj:IsA("Tool") and obj.Name:find("Fruit") then
            isFruit = true
            -- Get original name from attribute
            local originalName = obj:GetAttribute("OriginalName")
            if originalName then
                fruitName = originalName:gsub("-", " ")
            else
                fruitName = obj.Name:gsub(" Fruit", "")
            end
        elseif obj:IsA("Model") and obj.Name:find("Fruit") then
            isFruit = true
            fruitName = obj.Name:gsub(" Fruit", "")
        end

        if isFruit then
            local distance = GetDistance(obj)
            if distance > maxDistance then
                self:RemoveESP(obj)
                continue
            end

            -- Get tier and color
            local tier = GetFruitTier(fruitName)
            local color = FRUIT_TIER_COLORS[tier] or DEFAULT_COLORS.Fruit
            local text = fruitName .. " [" .. tier .. "]"

            -- Use Handle part for adornee
            local adornee = obj:FindFirstChild("Handle")

            if not self.espObjects[obj] then
                self:CreateBillboard(obj, text, color, "Fruit", adornee)
            else
                self:UpdateESP(obj, text, showDistance)
            end
        end
    end
end

-- Chest ESP - chests are in workspace.Map.IslandName.IslandModel.Details
function ESP:UpdateChestESP()
    if not self.config or not self.config:Get("ESP", "ChestESP") then return end

    local maxDistance = self.config:Get("ESP", "ChestDistance") or DEFAULT_DISTANCES.Chest
    local showDistance = self.config:Get("ESP", "ShowDistance")

    local map = Workspace:FindFirstChild("Map")
    if not map then return end

    -- Search through all islands
    for _, island in pairs(map:GetChildren()) do
        local islandModel = island:FindFirstChild("IslandModel") or island
        local details = islandModel:FindFirstChild("Details")

        if details then
            for _, obj in pairs(details:GetChildren()) do
                -- Check if it's a chest (Chest1, Chest2, Chest3)
                if obj.Name == "Chest1" or obj.Name == "Chest2" or obj.Name == "Chest3" then
                    local distance = GetDistance(obj)
                    if distance > maxDistance then
                        self:RemoveESP(obj)
                        continue
                    end

                    local text = obj.Name
                    local color = DEFAULT_COLORS.Chest

                    if not self.espObjects[obj] then
                        self:CreateBillboard(obj, text, color, "Chest")
                    else
                        self:UpdateESP(obj, text, showDistance)
                    end
                end
            end
        end
    end
end

-- Clean up removed entities
function ESP:Cleanup()
    for entity, data in pairs(self.espObjects) do
        if not entity or not entity.Parent then
            pcall(function()
                if data.Billboard then
                    data.Billboard:Destroy()
                end
            end)
            self.espObjects[entity] = nil
        end
    end
end

-- Count ESP objects
function ESP:GetESPCount()
    local count = 0
    for _ in pairs(self.espObjects) do
        count = count + 1
    end
    return count
end

-- Start ESP
function ESP:Start()
    if self.enabled then return end
    self.enabled = true

    self.updateLoop = RunService.Heartbeat:Connect(function()
        if not self.enabled then return end

        local now = tick()
        if now - self.lastUpdate < UPDATE_INTERVAL then return end
        self.lastUpdate = now

        pcall(function()
            if self:GetESPCount() >= MAX_ESP_OBJECTS then
                self:Cleanup()
            end

            pcall(function() self:UpdatePlayerESP() end)
            pcall(function() self:UpdateBossESP() end)
            pcall(function() self:UpdateFruitESP() end)
            pcall(function() self:UpdateChestESP() end)
            pcall(function() self:Cleanup() end)
        end)
    end)
end

-- Stop ESP
function ESP:Stop()
    self.enabled = false

    if self.updateLoop then
        self.updateLoop:Disconnect()
        self.updateLoop = nil
    end

    for entity, _ in pairs(self.espObjects) do
        self:RemoveESP(entity)
    end
    self.espObjects = {}
end

-- Toggle ESP
function ESP:Toggle()
    if self.enabled then
        self:Stop()
    else
        self:Start()
    end
end

-- Check if active
function ESP:IsActive()
    return self.enabled
end

-- Cleanup
function ESP:Destroy()
    self:Stop()
end

return {
    new = ESP.new,
    Colors = DEFAULT_COLORS,
    FruitColors = FRUIT_TIER_COLORS
}
