-- Значения по умолчанию.
-- Модель 1.20: у каждого типа юнита есть список канвасов (canvases). Каждый
-- канвас хранит собственную раскладку (позиция, размер, сетка, таймер, цвета),
-- а trackedBuffs/mirror/canvasOf остаются на уровне юнита: сканирование аур
-- одно на юнит, канвасы лишь рисуют свои подмножества.
local UNIT_TYPES = { "playerpet", "player", "target" }

-- Поля раскладки, которые в 1.19 лежали прямо в таблице юнита.
local LAYOUT_FIELDS = {
    "posX", "posY", "iconSize", "iconSpacing",
    "gridColumns", "gridRows", "maxIcons", "gridRowSpacing",
    "lockPositioning", "timerTextColor", "labelTextColor",
    "showLabel", "labelFontSize", "labelX", "labelY",
    "showTimer", "timerFontSize", "timerX", "timerY",
}

local CANVAS_LAYOUT_DEFAULT = {
    posX = 330,
    posY = 30,
    iconSize = 40,
    iconSpacing = 5,
    gridColumns = 10,
    gridRows = 1,
    maxIcons = 10,
    gridRowSpacing = 5,
    lockPositioning = false,
    timerTextColor = { r = 1, g = 1, b = 1, a = 1 },
    labelTextColor = { r = 1, g = 1, b = 1, a = 1 },
    showLabel = false,
    labelFontSize = 14,
    labelX = 0,
    labelY = -30,
    showTimer = true,
    timerFontSize = 16,
    timerX = 0,
    timerY = 0,
    -- 1.23.0: оверлей вокруг фрейма цели. Поля есть у каждого канваса (в
    -- настройках они показываются только для Target при включённом Overlay),
    -- чтобы включение режима не меняло модель данных.
    overlayX = 0,
    overlayY = -30,
    overlaySize = 26,
    overlayPerRow = 6,
}

-- 1.23.0: режимы показа, привязанные к нативным фреймам юнита. Живут на
-- уровне юнита, а не канваса: это переключатели показа всех канвасов юнита.
-- 1.25.0: Player-режим "Under MP bar" убран — DISPLAY_FIELDS только у цели.
-- 1.26.0: строка под HP/MP убрана совсем; остались оверлей цели и скрытие
-- её плавающих канвасов.
local DISPLAY_FIELDS = { "overlay", "hideCanvas", "avoidTTP", "ttpGap" }

local function clampNumber(value, minValue, maxValue, fallback)
    local n = tonumber(value)
    if not n or n ~= n then return fallback end
    n = math.floor(n + 0.5)
    if n < minValue then n = minValue end
    if n > maxValue then n = maxValue end
    return n
end

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = cloneValue(v)
    end
    return copy
end

-- Новый канвас с полным набором полей раскладки.
local function newCanvas(name, posX, posY)
    local canvas = { name = name or "Main" }
    for k, v in pairs(CANVAS_LAYOUT_DEFAULT) do
        canvas[k] = cloneValue(v)
    end
    if posX ~= nil then canvas.posX = posX end
    if posY ~= nil then canvas.posY = posY end
    return canvas
end

local defaultSettings = {
    enabled = true,
    buffOverrides = {},
    playerpet = {
        enabled = true,
        canvases = { newCanvas("Main", 330, 30) },
        canvasOf = {},          -- [tostring(buffId)] = индекс канваса
        selectedCanvas = 1,
        trackedBuffs = {},      -- общий список юнита (union всех канвасов)
        mirror = {},            -- [id]=true: ауру читаем с player, показываем на target
    },
    player = {
        enabled = true,
        canvases = { newCanvas("Main", 330, 100) },
        canvasOf = {},
        selectedCanvas = 1,
        trackedBuffs = {},
        mirror = {},
    },
    target = {
        enabled = true,
        canvases = { newCanvas("Main", 330, 170) },
        canvasOf = {},
        selectedCanvas = 1,
        trackedBuffs = {},
        mirror = {},
        cacheTimeout = 300,     -- 5 минут в секундах - время очистки кэша target
        overlay = false,        -- 1.23.0: оверлей каждого канваса вокруг фрейма
        hideCanvas = false,     -- 1.26.0: не рисовать плавающие канвасы цели
        avoidTTP = true,        -- ставить оверлей над рядом TrackThatPlease
        ttpGap = 4,             -- зазор между нашим рядом и рядом TTP, px
    },
    customBuffs = {},           -- Таблица для хранения пользовательских баффов
    debugBuffId = false,        -- Флаг режима отладки баффов (отключен по умолчанию)
}

-- Добивает недостающие поля одного канваса, не затирая сохранённые значения.
local function normalizeCanvas(canvas, index, fallbackPosY)
    if type(canvas) ~= "table" then
        return newCanvas("Canvas " .. tostring(index), 330, fallbackPosY or 30)
    end
    for k, v in pairs(CANVAS_LAYOUT_DEFAULT) do
        if type(v) == "table" then
            if type(canvas[k]) ~= "table" then
                canvas[k] = cloneValue(v)
            else
                for ck, cv in pairs(v) do
                    if canvas[k][ck] == nil then canvas[k][ck] = cv end
                end
            end
        elseif canvas[k] == nil then
            canvas[k] = v
        end
    end
    if type(canvas.name) ~= "string" or canvas.name:gsub("%s", "") == "" then
        canvas.name = "Canvas " .. tostring(index)
    else
        canvas.name = canvas.name:gsub("^%s+", ""):gsub("%s+$", "")
        if canvas.name == "" then canvas.name = "Canvas " .. tostring(index) end
    end
    return canvas
end

-- Тип кастомной записи: "buff" (бафф/дебафф), "skill" (навык по боевому логу)
-- или "mana" (навык маунта, который тратит ману). У записей до 1.22.0 поля
-- kind нет — выводим тип из данных записи.
local function entryKind(cb)
    if type(cb) ~= "table" then return "buff" end
    local k = cb.kind
    if k == "buff" or k == "skill" or k == "mana" then return k end
    if (tonumber(cb.manaCost) or 0) > 0 then return "mana" end
    if type(cb.spellName) == "string" and cb.spellName ~= "" then return "skill" end
    return "buff"
end

-- Старая (1.19 и раньше) плоская раскладка -> canvases[1] с именем "Main".
local function migrateFlatToCanvases(unit, unitType)
    local posY = defaultSettings[unitType] and defaultSettings[unitType].canvases[1].posY or 30
    local canvas = newCanvas("Main", 330, posY)
    local migrated = false
    for _, field in ipairs(LAYOUT_FIELDS) do
        local value = unit[field]
        if value ~= nil then
            canvas[field] = cloneValue(value)
            migrated = true
        end
    end
    if type(unit.canvasName) == "string" and unit.canvasName ~= "" then
        canvas.name = unit.canvasName
    end
    unit.canvasName = nil
    return canvas, migrated
end

-- Приводит таблицу юнита к модели канвасов. Возвращает true, если что-то
-- изменилось (нужно, чтобы вызывающий код мог сохранить настройки).
local function migrateUnit(unit, unitType)
    if type(unit) ~= "table" then
        return false
    end
    local changed = false

    if type(unit.canvases) ~= "table" or #unit.canvases == 0 then
        local canvas, migrated = migrateFlatToCanvases(unit, unitType)
        unit.canvases = { canvas }
        changed = migrated or true
    end

    -- Плоские поля больше не читаются: убираем их совсем.
    for _, field in ipairs(LAYOUT_FIELDS) do
        if unit[field] ~= nil then
            unit[field] = nil
            changed = true
        end
    end

    -- Уплотняем список (на случай дыр после ручного редактирования).
    local list = {}
    for i = 1, #unit.canvases do
        local canvas = unit.canvases[i]
        if type(canvas) == "table" then
            list[#list + 1] = canvas
        else
            changed = true
        end
    end
    if #list == 0 then
        list[1] = newCanvas("Main", 330, defaultSettings[unitType] and defaultSettings[unitType].canvases[1].posY or 30)
        changed = true
    end
    unit.canvases = list

    for i = 1, #unit.canvases do
        if type(unit.canvases[i].name) ~= "string" then changed = true end
        normalizeCanvas(unit.canvases[i], i, defaultSettings[unitType] and defaultSettings[unitType].canvases[1].posY or 30)
        local canvas = unit.canvases[i]
        -- maxIcons не может превышать ёмкость сетки
        local cols = math.floor(tonumber(canvas.gridColumns) or 10)
        local rows = math.floor(tonumber(canvas.gridRows) or 1)
        if cols < 1 then cols = 1 end
        if rows < 1 then rows = 1 end
        local capacity = cols * rows
        if capacity > 40 then capacity = 40 end
        local maxIcons = math.floor(tonumber(canvas.maxIcons) or capacity)
        if maxIcons < 1 then maxIcons = 1 end
        if maxIcons > capacity then maxIcons = capacity end
        canvas.maxIcons = maxIcons

        -- 1.23.0: поля оверлея цели. У сохранений до 1.23.0 их нет
        -- (normalizeCanvas уже добил дефолты), но значения могли прийти
        -- строками из импорта — приводим к числу и диапазону.
        local ox = clampNumber(canvas.overlayX, -2000, 2000, 0)
        local oy = clampNumber(canvas.overlayY, -2000, 2000, -30)
        local osize = clampNumber(canvas.overlaySize, 12, 64, 26)
        local oper = clampNumber(canvas.overlayPerRow, 1, 12, 6)
        if canvas.overlayX ~= ox or canvas.overlayY ~= oy
            or canvas.overlaySize ~= osize or canvas.overlayPerRow ~= oper then
            changed = true
        end
        canvas.overlayX, canvas.overlayY = ox, oy
        canvas.overlaySize, canvas.overlayPerRow = osize, oper
    end

    if type(unit.canvasOf) ~= "table" then
        unit.canvasOf = {}
        changed = true
    end
    local count = #unit.canvases
    for key, value in pairs(unit.canvasOf) do
        local idx = tonumber(value)
        if not idx or idx ~= math.floor(idx) or idx < 1 or idx > count then
            idx = 1
        end
        if unit.canvasOf[key] ~= idx then
            unit.canvasOf[key] = idx
            changed = true
        end
    end

    local selected = tonumber(unit.selectedCanvas) or 1
    selected = math.floor(selected)
    if selected < 1 or selected > count then selected = 1 end
    if unit.selectedCanvas ~= selected then
        unit.selectedCanvas = selected
        changed = true
    end

    if type(unit.trackedBuffs) ~= "table" then
        unit.trackedBuffs = {}
        changed = true
    end
    if type(unit.mirror) ~= "table" then
        unit.mirror = {}
        changed = true
    end
    if unit.enabled == nil then
        unit.enabled = true
        changed = true
    end

    -- 1.26.0: строка под HP/MP убрана полностью — её ключи (underBars и запас
    -- под чужой строкой) больше не читаются, чистим их из сохранений.
    -- 1.25.0: Player-режим "Under MP bar" убран вместе с underMp.
    if unit.underBars ~= nil then
        unit.underBars = nil
        changed = true
    end
    if unit.stripOffsetY ~= nil then
        unit.stripOffsetY = nil
        changed = true
    end
    if unitType == "player" and unit.underMp ~= nil then
        unit.underMp = nil
        changed = true
    end

    -- 1.23.0: режимы у нативных фреймов. У старых сохранений полей нет —
    -- добиваем дефолтами юнита; выключенное пользователем значение (false)
    -- сохраняется, потому что проверяем только nil.
    local unitDefaults = defaultSettings[unitType]
    if unitDefaults then
        for _, field in ipairs(DISPLAY_FIELDS) do
            if unitDefaults[field] ~= nil and unit[field] == nil then
                unit[field] = unitDefaults[field]
                changed = true
            end
        end
    end
    if unit.ttpGap ~= nil then
        local gap = clampNumber(unit.ttpGap, 0, 200, 4)
        if unit.ttpGap ~= gap then
            unit.ttpGap = gap
            changed = true
        end
    end

    return changed
end

-- Миграция новых полей без перезаписи уже сохранённых настроек.
-- ВАЖНО: поля presets / activePresetName намеренно НЕ добавляются в саму таблицу
-- defaultSettings. Иначе при каждой загрузке аддона defaults затирали бы
-- сохранённые пользователем пресеты. Вместо этого создаём их один раз здесь,
-- только если их ещё нет в постоянном хранилище.
function defaultSettings.migrate(settings)
    if not settings then return settings end

    -- Верхнеуровневый enabled нужен списку аддонов (кнопка Options в ESC-меню)
    if settings.enabled == nil then
        settings.enabled = true
    end

    -- Пользовательские CD/D для обычных (не кастомных) баффов
    if type(settings.buffOverrides) ~= "table" then
        settings.buffOverrides = {}
    end

    -- Таблица пресетов создаётся один раз и далее живёт в settings.txt
    if settings.presets == nil then
        settings.presets = {}
    end

    -- activePresetName остаётся nil, пока пользователь не загрузит пресет
    -- (специально не присваиваем значение, чтобы не перетереть существующее)

    -- 1.20: плоские настройки юнитов -> canvases[1] ("Main").
    for _, unitType in ipairs(UNIT_TYPES) do
        migrateUnit(settings[unitType], unitType)
    end

    -- 1.7.3: кастомные баффы, добавленные без ID (пустая строка), получают ключ
    -- из spellName или name; пустые ключи в списках трекинга заменяются им же.
    local emptyIdReplacement = nil
    if type(settings.customBuffs) == "table" then
        for _, cb in ipairs(settings.customBuffs) do
            if type(cb) == "table" and (cb.id == nil or cb.id == "") then
                local newId = nil
                if type(cb.spellName) == "string" and cb.spellName ~= "" then
                    newId = cb.spellName
                elseif type(cb.name) == "string" and cb.name ~= "" then
                    newId = cb.name
                end
                if newId then
                    cb.id = newId
                    emptyIdReplacement = newId
                end
            end
        end
    end
    if emptyIdReplacement then
        for _, unitType in ipairs(UNIT_TYPES) do
            local list = settings[unitType] and settings[unitType].trackedBuffs
            if type(list) == "table" then
                for i, id in ipairs(list) do
                    if id == "" then
                        list[i] = emptyIdReplacement
                    end
                end
            end
        end
    end

    -- 1.22.0: тип кастомной записи (buff/skill/mana) хранится в kind.
    -- У записей 1.21 и раньше поля нет — выводим один раз из данных записи.
    -- 1.28.0: эффективные КД цели — флаг, smart % и список модификаторов.
    if type(settings.customBuffs) == "table" then
        for _, cb in ipairs(settings.customBuffs) do
            if type(cb) == "table" then
                cb.kind = entryKind(cb)
                if cb.effectiveCDs == nil then cb.effectiveCDs = false end
                local smart = tonumber(cb.smartPct)
                if smart == nil or smart ~= smart then smart = 0 end
                if smart < 0 then smart = 0 end
                if smart > 100 then smart = 100 end
                cb.smartPct = smart
                if type(cb.cdMods) ~= "table" then
                    cb.cdMods = {}
                else
                    -- Чистим мусор из ручных/импортированных конфигов
                    for i = #cb.cdMods, 1, -1 do
                        local mod = cb.cdMods[i]
                        if type(mod) ~= "table" then
                            table.remove(cb.cdMods, i)
                        else
                            if mod.kind ~= "flat" and mod.kind ~= "percent" and mod.kind ~= "reset" then
                                mod.kind = "flat"
                            end
                            if mod.kind == "reset" then
                                mod.value = nil
                            else
                                mod.value = tonumber(mod.value) or 0
                                if mod.value < 0 then mod.value = 0 end
                            end
                            if mod.condition ~= "always" then mod.condition = "target" end
                        end
                    end
                end
            end
        end
    end

    return settings
end

-- Публичные утилиты для страницы настроек/импорта.
defaultSettings.unitTypes = UNIT_TYPES
defaultSettings.entryKind = entryKind
defaultSettings.layoutFields = LAYOUT_FIELDS
defaultSettings.cloneValue = cloneValue
defaultSettings.newCanvas = newCanvas
defaultSettings.normalizeCanvas = normalizeCanvas
defaultSettings.normalizeUnit = migrateUnit
defaultSettings.clampNumber = clampNumber

return defaultSettings
