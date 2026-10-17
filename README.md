# ScaledLifeTap

A World of Warcraft **1.12.1** addon for Warlocks. One button casts the highest **Life Tap** rank that fits into your missing mana, so you never waste health on mana you can't hold.

It accounts for your shadow spell damage, Improved Life Tap and (optionally) a health safety floor. Version 4 is a rewrite of Kimilly's ScaledLifeTap 3. It no longer uses BonusScanner, so you can uninstall it unless another addon needs it.

## Features

- **Picks the right rank automatically.** Goes from rank 6 down and casts the first one whose mana return fits.
- **Exact spell damage with client mods.** With [ClassicAPI](https://github.com/brues-code/ClassicAPI) or [Nampower](https://github.com/pepopo978/nampower), it reads the spell damage number the game client itself calculates. That includes buffs such as elixirs, flasks and trinkets.
- **Works without any mods.** A built-in gear scanner reads your item tooltips. It gives the same totals BonusScanner did, and works on English, German and French clients.
- **Mana check (Nampower).** Compares the mana each tap actually gives with the prediction, and adjusts itself if your server's Life Tap numbers differ.
- **Health safety floor.** Optionally never taps below a set percentage of your health.
- **Light.** No per-frame work. Gear is rescanned only after your equipment changes.
- **English, German and French clients.**

## Installation

1. Download the latest zip from [Releases](../../releases), or use **Code → Download ZIP**.
2. Extract it into `World of Warcraft\Interface\AddOns\`.
3. Make sure the folder is named exactly **`ScaledLifeTap`**. GitHub's "Download ZIP" names it `ScaledLifeTap-main`, so rename it.
4. If you used the old version (v3), delete its folder first. Your overtap setting carries over.

## Usage

Make a macro and put it on your bar:

```
/slt cast
```

Old macros using `/script ScaledLifeTap_CastLifeTap()` keep working.

### Commands

| Command | What it does |
|---|---|
| `/slt status` | Shows your spell damage and its source, the talent multiplier, and the health cost and mana gained for each rank |
| `/slt overtap [on\|off]` | When no rank fits but mana isn't full, cast rank 1 anyway (default: on) |
| `/slt reserve <0-90>` | Never tap below this % of max health (default: 0) |
| `/slt bonus <n>` | Add extra spell damage by hand. Only useful without ClassicAPI or Nampower, for buffs the gear scan can't see |
| `/slt source <name>` | Where spell damage comes from: `auto` (default), `classicapi`, `nampower`, `bonusscanner` or `internal` |
| `/slt calibrate [on\|off\|reset]` | Turn the mana check on or off, or reset what it has learned (needs Nampower) |
| `/slt debug [on\|off]` | Print each cast to chat |
| `/slt rescan` | Force a rescan of gear, spellbook and talents |

## Where spell damage comes from

With `source auto`, the first one available is used:

| Source | Includes buffs | Notes |
|---|---|---|
| ClassicAPI | Yes | `GetSpellBonusDamage(6)` |
| Nampower | Yes | `GetSpellPower()`. Also enables the mana check |
| Built-in scanner | No | Always available |

**Running ClassicAPI and Nampower together** (the usual setup) works fine. Spell damage comes from ClassicAPI; both mods read the same number, so it makes no difference which is used. The mana check still uses Nampower.

BonusScanner is never chosen automatically. `/slt source bonusscanner` forces it, but that's rarely useful: it gives the same totals as the built-in scanner on English clients, and likely 0 on German and French clients.

On Nampower versions older than 4.5, the mana check needs its event turned on once:
`/run SetCVar("NP_EnableSpellEnergizeEvents","1")`

## How the rank is chosen

For each rank, from highest to lowest:

- **Health cost** = base + coefficient × shadow spell damage
- **Mana gained** = health cost × Improved Life Tap (1.0 / 1.1 / 1.2) × server correction (from the mana check, normally 1.0)

| Rank | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| Base health | 30 | 75 | 140 | 220 | 310 | 424 |
| Coefficient | 0.38 | 0.68 | 0.8 | 0.8 | 0.8 | 0.8 |

Ranks 1 and 2 get a lower coefficient because of the low-level spell penalty. The addon casts the first rank where mana gained ≤ missing mana and you'd keep more health than your reserve.

## Development

The code targets the Lua 5.0 that the 1.12 client embeds. The tests run the addon against a mock of the WoW API. Run them from the repository root with a Lua 5.0 interpreter:

```
lua5.0 tests/test_core.lua . path/to/BonusScanner
lua5.0 tests/test_sources.lua . path/to/BonusScanner
```

`test_core.lua` checks the built-in scanner against [BonusScanner](https://github.com/jrc13245/BonusScanner) on the same gear, so it needs a copy of that.

## Credits

- **Kimilly**: ScaledLifeTap up to version 3.
- **Aredia (Gilneas)**: original macro, research and calculations.
- **Crowley**: BonusScanner, whose gear patterns the built-in scanner is based on.

See [CHANGELOG.md](CHANGELOG.md) for version history.
