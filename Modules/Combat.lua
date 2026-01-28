--[[
    Combat.lua
    Attack logic and skill management
    Uses M1 clicks, hitbox expansion, and proper targeting
]]

local Combat = {}
Combat.__index = Combat

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- Constants
local SKILL_KEYS = {Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C, Enum.KeyCode.V, Enum.KeyCode.F}
local HAKI_KEY = Enum.KeyCode.J
local SKILL_COOLDOWN = 0.5
local ATTACK_COOLDOWN = 0.1
local HITBOX_SIZE = 50

function Combat.new(config)
    local self = setmetatable({}, Combat)

    self.config = config
    self.enabled = false
    self.target = nil
    self.lastAttackTime = 0
    self.lastSkillTime = {}
    self.lastHakiTime = 0
    self.attackConnection = nil
    self.expandedHitboxes = {}
    self.originalSizes = {}

    -- Initialize skill cooldowns
    for _, key in ipairs(SKILL_KEYS) do
        self.lastSkillTime[key] = 0
    end

    return self
end

-- Get character and humanoid
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

-- Check if entity is alive
local function IsAlive(entity)
    if not entity or not entity.Parent then return false end

    local humanoid = entity:FindFirstChild("Humanoid")
    if humanoid then
        return humanoid.Health > 0
    end

    -- Check for NPC health value
    local health = entity:FindFirstChild("Health")
    if health and health:IsA("NumberValue") then
        return health.Value > 0
    end

    return false
end

-- Get distance to entity
local function GetDistance(entity)
    local _, _, rootPart = GetCharacter()
    if not rootPart then return math.huge end

    local targetPart = entity:FindFirstChild("HumanoidRootPart") or
                       entity:FindFirstChild("Torso") or
                       entity:FindFirstChild("Head")
    if not targetPart then return math.huge end

    return (rootPart.Position - targetPart.Position).Magnitude
end

-- Perform M1 attack (mouse click)
function Combat:Attack()
    local now = tick()
    if now - self.lastAttackTime < ATTACK_COOLDOWN then return end

    -- Simulate left mouse click
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
    task.wait()
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)

    self.lastAttackTime = now
end

-- Use a skill by key
function Combat:UseSkill(keyCode)
    local now = tick()
    local cooldown = self.config and self.config:Get("Combat", "SkillCooldown") or SKILL_COOLDOWN

    if now - (self.lastSkillTime[keyCode] or 0) < cooldown then
        return false
    end

    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait()
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)

    self.lastSkillTime[keyCode] = now
    return true
end

-- Use all available skills
function Combat:UseAllSkills(targetPosition)
    if not self.config then return end

    local skillsEnabled = self.config:Get("Combat", "SkillsEnabled") or
                         {Z = true, X = true, C = false, V = false, F = false}

    for i, keyCode in ipairs(SKILL_KEYS) do
        local keyName = keyCode.Name
        if skillsEnabled[keyName] then
            self:UseSkill(keyCode)
            task.wait(0.1)
        end
    end
end

-- Enable Haki (Buso) by pressing J or E
function Combat:EnableHaki()
    local now = tick()
    if now - self.lastHakiTime < 1 then return end

    local character = GetCharacter()
    if not character then return end

    -- Check if already has haki enabled
    if character:FindFirstChild("HasBuso") then return end

    -- Press J key for Haki
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.J, false, game)
    task.wait()
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.J, false, game)

    self.lastHakiTime = now
end

-- Expand hitbox of an enemy
function Combat:ExpandHitbox(enemy)
    if not enemy then return end
    if self.expandedHitboxes[enemy] then return end

    local hitboxSize = self.config and self.config:Get("Combat", "HitboxSize") or HITBOX_SIZE

    for _, part in pairs(enemy:GetDescendants()) do
        if part:IsA("BasePart") then
            -- Store original size
            if not self.originalSizes[part] then
                self.originalSizes[part] = part.Size
            end

            -- Expand the part
            pcall(function()
                part.Size = Vector3.new(hitboxSize, hitboxSize, hitboxSize)
                part.Transparency = 1
                part.CanCollide = false
            end)
        end
    end

    self.expandedHitboxes[enemy] = true
end

-- Restore hitbox of an enemy
function Combat:RestoreHitbox(enemy)
    if not enemy then return end
    if not self.expandedHitboxes[enemy] then return end

    for _, part in pairs(enemy:GetDescendants()) do
        if part:IsA("BasePart") and self.originalSizes[part] then
            pcall(function()
                part.Size = self.originalSizes[part]
            end)
        end
    end

    self.expandedHitboxes[enemy] = nil
end

-- Set current target
function Combat:SetTarget(target)
    self.target = target
end

-- Get current target
function Combat:GetTarget()
    return self.target
end

-- Find closest enemy by name
function Combat:FindEnemyByName(enemyName, maxDistance)
    maxDistance = maxDistance or 500
    local _, _, rootPart = GetCharacter()
    if not rootPart then return nil end

    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return nil end

    local closest = nil
    local closestDistance = maxDistance

    for _, enemy in pairs(enemies:GetChildren()) do
        if enemy.Name == enemyName and IsAlive(enemy) then
            local distance = GetDistance(enemy)
            if distance < closestDistance then
                closest = enemy
                closestDistance = distance
            end
        end
    end

    return closest, closestDistance
end

-- Find any closest enemy
function Combat:FindClosestEnemy(maxDistance)
    maxDistance = maxDistance or 200
    local _, _, rootPart = GetCharacter()
    if not rootPart then return nil end

    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return nil end

    local closest = nil
    local closestDistance = maxDistance

    for _, enemy in pairs(enemies:GetChildren()) do
        if IsAlive(enemy) then
            local distance = GetDistance(enemy)
            if distance < closestDistance then
                closest = enemy
                closestDistance = distance
            end
        end
    end

    return closest, closestDistance
end

-- Get target root part position
function Combat:GetTargetPosition()
    if not self.target then return nil end

    local targetPart = self.target:FindFirstChild("HumanoidRootPart") or
                       self.target:FindFirstChild("Torso")
    if targetPart then
        return targetPart.Position
    end

    return nil
end

-- Start auto combat loop
function Combat:Start(questTarget)
    if self.enabled then return end
    self.enabled = true

    self.attackConnection = RunService.Heartbeat:Connect(function()
        if not self.enabled then return end

        local character, humanoid, rootPart = GetCharacter()
        if not character or humanoid.Health <= 0 then return end

        -- Enable haki if configured
        if self.config and self.config:Get("Combat", "AutoHaki") then
            self:EnableHaki()
        end

        -- Find target if not set or dead
        if not self.target or not IsAlive(self.target) then
            if questTarget then
                self.target = self:FindEnemyByName(questTarget)
            else
                self.target = self:FindClosestEnemy()
            end
        end

        if not self.target then return end

        local distance = GetDistance(self.target)

        -- Expand hitbox if close enough
        if distance <= 100 then
            self:ExpandHitbox(self.target)
        end

        -- Attack if in range
        if distance <= 50 then
            -- Auto attack with M1
            if self.config and self.config:Get("Combat", "AutoAttack") then
                self:Attack()
            end

            -- Auto skills
            if self.config and self.config:Get("Combat", "AutoSkills") then
                self:UseAllSkills()
            end
        end
    end)
end

-- Stop auto combat
function Combat:Stop()
    self.enabled = false
    self.target = nil

    if self.attackConnection then
        self.attackConnection:Disconnect()
        self.attackConnection = nil
    end

    -- Restore all hitboxes
    for enemy, _ in pairs(self.expandedHitboxes) do
        self:RestoreHitbox(enemy)
    end
    self.expandedHitboxes = {}
    self.originalSizes = {}
end

-- Check if combat is active
function Combat:IsActive()
    return self.enabled
end

-- Cleanup
function Combat:Destroy()
    self:Stop()
end

return {
    new = Combat.new,
    IsAlive = IsAlive,
    GetDistance = GetDistance
}
