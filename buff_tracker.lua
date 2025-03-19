local api = require("api")

local BuffTracker = {
  cachedMountBuffs = {},
  cachedPlayerBuffs = {},
  cachedBuffStatus = {}
}

-- Функция для получения текущего времени
function BuffTracker.getCurrentTime()
  local currentTime = 0
  pcall(function()
    local msTime = api.Time:GetUiMsec() or 0
    currentTime = msTime / 1000
  end)
  return currentTime
end

-- Функция для проверки статуса баффа
function BuffTracker.checkBuffStatus(buff, currentTime)
  if not buff or not buff.fixedTime then return "ready" end
  
  local fixedTime = tonumber(buff.fixedTime) or 0
  local timeOfAction = tonumber(buff.timeOfAction) or 0
  local cooldown = tonumber(buff.cooldown) or 0
  currentTime = tonumber(currentTime) or 0
  
  local activeEndTime = fixedTime + timeOfAction
  local readyTime = fixedTime + cooldown
  
  if currentTime < activeEndTime - 0.05 then
    return "active"
  elseif currentTime < readyTime - 0.05 then
    return "cooldown"
  else
    return "ready"
  end
end

-- Функция для расчета времени восстановления
function BuffTracker.calculateReuseTime(buff, currentTime)
  if not buff or not buff.fixedTime then return 0 end
  
  local fixedTime = tonumber(buff.fixedTime) or 0
  local cooldown = tonumber(buff.cooldown) or 0
  currentTime = tonumber(currentTime) or 0
  
  local readyTime = fixedTime + cooldown
  local remainingCooldown = readyTime - currentTime
  
  if remainingCooldown < 0 then remainingCooldown = 0 end
  
  return remainingCooldown
end

-- Функция для установки статуса баффа
function BuffTracker.setBuffStatus(buffId, status, currentTime, unitType, buffData, playerBuffData)
  unitType = unitType or "playerpet"  -- По умолчанию используем mount
  
  local buffDataTable = unitType == "player" and playerBuffData or buffData
  
  if not buffDataTable[buffId] then return end
  
  local buff = buffDataTable[buffId]
  local oldStatus = buff.status
  
  buff.status = status
  
  if status == "active" then
    buff.fixedTime = currentTime
  elseif status == "cooldown" and not buff.fixedTime then
    -- Если бафф переходит в состояние кулдауна, но fixedTime не установлено,
    -- устанавливаем текущее время как время начала кулдауна
    buff.fixedTime = currentTime
  end
  
  buff.statusChangeTime = currentTime
  
  -- Обновляем кэшированный статус
  BuffTracker.cachedBuffStatus[buffId] = status
end

-- Функция для инициализации данных баффов
function BuffTracker.initBuffData(buffData, playerBuffData, BuffList, BuffsToTrack, safeLog)
  -- Инициализируем данные для обоих типов юнитов
  local unitTypes = {"playerpet", "player"}
  
  for _, unitType in ipairs(unitTypes) do
    local buffDataTable = unitType == "player" and playerBuffData or buffData
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
        if safeLog then safeLog(unitType .. " buff removed from tracking: " .. tostring(buffId)) end
      end
    end
    
    -- Добавляем новые баффы
    for _, buffId in ipairs(trackedBuffIds) do
      if not buffDataTable[buffId] then
        local buffName = BuffList.GetBuffName(buffId)
        local buffIcon = BuffList.GetBuffIcon(buffId)
        local buffCooldown = BuffList.GetBuffCooldown(buffId)
        local buffTimeOfAction = BuffList.GetBuffTimeOfAction(buffId)
        
        if not buffCooldown or tonumber(buffCooldown) <= 0 then
          buffCooldown = 30
        end
        
        if not buffTimeOfAction or tonumber(buffTimeOfAction) <= 0 then
          buffTimeOfAction = 3
        end
        
        buffDataTable[buffId] = {
          name = buffName,
          icon = buffIcon,
          cooldown = buffCooldown,
          timeOfAction = buffTimeOfAction,
          fixedTime = nil,
          status = "ready"
        }
        
        if safeLog then safeLog(unitType .. " buff added for tracking: " .. tostring(buffId) .. " (" .. tostring(buffName) .. ")") end
      end
    end
  end
end

-- Функция для проверки наличия баффов для отслеживания
function BuffTracker.hasTrackedBuffs(unitType, BuffsToTrack, settings)
  -- Сначала проверяем настройку, которая полностью отключает отслеживание
  if not settings then return false end
  
  if unitType == "player" then
    -- Проверяем настройки для игрока
    if not settings.player or settings.player.enabled == false then
      return false
    end
    
    -- Проверяем, есть ли баффы в списке
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds("player")
    return #trackedBuffIds > 0
  elseif unitType == "playerpet" then
    -- Проверяем настройки для маунта
    if not settings.playerpet or settings.playerpet.enabled == false then
      return false
    end
    
    -- Проверяем, есть ли баффы в списке
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds("playerpet")
    return #trackedBuffIds > 0
  else
    -- Если тип не указан, проверяем баффы любого типа
    local trackedMountBuffIds = BuffsToTrack.GetAllTrackedBuffIds("playerpet")
    local trackedPlayerBuffIds = BuffsToTrack.GetAllTrackedBuffIds("player")
    
    local hasMountBuffs = settings.playerpet and settings.playerpet.enabled ~= false and #trackedMountBuffIds > 0
    local hasPlayerBuffs = settings.player and settings.player.enabled ~= false and #trackedPlayerBuffIds > 0
    
    return hasMountBuffs or hasPlayerBuffs
  end
end

-- Функция для проверки баффов на юните
function BuffTracker.checkBuffs(unitType, settings, buffData, playerBuffData, 
                               BuffsToTrack, canvas, isCanvasInitialized,
                               UI, updateBuffIcons, BuffList, BuffDebugger, getCurrentTime, checkBuffStatus)
  unitType = unitType or "playerpet"  -- По умолчанию работаем с маунтом
  
  local status, err = pcall(function()
    -- Определяем, какие переменные использовать в зависимости от типа юнита
    local unitSettings = settings[unitType]
    local buffDataTable = unitType == "player" and playerBuffData or buffData
    
    -- Скрываем окно, если аддон отключен в настройках
    if not unitSettings or not unitSettings.enabled then
      if canvas then
        canvas:Show(false)
      end
      return
    end
    
    -- Проверяем, есть ли баффы для отслеживания
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds(unitType)
    
    -- Если список отслеживаемых баффов пуст, скрываем канвас
    if #trackedBuffIds == 0 then
      if canvas then
        canvas:Show(false)
      end
      return
    end
    
    local activeBuffsOnUnit = {}
    local hasChanges = false
    local currentBuffsOnUnit = {}
    
    -- Проверяем активные баффы на юните
    pcall(function()
      -- Получаем все активные баффы на юните
      local buffCount = api.Unit:UnitBuffCount(unitType) or 0
      for i = 1, buffCount do
        local buff = api.Unit:UnitBuff(unitType, i)
        
        -- Проверяем, существует ли бафф и есть ли у него идентификатор
        if buff and buff.buff_id then
          -- Записываем текущие ID баффов для последующего сравнения
          currentBuffsOnUnit[buff.buff_id] = true
          
          -- Проверяем, нужно ли отслеживать этот бафф
          if BuffsToTrack.ShouldTrackBuff(buff.buff_id, unitType) then
            activeBuffsOnUnit[buff.buff_id] = true
            
            -- Если баффа еще нет в данных или он не активен, обновляем его статус
            if not buffDataTable[buff.buff_id] or (buffDataTable[buff.buff_id].status ~= "active") then
              -- Бафф стал активным, обновляем его статус
              BuffTracker.setBuffStatus(buff.buff_id, "active", BuffTracker.getCurrentTime(), unitType, buffData, playerBuffData)
              hasChanges = true
              
              -- Обновляем кэшированный статус
              BuffTracker.cachedBuffStatus[buff.buff_id] = "active"
            end
          end
        end
      end
    end)
    
    -- Обновляем кэшированные баффы юнита
    if unitType == "player" then
      BuffTracker.cachedPlayerBuffs = currentBuffsOnUnit
    else
      BuffTracker.cachedMountBuffs = currentBuffsOnUnit
    end
    
    -- Проверяем баффы, которые были активны, но больше не существуют
    local currentTime = tonumber(BuffTracker.getCurrentTime()) or 0
    
    for buffId, buffInfo in pairs(buffDataTable) do
      local oldStatus = buffInfo.status
      
      if currentBuffsOnUnit[buffId] then
        -- Бафф активен на юните, ничего делать не нужно
        if buffInfo.status ~= "active" then
          BuffTracker.setBuffStatus(buffId, "active", currentTime, unitType, buffData, playerBuffData)
          hasChanges = true
          
          -- Обновляем кэшированный статус
          BuffTracker.cachedBuffStatus[buffId] = "active"
        end
      else
        -- Если баффа больше нет на юните
        if buffInfo.fixedTime then
          local expectedStatus = BuffTracker.checkBuffStatus(buffInfo, currentTime)
          
          if expectedStatus ~= buffInfo.status then
            BuffTracker.setBuffStatus(buffId, expectedStatus, currentTime, unitType, buffData, playerBuffData)
            hasChanges = true
            
            -- Обновляем кэшированный статус
            BuffTracker.cachedBuffStatus[buffId] = expectedStatus
          end
        elseif buffInfo.status ~= "ready" then
          BuffTracker.setBuffStatus(buffId, "ready", nil, unitType, buffData, playerBuffData)
          hasChanges = true
          
          -- Обновляем кэшированный статус
          BuffTracker.cachedBuffStatus[buffId] = "ready"
        end
      end
    end
    
    -- Обновляем иконки, если были изменения
    if hasChanges and updateBuffIcons then
      updateBuffIcons(unitType)
    end
  end)
  
  if not status and api and api.Log and api.Log.Info then
    pcall(function() api.Log:Info("Error checking buffs for " .. unitType .. ": " .. tostring(err)) end)
  end
end

return BuffTracker 