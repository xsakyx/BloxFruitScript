--[[
    Blox Fruits Auto Farm Script
    Main Entry Point - Executor Compatible Version

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

-- GitHub raw content base URL - UPDATE THIS TO YOUR REPO
local GITHUB_BASE = "https://raw.githubusercontent.com/xsakyx/BloxFruitScript/claude/blox-fruits-script-setup-qctSa/"

-- Module cache
local LoadedModules = {}

-- Print startup banner
local function PrintBanner()
    print("====================================")
    print(SCRIPT_CONFIG.Name)
    print("Version: " .. SCRIPT_CONFIG.Version)
    print("====================================")
    print("Loading modules...")
end

-- Load module from URL
local function LoadModule(modulePath)
    if LoadedModules[modulePath] then
        return LoadedModules[modulePath]
    end

    local url = GITHUB_BASE .. modulePath
    print("[BloxFruits] Loading:", modulePath)

    local success, result = pcall(function()
        local code = game:HttpGet(url)
        return loadstring(code)()
    end)

    if success then
        LoadedModules[modulePath] = result
        return result
    else
        warn("[BloxFruits] Failed to load module:", modulePath, result)
        return nil
    end
end

-- Load JSON data from URL
local function LoadJSONFromURL(jsonPath)
    local url = GITHUB_BASE .. jsonPath
    print("[BloxFruits] Loading data:", jsonPath)

    local success, result = pcall(function()
        local jsonString = game:HttpGet(url)
        return HttpService:JSONDecode(jsonString)
    end)

    if success then
        return result
    else
        warn("[BloxFruits] Failed to load JSON:", jsonPath, result)
        return nil
    end
end

-- Initialize all modules
local function InitializeModules()
    print("[BloxFruits] Initializing modules...")

    local Modules = {}

    -- Load Core modules
    Modules.StateManager = LoadModule("Core/StateManager.lua")
    Modules.ConfigManager = LoadModule("Core/ConfigManager.lua")

    -- Load Feature modules
    Modules.Teleport = LoadModule("Modules/Teleport.lua")
    Modules.Combat = LoadModule("Modules/Combat.lua")
    Modules.AutoFarm = LoadModule("Modules/AutoFarm.lua")
    Modules.FruitSniper = LoadModule("Modules/FruitSniper.lua")
    Modules.ESP = LoadModule("Modules/ESP.lua")
    Modules.Misc = LoadModule("Modules/Misc.lua")

    -- Note: UI will use the RenLib library directly instead of loading from file

    return Modules
end

-- Load game data (quests, islands, fruits, NPCs)
local function LoadGameData()
    print("[BloxFruits] Loading game data...")

    local questData = LoadJSONFromURL("Data/Quests.json")
    local islandsData = LoadJSONFromURL("Data/Islands.json")
    local fruitsData = LoadJSONFromURL("Data/Fruits.json")
    local npcsData = LoadJSONFromURL("Data/NPCs.json")

    return {
        Quests = questData or {},
        Islands = islandsData or {},
        Fruits = fruitsData or {},
        NPCs = npcsData or {}
    }
end

-- Create UI using RenLib
local function CreateUI(modules, instances)
    print("[BloxFruits] Creating UI...")

    -- Load RenLib
    local Library
    local success, err = pcall(function()
        Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/idk123456789012345678/ren/refs/heads/main/lib"))()
    end)

    if not success or not Library then
        warn("[BloxFruits] Failed to load UI library:", err)
        return nil
    end

    -- Create main window
    local Window = Library:CreateWindow({
        Name = "Blox Fruits Auto Farm"
    })

    -- Main Tab
    local MainTab = Window:CreateTab({
        Name = "Main",
        Emoji = "🏠"
    })

    local MainSection = MainTab:CreateSection({
        Name = "Auto Farm",
        Side = "Left"
    })

    -- Auto Farm Toggle
    MainSection:CreateToggle({
        Name = "Auto Farm Quests",
        Default = false,
        Callback = function(value)
            if instances.config then
                instances.config:Set("General", "AutoFarm", value)
            end
            if instances.autoFarm then
                if value then
                    instances.autoFarm:Start()
                else
                    instances.autoFarm:Stop()
                end
            end
        end
    })

    -- Fruit Sniper Toggle
    MainSection:CreateToggle({
        Name = "Fruit Sniper",
        Default = false,
        Callback = function(value)
            if instances.config then
                instances.config:Set("General", "FruitSniper", value)
            end
            if instances.fruitSniper then
                if value then
                    instances.fruitSniper:Start()
                else
                    instances.fruitSniper:Stop()
                end
            end
        end
    })

    -- ESP Toggle
    MainSection:CreateToggle({
        Name = "ESP",
        Default = false,
        Callback = function(value)
            if instances.config then
                instances.config:Set("ESP", "Enabled", value)
            end
            if instances.esp then
                if value then
                    instances.esp:Start()
                else
                    instances.esp:Stop()
                end
            end
        end
    })

    -- Farm Settings Section
    local FarmSection = MainTab:CreateSection({
        Name = "Farm Settings",
        Side = "Right"
    })

    FarmSection:CreateToggle({
        Name = "Bring Mobs",
        Default = true,
        Callback = function(value)
            if instances.config then
                instances.config:Set("General", "BringMobs", value)
            end
        end
    })

    FarmSection:CreateSlider({
        Name = "Bring Distance",
        Min = 20,
        Max = 200,
        Default = 80,
        Callback = function(value)
            if instances.config then
                instances.config:Set("General", "BringDistance", value)
            end
        end
    })

    FarmSection:CreateToggle({
        Name = "Skip Bosses",
        Default = false,
        Callback = function(value)
            if instances.config then
                instances.config:Set("Quest", "SkipBosses", value)
            end
        end
    })

    -- Combat Tab
    local CombatTab = Window:CreateTab({
        Name = "Combat",
        Emoji = "⚔️"
    })

    local CombatSection = CombatTab:CreateSection({
        Name = "Combat Settings",
        Side = "Left"
    })

    CombatSection:CreateToggle({
        Name = "Auto Attack",
        Default = true,
        Callback = function(value)
            if instances.config then
                instances.config:Set("Combat", "AutoAttack", value)
            end
        end
    })

    CombatSection:CreateToggle({
        Name = "Auto Skills",
        Default = true,
        Callback = function(value)
            if instances.config then
                instances.config:Set("Combat", "AutoSkills", value)
            end
        end
    })

    CombatSection:CreateToggle({
        Name = "Auto Haki",
        Default = true,
        Callback = function(value)
            if instances.config then
                instances.config:Set("Combat", "AutoHaki", value)
            end
        end
    })

    -- Skills Section
    local SkillsSection = CombatTab:CreateSection({
        Name = "Skills",
        Side = "Right"
    })

    for _, key in ipairs({"Z", "X", "C", "V", "F"}) do
        SkillsSection:CreateToggle({
            Name = "Use " .. key .. " Skill",
            Default = (key == "Z" or key == "X"),
            Callback = function(value)
                if instances.config then
                    local skills = instances.config:Get("Combat", "SkillsEnabled") or {}
                    skills[key] = value
                    instances.config:Set("Combat", "SkillsEnabled", skills)
                end
            end
        })
    end

    -- Teleport Tab
    local TeleportTab = Window:CreateTab({
        Name = "Teleport",
        Emoji = "🚀"
    })

    local TeleportSection = TeleportTab:CreateSection({
        Name = "Teleport Settings",
        Side = "Left"
    })

    TeleportSection:CreateSlider({
        Name = "Tween Speed",
        Min = 50,
        Max = 500,
        Default = 200,
        Callback = function(value)
            if instances.config then
                instances.config:Set("Teleport", "TweenSpeed", value)
            end
        end
    })

    TeleportSection:CreateToggle({
        Name = "Bypass Walls (NoClip)",
        Default = true,
        Callback = function(value)
            if instances.config then
                instances.config:Set("Teleport", "BypassWalls", value)
            end
        end
    })

    -- Sea Travel Section
    local SeaSection = TeleportTab:CreateSection({
        Name = "Sea Travel",
        Side = "Right"
    })

    SeaSection:CreateButton({
        Name = "Travel to Sea 1",
        Callback = function()
            if instances.misc then
                instances.misc:TravelToSea(1)
            end
        end
    })

    SeaSection:CreateButton({
        Name = "Travel to Sea 2",
        Callback = function()
            if instances.misc then
                instances.misc:TravelToSea(2)
            end
        end
    })

    SeaSection:CreateButton({
        Name = "Travel to Sea 3",
        Callback = function()
            if instances.misc then
                instances.misc:TravelToSea(3)
            end
        end
    })

    -- ESP Tab
    local ESPTab = Window:CreateTab({
        Name = "ESP",
        Emoji = "👁️"
    })

    local ESPSection = ESPTab:CreateSection({
        Name = "ESP Settings",
        Side = "Left"
    })

    ESPSection:CreateToggle({
        Name = "Fruit ESP",
        Default = true,
        Callback = function(value)
            if instances.config then
                instances.config:Set("ESP", "FruitESP", value)
            end
        end
    })

    ESPSection:CreateToggle({
        Name = "Boss ESP",
        Default = true,
        Callback = function(value)
            if instances.config then
                instances.config:Set("ESP", "BossESP", value)
            end
        end
    })

    ESPSection:CreateToggle({
        Name = "Player ESP",
        Default = false,
        Callback = function(value)
            if instances.config then
                instances.config:Set("ESP", "PlayerESP", value)
            end
        end
    })

    ESPSection:CreateToggle({
        Name = "Mob ESP",
        Default = false,
        Callback = function(value)
            if instances.config then
                instances.config:Set("ESP", "MobESP", value)
            end
        end
    })

    ESPSection:CreateToggle({
        Name = "Chest ESP",
        Default = false,
        Callback = function(value)
            if instances.config then
                instances.config:Set("ESP", "ChestESP", value)
            end
        end
    })

    -- Misc Tab
    local MiscTab = Window:CreateTab({
        Name = "Misc",
        Emoji = "⚙️"
    })

    local MiscSection = MiscTab:CreateSection({
        Name = "Utilities",
        Side = "Left"
    })

    MiscSection:CreateToggle({
        Name = "Anti-AFK",
        Default = true,
        Callback = function(value)
            if instances.config then
                instances.config:Set("Misc", "AntiAFK", value)
            end
            if instances.misc then
                if value then
                    instances.misc:StartAntiAFK()
                else
                    instances.misc:StopAntiAFK()
                end
            end
        end
    })

    MiscSection:CreateToggle({
        Name = "Auto Rejoin",
        Default = true,
        Callback = function(value)
            if instances.config then
                instances.config:Set("Misc", "AutoRejoin", value)
            end
            if instances.misc then
                if value then
                    instances.misc:StartAutoRejoin()
                else
                    instances.misc:StopAutoRejoin()
                end
            end
        end
    })

    MiscSection:CreateToggle({
        Name = "No Clip",
        Default = false,
        Callback = function(value)
            if instances.config then
                instances.config:Set("Misc", "NoClip", value)
            end
            if instances.misc then
                if value then
                    instances.misc:StartNoClip()
                else
                    instances.misc:StopNoClip()
                end
            end
        end
    })

    -- Actions Section
    local ActionsSection = MiscTab:CreateSection({
        Name = "Actions",
        Side = "Right"
    })

    ActionsSection:CreateButton({
        Name = "Server Hop",
        Callback = function()
            if instances.misc then
                instances.misc:ServerHop()
            end
        end
    })

    ActionsSection:CreateButton({
        Name = "Rejoin Server",
        Callback = function()
            if instances.misc then
                instances.misc:Rejoin()
            end
        end
    })

    ActionsSection:CreateButton({
        Name = "Reset Character",
        Callback = function()
            if instances.misc then
                instances.misc:ResetCharacter()
            end
        end
    })

    ActionsSection:CreateButton({
        Name = "Save Config",
        Callback = function()
            if instances.config then
                local success = instances.config:Save()
                Library:Notify({
                    Title = "Config",
                    Content = success and "Config saved!" or "Failed to save config",
                    Duration = 3
                })
            end
        end
    })

    return {
        Window = Window,
        Library = Library
    }
end

-- Main initialization
local function Initialize()
    PrintBanner()

    -- Initialize modules
    local modules = InitializeModules()

    -- Check if core modules loaded
    if not modules.ConfigManager or not modules.StateManager then
        warn("[BloxFruits] Failed to load core modules!")
        return
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

    local instances = {
        config = config,
        stateManager = stateManager,
        teleport = teleport,
        combat = combat,
        autoFarm = autoFarm,
        fruitSniper = fruitSniper,
        esp = esp,
        misc = misc
    }

    -- Load saved config
    if config then
        config:Load()
    end

    -- Load game data and inject into modules
    local gameData = LoadGameData()
    if autoFarm and gameData then
        autoFarm:LoadData(gameData.Quests, gameData.NPCs, gameData.Islands)
    end

    -- Create UI
    local ui = CreateUI(modules, instances)
    instances.ui = ui

    -- Start misc features (Anti-AFK, etc.)
    if misc then
        misc:Start()
    end

    -- Setup callbacks
    if autoFarm then
        autoFarm:OnQuestComplete(function(questName)
            if ui and ui.Library then
                ui.Library:Notify({
                    Title = "Quest Complete",
                    Content = questName,
                    Duration = 3
                })
            end
        end)

        autoFarm:OnLevelUp(function(newLevel)
            if ui and ui.Library then
                ui.Library:Notify({
                    Title = "Level Up!",
                    Content = "Level " .. tostring(newLevel),
                    Duration = 3
                })
            end
        end)
    end

    if fruitSniper then
        fruitSniper:OnFruitFound(function(fruitName, tier, distance)
            if ui and ui.Library then
                ui.Library:Notify({
                    Title = "Fruit Found!",
                    Content = fruitName .. " (" .. tier .. ") - " .. math.floor(distance) .. "m",
                    Duration = 5
                })
            end
        end)

        fruitSniper:OnFruitCollected(function(fruitName, tier)
            if ui and ui.Library then
                ui.Library:Notify({
                    Title = "Fruit Collected!",
                    Content = fruitName .. " (" .. tier .. ")",
                    Duration = 5
                })
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
                if ui and ui.Window then ui.Window:Toggle() end
            end,
            ServerHop = function()
                if misc then misc:ServerHop() end
            end,
            TravelToSea = function(sea)
                if misc then misc:TravelToSea(sea) end
            end
        }
    end

    print("[BloxFruits] Script loaded successfully!")
    print("[BloxFruits] Press K to toggle UI")

    if ui and ui.Library then
        ui.Library:Notify({
            Title = SCRIPT_CONFIG.Name,
            Content = "Script loaded! Press K to toggle UI",
            Duration = 5
        })
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

return SCRIPT_CONFIG
