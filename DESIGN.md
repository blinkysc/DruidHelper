# PriorityHelper - Design Document

## Overview

PriorityHelper is a WotLK 3.3.5a WoW addon that shows the next 3 recommended abilities as icons. Classes register their data into a generic framework via a registration API. A minimap dropdown lets the player select their rotation mode.

## Architecture

```
PriorityHelper/
├── PriorityHelper.lua          # Core framework, registration API, events, snooze system
├── State.lua                   # Generic state tracking (uses registered data)
├── UI.lua                      # Icon display, cooldown sweeps, range overlay
├── Config.lua                  # Minimap button, mode dropdown, overrides UpdateRecommendations
├── Classes/
│   ├── Druid/
│   │   ├── Druid.lua           # Ability defs + registers buffs/debuffs/cooldowns/talents/etc
│   │   └── Core.lua            # Rotation logic (Cat, Cat+Bearweave, Bear, Boomkin)
│   └── Paladin/
│       ├── Paladin.lua         # Ability defs + registers all Paladin data
│       └── Core.lua            # Rotation logic (Retribution, Protection)
```

## TOC Load Order (Critical)

```
PriorityHelper.lua   → Framework + API defined
State.lua            → State system defined
UI.lua               → Display system defined
Classes\...\*.lua    → Class modules register data + rotations
Config.lua           → MUST BE LAST - overrides UpdateRecommendations, creates minimap
```

Config.lua MUST load last. It overrides `UpdateRecommendations()` to dispatch by mode instead of spec. It also forces initialization if `ADDON_LOADED` fired before all files loaded.

## Initialization Lifecycle

1. All `.lua` files execute top-to-bottom (registrations happen)
2. `ADDON_LOADED` fires → `OnInitialize()` (loads DB, slash commands) → `OnEnable()` (registers events, creates UI, starts update loop)
3. Config.lua bottom code runs: injects minimap defaults, creates minimap button, hooks `OnEnable`
4. Both `OnInitialize` and `OnEnable` have guards (`_initialized`, `_enabled`) to prevent double-run

**Gotcha**: `ADDON_LOADED` may fire before Config.lua loads. Config.lua handles this by checking `if not DH.db then DH:OnInitialize() end` at the bottom.

## Registration API

Class modules call these from their `.lua` files at load time:

### Data Registration
| Function | Purpose |
|----------|---------|
| `RegisterBuffs({"key1", "key2"})` | Buff keys to create tracking tables for |
| `RegisterDebuffs({"key1", "key2"})` | Debuff keys to track |
| `RegisterCooldowns({key = spellId})` | Cooldown tracking by spell ID |
| `RegisterTalents({{tab, index, "key"}})` | Talent tree positions |
| `RegisterGlyphs({[glyphSpellId] = "key"})` | Glyph detection |
| `RegisterBuffMap({[spellId] = "buffKey"})` | Map UnitBuff spell IDs to buff keys |
| `RegisterDebuffMap({[spellId] = "debuffKey"})` | Map UnitDebuff spell IDs to debuff keys |
| `RegisterExternalDebuffMap({[spellId] = "key"})` | Debuffs from OTHER players |
| `RegisterDebuffNamePatterns({{"pattern", "key"}})` | Fallback name matching (case-insensitive) |
| `RegisterExternalDebuffNamePatterns(...)` | Same for external debuffs |
| `RegisterGCDSpell(spellId)` | Reference spell for GCD detection |
| `RegisterMeleeAbilities({"key1", "key2"})` | Abilities that show red range overlay |
| `RegisterDefaults({settings})` | Class-specific saved variable defaults |

### Behavior Registration
| Function | Purpose |
|----------|---------|
| `RegisterMode(key, {name, icon, rotation})` | Rotation mode for minimap dropdown |
| `RegisterRotation(specKey, fn)` | Rotation function (legacy, modes preferred) |
| `RegisterSpecDetector(fn)` | Returns spec string ("feral", "retribution", etc.) |
| `RegisterFormHandler(formId, fn)` | Called when shapeshift form matches |
| `RegisterCombatLogHandler(fn)` | Receives combat log events (player source only) |
| `RegisterSlashCommand(cmd, fn, helpText)` | Class-specific `/ph <cmd>` commands |
| `RegisterSnoozeable(key, duration)` | Allow snoozing skipped major CDs |

## Adding a New Class

### Step 1: Create `Classes/<ClassName>/<ClassName>.lua`

```lua
local DH = PriorityHelper
if not DH then return end
if select(2, UnitClass("player")) ~= "CLASSTOKEN" then return end

local ns = DH.ns
local class = DH.Class

-- Define abilities
class.abilities = {
    ability_key = {
        id = SPELL_ID,
        name = "Ability Name",
        texture = TEXTURE_ID,  -- fallback, GetSpellInfo overwrites
    },
}

-- Get textures from game
for key, ability in pairs(class.abilities) do
    ability.key = key
    class.abilityByName[ability.name] = ability
    if ability.id then
        local _, _, icon = GetSpellInfo(ability.id)
        if icon then ability.texture = icon end
    end
end

-- Register everything
DH:RegisterGCDSpell(SPELL_ID)
DH:RegisterMeleeAbilities({"ability1", "ability2"})
DH:RegisterBuffs({"buff1", "buff2"})
DH:RegisterDebuffs({"debuff1", "debuff2"})
DH:RegisterCooldowns({ability1 = SPELL_ID1, ability2 = SPELL_ID2})
DH:RegisterTalents({{tab, index, "talent_key"}})
DH:RegisterGlyphs({[GLYPH_SPELL_ID] = "glyph_key"})
DH:RegisterBuffMap({[BUFF_SPELL_ID] = "buff_key"})
DH:RegisterDebuffMap({[DEBUFF_SPELL_ID] = "debuff_key"})
DH:RegisterSpecDetector(function() ... return "spec_name" end)
DH:RegisterDefaults({class_settings = {}})
```

### Step 2: Create `Classes/<ClassName>/Core.lua`

**All rotations MUST use a simulation system** — copy state into a sim table, get the best ability, simulate its effects, advance time, repeat for 3 recommendations. This prevents icon flickering and gives the player anticipation of what's coming next.

```lua
local DH = PriorityHelper
if not DH then return end
if select(2, UnitClass("player")) ~= "CLASSTOKEN" then return end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- Simulated state table
local sim = {}

-- Helper to add recommendation
local function addRec(recommendations, key)
    local ability = class.abilities[key]
    if ability then
        table.insert(recommendations, {
            ability = key, texture = ability.texture, name = ability.name,
        })
    end
    return #recommendations >= 3
end

-- Step 1: Reset sim from real state
local function ResetSim(s)
    sim.gcd_remains = s.gcd_remains or 0

    -- Copy all relevant state: resources, buffs, debuffs, cooldowns
    sim.resource = s.resource_type.current  -- e.g. energy, mana, rage
    sim.buff_x_up = s.buff.x.up
    sim.buff_x_remains = s.buff.x.remains
    sim.debuff_y_remains = s.debuff.y.remains
    sim.cd_z_ready = s.cooldown.z.ready
    sim.cd_z_remains = s.cooldown.z.remains

    -- Account for haste on cast times / GCD
    local haste = s.stat.spell_haste or 1
    sim.gcd = math.max(1.0, 1.5 / haste)
    sim.cast_time = BASE_CAST / haste
end

-- Step 2: Simulate time passing
local function SimulateTime(seconds)
    if seconds <= 0 then return end

    -- Tick down all tracked buff/debuff/cooldown timers
    sim.buff_x_remains = sim.buff_x_remains - seconds
    if sim.buff_x_remains <= 0 then
        sim.buff_x_up = false
        sim.buff_x_remains = 0
    end

    sim.debuff_y_remains = sim.debuff_y_remains - seconds
    if sim.debuff_y_remains < 0 then sim.debuff_y_remains = 0 end

    sim.cd_z_remains = sim.cd_z_remains - seconds
    if sim.cd_z_remains <= 0 then
        sim.cd_z_ready = true
        sim.cd_z_remains = 0
    end

    -- Regen resources if applicable
    sim.resource = math.min(MAX, sim.resource + REGEN_RATE * seconds)
end

-- Step 3: Simulate an ability's effects
local function SimulateAbility(action)
    if action == "dot_ability" then
        sim.debuff_y_remains = DOT_DURATION
        SimulateTime(sim.gcd)
    elseif action == "nuke" then
        SimulateTime(sim.cast_time)
    elseif action == "cooldown_ability" then
        sim.cd_z_ready = false
        sim.cd_z_remains = CD_DURATION
        SimulateTime(sim.gcd)
    end
end

-- Step 4: Priority logic (called once per sim iteration)
local function GetNextAbility()
    -- Check conditions against sim state (NOT real state)
    if sim.cd_z_ready then return "cooldown_ability" end
    if sim.debuff_y_remains < 1 then return "dot_ability" end
    return "nuke"
end

-- Step 5: Main rotation function — simulate 3 GCDs ahead
local function GetMyRotation(addon)
    local recommendations = {}
    local s = state
    if not s.target.exists or not s.target.canAttack then return recommendations end

    ResetSim(s)

    -- Account for current GCD
    if sim.gcd_remains > 0 then
        SimulateTime(sim.gcd_remains)
    end

    -- Simulate 3 abilities
    for i = 1, 3 do
        local action = GetNextAbility()
        if action then
            addRec(recommendations, action)
            SimulateAbility(action)
        end
    end

    return recommendations
end

-- Register mode
DH:RegisterMode("mode_key", {
    name = "Spec Name (Role)",
    icon = select(3, GetSpellInfo(SPELL_ID)),
    rotation = function(addon) return GetMyRotation(addon) end,
})
```

### Simulation Design Principles

1. **Always simulate** — never just check current state for all 3 icons. Each recommendation must account for the effects of previous recommendations.
2. **Copy state first** — never modify real `state`, always work on a `sim` copy.
3. **Advance time by cast duration** — instant/GCD abilities advance by `sim.gcd`, casted spells advance by their haste-adjusted cast time.
4. **Track everything that changes** — if a buff expires, a DoT ticks down, or a cooldown comes off CD during the sim window, the priority logic sees it.
5. **Account for haste** — cast times, GCD, and resource regen are all affected by haste. Read `state.stat.spell_haste` or melee haste as appropriate.
6. **DoT refresh timing** — follow the spec guide. Most WotLK DoTs should be "allowed to fall off before reapplying" (check `< 1`), not pandemic-clipped early.
7. **Snoozeable CDs** — major cooldowns should use `DH:RegisterSnoozeable(key, 60)` and check `DH:IsSnoozed(key)` so players can skip them without nagging.

### Step 3: Add to TOC (BEFORE Config.lua)

```
Classes\ClassName\ClassName.lua
Classes\ClassName\Core.lua
Config.lua
```

## State API (available in rotation functions via `state`)

### Resources
- `state.health.current / .max / .pct`
- `state.mana.current / .max / .pct`
- `state.energy.current / .max`
- `state.rage.current / .max`
- `state.combo_points.current`
- `state.runic_power.current / .max`

### Target
- `state.target.exists / .guid / .canAttack`
- `state.target.health.current / .max / .pct`
- `state.target.time_to_die` (estimated: <20% = 10s, <35% = 30s, else 300s)
- `state.target.inRange` (true if CheckInteractDistance index 3 passes)

### Buffs/Debuffs (metatable-driven)
- `state.buff.key.up` / `.down` / `.remains` / `.stacks` / `.duration`
- `state.debuff.key.up` / `.down` / `.remains` / `.stacks`

### Cooldowns (metatable-driven)
- `state.cooldown.key.ready` / `.up` — true if remains <= 0.1
- `state.cooldown.key.remains` — seconds until ready
- `state.cooldown.key.down` — true if on cooldown

### Talents/Glyphs
- `state.talent.key.rank` (0 if not talented)
- `state.glyph.key.enabled` (false if not equipped)

### Other
- `state.now` — cached GetTime()
- `state.gcd` / `state.gcd_remains`
- `state.form` — GetShapeshiftForm() result
- `state.cat_form / .bear_form / .moonkin_form` — booleans (set by form handlers)
- `state.stat.attack_power / .spell_power / .crit / .haste`
- `state.active_enemies`

## Known Gotchas

### Permanent Buffs
Buffs with `expirationTime == 0` (Righteous Fury, auras, seals) are treated as 2-hour buffs. Without this, `buff.remains` returns 0 and `buff.up` is false.

### GCD vs Real Cooldown
`GetSpellCooldown()` returns the GCD when a spell has no real CD. The framework detects the actual GCD duration (haste-aware) and filters it out. If the GCD reference spell is on a real CD, it scans other spells to find the GCD.

### ADDON_LOADED Timing
`ADDON_LOADED` can fire before all TOC files load. Config.lua (last file) checks `if not DH.db` and forces init. Both `OnInitialize` and `OnEnable` have `_initialized`/`_enabled` guards.

### SCP File Caching
When deploying via `scp`, old files may persist. Always `rm -rf` the target folder before copying:
```
rm -rf ./PriorityHelper
scp -r server:/path/to/repo ./PriorityHelper
```

### Cooldown Snooze
Major CDs (like Avenging Wrath) can be registered as snoozeable. If the addon recommends it but the player uses a different ability, the CD is snoozed for N seconds. Using the CD manually clears the snooze. Detection uses combat log events (SPELL_CAST_SUCCESS, SPELL_DAMAGE, SPELL_AURA_APPLIED).

### Creature Type Detection
`UnitCreatureType("target")` returns strings like `"Undead"`, `"Demon"`, `"Beast"`, etc. Used by Paladin to prioritize Exorcism (100% crit vs Undead/Demon) and only show Holy Wrath vs valid targets.

## Rotation Sources

Rotations are based on:
1. **wowsim/wotlk** APL files (`~/wotlk/ui/<spec>/apls/default.apl.json`)
2. **Wowhead WotLK guides** for priority validation
3. Cross-referenced for accuracy

## Version History

- **1.0.0** — Druid only (Cat, Cat+Bearweave, Bear, Boomkin)
- **1.1.0** — Paladin added (Retribution, Protection), minimap dropdown, snooze system
- **1.1.1** — Prot 969 rotation fix, Divine Plea, init reliability
