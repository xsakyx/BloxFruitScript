--[[
    ESP.lua
    Visual ESP system for fruits, players, mobs, bosses, chests
    Creates billboards and highlights for entities
]]

local ESP = {}
ESP.__index = ESP

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer

-- Constants
local UPDATE_INTERVAL = 0.1
local DEFAULT_COLORS = {
    Player = Color3.fromRGB(255, 0, 0),
    Mob = Color3.fromRGB(255, 255, 0),
    Boss = Color3.fromRGB(255, 0, 255),
    Fruit = Color3.fromRGB(0, 255, 0),
    Chest = Color3.fromRGB(255, 170, 0),
    NPC = Color3.fromRGB(0, 170, 255)
}

local FRUIT_TIER_COLORS = {
    Mythical = Color3.fromRGB(255, 0, 255),
    Legendary = Color3.fromRGB(255, 215, 0),
    Rare = Color3.fromRGB(0, 112, 221),
    Uncommon = Color3.fromRGB(0, 200, 0),
    Common = Color3.fromRGB(200, 200, 200),
    Unknown = Color3.fromRGB(150, 150, 150)
}

function ESP.new(config)
    local self = setmetatable({}, ESP)

    self.config = config
    self.enabled = false
    self.espObjects = {}
    self.updateLoop = nil
    self.lastUpdate = 0

    -- ESP containers
    self.espFolder = Instance.new("Folder")
    self.espFolder.Name = "BloxFruitESP"
    self.espFolder.Parent = game:GetService("CoreGui")

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

-- Get distance to entity
local function GetDistance(entity)
    local _, rootPart = GetCharacter()
    if not rootPart then return math.huge end

    local targetPart
    if typeof(entity) == "Instance" then
        if entity:IsA("BasePart") then
            targetPart = entity
        else
            targetPart = entity:FindFirstChild("HumanoidRootPart") or
                        entity:FindFirstChild("Torso") or
                        entity.PrimaryPart or
                        entity:FindFirstChildOfClass("BasePart")
        end
    elseif typeof(entity) == "Vector3" then
        return (rootPart.Position - entity).Magnitude
    end

    if not targetPart then return math.huge end
    return (rootPart.Position - targetPart.Position).Magnitude
end

-- Create billboard GUI for ESP
function ESP:CreateBillboard(entity, text, color, entityType)
    if not entity then return nil end

    -- Find attachment point
    local adornee = entity:FindFirstChild("HumanoidRootPart") or
                   entity:FindFirstChild("Head") or
                   entity:FindFirstChild("Torso") or
                   entity.PrimaryPart or
                   entity:FindFirstChildOfClass("BasePart")

    if not adornee then return nil end

    -- Check if already exists
    local existingGui = adornee:FindFirstChild("ESP_Billboard")
    if existingGui then
        existingGui:Destroy()
    end

    -- Create billboard
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP_Billboard"
    billboard.Adornee = adornee
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = adornee

    -- Create text label
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

    -- Store reference
    self.espObjects[entity] = {
        Billboard = billboard,
        TextLabel = textLabel,
        Type = entityType,
        Color = color
    }

    return billboard
end

-- Create highlight for entity
function ESP:CreateHighlight(entity, color)
    if not entity then return nil end

    -- Check if already has highlight
    local existingHighlight = entity:FindFirstChild("ESP_Highlight")
    if existingHighlight then
        existingHighlight.FillColor = color
        return existingHighlight
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "ESP_Highlight"
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = 0.7
    highlight.OutlineTransparency = 0
    highlight.Parent = entity

    return highlight
end

-- Remove ESP from entity
function ESP:RemoveESP(entity)
    if not entity then return end

    local data = self.espObjects[entity]
    if data then
        if data.Billboard then
            data.Billboard:Destroy()
        end
        self.espObjects[entity] = nil
    end

    local highlight = entity:FindFirstChild("ESP_Highlight")
    if highlight then
        highlight:Destroy()
    end

    local billboard = entity:FindFirstChild("ESP_Billboard")
    if billboard then
        billboard:Destroy()
    end
end

-- Update ESP text
function ESP:UpdateESP(entity, text, showDistance, showHealth)
    local data = self.espObjects[entity]
    if not data then return end

    local displayText = text

    if showDistance then
        local distance = math.floor(GetDistance(entity))
        displayText = displayText .. "\n[" .. distance .. "m]"
    end

    if showHealth then
        local humanoid = entity:FindFirstChild("Humanoid")
        if humanoid then
            local healthPercent = math.floor((humanoid.Health / humanoid.MaxHealth) * 100)
            displayText = displayText .. "\n" .. healthPercent .. "% HP"
        end
    end

    data.TextLabel.Text = displayText
end

-- Scan and update player ESP
function ESP:UpdatePlayerESP()
    if not self.config or not self.config:Get("ESP", "PlayerESP") then return end

    local maxDistance = self.config:Get("ESP", "NPCDistance") or 500
    local showDistance = self.config:Get("ESP", "ShowDistance")
    local showHealth = self.config:Get("ESP", "ShowHealth")
    local teamCheck = self.config:Get("ESP", "TeamCheck")
    local character = GetCharacter()

    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if not player.Character then continue end

        -- Team check
        if teamCheck and player.Team == LocalPlayer.Team then
            self:RemoveESP(player.Character)
            continue
        end

        local distance = GetDistance(player.Character)
        if distance > maxDistance then
            self:RemoveESP(player.Character)
            continue
        end

        local color = DEFAULT_COLORS.Player
        local text = player.DisplayName

        if not self.espObjects[player.Character] then
            self:CreateBillboard(player.Character, text, color, "Player")
            self:CreateHighlight(player.Character, color)
        else
            self:UpdateESP(player.Character, text, showDistance, showHealth)
        end
    end
end

-- Scan and update mob ESP
function ESP:UpdateMobESP()
    if not self.config or not self.config:Get("ESP", "MobESP") then return end

    local maxDistance = self.config:Get("ESP", "NPCDistance") or 500
    local showDistance = self.config:Get("ESP", "ShowDistance")
    local showHealth = self.config:Get("ESP", "ShowHealth")

    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return end

    for _, enemy in pairs(enemies:GetChildren()) do
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

        local isBoss = enemy:GetAttribute("IsBoss") or enemy:GetAttribute("RaidBoss")
        local color = isBoss and DEFAULT_COLORS.Boss or DEFAULT_COLORS.Mob
        local text = enemy.Name

        if isBoss and self.config:Get("ESP", "BossESP") then
            if not self.espObjects[enemy] then
                self:CreateBillboard(enemy, text, color, "Boss")
                self:CreateHighlight(enemy, color)
            else
                self:UpdateESP(enemy, text, showDistance, showHealth)
            end
        elseif not isBoss then
            if not self.espObjects[enemy] then
                self:CreateBillboard(enemy, text, color, "Mob")
            else
                self:UpdateESP(enemy, text, showDistance, showHealth)
            end
        end
    end
end

-- Scan and update fruit ESP
function ESP:UpdateFruitESP()
    if not self.config or not self.config:Get("ESP", "FruitESP") then return end

    local maxDistance = self.config:Get("ESP", "FruitDistance") or 10000
    local showDistance = self.config:Get("ESP", "ShowDistance")

    local containers = {
        Workspace,
        Workspace:FindFirstChild("Fruits"),
        Workspace:FindFirstChild("FruitSpawns"),
        Workspace:FindFirstChild("Map")
    }

    for _, container in pairs(containers) do
        if not container then continue end

        for _, obj in pairs(container:GetDescendants()) do
            local isFruit = obj.Name == "Fruit " or obj.Name == "Fruit" or
                           (obj.Name:find("Fruit") and obj:IsA("Model"))

            if isFruit then
                local distance = GetDistance(obj)
                if distance > maxDistance then
                    self:RemoveESP(obj)
                    continue
                end

                -- Try to identify fruit
                local fruitName = obj.Name:gsub(" Fruit", ""):gsub("Fruit ", "")
                if fruitName == "" or fruitName == "Fruit" then
                    fruitName = "Unknown Fruit"
                end

                -- Get tier color
                local tier = "Unknown"
                for tierName, fruits in pairs(FRUIT_TIER_COLORS) do
                    -- This would need fruit tier data, using default for now
                end
                local color = FRUIT_TIER_COLORS[tier] or DEFAULT_COLORS.Fruit

                if not self.espObjects[obj] then
                    self:CreateBillboard(obj, fruitName, color, "Fruit")
                    self:CreateHighlight(obj, color)
                else
                    local displayText = fruitName
                    if showDistance then
                        displayText = displayText .. "\n[" .. math.floor(distance) .. "m]"
                    end
                    self.espObjects[obj].TextLabel.Text = displayText
                end
            end
        end
    end
end

-- Scan and update chest ESP
function ESP:UpdateChestESP()
    if not self.config or not self.config:Get("ESP", "ChestESP") then return end

    local maxDistance = self.config:Get("ESP", "NPCDistance") or 500
    local showDistance = self.config:Get("ESP", "ShowDistance")

    local chests = CollectionService:GetTagged("_ChestTagged")

    for _, chest in pairs(chests) do
        if chest:GetAttribute("IsDisabled") then
            self:RemoveESP(chest)
            continue
        end

        local distance = GetDistance(chest)
        if distance > maxDistance then
            self:RemoveESP(chest)
            continue
        end

        local color = DEFAULT_COLORS.Chest
        local text = "Chest"

        if not self.espObjects[chest] then
            self:CreateBillboard(chest, text, color, "Chest")
        else
            self:UpdateESP(chest, text, showDistance, false)
        end
    end
end

-- Clean up dead/removed entities
function ESP:Cleanup()
    for entity, data in pairs(self.espObjects) do
        if not entity or not entity.Parent then
            if data.Billboard then
                data.Billboard:Destroy()
            end
            self.espObjects[entity] = nil
        end
    end
end

-- Start ESP
function ESP:Start()
    if self.enabled then return end
    self.enabled = true

    self.updateLoop = RunService.Heartbeat:Connect(function()
        if not self.enabled then return end

        local now = tick()
        if now - self.lastUpdate < UPDATE_INTERVAL then
            return
        end
        self.lastUpdate = now

        -- Update all ESP types
        self:UpdatePlayerESP()
        self:UpdateMobESP()
        self:UpdateFruitESP()
        self:UpdateChestESP()
        self:Cleanup()
    end)
end

-- Stop ESP
function ESP:Stop()
    self.enabled = false

    if self.updateLoop then
        self.updateLoop:Disconnect()
        self.updateLoop = nil
    end

    -- Remove all ESP objects
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

-- Set ESP color for type
function ESP:SetColor(entityType, color)
    DEFAULT_COLORS[entityType] = color
end

-- Get default colors
function ESP:GetColors()
    return DEFAULT_COLORS
end

-- Cleanup
function ESP:Destroy()
    self:Stop()

    if self.espFolder then
        self.espFolder:Destroy()
    end
end

return {
    new = ESP.new,
    Colors = DEFAULT_COLORS,
    FruitColors = FRUIT_TIER_COLORS
}
