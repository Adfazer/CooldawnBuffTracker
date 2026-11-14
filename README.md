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
- **Multiple canvases per unit** — every unit type can show several independent
  panels at once. Each canvas has its own layout, position and tracked entries;
  the **Canvas** selector on the unit row adds, renames, deletes and
  switches them. Existing configurations migrate into a canvas named "Main".
- **Typed custom entries** — add a buff/debuff by its numeric ID, a skill by its
  combat-log spell name, or a mount mana skill, all from one form.
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

### Interface
- **Hover tooltips everywhere** — every button, field, list row and reference
  label explains what it does, its units and its range (icon size `16-64 px`,
  cooldowns in seconds, grid caps, overlay offsets). List rows use dynamic
  tooltips: the text is built when you hover, so it shows the current name,
  id, cooldown, duration, canvas or journal state.
- **Coloured chat log** — every addon message starts with a colour-coded
  `[CBT]` tag: white for information, green for successes, yellow for warnings,
  red for errors and grey for `Debug`-only diagnostics. Key values (ids, names,
  numbers) are highlighted.

### Configuration management
- **Settings presets** — save the full layout (position, size, colors, grid, and
  tracked buffs) for all unit types as a named preset, and load it any time.
- **Import / Export to file** — share your whole configuration as a file:
  - **Export** writes a uniquely-named file `cbt_config_<character>_<id>.txt`
    into the `CooldawnBuffTracker` addon folder.
  - **Import** loads such a file by name (the `.txt` extension is optional).

### Custom entries (typed)
The **Add custom entry** form has a type switch: **Buff/Debuff**, **Skill** or
**Mana skill**. The selected type is gold, the other two are muted, and the form
shows only the fields of that type.

- **Buff/Debuff** — `ID`, `Name`, `Cooldown`, `Duration`. The numeric buff id is
  the key; the icon comes from the buff table unless you pick one.
- **Skill** — `Name` (optional, used as the canvas label), `Cooldown`, `Spell`
  (exact name from the combat log — it becomes the key), `Icon`. When another
  player hits you with that spell, its cooldown is stored for that player: target
  him and the target panel shows the remaining cooldown. If you have not targeted
  him yet, the hit is remembered by name and applied when you first target him
  (if the cooldown has not expired). Your own casts restart your player/mount
  panels. Useful for instant skills with no cast bar and no trackable aura.
- **Mana skill** — `Name`, `Cooldown`, `Mana`, `Mount`, `Icon`: a mount skill
  tracked by the mana it spends (`UnitMana("playerpet")`).
- **Icon is optional for every type.** Click the icon preview to open the icon
  search (it opens with the current Spell/Name as the query); picking a row fills
  the path and closes the search. Without a picked icon the entry uses the icon
  of its id/name, else a neutral placeholder. The icon gallery
  (`cbt_icons.html` next to the addon) lists every file for manual reference.
- Each entry has **Add** (start tracking it for the currently selected unit type)
  and **Remove** buttons; **Edit** opens the same typed form and can change the
  type of an existing entry (older entries get their type derived from their
  data: mana cost → Mana skill, spell name → Skill, else Buff/Debuff).
- **Mirror** in the Target list is available for buffs/debuffs only — a skill or
  mana entry has no aura on the target to mirror.
- Long lists are paginated; all entries are saved automatically.

### Target tracking
- Real-time monitoring of buffs/debuffs on the current target.
- Smart caching: when you switch targets, buff state is preserved and restored if
  you return to a unit; stale cache is cleared after 5 minutes.
- Independent position/size/display settings.

### Native frame display (1.23.0, target only)

Two optional target switches attach the target panels to the game's own target
frame. They are off by default; turning them off restores the floating canvas
with its saved position. Configure them in the settings window, left column,
right under the `Unit: Mount / Player / Target` buttons — the block shows only
for **Target** (**Native frame display**); Mount and Player keep their floating
panels and have no frame-attached options.

- **Overlay around target** — each target canvas is drawn as its own compact
  overlay at the target's screen position (the same projection
  TrackThatPlease uses), with its own `X`, `Y`, `Size` and `Per row` fields in
  that canvas's layout. The position is re-read **every frame**, so the overlay
  follows a moving target; it is re-anchored only when the rounded position
  moved by a pixel, and hides when the target is lost or the projection is
  invalid. Overlay replaces the floating panel of that canvas.
- **Hide target canvas** — hides every floating target canvas. Buff data keeps
  running (timers are still tracked) and **Overlay** still draws when it is
  enabled. With Overlay off, nothing target-related is drawn — that is the
  chosen state, not a bug.
- **Avoid TrackThatPlease** (default ON) — when TrackThatPlease is loaded, the
  overlay row is placed **above** its target row, using TTP's own
  `targetBuffVerticalOffset` and `targetIconSize` (and the client UI scale).
  `Gap` sets the space between the rows (default 4 px). With TTP absent the
  overlay uses the canvas `X`/`Y` offsets from the target's screen position.
  Frame visibility and the target are re-checked twice a second; the overlay
  hides with the frame and with no target.

The merged under-bar strip (`Under HP/MP bar`) and its `Reserved Y` field were
removed in 1.26.0: the target overlay is the only frame-attached display mode,
and floating canvases stay exactly where the user put them.

### Debugging
- **Debug mode** — print buff IDs to chat to identify new buffs to track.
- **Record (Debug)** window (Debug mode ON) — one journal per unit, switched
  with `Player / Mount / Target`:
  - **Buff log** — every buff/debuff seen since Debug was switched on, one row
    per buff: `name [id] (xN)`. `xN` counts how many times the buff appeared;
    a buff that fades and returns increases the counter instead of adding a
    second row. Active rows are gold, faded rows grey; `Add` works on both.
    The journal is kept by the addon core while Debug is ON, so it accumulates
    even with this window closed (sampled every 200 ms, up to 300 entries per
    unit, reset on Debug OFF → ON).
  - **Log skills** — spells from the combat log, grouped by source name: your
    own casts go to Player, the mount/pet casts to Mount, casts by the current
    target to Target. Duplicates are counted (`xN`), each log keeps the last 200
    spells, and `Clear log` clears only the selected unit.

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

### 1.29.0

- **Hover tooltips on every control.** The settings window, the entry editor,
  the Record window, Presets, Import/Export, the icon search and the support
  window now explain their buttons, checkboxes, fields, colour pickers, icon
  previews, pagers and list rows on hover. Numeric fields state their units and
  ranges (`Icon size 16-64 px`, cooldowns in seconds, `Icons per row 1-20`,
  overlay `12-64 px`, ...). Window headers answer with `Drag to move the
  window.`; the close buttons say they close the window.
- **Dynamic row tooltips.** Tracked rows, custom-entry rows, modifier rows,
  record/skill rows, preset rows and icon-search rows build their tooltip text
  at hover time, so it reflects the current name, id, cooldown, duration,
  canvas, kind (buff/debuff, skill, mana skill), journal state or icon path.
- **Tooltip helper.** `CbtWindow.Tooltip(widget, text)` and
  `CbtWindow.TooltipDynamic(widget, fn)` share one implementation: `OnEnter`
  shows the text via `api.Interface:SetTooltipOnPos`, `OnLeave` clears it with
  `nil`, and the previous `OnEnter`/`OnLeave` handler (hover highlight) is
  chained instead of replaced. Nothing runs per frame.
- **One central chat logger** (`util/cbt_log.lua`). Every message starts with a
  colour-coded `[CBT]` tag: `info` white, `success` green, `warn` yellow,
  `error` red, `debug` grey and only printed while Debug is ON. Values can be
  highlighted with `CbtLog.hl()`; only ASCII and `|cAARRGGBB...|r` codes are
  used. All direct `api.Log` calls and the old `safeLog` wrapper were replaced
  across `main`, `helpers`, `buff_debugger`, `settings_page`,
  `import_export`, `record_window` and `icon_search_window` with the same
  messages, wording and frequency as before.

### 1.28.1

- The entry type (Buff/Debuff, Skill, Mana skill) is now fixed at creation: the Edit
  window shows it as a read-only label with a note «set at creation, cannot be changed»
  instead of the type buttons. Fields and validation follow the stored kind.

### 1.28.0

- **Effective CDs for target entries.** A buff/debuff or skill custom entry can
  now reduce its own timer by user-defined modifiers. The feature is target-only:
  Player and Mount entries keep the configured cooldown, and mana skills are not
  offered it.
- **Modifiers are fully user-defined.** Each entry stores `effectiveCDs`
  (on/off), `smartPct` (0 = off) and `cdMods`: a list of
  `{ id/name, kind = flat | percent | reset, value, condition = target | always }`.
  `flat` is seconds, `percent` is a percentage, `reset` carries no value. A
  conditional modifier counts only while its buff/debuff is on the target; an
  `always` modifier always counts. There are no built-in skillsets or tables.
- **Formula:** `eff = max(0, base - sumFlat) * (1 - sumPercent / 100)` — flat
  seconds first, then the additive sum of the percentages (10% + 20% = 30%).
  Every value is multiplied by the stack count read from the target's aura
  (1 when the aura reports no stack).
- **Reset modifiers** zero the entry's timer when their buff appears on the
  target: the buff/debuff active phase ends and the skill becomes ready. A
  reset pauses smart until the next application, and that interval is never
  used as evidence for an early re-use.
- **Smart reduction %** learns the real cooldown ratio per target id. On each
  application the actual interval is compared with the cooldown predicted at
  the previous application; applying more than 5% earlier marks the percentage
  as learned for that target and it applies from then on. State lives in the
  target cache (`targetCache[id].smart[entry]`) and is cleared with the cache.
  `api.Ability:GetUnitClassName('target')` is stored per target id: a class
  change (a respec) clears smart **for that id only**; switching targets never
  touches the previous target's state, and mobs (`Pending`) never reset it.
- **Edit window** grew to 640×600 and gained the Effective CDs block: the
  checkbox, the target-only stack note, a modifier list (`Source | Type | Value
  | Condition | Remove`, type and condition cycle on click), an add field for
  ID/name, an unconditional flat/percent adder, the Smart % field with its
  `Not learned` / `Learned for this target (+X%)` status and a live reference
  card (base CD, flat total, percent total with sources and stacks, effective
  now and the potential with every configured modifier active).
- The typed Add/Edit form, mirror gating, Record logs and the per-frame
  overlay are unchanged.

### 1.27.0

- **The Record buff journal accumulates in the background.** While `Debug: ON`
  the addon samples the active buffs/debuffs of Player, Mount and Target every
  200 ms and keeps one journal per unit — the `Record (Debug)` window no longer
  has to be open. Open it at any moment and it lists everything seen since
  Debug was switched on: one row per buff, `name [id] (xN)`, newest first,
  active rows gold and faded rows grey, up to 300 entries per unit. A buff that
  fades and returns grows its counter instead of adding a row.
- **Switching Debug OFF → ON resets the three journals**, exactly like the aura
  dump; `Clear log` wipes the journal of the selected unit only. Nothing is
  sampled while Debug is off, so the normal (non-debug) cost is unchanged.
- The window's private copy of the log is gone: `Buff log` reads the per-unit
  journal from the addon core, and `Clear log` clears that journal.

### 1.26.0

- **Target `Under HP/MP bar` mode removed completely.** The merged strip
  renderer, its strip holder windows, `target.underBars` / `target.stripOffsetY`,
  the `Under HP/MP bar` checkbox and label, the `Reserved Y` field and every
  Import/Export/preset mention are gone. The target overlay is the only
  frame-attached display mode; old saves drop the keys on load and old configs
  import without them.
- **New target switch `Hide target canvas`.** Hides all floating target
  canvases while buff scanning and timers keep running; the overlay still
  renders when it is on, and with Overlay off nothing target-related is drawn.
  Persisted in `target.hideCanvas` (default off), carried by presets and
  Import/Export, migrated for existing configurations.
- **Record buff log has no duplicates.** The buff tab keeps one row per buff,
  `name [id] (xN)`. The counter grows only when a buff appears again after it
  faded — while it stays active there are no repeated rows and no growth.
  `Clear log` resets the map of the selected unit. Active rows stay gold, faded
  rows grey.
- **Record skill log is per unit.** Combat-log spells are recorded into the
  Player, Mount or Target log by **source name**: a spell under your
  character's name goes to Player, under the mount/pet name to Mount, under the
  current target's name to Target (priority player → mount → target when names
  collide; a source that matches none is not logged). Each log keeps up to 200
  entries with a hit counter, `Clear log` clears only the selected unit, and the
  unit switch in the Record window now drives both tabs. Names are compared
  exactly (no `string.lower`, which does not fold Cyrillic).

### 1.25.0

- **Player `Under MP bar` display mode removed.** The player no longer has a
  frame-attached mode: `player.underMp`, its checkbox and label, the player
  `Reserved Y` and the merged player strip renderer are gone. Old saves drop the
  keys on load, Import/Export no longer carries them, and presets saved earlier
  simply ignore them. *(1.26.0 also removed the target `Under HP/MP bar` strip
  and the remaining `Reserved Y` field.)*
  **Native frame display** therefore shows nothing for Mount, nothing for
  Player, and only the target options for Target.
- **Target overlay follows the target at frame rate.** `GetUnitScreenPosition
  ("target")` is read on every `UPDATE` (NaN/Inf, an exploded projection or
  `z` outside the sane range hide the overlay) and each visible overlay window is
  re-anchored only when the rounded position moved by at least 1 px — the scheme
  TrackThatPlease uses. The row no longer lags or steps while the target moves,
  a stationary target stays perfectly still, and the overlay disappears as soon
  as the target is lost. Frame visibility, the MP/HP bar and TTP's private
  settings file stay on the 500 ms cache, so aura/buff polling is unchanged.

### 1.24.0

- Settings layout: the `Canvas:` row (dropdown, Add, Rename, Delete) moved up to the
  `Unit` row (`y=44`, `x 340..724`), and `Debug` / `Record (Debug)` became a column at
  the right edge (`x 1060`, `y 44` / `70`), so the `Icon settings` column now starts at
  `y=100` and nothing overlaps it.
- **Native frame display** moved out of the right column into the left one, directly
  under the unit buttons. The block shows only what applies to the selected unit
  (the Player row was dropped in 1.25.0, so only Target has controls now):
  Mount — nothing; Target — `Overlay around
  target`, `Under HP/MP bar`, `Avoid TrackThatPlease` + `Gap`, `Reserved Y`, and the
  per-canvas overlay `X` / `Y` / `Size` / `Per row` fields while Overlay is on
  (the strip and `Reserved Y` were removed in 1.26.0, the rest stays).
  `Tracked entries` moves down by exactly the height of the block (one anchor), the
  list is 208 px (9 rows) and the ID/name form with its pagination stays above the
  footer.
- `ID / name` autocomplete suggests only entries that exist in `Custom entries`
  (the dump search is gone); a row still inserts that entry's id. The popup stays at
  4 rows, or 3 while the overlay fields are shown, so it never spills out of the window.

### 1.23.1

- TrackThatPlease 3.1+ no longer keeps its target-row settings in the shared API
  table (it scrubs it and stores a private file). The overlay now reads
  `TrackThatPlease_settings.lua` (then `_backup`) to place our target row above TTP's
  row; the shared table is still tried first for older TTP versions.
- Settings layout: the `Reserved Y` field moved to its own row so it no longer
  overlaps the `Under HP/MP bar` label.

### 1.23.0

*(The under-bar strip this version added — player and target — was removed
again in 1.25.0 / 1.26.0; the target overlay described below is the part that
remains.)*

- **Native frame display modes** (all optional, off by default; floating
  canvases return when a mode is off):
  - **Player → Under MP bar**: all player canvases merge into one strip under the
    player frame's MP bar (HP bar if mana is hidden). Canvas order is preserved
    (canvas 1 entries, then canvas 2 …), max **9 icons per row**, no name labels,
    the canvas grid is ignored and extra icons wrap downwards. Icon size comes
    from the first player canvas (16–40). *(Removed in 1.25.0 — player panels are
    always floating.)*
  - **Target → Under HP/MP bar**: the same merged strip for all target canvases,
    below the target frame's MP bar (HP for mana-less targets).
  - **Target → Overlay around target**: every target canvas renders as its own
    overlay with per-canvas `X`, `Y`, `Size` (12–64) and `Per row` (1–12) fields,
    at the target's screen position — the projection TrackThatPlease uses. Both
    target modes can be enabled at once and render independently.
  - **Avoid TrackThatPlease** (default ON) + **Gap above TTP** (default 4 px):
    when TrackThatPlease is loaded its own `targetBuffVerticalOffset` /
    `targetIconSize` (with the client UI scale) place our overlay row directly
    above its target row. Without TTP the per-canvas offsets are used.
  - **Reserved Y** for the under-bar strips (default 0) to clear another addon's
    row. Frame visibility and target presence are checked ~twice per second; the
    strip hides with the frame or with no target, and re-anchors when the native
    frame or its MP/HP bar is recreated (never errors when `mpBar` is nil).
- All new fields persist in settings, presets and Import/Export
  (`player.underMp`, `target.overlay/underBars/avoidTTP/ttpGap/stripOffsetY`,
  `canvases[i].overlayX/overlayY/overlaySize/overlayPerRow`) with migration
  defaults for existing configurations. *(The player `underMp` key was removed
  again in 1.25.0 together with its mode.)*

### 1.22.0

- **Effective cooldowns removed completely.** The `effectiveCd` switch, the
  Effective CDs picker window, the per-target learning of skillset passives and
  the reset-proc handling are gone: the Target panel shows the configured
  cooldown again, like the player and mount panels. `effective_cd.lua`,
  `effective_cd_window.lua`, `classes.tbl`, `skillsets.tbl` and `cdmods.tbl`
  were deleted, together with the `permanent` custom-entry flag, so every
  custom entry is a normal entry with Remove/Edit again.
- **Typed Add form.** The Add custom entry block now has a type switch —
  **Buff/Debuff**, **Skill**, **Mana skill** — and shows only that type's fields
  with full labels (`ID:`, `Name:`, `Cooldown:`, `Duration:`, `Spell:`, `Mana:`,
  `Mount:` instead of the old NM/CD/D abbreviations). Buff: ID/Name/Cooldown/
  Duration on the first row. Skill: Name/Cooldown, with Spell on the second row.
  Mana: Name/Cooldown, with Mana+Mount on the second row. The icon preview sits
  at the right of the second row and **Add entry** on the third. Validation is
  per type (buff: id+name+cooldown+duration, skill: spell+cooldown, mana:
  name+cooldown+mana+mount) and the created entry carries
  `kind = "buff" | "skill" | "mana"`.
- **Icon picking from the preview.** The separate **Icon search** button is gone:
  clicking the icon preview opens the search with the current Spell/Name already
  typed, and picking a row fills the path and closes the search. The icon stays
  optional for every type (id/name lookup, then a neutral placeholder).
- **Typed Edit dialog** (`Cooldown / Duration`): same type switch, same fields,
  type detected from the entry when it opens (`manaCost > 0` → Mana skill,
  `spellName` set → Skill, else Buff/Debuff), validation on Save and `kind` saved
  back into `customBuffs`. The buff id is shown read-only because it is the key.
- **Mirror is buffs/debuffs only.** The Mir button is hidden for skill and mana
  entries, the mirror scan skips them, and switching an entry to Skill/Mana in
  Edit clears its `mirror` flag on every unit.

### 1.21.8

- Fixed the Record buff tab being empty: the 1.21.7 patch overwrote the existing
  `getActiveBuffs` provider with a forward-declared debug function that was still `nil`
  at load time. The working provider is restored; the buff log now fills again.

### 1.21.7

- Record (Debug) buff tab is now a persistent **buff log**: every buff/debuff seen on the
  selected unit is appended (newest first) and kept after it fades; live refresh every
  200 ms; active entries are gold, faded ones grey. **Clear log** works on both tabs
  (clears the buff log or the skill log depending on the active tab).
- The missing `getActiveBuffs` provider is implemented: the tab lists the current buffs
  and debuffs of Player / Mount / Target with id, name and icon (it was always empty).

### 1.21.6

- Vitalism list reduced to the two skills the user tracks: **Abyssal Petrification** and
  **Mirror Light** (the «Sacrificial Flame»: 90 s buff on an ally, 20 s debuff on an enemy).
  The other Vitalism skills were removed from the picker.

### 1.21.5

- Skillset table curated from the wiki noise: 117 trackable skills left.
  Removed Rising Hatred everywhere, plus Weak/Tough/Toughened/Spell Shield: Flame/Bleeding
  pseudo-entries; Battlerage: Soulbound Blades; Auramancy: Hollow Comet's Boon, Radiant
  Meditate, Teleportation; Occultism: Hollow Absorb Lifeforce, Radiant Mana Force;
  Sorcery: Flamebolt; Shadowplay: Radiant Stalker's Mark; Vitalism: Aranzeb's Boon,
  Hollow Renewal, Holy Bolt, Whirlwind's Blessing. Songcraft keeps only Abyssal Echoes,
  Alarm Call, Critical Discord, Dissonance, Double-Time, Polymorphic Resonance and
  Startling Strain. Defense keeps Toughen at 60 s (the 45 s entry was the buff variant).

### 1.21.4

- Fixed the data-file format: `classes.tbl`, `skillsets.tbl` and `cdmods.tbl` are now
  wrapped as `{ dump = "..." }` exactly like `buff_dump.tbl`, so `api.File:Read` can
  deserialize them. Previously they were plain TSV, File:Read returned nil and the
  Effective CDs picker showed trees but no skills. Now it lists 151 skills with icons
  across the 10 trees.

### 1.21.3

- Witchcraft buff **18475** (Exploitation) added as a stacking cooldown reduction:
  **-10% per stack**, capped at 5 stacks, applied to Witchcraft skills while the buff
  is on the target.

### 1.21.2

- Occultism cooldown buff **7657** added as a flat **-12 s** modifier (flat seconds are
  subtracted before the additive percentages).
- The Effective CDs controls moved into the picker window: the settings page has a single
  «Effective CDs» button; the picker carries the master **Enable** checkbox and
  **Reset learning**, so nothing overlaps the Debug/Record row.

### 1.21.1

- Always-on skillset passives: a target whose class contains **Battlerage** gets
  Attack Speed Training (-10% to all Battlerage skills), and a target whose class
  contains **Archery** gets Archery Expertise (-10% to Piercing Shot, Charged Bolt,
  Stalker's Mark, Missile Rain, Toxic Shot, Snipe). These are applied from the class
  table, not learned; the learner divides them out so they are not counted twice.

### 1.21.0

- **Effective cooldowns for the Target panel.** New `effectiveCd` master checkbox
  (off by default) with a tooltip: base CD + known skillset candidates +
  per-target learning from observed re-use; reset procs are handled separately,
  off = the configured CD. Player/mount panels are untouched.
- **Effective CDs picker** (settings window): ten skillset tabs, every skill that
  has a base cooldown, icon + name + CD + checkbox, 15 rows per page. Checking a
  skill creates a permanent entry (`id`, `name`, `cooldown`, `spellName`,
  `iconFile`, `tree`, `permanent`) and tracks it on the selected Target canvas;
  unchecking removes it from `customBuffs`, every `trackedBuffs` list, `canvasOf`
  and `mirror`. Permanent entries have no Remove/Edit buttons in the custom list.
- **Data tables** shipped next to the addon: `classes.tbl` (117 classes → three
  skillsets), `skillsets.tbl` (skill → tree, base CD variants, kind, icon) and
  `cdmods.tbl` (buff ids/names → percentage, flat, per-stack and reset effects).
  Icons were parsed from the wiki skill cards; skills without one fall back to
  `buff_dump.tbl`, then to a neutral placeholder. The picker can reload the tables.
- **Model:** `eff = max(0, base - sumFlat) * (1 - sumPct/100)` with additive
  percentages. Target class via `GetUnitClassName` + `classes.tbl`; visible Battle
  Focus rank 2/3 (7651/13612), 9000610, Rhythm, Mana Fountain, Inspired and
  Exploitation apply only while their aura is present.
- **Learning:** per-target tree ratios snapped to candidate values (0.90, 0.86,
  0.80, 0.76, 0.65, ...), applied to the whole tree after two consistent
  observations, 30-minute TTL, **Reset learning** button, debug line
  `[CBT] effCD: skill base=… flat=… pct=… eff=… tree=… target=…`.
- **Reset procs:** Deflect and Retaliate (2611, ICD 12 s) readies Battlerage,
  Quick Recovery (by name, ICD 12 s) readies Vitalism; an unexplained early
  re-use (<50% of the CD) is treated as a reset and does not change the ratio.
- Fervent Healing is marked `repeat-growth` in `skillsets.tbl`: its growing
  repeat interval is never learned as a cooldown reduction.

### 1.20.3

- Debug aura log is written to a file instead of chat: while Debug is on, the target's
  buffs/debuffs are polled every 100 ms and appended to
  `CooldawnBuffTracker/aura_dump.tbl` (flushed once a second, reset when Debug is enabled,
  target id/name and class/skillsets included). Chat only announces the dump path.

### 1.20.2

- Debug: continuous target aura log instead of the manual Dump button. While Debug is on,
  the addon polls the target's buffs/debuffs every 100 ms and prints every appearance,
  removal and stack change as `[CBT] + / ~ / - <kind> id= name= stack= time=`. Short
  (sub-second) buffs are captured. Target class and skillsets are printed on target change.

### 1.20.1

- Debug: target dump button (replaced in 1.20.2 by continuous logging).

### 1.20.0

- **Multiple canvases per unit.** Mount, Player and Target can each own several
  independent panels. The new **Canvas** row above the tracked list switches the
  current canvas and offers `Add`, `Rename` and `Delete` (delete asks for
  confirmation and removes the canvas together with its tracked entries).
- The whole right column — icon size/spacing, grid (columns/rows/max/row spacing),
  Position X/Y and Lock, timer font/colour, label font/offset/colour — now belongs
  to the **selected canvas** of the selected unit; switching the canvas refills
  every field with that canvas's values.
- Tracked entries are filtered per canvas, in their original order. Every row has
  an **Mv** button that moves the entry to another canvas of the same unit.
- One aura scan per unit is kept: canvases only draw their own subsets, so adding
  canvases costs no extra API polling.
- Existing settings migrate automatically: the old flat layout becomes the first
  canvas named "Main"; tracked lists and mirror flags are kept untouched.
- Presets and Import/Export now store canvases, per-entry canvas assignment and
  the selected canvas per unit; old preset/config files still load into canvas 1.

### 1.19.0

- Custom entries: the name column moved right (x=90) with a wider 56 px ID column, so the
  ID no longer overlaps the name.

### 1.18.9

- «Record (Debug)» moved to the right of the Debug button (same row).
- The ID/name input is shorter (180 px) and the Add button moved left (250..330), so it no
  longer runs under the «Add custom entry:» label.

### 1.18.8

- Tracked column narrowed and aligned with the unit selector: the name now sits right
  next to Up (no dead gap), rows end at the Target button's right edge, and the whole
  block starts on the same x as the unit label.
- Custom block starts right after it and is much wider: 52 px ID, 144 px name, evenly
  spaced CD/D/Add/Remove/Edit; ID and name use 13–14 px fonts.
- Tracked names use a 14 px font too.
- Pagination buttons are anchored below their lists instead of on top of the last row.
- Import/Export and Presets moved to the bottom-left corner; the autocomplete popup is
  raised to the dialog layer so it is never hidden behind them.
- “Thank you for your hard work!” moved to the bottom-right next to Save, so validation
  errors are visible.

### 1.18.7

- Settings layout rebuilt as a tidy grid: tracked and custom lists now share the same top,
  height and pagination row; forms sit below them at the same level.
- Tracked list no longer overflows its container (content width matched the rows), so its
  buttons no longer run under the custom block.
- Custom rows: 52 px ID column (long ids no longer merge with the name), 114 px name,
  evenly spaced CD / D / Add / Remove / Edit; row buttons use a 12 px font.
- Custom form: ID / NM / CD / D on one aligned row, Spell / Icon + preview on the next,
  Mana / Mount below, then Add entry / Icon search.

### 1.18.6

- Tracked entries show only the buff name (the ID column is gone), so the name no longer
  overlaps anything; the row and its buttons shifted left.
- Custom entries keep both ID and name: the ID is hidden when it duplicates the name or
  Spell, and the Spell suffix is only added when it differs. The name column is wider and
  the whole custom block moved 20 px left / widened by 20 px.
- Mana skills no longer carry the `[M]` prefix or the green name colour — uniform look.

### 1.18.5

- Cooldown/Duration dialog title no longer duplicates identical name / Spell / id: the
  string is assembled from distinct parts only, and long titles are truncated to fit.
- The hint is split into two short lines, so nothing overflows the small dialog.

### 1.18.4

- Layer model fixed: tracked buff panels are pinned to the `game` layer (above the world,
  below windows), while every addon window sits on `normal` — the same layer as the stock
  inventory/auction windows. Settings are no longer hidden behind the tracked panels and
  no longer force themselves above game windows.

### 1.18.3

- All addon windows moved from the `dialog` layer to the `game` layer — the same as the
  inventory/auction, so they no longer sit above every game window; a header click/drag
  raises the window among its siblings.
- Cooldown/Duration dialog: Cancel moved next to Save (it used to overlap the Mount field).
- Settings form: Mana and Mount fields are now above the Add entry / Icon search buttons;
  the Mount input no longer sits under them.

### 1.18.2

- Mana entries: only name, mana cost, mount name and cooldown are required; ID, Spell,
  duration and icon are optional (the key falls back to the name).
- Mount field moved to its own row so it no longer overlaps the icon-settings column.
- Mana detection: mount name matched case-insensitively and as a substring of the pet
  name; pet name falls back to GetUnitNameById when UnitName is nil; cost tolerance
  widened to ±max(3, 20%). Debug «no match» now prints the pet name, blocked counters
  and every tracked mana entry with its mount/ready state.

### 1.18.1

- Mana regen uses a single estimate (no in-combat/out-of-combat split): one EMA value,
  updated only when 5 seconds have passed since the last detected mana spend.
- Combat-state event no longer registered for this feature.

### 1.18.0

- **Mount skills by mana spend**: custom entries can carry a mana cost and a mount name.
  With a mana cost set the entry is a mana skill (`[M]` badge) — it is detected on the
  Mount list by a drop in the mount's mana, not by an aura or the combat log.
- Mana is sampled every 100 ms; regen is estimated empirically as an EMA separately in
  combat and out of combat (`UNIT_COMBAT_STATE_CHANGED`) and added back to the observed
  drop before matching a skill cost (±max(2, 15%)).
- Mount name is optional: empty matches any mount, otherwise only that mount's spends
  are attributed to the entry. Both fields are editable in the Edit dialog.
- Mana entries may omit the buff id (key = skill name); icon falls back to the neutral
  default if none is picked.

### 1.17.3

- All addon windows (except the main settings window) now have a taller full-width title
  bar (34 px) with a separator line; the title label is click-through, so the whole bar
  reliably starts a drag instead of swallowing clicks.
- Import/Export buttons rebuilt with the shared dark button helper (same look and hover
  as the rest of the addon); the native light skin and the flat repaint hack are gone.

### 1.17.2

- Mirror button now shows its state explicitly: «Mir ON» (green) / «Mir OFF» (grey).
  Row rebalanced again (name 110, Up 30, Down 38, Mir 56, Remove 64).

### 1.17.1

- Mirror is now bound to the target that was current when the aura appeared: switching
  the target removes the mirrored entry from the Target panel (the aura itself stays on
  the player). Returning to that target re-shows it with the real remaining time.
- Works for both buffs and debuffs (the player's buff and debuff lists are scanned).
- Mirror entries are marked as present in the poll, so the disappearance logic does not
  end their active phase every tick.

### 1.17.0

- **Mirror** toggle («Mir») on tracked entries in the Target list. With it on, the
  addon reads the same-named aura from **player** (remaining time and stacks) and
  shows it in the Target panel as if the debuff were on the current target;
  attribution is simply whoever is the target when the aura appears — no combat-log
  parsing involved.
- Tracked row rebalanced for the new button (name 110 px, Up/Down/Mir/Remove).

### 1.16.9

- Debug diagnostics: compact `[CBT] msg <event> src= tgt= spell= id=` line and
  `[CBT] cast <spell> by <caster>` from SPELLCAST_START.

### 1.16.8

- Record window: new «Clear log» button (visible on the Log skills tab) wipes the
  combat-log spell journal.
- Record window refreshes in real time while open (every 400 ms via OnUpdate), not
  only when switching tabs.

### 1.16.7

- Removing an entry in **Custom entries** now also removes it from **Tracked entries**
  on all three units (a custom entry without tracking makes no sense). Removing
  from Tracked entries still keeps the custom entry in the catalog.

### 1.16.6

Skill audit fixes (aac-addon-dev):
- Icon search window now uses the shared `CbtWindow` shell, so dragging works
  (`RegisterForDrag("LeftButton")` + `OnDragEnd`) and there is no fourth shell copy.
- Custom entries row: CD / D / Add / Remove / Edit no longer overlap; the ID error
  panel sits below the field instead of over it; autocomplete is capped at 4 rows
  so it cannot spill outside the window.
- «Unit:» label width fixed; decorative labels are now click-through; buttons are
  created as clipped children where possible.
- OnUnload saves canvas positions BEFORE freeing widgets; canvas offsets read
  `GetEffectiveOffset` first.
- `settings.enabled` master switch now applies both ways (OnSettingToggle shows or
  hides the panels).
- Removed the dead `ADDON_CBT_BUFFS_EMPTY` subscription; the combat-log receiver is
  hidden and click-through; record/CD-D windows tear down through `CbtWindow.Destroy`.
- Presets module: exported functions now bind to the forward locals (the Presets
  button works again), 7 rows per page, dark error panel.
- Import/Export: dead colour line removed, dark error panel.
- Added `CooldawnBuffTracker.yaml` manifest.
- Name label updates are change-driven (no per-tick SetText/SetColor).

### 1.16.5

- Add form: button renamed «Add entry»; the left input label is «ID/name:» and the
  field moved right so the label no longer overlaps the text.
- Import/Export window: compact 600x330, the long file hint shortened, the
  redundant «Close» button removed (the header X and ESC close it).
- Presets window: the redundant «Close» button removed as well.

### 1.16.4

- Denser lists: tracked entries 11 per page, custom entries 8 per page, row step
  22 px (was 23) — the containers are filled instead of leaving half the height empty.
- ID column widened (44 px) and names shifted right, font 12 — the id no longer
  runs into the name in both lists.

### 1.16.3

- «Unit:» label no longer overlaps the Mount/Player/Target buttons (short label,
  buttons shifted right).
- Page sizes now fill the list containers: tracked entries 9 per page, custom
  entries 6 per page (was 4 / 3 with a lot of empty space).

### 1.16.2

- Unit selector (Mount / Player / Target) moved to the left column above the
  tracked list.
- Bottom bar (Debug / Import-Export / Presets / Thanks / Save) now sits inside
  the window: bottom anchors used a positive y that pushed them below the frame.
- Debug button moved above the custom list; Record (Debug) sits right under it
  and appears only with Debug: ON.
- Renamed for the wider scope (buffs, debuffs, skills; the addon name is
  unchanged): «Buff list» → «Tracked entries», «Custom Buffs» → «Custom entries»,
  «Add Custom Buff» → «Add custom entry», «Buff ID» → «ID / name»; empty states
  are «Nothing tracked yet» / «No custom entries yet».

### 1.16.1

- Fixed the right column overlap: Grid moved 20 px down (below Show label) and
  Icon position now anchors under the grid's last field, so Grid / Position /
  Timer no longer stack on top of each other.

### 1.16.0

- Settings window redesigned for landscape: 1200x600, three columns —
  tracked buffs | custom buffs + add form | icon/grid/position/timer. Uniform
  field widths, aligned rows, Save button inside the window, Debug / Import /
  Presets / Thanks moved to a bottom bar.
- Saving keeps the current page of both lists (Enter-to-apply too); switching
  the unit type still resets the page by design.

### 1.15.3

- Removed the Edit button from the tracked Buff list: CD/D are edited in the
  Custom Buffs list only (one place, no duplicate entry points). Buff-list row
  buttons are back to their wider positions.

### 1.15.2

- Added the Edit (CD/D) button to the **Custom Buffs** list as well, next to
  Add/Remove. It edits the same `settings.customBuffs` entry, then applies the
  values to the live entries of all three panels (readyAt/activeUntil are
  recomputed from the same fixed start) and refreshes both lists.

### 1.15.1

- Fixed the Edit (CD/D) dialog: the custom empty window was created but never
  shown (`CreateEmptyWindow` starts hidden) — added `Show(true)`.

### 1.15.0

- **Edit** button in every tracked-buff row opens the Cooldown / Duration editor.
  For a custom buff it updates the custom entry; for a regular buff it stores a
  per-buff override. Values apply immediately and both lists refresh.
- The «Search» button is gone: the Buff ID field now has **live search** — matches
  appear under the field as you type (custom buffs first, then the icon dump);
  click a row to fill the id.
- Icons are shown in both lists (tracked buffs and custom buffs).
- Removed the obsolete buff_search_window module.

### 1.14.1

- Record window: unit selector (Player / Mount / Target); the Active buffs tab
  defaults to Player and «Add» uses the selected unit.
- A skill recorded from the log gets its icon automatically from the buff dump
  (name lookup), CD/D still left for manual tuning.
- All custom windows can be dragged again: handles now also call
  `RegisterForDrag("LeftButton")` and handle `OnDragEnd` (the AddonUILib pattern).
- The «Search» button next to the tracked-buff input is back; its list now also
  includes custom buffs/skills by name, so the exact name no longer has to be typed.

### 1.14.0

- Removed the duplicate «Find icon» button from the main settings form: the icon
  search window owns the dump scan («Scan dump»).
- Icon search: new «Spell: ON/OFF» toggle — when ON, picking a row also fills the
  custom buff's Spell field with the picked name (handy, but optional).
- Every log line and UI label is now English.
- New **Record (Debug)** window (button «Record (Debug)» appears next to the Buff
  list when Debug: ON): lists active buffs/debuffs of the current unit and skills
  seen in the combat log. «Add» records a buff as a custom entry + tracking; a
  skill becomes a custom entry with Spell filled automatically (CD/D left for
  manual tuning).
- Combat-log spell names are captured into a 200-entry ring for that window.

### 1.13.4

- Reverted the speculative cooldown-anchor experiments (`unitPollSeen`,
  `SPELLCAST_START` anchor): the real cause of the drift was a passive cooldown
  reduction the user had not accounted for. Anchoring is back to the long-standing
  rule — player/mount start at the first sighting of the aura, target estimates
  from the server remainder.
- Kept every real fix: custom buff CD/D/name/icon taken from the custom entry (no
  more 30/3 defaults), name-based matching, the green phase runs the full duration
  (no clamp when CD < D), target triggers honour custom CD/D, and the trigger
  debounce now only suppresses repeats during an active phase (DoT ticks).

### 1.13.3

- The cooldown start now anchors to the last `SPELLCAST_START` when a new aura
  appears within 6 s of it: for cast-time skills the aura appears at cast end,
  so anchoring there made the addon's cooldown end a few seconds later than the
  action-bar cooldown. Debug: ON logs every `SPELLCAST_START/STOP/SUCCEEDED`
  with its arguments.

### 1.13.2

- Removed the per-row «CD/D» button and its dialog: CD/D are already set on the
  custom-buff form, the duplicate control only confused.
- Custom buffs are matched to auras by id **or by display name / spell name**, so
  an entry keyed by name still contributes its CD/D to the panel entry. Before,
  such entries fell through to the empty built-in table and used CD=30 / D=3
  (the "addon shows more cooldown" case).
- Debug: ON logs the custom buff list at load: `[CBT] custom: id=… name=… spell=… CD=… D=…`.

### 1.13.1

- The CD/D editor is opened by a **button** in each tracked-buff row («CD/D»),
  not by clicking the name label: labels created through `CreateWidget` inside an
  addon-built row do not receive `OnClick` reliably, while buttons do (the same
  proven widgets as Up/Down/Remove). Row buttons shifted to make room.

### 1.13.0

- Regular (non-custom) tracked buffs can now take their own CD/D: **click the buff
  name in the tracked list** to open a small dialog (Cooldown / Duration / Reset).
  Values are stored in `settings.buffOverrides[id]`, apply to new entries and
  immediately to live ones (readyAt is recomputed from the same fixed start).
  Why: the built-in buff table (`ALL_BUFFS`) is empty, so every regular buff
  silently used CD=30 / D=3 — a real 21 s cooldown then showed ~9 s too much.

### 1.12.4

- If the combat log already started the entry (synthetic anchor), the aura poll no
  longer moves the start to the moment the aura appears: the cooldown keeps
  counting from the cast, so a delayed aura cannot push readiness later (the
  "addon shows more cooldown than the skill" case).
- Target-side spell triggers now use the custom buff's CD/D instead of the
  built-in buff-table defaults.

### 1.12.3

- Combat-log spell triggers are debounced: DoT ticks and repeats of the same
  spell no longer restart the cooldown. While the aura is present the debounce
  window equals the buff duration, otherwise the cooldown. Previously every tick
  re-anchored the start to the tick moment, so a dispelled buff showed a cooldown
  off by the time since the last tick.
- Debug: ON now prints timing lines
  `[CBT] timer <id> <old>-><new> now=.. D=.. CD=.. fixed=.. ready=.. rem=..`
  so the anchor can be verified against the game.

### 1.12.2

- Cooldown start is anchored to the moment the aura is actually seen on a unit we
  were already polling, instead of being back-calculated from the configured
  duration. Any mismatch between the configured D and the real aura shifted the
  start (a few seconds), so a dispelled buff showed the cooldown off by that
  amount. Only the very first poll after load / target switch still estimates the
  start from the API remainder; later new auras count as fresh applications.
- Removed the per-poll re-sync that recomputed the start from D (it kept the same
  bias). Verified offline: CD 21 / D 90, dispel at 5 s → 16 s of cooldown left,
  ready at 21 s.

### 1.12.1

- Fixed custom buffs ignoring their own CD/D: panel entries were created from the
  built-in buff table (cooldown defaulted to 30 s), so a custom buff with CD=0 and
  D=10 glowed green for 10 s and then showed a bogus 20 s cooldown. The entry now
  takes CD/D/name/icon from the custom buff, and existing entries are refreshed on
  load and on every buff-list change.
- The active (green) phase is no longer clamped to the cooldown: when CD ≤ D the
  icon stays green for the whole duration and then goes ready — no phantom red
  phase (CD=0 now works as expected).

### 1.12.0

- All remaining addon windows now use the same custom dark shell
  (`util/cbt_window.lua`): Buff Search, Presets, Import/Export and Support.
  Each has the dark nine-part plate, own header with title, close button, drag
  grip and ESC close.
- Their light 0.92-grey list panels are dark now; import/export buttons are
  flattened to the dark style; edits are tinted dark with light text.

### 1.11.0

- The settings and icon-search windows are now fully custom (BetterBars style):
  `CreateEmptyWindow` + dark nine-part plate, own header strip with a gold title,
  close button and drag grip — no more native cream title bar/frame. ESC closes
  them (`SetCloseOnEscape` + `OnCloseByEsc`), drag handlers are released on
  unload.

### 1.10.0

- Settings UI restyled to match BetterBars/Power Ranger: flat dark buttons with
  gold labels (no more cream native buttons), dark list containers with dimmed
  borders instead of the light 0.92-grey panels.
- Layout fixes: the unit selector moved below the title bar; the custom-buff form
  is a clean grid (ID / Name / CD / D on one row, Spell + Icon on the next,
  buttons on their own row) — the CD/D edits no longer sit under the Find icon
  button; the error panel moved below the form.

### 1.9.2

- Fixed the "settings window without text": a window-level colour drawable sank
  under the native window texture and the light labels became invisible on the
  client's light theme. The dark plate is now a child `emptywidget` created
  before the sections (above the window background, below the controls), and the
  labels are back to the theme's gold, readable on both dark and light themes.

### 1.9.1

- Registered in the **default ESC menu**: the addon now builds/uses the
  community `michaelClient` «Addon Options» panel on the system config frame
  (`ADDON:GetContent(UIC.SYSTEM_CONFIG_FRAME)`) — that is why BetterBars shows up
  there and we did not. With the ESCMenu addon installed, ESCMenu hides that
  panel and reroutes the same title into its own grid.

### 1.9.0

- **Icon search window** (button «Поиск иконки»): type a name and see live matches
  with icon previews from the buff dump; click a row to put the icon into the
  custom-buff form; a «Скан баффов» button rebuilds the dump in place.
- **Dark theme** for the settings window: near-black backdrop, light labels,
  gold accents (Power Ranger style).
- **ESC menu integration**: a row «Cooldown Buff Tracker» is registered in the
  ESCMenu addon (System/Addons column) when that addon is installed; the stock
  Addon Manager now shows the Options button too (top-level `settings.enabled`).
- `settings.enabled` acts as a master switch (the Addon Manager checkbox hides
  and shows the HUD panels).
- The buff dump is now written into the addon folder
  (`CooldawnBuffTracker/buff_dump.tbl`); the Addon-root copy is read only as a
  legacy fallback.

### 1.8.6

- Removed the diagnostic buff-id probes from the scan — no per-skill ids or
  names are hardcoded anywhere, lookup is purely by name from the dump.

### 1.8.5

- The buff dump (21 014 entries, id/name/icon) is now shipped inside the addon as
  `buff_dump.tbl` and loaded at startup when no fresh dump exists in the Addon
  root — no scanning needed out of the box.
- Icon paths from the dump are normalized (`Game\ui\icon\...` → `game/ui/icon/...`)
  so they render.
- Custom buffs without an icon get it automatically from the dump by spell name
  at load (e.g. Sacrifice → icon_skill_buff281.dds); names with "(Rank N)" are
  also indexed by their base name.

### 1.8.4

- Skill-tooltip scanning is dropped: the addon API always requests
  `SIK_DESCRIPTION`, and that table has description/synergy fields only —
  `name`/`path`/`type` are nil (confirmed by probes 13282, 10455, 23587, ...).
- **Find icon** now dumps the **buff** tooltips instead (`api.Ability:GetBuffTooltip`,
  ids 1..50000 and 8000000..8001000) into `buff_dump.tbl`: id, name and icon path.
  Most skills share their name with the buff they apply, so the lookup by spell
  name still works; the dump is loaded at startup and reused without scanning.

### 1.8.3

- Scan diagnostics: on start it probes 12 known client skill types (13282,
  10455, 23587, ...) and logs name/path/type plus the table fields, and the final
  line now reports how many tooltip tables, names and errors the scan saw — to
  explain an empty dump.
- Entries without an icon path are kept in the dump (path filled later).

### 1.8.2

- **Find icon** now dumps **all** client skill tooltips (id → name → icon path)
  into `skill_dump.tbl` in the addon folder instead of stopping at the first
  match, and reuses that dump on the next lookup/load — no repeated scans.
- The dump is loaded at startup when present; a name found in it is applied
  immediately. Leave Spell empty and press Find icon to refresh the dump.

### 1.8.1

- **Find icon** button in the custom-buff form: scans the client's skill tooltips
  by name and, when the skill is found, fills the icon path and updates custom
  buffs with the same spell name. Needed for skills whose spellId is 0 in the
  combat log (the client cannot resolve their icon by id).
- Log under Debug: ON shows the scan progress and the found id/name/path.

### 1.8.0

- Custom buffs get an optional **Icon** field: a file name from the game's icon
  set (`icon_skill_buff141.dds`) or a full path. Enter previews it in the form.
  The icon is used immediately and saved with the buff.
- A searchable icon gallery with previews is provided next to the addon
  (`cbt_icons.html`) so the right file can be found without guessing.

### 1.7.7

- Self casts are recorded for your own unit as well: if you target yourself, the
  Target panel now shows the cooldown too (a target is a target). Casts made while
  someone else is targeted still go only to the Player/Mount panels.

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

**Current Version:** 1.29.0

## Credits

- **Adfazer** - Original author
- **Claude** - Co-developer and contributor

## License

This project is distributed under the [MIT License](LICENSE), which allows you to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software, subject to the conditions in the license.
