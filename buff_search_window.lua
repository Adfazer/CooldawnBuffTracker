-- buff_search_window.lua
-- Окно поиска баффов CooldawnBuffTracker.
-- Позволяет найти бафф по ID (цифры) или по имени (буквы) и добавить его в
-- отслеживание одним кликом, не зная заранее числовой ID.
--
-- Источник данных: BuffList.ddsData (buff_helper.lua) — карта id -> иконка,
-- содержащая все известные клиенту баффы. Имена берутся из игрового API
-- (api.Ability.GetBuffTooltip) и кэшируются один раз при первом поиске по имени,
-- чтобы не дёргать API на каждый кадр и не вешать клиент.
--
-- ВАЖНО: модуль НЕ требует settings_page напрямую (во избежание циклического
-- require). Действие «добавить» передаётся колбэком из settings_page.
local api = require("api")
local helpers = require('CooldawnBuffTracker/helpers')
local BuffList = require('CooldawnBuffTracker/buff_helper')

local searchWindow = nil
local controls = {}
local resultWidgets = {}
local resultPage = 1
local resultsPerPage = 7

-- Колбэк добавления баффа: function(buffId) -> ok, message
local onAddCallback = nil

-- Кэш данных
local allBuffIds = nil          -- отсортированный список всех id (строки)
local nameIndex = nil           -- id -> имя в нижнем регистре (только реальные имена)
local nameIndexBuilt = false
local currentResults = {}       -- отфильтрованный список id под текущий запрос

-- Предварительное объявление локальных функций (Lua 5.1 требует порядка)
local openBuffSearchWindow, closeBuffSearchWindow
local createSearchWindowUI, updateResultList, performSearch
local setStatus

-- ----- Данные -----

-- Собираем и кэшируем список всех id из ddsData (один раз)
local function buildBuffIdList()
    if allBuffIds then return allBuffIds end
    allBuffIds = {}
    if BuffList and BuffList.ddsData then
        for idStr, _ in pairs(BuffList.ddsData) do
            table.insert(allBuffIds, idStr)
        end
    end
    table.sort(allBuffIds, function(a, b)
        return (tonumber(a) or 0) < (tonumber(b) or 0)
    end)
    return allBuffIds
end

-- Получить реальное имя баффа из игры (или nil, если неизвестно)
local function resolveName(idStr)
    if not (api and api.Ability and api.Ability.GetBuffTooltip) then
        return nil
    end
    local tooltip = nil
    pcall(function() tooltip = api.Ability.GetBuffTooltip(idStr) end)
    if tooltip and tooltip.name and tooltip.name ~= "" then
        return tooltip.name
    end
    return nil
end

-- Построить индекс имён один раз (синхронно). Дорогая операция вызывается
-- только при первом поиске по имени; результат кэшируется на сессию.
local function ensureNameIndex()
    if nameIndexBuilt then return end
    nameIndexBuilt = true
    nameIndex = {}

    local ids = buildBuffIdList()
    pcall(function()
        for _, idStr in ipairs(ids) do
            local nm = resolveName(idStr)
            if nm then
                nameIndex[idStr] = string.lower(nm)
            end
        end
    end)
    api.Log:Info("[CBT] Buff name index built")
end

-- ----- UI helpers -----

function setStatus(message, isError)
    if not controls.statusLabel then return end
    controls.statusLabel:SetText(tostring(message or ""))
    if isError then
        controls.statusLabel.style:SetColor(1, 0.3, 0.3, 1)
    else
        controls.statusLabel.style:SetColor(0.2, 1, 0.2, 1)
    end
end

-- ----- Поиск -----

-- Заполняет currentResults по тексту запроса
function performSearch(query)
    currentResults = {}
    query = query or ""
    -- trim
    query = query:gsub("^%s*(.-)%s*$", "%1")

    if query == "" then
        setStatus("Enter buff ID digits or a name fragment", false)
        resultPage = 1
        updateResultList()
        return
    end

    local ids = buildBuffIdList()
    local isNumeric = query:match("^%d+$") ~= nil

    if isNumeric then
        -- Поиск по подстроке ID
        for _, idStr in ipairs(ids) do
            if idStr:find(query, 1, true) then
                table.insert(currentResults, idStr)
            end
        end
    else
        -- Поиск по имени: требуется индекс имён
        if #query < 2 then
            setStatus("Type at least 2 letters to search by name", true)
            resultPage = 1
            updateResultList()
            return
        end
        ensureNameIndex()
        local q = string.lower(query)
        for _, idStr in ipairs(ids) do
            local nm = nameIndex[idStr]
            if nm and nm:find(q, 1, true) then
                table.insert(currentResults, idStr)
            end
        end
    end

    resultPage = 1
    if #currentResults == 0 then
        setStatus("No buffs found for: " .. query, true)
    else
        setStatus("Found " .. #currentResults .. " buff(s)", false)
    end
    updateResultList()
end

-- ----- Список результатов -----

function updateResultList()
    -- Очищаем ранее созданные строки
    for _, widget in ipairs(resultWidgets) do
        if widget then
            widget:Show(false)
            widget:RemoveAllAnchors()
        end
    end
    resultWidgets = {}

    local container = controls.listContainer
    if not container then return end

    local total = #currentResults
    local totalPages = math.max(1, math.ceil(total / resultsPerPage))
    if resultPage > totalPages then resultPage = totalPages end
    if resultPage < 1 then resultPage = 1 end

    if controls.pageIndicator then
        controls.pageIndicator:SetText(resultPage .. "/" .. totalPages)
    end

    if total == 0 then
        return
    end

    local startIndex = (resultPage - 1) * resultsPerPage + 1
    local endIndex = math.min(startIndex + resultsPerPage - 1, total)

    local yOffset = 8
    for i = startIndex, endIndex do
        local buffId = currentResults[i]
        -- Имя: из индекса (если есть) или из игры по требованию
        local name = nil
        if nameIndex and nameIndex[buffId] then
            name = resolveName(buffId) or nameIndex[buffId]
        else
            name = resolveName(buffId)
        end
        name = name or ("Buff #" .. buffId)

        local row = api.Interface:CreateWidget('window', 'cbtBuffSearchRow_' .. i, container)
        row:SetExtent(490, 24)
        row:RemoveAllAnchors()
        row:AddAnchor("TOPLEFT", container, 10, yOffset)
        row:Show(true)

        -- Иконка баффа (если фреймворк предоставляет CreateItemIconButton/F_SLOT).
        -- Всё под guard'ами: при отсутствии API строка просто остаётся без иконки.
        local textLeft = 0
        if CreateItemIconButton then
            local icon = CreateItemIconButton('cbtBuffSearchIcon_' .. i, row)
            if icon then
                icon:SetExtent(22, 22)
                icon:RemoveAllAnchors()
                icon:AddAnchor("LEFT", row, 0, 0)
                if F_SLOT and F_SLOT.SetIconBackGround and BuffList.GetBuffIcon then
                    pcall(function() F_SLOT.SetIconBackGround(icon, BuffList.GetBuffIcon(buffId)) end)
                end
                icon:Show(true)
                textLeft = 28
            end
        end

        local idLabel = helpers.createLabel('cbtBuffSearchId_' .. i, row, tostring(buffId), textLeft, 2, 14)
        idLabel:SetExtent(64, 20)
        idLabel:Show(true)

        local nameLabel = helpers.createLabel('cbtBuffSearchName_' .. i, row, name, textLeft + 66, 2, 14)
        nameLabel:SetExtent(280, 20)
        nameLabel:Show(true)

        local addButton = helpers.createButton('cbtBuffSearchAdd_' .. i, row, 'Add', 385, 0)
        addButton:SetExtent(95, 20)
        addButton:Show(true)
        addButton:SetHandler("OnClick", function()
            if not onAddCallback then return end
            local ok, message = onAddCallback(buffId)
            setStatus((message or (ok and "Added" or "Not added")) .. " — " .. name, not ok)
        end)

        table.insert(resultWidgets, row)
        yOffset = yOffset + 28
    end
end

-- ----- Создание окна -----

function createSearchWindowUI()
    searchWindow = api.Interface:CreateWindow("CooldawnBuffTrackerSearch", "Buff Search", 540, 500)
    searchWindow:AddAnchor("CENTER", 'UIParent', 0, 0)
    searchWindow:SetHandler("OnCloseByEsc", function() closeBuffSearchWindow() end)
    function searchWindow:OnClose() closeBuffSearchWindow() end

    -- Фон окна
    local background = searchWindow:CreateColorDrawable(0.1, 0.1, 0.1, 0.95, "background")
    background:AddAnchor("TOPLEFT", searchWindow, 0, 0)
    background:AddAnchor("BOTTOMRIGHT", searchWindow, 0, 0)

    -- Поле поиска
    local searchLabel = helpers.createLabel('cbtBuffSearchLabel', searchWindow, 'Search buff:', 15, 28, 15)
    searchLabel:SetWidth(110)
    searchLabel:Show(true)

    local searchInput = helpers.createEdit('cbtBuffSearchInput', searchWindow, "", 125, 26)
    searchInput:SetWidth(250)
    searchInput:SetMaxTextLength(40)
    searchInput:Show(true)
    controls.searchInput = searchInput

    local searchButton = helpers.createButton('cbtBuffSearchBtn', searchWindow, 'Search', 390, 22)
    searchButton:SetExtent(125, 26)
    searchButton:Show(true)
    searchButton:SetHandler("OnClick", function()
        performSearch(controls.searchInput:GetText())
    end)
    controls.searchButton = searchButton

    -- Подсказка
    local hint = helpers.createLabel('cbtBuffSearchHint', searchWindow,
        'Digits = search by ID, letters = search by name', 15, 58, 13)
    hint:SetWidth(510)
    hint:Show(true)
    hint.style:SetColor(0.7, 0.7, 0.7, 1)

    -- Заголовок списка
    local listHeader = helpers.createLabel('cbtBuffSearchListHeader', searchWindow, 'Results:', 15, 86, 16)
    listHeader:SetWidth(510)
    listHeader:Show(true)

    -- Контейнер списка
    local listContainer = api.Interface:CreateWidget('window', 'cbtBuffSearchListContainer', searchWindow)
    listContainer:SetExtent(510, 270)
    listContainer:RemoveAllAnchors()
    listContainer:AddAnchor("TOPLEFT", searchWindow, 15, 112)
    listContainer:Show(true)
    listContainer:Clickable(true)
    if listContainer.EnableScissor then
        listContainer:EnableScissor(true)
    end

    local listBorder = listContainer:CreateNinePartDrawable("ui/chat_option.dds", "artwork")
    listBorder:SetCoords(0, 0, 27, 16)
    listBorder:SetInset(9, 8, 9, 7)
    listBorder:AddAnchor("TOPLEFT", listContainer, -1, -1)
    listBorder:AddAnchor("BOTTOMRIGHT", listContainer, 1, 1)

    local listBg = listContainer:CreateColorDrawable(0.92, 0.92, 0.92, 1, "background")
    listBg:AddAnchor("TOPLEFT", listContainer, 0, 0)
    listBg:AddAnchor("BOTTOMRIGHT", listContainer, 0, 0)

    controls.listContainer = listContainer

    -- Пагинация (внизу контейнера)
    local prevButton = helpers.createButton('cbtBuffSearchPrevBtn', listContainer, '<', 0, 0)
    prevButton:SetExtent(30, 25)
    prevButton:RemoveAllAnchors()
    prevButton:AddAnchor("BOTTOMLEFT", listContainer, 10, -5)
    prevButton:SetHandler("OnClick", function()
        if resultPage > 1 then
            resultPage = resultPage - 1
            updateResultList()
        end
    end)
    prevButton:Show(true)
    controls.prevButton = prevButton

    local pageIndicator = helpers.createLabel('cbtBuffSearchPageIndicator', listContainer, "1/1", 0, 0, 14)
    pageIndicator:SetExtent(60, 25)
    pageIndicator:RemoveAllAnchors()
    pageIndicator:AddAnchor("LEFT", prevButton, "RIGHT", 5, 0)
    pageIndicator.style:SetAlign(ALIGN.CENTER)
    pageIndicator:Show(true)
    controls.pageIndicator = pageIndicator

    local nextButton = helpers.createButton('cbtBuffSearchNextBtn', listContainer, '>', 0, 0)
    nextButton:SetExtent(30, 25)
    nextButton:RemoveAllAnchors()
    nextButton:AddAnchor("LEFT", pageIndicator, "RIGHT", 5, 0)
    nextButton:SetHandler("OnClick", function()
        local totalPages = math.max(1, math.ceil(#currentResults / resultsPerPage))
        if resultPage < totalPages then
            resultPage = resultPage + 1
            updateResultList()
        end
    end)
    nextButton:Show(true)
    controls.nextButton = nextButton

    -- Статус
    local statusLabel = helpers.createLabel('cbtBuffSearchStatus', searchWindow, '', 15, 418, 14)
    statusLabel:SetWidth(510)
    statusLabel:Show(true)
    controls.statusLabel = statusLabel

    -- Кнопка закрытия
    local closeButton = helpers.createButton('cbtBuffSearchCloseBtn', searchWindow, 'Close', 0, 0)
    closeButton:SetExtent(150, 30)
    closeButton:RemoveAllAnchors()
    closeButton:AddAnchor("BOTTOM", searchWindow, 0, -15)
    closeButton:SetHandler("OnClick", function() closeBuffSearchWindow() end)
    closeButton:Show(true)
    controls.closeButton = closeButton
end

-- ----- Публичные функции -----

function openBuffSearchWindow(addCallback)
    onAddCallback = addCallback

    -- Поведение-переключатель: если окно открыто — закрываем
    if searchWindow and searchWindow:IsVisible() then
        closeBuffSearchWindow()
        return
    end

    if not searchWindow then
        createSearchWindowUI()
    end

    -- Сброс состояния
    if controls.searchInput then controls.searchInput:SetText("") end
    currentResults = {}
    resultPage = 1
    setStatus("Enter buff ID digits or a name fragment", false)
    updateResultList()
    searchWindow:Show(true)
end

function closeBuffSearchWindow()
    if searchWindow then
        searchWindow:Show(false)
    end
end

return {
    openBuffSearchWindow = openBuffSearchWindow,
    closeBuffSearchWindow = closeBuffSearchWindow
}
