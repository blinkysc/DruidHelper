-- Druid.lua
-- Ability definitions for DruidHelper (3.3.5a compatible)

local DH = DruidHelper
if not DH then return end

-- Only load for Druids
if select(2, UnitClass("player")) ~= "DRUID" then
    return
end

local ns = DH.ns
local class = DH.Class

-- Spell IDs (max rank for 3.3.5a)
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

-- Ability definitions with textures
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
    -- Get texture from spell info (returns path in 3.3.5a)
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
        -- Try GetSpellInfo if texture not set
        if not ability.texture and ability.id then
            local _, _, icon = GetSpellInfo(ability.id)
            ability.texture = icon
        end
        return ability.texture or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end
