-- Core.lua
-- Priority rotation logic for DruidHelper (3.3.5a compatible)

local DH = DruidHelper
if not DH then return end

-- Only load for Druids
if select(2, UnitClass("player")) ~= "DRUID" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- ============================================================================
-- FERAL CAT ROTATION (WotLK 3.3.5a)
-- Based on the definitive WotLK feral guide with advanced tactics:
-- - SR/Rip desync logic (clip SR up to 10 sec early)
-- - Bearweaving (shift to bear when energy-starved)
-- - Lacerateweaving (maintain 5-stack Lacerate for max DPS)
-- ============================================================================

-- Simulated state for prediction (copy of real state values)
local sim = {}
local SIM_GCD = 1.0  -- Feral GCD (1.0 sec with talents)
local ENERGY_REGEN = 10  -- Energy per second
local FUROR_ENERGY = 40  -- Energy from 5/5 Furor when shifting to cat

-- Reset simulated state from real state
local function ResetSimState(s)
    sim.energy = s.energy.current
    sim.rage = s.rage.current
    sim.cp = s.combo_points.current
    sim.berserk = s.buff.berserk.up
    sim.clearcasting = s.buff.clearcasting.up
    sim.tf_ready = s.cooldown.tigers_fury.ready
    sim.tf_cd_remains = s.cooldown.tigers_fury.remains
    sim.sr_up = s.buff.savage_roar.up
    sim.sr_remains = s.buff.savage_roar.remains
    sim.rip_up = s.debuff.rip.up
    sim.rip_remains = s.debuff.rip.remains
    sim.rake_up = s.debuff.rake.up
    sim.rake_remains = s.debuff.rake.remains
    sim.mangle_up = s.debuff.mangle.up
    sim.mangle_remains = s.debuff.mangle.remains
    sim.bleed_debuff_up = s.debuff.bleed_debuff.up  -- External Mangle/Trauma
    sim.ttd = s.target.time_to_die
    sim.has_mangle_talent = s.talent.mangle.rank > 0
    sim.has_berserk_talent = s.talent.berserk.rank > 0
    sim.has_ooc_talent = s.talent.omen_of_clarity.rank > 0
    sim.has_ooc_glyph = s.glyph.omen_of_clarity and s.glyph.omen_of_clarity.enabled
    sim.has_furor = s.talent.furor.rank >= 5
    sim.berserk_ready = s.cooldown.berserk.ready
    sim.berserk_remains = s.buff.berserk.remains or 0
    sim.ff_ready = s.cooldown.faerie_fire_feral.ready
    sim.ff_cd_remains = s.cooldown.faerie_fire_feral.remains

    -- Bear form state
    sim.in_bear = s.bear_form
    sim.in_cat = s.cat_form
    sim.mangle_bear_ready = s.cooldown.mangle_bear.ready
    sim.mangle_bear_cd_remains = s.cooldown.mangle_bear.remains
    sim.lacerate_up = s.debuff.lacerate.up
    sim.lacerate_stacks = s.debuff.lacerate.stacks or 0
    sim.lacerate_remains = s.debuff.lacerate.remains

    -- Use actual GCD from game state
    sim.gcd = s.gcd or 1.0
    sim.gcd_remains = s.gcd_remains or 0
end

-- ============================================================================
-- SR/RIP DESYNC LOGIC
-- If Rip will expire shortly after SR, clip SR early to build 5 CP for Rip
-- ============================================================================

-- Check if we need to clip SR early to prevent Rip desync
-- Returns true if SR should be refreshed early (even if it has time remaining)
local function ShouldClipSRForDesync()
    -- Only relevant if both SR and Rip are up
    if not sim.sr_up or not sim.rip_up then
        return false
    end

    -- Time needed to build 5 CP (roughly 5 GCDs = 5 seconds minimum)
    local time_to_build_5cp = 5.0

    -- Scenario: SR expires, then we need to rebuild 5 CP, but Rip expires during that time
    -- If Rip expires within (SR_remains + time_to_build_5cp + 2), we have a conflict
    local conflict_window = sim.sr_remains + time_to_build_5cp + 2

    -- If Rip will expire during this window, we need to clip SR now
    if sim.rip_remains < conflict_window and sim.rip_remains > sim.sr_remains then
        -- Rip expires after SR but before we can rebuild 5 CP
        -- Check if clipping would be within 10 sec limit
        if sim.sr_remains <= 10 then
            return true
        end
    end

    return false
end

-- ============================================================================
-- BEARWEAVING LOGIC
-- Shift to bear when energy-starved to deal damage while regenerating
-- ============================================================================

-- Check if we should enter bear form for bearweaving
local function ShouldBearweave()
    -- Must have Furor talent (5/5 for 10 rage on bear shift)
    if not sim.has_furor then
        return false
    end

    -- Conditions from the guide:
    -- 1. Less than 40 energy
    if sim.energy >= 40 then
        return false
    end

    -- 2. No Clearcasting proc active (would waste free ability)
    if sim.clearcasting then
        return false
    end

    -- 3. More than 4.5 seconds until Rip expires (safety margin)
    if sim.rip_up and sim.rip_remains < 4.5 then
        return false
    end

    -- 4. Berserk is not active (spam cat abilities during Berserk)
    if sim.berserk then
        return false
    end

    -- 5. SR should have enough time (need to get back to cat and use abilities)
    if sim.sr_up and sim.sr_remains < 4 then
        return false
    end

    return true
end

-- Check if we should exit bear form back to cat
local function ShouldExitBear()
    -- Exit conditions:
    -- 1. More than 70 energy (approaching cap)
    if sim.energy > 70 then
        return true
    end

    -- 2. Rip will expire in less than 3 seconds
    if sim.rip_up and sim.rip_remains < 3 then
        return true
    end

    -- 3. Clearcasting is active (use it in cat form)
    if sim.clearcasting then
        return true
    end

    -- 4. SR about to expire
    if sim.sr_up and sim.sr_remains < 3 then
        return true
    end

    return false
end

-- Get next bear ability (Lacerateweave - maintains 5-stack Lacerate)
-- Focus purely on Lacerate bleed, exit to cat when it's healthy
local function GetNextBearAbility()
    local has_rage = sim.rage >= 13 or sim.clearcasting
    local lacerate_emergency = sim.lacerate_up and sim.lacerate_remains < 3
    local lacerate_needs_stack = not sim.lacerate_up or sim.lacerate_stacks < 5
    local lacerate_needs_refresh = sim.lacerate_up and sim.lacerate_remains < 9

    -- Priority 1: Emergency Lacerate refresh (don't let stacks fall off!)
    if has_rage and lacerate_emergency then
        return "lacerate"
    end

    -- Priority 2: Exit if > 70 energy or Rip < 3 sec
    if sim.energy > 70 or (sim.rip_up and sim.rip_remains < 3) then
        return "cat_form"
    end

    -- Priority 3: Build Lacerate stacks to 5
    if has_rage and lacerate_needs_stack then
        return "lacerate"
    end

    -- Priority 4: Refresh Lacerate if < 9 sec (comfortable window)
    if has_rage and lacerate_needs_refresh then
        return "lacerate"
    end

    -- Priority 5: Lacerate is healthy (5 stacks, 9+ sec) - exit to cat
    -- Now we can leave and use any CC proc in cat form
    if sim.lacerate_up and sim.lacerate_stacks == 5 and sim.lacerate_remains >= 9 then
        return "cat_form"
    end

    -- Priority 6: Low rage - exit to cat (can't do anything useful)
    -- Note: CC does NOT trigger exit - Lacerate maintenance takes priority
    if sim.rage < 13 then
        return "cat_form"
    end

    -- Priority 7: Still have rage, keep stacking/refreshing Lacerate
    return "lacerate"
end

-- Wrapper for bear ability
local function GetNextBearweaveAbility()
    return GetNextBearAbility()
end

-- ============================================================================
-- CAT ROTATION
-- ============================================================================

-- Get next priority ability for single target
local function GetNextCatAbility()
    local shred_cost = sim.berserk and 21 or 42
    local mangle_cost = sim.berserk and 17 or 35
    local rake_cost = sim.berserk and 17 or 35
    local rip_cost = sim.berserk and 15 or 30
    local sr_cost = sim.berserk and 12 or 25

    -- Pandemic windows: refresh when < X seconds remain (don't wait until expired)
    local rake_needs_refresh = not sim.rake_up or sim.rake_remains < 3
    local rip_needs_refresh = not sim.rip_up or sim.rip_remains < 2
    local sr_needs_refresh = not sim.sr_up or sim.sr_remains < 3
    -- Skip Mangle if external bleed debuff (Trauma/other druid's Mangle) is up
    local mangle_needs_refresh = not sim.bleed_debuff_up and (not sim.mangle_up or sim.mangle_remains < 3)

    -- SR/Rip desync check: clip SR early if Rip will expire shortly after SR
    local sr_desync_clip = ShouldClipSRForDesync()

    -- Ferocious Bite conditions (should be rare - only when safe)
    local bite_cost = sim.berserk and 17 or 35
    local min_bite_rip_remains = 10  -- Need 10+ sec on Rip to safely Bite
    local min_bite_sr_remains = 8    -- Need 8+ sec on SR to safely Bite

    -- bite_at_end: Use bite instead of Rip at end of fight
    local bite_at_end = sim.cp == 5 and (sim.ttd < 10 or (sim.rip_up and sim.ttd - sim.rip_remains < 10))

    -- bite_before_rip: Safe to bite when Rip and SR have good duration
    local bite_before_rip = sim.cp == 5 and sim.rip_up and sim.sr_up
        and sim.rip_remains >= min_bite_rip_remains
        and sim.sr_remains >= min_bite_sr_remains

    -- Can bite: either end of fight or safe window, not wasting clearcasting
    -- NEVER during Berserk - spam Shred instead to maximize energy discount
    local can_bite = (bite_at_end or bite_before_rip)
        and not sim.clearcasting
        and not sim.berserk  -- No bite during Berserk
        and sim.energy >= bite_cost
        and sim.energy < 67  -- Don't bite at high energy

    -- Priority 1: Tiger's Fury when < 40 Energy
    if sim.energy < 40 and sim.tf_ready and not sim.berserk then
        return "tigers_fury"
    end

    -- Priority 2: Berserk when TF on CD for 15+ sec
    if sim.has_berserk_talent and sim.berserk_ready then
        if not sim.tf_ready and sim.tf_cd_remains >= 15 then
            return "berserk"
        end
    end

    -- Priority 3: Savage Roar - either needs normal refresh OR desync clip
    if (sr_needs_refresh or sr_desync_clip) and sim.cp >= 1 and sim.energy >= sr_cost then
        return "savage_roar"
    end

    -- Priority 4: Mangle when debuff needs refresh
    if sim.has_mangle_talent and mangle_needs_refresh and sim.energy >= mangle_cost then
        return "mangle_cat"
    end

    -- Priority 5: Rip at 5 CP when needs refresh (but not at end of fight)
    if sim.cp == 5 and rip_needs_refresh and sim.ttd >= 10 and sim.energy >= rip_cost and not bite_at_end then
        return "rip"
    end

    -- Priority 5b: Ferocious Bite at 5 CP when safe (Rip/SR have good duration) or end of fight
    if can_bite then
        return "ferocious_bite"
    end

    -- Priority 6: Rake when needs refresh
    if rake_needs_refresh and sim.ttd > 9 and sim.energy >= rake_cost then
        return "rake"
    end

    -- Priority 7: Clearcasting proc -> Shred (free shred!)
    if sim.clearcasting then
        return "shred"
    end

    -- Priority 8: Faerie Fire (Feral) for OoC procs
    -- Use FF before Shred if not at max energy (avoid capping during GCD)
    -- Skip during Berserk (spam abilities)
    if sim.ff_ready and not sim.berserk and sim.energy < 90 then
        return "faerie_fire_feral"
    end

    -- Priority 9: Shred (if we have energy)
    if sim.energy >= shred_cost then
        return "shred"
    end

    -- Priority 10: Bearweave if conditions met (energy starved, no CC, Rip safe, no Berserk)
    local bearweave_enabled = DH.db and DH.db.feral_cat and DH.db.feral_cat.bearweave
    if bearweave_enabled and ShouldBearweave() then
        return "dire_bear_form"
    end

    -- Not enough energy - wait
    return nil
end

-- Simulate time passing (tick down buffs/debuffs, regen energy)
local function SimulateTime(seconds)
    if seconds <= 0 then return end

    -- Energy regen
    sim.energy = math.min(100, sim.energy + (ENERGY_REGEN * seconds))

    -- Tick down buff/debuff timers
    if sim.sr_remains > 0 then
        sim.sr_remains = sim.sr_remains - seconds
        if sim.sr_remains <= 0 then
            sim.sr_up = false
            sim.sr_remains = 0
        end
    end

    if sim.rip_remains > 0 then
        sim.rip_remains = sim.rip_remains - seconds
        if sim.rip_remains <= 0 then
            sim.rip_up = false
            sim.rip_remains = 0
        end
    end

    if sim.rake_remains > 0 then
        sim.rake_remains = sim.rake_remains - seconds
        if sim.rake_remains <= 0 then
            sim.rake_up = false
            sim.rake_remains = 0
        end
    end

    if sim.mangle_remains > 0 then
        sim.mangle_remains = sim.mangle_remains - seconds
        if sim.mangle_remains <= 0 then
            sim.mangle_up = false
            sim.mangle_remains = 0
        end
    end

    -- Tick down cooldowns
    if sim.tf_cd_remains > 0 then
        sim.tf_cd_remains = sim.tf_cd_remains - seconds
        if sim.tf_cd_remains <= 0 then
            sim.tf_ready = true
            sim.tf_cd_remains = 0
        end
    end

    if sim.ff_cd_remains > 0 then
        sim.ff_cd_remains = sim.ff_cd_remains - seconds
        if sim.ff_cd_remains <= 0 then
            sim.ff_ready = true
            sim.ff_cd_remains = 0
        end
    end

    if sim.mangle_bear_cd_remains > 0 then
        sim.mangle_bear_cd_remains = sim.mangle_bear_cd_remains - seconds
        if sim.mangle_bear_cd_remains <= 0 then
            sim.mangle_bear_ready = true
            sim.mangle_bear_cd_remains = 0
        end
    end

    -- Tick down Lacerate
    if sim.lacerate_remains > 0 then
        sim.lacerate_remains = sim.lacerate_remains - seconds
        if sim.lacerate_remains <= 0 then
            sim.lacerate_up = false
            sim.lacerate_stacks = 0
            sim.lacerate_remains = 0
        end
    end

    -- Tick down GCD
    if sim.gcd_remains > 0 then
        sim.gcd_remains = sim.gcd_remains - seconds
        if sim.gcd_remains < 0 then sim.gcd_remains = 0 end
    end

    -- Berserk duration (15 sec)
    if sim.berserk and sim.berserk_remains then
        sim.berserk_remains = sim.berserk_remains - seconds
        if sim.berserk_remains <= 0 then
            sim.berserk = false
            sim.berserk_remains = 0
        end
    end
end

-- Simulate using an ability (update sim state)
local function SimulateAbility(action)
    local shred_cost = sim.berserk and 21 or 42
    local mangle_cost = sim.berserk and 17 or 35
    local rake_cost = sim.berserk and 17 or 35
    local rip_cost = sim.berserk and 15 or 30
    local sr_cost = sim.berserk and 12 or 25

    if action == "tigers_fury" then
        sim.energy = math.min(100, sim.energy + 60)
        sim.tf_ready = false
        sim.tf_cd_remains = 30

    elseif action == "berserk" then
        sim.berserk = true
        sim.berserk_ready = false

    elseif action == "savage_roar" then
        sim.energy = sim.energy - sr_cost
        sim.sr_up = true
        sim.sr_remains = 14 + (sim.cp * 5) -- Base 14 + 5 per CP
        sim.cp = 0

    elseif action == "mangle_cat" then
        sim.energy = sim.energy - mangle_cost
        sim.mangle_up = true
        sim.mangle_remains = 60
        sim.cp = math.min(5, sim.cp + 1)
        if sim.clearcasting then sim.clearcasting = false end

    elseif action == "shred" then
        if not sim.clearcasting then
            sim.energy = sim.energy - shred_cost
        end
        sim.cp = math.min(5, sim.cp + 1)
        sim.clearcasting = false

    elseif action == "rake" then
        sim.energy = sim.energy - rake_cost
        sim.rake_up = true
        sim.rake_remains = 9
        sim.cp = math.min(5, sim.cp + 1)
        if sim.clearcasting then sim.clearcasting = false end

    elseif action == "rip" then
        sim.energy = sim.energy - rip_cost
        sim.rip_up = true
        sim.rip_remains = 12 + (sim.cp * 2) -- Roughly
        sim.cp = 0

    elseif action == "faerie_fire_feral" then
        -- No energy cost, 6 sec CD
        sim.ff_ready = false
        sim.ff_cd_remains = 6

    elseif action == "ferocious_bite" then
        -- Costs 35 energy base (17 during berserk) + converts up to 30 extra energy to damage
        local bite_cost = sim.berserk and 17 or 35
        local extra_energy = math.min(30, sim.energy - bite_cost)
        sim.energy = sim.energy - bite_cost - extra_energy
        sim.cp = 0
        if sim.clearcasting then sim.clearcasting = false end

    elseif action == "swipe_cat" then
        local swipe_cost = sim.berserk and 25 or 50
        if not sim.clearcasting then
            sim.energy = sim.energy - swipe_cost
        end
        sim.clearcasting = false
        -- Swipe doesn't generate combo points

    -- Form shifts
    elseif action == "dire_bear_form" then
        sim.in_bear = true
        sim.in_cat = false
        -- Furor gives 10 rage when shifting to bear (5/5)
        if sim.has_furor then
            sim.rage = 10
        end

    elseif action == "cat_form" then
        sim.in_cat = true
        sim.in_bear = false
        -- Furor gives 40 energy when shifting to cat (5/5)
        if sim.has_furor then
            sim.energy = math.min(100, sim.energy + FUROR_ENERGY)
        end

    -- Bear abilities
    elseif action == "mangle_bear" then
        sim.rage = sim.rage - 15
        sim.mangle_up = true
        sim.mangle_remains = 60
        sim.mangle_bear_ready = false
        sim.mangle_bear_cd_remains = 6
        if sim.clearcasting then sim.clearcasting = false end

    elseif action == "lacerate" then
        if not sim.clearcasting then
            sim.rage = sim.rage - 13
        end
        sim.lacerate_up = true
        sim.lacerate_stacks = math.min(5, sim.lacerate_stacks + 1)
        sim.lacerate_remains = 15
        sim.clearcasting = false

    elseif action == "maul" then
        -- Maul is queued for next swing, costs 15 rage
        -- For sim purposes, just deduct rage
        sim.rage = sim.rage - 15
        if sim.clearcasting then sim.clearcasting = false end
    end

    -- Simulate ~1 GCD passing (1 second)
    SimulateTime(1.0)
end

function ns.GetFeralCatRecommendations(addon)
    local recommendations = {}
    local s = state

    if not s.target.exists or not s.target.canAttack then
        return recommendations
    end

    local function addRec(key)
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

    -- Initialize simulated state from real state
    ResetSimState(s)

    -- For first recommendation, account for current GCD remaining
    if sim.gcd_remains > 0 then
        SimulateTime(sim.gcd_remains)
    end

    -- Get recommendations by simulating each ability
    for i = 1, 3 do
        local action

        -- If we're in bear form (bearweaving), use bear rotation
        if sim.in_bear then
            action = GetNextBearweaveAbility()
        else
            action = GetNextCatAbility()
        end

        if action then
            addRec(action)
            SimulateAbility(action)
        else
            -- No action available (low energy in cat form)
            if sim.in_bear then
                -- In bear with nothing to do, just wait a bit
                SimulateTime(1.0)
            else
                -- Find the cheapest maintenance ability that needs refresh
                local rake_cost = sim.berserk and 17 or 35
                local mangle_cost = sim.berserk and 17 or 35
                local sr_cost = sim.berserk and 12 or 25
                local rip_cost = sim.berserk and 15 or 30
                local shred_cost = sim.berserk and 21 or 42

                local needed_energy = shred_cost  -- Default to shred
                local rake_needs_refresh = not sim.rake_up or sim.rake_remains < 3
                local mangle_needs_refresh = not sim.bleed_debuff_up and (not sim.mangle_up or sim.mangle_remains < 3)
                local sr_needs_refresh = not sim.sr_up or sim.sr_remains < 3
                local rip_needs_refresh = not sim.rip_up or sim.rip_remains < 2

                -- Find lowest energy cost for what we need
                if sr_needs_refresh and sim.cp >= 1 then needed_energy = math.min(needed_energy, sr_cost) end
                if mangle_needs_refresh and sim.has_mangle_talent then needed_energy = math.min(needed_energy, mangle_cost) end
                if rake_needs_refresh then needed_energy = math.min(needed_energy, rake_cost) end
                if rip_needs_refresh and sim.cp == 5 then needed_energy = math.min(needed_energy, rip_cost) end

                -- Wait for enough energy
                local time_to_energy = math.max(0, (needed_energy - sim.energy) / ENERGY_REGEN)
                SimulateTime(time_to_energy + 0.1)

                -- Try again after waiting
                action = GetNextCatAbility()
                if action then
                    addRec(action)
                    SimulateAbility(action)
                else
                    -- Still nothing, just wait more
                    SimulateTime(1.0)
                end
            end
        end
    end

    return recommendations
end

-- ============================================================================
-- FERAL BEAR ROTATION
-- ============================================================================

function ns.GetFeralBearRecommendations(addon)
    local recommendations = {}
    local s = state
    local settings = addon.db.feral_bear

    if not s.target.exists or not s.target.canAttack then
        return recommendations
    end

    local rage = s.rage.current
    local lacerate_up = s.debuff.lacerate.up
    local lacerate_stack = s.debuff.lacerate.stacks or 0
    local lacerate_remains = s.debuff.lacerate.remains
    local mangle_ready = s.cooldown.mangle_bear.ready
    local ttd = s.target.time_to_die

    local function addRec(key)
        local ability = class.abilities[key]
        if ability then
            table.insert(recommendations, {
                ability = key,
                texture = ability.texture,
                name = ability.name,
            })
        end
    end

    -- 1. Faerie Fire for OoC procs
    if s.glyph.omen_of_clarity.enabled and not s.buff.clearcasting.up and s.cooldown.faerie_fire_feral.ready then
        addRec("faerie_fire_feral")
        if #recommendations >= 4 then return recommendations end
    end

    -- 2. Berserk
    if s.talent.berserk.rank > 0 and s.cooldown.berserk.ready then
        addRec("berserk")
        if #recommendations >= 4 then return recommendations end
    end

    -- 3. Maul if excess rage
    if rage > 60 then
        addRec("maul")
        if #recommendations >= 4 then return recommendations end
    end

    -- 4. Emergency Lacerate
    if lacerate_up and lacerate_remains < 4.5 then
        addRec("lacerate")
        if #recommendations >= 4 then return recommendations end
    end

    -- 5. Mangle
    if s.talent.mangle.rank > 0 and mangle_ready then
        addRec("mangle_bear")
        if #recommendations >= 4 then return recommendations end
    end

    -- 6. Faerie Fire for debuff
    if s.cooldown.faerie_fire_feral.ready and not s.debuff.faerie_fire_feral.up then
        addRec("faerie_fire_feral")
        if #recommendations >= 4 then return recommendations end
    end

    -- 7. Build Lacerate stacks
    if not lacerate_up or lacerate_stack < 5 or lacerate_remains < 8 then
        addRec("lacerate")
        if #recommendations >= 4 then return recommendations end
    end

    -- 8. Swipe if excess rage
    if rage > 60 then
        addRec("swipe_bear")
        if #recommendations >= 4 then return recommendations end
    end

    -- Filler
    if #recommendations < 4 then
        addRec("lacerate")
    end

    return recommendations
end

-- ============================================================================
-- BALANCE (MOONKIN) ROTATION
-- ============================================================================

function ns.GetBalanceRecommendations(addon)
    local recommendations = {}
    local s = state

    if not s.target.exists or not s.target.canAttack then
        return recommendations
    end

    local function addRec(key)
        local ability = class.abilities[key]
        if ability then
            table.insert(recommendations, {
                ability = key,
                texture = ability.texture,
                name = ability.name,
            })
        end
    end

    -- Eclipse state
    local lunar_up = s.buff.eclipse_lunar.up
    local solar_up = s.buff.eclipse_solar.up
    local elunes_wrath_up = s.buff.elunes_wrath.up

    -- Eclipse ICD (30 seconds)
    local now = s.now
    local lunar_can_proc = s.buff.eclipse_lunar.last_applied == 0 or (now - s.buff.eclipse_lunar.last_applied) >= 30
    local solar_can_proc = s.buff.eclipse_solar.last_applied == 0 or (now - s.buff.eclipse_solar.last_applied) >= 30

    local spam_now = lunar_up or solar_up
    local fish_now = not spam_now
    local lunar_fish = fish_now and lunar_can_proc
    local solar_fish = fish_now and (solar_can_proc or not lunar_can_proc)

    -- Instant Starfire from Elune's Wrath
    if elunes_wrath_up then
        addRec("starfire")
        if #recommendations >= 4 then return recommendations end
    end

    -- Force of Nature
    if s.talent.force_of_nature.rank > 0 and s.cooldown.force_of_nature.ready then
        addRec("force_of_nature")
        if #recommendations >= 4 then return recommendations end
    end

    -- Starfall
    if s.talent.starfall.rank > 0 and s.cooldown.starfall.ready then
        addRec("starfall")
        if #recommendations >= 4 then return recommendations end
    end

    -- Faerie Fire (improved)
    if s.talent.improved_faerie_fire.rank > 0 and not s.debuff.faerie_fire.up then
        addRec("faerie_fire")
        if #recommendations >= 4 then return recommendations end
    end

    -- Insect Swarm
    if s.talent.insect_swarm.rank > 0 and not s.debuff.insect_swarm.up then
        addRec("insect_swarm")
        if #recommendations >= 4 then return recommendations end
    end

    -- SPAM PHASE
    if spam_now then
        if solar_up then
            addRec("wrath")
            if #recommendations >= 4 then return recommendations end
        end
        if lunar_up then
            addRec("starfire")
            if #recommendations >= 4 then return recommendations end
        end
    end

    -- FISHING PHASE
    if fish_now then
        if lunar_fish and not s.debuff.moonfire.up then
            addRec("moonfire")
            if #recommendations >= 4 then return recommendations end
        end
        if lunar_fish then
            addRec("wrath")
            if #recommendations >= 4 then return recommendations end
        end
        if solar_fish then
            addRec("starfire")
            if #recommendations >= 4 then return recommendations end
        end
    end

    -- Default
    if #recommendations < 4 then
        addRec("starfire")
    end

    return recommendations
end
