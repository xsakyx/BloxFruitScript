--[[
    Combat.lua
    Combat system using game remotes (no input blocking)
    Features: Weapon selection, skills, haki via game APIs
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
local ATTACK_COOLDOWN = 0.1
local SKILL_COOLDOWN = 0.3
local HAKI_COOLDOWN = 1

function Combat.new(config)
    local self = setmetatable({}, Combat)

    self.config = config
    self.enabled = false
    self.currentTarget = nil
    self.lastAttackTime = 0
    self.lastSkillTime = {}
    self.lastHakiTime = 0
    self.selectedWeaponType = "Melee" -- "Melee", "Sword", or "Demon Fruit"
    self.combatLoop = nil

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

-- Get all weapons from backpack and character
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

    -- Check backpack
    if backpack then
        for _, item in pairs(backpack:GetChildren()) do
            checkTool(item)
        end
    end

    -- Check character (equipped tools)
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
            table.insert(list, {
                Name = tool.Name,
                Type = weaponType,
                Tool = tool
            })
        end
    end

    return list
end

-- Get weapon names by type for dropdown
function Combat:GetWeaponNamesByType(weaponType)
    local names = {}
    local weapons = self:GetWeapons()

    if weapons[weaponType] then
        for _, tool in ipairs(weapons[weaponType]) do
            table.insert(names, tool.Name)
        end
    end

    return names
end

-- Set selected weapon type
function Combat:SetWeaponType(weaponType)
    self.selectedWeaponType = weaponType
end

-- Get selected weapon type
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
        -- Check if already equipped
        if tool.Parent == character then return true end

        -- Equip the tool
        pcall(function()
            humanoid:EquipTool(tool)
        end)
        return true
    end

    return false
end

-- Equip specific weapon by name
function Combat:EquipWeaponByName(weaponName)
    local character, humanoid = GetCharacter()
    if not humanoid then return false end

    local backpack = LocalPlayer:FindFirstChild("Backpack")

    -- Check backpack
    if backpack then
        local tool = backpack:FindFirstChild(weaponName)
        if tool and tool:IsA("Tool") then
            pcall(function()
                humanoid:EquipTool(tool)
            end)
            return true
        end
    end

    -- Check if already equipped
    if character then
        local tool = character:FindFirstChild(weaponName)
        if tool and tool:IsA("Tool") then
            return true
        end
    end

    return false
end

-- Attack using game remotes (doesn't block input)
function Combat:Attack()
    local now = tick()
    if now - self.lastAttackTime < ATTACK_COOLDOWN then return end
    self.lastAttackTime = now

    local character = GetCharacter()
    if not character then return end

    -- Find equipped tool
    local tool = character:FindFirstChildOfClass("Tool")
    if not tool then
        self:EquipSelectedWeapon()
        return
    end

    -- Activate tool (this triggers the weapon's attack)
    pcall(function()
        tool:Activate()
    end)

    -- Also try remote events on the tool
    pcall(function()
        local remote = tool:FindFirstChildOfClass("RemoteEvent")
        if remote then
            remote:FireServer()
        end
    end)
end

-- Use skill via game remote
function Combat:UseSkill(skillKey)
    local now = tick()
    if self.lastSkillTime[skillKey] and now - self.lastSkillTime[skillKey] < SKILL_COOLDOWN then
        return false
    end
    self.lastSkillTime[skillKey] = now

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return false end

    local commF = remotes:FindFirstChild("CommF_")
    if commF then
        pcall(function()
            -- Try different skill invocation methods
            commF:InvokeServer("Skill" .. skillKey)
            commF:InvokeServer("UseSkill", skillKey)
        end)
    end

    return true
end

-- Use all skills
function Combat:UseAllSkills()
    local skills = {"Z", "X", "C", "V"}
    for _, skill in ipairs(skills) do
        self:UseSkill(skill)
        task.wait(0.05)
    end
end

-- Enable Haki using game remote
function Combat:EnableHaki()
    local now = tick()
    if now - self.lastHakiTime < HAKI_COOLDOWN then return end
    self.lastHakiTime = now

    local character = GetCharacter()
    if not character then return end

    -- Check if already has Haki
    if character:FindFirstChild("HasBuso") then return end

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

-- Disable hitbox expansion (not visual)
function Combat:ExpandHitbox(entity, size)
    -- Don't expand visual hitbox, just disable collision
    if not entity then return end

    local rootPart = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso")
    if rootPart then
        pcall(function()
            rootPart.CanCollide = false
        end)
    end
end

-- Restore hitbox (no-op since we don't change size)
function Combat:RestoreHitbox(entity)
    -- Nothing to restore since we only disable collision
end

-- Set current target
function Combat:SetTarget(target)
    self.currentTarget = target
end

-- Get current target
function Combat:GetTarget()
    return self.currentTarget
end

-- Start combat loop
function Combat:Start(mobName)
    if self.enabled then return end
    self.enabled = true

    self.combatLoop = RunService.Heartbeat:Connect(function()
        if not self.enabled then return end

        pcall(function()
            -- Equip weapon
            self:EquipSelectedWeapon()

            -- Attack
            self:Attack()

            -- Use skills if configured
            if self.config and self.config:Get("Combat", "AutoSkills") then
                self:UseAllSkills()
            end

            -- Enable Haki if configured
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

-- Check if combat is active
function Combat:IsActive()
    return self.enabled
end

-- Cleanup
function Combat:Destroy()
    self:Stop()
end

return {
    new = Combat.new
}
