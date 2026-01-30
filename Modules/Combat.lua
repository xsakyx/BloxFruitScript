--[[
    Combat.lua
    Professional Combat System with Selectable Attack Methods

    Attack Methods:
    1. M1 (Mouse Click) - Uses VirtualInputManager
    2. Remote Events - Uses game remotes (CommF_, etc.)
    3. Hook Functions - Hooks into game modules
    4. FireTouchInterest - Direct touch simulation
    5. All Methods Combined - Uses all methods for reliability

    Features:
    - Configurable attack cooldown
    - Configurable skill cooldown
    - Auto skills (Z, X, C, V)
    - Auto Haki (J key)
    - Weapon type selection
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

-- Attack method constants
local ATTACK_METHODS = {
    M1 = "M1 (Mouse Click)",
    REMOTE = "Remote Events",
    HOOK = "Hook Functions",
    TOUCH = "FireTouchInterest",
    ALL = "All Methods Combined"
}

-- Default settings
local DEFAULT_ATTACK_COOLDOWN = 0.1
local DEFAULT_SKILL_COOLDOWN = 0.3
local HAKI_COOLDOWN = 2

-- Cached references
local CachedRemotes = {}
local HookedFunctions = {}

function Combat.new(config)
    local self = setmetatable({}, Combat)

    self.config = config
    self.enabled = false
    self.currentTarget = nil
    self.lastAttackTime = 0
    self.lastSkillTime = {}
    self.lastHakiTime = 0
    self.selectedWeaponType = "Melee"
    self.attackMethod = "All Methods Combined"
    self.attackCooldown = DEFAULT_ATTACK_COOLDOWN
    self.skillCooldown = DEFAULT_SKILL_COOLDOWN
    self.combatLoop = nil

    -- Initialize
    self:CacheRemotes()
    self:SetupHooks()

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

    -- Cache all remotes for searching
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

-- Setup function hooks for combat
function Combat:SetupHooks()
    -- Try to hook into game combat functions
    pcall(function()
        -- This is where you'd implement metatable hooks
        -- Note: Implementation depends on executor capabilities
        local mt = getrawmetatable(game)
        if mt and setreadonly then
            -- Store original namecall
            local oldNamecall = mt.__namecall

            -- Hook namecall for combat interception
            -- (This is a placeholder - actual implementation varies by executor)
            HookedFunctions.namecall = oldNamecall
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

-- Set attack method
function Combat:SetAttackMethod(method)
    self.attackMethod = method
end

-- Get attack method
function Combat:GetAttackMethod()
    return self.attackMethod
end

-- Set/Get weapon type
function Combat:SetWeaponType(weaponType)
    self.selectedWeaponType = weaponType
end

function Combat:GetWeaponType()
    return self.selectedWeaponType
end

-- Set attack cooldown
function Combat:SetAttackCooldown(cooldown)
    self.attackCooldown = cooldown
end

-- Set skill cooldown
function Combat:SetSkillCooldown(cooldown)
    self.skillCooldown = cooldown
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

-- ATTACK METHOD 1: M1 Mouse Clicks
function Combat:AttackM1()
    pcall(function()
        -- Simulate mouse down then up
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        task.wait()
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    end)
end

-- ATTACK METHOD 2: Remote Events
function Combat:AttackRemote(target, targetRoot)
    local character, _, rootPart = GetCharacter()
    if not rootPart then return end

    -- CommF_ remote (main Blox Fruits combat)
    if CachedRemotes.CommF then
        pcall(function()
            CachedRemotes.CommF:InvokeServer("LeftClick", CFrame.new(rootPart.Position))

            if targetRoot then
                CachedRemotes.CommF:InvokeServer("LeftClick", targetRoot.CFrame)
                CachedRemotes.CommF:InvokeServer("MeleeAttack", targetRoot.CFrame)
                CachedRemotes.CommF:InvokeServer("SwingSword", targetRoot.CFrame)
            end
        end)
    end

    -- Search and fire all combat-related remotes
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
end

-- ATTACK METHOD 3: Hook Functions
function Combat:AttackHook(target, targetRoot)
    local character = GetCharacter()
    if not character then return end

    local tool = character:FindFirstChildOfClass("Tool")
    if not tool then return end

    -- Try to fire tool's internal events
    pcall(function()
        local clickEvent = tool:FindFirstChild("ClickEvent") or tool:FindFirstChild("RemoteEvent")
        if clickEvent and clickEvent:IsA("RemoteEvent") then
            clickEvent:FireServer()
            if target then
                clickEvent:FireServer(target)
            end
        end

        local clickFunc = tool:FindFirstChild("RemoteFunction")
        if clickFunc then
            clickFunc:InvokeServer()
        end

        -- Activate tool
        tool:Activate()
    end)
end

-- ATTACK METHOD 4: FireTouchInterest
function Combat:AttackTouch(target, targetRoot)
    local character = GetCharacter()
    if not character then return end

    local tool = character:FindFirstChildOfClass("Tool")
    if not tool then return end

    if target and targetRoot and firetouchinterest then
        pcall(function()
            local handle = tool:FindFirstChild("Handle")
            if handle then
                firetouchinterest(handle, targetRoot, 0)
                task.wait()
                firetouchinterest(handle, targetRoot, 1)
            end
        end)
    end
end

-- MAIN ATTACK FUNCTION
function Combat:Attack()
    local now = tick()
    if now - self.lastAttackTime < self.attackCooldown then return end
    self.lastAttackTime = now

    local character, _, rootPart = GetCharacter()
    if not character or not rootPart then return end

    -- Ensure weapon is equipped
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

    -- Execute attack based on selected method
    local method = self.attackMethod

    if method == ATTACK_METHODS.M1 then
        self:AttackM1()

    elseif method == ATTACK_METHODS.REMOTE then
        self:AttackRemote(target, targetRoot)

    elseif method == ATTACK_METHODS.HOOK then
        self:AttackHook(target, targetRoot)

    elseif method == ATTACK_METHODS.TOUCH then
        self:AttackTouch(target, targetRoot)

    else -- All Methods Combined
        self:AttackM1()
        self:AttackRemote(target, targetRoot)
        self:AttackHook(target, targetRoot)
        self:AttackTouch(target, targetRoot)
    end
end

-- Use skill
function Combat:UseSkill(skillKey)
    local now = tick()
    if self.lastSkillTime[skillKey] and now - self.lastSkillTime[skillKey] < self.skillCooldown then
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
    new = Combat.new,
    ATTACK_METHODS = ATTACK_METHODS
}
