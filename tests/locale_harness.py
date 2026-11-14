#!/usr/bin/env python3
"""Offline harness for the localization layer (CooldawnBuffTracker 1.33.0).

Four things are verified:

1. Dictionary integrity — every English key exists in all four languages
   (en is the identity table, ru/tr/ko are translations), no empty values,
   no key that only exists in one translation, and every format specifier of the
   English template appears in the translation. Chinese is gone: no "zh" entry in
   locale.LANGS, no zh dictionary block, no zh option in the language popup.
2. Coverage — every string literal in the addon sources has a dictionary entry,
   except technical ones (widget ids, event and handler names, paths, colour
   codes, wallet addresses, debug-dump lines) and the game data tables. This is
   a full audit, not only the call sites that translate automatically.
3. Migration — a stored settings.language of "zh" (removed in 1.33.0) and any
   unknown code are rewritten to "en" on the first settings read.
4. Live switch — the settings window is opened inside the aac_smoke patch-293
   sandbox, the real Language button opens the real popup, each of the four
   languages is selected, and for every language the settings header, a hover
   tooltip (real shared gametooltip), a chat line AND a representative label of
   every child window (import/export, presets, record, icon search, entry
   editor, support) are checked. Switching the language while Import/Export and
   Presets are open must rebuild them in the new language (1.33.0 fix).

Usage:
    /home/hermes/work/.venv-aac/bin/python tests/locale_harness.py
Exit code 0 = all checks passed.
"""
import os
import re
import shutil
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON_ID = "CooldawnBuffTracker"
SKILL_SCRIPTS = os.environ.get(
    "AAC_SKILL_SCRIPTS",
    "/home/hermes/.hermes/skills/software-development/aac-addon-dev/scripts",
)
SCRATCH_ROOT = os.environ.get(
    "CBT_TEST_SCRATCH", "/home/hermes/.hermes/cache/scratch/cbt_locale_harness"
)

sys.path.insert(0, SKILL_SCRIPTS)
import aac_smoke  # noqa: E402

LANGS = ("en", "ru", "tr", "ko")

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
  local function widgetText(w)
    if not w then return nil end
    local target = w.textLabel or w
    local ok, text = pcall(function() return target:GetText() end)
    if ok then return text end
    return nil
  end

  ---------------------------------------------------------------------------
  -- 1. dictionary integrity + Chinese removal
  ---------------------------------------------------------------------------
  local keys = loc.keys()
  check(#keys > 300, "dictionary keys: " .. tostring(#keys))
  check(#loc.LANGS == 4, "four languages in LANGS (got " .. tostring(#loc.LANGS) .. ")")
  check(loc.validCode("zh") == nil, "zh is no longer a valid language code")
  check(loc.native("zh") == "English", "zh native name falls back to English")
  local ruTable = loc.tableFor("ru")
  local enTable = loc.tableFor("en")
  for _, k in ipairs(keys) do
    if enTable[k] ~= k then
      check(false, "en is not identity for: " .. k)
      break
    end
  end
  for _, code in ipairs({ "ru", "tr", "ko" }) do
    local t = loc.tableFor(code)
    local missing, empty, extra, same = 0, 0, 0, 0
    for _, k in ipairs(keys) do
      local v = t[k]
      if type(v) ~= "string" then
        missing = missing + 1
      elseif v == "" then
        empty = empty + 1
      elseif v == k then
        same = same + 1
      end
    end
    for k in pairs(t) do
      if enTable[k] == nil then extra = extra + 1 end
    end
    check(missing == 0, code .. ": missing keys " .. tostring(missing))
    check(empty == 0, code .. ": empty values " .. tostring(empty))
    check(extra == 0, code .. ": keys absent from en " .. tostring(extra))
    check(same < #keys / 4, code .. ": too many values equal to English (" .. tostring(same) .. ")")
  end
  check(ruTable["Tracked entries:"] ~= "Tracked entries:", "ru translates 'Tracked entries:'")

  ---------------------------------------------------------------------------
  -- 2. fallback and argument formatting
  ---------------------------------------------------------------------------
  loc.set("ru")
  check(loc.L("__cbt_missing_key__") == "__cbt_missing_key__", "unknown key falls back to source")
  check(loc.L("Mana skill") == ruTable["Mana skill"], "known key translated")
  local formatted = loc.L("Page %s - 7 presets per page.", 3)
  check(string.find(formatted, "3", 1, true) ~= nil, "format argument substituted")
  check(string.find(formatted, "%%s", 1, true) == nil, "no raw %s left in output")
  check(loc.L("Page %s - 7 presets per page.", 3) == ruTable["Page %s - 7 presets per page."]:gsub("%%s", "3"),
    "translated template formatted")
  loc.set("en")
  check(loc.current() == "en", "language reset to en")

  ---------------------------------------------------------------------------
  -- 3. migration of removed / unknown codes
  ---------------------------------------------------------------------------
  local s = api.GetSettings("CooldawnBuffTracker")
  check(s.language == "en", "settings.language migrated to en: " .. tostring(s.language))
  s.language = "zh"
  loc.applySettings(s)
  check(loc.current() == "en", "stored zh migrates to en (current)")
  check(s.language == "en", "stored zh rewritten to en in settings: " .. tostring(s.language))
  s.language = "xx"
  loc.applySettings(s)
  check(loc.current() == "en", "unknown code migrates to en")
  check(s.language == "en", "unknown code rewritten to en in settings")

  -- custom entries so the entry editor and its rows exist
  s.customBuffs = {
    { id = 800004, name = "Test Buff", cooldown = 30, timeOfAction = 3, kind = "buff",
      effectiveCDs = true, smartPct = 5,
      cdMods = {
        { id = 800005, name = "Mod A", kind = "flat", value = 5, condition = "always" },
        { name = "Mod B", kind = "percent", value = 10, condition = "target" },
      } },
    { id = "TestSkill", name = "Test Skill", cooldown = 12, kind = "skill", spellName = "TestSkill" },
  }

  ---------------------------------------------------------------------------
  -- 4. tooltip capture: the real shared gametooltip, created lazily
  ---------------------------------------------------------------------------
  local tipState = nil
  local tipCreations = 0
  local origCreateWidget = api.Interface.CreateWidget
  api.Interface.CreateWidget = function(self, kind, id, parent)
    local w = origCreateWidget(self, kind, id, parent)
    if kind == "gametooltip" and w ~= nil then
      tipCreations = tipCreations + 1
      local st = { lines = {}, anchors = {}, shows = 0, hides = 0, visible = false }
      w._cbtTip = st
      if tipState == nil then tipState = st end
      w.ClearLines = function(self2) st.lines = {} return self2 end
      w.AddLine = function(self2, text) st.lines[#st.lines + 1] = tostring(text) return self2 end
      w.Show = function(self2, show)
        if show then st.shows = st.shows + 1; st.visible = true
        else st.hides = st.hides + 1; st.visible = false end
        return self2
      end
      w.Raise = function(self2) return self2 end
      w.RemoveAllAnchors = function(self2) st.anchors = {} return self2 end
      w.AddAnchor = function(self2, point, target, tpoint, x, y)
        st.anchors[#st.anchors + 1] =
          { point = point, target = target, tpoint = tpoint, x = x, y = y }
        return self2
      end
    end
    return w
  end
  local origSetTip = api.Interface.SetTooltipOnPos
  local setTooltipCalls = 0
  api.Interface.SetTooltipOnPos = function() setTooltipCalls = setTooltipCalls + 1 return nil end

  local function hover(id)
    local w = byId(id)
    if not w then return nil end
    -- подпись с Clickable(false) держит подсказку на прозрачном hover-прокси,
    -- сам tooltip при этом анкорится к подписи
    local host = w._cbtHoverProxy or w
    if not (host._handlers and host._handlers.OnEnter) then return nil end
    if tipState then tipState.lines = {} end
    local showsBefore = tipState and tipState.shows or 0
    host._handlers.OnEnter(host)
    local st = tipState
    if not st or st.shows <= showsBefore then return nil end
    local anchor = st.anchors[#st.anchors]
    if not (anchor and anchor.target == w) then return nil end
    return st.lines[#st.lines]
  end

  -- chat capture
  local logs = {}
  local origInfo, origErr = api.Log.Info, api.Log.Err
  api.Log.Info = function(_, line) logs[#logs + 1] = tostring(line) end
  api.Log.Err = function(_, line) logs[#logs + 1] = tostring(line) end

  ---------------------------------------------------------------------------
  -- 5. open the settings window and the language popup
  ---------------------------------------------------------------------------
  sp.openSettingsWindow()
  check(byId("CooldawnBuffTrackerSettings") ~= nil, "settings window created")
  local button = byId("languageButton")
  check(button ~= nil, "language button exists in the header")
  check(string.find(tostring(widgetText(button)), "English", 1, true) ~= nil, "language button shows English")
  local caption = tostring(widgetText(button))
  check(#caption <= 24, "language caption fits the 150 px button (" .. caption .. ")")

  local enHeader = widgetText(byId("trackedBuffsListHeader"))
  check(enHeader == "Tracked entries:", "English header before switch: " .. tostring(enHeader))
  local enTip = hover("iconGroupLabel")
  check(type(enTip) == "string" and string.find(enTip, "Icon layout", 1, true) ~= nil,
    "English tooltip before switch: " .. tostring(enTip))

  local seq = 0
  local function selectLanguage(code)
    seq = seq + 1
    check(click("languageButton"), "language button clicked (" .. code .. ")")
    local option = byId("cbtLanguageOption_" .. code .. "_" .. tostring(seq))
    check(option ~= nil, "popup lists option " .. code)
    check(click("cbtLanguageOption_" .. code .. "_" .. tostring(seq)), "option clicked " .. code)
    return option ~= nil
  end

  -- popup opener lists exactly the four languages: Chinese is gone
  click("languageButton")
  for _, code in ipairs({ "en", "ru", "tr", "ko" }) do
    check(byId("cbtLanguageOption_" .. code .. "_1") ~= nil, "popup option present: " .. code)
  end
  check(byId("cbtLanguageOption_zh_1") == nil, "no Chinese option in the popup")
  -- close it again (pick the current language, which must be a no-op rebuild)
  click("cbtLanguageOption_en_1")
  seq = 1

  local expectedHeader = {
    en = "Tracked entries:",
    ru = ruTable["Tracked entries:"],
    tr = loc.tableFor("tr")["Tracked entries:"],
    ko = loc.tableFor("ko")["Tracked entries:"],
  }

  -- representative labels of the child windows, by widget id -> English key
  local CHILD_LABELS = {
    { window = "CooldawnBuffTrackerImportExport", id = "exportLabel",
      key = "EXPORT - save your current setup to a file:" },
    { window = "CooldawnBuffTrackerPresets", id = "cbtPresetListHeader",
      key = "Saved presets:" },
    { window = "cbtRecord", id = "cbtRecUnitLabel", key = "Unit:" },
    { window = "cbtIconSearch", id = "cbtIconSearch_title", key = "Icon search" },
    { window = "cbtCddWindow", id = "cbtCddKeyLabel", key = "ID:" },
    { window = "CooldawnBuffTrackerSupport", id = "CooldawnBuffTrackerSupport_title",
      key = "Support the Addon Developer" },
  }

  local function openChildWindows()
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
  end

  local previousTip = enTip
  for _, code in ipairs({ "ru", "tr", "ko", "en" }) do
    selectLanguage(code)
    check(loc.current() == code, "current language " .. code .. " (got " .. tostring(loc.current()) .. ")")
    check(api.GetSettings("CooldawnBuffTracker").language == code,
      "settings.language persisted as " .. code)
    local header = widgetText(byId("trackedBuffsListHeader"))
    check(header == expectedHeader[code],
      code .. " header text: " .. tostring(header) .. " ~= " .. tostring(expectedHeader[code]))
    local tip = hover("iconGroupLabel")
    check(type(tip) == "string" and tip ~= "", code .. ": tooltip present")
    check(loc.L("Icon layout of the selected canvas: size, spacing, label and grid.")
      == loc.tableFor(code)["Icon layout of the selected canvas: size, spacing, label and grid."],
      code .. ": probe L() on the tooltip key")
    check(tip == loc.tableFor(code)["Icon layout of the selected canvas: size, spacing, label and grid."],
      code .. ": gametooltip text equals dictionary value")
    check(tip ~= previousTip, code .. ": tooltip changed with the language (" ..
      tostring(previousTip) .. " -> " .. tostring(tip) .. ")")
    previousTip = tip
    local line = logs[#logs]
    check(type(line) == "string" and string.find(line, "|cFF87CEEB[CBT]|r", 1, true) ~= nil,
      code .. ": colored [CBT] tag kept")
    local template = loc.tableFor(code)["Language changed to %s"]
    local prefix = string.match(template, "^[^%%]*")
    check(type(line) == "string" and prefix ~= nil and prefix ~= ""
      and string.find(line, prefix, 1, true) ~= nil,
      code .. ": chat line translated (" .. tostring(line) .. ")")
    -- the window is rebuilt on every switch: exactly one live settings window
    local live = 0
    for i = 1, #ENGINE.widgets do
      local w = ENGINE.widgets[i]
      if not w._freed and tostring(w._id or "") == "CooldawnBuffTrackerSettings" then
        live = live + 1
      end
    end
    check(live == 1, code .. ": exactly one settings window (" .. tostring(live) .. ")")
    local okVis, vis = pcall(function() return byId("CooldawnBuffTrackerSettings"):IsVisible() end)
    check(okVis and vis, code .. ": settings window visible (" .. tostring(vis) .. ")")

    -- every child window must come up in the selected language
    openChildWindows()
    for _, spec in ipairs(CHILD_LABELS) do
      check(byId(spec.window) ~= nil, code .. ": window exists " .. spec.window)
      local w = byId(spec.id)
      local text = widgetText(w)
      local expected = loc.tableFor(code)[spec.key]
      check(text == expected, code .. ": " .. spec.id .. " = " .. tostring(text) ..
        " (expected " .. tostring(expected) .. ")")
    end
  end

  ---------------------------------------------------------------------------
  -- 6. switching the language while Import/Export and Presets are open
  ---------------------------------------------------------------------------
  check(loc.current() == "en", "stale-window test starts in English")
  check(click("importExportButton"), "import/export opened in English")
  check(click("presetsButton"), "presets opened in English")
  local oldIE = byId("CooldawnBuffTrackerImportExport")
  local oldPresets = byId("CooldawnBuffTrackerPresets")
  check(oldIE ~= nil and oldPresets ~= nil, "both windows exist before the switch")
  check(widgetText(byId("exportLabel")) == "EXPORT - save your current setup to a file:",
    "import/export shows English before the switch")

  selectLanguage("ru")
  check(loc.current() == "ru", "language switched to ru with the windows open")
  check(oldIE == nil or oldIE._freed == true, "old import/export window was destroyed")
  check(oldPresets == nil or oldPresets._freed == true, "old presets window was destroyed")

  check(click("importExportButton"), "import/export reopened after the switch")
  check(click("presetsButton"), "presets reopened after the switch")
  check(widgetText(byId("exportLabel")) == ruTable["EXPORT - save your current setup to a file:"],
    "reopened import/export is Russian: " .. tostring(widgetText(byId("exportLabel"))))
  check(widgetText(byId("cbtPresetListHeader")) == ruTable["Saved presets:"],
    "reopened presets is Russian: " .. tostring(widgetText(byId("cbtPresetListHeader"))))

  -- and the ordinary reuse path still works: reopen without a language change
  check(click("importExportButton"), "import/export toggled closed")
  local cachedIE = byId("CooldawnBuffTrackerImportExport")
  check(click("importExportButton"), "import/export reopened without a language change")
  check(byId("CooldawnBuffTrackerImportExport") == cachedIE,
    "window reused when the language did not change")

  selectLanguage("en")
  check(loc.current() == "en", "back to English")

  local finalButton = byId("languageButton")
  check(string.find(tostring(widgetText(finalButton)), "English", 1, true) ~= nil,
    "language button back to English: " .. tostring(widgetText(finalButton)))

  ---------------------------------------------------------------------------
  -- 7. no per-frame tooltip work is added by the locale layer
  ---------------------------------------------------------------------------
  check(tipCreations == 1, "one shared gametooltip across seven window builds (" ..
    tostring(tipCreations) .. ")")
  check(setTooltipCalls == 0, "SetTooltipOnPos fallback unused")
  local before = tipState and tipState.shows or 0
  for _ = 1, 5 do tick(50) end
  local after = tipState and tipState.shows or 0
  check(before == after, "no tooltip calls from UPDATE ticks")

  api.Interface.SetTooltipOnPos = origSetTip
  api.Interface.CreateWidget = origCreateWidget
  api.Log.Info = origInfo
  api.Log.Err = origErr

  ---------------------------------------------------------------------------
  -- 8. report
  ---------------------------------------------------------------------------
  HOST.localeReport = {
    checks = checks,
    failures = failures,
    logs = logs,
  }
end
"""

# Literals that never reach the widget or chat layer. Everything else that is
# neither in the dictionary nor matched by these patterns is reported, so a new
# English string cannot slip in untranslated.
ALLOW_PATTERNS = (
    r"/",                                   # paths and texture names
    r"\.(dds|tbl|lua|txt|png|html|json)$",  # file names
    r"^[a-z][A-Za-z0-9_]*$",                # widget ids, unit ids, machine values
    r"^[A-Z][A-Z0-9_]*$",                   # constants and event names
    r"^[A-Za-z0-9_]+_$",                    # widget id prefixes
    r"^_",                                  # internal fields
    r"^[0-9a-fx]+$",                        # wallet addresses
    r"^\|c",                                # chat colour codes
    r"^On[A-Z]",                            # handler names
    r"^\s*[A-Za-z_][A-Za-z0-9_]*=$",        # key=value debug fragments
    r"^[A-Za-z0-9]{26,}$",                  # wallet addresses and long tokens
    r"^[A-Za-z]+\[[0-9]+\]$",               # table[index] references
)

# Exact exceptions: addon metadata, data values that must not be translated
# (a stored canvas name), and strings that only go into a debug dump file.
ALLOW_EXACT = {
    "Buff #", "Canvas ", "Main", "Addon for tracking buffs", "Adfazer & Claude",
    "playerpet", "player", "target", "English", "Русский", "Türkçe", "한국어",
    "Label", "System", "Pending", "Unknown", "TrackThatPlease", "UIParent",
    "LeftButton", "RightButton", "GetUnitClassName=", " err=", " name=",
    # api.Interface lookup names used by the TrackThatPlease widget resolver
    "FindWidget", "GetWindow", "GetWidgetByName",
    "CBTCombatEvents", "BuffCanvas", "MountBuffCanvas", "PlayerBuffCanvas",
    "TargetBuffCanvas", "CooldawnBuffTracker", "CooldawnBuffTrackerSettings",
    "CooldawnBuffTrackerPresets", "CooldawnBuffTrackerImportExport",
    "CooldawnBuffTrackerSupport",
    # aura_dump.tbl lines: a debug file, never chat
    "[class] ", "[class] UnitClass=", "[target] id=", "[session] aura dump started",
    "%s(mount=%s,ready=%s)", "%s*%(%s*[Rr]ank%s*%d+%s*%)%s*$",
    "+ %s id=%s name=%s stack=%s time=%s", "~ %s id=%s name=%s stack=%s time=%s",
    "- %s id=%s name=%s",
}

# Files that are data rather than UI: buff names and the icon table must stay
# verbatim (they are game data, not translatable text).
DATA_FILES = {"buff_helper.lua", "buffs_to_track.lua", "api.lua", "locale.lua"}

STR_RE = re.compile(r'"((?:[^"\\]|\\.)*)"' + r"|'((?:[^'\\]|\\.)*)'")
SPEC_RE = re.compile(r"%[-+ 0#]*[0-9]*(?:\.[0-9]+)?[diouxXeEfgGqs%]")


def lua_strings(text):
    return [m.group(1) if m.group(1) is not None else m.group(2) for m in STR_RE.finditer(text)]


def calls(src, name):
    """String-aware call scanner: parentheses inside literals must not count."""
    out = []
    for m in re.finditer(re.escape(name) + r"\s*\(", src):
        i = m.end()
        depth, j, quote = 1, i, None
        while j < len(src) and depth > 0:
            ch = src[j]
            if quote:
                if ch == "\\":
                    j += 2
                    continue
                if ch == quote:
                    quote = None
            elif ch in "\"'":
                quote = ch
            elif ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            j += 1
        out.append((src[i:j - 1], src.count("\n", 0, m.start()) + 1))
    return out


def unescape(value):
    out, i = "", 0
    while i < len(value):
        if value[i] == "\\" and i + 1 < len(value):
            nxt = value[i + 1]
            out += {"n": "\n", "t": "\t", "\\": "\\", "'": "'", '"': '"'}.get(nxt, "\\" + nxt)
            i += 2
        else:
            out += value[i]
            i += 1
    return out


def strip_comment(line):
    out, quote, i = "", None, 0
    while i < len(line):
        ch = line[i]
        if quote:
            out += ch
            if ch == "\\" and i + 1 < len(line):
                out += line[i + 1]
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            out += ch
        elif ch == "-" and i + 1 < len(line) and line[i + 1] == "-":
            break
        else:
            out += ch
        i += 1
    return out


def lua_sources():
    for root, dirs, files in os.walk(REPO):
        if ".git" in root or os.path.basename(root) in ("tests", "docs"):
            continue
        for name in sorted(files):
            if name.endswith(".lua") and name not in DATA_FILES:
                yield os.path.join(root, name)


def is_technical(value):
    if value in ALLOW_EXACT:
        return True
    for pattern in ALLOW_PATTERNS:
        if re.search(pattern, value):
            return True
    return not re.search(r"[A-Za-z]{2,}", value)


def dictionary():
    """Parse the DICT blocks of locale.lua into {code: {key: value}}."""
    path = os.path.join(REPO, "locale.lua")
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    result = {}
    for code in ("ru", "tr", "ko"):
        match = re.search(r"dict\." + code + r"\s*=\s*\[(==?)\[(.*?)\]\1\]", text, re.S)
        if not match:
            raise SystemExit("locale.lua: dict.%s block not found" % code)
        table = {}
        for line in match.group(2).split("\n"):
            if not line.strip():
                continue
            key, sep, value = line.partition("\t")
            if not sep:
                raise SystemExit("locale.lua: malformed line in %s: %r" % (code, line))
            table[key] = value
        result[code] = table
    if re.search(r"dict\.zh\s*=", text):
        raise SystemExit("locale.lua: the zh dictionary must be removed in 1.33.0")
    return result


def coverage(table):
    """Every English string in the UI/chat layer must have a translation."""
    missing = []
    for path in lua_sources():
        rel = os.path.relpath(path, REPO)
        with open(path, "r", encoding="utf-8") as handle:
            lines = handle.readlines()
        for number, raw in enumerate(lines, 1):
            code = strip_comment(raw)
            if not code.strip():
                continue
            for literal in lua_strings(code):
                value = unescape(literal)
                if len(value) < 2 or is_technical(value) or value in table["ru"]:
                    continue
                missing.append("%s:%d %s" % (rel, number, value))
    return missing


def specifiers_compatible(table):
    problems = []
    for key, ru in table["ru"].items():
        en_specs = sorted(SPEC_RE.findall(key))
        for code in ("ru", "tr", "ko"):
            translated = table[code].get(key)
            if translated is None:
                continue
            if sorted(SPEC_RE.findall(translated)) != en_specs:
                problems.append("%s: %s specifiers differ (%r vs %r)"
                                % (code, key, en_specs, sorted(SPEC_RE.findall(translated))))
    return problems


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


def main():
    table = dictionary()
    print("dictionary: %d keys per language (ru/tr/ko)" % len(table["ru"]))

    problems = specifiers_compatible(table)
    if problems:
        for item in problems[:20]:
            print("SPEC:", item)
        print("RESULT: FAIL — %d format specifier mismatch(es)" % len(problems))
        return 1

    missing = coverage(table)
    if missing:
        print("literals without a translation (%d):" % len(missing))
        for item in missing[:40]:
            print("   ", item)
        print("RESULT: FAIL — %d untranslated literal(s)" % len(missing))
        return 1
    print("coverage: every UI/chat string in the sources has a translation")

    os.makedirs(SCRATCH_ROOT, exist_ok=True)
    addon_dir = os.path.join(SCRATCH_ROOT, ADDON_ID)
    copy_addon(addon_dir)
    patch_main(addon_dir)

    LuaRuntime = aac_smoke.load_lua51()
    if LuaRuntime is None:
        print("lupa (Lua 5.1) is not importable; use the .venv-aac interpreter", file=sys.stderr)
        return 2
    lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
    host = lua.execute(build_host(aac_smoke).encode("utf-8"), name="@cbt_locale_host.lua")

    result = aac_smoke.run_smoke(lua, host, addon_dir, ADDON_ID, SCRATCH_ROOT, [], 12)
    report = host_get(host, "localeReport")
    if report is None:
        print("RESULT: FAIL — the locale phase did not run")
        print("message:", result.get("message"))
        if result.get("traceback"):
            print(result["traceback"])
        return 1

    failures = list(report["failures"])
    print("checks: %d, chat lines captured: %d" % (report["checks"], len(report["logs"])))
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
    print("RESULT: PASS — 4 languages, Chinese removed and migrated, dictionaries complete, "
          "every window rebuilt in the selected language")
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
        "logs": [_text(x) for x in table.logs.values()],
    }


if __name__ == "__main__":
    sys.exit(main())
