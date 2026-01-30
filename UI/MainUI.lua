--[[
    MainUI.lua
    Professional Grade User Interface
    Version: 1.1.0

    Compatible with RenLib API (Section-based elements)
]]

local MainUI = {}
MainUI.__index = MainUI

local VERSION = "1.1.0"
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
        "Starter Island", "Marine Starter", "Middle Island", "Jungle",
        "Pirate Village", "Desert", "Frozen Village", "Marine Fortress",
        "Skylands", "Prison", "Colosseum", "Magma Village",
        "Underwater City", "Fountain City"
    },
    Sea2 = {
        "Kingdom of Rose", "Usopp Island", "Green Zone", "Graveyard",
        "Snow Mountain", "Hot and Cold", "Cursed Ship", "Ice Castle",
        "Forgotten Island", "Dark Arena"
    },
    Sea3 = {
        "Port Town", "Hydra Island", "Great Tree", "Floating Turtle",
        "Castle on the Sea", "Haunted Castle", "Sea of Treats",
        "Tiki Outpost", "Mansion"
    }
}

function MainUI.new()
    local self = setmetatable({}, MainUI)

    self.library = nil
    self.window = nil
    self.tabs = {}
    self.sections = {}
    self.elements = {}
    self.callbacks = {}

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

    -- Selected island for teleport
    self.selectedIsland = nil

    return self
end

function MainUI:GetVersion()
    return VERSION
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

-- Fallback UI when library fails
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
    title.Text = "Blox Fruits Pro v" .. VERSION
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
    self:SetupKeybinds()
    return false
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
    self:Notify("Auto Farm", self.autoFarmEnabled and "Enabled" or "Disabled")
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
    self:Notify("Fruit Sniper", self.fruitSniperEnabled and "Enabled" or "Disabled")
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
    self:Notify("ESP", self.espEnabled and "Enabled" or "Disabled")
end

-- Notification helper
function MainUI:Notify(title, content, duration)
    if self.library and self.library.Notify then
        pcall(function()
            self.library:Notify({
                Title = title or "Blox Fruits Pro",
                Content = content or "",
                Duration = duration or 3,
                Emoji = "✓"
            })
        end)
    elseif self.misc then
        self.misc:Notify(title, content)
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

    -- Create window using RenLib API
    local success, window = pcall(function()
        return self.library:CreateWindow({
            Name = "Blox Fruits Pro v" .. VERSION
        })
    end)

    if not success or not window then
        warn("[MainUI] Failed to create window:", window)
        return false
    end

    self.window = window

    -- Create all tabs and their content
    self:CreateMainTab()
    self:CreateFarmTab()
    self:CreateCombatTab()
    self:CreateTeleportTab()
    self:CreateFruitTab()
    self:CreateESPTab()
    self:CreateSettingsTab()

    -- Setup keybinds
    self:SetupKeybinds()

    return true
end

-- Create Main Tab
function MainUI:CreateMainTab()
    local tab = self.window:CreateTab({
        Name = "Main",
        Emoji = "🏠"
    })
    self.tabs.main = tab

    -- Quick Toggles Section
    local quickSection = tab:CreateSection({
        Name = "Quick Toggles",
        Side = "Left"
    })

    self.elements.autoFarmToggle = quickSection:CreateToggle({
        Name = "Auto Farm [U]",
        Default = false,
        Flag = "MainAutoFarm",
        Callback = function(value)
            self.autoFarmEnabled = value
            if self.config then self.config:Set("General", "AutoFarm", value) end
            if self.autoFarm then
                if value then self.autoFarm:Start() else self.autoFarm:Stop() end
            end
        end
    })

    self.elements.fruitSniperToggle = quickSection:CreateToggle({
        Name = "Fruit Sniper [I]",
        Default = false,
        Flag = "MainFruitSniper",
        Callback = function(value)
            self.fruitSniperEnabled = value
            if self.config then self.config:Set("General", "FruitSniper", value) end
            if self.fruitSniper then
                if value then self.fruitSniper:Start() else self.fruitSniper:Stop() end
            end
        end
    })

    self.elements.espToggle = quickSection:CreateToggle({
        Name = "ESP [O]",
        Default = false,
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
    local statusSection = tab:CreateSection({
        Name = "Status",
        Side = "Right"
    })

    self.elements.statusLabel = statusSection:CreateLabel("Status: Idle - Ready to farm")

    statusSection:CreateLabel("Press K to toggle UI visibility")
end

-- Create Farm Tab
function MainUI:CreateFarmTab()
    local tab = self.window:CreateTab({
        Name = "Auto Farm",
        Emoji = "🎯"
    })
    self.tabs.farm = tab

    -- Weapon Section
    local weaponSection = tab:CreateSection({
        Name = "Weapon Selection",
        Side = "Left"
    })

    weaponSection:CreateDropdown({
        Name = "Weapon Type",
        Values = {"Melee", "Sword", "Demon Fruit"},
        Default = "Melee",
        Flag = "WeaponType",
        Callback = function(value)
            if self.config then self.config:Set("Combat", "WeaponType", value) end
            if self.autoFarm then self.autoFarm:SetWeaponType(value) end
            if self.combat then self.combat:SetWeaponType(value) end
        end
    })

    weaponSection:CreateDropdown({
        Name = "Combat Method",
        Values = ATTACK_METHODS,
        Default = "All Methods Combined",
        Flag = "AttackMethod",
        Callback = function(value)
            if self.config then self.config:Set("Combat", "AttackMethod", value) end
            if self.combat then self.combat:SetAttackMethod(value) end
        end
    })

    -- Mob Settings Section
    local mobSection = tab:CreateSection({
        Name = "Mob Settings",
        Side = "Left"
    })

    mobSection:CreateToggle({
        Name = "Bring Mobs to Center",
        Default = true,
        Flag = "BringMobs",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "BringMobs", value) end
        end
    })

    mobSection:CreateToggle({
        Name = "Expand Enemy Hitbox",
        Default = true,
        Flag = "ExpandHitbox",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "ExpandHitbox", value) end
            if self.autoFarm then self.autoFarm:SetExpandHitbox(value) end
        end
    })

    mobSection:CreateSlider({
        Name = "Hitbox Size",
        Min = 10,
        Max = 100,
        Default = 50,
        Flag = "HitboxSize",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "HitboxSize", value) end
            if self.autoFarm then self.autoFarm:SetHitboxSize(value) end
        end
    })

    mobSection:CreateToggle({
        Name = "Anchor Mobs (Stop Movement)",
        Default = true,
        Flag = "AnchorMobs",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "AnchorMobs", value) end
        end
    })

    -- Position Section
    local posSection = tab:CreateSection({
        Name = "Position Settings",
        Side = "Right"
    })

    posSection:CreateSlider({
        Name = "Fly Height Above Mobs",
        Min = 5,
        Max = 100,
        Default = 15,
        Flag = "FlyHeight",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "FlyHeight", value) end
            if self.autoFarm then self.autoFarm:SetFlyHeight(value) end
        end
    })

    posSection:CreateSlider({
        Name = "Bring Distance (studs)",
        Min = 50,
        Max = 500,
        Default = 150,
        Flag = "BringDistance",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "BringDistance", value) end
        end
    })
end

-- Create Combat Tab
function MainUI:CreateCombatTab()
    local tab = self.window:CreateTab({
        Name = "Combat",
        Emoji = "⚔️"
    })
    self.tabs.combat = tab

    -- Auto Combat Section
    local combatSection = tab:CreateSection({
        Name = "Auto Combat",
        Side = "Left"
    })

    combatSection:CreateToggle({
        Name = "Auto Attack",
        Default = true,
        Flag = "AutoAttack",
        Callback = function(value)
            if self.config then self.config:Set("Combat", "AutoAttack", value) end
        end
    })

    combatSection:CreateToggle({
        Name = "Auto Skills (Z, X, C, V)",
        Default = true,
        Flag = "AutoSkills",
        Callback = function(value)
            if self.config then self.config:Set("Combat", "AutoSkills", value) end
        end
    })

    combatSection:CreateToggle({
        Name = "Auto Haki (J Key)",
        Default = true,
        Flag = "AutoHaki",
        Callback = function(value)
            if self.config then self.config:Set("Combat", "AutoHaki", value) end
        end
    })

    -- Timing Section
    local timingSection = tab:CreateSection({
        Name = "Timing",
        Side = "Right"
    })

    timingSection:CreateSlider({
        Name = "Attack Cooldown (ms)",
        Min = 50,
        Max = 500,
        Default = 100,
        Flag = "AttackCooldown",
        Callback = function(value)
            if self.config then self.config:Set("Combat", "AttackCooldown", value) end
            if self.combat then self.combat:SetAttackCooldown(value / 1000) end
        end
    })
end

-- Create Teleport Tab
function MainUI:CreateTeleportTab()
    local tab = self.window:CreateTab({
        Name = "Teleport",
        Emoji = "🧭"
    })
    self.tabs.teleport = tab

    -- Island Teleport Section
    local islandSection = tab:CreateSection({
        Name = "Island Teleport",
        Side = "Left"
    })

    local islands = self:GetCurrentIslands()

    islandSection:CreateDropdown({
        Name = "Select Island",
        Values = islands,
        Default = islands[1],
        Flag = "SelectedIsland",
        Callback = function(value)
            self.selectedIsland = value
        end
    })

    islandSection:CreateButton({
        Name = "Teleport to Island",
        Callback = function()
            if self.misc and self.selectedIsland then
                self.misc:TeleportToIsland(self.selectedIsland)
            elseif self.library and self.library.Flags and self.library.Flags.SelectedIsland then
                local island = self.library.Flags.SelectedIsland
                if self.misc then
                    self.misc:TeleportToIsland(island)
                end
            end
        end
    })

    -- Teleport Settings Section
    local settingsSection = tab:CreateSection({
        Name = "Teleport Settings",
        Side = "Right"
    })

    settingsSection:CreateSlider({
        Name = "Tween Speed (studs/s)",
        Min = 50,
        Max = 1000,
        Default = 200,
        Flag = "TweenSpeed",
        Callback = function(value)
            if self.config then self.config:Set("Teleport", "TweenSpeed", value) end
            if self.teleport then self.teleport:SetSpeed(value) end
        end
    })
end

-- Create Fruit Tab
function MainUI:CreateFruitTab()
    local tab = self.window:CreateTab({
        Name = "Fruit Sniper",
        Emoji = "🍎"
    })
    self.tabs.fruit = tab

    -- Collection Section
    local collectSection = tab:CreateSection({
        Name = "Collection",
        Side = "Left"
    })

    collectSection:CreateToggle({
        Name = "Auto Collect Fruits",
        Default = true,
        Flag = "AutoCollect",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "AutoCollect", value) end
        end
    })

    collectSection:CreateToggle({
        Name = "Auto Store Fruits",
        Default = false,
        Flag = "AutoStore",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "AutoStore", value) end
            if self.fruitSniper then self.fruitSniper:SetAutoStore(value) end
        end
    })

    collectSection:CreateSlider({
        Name = "Store Timeout (seconds)",
        Min = 2,
        Max = 10,
        Default = 5,
        Flag = "StoreTimeout",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "StoreTimeout", value) end
            if self.fruitSniper then self.fruitSniper:SetStoreTimeout(value) end
        end
    })

    -- Server Hop Section
    local hopSection = tab:CreateSection({
        Name = "Server Hop",
        Side = "Right"
    })

    hopSection:CreateToggle({
        Name = "Server Hop When No Fruits",
        Default = false,
        Flag = "ServerHopFruit",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "ServerHop", value) end
        end
    })

    -- Fruit Filters Section
    local filterSection = tab:CreateSection({
        Name = "Fruit Filters",
        Side = "Right"
    })

    filterSection:CreateToggle({
        Name = "Only Mythical Fruits",
        Default = false,
        Flag = "OnlyMythical",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "OnlyMythical", value) end
        end
    })

    filterSection:CreateToggle({
        Name = "Only Legendary+",
        Default = false,
        Flag = "OnlyLegendary",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "OnlyLegendary", value) end
        end
    })
end

-- Create ESP Tab
function MainUI:CreateESPTab()
    local tab = self.window:CreateTab({
        Name = "ESP",
        Emoji = "👁️"
    })
    self.tabs.esp = tab

    -- ESP Types Section
    local typesSection = tab:CreateSection({
        Name = "ESP Types",
        Side = "Left"
    })

    typesSection:CreateToggle({
        Name = "Fruit ESP",
        Default = true,
        Flag = "FruitESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "FruitESP", value) end
        end
    })

    typesSection:CreateToggle({
        Name = "Player ESP",
        Default = false,
        Flag = "PlayerESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "PlayerESP", value) end
        end
    })

    typesSection:CreateToggle({
        Name = "Boss ESP",
        Default = true,
        Flag = "BossESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "BossESP", value) end
        end
    })

    typesSection:CreateToggle({
        Name = "Chest ESP",
        Default = false,
        Flag = "ChestESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "ChestESP", value) end
        end
    })

    -- Display Section
    local displaySection = tab:CreateSection({
        Name = "Display",
        Side = "Right"
    })

    displaySection:CreateToggle({
        Name = "Show Distance",
        Default = true,
        Flag = "ShowDistance",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "ShowDistance", value) end
        end
    })
end

-- Create Settings Tab
function MainUI:CreateSettingsTab()
    local tab = self.window:CreateTab({
        Name = "Settings",
        Emoji = "⚙️",
        IsSettings = true
    })
    self.tabs.settings = tab

    -- Keybinds Section
    local keybindSection = tab:CreateSection({
        Name = "Keybinds",
        Side = "Left"
    })

    keybindSection:CreateLabel("U = Toggle Auto Farm")
    keybindSection:CreateLabel("I = Toggle Fruit Sniper")
    keybindSection:CreateLabel("O = Toggle ESP")
    keybindSection:CreateLabel("K = Toggle UI")

    -- Utilities Section
    local utilSection = tab:CreateSection({
        Name = "Utilities",
        Side = "Left"
    })

    utilSection:CreateToggle({
        Name = "No Clip",
        Default = false,
        Flag = "NoClip",
        Callback = function(value)
            if self.config then self.config:Set("Misc", "NoClip", value) end
            if self.misc then
                if value then self.misc:StartNoClip() else self.misc:StopNoClip() end
            end
        end
    })

    utilSection:CreateToggle({
        Name = "Full Bright",
        Default = false,
        Flag = "FullBright",
        Callback = function(value)
            if self.misc then self.misc:SetFullBright(value) end
        end
    })

    -- Server Section
    local serverSection = tab:CreateSection({
        Name = "Server",
        Side = "Right"
    })

    serverSection:CreateButton({
        Name = "Server Hop",
        Callback = function()
            if self.misc then self.misc:ServerHop() end
        end
    })

    serverSection:CreateButton({
        Name = "Rejoin Server",
        Callback = function()
            if self.misc then self.misc:Rejoin() end
        end
    })

    -- Config Section
    local configSection = tab:CreateSection({
        Name = "Configuration",
        Side = "Right"
    })

    configSection:CreateButton({
        Name = "Save Configuration",
        Callback = function()
            if self.config then
                self.config:Save()
                self:Notify("Config", "Saved!")
            end
        end
    })

    configSection:CreateButton({
        Name = "Load Configuration",
        Callback = function()
            if self.config then
                self.config:Load()
                self:Notify("Config", "Loaded!")
            end
        end
    })

    -- Info Section
    local infoSection = tab:CreateSection({
        Name = "Info",
        Side = "Right"
    })

    infoSection:CreateLabel("Anti-AFK: Always enabled")
    infoSection:CreateLabel("Version: " .. VERSION)
end

-- Setup keybinds
function MainUI:SetupKeybinds()
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
            self:Toggle()
        end
    end)
end

-- Toggle UI
function MainUI:Toggle()
    if self.window and self.window.Toggle then
        self.window:Toggle()
    elseif self.window and self.window.Minimize and self.window.Restore then
        -- RenLib uses Minimize/Restore
        if self.isMinimized then
            self.window:Restore()
            self.isMinimized = false
        else
            self.window:Minimize()
            self.isMinimized = true
        end
    elseif self.fallbackGui then
        self.fallbackGui.Enabled = not self.fallbackGui.Enabled
    end
end

-- Update status
function MainUI:UpdateStatus(status)
    if self.elements.statusLabel then
        pcall(function()
            -- Try to update label if possible
            if self.elements.statusLabel.Set then
                self.elements.statusLabel:Set("Status: " .. (status or "Idle"))
            end
        end)
    end
end

-- Initialize
function MainUI:Init()
    if self:LoadLibrary() then
        self:CreateWindow()
    end
end

-- Destroy
function MainUI:Destroy()
    pcall(function()
        if self.window and self.window.Close then
            self.window:Close()
        elseif self.window and self.window.Destroy then
            self.window:Destroy()
        end
        if self.fallbackGui then
            self.fallbackGui:Destroy()
        end
    end)
    self.callbacks = {}
end

return {
    new = MainUI.new,
    VERSION = VERSION
}
