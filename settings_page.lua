local api = require("api")
local helpers = require('CooldawnBuffTracker/helpers')
local defaultSettings = require('CooldawnBuffTracker/default_settings')
local iconSearch = require('CooldawnBuffTracker/icon_search_window')
local CbtWindow = require('CooldawnBuffTracker/util/cbt_window')
local recordWindow = require('CooldawnBuffTracker/record_window')

-- Load module for working with buffs
local BuffsToTrack = require("CooldawnBuffTracker/buffs_to_track")
local BuffList = require("CooldawnBuffTracker/buff_helper")

-- Импортируем модуль для отображения пиксельного изображения
local pixelViewer = require('CooldawnBuffTracker/util/pixel_viewer')

-- Импортируем модуль для Import/Export конфигурации
local importExport = require('CooldawnBuffTracker/util/import_export')

-- Импортируем модуль окна пресетов
local presetWindowModule = require('CooldawnBuffTracker/preset_window')

-- Импортируем модуль окна поиска баффов

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
local M = {}
-- 1.23.0: синхронизация секции "Native frame display"; назначается в
-- buildFrameModeSection (forward declaration, иначе вызов из
-- updateSettingsFields уйдёт в global).
local syncFrameModeControls = function() end

-- Состояние формы Add custom entry: выбранный тип записи и путь иконки.
-- Тип: "buff" (бафф/дебафф), "skill" (навык по боевому логу), "mana" (навык маунта).
local newEntryKind = "buff"
local newEntryIcon = ""

local function trimText(t)
    t = tostring(t or "")
    return (t:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Число из поля ввода с зажимом в диапазон (1.23.0: поля оверлея/строки).
local function clampIntText(text, minValue, maxValue, fallback)
    local n = tonumber(text)
    if not n or n ~= n then return fallback end
    n = math.floor(n + 0.5)
    if n < minValue then n = minValue end
    if n > maxValue then n = maxValue end
    return n
end

-- Вызывается из main.lua, когда сканер нашёл навык по имени (spellId в логе = 0)
local function onSkillIconFound(name, id, path)
    newEntryIcon = path or ""
    if settingsControls.customBuffIconPreview then
        F_SLOT.SetIconBackGround(settingsControls.customBuffIconPreview, path or "game/ui/icon/icon_buff_debuff.dds")
    end
    api.Log:Info("[CBT] skill icon: " .. tostring(path or "?"))
end
M.onSkillIconFound = onSkillIconFound
M.onIconDumpUpdated = function()
    pcall(function() iconSearch.refresh() end)
end
local trackedBuffsList = {} -- For storing buff list widgets
local currentUnitType = "playerpet" -- By default, show settings for mount
local buffListPage = 1 -- Текущая страница пагинации для списка баффов
local buffsPerPage = 9 -- Количество записей на странице
local customBuffsList = {} -- Для хранения виджетов списка пользовательских баффов
local customBuffPage = 1 -- Текущая страница пагинации для списка пользовательских баффов
local customsPerPage = 9 -- Количество custom записей на странице

-- =========================================================================
-- Модель канвасов (1.20)
-- Вся правая колонка (иконка/сетка/позиция/таймер/цвета) читает и пишет
-- ТОЛЬКО выбранный канвас выбранного юнита: settings[unitType].canvases[i].
-- trackedBuffs/mirror — общие для юнита; canvasOf[id] задаёт канвас записи.
-- =========================================================================

local canvasPopup = nil
local canvasPopupSeq = 0
local renameWindow = nil
local deleteWindow = nil
local canvasMenuButton = nil

local function currentUnitConfig()
    if not settings then settings = helpers.getSettings() end
    return settings and settings[currentUnitType]
end

-- Индекс выбранного канваса юнита (по умолчанию текущего), всегда валидный.
local function selectedCanvasIndex(unitType)
    unitType = unitType or currentUnitType
    local s = settings
    if not s then s = helpers.getSettings() end
    local unit = s and s[unitType]
    if not unit or type(unit.canvases) ~= "table" or #unit.canvases == 0 then return 1 end
    local idx = math.floor(tonumber(unit.selectedCanvas) or 1)
    if idx < 1 then idx = 1 end
    if idx > #unit.canvases then idx = #unit.canvases end
    return idx
end

-- Конфиг выбранного канваса — единственный источник для правой колонки.
local function selectedCanvasCfg()
    local unit = currentUnitConfig()
    if not unit or type(unit.canvases) ~= "table" then return nil end
    return unit.canvases[selectedCanvasIndex()]
end

local function canvasIndexOfId(unit, buffId)
    local map = unit and unit.canvasOf
    local idx = map and tonumber(map[tostring(buffId)])
    if not idx then return 1 end
    idx = math.floor(idx)
    if idx < 1 then idx = 1 end
    return idx
end

local function setCanvasOf(buffId, index, unitType)
    local unit = unitType and settings and settings[unitType] or currentUnitConfig()
    if not unit then return end
    if type(unit.canvasOf) ~= "table" then unit.canvasOf = {} end
    unit.canvasOf[tostring(buffId)] = index
end

local function trackedForCanvas(unit, list, index)
    local out = {}
    for _, id in ipairs(list or {}) do
        if canvasIndexOfId(unit, id) == index then out[#out + 1] = id end
    end
    return out
end

local function isTrackedOnUnit(unit, buffId)
    for _, id in ipairs((unit and unit.trackedBuffs) or {}) do
        if tostring(id) == tostring(buffId) then return true end
    end
    return false
end

local function canvasName(index)
    local unit = currentUnitConfig()
    local cfg = unit and unit.canvases and unit.canvases[index]
    local name = cfg and cfg.name
    if type(name) ~= "string" or name == "" then name = "Canvas " .. tostring(index) end
    return name
end

-- Обновляет текст кнопки Presets: показывает "*", когда активен пресет
local function setPresetsButtonText()
    if settingsControls.presetsButton then
        if helpers.hasActivePreset and helpers.hasActivePreset() then
            settingsControls.presetsButton:SetText("Presets *")
        else
            settingsControls.presetsButton:SetText("Presets")
        end
    end
end

-- Сбрасывает активный пресет при ручном изменении настроек
-- (раскладка перестаёт соответствовать сохранённому пресету)
local function deactivateActivePreset()
    if helpers.hasActivePreset and helpers.hasActivePreset() then
        helpers.clearActivePreset()
        setPresetsButtonText()
    end
end

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

-- Цвет из drawable: движок отдаёт r,g,b,a отдельными значениями (иногда таблицей).
local function readDrawableColor(drawable)
    if not drawable or not drawable.GetColor then return nil end
    local ok, r, g, b, a = pcall(function() return drawable:GetColor() end)
    if not ok or r == nil then return nil end
    if type(r) == "table" then
        return { r = r.r or 1, g = r.g or 1, b = r.b or 1, a = r.a or 1 }
    end
    if type(r) ~= "number" then return nil end
    return { r = r, g = g or r, b = b or r, a = a or 1 }
end

local function saveSettings()
    -- Get current settings
    settings = helpers.getSettings()

    local unitSettings = settings[currentUnitType]
    if not unitSettings then return end

    -- Правая колонка пишет ТОЛЬКО в выбранный канвас выбранного юнита.
    local canvasIndex = selectedCanvasIndex()
    local cfg = unitSettings.canvases and unitSettings.canvases[canvasIndex]
    if not cfg then return end

    -- Снимок значений ДО записи — чтобы понять, менял ли пользователь настройки
    -- (нужно для деактивации активного пресета только при реальном изменении)
    local prevSnapshot = {
        iconSize = cfg.iconSize,
        iconSpacing = cfg.iconSpacing,
        posX = cfg.posX,
        posY = cfg.posY,
        timerFontSize = cfg.timerFontSize,
        gridColumns = cfg.gridColumns,
        gridRows = cfg.gridRows,
        maxIcons = cfg.maxIcons,
        gridRowSpacing = cfg.gridRowSpacing,
        overlayX = cfg.overlayX,
        overlayY = cfg.overlayY,
        overlaySize = cfg.overlaySize,
        overlayPerRow = cfg.overlayPerRow
    }

    -- Update icon size settings
    if settingsControls.iconSize then
        cfg.iconSize = tonumber(settingsControls.iconSize:GetText())
    end
    if settingsControls.iconSpacing then
        cfg.iconSpacing = tonumber(settingsControls.iconSpacing:GetText())
    end

    -- Check values and set default values if needed
    if not cfg.iconSize or cfg.iconSize <= 0 then
        cfg.iconSize = 40
    end

    if not cfg.iconSpacing or cfg.iconSpacing < 0 then
        cfg.iconSpacing = 5
    end

    -- Этап 4: читаем и валидируем настройки сетки иконок
    if settingsControls.gridColumns then
        cfg.gridColumns = tonumber(settingsControls.gridColumns:GetText())
    end
    if settingsControls.gridRows then
        cfg.gridRows = tonumber(settingsControls.gridRows:GetText())
    end
    if settingsControls.maxIcons then
        cfg.maxIcons = tonumber(settingsControls.maxIcons:GetText())
    end
    if settingsControls.gridRowSpacing then
        cfg.gridRowSpacing = tonumber(settingsControls.gridRowSpacing:GetText())
    end

    do
        if not cfg.gridColumns or cfg.gridColumns < 1 then cfg.gridColumns = 1 end
        if cfg.gridColumns > 40 then cfg.gridColumns = 40 end
        if not cfg.gridRows or cfg.gridRows < 1 then cfg.gridRows = 1 end
        if cfg.gridRows > 40 then cfg.gridRows = 40 end
        local capacity = cfg.gridColumns * cfg.gridRows
        if capacity > 40 then capacity = 40 end
        if not cfg.maxIcons or cfg.maxIcons < 1 then cfg.maxIcons = capacity end
        if cfg.maxIcons > capacity then cfg.maxIcons = capacity end
        if not cfg.gridRowSpacing or cfg.gridRowSpacing < 0 then cfg.gridRowSpacing = 5 end
        if cfg.gridRowSpacing > 200 then cfg.gridRowSpacing = 200 end
        -- Отражаем фактически применённые (склампленные) значения обратно в поля ввода
        if settingsControls.gridColumns then settingsControls.gridColumns:SetText(tostring(cfg.gridColumns)) end
        if settingsControls.gridRows then settingsControls.gridRows:SetText(tostring(cfg.gridRows)) end
        if settingsControls.maxIcons then settingsControls.maxIcons:SetText(tostring(cfg.maxIcons)) end
        if settingsControls.gridRowSpacing then settingsControls.gridRowSpacing:SetText(tostring(cfg.gridRowSpacing)) end
    end

    -- Update position settings
    if settingsControls.posX then
        cfg.posX = tonumber(settingsControls.posX:GetText())
    end
    if settingsControls.posY then
        cfg.posY = tonumber(settingsControls.posY:GetText())
    end
    -- Lock positioning is saved immediately on button click, use current canvas value
    if cfg.lockPositioning == nil then cfg.lockPositioning = false end

    -- 1.23.0: режимы у нативных фреймов. Пишем только значения ВИДИМЫХ
    -- контролов: скрытая секция другого юнита иначе затирала бы его поля.
    -- 1.25.0: Player-режим убран, блок есть только у цели.
    -- 1.26.0: строки под HP/MP нет, hideCanvas сохраняется сразу по клику.
    if currentUnitType == "target" then
        if settings.target then
            settings.target.ttpGap = clampIntText(
                settingsControls.ttpGap and settingsControls.ttpGap:GetText(), 0, 200, 4)
            if settingsControls.ttpGap then
                settingsControls.ttpGap:SetText(tostring(settings.target.ttpGap))
            end
            -- Поля оверлея относятся к ВЫБРАННОМУ канвасу цели.
            if settings.target.overlay == true then
                cfg.overlayX = clampIntText(
                    settingsControls.overlayX and settingsControls.overlayX:GetText(), -2000, 2000, 0)
                cfg.overlayY = clampIntText(
                    settingsControls.overlayY and settingsControls.overlayY:GetText(), -2000, 2000, -30)
                cfg.overlaySize = clampIntText(
                    settingsControls.overlaySize and settingsControls.overlaySize:GetText(), 12, 64, 26)
                cfg.overlayPerRow = clampIntText(
                    settingsControls.overlayPerRow and settingsControls.overlayPerRow:GetText(), 1, 12, 6)
                if settingsControls.overlayX then settingsControls.overlayX:SetText(tostring(cfg.overlayX)) end
                if settingsControls.overlayY then settingsControls.overlayY:SetText(tostring(cfg.overlayY)) end
                if settingsControls.overlaySize then settingsControls.overlaySize:SetText(tostring(cfg.overlaySize)) end
                if settingsControls.overlayPerRow then settingsControls.overlayPerRow:SetText(tostring(cfg.overlayPerRow)) end
            end
        end
    end

    -- Update timer settings (per canvas)
    if settingsControls.timerFontSize then
        cfg.timerFontSize = tonumber(settingsControls.timerFontSize:GetText())
    end

    if settingsControls.timerTextColor and settingsControls.timerTextColor.colorBG then
        local rgb = readDrawableColor(settingsControls.timerTextColor.colorBG)
        if rgb then cfg.timerTextColor = rgb end
    end

    if settingsControls.labelTextColor and settingsControls.labelTextColor.colorBG then
        local lblRgb = readDrawableColor(settingsControls.labelTextColor.colorBG)
        if lblRgb then cfg.labelTextColor = lblRgb end
    end

    -- Если настройки этого канваса реально изменились — деактивируем пресет
    if cfg.iconSize ~= prevSnapshot.iconSize
        or cfg.iconSpacing ~= prevSnapshot.iconSpacing
        or cfg.posX ~= prevSnapshot.posX
        or cfg.posY ~= prevSnapshot.posY
        or cfg.timerFontSize ~= prevSnapshot.timerFontSize
        or cfg.gridColumns ~= prevSnapshot.gridColumns
        or cfg.gridRows ~= prevSnapshot.gridRows
        or cfg.maxIcons ~= prevSnapshot.maxIcons
        or cfg.gridRowSpacing ~= prevSnapshot.gridRowSpacing
        or cfg.overlayX ~= prevSnapshot.overlayX
        or cfg.overlayY ~= prevSnapshot.overlayY
        or cfg.overlaySize ~= prevSnapshot.overlaySize
        or cfg.overlayPerRow ~= prevSnapshot.overlayPerRow then
        deactivateActivePreset()
    end

    -- Сохраняем пользовательские баффы
    local currentCustomBuffs = settings.customBuffs or {}
    settings.customBuffs = {}

    -- Если есть баффы в текущих настройках, используем их
    if settings.customBuffs and #settings.customBuffs > 0 then
        for i, buffData in ipairs(settings.customBuffs) do
            local buff = {}
            for k, v in pairs(buffData) do
                buff[k] = v
            end
            table.insert(settings.customBuffs, buff)
        end
    elseif currentCustomBuffs and #currentCustomBuffs > 0 then
        for i, buffData in ipairs(currentCustomBuffs) do
            local buff = {}
            for k, v in pairs(buffData) do
                buff[k] = v
            end
            table.insert(settings.customBuffs, buff)
        end
    end

    -- Debug mode is saved immediately on button click, use current settings value
    settings.debugBuffId = settings.debugBuffId or false

    -- Save settings and explicitly apply
    api.SaveSettings()

    -- Save settings through helpers, which will completely restart UI
    if helpers and helpers.updateSettings then
        helpers.updateSettings()
    end
end

-- Применять значение поля по Enter (та же логика, что у кнопки Save),
-- чтобы не ждать клика по кнопке.
local function applySaveKeepPages()
    local keepPage, keepCustomPage = buffListPage, customBuffPage
    settings = helpers.getSettings()
    saveSettings()
    buffListPage, customBuffPage = keepPage, keepCustomPage
    pcall(updateTrackedBuffsList)
    pcall(updateCustomBuffsList)
end

local function bindApplyOnEnter(edit)
    if not edit or not edit.SetHandler then return end
    edit:SetHandler("OnEnterPressed", function(self)
        if self and self.ClearFocus then self:ClearFocus() end
        applySaveKeepPages()
    end)
end

-- Нормализует путь иконки: пустая строка -> nil, имя файла -> game/ui/icon/<file>
local function normalizeIconPath(text)
    text = text or ""
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    if not string.find(text, "/", 1, true) then
        text = "game/ui/icon/" .. text
    end
    return text
end

-- Тип кастомной записи: kind из настроек, иначе эвристика по данным записи
-- (manaCost > 0 -> mana, spellName задан -> skill, иначе buff). Для трекнутых
-- id без кастомной записи тип всегда buff.
local function kindOfId(buffId)
    local s = settings or helpers.getSettings()
    local key = tostring(buffId)
    for _, cb in ipairs((s and s.customBuffs) or {}) do
        if cb and tostring(cb.id) == key then
            if defaultSettings and defaultSettings.entryKind then
                return defaultSettings.entryKind(cb)
            end
            return cb.kind or "buff"
        end
    end
    return "buff"
end

-- Одна точка входа в окно поиска иконок: провайдер, скан и выбор пути.
-- После выбора окно закрывается (1.22.0: выбор иконки завершает диалог).
local function openIconSearchFor(initialQuery, applyFn)
    iconSearch.setProvider(function(q, l) return M.searchIcons and M.searchIcons(q, l) or {} end)
    iconSearch.setScanStarter(function() if M.startScan then M.startScan("") end end)
    iconSearch.setPicker(function(path, name)
        if applyFn then applyFn(path, name) end
        if iconSearch.close then iconSearch.close() end
        api.Log:Info("[CBT] icon picked: " .. tostring(name or "") .. " -> " .. tostring(path or ""))
    end)
    iconSearch.open(initialQuery or "")
end

-- Показать/скрыть панель ошибки формы Add custom entry.
local function showCustomError(msg)
    if settingsControls.addCustomBuffError and settingsControls.customBuffErrorPanel then
        settingsControls.addCustomBuffError:SetText(msg)
        settingsControls.customBuffErrorPanel:Show(true)
    end
end

-- Иконка по умолчанию для записей без своей иконки
local DEFAULT_ENTRY_ICON = "game/ui/icon/icon_buff_debuff.dds"

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

    local buffId = settingsControls.newBuffId:GetText() or ""
    buffId = buffId:gsub("^%s+", ""):gsub("%s+$", "")

    if buffId == "" then
        if settingsControls.addBuffError and settingsControls.errorPanel then
            settingsControls.addBuffError:SetText("Error: enter a buff ID or the skill name")
            settingsControls.errorPanel:Show(true)
        end
        return
    end

    -- Ищем сначала по ID, затем по отображаемому имени и по имени навыка (spellName)
    local resolvedId = nil
    if settings and settings.customBuffs then
        for _, buffInfo in ipairs(settings.customBuffs) do
            if buffInfo.id == buffId then
                resolvedId = buffInfo.id
                break
            end
        end
        if not resolvedId then
            for _, buffInfo in ipairs(settings.customBuffs) do
                if buffInfo.name == buffId or buffInfo.spellName == buffId then
                    resolvedId = buffInfo.id
                    break
                end
            end
        end
    end

    if not resolvedId then
        -- Показываем ошибку, если баф не найден в списке кастомных бафов
        if settingsControls.addBuffError and settingsControls.errorPanel then
            settingsControls.addBuffError:SetText("Error: '" .. buffId .. "' not found - add it as a custom buff first")
            settingsControls.errorPanel:Show(true)
        end
        return
    end

    buffId = resolvedId

    -- Запись попадает на ВЫБРАННЫЙ канвас выбранного юнита (уже отслеживаемую
    -- запись не переносим: для переноса есть кнопка Mv)
    if not isTrackedOnUnit(currentUnitConfig(), buffId) then
        setCanvasOf(buffId, selectedCanvasIndex(currentUnitType), currentUnitType)
    end

    -- Try to add buff for selected unit type
    if BuffsToTrack.AddTrackedBuff(buffId, currentUnitType) then
        -- Список баффов изменился — активный пресет больше не актуален
        deactivateActivePreset()

        -- Clear input field
        settingsControls.newBuffId:SetText("")
        if settingsControls.hideAc then settingsControls.hideAc() end

        -- Hide error message
        if settingsControls.errorPanel then
            settingsControls.errorPanel:Show(false)
        end

        -- Update main interface
        if helpers and helpers.updateSettings then
            helpers.updateSettings()
        end

        -- Explicitly call buffs list update event
        api:Emit("ADDON_CBT_BUFFS_CHANGED")

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

-- Добавляет бафф из окна поиска: гарантирует наличие в customBuffs и
-- добавляет его в отслеживание для текущего типа юнита. Возвращает ok, message.
local function addBuffFromSearch(buffId, unitType)
    if not buffId or buffId == "" then
        return false, "Invalid buff ID"
    end
    unitType = unitType or currentUnitType

    settings = helpers.getSettings()

    -- Гарантируем, что бафф есть в списке customBuffs (без этого его нельзя отслеживать)
    local inCustom = false
    if settings.customBuffs then
        for _, buffInfo in ipairs(settings.customBuffs) do
            if tostring(buffInfo.id) == tostring(buffId) then
                inCustom = true
                break
            end
        end
    end

    if not inCustom then
        if not settings.customBuffs then settings.customBuffs = {} end
        local nm = (BuffList.GetBuffName and BuffList.GetBuffName(buffId)) or ("Buff #" .. buffId)
        local cd = (BuffList.GetBuffCooldown and BuffList.GetBuffCooldown(buffId)) or 30
        local toa = (BuffList.GetBuffTimeOfAction and BuffList.GetBuffTimeOfAction(buffId)) or 5
        local newEntry = { id = buffId, name = nm, cooldown = cd, timeOfAction = toa, kind = "buff" }
        table.insert(settings.customBuffs, newEntry)
        pcall(function() api.SaveSettings() end)
        updateCustomBuffsList(true)
    end

    -- Добавляем в отслеживание для выбранного типа юнита (на его выбранный канвас)
    if not isTrackedOnUnit(settings and settings[unitType], buffId) then
        setCanvasOf(buffId, selectedCanvasIndex(unitType), unitType)
    end
    if BuffsToTrack.AddTrackedBuff(buffId, unitType) then
        -- Список баффов изменился — активный пресет больше не актуален
        deactivateActivePreset()

        if helpers and helpers.updateSettings then
            helpers.updateSettings()
        end
        api:Emit("ADDON_CBT_BUFFS_CHANGED")

        -- Перейти на последнюю страницу, чтобы показать добавленный бафф
        local trackedBuffs = BuffsToTrack.GetAllTrackedBuffIds(unitType)
        buffListPage = math.max(1, math.ceil(#trackedBuffs / buffsPerPage))
        if settingsControls.updateVisibleItems then
            settingsControls.updateVisibleItems()
        end

        return true, "Added to " .. tostring(unitType)
    else
        return false, "Already tracked (" .. tostring(unitType) .. ")"
    end
end

-- Записывает навык из боевого лога как кастомный бафф (CD/D пользователь
-- поправит вручную) и добавляет его в отслеживание текущего типа юнита.
local function addCustomFromSpell(spellName, unitType)
    if not spellName or spellName == "" then
        return false, "Invalid spell name"
    end
    unitType = unitType or currentUnitType
    settings = helpers.getSettings()
    if not settings.customBuffs then settings.customBuffs = {} end
    local exists = nil
    for _, cb in ipairs(settings.customBuffs) do
        if cb.id == spellName then exists = cb; break end
    end
    if not exists then
        local iconPath = nil
        if M.findIconByName then
            local ok, p = pcall(M.findIconByName, spellName)
            if ok then iconPath = p end
        end
        local entry = {
            id = spellName,
            name = spellName,
            spellName = spellName,
            cooldown = 0,
            timeOfAction = 0,
            iconFile = iconPath,
            kind = "skill",
        }
        table.insert(settings.customBuffs, entry)
        pcall(function() api.SaveSettings() end)
        updateCustomBuffsList(true)
    end
    if not isTrackedOnUnit(settings and settings[unitType], spellName) then
        setCanvasOf(spellName, selectedCanvasIndex(unitType), unitType)
    end
    if BuffsToTrack.AddTrackedBuff(spellName, unitType) then
        deactivateActivePreset()
        if helpers and helpers.updateSettings then helpers.updateSettings() end
        api:Emit("ADDON_CBT_BUFFS_CHANGED")
        return true, "Added skill: " .. tostring(spellName)
    end
    return false, "Already tracked: " .. tostring(spellName)
end

-- Добавляет запись выбранного типа: бафф/дебафф, навык по боевому логу или
-- навык маунта, который тратит ману. Обязательные поля у каждого типа свои.
local function addCustomBuff()
    local kind = newEntryKind or "buff"

    local id = trimText(settingsControls.newCustomBuffId and settingsControls.newCustomBuffId:GetText())
    local name = trimText(settingsControls.newCustomBuffName and settingsControls.newCustomBuffName:GetText())
    local cooldown = tonumber(settingsControls.newCustomBuffCooldown and settingsControls.newCustomBuffCooldown:GetText())
    local timeOfAction = tonumber(settingsControls.newCustomBuffTimeOfAction
        and settingsControls.newCustomBuffTimeOfAction:GetText())
    local spellName = trimText(settingsControls.newCustomBuffSpell and settingsControls.newCustomBuffSpell:GetText())
    local manaCost = tonumber(settingsControls.newCustomBuffMana and settingsControls.newCustomBuffMana:GetText()) or 0
    local mountName = trimText(settingsControls.newCustomBuffMount and settingsControls.newCustomBuffMount:GetText())
    if manaCost < 0 then manaCost = 0 end

    -- Duration не вводится для навыков: активной фазы у них нет
    if kind ~= "buff" then timeOfAction = 0 end

    if kind == "skill" then
        -- Ключ навыка — имя из боевого лога (spell), подпись — Name или spell
        if id == "" then id = spellName end
        if name == "" then name = spellName end
        if spellName == "" or not cooldown then
            showCustomError("Error: spell name and cooldown are required")
            return
        end
    elseif kind == "mana" then
        if id == "" then id = name end
        if name == "" or not cooldown or manaCost <= 0 or mountName == "" then
            showCustomError("Error: name, cooldown, mana cost and mount name are required")
            return
        end
    else
        if id == "" or name == "" or not cooldown or not timeOfAction then
            showCustomError("Error: ID, name, cooldown and duration are required")
            return
        end
    end
    if cooldown < 0 then
        showCustomError("Error: cooldown must be 0 or more")
        return
    end
    if kind == "buff" and timeOfAction < 0 then
        showCustomError("Error: duration must be 0 or more")
        return
    end

    -- Дубликат по ключу: запись с таким id уже есть
    if settings and settings.customBuffs then
        for _, buffInfo in ipairs(settings.customBuffs) do
            if tostring(buffInfo.id) == id then
                showCustomError("Error: entry with this ID already exists")
                return
            end
        end
    end

    -- Иконка необязательна: выбранная вручную, затем по id/имени, иначе нейтральная
    local iconPath = normalizeIconPath(newEntryIcon)
    if not iconPath and kind == "buff" then
        iconPath = BuffList.GetBuffIcon(id)
    end
    if not iconPath and M.findIconByName then
        local lookup = (kind == "skill") and (name ~= "" and name or spellName) or name
        if lookup and lookup ~= "" then
            local ok, p = pcall(M.findIconByName, lookup)
            if ok and p and p ~= "" then iconPath = p end
        end
    end
    if not iconPath or iconPath == "" then iconPath = DEFAULT_ENTRY_ICON end

    local newBuff = {
        id = id,
        name = name,
        cooldown = cooldown,
        timeOfAction = timeOfAction,
        kind = kind,
        iconFile = iconPath,
    }
    if kind == "skill" then
        newBuff.spellName = spellName
    elseif kind == "mana" then
        newBuff.manaCost = manaCost
        newBuff.mountName = mountName
    end

    if not settings.customBuffs then
        settings.customBuffs = {}
    end
    table.insert(settings.customBuffs, newBuff)

    -- Очищаем поля ввода (тип остаётся выбранным)
    for _, field in ipairs({
        settingsControls.newCustomBuffId,
        settingsControls.newCustomBuffName,
        settingsControls.newCustomBuffCooldown,
        settingsControls.newCustomBuffTimeOfAction,
        settingsControls.newCustomBuffSpell,
        settingsControls.newCustomBuffMana,
        settingsControls.newCustomBuffMount,
    }) do
        if field then field:SetText("") end
    end
    newEntryIcon = ""
    if settingsControls.customBuffIconPreview then
        F_SLOT.SetIconBackGround(settingsControls.customBuffIconPreview, DEFAULT_ENTRY_ICON)
    end
    if settingsControls.customBuffErrorPanel then
        settingsControls.customBuffErrorPanel:Show(false)
    end

    if helpers and helpers.updateSettings then
        helpers.updateSettings()
    end

    -- Go to last page to show newly added entry
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

    -- Правая колонка показывает значения ВЫБРАННОГО канваса.
    local unitSettings = settings[currentUnitType]
    local cfg = unitSettings.canvases and unitSettings.canvases[selectedCanvasIndex()] or {}
    unitSettings.selectedCanvas = selectedCanvasIndex()

    -- Имя канваса в селекторе
    if canvasMenuButton then
        canvasMenuButton:SetText("Canvas: " .. canvasName(unitSettings.selectedCanvas))
    end

    -- Update position fields
    if settingsControls.posX then
        settingsControls.posX:SetText(tostring(cfg.posX or 0))
    end

    if settingsControls.posY then
        settingsControls.posY:SetText(tostring(cfg.posY or 0))
    end

    -- Update lock button text
    if settingsControls.lockButton then
        settingsControls.lockButton:SetText(cfg.lockPositioning and "Lock: ON" or "Lock: OFF")
    end

    -- Update debug button text (global setting, not per unit type)
    if settingsControls.debugBuffButton then
        settingsControls.debugBuffButton:SetText(settings.debugBuffId and "Debug: ON" or "Debug: OFF")
    end

    -- Update timer settings
    if settingsControls.timerFontSize then
        settingsControls.timerFontSize:SetText(tostring(cfg.timerFontSize or 16))
    end

    -- Update timer text color
    if settingsControls.timerTextColor and settingsControls.timerTextColor.colorBG then
        local textColor = cfg.timerTextColor or {r = 1, g = 1, b = 1, a = 1}
        settingsControls.timerTextColor.colorBG:SetColor(
            textColor.r or 1,
            textColor.g or 1,
            textColor.b or 1,
            1
        )
    end

    -- Update label text color
    if settingsControls.labelTextColor and settingsControls.labelTextColor.colorBG then
        local lblColor = cfg.labelTextColor or {r = 1, g = 1, b = 1, a = 1}
        settingsControls.labelTextColor.colorBG:SetColor(
            lblColor.r or 1,
            lblColor.g or 1,
            lblColor.b or 1,
            1
        )
    end

    -- Update icon size settings
    if settingsControls.iconSize then
        settingsControls.iconSize:SetText(tostring(cfg.iconSize or 40))
    end

    if settingsControls.iconSpacing then
        settingsControls.iconSpacing:SetText(tostring(cfg.iconSpacing or 5))
    end

    -- Этап 4: поля сетки иконок
    if settingsControls.gridColumns then
        settingsControls.gridColumns:SetText(tostring(cfg.gridColumns or 10))
    end

    if settingsControls.gridRows then
        settingsControls.gridRows:SetText(tostring(cfg.gridRows or 1))
    end

    if settingsControls.maxIcons then
        local defMax = (cfg.gridColumns or 10) * (cfg.gridRows or 1)
        settingsControls.maxIcons:SetText(tostring(cfg.maxIcons or defMax))
    end

    if settingsControls.gridRowSpacing then
        settingsControls.gridRowSpacing:SetText(tostring(cfg.gridRowSpacing or cfg.iconSpacing or 5))
    end

    -- Update label settings
    if settingsControls.labelFontSize then
        settingsControls.labelFontSize:SetText(tostring(cfg.labelFontSize or 14))
    end

    if settingsControls.labelX then
        settingsControls.labelX:SetText(tostring(cfg.labelX or 0))
    end

    if settingsControls.labelY then
        settingsControls.labelY:SetText(tostring(cfg.labelY or -30))
    end

    -- Update show label button text
    if settingsControls.showLabel then
        settingsControls.showLabel:SetText(cfg.showLabel and "Show label: ON" or "Show label: OFF")
    end

    if settingsControls.showTimer then
        settingsControls.showTimer:SetChecked(cfg.showTimer ~= false) -- Default enabled
    end

    -- Update tracked buffs list (только записи выбранного канваса)
    updateTrackedBuffsList()

    -- 1.23.0: режимы у нативных фреймов (видимость контролов + значения)
    if syncFrameModeControls then
        pcall(syncFrameModeControls)
    end
end

-- Функция для добавления кнопки просмотра пиксельного изображения
local function addPixelViewerButton()
    if settingsWindow and settingsControls.debugBuffButton then
        -- Создаем кнопку для открытия окна просмотра пиксельного изображения
        -- Привязываем кнопку ПОД настройки сетки (gridBottomLabel), чтобы она не
        -- накладывалась на grid. Фолбэк — старый якорь, если grid почему-то нет.
        local thanksParent = settingsControls.gridBottomLabel or settingsControls.addCustomBuffButton
        local thanksX = settingsControls.gridBottomLabel and 0 or -25
        local thanksY = settingsControls.gridBottomLabel and 35 or 80
        local pixelViewButton = helpers.createButton('pixelViewButton', settingsWindow, 'Thank you for your hard work!', 0, 0)
        pixelViewButton:RemoveAllAnchors()
        pixelViewButton:AddAnchor("BOTTOMRIGHT", settingsWindow, -150, -18)
        pixelViewButton:SetExtent(200, 26)
        pixelViewButton:SetHandler("OnClick", function()
            pixelViewer.openPixelWindow()
        end)
        pixelViewButton:Show(true)
        settingsControls.pixelViewButton = pixelViewButton
    end
end



-- Редактор записи: тип (Buff/Debuff | Skill | Mana skill) + поля этого типа.
-- Кастомная запись обновляется напрямую, обычный отслеживаемый id — через
-- settings.buffOverrides (у него есть только CD/D).
local cddWindow = nil

local function openCddDialog(buffId)
    local s = helpers.getSettings()
    if type(s.buffOverrides) ~= "table" then s.buffOverrides = {} end
    local key = tostring(buffId)

    local cb = nil
    for _, item in ipairs(s.customBuffs or {}) do
        if tostring(item.id) == key then cb = item; break end
    end

    local curCd, curToa, curMana, curMount, curName, curSpell, curIcon
    local editKind = "buff"
    if cb then
        curCd = tonumber(cb.cooldown) or 0
        curToa = tonumber(cb.timeOfAction) or 0
        curMana = tonumber(cb.manaCost) or 0
        curMount = cb.mountName or ""
        curName = cb.name or ""
        curSpell = cb.spellName or ""
        curIcon = cb.iconFile or ""
        editKind = (defaultSettings and defaultSettings.entryKind)
            and defaultSettings.entryKind(cb) or "buff"
    else
        local ov = s.buffOverrides[key]
        if ov then
            curCd = tonumber(ov.cooldown) or 0
            curToa = tonumber(ov.timeOfAction) or 0
        else
            curCd = tonumber(BuffList.GetBuffCooldown(buffId)) or 30
            curToa = tonumber(BuffList.GetBuffTimeOfAction(buffId)) or 3
        end
        curMana = 0
        curMount = ""
        curName = BuffList.GetBuffName(buffId) or ""
        curSpell = ""
        curIcon = BuffList.GetBuffIcon(buffId) or ""
    end

    if cddWindow then
        pcall(function() CbtWindow.Destroy(cddWindow) end)
        cddWindow = nil
    end
    local wnd = CbtWindow.Create("cbtCddWindow", "Entry: cooldown / duration", 520, 300, function()
        if cddWindow then cddWindow:Show(false) end
    end)
    if not wnd then return end
    cddWindow = wnd
    wnd:Show(true)

    -- Заголовок: не дублируем name/Spell/id и обрезаем длинные строки
    local dispName = (cb and cb.name and cb.name ~= "" and cb.name) or BuffList.GetBuffName(buffId) or ""
    dispName = tostring(dispName)
    local dispSpell = (cb and cb.spellName and cb.spellName ~= "" and cb.spellName) or ""
    dispSpell = tostring(dispSpell)
    local parts = {}
    if dispName ~= "" then parts[#parts + 1] = dispName end
    if dispSpell ~= "" and dispSpell ~= dispName then parts[#parts + 1] = "[" .. dispSpell .. "]" end
    if key ~= "" and key ~= dispName and key ~= dispSpell then parts[#parts + 1] = "(" .. key .. ")" end
    local titleText = table.concat(parts, " ")
    if titleText == "" then titleText = key end
    if #titleText > 62 then titleText = titleText:sub(1, 59) .. "..." end

    local title = helpers.createLabel('cbtCddName', wnd, titleText, 15, 42, 14)
    title:SetWidth(490)
    title:Show(true)

    ---------------------------------------------------------------
    -- Переключатель типа: только для кастомных записей. У обычного
    -- отслеживаемого id есть лишь CD/D (settings.buffOverrides).
    ---------------------------------------------------------------
    local typeButtons = {}
    local applyType
    if cb then
        local typeLabel = helpers.createLabel('cbtCddTypeLabel', wnd, 'Type:', 15, 70, 13)
        typeLabel:SetWidth(38)
        pcall(function() typeLabel.style:SetColor(0.72, 0.74, 0.80, 1) end)
        typeLabel:Show(true)

        local specs = {
            { kind = 'buff',  text = 'Buff/Debuff', x = 55,  w = 100 },
            { kind = 'skill', text = 'Skill',       x = 159, w = 66  },
            { kind = 'mana',  text = 'Mana skill',  x = 229, w = 92  },
        }
        for _, spec in ipairs(specs) do
            local b = helpers.createButton('cbtCddType_' .. spec.kind, wnd, spec.text, spec.x, 66)
            b:SetExtent(spec.w, 24)
            b:Show(true)
            b:SetHandler("OnClick", function()
                if applyType then applyType(spec.kind) end
            end)
            typeButtons[spec.kind] = b
        end
    end

    local function makeFieldEdit(id, text, labelW, editW, y)
        local lbl = helpers.createLabel(id .. 'Label', wnd, text, 15, y, 13)
        lbl:SetWidth(labelW)
        lbl:Show(true)
        local edit = helpers.createEdit(id, lbl, "", labelW + 6, 0)
        edit:SetWidth(editW)
        edit:Show(true)
        return lbl, edit
    end

    -- ID у баффа не меняется: по нему запись ищется в списках
    local idLabel = helpers.createLabel('cbtCddKeyLabel', wnd, 'ID:', 15, 104, 13)
    idLabel:SetWidth(20)
    idLabel:Show(true)
    local idValue = helpers.createLabel('cbtCddKey', wnd, key, 42, 104, 13)
    idValue:SetWidth(70)
    pcall(function() idValue.style:SetColor(0.95, 0.80, 0.25, 1) end)
    idValue:Show(true)

    local nameLabel, nameEdit = makeFieldEdit('cbtCddNameEdit', 'Name:', 36, 150, 134)
    local cdLabel, cdEdit = makeFieldEdit('cbtCddCd', 'Cooldown:', 58, 44, 134)
    local toaLabel, toaEdit = makeFieldEdit('cbtCddToa', 'Duration:', 60, 48, 166)
    local spellLabel, spellEdit = makeFieldEdit('cbtCddSpell', 'Spell:', 34, 320, 166)
    local manaLabel, manaEdit = makeFieldEdit('cbtCddMana', 'Mana:', 30, 60, 166)
    local mountLabel, mountEdit = makeFieldEdit('cbtCddMount', 'Mount:', 38, 220, 166)
    nameEdit:SetText(curName)
    cdEdit:SetText(tostring(curCd))
    toaEdit:SetText(tostring(curToa))
    spellEdit:SetText(curSpell)
    manaEdit:SetText(tostring(curMana))
    mountEdit:SetText(curMount)
    nameEdit:SetMaxTextLength(60)
    spellEdit:SetMaxTextLength(60)
    mountEdit:SetMaxTextLength(60)
    cdEdit:SetMaxTextLength(6)
    toaEdit:SetMaxTextLength(6)
    manaEdit:SetMaxTextLength(7)

    -- Иконка записи: превью кликабельно, выбор в окне поиска закрывает его
    local editIcon = curIcon or ""
    local iconPreview = CreateItemIconButton('cbtCddIconPreview', wnd)
    if iconPreview then
        iconPreview:SetExtent(28, 28)
        iconPreview:AddAnchor("TOPLEFT", wnd, 470, 132)
        if iconPreview.RegisterForClicks then
            pcall(function() iconPreview:RegisterForClicks("LeftButton") end)
        end
        iconPreview:Show(true)
    end

    local function refreshEditIcon()
        if not iconPreview then return end
        local p = editIcon
        if not p or p == "" then p = DEFAULT_ENTRY_ICON end
        pcall(function() F_SLOT.SetIconBackGround(iconPreview, p) end)
    end
    refreshEditIcon()

    if iconPreview then
        iconPreview:SetHandler("OnClick", function()
            local query = ""
            if spellEdit:IsVisible() then query = trimText(spellEdit:GetText()) end
            if query == "" then query = trimText(nameEdit:GetText()) end
            if query == "" then query = key end
            openIconSearchFor(query, function(path)
                editIcon = path or ""
                refreshEditIcon()
            end)
        end)
    end

    local function placeLabel(lbl, x, y)
        if not lbl then return end
        lbl:RemoveAllAnchors()
        lbl:AddAnchor("TOPLEFT", wnd, x, y)
    end

    local function showField(lbl, edit, shown)
        if lbl then lbl:Show(shown) end
        if edit then edit:Show(shown) end
    end

    local errorLabel = helpers.createLabel('cbtCddError', wnd, '', 15, 206, 13)
    errorLabel:SetWidth(490)
    pcall(function() errorLabel.style:SetColor(0.95, 0.45, 0.45, 1) end)
    errorLabel:Show(false)

    local hint = helpers.createLabel('cbtCddHint', wnd,
        'Cooldown / Duration are seconds; 0 is valid. Icon is optional.', 15, 222, 12)
    hint:SetWidth(490)
    pcall(function() hint.style:SetColor(0.72, 0.74, 0.80, 1) end)
    hint:Show(true)

    applyType = function(kind)
        editKind = kind
        for k, b in pairs(typeButtons) do
            if b.textLabel then
                if k == kind then
                    pcall(function() b.textLabel.style:SetColor(0.95, 0.80, 0.25, 1) end)
                else
                    pcall(function() b.textLabel.style:SetColor(0.60, 0.62, 0.68, 1) end)
                end
            end
        end

        local isBuff = (kind == 'buff')
        local isSkill = (kind == 'skill')
        local isMana = (kind == 'mana')

        -- У обычного отслеживаемого id нет кастомной записи: правятся только
        -- CD/D (buffOverrides), поэтому имя и иконка не редактируются.
        local canEditEntry = (cb ~= nil)

        showField(idLabel, nil, isBuff)
        idValue:Show(isBuff)
        showField(toaLabel, toaEdit, isBuff)
        showField(spellLabel, spellEdit, isSkill)
        showField(manaLabel, manaEdit, isMana)
        showField(mountLabel, mountEdit, isMana)
        showField(nameLabel, nameEdit, canEditEntry)
        showField(cdLabel, cdEdit, true)
        if iconPreview then iconPreview:Show(canEditEntry) end

        if isBuff then
            placeLabel(idLabel, 15, 104)
            placeLabel(idValue, 42, 104)
            if canEditEntry then
                placeLabel(nameLabel, 120, 104)
                placeLabel(cdLabel, 320, 104)
            else
                placeLabel(cdLabel, 120, 104)
            end
            placeLabel(toaLabel, 15, 136)
        else
            placeLabel(nameLabel, 15, 104)
            placeLabel(cdLabel, 265, 104)
            if isSkill then
                placeLabel(spellLabel, 15, 136)
                if trimText(spellEdit:GetText()) == "" then
                    local pre = trimText(nameEdit:GetText())
                    if pre ~= "" then spellEdit:SetText(pre) end
                end
            elseif isMana then
                placeLabel(manaLabel, 15, 136)
                placeLabel(mountLabel, 120, 136)
            end
        end
        errorLabel:Show(false)
        refreshEditIcon()
    end

    applyType(cb and editKind or 'buff')

    local function validate(kind)
        local cd = tonumber(cdEdit:GetText())
        if not cd or cd < 0 then return "Cooldown must be a number >= 0" end
        if kind == "buff" then
            local toa = tonumber(toaEdit:GetText())
            if not toa or toa < 0 then return "Duration must be a number >= 0" end
            if trimText(nameEdit:GetText()) == "" then return "Name is required" end
        elseif kind == "skill" then
            if trimText(spellEdit:GetText()) == "" then return "Spell name is required" end
        elseif kind == "mana" then
            local mana = tonumber(manaEdit:GetText())
            if not mana or mana <= 0 then return "Mana cost must be > 0" end
            if trimText(mountEdit:GetText()) == "" then return "Mount name is required" end
            if trimText(nameEdit:GetText()) == "" then return "Name is required" end
        end
        return nil
    end

    local saveBtn = helpers.createButton('cbtCddSave', wnd, 'Save', 15, 250)
    saveBtn:SetExtent(120, 26)
    saveBtn:Show(true)
    saveBtn:SetHandler("OnClick", function()
        local err = validate(editKind)
        if err then
            errorLabel:SetText("Error: " .. err)
            errorLabel:Show(true)
            return
        end

        local cd = tonumber(cdEdit:GetText()) or 0
        local toa = tonumber(toaEdit:GetText()) or 0
        local mana = tonumber(manaEdit:GetText()) or 0
        local mount = trimText(mountEdit:GetText())
        local name = trimText(nameEdit:GetText())
        local spell = trimText(spellEdit:GetText())
        if cd < 0 then cd = 0 end
        if toa < 0 then toa = 0 end
        if mana < 0 then mana = 0 end
        if editKind ~= "buff" then toa = 0 end

        if cb then
            local prevKind = (defaultSettings and defaultSettings.entryKind)
                and defaultSettings.entryKind(cb) or (cb.kind or "buff")
            cb.kind = editKind
            cb.cooldown = cd
            cb.timeOfAction = toa
            if name ~= "" then
                cb.name = name
            elseif editKind == "skill" and spell ~= "" then
                cb.name = spell
            end
            if editKind == "skill" then
                cb.spellName = spell
                cb.manaCost = nil
                cb.mountName = nil
            elseif editKind == "mana" then
                cb.manaCost = mana
                cb.mountName = mount
                cb.spellName = nil
            else
                cb.spellName = nil
                cb.manaCost = nil
                cb.mountName = nil
            end

            local iconPath = normalizeIconPath(editIcon)
            if not iconPath and editKind == "buff" then
                iconPath = BuffList.GetBuffIcon(cb.id)
            end
            if not iconPath and M.findIconByName then
                local lookup = (name ~= "" and name or spell)
                if lookup ~= "" then
                    local ok, p = pcall(M.findIconByName, lookup)
                    if ok and p and p ~= "" then iconPath = p end
                end
            end
            cb.iconFile = iconPath or DEFAULT_ENTRY_ICON

            -- Mirror допустим только для баффов/дебаффов: снимаем флаг у всех юнитов
            if editKind ~= "buff" then
                for _, ut in ipairs({ "playerpet", "player", "target" }) do
                    local unit = s[ut]
                    if unit and type(unit.mirror) == "table" then
                        unit.mirror[key] = nil
                    end
                end
            end

            api.Log:Info(string.format("[CBT] entry %s: type=%s CD=%s D=%s%s",
                tostring(cb.id), tostring(editKind), tostring(cd), tostring(toa),
                (prevKind ~= editKind) and (" (was " .. tostring(prevKind) .. ")") or ""))
        else
            s.buffOverrides[key] = { cooldown = cd, timeOfAction = toa }
            api.Log:Info(string.format("[CBT] CD/D %s: CD=%s D=%s", key, tostring(cd), tostring(toa)))
        end

        api.SaveSettings()
        if M.applyBuffOverride then M.applyBuffOverride(buffId, cd, toa) end
        deactivateActivePreset()
        -- Сохраняем страницу списков: правка записи не должна сбрасывать пагинацию
        pcall(updateCustomBuffsList)
        pcall(updateTrackedBuffsList)
        if helpers and helpers.updateSettings then
            pcall(helpers.updateSettings)
        end
        api:Emit("ADDON_CBT_BUFFS_CHANGED")
        wnd:Show(false)
    end)

    local cancelBtn = helpers.createButton('cbtCddCancel', wnd, 'Cancel', 145, 250)
    cancelBtn:SetExtent(100, 26)
    cancelBtn:Show(true)
    cancelBtn:SetHandler("OnClick", function() wnd:Show(false) end)
end

-- =========================================================================
-- Селектор канвасов: выпадающий список + Add / Rename / Delete
-- =========================================================================

local closeCanvasPopup

closeCanvasPopup = function()
    if canvasPopup then
        pcall(function() CbtWindow.Destroy(canvasPopup) end)
        canvasPopup = nil
    end
end

-- Небольшой тёмный попап со списком кнопок (селектор канваса и Mv).
local function showCanvasPopup(title, items, onPick)
    closeCanvasPopup()
    canvasPopupSeq = canvasPopupSeq + 1
    local seq = canvasPopupSeq
    local w = CbtWindow.Create("cbtCanvasPopup" .. tostring(seq), title, 250, 78 + #items * 26, closeCanvasPopup)
    if not w then return end
    canvasPopup = w

    local hint = helpers.createLabel("cbtCanvasPopupHint" .. tostring(seq), w, "Select canvas:", 15, 42, 13)
    hint:SetWidth(215)
    hint.style:SetColor(0.72, 0.74, 0.80, 1)
    hint:Show(true)

    for i, item in ipairs(items) do
        local b = helpers.createButton("cbtCanvasPopupBtn" .. tostring(seq) .. "_" .. tostring(i), w, item.label, 15, 66 + (i - 1) * 26)
        b:SetExtent(220, 22)
        b:Show(true)
        if item.current then
            pcall(function() b.textLabel.style:SetColor(0.55, 0.95, 0.55, 1) end)
        end
        b:SetHandler("OnClick", function()
            closeCanvasPopup()
            if onPick then onPick(item.value) end
        end)
    end

    w:Show(true)
end

-- Список канвасов текущего юнита в выпадающем меню.
local function openCanvasListPopup()
    local unit = currentUnitConfig()
    if not unit or not unit.canvases then return end
    local sel = selectedCanvasIndex()
    local items = {}
    for i = 1, #unit.canvases do
        items[#items + 1] = {
            label = (i == sel and "* " or "") .. canvasName(i),
            value = i,
            current = (i == sel),
        }
    end
    showCanvasPopup("Canvases", items, function(index)
        unit.selectedCanvas = index
        pcall(function() api.SaveSettings() end)
        -- Поля справа должны показать значения выбранного канваса
        updateSettingsFields()
    end)
end

-- Добавить канвас: копия раскладки текущего, выбранный канвас переключается.
local function addCanvas()
    local unit = currentUnitConfig()
    if not unit or type(unit.canvases) ~= "table" then return end
    local src = unit.canvases[selectedCanvasIndex()]
    if not src then return end

    local newCfg = defaultSettings.cloneValue(src)
    newCfg.name = "Canvas " .. tostring(#unit.canvases + 1)
    -- Новый канвас ставим ПОД исходным (по его реальной высоте), чтобы панели
    -- не наложились друг на друга, и снимаем lock, чтобы его можно было тащить.
    local size = tonumber(src.iconSize) or 40
    local rows = math.floor(tonumber(src.gridRows) or 1)
    if rows < 1 then rows = 1 end
    local rowSpacing = tonumber(src.gridRowSpacing) or 5
    local height = rows * size + (rows - 1) * rowSpacing
    newCfg.posY = (tonumber(src.posY) or 30) + height + 20
    newCfg.lockPositioning = false
    table.insert(unit.canvases, newCfg)
    unit.selectedCanvas = #unit.canvases

    pcall(function() api.SaveSettings() end)
    -- Пересоздаём панели под новый набор канвасов
    if helpers and helpers.updateSettings then
        helpers.updateSettings()
    end
    api:Emit("ADDON_CBT_BUFFS_CHANGED")
    updateSettingsFields()
end

-- Переименовать выбранный канвас (маленький диалог с полем ввода).
local function openRenameCanvasDialog()
    local unit = currentUnitConfig()
    if not unit or not unit.canvases then return end
    local index = selectedCanvasIndex()
    local currentName = canvasName(index)

    if renameWindow then
        pcall(function() CbtWindow.Destroy(renameWindow) end)
        renameWindow = nil
    end
    local w = CbtWindow.Create("cbtCanvasRename", "Rename canvas", 360, 180, function()
        if renameWindow then renameWindow:Show(false) end
    end)
    if not w then return end
    renameWindow = w

    local lbl = helpers.createLabel("cbtCanvasRenameLabel", w, "Name:", 15, 44, 14)
    lbl:SetWidth(60)
    lbl:Show(true)

    local edit = helpers.createEdit("cbtCanvasRenameEdit", lbl, currentName, 60, -2)
    edit:SetWidth(250)
    edit:SetMaxTextLength(24)
    edit:Show(true)

    local function apply()
        local name = edit:GetText() or ""
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then name = currentName end
        local cfg = selectedCanvasCfg()
        if cfg then cfg.name = name end
        pcall(function() api.SaveSettings() end)
        if helpers and helpers.updateSettings then helpers.updateSettings() end
        updateSettingsFields()
        w:Show(false)
    end

    local saveBtn = helpers.createButton("cbtCanvasRenameSave", w, "Save", 15, 86)
    saveBtn:SetExtent(120, 26)
    saveBtn:Show(true)
    saveBtn:SetHandler("OnClick", apply)

    local cancelBtn = helpers.createButton("cbtCanvasRenameCancel", w, "Cancel", 143, 86)
    cancelBtn:SetExtent(100, 26)
    cancelBtn:Show(true)
    cancelBtn:SetHandler("OnClick", function() w:Show(false) end)

    -- Enter в поле = Save
    pcall(function()
        edit:SetHandler("OnEnterPressed", function(self)
            if self and self.ClearFocus then self:ClearFocus() end
            apply()
        end)
    end)

    w:Show(true)
end

-- Удалить выбранный канвас вместе со всеми его записями (с подтверждением).
local function deleteCanvas(index)
    local unit = currentUnitConfig()
    if not unit or type(unit.canvases) ~= "table" then return false end
    if #unit.canvases <= 1 then return false end
    if index < 1 or index > #unit.canvases then return false end

    table.remove(unit.canvases, index)

    -- Все записи этого канваса снимаются; индексы выше сдвигаются на -1.
    local keep = {}
    for _, id in ipairs(unit.trackedBuffs or {}) do
        local ci = canvasIndexOfId(unit, id)
        if ci ~= index then keep[#keep + 1] = id end
    end
    local newOf = {}
    for _, id in ipairs(keep) do
        local ci = canvasIndexOfId(unit, id)
        if ci > index then ci = ci - 1 end
        newOf[tostring(id)] = ci
    end
    unit.trackedBuffs = keep
    unit.canvasOf = newOf
    if type(unit.mirror) == "table" then
        for key in pairs(unit.mirror) do
            if newOf[key] == nil then unit.mirror[key] = nil end
        end
    end
    unit.enabled = (#keep > 0)

    local selected = index
    if selected > #unit.canvases then selected = #unit.canvases end
    if selected < 1 then selected = 1 end
    unit.selectedCanvas = selected

    pcall(function() api.SaveSettings() end)
    if helpers and helpers.updateSettings then helpers.updateSettings() end
    api:Emit("ADDON_CBT_BUFFS_CHANGED")
    updateTrackedBuffsList(true)
    updateSettingsFields()
    return true
end

local function openDeleteCanvasDialog()
    local unit = currentUnitConfig()
    if not unit or not unit.canvases then return end
    if #unit.canvases <= 1 then
        if settingsControls.customBuffErrorPanel and settingsControls.addCustomBuffError then
            settingsControls.addCustomBuffError:SetText("Error: the last canvas cannot be deleted")
            settingsControls.customBuffErrorPanel:Show(true)
        end
        return
    end

    local index = selectedCanvasIndex()
    local name = canvasName(index)
    local count = #trackedForCanvas(unit, unit.trackedBuffs, index)

    if deleteWindow then
        pcall(function() CbtWindow.Destroy(deleteWindow) end)
        deleteWindow = nil
    end
    local w = CbtWindow.Create("cbtCanvasDelete", "Delete canvas", 420, 200, function()
        if deleteWindow then deleteWindow:Show(false) end
    end)
    if not w then return end
    deleteWindow = w

    local line1 = helpers.createLabel("cbtCanvasDeleteLine1", w,
        'Delete canvas "' .. tostring(name) .. '" ?', 15, 46, 15)
    line1:SetWidth(385)
    pcall(function() line1.style:SetColor(0.95, 0.55, 0.45, 1) end)
    line1:Show(true)

    local line2 = helpers.createLabel("cbtCanvasDeleteLine2", w,
        tostring(count) .. ' tracked entries will be removed from this unit.', 15, 70, 13)
    line2:SetWidth(385)
    line2.style:SetColor(0.78, 0.80, 0.85, 1)
    line2:Show(true)

    local delBtn = helpers.createButton("cbtCanvasDeleteConfirm", w, "Delete", 15, 104)
    delBtn:SetExtent(120, 26)
    delBtn:Show(true)
    delBtn:SetHandler("OnClick", function()
        deleteCanvas(index)
        w:Show(false)
    end)

    local cancelBtn = helpers.createButton("cbtCanvasDeleteCancel", w, "Cancel", 143, 104)
    cancelBtn:SetExtent(100, 26)
    cancelBtn:Show(true)
    cancelBtn:SetHandler("OnClick", function() w:Show(false) end)

    w:Show(true)
end

-- Строка выбора канваса: [Canvas: Main] [Add] [Rename] [Delete]
local function buildCanvasSelector()
    -- 1.24.0: ряд канваса стоит на одном уровне с кнопками Unit (y=44), справа
    -- от них (x 340..724). Раньше он висел отдельной строкой на y=71 и съедал
    -- место, которое теперь занимает блок "Native frame display".
    local label = helpers.createLabel('canvasLabel', settingsWindow, 'Canvas:', 340, 47, 14)
    label:SetWidth(52)
    label:Show(true)

    canvasMenuButton = helpers.createButton('canvasMenuButton', settingsWindow,
        'Canvas: ' .. canvasName(selectedCanvasIndex()), 394, 44)
    canvasMenuButton:SetExtent(150, 26)
    pcall(function() canvasMenuButton.textLabel.style:SetFontSize(12) end)
    canvasMenuButton:Show(true)
    canvasMenuButton:SetHandler("OnClick", function() openCanvasListPopup() end)
    settingsControls.canvasMenuButton = canvasMenuButton

    local addButton = helpers.createButton('canvasAddButton', settingsWindow, 'Add', 548, 44)
    addButton:SetExtent(44, 26)
    pcall(function() addButton.textLabel.style:SetFontSize(12) end)
    addButton:Show(true)
    addButton:SetHandler("OnClick", addCanvas)
    settingsControls.canvasAddButton = addButton

    local renameButton = helpers.createButton('canvasRenameButton', settingsWindow, 'Rename', 596, 44)
    renameButton:SetExtent(66, 26)
    pcall(function() renameButton.textLabel.style:SetFontSize(12) end)
    renameButton:Show(true)
    renameButton:SetHandler("OnClick", openRenameCanvasDialog)
    settingsControls.canvasRenameButton = renameButton

    local deleteButton = helpers.createButton('canvasDeleteButton', settingsWindow, 'Delete', 666, 44)
    deleteButton:SetExtent(58, 26)
    pcall(function() deleteButton.textLabel.style:SetFontSize(12) end)
    deleteButton:Show(true)
    deleteButton:SetHandler("OnClick", openDeleteCanvasDialog)
    settingsControls.canvasDeleteButton = deleteButton

    return canvasMenuButton
end

local function buildUnitTypeSelector()
    -- UNIT TYPE SELECTOR - Add at the very top (c дополнительным отступом)
    local unitTypeLabel = helpers.createLabel('unitTypeLabel', settingsWindow,
                                           'Unit:', 20, 44, 16)
    unitTypeLabel:SetWidth(45)
    unitTypeLabel:Show(true)

    -- Mount settings button
    local mountButton = helpers.createButton('mountButton', settingsWindow, 'Mount', 70, 44)
    mountButton:SetWidth(80)
    mountButton:Show(true)

    -- Player settings button
    local playerButton = helpers.createButton('playerButton', settingsWindow, 'Player', 160, 44)
    playerButton:SetWidth(80)
    playerButton:Show(true)

    -- Target settings button
    local targetButton = helpers.createButton('targetButton', settingsWindow, 'Target', 250, 44)
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
end

local function buildTrackedBuffsSection()
    -- FIRST BLOCK - контейнер для размещения элементов (без заголовка)
    local trackedBuffsGroupLabel = helpers.createLabel('trackedBuffsGroupLabel', settingsWindow,
                                                    '', 34, 84, 20)  -- Удаляем текст "Buff tracker management"
    trackedBuffsGroupLabel:SetWidth(390) -- Increase header width
    trackedBuffsGroupLabel:Show(true)
    -- 1.24.0: якорь группы — точка, за которой едет вся левая колонка
    -- (заголовок, список, пагинация, форма ID/name). Его двигает
    -- syncFrameModeControls(), освобождая место блоку "Native frame display".
    settingsControls.trackedBuffsGroupLabel = trackedBuffsGroupLabel

    -- SECOND BLOCK - Tracked buffs list
    local trackedBuffsListHeader = helpers.createLabel('trackedBuffsListHeader', trackedBuffsGroupLabel,
                                                    'Tracked entries:', 0, 10, 16)
    trackedBuffsListHeader:Show(true)
    trackedBuffsListHeader:SetWidth(390)
    settingsControls.trackedBuffsListHeader = trackedBuffsListHeader

    -- Record (Debug): активные баффы и навыки из лога.
    -- 1.24.0: второй кнопкой в правом столбике — под Debug (1060, 70) и над
    -- блоком "Icon settings"; показывается только при Debug: ON. Родитель —
    -- само окно: кнопка не должна ездить вместе с группой Tracked entries.
    local recordButton = helpers.createButton('recordButton', settingsWindow, 'Record (Debug)', 0, 0)
    recordButton:SetExtent(110, 24)
    recordButton:RemoveAllAnchors()
    recordButton:AddAnchor("TOPLEFT", settingsWindow, 1060, 70)
    recordButton:Show(settings and settings.debugBuffId and true or false)
    recordButton:SetHandler("OnClick", function()
        recordWindow.setProviders(
            function(u, lim) return M.getLoggedSpells and M.getLoggedSpells(u or currentUnitType, lim) or {} end,
            function(id) return addBuffFromSearch(id, recordWindow.getUnit and recordWindow.getUnit() or currentUnitType) end,
            function(name) return addCustomFromSpell(name, recordWindow.getUnit and recordWindow.getUnit() or currentUnitType) end,
            function(u) if M.clearLoggedSpells then M.clearLoggedSpells(u or currentUnitType) end end,
            function(u) return M.getBuffLog and M.getBuffLog(u or currentUnitType) or {} end,
            function(u) if M.clearBuffLog then M.clearBuffLog(u or currentUnitType) end end)
        recordWindow.scanStarter = function() if M.startScan then M.startScan("") end end
        recordWindow.open()
    end)
    settingsControls.recordButton = recordButton




    -- Create container for buffs list and place it directly under header
    -- 1.24.0: высота 208 (было 220) — 9 строк по 22 px + верхний отступ 6 px;
    -- блок "Native frame display" над заголовком сдвигает список вниз, и форма
    -- ID/name с пагинацией должны остаться выше футера (Save на y=554).
    local buffsListContainer = api.Interface:CreateWidget('window', 'buffsListContainer', trackedBuffsListHeader)
    buffsListContainer:SetExtent(334, 208)
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
    containerBorder:SetColor(0.28, 0.30, 0.34, 1)
    containerBorder:AddAnchor("TOPLEFT", buffsListContainer, -1, -1)
    containerBorder:AddAnchor("BOTTOMRIGHT", buffsListContainer, 1, 1)

    -- Visible background for container
    local containerBg = buffsListContainer:CreateColorDrawable(0.10, 0.11, 0.13, 0.96, "background")
    containerBg:AddAnchor("TOPLEFT", buffsListContainer, 0, 0)
    containerBg:AddAnchor("BOTTOMRIGHT", buffsListContainer, 0, 0)

    -- Создаем внутренний контейнер для содержимого, который будет прокручиваться
    local buffsContentContainer = api.Interface:CreateWidget('window', 'buffsContentContainer', buffsListContainer)
    buffsContentContainer:SetWidth(314) -- Ширина с отступами
    -- Прикрепляем контент к левому верхнему углу с отступами
    buffsContentContainer:RemoveAllAnchors()
    buffsContentContainer:AddAnchor("TOPLEFT", buffsListContainer, 10, 5)
    buffsContentContainer:Show(true)

    settingsControls.buffsListContainer = buffsListContainer
    settingsControls.buffsContentContainer = buffsContentContainer

    -- Текущая позиция прокрутки
    -- Храним отображаемые в данный момент элементы списка
    local visibleBuffs = {}

    -- Функция обновления видимых элементов списка с пагинацией.
    -- Показываем только записи ВЫБРАННОГО канваса (canvasOf), порядок сохраняется.
    local function updateVisibleItems()
        -- Получаем ссылки на необходимые элементы
        local container = settingsControls.buffsListContainer
        if not container then return end

        local unit = currentUnitConfig()
        local canvasIdx = selectedCanvasIndex()
        local allTracked = BuffsToTrack.GetAllTrackedBuffIds(currentUnitType)
        local trackedBuffs = trackedForCanvas(unit, allTracked, canvasIdx)
        local hasSeveralCanvases = unit and unit.canvases and #unit.canvases > 1

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
        local itemHeight = 22

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
            local emptyLabel = helpers.createLabel('emptyBuffsList', container, "Nothing tracked yet", 0, 0, 16)
            emptyLabel:SetWidth(500)
            emptyLabel:AddAnchor("TOP", container, 0, 20)
            emptyLabel.style:SetAlign(ALIGN.CENTER)
            emptyLabel:Show(true)
            table.insert(visibleBuffs, emptyLabel)
            return
        end

        -- Создаем видимые элементы списка для текущей страницы
        local yOffset = 6

        for i = startIndex, endIndex do
            local buffId = trackedBuffs[i]
            if not buffId then break end

            -- Get buff name if possible
            local buffName = BuffList.GetBuffName(buffId) or ("Buff #" .. buffId)

            -- Create row with buff information
            local buffRow = api.Interface:CreateWidget('window', 'trackedBuff_' .. canvasIdx .. '_' .. i, container)
            buffRow:SetExtent(304, 20)
            buffRow:AddAnchor("TOPLEFT", container, 10, yOffset)
            buffRow:Show(true)

            -- Icon
            if CreateItemIconButton and F_SLOT and F_SLOT.SetIconBackGround then
                local iconBtn = CreateItemIconButton('trackedBuffIcon_' .. canvasIdx .. '_' .. i, buffRow)
                if iconBtn then
                    iconBtn:SetExtent(18, 18)
                    iconBtn:AddAnchor("LEFT", buffRow, 0, 0)
                    pcall(function() F_SLOT.SetIconBackGround(iconBtn, BuffList.GetBuffIcon(buffId)) end)
                    iconBtn:Show(true)
                end
            end

            -- Buff name only
            local buffNameLabel = helpers.createLabel('buffNameLabel_' .. canvasIdx .. '_' .. i, buffRow, buffName, 20, 0, 14)
            buffNameLabel:SetExtent(96, 20)
            pcall(function() buffNameLabel.style:SetEllipsis(true) end)
            buffNameLabel:Show(true)

            -- Up button
            local upButton = helpers.createButton('upBuffButton_' .. canvasIdx .. '_' .. i, buffRow, 'Up', 118, 0)
            upButton:SetExtent(24, 20)
            upButton:Show(true)
            upButton:SetHandler("OnClick", function()
                if M.moveTrackedWithinCanvas and M.moveTrackedWithinCanvas(buffId, "up", currentUnitType) then
                    deactivateActivePreset()
                    updateVisibleItems()
                    if helpers and helpers.updateSettings then
                        helpers.updateSettings()
                    end
                end
            end)

            -- Down button
            local downButton = helpers.createButton('downBuffButton_' .. canvasIdx .. '_' .. i, buffRow, 'Down', 144, 0)
            downButton:SetExtent(30, 20)
            downButton:Show(true)
            downButton:SetHandler("OnClick", function()
                if M.moveTrackedWithinCanvas and M.moveTrackedWithinCanvas(buffId, "down", currentUnitType) then
                    deactivateActivePreset()
                    updateVisibleItems()
                    if helpers and helpers.updateSettings then
                        helpers.updateSettings()
                    end
                end
            end)

            -- Mv: перенос записи на другой канвас этого же юнита
            if hasSeveralCanvases then
                local mvButton = helpers.createButton('moveBuffButton_' .. canvasIdx .. '_' .. i, buffRow, 'Mv', 176, 0)
                mvButton:SetExtent(26, 20)
                pcall(function() mvButton.textLabel.style:SetFontSize(11) end)
                mvButton:Show(true)
                mvButton:SetHandler("OnClick", function()
                    local unitNow = currentUnitConfig()
                    if not unitNow or not unitNow.canvases then return end
                    local currentCanvas = canvasIndexOfId(unitNow, buffId)
                    local items = {}
                    for ci = 1, #unitNow.canvases do
                        if ci ~= currentCanvas then
                            items[#items + 1] = { label = canvasName(ci), value = ci }
                        end
                    end
                    if #items == 0 then return end
                    showCanvasPopup("Move entry to canvas", items, function(index)
                        setCanvasOf(buffId, index, currentUnitType)
                        pcall(function() api.SaveSettings() end)
                        api:Emit("ADDON_CBT_BUFFS_CHANGED")
                        deactivateActivePreset()
                        updateVisibleItems()
                    end)
                end)
            end

            -- Mirror: ауру читаем с player, а её таймер показываем на текущем target.
            -- Только для баффов/дебаффов: у навыка и мана-навыка нет ауры на цели.
            if currentUnitType == "target" and kindOfId(buffId) == "buff" then
                local mirrorKey = tostring(buffId)
                local mirrorOn = settings.target and settings.target.mirror and settings.target.mirror[mirrorKey]
                -- Состояние видно по тексту: Mir ON / Mir OFF (+ цвет)
                local mirButton = helpers.createButton('mirrorBuffButton_' .. canvasIdx .. '_' .. i, buffRow,
                    mirrorOn and 'Mir ON' or 'Mir OFF', 204, 0)
                mirButton:SetExtent(46, 20)
                pcall(function() mirButton.textLabel.style:SetFontSize(11) end)
                mirButton:Show(true)
                if mirrorOn then
                    pcall(function() mirButton.textLabel.style:SetColor(0.55, 0.95, 0.55, 1) end)
                else
                    pcall(function() mirButton.textLabel.style:SetColor(0.75, 0.75, 0.75, 1) end)
                end
                mirButton:SetHandler("OnClick", function()
                    if not settings.target then settings.target = {} end
                    settings.target.mirror = settings.target.mirror or {}
                    if settings.target.mirror[mirrorKey] then
                        settings.target.mirror[mirrorKey] = nil
                    else
                        settings.target.mirror[mirrorKey] = true
                    end
                    if helpers and helpers.updateSettings then helpers.updateSettings() end
                    api:Emit("ADDON_CBT_BUFFS_CHANGED")
                    updateVisibleItems()
                end)
            end

            -- Remove button
            local removeButton = helpers.createButton('removeBuffButton_' .. canvasIdx .. '_' .. i, buffRow, 'Remove', 252, 0)
            removeButton:SetExtent(52, 20)
            pcall(function() removeButton.textLabel.style:SetFontSize(11) end)
            removeButton:Show(true)

            -- Remove button handler: снимает запись и её привязку к канвасу
            removeButton:SetHandler("OnClick", function()
                if BuffsToTrack.RemoveTrackedBuff(buffId, currentUnitType) then
                    local unitNow = currentUnitConfig()
                    if unitNow and type(unitNow.canvasOf) == "table" then
                        unitNow.canvasOf[tostring(buffId)] = nil
                    end
                    if unitNow and type(unitNow.mirror) == "table" then
                        unitNow.mirror[tostring(buffId)] = nil
                    end
                    api.SaveSettings()
                    deactivateActivePreset()
                    -- Update list after removal
                    updateTrackedBuffsList()
                    -- Update main interface
                    if helpers and helpers.updateSettings then
                        helpers.updateSettings()
                    end

                    -- Explicitly call buffs list update event
                    api:Emit("ADDON_CBT_BUFFS_CHANGED")
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
    buffPrevButton:AddAnchor("TOPLEFT", buffsListContainer, "BOTTOMLEFT", 10, 5)
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
    return buffsListContainer, trackedBuffsGroupLabel
end

local function buildNewBuffInput(buffsListContainer)
    -- THIRD BLOCK - Input field for new tracked buff (перемещаем его выше списка пользовательских баффов)
    local newBuffIdLabel = helpers.createLabel('newBuffIdLabel', settingsWindow, 'ID/name:', 15, 0, 15)
    newBuffIdLabel:SetWidth(100)
    newBuffIdLabel:Show(true)
    settingsControls.newBuffIdLabel = newBuffIdLabel

    -- Явно размещаем поле ввода нового баффа после списка обычных баффов
    newBuffIdLabel:RemoveAllAnchors()
    newBuffIdLabel:AddAnchor("TOPLEFT", buffsListContainer, "BOTTOMLEFT", 0, 40)

    local newBuffId = helpers.createEdit('newBuffId', newBuffIdLabel, "", 64, 0)
    if newBuffId then
        newBuffId:SetMaxTextLength(32)
        newBuffId:SetWidth(180)
        newBuffId:Show(true)
    end
    settingsControls.newBuffId = newBuffId

    -- Add buff button
    local addBuffButton = helpers.createButton('addBuffButton', newBuffIdLabel, 'Add', 250, -7)
    addBuffButton:SetWidth(80)
    addBuffButton:Show(true)
    settingsControls.addBuffButton = addBuffButton
    addBuffButton:SetHandler("OnClick", addTrackedBuff)

    -- Live search: подсказки только из Custom entries (1.24.0). Id/имя, которых
    -- нет в списке кастомных записей, не подсказываем и не ищем по дампу: поле
    -- принимает свободный id, а подсказка — это вход в уже заведённую запись.
    local acPanel = api.Interface:CreateWidget('window', 'buffAcPanel', newBuffIdLabel)
    pcall(function() acPanel:SetUILayer("dialog") end)
    acPanel:SetExtent(300, 22)
    acPanel:RemoveAllAnchors()
    acPanel:AddAnchor("TOPLEFT", newBuffId, "BOTTOMLEFT", 0, 3)
    acPanel:Show(false)
    local acBg = acPanel:CreateColorDrawable(0.05, 0.06, 0.07, 0.98, "background")
    acBg:AddAnchor("TOPLEFT", acPanel, 0, 0)
    acBg:AddAnchor("BOTTOMRIGHT", acPanel, 0, 0)
    local acRows = {}

    local function hideAc()
        acPanel:Show(false)
    end
    settingsControls.hideAc = hideAc

    local function ensureAcRow(i)
        if acRows[i] then return acRows[i] end
        local row = helpers.createButton('buffAcRow_' .. i, acPanel, '', 0, (i - 1) * 22)
        row:SetExtent(300, 22)
        row:Show(false)
        row:SetHandler("OnClick", function(self)
            if self.acValue ~= nil and settingsControls.newBuffId then
                settingsControls.newBuffId:SetText(tostring(self.acValue))
            end
            hideAc()
        end)
        acRows[i] = row
        return row
    end

    local function updateAc()
        if not settingsControls.newBuffId then return end
        local maxRows = settingsControls.acMaxRows or 4
        local q = settingsControls.newBuffId:GetText() or ""
        q = q:gsub("^%s+", ""):gsub("%s+$", "")
        if q == "" then hideAc(); return end
        local lq = string.lower(q)
        local matches = {}
        local seen = {}
        local s = helpers.getSettings()
        for _, cb in ipairs(s.customBuffs or {}) do
            local nm = tostring(cb.name or cb.spellName or "")
            local idv = tostring(cb.id or "")
            local hit = (nm ~= "" and string.lower(nm):find(lq, 1, true) ~= nil)
                or string.lower(idv):find(lq, 1, true) ~= nil
            if hit and idv ~= "" and not seen[idv] then
                seen[idv] = true
                matches[#matches + 1] = { value = cb.id, text = (nm ~= "" and nm or idv) .. "  [" .. idv .. "]" }
            end
            if #matches >= maxRows then break end
        end
        if #matches == 0 then hideAc(); return end
        for i = 1, maxRows do
            local item = matches[i]
            local row = acRows[i]
            if item then
                row = ensureAcRow(i)
                row.acValue = item.value
                row:SetText(item.text)
                row:Show(true)
            elseif row then
                row:Show(false)
            end
        end
        acPanel:SetExtent(300, math.min(#matches, maxRows) * 22)
        acPanel:Show(true)
    end

    newBuffId:SetHandler("OnTextChanged", updateAc)
    newBuffId:SetHandler("OnEnterPressed", function(self)
        if self and self.ClearFocus then self:ClearFocus() end
        hideAc()
    end)


    -- Create highlighted panel for error messages
    local errorPanel = api.Interface:CreateWidget('window', 'errorPanel', settingsWindow)
    errorPanel:SetExtent(320, 25)
    errorPanel:RemoveAllAnchors()
    errorPanel:AddAnchor("TOPLEFT", newBuffIdLabel, "BOTTOMLEFT", 0, -26)

    -- Frame for error panel for better highlighting
    local errorPanelBorder = errorPanel:CreateNinePartDrawable("ui/chat_option.dds", "artwork")
    errorPanelBorder:SetCoords(0, 0, 27, 16)
    errorPanelBorder:SetInset(0, 8, 0, 7)
    errorPanelBorder:AddAnchor("TOPLEFT", errorPanel, -1, -1)
    errorPanelBorder:AddAnchor("BOTTOMRIGHT", errorPanel, 1, 1)

    -- Background for error panel - make more visible
    local errorPanelBg = errorPanel:CreateColorDrawable(0.10, 0.11, 0.13, 0.96, "background")
    errorPanelBg:AddAnchor("TOPLEFT", errorPanel, 0, 0)
    errorPanelBg:AddAnchor("BOTTOMRIGHT", errorPanel, 0, 0)

    -- Error message in panel
    local addBuffError = helpers.createLabel('addBuffError', errorPanel, '', 5, 5, 14)
    addBuffError:SetExtent(560, 20) -- Increase error message width
    addBuffError.style:SetColor(0.95, 0.45, 0.45, 1) -- Red color for error message
    addBuffError:Show(true)
    settingsControls.addBuffError = addBuffError

    -- By default error panel is hidden
    errorPanel:Show(false)
    settingsControls.errorPanel = errorPanel
    return newBuffIdLabel
end

local function buildCustomBuffsSection(newBuffIdLabel, trackedBuffsGroupLabel)
    -- CUSTOM BUFFS LIST (перемещаем после поля ввода Buff ID)
    local customBuffsListHeader = helpers.createLabel('customBuffsListHeader', trackedBuffsGroupLabel,
                                                    'Custom entries:', 0, 30, 16)
    customBuffsListHeader:SetWidth(474)
    customBuffsListHeader:Show(true)
    settingsControls.customBuffsListHeader = customBuffsListHeader

    -- Явно размещаем заголовок для пользовательских баффов после панели ошибок ввода Buff ID
    customBuffsListHeader:RemoveAllAnchors()
    customBuffsListHeader:AddAnchor("TOPLEFT", settingsWindow, 376, 94)

    -- Контейнер для списка пользовательских баффов
    local customBuffsListContainer = api.Interface:CreateWidget('window', 'customBuffsListContainer', customBuffsListHeader)
    customBuffsListContainer:SetExtent(474, 220)
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
    customContainerBorder:SetColor(0.28, 0.30, 0.34, 1)
    customContainerBorder:AddAnchor("TOPLEFT", customBuffsListContainer, -1, -1)
    customContainerBorder:AddAnchor("BOTTOMRIGHT", customBuffsListContainer, 1, 1)

    -- Фон для контейнера
    local customContainerBg = customBuffsListContainer:CreateColorDrawable(0.10, 0.11, 0.13, 0.96, "background")
    customContainerBg:AddAnchor("TOPLEFT", customBuffsListContainer, 0, 0)
    customContainerBg:AddAnchor("BOTTOMRIGHT", customBuffsListContainer, 0, 0)

     -- Внутренний контейнер для прокручиваемого содержимого
     local customBuffsContentContainer = api.Interface:CreateWidget('window', 'customBuffsContentContainer', customBuffsListContainer)
     customBuffsContentContainer:SetWidth(454)
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

        local itemHeight = 22

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
            local emptyLabel = helpers.createLabel('emptyCustomBuffsList', container, "No custom entries yet", 0, 0, 16)
            emptyLabel:SetWidth(500)
            emptyLabel:AddAnchor("TOP", container, 0, 20)
            emptyLabel.style:SetAlign(ALIGN.CENTER)
            emptyLabel:Show(true)
            table.insert(customBuffsList, emptyLabel)
            return
        end

        -- Создаем видимые элементы для текущей страницы
        local yOffset = 6

        for i = startIndex, endIndex do
            local buffData = customBuffs[i]
            if not buffData or not buffData.id then break end

            local buffRow = api.Interface:CreateWidget('window', 'customBuff_' .. i, container)
            buffRow:SetExtent(444, 20)
            buffRow:AddAnchor("TOPLEFT", container, 5, yOffset)
            buffRow:Show(true)

            -- Icon
            if CreateItemIconButton and F_SLOT and F_SLOT.SetIconBackGround then
                local iconBtn = CreateItemIconButton('customBuffIcon_' .. i, buffRow)
                if iconBtn then
                    iconBtn:SetExtent(18, 18)
                    iconBtn:AddAnchor("LEFT", buffRow, 0, 0)
                    pcall(function() F_SLOT.SetIconBackGround(iconBtn, BuffList.GetBuffIcon(buffData.id)) end)
                    iconBtn:Show(true)
                end
            end

            -- ID и имя: не дублируем одинаковые строки
            local idText = tostring(buffData.id or "")
            local nameText = buffData.name or ""
            local spellText = buffData.spellName or ""
            local showId = (idText ~= "" and idText ~= nameText and idText ~= spellText)
            local displayName = nameText
            if displayName == "" then displayName = idText end
            if spellText ~= "" and spellText ~= nameText and spellText ~= idText then
                displayName = displayName .. " [" .. spellText .. "]"
            end

            if showId then
                local buffIdLabel = helpers.createLabel('customBuffIdLabel_' .. i, buffRow, idText, 22, 0, 12)
                buffIdLabel:SetExtent(56, 20)
                pcall(function() buffIdLabel.style:SetFontSize(13) end)
                buffIdLabel:Show(true)
            end

            local buffNameLabel = helpers.createLabel('customBuffNameLabel_' .. i, buffRow, displayName, 90, 0, 14)
            buffNameLabel:SetExtent(132, 20)
            buffNameLabel:Show(true)

            -- Cooldown
            local buffCooldownLabel = helpers.createLabel('customBuffCooldownLabel_' .. i, buffRow, tostring(buffData.cooldown), 226, 0, 13)
            buffCooldownLabel:SetExtent(34, 20)
            buffCooldownLabel:Show(true)

            -- timeOfAction
            local buffTimeOfActionLabel = helpers.createLabel('customBuffTimeOfAction_' .. i, buffRow, tostring(buffData.timeOfAction), 264, 0, 13)
            buffTimeOfActionLabel:SetExtent(34, 20)
            buffTimeOfActionLabel:Show(true)

            -- Remove button
            -- Add-to-tracking button: сразу добавляет этот бафф в отслеживание
            -- для выбранного типа юнита (Mount/Player/Target)
            local addToTrackButton = helpers.createButton('addCustomToTrackButton_' .. i, buffRow, 'Add', 302, 0)
            addToTrackButton:SetExtent(30, 20)
            pcall(function() addToTrackButton.textLabel.style:SetFontSize(12) end)
            addToTrackButton:Show(true)
            addToTrackButton:SetHandler("OnClick", function()
                -- ВАЖНО: передаём buffData.id КАК ЕСТЬ (без tonumber). ID кастом-баффов
                -- и отслеживаемых баффов хранятся строкой (из поля ввода), и аддон
                -- сопоставляет их по совпадению типа. Приведение к числу ломает поиск
                -- данных баффа -> "unknown buff".
                -- Запись добавляется на выбранный канвас текущего юнита.
                if not isTrackedOnUnit(currentUnitConfig(), buffData.id) then
                    setCanvasOf(buffData.id, selectedCanvasIndex(currentUnitType), currentUnitType)
                end
                if BuffsToTrack.AddTrackedBuff(buffData.id, currentUnitType) then
                    updateTrackedBuffsList()
                    api:Emit("ADDON_CBT_BUFFS_CHANGED")
                end
            end)

            local removeButton = helpers.createButton('removeCustomBuffButton_' .. i, buffRow, 'Remove', 340, 0)
            removeButton:SetExtent(44, 20)
            pcall(function() removeButton.textLabel.style:SetFontSize(12) end)

            -- Edit: правит CD/D этой кастомной записи; обновляет и Buff list
            local editCustomButton = helpers.createButton('editCustomBuffButton_' .. i, buffRow, 'Edit', 390, 0)
            editCustomButton:SetExtent(40, 20)
            pcall(function() editCustomButton.textLabel.style:SetFontSize(12) end)
            editCustomButton:Show(true)
            editCustomButton:SetHandler("OnClick", function()
                openCddDialog(buffData.id)
            end)
            removeButton:Show(true)

            -- Remove button handler: удаление кастомной записи убирает её и из
            -- отслеживания во всех трёх панелях (без записи она теряет CD/D).
            removeButton:SetHandler("OnClick", function()
                local removedId = buffData.id
                table.remove(settings.customBuffs, i)
                for _, ut in ipairs({ "playerpet", "player", "target" }) do
                    local unit = settings[ut]
                    local list = unit and unit.trackedBuffs
                    if type(list) == "table" then
                        for k = #list, 1, -1 do
                            if tostring(list[k]) == tostring(removedId) then
                                table.remove(list, k)
                            end
                        end
                    end
                    -- запись без метаданных бессмысленна: снимаем и привязку к канвасу
                    if unit and type(unit.canvasOf) == "table" then
                        unit.canvasOf[tostring(removedId)] = nil
                    end
                    if unit and type(unit.mirror) == "table" then
                        unit.mirror[tostring(removedId)] = nil
                    end
                end
                deactivateActivePreset()
                updateCustomBuffsList()
                updateTrackedBuffsList()
                if helpers and helpers.updateSettings then
                    helpers.updateSettings()
                end
                api:Emit("ADDON_CBT_BUFFS_CHANGED")
                api.Log:Info("[CBT] custom entry removed: " .. tostring(removedId))
            end)

            table.insert(customBuffsList, buffRow)
            yOffset = yOffset + itemHeight
        end
    end

    -- Кнопки пагинации для custom buffs list
    local customPrevButton = helpers.createButton('customPrevButton', customBuffsListContainer, '<', 0, 0)
    customPrevButton:SetExtent(30, 25)
    customPrevButton:RemoveAllAnchors()
    customPrevButton:AddAnchor("TOPLEFT", customBuffsListContainer, "BOTTOMLEFT", 10, 5)
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
    return customBuffsListContainer
end

local function buildCustomBuffInputs(customBuffsListContainer)
    -- CUSTOM BUFF INPUTS
    local customBuffInputsLabel = helpers.createLabel('customBuffInputsLabel', settingsWindow,
                                                    'Add custom entry:', 0, 0, 16)
    customBuffInputsLabel:SetWidth(570)
    customBuffInputsLabel:Show(true)
    settingsControls.customBuffInputsLabel = customBuffInputsLabel

    -- Явно размещаем заголовок блока добавления пользовательских баффов
    customBuffInputsLabel:RemoveAllAnchors()
    customBuffInputsLabel:AddAnchor("TOPLEFT", customBuffsListContainer, "BOTTOMLEFT", 0, 40)

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
        if settingsControls.recordButton then
            settingsControls.recordButton:Show(settings.debugBuffId and true or false)
        end

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
    if debugBuffButton then
        -- 1.24.0: кнопки Debug/Record — столбиком у правого края окна, над
        -- блоком "Icon settings" (он начинается с y=100): Debug 44..68,
        -- Record 70..94, обе по x 1060..1170 (как Save справа).
        debugBuffButton:RemoveAllAnchors()
        debugBuffButton:AddAnchor("TOPLEFT", settingsWindow, 1060, 44)
        debugBuffButton:SetExtent(110, 24)
    end

    -- Import/Export button
    local importExportButton = helpers.createButton('importExportButton', customBuffInputsLabel, 'Import/Export', 360, -5)
    if importExportButton then
        importExportButton:SetExtent(120, 25)
        importExportButton:Show(true)

        importExportButton:SetHandler("OnClick", function()
            importExport.openImportExportWindow(function()
                -- После успешного импорта обновляем списки баффов и поля канваса
                updateSettingsFields()
                updateTrackedBuffsList(true)
                updateCustomBuffsList(true)
                api.Log:Info("[CBT] Buff lists refreshed after import")
            end)
        end)
    end
    settingsControls.importExportButton = importExportButton
    if importExportButton then
        importExportButton:RemoveAllAnchors()
        importExportButton:AddAnchor("BOTTOMLEFT", settingsWindow, 20, -18)
        importExportButton:SetExtent(120, 25)
    end

    -- Presets button (рядом с Import/Export — управление конфигурацией)
    local presetsButton = helpers.createButton('presetsButton', customBuffInputsLabel, 'Presets', 485, -5)
    if presetsButton then
        presetsButton:SetExtent(90, 25)
        presetsButton:Show(true)
        presetsButton:SetHandler("OnClick", function()
            if presetWindowModule and presetWindowModule.openPresetWindow then
                presetWindowModule.openPresetWindow()
            end
        end)
    end
    settingsControls.presetsButton = presetsButton
    if presetsButton then
        presetsButton:RemoveAllAnchors()
        presetsButton:AddAnchor("BOTTOMLEFT", settingsWindow, 150, -18)
        presetsButton:SetExtent(100, 25)
    end
    setPresetsButtonText() -- отразить активный пресет, если есть

    ---------------------------------------------------------------
    -- Тип записи: Buff/Debuff | Skill | Mana skill (1.22.0)
    -- Выбранный тип подсвечен золотом, остальные приглушены; от него зависит
    -- набор полей ниже.
    ---------------------------------------------------------------
    local typeLabel = helpers.createLabel('customTypeLabel', customBuffInputsLabel, 'Type:', 150, 4, 13)
    typeLabel:SetWidth(36)
    pcall(function() typeLabel.style:SetColor(0.72, 0.74, 0.80, 1) end)
    typeLabel:Show(true)
    settingsControls.customTypeLabel = typeLabel

    local typeButtons = {}
    local applyEntryType
    local typeSpecs = {
        { kind = 'buff',  text = 'Buff/Debuff', x = 190, w = 100 },
        { kind = 'skill', text = 'Skill',       x = 294, w = 66  },
        { kind = 'mana',  text = 'Mana skill',  x = 364, w = 92  },
    }
    for _, spec in ipairs(typeSpecs) do
        local btn = helpers.createButton('customType_' .. spec.kind, customBuffInputsLabel, spec.text,
            spec.x, 0)
        btn:SetExtent(spec.w, 24)
        btn:Show(true)
        btn:SetHandler("OnClick", function()
            if applyEntryType then applyEntryType(spec.kind) end
        end)
        typeButtons[spec.kind] = btn
    end

    -- Поле = подпись (полное имя поля) + edit справа от неё; edit движется вместе
    -- с подписью, поэтому смена типа переставляет поля одним AddAnchor.
    local function makeField(id, text, labelW, editW)
        local lbl = helpers.createLabel(id .. 'Label', customBuffInputsLabel, text, 0, 25, 13)
        lbl:SetWidth(labelW)
        lbl:Show(true)
        local edit = helpers.createEdit(id, lbl, "", labelW + 6, 0)
        edit:SetWidth(editW)
        edit:Show(true)
        return lbl, edit
    end

    local idLabel, idEdit = makeField('newCustomBuffId', 'ID:', 20, 50)
    local nameLabel, nameEdit = makeField('newCustomBuffName', 'Name:', 36, 110)
    local cdLabel, cdEdit = makeField('newCustomBuffCooldown', 'Cooldown:', 58, 44)
    local toaLabel, toaEdit = makeField('newCustomBuffTimeOfAction', 'Duration:', 60, 48)
    local spellLabel, spellEdit = makeField('newCustomBuffSpell', 'Spell:', 34, 240)
    local manaLabel, manaEdit = makeField('newCustomBuffMana', 'Mana:', 30, 60)
    local mountLabel, mountEdit = makeField('newCustomBuffMount', 'Mount:', 38, 200)
    idEdit:SetMaxTextLength(12)
    cdEdit:SetMaxTextLength(6)
    toaEdit:SetMaxTextLength(6)
    manaEdit:SetMaxTextLength(7)
    settingsControls.newCustomBuffId = idEdit
    settingsControls.newCustomBuffName = nameEdit
    settingsControls.newCustomBuffCooldown = cdEdit
    settingsControls.newCustomBuffTimeOfAction = toaEdit
    settingsControls.newCustomBuffSpell = spellEdit
    settingsControls.newCustomBuffMana = manaEdit
    settingsControls.newCustomBuffMount = mountEdit

    -- Превью иконки: клик открывает поиск иконок, выбор заполняет путь и
    -- закрывает окно. Отдельной кнопки Icon search больше нет.
    local iconPreview = CreateItemIconButton('cbtIconPreview', customBuffInputsLabel)
    if iconPreview then
        iconPreview:SetExtent(28, 28)
        iconPreview:AddAnchor("TOPLEFT", customBuffInputsLabel, 440, 51)
        pcall(function() F_SLOT.SetIconBackGround(iconPreview, DEFAULT_ENTRY_ICON) end)
        if iconPreview.RegisterForClicks then
            pcall(function() iconPreview:RegisterForClicks("LeftButton") end)
        end
        iconPreview:Show(true)
        settingsControls.customBuffIconPreview = iconPreview
    end

    local function refreshNewIconPreview()
        if not iconPreview then return end
        local p = newEntryIcon
        if not p or p == "" then
            p = BuffList.GetBuffIcon(idEdit:GetText() or "")
        end
        if not p or p == "" then p = DEFAULT_ENTRY_ICON end
        pcall(function() F_SLOT.SetIconBackGround(iconPreview, p) end)
    end

    if iconPreview then
        iconPreview:SetHandler("OnClick", function()
            local query = ""
            if spellEdit:IsVisible() then query = trimText(spellEdit:GetText()) end
            if query == "" then query = trimText(nameEdit:GetText()) end
            if query == "" then query = trimText(idEdit:GetText()) end
            openIconSearchFor(query, function(path)
                newEntryIcon = path or ""
                refreshNewIconPreview()
            end)
        end)
    end

    local function placeLabel(lbl, x, y)
        if not lbl then return end
        lbl:RemoveAllAnchors()
        lbl:AddAnchor("TOPLEFT", customBuffInputsLabel, x, y)
    end

    local function showField(lbl, edit, shown)
        if lbl then lbl:Show(shown) end
        if edit then edit:Show(shown) end
    end

    -- Раскладка формы под выбранный тип: buff -> ID/Name/Cooldown/Duration,
    -- skill -> Name/Cooldown + Spell, mana -> Name/Cooldown + Mana/Mount.
    applyEntryType = function(kind)
        newEntryKind = kind

        for k, btn in pairs(typeButtons) do
            if btn.textLabel then
                if k == kind then
                    pcall(function() btn.textLabel.style:SetColor(0.95, 0.80, 0.25, 1) end)
                else
                    pcall(function() btn.textLabel.style:SetColor(0.60, 0.62, 0.68, 1) end)
                end
            end
        end

        local isBuff = (kind == 'buff')
        local isSkill = (kind == 'skill')
        local isMana = (kind == 'mana')

        showField(idLabel, idEdit, isBuff)
        showField(toaLabel, toaEdit, isBuff)
        showField(spellLabel, spellEdit, isSkill)
        showField(manaLabel, manaEdit, isMana)
        showField(mountLabel, mountEdit, isMana)
        showField(nameLabel, nameEdit, true)
        showField(cdLabel, cdEdit, true)

        if isBuff then
            nameEdit:SetWidth(110)
            placeLabel(idLabel, 0, 25)
            placeLabel(nameLabel, 84, 25)
            placeLabel(cdLabel, 240, 25)
            placeLabel(toaLabel, 350, 25)
        else
            nameEdit:SetWidth(200)
            placeLabel(nameLabel, 0, 25)
            placeLabel(cdLabel, 254, 25)
            if isSkill then
                placeLabel(spellLabel, 0, 55)
            elseif isMana then
                placeLabel(manaLabel, 0, 55)
                placeLabel(mountLabel, 98, 55)
            end
        end

        if settingsControls.customBuffErrorPanel then
            settingsControls.customBuffErrorPanel:Show(false)
        end
        refreshNewIconPreview()
    end

    -- Кнопка добавления записи
    local addCustomBuffButton = helpers.createButton('addCustomBuffButton', customBuffInputsLabel, 'Add entry', 0, 85)
    addCustomBuffButton:SetWidth(130)
    addCustomBuffButton:Show(true)
    settingsControls.addCustomBuffButton = addCustomBuffButton
    addCustomBuffButton:SetHandler("OnClick", addCustomBuff)

    -- Панель ошибок формы Add custom entry (между формой и футером окна)
    local customBuffErrorPanel = api.Interface:CreateWidget('window', 'customBuffErrorPanel', settingsWindow)
    customBuffErrorPanel:SetExtent(460, 25)
    customBuffErrorPanel:RemoveAllAnchors()
    customBuffErrorPanel:AddAnchor("TOPLEFT", customBuffInputsLabel, "BOTTOMLEFT", 0, 114)
    customBuffErrorPanel:Show(false)
    settingsControls.customBuffErrorPanel = customBuffErrorPanel

    -- Рамка для панели ошибок
    local customErrorPanelBorder = customBuffErrorPanel:CreateNinePartDrawable("ui/chat_option.dds", "artwork")
    customErrorPanelBorder:SetCoords(0, 0, 27, 16)
    customErrorPanelBorder:SetInset(0, 8, 0, 7)
    customErrorPanelBorder:AddAnchor("TOPLEFT", customBuffErrorPanel, -1, -1)
    customErrorPanelBorder:AddAnchor("BOTTOMRIGHT", customBuffErrorPanel, 1, 1)

    -- Фон для панели ошибок
    local customErrorPanelBg = customBuffErrorPanel:CreateColorDrawable(0.10, 0.11, 0.13, 0.96, "background")
    customErrorPanelBg:AddAnchor("TOPLEFT", customBuffErrorPanel, 0, 0)
    customErrorPanelBg:AddAnchor("BOTTOMRIGHT", customBuffErrorPanel, 0, 0)

    -- Текст ошибки
    local addCustomBuffError = helpers.createLabel('addCustomBuffError', customBuffErrorPanel, '', 5, 5, 13)
    addCustomBuffError:SetExtent(450, 20)
    addCustomBuffError.style:SetColor(0.95, 0.45, 0.45, 1)
    addCustomBuffError:Show(true)
    settingsControls.addCustomBuffError = addCustomBuffError

    settingsControls.applyEntryType = applyEntryType
    applyEntryType('buff')

    return customBuffErrorPanel
end

local function buildIconSection(customBuffErrorPanel)
    -- FOURTH BLOCK - Icon settings
    local iconGroupLabel = helpers.createLabel('iconGroupLabel', settingsWindow,
                                             'Icon settings', 15, 0, 20)
    iconGroupLabel:SetWidth(320)
    iconGroupLabel:Show(true)
    settingsControls.iconGroupLabel = iconGroupLabel

    -- Явно устанавливаем якорь для группы настроек иконок.
    -- 1.24.0: правый столбик начинается с y=100 — над ним стоят Debug (44..68)
    -- и Record (70..94), поэтому заголовок не пересекается с кнопками.
    iconGroupLabel:RemoveAllAnchors()
    iconGroupLabel:AddAnchor("TOPLEFT", settingsWindow, 860, 100)

    -- Icon size
    local iconSizeLabel = helpers.createLabel('iconSizeLabel', iconGroupLabel,
                                            'Icon size:', 0, 25, 15)
    iconSizeLabel:SetWidth(150) -- Set label width
    iconSizeLabel:Show(true)

    local iconCfg = selectedCanvasCfg() or {}
    local iconSize = helpers.createEdit('iconSize', iconSizeLabel,
                                      tostring(iconCfg.iconSize or 40), 200, 0)
    if iconSize then
        iconSize:SetMaxTextLength(4)
        iconSize:SetWidth(50) -- Increase input field width
        iconSize:Show(true)
    end
    settingsControls.iconSize = iconSize
    bindApplyOnEnter(iconSize)

    -- Icon spacing
    local iconSpacingLabel = helpers.createLabel('iconSpacingLabel', iconSizeLabel,
                                               'Icon spacing:', 0, 25, 15)
    iconSpacingLabel:SetWidth(150) -- Set label width
    iconSpacingLabel:Show(true)

    local iconSpacing = helpers.createEdit('iconSpacing', iconSpacingLabel,
                                         tostring(iconCfg.iconSpacing or 5), 200, 0)
    if iconSpacing then
        iconSpacing:SetMaxTextLength(4)
        iconSpacing:SetWidth(50) -- Increase input field width
        iconSpacing:Show(true)
    end
    settingsControls.iconSpacing = iconSpacing
    bindApplyOnEnter(iconSpacing)

    -- =============================================================
    -- Этап 4: настройки сетки иконок. Самодостаточный блок-второй столбец,
    -- якорится к iconGroupLabel и потому не вмешивается в цепочку остальных
    -- контролов (Columns / Rows / Max icons).
    -- =============================================================
    local gridUnitSettings = iconCfg
    local gridDefCols = gridUnitSettings.gridColumns or 10
    local gridDefRows = gridUnitSettings.gridRows or 1
    local gridDefMax = gridUnitSettings.maxIcons or (gridDefCols * gridDefRows)
    local gridDefRowSpacing = gridUnitSettings.gridRowSpacing or gridUnitSettings.iconSpacing or 5

    local gridGroupLabel = helpers.createLabel('gridGroupLabel', iconGroupLabel,
                                             'Grid (cols x rows):', 0, 110, 15)
    gridGroupLabel:SetWidth(320)
    gridGroupLabel:Show(true)
    settingsControls.gridGroupLabel = gridGroupLabel

    -- Columns
    local gridColumnsLabel = helpers.createLabel('gridColumnsLabel', gridGroupLabel,
                                               'Columns:', 0, 25, 15)
    gridColumnsLabel:SetWidth(95)
    gridColumnsLabel:Show(true)
    local gridColumns = helpers.createEdit('gridColumns', gridColumnsLabel,
                                         tostring(gridDefCols), 100, 0)
    if gridColumns then
        gridColumns:SetMaxTextLength(2)
        gridColumns:SetWidth(45)
        gridColumns:Show(true)
    end
    settingsControls.gridColumns = gridColumns
    bindApplyOnEnter(gridColumns)

    -- Rows
    local gridRowsLabel = helpers.createLabel('gridRowsLabel', gridColumnsLabel,
                                            'Rows:', 0, 25, 15)
    gridRowsLabel:SetWidth(95)
    gridRowsLabel:Show(true)
    local gridRows = helpers.createEdit('gridRows', gridRowsLabel,
                                      tostring(gridDefRows), 100, 0)
    if gridRows then
        gridRows:SetMaxTextLength(2)
        gridRows:SetWidth(45)
        gridRows:Show(true)
    end
    settingsControls.gridRows = gridRows
    bindApplyOnEnter(gridRows)

    -- Max icons (<= Columns * Rows)
    local maxIconsLabel = helpers.createLabel('maxIconsLabel', gridRowsLabel,
                                            'Max icons:', 0, 25, 15)
    maxIconsLabel:SetWidth(95)
    maxIconsLabel:Show(true)
    local maxIcons = helpers.createEdit('maxIcons', maxIconsLabel,
                                      tostring(gridDefMax), 100, 0)
    if maxIcons then
        maxIcons:SetMaxTextLength(3)
        maxIcons:SetWidth(45)
        maxIcons:Show(true)
    end
    settingsControls.maxIcons = maxIcons
    bindApplyOnEnter(maxIcons)

    -- Row spacing — вертикальный отступ между строками сетки
    local rowSpacingLabel = helpers.createLabel('rowSpacingLabel', maxIconsLabel,
                                            'Row spacing:', 0, 25, 15)
    rowSpacingLabel:SetWidth(95)
    rowSpacingLabel:Show(true)
    local gridRowSpacing = helpers.createEdit('gridRowSpacing', rowSpacingLabel,
                                      tostring(gridDefRowSpacing), 100, 0)
    if gridRowSpacing then
        gridRowSpacing:SetMaxTextLength(3)
        gridRowSpacing:SetWidth(45)
        gridRowSpacing:Show(true)
    end
    settingsControls.gridRowSpacing = gridRowSpacing
    bindApplyOnEnter(gridRowSpacing)
    -- нижний элемент сетки — к нему якорим кнопку "Thank you", чтобы не наезжала
    settingsControls.gridBottomLabel = rowSpacingLabel

    -- Show label button (ON/OFF toggle) — пишет в выбранный канвас
    local showLabelButtonText = (selectedCanvasCfg() or {}).showLabel and "Show label: ON" or "Show label: OFF"
    local showLabelButton = helpers.createButton('showLabelButton', iconSpacingLabel, showLabelButtonText, 0, 25)
    showLabelButton:SetExtent(120, 25)
    showLabelButton:Show(true)

    -- Toggle handler for show label button
    showLabelButton:SetHandler("OnClick", function()
        local cfg = selectedCanvasCfg()
        if not cfg then return end
        cfg.showLabel = not cfg.showLabel

        -- Настройка изменена вручную — деактивируем активный пресет
        deactivateActivePreset()

        -- Update button text
        showLabelButton:SetText(cfg.showLabel and "Show label: ON" or "Show label: OFF")

        api.SaveSettings()

        -- Update display through helpers.updateSettings()
        if helpers and helpers.updateSettings then
            helpers.updateSettings()
        end
    end)
    settingsControls.showLabel = showLabelButton
    return showLabelButton, iconSpacingLabel
end

local function buildPositionSection(showLabelButton, iconSpacingLabel)
    -- Icon position settings
    local positionLabel = helpers.createLabel('positionLabel', iconSpacingLabel,
                                            'Icon position', 0, 35, 18)
    positionLabel:SetWidth(320)
    positionLabel:Show(true)
    settingsControls.positionLabel = positionLabel

    -- Якорим группу позиционирования ПОД кнопкой "Show label", иначе заголовок
    -- "Icon position" наезжает на эту кнопку снизу.
    positionLabel:RemoveAllAnchors()
    positionLabel:AddAnchor("TOPLEFT", showLabelButton, "BOTTOMLEFT", 0, 15)

    -- X coordinate
    local posXLabel = helpers.createLabel('posXLabel', positionLabel,
                                        'Position X:', 0, 25, 15)
    posXLabel:SetWidth(150) -- Set label width
    posXLabel:Show(true)

    local posCfg = selectedCanvasCfg() or {}
    local posX = helpers.createEdit('posX', posXLabel,
                                  tostring(posCfg.posX or 0), 200, 0)
    if posX then
        posX:SetMaxTextLength(6)
        posX:SetWidth(50) -- Increase input field width
        posX:Show(true)
    end
    settingsControls.posX = posX
    bindApplyOnEnter(posX)

    -- Y coordinate
    local posYLabel = helpers.createLabel('posYLabel', posXLabel,
                                        'Position Y:', 0, 25, 15)
    posYLabel:SetWidth(150) -- Set label width
    posYLabel:Show(true)

    local posY = helpers.createEdit('posY', posYLabel,
                                  tostring(posCfg.posY or 0), 200, 0)
    if posY then
        posY:SetMaxTextLength(6)
        posY:SetWidth(50) -- Increase input field width
        posY:Show(true)
    end
    settingsControls.posY = posY
    bindApplyOnEnter(posY)

    -- Lock positioning button (ON/OFF toggle)
    local lockIsOn = posCfg.lockPositioning or false
    local lockButtonText = lockIsOn and "Lock: ON" or "Lock: OFF"
    local lockButton = helpers.createButton('lockButton', posYLabel, lockButtonText, 0, 25)
    if lockButton then
        lockButton:SetExtent(100, 25)
        lockButton:Show(true)

        -- Toggle handler for lock button
        lockButton:SetHandler("OnClick", function()
            -- Toggle state ВЫБРАННОГО канваса
            local cfg = selectedCanvasCfg()
            if not cfg then return end
            cfg.lockPositioning = not cfg.lockPositioning

            -- Настройка изменена вручную — деактивируем активный пресет
            deactivateActivePreset()

            -- Update button text
            lockButton:SetText(cfg.lockPositioning and "Lock: ON" or "Lock: OFF")

            api.SaveSettings()

            -- Notify main to update dragging state
            api:Emit("ADDON_CBT_BUFFS_CHANGED")
        end)
    end
    settingsControls.lockButton = lockButton
    return lockButton
end

local function buildTimerSection(lockButton)
    -- Timer settings group
    local timerGroupLabel = helpers.createLabel('timerGroupLabel', lockButton,
                                             'Timer settings', 0, 35, 18)
    timerGroupLabel:SetWidth(320)
    timerGroupLabel:Show(true)

    -- Явно устанавливаем якорь для группы настроек таймера
    timerGroupLabel:RemoveAllAnchors()
    timerGroupLabel:AddAnchor("TOPLEFT", lockButton, "BOTTOMLEFT", 0, 10)

    -- Timer font size
    local timerFontSizeLabel = helpers.createLabel('timerFontSizeLabel', timerGroupLabel,
                                                'Font size:', 0, 25, 15)
    timerFontSizeLabel:SetWidth(150) -- Set label width
    timerFontSizeLabel:Show(true)

    local timerCfg = selectedCanvasCfg() or {}
    local timerFontSize = helpers.createEdit('timerFontSize', timerFontSizeLabel,
                                          tostring(timerCfg.timerFontSize or 16), 200, 0)
    if timerFontSize then
        timerFontSize:SetMaxTextLength(4)
        timerFontSize:SetWidth(50) -- Increase input field width
        timerFontSize:Show(true)
    end
    settingsControls.timerFontSize = timerFontSize
    bindApplyOnEnter(timerFontSize)

    -- Timer text color
    local timerTextColorLabel = helpers.createLabel('timerTextColorLabel', timerFontSizeLabel,
                                                 'Text color:', 0, 25, 15)
    timerTextColorLabel:SetWidth(150) -- Set label width
    timerTextColorLabel:Show(true)

    -- Цвета берём из выбранного канваса
    local textColor = timerCfg.timerTextColor or {r = 1, g = 1, b = 1, a = 1}

    local timerTextColor = helpers.createColorPickButton('timerTextColor', timerTextColorLabel,
                                                      textColor, 200, 0)

    -- Configure color picker handler to save selected color
    if timerTextColor and timerTextColor.colorBG then
        timerTextColor:Show(true)
        function timerTextColor:SelectedProcedure(r, g, b, a)
            self.colorBG:SetColor(r, g, b, a)
            -- Сохраняем цвет в выбранный канвас
            local cfg = selectedCanvasCfg()
            if cfg then
                cfg.timerTextColor = {r = r, g = g, b = b, a = a or 1}
            end
            -- Цвет изменён вручную — деактивируем активный пресет
            deactivateActivePreset()
        end
    end
    settingsControls.timerTextColor = timerTextColor

    -- Label color — цвет надписи названия баффа в канвасе (аналог "Text color")
    local labelColorLabel = helpers.createLabel('labelColorLabel', timerTextColorLabel,
                                                 'Label color:', 0, 25, 15)
    labelColorLabel:SetWidth(150)
    labelColorLabel:Show(true)

    local labelColorValue = timerCfg.labelTextColor or {r = 1, g = 1, b = 1, a = 1}
    local labelTextColor = helpers.createColorPickButton('labelTextColor', labelColorLabel,
                                                      labelColorValue, 200, 0)
    if labelTextColor and labelTextColor.colorBG then
        labelTextColor:Show(true)
        function labelTextColor:SelectedProcedure(r, g, b, a)
            self.colorBG:SetColor(r, g, b, a)
            local cfg = selectedCanvasCfg()
            if cfg then
                cfg.labelTextColor = {r = r, g = g, b = b, a = a or 1}
            end
            deactivateActivePreset()
        end
    end
    settingsControls.labelTextColor = labelTextColor

    -- Save button — в самом низу окна, под "Label color". Применяет введённые
    -- значения (icon size/spacing, position, font size, сетка) сразу, не
    -- закрывая окно настроек.
    local saveButton = helpers.createButton('cbtSaveButton', settingsWindow, 'Save', 0, 0)
    saveButton:RemoveAllAnchors()
    saveButton:AddAnchor("BOTTOMRIGHT", settingsWindow, -20, -18)
    saveButton:SetExtent(120, 28)
    saveButton:Show(true)
    settingsControls.saveButton = saveButton
    saveButton:SetHandler("OnClick", function()
        settings = helpers.getSettings()
        applySaveKeepPages()
        if saveButton.SetText then
            saveButton:SetText("Saved")
            if api and api.DoIn then
                api:DoIn(900, function()
                    if saveButton and saveButton.SetText then saveButton:SetText("Save") end
                end)
            end
        end
    end)
end

-- =====================================================================
-- "Native frame display" — режимы, привязанные к юниту.
--   Player: ничего — Player-режим "Under MP bar" убран в 1.25.0.
--   Target: Overlay around target, Hide target canvas, Avoid TrackThatPlease
--           (+ Gap) и поля оверлея выбранного канваса.
--   Mount:  ничего — блок скрыт.
-- 1.26.0: слитая строка под HP/MP убрана совсем — у цели остались оверлей
-- вокруг неё и скрытие плавающих канвасов.
-- 1.24.0: блок переехал в ЛЕВУЮ колонку под кнопки Unit (x 20..355): ряд
-- Canvas сдвинут на y=44, поэтому под ним освободилось место. Один набор
-- контролов на выбранный юнит: syncFrameModeControls() прячет лишние,
-- подставляет значения выбранного юнита/канваса и уводит заголовок
-- "Tracked entries" вниз ровно на высоту блока (двигается один якорь группы —
-- за ним едет весь список).
-- =====================================================================
local frameControlsSyncing = false

-- Геометрия левой колонки: блок стоит сразу под рядом Unit (кнопки 44..70) и
-- левее ряда Canvas (он занимает x 340..724). Ширина блока — до x=355, поэтому
-- поля оверлея (X/Y/Size/Per row) идут отдельным рядом, а не в общей строке.
local FRAME_TITLE_Y   = 74
local FRAME_ROW_1     = 100  -- первый ряд чекбоксов
local FRAME_ROW_STEP  = 24   -- чекбокс 17 px + подпись 20 px
local FRAME_ROW_BOTTOM = 20  -- высота ряда по подписи
local FRAME_BLOCK_GAP = 12   -- зазор между последним рядом и "Tracked entries"
local TRACKED_GROUP_NO_BLOCK = 74 -- "Tracked entries" без блока (Mount)

-- y группы "Tracked entries" после блока из rows рядов. Подпись заголовка
-- рисуется на +10 от группы, поэтому из зазора вычитаются эти 10 px.
local function trackedGroupY(rows)
    if not rows or rows < 1 then return TRACKED_GROUP_NO_BLOCK end
    local lastRow = FRAME_ROW_1 + (rows - 1) * FRAME_ROW_STEP
    return lastRow + FRAME_ROW_BOTTOM + FRAME_BLOCK_GAP - 10
end

local function showControl(control, visible)
    if control and control.Show then
        control:Show(visible and true or false)
    end
end

local function anchorControl(control, x, y)
    if not control then return end
    control:RemoveAllAnchors()
    control:AddAnchor("TOPLEFT", settingsWindow, x, y)
end

local function buildFrameModeSection()
    -- Заголовок блока — в левой колонке, сразу под кнопками Unit (44..70).
    local groupLabel = helpers.createLabel('frameModeGroupLabel', settingsWindow,
                                           'Native frame display', 20, FRAME_TITLE_Y, 16)
    groupLabel:SetWidth(320)
    groupLabel:Show(false)
    settingsControls.frameModeGroupLabel = groupLabel

    -- Переключатель режима с сохранением и перерисовкой панелей.
    local function onToggle(unitType, field)
        return function(checked)
            if frameControlsSyncing then return end
            local us = settings and settings[unitType]
            if not us then return end
            us[field] = checked and true or false
            deactivateActivePreset()
            pcall(function() api.SaveSettings() end)
            if helpers and helpers.updateSettings then
                helpers.updateSettings()
            end
            pcall(syncFrameModeControls)
        end
    end

    -- 1.25.0: Player-режим "Under MP bar" убран — у игрока блок пуст.
    -- Target: оверлей у цели — ряд 1 левой колонки.
    local overlayCheck = CbtWindow.CheckButton('cbtTargetOverlay', settingsWindow, onToggle("target", "overlay"))
    if overlayCheck then
        overlayCheck:AddAnchor("TOPLEFT", settingsWindow, 20, FRAME_ROW_1)
        overlayCheck:Show(false)
        CbtWindow.Tooltip(overlayCheck,
            "Draw each target canvas as a compact overlay at the target's screen position (same projection TrackThatPlease uses). When TTP is loaded the row is placed above its target row.")
    end
    settingsControls.overlayCheck = overlayCheck

    local overlayLabel = helpers.createLabel('cbtTargetOverlayLabel', settingsWindow, 'Overlay around target', 42, FRAME_ROW_1 - 1, 13)
    overlayLabel:SetWidth(190)
    overlayLabel:Show(false)
    settingsControls.overlayLabel = overlayLabel

    -- 1.26.0: Hide target canvas — ряд 2. Прячет плавающие канвасы цели;
    -- оверлей, если он включён, продолжает рисоваться.
    local hideCanvasCheck = CbtWindow.CheckButton('cbtTargetHideCanvas', settingsWindow, onToggle("target", "hideCanvas"))
    if hideCanvasCheck then
        hideCanvasCheck:AddAnchor("TOPLEFT", settingsWindow, 20, FRAME_ROW_1 + FRAME_ROW_STEP)
        hideCanvasCheck:Show(false)
        CbtWindow.Tooltip(hideCanvasCheck,
            "Hide every floating target canvas. Buff data keeps running and the Target Overlay still draws when it is on; with Overlay off nothing target-related is drawn.")
    end
    settingsControls.hideCanvasCheck = hideCanvasCheck

    local hideCanvasLabel = helpers.createLabel('cbtTargetHideCanvasLabel', settingsWindow, 'Hide target canvas', 42, FRAME_ROW_1 + FRAME_ROW_STEP - 1, 13)
    hideCanvasLabel:SetWidth(170)
    hideCanvasLabel:Show(false)
    settingsControls.hideCanvasLabel = hideCanvasLabel

    -- Target: не наезжать на ряд TrackThatPlease — ряд 3 (+ поле Gap справа).
    local avoidTTPCheck = CbtWindow.CheckButton('cbtAvoidTTP', settingsWindow, onToggle("target", "avoidTTP"))
    if avoidTTPCheck then
        avoidTTPCheck:AddAnchor("TOPLEFT", settingsWindow, 20, FRAME_ROW_1 + 2 * FRAME_ROW_STEP)
        avoidTTPCheck:Show(false)
        CbtWindow.Tooltip(avoidTTPCheck,
            "Keep the target overlay above TrackThatPlease's target row. Read from TTP settings: targetBuffVerticalOffset, targetIconSize and the UI scale. Turn off to place the overlay with the canvas offsets instead.")
    end
    settingsControls.avoidTTPCheck = avoidTTPCheck

    local avoidTTPLabel = helpers.createLabel('cbtAvoidTTPLabel', settingsWindow, 'Avoid TrackThatPlease', 42, FRAME_ROW_1 + 2 * FRAME_ROW_STEP - 1, 13)
    avoidTTPLabel:SetWidth(150)
    avoidTTPLabel:Show(false)
    settingsControls.avoidTTPLabel = avoidTTPLabel

    local ttpGapLabel = helpers.createLabel('cbtTtpGapLabel', settingsWindow, 'Gap:', 200, FRAME_ROW_1 + 2 * FRAME_ROW_STEP - 1, 13)
    ttpGapLabel:SetWidth(34)
    ttpGapLabel:Show(false)
    settingsControls.ttpGapLabel = ttpGapLabel
    CbtWindow.Tooltip(ttpGapLabel, "Space between our overlay row and TrackThatPlease's row, px.")

    local ttpGap = helpers.createEdit('cbtTtpGap', settingsWindow, '4', 236, FRAME_ROW_1 + 2 * FRAME_ROW_STEP)
    if ttpGap then
        ttpGap:SetMaxTextLength(3)
        ttpGap:SetWidth(45)
        ttpGap:Show(false)
    end
    settingsControls.ttpGap = ttpGap
    bindApplyOnEnter(ttpGap)

    -- Поля оверлея выбранного target-канваса (видны только при Overlay) — ряд 4.
    -- Вся строка умещается в левую колонку (20..332), не заходя под ряд Canvas.
    local overlayRowY = FRAME_ROW_1 + 3 * FRAME_ROW_STEP

    local overlayXLabel = helpers.createLabel('cbtOverlayXLabel', settingsWindow, 'X:', 20, overlayRowY, 13)
    overlayXLabel:SetWidth(14)
    overlayXLabel:Show(false)
    settingsControls.overlayXLabel = overlayXLabel

    local overlayX = helpers.createEdit('cbtOverlayX', settingsWindow, '0', 36, overlayRowY)
    if overlayX then
        overlayX:SetMaxTextLength(5)
        overlayX:SetWidth(42)
        overlayX:Show(false)
    end
    settingsControls.overlayX = overlayX
    bindApplyOnEnter(overlayX)

    local overlayYLabel = helpers.createLabel('cbtOverlayYLabel', settingsWindow, 'Y:', 86, overlayRowY, 13)
    overlayYLabel:SetWidth(14)
    overlayYLabel:Show(false)
    settingsControls.overlayYLabel = overlayYLabel

    local overlayY = helpers.createEdit('cbtOverlayY', settingsWindow, '-30', 102, overlayRowY)
    if overlayY then
        overlayY:SetMaxTextLength(5)
        overlayY:SetWidth(42)
        overlayY:Show(false)
    end
    settingsControls.overlayY = overlayY
    bindApplyOnEnter(overlayY)

    local overlaySizeLabel = helpers.createLabel('cbtOverlaySizeLabel', settingsWindow, 'Size:', 152, overlayRowY, 13)
    overlaySizeLabel:SetWidth(32)
    overlaySizeLabel:Show(false)
    settingsControls.overlaySizeLabel = overlaySizeLabel

    local overlaySize = helpers.createEdit('cbtOverlaySize', settingsWindow, '26', 186, overlayRowY)
    if overlaySize then
        overlaySize:SetMaxTextLength(3)
        overlaySize:SetWidth(42)
        overlaySize:Show(false)
    end
    settingsControls.overlaySize = overlaySize
    bindApplyOnEnter(overlaySize)

    local overlayPerRowLabel = helpers.createLabel('cbtOverlayPerRowLabel', settingsWindow, 'Per row:', 236, overlayRowY, 13)
    overlayPerRowLabel:SetWidth(52)
    overlayPerRowLabel:Show(false)
    settingsControls.overlayPerRowLabel = overlayPerRowLabel

    local overlayPerRow = helpers.createEdit('cbtOverlayPerRow', settingsWindow, '6', 290, overlayRowY)
    if overlayPerRow then
        overlayPerRow:SetMaxTextLength(2)
        overlayPerRow:SetWidth(42)
        overlayPerRow:Show(false)
    end
    settingsControls.overlayPerRow = overlayPerRow
    bindApplyOnEnter(overlayPerRow)

    CbtWindow.Tooltip(overlayXLabel, "Overlay X offset from the target's screen position (ignored while Avoid TrackThatPlease is on).")
    CbtWindow.Tooltip(overlaySizeLabel, "Icon size of the overlay, px (12..64).")
    CbtWindow.Tooltip(overlayPerRowLabel, "Icons per overlay row (1..12). Extra icons wrap downwards.")

    syncFrameModeControls = function()
        if not settingsControls.frameModeGroupLabel then return end
        -- 1.25.0: блок относится только к цели — Mount и Player его не показывают.
        local isTarget = currentUnitType == "target"
        local show = isTarget

        showControl(settingsControls.frameModeGroupLabel, show)

        showControl(settingsControls.overlayCheck, isTarget)
        showControl(settingsControls.overlayLabel, isTarget)
        showControl(settingsControls.hideCanvasCheck, isTarget)
        showControl(settingsControls.hideCanvasLabel, isTarget)
        showControl(settingsControls.avoidTTPCheck, isTarget)
        showControl(settingsControls.avoidTTPLabel, isTarget)
        showControl(settingsControls.ttpGapLabel, isTarget)
        showControl(settingsControls.ttpGap, isTarget)

        local overlayFields = isTarget and settings.target and settings.target.overlay == true
        showControl(settingsControls.overlayXLabel, overlayFields)
        showControl(settingsControls.overlayX, overlayFields)
        showControl(settingsControls.overlayYLabel, overlayFields)
        showControl(settingsControls.overlayY, overlayFields)
        showControl(settingsControls.overlaySizeLabel, overlayFields)
        showControl(settingsControls.overlaySize, overlayFields)
        showControl(settingsControls.overlayPerRowLabel, overlayFields)
        showControl(settingsControls.overlayPerRow, overlayFields)

        -- "Tracked entries" уезжает вниз ровно на высоту блока: у Mount и Player
        -- блока нет, у Target — три ряда (четыре, когда Overlay ON и видны поля
        -- оверлея). Двигается один якорь группы, остальная левая колонка висит
        -- на нём.
        local rows = 0
        if isTarget then
            rows = overlayFields and 4 or 3
        end
        if settingsControls.trackedBuffsGroupLabel then
            anchorControl(settingsControls.trackedBuffsGroupLabel, 34, trackedGroupY(rows))
        end

        -- Подсказка поля ID/name не должна вылезать за нижний край окна.
        settingsControls.acMaxRows = 4

        if not show then return end

        frameControlsSyncing = true
        if isTarget and settings.target then
            if settingsControls.overlayCheck then
                pcall(function()
                    settingsControls.overlayCheck:SetChecked(settings.target.overlay == true)
                end)
            end
            if settingsControls.hideCanvasCheck then
                pcall(function()
                    settingsControls.hideCanvasCheck:SetChecked(settings.target.hideCanvas == true)
                end)
            end
            if settingsControls.avoidTTPCheck then
                pcall(function()
                    settingsControls.avoidTTPCheck:SetChecked(settings.target.avoidTTP ~= false)
                end)
            end
            if settingsControls.ttpGap then
                settingsControls.ttpGap:SetText(tostring(settings.target.ttpGap or 4))
            end
            local cfg = selectedCanvasCfg() or {}
            if settingsControls.overlayX then settingsControls.overlayX:SetText(tostring(cfg.overlayX or 0)) end
            if settingsControls.overlayY then settingsControls.overlayY:SetText(tostring(cfg.overlayY or -30)) end
            if settingsControls.overlaySize then settingsControls.overlaySize:SetText(tostring(cfg.overlaySize or 26)) end
            if settingsControls.overlayPerRow then settingsControls.overlayPerRow:SetText(tostring(cfg.overlayPerRow or 6)) end
        end
        frameControlsSyncing = false
    end
end

local function initSettingsPage()
    settings = helpers.getSettings()

    -- Кастомное окно (как у BetterBars): пустое окно + тёмный ninepart-фон +
    -- собственная шапка с заголовком, крестиком и перетаскиванием.
    settingsWindow = api.Interface:CreateEmptyWindow("CooldawnBuffTrackerSettings")
    if not settingsWindow then
        api.Log:Err("[CBT] Failed to create settings window!")
        return
    end
    settingsWindow:SetExtent(1200, 600)
    settingsWindow:SetUILayer("normal")
    pcall(function() settingsWindow:SetCloseOnEscape(true) end)
    pcall(function() settingsWindow:EnableHidingIsRemove(false) end)

    local winBg = settingsWindow:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    winBg:SetTextureInfo("bg_quest")
    winBg:SetInset(6, 6, 6, 6)
    winBg:SetColor(0.045, 0.048, 0.055, 0.98)
    winBg:AddAnchor("TOPLEFT", settingsWindow, 0, 0)
    winBg:AddAnchor("BOTTOMRIGHT", settingsWindow, 0, 0)

    local header = settingsWindow:CreateChildWidget("emptywidget", "cbtSettingsHeader", 0, true)
    header:SetExtent(1200, 30)
    header:AddAnchor("TOPLEFT", settingsWindow, 0, 0)
    header:AddAnchor("TOPRIGHT", settingsWindow, 0, 0)
    header:Clickable(true)
    local headerBg = header:CreateColorDrawable(0.015, 0.015, 0.020, 0.96, "background")
    headerBg:AddAnchor("TOPLEFT", header, 0, 0)
    headerBg:AddAnchor("BOTTOMRIGHT", header, 0, 0)

    local titleLabel = header:CreateChildWidget("label", "cbtSettingsTitle", 0, true)
    titleLabel:SetExtent(320, 22)
    titleLabel:AddAnchor("LEFT", header, 12, 0)
    titleLabel.style:SetFontSize(18)
    titleLabel.style:SetAlign(ALIGN.LEFT)
    titleLabel.style:SetColor(0.87, 0.69, 0.0, 1)
    titleLabel:SetText("Cooldown Buff Tracker")

    local closeBtn = header:CreateChildWidget("button", "cbtSettingsClose", 0, true)
    closeBtn:SetExtent(20, 20)
    closeBtn:AddAnchor("RIGHT", header, -8, 0)
    api.Interface:ApplyButtonSkin(closeBtn, BUTTON_BASIC.WINDOW_SMALL_CLOSE)
    closeBtn:SetHandler("OnClick", function() settingsWindowClose() end)

    header:EnableDrag(true)
    if header.RegisterForDrag then
        pcall(function() header:RegisterForDrag("LeftButton") end)
    end
    header:SetHandler("OnDragStart", function()
        settingsWindow:StartMoving()
        pcall(function() api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0) end)
    end)
    header:SetHandler("OnDragStop", function()
        settingsWindow:StopMovingOrSizing()
        pcall(function() api.Cursor:ClearCursor() end)
    end)
    header:SetHandler("OnDragEnd", function()
        settingsWindow:StopMovingOrSizing()
        pcall(function() api.Cursor:ClearCursor() end)
    end)
    settingsWindow.header = header

    -- Тёмная подложка контента: дочерний виджет создан ДО секций, поэтому лежит
    -- над фоном окна и под остальными элементами.
    local body = settingsWindow:CreateChildWidget("emptywidget", "cbtSettingsBody", 0, false)
    if body then
        body:SetExtent(1192, 562)
        body:AddAnchor("TOPLEFT", settingsWindow, 4, 34)
        body:Show(true)
        local bodyBg = body:CreateColorDrawable(0.055, 0.060, 0.070, 0.97, "background")
        bodyBg:AddAnchor("TOPLEFT", body, 0, 0)
        bodyBg:AddAnchor("BOTTOMRIGHT", body, 0, 0)
    end

    settingsWindow:AddAnchor("CENTER", 'UIParent', 0, 0)
    settingsWindow:SetHandler("OnCloseByEsc", settingsWindowClose)
    function settingsWindow:OnClose() settingsWindowClose() end

    buildUnitTypeSelector()
    buildCanvasSelector()
    local buffsListContainer, trackedBuffsGroupLabel = buildTrackedBuffsSection()
    local newBuffIdLabel = buildNewBuffInput(buffsListContainer)
    local customBuffsListContainer = buildCustomBuffsSection(newBuffIdLabel, trackedBuffsGroupLabel)
    local customBuffErrorPanel = buildCustomBuffInputs(customBuffsListContainer)
    local showLabelButton, iconSpacingLabel = buildIconSection(customBuffErrorPanel)
    local lockButton = buildPositionSection(settingsControls.gridBottomLabel or showLabelButton, iconSpacingLabel)
    buildTimerSection(lockButton)
    buildFrameModeSection()

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

    if settingsControls.gridGroupLabel then settingsControls.gridGroupLabel:Show(true) end
    if settingsControls.gridColumns then settingsControls.gridColumns:Show(true) end
    if settingsControls.gridRows then settingsControls.gridRows:Show(true) end
    if settingsControls.maxIcons then settingsControls.maxIcons:Show(true) end

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
    -- Попапы/диалоги канвасов
    if canvasPopup then
        pcall(function() CbtWindow.Destroy(canvasPopup) end)
        canvasPopup = nil
    end
    if renameWindow then
        pcall(function() CbtWindow.Destroy(renameWindow) end)
        renameWindow = nil
    end
    if deleteWindow then
        pcall(function() CbtWindow.Destroy(deleteWindow) end)
        deleteWindow = nil
    end

    if settingsWindow ~= nil then
        if settingsWindow.header then
            pcall(function() settingsWindow.header:ReleaseHandler("OnDragStop") end)
            pcall(function() settingsWindow.header:ReleaseHandler("OnDragStart") end)
        end
        settingsWindow:Show(false)
        pcall(function() api.Interface:Free(settingsWindow) end)
        settingsWindow = nil
    end

    -- Close icon search window if it's open
    pcall(function() iconSearch.Unload() end)
    pcall(function() recordWindow.Unload() end)
    if cddWindow then
        pcall(function() CbtWindow.Destroy(cddWindow) end)
        cddWindow = nil
    end


    -- Close palette if it's open
    local F_ETC = require('CooldawnBuffTracker/util/etc')
    if F_ETC then
        F_ETC.HidePallet()
    end

    -- Close Import/Export window if it's open
    if importExport and importExport.closeImportExportWindow then
        importExport.closeImportExportWindow()
    end

    -- Close Presets window if it's open
    if presetWindowModule and presetWindowModule.closePresetWindow then
        presetWindowModule.closePresetWindow()
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
        -- Поля формы показываем по выбранному типу: прямое Show(true) на всех
        -- полях открыло бы скрытые поля Buff/Debuff в режиме Skill/Mana
        if settingsControls.applyEntryType then
            pcall(settingsControls.applyEntryType, newEntryKind or "buff")
        end
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

-- true, если канвас (unitType, index) — тот, что сейчас показан в правой колонке.
local function isSelectedCanvas(unitType, index)
    if unitType ~= currentUnitType then return false end
    return selectedCanvasIndex(unitType) == index
end

-- Перестановка записи внутри ЕЁ канваса: сосед ищется только среди записей
-- того же canvasOf, иначе Up/Down не двигали бы строку на экране.
local function moveTrackedWithinCanvas(buffId, direction, unitType)
    unitType = unitType or currentUnitType
    if not settings then settings = helpers.getSettings() end
    local unit = settings and settings[unitType]
    if not unit or type(unit.trackedBuffs) ~= "table" then return false end

    local list = unit.trackedBuffs
    local canvasIdx = selectedCanvasIndex(unitType)
    local pos = nil
    for i, id in ipairs(list) do
        if tostring(id) == tostring(buffId) then
            pos = i
            break
        end
    end
    if not pos then return false end

    local step = (direction == "up") and -1 or 1
    local j = pos + step
    while j >= 1 and j <= #list do
        if canvasIndexOfId(unit, list[j]) == canvasIdx then
            list[pos], list[j] = list[j], list[pos]
            BuffsToTrack.SaveTrackedBuffs(list, unitType)
            return true
        end
        j = j + step
    end
    return false
end

-- Функция для обновления всех списков баффов (используется после импорта)
local function refreshAllLists()
    updateTrackedBuffsList(true)
    updateCustomBuffsList(true)
end

-- Обновление UI настроек извне (вызывается окном пресетов после load/save/delete).
-- Перечитывает значения полей для текущего типа юнита и обновляет кнопку Presets.
local function refreshFromExternal()
    if not settingsWindow then return end
    pcall(updateSettingsFields)
    pcall(function() updateCustomBuffsList(true) end)
    setPresetsButtonText()
end

M.Load = initSettingsPage
M.Unload = Unload
M.openSettingsWindow = openSettingsWindow
M.updatePositionFields = updatePositionFields
M.isSelectedCanvas = isSelectedCanvas
M.moveTrackedWithinCanvas = moveTrackedWithinCanvas
M.openPixelWindow = pixelViewer.openPixelWindow
M.openImportExportWindow = importExport.openImportExportWindow
M.refreshAllLists = refreshAllLists
M.refreshFromExternal = refreshFromExternal
M.startScan = nil
M.onSkillIconFound = onSkillIconFound

return M
