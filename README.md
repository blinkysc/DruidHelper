# DruidHelper

A rotation helper addon for Feral Druid DPS in World of Warcraft 3.3.5a (WotLK). Similar to Hekili, it provides real-time ability recommendations based on your current state.

## Features

### Feral Cat DPS
- **Priority-based rotation** following the optimal WotLK Feral guide
- **Bleed and buff tracking** - Rip, Rake, Savage Roar, Mangle with pandemic-style refresh windows
- **Clearcasting detection** - Prioritizes free Shred procs
- **Faerie Fire weaving** - Uses FF for Omen of Clarity procs when appropriate
- **Tiger's Fury and Berserk timing** - Optimal cooldown usage

### Advanced Tactics
- **SR/Rip Desync Logic** - Clips Savage Roar early (up to 10 sec) when Rip would expire shortly after, preventing combo point starvation
- **Bearweaving (Lacerateweave)** - Shifts to Dire Bear Form when energy-starved to maintain a 5-stack Lacerate bleed for extra DPS
- **External Mangle/Trauma Detection** - Skips Mangle if an Arms warrior or another druid is already keeping the bleed debuff up

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

## Bearweaving

When enabled (`/dh bearweave`), the addon will recommend shifting to Dire Bear Form when:
- Energy < 40
- No Clearcasting proc active
- Rip has > 4.5 seconds remaining
- Berserk is not active
- 5/5 Furor talent

In bear form, it focuses purely on maintaining a 5-stack Lacerate bleed, then exits back to cat form.

## Requirements

- World of Warcraft 3.3.5a client
- Druid class

## License

MIT
