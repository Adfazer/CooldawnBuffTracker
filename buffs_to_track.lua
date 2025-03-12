-- buffs_to_track.lua
-- Файл содержит список ID баффов, которые нужно постоянно отслеживать
local api = require("api")

local BuffsToTrack = {}

-- Загружаем отслеживаемые баффы из настроек
local function loadTrackedBuffsFromSettings(unitType)
    local settings = api.GetSettings("CooldawnBuffTracker") or {}
    
    -- Проверяем, что настройки для указанного типа юнита существуют
    if not settings[unitType] then
        settings[unitType] = {
            trackedBuffs = {},
            enabled = true
        }
        api.SaveSettings()
    end
    
    -- Проверяем специальную настройку, которая отключает отслеживание баффов для указанного типа юнита
    if settings[unitType].enabled == false then
        return {} -- Возвращаем пустой список, если отслеживание отключено
    end
    
    -- Если в настройках нет баффов, создаем пустой список
    if not settings[unitType].trackedBuffs then
        settings[unitType].trackedBuffs = {}
        -- Сохраняем пустой список в настройках
        api.SaveSettings()
    end
    
    return settings[unitType].trackedBuffs
end

-- Сохраняем список отслеживаемых баффов в настройки
function BuffsToTrack.SaveTrackedBuffs(buffIdList, unitType)
    unitType = unitType or "playerpet" -- По умолчанию используем маунта
    
    local settings = api.GetSettings("CooldawnBuffTracker") or {}
    
    -- Проверяем, что настройки для указанного типа юнита существуют
    if not settings[unitType] then
        settings[unitType] = {}
    end
    
    settings[unitType].trackedBuffs = buffIdList
    
    -- Если список пуст, явно отключаем отслеживание баффов
    if #buffIdList == 0 then
        settings[unitType].enabled = false
    else
        settings[unitType].enabled = true
    end
    
    api.SaveSettings()
    
    -- Отправляем событие для обновления канваса
    api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
end

-- Добавляем новый бафф в список отслеживаемых
function BuffsToTrack.AddTrackedBuff(buffId, unitType)
    unitType = unitType or "playerpet" -- По умолчанию используем маунта
    
    buffId = tonumber(buffId)
    if not buffId then return false end
    
    local trackedBuffs = loadTrackedBuffsFromSettings(unitType)
    
    -- Проверяем, не отслеживается ли уже этот бафф
    for _, id in ipairs(trackedBuffs) do
        if id == buffId then
            return false -- Бафф уже отслеживается
        end
    end
    
    -- Добавляем бафф в список
    table.insert(trackedBuffs, buffId)
    
    -- Сохраняем обновленный список
    BuffsToTrack.SaveTrackedBuffs(trackedBuffs, unitType)
    
    return true -- Бафф успешно добавлен
end

-- Удаляем бафф из списка отслеживаемых
function BuffsToTrack.RemoveTrackedBuff(buffId, unitType)
    unitType = unitType or "playerpet" -- По умолчанию используем маунта
    
    buffId = tonumber(buffId)
    if not buffId then return false end
    
    local trackedBuffs = loadTrackedBuffsFromSettings(unitType)
    
    -- Ищем бафф в списке
    for i, id in ipairs(trackedBuffs) do
        if id == buffId then
            -- Удаляем бафф
            table.remove(trackedBuffs, i)
            
            -- Сохраняем обновленный список
            BuffsToTrack.SaveTrackedBuffs(trackedBuffs, unitType)
            
            -- Отправляем общее событие для обновления канваса
            api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
            
            return true
        end
    end
    
    return false  -- Бафф не найден
end

-- Полностью очищаем список отслеживаемых баффов
function BuffsToTrack.ClearAllTrackedBuffs(unitType)
    unitType = unitType or "playerpet" -- По умолчанию используем маунта
    
    -- Сохраняем пустой список
    BuffsToTrack.SaveTrackedBuffs({}, unitType)
    
    -- Отправляем событие для обновления канваса
    api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
    
    return true
end

-- Проверить, нужно ли отслеживать указанный бафф
function BuffsToTrack.ShouldTrackBuff(buffId, unitType)
    unitType = unitType or "playerpet" -- По умолчанию используем маунта
    
    local trackedBuffs = loadTrackedBuffsFromSettings(unitType)
    
    for _, id in ipairs(trackedBuffs) do
        if id == buffId then
            return true
        end
    end
    
    return false
end

-- Получить список всех отслеживаемых баффов
function BuffsToTrack.GetAllTrackedBuffIds(unitType)
    unitType = unitType or "playerpet" -- По умолчанию используем маунта
    
    return loadTrackedBuffsFromSettings(unitType)
end

return BuffsToTrack