-- Модуль для отображения пиксельного изображения
local api = require("api")
local helpers = require("CooldawnBuffTracker/helpers")

-- Переменная для хранения ссылки на окно изображения
local pixelWindow = nil

local function drawQRCode(container, pixelData)
    local height = #pixelData
    local width = height > 0 and #pixelData[1] or 0
    
    -- Создаем и размещаем пакетами вертикальные прямоугольники
    for x = 1, width do
        local y = 1
        while y <= height do
            if pixelData[y][x] == 1 then
                local startY = y
                -- Находим высоту вертикального столбца
                while y <= height and pixelData[y][x] == 1 do
                    y = y + 1
                end
                
                local blackRect = container:CreateColorDrawable(0, 0, 0, 1, "overlay")
                blackRect:AddAnchor("TOPLEFT", container, x - 1, startY - 1)
                blackRect:SetExtent(1, y - startY)
            else
                y = y + 1
            end
        end
    end
end

-- Функция для открытия окна с пиксельной картинкой
local function openPixelWindow()
    -- Если окно уже открыто, закрываем и выходим
    if pixelWindow and pixelWindow:IsVisible() then
        pixelWindow:Show(false)
        pixelWindow = nil
        return
    end
    
    -- Загружаем данные пикселей
    local pixelData = require('CooldawnBuffTracker/util/pixel_data')
    local pixelData2 = require('CooldawnBuffTracker/util/pixel_data2')
    
    -- Создаем окно для отображения изображения
    pixelWindow = api.Interface:CreateWindow("CooldawnBuffTrackerPixelImage", 
                                         "Support the Addon Developer", 600, 600)
    
    pixelWindow:AddAnchor("CENTER", 'UIParent', 0, 0)
    pixelWindow:SetHandler("OnCloseByEsc", function() 
        pixelWindow:Show(false) 
        pixelWindow = nil
    end)
    
    -- Добавляем фон окна
    local background = pixelWindow:CreateColorDrawable(0.1, 0.1, 0.1, 0.9, "background")
    background:AddAnchor("TOPLEFT", pixelWindow, 0, 0)
    background:AddAnchor("BOTTOMRIGHT", pixelWindow, 0, 0)
    
    -- Создаем контейнер для Monero QR-кода
    local moneroContainer = api.Interface:CreateWidget('window', 'moneroContainer', pixelWindow)
    moneroContainer:SetExtent(300, 300)
    moneroContainer:AddAnchor("CENTER", pixelWindow, 28, -50)
    
    -- Создаем контейнер для СБП QR-кода
    local sbpContainer = api.Interface:CreateWidget('window', 'sbpContainer', pixelWindow)
    sbpContainer:SetExtent(300, 300)
    sbpContainer:AddAnchor("CENTER", pixelWindow, 28, 200)
    
    -- Отрисовываем QR-коды
    drawQRCode(moneroContainer, pixelData) 
    drawQRCode(sbpContainer, pixelData2)
    
    -- Добавляем текстовое описание для Monero
    local moneroLabel = api.Interface:CreateWidget('label', 'moneroLabel', moneroContainer)
    moneroLabel:SetExtent(280, 40)
    moneroLabel:AddAnchor("TOP", moneroContainer, -28, -20)
    moneroLabel:SetText("Donate with Monero")
    moneroLabel.style:SetFontSize(18)
    moneroLabel.style:SetColor(0, 0, 0, 1)
    moneroLabel.style:SetAlign(ALIGN.CENTER)
    
    -- Добавляем текстовое описание для СБП
    local sbpLabel = api.Interface:CreateWidget('label', 'sbpLabel', sbpContainer)
    sbpLabel:SetExtent(280, 40)
    sbpLabel:AddAnchor("TOP", sbpContainer, -28, -10)
    sbpLabel:SetText("Поддержать через СБП(Сбер)")
    sbpLabel.style:SetFontSize(18) 
    sbpLabel.style:SetColor(0, 0, 0, 1)
    sbpLabel.style:SetAlign(ALIGN.CENTER)
    
    pixelWindow:Show(true)
end

-- Функция для закрытия окна, если оно открыто
local function closePixelWindow()
    if pixelWindow then
        pixelWindow:Show(false)
        pixelWindow = nil
    end
end

-- Функция для создания кнопки открытия окна с QR-кодами
local function createSupportButton(parent)
    local supportButton = helpers.createButton("supportButton", parent, "Support", 10, 10)
    supportButton:SetExtent(100, 30)
    supportButton:AddAnchor("BOTTOMLEFT", parent, 10, 10)
    
    supportButton:SetHandler("OnClick", function()
        openPixelWindow()
    end)
    
    return supportButton
end

-- Экспортируем функции для использования в других модулях
return {
    openPixelWindow = openPixelWindow,
    closePixelWindow = closePixelWindow, 
    createSupportButton = createSupportButton
} 