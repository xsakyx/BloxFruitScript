--[[
    AutoFarm.lua
    Professional Auto Farm System

    Features:
    - Continuous farming with no time limit
    - Configurable hitbox expansion
    - Configurable mob anchoring
    - Weapon type selection
    - Fly height customization
    - Bring distance customization
    - NoClip during farming
    - State machine architecture
]]

local AutoFarm = {}
AutoFarm.__index = AutoFarm

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- Module dependencies (will be injected)
local Teleport
local Combat
local StateManager
local Config

-- Default settings
local DEFAULT_FLY_HEIGHT = 15
local DEFAULT_BRING_DISTANCE = 150
local DEFAULT_HITBOX_SIZE = 50
local MOB_GROUP_RADIUS = 5

function AutoFarm.new(config, teleport, combat, stateManager)
    local self = setmetatable({}, AutoFarm)

    Config = config
    Teleport = teleport
    Combat = combat
    StateManager = stateManager

    self.config = config
    self.teleport = teleport
    self.combat = combat
    self.stateManager = stateManager

    self.enabled = false
    self.currentQuest = nil
    self.questData = nil
    self.npcsData = nil
    self.islandsData = nil
    self.currentMobName = nil
    self.mobKillCount = 0
    self.requiredKills = 0
    self.farmPosition = nil
    self.selectedWeaponType = "Melee"

    -- Configurable options
    self.flyHeight = DEFAULT_FLY_HEIGHT
    self.bringDistance = DEFAULT_BRING_DISTANCE
    self.hitboxSize = DEFAULT_HITBOX_SIZE
    self.expandHitbox = true
    self.anchorMobs = true
    self.bringMobs = true

    self.mainLoop = nil
    self.noclipLoop = nil
    self.mobAuraLoop = nil  -- NEW: Separate loop for mob bringing
    self.noclipEnabled = true
    self.isTweeningToFarm = false  -- NEW: Track if we're tweening to farm spot
    self.hasReachedFarmSpot = false  -- NEW: Track if we've reached the farm spot

    self.callbacks = {
        onQuestStart = nil,
        onQuestComplete = nil,
        onMobKill = nil,
        onLevelUp = nil,
        onError = nil
    }

    return self
end

-- Load data from JSON files
function AutoFarm:LoadData(quests, npcs, islands)
    self.questData = quests
    self.npcsData = npcs
    self.islandsData = islands
end

-- Get character info
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

-- Get player level
local function GetPlayerLevel()
    local data = LocalPlayer:FindFirstChild("Data")
    if data then
        local level = data:FindFirstChild("Level")
        if level then
            return level.Value
        end
    end
    return 0
end

-- Get current sea based on place ID
local function GetCurrentSea()
    local placeIds = {
        [2753915549] = 1,
        [4442272183] = 2,
        [7449423635] = 3
    }
    return placeIds[game.PlaceId] or 1
end

-- Get sea key for quest data
local function GetSeaKey(sea)
    return "Sea" .. tostring(sea)
end

-- Enable noclip for the character
function AutoFarm:EnableNoclip()
    local character = GetCharacter()
    if not character then return end

    for _, part in pairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end
end

-- Noclip loop
function AutoFarm:StartNoclip()
    if self.noclipLoop then return end

    self.noclipLoop = RunService.Stepped:Connect(function()
        if not self.enabled then return end
        if not self.noclipEnabled then return end
        self:EnableNoclip()
    end)
end

function AutoFarm:StopNoclip()
    if self.noclipLoop then
        self.noclipLoop:Disconnect()
        self.noclipLoop = nil
    end
end

--[[
    MOB AURA SYSTEM
    This runs on RenderStepped (every frame) to continuously:
    1. Bring all nearby mobs to player
    2. Expand their hitboxes
    3. Anchor them in place
    4. Attack them all simultaneously

    This is the KEY technique that makes mob farming work!
]]
function AutoFarm:StartMobAura()
    if self.mobAuraLoop then return end

    print("[AutoFarm] Mob Aura started")

    self.mobAuraLoop = RunService.RenderStepped:Connect(function()
        if not self.enabled then return end
        if not self.currentMobName then return end
        if not self.hasReachedFarmSpot then return end

        local character, _, rootPart = GetCharacter()
        if not rootPart then return end

        -- Get settings
        local shouldBring = self:GetBringMobs()
        local shouldAnchor = self:GetAnchorMobs()
        local shouldExpandHitbox = self:GetExpandHitbox()
        local hitboxSize = self:GetHitboxSize()
        local bringDistance = self:GetBringDistance()
        local flyHeight = self:GetFlyHeight()

        -- Get all enemies of the target type
        local enemies = self:FindAllEnemies(self.currentMobName)

        -- Calculate farm position (where player is flying)
        local farmPos = rootPart.Position - Vector3.new(0, flyHeight, 0)

        for _, data in ipairs(enemies) do
            local distance = (data.RootPart.Position - rootPart.Position).Magnitude

            -- Only process mobs within bring distance
            if distance <= bringDistance then
                pcall(function()
                    -- STEP 1: Claim network ownership (critical for client-side manipulation)
                    if sethiddenproperty then
                        pcall(function()
                            sethiddenproperty(data.RootPart, "NetworkOwnershipRule", 2) -- Manual
                        end)
                    end

                    -- STEP 2: Expand hitbox for easier hits
                    if shouldExpandHitbox then
                        data.RootPart.Size = Vector3.new(hitboxSize, hitboxSize, hitboxSize)
                        data.RootPart.Transparency = 1
                        data.RootPart.CanCollide = false

                        -- Also expand other parts
                        for _, partName in ipairs({"Torso", "Head", "UpperTorso", "LowerTorso"}) do
                            local part = data.Entity:FindFirstChild(partName)
                            if part and part:IsA("BasePart") then
                                part.Size = Vector3.new(hitboxSize, hitboxSize, hitboxSize)
                                part.Transparency = 1
                                part.CanCollide = false
                            end
                        end
                    end

                    -- STEP 3: Bring mob to player (teleport using CFrame)
                    if shouldBring then
                        -- Random offset so mobs don't stack perfectly
                        local offset = Vector3.new(
                            math.random(-3, 3),
                            0,
                            math.random(-3, 3)
                        )
                        data.RootPart.CFrame = CFrame.new(farmPos + offset)

                        -- Zero all velocity
                        data.RootPart.Velocity = Vector3.zero
                        pcall(function()
                            data.RootPart.AssemblyLinearVelocity = Vector3.zero
                            data.RootPart.AssemblyAngularVelocity = Vector3.zero
                        end)
                    end

                    -- STEP 4: Anchor to prevent movement
                    if shouldAnchor then
                        data.RootPart.Anchored = true
                    end

                    -- Disable collision on all parts
                    for _, part in pairs(data.Entity:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = false
                        end
                    end
                end)
            end
        end
    end)
end

function AutoFarm:StopMobAura()
    if self.mobAuraLoop then
        self.mobAuraLoop:Disconnect()
        self.mobAuraLoop = nil
    end
end

-- Set weapon type for farming
function AutoFarm:SetWeaponType(weaponType)
    self.selectedWeaponType = weaponType
    if self.combat then
        self.combat:SetWeaponType(weaponType)
    end
end

function AutoFarm:GetWeaponType()
    return self.selectedWeaponType
end

-- Set fly height
function AutoFarm:SetFlyHeight(height)
    self.flyHeight = height
end

function AutoFarm:GetFlyHeight()
    return self.flyHeight or (self.config and self.config:Get("AutoFarm", "FlyHeight")) or DEFAULT_FLY_HEIGHT
end

-- Set bring distance
function AutoFarm:SetBringDistance(distance)
    self.bringDistance = distance
end

function AutoFarm:GetBringDistance()
    return self.bringDistance or (self.config and self.config:Get("AutoFarm", "BringDistance")) or DEFAULT_BRING_DISTANCE
end

-- Set hitbox expansion
function AutoFarm:SetExpandHitbox(enabled)
    self.expandHitbox = enabled
end

function AutoFarm:GetExpandHitbox()
    if self.config then
        return self.config:Get("AutoFarm", "ExpandHitbox")
    end
    return self.expandHitbox
end

-- Set hitbox size
function AutoFarm:SetHitboxSize(size)
    self.hitboxSize = size
end

function AutoFarm:GetHitboxSize()
    return self.hitboxSize or (self.config and self.config:Get("AutoFarm", "HitboxSize")) or DEFAULT_HITBOX_SIZE
end

-- Set mob anchoring
function AutoFarm:SetAnchorMobs(enabled)
    self.anchorMobs = enabled
end

function AutoFarm:GetAnchorMobs()
    if self.config then
        return self.config:Get("AutoFarm", "AnchorMobs")
    end
    return self.anchorMobs
end

-- Set bring mobs
function AutoFarm:SetBringMobs(enabled)
    self.bringMobs = enabled
end

function AutoFarm:GetBringMobs()
    if self.config then
        return self.config:Get("AutoFarm", "BringMobs")
    end
    return self.bringMobs
end

-- Check if player has an active quest
function AutoFarm:HasActiveQuest()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if playerGui then
        local main = playerGui:FindFirstChild("Main")
        if main then
            local quest = main:FindFirstChild("Quest")
            if quest and quest.Visible then
                return true
            end
        end
    end
    return false
end

-- Get current quest progress from UI
function AutoFarm:GetQuestProgress()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return nil end

    local main = playerGui:FindFirstChild("Main")
    if not main then return nil end

    local quest = main:FindFirstChild("Quest")
    if not quest or not quest.Visible then return nil end

    local container = quest:FindFirstChild("Container")
    if not container then return nil end

    local progressText = container:FindFirstChild("Progress")
    if progressText then
        local text = progressText.Text
        local current, total = text:match("(%d+)/(%d+)")
        if current and total then
            return tonumber(current), tonumber(total)
        end
    end

    return nil
end

-- Find best quest for player level
function AutoFarm:FindBestQuest()
    if not self.questData then
        warn("[AutoFarm] No quest data loaded")
        return nil
    end

    local playerLevel = GetPlayerLevel()
    local currentSea = GetCurrentSea()
    local seaKey = GetSeaKey(currentSea)

    local seaQuests = self.questData[seaKey]
    if not seaQuests then
        warn("[AutoFarm] No quests for", seaKey)
        return nil
    end

    local bestQuest = nil
    local bestQuestData = nil
    local bestLevel = 0

    for questName, questList in pairs(seaQuests) do
        for _, quest in ipairs(questList) do
            local levelReq = quest.LevelReq
            if levelReq <= playerLevel and levelReq > bestLevel then
                bestQuest = questName
                bestQuestData = quest
                bestLevel = levelReq
            end
        end
    end

    if bestQuest then
        return {
            QuestName = bestQuest,
            QuestData = bestQuestData,
            Sea = currentSea
        }
    end

    return nil
end

-- Find mob spawn location
function AutoFarm:GetMobSpawnLocation(mobName)
    -- Method 1: Search in Enemies folder for existing mobs
    local enemies = Workspace:FindFirstChild("Enemies")
    if enemies then
        for _, enemy in pairs(enemies:GetChildren()) do
            if enemy.Name == mobName then
                local humanoid = enemy:FindFirstChild("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    local rootPart = enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")
                    if rootPart then
                        return rootPart.CFrame
                    end
                end
            end
        end
    end

    -- Method 2: Check _WorldOrigin EnemySpawns
    local worldOrigin = Workspace:FindFirstChild("_WorldOrigin")
    if worldOrigin then
        local enemySpawns = worldOrigin:FindFirstChild("EnemySpawns")
        if enemySpawns then
            for _, spawn in pairs(enemySpawns:GetChildren()) do
                local spawnName = spawn.Name:gsub(" %[Lv%. %d+%]", "")
                if spawnName == mobName or spawn.Name == mobName or spawn.Name:find(mobName) then
                    return spawn:GetPivot()
                end
            end
        end
    end

    -- Method 3: Search Map for spawn points
    local map = Workspace:FindFirstChild("Map")
    if map then
        for _, island in pairs(map:GetChildren()) do
            for _, child in pairs(island:GetDescendants()) do
                if child.Name:find(mobName) or (child:IsA("BasePart") and child.Name == "SpawnPoint") then
                    return child.CFrame
                end
            end
        end
    end

    return nil
end

-- Accept quest from NPC
function AutoFarm:AcceptQuest(questName)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return false end

    local commF = remotes:FindFirstChild("CommF_")
    if not commF then return false end

    local currentSea = GetCurrentSea()
    local seaKey = GetSeaKey(currentSea)
    local seaQuests = self.questData[seaKey]

    if not seaQuests or not seaQuests[questName] then return false end

    local playerLevel = GetPlayerLevel()
    local questIndex = 1

    for i, quest in ipairs(seaQuests[questName]) do
        if quest.LevelReq <= playerLevel then
            questIndex = i
        end
    end

    local success = pcall(function()
        commF:InvokeServer("StartQuest", questName, questIndex)
    end)

    if success then
        task.wait(0.5)
        return self:HasActiveQuest()
    end

    return false
end

-- Find all enemies by name
function AutoFarm:FindAllEnemies(mobName)
    local found = {}
    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return found end

    for _, enemy in pairs(enemies:GetChildren()) do
        if enemy.Name == mobName then
            local humanoid = enemy:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then
                local rootPart = enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")
                if rootPart then
                    table.insert(found, {
                        Entity = enemy,
                        RootPart = rootPart,
                        Humanoid = humanoid
                    })
                end
            end
        end
    end

    return found
end

-- Find closest enemy
function AutoFarm:FindEnemy(mobName)
    local character, _, rootPart = GetCharacter()
    if not rootPart then return nil end

    local enemies = self:FindAllEnemies(mobName)
    local closest = nil
    local closestDistance = math.huge

    for _, data in ipairs(enemies) do
        local distance = (rootPart.Position - data.RootPart.Position).Magnitude
        if distance < closestDistance then
            closest = data.Entity
            closestDistance = distance
        end
    end

    return closest, closestDistance
end

-- Group all nearby mobs to a central position (PROVEN METHOD)
-- Based on working Blox Fruits scripts:
-- 1. Teleport mobs using CFrame
-- 2. Expand HumanoidRootPart Size for easier hits
-- 3. Anchor to prevent movement
-- 4. Zero velocity to stop momentum
function AutoFarm:GroupMobs(mobName, centerPosition)
    local shouldBring = self:GetBringMobs()
    local enemies = self:FindAllEnemies(mobName)
    local bringDistance = self:GetBringDistance()
    local shouldAnchor = self:GetAnchorMobs()
    local shouldExpandHitbox = self:GetExpandHitbox()
    local hitboxSize = self:GetHitboxSize()
    local groupedCount = 0

    -- Get player position for bringing mobs
    local character, _, rootPart = GetCharacter()
    if not rootPart then return 0 end

    -- Calculate bring position (in front of player, slightly below)
    local bringPosition = centerPosition

    for _, data in ipairs(enemies) do
        local distance = (data.RootPart.Position - rootPart.Position).Magnitude

        pcall(function()
            -- Try to claim network ownership (allows client-side manipulation)
            if sethiddenproperty then
                pcall(function()
                    sethiddenproperty(data.RootPart, "NetworkOwnership", 0)
                end)
            end

            -- HITBOX EXPANSION (always do this for easier hits)
            -- This is the key technique from working scripts
            if shouldExpandHitbox then
                -- Expand HumanoidRootPart to make it easier to hit
                data.RootPart.Size = Vector3.new(hitboxSize, hitboxSize, hitboxSize)
                data.RootPart.Transparency = 1 -- Hide the expanded hitbox
                data.RootPart.CanCollide = false

                -- Also expand Torso if exists (some mobs use Torso for hit detection)
                local torso = data.Entity:FindFirstChild("Torso")
                if torso then
                    torso.Size = Vector3.new(hitboxSize, hitboxSize, hitboxSize)
                    torso.Transparency = 1
                    torso.CanCollide = false
                end

                -- Expand Head too
                local head = data.Entity:FindFirstChild("Head")
                if head then
                    head.Size = Vector3.new(hitboxSize, hitboxSize, hitboxSize)
                    head.Transparency = 1
                    head.CanCollide = false
                end
            end

            -- BRING MOBS TO PLAYER (teleport using CFrame)
            -- This runs every frame so it keeps mobs in place
            if shouldBring and distance <= bringDistance then
                -- Teleport enemy to center with small random offset
                local offset = Vector3.new(
                    math.random(-MOB_GROUP_RADIUS, MOB_GROUP_RADIUS),
                    -2, -- Slightly below player
                    math.random(-MOB_GROUP_RADIUS, MOB_GROUP_RADIUS)
                )
                data.RootPart.CFrame = CFrame.new(bringPosition + offset)

                -- Zero velocity to stop movement (all methods)
                data.RootPart.Velocity = Vector3.new(0, 0, 0)
                pcall(function()
                    data.RootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                    data.RootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                end)

                groupedCount = groupedCount + 1
            end

            -- ANCHOR MOBS (stop them from moving) - Only if bringing is enabled
            if shouldAnchor and shouldBring then
                data.RootPart.Anchored = true
            end

            -- Disable collision on all parts to prevent physics issues
            for _, part in pairs(data.Entity:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end)
    end

    return groupedCount
end

-- Keep player flying above target position
function AutoFarm:FlyAbove(targetPosition)
    local character, humanoid, rootPart = GetCharacter()
    if not rootPart then return end

    local flyHeight = self:GetFlyHeight()
    local flyPos = targetPosition + Vector3.new(0, flyHeight, 0)

    pcall(function()
        rootPart.CFrame = CFrame.new(flyPos) * CFrame.Angles(math.rad(-90), 0, 0)
        rootPart.Velocity = Vector3.new(0, 0, 0)
    end)
end

-- Get farm position for current mob
function AutoFarm:GetMobFarmPosition(mobName)
    local enemy, _ = self:FindEnemy(mobName)
    if enemy then
        local rootPart = enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")
        if rootPart then
            return rootPart.Position
        end
    end

    local spawnCFrame = self:GetMobSpawnLocation(mobName)
    if spawnCFrame then
        return spawnCFrame.Position
    end

    return nil
end

-- Attack all nearby enemies using Combat module
function AutoFarm:AttackEnemies(mobName)
    -- Use the Combat module if available (primary method)
    if self.combat then
        -- Attack all enemies in range using proven methods
        self.combat:AttackAllInRange(100)
        self.combat:Attack()
        return
    end

    -- Fallback: Direct attack methods if Combat module not available
    local character = GetCharacter()
    if not character then return end

    local tool = character:FindFirstChildOfClass("Tool")
    if tool then
        -- Activate tool
        pcall(function()
            tool:Activate()
        end)

        -- Try firetouchinterest if available
        if firetouchinterest then
            local handle = tool:FindFirstChild("Handle")
            if handle then
                local enemies = self:FindAllEnemies(mobName)
                for _, data in ipairs(enemies) do
                    pcall(function()
                        firetouchinterest(handle, data.RootPart, 0)
                        task.wait()
                        firetouchinterest(handle, data.RootPart, 1)
                    end)
                end
            end
        end
    end
end

-- Enable haki using game remote
function AutoFarm:EnableHaki()
    local character = GetCharacter()
    if not character then return end
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

-- Use skills via game remotes
function AutoFarm:UseSkills()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end

    local commF = remotes:FindFirstChild("CommF_")
    if commF then
        for _, key in ipairs({"Z", "X", "C", "V"}) do
            pcall(function()
                commF:InvokeServer("Skill" .. key)
            end)
        end
    end
end

-- Main farm state handlers
function AutoFarm:HandleIdleState()
    local quest = self:FindBestQuest()
    if quest then
        self.currentQuest = quest.QuestName
        self.currentMobName = nil
        self.mobKillCount = 0

        if quest.QuestData and quest.QuestData.Task then
            for mobName, count in pairs(quest.QuestData.Task) do
                self.currentMobName = mobName
                self.requiredKills = count
                break
            end
        end

        self.stateManager:SetState(self.stateManager:GetStates().QUESTING, {
            quest = quest
        })
    end
end

function AutoFarm:HandleQuestingState()
    -- Check if we have an active quest in the UI
    if not self:HasActiveQuest() then
        -- No active quest - need to get one from quest giver
        print("[AutoFarm] No active quest, going to quest giver:", self.currentQuest)
        self.stateManager:SetState(self.stateManager:GetStates().NAVIGATING, {
            target = "questGiver",
            questName = self.currentQuest,
            turnIn = false  -- Not turning in, getting new quest
        })
        return
    end

    local current, total = self:GetQuestProgress()
    if current and total then
        self.mobKillCount = current
        self.requiredKills = total

        if current >= total then
            -- Quest complete! Go turn it in
            print("[AutoFarm] Quest complete! Going to turn in:", self.currentQuest)
            self.stateManager:SetState(self.stateManager:GetStates().NAVIGATING, {
                target = "questGiver",
                questName = self.currentQuest,
                turnIn = true
            })
            return
        end
    end

    -- Go to combat state to kill mobs
    self.stateManager:SetState(self.stateManager:GetStates().COMBAT, {
        mobName = self.currentMobName
    })
end

function AutoFarm:HandleNavigatingState()
    local data = self.stateManager:GetStateData()

    if data.target == "questGiver" then
        if self.npcsData and self.npcsData.QuestGivers then
            local npcData = self.npcsData.QuestGivers[data.questName]
            if npcData and npcData.Position then
                local pos = npcData.Position
                local targetCFrame = CFrame.new(pos[1], pos[2] + 3, pos[3])

                local character, _, rootPart = GetCharacter()
                if not rootPart then return end

                local distance = (rootPart.Position - targetCFrame.Position).Magnitude

                -- Use tweening for long distances (anti-cheat safe)
                if distance > 100 and self.teleport and not self.isTweeningToFarm then
                    self.isTweeningToFarm = true
                    print("[AutoFarm] Tweening to quest giver:", data.questName)

                    self.teleport:TweenTo(targetCFrame, function(success)
                        self.isTweeningToFarm = false
                        -- After arriving, handle quest logic
                        task.wait(0.5)
                        self:HandleQuestGiverArrival(data)
                    end, {speed = 200, bypassWalls = true})
                    return
                end

                -- Already close or tween complete - handle quest
                if distance <= 100 then
                    -- Move to exact position
                    rootPart.CFrame = targetCFrame
                    task.wait(0.3)
                    self:HandleQuestGiverArrival(data)
                end
            else
                -- No NPC data, try direct quest accept
                print("[AutoFarm] No NPC position data, trying direct quest accept")
                self:AcceptQuest(data.questName)
                self.stateManager:SetState(self.stateManager:GetStates().QUESTING)
            end
        else
            -- No NPC data at all, go back to idle
            print("[AutoFarm] No NPC data, returning to IDLE")
            self.stateManager:SetState(self.stateManager:GetStates().IDLE)
        end

    elseif data.target == "mobSpawn" then
        -- For mob spawn, we go to COMBAT and let it handle tweening
        self.hasReachedFarmSpot = false
        self.stateManager:SetState(self.stateManager:GetStates().COMBAT, {
            mobName = data.mobName
        })
    end
end

-- Helper function to handle quest giver interaction
function AutoFarm:HandleQuestGiverArrival(data)
    if data.turnIn then
        -- Turning in quest - wait then go back to IDLE to find next quest
        print("[AutoFarm] Turning in quest:", data.questName)
        task.wait(1)

        if self.callbacks.onQuestComplete then
            self.callbacks.onQuestComplete(data.questName)
        end

        -- IMPORTANT: Go back to IDLE to find the next best quest
        print("[AutoFarm] Quest turned in, finding next quest...")
        self.stateManager:SetState(self.stateManager:GetStates().IDLE)
    else
        -- Getting new quest
        print("[AutoFarm] Accepting new quest:", data.questName)
        local accepted = self:AcceptQuest(data.questName)

        if accepted then
            print("[AutoFarm] Quest accepted successfully!")
        else
            print("[AutoFarm] Quest accept may have failed, retrying...")
            task.wait(0.5)
            self:AcceptQuest(data.questName)
        end

        task.wait(0.5)
        self.stateManager:SetState(self.stateManager:GetStates().QUESTING)
    end
end

function AutoFarm:HandleCombatState()
    local data = self.stateManager:GetStateData()
    local mobName = data.mobName

    -- First check if quest is complete
    local current, total = self:GetQuestProgress()
    if current and total and current >= total then
        -- Quest done, reset farm spot flag and go to questing
        self.hasReachedFarmSpot = false
        self.stateManager:SetState(self.stateManager:GetStates().QUESTING)
        return
    end

    -- Get farm position
    local farmPosition = self:GetMobFarmPosition(mobName)
    if not farmPosition then
        local spawnCFrame = self:GetMobSpawnLocation(mobName)
        if spawnCFrame then
            self.hasReachedFarmSpot = false
            self.stateManager:SetState(self.stateManager:GetStates().NAVIGATING, {
                target = "mobSpawn",
                mobName = mobName
            })
        else
            task.wait(1)
        end
        return
    end

    -- Store farm position for consistency
    self.farmPosition = farmPosition

    local character, _, rootPart = GetCharacter()
    if not rootPart then return end

    local flyHeight = self:GetFlyHeight()
    local targetPos = farmPosition + Vector3.new(0, flyHeight, 0)
    local distanceToFarm = (rootPart.Position - targetPos).Magnitude

    -- TWEEN TO FARM SPOT FIRST (anti-cheat safe)
    -- Only tween if we haven't reached the spot yet
    if not self.hasReachedFarmSpot and distanceToFarm > 50 then
        if not self.isTweeningToFarm then
            self.isTweeningToFarm = true
            print("[AutoFarm] Tweening to farm spot for:", mobName)

            -- Use teleport module to tween (safer for anti-cheat)
            if self.teleport then
                self.teleport:TweenTo(CFrame.new(targetPos), function(success)
                    self.isTweeningToFarm = false
                    if success then
                        print("[AutoFarm] Reached farm spot, starting mob aura")
                        self.hasReachedFarmSpot = true
                    end
                end, {speed = 200, bypassWalls = true})
            else
                -- Fallback: direct teleport if no tween module
                rootPart.CFrame = CFrame.new(targetPos)
                self.isTweeningToFarm = false
                self.hasReachedFarmSpot = true
            end
        end
        return -- Wait for tween to complete
    end

    -- Mark as reached if close enough
    if distanceToFarm <= 50 then
        self.hasReachedFarmSpot = true
    end

    -- NOW WE'RE AT THE FARM SPOT - Do combat!

    -- Fly above the farm position (keep position stable)
    self:FlyAbove(farmPosition)

    -- Mob aura loop handles bringing mobs - just ensure it's running
    -- GroupMobs is now handled by the mob aura loop (RenderStepped)

    -- Enable haki
    self:EnableHaki()

    -- Equip weapon using Combat module
    if self.combat then
        self.combat:EquipSelectedWeapon()
    end

    -- Attack ALL enemies in range (not just nearest)
    self:AttackEnemies(mobName)

    -- Use skills
    if self.config and self.config:Get("Combat", "AutoSkills") then
        self:UseSkills()
    end
end

-- Start auto farming (continuous, no time limit)
function AutoFarm:Start()
    if self.enabled then return end
    self.enabled = true

    -- Reset state flags
    self.hasReachedFarmSpot = false
    self.isTweeningToFarm = false

    -- Start noclip
    self:StartNoclip()

    -- Start mob aura (runs on RenderStepped for smooth mob bringing)
    self:StartMobAura()

    -- Set weapon type in combat
    if self.combat then
        self.combat:SetWeaponType(self.selectedWeaponType)
    end

    -- Initialize state machine callbacks
    local states = self.stateManager:GetStates()

    self.stateManager:OnUpdate(states.IDLE, function()
        self:HandleIdleState()
    end)

    self.stateManager:OnUpdate(states.QUESTING, function()
        self:HandleQuestingState()
    end)

    self.stateManager:OnUpdate(states.NAVIGATING, function()
        self:HandleNavigatingState()
    end)

    self.stateManager:OnUpdate(states.COMBAT, function()
        self:HandleCombatState()
    end)

    -- Main loop - runs continuously
    self.mainLoop = RunService.Heartbeat:Connect(function()
        if not self.enabled then return end

        local character = GetCharacter()
        if not character then return end

        -- Update state machine
        self.stateManager:Update()
    end)

    -- Set initial state
    self.stateManager:SetState(states.IDLE)

    print("[AutoFarm] Started - Continuous farming with Mob Aura enabled")
end

-- Stop auto farming
function AutoFarm:Stop()
    self.enabled = false
    self.hasReachedFarmSpot = false
    self.isTweeningToFarm = false

    if self.mainLoop then
        self.mainLoop:Disconnect()
        self.mainLoop = nil
    end

    self:StopNoclip()
    self:StopMobAura()

    if self.combat then
        self.combat:Stop()
    end
    if self.teleport then
        self.teleport:Stop()
    end
    if self.stateManager then
        self.stateManager:Reset()
    end

    print("[AutoFarm] Stopped")
end

-- Check if farming is active
function AutoFarm:IsActive()
    return self.enabled
end

-- Get current farming status
function AutoFarm:GetStatus()
    return {
        enabled = self.enabled,
        state = self.stateManager and self.stateManager:GetCurrentState() or "Unknown",
        quest = self.currentQuest,
        mob = self.currentMobName,
        progress = self.mobKillCount .. "/" .. self.requiredKills,
        level = GetPlayerLevel(),
        weaponType = self.selectedWeaponType,
        flyHeight = self:GetFlyHeight(),
        hitboxEnabled = self:GetExpandHitbox(),
        hitboxSize = self:GetHitboxSize()
    }
end

-- Callbacks
function AutoFarm:OnQuestStart(callback)
    self.callbacks.onQuestStart = callback
end

function AutoFarm:OnQuestComplete(callback)
    self.callbacks.onQuestComplete = callback
end

function AutoFarm:OnMobKill(callback)
    self.callbacks.onMobKill = callback
end

function AutoFarm:OnLevelUp(callback)
    self.callbacks.onLevelUp = callback
end

function AutoFarm:OnError(callback)
    self.callbacks.onError = callback
end

-- Cleanup
function AutoFarm:Destroy()
    self:Stop()
    self.callbacks = {}
end

return {
    new = AutoFarm.new
}
