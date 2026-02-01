-- DruidHelper.lua
-- Standalone rotation helper for WotLK 3.3.5a Druids
-- No external library dependencies

-- Only load for Druids
if select(2, UnitClass("player")) ~= "DRUID" then
    return
end

-- Create addon namespace
DruidHelper = {}
local DH = DruidHelper

DH.Version = "1.0.0"

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

-- Class data structure
DH.Class = {
    file = "DRUID",
    resources = {},
    talents = {},
    glyphs = {},
    auras = {},
    abilities = {},
    abilityByName = {},
    range = 5,
    settings = {},
}

-- State will be initialized in State.lua
DH.State = {}

-- Recommendation queue
ns.queue = {}
ns.recommendations = {}

-- UI elements
ns.UI = {
    MainFrame = nil,
    Buttons = {}
}

-- Default settings
local defaults = {
    enabled = true,
    debug = false,
    showDebugFrame = false,  -- On-screen debug info
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
    feral_cat = {
        enabled = true,
        min_bite_rip_remains = 10,
        min_bite_sr_remains = 8,
        max_bite_energy = 65,
        ferociousbite_enabled = true,
        optimize_rake = true,
        rip_leeway = 0,
        min_roar_offset = 3,
        -- Advanced tactics
        bearweave = false,  -- Shift to bear when energy-starved (Lacerateweave)
    },
    feral_bear = {
        enabled = true,
        aoe_threshold = 3,
    },
    balance = {
        enabled = true,
        lunar_cooldown_leeway = 5,
    },
    common = {
        bearweaving_enabled = false,
        flowerweaving_enabled = false,
        dummy_ttd = 300,
    }
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

-- Debug print
function DH:Debug(msg, ...)
    if self.db and self.db.debug then
        print("|cFF00FF00DruidHelper:|r " .. string.format(msg, ...))
    end
end

-- Print message
function DH:Print(msg)
    print("|cFF00FF00DruidHelper:|r " .. msg)
end

-- Main event frame
local eventFrame = CreateFrame("Frame", "DruidHelperEventFrame", UIParent)
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

-- Combat log event storage (3.3.5a passes args directly)
local combatLogArgs = {}

-- Event handler
local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "DruidHelper" then
            DH:OnInitialize()
        end
    elseif event == "PLAYER_LOGIN" then
        DH:OnEnable()
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
        -- 3.3.5a passes combat log args directly
        DH:OnCombatLogEvent(...)
    end
end

eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

-- Initialize addon
function DH:OnInitialize()
    -- Load saved variables
    DruidHelperDB = DruidHelperDB or {}
    self.db = MergeDefaults(DruidHelperDB, defaults)
    DruidHelperDB = self.db

    -- Register slash commands
    SLASH_DRUIDHELPER1 = "/dh"
    SLASH_DRUIDHELPER2 = "/druidhelper"
    SlashCmdList["DRUIDHELPER"] = function(msg)
        DH:SlashCommand(msg)
    end

    self:Print("v" .. self.Version .. " loaded. Type /dh for options.")
end

-- Enable addon
function DH:OnEnable()
    -- Register events
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("UNIT_POWER")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

    -- Initialize state
    if self.State and self.State.Init then
        self.State:Init()
    end

    -- Create UI
    self:InitializeUI()

    -- Start update loop
    eventFrame:Show()
end

-- Slash command handler
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
        self:Print("DruidHelper " .. (self.db.enabled and "enabled" or "disabled"))
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
        -- Force everything visible for debugging
        self:InitializeUI()
        if ns.UI.MainFrame then
            ns.UI.MainFrame:Show()
            ns.UI.MainFrame:SetAlpha(1)
            self:Print("MainFrame forced visible")
        end
        -- Force test icons
        local _, _, shredIcon = GetSpellInfo(48572)
        for i, button in ipairs(ns.UI.Buttons) do
            button.icon:SetTexture(shredIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
            button:Show()
            self:Print("Button " .. i .. " forced visible")
        end
    elseif cmd == "test" then
        self:InitializeUI()
        -- Force test recommendations using GetSpellInfo for textures
        local _, _, shredIcon = GetSpellInfo(48572)
        local _, _, rakeIcon = GetSpellInfo(48574)
        local _, _, ripIcon = GetSpellInfo(49800)
        local _, _, srIcon = GetSpellInfo(52610)
        ns.recommendations = {
            { ability = "shred", texture = shredIcon or "Interface\\Icons\\Ability_Druid_Disembowel", name = "Shred" },
            { ability = "rake", texture = rakeIcon or "Interface\\Icons\\Ability_Druid_Disembowel", name = "Rake" },
            { ability = "rip", texture = ripIcon or "Interface\\Icons\\Ability_GhoulFrenzy", name = "Rip" },
            { ability = "savage_roar", texture = srIcon or "Interface\\Icons\\Ability_Druid_SavageRoar", name = "Savage Roar" },
        }
        self:UpdateUI()
        self:ShowUI()
        self:Print("Test icons displayed")
    elseif cmd == "status" then
        self:Print("--- Status ---")
        self:Print("Form: " .. tostring(GetShapeshiftForm()) .. " (1=Bear, 3=Cat, 5=Moonkin)")
        self:Print("Target: " .. tostring(UnitExists("target")) .. ", CanAttack: " .. tostring(UnitCanAttack("player", "target")))
        self:Print("Recommendations: " .. #ns.recommendations)
    elseif cmd == "cat" then
        -- Detailed cat status
        local s = self.State
        self:UpdateState()
        self:Print("--- Cat Status ---")
        self:Print("Energy: " .. tostring(s.energy.current) .. "/" .. tostring(s.energy.max))
        self:Print("CP: " .. tostring(s.combo_points.current))
        self:Print("SR: " .. (s.buff.savage_roar.up and ("UP " .. string.format("%.1f", s.buff.savage_roar.remains) .. "s") or "DOWN"))
        self:Print("Rip: " .. (s.debuff.rip.up and ("UP " .. string.format("%.1f", s.debuff.rip.remains) .. "s") or "DOWN"))
        self:Print("Rake: " .. (s.debuff.rake.up and ("UP " .. string.format("%.1f", s.debuff.rake.remains) .. "s") or "DOWN"))
        self:Print("Mangle: " .. (s.debuff.mangle.up and ("UP " .. string.format("%.1f", s.debuff.mangle.remains) .. "s") or "DOWN"))
        self:Print("Mangle talent: " .. tostring(s.talent.mangle.rank))
        self:Print("TF ready: " .. tostring(s.cooldown.tigers_fury.ready) .. " (CD: " .. string.format("%.1f", s.cooldown.tigers_fury.remains) .. "s)")
        self:Print("Berserk talent: " .. tostring(s.talent.berserk.rank) .. ", " .. (s.buff.berserk.up and "ACTIVE" or "ready=" .. tostring(s.cooldown.berserk.ready)))
        self:Print("Clearcasting: " .. (s.buff.clearcasting.up and "UP" or "DOWN"))
        self:Print("FF ready: " .. tostring(s.cooldown.faerie_fire_feral.ready) .. " (CD: " .. string.format("%.1f", s.cooldown.faerie_fire_feral.remains) .. "s)")
        self:Print("OoC talent: " .. tostring(s.talent.omen_of_clarity.rank))
        self:Print("Glyph Shred: " .. tostring(s.glyph.shred and s.glyph.shred.enabled))
        self:Print("Rip Extensions: " .. tostring(ns.rip_extensions or 0) .. "/6")
        self:Print("TTD: " .. tostring(s.target.time_to_die) .. "s")
    elseif cmd == "debuffs" then
        -- Show all debuffs on target for debugging
        self:Print("--- Target Debuffs ---")
        if UnitExists("target") then
            for i = 1, 40 do
                local name, rank, icon, count, debuffType, duration, expirationTime, source, _, _, spellId = UnitDebuff("target", i)
                if not name then break end
                local timeLeft = expirationTime and (expirationTime - GetTime()) or 0
                self:Print(i .. ": " .. name .. " (ID:" .. tostring(spellId) .. ") src:" .. tostring(source) .. " " .. string.format("%.1f", timeLeft) .. "s")
            end
        else
            self:Print("No target")
        end
        self:Print("--- Tracked State ---")
        local s = self.State
        self:Print("Rake: up=" .. tostring(s.debuff.rake.up) .. " remains=" .. string.format("%.1f", s.debuff.rake.remains))
        self:Print("Rip: up=" .. tostring(s.debuff.rip.up) .. " remains=" .. string.format("%.1f", s.debuff.rip.remains))
        self:Print("Mangle: up=" .. tostring(s.debuff.mangle.up) .. " remains=" .. string.format("%.1f", s.debuff.mangle.remains))
    elseif cmd == "aoe" then
        self:Print("AoE rotation not implemented - use single target rotation")
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
        self:Print("Use /dh scale <0.5-2.0> to change")
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
    elseif cmd == "bearweave" or cmd == "bw" then
        self.db.feral_cat.bearweave = not self.db.feral_cat.bearweave
        if self.db.feral_cat.bearweave then
            self:Print("Bearweave: |cFF00FF00ON|r (Lacerateweave - maintain 5-stack Lacerate)")
        else
            self:Print("Bearweave: |cFFFF0000OFF|r (mono-cat rotation)")
        end
    elseif cmd == "bear" then
        -- Detailed bear status for bearweaving
        local s = self.State
        self:UpdateState()
        local enabled = self.db.feral_cat.bearweave
        self:Print("--- Bear/Weave Status ---")
        self:Print("Bearweave: " .. (enabled and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
        self:Print("In Bear: " .. tostring(s.bear_form) .. " | In Cat: " .. tostring(s.cat_form))
        self:Print("Energy: " .. tostring(s.energy.current) .. " | Rage: " .. tostring(s.rage.current))
        self:Print("Furor talent: " .. tostring(s.talent.furor.rank) .. "/5")
        self:Print("Mangle (Bear) CD: " .. (s.cooldown.mangle_bear.ready and "READY" or string.format("%.1fs", s.cooldown.mangle_bear.remains)))
        self:Print("Lacerate: " .. (s.debuff.lacerate.up and (tostring(s.debuff.lacerate.stacks) .. " stacks, " .. string.format("%.1f", s.debuff.lacerate.remains) .. "s") or "DOWN"))
        self:Print("Rip: " .. (s.debuff.rip.up and string.format("%.1f", s.debuff.rip.remains) .. "s" or "DOWN"))
        self:Print("SR: " .. (s.buff.savage_roar.up and string.format("%.1f", s.buff.savage_roar.remains) .. "s" or "DOWN"))
    else
        self:Print("Commands:")
        self:Print("  /dh toggle - Enable/disable addon")
        self:Print("  /dh show - Force show UI")
        self:Print("  /dh status - Show debug status")
        self:Print("  /dh lock - Lock/unlock display position")
        self:Print("  /dh reset - Reset display position")
        self:Print("  /dh scale <0.5-2.0> - Set display scale")
        self:Print("  /dh debug - Toggle debug mode")
        self:Print("  /dh bearweave - Toggle bearweaving (Lacerateweave)")
        self:Print("  /dh live - Toggle live debug frame")
    end
end

-- Combat log handler (3.3.5a format - NO hideCaster or raidFlags in WotLK!)
-- Args: timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags,
--       [spellId, spellName, spellSchool], ...
function DH:OnCombatLogEvent(timestamp, subevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellId, spellName, spellSchool, ...)
    if sourceGUID ~= UnitGUID("player") then return end

    -- Track Eclipse procs for Balance
    if subevent == "SPELL_AURA_APPLIED" then
        if spellId == 48518 then -- Eclipse (Lunar)
            ns.eclipse_lunar_last_applied = GetTime()
        elseif spellId == 48517 then -- Eclipse (Solar)
            ns.eclipse_solar_last_applied = GetTime()
        elseif spellId == 49800 then -- Rip applied
            ns.rip_extensions = 0
            ns.rip_target_guid = destGUID
            ns.last_rip_applied = GetTime()
        end
    elseif subevent == "SPELL_AURA_REFRESH" then
        if spellId == 49800 then -- Rip refreshed
            ns.rip_extensions = 0
            ns.rip_target_guid = destGUID
            ns.last_rip_applied = GetTime()
        end
    elseif subevent == "SPELL_DAMAGE" then
        -- Glyph of Shred: Shred extends Rip by 2 sec (max 6 extensions)
        if spellId == 48572 then -- Shred
            if ns.rip_target_guid == destGUID and ns.rip_extensions < 6 then
                if self.State.glyph.shred and self.State.glyph.shred.enabled then
                    ns.rip_extensions = ns.rip_extensions + 1
                end
            end
        end
    elseif subevent == "SPELL_AURA_REMOVED" then
        if spellId == 49800 then -- Rip fell off
            if destGUID == ns.rip_target_guid then
                ns.rip_extensions = 0
                ns.rip_target_guid = nil
            end
        end
    end
end

-- Update state
function DH:UpdateState()
    if not self.db or not self.db.enabled then return end
    if self.State and self.State.Reset then
        self.State:Reset()
    end
end

-- Update recommendations
function DH:UpdateRecommendations()
    if not self.db or not self.db.enabled then return end
    if not UnitExists("target") and not ns.inCombat then return end

    -- Ensure state is updated
    self:UpdateState()

    -- Get current form and determine which rotation to use
    local form = GetShapeshiftForm()
    local recommendations = {}

    if form == 3 then -- Cat Form
        recommendations = self:GetFeralCatRecommendations()
    elseif form == 1 then -- Bear Form
        -- If bearweaving is enabled, use cat rotation (handles bear abilities via bearweave logic)
        if self.db.feral_cat and self.db.feral_cat.bearweave then
            recommendations = self:GetFeralCatRecommendations()
        else
            recommendations = self:GetFeralBearRecommendations()
        end
    elseif form == 5 then -- Moonkin Form
        recommendations = self:GetBalanceRecommendations()
    else
        -- Caster form - suggest shifting based on spec
        local spec = self:GetActiveSpec()
        if spec == "balance" then
            local ability = self.Class.abilities.moonkin_form
            recommendations = { { ability = "moonkin_form", texture = ability and ability.texture or select(3, GetSpellInfo(24858)) } }
        else
            local ability = self.Class.abilities.cat_form
            recommendations = { { ability = "cat_form", texture = ability and ability.texture or select(3, GetSpellInfo(768)) } }
        end
    end

    ns.recommendations = recommendations
    self:UpdateUI()

    -- Show UI if we have recommendations
    if #recommendations > 0 then
        self:ShowUI()
    end
end

-- Get active spec based on talent points
function DH:GetActiveSpec()
    local balance, feral, resto = 0, 0, 0

    for i = 1, GetNumTalentTabs() do
        local _, _, points = GetTalentTabInfo(i)
        if i == 1 then balance = points
        elseif i == 2 then feral = points
        else resto = points
        end
    end

    if balance > feral and balance > resto then
        return "balance"
    elseif feral > resto then
        return "feral"
    else
        return "resto"
    end
end

-- Placeholder functions (implemented in Core.lua)
function DH:GetFeralCatRecommendations()
    if ns.GetFeralCatRecommendations then
        return ns.GetFeralCatRecommendations(self)
    end
    return {}
end

function DH:GetFeralBearRecommendations()
    if ns.GetFeralBearRecommendations then
        return ns.GetFeralBearRecommendations(self)
    end
    return {}
end

function DH:GetBalanceRecommendations()
    if ns.GetBalanceRecommendations then
        return ns.GetBalanceRecommendations(self)
    end
    return {}
end

-- UI functions (implemented in UI.lua)
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
