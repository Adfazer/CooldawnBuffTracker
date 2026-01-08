local api = require("api")
local helpers = require('CooldawnBuffTracker/helpers')

-- Модуль отладки баффов
local BuffDebugger = {}

-- Хранение состояния предыдущих баффов для определения изменений
local previousPlayerBuffs = {}
local previousPetBuffs = {}
local previousTargetBuffs = {}  -- Added for target support
local debugTimerActive = false
local isInitialized = false  -- Flag to prevent multiple initializations
local lastUpdateTime = 0
local updateInterval = 500 -- миллисекунды между проверками

-- Функция для вывода ID баффа в чат
local function PrintBuffId(buffId, unitId, event)
    if not buffId then return end
    
    -- Получаем название баффа, если оно доступно
    local buffName = "Unknown"
    local BuffList = require("CooldawnBuffTracker/buff_helper")
    if BuffList and BuffList.GetBuffName then
        buffName = BuffList.GetBuffName(helpers.formatBuffId(buffId))
    end
    
    -- Форматируем ID баффа, чтобы большие числа отображались полностью без экспоненты
    local formattedBuffId = helpers.formatBuffId(buffId)
    
    -- Формируем и выводим сообщение в чат
    local message = string.format("[CBT] %s - Buff ID: %s, Unit: %s", 
                                 event or "BUFF_EVENT", 
                                 formattedBuffId, 
                                 unitId or "unknown")
    
    -- Выводим сообщение в чат
    if api.Log then
        api.Log:Info(message)
    end
end

-- Обработчик события наложения баффа на игрока
local function OnPlayerBuffAdded(params)
    -- Поддержка нескольких форматов вызова
    local buffId = nil
    if params then
        if params.buffId then -- стандартный формат
            buffId = params.buffId
        elseif params.buff_id then -- альтернативный формат
            buffId = params.buff_id
        elseif type(params) == "table" and params[1] then -- еще один возможный формат
            buffId = params[1]
        end
    end
    
    if buffId then
        PrintBuffId(buffId, "player", "BUFF_ADDED")
    end
end

-- Обработчик события удаления баффа с игрока
local function OnPlayerBuffRemoved(params)
    -- Поддержка нескольких форматов вызова
    local buffId = nil
    if params then
        if params.buffId then
            buffId = params.buffId
        elseif params.buff_id then
            buffId = params.buff_id
        elseif type(params) == "table" and params[1] then
            buffId = params[1]
        end
    end
    
    if buffId then
        PrintBuffId(buffId, "player", "BUFF_REMOVED")
    end
end

-- Обработчик события наложения баффа на питомца/маунта
local function OnPetBuffAdded(params)
    -- Поддержка нескольких форматов вызова
    local buffId = nil
    if params then
        if params.buffId then
            buffId = params.buffId
        elseif params.buff_id then
            buffId = params.buff_id
        elseif type(params) == "table" and params[1] then
            buffId = params[1]
        end
    end
    
    if buffId then
        PrintBuffId(buffId, "playerpet", "BUFF_ADDED")
    end
end

-- Обработчик события удаления баффа с питомца/маунта
local function OnPetBuffRemoved(params)
    -- Поддержка нескольких форматов вызова
    local buffId = nil
    if params then
        if params.buffId then
            buffId = params.buffId
        elseif params.buff_id then
            buffId = params.buff_id
        elseif type(params) == "table" and params[1] then
            buffId = params[1]
        end
    end
    
    if buffId then
        PrintBuffId(buffId, "playerpet", "BUFF_REMOVED")
    end
end

-- Функция проверки текущих баффов для юнита и сравнения с предыдущими
local function CheckUnitBuffs(unitId)
    -- Получаем текущие баффы
    local currentBuffs = {}
    local buffCount = api.Unit:UnitBuffCount(unitId) or 0
    
    for i = 1, buffCount do
        local buff = api.Unit:UnitBuff(unitId, i)
        if buff then
            local buffId = nil
            -- Пробуем разные форматы доступа к ID баффа
            if buff.buff_id then 
                buffId = buff.buff_id
            elseif buff.id then
                buffId = buff.id
            elseif buff[1] then
                buffId = buff[1]
            end
            
            if buffId then
                -- Используем строковый ключ для таблицы, но сохраняем оригинальный формат
                currentBuffs[tostring(buffId)] = buffId
            end
        end
    end
    
    -- Если это игрок или цель, также проверяем дебаффы
    if unitId == "player" or unitId == "target" then
        local debuffCount = api.Unit:UnitDeBuffCount(unitId) or 0
        
        for i = 1, debuffCount do
            local debuff = api.Unit:UnitDeBuff(unitId, i)
            if debuff then
                local debuffId = nil
                -- Пробуем разные форматы доступа к ID дебаффа
                if debuff.buff_id then 
                    debuffId = debuff.buff_id
                elseif debuff.id then
                    debuffId = debuff.id
                elseif debuff[1] then
                    debuffId = debuff[1]
                end
                
                if debuffId then
                    -- Добавляем дебаффы в общий список с префиксом debuff_ для различия
                    local debuffKey = "debuff_" .. tostring(debuffId)
                    currentBuffs[debuffKey] = debuffId
                end
            end
        end
    end
    
    -- Определяем добавленные и удаленные баффы
    local previousBuffs
    if unitId == "player" then
        previousBuffs = previousPlayerBuffs
    elseif unitId == "target" then
        previousBuffs = previousTargetBuffs
    else
        previousBuffs = previousPetBuffs
    end
    
    -- Проверяем добавленные баффы
    for buffId in pairs(currentBuffs) do
        if not previousBuffs[buffId] then
            -- Новый бафф найден
            if unitId == "player" or unitId == "target" then
                if string.sub(buffId, 1, 7) == "debuff_" then
                    PrintBuffId(currentBuffs[buffId], unitId, "DEBUFF_ADDED")
                else
                    PrintBuffId(currentBuffs[buffId], unitId, "BUFF_ADDED")
                end
            else
                PrintBuffId(currentBuffs[buffId], unitId, "BUFF_ADDED")
            end
        end
    end
    
    -- Проверяем удаленные баффы
    for buffId in pairs(previousBuffs) do
        if not currentBuffs[buffId] then
            -- Бафф был удален
            if unitId == "player" or unitId == "target" then
                if string.sub(buffId, 1, 7) == "debuff_" then
                    PrintBuffId(previousBuffs[buffId], unitId, "DEBUFF_REMOVED")
                else
                    PrintBuffId(previousBuffs[buffId], unitId, "BUFF_REMOVED")
                end
            else
                PrintBuffId(previousBuffs[buffId], unitId, "BUFF_REMOVED")
            end
        end
    end
    
    -- Сохраняем текущие баффы как предыдущие для следующей проверки
    if unitId == "player" then
        previousPlayerBuffs = currentBuffs
    elseif unitId == "target" then
        previousTargetBuffs = currentBuffs
    else
        previousPetBuffs = currentBuffs
    end
end

-- Обработчик таймера для проверки баффов
local function OnDebugUpdateTimer(dt)
    -- Получаем текущее время
    local currentTime = api.Time:GetUiMsec() / 1000
    
    -- Проверяем интервал
    if (currentTime - lastUpdateTime) * 1000 < updateInterval then
        return
    end
    
    lastUpdateTime = currentTime
    
    -- Проверяем статус настроек
    local settings = helpers.getSettings()
    if not settings or not settings.debugBuffId then
        -- Если отладка выключена, останавливаем таймер
        debugTimerActive = false
        return
    end
    
    -- Проверяем баффы игрока, питомца/маунта и target
    CheckUnitBuffs("player")
    CheckUnitBuffs("playerpet")
    
    -- Check target buffs if target exists
    local targetId = api.Unit:GetUnitId("target")
    if targetId then
        CheckUnitBuffs("target")
    else
        -- Clear previous target buffs if no target
        previousTargetBuffs = {}
    end
end

-- Инициализация модуля отладки
function BuffDebugger.Initialize()
    -- Prevent multiple initializations
    if isInitialized then
        api.Log:Info("[CBT] Debug mode already initialized, skipping.")
        return
    end
    
    -- Получаем текущие настройки
    local settings = helpers.getSettings()
    
    -- Проверяем, включен ли режим отладки
    if settings and settings.debugBuffId then
        -- Mark as initialized first to prevent re-entry
        isInitialized = true
        
        -- Используем событие UPDATE для проверки баффов с интервалом
        if not debugTimerActive then
            api.On("UPDATE", OnDebugUpdateTimer)
            debugTimerActive = true
            lastUpdateTime = api.Time:GetUiMsec() / 1000
            
            -- Очищаем предыдущие данные
            previousPlayerBuffs = {}
            previousPetBuffs = {}
            previousTargetBuffs = {}
            
            -- Инициализируем первоначальное состояние
            CheckUnitBuffs("player")
            CheckUnitBuffs("playerpet")
            
            -- Check target if exists
            local targetId = api.Unit:GetUnitId("target")
            if targetId then
                CheckUnitBuffs("target")
            end
        end
        
        -- Выводим сообщение о включении режима отладки
        api.Log:Info("[CBT] Buff debug mode enabled. Buff IDs will be displayed in chat.")
    end
end

-- Остановка модуля отладки
function BuffDebugger.Shutdown()
    -- Reset initialization flag first
    isInitialized = false
    
    -- Убираем таймер
    debugTimerActive = false
    
    -- Очищаем данные
    previousPlayerBuffs = {}
    previousPetBuffs = {}
    previousTargetBuffs = {}
    
    api.Log:Info("[CBT] Buff debug mode disabled.")
end

-- Выводит список всех активных баффов для юнита
local function PrintAllActiveBuffs(unitId)
    local buffCount = api.Unit:UnitBuffCount(unitId) or 0
    local buffList = {}
    
    api.Log:Info(string.format("[CBT] Active buffs for %s (%d):", unitId, buffCount))
    
    for i = 1, buffCount do
        local buff = api.Unit:UnitBuff(unitId, i)
        if buff then
            local buffId = nil
            -- Пробуем разные форматы доступа к ID баффа
            if buff.buff_id then 
                buffId = buff.buff_id
            elseif buff.id then
                buffId = buff.id
            elseif buff[1] then
                buffId = buff[1]
            end
            
            if buffId then
                -- Получаем название баффа
                local buffName = "Unknown"
                local BuffList = require("CooldawnBuffTracker/buff_helper")
                if BuffList and BuffList.GetBuffName then
                    buffName = BuffList.GetBuffName(helpers.formatBuffId(buffId))
                end
                
                -- Выводим информацию о баффе
                local formattedBuffId = helpers.formatBuffId(buffId)
                api.Log:Info(string.format("[CBT] %d. Buff ID: %s", i, formattedBuffId))
            end
        end
    end
    
    -- Если unitId это игрок или цель, также выводим дебаффы
    if unitId == "player" or unitId == "target" then
        local debuffCount = api.Unit:UnitDeBuffCount(unitId) or 0
        
        api.Log:Info(string.format("[CBT] Active debuffs for %s (%d):", unitId, debuffCount))
        
        for i = 1, debuffCount do
            local debuff = api.Unit:UnitDeBuff(unitId, i)
            if debuff then
                local debuffId = nil
                -- Пробуем разные форматы доступа к ID дебаффа
                if debuff.buff_id then 
                    debuffId = debuff.buff_id
                elseif debuff.id then
                    debuffId = debuff.id
                elseif debuff[1] then
                    debuffId = debuff[1]
                end
                
                if debuffId then
                    -- Получаем название дебаффа
                    local debuffName = "Unknown"
                    local BuffList = require("CooldawnBuffTracker/buff_helper")
                    if BuffList and BuffList.GetBuffName then
                        debuffName = BuffList.GetBuffName(helpers.formatBuffId(debuffId))
                    end
                    
                    -- Выводим информацию о дебаффе
                    local formattedDebuffId = helpers.formatBuffId(debuffId)
                    api.Log:Info(string.format("[CBT] %d. Debuff ID: %s", i, formattedDebuffId))
                end
            end
        end
        
        -- Если дебаффов нет, выводим соответствующее сообщение
        if debuffCount == 0 then
            api.Log:Info("[CBT] No active debuffs")
        end
    end
    
    -- Если баффов нет, выводим соответствующее сообщение
    if buffCount == 0 then
        api.Log:Info("[CBT] No active buffs")
    end
end

-- Функцию для публичного доступа
function BuffDebugger.PrintCurrentBuffs()
    local settings = helpers.getSettings()
    if not settings or not settings.debugBuffId then
        -- Проверяем, включен ли режим отладки
        api.Log:Info("[CBT] Buff debug mode is disabled. Enable it in settings.")
        return
    end
    
    -- Выводим баффы для игрока, питомца и target
    PrintAllActiveBuffs("player")
    PrintAllActiveBuffs("playerpet")
    
    -- Check target if exists
    local targetId = api.Unit:GetUnitId("target")
    if targetId then
        PrintAllActiveBuffs("target")
    else
        api.Log:Info("[CBT] No target selected")
    end
end

return BuffDebugger
