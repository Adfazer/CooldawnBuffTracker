#!/usr/bin/env python3
"""Offline harness for the 1.32.0 skill-icon pool (CooldawnBuffTracker).

Two layers, both offline:

1. Assets — `skill_icons/manifest.tsv` and `skill_dump.tbl` must describe the
   same 323 entries over 10 class trees: every PNG exists, has a valid PNG
   signature and sane square dimensions, every path resolves inside
   `skill_icons/`, ids are unique and never collide with `buff_dump.tbl`,
   names are non-empty and carry no `(Rank N)` suffix, and no (name, file) pair
   is duplicated.
2. Loader/search — the real `main.lua` runs inside the aac_smoke patch-293
   sandbox with both data files preloaded exactly as `api.File:Read` returns
   them. The real `loadBuffDump()` must report buffs + skills, and the real
   `searchIcons()` provider must find a skill by its English name and return a
   path that exists on disk. A second run without `skill_dump.tbl` proves the
   old buff-only install still loads.

Usage:
    /home/hermes/work/.venv-aac/bin/python tests/skill_icons_harness.py
Exit code 0 = all checks passed.
"""
import os
import re
import shutil
import struct
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON_ID = "CooldawnBuffTracker"
SKILL_SCRIPTS = os.environ.get(
    "AAC_SKILL_SCRIPTS",
    "/home/hermes/.hermes/skills/software-development/aac-addon-dev/scripts",
)
SCRATCH_ROOT = os.environ.get(
    "CBT_TEST_SCRATCH", "/home/hermes/.hermes/cache/scratch/cbt_skill_icons_harness"
)

sys.path.insert(0, SKILL_SCRIPTS)
import aac_smoke  # noqa: E402
from lupa import lua51  # noqa: E402

TREES = (
    "Battlerage", "Witchcraft", "Defense", "Auramancy", "Occultism",
    "Archery", "Sorcery", "Shadowplay", "Songcraft", "Vitalism",
)
# Snapshot of the wiki pages on 2026-11-14; regenerate the assets when a page
# changes and update these numbers together with the manifest.
EXPECTED = {
    "Battlerage": (31, 8),
    "Witchcraft": (20, 7),
    "Defense": (21, 8),
    "Auramancy": (22, 8),
    "Occultism": (27, 8),
    "Archery": (24, 7),
    "Sorcery": (27, 8),
    "Shadowplay": (22, 8),
    "Songcraft": (22, 8),
    "Vitalism": (29, 8),
}
SKILL_PREFIX = "../Addon/CooldawnBuffTracker/skill_icons/"
SYNTH_MIN = 9000000

failures = []
checks = [0]


def check(condition, message):
    checks[0] += 1
    if not condition:
        failures.append(message)


def lua_load_table(path):
    """api.File:Read loads the shipped text with a `return` prefix."""
    source = open(path, "rb").read().decode("utf-8")
    runtime = lua51.LuaRuntime()
    loader = runtime.eval(
        'function(s) local f=loadstring or load; local fn,err=f("return "..s); '
        'if not fn then return nil,err end; local ok,v=pcall(fn); '
        'if not ok then return nil,v end; return v end'
    )
    table = loader(source)
    if table is None:
        raise SystemExit("%s: not a Lua table" % path)
    return table


def png_size(path):
    data = open(path, "rb").read()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        return None
    if data[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", data[16:24])


def asset_checks():
    manifest_path = os.path.join(REPO, "skill_icons", "manifest.tsv")
    check(os.path.isfile(manifest_path), "manifest.tsv exists")
    lines = [l for l in open(manifest_path, encoding="utf-8").read().splitlines() if l]
    header = lines[0].split("\t")
    check(header[:5] == ["tree", "type", "skill_id", "name", "raw_name"],
          "manifest header: %r" % header)
    rows = [dict(zip(header, line.split("\t"))) for line in lines[1:]]
    check(len(rows) == sum(a + p for a, p in EXPECTED.values()),
          "manifest row count %d" % len(rows))

    per_tree = {}
    for row in rows:
        per_tree.setdefault(row["tree"], {"active": 0, "passive": 0})
        per_tree[row["tree"]][row["type"]] += 1
    check(set(per_tree) == set(TREES), "manifest covers exactly ten trees: %r" % sorted(per_tree))
    for tree, (active, passive) in EXPECTED.items():
        got = per_tree.get(tree, {"active": -1, "passive": -1})
        check(got["active"] == active and got["passive"] == passive,
              "%s counts active/passive %r != %r" % (tree, got, (active, passive)))
    check(sum(1 for r in rows if r["type"] == "passive") == 78, "78 passives in total")

    dump = lua_load_table(os.path.join(REPO, "skill_dump.tbl"))
    check(dump is not None and dump["count"] == len(rows), "skill_dump count matches manifest")
    dump_rows = []
    for line in dump["dump"].split("\n"):
        parts = line.split("\t")
        check(len(parts) == 3, "dump line has three columns: %r" % line[:60])
        if len(parts) == 3:
            dump_rows.append(parts)
    check(len(dump_rows) == len(rows), "dump and manifest are 1:1 (%d/%d)"
          % (len(dump_rows), len(rows)))

    # buff ids: ids in the merged pool must not collide
    buff = lua_load_table(os.path.join(REPO, "buff_dump.tbl"))
    buff_ids = set()
    valid_buffs = 0
    for line in buff["dump"].split("\n"):
        parts = line.split("\t")
        if len(parts) >= 2 and parts[0].strip().isdigit():
            buff_ids.add(int(parts[0]))
        # mirror main.lua: a name with an embedded newline is not a loadable row
        if len(parts) == 3 and parts[0].strip().isdigit() and parts[2].strip() != "":
            valid_buffs += 1
    check(len(buff_ids) > 20000, "buff_dump still has %d ids" % len(buff_ids))
    check(valid_buffs > 20000, "buff_dump loads %d rows" % valid_buffs)

    ids, names_files, shas = set(), set(), {}
    manifest_by_key = {(r["skill_id"], r["name"], r["file"]) for r in rows}
    dump_keys = {(i, n, p) for i, n, p in
                 ((row[0], row[1], row[2].replace(SKILL_PREFIX, "")) for row in dump_rows)}
    check(manifest_by_key == dump_keys, "manifest and dump describe the same entries")

    for row in rows:
        rid, name, file_name, path = row["skill_id"], row["name"], row["file"], row["file"]
        check(rid.isdigit(), "numeric id: %r" % rid)
        if not rid.isdigit():
            continue
        rid = int(rid)
        check(rid not in ids, "duplicate id %d" % rid)
        ids.add(rid)
        check(rid not in buff_ids, "id %d collides with buff_dump" % rid)
        check(rid >= SYNTH_MIN or rid < SYNTH_MIN, "id range")
        check(name.strip() != "", "empty name for id %d" % rid)
        check("(Rank" not in name and "(rank" not in name, "rank suffix left in %r" % name)
        check("/" not in file_name and "\\" not in file_name, "icon is a bare file name: %r" % file_name)
        check(re.match(r"^[A-Za-z0-9_.-]+\.png$", file_name) is not None,
              "safe PNG file name: %r" % file_name)
        check(row["type"] in ("active", "passive"), "type: %r" % row["type"])
        check(row["source_page"].startswith("https://wiki.aa-classic.com/" + row["tree"]),
              "source page for %r: %r" % (name, row["source_page"]))
        check(row["icon_url"].startswith("https://wiki.aa-classic.com/images/"),
              "icon url for %r: %r" % (name, row["icon_url"]))
        check((name.lower(), file_name) not in names_files,
              "duplicate (name, file): %r" % name)
        names_files.add((name.lower(), file_name))
        full = os.path.join(REPO, "skill_icons", file_name)
        check(os.path.isfile(full), "missing PNG %s" % file_name)
        if os.path.isfile(full):
            size = png_size(full)
            check(size is not None, "invalid PNG %s" % file_name)
            if size:
                w, h = size
                check(w == h and 16 <= w <= 256, "dimensions %dx%d for %s" % (w, h, file_name))
            import hashlib
            sha = hashlib.sha256(open(full, "rb").read()).hexdigest()
            check(sha not in shas or shas[sha] == file_name,
                  "identical bytes in %s and %s" % (file_name, shas.get(sha)))
            shas[sha] = file_name

    check(len(dump_rows) == len(ids), "dump ids are unique (%d/%d)" % (len(ids), len(dump_rows)))
    packaged = sorted(f for f in os.listdir(os.path.join(REPO, "skill_icons"))
                      if f.lower().endswith(".png"))
    check(len(packaged) == len(set(r["file"] for r in rows)),
          "packaged PNGs match the manifest (%d/%d)"
          % (len(packaged), len(set(r["file"] for r in rows))))
    print("assets: %d entries (%d active, %d passive), %d PNGs, %d trees, 0 skipped"
          % (len(rows), sum(1 for r in rows if r["type"] == "active"),
             sum(1 for r in rows if r["type"] == "passive"), len(packaged), len(per_tree)))
    return valid_buffs, len(rows)


TEST_HOOK = r"""
CooldawnBuffTracker.__test = {
  searchIcons = searchIcons,
  dumpInfo = function()
    if not buffDump then return nil end
    return {
      count = buffDump.count,
      list = #buffDump.list,
      buffByName = buffDump.byName["fatigue"] and buffDump.byName["fatigue"].path or nil,
      skillByName = buffDump.byName["radiant terrifying roar"] and buffDump.byName["radiant terrifying roar"].path or nil,
      nameCount = (function() local n = 0 for _ in pairs(buffDump.byName) do n = n + 1 end return n end)(),
    }
  end,
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
  local function skillRows(rows)
    local n = 0
    for _, r in ipairs(rows) do
      if string.find(tostring(r.path), "skill_icons/", 1, true) then n = n + 1 end
    end
    return n
  end
  local function has(rows, file)
    for _, r in ipairs(rows) do
      if string.find(tostring(r.path), file, 1, true) then return true end
    end
    return false
  end

  local info = hook.dumpInfo()
  check(info ~= nil, "buffDump is loaded")
  if info then
    check(info.count == EXPECT_COUNT, "merged count " .. tostring(info.count) .. " ~= " .. tostring(EXPECT_COUNT))
    check(info.list == EXPECT_COUNT, "sorted list size " .. tostring(info.list))
    check(info.nameCount > 15000, "byName index size " .. tostring(info.nameCount))
    check(type(info.buffByName) == "string" and string.find(info.buffByName, "game/ui/icon/", 1, true) == 1,
      "buff name still resolves from buff_dump: " .. tostring(info.buffByName))
    if EXPECT_SKILLS then
      check(type(info.skillByName) == "string"
        and string.find(info.skillByName, "skill_icons/", 1, true) ~= nil,
        "skill name resolves from skill_dump: " .. tostring(info.skillByName))
    else
      check(info.skillByName == nil, "skill name absent without skill_dump")
    end
  end

  local rows = hook.searchIcons("Radiant Terrifying Roar", 20)
  if EXPECT_SKILLS then
    check(#rows >= 1, "search by English skill name returns rows")
    check(has(rows, "skill_icons/Aac-radiant_terrifying_roar.png"), "Radiant Terrifying Roar icon")
  else
    check(#rows == 0, "skill-only name is absent without skill_dump")
  end

  rows = hook.searchIcons("Weapon Maneuvers", 20)
  check(#rows >= 1, "passive Weapon Maneuvers is searchable")
  if EXPECT_SKILLS then
    check(has(rows, "skill_icons/Icon_skill_fight03.png"), "Weapon Maneuvers icon")
  end

  rows = hook.searchIcons("Charge", 100)
  check(#rows >= 1, "Charge is searchable")
  if EXPECT_SKILLS then
    check(has(rows, "skill_icons/Icon_skill_fight14.png"), "Charge skill icon")
  end

  rows = hook.searchIcons("Triple Slash", 200)
  if EXPECT_SKILLS then
    check(skillRows(rows) == 9, "Triple Slash keeps nine morph icons: " .. tostring(skillRows(rows)))
  end

  rows = hook.searchIcons("zzz-no-such-skill", 10)
  check(#rows == 0, "unknown query returns nothing")
  rows = hook.searchIcons("", 40)
  check(#rows == 40, "empty query lists the pool: " .. tostring(#rows))
  rows = hook.searchIcons("Fatigue", 10)
  check(#rows >= 1 and string.find(tostring(rows[1].path), "game/ui/icon/", 1, true) == 1,
    "buff dump is searched alongside skills")

  HOST.skillReport = { checks = checks, failures = failures }
  if #failures > 0 then
    error(table.concat(failures, " | "), 0)
  end
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
    text = open(path, encoding="utf-8").read()
    marker = "\nreturn CooldawnBuffTracker"
    index = text.rfind(marker)
    if index < 0:
        raise SystemExit("main.lua: final return not found")
    open(path, "w", encoding="utf-8").write(text[:index] + "\n" + TEST_HOOK + text[index:])


def build_host(lua_module, addon_dir, expect_count, expect_skills):
    host_lua = lua_module.HOST_LUA
    preload = (
        '  do\n'
        '    local function preload(rel)\n'
        '      local fh = io.open(%r .. "/" .. rel, "rb")\n'
        '      if fh then ENGINE.files[ADDON_ID .. "/" .. rel] = fh:read("*a"); fh:close() end\n'
        '    end\n'
        '    preload("buff_dump.tbl")\n'
        '    preload("skill_dump.tbl")\n'
        '  end\n\n'
    ) % addon_dir
    anchor = "  ENGINE.dirs[ADDON_ID] = true\n"
    if anchor not in host_lua:
        raise SystemExit("aac_smoke HOST_LUA layout changed: ENGINE.dirs anchor not found")
    host_lua = host_lua.replace(anchor, anchor + "\n" + preload, 1)
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
    consts = "EXPECT_COUNT = %d\nEXPECT_SKILLS = %s\n" % (expect_count, "true" if expect_skills else "false")
    return head + consts + TEST_LUA + "\nreturn HOST" + tail


def run_lua_case(name, addon_dir, expect_count, expect_skills):
    runtime = lua51.LuaRuntime()
    host = runtime.execute(build_host(aac_smoke, addon_dir, expect_count, expect_skills).encode("utf-8"),
                           name="@cbt_skill_icons_host.lua")
    opts = runtime.table()
    opts[b"dir"] = os.fsencode(addon_dir)
    opts[b"parent"] = os.fsencode(os.path.dirname(addon_dir))
    opts[b"addon_id"] = os.fsencode(ADDON_ID)
    opts[b"ticks"] = 10
    opts[b"search_bases"] = runtime.table()
    dirs = []
    for root, subdirs, _files in os.walk(addon_dir):
        for sub in subdirs:
            rel = os.path.relpath(os.path.join(root, sub), os.path.dirname(addon_dir))
            dirs.append(os.fsencode(rel))
    opts[b"dirs"] = runtime.table(*dirs)
    opts[b"deps"] = runtime.table()
    result = host[b"run"](opts)
    ok = bool(result[b"ok"])
    failures = []
    report = host[b"skillReport"]
    if report is not None:
        raw_failures = report[b"failures"]
        for i in range(1, len(raw_failures) + 1):
            failures.append(str(raw_failures[i]))
    phase = str(result[b"phase"] or "")
    checks_done = int(report[b"checks"]) if report is not None else 0
    print("%s: %s (%d checks, phase %r)" % (name, "PASS" if ok and not failures else "FAIL",
                                            checks_done, phase))
    for item in failures:
        print("   FAIL:", item)
    return ok and not failures


def main():
    buff_count, skill_count = asset_checks()

    os.makedirs(SCRATCH_ROOT, exist_ok=True)
    addon_dir = os.path.join(SCRATCH_ROOT, ADDON_ID)
    copy_addon(addon_dir)
    patch_main(addon_dir)
    merged = run_lua_case("loader with buff_dump + skill_dump", addon_dir,
                          buff_count + skill_count, True)

    legacy_dir = os.path.join(SCRATCH_ROOT, "legacy", ADDON_ID)
    copy_addon(legacy_dir)
    os.remove(os.path.join(legacy_dir, "skill_dump.tbl"))
    patch_main(legacy_dir)
    legacy = run_lua_case("loader with buff_dump only (legacy)", legacy_dir,
                          buff_count, False)

    if failures:
        print("RESULT: FAIL — %d asset check(s)" % len(failures))
        for item in failures[:40]:
            print("   ", item)
        return 1
    if not (merged and legacy):
        print("RESULT: FAIL — Lua loader/search checks failed")
        return 1
    print("RESULT: PASS — assets + merged loader + legacy fallback")
    return 0


if __name__ == "__main__":
    sys.exit(main())
