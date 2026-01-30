--[[
    Combat.lua
    Professional Combat System - PROVEN METHODS

    Based on research from working Blox Fruits scripts:
    - firetouchinterest for direct hit registration
    - VirtualInputManager for M1 click simulation
    - Tool:Activate() for weapon activation
    - Proper hitbox expansion on HumanoidRootPart

    Attack Methods:
    1. M1 (Mouse Click) - VirtualInputManager click simulation
    2. FireTouchInterest - Direct touch event simulation (MOST RELIABLE)
    3. Tool Activate - Direct tool activation
    4. All Methods Combined - Uses all for maximum reliability
]]

local Combat = {}
Combat.__index = Combat

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- Try to get VirtualInputManager (may not exist in all executors)
local VirtualInputManager = nil
pcall(function()
    VirtualInputManager = game:GetService("VirtualInputManager")
end)

-- Attack method constants
local ATTACK_METHODS = {
    M1 = "M1 (Mouse Click)",
    TOUCH = "FireTouchInterest",
    TOOL = "Tool Activate",
    ALL = "All Methods Combined"
}

-- Default settings
local DEFAULT_ATTACK_COOLDOWN = 0.1
local DEFAULT_SKILL_COOLDOWN = 0.5
local HAKI_COOLDOWN = 2

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

    -- Check for executor functions
    self.hasFireTouchInterest = firetouchinterest ~= nil
    self.hasVirtualInputManager = VirtualInputManager ~= nil

    print("[Combat] Initialized")
    print("[Combat] firetouchinterest available:", self.hasFireTouchInterest)
    print("[Combat] VirtualInputManager available:", self.hasVirtualInputManager)

    return self
end

-- Get character safely
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

-- Get equipped tool
local function GetEquippedTool()
    local character = GetCharacter()
    if not character then return nil end
    return character:FindFirstChildOfClass("Tool")
end

-- Get tool handle (the part that deals damage)
local function GetToolHandle(tool)
    if not tool then return nil end
    return tool:FindFirstChild("Handle")
end

-- Set attack method
function Combat:SetAttackMethod(method)
    self.attackMethod = method
    print("[Combat] Attack method set to:", method)
end

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

-- Get weapons from backpack and character
function Combat:GetWeapons()
    local weapons = {
        Melee = {},
        Sword = {},
        ["Demon Fruit"] = {}
    }

    local character = GetCharacter()
    local backpack = LocalPlayer:FindFirstChild("Backpack")

    -- Helper to categorize tool
    local function categorizeTool(tool)
        if not tool:IsA("Tool") then return end

        local name = tool.Name:lower()
        local weaponType = tool:GetAttribute("WeaponType")

        -- Check attribute first
        if weaponType and weapons[weaponType] then
            table.insert(weapons[weaponType], tool)
            return
        end

        -- Categorize by name patterns
        if name:find("combat") or name:find("fist") or name:find("boxing") or
           name:find("superhuman") or name:find("brawler") or name:find("godhuman") or
           name:find("sharkman") or name:find("electric") or name:find("dragon") or
           name:find("death step") then
            table.insert(weapons.Melee, tool)
        elseif name:find("sword") or name:find("blade") or name:find("cutlass") or
               name:find("katana") or name:find("saber") or name:find("trident") or
               name:find("pole") or name:find("yama") or name:find("tushita") then
            table.insert(weapons.Sword, tool)
        elseif tool:FindFirstChild("RemoteEvent") or tool:FindFirstChild("SpecialMesh") then
            -- Likely a devil fruit or special weapon
            table.insert(weapons["Demon Fruit"], tool)
        else
            -- Default to melee for unknown tools
            table.insert(weapons.Melee, tool)
        end
    end

    if backpack then
        for _, item in pairs(backpack:GetChildren()) do
            categorizeTool(item)
        end
    end

    if character then
        for _, item in pairs(character:GetChildren()) do
            categorizeTool(item)
        end
    end

    return weapons
end

-- Equip the selected weapon type
function Combat:EquipSelectedWeapon()
    local character, humanoid = GetCharacter()
    if not humanoid then return false end

    -- Check if already have a tool equipped
    local currentTool = character:FindFirstChildOfClass("Tool")
    if currentTool then return true end

    local weapons = self:GetWeapons()
    local weaponType = self.selectedWeaponType or "Melee"

    -- Try to equip from selected category
    if weapons[weaponType] and #weapons[weaponType] > 0 then
        local tool = weapons[weaponType][1]
        if tool.Parent ~= character then
            pcall(function()
                humanoid:EquipTool(tool)
            end)
        end
        return true
    end

    -- Fallback: equip any available tool
    for _, category in pairs(weapons) do
        if #category > 0 then
            local tool = category[1]
            if tool.Parent ~= character then
                pcall(function()
                    humanoid:EquipTool(tool)
                end)
            end
            return true
        end
    end

    return false
end

-- Get nearest enemy
function Combat:GetNearestEnemy(maxDistance)
    local character, _, rootPart = GetCharacter()
    if not rootPart then return nil end

    maxDistance = maxDistance or math.huge
    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return nil end

    local nearest = nil
    local nearestDist = maxDistance

    for _, enemy in pairs(enemies:GetChildren()) do
        if enemy:IsA("Model") then
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
    end

    return nearest, nearestDist
end

-- Get all enemies within range
function Combat:GetEnemiesInRange(range)
    local character, _, rootPart = GetCharacter()
    if not rootPart then return {} end

    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return {} end

    local inRange = {}

    for _, enemy in pairs(enemies:GetChildren()) do
        if enemy:IsA("Model") then
            local humanoid = enemy:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then
                local enemyRoot = enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")
                if enemyRoot then
                    local dist = (rootPart.Position - enemyRoot.Position).Magnitude
                    if dist <= range then
                        table.insert(inRange, {
                            enemy = enemy,
                            root = enemyRoot,
                            humanoid = humanoid,
                            distance = dist
                        })
                    end
                end
            end
        end
    end

    -- Sort by distance
    table.sort(inRange, function(a, b)
        return a.distance < b.distance
    end)

    return inRange
end

--[[
    ATTACK METHOD 1: M1 Mouse Clicks
    Uses VirtualInputManager to simulate mouse button clicks
    This triggers the game's normal attack detection
]]
function Combat:AttackM1()
    if not self.hasVirtualInputManager then return false end

    local success = pcall(function()
        -- Mouse button down (0 = left click)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        task.wait()
        -- Mouse button up
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end)

    return success
end

--[[
    ATTACK METHOD 2: FireTouchInterest (MOST RELIABLE)
    Simulates touch events between tool handle and enemy parts
    This is the primary method used by working Blox Fruits scripts

    Syntax: firetouchinterest(Part1, Part2, Toggle)
    - Part1: The part initiating touch (tool handle or player part)
    - Part2: The part being touched (enemy HumanoidRootPart)
    - Toggle: 0 = start touch, 1 = end touch
]]
function Combat:AttackFireTouch(target, targetRoot)
    if not self.hasFireTouchInterest then return false end
    if not target or not targetRoot then return false end

    local character, _, rootPart = GetCharacter()
    if not character or not rootPart then return false end

    local tool = GetEquippedTool()
    local handle = tool and GetToolHandle(tool)

    -- Part to use for touch (prefer tool handle, fallback to HumanoidRootPart)
    local touchPart = handle or rootPart

    local success = pcall(function()
        -- Fire touch event on enemy's HumanoidRootPart
        firetouchinterest(touchPart, targetRoot, 0)
        task.wait()
        firetouchinterest(touchPart, targetRoot, 1)

        -- Also try touching the enemy's Torso if it exists
        local torso = target:FindFirstChild("Torso")
        if torso then
            firetouchinterest(touchPart, torso, 0)
            task.wait()
            firetouchinterest(touchPart, torso, 1)
        end

        -- Try touching Head for good measure
        local head = target:FindFirstChild("Head")
        if head then
            firetouchinterest(touchPart, head, 0)
            task.wait()
            firetouchinterest(touchPart, head, 1)
        end
    end)

    return success
end

--[[
    ATTACK METHOD 3: Tool Activate
    Directly activates the equipped tool
    This simulates clicking while holding a weapon
]]
function Combat:AttackToolActivate()
    local tool = GetEquippedTool()
    if not tool then return false end

    local success = pcall(function()
        tool:Activate()
    end)

    return success
end

--[[
    MAIN ATTACK FUNCTION
    Executes attack based on selected method
    Targets the nearest enemy or specified target
]]
function Combat:Attack(specificTarget)
    local now = tick()
    if now - self.lastAttackTime < self.attackCooldown then return false end
    self.lastAttackTime = now

    local character, _, rootPart = GetCharacter()
    if not character or not rootPart then return false end

    -- Ensure weapon is equipped
    local tool = GetEquippedTool()
    if not tool then
        self:EquipSelectedWeapon()
        return false
    end

    -- Get target
    local target = specificTarget or self.currentTarget
    local targetRoot = nil

    if not target then
        target = self:GetNearestEnemy(200)
    end

    if target then
        targetRoot = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")
    end

    -- Execute attack based on selected method
    local method = self.attackMethod
    local attacked = false

    if method == ATTACK_METHODS.M1 then
        attacked = self:AttackM1()

    elseif method == ATTACK_METHODS.TOUCH then
        attacked = self:AttackFireTouch(target, targetRoot)

    elseif method == ATTACK_METHODS.TOOL then
        attacked = self:AttackToolActivate()

    else -- All Methods Combined (default and most reliable)
        -- Try all methods for maximum hit registration
        self:AttackToolActivate()
        self:AttackM1()
        if target and targetRoot then
            self:AttackFireTouch(target, targetRoot)
        end
        attacked = true
    end

    return attacked
end

--[[
    Attack all enemies in range using FireTouchInterest
    This is the "Kill Aura" / "Mob Aura" effect
]]
function Combat:AttackAllInRange(range)
    range = range or 50

    local enemies = self:GetEnemiesInRange(range)
    local attackedCount = 0

    for _, data in ipairs(enemies) do
        if self:AttackFireTouch(data.enemy, data.root) then
            attackedCount = attackedCount + 1
        end
        self:AttackToolActivate()
    end

    return attackedCount
end

--[[
    Use skill (Z, X, C, V keys)
    Simulates key press using VirtualInputManager
]]
function Combat:UseSkill(skillKey)
    local now = tick()
    if self.lastSkillTime[skillKey] and now - self.lastSkillTime[skillKey] < self.skillCooldown then
        return false
    end
    self.lastSkillTime[skillKey] = now

    if self.hasVirtualInputManager then
        pcall(function()
            local keyCode = Enum.KeyCode[skillKey]
            if keyCode then
                VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
                task.wait(0.05)
                VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
            end
        end)
    end

    return true
end

-- Use all skills (Z, X, C, V)
function Combat:UseAllSkills()
    for _, skill in ipairs({"Z", "X", "C", "V"}) do
        self:UseSkill(skill)
        task.wait(0.05)
    end
end

--[[
    Enable Haki (Buso/Armament)
    Simulates J key press
]]
function Combat:EnableHaki()
    local now = tick()
    if now - self.lastHakiTime < HAKI_COOLDOWN then return false end
    self.lastHakiTime = now

    local character = GetCharacter()
    if not character then return false end

    -- Check if already has Buso active
    if character:FindFirstChild("HasBuso") then return true end

    if self.hasVirtualInputManager then
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.J, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.J, false, game)
        end)
    end

    return true
end

-- Set/Get target
function Combat:SetTarget(target)
    self.currentTarget = target
end

function Combat:GetTarget()
    return self.currentTarget
end

-- Start continuous combat loop
function Combat:Start()
    if self.enabled then return end
    self.enabled = true

    print("[Combat] Combat loop started")

    self.combatLoop = RunService.Heartbeat:Connect(function()
        if not self.enabled then return end

        pcall(function()
            -- Equip weapon
            self:EquipSelectedWeapon()

            -- Attack
            self:Attack()

            -- Use skills if enabled
            if self.config and self.config:Get("Combat", "AutoSkills") then
                self:UseAllSkills()
            end

            -- Enable haki if enabled
            if self.config and self.config:Get("Combat", "AutoHaki") then
                self:EnableHaki()
            end
        end)
    end)
end

-- Stop combat loop
function Combat:Stop()
    self.enabled = false

    if self.combatLoop then
        self.combatLoop:Disconnect()
        self.combatLoop = nil
    end

    self.currentTarget = nil
    print("[Combat] Combat loop stopped")
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
