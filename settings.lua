local api = require("api")

local Settings = {}

-- Значения по умолчанию
Settings.DEFAULT = {
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

-- Функция для безопасного логирования
local function safeLog(message)
  if api and api.Log and api.Log.Info then
    pcall(function() api.Log:Info(message) end)
  end
end

-- Загрузка настроек
function Settings.getSettings()
  local settings = api.GetSettings("CooldawnBuffTracker") or {}
  
  -- Проверка и дополнение структуры настроек
  if not settings.playerpet then
    settings.playerpet = {}
    for key, value in pairs(Settings.DEFAULT) do
      settings.playerpet[key] = value
    end
    safeLog("Созданы настройки по умолчанию для playerpet")
  end
  
  if not settings.player then
    settings.player = {}
    for key, value in pairs(Settings.DEFAULT) do
      settings.player[key] = value
      -- Для игрока позиция немного ниже
      if key == "posY" then 
        settings.player[key] = value + 70
      end
    end
    safeLog("Созданы настройки по умолчанию для player")
  end
  
  -- Заполнение отсутствующих значений
  for unitType, unitSettings in pairs(settings) do
    if unitType == "playerpet" or unitType == "player" then
      for key, value in pairs(Settings.DEFAULT) do
        if unitSettings[key] == nil then
          unitSettings[key] = value
          safeLog(string.format("Установлено значение по умолчанию для %s.%s: %s", 
                                unitType, key, tostring(value)))
        end
      end
    end
  end
  
  -- Проверка корректности настроек для совместимости
  if settings.posX ~= nil or settings.posY ~= nil or settings.iconSize ~= nil then
    safeLog("Обнаружены устаревшие настройки, выполняется миграция...")
    
    -- Мигрируем старые настройки в новую структуру
    if not settings.playerpet then
      settings.playerpet = {
        posX = settings.posX or Settings.DEFAULT.posX,
        posY = settings.posY or Settings.DEFAULT.posY,
        iconSize = settings.iconSize or Settings.DEFAULT.iconSize,
        iconSpacing = settings.iconSpacing or Settings.DEFAULT.iconSpacing,
        lockPositioning = settings.lockPositioning or Settings.DEFAULT.lockPositioning,
        enabled = settings.enabled ~= false, -- Enabled by default
        timerTextColor = settings.timerTextColor or Settings.DEFAULT.timerTextColor,
        labelTextColor = settings.labelTextColor or Settings.DEFAULT.labelTextColor,
        showLabel = settings.showLabel or Settings.DEFAULT.showLabel,
        labelFontSize = settings.labelFontSize or Settings.DEFAULT.labelFontSize,
        labelX = settings.labelX or Settings.DEFAULT.labelX,
        labelY = settings.labelY or Settings.DEFAULT.labelY,
        showTimer = settings.showTimer ~= false, -- Enabled by default
        timerFontSize = settings.timerFontSize or Settings.DEFAULT.timerFontSize,
        timerX = settings.timerX or Settings.DEFAULT.timerX,
        timerY = settings.timerY or Settings.DEFAULT.timerY,
        trackedBuffs = settings.trackedBuffs or {}
      }
    end
    
    if not settings.player then
      settings.player = {
        posX = settings.posX or Settings.DEFAULT.posX,
        posY = (settings.posY or Settings.DEFAULT.posY) + 70, -- Чуть ниже маунта
        iconSize = settings.iconSize or Settings.DEFAULT.iconSize,
        iconSpacing = settings.iconSpacing or Settings.DEFAULT.iconSpacing,
        lockPositioning = settings.lockPositioning or Settings.DEFAULT.lockPositioning,
        enabled = true, -- Enabled by default
        timerTextColor = settings.timerTextColor or Settings.DEFAULT.timerTextColor,
        labelTextColor = settings.labelTextColor or Settings.DEFAULT.labelTextColor,
        showLabel = settings.showLabel or Settings.DEFAULT.showLabel,
        labelFontSize = settings.labelFontSize or Settings.DEFAULT.labelFontSize,
        labelX = settings.labelX or Settings.DEFAULT.labelX,
        labelY = settings.labelY or Settings.DEFAULT.labelY,
        showTimer = settings.showTimer ~= false, -- Enabled by default
        timerFontSize = settings.timerFontSize or Settings.DEFAULT.timerFontSize,
        timerX = settings.timerX or Settings.DEFAULT.timerX,
        timerY = settings.timerY or Settings.DEFAULT.timerY,
        trackedBuffs = {}
      }
    end
    
    -- Удаляем старые ключи
    settings.posX = nil
    settings.posY = nil
    settings.iconSize = nil
    settings.iconSpacing = nil
    settings.lockPositioning = nil
    settings.enabled = nil
    settings.timerTextColor = nil
    settings.labelTextColor = nil
    settings.showLabel = nil
    settings.labelFontSize = nil
    settings.labelX = nil
    settings.labelY = nil
    settings.showTimer = nil
    settings.timerFontSize = nil
    settings.timerX = nil
    settings.timerY = nil
    settings.trackedBuffs = nil
    
    safeLog("Миграция настроек завершена")
    
    -- Сохраняем обновленные настройки
    Settings.updateSettings(settings)
  end
  
  return settings
end

-- Сохранение настроек
function Settings.updateSettings(settings)
  pcall(function()
    api.SaveSettings("CooldawnBuffTracker", settings)
  end)
end

-- Получение списка отслеживаемых баффов из настроек
function Settings.getTrackedBuffsFromSettings(unitType)
  local settings = api.GetSettings("CooldawnBuffTracker") or {}
  local trackedBuffs = {}
  
  if settings[unitType] and settings[unitType].trackedBuffs then
    trackedBuffs = settings[unitType].trackedBuffs
  end
  
  return trackedBuffs
end

-- Создание резервных настроек для BuffsToTrack, если модуль не загружен
function Settings.createPlaceholderBuffsToTrack()
  local BuffsToTrack = {
    ShouldTrackBuff = function(id, unitType) 
      local trackedBuffs = Settings.getTrackedBuffsFromSettings(unitType)
      for _, buffId in ipairs(trackedBuffs) do
        if buffId == id then
          return true
        end
      end
      return false
    end,
    GetAllTrackedBuffIds = function(unitType) 
      return Settings.getTrackedBuffsFromSettings(unitType)
    end
  }
  
  return BuffsToTrack
end

-- Создание резервных настроек для BuffList, если модуль не загружен
function Settings.createPlaceholderBuffList()
  local BuffList = {
    GetBuffName = function(id) return "Buff #" .. id end,
    GetBuffIcon = function(id) return nil end,
    GetBuffCooldown = function(id) return 30 end,
    GetBuffTimeOfAction = function(id) return 3 end
  }
  
  return BuffList
end

return Settings 