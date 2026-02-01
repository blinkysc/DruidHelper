-- State.lua
-- Game state tracking for DruidHelper (3.3.5a compatible)

local DH = DruidHelper
if not DH then return end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- State variables
state.now = 0
state.offset = 0
state.gcd = 0
state.gcd_remains = 0
state.latency = 0.05

state.inCombat = false
state.GUID = nil
state.level = 1

-- Resources (using power type numbers for 3.3.5a)
-- 0 = Mana, 1 = Rage, 2 = Focus, 3 = Energy, 4 = Happiness, 5 = Runes, 6 = Runic Power
state.health = { current = 0, max = 0, pct = 0 }
state.mana = { current = 0, max = 0, pct = 0, regen = 0 }
state.energy = { current = 0, max = 100, regen = 10 }
state.rage = { current = 0, max = 100 }
state.combo_points = { current = 0, max = 5 }

-- Target info
state.target = {
    exists = false,
    guid = nil,
    health = { current = 0, max = 0, pct = 0 },
    time_to_die = 300,
    distance = 0,
    inRange = false,
    canAttack = false,
}

-- Buffs and debuffs
state.buff = {}
state.debuff = {}

-- Cooldowns
state.cooldown = {}

-- Talent tracking
state.talent = {}

-- Glyph tracking
state.glyph = {}

-- Set bonuses
state.set_bonus = {}

-- Equipped items
state.equipped = {}

-- Swing timer
state.swings = {
    mainhand = 0,
    mainhand_speed = 2.5,
}

-- Form tracking
state.form = 0
state.cat_form = false
state.bear_form = false
state.moonkin_form = false

-- Active enemies tracking (simplified - no AoE detection)
state.active_enemies = 1

-- Feral tracking
ns.rip_extensions = 0           -- Glyph of Shred extensions (max 6)
ns.rip_target_guid = nil        -- Track which target has Rip
ns.last_rip_applied = 0         -- When Rip was last applied

-- Eclipse tracking (Balance)
ns.eclipse_lunar_last_applied = 0
ns.eclipse_solar_last_applied = 0

-- Stat tracking
state.stat = {
    attack_power = 0,
    spell_power = 0,
    crit = 0,
    haste = 0,
    armor_pen_rating = 0,
    spell_haste = 1,
}

-- Settings shortcut
state.settings = {}

-- Metatable for buff tracking
local buffMT = {
    __index = function(t, k)
        if k == "up" then
            return t.remains > 0
        elseif k == "down" then
            return t.remains <= 0
        elseif k == "remains" then
            return t.expires and math.max(0, t.expires - GetTime()) or 0
        elseif k == "stack" or k == "stacks" then
            return t.count or 0
        elseif k == "duration" then
            return t._duration or 0
        end
        return rawget(t, k)
    end
}

local function CreateAuraTable()
    return setmetatable({
        expires = 0,
        count = 0,
        _duration = 0,
        applied = 0,
        last_applied = 0,
    }, buffMT)
end

-- Metatable for cooldown tracking
local cooldownMT = {
    __index = function(t, k)
        if k == "up" or k == "ready" then
            -- Use tolerance of 0.1s to avoid timing race conditions
            return t.remains <= 0.1
        elseif k == "down" then
            return t.remains > 0.1
        elseif k == "remains" then
            local start, duration = t.start or 0, t.duration or 0
            if start == 0 then return 0 end
            -- Use cached time if available, otherwise GetTime()
            local now = state.now or GetTime()
            return math.max(0, start + duration - now)
        end
        return rawget(t, k)
    end
}

local function CreateCooldownTable()
    return setmetatable({
        start = 0,
        duration = 0,
    }, cooldownMT)
end

-- Metatable for talents
local talentMT = {
    __index = function(t, k)
        local data = rawget(t, k)
        if data then return data end
        return { rank = 0 }
    end
}

-- Metatable for glyphs
local glyphMT = {
    __index = function(t, k)
        return { enabled = false }
    end
}

-- Initialize state
function state:Init()
    self.GUID = UnitGUID("player")
    self.level = UnitLevel("player")

    -- Initialize buff tables for known buffs
    local buffs = {
        "cat_form", "dire_bear_form", "bear_form", "moonkin_form", "travel_form",
        "prowl", "shadowmeld",
        "savage_roar", "tigers_fury", "berserk", "clearcasting", "predators_swiftness",
        "enrage", "frenzied_regeneration", "survival_instincts", "barkskin",
        "eclipse_lunar", "eclipse_solar", "natures_grace", "owlkin_frenzy", "elunes_wrath",
        "mark_of_the_wild", "gift_of_the_wild", "thorns",
        "maul",
    }

    for _, buff in ipairs(buffs) do
        self.buff[buff] = CreateAuraTable()
    end

    -- Initialize debuff tables
    local debuffs = {
        "rake", "rip", "lacerate", "mangle", "faerie_fire", "faerie_fire_feral",
        "moonfire", "insect_swarm",
        "pounce", "pounce_bleed", "maim",
        "demoralizing_roar", "infected_wounds",
        "armor_reduction", "major_armor_reduction", "shattering_throw",
        "bleed", "bleed_debuff",  -- bleed_debuff = Mangle/Trauma from ANY source
        "training_dummy",
    }

    for _, debuff in ipairs(debuffs) do
        self.debuff[debuff] = CreateAuraTable()
    end

    -- Initialize cooldown tables
    local cooldowns = {
        "tigers_fury", "berserk", "survival_instincts", "barkskin",
        "mangle_cat", "mangle_bear", "swipe_cat", "swipe_bear",
        "faerie_fire_feral", "feral_charge_cat", "feral_charge_bear",
        "starfall", "force_of_nature", "typhoon", "innervate", "rebirth",
        "enrage", "frenzied_regeneration", "challenging_roar", "growl",
        "bash", "maim",
    }

    for _, cd in ipairs(cooldowns) do
        self.cooldown[cd] = CreateCooldownTable()
    end

    -- Set metatables
    setmetatable(self.talent, talentMT)
    setmetatable(self.glyph, glyphMT)
end

-- Reset state for new update cycle
function state:Reset()
    self.now = GetTime()
    self.GUID = UnitGUID("player")
    self.level = UnitLevel("player")

    -- Update combat state
    self.inCombat = UnitAffectingCombat("player")
    ns.inCombat = self.inCombat

    -- Update GCD (use Rake as reference spell)
    local gcdStart, gcdDuration = GetSpellCooldown(48574)
    if gcdStart and gcdStart > 0 then
        self.gcd = gcdDuration
        self.gcd_remains = math.max(0, gcdStart + gcdDuration - self.now)
    else
        self.gcd = 1.5
        self.gcd_remains = 0
    end

    -- Update resources
    self:UpdateResources()

    -- Update target
    self:UpdateTarget()

    -- Update active enemy count (for AoE)
    self:UpdateActiveEnemies()

    -- Update form
    self:UpdateForm()

    -- Update buffs
    self:UpdateBuffs()

    -- Update debuffs
    self:UpdateDebuffs()

    -- Update cooldowns
    self:UpdateCooldowns()

    -- Update stats
    self:UpdateStats()

    -- Update talents
    self:UpdateTalents()

    -- Update glyphs
    self:UpdateGlyphs()

    -- Update settings reference
    if DH.db then
        self.settings = DH.db
    end
end

function state:UpdateResources()
    -- Health
    self.health.current = UnitHealth("player")
    self.health.max = UnitHealthMax("player")
    self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 0

    -- Mana (power type 0)
    self.mana.current = UnitPower("player", 0)
    self.mana.max = UnitPowerMax("player", 0)
    self.mana.pct = self.mana.max > 0 and (self.mana.current / self.mana.max * 100) or 0

    -- Energy (power type 3)
    self.energy.current = UnitPower("player", 3)
    self.energy.max = UnitPowerMax("player", 3)
    if self.energy.max == 0 then self.energy.max = 100 end

    -- Rage (power type 1)
    self.rage.current = UnitPower("player", 1)
    self.rage.max = 100

    -- Combo Points
    self.combo_points.current = GetComboPoints("player", "target")
end

function state:UpdateActiveEnemies()
    -- Simplified - just set to 1 if we have a target
    if UnitExists("target") and UnitCanAttack("player", "target") then
        self.active_enemies = 1
    else
        self.active_enemies = 0
    end
end

function state:UpdateTarget()
    self.target.exists = UnitExists("target")
    self.target.guid = UnitGUID("target")

    if self.target.exists then
        self.target.health.current = UnitHealth("target")
        self.target.health.max = UnitHealthMax("target")
        self.target.health.pct = self.target.health.max > 0 and (self.target.health.current / self.target.health.max * 100) or 0

        -- Estimate time to die
        if self.target.health.pct < 20 then
            self.target.time_to_die = 10
        elseif self.target.health.pct < 35 then
            self.target.time_to_die = 30
        else
            self.target.time_to_die = 300
        end

        -- Check if target is a training dummy
        local name = UnitName("target")
        if name and name:find("Dummy") then
            self.target.time_to_die = DH.db and DH.db.common.dummy_ttd or 300
            self.debuff.training_dummy.expires = self.now + 3600
        else
            self.debuff.training_dummy.expires = 0
        end

        -- Range check using CheckInteractDistance (3.3.5a compatible)
        -- Index 3 = ~10 yards, Index 4 = ~28 yards
        if CheckInteractDistance("target", 3) then
            self.target.distance = 5
            self.target.inRange = true
        elseif CheckInteractDistance("target", 4) then
            self.target.distance = 20
            self.target.inRange = false
        else
            self.target.distance = 40
            self.target.inRange = false
        end

        -- Can attack check
        self.target.canAttack = UnitCanAttack("player", "target")
    else
        self.target.health.current = 0
        self.target.health.max = 0
        self.target.health.pct = 0
        self.target.time_to_die = 0
        self.target.distance = 40
        self.target.inRange = false
        self.target.canAttack = false
    end
end

function state:UpdateForm()
    self.form = GetShapeshiftForm()

    self.cat_form = self.form == 3
    self.bear_form = self.form == 1
    self.moonkin_form = self.form == 5

    -- Update buff tracking for forms
    self.buff.cat_form.expires = self.cat_form and (self.now + 3600) or 0
    self.buff.dire_bear_form.expires = self.bear_form and (self.now + 3600) or 0
    self.buff.bear_form.expires = self.bear_form and (self.now + 3600) or 0
    self.buff.moonkin_form.expires = self.moonkin_form and (self.now + 3600) or 0
end

function state:UpdateBuffs()
    -- Reset all non-form buff expires first (so faded buffs don't persist)
    for key, buff in pairs(self.buff) do
        if type(buff) == "table" and buff.expires then
            -- Don't reset form buffs (handled by UpdateForm)
            if key ~= "cat_form" and key ~= "dire_bear_form" and key ~= "bear_form" and key ~= "moonkin_form" then
                buff.expires = 0
                buff.count = 0
            end
        end
    end

    -- Scan player buffs
    for i = 1, 40 do
        local name, _, icon, count, debuffType, duration, expirationTime, source, _, _, spellId = UnitBuff("player", i)
        if not name then break end

        -- Map spell IDs to our buff keys
        local key = self:GetBuffKey(spellId, name)
        if key and self.buff[key] then
            self.buff[key].expires = expirationTime or (self.now + 3600)
            self.buff[key].count = count or 1
            self.buff[key]._duration = duration or 0
            self.buff[key].applied = expirationTime and (expirationTime - duration) or self.now
        end
    end

    -- Eclipse tracking
    self.buff.eclipse_lunar.last_applied = ns.eclipse_lunar_last_applied
    self.buff.eclipse_solar.last_applied = ns.eclipse_solar_last_applied

    -- Rip extension tracking (Glyph of Shred)
    if self.debuff.rip then
        self.debuff.rip.extensions = ns.rip_extensions or 0
    end
end

function state:UpdateDebuffs()
    if not self.target.exists then return end

    -- Reset debuff expires
    for key, debuff in pairs(self.debuff) do
        if type(debuff) == "table" and debuff.expires and key ~= "training_dummy" then
            debuff.expires = 0
            debuff.count = 0
        end
    end

    -- Scan target debuffs
    for i = 1, 40 do
        local name, _, icon, count, debuffType, duration, expirationTime, source, _, _, spellId = UnitDebuff("target", i)
        if not name then break end

        -- Track our debuffs
        if source == "player" then
            local key = self:GetDebuffKey(spellId, name)
            if key and self.debuff[key] then
                self.debuff[key].expires = expirationTime or (self.now + 3600)
                self.debuff[key].count = count or 1
                self.debuff[key]._duration = duration or 0
            end
        end

        -- Track external debuffs (from other players, not us)
        if source ~= "player" then
            local key = self:GetExternalDebuffKey(spellId, name)
            if key and self.debuff[key] then
                self.debuff[key].expires = expirationTime or (self.now + 3600)
            end
        end
    end
end

function state:UpdateCooldowns()
    local cooldownSpells = {
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
    }

    for key, spellId in pairs(cooldownSpells) do
        local start, duration, enabled = GetSpellCooldown(spellId)
        if self.cooldown[key] then
            -- Filter out GCD
            if duration and duration > 1.5 then
                self.cooldown[key].start = start or 0
                self.cooldown[key].duration = duration or 0
            else
                self.cooldown[key].start = 0
                self.cooldown[key].duration = 0
            end
        end
    end
end

function state:UpdateStats()
    local base, posBuff, negBuff = UnitAttackPower("player")
    self.stat.attack_power = base + posBuff + negBuff

    self.stat.spell_power = GetSpellBonusDamage(4) -- Nature damage

    self.stat.crit = GetCritChance()
    self.stat.haste = GetCombatRatingBonus(18) -- CR_HASTE_MELEE
    self.stat.armor_pen_rating = GetCombatRating(25) -- CR_ARMOR_PENETRATION

    local spellHaste = GetCombatRatingBonus(20) -- CR_HASTE_SPELL
    self.stat.spell_haste = 1 + (spellHaste / 100)
end

function state:UpdateTalents()
    -- Talent data: tab, index, key
    local talentData = {
        -- Balance
        { 1, 1, "starlight_wrath" },
        { 1, 3, "natures_majesty" },
        { 1, 5, "brambles" },
        { 1, 6, "natures_grace" },
        { 1, 7, "natures_splendor" },
        { 1, 8, "natures_reach" },
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
        { 1, 10, "moonglow" },

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
    }

    for _, data in ipairs(talentData) do
        local tab, index, key = data[1], data[2], data[3]
        local _, _, _, _, rank = GetTalentInfo(tab, index)
        self.talent[key] = { rank = rank or 0 }
    end
end

function state:UpdateGlyphs()
    local glyphSpells = {
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
    }

    -- Reset all glyphs
    for _, key in pairs(glyphSpells) do
        self.glyph[key] = { enabled = false }
    end

    -- Scan equipped glyphs (3.3.5a has 6 glyph slots)
    for i = 1, 6 do
        local enabled, glyphType, glyphTooltipIndex, glyphSpell, icon = GetGlyphSocketInfo(i)
        if enabled and glyphSpell then
            local key = glyphSpells[glyphSpell]
            if key then
                self.glyph[key] = { enabled = true }
            end
        end
    end
end

-- Helper: Map spell IDs to buff keys
function state:GetBuffKey(spellId, name)
    local buffMap = {
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
    }
    return buffMap[spellId]
end

-- Helper: Map spell IDs to debuff keys
function state:GetDebuffKey(spellId, name)
    local debuffMap = {
        -- Rake (all ranks)
        [48574] = "rake", [48573] = "rake", [27003] = "rake", [9904] = "rake",
        [9752] = "rake", [1824] = "rake", [1823] = "rake", [1822] = "rake",
        -- Rip (all ranks)
        [49800] = "rip", [49799] = "rip", [27008] = "rip", [9896] = "rip",
        [9894] = "rip", [9752] = "rip", [6800] = "rip", [1079] = "rip",
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
    }

    -- Try ID first
    local key = debuffMap[spellId]
    if key then return key end

    -- Fallback to name matching (case-insensitive)
    if name then
        local lowerName = name:lower()
        if lowerName:find("mangle") then return "mangle" end
        if lowerName:find("rake") then return "rake" end
        if lowerName:find("rip") then return "rip" end
        if lowerName:find("lacerate") then return "lacerate" end
        if lowerName:find("faerie fire") then
            if lowerName:find("feral") then return "faerie_fire_feral" end
            return "faerie_fire"
        end
        if lowerName:find("moonfire") then return "moonfire" end
        if lowerName:find("insect swarm") then return "insect_swarm" end
    end

    return nil
end

-- Helper: Map external debuffs
function state:GetExternalDebuffKey(spellId, name)
    local externalMap = {
        [47467] = "armor_reduction", -- Sunder Armor
        [8647] = "armor_reduction",  -- Expose Armor
        [55754] = "armor_reduction", -- Acid Spit
        -- Trauma (Arms Warrior) - same effect as Mangle
        [46857] = "bleed_debuff",
        -- Mangle (Bear) from other druids
        [48564] = "bleed_debuff", [48563] = "bleed_debuff",
        [33987] = "bleed_debuff", [33986] = "bleed_debuff", [33878] = "bleed_debuff",
        -- Mangle (Cat) from other druids
        [48566] = "bleed_debuff", [48565] = "bleed_debuff",
        [33983] = "bleed_debuff", [33982] = "bleed_debuff", [33876] = "bleed_debuff",
    }

    if name then
        local lowerName = name:lower()
        if lowerName:find("sunder") or lowerName:find("expose") then
            return "armor_reduction"
        end
        -- Mangle or Trauma from any source
        if lowerName:find("mangle") or lowerName:find("trauma") then
            return "bleed_debuff"
        end
    end

    return externalMap[spellId]
end

-- Convenience accessors
setmetatable(state, {
    __index = function(t, k)
        if k == "ttd" then
            return t.target.time_to_die
        elseif k == "time" then
            return t.now
        elseif k == "query_time" then
            return t.now + t.offset
        elseif k == "haste" then
            return 1 / (1 + t.stat.haste / 100)
        elseif k == "mainhand_speed" then
            local speed = UnitAttackSpeed("player")
            return speed or 2.5
        end
        return rawget(t, k)
    end
})

-- Initialize on load
state:Init()
