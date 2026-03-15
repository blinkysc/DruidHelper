-- Classes/Paladin/Core.lua
-- Priority rotation logic for Paladin specs (3.3.5a compatible)
-- Based on wowsim/wotlk APL

local DH = PriorityHelper
if not DH then return end

if select(2, UnitClass("player")) ~= "PALADIN" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- Helper to add a recommendation
local function addRec(recommendations, key)
    local ability = class.abilities[key]
    if ability then
        table.insert(recommendations, {
            ability = key,
            texture = ability.texture,
            name = ability.name,
        })
    end
    return #recommendations >= 3
end

-- ============================================================================
-- RETRIBUTION ROTATION (wowsim APL)
--
-- Priority:
-- 1. Hammer of Wrath (execute phase, < 20% HP)
-- 2. Judgement of Wisdom
-- 3. Crusader Strike
-- 4. Divine Storm
-- 5. Exorcism (only with Art of War proc - instant cast)
-- 6. Consecration (if > 4s remaining on fight)
--
-- Cooldowns (handled separately):
-- - Avenging Wrath on CD
-- - Divine Plea for mana
-- ============================================================================

local function GetRetributionRecommendations(addon)
    local recommendations = {}
    local s = state

    if not s.target.exists or not s.target.canAttack then
        return recommendations
    end

    -- Build priority queue: { abilityKey, cooldownKey, ready, remains, condition }
    -- Sorted by: ready first (by priority order), then by CD remaining
    local queue = {}
    local function queueAbility(abilityKey, cdKey, condition)
        if condition == false then return end
        local cd = s.cooldown[cdKey]
        local remains = cd and cd.remains or 0
        local ready = remains <= 0.1
        table.insert(queue, { ability = abilityKey, ready = ready, remains = remains })
    end

    -- Avenging Wrath off CD (snoozeable - if player skips it, don't nag for 60s)
    if s.cooldown.avenging_wrath.ready and not s.buff.avenging_wrath.up
        and not DH:IsSnoozed("avenging_wrath") then
        if addRec(recommendations, "avenging_wrath") then return recommendations end
    end

    -- Target type detection
    local creatureType = UnitCreatureType("target")
    local isUndeadOrDemon = creatureType == "Undead" or creatureType == "Demon"

    -- Execute phase: HoW (highest priority when available)
    local inExecute = s.target.health.pct < 20
    if inExecute then
        queueAbility("hammer_of_wrath", "hammer_of_wrath")
    end

    -- Core FCFS rotation (wowhead priority)
    -- Against Undead/Demons: Exorcism gets 100% crit, boost it above CS
    if isUndeadOrDemon and s.buff.art_of_war.up then
        queueAbility("exorcism", "exorcism")
    end

    -- 1. Crusader Strike - "highest priority button in single target"
    queueAbility("crusader_strike", "crusader_strike")
    -- 2. Judgement of Wisdom
    queueAbility("judgement_of_wisdom", "judgement")
    -- 3. Divine Storm
    queueAbility("divine_storm", "divine_storm", s.talent.divine_storm.rank > 0)
    -- 4. Consecration
    if s.target.time_to_die > 4 then
        queueAbility("consecration", "consecration")
    end
    -- 5. Exorcism (Art of War proc - normal priority vs non-undead)
    if not isUndeadOrDemon and s.buff.art_of_war.up then
        queueAbility("exorcism", "exorcism")
    end
    -- 6. Holy Wrath (only vs undead/demons - it can't hit other types)
    if isUndeadOrDemon then
        queueAbility("holy_wrath", "holy_wrath")
    end

    -- Divine Plea if low mana
    if s.mana.pct < 50 then
        queueAbility("divine_plea", "divine_plea")
    end

    -- Pass 1: add ready abilities in priority order (what to press NOW)
    for _, entry in ipairs(queue) do
        if entry.ready then
            if addRec(recommendations, entry.ability) then return recommendations end
        end
    end

    -- Pass 2: fill remaining slots with next abilities off CD (sorted by shortest CD)
    -- so the player can see what's coming up next
    local onCD = {}
    for _, entry in ipairs(queue) do
        if not entry.ready then
            table.insert(onCD, entry)
        end
    end
    table.sort(onCD, function(a, b) return a.remains < b.remains end)
    for _, entry in ipairs(onCD) do
        if #recommendations >= 3 then break end
        local isDupe = false
        for _, rec in ipairs(recommendations) do
            if rec.ability == entry.ability then isDupe = true break end
        end
        if not isDupe then
            addRec(recommendations, entry.ability)
        end
    end

    return recommendations
end

-- ============================================================================
-- PROTECTION ROTATION (wowsim APL)
--
-- Priority:
-- 1. Shield of Righteousness (when HotR CD <= 3s)
-- 2. Hammer of the Righteous (when SoR CD <= 3s)
-- 3. Hammer of Wrath (execute phase)
-- 4. Consecration
-- 5. Holy Shield (maintain)
-- 6. Judgement of Wisdom
--
-- The SoR/HotR interleaving ensures you always have one of the two
-- primary threat abilities coming off cooldown soon.
-- ============================================================================

local function GetProtectionRecommendations(addon)
    local recommendations = {}
    local s = state

    if not s.target.exists or not s.target.canAttack then
        return recommendations
    end

    -- Righteous Fury check
    if not s.buff.righteous_fury.up then
        if addRec(recommendations, "righteous_fury") then return recommendations end
    end

    -- Build priority queue
    local queue = {}
    local function queueAbility(abilityKey, cdKey, condition)
        if condition == false then return end
        local cd = s.cooldown[cdKey]
        local remains = cd and cd.remains or 0
        local ready = remains <= 0.1
        table.insert(queue, { ability = abilityKey, ready = ready, remains = remains })
    end

    -- SoR / HotR interleave logic (from sim APL)
    -- Prioritize whichever is ready when the other is coming off CD within 3s
    local sor_ready = s.cooldown.shield_of_righteousness.ready
    local hotr_ready = s.cooldown.hammer_of_the_righteous.ready
    local sor_remains = s.cooldown.shield_of_righteousness.remains
    local hotr_remains = s.cooldown.hammer_of_the_righteous.remains

    if sor_ready and hotr_remains <= 3 then
        if addRec(recommendations, "shield_of_righteousness") then return recommendations end
    elseif hotr_ready and sor_remains <= 3 then
        if addRec(recommendations, "hammer_of_the_righteous") then return recommendations end
    elseif sor_ready then
        if addRec(recommendations, "shield_of_righteousness") then return recommendations end
    elseif hotr_ready then
        if addRec(recommendations, "hammer_of_the_righteous") then return recommendations end
    end

    -- Queue ALL abilities for filling slots (SoR/HotR included for lookahead)
    queueAbility("shield_of_righteousness", "shield_of_righteousness")
    queueAbility("hammer_of_the_righteous", "hammer_of_the_righteous")
    if s.target.health.pct < 20 then
        queueAbility("hammer_of_wrath", "hammer_of_wrath")
    end
    queueAbility("consecration", "consecration")
    queueAbility("holy_shield", "holy_shield")
    queueAbility("judgement_of_wisdom", "judgement")

    -- Divine Plea for mana
    if s.mana.pct < 60 then
        queueAbility("divine_plea", "divine_plea")
    end

    -- Helper to check duplicates
    local function isDuplicate(abilityKey)
        for _, rec in ipairs(recommendations) do
            if rec.ability == abilityKey then return true end
        end
        return false
    end

    -- Add ready abilities first (skip dupes from SoR/HotR interleave above)
    for _, entry in ipairs(queue) do
        if entry.ready and not isDuplicate(entry.ability) then
            if addRec(recommendations, entry.ability) then return recommendations end
        end
    end

    -- Fill remaining with next off CD (shortest first)
    local onCD = {}
    for _, entry in ipairs(queue) do
        if not entry.ready then
            table.insert(onCD, entry)
        end
    end
    table.sort(onCD, function(a, b) return a.remains < b.remains end)

    for _, entry in ipairs(onCD) do
        if #recommendations >= 3 then break end
        if not isDuplicate(entry.ability) then
            addRec(recommendations, entry.ability)
        end
    end

    return recommendations
end

-- ============================================================================
-- ROTATION MODES
-- ============================================================================

DH:RegisterMode("ret", {
    name = "Retribution (DPS)",
    icon = select(3, GetSpellInfo(35395)) or "Interface\\Icons\\Ability_ThunderClap",
    rotation = function(addon)
        return GetRetributionRecommendations(addon)
    end,
})

DH:RegisterMode("prot_paladin", {
    name = "Protection (Tank)",
    icon = select(3, GetSpellInfo(48827)) or "Interface\\Icons\\Spell_Holy_AvengersShield",
    rotation = function(addon)
        return GetProtectionRecommendations(addon)
    end,
})
