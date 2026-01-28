--[[
    Combat.lua
    Attack logic and skill management
    Handles auto-attack, skill rotation, and target management
]]

local Combat = {}
Combat.__index = Combat

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- Constants
local SKILL_KEYS = {"Z", "X", "C", "V", "F"}
local SKILL_COOLDOWN = 0.5
local ATTACK_RANGE = {
    ["Blox Fruit"] = 35,
    ["Melee"] = 40,
    ["Sword"] = 40,
    ["Gun"] = 200
}

function Combat.new(config)
    local self = setmetatable({}, Combat)

    self.config = config
    self.enabled = false
    self.target = nil
    self.lastAttackTime = 0
    self.lastSkillTime = {}
    self.attackConnection = nil
    self.skillConnections = {}
    self.priorities = {
        QuestTarget = 10,
        Boss = 8,
        EliteMob = 7,
        RegularMob = 5,
        Player = 3
    }

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
    if not entity then return false end

    local humanoid = entity:FindFirstChild("Humanoid")
    if humanoid and humanoid.Health > 0 then
        return true
    end

    -- Check for NPC health value
    local health = entity:FindFirstChild("Health")
    if health and health:IsA("NumberValue") and health.Value > 0 then
        return true
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

-- Check if entity is a valid target
function Combat:IsValidTarget(entity)
    if not entity or not entity.Parent then return false end
    if not IsAlive(entity) then return false end

    local character = GetCharacter()
    if entity == character then return false end

    -- Check team (for players)
    local player = Players:GetPlayerFromCharacter(entity)
    if player then
        if self.config and not self.config:Get("Combat", "AttackPlayers") then
            return false
        end
        if player.Team == LocalPlayer.Team then
            return false
        end
    end

    return true
end

-- Get target priority
function Combat:GetTargetPriority(entity, questTarget)
    if not entity then return 0 end

    local name = entity.Name

    -- Quest target has highest priority
    if questTarget and name == questTarget then
        return self.priorities.QuestTarget
    end

    -- Boss detection
    if entity:GetAttribute("IsBoss") or entity:GetAttribute("RaidBoss") then
        return self.priorities.Boss
    end

    -- Player detection
    if Players:GetPlayerFromCharacter(entity) then
        return self.priorities.Player
    end

    -- Check for elite mobs (usually have special attributes)
    if entity:GetAttribute("IsElite") or string.find(name, "Elite") then
        return self.priorities.EliteMob
    end

    return self.priorities.RegularMob
end

-- Find closest enemy
function Combat:FindClosestEnemy(questTarget, maxDistance)
    maxDistance = maxDistance or 200
    local character, _, rootPart = GetCharacter()
    if not rootPart then return nil end

    local closest = nil
    local closestDistance = maxDistance
    local closestPriority = 0

    -- Check Enemies folder
    local enemies = Workspace:FindFirstChild("Enemies")
    if enemies then
        for _, enemy in pairs(enemies:GetChildren()) do
            if self:IsValidTarget(enemy) then
                local distance = GetDistance(enemy)
                local priority = self:GetTargetPriority(enemy, questTarget)

                -- Prioritize quest targets, then distance
                if priority > closestPriority or
                   (priority == closestPriority and distance < closestDistance) then
                    closest = enemy
                    closestDistance = distance
                    closestPriority = priority
                end
            end
        end
    end

    -- Check Characters folder (for PvP)
    if self.config and self.config:Get("Combat", "AttackPlayers") then
        local characters = Workspace:FindFirstChild("Characters")
        if characters then
            for _, char in pairs(characters:GetChildren()) do
                if self:IsValidTarget(char) then
                    local distance = GetDistance(char)
                    local priority = self:GetTargetPriority(char, questTarget)

                    if priority > closestPriority or
                       (priority == closestPriority and distance < closestDistance) then
                        closest = char
                        closestDistance = distance
                        closestPriority = priority
                    end
                end
            end
        end
    end

    return closest, closestDistance
end

-- Find enemy by name
function Combat:FindEnemyByName(enemyName, maxDistance)
    maxDistance = maxDistance or 500
    local character, _, rootPart = GetCharacter()
    if not rootPart then return nil end

    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return nil end

    local closest = nil
    local closestDistance = maxDistance

    for _, enemy in pairs(enemies:GetChildren()) do
        if enemy.Name == enemyName and self:IsValidTarget(enemy) then
            local distance = GetDistance(enemy)
            if distance < closestDistance then
                closest = enemy
                closestDistance = distance
            end
        end
    end

    return closest, closestDistance
end

-- Get equipped tool info
function Combat:GetEquippedTool()
    local character = GetCharacter()
    if not character then return nil, nil end

    local tool = character:FindFirstChildOfClass("Tool")
    if tool then
        return tool, tool.ToolTip or "Unknown"
    end

    return nil, nil
end

-- Get attack range for current weapon
function Combat:GetAttackRange()
    local tool, toolType = self:GetEquippedTool()
    return ATTACK_RANGE[toolType] or 50
end

-- Perform basic attack (click)
function Combat:Attack()
    local now = tick()
    if now - self.lastAttackTime < 0.1 then return end

    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)

    self.lastAttackTime = now
end

-- Use a skill by key
function Combat:UseSkill(key)
    local now = tick()
    local cooldown = self.config and self.config:Get("Combat", "SkillCooldown") or SKILL_COOLDOWN

    if now - (self.lastSkillTime[key] or 0) < cooldown then
        return false
    end

    VirtualInputManager:SendKeyEvent(true, key, false, game)
    VirtualInputManager:SendKeyEvent(false, key, false, game)

    self.lastSkillTime[key] = now
    return true
end

-- Use all available skills
function Combat:UseAllSkills()
    local skillsEnabled = self.config and self.config:Get("Combat", "SkillsEnabled") or
                         {Z = true, X = true, C = false, V = false, F = false}

    for _, key in ipairs(SKILL_KEYS) do
        if skillsEnabled[key] then
            self:UseSkill(key)
        end
    end
end

-- Enable auto haki (buso)
function Combat:EnableHaki()
    local character = GetCharacter()
    if not character then return end

    -- Check if already has haki enabled
    if character:FindFirstChild("HasBuso") then return end

    -- Try to enable haki
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local commF = remotes:FindFirstChild("CommF_")
        if commF then
            pcall(function()
                commF:InvokeServer("Buso")
            end)
        end
    end
end

-- Set current target
function Combat:SetTarget(target)
    self.target = target
end

-- Get current target
function Combat:GetTarget()
    return self.target
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

        -- Find target if not set or invalid
        if not self.target or not self:IsValidTarget(self.target) then
            self.target = self:FindClosestEnemy(questTarget)
        end

        if not self.target then return end

        local distance = GetDistance(self.target)
        local attackRange = self:GetAttackRange()

        -- Only attack if in range
        if distance <= attackRange then
            -- Auto attack
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
end

-- Check if combat is active
function Combat:IsActive()
    return self.enabled
end

-- Check if target is in range
function Combat:IsTargetInRange(target)
    target = target or self.target
    if not target then return false end

    local distance = GetDistance(target)
    return distance <= self:GetAttackRange()
end

-- Get target position (for navigation)
function Combat:GetTargetPosition()
    if not self.target then return nil end

    local targetPart = self.target:FindFirstChild("HumanoidRootPart") or
                       self.target:FindFirstChild("Torso")
    if targetPart then
        return targetPart.Position
    end

    return nil
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
