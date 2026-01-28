--[[
    StateManager.lua
    Finite State Machine (FSM) for managing script states
    Handles state transitions, callbacks, and error recovery
]]

local StateManager = {}
StateManager.__index = StateManager

-- Define all possible states
local States = {
    IDLE = "Idle",
    QUESTING = "Questing",
    FRUIT_SNIPING = "FruitSniping",
    BOSS_FARMING = "BossFarming",
    MASTERY = "Mastery",
    NAVIGATING = "Navigating",
    COMBAT = "Combat",
    LOOTING = "Looting",
    ERROR = "Error",
    PAUSED = "Paused"
}

-- State priorities (higher = more important)
local StatePriorities = {
    [States.IDLE] = 1,
    [States.NAVIGATING] = 2,
    [States.QUESTING] = 3,
    [States.MASTERY] = 3,
    [States.BOSS_FARMING] = 4,
    [States.FRUIT_SNIPING] = 5,
    [States.COMBAT] = 6,
    [States.LOOTING] = 7,
    [States.ERROR] = 10,
    [States.PAUSED] = 0
}

-- Valid state transitions
local ValidTransitions = {
    [States.IDLE] = {States.QUESTING, States.FRUIT_SNIPING, States.BOSS_FARMING, States.MASTERY, States.PAUSED},
    [States.QUESTING] = {States.IDLE, States.NAVIGATING, States.COMBAT, States.ERROR, States.PAUSED},
    [States.NAVIGATING] = {States.IDLE, States.QUESTING, States.COMBAT, States.ERROR, States.PAUSED},
    [States.COMBAT] = {States.IDLE, States.QUESTING, States.LOOTING, States.NAVIGATING, States.ERROR, States.PAUSED},
    [States.LOOTING] = {States.IDLE, States.QUESTING, States.NAVIGATING, States.ERROR, States.PAUSED},
    [States.FRUIT_SNIPING] = {States.IDLE, States.NAVIGATING, States.LOOTING, States.ERROR, States.PAUSED},
    [States.BOSS_FARMING] = {States.IDLE, States.NAVIGATING, States.COMBAT, States.ERROR, States.PAUSED},
    [States.MASTERY] = {States.IDLE, States.NAVIGATING, States.COMBAT, States.ERROR, States.PAUSED},
    [States.ERROR] = {States.IDLE, States.PAUSED},
    [States.PAUSED] = {States.IDLE, States.QUESTING, States.FRUIT_SNIPING, States.BOSS_FARMING, States.MASTERY}
}

function StateManager.new()
    local self = setmetatable({}, StateManager)

    self.currentState = States.IDLE
    self.previousState = nil
    self.stateData = {}
    self.callbacks = {
        onEnter = {},
        onExit = {},
        onUpdate = {}
    }
    self.errorCount = 0
    self.maxErrors = 5
    self.lastStateChange = tick()
    self.stateHistory = {}
    self.maxHistorySize = 20

    return self
end

-- Get all available states
function StateManager:GetStates()
    return States
end

-- Get current state
function StateManager:GetCurrentState()
    return self.currentState
end

-- Get previous state
function StateManager:GetPreviousState()
    return self.previousState
end

-- Check if state transition is valid
function StateManager:IsValidTransition(fromState, toState)
    local validStates = ValidTransitions[fromState]
    if validStates then
        for _, state in ipairs(validStates) do
            if state == toState then
                return true
            end
        end
    end
    return false
end

-- Transition to a new state
function StateManager:SetState(newState, data, force)
    -- Validate state exists
    local stateExists = false
    for _, state in pairs(States) do
        if state == newState then
            stateExists = true
            break
        end
    end

    if not stateExists then
        warn("[StateManager] Invalid state:", newState)
        return false
    end

    -- Check if transition is valid (unless forced)
    if not force and not self:IsValidTransition(self.currentState, newState) then
        warn("[StateManager] Invalid transition from", self.currentState, "to", newState)
        return false
    end

    -- Don't transition to same state
    if self.currentState == newState and not force then
        return true
    end

    local oldState = self.currentState

    -- Call exit callback for old state
    if self.callbacks.onExit[oldState] then
        local success, err = pcall(self.callbacks.onExit[oldState], self.stateData)
        if not success then
            warn("[StateManager] Error in exit callback:", err)
        end
    end

    -- Update state
    self.previousState = oldState
    self.currentState = newState
    self.stateData = data or {}
    self.lastStateChange = tick()

    -- Add to history
    table.insert(self.stateHistory, {
        from = oldState,
        to = newState,
        time = tick(),
        data = data
    })

    -- Trim history if too large
    while #self.stateHistory > self.maxHistorySize do
        table.remove(self.stateHistory, 1)
    end

    -- Call enter callback for new state
    if self.callbacks.onEnter[newState] then
        local success, err = pcall(self.callbacks.onEnter[newState], self.stateData)
        if not success then
            warn("[StateManager] Error in enter callback:", err)
            self.errorCount = self.errorCount + 1

            if self.errorCount >= self.maxErrors then
                self:SetState(States.ERROR, {error = err}, true)
            end
        end
    end

    -- Reset error count on successful transition
    if newState ~= States.ERROR then
        self.errorCount = 0
    end

    return true
end

-- Register callbacks for state transitions
function StateManager:OnEnter(state, callback)
    self.callbacks.onEnter[state] = callback
end

function StateManager:OnExit(state, callback)
    self.callbacks.onExit[state] = callback
end

function StateManager:OnUpdate(state, callback)
    self.callbacks.onUpdate[state] = callback
end

-- Update current state (call this in main loop)
function StateManager:Update()
    if self.currentState == States.PAUSED then
        return
    end

    if self.callbacks.onUpdate[self.currentState] then
        local success, result = pcall(self.callbacks.onUpdate[self.currentState], self.stateData)
        if not success then
            warn("[StateManager] Error in update callback:", result)
            self.errorCount = self.errorCount + 1

            if self.errorCount >= self.maxErrors then
                self:SetState(States.ERROR, {error = result}, true)
            end
        end
        return result
    end
end

-- Get state data
function StateManager:GetStateData(key)
    if key then
        return self.stateData[key]
    end
    return self.stateData
end

-- Set state data
function StateManager:SetStateData(key, value)
    self.stateData[key] = value
end

-- Pause the state machine
function StateManager:Pause()
    if self.currentState ~= States.PAUSED then
        self:SetState(States.PAUSED, {resumeState = self.currentState}, true)
    end
end

-- Resume from pause
function StateManager:Resume()
    if self.currentState == States.PAUSED then
        local resumeState = self.stateData.resumeState or States.IDLE
        self:SetState(resumeState, {}, true)
    end
end

-- Reset to idle state
function StateManager:Reset()
    self.errorCount = 0
    self.stateHistory = {}
    self.stateData = {}
    self:SetState(States.IDLE, {}, true)
end

-- Get time in current state
function StateManager:GetTimeInState()
    return tick() - self.lastStateChange
end

-- Get state priority
function StateManager:GetStatePriority(state)
    return StatePriorities[state or self.currentState] or 0
end

-- Check if current activity should be interrupted by a higher priority state
function StateManager:ShouldInterrupt(newState)
    local currentPriority = self:GetStatePriority(self.currentState)
    local newPriority = self:GetStatePriority(newState)
    return newPriority > currentPriority
end

-- Recovery from error state
function StateManager:RecoverFromError()
    if self.currentState == States.ERROR then
        self.errorCount = 0
        self:SetState(States.IDLE, {}, true)
        return true
    end
    return false
end

-- Get state history
function StateManager:GetHistory()
    return self.stateHistory
end

-- Check if in specific state
function StateManager:IsInState(state)
    return self.currentState == state
end

-- Check if in any farming state
function StateManager:IsFarming()
    return self.currentState == States.QUESTING or
           self.currentState == States.BOSS_FARMING or
           self.currentState == States.MASTERY or
           self.currentState == States.COMBAT or
           self.currentState == States.NAVIGATING
end

return {
    new = StateManager.new,
    States = States,
    Priorities = StatePriorities
}
