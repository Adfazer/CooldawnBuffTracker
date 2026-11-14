local api = require("api")
local locale = require("CooldawnBuffTracker/locale")
local BuffList = require("CooldawnBuffTracker/buff_helper")
local BuffsToTrack = require("CooldawnBuffTracker/buffs_to_track")
local helpers = require("CooldawnBuffTracker/helpers")
local settingsPage = require("CooldawnBuffTracker/settings_page")
local BuffDebugger = require("CooldawnBuffTracker/buff_debugger")
local EffectiveCD = require("CooldawnBuffTracker/effective_cd")
local CbtLog = require("CooldawnBuffTracker/util/cbt_log")
local CbtIcon = require("CooldawnBuffTracker/util/cbt_icon")
local CbtDebugLog = require("CooldawnBuffTracker/util/cbt_debuglog")

-- Declare variables for caching buff states (add to the beginning of file after other variables)
local cachedMountBuffs = {}
local cachedPlayerBuffs = {}
local cachedBuffStatus = {}
local lastRuntimeError = {}
local OnUpdate

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
  CbtLog.warn("Failed to load buffs_to_track.lua, using settings")
end

if not BuffList then
  BuffList = {
    GetBuffName = function(id) return "Buff #" .. id end,
    GetBuffIcon = function(id) return nil end,
    GetBuffCooldown = function(id) return 0 end,
    GetBuffTimeOfAction = function(id) return 0 end
  }
  CbtLog.warn("Failed to load buff_helper.lua, using placeholder")
end

local CooldawnBuffTracker = {
  name = "CooldawnBuffTracker",
  author = "Adfazer & Claude",
  desc = "Track buffs, debuffs and skill cooldowns with panels, target overlay and custom entries.",
  version = "2.0.0"
}

local buffData = {}
local playerBuffData = {}
-- Модель 1.20: N канвасов на каждый тип юнита. unitCanvases[unitType][i] —
-- живой виджет i-го канваса; раскладка лежит в settings[unitType].canvases[i].
local unitCanvases = { playerpet = {}, player = {}, target = {} }
local UNIT_TYPES = { "playerpet", "player", "target" }
-- 1.23.0: режим у нативного фрейма — оверлей цели. Объявлен заранее, потому
-- что hideUnitCanvases() должна гасить и его; присваивается ниже, после
-- функций отрисовки.
local hideFrameModesForUnit
local frameModeEnabled
-- 1.25.0: настройки TTP читает refreshFrameCache (кэш 500 мс), поэтому нужна
-- предварительная декларация — определение ниже, после ttpPixels/readTTPPrivate.
local ttpTargetBounds
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

-- Mirror допустим только для баффов/дебаффов: у навыка и мана-навыка нет ауры
-- на цели, зеркалить нечего. Для трекнутых id без кастомной записи — можно.
local function mirrorAllowed(buffId)
  local cb = findCustomBuff(buffId)
  if not cb then return true end
  local kind = helpers.entryKind and helpers.entryKind(cb) or cb.kind or "buff"
  return kind == "buff"
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
        CbtLog.info("%s buff removed from tracking: %s", unitType, CbtLog.hl(buffId))
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

        CbtLog.success("%s buff added for tracking: %s (%s)", unitType, CbtLog.hl(buffId), CbtLog.hl(buffName))
      end
    end
  end

  -- Применяем CD/D/иконки кастомных баффов к уже существующим записям
  applyCustomBuffOverrides()
end

local function setBuffStatus(buffId, status, currentTime, unitType, remainingTime, anchorTime, cdOverride)
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
  local cdUsed = tonumber(cdOverride)
  if cdUsed == nil then cdUsed = tonumber(buff.cooldown) or 0 end
  if cdUsed < 0 then cdUsed = 0 end
  if cdOverride ~= nil then
    -- Эффективный КД (1.28.0) живёт рядом с настроенным: cooldown остаётся
    -- базовым для отображения, readyAt считается от эффективного.
    buff.effCD = cdUsed
  end

  if status == "active" then
    if anchorTime then
      -- Явный якорь: начало каста навыка (SPELLCAST_START), а не момент ауры
      buff.fixedTime = anchorTime
      buff.activeUntil = anchorTime + timeOfAction
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
    else
      -- API не отдаёт timeLeft (у предмета/навыка нет длительности):
      -- берём длительность из настроек, как в 1.5.0. Это важно для бафов вещей,
      -- у которых есть только навык с кулдауном и нет собственного таймера.
      buff.fixedTime = currentTime
      buff.activeUntil = currentTime + timeOfAction
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

  buff.statusChangeTime = currentTime

  -- Диагностика таймингов (Debug: ON): видно, от какого момента считается КД
  if settings and settings.debugBuffId and oldStatus ~= buff.status then
    CbtLog.debug("timer %s %s->%s now=%.2f D=%s CD=%s fixed=%s ready=%s rem=%s",
      tostring(buffId), tostring(oldStatus), tostring(buff.status),
      tonumber(currentTime) or 0, tostring(buff.timeOfAction), tostring(buff.cooldown),
      tostring(buff.fixedTime), tostring(buff.readyAt), tostring(remainingTime))
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

-- ===== Эффективные КД цели (1.28.0) =====
-- Модификаторы (flat / percent / reset) задаёт пользователь в Edit окне записи;
-- работают ТОЛЬКО на панели Target и только у записей с effectiveCDs = true.
-- Состояние smart и класс цели хранятся СТРОГО per target id в targetCache:
-- смена класса сбрасывает smart того же id (респек ветвей), переход на другую
-- цель ничего не чистит — у прежней цели её smart живёт до истечения кэша.

local function ensureTargetCacheEntry(targetId)
  if targetId == nil then return nil end
  local cache = targetCache[targetId]
  if not cache then
    cache = { lastSeen = getCurrentTime(), buffStates = {} }
    targetCache[targetId] = cache
  end
  if type(cache.smart) ~= "table" then cache.smart = {} end
  return cache
end

-- Снимок аур текущей цели: id -> { stack = n }. id — строка (как в targetBuffData).
-- Нужен на момент применения записи и для reset-модификаторов.
local function readTargetAuras()
  local okId, unitId = pcall(function() return api.Unit:GetUnitId("target") end)
  if not okId or unitId == nil then return nil end
  local snapshot = {}
  local okBuff, buffCount = pcall(function() return api.Unit:UnitBuffCount("target") end)
  if okBuff and type(buffCount) == "number" then
    for i = 1, buffCount do
      local buff = api.Unit:UnitBuff("target", i)
      if buff and buff.buff_id then
        local id = helpers.formatBuffId(buff.buff_id)
        snapshot[tostring(id)] = { stack = buff.stack }
      end
    end
  end
  local okDebuff, debuffCount = pcall(function() return api.Unit:UnitDeBuffCount("target") end)
  if okDebuff and type(debuffCount) == "number" then
    for i = 1, debuffCount do
      local debuff = api.Unit:UnitDeBuff("target", i)
      if debuff and debuff.buff_id then
        local id = helpers.formatBuffId(debuff.buff_id)
        snapshot[tostring(id)] = { stack = debuff.stack }
      end
    end
  end
  return snapshot
end

-- Есть ли хоть одна запись с эффективными КД: без неё ауры цели лишний раз
-- не читаем и ничего не считаем.
local function targetUsesEffective()
  for _, cb in ipairs((settings and settings.customBuffs) or {}) do
    if EffectiveCD.isEnabled(cb) then return true end
  end
  return false
end

local function effectiveEntryFor(buffId)
  local cb = findCustomBuff(buffId)
  if not cb and targetUsesEffective() then
    local name = BuffList.GetBuffName(buffId)
    if type(name) == "string" and name ~= "" then
      cb = findCustomBuffByName(name)
    end
  end
  if cb and EffectiveCD.isEnabled(cb) then return cb end
  return nil
end

local function smartStateFor(targetId, entryKey, create)
  if targetId == nil or entryKey == nil then return nil end
  local cache = targetCache[targetId]
  if not cache and not create then return nil end
  cache = ensureTargetCacheEntry(targetId)
  if not cache then return nil end
  local state = cache.smart[entryKey]
  if not state and create then
    state = { learned = false, paused = false }
    cache.smart[entryKey] = state
  end
  return state
end

-- Момент применения записи: сначала проверяем раннее повторное применение
-- (факт < прогноз * 0.95), затем считаем эффективный КД по снимку аур цели.
-- Reset-пауза: интервал через reset не считается доказательством, пауза
-- снимается на следующем применении.
local function applyEffectiveCD(cb, snapshot, now, targetId)
  if not cb or not EffectiveCD.isEnabled(cb) or targetId == nil then return nil end
  local key = tostring(cb.id)
  local state = smartStateFor(targetId, key, true)
  local smartPct = tonumber(cb.smartPct) or 0
  if smartPct < 0 then smartPct = 0 end

  if state.paused then
    state.paused = false
  elseif not state.learned and smartPct > 0 and state.lastApply ~= nil and state.predicted ~= nil then
    local actual = (tonumber(now) or 0) - (tonumber(state.lastApply) or 0)
    local predicted = tonumber(state.predicted) or 0
    if actual > 0 and predicted > 0 and actual < predicted * 0.95 then
      state.learned = true
      CbtLog.success(
        "effective CD: smart %.1f%% learned for %s on target %s (applied after %.2f s < %.2f s)",
        smartPct, key, tostring(targetId), actual, predicted * 0.95)
    end
  end

  local eval = EffectiveCD.evaluate(cb, snapshot, { learned = state.learned, smartPct = smartPct })
  state.lastApply = now
  state.predicted = eval.effective
  return eval.effective, eval
end

-- Класс цели читается только у текущей цели (другого API нет). Пишем его в
-- кэш ИМЕННО этого id; смена класса сбрасывает smart только этого id.
local targetClassCheckedAt = 0
local function maybeCheckTargetClass(targetId, now)
  if targetId == nil then return end
  if (now - targetClassCheckedAt) < 1.0 then return end
  targetClassCheckedAt = now
  local ok, className = pcall(function() return api.Ability:GetUnitClassName("target") end)
  if not ok or type(className) ~= "string" or className == "" then return end
  local cache = ensureTargetCacheEntry(targetId)
  if not cache then return end
  local prev = cache.className
  local knownPrev = (type(prev) == "string" and prev ~= "" and prev ~= "Pending") or false
  local knownNow = (className ~= "Pending")
  if knownPrev and knownNow and className ~= prev then
    cache.smart = {}
    CbtLog.warn("effective CD: target %s class %s -> %s, smart reset for this target",
      tostring(targetId), tostring(prev), className)
  end
  if knownNow or not knownPrev then
    cache.className = className
  end
end

local function resetModKey(cb, modIndex)
  return tostring(cb.id) .. "|" .. tostring(modIndex)
end

-- Reset-модификаторы: появление их баффа на цели обнуляет таймер записи
-- (активная фаза кончается, навык готов) и ставит smart на паузу.
-- Первый опрос после взятия цели/восстановления кэша только запоминает уже
-- висящие баффы — «появлением» они не считаются.
local function processTargetResets(snapshot, now, records, targetId)
  if snapshot == nil or targetId == nil then return false end
  local cache = ensureTargetCacheEntry(targetId)
  if not cache then return false end
  local seeding = (type(cache.resetSeen) ~= "table")
  local seen = cache.resetSeen or {}
  local nextSeen = {}
  local changed = false

  for buffId, rec in pairs(records or {}) do
    local cb = effectiveEntryFor(buffId)
    if cb and EffectiveCD.hasReset(cb) then
      for modIndex, mod in ipairs(EffectiveCD.mods(cb)) do
        if mod.kind == "reset" then
          local aura = EffectiveCD.findAura(mod, snapshot)
          if aura then
            local key = resetModKey(cb, modIndex)
            nextSeen[key] = true
            if not seeding and not seen[key] then
              local state = smartStateFor(targetId, tostring(cb.id), true)
              if state then state.paused = true end
              if rec and rec.fixedTime then
                rec.readyAt = now
                rec.activeUntil = now
                rec.status = "ready"
                rec.statusChangeTime = now
                rec.effCD = 0
                changed = true
              end
              CbtLog.info("effective CD: reset '%s' zeroed %s on target %s",
                EffectiveCD.sourceLabel(mod, modIndex), tostring(cb.id), tostring(targetId))
            end
          end
        end
      end
    end
  end

  cache.resetSeen = nextSeen
  return changed
end

-- Данные для карточки Reference в Edit окне: текущая цель, активные условия,
-- smart этой цели. entry — рабочая копия записи из окна настроек.
local function getEffectivePreview(entry)
  if not EffectiveCD.isEnabled(entry) then return nil end
  local targetId = currentTargetId
  local snapshot = nil
  if targetId ~= nil then
    local ok, liveId = pcall(function() return api.Unit:GetUnitId("target") end)
    if ok and liveId ~= nil and tostring(liveId) == tostring(targetId) then
      snapshot = readTargetAuras()
    end
  end
  local state = nil
  if targetId ~= nil and entry.id ~= nil then
    state = smartStateFor(targetId, tostring(entry.id), false)
  end
  local learned = state and state.learned or false
  local paused = state and state.paused or false
  local smartPct = tonumber(entry.smartPct) or 0
  local eval = EffectiveCD.evaluate(entry, snapshot, {
    learned = learned and not paused,
    potentialLearned = learned,
    smartPct = smartPct,
  })
  eval.learned = learned and smartPct > 0
  eval.paused = paused
  eval.hasTarget = (snapshot ~= nil)
  return eval
end

-- ===== Триггеры навыков по боевому логу (враг ударил -> КД его навыка) =====
-- unitIdByName: имя (точно как в игре) -> id юнита (учим, когда берём цель в таргет)
-- pendingBySource: имя -> { [buffId] = время }, пока id игрока неизвестен
local unitIdByName = {}
local pendingBySource = {}

-- Журналы навыков из боевого лога — отдельные на каждый юнит (окно Record).
-- 1.26.0: навык пишется в журнал юнита, чьё имя совпало с источником события;
-- при совпадении имён приоритет player -> mount (playerpet) -> target.
local LOGGED_SPELL_CAP = 200
local loggedSpells = {
  player = { order = {}, map = {} },
  playerpet = { order = {}, map = {} },
  target = { order = {}, map = {} },
}

-- Имя юнита для сверки с источником боевого лога: UnitName, иначе по id.
-- Сравнение точное: string.lower не складывает кириллицу.
local function unitSourceName(unitType)
  local name = nil
  local ok, value = pcall(function() return api.Unit:UnitName(unitType) end)
  if ok then name = value end
  if type(name) ~= "string" or name == "" then
    local id = nil
    local okId, idValue = pcall(function() return api.Unit:GetUnitId(unitType) end)
    if okId then id = idValue end
    if id then
      local okName, byId = pcall(function() return api.Unit:GetUnitNameById(id) end)
      if okName then name = byId end
    end
  end
  if type(name) ~= "string" or name == "" then return nil end
  return name
end

-- Юнит, в журнал которого писать событие с источником sourceName, или nil:
-- источник должен совпасть с именем юнита, иначе событие не логируется.
local function loggedSpellUnitFor(sourceName)
  if type(sourceName) ~= "string" or sourceName == "" then return nil end
  if sourceName == unitSourceName("player") then return "player" end
  if sourceName == unitSourceName("playerpet") then return "playerpet" end
  if sourceName == unitSourceName("target") then return "target" end
  return nil
end

local function recordLoggedSpell(unitType, name, now)
  if not unitType or not name or name == "" then return end
  local store = loggedSpells[unitType]
  if not store then return end
  local e = store.map[name]
  if not e then
    e = { name = name, count = 0 }
    store.map[name] = e
    store.order[#store.order + 1] = name
    if #store.order > LOGGED_SPELL_CAP then
      local old = table.remove(store.order, 1)
      store.map[old] = nil
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

  local cdUsed = cd
  local effCD = nil
  -- Эффективный КД навыка (1.28.0): момент применения — каст навыка целью.
  -- Снимок аур читаем только у текущей цели (другой юнит API не отдаёт).
  if cb and helpers.entryKind(cb) == "skill" and EffectiveCD.isEnabled(cb) then
    local snapshot = nil
    if currentTargetId ~= nil and tostring(currentTargetId) == tostring(sourceId) then
      snapshot = readTargetAuras()
    end
    effCD = applyEffectiveCD(cb, snapshot, startedAt, sourceId)
    if effCD ~= nil then cdUsed = effCD end
  end

  local rec = {
    fixedTime = startedAt,
    activeUntil = startedAt + toa,
    readyAt = startedAt + cdUsed,
    effCD = effCD,
    synthetic = true,   -- нет ауры: пропажа не должна обрывать активную фазу
    status = "active",
    missingCount = 0,
    timeOfAction = toa,
    cooldown = cd,
    name = BuffList.GetBuffName(buffId),
    icon = BuffList.GetBuffIcon(buffId)
  }

  local cache = ensureTargetCacheEntry(sourceId)
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
      effCD = effCD,
      synthetic = true,
      status = "active"
    }
  end
  if settings and settings.debugBuffId then
    local where = (currentTargetId and tostring(currentTargetId) == tostring(sourceId))
      and " (current target)" or " (cached)"
    CbtLog.debug("target skill: %s from %s -> cd %.1fs%s",
      tostring(buffId), tostring(sourceId), tonumber(cdUsed) or 0, where)
    CbtDebugLog.info("target skill: " .. tostring(buffId) .. " from " .. tostring(sourceId)
      .. " -> cd " .. tostring(cdUsed) .. "s" .. where
      .. " fixed=" .. tostring(startedAt) .. " toa=" .. tostring(toa)
      .. " readyAt=" .. tostring(startedAt + cdUsed))
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
      CbtLog.debug("icon: no spellId in event for '%s'", tostring(cb.id))
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
    CbtLog.debug("icon lookup id=%s -> path=%s name=%s%s",
      tostring(spellId), tostring(path), tostring(name), errText)
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
  CbtLog.debug("icon learned for spell %s: %s", tostring(spellId), tostring(path))
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
        CbtLog.debug("%s args: %s", tostring(combatEvent), table.concat(parts, " "))
        CbtLog.debug("parsed: spellId=%s spellName=%s",
          tostring(spellId), tostring(spellName))
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
      -- A skill can emit two damage components for one hit (same spell name,
      -- same timestamp, different damage). With Duration=0 the active window
      -- is empty, so the old debounce did nothing and the second component
      -- restarted the cooldown indefinitely. Keep a short burst guard for
      -- skill entries.
      if helpers.entryKind(cb) == "skill" and blockWindow < 0.25 then
        blockWindow = 0.25
      end

      local blocked = false
      if blockWindow > 0 then
        local tkey = tostring(srcKey or "self") .. "|" .. tostring(cb.id)
        local last = lastTriggerTimes[tkey]
        if last and (now - last) < blockWindow then
          blocked = true
          if settings.debugBuffId then
            CbtLog.debug("'%s': repeat trigger after %.1f s - ignored (window %s)",
              tostring(spellName), now - last, tostring(blockWindow))
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
            CbtLog.debug("'%s': self cast -> Player/Mount panels: %s", spellName, tostring(hits))
          else
            CbtLog.debug("'%s': self cast, but the buff is not tracked on Player/Mount", spellName)
          end
          if sourceId and currentTargetId and tostring(currentTargetId) == tostring(sourceId) then
            CbtLog.debug("'%s': you are the current target -> recorded to Target", spellName)
          end
        end
      elseif sourceId then
        triggerTargetCooldown(sourceId, cb.id, now, now)
        if settings.debugBuffId then
          CbtLog.debug("'%s': cooldown recorded for %s (unit %s)",
            spellName, tostring(srcKey), tostring(sourceId))
        end
      elseif srcKey then
        local p = pendingBySource[srcKey]
        if not p then
          p = {}
          pendingBySource[srcKey] = p
        end
        p[cb.id] = now
        if settings.debugBuffId then
          CbtLog.debug("'%s': source %s unknown, waiting for the first target",
            spellName, tostring(srcKey))
        end
      else
        if settings.debugBuffId then
          CbtLog.debug("'%s': no source in the event", spellName)
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
local function cleanupTargetCache(now)
  local currentTime = tonumber(now) or getCurrentTime()
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
      CbtLog.debug("Target cache cleaned: %s", tostring(targetId))
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
  if list then
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
  -- Привязанные к фрейму оверлеи — часть показа этого юнита.
  if hideFrameModesForUnit then
    pcall(hideFrameModesForUnit, unitType)
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

-- Единый цветовой статус иконки: зелёный = активен, красный = кулдаун,
-- прозрачный = готов. Вынесено из renderCanvas, чтобы оверлей цели красился
-- точно так же, как плавающий канвас.
local function applyIconStatus(icon, status)
  if not icon then return end
  if status == "ready" then
    if icon.statusOverlay then
      icon.statusOverlay:SetColor(1, 1, 1, 0)
    end
    if icon.topBorder then icon.topBorder:SetColor(1, 1, 1, 0) end
    if icon.bottomBorder then icon.bottomBorder:SetColor(1, 1, 1, 0) end
    if icon.leftBorder then icon.leftBorder:SetColor(1, 1, 1, 0) end
    if icon.rightBorder then icon.rightBorder:SetColor(1, 1, 1, 0) end
    if icon.SetColor then
      icon:SetColor(ICON_COLORS.READY[1], ICON_COLORS.READY[2], ICON_COLORS.READY[3], ICON_COLORS.READY[4])
    end
  elseif status == "active" then
    if icon.statusOverlay then
      icon.statusOverlay:SetColor(0, 1, 0, 0.3)
    end
    local r, g, b, a = 0, 1, 0, 0.8
    if icon.topBorder then icon.topBorder:SetColor(r, g, b, a) end
    if icon.bottomBorder then icon.bottomBorder:SetColor(r, g, b, a) end
    if icon.leftBorder then icon.leftBorder:SetColor(r, g, b, a) end
    if icon.rightBorder then icon.rightBorder:SetColor(r, g, b, a) end
    if icon.SetColor then
      icon:SetColor(ICON_COLORS.ACTIVE[1], ICON_COLORS.ACTIVE[2], ICON_COLORS.ACTIVE[3], ICON_COLORS.ACTIVE[4])
    end
  elseif status == "cooldown" then
    if icon.statusOverlay then
      icon.statusOverlay:SetColor(1, 0, 0, 0.3)
    end
    local r, g, b, a = 1, 0, 0, 0.8
    if icon.topBorder then icon.topBorder:SetColor(r, g, b, a) end
    if icon.bottomBorder then icon.bottomBorder:SetColor(r, g, b, a) end
    if icon.leftBorder then icon.leftBorder:SetColor(r, g, b, a) end
    if icon.rightBorder then icon.rightBorder:SetColor(r, g, b, a) end
    if icon.SetColor then
      icon:SetColor(ICON_COLORS.COOLDOWN[1], ICON_COLORS.COOLDOWN[2], ICON_COLORS.COOLDOWN[3], ICON_COLORS.COOLDOWN[4])
    end
  end
end

-- Текст таймера для иконки: остаток активного баффа или остаток кулдауна.
local function iconTimerText(buff, status, currentTime)
  if status == "active" and buff.activeUntil and buff.activeUntil ~= math.huge then
    local remainingActive = buff.activeUntil - currentTime
    if remainingActive > 0 then
      return formatTimerSeconds(remainingActive)
    end
  elseif status == "cooldown" and buff.readyAt then
    local remainingCooldown = buff.readyAt - currentTime
    if remainingCooldown > 0 then
      return formatTimerSeconds(remainingCooldown)
    end
  end
  return ""
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
          -- Устанавливаем изображение для иконки (skill_icons/*.png -> PNG-дравейбл).
          -- A bad/custom icon must not abort the whole UPDATE loop (the old
          -- behaviour froze every timer and stopped target switching).
          local painted, paintErr = pcall(CbtIcon.Paint, icon, buff.icon)
          if not painted then
            pcall(function()
              if F_SLOT and F_SLOT.SetIconBackGround then
                F_SLOT.SetIconBackGround(icon, nil)
              end
            end)
            if not lastRuntimeError.icon then
              lastRuntimeError.icon = true
              CbtLog.error("icon paint failed: %s", tostring(paintErr))
            end
          end
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
          applyIconStatus(icon, currentStatus)
          icon.lastStatus = currentStatus
        end

        -- Таймер: текст меняется не чаще 10 раз/с — SetText только по изменению
        if icon.timerLabel and us.showTimer then
          local timerText = iconTimerText(buff, currentStatus, currentTime)

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

-- =====================================================================
-- 1.23.0: режим показа, привязанный к цели (1.26.0 — оверлей, единственный).
--   * Target "Overlay" — каждый канвас рисуется у цели в экранных
--     координатах (api.Unit:GetUnitScreenPosition), как это делает
--     TrackThatPlease; при загруженном TTP строка ставится над его рядом.
--     Позиция пересчитывается КАЖДЫЙ кадр; якорь меняется только при
--     сдвиге на >= 1 px (см. updateTargetOverlayPositions).
-- Плавающие канвасы при включённом оверлее остаются на месте (1.31.0): их
-- прячет только отдельный Hide target canvas. Выключение оверлея возвращает
-- панели на прежнее место (позиция в настройках не меняется).
-- Player-режим "Under MP bar" убран в 1.25.0, слитая строка под HP/MP у цели —
-- в 1.26.0: у обоих юнитов только плавающие канвасы, у цели ещё оверлей.
-- =====================================================================
local FRAME_CACHE_MS = 500      -- проверка фрейма/цели/настроек TTP ~2 раза в секунду
local TTP_ADDON_ID = "TrackThatPlease"
local FRAME_ANCHOR_MAX_DIST = 100
local MAX_ANCHOR_COORD = 20000  -- защита от вырожденной проекции у камеры

local frameOverlays = {}  -- [index] = { wnd, icons, sig, ax, ay, shown }
local frameCache = {}     -- [unitType] = { frame, visible, screenX/Y/z, ttpOffset/Size, at }

-- 1.26.0: у цели два независимых переключателя показа — оверлей у цели и
-- скрытие плавающих канвасов. Режимов у player/playerpet нет.
frameModeEnabled = function(unitType)
  local us = settings and settings[unitType]
  if not us then return false end
  if unitType == "target" then return us.overlay == true end
  return false
end

-- Нативная рамка юнита: только 20 разрешённых UIC id, поэтому pcall и nil.
local function getUnitFrame(unitType)
  local ok, frame = pcall(function()
    if unitType == "player" then
      return ADDON:GetContent(UIC.PLAYER_UNITFRAME)
    end
    return ADDON:GetContent(UIC.TARGET_UNITFRAME)
  end)
  if not ok then return nil end
  return frame
end

-- Ошибка чтения не должна гасить оверлей: считаем виджет видимым.
local function widgetVisible(widget)
  if not widget then return false end
  local ok, vis = pcall(function() return widget:IsVisible() end)
  if not ok then return true end
  return vis and true or false
end

-- 1.31.0: настоящий виджет target-ряда TrackThatPlease. api.Interface:
-- FindWidget часто не находит окна, созданные CreateEmptyWindow, поэтому
-- пробуем три способа подряд (паттерн tax_tracker). Объект принимаем, только
-- если он ведёт себя как виджет: у него есть GetExtent и AddAnchor.
-- Всё в одной таблице: у чанка main.lua жёсткий лимит 200 локальных имён.
local TTPRow = {
  canvasId = "targetBuffCanvas",
  lookups = { "FindWidget", "GetWindow", "GetWidgetByName" },
}

function TTPRow.looksLikeWidget(widget)
  if widget == nil then return false end
  local okExtent, extent = pcall(function() return widget.GetExtent end)
  if not okExtent or extent == nil then return false end
  local okAnchor, anchor = pcall(function() return widget.AddAnchor end)
  if not okAnchor or anchor == nil then return false end
  return true
end

-- Скрытый или освобождённый канвас (ошибка вызова) для якоря не годится.
function TTPRow.usable(widget)
  if not widget then return false end
  local ok, visible = pcall(function() return widget:IsVisible() end)
  if not ok then return false end
  return visible and true or false
end

function TTPRow.find()
  for _, lookup in ipairs(TTPRow.lookups) do
    local ok, widget = pcall(function()
      local getter = api.Interface[lookup]
      if getter == nil then return nil end
      return getter(api.Interface, TTPRow.canvasId)
    end)
    if ok and TTPRow.looksLikeWidget(widget) then return widget end
  end
  return nil
end

-- Кэш тяжёлых проверок: ~2 проверки в секунду, а не каждый кадр.
-- Позиция цели сюда НЕ входит — её читает readTargetScreen() каждый кадр.
local function refreshFrameCache(unitType, nowMs)
  local cache = frameCache[unitType]
  if not cache then
    cache = {}
    frameCache[unitType] = cache
  end
  if cache.at and (nowMs - cache.at) < FRAME_CACHE_MS then return cache end
  cache.at = nowMs

  local frame = getUnitFrame(unitType)
  cache.frame = frame
  cache.visible = frame ~= nil and widgetVisible(frame)

  if unitType == "target" then
    -- Настройки TTP (приватный файл) читаются вместе с рамкой — раз в 500 мс,
    -- а не на каждом кадре: по ним оверлей встаёт над рядом TrackThatPlease.
    cache.ttpOffset, cache.ttpSize = ttpTargetBounds()
    -- 1.31.0: сам виджет targetBuffCanvas ищется на том же 500-мс кэше;
    -- лог печатается только при смене состояния «найден/не найден».
    local canvas = TTPRow.find()
    cache.ttpCanvas = canvas or false
    local state = canvas and "found" or "missing"
    if cache.ttpCanvasState ~= state then
      cache.ttpCanvasState = state
      if canvas then
        CbtLog.debug("TTP canvas found: %s", TTPRow.canvasId)
      else
        CbtLog.debug("TTP canvas not found, fallback: %s", TTPRow.canvasId)
      end
    end
  end
  return cache
end

-- 1.25.0: проекция цели читается КАЖДЫЙ кадр (как у TrackThatPlease) — по ней
-- двигается оверлей, и 500-мс кэш давал рывки при движении/повороте камеры.
-- Ошибка чтения или нечисло/Nan/Inf обнуляют позицию: оверлей прячется.
local function readTargetScreen(cache)
  if not cache then return false end
  local ok, x, y, z = pcall(function() return api.Unit:GetUnitScreenPosition("target") end)
  if not ok or type(x) ~= "number" or type(y) ~= "number" then
    cache.screenX, cache.screenY, cache.z = nil, nil, nil
    return false
  end
  -- NaN не равен самому себе; Inf отвергаем руками
  local finite = (x == x) and (y == y)
    and x ~= math.huge and x ~= -math.huge
    and y ~= math.huge and y ~= -math.huge
  if not finite then
    cache.screenX, cache.screenY, cache.z = nil, nil, nil
    return false
  end
  cache.screenX, cache.screenY = x, y
  if type(z) == "number" and z == z then
    cache.z = z
  else
    cache.z = nil
  end
  return true
end

-- Годна ли позиция для якоря: z в прежнем диапазоне (0..FRAME_ANCHOR_MAX_DIST)
-- и координаты не «взорвались». Проекция вырождается у плоскости камеры, и z
-- при этом остаётся положительным (замер TTP: x от -12733 до 90218), поэтому
-- одного z мало.
local function targetScreenSane(cache)
  if not cache or not cache.screenX or not cache.screenY then return false end
  local x, y = cache.screenX, cache.screenY
  if x <= -MAX_ANCHOR_COORD or x >= MAX_ANCHOR_COORD then return false end
  if y <= -MAX_ANCHOR_COORD or y >= MAX_ANCHOR_COORD then return false end
  local z = cache.z
  if z and (z < 0 or z > FRAME_ANCHOR_MAX_DIST) then return false end
  return true
end

local function uiScaleSafe()
  local scale = 1
  pcall(function()
    local s = api.Interface:GetUIScale()
    if type(s) == "number" and s > 0 then scale = s end
  end)
  return scale
end

-- Настройки TTP в пикселях устройства; его смещения — device px, а
-- GetUnitScreenPosition говорит в UI-координатах.
local function ttpPixels(value)
  local n = tonumber(value)
  if not n then return nil end
  return n / uiScaleSafe()
end

-- TTP 3.1+ стирает свои ключи из общей таблицы и хранит настройки в
-- TrackThatPlease_settings.lua (при отсутствии — в _backup). Читаем оба места.
local function readTTPPrivate()
  local paths = { "TrackThatPlease_settings.lua", "TrackThatPlease_settings_backup.lua" }
  for _, path in ipairs(paths) do
    local ok, data = pcall(function() return api.File:Read(path) end)
    if ok and type(data) == "table" then
      for _ in pairs(data) do return data end
    end
  end
  return nil
end

-- Нижняя граница и высота target-ряда TrackThatPlease в UI-координатах.
-- nil, если TTP не загружен/настройки недоступны.
ttpTargetBounds = function()
  local conf = nil
  local ok, engine = pcall(function() return api.GetSettings(TTP_ADDON_ID) end)
  if ok and type(engine) == "table" and engine.targetBuffVerticalOffset ~= nil then
    conf = engine
  end
  if not conf then conf = readTTPPrivate() end
  if not conf then return nil end
  local offset = ttpPixels(conf.targetBuffVerticalOffset)
  local size = ttpPixels(conf.targetIconSize)
  if not offset or not size then return nil end
  return offset, size
end

-- Раскладка оверлея. Сетка канваса не используется: только perRow иконок в
-- ряд, без имён, таймер в оформлении первого канваса.
local function attachedCfg(unitType, perRow, size, count)
  local us = settings and settings[unitType]
  local first = (us and us.canvases and us.canvases[1]) or {}
  local spacing = math.floor(tonumber(first.iconSpacing) or 5)
  if spacing < 0 then spacing = 0 end
  if spacing > 12 then spacing = 12 end
  local timerSize = math.floor(tonumber(first.timerFontSize) or 14)
  local maxTimer = math.max(9, math.floor(size * 0.6))
  if timerSize > maxTimer then timerSize = maxTimer end
  if timerSize < 8 then timerSize = 8 end
  local rows = 1
  if count and count > 0 then
    rows = math.ceil(count / perRow)
    if rows < 1 then rows = 1 end
  end
  return {
    iconSize = size,
    iconSpacing = spacing,
    gridColumns = perRow,
    gridRows = rows,
    maxIcons = math.max(1, count or 1),
    gridRowSpacing = spacing,
    showLabel = false,
    labelFontSize = 12,
    labelX = 0,
    labelY = 0,
    showTimer = first.showTimer ~= false,
    timerFontSize = timerSize,
    timerX = 0,
    timerY = 0,
    timerTextColor = first.timerTextColor or { r = 1, g = 1, b = 1, a = 1 },
  }
end

local function attachedSig(cfg, buffs, count)
  local parts = {
    tostring(cfg.iconSize), tostring(cfg.iconSpacing), tostring(cfg.gridColumns),
    tostring(cfg.gridRowSpacing), tostring(cfg.showTimer and "1" or "0"),
    tostring(cfg.timerFontSize), colorSignature(cfg.timerTextColor), tostring(count)
  }
  for i = 1, count do
    local info = buffs[i]
    if info then
      parts[#parts + 1] = tostring(info.id) .. "="
        .. tostring(info.buff and info.buff.icon) .. "=" .. tostring(info.buff and info.buff.name)
    end
  end
  return table.concat(parts, "|")
end

-- Создаёт окно-оверлей с прозрачным фоном и без перехвата мыши.
-- 1.31.0: слой normal (выше слоя game, на котором TTP держит свой
-- targetBuffCanvas) + высокий z-order, чтобы строка рисовалась ПОВЕРХ ряда
-- TrackThatPlease, а не за ним. Клики всё так же проходят насквозь.
local function createAttachedWindow(id)
  local wnd = api.Interface:CreateEmptyWindow(id)
  if not wnd then return nil end
  pcall(function() wnd:SetUILayer("normal") end)
  pcall(function() if wnd.SetZOrder then wnd:SetZOrder(1000) end end)
  pcall(function() wnd:Clickable(false) end)
  pcall(function() wnd:EnablePick(false) end)
  wnd:Show(false)
  pcall(function() wnd:Raise() end)
  return wnd
end

local function ensureFrameOverlay(index)
  local holder = frameOverlays[index]
  if holder and holder.wnd then return holder end
  holder = { icons = {} }
  frameOverlays[index] = holder
  holder.wnd = createAttachedWindow("CBTFrameOverlay_" .. tostring(index))
  if not holder.wnd then return nil end
  holder.sig = nil
  holder.ax = nil
  holder.ay = nil
  holder.shown = false
  return holder
end

-- Show(true/false) только при смене состояния: оверлей перерисовывается
-- каждые 50 мс, лишние вызовы движка здесь не нужны.
local function setHolderShown(holder, shown)
  if not holder or not holder.wnd then return end
  shown = shown and true or false
  if holder.shown == shown then return end
  holder.shown = shown
  pcall(function() holder.wnd:Show(shown) end)
end

local function destroyFrameOverlay(index)
  local holder = frameOverlays[index]
  if not holder then return end
  frameOverlays[index] = nil
  if holder.wnd then
    pcall(function() holder.wnd:Show(false) end)
    pcall(function() api.Interface:Free(holder.wnd) end)
    holder.wnd = nil
  end
  holder.icons = {}
end

local function destroyFrameModes()
  local idx = 1
  while frameOverlays[idx] do
    destroyFrameOverlay(idx)
    idx = idx + 1
  end
  frameOverlays = {}
  frameCache = {}
end

hideFrameModesForUnit = function(unitType)
  if unitType == "target" then
    for _, oh in pairs(frameOverlays) do
      setHolderShown(oh, false)
    end
  end
end

-- Рисует icons holder'а по списку buffs (не больше MAX_GRID_ICONS).
-- Имена не показываются, порядок — как в buffs; пересборка только при
-- изменении подписи раскладки, статус/таймер — по изменению.
local function renderAttachedIcons(holder, unitType, namespace, buffs, cfg)
  if not holder or not holder.wnd then return end
  local count = #buffs
  if count > MAX_GRID_ICONS then count = MAX_GRID_ICONS end

  local sig = attachedSig(cfg, buffs, count)
  local relayout = (holder.sig ~= sig)

  if #holder.icons < count then
    for i = #holder.icons + 1, count do
      local icon = addBuffIcon(holder.wnd, i, unitType, namespace, cfg)
      if not icon then break end
      holder.icons[i] = icon
    end
  end

  local currentTime = tonumber(getCurrentTime()) or 0
  for i = 1, #holder.icons do
    local icon = holder.icons[i]
    if icon and icon.Show then
      if i <= count then
        local info = buffs[i]
        local buff = info.buff
        if relayout then
          icon:SetExtent(cfg.iconSize, cfg.iconSize)
          anchorIconInGrid(icon, holder.wnd, i, cfg)
          local paintOk, paintErr = pcall(CbtIcon.Paint, icon, buff.icon)
          if not paintOk then
            pcall(function()
              if F_SLOT and F_SLOT.SetIconBackGround then
                F_SLOT.SetIconBackGround(icon, nil)
              end
            end)
            if not lastRuntimeError.overlayIcon then
              lastRuntimeError.overlayIcon = true
              CbtLog.error("overlay icon paint failed: %s", tostring(paintErr))
            end
          end
          if icon.nameLabel then icon.nameLabel:Show(false) end
          if icon.timerLabel then
            icon.timerLabel.style:SetFontSize(cfg.timerFontSize or 14)
            icon.timerLabel:RemoveAllAnchors()
            icon.timerLabel:AddAnchor("CENTER", icon, cfg.timerX or 0, cfg.timerY or 0)
            local c = cfg.timerTextColor or { r = 1, g = 1, b = 1, a = 1 }
            icon.timerLabel.style:SetColor(c.r or 1, c.g or 1, c.b or 1, c.a or 1)
          end
          if icon.timerBg then
            icon.timerBg:SetExtent(cfg.iconSize, cfg.iconSize / 2)
            icon.timerBg:RemoveAllAnchors()
            icon.timerBg:AddAnchor("BOTTOM", icon, 0, 0)
          end
          icon:Show(true)
        end

        if icon.buffId ~= info.id then
          icon.buffId = info.id
        end

        local status = buff.status
        if buff.fixedTime then
          status = checkBuffStatus(buff, currentTime)
        end
        if relayout or icon.lastStatus ~= status then
          applyIconStatus(icon, status)
          icon.lastStatus = status
        end

        local timerText = ""
        if cfg.showTimer then
          timerText = iconTimerText(buff, status, currentTime)
        end
        if icon.lastTimerText ~= timerText then
          if icon.timerLabel then
            icon.timerLabel:SetText(timerText)
            icon.timerLabel:Show(timerText ~= "")
          end
          if icon.timerBg then icon.timerBg:Show(timerText ~= "") end
          icon.lastTimerText = timerText
        end
      else
        if icon.IsVisible == nil or icon:IsVisible() then
          icon:Show(false)
          if icon.timerLabel then icon.timerLabel:Show(false) end
          if icon.timerBg then icon.timerBg:Show(false) end
        end
        icon.lastStatus = nil
        icon.lastTimerText = nil
      end
    end
  end

  if relayout then
    local cols = cfg.gridColumns
    local usedCols = math.max(1, math.min(count, cols))
    local rows = math.max(1, math.ceil(count / cols))
    local width = usedCols * cfg.iconSize + (usedCols - 1) * cfg.iconSpacing
    local height = rows * cfg.iconSize + (rows - 1) * cfg.gridRowSpacing
    holder.wnd:SetExtent(width, height)
    holder.sig = sig
  end
end

-- 1.31.0: якорь оверлея к ряду TrackThatPlease и запасной расчёт. Всё в одной
-- таблице — у чанка main.lua жёсткий лимит 200 локальных имён.
local OverlayAnchor = {}

-- Зазор до ряда TTP: 0..200 px, по умолчанию 4.
function OverlayAnchor.gap(us)
  local gap = tonumber(us and us.ttpGap) or 4
  if gap < 0 then gap = 0 end
  if gap > 200 then gap = 200 end
  return gap
end

-- Экранная позиция оверлея: x и НИЖНЯЯ граница ряда (якорь BOTTOM).
-- TTP рисует свой target-ряд в мировых координатах, поэтому при загруженном
-- TTP наша строка встаёт над его рядом (topY - gap), иначе — от экранной
-- позиции цели с пользовательскими overlayX/overlayY. Настройки TTP берутся
-- из кэша (обновляются раз в 500 мс), сама позиция цели — уже свежая.
local function overlayScreenPosition(cfg, cache)
  local us = settings and settings.target
  local avoidTTP = not (us and us.avoidTTP == false)
  if avoidTTP then
    local ttpOffset, ttpSize = cache and cache.ttpOffset, cache and cache.ttpSize
    if ttpOffset and ttpSize then
      local gap = OverlayAnchor.gap(us)
      local bottom = cache.screenY + ttpOffset
      return cache.screenX, bottom - ttpSize - gap
    end
  end
  local ox = tonumber(cfg and cfg.overlayX) or 0
  local oy = tonumber(cfg and cfg.overlayY) or -30
  return cache.screenX + ox, cache.screenY + oy
end

-- 1.31.0: якорь к реальному ряду TrackThatPlease: наш низ ставится на зазор
-- выше его верхнего левого угла (BOTTOM -> TOPLEFT, -gap). Якорь ставится
-- ТОЛЬКО при смене канваса или зазора: TTP двигает свой ряд сам, наш едет
-- за ним без RemoveAllAnchors/AddAnchor на каждом кадре.
function OverlayAnchor.toTTP(holder, ttpCanvas, gap)
  if not (holder and holder.wnd and ttpCanvas) then return false end
  -- Сравнение по самой ссылке на виджет + зазору: строка с tostring() у
  -- userdata может меняться от вызова к вызову и вызывала бы лишний якорь.
  if holder.anchorKey == "ttp" and holder.anchorTTP == ttpCanvas and holder.anchorGap == gap then
    return true
  end
  local ok = pcall(function()
    holder.wnd:RemoveAllAnchors()
    holder.wnd:AddAnchor("BOTTOM", ttpCanvas, "TOPLEFT", 0, -gap)
  end)
  if not ok then return false end
  holder.anchorKey = "ttp"
  holder.anchorTTP = ttpCanvas
  holder.anchorGap = gap
  holder.ax, holder.ay = nil, nil
  return true
end

-- Ставит окно оверлея на (x, bottom) в целых пикселях. RemoveAllAnchors и
-- AddAnchor вызываются ТОЛЬКО когда округлённая позиция сдвинулась на >= 1 px
-- (как в TrackThatPlease): иначе виджеты дёргаются каждый кадр вхолостую.
local function applyOverlayAnchor(holder, x, bottomY)
  if not holder or not holder.wnd or not x or not bottomY then return end
  x = math.floor(x + 0.5)
  bottomY = math.floor(bottomY + 0.5)
  if holder.anchorKey == "screen" and holder.ax == x and holder.ay == bottomY then return end
  holder.anchorKey = "screen"
  holder.ax, holder.ay = x, bottomY
  pcall(function()
    holder.wnd:RemoveAllAnchors()
    holder.wnd:AddAnchor("BOTTOM", "UIParent", "TOPLEFT", x, bottomY)
  end)
end

-- Одно место выбора якоря: реальный ряд TTP (follow), иначе проекция цели с
-- настройками TTP (targetBuffVerticalOffset / targetIconSize), иначе
-- пользовательские overlayX/overlayY.
function OverlayAnchor.place(holder, cfg, cache)
  if not (holder and holder.wnd) then return false end
  local us = settings and settings.target
  local gap = OverlayAnchor.gap(us)
  local ttpCanvas = cache and cache.ttpCanvas or nil
  if ttpCanvas and not (us and us.avoidTTP == false) and TTPRow.usable(ttpCanvas) then
    if OverlayAnchor.toTTP(holder, ttpCanvas, gap) then return true end
  end
  local x, bottomY = overlayScreenPosition(cfg or {}, cache)
  if not x or not bottomY then return false end
  applyOverlayAnchor(holder, x, bottomY)
  return true
end

-- 1.25.0: оверлей цели ведётся каждый кадр (TrackThatPlease-стиль).
-- Каждый кадр читается только проекция + target id; рамка/полоса/настройки
-- TTP остаются на 500-мс кэше, баффы/ауры не опрашиваются чаще прежнего.
-- Цель потеряна или проекция негодна — все окна оверлея прячутся.
local function updateTargetOverlayPositions()
  local us = settings and settings.target
  if not (us and us.overlay == true) then return end
  local cache = frameCache.target
  local visible = cache and cache.visible
    and getCurrentTargetId() ~= nil
    and readTargetScreen(cache)
    and targetScreenSane(cache)
  if not visible then
    for _, oh in pairs(frameOverlays) do
      setHolderShown(oh, false)
    end
    return
  end
  local canvases = us.canvases or {}
  for idx = 1, #canvases do
    local holder = frameOverlays[idx]
    if holder and holder.shown and holder.wnd then
      OverlayAnchor.place(holder, canvases[idx] or {}, cache)
    end
  end
end

local function renderTargetOverlays(activeBuffs)
  local us = settings and settings.target
  local enabled = us and us.overlay == true
  local canvases = (us and us.canvases) or {}

  if not enabled then
    for _, oh in pairs(frameOverlays) do
      setHolderShown(oh, false)
    end
    return
  end

  local cache = frameCache.target
  -- Если позиция ещё не читалась (первый рендер после сохранения настроек),
  -- берём её здесь же: иначе оверлей мигнул бы до следующего кадра.
  if cache and not cache.screenX then readTargetScreen(cache) end
  local baseVisible = cache and cache.visible and targetScreenSane(cache)
  if baseVisible and getCurrentTargetId() == nil then baseVisible = false end

  for idx = 1, #canvases do
    local cfg = canvases[idx] or {}
    local holder = frameOverlays[idx]

    local subset = {}
    if baseVisible then
      for _, info in ipairs(activeBuffs) do
        if canvasIndexFor(us, info.id) == idx then
          subset[#subset + 1] = info
        end
      end
    end

    if #subset == 0 then
      setHolderShown(holder, false)
    else
      if not holder then holder = ensureFrameOverlay(idx) end
      if holder and holder.wnd then
        local size = math.floor(tonumber(cfg.overlaySize) or 26)
        if size < 12 then size = 12 end
        if size > 64 then size = 64 end
        local perRow = math.floor(tonumber(cfg.overlayPerRow) or 6)
        if perRow < 1 then perRow = 1 end
        if perRow > 12 then perRow = 12 end

        -- Свежая позиция уже посчитана updateTargetOverlayPositions() в этом
        -- кадре; здесь якорь нужен лишь для только что показанного окна.
        if not OverlayAnchor.place(holder, cfg, cache) then
          setHolderShown(holder, false)
        else
          local ocfg = attachedCfg("target", perRow, size, #subset)
          renderAttachedIcons(holder, "target", 110 + idx, subset, ocfg)
          setHolderShown(holder, true)
        end
      end
    end
  end

  local idx = #canvases + 1
  while frameOverlays[idx] do
    destroyFrameOverlay(idx)
    idx = idx + 1
  end
end

-- Точка входа из updateBuffIcons: обновляет оверлей цели.
local function renderFrameModes(unitType, activeBuffs)
  if not settings then return end
  local nowMs = 0
  local ok, msec = pcall(function() return api.Time:GetUiMsec() end)
  if ok and type(msec) == "number" then nowMs = msec end
  refreshFrameCache(unitType, nowMs)

  if unitType == "target" then
    renderTargetOverlays(activeBuffs)
  end
end

-- 1.26.0: Hide target canvas — плавающие канвасы цели не рисуются совсем.
-- Данные при этом собираются как обычно (checkBuffs), а оверлей, если включён,
-- продолжает рисоваться из renderFrameModes.
local function floatingCanvasesHidden(unitType, unitSettings)
  return unitType == "target" and unitSettings.hideCanvas == true
end

local function updateBuffIcons(unitType)
  unitType = unitType or "playerpet"  -- По умолчанию используем mount

  local unitSettings = settings and settings[unitType]
  if not unitSettings then return end
  local canvasesForUnit = unitCanvases[unitType] or {}
  if #canvasesForUnit == 0 then
    -- Режим у нативного фрейма рисует данные и без плавающего канваса:
    -- создаём канвасы (они будут скрыты) ради одного сканирования аур.
    if not (frameModeEnabled and frameModeEnabled(unitType)) then return end
    ensureUnitCanvases(unitType)
    canvasesForUnit = unitCanvases[unitType] or {}
    if #canvasesForUnit == 0 then return end
  end

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
        local now = getCurrentTime()
        for _, buffInfo in ipairs(activeBuffs) do
          local rec = buffInfo.buff
          local syntheticLive = rec and rec.synthetic and rec.fixedTime
            and (tonumber(rec.readyAt) or 0) > now
          if historyBuffs[buffInfo.id] or syntheticLive then
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
      local now = getCurrentTime()

      for _, buffInfo in ipairs(activeBuffs) do
        local rec = buffInfo.buff
        -- History normally marks everything seen on this target. Synthetic
        -- skill records (combat-log triggers) are valid cooldowns even when
        -- that history was lost/rebuilt; keep them while their cooldown runs.
        local syntheticLive = rec and rec.synthetic and rec.fixedTime
          and (tonumber(rec.readyAt) or 0) > now
        if historyBuffs[buffInfo.id] or syntheticLive then
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

  -- 1.31.0: оверлей цели и плавающие панели независимы. Плавающие канвасы
  -- прячет ТОЛЬКО Hide target canvas (settings.target.hideCanvas); оверлей лишь
  -- добавляет свою строку у цели.
  local hideFloating = floatingCanvasesHidden(unitType, unitSettings)

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
      if hideFloating then
        -- Плавающую панель прячет только Hide target canvas; данные при этом
        -- продолжают собираться, а оверлей (если включён) рисуется сам.
        if canvas.IsVisible and canvas:IsVisible() then canvas:Show(false) end
      elseif #canvasBuffs == 0 then
        canvas:Show(false)
      else
        renderCanvas(canvas, unitType, cfg, canvasBuffs)
      end
    end
  end

  if unitType == "target" and settings and settings.debugBuffId then
    local now = getCurrentTime()
    if not lastRuntimeError.targetDrawAt or (now - lastRuntimeError.targetDrawAt) >= 2 then
      lastRuntimeError.targetDrawAt = now
      local parts = {}
      for _, info in ipairs(activeBuffs) do
        local b = info.buff
        parts[#parts + 1] = tostring(info.id) .. ":status=" .. tostring(b.status)
          .. ":fixed=" .. tostring(b.fixedTime) .. ":ready=" .. tostring(b.readyAt)
          .. ":synthetic=" .. tostring(b.synthetic)
      end
      CbtDebugLog.info("target draw: id=" .. tostring(currentTargetId)
        .. " tracked=" .. tostring(#trackedBuffIds)
        .. " active=" .. tostring(#activeBuffs)
        .. " canvases=" .. tostring(#canvasesForUnit)
        .. " history=" .. tostring(targetActiveBuffs[currentTargetId] ~= nil)
        .. " " .. table.concat(parts, "; "))
    end
  end

  renderFrameModes(unitType, activeBuffs)
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
  -- Снимок аур цели для эффективных КД (1.28.0); заполняется только для target.
  local effectiveSnapshot = nil
  -- A target switch must force a redraw even when the new target has no auras;
  -- otherwise the old canvas stays on screen with its last timer text.
  local targetChanged = false

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
      CbtLog.debug("target switch: %s -> %s", tostring(currentTargetId), tostring(newTargetId))
      CbtDebugLog.info("target switch: " .. tostring(currentTargetId) .. " -> " .. tostring(newTargetId))
      targetChanged = true
      -- Save current target data to cache before switching
      if currentTargetId and targetCache[currentTargetId] then
        targetCache[currentTargetId].buffStates = {}
        for buffId, buffInfo in pairs(targetBuffData) do
          targetCache[currentTargetId].buffStates[buffId] = {
            fixedTime = buffInfo.fixedTime,
            activeUntil = buffInfo.activeUntil,
            readyAt = buffInfo.readyAt,
            effCD = buffInfo.effCD,
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
      local newCache = ensureTargetCacheEntry(newTargetId)
      if not newCache then
        newCache = { lastSeen = currentTime, buffStates = {} }
        targetCache[newTargetId] = newCache
      end
      -- Restore buff data from cache. The history table is what the target
      -- renderer uses to decide which records to keep; without this, a target
      -- that was left and re-acquired showed an empty panel until every record
      -- was triggered again.
      if not targetActiveBuffs[newTargetId] then
        targetActiveBuffs[newTargetId] = {}
      end
      for buffId, cachedBuff in pairs(newCache.buffStates) do
        targetActiveBuffs[newTargetId][buffId] = true
        targetBuffData[buffId] = {
          name = cachedBuff.name,
          icon = cachedBuff.icon,
          cooldown = cachedBuff.cooldown,
          timeOfAction = cachedBuff.timeOfAction,
          fixedTime = cachedBuff.fixedTime,
          activeUntil = cachedBuff.activeUntil,
          readyAt = cachedBuff.readyAt,
          effCD = cachedBuff.effCD,
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

      -- Класс новой цели читаем сразу, не дожидаясь троттлинга
      targetClassCheckedAt = 0
      -- Reset-моды на цели: первый опрос после возврата к этой цели снова
      -- только запоминает уже висящие баффы (появлением они не считаются).
      newCache.resetSeen = nil
    else
      -- Same target, update lastSeen and save to display cache
      lastDisplayedTargetId = newTargetId
      lastTargetLostTime = nil
    end

    -- Update lastSeen for current target
    if targetCache[currentTargetId] then
      targetCache[currentTargetId].lastSeen = currentTime
    end

    -- Эффективные КД: снимок аур текущей цели и класс ИМЕННО этого id.
    -- Без включённых записей ауры лишний раз не читаем.
    if targetUsesEffective() then
      effectiveSnapshot = readTargetAuras()
      if effectiveSnapshot then
        maybeCheckTargetClass(currentTargetId, currentTime)
      end
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
  local hasChanges = targetChanged
  local currentBuffsOnUnit = {}
  -- Все ауры цели за этот тик: нужны эффективным КД (flat/percent-моды,
  -- стаки, reset-проки), в том числе для навыков, которые не отслеживаются.
  local auraNow = nil
  if unitType == "target" then auraNow = effectiveSnapshot or {} end
  -- Reset-модификаторы: появление их баффа на цели обнуляет таймер записи.
  if effectiveSnapshot then
    if processTargetResets(effectiveSnapshot, getCurrentTime(), targetBuffData, currentTargetId) then
      hasChanges = true
    end
  end

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
          -- Эффективный КД (1.28.0): момент применения баффа — появление ауры.
          local effCD = nil
          if effectiveSnapshot then
            local effEntry = effectiveEntryFor(buff.buff_id)
            if effEntry then
              effCD = applyEffectiveCD(effEntry, effectiveSnapshot, now, currentTargetId)
            end
          end
          if anchorNow then
            -- Якорь — момент обнаружения: кулдаун после диспела отсчитывается от
            -- применения, а не от настроенной длительности
            setBuffStatus(buff.buff_id, "active", now, unitType, nil, nil, effCD)
          else
            setBuffStatus(buff.buff_id, "active", now, unitType, remaining, nil, effCD)
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
        elseif (isNewBuff or refreshed) and triggeredAnchor and effectiveSnapshot then
          -- Синтетическую запись уже запустил боевой лог; для баффа/дебаффа момент
          -- применения — появление ауры. Навык считается по касту, второй раз
          -- smart-интервал не трогаем (иначе аура сразу после каста = «рано»).
          local effEntry = effectiveEntryFor(buff.buff_id)
          local rec = buffDataTable[buff.buff_id]
          if effEntry and helpers.entryKind(effEntry) ~= "skill"
            and rec and rec.fixedTime then
            local effCD = applyEffectiveCD(effEntry, effectiveSnapshot, now, currentTargetId)
            if effCD ~= nil then
              rec.effCD = effCD
              rec.readyAt = rec.fixedTime + effCD
              hasChanges = true
            end
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
            -- Эффективный КД (1.28.0): момент применения дебаффа — появление ауры.
            local effCD = nil
            if effectiveSnapshot then
              local effEntry = effectiveEntryFor(debuff.buff_id)
              if effEntry then
                effCD = applyEffectiveCD(effEntry, effectiveSnapshot, now, currentTargetId)
              end
            end
            if anchorNow then
              -- Якорь — момент обнаружения (кулдаун от применения, не от длительности)
              setBuffStatus(debuff.buff_id, "active", now, unitType, nil, nil, effCD)
            else
              -- Дебафф уже висел до того, как мы его увидели — оцениваем старт по остатку
              setBuffStatus(debuff.buff_id, "active", now, unitType, remaining, nil, effCD)
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
          elseif (isNewDebuff or refreshed) and triggeredAnchor and effectiveSnapshot then
            local effEntry = effectiveEntryFor(debuff.buff_id)
            local rec = buffDataTable[debuff.buff_id]
            if effEntry and helpers.entryKind(effEntry) ~= "skill"
              and rec and rec.fixedTime then
              local effCD = applyEffectiveCD(effEntry, effectiveSnapshot, now, currentTargetId)
              if effCD ~= nil then
                rec.effCD = effCD
                rec.readyAt = rec.fixedTime + effCD
                hasChanges = true
              end
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

  -- ===== Mirror: ауру читаем с player, показываем на текущем target =====
  -- Включено кнопкой Mir у записи в Tracked entries (список Target).
  -- Лог не используем: атрибуция — тот, кто является целью в момент наложения.
  local mirrorCfg = (settings and settings.target) and settings.target.mirror or nil
  local hasMirror = false
  if type(mirrorCfg) == "table" then
    -- только баффы/дебаффы: флаги у skill/mana-записей игнорируем
    for k in pairs(mirrorCfg) do
      if mirrorAllowed(k) then hasMirror = true break end
    end
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
      if settings.target.mirror[key] and not activeBuffsOnUnit[mirrorId]
        and mirrorAllowed(mirrorId) then
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
            effCD = buffInfo.effCD,
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

-- 1.32.0: иконки навыков с wiki-страниц классов (skill_dump.tbl) живут в том же
-- пуле, что и иконки баффов: одна таблица byName/list на поиск и авто-подстановку.
-- Формат строки тот же: id \t имя \t путь. Дамп навыков необязателен — старые
-- установки без него грузятся как раньше.
local function loadSkillDump(byName, entries)
  local data = readDumpFile("CooldawnBuffTracker/skill_dump.tbl")
  if not data then
    data = readDumpFile("skill_dump.tbl")
  end
  if not data then return 0 end
  local n = 0
  for line in data.dump:gmatch("[^\n]+") do
    local id, name, path = line:match("^(%d+)\t([^\t]*)\t(.*)$")
    if id and name and path and path ~= "" then
      n = n + 1
      addDumpEntry(byName, id, name, path)
      entries[#entries + 1] = { id = tonumber(id), name = name, path = normalizeTexturePath(path) }
    end
  end
  return n
end

local function loadBuffDump()
  if not (api.File and api.File.Read) then return end
  -- дамп живёт в папке аддона; корень Addon читаем только как наследие старых версий
  local data = readDumpFile("CooldawnBuffTracker/buff_dump.tbl")
  if not data then
    data = readDumpFile("buff_dump.tbl")
  end
  local byName = {}
  local entries = {}
  local buffN = 0
  if data then
    for line in data.dump:gmatch("[^\n]+") do
      local id, name, path = line:match("^(%d+)\t([^\t]*)\t(.*)$")
      if id and name and path and path ~= "" then
        buffN = buffN + 1
        addDumpEntry(byName, id, name, path)
        entries[#entries + 1] = { id = tonumber(id), name = name, path = normalizeTexturePath(path) }
      end
    end
  end
  local skillN = loadSkillDump(byName, entries)
  if buffN + skillN > 0 then
    buffDump = { byName = byName, list = buildDumpList(entries), count = buffN + skillN }
    CbtLog.info("buff dump: %s buffs, %s skill icons", buffN, skillN)
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
        CbtLog.info("icon from dump: %s -> %s", tostring(cb.spellName), e.path)
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
  CbtLog.info("buff dump: '%s' -> id=%s path=%s (entries updated: %s)",
    nameKey, tostring(id), tostring(path), applied)
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
  CbtLog.info("buff scan: dumping all buffs%s (1..50000, 8000000..8001000)",
    (key ~= "" and locale.L(" + search '%s'", name)) or "")
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

-- 1.27.0: фоновый журнал баффов по юниту. Копится в UPDATE, пока Debug: ON,
-- даже если окно Record закрыто; окно только читает готовый журнал.
-- Запись: { id, name, icon, count, last, active }; count растёт только при
-- повторном появлении (пока бафф висит — не растёт).
local BUFF_JOURNAL_CAP = 300
local BUFF_JOURNAL_INTERVAL = 200 -- мс: чаще ауры не опрашиваем
local buffJournals = {}
local buffJournalTimer = 0

local function buffJournalOf(unitType)
  local j = buffJournals[unitType]
  if not j then
    j = { order = {}, map = {} }
    buffJournals[unitType] = j
  end
  return j
end

-- Debug OFF -> ON: журналы трёх юнитов начинаются заново (как aura dump).
local function resetBuffJournals()
  buffJournals = {}
  buffJournalTimer = 0
end

local function journalNowMsec()
  local ok, ms = pcall(function() return api.Time:GetUiMsec() end)
  if ok and type(ms) == "number" then return ms end
  return 0
end

-- Один сэмпл активных аур юнита: новый id -> строка наверх (count=0),
-- повторное появление -> count+1 и снова наверх; снятые остаются серыми.
local function sampleBuffJournal(unitType)
  local list = getActiveBuffs(unitType)
  local j = buffJournalOf(unitType)
  local seen = {}
  local now
  for _, it in ipairs(list) do
    local key = tostring(it.id)
    if not seen[key] then
      seen[key] = true
      local e = j.map[key]
      if not e then
        e = { id = it.id, name = it.name, icon = it.icon, count = 0, active = false }
        j.map[key] = e
        table.insert(j.order, 1, key)
      end
      if not e.active then
        -- Не был активен в прошлом сэмпле — это новое появление.
        e.count = (e.count or 0) + 1
        if now == nil then now = journalNowMsec() end
        e.last = now
        for i = #j.order, 1, -1 do
          if j.order[i] == key then
            table.remove(j.order, i)
            break
          end
        end
        table.insert(j.order, 1, key)
      end
      e.name = it.name or e.name
      e.icon = it.icon or e.icon
      e.active = true
    end
  end
  for key, e in pairs(j.map) do
    if not seen[key] then e.active = false end
  end
  -- Потолок 300 записей на юнит. Сначала вытесняем погасшие записи (снизу —
  -- самые старые), и только если все записи активны, самые старые вообще:
  -- иначе активный бафф, выброшенный из журнала, возвращался бы на каждом
  -- сэмпле как «новый» и прыгал наверх, ломая порядок.
  while #j.order > BUFF_JOURNAL_CAP do
    local victim = #j.order
    for i = #j.order, 1, -1 do
      local key = j.order[i]
      local e = j.map[key]
      if e and not e.active then
        victim = i
        break
      end
    end
    local old = j.order[victim]
    table.remove(j.order, victim)
    j.map[old] = nil
  end
end

-- Новейшие сверху; копия — окно не должно менять журнал.
local function getBuffLog(unitType)
  local out = {}
  local j = buffJournals[unitType or "player"]
  if not j then return out end
  for i = 1, #j.order do
    local e = j.map[j.order[i]]
    if e then
      out[#out + 1] = { id = e.id, name = e.name, icon = e.icon,
                        count = e.count, last = e.last, active = e.active }
    end
  end
  return out
end

-- Очистка журнала одного юнита (Clear log в окне Record); без юнита — всех.
local function clearBuffLog(unitType)
  if unitType then
    buffJournals[unitType] = { order = {}, map = {} }
    return
  end
  buffJournals = {}
end

-- Очистка журнала навыков выбранного юнита (кнопка Clear log в окне Record)
local function clearLoggedSpells(unitType)
  local store = loggedSpells[unitType]
  if not store then return end
  for i = #store.order, 1, -1 do
    store.order[i] = nil
  end
  for name in pairs(store.map) do
    store.map[name] = nil
  end
end

-- Навыки из боевого лога выбранного юнита (свежие сверху) для окна Record
local function getLoggedSpells(unitType, limit)
  local out = {}
  local store = loggedSpells[unitType]
  if not store then return out end
  for i = #store.order, 1, -1 do
    local e = store.map[store.order[i]]
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

if settingsPage then
  settingsPage.searchIcons = searchIcons
  settingsPage.applyBuffOverride = applyBuffOverride
  settingsPage.getActiveBuffs = getActiveBuffs
  settingsPage.getBuffLog = getBuffLog
  settingsPage.clearBuffLog = clearBuffLog
  settingsPage.getLoggedSpells = getLoggedSpells
  settingsPage.clearLoggedSpells = clearLoggedSpells
  settingsPage.findIconByName = findIconByName
  -- 1.28.0: карточка Reference в Edit окне считает значения на живой цели
  settingsPage.getEffectivePreview = getEffectivePreview
end

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
    -- 1.34.0: скан пишет ТОЛЬКО buff_dump.tbl (см. api.File.Write выше);
    -- skill_dump.tbl — поставляемый файл, он здесь лишь перечитывается. Если его
    -- нет (старая установка или файл потерян), пул остаётся buff-only и мы
    -- предупреждаем, но скан не валим.
    local skillDumpOk = readDumpFile("CooldawnBuffTracker/skill_dump.tbl") ~= nil
      or readDumpFile("skill_dump.tbl") ~= nil
    local skillN = loadSkillDump(byName, entries)
    buffDump = { byName = byName, list = buildDumpList(entries), count = #st.entries + skillN }
    CbtLog.info("buff dump: %s buffs, %s; tables=%s named=%s errors=%s%s",
      #st.entries,
      saved and locale.L("saved to buff_dump.tbl") or locale.L("NOT saved (api.File unavailable)"),
      tostring(st.tables), tostring(st.named), tostring(st.errors),
      (st.firstError and locale.L(" | first error: %s", st.firstError)) or "")
    if skillN > 0 then
      CbtLog.info("buff dump: %s buffs, %s skill icons", #st.entries, skillN)
    else
      CbtLog.warn(locale.L(skillDumpOk
        and "skill_dump.tbl holds no skill rows"
        or "skill_dump.tbl missing: skill icons are not in the icon pool"))
    end
    if st.target ~= "" then
      local e = byName[st.target]
      if e then
        applyBuffIcon(st.target, e.id, e.path)
      else
        CbtLog.warn("buff dump: '%s' not found", st.target)
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
          CbtLog.debug("mana cast %s cost=%s spend=%.1f regen=%.1f mount=%s",
            tostring(best.id), tostring(best.cost), spend, regen or 0, petName)
        end
      elseif settings.debugBuffId then
        local detail = {}
        for _, e in ipairs(entries) do
          detail[#detail + 1] = string.format("%s(mount=%s,ready=%s)",
            tostring(e.cost), tostring(e.mount), tostring(e.ready))
        end
        CbtLog.debug("mana drop %.1f (regen %.1f) — no match; pet='%s'; mount-blocked=%d cd-blocked=%d; entries: %s",
          spend, regen or 0, petName, blockedByMount, blockedByCd, table.concat(detail, " | "))
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
  -- The game log reported `bad argument to string` at this call. Keep the
  -- diagnostic writer alive and record exactly what was passed instead of
  -- letting one malformed debug value kill UPDATE.
  local okText, text = pcall(tostring, line)
  if not okText or type(text) ~= "string" then
    text = "<" .. type(line) .. ">"
  end
  local okFmt, formatted = pcall(string.format, "%.1f %s",
    tonumber(getCurrentTime()) or 0, text)
  if not okFmt then
    CbtDebugLog.error("debugRecord format failed: " .. tostring(formatted)
      .. "; original type=" .. type(line))
    return
  end
  debugAuraLines[#debugAuraLines + 1] = formatted
  debugAuraDirty = true
end

-- Safe formatter for debug journal rows: a malformed value from the client
-- must never throw inside UPDATE (the game log showed `bad argument to string`).
local function debugRecordf(fmt, ...)
  local args = { ... }
  local ok, text = pcall(string.format, fmt, unpack(args))
  if not ok then
    local types = {}
    for i = 1, #args do types[i] = type(args[i]) end
    CbtDebugLog.error("debugRecord format failed: " .. tostring(text)
      .. "; types=" .. table.concat(types, ","))
    return
  end
  debugRecord(text)
end

local function flushAuraDump()
  if not debugAuraDirty then return end
  debugAuraDirty = false
  local ok = pcall(function()
    api.File:Write(AURA_DUMP_PATH, { dump = table.concat(debugAuraLines, "\n") })
  end)
  if not ok then CbtLog.error("aura dump: write failed") end
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
  -- Capture each API result before tostring: these functions can return ZERO
  -- values in the client (not even nil), and `tostring(f())` with zero returns
  -- becomes `tostring()` -> "bad argument #1 (value expected)", killing UPDATE.
  local targetName = api.Unit:UnitName("target")
  local targetClass = api.Unit:UnitClass("target")
  local targetClassName = api.Ability:GetUnitClassName("target")
  debugRecord("[target] id=" .. tostring(id) .. " name=" .. tostring(targetName or "nil"))
  debugRecord("[class] UnitClass=" .. tostring(targetClass or "nil")
    .. " GetUnitClassName=" .. tostring(targetClassName or "nil"))
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
          debugRecordf("+ %s id=%s name=%s stack=%s time=%s",
            kind, key, debugAuraName(b.buff_id), tostring(b.stack), tostring(b.timeLeft))
        elseif prev.stack ~= now[key].stack then
          debugRecordf("~ %s id=%s name=%s stack=%s time=%s",
            kind, key, debugAuraName(b.buff_id), tostring(b.stack), tostring(b.timeLeft))
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
      debugRecordf("- %s id=%s name=%s", prev.kind, key, debugAuraName(tonumber(key) or key))
    end
  end
  debugAuraState = now
end

local function updateStep(dt)
  if not live then return end
  CbtDebugLog.heartbeat("UPDATE target=" .. tostring(currentTargetId))
  local scanOk, scanErr = pcall(processBuffIconScan)
  if not scanOk and not lastRuntimeError.scan then
    lastRuntimeError.scan = true
    CbtLog.error("icon scan failed: %s", tostring(scanErr))
  end
  -- Мастер-выключатель из списка аддонов (ESC-меню), поле settings.enabled
  if settings and settings.enabled == false then
    hideAllCanvases()
    return
  end
  -- 1.25.0: оверлей цели переставляется каждый кадр — баффы и рамка при этом
  -- не опрашиваются (их частота прежняя).
  local overlayOk, overlayErr = pcall(updateTargetOverlayPositions)
  if not overlayOk and not lastRuntimeError.overlay then
    lastRuntimeError.overlay = true
    CbtLog.error("overlay update failed: %s", tostring(overlayErr))
  end
  -- Мана маунта: сэмплим чаще, чем баффы (100 мс), чтобы не терять мелкие траты
  manaTimer = manaTimer + dt
  if manaTimer >= 100 then
    local step = manaTimer / 1000
    manaTimer = 0
    local manaOk, manaErr = pcall(pollMountMana, step)
    if not manaOk and not lastRuntimeError.mana then
      lastRuntimeError.mana = true
      CbtLog.error("mana poll failed: %s", tostring(manaErr))
    end
  end

  if settings and settings.debugBuffId then
    if not debugWasOn then
      debugWasOn = true
      debugAuraLines = {}
      debugAuraState = {}
      debugAuraTarget = nil
      debugAuraDirty = true
      -- 1.27.0: журналы журнала Record начинаются заново вместе с aura dump
      resetBuffJournals()
      debugRecord("[session] aura dump started")
      flushAuraDump()
      CbtLog.debug("aura dump -> %s", AURA_DUMP_PATH)
    end
    debugAuraTimer = debugAuraTimer + dt
    if debugAuraTimer >= 100 then
      debugAuraTimer = 0
      local auraOk, auraErr = pcall(watchTargetAuras)
      if not auraOk and not lastRuntimeError.aura then
        lastRuntimeError.aura = true
        CbtLog.error("aura watcher failed: %s", tostring(auraErr))
      end
    end
    debugAuraFlushTimer = debugAuraFlushTimer + dt
    if debugAuraFlushTimer >= 1000 then
      debugAuraFlushTimer = 0
      flushAuraDump()
    end
    -- 1.27.0: журнал баффов для окна Record копится в фоне (5 Гц по трём
    -- юнитам) даже при закрытом окне; чаще ауры не опрашиваем.
    buffJournalTimer = buffJournalTimer + dt
    if buffJournalTimer >= BUFF_JOURNAL_INTERVAL then
      buffJournalTimer = 0
      for _, unitType in ipairs(UNIT_TYPES) do
        local journalOk, journalErr = pcall(sampleBuffJournal, unitType)
        if not journalOk and not lastRuntimeError.journal then
          lastRuntimeError.journal = true
          CbtLog.error("buff journal failed: %s", tostring(journalErr))
        end
      end
    end
  else
    if debugWasOn then
      flushAuraDump()
      debugWasOn = false
    end
    debugAuraState = {}
    debugAuraTarget = nil
    debugAuraTimer = 0
    -- Журналы не сэмплим; сами записи держим — их сбросит OFF -> ON.
    buffJournalTimer = 0
  end

  updateTimer = updateTimer + dt
  if updateTimer >= updateInterval then
    for _, unitType in ipairs(UNIT_TYPES) do
      local okCheck, checkErr = pcall(checkBuffs, unitType)
      if not okCheck then
        local key = "check_" .. tostring(unitType)
        if not lastRuntimeError[key] then
          lastRuntimeError[key] = true
          CbtLog.error("checkBuffs(%s) failed: %s", tostring(unitType), tostring(checkErr))
        end
      end
    end
    updateTimer = 0
  end

  refreshUITimer = refreshUITimer + dt
  if refreshUITimer >= refreshUIInterval then
    for _, unitType in ipairs(UNIT_TYPES) do
      if #(unitCanvases[unitType] or {}) > 0
          or (frameModeEnabled and frameModeEnabled(unitType)) then
        local okDraw, drawErr = pcall(updateBuffIcons, unitType)
        if not okDraw then
          local key = "draw_" .. tostring(unitType)
          if not lastRuntimeError[key] then
            lastRuntimeError[key] = true
            CbtLog.error("updateBuffIcons(%s) failed: %s", tostring(unitType), tostring(drawErr))
          end
        end
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
    local cleanOk, cleanErr = pcall(cleanupTargetCache)
    if not cleanOk and not lastRuntimeError.cache then
      lastRuntimeError.cache = true
      CbtLog.error("target cache cleanup failed: %s", tostring(cleanErr))
    end
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
    CbtLog.info("UI initialization for %s: %s", unitType,
      shouldShowUI and locale.L("show") or locale.L("hide"))

    if shouldShowUI then
      local created = ensureUnitCanvases(unitType)
      if created or #(unitCanvases[unitType] or {}) > 0 then
        updateBuffIcons(unitType)
      else
        CbtLog.error("Error creating canvases for %s", unitType)

        -- Повторная попытка создания канвасов с задержкой
        api:DoIn(1000, function()
          if not live then return end
          local retryCreated = ensureUnitCanvases(unitType)
          if retryCreated or #(unitCanvases[unitType] or {}) > 0 then
            updateBuffIcons(unitType)
          else
            CbtLog.error("Repeated error creating canvases for %s", unitType)
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
    CbtLog.debug("msg %s src=%s tgt=%s spell=%s id=%s",
      tostring(combatEvent), tostring(args[3]), tostring(args[4]),
      tostring(parsed.spellName), tostring(parsed.spellId))
  end
  if parsed.spellName then
    -- Журнал Record: только если источник совпал с именем player/mount/target.
    local logUnit = loggedSpellUnitFor(args[3])
    if logUnit then
      recordLoggedSpell(logUnit, parsed.spellName, getCurrentTime())
    end
    local triggerOk, triggerErr = pcall(triggerSpell,
      parsed.spellName, args[3], parsed.spellId, args, combatEvent)
    if not triggerOk and not lastRuntimeError.trigger then
      lastRuntimeError.trigger = true
      CbtLog.error("skill trigger failed: %s", tostring(triggerErr))
    end
  end
end

local function OnLoad()
  -- Загружаем настройки (миграция плоских полей в canvases уже внутри)
  if helpers then
    settings = helpers.getSettings()
  else
    CbtLog.warn("Helpers module not loaded, using basic settings")
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

  -- Уровень debug в логгере: серые сообщения печатаются только при Debug ON
  CbtLog.setDebug(settings and settings.debugBuffId)
  CbtDebugLog.reset()
  CbtDebugLog.setEnabled(settings and settings.debugBuffId)

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

  -- Диагностика кастомных баффов: видно, чем они ключуются и какие CD/D у них
  if settings and settings.debugBuffId then
    for _, cb in ipairs(settings.customBuffs or {}) do
      CbtLog.debug("custom: id=%s name=%s spell=%s CD=%s D=%s",
        tostring(cb.id), tostring(cb.name), tostring(cb.spellName),
        tostring(cb.cooldown), tostring(cb.timeOfAction))
    end
  end

  -- Расширенное ESC-меню (аддон ESCMenu): своя строка настроек
  local function openFromEscMenu()
    if settingsPage and settingsPage.openSettingsWindow then
      settingsPage.openSettingsWindow()
    end
  end
  if type(ESCMenu) == "table" and type(ESCMenu.RegisterAddonBtn) == "function" then
    pcall(ESCMenu.RegisterAddonBtn, ESCMenu, "CooldawnBuffTracker", openFromEscMenu, "System", "optimizer")
  else
    ESCMenu = ESCMenu or {}
    ESCMenu.queue = ESCMenu.queue or {}
    table.insert(ESCMenu.queue, { name = "CooldawnBuffTracker", callback = openFromEscMenu, category = "System" })
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
      mc:SetText(locale.L("Addon Options"))
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
      configMenu.michaelClient:AddAddon("CooldawnBuffTracker", openFromEscMenu)
    end
  end)

  CbtLog.success("Loading CooldawnBuffTracker %s by %s",
    CbtLog.hl(CooldawnBuffTracker.version), CbtLog.hl(CooldawnBuffTracker.author))

  -- Модель канвасов уже нормализована helpers.getSettings()/default_settings.migrate():
  -- плоские поля юнитов переехали в canvases[1] ("Main"), ничего не потеряно.
  CbtLog.info("Canvas model ready: playerpet=%s player=%s target=%s",
    CbtLog.hl(#(settings.playerpet.canvases or {})),
    tostring(#(settings.player.canvases or {})),
    tostring(#(settings.target.canvases or {})))

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
          CbtLog.debug("cast %s by %s (%sms)",
            tostring(spellName), tostring(caster), tostring(castingTime))
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

-- Guard the whole UPDATE body: an exception in one branch must not kill the
-- shared event handler and freeze every canvas while the settings UI still
-- works. One-shot file log makes the real fault visible.
OnUpdate = function(dt)
  if not live then
    if not lastRuntimeError.live then
      lastRuntimeError.live = true
      CbtDebugLog.info("UPDATE skipped: live=false")
    end
    return
  end
  local ok, err = pcall(updateStep, dt)
  if not ok and not lastRuntimeError.update then
    lastRuntimeError.update = true
    CbtLog.error("UPDATE failed: %s", tostring(err))
    CbtDebugLog.error("UPDATE failed: " .. tostring(err))
    CbtDebugLog.flush()
  end
end

local function OnUnload()
  CbtDebugLog.info("OnUnload called")
  CbtDebugLog.flush()
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
  destroyFrameModes()
  for _, unitType in ipairs(UNIT_TYPES) do
    destroyUnitCanvases(unitType)
  end

  -- Выгружаем страницу настроек, если модуль загружен
  if settingsPage and settingsPage.Unload then
    settingsPage.Unload()
  end

  pcall(function() CbtDebugLog.flush() end)

  -- Общий gametooltip (1.33.0) живёт на UIParent: освобождаем вместе с аддоном.
  pcall(function()
    local CbtWindowModule = require("CooldawnBuffTracker/util/cbt_window")
    if CbtWindowModule and CbtWindowModule.DestroyTooltip then
      CbtWindowModule.DestroyTooltip()
    end
  end)

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
  CbtLog.info("Received buff list update event")

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

  CbtLog.info("Mount buff list updated: was %s, now %s", oldMountBuffsCount, newMountBuffsCount)
  CbtLog.info("Player buff list updated: was %s, now %s", oldPlayerBuffsCount, newPlayerBuffsCount)

  -- Пересобираем канвасы всех юнитов: набор записей и их привязка к канвасам
  -- могли измениться (добавление/удаление/перенос/пресет/импорт).
  refreshAllCanvases()
end)

-- Handler for event when buffs list becomes empty
-- (своё событие addon'а)
return CooldawnBuffTracker
