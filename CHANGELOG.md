# Changelog

## 4.0
Complete rewrite of ScaledLifeTap 3.

**New**
- Reads exact shadow spell damage, including buffs, from ClassicAPI (`GetSpellBonusDamage`) or Nampower (`GetSpellPower`) when present.
- BonusScanner is no longer used: a built-in gear scanner gives the same totals and also works on German and French clients. It can still be forced with `/slt source bonusscanner`.
- Mana check (Nampower): compares the mana each tap actually gives with the prediction and learns a correction if your server differs. See `/slt calibrate`.
- `/slt` commands: `cast`, `status`, `overtap`, `reserve`, `bonus`, `source`, `calibrate`, `debug`, `rescan`.
- Health reserve: never tap below a set % of max health.

**Fixed**
- Game freeze when Life Tap wasn't in the spellbook (the spellbook loop never ended).
- Settings were never saved (a `local SLT_Config` hid the saved variable).
- Overtap could cast rank 1 even when it would take more health than you had.

**Changed**
- Gear is scanned only after your equipment changes, and only on the next cast. No per-frame work.
- Spellbook and talents are cached and refreshed on events.
- Improved Life Tap is found by name, so a reordered talent tree doesn't break it.
- Casts by spellbook slot, so rank text localization no longer matters.
- Replaced the config window, which never worked, with `/slt` commands.

## 3
- Previous release by Kimilly. Required BonusScanner.
