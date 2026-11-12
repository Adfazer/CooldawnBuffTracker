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

**Current Version:** 1.16.1

## Credits

- **Adfazer** - Original author
- **Claude** - Co-developer and contributor

## License

This project is distributed under the [MIT License](LICENSE), which allows you to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software, subject to the conditions in the license.
