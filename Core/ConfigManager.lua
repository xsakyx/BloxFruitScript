--[[
    ConfigManager.lua
    Handles saving/loading configuration settings
    Uses executor file system for persistence
]]

local ConfigManager = {}
ConfigManager.__index = ConfigManager

-- Services
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

-- Default configuration
local DefaultConfig = {
    -- General Settings
    General = {
        AutoFarm = false,
        FruitSniper = false,
        BossFarm = false,
        MasteryFarm = false,
        BringMobs = true,
        BringDistance = 80,
        SmoothMode = false,
        SafeMode = true
    },

    -- Combat Settings
    Combat = {
        AutoAttack = true,
        AutoSkills = true,
        SkillsEnabled = {Z = true, X = true, C = false, V = false, F = false},
        AttackSpeed = 1,
        SkillCooldown = 0.5,
        AutoHaki = true
    },

    -- Teleport Settings
    Teleport = {
        TweenSpeed = 200,
        UseTween = true,
        BypassWalls = true,
        SafeHeight = 50
    },

    -- Quest Settings
    Quest = {
        SelectedQuest = nil,
        AutoSelectQuest = true,
        FarmBosses = false,
        SkipBosses = false
    },

    -- Fruit Sniper Settings
    FruitSniper = {
        Enabled = false,
        ServerHop = true,
        ServerHopDelay = 5,
        OnlyMythical = false,
        OnlyLegendary = false,
        BlacklistedFruits = {},
        WhitelistedFruits = {},
        UseWhitelist = false,
        NotifyOnFind = true,
        AutoCollect = true
    },

    -- Boss Farm Settings
    BossFarm = {
        SelectedBoss = nil,
        AutoSelectBoss = true,
        WaitForRespawn = true,
        CollectDrops = true
    },

    -- Mastery Settings
    Mastery = {
        SelectedWeapon = nil,
        TargetMastery = 600,
        MobName = nil,
        AutoSelectMob = true
    },

    -- ESP Settings
    ESP = {
        Enabled = false,
        FruitESP = true,
        PlayerESP = false,
        MobESP = false,
        BossESP = true,
        ChestESP = false,
        NPCDistance = 500,
        FruitDistance = 10000,
        ShowDistance = true,
        ShowHealth = true,
        TeamCheck = true
    },

    -- Misc Settings
    Misc = {
        AntiAFK = true,
        AutoRejoin = true,
        RejoinDelay = 5,
        Notifications = true,
        AutoSea = true,
        InfiniteEnergy = false,
        NoClip = false
    },

    -- UI Settings
    UI = {
        Theme = "Default",
        Keybind = "RightControl",
        MinimizeOnStart = false
    }
}

function ConfigManager.new()
    local self = setmetatable({}, ConfigManager)

    self.config = {}
    self.configPath = "BloxFruitScript"
    self.configFile = "config.json"
    self.callbacks = {}
    self.loaded = false

    -- Deep copy default config
    self:ResetToDefault()

    return self
end

-- Deep copy a table
local function DeepCopy(original)
    local copy = {}
    for key, value in pairs(original) do
        if type(value) == "table" then
            copy[key] = DeepCopy(value)
        else
            copy[key] = value
        end
    end
    return copy
end

-- Merge tables (target with source)
local function MergeTables(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" and type(target[key]) == "table" then
            MergeTables(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

-- Reset configuration to default
function ConfigManager:ResetToDefault()
    self.config = DeepCopy(DefaultConfig)
end

-- Get a configuration value
function ConfigManager:Get(category, key)
    if self.config[category] then
        if key then
            return self.config[category][key]
        end
        return self.config[category]
    end
    return nil
end

-- Set a configuration value
function ConfigManager:Set(category, key, value)
    if not self.config[category] then
        self.config[category] = {}
    end

    local oldValue = self.config[category][key]
    self.config[category][key] = value

    -- Trigger callbacks
    local callbackKey = category .. "." .. key
    if self.callbacks[callbackKey] then
        for _, callback in ipairs(self.callbacks[callbackKey]) do
            pcall(callback, value, oldValue)
        end
    end

    return true
end

-- Subscribe to configuration changes
function ConfigManager:OnChange(category, key, callback)
    local callbackKey = category .. "." .. key
    if not self.callbacks[callbackKey] then
        self.callbacks[callbackKey] = {}
    end
    table.insert(self.callbacks[callbackKey], callback)
end

-- Check if file system functions exist
local function HasFileSystem()
    return writefile and readfile and isfile and isfolder and makefolder
end

-- Save configuration to file
function ConfigManager:Save()
    if not HasFileSystem() then
        warn("[ConfigManager] File system not available")
        return false
    end

    local success, err = pcall(function()
        -- Create folder if it doesn't exist
        if not isfolder(self.configPath) then
            makefolder(self.configPath)
        end

        local filePath = self.configPath .. "/" .. self.configFile
        local jsonData = HttpService:JSONEncode(self.config)
        writefile(filePath, jsonData)
    end)

    if not success then
        warn("[ConfigManager] Failed to save config:", err)
        return false
    end

    return true
end

-- Load configuration from file
function ConfigManager:Load()
    if not HasFileSystem() then
        warn("[ConfigManager] File system not available")
        return false
    end

    local success, err = pcall(function()
        local filePath = self.configPath .. "/" .. self.configFile

        if isfile(filePath) then
            local jsonData = readfile(filePath)
            local loadedConfig = HttpService:JSONDecode(jsonData)

            -- Merge with default config to ensure all keys exist
            self:ResetToDefault()
            MergeTables(self.config, loadedConfig)
        end
    end)

    if not success then
        warn("[ConfigManager] Failed to load config:", err)
        return false
    end

    self.loaded = true
    return true
end

-- Delete saved configuration
function ConfigManager:Delete()
    if not HasFileSystem() then
        return false
    end

    local success = pcall(function()
        local filePath = self.configPath .. "/" .. self.configFile
        if isfile(filePath) then
            delfile(filePath)
        end
    end)

    return success
end

-- Export configuration as JSON string
function ConfigManager:Export()
    return HttpService:JSONEncode(self.config)
end

-- Import configuration from JSON string
function ConfigManager:Import(jsonString)
    local success, loadedConfig = pcall(function()
        return HttpService:JSONDecode(jsonString)
    end)

    if success and type(loadedConfig) == "table" then
        self:ResetToDefault()
        MergeTables(self.config, loadedConfig)
        return true
    end

    return false
end

-- Get all configuration categories
function ConfigManager:GetCategories()
    local categories = {}
    for category, _ in pairs(self.config) do
        table.insert(categories, category)
    end
    return categories
end

-- Check if configuration is loaded
function ConfigManager:IsLoaded()
    return self.loaded
end

-- Get default config
function ConfigManager:GetDefault(category, key)
    if DefaultConfig[category] then
        if key then
            return DefaultConfig[category][key]
        end
        return DeepCopy(DefaultConfig[category])
    end
    return nil
end

-- Quick access methods for common settings
function ConfigManager:IsAutoFarmEnabled()
    return self.config.General.AutoFarm
end

function ConfigManager:IsFruitSniperEnabled()
    return self.config.General.FruitSniper
end

function ConfigManager:IsBossFarmEnabled()
    return self.config.General.BossFarm
end

function ConfigManager:IsMasteryFarmEnabled()
    return self.config.General.MasteryFarm
end

function ConfigManager:GetTweenSpeed()
    return self.config.Teleport.TweenSpeed
end

function ConfigManager:IsESPEnabled()
    return self.config.ESP.Enabled
end

function ConfigManager:IsAntiAFKEnabled()
    return self.config.Misc.AntiAFK
end

return {
    new = ConfigManager.new,
    DefaultConfig = DefaultConfig
}
