local api = require("api")

local UI = {}

-- Константы для UI
UI.ICON_COLORS = {
  READY = {1, 1, 1, 1},          -- Белый
  ACTIVE = {0.2, 1, 0.2, 1},     -- Яркий зеленый
  COOLDOWN = {1, 0.2, 0.2, 1}    -- Яркий красный
}

-- Вспомогательная функция для безопасного создания дочерних виджетов
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

-- Форматирование времени для таймера
function UI.formatTimerSeconds(seconds)
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

-- Функция для создания иконки баффа
function UI.createBuffIcon(parent, index, unitType, unitSettings)
  if not parent or not unitSettings then return nil end
  
  local icon = CreateItemIconButton("buffIcon_" .. index, parent)
  if not icon then return nil end
  
  pcall(function()
    icon:SetExtent(unitSettings.iconSize, unitSettings.iconSize)
    
    -- Явно рассчитываем позицию иконки с учетом текущего интервала
    local xPosition = (index-1) * (unitSettings.iconSize + unitSettings.iconSpacing)
    icon:AddAnchor("LEFT", parent, xPosition, 0)
    
    -- Создаем цветовой оверлей для иконки (будет показывать статус)
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
  
  -- Создаем метку для имени
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
  
  -- Создаем полупрозрачный фон для таймера (без изображения, только цвет)
  local timerBg = createChildWidgetSafe(icon, "window", "timerBg_" .. index)
  if timerBg then
    pcall(function()
      -- Создаем полупрозрачный цветной фон, без изображения
      local bg = timerBg:CreateColorDrawable(0, 0, 0, 0.5, "background")
      timerBg:SetExtent(unitSettings.iconSize, unitSettings.iconSize/2)
      timerBg:AddAnchor("BOTTOM", icon, 0, 0)
      timerBg:Show(false)
    end)
  end
  
  -- Создаем метку для таймера
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

-- Создание канваса для отображения баффов
function UI.createBuffCanvas(settings, unitType)
  unitType = unitType or "playerpet"
  local unitSettings = settings[unitType]
  
  if not unitSettings then return nil end
  
  local canvas = api.Interface:CreateEmptyWindow(unitType == "player" and "PlayerBuffCanvas" or "MountBuffCanvas")
  if not canvas then
    return nil
  end
  
  pcall(function()    
    -- Устанавливаем размер канваса
    canvas:SetExtent(unitSettings.iconSize * 3, unitSettings.iconSize * 1.5)
    
    -- Явно устанавливаем позицию канваса из настроек
    canvas:RemoveAllAnchors()
    canvas:AddAnchor("TOPLEFT", "UIParent", unitSettings.posX, unitSettings.posY)
    
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
    canvas.buffIcons[i] = UI.createBuffIcon(canvas, i, unitType, unitSettings)
    
    -- Убеждаемся, что иконка имеет правильную позицию на основе настроек
    if canvas.buffIcons[i] then
      pcall(function()
        canvas.buffIcons[i]:RemoveAllAnchors()
        canvas.buffIcons[i]:SetExtent(unitSettings.iconSize, unitSettings.iconSize)
        
        -- Явно рассчитываем позицию иконки с учетом текущего интервала
        local xPosition = (i-1) * (unitSettings.iconSize + unitSettings.iconSpacing)
        canvas.buffIcons[i]:AddAnchor("LEFT", canvas, xPosition, 0)
      end)
    end
  end
  
  -- Реализация функциональности перетаскивания для канваса
  pcall(function()
    -- Флаг для отслеживания состояния перетаскивания
    canvas.isDragging = false
    
    -- Определяем функции для перетаскивания
    canvas.OnDragStart = function(self, arg)
      -- Проверяем, заблокировано ли перемещение
      if unitSettings.lockPositioning then
        return
      end
      
      self.isDragging = true
      -- Делаем фон более видимым во время перетаскивания
      if self.bg then
        self.bg:SetColor(0, 0, 0, 0.6)  -- Повышенная непрозрачность при перетаскивании
      end
      
      self:StartMoving()
      api.Cursor:ClearCursor()
      api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
    end
    
    canvas.OnDragStop = function(self)
      -- Проверяем, заблокировано ли перемещение
      if unitSettings.lockPositioning then
        return
      end
      
      self:StopMovingOrSizing()
      -- Возвращаемся к нормальной непрозрачности после перетаскивания
      if self.bg then
        self.bg:SetColor(0, 0, 0, 0.4)
      end
      
      local x, y = self:GetOffset()
      settings[unitType].posX = x
      settings[unitType].posY = y
      
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
    
    -- Устанавливаем обработчики событий для перетаскивания
    canvas:SetHandler("OnDragStart", canvas.OnDragStart)
    canvas:SetHandler("OnDragStop", canvas.OnDragStop)
    
    -- Регистрируем перетаскивание левой кнопкой мыши
    if canvas.RegisterForDrag ~= nil then
      canvas:RegisterForDrag("LeftButton")
    end
    
    -- Включаем/отключаем перетаскивание на основе настроек
    if canvas.EnableDrag ~= nil then
      canvas:EnableDrag(not unitSettings.lockPositioning)
    end
  end)
  
  return canvas
end

-- Обновление иконок баффов
function UI.updateBuffIcons(unitType, settings, buffData, canvas, isCanvasInitialized, BuffsToTrack, BuffList, BuffDebugger, getCurrentTime, checkBuffStatus, playerBuffData)
  unitType = unitType or "playerpet"
  local unitSettings = settings[unitType]
  
  if not unitSettings or not canvas or not isCanvasInitialized then return end
  
  local status, err = pcall(function()
    -- Выбираем подходящую таблицу данных баффов в зависимости от типа юнита
    local buffDataTable = unitType == "player" and playerBuffData or buffData
    
    -- Проверяем, есть ли баффы для отслеживания
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds(unitType)
    if #trackedBuffIds == 0 then
      canvas:Show(false)
      return
    end
    
    -- Создаем упорядоченный список баффов согласно порядку добавления
    local activeBuffs = {}
    for i, buffId in ipairs(trackedBuffIds) do
      if buffDataTable[buffId] then
        table.insert(activeBuffs, {id = buffId, buff = buffDataTable[buffId], order = i})
      end
    end
    
    -- Если нет баффов для отслеживания, скрываем canvas
    if #activeBuffs == 0 then
      canvas:Show(false)
      return
    end
    
    -- Обновляем все иконки и скрываем неиспользуемые
    for i, icon in ipairs(canvas.buffIcons or {}) do
      if icon and icon.Show then
        -- Показываем и настраиваем только иконки, которые используются
        if i <= #activeBuffs then
          local buffInfo = activeBuffs[i]
          local buffId = buffInfo.id
          local buff = buffInfo.buff
          
          pcall(function() 
            -- Обновляем размер иконки согласно текущим настройкам
            pcall(function()
              icon:SetExtent(unitSettings.iconSize, unitSettings.iconSize)
              
              -- Пересчитываем позицию на основе текущего интервала
              icon:RemoveAllAnchors()
              local xPosition = (i-1) * (unitSettings.iconSize + unitSettings.iconSpacing)
              icon:AddAnchor("LEFT", canvas, xPosition, 0)
            end)
            
            -- Устанавливаем изображение для иконки
            pcall(function()
              F_SLOT.SetIconBackGround(icon, buff.icon)
              
              -- Явно устанавливаем иконку видимой
              icon:Show(true)
              
              -- Сохраняем ID баффа для использования в обработчиках событий и отладчике
              icon.buffId = buffId
              
              -- Добавляем debug ID для отладчика баффов
              if BuffDebugger and BuffDebugger.SetBuffIdForIcon then
                pcall(function() 
                  BuffDebugger.SetBuffIdForIcon(icon, buffId, unitType) 
                end)
              end
            end)
            
            -- Отображаем имя баффа, если включено в настройках
            if icon.nameLabel and unitSettings.showLabel then
              pcall(function()
                -- Обновляем размер шрифта метки на основе текущих настроек
                icon.nameLabel.style:SetFontSize(unitSettings.labelFontSize or 14)
                
                -- Обновляем позицию метки на основе текущих настроек
                icon.nameLabel:RemoveAllAnchors()
                icon.nameLabel:AddAnchor("CENTER", icon, unitSettings.labelX or 0, unitSettings.labelY or -30)
                
                -- Обновляем цвет текста метки из настроек
                local labelTextColor = unitSettings.labelTextColor or {r = 1, g = 1, b = 1, a = 1}
                icon.nameLabel.style:SetColor(labelTextColor.r, labelTextColor.g, labelTextColor.b, labelTextColor.a)
                
                icon.nameLabel:SetText(buff.name or "")
                icon.nameLabel:Show(true)
              end)
            elseif icon.nameLabel then
              pcall(function()
                icon.nameLabel:Show(false)
              end)
            end
            
            -- Определяем текущий статус баффа
            local currentTime = tonumber(getCurrentTime()) or 0
            local currentStatus = buff.status
            if buff.fixedTime then
              currentStatus = checkBuffStatus(buff, currentTime)
            end
            
            -- Устанавливаем цвет иконки в зависимости от статуса
            if currentStatus == "ready" then
              -- Для готового баффа - прозрачный оверлей (без подсветки)
              pcall(function()
                if icon.statusOverlay then
                  icon.statusOverlay:SetColor(1, 1, 1, 0) -- Полностью прозрачный
                end
                
                -- Невидимая граница для состояния готовности
                if icon.topBorder then icon.topBorder:SetColor(1, 1, 1, 0) end
                if icon.bottomBorder then icon.bottomBorder:SetColor(1, 1, 1, 0) end
                if icon.leftBorder then icon.leftBorder:SetColor(1, 1, 1, 0) end
                if icon.rightBorder then icon.rightBorder:SetColor(1, 1, 1, 0) end
                
                -- Также восстанавливаем нормальный белый цвет иконки
                icon:SetColor(UI.ICON_COLORS.READY[1], UI.ICON_COLORS.READY[2], UI.ICON_COLORS.READY[3], UI.ICON_COLORS.READY[4])
              end)
            elseif currentStatus == "active" then
              -- Для активного баффа - зеленая подсветка
              pcall(function()
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
                icon:SetColor(UI.ICON_COLORS.ACTIVE[1], UI.ICON_COLORS.ACTIVE[2], UI.ICON_COLORS.ACTIVE[3], UI.ICON_COLORS.ACTIVE[4])
              end)
            elseif currentStatus == "cooldown" then
              -- Для баффа на кулдауне - красная подсветка
              pcall(function()
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
                icon:SetColor(UI.ICON_COLORS.COOLDOWN[1], UI.ICON_COLORS.COOLDOWN[2], UI.ICON_COLORS.COOLDOWN[3], UI.ICON_COLORS.COOLDOWN[4])
              end)
            end
            
            -- Отображаем таймер, если включено в настройках
            if icon.timerLabel and unitSettings.showTimer then
              pcall(function()
                local timerText = ""
                
                if currentStatus == "active" and buff.fixedTime then
                  local remainingActive = buff.timeOfAction - (currentTime - buff.fixedTime)
                  if remainingActive > 0 then
                    timerText = UI.formatTimerSeconds(remainingActive)
                  end
                elseif currentStatus == "cooldown" and buff.fixedTime then
                  local remainingCooldown = buff.cooldown - (currentTime - buff.fixedTime)
                  if remainingCooldown > 0 then
                    timerText = UI.formatTimerSeconds(remainingCooldown)
                  end
                end
                
                -- Обновляем размер шрифта таймера на основе текущих настроек
                icon.timerLabel.style:SetFontSize(unitSettings.timerFontSize or 16)
                
                -- Обновляем позицию таймера на основе текущих настроек
                icon.timerLabel:RemoveAllAnchors()
                icon.timerLabel:AddAnchor("CENTER", icon, unitSettings.timerX or 0, unitSettings.timerY or 0)
                
                icon.timerLabel:SetText(timerText)
                
                -- Устанавливаем цвет текста таймера из настроек
                local timerTextColor = unitSettings.timerTextColor or {r = 1, g = 1, b = 1, a = 1}
                icon.timerLabel.style:SetColor(timerTextColor.r, timerTextColor.g, timerTextColor.b, timerTextColor.a)
                
                -- Показываем таймер только если есть текст
                icon.timerLabel:Show(timerText ~= "")
                
                -- Показываем фон таймера, если есть текст
                if icon.timerBg then
                  pcall(function()
                    -- Обновляем размер фона таймера
                    icon.timerBg:SetExtent(unitSettings.iconSize, unitSettings.iconSize/2)
                    icon.timerBg:RemoveAllAnchors()
                    icon.timerBg:AddAnchor("BOTTOM", icon, 0, 0)
                    
                    icon.timerBg:Show(timerText ~= "")
                  end)
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
          end)
        else
          -- Скрываем неиспользуемые иконки
          pcall(function()
            icon:Show(false)
            if icon.nameLabel then icon.nameLabel:Show(false) end
            if icon.timerLabel then icon.timerLabel:Show(false) end
            if icon.timerBg then icon.timerBg:Show(false) end
          end)
        end
      end
    end
    
    -- Обновляем размер canvas
    local totalWidth = 0
    pcall(function()
      totalWidth = (#activeBuffs) * unitSettings.iconSize + (#activeBuffs - 1) * unitSettings.iconSpacing
      totalWidth = math.max(totalWidth, unitSettings.iconSize * 2)
      
      -- Устанавливаем новый размер canvas
      canvas:SetWidth(totalWidth)
      canvas:SetHeight(unitSettings.iconSize * 1.2)
      
      -- Устанавливаем позицию только если canvas не перетаскивается
      if canvas.isDragging ~= true then
        canvas:RemoveAllAnchors()
        canvas:AddAnchor("TOPLEFT", "UIParent", unitSettings.posX, unitSettings.posY)
        
        -- Убеждаемся, что перетаскивание все еще правильно включено/выключено
        pcall(function()
          if canvas.EnableDrag ~= nil then
            canvas:EnableDrag(not unitSettings.lockPositioning)
          end
        end)
      end
      
      if canvas.bg then
        canvas.bg:SetColor(0, 0, 0, 0.4)
      end
      canvas:Show(true)
    end)
  end)
  
  if not status then
    if api and api.Log and api.Log.Info then
      pcall(function() api.Log:Info("Error updating icons: " .. tostring(err)) end)
    end
  end
end

return UI 