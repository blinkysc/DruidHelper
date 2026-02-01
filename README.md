# DruidHelper

A rotation helper addon for Feral Druid DPS in World of Warcraft 3.3.5a (WotLK), designed primarily for players learning or improving their **bearweaving** technique.

Bearweaving is an advanced Feral DPS tactic that can boost your damage by ~4-6%, but the timing and decision-making can be difficult to master. This addon shows you exactly when to shift into bear, what abilities to use, and when to shift back to cat.

## Who Is This For?

- Feral Druids who want to learn bearweaving
- Players looking to optimize their Lacerateweave rotation
- Anyone wanting real-time feedback on bearweave entry/exit timing

## Features

### Bearweaving (Lacerateweave)
- **Entry timing** - Shows when conditions are right to shift to Dire Bear Form (energy < 40, no Clearcasting, Rip safe, etc.)
- **Bear rotation** - Focuses purely on building and maintaining 5-stack Lacerate
- **Exit timing** - Tells you when to shift back to cat (energy > 70, Rip expiring, Clearcasting proc)
- **Live status** - Debug frame shows current bearweave state (`/dh live`)

### Full Cat DPS Rotation
- **Priority-based rotation** following the optimal WotLK Feral guide
- **Bleed and buff tracking** - Rip, Rake, Savage Roar, Mangle with pandemic-style refresh windows
- **SR/Rip Desync Logic** - Clips Savage Roar early when needed to prevent combo point starvation
- **Clearcasting detection** - Prioritizes free Shred procs
- **Faerie Fire weaving** - Uses FF for Omen of Clarity procs
- **External Mangle/Trauma Detection** - Skips Mangle if another player has the debuff up

### UI
- Movable icon display with cooldown sweep animations
- Shows next 3 recommended abilities
- Range indicator for melee abilities
- Optional live debug frame (`/dh live`)

## Installation

1. Download or clone this repository
2. Copy the `DruidHelper` folder to your `Interface/AddOns` directory
3. Restart WoW or `/reload`

## Usage

The addon automatically shows recommendations when you have a target in combat.

### Slash Commands

| Command | Description |
|---------|-------------|
| `/dh` | Show all commands |
| `/dh toggle` | Enable/disable addon |
| `/dh bearweave` | Toggle bearweaving (Lacerateweave) |
| `/dh lock` | Lock/unlock display position |
| `/dh reset` | Reset display position |
| `/dh scale <0.5-2.0>` | Set display scale |
| `/dh live` | Toggle live debug frame |
| `/dh cat` | Show detailed cat form status |
| `/dh bear` | Show bearweave status |
| `/dh debug` | Toggle debug mode |

## Rotation Priority (Cat)

1. **Tiger's Fury** - When energy < 40
2. **Berserk** - When TF on cooldown for 15+ seconds
3. **Savage Roar** - Maintain (or clip early for desync)
4. **Mangle** - Maintain debuff (skipped if external source)
5. **Rip** - At 5 combo points
6. **Ferocious Bite** - When safe (Rip 10+ sec, SR 8+ sec remaining)
7. **Rake** - Maintain
8. **Clearcasting Shred** - Free damage
9. **Faerie Fire (Feral)** - For OoC procs
10. **Bearweave** - If enabled and conditions met
11. **Shred** - Filler

## Bearweaving Guide

Bearweaving is the technique of shifting to Dire Bear Form during energy-starved moments to deal damage (and build Lacerate stacks) while passively regenerating energy. When done correctly, you never miss a Cat Form ability because you're always back before capping energy.

### Enable Bearweaving
```
/dh bearweave
```

### When to Enter Bear (addon handles this)
- Energy < 40 (nothing to cast in cat)
- No Clearcasting proc (don't waste free Shred)
- Rip has > 4.5 seconds remaining (safety margin)
- Savage Roar has > 4 seconds remaining
- Berserk is not active (spam cat abilities during Berserk)
- You have 5/5 Furor talent (gives 10 rage on shift)

### What to Do in Bear
The addon recommends **Lacerateweave** - focusing purely on the Lacerate bleed:
1. Build Lacerate to 5 stacks
2. Refresh Lacerate before it falls off
3. Exit to cat when Lacerate is healthy (5 stacks, 9+ sec remaining)

### When to Exit Bear (addon handles this)
- Energy > 70 (approaching cap)
- Rip will expire in < 3 seconds
- Clearcasting procs (use it in cat)
- Lacerate is at 5 stacks with 9+ seconds remaining

### Tips for Learning
1. Enable the live debug frame: `/dh live`
2. Watch for "BW_RDY" indicator (bearweave conditions met)
3. Practice on a training dummy first
4. The addon shows bear abilities while in bear form

## Requirements

- World of Warcraft 3.3.5a client
- Druid class

## License

MIT
