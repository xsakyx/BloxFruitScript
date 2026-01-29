--[[
    MainUI.lua
    User Interface using RenLib
    Complete UI with all features:
    - Weapon Type dropdown
    - Fly Height slider
    - Island Teleport
    - Auto Farm settings
    - ESP settings
    - Fruit Sniper with Auto Store
]]

local MainUI = {}
MainUI.__index = MainUI

local LIBRARY_URL = "https://raw.githubusercontent.com/xsakyx/RobloxUILib/refs/heads/main/RenLibBêta.lua"

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

-- Fallback UI
function MainUI:CreateFallbackUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BloxFruitScript"
    screenGui.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 300, 0, 150)
    frame.Position = UDim2.new(0.5, -150, 0.5, -75)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.Parent = screenGui

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    title.Text = "Blox Fruits Script"
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.Parent = frame

    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, -20, 0, 80)
    info.Position = UDim2.new(0, 10, 0, 40)
    info.BackgroundTransparency = 1
    info.Text = "UI Library failed.\nScript is still running.\nPress K to toggle."
    info.TextColor3 = Color3.fromRGB(255, 200, 200)
    info.Font = Enum.Font.Gotham
    info.TextSize = 12
    info.TextWrapped = true
    info.Parent = frame

    pcall(function()
        screenGui.Parent = game:GetService("CoreGui")
    end)

    if not screenGui.Parent then
        screenGui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    end

    self.fallbackGui = screenGui
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

-- Create window
function MainUI:CreateWindow()
    if not self.library then return false end

    self.window = self.library:CreateWindow({
        Name = "Blox Fruits Auto Farm",
        LoadingTitle = "Loading...",
        LoadingSubtitle = "by BloxFruit Script",
        ConfigurationSaving = {
            Enabled = true,
            FolderName = "BloxFruitScript",
            FileName = "UIConfig"
        }
    })

    self:CreateMainTab()
    self:CreateAutoFarmTab()
    self:CreateCombatTab()
    self:CreateTeleportTab()
    self:CreateFruitSniperTab()
    self:CreateESPTab()
    self:CreateMiscTab()

    return true
end

-- MAIN TAB
function MainUI:CreateMainTab()
    local tab = self.window:CreateTab({
        Name = "Main",
        Icon = "home"
    })
    self.tabs.main = tab

    tab:CreateSection("Quick Toggles")

    tab:CreateToggle({
        Name = "Enable Auto Farm",
        CurrentValue = false,
        Flag = "AutoFarm",
        Callback = function(value)
            if self.config then self.config:Set("General", "AutoFarm", value) end
            if self.autoFarm then
                if value then self.autoFarm:Start() else self.autoFarm:Stop() end
            end
        end
    })

    tab:CreateToggle({
        Name = "Enable Fruit Sniper",
        CurrentValue = false,
        Flag = "FruitSniper",
        Callback = function(value)
            if self.config then self.config:Set("General", "FruitSniper", value) end
            if self.fruitSniper then
                if value then self.fruitSniper:Start() else self.fruitSniper:Stop() end
            end
        end
    })

    tab:CreateToggle({
        Name = "Enable ESP",
        CurrentValue = false,
        Flag = "ESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "Enabled", value) end
            if self.esp then
                if value then self.esp:Start() else self.esp:Stop() end
            end
        end
    })

    tab:CreateSection("Status")

    self.elements.stats = tab:CreateParagraph({
        Title = "Player Stats",
        Content = "Level: 0 | Beli: 0 | Sea: 1"
    })
end

-- AUTO FARM TAB
function MainUI:CreateAutoFarmTab()
    local tab = self.window:CreateTab({
        Name = "Auto Farm",
        Icon = "target"
    })
    self.tabs.autoFarm = tab

    tab:CreateSection("Weapon Selection")

    -- WEAPON TYPE DROPDOWN
    tab:CreateDropdown({
        Name = "Select Weapon Type",
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

    tab:CreateSection("Farm Settings")

    -- FLY HEIGHT SLIDER
    tab:CreateSlider({
        Name = "Fly Height Above Mobs",
        Range = {5, 50},
        Increment = 1,
        CurrentValue = 15,
        Flag = "FlyHeight",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "FlyHeight", value) end
            if self.autoFarm then self.autoFarm:SetFlyHeight(value) end
        end
    })

    -- BRING MOBS TOGGLE
    tab:CreateToggle({
        Name = "Bring Mobs to Center",
        CurrentValue = true,
        Flag = "BringMobs",
        Callback = function(value)
            if self.config then self.config:Set("General", "BringMobs", value) end
        end
    })

    -- BRING DISTANCE SLIDER
    tab:CreateSlider({
        Name = "Bring Distance",
        Range = {50, 500},
        Increment = 10,
        CurrentValue = 150,
        Flag = "BringDistance",
        Callback = function(value)
            if self.config then self.config:Set("AutoFarm", "BringDistance", value) end
        end
    })

    tab:CreateSection("Info")

    tab:CreateParagraph({
        Title = "How It Works",
        Content = "1. Flies above mobs\n2. Brings them to center\n3. Anchors them in place\n4. Attacks continuously"
    })
end

-- COMBAT TAB
function MainUI:CreateCombatTab()
    local tab = self.window:CreateTab({
        Name = "Combat",
        Icon = "swords"
    })
    self.tabs.combat = tab

    tab:CreateSection("Attack Settings")

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

    tab:CreateSection("Info")

    tab:CreateParagraph({
        Title = "Combat System",
        Content = "Uses multiple methods:\n- Virtual clicks\n- Game remotes\n- Tool activation\n- Touch interest"
    })
end

-- TELEPORT TAB
function MainUI:CreateTeleportTab()
    local tab = self.window:CreateTab({
        Name = "Teleport",
        Icon = "navigation"
    })
    self.tabs.teleport = tab

    tab:CreateSection("Island Teleport")

    -- Get island list
    local islandList = {
        "Starter Island", "Marine Starter", "Jungle", "Pirate Village",
        "Desert", "Middle Town", "Frozen Village", "Marine Fortress",
        "Colosseum", "Magma Village", "Underwater City", "Fountain City"
    }

    if self.misc then
        local miscIslands = self.misc:GetIslandList()
        if #miscIslands > 0 then
            islandList = miscIslands
        end
    end

    -- ISLAND DROPDOWN
    tab:CreateDropdown({
        Name = "Select Island",
        Options = islandList,
        CurrentOption = {},
        Flag = "SelectedIsland",
        Callback = function(option)
            -- Stored for teleport button
        end
    })

    -- TELEPORT BUTTON
    tab:CreateButton({
        Name = "Teleport to Selected Island",
        Callback = function()
            if self.misc and self.window then
                local selected = self.window.Flags and self.window.Flags.SelectedIsland
                if selected then
                    local island = type(selected) == "table" and selected[1] or selected
                    self.misc:TeleportToIsland(island)
                end
            end
        end
    })

    tab:CreateSection("Tween Settings")

    tab:CreateSlider({
        Name = "Tween Speed",
        Range = {50, 500},
        Increment = 10,
        CurrentValue = 200,
        Flag = "TweenSpeed",
        Callback = function(value)
            if self.config then self.config:Set("Teleport", "TweenSpeed", value) end
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

    tab:CreateSection("Collection")

    tab:CreateToggle({
        Name = "Auto Collect Fruits",
        CurrentValue = true,
        Flag = "AutoCollect",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "AutoCollect", value) end
        end
    })

    -- AUTO STORE TOGGLE
    tab:CreateToggle({
        Name = "Auto Store Fruits",
        CurrentValue = false,
        Flag = "AutoStore",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "AutoStore", value) end
            if self.fruitSniper then self.fruitSniper:SetAutoStore(value) end
        end
    })

    tab:CreateToggle({
        Name = "Server Hop When No Fruits",
        CurrentValue = false,
        Flag = "ServerHopFruit",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "ServerHop", value) end
        end
    })

    tab:CreateSection("Fruit Filter")

    tab:CreateToggle({
        Name = "Only Mythical Fruits",
        CurrentValue = false,
        Flag = "OnlyMythical",
        Callback = function(value)
            if self.config then self.config:Set("FruitSniper", "OnlyMythical", value) end
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

    tab:CreateSection("ESP Types")

    tab:CreateToggle({
        Name = "Fruit ESP",
        CurrentValue = true,
        Flag = "FruitESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "FruitESP", value) end
        end
    })

    tab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = false,
        Flag = "PlayerESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "PlayerESP", value) end
        end
    })

    tab:CreateToggle({
        Name = "Boss ESP",
        CurrentValue = true,
        Flag = "BossESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "BossESP", value) end
        end
    })

    tab:CreateToggle({
        Name = "Chest ESP",
        CurrentValue = false,
        Flag = "ChestESP",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "ChestESP", value) end
        end
    })

    tab:CreateSection("Display")

    tab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = true,
        Flag = "ShowDistance",
        Callback = function(value)
            if self.config then self.config:Set("ESP", "ShowDistance", value) end
        end
    })

    tab:CreateSection("ESP Distances")

    tab:CreateParagraph({
        Title = "Detection Range",
        Content = "Fruit: 10000 studs\nBoss: 5000 studs\nPlayer: 2000 studs\nChest: 1000 studs"
    })
end

-- MISC TAB
function MainUI:CreateMiscTab()
    local tab = self.window:CreateTab({
        Name = "Misc",
        Icon = "settings"
    })
    self.tabs.misc = tab

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

    tab:CreateSection("Info")

    tab:CreateParagraph({
        Title = "Anti-AFK",
        Content = "Anti-AFK is always enabled automatically."
    })

    tab:CreateSection("Config")

    tab:CreateButton({
        Name = "Save Config",
        Callback = function()
            if self.config then
                self.config:Save()
                if self.misc then self.misc:Notify("Config", "Saved!") end
            end
        end
    })

    tab:CreateButton({
        Name = "Load Config",
        Callback = function()
            if self.config then
                self.config:Load()
                if self.misc then self.misc:Notify("Config", "Loaded!") end
            end
        end
    })

    tab:CreateSection("UI")

    tab:CreateKeybind({
        Name = "Toggle UI Key",
        CurrentKeybind = "K",
        Flag = "ToggleUI",
        Callback = function()
            if self.window then self.window:Toggle() end
        end
    })
end

-- Toggle window
function MainUI:Toggle()
    if self.window then
        self.window:Toggle()
    elseif self.fallbackGui then
        self.fallbackGui.Enabled = not self.fallbackGui.Enabled
    end
end

-- Update stats
function MainUI:UpdateStats(stats)
    if self.elements.stats then
        pcall(function()
            self.elements.stats:Set({
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
