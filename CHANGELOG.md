# Changelog

All notable changes to PriorityHelper will be documented in this file.

## [1.1.3] - 2026-03-15

### Added
- Core simulation framework: GCD/haste, mana, energy, rage, cooldown, target helpers
- Mana simulation for Paladin: ability costs, JoW return (25%), Replenishment ticking
- `RegisterManaCosts()`, `RegisterAbilityCooldowns()` framework APIs
- `SimInitGCD()` with melee/spell haste support
- `SimInitMana/Energy/Rage/Target/CD()` helpers for all classes
- Divine Plea integrated into sim (appears in GCD gaps when mana < 40%)

### Fixed
- Paladin GCD now haste-adjusted (was hardcoded 1.5s)
- Judgement CD now respects Improved Judgements talent (8s with 2/2)
- Judgement cooldown sweep now shows in UI (key mismatch fix)
- Divine Plea no longer pops in as Rec1 over DPS abilities

### Changed
- Paladin rotations fully simulation-driven with mana tracking
- Removed seal and Divine Plea snoozing (handled by sim instead)

## [1.1.2] - 2026-03-15

### Added
- Balance Druid simulation system: predicts 3 GCDs ahead like Feral Cat
- Haste-adjusted cast times (Wrath, Starfire) and GCD in Balance sim
- Nature's Splendor talent support for DoT duration (Moonfire 15s, IS 14s)
- Eclipse ICD simulation: properly tracks Lunar ICD through Eclipse expiry

### Fixed
- Balance DoTs no longer flicker — simulation predicts when they'll expire
- Insect Swarm now properly recommended when down (removed overly strict ICD gate)
- Moonfire/IS refresh timing matches wowhead guide ("allow to fall off before reapplying")

### Changed
- Balance rotation rewritten with full simulation (was static priority checks)
- DoT refresh threshold tightened to < 1s remaining (from < 3s pandemic window)

## [1.1.1] - 2026-03-15

### Fixed
- Prot Paladin 969 rotation now properly shows SoR/HotR in upcoming slots
- Added Divine Plea to Prot rotation (mana < 60%)
- Duplicate ability prevention in priority queue

## [1.1.0] - 2026-03-15

### Added
- **Paladin support**: Retribution (DPS) and Protection (Tank) rotation modes
- Minimap button with dropdown for rotation mode selection
- Cooldown snooze system: skipped major CDs (e.g. Avenging Wrath) stop nagging for 60s
- Target-aware priorities: Exorcism prioritized vs Undead/Demon (100% crit), Holy Wrath only shown vs valid targets
- `UnitCreatureType` detection for Paladin ability conditions

### Fixed
- GCD detection now properly handles haste and spells with real CDs as reference
- Permanent buffs (Righteous Fury, auras, seals) no longer treated as expired
- Init lifecycle: guards against double-run, Config.lua forces init if ADDON_LOADED fires early
- Removed seal recommendations from Paladin (player decision based on AoE vs single target)

### Changed
- Balance Druid rotation rewritten based on wowsim APL: proper ICD-aware Eclipse fishing, correct Insect Swarm timing
- Removed Maul from Bear and Bearweave rotations (player decision)
- Bearweave toggle now driven by mode selection instead of DB setting

## [1.0.0] - 2026-03-15

### Added
- Initial release as PriorityHelper (renamed from DruidHelper)
- **Druid support**: Cat (DPS), Cat + Bearweave (DPS), Bear (Tank), Boomkin (DPS)
- Generic framework with registration API for multi-class support
- Feral cat rotation with SR/Rip desync logic, Clearcasting, FF weaving
- Bearweaving (Lacerateweave) with entry/exit timing
- Balance rotation with Eclipse fishing
- Movable icon display with cooldown sweep animations
- Range indicator for melee abilities
- Live debug frame (`/ph live`)
- Slash commands (`/ph`)
