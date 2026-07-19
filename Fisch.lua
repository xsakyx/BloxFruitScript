--[[
    BlackHub reel runtime tracer (all probes in one file)

    RUN ORDER
      1. Creates BlackHubTrace/<timestamp>/ and installs every probe.
      2. Takes the BEFORE snapshots.
      3. Runs the target block near the bottom of this file.
      4. Watches the target for TRACE_SECONDS.
      5. Takes AFTER snapshots and flushes all organized log files.

    Put this whole file on GitHub and loadstring the raw URL once.
    Edit only runBlackHubTarget() near the bottom so it runs the real BlackHub.
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local TRACE_SECONDS = 90
local ACTIVE_HOOK_DELAY = 10
local ROOT_FOLDER = "BlackHubTrace"
local SESSION_ID = os.date("%Y-%m-%d_%H-%M-%S") .. "_" .. tostring(math.random(1000, 9999))
local SESSION_FOLDER = ROOT_FOLDER .. "/" .. SESSION_ID
local SNAPSHOT_FOLDER = SESSION_FOLDER .. "/snapshots"

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local globals = (getgenv and getgenv()) or _G

local native = {
    tostring = tostring,
    type = type,
    typeof = typeof,
    pairs = pairs,
    ipairs = ipairs,
    pcall = pcall,
    xpcall = xpcall,
    select = select,
    unpack = table.unpack,
    insert = table.insert,
    concat = table.concat,
    format = string.format,
    lower = string.lower,
    gsub = string.gsub,
    find = string.find,
    sub = string.sub,
    clock = os.clock,
    date = os.date,
    writefile = writefile,
    appendfile = appendfile,
    makefolder = makefolder,
    isfolder = isfolder,
    isfile = isfile,
    readfile = readfile,
}

local Trace = {
    __BH_TRACE_INTERNAL = true,
    active = true,
    stopping = false,
    connections = {},
    buffers = {},
    fileCache = {},
    eventCounts = {},
    watchedInstances = setmetatable({}, {__mode = "k"}),
    watchedTables = setmetatable({}, {__mode = "k"}),
    watchedFunctions = setmetatable({}, {__mode = "k"}),
    tableIds = setmetatable({}, {__mode = "k"}),
    functionIds = setmetatable({}, {__mode = "k"}),
    nextTableId = 0,
    nextFunctionId = 0,
    oldHooks = {},
}

local oldTrace = rawget(globals, "__BLACKHUB_RUNTIME_TRACE")
if native.type(oldTrace) == "table" and native.type(oldTrace.Stop) == "function" then
    native.pcall(oldTrace.Stop, "replaced by a new trace")
end
globals.__BLACKHUB_RUNTIME_TRACE = Trace

local function normalize(value)
    return native.gsub(native.lower(native.tostring(value)), "[^%w]", "")
end

local function ensureFolder(path)
    if native.type(native.makefolder) ~= "function" then return false end
    if native.type(native.isfolder) == "function" then
        local ok, exists = native.pcall(native.isfolder, path)
        if ok and exists then return true end
    end
    return native.pcall(native.makefolder, path)
end

ensureFolder(ROOT_FOLDER)
ensureFolder(SESSION_FOLDER)
ensureFolder(SNAPSHOT_FOLDER)

local function count(name)
    Trace.eventCounts[name] = (Trace.eventCounts[name] or 0) + 1
end

local function safeFullName(instance)
    local ok, result = native.pcall(instance.GetFullName, instance)
    return ok and result or native.tostring(instance)
end

local function safeValue(value, depth)
    depth = depth or 0
    local valueType = native.typeof(value)
    if valueType == "Instance" then
        return native.format("<%s %s>", value.ClassName, safeFullName(value))
    elseif valueType == "string" then
        local text = value
        if #text > 500 then text = native.sub(text, 1, 500) .. "...<truncated>" end
        text = native.gsub(text, "\r", "\\r")
        text = native.gsub(text, "\n", "\\n")
        return native.format("%q", text)
    elseif valueType == "number" or valueType == "boolean" or valueType == "nil" then
        return native.tostring(value)
    elseif valueType == "table" then
        if depth >= 1 then return native.tostring(value) end
        local rendered = {}
        local total = 0
        for key, child in native.pairs(value) do
            total += 1
            if total <= 12 then
                rendered[#rendered + 1] = "[" .. safeValue(key, 1) .. "]=" .. safeValue(child, 1)
            end
        end
        if total > 12 then rendered[#rendered + 1] = "...+" .. native.tostring(total - 12) end
        return "{" .. native.concat(rendered, ", ") .. "}"
    end
    local ok, result = native.pcall(native.tostring, value)
    return ok and result or "<" .. valueType .. ">"
end

local function flushFile(name)
    local lines = Trace.buffers[name]
    if not lines or #lines == 0 or native.type(native.writefile) ~= "function" then return end
    local text = native.concat(lines, "\n") .. "\n"
    Trace.buffers[name] = {}
    local path = SESSION_FOLDER .. "/" .. name
    if native.type(native.appendfile) == "function" then
        native.pcall(native.appendfile, path, text)
    else
        local previous = Trace.fileCache[name] or ""
        previous ..= text
        Trace.fileCache[name] = previous
        native.pcall(native.writefile, path, previous)
    end
end

local function log(name, message)
    if not Trace.active and name ~= "12_summary.txt" then return end
    local line = native.format("[%0.4f] %s", native.clock(), native.tostring(message))
    local lines = Trace.buffers[name]
    if not lines then lines = {}; Trace.buffers[name] = lines end
    lines[#lines + 1] = line
    if #lines >= 25 then flushFile(name) end
end

local function flushAll()
    for name in native.pairs(Trace.buffers) do flushFile(name) end
end

if native.type(native.writefile) == "function" then
    native.pcall(native.writefile, ROOT_FOLDER .. "/LATEST.txt", SESSION_FOLDER)
end

local function connect(signal, callback)
    local ok, connection = native.pcall(signal.Connect, signal, callback)
    if ok and connection then Trace.connections[#Trace.connections + 1] = connection end
    return connection
end

local function isInterestingText(value)
    if native.type(value) ~= "string" then return false end
    local n = normalize(value)
    return native.find(n, "reel", 1, true) ~= nil
        or native.find(n, "playerbar", 1, true) ~= nil
        or n == "bar"
        or n == "fish"
        or native.find(n, "control", 1, true) ~= nil
        or native.find(n, "resilience", 1, true) ~= nil
        or native.find(n, "progress", 1, true) ~= nil
end

local function isInterestingInstance(instance)
    if native.typeof(instance) ~= "Instance" then return false end
    if isInterestingText(instance.Name) then return true end
    local parent = instance.Parent
    for _ = 1, 4 do
        if not parent then break end
        if isInterestingText(parent.Name) then return true end
        parent = parent.Parent
    end
    return false
end

local function instanceLine(prefix, instance)
    return native.format("%s class=%s name=%s path=%s", prefix, instance.ClassName, safeValue(instance.Name), safeFullName(instance))
end

local INSTANCE_PROPERTIES = {
    "Size", "Position", "AbsoluteSize", "AbsolutePosition", "AnchorPoint",
    "Visible", "Enabled", "Value", "Parent", "Name", "Active",
}

local function watchInstance(instance, reason)
    if native.typeof(instance) ~= "Instance" or Trace.watchedInstances[instance] then return end
    if not isInterestingInstance(instance) then return end
    Trace.watchedInstances[instance] = true
    count("instances_watched")
    log("03_ui_lifecycle.txt", instanceLine("WATCH reason=" .. native.tostring(reason), instance))

    for _, property in native.ipairs(INSTANCE_PROPERTIES) do
        local okRead, initial = native.pcall(function() return instance[property] end)
        if okRead then
            log("04_instance_changes.txt", native.format("INITIAL %s.%s = %s", safeFullName(instance), property, safeValue(initial)))
            local last = safeValue(initial)
            local okSignal, signal = native.pcall(instance.GetPropertyChangedSignal, instance, property)
            if okSignal and signal then
                connect(signal, function()
                    if not Trace.active then return end
                    local okValue, value = native.pcall(function() return instance[property] end)
                    local rendered = okValue and safeValue(value) or "<read failed>"
                    if rendered ~= last then
                        count("instance_property_changes")
                        log("04_instance_changes.txt", native.format("SIGNAL %s.%s: %s -> %s", safeFullName(instance), property, last, rendered))
                        last = rendered
                    end
                end)
            end
        end
    end

    local okAttributes, attributes = native.pcall(instance.GetAttributes, instance)
    if okAttributes then
        for key, value in native.pairs(attributes) do
            log("04_instance_changes.txt", native.format("ATTRIBUTE_INITIAL %s[%s] = %s", safeFullName(instance), safeValue(key), safeValue(value)))
        end
    end
    connect(instance.AttributeChanged, function(attribute)
        if not Trace.active then return end
        local okValue, value = native.pcall(instance.GetAttribute, instance, attribute)
        count("attribute_changes")
        log("04_instance_changes.txt", native.format("ATTRIBUTE_CHANGE %s[%s] = %s", safeFullName(instance), safeValue(attribute), okValue and safeValue(value) or "<read failed>"))
    end)
end

local function scanInstances(root, reason)
    if not root then return end
    watchInstance(root, reason)
    local ok, descendants = native.pcall(root.GetDescendants, root)
    if not ok then return end
    for _, item in native.ipairs(descendants) do watchInstance(item, reason) end
end

local function currentRod()
    local character = player.Character
    if not character then return nil end
    for _, child in native.ipairs(character:GetChildren()) do
        if child:IsA("Tool") then
            local n = normalize(child.Name)
            if native.find(n, "rod", 1, true) then return child end
            for _, item in native.ipairs(child:GetDescendants()) do
                if (item:IsA("RemoteEvent") or item:IsA("RemoteFunction")) and normalize(item.Name) == "cast" then return child end
            end
        end
    end
end

local lastRod
local function snapshotRod(rod, reason)
    if not rod then
        log("06_rod_state.txt", "ROD_NONE reason=" .. native.tostring(reason))
        return
    end
    log("06_rod_state.txt", instanceLine("ROD reason=" .. native.tostring(reason), rod))
    local items = {rod}
    for _, item in native.ipairs(rod:GetDescendants()) do items[#items + 1] = item end
    for _, item in native.ipairs(items) do
        local interesting = isInterestingInstance(item)
            or item:IsA("NumberValue")
            or item:IsA("IntValue")
            or item:IsA("StringValue")
            or item:IsA("ObjectValue")
        if interesting then
            local valueText = ""
            if item:IsA("ValueBase") then
                local okValue, value = native.pcall(function() return item.Value end)
                valueText = okValue and (" value=" .. safeValue(value)) or " value=<failed>"
            end
            log("06_rod_state.txt", instanceLine("ROD_ITEM", item) .. valueText)
            watchInstance(item, "rod")
        end
        local okAttributes, attributes = native.pcall(item.GetAttributes, item)
        if okAttributes then
            for key, value in native.pairs(attributes) do
                log("06_rod_state.txt", native.format("ROD_ATTRIBUTE %s[%s] = %s", safeFullName(item), safeValue(key), safeValue(value)))
            end
        end
    end
end

connect(playerGui.ChildAdded, function(child)
    if not Trace.active then return end
    if isInterestingInstance(child) or child:IsA("LayerCollector") then
        count("playergui_child_added")
        log("03_ui_lifecycle.txt", instanceLine("PLAYERGUI_CHILD_ADDED", child))
        task.defer(scanInstances, child, "PlayerGui.ChildAdded")
    end
end)

connect(playerGui.DescendantAdded, function(descendant)
    if not Trace.active or not isInterestingInstance(descendant) then return end
    count("playergui_descendant_added")
    log("03_ui_lifecycle.txt", instanceLine("PLAYERGUI_DESCENDANT_ADDED", descendant))
    watchInstance(descendant, "PlayerGui.DescendantAdded")
end)

connect(playerGui.DescendantRemoving, function(descendant)
    if not Trace.active or not isInterestingInstance(descendant) then return end
    count("playergui_descendant_removing")
    log("03_ui_lifecycle.txt", instanceLine("PLAYERGUI_DESCENDANT_REMOVING", descendant))
end)

scanInstances(playerGui, "initial PlayerGui scan")
snapshotRod(currentRod(), "before target")

local function relevantProperty(instance, key)
    if native.typeof(instance) ~= "Instance" then return false end
    local n = normalize(key)
    if n ~= "size" and n ~= "position" and n ~= "anchorpoint" and n ~= "value"
        and n ~= "parent" and n ~= "visible" and n ~= "enabled" and n ~= "name" then
        return false
    end
    return isInterestingInstance(instance)
end

local function installActiveHooks()
if native.type(hookmetamethod) == "function" and native.type(newcclosure) == "function" then
    local oldNewIndex
    local okNewIndex, resultNewIndex = native.pcall(function()
        oldNewIndex = hookmetamethod(game, "__newindex", newcclosure(function(self, key, value)
            if Trace.active and relevantProperty(self, key) then
                local okOld, oldValue = native.pcall(function() return self[key] end)
                count("newindex_writes")
                log("04_instance_changes.txt", native.format("__NEWINDEX %s.%s: %s -> %s", safeFullName(self), safeValue(key), okOld and safeValue(oldValue) or "<failed>", safeValue(value)))
            end
            return oldNewIndex(self, key, value)
        end))
        return oldNewIndex
    end)
    if okNewIndex then
        Trace.oldHooks.newindex = resultNewIndex
        log("01_capabilities.txt", "HOOK __newindex = installed")
    else
        log("11_errors.txt", "HOOK __newindex failed: " .. safeValue(resultNewIndex))
    end

    if native.type(getnamecallmethod) == "function" then
        local oldNamecall
        local okNamecall, resultNamecall = native.pcall(function()
            oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                local method = getnamecallmethod()
                if Trace.active and (method == "FireServer" or method == "InvokeServer") and native.typeof(self) == "Instance" then
                    local args = table.pack(...)
                    local rendered = {}
                    for index = 1, math.min(args.n, 20) do rendered[index] = safeValue(args[index]) end
                    count("remote_calls")
                    log("05_remote_calls.txt", native.format("%s %s args(%d)=%s", method, safeFullName(self), args.n, native.concat(rendered, " | ")))
                elseif Trace.active and method == "SetAttribute" and native.typeof(self) == "Instance" and isInterestingInstance(self) then
                    local attribute, value = ...
                    count("setattribute_calls")
                    log("04_instance_changes.txt", native.format("__NAMECALL SetAttribute %s[%s]=%s", safeFullName(self), safeValue(attribute), safeValue(value)))
                end
                return oldNamecall(self, ...)
            end))
            return oldNamecall
        end)
        if okNamecall then
            Trace.oldHooks.namecall = resultNamecall
            log("01_capabilities.txt", "HOOK __namecall = installed")
        else
            log("11_errors.txt", "HOOK __namecall failed: " .. safeValue(resultNamecall))
        end
    end
else
    log("01_capabilities.txt", "HOOK metamethods = unavailable")
end
end

local function tableId(target)
    local id = Trace.tableIds[target]
    if not id then
        Trace.nextTableId += 1
        id = "T" .. native.tostring(Trace.nextTableId)
        Trace.tableIds[target] = id
    end
    return id
end

local function functionId(target)
    local id = Trace.functionIds[target]
    if not id then
        Trace.nextFunctionId += 1
        id = "F" .. native.tostring(Trace.nextFunctionId)
        Trace.functionIds[target] = id
    end
    return id
end

local function relevantTableKey(key)
    if native.type(key) ~= "string" then return false end
    local n = normalize(key)
    return n == "control" or n == "reel" or n == "autoreel" or n == "playerbar"
        or n == "fish" or n == "bar" or n == "size" or n == "position"
        or n == "resilience" or n == "progress" or n == "progressspeed"
        or n == "forcedprogressspeed" or n == "reelfinished"
end

local function scalar(value)
    local kind = native.type(value)
    return kind == "nil" or kind == "boolean" or kind == "number" or kind == "string"
end

local function inspectTable(target, phase)
    if native.type(target) ~= "table" or target == Trace or Trace.watchedTables[target] then return false end
    local interesting = false
    local fields = {}
    local total = 0
    local ok = native.pcall(function()
        for key, value in native.pairs(target) do
            if relevantTableKey(key) or (native.type(key) == "string" and isInterestingText(key)) then interesting = true end
            if native.type(key) == "string" and (relevantTableKey(key) or scalar(value)) and total < 60 then
                total += 1
                fields[key] = safeValue(value)
            end
        end
    end)
    if not ok or not interesting then return false end
    Trace.watchedTables[target] = fields
    local rendered = {}
    for key, value in native.pairs(fields) do rendered[#rendered + 1] = safeValue(key) .. "=" .. value end
    count("gc_tables_watched")
    log("07_gc_tables.txt", native.format("%s %s %s", phase, tableId(target), native.concat(rendered, " | ")))
    return true
end

local function getFunctionConstants(func)
    if debug and native.type(debug.getconstants) == "function" then
        local ok, constants = native.pcall(debug.getconstants, func)
        if ok and native.type(constants) == "table" then return constants end
    end
    if native.type(getconstants) == "function" then
        local ok, constants = native.pcall(getconstants, func)
        if ok and native.type(constants) == "table" then return constants end
    end
end

local function getFunctionUpvalues(func)
    if debug and native.type(debug.getupvalues) == "function" then
        local ok, values = native.pcall(debug.getupvalues, func)
        if ok and native.type(values) == "table" then return values end
    end
    if native.type(getupvalues) == "function" then
        local ok, values = native.pcall(getupvalues, func)
        if ok and native.type(values) == "table" then return values end
    end
    local getter = debug and debug.getupvalue or getupvalue
    if native.type(getter) == "function" then
        local values = {}
        for index = 1, 100 do
            local ok, name, value = native.pcall(getter, func, index)
            if not ok or name == nil then break end
            values[index] = value
        end
        return values
    end
end

local function inspectFunction(func, phase)
    if native.type(func) ~= "function" or Trace.watchedFunctions[func] then return false end
    local constants = getFunctionConstants(func)
    if not constants then return false end
    local hits = {}
    for index, value in native.pairs(constants) do
        if native.type(value) == "string" and isInterestingText(value) then
            hits[#hits + 1] = native.tostring(index) .. "=" .. safeValue(value)
        end
    end
    if #hits == 0 then return false end
    local upvalues = getFunctionUpvalues(func) or {}
    local snapshot = {}
    local renderedUpvalues = {}
    for index, value in native.pairs(upvalues) do
        snapshot[index] = safeValue(value)
        renderedUpvalues[#renderedUpvalues + 1] = native.tostring(index) .. "=" .. snapshot[index]
        if native.type(value) == "table" then inspectTable(value, phase .. "_upvalue") end
    end
    Trace.watchedFunctions[func] = snapshot
    count("gc_functions_watched")
    log("09_functions.txt", native.format("%s %s constants=%s upvalues=%s", phase, functionId(func), native.concat(hits, " | "), native.concat(renderedUpvalues, " | ")))
    return true
end

local function discoverGc(phase)
    if native.type(getgc) ~= "function" then
        log("01_capabilities.txt", "getgc = unavailable")
        return
    end
    local ok, objects = native.pcall(getgc, true)
    if not ok or native.type(objects) ~= "table" then
        log("11_errors.txt", "getgc failed in " .. phase .. ": " .. safeValue(objects))
        return
    end
    local tablesFound, functionsFound = 0, 0
    for _, object in native.ipairs(objects) do
        if native.type(object) == "table" and inspectTable(object, phase) then tablesFound += 1 end
        if native.type(object) == "function" and inspectFunction(object, phase) then functionsFound += 1 end
    end
    log("07_gc_tables.txt", native.format("DISCOVERY_DONE phase=%s objects=%d newTables=%d newFunctions=%d", phase, #objects, tablesFound, functionsFound))
end

local function pollTables()
    for target, snapshot in native.pairs(Trace.watchedTables) do
        local ok = native.pcall(function()
            local keys = {}
            for key in native.pairs(snapshot) do keys[key] = true end
            for key in native.pairs(target) do
                if relevantTableKey(key) then keys[key] = true end
            end
            for key in native.pairs(keys) do
                local value = safeValue(rawget(target, key))
                local previous = snapshot[key]
                if previous ~= value then
                    count("gc_table_changes")
                    log("08_gc_changes.txt", native.format("%s[%s]: %s -> %s", tableId(target), safeValue(key), previous or "<not captured>", value))
                    snapshot[key] = value
                end
            end
        end)
        if not ok then Trace.watchedTables[target] = nil end
    end
end

local function pollFunctions()
    for func, snapshot in native.pairs(Trace.watchedFunctions) do
        local upvalues = getFunctionUpvalues(func)
        if upvalues then
            for index, value in native.pairs(upvalues) do
                local rendered = safeValue(value)
                local previous = snapshot[index]
                if previous ~= rendered then
                    count("function_upvalue_changes")
                    log("10_upvalue_changes.txt", native.format("%s upvalue[%s]: %s -> %s", functionId(func), safeValue(index), previous or "<not captured>", rendered))
                    snapshot[index] = rendered
                    if native.type(value) == "table" then inspectTable(value, "changed_upvalue") end
                end
            end
        end
    end
end

local function capability(name, value)
    log("01_capabilities.txt", native.format("%-24s %s", name, native.type(value)))
end

for _, item in native.ipairs({
    {"writefile", writefile}, {"appendfile", appendfile}, {"makefolder", makefolder},
    {"getgc", getgc}, {"hookmetamethod", hookmetamethod}, {"newcclosure", newcclosure},
    {"getnamecallmethod", getnamecallmethod}, {"checkcaller", checkcaller},
    {"getconstants", getconstants or (debug and debug.getconstants)},
    {"getupvalues", getupvalues or (debug and debug.getupvalues)},
    {"getconnections", getconnections}, {"getsenv", getsenv}, {"getloadedmodules", getloadedmodules},
}) do capability(item[1], item[2]) end

log("00_manifest.txt", "session=" .. SESSION_ID)
log("00_manifest.txt", "folder=" .. SESSION_FOLDER)
log("00_manifest.txt", "trace_seconds=" .. native.tostring(TRACE_SECONDS))
log("00_manifest.txt", "place_id=" .. native.tostring(game.PlaceId))
log("00_manifest.txt", "job_id=" .. native.tostring(game.JobId))
log("00_manifest.txt", "player=" .. native.tostring(player.Name))
log("00_manifest.txt", "executor=" .. safeValue(native.type(identifyexecutor) == "function" and identifyexecutor() or "unknown"))
log("00_manifest.txt", "FILES: 03 UI lifecycle; 04 writes/signals; 05 remotes; 06 rod; 07 GC candidates; 08 GC diffs; 09 functions; 10 upvalues; 11 errors; 12 summary")

local function snapshotUi(name)
    local lines = {}
    for _, item in native.ipairs(playerGui:GetDescendants()) do
        if isInterestingInstance(item) then
            local line = instanceLine("SNAPSHOT", item)
            for _, property in native.ipairs(INSTANCE_PROPERTIES) do
                local ok, value = native.pcall(function() return item[property] end)
                if ok then line ..= " " .. property .. "=" .. safeValue(value) end
            end
            lines[#lines + 1] = line
        end
    end
    if #lines == 0 then lines[1] = "<no relevant UI instances>" end
    if native.type(native.writefile) == "function" then
        native.pcall(native.writefile, SNAPSHOT_FOLDER .. "/" .. name .. ".txt", native.concat(lines, "\n"))
    end
end

snapshotUi("before_ui")
discoverGc("before_target")
flushAll()

task.spawn(function()
    while Trace.active do
        local rod = currentRod()
        if rod ~= lastRod then
            lastRod = rod
            snapshotRod(rod, "equipped rod changed")
            if rod then scanInstances(rod, "equipped rod") end
        end
        pollTables()
        pollFunctions()
        task.wait(0.05)
    end
end)

-- Keep startup passive so Luraph/LuaArmor validation sees an untouched
-- DataModel metatable. The signal and GC probes above are already recording.
task.delay(ACTIVE_HOOK_DELAY, function()
    if Trace.active then
        log("02_target.txt", "INSTALLING_ACTIVE_HOOKS after " .. native.tostring(ACTIVE_HOOK_DELAY) .. " seconds")
        installActiveHooks()
    end
end)

task.delay(15, function()
    if Trace.active then discoverGc("post_start_15s") end
end)
task.delay(45, function()
    if Trace.active then discoverGc("post_start_45s") end
end)

task.spawn(function()
    while Trace.active do
        task.wait(1)
        flushAll()
    end
end)

--[[
    ================================================================
    TARGET BLOCK -- THIS IS THE ONLY PART YOU EDIT
    ================================================================

    Option A (recommended): put the raw URL of the REAL protected BlackHub
    in BLACKHUB_TARGET_URL.

    Option B: replace the body of runBlackHubTarget() with the exact
    BlackHub execution line/source. The probes above are already active
    before this function is called.
]]
local BLACKHUB_TARGET_URL = "PASTE_RAW_BLACKHUB_URL_HERE"

local function runBlackHubTarget()
    -- You may replace these lines with the full protected BlackHub source.
    if BLACKHUB_TARGET_URL == "PASTE_RAW_BLACKHUB_URL_HERE" then
        error("Set BLACKHUB_TARGET_URL or paste BlackHub inside runBlackHubTarget()")
    end
    local source = game:HttpGet(BLACKHUB_TARGET_URL)
    local chunk, compileError = loadstring(source, "@BlackHubTraceTarget")
    if not chunk then error(compileError) end
    return chunk()
end

-- Do not place BlackHub before this point. All probes must install first.
task.spawn(function()
    log("02_target.txt", "TARGET_START")
    local started = native.clock()
    local ok, result = native.xpcall(runBlackHubTarget, function(message)
        local traceback = debug and debug.traceback and debug.traceback(native.tostring(message), 2) or native.tostring(message)
        return traceback
    end)
    log("02_target.txt", native.format("TARGET_RETURN ok=%s elapsed=%0.4f result=%s", native.tostring(ok), native.clock() - started, safeValue(result)))
    if not ok then log("11_errors.txt", "TARGET_ERROR " .. native.tostring(result)) end
    task.wait(0.1)
    discoverGc("after_target_return")
    snapshotUi("after_target_return_ui")
    snapshotRod(currentRod(), "after target return")
end)

local function restoreHooks()
    if native.type(hookmetamethod) ~= "function" then return end
    if Trace.oldHooks.newindex then native.pcall(hookmetamethod, game, "__newindex", Trace.oldHooks.newindex) end
    if Trace.oldHooks.namecall then native.pcall(hookmetamethod, game, "__namecall", Trace.oldHooks.namecall) end
end

local REPORT_FILES = {
    "00_manifest.txt", "01_capabilities.txt", "02_target.txt", "03_ui_lifecycle.txt",
    "04_instance_changes.txt", "05_remote_calls.txt", "06_rod_state.txt", "07_gc_tables.txt",
    "08_gc_changes.txt", "09_functions.txt", "10_upvalue_changes.txt", "11_errors.txt",
    "12_summary.txt",
}

local function consolidateReports()
    if native.type(native.readfile) ~= "function" or native.type(native.writefile) ~= "function" then return end
    local sections = {}
    for _, name in native.ipairs(REPORT_FILES) do
        local path = SESSION_FOLDER .. "/" .. name
        local exists = true
        if native.type(native.isfile) == "function" then
            local ok, result = native.pcall(native.isfile, path)
            exists = ok and result == true
        end
        if exists then
            local ok, contents = native.pcall(native.readfile, path)
            if ok then sections[#sections + 1] = "===== " .. name .. " =====\n" .. contents end
        end
    end
    for _, name in native.ipairs({"before_ui.txt", "after_target_return_ui.txt", "final_ui.txt"}) do
        local path = SNAPSHOT_FOLDER .. "/" .. name
        local ok, contents = native.pcall(native.readfile, path)
        if ok then sections[#sections + 1] = "===== snapshots/" .. name .. " =====\n" .. contents end
    end
    native.pcall(native.writefile, SESSION_FOLDER .. "/99_ALL_LOGS.txt", native.concat(sections, "\n\n"))
end

function Trace.Stop(reason)
    if Trace.stopping then return end
    Trace.stopping = true
    reason = reason or "manual"
    log("12_summary.txt", "STOP reason=" .. native.tostring(reason))
    snapshotUi("final_ui")
    snapshotRod(currentRod(), "final")
    discoverGc("final")
    for name, value in native.pairs(Trace.eventCounts) do
        log("12_summary.txt", native.format("COUNT %-32s %s", name, native.tostring(value)))
    end
    log("12_summary.txt", "SESSION_FOLDER=" .. SESSION_FOLDER)
    flushAll()
    consolidateReports()
    Trace.active = false
    for _, connection in native.ipairs(Trace.connections) do native.pcall(connection.Disconnect, connection) end
    table.clear(Trace.connections)
    restoreHooks()
    if rawget(globals, "__BLACKHUB_RUNTIME_TRACE") == Trace then globals.__BLACKHUB_RUNTIME_TRACE = nil end
    warn("[BlackHubTrace] finished: " .. SESSION_FOLDER)
end

task.delay(TRACE_SECONDS, function()
    Trace.Stop("automatic timeout after " .. native.tostring(TRACE_SECONDS) .. " seconds")
end)

warn("[BlackHubTrace] running. Logs: " .. SESSION_FOLDER)
warn("[BlackHubTrace] keep fishing normally / enable BlackHub Auto Reel during the next " .. native.tostring(TRACE_SECONDS) .. " seconds")
