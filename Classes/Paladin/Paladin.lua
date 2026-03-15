-- Classes/Paladin/Paladin.lua
-- Paladin class module: ability definitions + registration

local DH = PriorityHelper
if not DH then return end

-- Only load for Paladins
if select(2, UnitClass("player")) ~= "PALADIN" then
    return
end

local ns = DH.ns
local class = DH.Class

-- ============================================================================
-- SPELL IDS (max rank for 3.3.5a)
-- ============================================================================

local SPELLS = {
    -- Retribution
    CRUSADER_STRIKE = 35395,
    DIVINE_STORM = 53385,
    JUDGEMENT_OF_WISDOM = 53408,
    JUDGEMENT_OF_LIGHT = 20271,
    HAMMER_OF_WRATH = 48806,
    EXORCISM = 48801,
    CONSECRATION = 48819,
    AVENGING_WRATH = 31884,
    DIVINE_PLEA = 54428,

    -- Protection
    SHIELD_OF_RIGHTEOUSNESS = 61411,
    HAMMER_OF_THE_RIGHTEOUS = 53595,
    AVENGERS_SHIELD = 48827,
    HOLY_SHIELD = 48952,
    RIGHTEOUS_FURY = 25780,

    -- Shared
    HOLY_WRATH = 48817,
    SEAL_OF_VENGEANCE = 31801,
    SEAL_OF_COMMAND = 20375,
    SEAL_OF_RIGHTEOUSNESS = 21084,

    -- Auras
    DEVOTION_AURA = 48942,
    RETRIBUTION_AURA = 54043,

    -- Blessings
    BLESSING_OF_MIGHT = 48934,
    BLESSING_OF_KINGS = 20217,
}

ns.SPELLS = SPELLS

-- ============================================================================
-- ABILITY DEFINITIONS
-- ============================================================================

class.abilities = {
    -- Retribution
    crusader_strike = {
        id = SPELLS.CRUSADER_STRIKE,
        name = "Crusader Strike",
        texture = 135891,
    },
    divine_storm = {
        id = SPELLS.DIVINE_STORM,
        name = "Divine Storm",
        texture = 236250,
    },
    judgement_of_wisdom = {
        id = SPELLS.JUDGEMENT_OF_WISDOM,
        name = "Judgement of Wisdom",
        texture = 236255,
    },
    judgement_of_light = {
        id = SPELLS.JUDGEMENT_OF_LIGHT,
        name = "Judgement of Light",
        texture = 136002,
    },
    hammer_of_wrath = {
        id = SPELLS.HAMMER_OF_WRATH,
        name = "Hammer of Wrath",
        texture = 132326,
    },
    exorcism = {
        id = SPELLS.EXORCISM,
        name = "Exorcism",
        texture = 135903,
    },
    consecration = {
        id = SPELLS.CONSECRATION,
        name = "Consecration",
        texture = 135926,
    },
    avenging_wrath = {
        id = SPELLS.AVENGING_WRATH,
        name = "Avenging Wrath",
        texture = 135875,
    },
    divine_plea = {
        id = SPELLS.DIVINE_PLEA,
        name = "Divine Plea",
        texture = 236171,
    },

    -- Protection
    shield_of_righteousness = {
        id = SPELLS.SHIELD_OF_RIGHTEOUSNESS,
        name = "Shield of Righteousness",
        texture = 236265,
    },
    hammer_of_the_righteous = {
        id = SPELLS.HAMMER_OF_THE_RIGHTEOUS,
        name = "Hammer of the Righteous",
        texture = 236253,
    },
    avengers_shield = {
        id = SPELLS.AVENGERS_SHIELD,
        name = "Avenger's Shield",
        texture = 135874,
    },
    holy_shield = {
        id = SPELLS.HOLY_SHIELD,
        name = "Holy Shield",
        texture = 135880,
    },
    righteous_fury = {
        id = SPELLS.RIGHTEOUS_FURY,
        name = "Righteous Fury",
        texture = 135962,
    },

    -- Shared
    holy_wrath = {
        id = SPELLS.HOLY_WRATH,
        name = "Holy Wrath",
        texture = 135902,
    },
    seal_of_vengeance = {
        id = SPELLS.SEAL_OF_VENGEANCE,
        name = "Seal of Vengeance",
        texture = 236270,
    },
    seal_of_command = {
        id = SPELLS.SEAL_OF_COMMAND,
        name = "Seal of Command",
        texture = 132347,
    },
}

-- Create name mapping and get textures from GetSpellInfo
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
-- REGISTER PALADIN DATA INTO FRAMEWORK
-- ============================================================================

-- GCD reference spell (Crusader Strike)
DH:RegisterGCDSpell(SPELLS.CRUSADER_STRIKE)

-- Melee abilities (for UI range overlay)
DH:RegisterMeleeAbilities({
    "crusader_strike", "divine_storm", "hammer_of_wrath",
    "shield_of_righteousness", "hammer_of_the_righteous",
})

-- Buffs to track
DH:RegisterBuffs({
    "avenging_wrath", "divine_plea", "art_of_war",
    "seal_of_vengeance", "seal_of_command", "seal_of_righteousness",
    "righteous_fury", "holy_shield",
    "devotion_aura", "retribution_aura",
    "divine_protection", "divine_shield",
    "blessing_of_might", "blessing_of_kings",
})

-- Debuffs to track
DH:RegisterDebuffs({
    "judgement_of_wisdom", "judgement_of_light",
    "holy_vengeance", -- SoV dot stacks
    "consecration",
    "training_dummy",
})

-- Cooldowns
DH:RegisterCooldowns({
    crusader_strike = SPELLS.CRUSADER_STRIKE,
    divine_storm = SPELLS.DIVINE_STORM,
    judgement = SPELLS.JUDGEMENT_OF_WISDOM,
    judgement_of_wisdom = SPELLS.JUDGEMENT_OF_WISDOM,
    hammer_of_wrath = SPELLS.HAMMER_OF_WRATH,
    exorcism = SPELLS.EXORCISM,
    consecration = SPELLS.CONSECRATION,
    avenging_wrath = SPELLS.AVENGING_WRATH,
    divine_plea = SPELLS.DIVINE_PLEA,
    shield_of_righteousness = SPELLS.SHIELD_OF_RIGHTEOUSNESS,
    hammer_of_the_righteous = SPELLS.HAMMER_OF_THE_RIGHTEOUS,
    avengers_shield = SPELLS.AVENGERS_SHIELD,
    holy_shield = SPELLS.HOLY_SHIELD,
    holy_wrath = SPELLS.HOLY_WRATH,
})

-- Talents
DH:RegisterTalents({
    -- Retribution
    { 3, 4, "crusader_strike" },
    { 3, 8, "sanctified_wrath" },
    { 3, 10, "repentance" },
    { 3, 11, "divine_storm" },
    { 3, 7, "the_art_of_war" },
    { 3, 6, "righteous_vengeance" },
    { 3, 5, "fanaticism" },
    { 3, 3, "improved_judgements" },
    { 3, 2, "heart_of_the_crusader" },
    { 3, 9, "swift_retribution" },

    -- Protection
    { 2, 1, "divinity" },
    { 2, 4, "divine_strength" },
    { 2, 6, "anticipation" },
    { 2, 9, "blessing_of_sanctuary" },
    { 2, 10, "holy_shield_talent" },
    { 2, 11, "ardent_defender" },
    { 2, 12, "redoubt" },
    { 2, 13, "combat_expertise" },
    { 2, 14, "touched_by_the_light" },
    { 2, 15, "avengers_shield" },
    { 2, 16, "guarded_by_the_light" },
    { 2, 17, "shield_of_the_templar" },
    { 2, 18, "judgements_of_the_just" },
    { 2, 19, "hammer_of_the_righteous" },

    -- Holy (relevant ones)
    { 1, 5, "divine_intellect" },
    { 1, 8, "aura_mastery" },
})

-- Glyphs
DH:RegisterGlyphs({
    [54922] = "judgement",        -- Glyph of Judgement
    [54927] = "exorcism",         -- Glyph of Exorcism
    [54925] = "crusader_strike",  -- Glyph of Crusader Strike
    [63218] = "shield_of_righteousness", -- Glyph of Shield of Righteousness
    [54923] = "consecration",     -- Glyph of Consecration
    [56416] = "divine_storm",     -- Glyph of Divine Storm
    [54926] = "avenging_wrath",   -- Glyph of Avenging Wrath
})

-- Buff spell ID -> key mapping
DH:RegisterBuffMap({
    [31884] = "avenging_wrath",
    [54428] = "divine_plea",
    [53488] = "art_of_war",       -- Art of War proc (instant Exorcism)
    [59578] = "art_of_war",       -- Art of War rank 2 proc
    [31801] = "seal_of_vengeance",
    [20375] = "seal_of_command",
    [21084] = "seal_of_righteousness",
    [25780] = "righteous_fury",
    [48952] = "holy_shield",
    [498]   = "divine_protection",
    [642]   = "divine_shield",
    [48942] = "devotion_aura",
    [54043] = "retribution_aura",
    [48934] = "blessing_of_might",
    [20217] = "blessing_of_kings",
})

-- Debuff spell ID -> key mapping
DH:RegisterDebuffMap({
    [53408] = "judgement_of_wisdom",
    [20271] = "judgement_of_light",
    [31803] = "holy_vengeance", -- SoV dot
})

DH:RegisterDebuffNamePatterns({
    { "judgement of wisdom", "judgement_of_wisdom" },
    { "judgement of light", "judgement_of_light" },
    { "holy vengeance", "holy_vengeance" },
})

-- ============================================================================
-- SPEC DETECTION
-- ============================================================================

DH:RegisterSpecDetector(function()
    local holy, prot, ret = 0, 0, 0

    for i = 1, GetNumTalentTabs() do
        local _, _, points = GetTalentTabInfo(i)
        if i == 1 then holy = points
        elseif i == 2 then prot = points
        else ret = points
        end
    end

    if ret > prot and ret > holy then
        return "retribution"
    elseif prot > holy then
        return "protection"
    else
        return "holy"
    end
end)

-- ============================================================================
-- DEFAULT SETTINGS
-- ============================================================================

DH:RegisterDefaults({
    paladin = {
        retribution = { enabled = true },
        protection = { enabled = true },
    },
    common = {
        dummy_ttd = 300,
    },
})

-- Mana costs (% of base mana)
DH:RegisterManaCosts({
    crusader_strike = 0.05,
    judgement_of_wisdom = 0.05,
    divine_storm = 0.12,
    consecration = 0.22,
    exorcism = 0.08,
    holy_wrath = 0.20,
    hammer_of_wrath = 0.12,
    shield_of_righteousness = 0.06,
    hammer_of_the_righteous = 0.06,
    holy_shield = 0.10,
})

-- Major cooldowns: snoozeable if player skips them (60s snooze)
DH:RegisterSnoozeable("avenging_wrath", 60)

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

DH:RegisterSlashCommand("ret", function(cmd)
    local s = DH.State
    DH:UpdateState()
    DH:Print("--- Ret Status ---")
    DH:Print("Mana: " .. tostring(s.mana.current) .. "/" .. tostring(s.mana.max))
    DH:Print("Seal: " .. (s.buff.seal_of_vengeance.up and "Vengeance" or (s.buff.seal_of_command.up and "Command" or "None")))
    DH:Print("AoW: " .. (s.buff.art_of_war.up and "|cFF00FF00UP|r" or "no"))
    DH:Print("AW: " .. (s.buff.avenging_wrath.up and "|cFFFF0000UP|r" or (s.cooldown.avenging_wrath.ready and "READY" or string.format("CD %.1f", s.cooldown.avenging_wrath.remains))))
    DH:Print("CS CD: " .. (s.cooldown.crusader_strike.ready and "READY" or string.format("%.1f", s.cooldown.crusader_strike.remains)))
    DH:Print("DS CD: " .. (s.cooldown.divine_storm.ready and "READY" or string.format("%.1f", s.cooldown.divine_storm.remains)))
    DH:Print("Judge CD: " .. (s.cooldown.judgement.ready and "READY" or string.format("%.1f", s.cooldown.judgement.remains)))
    DH:Print("HoW CD: " .. (s.cooldown.hammer_of_wrath.ready and "READY" or string.format("%.1f", s.cooldown.hammer_of_wrath.remains)))
    DH:Print("TTD: " .. tostring(s.target.time_to_die) .. "s")
end, "ret - Show retribution status")

DH:RegisterSlashCommand("prot", function(cmd)
    local s = DH.State
    DH:UpdateState()
    DH:Print("--- Prot Status ---")
    DH:Print("Mana: " .. tostring(s.mana.current) .. "/" .. tostring(s.mana.max))
    DH:Print("RF: " .. (s.buff.righteous_fury.up and "|cFF00FF00UP|r" or "|cFFFF0000DOWN|r"))
    DH:Print("HS: " .. (s.buff.holy_shield.up and "|cFF00FF00UP|r" or (s.cooldown.holy_shield.ready and "READY" or string.format("CD %.1f", s.cooldown.holy_shield.remains))))
    DH:Print("SoR CD: " .. (s.cooldown.shield_of_righteousness.ready and "READY" or string.format("%.1f", s.cooldown.shield_of_righteousness.remains)))
    DH:Print("HotR CD: " .. (s.cooldown.hammer_of_the_righteous.ready and "READY" or string.format("%.1f", s.cooldown.hammer_of_the_righteous.remains)))
    DH:Print("AS CD: " .. (s.cooldown.avengers_shield.ready and "READY" or string.format("%.1f", s.cooldown.avengers_shield.remains)))
end, "prot - Show protection status")

-- ============================================================================
-- DEBUG FRAME
-- ============================================================================

ns.registered.debugFrameUpdater = function()
    if not ns.DebugFrame then return end

    local s = DH.State
    local rec1 = ns.recommendations[1] and ns.recommendations[1].ability or "none"
    local rec2 = ns.recommendations[2] and ns.recommendations[2].ability or "none"
    local rec3 = ns.recommendations[3] and ns.recommendations[3].ability or "none"

    local seal = "None"
    if s.buff.seal_of_vengeance.up then seal = "SoV"
    elseif s.buff.seal_of_command.up then seal = "SoC"
    elseif s.buff.seal_of_righteousness.up then seal = "SoR"
    end

    local lines = {
        "|cFFFFFF00=== Live Debug ===|r",
        string.format("Mana: %d/%d | Seal: %s", s.mana.current, s.mana.max, seal),
        string.format("AoW: %s | AW: %s", s.buff.art_of_war.up and "|cFF00FF00UP|r" or "no", s.buff.avenging_wrath.up and "|cFFFF0000UP|r" or "no"),
        string.format("|cFFFFFF00Rec: %s > %s > %s|r", rec1, rec2, rec3),
    }

    ns.DebugFrame.text:SetText(table.concat(lines, "\n"))
    ns.DebugFrame:Show()
end
