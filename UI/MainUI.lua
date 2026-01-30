--[[
    MainUI.lua
    Professional Grade User Interface
    Complete customization for all features

    Features:
    - Attack Method Selection (M1, Remotes, HookFunctions)
    - Hitbox Expansion Toggle
    - Quick Toggle Keybind (Default: U)
    - Island Teleport
    - Fruit Sniper with Auto Store
    - ESP Settings
    - All settings customizable
]]

local MainUI = {}
MainUI.__index = MainUI

local LIBRARY_URL = "https://raw.githubusercontent.com/xsakyx/RobloxUILib/refs/heads/main/RenLibBêta.lua"

-- Attack methods available
local ATTACK_METHODS = {
    "M1 (Mouse Click)",
    "Remote Events",
    "Hook Functions",
    "FireTouchInterest",
    "All Methods Combined"
}

-- Island lists by sea
local ISLAND_DATA = {
    Sea1 = {
        "Starter Island",
        "Marine Starter",
        "Middle Island",
        "Jungle",
        "Pirate Village",
        "Desert",
        "Frozen Village",
        "Marine Fortress",
        "Skylands",
        "Prison",
        "Colosseum",
        "Magma Village",
        "Underwater City",
        "Fountain City"
    },
    Sea2 = {
        "Kingdom of Rose",
        "Usopp Island",
        "Green Zone",
        "Graveyard",
        "Snow Mountain",
        "Hot and Cold",
        "Cursed Ship",
        "Ice Castle",
        "Forgotten Island",
        "Dark Arena"
    },
    Sea3 = {
        "Port Town",
        "Hydra Island",
        "Great Tree",
        "Floating Turtle",
        "Castle on the Sea",
        "Haunted Castle",
        "Sea of Treats",
        "Tiki Outpost",
        "Mansion"
    }
}

function MainUI.new()
    local self = setmetatable({}, MainUI)

    self.library = nil
    self.window = nil
    self.tabs = {}
    self.elements = {}
    self.callbacks = {}
    self.keybinds = {
        ToggleAutoFarm = "U",
        ToggleFruitSniper = "I",
        ToggleESP = "O",
        ToggleUI = "K"
    }

    -- Module references
    self.config = nil
    self.autoFarm = nil
    self.fruitSniper = nil
    self.combat = nil
    self.esp = nil
    self.misc = nil
    self.teleport = nil

    -- State tracking
    self.autoFarmEnabled = false
    self.fruitSniperEnabled = false
    self.espEnabled = false

    return self
end

-- Load UI library
function MainUI:LoadLibrary()
    local success, library = pcall(function()
        return loadstring(game:HttpGet(LIBRARY_URL))()
    end)

    if success and library then
        self.library = library
        return true
    else
        warn("[MainUI] Failed to load UI library:", library)
        return self:CreateFallbackUI()
    end
end

-- Professional fallback UI
function MainUI:CreateFallbackUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BloxFruitScript"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 400, 0, 300)
    mainFrame.Position = UDim2.new(0.5, -200, 0.5, -150)
    mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = mainFrame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 40)
    title.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    title.Text = "Blox Fruits Pro"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.Parent = mainFrame

    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 8)
    titleCorner.Parent = title

    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, -20, 0, 200)
    info.Position = UDim2.new(0, 10, 0, 50)
    info.BackgroundTransparency = 1
    info.Text = [[
UI Library failed to load.
Script is still running in background.

Quick Toggles:
  U = Toggle Auto Farm
  I = Toggle Fruit Sniper
  O = Toggle ESP
  K = Toggle this UI

Features are running with default settings.
    ]]
    info.TextColor3 = Color3.fromRGB(200, 200, 200)
    info.Font = Enum.Font.Gotham
    info.TextSize = 13
    info.TextWrapped = true
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextYAlignment = Enum.TextYAlignment.Top
    info.Parent = mainFrame

    pcall(function()
        screenGui.Parent = game:GetService("CoreGui")
    end)

    if not screenGui.Parent then
        screenGui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    end

    self.fallbackGui = screenGui
    self:SetupFallbackKeybinds()
    return false
end

-- Setup keybinds for fallback UI
function MainUI:SetupFallbackKeybinds()
    local UIS = game:GetService("UserInputService")

    UIS.InputBegan:Connect(function(input, processed)
        if processed then return end

        if input.KeyCode == Enum.KeyCode.U then
            self:ToggleAutoFarm()
        elseif input.KeyCode == Enum.KeyCode.I then
            self:ToggleFruitSniper()
        elseif input.KeyCode == Enum.KeyCode.O then
            self:ToggleESP()
        elseif input.KeyCode == Enum.KeyCode.K then
            if self.fallbackGui then
                self.fallbackGui.Enabled = not self.fallbackGui.Enabled
            end
        end
    end)
end

-- Set modules
function MainUI:SetModules(modules)
    self.config = modules.config
    self.autoFarm = modules.autoFarm
    self.fruitSniper = modules.fruitSniper
    self.combat = modules.combat
    self.esp = modules.esp
    self.misc = modules.misc
    self.teleport = modules.teleport
end

-- Toggle functions
function MainUI:ToggleAutoFarm()
    self.autoFarmEnabled = not self.autoFarmEnabled
    if self.config then
        self.config:Set("General", "AutoFarm", self.autoFarmEnabled)
    end
    if self.autoFarm then
        if self.autoFarmEnabled then
            self.autoFarm:Start()
        else
            self.autoFarm:Stop()
        end
    end
    if self.misc then
        self.misc:Notify("Auto Farm", self.autoFarmEnabled and "Enabled" or "Disabled")
    end
end

function MainUI:ToggleFruitSniper()
    self.fruitSniperEnabled = not self.fruitSniperEnabled
    if self.config then
        self.config:Set("General", "FruitSniper", self.fruitSniperEnabled)
    end
    if self.fruitSniper then
        if self.fruitSniperEnabled then
            self.fruitSniper:Start()
        else
            self.fruitSniper:Stop()
        end
    end
    if self.misc then
        self.misc:Notify("Fruit Sniper", self.fruitSniperEnabled and "Enabled" or "Disabled")
    end
end

function MainUI:ToggleESP()
    self.espEnabled = not self.espEnabled
    if self.config then
        self.config:Set("ESP", "Enabled", self.espEnabled)
    end
    if self.esp then
        if self.espEnabled then
            self.esp:Start()
        else
            self.esp:Stop()
        end
    end
    if self.misc then
        self.misc:Notify("ESP", self.espEnabled and "Enabled" or "Disabled")
    end
end

-- Get current sea's islands
function MainUI:GetCurrentIslands()
    local placeId = game.PlaceId
    local seaMap = {
        [2753915549] = "Sea1",
        [4442272183] = "Sea2",
        [7449423635] = "Sea3"
    }
    local sea = seaMap[placeId] or "Sea1"
    return ISLAND_DATA[sea] or ISLAND_DATA.Sea1
end

-- Create window
function MainUI:CreateWindow()
    if not self.library then return false end

    self.window = self.library:CreateWindow({
        Name = "Blox Fruits Pro",
        LoadingTitle = "Blox Fruits Pro",
        LoadingSubtitle = "Professional Auto Farm Suite",
        ConfigurationSaving = {
            Enabled = true,
            FolderName = "BloxFruitScript",
            FileName = "Config"
        }
    })

    -- Create all tabs
    self:CreateMainTab()
    self:CreateAutoFarmTab()
    self:CreateCombatTab()
    self:CreateTeleportTab()
    self:CreateFruitSniperTab()
    self:CreateESPTab()
    self:CreateSettingsTab()

    -- Setup global keybinds
    self:SetupKeybinds()

    return true
end

-- MAIN TAB - Quick Controls
function MainUI:CreateMainTab()
    local tab = self.window:CreateTab({
        Name = "Main",
        Icon = "home"
    })
    self.tabs.main = tab

    -- Quick Toggles Section
    tab:CreateSection("Quick Toggles")

    self.elements.autoFarmToggle = tab:CreateToggle({
        Name = "Auto Farm [U]",
        CurrentValue = false,
        Flag = "MainAutoFarm",
        Callback = function(value)
            self.autoFarmEnabled = value
            if self.config then self.config:Set("General", "AutoFarm", value) end
            if self.autoFarm then
                if value then self.autoFarm:Start() else self.autoFarm:Stop() end
            end
        end
    })

    self.elements.fruitSniperToggle = tab:CreateToggle({
        Name = "Fruit Sniper [I]",
        CurrentValue = false,
        Flag = "MainFruitSniper",
        Callback = function(value)
            self.fruitSniperEnabled = value
            if self.config then self.config:Set("General", "FruitSniper", value) end
            if self.fruitSniper then
                if value then self.fruitSniper:Start() else self.fruitSniper:Stop() end
            end
        end
    })

    self.elements.espToggle = tab:CreateToggle({
        Name = "ESP [O]",
        CurrentValue = false,
        Flag = "MainESP",
        Callback = function(value)
            self.espEnabled = value
            if self.config then self.config:Set("ESP", "Enabled", value) end
            if self.esp then
                if value then self.esp:Start() else self.esp:Stop() end
            end
        end
    })

    -- Status Section
    tab:CreateSection("Status")

    self.elements.statusParagraph = tab:CreateParagraph({
        Title = "Current Status",
        Content = "Idle - Ready to farm"
    })

    self.elements.statsParagraph = tab:CreateParagraph({
        Title = "Player Stats",
        Content = "Level: 0 | Beli: 0 | Sea: 1"
    })
end

-- AUTO FARM TAB - All farming settings
function MainUI:CreateAutoFarmTab()
    local tab = self.window:CreateTab({
        Name = "Auto Farm",
        Icon = "target"
    })
    self.tabs.autoFarm = tab

    -- Weapon Selection
    tab:CreateSection("Weapon Selection")

    tab:CreateDropdown({
        Name = "Weapon Type",
        Options = {"Melee", "Sword", "Demon Fruit"},
        CurrentOption = {"Melee"},
        Flag = "WeaponType",
        Callback = function(option)
            local selected = type(option) == "table" and option[1] or option
            if self.config then self.config:Set("Combat", "WeaponType", selected) end
            if self.autoFarm then self.autoFarm:SetWeaponType(selected) end
            if self.combat then self.combat:SetWeaponType(selected) end
        end
    })

    -- Attack Method
    tab:CreateSection("Attack Method")

    tab:CreateDropdown({
        Name = "Combat Method",
        Options = ATTACK_METHODS,
        CurrentOption = {"All Methods Combined"},
        Flag = "AttackMethod",
        Callback = function(option)
            local selected = type(option) == "table" and option[1] or option
            if self.config then self.config:Set("Combat", "AttackMethod", selected) end
            if self.combat then self.combat:SetAttackMethod(selected) end
        end
    })

    tab:CreateParagraph({
        Title = "Attack Methods Info",
        Content = "M1: Mouse clicks (blocks input)\nRemotes: Game remote events\nHook: Function hooks\nFireTouch: Touch simulation\nAll: Uses all methods"
    })

    -- Mob Settings
    tab:CreateSection("Mob Settings")

    tab:CreateToggle({
        Name = "Bring Mobs to Center",
        CurrentValue = true,
        Flag = "BringMobs",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "BringMobs", value) end
        end
    })

    tab:CreateToggle({
        Name = "Expand Enemy Hitbox",
        CurrentValue = true,
        Flag = "ExpandHitbox",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "ExpandHitbox", value) end
            if self.autoFarm then self.autoFarm:SetExpandHitbox(value) end
        end
    })

    tab:CreateSlider({
        Name = "Hitbox Size",
        Range = {10, 100},
        Increment = 5,
        CurrentValue = 50,
        Flag = "HitboxSize",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "HitboxSize", value) end
            if self.autoFarm then self.autoFarm:SetHitboxSize(value) end
        end
    })

    tab:CreateToggle({
        Name = "Anchor Mobs (Stop Movement)",
        CurrentValue = true,
        Flag = "AnchorMobs",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "AnchorMobs", value) end
        end
    })

    -- Position Settings
    tab:CreateSection("Position Settings")

    tab:CreateSlider({
        Name = "Fly Height Above Mobs",
        Range = {5, 100},
        Increment = 1,
        CurrentValue = 15,
        Flag = "FlyHeight",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "FlyHeight", value) end
            if self.autoFarm then self.autoFarm:SetFlyHeight(value) end
        end
    })

    tab:CreateSlider({
        Name = "Bring Distance (studs)",
        Range = {50, 500},
        Increment = 10,
        CurrentValue = 150,
        Flag = "BringDistance",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "BringDistance", value) end
        end
    })

    -- Character Settings
    tab:CreateSection("Character Settings")

    tab:CreateToggle({
        Name = "No Clip During Farm",
        CurrentValue = true,
        Flag = "FarmNoClip",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "NoClip", value) end
        end
    })
end

-- COMBAT TAB
function MainUI:CreateCombatTab()
    local tab = self.window:CreateTab({
        Name = "Combat",
        Icon = "swords"
    })
    self.tabs.combat = tab

    -- Auto Combat
    tab:CreateSection("Auto Combat")

    tab:CreateToggle({
        Name = "Auto Attack",
        CurrentValue = true,
        Flag = "AutoAttack",
        Callback = function(value)
            if self.config then self.config:Set("Combat", "AutoAttack", value) end
        end
    })

    tab:CreateToggle({
        Name = "Auto Skills (Z, X, C, V)",
        CurrentValue = true,
        Flag = "AutoSkills",
        Callback = function(value)
            if self.config then self.config:Set("Combat", "AutoSkills", value) end
        end
    })

    tab:CreateToggle({
        Name = "Auto Haki (J Key)",
        CurrentValue = true,
        Flag = "AutoHaki",
        Callback = function(value)
            if self.config then self.config:Set("Combat", "AutoHaki", value) end
        end
    })

    -- Timing Settings
    tab:CreateSection("Timing")

    tab:CreateSlider({
        Name = "Attack Cooldown (ms)",
        Range = {50, 500},
        Increment = 10,
        CurrentValue = 100,
        Flag = "AttackCooldown",
        Callback = function(value)
            if self.config then self.config:Set("Combat", "AttackCooldown", value) end
            if self.combat then self.combat:SetAttackCooldown(value / 1000) end
        end
    })

    tab:CreateSlider({
        Name = "Skill Cooldown (ms)",
        Range = {100, 1000},
        Increment = 50,
        CurrentValue = 300,
        Flag = "SkillCooldown",
        Callback = function(value)
            if self.config then self.config:Set("Combat", "SkillCooldown", value) end
            if self.combat then self.combat:SetSkillCooldown(value / 1000) end
        end
    })
end

-- TELEPORT TAB
function MainUI:CreateTeleportTab()
    local tab = self.window:CreateTab({
        Name = "Teleport",
        Icon = "navigation"
    })
    self.tabs.teleport = tab

    -- Island Teleport
    tab:CreateSection("Island Teleport")

    local islands = self:GetCurrentIslands()

    tab:CreateDropdown({
        Name = "Select Island",
        Options = islands,
        CurrentOption = {},
        Flag = "SelectedIsland",
        Callback = function(option)
            -- Store for teleport button
        end
    })

    tab:CreateButton({
        Name = "Teleport to Island",
        Callback = function()
            if self.misc then
                local flags = self.library and self.library.Flags
                if flags and flags.SelectedIsland then
                    local island = type(flags.SelectedIsland) == "table" and flags.SelectedIsland[1] or flags.SelectedIsland
                    self.misc:TeleportToIsland(island)
                end
            end
        end
    })

    -- Teleport Settings
    tab:CreateSection("Teleport Settings")

    tab:CreateSlider({
        Name = "Tween Speed (studs/s)",
        Range = {50, 1000},
        Increment = 25,
        CurrentValue = 200,
        Flag = "TweenSpeed",
        Callback = function(value)
            if self.config then self.config:Set("Teleport", "TweenSpeed", value) end
            if self.teleport then self.teleport:SetSpeed(value) end
        end
    })

    tab:CreateToggle({
        Name = "Use BodyVelocity (Smoother)",
        CurrentValue = true,
        Flag = "UseBodyVelocity",
        Callback = function(value)
            if self.config then self.config:Set("Teleport", "UseBodyVelocity", value) end
        end
    })
end

-- FRUIT SNIPER TAB
function MainUI:CreateFruitSniperTab()
    local tab = self.window:CreateTab({
        Name = "Fruit Sniper",
        Icon = "apple"
    })
    self.tabs.fruitSniper = tab

    -- Collection Settings
    tab:CreateSection("Collection")

    tab:CreateToggle({
        Name = "Auto Collect Fruits",
        CurrentValue = true,
        Flag = "AutoCollect",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "AutoCollect", value) end
        end
    })

    tab:CreateToggle({
        Name = "Auto Store Fruits",
        CurrentValue = false,
        Flag = "AutoStore",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "AutoStore", value) end
            if self.fruitSniper then self.fruitSniper:SetAutoStore(value) end
        end
    })

    tab:CreateParagraph({
        Title = "Auto Store Info",
        Content = "Tries to store fruit after pickup.\nIf already owned, closes UI and\ncontinues farming automatically."
    })

    tab:CreateSlider({
        Name = "Store Timeout (seconds)",
        Range = {2, 10},
        Increment = 1,
        CurrentValue = 5,
        Flag = "StoreTimeout",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "StoreTimeout", value) end
            if self.fruitSniper then self.fruitSniper:SetStoreTimeout(value) end
        end
    })

    -- Server Hop
    tab:CreateSection("Server Hop")

    tab:CreateToggle({
        Name = "Server Hop When No Fruits",
        CurrentValue = false,
        Flag = "ServerHopFruit",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "ServerHop", value) end
        end
    })

    tab:CreateSlider({
        Name = "Server Hop Delay (seconds)",
        Range = {10, 120},
        Increment = 5,
        CurrentValue = 30,
        Flag = "ServerHopDelay",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "ServerHopDelay", value) end
        end
    })

    -- Filters
    tab:CreateSection("Fruit Filters")

    tab:CreateToggle({
        Name = "Only Mythical Fruits",
        CurrentValue = false,
        Flag = "OnlyMythical",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "OnlyMythical", value) end
            if value and self.config then
                self.config:Set("FruitSniper", "OnlyLegendary", false)
            end
        end
    })

    tab:CreateToggle({
        Name = "Only Legendary+",
        CurrentValue = false,
        Flag = "OnlyLegendary",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "OnlyLegendary", value) end
        end
    })
end

-- ESP TAB
function MainUI:CreateESPTab()
    local tab = self.window:CreateTab({
        Name = "ESP",
        Icon = "eye"
    })
    self.tabs.esp = tab

    -- ESP Types
    tab:CreateSection("ESP Types")

    tab:CreateToggle({
        Name = "Fruit ESP",
        CurrentValue = true,
        Flag = "FruitESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "FruitESP", value) end
            if self.esp then self.esp:SetType("Fruit", value) end
        end
    })

    tab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = false,
        Flag = "PlayerESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "PlayerESP", value) end
            if self.esp then self.esp:SetType("Player", value) end
        end
    })

    tab:CreateToggle({
        Name = "Boss ESP",
        CurrentValue = true,
        Flag = "BossESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "BossESP", value) end
            if self.esp then self.esp:SetType("Boss", value) end
        end
    })

    tab:CreateToggle({
        Name = "Chest ESP",
        CurrentValue = false,
        Flag = "ChestESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "ChestESP", value) end
            if self.esp then self.esp:SetType("Chest", value) end
        end
    })

    -- Display Settings
    tab:CreateSection("Display Settings")

    tab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = true,
        Flag = "ShowDistance",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "ShowDistance", value) end
        end
    })

    tab:CreateToggle({
        Name = "Show Name",
        CurrentValue = true,
        Flag = "ShowName",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "ShowName", value) end
        end
    })

    -- Distance Settings
    tab:CreateSection("Detection Distance")

    tab:CreateSlider({
        Name = "Fruit Distance",
        Range = {1000, 20000},
        Increment = 500,
        CurrentValue = 10000,
        Flag = "FruitDistance",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "FruitDistance", value) end
        end
    })

    tab:CreateSlider({
        Name = "Player Distance",
        Range = {500, 5000},
        Increment = 100,
        CurrentValue = 2000,
        Flag = "PlayerDistance",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "PlayerDistance", value) end
        end
    })

    tab:CreateSlider({
        Name = "Boss Distance",
        Range = {1000, 10000},
        Increment = 500,
        CurrentValue = 5000,
        Flag = "BossDistance",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "BossDistance", value) end
        end
    })
end

-- SETTINGS TAB
function MainUI:CreateSettingsTab()
    local tab = self.window:CreateTab({
        Name = "Settings",
        Icon = "settings"
    })
    self.tabs.settings = tab

    -- Keybinds
    tab:CreateSection("Keybinds")

    tab:CreateKeybind({
        Name = "Toggle Auto Farm",
        CurrentKeybind = "U",
        Flag = "KeyAutoFarm",
        Callback = function()
            self:ToggleAutoFarm()
            -- Update UI toggle
            if self.elements.autoFarmToggle then
                pcall(function()
                    self.elements.autoFarmToggle:Set(self.autoFarmEnabled)
                end)
            end
        end
    })

    tab:CreateKeybind({
        Name = "Toggle Fruit Sniper",
        CurrentKeybind = "I",
        Flag = "KeyFruitSniper",
        Callback = function()
            self:ToggleFruitSniper()
            if self.elements.fruitSniperToggle then
                pcall(function()
                    self.elements.fruitSniperToggle:Set(self.fruitSniperEnabled)
                end)
            end
        end
    })

    tab:CreateKeybind({
        Name = "Toggle ESP",
        CurrentKeybind = "O",
        Flag = "KeyESP",
        Callback = function()
            self:ToggleESP()
            if self.elements.espToggle then
                pcall(function()
                    self.elements.espToggle:Set(self.espEnabled)
                end)
            end
        end
    })

    tab:CreateKeybind({
        Name = "Toggle UI",
        CurrentKeybind = "K",
        Flag = "KeyToggleUI",
        Callback = function()
            if self.window then
                self.window:Toggle()
            end
        end
    })

    -- Utilities
    tab:CreateSection("Utilities")

    tab:CreateToggle({
        Name = "No Clip",
        CurrentValue = false,
        Flag = "NoClip",
        Callback = function(value)
            if self.config then self.config:Set("Misc", "NoClip", value) end
            if self.misc then
                if value then self.misc:StartNoClip() else self.misc:StopNoClip() end
            end
        end
    })

    tab:CreateToggle({
        Name = "Full Bright",
        CurrentValue = false,
        Flag = "FullBright",
        Callback = function(value)
            if self.misc then self.misc:SetFullBright(value) end
        end
    })

    tab:CreateToggle({
        Name = "Infinite Jump",
        CurrentValue = false,
        Flag = "InfiniteJump",
        Callback = function(value)
            if self.misc then self.misc:SetInfiniteJump(value) end
        end
    })

    -- Server Actions
    tab:CreateSection("Server")

    tab:CreateButton({
        Name = "Server Hop",
        Callback = function()
            if self.misc then self.misc:ServerHop() end
        end
    })

    tab:CreateButton({
        Name = "Rejoin Server",
        Callback = function()
            if self.misc then self.misc:Rejoin() end
        end
    })

    tab:CreateButton({
        Name = "Reset Character",
        Callback = function()
            if self.misc then self.misc:ResetCharacter() end
        end
    })

    -- Config
    tab:CreateSection("Configuration")

    tab:CreateButton({
        Name = "Save Configuration",
        Callback = function()
            if self.config then
                self.config:Save()
                if self.misc then self.misc:Notify("Config", "Configuration saved!") end
            end
        end
    })

    tab:CreateButton({
        Name = "Load Configuration",
        Callback = function()
            if self.config then
                self.config:Load()
                if self.misc then self.misc:Notify("Config", "Configuration loaded!") end
            end
        end
    })

    tab:CreateButton({
        Name = "Reset to Defaults",
        Callback = function()
            if self.config then
                self.config:Reset()
                if self.misc then self.misc:Notify("Config", "Reset to defaults!") end
            end
        end
    })

    -- Info
    tab:CreateSection("Information")

    tab:CreateParagraph({
        Title = "Anti-AFK",
        Content = "Anti-AFK is always enabled automatically.\nYou will never be kicked for idling."
    })

    tab:CreateParagraph({
        Title = "Credits",
        Content = "Blox Fruits Pro\nProfessional Auto Farm Suite"
    })
end

-- Setup global keybinds
function MainUI:SetupKeybinds()
    local UIS = game:GetService("UserInputService")

    UIS.InputBegan:Connect(function(input, processed)
        if processed then return end

        -- These are handled by the library keybinds
        -- This is a backup in case library fails
    end)
end

-- Toggle window
function MainUI:Toggle()
    if self.window then
        self.window:Toggle()
    elseif self.fallbackGui then
        self.fallbackGui.Enabled = not self.fallbackGui.Enabled
    end
end

-- Update status
function MainUI:UpdateStatus(status)
    if self.elements.statusParagraph then
        pcall(function()
            self.elements.statusParagraph:Set({
                Title = "Current Status",
                Content = status or "Idle"
            })
        end)
    end
end

-- Update stats
function MainUI:UpdateStats(stats)
    if self.elements.statsParagraph then
        pcall(function()
            self.elements.statsParagraph:Set({
                Title = "Player Stats",
                Content = string.format(
                    "Level: %d | Beli: %s | Sea: %d",
                    stats.Level or 0,
                    tostring(stats.Beli or 0),
                    stats.CurrentSea or 1
                )
            })
        end)
    end
end

-- Callbacks
function MainUI:OnToggle(name, callback)
    self.callbacks["on" .. name .. "Toggle"] = callback
end

-- Initialize
function MainUI:Init()
    if self:LoadLibrary() then
        self:CreateWindow()
    end
end

-- Cleanup
function MainUI:Destroy()
    pcall(function()
        if self.window then self.window:Destroy() end
        if self.fallbackGui then self.fallbackGui:Destroy() end
    end)
    self.callbacks = {}
end

return {
    new = MainUI.new
}
