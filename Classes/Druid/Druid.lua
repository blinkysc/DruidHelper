-- Classes/Druid/Druid.lua
-- Druid class module: ability definitions + registration of all Druid-specific data

local DH = PriorityHelper
if not DH then return end

-- Only load for Druids
if select(2, UnitClass("player")) ~= "DRUID" then
    return
end

local ns = DH.ns
local class = DH.Class

-- ============================================================================
-- SPELL IDS (max rank for 3.3.5a)
-- ============================================================================

local SPELLS = {
    -- Forms
    CAT_FORM = 768,
    DIRE_BEAR_FORM = 9634,
    MOONKIN_FORM = 24858,

    -- Cat abilities
    MANGLE_CAT = 48566,
    SHRED = 48572,
    RAKE = 48574,
    RIP = 49800,
    SAVAGE_ROAR = 52610,
    FEROCIOUS_BITE = 48577,
    SWIPE_CAT = 62078,
    TIGERS_FURY = 50213,
    MAIM = 49802,

    -- Bear abilities
    MANGLE_BEAR = 48564,
    SWIPE_BEAR = 48562,
    LACERATE = 48568,
    MAUL = 48480,
    GROWL = 6795,
    ENRAGE = 5229,

    -- Shared
    FAERIE_FIRE_FERAL = 16857,
    BERSERK = 50334,
    SURVIVAL_INSTINCTS = 61336,
    BARKSKIN = 22812,

    -- Balance abilities
    WRATH = 48461,
    STARFIRE = 48465,
    MOONFIRE = 48463,
    INSECT_SWARM = 48468,
    STARFALL = 48505,
    TYPHOON = 61384,
    FORCE_OF_NATURE = 33831,
    HURRICANE = 48467,
    FAERIE_FIRE = 770,
}

ns.SPELLS = SPELLS

-- ============================================================================
-- ABILITY DEFINITIONS
-- ============================================================================

class.abilities = {
    -- Forms
    cat_form = {
        id = SPELLS.CAT_FORM,
        name = "Cat Form",
        texture = 132115,
    },
    dire_bear_form = {
        id = SPELLS.DIRE_BEAR_FORM,
        name = "Dire Bear Form",
        texture = 132276,
    },
    moonkin_form = {
        id = SPELLS.MOONKIN_FORM,
        name = "Moonkin Form",
        texture = 136036,
    },

    -- Cat Abilities
    mangle_cat = {
        id = SPELLS.MANGLE_CAT,
        name = "Mangle (Cat)",
        texture = 132135,
        energy_cost = 40,
    },
    shred = {
        id = SPELLS.SHRED,
        name = "Shred",
        texture = 136231,
        energy_cost = 60,
    },
    rake = {
        id = SPELLS.RAKE,
        name = "Rake",
        texture = 132122,
        energy_cost = 40,
    },
    rip = {
        id = SPELLS.RIP,
        name = "Rip",
        texture = 132152,
        energy_cost = 30,
    },
    savage_roar = {
        id = SPELLS.SAVAGE_ROAR,
        name = "Savage Roar",
        texture = 236167,
        energy_cost = 25,
    },
    ferocious_bite = {
        id = SPELLS.FEROCIOUS_BITE,
        name = "Ferocious Bite",
        texture = 132127,
        energy_cost = 35,
    },
    swipe_cat = {
        id = SPELLS.SWIPE_CAT,
        name = "Swipe (Cat)",
        texture = 134296,
        energy_cost = 50,
    },
    tigers_fury = {
        id = SPELLS.TIGERS_FURY,
        name = "Tiger's Fury",
        texture = 132242,
    },
    berserk = {
        id = SPELLS.BERSERK,
        name = "Berserk",
        texture = 236149,
    },
    faerie_fire_feral = {
        id = SPELLS.FAERIE_FIRE_FERAL,
        name = "Faerie Fire (Feral)",
        texture = 136033,
    },
    maim = {
        id = SPELLS.MAIM,
        name = "Maim",
        texture = 132134,
        energy_cost = 35,
    },

    -- Bear Abilities
    mangle_bear = {
        id = SPELLS.MANGLE_BEAR,
        name = "Mangle (Bear)",
        texture = 132135,
        rage_cost = 15,
    },
    swipe_bear = {
        id = SPELLS.SWIPE_BEAR,
        name = "Swipe (Bear)",
        texture = 134296,
        rage_cost = 15,
    },
    lacerate = {
        id = SPELLS.LACERATE,
        name = "Lacerate",
        texture = 132131,
        rage_cost = 13,
    },
    maul = {
        id = SPELLS.MAUL,
        name = "Maul",
        texture = 132136,
        rage_cost = 15,
    },
    enrage = {
        id = SPELLS.ENRAGE,
        name = "Enrage",
        texture = 132126,
    },
    growl = {
        id = SPELLS.GROWL,
        name = "Growl",
        texture = 132270,
    },
    survival_instincts = {
        id = SPELLS.SURVIVAL_INSTINCTS,
        name = "Survival Instincts",
        texture = 236169,
    },
    barkskin = {
        id = SPELLS.BARKSKIN,
        name = "Barkskin",
        texture = 136097,
    },

    -- Balance Abilities
    wrath = {
        id = SPELLS.WRATH,
        name = "Wrath",
        texture = 136006,
    },
    starfire = {
        id = SPELLS.STARFIRE,
        name = "Starfire",
        texture = 135753,
    },
    moonfire = {
        id = SPELLS.MOONFIRE,
        name = "Moonfire",
        texture = 136096,
    },
    insect_swarm = {
        id = SPELLS.INSECT_SWARM,
        name = "Insect Swarm",
        texture = 136045,
    },
    starfall = {
        id = SPELLS.STARFALL,
        name = "Starfall",
        texture = 236168,
    },
    typhoon = {
        id = SPELLS.TYPHOON,
        name = "Typhoon",
        texture = 236170,
    },
    force_of_nature = {
        id = SPELLS.FORCE_OF_NATURE,
        name = "Force of Nature",
        texture = 132129,
    },
    hurricane = {
        id = SPELLS.HURRICANE,
        name = "Hurricane",
        texture = 136018,
    },
    faerie_fire = {
        id = SPELLS.FAERIE_FIRE,
        name = "Faerie Fire",
        texture = 136033,
    },
}

-- Create name mapping and get textures from GetSpellInfo (3.3.5a compatible)
for key, ability in pairs(class.abilities) do
    ability.key = key
    class.abilityByName[ability.name] = ability
    if ability.id then
        local name, rank, icon = GetSpellInfo(ability.id)
        if icon then
            ability.texture = icon
        end
    end
end

-- Helper to get texture
function ns.GetAbilityTexture(key)
    local ability = class.abilities[key]
    if ability then
        if not ability.texture and ability.id then
            local _, _, icon = GetSpellInfo(ability.id)
            ability.texture = icon
        end
        return ability.texture or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- ============================================================================
-- REGISTER DRUID DATA INTO FRAMEWORK
-- ============================================================================

-- GCD reference spell (Rake)
DH:RegisterGCDSpell(SPELLS.RAKE)

-- Melee abilities (for UI range overlay)
DH:RegisterMeleeAbilities({
    "shred", "mangle_cat", "mangle_bear", "rake", "rip",
    "swipe_cat", "swipe_bear", "lacerate", "maul", "ferocious_bite",
})

-- Buffs to track
DH:RegisterBuffs({
    "cat_form", "dire_bear_form", "bear_form", "moonkin_form", "travel_form",
    "prowl", "shadowmeld",
    "savage_roar", "tigers_fury", "berserk", "clearcasting", "predators_swiftness",
    "enrage", "frenzied_regeneration", "survival_instincts", "barkskin",
    "eclipse_lunar", "eclipse_solar", "natures_grace", "owlkin_frenzy", "elunes_wrath",
    "mark_of_the_wild", "gift_of_the_wild", "thorns",
    "maul",
})

-- Debuffs to track
DH:RegisterDebuffs({
    "rake", "rip", "lacerate", "mangle", "faerie_fire", "faerie_fire_feral",
    "moonfire", "insect_swarm",
    "pounce", "pounce_bleed", "maim",
    "demoralizing_roar", "infected_wounds",
    "armor_reduction", "major_armor_reduction", "shattering_throw",
    "bleed", "bleed_debuff",
    "training_dummy",
})

-- Cooldowns
DH:RegisterCooldowns({
    tigers_fury = 50213,
    berserk = 50334,
    survival_instincts = 61336,
    barkskin = 22812,
    faerie_fire_feral = 16857,
    feral_charge_cat = 49376,
    feral_charge_bear = 16979,
    mangle_bear = 48564,
    starfall = 48505,
    force_of_nature = 33831,
    typhoon = 50516,
    innervate = 29166,
    rebirth = 48477,
    enrage = 5229,
    frenzied_regeneration = 22842,
    challenging_roar = 5209,
    growl = 6795,
    bash = 8983,
    maim = 49802,
})

-- Talents
DH:RegisterTalents({
    -- Balance
    { 1, 1, "starlight_wrath" },
    { 1, 3, "natures_majesty" },
    { 1, 5, "brambles" },
    { 1, 6, "natures_grace" },
    { 1, 7, "natures_splendor" },
    { 1, 8, "natures_reach" },
    { 1, 10, "moonglow" },
    { 1, 11, "vengeance" },
    { 1, 12, "celestial_focus" },
    { 1, 13, "lunar_guidance" },
    { 1, 14, "insect_swarm" },
    { 1, 16, "moonfury" },
    { 1, 17, "balance_of_power" },
    { 1, 18, "moonkin_form" },
    { 1, 19, "improved_moonkin_form" },
    { 1, 20, "improved_faerie_fire" },
    { 1, 21, "owlkin_frenzy" },
    { 1, 23, "eclipse" },
    { 1, 25, "force_of_nature" },
    { 1, 26, "gale_winds" },
    { 1, 27, "earth_and_moon" },
    { 1, 28, "starfall" },

    -- Feral
    { 2, 1, "ferocity" },
    { 2, 2, "feral_aggression" },
    { 2, 3, "feral_instinct" },
    { 2, 4, "savage_fury" },
    { 2, 5, "thick_hide" },
    { 2, 6, "feral_swiftness" },
    { 2, 7, "survival_instincts" },
    { 2, 8, "sharpened_claws" },
    { 2, 9, "shredding_attacks" },
    { 2, 10, "predatory_strikes" },
    { 2, 11, "primal_fury" },
    { 2, 12, "primal_precision" },
    { 2, 13, "brutal_impact" },
    { 2, 14, "feral_charge" },
    { 2, 17, "heart_of_the_wild" },
    { 2, 19, "leader_of_the_pack" },
    { 2, 23, "predatory_instincts" },
    { 2, 24, "infected_wounds" },
    { 2, 25, "king_of_the_jungle" },
    { 2, 26, "mangle" },
    { 2, 27, "improved_mangle" },
    { 2, 28, "rend_and_tear" },
    { 2, 29, "primal_gore" },
    { 2, 30, "berserk" },

    -- Restoration
    { 3, 1, "improved_mark_of_the_wild" },
    { 3, 3, "furor" },
    { 3, 4, "naturalist" },
    { 3, 6, "natural_shapeshifter" },
    { 3, 8, "intensity" },
    { 3, 9, "omen_of_clarity" },
    { 3, 10, "master_shapeshifter" },
})

-- Glyphs
DH:RegisterGlyphs({
    [54815] = "shred",
    [54818] = "rip",
    [54821] = "rake",
    [63055] = "savage_roar",
    [62969] = "berserk",
    [54813] = "mangle",
    [54811] = "maul",
    [413895] = "omen_of_clarity",
    [54828] = "starfall",
    [54845] = "starfire",
    [54829] = "moonfire",
    [62135] = "typhoon",
})

-- Buff spell ID -> key mapping
DH:RegisterBuffMap({
    [768] = "cat_form",
    [9634] = "dire_bear_form",
    [5487] = "bear_form",
    [24858] = "moonkin_form",
    [52610] = "savage_roar",
    [50213] = "tigers_fury",
    [50334] = "berserk",
    [16870] = "clearcasting",
    [69369] = "predators_swiftness",
    [5229] = "enrage",
    [22842] = "frenzied_regeneration",
    [61336] = "survival_instincts",
    [22812] = "barkskin",
    [48518] = "eclipse_lunar",
    [48517] = "eclipse_solar",
    [16886] = "natures_grace",
    [48391] = "owlkin_frenzy",
    [60433] = "elunes_wrath",
    [1126] = "mark_of_the_wild",
    [21849] = "gift_of_the_wild",
    [467] = "thorns",
    [5215] = "prowl",
})

-- Debuff spell ID -> key mapping (player-applied)
DH:RegisterDebuffMap({
    -- Rake (all ranks)
    [48574] = "rake", [48573] = "rake", [27003] = "rake", [9904] = "rake",
    [9752] = "rake", [1824] = "rake", [1823] = "rake", [1822] = "rake",
    -- Rip (all ranks)
    [49800] = "rip", [49799] = "rip", [27008] = "rip", [9896] = "rip",
    [9894] = "rip", [6800] = "rip", [1079] = "rip",
    -- Lacerate (all ranks)
    [48568] = "lacerate", [48567] = "lacerate", [33745] = "lacerate",
    -- Mangle (Cat all ranks)
    [48566] = "mangle", [48565] = "mangle", [33983] = "mangle",
    [33982] = "mangle", [33876] = "mangle",
    -- Mangle (Bear all ranks)
    [48564] = "mangle", [48563] = "mangle", [33987] = "mangle",
    [33986] = "mangle", [33878] = "mangle",
    -- Others
    [770] = "faerie_fire",
    [16857] = "faerie_fire_feral",
    [48463] = "moonfire", [48462] = "moonfire", [26988] = "moonfire",
    [48468] = "insect_swarm", [48467] = "insect_swarm", [27013] = "insect_swarm",
    [49803] = "pounce",
    [49802] = "maim",
    [48560] = "demoralizing_roar",
    [48485] = "infected_wounds",
})

-- Debuff name patterns (fallback matching)
DH:RegisterDebuffNamePatterns({
    { "mangle", "mangle" },
    { "rake", "rake" },
    { "rip", "rip" },
    { "lacerate", "lacerate" },
    { "faerie fire.*feral", "faerie_fire_feral" },
    { "faerie fire", "faerie_fire" },
    { "moonfire", "moonfire" },
    { "insect swarm", "insect_swarm" },
})

-- External debuff mapping (from other players)
DH:RegisterExternalDebuffMap({
    [47467] = "armor_reduction", -- Sunder Armor
    [8647] = "armor_reduction",  -- Expose Armor
    [55754] = "armor_reduction", -- Acid Spit
    -- Trauma (Arms Warrior)
    [46857] = "bleed_debuff",
    -- Mangle (Bear) from other druids
    [48564] = "bleed_debuff", [48563] = "bleed_debuff",
    [33987] = "bleed_debuff", [33986] = "bleed_debuff", [33878] = "bleed_debuff",
    -- Mangle (Cat) from other druids
    [48566] = "bleed_debuff", [48565] = "bleed_debuff",
    [33983] = "bleed_debuff", [33982] = "bleed_debuff", [33876] = "bleed_debuff",
})

DH:RegisterExternalDebuffNamePatterns({
    { "sunder", "armor_reduction" },
    { "expose", "armor_reduction" },
    { "mangle", "bleed_debuff" },
    { "trauma", "bleed_debuff" },
})

-- ============================================================================
-- FORM HANDLERS
-- ============================================================================

-- Form 1: Bear
DH:RegisterFormHandler(1, function(state)
    state.bear_form = true
    state.buff.dire_bear_form.expires = state.now + 3600
    state.buff.bear_form.expires = state.now + 3600
end)

-- Form 3: Cat
DH:RegisterFormHandler(3, function(state)
    state.cat_form = true
    state.buff.cat_form.expires = state.now + 3600
end)

-- Form 5: Moonkin
DH:RegisterFormHandler(5, function(state)
    state.moonkin_form = true
    state.buff.moonkin_form.expires = state.now + 3600
end)

-- ============================================================================
-- SPEC DETECTION
-- ============================================================================

DH:RegisterSpecDetector(function()
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
end)

-- ============================================================================
-- DEFAULT SETTINGS (class-specific)
-- ============================================================================

DH:RegisterDefaults({
    feral_cat = {
        enabled = true,
        min_bite_rip_remains = 10,
        min_bite_sr_remains = 8,
        max_bite_energy = 65,
        ferociousbite_enabled = true,
        optimize_rake = true,
        rip_leeway = 0,
        min_roar_offset = 3,
        bearweave = false,
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
    },
})

-- Major cooldowns: snoozeable if player skips them (60s snooze)
DH:RegisterSnoozeable("force_of_nature", 60)
DH:RegisterSnoozeable("starfall", 60)
DH:RegisterSnoozeable("berserk", 60)

-- ============================================================================
-- DRUID-SPECIFIC TRACKING
-- ============================================================================

-- Feral tracking
ns.rip_extensions = 0
ns.rip_target_guid = nil
ns.last_rip_applied = 0

-- Eclipse tracking (Balance)
ns.eclipse_lunar_last_applied = 0
ns.eclipse_solar_last_applied = 0

-- Combat log handler for Druid-specific tracking
DH:RegisterCombatLogHandler(function(subevent, sourceGUID, destGUID, spellId, spellName, ...)
    local state = DH.State

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
                if state.glyph.shred and state.glyph.shred.enabled then
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
end)

-- Post-buff update hook: sync eclipse and rip extension tracking
-- This runs after the generic UpdateBuffs via a hook
local origUpdateBuffs = DH.State.UpdateBuffs
function DH.State:UpdateBuffs()
    origUpdateBuffs(self)

    -- Eclipse tracking
    self.buff.eclipse_lunar.last_applied = ns.eclipse_lunar_last_applied
    self.buff.eclipse_solar.last_applied = ns.eclipse_solar_last_applied

    -- Rip extension tracking (Glyph of Shred)
    if self.debuff.rip then
        self.debuff.rip.extensions = ns.rip_extensions or 0
    end
end

-- ============================================================================
-- SLASH COMMANDS (Druid-specific)
-- ============================================================================

DH:RegisterSlashCommand("bearweave", function(cmd)
    DH.db.feral_cat.bearweave = not DH.db.feral_cat.bearweave
    if DH.db.feral_cat.bearweave then
        DH:Print("Bearweave: |cFF00FF00ON|r (Lacerateweave - maintain 5-stack Lacerate)")
    else
        DH:Print("Bearweave: |cFFFF0000OFF|r (mono-cat rotation)")
    end
end, "bearweave - Toggle bearweaving (Lacerateweave)")

DH:RegisterSlashCommand("bw", function(cmd)
    DH.db.feral_cat.bearweave = not DH.db.feral_cat.bearweave
    if DH.db.feral_cat.bearweave then
        DH:Print("Bearweave: |cFF00FF00ON|r (Lacerateweave - maintain 5-stack Lacerate)")
    else
        DH:Print("Bearweave: |cFFFF0000OFF|r (mono-cat rotation)")
    end
end, nil) -- No help text for alias

DH:RegisterSlashCommand("cat", function(cmd)
    local s = DH.State
    DH:UpdateState()
    DH:Print("--- Cat Status ---")
    DH:Print("Energy: " .. tostring(s.energy.current) .. "/" .. tostring(s.energy.max))
    DH:Print("CP: " .. tostring(s.combo_points.current))
    DH:Print("SR: " .. (s.buff.savage_roar.up and ("UP " .. string.format("%.1f", s.buff.savage_roar.remains) .. "s") or "DOWN"))
    DH:Print("Rip: " .. (s.debuff.rip.up and ("UP " .. string.format("%.1f", s.debuff.rip.remains) .. "s") or "DOWN"))
    DH:Print("Rake: " .. (s.debuff.rake.up and ("UP " .. string.format("%.1f", s.debuff.rake.remains) .. "s") or "DOWN"))
    DH:Print("Mangle: " .. (s.debuff.mangle.up and ("UP " .. string.format("%.1f", s.debuff.mangle.remains) .. "s") or "DOWN"))
    DH:Print("Mangle talent: " .. tostring(s.talent.mangle.rank))
    DH:Print("TF ready: " .. tostring(s.cooldown.tigers_fury.ready) .. " (CD: " .. string.format("%.1f", s.cooldown.tigers_fury.remains) .. "s)")
    DH:Print("Berserk talent: " .. tostring(s.talent.berserk.rank) .. ", " .. (s.buff.berserk.up and "ACTIVE" or "ready=" .. tostring(s.cooldown.berserk.ready)))
    DH:Print("Clearcasting: " .. (s.buff.clearcasting.up and "UP" or "DOWN"))
    DH:Print("FF ready: " .. tostring(s.cooldown.faerie_fire_feral.ready) .. " (CD: " .. string.format("%.1f", s.cooldown.faerie_fire_feral.remains) .. "s)")
    DH:Print("OoC talent: " .. tostring(s.talent.omen_of_clarity.rank))
    DH:Print("Glyph Shred: " .. tostring(s.glyph.shred and s.glyph.shred.enabled))
    DH:Print("Rip Extensions: " .. tostring(ns.rip_extensions or 0) .. "/6")
    DH:Print("TTD: " .. tostring(s.target.time_to_die) .. "s")
end, "cat - Show feral cat status")

DH:RegisterSlashCommand("bear", function(cmd)
    local s = DH.State
    DH:UpdateState()
    local enabled = DH.db.feral_cat.bearweave
    DH:Print("--- Bear/Weave Status ---")
    DH:Print("Bearweave: " .. (enabled and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
    DH:Print("In Bear: " .. tostring(s.bear_form) .. " | In Cat: " .. tostring(s.cat_form))
    DH:Print("Energy: " .. tostring(s.energy.current) .. " | Rage: " .. tostring(s.rage.current))
    DH:Print("Furor talent: " .. tostring(s.talent.furor.rank) .. "/5")
    DH:Print("Mangle (Bear) CD: " .. (s.cooldown.mangle_bear.ready and "READY" or string.format("%.1fs", s.cooldown.mangle_bear.remains)))
    DH:Print("Lacerate: " .. (s.debuff.lacerate.up and (tostring(s.debuff.lacerate.stacks) .. " stacks, " .. string.format("%.1f", s.debuff.lacerate.remains) .. "s") or "DOWN"))
    DH:Print("Rip: " .. (s.debuff.rip.up and string.format("%.1f", s.debuff.rip.remains) .. "s" or "DOWN"))
    DH:Print("SR: " .. (s.buff.savage_roar.up and string.format("%.1f", s.buff.savage_roar.remains) .. "s" or "DOWN"))
end, "bear - Show bear/bearweave status")

DH:RegisterSlashCommand("debuffs", function(cmd)
    DH:Print("--- Target Debuffs ---")
    if UnitExists("target") then
        for i = 1, 40 do
            local name, rank, icon, count, debuffType, duration, expirationTime, source, _, _, spellId = UnitDebuff("target", i)
            if not name then break end
            local timeLeft = expirationTime and (expirationTime - GetTime()) or 0
            DH:Print(i .. ": " .. name .. " (ID:" .. tostring(spellId) .. ") src:" .. tostring(source) .. " " .. string.format("%.1f", timeLeft) .. "s")
        end
    else
        DH:Print("No target")
    end
    DH:Print("--- Tracked State ---")
    local s = DH.State
    DH:Print("Rake: up=" .. tostring(s.debuff.rake.up) .. " remains=" .. string.format("%.1f", s.debuff.rake.remains))
    DH:Print("Rip: up=" .. tostring(s.debuff.rip.up) .. " remains=" .. string.format("%.1f", s.debuff.rip.remains))
    DH:Print("Mangle: up=" .. tostring(s.debuff.mangle.up) .. " remains=" .. string.format("%.1f", s.debuff.mangle.remains))
end, "debuffs - Show target debuffs")

DH:RegisterSlashCommand("aoe", function(cmd)
    DH:Print("AoE rotation not implemented - use single target rotation")
end, nil)

-- ============================================================================
-- DEBUG FRAME (Druid-specific)
-- ============================================================================

ns.registered.debugFrameUpdater = function()
    if not ns.DebugFrame then return end

    local s = DH.State
    local rec1 = ns.recommendations[1] and ns.recommendations[1].ability or "none"
    local rec2 = ns.recommendations[2] and ns.recommendations[2].ability or "none"
    local rec3 = ns.recommendations[3] and ns.recommendations[3].ability or "none"

    -- FF status
    local ff_status = "?"
    local ff_remains = s.cooldown.faerie_fire_feral.remains
    if ff_remains > 0.1 then
        ff_status = string.format("|cFFFF0000CD %.1f|r", ff_remains)
    elseif s.buff.berserk.up then
        ff_status = "|cFFFFFF00RDY(Bzk)|r"
    elseif s.buff.clearcasting.up then
        ff_status = "|cFFFFFF00RDY(CC)|r"
    else
        ff_status = "|cFF00FF00RDY!|r"
    end

    -- Bearweave status
    local bw_status = ""
    local bw_enabled = DH.db.feral_cat and DH.db.feral_cat.bearweave
    if bw_enabled then
        if s.bear_form then
            bw_status = string.format("|cFFFF8800BEAR|r R:%d Lac:%d/%d",
                s.rage.current,
                s.debuff.lacerate.stacks or 0,
                s.debuff.lacerate.up and math.floor(s.debuff.lacerate.remains) or 0)
        else
            local can_bw = s.energy.current < 40 and not s.buff.clearcasting.up
                and (not s.debuff.rip.up or s.debuff.rip.remains > 4.5)
                and not s.buff.berserk.up
            if can_bw then
                bw_status = "|cFF00FF00BW_RDY|r"
            else
                bw_status = "|cFF888888BW:wait|r"
            end
        end
    end

    local lines = {
        "|cFFFFFF00=== Live Debug ===|r",
        string.format("E: %d | CP: %d | GCD: %.2f", s.energy.current, s.combo_points.current, s.gcd_remains),
        string.format("Berserk: %s | CC: %s", s.buff.berserk.up and "|cFFFF0000UP|r" or "no", s.buff.clearcasting.up and "|cFF00FF00UP|r" or "no"),
        string.format("FF: %s %s", ff_status, bw_status),
        string.format("SR:%.1f Rip:%.1f Rake:%.1f", s.buff.savage_roar.remains, s.debuff.rip.remains, s.debuff.rake.remains),
        string.format("|cFFFFFF00Rec: %s > %s > %s|r", rec1, rec2, rec3),
    }

    ns.DebugFrame.text:SetText(table.concat(lines, "\n"))
    ns.DebugFrame:Show()
end

