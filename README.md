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
  the **Canvas** selector above the tracked list adds, renames, deletes and
  switches them. Existing configurations migrate into a canvas named "Main".
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
  name instead of the numeric id. If the game reports no icon, type a file name
  from the icon gallery (`cbt_icons.html` next to the addon) into the **Icon**
  field — Enter previews it.
- Each entry has **Add** (start tracking it for the currently selected unit type)
  and **Remove** buttons.
- Long lists are paginated; all custom buffs are saved automatically.

### Target tracking
- Real-time monitoring of buffs/debuffs on the current target.
- Smart caching: when you switch targets, buff state is preserved and restored if
  you return to a unit; stale cache is cleared after 5 minutes.
- Independent position/size/display settings.

### Effective cooldowns (Target only)
- **Effective CD (Target)** checkbox in the settings window turns the feature on
  (`effectiveCd`, off by default). It only changes the Target panel; player and
  mount keep the configured cooldown.
- **Effective CDs** opens a picker with the ten skillsets (Battlerage, Witchcraft,
  Defense, Auramancy, Occultism, Archery, Sorcery, Shadowplay, Songcraft,
  Vitalism). It lists every skill that has a base cooldown, with icon, CD and a
  checkbox. Checking a skill creates a permanent entry (id, name, cooldown, spell
  name, icon and tree from `skillsets.tbl`) and tracks it on the selected Target
  canvas. Unchecking is the only way to remove such an entry; permanent entries
  have no Remove/Edit buttons in the custom list.
- **Formula:** `eff = max(0, base - sumFlat) * (1 - sumPct/100)`; flat seconds are
  subtracted first and percentages add up (10% + 20% = 30%).
- **Target class** comes from `GetUnitClassName` mapped through `classes.tbl`;
  mobs return `Pending` and rely on learning only.
- **Visible buffs** apply while they are on the target: Battle Focus rank 2 (id
  7651, -35%) and rank 3 (id 13612, -40%) to Battlerage, buff 9000610 (-10% to
  everything), Rhythm (-0.4 s per stack), Mana Fountain (-2% per stack),
  Inspired (-0.6/-2.1/-1.2 s) and Exploitation (-10% per stack).
- **Learning:** no passive is assumed up front. Repeated casts of a tracked skill
  are compared with its base CD, the observed ratio is snapped to a known
  candidate (0.90, 0.86, 0.80, 0.76, 0.65, ...) and after two consistent
  observations it is applied to every tracked skill of that tree for that target
  only. Learned state expires 30 minutes after the target was last seen, and
  **Reset learning** clears it.
- **Reset procs** are handled separately: Deflect and Retaliate (id 2611, ICD
  12 s) readies all Battlerage timers, Quick Recovery (by name, ICD 12 s) readies
  Vitalism; a single far-too-early re-use also reads the tree as reset without
  changing the learned ratio.
- All game numbers live in `classes.tbl`, `skillsets.tbl` and `cdmods.tbl` next to
  the addon and can be edited (the picker's **Reload tables** re-reads them).

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

**Current Version:** 1.21.5

## Credits

- **Adfazer** - Original author
- **Claude** - Co-developer and contributor

## License

This project is distributed under the [MIT License](LICENSE), which allows you to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software, subject to the conditions in the license.
