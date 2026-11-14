local api = require("api")
local defaultSettings = require('CooldawnBuffTracker/default_settings')
local CbtWindow = require('CooldawnBuffTracker/util/cbt_window')
local CbtLog = require('CooldawnBuffTracker/util/cbt_log')
local helpers = {}
local settingsOpened = false

-- Реестр живых канвасов: { playerpet = {widget1, widget2, ...}, ... }.
-- Заполняется из main.lua (helpers.setCanvasRegistry), чтобы helpers мог
-- сохранять позицию КАЖДОГО канваса, не зная деталей UI.
local CANVAS_REGISTRY = nil
local refreshCallback = nil

function helpers.setCanvasRegistry(registry)
    CANVAS_REGISTRY = registry
end

function helpers.getCanvasRegistry()
    return CANVAS_REGISTRY
end

-- Колбэк полного обновления панелей после изменения настроек.
function helpers.setRefreshCallback(fn)
    refreshCallback = fn
end

-- Глубокая копия таблицы (используется и для defaults, и для пресетов).
local function deepCopy(original)
    if type(original) ~= "table" then
        return original
    end
    local copy = {}
    for key, value in pairs(original) do
        copy[key] = deepCopy(value)
    end
    return copy
end

-- Функция-помощник для форматирования ID баффа (без экспоненты)
function helpers.formatBuffId(buffId)
    if type(buffId) == "number" then
        return string.format("%.0f", buffId)
    else
        return tostring(buffId)
    end
end

-- Тип кастомной записи: "buff" (бафф/дебафф), "skill" (навык по боевому логу)
-- или "mana" (навык маунта с маной). Для записей без kind — эвристика.
function helpers.entryKind(cb)
    if defaultSettings and defaultSettings.entryKind then
        return defaultSettings.entryKind(cb)
    end
    if type(cb) ~= "table" then return "buff" end
    return cb.kind or "buff"
end

-- Main functions for working with settings
function helpers.getSettings(cnv, playerCnv, targetCnv)
    local settings = api.GetSettings("CooldawnBuffTracker")

    -- Миграция новых полей (canvases, presets и т.д.) без перезаписи данных
    if defaultSettings and defaultSettings.migrate then
        settings = defaultSettings.migrate(settings)
    end

    -- Check and set default settings (глубокая копия: canvases/defaults не должны
    -- разделять таблицы с модулем defaults)
    for _, unitType in ipairs(defaultSettings.unitTypes or {"playerpet", "player", "target"}) do
        if type(settings[unitType]) ~= "table" then
            settings[unitType] = deepCopy(defaultSettings[unitType])
        end
    end

    return settings
end

local UNIT_TYPES = {"playerpet", "player", "target"}

-- Сохраняет позицию каждого живого канваса в его собственную запись
-- canvases[i].posX/posY. Пишем только если виджет реально сдвинут относительно
-- последней применённой раскладки: иначе введённое в поле значение позиции
-- было бы затёрто старым смещением до пересборки панели.
function helpers.saveCanvasPositions(settings)
    settings = settings or api.GetSettings("CooldawnBuffTracker")
    if not settings or type(CANVAS_REGISTRY) ~= "table" then return end

    for _, unitType in ipairs(UNIT_TYPES) do
        local unitSettings = settings[unitType]
        local widgets = CANVAS_REGISTRY[unitType]
        if unitSettings and type(unitSettings.canvases) == "table" and type(widgets) == "table" then
            for i, canvas in ipairs(widgets) do
                local cfg = unitSettings.canvases[i]
                if canvas and cfg then
                    -- Пишем только для уже отрисованного и видимого канваса:
                    -- у скрытого/ещё не разложенного виджета смещение не является
                    -- позицией, которую выбрал пользователь.
                    local visible = true
                    if canvas.IsVisible then
                        local okVis, vis = pcall(function() return canvas:IsVisible() end)
                        if okVis then visible = vis and true or false end
                    end
                    if visible and canvas.layoutSig ~= nil then
                        local ok, x, y = pcall(function()
                            local fx, fy
                            if canvas.GetEffectiveOffset then
                                fx, fy = canvas:GetEffectiveOffset()
                            end
                            if fx == nil or fy == nil then
                                fx, fy = canvas:GetOffset()
                            end
                            return fx, fy
                        end)
                        if ok and type(x) == "number" and type(y) == "number" then
                            local appliedX = canvas.appliedPosX
                            local appliedY = canvas.appliedPosY
                            local moved = (appliedX == nil) or (appliedY == nil)
                                or (math.abs(x - appliedX) > 0.5) or (math.abs(y - appliedY) > 0.5)
                            -- (0,0) — типичный «пустой» ответ виджета, который ещё не
                            -- разложен; настоящий перенос в 0,0 уже сохранён OnDragStop.
                            local sane = (x ~= 0) or (y ~= 0)
                            if moved and sane and (cfg.posX ~= x or cfg.posY ~= y) then
                                cfg.posX = x
                                cfg.posY = y
                            end
                        end
                    end
                end
            end
        end
    end
end

function helpers.updateSettings(newSettings)
    local settings = newSettings or api.GetSettings("CooldawnBuffTracker")
    if not settings then return api.GetSettings("CooldawnBuffTracker") end

    helpers.saveCanvasPositions(settings)

    -- Ensure changes are saved in settings
    api.SaveSettings()

    -- Явное обновление панелей: пересоздаёт канвасы под текущее число канвасов
    -- и перерисовывает иконки (раньше здесь был мёртвый canvas.OnSettingsSaved).
    if refreshCallback then
        pcall(refreshCallback)
    end

    return api.GetSettings("CooldawnBuffTracker")
end

function helpers.resetSettingsToDefault()
    local settings = api.GetSettings("CooldawnBuffTracker")

    -- Глубокая копия дефолтов: у каждого юнита свой canvases/canvasOf
    for _, unitType in ipairs(UNIT_TYPES) do
        settings[unitType] = deepCopy(defaultSettings[unitType])
    end

    -- Save settings
    api.SaveSettings()

    if refreshCallback then
        pcall(refreshCallback)
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
        -- Золото читается и на тёмной подложке, и на светлой теме клиента
        label.style:SetColor(FONT_COLOR.TITLE[1], FONT_COLOR.TITLE[2], FONT_COLOR.TITLE[3], 1)
    else
        label.style:SetColor(0.87, 0.69, 0, 1) -- Gold color by default
    end
    
    label.style:SetAlign(ALIGN.LEFT)
    label.style:SetFontSize(fontSize or 18)
    if label.Clickable then label:Clickable(false) end

    return label
end

function helpers.createEdit(id, parent, text, offsetX, offsetY, tip)
    local field = W_CTRL.CreateEdit(id, parent)
    field:SetExtent(100, 20)
    field:AddAnchor("TOPLEFT", offsetX, offsetY)
    field:SetText(tostring(text))
    field.style:SetAlign(ALIGN.LEFT)
    field:SetInitVal(tonumber(text) or 0)
    CbtWindow.StyleEdit(field)
    if tip then CbtWindow.Tooltip(field, tip) end

    return field
end

function helpers.createButton(id, parent, text, x, y, tip)
    local button
    if parent and parent.CreateChildWidget then
        button = parent:CreateChildWidget("button", id, 0, true)
    end
    if not button then
        button = api.Interface:CreateWidget('button', id, parent)
    end
    button:AddAnchor("TOPLEFT", x, y)
    button:SetExtent(95, 26)
    button:SetText("") -- нативную надпись гасим, рисуем свою (тёмная тема)

    -- Плоская тёмная кнопка в стиле BetterBars: рамка + заливка + светлый текст
    local border = button:CreateColorDrawable(0.00, 0.00, 0.00, 0.90, "background")
    border:AddAnchor("TOPLEFT", button, 0, 0)
    border:AddAnchor("BOTTOMRIGHT", button, 0, 0)
    local fill = button:CreateColorDrawable(0.12, 0.13, 0.15, 0.95, "background")
    fill:AddAnchor("TOPLEFT", button, 1, 1)
    fill:AddAnchor("BOTTOMRIGHT", button, -1, -1)

    local label = button:CreateChildWidget("label", id .. "_text", 0, true)
    label:SetExtent(80, 20)
    label:AddAnchor("LEFT", button, 4, 0)
    label:AddAnchor("RIGHT", button, -4, 0)
    label.style:SetAlign(ALIGN.CENTER)
    label.style:SetFontSize(13)
    label.style:SetColor(0.87, 0.69, 0, 1)
    label:SetText(text or "")
    if label.Clickable then label:Clickable(false) end
    button.textLabel = label

    function button:SetText(t)
        if self.textLabel then self.textLabel:SetText(t or "") end
    end

    -- Hover-подсветка через CbtWindow.Hover: тултип потом её не затирает.
    CbtWindow.Hover(button, function()
        fill:SetColor(0.18, 0.19, 0.23, 0.95)
    end, function()
        fill:SetColor(0.12, 0.13, 0.15, 0.95)
    end)

    -- Подсказка ставится после ховер-подсветки: CbtWindow.Tooltip цепляет
    -- прежние OnEnter/OnLeave, поэтому подсветка остаётся.
    if tip then CbtWindow.Tooltip(button, tip) end

    return button
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
    CbtLog.success("Preset saved: " .. CbtLog.hl(presetName))
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
    CbtLog.success("Preset deleted: " .. CbtLog.hl(presetName))
    return true
end

-- Загрузить пресет: копируем его настройки в текущие (глубокая копия).
-- Недостающие ключи добиваются из defaults через nil-проверку (false сохраняется).
function helpers.loadPreset(presetName)
    local settings = api.GetSettings("CooldawnBuffTracker")
    local preset = helpers.getPreset(presetName)

    if not preset then
        CbtLog.error("Preset not found: " .. CbtLog.hl(presetName))
        return false, "Preset not found"
    end

    for _, unitType in ipairs(PRESET_UNIT_TYPES) do
        if preset[unitType] then
            local cloned = helpers.cloneTable(preset[unitType])
            -- Пресет старого формата (плоские posX/iconSize/...): конвертируем в
            -- canvases[1] ДО добавления defaults, иначе раскладка потеряется.
            if defaultSettings and defaultSettings.normalizeUnit then
                defaultSettings.normalizeUnit(cloned, unitType)
            end
            -- Добавляем недостающие поля из defaults, не затирая существующие
            if defaultSettings and defaultSettings[unitType] then
                for k, v in pairs(defaultSettings[unitType]) do
                    if k ~= "canvases" and cloned[k] == nil then cloned[k] = v end
                end
                if type(cloned.canvases) ~= "table" or #cloned.canvases == 0 then
                    cloned.canvases = helpers.cloneTable(defaultSettings[unitType].canvases)
                end
            end
            settings[unitType] = cloned
        end
    end

    settings.activePresetName = presetName

    pcall(function() api.SaveSettings() end)
    CbtLog.success("Preset loaded: " .. CbtLog.hl(presetName))
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
