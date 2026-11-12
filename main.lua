local api = require("api")
local BuffList = require("CooldawnBuffTracker/buff_helper")
local BuffsToTrack = require("CooldawnBuffTracker/buffs_to_track")
local helpers = require("CooldawnBuffTracker/helpers")
local settingsPage = require("CooldawnBuffTracker/settings_page")
local BuffDebugger = require("CooldawnBuffTracker/buff_debugger")
local EffectiveCD = require("CooldawnBuffTracker/effective_cd")
local EffectivePicker = require("CooldawnBuffTracker/effective_cd_window")

-- Declare variables for caching buff states (add to the beginning of file after other variables)
local cachedMountBuffs = {}
local cachedPlayerBuffs = {}
local cachedBuffStatus = {}

-- Target tracking variables
local targetBuffData = {}
local currentTargetId = nil
local lastTargetCleanupTime = 0
local targetCleanupInterval = 60 -- Check every 60 seconds

-- Cache for storing buff states of different targets
-- Format: targetCache[targetId] = { lastSeen = timestamp, buffStates = { [buffId] = { fixedTime, status, timeOfAction, cooldown } } }
local targetCache = {}

-- Last displayed target data (for showing cached data when target is lost)
local lastDisplayedTargetId = nil
local lastTargetLostTime = nil  -- Time when target was lost
local cachedTargetDisplayData = {}  -- Buff data to display when target is lost

-- Хранит баффы, которые когда-либо были активны на каждой цели
-- Format: targetActiveBuffs[targetId] = { [buffId] = true }
local targetActiveBuffs = {}

-- Function to get a list of tracked buffs from settings
local function getTrackedBuffsFromSettings(unitType)
  local settings = api.GetSettings("CooldawnBuffTracker") or {}
  local trackedBuffs = {}

  if settings[unitType] and settings[unitType].trackedBuffs then
    trackedBuffs = settings[unitType].trackedBuffs
  end

  return trackedBuffs
end

-- Replacement for BuffsToTrack if module not loaded
if not BuffsToTrack then
  BuffsToTrack = {
    ShouldTrackBuff = function(id, unitType)
      local trackedBuffs = getTrackedBuffsFromSettings(unitType)
      for _, buffId in ipairs(trackedBuffs) do
        if buffId == id then
          return true
        end
      end
      return false
    end,
    GetAllTrackedBuffIds = function(unitType)
      return getTrackedBuffsFromSettings(unitType)
    end
  }
  api.Log:Info("[CBT] Failed to load buffs_to_track.lua, using settings")
end

if not BuffList then
  BuffList = {
    GetBuffName = function(id) return "Buff #" .. id end,
    GetBuffIcon = function(id) return nil end,
    GetBuffCooldown = function(id) return 0 end,
    GetBuffTimeOfAction = function(id) return 0 end
  }
  api.Log:Info("[CBT] Failed to load buff_helper.lua, using placeholder")
end

local CooldawnBuffTracker = {
  name = "Cooldown Buff Tracker",
  author = "Adfazer & Claude",
  desc = "Addon for tracking buffs",
  version = "1.21.1"
}

-- Simplified logging function that only logs during initialization
local function safeLog(message)
  if api and api.Log and api.Log.Info then
    api.Log:Info(message)
  end
end

local buffData = {}
local playerBuffData = {}
-- Модель 1.20: N канвасов на каждый тип юнита. unitCanvases[unitType][i] —
-- живой виджет i-го канваса; раскладка лежит в settings[unitType].canvases[i].
local unitCanvases = { playerpet = {}, player = {}, target = {} }
local UNIT_TYPES = { "playerpet", "player", "target" }
local CANVAS_BASE_ID = {
  playerpet = "MountBuffCanvas",
  player = "PlayerBuffCanvas",
  target = "TargetBuffCanvas"
}
local updateTimer = 0
local refreshUITimer = 0
local updateInterval = 50
local refreshUIInterval = 50
local iconSize = 40
local iconSpacing = 5
local defaultPositionX = 330
local defaultPositionY = 30
local targetCacheCleanupTimer = 0

local ICON_COLORS = {
  READY = {1, 1, 1, 1},          -- White (unchanged)
  ACTIVE = {0.2, 1, 0.2, 1},     -- Brighter green
  COOLDOWN = {1, 0.2, 0.2, 1}    -- Brighter red
}

local settings = {}
-- api.Off в patch 293 не существует: после OnUnload гасим OnUpdate флагом
local live = false
-- Окно-приёмник боевого лога (для триггера по имени навыка)
local combatEventWnd = nil
-- Mirror: id буффа -> id цели, на которую он был «прикреплён» в момент появления
local mirrorTargetByBuff = {}


-- Компактное число для debug-строк (30, 21.5 — без хвостовых нулей)
local function fmtNum(v)
  v = tonumber(v) or 0
  if math.abs(v - math.floor(v + 0.5)) < 0.05 then
    return string.format("%.0f", v)
  end
  return string.format("%.2f", v)
end

local function formatTimerSeconds(seconds)
  if not seconds or seconds <= 0 then return "" end
  seconds = math.floor(seconds * 10 + 0.5) / 10
  if seconds > 3600 then
    return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), math.floor(seconds % 60))
  elseif seconds > 60 then
    return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
  elseif seconds >= 10 then
    return string.format("%d", math.floor(seconds))
  else
    return string.format("%.1f", seconds)
  end
end

local function getCurrentTime()
  local msTime = api.Time:GetUiMsec() or 0
  return msTime / 1000
end

-- Компактная подпись цвета {r,g,b,a} для сравнения раскладки
local function colorSignature(c)
  if type(c) ~= "table" then return "-" end
  return tostring(c.r) .. "," .. tostring(c.g) .. "," .. tostring(c.b) .. "," .. tostring(c.a)
end

-- Настройки пользовательского баффа по id (id может быть числом или строкой)
local function findCustomBuff(buffId)
  local s = settings or api.GetSettings("CooldawnBuffTracker") or {}
  local custom = s.customBuffs or {}
  local key = tostring(buffId)
  for _, cb in ipairs(custom) do
    if cb and cb.id ~= nil and tostring(cb.id) == key then
      return cb
    end
  end
  return nil
end

-- Поиск кастомного баффа по отображаемому имени/Spell (когда id не совпадает
-- с buff_id ауры: пользователь мог задать ключом имя навыка)
local function findCustomBuffByName(name)
  if not name or name == "" then return nil end
  local key = tostring(name):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local s = settings or api.GetSettings("CooldawnBuffTracker") or {}
  for _, cb in ipairs(s.customBuffs or {}) do
    local n = cb.name or cb.spellName
    if n and n ~= "" then
      local k = tostring(n):lower():gsub("^%s+", ""):gsub("%s+$", "")
      if k == key then return cb end
    end
  end
  return nil
end

-- Пользовательские CD/D для обычного баффа (settings.buffOverrides)
local function findBuffOverride(buffId)
  local s = settings or api.GetSettings("CooldawnBuffTracker") or {}
  local ov = s.buffOverrides
  if type(ov) ~= "table" then return nil end
  return ov[tostring(buffId)]
end

-- Применяет CD/D из override к живым записям и кэшам целей
local function applyBuffOverride(buffId, cd, toa)
  cd = tonumber(cd) or 0
  toa = tonumber(toa) or 0
  local tables = { buffData, playerBuffData, targetBuffData }
  for _, tbl in pairs(tables) do
    local e = tbl[buffId]
    if e then
      e.cooldown = cd
      e.timeOfAction = toa
      if e.fixedTime then
        e.readyAt = e.fixedTime + cd
        if not e.synthetic then
          e.activeUntil = e.fixedTime + toa
        end
      end
    end
  end
  for _, cache in pairs(targetCache) do
    local e = cache.buffStates and cache.buffStates[buffId]
    if e then
      e.cooldown = cd
      e.timeOfAction = toa
      if e.fixedTime then
        e.readyAt = e.fixedTime + cd
        e.activeUntil = e.fixedTime + toa
      end
    end
  end
end

-- Переносит CD/D/имя/иконку из customBuffs в уже созданные записи панелей
local function applyCustomBuffOverrides()
  if not settings or type(settings.customBuffs) ~= "table" then return end
  local count = 0
  for _ in ipairs(settings.customBuffs) do count = count + 1 end
  if count == 0 then return end
  local tables = { buffData, playerBuffData, targetBuffData }
  for _, tbl in pairs(tables) do
    for id, entry in pairs(tbl) do
      local cb = findCustomBuff(id) or findCustomBuffByName(entry.name)
      if cb then
        local cd = tonumber(cb.cooldown)
        if cd ~= nil and cd >= 0 then entry.cooldown = cd end
        local toa = tonumber(cb.timeOfAction)
        if toa ~= nil and toa >= 0 then entry.timeOfAction = toa end
        if cb.name and cb.name ~= "" then entry.name = cb.name end
        if cb.iconFile and cb.iconFile ~= "" then entry.icon = cb.iconFile end
        local ov = findBuffOverride(id)
        if ov then
          entry.cooldown = tonumber(ov.cooldown) or 0
          entry.timeOfAction = tonumber(ov.timeOfAction) or 0
        end
      end
    end
  end
end

-- ===== Effective cooldowns: дескриптор записи и сброс ветви (1.21.0) =====

-- Всё, что нужно модулю effective_cd, чтобы найти ветвь/базу/тип навыка.
local function effectiveDescriptor(buffId, name, cd, cb)
  local s = api.GetSettings("CooldawnBuffTracker") or settings or {}
  local ov = s.buffOverrides and s.buffOverrides[tostring(buffId)] or nil
  return {
    id = buffId,
    name = name or (cb and cb.name) or BuffList.GetBuffName(buffId),
    spell = cb and cb.spellName or nil,
    tree = (cb and cb.tree) or (ov and ov.tree) or nil,
    kind = cb and cb.kind or nil,
    cd = tonumber(cd) or 0,
    -- CD записи авторитетен только если он задан вручную (custom/override)
    custom = (cb ~= nil and tonumber(cb.cooldown or 0) > 0) or (ov ~= nil),
  }
end

-- Reset-прок ветви: все записи этой ветви становятся готовыми (таймеры не трогаем).
local function markTargetTreeReady(targetId, tree, reason)
  if not targetId or not tree or tree == "" then return 0 end
  local now = getCurrentTime()
  local count = 0

  local function clearTable(tbl)
    if type(tbl) ~= "table" then return end
    for buffId, rec in pairs(tbl) do
      if type(rec) == "table" then
        local cb = findCustomBuff(buffId)
        local desc = effectiveDescriptor(buffId, rec.name, rec.cooldown, cb)
        local recTree = EffectiveCD.TreeOf(desc)
        if recTree and string.lower(tostring(recTree)) == string.lower(tostring(tree)) then
          rec.status = "ready"
          rec.fixedTime = nil
          rec.activeUntil = nil
          rec.readyAt = now
          rec.missingCount = 0
          rec.effCooldown = nil
          rec.effInfo = nil
          count = count + 1
        end
      end
    end
  end

  clearTable(targetBuffData)
  clearTable(cachedTargetDisplayData)
  local cache = targetCache[targetId]
  if cache then clearTable(cache.buffStates) end

  if count > 0 then
    safeLog("[CBT] effCD: reset " .. tostring(tree) .. " timers=" .. tostring(count)
      .. " target=" .. tostring(targetId) .. (reason and (" (" .. tostring(reason) .. ")") or ""))
  end
  return count
end

local function initBuffData()
  -- Инициализируем данные для всех типов юнитов
  local unitTypes = {"playerpet", "player", "target"}

  for _, unitType in ipairs(unitTypes) do
    local buffDataTable
    if unitType == "target" then
      buffDataTable = targetBuffData
    elseif unitType == "player" then
      buffDataTable = playerBuffData
    else
      buffDataTable = buffData
    end
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds(unitType)

    -- Создаем таблицу для проверки существующих баффов
    local trackedBuffsMap = {}
    for _, buffId in ipairs(trackedBuffIds) do
      trackedBuffsMap[buffId] = true
    end

    -- Удаляем баффы, которые больше не отслеживаются
    for buffId in pairs(buffDataTable) do
      if not trackedBuffsMap[buffId] then
        -- Если бафф больше не отслеживается, удаляем его из данных
        buffDataTable[buffId] = nil
        safeLog("[CBT] " .. unitType .. " buff removed from tracking: " .. tostring(buffId))
      end
    end

    -- Добавляем новые баффы
    for _, buffId in ipairs(trackedBuffIds) do
      if not buffDataTable[buffId] then
        local customCfg = findCustomBuff(buffId) or findCustomBuffByName(BuffList.GetBuffName(buffId))
        local buffName, buffIcon, buffCooldown, buffTimeOfAction
        if customCfg then
          -- У кастомного баффа CD/D берём из его настроек (0 — допустимый CD)
          buffName = (customCfg.name and customCfg.name ~= "" and customCfg.name)
            or BuffList.GetBuffName(buffId)
          buffIcon = (customCfg.iconFile and customCfg.iconFile ~= "" and customCfg.iconFile)
            or BuffList.GetBuffIcon(buffId)
          buffCooldown = tonumber(customCfg.cooldown) or 0
          buffTimeOfAction = tonumber(customCfg.timeOfAction) or 0
        else
          buffName = BuffList.GetBuffName(buffId)
          buffIcon = BuffList.GetBuffIcon(buffId)
          buffCooldown = BuffList.GetBuffCooldown(buffId)
          buffTimeOfAction = BuffList.GetBuffTimeOfAction(buffId)

          if not buffCooldown or tonumber(buffCooldown) <= 0 then
            buffCooldown = 30
          end

          local toaNum = tonumber(buffTimeOfAction)
          -- 0 — допустимое значение (мгновенный бафф), дефолт только при мусоре/отрицательном
          if toaNum == nil or toaNum < 0 then
            buffTimeOfAction = 3
          end
        end

        local ov = findBuffOverride(buffId)
        if ov then
          buffCooldown = tonumber(ov.cooldown) or 0
          buffTimeOfAction = tonumber(ov.timeOfAction) or 0
        end

        buffDataTable[buffId] = {
          name = buffName,
          icon = buffIcon,
          cooldown = buffCooldown,
          timeOfAction = buffTimeOfAction,
          fixedTime = nil,
          status = "ready"
        }

        safeLog("[CBT] " .. unitType .. " buff added for tracking: " .. tostring(buffId) .. " (" .. tostring(buffName) .. ")")
      end
    end
  end

  -- Применяем CD/D/иконки кастомных баффов к уже существующим записям
  applyCustomBuffOverrides()
end

local function setBuffStatus(buffId, status, currentTime, unitType, remainingTime, anchorTime)
  unitType = unitType or "playerpet"  -- По умолчанию используем mount

  local buffDataTable
  if unitType == "target" then
    buffDataTable = targetBuffData
  elseif unitType == "player" then
    buffDataTable = playerBuffData
  else
    buffDataTable = buffData
  end

  -- If buff doesn't exist in table, create it first (for tracked buffs)
  if not buffDataTable[buffId] then
    local customCfg = findCustomBuff(buffId) or findCustomBuffByName(BuffList.GetBuffName(buffId))
    local buffName, buffIcon, buffCooldown, buffTimeOfAction
    if customCfg then
      buffName = (customCfg.name and customCfg.name ~= "" and customCfg.name)
        or BuffList.GetBuffName(buffId)
      buffIcon = (customCfg.iconFile and customCfg.iconFile ~= "" and customCfg.iconFile)
        or BuffList.GetBuffIcon(buffId)
      buffCooldown = tonumber(customCfg.cooldown) or 0
      buffTimeOfAction = tonumber(customCfg.timeOfAction) or 0
    else
      buffName = BuffList.GetBuffName(buffId)
      buffIcon = BuffList.GetBuffIcon(buffId)
      buffCooldown = BuffList.GetBuffCooldown(buffId)
      buffTimeOfAction = BuffList.GetBuffTimeOfAction(buffId)

      if not buffCooldown or tonumber(buffCooldown) <= 0 then
        buffCooldown = 30
      end

      local toaNum = tonumber(buffTimeOfAction)
      -- 0 — допустимое значение (мгновенный бафф), дефолт только при мусоре/отрицательном
      if toaNum == nil or toaNum < 0 then
        buffTimeOfAction = 3
      end
    end

    local ov = findBuffOverride(buffId)
    if ov then
      buffCooldown = tonumber(ov.cooldown) or 0
      buffTimeOfAction = tonumber(ov.timeOfAction) or 0
    end

    buffDataTable[buffId] = {
      name = buffName,
      icon = buffIcon,
      cooldown = buffCooldown,
      timeOfAction = buffTimeOfAction,
      fixedTime = nil,
      status = "ready"
    }
  end

  local buff = buffDataTable[buffId]
  local oldStatus = buff.status

  buff.status = status

  local timeOfAction = tonumber(buff.timeOfAction) or 0
  local cooldown = tonumber(buff.cooldown) or 0

  -- 1.21.0: эффективный КД только для панели Target. База остаётся в buff.cooldown
  -- (её видно в Edit), в readyAt уходит eff. Пересчитывается на каждой активации.
  local cdUsed = cooldown
  local effInfo = nil
  local isMirrored = settings and settings.target and settings.target.mirror
    and settings.target.mirror[tostring(buffId)]
  if unitType == "target" and settings and settings.effectiveCd and status == "active"
    and not isMirrored then
    local cbEff = findCustomBuff(buffId) or findCustomBuffByName(buff.name)
    local desc = effectiveDescriptor(buffId, buff.name, cooldown, cbEff)
    local targetKey = currentTargetId or api.Unit:GetUnitId("target")
    local eff, info = EffectiveCD.Effective(desc, targetKey)
    if eff and info then
      cdUsed = eff
      effInfo = info
    end
  end

  if status == "active" then
    if anchorTime then
      -- Явный якорь: начало каста навыка (SPELLCAST_START), а не момент ауры
      buff.fixedTime = anchorTime
      buff.activeUntil = anchorTime + timeOfAction
      buff.permanent = false
    elseif remainingTime ~= nil then
      -- remainingTime (мс) — серверный остаток баффа. Отсчёт ведём прямо от него,
      -- поэтому таймер не зависит от точности введённой длительности и одинаково
      -- работает для player, playerpet и target.
      local remainingSeconds = remainingTime / 1000
      -- Оценка момента старта: (настроенная длительность - остаток).
      -- Отрицательное значение = API-остаток больше настроенной длительности
      -- (устаревшие данные в customBuffs) — прижимаем к нулю, иначе readyAt уедет в будущее
      -- и после конца баффа появится фантомный кулдаун.
      local elapsed = timeOfAction - remainingSeconds
      if elapsed < 0 then
        elapsed = 0
      end
      buff.fixedTime = currentTime - elapsed
      -- Активная фаза ограничена длительностью из настроек: если API-остаток
      -- больше неё (долгая аура, а способность мгновенная), зелёная подсветка
      -- не висит всё время ауры.
      buff.activeUntil = buff.fixedTime + timeOfAction
      buff.permanent = false
    else
      -- API не отдаёт timeLeft (у предмета/навыка нет длительности):
      -- берём длительность из настроек, как в 1.5.0. Это важно для бафов вещей,
      -- у которых есть только навык с кулдауном и нет собственного таймера.
      buff.fixedTime = currentTime
      buff.activeUntil = currentTime + timeOfAction
      buff.permanent = false
    end
    buff.readyAt = buff.fixedTime + cdUsed
    -- Активная фаза (зелёный) всегда равна длительности баффа. Если кулдаун
    -- короче длительности (например CD=0), красной фазы просто нет — зелёный
    -- держится всю длительность, затем сразу ready.
    buff.missingCount = 0
  elseif status == "cooldown" and not buff.fixedTime then
    -- Если бафф переходит в состояние кулдауна, но fixedTime не установлено,
    -- устанавливаем текущее время как время начала кулдауна
    buff.fixedTime = currentTime
    buff.activeUntil = currentTime
    buff.readyAt = currentTime + cdUsed
  end

  -- Значение эффективного КД записи (Edit показывает базу, таймер — eff)
  buff.effCooldown = effInfo and cdUsed or nil
  buff.effInfo = effInfo
  if effInfo and settings and settings.debugBuffId then
    safeLog(string.format("[CBT] effCD: skill %s base=%s flat=%s pct=%s eff=%s tree=%s target=%s",
      tostring(buff.name), fmtNum(effInfo.base), fmtNum(effInfo.flat), fmtNum(effInfo.pct),
      fmtNum(cdUsed), tostring(effInfo.tree),
      tostring(effInfo.cls or currentTargetId or "?")))
  end

  buff.statusChangeTime = currentTime

  -- Диагностика таймингов (Debug: ON): видно, от какого момента считается КД
  if settings and settings.debugBuffId and oldStatus ~= buff.status then
    safeLog(string.format("[CBT] timer %s %s->%s now=%.2f D=%s CD=%s fixed=%s ready=%s rem=%s",
      tostring(buffId), tostring(oldStatus), tostring(buff.status),
      tonumber(currentTime) or 0, tostring(buff.timeOfAction), tostring(buff.cooldown),
      tostring(buff.fixedTime), tostring(buff.readyAt), tostring(remainingTime)))
  end
end

local function checkBuffStatus(buff, currentTime)
  if not buff or not buff.fixedTime then return "ready" end

  local fixedTime = tonumber(buff.fixedTime) or 0
  local timeOfAction = tonumber(buff.timeOfAction) or 0
  local cooldown = tonumber(buff.cooldown) or 0
  currentTime = tonumber(currentTime) or 0

  -- activeUntil может быть обрезан при досрочном снятии баффа (диспел/смерть);
  -- readyAt — момент готовности способности (старт баффа + кулдаун).
  local activeUntil = tonumber(buff.activeUntil) or (fixedTime + timeOfAction)
  local readyAt = tonumber(buff.readyAt) or (fixedTime + cooldown)

  if currentTime < activeUntil - 0.05 then
    return "active"
  elseif currentTime < readyAt - 0.05 then
    return "cooldown"
  else
    return "ready"
  end
end

-- ===== Триггеры навыков по боевому логу (враг ударил -> КД его навыка) =====
-- unitIdByName: имя (точно как в игре) -> id юнита (учим, когда берём цель в таргет)
-- pendingBySource: имя -> { [buffId] = время }, пока id игрока неизвестен
local unitIdByName = {}
local pendingBySource = {}

-- Журнал навыков из боевого лога (для окна Record)
local loggedSpellOrder = {}
local loggedSpellMap = {}

local function recordLoggedSpell(name, now)
  if not name or name == "" then return end
  local e = loggedSpellMap[name]
  if not e then
    e = { name = name, count = 0 }
    loggedSpellMap[name] = e
    loggedSpellOrder[#loggedSpellOrder + 1] = name
    if #loggedSpellOrder > 200 then
      local old = table.remove(loggedSpellOrder, 1)
      loggedSpellMap[old] = nil
    end
  end
  e.count = (e.count or 0) + 1
  e.last = now or getCurrentTime()
end
-- Анти-дребезг триггеров по боевому логу: DoT-тики не должны перезапускать КД
local lastTriggerTimes = {}
local myNameExact = nil   -- мой ник ровно как в игре (string.lower не работает с кириллицей)

-- Записать/обновить кулдаун навыка, применённого игроком sourceId
local function triggerTargetCooldown(sourceId, buffId, startedAt, now)
  if not sourceId or not buffId then return end
  now = now or getCurrentTime()
  startedAt = startedAt or now
  local cb = findCustomBuff(buffId)
  local toa, cd
  if cb then
    toa = tonumber(cb.timeOfAction) or 0
    cd = tonumber(cb.cooldown) or 0
  else
    toa = tonumber(BuffList.GetBuffTimeOfAction(buffId)) or 3
    cd = tonumber(BuffList.GetBuffCooldown(buffId)) or 30
  end
  -- устаревшее событие (кулдаун уже прошёл) не показываем
  if now - startedAt >= cd then return end

  -- Наблюдение фактического интервала повторного применения этого навыка
  -- (обучение коэффициентов ветви; сбросы ловятся отдельно от соотношения).
  local prevCache = targetCache[sourceId]
  local prevRec = prevCache and prevCache.buffStates and prevCache.buffStates[buffId]
  if prevRec and prevRec.fixedTime and settings and settings.effectiveCd then
    local interval = startedAt - (tonumber(prevRec.fixedTime) or startedAt)
    if interval > 1.5 then
      local obsDesc = effectiveDescriptor(buffId, BuffList.GetBuffName(buffId), cd, cb)
      local res, tree = EffectiveCD.Observe(obsDesc, sourceId, interval)
      if res == "reset" then
        markTargetTreeReady(sourceId, tree, string.format("early reuse %.1fs", interval))
      end
    end
  end

  -- Эффективный КД для цели (база записи остаётся в cooldown)
  local cdUsed = cd
  local effInfo = nil
  if settings and settings.effectiveCd and BuffsToTrack.ShouldTrackBuff(buffId, "target") then
    local desc = effectiveDescriptor(buffId, BuffList.GetBuffName(buffId), cd, cb)
    local eff, info = EffectiveCD.Effective(desc, sourceId)
    if eff and info then
      cdUsed = eff
      effInfo = info
    end
  end

  local rec = {
    fixedTime = startedAt,
    activeUntil = startedAt + toa,
    readyAt = startedAt + cdUsed,
    permanent = false,
    synthetic = true,   -- нет ауры: пропажа не должна обрывать активную фазу
    status = "active",
    missingCount = 0,
    timeOfAction = toa,
    cooldown = cd,
    effCooldown = effInfo and cdUsed or nil,
    effInfo = effInfo,
    name = BuffList.GetBuffName(buffId),
    icon = BuffList.GetBuffIcon(buffId)
  }
  if effInfo and settings and settings.debugBuffId then
    safeLog(string.format("[CBT] effCD: skill %s base=%s flat=%s pct=%s eff=%s tree=%s target=%s",
      tostring(rec.name), fmtNum(effInfo.base), fmtNum(effInfo.flat), fmtNum(effInfo.pct),
      fmtNum(cdUsed), tostring(effInfo.tree), tostring(effInfo.cls or sourceId or "?")))
  end

  local cache = targetCache[sourceId]
  if not cache then
    cache = { lastSeen = now, buffStates = {} }
    targetCache[sourceId] = cache
  end
  cache.lastSeen = now
  cache.buffStates[buffId] = rec

  if not targetActiveBuffs[sourceId] then
    targetActiveBuffs[sourceId] = {}
  end
  targetActiveBuffs[sourceId][buffId] = true

  -- если этот игрок — текущая цель, обновляем и «живую» таблицу
  if currentTargetId and tostring(currentTargetId) == tostring(sourceId) then
    targetBuffData[buffId] = {
      name = rec.name,
      icon = rec.icon,
      cooldown = cd,
      timeOfAction = toa,
      fixedTime = startedAt,
      activeUntil = startedAt + toa,
      readyAt = startedAt + cdUsed,
      permanent = false,
      synthetic = true,
      status = "active",
      effCooldown = effInfo and cdUsed or nil,
      effInfo = effInfo
    }
  end
end

-- Запомнить имя юнита (и применить отложенные триггеры для этого имени)
local function learnUnitName(unitId)
  if not unitId then return nil end
  local info = api.Unit:GetUnitInfoById(unitId)
  if not info or not info.name or info.name == "" then return nil end
  local key = info.name
  unitIdByName[key] = unitId

  local pending = pendingBySource[key]
  if pending then
    local now = getCurrentTime()
    for buffId, t in pairs(pending) do
      triggerTargetCooldown(unitId, buffId, t, now)
    end
    pendingBySource[key] = nil
  end

  return info.name, key
end

-- Сам применил навык (наш ник в источнике) -> запускаем свои панели
local function triggerSelfBuff(buffId, now)
  now = now or getCurrentTime()
  local tables = { player = playerBuffData, playerpet = buffData }
  local count = 0
  for unitType, tbl in pairs(tables) do
    if tbl[buffId] and BuffsToTrack.ShouldTrackBuff(buffId, unitType) then
      setBuffStatus(buffId, "active", now, unitType, nil)
      tbl[buffId].synthetic = true
      cachedBuffStatus[buffId] = "active"
      count = count + 1
    end
  end
  return count
end

-- Выучить иконку навыка по spellId из боевого лога (api.Skill:GetSkillTooltip).
-- Вызывается один раз на кастомный бафф; путь сохраняется в настройках (iconFile).
local function learnSkillIcon(cb, spellId)
  if not cb then return end
  if cb.iconFile and cb.iconFile ~= "" then return end
  if not spellId then
    if settings.debugBuffId then
      safeLog("[CBT] icon: no spellId in event for '" .. tostring(cb.id) .. "'")
    end
    return
  end
  local path, name = nil, nil
  local ok, info = pcall(function() return api.Skill:GetSkillTooltip(spellId) end)
  if ok and type(info) == "table" then
    path = info.path
    name = info.name
  end
  -- запасной путь: у некоторых "навыков" иконка отдаётся тултипом баффа
  if (not path or path == "") and api.Ability and api.Ability.GetBuffTooltip then
    local ok2, tip = pcall(function() return api.Ability:GetBuffTooltip(spellId) end)
    if ok2 and type(tip) == "table" then
      path = tip.path
      name = name or tip.name
    end
  end
  if settings.debugBuffId then
    local errText = ok and "" or (" err=" .. tostring(info))
    safeLog("[CBT] icon lookup id=" .. tostring(spellId)
      .. " -> path=" .. tostring(path) .. " name=" .. tostring(name) .. errText)
  end
  if not path or path == "" then
    return
  end
  cb.iconFile = info and info.path or path
  -- обновить живые записи и кэш целей, чтобы иконка сменилась сразу
  local tables = { buffData, playerBuffData, targetBuffData }
  for _, tbl in pairs(tables) do
    local entry = tbl[cb.id]
    if entry then entry.icon = path end
  end
  for _, cache in pairs(targetCache) do
    if cache.buffStates and cache.buffStates[cb.id] then
      cache.buffStates[cb.id].icon = path
    end
  end
  pcall(function() api.SaveSettings() end)
  safeLog("[CBT] icon learned for spell " .. tostring(spellId) .. ": " .. tostring(path))
end

-- Имя навыка из лога -> запуск/обновление таймера у виновника
local function triggerSpell(spellName, sourceName, spellId, rawArgs, combatEvent)
  if not spellName or spellName == "" then return end
  local s = api.GetSettings("CooldawnBuffTracker") or {}
  local custom = s.customBuffs or {}
  if #custom == 0 then return end

  local needle = spellName
  local srcKey = (sourceName and sourceName ~= "") and sourceName or nil
  local now = getCurrentTime()

  if srcKey and not myNameExact then
    local myName = learnUnitName(api.Unit:GetUnitId("player"))
    if myName then myNameExact = myName end
  end

  for _, cb in ipairs(custom) do
    local trigger = cb.spellName
    if trigger and trigger ~= "" and trigger == needle and cb.id then
      if settings.debugBuffId and rawArgs then
        local parts = {}
        for i = 1, 14 do
          parts[#parts + 1] = tostring(i) .. "=" .. tostring(rawArgs[i])
        end
        safeLog("[CBT] " .. tostring(combatEvent) .. " args: " .. table.concat(parts, " "))
        safeLog("[CBT] parsed: spellId=" .. tostring(spellId)
          .. " spellName=" .. tostring(spellName))
      end
      learnSkillIcon(cb, spellId)

      local isSelf = (srcKey and myNameExact and srcKey == myNameExact) and true or false
      local sourceId = nil
      if isSelf then
        sourceId = api.Unit:GetUnitId("player")
      elseif srcKey then
        sourceId = unitIdByName[srcKey]
      end

      -- DoT-тики одного и того же навыка приходят в лог многократно. Пока идёт
      -- активная фаза записи, повторные события игнорируем; после неё триггер
      -- снова разрешён (перезапуск по ауре отработает обычным опросом).
      local entry = nil
      if isSelf then
        entry = playerBuffData[cb.id] or buffData[cb.id]
      elseif sourceId then
        if currentTargetId and tostring(currentTargetId) == tostring(sourceId) then
          entry = targetBuffData[cb.id]
        end
        if not entry and targetCache[sourceId] and targetCache[sourceId].buffStates then
          entry = targetCache[sourceId].buffStates[cb.id]
        end
      end
      local blockWindow = 0
      if entry and entry.fixedTime then
        local actLeft = (tonumber(entry.activeUntil) or 0) - now
        if actLeft > 0.5 then blockWindow = actLeft + 0.5 end
      end

      local blocked = false
      if blockWindow > 0.5 then
        local tkey = tostring(srcKey or "self") .. "|" .. tostring(cb.id)
        local last = lastTriggerTimes[tkey]
        if last and (now - last) < (blockWindow - 0.5) then
          blocked = true
          if settings.debugBuffId then
            safeLog("[CBT] '" .. tostring(spellName) .. "': repeat trigger after "
              .. string.format("%.1f", now - last) .. " s - ignored (window " .. tostring(blockWindow) .. ")")
          end
        else
          lastTriggerTimes[tkey] = now
        end
      end

      if not blocked then

      if isSelf then
        local hits = triggerSelfBuff(cb.id, now)
        -- КД пишем на юнит-источник: если ты держишь себя в таргете, он покажется
        -- и на панели Target тоже (сам себе цель — это цель).
        if sourceId then
          triggerTargetCooldown(sourceId, cb.id, now, now)
        end
        if settings.debugBuffId then
          if hits > 0 then
            safeLog("[CBT] '" .. spellName .. "': self cast -> Player/Mount panels: " .. tostring(hits))
          else
            safeLog("[CBT] '" .. spellName .. "': self cast, but the buff is not tracked on Player/Mount")
          end
          if sourceId and currentTargetId and tostring(currentTargetId) == tostring(sourceId) then
            safeLog("[CBT] '" .. spellName .. "': you are the current target -> recorded to Target")
          end
        end
      elseif sourceId then
        triggerTargetCooldown(sourceId, cb.id, now, now)
        if settings.debugBuffId then
          safeLog("[CBT] '" .. spellName .. "': cooldown recorded for " .. tostring(srcKey) .. " (unit " .. tostring(sourceId) .. ")")
        end
      elseif srcKey then
        local p = pendingBySource[srcKey]
        if not p then
          p = {}
          pendingBySource[srcKey] = p
        end
        p[cb.id] = now
        if settings.debugBuffId then
          safeLog("[CBT] '" .. spellName .. "': source " .. tostring(srcKey) .. " unknown, waiting for the first target")
        end
      else
        if settings.debugBuffId then
          safeLog("[CBT] '" .. spellName .. "': no source in the event")
        end
      end
      end
    end
  end
end

local function createChildWidgetSafe(parent, widgetType, name, index)
  if not parent then return nil end

  local widget = api.Interface:CreateWidget(widgetType, name, parent)

  if not widget then
    widget = parent:CreateChildWidget(widgetType, name, index or 0, true)
  end

  return widget
end

-- Обёртка над CreateItemIconButton: гарантирует SetColor/SetBorderColor,
-- не подменяя глобальную функцию движка.
local function createTrackedIconButton(name, parent)
  if not CreateItemIconButton then return nil end
  local icon = CreateItemIconButton(name, parent)
  if not icon then return nil end
  if not icon.SetBorderColor then
    icon.SetBorderColor = function(self, r, g, b, a)
      if self.back and self.back.SetColor then
        self.back:SetColor(r, g, b, a)
      end
    end
  end
  if not icon.SetColor then
    icon.SetColor = function(self, r, g, b, a)
      if self.back and self.back.SetColor then
        self.back:SetColor(r, g, b, a)
      end
    end
  end
  return icon
end

-- =====================================================================
-- Этап 4: настраиваемая сетка иконок (columns x rows + maxIcons).
-- Защитный предел на число создаваемых виджетов-иконок в одном канвасе.
-- Канвас создаётся один раз, поэтому держим фиксированный пул иконок этого
-- размера, а реальное число показанных ограничиваем maxIcons на лету.
-- =====================================================================
local MAX_GRID_ICONS = 40

local function getGridColumns(cfg)
  local cols = math.floor(tonumber(cfg and cfg.gridColumns) or 10)
  if cols < 1 then cols = 1 end
  if cols > MAX_GRID_ICONS then cols = MAX_GRID_ICONS end
  return cols
end

local function getGridRows(cfg)
  local rows = math.floor(tonumber(cfg and cfg.gridRows) or 1)
  if rows < 1 then rows = 1 end
  if rows > MAX_GRID_ICONS then rows = MAX_GRID_ICONS end
  return rows
end

-- Сколько иконок реально показываем: не больше ёмкости сетки (cols*rows),
-- не больше глобального предела и не меньше 1.
local function getMaxIcons(cfg)
  local capacity = getGridColumns(cfg) * getGridRows(cfg)
  if capacity > MAX_GRID_ICONS then capacity = MAX_GRID_ICONS end
  local maxIcons = tonumber(cfg and cfg.maxIcons)
  if not maxIcons then
    maxIcons = capacity
  else
    maxIcons = math.floor(maxIcons)
  end
  if maxIcons < 1 then maxIcons = 1 end
  if maxIcons > capacity then maxIcons = capacity end
  return maxIcons
end

-- Позиция иконки по индексу (1-based): слева направо, сверху вниз.
local function calculateIconPosition(index, cfg)
  local cols = getGridColumns(cfg)
  local size = tonumber(cfg and cfg.iconSize) or 40
  local spacing = tonumber(cfg and cfg.iconSpacing) or 5
  -- вертикальный отступ между строками — отдельная настройка (с откатом на iconSpacing)
  local rowSpacing = tonumber(cfg and cfg.gridRowSpacing) or spacing
  local col = (index - 1) % cols
  local row = math.floor((index - 1) / cols)
  return col * (size + spacing), row * (size + rowSpacing)
end

-- Якорим иконку в ячейку сетки относительно левого-верхнего угла канваса.
local function anchorIconInGrid(icon, parent, index, cfg)
  if not icon then return end
  local x, y = calculateIconPosition(index, cfg)
  icon:RemoveAllAnchors()
  icon:AddAnchor("TOPLEFT", parent, x, y)
end

-- Function to create buff icon
-- cfg — раскладка КОНКРЕТНОГО канваса (settings[unitType].canvases[canvasIndex]);
-- canvasIndex входит в id виджетов: id в движке глобальные, а иконки у каждого
-- канваса свои.
local function addBuffIcon(parent, index, unitType, canvasIndex, canvasCfg)
  unitType = unitType or "playerpet" -- Use mount by default
  canvasIndex = canvasIndex or 1

  local us = canvasCfg
  if not us then
    us = (settings[unitType] and settings[unitType].canvases and settings[unitType].canvases[canvasIndex]) or {}
  end
  local uid = tostring(unitType) .. "_" .. tostring(canvasIndex) .. "_" .. tostring(index)

  local icon = createTrackedIconButton("buffIcon_" .. uid, parent)
  if not icon then return nil end

  icon:SetExtent(us.iconSize, us.iconSize)

  -- Этап 4: позиция иконки в сетке (слева направо, сверху вниз)
  anchorIconInGrid(icon, parent, index, us)

  -- Create a color overlay for the icon (will show status)
  local statusOverlay = icon:CreateColorDrawable(0, 0, 0, 0, "overlay")
  statusOverlay:AddAnchor("TOPLEFT", icon, 0, 0)
  statusOverlay:AddAnchor("BOTTOMRIGHT", icon, 0, 0)
  icon.statusOverlay = statusOverlay

  -- Create a border around the icon
  local borderSize = 2

  -- Top border
  local topBorder = icon:CreateColorDrawable(1, 1, 1, 0, "overlay")
  topBorder:AddAnchor("TOPLEFT", icon, -borderSize, -borderSize)
  topBorder:AddAnchor("TOPRIGHT", icon, borderSize, -borderSize)
  topBorder:SetHeight(borderSize)
  icon.topBorder = topBorder

  -- Bottom border
  local bottomBorder = icon:CreateColorDrawable(1, 1, 1, 0, "overlay")
  bottomBorder:AddAnchor("BOTTOMLEFT", icon, -borderSize, borderSize)
  bottomBorder:AddAnchor("BOTTOMRIGHT", icon, borderSize, borderSize)
  bottomBorder:SetHeight(borderSize)
  icon.bottomBorder = bottomBorder

  -- Left border
  local leftBorder = icon:CreateColorDrawable(1, 1, 1, 0, "overlay")
  leftBorder:AddAnchor("TOPLEFT", icon, -borderSize, -borderSize)
  leftBorder:AddAnchor("BOTTOMLEFT", icon, -borderSize, borderSize)
  leftBorder:SetWidth(borderSize)
  icon.leftBorder = leftBorder

  -- Right border
  local rightBorder = icon:CreateColorDrawable(1, 1, 1, 0, "overlay")
  rightBorder:AddAnchor("TOPRIGHT", icon, borderSize, -borderSize)
  rightBorder:AddAnchor("BOTTOMRIGHT", icon, borderSize, borderSize)
  rightBorder:SetWidth(borderSize)
  icon.rightBorder = rightBorder

  -- Save creation parameters for diagnostics
  icon.createdWithSize = us.iconSize
  icon.createdWithSpacing = us.iconSpacing
  icon.iconIndex = index

  -- Create background for icon
  local slotStyle = {
      path = TEXTURE_PATH.HUD,
      coords = {685, 130, 7, 8},
      inset = {3, 3, 3, 3},
      color = {1, 1, 1, 1}
  }
  F_SLOT.ApplySlotSkin(icon, icon.back, slotStyle)

  icon:Show(false)

  -- Create label for name
  local nameLabel = createChildWidgetSafe(icon, "label", "nameLabel_" .. uid)
  if nameLabel then
    nameLabel:SetExtent(us.iconSize * 2, us.iconSize/2)
    nameLabel:AddAnchor("CENTER", icon, us.labelX, us.labelY)
    nameLabel.style:SetFontSize(us.labelFontSize or 14)
    nameLabel.style:SetAlign(ALIGN.CENTER)
    nameLabel.style:SetShadow(true)

    -- Set color from settings
    if us.labelTextColor then
      nameLabel.style:SetColor(
        us.labelTextColor.r or 1,
        us.labelTextColor.g or 1,
        us.labelTextColor.b or 1,
        1
      )
    else
      nameLabel.style:SetColor(1, 1, 1, 1)
    end

    nameLabel:SetText("")
    nameLabel:Show(false)
  end

  -- Create semi-transparent background for timer (no image, only color)
  local timerBg = createChildWidgetSafe(icon, "window", "timerBg_" .. uid)
  if timerBg then
    -- Create semi-transparent color background, not an image
    local bg = timerBg:CreateColorDrawable(0, 0, 0, 0.5, "background")
    timerBg:SetExtent(us.iconSize, us.iconSize/2)
    timerBg:AddAnchor("BOTTOM", icon, 0, 0)
    timerBg:Show(false)
  end

  -- Create label for timer
  local timerLabel = createChildWidgetSafe(icon, "label", "timerLabel_" .. uid)
  timerLabel:SetExtent(us.iconSize, us.iconSize/2)
  timerLabel:AddAnchor("CENTER", icon, us.timerX, us.timerY)
  timerLabel.style:SetFontSize(us.timerFontSize or 16)
  timerLabel.style:SetAlign(ALIGN.CENTER)
  timerLabel.style:SetShadow(true)

  -- Set color from settings
  if us.timerTextColor then
    timerLabel.style:SetColor(
      us.timerTextColor.r or 1,
      us.timerTextColor.g or 1,
      us.timerTextColor.b or 1,
      1
    )
  else
    timerLabel.style:SetColor(1, 1, 1, 1)
  end

  timerLabel:SetText("")
  timerLabel:Show(false)

  icon.nameLabel = nameLabel
  icon.timerLabel = timerLabel
  icon.timerBg = timerBg

  return icon
end

-- Раскладка канваса, читается ЗАНОВО на каждое событие: пресет/импорт могут
-- заменить таблицу настроек целиком, и захваченный при создании upvalue станет
-- «оторванной» копией.
local function canvasCfgOf(unitType, canvasIndex)
  local unitSettings = settings and settings[unitType]
  if not unitSettings or type(unitSettings.canvases) ~= "table" then return nil end
  return unitSettings.canvases[canvasIndex]
end

-- Общий конструктор панели: одинаков для mount/player/target и для всех
-- канвасов юнита; отличается id окна, типом юнита и индексом канваса.
local function createPanelCanvas(windowId, unitType, canvasIndex)
  canvasIndex = canvasIndex or 1
  local unitSettings = settings[unitType]
  local us = unitSettings and unitSettings.canvases and unitSettings.canvases[canvasIndex]
  if not us then return nil end

  local canvas = api.Interface:CreateEmptyWindow(windowId)
  if not canvas then
    return nil
  end

  -- HUD-панели держим на слое game: они выше мира, но НИЖЕ любых окон
  pcall(function() canvas:SetUILayer("game") end)
  canvas:SetExtent(us.iconSize * 3, us.iconSize * 1.5)

  -- Explicitly set canvas position from settings
  canvas:RemoveAllAnchors()
  canvas:AddAnchor("TOPLEFT", "UIParent", us.posX, us.posY)

  canvas:Clickable(true)

  if canvas.SetZOrder then
    canvas:SetZOrder(100)
  end

  local bg = canvas:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
  if bg then
    bg:SetTextureInfo("bg_quest")
    bg:SetColor(0, 0, 0, 0.4)
    bg:AddAnchor("TOPLEFT", canvas, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", canvas, 0, 0)
    canvas.bg = bg
  end

  canvas:Show(false)

  -- Store unit type / canvas index for later use
  canvas.unitType = unitType
  canvas.canvasIndex = canvasIndex

  canvas.buffIcons = {}
  -- Пул иконок этого канваса: только записи, назначенные на него.
  local initialIcons = 0
  local map = unitSettings.canvasOf or {}
  local allIds = BuffsToTrack.GetAllTrackedBuffIds(unitType) or {}
  for _, buffId in ipairs(allIds) do
    local idx = tonumber(map[tostring(buffId)]) or 1
    if idx == canvasIndex then initialIcons = initialIcons + 1 end
  end
  if initialIcons < 1 then initialIcons = 1 end
  if initialIcons > MAX_GRID_ICONS then initialIcons = MAX_GRID_ICONS end
  for i = 1, initialIcons do
    canvas.buffIcons[i] = addBuffIcon(canvas, i, unitType, canvasIndex, us)

    -- Ensure that the icon has the correct position based on settings
    if canvas.buffIcons[i] then
      canvas.buffIcons[i]:RemoveAllAnchors()
      canvas.buffIcons[i]:SetExtent(us.iconSize, us.iconSize)

      -- Explicitly calculate icon position taking into account current interval
      anchorIconInGrid(canvas.buffIcons[i], canvas, i, us)
    end
  end

  -- Implementation of drag functionality for canvas
  canvas.isDragging = false

  canvas.OnDragStart = function(self, arg)
    local cfg = canvasCfgOf(unitType, canvasIndex) or us
    if cfg.lockPositioning then return end

    self.isDragging = true
    if self.bg then
      self.bg:SetColor(0, 0, 0, 0.6)  -- Higher opacity during dragging
    end

    self:StartMoving()
    api.Cursor:ClearCursor()
    api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
  end

  canvas.OnDragStop = function(self)
    local cfg = canvasCfgOf(unitType, canvasIndex) or us
    if cfg.lockPositioning then
      return
    end

    self:StopMovingOrSizing()
    if self.bg then
      self.bg:SetColor(0, 0, 0, 0.4)
    end

    local x, y = self:GetEffectiveOffset()
    if x == nil or y == nil then
      x, y = self:GetOffset()
    end
    if type(x) == "number" and type(y) == "number" then
      cfg.posX = x
      cfg.posY = y
      self.appliedPosX = x
      self.appliedPosY = y
    end

    if settingsPage and settingsPage.updatePositionFields
        and settingsPage.isSelectedCanvas and settingsPage.isSelectedCanvas(unitType, canvasIndex) then
      settingsPage.updatePositionFields(x, y)
    end

    if helpers and helpers.updateSettings then
      helpers.updateSettings()
    end

    self.isDragging = false
    api.Cursor:ClearCursor()
  end

  canvas:SetHandler("OnDragStart", canvas.OnDragStart)
  canvas:SetHandler("OnDragStop", canvas.OnDragStop)

  if canvas.RegisterForDrag ~= nil then
    canvas:RegisterForDrag("LeftButton")
  end

  if canvas.EnableDrag ~= nil then
    canvas:EnableDrag(not us.lockPositioning)
  end

  canvas.appliedPosX = us.posX
  canvas.appliedPosY = us.posY

  return canvas
end

-- Function to cleanup old target cache entries
local function cleanupTargetCache()
  local currentTime = getCurrentTime()
  local cacheTimeout = settings.target and settings.target.cacheTimeout or 300 -- Default 5 minutes

  local keysToRemove = {}

  for targetId, cacheEntry in pairs(targetCache) do
    if currentTime - cacheEntry.lastSeen > cacheTimeout then
      table.insert(keysToRemove, targetId)
    end
  end

  for _, targetId in ipairs(keysToRemove) do
    targetCache[targetId] = nil
    if settings.debugBuffId then
      safeLog("[CBT] Target cache cleaned: " .. tostring(targetId))
    end
  end

  -- Очищаем историю баффов для удаленных целей
  for targetId, _ in pairs(keysToRemove) do
    targetActiveBuffs[targetId] = nil
  end
end

-- Function to get current target ID
local function getCurrentTargetId()
  local targetId = api.Unit:GetUnitId("target")
  return targetId
end

-- Function to check if there are buffs to track
local function hasTrackedBuffs(unitType)
  -- First check the setting that completely disables tracking
  local settings = api.GetSettings("CooldawnBuffTracker") or {}

  if unitType == "player" then
    -- Check settings for player
    if not settings.player or settings.player.enabled == false then
      return false
    end

    -- Check if there are buffs in the list
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds("player")
    return #trackedBuffIds > 0
  elseif unitType == "playerpet" then
    -- Check settings for mount
    if not settings.playerpet or settings.playerpet.enabled == false then
      return false
    end

    -- Check if there are buffs in the list
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds("playerpet")
    return #trackedBuffIds > 0
  elseif unitType == "target" then
    -- Check settings for target
    if not settings.target or settings.target.enabled == false then
      return false
    end

    -- Check if there are buffs in the list
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds("target")
    return #trackedBuffIds > 0
  else
    -- If type is not specified, check for buffs of any type
    local trackedMountBuffIds = BuffsToTrack.GetAllTrackedBuffIds("playerpet")
    local trackedPlayerBuffIds = BuffsToTrack.GetAllTrackedBuffIds("player")
    local trackedTargetBuffIds = BuffsToTrack.GetAllTrackedBuffIds("target")

    local hasMountBuffs = settings.playerpet and settings.playerpet.enabled ~= false and #trackedMountBuffIds > 0
    local hasPlayerBuffs = settings.player and settings.player.enabled ~= false and #trackedPlayerBuffIds > 0
    local hasTargetBuffs = settings.target and settings.target.enabled ~= false and #trackedTargetBuffIds > 0

    return hasMountBuffs or hasPlayerBuffs or hasTargetBuffs
  end
end

-- Достраивает пул иконок панели до нужного числа (не больше MAX_GRID_ICONS).
-- Иконки создаются по мере надобности, а не 40 на каждую панель сразу.
-- Достраивает пул иконок панели до нужного числа (не больше MAX_GRID_ICONS).
-- Иконки создаются по мере надобности, а не 40 на каждый канвас сразу.
local function ensureIconPool(canvas, unitType, canvasIndex, cfg, needed)
  if not canvas or not needed or not cfg then return end
  if needed > MAX_GRID_ICONS then needed = MAX_GRID_ICONS end
  local have = #canvas.buffIcons
  if needed <= have then return end
  for i = have + 1, needed do
    local icon = addBuffIcon(canvas, i, unitType, canvasIndex, cfg)
    if not icon then break end
    icon:RemoveAllAnchors()
    icon:SetExtent(cfg.iconSize, cfg.iconSize)
    anchorIconInGrid(icon, canvas, i, cfg)
    canvas.buffIcons[i] = icon
  end
end

-- Индекс канваса, которому принадлежит запись юнита (по умолчанию — первый).
local function canvasIndexFor(unitSettings, buffId)
  local map = unitSettings and unitSettings.canvasOf
  local idx = map and tonumber(map[tostring(buffId)])
  if not idx then return 1 end
  idx = math.floor(idx)
  if idx < 1 then idx = 1 end
  return idx
end

-- =====================================================================
-- Жизненный цикл канвасов: создание/удаление под текущий список
-- settings[unitType].canvases.
-- =====================================================================

local function destroyCanvasWidget(canvas)
  if not canvas then return end
  pcall(function() canvas:StopMovingOrSizing() end)
  pcall(function() canvas:ReleaseHandler("OnDragStart") end)
  pcall(function() canvas:ReleaseHandler("OnDragStop") end)
  pcall(function() canvas:Show(false) end)
  pcall(function() api.Interface:Free(canvas) end)
end

local function destroyUnitCanvases(unitType)
  local list = unitCanvases[unitType]
  if not list then return end
  for i = #list, 1, -1 do
    destroyCanvasWidget(list[i])
    list[i] = nil
  end
end

local function hideUnitCanvases(unitType)
  local list = unitCanvases[unitType]
  if not list then return end
  for _, canvas in ipairs(list) do
    if canvas and canvas.Show then
      -- не дёргаем Show(false) каждый кадр, если панель уже скрыта
      local visible = true
      if canvas.IsVisible then
        local okVis, vis = pcall(function() return canvas:IsVisible() end)
        if okVis then visible = vis and true or false end
      end
      if visible then canvas:Show(false) end
    end
  end
end

local function hideAllCanvases()
  for _, unitType in ipairs(UNIT_TYPES) do
    hideUnitCanvases(unitType)
  end
end

-- Приводит набор виджетов к числу канвасов в настройках: создаёт недостающие,
-- освобождает лишние. Возвращает true, если что-то создано.
local function ensureUnitCanvases(unitType)
  local unitSettings = settings and settings[unitType]
  if not unitSettings or type(unitSettings.canvases) ~= "table" then return false end
  local list = unitCanvases[unitType]
  if not list then
    list = {}
    unitCanvases[unitType] = list
  end

  local wanted = #unitSettings.canvases
  -- Лишние канвасы (после удаления) освобождаем.
  for i = #list, wanted + 1, -1 do
    destroyCanvasWidget(list[i])
    list[i] = nil
  end

  local created = false
  local baseId = CANVAS_BASE_ID[unitType] or (unitType .. "BuffCanvas")
  for i = 1, wanted do
    if not list[i] then
      local windowId = baseId
      if i > 1 then windowId = baseId .. tostring(i) end
      list[i] = createPanelCanvas(windowId, unitType, i)
      if list[i] then created = true end
    end
  end
  return created
end

-- Рисует один канвас. activeBuffs — список записей ИМЕННО этого канваса.
local function renderCanvas(canvas, unitType, us, activeBuffs)
  if not canvas or not us then return end

  -- Обновляем все иконки и скрываем неиспользуемые
  -- Число одновременно показанных иконок ограничено настройкой maxIcons
  local maxShown = math.min(#activeBuffs, getMaxIcons(us))
  ensureIconPool(canvas, unitType, canvas.canvasIndex or 1, us, maxShown)

  -- Подпись раскладки: геометрия + набор/иконки/имена показанных баффов.
  -- Пока подпись не меняется, виджеты не пересобираются — обновляются только
  -- цвет статуса и текст таймера. Это главный выигрыш по нагрузке.
  local sigParts = {
    tostring(us.iconSize), tostring(us.iconSpacing), tostring(us.gridColumns),
    tostring(us.gridRows), tostring(us.maxIcons), tostring(us.gridRowSpacing),
    us.showLabel and "1" or "0", tostring(us.labelFontSize),
    tostring(us.labelX), tostring(us.labelY), colorSignature(us.labelTextColor),
    us.showTimer and "1" or "0", tostring(us.timerFontSize),
    tostring(us.timerX), tostring(us.timerY), colorSignature(us.timerTextColor),
    tostring(us.posX), tostring(us.posY), us.lockPositioning and "1" or "0",
    tostring(maxShown)
  }
  for i = 1, maxShown do
    sigParts[#sigParts + 1] = tostring(activeBuffs[i].id) .. "="
      .. tostring(activeBuffs[i].buff.icon) .. "=" .. tostring(activeBuffs[i].buff.name)
  end
  local layoutSig = table.concat(sigParts, "|")
  local relayout = (canvas.layoutSig ~= layoutSig)

  local currentTime = tonumber(getCurrentTime()) or 0
  for i, icon in ipairs(canvas.buffIcons or {}) do
    if icon and icon.Show then
      -- Показываем и настраиваем только иконки, которые используются
      if i <= maxShown then
        local buffInfo = activeBuffs[i]
        local buffId = buffInfo.id
        local buff = buffInfo.buff

        if relayout then
          -- Обновляем размер иконки согласно текущим настройкам
          icon:SetExtent(us.iconSize, us.iconSize)
          -- Позиция иконки в сетке (слева направо, сверху вниз)
          anchorIconInGrid(icon, canvas, i, us)
          -- Устанавливаем изображение для иконки
          F_SLOT.SetIconBackGround(icon, buff.icon)
          -- Явно устанавливаем иконку видимой
          icon:Show(true)
        end

        -- Сохраняем ID баффа и привязку к отладчику только при смене
        if icon.buffId ~= buffId then
          icon.buffId = buffId
          if BuffDebugger and BuffDebugger.SetBuffIdForIcon then
            BuffDebugger.SetBuffIdForIcon(icon, buffId, unitType)
          end
        end

        if relayout then
          -- Отображаем имя баффа, если включено в настройках
          if icon.nameLabel and us.showLabel then
            -- Обновляем размер шрифта метки на основе текущих настроек
            icon.nameLabel.style:SetFontSize(us.labelFontSize or 14)

            -- Обновляем позицию метки на основе текущих настроек
            icon.nameLabel:RemoveAllAnchors()
            icon.nameLabel:AddAnchor("CENTER", icon, us.labelX or 0, us.labelY or -30)

            -- Обновляем цвет текста метки из настроек (только при изменении)
            local labelTextColor = us.labelTextColor or {r = 1, g = 1, b = 1, a = 1}
            local colorKey = tostring(labelTextColor.r) .. "," .. tostring(labelTextColor.g)
                .. "," .. tostring(labelTextColor.b) .. "," .. tostring(labelTextColor.a)
            if icon._nameColorKey ~= colorKey then
                icon.nameLabel.style:SetColor(labelTextColor.r, labelTextColor.g, labelTextColor.b, labelTextColor.a)
                icon._nameColorKey = colorKey
            end

            local nameText = buff.name or ""
            if icon._nameText ~= nameText then
                icon.nameLabel:SetText(nameText)
                icon._nameText = nameText
            end
            icon.nameLabel:Show(true)
          elseif icon.nameLabel then
            icon.nameLabel:Show(false)
          end
        end

        -- Определяем текущий статус баффа
        local currentStatus = buff.status
        if buff.fixedTime then
          currentStatus = checkBuffStatus(buff, currentTime)
        end

        -- Цвет статуса меняется редко: оверлей/рамки трогаем только при смене
        if relayout or icon.lastStatus ~= currentStatus then
        if currentStatus == "ready" then
          -- Для готового баффа - прозрачный оверлей (без подсветки)
          if icon.statusOverlay then
            icon.statusOverlay:SetColor(1, 1, 1, 0) -- Полностью прозрачный
          end

          -- Невидимая граница для состояния готовности
          if icon.topBorder then icon.topBorder:SetColor(1, 1, 1, 0) end
          if icon.bottomBorder then icon.bottomBorder:SetColor(1, 1, 1, 0) end
          if icon.leftBorder then icon.leftBorder:SetColor(1, 1, 1, 0) end
          if icon.rightBorder then icon.rightBorder:SetColor(1, 1, 1, 0) end

          -- Также восстанавливаем нормальный белый цвет иконки
          if icon.SetColor then
            icon:SetColor(ICON_COLORS.READY[1], ICON_COLORS.READY[2], ICON_COLORS.READY[3], ICON_COLORS.READY[4])
          end
        elseif currentStatus == "active" then
          -- Для активного баффа - зеленая подсветка
          if icon.statusOverlay then
            icon.statusOverlay:SetColor(0, 1, 0, 0.3) -- Полупрозрачный зеленый
          end

          -- Яркая зеленая граница для активного состояния
          local borderColor = {0, 1, 0, 0.8} -- Яркий зеленый
          if icon.topBorder then icon.topBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
          if icon.bottomBorder then icon.bottomBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
          if icon.leftBorder then icon.leftBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
          if icon.rightBorder then icon.rightBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end

          -- Также устанавливаем зеленый цвет для иконки
          if icon.SetColor then
            icon:SetColor(ICON_COLORS.ACTIVE[1], ICON_COLORS.ACTIVE[2], ICON_COLORS.ACTIVE[3], ICON_COLORS.ACTIVE[4])
          end
        elseif currentStatus == "cooldown" then
          -- Для баффа на кулдауне - красная подсветка
          if icon.statusOverlay then
            icon.statusOverlay:SetColor(1, 0, 0, 0.3) -- Полупрозрачный красный
          end

          -- Яркая красная граница для состояния кулдауна
          local borderColor = {1, 0, 0, 0.8} -- Яркий красный
          if icon.topBorder then icon.topBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
          if icon.bottomBorder then icon.bottomBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
          if icon.leftBorder then icon.leftBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
          if icon.rightBorder then icon.rightBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end

          -- Также устанавливаем красный цвет для иконки
          if icon.SetColor then
            icon:SetColor(ICON_COLORS.COOLDOWN[1], ICON_COLORS.COOLDOWN[2], ICON_COLORS.COOLDOWN[3], ICON_COLORS.COOLDOWN[4])
          end
        end
          icon.lastStatus = currentStatus
        end

        -- Таймер: текст меняется не чаще 10 раз/с — SetText только по изменению
        if icon.timerLabel and us.showTimer then
          local timerText = ""

          if currentStatus == "active" and buff.activeUntil and buff.activeUntil ~= math.huge then
            local remainingActive = buff.activeUntil - currentTime
            if remainingActive > 0 then
              timerText = formatTimerSeconds(remainingActive)
            end
          elseif currentStatus == "cooldown" and buff.readyAt then
            local remainingCooldown = buff.readyAt - currentTime
            if remainingCooldown > 0 then
              timerText = formatTimerSeconds(remainingCooldown)
            end
          end

          if relayout then
            -- Шрифт/позиция/цвет таймера — только при пересборке раскладки
            icon.timerLabel.style:SetFontSize(us.timerFontSize or 16)
            icon.timerLabel:RemoveAllAnchors()
            icon.timerLabel:AddAnchor("CENTER", icon, us.timerX or 0, us.timerY or 0)
            local timerTextColor = us.timerTextColor or {r = 1, g = 1, b = 1, a = 1}
            icon.timerLabel.style:SetColor(
              (timerTextColor and timerTextColor.r) or 1,
              (timerTextColor and timerTextColor.g) or 1,
              (timerTextColor and timerTextColor.b) or 1,
              (timerTextColor and timerTextColor.a) or 1)
            if icon.timerBg then
              icon.timerBg:SetExtent(us.iconSize, us.iconSize/2)
              icon.timerBg:RemoveAllAnchors()
              icon.timerBg:AddAnchor("BOTTOM", icon, 0, 0)
            end
          end

          if icon.lastTimerText ~= timerText then
            icon.timerLabel:SetText(timerText)
            icon.timerLabel:Show(timerText ~= "")
            if icon.timerBg then icon.timerBg:Show(timerText ~= "") end
            icon.lastTimerText = timerText
          end
        elseif icon.timerLabel then
          if icon.lastTimerText ~= "" then
            icon.timerLabel:Show(false)
            if icon.timerBg then icon.timerBg:Show(false) end
            icon.lastTimerText = ""
          end
        end
      else
        -- Скрываем неиспользуемые иконки (и сбрасываем кэш их состояния)
        if icon.IsVisible == nil or icon:IsVisible() then
          icon:Show(false)
          if icon.nameLabel then icon.nameLabel:Show(false) end
          if icon.timerLabel then icon.timerLabel:Show(false) end
          if icon.timerBg then icon.timerBg:Show(false) end
        end
        icon.lastStatus = nil
        icon.lastTimerText = nil
      end
    end
  end

  if relayout then
    -- Обновляем размер canvas под фактическую сетку
    local cols = getGridColumns(us)
    local usedCols = math.max(1, math.min(maxShown, cols))
    local usedRows = math.max(1, math.ceil(maxShown / cols))
    local totalWidth = usedCols * us.iconSize + (usedCols - 1) * us.iconSpacing
    totalWidth = math.max(totalWidth, us.iconSize * 2)
    local rowSpacing = tonumber(us.gridRowSpacing) or us.iconSpacing
    local totalHeight = usedRows * us.iconSize + (usedRows - 1) * rowSpacing
    totalHeight = math.max(totalHeight, us.iconSize * 1.2)

    -- "Язычок" справа: всегда оставляем пустую область фона, за которую можно
    -- перетаскивать канвас (иначе иконки-кнопки заняли бы всю ширину и тащить
    -- было бы не за что).
    local dragHandle = math.max(12, math.floor(us.iconSize * 0.4))

    canvas:SetWidth(totalWidth + dragHandle)
    canvas:SetHeight(totalHeight)

    -- Позиция и состояние drag — только при пересборке и не во время перетаскивания
    if canvas.isDragging ~= true then
      canvas:RemoveAllAnchors()
      canvas:AddAnchor("TOPLEFT", "UIParent", us.posX, us.posY)
      canvas.appliedPosX = us.posX
      canvas.appliedPosY = us.posY
      if canvas.EnableDrag ~= nil then
        canvas:EnableDrag(not us.lockPositioning)
      end
    end

    if canvas.bg then
      canvas.bg:SetColor(0, 0, 0, 0.4)
    end
    canvas.layoutSig = layoutSig
  end

  canvas:Show(true)
end

local function updateBuffIcons(unitType)
  unitType = unitType or "playerpet"  -- По умолчанию используем mount

  local unitSettings = settings and settings[unitType]
  local canvasesForUnit = unitCanvases[unitType] or {}
  if not unitSettings or #canvasesForUnit == 0 then return end

  -- Данные юнита: одно сканирование аур на юнит, канвасы лишь делят записи.
  local buffDataTable

  if unitType == "target" then
    -- Use cached display data if no current target, otherwise use live data
    local currentTarget = getCurrentTargetId()
    if not currentTarget and lastDisplayedTargetId then
      -- No target but we have cached data - use it
      buffDataTable = cachedTargetDisplayData

      -- Record the time when target was lost (if not already recorded)
      if not lastTargetLostTime then
        lastTargetLostTime = getCurrentTime()
      end
    else
      buffDataTable = targetBuffData
      -- Reset lost time since we have a target
      if currentTarget then
        lastTargetLostTime = nil
      end
    end
  elseif unitType == "player" then
    buffDataTable = playerBuffData
  else
    buffDataTable = buffData
  end

  -- Проверяем, есть ли баффы для отслеживания
  local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds(unitType)
  if #trackedBuffIds == 0 then
    hideUnitCanvases(unitType)
    return
  end

  -- Создаем упорядоченный список баффов согласно порядку добавления
  local activeBuffs = {}
  for i, buffId in ipairs(trackedBuffIds) do
    if buffDataTable[buffId] then
      table.insert(activeBuffs, {id = buffId, buff = buffDataTable[buffId], order = i})
    end
  end

  -- Для target: показываем баффы, которые когда-либо были активны на текущей цели
  if unitType == "target" then
    -- Проверяем, есть ли у нас текущая цель
    local currentTargetId = getCurrentTargetId()

    if not currentTargetId then
      -- Нет цели - используем кэшированные данные (обработка ниже)
      if lastDisplayedTargetId and lastTargetLostTime and targetActiveBuffs[lastDisplayedTargetId] then
        -- Используем историю для последней цели
        local historyBuffs = targetActiveBuffs[lastDisplayedTargetId]
        local historyActiveBuffs = {}
        for _, buffInfo in ipairs(activeBuffs) do
          if historyBuffs[buffInfo.id] then
            table.insert(historyActiveBuffs, buffInfo)
          end
        end

        if #historyActiveBuffs == 0 then
          hideUnitCanvases(unitType)
          return
        end

        activeBuffs = historyActiveBuffs
      else
        hideUnitCanvases(unitType)
        return
      end
    else
      -- Есть цель - фильтруем по истории для этой цели
      if not targetActiveBuffs[currentTargetId] then
        targetActiveBuffs[currentTargetId] = {}
      end

      local historyBuffs = targetActiveBuffs[currentTargetId]
      local historyActiveBuffs = {}

      for _, buffInfo in ipairs(activeBuffs) do
        if historyBuffs[buffInfo.id] then
          table.insert(historyActiveBuffs, buffInfo)
        end
      end

      if #historyActiveBuffs == 0 then
        hideUnitCanvases(unitType)
        return
      end

      activeBuffs = historyActiveBuffs
    end
  end

  -- Если нет баффов для отслеживания, скрываем все канвасы
  -- Exception for target: check if we have cached data within timeout
  if #activeBuffs == 0 then
    if unitType == "target" and lastDisplayedTargetId and lastTargetLostTime then
      local currentTime = getCurrentTime()
      local cacheTimeout = settings.target and settings.target.cacheTimeout or 300
      if currentTime - lastTargetLostTime < cacheTimeout then
        -- Don't hide, we're showing cached data
        -- But if cached data is also empty, hide
        local hasCachedBuffs = false
        for _ in pairs(cachedTargetDisplayData) do
          hasCachedBuffs = true
          break
        end
        if not hasCachedBuffs then
          hideUnitCanvases(unitType)
          return
        end
        -- Use cached data for display
        activeBuffs = {}
        for i, buffId in ipairs(trackedBuffIds) do
          if cachedTargetDisplayData[buffId] then
            table.insert(activeBuffs, {id = buffId, buff = cachedTargetDisplayData[buffId], order = i})
          end
        end
        if #activeBuffs == 0 then
          hideUnitCanvases(unitType)
          return
        end
      else
        -- Timeout expired
        hideUnitCanvases(unitType)
        lastDisplayedTargetId = nil
        lastTargetLostTime = nil
        cachedTargetDisplayData = {}
        return
      end
    else
      hideUnitCanvases(unitType)
      return
    end
  end

  -- Рисуем каждый канвас своим подмножеством записей (canvasOf).
  for idx = 1, #canvasesForUnit do
    local canvas = canvasesForUnit[idx]
    local cfg = unitSettings.canvases and unitSettings.canvases[idx]
    if canvas and cfg then
      local canvasBuffs = {}
      for _, buffInfo in ipairs(activeBuffs) do
        if canvasIndexFor(unitSettings, buffInfo.id) == idx then
          canvasBuffs[#canvasBuffs + 1] = buffInfo
        end
      end
      if #canvasBuffs == 0 then
        canvas:Show(false)
      else
        renderCanvas(canvas, unitType, cfg, canvasBuffs)
      end
    end
  end
end

-- Создаёт/удаляет канвасы под настройки и перерисовывает иконки.
local function syncUnitCanvases(unitType)
  if not (settings and settings[unitType]) then return end
  if not hasTrackedBuffs(unitType) then
    hideUnitCanvases(unitType)
    return
  end
  ensureUnitCanvases(unitType)
  updateBuffIcons(unitType)
end

-- Полная пересборка панелей (после сохранения настроек/пресета/импорта).
local function refreshAllCanvases()
  if not live then return end
  for _, unitType in ipairs(UNIT_TYPES) do
    pcall(syncUnitCanvases, unitType)
  end
end

local function checkBuffs(unitType)
  unitType = unitType or "playerpet"  -- По умолчанию работаем с маунтом

  -- Определяем, какие переменные использовать в зависимости от типа юнита
  local unitSettings = settings[unitType]
  local buffDataTable
  local hasCanvases = #(unitCanvases[unitType] or {}) > 0

  if unitType == "target" then
    -- Special handling for target with caching logic
    local newTargetId = getCurrentTargetId()
    local currentTime = getCurrentTime()
    local cacheTimeout = settings.target and settings.target.cacheTimeout or 300

    -- If no target
    if not newTargetId then
      -- Check if we have cached data and timeout hasn't expired
      if lastDisplayedTargetId and lastTargetLostTime then
        local timeSinceLost = currentTime - lastTargetLostTime

        if timeSinceLost < cacheTimeout then
          -- Continue showing cached data, don't hide canvas
          -- Use cached display data for rendering
          buffDataTable = cachedTargetDisplayData

          -- Update timers based on cached fixedTime values
          for buffId, buffInfo in pairs(cachedTargetDisplayData) do
            if buffInfo.fixedTime then
              local expectedStatus = checkBuffStatus(buffInfo, currentTime)
              if expectedStatus ~= buffInfo.status then
                cachedTargetDisplayData[buffId].status = expectedStatus
              end
            end
          end

          -- Continue to updateBuffIcons with cached data
          if hasCanvases then
            updateBuffIcons("target")
          end
          return
        else
          -- Timeout expired, hide canvas and clear cached data
          lastDisplayedTargetId = nil
          lastTargetLostTime = nil
          cachedTargetDisplayData = {}
          hideUnitCanvases("target")
          return
        end
      else
        -- No cached data, hide canvas
        hideUnitCanvases("target")
        return
      end
    end

    -- We have a target
    -- Check if target changed
    if newTargetId ~= currentTargetId then
      -- Save current target data to cache before switching
      if currentTargetId and targetCache[currentTargetId] then
        targetCache[currentTargetId].buffStates = {}
        for buffId, buffInfo in pairs(targetBuffData) do
          targetCache[currentTargetId].buffStates[buffId] = {
            fixedTime = buffInfo.fixedTime,
            activeUntil = buffInfo.activeUntil,
            readyAt = buffInfo.readyAt,
            permanent = buffInfo.permanent,
            synthetic = buffInfo.synthetic,
            status = buffInfo.status,
            timeOfAction = buffInfo.timeOfAction,
            cooldown = buffInfo.cooldown,
            name = buffInfo.name,
            icon = buffInfo.icon
          }
        end
      end

      -- Clear current target data
      targetBuffData = {}

      -- Switch to new target
      currentTargetId = newTargetId
      lastDisplayedTargetId = newTargetId
      lastTargetLostTime = nil  -- Reset lost time since we have a target now


      -- Учим имя цели: по нему потом сопоставляем удары из боевого лога
      learnUnitName(newTargetId)

      -- Initialize or restore cache entry for new target
      if not targetCache[newTargetId] then
        targetCache[newTargetId] = {
          lastSeen = currentTime,
          buffStates = {}
        }
      else
        -- Restore buff data from cache
        for buffId, cachedBuff in pairs(targetCache[newTargetId].buffStates) do
          targetBuffData[buffId] = {
            name = cachedBuff.name,
            icon = cachedBuff.icon,
            cooldown = cachedBuff.cooldown,
            timeOfAction = cachedBuff.timeOfAction,
            fixedTime = cachedBuff.fixedTime,
            activeUntil = cachedBuff.activeUntil,
            readyAt = cachedBuff.readyAt,
            permanent = cachedBuff.permanent,
            synthetic = cachedBuff.synthetic,
            missingCount = 0,
            status = cachedBuff.status
          }
          -- Recalculate status based on current time
          if cachedBuff.fixedTime then
            local expectedStatus = checkBuffStatus(targetBuffData[buffId], currentTime)
            targetBuffData[buffId].status = expectedStatus
          end
        end
      end
    else
      -- Same target, update lastSeen and save to display cache
      lastDisplayedTargetId = newTargetId
      lastTargetLostTime = nil
    end

    -- Update lastSeen for current target
    if targetCache[currentTargetId] then
      targetCache[currentTargetId].lastSeen = currentTime
    end

    -- Update cached display data with current targetBuffData
    cachedTargetDisplayData = {}
    for buffId, buffInfo in pairs(targetBuffData) do
      cachedTargetDisplayData[buffId] = {
        name = buffInfo.name,
        icon = buffInfo.icon,
        cooldown = buffInfo.cooldown,
        timeOfAction = buffInfo.timeOfAction,
        fixedTime = buffInfo.fixedTime,
        activeUntil = buffInfo.activeUntil,
        readyAt = buffInfo.readyAt,
        permanent = buffInfo.permanent,
        status = buffInfo.status
      }
    end

    buffDataTable = targetBuffData
  elseif unitType == "player" then
    buffDataTable = playerBuffData
  else
    buffDataTable = buffData
  end

  -- Скрываем панели, если тип юнита отключен в настройках
  if not unitSettings.enabled then
    hideUnitCanvases(unitType)
    return
  end

  -- Проверяем, есть ли баффы для отслеживания
  local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds(unitType)

  -- Если список отслеживаемых баффов пуст, скрываем канвасы
  if #trackedBuffIds == 0 then
    hideUnitCanvases(unitType)
    return
  end

  local activeBuffsOnUnit = {}
  local hasChanges = false
  local currentBuffsOnUnit = {}
  -- Все ауры цели за этот тик: нужны эффективным КД (Battle Focus, 9000610,
  -- стаки, reset-проки), в том числе для навыков, которые не отслеживаются.
  local auraNow = nil
  if unitType == "target" then auraNow = {} end

  -- Проверяем активные баффы на юните
  local buffCountRaw = api.Unit:UnitBuffCount(unitType)
  local buffCount = buffCountRaw or 0
  for i = 1, buffCount do
    local buff = api.Unit:UnitBuff(unitType, i)

    -- Проверяем, существует ли бафф и есть ли у него идентификатор
    if buff and buff.buff_id then
      buff.buff_id = helpers.formatBuffId(buff.buff_id)
      -- Записываем текущие ID баффов для последующего сравнения
      currentBuffsOnUnit[buff.buff_id] = true
      if auraNow then auraNow[tostring(buff.buff_id)] = { stack = buff.stack } end

      -- Проверяем, нужно ли отслеживать этот бафф
      if BuffsToTrack.ShouldTrackBuff(buff.buff_id, unitType) then
        activeBuffsOnUnit[buff.buff_id] = true

        -- timeLeft отдаётся для любого юнита: по нему ре-синхронизируем момент старта.
        -- Порог 500 мс — защита от мерцания в последний момент баффа.
        local entry = buffDataTable[buff.buff_id]
        local remaining = buff.timeLeft
        local prevRemaining = entry and entry.lastRemaining
        -- Новый бафф: раньше его не было на юните (или записи не было вовсе).
        -- Refresh: остаток резко вырос — способность применили заново.
        local isNewBuff = (not entry) or (not entry.present)
        local refreshed = (prevRemaining ~= nil) and (remaining ~= nil)
          and (remaining > prevRemaining + 1000)
        -- Ре-синк имеет смысл только пока остаток укладывается в настроенную
        -- длительность. Если аура живёт дольше (R > toa), активную фазу задаёт
        -- настройка, и трогать её нельзя — иначе зелёная подсветка не кончится.
        local toaMs = (tonumber(entry and entry.timeOfAction) or 0) * 1000
        local now = getCurrentTime()
        -- player/mount — старт от первого появления ауры (как в 1.5.0);
        -- target — оценка по серверному остатку (аура могла висеть до таргета).
        local anchorNow = (unitType ~= "target")
        -- Запись уже запущена боевым логом (каст был раньше появления ауры) —
        -- не сдвигаем старт на момент ауры, иначе КД уезжает вперёд.
        local triggeredAnchor = entry and entry.synthetic and entry.fixedTime
          and (now - entry.fixedTime) < ((tonumber(entry.timeOfAction) or 0) + 5)

        if (isNewBuff or refreshed) and not triggeredAnchor then
          if anchorNow then
            -- Якорь — момент обнаружения: кулдаун после диспела отсчитывается от
            -- применения, а не от настроенной длительности
            setBuffStatus(buff.buff_id, "active", now, unitType, nil)
          else
            setBuffStatus(buff.buff_id, "active", now, unitType, remaining)
          end
          hasChanges = true

          -- Обновляем кэшированный статус
          cachedBuffStatus[buff.buff_id] = "active"

          -- Запоминаем бафф для текущей цели (для отслеживания истории)
          if unitType == "target" and currentTargetId then
            if not targetActiveBuffs[currentTargetId] then
              targetActiveBuffs[currentTargetId] = {}
            end
            targetActiveBuffs[currentTargetId][buff.buff_id] = true
          end
        end

        local rec = buffDataTable[buff.buff_id]
        if rec then
          rec.present = true
          rec.lastRemaining = remaining
          rec.synthetic = false   -- аура реально на юните, триггер больше не нужен
        end
      end
    end
  end

  -- Проверяем активные дебаффы на игроке и цели
  local debuffCountRaw = nil
  if unitType == "player" or unitType == "target" then
    -- Получаем все активные дебаффы на юните
    debuffCountRaw = api.Unit:UnitDeBuffCount(unitType)
    local debuffCount = debuffCountRaw or 0
    for i = 1, debuffCount do
      local debuff = api.Unit:UnitDeBuff(unitType, i)

      -- Проверяем, существует ли дебафф и есть ли у него идентификатор
      if debuff and debuff.buff_id then
        debuff.buff_id = helpers.formatBuffId(debuff.buff_id)
        -- Записываем текущие ID дебаффов для последующего сравнения
        currentBuffsOnUnit[debuff.buff_id] = true
        if auraNow then auraNow[tostring(debuff.buff_id)] = { stack = debuff.stack } end

        -- Проверяем, нужно ли отслеживать этот дебафф
        if BuffsToTrack.ShouldTrackBuff(debuff.buff_id, unitType) then
          activeBuffsOnUnit[debuff.buff_id] = true

          local entry = buffDataTable[debuff.buff_id]
          local remaining = debuff.timeLeft
          local prevRemaining = entry and entry.lastRemaining
          local isNewDebuff = (not entry) or (not entry.present)
          local refreshed = (prevRemaining ~= nil) and (remaining ~= nil)
            and (remaining > prevRemaining + 1000)
          local toaMs = (tonumber(entry and entry.timeOfAction) or 0) * 1000
          local now = getCurrentTime()
          local anchorNow = (unitType ~= "target")
          local triggeredAnchor = entry and entry.synthetic and entry.fixedTime
            and (now - entry.fixedTime) < ((tonumber(entry.timeOfAction) or 0) + 5)

          if (isNewDebuff or refreshed) and not triggeredAnchor then
            if anchorNow then
              -- Якорь — момент обнаружения (кулдаун от применения, не от длительности)
              setBuffStatus(debuff.buff_id, "active", now, unitType, nil)
            else
              -- Дебафф уже висел до того, как мы его увидели — оцениваем старт по остатку
              setBuffStatus(debuff.buff_id, "active", now, unitType, remaining)
            end
            hasChanges = true

            -- Обновляем кэшированный статус
            cachedBuffStatus[debuff.buff_id] = "active"

            -- Запоминаем бафф для текущей цели (для отслеживания истории)
            if unitType == "target" and currentTargetId then
              if not targetActiveBuffs[currentTargetId] then
                targetActiveBuffs[currentTargetId] = {}
              end
              targetActiveBuffs[currentTargetId][debuff.buff_id] = true
            end
          end

          local rec = buffDataTable[debuff.buff_id]
          if rec then
            rec.present = true
            rec.lastRemaining = remaining
            rec.synthetic = false
          end
        end
      end
    end
  end

  -- Эффективные КД: снимок видимых модификаторов + reset-проки по аурам цели
  if unitType == "target" and auraNow and settings and settings.effectiveCd then
    local resets = EffectiveCD.OnTargetAuras(currentTargetId, auraNow)
    for _, r in ipairs(resets or {}) do
      markTargetTreeReady(currentTargetId, r.tree,
        "proc " .. tostring(r.name) .. " (" .. tostring(r.id) .. ")")
    end
  end

  -- ===== Mirror: ауру читаем с player, показываем на текущем target =====
  -- Включено кнопкой Mir у записи в Tracked entries (список Target).
  -- Лог не используем: атрибуция — тот, кто является целью в момент наложения.
  local mirrorCfg = (settings and settings.target) and settings.target.mirror or nil
  local hasMirror = false
  if type(mirrorCfg) == "table" then
    for _ in pairs(mirrorCfg) do hasMirror = true break end
  end
  if unitType == "target" and hasMirror then
    local pById, pByName = {}, {}
    local function scanPlayerAuras(countFn, getFn)
      local n = countFn("player") or 0
      for i = 1, n do
        local b = getFn("player", i)
        if b and b.buff_id then
          local id = helpers.formatBuffId(b.buff_id)
          local rec = { id = id, timeLeft = b.timeLeft, stack = b.stack }
          pById[tostring(id)] = rec
          local nm = BuffList.GetBuffName(id)
          if type(nm) == "string" and nm ~= "" then pByName[nm] = rec end
        end
      end
    end
    pcall(scanPlayerAuras,
      function(u) return api.Unit:UnitBuffCount(u) end,
      function(u, i) return api.Unit:UnitBuff(u, i) end)
    pcall(scanPlayerAuras,
      function(u) return api.Unit:UnitDeBuffCount(u) end,
      function(u, i) return api.Unit:UnitDeBuff(u, i) end)

    for _, mirrorId in ipairs(trackedBuffIds) do
      local key = tostring(mirrorId)
      if settings.target.mirror[key] and not activeBuffsOnUnit[mirrorId] then
        local aura = pById[key]
        if not aura then
          local cb = findCustomBuff and findCustomBuff(mirrorId)
          local nm = (cb and cb.name) or BuffList.GetBuffName(mirrorId)
          if type(nm) == "string" and nm ~= "" then aura = pByName[nm] end
        end
        if not aura then
          mirrorTargetByBuff[mirrorId] = nil
        end
        if aura then
          local boundTarget = mirrorTargetByBuff[mirrorId]
          if boundTarget == nil and currentTargetId ~= nil then
            boundTarget = currentTargetId
            mirrorTargetByBuff[mirrorId] = boundTarget
          end
          local sameTarget = boundTarget ~= nil and currentTargetId ~= nil
            and tostring(boundTarget) == tostring(currentTargetId)
          if not sameTarget then
            -- зеркало прикреплено к другой цели: с панели убираем, ауру не трогаем
            aura = nil
          end
        end
        if aura then
          activeBuffsOnUnit[mirrorId] = true
          currentBuffsOnUnit[mirrorId] = true
          local entry = buffDataTable[mirrorId]
          local remaining = aura.timeLeft
          local prevRemaining = entry and entry.lastRemaining
          local isNewMirror = (not entry) or (not entry.present)
          local refreshedMirror = prevRemaining ~= nil and remaining ~= nil
            and remaining > prevRemaining + 1000
          if isNewMirror or refreshedMirror then
            local now = getCurrentTime()
            setBuffStatus(mirrorId, "active", now, unitType, remaining)
            hasChanges = true
            cachedBuffStatus[mirrorId] = "active"
            if currentTargetId then
              if not targetActiveBuffs[currentTargetId] then
                targetActiveBuffs[currentTargetId] = {}
              end
              targetActiveBuffs[currentTargetId][mirrorId] = true
            end
          end
          local rec = buffDataTable[mirrorId]
          if rec then
            rec.present = true
            rec.lastRemaining = remaining
            rec.synthetic = false
            rec.mirrored = true
          end
        end
      end
    end
  end

  -- Обновляем кэшированные баффы юнита
  if unitType == "player" then
    cachedPlayerBuffs = currentBuffsOnUnit
  else
    cachedMountBuffs = currentBuffsOnUnit
  end

  -- Можно ли доверять «пустому» списку баффов в этом опросе:
  -- API ответил числом, юнит жив/существует, и либо на юните есть баффы, либо юнит
  -- доступен, либо это маунт (пет мог быть отпущен). В загрузке/без мира не обрываем таймеры.
  local unitIdNow = api.Unit:GetUnitId(unitType)
  local healthNow = api.Unit:UnitHealth(unitType)
  local listReadable = (buffCountRaw ~= nil) and (healthNow ~= nil)
  if unitType == "player" or unitType == "target" then
    listReadable = listReadable and (debuffCountRaw ~= nil)
  end
  local disappearanceValid = listReadable and (buffCount > 0 or unitIdNow ~= nil or unitType == "playerpet")

  -- Проверяем баффы, которые были активны, но больше не существуют
  local currentTime = tonumber(getCurrentTime()) or 0

  for buffId, buffInfo in pairs(buffDataTable) do
    if currentBuffsOnUnit[buffId] then
      -- Бафф на юните: сбрасываем счётчик пропусков.
      -- Повторно активировать здесь нельзя: аура может висеть дольше настроенной
      -- длительности, и тогда статус уже cooldown/ready — он должен остаться.
      buffInfo.missingCount = 0
    else
      -- Бафф исчез: подтверждаем двумя читаемыми опросами подряд.
      -- Невалидные опросы (загрузка, юнит недоступен) счётчик не накручивают.
      if disappearanceValid then
        buffInfo.missingCount = (buffInfo.missingCount or 0) + 1
      end
      if disappearanceValid and buffInfo.missingCount >= 2 then
        -- Записи о присутствии больше нет: следующее появление = новая активация
        buffInfo.present = false
        buffInfo.lastRemaining = nil
        if buffInfo.status == "active" and not buffInfo.synthetic then
          -- Досрочное снятие (диспел/смерть) или конец действия:
          -- активная фаза заканчивается СЕЙЧАС, а кулдаун считается от старта баффа.
          buffInfo.activeUntil = currentTime
          buffInfo.permanent = false
          buffInfo.status = checkBuffStatus(buffInfo, currentTime)
          buffInfo.statusChangeTime = currentTime
          hasChanges = true
          cachedBuffStatus[buffId] = buffInfo.status
        end
      end
      -- Таймерная часть статуса (cooldown/ready)
      if buffInfo.status ~= "active" then
        if buffInfo.fixedTime then
          local expectedStatus = checkBuffStatus(buffInfo, currentTime)
          if expectedStatus ~= buffInfo.status then
            setBuffStatus(buffId, expectedStatus, currentTime, unitType)
            hasChanges = true
            cachedBuffStatus[buffId] = expectedStatus
          end
        elseif buffInfo.status ~= "ready" then
          setBuffStatus(buffId, "ready", nil, unitType)
          hasChanges = true
          cachedBuffStatus[buffId] = "ready"
        end
      end
    end
  end


  -- Показываем окно только если есть отслеживаемые баффы и если отслеживание разрешено в настройках
  local hasBuffs = false
  for _ in pairs(buffDataTable) do
      hasBuffs = true
      break
  end

  if hasBuffs and unitSettings.enabled then
    -- Канвасы создаём по числу записей в настройках (и освобождаем лишние).
    local canvasJustCreated = ensureUnitCanvases(unitType)

    -- For target, update cache and display data after processing
    if unitType == "target" and currentTargetId then
      -- Update cache with current buff states
      if targetCache[currentTargetId] then
        targetCache[currentTargetId].buffStates = {}
        for buffId, buffInfo in pairs(targetBuffData) do
          targetCache[currentTargetId].buffStates[buffId] = {
            fixedTime = buffInfo.fixedTime,
            activeUntil = buffInfo.activeUntil,
            readyAt = buffInfo.readyAt,
            permanent = buffInfo.permanent,
            synthetic = buffInfo.synthetic,
            status = buffInfo.status,
            timeOfAction = buffInfo.timeOfAction,
            cooldown = buffInfo.cooldown,
            name = buffInfo.name,
            icon = buffInfo.icon
          }
        end
      end

      -- Update cached display data
      cachedTargetDisplayData = {}
      for buffId, buffInfo in pairs(targetBuffData) do
        cachedTargetDisplayData[buffId] = {
          name = buffInfo.name,
          icon = buffInfo.icon,
          cooldown = buffInfo.cooldown,
          timeOfAction = buffInfo.timeOfAction,
          fixedTime = buffInfo.fixedTime,
          activeUntil = buffInfo.activeUntil,
          readyAt = buffInfo.readyAt,
          permanent = buffInfo.permanent,
          status = buffInfo.status
        }
      end
    end

    -- Update icons if there were changes or if canvas was just created
    if hasChanges or canvasJustCreated then
      updateBuffIcons(unitType)
    end
  end
end

-- Скан тултипов баффов: id -> name -> icon path.
-- api.Skill:GetSkillTooltip жёстко вызывает SIK_DESCRIPTION и отдаёт только
-- описание (name/path = nil), поэтому иконки берём из базы баффов — у большинства
-- навыков бафф одноимённый. Дамп пишется в buff_dump.tbl и переиспользуется.
local buffIconScan = nil
local buffDump = nil

local function normalizeSkillName(s)
  s = tostring(s or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

local function normalizeTexturePath(p)
  p = tostring(p or "")
  p = p:gsub("[\r\n]+$", "")
  p = p:gsub("^%s+", ""):gsub("%s+$", "")
  p = p:gsub("\\", "/")
  p = p:gsub("^Game/", "game/")
  p = p:gsub("/+$", "")
  return p
end

local function addDumpEntry(byName, id, name, path)
  path = normalizeTexturePath(path)
  if path == "" then return end
  local function put(k)
    if k ~= "" and not byName[k] then
      byName[k] = { id = tonumber(id), path = path, name = name }
    end
  end
  local key = normalizeSkillName(name)
  put(key)
  -- баффы часто названы "X (Rank N)" — индексируем и базовое имя
  local base = name:gsub("%s*%(%s*[Rr]ank%s*%d+%s*%)%s*$", "")
  if base ~= name then
    local bkey = normalizeSkillName(base)
    if bkey ~= key then put(bkey) end
  end
end

local function readDumpFile(path)
  local ok, data = pcall(api.File.Read, api.File, path)
  if ok and type(data) == "table" and type(data.dump) == "string" and #data.dump > 0 then
    return data, path
  end
  return nil
end

local function buildDumpList(entries)
  local list = {}
  for i = 1, #entries do
    local e = entries[i]
    if e and e.name and e.name ~= "" and e.path and e.path ~= "" then
      list[#list + 1] = e
    end
  end
  table.sort(list, function(a, b)
    local x = tostring(a.name):lower()
    local y = tostring(b.name):lower()
    if x == y then return tostring(a.id) < tostring(b.id) end
    return x < y
  end)
  return list
end

local function loadBuffDump()
  if not (api.File and api.File.Read) then return end
  -- дамп живёт в папке аддона; корень Addon читаем только как наследие старых версий
  local data, usedPath = readDumpFile("CooldawnBuffTracker/buff_dump.tbl")
  if not data then
    data, usedPath = readDumpFile("buff_dump.tbl")
  end
  if not data then return end
  local byName = {}
  local entries = {}
  local n = 0
  for line in data.dump:gmatch("[^\n]+") do
    local id, name, path = line:match("^(%d+)\t([^\t]*)\t(.*)$")
    if id and name and path and path ~= "" then
      n = n + 1
      addDumpEntry(byName, id, name, path)
      entries[#entries + 1] = { id = tonumber(id), name = name, path = normalizeTexturePath(path) }
    end
  end
  if n > 0 then
    buffDump = { byName = byName, list = buildDumpList(entries), count = n }
    safeLog("[CBT] buff dump: " .. n .. " buffs loaded from " .. tostring(usedPath))
  end
end

-- Проставляет иконки кастомным баффам по имени из дампа (только там, где иконки нет)
local function applyDumpToCustomBuffs()
  if not (buffDump and settings.customBuffs) then return 0 end
  local changed = 0
  for _, cb in ipairs(settings.customBuffs) do
    local key = normalizeSkillName(cb.spellName)
    if key ~= "" and (not cb.iconFile or cb.iconFile == "") then
      local e = buffDump.byName[key]
      if e then
        cb.iconFile = e.path
        changed = changed + 1
        local tables = { buffData, playerBuffData, targetBuffData }
        for _, tbl in pairs(tables) do
          local entry = tbl[cb.id]
          if entry then entry.icon = e.path end
        end
        for _, cache in pairs(targetCache) do
          if cache.buffStates and cache.buffStates[cb.id] then
            cache.buffStates[cb.id].icon = e.path
          end
        end
        safeLog("[CBT] icon from dump: " .. tostring(cb.spellName) .. " -> " .. e.path)
      end
    end
  end
  if changed > 0 then
    pcall(function() api.SaveSettings() end)
  end
  return changed
end

local function applyBuffIcon(nameKey, id, path)
  path = normalizeTexturePath(path)
  local applied = 0
  for _, cb in ipairs(settings.customBuffs or {}) do
    if normalizeSkillName(cb.spellName) == nameKey then
      cb.iconFile = path
      applied = applied + 1
      local tables = { buffData, playerBuffData, targetBuffData }
      for _, tbl in pairs(tables) do
        local entry = tbl[cb.id]
        if entry then entry.icon = path end
      end
      for _, cache in pairs(targetCache) do
        if cache.buffStates and cache.buffStates[cb.id] then
          cache.buffStates[cb.id].icon = path
        end
      end
    end
  end
  if applied > 0 then
    pcall(function() api.SaveSettings() end)
  end
  if settingsPage and settingsPage.onSkillIconFound then
    pcall(settingsPage.onSkillIconFound, nameKey, id, path)
  end
  safeLog("[CBT] buff dump: '" .. nameKey .. "' -> id=" .. tostring(id)
    .. " path=" .. tostring(path) .. " (entries updated: " .. applied .. ")")
end

local function startBuffIconScan(name)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local key = normalizeSkillName(name)
  if key ~= "" and buffDump and buffDump.byName[key] then
    local e = buffDump.byName[key]
    applyBuffIcon(key, e.id, e.path)
    return true
  end
  if not (api.Ability and api.Ability.GetBuffTooltip) then return false end
  buffIconScan = {
    target = key,
    rangeIndex = 1,
    ranges = { { 1, 50000 }, { 8000000, 8001000 } },
    nextId = 1,
    entries = {},
    tables = 0,
    named = 0,
    errors = 0,
    firstError = nil,
  }
  safeLog("[CBT] buff scan: dumping all buffs"
    .. (key ~= "" and (" + search '" .. name .. "'") or "")
    .. " (1..50000, 8000000..8001000)")
  return true
end

-- Кросс-модульная точка: settings_page не видит глобалы main (приватное окружение)
if settingsPage then
  settingsPage.startScan = startBuffIconScan
end

-- Поиск по базе баффов для окна «Поиск иконки» (живой фильтр по имени)
local function searchIcons(query, limit)
  if not (buffDump and buffDump.list) then return {} end
  local q = normalizeSkillName(query)
  local out = {}
  local max = limit or 100
  for i = 1, #buffDump.list do
    local e = buffDump.list[i]
    if q == "" or string.find(string.lower(tostring(e.name)), q, 1, true) then
      out[#out + 1] = { name = e.name, path = e.path, id = e.id }
      if #out >= max then break end
    end
  end
  return out
end

-- Активные баффы/дебаффы юнита для окна Record
local function getActiveBuffs(unitType)
  unitType = unitType or "player"
  local out = {}
  local seen = {}
  local bc = api.Unit:UnitBuffCount(unitType) or 0
  for i = 1, bc do
    local b = api.Unit:UnitBuff(unitType, i)
    if b and b.buff_id then
      local id = helpers.formatBuffId(b.buff_id)
      if not seen[id] then
        seen[id] = true
        out[#out + 1] = {
          id = id,
          name = BuffList.GetBuffName(id),
          icon = b.path or BuffList.GetBuffIcon(id),
          remaining = b.timeLeft,
          kind = "buff",
        }
      end
    end
  end
  local dc = api.Unit:UnitDeBuffCount(unitType) or 0
  for i = 1, dc do
    local b = api.Unit:UnitDeBuff(unitType, i)
    if b and b.buff_id then
      local id = helpers.formatBuffId(b.buff_id)
      if not seen[id] then
        seen[id] = true
        out[#out + 1] = {
          id = id,
          name = BuffList.GetBuffName(id),
          icon = b.path or BuffList.GetBuffIcon(id),
          remaining = b.timeLeft,
          kind = "debuff",
        }
      end
    end
  end
  return out
end

-- Очистка журнала навыков (кнопка Clear log в окне Record)
local function clearLoggedSpells()
  for i = #loggedSpellOrder, 1, -1 do
    loggedSpellOrder[i] = nil
  end
  for k in pairs(loggedSpellMap) do
    loggedSpellMap[k] = nil
  end
end

-- Навыки из боевого лога (свежие сверху) для окна Record
local function getLoggedSpells(limit)
  local out = {}
  for i = #loggedSpellOrder, 1, -1 do
    local e = loggedSpellMap[loggedSpellOrder[i]]
    if e then
      out[#out + 1] = { name = e.name, count = e.count, last = e.last }
    end
    if #out >= (limit or 50) then break end
  end
  return out
end

-- Иконка из дампа по имени (для баффов/навыков, добавленных из лога)
local function findIconByName(name)
  if not (buffDump and buffDump.byName) then return nil end
  local key = normalizeSkillName(name)
  local e = buffDump.byName[key]
  if e then return e.path end
  return nil
end

-- ===== Effective CDs: перманентные записи пикера (1.21.0) =====
-- Отметка навыка в окне Effective CDs создаёт постоянную запись customBuffs
-- (CD/иконка/ветвь из skillsets.tbl) и сразу ставит её на выбранный Target-канвас.
-- Снятие отметки — единственный способ удалить такую запись.

local function isSkillPicked(name)
  local key = tostring(name or "")
  if key == "" then return false end
  local s = api.GetSettings("CooldawnBuffTracker") or settings or {}
  for _, cb in ipairs(s.customBuffs or {}) do
    if cb and tostring(cb.id) == key and cb.permanent then return true end
  end
  return false
end

local function pickEffectiveSkill(skill)
  if type(skill) ~= "table" or not skill.name or skill.name == "" then
    return false, "Invalid skill"
  end
  local s = api.GetSettings("CooldawnBuffTracker") or settings or {}
  s.customBuffs = s.customBuffs or {}
  local id = tostring(skill.name)

  local entry = nil
  for _, cb in ipairs(s.customBuffs) do
    if tostring(cb.id) == id then entry = cb; break end
  end
  if not entry then
    entry = {
      id = id,
      name = skill.name,
      spellName = skill.name,
      cooldown = tonumber(skill.cd) or 0,
      timeOfAction = 0,
      iconFile = skill.icon,
      tree = skill.tree,
      permanent = true,
      effective = true,
    }
    table.insert(s.customBuffs, entry)
  else
    entry.permanent = true
    entry.effective = true
    entry.cooldown = tonumber(skill.cd) or entry.cooldown or 0
    if skill.tree and skill.tree ~= "" then entry.tree = skill.tree end
    if skill.icon and skill.icon ~= "" then entry.iconFile = skill.icon end
    if not entry.spellName or entry.spellName == "" then entry.spellName = skill.name end
  end

  -- Сразу в трекинг Target на выбранный канвас (эффективный КД только для цели)
  local tgt = s.target
  if tgt then
    tgt.trackedBuffs = tgt.trackedBuffs or {}
    tgt.canvasOf = tgt.canvasOf or {}
    local found = false
    for _, v in ipairs(tgt.trackedBuffs) do
      if tostring(v) == id then found = true; break end
    end
    if not found then table.insert(tgt.trackedBuffs, id) end
    tgt.canvasOf[id] = tonumber(tgt.selectedCanvas) or 1
    -- панель Target должна быть включена, иначе выбранный навык негде показать
    tgt.enabled = true
  end

  api.SaveSettings()
  initBuffData()
  api:Emit("ADDON_CBT_BUFFS_CHANGED")
  if settingsPage and settingsPage.refreshFromExternal then
    pcall(settingsPage.refreshFromExternal)
  end
  safeLog("[CBT] effCD: picked " .. id .. " (" .. tostring(skill.tree) .. ", CD "
    .. tostring(entry.cooldown) .. ")")
  return true, "Tracking " .. id
end

local function unpickEffectiveSkill(name)
  local id = tostring(name or "")
  if id == "" then return false, "Invalid skill" end
  local s = api.GetSettings("CooldawnBuffTracker") or settings or {}
  local removed = false
  if type(s.customBuffs) == "table" then
    for i = #s.customBuffs, 1, -1 do
      local cb = s.customBuffs[i]
      if cb and tostring(cb.id) == id and cb.permanent then
        table.remove(s.customBuffs, i)
        removed = true
      end
    end
  end
  if not removed then return false, "Not a permanent entry" end

  for _, unitType in ipairs(UNIT_TYPES) do
    local u = s[unitType]
    if type(u) == "table" then
      if type(u.trackedBuffs) == "table" then
        for i = #u.trackedBuffs, 1, -1 do
          if tostring(u.trackedBuffs[i]) == id then table.remove(u.trackedBuffs, i) end
        end
      end
      if type(u.canvasOf) == "table" then u.canvasOf[id] = nil end
      if type(u.mirror) == "table" then u.mirror[id] = nil end
    end
  end
  targetBuffData[id] = nil
  playerBuffData[id] = nil
  buffData[id] = nil
  for _, cache in pairs(targetCache) do
    if cache.buffStates then cache.buffStates[id] = nil end
  end

  api.SaveSettings()
  initBuffData()
  api:Emit("ADDON_CBT_BUFFS_CHANGED")
  if settingsPage and settingsPage.refreshFromExternal then
    pcall(settingsPage.refreshFromExternal)
  end
  safeLog("[CBT] effCD: unpicked " .. id)
  return true, "Removed " .. id
end

local function toggleEffectiveSkill(skill, checked)
  if checked then
    return pickEffectiveSkill(skill)
  end
  return unpickEffectiveSkill(skill and skill.name)
end

local function reloadEffectiveTables()
  local c, s, m = EffectiveCD.LoadTables()
  return string.format("Tables reloaded: %d classes, %d skills, %d mods", c or 0, s or 0, m or 0)
end

if settingsPage then
  settingsPage.searchIcons = searchIcons
  settingsPage.applyBuffOverride = applyBuffOverride
  settingsPage.getActiveBuffs = getActiveBuffs
  settingsPage.getLoggedSpells = getLoggedSpells
  settingsPage.clearLoggedSpells = clearLoggedSpells
  settingsPage.findIconByName = findIconByName
  settingsPage.openEffectiveCdWindow = function() EffectivePicker.open() end
  settingsPage.resetEffectiveLearning = function()
    return EffectiveCD.ResetLearning()
  end
  settingsPage.skillInfo = function(name) return EffectiveCD.SkillInfo(name) end
end

EffectivePicker.setHooks({
  trees = function() return EffectiveCD.TreeList() end,
  skillsForTree = function(tree) return EffectiveCD.SkillsForTree(tree) end,
  isPicked = isSkillPicked,
  onToggle = toggleEffectiveSkill,
  onReload = reloadEffectiveTables,
})

local function processBuffIconScan()
  if not buffIconScan then return end
  local st = buffIconScan
  local r = st.ranges[st.rangeIndex]
  if not r then
    -- Скан закончен: сохраняем дамп и применяем найденное
    local text = table.concat(st.entries, "\n")
    local saved = false
    if api.File and api.File.Write then
      saved = pcall(api.File.Write, api.File, "CooldawnBuffTracker/buff_dump.tbl",
        { version = 1, count = #st.entries, dump = text })
    end
    local byName = {}
    local entries = {}
    for _, line in ipairs(st.entries) do
      local id, name, path = line:match("^(%d+)\t([^\t]*)\t(.*)$")
      if id and name and path and path ~= "" then
        addDumpEntry(byName, id, name, path)
        entries[#entries + 1] = { id = tonumber(id), name = name, path = normalizeTexturePath(path) }
      end
    end
    buffDump = { byName = byName, list = buildDumpList(entries), count = #st.entries }
    safeLog("[CBT] buff dump: " .. #st.entries .. " buffs, "
      .. (saved and "saved to buff_dump.tbl" or "NOT saved (api.File unavailable)")
      .. "; tables=" .. tostring(st.tables) .. " named=" .. tostring(st.named)
      .. " errors=" .. tostring(st.errors)
      .. (st.firstError and (" | first error: " .. st.firstError) or ""))
    if st.target ~= "" then
      local e = byName[st.target]
      if e then
        applyBuffIcon(st.target, e.id, e.path)
      else
        safeLog("[CBT] buff dump: '" .. st.target .. "' not found")
      end
    end
    if settingsPage and settingsPage.onIconDumpUpdated then
      pcall(settingsPage.onIconDumpUpdated)
    end
    buffIconScan = nil
    return
  end
  if st.nextId < r[1] then st.nextId = r[1] end
  local last = math.min(st.nextId + 150 - 1, r[2])
  local getter = api.Ability.GetBuffTooltip
  for id = st.nextId, last do
    local ok, info = pcall(getter, api.Ability, id, 1)
    if not ok then
      st.errors = st.errors + 1
      if not st.firstError then st.firstError = tostring(info) end
    elseif type(info) == "table" then
      st.tables = st.tables + 1
      if info.name then
        st.named = st.named + 1
        local nm = tostring(info.name)
        if nm ~= "" then
          st.entries[#st.entries + 1] = tostring(id) .. "\t" .. nm .. "\t"
            .. ((info.path and tostring(info.path)) or "")
        end
      end
    end
  end
  if last >= r[2] then
    st.rangeIndex = st.rangeIndex + 1
    local nr = st.ranges[st.rangeIndex]
    st.nextId = nr and nr[1] or 0
  else
    st.nextId = last + 1
  end
end

-- Отслеживание навыков маунта по расходу маны
local manaPrev = nil
local manaRegen = 0          -- единая оценка регена, мана/сек (EMA)
local manaLastSpendTime = 0  -- время последней траты; реген оцениваем только через 5с после неё
local manaTimer = 0          -- накопитель до 100 мс

-- Имя текущего маунта: UnitName может быть nil, пробуем через id
local function resolvePetName()
  local name = api.Unit:UnitName("playerpet")
  if not name or name == "" then
    local id = api.Unit:GetUnitId("playerpet")
    if id then name = api.Unit:GetUnitNameById(id) end
  end
  return name or ""
end

-- Записи-навыки маунта: у кастомной записи задан manaCost > 0
local function getManaEntries()
  local out = {}
  local ids = BuffsToTrack and BuffsToTrack.GetAllTrackedBuffIds
    and BuffsToTrack.GetAllTrackedBuffIds("playerpet") or {}
  local now = getCurrentTime()
  for _, id in ipairs(ids) do
    local cb = findCustomBuff(id)
    local cost = cb and tonumber(cb.manaCost) or nil
    if cost and cost > 0 then
      local rec = buffData[id]
      local ready = true
      if rec and rec.readyAt and now < rec.readyAt - 0.05 and rec.status ~= "ready" then
        ready = false
      end
      out[#out + 1] = {
        id = id,
        cost = cost,
        mount = (cb.mountName or ""),
        ready = ready
      }
    end
  end
  return out
end

-- Опрос маны маунта: реген оцениваем эмпирически (в бою/вне боя), траты ищем по дельте
local function pollMountMana(dtSec)
  if not settings or not settings.playerpet then return end
  local hasMana = false
  for _, cb in ipairs(settings.customBuffs or {}) do
    if tonumber(cb.manaCost) and tonumber(cb.manaCost) > 0 then hasMana = true break end
  end
  if not hasMana then manaPrev = nil; return end
  local mana = api.Unit:UnitMana("playerpet")
  local maxMana = api.Unit:UnitMaxMana("playerpet")
  if not mana or not maxMana or maxMana <= 0 then
    manaPrev = nil
    manaLastSpendTime = 0
    return
  end
  if manaPrev == nil then
    manaPrev = mana
    manaLastSpendTime = 0
    return
  end
  local dt = (dtSec and dtSec > 0) and dtSec or 0.1
  local delta = mana - manaPrev

  -- Реген: единая оценка; обновляем только спустя 5с после последней траты
  -- и только на положительных приращениях не на полной мане.
  local now = getCurrentTime()
  if delta > 0 and mana < maxMana * 0.995
     and (now - manaLastSpendTime) >= 5 then
    local rate = delta / dt
    if rate < maxMana * 0.5 then
      manaRegen = manaRegen * 0.85 + rate * 0.15
    end
  end

  -- Трата: отрицательная дельта; возвращаем к ней реген за интервал
  if delta < -2 then
    manaLastSpendTime = now
    local regen = manaRegen or 0
    local spend = -delta + (regen or 0) * dt
    local entries = getManaEntries()
    if #entries > 0 then
      local petName = resolvePetName()
      local petKey = petName:lower()
      local best, bestDiff = nil, nil
      local blockedByMount, blockedByCd = 0, 0
      for _, e in ipairs(entries) do
        local em = (e.mount or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
        -- пустое имя = любой маунт; если имя пета неизвестно — не блокируем
        local mountOk = (em == "" or petKey == "" or em == petKey
          or petKey:find(em, 1, true) ~= nil)
        local tol = math.max(3, e.cost * 0.2)
        local diff = math.abs(spend - e.cost)
        if not mountOk then
          blockedByMount = blockedByMount + 1
        elseif not e.ready then
          blockedByCd = blockedByCd + 1
        elseif diff <= tol and (bestDiff == nil or diff < bestDiff) then
          best, bestDiff = e, diff
        end
      end
      if best then
        setBuffStatus(best.id, "active", getCurrentTime(), "playerpet", nil)
        if buffData[best.id] then buffData[best.id].synthetic = true end
        if settings.debugBuffId then
          safeLog(string.format("[CBT] mana cast %s cost=%s spend=%.1f regen=%.1f mount=%s",
            tostring(best.id), tostring(best.cost), spend, regen or 0, petName))
        end
      elseif settings.debugBuffId then
        local detail = {}
        for _, e in ipairs(entries) do
          detail[#detail + 1] = string.format("%s(mount=%s,ready=%s)",
            tostring(e.cost), tostring(e.mount), tostring(e.ready))
        end
        safeLog(string.format("[CBT] mana drop %.1f (regen %.1f) — no match; pet='%s'; mount-blocked=%d cd-blocked=%d; entries: %s",
          spend, regen or 0, petName, blockedByMount, blockedByCd, table.concat(detail, " | ")))
      end
    end
  end

  manaPrev = mana
end

-- Debug: непрерывная запись аур таргета (100 мс). Ловит короткие баффы.
local debugAuraState = {}
local debugAuraTarget = nil
local debugAuraTimer = 0
local debugAuraNames = {}
local debugAuraLines = {}
local debugAuraFlushTimer = 0
local debugAuraDirty = false
local debugWasOn = false
local AURA_DUMP_PATH = "CooldawnBuffTracker/aura_dump.tbl"

local function debugRecord(line)
  if #debugAuraLines > 20000 then table.remove(debugAuraLines, 1) end
  debugAuraLines[#debugAuraLines + 1] = string.format("%.1f %s",
    tonumber(getCurrentTime()) or 0, tostring(line))
  debugAuraDirty = true
end

local function flushAuraDump()
  if not debugAuraDirty then return end
  debugAuraDirty = false
  local ok = pcall(function()
    api.File:Write(AURA_DUMP_PATH, { dump = table.concat(debugAuraLines, "\n") })
  end)
  if not ok then safeLog("[CBT] aura dump: write failed") end
end

local function debugAuraName(buffId)
  local nm = debugAuraNames[buffId]
  if nm ~= nil then return nm end
  nm = BuffList.GetBuffName(buffId)
  if not nm or nm == "" then
    local ok, tip = pcall(api.Ability.GetBuffTooltip, api.Ability, buffId, 1)
    if ok and type(tip) == "table" then nm = tip.name end
  end
  nm = tostring(nm or "")
  debugAuraNames[buffId] = nm
  return nm
end

local function logTargetClass()
  local id = api.Unit:GetUnitId("target")
  debugRecord("[target] id=" .. tostring(id) .. " name=" .. tostring(api.Unit:UnitName("target")))
  debugRecord("[class] UnitClass=" .. tostring(api.Unit:UnitClass("target"))
    .. " GetUnitClassName=" .. tostring(api.Ability:GetUnitClassName("target")))
  if not id then return end
  local ok, info = pcall(api.Unit.GetUnitInfoById, api.Unit, id)
  if ok and type(info) == "table" and type(info.class) == "table" then
    local parts = {}
    for k, v in pairs(info.class) do
      local nm = ""
      local ok2, n2 = pcall(api.Ability.GetSkillsetNameById, api.Ability, v)
      if ok2 then nm = tostring(n2) end
      parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) .. "(" .. nm .. ")"
    end
    debugRecord("[class] " .. table.concat(parts, " "))
  end
end

local function watchTargetAuras()
  local id = api.Unit:GetUnitId("target")
  if tostring(id) ~= tostring(debugAuraTarget) then
    debugAuraTarget = id
    debugAuraState = {}
    logTargetClass()
  end
  if not id then return end

  local now = {}
  local function scan(kind, countFn, getFn)
    local n = countFn("target") or 0
    for i = 1, n do
      local b = getFn("target", i)
      if b and b.buff_id then
        local key = tostring(b.buff_id)
        now[key] = { stack = tonumber(b.stack) or 0, kind = kind }
        local prev = debugAuraState[key]
        if not prev then
          debugRecord(string.format("+ %s id=%s name=%s stack=%s time=%s",
            kind, key, debugAuraName(b.buff_id), tostring(b.stack), tostring(b.timeLeft)))
        elseif prev.stack ~= now[key].stack then
          debugRecord(string.format("~ %s id=%s name=%s stack=%s time=%s",
            kind, key, debugAuraName(b.buff_id), tostring(b.stack), tostring(b.timeLeft)))
        end
      end
    end
  end
  pcall(scan, "buff", function(u) return api.Unit:UnitBuffCount(u) end,
    function(u, i) return api.Unit:UnitBuff(u, i) end)
  pcall(scan, "debuff", function(u) return api.Unit:UnitDeBuffCount(u) end,
    function(u, i) return api.Unit:UnitDeBuff(u, i) end)

  for key, prev in pairs(debugAuraState) do
    if not now[key] then
      debugRecord(string.format("- %s id=%s name=%s", prev.kind, key, debugAuraName(tonumber(key) or key)))
    end
  end
  debugAuraState = now
end

local function OnUpdate(dt)
  if not live then return end
  processBuffIconScan()
  -- Мастер-выключатель из списка аддонов (ESC-меню), поле settings.enabled
  if settings and settings.enabled == false then
    hideAllCanvases()
    return
  end
  -- Мана маунта: сэмплим чаще, чем баффы (100 мс), чтобы не терять мелкие траты
  manaTimer = manaTimer + dt
  if manaTimer >= 100 then
    local step = manaTimer / 1000
    manaTimer = 0
    pollMountMana(step)
  end

  if settings and settings.debugBuffId then
    if not debugWasOn then
      debugWasOn = true
      debugAuraLines = {}
      debugAuraState = {}
      debugAuraTarget = nil
      debugAuraDirty = true
      debugRecord("[session] aura dump started")
      flushAuraDump()
      safeLog("[CBT] aura dump -> " .. AURA_DUMP_PATH)
    end
    debugAuraTimer = debugAuraTimer + dt
    if debugAuraTimer >= 100 then
      debugAuraTimer = 0
      watchTargetAuras()
    end
    debugAuraFlushTimer = debugAuraFlushTimer + dt
    if debugAuraFlushTimer >= 1000 then
      debugAuraFlushTimer = 0
      flushAuraDump()
    end
  else
    if debugWasOn then
      flushAuraDump()
      debugWasOn = false
    end
    debugAuraState = {}
    debugAuraTarget = nil
    debugAuraTimer = 0
  end

  updateTimer = updateTimer + dt
  if updateTimer >= updateInterval then
    checkBuffs("playerpet")  -- Проверяем баффы маунта
    checkBuffs("player")     -- Проверяем баффы игрока
    checkBuffs("target")     -- Проверяем баффы target
    updateTimer = 0
  end

  refreshUITimer = refreshUITimer + dt
  if refreshUITimer >= refreshUIInterval then
    for _, unitType in ipairs(UNIT_TYPES) do
      if #(unitCanvases[unitType] or {}) > 0 then
        updateBuffIcons(unitType)
      end
    end

    -- Обновляем отладчик баффов, если он существует
    if BuffDebugger and BuffDebugger.Update then
      BuffDebugger.Update({
        playerCanvas = unitCanvases.player[1],
        mountCanvas = unitCanvases.playerpet[1],
        targetCanvas = unitCanvases.target[1],
        currentTime = getCurrentTime()
      })
    end

    refreshUITimer = 0
  end

  -- Target cache cleanup timer
  targetCacheCleanupTimer = targetCacheCleanupTimer + dt
  if targetCacheCleanupTimer >= targetCleanupInterval * 1000 then -- Convert to milliseconds
    cleanupTargetCache()
    targetCacheCleanupTimer = 0
  end
end

-- Определяем функции инициализации интерфейса
local function initializeUI()
  -- Проверяем необходимость отображения панелей каждого юнита.
  -- Note: target canvases should NOT be created at initialization - only when target exists
  local unitTypes = {"playerpet", "player"}

  for _, unitType in ipairs(unitTypes) do
    local shouldShowUI = hasTrackedBuffs(unitType)
    safeLog("[CBT] UI initialization for " .. unitType .. ": " .. (shouldShowUI and "show" or "hide"))

    if shouldShowUI then
      local created = ensureUnitCanvases(unitType)
      if created or #(unitCanvases[unitType] or {}) > 0 then
        updateBuffIcons(unitType)
      else
        safeLog("[CBT] Error creating canvases for " .. unitType)

        -- Повторная попытка создания канвасов с задержкой
        api:DoIn(1000, function()
          if not live then return end
          local retryCreated = ensureUnitCanvases(unitType)
          if retryCreated or #(unitCanvases[unitType] or {}) > 0 then
            updateBuffIcons(unitType)
          else
            safeLog("[CBT] Repeated error creating canvases for " .. unitType)
          end
        end)
      end
    end
  end
end

local function onCombatMessage(event, ...)
  if not live then return end
  if event ~= "COMBAT_MSG" then return end
  local args = { ... }
  local combatEvent = args[2]
  if type(combatEvent) ~= "string" then return end
  local ok, parsed = pcall(ParseCombatMessage, combatEvent, unpack(args, 5))
  if not ok or type(parsed) ~= "table" then return end
  if settings and settings.debugBuffId then
    safeLog(string.format("[CBT] msg %s src=%s tgt=%s spell=%s id=%s",
      tostring(combatEvent), tostring(args[3]), tostring(args[4]),
      tostring(parsed.spellName), tostring(parsed.spellId)))
  end
  if parsed.spellName then
    recordLoggedSpell(parsed.spellName, getCurrentTime())
    triggerSpell(parsed.spellName, args[3], parsed.spellId, args, combatEvent)
  end
end

local function OnLoad()
  -- Загружаем настройки (миграция плоских полей в canvases уже внутри)
  if helpers then
    settings = helpers.getSettings()
  else
    safeLog("[CBT] Helpers module not loaded, using basic settings")
    settings = {
      playerpet = {
        canvases = { { name = "Main", posX = defaultPositionX, posY = defaultPositionY,
          iconSize = iconSize, iconSpacing = iconSpacing, gridColumns = 10, gridRows = 1,
          maxIcons = 10, gridRowSpacing = 5, enabled = true, lockPositioning = false } },
        canvasOf = {}, selectedCanvas = 1, trackedBuffs = {}, mirror = {}, enabled = true
      },
      player = {
        canvases = { { name = "Main", posX = defaultPositionX, posY = defaultPositionY + 70,
          iconSize = iconSize, iconSpacing = iconSpacing, gridColumns = 10, gridRows = 1,
          maxIcons = 10, gridRowSpacing = 5, lockPositioning = false } },
        canvasOf = {}, selectedCanvas = 1, trackedBuffs = {}, mirror = {}, enabled = true
      },
      target = {
        canvases = { { name = "Main", posX = defaultPositionX, posY = defaultPositionY + 140,
          iconSize = iconSize, iconSpacing = iconSpacing, gridColumns = 10, gridRows = 1,
          maxIcons = 10, gridRowSpacing = 5, lockPositioning = false } },
        canvasOf = {}, selectedCanvas = 1, trackedBuffs = {}, mirror = {}, enabled = true
      }
    }
  end

  -- helpers сохраняет позиции канвасов и пересобирает панели по этим хукам
  if helpers then
    if helpers.setCanvasRegistry then helpers.setCanvasRegistry(unitCanvases) end
    if helpers.setRefreshCallback then helpers.setRefreshCallback(refreshAllCanvases) end
  end

  -- Инициализация модуля отладки баффов
  if BuffDebugger and BuffDebugger.Initialize then
    BuffDebugger.Initialize({
      playerCanvas = unitCanvases.player[1],
      mountCanvas = unitCanvases.playerpet[1],
      settings = settings
    })
  end

  -- Инициализируем данные баффов
  initBuffData()

  -- Загружаем ранее сохранённый дамп баффов (id -> name -> иконка)
  loadBuffDump()
  applyDumpToCustomBuffs()

  -- Эффективные КД: классы/навыки/модификаторы из плоских таблиц аддона.
  -- Инициализация после дампа: иконки навыков без своей колонки берутся из него.
  EffectiveCD.Initialize({
    log = safeLog,
    nameOf = function(id)
      local cb = findCustomBuff(id) or findCustomBuffByName(BuffList.GetBuffName(id))
      return (cb and cb.name) or BuffList.GetBuffName(id)
    end,
    dumpIcon = findIconByName,
  })

  -- Диагностика кастомных баффов: видно, чем они ключуются и какие CD/D у них
  if settings and settings.debugBuffId then
    for _, cb in ipairs(settings.customBuffs or {}) do
      safeLog("[CBT] custom: id=" .. tostring(cb.id)
        .. " name=" .. tostring(cb.name)
        .. " spell=" .. tostring(cb.spellName)
        .. " CD=" .. tostring(cb.cooldown)
        .. " D=" .. tostring(cb.timeOfAction))
    end
  end

  -- Расширенное ESC-меню (аддон ESCMenu): своя строка настроек
  local function openFromEscMenu()
    if settingsPage and settingsPage.openSettingsWindow then
      settingsPage.openSettingsWindow()
    end
  end
  if type(ESCMenu) == "table" and type(ESCMenu.RegisterAddonBtn) == "function" then
    pcall(ESCMenu.RegisterAddonBtn, ESCMenu, "Cooldown Buff Tracker", openFromEscMenu, "System", "optimizer")
  else
    ESCMenu = ESCMenu or {}
    ESCMenu.queue = ESCMenu.queue or {}
    table.insert(ESCMenu.queue, { name = "Cooldown Buff Tracker", callback = openFromEscMenu, category = "System" })
  end

  -- Дефолтное ESC-меню: панель «Addon Options» (конвенция michaelClient).
  -- Первый загрузившийся аддон строит панель на системном фрейме, остальные
  -- добавляют свою кнопку. Без неё наш аддон в ванильном меню не виден.
  pcall(function()
    local configMenu = ADDON:GetContent(UIC.SYSTEM_CONFIG_FRAME)
    if not configMenu then return end
    if configMenu.michaelClient == nil then
      local mc = configMenu:CreateChildWidget("label", "cbt_michaelClient", 0, true)
      mc:AddAnchor("TOPLEFT", configMenu, -110, 5)
      mc:SetExtent(110, 28)
      mc:SetText("Addon Options")
      configMenu.michaelClient = mc
      configMenu.michaelClient.addons = {}
      mc.bg = mc:CreateNinePartDrawable("ui/common/tab_list.dds", "background")
      mc.bg:SetTextureInfo("bg_quest")
      mc.bg:SetColor(0, 0, 0, 0.5)
      mc.bg:AddAnchor("TOPLEFT", mc, 0, 0)
      mc.bg:AddAnchor("BOTTOMRIGHT", mc, 0, 0)
      mc.addonCount = 0
      function configMenu.michaelClient:AddAddon(title, callback)
        if self.addons[title] then
          self.addons[title]:SetHandler("OnClick", function() callback() end)
          self.addons[title]:Show(true)
          return
        end
        self.addonCount = self.addonCount + 1
        local btn = self:CreateChildWidget("button", "cbt_addon_" .. tostring(self.addonCount), 0, true)
        btn:SetText(title)
        btn:AddAnchor("TOPLEFT", self, 5, self.addonCount * 30)
        btn:SetExtent(100, 28)
        btn:SetHandler("OnClick", function() callback() end)
        btn:Show(true)
        self.addons[title] = btn
        self.bg:SetExtent(self.bg:GetWidth(), self.addonCount * 30)
        self.bg:RemoveAllAnchors()
        self.bg:AddAnchor("TOPLEFT", self, 0, 0)
        self.bg:AddAnchor("BOTTOMRIGHT", self, 0, self.addonCount * 30 + 10)
      end
    end
    if configMenu.michaelClient.AddAddon then
      configMenu.michaelClient:AddAddon("Cooldown Buff Tracker", openFromEscMenu)
    end
  end)

  safeLog("[CBT] Loading CooldawnBuffTracker " .. CooldawnBuffTracker.version .. " by " .. CooldawnBuffTracker.author)

  -- Модель канвасов уже нормализована helpers.getSettings()/default_settings.migrate():
  -- плоские поля юнитов переехали в canvases[1] ("Main"), ничего не потеряно.
  safeLog("[CBT] Canvas model ready: playerpet=" .. tostring(#(settings.playerpet.canvases or {}))
    .. " player=" .. tostring(#(settings.player.canvases or {}))
    .. " target=" .. tostring(#(settings.target.canvases or {})))

  -- Инициализируем страницу настроек, если модуль загружен
  if settingsPage and settingsPage.Load then
    settingsPage.Load()
  end

  -- Инициализируем UI
  initializeUI()

  live = true
  api.On("UPDATE", OnUpdate)

  -- Приёмник боевого лога: триггер кастомных баффов по имени навыка
  combatEventWnd = api.Interface:CreateEmptyWindow("CBTCombatEvents")
  if combatEventWnd then
    combatEventWnd:Show(false)
    pcall(function() combatEventWnd:Clickable(false) end)
    pcall(function() combatEventWnd:EnablePick(false) end)
    combatEventWnd:SetHandler("OnEvent", function(self, event, ...)
      if event == "SPELLCAST_START" then
        local spellName, castingTime, caster = ...
        if settings and settings.debugBuffId then
          safeLog(string.format("[CBT] cast %s by %s (%sms)",
            tostring(spellName), tostring(caster), tostring(castingTime)))
        end
        return
      end
      onCombatMessage(event, ...)
    end)
    pcall(function() combatEventWnd:RegisterEvent("COMBAT_MSG") end)
    pcall(function() combatEventWnd:RegisterEvent("SPELLCAST_START") end)
  end

  -- Полное обновление панелей после изменения настроек (вызывается из helpers)
  CooldawnBuffTracker.OnSettingsSaved = function()
    settings = helpers and helpers.getSettings() or settings
    if BuffDebugger and BuffDebugger.Shutdown then
      BuffDebugger.Shutdown({
        playerCanvas = unitCanvases.player[1],
        mountCanvas = unitCanvases.playerpet[1]
      })
    end
    if BuffDebugger and BuffDebugger.Initialize then
      BuffDebugger.Initialize({
        playerCanvas = unitCanvases.player[1],
        mountCanvas = unitCanvases.playerpet[1],
        settings = settings
      })
    end
    refreshAllCanvases()
  end
end

local function OnUnload()
  -- Отключить OnUpdate: api.Off нет, поэтому гасим флагом
  live = false
  pcall(flushAuraDump)
  mirrorTargetByBuff = {}
  manaPrev = nil
  manaLastSpendTime = 0
  manaTimer = 0

  -- Сохраняем позиции КАЖДОГО канваса ДО их освобождения
  -- (иначе GetOffset на мёртвых виджетах отдаст мусор)
  if helpers and helpers.saveCanvasPositions then
    pcall(function() helpers.saveCanvasPositions(settings) end)
  end
  pcall(function() api.SaveSettings() end)

  -- Отключаем приёмник боевого лога
  if combatEventWnd then
    pcall(function() combatEventWnd:UnregisterEvent("COMBAT_MSG") end)
    pcall(function() combatEventWnd:ReleaseHandler("OnEvent") end)
    pcall(function() combatEventWnd:Show(false) end)
    pcall(function() api.Interface:Free(combatEventWnd) end)
    combatEventWnd = nil
  end

  -- Отключаем модуль отладки баффов
  if BuffDebugger and BuffDebugger.Shutdown then
    BuffDebugger.Shutdown({
      playerCanvas = unitCanvases.player[1],
      mountCanvas = unitCanvases.playerpet[1],
      targetCanvas = unitCanvases.target[1]
    })
  end

  -- Очищаем данные
  buffData = {}
  playerBuffData = {}
  targetBuffData = {}
  targetCache = {}

  -- Очищаем все канвасы всех юнитов
  for _, unitType in ipairs(UNIT_TYPES) do
    destroyUnitCanvases(unitType)
  end

  -- Окно выбора навыков для эффективных КД
  if EffectivePicker and EffectivePicker.Unload then
    pcall(EffectivePicker.Unload)
  end

  -- Выгружаем страницу настроек, если модуль загружен
  if settingsPage and settingsPage.Unload then
    settingsPage.Unload()
  end

end

-- Handler for opening settings window
local function OnSettingToggle()
  if settingsPage and settingsPage.openSettingsWindow then
    settingsPage.openSettingsWindow()
  end
  if settings then
    if settings.enabled == false then
      hideAllCanvases()
    else
      for _, unitType in ipairs(UNIT_TYPES) do
        pcall(function() checkBuffs(unitType) end)
      end
    end
  end
end

CooldawnBuffTracker.OnLoad = OnLoad
CooldawnBuffTracker.OnUnload = OnUnload
CooldawnBuffTracker.OnSettingToggle = OnSettingToggle

-- Handler for event when tracked buffs list is updated
-- (своё событие addon'а, шлётся через api:Emit из buffs_to_track/presets/import)
api.On("ADDON_CBT_BUFFS_CHANGED", function()
  if not live then return end
  safeLog("[CBT] Received buff list update event")

  -- Обновляем данные баффов (включая удаление ненужных)
  local oldMountBuffsCount = 0
  for _ in pairs(buffData) do oldMountBuffsCount = oldMountBuffsCount + 1 end

  local oldPlayerBuffsCount = 0
  for _ in pairs(playerBuffData) do oldPlayerBuffsCount = oldPlayerBuffsCount + 1 end

  -- Инициализируем данные баффов
  initBuffData()

  -- Считаем новое количество баффов
  local newMountBuffsCount = 0
  for _ in pairs(buffData) do newMountBuffsCount = newMountBuffsCount + 1 end

  local newPlayerBuffsCount = 0
  for _ in pairs(playerBuffData) do newPlayerBuffsCount = newPlayerBuffsCount + 1 end

  safeLog("[CBT] Mount buff list updated: was " .. oldMountBuffsCount .. ", now " .. newMountBuffsCount)
  safeLog("[CBT] Player buff list updated: was " .. oldPlayerBuffsCount .. ", now " .. newPlayerBuffsCount)

  -- Пересобираем канвасы всех юнитов: набор записей и их привязка к канвасам
  -- могли измениться (добавление/удаление/перенос/пресет/импорт).
  refreshAllCanvases()
end)

-- Handler for event when buffs list becomes empty
-- (своё событие addon'а)
return CooldawnBuffTracker
