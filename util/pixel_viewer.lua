-- Модуль для отображения окна поддержки разработчика
local api = require("api")
local helpers = require("CooldawnBuffTracker/helpers")
local CbtWindow = require("CooldawnBuffTracker/util/cbt_window")
local locale = require("CooldawnBuffTracker/locale")
local L = locale.L

-- Переменная для хранения ссылки на окно
local supportWindow = nil

-- USDT TRC20 адрес для донатов
local USDT_ADDRESS = "TCXVaGQLMKQMNykji9zBCkM2CBKhaNHLkX"

-- EthereumX (ETX) адрес для донатов
local ETX_ADDRESS = "0xe192951a6291030ce075f24D74e964891afA8958"

-- USDT TON адрес для донатов
local USDT_TON_ADDRESS = "UQCMLDPT21xIfpE2IiQEa5Ws0dsPV65pOlPPAovzXkYdWrQd"

-- USDT SOL адрес для донатов
local USDT_SOL_ADDRESS = "7svDzftRPEW9TxqAY5Ub7EjYL5ACXQh6MzCrxnXFnfge"

-- USDT ERC20 адрес для донатов
local USDT_ERC20_ADDRESS = "0xe192951a6291030ce075f24D74e964891afA8958"

-- Функция для открытия окна поддержки
local function openPixelWindow()
    -- Если окно уже открыто, закрываем и выходим
    if supportWindow and supportWindow:IsVisible() then
        supportWindow:Show(false)
        supportWindow = nil
        return
    end
    
    -- Создаем окно для отображения
    supportWindow = CbtWindow.Create("CooldawnBuffTrackerSupport",
                                     "Support the Addon Developer", 450, 500,
                                     function()
                                         if supportWindow then
                                             supportWindow:Show(false)
                                             supportWindow = nil
                                         end
                                     end)
    if not supportWindow then return end
    
    -- Добавляем заголовок с описанием
    local titleLabel = api.Interface:CreateWidget('label', 'titleLabel', supportWindow)
    titleLabel:SetExtent(400, 30)
    titleLabel:AddAnchor("TOP", supportWindow, 0, 50)
    titleLabel:SetText(L("Donate USDT TRC20:"))
    titleLabel.style:SetFontSize(20)
    titleLabel.style:SetColor(0.2, 0.9, 0.2, 1)  -- Green color for better visibility
    titleLabel.style:SetAlign(ALIGN.CENTER)
    
    -- Создаем текстовое поле с адресом USDT
    local addressEdit = W_CTRL.CreateEdit("usdtAddressEdit", supportWindow)
    addressEdit:SetExtent(400, 30)
    addressEdit:AddAnchor("TOP", titleLabel, 0, 40)
    addressEdit:SetText(USDT_ADDRESS)
    addressEdit.style:SetColor(0, 0, 0, 1)
    addressEdit.style:SetAlign(ALIGN.CENTER)
    addressEdit.style:SetFontSize(14)
    CbtWindow.StyleEdit(addressEdit)
    CbtWindow.Tooltip(addressEdit, "Donation address. Click the field, select it and copy with Ctrl+C.")

    -- Добавляем заголовок для USDT TON
    local tonTitleLabel = api.Interface:CreateWidget('label', 'tonTitleLabel', supportWindow)
    tonTitleLabel:SetExtent(400, 30)
    tonTitleLabel:AddAnchor("TOP", addressEdit, 0, 30)
    tonTitleLabel:SetText(L("Donate USDT TON:"))
    tonTitleLabel.style:SetFontSize(20)
    tonTitleLabel.style:SetColor(0.2, 0.9, 0.2, 1)
    tonTitleLabel.style:SetAlign(ALIGN.CENTER)

    -- Создаем текстовое поле с адресом USDT TON
    local tonAddressEdit = W_CTRL.CreateEdit("tonAddressEdit", supportWindow)
    tonAddressEdit:SetExtent(400, 30)
    tonAddressEdit:AddAnchor("TOP", tonTitleLabel, 0, 40)
    tonAddressEdit:SetText(USDT_TON_ADDRESS)
    tonAddressEdit.style:SetColor(0, 0, 0, 1)
    tonAddressEdit.style:SetAlign(ALIGN.CENTER)
    tonAddressEdit.style:SetFontSize(14)
    CbtWindow.StyleEdit(tonAddressEdit)
    CbtWindow.Tooltip(tonAddressEdit, "Donation address. Click the field, select it and copy with Ctrl+C.")

    -- Добавляем заголовок для USDT SOL
    local solTitleLabel = api.Interface:CreateWidget('label', 'solTitleLabel', supportWindow)
    solTitleLabel:SetExtent(400, 30)
    solTitleLabel:AddAnchor("TOP", tonAddressEdit, 0, 30)
    solTitleLabel:SetText(L("Donate USDT SOL:"))
    solTitleLabel.style:SetFontSize(20)
    solTitleLabel.style:SetColor(0.2, 0.9, 0.2, 1)
    solTitleLabel.style:SetAlign(ALIGN.CENTER)

    -- Создаем текстовое поле с адресом USDT SOL
    local solAddressEdit = W_CTRL.CreateEdit("solAddressEdit", supportWindow)
    solAddressEdit:SetExtent(400, 30)
    solAddressEdit:AddAnchor("TOP", solTitleLabel, 0, 40)
    solAddressEdit:SetText(USDT_SOL_ADDRESS)
    solAddressEdit.style:SetColor(0, 0, 0, 1)
    solAddressEdit.style:SetAlign(ALIGN.CENTER)
    solAddressEdit.style:SetFontSize(14)
    CbtWindow.StyleEdit(solAddressEdit)
    CbtWindow.Tooltip(solAddressEdit, "Donation address. Click the field, select it and copy with Ctrl+C.")

    -- Добавляем заголовок для USDT ERC20
    local erc20TitleLabel = api.Interface:CreateWidget('label', 'erc20TitleLabel', supportWindow)
    erc20TitleLabel:SetExtent(400, 30)
    erc20TitleLabel:AddAnchor("TOP", solAddressEdit, 0, 30)
    erc20TitleLabel:SetText(L("Donate USDT ERC20:"))
    erc20TitleLabel.style:SetFontSize(20)
    erc20TitleLabel.style:SetColor(0.2, 0.9, 0.2, 1)
    erc20TitleLabel.style:SetAlign(ALIGN.CENTER)

    -- Создаем текстовое поле с адресом USDT ERC20
    local erc20AddressEdit = W_CTRL.CreateEdit("erc20AddressEdit", supportWindow)
    erc20AddressEdit:SetExtent(400, 30)
    erc20AddressEdit:AddAnchor("TOP", erc20TitleLabel, 0, 40)
    erc20AddressEdit:SetText(USDT_ERC20_ADDRESS)
    erc20AddressEdit.style:SetColor(0, 0, 0, 1)
    erc20AddressEdit.style:SetAlign(ALIGN.CENTER)
    erc20AddressEdit.style:SetFontSize(14)
    CbtWindow.StyleEdit(erc20AddressEdit)
    CbtWindow.Tooltip(erc20AddressEdit, "Donation address. Click the field, select it and copy with Ctrl+C.")

    -- Добавляем заголовок для EthereumX (ETX)
    local etxTitleLabel = api.Interface:CreateWidget('label', 'etxTitleLabel', supportWindow)
    etxTitleLabel:SetExtent(400, 30)
    etxTitleLabel:AddAnchor("TOP", erc20AddressEdit, 0, 30)
    etxTitleLabel:SetText(L("Donate EthereumX (ETX):"))
    etxTitleLabel.style:SetFontSize(20)
    etxTitleLabel.style:SetColor(0.2, 0.9, 0.2, 1)
    etxTitleLabel.style:SetAlign(ALIGN.CENTER)

    -- Создаем текстовое поле с адресом ETX
    local etxAddressEdit = W_CTRL.CreateEdit("etxAddressEdit", supportWindow)
    etxAddressEdit:SetExtent(400, 30)
    etxAddressEdit:AddAnchor("TOP", etxTitleLabel, 0, 40)
    etxAddressEdit:SetText(ETX_ADDRESS)
    etxAddressEdit.style:SetColor(0, 0, 0, 1)
    etxAddressEdit.style:SetAlign(ALIGN.CENTER)
    etxAddressEdit.style:SetFontSize(14)
    CbtWindow.StyleEdit(etxAddressEdit)
    CbtWindow.Tooltip(etxAddressEdit, "Donation address. Click the field, select it and copy with Ctrl+C.")

    -- Добавляем подсказку
    local hintLabel = api.Interface:CreateWidget('label', 'hintLabel', supportWindow)
    hintLabel:SetExtent(400, 25)
    hintLabel:AddAnchor("TOP", etxAddressEdit, 0, 30)
    hintLabel:SetText(L("Select address above and copy it manually (Ctrl+C)"))
    hintLabel.style:SetFontSize(12)
    hintLabel.style:SetColor(0.7, 0.7, 0.7, 1)
    hintLabel.style:SetAlign(ALIGN.CENTER)

    -- Добавляем благодарность
    local thanksLabel = api.Interface:CreateWidget('label', 'thanksLabel', supportWindow)
    thanksLabel:SetExtent(400, 25)
    thanksLabel:AddAnchor("TOP", hintLabel, 0, 30)
    thanksLabel:SetText(L("Thank you for supporting the development!"))
    thanksLabel.style:SetFontSize(14)
    thanksLabel.style:SetColor(0.4, 0.8, 0.4, 1)
    thanksLabel.style:SetAlign(ALIGN.CENTER)
    
    supportWindow:Show(true)
end

-- Функция для закрытия окна, если оно открыто
local function closePixelWindow()
    if supportWindow then
        supportWindow:Show(false)
        supportWindow = nil
    end
end

-- Функция для создания кнопки открытия окна поддержки
local function createSupportButton(parent)
    local supportButton = helpers.createButton("supportButton", parent, "Support", 10, 10)
    supportButton:SetExtent(100, 30)
    supportButton:AddAnchor("BOTTOMLEFT", parent, 10, 10)
    CbtWindow.Tooltip(supportButton, "Open the support window (donation addresses).")
    
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
