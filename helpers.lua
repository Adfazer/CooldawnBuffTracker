local api = require("api")
local defaultSettings = require('CooldawnBuffTracker/default_settings')
local helpers = {}
local CANVAS
local PLAYER_CANVAS
local TARGET_CANVAS

local settingsOpened = false

-- Функция-помощник для форматирования ID баффа (без экспоненты)
function helpers.formatBuffId(buffId)
    if type(buffId) == "number" then
        return string.format("%.0f", buffId)
    else
        return tostring(buffId)
    end
end

-- Main functions for working with settings
function helpers.getSettings(cnv, playerCnv, targetCnv)
    if cnv ~= nil then CANVAS = cnv end
    if playerCnv ~= nil then PLAYER_CANVAS = playerCnv end
    if targetCnv ~= nil then TARGET_CANVAS = targetCnv end
    
    local settings = api.GetSettings("CooldawnBuffTracker")

    -- Миграция новых полей (presets и т.д.) без перезаписи существующих данных
    if defaultSettings and defaultSettings.migrate then
        settings = defaultSettings.migrate(settings)
    end

    -- Check and set default settings
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
    
    if not settings.target then
        settings.target = {}
        for k, v in pairs(defaultSettings.target) do
            settings.target[k] = v
        end
    end
    
    return settings
end

function helpers.updateSettings(newSettings)
    local settings = newSettings or api.GetSettings("CooldawnBuffTracker")
    local currentPosX, currentPosY, playerPosX, playerPosY, targetPosX, targetPosY
    
    -- Save current mount canvas position, if it exists
    if CANVAS then
        currentPosX, currentPosY = CANVAS:GetOffset()
        if currentPosX and currentPosY then
            -- Update position in settings only if position has changed
            if settings.playerpet.posX ~= currentPosX or settings.playerpet.posY ~= currentPosY then
                settings.playerpet.posX = currentPosX
                settings.playerpet.posY = currentPosY
            end
        end
    end
    
    -- Save current player canvas position, if it exists
    if PLAYER_CANVAS then
        playerPosX, playerPosY = PLAYER_CANVAS:GetOffset()
        if playerPosX and playerPosY then
            -- Update position in settings only if position has changed
            if settings.player.posX ~= playerPosX or settings.player.posY ~= playerPosY then
                settings.player.posX = playerPosX
                settings.player.posY = playerPosY
            end
        end
    end
    
    -- Save current target canvas position, if it exists
    if TARGET_CANVAS then
        targetPosX, targetPosY = TARGET_CANVAS:GetOffset()
        if targetPosX and targetPosY then
            -- Update position in settings only if position has changed
            if settings.target and (settings.target.posX ~= targetPosX or settings.target.posY ~= targetPosY) then
                settings.target.posX = targetPosX
                settings.target.posY = targetPosY
            end
        end
    end
    
    -- Ensure changes are saved in settings
    api.SaveSettings()
    
    -- Explicit UI update via handler
    if CANVAS and CANVAS.OnSettingsSaved then
        CANVAS.OnSettingsSaved()
        
        -- Restore position after update
        if currentPosX and currentPosY then
            CANVAS:RemoveAllAnchors()
            CANVAS:AddAnchor("TOPLEFT", "UIParent", currentPosX, currentPosY)
        end
    end
    
    -- Explicit UI update for player via handler
    if PLAYER_CANVAS and PLAYER_CANVAS.OnSettingsSaved then
        PLAYER_CANVAS.OnSettingsSaved()
        
        -- Restore position after update
        if playerPosX and playerPosY then
            PLAYER_CANVAS:RemoveAllAnchors()
            PLAYER_CANVAS:AddAnchor("TOPLEFT", "UIParent", playerPosX, playerPosY)
        end
    end
    
    -- Explicit UI update for target via handler
    if TARGET_CANVAS and TARGET_CANVAS.OnSettingsSaved then
        TARGET_CANVAS.OnSettingsSaved()
        
        -- Restore position after update
        if targetPosX and targetPosY then
            TARGET_CANVAS:RemoveAllAnchors()
            TARGET_CANVAS:AddAnchor("TOPLEFT", "UIParent", targetPosX, targetPosY)
        end
    end
    
    settings = helpers.getSettings()
    return settings
end

function helpers.resetSettingsToDefault()
    local settings = api.GetSettings("CooldawnBuffTracker")
    
    -- Copy all default settings for playerpet
    settings.playerpet = {}
    for k, v in pairs(defaultSettings.playerpet) do
        settings.playerpet[k] = v
    end
    
    -- Copy all default settings for player
    settings.player = {}
    for k, v in pairs(defaultSettings.player) do
        settings.player[k] = v
    end
    
    -- Copy all default settings for target
    settings.target = {}
    for k, v in pairs(defaultSettings.target) do
        settings.target[k] = v
    end
    
    -- Save settings
    api.SaveSettings()
    
    -- Full UI update for mount
    if CANVAS and CANVAS.OnSettingsSaved then
        CANVAS.OnSettingsSaved()
    end
    
    -- Full UI update for player
    if PLAYER_CANVAS and PLAYER_CANVAS.OnSettingsSaved then
        PLAYER_CANVAS.OnSettingsSaved()
    end
    
    -- Full UI update for target
    if TARGET_CANVAS and TARGET_CANVAS.OnSettingsSaved then
        TARGET_CANVAS.OnSettingsSaved()
    end
    
    return settings
end

-- Functions for working with UI
function helpers.createLabel(id, parent, text, offsetX, offsetY, fontSize)
    local label = api.Interface:CreateWidget('label', id, parent)
    label:AddAnchor("TOPLEFT", offsetX, offsetY)
    label:SetExtent(255, 20)
    label:SetText(text)
    
    -- Set color if available
    if FONT_COLOR and FONT_COLOR.TITLE then
        label.style:SetColor(FONT_COLOR.TITLE[1], FONT_COLOR.TITLE[2], FONT_COLOR.TITLE[3], 1)
    else
        label.style:SetColor(0.87, 0.69, 0, 1) -- Gold color by default
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
    field:SetInitVal(tonumber(text) or 0)
    
    return field
end

function helpers.createButton(id, parent, text, x, y)
    local button = api.Interface:CreateWidget('button', id, parent)
    button:AddAnchor("TOPLEFT", x, y)
    button:SetExtent(95, 26)  -- Increased width for buttons
    button:SetText(text)
    api.Interface:ApplyButtonSkin(button, BUTTON_BASIC.DEFAULT)
    
    return button
end

function helpers.createCheckbox(id, parent, text, offsetX, offsetY)
    local checkBox = nil
    checkBox = api._Library.UI.CreateCheckButton(id, parent, text)
    checkBox:AddAnchor("TOPLEFT", offsetX, offsetY)
    checkBox:SetButtonStyle("default")
    return checkBox
end

-- Create color pick button
function helpers.createColorPickButton(id, parent, color, offsetX, offsetY)
    local colorButton = nil
    
    -- Продолжаем использовать локальный модуль
    local createColorPickButtonsModule = require('CooldawnBuffTracker/util/color_picker')
    
    if createColorPickButtonsModule then
        colorButton = createColorPickButtonsModule(id, parent)
        colorButton:SetExtent(23, 15)
        colorButton:AddAnchor("TOPLEFT", parent, offsetX, offsetY)
        colorButton.colorBG:SetColor(color.r or 1, color.g or 1, color.b or 1, 1)
        
        function colorButton:SelectedProcedure(r, g, b, a)
            self.colorBG:SetColor(r, g, b, a)
        end
        
        local F_ETC = require('CooldawnBuffTracker/util/etc')
            
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
        -- Create simple color button if module is not available
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

-- Functions for managing settings state
function helpers.setSettingsPageOpened(state) 
    settingsOpened = state 
end

function helpers.getSettingsPageOpened()
    return settingsOpened
end

-- =========================================================================
-- Пресеты настроек
-- Пресет хранит полную раскладку для трёх типов юнитов (позиция, размер,
-- цвета, showLabel/showTimer И список отслеживаемых баффов trackedBuffs).
-- customBuffs и debugBuffId остаются глобальными и в пресеты не входят.
-- =========================================================================

-- Типы юнитов, чьи настройки сохраняются в пресете
local PRESET_UNIT_TYPES = {"playerpet", "player", "target"}

-- Глубокое (рекурсивное) копирование таблицы.
-- Нужно, чтобы пресеты были независимы от текущих настроек: без этого
-- присваивание создаёт ссылку, и правка настроек меняла бы сам пресет.
function helpers.cloneTable(original)
    if type(original) ~= "table" then
        return original
    end

    local copy = {}
    for key, value in pairs(original) do
        if type(value) == "table" then
            copy[key] = helpers.cloneTable(value)
        else
            copy[key] = value
        end
    end
    return copy
end

-- Список имён всех пресетов (отсортирован для стабильного порядка в UI)
function helpers.getPresetNames()
    local settings = api.GetSettings("CooldawnBuffTracker")
    local names = {}
    if settings and settings.presets then
        for name, _ in pairs(settings.presets) do
            table.insert(names, name)
        end
        table.sort(names)
    end
    return names
end

-- Получить данные пресета по имени
function helpers.getPreset(presetName)
    local settings = api.GetSettings("CooldawnBuffTracker")
    if not presetName or not settings or not settings.presets then
        return nil
    end
    return settings.presets[presetName]
end

-- Сохранить текущие настройки как пресет с указанным именем (с глубоким копированием)
function helpers.savePresetFromCurrent(presetName)
    if not presetName or presetName == "" then
        return false, "Empty preset name"
    end

    local settings = api.GetSettings("CooldawnBuffTracker")
    if not settings.presets then settings.presets = {} end

    local preset = { name = presetName }
    for _, unitType in ipairs(PRESET_UNIT_TYPES) do
        preset[unitType] = helpers.cloneTable(settings[unitType] or {})
    end

    settings.presets[presetName] = preset
    settings.activePresetName = presetName

    pcall(function() api.SaveSettings() end)
    api.Log:Info("[CBT] Preset saved: " .. presetName)
    return true
end

-- Удалить пресет. Если удаляем активный — сбрасываем activePresetName.
function helpers.deletePreset(presetName)
    local settings = api.GetSettings("CooldawnBuffTracker")
    if not settings.presets or settings.presets[presetName] == nil then
        return false, "Preset not found"
    end

    settings.presets[presetName] = nil
    if settings.activePresetName == presetName then
        settings.activePresetName = nil
    end

    pcall(function() api.SaveSettings() end)
    api.Log:Info("[CBT] Preset deleted: " .. presetName)
    return true
end

-- Загрузить пресет: копируем его настройки в текущие (глубокая копия).
-- Недостающие ключи добиваются из defaults через nil-проверку (false сохраняется).
function helpers.loadPreset(presetName)
    local settings = api.GetSettings("CooldawnBuffTracker")
    local preset = helpers.getPreset(presetName)

    if not preset then
        api.Log:Err("[CBT] Preset not found: " .. tostring(presetName))
        return false, "Preset not found"
    end

    for _, unitType in ipairs(PRESET_UNIT_TYPES) do
        if preset[unitType] then
            local cloned = helpers.cloneTable(preset[unitType])
            -- Добавляем недостающие поля из defaults, не затирая существующие
            if defaultSettings and defaultSettings[unitType] then
                for k, v in pairs(defaultSettings[unitType]) do
                    if cloned[k] == nil then cloned[k] = v end
                end
            end
            settings[unitType] = cloned
        end
    end

    settings.activePresetName = presetName

    pcall(function() api.SaveSettings() end)
    api.Log:Info("[CBT] Preset loaded: " .. presetName)
    return true
end

-- Есть ли сейчас активный пресет
function helpers.hasActivePreset()
    local settings = api.GetSettings("CooldawnBuffTracker")
    return settings.activePresetName ~= nil and settings.activePresetName ~= ""
end

-- Имя активного пресета (или nil)
function helpers.getActivePresetName()
    local settings = api.GetSettings("CooldawnBuffTracker")
    return settings.activePresetName
end

-- Сбросить активный пресет (вызывается при ручном изменении настроек)
function helpers.clearActivePreset()
    local settings = api.GetSettings("CooldawnBuffTracker")
    if settings.activePresetName ~= nil then
        settings.activePresetName = nil
        pcall(function() api.SaveSettings() end)
    end
end

return helpers
