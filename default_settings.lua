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
}

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
    },
    customBuffs = {},           -- Таблица для хранения пользовательских баффов
    debugBuffId = false,        -- Флаг режима отладки баффов (отключен по умолчанию)
    -- 1.21.0: эффективные КД только для панели Target (мастер-включение).
    -- Список навыков выбирается в окне Effective CDs и хранится в customBuffs
    -- как permanent-записи; выключено = показывается настроенный CD.
    effectiveCd = false,
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

    -- 1.21.0: эффективные КД (мастер-включение, по умолчанию выключено)
    if settings.effectiveCd == nil then
        settings.effectiveCd = false
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

    return settings
end

-- Публичные утилиты для страницы настроек/импорта.
defaultSettings.unitTypes = UNIT_TYPES
defaultSettings.layoutFields = LAYOUT_FIELDS
defaultSettings.cloneValue = cloneValue
defaultSettings.newCanvas = newCanvas
defaultSettings.normalizeCanvas = normalizeCanvas
defaultSettings.normalizeUnit = migrateUnit

return defaultSettings
