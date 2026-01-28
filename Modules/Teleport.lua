--[[
    Teleport.lua
    Tween-based movement system (no direct teleportation)
    Handles smooth navigation with obstacle avoidance
]]

local Teleport = {}
Teleport.__index = Teleport

-- Services
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- Constants
local DEFAULT_SPEED = 200
local SAFE_HEIGHT = 50
local CHECK_INTERVAL = 0.1
local STUCK_THRESHOLD = 3
local STUCK_CHECK_TIME = 2

function Teleport.new(config)
    local self = setmetatable({}, Teleport)

    self.config = config
    self.isTweening = false
    self.currentTween = nil
    self.destination = nil
    self.startPosition = nil
    self.lastPosition = nil
    self.stuckTime = 0
    self.bodyVelocity = nil
    self.callbacks = {
        onStart = nil,
        onComplete = nil,
        onCancel = nil,
        onStuck = nil
    }

    return self
end

-- Get character and humanoid root part
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

-- Check if player is alive
local function IsAlive()
    local character, humanoid = GetCharacter()
    return humanoid and humanoid.Health > 0
end

-- Calculate distance between two positions
local function GetDistance(pos1, pos2)
    if typeof(pos1) == "CFrame" then pos1 = pos1.Position end
    if typeof(pos2) == "CFrame" then pos2 = pos2.Position end
    return (pos1 - pos2).Magnitude
end

-- Create or get BodyVelocity for movement
function Teleport:GetBodyVelocity()
    local character, humanoid, rootPart = GetCharacter()
    if not rootPart then return nil end

    local upperTorso = character:FindFirstChild("UpperTorso")
    local attachPart = upperTorso or rootPart

    if self.bodyVelocity and self.bodyVelocity.Parent then
        return self.bodyVelocity
    end

    self.bodyVelocity = Instance.new("BodyVelocity")
    self.bodyVelocity.Velocity = Vector3.zero
    self.bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    self.bodyVelocity.P = 1000
    self.bodyVelocity.Parent = attachPart

    return self.bodyVelocity
end

-- Remove BodyVelocity
function Teleport:RemoveBodyVelocity()
    if self.bodyVelocity then
        self.bodyVelocity.Velocity = Vector3.zero
        self.bodyVelocity:Destroy()
        self.bodyVelocity = nil
    end
end

-- Set noclip for character
function Teleport:SetNoClip(enabled)
    local character = GetCharacter()
    if not character then return end

    for _, part in pairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = not enabled
        end
    end
end

-- Get speed from config or default
function Teleport:GetSpeed()
    if self.config then
        return self.config:Get("Teleport", "TweenSpeed") or DEFAULT_SPEED
    end
    return DEFAULT_SPEED
end

-- Calculate travel time based on distance and speed
function Teleport:CalculateTravelTime(startPos, endPos)
    local distance = GetDistance(startPos, endPos)
    local speed = self:GetSpeed()
    return distance / speed
end

-- Tween to a position using TweenService
function Teleport:TweenTo(targetCFrame, onComplete, options)
    if self.isTweening then
        self:Stop()
    end

    local character, humanoid, rootPart = GetCharacter()
    if not rootPart then
        if onComplete then onComplete(false, "No character") end
        return false
    end

    -- Convert Vector3 to CFrame if needed
    if typeof(targetCFrame) == "Vector3" then
        targetCFrame = CFrame.new(targetCFrame)
    end

    options = options or {}
    local speed = options.speed or self:GetSpeed()
    local bypassWalls = options.bypassWalls
    if bypassWalls == nil then
        bypassWalls = self.config and self.config:Get("Teleport", "BypassWalls")
    end

    self.isTweening = true
    self.destination = targetCFrame
    self.startPosition = rootPart.Position
    self.lastPosition = rootPart.Position
    self.stuckTime = 0

    -- Calculate travel time
    local distance = GetDistance(rootPart.Position, targetCFrame.Position)
    local travelTime = distance / speed

    -- Fire start callback
    if self.callbacks.onStart then
        self.callbacks.onStart(targetCFrame, travelTime)
    end

    -- Enable noclip if bypassing walls
    if bypassWalls then
        self:SetNoClip(true)
    end

    -- Create tween info
    local tweenInfo = TweenInfo.new(
        travelTime,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.Out,
        0,
        false,
        0
    )

    -- Create and play tween
    self.currentTween = TweenService:Create(rootPart, tweenInfo, {
        CFrame = targetCFrame
    })

    local connection
    connection = self.currentTween.Completed:Connect(function(playbackState)
        connection:Disconnect()
        self.isTweening = false
        self.currentTween = nil

        -- Disable noclip
        if bypassWalls then
            self:SetNoClip(false)
        end

        local success = playbackState == Enum.PlaybackState.Completed

        -- Fire complete callback
        if self.callbacks.onComplete then
            self.callbacks.onComplete(success)
        end

        if onComplete then
            onComplete(success, playbackState)
        end
    end)

    self.currentTween:Play()

    -- Stuck detection coroutine
    task.spawn(function()
        while self.isTweening do
            task.wait(STUCK_CHECK_TIME)

            if not self.isTweening then break end

            local _, _, currentRoot = GetCharacter()
            if currentRoot then
                local moveDistance = GetDistance(self.lastPosition, currentRoot.Position)

                if moveDistance < STUCK_THRESHOLD then
                    self.stuckTime = self.stuckTime + STUCK_CHECK_TIME

                    if self.stuckTime >= STUCK_CHECK_TIME * 2 then
                        if self.callbacks.onStuck then
                            self.callbacks.onStuck(currentRoot.Position, targetCFrame.Position)
                        end
                        -- Try to unstick by adding height
                        rootPart.CFrame = rootPart.CFrame + Vector3.new(0, 10, 0)
                        self.stuckTime = 0
                    end
                else
                    self.stuckTime = 0
                end

                self.lastPosition = currentRoot.Position
            end
        end
    end)

    return true
end

-- Tween using BodyVelocity (alternative method)
function Teleport:TweenWithVelocity(targetPosition, onComplete, options)
    if self.isTweening then
        self:Stop()
    end

    local character, humanoid, rootPart = GetCharacter()
    if not rootPart then
        if onComplete then onComplete(false, "No character") end
        return false
    end

    -- Convert CFrame to Vector3 if needed
    if typeof(targetPosition) == "CFrame" then
        targetPosition = targetPosition.Position
    end

    options = options or {}
    local speed = options.speed or self:GetSpeed()
    local stopDistance = options.stopDistance or 3
    local bypassWalls = options.bypassWalls
    if bypassWalls == nil then
        bypassWalls = self.config and self.config:Get("Teleport", "BypassWalls")
    end

    self.isTweening = true
    self.destination = targetPosition
    self.startPosition = rootPart.Position
    self.lastPosition = rootPart.Position
    self.stuckTime = 0

    -- Enable noclip if bypassing walls
    if bypassWalls then
        self:SetNoClip(true)
    end

    local bv = self:GetBodyVelocity()
    if not bv then
        if onComplete then onComplete(false, "No body velocity") end
        return false
    end

    -- Fire start callback
    if self.callbacks.onStart then
        local distance = GetDistance(rootPart.Position, targetPosition)
        self.callbacks.onStart(targetPosition, distance / speed)
    end

    -- Movement loop
    local connection
    connection = RunService.Heartbeat:Connect(function()
        if not self.isTweening then
            connection:Disconnect()
            return
        end

        local _, _, currentRoot = GetCharacter()
        if not currentRoot then
            connection:Disconnect()
            self:Stop()
            if onComplete then onComplete(false, "Character lost") end
            return
        end

        local direction = (targetPosition - currentRoot.Position)
        local distance = direction.Magnitude

        if distance <= stopDistance then
            connection:Disconnect()
            self:Stop()

            -- Set final position
            currentRoot.CFrame = CFrame.new(targetPosition) * CFrame.Angles(0, currentRoot.CFrame:ToEulerAnglesYXZ())

            if self.callbacks.onComplete then
                self.callbacks.onComplete(true)
            end

            if onComplete then onComplete(true) end
            return
        end

        -- Set velocity towards target
        bv.Velocity = direction.Unit * speed
    end)

    return true
end

-- Stop current tween
function Teleport:Stop()
    if self.currentTween then
        self.currentTween:Cancel()
        self.currentTween = nil
    end

    self:RemoveBodyVelocity()
    self:SetNoClip(false)

    if self.isTweening and self.callbacks.onCancel then
        self.callbacks.onCancel()
    end

    self.isTweening = false
    self.destination = nil
end

-- Check if currently tweening
function Teleport:IsTweening()
    return self.isTweening
end

-- Get current destination
function Teleport:GetDestination()
    return self.destination
end

-- Get distance to destination
function Teleport:GetDistanceToDestination()
    if not self.destination then return math.huge end

    local _, _, rootPart = GetCharacter()
    if not rootPart then return math.huge end

    local destPos = typeof(self.destination) == "CFrame" and self.destination.Position or self.destination
    return GetDistance(rootPart.Position, destPos)
end

-- Get progress (0-1)
function Teleport:GetProgress()
    if not self.isTweening or not self.startPosition or not self.destination then
        return 0
    end

    local _, _, rootPart = GetCharacter()
    if not rootPart then return 0 end

    local destPos = typeof(self.destination) == "CFrame" and self.destination.Position or self.destination
    local totalDistance = GetDistance(self.startPosition, destPos)
    local currentDistance = GetDistance(rootPart.Position, destPos)

    if totalDistance <= 0 then return 1 end
    return math.clamp(1 - (currentDistance / totalDistance), 0, 1)
end

-- Set callbacks
function Teleport:OnStart(callback)
    self.callbacks.onStart = callback
end

function Teleport:OnComplete(callback)
    self.callbacks.onComplete = callback
end

function Teleport:OnCancel(callback)
    self.callbacks.onCancel = callback
end

function Teleport:OnStuck(callback)
    self.callbacks.onStuck = callback
end

-- Tween to an island by name
function Teleport:TweenToIsland(islandName, islands, onComplete)
    if not islands then
        if onComplete then onComplete(false, "No island data") end
        return false
    end

    -- Search through all seas
    for sea, islandList in pairs(islands) do
        if type(islandList) == "table" and islandList[islandName] then
            local pos = islandList[islandName].Position
            if pos then
                local targetCFrame = CFrame.new(pos[1], pos[2] + SAFE_HEIGHT, pos[3])
                return self:TweenTo(targetCFrame, onComplete)
            end
        end
    end

    if onComplete then onComplete(false, "Island not found") end
    return false
end

-- Tween to NPC by quest name
function Teleport:TweenToNPC(questName, npcs, onComplete)
    if not npcs or not npcs.QuestGivers then
        if onComplete then onComplete(false, "No NPC data") end
        return false
    end

    local npcData = npcs.QuestGivers[questName]
    if npcData and npcData.Position then
        local pos = npcData.Position
        local targetCFrame = CFrame.new(pos[1], pos[2] + 3, pos[3])
        return self:TweenTo(targetCFrame, onComplete)
    end

    if onComplete then onComplete(false, "NPC not found") end
    return false
end

-- Tween to boss location
function Teleport:TweenToBoss(bossName, islands, onComplete)
    if not islands or not islands.Bosses then
        if onComplete then onComplete(false, "No boss data") end
        return false
    end

    local bossData = islands.Bosses[bossName]
    if bossData and bossData.Position then
        local pos = bossData.Position
        local targetCFrame = CFrame.new(pos[1], pos[2] + 10, pos[3])
        return self:TweenTo(targetCFrame, onComplete)
    end

    if onComplete then onComplete(false, "Boss not found") end
    return false
end

-- Travel to different sea using in-game buttons
function Teleport:TravelToSea(seaNumber)
    local character = GetCharacter()
    if not character then return false end

    -- Access the server browser UI
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return false end

    local serverBrowser = playerGui:FindFirstChild("ServerBrowser")
    if not serverBrowser then
        warn("[Teleport] ServerBrowser not found")
        return false
    end

    local frame = serverBrowser:FindFirstChild("Frame")
    if not frame then return false end

    local teleportButtons = frame:FindFirstChild("TeleportButtons")
    if not teleportButtons then return false end

    local buttonName = "Sea" .. tostring(seaNumber)
    local seaButton = teleportButtons:FindFirstChild(buttonName)

    if seaButton then
        -- Fire the button click
        if seaButton:FindFirstChild("TextButton") then
            firesignal(seaButton.TextButton.Activated)
        else
            firesignal(seaButton.Activated)
        end
        return true
    end

    return false
end

-- Get current sea
function Teleport:GetCurrentSea()
    local placeIds = {
        [2753915549] = 1,    -- Sea 1
        [4442272183] = 2,    -- Sea 2
        [7449423635] = 3     -- Sea 3
    }
    return placeIds[game.PlaceId] or 0
end

-- Wait for tween to complete
function Teleport:WaitForComplete(timeout)
    timeout = timeout or 120
    local startTime = tick()

    while self.isTweening do
        if tick() - startTime > timeout then
            self:Stop()
            return false, "Timeout"
        end
        task.wait(0.1)
    end

    return true
end

-- Cleanup
function Teleport:Destroy()
    self:Stop()
    self.callbacks = {}
end

return {
    new = Teleport.new,
    GetDistance = GetDistance,
    IsAlive = IsAlive
}
