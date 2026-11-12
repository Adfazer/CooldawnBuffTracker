# CooldawnBuffTracker

An addon for tracking buffs and cooldowns in ArcheAge Classic.

## Description

CooldawnBuffTracker helps players track buff durations and ability cooldowns in an intuitive visual interface. This allows for more efficient skill usage and better action planning during combat.

Track buffs and debuffs for multiple unit types.

## Installation

1. Copy the `CooldawnBuffTracker` folder into
   `Documents\AAClassic\Addon\`, so that the file layout is
   `Addon\CooldawnBuffTracker\main.lua`.
2. Add one line with the folder name to `Documents\AAClassic\Addon\addons.txt`:

   ```
   CooldawnBuffTracker
   ```

3. Restart the client or run `/reload`. The addon appears in the in-game Addon
   Manager; the settings window opens from there (Options button).

Keep the folder name exactly `CooldawnBuffTracker` — it is the addon id used for
settings storage and all `require` paths.

## Features

### Core
- **Multi-unit tracking** — player, pet/mount and target at the same time, each
  with its own panel and settings.
- **Custom buff system** — track any buff by its numeric ID, even if it is not
  in the default list.
- **Real-time timers** — remaining buff duration and cooldown, shown on the icon.
- **Color-coded status** — green = active, red = on cooldown, white = ready.

### Icon layout
- **Configurable grid** — arrange icons in a grid of `Columns × Rows` and cap how
  many are shown with `Max icons`. Icons fill left-to-right, top-to-bottom. A
  single row reproduces the classic horizontal bar.
  - Examples: `10×1` bar, `5×4` block, `15×2` wide bar.
- **Icon size & spacing** — icon dimensions and the horizontal gap between icons.
- **Row spacing** — a separate vertical gap between grid rows.
- **Draggable panel** — drag each panel into place; a small empty "handle" on the
  right is always grabbable. Position can be locked to prevent accidental moves.

### Appearance
- **Buff name label** — optional name under each icon, with its own font size,
  offset, and **Label color**.
- **Timer** — font size and **Text color** for the countdown.

### Configuration management
- **Settings presets** — save the full layout (position, size, colors, grid, and
  tracked buffs) for all unit types as a named preset, and load it any time.
- **Import / Export to file** — share your whole configuration as a file:
  - **Export** writes a uniquely-named file `cbt_config_<character>_<id>.txt`
    into the `CooldawnBuffTracker` addon folder.
  - **Import** loads such a file by name (the `.txt` extension is optional).

### Custom buffs
- Add a buff by ID with name, cooldown and time-of-action.
- **Spell trigger** — optional spell name from the combat log (exact, as shown in
  the log). When another player hits you with that spell, its cooldown is stored
  for that player: target him and the target panel shows the remaining cooldown.
  If you have not targeted him yet, the hit is remembered by name and applied
  when you first target him (if the cooldown has not expired). Your own casts
  restart your player/mount panels. Useful for instant skills with no cast bar
  and no trackable aura.
- **Icon** — for a spell trigger the skill icon is learned automatically from the
  game the first time the spell is seen in the combat log (by its spell id); if
  the id is unknown you can leave the ID field empty and the spell name becomes
  the key. The tracked-buff ID field also accepts the buff name or the spell
  name instead of the numeric id.
- Each entry has **Add** (start tracking it for the currently selected unit type)
  and **Remove** buttons.
- Long lists are paginated; all custom buffs are saved automatically.

### Target tracking
- Real-time monitoring of buffs/debuffs on the current target.
- Smart caching: when you switch targets, buff state is preserved and restored if
  you return to a unit; stale cache is cleared after 5 minutes.
- Independent position/size/display settings.

### Debugging
- **Debug mode** — print buff IDs to chat to identify new buffs to track.

## How the timers work

- The addon reads the real remaining time of every tracked buff from the game
  (`UnitBuff.timeLeft`) for player, mount and target. The countdown therefore
  matches the game's own buff timer and is correct even when the buff was
  already active before you logged in, targeted the unit or reloaded the UI.
- Cooldowns are counted from the moment the buff was applied. If a buff is
  removed early (dispelled, target died), the green highlight ends immediately
  and the remaining cooldown is shown. Example: a 3 s buff with a 30 s cooldown,
  targeted with 2 s left, shows 29 s; if it is dispelled with 1 s left, the icon
  switches to a red 28 s countdown.
- Buffs/auras that report no remaining time (for example an item skill without
  its own duration) use the configured time-of-action, so the green phase and
  the cooldown follow your custom values; set 0 for an instant effect.
  This is the fallback whenever the game does not report a remaining time.

## Using Import / Export

Open the settings window and click the Import/Export button.

- **Export your setup:** click **“Save my config to a file”**. The addon writes
  `cbt_config_<character>_<id>.txt` into the `CooldawnBuffTracker` folder and
  shows the path. Hand that file to anyone.
- **Import someone's setup:** put the received file into the
  `CooldawnBuffTracker` folder, type its name into the field (extension optional),
  and click **“Load config from file”**.

A configuration contains your custom buffs and the tracked-buff lists for player,
mount and target.

## Changelog

### 1.7.6

- Debug: ON now dumps the raw `COMBAT_MSG` arguments (1..14) and the parsed
  spellId/spellName for every matched spell, to diagnose why the client returns
  no icon for a skill (spellId was reported as 0).

### 1.7.5

- Skill-icon lookup is now logged under **Debug: ON**: the spell id from the
  combat log, the path/name the client returned (SkillTooltip, then BuffTooltip
  as a fallback), or the error. This shows why an icon is missing.
- The fallback icon is now the neutral buff icon instead of the red
  "no entry" placeholder.

### 1.7.4

- Spell-trigger diagnostics under the existing **Debug: ON** toggle: chat now says
  whether a matched spell was a self cast (and on which panels it fired), whether
  the cooldown was stored for a player, or whether the attacker is still unknown
  and waiting for the first target.
- If the configured time-of-action is longer than the cooldown, the green phase
  is clamped to the cooldown so the ready state is still reached.

### 1.7.3

- The buff-ID field now accepts the custom buff name or the spell name as well
  as the numeric id, and its length limit is 32 characters.
- Custom buffs added with an empty ID are migrated: their key becomes the spell
  name (or the display name), including entries already sitting in the tracked
  lists.

### 1.7.2

- No skill id needed: leave the ID field empty and the spell name becomes the key.
- Skill icons are learned automatically: on the first matched combat-log event
  the addon asks the game for the skill icon by its spell id
  (`api.Skill:GetSkillTooltip`) and saves the path in the custom buff.
- A custom buff may now carry an explicit `iconFile` path, which takes priority
  over the built-in icon table.

### 1.7.1

- The spell trigger now remembers **who** cast the spell: cooldowns are stored
  per player and the target panel shows them when you target that player.
- A hit from a player you have not targeted yet is remembered by name and applied
  the first time you target him (unless the cooldown has already expired).
- Your own casts restart your player/mount panels, not the target panel.
- Spell and player names are compared exactly as the game reports them (no
  case folding, which would break localized/Cyrillic spell names).

### 1.7.0

- Custom buffs get an optional **Spell** field: the spell name as it appears in
  the combat log. Every `COMBAT_MSG` with that spell name (including hits on
  you) restarts the buff's active phase and cooldown. This covers instant
  skills that have no cast bar and no trackable aura.

### 1.6.3

- Buffs with no remaining time reported by the game (for example an item skill
  that has no duration of its own) now use the configured time-of-action for the
  green phase instead of being treated as permanent. Set 0 for an instant
  effect; the cooldown then follows your custom value as usual.

### 1.6.2

- The green "active" phase is now capped by the configured time-of-action: a
  buff configured as 0.1 s (or 0) no longer stays green for the whole long aura
  reported by the game API; it switches to the cooldown right away.
- Zero time-of-action is allowed (instant buff) instead of being replaced with
  the 3 s default.
- Remaining-time re-sync only applies while the API remainder fits the
  configured duration, so a long aura cannot push the active phase forward
  every tick.

### 1.6.1

- Fixed: buff panels no longer render above the inventory, auction and other
  windows (reverted the HUD UI-layer change to the previous z-order behaviour).
- Fixed the settings window: clicks on Position X/Y no longer hit the
  "Show label" / "Lock" buttons; the Save button and font-size changes apply
  correctly again.
- Numeric fields now also apply on Enter (same logic as Save).

### 1.6.0

- Timers are now equally accurate for player, mount and target: the real
  remaining time comes from the game API instead of a local countdown started
  from the configured duration.
- Early removal of a buff immediately switches the icon to its cooldown with the
  correct remainder (dispelled debuff no longer stays green).
- Buff icons for unknown ids are now resolved through the game API (`GetBuffTooltip`), with
  the built-in icon table kept as the primary source for known ids and a default icon last.
- Settings are no longer written from the per-frame update; import/export keeps
  fractional cooldowns (e.g. 16.2 instead of 16).
- Removed dead modules, fixed widget leaks on `/reload`, and switched panels to
  the HUD UI layer.

### 1.5.0

- Grid layout (columns × rows, max icons), row spacing, presets, import/export.

## Version

**Current Version:** 1.7.6

## Credits

- **Adfazer** - Original author
- **Claude** - Co-developer and contributor

## License

This project is distributed under the [MIT License](LICENSE), which allows you to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software, subject to the conditions in the license.
