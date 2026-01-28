--[[
    MainUI.lua
    User Interface using RenLib
    Provides controls for all script features
]]

local MainUI = {}
MainUI.__index = MainUI

-- UI Library URL (RenLib or alternative)
local LIBRARY_URL = "https://raw.githubusercontent.com/idk123456789012345678/ren/refs/heads/main/lib"

function MainUI.new()
    local self = setmetatable({}, MainUI)

    self.library = nil
    self.window = nil
    self.tabs = {}
    self.elements = {}
    self.callbacks = {}

    -- Module references (injected later)
    self.config = nil
    self.autoFarm = nil
    self.fruitSniper = nil
    self.combat = nil
    self.esp = nil
    self.misc = nil
    self.teleport = nil

    return self
end

-- Initialize UI library
function MainUI:LoadLibrary()
    local success, library = pcall(function()
        return loadstring(game:HttpGet(LIBRARY_URL))()
    end)

    if success and library then
        self.library = library
        return true
    else
        warn("[MainUI] Failed to load UI library:", library)
        -- Create fallback simple UI
        return self:CreateFallbackUI()
    end
end

-- Create fallback UI if library fails to load
function MainUI:CreateFallbackUI()
    -- Simple screen GUI fallback
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BloxFruitScript"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local frame = Instance.new("Frame")
    frame.Name = "MainFrame"
    frame.Size = UDim2.new(0, 400, 0, 300)
    frame.Position = UDim2.new(0.5, -200, 0.5, -150)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BorderSizePixel = 0
    frame.Parent = screenGui

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    title.BorderSizePixel = 0
    title.Text = "Blox Fruits Script"
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.Parent = frame

    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(1, -20, 0, 50)
    infoLabel.Position = UDim2.new(0, 10, 0, 50)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Text = "UI Library failed to load.\nPlease check your executor.\nScript features are still functional."
    infoLabel.TextColor3 = Color3.fromRGB(255, 200, 200)
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextSize = 14
    infoLabel.TextWrapped = true
    infoLabel.Parent = frame

    -- Protect GUI
    pcall(function()
        screenGui.Parent = game:GetService("CoreGui")
    end)

    if not screenGui.Parent then
        screenGui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    end

    self.fallbackGui = screenGui
    return false
end

-- Inject module dependencies
function MainUI:SetModules(modules)
    self.config = modules.config
    self.autoFarm = modules.autoFarm
    self.fruitSniper = modules.fruitSniper
    self.combat = modules.combat
    self.esp = modules.esp
    self.misc = modules.misc
    self.teleport = modules.teleport
end

-- Create the main window
function MainUI:CreateWindow()
    if not self.library then
        warn("[MainUI] Library not loaded")
        return false
    end

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

    -- Create tabs
    self:CreateMainTab()
    self:CreateFarmTab()
    self:CreateCombatTab()
    self:CreateTeleportTab()
    self:CreateMiscTab()
    self:CreateSettingsTab()

    return true
end

-- Create Main Tab
function MainUI:CreateMainTab()
    local tab = self.window:CreateTab({
        Name = "Main",
        Icon = "home"
    })
    self.tabs.main = tab

    -- Status Section
    local statusSection = tab:CreateSection("Status")

    -- Auto Farm Toggle
    tab:CreateToggle({
        Name = "Auto Farm",
        CurrentValue = false,
        Flag = "AutoFarm",
        Callback = function(value)
            if self.config then
                self.config:Set("General", "AutoFarm", value)
            end
            if self.autoFarm then
                if value then
                    self.autoFarm:Start()
                else
                    self.autoFarm:Stop()
                end
            end
            if self.callbacks.onAutoFarmToggle then
                self.callbacks.onAutoFarmToggle(value)
            end
        end
    })

    -- Fruit Sniper Toggle
    tab:CreateToggle({
        Name = "Fruit Sniper",
        CurrentValue = false,
        Flag = "FruitSniper",
        Callback = function(value)
            if self.config then
                self.config:Set("General", "FruitSniper", value)
            end
            if self.fruitSniper then
                if value then
                    self.fruitSniper:Start()
                else
                    self.fruitSniper:Stop()
                end
            end
        end
    })

    -- ESP Toggle
    tab:CreateToggle({
        Name = "ESP",
        CurrentValue = false,
        Flag = "ESP",
        Callback = function(value)
            if self.config then
                self.config:Set("ESP", "Enabled", value)
            end
            if self.esp then
                if value then
                    self.esp:Start()
                else
                    self.esp:Stop()
                end
            end
        end
    })

    -- Stats Display
    tab:CreateParagraph({
        Title = "Player Stats",
        Content = "Level: 0 | Beli: 0 | Sea: 1"
    })
end

-- Create Farm Tab
function MainUI:CreateFarmTab()
    local tab = self.window:CreateTab({
        Name = "Farm",
        Icon = "target"
    })
    self.tabs.farm = tab

    -- Quest Settings Section
    local questSection = tab:CreateSection("Quest Settings")

    tab:CreateToggle({
        Name = "Auto Select Quest",
        CurrentValue = true,
        Flag = "AutoSelectQuest",
        Callback = function(value)
            if self.config then
                self.config:Set("Quest", "AutoSelectQuest", value)
            end
        end
    })

    tab:CreateToggle({
        Name = "Skip Bosses",
        CurrentValue = false,
        Flag = "SkipBosses",
        Callback = function(value)
            if self.config then
                self.config:Set("Quest", "SkipBosses", value)
            end
        end
    })

    tab:CreateToggle({
        Name = "Bring Mobs",
        CurrentValue = true,
        Flag = "BringMobs",
        Callback = function(value)
            if self.config then
                self.config:Set("General", "BringMobs", value)
            end
        end
    })

    tab:CreateSlider({
        Name = "Bring Distance",
        Range = {20, 200},
        Increment = 5,
        CurrentValue = 80,
        Flag = "BringDistance",
        Callback = function(value)
            if self.config then
                self.config:Set("General", "BringDistance", value)
            end
        end
    })

    -- Mastery Section
    local masterySection = tab:CreateSection("Mastery Farm")

    tab:CreateToggle({
        Name = "Mastery Farm",
        CurrentValue = false,
        Flag = "MasteryFarm",
        Callback = function(value)
            if self.config then
                self.config:Set("General", "MasteryFarm", value)
            end
        end
    })

    tab:CreateSlider({
        Name = "Target Mastery",
        Range = {1, 600},
        Increment = 1,
        CurrentValue = 600,
        Flag = "TargetMastery",
        Callback = function(value)
            if self.config then
                self.config:Set("Mastery", "TargetMastery", value)
            end
        end
    })
end

-- Create Combat Tab
function MainUI:CreateCombatTab()
    local tab = self.window:CreateTab({
        Name = "Combat",
        Icon = "swords"
    })
    self.tabs.combat = tab

    local combatSection = tab:CreateSection("Combat Settings")

    tab:CreateToggle({
        Name = "Auto Attack",
        CurrentValue = true,
        Flag = "AutoAttack",
        Callback = function(value)
            if self.config then
                self.config:Set("Combat", "AutoAttack", value)
            end
        end
    })

    tab:CreateToggle({
        Name = "Auto Skills",
        CurrentValue = true,
        Flag = "AutoSkills",
        Callback = function(value)
            if self.config then
                self.config:Set("Combat", "AutoSkills", value)
            end
        end
    })

    tab:CreateToggle({
        Name = "Auto Haki",
        CurrentValue = true,
        Flag = "AutoHaki",
        Callback = function(value)
            if self.config then
                self.config:Set("Combat", "AutoHaki", value)
            end
        end
    })

    -- Skill toggles
    local skillsSection = tab:CreateSection("Skills")

    for _, key in ipairs({"Z", "X", "C", "V", "F"}) do
        tab:CreateToggle({
            Name = "Use " .. key .. " Skill",
            CurrentValue = key == "Z" or key == "X",
            Flag = "Skill" .. key,
            Callback = function(value)
                if self.config then
                    local skills = self.config:Get("Combat", "SkillsEnabled") or {}
                    skills[key] = value
                    self.config:Set("Combat", "SkillsEnabled", skills)
                end
            end
        })
    end
end

-- Create Teleport Tab
function MainUI:CreateTeleportTab()
    local tab = self.window:CreateTab({
        Name = "Teleport",
        Icon = "navigation"
    })
    self.tabs.teleport = tab

    local tpSection = tab:CreateSection("Teleport Settings")

    tab:CreateSlider({
        Name = "Tween Speed",
        Range = {50, 500},
        Increment = 10,
        CurrentValue = 200,
        Flag = "TweenSpeed",
        Callback = function(value)
            if self.config then
                self.config:Set("Teleport", "TweenSpeed", value)
            end
        end
    })

    tab:CreateToggle({
        Name = "Bypass Walls",
        CurrentValue = true,
        Flag = "BypassWalls",
        Callback = function(value)
            if self.config then
                self.config:Set("Teleport", "BypassWalls", value)
            end
        end
    })

    -- Sea travel
    local seaSection = tab:CreateSection("Sea Travel")

    tab:CreateButton({
        Name = "Travel to Sea 1",
        Callback = function()
            if self.misc then
                self.misc:TravelToSea(1)
            end
        end
    })

    tab:CreateButton({
        Name = "Travel to Sea 2",
        Callback = function()
            if self.misc then
                self.misc:TravelToSea(2)
            end
        end
    })

    tab:CreateButton({
        Name = "Travel to Sea 3",
        Callback = function()
            if self.misc then
                self.misc:TravelToSea(3)
            end
        end
    })
end

-- Create Misc Tab
function MainUI:CreateMiscTab()
    local tab = self.window:CreateTab({
        Name = "Misc",
        Icon = "settings"
    })
    self.tabs.misc = tab

    local miscSection = tab:CreateSection("Utilities")

    tab:CreateToggle({
        Name = "Anti-AFK",
        CurrentValue = true,
        Flag = "AntiAFK",
        Callback = function(value)
            if self.config then
                self.config:Set("Misc", "AntiAFK", value)
            end
            if self.misc then
                if value then
                    self.misc:StartAntiAFK()
                else
                    self.misc:StopAntiAFK()
                end
            end
        end
    })

    tab:CreateToggle({
        Name = "Auto Rejoin",
        CurrentValue = true,
        Flag = "AutoRejoin",
        Callback = function(value)
            if self.config then
                self.config:Set("Misc", "AutoRejoin", value)
            end
            if self.misc then
                if value then
                    self.misc:StartAutoRejoin()
                else
                    self.misc:StopAutoRejoin()
                end
            end
        end
    })

    tab:CreateToggle({
        Name = "No Clip",
        CurrentValue = false,
        Flag = "NoClip",
        Callback = function(value)
            if self.config then
                self.config:Set("Misc", "NoClip", value)
            end
            if self.misc then
                if value then
                    self.misc:StartNoClip()
                else
                    self.misc:StopNoClip()
                end
            end
        end
    })

    -- ESP Section
    local espSection = tab:CreateSection("ESP Settings")

    tab:CreateToggle({
        Name = "Fruit ESP",
        CurrentValue = true,
        Flag = "FruitESP",
        Callback = function(value)
            if self.config then
                self.config:Set("ESP", "FruitESP", value)
            end
        end
    })

    tab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = false,
        Flag = "PlayerESP",
        Callback = function(value)
            if self.config then
                self.config:Set("ESP", "PlayerESP", value)
            end
        end
    })

    tab:CreateToggle({
        Name = "Mob ESP",
        CurrentValue = false,
        Flag = "MobESP",
        Callback = function(value)
            if self.config then
                self.config:Set("ESP", "MobESP", value)
            end
        end
    })

    tab:CreateToggle({
        Name = "Boss ESP",
        CurrentValue = true,
        Flag = "BossESP",
        Callback = function(value)
            if self.config then
                self.config:Set("ESP", "BossESP", value)
            end
        end
    })

    tab:CreateToggle({
        Name = "Chest ESP",
        CurrentValue = false,
        Flag = "ChestESP",
        Callback = function(value)
            if self.config then
                self.config:Set("ESP", "ChestESP", value)
            end
        end
    })

    -- Buttons
    local actionsSection = tab:CreateSection("Actions")

    tab:CreateButton({
        Name = "Server Hop",
        Callback = function()
            if self.misc then
                self.misc:ServerHop()
            end
        end
    })

    tab:CreateButton({
        Name = "Rejoin Server",
        Callback = function()
            if self.misc then
                self.misc:Rejoin()
            end
        end
    })

    tab:CreateButton({
        Name = "Reset Character",
        Callback = function()
            if self.misc then
                self.misc:ResetCharacter()
            end
        end
    })
end

-- Create Settings Tab
function MainUI:CreateSettingsTab()
    local tab = self.window:CreateTab({
        Name = "Settings",
        Icon = "cog"
    })
    self.tabs.settings = tab

    local configSection = tab:CreateSection("Configuration")

    tab:CreateButton({
        Name = "Save Config",
        Callback = function()
            if self.config then
                local success = self.config:Save()
                if self.misc then
                    self.misc:Notify("Config", success and "Config saved!" or "Failed to save config")
                end
            end
        end
    })

    tab:CreateButton({
        Name = "Load Config",
        Callback = function()
            if self.config then
                local success = self.config:Load()
                if self.misc then
                    self.misc:Notify("Config", success and "Config loaded!" or "Failed to load config")
                end
            end
        end
    })

    tab:CreateButton({
        Name = "Reset to Default",
        Callback = function()
            if self.config then
                self.config:ResetToDefault()
                if self.misc then
                    self.misc:Notify("Config", "Config reset to default")
                end
            end
        end
    })

    -- UI Settings
    local uiSection = tab:CreateSection("UI Settings")

    tab:CreateKeybind({
        Name = "Toggle UI",
        CurrentKeybind = "RightControl",
        Flag = "ToggleUI",
        Callback = function()
            if self.window then
                self.window:Toggle()
            end
        end
    })
end

-- Show/Hide window
function MainUI:Toggle()
    if self.window then
        self.window:Toggle()
    elseif self.fallbackGui then
        self.fallbackGui.Enabled = not self.fallbackGui.Enabled
    end
end

-- Update stats display
function MainUI:UpdateStats(stats)
    if not self.tabs.main then return end

    local content = string.format(
        "Level: %d | Beli: %s | Sea: %d\nFragments: %d | Bounty: %s",
        stats.Level or 0,
        tostring(stats.Beli or 0),
        stats.CurrentSea or 1,
        stats.Fragments or 0,
        tostring(stats.Bounty or 0)
    )

    -- Update paragraph if it exists
    -- (This would need the element reference stored)
end

-- Set callback
function MainUI:OnToggle(name, callback)
    self.callbacks["on" .. name .. "Toggle"] = callback
end

-- Initialize and show UI
function MainUI:Init()
    if self:LoadLibrary() then
        self:CreateWindow()
    end
end

-- Cleanup
function MainUI:Destroy()
    if self.window then
        self.window:Destroy()
    end

    if self.fallbackGui then
        self.fallbackGui:Destroy()
    end

    self.callbacks = {}
end

return {
    new = MainUI.new
}
