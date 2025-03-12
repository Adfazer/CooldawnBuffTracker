local api = require("api")
local helpers = require('CooldawnBuffTracker/helpers')

-- Load module for working with buffs
pcall(function()
    BuffsToTrack = require("CooldawnBuffTracker/buffs_to_track") or require("buffs_to_track") or require("./buffs_to_track")
end)

local BuffList
pcall(function()
    BuffList = require("CooldawnBuffTracker/buff_helper") or require("buff_helper") or require("./buff_helper")
end)

-- If failed to load the module for working with buffs, create a placeholder
if not BuffsToTrack then
    BuffsToTrack = {
        GetAllTrackedBuffIds = function() return {} end,
        ShouldTrackBuff = function(id) return false end,
        AddTrackedBuff = function() return false end,
        RemoveTrackedBuff = function() return false end
    }
end

if not BuffList then
    BuffList = {
        GetBuffName = function(id) return "Buff #" .. id end,
        GetBuffIcon = function(id) return nil end
    }
end

local settings, settingsWindow
local settingsControls = {}
local palletWindow
local trackedBuffsList = {} -- For storing buff list widgets
local currentUnitType = "playerpet" -- By default, show settings for mount

local function settingsWindowClose()
    if settingsWindow then
        settingsWindow:Show(false)
        helpers.setSettingsPageOpened(false)
    end
    
    -- Close palette if it's open
    local F_ETC = nil
    F_ETC = require('CooldawnBuffTracker/util/etc') or require('util/etc') or require('./util/etc')
    if F_ETC then
        F_ETC.HidePallet()
    end
end

-- Updates the list of tracked buffs in the interface
local function updateTrackedBuffsList()
    -- Clear previous list elements
    for _, widget in ipairs(trackedBuffsList) do
        pcall(function()
            if widget then
                widget:Show(false)
                widget:RemoveAllAnchors()
            end
        end)
    end
    trackedBuffsList = {}
    
    -- Get current list of tracked buffs for the selected unit type
    local trackedBuffs = BuffsToTrack.GetAllTrackedBuffIds(currentUnitType)
    
    -- Reference to parent element for the list
    local container = settingsControls.buffsListContainer
    local yOffset = 0
    
    -- If list is empty, show selected message
    if #trackedBuffs == 0 then
        -- Check setting to understand if tracking is disabled completely
        local settings = api.GetSettings("CooldawnBuffTracker") or {}
        local isTrackingDisabled = settings[currentUnitType] and settings[currentUnitType].enabled == false
        
        -- Create background for empty list, with color depending on tracking status
        local bgColor = isTrackingDisabled and {r=0.2, g=0.8, b=0.2, a=0.3} or {r=0.9, g=0.7, b=0.7, a=0.5}
        local emptyBg = container:CreateColorDrawable(bgColor.r, bgColor.g, bgColor.b, bgColor.a, "background")
        emptyBg:AddAnchor("TOPLEFT", container, 10, 10)
        emptyBg:AddAnchor("BOTTOMRIGHT", container, -10, -10)
        table.insert(trackedBuffsList, emptyBg)
        
        -- Add text for empty list depending on tracking status
        local unitName = currentUnitType == "playerpet" and "mount" or "player"
        local messageText = isTrackingDisabled 
            and "Buff tracking for " .. unitName .. " is disabled" 
            or "Buff list for " .. unitName .. " is empty! Add new buff below."
        
        local messageColor = isTrackingDisabled and {r=0, g=0.6, b=0, a=1} or {r=0.8, g=0, b=0, a=1}
        
        local emptyLabel = helpers.createLabel('emptyTrackedBuffsList', container, messageText, 0, 40, 16)
        emptyLabel:SetWidth(550) -- Increase message width
        emptyLabel:AddAnchor("TOP", container, 0, 40) -- Center message
        emptyLabel.style:SetAlign(ALIGN.CENTER) -- Center text
        emptyLabel.style:SetColor(messageColor.r, messageColor.g, messageColor.b, messageColor.a)
        table.insert(trackedBuffsList, emptyLabel)
        
        -- Set minimum container height
        container:SetHeight(100)
        return
    end
    
    -- Create list of tracked buffs
    for i, buffId in ipairs(trackedBuffs) do
        -- Get buff name if possible
        local buffName = "Buff #" .. buffId
        pcall(function()
            buffName = BuffList.GetBuffName(buffId) or buffName
        end)
        
        -- Create row with buff information
        local buffRow = api.Interface:CreateWidget('window', 'trackedBuff_' .. i, container)
        buffRow:SetExtent(550, 20) -- Increase row width
        buffRow:AddAnchor("TOPLEFT", container, 10, yOffset)
        
        -- Buff ID
        local buffIdLabel = helpers.createLabel('buffIdLabel_' .. i, buffRow, tostring(buffId), 0, 0, 14)
        buffIdLabel:SetExtent(70, 20) -- Increase ID field width
        
        -- Buff name
        local buffNameLabel = helpers.createLabel('buffNameLabel_' .. i, buffRow, buffName, 80, 0, 14)
        buffNameLabel:SetExtent(350, 20) -- Increase name field width
        
        -- Remove button
        local removeButton = helpers.createButton('removeBuffButton_' .. i, buffRow, 'Remove', 440, 0)
        removeButton:SetExtent(100, 20) -- Increase remove button width
        
        -- Remove button handler
        removeButton:SetHandler("OnClick", function()
            if BuffsToTrack.RemoveTrackedBuff(buffId, currentUnitType) then
                -- Update list after removal
                updateTrackedBuffsList()
                -- Update main interface
                if helpers and helpers.updateSettings then
                    helpers.updateSettings()
                end
                
                -- Explicitly call buffs list update event
                pcall(function()
                    api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
                end)
            end
        end)
        
        yOffset = yOffset + 25
        table.insert(trackedBuffsList, buffRow)
    end
    
    -- Set correct container height to fit all elements
    local containerHeight = math.max(100, yOffset + 30)
    container:SetHeight(containerHeight)
end

local function saveSettings()
    -- Get current settings
    local mainSettings = api.GetSettings("CooldawnBuffTracker")
    
    -- Update values from controls for selected unit type
    if not mainSettings[currentUnitType] then
        mainSettings[currentUnitType] = {}
    end
    
    -- Update icon size settings
    mainSettings[currentUnitType].iconSize = tonumber(settingsControls.iconSize:GetText())
    mainSettings[currentUnitType].iconSpacing = tonumber(settingsControls.iconSpacing:GetText())
    
    -- Check values and set default values if needed
    if not mainSettings[currentUnitType].iconSize or mainSettings[currentUnitType].iconSize <= 0 then 
        mainSettings[currentUnitType].iconSize = 40 
    end
    
    if not mainSettings[currentUnitType].iconSpacing or mainSettings[currentUnitType].iconSpacing < 0 then 
        mainSettings[currentUnitType].iconSpacing = 5
    end
    
    -- Update position settings
    mainSettings[currentUnitType].posX = tonumber(settingsControls.posX:GetText())
    mainSettings[currentUnitType].posY = tonumber(settingsControls.posY:GetText())
    mainSettings[currentUnitType].lockPositioning = settingsControls.lockPositioning:GetChecked()
    
    -- Update timer settings
    if settingsControls.timerFontSize then
        mainSettings[currentUnitType].timerFontSize = tonumber(settingsControls.timerFontSize:GetText())
    end
    
    if settingsControls.timerTextColor and settingsControls.timerTextColor.colorBG then
        mainSettings[currentUnitType].timerTextColor = {r = 0, g = 0, b = 0, a = 1}
        mainSettings[currentUnitType].timerTextColor.r, mainSettings[currentUnitType].timerTextColor.g, mainSettings[currentUnitType].timerTextColor.b = 
            settingsControls.timerTextColor.colorBG:GetColor()
    end
    
    -- Update debug settings (common for all unit types)
    if settingsControls.debugBuffId then
        mainSettings.debugBuffId = settingsControls.debugBuffId:GetChecked()
    end
    
    -- Save settings and explicitly apply
    api.SaveSettings()
    
    -- Save settings through helpers, which will completely restart UI
    if helpers and helpers.updateSettings then
        helpers.updateSettings()
    end
    
    -- Close settings window
    settingsWindowClose()
end

local function resetSettings()
    pcall(function()
        -- Reset settings to default values
        settings = helpers.resetSettingsToDefault()
        
        -- Update values in interface for current unit type
        local unitSettings = settings[currentUnitType] or {}
        
        -- Update settings fields for selected unit type
        if settingsControls.iconSize then
            settingsControls.iconSize:SetText(tostring(unitSettings.iconSize or 40))
        end
        
        if settingsControls.iconSpacing then
            settingsControls.iconSpacing:SetText(tostring(unitSettings.iconSpacing or 5))
        end
        
        if settingsControls.posX then
            settingsControls.posX:SetText(tostring(unitSettings.posX or 0))
        end
        
        if settingsControls.posY then
            settingsControls.posY:SetText(tostring(unitSettings.posY or 0))
        end
        
        if settingsControls.lockPositioning then
            settingsControls.lockPositioning:SetChecked(unitSettings.lockPositioning or false)
        end
        
        -- Update timer settings
        if settingsControls.timerFontSize then
            settingsControls.timerFontSize:SetText(tostring(unitSettings.timerFontSize or 16))
        end
        
        -- Update timer text color
        if settingsControls.timerTextColor and settingsControls.timerTextColor.colorBG then
            local textColor = unitSettings.timerTextColor or {r = 1, g = 1, b = 1, a = 1}
            settingsControls.timerTextColor.colorBG:SetColor(
                textColor.r or 1,
                textColor.g or 1,
                textColor.b or 1,
                1
            )
        end
        
        -- Update debug settings (common)
        if settingsControls.debugBuffId then
            settingsControls.debugBuffId:SetChecked(settings.debugBuffId or false)
        end
        
        -- Update tracked buffs list
        updateTrackedBuffsList()
        
        -- Update main interface
        if helpers and helpers.updateSettings then
            helpers.updateSettings()
        end
        
        -- Explicitly call buffs list update event
        pcall(function()
            api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
        end)
    end)
end

-- Add new buff
local function addTrackedBuff()
    -- Always update list on any interaction
    updateTrackedBuffsList()
    
    local buffIdText = settingsControls.newBuffId:GetText()
    local buffId = tonumber(buffIdText)
    
    if not buffId then
        -- Show error if buff ID is not a number
        if settingsControls.addBuffError and settingsControls.errorPanel then
            settingsControls.addBuffError:SetText("Error: Buff ID must be a number")
            settingsControls.errorPanel:Show(true)
        end
        return
    end
    
    -- Check buff existence in BuffList
    local isValidBuff = false
    pcall(function()
        -- Use more reliable function for checking buff existence
        if BuffList and BuffList.IsValidBuff then
            isValidBuff = BuffList.IsValidBuff(buffId)
        else
            -- Backup option: try to get buff icon or name through BuffList
            local buffIcon = BuffList.GetBuffIcon(buffId)
            local buffName = BuffList.GetBuffName(buffId)
            
            -- Check buff existence - if there's at least an icon or specific name
            isValidBuff = buffIcon ~= nil or (buffName and buffName ~= "Buff #" .. buffId)
        end
    end)
    
    if not isValidBuff then
        -- Show error if buff ID not found in BuffList
        if settingsControls.addBuffError and settingsControls.errorPanel then
            settingsControls.addBuffError:SetText("Error: Buff with ID " .. buffId .. " not found in buff library")
            settingsControls.errorPanel:Show(true)
        end
        return
    end
    
    -- Try to add buff for selected unit type
    if BuffsToTrack.AddTrackedBuff(buffId, currentUnitType) then
        -- Update list if buff successfully added
        updateTrackedBuffsList()
        
        -- Clear input field
        settingsControls.newBuffId:SetText("")
        
        -- Hide error message
        if settingsControls.errorPanel then
            settingsControls.errorPanel:Show(false)
        end
        
        -- Update main interface
        if helpers and helpers.updateSettings then
            helpers.updateSettings()
        end
        
        -- Explicitly call buffs list update event
        pcall(function()
            api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
        end)
    else
        -- Show message that buff already tracked
        if settingsControls.addBuffError and settingsControls.errorPanel then
            settingsControls.addBuffError:SetText("Error: Buff already tracked or error occurred")
            settingsControls.errorPanel:Show(true)
        end
    end
    
    -- Forcefully update list one more time
    pcall(function()
        updateTrackedBuffsList()
        if settingsControls.buffsListContainer then
            settingsControls.buffsListContainer:Show(true)
        end
    end)
end

-- Function to update settings fields depending on selected unit type
local function updateSettingsFields()
    -- Update settings from current data
    settings = helpers.getSettings()
    
    -- Check if settings for selected unit type exist
    if not settings[currentUnitType] then
        settings[currentUnitType] = {}
    end
    
    -- Update settings fields for selected unit type
    local unitSettings = settings[currentUnitType]
    
    -- Update position fields
    if settingsControls.posX then
        settingsControls.posX:SetText(tostring(unitSettings.posX or 0))
    end
    
    if settingsControls.posY then
        settingsControls.posY:SetText(tostring(unitSettings.posY or 0))
    end
    
    -- Update lock positioning checkbox
    if settingsControls.lockPositioning then
        settingsControls.lockPositioning:SetChecked(unitSettings.lockPositioning or false)
    end
    
    -- Update timer settings
    if settingsControls.timerFontSize then
        settingsControls.timerFontSize:SetText(tostring(unitSettings.timerFontSize or 16))
    end
    
    -- Update timer text color
    if settingsControls.timerTextColor and settingsControls.timerTextColor.colorBG then
        local textColor = unitSettings.timerTextColor or {r = 1, g = 1, b = 1, a = 1}
        settingsControls.timerTextColor.colorBG:SetColor(
            textColor.r or 1,
            textColor.g or 1,
            textColor.b or 1,
            1
        )
    end
    
    -- Update icon size settings
    if settingsControls.iconSize then
        settingsControls.iconSize:SetText(tostring(unitSettings.iconSize or 40))
    end
    
    if settingsControls.iconSpacing then
        settingsControls.iconSpacing:SetText(tostring(unitSettings.iconSpacing or 5))
    end
    
    -- Update label settings
    if settingsControls.labelFontSize then
        settingsControls.labelFontSize:SetText(tostring(unitSettings.labelFontSize or 14))
    end
    
    if settingsControls.labelX then
        settingsControls.labelX:SetText(tostring(unitSettings.labelX or 0))
    end
    
    if settingsControls.labelY then
        settingsControls.labelY:SetText(tostring(unitSettings.labelY or -30))
    end
    
    -- Update checkboxes
    if settingsControls.showLabel then
        settingsControls.showLabel:SetChecked(unitSettings.showLabel or false)
    end
    
    if settingsControls.showTimer then
        settingsControls.showTimer:SetChecked(unitSettings.showTimer ~= false) -- Default enabled
    end
    
    -- Update tracked buffs list
    updateTrackedBuffsList()
end

local function initSettingsPage()
    settings = helpers.getSettings()
    
    -- Use CreateWindow instead of CreateEmptyWindow for correct support of ESC and dragging
    settingsWindow = api.Interface:CreateWindow("CooldawnBuffTrackerSettings",
                                             'CooldawnBuffTracker', 600, 650)
    settingsWindow:AddAnchor("CENTER", 'UIParent', 0, 0)
    settingsWindow:SetHandler("OnCloseByEsc", settingsWindowClose)
    function settingsWindow:OnClose() settingsWindowClose() end
    
    -- If unable to create window, exit
    if not settingsWindow then return end
    
    -- UNIT TYPE SELECTOR - Add at the very top
    local unitTypeLabel = helpers.createLabel('unitTypeLabel', settingsWindow,
                                           'Select unit type for settings:', 15, 30, 16)
    unitTypeLabel:SetWidth(250)
    
    -- Mount settings button
    local mountButton = helpers.createButton('mountButton', settingsWindow, 'Mount (playerpet)', 300, 30)
    mountButton:SetWidth(140)
    
    -- Player settings button
    local playerButton = helpers.createButton('playerButton', settingsWindow, 'Player (player)', 450, 30)
    playerButton:SetWidth(140)
    
    -- Function to update button style depending on selected type
    local function updateUnitTypeButtons()
        if currentUnitType == "playerpet" then
            mountButton:SetText("* Mount (playerpet)")
            playerButton:SetText("Player (player)")
        else
            mountButton:SetText("Mount (playerpet)")
            playerButton:SetText("* Player (player)")
        end
    end
    
    -- Unit type button click handlers
    mountButton:SetHandler("OnClick", function()
        currentUnitType = "playerpet"
        updateUnitTypeButtons()
        updateTrackedBuffsList()
        -- Update all settings fields for mount settings display
        updateSettingsFields()
    end)
    
    playerButton:SetHandler("OnClick", function()
        currentUnitType = "player"
        updateUnitTypeButtons()
        updateTrackedBuffsList()
        -- Update all settings fields for player settings display
        updateSettingsFields()
    end)
    
    -- Initialize button style
    updateUnitTypeButtons()
    
    -- FIRST BLOCK - Buff tracker management header
    local trackedBuffsGroupLabel = helpers.createLabel('trackedBuffsGroupLabel', settingsWindow,
                                                    'Buff tracker management', 15, 60, 20)
    trackedBuffsGroupLabel:SetWidth(570) -- Increase header width
    
    -- Clear all buffs button

    
    -- SECOND BLOCK - Tracked buffs list (RIGHT AFTER HEADER)
    -- Place it above other elements in hierarchy
    local trackedBuffsListHeader = helpers.createLabel('trackedBuffsListHeader', trackedBuffsGroupLabel,
                                                    'Buff list:', 0, 30, 16)
    trackedBuffsListHeader:Show(true)
    trackedBuffsListHeader:SetWidth(570) -- Increase header width
    settingsControls.trackedBuffsListHeader = trackedBuffsListHeader
    
    -- Create container for buffs list and place it directly under header
    local buffsListContainer = api.Interface:CreateWidget('window', 'buffsListContainer', trackedBuffsListHeader)
    buffsListContainer:SetExtent(570, 120) -- Increase container width
    buffsListContainer:AddAnchor("TOPLEFT", trackedBuffsListHeader, 0, 25)
    buffsListContainer:Show(true)
    
    -- Visible background for container
    local containerBg = buffsListContainer:CreateColorDrawable(0.85, 0.85, 0.85, 1, "background")
    containerBg:AddAnchor("TOPLEFT", buffsListContainer, 0, 0)
    containerBg:AddAnchor("BOTTOMRIGHT", buffsListContainer, 0, 0)
    
    -- Save container in controlling elements
    settingsControls.buffsListContainer = buffsListContainer
    
    -- IMMEDIATELY fill list of tracked buffs
    updateTrackedBuffsList()
    
    -- THIRD BLOCK - Only after list creation adds input elements for new buff
    -- Input field for new buff ID - place AFTER list, but in main window (not in list container)
    local newBuffIdLabel = helpers.createLabel('newBuffIdLabel', settingsWindow,
                                            'Buff ID:', 15, 220, 15)
    newBuffIdLabel:SetWidth(100) -- Set label width
    local newBuffId = helpers.createEdit('newBuffId', newBuffIdLabel,
                                      "", 200, 0)
    if newBuffId then 
        newBuffId:SetMaxTextLength(10) 
        newBuffId:SetWidth(50) -- Increase input field width
    end
    settingsControls.newBuffId = newBuffId
    
    -- Add buff button
    local addBuffButton = helpers.createButton('addBuffButton', newBuffIdLabel, 'Add', 450, 0)
    addBuffButton:SetWidth(100) -- Increase button width
    settingsControls.addBuffButton = addBuffButton
    
    -- Now bind input handler to add button
    addBuffButton:SetHandler("OnClick", addTrackedBuff)
    
    -- Create highlighted panel for error messages
    -- Place it in separate place between input ID field and icon settings
    local errorPanel = api.Interface:CreateWidget('window', 'errorPanel', settingsWindow)
    errorPanel:SetExtent(570, 25) -- Increase error panel width
    errorPanel:AddAnchor("TOPLEFT", settingsWindow, 15, 250) -- Fixed position under input field
    
    -- Frame for error panel for better highlighting
    local errorPanelBorder = errorPanel:CreateNinePartDrawable("ui/chat_option.dds", "artwork")
    errorPanelBorder:SetCoords(0, 0, 27, 16)
    errorPanelBorder:SetInset(0, 8, 0, 7)
    errorPanelBorder:AddAnchor("TOPLEFT", errorPanel, -1, -1)
    errorPanelBorder:AddAnchor("BOTTOMRIGHT", errorPanel, 1, 1)
    
    -- Background for error panel - make more visible
    local errorPanelBg = errorPanel:CreateColorDrawable(0.98, 0.85, 0.85, 0.9, "background")
    errorPanelBg:AddAnchor("TOPLEFT", errorPanel, 0, 0)
    errorPanelBg:AddAnchor("BOTTOMRIGHT", errorPanel, 0, 0)
    
    -- Error message in panel
    local addBuffError = helpers.createLabel('addBuffError', errorPanel, '', 5, 5, 14)
    addBuffError:SetExtent(560, 20) -- Increase error message width
    addBuffError.style:SetColor(1, 0, 0, 1) -- Red color for error message
    settingsControls.addBuffError = addBuffError
    
    -- By default error panel is hidden
    errorPanel:Show(false)
    settingsControls.errorPanel = errorPanel
    
    -- FOURTH BLOCK - other settings
    -- Icon settings group - place below error panel
    local iconGroupLabel = helpers.createLabel('iconGroupLabel', settingsWindow,
                                             'Icon settings', 15, 290, 20)
    iconGroupLabel:SetWidth(570) -- Increase header width
                                             
    -- Icon size
    local iconSizeLabel = helpers.createLabel('iconSizeLabel', iconGroupLabel,
                                            'Icon size:', 0, 25, 15)
    iconSizeLabel:SetWidth(150) -- Set label width
    local iconSize = helpers.createEdit('iconSize', iconSizeLabel,
                                      settings.iconSize, 200, 0)
    if iconSize then 
        iconSize:SetMaxTextLength(4) 
        iconSize:SetWidth(50) -- Increase input field width
    end
    settingsControls.iconSize = iconSize
    
    -- Icon spacing
    local iconSpacingLabel = helpers.createLabel('iconSpacingLabel', iconSizeLabel,
                                               'Icon spacing:', 0, 25, 15)
    iconSpacingLabel:SetWidth(150) -- Set label width
    local iconSpacing = helpers.createEdit('iconSpacing', iconSpacingLabel,
                                         settings.iconSpacing, 200, 0)
    if iconSpacing then 
        iconSpacing:SetMaxTextLength(4) 
        iconSpacing:SetWidth(50) -- Increase input field width
    end
    settingsControls.iconSpacing = iconSpacing
    
    -- Icon position group
    local positionLabel = helpers.createLabel('positionLabel', iconSpacingLabel,
                                            'Icon position', 0, 35, 18)
    positionLabel:SetWidth(570) -- Increase header width
                                            
    -- X coordinate
    local posXLabel = helpers.createLabel('posXLabel', positionLabel,
                                        'Position X:', 0, 25, 15)
    posXLabel:SetWidth(150) -- Set label width
    local posX = helpers.createEdit('posX', posXLabel,
                                  settings.posX, 200, 0)
    if posX then 
        posX:SetMaxTextLength(6) 
        posX:SetWidth(50) -- Increase input field width
    end
    settingsControls.posX = posX
    
    -- Y coordinate
    local posYLabel = helpers.createLabel('posYLabel', posXLabel,
                                        'Position Y:', 0, 25, 15)
    posYLabel:SetWidth(150) -- Set label width
    local posY = helpers.createEdit('posY', posYLabel,
                                  settings.posY, 200, 0)
    if posY then 
        posY:SetMaxTextLength(6) 
        posY:SetWidth(50) -- Increase input field width
    end
    settingsControls.posY = posY
    
    -- Lock positioning
    local lockPositioning = helpers.createCheckbox('lockPositioning', posYLabel,
                                                 "Lock icon movement", 0, 25)
    if lockPositioning then 
        lockPositioning:SetChecked(settings.lockPositioning or false)
    end
    settingsControls.lockPositioning = lockPositioning
    
    -- Timer settings
    local timerGroupLabel = helpers.createLabel('timerGroupLabel', lockPositioning,
                                             'Timer settings', 0, 35, 18)
    timerGroupLabel:SetWidth(570) -- Increase header width
    
    -- Timer font size
    local timerFontSizeLabel = helpers.createLabel('timerFontSizeLabel', timerGroupLabel,
                                                'Font size:', 0, 25, 15)
    timerFontSizeLabel:SetWidth(150) -- Set label width
    local timerFontSize = helpers.createEdit('timerFontSize', timerFontSizeLabel,
                                          settings.timerFontSize, 200, 0)
    if timerFontSize then 
        timerFontSize:SetMaxTextLength(4) 
        timerFontSize:SetWidth(50) -- Increase input field width
    end
    settingsControls.timerFontSize = timerFontSize
    
    -- Timer text color
    local timerTextColorLabel = helpers.createLabel('timerTextColorLabel', timerFontSizeLabel,
                                                 'Text color:', 0, 25, 15)
    timerTextColorLabel:SetWidth(150) -- Set label width
    
    -- Get timer text color from settings for selected unit type
    local unitSettings = settings[currentUnitType] or {}
    local textColor = unitSettings.timerTextColor or {r = 1, g = 1, b = 1, a = 1}
    
    local timerTextColor = helpers.createColorPickButton('timerTextColor', timerTextColorLabel, 
                                                      textColor, 200, 0)
    
    -- Configure color picker handler to save selected color
    if timerTextColor and timerTextColor.colorBG then
        function timerTextColor:SelectedProcedure(r, g, b, a)
            self.colorBG:SetColor(r, g, b, a)
            -- Save color for future use
            local mainSettings = api.GetSettings("CooldawnBuffTracker")
            if not mainSettings[currentUnitType] then
                mainSettings[currentUnitType] = {}
            end
            mainSettings[currentUnitType].timerTextColor = {r = r, g = g, b = b, a = a or 1}
        end
    end
    
    settingsControls.timerTextColor = timerTextColor
    
    -- Add debug settings with better location
    local debugGroupLabel = helpers.createLabel('debugGroupLabel', timerTextColorLabel,
                                             'Debug settings', 0, 35, 18)
    debugGroupLabel:SetWidth(570) -- Increase header width
    
    -- Checkbox for debug buff ID - change position for better display
    local debugBuffId = helpers.createCheckbox('debugBuffId', debugGroupLabel,
                                            "Debug buffId", 0, 25)
    if debugBuffId then 
        debugBuffId:SetChecked(settings.debugBuffId or false)
    end
    settingsControls.debugBuffId = debugBuffId
    
    -- Create save and cancel buttons
    local saveButton = helpers.createButton("saveButton", settingsWindow, "Save", 0, 0)
    saveButton:SetExtent(120, 30)
    saveButton:RemoveAllAnchors()
    saveButton:AddAnchor("BOTTOMRIGHT", settingsWindow, "BOTTOMRIGHT", -20, -20)
    saveButton:SetHandler("OnClick", function()
      saveSettings()
    end)
    settingsControls.saveButton = saveButton
    
    local resetButton = helpers.createButton("resetButton", settingsWindow, "Reset", 0, 0)
    resetButton:SetExtent(120, 30)
    resetButton:RemoveAllAnchors()
    resetButton:AddAnchor("RIGHT", saveButton, "LEFT", -10, 0)
    resetButton:SetHandler("OnClick", function()
      resetSettings()
    end)
    settingsControls.resetButton = resetButton
    
    local cancelButton = helpers.createButton("cancelButton", settingsWindow, "Cancel", 0, 0)
    cancelButton:SetExtent(120, 30)
    cancelButton:RemoveAllAnchors()
    cancelButton:AddAnchor("RIGHT", resetButton, "LEFT", -10, 0)
    cancelButton:SetHandler("OnClick", function()
      settingsWindowClose()
    end)
    settingsControls.cancelButton = cancelButton
    
    -- Final check - call update one more time for confidence
    pcall(function()
        -- Force update list one more time
        updateTrackedBuffsList()
        
        -- Force show all critical elements
        settingsControls.buffsListContainer:Show(true)
        settingsControls.trackedBuffsListHeader:Show(true)
        
        -- Hide error panel on first opening
        if settingsControls.errorPanel then
            settingsControls.errorPanel:Show(false)
        end
        
        -- Check buffs existence in list
        local buffIds = BuffsToTrack.GetAllTrackedBuffIds()
        if #buffIds == 0 then
            -- Add informational message for empty list
            local emptyLabel = helpers.createLabel('initialEmptyLabel', settingsControls.buffsListContainer, 
                                                'Empty list. Add new buff below.', 10, 10, 14)
            table.insert(trackedBuffsList, emptyLabel)
        end
    end)
end

local function Unload()
    if settingsWindow ~= nil then
        settingsWindow:Show(false)
        settingsWindow = nil
    end
    
    -- Close palette if it's open
    local F_ETC = nil
    F_ETC = require('CooldawnBuffTracker/util/etc') or require('util/etc') or require('./util/etc')
    if F_ETC then
        F_ETC.HidePallet()
    end
end

local function openSettingsWindow()
    if settingsWindow and settingsWindow:IsVisible() then
        settingsWindowClose()
        return
    end
    
    -- If window was already initialized, just show it
    if settingsWindow then
        -- Update settings fields for current unit type
        updateSettingsFields()
        
        -- Update tracked buffs list on each window opening
        updateTrackedBuffsList()
        
        -- Hide error panel on each window opening
        if settingsControls.errorPanel then
            settingsControls.errorPanel:Show(false)
        end
        
        settingsWindow:Show(true)
        helpers.setSettingsPageOpened(true)
        return
    end
    
    -- If window wasn't initialized, create it
    initSettingsPage()
    
    if settingsWindow then
        -- Update settings fields for current unit type
        updateSettingsFields()
        
        settingsWindow:Show(true)
        helpers.setSettingsPageOpened(true)
    end
end

local function updatePositionFields(x, y)
    pcall(function()
        if settingsControls.posX and settingsControls.posY then
            settingsControls.posX:SetText(tostring(x))
            settingsControls.posY:SetText(tostring(y))
        end
    end)
end

local settings_page = {
    Load = initSettingsPage,
    Unload = Unload,
    openSettingsWindow = openSettingsWindow,
    updatePositionFields = updatePositionFields
}

return settings_page 