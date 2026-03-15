-- PriorityHelper.lua
-- Rotation helper framework for WotLK 3.3.5a
-- Class modules register their data via the registration API

-- Create addon namespace
PriorityHelper = {}
local DH = PriorityHelper

DH.Version = "1.1.6"

-- Namespace for internal data
local ns = {}
DH.ns = ns

ns.debug = {}
ns.inCombat = false

-- Aura tracking cache
ns.auras = {
    target = { buff = {}, debuff = {} },
    player = { buff = {}, debuff = {} }
}

-- Player class (detected at load time)
DH.playerClass = select(2, UnitClass("player"))

-- Class data structure
DH.Class = {
    file = DH.playerClass,
    resources = {},
    talents = {},
    glyphs = {},
    auras = {},
    abilities = {},
    abilityByName = {},
    meleeAbilities = {},  -- Keys of abilities that are melee range
    range = 5,
    settings = {},
}

-- State will be initialized in State.lua
DH.State = {}

-- Recommendation queue
ns.queue = {}
ns.recommendations = {}

-- Recommendation stability: prevent flickering by keeping recommendations
-- stable for at least one GCD. If the new recommendations differ from the
-- previous ones, only update if enough time has passed.
ns.lastRecTime = 0
ns.lastRecAbilities = {}
local REC_STABLE_DURATION = 0.5  -- Minimum time a recommendation stays visible

-- UI elements
ns.UI = {
    MainFrame = nil,
    Buttons = {}
}

-- ============================================================================
-- COOLDOWN SNOOZE SYSTEM
-- When the addon recommends a major cooldown but the player uses a different
-- ability instead, the CD recommendation is snoozed for a duration. If the
-- player manually uses the CD, the snooze clears immediately.
-- ============================================================================

ns.snooze = {}          -- { [abilityKey] = expireTime }
ns.lastRecommended = nil -- The first recommended ability key from last update

-- Check if an ability is currently snoozed
function DH:IsSnoozed(key)
    local expires = ns.snooze[key]
    if expires and GetTime() < expires then
        return true
    end
    ns.snooze[key] = nil
    return false
end

-- Snooze an ability for a duration (default 60s)
function DH:Snooze(key, duration)
    ns.snooze[key] = GetTime() + (duration or 60)
end

-- Clear snooze for an ability (player used it)
function DH:ClearSnooze(key)
    ns.snooze[key] = nil
end

-- Register an ability as snoozeable with a duration
-- When recommended but skipped, it won't be recommended again for `duration` seconds
ns.snoozeable = {}
function DH:RegisterSnoozeable(key, duration)
    ns.snoozeable[key] = duration or 60
end

-- ============================================================================
-- SIMULATION FRAMEWORK
-- Core simulation utilities used by all class rotation modules.
-- All sim functions operate on a sim table (not real state).
-- ============================================================================

-- ---- Registered Data ----
ns.manaCosts = {}       -- { [abilityKey] = costAsPctOfBaseMana }
ns.abilityCDs = {}      -- { [abilityKey] = baseCooldownSeconds }

-- ---- Registration ----

-- Register mana costs for abilities (as % of base mana, e.g. 0.05 = 5%)
function DH:RegisterManaCosts(costs)
    for key, cost in pairs(costs) do
        ns.manaCosts[key] = cost
    end
end

-- Register base cooldown durations for abilities
function DH:RegisterAbilityCooldowns(cds)
    for key, cd in pairs(cds) do
        ns.abilityCDs[key] = cd
    end
end

-- ---- GCD / Haste ----

-- Initialize GCD in a sim table from state (haste-adjusted)
-- resourceType: "melee" or "spell" (determines which haste to use)
function DH:SimInitGCD(simState, s, resourceType)
    local hasteBonus
    if resourceType == "spell" then
        hasteBonus = (s.stat.spell_haste or 1)  -- Already a multiplier
    else
        hasteBonus = 1 + (s.stat.haste or 0) / 100  -- Melee haste rating %
    end
    simState.haste = hasteBonus
    simState.gcd = math.max(1.0, 1.5 / hasteBonus)
    simState.gcd_remains = s.gcd_remains or 0
end

-- Get a haste-adjusted cast time
function DH:SimCastTime(simState, baseCastTime)
    local haste = simState.haste or 1
    return baseCastTime / haste
end

-- ---- Mana ----

-- Initialize mana fields in a sim table from state
function DH:SimInitMana(simState, s)
    simState.mana = s.mana.current
    simState.mana_max = s.mana.max
    simState.mana_pct = s.mana.pct
    simState.replenishment_remains = 0
    simState.mp5 = 0
end

local function UpdateManaPct(simState)
    simState.mana_pct = simState.mana_max > 0 and (simState.mana / simState.mana_max * 100) or 0
end

-- Spend mana for an ability (by key or override %)
function DH:SimSpendMana(simState, abilityKey, overrideCost)
    local cost_pct = overrideCost or ns.manaCosts[abilityKey]
    if not cost_pct then return end
    simState.mana = math.max(0, simState.mana - simState.mana_max * cost_pct)
    UpdateManaPct(simState)
end

-- Gain flat mana
function DH:SimGainMana(simState, amount)
    simState.mana = math.min(simState.mana_max, simState.mana + amount)
    UpdateManaPct(simState)
end

-- Gain mana as % of max
function DH:SimGainManaPct(simState, pct)
    DH:SimGainMana(simState, simState.mana_max * pct)
end

-- Tick mana regen over time (Replenishment + MP5)
function DH:SimTickMana(simState, seconds)
    if simState.replenishment_remains and simState.replenishment_remains > 0 then
        simState.replenishment_remains = simState.replenishment_remains - seconds
        if simState.replenishment_remains < 0 then simState.replenishment_remains = 0 end
        DH:SimGainMana(simState, simState.mana_max * 0.002 * seconds)
    end
    if simState.mp5 and simState.mp5 > 0 then
        DH:SimGainMana(simState, simState.mp5 / 5 * seconds)
    end
end

-- Check if sim can afford an ability
function DH:SimCanAfford(simState, abilityKey)
    local cost_pct = ns.manaCosts[abilityKey]
    if not cost_pct then return true end
    return simState.mana >= (simState.mana_max * cost_pct)
end

-- ---- Energy ----

-- Initialize energy fields in a sim table from state
function DH:SimInitEnergy(simState, s)
    simState.energy = s.energy.current
    simState.energy_max = s.energy.max or 100
    simState.energy_regen = 10  -- Base 10 energy/sec
end

-- Tick energy regen over time
function DH:SimTickEnergy(simState, seconds)
    simState.energy = math.min(simState.energy_max, simState.energy + simState.energy_regen * seconds)
end

-- ---- Rage ----

-- Initialize rage fields in a sim table from state
function DH:SimInitRage(simState, s)
    simState.rage = s.rage.current
    simState.rage_max = s.rage.max or 100
end

-- ---- Cooldown Tracking ----

-- Initialize a cooldown in sim from state
-- Returns: ready (bool), remains (seconds)
function DH:SimInitCD(s, cdKey)
    local cd = s.cooldown[cdKey]
    if cd then
        return cd.ready, cd.remains
    end
    return true, 0
end

-- Tick down a cooldown field in sim, returns new ready state
function DH:SimTickCD(simState, cdField, readyField, seconds)
    if simState[cdField] > 0 then
        simState[cdField] = simState[cdField] - seconds
        if simState[cdField] <= 0 then
            simState[readyField] = true
            simState[cdField] = 0
        end
    end
end

-- ---- Wait / Advance Time ----

-- Calculate how long to wait until the next action is available.
-- Takes a list of CD remaining values and the sim's GCD.
-- Returns the wait time (at least one GCD, so close CDs both resolve).
-- Usage: local wait = DH:SimWaitTime(sim, {sim.cs_cd, sim.judge_cd, sim.ds_cd})
function DH:SimWaitTime(simState, cdList)
    local shortest = 999
    for _, cd in ipairs(cdList) do
        if cd > 0 and cd < shortest then
            shortest = cd
        end
    end
    if shortest >= 999 then return shortest end
    -- Wait at least one GCD so abilities within one GCD of each other
    -- both get a chance to be ready (priority decides which to use)
    return math.max(shortest, simState.gcd or 1.5)
end

-- ---- Target ----

-- Initialize target fields in a sim table from state
function DH:SimInitTarget(simState, s)
    simState.ttd = s.target.time_to_die
    simState.target_pct = s.target.health.pct
    simState.in_execute = s.target.health.pct < 20
end

-- ============================================================================
-- REGISTRATION API
-- Class modules use these to register their data into the framework.
-- ============================================================================

-- Registered class data (populated by class modules)
ns.registered = {
    buffs = {},           -- List of buff keys to track
    debuffs = {},         -- List of debuff keys to track
    cooldowns = {},       -- { key = spellId } for cooldown tracking
    talents = {},         -- { { tab, index, key }, ... }
    glyphs = {},          -- { [glyphSpellId] = key, ... }
    buffMap = {},         -- { [spellId] = buffKey, ... }
    debuffMap = {},       -- { [spellId] = debuffKey, ... }
    externalDebuffMap = {},  -- { [spellId] = debuffKey, ... }
    debuffNamePatterns = {},  -- { { pattern, key }, ... } for name-based fallback
    externalDebuffNamePatterns = {},  -- same for external debuffs
    combatLogHandlers = {},  -- Functions called on COMBAT_LOG_EVENT_UNFILTERED
    formHandlers = {},    -- { formId = { update = fn, spec = fn }, ... }
    specDetector = nil,   -- Function that returns current spec string
    rotations = {},       -- { specKey = fn(addon), ... } returns recommendations
    modes = {},           -- Rotation modes for minimap dropdown
    gcdSpellId = nil,     -- Spell ID used to check GCD
    defaults = {},        -- Class-specific default settings
}

-- Register buff keys to track
function DH:RegisterBuffs(buffs)
    for _, buff in ipairs(buffs) do
        table.insert(ns.registered.buffs, buff)
    end
end

-- Register debuff keys to track
function DH:RegisterDebuffs(debuffs)
    for _, debuff in ipairs(debuffs) do
        table.insert(ns.registered.debuffs, debuff)
    end
end

-- Register cooldowns: { key = spellId, ... }
function DH:RegisterCooldowns(cooldowns)
    for key, spellId in pairs(cooldowns) do
        ns.registered.cooldowns[key] = spellId
    end
end

-- Register talents: { { tab, index, key }, ... }
function DH:RegisterTalents(talents)
    for _, data in ipairs(talents) do
        table.insert(ns.registered.talents, data)
    end
end

-- Register glyphs: { [glyphSpellId] = key, ... }
function DH:RegisterGlyphs(glyphs)
    for spellId, key in pairs(glyphs) do
        ns.registered.glyphs[spellId] = key
    end
end

-- Register buff spell ID mapping: { [spellId] = buffKey, ... }
function DH:RegisterBuffMap(map)
    for spellId, key in pairs(map) do
        ns.registered.buffMap[spellId] = key
    end
end

-- Register debuff spell ID mapping: { [spellId] = debuffKey, ... }
function DH:RegisterDebuffMap(map)
    for spellId, key in pairs(map) do
        ns.registered.debuffMap[spellId] = key
    end
end

-- Register external debuff mapping (from other players)
function DH:RegisterExternalDebuffMap(map)
    for spellId, key in pairs(map) do
        ns.registered.externalDebuffMap[spellId] = key
    end
end

-- Register debuff name patterns for fallback matching
function DH:RegisterDebuffNamePatterns(patterns)
    for _, data in ipairs(patterns) do
        table.insert(ns.registered.debuffNamePatterns, data)
    end
end

-- Register external debuff name patterns
function DH:RegisterExternalDebuffNamePatterns(patterns)
    for _, data in ipairs(patterns) do
        table.insert(ns.registered.externalDebuffNamePatterns, data)
    end
end

-- Register combat log handler function
function DH:RegisterCombatLogHandler(fn)
    table.insert(ns.registered.combatLogHandlers, fn)
end

-- Register spec detector function
function DH:RegisterSpecDetector(fn)
    ns.registered.specDetector = fn
end

-- Register rotation function for a spec key
function DH:RegisterRotation(specKey, fn)
    ns.registered.rotations[specKey] = fn
end

-- Register a rotation mode for the minimap dropdown
-- key: unique string, data: { name, icon, rotation = fn(addon) }
function DH:RegisterMode(key, data)
    ns.registered.modes = ns.registered.modes or {}
    data.key = key
    table.insert(ns.registered.modes, data)
end

-- Register GCD reference spell
function DH:RegisterGCDSpell(spellId)
    ns.registered.gcdSpellId = spellId
end

-- Register abilities that are melee range (for UI range overlay)
function DH:RegisterMeleeAbilities(keys)
    for _, key in ipairs(keys) do
        DH.Class.meleeAbilities[key] = true
    end
end

-- Register class-specific default settings (merged into defaults)
function DH:RegisterDefaults(classDefaults)
    ns.registered.defaults = classDefaults
end

-- Register form update handler
function DH:RegisterFormHandler(formId, handler)
    ns.registered.formHandlers[formId] = handler
end

-- ============================================================================
-- SETTINGS
-- ============================================================================

-- Core default settings (class-agnostic)
local coreDefaults = {
    enabled = true,
    debug = false,
    showDebugFrame = false,
    locked = false,
    display = {
        scale = 1.0,
        alpha = 1.0,
        x = 0,
        y = -200,
        iconSize = 50,
        showGCD = true,
        showRange = true,
        numIcons = 3,
    },
}

-- Deep copy function for defaults
local function DeepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Merge saved vars with defaults
local function MergeDefaults(saved, default)
    if type(default) ~= "table" then return saved or default end
    if type(saved) ~= "table" then saved = {} end

    for k, v in pairs(default) do
        if saved[k] == nil then
            saved[k] = DeepCopy(v)
        elseif type(v) == "table" then
            saved[k] = MergeDefaults(saved[k], v)
        end
    end
    return saved
end

-- Build full defaults by merging core + class-specific
local function BuildDefaults()
    local defaults = DeepCopy(coreDefaults)
    for k, v in pairs(ns.registered.defaults) do
        defaults[k] = DeepCopy(v)
    end
    return defaults
end

-- Debug print
function DH:Debug(msg, ...)
    if self.db and self.db.debug then
        print("|cFF00FF00PriorityHelper:|r " .. string.format(msg, ...))
    end
end

-- Print message
function DH:Print(msg)
    print("|cFF00FF00PriorityHelper:|r " .. msg)
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

-- Main event frame
local eventFrame = CreateFrame("Frame", "PriorityHelperEventFrame", UIParent)
eventFrame:Hide()

-- Update timer (200 updates/sec = 5ms)
local updateElapsed = 0
local UPDATE_INTERVAL = 0.005

eventFrame:SetScript("OnUpdate", function(self, elapsed)
    updateElapsed = updateElapsed + elapsed
    if updateElapsed >= UPDATE_INTERVAL then
        updateElapsed = 0
        DH:UpdateRecommendations()
    end
end)

-- Event handler
local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "PriorityHelper" then
            DH:OnInitialize()
            DH:OnEnable()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.inCombat = true
        ns.combatStart = GetTime()
        DH:ShowUI()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.inCombat = false
        if not UnitExists("target") then
            DH:HideUI()
        end
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" or unit == "target" then
            DH:UpdateRecommendations()
        end
    elseif event == "UNIT_POWER" then
        local unit = ...
        if unit == "player" then
            DH:UpdateRecommendations()
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        DH:UpdateRecommendations()
    elseif event == "PLAYER_TARGET_CHANGED" then
        DH:UpdateRecommendations()
        if UnitExists("target") and UnitCanAttack("player", "target") then
            DH:ShowUI()
        elseif not ns.inCombat then
            DH:HideUI()
        end
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        DH:UpdateRecommendations()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        DH:OnCombatLogEvent(...)
    end
end

eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

-- Initialize addon
function DH:OnInitialize()
    if self._initialized then return end
    self._initialized = true

    -- Load saved variables with merged defaults
    PriorityHelperDB = PriorityHelperDB or {}
    local defaults = BuildDefaults()
    self.db = MergeDefaults(PriorityHelperDB, defaults)
    PriorityHelperDB = self.db

    -- Register slash commands
    SLASH_PRIORITYHELPER1 = "/ph"
    SLASH_PRIORITYHELPER2 = "/priorityhelper"
    SlashCmdList["PRIORITYHELPER"] = function(msg)
        DH:SlashCommand(msg)
    end

    self:Print("v" .. self.Version .. " loaded. Type /ph for options.")
end

-- Enable addon
function DH:OnEnable()
    if self._enabled then return end
    self._enabled = true

    -- Register events
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("UNIT_POWER")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT")

    -- Initialize state
    if self.State and self.State.Init then
        self.State:Init()
    end

    -- Create UI
    self:InitializeUI()

    -- Start update loop
    eventFrame:Show()
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

-- Registered slash command handlers from class modules
ns.slashCommands = {}

function DH:RegisterSlashCommand(cmd, handler, helpText)
    ns.slashCommands[cmd] = { handler = handler, help = helpText }
end

function DH:SlashCommand(input)
    local cmd = string.lower(input or "")

    if cmd == "debug" then
        self.db.debug = not self.db.debug
        self:Print("Debug mode: " .. (self.db.debug and "ON" or "OFF"))
    elseif cmd == "lock" then
        self.db.locked = not self.db.locked
        self:Print("Display " .. (self.db.locked and "locked" or "unlocked"))
        if ns.UI.MainFrame then
            ns.UI.MainFrame:EnableMouse(not self.db.locked)
        end
    elseif cmd == "reset" then
        if ns.UI.MainFrame then
            ns.UI.MainFrame:ClearAllPoints()
            ns.UI.MainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
            self.db.display.x = 0
            self.db.display.y = -200
        end
        self:Print("Display position reset")
    elseif cmd == "toggle" then
        self.db.enabled = not self.db.enabled
        self:Print("PriorityHelper " .. (self.db.enabled and "enabled" or "disabled"))
        if self.db.enabled then
            eventFrame:Show()
        else
            eventFrame:Hide()
            self:HideUI()
        end
    elseif cmd == "show" then
        self:InitializeUI()
        self:UpdateState()
        self:UpdateRecommendations()
        self:ShowUI()
        self:Print("Forced UI show")
    elseif cmd == "force" then
        self:InitializeUI()
        if ns.UI.MainFrame then
            ns.UI.MainFrame:Show()
            ns.UI.MainFrame:SetAlpha(1)
            self:Print("MainFrame forced visible")
        end
        local _, _, questionIcon = GetSpellInfo(1) -- fallback
        for i, button in ipairs(ns.UI.Buttons) do
            button.icon:SetTexture(questionIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
            button:Show()
            self:Print("Button " .. i .. " forced visible")
        end
    elseif cmd == "test" then
        self:InitializeUI()
        -- Test with first 4 registered abilities
        local testRecs = {}
        local count = 0
        for key, ability in pairs(self.Class.abilities) do
            if count < 4 then
                table.insert(testRecs, { ability = key, texture = ability.texture, name = ability.name })
                count = count + 1
            end
        end
        ns.recommendations = testRecs
        self:UpdateUI()
        self:ShowUI()
        self:Print("Test icons displayed")
    elseif cmd == "status" then
        self:Print("--- Status ---")
        self:Print("Class: " .. tostring(self.playerClass))
        self:Print("Spec: " .. tostring(self:GetActiveSpec()))
        self:Print("Target: " .. tostring(UnitExists("target")) .. ", CanAttack: " .. tostring(UnitCanAttack("player", "target")))
        self:Print("Recommendations: " .. #ns.recommendations)
    elseif cmd == "live" then
        self.db.showDebugFrame = not self.db.showDebugFrame
        self:Print("Live debug: " .. (self.db.showDebugFrame and "ON" or "OFF"))
        if ns.DebugFrame then
            if self.db.showDebugFrame then
                ns.DebugFrame:Show()
            else
                ns.DebugFrame:Hide()
            end
        end
    elseif cmd == "scale" then
        self:Print("Current scale: " .. self.db.display.scale)
        self:Print("Use /ph scale <0.5-2.0> to change")
    elseif string.match(cmd, "^scale ") then
        local val = tonumber(string.match(cmd, "^scale (.+)"))
        if val and val >= 0.5 and val <= 2.0 then
            self.db.display.scale = val
            if ns.UI.MainFrame then
                ns.UI.MainFrame:SetScale(val)
            end
            self:Print("Scale set to " .. val)
        else
            self:Print("Invalid scale. Use 0.5 to 2.0")
        end
    elseif string.match(cmd, "^icons ") then
        local val = tonumber(string.match(cmd, "^icons (.+)"))
        if val and val >= 1 and val <= 4 then
            self.db.display.numIcons = val
            self:Print("Icons set to " .. val .. " - /reload to apply")
        else
            self:Print("Invalid. Use 1 to 4")
        end
    else
        -- Try class-registered slash commands
        local handled = false
        for pattern, data in pairs(ns.slashCommands) do
            if cmd == pattern or string.match(cmd, "^" .. pattern .. " ") or string.match(cmd, "^" .. pattern .. "$") then
                data.handler(cmd)
                handled = true
                break
            end
        end

        if not handled then
            self:Print("Commands:")
            self:Print("  /ph toggle - Enable/disable addon")
            self:Print("  /ph show - Force show UI")
            self:Print("  /ph status - Show debug status")
            self:Print("  /ph lock - Lock/unlock display position")
            self:Print("  /ph reset - Reset display position")
            self:Print("  /ph scale <0.5-2.0> - Set display scale")
            self:Print("  /ph icons <1-4> - Set icon count")
            self:Print("  /ph debug - Toggle debug mode")
            self:Print("  /ph live - Toggle live debug frame")
            -- Show class-registered commands
            for pattern, data in pairs(ns.slashCommands) do
                if data.help then
                    self:Print("  /ph " .. data.help)
                end
            end
        end
    end
end

-- ============================================================================
-- COMBAT LOG
-- ============================================================================

function DH:OnCombatLogEvent(timestamp, subevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellId, spellName, spellSchool, ...)
    if sourceGUID ~= UnitGUID("player") then return end

    -- Snooze detection: when player uses any ability, check if they skipped a snoozeable recommendation
    if subevent == "SPELL_CAST_SUCCESS" or subevent == "SPELL_DAMAGE" or subevent == "SPELL_AURA_APPLIED" then
        local topRec = ns.recommendations[1]
        if topRec and spellId then
            local topAbility = topRec.ability
            -- Find the ability key that matches the spell just used
            local castKey = nil
            local numericId = tonumber(spellId)
            for key, ability in pairs(self.Class.abilities) do
                if ability.id == numericId or ability.id == spellId then
                    castKey = key
                    break
                end
            end

            if castKey then
                -- Player used the snoozed ability — clear its snooze
                if ns.snooze[castKey] then
                    self:ClearSnooze(castKey)
                end

                -- Player used a different ability than recommended — snooze the recommended one
                if castKey ~= topAbility and ns.snoozeable and ns.snoozeable[topAbility] then
                    self:Snooze(topAbility, ns.snoozeable[topAbility])
                end
            end
        end
    end

    -- Dispatch to registered handlers
    for _, handler in ipairs(ns.registered.combatLogHandlers) do
        handler(subevent, sourceGUID, destGUID, spellId, spellName, ...)
    end
end

-- ============================================================================
-- CORE LOGIC
-- ============================================================================

-- Update state
function DH:UpdateState()
    if not self.db or not self.db.enabled then return end
    if self.State and self.State.Reset then
        self.State:Reset()
    end
end

-- Get active spec using registered detector
function DH:GetActiveSpec()
    if ns.registered.specDetector then
        return ns.registered.specDetector()
    end
    return "unknown"
end

-- Update recommendations using registered rotations
function DH:UpdateRecommendations()
    if not self.db or not self.db.enabled then return end
    if not UnitExists("target") and not ns.inCombat then return end

    -- Ensure state is updated
    self:UpdateState()

    local spec = self:GetActiveSpec()
    local recommendations = {}

    -- Try registered rotation for current spec
    local rotationFn = ns.registered.rotations[spec]
    if rotationFn then
        recommendations = rotationFn(self)
    end

    ns.recommendations = recommendations
    self:UpdateUI()

    if #recommendations > 0 then
        self:ShowUI()
    end
end

-- ============================================================================
-- UI FUNCTIONS (implemented in UI.lua)
-- ============================================================================

function DH:InitializeUI()
    if ns.InitializeUI then
        ns.InitializeUI(self)
    end
end

function DH:UpdateUI()
    if ns.UpdateUI then
        ns.UpdateUI(self)
    end
end

function DH:ShowUI()
    if ns.UI.MainFrame then
        ns.UI.MainFrame:Show()
    end
end

function DH:HideUI()
    if ns.UI.MainFrame then
        ns.UI.MainFrame:Hide()
    end
end

