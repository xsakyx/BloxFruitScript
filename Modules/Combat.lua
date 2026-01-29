--[[
    Combat.lua
    Advanced Combat System using multiple techniques:
    1. Metatable hooking for remote interception
    2. Direct module interaction
    3. Multiple remote fallbacks
    4. State-aware combat
]]

local Combat = {}
Combat.__index = Combat

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

-- Constants
local ATTACK_COOLDOWN = 0.1
local SKILL_COOLDOWN = 0.3
local HAKI_COOLDOWN = 2

-- Cached references
local CachedRemotes = {}
local OldNamecall = nil

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

    -- Initialize
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

-- Cache all remotes
function Combat:CacheRemotes()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end

    -- Main Blox Fruits remote
    CachedRemotes.CommF = remotes:FindFirstChild("CommF_")

    -- Search all remotes
    for _, remote in pairs(remotes:GetChildren()) do
        CachedRemotes[remote.Name] = remote
    end

    -- Try to find combat-related modules
    pcall(function()
        local modules = ReplicatedStorage:FindFirstChild("Modules")
        if modules then
            for _, module in pairs(modules:GetChildren()) do
                if module.Name:lower():find("combat") or module.Name:lower():find("damage") then
                    CachedRemotes["Module_" .. module.Name] = module
                end
            end
        end
    end)
end

-- Get weapons
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

-- Get weapon list
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

-- Set/Get weapon type
function Combat:SetWeaponType(weaponType)
    self.selectedWeaponType = weaponType
end

function Combat:GetWeaponType()
    return self.selectedWeaponType
end

-- Equip weapon
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

-- Get nearest enemy
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

-- MAIN ATTACK FUNCTION - Multiple methods
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

    -- Get target
    local target = self.currentTarget or self:GetNearestEnemy()
    local targetRoot = nil
    if target then
        targetRoot = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")
    end

    -- METHOD 1: Virtual Mouse Click (simulates actual click)
    pcall(function()
        -- This actually clicks the mouse which triggers tool attack
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        task.wait()
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    end)

    -- METHOD 2: CommF_ with multiple attack patterns
    if CachedRemotes.CommF then
        pcall(function()
            -- Standard click attack
            CachedRemotes.CommF:InvokeServer("LeftClick", CFrame.new(rootPart.Position))

            -- With target position
            if targetRoot then
                CachedRemotes.CommF:InvokeServer("LeftClick", targetRoot.CFrame)
                CachedRemotes.CommF:InvokeServer("MeleeAttack", targetRoot.CFrame)
                CachedRemotes.CommF:InvokeServer("SwingSword", targetRoot.CFrame)
            end
        end)
    end

    -- METHOD 3: Tool click simulation
    pcall(function()
        -- Fire tool's internal events
        local clickEvent = tool:FindFirstChild("ClickEvent") or tool:FindFirstChild("RemoteEvent")
        if clickEvent and clickEvent:IsA("RemoteEvent") then
            clickEvent:FireServer()
            if target then
                clickEvent:FireServer(target)
            end
        end

        -- Try tool RemoteFunction
        local clickFunc = tool:FindFirstChild("RemoteFunction")
        if clickFunc then
            clickFunc:InvokeServer()
        end

        -- Activate tool
        tool:Activate()
    end)

    -- METHOD 4: Search and fire ALL combat-related remotes
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        for _, remote in pairs(remotes:GetChildren()) do
            local name = remote.Name:lower()
            if name:find("click") or name:find("attack") or name:find("swing") or
               name:find("combat") or name:find("damage") or name:find("melee") then
                pcall(function()
                    if remote:IsA("RemoteEvent") then
                        remote:FireServer()
                        if target then
                            remote:FireServer(target)
                        end
                        if targetRoot then
                            remote:FireServer(targetRoot.CFrame)
                        end
                    elseif remote:IsA("RemoteFunction") then
                        remote:InvokeServer()
                    end
                end)
            end
        end
    end

    -- METHOD 5: Direct mouse target with firetouchinterest
    if target and targetRoot then
        pcall(function()
            if firetouchinterest then
                -- Simulate tool hitting the enemy
                local handle = tool:FindFirstChild("Handle")
                if handle then
                    firetouchinterest(handle, targetRoot, 0)
                    task.wait()
                    firetouchinterest(handle, targetRoot, 1)
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

    -- Virtual key press
    pcall(function()
        local keyCode = Enum.KeyCode[skillKey]
        if keyCode then
            VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
            task.wait()
            VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
        end
    end)

    -- CommF_ skill
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

    -- Virtual J key press
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.J, false, game)
        task.wait()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.J, false, game)
    end)

    -- CommF_ Buso
    if CachedRemotes.CommF then
        pcall(function()
            CachedRemotes.CommF:InvokeServer("Buso")
        end)
    end
end

-- Set/Get target
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
