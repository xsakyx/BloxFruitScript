--[[
    Misc.lua
    Miscellaneous utilities: Anti-AFK, Auto-Rejoin, Stats, etc.
]]

local Misc = {}
Misc.__index = Misc

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

-- Constants
local ANTI_AFK_INTERVAL = 60
local STATS_UPDATE_INTERVAL = 1

function Misc.new(config)
    local self = setmetatable({}, Misc)

    self.config = config
    self.connections = {}
    self.antiAfkEnabled = false
    self.autoRejoinEnabled = false
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

    -- Get bounty from leaderstats
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
    return placeIds[game.PlaceId] or 0
end

-- Anti-AFK System
function Misc:StartAntiAFK()
    if self.antiAfkEnabled then return end
    self.antiAfkEnabled = true

    -- Disconnect default idle detection
    local idleConnection
    for _, connection in pairs(getconnections(LocalPlayer.Idled)) do
        connection:Disable()
    end

    -- Custom anti-AFK loop
    local antiAfkLoop = task.spawn(function()
        while self.antiAfkEnabled do
            -- Simulate activity
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)

            -- Alternative method
            pcall(function()
                local viewport = workspace.CurrentCamera.ViewportSize
                VirtualInputManager:SendMouseMoveEvent(viewport.X / 2, viewport.Y / 2, game)
            end)

            task.wait(ANTI_AFK_INTERVAL)
        end
    end)

    self.connections.antiAfk = antiAfkLoop
end

function Misc:StopAntiAFK()
    self.antiAfkEnabled = false
end

-- Auto-Rejoin on kick/disconnect
function Misc:StartAutoRejoin()
    if self.autoRejoinEnabled then return end
    self.autoRejoinEnabled = true

    -- Listen for teleport failure
    local connection = LocalPlayer.OnTeleport:Connect(function(state)
        if state == Enum.TeleportState.Failed then
            task.wait(self.config and self.config:Get("Misc", "RejoinDelay") or 5)
            if self.autoRejoinEnabled then
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            end
        end
    end)

    self.connections.autoRejoin = connection
end

function Misc:StopAutoRejoin()
    self.autoRejoinEnabled = false
    if self.connections.autoRejoin then
        self.connections.autoRejoin:Disconnect()
        self.connections.autoRejoin = nil
    end
end

-- Rejoin server manually
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

    -- Fallback
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

-- Copy to clipboard
function Misc:CopyToClipboard(text)
    if setclipboard then
        setclipboard(text)
        return true
    end
    return false
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

-- Travel to sea
function Misc:TravelToSea(seaNumber)
    local currentSea = self:GetCurrentSea()
    if currentSea == seaNumber then return true end

    -- Use in-game server browser
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return false end

    local serverBrowser = playerGui:FindFirstChild("ServerBrowser")
    if not serverBrowser then return false end

    local frame = serverBrowser:FindFirstChild("Frame")
    if not frame then return false end

    local teleportButtons = frame:FindFirstChild("TeleportButtons")
    if not teleportButtons then return false end

    local buttonName = "Sea" .. tostring(seaNumber)
    local seaButton = teleportButtons:FindFirstChild(buttonName)

    if seaButton then
        -- Fire the button
        pcall(function()
            if seaButton:FindFirstChild("TextButton") then
                firesignal(seaButton.TextButton.Activated)
            else
                firesignal(seaButton.Activated)
            end
        end)
        return true
    end

    return false
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

-- Start all enabled features
function Misc:Start()
    if self.config then
        if self.config:Get("Misc", "AntiAFK") then
            self:StartAntiAFK()
        end

        if self.config:Get("Misc", "AutoRejoin") then
            self:StartAutoRejoin()
        end

        if self.config:Get("Misc", "InfiniteEnergy") then
            self:StartInfiniteEnergy()
        end

        if self.config:Get("Misc", "NoClip") then
            self:StartNoClip()
        end
    end
end

-- Stop all features
function Misc:Stop()
    self:StopAntiAFK()
    self:StopAutoRejoin()
    self:StopInfiniteEnergy()
    self:StopNoClip()
end

-- Cleanup
function Misc:Destroy()
    self:Stop()

    for _, connection in pairs(self.connections) do
        if typeof(connection) == "RBXScriptConnection" then
            connection:Disconnect()
        end
    end

    self.connections = {}
end

return {
    new = Misc.new
}
