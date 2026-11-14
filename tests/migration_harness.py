#!/usr/bin/env python3
"""Migration checks for 1.5.0 -> 2.0.0 settings/presets.

Loads the real `default_settings.lua` in a Lua 5.1 sandbox and migrates a
1.5.0-shaped settings table:

- flat unit layout -> canvases[1] named "Main" (first canvas only);
- every old custom entry (no `kind`) -> `kind = "buff"`;
- old `spellName` triggers are preserved; explicit newer kinds stay intact;
- tracked lists stay on the unit and therefore land on canvas 1;
- old flat presets normalize through the same `normalizeUnit`.
"""
import os
import sys

from lupa import lua51

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DS = os.path.join(REPO, "default_settings.lua")


def main():
    source = open(DS, "rb").read().decode("utf-8")
    lua = lua51.LuaRuntime()
    loader = lua.eval(
        'function(s) local f=loadstring or load; local fn,err=f(s); '
        'if not fn then return nil,err end; local ok,v=pcall(fn); '
        'if not ok then return nil,v end; return v end'
    )
    default = loader(source)
    if isinstance(default, tuple):
        default = default[0]
    if default is None:
        raise SystemExit("default_settings.lua did not return a table")

    settings = lua.eval(
        r"""
        {
          enabled = true,
          playerpet = {
            posX = 11, posY = 22, iconSize = 33, iconSpacing = 7,
            showLabel = true, trackedBuffs = { 800004, "OldSkill" },
          },
          player = {
            posX = 44, posY = 55, iconSize = 44,
            trackedBuffs = {},
          },
          target = {
            posX = 66, posY = 77, trackedBuffs = {},
            overlay = true, avoidTTP = false, ttpGap = 9,
          },
          customBuffs = {
            { id = 800004, name = "Old Buff", cooldown = 30, timeOfAction = 3,
              spellName = "Old Spell Trigger" },
            { id = 800005, name = "Old Mana", cooldown = 20, timeOfAction = 0,
              manaCost = 42, mountName = "Horse" },
            { id = 800006, name = "Modern Skill", cooldown = 12,
              kind = "skill", spellName = "NewSkill" },
          },
          presets = {
            old = {
              name = "old",
              playerpet = { posX = 111, posY = 122, iconSize = 28,
                            trackedBuffs = { 800004 } },
            },
          },
        }
        """
    )
    migrated = default.migrate(settings)

    failures = []

    def check(cond, msg):
        if not cond:
            failures.append(msg)

    pet = migrated.playerpet
    check(pet.canvases is not None and len(pet.canvases) == 1,
          "playerpet has one canvas")
    canvas = pet.canvases[1]
    check(canvas.name == "Main", "first canvas is named Main")
    check(canvas.posX == 11 and canvas.posY == 22 and canvas.iconSize == 33,
          "flat position/size moved into the first canvas")
    check(pet.posX is None and pet.posY is None and pet.iconSize is None,
          "flat layout fields removed")
    check(pet.canvasOf is not None and pet.selectedCanvas == 1,
          "unit has canvasOf and selectedCanvas=1")
    check(pet.trackedBuffs is not None and len(pet.trackedBuffs) == 2,
          "tracked list preserved")
    check(migrated.target.overlay is True and migrated.target.avoidTTP is False
          and migrated.target.ttpGap == 9,
          "target display switches preserved")

    cb = migrated.customBuffs
    check(cb[1].kind == "buff", "legacy entry becomes buff/debuff")
    check(cb[1].spellName == "Old Spell Trigger",
          "legacy combat-log trigger is preserved")
    check(cb[1].effectiveCDs is False and cb[1].cdMods is not None,
          "legacy entry gets safe effective-CD defaults")
    check(cb[2].kind == "buff", "legacy mana-shaped entry also becomes buff")
    check(cb[3].kind == "skill", "explicit modern kind is not rewritten")

    preset = migrated.presets.old
    default.normalizeUnit(preset.playerpet, "playerpet")
    pcan = preset.playerpet.canvases[1]
    check(pcan.name == "Main" and pcan.posX == 111 and pcan.posY == 122,
          "old flat preset normalizes to its first canvas")
    check(preset.playerpet.selectedCanvas == 1,
          "old preset gets selectedCanvas=1")

    check(migrated.language == "en", "old config gets English language")

    if failures:
        print("FAIL: %d migration check(s)" % len(failures))
        for f in failures:
            print("  FAIL:", f)
        return 1
    print("RESULT: PASS — 1.5.0 settings/presets migrate to buff entries on canvas 1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
