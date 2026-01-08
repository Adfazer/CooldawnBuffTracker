local api = require("api")
local helpers = require('CooldawnBuffTracker/helpers')

-- Load module for working with buffs
local BuffsToTrack = require("CooldawnBuffTracker/buffs_to_track")
local BuffList = require("CooldawnBuffTracker/buff_helper")

-- Импортируем модуль для отображения пиксельного изображения
local pixelViewer = require('CooldawnBuffTracker/util/pixel_viewer')

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
local trackedBuffsList = {} -- For storing buff list widgets
local currentUnitType = "playerpet" -- By default, show settings for mount
local buffListPage = 1 -- Текущая страница пагинации для списка баффов
local buffsPerPage = 4 -- Количество баффов на странице
local customBuffsList = {} -- Для хранения виджетов списка пользовательских баффов
local customBuffPage = 1 -- Текущая страница пагинации для списка пользовательских баффов
local customsPerPage = 3 -- Количество custom баффов на странице

-- Updates the list of tracked buffs in the interface
local function updateTrackedBuffsList(resetPage)
    -- Clear previous list elements
    for _, widget in ipairs(trackedBuffsList) do
        if widget then
            widget:Show(false)
            widget:RemoveAllAnchors()
            widget = nil
        end
    end
    trackedBuffsList = {}
    
    -- Сбросим страницу только при явном запросе (например при переключении вкладок)
    if resetPage then
        buffListPage = 1
    end
    
    -- Проверяем существование контейнера
    if not settingsControls.buffsListContainer then
        api.Log:Err("[CBT] Containers not found!")
        return
    end
    
    -- Убедимся, что контейнер виден
    settingsControls.buffsListContainer:Show(true)
    
    -- Обновляем видимые элементы
    if settingsControls.updateVisibleItems then
        settingsControls.updateVisibleItems()
    else
        api.Log:Err("[CBT] updateVisibleItems not found!")
    end
    
    -- Убедимся, что все остальные элементы интерфейса отображаются
    -- Проверяем поле ввода и кнопку добавления
    if settingsControls.newBuffId then settingsControls.newBuffId:Show(true) end
    if settingsControls.addBuffButton then settingsControls.addBuffButton:Show(true) end
    
    -- Проверяем группы настроек иконок, позиций и таймера
    if settingsControls.iconSize then settingsControls.iconSize:Show(true) end
    if settingsControls.iconSpacing then settingsControls.iconSpacing:Show(true) end
    if settingsControls.posX then settingsControls.posX:Show(true) end
    if settingsControls.posY then settingsControls.posY:Show(true) end
    if settingsControls.lockButton then settingsControls.lockButton:Show(true) end
    if settingsControls.timerFontSize then settingsControls.timerFontSize:Show(true) end
end

-- Обновляет список пользовательских баффов
local function updateCustomBuffsList(resetPage)
    -- Очищаем предыдущие элементы списка
    for _, widget in ipairs(customBuffsList) do
        if widget then
            widget:Show(false)
            widget:RemoveAllAnchors()
            widget = nil
        end
    end
    customBuffsList = {}

    -- Сбрасываем страницу только при явном запросе
    if resetPage then
        customBuffPage = 1
    end

    -- Проверяем существование контейнера
    if not settingsControls.customBuffsListContainer then
        return
    end

    settingsControls.customBuffsListContainer:Show(true)

    -- Обновляем видимые элементы
    if settingsControls.updateCustomVisibleItems then
        settingsControls.updateCustomVisibleItems()
    end
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
    -- Lock positioning is saved immediately on button click, use current settings value
    mainSettings[currentUnitType].lockPositioning = settings[currentUnitType] and settings[currentUnitType].lockPositioning or false
    
    -- Update timer settings (common for all unit types)
    if settingsControls.timerFontSize then
        mainSettings[currentUnitType].timerFontSize = tonumber(settingsControls.timerFontSize:GetText())
    end
    
    if settingsControls.timerTextColor and settingsControls.timerTextColor.colorBG then
        local rgb = settingsControls.timerTextColor.colorBG:GetColor()
        mainSettings[currentUnitType].timerTextColor = rgb
    end
    
    -- Сохраняем пользовательские баффы
    local currentCustomBuffs = api.GetSettings("CooldawnBuffTracker").customBuffs or {}
    mainSettings.customBuffs = {}
    
    -- Если есть баффы в текущих настройках, используем их
    if settings.customBuffs and #settings.customBuffs > 0 then
        for i, buffData in ipairs(settings.customBuffs) do
            local buff = {}
            for k, v in pairs(buffData) do
                buff[k] = v
            end
            table.insert(mainSettings.customBuffs, buff)
        end
    -- Иначе сохраняем текущие кастомные баффы из mainSettings
    elseif currentCustomBuffs and #currentCustomBuffs > 0 then
        for i, buffData in ipairs(currentCustomBuffs) do
            local buff = {}
            for k, v in pairs(buffData) do
                buff[k] = v
            end
            table.insert(mainSettings.customBuffs, buff)
        end
    end
    
    -- Debug mode is saved immediately on button click, use current settings value
    mainSettings.debugBuffId = settings.debugBuffId or false
    
    -- Save settings and explicitly apply
    api.SaveSettings()
    
    -- Save settings through helpers, which will completely restart UI
    if helpers and helpers.updateSettings then
        helpers.updateSettings()
    end
end

local function settingsWindowClose()
    -- Обновляем настройки перед сохранением
    settings = helpers.getSettings() -- Обновим переменную settings актуальными данными
    
    -- Debug mode is already saved on button click, no need to update here
    
    -- Сохраняем настройки перед закрытием окна
    saveSettings()
    
    if settingsWindow then
        settingsWindow:Show(false)
        helpers.setSettingsPageOpened(false)
    end
    
    local F_ETC = require('CooldawnBuffTracker/util/etc')
    if F_ETC then
        F_ETC.HidePallet()
    end
end

-- Add new buff
local function addTrackedBuff()
    -- Always update list on any interaction
    updateTrackedBuffsList()
    
    local buffId = settingsControls.newBuffId:GetText()
    
    if not buffId then
        -- Show error if buff ID is not a number
        if settingsControls.addBuffError and settingsControls.errorPanel then
            settingsControls.addBuffError:SetText("Error: Buff ID must be a number")
            settingsControls.errorPanel:Show(true)
        end
        return
    end
    
    -- Проверяем, есть ли баф с таким ID в списке кастомных бафов
    local isInCustomBuffs = false
    if settings and settings.customBuffs then
        for _, buffInfo in ipairs(settings.customBuffs) do
            if buffInfo.id == buffId then
                isInCustomBuffs = true
                break
            end
        end
    end
    
    if not isInCustomBuffs then
        -- Показываем ошибку, если баф не найден в списке кастомных бафов
        if settingsControls.addBuffError and settingsControls.errorPanel then
            settingsControls.addBuffError:SetText("Error: Buff ID " .. buffId .. " not found in custom buffs list")
            settingsControls.errorPanel:Show(true)
        end
        return
    end
    
    -- Try to add buff for selected unit type
    if BuffsToTrack.AddTrackedBuff(buffId, currentUnitType) then
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
        api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
        
        -- Go to last page to show newly added buff
        local trackedBuffs = BuffsToTrack.GetAllTrackedBuffIds(currentUnitType)
        buffListPage = math.max(1, math.ceil(#trackedBuffs / buffsPerPage))
        
        if settingsControls.updateVisibleItems then
            settingsControls.updateVisibleItems()
        end
    else
        -- Show message that buff already tracked
        if settingsControls.addBuffError and settingsControls.errorPanel then
            settingsControls.addBuffError:SetText("Error: Buff already tracked or error occurred")
            settingsControls.errorPanel:Show(true)
        end
    end
end

-- Добавляет пользовательский бафф
local function addCustomBuff()
    local id = settingsControls.newCustomBuffId:GetText()
    local name = settingsControls.newCustomBuffName:GetText()
    local cooldown = tonumber(settingsControls.newCustomBuffCooldown:GetText())
    local timeOfAction = tonumber(settingsControls.newCustomBuffTimeOfAction:GetText())

    if not id or not name or not cooldown or not timeOfAction then
        if settingsControls.addCustomBuffError and settingsControls.customBuffErrorPanel then
            settingsControls.addCustomBuffError:SetText("Error: All fields must be filled correctly")
            settingsControls.customBuffErrorPanel:Show(true)
        end
        return
    end

    -- Проверяем, существует ли уже бафф с таким ID
    if settings and settings.customBuffs then
        for _, buffInfo in ipairs(settings.customBuffs) do
            if buffInfo.id == id then
                if settingsControls.addCustomBuffError and settingsControls.customBuffErrorPanel then
                    settingsControls.addCustomBuffError:SetText("Error: Buff with this ID already exists")
                    settingsControls.customBuffErrorPanel:Show(true)
                end
                return
            end
        end
    end
    
    -- Проверяем наличие иконки с таким ID
    local buffIcon = BuffList.GetBuffIcon(id)
    local iconExists = buffIcon ~= nil
    
    if not iconExists then
        if settingsControls.addCustomBuffError and settingsControls.customBuffErrorPanel then
            settingsControls.addCustomBuffError:SetText("Error: Icon for buff ID " .. id .. " not found")
            settingsControls.customBuffErrorPanel:Show(true)
        end
        return
    end

    local newBuff = {
        id = id,
        name = name,
        cooldown = cooldown,
        timeOfAction = timeOfAction
    }

    -- Добавляем бафф в настройки
    if not settings.customBuffs then
        settings.customBuffs = {}
    end
    table.insert(settings.customBuffs, newBuff)

    -- Очищаем поля ввода
    settingsControls.newCustomBuffId:SetText("")
    settingsControls.newCustomBuffName:SetText("")
    settingsControls.newCustomBuffCooldown:SetText("")
    settingsControls.newCustomBuffTimeOfAction:SetText("")

    -- Скрываем сообщение об ошибке
    if settingsControls.customBuffErrorPanel then
        settingsControls.customBuffErrorPanel:Show(false)
    end

    -- Обновляем интерфейс
    if helpers and helpers.updateSettings then
        helpers.updateSettings()
    end
    
    -- Go to last page to show newly added buff
    local customBuffs = settings.customBuffs or {}
    customBuffPage = math.max(1, math.ceil(#customBuffs / customsPerPage))
    
    if settingsControls.updateCustomVisibleItems then
        settingsControls.updateCustomVisibleItems()
    end
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
    
    -- Update lock button text
    if settingsControls.lockButton then
        settingsControls.lockButton:SetText(unitSettings.lockPositioning and "Lock: ON" or "Lock: OFF")
    end
    
    -- Update debug button text (global setting, not per unit type)
    if settingsControls.debugBuffButton then
        settingsControls.debugBuffButton:SetText(settings.debugBuffId and "Debug: ON" or "Debug: OFF")
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

-- Функция для добавления кнопки просмотра пиксельного изображения
local function addPixelViewerButton()
    if settingsWindow and settingsControls.debugBuffButton then
        -- Создаем кнопку для открытия окна просмотра пиксельного изображения
        local pixelViewButton = helpers.createButton('pixelViewButton', settingsControls.addCustomBuffButton, 'Thank you for your hard work!', -25, 80)
        pixelViewButton:SetExtent(200, 200)
        pixelViewButton:SetHandler("OnClick", function()
            pixelViewer.openPixelWindow()
        end)
        pixelViewButton:Show(true)
        settingsControls.pixelViewButton = pixelViewButton
    end
end

local function initSettingsPage()
    settings = helpers.getSettings()
    
    -- Use CreateWindow instead of CreateEmptyWindow for correct support of ESC and dragging
    settingsWindow = api.Interface:CreateWindow("CooldawnBuffTrackerSettings",
                                             'CooldawnBuffTracker', 600, 900) -- Увеличиваем высоту окна для всех элементов
    if not settingsWindow then
        api.Log:Err("[CBT] Failed to create settings window!")
        return
    end
    
    settingsWindow:AddAnchor("CENTER", 'UIParent', 0, 0)
    settingsWindow:SetHandler("OnCloseByEsc", settingsWindowClose)
    function settingsWindow:OnClose() settingsWindowClose() end
    
    -- UNIT TYPE SELECTOR - Add at the very top (c дополнительным отступом)
    local unitTypeLabel = helpers.createLabel('unitTypeLabel', settingsWindow,
                                           'Select unit type for settings:', 15, 30, 16)
    unitTypeLabel:SetWidth(250)
    unitTypeLabel:Show(true)
    
    -- Mount settings button
    local mountButton = helpers.createButton('mountButton', settingsWindow, 'Mount', 280, 30)
    mountButton:SetWidth(80)
    mountButton:Show(true)
    
    -- Player settings button
    local playerButton = helpers.createButton('playerButton', settingsWindow, 'Player', 365, 30)
    playerButton:SetWidth(80)
    playerButton:Show(true)
    
    -- Target settings button
    local targetButton = helpers.createButton('targetButton', settingsWindow, 'Target', 450, 30)
    targetButton:SetWidth(80)
    targetButton:Show(true)
    
    -- Function to update button style depending on selected type
    local function updateUnitTypeButtons()
        if currentUnitType == "playerpet" then
            mountButton:SetText("* Mount")
            playerButton:SetText("Player")
            targetButton:SetText("Target")
        elseif currentUnitType == "player" then
            mountButton:SetText("Mount")
            playerButton:SetText("* Player")
            targetButton:SetText("Target")
        else
            mountButton:SetText("Mount")
            playerButton:SetText("Player")
            targetButton:SetText("* Target")
        end
    end
    
    -- Unit type button click handlers
    mountButton:SetHandler("OnClick", function()
        currentUnitType = "playerpet"
        updateUnitTypeButtons()
        updateTrackedBuffsList(true) -- Reset page when switching tabs
        -- Update all settings fields for mount settings display
        updateSettingsFields()
    end)
    
    playerButton:SetHandler("OnClick", function()
        currentUnitType = "player"
        updateUnitTypeButtons()
        updateTrackedBuffsList(true) -- Reset page when switching tabs
        -- Update all settings fields for player settings display
        updateSettingsFields()
    end)
    
    targetButton:SetHandler("OnClick", function()
        currentUnitType = "target"
        updateUnitTypeButtons()
        updateTrackedBuffsList(true) -- Reset page when switching tabs
        -- Update all settings fields for target settings display
        updateSettingsFields()
    end)
    
    -- Initialize button style
    updateUnitTypeButtons()
    
    -- FIRST BLOCK - контейнер для размещения элементов (без заголовка)
    local trackedBuffsGroupLabel = helpers.createLabel('trackedBuffsGroupLabel', settingsWindow,
                                                    '', 15, 50, 20)  -- Удаляем текст "Buff tracker management"
    trackedBuffsGroupLabel:SetWidth(570) -- Increase header width
    trackedBuffsGroupLabel:Show(true)
    
    -- SECOND BLOCK - Tracked buffs list
    local trackedBuffsListHeader = helpers.createLabel('trackedBuffsListHeader', trackedBuffsGroupLabel,
                                                    'Buff list:', 0, 10, 16)
    trackedBuffsListHeader:Show(true)
    trackedBuffsListHeader:SetWidth(570)
    settingsControls.trackedBuffsListHeader = trackedBuffsListHeader
    
    -- Create container for buffs list and place it directly under header
    local buffsListContainer = api.Interface:CreateWidget('window', 'buffsListContainer', trackedBuffsListHeader)
    buffsListContainer:SetExtent(570, 140) -- Увеличенная высота контейнера для списка (6 элементов)
    buffsListContainer:AddAnchor("TOPLEFT", trackedBuffsListHeader, 0, 35)
    buffsListContainer:Show(true)
    buffsListContainer:Clickable(true) -- Включаем кликабельность для обработки колесика мыши
    
    -- Enable scissor clipping to prevent elements from rendering outside container bounds
    if buffsListContainer.EnableScissor then
        buffsListContainer:EnableScissor(true)
    end
    
    -- Добавляем рамку для визуального обозначения границ списка
    local containerBorder = buffsListContainer:CreateNinePartDrawable("ui/chat_option.dds", "artwork")
    containerBorder:SetCoords(0, 0, 27, 16)
    containerBorder:SetInset(9, 8, 9, 7)
    containerBorder:AddAnchor("TOPLEFT", buffsListContainer, -1, -1)
    containerBorder:AddAnchor("BOTTOMRIGHT", buffsListContainer, 1, 1)
    
    -- Visible background for container
    local containerBg = buffsListContainer:CreateColorDrawable(0.92, 0.92, 0.92, 1, "background")
    containerBg:AddAnchor("TOPLEFT", buffsListContainer, 0, 0)
    containerBg:AddAnchor("BOTTOMRIGHT", buffsListContainer, 0, 0)
    
    -- Создаем внутренний контейнер для содержимого, который будет прокручиваться
    local buffsContentContainer = api.Interface:CreateWidget('window', 'buffsContentContainer', buffsListContainer)
    buffsContentContainer:SetWidth(540) -- Ширина с отступами
    -- Прикрепляем контент к левому верхнему углу с отступами
    buffsContentContainer:RemoveAllAnchors()
    buffsContentContainer:AddAnchor("TOPLEFT", buffsListContainer, 10, 5)
    buffsContentContainer:Show(true)
    
    settingsControls.buffsListContainer = buffsListContainer
    settingsControls.buffsContentContainer = buffsContentContainer
    
    -- Текущая позиция прокрутки
    -- Храним отображаемые в данный момент элементы списка
    local visibleBuffs = {}
    
    -- Функция обновления видимых элементов списка с пагинацией
    local function updateVisibleItems()
        -- Получаем ссылки на необходимые элементы
        local container = settingsControls.buffsListContainer
        
        -- Получаем список отслеживаемых бафов
        local trackedBuffs = BuffsToTrack.GetAllTrackedBuffIds(currentUnitType)
        
        -- Очищаем предыдущие элементы
        for _, widget in ipairs(visibleBuffs) do
            if widget then
                widget:Show(false)
                widget:RemoveAllAnchors()
                widget = nil
            end
        end
        visibleBuffs = {}
        
        -- Определяем размер видимой области
        local itemHeight = 23
        
        -- Вычисляем общее количество страниц
        local totalPages = math.max(1, math.ceil(#trackedBuffs / buffsPerPage))
        
        -- Корректируем текущую страницу если нужно
        if buffListPage > totalPages then buffListPage = totalPages end
        if buffListPage < 1 then buffListPage = 1 end
        
        -- Вычисляем диапазон элементов для текущей страницы
        local startIndex = (buffListPage - 1) * buffsPerPage + 1
        local endIndex = math.min(startIndex + buffsPerPage - 1, #trackedBuffs)
        
        -- Обновляем индикатор страницы
        if settingsControls.buffPageIndicator then
            settingsControls.buffPageIndicator:SetText(buffListPage .. "/" .. totalPages)
        end
        
        -- Если список пуст, показываем сообщение
        if #trackedBuffs == 0 then
            local emptyLabel = helpers.createLabel('emptyBuffsList', container, "Buffs list is empty", 0, 0, 16)
            emptyLabel:SetWidth(500)
            emptyLabel:AddAnchor("TOP", container, 0, 20)
            emptyLabel.style:SetAlign(ALIGN.CENTER)
            emptyLabel:Show(true)
            table.insert(visibleBuffs, emptyLabel)
            return
        end
        
        -- Создаем видимые элементы списка для текущей страницы
        local yOffset = 8
        
        for i = startIndex, endIndex do
            local buffId = trackedBuffs[i]
            if not buffId then break end
            
            -- Get buff name if possible
            local buffName = BuffList.GetBuffName(buffId) or ("Buff #" .. buffId)
            
            -- Create row with buff information
            local buffRow = api.Interface:CreateWidget('window', 'trackedBuff_' .. i, container)
            buffRow:SetExtent(520, 20) -- Ширина и высота строки
            buffRow:AddAnchor("TOPLEFT", container, 15, yOffset)
            buffRow:Show(true)
            
            -- Buff ID
            local buffIdLabel = helpers.createLabel('buffIdLabel_' .. i, buffRow, tostring(buffId), 0, 0, 14)
            buffIdLabel:SetExtent(70, 20)
            buffIdLabel:Show(true)
            
            -- Buff name
            local buffNameLabel = helpers.createLabel('buffNameLabel_' .. i, buffRow, buffName, 80, 0, 14)
            buffNameLabel:SetExtent(330, 20)
            buffNameLabel:Show(true)
            
            -- Remove button
            local removeButton = helpers.createButton('removeBuffButton_' .. i, buffRow, 'Remove', 410, 0)
            removeButton:SetExtent(100, 20)
            removeButton:Show(true)
            
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
                    api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
                end
            end)
            
            -- Добавляем элементы в список видимых
            table.insert(visibleBuffs, buffRow)
            yOffset = yOffset + itemHeight
        end
        
        -- Убедимся, что остальные элементы интерфейса не были затронуты
        if settingsControls.newBuffIdLabel then
            settingsControls.newBuffIdLabel:Show(true)
        end
        if settingsControls.iconGroupLabel then
            settingsControls.iconGroupLabel:Show(true)
        end
        if settingsControls.positionLabel then
            settingsControls.positionLabel:Show(true)
        end
        if settingsControls.timerGroupLabel then
            settingsControls.timerGroupLabel:Show(true)
        end
    end
    
    -- Кнопки пагинации для buff list
    local buffPrevButton = helpers.createButton('buffPrevButton', buffsListContainer, '<', 0, 0)
    buffPrevButton:SetExtent(30, 25)
    buffPrevButton:RemoveAllAnchors()
    buffPrevButton:AddAnchor("BOTTOMLEFT", buffsListContainer, "BOTTOMLEFT", 10, -5)
    buffPrevButton:SetHandler("OnClick", function()
        if buffListPage > 1 then
            buffListPage = buffListPage - 1
            updateVisibleItems()
        end
    end)
    buffPrevButton:Show(true)
    settingsControls.buffPrevButton = buffPrevButton
    
    -- Индикатор страницы
    local buffPageIndicator = helpers.createLabel('buffPageIndicator', buffsListContainer, "1/1", 0, 0, 14)
    buffPageIndicator:SetExtent(50, 25)
    buffPageIndicator:RemoveAllAnchors()
    buffPageIndicator:AddAnchor("LEFT", buffPrevButton, "RIGHT", 5, 0)
    buffPageIndicator.style:SetAlign(ALIGN.CENTER)
    buffPageIndicator:Show(true)
    settingsControls.buffPageIndicator = buffPageIndicator
    
    local buffNextButton = helpers.createButton('buffNextButton', buffsListContainer, '>', 0, 0)
    buffNextButton:SetExtent(30, 25)
    buffNextButton:RemoveAllAnchors()
    buffNextButton:AddAnchor("LEFT", buffPageIndicator, "RIGHT", 5, 0)
    buffNextButton:SetHandler("OnClick", function()
        local trackedBuffs = BuffsToTrack.GetAllTrackedBuffIds(currentUnitType)
        local totalPages = math.max(1, math.ceil(#trackedBuffs / buffsPerPage))
        if buffListPage < totalPages then
            buffListPage = buffListPage + 1
            updateVisibleItems()
        end
    end)
    buffNextButton:Show(true)
    settingsControls.buffNextButton = buffNextButton
    
    -- Сохраняем функцию обновления в контролах
    settingsControls.updateVisibleItems = updateVisibleItems
    
    -- IMMEDIATELY fill list of tracked buffs
    updateTrackedBuffsList(true)

    -- THIRD BLOCK - Input field for new tracked buff (перемещаем его выше списка пользовательских баффов)
    local newBuffIdLabel = helpers.createLabel('newBuffIdLabel', settingsWindow, 'Buff ID:', 15, 0, 15)
    newBuffIdLabel:SetWidth(100)
    newBuffIdLabel:Show(true)
    settingsControls.newBuffIdLabel = newBuffIdLabel
    
    -- Явно размещаем поле ввода нового баффа после списка обычных баффов
    newBuffIdLabel:RemoveAllAnchors()
    newBuffIdLabel:AddAnchor("TOPLEFT", buffsListContainer, "BOTTOMLEFT", 0, 30)
    
    local newBuffId = helpers.createEdit('newBuffId', newBuffIdLabel, "", 52, 0)
    if newBuffId then 
        newBuffId:SetMaxTextLength(10) 
        newBuffId:SetWidth(80)
        newBuffId:Show(true)
    end
    settingsControls.newBuffId = newBuffId
    
    -- Add buff button
    local addBuffButton = helpers.createButton('addBuffButton', newBuffIdLabel, 'Add', 140, -7)
    addBuffButton:SetWidth(100)
    addBuffButton:Show(true)
    settingsControls.addBuffButton = addBuffButton
    addBuffButton:SetHandler("OnClick", addTrackedBuff)
    
    -- Create highlighted panel for error messages
    local errorPanel = api.Interface:CreateWidget('window', 'errorPanel', settingsWindow)
    errorPanel:SetExtent(320, 25)
    errorPanel:RemoveAllAnchors()
    errorPanel:AddAnchor("TOPLEFT", newBuffIdLabel, "BOTTOMLEFT", 250, -22)
    
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
    addBuffError:Show(true)
    settingsControls.addBuffError = addBuffError
    
    -- By default error panel is hidden
    errorPanel:Show(false)
    settingsControls.errorPanel = errorPanel

    -- CUSTOM BUFFS LIST (перемещаем после поля ввода Buff ID)
    local customBuffsListHeader = helpers.createLabel('customBuffsListHeader', trackedBuffsGroupLabel,
                                                    'Custom Buffs:', 0, 30, 16)
    customBuffsListHeader:SetWidth(570)
    customBuffsListHeader:Show(true)
    settingsControls.customBuffsListHeader = customBuffsListHeader
    
    -- Явно размещаем заголовок для пользовательских баффов после панели ошибок ввода Buff ID
    customBuffsListHeader:RemoveAllAnchors()
    customBuffsListHeader:AddAnchor("TOPLEFT", newBuffIdLabel, "BOTTOMLEFT", 0, 10)
    
    -- Контейнер для списка пользовательских баффов
    local customBuffsListContainer = api.Interface:CreateWidget('window', 'customBuffsListContainer', customBuffsListHeader)
    customBuffsListContainer:SetExtent(570, 115)
    customBuffsListContainer:AddAnchor("TOPLEFT", customBuffsListHeader, 0, 35)
    customBuffsListContainer:Show(true)
    customBuffsListContainer:Clickable(true)
    
    -- Enable scissor clipping to prevent elements from rendering outside container bounds
    if customBuffsListContainer.EnableScissor then
        customBuffsListContainer:EnableScissor(true)
    end
    
    settingsControls.customBuffsListContainer = customBuffsListContainer

    -- Рамка для контейнера
    local customContainerBorder = customBuffsListContainer:CreateNinePartDrawable("ui/chat_option.dds", "artwork")
    customContainerBorder:SetCoords(0, 0, 27, 16)
    customContainerBorder:SetInset(9, 8, 9, 7)
    customContainerBorder:AddAnchor("TOPLEFT", customBuffsListContainer, -1, -1)
    customContainerBorder:AddAnchor("BOTTOMRIGHT", customBuffsListContainer, 1, 1)

    -- Фон для контейнера
    local customContainerBg = customBuffsListContainer:CreateColorDrawable(0.92, 0.92, 0.92, 1, "background")
    customContainerBg:AddAnchor("TOPLEFT", customBuffsListContainer, 0, 0)
    customContainerBg:AddAnchor("BOTTOMRIGHT", customBuffsListContainer, 0, 0)

     -- Внутренний контейнер для прокручиваемого содержимого
     local customBuffsContentContainer = api.Interface:CreateWidget('window', 'customBuffsContentContainer', customBuffsListContainer)
     customBuffsContentContainer:SetWidth(540)
     customBuffsContentContainer:RemoveAllAnchors()
     customBuffsContentContainer:AddAnchor("TOPLEFT", customBuffsListContainer, 10, 5)
     customBuffsContentContainer:Show(true)
     settingsControls.customBuffsContentContainer = customBuffsContentContainer

    -- Функция обновления видимых элементов списка пользовательских баффов с пагинацией
    local function updateCustomVisibleItems()
        local container = settingsControls.customBuffsListContainer

        local customBuffs = settings.customBuffs or {}

        -- Очищаем предыдущие элементы
        for _, widget in ipairs(customBuffsList) do
            if widget then
                widget:Show(false)
                widget:RemoveAllAnchors()
                widget = nil
            end
        end
        customBuffsList = {}

        local itemHeight = 23
        
        -- Вычисляем общее количество страниц
        local totalPages = math.max(1, math.ceil(#customBuffs / customsPerPage))
        
        -- Корректируем текущую страницу если нужно
        if customBuffPage > totalPages then customBuffPage = totalPages end
        if customBuffPage < 1 then customBuffPage = 1 end
        
        -- Вычисляем диапазон элементов для текущей страницы
        local startIndex = (customBuffPage - 1) * customsPerPage + 1
        local endIndex = math.min(startIndex + customsPerPage - 1, #customBuffs)
        
        -- Обновляем индикатор страницы
        if settingsControls.customPageIndicator then
            settingsControls.customPageIndicator:SetText(customBuffPage .. "/" .. totalPages)
        end

        -- Если список пуст, показываем сообщение
        if #customBuffs == 0 then
            local emptyLabel = helpers.createLabel('emptyCustomBuffsList', container, "Custom buffs list is empty", 0, 0, 16)
            emptyLabel:SetWidth(500)
            emptyLabel:AddAnchor("TOP", container, 0, 20)
            emptyLabel.style:SetAlign(ALIGN.CENTER)
            emptyLabel:Show(true)
            table.insert(customBuffsList, emptyLabel)
            return
        end

        -- Создаем видимые элементы для текущей страницы
        local yOffset = 8

        for i = startIndex, endIndex do
            local buffData = customBuffs[i]
            if not buffData or not buffData.id then break end

            local buffRow = api.Interface:CreateWidget('window', 'customBuff_' .. i, container)
            buffRow:SetExtent(520, 20)
            buffRow:AddAnchor("TOPLEFT", container, 15, yOffset)
            buffRow:Show(true)

            -- ID
            local buffIdLabel = helpers.createLabel('customBuffIdLabel_' .. i, buffRow, tostring(buffData.id), 0, 0, 14)
            buffIdLabel:SetExtent(50, 20)
            buffIdLabel:Show(true)

            -- Name
            local buffNameLabel = helpers.createLabel('customBuffNameLabel_' .. i, buffRow, buffData.name, 80, 0, 14)
            buffNameLabel:SetExtent(200, 20)
            buffNameLabel:Show(true)

            -- Cooldown
            local buffCooldownLabel = helpers.createLabel('customBuffCooldownLabel_' .. i, buffRow, tostring(buffData.cooldown), 270, 0, 14)
            buffCooldownLabel:SetExtent(50,20)
            buffCooldownLabel:Show(true)

            -- timeOfAction
            local buffTimeOfActionLabel = helpers.createLabel('customBuffTimeOfAction_' .. i, buffRow, tostring(buffData.timeOfAction), 330, 0, 14)
            buffTimeOfActionLabel:SetExtent(50, 20)
            buffTimeOfActionLabel:Show(true)

            -- Remove button
            local removeButton = helpers.createButton('removeCustomBuffButton_' .. i, buffRow, 'Remove', 410, 0)
            removeButton:SetExtent(100, 20)
            removeButton:Show(true)

            -- Remove button handler
            removeButton:SetHandler("OnClick", function()
                table.remove(settings.customBuffs, i)
                updateCustomBuffsList()
                if helpers and helpers.updateSettings then
                    helpers.updateSettings()
                end
            end)

            table.insert(customBuffsList, buffRow)
            yOffset = yOffset + itemHeight
        end
    end

    -- Кнопки пагинации для custom buffs list
    local customPrevButton = helpers.createButton('customPrevButton', customBuffsListContainer, '<', 0, 0)
    customPrevButton:SetExtent(30, 25)
    customPrevButton:RemoveAllAnchors()
    customPrevButton:AddAnchor("BOTTOMLEFT", customBuffsListContainer, "BOTTOMLEFT", 10, -5)
    customPrevButton:SetHandler("OnClick", function()
        if customBuffPage > 1 then
            customBuffPage = customBuffPage - 1
            updateCustomVisibleItems()
        end
    end)
    customPrevButton:Show(true)
    settingsControls.customPrevButton = customPrevButton
    
    -- Индикатор страницы
    local customPageIndicator = helpers.createLabel('customPageIndicator', customBuffsListContainer, "1/1", 0, 0, 14)
    customPageIndicator:SetExtent(50, 25)
    customPageIndicator:RemoveAllAnchors()
    customPageIndicator:AddAnchor("LEFT", customPrevButton, "RIGHT", 5, 0)
    customPageIndicator.style:SetAlign(ALIGN.CENTER)
    customPageIndicator:Show(true)
    settingsControls.customPageIndicator = customPageIndicator
    
    local customNextButton = helpers.createButton('customNextButton', customBuffsListContainer, '>', 0, 0)
    customNextButton:SetExtent(30, 25)
    customNextButton:RemoveAllAnchors()
    customNextButton:AddAnchor("LEFT", customPageIndicator, "RIGHT", 5, 0)
    customNextButton:SetHandler("OnClick", function()
        local customBuffs = settings.customBuffs or {}
        local totalPages = math.max(1, math.ceil(#customBuffs / customsPerPage))
        if customBuffPage < totalPages then
            customBuffPage = customBuffPage + 1
            updateCustomVisibleItems()
        end
    end)
    customNextButton:Show(true)
    settingsControls.customNextButton = customNextButton

    settingsControls.updateCustomVisibleItems = updateCustomVisibleItems
    updateCustomBuffsList(true) -- Инициализация списка

    -- CUSTOM BUFF INPUTS
    local customBuffInputsLabel = helpers.createLabel('customBuffInputsLabel', settingsWindow,
                                                    'Add Custom Buff:', 15, 0, 18)
    customBuffInputsLabel:SetWidth(570)
    customBuffInputsLabel:Show(true)
    settingsControls.customBuffInputsLabel = customBuffInputsLabel
    
    -- Явно размещаем заголовок блока добавления пользовательских баффов
    customBuffInputsLabel:RemoveAllAnchors()
    customBuffInputsLabel:AddAnchor("TOPLEFT", customBuffsListContainer, "BOTTOMLEFT", 0, 20)

    -- Debug Buff ID button (ON/OFF toggle)
    local debugButtonText = settings.debugBuffId and "Debug: ON" or "Debug: OFF"
    local debugBuffButton = helpers.createButton('debugBuffButton', customBuffInputsLabel, debugButtonText, 250, -5)
    if debugBuffButton then
        debugBuffButton:SetExtent(100, 25)
        debugBuffButton:Show(true)
        
        -- Toggle handler for debug button
        debugBuffButton:SetHandler("OnClick", function()
            -- Toggle state
            settings.debugBuffId = not settings.debugBuffId
            
            -- Update button text
            debugBuffButton:SetText(settings.debugBuffId and "Debug: ON" or "Debug: OFF")
            
            -- Save settings
            local mainSettings = api.GetSettings("CooldawnBuffTracker")
            mainSettings.debugBuffId = settings.debugBuffId
            api.SaveSettings()
            
            -- Reinitialize/shutdown debugger based on new setting
            local BuffDebugger = require("CooldawnBuffTracker/buff_debugger")
            if settings.debugBuffId then
                if BuffDebugger and BuffDebugger.Initialize then
                    BuffDebugger.Initialize()
                end
            else
                if BuffDebugger and BuffDebugger.Shutdown then
                    BuffDebugger.Shutdown()
                end
            end
        end)
    end
    settingsControls.debugBuffButton = debugBuffButton
    
    -- Поле ID
    local newCustomBuffIdLabel = helpers.createLabel('newCustomBuffIdLabel', customBuffInputsLabel, 'ID:', 0, 30, 14)
    newCustomBuffIdLabel:SetWidth(100)
    newCustomBuffIdLabel:Show(true)
    
    local newCustomBuffId = helpers.createEdit('newCustomBuffId', newCustomBuffIdLabel, "", 20, 0)
    newCustomBuffId:SetWidth(100)
    newCustomBuffId:Show(true)
    settingsControls.newCustomBuffId = newCustomBuffId
    
    -- Поле Name
    local newCustomBuffNameLabel = helpers.createLabel('newCustomBuffNameLabel', customBuffInputsLabel, 'NM:', 125, 30, 14)
    newCustomBuffNameLabel:SetWidth(100)
    newCustomBuffNameLabel:Show(true)
    
    local newCustomBuffName = helpers.createEdit('newCustomBuffName', newCustomBuffNameLabel, "", 30, 0)
    newCustomBuffName:SetWidth(100)
    newCustomBuffName:Show(true)
    settingsControls.newCustomBuffName = newCustomBuffName
    
    -- Поле Cooldown
    local newCustomBuffCooldownLabel = helpers.createLabel('newCustomBuffCooldownLabel', customBuffInputsLabel, 'CD:', 260, 30, 14)
    newCustomBuffCooldownLabel:SetWidth(100)
    newCustomBuffCooldownLabel:Show(true)
    
    local newCustomBuffCooldown = helpers.createEdit('newCustomBuffCooldown', newCustomBuffCooldownLabel, "", 30, 0)
    newCustomBuffCooldown:SetWidth(100)
    newCustomBuffCooldown:Show(true)
    settingsControls.newCustomBuffCooldown = newCustomBuffCooldown
    
    -- Поле Duration
    local newCustomBuffTimeOfActionLabel = helpers.createLabel('newCustomBuffTimeOfActionLabel', customBuffInputsLabel, 'D:', 395, 30, 14)
    newCustomBuffTimeOfActionLabel:SetWidth(100)
    newCustomBuffTimeOfActionLabel:Show(true)
    
    local newCustomBuffTimeOfAction = helpers.createEdit('newCustomBuffTimeOfAction', newCustomBuffTimeOfActionLabel, "", 25, 0)
    newCustomBuffTimeOfAction:SetWidth(100)
    newCustomBuffTimeOfAction:Show(true)
    settingsControls.newCustomBuffTimeOfAction = newCustomBuffTimeOfAction
    
    -- Кнопка добавления пользовательского баффа
    local addCustomBuffButton = helpers.createButton('addCustomBuffButton', customBuffInputsLabel, 'Add Custom Buff', 355, 60)
    addCustomBuffButton:SetWidth(150)
    addCustomBuffButton:Show(true)
    settingsControls.addCustomBuffButton = addCustomBuffButton
    addCustomBuffButton:SetHandler("OnClick", addCustomBuff)
    
    -- Панель ошибок для пользовательских баффов
    local customBuffErrorPanel = api.Interface:CreateWidget('window', 'customBuffErrorPanel', settingsWindow)
    customBuffErrorPanel:SetExtent(350, 25)
    customBuffErrorPanel:RemoveAllAnchors()
    customBuffErrorPanel:AddAnchor("TOPLEFT", customBuffInputsLabel, "BOTTOMLEFT", 0, 45)
    customBuffErrorPanel:Show(false)
    settingsControls.customBuffErrorPanel = customBuffErrorPanel
    
    -- Рамка для панели ошибок пользовательских баффов
    local customErrorPanelBorder = customBuffErrorPanel:CreateNinePartDrawable("ui/chat_option.dds", "artwork")
    customErrorPanelBorder:SetCoords(0, 0, 27, 16)
    customErrorPanelBorder:SetInset(0, 8, 0, 7)
    customErrorPanelBorder:AddAnchor("TOPLEFT", customBuffErrorPanel, -1, -1)
    customErrorPanelBorder:AddAnchor("BOTTOMRIGHT", customBuffErrorPanel, 1, 1)

    -- Фон для панели ошибок
    local customErrorPanelBg = customBuffErrorPanel:CreateColorDrawable(0.98, 0.85, 0.85, 0.9, "background")
    customErrorPanelBg:AddAnchor("TOPLEFT", customBuffErrorPanel, 0, 0)
    customErrorPanelBg:AddAnchor("BOTTOMRIGHT", customBuffErrorPanel, 0, 0)

    -- Текст ошибки
    local addCustomBuffError = helpers.createLabel('addCustomBuffError', customBuffErrorPanel, '', 5, 5, 14)
    addCustomBuffError:SetExtent(560, 20)
    addCustomBuffError.style:SetColor(1, 0, 0, 1)
    addCustomBuffError:Show(true)
    settingsControls.addCustomBuffError = addCustomBuffError

    -- FOURTH BLOCK - Icon settings
    local iconGroupLabel = helpers.createLabel('iconGroupLabel', settingsWindow,
                                             'Icon settings', 15, 0, 20)
    iconGroupLabel:SetWidth(570)
    iconGroupLabel:Show(true)
    settingsControls.iconGroupLabel = iconGroupLabel
    
    -- Явно устанавливаем якорь для группы настроек иконок
    iconGroupLabel:RemoveAllAnchors()
    iconGroupLabel:AddAnchor("TOPLEFT", customBuffErrorPanel, "BOTTOMLEFT", 0, 20)
    
    -- Icon size
    local iconSizeLabel = helpers.createLabel('iconSizeLabel', iconGroupLabel,
                                            'Icon size:', 0, 25, 15)
    iconSizeLabel:SetWidth(150) -- Set label width
    iconSizeLabel:Show(true)
    
    local iconSize = helpers.createEdit('iconSize', iconSizeLabel,
                                      tostring(settings[currentUnitType] and settings[currentUnitType].iconSize or 40), 200, 0)
    if iconSize then 
        iconSize:SetMaxTextLength(4) 
        iconSize:SetWidth(50) -- Increase input field width
        iconSize:Show(true)
    end
    settingsControls.iconSize = iconSize
    
    -- Icon spacing
    local iconSpacingLabel = helpers.createLabel('iconSpacingLabel', iconSizeLabel,
                                               'Icon spacing:', 0, 25, 15)
    iconSpacingLabel:SetWidth(150) -- Set label width
    iconSpacingLabel:Show(true)
    
    local iconSpacing = helpers.createEdit('iconSpacing', iconSpacingLabel,
                                         tostring(settings[currentUnitType] and settings[currentUnitType].iconSpacing or 5), 200, 0)
    if iconSpacing then 
        iconSpacing:SetMaxTextLength(4) 
        iconSpacing:SetWidth(50) -- Increase input field width
        iconSpacing:Show(true)
    end
    settingsControls.iconSpacing = iconSpacing
    
    -- Icon position settings
    local positionLabel = helpers.createLabel('positionLabel', iconSpacingLabel,
                                            'Icon position', 0, 35, 18)
    positionLabel:SetWidth(570)
    positionLabel:Show(true)
    settingsControls.positionLabel = positionLabel
    
    -- Явно устанавливаем якорь для группы настроек позиционирования
    positionLabel:RemoveAllAnchors()
    positionLabel:AddAnchor("TOPLEFT", iconSpacingLabel, "BOTTOMLEFT", 0, 20)
    
    -- X coordinate
    local posXLabel = helpers.createLabel('posXLabel', positionLabel,
                                        'Position X:', 0, 25, 15)
    posXLabel:SetWidth(150) -- Set label width
    posXLabel:Show(true)
    
    local posX = helpers.createEdit('posX', posXLabel,
                                  tostring(settings[currentUnitType] and settings[currentUnitType].posX or 0), 200, 0)
    if posX then 
        posX:SetMaxTextLength(6) 
        posX:SetWidth(50) -- Increase input field width
        posX:Show(true)
    end
    settingsControls.posX = posX
    
    -- Y coordinate
    local posYLabel = helpers.createLabel('posYLabel', posXLabel,
                                        'Position Y:', 0, 25, 15)
    posYLabel:SetWidth(150) -- Set label width
    posYLabel:Show(true)
    
    local posY = helpers.createEdit('posY', posYLabel,
                                  tostring(settings[currentUnitType] and settings[currentUnitType].posY or 0), 200, 0)
    if posY then 
        posY:SetMaxTextLength(6) 
        posY:SetWidth(50) -- Increase input field width
        posY:Show(true)
    end
    settingsControls.posY = posY
    
    -- Lock positioning button (ON/OFF toggle)
    local lockIsOn = settings[currentUnitType] and settings[currentUnitType].lockPositioning or false
    local lockButtonText = lockIsOn and "Lock: ON" or "Lock: OFF"
    local lockButton = helpers.createButton('lockButton', posYLabel, lockButtonText, 0, 25)
    if lockButton then
        lockButton:SetExtent(100, 25)
        lockButton:Show(true)
        
        -- Toggle handler for lock button
        lockButton:SetHandler("OnClick", function()
            -- Toggle state
            local unitSettings = settings[currentUnitType] or {}
            unitSettings.lockPositioning = not unitSettings.lockPositioning
            settings[currentUnitType] = unitSettings
            
            -- Update button text
            lockButton:SetText(unitSettings.lockPositioning and "Lock: ON" or "Lock: OFF")
            
            -- Save settings
            local mainSettings = api.GetSettings("CooldawnBuffTracker")
            if not mainSettings[currentUnitType] then
                mainSettings[currentUnitType] = {}
            end
            mainSettings[currentUnitType].lockPositioning = unitSettings.lockPositioning
            api.SaveSettings()
            
            -- Notify main to update dragging state
            api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
        end)
    end
    settingsControls.lockButton = lockButton
    
    -- Timer settings group
    local timerGroupLabel = helpers.createLabel('timerGroupLabel', lockButton,
                                             'Timer settings', 0, 35, 18)
    timerGroupLabel:SetWidth(570)
    timerGroupLabel:Show(true)
    
    -- Явно устанавливаем якорь для группы настроек таймера
    timerGroupLabel:RemoveAllAnchors()
    timerGroupLabel:AddAnchor("TOPLEFT", lockButton, "BOTTOMLEFT", 0, 10)
    
    -- Timer font size
    local timerFontSizeLabel = helpers.createLabel('timerFontSizeLabel', timerGroupLabel,
                                                'Font size:', 0, 25, 15)
    timerFontSizeLabel:SetWidth(150) -- Set label width
    timerFontSizeLabel:Show(true)
    
    local timerFontSize = helpers.createEdit('timerFontSize', timerFontSizeLabel,
                                          tostring(settings[currentUnitType] and settings[currentUnitType].timerFontSize or 16), 200, 0)
    if timerFontSize then 
        timerFontSize:SetMaxTextLength(4) 
        timerFontSize:SetWidth(50) -- Increase input field width
        timerFontSize:Show(true)
    end
    settingsControls.timerFontSize = timerFontSize
    
    -- Timer text color
    local timerTextColorLabel = helpers.createLabel('timerTextColorLabel', timerFontSizeLabel,
                                                 'Text color:', 0, 25, 15)
    timerTextColorLabel:SetWidth(150) -- Set label width
    timerTextColorLabel:Show(true)
    
    -- Get timer text color from settings for selected unit type
    local unitSettings = settings[currentUnitType] or {}
    local textColor = unitSettings.timerTextColor or {r = 1, g = 1, b = 1, a = 1}
    
    local timerTextColor = helpers.createColorPickButton('timerTextColor', timerTextColorLabel, 
                                                      textColor, 200, 0)
    
    -- Configure color picker handler to save selected color
    if timerTextColor and timerTextColor.colorBG then
        timerTextColor:Show(true)
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
    
    -- Final check - call update one more time for confidence
    -- Force update list one more time
    updateTrackedBuffsList()
    updateCustomBuffsList()
    
    -- Force show all critical elements
    settingsControls.buffsListContainer:Show(true)
    settingsControls.trackedBuffsListHeader:Show(true)

    settingsControls.customBuffsListContainer:Show(true)
    settingsControls.customBuffsListHeader:Show(true)
    
    -- Явно показываем все ключевые элементы интерфейса
    if settingsControls.newBuffIdLabel then settingsControls.newBuffIdLabel:Show(true) end
    if settingsControls.newBuffId then settingsControls.newBuffId:Show(true) end
    if settingsControls.addBuffButton then settingsControls.addBuffButton:Show(true) end
    
    if settingsControls.iconGroupLabel then settingsControls.iconGroupLabel:Show(true) end
    if settingsControls.iconSize then settingsControls.iconSize:Show(true) end
    if settingsControls.iconSpacing then settingsControls.iconSpacing:Show(true) end
    
    if settingsControls.positionLabel then settingsControls.positionLabel:Show(true) end
    if settingsControls.posX then settingsControls.posX:Show(true) end
    if settingsControls.posY then settingsControls.posY:Show(true) end
    
    if settingsControls.timerGroupLabel then settingsControls.timerGroupLabel:Show(true) end
    if settingsControls.timerFontSize then settingsControls.timerFontSize:Show(true) end
    
    if settingsControls.errorPanel then
        settingsControls.errorPanel:Show(false)
    end

    if settingsControls.customBuffErrorPanel then
        settingsControls.customBuffErrorPanel:Show(false)
    end

    -- Добавляем вызов функции создания кнопки в конец функции инициализации окна настроек
    addPixelViewerButton()
end

local function Unload()
    if settingsWindow ~= nil then
        settingsWindow:Show(false)
        settingsWindow = nil
    end
    
    -- Close palette if it's open
    local F_ETC = require('CooldawnBuffTracker/util/etc')
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

        -- Update custom buffs list
        updateCustomBuffsList()
        
        -- Hide error panel on each window opening
        if settingsControls.errorPanel then
            settingsControls.errorPanel:Show(false)
        end

        if settingsControls.customBuffErrorPanel then
            settingsControls.customBuffErrorPanel:Show(false)
        end
        
        -- Явно показываем все ключевые элементы интерфейса
        if settingsControls.newBuffIdLabel then settingsControls.newBuffIdLabel:Show(true) end
        if settingsControls.newBuffId then settingsControls.newBuffId:Show(true) end
        if settingsControls.addBuffButton then settingsControls.addBuffButton:Show(true) end

        if settingsControls.customBuffInputsLabel then settingsControls.customBuffInputsLabel:Show(true) end
        if settingsControls.newCustomBuffId then settingsControls.newCustomBuffId:Show(true) end
        if settingsControls.newCustomBuffName then settingsControls.newCustomBuffName:Show(true) end
        if settingsControls.newCustomBuffCooldown then settingsControls.newCustomBuffCooldown:Show(true) end
        if settingsControls.newCustomBuffTimeOfAction then settingsControls.newCustomBuffTimeOfAction:Show(true) end
        if settingsControls.addCustomBuffButton then settingsControls.addCustomBuffButton:Show(true) end
        
        if settingsControls.iconGroupLabel then settingsControls.iconGroupLabel:Show(true) end
        if settingsControls.iconSize then settingsControls.iconSize:Show(true) end
        if settingsControls.iconSpacing then settingsControls.iconSpacing:Show(true) end
        
        if settingsControls.positionLabel then settingsControls.positionLabel:Show(true) end
        if settingsControls.posX then settingsControls.posX:Show(true) end
        if settingsControls.posY then settingsControls.posY:Show(true) end
        
        if settingsControls.timerGroupLabel then settingsControls.timerGroupLabel:Show(true) end
        if settingsControls.timerFontSize then settingsControls.timerFontSize:Show(true) end
        
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
    if settingsControls.posX and settingsControls.posY then
        settingsControls.posX:SetText(tostring(x))
        settingsControls.posY:SetText(tostring(y))
    end
end

local settings_page = {
    Load = initSettingsPage,
    Unload = Unload,
    openSettingsWindow = openSettingsWindow,
    updatePositionFields = updatePositionFields,
    openPixelWindow = pixelViewer.openPixelWindow
}

return settings_page
