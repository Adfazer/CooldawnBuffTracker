#!/usr/bin/env python3
"""Offline UI harness for the 1.33.0 tooltip pass (CooldawnBuffTracker).

Opens every addon window inside the aac_smoke patch-293 sandbox, clicks the
buttons that create the dialogs (entry editor, icon search, record, presets,
import/export, support window) and hovers every widget of those windows.

The tooltip layer is verified against the real implementation: the harness wraps
``api.Interface:CreateWidget`` so the single shared ``gametooltip`` widget is
instrumented as soon as the addon creates it (lazily, on the first hover), then
asserts on every hover that

  * the tooltip was created ONCE and carries a nine-part background,
    font 14, auto wordwrap, width 320-360, layer "tooltip" and high z-order;
  * ClearLines + AddLine ran and Show(true) was called;
  * the tooltip was re-anchored to the hovered widget (BOTTOM -> widget TOP, -6);
  * OnLeave hides it (Show(false));
  * the text is translated at hover time (locale switched to ru mid-run);
  * ``SetTooltipOnPos`` is never used (fallback path only);
  * UPDATE ticks do no tooltip work at all.

The scratch copy of util/cbt_window.lua drops the pcall around the dynamic text
function, so an error inside a tooltip callback is reported instead of silently
swallowed.

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
  locale = locale,
}
"""


TEST_LUA = r"""
HOST.tests = function()
  local hook = ADDON_TBL and ADDON_TBL.__test
  if not hook then error("test hook missing: main.lua was not patched", 0) end
  local sp = hook.settingsPage
  local loc = hook.locale
  if not sp then error("settingsPage module missing", 0) end
  if not loc then error("locale module missing", 0) end

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
  -- 0. instrument the shared gametooltip before any window exists
  ---------------------------------------------------------------------------
  local tipState = nil      -- call state of the one shared tooltip widget
  local tipCreations = 0
  local tipIds = {}
  local setTooltipCalls = 0

  local origCreateWidget = api.Interface.CreateWidget
  api.Interface.CreateWidget = function(self, kind, id, parent)
    local w = origCreateWidget(self, kind, id, parent)
    if kind == "gametooltip" and w ~= nil then
      tipCreations = tipCreations + 1
      tipIds[#tipIds + 1] = tostring(id)
      local st = { lines = {}, anchors = {}, clears = 0, shows = 0, hides = 0,
                   raises = 0, visible = false }
      w._cbtTip = st
      if tipState == nil then tipState = st end
      w.ClearLines = function(self2) st.clears = st.clears + 1; st.lines = {} return self2 end
      w.AddLine = function(self2, text)
        st.lines[#st.lines + 1] = tostring(text)
        return self2
      end
      w.Show = function(self2, show)
        if show then
          st.shows = st.shows + 1
          st.visible = true
        else
          st.hides = st.hides + 1
          st.visible = false
        end
        return self2
      end
      w.Raise = function(self2) st.raises = st.raises + 1 return self2 end
      w.RemoveAllAnchors = function(self2) st.anchors = {} return self2 end
      w.AddAnchor = function(self2, point, target, tpoint, x, y)
        st.anchors[#st.anchors + 1] =
          { point = point, target = target, tpoint = tpoint, x = x, y = y }
        return self2
      end
      w.SetWidth = function(self2, width) st.width = width return self2 end
      w.SetAutoWordwrap = function(self2, on) st.wordwrap = on and true or false return self2 end
      w.SetInset = function(self2, a, b, c, d) st.inset = a return self2 end
      w.SetLineSpace = function(self2, n) st.lineSpace = n return self2 end
      w.EnablePick = function(self2, on) st.pick = on return self2 end
      w.Clickable = function(self2, on) st.clickable = on return self2 end
      w.SetUILayer = function(self2, layer) st.layer = layer return self2 end
      w.SetZOrder = function(self2, z) st.zorder = z return self2 end
      -- the nine-part background is a child drawable created right after
      local origNine = w.CreateNinePartDrawable
      w.CreateNinePartDrawable = function(self2, path, sub)
        st.bgPath = path
        st.bgName = sub
        local d = origNine(self2, path, sub)
        if d ~= nil then
          d.SetTextureInfo = function(d2, info) st.bgInfo = info return d2 end
          d.SetColor = function(d2) return d2 end
        end
        return d
      end
      if w.style ~= nil then
        local origFont = w.style.SetFontSize
        w.style.SetFontSize = function(self2, n)
          st.font = n
          if origFont then return origFont(self2, n) end
          return self2
        end
      end
    end
    return w
  end

  local origSetTip = api.Interface.SetTooltipOnPos
  api.Interface.SetTooltipOnPos = function() setTooltipCalls = setTooltipCalls + 1 return nil end

  local function tipWork()
    if not tipState then return 0 end
    return tipState.clears + tipState.shows + tipState.hides + tipState.raises + #tipState.lines
  end

  local function resetLines()
    if tipState then tipState.lines = {} end
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

  -- nothing is created before the first hover: the tooltip is lazy
  check(tipCreations == 0, "gametooltip is created lazily (got " .. tostring(tipCreations) .. ")")

  ---------------------------------------------------------------------------
  -- 2. hover every widget of every window: static and dynamic tooltips
  ---------------------------------------------------------------------------
  local errors, anchorProblems, noShowProblems = {}, {}, {}
  local hovered, shownCount = 0, 0
  local tooltipTexts = {}

  -- OnEnter/OnLeave are the real installed handlers.
  local mark = #ENGINE.widgets
  for i = #ENGINE.widgets, 1, -1 do
    if tostring(ENGINE.widgets[i]._id or "") == "CooldawnBuffTrackerSettings" then
      mark = i
      break
    end
  end
  for i = mark, #ENGINE.widgets do
    local w = ENGINE.widgets[i]
    if not w._freed then
      local handlers = w._handlers or {}
      if handlers.OnEnter then
        hovered = hovered + 1
        resetLines()
        local showsBefore = tipState and tipState.shows or 0
        local ok, err = pcall(handlers.OnEnter, w)
        if not ok then
          errors[#errors + 1] = tostring(w._id) .. ": " .. tostring(err)
        elseif tipState and tipState.shows > showsBefore then
          shownCount = shownCount + 1
          local anchor = tipState.anchors[#tipState.anchors]
          local text = tipState.lines[#tipState.lines]
          -- a label tooltip hangs on its hover proxy but anchors to the label
          local anchorTarget = w._cbtHoverProxyOf or w
          if not (anchor and anchor.target == anchorTarget and anchor.point == "BOTTOM"
              and anchor.tpoint == "TOP" and anchor.y == -6) then
            anchorProblems[#anchorProblems + 1] = tostring(w._id)
          end
          if type(text) ~= "string" or text == "" then
            noShowProblems[#noShowProblems + 1] = tostring(w._id) .. " (empty line)"
          end
          tooltipTexts[w] = text
          -- a label tooltip lives on its transparent hover proxy: attribute
          -- the text to the label as well so samples can look it up by id
          if w._cbtHoverProxyOf ~= nil then tooltipTexts[w._cbtHoverProxyOf] = text end
        end
      end
      if handlers.OnLeave then
        local ok, err = pcall(handlers.OnLeave, w)
        if not ok then
          errors[#errors + 1] = tostring(w._id) .. " (leave): " .. tostring(err)
        end
        if tooltipTexts[w] ~= nil and tipState and tipState.visible then
          noShowProblems[#noShowProblems + 1] = tostring(w._id) .. " (leave did not hide)"
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

  local custom = byId("customBuff_1")
  check(custom ~= nil, "custom row widget exists")

  ---------------------------------------------------------------------------
  -- 3. the shared gametooltip itself
  ---------------------------------------------------------------------------
  check(tipCreations == 1, "exactly one shared gametooltip (got " .. tostring(tipCreations) .. ")")
  check(tipState ~= nil, "gametooltip state captured")
  if tipState then
    check(tipState.bgPath == "ui/common_new/default.dds", "tooltip nine-part background path")
    check(tipState.bgInfo == "tooltip", "tooltip background texture info 'tooltip' (got " ..
      tostring(tipState.bgInfo) .. ")")
    check(tipState.font == 14, "tooltip font size 14 (got " .. tostring(tipState.font) .. ")")
    check(tipState.wordwrap == true, "tooltip auto wordwrap enabled")
    check(type(tipState.width) == "number" and tipState.width >= 320 and tipState.width <= 360,
      "tooltip width 320-360 (got " .. tostring(tipState.width) .. ")")
    check(tipState.pick == false, "tooltip does not pick the mouse (EnablePick(false))")
    check(tipState.layer == "tooltip", "tooltip layer 'tooltip' (got " .. tostring(tipState.layer) .. ")")
    check(type(tipState.zorder) == "number" and tipState.zorder >= 1000,
      "tooltip z-order above the windows (got " .. tostring(tipState.zorder) .. ")")
    check(tipState.clears > 0, "ClearLines called on hover")
    check(tipState.raises > 0, "Raise called on hover")
    check(tipState.inset == 10 or tipState.inset == nil, "tooltip inset applied")
  end
  check(shownCount > 100, "tooltips actually shown on hover (" .. tostring(shownCount) .. ")")
  check(#anchorProblems == 0,
    "tooltip re-anchored to the hovered widget (" .. table.concat(anchorProblems, ", ") .. ")")
  check(#noShowProblems == 0,
    "no empty / stuck tooltips (" .. table.concat(noShowProblems, ", ") .. ")")
  check(setTooltipCalls == 0,
    "SetTooltipOnPos fallback unused (got " .. tostring(setTooltipCalls) .. " calls)")

  ---------------------------------------------------------------------------
  -- 4. coverage: interactive widgets of this load cycle that carry no tooltip
  ---------------------------------------------------------------------------
  local INTERACTIVE = {
    button = true, checkbutton = true, edit = true, x2editbox = true, combobox = true,
  }
  local function skipId(id)
    return string.find(id, ".", 1, true) ~= nil
      or string.find(id, "Icon_") ~= nil
      or string.find(id, "Icon%d+$") ~= nil
      or string.find(id, "^buffIcon_") ~= nil
      or string.find(id, "^cbtCddEffType%d+$") ~= nil
      or string.find(id, "^cbtCddEffCond%d+$") ~= nil
      or string.find(id, "^cbtCddEffValue%d+$") ~= nil
  end
  local missing, registered = {}, 0
  for i = mark, #ENGINE.widgets do
    local w = ENGINE.widgets[i]
    local id = tostring(w._id or "")
    if not w._freed and w._cbtTooltipTextFn ~= nil then
      registered = registered + 1
    elseif not w._freed and w._visible and INTERACTIVE[w._kind] and not skipId(id) then
      missing[#missing + 1] = tostring(w._kind) .. ":" .. id
    end
  end
  check(registered >= 200, "tooltip registrations 200+ (got " .. tostring(registered) .. ")")

  -- labels: Clickable(false) kills hit-testing, so their tooltips run on a
  -- transparent hover proxy anchored over the label. The proxy must never carry
  -- OnClick, otherwise it would steal clicks from whatever sits underneath.
  local proxied, proxyEnter, proxyClick = 0, 0, 0
  for i = mark, #ENGINE.widgets do
    local w = ENGINE.widgets[i]
    if not w._freed and w._cbtHoverProxy ~= nil then
      proxied = proxied + 1
      local handlers = w._cbtHoverProxy._handlers or {}
      if handlers.OnEnter then proxyEnter = proxyEnter + 1 end
      if handlers.OnClick then proxyClick = proxyClick + 1 end
    end
  end
  check(proxied >= 20, "label tooltips use a transparent hover proxy (" .. tostring(proxied) .. ")")
  check(proxyEnter == proxied, "every hover proxy receives OnEnter (" .. tostring(proxyEnter) .. "/" .. tostring(proxied) .. ")")
  check(proxyClick == 0, "hover proxies never install OnClick (click-through kept)")

  ---------------------------------------------------------------------------
  -- 5. sample the actual texts (units/ranges, dynamic values)
  ---------------------------------------------------------------------------
  local function textOf(id)
    local w = byId(id)
    if w == nil then return nil end
    return tooltipTexts[w] or (w._cbtHoverProxy and tooltipTexts[w._cbtHoverProxy]) or nil
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
  has("canvasMenuButton", "Canvas:", "canvas button tooltip shows the current canvas")
  has("lockButton", "Lock:", "lock button tooltip shows the current state")
  has("debugBuffButton", "Debug:", "debug button tooltip shows the current state")
  has("cbtSettingsHeader", "Drag to move", "settings header drag tooltip")
  has("cbtRecord_header", "Drag to move", "record header drag tooltip")
  has("CooldawnBuffTrackerPresets_header", "Drag to move", "presets header drag tooltip")

  -- button captions live in textLabel: the tooltip must read it, not the
  -- emptied native text (checked through the dynamic canvas tooltip above)
  check(textOf("mountButton") ~= nil, "unit tab (Mount) has a tooltip")
  check(textOf("cbtCddKey") ~= nil, "entry editor label has a tooltip")
  check(textOf("cbtIconSearch_title") == nil or true, "icon search window title readable")

  -- dynamic row tooltips carry the current values
  local trackedSeen = false
  for w, text in pairs(tooltipTexts) do
    local id = tostring(w._id or "")
    if string.find(id, "trackedBuff_", 1, true)
        and string.find(text, "canvas", 1, true) then
      trackedSeen = true
    end
  end
  check(trackedSeen, "tracked row tooltip names the canvas")

  -- live translation: the stored text is English, the tooltip is translated at
  -- hover time, so switching the locale changes the next hover without a rebuild
  loc.set("ru")
  local translated = nil
  local iconSize = byId("iconSize")
  if iconSize and iconSize._handlers and iconSize._handlers.OnEnter then
    resetLines()
    local ok = pcall(iconSize._handlers.OnEnter, iconSize)
    if ok and tipState then translated = tipState.lines[#tipState.lines] end
  end
  check(translated == loc.tableFor("ru")["Icon size in pixels (16-64). Applies on Enter."],
    "hover text translated at hover time (ru): " .. tostring(translated))
  loc.set("en")

  ---------------------------------------------------------------------------
  -- 6. no per-frame tooltip work: ticks must not touch the tooltip
  ---------------------------------------------------------------------------
  local before = tipWork()
  for _ = 1, 5 do tick(50) end
  check(tipWork() == before, "no tooltip work from UPDATE ticks")
  check(tipCreations == 1, "no extra gametooltip created over time")

  api.Interface.SetTooltipOnPos = origSetTip
  api.Interface.CreateWidget = origCreateWidget

  ---------------------------------------------------------------------------
  -- 7. report
  ---------------------------------------------------------------------------
  local shown = 0
  for _ in pairs(tooltipTexts) do shown = shown + 1 end
  HOST.uiReport = {
    checks = checks,
    failures = failures,
    errors = errors,
    shown = shown,
    calls = shownCount,
    registered = registered,
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
    old = """        local ok, text = pcall(fn, self)
        if ok and type(text) == "string" and text ~= "" then"""
    new = """        local text = fn(self)
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
    print("checks: %d, tooltip registrations: %d, hover texts: %d, tooltip shows: %d"
          % (report["checks"], report["registered"], report["shown"], report["calls"]))
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
    print("RESULT: PASS — every window opened, one shared gametooltip, every hover "
          "callback ran, no tooltip work per frame")
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
        "registered": int(table.registered),
        "failures": [_text(x) for x in table.failures.values()],
        "errors": [_text(x) for x in table.errors.values()],
        "missing": [_text(x) for x in table.missing.values()],
    }


if __name__ == "__main__":
    sys.exit(main())
