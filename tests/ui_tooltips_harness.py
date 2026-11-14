#!/usr/bin/env python3
"""Offline UI harness for the 1.29.0 tooltip pass (CooldawnBuffTracker).

Opens every addon window inside the aac_smoke patch-293 sandbox, clicks the
buttons that create the dialogs (entry editor, icon search, record, presets,
import/export, support window) and hovers every widget of those windows, so the
static and dynamic tooltip closures really run. The scratch copy of
util/cbt_window.lua drops the pcall around the dynamic text function, so an
error inside a tooltip callback is reported instead of silently swallowed.

Usage:
    /home/hermes/work/.venv-aac/bin/python tests/ui_tooltips_harness.py
Exit code 0 = every window opened, every hover callback ran, no tooltip call
per frame.
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
    "CBT_TEST_SCRATCH", "/home/hermes/.hermes/cache/scratch/cbt_ui_harness"
)

sys.path.insert(0, SKILL_SCRIPTS)
import aac_smoke  # noqa: E402


TEST_HOOK = r"""
CooldawnBuffTracker.__test = {
  settingsPage = settingsPage,
}
"""


TEST_LUA = r"""
HOST.tests = function()
  local hook = ADDON_TBL and ADDON_TBL.__test
  if not hook then error("test hook missing: main.lua was not patched", 0) end
  local sp = hook.settingsPage
  if not sp then error("settingsPage module missing", 0) end

  local checks, failures = 0, {}
  local function check(condition, name)
    checks = checks + 1
    if not condition then failures[#failures + 1] = name end
  end

  -- newest widget with this exact id (ids repeat across reload cycles)
  local function byId(id)
    for i = #ENGINE.widgets, 1, -1 do
      local w = ENGINE.widgets[i]
      if tostring(w._id or "") == id and not w._freed then return w end
    end
    return nil
  end
  local function click(id)
    local w = byId(id)
    if w and w._handlers and w._handlers.OnClick then
      w._handlers.OnClick(w)
      return true
    end
    return false
  end

  ---------------------------------------------------------------------------
  -- 1. open every window through the real entry points
  ---------------------------------------------------------------------------
  sp.openSettingsWindow()
  check(byId("CooldawnBuffTrackerSettings") ~= nil, "settings window created")

  -- custom entries so the list rows and the entry editor exist
  local s = api.GetSettings("CooldawnBuffTracker")
  s.customBuffs = {
    { id = 800004, name = "Test Buff", cooldown = 30, timeOfAction = 3, kind = "buff",
      effectiveCDs = true, smartPct = 5,
      cdMods = {
        { id = 800005, name = "Mod A", kind = "flat", value = 5, condition = "always" },
        { name = "Mod B", kind = "percent", value = 10, condition = "target" },
      } },
    { id = "TestSkill", name = "Test Skill", cooldown = 12, kind = "skill", spellName = "TestSkill" },
  }
  -- one tracked entry on the mount canvas so the tracked row (and its dynamic
  -- tooltip) exists
  local mountCfg = s.playerpet
  mountCfg.trackedBuffs = { 800004 }
  mountCfg.canvasOf = { ["800004"] = 1 }
  mountCfg.enabled = true
  sp.refreshAllLists()

  check(click("editCustomBuffButton_1"), "custom row Edit clicked")
  check(byId("cbtCddWindow") ~= nil, "entry editor created")
  check(click("cbtCddIconPreview"), "icon preview clicked")
  check(byId("cbtIconSearch") ~= nil, "icon search window created")
  check(click("recordButton"), "record button clicked")
  check(byId("cbtRecord") ~= nil, "record window created")
  check(click("presetsButton"), "presets button clicked")
  check(byId("CooldawnBuffTrackerPresets") ~= nil, "presets window created")
  check(click("importExportButton"), "import/export button clicked")
  check(byId("CooldawnBuffTrackerImportExport") ~= nil, "import/export window created")
  check(click("pixelViewButton"), "support button clicked")
  check(byId("CooldawnBuffTrackerSupport") ~= nil, "support window created")
  check(click("canvasMenuButton"), "canvas popup opened")
  check(byId("cbtCanvasPopup1") ~= nil, "canvas popup created")
  check(click("canvasRenameButton"), "rename dialog opened")
  check(byId("cbtCanvasRename") ~= nil, "rename dialog created")
  check(click("cbtCanvasRenameCancel"), "rename dialog cancelled")
  -- a second canvas is required before the delete confirmation opens
  check(click("canvasAddButton"), "canvas added")
  check(click("canvasDeleteButton"), "delete dialog opened")
  check(byId("cbtCanvasDelete") ~= nil, "delete dialog created")

  ---------------------------------------------------------------------------
  -- 2. hover every widget of every window: static and dynamic tooltips
  ---------------------------------------------------------------------------
  local seen, errors, calls = {}, {}, 0
  local orig = api.Interface.SetTooltipOnPos
  api.Interface.SetTooltipOnPos = function(_, text, target, x, y)
    calls = calls + 1
    if text ~= nil and text ~= "" and target ~= nil then
      seen[target] = tostring(text)
    end
    return nil
  end

  -- OnEnter/OnLeave are the real installed handlers: the tooltip wrapper is the
  -- outermost one, so calling them runs every static and dynamic tooltip closure.
  -- The mock does not register W_CTRL edits as children, so walk the flat widget
  -- list from the settings window (the first UI of this load cycle) onwards.
  local mark = #ENGINE.widgets
  for i = #ENGINE.widgets, 1, -1 do
    if tostring(ENGINE.widgets[i]._id or "") == "CooldawnBuffTrackerSettings" then
      mark = i
      break
    end
  end
  local hovered = 0
  for i = mark, #ENGINE.widgets do
    local w = ENGINE.widgets[i]
    if not w._freed then
      local handlers = w._handlers or {}
      if handlers.OnEnter then
        hovered = hovered + 1
        local ok, err = pcall(handlers.OnEnter, w)
        if not ok then
          errors[#errors + 1] = tostring(w._id) .. ": " .. tostring(err)
        end
      end
      if handlers.OnLeave then
        local ok, err = pcall(handlers.OnLeave, w)
        if not ok then
          errors[#errors + 1] = tostring(w._id) .. " (leave): " .. tostring(err)
        end
      end
    end
  end
  check(hovered > 100, "hovered widgets with handlers: " .. tostring(hovered))

  local windows = {
    "CooldawnBuffTrackerSettings", "cbtCddWindow", "cbtIconSearch", "cbtRecord",
    "CooldawnBuffTrackerPresets", "CooldawnBuffTrackerImportExport",
    "CooldawnBuffTrackerSupport", "cbtCanvasPopup1", "cbtCanvasRename",
    "cbtCanvasDelete",
  }
  for _, id in ipairs(windows) do
    check(byId(id) ~= nil, "window exists: " .. id)
  end

  -- hover the canvas popup rows too (created before this pass)
  local custom = byId("customBuff_1")
  check(custom ~= nil, "custom row widget exists")

  -- coverage: interactive widgets of this load cycle that produced no tooltip
  local INTERACTIVE = {
    button = true, checkbutton = true, edit = true, x2editbox = true, combobox = true,
  }
  -- only OUR visible widgets: native frames have dotted ids, icon buttons inside
  -- a row and the HUD canvas icons are display elements covered by their row.
  local function skipId(id)
    -- inner icon buttons are covered by their row's tooltip; HUD canvas icons are
    -- display-only; hidden modifier rows legitimately return no text.
    return string.find(id, ".", 1, true) ~= nil
      or string.find(id, "Icon_") ~= nil
      or string.find(id, "Icon%d+$") ~= nil
      or string.find(id, "^buffIcon_") ~= nil
      or string.find(id, "^cbtCddEffType%d+$") ~= nil
      or string.find(id, "^cbtCddEffCond%d+$") ~= nil
      or string.find(id, "^cbtCddEffValue%d+$") ~= nil
  end
  local missing = {}
  for i = mark, #ENGINE.widgets do
    local w = ENGINE.widgets[i]
    local id = tostring(w._id or "")
    if not w._freed and w._visible and INTERACTIVE[w._kind]
        and seen[w] == nil and not skipId(id) then
      missing[#missing + 1] = tostring(w._kind) .. ":" .. id
    end
  end

  ---------------------------------------------------------------------------
  -- 3. sample the actual texts (units/ranges, dynamic values)
  ---------------------------------------------------------------------------
  local function textOf(id)
    local w = byId(id)
    return w and seen[w] or nil
  end
  local function has(id, needle, name)
    local text = textOf(id)
    check(type(text) == "string" and string.find(text, needle, 1, true) ~= nil, name)
  end

  has("iconSize", "16-64", "icon size tooltip states the px range")
  has("posX", "px", "position X tooltip states the unit")
  has("cbtCddCd", "seconds", "cooldown tooltip states seconds")
  has("cbtTtpGap", "px", "gap tooltip states px")
  has("addBuffButton", "canvas", "Add button tooltip mentions the canvas")
  has("cbtCddEffCheck", "target", "Effective CDs checkbox explains target-only")
  has("cbtCddRefEff", "max(0", "reference card shows the formula")
  has("cbtCddEffType1", "Type:", "modifier type button tooltip")
  has("cbtCddEffValue1", "s.", "modifier value tooltip states seconds")
  has("cbtCddEffValue2", "%", "modifier value tooltip states percent")
  has("cbtCddEffCond2", "On target", "modifier condition tooltip")
  -- helper buttons keep their caption in textLabel: the tooltip must read it, not
  -- the emptied native text
  has("canvasMenuButton", "Canvas:", "canvas button tooltip shows the current canvas")
  has("lockButton", "Lock:", "lock button tooltip shows the current state")
  has("debugBuffButton", "Debug:", "debug button tooltip shows the current state")
  has("cbtSettingsHeader", "Drag to move", "settings header drag tooltip")
  has("cbtRecord_header", "Drag to move", "record header drag tooltip")
  has("CooldawnBuffTrackerPresets_header", "Drag to move", "presets header drag tooltip")

  -- dynamic row tooltips carry the current values
  local trackedSeen = false
  for w, text in pairs(seen) do
    local id = tostring(w._id or "")
    if string.find(id, "trackedBuff_", 1, true)
        and string.find(text, "canvas", 1, true) then
      trackedSeen = true
    end
  end
  check(trackedSeen, "tracked row tooltip names the canvas")

  ---------------------------------------------------------------------------
  -- 4. no per-frame tooltip calls: ticks must not add any
  ---------------------------------------------------------------------------
  local before = calls
  for _ = 1, 5 do tick(50) end
  check(calls == before, "no tooltip calls from UPDATE ticks")
  check(calls > 60, "hover produced tooltip calls (" .. tostring(calls) .. ")")

  api.Interface.SetTooltipOnPos = orig

  ---------------------------------------------------------------------------
  -- 5. report
  ---------------------------------------------------------------------------
  local shown = 0
  for _ in pairs(seen) do shown = shown + 1 end
  HOST.uiReport = {
    checks = checks,
    failures = failures,
    errors = errors,
    shown = shown,
    calls = calls,
    missing = missing,
  }
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
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text[:index] + "\n" + TEST_HOOK + text[index:])


def patch_window(addon_dir):
    """Drop the pcall around the dynamic text so callback errors surface."""
    path = os.path.join(addon_dir, "util", "cbt_window.lua")
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    old = """        local ok, text = pcall(textFn, self)
        if ok and type(text) == "string" and text ~= "" then"""
    new = """        local text = textFn(self)
        if type(text) == "string" and text ~= "" then"""
    if old not in text:
        raise SystemExit("cbt_window.lua: dynamic tooltip body changed")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text.replace(old, new, 1))


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
    patch_window(addon_dir)

    LuaRuntime = aac_smoke.load_lua51()
    if LuaRuntime is None:
        print("lupa (Lua 5.1) is not importable; use the .venv-aac interpreter", file=sys.stderr)
        return 2
    lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
    host = lua.execute(build_host(aac_smoke).encode("utf-8"), name="@cbt_ui_host.lua")

    result = aac_smoke.run_smoke(lua, host, addon_dir, ADDON_ID, SCRATCH_ROOT, [], 12)
    report = host_get(host, "uiReport")
    if report is None:
        print("RESULT: FAIL — the UI phase did not run")
        print("message:", result.get("message"))
        if result.get("traceback"):
            print(result["traceback"])
        return 1

    failures = list(report["failures"]) + list(report["errors"])
    if report["missing"]:
        print("interactive widgets without a tooltip (%d):" % len(report["missing"]))
        for item in report["missing"]:
            print("   ", item)
    print("checks: %d, widgets with a tooltip: %d, tooltip calls: %d"
          % (report["checks"], report["shown"], report["calls"]))
    for item in failures:
        print("FAIL:", item)
    if failures:
        print("RESULT: FAIL — %d problem(s)" % len(failures))
        return 1
    if not result.get("ok"):
        print("RESULT: FAIL — smoke phase=%s" % (result.get("phase") or "?"))
        print("message:", result.get("message"))
        if result.get("traceback"):
            print(result["traceback"])
        return 1
    print("RESULT: PASS — every window opened, every hover callback ran, "
          "no tooltip call per frame")
    return 0


def _text(value):
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return str(value)


def host_get(host, name):
    """Read HOST.<name>; lupa exposes Lua tables through attributes here."""
    try:
        table = getattr(host, name)
    except Exception:
        return None
    if table is None:
        return None
    return {
        "checks": int(table.checks),
        "shown": int(table.shown),
        "calls": int(table.calls),
        "failures": [_text(x) for x in table.failures.values()],
        "errors": [_text(x) for x in table.errors.values()],
        "missing": [_text(x) for x in table.missing.values()],
    }


if __name__ == "__main__":
    sys.exit(main())
