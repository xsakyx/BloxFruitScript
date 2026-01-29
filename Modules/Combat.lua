--[[
    Combat.lua
    Combat system using actual game remotes to hit mobs
    Uses multiple fallback methods for reliable attacks
]]

local Combat = {}
Combat.__index = Combat

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Constants
local ATTACK_COOLDOWN = 0.15
local SKILL_COOLDOWN = 0.5
local HAKI_COOLDOWN = 2

-- Cache remotes
local CachedRemotes = {}

function Combat.new(config)
    local self = setmetatable({}, Combat)

    self.config = config
    self.enabled = false
    self.currentTarget = nil
    self.lastAttackTime = 0
    self.lastSkillTime = {}
    self.lastHakiTime = 0
    self.selectedWeaponType = "Melee"
    self.combatLoop = nil

    -- Cache game remotes on init
    self:CacheRemotes()

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

-- Cache all relevant remotes
function Combat:CacheRemotes()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end

    -- Main combat remote
    CachedRemotes.CommF = remotes:FindFirstChild("CommF_")

    -- Search for combat-related remotes
    local remoteNames = {
        "Damage", "CombatRemote", "AttackEvent", "SwingSword",
        "SkillRemote", "UseSkill", "ClickDamage", "HitRemote",
        "AoeDamage", "Combat", "Attack", "MeleeAttack"
    }

    for _, name in ipairs(remoteNames) do
        local remote = remotes:FindFirstChild(name)
        if remote then
            CachedRemotes[name] = remote
        end
    end

    -- Also search in tool remotes
    CachedRemotes.ToolRemotes = {}
end

-- Get all weapons
function Combat:GetWeapons()
    local weapons = {
        Melee = {},
        Sword = {},
        ["Demon Fruit"] = {}
    }

    local character = GetCharacter()
    local backpack = LocalPlayer:FindFirstChild("Backpack")

    local function checkTool(tool)
        if tool:IsA("Tool") then
            local weaponType = tool:GetAttribute("WeaponType")
            if weaponType and weapons[weaponType] then
                table.insert(weapons[weaponType], tool)
            end
        end
    end

    if backpack then
        for _, item in pairs(backpack:GetChildren()) do
            checkTool(item)
        end
    end

    if character then
        for _, item in pairs(character:GetChildren()) do
            checkTool(item)
        end
    end

    return weapons
end

-- Get weapon list for dropdown
function Combat:GetWeaponList()
    local list = {}
    local weapons = self:GetWeapons()

    for weaponType, tools in pairs(weapons) do
        for _, tool in ipairs(tools) do
            table.insert(list, tool.Name .. " (" .. weaponType .. ")")
        end
    end

    return list
end

-- Set weapon type
function Combat:SetWeaponType(weaponType)
    self.selectedWeaponType = weaponType
end

function Combat:GetWeaponType()
    return self.selectedWeaponType
end

-- Equip weapon of selected type
function Combat:EquipSelectedWeapon()
    local character, humanoid = GetCharacter()
    if not humanoid then return false end

    local weapons = self:GetWeapons()
    local weaponType = self.selectedWeaponType or "Melee"

    if weapons[weaponType] and #weapons[weaponType] > 0 then
        local tool = weapons[weaponType][1]
        if tool.Parent == character then return true end

        pcall(function()
            humanoid:EquipTool(tool)
        end)
        return true
    end

    return false
end

-- Get nearest enemy to attack
function Combat:GetNearestEnemy()
    local character, _, rootPart = GetCharacter()
    if not rootPart then return nil end

    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return nil end

    local nearest = nil
    local nearestDist = math.huge

    for _, enemy in pairs(enemies:GetChildren()) do
        local humanoid = enemy:FindFirstChild("Humanoid")
        if humanoid and humanoid.Health > 0 then
            local enemyRoot = enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")
            if enemyRoot then
                local dist = (rootPart.Position - enemyRoot.Position).Magnitude
                if dist < nearestDist then
                    nearest = enemy
                    nearestDist = dist
                end
            end
        end
    end

    return nearest, nearestDist
end

-- Attack using multiple methods
function Combat:Attack()
    local now = tick()
    if now - self.lastAttackTime < ATTACK_COOLDOWN then return end
    self.lastAttackTime = now

    local character, _, rootPart = GetCharacter()
    if not character or not rootPart then return end

    -- Get equipped tool
    local tool = character:FindFirstChildOfClass("Tool")
    if not tool then
        self:EquipSelectedWeapon()
        return
    end

    -- Get nearest enemy for targeting
    local target = self.currentTarget or self:GetNearestEnemy()

    -- Method 1: Use CommF_ remote (main Blox Fruits combat remote)
    if CachedRemotes.CommF then
        pcall(function()
            -- Try different combat calls
            CachedRemotes.CommF:InvokeServer("LeftClick", CFrame.new(rootPart.Position))
            if target then
                local targetRoot = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")
                if targetRoot then
                    CachedRemotes.CommF:InvokeServer("LeftClick", targetRoot.CFrame)
                end
            end
        end)
    end

    -- Method 2: Tool remote events
    pcall(function()
        for _, child in pairs(tool:GetDescendants()) do
            if child:IsA("RemoteEvent") then
                child:FireServer()
                if target then
                    child:FireServer(target)
                end
            elseif child:IsA("RemoteFunction") then
                child:InvokeServer()
            end
        end
    end)

    -- Method 3: Tool activation with mouse target
    pcall(function()
        local mouse = LocalPlayer:GetMouse()
        if target then
            local targetRoot = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")
            if targetRoot then
                -- Set mouse target before activation
                mouse.TargetFilter = character
            end
        end
        tool:Activate()
    end)

    -- Method 4: Direct damage remotes
    for _, remoteName in ipairs({"Damage", "CombatRemote", "AttackEvent", "ClickDamage"}) do
        local remote = CachedRemotes[remoteName]
        if remote then
            pcall(function()
                if remote:IsA("RemoteEvent") then
                    remote:FireServer()
                    if target then
                        remote:FireServer(target)
                        remote:FireServer(target, target:FindFirstChild("HumanoidRootPart"))
                    end
                elseif remote:IsA("RemoteFunction") then
                    remote:InvokeServer()
                end
            end)
        end
    end

    -- Method 5: Search remotes folder for any attack-related remote
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        pcall(function()
            for _, remote in pairs(remotes:GetChildren()) do
                local name = remote.Name:lower()
                if name:find("attack") or name:find("combat") or name:find("click") or name:find("swing") then
                    if remote:IsA("RemoteEvent") then
                        remote:FireServer()
                    end
                end
            end
        end)
    end
end

-- Use skill
function Combat:UseSkill(skillKey)
    local now = tick()
    if self.lastSkillTime[skillKey] and now - self.lastSkillTime[skillKey] < SKILL_COOLDOWN then
        return false
    end
    self.lastSkillTime[skillKey] = now

    if not CachedRemotes.CommF then
        self:CacheRemotes()
    end

    if CachedRemotes.CommF then
        pcall(function()
            CachedRemotes.CommF:InvokeServer("ActivateSpecial", skillKey)
            CachedRemotes.CommF:InvokeServer("Skill" .. skillKey)
        end)
    end

    return true
end

-- Use all skills
function Combat:UseAllSkills()
    for _, skill in ipairs({"Z", "X", "C", "V"}) do
        self:UseSkill(skill)
    end
end

-- Enable Haki
function Combat:EnableHaki()
    local now = tick()
    if now - self.lastHakiTime < HAKI_COOLDOWN then return end
    self.lastHakiTime = now

    local character = GetCharacter()
    if not character then return end
    if character:FindFirstChild("HasBuso") then return end

    if CachedRemotes.CommF then
        pcall(function()
            CachedRemotes.CommF:InvokeServer("Buso")
        end)
    end
end

-- Set target
function Combat:SetTarget(target)
    self.currentTarget = target
end

function Combat:GetTarget()
    return self.currentTarget
end

-- Start combat loop
function Combat:Start(mobName)
    if self.enabled then return end
    self.enabled = true

    self:CacheRemotes()

    self.combatLoop = RunService.Heartbeat:Connect(function()
        if not self.enabled then return end

        pcall(function()
            self:EquipSelectedWeapon()
            self:Attack()

            if self.config and self.config:Get("Combat", "AutoSkills") then
                self:UseAllSkills()
            end

            if self.config and self.config:Get("Combat", "AutoHaki") then
                self:EnableHaki()
            end
        end)
    end)
end

-- Stop combat
function Combat:Stop()
    self.enabled = false

    if self.combatLoop then
        self.combatLoop:Disconnect()
        self.combatLoop = nil
    end

    self.currentTarget = nil
end

function Combat:IsActive()
    return self.enabled
end

function Combat:Destroy()
    self:Stop()
end

return {
    new = Combat.new
}
