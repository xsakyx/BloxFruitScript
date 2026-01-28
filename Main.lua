--[[
    Blox Fruits Auto Farm Script
    Main Entry Point

    Features:
    - Auto Quest Farm (auto-select best quest, kill mobs, turn in)
    - Fruit Sniper (detect and collect fruits, server hop)
    - Boss Farm (detect boss spawns, kill, collect drops)
    - Mastery Farm (grind weapon/fruit mastery)
    - ESP (fruits, bosses, players, mobs)
    - Anti-AFK, Auto-Rejoin, Server Hop

    Uses tween-based teleportation (no direct TP)
]]

-- Prevent multiple instances
if getgenv and getgenv().BloxFruitScriptLoaded then
    warn("[BloxFruits] Script already loaded!")
    return
end
if getgenv then
    getgenv().BloxFruitScriptLoaded = true
end

-- Services
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Game ID verification
local BLOX_FRUIT_GAME_ID = 994732206
local VALID_PLACE_IDS = {
    2753915549, -- Sea 1
    4442272183, -- Sea 2
    7449423635  -- Sea 3
}

-- Check if in Blox Fruits
local function IsBloxFruits()
    if game.GameId == BLOX_FRUIT_GAME_ID then
        return true
    end
    for _, placeId in ipairs(VALID_PLACE_IDS) do
        if game.PlaceId == placeId then
            return true
        end
    end
    return false
end

if not IsBloxFruits() then
    warn("[BloxFruits] This script only works in Blox Fruits!")
    return
end

-- Script configuration
local SCRIPT_CONFIG = {
    Name = "Blox Fruits Auto Farm",
    Version = "1.0.0",
    Author = "BloxFruit Script Team",
    DataFolder = "BloxFruitScript"
}

-- GitHub raw content base URL (for loading modules remotely if needed)
local GITHUB_BASE = "https://raw.githubusercontent.com/your-repo/BloxFruitScript/main/"

-- Module cache
local Modules = {}

-- Load module from string (for executor environment)
local function LoadModuleFromString(moduleCode, moduleName)
    local success, result = pcall(function()
        return loadstring(moduleCode)()
    end)

    if success then
        return result
    else
        warn("[BloxFruits] Failed to load module:", moduleName, result)
        return nil
    end
end

-- Load JSON data
local function LoadJSONData(jsonString)
    local success, result = pcall(function()
        return HttpService:JSONDecode(jsonString)
    end)

    if success then
        return result
    else
        warn("[BloxFruits] Failed to parse JSON:", result)
        return nil
    end
end

-- Print startup banner
local function PrintBanner()
    print("====================================")
    print(SCRIPT_CONFIG.Name)
    print("Version: " .. SCRIPT_CONFIG.Version)
    print("====================================")
    print("Loading modules...")
end

--[[
    INLINE MODULE LOADING
    In a real executor environment, you would either:
    1. Load modules from URLs using game:HttpGet()
    2. Have modules as separate files loaded by the executor
    3. Use a loadstring approach

    For this structure, we'll define how modules should be loaded
]]

-- Module loader (simulated - replace with actual loading in executor)
local function RequireModule(modulePath)
    -- In executor environment, this would be:
    -- return loadstring(game:HttpGet(GITHUB_BASE .. modulePath))()

    -- For local development/testing, return placeholder
    print("[BloxFruits] Loading:", modulePath)
    return nil -- Replace with actual module loading
end

-- Initialize all modules
local function InitializeModules()
    print("[BloxFruits] Initializing modules...")

    -- Load Core modules
    local StateManagerModule = require and require(script.Parent.Core.StateManager) or RequireModule("Core/StateManager.lua")
    local ConfigManagerModule = require and require(script.Parent.Core.ConfigManager) or RequireModule("Core/ConfigManager.lua")

    -- Load Feature modules
    local TeleportModule = require and require(script.Parent.Modules.Teleport) or RequireModule("Modules/Teleport.lua")
    local CombatModule = require and require(script.Parent.Modules.Combat) or RequireModule("Modules/Combat.lua")
    local AutoFarmModule = require and require(script.Parent.Modules.AutoFarm) or RequireModule("Modules/AutoFarm.lua")
    local FruitSniperModule = require and require(script.Parent.Modules.FruitSniper) or RequireModule("Modules/FruitSniper.lua")
    local ESPModule = require and require(script.Parent.Modules.ESP) or RequireModule("Modules/ESP.lua")
    local MiscModule = require and require(script.Parent.Modules.Misc) or RequireModule("Modules/Misc.lua")

    -- Load UI module
    local MainUIModule = require and require(script.Parent.UI.MainUI) or RequireModule("UI/MainUI.lua")

    -- Store modules
    Modules = {
        StateManager = StateManagerModule,
        ConfigManager = ConfigManagerModule,
        Teleport = TeleportModule,
        Combat = CombatModule,
        AutoFarm = AutoFarmModule,
        FruitSniper = FruitSniperModule,
        ESP = ESPModule,
        Misc = MiscModule,
        MainUI = MainUIModule
    }

    return Modules
end

-- Load game data (quests, islands, fruits, NPCs)
local function LoadGameData()
    print("[BloxFruits] Loading game data...")

    local questData, islandsData, fruitsData, npcsData

    -- In executor environment, load from JSON files or URLs
    -- For now, return empty tables (data is defined in Data/*.json)

    return {
        Quests = questData or {},
        Islands = islandsData or {},
        Fruits = fruitsData or {},
        NPCs = npcsData or {}
    }
end

-- Main initialization
local function Initialize()
    PrintBanner()

    -- Initialize modules
    local modules = InitializeModules()

    -- Check if modules loaded
    local hasModules = false
    for name, mod in pairs(modules) do
        if mod then
            hasModules = true
            break
        end
    end

    if not hasModules then
        warn("[BloxFruits] No modules loaded. Using inline fallback...")
    end

    -- Create instances
    local config = modules.ConfigManager and modules.ConfigManager.new() or nil
    local stateManager = modules.StateManager and modules.StateManager.new() or nil
    local teleport = modules.Teleport and modules.Teleport.new(config) or nil
    local combat = modules.Combat and modules.Combat.new(config) or nil
    local autoFarm = modules.AutoFarm and modules.AutoFarm.new(config, teleport, combat, stateManager) or nil
    local fruitSniper = modules.FruitSniper and modules.FruitSniper.new(config, teleport) or nil
    local esp = modules.ESP and modules.ESP.new(config) or nil
    local misc = modules.Misc and modules.Misc.new(config) or nil
    local ui = modules.MainUI and modules.MainUI.new() or nil

    -- Load saved config
    if config then
        config:Load()
    end

    -- Load game data and inject into modules
    local gameData = LoadGameData()
    if autoFarm then
        autoFarm:LoadData(gameData.Quests, gameData.NPCs, gameData.Islands)
    end

    -- Initialize UI
    if ui then
        ui:SetModules({
            config = config,
            autoFarm = autoFarm,
            fruitSniper = fruitSniper,
            combat = combat,
            esp = esp,
            misc = misc,
            teleport = teleport
        })
        ui:Init()
    end

    -- Start misc features (Anti-AFK, etc.)
    if misc then
        misc:Start()
    end

    -- Setup callbacks
    if autoFarm then
        autoFarm:OnQuestComplete(function(questName)
            if misc then
                misc:Notify("Quest Complete", questName)
            end
        end)

        autoFarm:OnLevelUp(function(newLevel)
            if misc then
                misc:Notify("Level Up!", "Level " .. tostring(newLevel))
            end
        end)
    end

    if fruitSniper then
        fruitSniper:OnFruitFound(function(fruitName, tier, distance)
            if misc then
                misc:Notify("Fruit Found!", fruitName .. " (" .. tier .. ") - " .. math.floor(distance) .. "m")
            end
        end)

        fruitSniper:OnFruitCollected(function(fruitName, tier)
            if misc then
                misc:Notify("Fruit Collected!", fruitName .. " (" .. tier .. ")")
            end
        end)
    end

    -- Store global references
    if getgenv then
        getgenv().BloxFruits = {
            Config = config,
            StateManager = stateManager,
            Teleport = teleport,
            Combat = combat,
            AutoFarm = autoFarm,
            FruitSniper = fruitSniper,
            ESP = esp,
            Misc = misc,
            UI = ui,

            -- Quick access functions
            Start = function()
                if autoFarm then autoFarm:Start() end
            end,
            Stop = function()
                if autoFarm then autoFarm:Stop() end
                if fruitSniper then fruitSniper:Stop() end
                if esp then esp:Stop() end
            end,
            ToggleUI = function()
                if ui then ui:Toggle() end
            end,
            ServerHop = function()
                if misc then misc:ServerHop() end
            end,
            TravelToSea = function(sea)
                if misc then misc:TravelToSea(sea) end
            end
        }
    end

    -- Stats update loop
    task.spawn(function()
        while true do
            task.wait(1)

            if misc and ui then
                local stats = misc:GetPlayerData()
                ui:UpdateStats(stats)
            end
        end
    end)

    print("[BloxFruits] Script loaded successfully!")
    print("[BloxFruits] Press RightControl to toggle UI")

    if misc then
        misc:Notify(SCRIPT_CONFIG.Name, "Script loaded! Press RightControl to toggle UI")
    end
end

-- Wait for game to load
local function WaitForGame()
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end

    -- Wait for character
    if not LocalPlayer.Character then
        LocalPlayer.CharacterAdded:Wait()
    end

    -- Wait for essential game elements
    local maxWait = 30
    local waited = 0

    while waited < maxWait do
        local enemies = workspace:FindFirstChild("Enemies")
        local worldOrigin = workspace:FindFirstChild("_WorldOrigin")
        local data = LocalPlayer:FindFirstChild("Data")

        if enemies and worldOrigin and data then
            break
        end

        task.wait(1)
        waited = waited + 1
    end

    if waited >= maxWait then
        warn("[BloxFruits] Game took too long to load essential elements")
    end
end

-- Main entry point
task.spawn(function()
    local success, err = pcall(function()
        WaitForGame()
        Initialize()
    end)

    if not success then
        warn("[BloxFruits] Failed to initialize:", err)
    end
end)

--[[
    EXECUTOR LOADING EXAMPLE
    To use this script in an executor, you would typically:

    1. Single file approach (concatenate all modules):
       loadstring(game:HttpGet("your-url/BloxFruitScript.lua"))()

    2. Multi-file approach (load modules separately):
       local baseUrl = "your-url/BloxFruitScript/"
       local modules = {"Core/StateManager", "Core/ConfigManager", ...}
       for _, mod in ipairs(modules) do
           loadstring(game:HttpGet(baseUrl .. mod .. ".lua"))()
       end
       loadstring(game:HttpGet(baseUrl .. "Main.lua"))()

    3. GitHub raw content:
       loadstring(game:HttpGet("https://raw.githubusercontent.com/user/repo/main/Main.lua"))()
]]

return SCRIPT_CONFIG
