local defaultSettings = {
    enabled = true,
    playerpet = {
        posX = 330,
        posY = 30,
        iconSize = 40,
        iconSpacing = 5,
        gridColumns = 10,  -- Этап 4: число колонок в сетке иконок
        gridRows = 1,      -- число строк в сетке
        maxIcons = 10,     -- максимум одновременно отображаемых иконок (<= gridColumns*gridRows)
        gridRowSpacing = 5, -- вертикальный отступ между строками сетки
        lockPositioning = false,
        enabled = true,
        timerTextColor = {r = 1, g = 1, b = 1, a = 1},
        labelTextColor = {r = 1, g = 1, b = 1, a = 1},
        showLabel = false,
        labelFontSize = 14,
        labelX = 0,
        labelY = -30,
        showTimer = true,
        timerFontSize = 16,
        timerX = 0,
        timerY = 0,
        trackedBuffs = {}  -- Empty array - user specifies buffs themselves
    },
    player = {
        posX = 330,
        posY = 100,  -- Slightly lower than mount
        iconSize = 40,
        iconSpacing = 5,
        gridColumns = 10,  -- Этап 4: число колонок в сетке иконок
        gridRows = 1,      -- число строк в сетке
        maxIcons = 10,     -- максимум одновременно отображаемых иконок (<= gridColumns*gridRows)
        gridRowSpacing = 5, -- вертикальный отступ между строками сетки
        lockPositioning = false,
        enabled = true,
        timerTextColor = {r = 1, g = 1, b = 1, a = 1},
        labelTextColor = {r = 1, g = 1, b = 1, a = 1},
        showLabel = false,
        labelFontSize = 14,
        labelX = 0,
        labelY = -30,
        showTimer = true,
        timerFontSize = 16,
        timerX = 0,
        timerY = 0,
        trackedBuffs = {}  -- Empty array - user specifies buffs themselves
    },
    target = {
        posX = 330,
        posY = 170,  -- Below player
        iconSize = 40,
        iconSpacing = 5,
        gridColumns = 10,  -- Этап 4: число колонок в сетке иконок
        gridRows = 1,      -- число строк в сетке
        maxIcons = 10,     -- максимум одновременно отображаемых иконок (<= gridColumns*gridRows)
        gridRowSpacing = 5, -- вертикальный отступ между строками сетки
        lockPositioning = false,
        enabled = true,
        timerTextColor = {r = 1, g = 1, b = 1, a = 1},
        labelTextColor = {r = 1, g = 1, b = 1, a = 1},
        showLabel = false,
        labelFontSize = 14,
        labelX = 0,
        labelY = -30,
        showTimer = true,
        timerFontSize = 16,
        timerX = 0,
        timerY = 0,
        trackedBuffs = {},  -- Empty array - user specifies buffs themselves
        cacheTimeout = 300  -- 5 минут в секундах - время очистки кэша target
    },
    customBuffs = {}, -- Таблица для хранения пользовательских баффов
    debugBuffId = false -- Флаг режима отладки баффов (отключен по умолчанию)
}

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

    -- Таблица пресетов создаётся один раз и далее живёт в settings.txt
    if settings.presets == nil then
        settings.presets = {}
    end

    -- activePresetName остаётся nil, пока пользователь не загрузит пресет
    -- (специально не присваиваем значение, чтобы не перетереть существующее)

    -- Этап 4: добиваем поля сетки иконок существующим пользователям,
    -- не затирая уже сохранённые значения.
    local gridDefaults = { gridColumns = 10, gridRows = 1, maxIcons = 10, gridRowSpacing = 5 }
    for _, unitType in ipairs({"playerpet", "player", "target"}) do
        if type(settings[unitType]) == "table" then
            for key, value in pairs(gridDefaults) do
                if settings[unitType][key] == nil then
                    settings[unitType][key] = value
                end
            end
        end
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
        for _, unitType in ipairs({"playerpet", "player", "target"}) do
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

return defaultSettings