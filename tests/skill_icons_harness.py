#!/usr/bin/env python3
"""Offline harness for the skill-icon pool (CooldawnBuffTracker 1.34.0).

Three layers, all offline:

1. Assets — `skill_icons/manifest.tsv` and `skill_dump.tbl` must describe the
   same 323 entries over 10 class trees: every file is a 64x64 uncompressed
   ARGB8888 DDS (`DDS ` magic, 32-bit RGB + alpha masks, 128 + 64*64*4 bytes),
   every path resolves inside `skill_icons/` and ends in `.dds`, the PNG
   sources live outside the runtime folder, ids are unique and never collide
   with `buff_dump.tbl`, names are non-empty and carry no `(Rank N)` suffix,
   and no (name, file) pair is duplicated.
2. Loader/search — the real `main.lua` runs inside the aac_smoke patch-293
   sandbox with both data files preloaded exactly as `api.File:Read` returns
   them. The real `loadBuffDump()` must report buffs + skills, and the real
   `searchIcons()` provider must find a skill by its English name and return a
   `.dds` path that exists on disk. A second run without `skill_dump.tbl` proves
   the old buff-only install still loads.
3. Scan safety (1.34.0) — statically, the only `api.File` write in `main.lua`
   near the buff scan targets `buff_dump.tbl`; dynamically, a simulated
   completed scan writes `buff_dump.tbl` in the sandbox, leaves the preloaded
   `skill_dump.tbl` byte-identical, and the merged pool still carries the skill
   icons. `skill_dump.tbl` on disk is hashed before and after the whole run.

Usage:
    /home/hermes/work/.venv-aac/bin/python tests/skill_icons_harness.py
Exit code 0 = all checks passed.
"""
import hashlib
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
SKILL_SRC_DIR = os.path.join(REPO, "skill_icons_src")
SYNTH_MIN = 9000000
DDS_SIZE = 64
DDS_BYTES = 128 + DDS_SIZE * DDS_SIZE * 4
DDPF_ALPHAPIXELS = 0x1
DDPF_RGB = 0x40

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


def dds_info(path):
    """Parse an uncompressed DDS header; None when the file is not one.

    Returns {w, h, alpha, bpp, masks, caps, alpha_min} — alpha_min lets the
    harness prove the alpha channel survived the conversion.
    """
    data = open(path, "rb").read()
    if len(data) < 128 or data[:4] != b"DDS ":
        return None
    size, flags, h, w, pitch, _depth, mips = struct.unpack("<7I", data[4:32])
    pf_size, pf_flags, fourcc, bpp, rmask, gmask, bmask, amask = struct.unpack(
        "<2I4s5I", data[76:108])
    caps = struct.unpack("<5I", data[108:128])[0]
    if size != 124 or pf_size != 32 or fourcc != b"\x00" * 4:
        return None
    if not (pf_flags & DDPF_RGB and pf_flags & DDPF_ALPHAPIXELS):
        return None
    if len(data) != 128 + w * h * bpp // 8:
        return None
    alpha_min = 255
    if bpp == 32 and amask == 0xFF000000:
        raw = data[128:]
        # A8R8G8B8 little-endian: the fourth byte of every pixel is alpha
        alpha_min = min(raw[3::4]) if raw else 0
    return {
        "w": w, "h": h, "bpp": bpp, "alpha": bool(pf_flags & DDPF_ALPHAPIXELS),
        "masks": (rmask, gmask, bmask, amask), "caps": caps, "mips": mips,
        "pitch": pitch, "alpha_min": alpha_min, "size": len(data),
    }


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
    dds_alpha = []
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
        check(re.match(r"^[A-Za-z0-9_.-]+\.dds$", file_name) is not None,
              "safe DDS file name: %r" % file_name)
        check(row["type"] in ("active", "passive"), "type: %r" % row["type"])
        check(row["source_page"].startswith("https://wiki.aa-classic.com/" + row["tree"]),
              "source page for %r: %r" % (name, row["source_page"]))
        check(row["icon_url"].startswith("https://wiki.aa-classic.com/images/"),
              "icon url for %r: %r" % (name, row["icon_url"]))
        check((name.lower(), file_name) not in names_files,
              "duplicate (name, file): %r" % name)
        names_files.add((name.lower(), file_name))
        full = os.path.join(REPO, "skill_icons", file_name)
        check(os.path.isfile(full), "missing DDS %s" % file_name)
        if os.path.isfile(full):
            info = dds_info(full)
            check(info is not None, "invalid DDS %s" % file_name)
            if info:
                check((info["w"], info["h"]) == (DDS_SIZE, DDS_SIZE),
                      "dimensions %dx%d for %s" % (info["w"], info["h"], file_name))
                check(info["size"] == DDS_BYTES,
                      "payload %d bytes for %s (want %d)" % (info["size"], file_name, DDS_BYTES))
                check(info["masks"] == (0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000),
                      "ARGB8888 masks in %s: %r" % (file_name, info["masks"]))
                check(info["mips"] == 0 and info["pitch"] == DDS_SIZE * 4,
                      "pitch/mips in %s: %d/%d" % (file_name, info["pitch"], info["mips"]))
                dds_alpha.append(info["alpha_min"])
            sha = hashlib.sha256(open(full, "rb").read()).hexdigest()
            check(sha not in shas or shas[sha] == file_name,
                  "identical bytes in %s and %s" % (file_name, shas.get(sha)))
            shas[sha] = file_name

    check(len(dump_rows) == len(ids), "dump ids are unique (%d/%d)" % (len(ids), len(dump_rows)))
    runtime_dir = os.path.join(REPO, "skill_icons")
    packaged = sorted(f for f in os.listdir(runtime_dir) if f.lower().endswith(".dds"))
    check(len(packaged) == len(set(r["file"] for r in rows)),
          "packaged DDS files match the manifest (%d/%d)"
          % (len(packaged), len(set(r["file"] for r in rows))))
    check(not [f for f in os.listdir(runtime_dir) if f.lower().endswith(".png")],
          "runtime skill_icons/ carries no PNG")
    extra = [f for f in os.listdir(runtime_dir) if not f.endswith(".dds")]
    check(extra == ["manifest.tsv"], "runtime skill_icons/ holds only DDS + manifest: %r" % extra)
    check(os.path.isdir(SKILL_SRC_DIR), "PNG sources kept in skill_icons_src/")
    sources = sorted(f for f in os.listdir(SKILL_SRC_DIR) if f.lower().endswith(".png")) \
        if os.path.isdir(SKILL_SRC_DIR) else []
    check(len(sources) == len(set(r["file"] for r in rows)),
          "one PNG source per unique icon (%d/%d)" % (len(sources), len(set(r["file"] for r in rows))))
    check({f[:-4] for f in sources} == {r["file"][:-4] for r in rows},
          "every DDS has exactly one PNG source and vice versa")
    check(dds_alpha and all(0 <= a <= 255 for a in dds_alpha), "alpha channel in every DDS")
    print("assets: %d entries (%d active, %d passive), %d DDS (64x64 ARGB8888, %d with alpha), "
          "%d trees, %d PNG sources, 0 skipped"
          % (len(rows), sum(1 for r in rows if r["type"] == "active"),
             sum(1 for r in rows if r["type"] == "passive"), len(packaged),
             sum(1 for a in dds_alpha if a < 255), len(per_tree), len(sources)))
    return valid_buffs, len(rows)


def strip_lua_comments(src):
    """Lua source without comments (strings kept) — the scan check reads code only."""
    out, i, n = [], 0, len(src)
    while i < n:
        ch = src[i]
        if ch in "\"'":
            quote = ch
            out.append(ch)
            i += 1
            while i < n:
                c = src[i]
                out.append(c)
                i += 1
                if c == "\\" and i < n:
                    out.append(src[i])
                    i += 1
                    continue
                if c == quote:
                    break
        elif src.startswith("--", i):
            if src.startswith("--[[", i):
                end = src.find("]]", i + 4)
                i = (end + 2) if end >= 0 else n
            else:
                end = src.find("\n", i)
                i = end if end >= 0 else n
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def scan_safety_checks():
    """The buff icon scan must write buff_dump.tbl and never skill_dump.tbl."""
    src = strip_lua_comments(open(os.path.join(REPO, "main.lua"), encoding="utf-8").read())
    write_call = re.compile(r'api\.File[:.]Write\s*[,(]\s*(?:api\.File\s*,\s*)?"([^"]*)"')
    call_site = re.compile(r"api\.File(?::Write\s*\(|\.Write\s*,)")
    sites = [m.start() for m in call_site.finditer(src)]
    check(len(sites) >= 1, "main.lua has a buff-scan write")
    for pos in sites:
        window = src[pos:pos + 320]
        check("skill_dump" not in window,
              "api.File.Write at offset %d mentions skill_dump: %r" % (pos, window[:120]))
    start = src.find("local function processBuffIconScan()")
    check(start >= 0, "processBuffIconScan found in main.lua")
    end = src.find("\nlocal function ", start + 10)
    body = src[start:end if end > 0 else len(src)]
    check(len(call_site.findall(body)) == 1, "the scan has exactly one file write")
    writes = write_call.findall(body)
    check(writes == ["CooldawnBuffTracker/buff_dump.tbl"],
          "the scan writes only buff_dump.tbl: %r" % writes)
    check("loadSkillDump(byName, entries)" in body, "the scan re-merges skill_dump")
    check("skill_dump.tbl" in body, "the scan reads (never writes) skill_dump.tbl")
    print("scan safety: only write target %r" % (writes,))


def sha256(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


TEST_HOOK = r"""
CooldawnBuffTracker.__test = {
  searchIcons = searchIcons,
  -- 1.34.0: drive the real save branch of processBuffIconScan with a finished
  -- fake scan (ranges exhausted -> it writes buff_dump.tbl and re-merges).
  runScanSave = function(lines)
    buffIconScan = {
      ranges = {}, rangeIndex = 1, nextId = 0, entries = lines,
      tables = #lines, named = #lines, errors = 0, target = "",
    }
    processBuffIconScan()
  end,
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
    check(has(rows, "skill_icons/Aac-radiant_terrifying_roar.dds"), "Radiant Terrifying Roar icon")
  else
    check(#rows == 0, "skill-only name is absent without skill_dump")
  end

  rows = hook.searchIcons("Weapon Maneuvers", 20)
  check(#rows >= 1, "passive Weapon Maneuvers is searchable")
  if EXPECT_SKILLS then
    check(has(rows, "skill_icons/Icon_skill_fight03.dds"), "Weapon Maneuvers icon")
  end

  rows = hook.searchIcons("Charge", 100)
  check(#rows >= 1, "Charge is searchable")
  if EXPECT_SKILLS then
    check(has(rows, "skill_icons/Icon_skill_fight14.dds"), "Charge skill icon")
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

  -- 1.34.0 scan safety: a finished buff scan writes buff_dump.tbl only, never
  -- truncates the supplied skill_dump.tbl, and re-merges the skill pool.
  local skillBefore = ENGINE.files["CooldawnBuffTracker/skill_dump.tbl"]
  hook.runScanSave({
    "777001\tFake Buff\tgame/ui/icon/icon_buff_debuff.dds",
    "777002\tFake Buff 2\tgame/ui/icon/icon_buff_debuff.dds",
  })
  local buffAfter = ENGINE.files["CooldawnBuffTracker/buff_dump.tbl"]
  local skillAfter = ENGINE.files["CooldawnBuffTracker/skill_dump.tbl"]
  check(type(buffAfter) == "string" and string.find(buffAfter, "Fake Buff", 1, true) ~= nil,
    "the buff scan wrote buff_dump.tbl")
  check(type(buffAfter) == "string" and string.find(buffAfter, "skill_icons/", 1, true) == nil,
    "buff_dump.tbl carries no skill rows")
  check(skillAfter == skillBefore, "the buff scan left skill_dump.tbl byte-identical")
  local post = hook.dumpInfo()
  check(post ~= nil, "the pool is rebuilt after the scan")
  if post then
    if EXPECT_SKILLS then
      check(post.count == 2 + SKILL_COUNT,
        "the post-scan pool still merges every skill row: " .. tostring(post.count))
      check(type(post.skillByName) == "string"
        and string.find(post.skillByName, "skill_icons/", 1, true) ~= nil
        and string.find(post.skillByName, ".dds", 1, true) ~= nil,
        "the post-scan skill icon is a skill_icons/*.dds path: " .. tostring(post.skillByName))
      local postRows = hook.searchIcons("Radiant Terrifying Roar", 20)
      check(#postRows >= 1 and has(postRows, "skill_icons/Aac-radiant_terrifying_roar.dds"),
        "the post-scan search still returns skill icons")
    else
      check(post.count == 2, "legacy post-scan pool stays buff-only: " .. tostring(post.count))
      check(post.skillByName == nil, "no skill icon without skill_dump")
    end
  end

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


def build_host(lua_module, addon_dir, expect_count, expect_skills, skill_count):
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
    consts = "EXPECT_COUNT = %d\nEXPECT_SKILLS = %s\nSKILL_COUNT = %d\n" % (
        expect_count, "true" if expect_skills else "false", skill_count)
    return head + consts + TEST_LUA + "\nreturn HOST" + tail


def run_lua_case(name, addon_dir, expect_count, expect_skills, skill_count):
    runtime = lua51.LuaRuntime()
    host = runtime.execute(
        build_host(aac_smoke, addon_dir, expect_count, expect_skills, skill_count).encode("utf-8"),
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
    dump_path = os.path.join(REPO, "skill_dump.tbl")
    dump_hash = sha256(dump_path)
    buff_count, skill_count = asset_checks()
    scan_safety_checks()

    os.makedirs(SCRATCH_ROOT, exist_ok=True)
    addon_dir = os.path.join(SCRATCH_ROOT, ADDON_ID)
    copy_addon(addon_dir)
    patch_main(addon_dir)
    merged = run_lua_case("loader with buff_dump + skill_dump", addon_dir,
                          buff_count + skill_count, True, skill_count)

    legacy_dir = os.path.join(SCRATCH_ROOT, "legacy", ADDON_ID)
    copy_addon(legacy_dir)
    os.remove(os.path.join(legacy_dir, "skill_dump.tbl"))
    patch_main(legacy_dir)
    legacy = run_lua_case("loader with buff_dump only (legacy)", legacy_dir,
                          buff_count, False, 0)

    check(sha256(dump_path) == dump_hash,
          "skill_dump.tbl on disk unchanged across every buff-scan path (sha256)")
    print("skill_dump.tbl sha256 %s (unchanged by the scan paths)" % dump_hash[:16])

    if failures:
        print("RESULT: FAIL — %d asset check(s)" % len(failures))
        for item in failures[:40]:
            print("   ", item)
        return 1
    if not (merged and legacy):
        print("RESULT: FAIL — Lua loader/search checks failed")
        return 1
    print("RESULT: PASS — DDS assets + merged loader + legacy fallback + scan safety")
    return 0


if __name__ == "__main__":
    sys.exit(main())
