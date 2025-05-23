local api = require("api")
local helpers = require('CooldawnBuffTracker/helpers')

-- Модуль отладки баффов
local BuffDebugger = {}

-- Хранение состояния предыдущих баффов для определения изменений
local previousPlayerBuffs = {}
local previousPetBuffs = {}
local debugTimerActive = false
local lastUpdateTime = 0
local updateInterval = 500 -- миллисекунды между проверками

-- Функция для вывода ID баффа в чат
local function PrintBuffId(buffId, unitId, event)
    if not buffId then return end
    
    -- Получаем название баффа, если оно доступно
    local buffName = "Unknown"
    pcall(function()
        -- Попытка получить имя баффа из BuffList
        local BuffList = require("CooldawnBuffTracker/buff_helper")
        if BuffList and BuffList.GetBuffName then
            buffName = BuffList.GetBuffName(helpers.formatBuffId(buffId))
        end
    end)
    
    -- Форматируем ID баффа, чтобы большие числа отображались полностью без экспоненты
    local formattedBuffId = helpers.formatBuffId(buffId)
    
    -- Формируем и выводим сообщение в чат
    local message = string.format("[BuffTracker] %s - Buff ID: %s, Unit: %s", 
                                 event or "BUFF_EVENT", 
                                 formattedBuffId, 
                                 unitId or "unknown")
    
    -- Выводим сообщение в чат
    pcall(function()
        if api.Log then
            api.Log:Info(message)
        elseif io and io.write then
            -- Запасной вариант, если нет API чата
            io.write(message .. "\n")
        end
    end)
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
    
    -- Если это игрок, также проверяем дебаффы
    if unitId == "player" then
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
    local previousBuffs = unitId == "player" and previousPlayerBuffs or previousPetBuffs
    
    -- Проверяем добавленные баффы
    for buffId in pairs(currentBuffs) do
        if not previousBuffs[buffId] then
            -- Новый бафф найден
            if unitId == "player" then
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
            if unitId == "player" then
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
    
    -- Проверяем баффы игрока и питомца/маунта
    pcall(function()
        CheckUnitBuffs("player")
        CheckUnitBuffs("playerpet")
    end)
end

-- Инициализация модуля отладки
function BuffDebugger.Initialize()
    -- Получаем текущие настройки
    local settings = helpers.getSettings()
    
    -- Проверяем, включен ли режим отладки
    if settings and settings.debugBuffId then
        -- Подписываемся на события баффов
        pcall(function()
            -- Используем api.On вместо RegisterEventHandler
            api.On("PLAYER_BUFF_ADDED", OnPlayerBuffAdded)
            api.On("PLAYER_BUFF_REMOVED", OnPlayerBuffRemoved)
            api.On("PLAYERPET_BUFF_ADDED", OnPetBuffAdded)
            api.On("PLAYERPET_BUFF_REMOVED", OnPetBuffRemoved)
            
            -- Подписываемся на события дебаффов для игрока, если они доступны
            pcall(function()
                api.On("PLAYER_DEBUFF_ADDED", function(event, args)
                    if args and args.buff_id then
                        PrintBuffId(args.buff_id, "player", "DEBUFF_ADDED")
                    end
                end)
                
                api.On("PLAYER_DEBUFF_REMOVED", function(event, args)
                    if args and args.buff_id then
                        PrintBuffId(args.buff_id, "player", "DEBUFF_REMOVED")
                    end
                end)
            end)
            
            -- Используем событие UPDATE для проверки баффов с интервалом
            if not debugTimerActive then
                api.On("UPDATE", OnDebugUpdateTimer)
                debugTimerActive = true
                lastUpdateTime = api.Time:GetUiMsec() / 1000
                
                -- Очищаем предыдущие данные
                previousPlayerBuffs = {}
                previousPetBuffs = {}
                
                -- Инициализируем первоначальное состояние
                pcall(function()
                    CheckUnitBuffs("player")
                    CheckUnitBuffs("playerpet")
                end)
            end
        end)
        
        -- Выводим сообщение о включении режима отладки
        pcall(function()
            api.Log:Info("[BuffTracker] Buff debug mode enabled. Buff IDs will be displayed in chat.")
        end)
    end
end

-- Остановка модуля отладки
function BuffDebugger.Shutdown()
    -- Убираем таймер
    debugTimerActive = false
    
    -- Очищаем данные
    previousPlayerBuffs = {}
    previousPetBuffs = {}
end

-- Выводит список всех активных баффов для юнита
local function PrintAllActiveBuffs(unitId)
    local buffCount = api.Unit:UnitBuffCount(unitId) or 0
    local buffList = {}
    
    pcall(function()
        api.Log:Info(string.format("[BuffTracker] Active buffs for %s (%d):", unitId, buffCount))
    end)
    
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
                pcall(function()
                    local BuffList = require("CooldawnBuffTracker/buff_helper")
                    if BuffList and BuffList.GetBuffName then
                        buffName = BuffList.GetBuffName(helpers.formatBuffId(buffId))
                    end
                end)
                
                -- Выводим информацию о баффе
                pcall(function()
                    -- Форматируем ID баффа, чтобы большие числа отображались полностью
                    local formattedBuffId = helpers.formatBuffId(buffId)
                    
                    api.Log:Info(string.format("[BuffTracker] %d. Buff ID: %s", 
                                i, formattedBuffId))
                end)
            end
        end
    end
    
    -- Если unitId это игрок, также выводим дебаффы
    if unitId == "player" then
        local debuffCount = api.Unit:UnitDeBuffCount(unitId) or 0
        
        pcall(function()
            api.Log:Info(string.format("[BuffTracker] Active debuffs for %s (%d):", unitId, debuffCount))
        end)
        
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
                    pcall(function()
                        local BuffList = require("CooldawnBuffTracker/buff_helper")
                        if BuffList and BuffList.GetBuffName then
                            debuffName = BuffList.GetBuffName(helpers.formatBuffId(debuffId))
                        end
                    end)
                    
                    -- Выводим информацию о дебаффе
                    pcall(function()
                        -- Форматируем ID дебаффа, чтобы большие числа отображались полностью
                        local formattedDebuffId = helpers.formatBuffId(debuffId)
                        
                        api.Log:Info(string.format("[BuffTracker] %d. Debuff ID: %s", 
                                    i, formattedDebuffId))
                    end)
                end
            end
        end
        
        -- Если дебаффов нет, выводим соответствующее сообщение
        if debuffCount == 0 then
            pcall(function()
                api.Log:Info("[BuffTracker] No active debuffs")
            end)
        end
    end
    
    -- Если баффов нет, выводим соответствующее сообщение
    if buffCount == 0 then
        pcall(function()
            api.Log:Info("[BuffTracker] No active buffs")
        end)
    end
end

-- Функцию для публичного доступа
function BuffDebugger.PrintCurrentBuffs()
    local settings = helpers.getSettings()
    if not settings or not settings.debugBuffId then
        -- Проверяем, включен ли режим отладки
        pcall(function()
            api.Log:Info("[BuffTracker] Buff debug mode is disabled. Enable it in settings.")
        end)
        return
    end
    
    -- Выводим баффы для игрока и питомца
    pcall(function()
        PrintAllActiveBuffs("player")
        PrintAllActiveBuffs("playerpet")
    end)
end

return BuffDebugger 