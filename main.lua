local api = require("api")
local BuffList = require("CooldawnBuffTracker/buff_helper")
local BuffsToTrack = require("CooldawnBuffTracker/buffs_to_track")
local helpers = require("CooldawnBuffTracker/helpers")
local settingsPage = require("CooldawnBuffTracker/settings_page")
local BuffDebugger = require("CooldawnBuffTracker/buff_debugger")

-- Declare variables for caching buff states (add to the beginning of file after other variables)
local cachedMountBuffs = {}
local cachedPlayerBuffs = {}
local cachedBuffStatus = {}

-- Target tracking variables
local targetBuffCanvas = nil
local targetBuffData = {}
local isTargetCanvasInitialized = false
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
  name = "CooldawnBuffTracker",
  author = "Adfazer & Claude",
  desc = "Addon for tracking buffs",
  version = "1.4.0"
}

-- Simplified logging function that only logs during initialization
local function safeLog(message)
  if api and api.Log and api.Log.Info then
    api.Log:Info(message)
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
local targetCacheCleanupTimer = 0

local ICON_COLORS = {
  READY = {1, 1, 1, 1},          -- White (unchanged)
  ACTIVE = {0.2, 1, 0.2, 1},     -- Brighter green
  COOLDOWN = {1, 0.2, 0.2, 1}    -- Brighter red
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
  local msTime = api.Time:GetUiMsec() or 0
  return msTime / 1000
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
        
        safeLog("[CBT] " .. unitType .. " buff added for tracking: " .. tostring(buffId) .. " (" .. tostring(buffName) .. ")")
      end
    end
  end
end

local function setBuffStatus(buffId, status, currentTime, unitType, remainingTime)
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
  end
  
  local buff = buffDataTable[buffId]
  local oldStatus = buff.status
  
  buff.status = status
  
  if status == "active" then
    -- Если передано оставшееся время баффа, рассчитываем fixedTime на его основе
    if remainingTime and remainingTime > 0 and buff.timeOfAction then
      -- fixedTime = момент когда бафф начал действовать
      -- remainingTime приходит в миллисекундах от API, конвертируем в секунды
      local remainingSeconds = remainingTime / 1000
      -- currentTime - (timeOfAction - remainingSeconds) = когда бафф был активирован
      buff.fixedTime = currentTime - (tonumber(buff.timeOfAction) - remainingSeconds)
    else
      buff.fixedTime = currentTime
    end
  elseif status == "cooldown" and not buff.fixedTime then
    -- Если бафф переходит в состояние кулдауна, но fixedTime не установлено,
    -- устанавливаем текущее время как время начала кулдауна
    buff.fixedTime = currentTime
  end
  
  buff.statusChangeTime = currentTime
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

local function createChildWidgetSafe(parent, widgetType, name, index)
  if not parent then return nil end
  
  local widget = api.Interface:CreateWidget(widgetType, name, parent)
  
  if not widget then
    widget = parent:CreateChildWidget(widgetType, name, index or 0, true)
  end
  
  return widget
end

-- Function to create buff icon
local function addBuffIcon(parent, index, unitType)
  unitType = unitType or "playerpet" -- Use mount by default
  
  local unitSettings = settings[unitType] or settings.playerpet
  
  local icon = CreateItemIconButton("buffIcon_" .. index, parent)
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
  local nameLabel = createChildWidgetSafe(icon, "label", "nameLabel_" .. index)
  if nameLabel then
    nameLabel:SetExtent(unitSettings.iconSize * 2, unitSettings.iconSize/2)
    nameLabel:AddAnchor("CENTER", icon, unitSettings.labelX, unitSettings.labelY)
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
  
  -- Create semi-transparent background for timer (no image, only color)
  local timerBg = createChildWidgetSafe(icon, "window", "timerBg_" .. index)
  if timerBg then
    -- Create semi-transparent color background, not an image
    local bg = timerBg:CreateColorDrawable(0, 0, 0, 0.5, "background")
    timerBg:SetExtent(unitSettings.iconSize, unitSettings.iconSize/2)
    timerBg:AddAnchor("BOTTOM", icon, 0, 0)
    timerBg:Show(false)
  end
  
  -- Create label for timer
  local timerLabel = createChildWidgetSafe(icon, "label", "timerLabel_" .. index)
  timerLabel:SetExtent(unitSettings.iconSize, unitSettings.iconSize/2)
  timerLabel:AddAnchor("CENTER", icon, unitSettings.timerX, unitSettings.timerY)
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
  
  -- Set canvas size
  canvas:SetExtent(settings.playerpet.iconSize * 3, settings.playerpet.iconSize * 1.5)
  
  -- Explicitly set canvas position from settings
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
  
  canvas.buffIcons = {}
  for i = 1, 10 do
    canvas.buffIcons[i] = addBuffIcon(canvas, i, "playerpet")
    
    -- Ensure that the icon has the correct position based on settings
    if canvas.buffIcons[i] then
      canvas.buffIcons[i]:RemoveAllAnchors()
      canvas.buffIcons[i]:SetExtent(settings.playerpet.iconSize, settings.playerpet.iconSize)
      
      -- Explicitly calculate icon position taking into account current interval
      local xPosition = (i-1) * (settings.playerpet.iconSize + settings.playerpet.iconSpacing)
      canvas.buffIcons[i]:AddAnchor("LEFT", canvas, xPosition, 0)
    end
  end
  
  -- Implementation of drag functionality for canvas
  -- Flag to track dragging state
  canvas.isDragging = false
  
  -- Define functions for dragging
  canvas.OnDragStart = function(self, arg)
    -- Check if movement is blocked
    if settings.playerpet.lockPositioning then
      return
    end
    
    self.isDragging = true
    -- Make the background more visible during dragging
    if self.bg then
      self.bg:SetColor(0, 0, 0, 0.6)  -- Higher opacity during dragging
    end
    
    self:StartMoving()
    api.Cursor:ClearCursor()
    api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
  end
  
  canvas.OnDragStop = function(self)
    -- Check if movement is blocked
    if settings.playerpet.lockPositioning then
      return
    end
    
    self:StopMovingOrSizing()
    -- Return to normal opacity after dragging
    if self.bg then
      self.bg:SetColor(0, 0, 0, 0.4)
    end
    
    local x, y = self:GetOffset()
    settings.playerpet.posX = x
    settings.playerpet.posY = y
    
    -- Update fields in settings window if it's open
    if settingsPage and settingsPage.updatePositionFields then
      settingsPage.updatePositionFields(x, y)
    end
    
    -- Save settings through helpers
    if helpers and helpers.updateSettings then
      helpers.updateSettings()
    end
    
    self.isDragging = false
    api.Cursor:ClearCursor()
  end
  
  -- Set event handlers for dragging
  canvas:SetHandler("OnDragStart", canvas.OnDragStart)
  canvas:SetHandler("OnDragStop", canvas.OnDragStop)
  
  -- Register dragging with left mouse button
  if canvas.RegisterForDrag ~= nil then
    canvas:RegisterForDrag("LeftButton")
  end
  
  -- Enable/disable dragging based on settings
  if canvas.EnableDrag ~= nil then
    canvas:EnableDrag(not settings.playerpet.lockPositioning)
  end
  
  return canvas
end

-- Create new function for player buff canvas creation
local function createPlayerBuffCanvas()
  local canvas = api.Interface:CreateEmptyWindow("PlayerBuffCanvas")
  if not canvas then
    return nil
  end
  
  -- Set canvas size
  canvas:SetExtent(settings.player.iconSize * 3, settings.player.iconSize * 1.5)
  
  -- Explicitly set canvas position from settings
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
  
  canvas.buffIcons = {}
  for i = 1, 10 do
    canvas.buffIcons[i] = addBuffIcon(canvas, i, "player")
    
    -- Ensure that the icon has the correct position based on settings
    if canvas.buffIcons[i] then
      canvas.buffIcons[i]:RemoveAllAnchors()
      canvas.buffIcons[i]:SetExtent(settings.player.iconSize, settings.player.iconSize)
      
      -- Explicitly calculate icon position taking into account current interval
      local xPosition = (i-1) * (settings.player.iconSize + settings.player.iconSpacing)
      canvas.buffIcons[i]:AddAnchor("LEFT", canvas, xPosition, 0)
    end
  end
  
  -- Implementation of drag functionality for canvas
  -- Flag to track dragging state
  canvas.isDragging = false
  
  -- Define functions for dragging
  canvas.OnDragStart = function(self, arg)
    -- Check if movement is blocked
    if settings.player.lockPositioning then
      return
    end
    
    self.isDragging = true
    -- Make the background more visible during dragging
    if self.bg then
      self.bg:SetColor(0, 0, 0, 0.6)  -- Higher opacity during dragging
    end
    
    self:StartMoving()
    api.Cursor:ClearCursor()
    api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
  end
  
  canvas.OnDragStop = function(self)
    -- Check if movement is blocked
    if settings.player.lockPositioning then
      return
    end
    
    self:StopMovingOrSizing()
    -- Return to normal opacity after dragging
    if self.bg then
      self.bg:SetColor(0, 0, 0, 0.4)
    end
    
    local x, y = self:GetOffset()
    settings.player.posX = x
    settings.player.posY = y
    
    -- Update fields in settings window if it's open
    if settingsPage and settingsPage.updatePositionFields then
      settingsPage.updatePositionFields(x, y)
    end
    
    -- Save settings through helpers
    if helpers and helpers.updateSettings then
      helpers.updateSettings()
    end
    
    self.isDragging = false
    api.Cursor:ClearCursor()
  end
  
  -- Set event handlers for dragging
  canvas:SetHandler("OnDragStart", canvas.OnDragStart)
  canvas:SetHandler("OnDragStop", canvas.OnDragStop)
  
  -- Register dragging with left mouse button
  if canvas.RegisterForDrag ~= nil then
    canvas:RegisterForDrag("LeftButton")
  end
  
  -- Enable/disable dragging based on settings
  if canvas.EnableDrag ~= nil then
    canvas:EnableDrag(not settings.player.lockPositioning)
  end
  
  return canvas
end

-- Create target buff canvas
local function createTargetBuffCanvas()
  local canvas = api.Interface:CreateEmptyWindow("TargetBuffCanvas")
  if not canvas then
    return nil
  end
  
  -- Set canvas size
  canvas:SetExtent(settings.target.iconSize * 3, settings.target.iconSize * 1.5)
  
  -- Explicitly set canvas position from settings
  canvas:RemoveAllAnchors()
  canvas:AddAnchor("TOPLEFT", "UIParent", settings.target.posX, settings.target.posY)
  
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
  canvas.unitType = "target"
  
  canvas.buffIcons = {}
  for i = 1, 10 do
    canvas.buffIcons[i] = addBuffIcon(canvas, i, "target")
    
    if canvas.buffIcons[i] then
      canvas.buffIcons[i]:RemoveAllAnchors()
      canvas.buffIcons[i]:SetExtent(settings.target.iconSize, settings.target.iconSize)
      
      local xPosition = (i-1) * (settings.target.iconSize + settings.target.iconSpacing)
      canvas.buffIcons[i]:AddAnchor("LEFT", canvas, xPosition, 0)
    end
  end
  
  -- Implementation of drag functionality
  canvas.isDragging = false
  
  canvas.OnDragStart = function(self, arg)
    if settings.target.lockPositioning then
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
    if settings.target.lockPositioning then
      return
    end
    
    self:StopMovingOrSizing()
    if self.bg then
      self.bg:SetColor(0, 0, 0, 0.4)
    end
    
    local x, y = self:GetOffset()
    settings.target.posX = x
    settings.target.posY = y
    
    if settingsPage and settingsPage.updatePositionFields then
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
    canvas:EnableDrag(not settings.target.lockPositioning)
  end
  
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
    safeLog("[CBT] Target cache cleaned: " .. tostring(targetId))
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

local function updateBuffIcons(unitType)
  unitType = unitType or "playerpet"  -- По умолчанию используем mount
  
  local canvas, isCanvasInit, buffDataTable
  
  if unitType == "target" then
    canvas = targetBuffCanvas
    isCanvasInit = isTargetCanvasInitialized
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
    canvas = playerBuffCanvas
    isCanvasInit = isPlayerCanvasInitialized
    buffDataTable = playerBuffData
  else
    canvas = buffCanvas
    isCanvasInit = isCanvasInitialized
    buffDataTable = buffData
  end
  
  if not canvas or not isCanvasInit then return end
  
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
          canvas:Show(false)
          return
        end
        
        activeBuffs = historyActiveBuffs
      else
        canvas:Show(false)
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
        canvas:Show(false)
        return
      end
      
      activeBuffs = historyActiveBuffs
    end
  end
  
  -- Если нет баффов для отслеживания, скрываем canvas
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
          canvas:Show(false)
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
          canvas:Show(false)
          return
        end
      else
        -- Timeout expired
        canvas:Show(false)
        lastDisplayedTargetId = nil
        lastTargetLostTime = nil
        cachedTargetDisplayData = {}
        return
      end
    else
      canvas:Show(false)
      return
    end
  end
  
  -- Обновляем все иконки и скрываем неиспользуемые
  for i, icon in ipairs(canvas.buffIcons or {}) do
    if icon and icon.Show then
      -- Показываем и настраиваем только иконки, которые используются
      if i <= #activeBuffs then
        local buffInfo = activeBuffs[i]
        local buffId = buffInfo.id
        local buff = buffInfo.buff
        
        -- Обновляем размер иконки согласно текущим настройкам
        icon:SetExtent(settings[unitType].iconSize, settings[unitType].iconSize)
        
        -- Пересчитываем позицию на основе текущего интервала
        icon:RemoveAllAnchors()
        local xPosition = (i-1) * (settings[unitType].iconSize + settings[unitType].iconSpacing)
        icon:AddAnchor("LEFT", canvas, xPosition, 0)
        
        -- Устанавливаем изображение для иконки
        F_SLOT.SetIconBackGround(icon, buff.icon)
        
        -- Явно устанавливаем иконку видимой
        icon:Show(true)
        
        -- Сохраняем ID баффа для использования в обработчиках событий и отладчике
        icon.buffId = buffId
        
        -- Добавляем debug ID для отладчика баффов
        if BuffDebugger and BuffDebugger.SetBuffIdForIcon then
          BuffDebugger.SetBuffIdForIcon(icon, buffId, unitType)
        end
        
        -- Отображаем имя баффа, если включено в настройках
        if icon.nameLabel and settings[unitType].showLabel then
          -- Обновляем размер шрифта метки на основе текущих настроек
          icon.nameLabel.style:SetFontSize(settings[unitType].labelFontSize or 14)
          
          -- Обновляем позицию метки на основе текущих настроек
          icon.nameLabel:RemoveAllAnchors()
          icon.nameLabel:AddAnchor("CENTER", icon, settings[unitType].labelX or 0, settings[unitType].labelY or -30)
          
          -- Обновляем цвет текста метки из настроек
          local labelTextColor = settings[unitType].labelTextColor or {r = 1, g = 1, b = 1, a = 1}
          icon.nameLabel.style:SetColor(labelTextColor.r, labelTextColor.g, labelTextColor.b, labelTextColor.a)
          
          icon.nameLabel:SetText(buff.name or "")
          icon.nameLabel:Show(true)
        elseif icon.nameLabel then
          icon.nameLabel:Show(false)
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
        
        -- Отображаем таймер, если включено в настройках
        if icon.timerLabel and settings[unitType].showTimer then
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
          
          -- Обновляем размер шрифта таймера на основе текущих настроек
          icon.timerLabel.style:SetFontSize(settings[unitType].timerFontSize or 16)
          
          -- Обновляем позицию таймера на основе текущих настроек
          icon.timerLabel:RemoveAllAnchors()
          icon.timerLabel:AddAnchor("CENTER", icon, settings[unitType].timerX or 0, settings[unitType].timerY or 0)
          
          icon.timerLabel:SetText(timerText)
          
          -- Устанавливаем цвет текста таймера из настроек
          local timerTextColor = settings[unitType].timerTextColor or {r = 1, g = 1, b = 1, a = 1}
          
          -- Добавляем проверку на nil для каждого компонента цвета
          local r = (timerTextColor and timerTextColor.r) or 1
          local g = (timerTextColor and timerTextColor.g) or 1
          local b = (timerTextColor and timerTextColor.b) or 1
          local a = (timerTextColor and timerTextColor.a) or 1
          
          icon.timerLabel.style:SetColor(r, g, b, a)
          
          -- Показываем таймер только если есть текст
          icon.timerLabel:Show(timerText ~= "")
          
          -- Показываем фон таймера, если есть текст
          if icon.timerBg then
            -- Обновляем размер фона таймера
            icon.timerBg:SetExtent(settings[unitType].iconSize, settings[unitType].iconSize/2)
            icon.timerBg:RemoveAllAnchors()
            icon.timerBg:AddAnchor("BOTTOM", icon, 0, 0)
            
            icon.timerBg:Show(timerText ~= "")
          end
        elseif icon.timerLabel then
          icon.timerLabel:Show(false)
          if icon.timerBg then
            icon.timerBg:Show(false)
          end
        end
      else
        -- Скрываем неиспользуемые иконки
        icon:Show(false)
        if icon.nameLabel then icon.nameLabel:Show(false) end
        if icon.timerLabel then icon.timerLabel:Show(false) end
        if icon.timerBg then icon.timerBg:Show(false) end
      end
    end
  end
  
  -- Обновляем размер canvas
  local totalWidth = (#activeBuffs) * settings[unitType].iconSize + (#activeBuffs - 1) * settings[unitType].iconSpacing
  totalWidth = math.max(totalWidth, settings[unitType].iconSize * 2)
  
  -- Устанавливаем новый размер canvas
  canvas:SetWidth(totalWidth)
  canvas:SetHeight(settings[unitType].iconSize * 1.2)
  
  -- Устанавливаем позицию только если canvas не перетаскивается
  if canvas.isDragging ~= true then
    canvas:RemoveAllAnchors()
    canvas:AddAnchor("TOPLEFT", "UIParent", settings[unitType].posX, settings[unitType].posY)
    
    -- Убеждаемся, что перетаскивание все еще правильно включено/выключено
    if canvas.EnableDrag ~= nil then
      canvas:EnableDrag(not settings[unitType].lockPositioning)
    end
  end
  
  if canvas.bg then
    canvas.bg:SetColor(0, 0, 0, 0.4)
  end
  canvas:Show(true)
end

local function checkBuffs(unitType)
  unitType = unitType or "playerpet"  -- По умолчанию работаем с маунтом
  
  -- Определяем, какие переменные использовать в зависимости от типа юнита
  local unitSettings = settings[unitType]
  local buffDataTable, canvas, isCanvasInit
  
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
          canvas = targetBuffCanvas
          isCanvasInit = isTargetCanvasInitialized
          
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
          if isCanvasInit and canvas then
            updateBuffIcons("target")
          end
          return
        else
          -- Timeout expired, hide canvas and clear cached data
          lastDisplayedTargetId = nil
          lastTargetLostTime = nil
          cachedTargetDisplayData = {}
          if targetBuffCanvas then
            targetBuffCanvas:Show(false)
          end
          return
        end
      else
        -- No cached data, hide canvas
        if targetBuffCanvas then
          targetBuffCanvas:Show(false)
        end
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
        status = buffInfo.status
      }
    end
    
    buffDataTable = targetBuffData
    canvas = targetBuffCanvas
    isCanvasInit = isTargetCanvasInitialized
  elseif unitType == "player" then
    buffDataTable = playerBuffData
    canvas = playerBuffCanvas
    isCanvasInit = isPlayerCanvasInitialized
  else
    buffDataTable = buffData
    canvas = buffCanvas
    isCanvasInit = isCanvasInitialized
  end
  
  -- Скрываем окно, если аддон отключен в настройках
  if not unitSettings.enabled then
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
  -- Получаем все активные баффы на юните
  local buffCount = api.Unit:UnitBuffCount(unitType) or 0
  for i = 1, buffCount do
    local buff = api.Unit:UnitBuff(unitType, i)
    
    -- Проверяем, существует ли бафф и есть ли у него идентификатор
    if buff and buff.buff_id then
      buff.buff_id = helpers.formatBuffId(buff.buff_id)
      -- Записываем текущие ID баффов для последующего сравнения
      currentBuffsOnUnit[buff.buff_id] = true
      
      -- Проверяем, нужно ли отслеживать этот бафф
      if BuffsToTrack.ShouldTrackBuff(buff.buff_id, unitType) then
        activeBuffsOnUnit[buff.buff_id] = true
        
        -- Для target: обновляем fixedTime только если timeLeft значительный (> 500мс)
        -- Это предотвращает "мерцание" в последний момент бафа
        -- Для player/playerpet: только при первой активации, без timeLeft
        local isNewBuff = not buffDataTable[buff.buff_id] or (buffDataTable[buff.buff_id].status ~= "active")
        local shouldUpdateTarget = unitType == "target" and buff.timeLeft and buff.timeLeft > 500
        
        if isNewBuff or shouldUpdateTarget then
          -- Бафф стал активным, обновляем его статус
          -- Для target передаём timeLeft (API возвращает время в мс)
          -- Для player/playerpet - nil, чтобы fixedTime = currentTime
          local timeLeftParam = (unitType == "target") and buff.timeLeft or nil
          setBuffStatus(buff.buff_id, "active", getCurrentTime(), unitType, timeLeftParam)
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
      end
    end
  end
  
  -- Проверяем активные дебаффы на игроке и цели
  if unitType == "player" or unitType == "target" then
    -- Получаем все активные дебаффы на юните
    local debuffCount = api.Unit:UnitDeBuffCount(unitType) or 0
    for i = 1, debuffCount do
      local debuff = api.Unit:UnitDeBuff(unitType, i)
      
      -- Проверяем, существует ли дебафф и есть ли у него идентификатор
      if debuff and debuff.buff_id then
        debuff.buff_id = helpers.formatBuffId(debuff.buff_id)
        -- Записываем текущие ID дебаффов для последующего сравнения
        currentBuffsOnUnit[debuff.buff_id] = true
        
        -- Проверяем, нужно ли отслеживать этот дебафф
        if BuffsToTrack.ShouldTrackBuff(debuff.buff_id, unitType) then
          activeBuffsOnUnit[debuff.buff_id] = true
          
          -- Для target: обновляем только если timeLeft значительный (> 500мс)
          -- Для player: только при первой активации
          local isNewDebuff = not buffDataTable[debuff.buff_id] or (buffDataTable[debuff.buff_id].status ~= "active")
          local shouldUpdateTarget = unitType == "target" and debuff.timeLeft and debuff.timeLeft > 500
          
          if isNewDebuff or shouldUpdateTarget then
            -- Дебафф стал активным, обновляем его статус
            -- Для target передаём timeLeft, для player - nil
            local timeLeftParam = (unitType == "target") and debuff.timeLeft or nil
          setBuffStatus(debuff.buff_id, "active", getCurrentTime(), unitType, timeLeftParam)
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
  
  -- Проверяем баффы, которые были активны, но больше не существуют
  local currentTime = tonumber(getCurrentTime()) or 0
  
  for buffId, buffInfo in pairs(buffDataTable) do
    local oldStatus = buffInfo.status
    
    if currentBuffsOnUnit[buffId] then
      -- Бафф активен на юните, ничего делать не нужно
      if buffInfo.status ~= "active" then
        setBuffStatus(buffId, "active", currentTime, unitType)
        hasChanges = true
        
        -- Обновляем кэшированный статус
        cachedBuffStatus[buffId] = "active"
      end
    else
      -- Если баффа больше нет на юните
      if buffInfo.fixedTime then
        local expectedStatus = checkBuffStatus(buffInfo, currentTime)
        
        if expectedStatus ~= buffInfo.status then
          setBuffStatus(buffId, expectedStatus, currentTime, unitType)
          hasChanges = true
          
          -- Обновляем кэшированный статус
          cachedBuffStatus[buffId] = expectedStatus
        end
      elseif buffInfo.status ~= "ready" then
        setBuffStatus(buffId, "ready", nil, unitType)
        hasChanges = true
        
        -- Обновляем кэшированный статус
        cachedBuffStatus[buffId] = "ready"
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
    local canvasJustCreated = false
    
    if unitType == "player" and not isPlayerCanvasInitialized then
      playerBuffCanvas = createPlayerBuffCanvas()
      isPlayerCanvasInitialized = true
      canvasJustCreated = true
    elseif unitType == "playerpet" and not isCanvasInitialized then
      buffCanvas = createBuffCanvas()
      isCanvasInitialized = true
      canvasJustCreated = true
    elseif unitType == "target" and not isTargetCanvasInitialized then
      targetBuffCanvas = createTargetBuffCanvas()
      isTargetCanvasInitialized = true
      canvasJustCreated = true
    end
    
    -- For target, update cache and display data after processing
    if unitType == "target" and currentTargetId then
      -- Update cache with current buff states
      if targetCache[currentTargetId] then
        targetCache[currentTargetId].buffStates = {}
        for buffId, buffInfo in pairs(targetBuffData) do
          targetCache[currentTargetId].buffStates[buffId] = {
            fixedTime = buffInfo.fixedTime,
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

local function OnUpdate(dt)
  updateTimer = updateTimer + dt
  if updateTimer >= updateInterval then
    checkBuffs("playerpet")  -- Проверяем баффы маунта
    checkBuffs("player")     -- Проверяем баффы игрока
    checkBuffs("target")     -- Проверяем баффы target
    updateTimer = 0
  end
  
  refreshUITimer = refreshUITimer + dt
  if refreshUITimer >= refreshUIInterval then
    if isCanvasInitialized then
      updateBuffIcons("playerpet")
    end
    if isPlayerCanvasInitialized then
      updateBuffIcons("player")
    end
    if isTargetCanvasInitialized then
      updateBuffIcons("target")
    end
    
    -- Обновляем отладчик баффов, если он существует
    if BuffDebugger and BuffDebugger.Update then
      BuffDebugger.Update({
        playerCanvas = playerBuffCanvas,
        mountCanvas = buffCanvas,
        targetCanvas = targetBuffCanvas,
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
  -- Проверяем необходимость отображения каждого из канвасов
  -- Note: target canvas should NOT be created at initialization - only when target exists
  local unitTypes = {"playerpet", "player"}  -- Removed "target" from initialization
  
  for _, unitType in ipairs(unitTypes) do
    local shouldShowUI = hasTrackedBuffs(unitType)
    safeLog("[CBT] UI initialization for " .. unitType .. ": " .. (shouldShowUI and "show" or "hide"))
    
    if shouldShowUI then
      local canvasCreator
      if unitType == "player" then
        canvasCreator = createPlayerBuffCanvas
      else
        canvasCreator = createBuffCanvas
      end
      
      local result = canvasCreator()
      if result then
        if unitType == "player" then
          playerBuffCanvas = result
          isPlayerCanvasInitialized = true
          updateBuffIcons("player")
        else
          buffCanvas = result
          isCanvasInitialized = true
          updateBuffIcons("playerpet")
        end
      else
        safeLog("[CBT] Error creating canvas for " .. unitType)
        
        -- Повторная попытка создания канваса с задержкой
        api:DoIn(1000, function()
          local retryResult = canvasCreator()
          if retryResult then
            if unitType == "player" then
              playerBuffCanvas = retryResult
              isPlayerCanvasInitialized = true
              updateBuffIcons("player")
            else
              buffCanvas = retryResult
              isCanvasInitialized = true
              updateBuffIcons("playerpet")
            end
          else
            safeLog("[CBT] Repeated error creating canvas for " .. unitType)
          end
        end)
      end
    end
  end
end

local function OnLoad()
  -- Загружаем настройки
  if helpers then
    settings = helpers.getSettings(buffCanvas, playerBuffCanvas, targetBuffCanvas)
  else
    safeLog("[CBT] Helpers module not loaded, using basic settings")
    settings = {
      playerpet = {
        posX = defaultPositionX,
        posY = defaultPositionY,
        iconSize = iconSize,
        iconSpacing = iconSpacing,
        enabled = true,
        lockPositioning = false
      },
      player = {
        posX = defaultPositionX,
        posY = defaultPositionY + 70,  -- Slightly lower than mount
        iconSize = iconSize,
        iconSpacing = iconSpacing,
        enabled = true,
        lockPositioning = false
      }
    }
  end
  
  -- Инициализация модуля отладки баффов
  if BuffDebugger and BuffDebugger.Initialize then
    BuffDebugger.Initialize({
      playerCanvas = playerBuffCanvas,
      mountCanvas = buffCanvas,
      settings = settings
    })
  end
  
  -- Инициализируем данные баффов
  initBuffData()

  safeLog("[CBT] Loading CooldawnBuffTracker " .. CooldawnBuffTracker.version .. " by " .. CooldawnBuffTracker.author)
  
  -- Проверяем корректность настроек и мигрируем в новую структуру при необходимости
  if not settings.playerpet then
    
    -- Создаем структуру для playerpet
    settings.playerpet = {
      posX = settings.posX or defaultPositionX,
      posY = settings.posY or defaultPositionY,
      iconSize = settings.iconSize or iconSize,
      iconSpacing = settings.iconSpacing or 5,
      lockPositioning = settings.lockPositioning or false,
      enabled = settings.enabled ~= false, -- Enabled by default
      timerTextColor = settings.timerTextColor or {r = 1, g = 1, b = 1, a = 1},
      labelTextColor = settings.labelTextColor or {r = 1, g = 1, b = 1, a = 1},
      showLabel = settings.showLabel or false,
      labelFontSize = settings.labelFontSize or 14,
      labelX = settings.labelX or 0,
      labelY = settings.labelY or -30,
      showTimer = settings.showTimer ~= false, -- Enabled by default
      timerFontSize = settings.timerFontSize or 16,
      timerX = settings.timerX or 0,
      timerY = settings.timerY or 0,
      trackedBuffs = settings.trackedBuffs or {}
    }
    
    -- Создаем структуру для player
    settings.player = {
      posX = settings.posX or defaultPositionX,
      posY = (settings.posY or defaultPositionY) + 70, -- Slightly below the mount
      iconSize = settings.iconSize or iconSize,
      iconSpacing = settings.iconSpacing or 5,
      lockPositioning = settings.lockPositioning or false,
      enabled = true, -- Enabled by default
      timerTextColor = settings.timerTextColor or {r = 1, g = 1, b = 1, a = 1},
      labelTextColor = settings.labelTextColor or {r = 1, g = 1, b = 1, a = 1},
      showLabel = settings.showLabel or false,
      labelFontSize = settings.labelFontSize or 14,
      labelX = settings.labelX or 0,
      labelY = settings.labelY or -30,
      showTimer = settings.showTimer ~= false, -- Enabled by default
      timerFontSize = settings.timerFontSize or 16,
      timerX = settings.timerX or 0,
      timerY = settings.timerY or 0,
      trackedBuffs = {}
    }
    
    -- Создаем структуру для target
    settings.target = {
      posX = settings.posX or defaultPositionX,
      posY = (settings.posY or defaultPositionY) + 140, -- Below the player
      iconSize = settings.iconSize or iconSize,
      iconSpacing = settings.iconSpacing or 5,
      lockPositioning = settings.lockPositioning or false,
      enabled = true, -- Enabled by default
      timerTextColor = settings.timerTextColor or {r = 1, g = 1, b = 1, a = 1},
      labelTextColor = settings.labelTextColor or {r = 1, g = 1, b = 1, a = 1},
      showLabel = settings.showLabel or false,
      labelFontSize = settings.labelFontSize or 14,
      labelX = settings.labelX or 0,
      labelY = settings.labelY or -30,
      showTimer = settings.showTimer ~= false, -- Enabled by default
      timerFontSize = settings.timerFontSize or 16,
      timerX = settings.timerX or 0,
      timerY = settings.timerY or 0,
      trackedBuffs = {},
      cacheTimeout = 300 -- 5 minutes in seconds
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
    
    safeLog("[CBT] Settings migrated to new structure with separation for playerpet and player")
  end
  
  -- Проверяем корректность настроек
  if settings.iconSize == nil then
    safeLog("[CBT] Missing iconSize key in settings, setting default value")
    settings.iconSize = iconSize
  end
  
  if settings.iconSpacing == nil then
    safeLog("[CBT] Missing iconSpacing key in settings, setting default value")
    settings.iconSpacing = 5
  end
  
  if settings.posX == nil then
    safeLog("[CBT] Missing posX key in settings, setting default value")
    settings.posX = defaultPositionX
  end
  
  if settings.posY == nil then
    safeLog("[CBT] Missing posY key in settings, setting default value")
    settings.posY = defaultPositionY
  end
  
  -- Инициализируем страницу настроек, если модуль загружен
  if settingsPage and settingsPage.Load then
    settingsPage.Load()
  end
  
  -- Инициализируем UI
  initializeUI()
  
  api.On("UPDATE", OnUpdate)
  
  -- Создаем ассоциацию с обработчиком обновления настроек
  CooldawnBuffTracker.OnSettingsSaved = function()
    -- Полностью пересоздаем UI при изменении настроек
    if helpers then
      settings = helpers.getSettings(buffCanvas, playerBuffCanvas, targetBuffCanvas)
    end
    
    -- Обновляем модуль отладки баффов после изменения настроек
    if BuffDebugger then
      -- Сначала отключаем
      if BuffDebugger.Shutdown then
        BuffDebugger.Shutdown({
          playerCanvas = playerBuffCanvas,
          mountCanvas = buffCanvas
        })
      end
      -- Затем инициализируем заново с новыми настройками
      if BuffDebugger.Initialize then
        BuffDebugger.Initialize({
          playerCanvas = playerBuffCanvas,
          mountCanvas = buffCanvas,
          settings = settings
        })
      end
    end
    
    -- Проверяем необходимость отображения каждого из канвасов
    local unitTypes = {"playerpet", "player", "target"}
    
    for _, unitType in ipairs(unitTypes) do
      local shouldShowUI = hasTrackedBuffs(unitType)
      local canvas, isCanvasInit
      
      if unitType == "target" then
        canvas = targetBuffCanvas
        isCanvasInit = isTargetCanvasInitialized
      elseif unitType == "player" then
        canvas = playerBuffCanvas
        isCanvasInit = isPlayerCanvasInitialized
      else
        canvas = buffCanvas
        isCanvasInit = isCanvasInitialized
      end
      
      -- Если баффов для отслеживания нет, скрываем канвас
      if not shouldShowUI and canvas then
        canvas:Show(false)
      elseif shouldShowUI then
        -- Если баффы существуют, но канвас не создан, создаем его
        if not isCanvasInit then
          local canvasCreator
          if unitType == "target" then
            canvasCreator = createTargetBuffCanvas
          elseif unitType == "player" then
            canvasCreator = createPlayerBuffCanvas
          else
            canvasCreator = createBuffCanvas
          end
          
          local result = canvasCreator()
          if result then
            if unitType == "target" then
              targetBuffCanvas = result
              isTargetCanvasInitialized = true
            elseif unitType == "player" then
              playerBuffCanvas = result
              isPlayerCanvasInitialized = true
            else
              buffCanvas = result
              isCanvasInitialized = true 
            end
          end
        end
        
        -- Обновляем иконки
        updateBuffIcons(unitType)
      end
    end
  end
end

local function OnUnload()
  -- Отключаем обработчик обновления
  api.On("UPDATE", function() end)
  
  -- Отключаем модуль отладки баффов
  if BuffDebugger and BuffDebugger.Shutdown then
    BuffDebugger.Shutdown({
      playerCanvas = playerBuffCanvas,
      mountCanvas = buffCanvas,
      targetCanvas = targetBuffCanvas
    })
  end
  
  -- Очищаем данные
  buffData = {}
  playerBuffData = {}
  targetBuffData = {}
  targetCache = {}
  isCanvasInitialized = false
  isPlayerCanvasInitialized = false
  isTargetCanvasInitialized = false
  
  -- Очищаем канвасы
  local unitTypes = {"playerpet", "player", "target"}
  for _, unitType in ipairs(unitTypes) do
    local canvas
    if unitType == "target" then
      canvas = targetBuffCanvas
    elseif unitType == "player" then
      canvas = playerBuffCanvas
    else
      canvas = buffCanvas
    end
    
    if canvas then
      canvas:Show(false)
      if canvas.ReleaseHandler then
        canvas:ReleaseHandler("OnDragStart")
        canvas:ReleaseHandler("OnDragStop")
      end
    end
    
    -- Обнуляем переменные канвасов
    if unitType == "target" then
      targetBuffCanvas = nil
    elseif unitType == "player" then
      playerBuffCanvas = nil
    else
      buffCanvas = nil
    end
  end
  
  -- Выгружаем страницу настроек, если модуль загружен
  if settingsPage and settingsPage.Unload then
    settingsPage.Unload()
  end
  
  -- Сохраняем настройки через вспомогательные функции
  if helpers and helpers.updateSettings then
    helpers.updateSettings()
  end
end

-- Handler for opening settings window
local function OnSettingToggle()
  if settingsPage and settingsPage.openSettingsWindow then
    settingsPage.openSettingsWindow()
  end
end

CooldawnBuffTracker.OnLoad = OnLoad
CooldawnBuffTracker.OnUnload = OnUnload
CooldawnBuffTracker.OnSettingToggle = OnSettingToggle

-- Also add function SetBorderColor and SetColor for icons if they're not there:
local originalCreateItemIconButton = CreateItemIconButton
if originalCreateItemIconButton then
  CreateItemIconButton = function(name, parent)
    local icon = originalCreateItemIconButton(name, parent)
    if icon and not icon.SetBorderColor then
      icon.SetBorderColor = function(self, r, g, b, a)
        -- Set border color if method is available
        if self.back then
          self.back:SetColor(r, g, b, a)
        end
      end
    end
    -- Add SetColor method if not available
    if icon and not icon.SetColor then
      icon.SetColor = function(self, r, g, b, a)
        -- Set icon color through back element if available
        if self.back and self.back.SetColor then
          self.back:SetColor(r, g, b, a)
        end
      end
    end
    return icon
  end
end

-- Handler for event when tracked buffs list is updated
api.On("MOUNT_BUFF_TRACKER_UPDATE_BUFFS", function()
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
  
  -- Проверяем необходимость отображения каждого из канвасов
  local unitTypes = {"playerpet", "player", "target"}
  
  for _, unitType in ipairs(unitTypes) do
    local shouldShowUI = hasTrackedBuffs(unitType)
    local canvas, isCanvasInit
    
    if unitType == "target" then
      canvas = targetBuffCanvas
      isCanvasInit = isTargetCanvasInitialized
    elseif unitType == "player" then
      canvas = playerBuffCanvas
      isCanvasInit = isPlayerCanvasInitialized
    else
      canvas = buffCanvas
      isCanvasInit = isCanvasInitialized
    end
    
    -- Если баффов для отслеживания нет, скрываем канвас
    if not shouldShowUI and canvas then
      canvas:Show(false)
    elseif shouldShowUI then
      -- Если баффы существуют, но канвас не создан, создаем его
      if not isCanvasInit then
        local canvasCreator
        if unitType == "target" then
          canvasCreator = createTargetBuffCanvas
        elseif unitType == "player" then
          canvasCreator = createPlayerBuffCanvas
        else
          canvasCreator = createBuffCanvas
        end
        
        local result = canvasCreator()
        if result then
          if unitType == "target" then
            targetBuffCanvas = result
            isTargetCanvasInitialized = true
          elseif unitType == "player" then
            playerBuffCanvas = result
            isPlayerCanvasInitialized = true
          else
            buffCanvas = result
            isCanvasInitialized = true 
          end
        end
      end
      
      -- Обновляем иконки
      updateBuffIcons(unitType)
    end
  end
end)

-- Handler for event when buffs list becomes empty
api.On("MOUNT_BUFF_TRACKER_EMPTY_LIST", function(unitType)
  unitType = unitType or "playerpet"
  
  safeLog("[CBT] Received empty buff list event for " .. unitType .. " - forcibly hiding canvas")
  
  local canvas = unitType == "player" and playerBuffCanvas or buffCanvas
  local buffDataTable = unitType == "player" and playerBuffData or buffData
  
  -- Принудительно скрываем канвас
  if canvas then
    canvas:Show(false)
    safeLog("[CBT] Canvas hidden successfully")
  end
  
  -- Для безопасности сбрасываем данные
  for buffId in pairs(buffDataTable) do
    buffDataTable[buffId] = nil
  end
end)

return CooldawnBuffTracker
