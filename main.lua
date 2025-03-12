local api = require("api")
local BuffList
pcall(function()
  BuffList = require("CooldawnBuffTracker/buff_helper") or require("buff_helper") or require("./buff_helper")
end)

local BuffsToTrack
pcall(function()
  BuffsToTrack = require("CooldawnBuffTracker/buffs_to_track") or require("buffs_to_track") or require("./buffs_to_track")
end)

-- Connect new settings modules
local helpers
pcall(function()
  helpers = require("CooldawnBuffTracker/helpers") or require("helpers") or require("./helpers")
end)

local settingsPage
pcall(function()
  settingsPage = require("CooldawnBuffTracker/settings_page") or require("settings_page") or require("./settings_page")
end)

-- Declare variables for caching buff states (add to the beginning of file after other variables)
local cachedMountBuffs = {}
local cachedPlayerBuffs = {}
local cachedBuffStatus = {}

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
  pcall(function() api.Log:Info("Failed to load buffs_to_track.lua, using settings") end)
end

if not BuffList then
  BuffList = {
    GetBuffName = function(id) return "Buff #" .. id end,
    GetBuffIcon = function(id) return nil end,
    GetBuffCooldown = function(id) return 0 end,
    GetBuffTimeOfAction = function(id) return 0 end
  }
  pcall(function() api.Log:Info("Failed to load buff_helper.lua, using placeholder") end)
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
  local currentTime = 0
  pcall(function()
    local msTime = api.Time:GetUiMsec() or 0
    currentTime = msTime / 1000
  end)
  return currentTime
end

local function initBuffData()
  -- Initialize data for mount (playerpet)
  local trackedMountBuffIds = BuffsToTrack.GetAllTrackedBuffIds("playerpet")
  
  -- Create a table to check existing mount buffs
  local trackedMountBuffsMap = {}
  for _, buffId in ipairs(trackedMountBuffIds) do
    trackedMountBuffsMap[buffId] = true
  end
  
  -- Remove buffs that are no longer tracked from buffData
  for buffId in pairs(buffData) do
    if not trackedMountBuffsMap[buffId] then
      -- If buff is no longer tracked, remove it from data
      buffData[buffId] = nil
      safeLog("Mount buff removed from tracking: " .. tostring(buffId))
    end
  end
  
  -- Add new mount buffs
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
      
      safeLog("Mount buff added for tracking: " .. tostring(buffId) .. " (" .. tostring(buffName) .. ")")
    end
  end
  
  -- Initialize data for player (player)
  local trackedPlayerBuffIds = BuffsToTrack.GetAllTrackedBuffIds("player")
  
  -- Create a table to check existing player buffs
  local trackedPlayerBuffsMap = {}
  for _, buffId in ipairs(trackedPlayerBuffIds) do
    trackedPlayerBuffsMap[buffId] = true
  end
  
  -- Remove buffs that are no longer tracked from playerBuffData
  for buffId in pairs(playerBuffData) do
    if not trackedPlayerBuffsMap[buffId] then
      -- If buff is no longer tracked, remove it from data
      playerBuffData[buffId] = nil
      safeLog("Player buff removed from tracking: " .. tostring(buffId))
    end
  end
  
  -- Add new player buffs
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
      
      safeLog("Player buff added for tracking: " .. tostring(buffId) .. " (" .. tostring(buffName) .. ")")
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
      -- If buff transitions to cooldown, but fixedTime is not set,
      -- set current time as cooldown start time
      buff.fixedTime = currentTime
    end
    
    buff.statusChangeTime = currentTime
  else
    -- Default work with mount
    if not buffData[buffId] then return end
    
    local buff = buffData[buffId]
    local oldStatus = buff.status
    
    buff.status = status
    
    if status == "active" then
      buff.fixedTime = currentTime
    elseif status == "cooldown" and not buff.fixedTime then
      -- If buff transitions to cooldown, but fixedTime is not set,
      -- set current time as cooldown start time
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

-- Function to create buff icon
local function addBuffIcon(parent, index, unitType)
  unitType = unitType or "playerpet" -- Use mount by default
  
  local unitSettings = settings[unitType] or settings.playerpet
  
  local icon = CreateItemIconButton("buffIcon_" .. index, parent)
  if not icon then return nil end
  
  pcall(function()
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
  end)
  
  -- Create label for name
  local nameLabel = createChildWidgetSafe(icon, "label", "nameLabel_" .. index)
  if nameLabel then
    pcall(function()
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
    end)
  end
  
  -- Create semi-transparent background for timer (no image, only color)
  local timerBg = createChildWidgetSafe(icon, "window", "timerBg_" .. index)
  if timerBg then
    pcall(function()
      -- Create semi-transparent color background, not an image
      local bg = timerBg:CreateColorDrawable(0, 0, 0, 0.5, "background")
      timerBg:SetExtent(unitSettings.iconSize, unitSettings.iconSize/2)
      timerBg:AddAnchor("BOTTOM", icon, 0, 0)
      timerBg:Show(false)
    end)
  end
  
  -- Create label for timer
  local timerLabel = createChildWidgetSafe(icon, "label", "timerLabel_" .. index)
  pcall(function()
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
  end)
  
  canvas.buffIcons = {}
  for i = 1, 10 do
    canvas.buffIcons[i] = addBuffIcon(canvas, i, "playerpet")
    
    -- Ensure that the icon has the correct position based on settings
    if canvas.buffIcons[i] then
      pcall(function()
        canvas.buffIcons[i]:RemoveAllAnchors()
        canvas.buffIcons[i]:SetExtent(settings.playerpet.iconSize, settings.playerpet.iconSize)
        
        -- Explicitly calculate icon position taking into account current interval
        local xPosition = (i-1) * (settings.playerpet.iconSize + settings.playerpet.iconSpacing)
        canvas.buffIcons[i]:AddAnchor("LEFT", canvas, xPosition, 0)
      end)
    end
  end
  
  -- Implementation of drag functionality for canvas
  pcall(function()
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
  end)
  
  return canvas
end

-- Create new function for player buff canvas creation
local function createPlayerBuffCanvas()
  local canvas = api.Interface:CreateEmptyWindow("PlayerBuffCanvas")
  if not canvas then
    return nil
  end
  
  pcall(function()    
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
  end)
  
  canvas.buffIcons = {}
  for i = 1, 10 do
    canvas.buffIcons[i] = addBuffIcon(canvas, i, "player")
    
    -- Ensure that the icon has the correct position based on settings
    if canvas.buffIcons[i] then
      pcall(function()
        canvas.buffIcons[i]:RemoveAllAnchors()
        canvas.buffIcons[i]:SetExtent(settings.player.iconSize, settings.player.iconSize)
        
        -- Explicitly calculate icon position taking into account current interval
        local xPosition = (i-1) * (settings.player.iconSize + settings.player.iconSpacing)
        canvas.buffIcons[i]:AddAnchor("LEFT", canvas, xPosition, 0)
      end)
    end
  end
  
  -- Implementation of drag functionality for canvas
  pcall(function()
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
  end)
  
  return canvas
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
  else
    -- If type is not specified, check for buffs of any type
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
    
    -- Check if there are buffs to track
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds("playerpet")
    if #trackedBuffIds == 0 then
      buffCanvas:Show(false)
      return
    end
    
    -- Create an ordered list of buffs according to the order of addition
    local activeBuffs = {}
    for i, buffId in ipairs(trackedBuffIds) do
      if buffData[buffId] then
        table.insert(activeBuffs, {id = buffId, buff = buffData[buffId], order = i})
      end
    end
    
    -- If there are no buffs to track, hide the canvas
    if #activeBuffs == 0 then
      buffCanvas:Show(false)
      return
    end
    
    for i, icon in ipairs(buffCanvas.buffIcons or {}) do
      if icon and icon.Show then
        pcall(function() 
          -- Update size for each icon and position based on interval
          icon:SetExtent(settings.playerpet.iconSize, settings.playerpet.iconSize)
          
          -- Recalculate position based on current interval
          icon:RemoveAllAnchors()
          local xPosition = (i-1) * (settings.playerpet.iconSize + settings.playerpet.iconSpacing)
          icon:AddAnchor("LEFT", buffCanvas, xPosition, 0)
          
          icon:Show(false) 
        end)
      end
    end
    
    -- Get current time for status updates
    local currentTime = tonumber(getCurrentTime()) or 0
    
    -- Update all icons according to current buff list
    for i, buffInfo in ipairs(activeBuffs) do
      local icon = buffCanvas.buffIcons[i]
      if icon then
        local buffId = buffInfo.id
        local buff = buffInfo.buff
        
        pcall(function()
          -- Get icon for buff
          local iconPath = BuffList.GetBuffIcon(buffId) or "icon_default"
          F_SLOT.SetIconBackGround(icon, buff.icon)
          
          -- Explicitly set icon visible
          icon:SetVisible(true)
        end)
        
        -- Save buff ID for use in event handlers
        icon.buffId = buffId
        icon:Show(true)
        
        -- Display buff name if enabled in settings
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
        
        -- Determine current buff status
        local currentStatus = buff.status
        if buff.fixedTime then
          currentStatus = checkBuffStatus(buff, currentTime)
        end
        
        -- Set icon color based on status
        if currentStatus == "ready" then
          -- For ready buff - transparent overlay (no highlight)
          pcall(function() 
            if icon.statusOverlay then
              icon.statusOverlay:SetColor(1, 1, 1, 0) -- Completely transparent
            end
            
            -- Invisible border for ready state
            if icon.topBorder then icon.topBorder:SetColor(1, 1, 1, 0) end
            if icon.bottomBorder then icon.bottomBorder:SetColor(1, 1, 1, 0) end
            if icon.leftBorder then icon.leftBorder:SetColor(1, 1, 1, 0) end
            if icon.rightBorder then icon.rightBorder:SetColor(1, 1, 1, 0) end
            
            -- Also restore normal white color to icon
            icon:SetColor(ICON_COLORS.READY[1], ICON_COLORS.READY[2], ICON_COLORS.READY[3], ICON_COLORS.READY[4])
          end)
        elseif currentStatus == "active" then
          -- For active buff - green highlight
          pcall(function() 
            if icon.statusOverlay then
              icon.statusOverlay:SetColor(0, 1, 0, 0.3) -- Semi-transparent green
            end
            
            -- Bright green border for active state
            local borderColor = {0, 1, 0, 0.8} -- Bright green
            if icon.topBorder then icon.topBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.bottomBorder then icon.bottomBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.leftBorder then icon.leftBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.rightBorder then icon.rightBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            
            -- Also set green color for icon
            icon:SetColor(ICON_COLORS.ACTIVE[1], ICON_COLORS.ACTIVE[2], ICON_COLORS.ACTIVE[3], ICON_COLORS.ACTIVE[4])
          end)
        elseif currentStatus == "cooldown" then
          -- For buff on cooldown - red highlight
          pcall(function() 
            if icon.statusOverlay then
              icon.statusOverlay:SetColor(1, 0, 0, 0.3) -- Semi-transparent red
            end
            
            -- Bright red border for cooldown state
            local borderColor = {1, 0, 0, 0.8} -- Bright red
            if icon.topBorder then icon.topBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.bottomBorder then icon.bottomBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.leftBorder then icon.leftBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.rightBorder then icon.rightBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            
            -- Also set red color for icon
            icon:SetColor(ICON_COLORS.COOLDOWN[1], ICON_COLORS.COOLDOWN[2], ICON_COLORS.COOLDOWN[3], ICON_COLORS.COOLDOWN[4])
          end)
        end
        
        -- Display timer if enabled in settings
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
            
            -- Set timer text color from settings
            local timerTextColor = settings.playerpet.timerTextColor or {r = 1, g = 1, b = 1, a = 1}
            icon.timerLabel.style:SetColor(timerTextColor.r, timerTextColor.g, timerTextColor.b, timerTextColor.a)
            
            -- Show timer only if there is text
            icon.timerLabel:Show(timerText ~= "")
            
            -- Show timer background if there is text
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
    
    -- Hide extra icons
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
    
    -- Update canvas size
    local totalWidth = 0
    pcall(function()
      totalWidth = (#activeBuffs) * settings.playerpet.iconSize + (#activeBuffs - 1) * settings.playerpet.iconSpacing
      totalWidth = math.max(totalWidth, settings.playerpet.iconSize * 2)
      
      -- Set new canvas size
      buffCanvas:SetWidth(totalWidth)
      buffCanvas:SetHeight(settings.playerpet.iconSize * 1.2)
      
      -- Set position only if canvas is not being dragged
      if buffCanvas.isDragging ~= true then
        buffCanvas:RemoveAllAnchors()
        buffCanvas:AddAnchor("TOPLEFT", "UIParent", settings.playerpet.posX, settings.playerpet.posY)
        
        -- Make sure that dragging is still enabled/disabled correctly
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
    safeLog("Error updating icons: " .. tostring(err))
  end
end

local function checkMountBuffs()
  local status, err = pcall(function()
    -- Hide window if addon is disabled in settings
    if not settings.playerpet.enabled then
      if buffCanvas then
        buffCanvas:Show(false)
      end
      return
    end
    
    -- Check if there are buffs to track
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds("playerpet")
    
    -- If the list of tracked buffs is empty, hide the canvas 
    if #trackedBuffIds == 0 then
      if buffCanvas then
        buffCanvas:Show(false)
      end
      return
    end
    
    local activeBuffsOnMount = {}
    local hasChanges = false
    local currentBuffsOnMount = {}
    
    -- Check active buffs on mount
    for i = 1, api.Unit:UnitBuffCount("playerpet") do
      local buff = api.Unit:UnitBuff("playerpet", i)
      
      -- Correct access to buff ID - using buff.buff_id instead of buff.id
      if buff and buff.buff_id then
        -- Record current buff IDs for later comparison
        currentBuffsOnMount[buff.buff_id] = true
        
        -- For debug mode register new mount buffs
        if settings.debugBuffId and not cachedMountBuffs[buff.buff_id] then
          pcall(function()
            api.Log:Info("[CooldawnBuffTracker] New mount buff: " .. tostring(buff.buff_id))
          end)
        end
        
        -- Add only tracked buffs to active buffs
        if BuffsToTrack.ShouldTrackBuff(buff.buff_id) then
          activeBuffsOnMount[buff.buff_id] = true
        end
      end
    end
    
    -- Update cached buffs of mount
    cachedMountBuffs = currentBuffsOnMount
    
    local currentTime = tonumber(getCurrentTime()) or 0
    
    for buffId, buffInfo in pairs(buffData) do
      local oldStatus = buffInfo.status
      
      if activeBuffsOnMount[buffId] then
        if buffInfo.status ~= "active" then
          setBuffStatus(buffId, "active", currentTime, "playerpet")
          hasChanges = true
          
          -- Log only status change for tracked buffs
          if settings.debugBuffId and cachedBuffStatus[buffId] ~= "active" then
            pcall(function()
              api.Log:Info(string.format("[CooldawnBuffTracker] Buff ID %d changed status to: active", buffId))
            end)
          end
          
          -- Update cached status
          cachedBuffStatus[buffId] = "active"
        end
      else
        if buffInfo.fixedTime then
          local expectedStatus = checkBuffStatus(buffInfo, currentTime)
          
          if expectedStatus ~= buffInfo.status then
            setBuffStatus(buffId, expectedStatus, currentTime, "playerpet")
            hasChanges = true
            
            -- Log only status change for tracked buffs
            if settings.debugBuffId and cachedBuffStatus[buffId] ~= expectedStatus then
              pcall(function()
                api.Log:Info(string.format("[CooldawnBuffTracker] Buff ID %d changed status to: %s", buffId, expectedStatus))
              end)
            end
            
            -- Update cached status
            cachedBuffStatus[buffId] = expectedStatus
          end
        elseif buffInfo.status ~= "ready" then
          setBuffStatus(buffId, "ready", nil, "playerpet")
          hasChanges = true
          
          -- Log only status change for tracked buffs
          if settings.debugBuffId and cachedBuffStatus[buffId] ~= "ready" then
            pcall(function()
              api.Log:Info(string.format("[CooldawnBuffTracker] Buff ID %d changed status to: ready", buffId))
            end)
          end
          
          -- Update cached status
          cachedBuffStatus[buffId] = "ready"
        end
      end
    end
    
    -- Check if any buffs have disappeared from mount
    if settings.debugBuffId then
      for buffId in pairs(cachedMountBuffs) do
        if not currentBuffsOnMount[buffId] then
          pcall(function()
            api.Log:Info("[CooldawnBuffTracker] Buff disappeared from mount: " .. tostring(buffId))
          end)
        end
      end
    end
    
    if hasChanges and isCanvasInitialized then
      updateBuffIcons()
    end
  end)
  
  if not status then
    safeLog("Error checking buffs: " .. tostring(err))
  end
end

-- Function to check for player buffs
local function checkPlayerBuffs()
  local status, err = pcall(function()
    -- Hide window if addon is disabled in settings
    if not settings.player.enabled then
      if playerBuffCanvas then
        playerBuffCanvas:Show(false)
      end
      return
    end
    
    -- Check if there are buffs to track
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds("player")
    
    -- If the list of tracked buffs is empty, hide the canvas 
    if #trackedBuffIds == 0 then
      if playerBuffCanvas then
        playerBuffCanvas:Show(false)
      end
      return
    end
    
    local activeBuffsOnPlayer = {}
    local hasChanges = false
    local currentBuffsOnPlayer = {}
    
    -- Check active buffs on player
    pcall(function()
      -- Get all active buffs on player
      local buffCount = api.Unit:UnitBuffCount("player") or 0
      for i = 1, buffCount do
        local buff = api.Unit:UnitBuff("player", i)
        
        -- Check if buff exists and has an identifier
        if buff and buff.buff_id then
          -- Record current buff IDs for later comparison
          currentBuffsOnPlayer[buff.buff_id] = true
          
          -- For debug mode register new player buffs
          if settings.debugBuffId and not cachedPlayerBuffs[buff.buff_id] then
            pcall(function()
              api.Log:Info("[CooldawnBuffTracker] New player buff: " .. tostring(buff.buff_id))
            end)
            cachedPlayerBuffs[buff.buff_id] = true
          end
          
          -- Check if we need to track this buff
          if BuffsToTrack.ShouldTrackBuff(buff.buff_id, "player") then
            -- If the buff is not in data yet or it's not active, update its status
            if not playerBuffData[buff.buff_id] or (playerBuffData[buff.buff_id].status ~= "active") then
              -- Buff became active, update its status
              setBuffStatus(buff.buff_id, "active", getCurrentTime(), "player")
              hasChanges = true
              
              -- Log only status change for tracked buffs
              if settings.debugBuffId then
                pcall(function()
                  api.Log:Info(string.format("[CooldawnBuffTracker] Buff ID %d (player) changed status to: active", buff.buff_id))
                end)
              end
              
              -- Update cached status
              cachedBuffStatus[buff.buff_id] = "active"
            end
          end
        end
      end
    end)
    
    -- Check buffs that were active but are no longer there
    local currentTime = tonumber(getCurrentTime())
    for _, buffId in ipairs(trackedBuffIds) do
      if playerBuffData[buffId] then
        local buffInfo = playerBuffData[buffId]
        
        if currentBuffsOnPlayer[buffId] then
          -- Buff is active on player, nothing to do
        elseif buffInfo.status == "active" then
          -- If the buff was active but is now off - it's on cooldown
          setBuffStatus(buffId, "cooldown", currentTime, "player")
          hasChanges = true
          
          -- Log only status change for tracked buffs
          if settings.debugBuffId and cachedBuffStatus[buffId] ~= "cooldown" then
            pcall(function()
              api.Log:Info(string.format("[CooldawnBuffTracker] Buff ID %d (player) changed status to: cooldown", buffId))
            end)
          end
          
          -- Update cached status
          cachedBuffStatus[buffId] = "cooldown"
        elseif buffInfo.status == "cooldown" then
          -- If the buff is already on cooldown, check if it's over
          local timeSinceLastStatus = currentTime - (buffInfo.statusChangeTime or 0)
          local cooldownTime = BuffList.GetBuffCooldown(buffId) or 0
          
          if cooldownTime > 0 and timeSinceLastStatus >= cooldownTime then
            -- If cooldown time has passed, buff is ready to use again
            setBuffStatus(buffId, "ready", currentTime, "player")
            hasChanges = true
            
            -- Log only status change for tracked buffs
            if settings.debugBuffId and cachedBuffStatus[buffId] ~= "ready" then
              pcall(function()
                api.Log:Info(string.format("[CooldawnBuffTracker] Buff ID %d (player) changed status to: ready", buffId))
              end)
            end
            
            -- Update cached status
            cachedBuffStatus[buffId] = "ready"
          end
        end
      end
    end
    
    -- Show window only if there are tracked buffs and if tracking is allowed in settings
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
          safeLog("Error initializing player buff canvas")
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
    safeLog("Error checking player buffs: " .. tostring(err))
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
  
  -- Load module for working with buffs
  pcall(function()
    BuffsToTrack = require("CooldawnBuffTracker/buffs_to_track") or require("buffs_to_track") or require("./buffs_to_track")
  end)
  
  -- Load module with information about available buffs
  pcall(function()
    BuffList = require("CooldawnBuffTracker/buff_helper") or require("buff_helper") or require("./buff_helper")
  end)
  
  -- Load module for working with helper functions
  pcall(function()
    helpers = require("CooldawnBuffTracker/helpers") or require("helpers") or require("./helpers") 
  end)
  
  -- Load module for settings page
  pcall(function()
    settingsPage = require("CooldawnBuffTracker/settings_page") or require("settings_page") or require("./settings_page")
  end)
  
  if not BuffsToTrack then
    -- If module for working with buffs couldn't be loaded, create a placeholder
    BuffsToTrack = {
      GetAllTrackedBuffIds = function() return {} end,
      ShouldTrackBuff = function(id) return false end
    }
    pcall(function() api.Log:Info("Failed to load buffs_to_track.lua, using placeholder") end)
  end
  
  if not BuffList then
    BuffList = {
      GetBuffName = function(id) return "Buff #" .. id end,
      GetBuffIcon = function(id) return nil end,
      GetBuffCooldown = function(id) return 0 end,
      GetBuffTimeOfAction = function(id) return 0 end
    }
    pcall(function() api.Log:Info("Failed to load buff_helper.lua, using placeholder") end)
  end
  
  -- Load settings if available
  if helpers and helpers.getSettings then
    settings = helpers.getSettings()
  else
    settings = api.GetSettings("CooldawnBuffTracker") or {}
  end
  
  -- Check settings correctness and migrate to new structure if necessary
  if not settings.playerpet then
    -- If there's no playerpet and player separation, create new structure
    local defaultSettings = require("CooldawnBuffTracker/default_settings") or require("default_settings") or require("./default_settings") or {}
    
    -- Create structure for playerpet
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
    
    -- Create structure for player
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
    
    -- Remove old keys
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
    
    -- Save updated settings
    if helpers and helpers.updateSettings then
      helpers.updateSettings(settings)
    else
      api.SaveSettings()
    end
    
    safeLog("Settings migrated to new structure with separation for playerpet and player")
  end
  
  -- Check for presence of debugBuffId key
  if settings.debugBuffId == nil then
    settings.debugBuffId = false
  end
  
  -- Check if settings are correct
  if settings.iconSize == nil then
    safeLog("Missing iconSize key in settings, setting default value")
    settings.iconSize = iconSize
  end
  
  if settings.iconSpacing == nil then
    safeLog("Missing iconSpacing key in settings, setting default value")
    settings.iconSpacing = 5
  end
  
  if settings.posX == nil then
    safeLog("Missing posX key in settings, setting default value")
    settings.posX = defaultPositionX
  end
  
  if settings.posY == nil then
    safeLog("Missing posY key in settings, setting default value")
    settings.posY = defaultPositionY
  end
  
  -- Initialize settings page if module is loaded
  if settingsPage and settingsPage.Load then
    pcall(function() settingsPage.Load() end)
  end
  
  pcall(initBuffData)
  
  -- Check if there are tracked mount buffs when loading
  local shouldShowMountUI = hasTrackedBuffs("playerpet")
  safeLog("Mount UI initialization: " .. (shouldShowMountUI and "show" or "hide"))
  
  -- Check if there are tracked player buffs when loading
  local shouldShowPlayerUI = hasTrackedBuffs("player")
  safeLog("Player UI initialization: " .. (shouldShowPlayerUI and "show" or "hide"))
  
  -- Create canvas for mount if there are tracked buffs
  if shouldShowMountUI then
    local success, result = pcall(createBuffCanvas)
    if success and result then
      buffCanvas = result
      isCanvasInitialized = true
      updateBuffIcons()
    else
      safeLog("Error creating mount buff canvas: " .. tostring(result))
      
      -- Repeat attempt to create canvas with delay
      api:DoIn(1000, function()
        local retrySuccess, retryResult = pcall(createBuffCanvas)
        if retrySuccess and retryResult then
          buffCanvas = retryResult
          isCanvasInitialized = true
          updateBuffIcons()
        else
          safeLog("Repeated error creating mount buff canvas: " .. tostring(retryResult))
        end
      end)
    end
  end
  
  -- Create canvas for player if there are tracked buffs
  if shouldShowPlayerUI then
    local success, result = pcall(createPlayerBuffCanvas)
    if success and result then
      playerBuffCanvas = result
      isPlayerCanvasInitialized = true
      updatePlayerBuffIcons()
    else
      safeLog("Error creating player buff canvas: " .. tostring(result))
      
      -- Repeat attempt to create canvas with delay
      api:DoIn(1000, function()
        local retrySuccess, retryResult = pcall(createPlayerBuffCanvas)
        if retrySuccess and retryResult then
          playerBuffCanvas = retryResult
          isPlayerCanvasInitialized = true
          updatePlayerBuffIcons()
        else
          safeLog("Repeated error creating player buff canvas: " .. tostring(retryResult))
        end
      end)
    end
  end
  
  pcall(function() 
    api.On("UPDATE", OnUpdate)
  end)
  
  -- Create association with settings update handler
  pcall(function()
    CooldawnBuffTracker.OnSettingsSaved = function()
      -- Completely recreate UI when settings change
      if helpers then
        settings = helpers.getSettings(buffCanvas, playerBuffCanvas)
      end
      
      -- Update mount canvas
      local shouldShowMountUI = hasTrackedBuffs("playerpet")
      
      -- If there are no buffs to track, hide mount canvas
      if not shouldShowMountUI and buffCanvas then
        pcall(function() buffCanvas:Show(false) end)
      elseif shouldShowMountUI then
        -- If buffs exist but canvas is not created, create it
        if not isCanvasInitialized then
          local success, result = pcall(createBuffCanvas)
          if success and result then
            buffCanvas = result
            isCanvasInitialized = true
          end
        end
        
        -- Update icons
        if isCanvasInitialized then
          updateBuffIcons()
        end
      end
      
      -- Update player canvas
      local shouldShowPlayerUI = hasTrackedBuffs("player")
      
      -- If there are no buffs to track, hide player canvas
      if not shouldShowPlayerUI and playerBuffCanvas then
        pcall(function() playerBuffCanvas:Show(false) end)
      elseif shouldShowPlayerUI then
        -- If buffs exist but canvas is not created, create it
        if not isPlayerCanvasInitialized then
          local success, result = pcall(createPlayerBuffCanvas)
          if success and result then
            playerBuffCanvas = result
            isPlayerCanvasInitialized = true
          end
        end
        
        -- Update icons
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
  
  -- Unload settings page if module is loaded
  if settingsPage and settingsPage.Unload then
    pcall(function() settingsPage.Unload() end)
  end
  
  -- Save settings through helpers
  if helpers and helpers.updateSettings then
    helpers.updateSettings()
  end
end

-- Handler for opening settings window
local function OnSettingToggle()
  if settingsPage and settingsPage.openSettingsWindow then
    pcall(function() settingsPage.openSettingsWindow() end)
  end
end

CooldawnBuffTracker.OnLoad = OnLoad
CooldawnBuffTracker.OnUnload = OnUnload
CooldawnBuffTracker.OnSettingToggle = OnSettingToggle

-- Also add function SetBorderColor for icons if it's not there:
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

-- Handler for event when tracked buffs list is updated
pcall(function()
  api.On("MOUNT_BUFF_TRACKER_UPDATE_BUFFS", function()
    safeLog("Received buffs list update event")
    
    -- Update buff data (including removing unnecessary ones)
    local oldMountBuffsCount = 0
    for _ in pairs(buffData) do oldMountBuffsCount = oldMountBuffsCount + 1 end
    
    local oldPlayerBuffsCount = 0
    for _ in pairs(playerBuffData) do oldPlayerBuffsCount = oldPlayerBuffsCount + 1 end
    
    -- Initialize buff data
    initBuffData()
    
    -- Count new number of buffs
    local newMountBuffsCount = 0
    for _ in pairs(buffData) do newMountBuffsCount = newMountBuffsCount + 1 end
    
    local newPlayerBuffsCount = 0
    for _ in pairs(playerBuffData) do newPlayerBuffsCount = newPlayerBuffsCount + 1 end
    
    safeLog("Mount buffs list update: was " .. oldMountBuffsCount .. ", now " .. newMountBuffsCount)
    safeLog("Player buffs list update: was " .. oldPlayerBuffsCount .. ", now " .. newPlayerBuffsCount)
    
    -- Check if we need to show mount canvas
    local shouldShowMountUI = hasTrackedBuffs("playerpet")
    
    -- If there are no buffs to track, hide mount canvas
    if not shouldShowMountUI and buffCanvas then
      pcall(function() buffCanvas:Show(false) end)
    elseif shouldShowMountUI then
      -- If buffs exist but canvas is not created, create it
      if not isCanvasInitialized then
        local success, result = pcall(createBuffCanvas)
        if success and result then
          buffCanvas = result
          isCanvasInitialized = true
        end
      end
      
      -- Update icons
      if isCanvasInitialized then
        updateBuffIcons()
      end
    end
    
    -- Check if we need to show player canvas
    local shouldShowPlayerUI = hasTrackedBuffs("player")
    
    -- If there are no buffs to track, hide player canvas
    if not shouldShowPlayerUI and playerBuffCanvas then
      pcall(function() playerBuffCanvas:Show(false) end)
    elseif shouldShowPlayerUI then
      -- If buffs exist but canvas is not created, create it
      if not isPlayerCanvasInitialized then
        local success, result = pcall(createPlayerBuffCanvas)
        if success and result then
          playerBuffCanvas = result
          isPlayerCanvasInitialized = true
        end
      end
      
      -- Update icons
      if isPlayerCanvasInitialized then
        updatePlayerBuffIcons()
      end
    end
  end)
end)

-- Handler for event when buffs list becomes empty
pcall(function()
  api.On("MOUNT_BUFF_TRACKER_EMPTY_LIST", function()
    safeLog("Received event about empty buff list - forcibly hiding canvas")
    
    -- Force hide canvas
    pcall(function()
      if buffCanvas then
        buffCanvas:Show(false)
        safeLog("Canvas hidden successfully")
      end
    end)
    
    -- For safety, reset data
    pcall(function()
      for buffId in pairs(buffData) do
        buffData[buffId] = nil
      end
    end)
  end)
end)

-- Add new function for updating player buff icons
function updatePlayerBuffIcons()
  local status, err = pcall(function()
    if not playerBuffCanvas or not isPlayerCanvasInitialized then return end
    
    -- Check if there are buffs to track
    local trackedBuffIds = BuffsToTrack.GetAllTrackedBuffIds("player")
    if #trackedBuffIds == 0 then
      playerBuffCanvas:Show(false)
      return
    end
    
    -- Create ordered list of buffs in accordance with addition order
    local activeBuffs = {}
    for i, buffId in ipairs(trackedBuffIds) do
      if playerBuffData[buffId] then
        table.insert(activeBuffs, {id = buffId, buff = playerBuffData[buffId], order = i})
      end
    end
    
    -- If there are no buffs to track, hide the canvas
    if #activeBuffs == 0 then
      playerBuffCanvas:Show(false)
      return
    end
    
    -- Sort buffs by order
    table.sort(activeBuffs, function(a, b) return a.order < b.order end)
    
    -- Get current time for status updates
    local currentTime = tonumber(getCurrentTime()) or 0
    
    -- Update all icons in accordance with current buff list
    for i, buffInfo in ipairs(activeBuffs) do
      local icon = playerBuffCanvas.buffIcons[i]
      if icon then
        local buffId = buffInfo.id
        local buff = buffInfo.buff
        
        pcall(function()
          -- Make sure the icon is positioned correctly before displaying
          icon:RemoveAllAnchors()
          local xPosition = (i-1) * (settings.player.iconSize + settings.player.iconSpacing)
          icon:AddAnchor("LEFT", playerBuffCanvas, xPosition, 0)
          
          -- Set icon for buff
          F_SLOT.SetIconBackGround(icon, buff.icon)
          icon:SetVisible(true)
        end)
        
        -- Save buff ID for later use
        icon.buffId = buffId
        icon:Show(true)
        
        -- Display buff name if enabled
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
        
        -- Determine current status of buff
        local currentStatus = "ready"
        
        if buff.fixedTime then
          currentStatus = checkBuffStatus(buff, currentTime)
        else
          currentStatus = buff.status
        end
        
        -- Set icon color based on status
        if currentStatus == "ready" then
          -- For ready buff - transparent overlay (no highlight)
          pcall(function() 
            if icon.statusOverlay then
              icon.statusOverlay:SetColor(1, 1, 1, 0) -- Completely transparent
            end
            
            -- Invisible border for ready state
            if icon.topBorder then icon.topBorder:SetColor(1, 1, 1, 0) end
            if icon.bottomBorder then icon.bottomBorder:SetColor(1, 1, 1, 0) end
            if icon.leftBorder then icon.leftBorder:SetColor(1, 1, 1, 0) end
            if icon.rightBorder then icon.rightBorder:SetColor(1, 1, 1, 0) end
            
            -- Also return normal white color to icon
            icon:SetColor(ICON_COLORS.READY[1], ICON_COLORS.READY[2], ICON_COLORS.READY[3], ICON_COLORS.READY[4])
          end)
        elseif currentStatus == "active" then
          -- For active buff - green highlight
          pcall(function() 
            if icon.statusOverlay then
              icon.statusOverlay:SetColor(0, 1, 0, 0.3) -- Green semi-transparent
            end
            
            -- Bright green border for active state
            local borderColor = {0, 1, 0, 0.8} -- Bright green
            if icon.topBorder then icon.topBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.bottomBorder then icon.bottomBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.leftBorder then icon.leftBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.rightBorder then icon.rightBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            
            -- Also set green color for icon
            icon:SetColor(ICON_COLORS.ACTIVE[1], ICON_COLORS.ACTIVE[2], ICON_COLORS.ACTIVE[3], ICON_COLORS.ACTIVE[4])
          end)
        elseif currentStatus == "cooldown" then
          -- For buff on cooldown - red highlight
          pcall(function() 
            if icon.statusOverlay then
              icon.statusOverlay:SetColor(1, 0, 0, 0.3) -- Red semi-transparent
            end
            
            -- Bright red border for cooldown state
            local borderColor = {1, 0, 0, 0.8} -- Bright red
            if icon.topBorder then icon.topBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.bottomBorder then icon.bottomBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.leftBorder then icon.leftBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            if icon.rightBorder then icon.rightBorder:SetColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
            
            -- Also set red color for icon
            icon:SetColor(ICON_COLORS.COOLDOWN[1], ICON_COLORS.COOLDOWN[2], ICON_COLORS.COOLDOWN[3], ICON_COLORS.COOLDOWN[4])
          end)
        end
        
        -- Display timer if enabled
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
            
            -- Set timer text color from settings
            local timerTextColor = settings.player.timerTextColor or {r = 1, g = 1, b = 1, a = 1}
            icon.timerLabel.style:SetColor(timerTextColor.r, timerTextColor.g, timerTextColor.b, timerTextColor.a)
            
            -- Show timer only if there is text
            icon.timerLabel:Show(timerText ~= "")
            
            -- Show timer background if there is text
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
    
    -- Hide extra icons
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
    
    -- Update canvas size
    local totalWidth = 0
    pcall(function()
      totalWidth = (#activeBuffs) * settings.player.iconSize + (#activeBuffs - 1) * settings.player.iconSpacing
      totalWidth = math.max(totalWidth, settings.player.iconSize * 2)
      
      -- Set new canvas size
      playerBuffCanvas:SetWidth(totalWidth)
      playerBuffCanvas:SetHeight(settings.player.iconSize * 1.2)
      
      -- Set position only if canvas is not being dragged
      if playerBuffCanvas.isDragging ~= true then
        playerBuffCanvas:RemoveAllAnchors()
        playerBuffCanvas:AddAnchor("TOPLEFT", "UIParent", settings.player.posX, settings.player.posY)
        
        -- Make sure that dragging is still enabled/disabled correctly
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
    safeLog("Error updating player buff icons: " .. tostring(err))
  end
end

return CooldawnBuffTracker
