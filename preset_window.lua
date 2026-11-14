-- preset_window.lua
-- Окно управления пресетами настроек CooldawnBuffTracker.
-- Пресет хранит полную раскладку (позиция/размер/цвета/баффы) для трёх типов
-- юнитов. Сами операции с пресетами реализованы в helpers.lua, здесь только UI.
local api = require("api")
local helpers = require('CooldawnBuffTracker/helpers')
local CbtWindow = require('CooldawnBuffTracker/util/cbt_window')

local presetWindow = nil
local presetControls = {}
local presetListWidgets = {}
local presetListPage = 1
local presetsPerPage = 7

-- Предварительное объявление локальных функций (Lua 5.1 требует порядка)
local openPresetWindow, closePresetWindow
local createPresetWindowUI, updatePresetList, updateActivePresetLabel
local showError, hideError

-- Убираем пробелы по краям имени пресета
local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- Лениво обновляем открытое окно настроек (избегаем циклического require)
local function refreshSettingsPage()
    local ok, settingsPage = pcall(require, "CooldawnBuffTracker/settings_page")
    if ok and settingsPage and settingsPage.refreshFromExternal then
        pcall(settingsPage.refreshFromExternal)
    end
end

-- Показать / скрыть панель ошибок
showError = function(message)
    if presetControls.errorLabel then
        presetControls.errorLabel:SetText(tostring(message or ""))
    end
    if presetControls.errorPanel then
        presetControls.errorPanel:Show(true)
    end
end

hideError = function()
    if presetControls.errorPanel then
        presetControls.errorPanel:Show(false)
    end
end

-- Обновить надпись об активном пресете
updateActivePresetLabel = function()
    if not presetControls.activeLabel then return end
    local active = helpers.getActivePresetName()
    if active and active ~= "" then
        presetControls.activeLabel:SetText("Active preset: " .. active)
        presetControls.activeLabel.style:SetColor(0.2, 1, 0.2, 1)
    else
        presetControls.activeLabel:SetText("Active preset: None")
        presetControls.activeLabel.style:SetColor(0.87, 0.69, 0, 1)
    end
end

-- ----- Обработчики действий -----

local function onSaveClicked()
    if not presetControls.nameInput then return end

    local name = trim(presetControls.nameInput:GetText())
    if name == "" then
        showError("Preset name cannot be empty")
        return
    end

    -- Пресет с таким именем уже существует
    if helpers.getPreset(name) then
        showError("Preset already exists: " .. name)
        return
    end

    helpers.savePresetFromCurrent(name)
    presetControls.nameInput:SetText("")
    hideError()

    -- Перейти на последнюю страницу, чтобы показать новый пресет
    local names = helpers.getPresetNames()
    presetListPage = math.max(1, math.ceil(#names / presetsPerPage))

    updateActivePresetLabel()
    updatePresetList()
    refreshSettingsPage()
end

local function onLoadClicked(presetName)
    local ok, err = helpers.loadPreset(presetName)
    if not ok then
        showError(err or "Failed to load preset")
        return
    end

    hideError()

    -- Применяем пресет: пересобираем список баффов и канвасы.
    -- ВАЖНО: НЕ вызываем helpers.updateSettings() — она перезаписывает posX/posY
    -- текущей позицией канваса и затёрла бы позицию из пресета. Позиция, размер
    -- и набор баффов применятся из настроек этим событием и на ближайшем кадре
    -- (OnUpdate -> updateBuffIcons).
    api:Emit("ADDON_CBT_BUFFS_CHANGED")
    refreshSettingsPage()

    updateActivePresetLabel()
    updatePresetList()
end

local function onDeleteClicked(presetName)
    local ok, err = helpers.deletePreset(presetName)
    if not ok then
        showError(err or "Failed to delete preset")
        return
    end

    hideError()
    updateActivePresetLabel()
    updatePresetList()
    refreshSettingsPage()
end

-- ----- Построение списка пресетов -----

updatePresetList = function()
    -- Очищаем ранее созданные элементы списка
    for _, widget in ipairs(presetListWidgets) do
        if widget then
            widget:Show(false)
            widget:RemoveAllAnchors()
        end
    end
    presetListWidgets = {}

    local container = presetControls.listContainer
    if not container then return end

    local names = helpers.getPresetNames()
    local activeName = helpers.getActivePresetName()

    -- Пагинация
    local totalPages = math.max(1, math.ceil(#names / presetsPerPage))
    if presetListPage > totalPages then presetListPage = totalPages end
    if presetListPage < 1 then presetListPage = 1 end

    if presetControls.pageIndicator then
        presetControls.pageIndicator:SetText(presetListPage .. "/" .. totalPages)
    end

    -- Пустой список
    if #names == 0 then
        local emptyLabel = helpers.createLabel('cbtPresetEmpty', container, "No presets saved", 0, 0, 16)
        emptyLabel:SetWidth(470)
        emptyLabel:RemoveAllAnchors()
        emptyLabel:AddAnchor("TOP", container, 0, 20)
        emptyLabel.style:SetAlign(ALIGN.CENTER)
        emptyLabel:Show(true)
        table.insert(presetListWidgets, emptyLabel)
        return
    end

    local startIndex = (presetListPage - 1) * presetsPerPage + 1
    local endIndex = math.min(startIndex + presetsPerPage - 1, #names)

    local yOffset = 8
    for i = startIndex, endIndex do
        local presetName = names[i]
        local isActive = (presetName == activeName)

        local row = api.Interface:CreateWidget('window', 'cbtPresetRow_' .. i, container)
        row:SetExtent(470, 22)
        row:RemoveAllAnchors()
        row:AddAnchor("TOPLEFT", container, 10, yOffset)
        row:Show(true)
        CbtWindow.TooltipDynamic(row, function()
            return "Preset " .. tostring(presetName) .. (isActive and " (active)" or "")
                .. ": Load applies its layout to all units, Delete removes it."
        end)

        -- Имя пресета (со звёздочкой, если активен)
        local displayName = (isActive and "* " or "") .. presetName
        local nameLabel = helpers.createLabel('cbtPresetRowName_' .. i, row, displayName, 0, 2, 14)
        nameLabel:SetExtent(250, 20)
        nameLabel:Show(true)

        -- Кнопка загрузки
        local loadButton = helpers.createButton('cbtPresetLoadBtn_' .. i, row, isActive and "Active" or "Load", 260, 0)
        loadButton:SetExtent(90, 20)
        loadButton:Show(true)
        CbtWindow.TooltipDynamic(loadButton, function()
            return isActive and ("Re-apply the active preset " .. tostring(presetName) .. ".")
                or ("Load preset " .. tostring(presetName) .. ": position, size, colours and tracked entries.")
        end)
        loadButton:SetHandler("OnClick", function()
            onLoadClicked(presetName)
        end)

        -- Кнопка удаления
        local deleteButton = helpers.createButton('cbtPresetDelBtn_' .. i, row, 'Delete', 360, 0)
        deleteButton:SetExtent(90, 20)
        deleteButton:Show(true)
        CbtWindow.TooltipDynamic(deleteButton, function()
            return "Delete preset " .. tostring(presetName) .. ". Cannot be undone."
        end)
        deleteButton:SetHandler("OnClick", function()
            onDeleteClicked(presetName)
        end)

        table.insert(presetListWidgets, row)
        yOffset = yOffset + 26
    end
end

-- ----- Создание окна -----

createPresetWindowUI = function()
    presetWindow = CbtWindow.Create("CooldawnBuffTrackerPresets", "Presets", 520, 470, closePresetWindow)
    if not presetWindow then return end

    -- Надпись об активном пресете
    local activeLabel = helpers.createLabel('cbtPresetActive', presetWindow, 'Active preset: None', 15, 38, 16)
    activeLabel:SetWidth(490)
    activeLabel:Show(true)
    CbtWindow.Tooltip(activeLabel, "Preset currently applied to all three units.")
    presetControls.activeLabel = activeLabel

    -- Секция: сохранить текущие настройки как новый пресет
    local nameLabel = helpers.createLabel('cbtPresetNameLabel', presetWindow, 'New preset name:', 15, 65, 15)
    nameLabel:SetWidth(140)
    nameLabel:Show(true)

    local nameInput = helpers.createEdit('cbtPresetNameInput', presetWindow, "", 160, 63)
    nameInput:SetWidth(200)
    nameInput:SetMaxTextLength(40)
    CbtWindow.Tooltip(nameInput, "Name for the new preset, up to 40 characters. Must be unique.")
    nameInput:Show(true)
    presetControls.nameInput = nameInput

    local saveButton = helpers.createButton('cbtPresetSaveBtn', presetWindow, 'Save current', 375, 59)
    saveButton:SetExtent(125, 26)
    saveButton:Show(true)
    CbtWindow.Tooltip(saveButton,
        "Save the current layout of all units (position, size, colours, grid, tracked entries) as a preset.")
    saveButton:SetHandler("OnClick", onSaveClicked)
    presetControls.saveButton = saveButton

    -- Заголовок списка
    local listHeader = helpers.createLabel('cbtPresetListHeader', presetWindow, 'Saved presets:', 15, 104, 16)
    listHeader:SetWidth(490)
    listHeader:Show(true)

    -- Контейнер списка
    local listContainer = api.Interface:CreateWidget('window', 'cbtPresetListContainer', presetWindow)
    listContainer:SetExtent(490, 235)
    listContainer:RemoveAllAnchors()
    listContainer:AddAnchor("TOPLEFT", presetWindow, 15, 132)
    listContainer:Show(true)
    listContainer:Clickable(true)
    if listContainer.EnableScissor then
        listContainer:EnableScissor(true)
    end

    -- Рамка контейнера
    local listBorder = listContainer:CreateNinePartDrawable("ui/chat_option.dds", "artwork")
    listBorder:SetCoords(0, 0, 27, 16)
    listBorder:SetInset(9, 8, 9, 7)
    listBorder:SetColor(0.28, 0.30, 0.34, 1)
    listBorder:AddAnchor("TOPLEFT", listContainer, -1, -1)
    listBorder:AddAnchor("BOTTOMRIGHT", listContainer, 1, 1)

    -- Фон контейнера
    local listBg = listContainer:CreateColorDrawable(0.10, 0.11, 0.13, 0.96, "background")
    listBg:AddAnchor("TOPLEFT", listContainer, 0, 0)
    listBg:AddAnchor("BOTTOMRIGHT", listContainer, 0, 0)

    presetControls.listContainer = listContainer

    -- Пагинация (внизу контейнера)
    local prevButton = helpers.createButton('cbtPresetPrevBtn', listContainer, '<', 0, 0)
    prevButton:SetExtent(30, 25)
    prevButton:RemoveAllAnchors()
    prevButton:AddAnchor("BOTTOMLEFT", listContainer, 10, -5)
    CbtWindow.Tooltip(prevButton, "Previous page of presets.")
    prevButton:SetHandler("OnClick", function()
        if presetListPage > 1 then
            presetListPage = presetListPage - 1
            updatePresetList()
        end
    end)
    prevButton:Show(true)
    presetControls.prevButton = prevButton

    local pageIndicator = helpers.createLabel('cbtPresetPageIndicator', listContainer, "1/1", 0, 0, 14)
    pageIndicator:SetExtent(50, 25)
    pageIndicator:RemoveAllAnchors()
    pageIndicator:AddAnchor("LEFT", prevButton, "RIGHT", 5, 0)
    pageIndicator.style:SetAlign(ALIGN.CENTER)
    pageIndicator:Show(true)
    CbtWindow.TooltipDynamic(pageIndicator, function(self)
        return "Page " .. tostring(self:GetText() or "1/1") .. " - 7 presets per page."
    end)
    presetControls.pageIndicator = pageIndicator

    local nextButton = helpers.createButton('cbtPresetNextBtn', listContainer, '>', 0, 0)
    nextButton:SetExtent(30, 25)
    nextButton:RemoveAllAnchors()
    nextButton:AddAnchor("LEFT", pageIndicator, "RIGHT", 5, 0)
    CbtWindow.Tooltip(nextButton, "Next page of presets.")
    nextButton:SetHandler("OnClick", function()
        local names = helpers.getPresetNames()
        local totalPages = math.max(1, math.ceil(#names / presetsPerPage))
        if presetListPage < totalPages then
            presetListPage = presetListPage + 1
            updatePresetList()
        end
    end)
    nextButton:Show(true)
    presetControls.nextButton = nextButton

    -- Панель ошибок
    local errorPanel = api.Interface:CreateWidget('window', 'cbtPresetErrorPanel', presetWindow)
    errorPanel:SetExtent(490, 25)
    errorPanel:RemoveAllAnchors()
    errorPanel:AddAnchor("TOPLEFT", presetWindow, 15, 382)

    local errorBorder = errorPanel:CreateNinePartDrawable("ui/chat_option.dds", "artwork")
    errorBorder:SetCoords(0, 0, 27, 16)
    errorBorder:SetInset(0, 8, 0, 7)
    errorBorder:AddAnchor("TOPLEFT", errorPanel, -1, -1)
    errorBorder:AddAnchor("BOTTOMRIGHT", errorPanel, 1, 1)

    local errorBg = errorPanel:CreateColorDrawable(0.10, 0.11, 0.13, 0.96, "background")
    errorBg:AddAnchor("TOPLEFT", errorPanel, 0, 0)
    errorBg:AddAnchor("BOTTOMRIGHT", errorPanel, 0, 0)

    local errorLabel = helpers.createLabel('cbtPresetErrorLabel', errorPanel, '', 5, 5, 14)
    errorLabel:SetExtent(480, 20)
    errorLabel.style:SetColor(0.95, 0.45, 0.45, 1)
    errorLabel:Show(true)
    presetControls.errorLabel = errorLabel
    presetControls.errorPanel = errorPanel
    errorPanel:Show(false)

end

-- ----- Публичные функции -----

openPresetWindow = function()
    -- Поведение-переключатель: если окно открыто — закрываем
    if presetWindow and presetWindow:IsVisible() then
        closePresetWindow()
        return
    end

    if not presetWindow then
        createPresetWindowUI()
    end

    hideError()
    updateActivePresetLabel()
    updatePresetList()
    presetWindow:Show(true)
end

closePresetWindow = function()
    if presetWindow then
        presetWindow:Show(false)
    end
end

return {
    openPresetWindow = openPresetWindow,
    closePresetWindow = closePresetWindow
}
