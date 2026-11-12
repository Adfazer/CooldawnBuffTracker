-- Effective cooldowns for the TARGET panel (1.21.0).
--
-- Model: eff = max(0, base - sumFlat) * (1 - sumPct / 100); percentages add up.
-- Base CD comes from the entry (custom/override), otherwise from skillsets.tbl.
-- Skillset passives are NEVER applied by default: they are snapping candidates for
-- per-target learning (a tree ratio is applied after 2 consistent observations).
-- Visible buffs (Battle Focus R2/R3, 9000610, Rhythm, Mana Fountain, Inspired,
-- Exploitation) apply only while the aura is on the target and revert when it fades.
-- Reset procs (Deflect and Retaliate 2611, Quick Recovery by name) are handled apart
-- from the ratio: they make the tree's timers ready.
--
-- All game data lives in flat, user-editable tables next to the addon:
--   classes.tbl    className <tab> tree1 <tab> tree2 <tab> tree3
--   skillsets.tbl  skillName <tab> tree <tab> baseCD(s) <tab> kind <tab> iconFile
--   cdmods.tbl     id <tab> name <tab> scope <tab> skill <tab> pct <tab> flat <tab>
--                  pctPerStack <tab> flatPerStack <tab> maxStacks <tab> effect <tab> icdMs
local api = require("api")

local M = {}

local ADDON_ID = "CooldawnBuffTracker"
local CLASSES_PATH = "CooldawnBuffTracker/classes.tbl"
local SKILLS_PATH = "CooldawnBuffTracker/skillsets.tbl"
local MODS_PATH = "CooldawnBuffTracker/cdmods.tbl"

local TTL_MS = 30 * 60 * 1000   -- learned state expires 30 min after the target was last seen
local SNAP_TOL = 0.04           -- candidate ratio tolerance
local MIN_OBS = 2               -- consistent observations before a ratio applies to the whole tree
local PASSIVE_CAP = 90          -- summed percentages never exceed this

local PLACEHOLDER_ICON = "game/ui/icon/icon_buff_debuff.dds"
local ICON_ROOT = "game/ui/icon/"

local classes = {}     -- [normalizedName] = { name =, trees = { ... } }
local skills = {}      -- [normalizedName] = { name, tree, cds = {..}, kind, icon }
local byTree = {}      -- [tree] = array of skill records (CD > 0), sorted by name
local treeOrder = {}   -- canonical order: first appearance in skillsets.tbl
local mods = {}        -- array of modifier rows
local candidates = {}  -- { { ratio =, label = }, ... } sorted ascending

local learned = {}     -- [targetKey] = per-target state
local active = {}      -- [targetKey] = dynamic modifier list for the current tick
local prevAura = {}    -- [targetKey] = { [modKey] = true }
local lastReset = {}   -- [targetKey] = { [modKey] = ms }

local auraNameCache = {}  -- [buffId] = resolved name (name-based modifiers only)
local logFn = nil
local nameOfFn = nil
local dumpIconFn = nil

local function log(msg)
  if logFn then logFn(msg) end
end

local function currentMs()
  local ok, ms = pcall(function() return api.Time:GetUiMsec() end)
  if ok and tonumber(ms) then return tonumber(ms) end
  return 0
end

local function normalize(s)
  return tostring(s or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function getSettings()
  local ok, s = pcall(function() return api.GetSettings(ADDON_ID) end)
  if ok and type(s) == "table" then return s end
  return nil
end

local function splitTabs(line)
  local out = {}
  local start = 1
  while true do
    local pos = string.find(line, "\t", start, true)
    if not pos then
      out[#out + 1] = string.sub(line, start)
      break
    end
    out[#out + 1] = string.sub(line, start, pos - 1)
    start = pos + 1
  end
  return out
end

local function readTable(path)
  if not (api.File and api.File.Read) then return nil end
  local ok, data = pcall(api.File.Read, api.File, path)
  if ok and type(data) == "table" and type(data.dump) == "string" and #data.dump > 0 then
    return data.dump
  end
  return nil
end

local function parseCdList(text)
  local out = {}
  for v in tostring(text or ""):gmatch("[^,%s]+") do
    local n = tonumber(v)
    if n and n > 0 then out[#out + 1] = n end
  end
  return out
end

local function iconPath(file)
  file = tostring(file or ""):gsub("\\", "/")
  file = file:gsub("^%s+", ""):gsub("%s+$", "")
  if file == "" then return nil end
  if file:find("/", 1, true) then return file end
  return ICON_ROOT .. file
end

-- Загружает/перезагружает все таблицы. Возвращает сводку для лога.
function M.LoadTables()
  classes, skills, byTree, treeOrder, mods, candidates = {}, {}, {}, {}, {}, {}
  auraNameCache = {}

  local classDump = readTable(CLASSES_PATH) or readTable("classes.tbl")
  local classCount = 0
  if classDump then
    for line in classDump:gmatch("[^\r\n]+") do
      if line ~= "" and string.sub(line, 1, 1) ~= "#" then
        local p = splitTabs(line)
        local name = p[1]
        if name and name ~= "" then
          local trees = {}
          for i = 2, 4 do
            if p[i] and p[i] ~= "" then trees[#trees + 1] = p[i] end
          end
          classes[normalize(name)] = { name = name, trees = trees }
          classCount = classCount + 1
        end
      end
    end
  end

  local skillDump = readTable(SKILLS_PATH) or readTable("skillsets.tbl")
  local skillCount = 0
  if skillDump then
    for line in skillDump:gmatch("[^\r\n]+") do
      if line ~= "" and string.sub(line, 1, 1) ~= "#" then
        local p = splitTabs(line)
        local name, tree = p[1], p[2]
        local cds = parseCdList(p[3])
        local kind = (p[4] and p[4] ~= "") and p[4] or "skill"
        local icon = iconPath(p[5])
        if name and name ~= "" then
          local rec = { name = name, tree = tree or "", cds = cds, kind = kind, cd = cds[1] }
          -- иконки: колонка таблицы, затем дамп баффов по имени, затем заглушка
          local key = normalize(name)
          if not icon and dumpIconFn then
            local ok, p2 = pcall(dumpIconFn, name)
            if ok and type(p2) == "string" and p2 ~= "" then icon = iconPath(p2) end
          end
          rec.icon = icon or PLACEHOLDER_ICON
          local prev = skills[key]
          -- одноимённые навыки разных ветвей: первая строка задаёт lookup по имени
          if not prev then skills[key] = rec end
          if rec.tree ~= "" and #cds > 0 and kind ~= "passive" then
            local list = byTree[rec.tree]
            if not list then
              list = {}
              byTree[rec.tree] = list
              treeOrder[#treeOrder + 1] = rec.tree
            end
            list[#list + 1] = rec
          end
          skillCount = skillCount + 1
        end
      end
    end
  end
  for _, list in pairs(byTree) do
    table.sort(list, function(a, b)
      local x, y = normalize(a.name), normalize(b.name)
      if x == y then return tostring(a.tree) < tostring(b.tree) end
      return x < y
    end)
  end

  local modDump = readTable(MODS_PATH) or readTable("cdmods.tbl")
  local modCount = 0
  if modDump then
    for line in modDump:gmatch("[^\r\n]+") do
      if line ~= "" and string.sub(line, 1, 1) ~= "#" then
        local p = splitTabs(line)
        local mod = {
          id = tonumber(p[1]) or 0,
          name = p[2] or "",
          scope = p[3] or "",
          skill = p[4] or "",
          pct = tonumber(p[5]) or 0,
          flat = tonumber(p[6]) or 0,
          pctPerStack = tonumber(p[7]) or 0,
          flatPerStack = tonumber(p[8]) or 0,
          maxStacks = tonumber(p[9]) or 0,
          effect = (p[10] and p[10] ~= "") and p[10] or "dynamic",
          icdMs = tonumber(p[11]) or 0,
        }
        mods[#mods + 1] = mod
        modCount = modCount + 1
      end
    end
  end

  -- Кандидаты для обучения: известные пассивки + готовые комбинации.
  local seen = {}
  for _, mod in ipairs(mods) do
    if mod.effect == "passive" or mod.effect == "snap" then
      local ratio = 1 - mod.pct / 100
      local key = string.format("%.3f", ratio)
      if ratio > 0 and not seen[key] then
        seen[key] = true
        candidates[#candidates + 1] = { ratio = ratio, label = mod.name, pct = mod.pct }
      end
    end
  end
  table.sort(candidates, function(a, b) return a.ratio < b.ratio end)

  M.SyncPermanentEntries()
  log(string.format("[CBT] effCD data: %d classes, %d skills, %d mods, %d candidates",
    classCount, skillCount, modCount, #candidates))
  return classCount, skillCount, modCount
end

function M.Initialize(opts)
  opts = opts or {}
  logFn = opts.log
  nameOfFn = opts.nameOf
  dumpIconFn = opts.dumpIcon
  M.LoadTables()
end

function M.IsEnabled()
  local s = getSettings()
  return (s ~= nil) and (s.effectiveCd == true)
end

function M.TreeList()
  if #treeOrder > 0 then return treeOrder end
  return { "Battlerage", "Witchcraft", "Defense", "Auramancy", "Occultism",
    "Archery", "Sorcery", "Shadowplay", "Songcraft", "Vitalism" }
end

function M.SkillsForTree(tree)
  return byTree[tostring(tree or "")] or {}
end

function M.SkillInfo(name)
  local rec = skills[normalize(name)]
  if not rec then return nil end
  return { name = rec.name, tree = rec.tree, cd = rec.cds[1], cds = rec.cds,
    kind = rec.kind, icon = rec.icon }
end

local function resolve(desc)
  if type(desc) ~= "table" then return nil end
  local key = normalize(desc.spell)
  local rec = (key ~= "") and skills[key] or nil
  if not rec then
    key = normalize(desc.name)
    if key ~= "" then rec = skills[key] end
  end
  return rec
end

function M.TreeOf(desc)
  if type(desc) ~= "table" then return nil end
  if desc.tree and desc.tree ~= "" then return desc.tree end
  local rec = resolve(desc)
  return rec and rec.tree or nil
end

local function stateFor(targetKey, now)
  local key = tostring(targetKey)
  local st = learned[key]
  if st and now and st.lastSeen and (now - st.lastSeen) > TTL_MS then
    learned[key] = nil
    active[key] = nil
    prevAura[key] = nil
    lastReset[key] = nil
    st = nil
  end
  if not st then
    st = {
      key = key,
      lastSeen = now or 0,
      classCheckedAt = 0,
      className = nil,
      classTrees = nil,
      obsTrees = {},
      treeRatio = {},
      buffRatio = {},
    }
    learned[key] = st
  end
  if now and now > (st.lastSeen or 0) then st.lastSeen = now end
  return st
end

-- Деревья цели по классу (GetUnitClassName + classes.tbl). nil, если класс неизвестен
-- (мобы отдают "Pending"); вызывающий код тогда опирается на обучение/наблюдённые ветви.
local function classTrees(st)
  if st.classTrees then return st.classTrees end
  local now = currentMs()
  if st.classCheckedAt and (now - st.classCheckedAt) < 5000 then return nil end
  st.classCheckedAt = now
  local okId, curId = pcall(function() return api.Unit:GetUnitId("target") end)
  if not okId or not curId or tostring(curId) ~= st.key then return nil end
  local ok, cls = pcall(function() return api.Ability:GetUnitClassName("target") end)
  if ok and type(cls) == "string" and cls ~= "" and normalize(cls) ~= "pending" then
    local c = classes[normalize(cls)]
    if c then
      st.className = c.name
      st.classTrees = c.trees
      return c.trees
    end
  end
  return nil
end

local function treeAllowed(st, tree)
  if not tree or tree == "" then return false end
  local trees = st.classTrees
  if not trees or #trees == 0 then return true end
  for _, t in ipairs(trees) do
    if normalize(t) == normalize(tree) then return true end
  end
  return false
end

local function skillMatches(mod, desc)
  if not mod.skill or mod.skill == "" then return true end
  local want = normalize(mod.skill)
  return normalize(desc.spell) == want or normalize(desc.name) == want
end

-- Сумма видимых динамических модификаторов для цели/ветви/навыка.
local function sumDynamic(targetKey, tree, desc, st)
  local pct, flat = 0, 0
  local list = active[targetKey]
  if not list then return 0, 0 end
  local allowed = treeAllowed(st, tree)
  for _, a in ipairs(list) do
    local mod = a.mod
    local scope = mod.scope
    local scopeOk
    if not scope or scope == "" or normalize(scope) == "all" then
      scopeOk = true
    else
      scopeOk = (tree ~= nil) and (normalize(scope) == normalize(tree)) and allowed
    end
    if scopeOk and skillMatches(mod, desc) then
      pct = pct + (a.pct or 0)
      flat = flat + (a.flat or 0)
    end
  end
  return pct, flat
end

local function effectiveBase(desc, rec)
  local base = tonumber(desc.cd) or 0
  if desc.custom then
    -- запись создана пользователем: её CD авторитетен, 0 = без кулдауна
    return base
  end
  if rec and rec.cds and rec.cds[1] and rec.cds[1] > 0 then
    return rec.cds[1]
  end
  return base
end

-- Возвращает effCd, info{ base, flat, pct, tree, cls, learned }.
-- targetId — id юнита-цели (sourceId из боевого лога), forClass — читать класс с "target".
function M.Effective(desc, targetId, now)
  if type(desc) ~= "table" then return nil end
  now = now or currentMs()
  local st = stateFor(tostring(targetId), now)
  classTrees(st)
  local rec = resolve(desc)
  local base = effectiveBase(desc, rec)
  local tree = M.TreeOf(desc)
  local pct, flat = 0, 0
  local learnedPct = 0

  if tree and tree ~= "" then st.obsTrees[tree] = true end

  -- Выученный коэффициент: для конкретного навыка — сразу, для ветви — после 2 совпадений.
  if tree and tree ~= "" and base > 0 then
    local br = st.buffRatio[tostring(desc.id)]
    local tr = st.treeRatio[normalize(tree)]
    if br then
      learnedPct = (1 - br.ratio) * 100
    elseif tr and tr.ready then
      learnedPct = (1 - tr.ratio) * 100
    end
    pct = pct + learnedPct
  end

  local dpct, dflat = sumDynamic(tostring(targetId), tree, desc, st)
  pct = pct + dpct
  flat = flat + dflat
  if pct < 0 then pct = 0 end
  if pct > PASSIVE_CAP then pct = PASSIVE_CAP end

  local sec = base - flat
  if sec < 0 then sec = 0 end
  local eff = sec * (1 - pct / 100)
  if eff < 0 then eff = 0 end
  return eff, { base = base, flat = flat, pct = pct, tree = tree,
    cls = st.className, learned = learnedPct, skill = rec and rec.name or nil }
end

-- Полный опрос аур цели. auras: { [tostring(buffId)] = { stack = n } }.
-- Возвращает массив сбросов: { { tree =, name =, id = }, ... }.
function M.OnTargetAuras(targetId, auras, now)
  if not M.IsEnabled() then
    active = {}
    return nil
  end
  now = now or currentMs()
  local key = tostring(targetId)
  local st = stateFor(key, now)
  local list = {}
  local present = {}
  local resets = nil
  auras = auras or {}

  local function auraName(id)
    local nm = auraNameCache[id]
    if nm == nil then
      local numId = tonumber(id) or id
      local ok, v = pcall(function() return nameOfFn and nameOfFn(numId) end)
      nm = (ok and type(v) == "string") and v or ""
      auraNameCache[id] = nm
    end
    return nm
  end

  for _, mod in ipairs(mods) do
    if mod.effect == "dynamic" or mod.effect == "reset" then
      local found, stacks = false, 1
      if mod.id and mod.id > 0 then
        -- известный id: сопоставляем только по нему, иначе две строки одного
        -- баффа (R2/R3) сработали бы обе на одну ауру
        local a = auras[tostring(mod.id)]
        if a then found = true; stacks = tonumber(a.stack) or 1 end
      elseif mod.name ~= "" then
        -- id неизвестен: ищем по имени (Quick Recovery, Rhythm, Inspired, ...)
        for id, a in pairs(auras) do
          if normalize(auraName(id)) == normalize(mod.name) then
            found = true
            stacks = tonumber(a and a.stack) or 1
            break
          end
        end
      end
      if found then
        local maxS = tonumber(mod.maxStacks) or 0
        if maxS > 0 and stacks > maxS then stacks = maxS end
        if stacks < 1 then stacks = 1 end
        local mkey = tostring(mod.id) .. "|" .. mod.name .. "|" .. tostring(mod.skill)
        present[mkey] = true
        if mod.effect == "dynamic" then
          list[#list + 1] = {
            mod = mod,
            stacks = stacks,
            pct = (mod.pct or 0) + (mod.pctPerStack or 0) * stacks,
            flat = (mod.flat or 0) + (mod.flatPerStack or 0) * stacks,
          }
        else
          local isNew = (prevAura[key] == nil) or (prevAura[key][mkey] ~= true)
          local icd = tonumber(mod.icdMs) or 0
          local lr = lastReset[key] and lastReset[key][mkey] or nil
          local fresh = (lr == nil) or (icd <= 0) or ((now - lr) >= icd)
          if isNew and fresh then
            resets = resets or {}
            resets[#resets + 1] = { tree = mod.scope, name = mod.name, id = mod.id }
            if not lastReset[key] then lastReset[key] = {} end
            lastReset[key][mkey] = now
            log(string.format("[CBT] effCD: reset proc %s (%s) tree=%s target=%s",
              tostring(mod.name), tostring(mod.id), tostring(mod.scope), key))
          end
        end
      end
    end
  end

  prevAura[key] = present
  active[key] = list
  st.lastSeen = now
  return resets
end

local function nearestCandidate(ratio)
  local best, bestDist = nil, nil
  for _, c in ipairs(candidates) do
    local d = math.abs(c.ratio - ratio)
    if bestDist == nil or d < bestDist then best, bestDist = c, d end
  end
  return best, bestDist
end

-- Наблюдение повторного применения навыка: intervalSec — фактический интервал.
-- Возвращает "obs"|"reset"|"up"|"skip", ветвь, применённый коэффициент.
function M.Observe(desc, targetId, intervalSec, now)
  if not M.IsEnabled() or type(desc) ~= "table" then return nil end
  now = now or currentMs()
  local rec = resolve(desc)
  local kind = desc.kind or (rec and rec.kind)
  if kind == "repeat-growth" or kind == "charges" then
    log("[CBT] effCD: learn skip (" .. tostring(kind) .. ") " .. tostring(desc.name))
    return "skip", nil, nil
  end
  local base = effectiveBase(desc, rec)
  if base <= 1 or not intervalSec or intervalSec <= 0 then return nil end
  local raw = intervalSec / base
  if raw > 1.05 then return "up", nil, raw end

  local key = tostring(targetId)
  local st = stateFor(key, now)
  classTrees(st)
  local tree = M.TreeOf(desc)

  -- Убираем из наблюдения динамику, действовавшую в момент каста.
  local dpct = sumDynamic(key, tree, desc, st)
  local factor = 1 - dpct / 100
  if factor < 0.1 then factor = 0.1 end
  local passive = raw / factor
  if passive > 1.05 then return "up", nil, passive end

  local cand, dist = nearestCandidate(passive)
  if passive < 0.5 and (not cand or dist > SNAP_TOL) then
    -- слишком раннее повторное применение без объяснения — это сброс, не CDR
    return "reset", tree, passive
  end

  local use = passive
  if cand and dist <= SNAP_TOL then use = cand.ratio end

  local bkey = tostring(desc.id)
  local br = st.buffRatio[bkey]
  if br and math.abs(br.ratio - use) <= 0.02 then
    br.count = br.count + 1
  else
    br = { ratio = use, count = 1 }
    st.buffRatio[bkey] = br
  end

  if tree and tree ~= "" then
    local tkey = normalize(tree)
    local tr = st.treeRatio[tkey]
    if tr and math.abs(tr.ratio - use) <= 0.02 then
      tr.count = tr.count + 1
    else
      tr = { ratio = use, count = 1, ready = false }
      st.treeRatio[tkey] = tr
    end
    tr.ready = (tr.count >= MIN_OBS)
    st.obsTrees[tree] = true
    log(string.format("[CBT] effCD: obs %s raw=%.3f passive=%.3f use=%.3f %s=%.3f n=%d %s target=%s",
      tostring(desc.name), raw, passive, use, tostring(tree), tr.ratio, tr.count,
      tr.ready and "active" or "pending", key))
  else
    log(string.format("[CBT] effCD: obs %s raw=%.3f use=%.3f tree=? n=%d target=%s",
      tostring(desc.name), raw, use, br.count, key))
  end
  return "obs", tree, use
end

function M.ResetLearning()
  local n = 0
  for _ in pairs(learned) do n = n + 1 end
  learned = {}
  active = {}
  prevAura = {}
  lastReset = {}
  log("[CBT] effCD: learning reset for " .. tostring(n) .. " target(s)")
  return n
end

function M.LearnedCount()
  local n = 0
  for _ in pairs(learned) do n = n + 1 end
  return n
end

function M.DataPath()
  return SKILLS_PATH
end

-- Перманентные записи пикера: CD/иконка/ветвь всегда из skillsets.tbl.
function M.SyncPermanentEntries()
  local s = getSettings()
  if not s or type(s.customBuffs) ~= "table" then return 0 end
  local changed = 0
  for _, cb in ipairs(s.customBuffs) do
    if type(cb) == "table" and cb.permanent then
      local rec = resolve({ id = cb.id, name = cb.name, spell = cb.spellName, tree = cb.tree })
      if rec then
        if rec.cds[1] and tonumber(cb.cooldown) ~= rec.cds[1] then
          cb.cooldown = rec.cds[1]
          changed = changed + 1
        end
        if rec.tree ~= "" and cb.tree ~= rec.tree then
          cb.tree = rec.tree
          changed = changed + 1
        end
        if rec.icon and rec.icon ~= "" and cb.iconFile ~= rec.icon then
          cb.iconFile = rec.icon
          changed = changed + 1
        end
      end
    end
  end
  if changed > 0 then
    pcall(function() api.SaveSettings() end)
    log("[CBT] effCD: permanent entries refreshed from skillsets.tbl (" .. tostring(changed) .. ")")
  end
  return changed
end

return M
