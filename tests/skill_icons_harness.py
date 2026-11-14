#!/usr/bin/env python3
"""Offline harness for the skill-icon pool (CooldawnBuffTracker 1.35.0).

Four layers, all offline:

1. Assets — `skill_icons/manifest.tsv` and `skill_dump.tbl` must describe the
   same 323 entries over 10 class trees and reference the **PNG** pool
   (`../../Addon/CooldawnBuffTracker/skill_icons/<name>.png`). Every unique icon
   is a real PNG in `skill_icons/` (magic + IHDR parsed, square, 28/48/64 px),
   byte-identical to its source in `skill_icons_src/`, and still has its 64x64
   DDS copy next to it as the native fallback. Ids are unique and never collide
   with `buff_dump.tbl`; no (name, file) pair is duplicated.
2. Loader/search — the real `main.lua` runs inside the aac_smoke patch-293
   sandbox with both data files preloaded exactly as `api.File:Read` returns
   them. The real `loadBuffDump()` must report buffs + skills, and the real
   `searchIcons()` provider must find a skill by its English name and return a
   `.png` path that exists on disk. A second run without `skill_dump.tbl` proves
   the old buff-only install still loads.
3. Scan safety — statically, the only `api.File` write in `main.lua` near the
   buff scan targets `buff_dump.tbl`; dynamically, a simulated completed scan
   writes `buff_dump.tbl` in the sandbox, leaves the preloaded `skill_dump.tbl`
   byte-identical, and the merged pool still carries the skill icons.
   `skill_dump.tbl` on disk is hashed before and after the whole run.
4. Icon painting (1.35.0) — `CbtIcon.Paint` must draw a skill PNG on an
   ImageDrawable with `SetTgaTexture` (the client's loose-PNG path), not through
   `F_SLOT.SetIconBackGround`, and must leave normal game icons on the native
   path. Asserted against the mock widget layer: layer `artwork`, 1 px anchors
   on both corners, shown after a successful load, the dump-relative PNG path
   tried first, the `api.baseDir` forms present as candidates, one drawable per
   slot with no `SetTgaTexture` calls on repaints, no per-frame creation, and a
   native `.dds` fallback plus exactly one chat warning when nothing loads.

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
SKILL_LIVE_DIR = os.path.join(REPO, "skill_icons")
SYNTH_MIN = 9000000
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
PNG_SIDES = (28, 48, 64)
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


def png_info(path):
    """Parse the PNG signature + IHDR; None when the file is not a PNG."""
    data = open(path, "rb").read()
    if len(data) < 33 or data[:8] != PNG_MAGIC:
        return None
    if data[12:16] != b"IHDR":
        return None
    width, height = struct.unpack(">II", data[16:24])
    return {
        "w": width, "h": height, "depth": data[24], "color": data[25],
        "size": len(data),
    }


def dds_info(path):
    """Parse an uncompressed DDS header; None when the file is not one."""
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
    return {
        "w": w, "h": h, "bpp": bpp, "masks": (rmask, gmask, bmask, amask),
        "caps": caps, "mips": mips, "pitch": pitch, "size": len(data),
    }


def asset_checks():
    manifest_path = os.path.join(SKILL_LIVE_DIR, "manifest.tsv")
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

    ids, names_files = set(), set()
    folders = set()
    manifest_by_key = {(r["skill_id"], r["name"], r["file"]) for r in rows}
    dump_keys = set()
    for row in dump_rows:
        check(row[2].startswith(SKILL_PREFIX),
              "dump path is the addon-folder PNG pool: %r" % row[2])
        check(row[2].endswith(".png"), "dump path ends in .png: %r" % row[2])
        folders.add(row[2].rsplit("/", 1)[0] + "/")
        dump_keys.add((row[0], row[1], row[2].replace(SKILL_PREFIX, "")))
    check(folders == {SKILL_PREFIX}, "every dump path lives in one folder: %r" % sorted(folders))
    check(manifest_by_key == dump_keys, "manifest and dump describe the same entries")

    for row in rows:
        rid, name, file_name = row["skill_id"], row["name"], row["file"]
        check(rid.isdigit(), "numeric id: %r" % rid)
        if not rid.isdigit():
            continue
        rid = int(rid)
        check(rid not in ids, "duplicate id %d" % rid)
        ids.add(rid)
        check(rid not in buff_ids, "id %d collides with buff_dump" % rid)
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
        check(row["icon_url"].endswith(".png"), "wiki source is a PNG for %r" % name)
        check((name.lower(), file_name) not in names_files,
              "duplicate (name, file): %r" % name)
        names_files.add((name.lower(), file_name))

    unique_files = sorted({r["file"] for r in rows})
    check(len(unique_files) == len({r["file"][:-4] for r in rows}), "one file per unique icon")

    png_sides = {}
    dds_files = []
    for file_name in unique_files:
        full = os.path.join(SKILL_LIVE_DIR, file_name)
        check(os.path.isfile(full), "missing PNG %s" % file_name)
        info = png_info(full) if os.path.isfile(full) else None
        check(info is not None, "invalid PNG %s" % file_name)
        if info:
            check(info["w"] == info["h"] and info["w"] in PNG_SIDES,
                  "dimensions %dx%d for %s" % (info["w"], info["h"], file_name))
            check(info["depth"] == 8, "8-bit channel depth in %s" % file_name)
            check(info["color"] in (2, 6), "RGB/RGBA colour type in %s (%r)"
                  % (file_name, info["color"]))
            check(info["size"] > 100, "PNG payload %d bytes in %s" % (info["size"], file_name))
            png_sides[info["w"]] = png_sides.get(info["w"], 0) + 1
        dds = os.path.join(SKILL_LIVE_DIR, file_name[:-4] + ".dds")
        check(os.path.isfile(dds), "native DDS fallback missing for %s" % file_name)
        dds_info_value = dds_info(dds) if os.path.isfile(dds) else None
        check(dds_info_value is not None, "invalid DDS fallback for %s" % file_name)
        if dds_info_value:
            check((dds_info_value["w"], dds_info_value["h"]) == (DDS_SIZE, DDS_SIZE),
                  "fallback DDS is 64x64 for %s" % file_name)
            check(dds_info_value["size"] == DDS_BYTES,
                  "fallback DDS payload for %s" % file_name)
            dds_files.append(file_name)

    check(len(dump_rows) == len(ids), "dump ids are unique (%d/%d)" % (len(ids), len(dump_rows)))
    packaged_png = sorted(f for f in os.listdir(SKILL_LIVE_DIR) if f.lower().endswith(".png"))
    packaged_dds = sorted(f for f in os.listdir(SKILL_LIVE_DIR) if f.lower().endswith(".dds"))
    check(packaged_png == unique_files,
          "packaged PNG files match the manifest (%d/%d)" % (len(packaged_png), len(unique_files)))
    check(len(packaged_dds) == len(unique_files),
          "one DDS fallback per PNG (%d/%d)" % (len(packaged_dds), len(unique_files)))
    extra = [f for f in os.listdir(SKILL_LIVE_DIR)
             if not f.endswith(".png") and not f.endswith(".dds")]
    check(extra == ["manifest.tsv"], "runtime skill_icons/ holds PNG + DDS + manifest: %r" % extra)

    check(os.path.isdir(SKILL_SRC_DIR), "PNG sources kept in skill_icons_src/")
    sources = sorted(f for f in os.listdir(SKILL_SRC_DIR) if f.lower().endswith(".png")) \
        if os.path.isdir(SKILL_SRC_DIR) else []
    check(sources == unique_files,
          "the source folder mirrors the runtime PNG pool (%d/%d)" % (len(sources), len(unique_files)))
    identical = 0
    for file_name in sources:
        live = os.path.join(SKILL_LIVE_DIR, file_name)
        src = os.path.join(SKILL_SRC_DIR, file_name)
        if os.path.isfile(live) and hashlib.sha256(open(live, "rb").read()).digest() == \
                hashlib.sha256(open(src, "rb").read()).digest():
            identical += 1
    check(identical == len(sources),
          "runtime PNGs are byte-identical to the sources (%d/%d)" % (identical, len(sources)))

    print("assets: %d entries (%d active, %d passive), %d unique PNG (%s px), %d DDS fallbacks, "
          "%d trees, 0 skipped"
          % (len(rows), sum(1 for r in rows if r["type"] == "active"),
             sum(1 for r in rows if r["type"] == "passive"), len(unique_files),
             ", ".join("%d:%d" % (k, v) for k, v in sorted(png_sides.items())),
             len(dds_files), len(per_tree)))
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
    write_call = re.compile(r'api\.File[:.]Write\s*[,(]\s*(?:api\.File\s*,\s*)?\"([^\"]*)\"')
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
  -- 1.35.0: the icon painter, so the harness can drive the real slot path.
  icon = CbtIcon,
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
-- 1.35.0: F_SLOT is handed to the addon behind a ReadOnlyLib proxy that caches
-- one wrapper per method name, so patching the field from inside a phase is
-- invisible after the first call. Install the recorder at chunk scope instead:
-- it runs before the addon is imported, forwards to the real method, and only
-- records while the paint checks are running.
local ICON_WRAP = { calls = {}, active = false }
do
  local realSetIcon = F_SLOT.SetIconBackGround
  F_SLOT.SetIconBackGround = function(button, path)
    if ICON_WRAP.active then
      ICON_WRAP.calls[#ICON_WRAP.calls + 1] = { button = button, path = path }
    end
    return realSetIcon(button, path)
  end
end

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
        and string.find(info.skillByName, "skill_icons/", 1, true) ~= nil
        and string.find(info.skillByName, ".png", 1, true) ~= nil,
        "skill name resolves to a PNG in skill_dump: " .. tostring(info.skillByName))
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

  ---------------------------------------------------------------------------
  -- 1.35.0 scan safety: a finished buff scan writes buff_dump.tbl only, never
  -- truncates the supplied skill_dump.tbl, and re-merges the skill pool.
  ---------------------------------------------------------------------------
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
        and string.find(post.skillByName, ".png", 1, true) ~= nil,
        "the post-scan skill icon is a skill_icons/*.png path: " .. tostring(post.skillByName))
      local postRows = hook.searchIcons("Radiant Terrifying Roar", 20)
      check(#postRows >= 1 and has(postRows, "skill_icons/Aac-radiant_terrifying_roar.png"),
        "the post-scan search still returns skill icons")
    else
      check(post.count == 2, "legacy post-scan pool stays buff-only: " .. tostring(post.count))
      check(post.skillByName == nil, "no skill icon without skill_dump")
    end
  end

  ---------------------------------------------------------------------------
  -- 1.35.0 painting: skill PNGs go on an ImageDrawable via SetTgaTexture, the
  -- native F_SLOT path stays for every other icon, and nothing is created or
  -- reloaded on repaint.
  ---------------------------------------------------------------------------
  local CbtIcon = hook.icon
  check(type(CbtIcon) == "table" and type(CbtIcon.Paint) == "function",
    "CbtIcon.Paint is exported through main.lua")

  local realImage = METHODS.CreateImageDrawable
  local realTga = METHODS.SetTgaTexture
  local realAnchor = METHODS.AddAnchor
  local realInfo = api.Log.Info

  ICON_WRAP.calls = {}
  ICON_WRAP.active = true
  local iconCalls = ICON_WRAP.calls

  local created = {}
  METHODS.CreateImageDrawable = function(w, path, layer)
    local d = realImage(w, path, layer)
    created[#created + 1] = { owner = w, path = path, layer = layer, drawable = d }
    return d
  end

  local tga, anchors = {}, {}
  local tgaFail = 0
  METHODS.SetTgaTexture = function(w, path)
    local list = tga[w]
    if not list then list = {}; tga[w] = list end
    list[#list + 1] = path
    if tgaFail > 0 and #list <= tgaFail then return false end
    w._tgaPath = path
    return w
  end
  METHODS.AddAnchor = function(w, point, target, x, y)
    local list = anchors[w]
    if not list then list = {}; anchors[w] = list end
    list[#list + 1] = { point = point, target = target, x = x, y = y }
    return realAnchor(w, point, target, x, y)
  end

  local chat = {}
  api.Log.Info = function(_, line)
    chat[#chat + 1] = tostring(line)
    return nil
  end

  local function newSlot(id)
    return api.Interface:CreateWidget("button", id, nil)
  end
  local function tgaList(d)
    return (d and tga[d]) or {}
  end
  local function lastIconCall()
    return iconCalls[#iconCalls]
  end

  -- skill_icons/<name>.png is the pool the client now records.
  local skillPath = "../Addon/CooldawnBuffTracker/skill_icons/Icon_skill_fight02.png"
  check(CbtIcon.SkillFile(skillPath) == "Icon_skill_fight02",
    "dump path recognised as a skill icon: " .. tostring(CbtIcon.SkillFile(skillPath)))
  check(CbtIcon.SkillFile("game/ui/icon/icon_buff_debuff.dds") == nil,
    "game icons are not skill icons")
  check(CbtIcon.SkillFile(nil) == nil and CbtIcon.SkillFile("") == nil,
    "nil/empty paths are not skill icons")
  check(CbtIcon.SkillFile("../Addon/CooldawnBuffTracker/skill_icons/Foo.DDS") == "Foo",
    "uppercase DDS extension still recognised (name without extension)")

  local slot = newSlot("cbtPaintSlot1")
  local painted = CbtIcon.Paint(slot, skillPath)
  local d = slot._cbtSkillIcon
  check(painted == true, "Paint returns true for a skill icon")
  check(d ~= nil, "the PNG drawable is created and cached on the slot")
  check(#created == 1 and created[1].owner == slot,
    "exactly one drawable was created for the slot (" .. tostring(#created) .. ")")
  check(d ~= nil and d._name == "artwork",
    "layer is artwork (above the slot background, below the HUD overlay): " .. tostring(d and d._name))
  check(d ~= nil and d._texturePath == "Textures/Defaults/White.dds",
    "drawable is seeded with the white texture: " .. tostring(d and d._texturePath))
  local alist = (d and anchors[d]) or {}
  check(#alist == 2, "the overlay has two anchors: " .. tostring(#alist))
  check(#alist == 2 and alist[1].point == "TOPLEFT" and alist[1].x == 1 and alist[1].y == 1,
    "TOPLEFT anchor with a 1 px inset")
  check(#alist == 2 and alist[2].point == "BOTTOMRIGHT" and alist[2].x == -1 and alist[2].y == -1,
    "BOTTOMRIGHT anchor with a 1 px inset")
  check(d ~= nil and d._visible == true, "the overlay is shown after the PNG loads")
  local firstTga = tgaList(d)[1]
  check(firstTga == skillPath,
    "first SetTgaTexture call uses the dump-relative PNG: " .. tostring(firstTga))
  check(lastIconCall() ~= nil and lastIconCall().path == nil,
    "the slot background is cleared so the PNG is not doubled")

  -- repaint: same drawable, no texture churn
  local childrenBefore, tgaBefore = #slot._children, #tgaList(d)
  local stillPainted = true
  for _ = 1, 30 do
    if CbtIcon.Paint(slot, skillPath) ~= true then stillPainted = false end
  end
  check(stillPainted, "30 repaints keep returning true")
  check(#slot._children == childrenBefore, "30 repaints create no new drawable")
  check(#tgaList(d) == tgaBefore, "30 repaints issue no SetTgaTexture call")
  check(#created == 1, "still exactly one drawable after the repaints: " .. tostring(#created))

  -- a second slot: the api.baseDir candidates are the fallback forms
  local slot2 = newSlot("cbtPaintSlot2")
  tgaFail = 2
  local painted2 = CbtIcon.Paint(slot2, skillPath)
  tgaFail = 0
  local d2 = slot2._cbtSkillIcon
  local list2 = tgaList(d2)
  check(painted2 == true, "Paint still succeeds when the first candidates fail")
  check(list2[1] == skillPath, "candidate 1 is the dump-relative path: " .. tostring(list2[1]))
  check(list2[2] == api.baseDir .. "/CooldawnBuffTracker/skill_icons/Icon_skill_fight02.png",
    "candidate 2 is api.baseDir + addon folder: " .. tostring(list2[2]))
  check(list2[3] == api.baseDir .. "/skill_icons/Icon_skill_fight02.png",
    "candidate 3 is api.baseDir + /skill_icons/ (the literal form): " .. tostring(list2[3]))
  check(list2[4] == nil, "no fourth candidate: " .. tostring(list2[4]))

  -- bare relative form is recognised too
  local slot3 = newSlot("cbtPaintSlot3")
  local painted3 = CbtIcon.Paint(slot3, "skill_icons/Icon_skill_fight01.png")
  check(painted3 == true, "a bare skill_icons/... path is painted")
  check(tgaList(slot3._cbtSkillIcon)[1]
    == "../Addon/CooldawnBuffTracker/skill_icons/Icon_skill_fight01.png",
    "a bare path gets the addon-relative prefix: " .. tostring(tgaList(slot3._cbtSkillIcon)[1]))

  -- normal game icon: native path, overlay hidden
  local painted4 = CbtIcon.Paint(slot, "game/ui/icon/icon_buff_debuff.dds")
  check(painted4 == false, "a game icon returns false")
  check(slot._cbtSkillIconShown == false or slot._cbtSkillIconShown == nil,
    "the PNG overlay is hidden for a game icon")
  check(d ~= nil and d._visible == false, "the drawable itself is visible=false")
  check(lastIconCall() ~= nil and lastIconCall().path == "game/ui/icon/icon_buff_debuff.dds",
    "F_SLOT.SetIconBackGround keeps the normal path: " .. tostring(lastIconCall() and lastIconCall().path))
  CbtIcon.Paint(slot, nil)
  check(lastIconCall() ~= nil and lastIconCall().path == nil,
    "a nil icon still clears through F_SLOT")

  -- back to a skill icon re-shows the same drawable
  local repainted = CbtIcon.Paint(slot, skillPath)
  check(repainted == true and d._visible == true, "the same slot re-shows its skill icon")
  check(#created == 3, "no extra drawable was created on the re-show: " .. tostring(#created))

  -- failure: no candidate loads -> native DDS fallback + exactly one warning
  local slot4 = newSlot("cbtPaintSlot4")
  tgaFail = 99
  local painted5 = CbtIcon.Paint(slot4, "../Addon/CooldawnBuffTracker/skill_icons/Icon_skill_fight03.png")
  tgaFail = 0
  check(painted5 == false, "a failed PNG load returns false")
  check(slot4._cbtSkillIconShown == false, "the overlay stays hidden after a failed load")
  check(slot4._cbtSkillIcon ~= nil and slot4._cbtSkillIcon._visible == false,
    "the drawable is hidden after a failed load")
  local fallback = lastIconCall() and lastIconCall().path or ""
  check(fallback == api.baseDir .. "/CooldawnBuffTracker/skill_icons/Icon_skill_fight03.dds",
    "falls back to the native 64x64 DDS path: " .. tostring(fallback))
  local warned, warnCount = false, 0
  for _, line in ipairs(chat) do
    if string.find(line, "skill icon paint failed", 1, true) then
      warned = true
      warnCount = warnCount + 1
    end
  end
  check(warned, "a chat warning reports the failed PNG load")
  CbtIcon.Paint(slot4, "../Addon/CooldawnBuffTracker/skill_icons/Icon_skill_fight04.png")
  local warnCount2 = 0
  for _, line in ipairs(chat) do
    if string.find(line, "skill icon paint failed", 1, true) then warnCount2 = warnCount2 + 1 end
  end
  check(warnCount2 == warnCount, "only one warning per session (" .. tostring(warnCount2) .. ")")

  -- no per-frame work: repaints and UPDATE ticks leave the slot untouched
  local slot5 = newSlot("cbtPaintSlot5")
  CbtIcon.Paint(slot5, skillPath)
  local kids = #slot5._children
  local tgaSlot5 = #tgaList(slot5._cbtSkillIcon)
  for _ = 1, 50 do CbtIcon.Paint(slot5, skillPath) end
  for _ = 1, 5 do tick(50) end
  check(#slot5._children == kids, "50 repaints + 5 UPDATE frames create no drawable on the slot")
  check(#tgaList(slot5._cbtSkillIcon) == tgaSlot5,
    "50 repaints + 5 UPDATE frames issue no SetTgaTexture call")

  ---------------------------------------------------------------------------
  -- restore every stub: the update / OnSettingToggle / reload phases follow
  ---------------------------------------------------------------------------
  ICON_WRAP.active = false
  METHODS.CreateImageDrawable = realImage
  METHODS.SetTgaTexture = realTga
  METHODS.AddAnchor = realAnchor
  api.Log.Info = realInfo

  HOST.skillReport = { checks = checks, failures = failures, paintDrawables = #created }
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
    drawables = int(report[b"paintDrawables"]) if report is not None else 0
    print("%s: %s (%d checks, %d drawables, phase %r)"
          % (name, "PASS" if ok and not failures else "FAIL", checks_done, drawables, phase))
    for item in failures:
        print("   FAIL:", item)
    if not ok and not failures:
        message = str(result[b"message"] or "")
        hint = str(result[b"hint"] or "")
        print("   error:", message)
        if hint:
            print("   hint :", hint)
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
        print("RESULT: FAIL — Lua loader/search/paint checks failed")
        return 1
    print("RESULT: PASS — PNG assets + merged loader + legacy fallback + scan safety "
          "+ PNG overlay painting")
    return 0


if __name__ == "__main__":
    sys.exit(main())
