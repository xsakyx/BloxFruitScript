-- BlackHub Fisch - clean-room reconstruction (phase 1)
-- No key system, no telemetry, no external UI library.
-- Import this file into your executor and run it after joining Fisch.

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
local old = env.__BLACKHUB_RECONSTRUCTED
if type(old) == "table" and type(old.Unload) == "function" then
    pcall(old.Unload)
end

local Runtime = {alive = true, connections = {}, version = "1.0.0-phase1"}
env.__BLACKHUB_RECONSTRUCTED = Runtime

local ROOT = "BlackHubReconstructed"
local CONFIG_FILE = ROOT .. "/config.json"
local LOG_FILE = ROOT .. "/diagnostics.txt"

local defaults = {
    autoFish = false,
    autoEquip = true,
    autoCast = true,
    autoShake = true,
    instantReel = true,
    autoSell = false,
    antiAfk = true,
    zoneCasting = false,
    walkSpeedToggle = false,
    walkSpeedValue = 32,
    jumpPowerToggle = false,
    jumpPowerValue = 75,
    flyToggle = false,
    flySpeed = 45,
    freezePosition = false,
    disableRendering = false,
    castPower = 100,
    castInterval = 12,
    reelDelay = 0.15,
    sellInterval = 300,
    savedZone = nil,
}

local State = {}
for key, value in pairs(defaults) do State[key] = value end

local function ensureFolder()
    if type(makefolder) ~= "function" or type(isfolder) ~= "function" then return end
    if not isfolder(ROOT) then pcall(makefolder, ROOT) end
end

local logLines = {}
local function log(message)
    local line = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(message))
    table.insert(logLines, line)
    if #logLines > 250 then table.remove(logLines, 1) end
    warn("[BH-R] " .. tostring(message))
    if type(writefile) == "function" then
        ensureFolder()
        pcall(writefile, LOG_FILE, table.concat(logLines, "\n"))
    end
end

local function saveConfig()
    if type(writefile) ~= "function" then return end
    ensureFolder()
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, State)
    if ok then pcall(writefile, CONFIG_FILE, encoded) end
end

local function loadConfig()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return end
    ensureFolder()
    if not isfile(CONFIG_FILE) then return end
    local okRead, raw = pcall(readfile, CONFIG_FILE)
    if not okRead then return end
    local okJson, saved = pcall(HttpService.JSONDecode, HttpService, raw)
    if not okJson or type(saved) ~= "table" then return end
    for key, default in pairs(defaults) do
        if saved[key] ~= nil and typeof(saved[key]) == typeof(default) then
            State[key] = saved[key]
        end
    end
    if type(saved.savedZone) == "table" then State.savedZone = saved.savedZone end
end

loadConfig()

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Runtime.connections, connection)
    return connection
end

local function normalize(value)
    return string.lower(tostring(value)):gsub("[^%w]", "")
end

local function fullName(instance)
    local ok, value = pcall(instance.GetFullName, instance)
    return ok and value or tostring(instance)
end

local remoteCache = {}
local function findRemote(names, allowContains)
    local wanted = {}
    for _, name in ipairs(names) do wanted[normalize(name)] = true end
    local cacheKey = table.concat(names, "|") .. tostring(allowContains)
    local cached = remoteCache[cacheKey]
    if cached and cached.Parent then return cached end

    local partial
    for _, item in ipairs(ReplicatedStorage:GetDescendants()) do
        if item:IsA("RemoteEvent") or item:IsA("RemoteFunction") then
            local n = normalize(item.Name)
            if wanted[n] then
                remoteCache[cacheKey] = item
                log("resolved remote: " .. fullName(item))
                return item
            end
            if allowContains and not partial then
                for candidate in pairs(wanted) do
                    if string.find(n, candidate, 1, true) then partial = item break end
                end
            end
        end
    end
    if partial then
        remoteCache[cacheKey] = partial
        log("resolved partial remote: " .. fullName(partial))
    end
    return partial
end

local function callRemote(remote, ...)
    if not remote then return false, "remote not found" end
    local args = table.pack(...)
    local ok, result = pcall(function()
        if remote:IsA("RemoteEvent") then
            remote:FireServer(table.unpack(args, 1, args.n))
            return true
        end
        remote:InvokeServer(table.unpack(args, 1, args.n))
        return true
    end)
    return ok, result
end

local function character()
    return player.Character
end

local function humanoid()
    local char = character()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function isRod(tool)
    if not tool or not tool:IsA("Tool") then return false end
    for _, item in ipairs(tool:GetDescendants()) do
        if (item:IsA("RemoteEvent") or item:IsA("RemoteFunction")) and normalize(item.Name) == "cast" then
            return true
        end
    end
    local n = normalize(tool.Name)
    return string.find(n, "rod", 1, true) ~= nil
end

local function equippedRod()
    local char = character()
    if not char then return nil end
    for _, child in ipairs(char:GetChildren()) do
        if isRod(child) then return child end
    end
end

local function backpackRod()
    local backpack = player:FindFirstChildOfClass("Backpack")
    if not backpack then return nil end
    local fallback
    for _, child in ipairs(backpack:GetChildren()) do
        if child:IsA("Tool") then
            if isRod(child) then return child end
            fallback = fallback or child
        end
    end
    return fallback
end

local function equipRod()
    local rod = equippedRod()
    if rod then return rod end
    rod = backpackRod()
    local hum = humanoid()
    if rod and hum then
        local ok = pcall(hum.EquipTool, hum, rod)
        if ok then
            log("equipped: " .. rod.Name)
            task.wait(0.2)
            return equippedRod() or rod
        end
    end
    return nil
end

local function findCastRemote(rod)
    if not rod then return nil end
    for _, item in ipairs(rod:GetDescendants()) do
        if (item:IsA("RemoteEvent") or item:IsA("RemoteFunction")) and normalize(item.Name) == "cast" then
            return item
        end
    end
end

local function hasBobber(rod)
    if not rod then return false end
    for _, item in ipairs(rod:GetDescendants()) do
        local n = normalize(item.Name)
        if n == "bobber" or n == "float" then return true end
    end
    local char = character()
    if char then
        for _, item in ipairs(char:GetDescendants()) do
            if normalize(item.Name) == "bobber" then return true end
        end
    end
    return false
end

local function cast()
    local rod = equippedRod() or (State.autoEquip and equipRod())
    if not rod then return false, "no rod found" end
    local remote = findCastRemote(rod)
    if remote then
        local ok, err = callRemote(remote, State.castPower)
        if ok then return true end
        return false, err
    end
    local ok, err = pcall(rod.Activate, rod)
    return ok, err
end

local function visibleGuiNamed(fragment)
    local gui = player:FindFirstChildOfClass("PlayerGui")
    if not gui then return nil end
    fragment = normalize(fragment)
    for _, item in ipairs(gui:GetDescendants()) do
        if (item:IsA("GuiObject") or item:IsA("LayerCollector")) and string.find(normalize(item.Name), fragment, 1, true) then
            local visible = true
            if item:IsA("GuiObject") then visible = item.Visible end
            if item:IsA("LayerCollector") then visible = item.Enabled end
            if visible then return item end
        end
    end
end

local function shakeButton()
    local gui = player:FindFirstChildOfClass("PlayerGui")
    if not gui then return nil end
    local shakeRoot = visibleGuiNamed("shake")
    if not shakeRoot then return nil end
    if shakeRoot:IsA("GuiButton") and shakeRoot.Visible then return shakeRoot end
    for _, item in ipairs(shakeRoot:GetDescendants()) do
        if item:IsA("GuiButton") and item.Visible then return item end
    end
end

local function clickGuiButton(button)
    if not button then return false end
    if type(firesignal) == "function" then
        local ok = pcall(function()
            firesignal(button.Activated)
            firesignal(button.MouseButton1Click)
        end)
        if ok then return true end
    end
    local ok = pcall(function()
        GuiService.SelectedObject = button
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
        GuiService.SelectedObject = nil
    end)
    if ok then return true end
    local center = button.AbsolutePosition + (button.AbsoluteSize / 2)
    return pcall(function()
        VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
        VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
    end)
end

local function reelVisible()
    return visibleGuiNamed("reel") ~= nil
end

local function finishReel()
    local remote = findRemote({"reelfinished", "ReelFinished", "reel_finished", "reelfinished "}, false)
    if not remote then return false, "ReelFinished remote not found" end
    return callRemote(remote, 100, true)
end

local function sellAll()
    -- Deliberately require a sell-all name. Calling an arbitrary 'sell' remote can sell the held item.
    local remote = findRemote({"sellall", "SellAll", "sellallfish", "SellAllFish", "sellallitems", "SellAllItems"}, true)
    if not remote then return false, "sell-all remote not found" end
    return callRemote(remote)
end

local function rootPart()
    local char = character()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function saveZone()
    local root = rootPart()
    if not root then return false end
    local p = root.Position
    local l = root.CFrame.LookVector
    State.savedZone = {p.X, p.Y, p.Z, l.X, l.Y, l.Z}
    saveConfig()
    log(string.format("saved zone at %.1f, %.1f, %.1f", p.X, p.Y, p.Z))
    return true
end

local function teleportSavedZone()
    local data = State.savedZone
    local root = rootPart()
    if not root or type(data) ~= "table" or #data < 6 then return false end
    local position = Vector3.new(data[1], data[2], data[3])
    local look = Vector3.new(data[4], data[5], data[6])
    root.CFrame = CFrame.lookAt(position, position + look)
    return true
end

local function savedZoneCFrame()
    local data = State.savedZone
    if type(data) ~= "table" or #data < 6 then return nil end
    local position = Vector3.new(data[1], data[2], data[3])
    local look = Vector3.new(data[4], data[5], data[6])
    return CFrame.lookAt(position, position + look)
end

local function moveBobberToSavedZone(rod)
    local target = savedZoneCFrame()
    if not target then return false, "save a zone position first" end
    local root = rootPart()
    local best, bestDistance
    local function consider(item)
        if not item:IsA("BasePart") then return end
        local n = normalize(item.Name)
        if n ~= "bobber" and n ~= "float" then return end
        local distance = root and (item.Position - root.Position).Magnitude or 0
        if not bestDistance or distance < bestDistance then best, bestDistance = item, distance end
    end
    if rod then
        for _, item in ipairs(rod:GetDescendants()) do consider(item) end
    end
    if not best then
        for _, item in ipairs(workspace:GetDescendants()) do consider(item) end
    end
    if not best then return false, "bobber not found" end
    local ok, err = pcall(function()
        best.AssemblyLinearVelocity = Vector3.zero
        best.CFrame = target + Vector3.new(0, -2, 0)
    end)
    return ok, err
end

-- Small standalone UI: no remote loadstring and no UI-library dependency.
local uiParent = CoreGui
if type(gethui) == "function" then
    local ok, result = pcall(gethui)
    if ok and result then uiParent = result end
end

local gui = Instance.new("ScreenGui")
gui.Name = "BlackHubReconstructed"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
    if type(protectgui) == "function" then protectgui(gui) end
    gui.Parent = uiParent
end)
if not gui.Parent then gui.Parent = player:WaitForChild("PlayerGui") end

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(430, 470)
panel.Position = UDim2.new(0.5, -215, 0.5, -235)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 27)
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(78, 93, 145)
stroke.Thickness = 1
stroke.Parent = panel

local top = Instance.new("TextButton")
top.AutoButtonColor = false
top.Text = "  BlackHub Reconstruction  •  Fisch"
top.TextXAlignment = Enum.TextXAlignment.Left
top.Font = Enum.Font.GothamBold
top.TextSize = 16
top.TextColor3 = Color3.fromRGB(235, 238, 250)
top.BackgroundColor3 = Color3.fromRGB(27, 31, 43)
top.BorderSizePixel = 0
top.Size = UDim2.new(1, 0, 0, 42)
top.Parent = panel
Instance.new("UICorner", top).CornerRadius = UDim.new(0, 10)

local close = Instance.new("TextButton")
close.Text = "×"
close.Font = Enum.Font.GothamBold
close.TextSize = 23
close.TextColor3 = Color3.fromRGB(255, 145, 145)
close.BackgroundTransparency = 1
close.Size = UDim2.fromOffset(42, 42)
close.Position = UDim2.new(1, -42, 0, 0)
close.Parent = panel

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Text = "Ready"
status.TextXAlignment = Enum.TextXAlignment.Left
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(153, 164, 194)
status.Position = UDim2.fromOffset(14, 438)
status.Size = UDim2.new(1, -28, 0, 22)
status.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.Position = UDim2.fromOffset(10, 52)
scroll.Size = UDim2.new(1, -20, 0, 380)
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = Color3.fromRGB(93, 117, 190)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = scroll

local function setStatus(text)
    status.Text = tostring(text)
end

local function addLabel(text, height)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.GothamSemibold
    label.TextSize = 13
    label.TextColor3 = Color3.fromRGB(180, 189, 219)
    label.Size = UDim2.new(1, -8, 0, height or 24)
    label.Parent = scroll
    return label
end

local function addButton(text, callback)
    local button = Instance.new("TextButton")
    button.Text = text
    button.Font = Enum.Font.GothamSemibold
    button.TextSize = 13
    button.TextColor3 = Color3.fromRGB(232, 235, 245)
    button.BackgroundColor3 = Color3.fromRGB(42, 48, 66)
    button.BorderSizePixel = 0
    button.Size = UDim2.new(1, -8, 0, 34)
    button.Parent = scroll
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)
    connect(button.MouseButton1Click, function()
        local ok, result = pcall(callback)
        if not ok then log(text .. " failed: " .. tostring(result)); setStatus("Error: " .. tostring(result)) end
    end)
    return button
end

local toggleRefresh = {}
local function addToggle(key, text)
    local button = addButton("", function()
        State[key] = not State[key]
        saveConfig()
        toggleRefresh[key]()
        setStatus(text .. ": " .. (State[key] and "ON" or "OFF"))
    end)
    local function refresh()
        button.Text = (State[key] and "[ ON ]  " or "[ OFF ] ") .. text
        button.BackgroundColor3 = State[key] and Color3.fromRGB(50, 82, 78) or Color3.fromRGB(42, 48, 66)
    end
    toggleRefresh[key] = refresh
    refresh()
end

local function addNumber(key, text, minimum, maximum)
    local row = Instance.new("Frame")
    row.BackgroundColor3 = Color3.fromRGB(31, 35, 48)
    row.BorderSizePixel = 0
    row.Size = UDim2.new(1, -8, 0, 36)
    row.Parent = scroll
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Text = "  " .. text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.Gotham
    label.TextSize = 13
    label.TextColor3 = Color3.fromRGB(220, 224, 238)
    label.Size = UDim2.new(1, -100, 1, 0)
    label.Parent = row
    local box = Instance.new("TextBox")
    box.Text = tostring(State[key])
    box.ClearTextOnFocus = false
    box.Font = Enum.Font.Code
    box.TextSize = 13
    box.TextColor3 = Color3.fromRGB(220, 230, 255)
    box.BackgroundColor3 = Color3.fromRGB(22, 25, 35)
    box.BorderSizePixel = 0
    box.Position = UDim2.new(1, -90, 0, 4)
    box.Size = UDim2.fromOffset(82, 28)
    box.Parent = row
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5)
    connect(box.FocusLost, function()
        local value = tonumber(box.Text) or State[key]
        State[key] = math.clamp(value, minimum, maximum)
        box.Text = tostring(State[key])
        saveConfig()
    end)
end

addLabel("CORE FISHING")
addToggle("autoFish", "Master Auto Fish")
addToggle("autoEquip", "Auto Equip Rod")
addToggle("autoCast", "Auto Cast")
addToggle("autoShake", "Auto Shake")
addToggle("instantReel", "Instant Reel")
addToggle("zoneCasting", "Zone Casting (uses saved position)")
addNumber("castPower", "Cast power", 1, 100)
addNumber("castInterval", "Recast timeout (seconds)", 3, 60)
addNumber("reelDelay", "Reel delay (seconds)", 0, 5)

addLabel("SELLING")
addToggle("autoSell", "Auto Sell All")
addNumber("sellInterval", "Sell interval (seconds)", 30, 3600)
addButton("Sell All Now", function()
    local ok, err = sellAll()
    setStatus(ok and "Sell-all request sent" or tostring(err))
    if not ok then log("sell failed: " .. tostring(err)) end
end)

addLabel("POSITION / ZONE")
addButton("Save Current Position", function()
    setStatus(saveZone() and "Zone position saved" or "Character not ready")
end)
addButton("Teleport To Saved Position", function()
    setStatus(teleportSavedZone() and "Teleported" or "No saved position")
end)

addLabel("PLAYER")
addToggle("walkSpeedToggle", "Walk Speed")
addNumber("walkSpeedValue", "Walk speed value", 16, 250)
addToggle("jumpPowerToggle", "Jump Power")
addNumber("jumpPowerValue", "Jump power value", 50, 250)
addToggle("flyToggle", "Fly")
addNumber("flySpeed", "Fly speed", 10, 250)
addToggle("freezePosition", "Freeze Position")
addToggle("disableRendering", "Disable 3D Rendering")

addLabel("RUNTIME")
addToggle("antiAfk", "Anti AFK")
addButton("Run Diagnostics", function()
    remoteCache = {}
    local rod = equippedRod() or backpackRod()
    log("version: " .. Runtime.version)
    log("place id: " .. tostring(game.PlaceId))
    log("executor: " .. tostring(identifyexecutor and identifyexecutor() or "unknown"))
    log("rod: " .. (rod and fullName(rod) or "not found"))
    log("cast remote: " .. (findCastRemote(rod) and fullName(findCastRemote(rod)) or "not found"))
    log("reel remote: " .. (findRemote({"reelfinished", "ReelFinished", "reel_finished"}, false) and "found" or "not found"))
    log("sell-all remote: " .. (findRemote({"sellall", "SellAll", "sellallfish", "SellAllFish", "sellallitems", "SellAllItems"}, true) and "found" or "not found"))
    setStatus("Diagnostics written to " .. LOG_FILE)
end)
addButton("Unload", function() Runtime.Unload() end)

-- Dragging works with touch and mouse.
local dragging, dragStart, startPosition
local modifiedHumanoids = setmetatable({}, {__mode = "k"})
local flightVelocity
local flightGyro
local wasFrozen = false
local frozenRoot
local frozenRootWasAnchored = false
local renderingDisabled = false
local removeFlight
connect(top.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPosition = panel.Position
    end
end)
connect(UserInputService.InputChanged, function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        panel.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
    end
end)
connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
end)

function Runtime.Unload()
    if not Runtime.alive then return end
    Runtime.alive = false
    saveConfig()
    for _, connection in ipairs(Runtime.connections) do pcall(connection.Disconnect, connection) end
    table.clear(Runtime.connections)
    for hum, original in pairs(modifiedHumanoids or {}) do
        if hum and hum.Parent then
            pcall(function() hum.WalkSpeed = original.walkSpeed; hum.JumpPower = original.jumpPower end)
        end
    end
    removeFlight()
    if frozenRoot and frozenRoot.Parent and wasFrozen then
        pcall(function() frozenRoot.Anchored = frozenRootWasAnchored end)
    end
    if renderingDisabled then pcall(RunService.Set3dRenderingEnabled, RunService, true) end
    if gui then pcall(gui.Destroy, gui) end
    if env.__BLACKHUB_RECONSTRUCTED == Runtime then env.__BLACKHUB_RECONSTRUCTED = nil end
    warn("[BH-R] unloaded")
end

connect(close.MouseButton1Click, Runtime.Unload)
connect(player.Idled, function()
    if not Runtime.alive or not State.antiAfk then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(0.1)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
end)

local nextCast = 0
local lastReel = 0
local nextSell = os.clock() + State.sellInterval
local lastError = ""
removeFlight = function()
    if flightVelocity then pcall(flightVelocity.Destroy, flightVelocity); flightVelocity = nil end
    if flightGyro then pcall(flightGyro.Destroy, flightGyro); flightGyro = nil end
end

local function updatePlayerMods()
    local hum = humanoid()
    local root = rootPart()
    if hum then
        if not modifiedHumanoids[hum] then
            modifiedHumanoids[hum] = {
                walkSpeed = hum.WalkSpeed,
                jumpPower = hum.JumpPower,
                walkApplied = false,
                jumpApplied = false,
            }
        end
        local original = modifiedHumanoids[hum]
        if State.walkSpeedToggle then
            hum.WalkSpeed = State.walkSpeedValue
            original.walkApplied = true
        elseif original.walkApplied then
            hum.WalkSpeed = original.walkSpeed
            original.walkApplied = false
        end
        if State.jumpPowerToggle then
            hum.UseJumpPower = true
            hum.JumpPower = State.jumpPowerValue
            original.jumpApplied = true
        elseif original.jumpApplied then
            hum.JumpPower = original.jumpPower
            original.jumpApplied = false
        end
    end

    if root then
        if State.freezePosition ~= wasFrozen then
            if State.freezePosition then
                frozenRoot = root
                frozenRootWasAnchored = root.Anchored
            end
            root.Anchored = State.freezePosition
            if not State.freezePosition and frozenRoot == root then root.Anchored = frozenRootWasAnchored end
            wasFrozen = State.freezePosition
        end
        if State.flyToggle then
            if not flightVelocity or flightVelocity.Parent ~= root then
                removeFlight()
                flightVelocity = Instance.new("BodyVelocity")
                flightVelocity.Name = "BH_Reconstructed_FlightVelocity"
                flightVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                flightVelocity.Parent = root
                flightGyro = Instance.new("BodyGyro")
                flightGyro.Name = "BH_Reconstructed_FlightGyro"
                flightGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                flightGyro.P = 9000
                flightGyro.Parent = root
            end
            local direction = hum and hum.MoveDirection or Vector3.zero
            flightVelocity.Velocity = direction * State.flySpeed
            local camera = workspace.CurrentCamera
            if camera then flightGyro.CFrame = CFrame.lookAt(root.Position, root.Position + camera.CFrame.LookVector) end
        else
            removeFlight()
        end
    else
        removeFlight()
    end

    if State.disableRendering ~= renderingDisabled then
        renderingDisabled = State.disableRendering
        pcall(RunService.Set3dRenderingEnabled, RunService, not renderingDisabled)
    end
end

task.spawn(function()
    while Runtime.alive do
        local now = os.clock()
        if State.autoFish then
            local ok, err = pcall(function()
                local rod = equippedRod()
                if not rod and State.autoEquip then rod = equipRod() end

                local button = State.autoShake and shakeButton() or nil
                if button then
                    clickGuiButton(button)
                    setStatus("Auto Fish: shaking")
                elseif State.instantReel and reelVisible() and now - lastReel >= math.max(State.reelDelay, 0.1) then
                    lastReel = now
                    local reelOk, reelErr = finishReel()
                    if reelOk then
                        nextCast = now + 1.2
                        setStatus("Auto Fish: reel finished")
                    else
                        error(reelErr)
                    end
                elseif State.autoCast and rod and now >= nextCast and not hasBobber(rod) then
                    local castOk, castErr = cast()
                    nextCast = now + State.castInterval
                    if castOk then
                        setStatus("Auto Fish: cast sent")
                        if State.zoneCasting then
                            task.spawn(function()
                                for _ = 1, 8 do
                                    if not Runtime.alive or not State.zoneCasting then return end
                                    task.wait(0.25)
                                    local moved = moveBobberToSavedZone(rod)
                                    if moved then setStatus("Auto Fish: zone cast positioned"); return end
                                end
                            end)
                        end
                    else error(castErr) end
                end
            end)
            if not ok then
                local message = tostring(err)
                if message ~= lastError then log("auto fish: " .. message); lastError = message end
                setStatus("Auto Fish waiting: " .. message)
            else
                lastError = ""
            end
        end

        if State.autoSell and now >= nextSell then
            nextSell = now + State.sellInterval
            local ok, err = sellAll()
            if not ok then log("auto sell: " .. tostring(err)) end
        elseif not State.autoSell then
            nextSell = now + State.sellInterval
        end
        local modsOk, modsErr = pcall(updatePlayerMods)
        if not modsOk and tostring(modsErr) ~= lastError then log("player mods: " .. tostring(modsErr)) end
        task.wait(0.08)
    end
end)

log("started version " .. Runtime.version)
setStatus("Ready • enable Master Auto Fish")
