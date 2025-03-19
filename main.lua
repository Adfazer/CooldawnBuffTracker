local api = require("api")

-- Импорт внутренних модулей
local UI
pcall(function() UI = require("CooldawnBuffTracker/ui") end)

local BuffTracker
pcall(function() BuffTracker = require("CooldawnBuffTracker/buff_tracker") end)

local Settings
pcall(function() Settings = require("CooldawnBuffTracker/settings") end)

-- Импорт существующих модулей
local BuffList
pcall(function() BuffList = require("CooldawnBuffTracker/buff_helper") end)

local BuffsToTrack
pcall(function() BuffsToTrack = require("CooldawnBuffTracker/buffs_to_track") end)

local helpers
pcall(function() helpers = require("CooldawnBuffTracker/helpers") end)

local settingsPage
pcall(function() settingsPage = require("CooldawnBuffTracker/settings_page") end)

local BuffDebugger
pcall(function() BuffDebugger = require("CooldawnBuffTracker/buff_debugger") end)

local CooldawnBuffTracker = {
  name = "CooldawnBuffTracker",
  author = "Adfazer & Claude",
  desc = "Addon for tracking buffs",
  version = "1.1.0"
}

-- Переменные состояния
local buffData = {}
local playerBuffData = {}
local buffCanvas = nil
local playerBuffCanvas = nil
local updateTimer = 0
local refreshUITimer = 0
local updateInterval = 50 -- Не изменяем частоту проверок
local refreshUIInterval = 50
local isCanvasInitialized = false
local isPlayerCanvasInitialized = false
local settings = {}

-- Безопасное логирование
local function safeLog(message)
  if api and api.Log and api.Log.Info then
    pcall(function() api.Log:Info(message) end)
  end
end

-- Создаем заменители для отсутствующих модулей
if not UI then
  safeLog("Не удалось загрузить модуль UI, используем встроенный вариант")
  UI = {
    formatTimerSeconds = function(seconds) 
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
    end,
    ICON_COLORS = {
      READY = {1, 1, 1, 1},
      ACTIVE = {0.2, 1, 0.2, 1},
      COOLDOWN = {1, 0.2, 0.2, 1}
    }
  }
end

if not BuffTracker then
  safeLog("Не удалось загрузить модуль BuffTracker, используем встроенный вариант")
  BuffTracker = {
    getCurrentTime = function()
      local currentTime = 0
      pcall(function()
        local msTime = api.Time:GetUiMsec() or 0
        currentTime = msTime / 1000
      end)
      return currentTime
    end,
    cachedMountBuffs = {},
    cachedPlayerBuffs = {},
    cachedBuffStatus = {}
  }
end

if not Settings then
  safeLog("Не удалось загрузить модуль Settings, используем встроенный вариант")
  Settings = {
    DEFAULT = {
      iconSize = 40,
      iconSpacing = 5,
      posX = 330,
      posY = 30,
      lockPositioning = false,
      enabled = true,
      timerTextColor = {r = 1, g = 1, b = 1, a = 1},
      labelTextColor = {r = 1, g = 1, b = 1, a = 1},
      showLabel = false,
      labelFontSize = 14,
      labelX = 0,
      labelY = -30,
      showTimer = true,
      timerFontSize = 16,
      timerX = 0,
      timerY = 0,
      trackedBuffs = {}
    }
  }
end

-- Если не загружаются существующие модули, создаем заглушки
if not BuffsToTrack then
  safeLog("Не удалось загрузить buffs_to_track.lua, используем заглушку")
  BuffsToTrack = Settings.createPlaceholderBuffsToTrack()
end

if not BuffList then
  safeLog("Не удалось загрузить buff_helper.lua, используем заглушку")
  BuffList = Settings.createPlaceholderBuffList()
end

-- Функция для определения текущего времени
local function getCurrentTime()
  return BuffTracker.getCurrentTime()
end

-- Функция для проверки статуса баффа
local function checkBuffStatus(buff, currentTime)
  return BuffTracker.checkBuffStatus(buff, currentTime)
end

-- Функция для обновления иконок баффов
local function updateBuffIcons(unitType)
  unitType = unitType or "playerpet"  -- По умолчанию используем mount
  
  local canvas = unitType == "player" and playerBuffCanvas or buffCanvas
  local isCanvasInit = unitType == "player" and isPlayerCanvasInitialized or isCanvasInitialized
  
  UI.updateBuffIcons(unitType, settings, buffData, canvas, isCanvasInit, BuffsToTrack, BuffList, BuffDebugger, getCurrentTime, checkBuffStatus, playerBuffData)
end

-- Функция для проверки баффов
local function checkBuffs(unitType)
  unitType = unitType or "playerpet"  -- По умолчанию работаем с маунтом
  
  -- Определяем, какие переменные использовать в зависимости от типа юнита
  local canvas = unitType == "player" and playerBuffCanvas or buffCanvas
  local isCanvasInit = unitType == "player" and isPlayerCanvasInitialized or isCanvasInitialized
  
  BuffTracker.checkBuffs(unitType, settings, buffData, playerBuffData, 
                        BuffsToTrack, canvas, isCanvasInit,
                        UI, updateBuffIcons, BuffList, BuffDebugger, getCurrentTime, checkBuffStatus)
end

-- Функция для обновления данных
local function OnUpdate(dt)
  updateTimer = updateTimer + dt
  if updateTimer >= updateInterval then
    checkBuffs("playerpet")  -- Проверяем баффы маунта
    checkBuffs("player")     -- Проверяем баффы игрока
    updateTimer = 0
  end
  
  refreshUITimer = refreshUITimer + dt
  if refreshUITimer >= refreshUIInterval then
    if isCanvasInitialized then
      pcall(function() updateBuffIcons("playerpet") end)
    end
    if isPlayerCanvasInitialized then
      pcall(function() updateBuffIcons("player") end)
    end
    
    -- Обновляем отладчик баффов, если он существует
    if BuffDebugger and BuffDebugger.Update then
      pcall(function() 
        BuffDebugger.Update({
          playerCanvas = playerBuffCanvas,
          mountCanvas = buffCanvas,
          currentTime = getCurrentTime()
        }) 
      end)
    end
    
    refreshUITimer = 0
  end
end

-- Функция инициализации интерфейса
local function initializeUI()
  -- Проверяем необходимость отображения каждого из канвасов
  local unitTypes = {"playerpet", "player"}
  
  for _, unitType in ipairs(unitTypes) do
    local shouldShowUI = BuffTracker.hasTrackedBuffs(unitType, BuffsToTrack, settings)
    safeLog("UI initialization for " .. unitType .. ": " .. (shouldShowUI and "show" or "hide"))
    
    if shouldShowUI then
      if unitType == "player" then
        playerBuffCanvas = UI.createBuffCanvas(settings, unitType)
        isPlayerCanvasInitialized = true
        updateBuffIcons("player")
      else
        buffCanvas = UI.createBuffCanvas(settings, unitType)
        isCanvasInitialized = true
        updateBuffIcons("playerpet")
      end
    end
  end
end

-- Функция загрузки аддона
local function OnLoad()
  local status, err = pcall(function()
    -- Загружаем настройки
    settings = Settings.getSettings()
    
    -- Инициализируем модуль отладки баффов
    if BuffDebugger and BuffDebugger.Initialize then
      pcall(function() 
        BuffDebugger.Initialize({
          playerCanvas = playerBuffCanvas,
          mountCanvas = buffCanvas,
          settings = settings
        }) 
      end)
    end
    
    -- Инициализируем данные баффов
    BuffTracker.initBuffData(buffData, playerBuffData, BuffList, BuffsToTrack, safeLog)

    safeLog("Loading CooldawnBuffTracker " .. CooldawnBuffTracker.version .. " by " .. CooldawnBuffTracker.author)
    
    -- Инициализируем страницу настроек, если модуль загружен
    if settingsPage and settingsPage.Load then
      pcall(function() settingsPage.Load() end)
    end
    
    -- Инициализируем UI
    initializeUI()
    
    -- Регистрируем обработчик обновления
    pcall(function() 
      api.On("UPDATE", OnUpdate)
    end)
    
    -- Создаем ассоциацию с обработчиком обновления настроек
    pcall(function()
      CooldawnBuffTracker.OnSettingsSaved = function()
        -- Полностью пересоздаем UI при изменении настроек
        if helpers then
          settings = helpers.getSettings(buffCanvas, playerBuffCanvas)
        else
          settings = Settings.getSettings()
        end
        
        -- Обновляем модуль отладки баффов после изменения настроек
        if BuffDebugger then
          -- Сначала отключаем
          pcall(function() 
            BuffDebugger.Shutdown({
              playerCanvas = playerBuffCanvas,
              mountCanvas = buffCanvas
            }) 
          end)
          -- Затем инициализируем заново с новыми настройками
          pcall(function() 
            BuffDebugger.Initialize({
              playerCanvas = playerBuffCanvas,
              mountCanvas = buffCanvas,
              settings = settings
            }) 
          end)
        end
        
        -- Проверяем необходимость отображения каждого из канвасов
        local unitTypes = {"playerpet", "player"}
        
        for _, unitType in ipairs(unitTypes) do
          local shouldShowUI = BuffTracker.hasTrackedBuffs(unitType, BuffsToTrack, settings)
          local canvas = unitType == "player" and playerBuffCanvas or buffCanvas
          local isCanvasInit = unitType == "player" and isPlayerCanvasInitialized or isCanvasInitialized
          
          -- Если баффов для отслеживания нет, скрываем канвас
          if not shouldShowUI and canvas then
            pcall(function() canvas:Show(false) end)
          elseif shouldShowUI then
            -- Если баффы существуют, но канвас не создан, создаем его
            if not isCanvasInit then
              if unitType == "player" then
                playerBuffCanvas = UI.createBuffCanvas(settings, unitType)
                isPlayerCanvasInitialized = true
              else
                buffCanvas = UI.createBuffCanvas(settings, unitType)
                isCanvasInitialized = true 
              end
            end
            
            -- Обновляем иконки
            updateBuffIcons(unitType)
          end
        end
      end
    end)
  end)
  
  if not status then
    safeLog("Error initializing: " .. tostring(err))
  end
end

-- Функция выгрузки аддона
local function OnUnload()
  -- Отключаем обработчик обновления
  pcall(function() api.On("UPDATE", function() end) end)
  
  -- Отключаем модуль отладки баффов
  if BuffDebugger and BuffDebugger.Shutdown then
    pcall(function() 
      BuffDebugger.Shutdown({
        playerCanvas = playerBuffCanvas,
        mountCanvas = buffCanvas
      }) 
    end)
  end
  
  -- Очищаем данные
  buffData = {}
  playerBuffData = {}
  isCanvasInitialized = false
  isPlayerCanvasInitialized = false
  
  -- Очищаем канвасы
  local unitTypes = {"playerpet", "player"}
  for _, unitType in ipairs(unitTypes) do
    local canvas = unitType == "player" and playerBuffCanvas or buffCanvas
    if canvas then
      pcall(function() 
        canvas:Show(false)
        if canvas.ReleaseHandler then
          canvas:ReleaseHandler("OnDragStart")
          canvas:ReleaseHandler("OnDragStop")
        end
      end)
    end
    
    -- Обнуляем переменные канвасов
    if unitType == "player" then
      playerBuffCanvas = nil
    else
      buffCanvas = nil
    end
  end
  
  -- Выгружаем страницу настроек, если модуль загружен
  if settingsPage and settingsPage.Unload then
    pcall(function() settingsPage.Unload() end)
  end
  
  -- Сохраняем настройки через вспомогательные функции
  if helpers and helpers.updateSettings then
    helpers.updateSettings()
  else
    Settings.updateSettings(settings)
  end
end

-- Обработчик для открытия окна настроек
local function OnSettingToggle()
  if settingsPage and settingsPage.openSettingsWindow then
    pcall(function() settingsPage.openSettingsWindow() end)
  end
end

-- Добавляем функцию SetBorderColor для иконок, если её нет
local originalCreateItemIconButton = CreateItemIconButton
if originalCreateItemIconButton then
  CreateItemIconButton = function(name, parent)
    local icon = originalCreateItemIconButton(name, parent)
    if icon and not icon.SetBorderColor then
      icon.SetBorderColor = function(self, r, g, b, a)
        -- Set border color if method is available
        pcall(function()
          if self.back then
            self.back:SetColor(r, g, b, a)
          end
        end)
      end
    end
    return icon
  end
end

-- Обработчик события обновления списка отслеживаемых баффов
pcall(function()
  api.On("MOUNT_BUFF_TRACKER_UPDATE_BUFFS", function()
    safeLog("Received buff list update event")
    
    -- Обновляем данные баффов (включая удаление ненужных)
    local oldMountBuffsCount = 0
    for _ in pairs(buffData) do oldMountBuffsCount = oldMountBuffsCount + 1 end
    
    local oldPlayerBuffsCount = 0
    for _ in pairs(playerBuffData) do oldPlayerBuffsCount = oldPlayerBuffsCount + 1 end
    
    -- Инициализируем данные баффов
    BuffTracker.initBuffData(buffData, playerBuffData, BuffList, BuffsToTrack, safeLog)
    
    -- Считаем новое количество баффов
    local newMountBuffsCount = 0
    for _ in pairs(buffData) do newMountBuffsCount = newMountBuffsCount + 1 end
    
    local newPlayerBuffsCount = 0
    for _ in pairs(playerBuffData) do newPlayerBuffsCount = newPlayerBuffsCount + 1 end
    
    safeLog("Mount buff list updated: was " .. oldMountBuffsCount .. ", now " .. newMountBuffsCount)
    safeLog("Player buff list updated: was " .. oldPlayerBuffsCount .. ", now " .. newPlayerBuffsCount)
    
    -- Проверяем необходимость отображения каждого из канвасов
    local unitTypes = {"playerpet", "player"}
    
    for _, unitType in ipairs(unitTypes) do
      local shouldShowUI = BuffTracker.hasTrackedBuffs(unitType, BuffsToTrack, settings)
      local canvas = unitType == "player" and playerBuffCanvas or buffCanvas
      local isCanvasInit = unitType == "player" and isPlayerCanvasInitialized or isCanvasInitialized
      
      -- Если баффов для отслеживания нет, скрываем канвас
      if not shouldShowUI and canvas then
        pcall(function() canvas:Show(false) end)
      elseif shouldShowUI then
        -- Если баффы существуют, но канвас не создан, создаем его
        if not isCanvasInit then
          if unitType == "player" then
            playerBuffCanvas = UI.createBuffCanvas(settings, unitType)
            isPlayerCanvasInitialized = true
          else
            buffCanvas = UI.createBuffCanvas(settings, unitType)
            isCanvasInitialized = true 
          end
        end
        
        -- Обновляем иконки
        updateBuffIcons(unitType)
      end
    end
  end)
end)

-- Обработчик события пустого списка баффов
pcall(function()
  api.On("MOUNT_BUFF_TRACKER_EMPTY_LIST", function(unitType)
    unitType = unitType or "playerpet"
    
    safeLog("Received empty buff list event for " .. unitType .. " - forcibly hiding canvas")
    
    local canvas = unitType == "player" and playerBuffCanvas or buffCanvas
    local buffDataTable = unitType == "player" and playerBuffData or buffData
    
    -- Принудительно скрываем канвас
    pcall(function()
      if canvas then
        canvas:Show(false)
        safeLog("Canvas hidden successfully")
      end
    end)
    
    -- Для безопасности сбрасываем данные
    pcall(function()
      for buffId in pairs(buffDataTable) do
        buffDataTable[buffId] = nil
      end
    end)
  end)
end)

CooldawnBuffTracker.OnLoad = OnLoad
CooldawnBuffTracker.OnUnload = OnUnload
CooldawnBuffTracker.OnSettingToggle = OnSettingToggle

return CooldawnBuffTracker
