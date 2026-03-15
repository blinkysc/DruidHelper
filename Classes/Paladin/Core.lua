-- Classes/Paladin/Core.lua
-- Priority rotation logic for Paladin specs (3.3.5a compatible)
-- Based on wowsim/wotlk APL + wowhead guides
-- Uses simulation system: copy state, get ability, simulate, repeat for 3

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
-- SHARED PALADIN SIMULATION
-- ============================================================================

local sim = {}

local function ResetPaladinSim(s)
    -- GCD + haste (melee-based for Paladin)
    DH:SimInitGCD(sim, s, "melee")

    -- Target
    DH:SimInitTarget(sim, s)

    -- Target type (cached once, doesn't change mid-fight)
    local creatureType = UnitCreatureType("target")
    sim.is_undead_or_demon = creatureType == "Undead" or creatureType == "Demon"

    -- Improved Judgements: reduces Judgement CD by 1s per rank (max 2)
    sim.judge_base_cd = 10 - (s.talent.improved_judgements and s.talent.improved_judgements.rank or 0)

    -- Resources
    DH:SimInitMana(sim, s)

    -- Buffs
    sim.avenging_wrath_up = s.buff.avenging_wrath.up
    sim.art_of_war_up = s.buff.art_of_war.up
    sim.righteous_fury_up = s.buff.righteous_fury.up
    sim.holy_shield_up = s.buff.holy_shield.up
    sim.holy_shield_remains = s.buff.holy_shield.remains

    -- Cooldowns
    sim.cs_ready = s.cooldown.crusader_strike.ready
    sim.cs_cd = s.cooldown.crusader_strike.remains
    sim.judge_ready = s.cooldown.judgement.ready
    sim.judge_cd = s.cooldown.judgement.remains
    sim.ds_ready = s.cooldown.divine_storm.ready
    sim.ds_cd = s.cooldown.divine_storm.remains
    sim.how_ready = s.cooldown.hammer_of_wrath.ready
    sim.how_cd = s.cooldown.hammer_of_wrath.remains
    sim.exo_ready = s.cooldown.exorcism.ready
    sim.exo_cd = s.cooldown.exorcism.remains
    sim.cons_ready = s.cooldown.consecration.ready
    sim.cons_cd = s.cooldown.consecration.remains
    sim.aw_ready = s.cooldown.avenging_wrath.ready and not DH:IsSnoozed("avenging_wrath")
    sim.aw_cd = s.cooldown.avenging_wrath.remains
    sim.plea_ready = s.cooldown.divine_plea.ready
    sim.plea_cd = s.cooldown.divine_plea.remains
    sim.hw_ready = s.cooldown.holy_wrath.ready
    sim.hw_cd = s.cooldown.holy_wrath.remains

    -- Prot-specific
    sim.sor_ready = s.cooldown.shield_of_righteousness.ready
    sim.sor_cd = s.cooldown.shield_of_righteousness.remains
    sim.hotr_ready = s.cooldown.hammer_of_the_righteous.ready
    sim.hotr_cd = s.cooldown.hammer_of_the_righteous.remains
    sim.hs_ready = s.cooldown.holy_shield.ready
    sim.hs_cd = s.cooldown.holy_shield.remains

    -- Replenishment (from Judgements of the Wise)
    sim.replenishment_remains = 0  -- Will be set when Judgement is simulated

    -- Talents
    sim.has_ds = s.talent.divine_storm.rank > 0
end

local function SimulatePaladinTime(seconds)
    if seconds <= 0 then return end

    -- Tick down GCD
    if sim.gcd_remains > 0 then
        sim.gcd_remains = sim.gcd_remains - seconds
        if sim.gcd_remains < 0 then sim.gcd_remains = 0 end
    end

    -- Tick down all cooldowns
    if sim.cs_cd > 0 then
        sim.cs_cd = sim.cs_cd - seconds
        if sim.cs_cd <= 0 then sim.cs_ready = true; sim.cs_cd = 0 end
    end
    if sim.judge_cd > 0 then
        sim.judge_cd = sim.judge_cd - seconds
        if sim.judge_cd <= 0 then sim.judge_ready = true; sim.judge_cd = 0 end
    end
    if sim.ds_cd > 0 then
        sim.ds_cd = sim.ds_cd - seconds
        if sim.ds_cd <= 0 then sim.ds_ready = true; sim.ds_cd = 0 end
    end
    if sim.how_cd > 0 then
        sim.how_cd = sim.how_cd - seconds
        if sim.how_cd <= 0 then sim.how_ready = true; sim.how_cd = 0 end
    end
    if sim.exo_cd > 0 then
        sim.exo_cd = sim.exo_cd - seconds
        if sim.exo_cd <= 0 then sim.exo_ready = true; sim.exo_cd = 0 end
    end
    if sim.cons_cd > 0 then
        sim.cons_cd = sim.cons_cd - seconds
        if sim.cons_cd <= 0 then sim.cons_ready = true; sim.cons_cd = 0 end
    end
    if sim.hw_cd > 0 then
        sim.hw_cd = sim.hw_cd - seconds
        if sim.hw_cd <= 0 then sim.hw_ready = true; sim.hw_cd = 0 end
    end
    if sim.plea_cd > 0 then
        sim.plea_cd = sim.plea_cd - seconds
        if sim.plea_cd <= 0 then sim.plea_ready = true; sim.plea_cd = 0 end
    end
    if sim.aw_cd > 0 then
        sim.aw_cd = sim.aw_cd - seconds
        if sim.aw_cd <= 0 then sim.aw_ready = true; sim.aw_cd = 0 end
    end

    -- Prot CDs
    if sim.sor_cd > 0 then
        sim.sor_cd = sim.sor_cd - seconds
        if sim.sor_cd <= 0 then sim.sor_ready = true; sim.sor_cd = 0 end
    end
    if sim.hotr_cd > 0 then
        sim.hotr_cd = sim.hotr_cd - seconds
        if sim.hotr_cd <= 0 then sim.hotr_ready = true; sim.hotr_cd = 0 end
    end
    if sim.hs_cd > 0 then
        sim.hs_cd = sim.hs_cd - seconds
        if sim.hs_cd <= 0 then sim.hs_ready = true; sim.hs_cd = 0 end
    end

    -- Holy Shield buff
    if sim.holy_shield_remains > 0 then
        sim.holy_shield_remains = sim.holy_shield_remains - seconds
        if sim.holy_shield_remains <= 0 then
            sim.holy_shield_up = false
            sim.holy_shield_remains = 0
        end
    end

    -- Mana regen (Replenishment + MP5) via framework
    DH:SimTickMana(sim, seconds)

    -- Art of War doesn't tick down in sim (it's a proc, consumed on use)
end

-- ============================================================================
-- RETRIBUTION SIMULATION
-- ============================================================================

local function SimulateRetAbility(action)
    -- Spend mana via framework
    DH:SimSpendMana(sim, action)

    if action == "crusader_strike" then
        sim.cs_ready = false
        sim.cs_cd = 4
    elseif action == "judgement_of_wisdom" then
        sim.judge_ready = false
        sim.judge_cd = sim.judge_base_cd
        -- Judgements of the Wise: 25% base mana returned
        DH:SimGainManaPct(sim, 0.25)
        sim.replenishment_remains = 15
    elseif action == "divine_storm" then
        sim.ds_ready = false
        sim.ds_cd = 10
    elseif action == "hammer_of_wrath" then
        sim.how_ready = false
        sim.how_cd = 6
    elseif action == "exorcism" then
        sim.exo_ready = false
        sim.exo_cd = 15
        sim.art_of_war_up = false
    elseif action == "consecration" then
        sim.cons_ready = false
        sim.cons_cd = 8
    elseif action == "holy_wrath" then
        sim.hw_ready = false
        sim.hw_cd = 30
    elseif action == "avenging_wrath" then
        sim.aw_ready = false
        sim.aw_cd = 180
        sim.avenging_wrath_up = true
    elseif action == "divine_plea" then
        sim.plea_ready = false
        sim.plea_cd = 60
        -- Divine Plea restores 25% mana over 15s — approximate as immediate
        DH:SimGainManaPct(sim, 0.25)
    end

    SimulatePaladinTime(sim.gcd)
end

local function GetNextRetAbility()
    -- Avenging Wrath (snoozeable)
    if sim.aw_ready and not sim.avenging_wrath_up then
        return "avenging_wrath"
    end

    -- Execute phase: Hammer of Wrath
    if sim.in_execute and sim.how_ready then
        return "hammer_of_wrath"
    end

    -- Exorcism with Art of War vs Undead/Demon (100% crit, high priority)
    if sim.is_undead_or_demon and sim.art_of_war_up and sim.exo_ready then
        return "exorcism"
    end

    -- Core FCFS
    if sim.cs_ready then return "crusader_strike" end
    if sim.judge_ready then return "judgement_of_wisdom" end
    if sim.has_ds and sim.ds_ready then return "divine_storm" end

    -- Consecration
    if sim.cons_ready and sim.ttd > 4 then return "consecration" end

    -- Exorcism with Art of War (normal priority vs non-undead)
    if not sim.is_undead_or_demon and sim.art_of_war_up and sim.exo_ready then
        return "exorcism"
    end

    -- Holy Wrath (only vs undead/demons)
    if sim.is_undead_or_demon and sim.hw_ready then
        return "holy_wrath"
    end

    -- Divine Plea — weave in when mana is getting low
    -- At ~30% we risk not being able to cast core abilities
    -- At ~40% it's a good time to weave it in during a GCD gap
    if sim.plea_ready and sim.mana_pct < 40 then
        return "divine_plea"
    end

    return nil
end

local function GetRetributionRecommendations(addon)
    local recommendations = {}
    local s = state

    if not s.target.exists or not s.target.canAttack then
        return recommendations
    end

    ResetPaladinSim(s)

    -- Account for current GCD
    if sim.gcd_remains > 0 then
        SimulatePaladinTime(sim.gcd_remains)
    end

    for i = 1, 3 do
        local action = GetNextRetAbility()

        if action then
            addRec(recommendations, action)
            SimulateRetAbility(action)
        else
            -- Nothing ready — advance time (at least one GCD via framework)
            local waitTime = DH:SimWaitTime(sim, {
                sim.cs_cd, sim.judge_cd, sim.ds_cd, sim.cons_cd,
                sim.in_execute and sim.how_cd or 999,
            })

            -- Divine Plea fills GCD gaps when mana is low
            if sim.plea_ready and sim.mana_pct < 40 then
                addRec(recommendations, "divine_plea")
                sim.plea_ready = false
                sim.plea_cd = 60
                DH:SimGainManaPct(sim, 0.25)
                SimulatePaladinTime(sim.gcd)
            elseif waitTime < 999 then
                SimulatePaladinTime(waitTime + 0.01)
                action = GetNextRetAbility()
                if action then
                    addRec(recommendations, action)
                    SimulateRetAbility(action)
                end
            end
        end
    end

    return recommendations
end

-- ============================================================================
-- PROTECTION SIMULATION
-- ============================================================================

local function SimulateProtAbility(action)
    -- Spend mana via framework
    DH:SimSpendMana(sim, action)

    if action == "shield_of_righteousness" then
        sim.sor_ready = false
        sim.sor_cd = 6
    elseif action == "hammer_of_the_righteous" then
        sim.hotr_ready = false
        sim.hotr_cd = 6
    elseif action == "hammer_of_wrath" then
        sim.how_ready = false
        sim.how_cd = 6
    elseif action == "consecration" then
        sim.cons_ready = false
        sim.cons_cd = 8
    elseif action == "holy_shield" then
        sim.hs_ready = false
        sim.hs_cd = 8
        sim.holy_shield_up = true
        sim.holy_shield_remains = 10
    elseif action == "judgement_of_wisdom" then
        sim.judge_ready = false
        sim.judge_cd = sim.judge_base_cd
        DH:SimGainManaPct(sim, 0.25)
        sim.replenishment_remains = 15
    elseif action == "divine_plea" then
        sim.plea_ready = false
        sim.plea_cd = 60
        DH:SimGainManaPct(sim, 0.25)
    elseif action == "righteous_fury" then
        sim.righteous_fury_up = true
    end

    SimulatePaladinTime(sim.gcd)
end

local function GetNextProtAbility()
    -- Righteous Fury check
    if not sim.righteous_fury_up then
        return "righteous_fury"
    end

    -- SoR / HotR interleave (969 rotation)
    -- Cast SoR when HotR is coming off CD within 3s
    if sim.sor_ready and sim.hotr_cd <= 3 then
        return "shield_of_righteousness"
    end
    -- Cast HotR when SoR is coming off CD within 3s
    if sim.hotr_ready and sim.sor_cd <= 3 then
        return "hammer_of_the_righteous"
    end
    -- If both ready, prioritize SoR
    if sim.sor_ready then return "shield_of_righteousness" end
    if sim.hotr_ready then return "hammer_of_the_righteous" end

    -- Execute phase: Hammer of Wrath
    if sim.in_execute and sim.how_ready then
        return "hammer_of_wrath"
    end

    -- 9-second abilities (fill between SoR/HotR)
    if sim.cons_ready then return "consecration" end
    if sim.hs_ready then return "holy_shield" end
    if sim.judge_ready then return "judgement_of_wisdom" end

    -- Divine Plea when mana getting low
    if sim.plea_ready and sim.mana_pct < 40 then
        return "divine_plea"
    end

    return nil
end

local function GetProtectionRecommendations(addon)
    local recommendations = {}
    local s = state

    if not s.target.exists or not s.target.canAttack then
        return recommendations
    end

    ResetPaladinSim(s)

    -- Account for current GCD
    if sim.gcd_remains > 0 then
        SimulatePaladinTime(sim.gcd_remains)
    end

    for i = 1, 3 do
        local action = GetNextProtAbility()

        if action then
            addRec(recommendations, action)
            SimulateProtAbility(action)
        else
            -- Nothing ready — advance time (at least one GCD via framework)
            local waitTime = DH:SimWaitTime(sim, {
                sim.sor_cd, sim.hotr_cd, sim.cons_cd, sim.hs_cd, sim.judge_cd,
                sim.in_execute and sim.how_cd or 999,
            })

            if sim.plea_ready and sim.mana_pct < 40 then
                addRec(recommendations, "divine_plea")
                sim.plea_ready = false
                sim.plea_cd = 60
                DH:SimGainManaPct(sim, 0.25)
                SimulatePaladinTime(sim.gcd)
            elseif waitTime < 999 then
                SimulatePaladinTime(waitTime + 0.01)
                action = GetNextProtAbility()
                if action then
                    addRec(recommendations, action)
                    SimulateProtAbility(action)
                end
            end
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
