local api = require("api")
local BuffList
pcall(function()
  BuffList = require("CooldawnBuffTracker/buff_helper") or require("buff_helper") or require("./buff_helper")
end)

local BuffsToTrack
pcall(function()
  BuffsToTrack = require("CooldawnBuffTracker/buffs_to_track") or require("buffs_to_track") or require("./buffs_to_track")
end)

-- Подключаем новые модули настроек
local helpers
pcall(function()
  helpers = require("CooldawnBuffTracker/helpers") or require("helpers") or require("./helpers")
end)

local settingsPage
pcall(function()
  settingsPage = require("CooldawnBuffTracker/settings_page") or require("settings_page") or require("./settings_page")
end)

-- Объявляем переменные для кэширования состояний баффов (добавляем в начало файла после остальных переменных)
local cachedMountBuffs = {}
local cachedPlayerBuffs = {}
local cachedBuffStatus = {}

-- Функция для получения списка отслеживаемых баффов из настроек
local function getTrackedBuffsFromSettings(unitType)
  local settings = api.GetSettings("CooldawnBuffTracker") or {}
  local trackedBuffs = {}
  
  if settings[unitType] and settings[unitType].trackedBuffs then
    trackedBuffs = settings[unitType].trackedBuffs
  end
  
  return trackedBuffs
end

-- Замена для BuffsToTrack, если модуль не загрузился
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
  pcall(function() api.Log:Info("Не удалось загрузить buffs_to_track.lua, используем настройки") end)
end

if not BuffList then
  BuffList = {
    GetBuffName = function(id) return "Бафф #" .. id end,
    GetBuffIcon = function(id) return nil end,
    GetBuffCooldown = function(id) return 0 end,
    GetBuffTimeOfAction = function(id) return 0 end
  }
  pcall(function() api.Log:Info("Не удалось загрузить buff_helper.lua, используем заглушку") end)
end

local CooldawnBuffTracker = {
  name = "CooldawnBuffTracker",
  author = "Adfazer & Claude",
  desc = "Addon for tracking buffs",
  version = "1.0.0"
}

-- Simplified logging function that only logs during initialization
local function safeLog(message)
  if api and api.Log and api.Log.Info then
    pcall(function() api.Log:Info(message) end)
  end
end

local buffData = {}
local playerBuffData = {}
local buffCanvas = nil
local playerBuffCanvas = nil
local updateTimer = 0
local refreshUITimer = 0
local updateInterval = 50
local refreshUIInterval = 50
local isCanvasInitialized = false
local isPlayerCanvasInitialized = false
local iconSize = 40
local iconSpacing = 5
local defaultPositionX = 330
local defaultPositionY = 30

local ICON_COLORS = {
  READY = {1, 1, 1, 1},          -- Белый (не изменяется)
  ACTIVE = {0.2, 1, 0.2, 1},     -- Более яркий зеленый
  COOLDOWN = {1, 0.2, 0.2, 1}    -- Более яркий красный
}

local settings = {}

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
  local currentTime = 0
  pcall(function()
    local msTime = api.Time:GetUiMsec() or 0
    currentTime = msTime / 1000
  end)
  return currentTime
end

local function initBuffData()
  -- Инициализация данных для маунта (playerpet)
  local trackedMountBuffIds = BuffsToTrack.GetAllTrackedBuffIds("playerpet")
  
  -- Создаем таблицу для проверки существующих баффов маунта
  local trackedMountBuffsMap = {}
  for _, buffId in ipairs(trackedMountBuffIds) do
    trackedMountBuffsMap[buffId] = true
  end
  
  -- Удаляем из buffData баффы, которые больше не отслеживаются
  for buffId in pairs(buffData) do
    if not trackedMountBuffsMap[buffId] then
      -- Если бафф больше не отслеживается, удаляем его из данных
      buffData[buffId] = nil
      safeLog("Удален бафф маунта из отслеживания: " .. tostring(buffId))
    end
  end
  
  -- Добавляем новые баффы маунта
  for _, buffId in ipairs(trackedMountBuffIds) do
    if not buffData[buffId] then
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
      
      buffData[buffId] = {
        name = buffName,
        icon = buffIcon,
        cooldown = buffCooldown,
        timeOfAction = buffTimeOfAction,
        fixedTime = nil,
        status = "ready"
      }
      
      safeLog("Добавлен бафф маунта для отслеживания: " .. tostring(buffId) .. " (" .. tostring(buffName) .. ")")
    end
  end
  
  -- Инициализация данных для игрока (player)
  local trackedPlayerBuffIds = BuffsToTrack.GetAllTrackedBuffIds("player")
  
  -- Создаем таблицу для проверки существующих баффов игрока
  local trackedPlayerBuffsMap = {}
  for _, buffId in ipairs(trackedPlayerBuffIds) do
    trackedPlayerBuffsMap[buffId] = true
  end
  
  -- Удаляем из playerBuffData баффы, которые больше не отслеживаются
  for buffId in pairs(playerBuffData) do
    if not trackedPlayerBuffsMap[buffId] then
      -- Если бафф больше не отслеживается, удаляем его из данных
      playerBuffData[buffId] = nil
      safeLog("Удален бафф игрока из отслеживания: " .. tostring(buffId))
    end
  end
  
  -- Добавляем новые баффы игрока
  for _, buffId in ipairs(trackedPlayerBuffIds) do
    if not playerBuffData[buffId] then
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
      
      playerBuffData[buffId] = {
        name = buffName,
        icon = buffIcon,
        cooldown = buffCooldown,
        timeOfAction = buffTimeOfAction,
        fixedTime = nil,
        status = "ready"
      }
      
      safeLog("Добавлен бафф игрока для отслеживания: " .. tostring(buffId) .. " (" .. tostring(buffName) .. ")")
    end
  end
end

local function setBuffStatus(buffId, status, currentTime, unitType)
  if unitType == "player" then
    if not playerBuffData[buffId] then return end
    
    local buff = playerBuffData[buffId]
    local oldStatus = buff.status
    
    buff.status = status
    
    if status == "active" then
      buff.fixedTime = currentTime
    elseif status == "cooldown" and not buff.fixedTime then
      -- Если баф переходит в кулдаун, но fixedTime не установлен, 
      -- устанавливаем текущее время как время начала кулдауна
      buff.fixedTime = currentTime
    end
    
    buff.statusChangeTime = currentTime
  else
    -- По умолчанию работаем с маунтом
    if not buffData[buffId] then return end
    
    local buff = buffData[buffId]
    local oldStatus = buff.status
    
    buff.status = status
    
    if status == "active" then
      buff.fixedTime = currentTime
    elseif status == "cooldown" and not buff.fixedTime then
      -- Если баф переходит в кулдаун, но fixedTime не установлен, 
      -- устанавливаем текущее время как время начала кулдауна
      buff.fixedTime = currentTime
    end
    
    buff.statusChangeTime = currentTime
  end
end

local function checkBuffStatus(buff, currentTime)
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

local function calculateReuseTime(buff, currentTime)
  if not buff or not buff.fixedTime then return 0 end
  
  local fixedTime = tonumber(buff.fixedTime) or 0
  local cooldown = tonumber(buff.cooldown) or 0
  currentTime = tonumber(currentTime) or 0
  
  local readyTime = fixedTime + cooldown
  local remainingCooldown = readyTime - currentTime
  
  if remainingCooldown < 0 then remainingCooldown = 0 end
  
  return remainingCooldown
end

local function createChildWidgetSafe(parent, widgetType, name, index)
  if not parent then return nil end
  
  local widget = nil
  pcall(function()
    widget = api.Interface:CreateWidget(widgetType, name, parent)
  end)
  
  if not widget then
    pcall(function()
      widget = parent:CreateChildWidget(widgetType, name, index or 0, true)
    end)
  end
  
  return widget
end

-- Функция для создания иконки баффа
local function addBuffIcon(parent, index, unitType)
  unitType = unitType or "playerpet" -- По умолчанию используем маунта
  
  local unitSettings = settings[unitType] or settings.playerpet
  
  local icon = CreateItemIconButton("buffIcon_" .. index, parent)
  if not icon then return nil end
  
  pcall(function()
    icon:SetExtent(unitSettings.iconSize, unitSettings.iconSize)
    
    -- Явно вычисляем позицию иконки с учетом текущего интервала
    local xPosition = (index-1) * (unitSettings.iconSize + unitSettings.iconSpacing)
    icon:AddAnchor("LEFT", parent, xPosition, 0)
    
    -- Создаем цветной оверлей для иконки (будет показывать статус)
    local statusOverlay = icon:CreateColorDrawable(0, 0, 0, 0, "overlay")
    statusOverlay:AddAnchor("TOPLEFT", icon, 0, 0)
    statusOverlay:AddAnchor("BOTTOMRIGHT", icon, 0, 0)
    icon.statusOverlay = statusOverlay
    
    -- Создаем рамку вокруг иконки
    local borderSize = 2
    
    -- Верхняя рамка
    local topBorder = icon:CreateColorDrawable(1, 1, 1, 0, "overlay")
    topBorder:AddAnchor("TOPLEFT", icon, -borderSize, -borderSize)
    topBorder:AddAnchor("TOPRIGHT", icon, borderSize, -borderSize)
    topBorder:SetHeight(borderSize)
    icon.topBorder = topBorder
    
    -- Нижняя рамка
    local bottomBorder = icon:CreateColorDrawable(1, 1, 1, 0, "overlay")
    bottomBorder:AddAnchor("BOTTOMLEFT", icon, -borderSize, borderSize)
    bottomBorder:AddAnchor("BOTTOMRIGHT", icon, borderSize, borderSize)
    bottomBorder:SetHeight(borderSize)
    icon.bottomBorder = bottomBorder
    
    -- Левая рамка
    local leftBorder = icon:CreateColorDrawable(1, 1, 1, 0, "overlay")
    leftBorder:AddAnchor("TOPLEFT", icon, -borderSize, -borderSize)
    leftBorder:AddAnchor("BOTTOMLEFT", icon, -borderSize, borderSize)
    leftBorder:SetWidth(borderSize)
    icon.leftBorder = leftBorder
    
    -- Правая рамка
    local rightBorder = icon:CreateColorDrawable(1, 1, 1, 0, "overlay")
    rightBorder:AddAnchor("TOPRIGHT", icon, borderSize, -borderSize)
    rightBorder:AddAnchor("BOTTOMRIGHT", icon, borderSize, borderSize)
    rightBorder:SetWidth(borderSize)
    icon.rightBorder = rightBorder
    
    -- Сохраняем параметры создания для диагностики
    icon.createdWithSize = unitSettings.iconSize
    icon.createdWithSpacing = unitSettings.iconSpacing
    icon.iconIndex = index
    
    -- Создаем фон для иконки
    local slotStyle = {
        path = TEXTURE_PATH.HUD,
        coords = {685, 130, 7, 8},
        inset = {3, 3, 3, 3},
        color = {1, 1, 1, 1}
    }
    F_SLOT.ApplySlotSkin(icon, icon.back, slotStyle)
    
    icon:Show(false)
  end)
  
  -- Создаем лейбл для названия
  local nameLabel = createChildWidgetSafe(icon, "label", "nameLabel_" .. index)
  if nameLabel then
    pcall(function()
      nameLabel:SetExtent(unitSettings.iconSize * 2, unitSettings.iconSize/2)
      nameLabel:AddAnchor("CENTER", icon, unitSettings.labelX, unitSettings.labelY)
      nameLabel.style:SetFontSize(unitSettings.labelFontSize or 14)
      nameLabel.style:SetAlign(ALIGN.CENTER)
      nameLabel.style:SetShadow(true)
      
      -- Устанавливаем цвет из настроек
      if unitSettings.labelTextColor then
        nameLabel.style:SetColor(
          unitSettings.labelTextColor.r or 1, 
          unitSettings.labelTextColor.g or 1, 
          unitSettings.labelTextColor.b or 1, 
          1
        )
      else
        nameLabel.style:SetColor(1, 1, 1, 1)
      end
      
      nameLabel:SetText("")
      nameLabel:Show(false)
    end)
  end
  
  -- Создаем полупрозрачный фон для таймера (без изображения, только с цветом)
  local timerBg = createChildWidgetSafe(icon, "window", "timerBg_" .. index)
  if timerBg then
    pcall(function()
      -- Создаем полупрозрачный цветной фон, а не изображение
      local bg = timerBg:CreateColorDrawable(0, 0, 0, 0.5, "background")
      timerBg:SetExtent(unitSettings.iconSize, unitSettings.iconSize/2)
      timerBg:AddAnchor("BOTTOM", icon, 0, 0)
      timerBg:Show(false)
    end)
  end
  
  -- Создаем лейбл для таймера
  local timerLabel = createChildWidgetSafe(icon, "label", "timerLabel_" .. index)
  pcall(function()
    timerLabel:SetExtent(unitSettings.iconSize, unitSettings.iconSize/2)
    timerLabel:AddAnchor("CENTER", icon, unitSettings.timerX, unitSettings.timerY)
    timerLabel.style:SetFontSize(unitSettings.timerFontSize or 16)
    timerLabel.style:SetAlign(ALIGN.CENTER)
    timerLabel.style:SetShadow(true)
    
    -- Устанавливаем цвет из настроек
    if unitSettings.timerTextColor then
      timerLabel.style:SetColor(
        unitSettings.timerTextColor.r or 1, 
        unitSettings.timerTextColor.g or 1, 
        unitSettings.timerTextColor.b or 1, 
        1
      )
    else
      timerLabel.style:SetColor(1, 1, 1, 1)
    end
    
    timerLabel:SetText("")
    timerLabel:Show(false)
  end)
  
  icon.nameLabel = nameLabel
  icon.timerLabel = timerLabel
  icon.timerBg = timerBg
  
  return icon
end

local function createBuffCanvas()
  local canvas = api.Interface:CreateEmptyWindow("MountBuffCanvas")
  if not canvas then
    return nil
  end
  
  pcall(function()    
    -- Устанавливаем размер холста
    canvas:SetExtent(settings.playerpet.iconSize * 3, settings.playerpet.iconSize * 1.5)
    
    -- Явно устанавливаем позицию холста из настроек
    canvas:RemoveAllAnchors()
    canvas:AddAnchor("TOPLEFT", "UIParent", settings.playerpet.posX, settings.playerpet.posY)
    
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
  end)
  
  canvas.buffIcons = {}
  for i = 1, 10 do
    canvas.buffIcons[i] = addBuffIcon(canvas, i, "playerpet")
    
    -- Дополнительно убедимся, что иконка имеет правильную позицию, основанную на настройках
    if canvas.buffIcons[i] then
      pcall(function()
        canvas.buffIcons[i]:RemoveAllAnchors()
        canvas.buffIcons[i]:SetExtent(settings.playerpet.iconSize, settings.playerpet.iconSize)
        
        -- Явно вычисляем позицию иконки с учетом текущего интервала
        local xPosition = (i-1) * (settings.playerpet.iconSize + settings.playerpet.iconSpacing)
        canvas.buffIcons[i]:AddAnchor("LEFT", canvas, xPosition, 0)
      end)
    end
  end
  
  -- Реализация перетаскивания (drag) для canvas
  pcall(function()
    -- Флаг для отслеживания состояния перетаскивания
    canvas.isDragging = false
    
    -- Определяем функции для перетаскивания
    canvas.OnDragStart = function(self, arg)
      -- Проверяем, не заблокировано ли перемещение
      if settings.playerpet.lockPositioning then
        return
      end
      
      self.isDragging = true
      -- Делаем фон более заметным во время перетаскивания
      if self.bg then
        self.bg:SetColor(0, 0, 0, 0.6)  -- Более высокая непрозрачность при перетаскивании
      end
      
      self:StartMoving()
      api.Cursor:ClearCursor()
      api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
    end
    
    canvas.OnDragStop = function(self)
      -- Проверяем, не заблокировано ли перемещение
      if settings.playerpet.lockPositioning then
        return
      end
      
      self:StopMovingOrSizing()
      -- Возвращаем обычную непрозрачность после перетаскивания
      if self.bg then
        self.bg:SetColor(0, 0, 0, 0.4)
      end
      
      local x, y = self:GetOffset()
      settings.playerpet.posX = x
      settings.playerpet.posY = y
      
      -- Обновляем поля в окне настроек, если оно открыто
      if settingsPage and settingsPage.updatePositionFields then
        settingsPage.updatePositionFields(x, y)
      end
      
      -- Сохраняем настройки через helpers
      if helpers and helpers.updateSettings then
        helpers.updateSettings()
      end
      
      self.isDragging = false
      api.Cursor:ClearCursor()
    end
    
    -- Устанавливаем обработчики событий перетаскивания
    canvas:SetHandler("OnDragStart", canvas.OnDragStart)
    canvas:SetHandler("OnDragStop", canvas.OnDragStop)
    
    -- Регистрируем перетаскивание с помощью левой кнопки мыши
    if canvas.RegisterForDrag ~= nil then
      canvas:RegisterForDrag("LeftButton")
    end
    
    -- Включаем/отключаем перетаскивание в зависимости от настроек
    if canvas.EnableDrag ~= nil then
      canvas:EnableDrag(not settings.playerpet.lockPositioning)
    end
  end)
  
  return canvas
end

-- Создаем новую функцию для создания канваса баффов игрока
local function createPlayerBuffCanvas()
  local canvas = api.Interface:CreateEmptyWindow("PlayerBuffCanvas")
  if not canvas then
    return nil
  end
  
  pcall(function()    
    -- Устанавливаем размер холста
    canvas:SetExtent(settings.player.iconSize * 3, settings.player.iconSize * 1.5)
    
    -- Явно устанавливаем позицию холста из настроек
    canvas:RemoveAllAnchors()
    canvas:AddAnchor("TOPLEFT", "UIParent", settings.player.posX, settings.player.posY)
    
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
  end)
  
  canvas.buffIcons = {}
  for i = 1, 10 do
    canvas.buffIcons[i] = addBuffIcon(canvas, i, "player")
    
    -- Дополнительно убедимся, что иконка имеет правильную позицию, основанную на настройках
    if canvas.buffIcons[i] then
      pcall(function()
        canvas.buffIcons[i]:RemoveAllAnchors()
        canvas.buffIcons[i]:SetExtent(settings.player.iconSize, settings.player.iconSize)
        
        -- Явно вычисляем позицию иконки с учетом текущего интервала
        local xPosition = (i-1) * (settings.player.iconSize + settings.player.iconSpacing)
        canvas.buffIcons[i]:AddAnchor("LEFT", canvas, xPosition, 0)
      end)
    end
  end
  
  -- Реализация перетаскивания (drag) для canvas
  pcall(function()
    -- Флаг для отслеживания состояния перетаскивания
    canvas.isDragging = false
    
    -- Определяем функции для перетаскивания
    canvas.OnDragStart = function(self, arg)
      -- Проверяем, не заблокировано ли перемещение
      if settings.player.lockPositioning then
        return
      end
      
      self.isDragging = true
      -- Делаем фон более заметным во время перетаскивания
      if self.bg then
        self.bg:SetColor(0, 0, 0, 0.6)  -- Более высокая непрозрачность при перетаскивании
      end
      
      self:StartMoving()
      api.Cursor:ClearCursor()
      api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
    end
    
    canvas.OnDragStop = function(self)
      -- Проверяем, не заблокировано ли перемещение
      if settings.player.lockPositioning then
        return
      end
      
      self:StopMovingOrSizing()
      -- Возвращаем обычную непрозрачность после перетаскивания
      if self.bg then
        self.bg:SetColor(0, 0, 0, 0.4)
      end
      
      local x, y = self:GetOffset()
      settings.player.posX = x
      settings.player.posY = y
      
      -- Обновляем поля в окне настроек, если оно открыто
      if settingsPage and settingsPage.updatePositionFields then
        settingsPage.updatePositionFields(x, y)
      end
      
      -- Сохраняем настройки через helpers
      if helpers and helpers.updateSettings then
        helpers.updateSettings()
      end
      
      self.isDragging = false
      api.Cursor:ClearCursor()
    end
    
    -- Устанавливаем обработчики событий перетаскивания
    canvas:SetHandler("OnDragStart", canvas.OnDragStart)
    canvas:SetHandler("OnDragStop", canvas.OnDragStop)
    
    -- Регистрируем перетаскивание с помощью левой кнопки мыши
    if canvas.RegisterForDrag ~= nil then
      canvas:RegisterForDrag("LeftButton")
    end
    
    -- Включаем/отключаем перетаскивание в зависимости от настроек
    if canvas.EnableDrag ~= nil then
      canvas:EnableDrag(not settings.player.lockPositioning)
    end
  end)
  
  return canvas
end

-- Функция для проверки наличия баффов для отслеживания
local function hasTrackedBuffs(unitType)
  -- Сначала проверяем настройку, которая полностью отключает отслеживание
  local settings = api.GetSettings("CooldawnBuffTracker") or {}
  
  if unitType == "player" then
    -- Проверяем настройки для игрока
    if not settings.player or settings.player.enabled == false then
      return false
    end
    
    -- Проверяем наличие баффов в списке
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds("player")
    return #trackedBuffIds > 0
  elseif unitType == "playerpet" then
    -- Проверяем настройки для маунта
    if not settings.playerpet or settings.playerpet.enabled == false then
      return false
    end
    
    -- Проверяем наличие баффов в списке
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds("playerpet")
    return #trackedBuffIds > 0
  else
    -- Если тип не указан, проверяем наличие баффов для любого типа
    local trackedMountBuffIds = BuffsToTrack.GetAllTrackedBuffIds("playerpet")
    local trackedPlayerBuffIds = BuffsToTrack.GetAllTrackedBuffIds("player")
    
    local hasMountBuffs = settings.playerpet and settings.playerpet.enabled ~= false and #trackedMountBuffIds > 0
    local hasPlayerBuffs = settings.player and settings.player.enabled ~= false and #trackedPlayerBuffIds > 0
    
    return hasMountBuffs or hasPlayerBuffs
  end
end

local function updateBuffIcons()
  local status, err = pcall(function()
    if not buffCanvas or not isCanvasInitialized then return end
    
    -- Проверяем, есть ли баффы для отслеживания
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds("playerpet")
    if #trackedBuffIds == 0 then
      buffCanvas:Show(false)
      return
    end
    
    -- Создаем упорядоченный список баффов в соответствии с порядком добавления
    local activeBuffs = {}
    for i, buffId in ipairs(trackedBuffIds) do
      if buffData[buffId] then
        table.insert(activeBuffs, {id = buffId, buff = buffData[buffId], order = i})
      end
    end
    
    -- Если нет баффов для отслеживания, скрываем холст
    if #activeBuffs == 0 then
      buffCanvas:Show(false)
      return
    end
    
    for i, icon in ipairs(buffCanvas.buffIcons or {}) do
      if icon and icon.Show then
        pcall(function() 
          -- Обновляем размер для каждой иконки и позицию с учетом интервала
          icon:SetExtent(settings.playerpet.iconSize, settings.playerpet.iconSize)
          
          -- Пересчитываем позицию с учетом текущего интервала
          icon:RemoveAllAnchors()
          local xPosition = (i-1) * (settings.playerpet.iconSize + settings.playerpet.iconSpacing)
          icon:AddAnchor("LEFT", buffCanvas, xPosition, 0)
          
          icon:Show(false) 
        end)
      end
    end
    
    -- Получаем текущее время для обновления статусов
    local currentTime = tonumber(getCurrentTime()) or 0
    
    -- Обновляем все иконки в соответствии с текущим списком баффов
    for i, buffInfo in ipairs(activeBuffs) do
      local icon = buffCanvas.buffIcons[i]
      if icon then
        local buffId = buffInfo.id
        local buff = buffInfo.buff
        
        pcall(function()
          -- Получаем иконку для баффа
          local iconPath = BuffList.GetBuffIcon(buffId) or "icon_default"
          F_SLOT.SetIconBackGround(icon, buff.icon)
          
          -- Явно устанавливаем иконку видимой
          icon:SetVisible(true)
        end)
        
        -- Сохраняем ID баффа для использования в обработчиках событий
        icon.buffId = buffId
        icon:Show(true)
        
        -- Отображаем название баффа, если включено в настройках
        if icon.nameLabel and settings.playerpet.showLabel then
          pcall(function()
            icon.nameLabel:SetText(buff.name or "")
            icon.nameLabel:Show(true)
          end)
        elseif icon.nameLabel then
          pcall(function()
            icon.nameLabel:Show(false)
          end)
        end
        
        -- Определяем текущий статус баффа
        local currentStatus = buff.status
        if buff.fixedTime then
          currentStatus = checkBuffStatus(buff, currentTime)
        end
        
        -- Устанавливаем цвет иконки в зависимости от статуса
        if currentStatus == "ready" then
          -- Для готового баффа - прозрачный оверлей (никакой подсветки)
          pcall(function() 
            if icon.statusOverlay then
              icon.statusOverlay:SetColor(1, 1, 1, 0) -- Полностью прозрачный
            end
            
            -- Невидимая рамка для готового состояния
            if icon.topBorder then icon.topBorder:SetColor(1, 1, 1, 0) end
            if icon.bottomBorder then icon.bottomBorder:SetColor(1, 1, 1, 0) end
            if icon.leftBorder then icon.leftBorder:SetColor(1, 1, 1, 0) end
            if icon.rightBorder then icon.rightBorder:SetColor(1, 1, 1, 0) end
            
            -- Также возвращаем нормальный белый цвет иконке
            icon:SetColor(ICON_COLORS.READY[1], ICON_COLORS.READY[2], ICON_COLORS.READY[3], ICON_COLORS.READY[4])
          end)
        elseif currentStatus == "active" then
          -- Для активного баффа - зеленая подсветка
          pcall(function() 
            if icon.statusOverlay then
              icon.statusOverlay:SetColor(0, 1, 0, 0.3) -- Зеленый полупрозрачный
            end
            
            -- Яркая зеленая рамка для активного состояния
            local borderColor = {0, 1, 0, 0.8} -- Яркий зеленый
            if icon.topBorder then icon.topBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.bottomBorder then icon.bottomBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.leftBorder then icon.leftBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.rightBorder then icon.rightBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            
            -- Также устанавливаем зеленый цвет для иконки
            icon:SetColor(ICON_COLORS.ACTIVE[1], ICON_COLORS.ACTIVE[2], ICON_COLORS.ACTIVE[3], ICON_COLORS.ACTIVE[4])
          end)
        elseif currentStatus == "cooldown" then
          -- Для баффа на кулдауне - красная подсветка
          pcall(function() 
            if icon.statusOverlay then
              icon.statusOverlay:SetColor(1, 0, 0, 0.3) -- Красный полупрозрачный
            end
            
            -- Яркая красная рамка для состояния кулдауна
            local borderColor = {1, 0, 0, 0.8} -- Яркий красный
            if icon.topBorder then icon.topBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.bottomBorder then icon.bottomBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.leftBorder then icon.leftBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.rightBorder then icon.rightBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            
            -- Также устанавливаем красный цвет для иконки
            icon:SetColor(ICON_COLORS.COOLDOWN[1], ICON_COLORS.COOLDOWN[2], ICON_COLORS.COOLDOWN[3], ICON_COLORS.COOLDOWN[4])
          end)
        end
        
        -- Отображаем таймер, если включено в настройках
        if icon.timerLabel and settings.playerpet.showTimer then
          pcall(function()
            local timerText = ""
            
            if currentStatus == "active" and buff.fixedTime then
              local remainingActive = buff.timeOfAction - (currentTime - buff.fixedTime)
              if remainingActive > 0 then
                timerText = formatTimerSeconds(remainingActive)
              end
            elseif currentStatus == "cooldown" and buff.fixedTime then
              local remainingCooldown = buff.cooldown - (currentTime - buff.fixedTime)
              if remainingCooldown > 0 then
                timerText = formatTimerSeconds(remainingCooldown)
              end
            end
            
            icon.timerLabel:SetText(timerText)
            
            -- Устанавливаем цвет текста таймера из настроек
            local timerTextColor = settings.playerpet.timerTextColor or {r = 1, g = 1, b = 1, a = 1}
            icon.timerLabel.style:SetColor(timerTextColor.r, timerTextColor.g, timerTextColor.b, timerTextColor.a)
            
            -- Показываем таймер только если есть текст
            icon.timerLabel:Show(timerText ~= "")
            
            -- Показываем фон таймера, если есть текст
            if icon.timerBg then
              icon.timerBg:Show(timerText ~= "")
            end
          end)
        elseif icon.timerLabel then
          pcall(function()
            icon.timerLabel:Show(false)
            if icon.timerBg then
              icon.timerBg:Show(false)
            end
          end)
        end
      end
    end
    
    -- Скрываем лишние иконки
    for i = #activeBuffs + 1, #buffCanvas.buffIcons do
      local icon = buffCanvas.buffIcons[i]
      if icon then
        pcall(function()
          icon:Show(false)
          if icon.nameLabel then icon.nameLabel:Show(false) end
          if icon.timerLabel then icon.timerLabel:Show(false) end
          if icon.timerBg then icon.timerBg:Show(false) end
        end)
      end
    end
    
    -- Обновляем размер холста
    local totalWidth = 0
    pcall(function()
      totalWidth = (#activeBuffs) * settings.playerpet.iconSize + (#activeBuffs - 1) * settings.playerpet.iconSpacing
      totalWidth = math.max(totalWidth, settings.playerpet.iconSize * 2)
      
      -- Устанавливаем новый размер холста
      buffCanvas:SetWidth(totalWidth)
      buffCanvas:SetHeight(settings.playerpet.iconSize * 1.2)
      
      -- Устанавливаем позицию только если холст не перетаскивается
      if buffCanvas.isDragging ~= true then
        buffCanvas:RemoveAllAnchors()
        buffCanvas:AddAnchor("TOPLEFT", "UIParent", settings.playerpet.posX, settings.playerpet.posY)
        
        -- Убедимся, что перетаскивание по-прежнему включено/отключено правильно
        pcall(function()
          if buffCanvas.EnableDrag ~= nil then
            buffCanvas:EnableDrag(not settings.playerpet.lockPositioning)
          end
        end)
      end
      
      if buffCanvas.bg then
        buffCanvas.bg:SetColor(0, 0, 0, 0.4)
      end
      buffCanvas:Show(true)
    end)
  end)
  
  if not status then
    safeLog("Ошибка при обновлении иконок: " .. tostring(err))
  end
end

local function checkMountBuffs()
  local status, err = pcall(function()
    -- Скрываем окно, если аддон выключен в настройках
    if not settings.playerpet.enabled then
      if buffCanvas then
        buffCanvas:Show(false)
      end
      return
    end
    
    -- Проверяем, есть ли баффы для отслеживания
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds("playerpet")
    
    -- Если список отслеживаемых баффов пуст, скрываем канвас 
    if #trackedBuffIds == 0 then
      if buffCanvas then
        buffCanvas:Show(false)
      end
      return
    end
    
    local activeBuffsOnMount = {}
    local hasChanges = false
    local currentBuffsOnMount = {}
    
    -- Проверяем активные баффы на маунте
    for i = 1, api.Unit:UnitBuffCount("playerpet") do
      local buff = api.Unit:UnitBuff("playerpet", i)
      
      -- Исправляем доступ к ID баффа - используем buff.buff_id вместо buff.id
      if buff and buff.buff_id then
        -- Записываем ID текущих баффов для дальнейшего сравнения
        currentBuffsOnMount[buff.buff_id] = true
        
        -- Для режима отладки регистрируем новые баффы маунта
        if settings.debugBuffId and not cachedMountBuffs[buff.buff_id] then
          pcall(function()
            api.Log:Info("[CooldawnBuffTracker] Новый бафф на маунте: " .. tostring(buff.buff_id))
          end)
        end
        
        -- Добавляем в активные только отслеживаемые баффы
        if BuffsToTrack.ShouldTrackBuff(buff.buff_id) then
          activeBuffsOnMount[buff.buff_id] = true
        end
      end
    end
    
    -- Обновляем кэш баффов маунта
    cachedMountBuffs = currentBuffsOnMount
    
    local currentTime = tonumber(getCurrentTime()) or 0
    
    for buffId, buffInfo in pairs(buffData) do
      local oldStatus = buffInfo.status
      
      if activeBuffsOnMount[buffId] then
        if buffInfo.status ~= "active" then
          setBuffStatus(buffId, "active", currentTime, "playerpet")
          hasChanges = true
          
          -- Логируем только изменение статуса для отслеживаемых баффов
          if settings.debugBuffId and cachedBuffStatus[buffId] ~= "active" then
            pcall(function()
              api.Log:Info(string.format("[CooldawnBuffTracker] Бафф ID %d сменил статус на: active", buffId))
            end)
          end
          
          -- Обновляем кэш статуса
          cachedBuffStatus[buffId] = "active"
        end
      else
        if buffInfo.fixedTime then
          local expectedStatus = checkBuffStatus(buffInfo, currentTime)
          
          if expectedStatus ~= buffInfo.status then
            setBuffStatus(buffId, expectedStatus, currentTime, "playerpet")
            hasChanges = true
            
            -- Логируем только изменение статуса для отслеживаемых баффов
            if settings.debugBuffId and cachedBuffStatus[buffId] ~= expectedStatus then
              pcall(function()
                api.Log:Info(string.format("[CooldawnBuffTracker] Бафф ID %d сменил статус на: %s", buffId, expectedStatus))
              end)
            end
            
            -- Обновляем кэш статуса
            cachedBuffStatus[buffId] = expectedStatus
          end
        elseif buffInfo.status ~= "ready" then
          setBuffStatus(buffId, "ready", nil, "playerpet")
          hasChanges = true
          
          -- Логируем только изменение статуса для отслеживаемых баффов
          if settings.debugBuffId and cachedBuffStatus[buffId] ~= "ready" then
            pcall(function()
              api.Log:Info(string.format("[CooldawnBuffTracker] Бафф ID %d сменил статус на: ready", buffId))
            end)
          end
          
          -- Обновляем кэш статуса
          cachedBuffStatus[buffId] = "ready"
        end
      end
    end
    
    -- Проверяем, исчезли ли какие-то баффы с маунта
    if settings.debugBuffId then
      for buffId in pairs(cachedMountBuffs) do
        if not currentBuffsOnMount[buffId] then
          pcall(function()
            api.Log:Info("[CooldawnBuffTracker] Бафф исчез с маунта: " .. tostring(buffId))
          end)
        end
      end
    end
    
    if hasChanges and isCanvasInitialized then
      updateBuffIcons()
    end
  end)
  
  if not status then
    safeLog("Ошибка при проверке баффов: " .. tostring(err))
  end
end

-- Функция для проверки наличия баффов игрока
local function checkPlayerBuffs()
  local status, err = pcall(function()
    -- Скрываем окно, если аддон выключен в настройках
    if not settings.player.enabled then
      if playerBuffCanvas then
        playerBuffCanvas:Show(false)
      end
      return
    end
    
    -- Проверяем, есть ли баффы для отслеживания
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds("player")
    
    -- Если список отслеживаемых баффов пуст, скрываем канвас 
    if #trackedBuffIds == 0 then
      if playerBuffCanvas then
        playerBuffCanvas:Show(false)
      end
      return
    end
    
    local activeBuffsOnPlayer = {}
    local hasChanges = false
    local currentBuffsOnPlayer = {}
    
    -- Проверяем активные баффы на игроке
    pcall(function()
      -- Получаем все активные баффы на игроке
      local buffCount = api.Unit:UnitBuffCount("player") or 0
      for i = 1, buffCount do
        local buff = api.Unit:UnitBuff("player", i)
        
        -- Проверяем, что бафф существует и имеет идентификатор
        if buff and buff.buff_id then
          -- Записываем ID текущих баффов для дальнейшего сравнения
          currentBuffsOnPlayer[buff.buff_id] = true
          
          -- Для режима отладки регистрируем новые баффы игрока
          if settings.debugBuffId and not cachedPlayerBuffs[buff.buff_id] then
            pcall(function()
              api.Log:Info("[CooldawnBuffTracker] Новый бафф на игроке: " .. tostring(buff.buff_id))
            end)
            cachedPlayerBuffs[buff.buff_id] = true
          end
          
          -- Проверяем, нужно ли отслеживать этот бафф
          if BuffsToTrack.ShouldTrackBuff(buff.buff_id, "player") then
            -- Если баффа еще нет в данных или он не активен, обновляем его статус
            if not playerBuffData[buff.buff_id] or (playerBuffData[buff.buff_id].status ~= "active") then
              -- Бафф стал активным, обновляем его статус
              setBuffStatus(buff.buff_id, "active", getCurrentTime(), "player")
              hasChanges = true
              
              -- Логируем только изменение статуса для отслеживаемых баффов
              if settings.debugBuffId then
                pcall(function()
                  api.Log:Info(string.format("[CooldawnBuffTracker] Бафф ID %d (player) сменил статус на: active", buff.buff_id))
                end)
              end
              
              -- Обновляем кэш статуса
              cachedBuffStatus[buff.buff_id] = "active"
            end
          end
        end
      end
    end)
    
    -- Проверяем баффы, которые были активны, но теперь их нет
    local currentTime = tonumber(getCurrentTime())
    for _, buffId in ipairs(trackedBuffIds) do
      if playerBuffData[buffId] then
        local buffInfo = playerBuffData[buffId]
        
        if currentBuffsOnPlayer[buffId] then
          -- Бафф активен на игроке, ничего не делаем
        elseif buffInfo.status == "active" then
          -- Если бафф был активным, но теперь его нет - он на кулдауне
          setBuffStatus(buffId, "cooldown", currentTime, "player")
          hasChanges = true
          
          -- Логируем только изменение статуса для отслеживаемых баффов
          if settings.debugBuffId and cachedBuffStatus[buffId] ~= "cooldown" then
            pcall(function()
              api.Log:Info(string.format("[CooldawnBuffTracker] Бафф ID %d (player) сменил статус на: cooldown", buffId))
            end)
          end
          
          -- Обновляем кэш статуса
          cachedBuffStatus[buffId] = "cooldown"
        elseif buffInfo.status == "cooldown" then
          -- Если бафф уже на кулдауне, проверим, не закончился ли он
          local timeSinceLastStatus = currentTime - (buffInfo.statusChangeTime or 0)
          local cooldownTime = BuffList.GetBuffCooldown(buffId) or 0
          
          if cooldownTime > 0 and timeSinceLastStatus >= cooldownTime then
            -- Если время кулдауна истекло, бафф снова готов к использованию
            setBuffStatus(buffId, "ready", currentTime, "player")
            hasChanges = true
            
            -- Логируем только изменение статуса для отслеживаемых баффов
            if settings.debugBuffId and cachedBuffStatus[buffId] ~= "ready" then
              pcall(function()
                api.Log:Info(string.format("[CooldawnBuffTracker] Бафф ID %d (player) сменил статус на: ready", buffId))
              end)
            end
            
            -- Обновляем кэш статуса
            cachedBuffStatus[buffId] = "ready"
          end
        end
      end
    end
    
    -- Показываем окно только если есть отслеживаемые баффы и если отслеживание разрешено в настройках
    local hasBuffs = false
    for _ in pairs(playerBuffData) do
        hasBuffs = true
        break
    end
    
    if hasBuffs and settings.player.enabled then
      if not isPlayerCanvasInitialized then
        local success, _ = pcall(function()
          playerBuffCanvas = createPlayerBuffCanvas()
          isPlayerCanvasInitialized = true
        end)
        if not success then
          safeLog("Ошибка при инициализации канваса баффов игрока")
        end
      end
      
      if playerBuffCanvas then
        playerBuffCanvas:Show(true)
      end
      
      if hasChanges then
        updatePlayerBuffIcons()
      end
    end
  end)
  
  if not status then
    safeLog("Ошибка при проверке баффов игрока: " .. tostring(err))
  end
end

local function OnUpdate(dt)
  updateTimer = updateTimer + dt
  if updateTimer >= updateInterval then
    checkMountBuffs()
    checkPlayerBuffs()
    updateTimer = 0
  end
  
  refreshUITimer = refreshUITimer + dt
  if refreshUITimer >= refreshUIInterval then
    if isCanvasInitialized then
      pcall(updateBuffIcons)
    end
    if isPlayerCanvasInitialized then
      pcall(updatePlayerBuffIcons)
    end
    refreshUITimer = 0
  end
end

local function OnLoad()
  pcall(function()
    safeLog("Loading CooldawnBuffTracker " .. CooldawnBuffTracker.version .. " by " .. CooldawnBuffTracker.author)
  end)
  
  -- Загружаем модуль для работы с баффами
  pcall(function()
    BuffsToTrack = require("CooldawnBuffTracker/buffs_to_track") or require("buffs_to_track") or require("./buffs_to_track")
  end)
  
  -- Загружаем модуль с информацией о доступных баффах
  pcall(function()
    BuffList = require("CooldawnBuffTracker/buff_helper") or require("buff_helper") or require("./buff_helper")
  end)
  
  -- Загружаем модуль с функциями-помощниками
  pcall(function()
    helpers = require("CooldawnBuffTracker/helpers") or require("helpers") or require("./helpers") 
  end)
  
  -- Загружаем модуль для работы со страницей настроек
  pcall(function()
    settingsPage = require("CooldawnBuffTracker/settings_page") or require("settings_page") or require("./settings_page")
  end)
  
  if not BuffsToTrack then
    -- Если не удалось загрузить модуль для работы с баффами, создаем заглушку
    BuffsToTrack = {
      GetAllTrackedBuffIds = function() return {} end,
      ShouldTrackBuff = function(id) return false end
    }
    pcall(function() api.Log:Info("Не удалось загрузить buffs_to_track.lua, используем заглушку") end)
  end
  
  if not BuffList then
    BuffList = {
      GetBuffName = function(id) return "Бафф #" .. id end,
      GetBuffIcon = function(id) return nil end,
      GetBuffCooldown = function(id) return 0 end,
      GetBuffTimeOfAction = function(id) return 0 end
    }
    pcall(function() api.Log:Info("Не удалось загрузить buff_helper.lua, используем заглушку") end)
  end
  
  -- Загружаем настройки, если доступны
  if helpers and helpers.getSettings then
    settings = helpers.getSettings()
  else
    settings = api.GetSettings("CooldawnBuffTracker") or {}
  end
  
  -- Проверяем корректность настроек и мигрируем на новую структуру, если необходимо
  if not settings.playerpet then
    -- Если нет разделения на playerpet и player, создаем новую структуру
    local defaultSettings = require("CooldawnBuffTracker/default_settings") or require("default_settings") or require("./default_settings") or {}
    
    -- Создаем структуру для playerpet
    settings.playerpet = {
      posX = settings.posX or defaultPositionX,
      posY = settings.posY or defaultPositionY,
      iconSize = settings.iconSize or iconSize,
      iconSpacing = settings.iconSpacing or 5,
      lockPositioning = settings.lockPositioning or false,
      enabled = settings.enabled ~= false, -- По умолчанию включено
      timerTextColor = settings.timerTextColor or {r = 1, g = 1, b = 1, a = 1},
      labelTextColor = settings.labelTextColor or {r = 1, g = 1, b = 1, a = 1},
      showLabel = settings.showLabel or false,
      labelFontSize = settings.labelFontSize or 14,
      labelX = settings.labelX or 0,
      labelY = settings.labelY or -30,
      showTimer = settings.showTimer ~= false, -- По умолчанию включено
      timerFontSize = settings.timerFontSize or 16,
      timerX = settings.timerX or 0,
      timerY = settings.timerY or 0,
      trackedBuffs = settings.trackedBuffs or {}
    }
    
    -- Создаем структуру для player
    settings.player = {
      posX = settings.posX or defaultPositionX,
      posY = (settings.posY or defaultPositionY) + 70, -- Немного ниже маунта
      iconSize = settings.iconSize or iconSize,
      iconSpacing = settings.iconSpacing or 5,
      lockPositioning = settings.lockPositioning or false,
      enabled = true, -- По умолчанию включено
      timerTextColor = settings.timerTextColor or {r = 1, g = 1, b = 1, a = 1},
      labelTextColor = settings.labelTextColor or {r = 1, g = 1, b = 1, a = 1},
      showLabel = settings.showLabel or false,
      labelFontSize = settings.labelFontSize or 14,
      labelX = settings.labelX or 0,
      labelY = settings.labelY or -30,
      showTimer = settings.showTimer ~= false, -- По умолчанию включено
      timerFontSize = settings.timerFontSize or 16,
      timerX = settings.timerX or 0,
      timerY = settings.timerY or 0,
      trackedBuffs = {}
    }
    
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
    
    -- Сохраняем обновленные настройки
    if helpers and helpers.updateSettings then
      helpers.updateSettings(settings)
    else
      api.SaveSettings()
    end
    
    safeLog("Настройки мигрированы на новую структуру с разделением на playerpet и player")
  end
  
  -- Проверяем наличие ключа debugBuffId
  if settings.debugBuffId == nil then
    settings.debugBuffId = false
  end
  
  -- Проверяем корректность настроек
  if settings.iconSize == nil then
    safeLog("Отсутствует ключ iconSize в настройках, устанавливаем значение по умолчанию")
    settings.iconSize = iconSize
  end
  
  if settings.iconSpacing == nil then
    safeLog("Отсутствует ключ iconSpacing в настройках, устанавливаем значение по умолчанию")
    settings.iconSpacing = 5
  end
  
  if settings.posX == nil then
    safeLog("Отсутствует ключ posX в настройках, устанавливаем значение по умолчанию")
    settings.posX = defaultPositionX
  end
  
  if settings.posY == nil then
    safeLog("Отсутствует ключ posY в настройках, устанавливаем значение по умолчанию")
    settings.posY = defaultPositionY
  end
  
  -- Инициализируем страницу настроек, если модуль загружен
  if settingsPage and settingsPage.Load then
    pcall(function() settingsPage.Load() end)
  end
  
  pcall(initBuffData)
  
  -- Проверяем, есть ли отслеживаемые баффы маунта при загрузке
  local shouldShowMountUI = hasTrackedBuffs("playerpet")
  safeLog("Инициализация UI маунта: " .. (shouldShowMountUI and "показать" or "скрыть"))
  
  -- Проверяем, есть ли отслеживаемые баффы игрока при загрузке
  local shouldShowPlayerUI = hasTrackedBuffs("player")
  safeLog("Инициализация UI игрока: " .. (shouldShowPlayerUI and "показать" or "скрыть"))
  
  -- Создаем канвас для маунта, если есть отслеживаемые баффы
  if shouldShowMountUI then
    local success, result = pcall(createBuffCanvas)
    if success and result then
      buffCanvas = result
      isCanvasInitialized = true
      updateBuffIcons()
    else
      safeLog("Ошибка при создании канваса баффов маунта: " .. tostring(result))
      
      -- Повторная попытка создания канваса с задержкой
      api:DoIn(1000, function()
        local retrySuccess, retryResult = pcall(createBuffCanvas)
        if retrySuccess and retryResult then
          buffCanvas = retryResult
          isCanvasInitialized = true
          updateBuffIcons()
        else
          safeLog("Повторная ошибка при создании канваса баффов маунта: " .. tostring(retryResult))
        end
      end)
    end
  end
  
  -- Создаем канвас для игрока, если есть отслеживаемые баффы
  if shouldShowPlayerUI then
    local success, result = pcall(createPlayerBuffCanvas)
    if success and result then
      playerBuffCanvas = result
      isPlayerCanvasInitialized = true
      updatePlayerBuffIcons()
    else
      safeLog("Ошибка при создании канваса баффов игрока: " .. tostring(result))
      
      -- Повторная попытка создания канваса с задержкой
      api:DoIn(1000, function()
        local retrySuccess, retryResult = pcall(createPlayerBuffCanvas)
        if retrySuccess and retryResult then
          playerBuffCanvas = retryResult
          isPlayerCanvasInitialized = true
          updatePlayerBuffIcons()
        else
          safeLog("Повторная ошибка при создании канваса баффов игрока: " .. tostring(retryResult))
        end
      end)
    end
  end
  
  pcall(function() 
    api.On("UPDATE", OnUpdate)
  end)
  
  -- Создаем ассоциацию с обработчиком обновления настроек
  pcall(function()
    CooldawnBuffTracker.OnSettingsSaved = function()
      -- Полностью пересоздаем UI при изменении настроек
      if helpers then
        settings = helpers.getSettings(buffCanvas, playerBuffCanvas)
      end
      
      -- Обновляем канвас маунта
      local shouldShowMountUI = hasTrackedBuffs("playerpet")
      
      -- Если нет баффов для отслеживания, скрываем канвас маунта
      if not shouldShowMountUI and buffCanvas then
        pcall(function() buffCanvas:Show(false) end)
      elseif shouldShowMountUI then
        -- Если баффы есть, но канвас не создан, создаем его
        if not isCanvasInitialized then
          local success, result = pcall(createBuffCanvas)
          if success and result then
            buffCanvas = result
            isCanvasInitialized = true
          end
        end
        
        -- Обновляем иконки
        if isCanvasInitialized then
          updateBuffIcons()
        end
      end
      
      -- Обновляем канвас игрока
      local shouldShowPlayerUI = hasTrackedBuffs("player")
      
      -- Если нет баффов для отслеживания, скрываем канвас игрока
      if not shouldShowPlayerUI and playerBuffCanvas then
        pcall(function() playerBuffCanvas:Show(false) end)
      elseif shouldShowPlayerUI then
        -- Если баффы есть, но канвас не создан, создаем его
        if not isPlayerCanvasInitialized then
          local success, result = pcall(createPlayerBuffCanvas)
          if success and result then
            playerBuffCanvas = result
            isPlayerCanvasInitialized = true
          end
        end
        
        -- Обновляем иконки
        if isPlayerCanvasInitialized then
          updatePlayerBuffIcons()
        end
      end
    end
  end)
end

local function OnUnload()
  -- Only keep initialization/unload log
  pcall(function() api.On("UPDATE", function() end) end)
  
  buffData = {}
  isCanvasInitialized = false
  
  if buffCanvas then
    pcall(function() 
      buffCanvas:Show(false)
      if buffCanvas.ReleaseHandler then
        buffCanvas:ReleaseHandler("OnDragStart")
        buffCanvas:ReleaseHandler("OnDragStop")
      end
    end)
  end
  buffCanvas = nil
  
  -- Выгружаем страницу настроек, если модуль загружен
  if settingsPage and settingsPage.Unload then
    pcall(function() settingsPage.Unload() end)
  end
  
  -- Сохраняем настройки через helpers
  if helpers and helpers.updateSettings then
    helpers.updateSettings()
  end
end

-- Обработчик открытия окна настроек
local function OnSettingToggle()
  if settingsPage and settingsPage.openSettingsWindow then
    pcall(function() settingsPage.openSettingsWindow() end)
  end
end

CooldawnBuffTracker.OnLoad = OnLoad
CooldawnBuffTracker.OnUnload = OnUnload
CooldawnBuffTracker.OnSettingToggle = OnSettingToggle

-- Также добавим функцию SetBorderColor для иконок, если её нет:
local originalCreateItemIconButton = CreateItemIconButton
if originalCreateItemIconButton then
  CreateItemIconButton = function(name, parent)
    local icon = originalCreateItemIconButton(name, parent)
    if icon and not icon.SetBorderColor then
      icon.SetBorderColor = function(self, r, g, b, a)
        -- Устанавливаем цвет рамки, если метод доступен
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
    safeLog("Получено событие обновления списка баффов")
    
    -- Обновляем данные баффов (включая удаление ненужных)
    local oldMountBuffsCount = 0
    for _ in pairs(buffData) do oldMountBuffsCount = oldMountBuffsCount + 1 end
    
    local oldPlayerBuffsCount = 0
    for _ in pairs(playerBuffData) do oldPlayerBuffsCount = oldPlayerBuffsCount + 1 end
    
    -- Инициализируем данные баффов
    initBuffData()
    
    -- Подсчитываем новое количество баффов
    local newMountBuffsCount = 0
    for _ in pairs(buffData) do newMountBuffsCount = newMountBuffsCount + 1 end
    
    local newPlayerBuffsCount = 0
    for _ in pairs(playerBuffData) do newPlayerBuffsCount = newPlayerBuffsCount + 1 end
    
    safeLog("Обновление списка баффов маунта: было " .. oldMountBuffsCount .. ", стало " .. newMountBuffsCount)
    safeLog("Обновление списка баффов игрока: было " .. oldPlayerBuffsCount .. ", стало " .. newPlayerBuffsCount)
    
    -- Проверяем, нужно ли показывать канвас маунта
    local shouldShowMountUI = hasTrackedBuffs("playerpet")
    
    -- Если нет баффов для отслеживания, скрываем канвас маунта
    if not shouldShowMountUI and buffCanvas then
      pcall(function() buffCanvas:Show(false) end)
    elseif shouldShowMountUI then
      -- Если баффы есть, но канвас не создан, создаем его
      if not isCanvasInitialized then
        local success, result = pcall(createBuffCanvas)
        if success and result then
          buffCanvas = result
          isCanvasInitialized = true
        end
      end
      
      -- Обновляем иконки
      if isCanvasInitialized then
        updateBuffIcons()
      end
    end
    
    -- Проверяем, нужно ли показывать канвас игрока
    local shouldShowPlayerUI = hasTrackedBuffs("player")
    
    -- Если нет баффов для отслеживания, скрываем канвас игрока
    if not shouldShowPlayerUI and playerBuffCanvas then
      pcall(function() playerBuffCanvas:Show(false) end)
    elseif shouldShowPlayerUI then
      -- Если баффы есть, но канвас не создан, создаем его
      if not isPlayerCanvasInitialized then
        local success, result = pcall(createPlayerBuffCanvas)
        if success and result then
          playerBuffCanvas = result
          isPlayerCanvasInitialized = true
        end
      end
      
      -- Обновляем иконки
      if isPlayerCanvasInitialized then
        updatePlayerBuffIcons()
      end
    end
  end)
end)

-- Обработчик события когда список баффов становится пустым
pcall(function()
  api.On("MOUNT_BUFF_TRACKER_EMPTY_LIST", function()
    safeLog("Получено событие о пустом списке баффов - принудительно скрываем канвас")
    
    -- Принудительно скрываем канвас
    pcall(function()
      if buffCanvas then
        buffCanvas:Show(false)
        safeLog("Канвас скрыт успешно")
      end
    end)
    
    -- Для гарантии обнуляем данные
    pcall(function()
      for buffId in pairs(buffData) do
        buffData[buffId] = nil
      end
    end)
  end)
end)

-- Добавляем новую функцию для обновления иконок баффов игрока
function updatePlayerBuffIcons()
  local status, err = pcall(function()
    if not playerBuffCanvas or not isPlayerCanvasInitialized then return end
    
    -- Проверяем, есть ли баффы для отслеживания
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds("player")
    if #trackedBuffIds == 0 then
      playerBuffCanvas:Show(false)
      return
    end
    
    -- Создаем упорядоченный список баффов в соответствии с порядком добавления
    local activeBuffs = {}
    for i, buffId in ipairs(trackedBuffIds) do
      if playerBuffData[buffId] then
        table.insert(activeBuffs, {id = buffId, buff = playerBuffData[buffId], order = i})
      end
    end
    
    -- Если нет баффов для отслеживания, скрываем холст
    if #activeBuffs == 0 then
      playerBuffCanvas:Show(false)
      return
    end
    
    -- Сортируем баффы по порядку
    table.sort(activeBuffs, function(a, b) return a.order < b.order end)
    
    -- Получаем текущее время для обновления статусов
    local currentTime = tonumber(getCurrentTime()) or 0
    
    -- Обновляем все иконки в соответствии с текущим списком баффов
    for i, buffInfo in ipairs(activeBuffs) do
      local icon = playerBuffCanvas.buffIcons[i]
      if icon then
        local buffId = buffInfo.id
        local buff = buffInfo.buff
        
        pcall(function()
          -- Убедимся, что иконка правильно позиционирована перед показом
          icon:RemoveAllAnchors()
          local xPosition = (i-1) * (settings.player.iconSize + settings.player.iconSpacing)
          icon:AddAnchor("LEFT", playerBuffCanvas, xPosition, 0)
          
          -- Устанавливаем иконку для баффа
          F_SLOT.SetIconBackGround(icon, buff.icon)
          icon:SetVisible(true)
        end)
        
        -- Сохраняем ID баффа для последующего использования
        icon.buffId = buffId
        icon:Show(true)
        
        -- Отображаем название баффа, если включено
        if icon.nameLabel and settings.player.showLabel then
          pcall(function()
            icon.nameLabel:SetText(buff.name or "")
            icon.nameLabel:Show(true)
          end)
        elseif icon.nameLabel then
          pcall(function()
            icon.nameLabel:Show(false)
          end)
        end
        
        -- Определяем текущий статус баффа
        local currentStatus = "ready"
        
        if buff.fixedTime then
          currentStatus = checkBuffStatus(buff, currentTime)
        else
          currentStatus = buff.status
        end
        
        -- Устанавливаем цвет иконки в зависимости от статуса
        if currentStatus == "ready" then
          -- Для готового баффа - прозрачный оверлей (никакой подсветки)
          pcall(function() 
            if icon.statusOverlay then
              icon.statusOverlay:SetColor(1, 1, 1, 0) -- Полностью прозрачный
            end
            
            -- Невидимая рамка для готового состояния
            if icon.topBorder then icon.topBorder:SetColor(1, 1, 1, 0) end
            if icon.bottomBorder then icon.bottomBorder:SetColor(1, 1, 1, 0) end
            if icon.leftBorder then icon.leftBorder:SetColor(1, 1, 1, 0) end
            if icon.rightBorder then icon.rightBorder:SetColor(1, 1, 1, 0) end
            
            -- Также возвращаем нормальный белый цвет иконке
            icon:SetColor(ICON_COLORS.READY[1], ICON_COLORS.READY[2], ICON_COLORS.READY[3], ICON_COLORS.READY[4])
          end)
        elseif currentStatus == "active" then
          -- Для активного баффа - зеленая подсветка
          pcall(function() 
            if icon.statusOverlay then
              icon.statusOverlay:SetColor(0, 1, 0, 0.3) -- Зеленый полупрозрачный
            end
            
            -- Яркая зеленая рамка для активного состояния
            local borderColor = {0, 1, 0, 0.8} -- Яркий зеленый
            if icon.topBorder then icon.topBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.bottomBorder then icon.bottomBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.leftBorder then icon.leftBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.rightBorder then icon.rightBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            
            -- Также устанавливаем зеленый цвет для иконки
            icon:SetColor(ICON_COLORS.ACTIVE[1], ICON_COLORS.ACTIVE[2], ICON_COLORS.ACTIVE[3], ICON_COLORS.ACTIVE[4])
          end)
        elseif currentStatus == "cooldown" then
          -- Для баффа на кулдауне - красная подсветка
          pcall(function() 
            if icon.statusOverlay then
              icon.statusOverlay:SetColor(1, 0, 0, 0.3) -- Красный полупрозрачный
            end
            
            -- Яркая красная рамка для состояния кулдауна
            local borderColor = {1, 0, 0, 0.8} -- Яркий красный
            if icon.topBorder then icon.topBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.bottomBorder then icon.bottomBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.leftBorder then icon.leftBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.rightBorder then icon.rightBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            
            -- Также устанавливаем красный цвет для иконки
            icon:SetColor(ICON_COLORS.COOLDOWN[1], ICON_COLORS.COOLDOWN[2], ICON_COLORS.COOLDOWN[3], ICON_COLORS.COOLDOWN[4])
          end)
        end
        
        -- Отображаем таймер, если включено
        if icon.timerLabel and settings.player.showTimer then
          pcall(function()
            local timerText = ""
            
            if currentStatus == "active" and buff.fixedTime then
              local remainingActive = buff.timeOfAction - (currentTime - buff.fixedTime)
              if remainingActive > 0 then
                timerText = formatTimerSeconds(remainingActive)
              end
            elseif currentStatus == "cooldown" and buff.fixedTime then
              local remainingCooldown = buff.cooldown - (currentTime - buff.fixedTime)
              if remainingCooldown > 0 then
                timerText = formatTimerSeconds(remainingCooldown)
              end
            end
            
            icon.timerLabel:SetText(timerText)
            
            -- Устанавливаем цвет текста таймера из настроек
            local timerTextColor = settings.player.timerTextColor or {r = 1, g = 1, b = 1, a = 1}
            icon.timerLabel.style:SetColor(timerTextColor.r, timerTextColor.g, timerTextColor.b, timerTextColor.a)
            
            -- Показываем таймер только если есть текст
            icon.timerLabel:Show(timerText ~= "")
            
            -- Показываем фон таймера, если есть текст
            if icon.timerBg then
              icon.timerBg:Show(timerText ~= "")
            end
          end)
        elseif icon.timerLabel then
          pcall(function()
            icon.timerLabel:Show(false)
            if icon.timerBg then
              icon.timerBg:Show(false)
            end
          end)
        end
      end
    end
    
    -- Скрываем лишние иконки
    for i = #activeBuffs + 1, #playerBuffCanvas.buffIcons do
      local icon = playerBuffCanvas.buffIcons[i]
      if icon then
        pcall(function()
          icon:Show(false)
          if icon.nameLabel then icon.nameLabel:Show(false) end
          if icon.timerLabel then icon.timerLabel:Show(false) end
          if icon.timerBg then icon.timerBg:Show(false) end
        end)
      end
    end
    
    -- Обновляем размер холста
    local totalWidth = 0
    pcall(function()
      totalWidth = (#activeBuffs) * settings.player.iconSize + (#activeBuffs - 1) * settings.player.iconSpacing
      totalWidth = math.max(totalWidth, settings.player.iconSize * 2)
      
      -- Устанавливаем новый размер холста
      playerBuffCanvas:SetWidth(totalWidth)
      playerBuffCanvas:SetHeight(settings.player.iconSize * 1.2)
      
      -- Устанавливаем позицию только если холст не перетаскивается
      if playerBuffCanvas.isDragging ~= true then
        playerBuffCanvas:RemoveAllAnchors()
        playerBuffCanvas:AddAnchor("TOPLEFT", "UIParent", settings.player.posX, settings.player.posY)
        
        -- Убедимся, что перетаскивание по-прежнему включено/отключено правильно
        pcall(function()
          if playerBuffCanvas.EnableDrag ~= nil then
            playerBuffCanvas:EnableDrag(not settings.player.lockPositioning)
          end
        end)
      end
      
      if playerBuffCanvas.bg then
        playerBuffCanvas.bg:SetColor(0, 0, 0, 0.4)
      end
      playerBuffCanvas:Show(true)
    end)
  end)
  
  if not status then
    safeLog("Ошибка при обновлении иконок баффов игрока: " .. tostring(err))
  end
end

return CooldawnBuffTracker