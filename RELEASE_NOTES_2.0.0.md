# CooldawnBuffTracker 2.0.0

**Status:** release-candidate notes, not published. No tag, GitHub release or
catalog update has been made.

**Base:** `v1.5.0` (`7fce312`, `main`)
**Target branch:** `refactor/aac-skill-audit`
**Code diff:** 106 commits, 34 files, +37,905 / −3,545 (before the release
documentation pass).

## Summary

2.0.0 is a full UI and behavior release after the 1.5.0 baseline. It keeps the
same addon id (`CooldawnBuffTracker`), settings key and folder name, so existing
installations upgrade in place. The display name is **CooldawnBuffTracker**
(the historical spelling is intentional and matches the manager).

The release adds independent canvases, typed entries, target overlays,
per-entry effective cooldowns, four-language UI, real hover tooltips, a
coloured `[CBT]` chat logger, a persistent debug journal and the complete
class-tree icon pool. It also removes the old Effective CDs experimental
system and the addon's unused library dependency.

## Highlights

### Panels and units

- Player, Mount and Target each support **any number of canvases**. Every
  canvas owns its position, grid, icon size/spacing, timer, colours and tracked
  entries; `Add`, `Rename`, `Delete` and `Mv` live in the Canvas row.
- Existing 1.5.0 layouts migrate into a first canvas named `Main`.
- Floating panels stay on the HUD/game layer; addon windows use the normal
  window layer and raise on header click.

### Entries and skills

- The Add form has three fixed types:
  - **Buff/Debuff** — id, name, cooldown, duration;
  - **Skill** — combat-log spell name, cooldown, optional name;
  - **Mana skill** — mount skill name, mana cost, mount name, cooldown.
- Type is chosen once and is read-only in Edit.
- Skill entries are triggered from `COMBAT_MSG`; hits from another player are
  buffered by name and attached when that player is first targeted. Self casts
  restart the Player/Mount panels.
- Mount skills are detected from the pet's mana spend with an empirical regen
  estimate and a cost tolerance.
- Mirror is available for buff/debuff entries only.

### Target overlay and TrackThatPlease

- `Overlay around target` draws an extra compact row at the target's screen
  position; it follows the target every frame.
- `Hide target canvas` hides the floating Target panel only. Overlay and Hide
  are independent.
- With TrackThatPlease loaded, the overlay anchors to its real
  `targetBuffCanvas` (`BOTTOM → TOPLEFT`, `-Gap`) and is drawn above TTP on the
  `normal` layer. If the widget cannot be resolved, a computed fallback based
  on TTP's private settings is used.

### Effective cooldowns

- Target-only, per-entry, fully user-defined modifiers:
  - **Flat** seconds, subtracted first;
  - **Percent** values, additive after flat;
  - **Reset** on the modifier aura (zeroes the timer and pauses smart until the
    next application).
- Each modifier is `On target` or `Always`; values multiply by the target
  aura's stack count (fallback 1).
- Formula: `max(0, base - Σflat) × (1 - Σpct/100)`.
- **Smart %** is percent-only, learns after a >5% early re-use, is stored per
  target id + entry, survives while the target is active, and resets with the
  target cache or a class change for the same id.
- Edit contains a reference card: base, flat total, percent total with
  sources/stacks, effective now, potential.

### Interface and localization

- Four languages: English (default), Russian, Turkish, Korean. Chinese was
  removed because the client font rendered it as boxes; a stored `zh` migrates
  to `en`.
- Switching rebuilds the settings window, recreates cached child windows and
  changes UI, tooltips and chat lines. No `/reload`.
- Every control has a real `gametooltip`; labels use transparent hover proxies
  that hide with their label and never cover child buttons.
- All chat messages use one logger with a coloured `[CBT]` tag and
  info/success/warn/error/debug levels.
- The main settings window has no Save button: Enter applies text fields,
  toggles/colours apply immediately, closing applies the full save.

### Record, icons and configuration

- Record keeps a per-unit buff journal while Debug is on (one row per id,
  appearance counter, active/faded colours, up to 300 entries) and a per-source
  skill log (Player/Mount/Target, up to 200 each).
- Icon search merges `buff_dump.tbl` and `skill_dump.tbl`:
  - 323 skill entries from the ten class trees, 245 active/morphs + 78 passive;
  - 321 native `game/ui/icon/icon_skill_*.dds` paths, verified against the
    client asset manifest (`fat_aac.json`, 0 missing);
  - two PNG fallbacks for `Radiant Revive` and `Hollow Renewal`.
- A buff rescan writes only `buff_dump.tbl`; `skill_dump.tbl` is re-read and
  re-merged, never overwritten.
- Presets and file import/export store the complete configuration.

## Breaking changes and migration

- **Effective CDs 1.x picker removed.** Its classes/skillsets tables and
  hardcoded passives are gone. The replacement is the per-entry user-defined
  modifier system; no built-in class tables remain.
- **Type is fixed at creation.** An existing entry cannot be converted between
  Buff/Debuff, Skill and Mana skill; create a new entry instead.
- **Overlay no longer hides the floating panel.** Use `Hide target canvas` for
  that; both switches are independent.
- **Chinese removed** (`zh` → `en`); Korean remains and must be checked against
  the user's client font.
- **Main settings Save button removed.** Add/Edit entry, preset save and canvas
  rename still have their own confirm buttons.
- **No `addonlibrary` dependency.** The repository no longer carries a
  `CooldawnBuffTracker.yaml`; the Classic Addon Manager manifest is maintained
  in the catalog repository.
- Existing settings, presets and imported configurations migrate
  automatically. **Every 1.5.0 entry becomes Buff/Debuff**; a legacy
  `spellName` trigger is preserved. The old flat layout becomes the first
  canvas (`Main`), and all old tracked entries go to canvas 1. Old presets are
  normalized through the same path when loaded.

## Known limitations

- `COMBAT_MSG` has no aura-applied/removed events. Target skill attribution is
  name-based; same-named mobs can collide, and a pure debuff with no damage and
  no cast line is not observable.
- A skill with neither an aura nor a combat-log line needs the mount-mana path;
  the addon has no keyboard/action channel.
- TTP anchoring depends on its internal `targetBuffCanvas`; if TTP renames or
  restructures it, the computed fallback is used.
- The client font may lack Korean glyphs; test before advertising Korean as
  fully supported.
- The UI is designed for the normal 1920×1080 client layout; very small
  resolutions may need manual window placement.

## Validation

Offline checks for this candidate:

- `aac_check.py` — PASS, 0 errors, 5 justified warnings.
- `aac_smoke.py` — PASS, 6/6 phases, 0 warnings.
- `migration_harness.py` — PASS, 1.5.0 entries → buff/debuff on canvas 1,
  legacy spell triggers and old presets preserved.
- `ui_tooltips_harness.py` — PASS, 200+ tooltip registrations, no per-frame work.
- `locale_harness.py` — PASS, four languages and child-window rebuild.
- `skill_icons_harness.py` — PASS, native paths, two PNG fallbacks, scan safety.
- `eff_cd_harness.py` — PASS, formula, stacks, smart/reset behavior.
- `ttp_anchor_harness.py` — PASS, anchor/fallback/Overlay-Hide matrix.

The tooltip, language, icon, effective-CD and TTP checks are offline sandbox
tests; an in-game smoke test of the full settings/overlay flow is still
required before publishing.

## Release checklist (not executed)

1. Review and merge `refactor/aac-skill-audit` into `main` (or decide to
   publish from the branch and update `branch:` in the CAM manifest).
2. Confirm the version is `2.0.0` in `main.lua`, README and this notes file.
3. Run the in-game smoke test: settings, type switches, icon search, language
   switch, target overlay with TTP, Effective CDs, Record.
4. Tag `v2.0.0` and create the GitHub release with these notes.
5. Sync the `Adfazer/addons` fork with upstream and update
   `c/CooldawnBuffTracker.yaml` (remove `dependencies`, update tags/keywords,
   confirm `branch: main`); open the catalog PR.
6. Verify the CAM listing: README rendering, screenshots and install/update.

## Diff map

- New foundation: `locale.lua`, `util/cbt_window.lua`, `util/cbt_log.lua`,
  `util/cbt_icon.lua`, `icon_search_window.lua`, `record_window.lua`,
  `effective_cd.lua`, `skill_dump.tbl`, `skill_icons/manifest.tsv`.
- Reworked: `main.lua`, `settings_page.lua`, `default_settings.lua`,
  `helpers.lua`, `buff_helper.lua`, `buffs_to_track.lua`, `preset_window.lua`,
  `util/import_export.lua`, `util/pixel_viewer.lua`.
- Removed: `buff_search_window.lua`, `canvas_factory.lua`,
  `util/check_button.lua`, `CooldawnBuffTracker.yaml`.
- Added tests: `tests/ui_tooltips_harness.py`, `tests/locale_harness.py`,
  `tests/skill_icons_harness.py`, `tests/eff_cd_harness.py`,
  `tests/ttp_anchor_harness.py`.
