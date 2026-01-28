--[[
    AutoFarm.lua
    Main farming logic - Quest selection, navigation, combat, turn-in
    Implements the core auto-farm loop
]]

local AutoFarm = {}
AutoFarm.__index = AutoFarm

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- Module dependencies (will be injected)
local Teleport
local Combat
local StateManager
local Config

-- Constants
local QUEST_TURN_IN_DISTANCE = 15
local MOB_BRING_DISTANCE = 100
local MOB_SEARCH_RADIUS = 500
local QUEST_CHECK_INTERVAL = 1
local FLY_HEIGHT = 15 -- Height above mobs when attacking
local ATTACK_RANGE = 50

function AutoFarm.new(config, teleport, combat, stateManager)
    local self = setmetatable({}, AutoFarm)

    -- Store dependencies
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

    self.mainLoop = nil
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
        -- Parse "X/Y" format
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

    -- Find highest level quest that player can do
    for questName, questList in pairs(seaQuests) do
        for _, quest in ipairs(questList) do
            local levelReq = quest.LevelReq
            if levelReq <= playerLevel and levelReq > bestLevel then
                -- Skip bosses if configured
                local isBoss = quest.Task and next(quest.Task) and
                              (select(2, next(quest.Task)) == 1)

                if not isBoss or not (self.config and self.config:Get("Quest", "SkipBosses")) then
                    bestQuest = questName
                    bestQuestData = quest
                    bestLevel = levelReq
                end
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

-- Get mob spawn location for quest
function AutoFarm:GetMobSpawnLocation(mobName)
    local worldOrigin = Workspace:FindFirstChild("_WorldOrigin")
    if not worldOrigin then return nil end

    local enemySpawns = worldOrigin:FindFirstChild("EnemySpawns")
    if not enemySpawns then return nil end

    for _, spawn in pairs(enemySpawns:GetChildren()) do
        -- Remove level requirement from spawn name for matching
        local spawnName = spawn.Name:gsub(" %[Lv%. %d+%]", "")
        if spawnName == mobName or spawn.Name == mobName then
            return spawn:GetPivot()
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

    -- Get quest index
    local currentSea = GetCurrentSea()
    local seaKey = GetSeaKey(currentSea)
    local seaQuests = self.questData[seaKey]

    if not seaQuests or not seaQuests[questName] then return false end

    local playerLevel = GetPlayerLevel()
    local questIndex = 1

    -- Find the correct quest index based on level
    for i, quest in ipairs(seaQuests[questName]) do
        if quest.LevelReq <= playerLevel then
            questIndex = i
        end
    end

    local success, result = pcall(function()
        return commF:InvokeServer("StartQuest", questName, questIndex)
    end)

    if success then
        task.wait(0.5)
        return self:HasActiveQuest()
    end

    return false
end

-- Find enemy instances in workspace
function AutoFarm:FindEnemy(mobName)
    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return nil end

    local character, _, rootPart = GetCharacter()
    if not rootPart then return nil end

    local closest = nil
    local closestDistance = math.huge

    for _, enemy in pairs(enemies:GetChildren()) do
        if enemy.Name == mobName then
            local humanoid = enemy:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then
                local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
                if enemyRoot then
                    local distance = (rootPart.Position - enemyRoot.Position).Magnitude
                    if distance < closestDistance then
                        closest = enemy
                        closestDistance = distance
                    end
                end
            end
        end
    end

    return closest, closestDistance
end

-- Bring mobs towards player (continuous)
function AutoFarm:BringMobs(mobName, targetPosition)
    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return 0 end

    local bringDistance = self.config and self.config:Get("General", "BringDistance") or MOB_BRING_DISTANCE
    local broughtCount = 0

    for _, enemy in pairs(enemies:GetChildren()) do
        if enemy.Name == mobName then
            local humanoid = enemy:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then
                local enemyRoot = enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")
                if enemyRoot then
                    -- Check if within bring distance from spawn
                    local distance = targetPosition and (enemyRoot.Position - targetPosition).Magnitude or math.huge
                    if distance <= bringDistance then
                        -- Move enemy below player (player is above)
                        pcall(function()
                            enemyRoot.CFrame = CFrame.new(targetPosition) * CFrame.new(math.random(-3, 3), 0, math.random(-3, 3))
                            enemyRoot.Velocity = Vector3.new(0, 0, 0)
                            enemyRoot.Anchored = false
                        end)
                        broughtCount = broughtCount + 1
                    end
                end
            end
        end
    end

    return broughtCount
end

-- Keep player flying above target position
function AutoFarm:FlyAbove(targetPosition)
    local character, humanoid, rootPart = GetCharacter()
    if not rootPart then return end

    local flyPos = targetPosition + Vector3.new(0, FLY_HEIGHT, 0)

    -- Use BodyPosition or CFrame to stay above
    pcall(function()
        rootPart.CFrame = CFrame.new(flyPos) * CFrame.Angles(math.rad(-90), 0, 0)
        rootPart.Velocity = Vector3.new(0, 0, 0)
    end)
end

-- Get spawn position for current quest mob
function AutoFarm:GetMobFarmPosition(mobName)
    -- First try to find an alive mob
    local enemy = self:FindEnemy(mobName)
    if enemy then
        local enemyRoot = enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")
        if enemyRoot then
            return enemyRoot.Position
        end
    end

    -- Otherwise use spawn location
    local spawnCFrame = self:GetMobSpawnLocation(mobName)
    if spawnCFrame then
        return spawnCFrame.Position
    end

    return nil
end

-- Main farm state handlers
function AutoFarm:HandleIdleState()
    -- Find best quest
    local quest = self:FindBestQuest()
    if quest then
        self.currentQuest = quest.QuestName
        self.currentMobName = nil
        self.mobKillCount = 0

        -- Get mob name and required kills from quest data
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
    -- Check if we have an active quest
    if not self:HasActiveQuest() then
        -- Navigate to quest giver
        self.stateManager:SetState(self.stateManager:GetStates().NAVIGATING, {
            target = "questGiver",
            questName = self.currentQuest
        })
        return
    end

    -- Check quest progress
    local current, total = self:GetQuestProgress()
    if current and total then
        self.mobKillCount = current
        self.requiredKills = total

        if current >= total then
            -- Quest complete, turn in
            self.stateManager:SetState(self.stateManager:GetStates().NAVIGATING, {
                target = "questGiver",
                questName = self.currentQuest,
                turnIn = true
            })
            return
        end
    end

    -- Find and fight mobs - go directly to combat state
    local enemy, distance = self:FindEnemy(self.currentMobName)
    if enemy then
        -- Go directly to combat (we fly to them)
        self.stateManager:SetState(self.stateManager:GetStates().COMBAT, {
            target = enemy,
            mobName = self.currentMobName
        })
    else
        -- No enemies found, navigate to spawn location first
        local spawnCFrame = self:GetMobSpawnLocation(self.currentMobName)
        if spawnCFrame then
            -- Tween to spawn location then combat
            local character, _, rootPart = GetCharacter()
            if rootPart then
                local dist = (rootPart.Position - spawnCFrame.Position).Magnitude
                if dist > 100 then
                    -- Far away, need to tween
                    self.stateManager:SetState(self.stateManager:GetStates().NAVIGATING, {
                        target = "mobSpawn",
                        mobName = self.currentMobName
                    })
                else
                    -- Close enough, wait for respawn or go to combat
                    self.stateManager:SetState(self.stateManager:GetStates().COMBAT, {
                        mobName = self.currentMobName
                    })
                end
            end
        else
            warn("[AutoFarm] Could not find spawn for:", self.currentMobName)
        end
    end
end

function AutoFarm:HandleNavigatingState()
    local data = self.stateManager:GetStateData()

    if data.target == "questGiver" then
        -- Navigate to quest giver NPC
        if self.npcsData and self.npcsData.QuestGivers then
            local npcData = self.npcsData.QuestGivers[data.questName]
            if npcData and npcData.Position then
                local pos = npcData.Position
                local targetCFrame = CFrame.new(pos[1], pos[2] + 3, pos[3])

                self.teleport:TweenTo(targetCFrame, function(success)
                    if success then
                        task.wait(0.5)

                        if data.turnIn then
                            -- Wait for quest to complete
                            task.wait(1)
                            if self.callbacks.onQuestComplete then
                                self.callbacks.onQuestComplete(data.questName)
                            end
                        else
                            -- Accept new quest
                            self:AcceptQuest(data.questName)
                        end

                        self.stateManager:SetState(self.stateManager:GetStates().QUESTING)
                    else
                        self.stateManager:SetState(self.stateManager:GetStates().ERROR, {
                            reason = "Navigation failed"
                        })
                    end
                end)
            end
        end

    elseif data.target == "mob" then
        -- Navigate to specific mob
        local enemy = self:FindEnemy(data.mobName)
        if enemy then
            local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
            if enemyRoot then
                self.teleport:TweenTo(enemyRoot.CFrame, function(success)
                    if success then
                        self.stateManager:SetState(self.stateManager:GetStates().COMBAT, {
                            target = enemy,
                            mobName = data.mobName
                        })
                    end
                end)
            end
        else
            -- Go to spawn location instead
            self.stateManager:SetStateData("target", "mobSpawn")
        end

    elseif data.target == "mobSpawn" then
        -- Navigate to mob spawn location
        local spawnCFrame = self:GetMobSpawnLocation(data.mobName)
        if spawnCFrame then
            self.teleport:TweenTo(spawnCFrame, function(success)
                if success then
                    self.stateManager:SetState(self.stateManager:GetStates().QUESTING)
                end
            end)
        else
            warn("[AutoFarm] Could not find spawn for:", data.mobName)
            self.stateManager:SetState(self.stateManager:GetStates().QUESTING)
        end
    end
end

function AutoFarm:HandleCombatState()
    local data = self.stateManager:GetStateData()
    local mobName = data.mobName

    -- Get farm position (where mobs spawn or where the closest mob is)
    local farmPosition = self:GetMobFarmPosition(mobName)
    if not farmPosition then
        -- No mobs found, go back to questing
        self.stateManager:SetState(self.stateManager:GetStates().QUESTING)
        return
    end

    -- Fly above the farm position
    self:FlyAbove(farmPosition)

    -- Bring all nearby mobs to center (below player)
    local bringEnabled = not self.config or self.config:Get("General", "BringMobs") ~= false
    if bringEnabled then
        self:BringMobs(mobName, farmPosition)
    end

    -- Expand hitboxes of nearby enemies
    local enemies = Workspace:FindFirstChild("Enemies")
    if enemies then
        for _, enemy in pairs(enemies:GetChildren()) do
            if enemy.Name == mobName then
                local humanoid = enemy:FindFirstChild("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    -- Expand hitbox using Combat module
                    self.combat:ExpandHitbox(enemy)
                    -- Set as target for combat
                    self.combat:SetTarget(enemy)
                end
            end
        end
    end

    -- Enable Haki if configured
    if self.config and self.config:Get("Combat", "AutoHaki") then
        self.combat:EnableHaki()
    end

    -- Perform M1 attack
    if self.config and self.config:Get("Combat", "AutoAttack") ~= false then
        self.combat:Attack()
    end

    -- Use skills if configured
    if self.config and self.config:Get("Combat", "AutoSkills") then
        self.combat:UseAllSkills()
    end

    -- Check if any enemies are still alive
    local anyAlive = false
    if enemies then
        for _, enemy in pairs(enemies:GetChildren()) do
            if enemy.Name == mobName then
                local humanoid = enemy:FindFirstChild("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    anyAlive = true
                    break
                end
            end
        end
    end

    -- If no enemies alive, check quest progress
    if not anyAlive then
        -- Restore hitboxes
        for _, enemy in pairs(enemies:GetChildren()) do
            self.combat:RestoreHitbox(enemy)
        end

        if self.callbacks.onMobKill then
            self.callbacks.onMobKill(mobName)
        end

        -- Small delay before checking quest
        task.wait(0.3)
        self.stateManager:SetState(self.stateManager:GetStates().QUESTING)
    end
end

-- Start auto farming
function AutoFarm:Start()
    if self.enabled then return end
    self.enabled = true

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

    -- Main loop
    self.mainLoop = RunService.Heartbeat:Connect(function()
        if not self.enabled then return end

        local character = GetCharacter()
        if not character then return end

        -- Update state machine
        self.stateManager:Update()
    end)

    -- Set initial state
    self.stateManager:SetState(states.IDLE)
end

-- Stop auto farming
function AutoFarm:Stop()
    self.enabled = false

    if self.mainLoop then
        self.mainLoop:Disconnect()
        self.mainLoop = nil
    end

    self.combat:Stop()
    self.teleport:Stop()
    self.stateManager:Reset()
end

-- Check if farming is active
function AutoFarm:IsActive()
    return self.enabled
end

-- Get current farming status
function AutoFarm:GetStatus()
    return {
        enabled = self.enabled,
        state = self.stateManager:GetCurrentState(),
        quest = self.currentQuest,
        mob = self.currentMobName,
        progress = self.mobKillCount .. "/" .. self.requiredKills,
        level = GetPlayerLevel()
    }
end

-- Set callbacks
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
