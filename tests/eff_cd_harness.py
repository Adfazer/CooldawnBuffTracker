#!/usr/bin/env python3
"""Offline harness for the Effective CD feature (CooldawnBuffTracker 1.28.0).

Runs the real addon inside the aac_smoke patch-293 sandbox, patches a scratch
copy of main.lua with a test hook (locals are reachable only inside the chunk)
and executes a Lua test phase between OnLoad and the update ticks.

Usage:
    /home/hermes/work/.venv-aac/bin/python tests/eff_cd_harness.py
Exit code 0 = all checks passed.
"""
import os
import shutil
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON_ID = "CooldawnBuffTracker"
SKILL_SCRIPTS = os.environ.get(
    "AAC_SKILL_SCRIPTS",
    "/home/hermes/.hermes/skills/software-development/aac-addon-dev/scripts",
)
SCRATCH_ROOT = os.environ.get(
    "CBT_TEST_SCRATCH", "/home/hermes/.hermes/cache/scratch/cbt_eff_harness"
)

sys.path.insert(0, SKILL_SCRIPTS)
import aac_smoke  # noqa: E402


TEST_HOOK = r"""
CooldawnBuffTracker.__test = {
  eff = EffectiveCD,
  setSettings = function(value) settings = value end,
  refreshLists = function()
    if settingsPage and settingsPage.refreshAllLists then settingsPage.refreshAllLists() end
  end,
  applyEffective = function(cb, snapshot, now, targetId)
    return applyEffectiveCD(cb, snapshot, now, targetId)
  end,
  smartState = function(targetId, key) return smartStateFor(targetId, key, false) end,
  checkClass = function(targetId, now) return maybeCheckTargetClass(targetId, now) end,
  processResets = function(snapshot, now, records, targetId)
    return processTargetResets(snapshot, now, records, targetId)
  end,
  cleanupCache = function(now) return cleanupTargetCache(now) end,
  clearCache = function() targetCache = {} end,
  targetCache = function() return targetCache end,
  targetBuffData = function() return targetBuffData end,
  playerBuffData = function() return playerBuffData end,
  checkUnit = function(unitType) return checkBuffs(unitType) end,
  triggerCooldown = function(sourceId, buffId, startedAt, now)
    return triggerTargetCooldown(sourceId, buffId, startedAt, now)
  end,
}
"""


TEST_LUA = r"""
HOST.tests = function()
  local hook = ADDON_TBL and ADDON_TBL.__test
  if not hook then error("test hook missing: main.lua was not patched", 0) end
  local eff = hook.eff
  local checks, failures = 0, {}
  local function check(condition, name)
    checks = checks + 1
    if not condition then failures[#failures + 1] = name end
  end
  local function near(a, b)
    local x, y = tonumber(a) or 0, tonumber(b) or 0
    return math.abs(x - y) < 0.02
  end
  local function isEmpty(tbl)
    if type(tbl) ~= "table" then return true end
    for _ in pairs(tbl) do return false end
    return true
  end

  ---------------------------------------------------------------------------
  -- 1. formula: flat first, additive percents, conditions, stacks
  ---------------------------------------------------------------------------
  local formula = {
    id = "formula", kind = "buff", cooldown = 60, effectiveCDs = true, smartPct = 0,
    cdMods = {
      { id = 7657, name = "Occultism", kind = "flat", value = 12, condition = "target" },
      { id = 9000610, name = "Passive", kind = "percent", value = 10, condition = "always" },
      { id = 7651, name = "Battle Focus", kind = "percent", value = 20, condition = "target" },
    },
  }
  local snapshot = { ["7657"] = { stack = 1 }, ["7651"] = { stack = 1 } }
  local result = eff.evaluate(formula, snapshot, {})
  check(near(result.flat, 12), "formula: flat seconds")
  check(near(result.pct, 30), "formula: percentages are additive")
  check(near(result.effective, 33.6), "formula: flat first, then percents")
  check(near(result.potential, 33.6), "formula: potential with all modifiers")

  local withoutAura = eff.evaluate(formula, {}, {})
  check(near(withoutAura.flat, 0), "conditional: absent aura gives no flat")
  check(near(withoutAura.pct, 10), "conditional: always percent stays")
  check(near(withoutAura.effective, 54), "conditional: inactive modifier skipped")
  check(near(withoutAura.potential, 33.6), "conditional: potential keeps inactive modifiers")

  local stacked = {
    id = "stacked", kind = "buff", cooldown = 100, effectiveCDs = true,
    cdMods = {
      { id = 1, kind = "flat", value = 5, condition = "target" },
      { id = 2, kind = "percent", value = 10, condition = "target" },
    },
  }
  local withStacks = eff.evaluate(stacked, { ["1"] = { stack = 2 }, ["2"] = { stack = 3 } }, {})
  check(near(withStacks.flat, 10), "stacks: flat value x stacks")
  check(near(withStacks.pct, 30), "stacks: percent value x stacks")
  check(near(withStacks.effective, 63), "stacks: effective value")
  local noStack = eff.evaluate(stacked, { ["1"] = {}, ["2"] = {} }, {})
  check(near(noStack.flat, 5) and near(noStack.pct, 10), "stacks: fallback to 1")

  local byName = {
    id = "byname", kind = "buff", cooldown = 20, effectiveCDs = true,
    cdMods = { { name = "Battle Focus", kind = "flat", value = 5, condition = "target" } },
  }
  check(near(eff.evaluate(byName, { ["15003"] = { name = "Battle Focus" } }, {}).flat, 5),
    "match: exact aura name")
  check(near(eff.evaluate(byName, { ["15003"] = { name = "battle focus" } }, {}).flat, 0),
    "match: case-exact, no folding")

  local unconditional = {
    id = "uncond", kind = "skill", cooldown = 40, effectiveCDs = true,
    cdMods = {
      { kind = "flat", value = 10, condition = "always" },
      { kind = "percent", value = 25, condition = "always" },
      { id = 99, kind = "percent", value = 50, condition = "target" },
    },
  }
  check(near(eff.evaluate(unconditional, {}, {}).effective, 22.5),
    "unconditional: works with no target")

  ---------------------------------------------------------------------------
  -- 2. reset modifiers have no numeric effect
  ---------------------------------------------------------------------------
  local resetEntry = {
    id = "reset", kind = "skill", cooldown = 30, effectiveCDs = true, smartPct = 20,
    cdMods = { { id = 2611, name = "Deflect and Retaliate", kind = "reset", condition = "target" } },
  }
  local resetSnapshot = { ["2611"] = { stack = 1 } }
  local resetEval = eff.evaluate(resetEntry, resetSnapshot, {})
  check(near(resetEval.flat, 0) and near(resetEval.pct, 0) and near(resetEval.effective, 30),
    "reset: no numeric effect on the formula")

  ---------------------------------------------------------------------------
  -- 3. smart learning: per target, 5% threshold, pause, class change, cache
  ---------------------------------------------------------------------------
  local store = api.GetSettings("CooldawnBuffTracker")
  local smartEntry = {
    id = "smart", kind = "skill", cooldown = 60, effectiveCDs = true,
    smartPct = 10, cdMods = {},
  }
  store.customBuffs = { smartEntry }
  hook.setSettings(store)
  hook.clearCache()

  local first = hook.applyEffective(smartEntry, {}, 100, "T1")
  check(near(first, 60), "smart: first application keeps base CD")
  check(hook.smartState("T1", "smart") ~= nil, "smart: state created per target")
  check(hook.smartState("T1", "smart").learned == false, "smart: not learned yet")
  local second = hook.applyEffective(smartEntry, {}, 150, "T1")
  check(hook.smartState("T1", "smart").learned == true, "smart: learned when applied >5% early")
  check(near(second, 54), "smart: learned percentage applies immediately")
  check(hook.smartState("T2", "smart") == nil, "smart: other target untouched")

  local edge = { id = "edge", kind = "skill", cooldown = 100, effectiveCDs = true, smartPct = 10, cdMods = {} }
  store.customBuffs = { edge }
  hook.setSettings(store)
  hook.clearCache()
  hook.applyEffective(edge, {}, 1000, "E1")
  hook.applyEffective(edge, {}, 1095, "E1")
  check(hook.smartState("E1", "edge").learned == false, "smart: exactly 95% is not early")
  hook.applyEffective(edge, {}, 1180, "E1")
  check(hook.smartState("E1", "edge").learned == true, "smart: later short interval learns")

  local zero = { id = "zero", kind = "skill", cooldown = 60, effectiveCDs = true, smartPct = 0, cdMods = {} }
  store.customBuffs = { zero }
  hook.setSettings(store)
  hook.clearCache()
  hook.applyEffective(zero, {}, 10, "Z1")
  hook.applyEffective(zero, {}, 11, "Z1")
  check(hook.smartState("Z1", "zero").learned == false, "smart: 0% never learns")

  local combo = {
    id = "combo", kind = "buff", cooldown = 60, effectiveCDs = true, smartPct = 5,
    cdMods = { { id = 1, kind = "percent", value = 10, condition = "always" } },
  }
  local comboEval = eff.evaluate(combo, {}, { learned = true, smartPct = 5 })
  check(near(comboEval.pct, 15), "smart: additive with configured percents")
  check(near(comboEval.effective, 51), "smart: effective with learned smart")
  check(#comboEval.pctList == 2, "smart: listed as one of the percent sources")

  local classEntry = { id = "classy", kind = "buff", cooldown = 60, effectiveCDs = true, smartPct = 10, cdMods = {} }
  store.customBuffs = { classEntry }
  hook.setSettings(store)
  hook.clearCache()
  local classValue = "Argent"
  api.Ability.GetUnitClassName = function() return classValue end
  hook.applyEffective(classEntry, {}, 1000, "C1")
  hook.applyEffective(classEntry, {}, 1040, "C1")
  hook.applyEffective(classEntry, {}, 2000, "C2")
  hook.applyEffective(classEntry, {}, 2040, "C2")
  check(hook.smartState("C1", "classy").learned and hook.smartState("C2", "classy").learned,
    "class: both targets learned")
  hook.checkClass("C1", 3000)
  hook.checkClass("C1", 4005)
  check(hook.smartState("C1", "classy").learned == true, "class: same class keeps smart")
  classValue = "Blade Dancer"
  hook.checkClass("C1", 5010)
  check(hook.smartState("C1", "classy") == nil, "class: change clears that target's smart")
  check(hook.smartState("C2", "classy") and hook.smartState("C2", "classy").learned == true,
    "class: other target keeps its smart (no global reset)")
  classValue = "Pending"
  hook.checkClass("C2", 6015)
  check(hook.smartState("C2", "classy").learned == true, "class: Pending never clears")
  classValue = "Argent"
  hook.checkClass("C2", 7020)
  check(hook.smartState("C2", "classy").learned == true, "class: back to the same class keeps")

  hook.applyEffective(classEntry, {}, 8000, "K1")
  local caches = hook.targetCache()
  check(caches["K1"] ~= nil, "cache: state stored on the target id")
  caches["K1"].lastSeen = 0
  store.target.cacheTimeout = 300
  hook.cleanupCache(100000)
  check(hook.smartState("K1", "classy") == nil, "cache: cleanup drops the smart state")

  ---------------------------------------------------------------------------
  -- 4. reset modifier: timer zeroed, smart paused, interval not evidence
  ---------------------------------------------------------------------------
  store.customBuffs = { resetEntry }
  hook.setSettings(store)
  hook.clearCache()
  local record = {
    fixedTime = 100, activeUntil = 110, readyAt = 130, status = "active",
    cooldown = 30, timeOfAction = 10, effCD = 30,
  }
  local records = { ["reset"] = record }
  hook.processResets(resetSnapshot, 105, records, "R1")
  check(near(record.readyAt, 130), "reset: first sight seeds without firing")
  hook.processResets({}, 106, records, "R1")
  hook.processResets(resetSnapshot, 107, records, "R1")
  check(near(record.readyAt, 107), "reset: appearance zeroes readyAt")
  check(record.status == "ready", "reset: entry becomes ready")
  check(hook.smartState("R1", "reset").paused == true, "reset: smart paused")

  hook.applyEffective(resetEntry, {}, 200, "R2")
  local record2 = {
    fixedTime = 200, activeUntil = 210, readyAt = 230, status = "active",
    cooldown = 30, timeOfAction = 10,
  }
  local records2 = { ["reset"] = record2 }
  hook.processResets(resetSnapshot, 205, records2, "R2")
  hook.processResets({}, 206, records2, "R2")
  hook.processResets(resetSnapshot, 210, records2, "R2")
  check(hook.smartState("R2", "reset").paused == true, "reset: pause before the next application")
  hook.applyEffective(resetEntry, {}, 211, "R2")
  check(hook.smartState("R2", "reset").paused == false, "reset: next application clears the pause")
  check(hook.smartState("R2", "reset").learned == false, "reset: interval is not learning evidence")

  ---------------------------------------------------------------------------
  -- 5. Edit dialog: section renders, controls work, Save persists the model
  ---------------------------------------------------------------------------
  store.customBuffs = {
    { id = "uibuff", name = "UI Buff", kind = "buff", cooldown = 60, timeOfAction = 10,
      iconFile = "game/ui/icon/icon_buff_debuff.dds", effectiveCDs = true, smartPct = 5,
      cdMods = { { id = 7657, name = "Occultism", kind = "flat", value = 12, condition = "target" } } },
  }
  hook.setSettings(store)
  hook.refreshLists()

  local function newest(id)
    for i = #ENGINE.widgets, 1, -1 do
      local widget = ENGINE.widgets[i]
      if widget and widget._id == id then return widget end
    end
    return nil
  end
  local function click(widget)
    if widget and widget._handlers and widget._handlers["OnClick"] then
      widget._handlers["OnClick"](widget)
    end
  end

  local editButton = newest("editCustomBuffButton_1")
  check(editButton ~= nil, "ui: custom entry edit button exists")
  click(editButton)

  local dialog = newest("cbtCddWindow")
  check(dialog ~= nil and dialog:IsVisible(), "ui: edit dialog opens")
  local effCheckBox = newest("cbtCddEffCheck")
  check(effCheckBox ~= nil and effCheckBox:IsVisible(), "ui: effective checkbox visible")
  check(effCheckBox:GetChecked() == true, "ui: checkbox reflects the stored entry")
  check(newest("cbtCddEffRow1") ~= nil and newest("cbtCddEffRow1"):IsVisible(),
    "ui: modifier row rendered")
  check(newest("cbtCddRefBase") ~= nil, "ui: reference card exists")
  check(newest("cbtCddEffNote") ~= nil and newest("cbtCddEffNote"):IsVisible(),
    "ui: target-only note visible")

  effCheckBox:SetChecked(false)
  if effCheckBox._handlers["OnCheckChanged"] then
    effCheckBox._handlers["OnCheckChanged"](effCheckBox)
  end
  check(newest("cbtCddEffRow1"):IsVisible() == false, "ui: unchecking hides modifiers")
  effCheckBox:SetChecked(true)
  if effCheckBox._handlers["OnCheckChanged"] then
    effCheckBox._handlers["OnCheckChanged"](effCheckBox)
  end
  check(newest("cbtCddEffRow1"):IsVisible() == true, "ui: checking shows modifiers")

  local sourceEdit = newest("cbtCddEffSource")
  local addSourceButton = newest("cbtCddEffAdd")
  sourceEdit:SetText("15003")
  click(addSourceButton)
  check(newest("cbtCddEffRow2") ~= nil and newest("cbtCddEffRow2"):IsVisible(),
    "ui: Add creates a second modifier")

  local typeButton = newest("cbtCddEffType2")
  click(typeButton)
  check(typeButton.textLabel:GetText() == "Percent", "ui: type cycles Flat -> Percent")
  local conditionButton = newest("cbtCddEffCond2")
  click(conditionButton)
  check(conditionButton.textLabel:GetText() == "Always", "ui: condition toggles to Always")
  local valueEdit = newest("cbtCddEffValue2")
  valueEdit:SetText("25")
  if valueEdit._handlers["OnEnterPressed"] then
    valueEdit._handlers["OnEnterPressed"](valueEdit)
  end

  click(newest("cbtCddSave"))
  local savedEntry = store.customBuffs[1]
  check(savedEntry.effectiveCDs == true, "ui: save keeps effectiveCDs")
  check(near(savedEntry.smartPct, 5), "ui: save keeps smart percent")
  check(#savedEntry.cdMods == 2, "ui: save persists both modifiers")
  check(savedEntry.cdMods[2].kind == "percent" and savedEntry.cdMods[2].condition == "always"
    and near(savedEntry.cdMods[2].value, 25), "ui: save persists type/condition/value")
  check(dialog:IsVisible() == false, "ui: save closes the dialog")

  ---------------------------------------------------------------------------
  -- 6. runtime wiring: the target aura applies eff, the player ignores it
  ---------------------------------------------------------------------------
  BUFFS.target = {
    { buff_id = 21001, name = "Bleeding", stack = 2, timeLeft = 12000, timeUnit = 1, isBuff = false },
    { buff_id = 15003, name = "Battle Focus", stack = 1, timeLeft = 9000, timeUnit = 1, isBuff = true },
  }
  local runtimeEntry = {
    id = "21001", name = "Bleeding", kind = "buff", cooldown = 60, timeOfAction = 12,
    effectiveCDs = true, smartPct = 0,
    cdMods = { { id = 15003, name = "Battle Focus", kind = "flat", value = 20, condition = "target" } },
  }
  local playerEntry = {
    id = "15001", name = "Inspiring Roar", kind = "buff", cooldown = 60, timeOfAction = 24,
    effectiveCDs = true, smartPct = 0,
    cdMods = { { id = 15003, name = "Battle Focus", kind = "flat", value = 20, condition = "target" } },
  }
  store.customBuffs = { runtimeEntry, playerEntry }
  store.target.trackedBuffs = { "21001" }
  store.player.trackedBuffs = { "15001" }
  store.target.canvasOf = {}
  store.player.canvasOf = {}
  hook.setSettings(store)
  hook.checkUnit("target")
  local targetRecord = hook.targetBuffData()["21001"]
  check(targetRecord ~= nil, "runtime: target entry created")
  check(near(targetRecord.cooldown, 60), "runtime: configured base kept for display")
  check(near(targetRecord.effCD, 40), "runtime: effective CD computed from the target aura")
  check(near(targetRecord.readyAt - targetRecord.fixedTime, 40),
    "runtime: readyAt uses the effective CD")

  hook.checkUnit("player")
  local playerRecord = hook.playerBuffData()["15001"]
  check(playerRecord ~= nil, "runtime: player entry created")
  check(near(playerRecord.readyAt - playerRecord.fixedTime, 60),
    "runtime: player ignores effective CDs")

  local skillEntry = {
    id = "skill1", name = "Test Skill", kind = "skill", spellName = "Test Skill",
    cooldown = 100, timeOfAction = 0, effectiveCDs = true, smartPct = 0,
    cdMods = { { kind = "flat", value = 30, condition = "always" } },
  }
  store.customBuffs = { skillEntry }
  hook.setSettings(store)
  hook.triggerCooldown("2002a", "skill1", 10, 10)
  local skillRecord = hook.targetCache()["2002a"]
    and hook.targetCache()["2002a"].buffStates["skill1"] or nil
  check(skillRecord ~= nil, "runtime: skill cast recorded for the target")
  check(near(skillRecord.effCD, 70), "runtime: skill uses the effective CD")
  check(near(skillRecord.readyAt - skillRecord.fixedTime, 70),
    "runtime: skill readyAt uses the effective CD")
  check(near(skillRecord.cooldown, 100), "runtime: skill keeps the configured base CD")

  if #failures > 0 then
    error("EFF-CD TESTS FAILED (" .. tostring(#failures) .. "/" .. tostring(checks) .. "): "
      .. table.concat(failures, " | "), 0)
  end
  RESULT.notes[#RESULT.notes + 1] = "eff-cd harness: " .. tostring(checks) .. " checks passed"
end
"""


def copy_addon(dest):
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    for name in os.listdir(REPO):
        src = os.path.join(REPO, name)
        if name in (".git", "docs", "tests", "__pycache__"):
            continue
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(dest, name))
        elif name.endswith((".lua", ".tbl", ".yaml", ".txt", ".md")):
            shutil.copy2(src, os.path.join(dest, name))


def patch_main(addon_dir):
    path = os.path.join(addon_dir, "main.lua")
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    marker = "\nreturn CooldawnBuffTracker"
    index = text.rfind(marker)
    if index < 0:
        raise SystemExit("main.lua: final return not found")
    patched = text[:index] + "\n" + TEST_HOOK + text[index:]
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(patched)


def build_host(lua_module):
    host_lua = lua_module.HOST_LUA
    phases = '    { "update", phaseTicks },'
    if phases not in host_lua:
        raise SystemExit("aac_smoke HOST_LUA layout changed: update phase not found")
    host_lua = host_lua.replace(
        phases,
        '    { "tests", function() if HOST.tests then HOST.tests() end end },\n' + phases,
        1,
    )
    head, sep, tail = host_lua.rpartition("return HOST")
    if not sep:
        raise SystemExit("aac_smoke HOST_LUA layout changed: return HOST not found")
    return head + TEST_LUA + "\nreturn HOST" + tail


def main():
    os.makedirs(SCRATCH_ROOT, exist_ok=True)
    addon_dir = os.path.join(SCRATCH_ROOT, ADDON_ID)
    copy_addon(addon_dir)
    patch_main(addon_dir)

    LuaRuntime = aac_smoke.load_lua51()
    if LuaRuntime is None:
        print("lupa (Lua 5.1) is not importable; use the .venv-aac interpreter", file=sys.stderr)
        return 2
    lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
    host_source = build_host(aac_smoke)
    host = lua.execute(host_source.encode("utf-8"), name="@cbt_eff_host.lua")

    result = aac_smoke.run_smoke(
        lua, host, addon_dir, ADDON_ID, SCRATCH_ROOT, [], 12
    )
    notes = result.get("notes") or []
    for note in notes:
        print("note:", note)
    if result.get("ok"):
        print("RESULT: PASS — %s (phases %s/%s, warnings %s)" % (
            result.get("message") or "ok",
            result.get("phases_run"), result.get("phase_count"),
            len(result.get("warnings") or []),
        ))
        return 0
    print("RESULT: FAIL — phase=%s" % (result.get("phase") or "?"))
    print("message:", result.get("message"))
    if result.get("traceback"):
        print(result["traceback"])
    return 1


if __name__ == "__main__":
    sys.exit(main())
