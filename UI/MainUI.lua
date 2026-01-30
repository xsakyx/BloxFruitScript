--[[
    MainUI.lua
    Professional Grade User Interface
    Version: 1.1.0

    Compatible with RenLib API
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

-- Helper to add element (tries different API patterns)
local function AddElement(parent, elementType, options)
    local methods = {
        "Add" .. elementType,
        "Create" .. elementType,
        elementType
    }

    for _, method in ipairs(methods) do
        if parent[method] then
            local success, result = pcall(function()
                return parent[method](parent, options)
            end)
            if success then
                return result
            end
        end
    end

    warn("[MainUI] Could not create element:", elementType)
    return nil
end

-- Create window
function MainUI:CreateWindow()
    if not self.library then return false end

    -- Try different window creation methods
    local windowOptions = {
        Name = "Blox Fruits Pro v" .. VERSION,
        LoadingTitle = "Blox Fruits Pro",
        LoadingSubtitle = "Professional Auto Farm Suite",
        ConfigurationSaving = {
            Enabled = true,
            FolderName = "BloxFruitScript",
            FileName = "Config"
        }
    }

    -- Try CreateWindow or MakeWindow
    if self.library.CreateWindow then
        self.window = self.library:CreateWindow(windowOptions)
    elseif self.library.MakeWindow then
        self.window = self.library:MakeWindow(windowOptions)
    elseif self.library.new then
        self.window = self.library.new(windowOptions)
    else
        warn("[MainUI] Unknown library API")
        return false
    end

    if not self.window then
        warn("[MainUI] Failed to create window")
        return false
    end

    -- Create tabs
    self:CreateTabs()

    -- Setup keybinds
    self:SetupKeybinds()

    return true
end

-- Create all tabs
function MainUI:CreateTabs()
    -- Try to create tabs with different API patterns
    local tabMethod = self.window.CreateTab or self.window.AddTab or self.window.MakeTab
    if not tabMethod then
        warn("[MainUI] No tab creation method found")
        return
    end

    -- MAIN TAB
    local mainTab = tabMethod(self.window, {Name = "Main", Icon = "home"})
    if mainTab then
        self.tabs.main = mainTab
        self:PopulateMainTab(mainTab)
    end

    -- AUTO FARM TAB
    local farmTab = tabMethod(self.window, {Name = "Auto Farm", Icon = "target"})
    if farmTab then
        self.tabs.farm = farmTab
        self:PopulateFarmTab(farmTab)
    end

    -- COMBAT TAB
    local combatTab = tabMethod(self.window, {Name = "Combat", Icon = "swords"})
    if combatTab then
        self.tabs.combat = combatTab
        self:PopulateCombatTab(combatTab)
    end

    -- TELEPORT TAB
    local teleportTab = tabMethod(self.window, {Name = "Teleport", Icon = "navigation"})
    if teleportTab then
        self.tabs.teleport = teleportTab
        self:PopulateTeleportTab(teleportTab)
    end

    -- FRUIT SNIPER TAB
    local fruitTab = tabMethod(self.window, {Name = "Fruit Sniper", Icon = "apple"})
    if fruitTab then
        self.tabs.fruit = fruitTab
        self:PopulateFruitTab(fruitTab)
    end

    -- ESP TAB
    local espTab = tabMethod(self.window, {Name = "ESP", Icon = "eye"})
    if espTab then
        self.tabs.esp = espTab
        self:PopulateESPTab(espTab)
    end

    -- SETTINGS TAB
    local settingsTab = tabMethod(self.window, {Name = "Settings", Icon = "settings"})
    if settingsTab then
        self.tabs.settings = settingsTab
        self:PopulateSettingsTab(settingsTab)
    end
end

-- Populate Main Tab
function MainUI:PopulateMainTab(tab)
    -- Section
    AddElement(tab, "Section", {Name = "Quick Toggles"})

    -- Auto Farm Toggle
    self.elements.autoFarmToggle = AddElement(tab, "Toggle", {
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

    -- Fruit Sniper Toggle
    self.elements.fruitSniperToggle = AddElement(tab, "Toggle", {
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

    -- ESP Toggle
    self.elements.espToggle = AddElement(tab, "Toggle", {
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

    -- Status
    AddElement(tab, "Section", {Name = "Status"})

    self.elements.statusParagraph = AddElement(tab, "Paragraph", {
        Title = "Current Status",
        Content = "Idle - Ready to farm"
    })
end

-- Populate Farm Tab
function MainUI:PopulateFarmTab(tab)
    AddElement(tab, "Section", {Name = "Weapon Selection"})

    AddElement(tab, "Dropdown", {
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

    AddElement(tab, "Section", {Name = "Attack Method"})

    AddElement(tab, "Dropdown", {
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

    AddElement(tab, "Section", {Name = "Mob Settings"})

    AddElement(tab, "Toggle", {
        Name = "Bring Mobs to Center",
        CurrentValue = true,
        Flag = "BringMobs",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "BringMobs", value) end
        end
    })

    AddElement(tab, "Toggle", {
        Name = "Expand Enemy Hitbox",
        CurrentValue = true,
        Flag = "ExpandHitbox",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "ExpandHitbox", value) end
            if self.autoFarm then self.autoFarm:SetExpandHitbox(value) end
        end
    })

    AddElement(tab, "Slider", {
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

    AddElement(tab, "Toggle", {
        Name = "Anchor Mobs (Stop Movement)",
        CurrentValue = true,
        Flag = "AnchorMobs",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "AnchorMobs", value) end
        end
    })

    AddElement(tab, "Section", {Name = "Position Settings"})

    AddElement(tab, "Slider", {
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

    AddElement(tab, "Slider", {
        Name = "Bring Distance (studs)",
        Range = {50, 500},
        Increment = 10,
        CurrentValue = 150,
        Flag = "BringDistance",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "BringDistance", value) end
        end
    })
end

-- Populate Combat Tab
function MainUI:PopulateCombatTab(tab)
    AddElement(tab, "Section", {Name = "Auto Combat"})

    AddElement(tab, "Toggle", {
        Name = "Auto Attack",
        CurrentValue = true,
        Flag = "AutoAttack",
        Callback = function(value)
            if self.config then self.config:Set("Combat", "AutoAttack", value) end
        end
    })

    AddElement(tab, "Toggle", {
        Name = "Auto Skills (Z, X, C, V)",
        CurrentValue = true,
        Flag = "AutoSkills",
        Callback = function(value)
            if self.config then self.config:Set("Combat", "AutoSkills", value) end
        end
    })

    AddElement(tab, "Toggle", {
        Name = "Auto Haki (J Key)",
        CurrentValue = true,
        Flag = "AutoHaki",
        Callback = function(value)
            if self.config then self.config:Set("Combat", "AutoHaki", value) end
        end
    })

    AddElement(tab, "Section", {Name = "Timing"})

    AddElement(tab, "Slider", {
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
end

-- Populate Teleport Tab
function MainUI:PopulateTeleportTab(tab)
    AddElement(tab, "Section", {Name = "Island Teleport"})

    local islands = self:GetCurrentIslands()

    AddElement(tab, "Dropdown", {
        Name = "Select Island",
        Options = islands,
        CurrentOption = {},
        Flag = "SelectedIsland",
        Callback = function(option) end
    })

    AddElement(tab, "Button", {
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

    AddElement(tab, "Section", {Name = "Teleport Settings"})

    AddElement(tab, "Slider", {
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
end

-- Populate Fruit Tab
function MainUI:PopulateFruitTab(tab)
    AddElement(tab, "Section", {Name = "Collection"})

    AddElement(tab, "Toggle", {
        Name = "Auto Collect Fruits",
        CurrentValue = true,
        Flag = "AutoCollect",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "AutoCollect", value) end
        end
    })

    AddElement(tab, "Toggle", {
        Name = "Auto Store Fruits",
        CurrentValue = false,
        Flag = "AutoStore",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "AutoStore", value) end
            if self.fruitSniper then self.fruitSniper:SetAutoStore(value) end
        end
    })

    AddElement(tab, "Slider", {
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

    AddElement(tab, "Section", {Name = "Server Hop"})

    AddElement(tab, "Toggle", {
        Name = "Server Hop When No Fruits",
        CurrentValue = false,
        Flag = "ServerHopFruit",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "ServerHop", value) end
        end
    })

    AddElement(tab, "Section", {Name = "Fruit Filters"})

    AddElement(tab, "Toggle", {
        Name = "Only Mythical Fruits",
        CurrentValue = false,
        Flag = "OnlyMythical",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "OnlyMythical", value) end
        end
    })

    AddElement(tab, "Toggle", {
        Name = "Only Legendary+",
        CurrentValue = false,
        Flag = "OnlyLegendary",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "OnlyLegendary", value) end
        end
    })
end

-- Populate ESP Tab
function MainUI:PopulateESPTab(tab)
    AddElement(tab, "Section", {Name = "ESP Types"})

    AddElement(tab, "Toggle", {
        Name = "Fruit ESP",
        CurrentValue = true,
        Flag = "FruitESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "FruitESP", value) end
        end
    })

    AddElement(tab, "Toggle", {
        Name = "Player ESP",
        CurrentValue = false,
        Flag = "PlayerESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "PlayerESP", value) end
        end
    })

    AddElement(tab, "Toggle", {
        Name = "Boss ESP",
        CurrentValue = true,
        Flag = "BossESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "BossESP", value) end
        end
    })

    AddElement(tab, "Toggle", {
        Name = "Chest ESP",
        CurrentValue = false,
        Flag = "ChestESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "ChestESP", value) end
        end
    })

    AddElement(tab, "Section", {Name = "Display"})

    AddElement(tab, "Toggle", {
        Name = "Show Distance",
        CurrentValue = true,
        Flag = "ShowDistance",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "ShowDistance", value) end
        end
    })
end

-- Populate Settings Tab
function MainUI:PopulateSettingsTab(tab)
    AddElement(tab, "Section", {Name = "Keybinds"})

    AddElement(tab, "Keybind", {
        Name = "Toggle Auto Farm",
        CurrentKeybind = "U",
        Flag = "KeyAutoFarm",
        Callback = function()
            self:ToggleAutoFarm()
        end
    })

    AddElement(tab, "Keybind", {
        Name = "Toggle Fruit Sniper",
        CurrentKeybind = "I",
        Flag = "KeyFruitSniper",
        Callback = function()
            self:ToggleFruitSniper()
        end
    })

    AddElement(tab, "Keybind", {
        Name = "Toggle ESP",
        CurrentKeybind = "O",
        Flag = "KeyESP",
        Callback = function()
            self:ToggleESP()
        end
    })

    AddElement(tab, "Keybind", {
        Name = "Toggle UI",
        CurrentKeybind = "K",
        Flag = "KeyToggleUI",
        Callback = function()
            self:Toggle()
        end
    })

    AddElement(tab, "Section", {Name = "Utilities"})

    AddElement(tab, "Toggle", {
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

    AddElement(tab, "Toggle", {
        Name = "Full Bright",
        CurrentValue = false,
        Flag = "FullBright",
        Callback = function(value)
            if self.misc then self.misc:SetFullBright(value) end
        end
    })

    AddElement(tab, "Section", {Name = "Server"})

    AddElement(tab, "Button", {
        Name = "Server Hop",
        Callback = function()
            if self.misc then self.misc:ServerHop() end
        end
    })

    AddElement(tab, "Button", {
        Name = "Rejoin Server",
        Callback = function()
            if self.misc then self.misc:Rejoin() end
        end
    })

    AddElement(tab, "Section", {Name = "Config"})

    AddElement(tab, "Button", {
        Name = "Save Configuration",
        Callback = function()
            if self.config then
                self.config:Save()
                if self.misc then self.misc:Notify("Config", "Saved!") end
            end
        end
    })

    AddElement(tab, "Button", {
        Name = "Load Configuration",
        Callback = function()
            if self.config then
                self.config:Load()
                if self.misc then self.misc:Notify("Config", "Loaded!") end
            end
        end
    })

    AddElement(tab, "Section", {Name = "Info"})

    AddElement(tab, "Paragraph", {
        Title = "Anti-AFK",
        Content = "Anti-AFK is always enabled automatically."
    })

    AddElement(tab, "Paragraph", {
        Title = "Version",
        Content = "Blox Fruits Pro v" .. VERSION
    })
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
    elseif self.window and self.window.Visible ~= nil then
        self.window.Visible = not self.window.Visible
    elseif self.fallbackGui then
        self.fallbackGui.Enabled = not self.fallbackGui.Enabled
    end
end

-- Update status
function MainUI:UpdateStatus(status)
    if self.elements.statusParagraph and self.elements.statusParagraph.Set then
        pcall(function()
            self.elements.statusParagraph:Set({
                Title = "Current Status",
                Content = status or "Idle"
            })
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
        if self.window and self.window.Destroy then
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
