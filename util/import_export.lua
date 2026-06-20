-- Модуль для Import/Export конфигурации баффов
local api = require("api")
local helpers = require("CooldawnBuffTracker/helpers")

-- Переменная для хранения ссылки на окно
local importExportWindow = nil
-- Виджеты окна, которые нужно сбрасывать при повторном открытии (окно
-- создаётся один раз и переиспользуется, чтобы не плодить виджеты в памяти)
local ieWidgets = {}

-- Простой JSON encoder/decoder
local json = {}

-- Escape символ для JSON
local function escapeChar(c)
    local escapeMap = {
        ["\""] = "\\\"",
        ["\\"] = "\\\\",
        ["/"] = "\\/",
        ["\b"] = "\\b",
        ["\f"] = "\\f",
        ["\n"] = "\\n",
        ["\r"] = "\\r",
        ["\t"] = "\\t"
    }
    return escapeMap[c] or string.format("\\u%04x", string.byte(c))
end

-- JSON encode
function json.encode(value, indent)
    indent = indent or ""
    local localIndent = indent .. "  "
    
    local t = type(value)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        -- Проверка на NaN и infinity
        if value ~= value then
            return "null"
        elseif value == math.huge then
            return "null"
        elseif value == -math.huge then
            return "null"
        end
        -- Форматируем число без экспоненты
        return string.format("%.0f", value)
    elseif t == "string" then
        return "\"" .. value:gsub('[%z\001-\031"\\/]', escapeChar) .. "\""
    elseif t == "table" then
        -- Проверка на массив (последовательные числовые ключи)
        local isArray = true
        local maxIndex = 0
        for k, v in pairs(value) do
            if type(k) ~= "number" or k <= 0 or k > 2147483647 or math.floor(k) ~= k then
                isArray = false
                break
            end
            if k > maxIndex then
                maxIndex = k
            end
        end
        if isArray and #value == 0 then
            -- Пустой массив
            return "[]"
        end
        if isArray then
            -- Проверка на плотность массива
            for i = 1, maxIndex do
                if value[i] == nil then
                    isArray = false
                    break
                end
            end
        end
        
        if isArray then
            local result = {}
            for i = 1, #value do
                result[#result + 1] = json.encode(value[i], localIndent)
            end
            return "[" .. table.concat(result, ", ") .. "]"
        else
            local result = {}
            local keys = {}
            for k in pairs(value) do
                keys[#keys + 1] = k
            end
            table.sort(keys)
            
            for i, k in ipairs(keys) do
                local v = value[k]
                local keyEncoded
                if type(k) == "string" then
                    keyEncoded = "\"" .. k:gsub('[%z\001-\031"\\/]', escapeChar) .. "\""
                elseif type(k) == "number" then
                    keyEncoded = "\"" .. string.format("%.0f", k) .. "\""
                else
                    keyEncoded = "\"" .. tostring(k) .. "\""
                end
                result[#result + 1] = keyEncoded .. ": " .. json.encode(v, localIndent)
            end
            return "{" .. table.concat(result, ", ") .. "}"
        end
    else
        return "null"
    end
end

-- JSON decode - простой парсер
function json.decode(str)
    local pos = 1
    local function skipWhitespace()
        while pos <= #str and (str:sub(pos, pos) == " " or str:sub(pos, pos) == "\t" or str:sub(pos, pos) == "\n" or str:sub(pos, pos) == "\r") do
            pos = pos + 1
        end
    end
    
    local function parseString()
        local result = {}
        pos = pos + 1 -- Skip opening quote
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == "\"" then
                pos = pos + 1 -- Skip closing quote
                return table.concat(result)
            elseif c == '\\' then
                pos = pos + 1
                local nextChar = str:sub(pos, pos)
                if nextChar == "\"" then
                    result[#result + 1] = "\""
                elseif nextChar == '\\' then
                    result[#result + 1] = '\\'
                elseif nextChar == '/' then
                    result[#result + 1] = '/'
                elseif nextChar == 'b' then
                    result[#result + 1] = '\b'
                elseif nextChar == 'f' then
                    result[#result + 1] = '\f'
                elseif nextChar == 'n' then
                    result[#result + 1] = '\n'
                elseif nextChar == 'r' then
                    result[#result + 1] = '\r'
                elseif nextChar == 't' then
                    result[#result + 1] = '\t'
                elseif nextChar == 'u' then
                    local hex = str:sub(pos + 1, pos + 4)
                    result[#result + 1] = string.char(tonumber(hex, 16))
                    pos = pos + 4
                end
                pos = pos + 1
            else
                result[#result + 1] = c
                pos = pos + 1
            end
        end
        return nil -- Unterminated string
    end
    
    local function parseNumber()
        local startPos = pos
        if str:sub(pos, pos) == "-" then
            pos = pos + 1
        end
        while pos <= #str and (str:sub(pos, pos):match("%d") or str:sub(pos, pos) == ".") do
            pos = pos + 1
        end
        if pos <= #str and (str:sub(pos, pos) == "e" or str:sub(pos, pos) == "E") then
            pos = pos + 1
            if pos <= #str and (str:sub(pos, pos) == "+" or str:sub(pos, pos) == "-") then
                pos = pos + 1
            end
            while pos <= #str and str:sub(pos, pos):match("%d") do
                pos = pos + 1
            end
        end
        -- ВАЖНО: pos уже указывает на первый символ после числа (разделитель
        -- , ] } или пробел). НЕ продвигаем pos дальше, иначе съедим разделитель
        -- и разбор массива/объекта сломается.
        local numStr = str:sub(startPos, pos - 1)
        return tonumber(numStr)
    end
    
    local function parseValue()
        skipWhitespace()
        if pos > #str then
            return nil
        end
        
        local c = str:sub(pos, pos)
        if c == "\"" then
            return parseString()
        elseif c == "{" then
            pos = pos + 1
            local obj = {}
            skipWhitespace()
            while pos <= #str and str:sub(pos, pos) ~= "}" do
                skipWhitespace()
                local key = parseValue()
                if key == nil then
                    return nil
                end
                skipWhitespace()
                if pos > #str or str:sub(pos, pos) ~= ":" then
                    return nil
                end
                pos = pos + 1 -- Skip colon
                local val = parseValue()
                if val == nil then
                    return nil
                end
                obj[key] = val
                skipWhitespace()
                if pos <= #str and str:sub(pos, pos) == "," then
                    pos = pos + 1
                end
                skipWhitespace()
            end
            pos = pos + 1 -- Skip closing brace
            return obj
        elseif c == "[" then
            pos = pos + 1
            local arr = {}
            skipWhitespace()
            while pos <= #str and str:sub(pos, pos) ~= "]" do
                local val = parseValue()
                if val == nil then
                    return nil
                end
                arr[#arr + 1] = val
                skipWhitespace()
                if pos <= #str and str:sub(pos, pos) == "," then
                    pos = pos + 1
                end
                skipWhitespace()
            end
            pos = pos + 1 -- Skip closing bracket
            return arr
        elseif c == "t" then
            if str:sub(pos, pos + 3) == "true" then
                pos = pos + 4
                return true
            end
            return nil
        elseif c == "f" then
            if str:sub(pos, pos + 4) == "false" then
                pos = pos + 5
                return false
            end
            return nil
        elseif c == "n" then
            if str:sub(pos, pos + 3) == "null" then
                pos = pos + 4
                return nil
            end
            return nil
        elseif c == "-" or c:match("%d") then
            return parseNumber()
        else
            return nil
        end
    end
    
    return parseValue()
end

-- Экспорт конфигурации в JSON строку
-- Собирает таблицу текущей конфигурации (общая часть для текстового и файлового экспорта)
local function buildConfigTable()
    local settings = api.GetSettings("CooldawnBuffTracker")
    if not settings then
        api.Log:Err("[CBT] Failed to get settings for export")
        return nil
    end
    return {
        customBuffs = settings.customBuffs or {},
        trackedBuffs = {
            playerpet = settings.playerpet and settings.playerpet.trackedBuffs or {},
            player = settings.player and settings.player.trackedBuffs or {},
            target = settings.target and settings.target.trackedBuffs or {}
        }
    }
end

local function exportConfiguration()
    local config = buildConfigTable()
    if not config then return nil end

    local success, result = pcall(function()
        return json.encode(config)
    end)

    if not success then
        api.Log:Err("[CBT] Failed to encode configuration: " .. tostring(result))
        return nil
    end

    return result
end

-- Импорт конфигурации из JSON строки
local function importConfiguration(configString, errorMsgLabel)
    -- Валидация входных данных
    if not configString or configString == "" then
        if errorMsgLabel then
            errorMsgLabel:SetText("Import field is empty - paste a configuration into the lower field first")
        end
        api.Log:Info("[CBT] Import: the Import field is empty - paste a configuration into the lower field first")
        return false
    end
    
    -- Парсинг JSON
    local success, config = pcall(function()
        return json.decode(configString)
    end)
    
    if not success or not config then
        if errorMsgLabel then
            errorMsgLabel:SetText("Error: Invalid JSON format")
        end
        api.Log:Err("[CBT] Import failed: Invalid JSON format - " .. tostring(config))
        return false
    end
    
    -- Валидация структуры
    if type(config) ~= "table" then
        if errorMsgLabel then
            errorMsgLabel:SetText("Error: Configuration must be a table")
        end
        api.Log:Err("[CBT] Import failed: Configuration must be a table")
        return false
    end
    
    if config.customBuffs == nil or config.trackedBuffs == nil then
        if errorMsgLabel then
            errorMsgLabel:SetText("Error: Missing required fields (customBuffs, trackedBuffs)")
        end
        api.Log:Err("[CBT] Import failed: Missing required fields")
        return false
    end
    
    if type(config.customBuffs) ~= "table" or type(config.trackedBuffs) ~= "table" then
        if errorMsgLabel then
            errorMsgLabel:SetText("Error: customBuffs and trackedBuffs must be tables")
        end
        api.Log:Err("[CBT] Import failed: customBuffs and trackedBuffs must be tables")
        return false
    end
    
    if config.trackedBuffs.playerpet == nil or config.trackedBuffs.player == nil or config.trackedBuffs.target == nil then
        if errorMsgLabel then
            errorMsgLabel:SetText("Error: Missing trackedBuffs fields (playerpet, player, target)")
        end
        api.Log:Err("[CBT] Import failed: Missing trackedBuffs fields")
        return false
    end
    
    -- Валидация customBuffs
    for i, buff in ipairs(config.customBuffs) do
        if type(buff) ~= "table" then
            if errorMsgLabel then
                errorMsgLabel:SetText("Error: Custom buff at index " .. i .. " is not a table")
            end
            api.Log:Err("[CBT] Import failed: Custom buff at index " .. i .. " is not a table")
            return false
        end
        if not buff.id or not buff.name or not buff.cooldown or not buff.timeOfAction then
            if errorMsgLabel then
                errorMsgLabel:SetText("Error: Custom buff at index " .. i .. " missing required fields")
            end
            api.Log:Err("[CBT] Import failed: Custom buff at index " .. i .. " missing required fields")
            return false
        end
    end
    
    -- Валидация trackedBuffs (проверяем, что это массивы чисел)
    local unitTypes = {"playerpet", "player", "target"}
    for _, unitType in ipairs(unitTypes) do
        local trackedBuffs = config.trackedBuffs[unitType]
        if type(trackedBuffs) ~= "table" then
            if errorMsgLabel then
                errorMsgLabel:SetText("Error: trackedBuffs." .. unitType .. " is not a table")
            end
            api.Log:Err("[CBT] Import failed: trackedBuffs." .. unitType .. " is not a table")
            return false
        end
        for j, buffId in ipairs(trackedBuffs) do
            -- Принимаем числа и числовые строки, но ТИП НЕ меняем: ID хранятся так
            -- же, как их добавляет аддон (строкой), иначе сопоставление с данными
            -- баффа сломается -> "неизвестный бафф".
            if not tonumber(buffId) then
                if errorMsgLabel then
                    errorMsgLabel:SetText("Error: trackedBuffs." .. unitType .. " contains non-number at index " .. j)
                end
                api.Log:Err("[CBT] Import failed: trackedBuffs." .. unitType .. " contains non-number at index " .. j)
                return false
            end
        end
    end
    
    -- Получаем текущие настройки
    local settings = api.GetSettings("CooldawnBuffTracker")
    if not settings then
        if errorMsgLabel then
            errorMsgLabel:SetText("Error: Failed to get current settings")
        end
        api.Log:Err("[CBT] Import failed: Failed to get current settings")
        return false
    end
    
    -- Обновляем только нужные поля (сохраняем в постоянное хранилище)
    settings.customBuffs = config.customBuffs
    
    if not settings.playerpet then settings.playerpet = {} end
    settings.playerpet.trackedBuffs = config.trackedBuffs.playerpet
    
    if not settings.player then settings.player = {} end
    settings.player.trackedBuffs = config.trackedBuffs.player
    
    if not settings.target then settings.target = {} end
    settings.target.trackedBuffs = config.trackedBuffs.target
    
    -- Сохраняем в постоянное хранилище через api.SaveSettings()
    api.SaveSettings()
    
    -- Обновляем UI
    if helpers and helpers.updateSettings then
        helpers.updateSettings()
    end
    
    -- Отправляем события для обновления списков баффов
    api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
    
    api.Log:Info("[CBT] Configuration imported successfully")
    return true
end

-- ===== Файловый экспорт/импорт (отдать/получить конфиг файлом) =====

-- Уникальное имя файла: cbt_config_<charName>_<msec>.txt
local function makeExportFileName()
    local charName = "player"
    local okN, nm = pcall(function()
        local id = api.Unit:GetUnitId("player")
        return id and api.Unit:GetUnitNameById(id) or nil
    end)
    if okN and nm and nm ~= "" then
        charName = tostring(nm):gsub("[^%w]", "")
    end
    if charName == "" then charName = "player" end

    local stamp = "0"
    local okT, ms = pcall(function() return api.Time:GetUiMsec() end)
    if okT and ms then stamp = tostring(math.floor(ms)) end

    return "cbt_config_" .. charName .. "_" .. stamp .. ".txt"
end

-- Пути в api.File относительны папки addons; кладём файлы в каталог аддона
local CONFIG_DIR = "CooldawnBuffTracker/"

-- Экспорт текущей конфигурации в файл. Возвращает путь к файлу или nil + ошибку.
local function exportConfigurationToFile()
    local config = buildConfigTable()
    if not config then return nil, "Failed to read settings" end

    local filename = makeExportFileName()
    local path = CONFIG_DIR .. filename

    local ok, err = pcall(function() api.File:Write(path, config) end)
    if not ok then
        api.Log:Err("[CBT] Failed to write config file: " .. tostring(err))
        return nil, "Failed to write file"
    end
    api.Log:Info("[CBT] Configuration saved to file: " .. path)
    return path
end

-- Импорт конфигурации из файла по имени. Переиспользует проверенную логику
-- применения (table -> json -> importConfiguration).
local function importConfigurationFromFile(filename, errorMsgLabel)
    filename = filename and (filename:gsub("^%s+", ""):gsub("%s+$", "")) or ""
    if filename == "" then
        if errorMsgLabel then errorMsgLabel:SetText("Enter the name of the config file first") end
        api.Log:Info("[CBT] Import from file: no file name entered")
        return false
    end

    -- Игнорируем расширение: берём только имя и подставляем .txt (если путь без папки)
    local path
    if filename:find("/") then
        path = filename
    else
        local base = filename:gsub("%.%w+$", "")  -- срезаем любое расширение
        path = CONFIG_DIR .. base .. ".txt"
    end

    local ok, config = pcall(function() return api.File:Read(path) end)
    if not ok or type(config) ~= "table" then
        if errorMsgLabel then
            errorMsgLabel:SetText("Could not read file: " .. tostring(filename) .. " (put it into the CooldawnBuffTracker folder)")
        end
        api.Log:Err("[CBT] Import from file failed: " .. tostring(config))
        return false
    end

    local okEnc, jsonStr = pcall(function() return json.encode(config) end)
    if not okEnc or type(jsonStr) ~= "string" then
        if errorMsgLabel then errorMsgLabel:SetText("File has an unexpected format") end
        return false
    end

    return importConfiguration(jsonStr, errorMsgLabel)
end

-- Функция для открытия окна Import/Export
local function openImportExportWindow(onImportSuccess)
    -- Переключатель: если окно открыто — закрываем (НЕ уничтожаем, переиспользуем)
    if importExportWindow and importExportWindow:IsVisible() then
        importExportWindow:Show(false)
        return
    end
    -- Окно уже создано — сбрасываем поля и показываем заново (без пересоздания)
    if importExportWindow then
        if ieWidgets.fileStatus then ieWidgets.fileStatus:SetText("") end
        if ieWidgets.importFileEdit then ieWidgets.importFileEdit:SetText("") end
        if ieWidgets.errorPanel then ieWidgets.errorPanel:Show(false) end
        importExportWindow:Show(true)
        return
    end

    -- Первое открытие — создаём окно ОДИН раз
    importExportWindow = api.Interface:CreateWindow("CooldawnBuffTrackerImportExport",
                                         "Import / Export Configuration", 600, 380)

    importExportWindow:AddAnchor("CENTER", 'UIParent', 0, 0)
    importExportWindow:SetHandler("OnCloseByEsc", function()
        importExportWindow:Show(false)
    end)
    function importExportWindow:OnClose()
        importExportWindow:Show(false)
    end
    
    -- Добавляем фон окна
    local background = importExportWindow:CreateColorDrawable(0.1, 0.1, 0.1, 0.95, "background")
    background:AddAnchor("TOPLEFT", importExportWindow, 0, 0)
    background:AddAnchor("BOTTOMRIGHT", importExportWindow, 0, 0)
    
    -- Секция EXPORT
    local exportLabel = api.Interface:CreateWidget('label', 'exportLabel', importExportWindow)
    exportLabel:SetExtent(560, 25)
    exportLabel:AddAnchor("TOP", importExportWindow, 0, 20)
    exportLabel:SetText("EXPORT - save your current setup to a file:")
    exportLabel.style:SetFontSize(17)
    exportLabel.style:SetColor(0.87, 0.69, 0, 1)
    exportLabel.style:SetAlign(ALIGN.LEFT)
    
    -- Кнопка: сохранить мой конфиг в файл (его можно сразу отдать)
    local saveFileButton = api.Interface:CreateWidget('button', 'cbtSaveFileButton', importExportWindow)
    saveFileButton:AddAnchor("TOP", exportLabel, "BOTTOM", 0, 12)
    saveFileButton:SetExtent(260, 34)
    saveFileButton:SetText("Save my config to a file")
    api.Interface:ApplyButtonSkin(saveFileButton, BUTTON_BASIC.DEFAULT)

    local fileStatus = api.Interface:CreateWidget('label', 'cbtFileStatus', importExportWindow)
    fileStatus:SetExtent(560, 22)
    fileStatus:AddAnchor("TOP", saveFileButton, "BOTTOM", 0, 8)
    fileStatus:SetText("")
    fileStatus.style:SetFontSize(13)
    fileStatus.style:SetColor(0.4, 1, 0.4, 1)
    fileStatus.style:SetAlign(ALIGN.CENTER)
    ieWidgets.fileStatus = fileStatus

    saveFileButton:SetHandler("OnClick", function()
        local path, err = exportConfigurationToFile()
        if path then
            fileStatus.style:SetColor(0.4, 1, 0.4, 1)
            fileStatus:SetText("Saved to: " .. path)
        else
            fileStatus.style:SetColor(1, 0.4, 0.4, 1)
            fileStatus:SetText("Could not save file: " .. tostring(err or "error"))
        end
    end)

    -- ============ IMPORT: загрузить чужой конфиг ============
    local importLabel = api.Interface:CreateWidget('label', 'importLabel', importExportWindow)
    importLabel:SetExtent(560, 25)
    importLabel:AddAnchor("TOP", fileStatus, "BOTTOM", 0, 16)
    importLabel:SetText("IMPORT - load a config you received")
    importLabel.style:SetFontSize(17)
    importLabel.style:SetColor(0.87, 0.69, 0, 1)
    importLabel.style:SetAlign(ALIGN.LEFT)

    -- Загрузка из файла: имя файла + кнопка
    local fileNameHint = api.Interface:CreateWidget('label', 'cbtFileNameHint', importExportWindow)
    fileNameHint:SetExtent(560, 20)
    fileNameHint:AddAnchor("TOP", importLabel, "BOTTOM", 0, 6)
    fileNameHint:SetText("File name (put the received file into the CooldawnBuffTracker folder):")
    fileNameHint.style:SetFontSize(13)
    fileNameHint.style:SetColor(0.8, 0.8, 0.8, 1)
    fileNameHint.style:SetAlign(ALIGN.LEFT)

    local importFileEdit = W_CTRL.CreateEdit("importFileEdit", importExportWindow)
    importFileEdit:SetExtent(360, 26)
    importFileEdit:AddAnchor("TOPLEFT", fileNameHint, "BOTTOMLEFT", 0, 4)
    importFileEdit.style:SetColor(0, 0, 0, 1)
    importFileEdit.style:SetAlign(ALIGN.LEFT)
    importFileEdit.style:SetFontSize(12)
    importFileEdit:SetText("")
    ieWidgets.importFileEdit = importFileEdit

    local loadFileButton = api.Interface:CreateWidget('button', 'cbtLoadFileButton', importExportWindow)
    loadFileButton:AddAnchor("LEFT", importFileEdit, "RIGHT", 12, 0)
    loadFileButton:SetExtent(185, 30)
    loadFileButton:SetText("Load config from file")
    api.Interface:ApplyButtonSkin(loadFileButton, BUTTON_BASIC.DEFAULT)

    -- Панель ошибок для импорта
    local errorPanel = api.Interface:CreateWidget('window', 'importErrorPanel', importExportWindow)
    errorPanel:SetExtent(560, 25)
    errorPanel:AddAnchor("TOPLEFT", importFileEdit, "BOTTOMLEFT", 0, 16)
    errorPanel:Show(false)
    
    -- Рамка для панели ошибок
    local errorPanelBorder = errorPanel:CreateNinePartDrawable("ui/chat_option.dds", "artwork")
    errorPanelBorder:SetCoords(0, 0, 27, 16)
    errorPanelBorder:SetInset(0, 8, 0, 7)
    errorPanelBorder:AddAnchor("TOPLEFT", errorPanel, -1, -1)
    errorPanelBorder:AddAnchor("BOTTOMRIGHT", errorPanel, 1, 1)
    
    -- Фон для панели ошибок
    local errorPanelBg = errorPanel:CreateColorDrawable(0.98, 0.85, 0.85, 0.9, "background")
    errorPanelBg:AddAnchor("TOPLEFT", errorPanel, 0, 0)
    errorPanelBg:AddAnchor("BOTTOMRIGHT", errorPanel, 0, 0)
    
    -- Текст ошибки
    local errorMsg = api.Interface:CreateWidget('label', 'errorMsg', errorPanel)
    errorMsg:SetText("")
    errorMsg:AddAnchor("TOPLEFT", 5, 5)
    errorMsg:SetExtent(560, 20)
    errorMsg.style:SetFontSize(14)
    errorMsg.style:SetColor(1, 0, 0, 1)
    errorMsg:Show(true)
    ieWidgets.errorPanel = errorPanel

    -- Загрузка чужого конфига из файла (импорт)
    loadFileButton:SetHandler("OnClick", function()
        local success = importConfigurationFromFile(importFileEdit:GetText(), errorMsg)
        if success then
            errorPanel:Show(false)
            importExportWindow:Show(false)
            api.Log:Info("[CBT] Configuration imported from file - window closed")
            if onImportSuccess then onImportSuccess() end
        else
            errorPanel:Show(true)
        end
    end)

    -- Кнопка Close
    local closeButton = api.Interface:CreateWidget('button', 'closeButton', importExportWindow)
    closeButton:AddAnchor("BOTTOM", importExportWindow, 0, -20)
    closeButton:SetExtent(150, 35)
    closeButton:SetText("Close")
    api.Interface:ApplyButtonSkin(closeButton, BUTTON_BASIC.DEFAULT)
    
    closeButton:SetHandler("OnClick", function()
        importExportWindow:Show(false)
        importExportWindow = nil
    end)
    
    importExportWindow:Show(true)
end

-- Функция для закрытия окна, если оно открыто
local function closeImportExportWindow()
    if importExportWindow then
        importExportWindow:Show(false)
    end
end

-- Экспортируем функции для использования в других модулях
return {
    openImportExportWindow = openImportExportWindow,
    closeImportExportWindow = closeImportExportWindow,
    exportConfiguration = exportConfiguration,
    importConfiguration = importConfiguration,
    exportConfigurationToFile = exportConfigurationToFile,
    importConfigurationFromFile = importConfigurationFromFile
}
