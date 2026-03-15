# Changelog

All notable changes to PriorityHelper will be documented in this file.

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
