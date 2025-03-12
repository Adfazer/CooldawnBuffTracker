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

-- Обновляет список отслеживаемых баффов в интерфейсе
local function updateTrackedBuffsList()
    -- Очищаем предыдущие элементы списка
    for _, widget in ipairs(trackedBuffsList) do
        pcall(function()
            if widget then
                widget:Show(false)
                widget:RemoveAllAnchors()
            end
        end)
    end
    trackedBuffsList = {}
    
    -- Получаем актуальный список отслеживаемых баффов для выбранного типа юнита
    local trackedBuffs = BuffsToTrack.GetAllTrackedBuffIds(currentUnitType)
    
    -- Ссылка на родительский элемент для списка
    local container = settingsControls.buffsListContainer
    local yOffset = 0
    
    -- Если список пуст, показываем выделенное сообщение
    if #trackedBuffs == 0 then
        -- Проверяем настройку, чтобы понять, отключено ли отслеживание полностью
        local settings = api.GetSettings("CooldawnBuffTracker") or {}
        local isTrackingDisabled = settings[currentUnitType] and settings[currentUnitType].enabled == false
        
        -- Создаем фон для пустого списка, с цветом в зависимости от статуса отслеживания
        local bgColor = isTrackingDisabled and {r=0.2, g=0.8, b=0.2, a=0.3} or {r=0.9, g=0.7, b=0.7, a=0.5}
        local emptyBg = container:CreateColorDrawable(bgColor.r, bgColor.g, bgColor.b, bgColor.a, "background")
        emptyBg:AddAnchor("TOPLEFT", container, 10, 10)
        emptyBg:AddAnchor("BOTTOMRIGHT", container, -10, -10)
        table.insert(trackedBuffsList, emptyBg)
        
        -- Добавляем текст для пустого списка в зависимости от статуса отслеживания
        local unitName = currentUnitType == "playerpet" and "mount" or "player"
        local messageText = isTrackingDisabled 
            and "Buff tracking for " .. unitName .. " is disabled" 
            or "Buff list for " .. unitName .. " is empty! Add new buff below."
        
        local messageColor = isTrackingDisabled and {r=0, g=0.6, b=0, a=1} or {r=0.8, g=0, b=0, a=1}
        
        local emptyLabel = helpers.createLabel('emptyTrackedBuffsList', container, messageText, 0, 40, 16)
        emptyLabel:SetWidth(550) -- Увеличиваем ширину сообщения
        emptyLabel:AddAnchor("TOP", container, 0, 40) -- Центрируем сообщение
        emptyLabel.style:SetAlign(ALIGN.CENTER) -- Центрируем текст
        emptyLabel.style:SetColor(messageColor.r, messageColor.g, messageColor.b, messageColor.a)
        table.insert(trackedBuffsList, emptyLabel)
        
        -- Устанавливаем минимальную высоту контейнера
        container:SetHeight(100)
        return
    end
    
    -- Создаем список отслеживаемых баффов
    for i, buffId in ipairs(trackedBuffs) do
        -- Получаем название баффа, если возможно
        local buffName = "Buff #" .. buffId
        pcall(function()
            buffName = BuffList.GetBuffName(buffId) or buffName
        end)
        
        -- Создаем строку с информацией о баффе
        local buffRow = api.Interface:CreateWidget('window', 'trackedBuff_' .. i, container)
        buffRow:SetExtent(550, 20) -- Увеличиваем ширину строки списка
        buffRow:AddAnchor("TOPLEFT", container, 10, yOffset)
        
        -- ID баффа
        local buffIdLabel = helpers.createLabel('buffIdLabel_' .. i, buffRow, tostring(buffId), 0, 0, 14)
        buffIdLabel:SetExtent(70, 20) -- Увеличиваем ширину поля ID
        
        -- Название баффа
        local buffNameLabel = helpers.createLabel('buffNameLabel_' .. i, buffRow, buffName, 80, 0, 14)
        buffNameLabel:SetExtent(350, 20) -- Увеличиваем ширину поля названия
        
        -- Кнопка удаления
        local removeButton = helpers.createButton('removeBuffButton_' .. i, buffRow, 'Remove', 440, 0)
        removeButton:SetExtent(100, 20) -- Увеличиваем ширину кнопки удаления
        
        -- Обработчик кнопки удаления
        removeButton:SetHandler("OnClick", function()
            if BuffsToTrack.RemoveTrackedBuff(buffId, currentUnitType) then
                -- Обновляем список после удаления
                updateTrackedBuffsList()
                -- Обновляем основной интерфейс
                if helpers and helpers.updateSettings then
                    helpers.updateSettings()
                end
                
                -- Явно вызываем событие обновления списка отслеживаемых баффов
                pcall(function()
                    api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
                end)
            end
        end)
        
        yOffset = yOffset + 25
        table.insert(trackedBuffsList, buffRow)
    end
    
    -- Устанавливаем правильную высоту контейнера, чтобы он вмещал все элементы
    local containerHeight = math.max(100, yOffset + 30)
    container:SetHeight(containerHeight)
end

local function saveSettings()
    -- Получаем текущие настройки
    local mainSettings = api.GetSettings("CooldawnBuffTracker")
    
    -- Обновляем значения из контролов для выбранного типа юнита
    if not mainSettings[currentUnitType] then
        mainSettings[currentUnitType] = {}
    end
    
    -- Обновляем настройки размера иконок
    mainSettings[currentUnitType].iconSize = tonumber(settingsControls.iconSize:GetText())
    mainSettings[currentUnitType].iconSpacing = tonumber(settingsControls.iconSpacing:GetText())
    
    -- Проверяем правильность значений и устанавливаем значения по умолчанию, если нужно
    if not mainSettings[currentUnitType].iconSize or mainSettings[currentUnitType].iconSize <= 0 then 
        mainSettings[currentUnitType].iconSize = 40 
    end
    
    if not mainSettings[currentUnitType].iconSpacing or mainSettings[currentUnitType].iconSpacing < 0 then 
        mainSettings[currentUnitType].iconSpacing = 5
    end
    
    -- Обновляем настройки позиции
    mainSettings[currentUnitType].posX = tonumber(settingsControls.posX:GetText())
    mainSettings[currentUnitType].posY = tonumber(settingsControls.posY:GetText())
    mainSettings[currentUnitType].lockPositioning = settingsControls.lockPositioning:GetChecked()
    
    -- Сохраняем настройки таймера
    if settingsControls.timerFontSize then
        mainSettings[currentUnitType].timerFontSize = tonumber(settingsControls.timerFontSize:GetText())
    end
    
    if settingsControls.timerTextColor and settingsControls.timerTextColor.colorBG then
        mainSettings[currentUnitType].timerTextColor = {r = 0, g = 0, b = 0, a = 1}
        mainSettings[currentUnitType].timerTextColor.r, mainSettings[currentUnitType].timerTextColor.g, mainSettings[currentUnitType].timerTextColor.b = 
            settingsControls.timerTextColor.colorBG:GetColor()
    end
    
    -- Сохраняем настройки отладки (общие для всех типов юнитов)
    if settingsControls.debugBuffId then
        mainSettings.debugBuffId = settingsControls.debugBuffId:GetChecked()
    end
    
    -- Сохраняем настройки и явно применяем
    api.SaveSettings()
    
    -- Сохраняем настройки через helpers, который полностью перезапустит UI
    if helpers and helpers.updateSettings then
        helpers.updateSettings()
    end
    
    -- Закрываем окно настроек
    settingsWindowClose()
end

local function resetSettings()
    pcall(function()
        -- Сбрасываем настройки на значения по умолчанию
        settings = helpers.resetSettingsToDefault()
        
        -- Обновляем значения в интерфейсе для текущего типа юнита
        local unitSettings = settings[currentUnitType] or {}
        
        -- Обновляем поля настроек для выбранного типа юнита
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
        
        -- Обновляем настройки таймера
        if settingsControls.timerFontSize then
            settingsControls.timerFontSize:SetText(tostring(unitSettings.timerFontSize or 16))
        end
        
        -- Обновляем цвет текста таймера
        if settingsControls.timerTextColor and settingsControls.timerTextColor.colorBG then
            local textColor = unitSettings.timerTextColor or {r = 1, g = 1, b = 1, a = 1}
            settingsControls.timerTextColor.colorBG:SetColor(
                textColor.r or 1,
                textColor.g or 1,
                textColor.b or 1,
                1
            )
        end
        
        -- Обновляем настройки отладки (общие)
        if settingsControls.debugBuffId then
            settingsControls.debugBuffId:SetChecked(settings.debugBuffId or false)
        end
        
        -- Обновляем список отслеживаемых баффов
        updateTrackedBuffsList()
        
        -- Обновляем основной интерфейс
        if helpers and helpers.updateSettings then
            helpers.updateSettings()
        end
        
        -- Явно вызываем событие обновления списка отслеживаемых баффов
        pcall(function()
            api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
        end)
    end)
end

-- Добавление нового баффа
local function addTrackedBuff()
    -- Всегда обновляем список при любом взаимодействии
    updateTrackedBuffsList()
    
    local buffIdText = settingsControls.newBuffId:GetText()
    local buffId = tonumber(buffIdText)
    
    if not buffId then
        -- Показываем ошибку, если ID баффа не является числом
        if settingsControls.addBuffError and settingsControls.errorPanel then
            settingsControls.addBuffError:SetText("Error: Buff ID must be a number")
            settingsControls.errorPanel:Show(true)
        end
        return
    end
    
    -- Проверяем наличие баффа в BuffList
    local isValidBuff = false
    pcall(function()
        -- Используем более надежную функцию для проверки существования баффа
        if BuffList and BuffList.IsValidBuff then
            isValidBuff = BuffList.IsValidBuff(buffId)
        else
            -- Запасной вариант: пытаемся получить иконку или имя баффа через BuffList
            local buffIcon = BuffList.GetBuffIcon(buffId)
            local buffName = BuffList.GetBuffName(buffId)
            
            -- Проверка существования баффа - если есть хотя бы иконка или специфическое имя
            isValidBuff = buffIcon ~= nil or (buffName and buffName ~= "Buff #" .. buffId)
        end
    end)
    
    if not isValidBuff then
        -- Показываем ошибку, если ID баффа не найден в BuffList
        if settingsControls.addBuffError and settingsControls.errorPanel then
            settingsControls.addBuffError:SetText("Error: Buff with ID " .. buffId .. " not found in buff library")
            settingsControls.errorPanel:Show(true)
        end
        return
    end
    
    -- Пытаемся добавить бафф для выбранного типа юнита
    if BuffsToTrack.AddTrackedBuff(buffId, currentUnitType) then
        -- Обновляем список, если бафф успешно добавлен
        updateTrackedBuffsList()
        
        -- Очищаем поле ввода
        settingsControls.newBuffId:SetText("")
        
        -- Скрываем сообщение об ошибке
        if settingsControls.errorPanel then
            settingsControls.errorPanel:Show(false)
        end
        
        -- Обновляем основной интерфейс
        if helpers and helpers.updateSettings then
            helpers.updateSettings()
        end
        
        -- Явно вызываем событие обновления списка отслеживаемых баффов
        pcall(function()
            api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
        end)
    else
        -- Показываем сообщение, что бафф уже отслеживается
        if settingsControls.addBuffError and settingsControls.errorPanel then
            settingsControls.addBuffError:SetText("Error: Buff already tracked or error occurred")
            settingsControls.errorPanel:Show(true)
        end
    end
    
    -- Еще раз принудительно обновляем список
    pcall(function()
        updateTrackedBuffsList()
        if settingsControls.buffsListContainer then
            settingsControls.buffsListContainer:Show(true)
        end
    end)
end

-- Функция для обновления полей настроек в зависимости от выбранного типа юнита
local function updateSettingsFields()
    -- Обновляем настройки из текущих данных
    settings = helpers.getSettings()
    
    -- Проверяем, что настройки для выбранного типа юнита существуют
    if not settings[currentUnitType] then
        settings[currentUnitType] = {}
    end
    
    -- Обновляем поля настроек для выбранного типа юнита
    local unitSettings = settings[currentUnitType]
    
    -- Обновляем поля позиции
    if settingsControls.posX then
        settingsControls.posX:SetText(tostring(unitSettings.posX or 0))
    end
    
    if settingsControls.posY then
        settingsControls.posY:SetText(tostring(unitSettings.posY or 0))
    end
    
    -- Обновляем чекбокс блокировки перемещения
    if settingsControls.lockPositioning then
        settingsControls.lockPositioning:SetChecked(unitSettings.lockPositioning or false)
    end
    
    -- Обновляем настройки таймера
    if settingsControls.timerFontSize then
        settingsControls.timerFontSize:SetText(tostring(unitSettings.timerFontSize or 16))
    end
    
    -- Обновляем цвет текста таймера
    if settingsControls.timerTextColor and settingsControls.timerTextColor.colorBG then
        local textColor = unitSettings.timerTextColor or {r = 1, g = 1, b = 1, a = 1}
        settingsControls.timerTextColor.colorBG:SetColor(
            textColor.r or 1,
            textColor.g or 1,
            textColor.b or 1,
            1
        )
    end
    
    -- Обновляем настройки размера иконок
    if settingsControls.iconSize then
        settingsControls.iconSize:SetText(tostring(unitSettings.iconSize or 40))
    end
    
    if settingsControls.iconSpacing then
        settingsControls.iconSpacing:SetText(tostring(unitSettings.iconSpacing or 5))
    end
    
    -- Обновляем настройки метки
    if settingsControls.labelFontSize then
        settingsControls.labelFontSize:SetText(tostring(unitSettings.labelFontSize or 14))
    end
    
    if settingsControls.labelX then
        settingsControls.labelX:SetText(tostring(unitSettings.labelX or 0))
    end
    
    if settingsControls.labelY then
        settingsControls.labelY:SetText(tostring(unitSettings.labelY or -30))
    end
    
    -- Обновляем чекбоксы
    if settingsControls.showLabel then
        settingsControls.showLabel:SetChecked(unitSettings.showLabel or false)
    end
    
    if settingsControls.showTimer then
        settingsControls.showTimer:SetChecked(unitSettings.showTimer ~= false) -- По умолчанию включено
    end
    
    -- Обновляем список отслеживаемых баффов
    updateTrackedBuffsList()
end

local function initSettingsPage()
    settings = helpers.getSettings()
    
    -- Используем CreateWindow вместо CreateEmptyWindow для корректной поддержки ESC и перетаскивания
    settingsWindow = api.Interface:CreateWindow("CooldawnBuffTrackerSettings",
                                             'CooldawnBuffTracker', 600, 650)
    settingsWindow:AddAnchor("CENTER", 'UIParent', 0, 0)
    settingsWindow:SetHandler("OnCloseByEsc", settingsWindowClose)
    function settingsWindow:OnClose() settingsWindowClose() end
    
    -- Если не удалось создать окно, выходим
    if not settingsWindow then return end
    
    -- ПЕРЕКЛЮЧАТЕЛЬ ТИПА ЮНИТА - Добавляем в самом верху
    local unitTypeLabel = helpers.createLabel('unitTypeLabel', settingsWindow,
                                           'Select unit type for settings:', 15, 30, 16)
    unitTypeLabel:SetWidth(250)
    
    -- Кнопка для выбора настроек маунта
    local mountButton = helpers.createButton('mountButton', settingsWindow, 'Mount (playerpet)', 300, 30)
    mountButton:SetWidth(140)
    
    -- Кнопка для выбора настроек игрока
    local playerButton = helpers.createButton('playerButton', settingsWindow, 'Player (player)', 450, 30)
    playerButton:SetWidth(140)
    
    -- Функция для обновления стиля кнопок в зависимости от выбранного типа
    local function updateUnitTypeButtons()
        if currentUnitType == "playerpet" then
            mountButton:SetText("* Mount (playerpet)")
            playerButton:SetText("Player (player)")
        else
            mountButton:SetText("Mount (playerpet)")
            playerButton:SetText("* Player (player)")
        end
    end
    
    -- Обработчики нажатия на кнопки выбора типа юнита
    mountButton:SetHandler("OnClick", function()
        currentUnitType = "playerpet"
        updateUnitTypeButtons()
        updateTrackedBuffsList()
        -- Обновляем все поля настроек для отображения настроек маунта
        updateSettingsFields()
    end)
    
    playerButton:SetHandler("OnClick", function()
        currentUnitType = "player"
        updateUnitTypeButtons()
        updateTrackedBuffsList()
        -- Обновляем все поля настроек для отображения настроек игрока
        updateSettingsFields()
    end)
    
    -- Инициализируем стиль кнопок
    updateUnitTypeButtons()
    
    -- ПЕРВЫЙ БЛОК - Заголовок управления отслеживаемыми баффами
    local trackedBuffsGroupLabel = helpers.createLabel('trackedBuffsGroupLabel', settingsWindow,
                                                    'Buff tracker management', 15, 60, 20)
    trackedBuffsGroupLabel:SetWidth(570) -- Увеличиваем ширину заголовка
    
    -- Кнопка для очистки всего списка баффов

    
    -- ВТОРОЙ БЛОК - Список отслеживаемых баффов (СРАЗУ ПОСЛЕ ЗАГОЛОВКА)
    -- Помещаем его выше остальных элементов в иерархии
    local trackedBuffsListHeader = helpers.createLabel('trackedBuffsListHeader', trackedBuffsGroupLabel,
                                                    'Buff list:', 0, 30, 16)
    trackedBuffsListHeader:Show(true)
    trackedBuffsListHeader:SetWidth(570) -- Увеличиваем ширину заголовка списка
    settingsControls.trackedBuffsListHeader = trackedBuffsListHeader
    
    -- Создаем контейнер для списка баффов и помещаем его прямо под заголовком
    local buffsListContainer = api.Interface:CreateWidget('window', 'buffsListContainer', trackedBuffsListHeader)
    buffsListContainer:SetExtent(570, 120) -- Увеличиваем ширину контейнера для списка
    buffsListContainer:AddAnchor("TOPLEFT", trackedBuffsListHeader, 0, 25)
    buffsListContainer:Show(true)
    
    -- Крайне заметный фон для контейнера
    local containerBg = buffsListContainer:CreateColorDrawable(0.85, 0.85, 0.85, 1, "background")
    containerBg:AddAnchor("TOPLEFT", buffsListContainer, 0, 0)
    containerBg:AddAnchor("BOTTOMRIGHT", buffsListContainer, 0, 0)
    
    -- Сохраняем контейнер в управляющих элементах
    settingsControls.buffsListContainer = buffsListContainer
    
    -- НЕМЕДЛЕННО заполняем список отслеживаемых баффов
    updateTrackedBuffsList()
    
    -- ТРЕТИЙ БЛОК - Только после создания списка добавляем элементы ввода нового баффа
    -- Поле для ввода ID нового баффа - размещаем ПОСЛЕ списка баффов, но в основном окне (не в контейнере списка)
    local newBuffIdLabel = helpers.createLabel('newBuffIdLabel', settingsWindow,
                                            'Buff ID:', 15, 220, 15)
    newBuffIdLabel:SetWidth(100) -- Устанавливаем ширину метки
    local newBuffId = helpers.createEdit('newBuffId', newBuffIdLabel,
                                      "", 200, 0)
    if newBuffId then 
        newBuffId:SetMaxTextLength(10) 
        newBuffId:SetWidth(50) -- Увеличиваем ширину поля ввода
    end
    settingsControls.newBuffId = newBuffId
    
    -- Кнопка добавления баффа
    local addBuffButton = helpers.createButton('addBuffButton', newBuffIdLabel, 'Add', 450, 0)
    addBuffButton:SetWidth(100) -- Увеличиваем ширину кнопки
    settingsControls.addBuffButton = addBuffButton
    
    -- Теперь привязываем обработчик нажатия на кнопку добавления
    addBuffButton:SetHandler("OnClick", addTrackedBuff)
    
    -- Создаем выделенную панель для сообщений об ошибке
    -- Размещаем ее в отдельном месте между полем ввода ID и настройками иконок
    local errorPanel = api.Interface:CreateWidget('window', 'errorPanel', settingsWindow)
    errorPanel:SetExtent(570, 25) -- Увеличиваем ширину панели ошибок
    errorPanel:AddAnchor("TOPLEFT", settingsWindow, 15, 250) -- Фиксированное положение под полем ввода
    
    -- Рамка для панели ошибок для лучшего выделения
    local errorPanelBorder = errorPanel:CreateNinePartDrawable("ui/chat_option.dds", "artwork")
    errorPanelBorder:SetCoords(0, 0, 27, 16)
    errorPanelBorder:SetInset(0, 8, 0, 7)
    errorPanelBorder:AddAnchor("TOPLEFT", errorPanel, -1, -1)
    errorPanelBorder:AddAnchor("BOTTOMRIGHT", errorPanel, 1, 1)
    
    -- Фон для панели ошибок - делаем более заметным
    local errorPanelBg = errorPanel:CreateColorDrawable(0.98, 0.85, 0.85, 0.9, "background")
    errorPanelBg:AddAnchor("TOPLEFT", errorPanel, 0, 0)
    errorPanelBg:AddAnchor("BOTTOMRIGHT", errorPanel, 0, 0)
    
    -- Сообщение об ошибке в панели
    local addBuffError = helpers.createLabel('addBuffError', errorPanel, '', 5, 5, 14)
    addBuffError:SetExtent(560, 20) -- Увеличиваем ширину сообщения об ошибке
    addBuffError.style:SetColor(1, 0, 0, 1) -- Красный цвет для сообщения об ошибке
    settingsControls.addBuffError = addBuffError
    
    -- По умолчанию панель ошибок скрыта
    errorPanel:Show(false)
    settingsControls.errorPanel = errorPanel
    
    -- ЧЕТВЕРТЫЙ БЛОК - остальные настройки
    -- Группа настроек иконок - размещаем ниже панели ошибок
    local iconGroupLabel = helpers.createLabel('iconGroupLabel', settingsWindow,
                                             'Icon settings', 15, 290, 20)
    iconGroupLabel:SetWidth(570) -- Увеличиваем ширину заголовка группы настроек
                                             
    -- Размер иконок
    local iconSizeLabel = helpers.createLabel('iconSizeLabel', iconGroupLabel,
                                            'Icon size:', 0, 25, 15)
    iconSizeLabel:SetWidth(150) -- Устанавливаем ширину метки
    local iconSize = helpers.createEdit('iconSize', iconSizeLabel,
                                      settings.iconSize, 200, 0)
    if iconSize then 
        iconSize:SetMaxTextLength(4) 
        iconSize:SetWidth(50) -- Увеличиваем ширину поля ввода
    end
    settingsControls.iconSize = iconSize
    
    -- Интервал между иконками
    local iconSpacingLabel = helpers.createLabel('iconSpacingLabel', iconSizeLabel,
                                               'Icon spacing:', 0, 25, 15)
    iconSpacingLabel:SetWidth(150) -- Устанавливаем ширину метки
    local iconSpacing = helpers.createEdit('iconSpacing', iconSpacingLabel,
                                         settings.iconSpacing, 200, 0)
    if iconSpacing then 
        iconSpacing:SetMaxTextLength(4) 
        iconSpacing:SetWidth(50) -- Увеличиваем ширину поля ввода
    end
    settingsControls.iconSpacing = iconSpacing
    
    -- Группа настроек положения иконок
    local positionLabel = helpers.createLabel('positionLabel', iconSpacingLabel,
                                            'Icon position', 0, 35, 18)
    positionLabel:SetWidth(570) -- Увеличиваем ширину заголовка группы настроек
                                            
    -- Координата X
    local posXLabel = helpers.createLabel('posXLabel', positionLabel,
                                        'Position X:', 0, 25, 15)
    posXLabel:SetWidth(150) -- Устанавливаем ширину метки
    local posX = helpers.createEdit('posX', posXLabel,
                                  settings.posX, 200, 0)
    if posX then 
        posX:SetMaxTextLength(6) 
        posX:SetWidth(50) -- Увеличиваем ширину поля ввода
    end
    settingsControls.posX = posX
    
    -- Координата Y
    local posYLabel = helpers.createLabel('posYLabel', posXLabel,
                                        'Position Y:', 0, 25, 15)
    posYLabel:SetWidth(150) -- Устанавливаем ширину метки
    local posY = helpers.createEdit('posY', posYLabel,
                                  settings.posY, 200, 0)
    if posY then 
        posY:SetMaxTextLength(6) 
        posY:SetWidth(50) -- Увеличиваем ширину поля ввода
    end
    settingsControls.posY = posY
    
    -- Блокировка перемещения
    local lockPositioning = helpers.createCheckbox('lockPositioning', posYLabel,
                                                 "Lock icon movement", 0, 25)
    if lockPositioning then 
        lockPositioning:SetChecked(settings.lockPositioning or false)
    end
    settingsControls.lockPositioning = lockPositioning
    
    -- Настройки таймера
    local timerGroupLabel = helpers.createLabel('timerGroupLabel', lockPositioning,
                                             'Timer settings', 0, 35, 18)
    timerGroupLabel:SetWidth(570) -- Увеличиваем ширину заголовка группы настроек
    
    -- Размер шрифта таймера
    local timerFontSizeLabel = helpers.createLabel('timerFontSizeLabel', timerGroupLabel,
                                                'Font size:', 0, 25, 15)
    timerFontSizeLabel:SetWidth(150) -- Устанавливаем ширину метки
    local timerFontSize = helpers.createEdit('timerFontSize', timerFontSizeLabel,
                                          settings.timerFontSize, 200, 0)
    if timerFontSize then 
        timerFontSize:SetMaxTextLength(4) 
        timerFontSize:SetWidth(50) -- Увеличиваем ширину поля ввода
    end
    settingsControls.timerFontSize = timerFontSize
    
    -- Цвет текста таймера
    local timerTextColorLabel = helpers.createLabel('timerTextColorLabel', timerFontSizeLabel,
                                                 'Text color:', 0, 25, 15)
    timerTextColorLabel:SetWidth(150) -- Устанавливаем ширину метки
    
    -- Получаем цвет текста таймера из настроек для выбранного типа юнита
    local unitSettings = settings[currentUnitType] or {}
    local textColor = unitSettings.timerTextColor or {r = 1, g = 1, b = 1, a = 1}
    
    local timerTextColor = helpers.createColorPickButton('timerTextColor', timerTextColorLabel, 
                                                      textColor, 200, 0)
    
    -- Настраиваем обработчик выбора цвета для сохранения выбранного цвета
    if timerTextColor and timerTextColor.colorBG then
        function timerTextColor:SelectedProcedure(r, g, b, a)
            self.colorBG:SetColor(r, g, b, a)
            -- Сохраняем цвет для будущего использования
            local mainSettings = api.GetSettings("CooldawnBuffTracker")
            if not mainSettings[currentUnitType] then
                mainSettings[currentUnitType] = {}
            end
            mainSettings[currentUnitType].timerTextColor = {r = r, g = g, b = b, a = a or 1}
        end
    end
    
    settingsControls.timerTextColor = timerTextColor
    
    -- Добавляем настройки отладки с лучшим расположением
    local debugGroupLabel = helpers.createLabel('debugGroupLabel', timerTextColorLabel,
                                             'Debug settings', 0, 35, 18)
    debugGroupLabel:SetWidth(570) -- Увеличиваем ширину заголовка группы настроек
    
    -- Чекбокс для отладки buff ID - изменяем позицию для лучшего отображения
    local debugBuffId = helpers.createCheckbox('debugBuffId', debugGroupLabel,
                                            "Debug buffId", 0, 25)
    if debugBuffId then 
        debugBuffId:SetChecked(settings.debugBuffId or false)
    end
    settingsControls.debugBuffId = debugBuffId
    
    -- Создаем кнопки Сохранить и Отмена
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
    
    -- Финальная проверка - вызываем ещё раз обновление списка для уверенности
    pcall(function()
        -- Заставляем обновить список еще раз
        updateTrackedBuffsList()
        
        -- Заставляем показать все критические элементы
        settingsControls.buffsListContainer:Show(true)
        settingsControls.trackedBuffsListHeader:Show(true)
        
        -- Скрываем панель ошибок при первом открытии
        if settingsControls.errorPanel then
            settingsControls.errorPanel:Show(false)
        end
        
        -- Проверяем наличие баффов в списке
        local buffIds = BuffsToTrack.GetAllTrackedBuffIds()
        if #buffIds == 0 then
            -- Добавляем информационное сообщение для пустого списка
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
    
    -- Закрываем палитру, если она открыта
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
    
    -- Если окно уже было инициализировано, просто показываем его
    if settingsWindow then
        -- Обновляем настройки полей для текущего типа юнита
        updateSettingsFields()
        
        -- Обновляем список отслеживаемых баффов при каждом открытии окна настроек
        updateTrackedBuffsList()
        
        -- Скрываем панель ошибок при каждом открытии окна
        if settingsControls.errorPanel then
            settingsControls.errorPanel:Show(false)
        end
        
        settingsWindow:Show(true)
        helpers.setSettingsPageOpened(true)
        return
    end
    
    -- Если окно не было инициализировано, создаем его
    initSettingsPage()
    
    if settingsWindow then
        -- Обновляем настройки полей для текущего типа юнита
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