# CooldawnBuffTracker

A self-contained **ArcheAge Classic** addon for tracking buffs, debuffs and
skill cooldowns on the **Player**, **Mount** and **Target** at the same time.

The addon folder, settings id and display name are all **`CooldawnBuffTracker`**;
the historical spelling is kept everywhere to avoid a second identity.

> **Version 2.0.0** · AAC client patch 293 · No external library dependencies
>
> The previous public release was **1.5.0**. See [CHANGELOG.md](CHANGELOG.md)
> for the complete history.

## Highlights

- **Three units, any number of panels.** Player, mount and target each have
  independent floating panels. Every unit can own several **canvases**, each
  with its own position, grid, colours, timer and tracked entries.
- **Typed custom entries.** Track a buff/debuff by id, a skill by its exact
  combat-log name, or a mount skill by its mana cost. The type is chosen once
  and stays fixed; Edit shows the type read-only.
- **Target overlay.** Draw an additional compact row at the target's screen
  position. It works with TrackThatPlease and sits **above** TTP's target row;
  `Hide target canvas` remains a separate, independent switch.
- **Effective cooldowns (target only).** User-defined flat, percent and reset
  modifiers, stack-aware, plus a “smart %” learned per target from early
  re-use. No hardcoded class or skillset tables.
- **Record and debug journal.** While Debug is on, the addon keeps a buff
  journal per unit, plus a combat-log skill log split by source
  (Player/Mount/Target).
- **323 class-tree skill entries** (245 active with morphs, 78 passive) merged
  into the icon pool. 321 use the game's native `game/ui/icon/icon_skill_*.dds`
  paths; two morphs without a native base use a packaged PNG fallback.
- **Four languages.** English (default), Русский, Türkçe and 한국어. Switching
  changes the UI, tooltips and chat messages immediately; a missing key falls
  back to English. Chinese was removed because the client font rendered it as
  boxes.
- **Tooltips on every control**, using a real `gametooltip`; **coloured chat
  output**, every line prefixed with `[CBT]`.
- **Presets and file import/export** for the full configuration.
- **Self-contained.** No `addonlibrary`/`AddonUILib` dependency. The addon uses
  only the client API and its own modules.

## Installation

1. Copy the `CooldawnBuffTracker` folder into
   `Documents\AAClassic\Addon\`, so that this file exists:
   `Addon\CooldawnBuffTracker\main.lua`.
2. Add one line to `Documents\AAClassic\Addon\addons.txt`:

   ```
   CooldawnBuffTracker
   ```

3. Restart the client or run `/reload`.

Keep the folder name exactly `CooldawnBuffTracker`; it is the addon id used for
settings storage and all `require` paths.

Open the settings from the in-game Addon Manager (Options), the ESC menu's
Addon Options panel, or the ESCMenu addon if installed.

## Quick start

1. Open **Settings** and choose a unit: **Mount**, **Player** or **Target**.
2. Choose or create a **Canvas** (the selector on the unit row). Each canvas is
   an independent panel.
3. Add an entry under **Custom entries**:
   - **Buff/Debuff** — numeric id + name + cooldown + duration;
   - **Skill** — combat-log spell name + cooldown (+ optional display name);
   - **Mana skill** — mount skill name + mana cost + mount name + cooldown.
4. Press **Add entry**, then add the entry to the tracked list of the canvas.
5. Drag the canvas where you want it. Layout, colours and position are saved
   automatically.

The ID/name field filters existing custom entries as you type. The icon search
opens from the icon preview and closes as soon as an icon is picked.

## Units, canvases and layout

- **Unit selector** — Mount / Player / Target. Each unit has its own settings.
- **Canvas selector** — switch, add, rename or delete panels of the selected
  unit. Deleting a canvas removes its tracked entries after confirmation.
- **Grid** — columns × rows, maximum icons, icon size (16–64 px), icon spacing
  and row spacing.
- **Position and lock** — drag a panel by its handle; lock it to prevent
  accidental movement.
- **Names and timer** — optional name under each icon (font, offset, colour),
  timer font and text colour.
- **Panel layers** — floating HUD canvases stay below the game's windows;
  addon windows use the normal window layer. Clicking a window header raises
  it like a stock window.

## Custom entries

The **Add custom entry** form has three types. Only the fields of the selected
type are shown; the type is fixed after creation.

| Type | Required | Optional | Key |
|---|---|---|---|
| **Buff/Debuff** | ID, Name, Cooldown, Duration | Icon | Numeric id |
| **Skill** | Spell, Cooldown | Name, Icon | Exact combat-log spell name |
| **Mana skill** | Name, Cooldown, Mana, Mount | Icon | Name |

- **Buff/Debuff** reads the aura on the unit and uses the real remaining time.
- **Skill** is triggered by its name in the combat log. Hits from another
  player are remembered by name, then attached to that player when you target
  them. Your own casts restart the Player/Mount panels. Works for instant
  skills without a cast bar or trackable aura.
- **Mana skill** is detected from the mount's mana spend. Regen is estimated
  after a quiet window; the cost tolerance is adjusted for regen.
- **Icon** is optional. Without it the addon resolves an icon by id/name, then
  uses a neutral placeholder.
- **Mirror** (Target list only) displays a same-named buff/debuff from the
  player on the target. Available for buff/debuff entries only.
- Removing a **custom entry** also removes it from the tracked lists of all
  units; removing only from a tracked list keeps the catalog entry.

## Target tracking and overlay

The Target panel uses a five-minute cache: switching away preserves the last
state, returning restores the real remaining time, and a target that has not
been seen for five minutes is dropped.

The **Native frame display** block is shown only for the Target unit:

- **Overlay around target** — an additional compact row at the target's screen
  position. It follows the target every frame. It does **not** hide the
  floating canvas.
- **Hide target canvas** — hides the floating Target panel only. Buff tracking
  and the overlay continue.
- **Avoid TrackThatPlease** (default on) — when TTP is loaded, our overlay is
  anchored to its real `targetBuffCanvas` and drawn above it, separated by
  `Gap`. If the widget cannot be found, a computed fallback based on TTP's
  settings is used.

Overlay and Hide are independent: panel only, panel + overlay, overlay only,
or neither.

## Effective cooldowns

Effective CDs apply to **Target** buff/debuff and skill entries only.

Each entry can have a user-defined modifier list:

- **Flat** — seconds, subtracted first;
- **Percent** — additive percentages, applied after flat;
- **Reset** — when the modifier's aura appears, the entry's timer becomes 0 and
  smart learning pauses until the next application.

Each modifier is either **On target** (counts only while its aura is on the
target at the application moment) or **Always**. Values are multiplied by the
aura's stack count (1 if the aura reports no stack).

```
effective = max(0, base - sum(flat)) * (1 - sum(percent) / 100)
```

**Smart %** is optional and only percent-based. When the entry is re-used more
than 5% earlier than the cooldown predicted at the previous application, the
percentage is learned for that target and entry. State belongs to the target
id, survives while that target is current (the cache's `lastSeen` refreshes on
every scan), and is cleared with the target cache or when
`GetUnitClassName("target")` changes for the same id. Switching to another
target never touches the previous target's smart state.

The Edit window includes a reference card: base CD, flat total, percent total
with sources/stacks, effective now and the potential with every configured
modifier active.

## Skills, icons and the debug log

The icon pool merges:

- `buff_dump.tbl` — the shipped buff/icon dump and any local rescan;
- `skill_dump.tbl` — 323 class-tree skill entries from the ten AA Classic
  trees: Battlerage, Witchcraft, Defense, Auramancy, Occultism, Archery,
  Sorcery, Shadowplay, Songcraft and Vitalism.

Skill names are English base names (the wiki rank suffix is removed). The icon
search finds buffs and skills by name; `Spell: ON` also fills the Spell field.
A **buff rescan writes only `buff_dump.tbl`** and re-merges `skill_dump.tbl`;
the skill file is never overwritten.

**Record (Debug)** is visible only when Debug is on:

- **Buff log** — one row per buff id, with an appearance counter; active rows
  gold, faded rows grey. The journal accumulates in the addon core even while
  the window is closed (up to 300 entries per unit).
- **Log skills** — combat-log spells grouped by source: your character, the
  mount/pet, or the current target. Up to 200 per unit, with a counter.

## Languages and chat output

The `Language: English` control in the settings header opens a popup with
English, Русский, Türkçe and 한국어. The choice is saved immediately and
rebuilds the settings window; child windows are recreated so they cannot keep
old-language labels. Tooltips and chat lines are translated at use time.

Every addon chat line goes through one logger and starts with a coloured
`[CBT]` tag: info (white), success (green), warning (yellow), error (red),
debug (grey, Debug only). Names, ids and numbers are highlighted inside the
message.

## Configuration management

- **Presets** — save the full configuration (units, canvases, layouts,
  tracked entries, colours) under a name and load it later.
- **Import/Export** — export to a configuration file in the addon folder or
  import a received file by name.

## Compatibility and limitations

- Built for AAC client patch 293. API behavior may change in later client
  builds.
- `COMBAT_MSG` does not carry aura-applied/removed events; target skills are
  attributed from the combat log's spell name. Same-named mobs can collide.
- A skill with neither an aura nor a combat-log line needs the mount mana
  path or a manual trigger; no action channel exists in the addon sandbox.
- The target overlay uses TrackThatPlease's widget when available. If TTP
  changes its internal widget name or layout, the computed fallback is used.
- Korean may render as boxes if the client font lacks the glyphs. Chinese was
  removed for that reason; Korean is kept as an option and can be dropped the
  same way.
- The settings UI is intentionally wide. It is designed for the client's
  normal 1920×1080 layout, not a narrow window.

## Data and compatibility

- Settings are stored by `api.GetSettings("CooldawnBuffTracker")` and migrate
  automatically from older releases.
- **Upgrade from 1.5.0:** every old custom entry becomes **Buff/Debuff** and
  keeps its legacy `spellName` combat-log trigger; all entries go to the first
  canvas (`Main`). Old presets are normalized the same way when loaded, and
  imported 1.5.0 configuration files follow the same migration. Explicit
  `kind` values written by newer versions are preserved.
- `buff_dump.tbl` and `skill_dump.tbl` are Lua tables with a `dump` string.
- Runtime skill icons live in `skill_icons/` (`manifest.tsv` plus two PNG
  fallbacks); the 321 native paths are read from the game assets.
- The repository no longer carries a `CooldawnBuffTracker.yaml`. The addon
  manifest is maintained in the Classic Addon Manager catalog
  (`classic-addon-manager/addons/c/CooldawnBuffTracker.yaml`).

## Development

Offline checks used for this release:

```bash
python3 ~/.hermes/skills/software-development/aac-addon-dev/scripts/aac_check.py .
python3 ~/.hermes/skills/software-development/aac-addon-dev/scripts/aac_smoke.py .
python3 tests/migration_harness.py
python3 tests/ui_tooltips_harness.py
python3 tests/locale_harness.py
python3 tests/skill_icons_harness.py
python3 tests/eff_cd_harness.py
python3 tests/ttp_anchor_harness.py
```

The addon is MIT-licensed; see [LICENSE](LICENSE).

## Changelog

The full history, including the 1.5.0 baseline, is in [CHANGELOG.md](CHANGELOG.md).
