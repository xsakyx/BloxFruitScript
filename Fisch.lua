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

local Runtime = {alive = true, connections = {}, version = "1.0.7-blackhub-internal-reel"}
env.__BLACKHUB_RECONSTRUCTED = Runtime

local ROOT = "BlackHubReconstructed"
local CONFIG_FILE = ROOT .. "/config.json"
local LOG_FILE = ROOT .. "/diagnostics.txt"

local defaults = {
    autoFish = false,
    autoEquip = true,
    autoCast = true,
    autoShake = true,
    autoReel = true,
    autoSell = false,
    antiAfk = true,
    disableRendering = false,
    castPower = 100,
    castInterval = 2,
    shakeInterval = 0.12,
    sellInterval = 300,
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
    -- Migrate phase-1 configs to the corrected fishing timings and reel controller.
    if saved.autoReel == nil then
        State.autoReel = true
        State.castInterval = defaults.castInterval
    end
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

local primaryInputDown = false
local function setPrimaryInput(down)
    if primaryInputDown == down then return true end
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(2, 2)
    local ok = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(viewport.X / 2, viewport.Y / 2, 0, down, game, 0)
    end)
    if ok then primaryInputDown = down end
    return ok
end

local function castPowerBar()
    local char = character()
    if not char then return nil end
    for _, item in ipairs(char:GetDescendants()) do
        if item:IsA("GuiObject") and normalize(item.Name) == "bar" then
            local parent = item.Parent
            local grandparent = parent and parent.Parent
            local parentName = parent and normalize(parent.Name) or ""
            local grandparentName = grandparent and normalize(grandparent.Name) or ""
            if parentName == "powerbar" or grandparentName == "powerbar" then return item end
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
    if not setPrimaryInput(true) then return false, "primary input unavailable" end

    local started = os.clock()
    local targetPower = math.clamp(State.castPower / 100, 0.01, 1)
    local fallbackHold = 0.25 + (1.25 * targetPower)
    local sawPowerBar = false

    repeat
        task.wait(0.025)
        local bar = castPowerBar()
        if bar then
            sawPowerBar = true
            if bar.Size.X.Scale >= targetPower - 0.01 then break end
        elseif not sawPowerBar and os.clock() - started >= fallbackHold then
            break
        end
    until os.clock() - started >= 2.25 or not Runtime.alive or not State.autoFish or not State.autoCast

    setPrimaryInput(false)
    return true
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

-- BlackHub's reel is not an instant-finish call.  The reel LocalScript keeps
-- the effective player-bar/hitbox width in Lua state, so changing GuiObject.Size
-- alone is only cosmetic.  Patch the live controller values and let the game's
-- ordinary reel loop do all progress and completion work.
local reelPlayerGui = player:WaitForChild("PlayerGui")
local reelPatch = {
    reel = nil,
    changes = {},
    tableSlots = setmetatable({}, {__mode = "k"}),
    functionSlots = setmetatable({}, {__mode = "k"}),
    applied = 0,
    attempts = 0,
    lastScan = 0,
    reported = false,
}

local debugLibrary = type(debug) == "table" and debug or nil
local getUpvalues = debugLibrary and debugLibrary.getupvalues or getupvalues
local setUpvalue = debugLibrary and debugLibrary.setupvalue or setupvalue
local getConstants = debugLibrary and debugLibrary.getconstants or getconstants
local getEnvironment = getfenv
local getGarbage = getgc
local getConnections = getconnections
local getScriptEnvironment = getsenv

local INTERNAL_SIZE_KEYS = {
    control = true,
    barsize = true,
    barwidth = true,
    playerbarsize = true,
    playerbarwidth = true,
    reelbarsize = true,
    reelbarwidth = true,
    controlbarsize = true,
    controlbarwidth = true,
    hitboxsize = true,
    hitboxwidth = true,
    reelhitboxsize = true,
    reelhitboxwidth = true,
}

local function clearReelPatchBookkeeping()
    reelPatch.reel = nil
    table.clear(reelPatch.changes)
    reelPatch.tableSlots = setmetatable({}, {__mode = "k"})
    reelPatch.functionSlots = setmetatable({}, {__mode = "k"})
    reelPatch.applied = 0
    reelPatch.attempts = 0
    reelPatch.lastScan = 0
    reelPatch.reported = false
end

local function restoreReelControl()
    for index = #reelPatch.changes, 1, -1 do
        local change = reelPatch.changes[index]
        if change.kind == "table" then
            pcall(function() change.target[change.key] = change.original end)
        elseif change.kind == "upvalue" and type(setUpvalue) == "function" then
            pcall(setUpvalue, change.target, change.key, change.original)
        end
    end
    clearReelPatchBookkeeping()
end

local function rememberTableValue(target, key, desired)
    local slots = reelPatch.tableSlots[target]
    if not slots then
        slots = {}
        reelPatch.tableSlots[target] = slots
    end
    local change = slots[key]
    if not change then
        change = {kind = "table", target = target, key = key, original = target[key], desired = desired}
        slots[key] = change
        reelPatch.changes[#reelPatch.changes + 1] = change
        reelPatch.applied = reelPatch.applied + 1
    else
        change.desired = desired
    end
    pcall(function() target[key] = desired end)
end

local function rememberUpvalue(target, key, original, desired)
    if type(setUpvalue) ~= "function" or type(key) ~= "number" then return end
    local slots = reelPatch.functionSlots[target]
    if not slots then
        slots = {}
        reelPatch.functionSlots[target] = slots
    end
    local change = slots[key]
    if not change then
        change = {kind = "upvalue", target = target, key = key, original = original, desired = desired}
        slots[key] = change
        reelPatch.changes[#reelPatch.changes + 1] = change
        reelPatch.applied = reelPatch.applied + 1
    else
        change.desired = desired
    end
    pcall(setUpvalue, target, key, desired)
end

local function enforceRememberedReelValues()
    for _, change in ipairs(reelPatch.changes) do
        if change.kind == "table" then
            pcall(function()
                if change.target[change.key] ~= change.desired then
                    change.target[change.key] = change.desired
                end
            end)
        elseif change.kind == "upvalue" and type(setUpvalue) == "function" then
            pcall(setUpvalue, change.target, change.key, change.desired)
        end
    end
end

local function readUpvalues(callback)
    if type(getUpvalues) ~= "function" then return nil end
    local ok, values = pcall(getUpvalues, callback)
    return ok and type(values) == "table" and values or nil
end

local function valueContainsTarget(value, targets, depth, seen)
    if targets[value] then return true end
    if depth <= 0 or type(value) ~= "table" then return false end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    local inspected = 0
    for key, child in pairs(value) do
        inspected = inspected + 1
        if inspected > 100 then break end
        if targets[key] or targets[child] then return true end
        if valueContainsTarget(child, targets, depth - 1, seen) then return true end
    end
    return false
end

local function matchingWidthNumber(value, widthScale, widthRatio)
    if type(value) ~= "number" or value <= 0 or value >= 0.99 then return false end
    local tolerance = math.max(0.002, math.abs(widthRatio) * 0.025)
    return (widthScale > 0.01 and math.abs(value - widthScale) <= tolerance)
        or math.abs(value - widthRatio) <= tolerance
end

local function internalMaxValue(value, keyName, metrics)
    local kind = typeof(value)
    if kind == "number" then
        if value >= 0 and value < 1.01 then return 1 end
    elseif kind == "UDim" then
        return UDim.new(1, 0)
    elseif kind == "UDim2" then
        return UDim2.new(1, 0, value.Y.Scale, value.Y.Offset)
    elseif kind == "Vector2" and metrics.barWidth > 0 then
        return Vector2.new(metrics.barWidth, value.Y)
    end
    return nil
end

local function patchNamedControllerTable(target, metrics, depth, seen)
    if type(target) ~= "table" or depth < 0 then return end
    seen = seen or {}
    if seen[target] then return end
    seen[target] = true
    local inspected = 0
    for key, value in pairs(target) do
        inspected = inspected + 1
        if inspected > 250 then break end
        if type(key) == "string" and INTERNAL_SIZE_KEYS[normalize(key)] then
            local desired = internalMaxValue(value, key, metrics)
            if desired ~= nil and desired ~= value then rememberTableValue(target, key, desired) end
        elseif matchingWidthNumber(value, metrics.widthScale, metrics.widthRatio) then
            rememberTableValue(target, key, 1)
        elseif typeof(value) == "UDim" and value == metrics.playerSize.X then
            rememberTableValue(target, key, UDim.new(1, 0))
        elseif typeof(value) == "UDim2" and value == metrics.playerSize then
            rememberTableValue(target, key, UDim2.new(1, 0, value.Y.Scale, value.Y.Offset))
        end
        if type(value) == "table" and depth > 0 then
            patchNamedControllerTable(value, metrics, depth - 1, seen)
        end
    end
end

local function reelOwnedScript(owner, reel)
    if typeof(owner) ~= "Instance" or not owner:IsA("LuaSourceContainer") then return false end
    if owner:IsDescendantOf(reel) then return true end
    if not owner:IsDescendantOf(reelPlayerGui) then return false end
    local name = normalize(owner.Name)
    return string.find(name, "reel", 1, true) ~= nil or string.find(name, "fish", 1, true) ~= nil
end

local function functionMentionsReel(callback)
    if type(getConstants) ~= "function" then return false end
    local ok, constants = pcall(getConstants, callback)
    if not ok or type(constants) ~= "table" then return false end
    for _, constant in pairs(constants) do
        if type(constant) == "string" then
            local name = normalize(constant)
            if name == "playerbar" or name == "reel" or name == "reelbar" then
                return true
            end
        end
    end
    return false
end

local function patchControllerFunction(callback, reel, bar, playerBar, metrics, allowTargetProbe)
    local relevant = functionMentionsReel(callback)
    if not relevant and type(getEnvironment) == "function" then
        local ok, environment = pcall(getEnvironment, callback)
        local owner = ok and type(environment) == "table" and rawget(environment, "script") or nil
        relevant = reelOwnedScript(owner, reel)
    end
    if not relevant and not allowTargetProbe then return end
    local values = readUpvalues(callback)
    if not values then return end
    if not relevant then
        local targets = {[reel] = true, [bar] = true, [playerBar] = true}
        for _, value in pairs(values) do
            if valueContainsTarget(value, targets, 2) then relevant = true break end
        end
    end
    if not relevant then return end

    for key, value in pairs(values) do
        if type(value) == "table" then
            patchNamedControllerTable(value, metrics, 3)
        elseif type(key) == "number" then
            local kind = typeof(value)
            if matchingWidthNumber(value, metrics.widthScale, metrics.widthRatio) then
                rememberUpvalue(callback, key, value, 1)
            elseif kind == "UDim" and value == metrics.playerSize.X then
                rememberUpvalue(callback, key, value, UDim.new(1, 0))
            elseif kind == "UDim2" and value == metrics.playerSize then
                rememberUpvalue(callback, key, value, UDim2.new(1, 0, value.Y.Scale, value.Y.Offset))
            elseif kind == "Vector2" and metrics.playerWidth > 0 and math.abs(value.X - metrics.playerWidth) <= 2 then
                rememberUpvalue(callback, key, value, Vector2.new(metrics.barWidth, value.Y))
            end
        end
    end
end

local function addCandidate(candidates, callback, allowTargetProbe)
    if type(callback) ~= "function" then return end
    if candidates[callback] == nil or allowTargetProbe then
        candidates[callback] = allowTargetProbe == true
    end
end

local function collectSignalCallbacks(candidates, signal)
    if type(getConnections) ~= "function" then return end
    local ok, connections = pcall(getConnections, signal)
    if not ok or type(connections) ~= "table" then return end
    for _, connection in ipairs(connections) do
        local callback
        pcall(function() callback = connection.Function or connection.Callback end)
        addCandidate(candidates, callback, true)
    end
end

local function patchInternalReelController(reel, bar, playerBar)
    if reelPatch.reel ~= reel then
        restoreReelControl()
        reelPatch.reel = reel
    end
    local now = os.clock()
    if reelPatch.applied > 0 then
        enforceRememberedReelValues()
        return true
    end
    if reelPatch.attempts >= 6 then return false end
    if now - reelPatch.lastScan < 0.25 then return false end
    reelPatch.lastScan = now
    reelPatch.attempts = reelPatch.attempts + 1

    local barWidth = bar.AbsoluteSize.X
    local playerWidth = playerBar.AbsoluteSize.X
    local widthScale = playerBar.Size.X.Scale
    local widthRatio = barWidth > 0 and playerWidth / barWidth or widthScale
    local metrics = {
        barWidth = barWidth,
        playerWidth = playerWidth,
        widthScale = widthScale,
        widthRatio = widthRatio,
        tolerance = math.max(0.002, math.abs(widthRatio) * 0.025),
        playerSize = playerBar.Size,
    }
    local candidates = {}

    collectSignalCallbacks(candidates, RunService.RenderStepped)
    collectSignalCallbacks(candidates, RunService.Heartbeat)
    pcall(function() collectSignalCallbacks(candidates, RunService.PreRender) end)

    if type(getScriptEnvironment) == "function" then
        for _, owner in ipairs(reelPlayerGui:GetDescendants()) do
            if owner:IsA("LocalScript") and reelOwnedScript(owner, reel) then
                local ok, environment = pcall(getScriptEnvironment, owner)
                if ok and type(environment) == "table" then
                    for _, value in pairs(environment) do addCandidate(candidates, value, true) end
                end
            end
        end
    end

    if type(getGarbage) == "function" and (reelPatch.attempts == 1 or reelPatch.attempts == 4) then
        local ok, objects = pcall(getGarbage, true)
        if ok and type(objects) == "table" then
            local targets = {[reel] = true, [bar] = true, [playerBar] = true}
            for index = 1, math.min(#objects, 12000) do
                local object = objects[index]
                if type(object) == "function" then
                    addCandidate(candidates, object, false)
                elseif type(object) == "table" and valueContainsTarget(object, targets, 2) then
                    patchNamedControllerTable(object, metrics, 3)
                end
            end
        end
    end

    for callback, allowTargetProbe in pairs(candidates) do
        patchControllerFunction(callback, reel, bar, playerBar, metrics, allowTargetProbe)
    end
    if reelPatch.applied > 0 and not reelPatch.reported then
        reelPatch.reported = true
        log("internal reel controller patched: " .. tostring(reelPatch.applied) .. " captured gameplay value(s)")
    end
    return reelPatch.applied > 0
end

local function normalReel(reelGui)
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    local reel = reelGui or (playerGui and playerGui:FindFirstChild("reel"))
    if not reel then
        if reelPatch.reel then restoreReelControl() end
        return false
    end
    if normalize(reel.Name) ~= "reel" or not reel:IsA("ScreenGui") then return false end
    local bar = reel:FindFirstChild("bar")
    local playerBar = bar and bar:FindFirstChild("playerbar")
    if bar and playerBar and playerBar:IsA("GuiObject") then
        patchInternalReelController(reel, bar, playerBar)
    end
    return true
end

connect(reelPlayerGui.ChildAdded, function(child)
    if Runtime.alive and State.autoFish and State.autoReel then normalReel(child) end
end)

local function sellAll()
    -- Deliberately require a sell-all name. Calling an arbitrary 'sell' remote can sell the held item.
    local remote = findRemote({"sellall", "SellAll", "sellallfish", "SellAllFish", "sellallitems", "SellAllItems"}, true)
    if not remote then return false, "sell-all remote not found" end
    return callRemote(remote)
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
        if (key == "autoReel" or key == "autoFish") and (not State.autoReel or not State.autoFish) then
            restoreReelControl()
        end
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
addToggle("autoReel", "Auto Reel (internal max bar)")
addNumber("castPower", "Cast power", 1, 100)
addNumber("castInterval", "Recast delay (seconds)", 0.5, 15)
addNumber("shakeInterval", "Shake interval (seconds)", 0.08, 0.5)

addLabel("SELLING")
addToggle("autoSell", "Auto Sell All")
addNumber("sellInterval", "Sell interval (seconds)", 30, 3600)
addButton("Sell All Now", function()
    local ok, err = sellAll()
    setStatus(ok and "Sell-all request sent" or tostring(err))
    if not ok then log("sell failed: " .. tostring(err)) end
end)

addLabel("DISPLAY")
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
    log("cast method: normal held primary input")
    log("reel method: live LocalScript controller width/hitbox state; no cosmetic GUI edit")
    log("reel completion method: normal game reeling; no finish remote")
    log("sell-all remote: " .. (findRemote({"sellall", "SellAll", "sellallfish", "SellAllFish", "sellallitems", "SellAllItems"}, true) and "found" or "not found"))
    setStatus("Diagnostics written to " .. LOG_FILE)
end)
addButton("Unload", function() Runtime.Unload() end)

-- Dragging works with touch and mouse.
local dragging, dragStart, startPosition
local renderingDisabled = false
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
    restoreReelControl()
    setPrimaryInput(false)
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
local lastShake = 0
local nextSell = os.clock() + State.sellInterval
local lastError = ""
local function updateRendering()
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

                local reeling = State.autoReel and normalReel() or false
                local button = not reeling and State.autoShake and shakeButton() or nil
                if reeling then
                    setStatus(reelPatch.applied > 0 and "Auto Fish: internal max bar active" or "Auto Fish: finding reel controller")
                elseif button and now - lastShake >= State.shakeInterval then
                    lastShake = now
                    clickGuiButton(button)
                    setStatus("Auto Fish: shaking")
                elseif State.autoCast and rod and now >= nextCast and not hasBobber(rod) then
                    local castOk, castErr = cast()
                    nextCast = now + State.castInterval
                    if castOk then
                        setStatus("Auto Fish: cast sent")
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
        local renderOk, renderErr = pcall(updateRendering)
        if not renderOk and tostring(renderErr) ~= lastError then log("render setting: " .. tostring(renderErr)) end
        task.wait(0.05)
    end
end)

log("started version " .. Runtime.version)
setStatus("Ready - enable Master Auto Fish")
