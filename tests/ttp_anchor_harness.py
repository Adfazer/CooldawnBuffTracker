#!/usr/bin/env python3
"""Offline harness for the 1.31.0 TrackThatPlease anchoring pass
(CooldawnBuffTracker).

Three things are verified inside the aac_smoke patch-293 sandbox:

1. TTP canvas FOUND — a mocked ``targetBuffCanvas`` widget is returned by
   ``api.Interface:FindWidget`` (and, in a second pass, only by ``GetWindow``
   after FindWidget returns a non-widget). The overlay window must be anchored
   ``BOTTOM -> TOPLEFT`` of that widget with ``0, -gap``, anchored exactly once
   (no per-frame re-anchor), and re-anchored when the gap changes.
2. TTP canvas NOT FOUND — all three lookups fail, the debug line
   "TTP canvas not found, fallback" is printed once, and the overlay falls back
   to the computed position (target projection + targetBuffVerticalOffset /
   targetIconSize) without per-frame churn.
3. Overlay / Hide target canvas matrix — the four combinations of
   ``target.overlay`` and ``target.hideCanvas``: the floating target canvas is
   visible exactly when ``hideCanvas`` is false, and the overlay keeps drawing
   with ``hideCanvas`` on.

It also records the layer / z-order / click-through calls made on every
``CreateEmptyWindow`` window, so the overlay is proven to sit on ``normal`` with
z-order 1000 (above TrackThatPlease) while the addon windows are lifted to 1100
above the overlay.

Usage:
    /home/hermes/work/.venv-aac/bin/python tests/ttp_anchor_harness.py
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
    "CBT_TEST_SCRATCH", "/home/hermes/.hermes/cache/scratch/cbt_ttp_anchor_harness"
)

sys.path.insert(0, SKILL_SCRIPTS)
import aac_smoke  # noqa: E402


TEST_HOOK = r"""
-- test-only state, reachable only from the scratch copy
local function seedTargetForTest(id, buffId, record)
  currentTargetId = id
  lastDisplayedTargetId = id
  lastTargetLostTime = nil
  targetBuffData[buffId] = record
  targetActiveBuffs[id] = targetActiveBuffs[id] or {}
  targetActiveBuffs[id][buffId] = true
end

CooldawnBuffTracker.__test = {
  settingsPage = settingsPage,
  logs = CbtLog,
  cbtWindow = require("CooldawnBuffTracker/util/cbt_window"),
  cache = function() return frameCache end,
  overlays = function() return frameOverlays end,
  canvases = function() return unitCanvases end,
  refreshFrameCache = refreshFrameCache,
  updateTargetOverlayPositions = updateTargetOverlayPositions,
  updateBuffIcons = updateBuffIcons,
  ensureFrameOverlay = ensureFrameOverlay,
  ensureUnitCanvases = ensureUnitCanvases,
  destroyFrameModes = destroyFrameModes,
  seedTarget = seedTargetForTest,
  overlayAnchor = OverlayAnchor,
  ttpRow = TTPRow,
}
"""


TEST_LUA = r"""
HOST.tests = function()
  local hook = ADDON_TBL and ADDON_TBL.__test
  if not hook then error("test hook missing: main.lua was not patched", 0) end

  local checks, failures = 0, {}
  local function check(condition, name)
    checks = checks + 1
    if not condition then failures[#failures + 1] = name end
  end

  local settings = api.GetSettings("CooldawnBuffTracker")
  settings.target.overlay = true
  settings.target.hideCanvas = false
  settings.target.avoidTTP = true
  settings.target.ttpGap = 9

  ---------------------------------------------------------------------------
  -- chat capture (CbtLog -> api.Log)
  ---------------------------------------------------------------------------
  local logs = {}
  local origInfo, origErr = api.Log.Info, api.Log.Err
  api.Log.Info = function(_, line) logs[#logs + 1] = tostring(line) end
  api.Log.Err = function(_, line) logs[#logs + 1] = tostring(line) end
  local function logHas(needle)
    for _, line in ipairs(logs) do
      if string.find(line, needle, 1, true) then return true end
    end
    return false
  end

  ---------------------------------------------------------------------------
  -- api stubs: a live target, a screen position, and a widget recorder
  ---------------------------------------------------------------------------
  local origUnitId, origScreenPos = api.Unit.GetUnitId, api.Unit.GetUnitScreenPosition
  local origFind, origGetWindow, origGetByName =
    api.Interface.FindWidget, api.Interface.GetWindow, api.Interface.GetWidgetByName
  api.Unit.GetUnitId = function(_, unit) return "1dafb" end
  api.Unit.GetUnitScreenPosition = function(_, unit) return 500, 400, 10 end

  local windows = {}   -- [id] = { layers, zorders, clickable, pick, raises }
  local realCreate = api.Interface.CreateEmptyWindow
  api.Interface.CreateEmptyWindow = function(self, id)
    local w = realCreate(self, id)
    if not w then return w end
    local rec = { layers = {}, zorders = {}, raises = 0 }
    windows[tostring(id)] = rec
    local realLayer, realZ, realClick, realPick, realRaise =
      w.SetUILayer, w.SetZOrder, w.Clickable, w.EnablePick, w.Raise
    w.SetUILayer = function(me, layer) rec.layers[#rec.layers + 1] = tostring(layer) return realLayer(me, layer) end
    w.SetZOrder = function(me, z) rec.zorders[#rec.zorders + 1] = tonumber(z) return realZ(me, z) end
    w.Clickable = function(me, v) rec.clickable = v return realClick(me, v) end
    w.EnablePick = function(me, v) rec.pick = v return realPick(me, v) end
    w.Raise = function(me) rec.raises = rec.raises + 1 return realRaise(me) end
    return w
  end

  local function valueOf(list, wanted)
    for _, v in ipairs(list or {}) do if v == wanted then return true end end
    return false
  end

  -- fake TrackThatPlease target row: only the methods we validate/use
  local ttpVisible = true
  local ttpWnd = {
    GetExtent = function() return 60, 26 end,
    AddAnchor = function() end,
    IsVisible = function() return ttpVisible end,
  }
  local notAWidget = { SomeOtherApi = function() end }
  local lookups = {}
  local function installLookup(mode)
    api.Interface.FindWidget = function(_, name)
      lookups[#lookups + 1] = "FindWidget:" .. tostring(name)
      if mode == "find" then return ttpWnd end
      if mode == "second" then return notAWidget end
      return nil
    end
    api.Interface.GetWindow = function(_, name)
      lookups[#lookups + 1] = "GetWindow:" .. tostring(name)
      if mode == "second" then return ttpWnd end
      return nil
    end
    api.Interface.GetWidgetByName = function(_, name)
      lookups[#lookups + 1] = "GetWidgetByName:" .. tostring(name)
      return nil
    end
  end

  hook.logs.setDebug(true)

  ---------------------------------------------------------------------------
  -- 1. TTP canvas FOUND -> BOTTOM/TOPLEFT, -gap, anchored once
  ---------------------------------------------------------------------------
  installLookup("find")
  hook.destroyFrameModes()
  local cache = hook.refreshFrameCache("target", 1000000)
  check(cache.ttpCanvas == ttpWnd, "found: ttpCanvas cached from FindWidget")
  check(logHas("TTP canvas found"), "found: debug line 'TTP canvas found'")
  check(#lookups >= 1, "found: lookup attempted")

  cache.visible = true
  cache.screenX, cache.screenY, cache.z = 500, 400, 10
  cache.ttpOffset, cache.ttpSize = 40, 26

  local holder = hook.ensureFrameOverlay(1)
  check(holder ~= nil and holder.wnd ~= nil, "found: overlay window created")
  holder.shown = true

  -- layer / z-order / click-through of the overlay window
  local rec = windows["CBTFrameOverlay_1"]
  check(rec ~= nil, "overlay window recorded")
  if rec then
    check(valueOf(rec.layers, "normal"), "overlay window on layer normal (" ..
      table.concat(rec.layers, ",") .. ")")
    check(not valueOf(rec.layers, "game"), "overlay window not on layer game")
    check(valueOf(rec.zorders, 1000), "overlay window z-order 1000")
    check(rec.clickable == false, "overlay window click-through (Clickable(false))")
    check(rec.pick == false, "overlay window EnablePick(false)")
  end

  local anchorLog = {}
  local realAdd, realRemove = holder.wnd.AddAnchor, holder.wnd.RemoveAllAnchors
  local removes = 0
  holder.wnd.AddAnchor = function(self, ...) anchorLog[#anchorLog + 1] = {...} return realAdd(self, ...) end
  holder.wnd.RemoveAllAnchors = function(self) removes = removes + 1 return realRemove(self) end

  hook.updateTargetOverlayPositions()
  check(#anchorLog == 1, "found: one anchor call (" .. tostring(#anchorLog) .. ")")
  local a = anchorLog[1] or {}
  check(a[1] == "BOTTOM", "found: my point is BOTTOM")
  check(a[2] == ttpWnd, "found: anchored to the TTP targetBuffCanvas widget")
  check(a[3] == "TOPLEFT", "found: target point is TOPLEFT")
  check(a[4] == 0 and a[5] == -9, "found: offset 0,-ttpGap (" ..
    tostring(a[4]) .. "," .. tostring(a[5]) .. ")")

  for _ = 1, 8 do hook.updateTargetOverlayPositions() end
  check(#anchorLog == 1, "found: no per-frame re-anchor (" .. tostring(#anchorLog) .. ")")
  check(removes == 1, "found: anchors cleared exactly once (" .. tostring(removes) .. ")")

  settings.target.ttpGap = 14
  hook.updateTargetOverlayPositions()
  local b = anchorLog[#anchorLog] or {}
  check(#anchorLog == 2, "gap change: exactly one new anchor call")
  check(b[4] == 0 and b[5] == -14, "gap change: re-anchored with the new gap")
  settings.target.ttpGap = 9
  hook.updateTargetOverlayPositions()   -- back to 9, one more anchor call

  -- a hidden TTP canvas falls back, a visible one anchors again
  ttpVisible = false
  local beforeHidden = #anchorLog
  hook.updateTargetOverlayPositions()
  local hidden = anchorLog[#anchorLog] or {}
  check(#anchorLog == beforeHidden + 1 and hidden[2] == "UIParent",
    "hidden TTP canvas: computed fallback")
  ttpVisible = true
  local beforeShown = #anchorLog
  hook.updateTargetOverlayPositions()
  local shown = anchorLog[#anchorLog] or {}
  check(#anchorLog == beforeShown + 1 and shown[2] == ttpWnd,
    "visible TTP canvas again: re-anchored to it")

  -- Avoid TrackThatPlease OFF -> canvas offsets, even with the widget found
  settings.target.avoidTTP = false
  local beforeOff = #anchorLog
  hook.updateTargetOverlayPositions()
  local off = anchorLog[#anchorLog] or {}
  check(#anchorLog == beforeOff + 1 and off[2] == "UIParent", "avoidTTP off: computed anchor")
  check(off[4] == 500 and off[5] == 370, "avoidTTP off: canvas overlayX/overlayY used")
  settings.target.avoidTTP = true
  hook.updateTargetOverlayPositions()   -- back to the TTP anchor

  ---------------------------------------------------------------------------
  -- 1b. validation: a non-widget from FindWidget falls through to GetWindow
  ---------------------------------------------------------------------------
  installLookup("second")
  hook.destroyFrameModes()
  local cache2 = hook.refreshFrameCache("target", 3000000)
  check(cache2.ttpCanvas == ttpWnd, "second lookup: GetWindow result used")
  check(#lookups >= 2, "second lookup: both lookups attempted")

  ---------------------------------------------------------------------------
  -- 2. TTP canvas NOT FOUND -> computed fallback, no churn
  ---------------------------------------------------------------------------
  installLookup("none")
  hook.destroyFrameModes()
  local cache3 = hook.refreshFrameCache("target", 4000000)
  check(cache3.ttpCanvas == false, "missing: ttpCanvas cached as false")
  check(logHas("TTP canvas not found, fallback"), "missing: fallback debug line")

  cache3.visible = true
  cache3.screenX, cache3.screenY, cache3.z = 500, 400, 10
  cache3.ttpOffset, cache3.ttpSize = 40, 26

  local holder2 = hook.ensureFrameOverlay(1)
  check(holder2 ~= nil and holder2.wnd ~= nil, "missing: overlay window created")
  holder2.shown = true
  local log2 = {}
  local realAdd2 = holder2.wnd.AddAnchor
  holder2.wnd.AddAnchor = function(self, ...) log2[#log2 + 1] = {...} return realAdd2(self, ...) end

  hook.updateTargetOverlayPositions()
  check(#log2 == 1, "missing: one anchor call (" .. tostring(#log2) .. ")")
  local f = log2[1] or {}
  check(f[1] == "BOTTOM" and f[2] == "UIParent" and f[3] == "TOPLEFT",
    "missing: computed anchor on UIParent")
  check(f[4] == 500 and f[5] == 405, "missing: y = screenY + offset - size - gap (" ..
    tostring(f[4]) .. "," .. tostring(f[5]) .. ")")

  for _ = 1, 8 do hook.updateTargetOverlayPositions() end
  check(#log2 == 1, "missing: stationary fallback produces no anchor churn (" ..
    tostring(#log2) .. ")")

  ---------------------------------------------------------------------------
  -- 3. overlay / hideCanvas matrix
  ---------------------------------------------------------------------------
  local buffId = "800004"
  settings.target.trackedBuffs = { buffId }
  settings.target.enabled = true
  hook.ensureUnitCanvases("target")
  hook.seedTarget("1dafb", buffId, {
    name = "Test aura",
    icon = "game/ui/icon/icon_buff_debuff.dds",
    status = "active",
  })
  local canvas = (hook.canvases().target or {})[1]
  check(canvas ~= nil, "matrix: target canvas exists")

  local combos = {
    { false, false, "overlay off / hide off" },
    { true,  false, "overlay on / hide off" },
    { false, true,  "overlay off / hide on" },
    { true,  true,  "overlay on / hide on" },
  }
  for _, combo in ipairs(combos) do
    settings.target.overlay = combo[1]
    settings.target.hideCanvas = combo[2]
    local c = hook.cache().target
    if c then
      c.visible = true
      c.screenX, c.screenY, c.z = 500, 400, 10
      c.ttpOffset, c.ttpSize = 40, 26
      c.at = nil   -- let the next render refresh from the live clock
    end
    pcall(hook.updateBuffIcons, "target")
    local vis = canvas ~= nil and canvas:IsVisible()
    check(vis == (combo[2] == false), "matrix " .. combo[3] ..
      ": floating canvas visible " .. tostring(vis))
  end

  -- with hideCanvas ON the overlay keeps drawing
  settings.target.overlay = true
  settings.target.hideCanvas = true
  local c = hook.cache().target
  if c then
    c.visible = true
    c.screenX, c.screenY, c.z = 500, 400, 10
    c.ttpOffset, c.ttpSize = 40, 26
    c.at = nil
  end
  pcall(hook.updateBuffIcons, "target")
  local oh = hook.overlays()[1]
  check(oh ~= nil and oh.shown == true, "matrix: overlay still drawn with hideCanvas on")

  ---------------------------------------------------------------------------
  -- 4. addon windows stay above the overlay
  ---------------------------------------------------------------------------
  local sp = hook.settingsPage
  check(sp ~= nil, "settingsPage module exported")
  check(hook.cbtWindow ~= nil, "cbt_window module exported")

  -- The settings window is built during OnLoad, before this recorder exists:
  -- wrap it now and run the same helper initSettingsPage calls at creation
  -- (the Python side asserts that call site statically).
  local settingsWnd = nil
  for i = #ENGINE.widgets, 1, -1 do
    local w = ENGINE.widgets[i]
    if tostring(w._id or "") == "CooldawnBuffTrackerSettings" and not w._freed then
      settingsWnd = w
      break
    end
  end
  check(settingsWnd ~= nil, "settings window exists")
  if settingsWnd and hook.cbtWindow then
    local srec = { layers = {}, zorders = {} }
    local rl, rz = settingsWnd.SetUILayer, settingsWnd.SetZOrder
    settingsWnd.SetUILayer = function(me, l) srec.layers[#srec.layers + 1] = tostring(l) return rl(me, l) end
    settingsWnd.SetZOrder = function(me, z) srec.zorders[#srec.zorders + 1] = tonumber(z) return rz(me, z) end
    hook.cbtWindow.KeepAboveOverlay(settingsWnd)
    check(valueOf(srec.layers, "normal"), "settings window on layer normal")
    check(valueOf(srec.zorders, 1100), "settings window z-order 1100 (above the overlay)")
  end

  if hook.cbtWindow then
    local dlg = hook.cbtWindow.Create("cbtTestDialog", "Test dialog", 300, 200, nil)
    local drec = windows["cbtTestDialog"]
    check(dlg ~= nil and drec ~= nil, "cbt_window dialog created")
    if drec then
      check(valueOf(drec.layers, "normal"), "dialog on layer normal")
      check(valueOf(drec.zorders, 1100), "dialog z-order 1100 (above the overlay)")
    end
    if dlg then hook.cbtWindow.Destroy(dlg) end
  end

  hook.logs.setDebug(false)
  api.Log.Info, api.Log.Err = origInfo, origErr
  api.Interface.CreateEmptyWindow = realCreate
  api.Interface.FindWidget, api.Interface.GetWindow, api.Interface.GetWidgetByName =
    origFind, origGetWindow, origGetByName
  api.Unit.GetUnitId, api.Unit.GetUnitScreenPosition = origUnitId, origScreenPos

  HOST.ttpReport = {
    checks = checks,
    failures = failures,
    logs = logs,
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


def static_checks():
    """Source-level assertions the sandbox cannot observe (call sites)."""
    problems = []
    with open(os.path.join(REPO, "settings_page.lua"), "r", encoding="utf-8") as handle:
        page = handle.read()
    if "CbtWindow.KeepAboveOverlay(settingsWindow)" not in page:
        problems.append("settings_page.lua: the settings window is not lifted above the overlay")
    with open(os.path.join(REPO, "main.lua"), "r", encoding="utf-8") as handle:
        main = handle.read()
    if 'SetUILayer("normal")' not in main:
        problems.append("main.lua: the target overlay is not on the normal layer")
    if 'wnd:AddAnchor("BOTTOM", ttpCanvas, "TOPLEFT", 0, -gap)' not in main:
        problems.append("main.lua: the TTP anchor call is missing")
    if "overlayMode or hideFloating" in main:
        problems.append("main.lua: the overlay still hides the floating canvas")
    return problems


def main():
    problems = static_checks()
    if problems:
        for item in problems:
            print("STATIC:", item)
        print("RESULT: FAIL — %d source problem(s)" % len(problems))
        return 1
    os.makedirs(SCRATCH_ROOT, exist_ok=True)
    addon_dir = os.path.join(SCRATCH_ROOT, ADDON_ID)
    copy_addon(addon_dir)
    patch_main(addon_dir)

    LuaRuntime = aac_smoke.load_lua51()
    if LuaRuntime is None:
        print("lupa (Lua 5.1) is not importable; use the .venv-aac interpreter", file=sys.stderr)
        return 2
    lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
    host = lua.execute(build_host(aac_smoke).encode("utf-8"), name="@cbt_ttp_host.lua")

    result = aac_smoke.run_smoke(lua, host, addon_dir, ADDON_ID, SCRATCH_ROOT, [], 12)
    report = host_get(host, "ttpReport")
    if report is None:
        print("RESULT: FAIL — the tests phase did not run")
        print("message:", result.get("message"))
        if result.get("traceback"):
            print(result["traceback"])
        return 1

    failures = list(report["failures"])
    print("checks: %d" % report["checks"])
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
    print("RESULT: PASS — TTP anchor, fallback and overlay/hideCanvas matrix verified")
    return 0


def _text(value):
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return str(value)


def host_get(host, name):
    try:
        table = getattr(host, name)
    except Exception:
        return None
    if table is None:
        return None
    return {
        "checks": int(table.checks),
        "failures": [_text(x) for x in table.failures.values()],
    }


if __name__ == "__main__":
    sys.exit(main())
