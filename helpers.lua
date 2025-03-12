local api = require("api")
local defaultSettings = require('CooldawnBuffTracker/default_settings')
local helpers = {}
local CANVAS
local PLAYER_CANVAS

local settingsOpened = false

-- Основные функции для работы с настройками
function helpers.getSettings(cnv, playerCnv)
    if cnv ~= nil then CANVAS = cnv end
    if playerCnv ~= nil then PLAYER_CANVAS = playerCnv end
    
    local settings = api.GetSettings("CooldawnBuffTracker")
    
    -- Проверяем и устанавливаем настройки по умолчанию
    if not settings.playerpet then
        settings.playerpet = {}
        for k, v in pairs(defaultSettings.playerpet) do
            settings.playerpet[k] = v
        end
    end
    
    if not settings.player then
        settings.player = {}
        for k, v in pairs(defaultSettings.player) do
            settings.player[k] = v
        end
    end
    
    -- Проверяем общие настройки
    if settings.debugBuffId == nil then
        settings.debugBuffId = defaultSettings.debugBuffId
    end
    
    return settings
end

function helpers.updateSettings(newSettings)
    local settings = newSettings or api.GetSettings("CooldawnBuffTracker")
    local currentPosX, currentPosY, playerPosX, playerPosY
    
    -- Сохраняем текущую позицию холста маунта, если он существует
    if CANVAS then
        pcall(function()
            currentPosX, currentPosY = CANVAS:GetOffset()
            if currentPosX and currentPosY then
                -- Обновляем позицию в настройках только если позиция изменилась
                if settings.playerpet.posX ~= currentPosX or settings.playerpet.posY ~= currentPosY then
                    settings.playerpet.posX = currentPosX
                    settings.playerpet.posY = currentPosY
                end
            end
        end)
    end
    
    -- Сохраняем текущую позицию холста игрока, если он существует
    if PLAYER_CANVAS then
        pcall(function()
            playerPosX, playerPosY = PLAYER_CANVAS:GetOffset()
            if playerPosX and playerPosY then
                -- Обновляем позицию в настройках только если позиция изменилась
                if settings.player.posX ~= playerPosX or settings.player.posY ~= playerPosY then
                    settings.player.posX = playerPosX
                    settings.player.posY = playerPosY
                end
            end
        end)
    end
    
    -- Убедимся, что изменения сохранены в настройках
    pcall(function()
        api.SaveSettings()
    end)
    
    -- Явное обновление интерфейса через обработчик
    if CANVAS and CANVAS.OnSettingsSaved then
        pcall(function()
            CANVAS.OnSettingsSaved()
            
            -- Восстанавливаем позицию после обновления
            if currentPosX and currentPosY then
                CANVAS:RemoveAllAnchors()
                CANVAS:AddAnchor("TOPLEFT", "UIParent", currentPosX, currentPosY)
            end
        end)
    end
    
    -- Явное обновление интерфейса игрока через обработчик
    if PLAYER_CANVAS and PLAYER_CANVAS.OnSettingsSaved then
        pcall(function()
            PLAYER_CANVAS.OnSettingsSaved()
            
            -- Восстанавливаем позицию после обновления
            if playerPosX and playerPosY then
                PLAYER_CANVAS:RemoveAllAnchors()
                PLAYER_CANVAS:AddAnchor("TOPLEFT", "UIParent", playerPosX, playerPosY)
            end
        end)
    end
    
    settings = helpers.getSettings()
    return settings
end

function helpers.resetSettingsToDefault()
    local settings = api.GetSettings("CooldawnBuffTracker")
    
    -- Копируем все настройки по умолчанию для playerpet
    settings.playerpet = {}
    for k, v in pairs(defaultSettings.playerpet) do
        settings.playerpet[k] = v
    end
    
    -- Копируем все настройки по умолчанию для player
    settings.player = {}
    for k, v in pairs(defaultSettings.player) do
        settings.player[k] = v
    end
    
    -- Копируем общие настройки
    settings.debugBuffId = defaultSettings.debugBuffId
    
    -- Сохраняем настройки
    pcall(function()
        api.SaveSettings()
    end)
    
    -- Полное обновление UI для маунта
    if CANVAS and CANVAS.OnSettingsSaved then
        pcall(function()
            CANVAS.OnSettingsSaved()
        end)
    end
    
    -- Полное обновление UI для игрока
    if PLAYER_CANVAS and PLAYER_CANVAS.OnSettingsSaved then
        pcall(function()
            PLAYER_CANVAS.OnSettingsSaved()
        end)
    end
    
    return settings
end

-- Функции для работы с UI
function helpers.createLabel(id, parent, text, offsetX, offsetY, fontSize)
    local label = api.Interface:CreateWidget('label', id, parent)
    label:AddAnchor("TOPLEFT", offsetX, offsetY)
    label:SetExtent(255, 20)
    label:SetText(text)
    
    -- Устанавливаем цвет, если доступно
    if FONT_COLOR and FONT_COLOR.TITLE then
        label.style:SetColor(FONT_COLOR.TITLE[1], FONT_COLOR.TITLE[2], FONT_COLOR.TITLE[3], 1)
    else
        label.style:SetColor(0.87, 0.69, 0, 1) -- Золотистый цвет по умолчанию
    end
    
    label.style:SetAlign(ALIGN.LEFT)
    label.style:SetFontSize(fontSize or 18)
    
    return label
end

function helpers.createEdit(id, parent, text, offsetX, offsetY)
    local field = W_CTRL.CreateEdit(id, parent)
    field:SetExtent(100, 20)
    field:AddAnchor("TOPLEFT", offsetX, offsetY)
    field:SetText(tostring(text))
    field.style:SetColor(0, 0, 0, 1)
    field.style:SetAlign(ALIGN.LEFT)
    field:SetInitVal(text)
    
    return field
end

function helpers.createButton(id, parent, text, x, y)
    local button = api.Interface:CreateWidget('button', id, parent)
    button:AddAnchor("TOPLEFT", x, y)
    button:SetExtent(95, 26)  -- Увеличил ширину для кнопок
    button:SetText(text)
    api.Interface:ApplyButtonSkin(button, BUTTON_BASIC.DEFAULT)
    
    return button
end

function helpers.createCheckbox(id, parent, text, offsetX, offsetY)
    local checkBox = nil
    
    -- Используем компонент чекбокса из утилит, если доступен
    local checkButtonModule = require('CooldawnBuffTracker/util/check_button') or require('util/check_button') or require('./util/check_button')
    
    if checkButtonModule and checkButtonModule.CreateCheckButton then
        checkBox = checkButtonModule.CreateCheckButton(id, parent, text)
        checkBox:AddAnchor("TOPLEFT", offsetX, offsetY)
        checkBox:SetButtonStyle("default")
    else
        -- Создаем чекбокс, используя доступные методы
        checkBox = api.Interface:CreateWidget('checkbutton', id, parent)
        checkBox:AddAnchor("TOPLEFT", offsetX, offsetY)
        
        -- Добавляем текст
        local textLabel = helpers.createLabel(id .. "Text", checkBox, text, 20, 0, 15)
        
        -- Обработчик клика на текст
        if textLabel then
            textLabel:SetHandler("OnClick", function()
                checkBox:SetChecked(not checkBox:GetChecked())
            end)
        end
    end
    
    return checkBox
end

-- Создание кнопки выбора цвета
function helpers.createColorPickButton(id, parent, color, offsetX, offsetY)
    local colorButton = nil
    
    -- Загружаем модуль создания кнопки выбора цвета
    local createColorPickButtonsModule = require('CooldawnBuffTracker/util/color_picker') or require('util/color_picker') or require('./util/color_picker')
    
    if createColorPickButtonsModule then
        colorButton = createColorPickButtonsModule(id, parent)
        colorButton:SetExtent(23, 15)
        colorButton:AddAnchor("TOPLEFT", parent, offsetX, offsetY)
        colorButton.colorBG:SetColor(color.r or 1, color.g or 1, color.b or 1, 1)
        
        function colorButton:SelectedProcedure(r, g, b, a)
            self.colorBG:SetColor(r, g, b, a)
        end
        
        local F_ETC = require('CooldawnBuffTracker/util/etc') or require('util/etc') or require('./util/etc')
        
        if F_ETC then
            function colorButton:OnClick()
                F_ETC.HidePallet()
                local palletWindow = F_ETC.ShowPallet(self)
                function palletWindow:OnHide() F_ETC.HidePallet() end
                palletWindow:SetHandler("OnHide", palletWindow.OnHide)
            end
            colorButton:SetHandler("OnClick", colorButton.OnClick)
        end
    else
        -- Создаем простую цветную кнопку, если модуль не доступен
        colorButton = api.Interface:CreateWidget('button', id, parent)
        colorButton:AddAnchor("TOPLEFT", parent, offsetX, offsetY)
        colorButton:SetExtent(23, 15)
        
        local colorBG = colorButton:CreateColorDrawable(color.r or 1, color.g or 1, color.b or 1, 1, "background")
        colorBG:AddAnchor("TOPLEFT", colorButton, 1, 1)
        colorBG:AddAnchor("BOTTOMRIGHT", colorButton, -1, -1)
        colorButton.colorBG = colorBG
    end
    
    return colorButton
end

-- Функции для управления состоянием настроек
function helpers.setSettingsPageOpened(state) 
    settingsOpened = state 
end

function helpers.getSettingsPageOpened() 
    return settingsOpened 
end

return helpers 