local api = require("api")

-- Модуль фабрики для создания канвасов баффов
local CanvasFactory = {}

-- Цвета состояний иконок
local ICON_COLORS = {
  READY = {1, 1, 1, 1},          -- White (unchanged)
  ACTIVE = {0.2, 1, 0.2, 1},     -- Brighter green
  COOLDOWN = {1, 0.2, 0.2, 1}    -- Brighter red
}

-- Вспомогательная функция для создания дочернего виджета
local function createChildWidgetSafe(parent, widgetType, name, index)
  if not parent then return nil end
  
  local widget = api.Interface:CreateWidget(widgetType, name, parent)
  
  if not widget then
    widget = parent:CreateChildWidget(widgetType, name, index or 0, true)
  end
  
  return widget
end

-- Создание иконки баффа
function CanvasFactory.createBuffIcon(parent, index, unitType, unitSettings)
  unitType = unitType or "playerpet"
  
  local icon = CreateItemIconButton("buffIcon_" .. unitType .. "_" .. index, parent)
  if not icon then return nil end
  
  icon:SetExtent(unitSettings.iconSize, unitSettings.iconSize)
  
  -- Explicitly calculate icon position taking into account current interval
  local xPosition = (index-1) * (unitSettings.iconSize + unitSettings.iconSpacing)
  icon:AddAnchor("LEFT", parent, xPosition, 0)
  
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
  icon.createdWithSize = unitSettings.iconSize
  icon.createdWithSpacing = unitSettings.iconSpacing
  icon.iconIndex = index
  icon.unitType = unitType
  
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
  local nameLabel = createChildWidgetSafe(icon, "label", "nameLabel_" .. unitType .. "_" .. index)
  if nameLabel then
    nameLabel:SetExtent(unitSettings.iconSize * 2, unitSettings.iconSize/2)
    nameLabel:AddAnchor("CENTER", icon, unitSettings.labelX or 0, unitSettings.labelY or -30)
    nameLabel.style:SetFontSize(unitSettings.labelFontSize or 14)
    nameLabel.style:SetAlign(ALIGN.CENTER)
    nameLabel.style:SetShadow(true)
    
    -- Set color from settings
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
  end
  
  -- Create semi-transparent background for timer
  local timerBg = createChildWidgetSafe(icon, "window", "timerBg_" .. unitType .. "_" .. index)
  if timerBg then
    local bg = timerBg:CreateColorDrawable(0, 0, 0, 0.5, "background")
    timerBg:SetExtent(unitSettings.iconSize, unitSettings.iconSize/2)
    timerBg:AddAnchor("BOTTOM", icon, 0, 0)
    timerBg:Show(false)
  end
  
  -- Create label for timer
  local timerLabel = createChildWidgetSafe(icon, "label", "timerLabel_" .. unitType .. "_" .. index)
  if timerLabel then
    timerLabel:SetExtent(unitSettings.iconSize, unitSettings.iconSize/2)
    timerLabel:AddAnchor("CENTER", icon, unitSettings.timerX or 0, unitSettings.timerY or 0)
    timerLabel.style:SetFontSize(unitSettings.timerFontSize or 16)
    timerLabel.style:SetAlign(ALIGN.CENTER)
    timerLabel.style:SetShadow(true)
    
    -- Set color from settings
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
  end
  
  icon.nameLabel = nameLabel
  icon.timerLabel = timerLabel
  icon.timerBg = timerBg
  
  return icon
end

-- Универсальная функция создания канваса для любого типа юнита
-- @param unitType - тип юнита ("playerpet", "player", "target")
-- @param unitSettings - настройки для этого типа юнита
-- @param callbacks - таблица с функциями обратного вызова:
--   callbacks.onDragStop(x, y) - вызывается после перетаскивания
--   callbacks.updatePositionFields(x, y) - обновление полей в настройках
function CanvasFactory.createBuffCanvas(unitType, unitSettings, callbacks)
  callbacks = callbacks or {}
  
  local canvasName = unitType == "playerpet" and "MountBuffCanvas" or 
                     unitType == "player" and "PlayerBuffCanvas" or 
                     "TargetBuffCanvas"
  
  local canvas = api.Interface:CreateEmptyWindow(canvasName)
  if not canvas then
    return nil
  end
  
  -- Set canvas size
  canvas:SetExtent(unitSettings.iconSize * 3, unitSettings.iconSize * 1.5)
  
  -- Explicitly set canvas position from settings
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
  
  -- Store unit type for later use
  canvas.unitType = unitType
  
  -- Create buff icons
  canvas.buffIcons = {}
  for i = 1, 10 do
    canvas.buffIcons[i] = CanvasFactory.createBuffIcon(canvas, i, unitType, unitSettings)
    
    if canvas.buffIcons[i] then
      canvas.buffIcons[i]:RemoveAllAnchors()
      canvas.buffIcons[i]:SetExtent(unitSettings.iconSize, unitSettings.iconSize)
      
      local xPosition = (i-1) * (unitSettings.iconSize + unitSettings.iconSpacing)
      canvas.buffIcons[i]:AddAnchor("LEFT", canvas, xPosition, 0)
    end
  end
  
  -- Implementation of drag functionality
  canvas.isDragging = false
  
  canvas.OnDragStart = function(self, arg)
    if unitSettings.lockPositioning then
      return
    end
    
    self.isDragging = true
    if self.bg then
      self.bg:SetColor(0, 0, 0, 0.6)
    end
    
    self:StartMoving()
    api.Cursor:ClearCursor()
    api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
  end
  
  canvas.OnDragStop = function(self)
    if unitSettings.lockPositioning then
      return
    end
    
    self:StopMovingOrSizing()
    if self.bg then
      self.bg:SetColor(0, 0, 0, 0.4)
    end
    
    local x, y = self:GetOffset()
    unitSettings.posX = x
    unitSettings.posY = y
    
    -- Call callbacks
    if callbacks.updatePositionFields then
      callbacks.updatePositionFields(x, y)
    end
    
    if callbacks.onDragStop then
      callbacks.onDragStop(x, y)
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
    canvas:EnableDrag(not unitSettings.lockPositioning)
  end
  
  return canvas
end

-- Функция обновления состояния иконки
function CanvasFactory.updateIconStatus(icon, status)
  if not icon then return end
  
  if status == "ready" then
    if icon.statusOverlay then
      icon.statusOverlay:SetColor(1, 1, 1, 0)
    end
    
    if icon.topBorder then icon.topBorder:SetColor(1, 1, 1, 0) end
    if icon.bottomBorder then icon.bottomBorder:SetColor(1, 1, 1, 0) end
    if icon.leftBorder then icon.leftBorder:SetColor(1, 1, 1, 0) end
    if icon.rightBorder then icon.rightBorder:SetColor(1, 1, 1, 0) end
    
    icon:SetColor(ICON_COLORS.READY[1], ICON_COLORS.READY[2], ICON_COLORS.READY[3], ICON_COLORS.READY[4])
    
  elseif status == "active" then
    if icon.statusOverlay then
      icon.statusOverlay:SetColor(0, 1, 0, 0.3)
    end
    
    local borderColor = {0, 1, 0, 0.8}
    if icon.topBorder then icon.topBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
    if icon.bottomBorder then icon.bottomBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
    if icon.leftBorder then icon.leftBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
    if icon.rightBorder then icon.rightBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
    
    icon:SetColor(ICON_COLORS.ACTIVE[1], ICON_COLORS.ACTIVE[2], ICON_COLORS.ACTIVE[3], ICON_COLORS.ACTIVE[4])
    
  elseif status == "cooldown" then
    if icon.statusOverlay then
      icon.statusOverlay:SetColor(1, 0, 0, 0.3)
    end
    
    local borderColor = {1, 0, 0, 0.8}
    if icon.topBorder then icon.topBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
    if icon.bottomBorder then icon.bottomBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
    if icon.leftBorder then icon.leftBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
    if icon.rightBorder then icon.rightBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
    
    icon:SetColor(ICON_COLORS.COOLDOWN[1], ICON_COLORS.COOLDOWN[2], ICON_COLORS.COOLDOWN[3], ICON_COLORS.COOLDOWN[4])
  end
end

-- Получение цветов иконок
function CanvasFactory.getIconColors()
  return ICON_COLORS
end

return CanvasFactory

