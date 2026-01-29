--[[
    Misc.lua
    Miscellaneous utilities: Anti-AFK (always on), Island Teleport, Stats
    NOTE: Sea teleport removed, Anti-AFK always enabled
]]

local Misc = {}
Misc.__index = Misc

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

-- Constants
local ANTI_AFK_INTERVAL = 60

-- Island data for teleportation
local ISLANDS = {
    Sea1 = {
        ["Starter Island"] = {Position = CFrame.new(-631, 15, 1503)},
        ["Marine Starter"] = {Position = CFrame.new(-2570, 7, 2073)},
        ["Jungle"] = {Position = CFrame.new(-1240, 15, 351)},
        ["Pirate Village"] = {Position = CFrame.new(-1134, 10, 3824)},
        ["Desert"] = {Position = CFrame.new(1091, 7, 4491)},
        ["Middle Town"] = {Position = CFrame.new(-692, 15, 1583)},
        ["Frozen Village"] = {Position = CFrame.new(1201, 87, -1310)},
        ["Marine Fortress"] = {Position = CFrame.new(-4606, 88, 4294)},
        ["Colosseum"] = {Position = CFrame.new(-1448, 7, -2756)},
        ["Magma Village"] = {Position = CFrame.new(-5296, 15, 8417)},
        ["Underwater City"] = {Position = CFrame.new(61182, 11, 1568)},
        ["Fountain City"] = {Position = CFrame.new(5276, 70, 4326)}
    },
    Sea2 = {
        ["Kingdom of Rose"] = {Position = CFrame.new(-362, 93, 678)},
        ["Green Zone"] = {Position = CFrame.new(-2395, 73, -3129)},
        ["Graveyard"] = {Position = CFrame.new(-5441, 91, -766)},
        ["Snow Mountain"] = {Position = CFrame.new(533, 474, -5147)},
        ["Hot and Cold"] = {Position = CFrame.new(-6015, 15, -4820)},
        ["Cursed Ship"] = {Position = CFrame.new(916, 125, 33028)},
        ["Ice Castle"] = {Position = CFrame.new(-6032, 15, -5000)},
        ["Forgotten Island"] = {Position = CFrame.new(-3053, 240, -10295)},
        ["Dark Arena"] = {Position = CFrame.new(-7050, 108, -2800)},
        ["Usoap Island"] = {Position = CFrame.new(4837, 14, -775)}
    },
    Sea3 = {
        ["Port Town"] = {Position = CFrame.new(-293, 44, 5554)},
        ["Hydra Island"] = {Position = CFrame.new(5229, 15, 344)},
        ["Great Tree"] = {Position = CFrame.new(2877, 1882, -7928)},
        ["Floating Turtle"] = {Position = CFrame.new(-12681, 409, -7615)},
        ["Castle on the Sea"] = {Position = CFrame.new(-5044, 314, -2840)},
        ["Haunted Castle"] = {Position = CFrame.new(-9508, 165, 5765)},
        ["Sea of Treats"] = {Position = CFrame.new(-2150, 74, -11427)},
        ["Cake Land"] = {Position = CFrame.new(-1927, 20, -11267)},
        ["Peanut Island"] = {Position = CFrame.new(-1975, 20, -12400)},
        ["Chocolate Land"] = {Position = CFrame.new(-2480, 20, -11180)}
    }
}

function Misc.new(config, teleport)
    local self = setmetatable({}, Misc)

    self.config = config
    self.teleport = teleport
    self.connections = {}
    self.antiAfkEnabled = false
    self.infiniteEnergyEnabled = false
    self.noClipEnabled = false

    self.stats = {
        Level = 0,
        Beli = 0,
        Fragments = 0,
        Bounty = 0,
        Race = "Unknown",
        CurrentSea = 0
    }

    -- Auto-start Anti-AFK (always enabled, not toggleable)
    self:StartAntiAFK()

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

-- Get player data
function Misc:GetPlayerData()
    local data = LocalPlayer:FindFirstChild("Data")
    if not data then return self.stats end

    self.stats = {
        Level = data:FindFirstChild("Level") and data.Level.Value or 0,
        Beli = data:FindFirstChild("Beli") and data.Beli.Value or 0,
        Fragments = data:FindFirstChild("Fragments") and data.Fragments.Value or 0,
        Race = data:FindFirstChild("Race") and data.Race.Value or "Unknown",
        CurrentSea = self:GetCurrentSea()
    }

    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local bountyHonor = leaderstats:FindFirstChild("Bounty/Honor")
        if bountyHonor then
            self.stats.Bounty = bountyHonor.Value
        end
    end

    return self.stats
end

-- Get current sea
function Misc:GetCurrentSea()
    local placeIds = {
        [2753915549] = 1,
        [4442272183] = 2,
        [7449423635] = 3
    }
    return placeIds[game.PlaceId] or 1
end

-- Get sea key
function Misc:GetSeaKey()
    return "Sea" .. tostring(self:GetCurrentSea())
end

-- Get island list for current sea
function Misc:GetIslandList()
    local seaKey = self:GetSeaKey()
    local islands = ISLANDS[seaKey]
    if not islands then return {} end

    local list = {}
    for name, _ in pairs(islands) do
        table.insert(list, name)
    end
    table.sort(list)
    return list
end

-- Teleport to island (using tween)
function Misc:TeleportToIsland(islandName)
    local seaKey = self:GetSeaKey()
    local islands = ISLANDS[seaKey]

    if not islands or not islands[islandName] then
        warn("[Misc] Island not found:", islandName)
        return false
    end

    local targetCFrame = islands[islandName].Position
    if not targetCFrame then return false end

    if self.teleport then
        self.teleport:TweenTo(targetCFrame, function(success)
            if success then
                self:Notify("Teleport", "Arrived at " .. islandName, 3)
            end
        end)
        return true
    else
        -- Fallback direct teleport if no tween module
        local character, _, rootPart = GetCharacter()
        if rootPart then
            rootPart.CFrame = targetCFrame
            return true
        end
    end

    return false
end

-- Anti-AFK System (always enabled)
function Misc:StartAntiAFK()
    if self.antiAfkEnabled then return end
    self.antiAfkEnabled = true

    -- Disconnect default idle detection
    pcall(function()
        for _, connection in pairs(getconnections(LocalPlayer.Idled)) do
            connection:Disable()
        end
    end)

    -- Custom anti-AFK loop
    local antiAfkLoop = task.spawn(function()
        while self.antiAfkEnabled do
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
            task.wait(ANTI_AFK_INTERVAL)
        end
    end)

    self.connections.antiAfk = antiAfkLoop
    print("[Misc] Anti-AFK enabled (always on)")
end

-- Rejoin server
function Misc:Rejoin()
    local players = Players:GetPlayers()
    if #players <= 1 then
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    else
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end
end

-- Server hop
function Misc:ServerHop(maxPlayers)
    maxPlayers = maxPlayers or 8

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
                if jobId ~= currentJob and serverInfo.Count <= maxPlayers and serverInfo.Count < minPlayers then
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

-- Infinite Energy/Stamina
function Misc:StartInfiniteEnergy()
    if self.infiniteEnergyEnabled then return end
    self.infiniteEnergyEnabled = true

    local energyLoop = RunService.Heartbeat:Connect(function()
        if not self.infiniteEnergyEnabled then return end

        local character = GetCharacter()
        if not character then return end

        local energy = character:FindFirstChild("Energy")
        if energy and energy:IsA("NumberValue") then
            energy.Value = 100
        end
    end)

    self.connections.infiniteEnergy = energyLoop
end

function Misc:StopInfiniteEnergy()
    self.infiniteEnergyEnabled = false
    if self.connections.infiniteEnergy then
        self.connections.infiniteEnergy:Disconnect()
        self.connections.infiniteEnergy = nil
    end
end

-- NoClip
function Misc:StartNoClip()
    if self.noClipEnabled then return end
    self.noClipEnabled = true

    local noClipLoop = RunService.Stepped:Connect(function()
        if not self.noClipEnabled then return end

        local character = GetCharacter()
        if not character then return end

        for _, part in pairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)

    self.connections.noClip = noClipLoop
end

function Misc:StopNoClip()
    self.noClipEnabled = false
    if self.connections.noClip then
        self.connections.noClip:Disconnect()
        self.connections.noClip = nil
    end
end

-- Send notification
function Misc:Notify(title, text, duration)
    duration = duration or 5

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration
        })
    end)
end

-- Get inventory info
function Misc:GetInventory()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return {} end

    local commF = remotes:FindFirstChild("CommF_")
    if not commF then return {} end

    local success, inventory = pcall(function()
        return commF:InvokeServer("getInventory")
    end)

    if success and type(inventory) == "table" then
        return inventory
    end

    return {}
end

-- Get owned fruits
function Misc:GetOwnedFruits()
    local inventory = self:GetInventory()
    local fruits = {}

    for _, item in pairs(inventory) do
        if type(item) == "table" and item.Name and item.Name:find("Fruit") then
            table.insert(fruits, item.Name)
        end
    end

    return fruits
end

-- Reset character
function Misc:ResetCharacter()
    local character, humanoid = GetCharacter()
    if humanoid then
        humanoid.Health = 0
    end
end

-- Full bright
function Misc:SetFullBright(enabled)
    local lighting = game:GetService("Lighting")

    if enabled then
        lighting.Brightness = 2
        lighting.ClockTime = 14
        lighting.FogEnd = 100000
        lighting.GlobalShadows = false
        lighting.Ambient = Color3.new(1, 1, 1)
    else
        lighting.Brightness = 1
        lighting.ClockTime = 14
        lighting.FogEnd = 10000
        lighting.GlobalShadows = true
        lighting.Ambient = Color3.fromRGB(127, 127, 127)
    end
end

-- Get mastery info for equipped tool
function Misc:GetToolMastery()
    local character = GetCharacter()
    if not character then return nil end

    local tool = character:FindFirstChildOfClass("Tool")
    if not tool then return nil end

    local mastery = tool:GetAttribute("Level")
    local maxMastery = 600

    return {
        ToolName = tool.Name,
        ToolType = tool.ToolTip,
        Mastery = mastery or 0,
        MaxMastery = maxMastery
    }
end

-- Start (Anti-AFK is already auto-started in constructor)
function Misc:Start()
    if self.config then
        if self.config:Get("Misc", "InfiniteEnergy") then
            self:StartInfiniteEnergy()
        end

        if self.config:Get("Misc", "NoClip") then
            self:StartNoClip()
        end
    end
end

-- Stop all features (except Anti-AFK which is always on)
function Misc:Stop()
    self:StopInfiniteEnergy()
    self:StopNoClip()
end

-- Cleanup
function Misc:Destroy()
    self:Stop()
    self.antiAfkEnabled = false

    for _, connection in pairs(self.connections) do
        if typeof(connection) == "RBXScriptConnection" then
            connection:Disconnect()
        end
    end

    self.connections = {}
end

return {
    new = Misc.new,
    Islands = ISLANDS
}
